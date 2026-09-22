-- 3D GALE TORNADO SYSTEM.
--
-- Strict 3D/FPV Gale weather owns persistent world-space funnels. They condense
-- down from the live cloud deck, roam the flat voxel world for about three
-- minutes, ingest water into a temporary waterspout appearance, and finally
-- rope out upward into the cloud bank. The player-facing TORNADO PLAYER PICKUP
-- control chooses how often newly spawned funnels may become carry tornadoes; destinations are
-- restricted to maps already recorded as visited.
--
-- Carry never walks the gameplay player through arbitrary cells. Weather FX
-- asserts the engine player's native inputLocked flag for the full carry (with
-- movement.collision as a second safety net), so both grid movement and voxel
-- free-move controls stop while the renderer receives the orbit/lift pose. The
-- actual map transfer uses the engine's guarded overworld map-change path.
--
-- Flat 2D mode retains the older warning-funnel/visited-map event as a fallback;
-- it is never stacked over the strict 3D funnel.
local V = ...
local mod = V.mod
local T = {
  timer=0,lastReason="idle",active={},serial=0,stormAge=0,nextSpawn=0,
  _gale=false,_carry=nil,_voxelState=nil,_hookInstalled=false,
  _legacyTimer=0,_legacyCarry=nil,_controlLock=nil,
}

local sin,cos,sqrt,pi=math.sin,math.cos,math.sqrt,math.pi
local randomFn = function()
  if love and love.math and love.math.random then return love.math.random() end
  return math.random()
end
local flatScratch={water=false,solid=false,canopy=false,roof=false,shelter=0,drag=1,groundY=0}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function atan2(y,x)
  if math.atan2 then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) end
  if x<0 and y>=0 then return math.atan(y/x)+pi end
  if x<0 and y<0 then return math.atan(y/x)-pi end
  if x==0 and y>0 then return pi*.5 end
  if x==0 and y<0 then return -pi*.5 end
  return 0
end
local function rnd() return randomFn() end
local function range(a,b) return a+(b-a)*rnd() end
local function irand(n) if n<=1 then return 1 end return math.min(n,1+math.floor(rnd()*n)) end
local function req(name) local ok,m=pcall(V.require,name); return ok and m or nil end

local function cfg()
  local C=req("Config"); local c=C and C.get and C.get() or {}; return type(c.tornado)=="table" and c.tornado or {}
end
local function settingOn()
  local S=req("Settings"); if not (S and S.is and S.is("tornado","on")) then return false end
  return cfg().enabled~=false
end
local function currentWeather()
  local S=req("WeatherState"); return S and S.current and S.current() or nil
end
local function galeNow()
  local WS=req("WeatherState")
  local S=req("Settings")
  -- A real explicit level 0 is WEATHER OFF. Older/partial hosts and test
  -- harnesses may not expose WeatherState.level at all; absence is unknown,
  -- not OFF, so preserve the current authored GALE in that compatibility case.
  if (WS and WS.level~=nil and (tonumber(WS.level) or 0)<=0)
      or (S and S.weatherDisabled and S.weatherDisabled()) then return false end
  local d=currentWeather(); return type(d)=="table" and tostring(d.id or ""):upper()=="GALE"
end
local function strict3d()
  local B=req("VoxelAtmosBridge")
  if not B then return false end
  if B.presentation3d then
    local ok,yes=pcall(B.presentation3d); return ok and yes and true or false
  end
  -- Compatibility fallback for an older bridge: host activity alone is not
  -- enough when the player explicitly selected the flat presentation.
  local S=req("Settings")
  if S and S.isFirstPerson and S.isFirstPerson() then return true end
  if S and S.force2dPresent and S.force2dPresent() then return false end
  if S and S.allow3dPresent and not S.allow3dPresent() then return false end
  return B.active and B.active() or false
end
local function outdoors()
  local S=req("Scene"); local n=S and S.now or {}; return n.visible=="world" and not n.indoors
end
local function playerInfo()
  -- Gameplay contact must follow the LIVE overworld entity, not a render-state
  -- snapshot that may be one frame old (or a copied pose on some voxel hosts).
  -- The voxel snapshot remains the world-space fallback used by headless/older
  -- hosts and by disconnected presentation-only probes.
  local S=req("Scene"); local n=S and S.now or {}
  local ow=S and S.overworld and S.overworld() or nil
  local p=ow and ow.player or nil
  local x=p and tonumber(p.px or p.x); local z=p and tonumber(p.py or p.y)
  if x==nil and p and tonumber(p.cellX) then x=tonumber(p.cellX)*16 end
  if z==nil and p and tonumber(p.cellY) then z=tonumber(p.cellY)*16 end
  local mapId=ow and ow.map and ow.map.id or n.mapId
  if x~=nil and z~=nil then return x,z,p,mapId end

  local state=T._voxelState; p=state and state.player
  x=p and tonumber(p.px or p.x); z=p and tonumber(p.py or p.y)
  if x==nil and p and tonumber(p.cellX) then x=tonumber(p.cellX)*16 end
  if z==nil and p and tonumber(p.cellY) then z=tonumber(p.cellY)*16 end
  if x==nil and n.playerPosKnown then x=tonumber(n.playerWorldX) end
  if z==nil and n.playerPosKnown then z=tonumber(n.playerWorldY) end
  return x,z,p,mapId
end
local function flatSample(x,z)
  local F=req("FlatWorldInteraction")
  if F and F.ready and F.ready() and F.sampleAt then return F.sampleAt(x,z,flatScratch) end
  flatScratch.water,flatScratch.solid,flatScratch.canopy,flatScratch.roof=false,false,false,false
  flatScratch.shelter,flatScratch.drag,flatScratch.groundY=0,1,0
  return flatScratch
end
local function windDir()
  local W=req("WindEngine")
  if W and W.direction then local ok,x,z=pcall(W.direction); if ok and tonumber(x) and tonumber(z) then return x,z end end
  local p=W and W.peek and W.peek() or nil
  if p then return tonumber(p.x) or 1,tonumber(p.z) or 0 end
  return 1,0
end

local function gameObject()
  if mod and type(mod.game)=="table" then return mod.game end
  local ok,g=pcall(require,"src.core.Game"); if ok then return g end
end
local function validCell(v)
  v=tonumber(v); return v and v==math.floor(v) and v>=0 and v<65536
end
local function mapApi()
  local ok,m=pcall(require,"src.world.Map")
  return ok and type(m)=="table" and m or nil
end
local function mapDef(mapId)
  local g=gameObject(); local data=g and g.data or nil
  return data and data.maps and data.maps[mapId] or nil,data
end
local function tilesetFor(def,data)
  if not def then return nil end
  local id=def.tileset
  if data then
    if type(data.tilesets)=="table" and data.tilesets[id]~=nil then return data.tilesets[id] end
    if type(data.field)=="table" and type(data.field.tilesets)=="table" and data.field.tilesets[id]~=nil then return data.field.tilesets[id] end
  end
  return id
end
local function mapDims(def)
  local w=tonumber(def and (def.widthCells or def.width or def.w))
  local h=tonumber(def and (def.heightCells or def.height or def.h))
  if not w or not h then return nil,nil end
  w,h=math.floor(w),math.floor(h)
  if w<1 or h<1 or w>512 or h>512 then return nil,nil end
  return w,h
end
local function mapOutside(mapId,def,data,Map)
  if not def then return false end
  local C=req("Config"); local cc=C and C.get and C.get() or {}
  if type(cc.indoorMaps)=="table" and cc.indoorMaps[mapId] then return false end
  if Map and type(Map.isOutside)=="function" then
    local outsideTilesets=data and data.field and data.field.outsideTilesets or nil
    local ok,v=pcall(Map.isOutside,def,outsideTilesets)
    if ok and type(v)=="boolean" then return v end
  end
  if Map and type(Map.isOutdoor)=="function" then
    local ok,v=pcall(Map.isOutdoor,def)
    if ok and type(v)=="boolean" then return v end
  end
  local ts=tostring(def.tileset or ""):upper()
  return def.outdoor==true or ts=="OVERWORLD" or ts=="PLATEAU" or def.outside==true
end
local function warpCell(def,x,y)
  for _,w in ipairs(def and def.warps or {}) do
    if tonumber(w.x)==x and tonumber(w.y)==y then return true end
  end
  return false
end
local function cellWater(Map,def,tileset,x,y)
  if not (Map and type(Map.defIsWaterCell)=="function") then return false end
  local ok,v=pcall(Map.defIsWaterCell,def,tileset,x,y)
  return ok and v and true or false
end
local function cellPassable(Map,def,tileset,x,y,surfing)
  if Map and type(Map.defPassable)=="function" then
    local ok,v=pcall(Map.defPassable,def,tileset,x,y,surfing and true or false)
    if ok and type(v)=="boolean" then return v end
  end
  if Map and type(Map.defIsWalkableCell)=="function" then
    local ok,v=pcall(Map.defIsWalkableCell,def,tileset,x,y)
    if ok and v then return true end
  end
  return surfing and cellWater(Map,def,tileset,x,y) or false
end
local function cellTraversable(Map,def,tileset,x,y,surfAllowed)
  -- Walking always remains valid on ordinary ground. When Surf is currently
  -- legal, water cells join the same reachability graph so an island/shore can
  -- qualify only if the player can genuinely leave it by swimming.
  if cellPassable(Map,def,tileset,x,y,false) then return true end
  return surfAllowed and cellWater(Map,def,tileset,x,y) and cellPassable(Map,def,tileset,x,y,true) or false
