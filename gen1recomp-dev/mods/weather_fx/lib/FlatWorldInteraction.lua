local V = ...

-- Flat-world interaction field.
--
-- Weather FX does not have mountain terrain. What matters in this voxel world
-- is the 2D footprint of roofs/buildings/trees/water/open ground. This module
-- observes the live voxel render state and cheaply classifies those footprints
-- so weather systems can share one answer about shelter and water without
-- building another world grid.
local F = {}

local TILE = 16
local regions = {}
local regionCount = 0
local shapeCache = setmetatable({}, {__mode="k"})
local sampleCache = setmetatable({}, {__mode="k"})
local READY = false
local ZERO = {class="open",water=false,solid=false,canopy=false,roof=false,shelter=0,drag=1,groundY=0,built=0,canopyFraction=0,waterFraction=0,openFraction=1,windShadow=0,windExposure=1,humidityBias=0,tempBias=0,fogAffinity=0}

local SOLID = {
  wall=true,building=true,house=true,roof=true,raised=true,block=true,
  sign=true,signpost=true,post=true,billboard=true,prop=true,
}
local CANOPY = {tree=true,canopy=true,bush=true,shrub=true,stump=true,planter=true}

local function mapDims(map)
  if not map then return 0,0 end
  local w,h=tonumber(map.widthCells),tonumber(map.heightCells)
  if (not w or w<=0) and map.def then local q=tonumber(map.def.width); if q and q>0 then w=q*2 end end
  if (not h or h<=0) and map.def then local q=tonumber(map.def.height); if q and q>0 then h=q*2 end end
  return math.max(0,math.floor(w or 0)),math.max(0,math.floor(h or 0))
end

local function clearRegion(r)
  r.cell = {}
  r.builtLightCells = nil
  -- Static footprint/shelter profiles are derived only from the same cached
  -- voxel cell descriptors above. Drop them whenever that descriptor cache is
  -- invalidated so there is one exact terrain authority.
  sampleCache[r] = nil
end

local function addRegion(map,ox,oz,TS,VS)
  local w,h=mapDims(map); if not map or w<=0 or h<=0 then return end
  regionCount=regionCount+1
  local r=regions[regionCount]
  if not r then r={cell={}}; regions[regionCount]=r end
  if r.map~=map or r.w~=w or r.h~=h then clearRegion(r) end
  r.map,r.ox,r.oz,r.w,r.h,r.VS=map,tonumber(ox) or 0,tonumber(oz) or 0,w,h,VS
  local shapes=shapeCache[map]
  if shapes==nil and TS and type(TS.forMap)=="function" then
    local ok,v=pcall(TS.forMap,map); shapes=(ok and type(v)=="table") and v or false; shapeCache[map]=shapes
  end
  r.shapes=shapes~=false and shapes or nil
end

function F.observeVoxel(state, voxelScene, tileShape)
  if type(state)~="table" or not state.map then READY=false; return false end
  local old=regionCount; regionCount=0
  addRegion(state.map,0,0,tileShape,voxelScene)
  for _,nb in ipairs(state.neighbors or {}) do
    if nb and nb.map then addRegion(nb.map,nb.ox or 0,nb.oy or nb.oz or 0,tileShape,voxelScene) end
  end
  for i=old,regionCount+1,-1 do regions[i]=nil end
  READY=regionCount>0
  return READY
end

local function regionAt(x,z)
  for i=1,regionCount do
    local r=regions[i]; local lx,lz=x-r.ox,z-r.oz
    if lx>=0 and lz>=0 and lx<r.w*TILE and lz<r.h*TILE then
      return r,math.floor(lx/TILE),math.floor(lz/TILE)
    end
  end
end

local function shapeText(shape)
  if type(shape)~="table" then return "" end
  return table.concat({tostring(shape.class or ""),tostring(shape.kind or ""),tostring(shape.art or ""),tostring(shape.name or ""),tostring(shape.tag or "")}," "):lower()
end

