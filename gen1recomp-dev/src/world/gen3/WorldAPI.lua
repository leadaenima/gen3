-- THE GEN 3 ARM OF mod.world.
--
-- `mod.world` is the route the loader's own error messages point mod authors
-- at -- "take the game from the game.ready payload and mod.world" -- and until
-- this file existed it lied on Ruby: Loader:_modApi resolved the arm with
-- `generation == 2 and gen2 or gen1`, so a Gen 3 boot fell through to
-- src/world/WorldAPI.lua. That is RED's world API wrapped around a Game3
-- instance. Every call found nil where it looked for `game.overworld`, and the
-- mod had no way to tell that from an empty map.
--
-- WHAT SHAPE RUBY IS.
--
-- Gen 1 has an OverworldController holding the map, and Gen 2 has a World; the
-- API on both is a thin reader over that object. Ruby has neither -- main.lua
-- branches to src/core/Game3.lua and that ONE object is the overworld, the
-- battle, every menu and the renderer. So `overworld()` here answers the game
-- itself when it is actually standing in a map, and the rest reads fields off
-- it: self.map (grid, width, height), self.playerX/playerY, self.facing.
--
-- A Gen 3 map cell is one 16-bit word, and all three things a caller wants are
-- packed into it -- fieldmap.c's own masks, and Game3 already has the readers:
--
--   metatile   bits 0-9    Game3.metatileOf
--   collision  bits 10-11  Game3.collisionOf
--   elevation  bits 12-15  Game3.elevationOf
--
-- That last one is why this file can answer a 3D renderer at all. Gen 2
-- records no height whatsoever, which is why the Johto profile of a voxel mod
-- has to infer terraces from floor art; Ruby hands the Y axis over directly,
-- and 386 of Hoenn's 394 maps carry more than one level.
--
-- WHAT IS DELIBERATELY NOT HERE.
--
-- Gen 1's WorldAPI is twenty-two methods: field actions, fly, NPC spawning,
-- script queueing, wild battles. Those are real work against Game3's own
-- systems and each wants its own evidence and its own test. Rather than stub
-- them into silence, every one of them is listed in UNIMPLEMENTED below and
-- answers `nil, reason` -- the same two-value shape the implemented ones use
-- for their own failures, so a caller that already handles "nil and a string"
-- needs no new branch, and an author reading the reason knows it is a gap
-- rather than a refusal.

local Logger = require("src.core.Logger")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

-- The live world. On Ruby that IS the game object -- but only once it is
-- actually standing in a map: during the boot cinema, the title and the
-- naming screen there is no world to read, and answering the game anyway
-- would hand back a map-less object that looks live.
function WorldAPI:overworld()
  local game = self.game
  if game and game.map and game.map.grid then return game end
  return nil
end

local function validCoordinate(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value)
end

-- Where the player is. `mapId` is the layout id Game3 keys maps by, so it is
-- comparable with what mapView() reports rather than with a Gen 1 map name.
function WorldAPI:current()
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  local map = ow.map
  return {
    mapId = map.id or ow.mapLayoutId,
    x = ow.playerX,
    y = ow.playerY,
    facing = ow.facing,
  }
end

-- ---------------------------------------------------------------- the cells
--
-- Zero-based cell coordinates, and out of bounds is an error rather than a
-- clamp. The cartridge itself border-extends outside the body (fieldmap.c
-- GetBorderBlockAt wraps a 2x2 patch), and a caller that wants that behaviour
-- should ask for it by name -- borderMetatileAt below -- instead of getting it
-- silently from a coordinate it thought was inside.
local function cellIndex(map, cx, cy)
  if not validCoordinate(cx) or not validCoordinate(cy) then
    return nil, "invalid cell coordinates"
  end
  local w, h = tonumber(map.width) or 0, tonumber(map.height) or 0
  if w <= 0 or h <= 0 then return nil, "map has no body" end
  if cx < 0 or cy < 0 or cx >= w or cy >= h then
    return nil, "cell out of bounds"
  end
  return cy * w + cx + 1
end

local Game3Cells = nil
local function cells()
  if Game3Cells == nil then
    local ok, mod = pcall(require, "src.core.Game3")
    Game3Cells = ok and mod or false
  end
  return Game3Cells or nil
end

-- The raw 16-bit word, for a caller that wants all three fields without
-- paying for three lookups.
function WorldAPI:cellAt(cx, cy)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  local map = ow.map
  local i, why = cellIndex(map, cx, cy)
  if not i then return nil, why end
  local word = map.grid[i]
  if not validCoordinate(word) then return nil, "cell unavailable" end
  return word
end

function WorldAPI:metatileAt(cx, cy)
  local word, why = self:cellAt(cx, cy)
  if not word then return nil, why end
  local G = cells()
  if not G then return nil, "cell readers unavailable" end
  return G.metatileOf(word)
end

function WorldAPI:collisionAt(cx, cy)
  local word, why = self:cellAt(cx, cy)
  if not word then return nil, why end
  local G = cells()
  if not G then return nil, "cell readers unavailable" end
  return G.collisionOf(word)
end

-- The Y axis. Gen 1 and Gen 2 have no equivalent to return.
function WorldAPI:elevationAt(cx, cy)
  local word, why = self:cellAt(cx, cy)
  if not word then return nil, why end
  local G = cells()
  if not G then return nil, "cell readers unavailable" end
  return G.elevationOf(word)
