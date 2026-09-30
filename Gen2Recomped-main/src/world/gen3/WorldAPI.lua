-- Gen 3 WorldAPI: the `mod.world` arm for a Ruby boot.
--
-- Until this file existed `mod.world` LIED on Ruby -- Loader:_modApi resolved
-- the arm with `generation == 2 and gen2 or gen1`, so a Gen 3 boot fell
-- through to Red's WorldAPI wrapped around a Game3 instance, every call
-- finding nil where it looked for game.overworld, indistinguishable from an
-- empty map.
--
-- Two things this deliberately does NOT do:
--
--   * it does not gate on displayGateOK.  A party menu sets game.field, and
--     gating there would hide the overworld from free_fly's takeoff path for
--     the whole time a menu is up;
--   * it does not cache the map view.  A warp replaces game.map underneath a
--     mod that is still holding one, and a cached view would answer for the
--     map the player has already left.
--
-- Where Ruby has no answer the method says so BY NAME through UNIMPLEMENTED
-- rather than returning a bare nil: every entry there is a real verb a Gen
-- 1-shaped mod reaches for and Game3 has no equivalent of.

local WorldAPI = {}
WorldAPI.__index = WorldAPI

-- fieldmap.c packs one 16-bit word per cell and these are its three planes.
-- Read with arithmetic rather than bit operators so the file stays correct on
-- a Lua 5.1 host, which has none.
local METATILE_SPAN = 1024   -- bits 0-9
local COLLISION_SPAN = 4     -- bits 10-11
local ELEVATION_SPAN = 16    -- bits 12-15

local function game3()
  return require("src.core.Game3")
end

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

local function mapOf(self)
  local g = self.game
  if type(g) ~= "table" then return nil end
  local map = g.map
  if type(map) ~= "table" then return nil end
  return map, g
end

-- The live overworld view, or nil when there is no map to have one.  During
-- the boot cinema and the title there is nothing to read, and answering the
-- game anyway would hand back a live-looking object.
function WorldAPI:overworld()
  local map, g = mapOf(self)
  if not map then return nil end
  if type(g.modOverworld) == "function" then
    local ok, ow = pcall(g.modOverworld, g)
    if ok and ow then return ow end
  end
  return g.overworld
end

function WorldAPI:current()
  local map, g = mapOf(self)
  if not map then return nil, "no overworld" end
  return { mapId = map.id, x = g.playerX, y = g.playerY, facing = g.facing }
end

-- ---------------------------------------------------------- the cell readers
--
-- Out of bounds is an ERROR, not a clamp.  The cartridge border-extends past
-- the edge and a caller that wants that has to ask for it by name
-- (borderMetatileAt), because quietly answering the nearest in-bounds cell
-- reads as real terrain to anything walking the map.

local function cellWord(map, x, y)
  if type(x) ~= "number" or type(y) ~= "number"
      or x ~= math.floor(x) or y ~= math.floor(y) then
    return nil, "invalid cell coordinates"
  end
  local w, h = tonumber(map.width) or 0, tonumber(map.height) or 0
  if x < 0 or y < 0 or x >= w or y >= h then
    return nil, "cell out of bounds"
  end
  local grid = map.grid
  if type(grid) ~= "table" then return nil, "map has no grid" end
  local word = grid[y * w + x + 1]
  if type(word) ~= "number" then return nil, "cell out of bounds" end
  return word
end

local function planeOf(word, span, below)
  return math.floor(word / below) % span
end

function WorldAPI:metatileAt(x, y)
  local map = mapOf(self)
  if not map then return nil, "no overworld" end
  local word, why = cellWord(map, x, y)
  if not word then return nil, why end
  return word % METATILE_SPAN
end

function WorldAPI:collisionAt(x, y)
  local map = mapOf(self)
  if not map then return nil, "no overworld" end
  local word, why = cellWord(map, x, y)
  if not word then return nil, why end
  return planeOf(word, COLLISION_SPAN, METATILE_SPAN)
end

