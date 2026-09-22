-- Building-proximity star / ambient modifier (map metadata, not rendered geometry).
--
-- Architecture:
--   map.def / warps / door events        →  BuildingLocation registry
--   player tile                          →  continuous distance falloff
--   target factor                        →  dt-smoothed current factor
--   factor × day-night visibility        →  starScale / ambientMul
--
-- Building locations are known from map data whether or not the voxel
-- geometry for that building is loaded. Loading geometry must not change
-- brightness.

local V = ...

local BuildingLight = {
  dist = 50,
  factor = 0,          -- smoothed 0 = near building, 1 = far/wild
  _factorRaw = 0,
  ambientMul = 1,
  starMul = 1,
  _activeMapId = nil,
  _buildings = nil,
  _lastDist = nil,
  _neighborhoodKey = nil,
  _neighborhoodBuildings = nil,
  _neighborhoodMaps = 0,
  DEBUG = false,
}

-- Continuous falloff (player steps ≈ map cells)
local NEAR_STEPS = 4     -- strongest building glow close to the footprint
local FAR_STEPS = 48     -- long gradual fade to truly dark-sky wilderness
local AMBIENT_NEAR = 1.0
local AMBIENT_FAR = 0.48
local STAR_NEAR = 0.35   -- dimmer stars near buildings
local STAR_FAR = 1.0     -- full stars in the wild
-- Temporal ease (frame-rate independent). Higher = snappier; keep gentle.
local SMOOTH = 0.72

-- Permanent registry: mapId → { {x,y,w,h}, ... }
-- Survives geometry load/unload; only rebuilt when map identity changes.
local REGISTRY = {}

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function smoothstep(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end

local function isTrueNight()
  local ok, TOD = pcall(function() return V.require("TimeOfDay") end)
  if not (ok and TOD) then return false end
  if TOD.pin == "NITE" or TOD.pin == "NIGHT" then return true end
  if TOD.tod == "NITE" or TOD.tod == "NIGHT" then return true end
  if TOD.isNight then
    local ok2, n = pcall(TOD.isNight)
    if ok2 and n then return true end
  end
  return false
end

local function mapIdOf(map)
  if not map then return nil end
  return map.id or (map.def and (map.def.id or map.def.name)) or tostring(map)
end

local function dims(map)
  if not map then return 0, 0 end
  -- Gen1Recomp/Voxel Realism expose widthCells when a cell dimension is
  -- available. map.def.width / height are *block* dimensions (one block is
  -- 2x2 movement cells), so they must be doubled before they are used by this
  -- cell-space distance field. Older BuildingLight code read def.width as if
  -- it were already cells and only doubled it in an unreachable fallback.
  local w = tonumber(map.widthCells)
  local h = tonumber(map.heightCells)
  if (not w or w <= 0) and map.def then w = tonumber(map.def.widthCells) end
  if (not h or h <= 0) and map.def then h = tonumber(map.def.heightCells) end
  if (not w or w <= 0) and map.def and map.def.width then w = tonumber(map.def.width) * 2 end
  if (not h or h <= 0) and map.def and map.def.height then h = tonumber(map.def.height) * 2 end
  -- Generic-host fallback only after the explicit Gen1 block fields above.
  if not w or w <= 0 then w = tonumber(map.width) end
  if not h or h <= 0 then h = tonumber(map.height) end
  return tonumber(w) or 0, tonumber(h) or 0
end

local function pushPoint(list, x, y, footprint)
  if x == nil or y == nil then return end
  x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)
  local fp = footprint or 2
  list[#list + 1] = { x = x, y = y, w = fp, h = fp }
end

--- Collect building-like locations from static map data (not rendered voxels).
local function collectFromMapData(map)
  local list = {}
  if not map then return list end
  local w, h = dims(map)
  if w <= 0 or h <= 0 then w, h = 64, 64 end

  local def = map.def or map

  -- 1) Warps / doors / events — present in map definitions without geometry
  local function scanEvents(events)
    if type(events) ~= "table" then return end
    for _, e in pairs(events) do
      if type(e) == "table" then
        local ex = tonumber(e.x or e.tileX or e.tx or e.col or e.cx)
        local ey = tonumber(e.y or e.tileY or e.ty or e.row or e.cy)
        local isDoor = e.warp or e.destination or e.map or e.toMap
            or e.targetMap or e.destMap or e.warpId
            or e.type == "warp" or e.kind == "warp" or e.script == "warp"
            or e.type == "door" or e.kind == "door"
            or e.door or e.entrance
        if isDoor and ex and ey then
          pushPoint(list, ex, ey, 3)
        end
      end
    end
  end
  scanEvents(map.events)
  scanEvents(map.warps)
  scanEvents(def.events)
  scanEvents(def.warps)
  scanEvents(def.warpEvents)
  scanEvents(map.objects)
  scanEvents(def.objects)

  -- Nested event tables (some maps store warps under events.warps)
  if type(def.events) == "table" then
    scanEvents(def.events.warps)
    scanEvents(def.events.doors)
  end

  -- 2) Building entrances are the cross-renderer source of truth.  Older
  -- versions also attempted V.require("TileShape") here, but V.require only
  -- resolves Weather FX's own lib/*.lua modules. That branch could therefore
  -- never execute and has been removed rather than kept as fake coverage.

  -- Do NOT invent town-centre/corner emitters when metadata is empty. That old
  -- heuristic could put an invisible light source on the opposite side of the
  -- player from the building they were actually walking away from, making
  -- constellations get darker with distance. Voxel mode now contributes real
  -- roof/building footprint distance through FlatWorldInteraction instead.

  return list