local function cellInfo(r,cx,cz)
  if not r or cx<0 or cz<0 or cx>=r.w or cz>=r.h then return nil end
  local k=cx*(r.h+1)+cz+1; local got=r.cell[k]; if got then return got end
  local water=false
  if type(r.map.isWaterCell)=="function" then local ok,v=pcall(r.map.isWaterCell,r.map,cx,cz); water=ok and v==true end
  local shape=nil
  if r.shapes and type(r.map.cellTile)=="function" then local ok,t=pcall(r.map.cellTile,r.map,cx,cz); if ok then shape=r.shapes[t] end end
  local class=tostring(type(shape)=="table" and (shape.class or shape.kind) or "open"):lower()
  local art=tostring(type(shape)=="table" and shape.art or ""):lower()
  local text=shapeText(shape)
  if class=="water" or art=="water" or text:find("water",1,true) then water=true end
  local canopy=CANOPY[class] or text:find("tree",1,true)~=nil or text:find("canopy",1,true)~=nil or text:find("bush",1,true)~=nil
  local roof=class=="roof" or text:find("roof",1,true)~=nil or text:find("building",1,true)~=nil or text:find("house",1,true)~=nil
  local h=type(shape)=="table" and tonumber(shape.h) or 0
  -- Tall trees/canopies have height, but they are permeable shelter rather
  -- than buildings. Do not let the generic height fallback classify them as
  -- solid roofs, or forests become acoustically/weather-sealed rooms.
  local solid=(not water) and (not canopy) and (SOLID[class] or roof or (h and h>1.5)) or false
  local gy=0
  if r.VS and type(r.VS.groundAt)=="function" then local ok,v=pcall(r.VS.groundAt,r.map,cx,cz); if ok and type(v)=="number" then gy=v end end
  -- Light pollution follows actual building/roof footprint, not every raised
  -- solid. Gen-1 cliffs/ledges are solid weather obstacles but must not behave
  -- like electrically lit buildings in the constellation dimmer. Door/warp
  -- metadata remains a second source in BuildingLight for building styles whose
  -- tileset semantics do not expose a roof class.
  local builtLight=roof or class=="building" or class=="house"
  got={class=water and "water" or (canopy and "canopy" or (roof and "roof" or (solid and "solid" or class))),water=water,solid=solid,canopy=canopy,roof=roof,builtLight=builtLight,groundY=gy}
  r.cell[k]=got; return got
end

local function rawAt(x,z)
  local r,cx,cz=regionAt(x,z); if not r then return nil end
  return cellInfo(r,cx,cz),r,cx,cz
end

local function footprintFractions(r,cx,cz)
  local seen,built,canopy,water=0,0,0,0
  -- Five-by-five is still only 25 cached cell lookups and gives towns, forests
  -- and shorelines a footprint large enough to matter without creating a new
  -- simulation grid. This is intentionally horizontal: the game has no
  -- mountain/orographic weather.
  for dz=-2,2 do for dx=-2,2 do
    local q=cellInfo(r,cx+dx,cz+dz)
    if q then
      seen=seen+1
      if q.solid or q.roof then built=built+1 end
      if q.canopy then canopy=canopy+1 end
      if q.water then water=water+1 end
    end
  end end
  if seen<=0 then return 0,0,0,1 end
  local bf,cf,wf=built/seen,canopy/seen,water/seen
  return bf,cf,wf,math.max(0,1-math.min(1,bf+cf+wf))
end

-- Static half of sampleAt(). 8.1.47 caches this once per stable voxel cell.
-- Previously every WindFlow/Hydrology sample rescanned the same 3x3 and 5x5
-- neighbourhood even though map geometry had not changed. Directional wind
-- shadow remains live below, so the output is byte-for-formula identical while
-- the expensive footprint classification becomes O(1) after first touch.
local function staticProfile(r,cx,cz)
  if not r or cx<0 or cz<0 or cx>=r.w or cz>=r.h then return nil end
  local cache=sampleCache[r]
  if not cache then cache={}; sampleCache[r]=cache end
  local k=cx*(r.h+1)+cz+1
  local got=cache[k]
  if got then return got end
  local c=cellInfo(r,cx,cz)
  if not c then return nil end
  local neighbours,solidN,canopyN=0,0,0
  for dz=-1,1 do for dx=-1,1 do
    if dx~=0 or dz~=0 then
      local q=cellInfo(r,cx+dx,cz+dz)
      if q then
        neighbours=neighbours+1
        if q.solid then solidN=solidN+1 end
        if q.canopy then canopyN=canopyN+1 end
      end
    end
  end end
  local shelter=0
  if c.solid or c.roof then shelter=.96
  elseif c.canopy then shelter=.62
  elseif neighbours>0 then shelter=math.min(.72,solidN/neighbours*.62+canopyN/neighbours*.28) end
  local builtF,canopyF,waterF,openF=footprintFractions(r,cx,cz)
  got={cell=c,baseShelter=shelter,built=builtF,canopy=canopyF,water=waterF,open=openF}
  cache[k]=got
  return got
end