function WorldAPI:elevationAt(x, y)
  local map = mapOf(self)
  if not map then return nil, "no overworld" end
  local word, why = cellWord(map, x, y)
  if not word then return nil, why end
  return planeOf(word, ELEVATION_SPAN, METATILE_SPAN * COLLISION_SPAN)
end

-- GetBorderBlockAt wraps a 2x2 patch by coordinate parity, so the border
-- repeats outward from the map edge in both axes.
function WorldAPI:borderMetatileAt(x, y)
  local map = mapOf(self)
  if not map then return nil, "no overworld" end
  if type(x) ~= "number" or type(y) ~= "number"
      or x ~= math.floor(x) or y ~= math.floor(y) then
    return nil, "invalid cell coordinates"
  end
  local border = map.border
  if type(border) ~= "table" then return nil, "map has no border" end
  local index = (x + 1) % 2 + ((y + 1) % 2) * 2
  local word = border[index + 1]
  if type(word) ~= "number" then return nil, "map has no border" end
  return word % METATILE_SPAN
end

-- Fails closed when the map moved under a stale caller: a mod holding a map id
-- across a warp is told, rather than reading the new map's cell as though it
-- belonged to the old one.
function WorldAPI:activeBlockAt(mapId, x, y)
  local map = mapOf(self)
  if not map then return nil, "no overworld" end
  if map.id ~= mapId then return nil, "map is not active" end
  return self:metatileAt(x, y)
end