end
local function directionOf(k,c)
  local d=tostring((type(c)=="table" and (c.direction or c.dir or c.side)) or k or ""):lower()
  if d=="north" then d="up" elseif d=="south" then d="down" elseif d=="west" then d="left" elseif d=="east" then d="right" end
  if d=="up" or d=="down" or d=="left" or d=="right" then return d end
end
local function connectionMap(c)
  if type(c)~="table" then return nil end
  local v=c.mapId or c.map or c.to or c.destination or c.dest or c.target
  if type(v)=="table" then v=v.id or v.mapId end
  return type(v)=="string" and v or nil
end
local function connectedExit(mapId,def,data,Map,x,y,surfAllowed)
  local w,h=mapDims(def); if not w then return false end
  for k,c in pairs(def.connections or {}) do
    local dir=directionOf(k,c)
    local atEdge=(dir=="up" and y==0) or (dir=="down" and y==h-1) or (dir=="left" and x==0) or (dir=="right" and x==w-1)
    if dir and atEdge then
      local destId=connectionMap(c); local dd=destId and data and data.maps and data.maps[destId] or nil
      if destId and dd and mapOutside(destId,dd,data,Map) then
        local dw,dh=mapDims(dd); local dts=tilesetFor(dd,data)
        if dw and dts~=nil then
          local off=(tonumber(c.offset) or 0)*2
          local dx,dy
          if dir=="up" then dx=x-off;dy=dh-1
          elseif dir=="down" then dx=x-off;dy=0
          elseif dir=="left" then dx=dw-1;dy=y-off
          else dx=0;dy=y-off end
          dx=math.max(0,math.min(dw-1,math.floor(dx)));dy=math.max(0,math.min(dh-1,math.floor(dy)))
          if cellTraversable(Map,dd,dts,dx,dy,surfAllowed) then return true,destId,dx,dy end
        end
      end
    end
  end
  return false
end
local function safeCache()
  T._safeCache=T._safeCache or {}; return T._safeCache
