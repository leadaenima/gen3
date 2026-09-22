-- ============================================================================
-- WEATHER FX 3D SNOW ACCUMULATION / FOOTPRINT PHYSICS
-- 8.1.69: player-toggleable accumulation; 8.1.68 distributed/coalesced banks retained.
-- ============================================================================
-- Snow is a persistent world-space depth field made from bounded radial mounds.
-- Every real WorldPrecip flake deposits at its exact X/Z impact. Nearby impacts
-- merge and stack vertically; separated impacts remain distinct round patches
-- until snowfall naturally bridges them. No 16x16 cell is ever switched on as
-- one rectangular blanket.
--
-- Lifetime authority is WEATHER, not deposit age. While a snow-family weather
-- is active accumulated depth can only stay the same or increase. Once weather
-- leaves the snow family, the total depth field melts gradually from the top.
-- There are no expiring "layers" whose old timer can delete a newer stack.
-- ============================================================================

local V = ...
local floor, ceil, sqrt, abs, max, min = math.floor, math.ceil, math.sqrt, math.abs, math.max, math.min
local sin, cos = math.sin, math.cos
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
local PI2 = math.pi * 2

local SP = {}
-- 8.1.28 flat-world SnowPack redesign. Accumulation is restored through the
-- bounded physical depth field plus the 8.1.66 conformal surface repaint pass.
-- Ground/grass/ice may still gain real mound thickness, while raised scenery and
-- trees are whitened on the host's own mesh instead of receiving detached caps.
-- Deposition follows exact voxel support, never accumulates on liquid water,
-- uses shallower retention on roofs/canopies/props, and melts on a finite clock.
SP.ACCUMULATION_ENABLED = true
local runtimeAccumulationEnabled = true
local function accumulationEnabled()
  return SP.ACCUMULATION_ENABLED ~= false and runtimeAccumulationEnabled ~= false
end
function SP.isEnabled() return accumulationEnabled() end
function SP.setEnabled(on)
  local nextEnabled = (on ~= false)
  if runtimeAccumulationEnabled == nextEnabled then return accumulationEnabled() end
  runtimeAccumulationEnabled = nextEnabled
  -- OFF is an immediate player-facing kill switch: no hidden banks remain to
  -- pop back in later, and re-enabling starts from a clean accumulation field.
  if not nextEnabled and SP._reset then SP._reset() end
  return accumulationEnabled()
end
SP.TILE = 16
SP.SUBTILE = 8
SP.SWEEP_STEP = 0.75
SP.FLAKE_RADIUS = 0.35
SP.MAX_CELLS = 2048
SP.MAX_PATCHES_PER_CELL = 6
SP.MAX_FOOTPRINTS = 192
SP.FOOT_STEP = 2.25
SP.FOOT_SIDE = 1.50
SP.FOOT_LIFE = 110.0
SP.MIN_TRACK_DEPTH = 0.055
SP.PATCH_RADIUS_MIN = 1.15
SP.PATCH_RADIUS_MAX = 9.75
SP.PATCH_MERGE_DISTANCE = 5.80
SP.PATCH_CLIP_STEP = 0.70
SP.PERSIST_WHILE_SNOW = true
-- Accumulation never ages while a snow-family weather is authoritative. Once
-- that weather ends, all remaining snow is guaranteed to finish melting within
-- this finite cleanup window. The countdown is global/lazy, not per-layer.
SP.ACCUM_HOLD = 0
SP.POST_SNOW_DESPAWN = 150.0
SP.MAX_GROUND_HEIGHT = 3.60
SP.MAX_GRASS_HEIGHT = 3.20
SP.MAX_RAISED_HEIGHT = 2.40
SP.MAX_TREE_HEIGHT = 1.85
SP.MAX_THIN_PROP_HEIGHT = 0.90
SP.MIN_VISIBLE_BANK_HEIGHT = 0.055
SP.FOOTPRINT_VISUAL_DEPTH = 0.42

local cells, byKey, freeSlots = {}, {}, {}
local cellTop, activeCells, evictCursor = 0, 0, 0
local activeList = {}
local clock, meltIntegral, snowFillIntegral = 0, 0, 0
local snowActive = false
local cleanupSerial, cleanupStart, cleanupDuration = 0, nil, SP.POST_SNOW_DESPAWN
local footprints = {}
local footTop, footCursor = 0, 0
local playerTrack = { mapKey=nil, x=nil, z=nil, accum=0, side=1 }

local DIRX={1,0.70710678,0,-0.70710678,-1,-0.70710678,0,0.70710678}
local DIRZ={0,0.70710678,1,0.70710678,0,-0.70710678,-1,-0.70710678}

local function clamp(v,a,b)
  v=tonumber(v) or 0
  if v<a then return a end
  if v>b then return b end
  return v
end


local _connectedWater=nil
local function connectedWater()
  if _connectedWater then return _connectedWater end
  local ok,m=pcall(V.require,"ConnectedWater");if ok and m then _connectedWater=m;return m end
end
local function iceSupportAt(x,z)
  local C=connectedWater();if not (C and C.isLoadBearingAt and C.isLoadBearingAt(x,z)) then return false,nil end
  local y=C.surfaceYAt and C.surfaceYAt(x,z) or -2
  return true,tonumber(y) or -2
end

local function mapKey(map)
  if not map then return "nil" end
  local d=map.def
  return tostring(map.id or (d and (d.id or d.name)) or map)
end
SP.mapKey=mapKey

local function mapDims(map)
  if not map then return 0,0 end
  local w,h=tonumber(map.widthCells),tonumber(map.heightCells)
  if (not w or w<=0) and map.def then local bw=tonumber(map.def.width); if bw and bw>0 then w=bw*2 end end
  if (not h or h<=0) and map.def then local bh=tonumber(map.def.height); if bh and bh>0 then h=bh*2 end end
  return max(0,floor(w or 0)),max(0,floor(h or 0))
end

local FRAME_CTX={regions={},regionByKey={},regionCount=0,frameSerial=0}
local shapeCache=setmetatable({}, {__mode="k"})
local structuresCache=setmetatable({}, {__mode="k"})
local roundSupportCache=setmetatable({}, {__mode="k"})

local function roundCellKey(cx,cz) return tostring(cx)..":"..tostring(cz) end