-- ------------------------------------------------------------------ map view
--
-- The shape a renderer walks, built from the grid on every call.  The three
-- planes are DERIVED, never a second stored copy that could drift out of step
-- with the grid they came from.
--
-- blockTiles / blockCells exist so a renderer need not ask which game it is
-- in: a Gen 3 metatile is 16x16 and IS one collision cell, where a Gen 1/2
-- block is 32x32 holding four.
function WorldAPI:mapView()
  local map = mapOf(self)
  if not map then return nil, "no overworld" end
  local w, h = tonumber(map.width) or 0, tonumber(map.height) or 0
  local metatiles, collisions, elevations = {}, {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = y * w + x + 1
      local word = cellWord(map, x, y) or 0
      metatiles[i] = word % METATILE_SPAN
      collisions[i] = planeOf(word, COLLISION_SPAN, METATILE_SPAN)
      elevations[i] = planeOf(word, ELEVATION_SPAN,
                              METATILE_SPAN * COLLISION_SPAN)
    end
  end
  return {
    id = map.id, width = w, height = h,
    metatileCells = metatiles,
    collisionCells = collisions,
    -- the Y axis Gen 2 records nowhere at all
    elevationCells = elevations,
    blockTiles = 2, blockCells = 1,
    outdoor = game3().isOutdoorMapType(map.mapType) and true or false,
  }
end

-- ------------------------------------------------------------- the verbs
--
-- EVERY REFUSAL HAPPENS BEFORE THE GAME IS TOUCHED.  A verb that validates
-- half its arguments, warps, and then discovers the third one was nonsense
-- has already moved the player; the tests here assert `#g.warps == 0` after
-- each refusal for exactly that reason.

-- Hoenn's map ids are "g<group>_<num>", which is also how Game3 keys
-- data.maps.maps.  A Gen 1-shaped name ("PALLET_TOWN") is refused with the
-- shape spelled out, because the author's next question is always what it
-- should have looked like.
local function parseMapId(mapId)
  if type(mapId) ~= "string" then return nil end
  local group, num = mapId:match("^g(%d+)_(%d+)$")
  if not group then return nil end
  return tonumber(group), tonumber(num)
end

local function wholeNumber(v)
  return type(v) == "number" and v == math.floor(v)
end

function WorldAPI:warpTo(mapId, x, y, facing)
  local map, g = mapOf(self)
  if not map then return nil, "no overworld" end
  local group, num = parseMapId(mapId)
  if not group then
    return nil, ("not a Gen 3 map id: %s (they look like g0_9)")
      :format(tostring(mapId))
  end
  if type(g.lookupMap) ~= "function" or not g:lookupMap(group, num) then
    return nil, "unknown map: " .. mapId
  end
  if not (wholeNumber(x) and wholeNumber(y)) then
    return nil, "warp coordinates must be whole numbers"
  end
  if type(g.scriptWarp) ~= "function" then
    return nil, "this game cannot script a warp"
  end
  -- the game's own verb does the work; a facing is applied only once the warp
  -- has been accepted, so a refusal leaves the player facing where they were
  local ok = g:scriptWarp(group, num, nil, x, y)
  if not ok then return nil, "the game refused the warp" end
  if facing ~= nil then g.facing = facing end
  return true
end

-- Hoenn's own rule, not the party's: FLY needs the move, the badge that
-- authorises it, and an OUTDOOR map -- the cart refuses indoors even with
-- both.  All three are asked separately so no one of them can stand in for
-- another.
local FLY_BADGE = 6

function WorldAPI:canFly()
  local map, g = mapOf(self)
  if not map then return false end
  local Game3 = game3()
  if type(g.partyKnowsMove) ~= "function"
      or not g:partyKnowsMove(Game3.MOVE_FLY) then
    return false
  end
  if type(g.hasBadge) ~= "function" or not g:hasBadge(FLY_BADGE) then
    return false
  end
  return Game3.isOutdoorMapType(map.mapType) and true or false
end

function WorldAPI:flyTo(mapId)
  local map, g = mapOf(self)
  if not map then return nil, "no overworld" end
  if not self:canFly() then
    return nil, "this game cannot fly from here right now"
  end
  if not parseMapId(mapId) then
    return nil, ("not a Gen 3 map id: %s (they look like g0_9)")
      :format(tostring(mapId))
  end
  if type(g.flyTo) ~= "function" then return nil, "this game cannot fly" end
  return g:flyTo(mapId) and true or nil
end

function WorldAPI:startWildBattle(species, level)
  local map, g = mapOf(self)
  if not map then return nil, "no overworld" end
  -- Ruby numbers its species and its levels; a name here would be a Gen 1
  -- habit, and coercing one silently would start a battle with the wrong mon
  if type(species) ~= "number" then
    return nil, "species must be the cart's own number"
  end
  if type(level) ~= "number" then return nil, "level must be a number" end
  if type(g.startWildBattle) ~= "function" then
    return nil, "this game cannot start a wild battle"
  end
  return g:startWildBattle(species, level) and true or nil
end

-- ---------------------------------------------------------- the honest gaps
--
-- Published as a table rather than discovered one warning at a time, so an
-- author can ask what Ruby cannot do before writing against it.  Each answers
-- nil and its own reason -- the same shape a real failure returns.
WorldAPI.UNIMPLEMENTED = {
  spawnNpc = "Ruby draws the object events its map declares; there is no "
    .. "runtime object store to add one to",
  removeNpc = "same store: an object event is map data, not an entry in a "
    .. "live entity list",
  npc = "no runtime object store to look one up in",
  queueScript = "Game3 runs the cart's own script bytecode, not a Lua row list",
  setFlag = "flags live in the Gen 3 save struct and are written through the "
    .. "script VM, not by id from outside it",
  getFlag = "same struct: reading one by a Gen 1 flag name would answer for a "
    .. "different bit",
  toggleObject = "object visibility is a script flag on Ruby, not a property "
    .. "of a live entity",
  replaceBlock = "the metatile grid is rebuilt from the cart's layout on every "
    .. "map entry, so a written cell would not survive a warp",
  invalidateMap = "Game3 owns its own tile batches and rebuilds them itself",
  mapOverview = "Ruby's region map is a Gen 3 screen with its own layout, not "
    .. "a Gen 1 overview record",
  useFieldAction = "field moves are dispatched by the script VM through the "
    .. "party menu, not by name from outside",
  availableFieldActions = "same dispatch: there is no list to enumerate",
  reorderParty = "the party is reordered inside Game3's own party screen",
  canReorderParty = "same screen owns the rule",
}

for name, reason in pairs(WorldAPI.UNIMPLEMENTED) do
  WorldAPI[name] = function() return nil, reason end
end

return WorldAPI