end

local function buildingsFor(map)
  local id = mapIdOf(map)
  if not id then
    local list = collectFromMapData(map)
    BuildingLight._buildings = list
    return list
  end
  local entry = REGISTRY[id]
  if entry and entry.list then
    BuildingLight._buildings = entry.list
    return entry.list
  end
  local list = collectFromMapData(map)
  REGISTRY[id] = { list = list, w = select(1, dims(map)), h = select(2, dims(map)) }
  BuildingLight._buildings = list
  return list
end

-- Resolve the same connected-map neighborhood that the voxel renderer has
-- already posed around the current root map. Offsets are world pixels, while
-- BuildingLight works in 16-pixel movement cells. This is the crucial seam:
-- a town/building just over a route boundary remains physically close before
-- and after the root map changes, so sky brightness follows distance instead
-- of the map-transition event.
local function neighborhoodFor(map)
  if not map then return nil, false end
  local rootId=mapIdOf(map)
  local regions={{map=map,ox=0,oy=0}}
  local hasVoxelContext=false
  pcall(function()
    local Atmos=V.require("DramalessAtmos")
    if not Atmos then return end
    local posed=Atmos._lastMap
    if posed and mapIdOf(posed)==rootId and type(Atmos._lastNeighbors)=="table" then
      hasVoxelContext=true
      for _,nb in ipairs(Atmos._lastNeighbors) do
        if nb and nb.map then
          regions[#regions+1]={map=nb.map,ox=tonumber(nb.ox) or 0,oy=tonumber(nb.oy or nb.oz) or 0}
        end
      end
    end
  end)
  return regions,hasVoxelContext
end

local function neighborhoodBuildings(map)
  local regions,hasVoxelContext=neighborhoodFor(map)
  if not regions then return nil,false end
  local parts={}
  for i,r in ipairs(regions) do
    parts[i]=table.concat({tostring(mapIdOf(r.map)),tostring(r.ox or 0),tostring(r.oy or 0)},"@");
  end
  local key=table.concat(parts,"|")
  if BuildingLight._neighborhoodKey==key and BuildingLight._neighborhoodBuildings then
    BuildingLight._buildings=BuildingLight._neighborhoodBuildings
    return BuildingLight._neighborhoodBuildings,hasVoxelContext
  end
  local out={}
  for _,r in ipairs(regions) do
    local src=buildingsFor(r.map)
    local dx=(tonumber(r.ox) or 0)/16
    local dy=(tonumber(r.oy) or 0)/16
    for i=1,#src do
      local b=src[i]
      out[#out+1]={x=(tonumber(b.x) or 0)+dx,y=(tonumber(b.y) or 0)+dy,w=b.w,h=b.h}
    end
  end
  BuildingLight._neighborhoodKey=key
  BuildingLight._neighborhoodBuildings=out
  BuildingLight._neighborhoodMaps=#regions
  BuildingLight._buildings=out
  return out,hasVoxelContext
end

--- Distance to nearest building footprint (not a single door pixel).
local function nearestDist(px, py, buildings)
  if not buildings or #buildings == 0 then return nil end
  local best = 1e9
  for i = 1, #buildings do
    local b = buildings[i]
    local hw = (tonumber(b.w) or 2) * 0.5
    local hh = (tonumber(b.h) or 2) * 0.5
    -- Distance to axis-aligned footprint rectangle
    local dx = math.max(math.abs(px - b.x) - hw, 0)
    local dy = math.max(math.abs(py - b.y) - hh, 0)
    local d = math.sqrt(dx * dx + dy * dy)
    if d < best then best = d end
  end
  return best
end

--- Continuous falloff: 0 near building → 1 at FAR_STEPS (smoothstep).
local function distToFactor(d)
  if d == nil then return nil end
  if d <= NEAR_STEPS then return 0 end
  if d >= FAR_STEPS then return 1 end
  local t = (d - NEAR_STEPS) / (FAR_STEPS - NEAR_STEPS)
  return smoothstep(t)
end

local function playerTile()
  local Scene
  local ok, value = pcall(V.require, "Scene")
  if ok then Scene = value end
  if not Scene then return nil, nil end

  -- Scene.sample already resolves the live Gen-1/Gen-2 overworld at call time.
  -- Its playerWorld values are world pixels, so convert to map cells here.
  local now = Scene.now
  if now and now.playerPosKnown then
    local wx, wy = tonumber(now.playerWorldX), tonumber(now.playerWorldY)
    if wx and wy then return math.floor(wx / 16), math.floor(wy / 16) end
  end

  -- Direct fallback for the first frame before Scene.sample populated `now`.
  local ow = Scene.overworld and Scene.overworld() or nil
  local p = ow and (ow.player or ow.hero or ow.avatar)
  if type(p) == "table" then
    local wx, wy = tonumber(p.px), tonumber(p.py)
    if wx and wy then return math.floor(wx / 16), math.floor(wy / 16) end
    local cx = tonumber(p.cellX or p.tileX or p.tx or p.x)
    local cy = tonumber(p.cellY or p.tileY or p.ty or p.y)
    if cx and cy then return math.floor(cx), math.floor(cy) end
  end
  return nil, nil
end

local function resolveMap()
  -- Use the same call-time overworld resolver as the rest of Weather FX. This
  -- works on the flat renderer, Gen 2 and voxel hosts and does not depend on a
  -- renderer-specific `_lastMap` side channel.
  local ok, Scene = pcall(V.require, "Scene")
  if ok and Scene and Scene.overworld then
    local okOw, ow = pcall(Scene.overworld)
    if okOw and type(ow) == "table" and ow.map then return ow.map end
  end

  -- During a transient unsampleable frame, a voxel host may still retain its
  -- last map. This is a fallback only; it is not required for vanilla 2D.
  local map
  pcall(function()
    local Atmos = V.require("DramalessAtmos")
    if Atmos and Atmos._lastMap then map = Atmos._lastMap end
  end)
  return map
end

function BuildingLight.update(dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 end
  if dt > 0.25 then dt = 0.25 end

  local map = resolveMap()
  local mapId = mapIdOf(map)
  local mapChanged=mapId ~= BuildingLight._activeMapId
  if mapChanged then
    -- Do NOT clear the prior physical distance merely because the root map
    -- changed. The voxel renderer can swap the root while the same building is
    -- still only a few steps away on the connected neighbour. The new
    -- neighborhood scan below replaces the distance as soon as that posed
    -- context is available; until then the smoothed light field holds rather
    -- than flashing at the seam.
    BuildingLight._activeMapId = mapId
    BuildingLight._neighborhoodKey=nil
  end
  local px, py = playerTile()
  local target

  if not (px and py) then
    -- Unknown player position: keep last factor (do not snap to wild)
    target = BuildingLight._factorRaw
    if target == nil then target = 0.5 end
  else
    local buildings,hasVoxelContext = neighborhoodBuildings(map)
    local d = nearestDist(px, py, buildings)
    -- In voxel mode use the geometry the player can actually see as another
    -- distance authority. The final distance is the nearer of a door/warp
    -- emitter and a real roof/building footprint, so walking away from visible
    -- buildings can only relax light pollution rather than reverse it.
    pcall(function()
      local F=V.require("FlatWorldInteraction")
      if F and F.ready and F.ready() and F.nearestBuiltDistance then
        local pd=F.nearestBuiltDistance(px*16+8,py*16+8,FAR_STEPS)
        if type(pd)=="number" and pd==pd then d=(d==nil) and pd or math.min(d,pd) end
      end
    end)
    if d == nil then
      -- A known metadata-free map with a stable sample is wilderness. During
      -- the first transient root-swap frame, however, keep the previous
      -- distance until the connected neighborhood arrives; this removes the
      -- map-transition brightness impulse without leaving wilderness polluted.
      if mapChanged and BuildingLight._lastDist~=nil then d=BuildingLight._lastDist
      elseif map~=nil then d=FAR_STEPS
      else d=BuildingLight._lastDist or FAR_STEPS*0.6 end
    end
    if d~=nil then BuildingLight._lastDist=d end
    BuildingLight.dist = d
    target = distToFactor(d)
    if target == nil then target = BuildingLight._factorRaw or 0.5 end
  end

  BuildingLight._factorRaw = target

  -- Time-based smoothing is intentionally gentle in BOTH directions. Distance
  -- supplies the main change; temporal easing removes tile-step/map-sample pops.
  -- Do not special-case a large delta with a fast snap: that was visible as the
  -- stars suddenly brightening after leaving a building.
  local f = BuildingLight.factor or target
  local k = 1 - math.exp(-SMOOTH * dt)
  f = f + (target - f) * k
  BuildingLight.factor = clamp01(f)

  local ff = BuildingLight.factor
  BuildingLight.ambientMul = AMBIENT_NEAR + (AMBIENT_FAR - AMBIENT_NEAR) * ff
  BuildingLight.starMul = STAR_NEAR + (STAR_FAR - STAR_NEAR) * ff
end

function BuildingLight.nightAmbientScale()
  if not isTrueNight() then return 1 end
  return BuildingLight.ambientMul or 1
end

function BuildingLight.starScale()
  -- Track/apply local light pollution continuously, even while the sky itself
  -- is invisible in daylight. This prevents dusk from starting with a stale
  -- building-distance multiplier and makes approach/retreat symmetric.
  local m = BuildingLight.starMul
  if type(m) ~= "number" or m ~= m then m = STAR_FAR end
  if m < STAR_NEAR then m = STAR_NEAR end
  if m > STAR_FAR then m = STAR_FAR end
  return m
end

-- Named constellation contract: 0/near building is dimmest, 1/far is
-- brightest. Keeping this separate from generic starScale makes the direction
-- explicit and gives regression tests a stable authority to protect.
function BuildingLight.constellationScale()
  local f=BuildingLight.factor
  if type(f)~="number" or f~=f then f=1 end
  f=clamp01(f)
  return STAR_NEAR+(STAR_FAR-STAR_NEAR)*f
end

--- Debug snapshot for AI / HUD tools
function BuildingLight.debugInfo()
  return {
    dist = BuildingLight.dist,
    factor = BuildingLight.factor,
    factorRaw = BuildingLight._factorRaw,
    starMul = BuildingLight.starMul,
    ambientMul = BuildingLight.ambientMul,
    buildings = BuildingLight._buildings and #BuildingLight._buildings or 0,
    neighborhoodMaps = BuildingLight._neighborhoodMaps or 0,
    registryMaps = (function()
      local n = 0
      for _ in pairs(REGISTRY) do n = n + 1 end
      return n
    end)(),
    night = isTrueNight(),
  }
end

-- Narrow deterministic seams used by regression tests; no runtime caller needs
-- these and they do not mutate game state.
BuildingLight._testDims=dims
BuildingLight._testNearestDist=nearestDist
BuildingLight._testNeighborhoodBuildings=neighborhoodBuildings
BuildingLight._testDistToFactor=distToFactor

return BuildingLight
