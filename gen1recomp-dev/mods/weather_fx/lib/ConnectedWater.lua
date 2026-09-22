-- Weather FX 8.1.34: connected flat-world hydrosphere + voxel void-water authority.
--
-- Cartridge water classification stays authoritative for gameplay/shorelines.
-- This module observes the exact visible voxel maps, stitches adjacent water
-- cells across map connections into coherent bodies, drives wind/rain/tide/ice
-- state, and narrowly allows walking only on genuinely load-bearing ice.
-- No mountains, slopes, or orographic assumptions exist here: water is a
-- horizontal flat-world surface whose local character comes from body size,
-- exposure, weather, season and the moon.
local V = ...
local mod = V.mod
local W = {
  TILE=16,
  LOAD_BEARING=0.90,
  THAW_HOLD=0.91,
  MAX_RIPPLES=48,
  OBSERVATION_TTL=0.75,
  bodies={}, voidBodies={}, hostBodies={}, renderBodies={}, outerSea=nil, bodyByCell={}, bodyByMapCell={}, ripples={}, serial=0,
  observed=false, observationAge=1e9, player=nil, playerBody=nil,
  windX=1, windZ=0, windStrength=0, rain=0, snow=0, moonPhase=0, tidePhase=0,
  _hookInstalled=false, _topologyKey=nil, _mapWaterCache=setmetatable({}, {__mode="k"}), _hostTileShape=nil,
  _voxelWaterHost={id="unknown",outerRange=32768,voidRingWorld=96,drawWater=false},
  visualIce=0, visualTemp=6,
  _cellState={}, _cellStateCount=0, _persistSerial=0, MAX_STORED_CELLS=16384,
}

local floor,abs,max,min,sqrt,sin,cos,pi=math.floor,math.abs,math.max,math.min,math.sqrt,math.sin,math.cos,math.pi
local TAU=pi*2
-- These sibling modules are stable for this Weather FX instance. Resolve each
-- lazily and retain successful handles instead of paying protected require
-- overhead every hydrosphere tick. A missing dependency stays nil and is
-- retried later, preserving late-load/fail-open behavior.
local _Settings,_CelestialSim,_TimeOfDay,_WindEngine,_Microclimate
-- Gen1Recomp owns the player-facing VOID FILL option. Voxel Realism turns the
-- WATER choice into a synthetic 3-block apron around the CURRENT map. Keep this
-- engine handle separate from Weather FX modules so a late host load still
-- retries safely.
local _TileRenderer
local function tileRenderer()
  if _TileRenderer then return _TileRenderer end
  local ok,m=pcall(require,"src.render.TileRenderer")
  if ok and m then _TileRenderer=m;return m end
  return nil
end
local function cached(cur,name)
  if cur then return cur end
  local ok,m=pcall(V.require,name);if ok and m then return m end
  return nil
end
local function clamp(v,a,b) v=tonumber(v) or 0;if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function mapDims(map)
  if not map then return 0,0 end
  local w,h=tonumber(map.widthCells),tonumber(map.heightCells)
  if (not w or w<=0) and map.def then local q=tonumber(map.def.width);if q and q>0 then w=q*2 end end
  if (not h or h<=0) and map.def then local q=tonumber(map.def.height);if q and q>0 then h=q*2 end end
  return max(0,floor(w or 0)),max(0,floor(h or 0))
end
local function cellKey(x,z) return tostring(x)..":"..tostring(z) end
local function mapIdentity(map)
  if not map then return "nil" end
  local d=map.def
  return tostring(map.id or (d and (d.id or d.name)) or map)
end
local function identityKey(map,cx,cz) return mapIdentity(map)..":"..tostring(cx)..":"..tostring(cz) end
local function worldCell(ox,oz,cx,cz)
  -- Gen1Recomp neighbour offsets are exact world pixels. Round rather than
  -- truncating so negative connected maps stitch at the same seam as positive.
  local gx=floor(((tonumber(ox) or 0)+cx*W.TILE)/W.TILE + 0.5)
  local gz=floor(((tonumber(oz) or 0)+cz*W.TILE)/W.TILE + 0.5)
  return gx,gz
end