end

-- Gen 1's name for the same question, kept so a caller written against that
-- API reads the right thing here. `mapId` must match the active map, which
-- makes a stale read fail closed if a warp moved the player first.
function WorldAPI:activeBlockAt(mapId, bx, by)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  local map = ow.map
  local active = map.id or ow.mapLayoutId
  if mapId ~= nil and active ~= mapId then return nil, "map is not active" end
  return self:metatileAt(bx, by)
end

-- fieldmap.c GetBorderBlockAt: outside the body the cartridge repeats a 2x2
-- patch, indexed `(x + 1) & 1 + ((y + 1) & 1) * 2`. Named rather than folded
-- into metatileAt so that reading past the edge is always a decision.
function WorldAPI:borderMetatileAt(cx, cy)
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  local map = ow.map
  local border = map.border
  if type(border) ~= "table" or #border < 4 then
    return nil, "map has no border patch"
  end
  if not (validCoordinate(cx) and validCoordinate(cy)) then
    return nil, "invalid cell coordinates"
  end
  local G = cells()
  if not G then return nil, "cell readers unavailable" end
  local slot = (cx + 1) % 2 + ((cy + 1) % 2) * 2
  return G.metatileOf(border[slot + 1])
end

-- ------------------------------------------------------------- the map view
--
-- One read-only description of the active map, shaped for a renderer: the
-- dimensions, the three per-cell planes and enough about the tileset to find
-- the art. Built fresh per call rather than cached, because a warp replaces
-- the map underneath and a cached view would keep drawing the old one.
--
-- `collisionCells` and `elevationCells` are flat arrays in row-major order,
-- one entry per cell, because that is the shape a mesher walks. They are
-- derived here rather than stored, since the grid word already holds both and
-- a second copy could disagree with it.
function WorldAPI:mapView()
  local ow = self:overworld()
  if not ow then return nil, NO_OVERWORLD end
  local G = cells()
  if not G then return nil, "cell readers unavailable" end
  local map = ow.map
  local w, h = tonumber(map.width) or 0, tonumber(map.height) or 0
  if w <= 0 or h <= 0 then return nil, "map has no body" end

  local metatiles, collision, elevation = {}, {}, {}
  for i = 1, w * h do
    local word = map.grid[i] or 0
    metatiles[i] = G.metatileOf(word)
    collision[i] = G.collisionOf(word)
    elevation[i] = G.elevationOf(word)
  end

  local api = self
  return {
    id = map.id or ow.mapLayoutId,
    width = w,
    height = h,
    -- the three planes, row-major, one entry per cell
    metatileCells = metatiles,
    collisionCells = collision,
    elevationCells = elevation,
    -- A Gen 3 METATILE is 16x16 and IS one collision cell, where a Gen 1/2
    -- block is 32x32 holding four. A renderer reads these two numbers instead
    -- of asking which game is running.
    blockTiles = 2,
    blockCells = 1,
    outdoor = G.isOutdoorMapType and G.isOutdoorMapType(map.mapType) or false,
    mapType = map.mapType,
    metatileAt = function(_, cx, cy) return api:metatileAt(cx, cy) end,
    collisionAt = function(_, cx, cy) return api:collisionAt(cx, cy) end,
    elevationAt = function(_, cx, cy) return api:elevationAt(cx, cy) end,
    borderMetatileAt = function(_, cx, cy)
      return api:borderMetatileAt(cx, cy)
    end,
  }
end

-- --------------------------------------------------------------- the gaps
--
-- Named, not silent. Each of these is a real piece of work against Game3's own
-- systems -- not a refusal -- and every one answers the same `nil, reason`
-- shape the implemented methods use for their failures.
local UNIMPLEMENTED = {
  canReorderParty = "party reordering is not wired to Game3 yet",
  reorderParty = "party reordering is not wired to Game3 yet",
  availableFieldActions = "field moves live in Game3's own field handler",
  useFieldAction = "field moves live in Game3's own field handler",
  canFly = "Ruby's fly is driven by the region map screen",
  flyTo = "Ruby's fly is driven by the region map screen",
  mapOverview = "no Gen 3 map overview is assembled yet",
  warpTo = "warps run through Game3's script VM",
  toggleObject = "object visibility runs through Game3's script VM",
  setFlag = "flags are Game3.flags; no Gen 3 flag API is published yet",
  getFlag = "flags are Game3.flags; no Gen 3 flag API is published yet",
  replaceBlock = "writing the map grid back is not exposed yet",
  spawnNpc = "NPC spawning runs through Game3's object events",
  removeNpc = "NPC spawning runs through Game3's object events",
  npc = "NPC reads run through Game3's object events",
  queueScript = "scripts run through Game3's own VM",
  startWildBattle = "battles are started by Game3 directly",
  invalidateMap = "Game3 rebuilds its own tile batches",
}

local warned = {}
for name, reason in pairs(UNIMPLEMENTED) do
  WorldAPI[name] = function(self)
    if not warned[name] then
      warned[name] = true
      Logger.warn("mod.world:%s has no Gen 3 arm: %s", name, reason)
    end
    return nil, reason
  end
end

-- Published so the mod manager and the tests can read the gaps rather than
-- discovering them one runtime warning at a time.
WorldAPI.UNIMPLEMENTED = UNIMPLEMENTED

return WorldAPI