local function directionalShadow(r,cx,cz,windX,windZ)
  windX,windZ=tonumber(windX) or 0,tonumber(windZ) or 0
  local l=math.sqrt(windX*windX+windZ*windZ)
  if l<1e-5 then return 0 end
  -- Weather travels WITH the wind, therefore shelter is upwind of the sample.
  local ux,uz=-windX/l,-windZ/l
  local shadow=0
  for step=1,4 do
    local sx=math.floor(cx+ux*step+0.5)
    local sz=math.floor(cz+uz*step+0.5)
    local q=cellInfo(r,sx,sz)
    if q then
      local w=(5-step)/4
      if q.solid or q.roof then shadow=math.max(shadow,.38+.50*w)
      elseif q.canopy then shadow=math.max(shadow,.20+.34*w) end
    end
  end
  return math.min(.94,shadow)
end

function F.sampleAt(x,z,out,windX,windZ)
  x,z=tonumber(x) or 0,tonumber(z) or 0; out=out or {}
  local r,cx,cz=regionAt(x,z)
  local p=staticProfile(r,cx,cz)
  if not p then for k,v in pairs(ZERO) do out[k]=v end; return out end
  local c=p.cell
  local windShadow=directionalShadow(r,cx,cz,windX,windZ)
  local shelter=math.max(p.baseShelter,windShadow*.82)
  local builtF,canopyF,waterF,openF=p.built,p.canopy,p.water,p.open
  local drag=c.water and 1.08 or math.max(.18,1-shelter*.76)
  local windExposure=math.max(.05,math.min(1.18,openF*1.08+waterF*1.12+(1-windShadow)*.18-shelter*.22))
  out.class,out.water,out.solid,out.canopy,out.roof=c.class,c.water,c.solid,c.canopy,c.roof
  out.shelter,out.drag,out.groundY=shelter,drag,c.groundY or 0
  out.built,out.canopyFraction,out.waterFraction,out.openFraction=builtF,canopyF,waterF,openF
  out.windShadow,out.windExposure=windShadow,windExposure
  -- Small bounded physical biases for the microclimate layer. Town footprints
  -- retain heat; canopy cools/humidifies; water humidifies and encourages fog.
  out.tempBias=builtF*1.35-canopyF*1.65-waterF*.55
  out.humidityBias=waterF*.18+canopyF*.12-builtF*.035
  out.fogAffinity=math.min(1,waterF*.92+canopyF*.28+shelter*.12)
  return out
end

function F.directionalShelter(x,z,windX,windZ)
  local r,cx,cz=regionAt(tonumber(x) or 0,tonumber(z) or 0)
  if not r then return 0 end
  return directionalShadow(r,cx,cz,windX,windZ)
end

function F.exposureAt(x,z)
  local c=rawAt(tonumber(x) or 0,tonumber(z) or 0)
  if not c then return 1 end
  if c.roof or c.solid then return .04 end
  if c.canopy then return .42 end
  return 1
end

local function builtLightCells(r)
  if not r then return nil end
  if r.builtLightCells then return r.builtLightCells end
  local out={}
  -- Build once per stable map/TileShape observation, then distance queries are
  -- O(number of building cells) rather than rescanning the map every frame.
  for cz=0,r.h-1 do
    for cx=0,r.w-1 do
      local q=cellInfo(r,cx,cz)
      if q and q.builtLight then
        out[#out+1]={x=r.ox+(cx+.5)*TILE,z=r.oz+(cz+.5)*TILE}
      end
    end
  end
  r.builtLightCells=out
  return out
end

-- Distance in movement cells to the nearest *visible building footprint* in the
-- connected voxel neighborhood. This is intentionally separate from shelter:
-- trees, cliffs and other solid weather blockers do not emit town light.
function F.nearestBuiltDistance(x,z,maxCells)
  if not READY then return nil end
  x,z=tonumber(x) or 0,tonumber(z) or 0
  maxCells=math.max(1,tonumber(maxCells) or 48)
  local maxPx=maxCells*TILE;local best2=maxPx*maxPx
  local found=false
  for i=1,regionCount do
    local cells=builtLightCells(regions[i])
    for j=1,#cells do
      local q=cells[j];local dx,dz=q.x-x,q.z-z
      local d2=dx*dx+dz*dz
      if d2<best2 then best2=d2;found=true end
    end
  end
  if not found then return nil end
  return math.sqrt(best2)/TILE
end

function F.waterAt(x,z) local c=rawAt(tonumber(x) or 0,tonumber(z) or 0); return c and c.water==true or false end
function F.ready() return READY end
function F.stats() return {ready=READY,regions=regionCount} end
function F.invalidate() READY=false; regionCount=0; for i=#regions,1,-1 do regions[i]=nil end end

return F