local function greedyRects(cells,tileSize)
  tileSize=tonumber(tileSize) or W.TILE
  local mask={};local n=0
  for _,c in ipairs(cells) do mask[cellKey(c.gx,c.gz)]=true end
  local used={};local rows={}
  for _,c in ipairs(cells) do rows[c.gz]=rows[c.gz] or {};rows[c.gz][#rows[c.gz]+1]=c.gx end
  local zs={};for z in pairs(rows) do zs[#zs+1]=z end;table.sort(zs)
  for _,z in ipairs(zs) do table.sort(rows[z]) end
  local out={}
  for _,z in ipairs(zs) do
    for _,x in ipairs(rows[z]) do
      local k=cellKey(x,z)
      if mask[k] and not used[k] then
        local x1=x
        while mask[cellKey(x1+1,z)] and not used[cellKey(x1+1,z)] do x1=x1+1 end
        local z1=z
        while true do
          local nz=z1+1;local ok=true
          for xx=x,x1 do local kk=cellKey(xx,nz);if not mask[kk] or used[kk] then ok=false;break end end
          if not ok then break end
          z1=nz
        end
        for zz=z,z1 do for xx=x,x1 do used[cellKey(xx,zz)]=true end end
        out[#out+1]={x0=x*tileSize,z0=z*tileSize,x1=(x1+1)*tileSize,z1=(z1+1)*tileSize,cells=(x1-x+1)*(z1-z+1)}
        n=n+1
      end
    end
  end
  return out
end
W._greedyRects=greedyRects

local function bodyMorphology(cells,touchesBoundary)
  local minx,maxx,minz,maxz=1e9,-1e9,1e9,-1e9
  local set={}
  for _,c in ipairs(cells) do
    minx,maxx=min(minx,c.gx),max(maxx,c.gx);minz,maxz=min(minz,c.gz),max(maxz,c.gz)
    set[cellKey(c.gx,c.gz)]=true
  end
  local w=max(1,maxx-minx+1);local d=max(1,maxz-minz+1);local short=min(w,d);local long=max(w,d)
  local area=max(1,#cells);local fill=area/(w*d);local aspect=long/max(1,short)
  local perimeter=0
  for _,c in ipairs(cells) do
    if not set[cellKey(c.gx-1,c.gz)] then perimeter=perimeter+1 end
    if not set[cellKey(c.gx+1,c.gz)] then perimeter=perimeter+1 end
    if not set[cellKey(c.gx,c.gz-1)] then perimeter=perimeter+1 end
    if not set[cellKey(c.gx,c.gz+1)] then perimeter=perimeter+1 end
  end
  local kind
  if aspect>=2.35 and short<=4 and area>=6 then kind="RIVER"
  elseif touchesBoundary and area>=64 and short>=4 then kind="SEA"
  elseif area>=24 or short>=4 then kind="LAKE"
  else kind="POND" end
  local flowX,flowZ=0,0
  if kind=="RIVER" then if w>=d then flowX=1 else flowZ=1 end end
  local rapidness=0
  if kind=="RIVER" then rapidness=clamp(0.34+(aspect-2.0)*0.12+(4-short)*0.12+(1-fill)*0.18,0.35,1) end
  return {kind=kind,widthCells=w,depthCells=d,aspect=aspect,fill=fill,perimeter=perimeter,flowX=flowX,flowZ=flowZ,rapidness=rapidness}
end
W._bodyMorphology=bodyMorphology

local function signature(cells)
  local keys={};for i,c in ipairs(cells) do keys[i]=c.identity or cellKey(c.gx,c.gz) end;table.sort(keys)
  return table.concat(keys,"|")
end
local function mapRevision(map)
  return tostring(map and (map.revision or map._revision or map.serial or map.version) or "")
end
local function cachedWaterCells(map)
  local w,h=mapDims(map);local rev=mapRevision(map);local q=W._mapWaterCache[map]
  if q and q.w==w and q.h==h and q.rev==rev then return q.cells,w,h end
  local cells={}
  if map and type(map.isWaterCell)=="function" then
    for cx=0,w-1 do for cz=0,h-1 do local ok,v=pcall(map.isWaterCell,map,cx,cz);if ok and v==true then cells[#cells+1]={cx=cx,cz=cz} end end end
  end
  W._mapWaterCache[map]={cells=cells,w=w,h=h,rev=rev};return cells,w,h
end
-- Publish only renderer capabilities, never host gameplay state. 8.1.39 uses
-- this to make VOID-water presentation host-agnostic: every supported voxel
-- renderer gets the same Weather FX sea, while a host that exposes a wider
-- background/underlay may publish its actual range. Unknown hosts retain the
-- conservative 32K horizon used by the established voxel lineage.
function W.setVoxelWaterHost(info)
  info=type(info)=="table" and info or {}
  local q=W._voxelWaterHost or {}
  q.id=tostring(info.id or q.id or "unknown")
  q.outerRange=max(2048,min(65536,tonumber(info.outerRange) or tonumber(q.outerRange) or 32768))
  q.voidRingWorld=max(W.TILE,min(512,tonumber(info.voidRingWorld) or tonumber(q.voidRingWorld) or 96))
  q.drawWater=info.drawWater==true
  q.worldUnderlay=info.worldUnderlay==true
  -- Renderer fingerprint, not a mod-id alias. Upstream Battle Art 1.10.x and
  -- Voxel Nexus both use BATTLE_ART_VOXEL_FORK; only the former lacks the
  -- _trainSource export while retaining the same structured wave clock/tables.
  q.publicBattleArtWater=info.publicBattleArtWater==true
  -- Voxel Nexus is capability-distinguished from upstream Battle Art by the
  -- structured _trainSource export. Its bundled WaterEngine can also add a
  -- model-space tide inside Water.draw; Weather FX uses this metadata only to
  -- neutralize that duplicate presentation transform during owned draws.
  q.voxelNexusWater=info.voxelNexusWater==true
  q.hostWaterModelTide=info.hostWaterModelTide==true
  W._voxelWaterHost=q
  -- Host capability changes are a presentation topology change. Rebuild the
  -- visual-only apron/outer sea on the next observation, but leave authored
  -- body thermodynamics/collision identities untouched.
  W._topologyKey=nil
  return q
end
function W.voxelWaterHost() return W._voxelWaterHost end

local function outdoorMapDef(def)
  if not def then return false end
  -- Engine modules are deliberately required at CALL time. Gen1 and Gen2 can
  -- install different src.world.Map tables during the same process, and a
  -- file-scope capture previously made Gold outdoor detection permanently use
  -- the Gen1 implementation.
  local ok,Map=pcall(require,"src.world.Map")
  if ok and Map and type(Map.isOutdoor)=="function" then
    local ok2,v=pcall(Map.isOutdoor,def);if ok2 then return v==true end
  end
  -- Fixture/older-engine fallback only. Test the semantic environment rather
  -- than requiring the Gen1 OVERWORLD tileset shape.
  if tostring(def.tileset or ""):upper()=="OVERWORLD" then return true end
  local e=tostring(def.environment or ""):upper()
  return e=="ROUTE" or e=="TOWN" or e=="OUTDOOR" or e=="CITY"
end
local function voidWaterMode(state)
  local map=state and state.map
  if not (map and map.def and outdoorMapDef(map.def)) then return false end
  local T=tileRenderer()
  return T and tostring(T.voidFill or "trees"):lower()=="water" or false
end
W._voidWaterMode=voidWaterMode
W._outdoorMapDef=outdoorMapDef

-- Dramatic Shape, Dramaless, Potato Voxel and the Battle-Art/Voxel-Nexus
-- lineage all derive their visible VOID FILL apron from the engine's three
-- 32px border blocks. Keep the default exact 96px semantic ring, but consume a
-- host-published value when a compatible renderer exposes one. This visual body
-- never enters bodyByCell, collision, Surf, freezing or humidity.
local DEFAULT_VOID_RING_WORLD=96
local DEFAULT_OUTER_VOID_RANGE=32768
local function voidRingWorld()
  local q=W._voxelWaterHost or {};return tonumber(q.voidRingWorld) or DEFAULT_VOID_RING_WORLD
end
local function voidRingCells() return max(1,floor(voidRingWorld()/W.TILE+0.5)) end
local function outerVoidRange()
  local q=W._voxelWaterHost or {};return tonumber(q.outerRange) or DEFAULT_OUTER_VOID_RANGE
end
local function voidWaterCells(state,regions)
  if not voidWaterMode(state) then return {} end
  local root=regions and regions[1]
  if not (root and root.map) then return {} end
  local w,h=mapDims(root.map);if w<=0 or h<=0 then return {} end
  local masks={}
  for i=2,#regions do
    local r=regions[i]
    if r and r.map and r.map.def then
      local rw,rh=mapDims(r.map)
      masks[#masks+1]={tonumber(r.ox) or 0,tonumber(r.oz) or 0,(tonumber(r.ox) or 0)+rw*W.TILE,(tonumber(r.oz) or 0)+rh*W.TILE}
    end
  end
  local function masked(x0,z0,x1,z1)
    for _,m in ipairs(masks) do
      if x1>m[1] and x0<m[3] and z1>m[2] and z0<m[4] then return true end
    end
    return false
  end
  local out={}
  local ringCells=voidRingCells()
  for gz=-ringCells,h+ringCells-1 do
    for gx=-ringCells,w+ringCells-1 do
      local inBody=gx>=0 and gz>=0 and gx<w and gz<h
      if not inBody then
        local x0,z0=gx*W.TILE,gz*W.TILE
        if not masked(x0,z0,x0+W.TILE,z0+W.TILE) then
          out[#out+1]={gx=gx,gz=gz,visualOnly=true,voidWater=true}
        end
      end
    end
  end
  return out
end
W._voidWaterCells=voidWaterCells

-- Current Voxel Nexus draws a much larger cosmetic WorldUnderlay beyond the
-- engine's authored three-border-block VOID FILL ring. The finite 96px apron
-- above remains the exact host-semantic replacement. This second descriptor is
-- only presentation metadata for ConnectedWater3D: it is deliberately NOT put
-- into bodyByCell/renderBodies, so it can never become Surf/collision/ice/
-- SnowPack/hydrology authority and cannot accidentally look like authored water
-- to gameplay consumers.
local function outerVoidSea(state,regions,topo)
  if not voidWaterMode(state) then return nil end
  local root=regions and regions[1]
  if not (root and root.map) then return nil end
  local w,h=mapDims(root.map);if w<=0 or h<=0 then return nil end
  local ringWorld=voidRingWorld()
  local holes={{x0=-ringWorld,z0=-ringWorld,x1=w*W.TILE+ringWorld,z1=h*W.TILE+ringWorld,inner=true}}
  for i=2,#regions do
    local r=regions[i]
    if r and r.map then
      local rw,rh=mapDims(r.map);local ox,oz=tonumber(r.ox) or 0,tonumber(r.oz) or 0
      holes[#holes+1]={x0=ox,z0=oz,x1=ox+rw*W.TILE,z1=oz+rh*W.TILE,map=true}
    end
  end
  return {id=-2,signature="__WEATHER_FX_OUTER_VOID_WATER__|"..mapIdentity(root.map).."|"..tostring(topo),
    visualOnly=true,voidWater=true,outerSea=true,kind="SEA",loadBearing=false,ice=0,temp=6,tide=0,wave=0,
    range=outerVoidRange(),innerRing=ringWorld,mapWidth=w*W.TILE,mapHeight=h*W.TILE,
    cx=w*W.TILE*.5,cz=h*W.TILE*.5,holes=holes,area=0,touchesBoundary=true}
end
W._outerVoidSea=outerVoidSea

local function topologyKey(regions,state)
  local t={}
  for i,r in ipairs(regions) do
    local _,w,h=cachedWaterCells(r.map);r.w,r.h=w,h
    t[i]=table.concat({mapIdentity(r.map),tostring(r.ox),tostring(r.oz),tostring(w),tostring(h),mapRevision(r.map)},"@")
  end
  t[#t+1]="void="..(voidWaterMode(state) and "water" or "native")
  t[#t+1]="hostTiles="..(W._hostTileShape and "1" or "0")
  local vh=W._voxelWaterHost or {}
  t[#t+1]="voxelWater="..tostring(vh.id or "unknown")..":"..tostring(vh.outerRange or DEFAULT_OUTER_VOID_RANGE)..":"..tostring(vh.voidRingWorld or DEFAULT_VOID_RING_WORLD)
    ..":"..(vh.voxelNexusWater and "nexus" or (vh.publicBattleArtWater and "public" or "generic"))
  return table.concat(t,"|")
end
-- Voxel Realism resolves presentation at 8x8 tile granularity while cartridge
-- collision water is 16x16-cell authority. A blocked cell can therefore still
-- contain authored water art that the host legitimately emits into its water
-- mesh. 8.1.35 only scanned map:isWaterCell(), so those exact tile fragments
-- could fall through to a legacy host-water appearance. Capture ONLY the extra
-- host-semantic water tiles here as presentation-only bodies; gameplay remains
-- exclusively on the 16px cartridge hydrology above.
local function hostVisualWaterBodies(regions,gameplayCells,tileShape)
  if not (tileShape and type(tileShape.forMap)=="function" and type(tileShape.at)=="function") then return {} end
  local covered8={}
  for _,c in ipairs(gameplayCells or {}) do
    local bx,bz=c.gx*2,c.gz*2
    covered8[cellKey(bx,bz)]=true;covered8[cellKey(bx+1,bz)]=true
    covered8[cellKey(bx,bz+1)]=true;covered8[cellKey(bx+1,bz+1)]=true
  end
  local tiles,by={},{}
  for _,r in ipairs(regions or {}) do
    local map=r.map;local w,h=mapDims(map)
    if map and w>0 and h>0 and type(map.tileAt)=="function" then
      local okS,shapes=pcall(tileShape.forMap,map)
      if okS and type(shapes)=="table" then
        for ty=0,h*2-1 do for tx=0,w*2-1 do
          local okT,tile=pcall(map.tileAt,map,tx,ty)
          if okT and tile~=nil then
            local okA,shape=pcall(tileShape.at,map,shapes,tile,tx,ty)
            if okA and type(shape)=="table" and tostring(shape.class or ""):lower()=="water" then
              local gx=floor(((tonumber(r.ox) or 0)+tx*8)/8+0.5)
              local gz=floor(((tonumber(r.oz) or 0)+ty*8)/8+0.5)
              local k=cellKey(gx,gz)
              if not covered8[k] and not by[k] then
                local c={gx=gx,gz=gz,map=map,tx=tx,tz=ty,region=r,identity=mapIdentity(map)..":tile:"..tx..":"..ty}
                by[k]=c;tiles[#tiles+1]=c
              end
            end
          end
        end end
      end
    end
  end
  local seen,bodies={},{}
  table.sort(tiles,function(a,b) return a.gz==b.gz and a.gx<b.gx or a.gz<b.gz end)
  for _,seed in ipairs(tiles) do
    local sk=cellKey(seed.gx,seed.gz)
    if not seen[sk] then
      local q={seed};seen[sk]=true;local qi=1;local cc={};local boundary=false
      while q[qi] do
        local c=q[qi];qi=qi+1;cc[#cc+1]=c
        local r=c.region;local w,h=mapDims(r and r.map)
        if c.tx==0 or c.tz==0 or c.tx==w*2-1 or c.tz==h*2-1 then boundary=true end
        local nn={{c.gx+1,c.gz},{c.gx-1,c.gz},{c.gx,c.gz+1},{c.gx,c.gz-1}}
        for _,pt in ipairs(nn) do local k=cellKey(pt[1],pt[2]);local nc=by[k];if nc and not seen[k] then seen[k]=true;q[#q+1]=nc end end
      end
      local minx,maxx,minz,maxz=1e9,-1e9,1e9,-1e9;local sx,sz=0,0
      for _,c in ipairs(cc) do minx,maxx=min(minx,c.gx),max(maxx,c.gx);minz,maxz=min(minz,c.gz),max(maxz,c.gz);sx=sx+c.gx*8+4;sz=sz+c.gz*8+4 end
      local tw,td=maxx-minx+1,maxz-minz+1;local short,long=min(tw,td),max(tw,td);local area16=#cc*0.25;local aspect=long/max(1,short)
      local kind=(aspect>=2.35 and short<=8 and #cc>=12 and "RIVER") or (boundary and #cc>=256 and "SEA") or (#cc>=96 and "LAKE") or "POND"
      local fx,fz=0,0;if kind=="RIVER" then if tw>=td then fx=1 else fz=1 end end
      local sig="__HOST_WATER_8PX__|"..signature(cc)
      bodies[#bodies+1]={id=-1000-#bodies,signature=sig,cells=cc,rects=greedyRects(cc,8),cellSize=8,area=area16,touchesBoundary=boundary,
        visualOnly=true,hostWater=true,ice=W.visualIce or 0,temp=W.visualTemp or 6,rippleClock=0,tide=0,wave=0,loadBearing=false,presentationFrozen=false,
        kind=kind,widthCells=tw*.5,depthCells=td*.5,aspect=aspect,fill=1,perimeter=0,flowX=fx,flowZ=fz,rapidness=(kind=="RIVER" and .55 or 0),cx=sx/#cc,cz=sz/#cc}
    end
  end
  return bodies
end
W._hostVisualWaterBodies=hostVisualWaterBodies

local function rememberBodies()
  W._persistSerial=W._persistSerial+1;local stamp=W._persistSerial
  for _,b in ipairs(W.bodies or {}) do
    for _,c in ipairs(b.cells or {}) do
      local k=c.identity or identityKey(c.map,c.cx,c.cz);local q=W._cellState[k]
      if not q then q={};W._cellState[k]=q;W._cellStateCount=W._cellStateCount+1 end
      q.ice,q.temp,q.stamp=b.ice,b.temp,stamp
    end
  end
  if W._cellStateCount>W.MAX_STORED_CELLS then
    local cutoff=stamp-12
    for k,q in pairs(W._cellState) do if W._cellStateCount<=W.MAX_STORED_CELLS then break end;if (q.stamp or 0)<cutoff then W._cellState[k]=nil;W._cellStateCount=W._cellStateCount-1 end end
  end
end
local function restoredCellState(cells)
  local ni,nt,n=0,0,0
  for _,c in ipairs(cells) do local q=W._cellState[c.identity];if q then ni=ni+(tonumber(q.ice) or 0);nt=nt+(tonumber(q.temp) or 6);n=n+1 end end
  if n>0 then return ni/n,nt/n end
end

local function regionList(state)
  local r={}
  if state and state.map then r[#r+1]={map=state.map,ox=0,oz=0,root=true} end
  for _,nb in ipairs(state and state.neighbors or {}) do
    if nb and nb.map then r[#r+1]={map=nb.map,ox=tonumber(nb.ox) or 0,oz=tonumber(nb.oy or nb.oz) or 0,root=false} end
  end
  return r
end

local function playerWorld(state)
  local p=state and state.player
  if not p then return nil end
  local x=tonumber(p.px or p.x);local z=tonumber(p.py or p.y or p.z)
  if x and z then return x+8,z+8,p end
  if tonumber(p.cellX) and tonumber(p.cellY) then return p.cellX*W.TILE+8,p.cellY*W.TILE+8,p end
end

function W.observeVoxel(state,hostTileShape)
  if hostTileShape and type(hostTileShape)=="table" then W._hostTileShape=hostTileShape end
  if type(state)~="table" or not state.map then W.observed=false;W.observationAge=1e9;return false end
  local regions=regionList(state);local topo=topologyKey(regions,state)
  if W.observed and W._topologyKey==topo then
    W.observationAge=0;W._state=state
    local px,pz,p=playerWorld(state);W.player=p;W.playerBody=(px and W.bodyAt(px,pz)) or nil
    return true
  end
  rememberBodies()
  local oldBySig={};local oldByCell={}
  for _,b in ipairs(W.bodies) do
    oldBySig[b.signature]=b
    for _,c in ipairs(b.cells or {}) do oldByCell[c.identity or cellKey(c.gx,c.gz)]=b end
  end
  local cells={}; local by={}
  for _,r in ipairs(regions) do
    local wc,mw,mh=cachedWaterCells(r.map);r.w,r.h=mw,mh
    for _,lc in ipairs(wc) do
      local cx,cz=lc.cx,lc.cz
      local gx,gz=worldCell(r.ox,r.oz,cx,cz);local k=cellKey(gx,gz)
      if not by[k] then
        local c={gx=gx,gz=gz,map=r.map,cx=cx,cz=cz,region=r,identity=identityKey(r.map,cx,cz)};by[k]=c;cells[#cells+1]=c
      end
    end
  end
  local seen={};local bodies={};local bodyBy={};local bodyByMap={}
  table.sort(cells,function(a,b) return a.gz==b.gz and a.gx<b.gx or a.gz<b.gz end)
  for _,seed in ipairs(cells) do
    local sk=cellKey(seed.gx,seed.gz)
    if not seen[sk] then
      local q={seed};seen[sk]=true;local qi=1;local cc={};local boundary=false
      while q[qi] do
        local c=q[qi];qi=qi+1;cc[#cc+1]=c
        local r=c.region
        if c.cx==0 or c.cz==0 or c.cx==r.w-1 or c.cz==r.h-1 then boundary=true end
        local nn={{c.gx+1,c.gz},{c.gx-1,c.gz},{c.gx,c.gz+1},{c.gx,c.gz-1}}
        for _,p in ipairs(nn) do local k=cellKey(p[1],p[2]);local nc=by[k];if nc and not seen[k] then seen[k]=true;q[#q+1]=nc end end
      end
      local sig=signature(cc);local prev=oldBySig[sig]
      if not prev then
        local counts={};local best,bestN=nil,0
        for _,c in ipairs(cc) do local q=oldByCell[c.identity or cellKey(c.gx,c.gz)];if q then counts[q]=(counts[q] or 0)+1;if counts[q]>bestN then best,bestN=q,counts[q] end end end
        prev=best
      end
      if not prev then W.serial=W.serial+1 end
      local savedIce,savedTemp=restoredCellState(cc);local morph=bodyMorphology(cc,boundary)
      local b={id=prev and prev.id or W.serial,signature=sig,cells=cc,rects=greedyRects(cc),area=#cc,touchesBoundary=boundary,
        ice=prev and prev.ice or savedIce or 0,temp=prev and prev.temp or savedTemp or 6,rippleClock=prev and prev.rippleClock or 0,
        tide=prev and prev.tide or 0,wave=prev and prev.wave or 0,loadBearing=prev and prev.loadBearing or false,
        kind=morph.kind,widthCells=morph.widthCells,depthCells=morph.depthCells,aspect=morph.aspect,fill=morph.fill,perimeter=morph.perimeter,
        flowX=morph.flowX,flowZ=morph.flowZ,rapidness=morph.rapidness}
      local sx,sz=0,0
      for _,c in ipairs(cc) do
        sx=sx+c.gx*W.TILE+8;sz=sz+c.gz*W.TILE+8;bodyBy[cellKey(c.gx,c.gz)]=b
        bodyByMap[c.identity or identityKey(c.map,c.cx,c.cz)]=b
      end
      b.cx,b.cz=sx/#cc,sz/#cc
      bodies[#bodies+1]=b
    end
  end
  W.bodies,W.bodyByCell,W.bodyByMapCell=bodies,bodyBy,bodyByMap
  local voidCells=voidWaterCells(state,regions);local voidBodies={}
  if #voidCells>0 then
    local sx,sz=0,0
    for _,c in ipairs(voidCells) do sx=sx+c.gx*W.TILE+8;sz=sz+c.gz*W.TILE+8 end
    local b={id=-1,signature="__WEATHER_FX_VOID_WATER__|"..mapIdentity(state.map).."|"..topo,cells=voidCells,rects=greedyRects(voidCells),area=#voidCells,
      touchesBoundary=true,visualOnly=true,voidWater=true,ice=0,temp=6,rippleClock=0,tide=0,wave=0,loadBearing=false,
      kind="SEA",widthCells=0,depthCells=0,aspect=1,fill=1,perimeter=0,flowX=0,flowZ=0,rapidness=0,cx=sx/#voidCells,cz=sz/#voidCells}
    voidBodies[1]=b
  end
  W.voidBodies=voidBodies
  W.outerSea=outerVoidSea(state,regions,topo)
  local hostBodies=hostVisualWaterBodies(regions,cells,W._hostTileShape)
  W.hostBodies=hostBodies
  local renderBodies={}
  for _,b in ipairs(bodies) do renderBodies[#renderBodies+1]=b end
  for _,b in ipairs(hostBodies) do renderBodies[#renderBodies+1]=b end
  for _,b in ipairs(voidBodies) do renderBodies[#renderBodies+1]=b end
  W.renderBodies=renderBodies
  W._topologyKey=topo;W.observed=true;W.observationAge=0;W._state=state
  local px,pz,p=playerWorld(state);W.player=p
  W.playerBody=(px and W.bodyAt(px,pz)) or nil
  return true
end

function W.bodyForMapCell(map,cx,cz)
  if not (map and cx~=nil and cz~=nil) then return nil end
  return W.bodyByMapCell and W.bodyByMapCell[identityKey(map,cx,cz)] or nil
end
function W.isLoadBearingMapCell(map,cx,cz)
  if not W.observed or W.observationAge>W.OBSERVATION_TTL then return false end
  local b=W.bodyForMapCell(map,cx,cz)
  return b~=nil and b.visualOnly~=true and b.loadBearing==true
end
function W.bodyAt(x,z)
  if not (x and z) then return nil end
  local gx=floor((tonumber(x) or 0)/W.TILE);local gz=floor((tonumber(z) or 0)/W.TILE)
  return W.bodyByCell[cellKey(gx,gz)]
end
function W.isWaterAt(x,z) return W.bodyAt(x,z)~=nil end
function W.iceFractionAt(x,z) local b=W.bodyAt(x,z);return b and b.ice or 0 end
function W.liquidFractionAt(x,z) local b=W.bodyAt(x,z);return b and (1-b.ice) or 0 end
function W.surfaceYAt(x,z) local b=W.bodyAt(x,z);return b and (-2+(tonumber(b.tide) or 0)) or nil end
local function presentationEnabled()
  _Settings=cached(_Settings,"Settings");local S=_Settings
  if not S then return true end
  if type(S.weatherFxWaterEnabled)=="function" then
    local ok2,v=pcall(S.weatherFxWaterEnabled);if ok2 then return v~=false end
  end
  return true
end
function W.isLoadBearingAt(x,z)
  -- ORIGINAL WATER must also restore original gameplay semantics. Otherwise a
  -- hidden frozen state could make visibly liquid native water walkable.
  if not presentationEnabled() then return false end
  if not W.observed or W.observationAge>W.OBSERVATION_TTL then return false end
  local b=W.bodyAt(x,z);return b and b.loadBearing==true or false
end
function W.liquidFractionNear(x,z,radius)
  -- Native/original water remains ordinary open water to Weather FX's local
  -- humidity/fog model while the connected hydrosphere presentation is off.
  if not presentationEnabled() then return 1 end
  radius=max(0,floor(tonumber(radius) or 2));local gx=floor((tonumber(x) or 0)/W.TILE);local gz=floor((tonumber(z) or 0)/W.TILE)
  local total,liquid=0,0
  for dz=-radius,radius do for dx=-radius,radius do local b=W.bodyByCell[cellKey(gx+dx,gz+dz)];if b then total=total+1;liquid=liquid+(1-b.ice) end end end
  if total==0 then return 1 end
  return liquid/total
end

local function weatherChannels(state)
  local rain,snow=0,0
  if state and type(state.channel)=="function" then
    local ok,v=pcall(state.channel,"rain");if ok then rain=tonumber(v) or 0 end
    ok,v=pcall(state.channel,"snow");if ok then snow=tonumber(v) or 0 end
  end
  if rain==0 and state and state.channels then rain=tonumber(state.channels.rain) or 0 end
  if snow==0 and state and state.channels then snow=tonumber(state.channels.snow) or 0 end
  return rain,snow
end
local function moonPhase()
  _CelestialSim=cached(_CelestialSim,"CelestialSim");local C=_CelestialSim;if C then
    if type(C.moonPhase)=="function" then local q=tonumber(C.moonPhase());if q then return q%1 end end
    if type(C.sample)=="function" then local s=C.sample();local q=s and s.moon and tonumber(s.moon.phase);if q then return q%1 end end
  end
  return 0
end
local function timeFraction(dt)
  _TimeOfDay=cached(_TimeOfDay,"TimeOfDay");local T=_TimeOfDay;if T then
    local h=tonumber(T.hour);if h then return (h%24)/24 end
  end
  W.tidePhase=(W.tidePhase+(tonumber(dt) or 0)/180)%1;return W.tidePhase
end
local function seasonTemperature(seasonId)
  seasonId=tostring(seasonId or ""):upper()
  if seasonId=="WINTER" then return -7 end
  if seasonId=="AUTUMN" or seasonId=="FALL" then return 5 end
  if seasonId=="SPRING" then return 9 end
  return 18
end

local function spawnRipples(dt)
  -- One global pool; large bodies receive proportionally more impacts without
  -- allowing a lake to turn rain into an unbounded particle system.
  for i=#W.ripples,1,-1 do local r=W.ripples[i];r.age=r.age+dt;if r.age>=r.life then table.remove(W.ripples,i) end end
  if W.rain<=0.03 or #W.ripples>=W.MAX_RIPPLES then return end
  local total=0;for _,b in ipairs(W.bodies) do total=total+b.area*(1-b.ice) end;if total<=0 then return end
  W._rippleAcc=(W._rippleAcc or 0)+dt*min(30,2+W.rain*10+sqrt(total)*0.4)
  while W._rippleAcc>=1 and #W.ripples<W.MAX_RIPPLES do
    W._rippleAcc=W._rippleAcc-1
    local pick=((W.serial*17+#W.ripples*13+floor(W._rippleAcc*101))%max(1,floor(total*10)))/10
    local acc=0;local b=W.bodies[1]
    for _,q in ipairs(W.bodies) do acc=acc+q.area*(1-q.ice);if pick<=acc then b=q;break end end
    if b and #b.cells>0 and b.ice<0.95 then
      local ci=((#W.ripples*29+W.serial*7)%#b.cells)+1;local c=b.cells[ci]
      local u=((#W.ripples*37+11)%97)/97;local v=((#W.ripples*53+19)%89)/89
      W.ripples[#W.ripples+1]={x=c.gx*W.TILE+2+12*u,z=c.gz*W.TILE+2+12*v,age=0,life=0.55+0.35*clamp(W.rain,0,1),strength=clamp(W.rain*(1-b.ice),0,1),body=b}
    end
  end
end

function W.update(dt,state,seasons)
  dt=max(0,min(0.25,tonumber(dt) or 0));W.observationAge=W.observationAge+dt
  _WindEngine=cached(_WindEngine,"WindEngine");local wind=nil;local WE=_WindEngine;if WE and WE.peek then wind=WE.peek() end
  local wx,wz=tonumber(wind and wind.x) or 0,tonumber(wind and wind.z) or 0;local wl=sqrt(wx*wx+wz*wz)
  if wl>1e-5 then W.windX,W.windZ=wx/wl,wz/wl end
  W.windStrength=clamp(tonumber(wind and (wind.strength or wind.envelope)) or 0,0,1.5)
  W.rain,W.snow=weatherChannels(state);W.moonPhase=moonPhase();local tf=timeFraction(dt)
  local sid=seasons and seasons.id or nil;local baseTemp=seasonTemperature(sid)
  _Microclimate=cached(_Microclimate,"Microclimate");local micro=nil;local M=_Microclimate;if M and M.peek then micro=M.peek() end
  if micro and tonumber(micro.temperature) then baseTemp=baseTemp*0.65+tonumber(micro.temperature)*0.35 end
  -- The user's seasonal contract is explicit: winter water eventually freezes.
  -- Local warmth can delay the process, but towns cannot keep an entire lake
  -- permanently liquid for the whole winter.
  if tostring(sid or ""):upper()=="WINTER" then baseTemp=min(baseTemp,-3.5) end
  local px,pz,p=playerWorld(W._state);W.player=p;local currentBody=px and W.bodyAt(px,pz) or nil;W.playerBody=currentBody
  local spring=0.35+0.65*abs(cos((W.moonPhase%1)*TAU)) -- full/new spring, quarters neap
  local semi=sin(tf*TAU*2)
  for _,b in ipairs(W.bodies) do
    local inertia=clamp(0.45+sqrt(b.area)*0.11,0.55,3.2)
    local target=baseTemp-W.snow*1.6+W.rain*0.12
    b.temp=b.temp+(target-b.temp)*(1-math.exp(-dt/(10*inertia)))
    local prevLoad=b.loadBearing
    local freezeRate=(b.temp<0) and dt*(0.010+min(0.022,-b.temp*0.0025)+W.snow*0.004)/inertia or 0
    local thawRate=(b.temp>0.8) and dt*(0.008+min(0.035,b.temp*0.0018))/max(0.7,inertia*0.72) or 0
    local nextIce=clamp(b.ice+freezeRate-thawRate,0,1)
    if currentBody==b then
      if prevLoad or b.ice>=W.LOAD_BEARING then nextIce=max(nextIce,W.THAW_HOLD)
      else nextIce=min(nextIce,W.LOAD_BEARING-0.025) end -- active surfer/open-water player cannot be trapped by a new freeze
    end
    b.ice=nextIce;b.loadBearing=b.ice>=W.LOAD_BEARING
    local sizeScale=clamp((sqrt(b.area)-1)/10,0,1)
    local tideScale=(0.05+0.95*sizeScale)*(b.touchesBoundary and 1 or 0.35+0.45*sizeScale)
    -- The host shoreline wall reaches the cartridge's normal -2 water plane.
    -- Ebb therefore returns to that low-water datum rather than sinking below
    -- it and exposing a void slit under shore geometry.
    b.tide=(0.5+0.5*semi)*spring*0.75*tideScale*(1-smooth(b.ice))
    -- A lake should still be visibly alive on a calm day; wind then grows that
    -- baseline into rough water instead of being the only source of relief.
    -- Narrow rivers keep lower heave but are handed a rapidness/flow channel to
    -- the 3D renderer for whitewater. Small ponds stay comparatively gentle.
    local kind=tostring(b.kind or "LAKE")
    local calm=(kind=="SEA" and (0.42+0.22*sizeScale)) or (kind=="LAKE" and (0.34+0.20*sizeScale))
      or (kind=="RIVER" and (0.22+0.10*sizeScale)) or (0.14+0.12*sizeScale)
    local windGain=(kind=="SEA" and 1.05) or (kind=="LAKE" and 0.92) or (kind=="RIVER" and 0.62) or 0.42
    local exposure=b.touchesBoundary and 1 or (0.55+0.45*sizeScale)
    b.wave=clamp((calm+windGain*W.windStrength+0.10*W.rain)*exposure*(1-b.ice)*(1-b.ice),0,1.45)
  end
  -- Presentation-only 8px host water fragments follow the same seasonal
  -- freeze/thaw clock so no blue legacy patch remains inside a frozen scene.
  -- They never enter bodyByCell and never become collision support.
  do
    local target=baseTemp-W.snow*1.6+W.rain*0.12
    W.visualTemp=(tonumber(W.visualTemp) or 6)+(target-(tonumber(W.visualTemp) or 6))*(1-math.exp(-dt/14))
    local freeze=(W.visualTemp<0) and dt*(0.011+min(0.024,-W.visualTemp*0.0027)+W.snow*0.004) or 0
    local thaw=(W.visualTemp>0.8) and dt*(0.010+min(0.038,W.visualTemp*0.0019)) or 0
    W.visualIce=clamp((tonumber(W.visualIce) or 0)+freeze-thaw,0,1)
  end
  for _,b in ipairs(W.hostBodies or {}) do
    b.ice=W.visualIce;b.temp=W.visualTemp;b.loadBearing=false;b.presentationFrozen=b.ice>=W.LOAD_BEARING
    local sizeScale=clamp((sqrt(max(1,b.area))-1)/10,0,1)
    local tideScale=(0.05+0.95*sizeScale)*(b.touchesBoundary and 1 or 0.35+0.45*sizeScale)
    b.tide=(0.5+0.5*semi)*spring*0.75*tideScale*(1-smooth(b.ice))
    local kind=tostring(b.kind or "POND")
    local calm=(kind=="SEA" and (0.42+0.22*sizeScale)) or (kind=="LAKE" and (0.34+0.20*sizeScale)) or (kind=="RIVER" and (0.22+0.10*sizeScale)) or (0.14+0.12*sizeScale)
    local windGain=(kind=="SEA" and 1.05) or (kind=="LAKE" and 0.92) or (kind=="RIVER" and 0.62) or 0.42
    local exposure=b.touchesBoundary and 1 or (0.55+0.45*sizeScale)
    b.wave=clamp((calm+windGain*W.windStrength+0.10*W.rain)*exposure*(1-b.ice)*(1-b.ice),0,1.45)
  end

  -- Synthetic VOID FILL water is an exposed visual sea, never gameplay water.
  -- It follows the same moon/wind/rain wave field so the horizon joins the
  -- authored hydrosphere naturally, but it can never freeze or become support.
  for _,b in ipairs(W.voidBodies or {}) do
    b.ice=0;b.loadBearing=false;b.temp=baseTemp
    local sizeScale=clamp((sqrt(max(1,b.area))-1)/10,0,1)
    b.tide=(0.5+0.5*semi)*spring*0.75*(0.05+0.95*sizeScale)
    local calm=0.42+0.22*sizeScale
    b.wave=clamp(calm+1.05*W.windStrength+0.10*W.rain,0,1.45)
  end
  if W.outerSea then
    -- The far sea is the same exposed body as the finite host apron, not a
    -- second simulation. Copy exact phase/state so the 96px handoff cannot
    -- reveal a static seam. It remains permanently non-gameplay/non-freezing.
    local src=W.voidBodies and W.voidBodies[1]
    W.outerSea.ice=0;W.outerSea.loadBearing=false;W.outerSea.temp=baseTemp
    W.outerSea.tide=src and (tonumber(src.tide) or 0) or 0
    W.outerSea.wave=src and (tonumber(src.wave) or 0) or clamp(0.64+1.05*W.windStrength+0.10*W.rain,0,1.45)
  end
  spawnRipples(dt)
end

function W.sample()
  local area,ice,wave,tide=0,0,0,0
  for _,b in ipairs(W.bodies) do area=area+b.area;ice=ice+b.ice*b.area;wave=wave+b.wave*b.area;tide=tide+b.tide*b.area end
  if area>0 then ice,wave,tide=ice/area,wave/area,tide/area end
  local voidCells=0;for _,b in ipairs(W.voidBodies or {}) do voidCells=voidCells+(tonumber(b.area) or 0) end
  local hostTiles=0;for _,b in ipairs(W.hostBodies or {}) do hostTiles=hostTiles+#(b.cells or {}) end
  return {bodies=#W.bodies,cells=area,hostBodies=#(W.hostBodies or {}),hostTiles=hostTiles,voidBodies=#(W.voidBodies or {}),voidCells=voidCells,renderBodies=#(W.renderBodies or W.bodies),outerSea=W.outerSea~=nil,outerSeaRange=W.outerSea and W.outerSea.range or 0,ice=ice,liquid=1-ice,wave=wave,tide=tide,windX=W.windX,windZ=W.windZ,wind=W.windStrength,rain=W.rain,ripples=#W.ripples,moonPhase=W.moonPhase,fresh=W.observationAge<=W.OBSERVATION_TTL}
end
function W.rippleState() return W.ripples end

-- Exact Gen1Recomp 0.2.53 hook contract: ctx contains map/mover/fromX/fromY/
-- toX/toY/reason. We only widen a vanilla TILE refusal on a cartridge water
-- cell, only for the observed player, and never an entity/bounds refusal.
function W.installHooks()
  if W._hookInstalled then return true end
  if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then return false end
  local ok=pcall(function()
    mod.hooks:wrap("movement.collision",function(next,allowed,ctx)
      allowed=next(allowed,ctx)
      if allowed or not ctx or ctx.reason~="tile" then return allowed end
      if not W.observed or W.observationAge>W.OBSERVATION_TTL then return allowed end
      if W.player and ctx.mover~=W.player then return allowed end
      if ctx.mover and ctx.mover.surfing then return allowed end
      local map=ctx.map;local tx,tz=tonumber(ctx.toX),tonumber(ctx.toY)
      if not (map and tx and tz and type(map.isWaterCell)=="function") then return allowed end
      -- Never widen a bounds refusal even if another hook corrupted ctx.reason,
      -- and never trust a same-coordinate water body from a connected map. The
      -- exact authored map+cell must be present in the fresh hydrosphere lookup.
      if type(map.inBounds)=="function" then local okb,inside=pcall(map.inBounds,map,tx,tz);if not (okb and inside==true) then return allowed end end
      local okw,isw=pcall(map.isWaterCell,map,tx,tz);if not (okw and isw==true) then return allowed end
      if W.isLoadBearingMapCell(map,tx,tz) then ctx.reason="weather_fx_ice";return true end
      return allowed
    end)
  end)
  W._hookInstalled=ok and true or false;return W._hookInstalled
end

function W.invalidate()
  rememberBodies();W.bodies={};W.voidBodies={};W.hostBodies={};W.renderBodies={};W.outerSea=nil;W.bodyByCell={};W.bodyByMapCell={};W.ripples={};W.observed=false;W.observationAge=1e9;W.player=nil;W.playerBody=nil;W._topologyKey=nil
end
return W