-- Build a tiny spatial index over the host's exact round/canopy stamp list.
-- Each stamp owns the same local quads ChunkMesher later translates into the
-- visible terrain mesh.  We index references only; no host geometry is copied.
local function roundSupportIndex(S)
  if type(S)~="table" then return nil end
  local cached=roundSupportCache[S]
  if cached then return cached end
  local out={cells={},stampCount=0}
  local stamps=type(S.roundStamps)=="table" and S.roundStamps or {}
  for _,st in ipairs(stamps) do
    local mx,mz=tonumber(st.mx),tonumber(st.mz)
    if mx and mz and type(st.quads)=="table" then
      local rr=max(1,tonumber(st.r) or 8)
      local cx0,cx1=floor((mx-rr)/SP.TILE),floor((mx+rr-1e-6)/SP.TILE)
      local cz0,cz1=floor((mz-rr)/SP.TILE),floor((mz+rr-1e-6)/SP.TILE)
      for cz=cz0,cz1 do for cx=cx0,cx1 do
        local k=roundCellKey(cx,cz);local list=out.cells[k]
        if not list then list={};out.cells[k]=list end
        list[#list+1]=st
      end end
      out.stampCount=out.stampCount+1
    end
  end
  roundSupportCache[S]=out
  return out
end

-- Return the highest horizontal host-quad under one map-local X/Z point.
-- `exact=true` means the host Structures authority was available even if this
-- point lies in a real gap in the hull; callers must then NOT invent a crown.
local function exactRoundTop(r,lx,lz,cx,cz)
  local S=r and r.structures
  if not (type(S)=="table" and type(S.roundStamps)=="table") then return nil,false end
  local idx=roundSupportIndex(S)
  local list=idx and idx.cells[roundCellKey(cx,cz)]
  if not list then return nil,true end
  local best=nil;local eps=1e-5
  for _,st in ipairs(list) do
    local mx,mz=tonumber(st.mx) or 0,tonumber(st.mz) or 0
    local rr=max(1,tonumber(st.r) or 8)
    if lx>=mx-rr-eps and lx<=mx+rr+eps and lz>=mz-rr-eps and lz<=mz+rr+eps then
      for _,q in ipairs(st.quads or {}) do
        if type(q)=="table" and type(q[1])=="table" and type(q[2])=="table"
           and type(q[3])=="table" and type(q[4])=="table" then
          local y=tonumber(q[1][2])
          if y and abs((tonumber(q[2][2]) or y)-y)<=eps
             and abs((tonumber(q[3][2]) or y)-y)<=eps
             and abs((tonumber(q[4][2]) or y)-y)<=eps then
            local x0,x1,z0,z1=1e30,-1e30,1e30,-1e30
            for i=1,4 do
              local qx=(tonumber(q[i][1]) or 0)+mx
              local qz=(tonumber(q[i][3]) or 0)+mz
              if qx<x0 then x0=qx end;if qx>x1 then x1=qx end
              if qz<z0 then z0=qz end;if qz>z1 then z1=qz end
            end
            if lx>=x0-eps and lx<=x1+eps and lz>=z0-eps and lz<=z1+eps then
              if best==nil or y>best then best=y end
            end
          end
        end
      end
    end
  end
  return best,true
end
SP.exactRoundTop=exactRoundTop

local function addRegion(ctx,map,ox,oz,hostTileShape,hostStructures)
  local w,h=mapDims(map)
  if not map or w<=0 or h<=0 then return end
  local n=(ctx.regionCount or 0)+1; ctx.regionCount=n
  local r=ctx.regions[n]
  if not r then
    r={groundValue={},groundStamp={},kindValue={},classValue={},artValue={},profileValue={},tileShape={},tileId={}}
    ctx.regions[n]=r
  elseif r.map~=map or r.w~=w or r.h~=h then
    r.groundValue,r.groundStamp,r.kindValue,r.classValue,r.artValue,r.profileValue,r.tileShape,r.tileId={},{},{},{},{},{},{},{}
  end
  r.map,r.key,r.ox,r.oz,r.w,r.h=map,mapKey(map),tonumber(ox) or 0,tonumber(oz) or 0,w,h
  -- 8.1.67 live-host correction: TileShape.forMap() is the host's current
  -- presentation authority and may replace its returned table after an in-place
  -- map/tileset hydration or TileShape.invalidate().  Do not retain an older
  -- shape table by map object forever: refresh the table each frame and only
  -- cache it as a compatibility fallback if the host call temporarily fails.
  local sh=nil
  if hostTileShape and type(hostTileShape.forMap)=="function" then
    local ok,got=pcall(hostTileShape.forMap,map)
    if ok and type(got)=="table" then sh=got; shapeCache[map]=got end
  end
  if sh==nil then sh=shapeCache[map] end
  r.shapes=(sh~=false) and sh or nil
  local ss=structuresCache[map]
  if ss==nil and hostStructures and type(hostStructures.forMap)=="function" then
    local ok,got=pcall(hostStructures.forMap,map)
    ss=(ok and type(got)=="table") and got or false
    structuresCache[map]=ss
  end
  r.structures=(ss~=false) and ss or nil
  ctx.regionByKey[r.key]=r
end

function SP.beginFrame(meta,fallbackGroundY,hostVoxelScene,hostTileShape,hostStructures)
  meta=type(meta)=="table" and meta or {}
  local ctx=FRAME_CTX; local oldCount=ctx.regionCount or 0
  ctx.frameSerial=(ctx.frameSerial or 0)+1; SP._frameSerial=ctx.frameSerial
  ctx.regionCount=0
  for k in pairs(ctx.regionByKey) do ctx.regionByKey[k]=nil end
  ctx.VS=hostVoxelScene or meta.voxelScene or meta.VoxelScene
  ctx.TS=hostTileShape or meta.tileShape or meta.TileShape
  ctx.Structures=hostStructures or meta.structures or meta.Structures
  ctx.state=meta.state; ctx.player=meta.player or (meta.state and meta.state.player)
  -- 8.1.67 live-host correction: WorldPrecip's stream focus can be a camera
  -- point rather than the player's load-bearing surface. Never let that camera
  -- Y become SnowPack's floor. When the voxel host exposes its authoritative
  -- groundAt() and the live player cell, resolve the fallback from the exact
  -- same surface the voxel player stands on. This keeps ground banks and the
  -- conformal repaint height aligned to real terrain instead of floating near
  -- eye/chest height in third-person views.
  local fallback=tonumber(fallbackGroundY) or 0
  local rootMap=meta.map or (meta.state and meta.state.map)
  local pl=ctx.player
  if hostVoxelScene and type(hostVoxelScene.groundAt)=="function" and rootMap and pl then
    local cx=tonumber(pl.cellX); local cz=tonumber(pl.cellY or pl.cellZ)
    if cx and cz then
      local ok,gy=pcall(hostVoxelScene.groundAt,rootMap,math.floor(cx),math.floor(cz))
      if ok and type(gy)=="number" and gy==gy then fallback=gy end
    end
  end
  ctx.fallbackGroundY=fallback
  ctx.snowy=false; ctx.weatherId=""
  addRegion(ctx,meta.map,0,0,ctx.TS,ctx.Structures)
  for _,nb in ipairs(meta.neighbors or {}) do if nb and nb.map then addRegion(ctx,nb.map,nb.ox or 0,nb.oy or nb.oz or 0,ctx.TS,ctx.Structures) end end
  for i=oldCount,ctx.regionCount+1,-1 do ctx.regions[i]=nil end
  ctx.collisionEnabled=ctx.VS~=nil and type(ctx.VS.groundAt)=="function" and ctx.regionCount>0
  return ctx
end

local function regionCell(ctx,x,z)
  if not ctx then return nil end
  for i=1,(ctx.regionCount or #ctx.regions) do
    local r=ctx.regions[i]; local lx,lz=x-r.ox,z-r.oz
    if lx>=0 and lz>=0 and lx<r.w*SP.TILE and lz<r.h*SP.TILE then
      return r,floor(lx/SP.TILE),floor(lz/SP.TILE),i,lx,lz
    end
  end
  return nil
end
SP.regionCell=regionCell

function SP.groundAt(ctx,x,z)
  if not ctx or not ctx.collisionEnabled then return ctx and ctx.fallbackGroundY or 0 end
  local r,cx,cz=regionCell(ctx,x,z); if not r then return ctx.fallbackGroundY end
  local key=cx*(r.h+1)+cz+1
  if r.groundStamp[key]==ctx.frameSerial then return r.groundValue[key] end
  local y=ctx.fallbackGroundY
  local ok,h=pcall(ctx.VS.groundAt,r.map,cx,cz)
  if ok and type(h)=="number" and h==h then y=h end
  r.groundValue[key]=y; r.groundStamp[key]=ctx.frameSerial
  return y
end

local THIN_CLASS={sign=true,signpost=true,post=true,billboard=true,prop=true,cutout=true,bike=true,console=true,stool=true}
local ROUND_CLASS={tree=true,canopy=true,cylinder=true,stump=true,planter=true,can=true,bush=true,shrub=true}
local function footprintProfile(kind,class,art)
  kind=tostring(kind or "ground"):lower(); class=tostring(class or ""):lower(); art=tostring(art or ""):lower()
  if kind=="water" then return "none" end
  if THIN_CLASS[class] or art=="billboard" or art=="post" then return "thin" end
  if kind=="tree" or ROUND_CLASS[class] or art=="canopy" or art=="cylinder" or art=="planter" then return "round" end
  return "full"
end
SP.footprintProfile=footprintProfile

local function classifyShape(shape,surfaceY,fallback)
  if type(shape)~="table" then
    if (tonumber(surfaceY) or 0)>(tonumber(fallback) or 0)+1.5 then return "raised","raised","top","full" end
    return "ground","ground","flat","full"
  end
  local class=tostring(shape.class or shape.kind or "ground"):lower()
  local art=tostring(shape.art or "flat"):lower()
  if class=="water" or art=="water" then return "water","water","flat","none" end
  local text=table.concat({class,art,tostring(shape.name or ""),tostring(shape.tag or "")}," "):lower()
  local kind="ground"
  if text:find("tree",1,true) or text:find("canopy",1,true) or ROUND_CLASS[class] then kind="tree"
  elseif text:find("bush",1,true) or text:find("shrub",1,true) then kind="tree"
  elseif text:find("grass",1,true) or text:find("plant",1,true) or text:find("flower",1,true) or class=="grass" or class=="flower" then kind="grass"
  elseif (tonumber(shape.h) or 0)>1.5 then kind="raised" end
  return kind,class,art,footprintProfile(kind,class,art)
end

local function cellShape(ctx,r,cx,cz)
  if not r then return nil end
  local ck=cx*(r.h+1)+cz+1
  local cached=r.kindValue[ck]
  if cached then
    if cached=="water" then
      local frozen=iceSupportAt(r.ox+cx*SP.TILE+8,r.oz+cz*SP.TILE+8)
      if frozen then return "ice","ice","flat","full" end
    end
    return cached,r.classValue[ck],r.artValue[ck],r.profileValue[ck]
  end
  local water=false
  if r.map and type(r.map.isWaterCell)=="function" then local ok,v=pcall(r.map.isWaterCell,r.map,cx,cz); water=ok and v==true end
  local shape=nil
  if r.shapes and r.map and type(r.map.cellTile)=="function" then local ok,t=pcall(r.map.cellTile,r.map,cx,cz); if ok then shape=r.shapes[t] end end
  local kind,class,art,profile
  if water then
    kind,class,art,profile="water","water","flat","none"
    r.kindValue[ck],r.classValue[ck],r.artValue[ck],r.profileValue[ck]=kind,class,art,profile
    local frozen=iceSupportAt(r.ox+cx*SP.TILE+8,r.oz+cz*SP.TILE+8)
    if frozen then return "ice","ice","flat","full" end
    return kind,class,art,profile
  else
    kind,class,art,profile=classifyShape(shape,SP.groundAt(ctx,r.ox+cx*SP.TILE+8,r.oz+cz*SP.TILE+8),ctx.fallbackGroundY)
  end
  r.kindValue[ck],r.classValue[ck],r.artValue[ck],r.profileValue[ck]=kind,class,art,profile
  return kind,class,art,profile
end

local function surfaceInfo(ctx,r,cx,cz,surfaceY)
  return cellShape(ctx,r,cx,cz)
end
SP.surfaceInfo=surfaceInfo
local function surfaceKind(ctx,r,cx,cz,surfaceY) return (cellShape(ctx,r,cx,cz)) end
SP.surfaceKind=surfaceKind

-- Resolve the actually supported top at one world-space point. VoxelScene's
-- groundAt() intentionally uses one collision height for a whole 16x16 cell;
-- snow needs finer presentation geometry, so use TileShape.at at 8x8 tile
-- resolution and clip round/thin objects to their real footprint.
local function preciseShape(ctx,r,lx,lz,cx,cz)
  local tx,tz=floor(lx/SP.SUBTILE),floor(lz/SP.SUBTILE)
  local tk=tx*((r.h*2)+3)+tz+1
  -- 8.1.67 live-host repair: map objects are hydrated in place. A coordinate
  -- can therefore answer a placeholder ground tile during predictive loading
  -- and the authored ledge tile a few frames later without changing map object
  -- identity. Cache the SHAPE only while the underlying tile id is unchanged;
  -- otherwise refresh immediately so snowfall cannot keep falling through a
  -- ledge whose visible ChunkMesher geometry has already finalized.
  local tile=nil
  if type(r.map.tileAt)=="function" then local ok,t=pcall(r.map.tileAt,r.map,tx,tz); if ok then tile=t end end
  if tile==nil and type(r.map.cellTile)=="function" then local ok,t=pcall(r.map.cellTile,r.map,cx,cz); if ok then tile=t end end
  local cached=r.tileShape[tk]
  if cached~=nil and r.tileId and r.tileId[tk]==tile then return cached~=false and cached or nil,tx,tz end
  local shape=nil
  if r.shapes and tile~=nil then
    local raw=r.shapes[tile]
    -- An authored TileShape is already the host's explicit answer for this
    -- exact 8x8 tile and must outrank cell-wide walkability/collision rules.
    -- The live Route 4 ledge exposed a host wrapper that could flatten the
    -- authored 54/55 ledge through TileShape.at even while the raw current
    -- table and visible ChunkMesher both said ledge h=6.  Preserve authored
    -- pins directly; use TileShape.at only for position-dependent / derived
    -- non-authored shapes (conditional pins still resolve there).
    if type(raw)=="table" and raw.authored==true then
      shape=raw
    elseif ctx.TS and type(ctx.TS.at)=="function" and type(r.map.tileAt)=="function" then
      local ok,s=pcall(ctx.TS.at,r.map,r.shapes,tile,tx,tz); if ok then shape=s end
    end
    if not shape then shape=raw end
  end
  r.tileId=r.tileId or {}; r.tileId[tk]=tile
  r.tileShape[tk]=shape or false
  return shape,tx,tz
end

function SP.debugSurface(ctx,x,z)
  local r,cx,cz,ri,lx,lz=regionCell(ctx,x,z)
  if not r then return {x=x,z=z,region=nil,fallback=ctx and ctx.fallbackGroundY or 0} end
  local shape,tx,tz=preciseShape(ctx,r,lx,lz,cx,cz)
  local tile=nil
  if type(r.map.tileAt)=="function" then local ok,t=pcall(r.map.tileAt,r.map,tx,tz); if ok then tile=t end end
  if tile==nil and type(r.map.cellTile)=="function" then local ok,t=pcall(r.map.cellTile,r.map,cx,cz); if ok then tile=t end end
  local hostY=SP.groundAt(ctx,x,z)
  local kind,class,art,profile=classifyShape(shape,hostY,ctx.fallbackGroundY)
  return {x=x,z=z,region=r.key,regionIndex=ri,cx=cx,cz=cz,lx=lx,lz=lz,tx=tx,tz=tz,tile=tile,shapeClass=type(shape)=="table" and shape.class or nil,shapeKind=type(shape)=="table" and shape.kind or nil,shapeH=type(shape)=="table" and shape.h or nil,shapeArt=type(shape)=="table" and shape.art or nil,shapeAuthored=type(shape)=="table" and shape.authored or nil,hostY=hostY,fallback=ctx.fallbackGroundY,kind=kind,class=class,art=art,profile=profile}
end

function SP.surfaceAt(ctx,x,z)
  local r,cx,cz,_,lx,lz=regionCell(ctx,x,z)
  if not r then return ctx and ctx.fallbackGroundY or 0,"ground","ground","flat","full",nil end
  if type(r.map.isWaterCell)=="function" then
    local ok,v=pcall(r.map.isWaterCell,r.map,cx,cz)
    if ok and v==true then
      local frozen,iy=iceSupportAt(x,z)
      if frozen then return iy,"ice","ice","flat","full",r end
      return SP.groundAt(ctx,x,z),"water","water","flat","none",r
    end
  end
  local shape,tx,tz=preciseShape(ctx,r,lx,lz,cx,cz)
  local hostY=SP.groundAt(ctx,x,z)
  local kind,class,art,profile=classifyShape(shape,hostY,ctx.fallbackGroundY)
  if kind=="water" then return hostY,kind,class,art,profile,r end
  local h=type(shape)=="table" and tonumber(shape.h) or nil
  local base=ctx.fallbackGroundY or 0
  local cellCx=r.ox+cx*SP.TILE+8; local cellCz=r.oz+cz*SP.TILE+8
  if profile=="round" then
    -- Voxel Nexus/compatible hosts expose the exact reusable hull stamps that
    -- ChunkMesher puts into the visible terrain mesh.  Use their real horizontal
    -- top quads as the snow landing surface.  If Structures is available and
    -- this point is a genuine gap between leaves/branches, fall through to
    -- ground instead of fabricating the old smooth invisible crown.
    local exactY,exact=exactRoundTop(r,lx,lz,cx,cz)
    if exact then
      if exactY~=nil then return max(base,exactY),kind,class,art,profile,r end
      return base,"ground","ground","flat","full",r
    end
    -- Compatibility fallback for voxel hosts that publish TileShape but not
    -- Structures.  This is intentionally never used on Voxel Nexus' exact hull.
    local dx,dz=x-cellCx,z-cellCz; local rr=6.85
    if class=="canopy" then rr=7.45 elseif class=="stump" then rr=5.4 elseif class=="planter" then rr=5.0 end
    local q=(dx*dx+dz*dz)/(rr*rr)
    if q>1 then return base,"ground","ground","flat","full",r end
    local top=(h and h>0) and h or hostY
    return max(base,top-min(1.55,top*0.08)*q),kind,class,art,profile,r
  elseif profile=="thin" then
    local hx,hz=6.2,1.65
    if class=="post" or class=="signpost" then hx,hz=2.4,1.45 elseif class=="cutout" or class=="bike" then hx,hz=4.2,0.95 end
    if abs(x-cellCx)>hx or abs(z-cellCz)>hz then return base,"ground","ground","flat","full",r end
    return (h and h>0) and h or hostY,kind,class,art,profile,r
  end
  if h and h>0 then return h,kind,class,art,profile,r end
  if art=="flat" or art=="grass" or art=="flower" then return base,kind,class,art,profile,r end
  return hostY,kind,class,art,profile,r
end

function SP.heightForDepth(kind,class,depth)
  depth=clamp(depth,0,1); if tostring(kind or ""):lower()=="water" then return 0 end
  local profile=footprintProfile(kind,class); local maxH=SP.MAX_GROUND_HEIGHT
  if profile=="thin" then maxH=SP.MAX_THIN_PROP_HEIGHT
  elseif kind=="tree" then maxH=SP.MAX_TREE_HEIGHT
  elseif kind=="grass" then maxH=SP.MAX_GRASS_HEIGHT
  elseif kind=="raised" then maxH=SP.MAX_RAISED_HEIGHT end
  return maxH*(depth*(1.18-0.18*depth))
end

local function cellKey(r,cx,cz) return r.key..":"..tostring(cx)..":"..tostring(cz) end
local function refreshDepth(c)
  local d=0
  for i=1,(c.patchN or 0) do local p=c.patches[i]; if p and (p.depth or 0)>d then d=p.depth end end
  c.depth=d; return d
end
local function releaseCell(i)
  local c=cells[i]; if not c or not c.key then return end
  byKey[c.key]=nil
  local pos=c.activePos
  if pos then
    local lp=#activeList; local swap=activeList[lp]; activeList[pos]=swap; activeList[lp]=nil
    if swap and swap~=i and cells[swap] then cells[swap].activePos=pos end
  end
  c.activePos=nil;c.key=nil;c.depth=0;c.mapKey=nil;c.class=nil;c.art=nil;c.profile=nil;c.patchN=0
  activeCells=max(0,activeCells-1);freeSlots[#freeSlots+1]=i
end
local function allocCell()
  local n=#freeSlots
  if n>0 then local i=freeSlots[n];freeSlots[n]=nil;return i end
  if cellTop<SP.MAX_CELLS then cellTop=cellTop+1;cells[cellTop]={patches={}};return cellTop end
  evictCursor=evictCursor%SP.MAX_CELLS+1;local i=evictCursor;local old=cells[i]
  if old and old.key then byKey[old.key]=nil end
  return i
end

local function syncCell(c)
  if not c or not c.key then return 0 end
  if snowActive or not cleanupStart then return refreshDepth(c) end
  local dur=max(0.1,tonumber(cleanupDuration) or SP.POST_SNOW_DESPAWN)
  local q=clamp((clock-cleanupStart)/dur,0,1)
  local n=c.patchN or 0; local w=1
  for i=1,n do
    local p=c.patches[i]
    if p then
      if p.cleanupSerial~=cleanupSerial then
        p.cleanupSerial=cleanupSerial
        p.cleanupBaseDepth=p.depth or 0
        p.cleanupBaseRadius=p.radius or SP.PATCH_RADIUS_MIN
      end
      p.depth=max(0,(p.cleanupBaseDepth or 0)*(1-q))
      p.radius=max(SP.PATCH_RADIUS_MIN,(p.cleanupBaseRadius or SP.PATCH_RADIUS_MIN)*(1-0.30*q))
      if p.depth>0.002 and q<1 then c.patches[w]=p;w=w+1 end
    end
  end
  for i=w,n do c.patches[i]=nil end
  c.patchN=w-1
  return refreshDepth(c)
end
SP.syncCell=syncCell

local function ensureCell(ctx,r,cx,cz,surfaceY,kind,class,art,profile)
  if kind=="water" then return nil,nil end
  local key=cellKey(r,cx,cz); local i=byKey[key]
  if i then local c=cells[i];syncCell(c);return c,i end
  i=allocCell();local c=cells[i]
  if c.key then byKey[c.key]=nil else activeCells=activeCells+1;activeList[#activeList+1]=i;c.activePos=#activeList end
  c.key=key;c.mapKey=r.key;c.cx=cx;c.cz=cz;c.depth=0;c.surfaceY=surfaceY;c.meltBase=meltIntegral
  c.kind,c.class,c.art,c.profile=kind,class,art,profile;c.lastTouch=clock;c.lastDeposit=clock;c.patchN=0;c.patches=c.patches or {}
  byKey[key]=i;return c,i
end

local function sameSupport(y0,kind0,class0,y1,kind1,class1)
  if kind1=="water" then return false end
  if abs((y1 or 0)-(y0 or 0))>0.72 then return false end
  local g0=(kind0=="ground" or kind0=="grass");local g1=(kind1=="ground" or kind1=="grass")
  if g0 and g1 then return true end
  if kind0~=kind1 then return false end
  if kind0=="raised" or kind0=="tree" then return tostring(class0)==tostring(class1) end
  return true
end

local function computeClip(ctx,p)
  p.clip=p.clip or {}
  -- 8.1.68 banks can grow wider after neighboring deposits merge. Only probe
  -- as far as this bank can currently reach; this keeps exact-support work
  -- bounded despite the larger visual bank radius.
  local clipLimit=min(SP.PATCH_RADIUS_MAX,max(SP.PATCH_RADIUS_MIN,(tonumber(p.radius) or SP.PATCH_RADIUS_MIN)+SP.PATCH_CLIP_STEP))
  for k=1,8 do
    local last=0; local d=SP.PATCH_CLIP_STEP; local bad=nil
    while d<=clipLimit+0.001 do
      local y,kind,class=SP.surfaceAt(ctx,p.x+DIRX[k]*d,p.z+DIRZ[k]*d)
      if not sameSupport(p.baseY,p.kind,p.class,y,kind,class) then bad=d;break end
      last=d;d=d+SP.PATCH_CLIP_STEP
    end
    if bad then
      -- Refine the exact support edge so shoreline/object caps cannot hang over
      -- the first invalid sample by a whole sweep step.
      local lo,hi=last,bad
      for _=1,5 do
        local mid=(lo+hi)*0.5
        local y,kind,class=SP.surfaceAt(ctx,p.x+DIRX[k]*mid,p.z+DIRZ[k]*mid)
        if sameSupport(p.baseY,p.kind,p.class,y,kind,class) then lo=mid else hi=mid end
      end
      last=lo
    elseif last<clipLimit then
      last=clipLimit
    end
    p.clip[k]=min(clipLimit,max(0.08,last))
  end
end

local function retentionFor(kind,class,art,profile)
  kind=tostring(kind or "ground"):lower();class=tostring(class or ""):lower();art=tostring(art or ""):lower();profile=tostring(profile or "full"):lower()
  if kind=="water" then return 0 end
  if profile=="thin" then return .20 end
  if kind=="tree" or class=="canopy" or art=="canopy" then return .52 end
  if kind=="raised" or class=="roof" or art=="roof" then return .72 end
  if kind=="grass" then return 1.06 end
  return 1.0
end
SP.retentionFor=retentionFor

local function resetPatch(ctx,p,x,z,size,baseY,kind,class,art,profile)
  p=p or {}
  p.x,p.z=x,z;p.baseY=baseY;p.kind,p.class=kind,class
  p.art,p.profile=art,profile
  p.depth=0;p.radius=SP.PATCH_RADIUS_MIN+clamp(tonumber(size) or 0.5,0,1.5)*0.35;p.clip=p.clip or {}
  p.cleanupSerial=nil;p.cleanupBaseDepth=nil;p.cleanupBaseRadius=nil
  computeClip(ctx,p);return p
end

local function newPatch(ctx,c,x,z,size,baseY,kind,class,art,profile)
  local n=(c.patchN or 0)+1; local p=resetPatch(ctx,c.patches[n],x,z,size,baseY,kind,class,art,profile);c.patches[n]=p;c.patchN=n
  return p
end

-- A 16x16 cell can contain multiple real 8x8 support surfaces (Route 4 is a
-- concrete example: ordinary ground in one half and an authored h=6 ledge in
-- the other). Keep the hard six-patch/cell performance bound, but never let six
-- duplicate patches from one support family starve a newly encountered support.
-- If the cell is full and the new support has no representative, recycle the
-- shallowest member of an over-represented support group.
local function recycleForDistinctSupport(ctx,c,x,z,size,baseY,kind,class,art,profile)
  local n=c.patchN or 0
  if n<SP.MAX_PATCHES_PER_CELL then return newPatch(ctx,c,x,z,size,baseY,kind,class,art,profile) end
  local pick,pickCount,pickDepth=nil,1,1e30
  for i=1,n do
    local a=c.patches[i]
    if a then
      local count=0
      for j=1,n do
        local b=c.patches[j]
        if b and sameSupport(a.baseY,a.kind,a.class,b.baseY,b.kind,b.class) then count=count+1 end
      end
      local dep=tonumber(a.depth) or 0
      if count>1 and (count>pickCount or (count==pickCount and dep<pickDepth)) then
        pick,pickCount,pickDepth=i,count,dep
      end
    end
  end
  if not pick then return nil end
  local p=resetPatch(ctx,c.patches[pick],x,z,size,baseY,kind,class,art,profile)
  c.patches[pick]=p
  return p
end

function SP.deposit(ctx,x,z,surfaceY,size)
  if not accumulationEnabled() then return nil,nil end
  if not ctx then return nil end
  local base,kind,class,art,profile,r=SP.surfaceAt(ctx,x,z)
  if not r or kind=="water" then return nil end
  surfaceY=tonumber(surfaceY) or base
  -- Trust the point-accurate support, not the cell-wide actor collision height.
  surfaceY=base
  local _,cx,cz=regionCell(ctx,x,z); local c=ensureCell(ctx,r,cx,cz,surfaceY,kind,class,art,profile)
  if not c then return nil end
  local retention=retentionFor(kind,class,art,profile)
  if retention<=0 then return nil end
  local amt=clamp(0.010+(tonumber(size) or 0.5)*0.006,0.010,0.030)*retention
  local best,bestD2=nil,1e30
  for i=1,(c.patchN or 0) do
    local p=c.patches[i];local dx,dz=x-p.x,z-p.z;local d2=dx*dx+dz*dz
    if sameSupport(p.baseY,p.kind,p.class,base,kind,class) and d2<bestD2 then best,bestD2=p,d2 end
  end
  local p=best
  local merge=SP.PATCH_MERGE_DISTANCE
  if not p or bestD2>merge*merge then
    if best then
      -- Same support exists but this impact is spatially separate. Preserve the
      -- historical bounded behavior when no slot remains.
      if (c.patchN or 0)<SP.MAX_PATCHES_PER_CELL then p=newPatch(ctx,c,x,z,size,base,kind,class,art,profile) end
    else
      -- No patch represents this support at all. A mixed ground/ledge/tree cell
      -- must retain at least one representative for the newly hit real surface.
      p=recycleForDistinctSupport(ctx,c,x,z,size,base,kind,class,art,profile)
    end
  end
  if not p then return nil end
  p.art,p.profile=art,profile
  local cap=(kind=="tree") and 0.88 or 1.0
  p.depth=min(cap,(p.depth or 0)+amt)
  p.radius=min(SP.PATCH_RADIUS_MAX,(p.radius or SP.PATCH_RADIUS_MIN)+0.055+amt*2.8)
  -- Fresh snow during a snow-family weather owns the current physical depth;
  -- stale cleanup baselines must never delete it later.
  p.cleanupSerial=nil;p.cleanupBaseDepth=nil;p.cleanupBaseRadius=nil
  c.surfaceY=base;c.kind,c.class,c.art,c.profile=kind,class,art,profile;c.lastTouch=clock;c.lastDeposit=clock;c.meltBase=meltIntegral
  refreshDepth(c)
  return c,p
end

-- Remove one patch without reallocating the cell. This is used only by the
-- bounded aggregate coalescer below, so the six-patch/cell memory ceiling stays
-- intact and can only decrease as a bank matures.
local function removePatchAt(c,i)
  local n=c and (c.patchN or 0) or 0
  if i<1 or i>n then return end
  for j=i,n-1 do c.patches[j]=c.patches[j+1] end
  c.patches[n]=nil;c.patchN=n-1;refreshDepth(c)
end

local function bankCap(p) return (p and p.kind=="tree") and 0.88 or 1.0 end
local function bankVolume(p)
  if not p then return 0 end
  local r=max(0.25,tonumber(p.radius) or SP.PATCH_RADIUS_MIN)
  return max(0,tonumber(p.depth) or 0)*r*r
end

-- 8.1.68: once two same-surface mounds overlap, they become ONE physical bank.
-- This is deliberately a local 3x3-cell operation: with a <10-unit radius and
-- 16-unit cells every possible overlap is inside that neighborhood. Combining
-- a depth*area proxy preserves snow mass without adding the two heights, which
-- prevents the old stacked-blob look and sudden vertical spikes.
local function coalesceAggregate(ctx,p)
  if not (ctx and p) then return p end
  local r,cx,cz=regionCell(ctx,p.x,p.z);if not r then return p end
  local passes=0;local changed=true
  while changed and passes<2 do
    changed=false;passes=passes+1
    for ix=cx-1,cx+1 do for iz=cz-1,cz+1 do
      local ci=byKey[cellKey(r,ix,iz)];local c=ci and cells[ci]
      if c and c.key then
        syncCell(c)
        for j=(c.patchN or 0),1,-1 do
          local q=c.patches[j]
          if q and q~=p and sameSupport(p.baseY,p.kind,p.class,q.baseY,q.kind,q.class) then
            local dx,dz=q.x-p.x,q.z-p.z;local dist=sqrt(dx*dx+dz*dz)
            local pr=max(SP.PATCH_RADIUS_MIN,tonumber(p.radius) or SP.PATCH_RADIUS_MIN)
            local qr=max(SP.PATCH_RADIUS_MIN,tonumber(q.radius) or SP.PATCH_RADIUS_MIN)
            if dist<=max(SP.PATCH_MERGE_DISTANCE,(pr+qr)*0.74) then
              local v1,v2=bankVolume(p),bankVolume(q);local vt=v1+v2
              local nr=min(SP.PATCH_RADIUS_MAX,sqrt(pr*pr+qr*qr))
              if vt>1e-7 then
                local nx=(p.x*v1+q.x*v2)/vt;local nz=(p.z*v1+q.z*v2)/vt
                local nb,nk,nc=SP.surfaceAt(ctx,nx,nz)
                if sameSupport(p.baseY,p.kind,p.class,nb,nk,nc) then p.x,p.z=nx,nz end
              end
              p.radius=nr
              p.depth=min(bankCap(p),vt/max(0.25,nr*nr))
              p.cleanupSerial=nil;p.cleanupBaseDepth=nil;p.cleanupBaseRadius=nil
              removePatchAt(c,j);computeClip(ctx,p);changed=true
            end
          end
        end
      end
    end end
  end
  return p
end
SP.coalesceAggregate=coalesceAggregate

-- Aggregate procedural snowfall represents the GPU-owned visual storm with a
-- tiny fixed exact-support sample stream. 8.1.68 keeps that bounded architecture
-- but makes each sample lighter, grows broader/flatter with age, and coalesces
-- overlaps so sustained snow converges toward continuous banks instead of a
-- pile of independent blobs. Literal interaction flakes still use SP.deposit.
function SP.depositAggregate(ctx,x,z,size)
  local c,p=SP.deposit(ctx,x,z,nil,size)
  if not p then return c,p end
  local retention=retentionFor(p.kind,p.class,c and c.art,c and c.profile)
  local aggregateMass=(0.012+clamp(tonumber(size) or 0.8,0,1.5)*0.005)*retention
  p.depth=min(bankCap(p),(tonumber(p.depth) or 0)+aggregateMass)
  if c then refreshDepth(c);c.lastTouch=clock;c.lastDeposit=clock end
  local d=tonumber(p.depth) or 0
  local target=3.60 + min(3.65,d*4.9)
  if (p.radius or 0)<target then p.radius=min(SP.PATCH_RADIUS_MAX,target) end
  computeClip(ctx,p)
  coalesceAggregate(ctx,p)
  if c then refreshDepth(c) end
  return c,p
end

local function dirIndex(dx,dz)
  if abs(dx)+abs(dz)<1e-8 then return 1 end
  local a=atan2(dz,dx);if a<0 then a=a+PI2 end
  return (floor((a+math.pi/8)/(math.pi/4))%8)+1
end
local function patchContribution(p,x,z)
  local dx,dz=x-p.x,z-p.z;local d2=dx*dx+dz*dz
  local r=min(p.radius or SP.PATCH_RADIUS_MIN,(p.clip and p.clip[dirIndex(dx,dz)]) or SP.PATCH_RADIUS_MAX)
  if r<=0 or d2>=r*r then return 0 end
  local q=sqrt(d2)/r;local f=1-q*q;f=f*f
  return (p.depth or 0)*f
end

function SP.depthAtPoint(ctx,x,z)
  if not accumulationEnabled() then
    local base,kind,class=SP.surfaceAt(ctx,x,z)
    return 0,base,kind,class,nil
  end
  local base,kind,class,art,profile,r=SP.surfaceAt(ctx,x,z)
  if not r or kind=="water" then return 0,base,kind,class,nil end
  local _,cx,cz=regionCell(ctx,x,z);local total,best,bestV=0,nil,0
  for ix=cx-1,cx+1 do
    for iz=cz-1,cz+1 do
      local ci=byKey[cellKey(r,ix,iz)];local c=ci and cells[ci]
      if c and c.key then
        syncCell(c)
        for j=1,(c.patchN or 0) do
          local p=c.patches[j]
          if sameSupport(p.baseY,p.kind,p.class,base,kind,class) then
            local v=patchContribution(p,x,z)
            if v>0 then total=total+v;if v>bestV then bestV,best=v,p end end
          end
        end
      end
    end
  end
  return min(1,total),base,kind,class,best
end

local function snowTopAt(ctx,x,z)
  if not accumulationEnabled() then
    local base,kind,class=SP.surfaceAt(ctx,x,z)
    return base,nil,kind,0,base,class
  end
  local d,base,kind,class,p=SP.depthAtPoint(ctx,x,z)
  return base+SP.heightForDepth(kind,class,d),p,kind,d,base,class
end
SP.snowTopAt=snowTopAt

local flakeHit={x=0,y=0,z=0,t=0,cell=nil,patch=nil,water=false}
local function finishFlakeHit(ctx,x0,y0,z0,x1,y1,z1,t,size)
  local x=x0+(x1-x0)*t;local z=z0+(z1-z0)*t
  local base,kind=SP.surfaceAt(ctx,x,z)
  local c,p=nil,nil
  if accumulationEnabled() and kind~="water" then c,p=SP.deposit(ctx,x,z,base,size) end
  local top=select(1,snowTopAt(ctx,x,z))
  flakeHit.x,flakeHit.y,flakeHit.z,flakeHit.t,flakeHit.cell,flakeHit.patch=x,top+SP.FLAKE_RADIUS,z,t,c,p
  flakeHit.water=(kind=="water");return flakeHit
end

function SP.resolveFlake(ctx,x0,y0,z0,x1,y1,z1,size)
  if not ctx or not ctx.collisionEnabled then return nil end
  local dx,dy,dz=x1-x0,y1-y0,z1-z0
  -- Exact vertical/nearly-vertical path: point snow height can vary inside a
  -- cell, so solve at the impact X/Z rather than assuming cell-wide height.
  if abs(dx)<0.12 and abs(dz)<0.12 then
    local top=select(1,snowTopAt(ctx,x1,z1));local target=top+SP.FLAKE_RADIUS
    if y1<=target then local t=1;if abs(dy)>1e-9 and y0>target then t=clamp((target-y0)/dy,0,1) end;return finishFlakeHit(ctx,x0,y0,z0,x1,y1,z1,t,size) end
    return nil
  end
  local span=max(abs(dx),abs(dy),abs(dz));local steps=max(1,ceil(span/SP.SWEEP_STEP))
  for k=1,steps do local t=k/steps;local x,y,z=x0+dx*t,y0+dy*t,z0+dz*t;local top=select(1,snowTopAt(ctx,x,z));if y<=top+SP.FLAKE_RADIUS then return finishFlakeHit(ctx,x0,y0,z0,x1,y1,z1,t,size) end end
  return nil
end

local function weatherMeltRate(id)
  id=tostring(id or ""):upper()
  if id:find("RAIN",1,true) or id=="STORM" or id=="GALE" or id=="PRIMAL_RAIN" then return 0.008 end
  if id=="SUNNY" or id=="HARSH_SUN" or id=="HEATWAVE" then return 0.005 end
  if id=="CLEAR" then return 0.0025 end
  if id=="SANDSTORM" or id=="DUSTSTORM" then return 0.004 end
  return 0.0018
end
local function cleanupDurationFor(id,temp)
  id=tostring(id or ""):upper();temp=tonumber(temp) or 4
  if id:find("RAIN",1,true) or id=="STORM" or id=="PRIMAL_RAIN" or id=="SLEET" then return 48 end
  if id=="HEATWAVE" or id=="HARSH_SUN" then return 32 end
  if temp>=14 then return 70 end
  if temp>=6 then return 110 end
  if temp>0 then return 165 end
  return 240
end

local function isSnowWeather(id)
  id=tostring(id or ""):upper()
  if id:find("SNOW",1,true) then return true end
  if id:sub(1,5)=="FROST" or id:sub(1,3)=="ICE" then return true end
  return id=="BLIZZARD" or id=="WHITEOUT" or id=="THUNDERSNOW" or id=="DRAGONSTORM" or id=="SLEET"
end
SP.isSnowWeather=isSnowWeather

local function allocFoot()
  if footTop<SP.MAX_FOOTPRINTS then footTop=footTop+1;footprints[footTop]={};return footTop end
  footCursor=footCursor%SP.MAX_FOOTPRINTS+1;return footCursor
end

local function stampFoot(ctx,r,wx,wz,dirX,dirZ)
  local side=playerTrack.side or 1;playerTrack.side=-side
  local px,pz=-dirZ,dirX;local fx,fz=wx+px*SP.FOOT_SIDE*side,wz+pz*SP.FOOT_SIDE*side
  local depth,base,kind,class,p=SP.depthAtPoint(ctx,fx,fz)
  -- 8.1.64: a boot sole has area. Procedural SnowPack is intentionally made
  -- of rounded sub-cell mounds, so a zero-width probe can fall into a tiny gap
  -- even while the rendered shoe visibly overlaps snow. Sample a bounded 5-point
  -- sole footprint and use the deepest walkable support. This runs only on
  -- actual player footfalls (FOOT_STEP), never on the dense visual snow field.
  if depth<SP.MIN_TRACK_DEPTH or (kind~="ground" and kind~="grass") then
    local bestD,bestX,bestZ,bestBase,bestKind,bestClass,bestP=depth,fx,fz,base,kind,class,p
    local alongX,alongZ=dirX*0.80,dirZ*0.80
    local crossX,crossZ=px*0.72,pz*0.72
    local probes={{alongX,alongZ},{-alongX,-alongZ},{crossX,crossZ},{-crossX,-crossZ}}
    for i=1,4 do
      local q=probes[i];local qx,qz=fx+q[1],fz+q[2]
      local qd,qb,qk,qc,qp=SP.depthAtPoint(ctx,qx,qz)
      if (qk=="ground" or qk=="grass") and qd>bestD then
        bestD,bestX,bestZ,bestBase,bestKind,bestClass,bestP=qd,qx,qz,qb,qk,qc,qp
      end
    end
    depth,fx,fz,base,kind,class,p=bestD,bestX,bestZ,bestBase,bestKind,bestClass,bestP
  end
  if depth<SP.MIN_TRACK_DEPTH or (kind~="ground" and kind~="grass") then return false end
  local fi=allocFoot();local f=footprints[fi];local bankH=SP.heightForDepth(kind,class,depth)
  f.active=true;f.mapKey=r.key;f.lx=fx-r.ox;f.lz=fz-r.oz;f.surfaceY=base
  f.depression=min(SP.FOOTPRINT_VISUAL_DEPTH,bankH*0.42);f.angle=atan2(dirZ,dirX);f.age=0;f.life=SP.FOOT_LIFE;f.fill=0;f.side=side
  f.bornAt=clock;f.fillBase=snowFillIntegral
  -- The footprint is a transient depression overlay. While snow is still
  -- falling, do not subtract persistent bank mass underneath it; otherwise a
  -- heavily walked route can visibly erode even though the storm continues.
  if p and not snowActive then p.depth=max(0,(p.depth or 0)-0.006) end
  return true
end

function SP.updatePlayer(ctx,dt)
  if not accumulationEnabled() then return end
  if not ctx then return end
  local state=ctx.state;local p=ctx.player or (state and state.player);local r=ctx.regions[1]
  if not p or not r then playerTrack.mapKey=nil;playerTrack.x=nil;playerTrack.z=nil;return end
  local x=tonumber(p.px);local z=tonumber(p.py)
  if x==nil and tonumber(p.cellX) then x=tonumber(p.cellX)*SP.TILE end
  if z==nil and tonumber(p.cellY) then z=tonumber(p.cellY)*SP.TILE end
  if x==nil or z==nil then return end
  x,z=x+8,z+8
  if playerTrack.mapKey~=r.key or playerTrack.x==nil then playerTrack.mapKey=r.key;playerTrack.x=x;playerTrack.z=z;playerTrack.accum=0;return end
  local dx,dz=x-playerTrack.x,z-playerTrack.z;local dist=sqrt(dx*dx+dz*dz)
  if dist>72 then playerTrack.x=x;playerTrack.z=z;playerTrack.accum=0;return end
  if dist>0.015 then
    local dirX,dirZ=dx/dist,dz/dist;local old=playerTrack.accum or 0;local total=old+dist
    if total>=SP.FOOT_STEP then
      local t=(SP.FOOT_STEP-old)/dist
      while t<=1.0001 do stampFoot(ctx,r,playerTrack.x+dx*t,playerTrack.z+dz*t,dirX,dirZ);t=t+SP.FOOT_STEP/dist end
      total=total%SP.FOOT_STEP
    end
    playerTrack.accum=total
  end
  playerTrack.x=x;playerTrack.z=z
end

function SP.update(dt,ctx,snowy,weatherId)
  if not accumulationEnabled() then
    if activeCells>0 or footTop>0 then SP._reset() end
    if ctx then ctx.snowy=false;ctx.weatherId=tostring(weatherId or "") end
    return
  end
  dt=max(0,min(0.25,tonumber(dt) or 0));clock=clock+dt
  local wid=tostring(weatherId or "")
  -- The authoritative weather ID wins over a fading snow-intensity channel.
  -- This makes manual weather changes begin cleanup immediately. Only hosts
  -- that provide no ID at all fall back to the legacy snowy boolean.
  local nextSnow
  if wid~="" then nextSnow=isSnowWeather(wid) else nextSnow=(snowy==true) end
  if snowActive and not nextSnow then
    cleanupSerial=cleanupSerial+1
    cleanupStart=clock
    local temp=4
    local okM,M=pcall(V.require,"Microclimate")
    if okM and M and M.peek then local okQ,q=pcall(M.peek);if okQ and q then temp=tonumber(q.temperature) or temp end end
    cleanupDuration=cleanupDurationFor(wid,temp)
  elseif (not snowActive) and nextSnow then
    cleanupStart=nil
  end
  snowActive=nextSnow
  if ctx then ctx.snowy=snowActive;ctx.weatherId=wid end
  -- Retain the historical integral only for compatibility/telemetry. Physical
  -- SnowPack cleanup is now a finite normalized countdown, never depth-rate
  -- dependent, so even a maximum bank is guaranteed gone by the deadline.
  local melt=snowActive and 0 or weatherMeltRate(wid)
  if melt>0 then meltIntegral=meltIntegral+melt*dt end
  if snowActive then snowFillIntegral=snowFillIntegral+dt*0.012 end
  SP.updatePlayer(ctx,dt)
end

local function regionForKey(ctx,key) return ctx and ctx.regionByKey and ctx.regionByKey[key] or nil end

function SP.fillGroundPool(pool,maxCount,ctx,focusX,focusZ,radius)
  if not accumulationEnabled() then if pool then pool.active=0 end; return 0 end
  if not pool then return 0 end
  pool.baseY=pool.baseY or {};pool.height=pool.height or {};pool.class=pool.class or {};pool.profile=pool.profile or {};pool.art=pool.art or {}
  pool.r1=pool.r1 or {};pool.r2=pool.r2 or {};pool.r3=pool.r3 or {};pool.r4=pool.r4 or {};pool.r5=pool.r5 or {};pool.r6=pool.r6 or {};pool.r7=pool.r7 or {};pool.r8=pool.r8 or {}
  maxCount=max(0,floor(tonumber(maxCount) or 0));radius=tonumber(radius) or 999999;local rr=radius*radius;local n=0
  local ai=1
  while ai<=#activeList do
    local i=activeList[ai];local c=cells[i];syncCell(c)
    if (c.patchN or 0)<=0 or (c.depth or 0)<=0.002 then releaseCell(i)
    else
      local r=regionForKey(ctx,c.mapKey)
      if r then
        for j=1,(c.patchN or 0) do
          local p=c.patches[j]
          if p and (p.depth or 0)>0.012 then
            local dx,dz=p.x-(focusX or p.x),p.z-(focusZ or p.z)
            if dx*dx+dz*dz<=rr then
              n=n+1;if n>maxCount then n=maxCount;pool.active=n;return n end
              local h=SP.heightForDepth(p.kind,p.class,p.depth or 0)
              pool.x[n],pool.z[n]=p.x,p.z;pool.baseY[n]=p.baseY or 0;pool.height[n]=h;pool.y[n]=(p.baseY or 0)+h
              pool.amount[n]=p.depth or 0;pool.kind[n]=p.kind or c.kind or "ground";pool.class[n]=p.class or c.class or "ground";pool.art[n]=p.art or c.art;pool.profile[n]=p.profile or footprintProfile(p.kind,p.class,p.art or c.art)
              pool.size[n]=p.radius or SP.PATCH_RADIUS_MIN
              for k=1,8 do pool["r"..k][n]=min(p.radius or SP.PATCH_RADIUS_MIN,(p.clip and p.clip[k]) or SP.PATCH_RADIUS_MAX) end
            end
          end
        end
      end
      ai=ai+1
    end
  end
  pool.active=n;return n
end

function SP.fillFootPool(pool,maxCount,ctx)
  if not accumulationEnabled() then if pool then pool.active=0 end; return 0 end
  if not pool then return 0 end
  pool.depression=pool.depression or {};local n=0
  for i=1,footTop do
    local f=footprints[i]
    if f and f.active then
      local age=clock-(tonumber(f.bornAt) or clock);local fill=min(1,(tonumber(f.fill) or 0)+max(0,snowFillIntegral-(tonumber(f.fillBase) or snowFillIntegral)))
      if age>=(f.life or SP.FOOT_LIFE) or fill>=1 then f.active=false
      else
        local r=regionForKey(ctx,f.mapKey)
        if r then
          local wx,wz=r.ox+(f.lx or 0),r.oz+(f.lz or 0);local depth,base,kind,class=SP.depthAtPoint(ctx,wx,wz)
          if depth>SP.MIN_TRACK_DEPTH and kind~="water" then
            n=n+1;if n>maxCount then n=maxCount;break end
            pool.x[n],pool.z[n]=wx,wz;local h=SP.heightForDepth(kind,class,depth);local dep=min(f.depression or 0,h*0.48)
            pool.y[n]=max(base+0.025,base+h-dep*0.36)+0.01;pool.depression[n]=dep;pool.angle[n]=f.angle or 0;pool.size[n]=1
            local life=max(0.1,f.life or SP.FOOT_LIFE);local ageFade=1-clamp((age/life-0.82)/0.18,0,1)
            pool.a[n]=max(0,ageFade*(1-fill));pool.side[n]=f.side or 1
          end
        end
      end
    end
  end
  pool.active=n;return n
end

function SP.depthAtMapCell(map,cx,cz)
  if not accumulationEnabled() then return 0 end
  local i=byKey[mapKey(map)..":"..tostring(cx)..":"..tostring(cz)];local c=i and cells[i]
  if not c then return 0 end;return syncCell(c)
end
function SP.heightAtMapCell(map,cx,cz)
  if not accumulationEnabled() then return 0 end
  local i=byKey[mapKey(map)..":"..tostring(cx)..":"..tostring(cz)];local c=i and cells[i]
  if not c then return 0 end;syncCell(c);local h=0
  for j=1,(c.patchN or 0) do local p=c.patches[j];h=max(h,SP.heightForDepth(p.kind,p.class,p.depth or 0)) end
  return h
end
function SP.stats()
  if not accumulationEnabled() then return 0,0,0,0,0 end
  local f,pn=0,0
  for i=1,footTop do if footprints[i] and footprints[i].active then f=f+1 end end
  for _,ci in ipairs(activeList) do local c=cells[ci];if c then pn=pn+(c.patchN or 0) end end
  return activeCells,f,cellTop,footTop,pn
end
function SP._reset()
  cells={};byKey={};freeSlots={};activeList={};cellTop=0;activeCells=0;evictCursor=0
  footprints={};footTop=0;footCursor=0;clock=0;meltIntegral=0;snowFillIntegral=0;snowActive=false
  cleanupSerial=0;cleanupStart=nil;cleanupDuration=SP.POST_SNOW_DESPAWN
  playerTrack={mapKey=nil,x=nil,z=nil,accum=0,side=1};FRAME_CTX={regions={},regionByKey={},regionCount=0,frameSerial=0};shapeCache=setmetatable({}, {__mode="k"})
end

return SP