end
function T.validateLanding(mapId,x,y,mode)
  if type(mapId)~="string" or not validCell(x) or not validCell(y) then return false,"bad cell" end
  x,y=math.floor(x),math.floor(y);mode=(mode=="water") and "water" or "land"
  local surfAllowed=T.hasSurf and T.hasSurf() or false
  if mode=="water" and not surfAllowed then return false,"Surf unavailable" end
  local ck=mapId..":"..x..":"..y..":"..mode..":"..(surfAllowed and "surf" or "walk"); local cache=safeCache(); if cache[ck]~=nil then return cache[ck],cache[ck] and mode or "unsafe" end
  local def,data=mapDef(mapId);local Map=mapApi();local w,h=mapDims(def)
  if not (def and Map and w and mapOutside(mapId,def,data,Map)) then cache[ck]=false;return false,"not outdoor" end
  if x>=w or y>=h or warpCell(def,x,y) then cache[ck]=false;return false,"edge/warp entrance" end
  local ts=tilesetFor(def,data);if ts==nil then cache[ck]=false;return false,"tileset unavailable" end
  local isWater=cellWater(Map,def,ts,x,y)
  if (mode=="water")~=isWater then cache[ck]=false;return false,"surface mismatch" end
  if not cellTraversable(Map,def,ts,x,y,surfAllowed) then cache[ck]=false;return false,"blocked" end

  -- Bounded flood fill from the exact landing cell. A destination is accepted
  -- only when this connected component can physically walk/surf to a real edge
  -- connection whose destination is also an outdoor map. Empty-looking ground
  -- and cave/building warp cells therefore never count as proof of escape.
  local qx,qy={x},{y};local head=1;local seen={[y*w+x]=true};local limit=math.min(w*h,65536);local visited=0
  while head<=#qx and visited<limit do
    local cx,cy=qx[head],qy[head];head=head+1;visited=visited+1
    if connectedExit(mapId,def,data,Map,cx,cy,surfAllowed) then cache[ck]=true;return true,mode end
    local nx,ny
    for i=1,4 do
      if i==1 then nx,ny=cx+1,cy elseif i==2 then nx,ny=cx-1,cy elseif i==3 then nx,ny=cx,cy+1 else nx,ny=cx,cy-1 end
      if nx>=0 and ny>=0 and nx<w and ny<h then
        local sk=ny*w+nx
        if not seen[sk] and cellTraversable(Map,def,ts,nx,ny,surfAllowed) then seen[sk]=true;qx[#qx+1]=nx;qy[#qy+1]=ny end
      end
    end
  end
  cache[ck]=false;return false,"no outdoor exit"
end
local function landingTable()
  if type(T._landings)=="table" then return T._landings end
  local t={}
  pcall(function()
    local saved=mod.save:get("tornadoLandings",{})
    if type(saved)=="table" then t=saved end
  end)
  T._landings=t; return t
end
function T.hasSurf()
  local S=req("Scene"); local ow=S and S.overworld and S.overworld() or nil
  if not ow then return false end
  if ow.player and ow.player.surfing then return true end
  if type(ow.partyKnows)=="function" then
    local ok,v=pcall(ow.partyKnows,ow,"SURF");if ok and v then return true end
  end
  local world=mod and mod.world
  if world and type(world.availableFieldActions)=="function" then
    local ok,list=pcall(world.availableFieldActions,world)
    if ok and type(list)=="table" then for _,a in ipairs(list) do local id=type(a)=="table" and (a.id or a.action) or a;if tostring(id):lower()=="surf" then return true end end end
  end
  return false
end
function T.rememberLanding(mapId,x,y,facing,isWater)
  if type(mapId)~="string" or not validCell(x) or not validCell(y) then return false end
  x,y=math.floor(x),math.floor(y);local mode=isWater and "water" or "land"
  local ok=T.validateLanding(mapId,x,y,mode);if not ok then return false end
  local t=landingTable();local row=t[mapId]
  if type(row)~="table" then row={};t[mapId]=row end
  -- Migrate the old single-cell shape without trusting it. It is revalidated
  -- below by landingFor before it can ever become a destination.
  if row.x~=nil and row.y~=nil and row.land==nil then row.land={x=row.x,y=row.y,facing=row.facing};row.x,row.y,row.facing=nil,nil,nil end
  local old=row[mode]
  if type(old)=="table" and old.x==x and old.y==y then return true end
  row[mode]={x=x,y=y,facing=tostring(facing or "down")}
  pcall(function() mod.save:set("tornadoLandings",t) end)
  return true
end
local function verifiedSaved(mapId,mode)
  local row=landingTable()[mapId];if type(row)~="table" then return nil end
  if row.x~=nil and row.y~=nil and row.land==nil then row.land={x=row.x,y=row.y,facing=row.facing} end
  local s=row[mode];if type(s)~="table" or not validCell(s.x) or not validCell(s.y) then return nil end
  if not T.validateLanding(mapId,s.x,s.y,mode) then return nil end
  return {x=math.floor(s.x),y=math.floor(s.y),facing=tostring(s.facing or "down"),source="remembered",mode=mode}
end
local function derivedConnectedLanding(mapId,def,data,Map)
  local w,h=mapDims(def);local ts=tilesetFor(def,data)
  if not (w and h and ts~=nil) then return nil end
  local surfAllowed=T.hasSurf and T.hasSurf() or false
  -- A visited outdoor map does not have to have been observed by Weather FX.
  -- Seed from REAL outdoor connections, then walk inward through the same
  -- passability graph validateLanding uses. The first ordinary non-warp land
  -- cell is preferred; water is a Surf-only fallback.
  local qx,qy,head,seen={}, {},1,{}
  local function seed(x,y)
    if x<0 or y<0 or x>=w or y>=h then return end
    local k=y*w+x;if seen[k] then return end
    if not cellTraversable(Map,def,ts,x,y,surfAllowed) then return end
    if not connectedExit(mapId,def,data,Map,x,y,surfAllowed) then return end
    seen[k]=true;qx[#qx+1]=x;qy[#qy+1]=y
  end
  for x=0,w-1 do seed(x,0);if h>1 then seed(x,h-1) end end
  for y=1,h-2 do seed(0,y);if w>1 then seed(w-1,y) end end
  local waterFallback
  while head<=#qx do
    local x,y=qx[head],qy[head];head=head+1
    local atEdge=x==0 or y==0 or x==w-1 or y==h-1
    local water=cellWater(Map,def,ts,x,y)
    if not atEdge and not warpCell(def,x,y) then
      local row={x=x,y=y,facing="down",source="connection",mode=water and "water" or "land"}
      if not water then if T.validateLanding(mapId,x,y,"land") then return row end
      elseif surfAllowed and not waterFallback and T.validateLanding(mapId,x,y,"water") then waterFallback=row end
    end
    local n={{x+1,y},{x-1,y},{x,y+1},{x,y-1}}
    for i=1,4 do local nx,ny=n[i][1],n[i][2]
      if nx>=0 and ny>=0 and nx<w and ny<h then local k=ny*w+nx
        if not seen[k] and cellTraversable(Map,def,ts,nx,ny,surfAllowed) then seen[k]=true;qx[#qx+1]=nx;qy[#qy+1]=ny end
      end
    end
  end
  return waterFallback
end

function T.landingFor(mapId)
  if type(mapId)~="string" then return nil end
  local land=verifiedSaved(mapId,"land");if land then return land end
  local def,data=mapDef(mapId);local Map=mapApi();if not (def and Map and mapOutside(mapId,def,data,Map)) then return nil end
  -- Engine-authored fly coordinates are the only non-observed fallback, and
  -- they still have to pass the same exact-cell escape proof. Generic map
  -- warps are deliberately NEVER used: those are often doors/cave entrances.
  local fw=data and data.field and data.field.flyWarps and data.field.flyWarps[mapId] or nil
  if fw and validCell(fw.x) and validCell(fw.y) then
    local ts=tilesetFor(def,data);local water=ts~=nil and cellWater(Map,def,ts,math.floor(fw.x),math.floor(fw.y))
    local mode=water and "water" or "land"
    if (mode=="land" or T.hasSurf()) and T.validateLanding(mapId,fw.x,fw.y,mode) then
      return {x=math.floor(fw.x),y=math.floor(fw.y),facing=tostring(fw.facing or "down"),source="fly",mode=mode}
    end
  end
  local derived=derivedConnectedLanding(mapId,def,data,Map);if derived then return derived end
  if T.hasSurf() then local water=verifiedSaved(mapId,"water");if water then return water end end
  return nil
end

local function liveMapWorldSize(map)
  if type(map)~="table" then return nil,nil end
  local w=tonumber(map.widthCells)
  local h=tonumber(map.heightCells)
  if (not w or w<=0) and map.def then
    local q=tonumber(map.def.widthCells); if q and q>0 then w=q else q=tonumber(map.def.width); if q and q>0 then w=q*2 end end
  end
  if (not h or h<=0) and map.def then
    local q=tonumber(map.def.heightCells); if q and q>0 then h=q else q=tonumber(map.def.height); if q and q>0 then h=q*2 end end
  end
  if (not w or not h or w<=0 or h<=0) and map.id then
    -- Some host/test snapshots expose only a live map id. Fall back to the
    -- canonical map definition so current-map behavior remains identical and
    -- persistent roaming does not mistake a valid visible map for offscreen.
    local def=mapDef(tostring(map.id))
    if def then
      if not w or w<=0 then
        local q=tonumber(def.widthCells); if q and q>0 then w=q else q=tonumber(def.width or def.w); if q and q>0 then w=q*2 end end
      end
      if not h or h<=0 then
        local q=tonumber(def.heightCells); if q and q>0 then h=q else q=tonumber(def.height or def.h); if q and q>0 then h=q*2 end end
      end
    end
  end
  if not w or not h or w<=0 or h<=0 then return nil,nil end
  return w*16,h*16
end
local function liveRegionFor(state,mapId)
  if type(state)~="table" or not mapId then return nil end
  if state.map and tostring(state.map.id)==tostring(mapId) then
    local w,h=liveMapWorldSize(state.map); if w then return {id=tostring(mapId),map=state.map,ox=0,oz=0,w=w,h=h} end
  end
  for _,nb in ipairs(state.neighbors or {}) do
    if nb and nb.map and tostring(nb.map.id)==tostring(mapId) then
      local w,h=liveMapWorldSize(nb.map); if w then return {id=tostring(mapId),map=nb.map,ox=tonumber(nb.ox) or tonumber(nb.offsetX) or 0,oz=tonumber(nb.oy) or tonumber(nb.oz) or tonumber(nb.offsetZ) or 0,w=w,h=h} end
    end
  end
end
local function liveRegionAt(state,x,z)
  if type(state)~="table" then return nil end
  local function hit(map,ox,oz)
    local w,h=liveMapWorldSize(map); if not w then return nil end
    ox,oz=tonumber(ox) or 0,tonumber(oz) or 0
    if x>=ox and z>=oz and x<ox+w and z<oz+h then return {id=tostring(map.id),map=map,ox=ox,oz=oz,w=w,h=h} end
  end
  local r=state.map and hit(state.map,0,0); if r then return r end
  for _,nb in ipairs(state.neighbors or {}) do
    if nb and nb.map then r=hit(nb.map,nb.ox or nb.offsetX,nb.oy or nb.oz or nb.offsetZ); if r then return r end end
  end
end

-- Persistent funnels need a map-local position as well as the current voxel
-- root-frame x/z. The root frame is intentionally only current + immediate
-- neighbors, so relying on x/z alone freezes a tornado as soon as the player
-- gets two connected maps away. mapX/mapZ let the storm continue through the
-- authored outdoor connection graph while it is not being rendered.
local function defWorldSize(def)
  if type(def)~="table" then return nil,nil end
  local wc=tonumber(def.widthCells); local hc=tonumber(def.heightCells)
  if not wc then local w=tonumber(def.width or def.w); if w then wc=w*2 end end
  if not hc then local h=tonumber(def.height or def.h); if h then hc=h*2 end end
  if not wc or not hc or wc<=0 or hc<=0 or wc>2048 or hc>2048 then return nil,nil end
  return wc*16,hc*16
end

local function connectionFor(def,dir)
  for k,c in pairs(def and def.connections or {}) do
    if directionOf(k,c)==dir then
      local dest=connectionMap(c)
      if dest then return c,dest end
    end
  end
end

local function reflectAtBoundary(r,dir)
  local a=tonumber(r.heading) or 0
  if dir=="left" or dir=="right" then a=pi-a else a=-a end
  r.heading=a+(rnd()-.5)*.18
end

local function resolveMapLocal(r,lx,lz)
  local hops=0
  while hops<4 do
    local def,data=mapDef(r.mapId); local w,h=defWorldSize(def)
    if not w then r.mapX,r.mapZ=lx,lz; return true,false end
    if lx>=0 and lz>=0 and lx<w and lz<h then r.mapX,r.mapZ=lx,lz; return true,false end

    local dir
    if lx<0 or lx>=w then dir=(lx<0) and "left" or "right"
    elseif lz<0 or lz>=h then dir=(lz<0) and "up" or "down" end
    local c,dest=connectionFor(def,dir)
    local ddef=dest and data and data.maps and data.maps[dest] or nil
    local dw,dh=defWorldSize(ddef)
    local Map=mapApi()
    if not (c and dest and ddef and dw and mapOutside(dest,ddef,data,Map)) then
      lx=clamp(lx,.001,w-.001); lz=clamp(lz,.001,h-.001)
      reflectAtBoundary(r,dir); r.mapX,r.mapZ=lx,lz
      return false,false
    end

    local offCells=tonumber(c.offsetCells or c.cellOffset)
    local offPx=(offCells and offCells*16) or ((tonumber(c.offset) or 0)*32)
    local nx,nz
    if dir=="right" then nx=lx-w; nz=lz-offPx
    elseif dir=="left" then nx=dw+lx; nz=lz-offPx
    elseif dir=="down" then nx=lx-offPx; nz=lz-h
    else nx=lx-offPx; nz=dh+lz end

    -- A connection offset can expose only part of the destination edge. If
    -- this exact trajectory misses that overlap, it hit a real outer boundary
    -- rather than a usable seam; bounce instead of teleporting sideways.
    if nx<0 or nz<0 or nx>=dw or nz>=dh then
      lx=clamp(lx,.001,w-.001); lz=clamp(lz,.001,h-.001)
      reflectAtBoundary(r,dir); r.mapX,r.mapZ=lx,lz
      return false,false
    end

    r.mapId=tostring(dest); r.mapCrossings=(r.mapCrossings or 0)+1
    if r.offscreen then r.offscreenCrossings=(r.offscreenCrossings or 0)+1 end
    lx,lz=nx,nz; hops=hops+1
    T.lastReason=r.offscreen and "remote tornado crossed outdoor map connection" or "tornado crossed outdoor map connection"
  end
  r.mapX,r.mapZ=lx,lz
  return true,true
end

local function projectFromMapLocal(r,state)
  local reg=liveRegionFor(state,r.mapId)
  if not reg then r.offscreen=true; return false end
  if tonumber(r.mapX) and tonumber(r.mapZ) then
    r.x=(reg.ox or 0)+r.mapX; r.z=(reg.oz or 0)+r.mapZ
  else
    r.mapX=(tonumber(r.x) or 0)-(reg.ox or 0)
    r.mapZ=(tonumber(r.z) or 0)-(reg.oz or 0)
  end
  r.offscreen=false
  return true
end

local function updateRemoteSurface(r,dt)
  local def,data=mapDef(r.mapId); local Map=mapApi()
  local water=false
  if def and Map and tonumber(r.mapX) and tonumber(r.mapZ) then
    local ts=tilesetFor(def,data)
    local cx,cy=math.floor(r.mapX/16),math.floor(r.mapZ/16)
    if ts~=nil then water=cellWater(Map,def,ts,cx,cy) end
  end
  local target=(water and cfg().waterTwister~=false) and 1 or 0
  r.waterSurface=target>0
  local tau=target>0 and .32 or .90
  r.waterBlend=(tonumber(r.waterBlend) or 0)+(target-(tonumber(r.waterBlend) or 0))*(1-math.exp(-math.max(0.001,tonumber(dt) or 0.25)/tau))
end

local function moveOffscreen(r,dt)
  local wx,wz=windDir(); local targetAng=atan2(wz,wx)
  r.wander=(r.wander or 0)+dt*.19
  targetAng=targetAng+sin(r.wander+r.id*.71)*.75
  local dAng=(targetAng-r.heading+pi)%(2*pi)-pi
  r.heading=r.heading+dAng*math.min(1,dt*.42)
  local speed=r.speed*(r.stage=="forming" and (.30+.70*smooth(r.age/r.formation)) or 1)
  local lx=(tonumber(r.mapX) or tonumber(r.x) or 0)+cos(r.heading)*speed*dt
  local lz=(tonumber(r.mapZ) or tonumber(r.z) or 0)+sin(r.heading)*speed*dt
  resolveMapLocal(r,lx,lz)
  updateRemoteSurface(r,dt)

  -- The crossing may have brought the funnel into the current map or an
  -- immediate rendered neighbor. Re-project the SAME entity immediately so
  -- the next draw sees it enter at the correct map edge, without respawning.
  projectFromMapLocal(r,T._voxelState)
end
local function worldSample(x,z)
  local q=flatSample(x,z)
  local reg=liveRegionAt(T._voxelState,x,z);local map=reg and reg.map
  if map and type(map.isWaterCell)=="function" then
    local cx=math.floor((x-(reg.ox or 0))/16);local cy=math.floor((z-(reg.oz or 0))/16)
    local ok,v=pcall(map.isWaterCell,map,cx,cy);if ok then q.water=v and true or false end
  end
  if q.water then q.solid=false end
  return q
end

local function snapshotRootFrame(state)
  local newId=state and state.map and state.map.id and tostring(state.map.id) or nil
  local oldId=T._rootMapId
  if oldId and newId and oldId~=newId then
    local row=T._rootNeighborOffsets and T._rootNeighborOffsets[newId]
    if row then
      local dx,dz=-(tonumber(row[1]) or 0),-(tonumber(row[2]) or 0)
      for _,r in ipairs(T.active) do
        r.x=(tonumber(r.x) or 0)+dx
        r.z=(tonumber(r.z) or 0)+dz
      end
      T._rootRebases=(T._rootRebases or 0)+1
      T.lastReason="outdoor map root changed; tornado field persisted"
    end
  end
  T._rootMapId=newId or oldId
  local snap=T._rootNeighborOffsets or {};T._rootNeighborOffsets=snap
  for k in pairs(snap) do snap[k]=nil end
  for _,nb in ipairs(state and state.neighbors or {}) do
    local id=nb and nb.map and nb.map.id
    if id~=nil then
      local row=snap[tostring(id)] or {};snap[tostring(id)]=row
      row[1]=tonumber(nb.ox) or tonumber(nb.offsetX) or 0
      row[2]=tonumber(nb.oy) or tonumber(nb.oz) or tonumber(nb.offsetZ) or 0
    end
  end
end

local function refreshTornadoMap(r,oldX,oldZ)
  local state=T._voxelState
  if not (state and state.map) then return true end
  local from=liveRegionFor(state,r.mapId)
  -- Older/alternate voxel hosts may omit widthCells/def dimensions from the
  -- public render snapshot. In that case we cannot prove a live render edge;
  -- keep historical unconstrained motion and still remember map-local x/z.
  local rw=liveMapWorldSize(state.map)
  local anyRegion=rw~=nil
  if not anyRegion then
    for _,nb in ipairs(state.neighbors or {}) do if nb and nb.map and liveMapWorldSize(nb.map) then anyRegion=true;break end end
  end
  if not anyRegion then
    if from then r.mapX=r.x-(from.ox or 0);r.mapZ=r.z-(from.oz or 0) end
    return true
  end
  local reg=liveRegionAt(state,r.x,r.z)
  if reg then
    if r.mapId~=reg.id then
      r.mapId=reg.id
      r.mapCrossings=(r.mapCrossings or 0)+1
      T.lastReason="tornado crossed outdoor map connection"
    end
    r.mapX=r.x-(reg.ox or 0);r.mapZ=r.z-(reg.oz or 0);r.offscreen=false
    return true
  end

  -- Leaving current+neighbor rendering is not the same as leaving the world.
  -- Resolve the attempted point against the source map's authored connection
  -- graph. A valid second-hop outdoor seam becomes remote simulation; only a
  -- true unconnected outer edge reflects the funnel.
  if from then
    local lx=r.x-(from.ox or 0); local lz=r.z-(from.oz or 0)
    r.offscreen=true
    local ok=resolveMapLocal(r,lx,lz)
    if ok then
      projectFromMapLocal(r,state)
      return true
    end
    r.offscreen=false;r.x,r.z=oldX,oldZ
    return false
  end

  r.x,r.z=oldX,oldZ
  r.heading=(tonumber(r.heading) or 0)+pi*(.48+(rnd()-.5)*.18)
  return false
end

function T.observeVoxelState(state)
  if type(state)~="table" then return end
  snapshotRootFrame(state)
  T._voxelState=state
  for _,r in ipairs(T.active) do projectFromMapLocal(r,state) end
  local p=state.player; local mapId=state.map and state.map.id
  local S=req("Scene"); local n=S and S.now or {}
  if mapId and p and n.outdoor and validCell(p.cellX) and validCell(p.cellY) then
    local water=p.surfing and true or false
    if not water then local q=flatSample((p.cellX+.5)*16,(p.cellY+.5)*16);water=q and q.water and true or false end
    T.rememberLanding(mapId,p.cellX,p.cellY,p.facing,water)
  end
end
function T.observeCurrent(dt)
  T._observeTimer=(T._observeTimer or 0)+(tonumber(dt) or 0);if T._observeTimer<1 then return end;T._observeTimer=0
  local S=req("Scene");local n=S and S.now or {};local ow=S and S.overworld and S.overworld() or nil;local p=ow and ow.player;local map=ow and ow.map
  local mapId=map and map.id or n.mapId
  if not (n.outdoor and mapId and p and validCell(p.cellX) and validCell(p.cellY)) then return end
  local water=p.surfing and true or false
  if map and type(map.isWaterCell)=="function" then local ok,v=pcall(map.isWaterCell,map,p.cellX,p.cellY);if ok then water=v and true or false end end
  T.rememberLanding(mapId,p.cellX,p.cellY,p.facing,water)
end

-- Every actually visited outdoor map that also has a proven, currently usable
-- escape-safe landing. Gen1Recomp's save.visited is NOT a general map-history
-- table: it only records fly-eligible towns. Weather FX already persists a
-- validated landing whenever it observes the player on an outdoor map, so the
-- tornado history is the authoritative all-outdoor visited set. Engine town
-- visits are merged in for old saves that predate tornadoLandings.
function T.destinations(here)
  local out,added={},{}
  local function consider(mapId)
    if type(mapId)~="string" or mapId==here or added[mapId] then return end
    if T.landingFor(mapId) then added[mapId]=true;out[#out+1]=mapId end
  end
  pcall(function()
    for mapId,row in pairs(landingTable()) do
      if type(row)=="table" then consider(mapId) end
    end
    local g=gameObject(); local visited=g and g.save and g.save.visited
    if type(visited)=="table" then
      for mapId,seen in pairs(visited) do if seen then consider(mapId) end end
    end
  end)
  table.sort(out); return out
end

function T.remember(mapId,x,y,facing,surfing)
  pcall(function()
    mod.save:set("tornadoFrom",mapId);mod.save:set("tornadoFromX",x);mod.save:set("tornadoFromY",y)
    mod.save:set("tornadoFromFacing",tostring(facing or "down"));mod.save:set("tornadoFromSurf",surfing and true or false)
  end)
end
function T.origin()
  local ok,a,b,c,d,e=pcall(function()
    return mod.save:get("tornadoFrom",nil),mod.save:get("tornadoFromX",nil),mod.save:get("tornadoFromY",nil),mod.save:get("tornadoFromFacing","down"),mod.save:get("tornadoFromSurf",false)
  end)
  if ok then return a,b,c,d,e end
end
local function liveOverworld()
  local world=mod and mod.world
  if world and type(world.overworld)=="function" then
    local ok,ow=pcall(world.overworld,world)
    if ok and type(ow)=="table" and ow.map then return ow end
  end
  local S=req("Scene")
  local ok,ow=pcall(function() return S and S.overworld and S.overworld() or nil end)
  if ok and type(ow)=="table" and ow.map then return ow end
  return nil
end

-- Tornado has its own departure/blackout/arrival presentation, so routing the
-- carry through the engine's second visual warp transition is unnecessary and
-- can leave a request queued behind another state. Prefer the live world's
-- synchronous map-change primitive and PROVE the destination became active.
-- Gen 2 exposes warpToMapId; Gen 1 exposes setMap. The public mod.world warp is
-- retained only as a compatibility fallback for hosts that hide both.
function T._warpTo(destination,landing,onDone)
  if type(destination)~="string" or not landing or not validCell(landing.x) or not validCell(landing.y) then return false,"invalid landing" end
  local fired=false
  local function finished()
    if fired then return end;fired=true
    if type(onDone)=="function" then pcall(onDone,destination,landing) end
  end
  local ow=liveOverworld()
  if ow and ow.map and tostring(ow.map.id)==tostring(destination) then return false,"destination is current map" end

  -- Gen 2 direct world transfer.
  if ow and type(ow.warpToMapId)=="function" then
    local ok,r1,why=pcall(ow.warpToMapId,ow,destination,landing.x,landing.y,landing.facing or "down")
    if ok and r1~=false and ow.map and tostring(ow.map.id)==tostring(destination) then finished();return true,"direct gen2 transfer" end
    if not ok then why=r1 end
  end

  -- Gen 1 direct map swap. This is the same map loader startWarpTo reaches at
  -- its transition midpoint, but the tornado already supplies that midpoint.
  if ow and type(ow.setMap)=="function" then
    local p=ow.player
    if p and landing.mode~="water" and p.surfing then
      p.surfing=false
      if type(ow.syncSurfingPikachu)=="function" then pcall(ow.syncSurfingPikachu,ow) end
    end
    if type(ow.rememberOutdoor)=="function" and ow.map and ow.map.id then
      pcall(ow.rememberOutdoor,ow,ow.map.id,p and p.cellX,p and p.cellY)
    end
    local ok,err=pcall(ow.setMap,ow,destination,landing.x,landing.y,landing.facing or "down",{via="warp",keepMusic=true})
    if ok and ow.map and tostring(ow.map.id)==tostring(destination) then finished();return true,"direct gen1 transfer" end
    if not ok and mod.log and mod.log.warn then mod.log:warn("tornado direct map transfer failed: %s",tostring(err)) end
  end

  local world=mod and mod.world
  if world and type(world.warpTo)=="function" then
    local ok,r1,why=pcall(world.warpTo,world,destination,landing.x,landing.y,landing.facing or "down",{keepMusic=true,onDone=finished})
    if ok and r1 then return true,"public warp pending" end
    return false,ok and (why or r1 or "warp refused") or r1
  end
  if ow and type(ow.startWarpTo)=="function" then
    local ok,err=pcall(ow.startWarpTo,ow,destination,landing.x,landing.y,landing.facing or "down",finished,{via="warp",keepMusic=true})
    return ok,ok and "private warp pending" or tostring(err or "private warp failed")
  end
  return false,"warp unavailable"
end
function T.activateSurfLanding(landing)
  if not landing or landing.mode~="water" then return true end
  local S=req("Scene");local ow=S and S.overworld and S.overworld() or nil;local p=ow and ow.player;local map=ow and ow.map
  if not (ow and p and map and type(map.isWaterCell)=="function" and type(ow.partyKnows)=="function") then return false end
  local okWater,onWater=pcall(map.isWaterCell,map,p.cellX,p.cellY);if not (okWater and onWater) then return false end
  local okSurf,has=pcall(ow.partyKnows,ow,"SURF");if not (okSurf and has) then return false end
  p.surfing=true
  local g=gameObject();if g and type(g.save)=="table" then g.save.onBike=false;g.save.forcedBike=false end
  if type(ow.syncSurfingPikachu)=="function" then pcall(ow.syncSurfingPikachu,ow) end
  return p.surfing==true
end
function T.emergencyReturn(r)
  local m,x,y,facing,surfing=T.origin();if type(m)~="string" or not validCell(x) or not validCell(y) then return false end
  local ok=T._warpTo(m,{x=x,y=y,facing=facing or "down",mode=surfing and "water" or "land"})
  if ok then r.returnMap=m;r.returnSurf=surfing and true or false;r.stage="returning";r.transferAge=0;T.lastReason="unsafe landing rejected / returning" end
  return ok
end
function T.carry(destination,onDone,landingOverride)
  local landing=landingOverride or T.landingFor(destination)
  if not landing then T.lastReason="no escape-safe outdoor destination"; return false end
  if landing.mode=="water" and not T.hasSurf() then T.lastReason="water destination needs Surf"; return false end
  local S=req("Scene"); local ow=S and S.overworld and S.overworld() or nil
  local here=ow and ow.map and ow.map.id
  local p=ow and ow.player;local px=p and p.cellX;local py=p and p.cellY
  T.remember(here,px,py,p and p.facing,p and p.surfing)
  local ok,why=T._warpTo(destination,landing,onDone)
  if ok then
    T._pendingLanding=landing
    if mod.log and mod.log.info then mod.log:info("tornado carrying player from %s to escape-safe outdoor map %s",tostring(here),tostring(destination)) end
    T.lastReason="cross-map transfer started"; return true
  end
  T.lastReason="warp refused: "..tostring(why or "unknown")
  if mod.log and mod.log.warn then mod.log:warn("tornado carry refused: %s",T.lastReason) end
  return false
end
function T.windy(def)
  local id=tostring(type(def)=="table" and def.id or def or ""):upper()
  local c=cfg()
  return id=="GALE" or id=="STRONG_WINDS" or (c.sandstorms~=false and (id=="SANDSTORM" or id=="DUSTSTORM"))
end

local function alreadySeeker()
  if T._carry then return true end
  for i=1,#T.active do if T.active[i].seeker then return true end end
  return false
end
local function safeSpawn(px,pz,dist,ang)
  local x,z=px+cos(ang)*dist,pz+sin(ang)*dist
  for _=0,7 do
    local q=worldSample(x,z)
    if not q.solid or q.water then return x,z,q end
    ang=ang+pi*.25; x,z=px+cos(ang)*dist,pz+sin(ang)*dist
  end
  return x,z,worldSample(x,z)
end

function T.spawn(forceRoamer)
  if not (settingOn() and strict3d() and galeNow() and outdoors()) then return nil end
  local c=cfg(); local maxActive=math.max(1,math.min(4,tonumber(c.maxActive) or 3))
  if #T.active>=maxActive then return nil end
  local px,pz,_,mapId=playerInfo(); if not px or not pz then return nil end
  local dmin=tonumber(c.spawnDistanceMin) or 150; local dmax=math.max(dmin,tonumber(c.spawnDistanceMax) or 250)
  local dist=range(dmin,dmax); local ang=range(0,pi*2); local x,z,q=safeSpawn(px,pz,dist,ang)
  local destinations=T.destinations(mapId)
  -- minVisited counts the current map too; requiring #destinations>=minVisited
  -- would accidentally demand one additional visited map.
  local canCarry=#destinations>0
  local carryChance=clamp(tonumber(c.carryChance) or .10,0,1)
  local Settings=req("Settings")
  if Settings and Settings.tornadoPickupChance then
    local ok,v=pcall(Settings.tornadoPickupChance); if ok and tonumber(v) then carryChance=clamp(v,0,1) end
  end
  local durationScale=1
  if Settings and Settings.tornadoDurationScale then
    local ok,v=pcall(Settings.tornadoDurationScale); if ok and tonumber(v) then durationScale=tonumber(v) end
  end
  local seeker=(not forceRoamer) and canCarry and not alreadySeeker() and rnd()<carryChance
  local wx,wz=windDir(); local wa=atan2(wz,wx)
  T.serial=T.serial+1
  local r={
    id=T.serial,x=x,z=z,mapId=mapId,mapX=x,mapZ=z,offscreen=false,age=0,roamAge=0,
    formation=math.max(2,tonumber(c.formationSeconds) or 8),
    roamFor=math.max(30,(tonumber(c.roamSeconds) or 180)*durationScale),
    ropeFor=math.max(3,tonumber(c.ropeSeconds) or 12),
    stage="forming",ropeAge=0,seeker=seeker,
    destination=seeker and destinations[irand(#destinations)] or nil,
    heading=wa+range(-.85,.85),speed=range(7.5,12.5),spin=range(3.7,5.5),
    waterBlend=(q and q.water) and 1 or 0,groundY=q and q.groundY or 0,
    wander=range(0,pi*2),seekAge=0,
  }
  T.active[#T.active+1]=r
  T.lastReason=seeker and "distant carry tornado forming" or "roaming tornado forming"
  return r
end

local function currentOverworld()
  local S=req("Scene");return S and S.overworld and S.overworld() or nil
end

-- Carry control ownership. Gen1Recomp's Player:handleInput and Voxel Nexus's
-- FreeMove.tick both honor player.inputLocked. The old movement.collision hook
-- only covered grid steps, so a free-camera/third-person player could continue
-- driving after Tornado had already entered pickup. Keep the engine-native lock
-- asserted for the entire 2D sweep or 3D airborne sequence, preserving whatever
-- lock state existed before Weather FX took ownership.
local function restoreControlLock()
  local l=T._controlLock
  if not l then return end
  if l.owner then pcall(function() l.owner.inputLocked=l.original and true or false end) end
  T._controlLock=nil
end
local function lockPlayerControls()
  local ow=currentOverworld();local p=ow and ow.player
  if not p then return false end
  local l=T._controlLock
  if not l or l.owner~=p then
    restoreControlLock()
    T._controlLock={owner=p,original=p.inputLocked and true or false}
  end
  p.inputLocked=true
  return true
end

local function beginCarry(r,px,pz,reason)
  if not r.destination or T._carry then r.seeker=false; return false end
  r.stage="pickup"; r.carryAge=0; r.x,r.z=px,pz; r.seekAge=0
  r.contactCarry=(reason=="touch") and true or false
  T._carry=r
  lockPlayerControls()
  T.lastReason=r.contactCarry and "player touched active tornado / suction pickup" or "player pickup"
  return true
end

-- Direct-contact rule: every sufficiently formed active 3D funnel is hazardous,
-- not only the rare seeker variant. If the player physically reaches the funnel
-- footprint, choose an already-visited, escape-safe outdoor destination and
-- start the same guarded suction/carry/relocation sequence. The random 10%
-- seeker chance still controls whether a tornado actively hunts the player; it
-- no longer controls whether touching an ordinary tornado is dangerous.
local function segmentOriginDistanceSq(ax,az,bx,bz)
  local vx,vz=bx-ax,bz-az;local vv=vx*vx+vz*vz
  if vv<=1e-9 then return bx*bx+bz*bz end
  local t=clamp(-(ax*vx+az*vz)/vv,0,1)
  local x,z=ax+vx*t,az+vz*t
  return x*x+z*z
end

local function tryTouchCarry(r,px,pz,mapId,prevPx,prevPz,oldRx,oldRz)
  if T._carry or not (px and pz) then return false end
  if mapId~=nil and r.mapId~=nil and tostring(mapId)~=tostring(r.mapId) then return false end
  if r.stage~="roam" and not (r.stage=="forming" and r.age>=r.formation*.85) then return false end

  -- The rendered ground circulation is intentionally much wider than the
  -- narrow condensation tube: dirt/debris reaches ~21 world px from the
  -- centre and the player sprite/body contributes roughly another half-cell.
  -- Treat visible body overlap as contact instead of requiring the player's
  -- anchor point to enter the old 14px core. Preserve any larger private host
  -- tuning, but never shrink below the physically visible footprint.
  local touchRadius=math.max(30,tonumber(cfg().touchRadius) or 14)
  local dx,dz=px-r.x,pz-r.z
  local hit=dx*dx+dz*dz<=touchRadius*touchRadius

  -- Swept relative-motion test prevents a fast/free-move player or moving
  -- funnel from crossing the hazardous footprint between two simulation
  -- samples without ever landing inside the radius at an endpoint.
  if not hit and prevPx and prevPz and oldRx and oldRz then
    local ax,az=prevPx-oldRx,prevPz-oldRz
    local bx,bz=px-r.x,pz-r.z
    hit=segmentOriginDistanceSq(ax,az,bx,bz)<=touchRadius*touchRadius
  end
  if not hit then return false end

  if not r.destination then
    local choices=T.destinations(mapId or r.mapId)
    if #choices==0 then
      T.lastReason="player touched tornado but no proven escape-safe visited destination exists"
      return false
    end
    r.destination=choices[irand(#choices)]
  end
  r.seeker=true
  return beginCarry(r,px,pz,"touch")
end
local function startRope(r)
  if r.stage~="rope" then r.stage="rope";r.ropeAge=0;r.seeker=false end
end
local function moveNormal(r,dt,px,pz,mapId,prevPx,prevPz)
  -- A funnel outside current+immediate-neighbor rendering is still a live
  -- weather entity. Continue it in its own map-local frame until it physically
  -- crosses back into a rendered map; never pin it to the player's load radius.
  local visibleReg=r.mapId and liveRegionFor(T._voxelState,r.mapId) or nil
  if T._voxelState and r.mapId and not visibleReg then
    r.offscreen=true
    moveOffscreen(r,dt)
    return
  end
  if visibleReg then
    -- While visible, preserve the established world-frame x/z as the motion
    -- authority and mirror it into persistent map-local storage. This keeps
    -- host integrations/debug tooling that legitimately adjust x/z compatible;
    -- map-local coordinates become authoritative only while the funnel is
    -- outside the current+neighbor render set or during a root re-projection.
    r.offscreen=false
    r.mapX=(tonumber(r.x) or 0)-(visibleReg.ox or 0)
    r.mapZ=(tonumber(r.z) or 0)-(visibleReg.oz or 0)
  end

  -- Ordinary roaming funnels use physical overlap. A committed 10% seeker has
  -- its own approach/pickup rule below so its successful hunt cannot be
  -- mislabeled as a walk-in collision merely because the visible footprints
  -- overlap on the final approach.
  if not r.seeker and tryTouchCarry(r,px,pz,mapId,prevPx,prevPz,r.x,r.z) then return end
  local oldX,oldZ=r.x,r.z
  local wx,wz=windDir(); local targetAng=atan2(wz,wx)
  local seekDistance
  if r.seeker and px and pz then
    local dx,dz=px-r.x,pz-r.z; local d=sqrt(dx*dx+dz*dz);seekDistance=d
    if d>1e-3 then targetAng=atan2(dz,dx) end
    r.seekAge=(r.seekAge or 0)+dt
    -- A seeker is an exceptional storm event, not a wind-drifting roamer. It
    -- must make obvious net progress from the configured 150..250 px spawn
    -- range instead of spending most of its lifetime circling the target.
    r.speed=math.max(r.speed,18+math.min(12,r.seekAge*1.0))
    local pickupRadius=math.max(30,tonumber(cfg().touchRadius) or 14)
    local mature=r.stage~="forming" or r.age>=r.formation*.85
    if mature and d<=pickupRadius then if beginCarry(r,px,pz,"seeker") then return end end
  else
    r.wander=(r.wander or 0)+dt*.19;targetAng=targetAng+sin(r.wander+r.id*.71)*.75
  end
  local dAng=(targetAng-r.heading+pi)%(2*pi)-pi
  r.heading=r.heading+dAng*math.min(1,dt*(r.seeker and 4.0 or .42))
  local speed=r.speed*(r.stage=="forming" and (.30+.70*smooth(r.age/r.formation)) or 1)
  local nx,nz=r.x+cos(r.heading)*speed*dt,r.z+sin(r.heading)*speed*dt
  local q=worldSample(nx,nz)
  if q.solid and not q.water and not r.seeker then
    -- Normal tornadoes remain terrain-reactive. A committed seeker is a
    -- weather-field phenomenon and static scenery must not permanently repel
    -- it from the player (the real Route 1 failure in 8.1.62/early 8.1.63).
    r.heading=r.heading+(rnd()<.5 and 1 or -1)*pi*.42;speed=speed*.45
    nx,nz=r.x+cos(r.heading)*speed*dt,r.z+sin(r.heading)*speed*dt;q=worldSample(nx,nz)
  elseif r.seeker and q.solid and not q.water then
    r.seekSceneryCrossings=(r.seekSceneryCrossings or 0)+1
  end
  r.x,r.z=nx,nz
  local stayedInOutdoorField=refreshTornadoMap(r,oldX,oldZ)
  if r.offscreen then
    -- Once this step leaves the live render set, do not sample the player's
    -- current voxel root or run contact/seeker pickup in an unrelated frame.
    -- Remote surface state is derived from the tornado's own map instead.
    updateRemoteSurface(r,dt)
    return
  end
  q=worldSample(r.x,r.z)
  r.groundY=tonumber(q.groundY) or r.groundY or 0
  local targetWater=(q.water and cfg().waterTwister~=false) and 1 or 0;r.waterSurface=targetWater>0
  local tau=targetWater>0 and .32 or .90;r.waterBlend=r.waterBlend+(targetWater-r.waterBlend)*(1-math.exp(-dt/tau))
  if r.seeker and px and pz and stayedInOutdoorField~=false then
    local dx,dz=px-r.x,pz-r.z;local d=sqrt(dx*dx+dz*dz)
    r.seekBestDistance=math.min(tonumber(r.seekBestDistance) or (seekDistance or d),d)
    local pickupRadius=math.max(30,tonumber(cfg().touchRadius) or 14)
    local mature=r.stage~="forming" or r.age>=r.formation*.85
    if mature and d<=pickupRadius then beginCarry(r,px,pz,"seeker") end
  elseif not r.seeker then
    tryTouchCarry(r,px,pz,mapId,prevPx,prevPz,oldX,oldZ)
  end
end

local function updateCarry(r,dt,px,pz,mapId)
  lockPlayerControls()
  r.carryAge=(r.carryAge or 0)+dt
  if r.stage=="pickup" then
    if px and pz then r.x,r.z=px,pz end
    if r.carryAge>=3.4 then r.stage="depart";r.carryAge=0;r.departHeading=tonumber(r.heading) or 0;T.lastReason="player airborne / tornado departing source map" end
  elseif r.stage=="depart" then
    local a=tonumber(r.departHeading) or tonumber(r.heading) or 0;r.x=r.x+cos(a)*22*dt;r.z=r.z+sin(a)*22*dt
    if r.carryAge>=1.25 then
      r.carryAge=0;r.warpDone=false;local landing=T.landingFor(r.destination)
      local ok=T.carry(r.destination,function() r.warpDone=true end,landing)
      if ok then lockPlayerControls();r.stage="transfer";r.transferAge=0;T.lastReason="player carried across map boundary" else startRope(r);T._carry=nil;restoreControlLock() end
    end
  elseif r.stage=="transfer" then
    r.transferAge=(r.transferAge or 0)+dt
    if mapId==r.destination and px and pz then
      local landing=T._pendingLanding
      if landing and landing.mode=="water" and not T.activateSurfLanding(landing) then if not T.emergencyReturn(r) then T.lastReason="water landing safety failure" end
      else local a=tonumber(r.departHeading) or tonumber(r.heading) or 0;r.stage="arrival";r.carryAge=0;r.mapId=mapId;r.arrivalX0=px-cos(a)*46;r.arrivalZ0=pz-sin(a)*46;r.x,r.z=r.arrivalX0,r.arrivalZ0;T.lastReason="destination live / tornado carrying player in" end
    elseif r.transferAge>15 then startRope(r);T._carry=nil;restoreControlLock();T.lastReason="carry transfer timeout" end
  elseif r.stage=="arrival" then
    if px and pz then local u=smooth((r.carryAge or 0)/1.65);r.x=(r.arrivalX0 or px)+(px-(r.arrivalX0 or px))*u;r.z=(r.arrivalZ0 or pz)+(pz-(r.arrivalZ0 or pz))*u end
    if r.carryAge>=1.65 then r.stage="landing";r.carryAge=0;if px and pz then r.x,r.z=px,pz end;T.lastReason="tornado setting player down" end
  elseif r.stage=="returning" then
    r.transferAge=(r.transferAge or 0)+dt
    if mapId==r.returnMap and px and pz then if r.returnSurf then local S=req("Scene");local ow=S and S.overworld and S.overworld() or nil;if ow and ow.player then ow.player.surfing=true end end;T._pendingLanding=nil;T._carry=nil;restoreControlLock();startRope(r);T.lastReason="returned to safe origin"
    elseif r.transferAge>10 then T.lastReason="emergency return still pending" end
  elseif r.stage=="landing" then
    if px and pz then r.x,r.z=px,pz end
    if r.carryAge>=3.2 then T._pendingLanding=nil;T._carry=nil;restoreControlLock();startRope(r);T.lastReason="gentle landing / rope-out" end
  end
end

local function updateOne(r,dt,gale,px,pz,mapId,prevPx,prevPz)
  r.age=r.age+dt
  if r.stage=="pickup" or r.stage=="depart" or r.stage=="transfer" or r.stage=="arrival" or r.stage=="returning" or r.stage=="landing" then updateCarry(r,dt,px,pz,mapId); return end
  if r.stage=="rope" then r.ropeAge=r.ropeAge+dt; return end
  if not gale then startRope(r); return end
  if r.stage=="forming" and r.age>=r.formation then r.stage="roam";r.roamAge=0 end
  moveNormal(r,dt,px,pz,mapId,prevPx,prevPz)
  if r.stage=="roam" then r.roamAge=r.roamAge+dt; if r.roamAge>=r.roamFor then startRope(r) end end
end
local function spawnSchedule(c,first)
  if first then return range(9,18) end
  local every=math.max(30,tonumber(c.everySeconds) or 90)
  return every*range(.78,1.22)
end

local function update3d(dt)
  local weatherGale=galeNow(); local outside=outdoors(); local gale=weatherGale and outside
  local px,pz,_,mapId=playerInfo()
  local prevPx,prevPz
  if T._contactMapId~=nil and tostring(T._contactMapId)==tostring(mapId) then
    prevPx,prevPz=T._contactPlayerX,T._contactPlayerZ
  end
  -- Going indoors/cave hides the outdoor renderer but must not destroy the
  -- storm. Preserve funnel stage/position/timers and resume the same tornadoes
  -- on exit. Only an actual departure from GALE ropes them out.
  if weatherGale and not outside then
    T.lastReason="gale tornado field suspended indoors"
    return
  end
  if gale and not T._gale then T._gale=true;T.stormAge=0;T.timer=0;T.nextSpawn=spawnSchedule(cfg(),true);T.lastReason="gale tornado watch" end
  if not weatherGale and T._gale then T._gale=false; for i=1,#T.active do if T.active[i]~=T._carry then startRope(T.active[i]) end end end
  if gale then
    T.stormAge=T.stormAge+dt;T.timer=T.timer+dt
    if T.timer>=T.nextSpawn then
      T.timer=0; local c=cfg(); T.nextSpawn=spawnSchedule(c,false)
      local spawned=T.spawn(false)
      if spawned then
        -- Rare second funnel in the same storm; rarer outbreak creates up to
        -- two additional roamers at once. maxActive remains a hard CPU/GPU cap.
        local slots=math.max(0,math.min(4,tonumber(c.maxActive) or 3)-#T.active)
        if slots>0 and rnd()<clamp(tonumber(c.outbreakChance) or .035,0,.5) then
          T.spawn(true); if slots>1 then T.spawn(true) end
        elseif slots>0 and rnd()<clamp(tonumber(c.secondaryChance) or .12,0,.75) then
          T.spawn(true)
        end
      end
    end
  end
  for i=#T.active,1,-1 do
    local r=T.active[i]; updateOne(r,dt,gale,px,pz,mapId,prevPx,prevPz)
    if r.stage=="rope" and r.ropeAge>=r.ropeFor then if T._carry==r then T._carry=nil end; table.remove(T.active,i) end
  end
  T._contactPlayerX,T._contactPlayerZ,T._contactMapId=px,pz,mapId
end

local function restoreLegacyHidden(e)
  local ow=e and e.hiddenOwner;if not ow then return end
  if e.hiddenKind=="gen2" then pcall(function() ow.flyHidden=e.hiddenOriginal end) else pcall(function() ow.playerHidden=e.hiddenOriginal and true or false end) end
  e.hiddenOwner=nil;e.hiddenOriginal=nil;e.hiddenKind=nil
end
local function legacyHidePlayer(e,yes)
  if not e then return end;local ow=currentOverworld()
  if yes and ow then
    if e.hiddenOwner~=ow then
      restoreLegacyHidden(e);e.hiddenOwner=ow
      if type(ow.flyHides)=="function" and ow.playerHidden==nil then e.hiddenKind="gen2";e.hiddenOriginal=ow.flyHidden;ow.flyHidden="weather_fx_tornado"
      else e.hiddenKind="gen1";e.hiddenOriginal=ow.playerHidden and true or false;ow.playerHidden=true end
    elseif e.hiddenKind=="gen2" then ow.flyHidden="weather_fx_tornado" else ow.playerHidden=true end
  elseif not yes then restoreLegacyHidden(e) end
end
local function legacyLockCamera(e,which)
  if not e then return end;local ow=currentOverworld();local cam=ow and ow.camera;if not (cam and tonumber(cam.x) and tonumber(cam.y)) then return end
  local key=which=="destination" and "destCamera" or "sourceCamera";local v=e[key]
  if type(v)~="table" or v.owner~=ow then v={owner=ow,x=cam.x,y=cam.y};e[key]=v end;cam.x,cam.y=v.x,v.y
end
local function playerOnWater()
  local ow=currentOverworld();local p=ow and ow.player;local map=ow and ow.map;if not (p and map) then return false end;if p.surfing then return true end
  if type(map.isWaterCell)=="function" then local ok,v=pcall(map.isWaterCell,map,p.cellX,p.cellY);if ok then return v and true or false end end;return false
end
local function drawLegacyPlayerProxy(cx,cy,angle,frameX,frameY,px)
  if not (love and love.graphics) then return end;local ow=currentOverworld();local p=ow and ow.player;if not (p and type(p.draw)=="function") then return end
  local G=love.graphics;px=math.max(.5,tonumber(px) or 1);local gx=(cx-frameX)/px-8;local gy=(cy-frameY)/px-8
  local gen=1;pcall(function() local H=V.require("HostRuntime");gen=tonumber(H and H.generation and H.generation() or 1) or 1 end)
  G.push();G.translate(cx,cy);G.rotate(tonumber(angle) or 0);G.translate(-cx,-cy);G.push();G.translate(frameX,frameY);G.scale(px,px)
  if gen==2 then pcall(p.draw,p,gx-(tonumber(p.px) or 0),gy-(tonumber(p.py) or 0),1) else pcall(p.draw,p,(tonumber(p.px) or 0)-gx,(tonumber(p.py) or 0)-gy) end
  G.pop();G.pop()
end
local function update2d(dt)
  local Funnel=req("Funnel")
  if T._legacyCarry then
    lockPlayerControls()
    local e=T._legacyCarry;local ph=Funnel and Funnel.phaseName and Funnel.phaseName() or nil
    if ph=="sweepout" or ph=="blackout" or ph=="sweepin" then legacyHidePlayer(e,true) end
    local _,_,_,mapId=playerInfo()
    if e.warped and not e.arrived and mapId==e.destination then
      if e.landing and e.landing.mode=="water" and not e.surfApplied then e.surfApplied=T.activateSurfLanding(e.landing) and true or false end
      e.arrived=true;legacyLockCamera(e,"destination");if Funnel and Funnel.relocationArrived then Funnel.relocationArrived() end;T.lastReason="2d destination live / sweeping player in from left"
    elseif e.warpFailed and not e.arrived then e.arrived=true;if Funnel and Funnel.relocationArrived then Funnel.relocationArrived() end end
    if e.arrived then legacyLockCamera(e,"destination")
    elseif ph=="approach" or ph=="sweepout" or ph=="blackout" then legacyLockCamera(e,"source") end
    return
  end
  if not (settingOn() and outdoors() and galeNow()) then T._legacyTimer=0;return end
  if Funnel and Funnel.active then return end
  T._legacyTimer=T._legacyTimer+dt;local c=cfg()
  -- 8.1.67: 2D Gale uses the same player-facing TORNADO FREQUENCY cadence
  -- as 3D opportunity scheduling. NORMAL/default is exactly 90 seconds
  -- (1.5 minutes). The carry roll remains independent and defaults to 10%.
  local every=math.max(30,tonumber(c.everySeconds) or 90)
  if T._legacyTimer<every then return end
  T._legacyTimer=T._legacyTimer-every
  local Settings=req("Settings");local carryChance=tonumber(c.carryChance) or .10;if Settings and Settings.tornadoPickupChance then local ok,v=pcall(Settings.tornadoPickupChance);if ok and tonumber(v) then carryChance=tonumber(v) end end
  carryChance=clamp(carryChance,0,1);if carryChance<=0 or rnd()>=carryChance then return end
  local _,_,_,mapId=playerInfo();local dest=T.destinations(mapId);if #dest==0 then T.lastReason="2d carry rolled but no escape-safe visited destination";return end
  local target=dest[irand(#dest)];local landing=T.landingFor(target);if not landing or (landing.mode=="water" and not T.hasSurf()) then return end
  local e={destination=target,landing=landing,warped=false,arrived=false,waterTwister=playerOnWater() and c.waterTwister~=false};T._legacyCarry=e;lockPlayerControls();legacyLockCamera(e,"source");T.lastReason="2d tornado approaching / controls + camera locked"
  if c.funnel~=false and Funnel and Funnel.start then
    Funnel.start(tonumber(c.funnelSeconds) or 2.5,function() legacyHidePlayer(e,false);T._pendingLanding=nil;if T._legacyCarry==e then T._legacyCarry=nil end;restoreControlLock();T.lastReason=e.warped and "2d relocation complete / tornado exited right" or "2d tornado event ended without transfer" end,
      {mode="relocate2d",waterTwister=e.waterTwister,playerDrawer=drawLegacyPlayerProxy,
       onCapture=function() if T._legacyCarry==e then legacyHidePlayer(e,true);T.lastReason="2d tornado swept player off screen" end end,
       onPickup=function() if T._legacyCarry~=e then return end;local ok=T.carry(e.destination,function() e.warpCallback=true end,e.landing);e.warped=ok and true or false;e.warpFailed=not ok;if ok then lockPlayerControls();T.lastReason="2d blackout / real map transfer in progress" elseif Funnel.relocationArrived then Funnel.relocationArrived() end end,
       onDrop=function() if T._legacyCarry==e then legacyHidePlayer(e,false);legacyLockCamera(e,"destination");T.lastReason="2d player dropped into destination" end end})
  else local ok=T.carry(target,nil,landing);T._legacyCarry=nil;restoreControlLock();if not ok then T.lastReason="2d relocation refused" end end
end

function T.update(dt)
  dt=clamp(tonumber(dt) or 0,0,.25); if dt<=0 then return end
  -- Tornado owns the 2D funnel clock.  Draw.lua is render-only, preventing the
  -- historical double-tick where both simulation and compositor advanced it.
  local Funnel=req("Funnel")
  if Funnel and Funnel.active and Funnel.update then Funnel.update(dt) end
  T.observeCurrent(dt)
  if not settingOn() then
    -- OFF is a graceful shutdown, not a frozen state. Let an already-started
    -- carry finish its guarded landing so the player can never be stranded,
    -- while every other funnel retracts upward and spawn clocks reset.
    T._gale=false;T.timer=0;T.nextSpawn=0;T._legacyTimer=0
    local px,pz,_,mapId=playerInfo()
    for i=#T.active,1,-1 do
      local r=T.active[i]
      if r==T._carry or r.stage=="pickup" or r.stage=="depart" or r.stage=="transfer" or r.stage=="arrival" or r.stage=="returning" or r.stage=="landing" then
        updateCarry(r,dt,px,pz,mapId)
      else
        startRope(r);r.ropeAge=r.ropeAge+dt
      end
      if r.stage=="rope" and r.ropeAge>=r.ropeFor then if T._carry==r then T._carry=nil end;table.remove(T.active,i) end
    end
    return
  end
  if strict3d() then update3d(dt) else update2d(dt) end
end

-- Render-time player pose. The voxel bridge applies this only while calling the
-- host renderer, then restores the real entity immediately.
function T.presentationPose()
  local r=T._carry; if not r then return nil end
  local a=(r.carryAge or 0)*5.4+r.id
  local phase=math.floor((a%(2*pi))/(pi*.5))
  local facing=(phase==0 and "down" or phase==1 and "right" or phase==2 and "up" or "left")
  if r.stage=="pickup" then
    local u=smooth((r.carryAge or 0)/3.4)
    -- Suction reads as an inward spiral: the visible player starts near the
    -- outer funnel wall, is pulled toward the core while rising, then the
    -- guarded map relocation occurs at the end of pickup.
    local rad=9-7*u
    return {x=r.x+cos(a)*rad,z=r.z+sin(a)*rad,lift=2+24*u,facing=facing}
  elseif r.stage=="depart" or r.stage=="transfer" or r.stage=="arrival" or r.stage=="returning" then
    local rad=(r.stage=="arrival") and 7 or 8
    return {x=r.x+cos(a)*rad,z=r.z+sin(a)*rad,lift=25,facing=facing}
  elseif r.stage=="landing" then
    local u=smooth((r.carryAge or 0)/3.2); local rad=8*(1-u)
    return {x=r.x+cos(a)*rad,z=r.z+sin(a)*rad,lift=24*(1-u),facing=facing}
  end
end

function T.isCarrying() return T._carry~=nil or T._legacyCarry~=nil end
function T.renderState() return T.active end
function T.cloudBase()
  local S=T._cloudHeightSettings
  if not S then local ok,m=pcall(V.require,"Settings");if ok and m then T._cloudHeightSettings=m;S=m end end
  local scale=(S and S.cloudHeightScale and tonumber(S.cloudHeightScale())) or 1.5
  return 122*math.max(1.0,math.min(1.5,scale))
end
local function installNativeInputGuard()
  -- Tornado carry owns the whole overworld control surface, not just movement.
  -- Gen1Recomp map replacement may construct/reset a Player with inputLocked=false
  -- before Weather FX's next effects tick. Voxel Nexus FreeMove also lives behind
  -- this same handleInput seam. Guard the seam itself so there is no one-frame
  -- window for d-pad, free move, A, or START while a carry is active.
  local ok,OW=pcall(require,"src.world.OverworldController")
  if not ok or type(OW)~="table" or type(OW.handleInput)~="function" then return false end

  -- Hot reload-safe ownership: the wrapper is installed only once on the engine
  -- class and consults the newest Weather FX Tornado table through this slot.
  OW.weatherFxTornadoInputOwner=T
  if OW.weatherFxTornadoInputGuard then return true end

  local inner=OW.handleInput
  local function guarded(self,...)
    local owner=OW.weatherFxTornadoInputOwner
    if owner and type(owner.isCarrying)=="function" and owner.isCarrying() then
      -- Reassert the native flag at the exact input phase; setMap/warp code is
      -- allowed to replace/reset the player between Weather FX update ticks.
      if owner._lockPlayerControls then owner._lockPlayerControls() end
      if self then self.joyLatch=nil end
      return nil
    end
    return inner(self,...)
  end
  OW.handleInput=guarded
  OW.weatherFxTornadoInputGuard=guarded
  return true
end

-- Private bridge used by the engine input guard above. Kept as a field so a
-- hot-reloaded engine wrapper can always call the newest Tornado module table.
T._lockPlayerControls=lockPlayerControls

function T.installHooks()
  if T._hookInstalled then
    installNativeInputGuard()
    return true
  end
  local collisionOk=false
  if mod.hooks and type(mod.hooks.wrap)=="function" then
    collisionOk=pcall(function()
      mod.hooks:wrap("movement.collision",function(next,allowed,ctx)
        allowed=next(allowed,ctx)
        if not T.isCarrying() then return allowed end
        local S=req("Scene"); local ow=S and S.overworld and S.overworld() or nil
        if ctx and ow and ctx.mover==ow.player then ctx.reason="weather_fx_tornado"; return false end
        return allowed
      end)
    end)
  end
  local nativeOk=installNativeInputGuard()
  T._hookInstalled=(collisionOk or nativeOk) and true or false
  return T._hookInstalled
end
function T.worldPersistenceStatus()
  local crossings,remoteCrossings,offscreen=0,0,0
  for _,r in ipairs(T.active) do
    crossings=crossings+(tonumber(r.mapCrossings) or 0)
    remoteCrossings=remoteCrossings+(tonumber(r.offscreenCrossings) or 0)
    if r.offscreen then offscreen=offscreen+1 end
  end
  return {rootRebases=tonumber(T._rootRebases) or 0,mapCrossings=crossings,offscreenCrossings=remoteCrossings,offscreen=offscreen,active=#T.active}
end

function T.describe()
  if not settingOn() then return "off" end
  if not strict3d() then return T._legacyCarry and "2d gale relocation tornado" or "2d gale relocation-only" end
  return string.format("3d gale tornadoes=%d carry=%s next=%.0fs",#T.active,T._carry and T._carry.stage or "no",math.max(0,(T.nextSpawn or 0)-(T.timer or 0)))
end
function T.invalidate()
  if T._legacyCarry then legacyHidePlayer(T._legacyCarry,false) end
  restoreControlLock()
  T.active={};T._carry=nil;T._gale=false;T.timer=0;T.nextSpawn=0;T._voxelState=nil;T._legacyTimer=0;T._legacyCarry=nil;T._landings=nil;T._safeCache=nil;T._pendingLanding=nil;T._observeTimer=0;T._rootRebases=0;T._rootMapId=nil;T._rootNeighborOffsets=nil;T._contactPlayerX=nil;T._contactPlayerZ=nil;T._contactMapId=nil
end

-- Test-only deterministic RNG seam. Production never calls this.
function T._setRandom(fn) randomFn=type(fn)=="function" and fn or math.random end

return T
