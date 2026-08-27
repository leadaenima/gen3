-- Ruby Phase 85: maps.lua shards so LuaJIT can load baked scripts.
--   luajit tests/engine/ruby_map_pack_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby map pack")
local check = S.check
local eq = S.eq

local LuaWriter = require("src.import.LuaWriter")
local Gen3MapPack = require("src.import.Gen3MapPack")
local Game3 = require("src.core.Game3")

;(function()
local pack = {
  atlasCols = 8,
  mapCount = 2,
  start = "g0_9",
  tileSize = 16,
  tilesets = { atlasCols = 8 },
  maps = {
    g0_9 = {
      id = "g0_9",
      width = 8,
      height = 8,
      text = 'hello {PLAYER} { "nested" }',
      scripts = { { op = "msgbox", args = { 'say { "hi" }' } } },
    },
    g25_40 = {
      id = "g25_40",
      width = 5,
      height = 5,
      objects = { { x = 0, y = 0 }, { x = 0, y = 3 }, { x = 2, y = 3 } },
    },
  },
}
local src = LuaWriter.encode(pack)
local got, err = Gen3MapPack.split(src)
check(got ~= nil, "split compiles LuaWriter maps.lua (" .. tostring(err) .. ")")
eq(got.start, "g0_9", "index keeps start")
eq(got.atlasCols, 8, "and atlasCols")
eq(got.mapCount, 2, "and mapCount")
eq(#got.ids, 2, "both map ids")
eq(got.ids[1], "g0_9", "ids are sorted")
eq(got.maps.g0_9.width, 8, "Littleroot round-trips")
eq(got.maps.g0_9.text, 'hello {PLAYER} { "nested" }',
  "braces inside strings are not tables")
eq(got.maps.g0_9.scripts[1].args[1], 'say { "hi" }',
  "quoted braces inside IR strings survive")
eq(got.maps.g25_40.width, 5, "the truck round-trips")
end)()

;(function()
local index, maps = Gen3MapPack.indexFromPack({
  start = "g0_9",
  mapCount = 2,
  tilesets = { atlasCols = 32 },
  maps = { g25_40 = { id = "g25_40" }, g0_9 = { id = "g0_9" } },
})
eq(index.maps, nil, "the index does not embed map tables")
eq(index.tilesets, nil, "or tilesets")
eq(index.start, "g0_9", "start stays on the index")
eq(#index.ids, 2, "ids lists every map")
eq(index.ids[1], "g0_9", "sorted")
eq(index.ids[2], "g25_40", "truck second")
eq(maps.g0_9.id, "g0_9", "tables are returned beside the index")
end)()

;(function()
local cells = {}
for i = 1, 25 do cells[i] = 0 end
local truck = {
  id = "g25_40", width = 5, height = 5, connections = {},
  grid = cells, spawn = { x = 1, y = 2 },
  objects = {
    { x = 0, y = 0, localId = 1 },
    { x = 0, y = 3, localId = 2 },
    { x = 2, y = 3, localId = 3 },
  },
}
local g = Game3.new()
g.data.maps = { start = "g0_9", maps = { g25_40 = truck } }
function g.readSave()
  return { party = {}, bag = {}, flags = {}, mapId = "gone", x = 9, y = 9 }
end
check(g:continueSave(), "CONTINUE with a missing map still starts")
eq(g.phase, "play", "on the field, not the species list")
eq(g.map.id, "g25_40", "falling back to the truck")
end)()

;(function()
local g = Game3.new()
g:applyNewGameHideFlags()
eq(g.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB], true, "Birch starts out of the lab")
eq(g.flags[Game3.FLAG_HIDE_MOM_UPSTAIRS], true, "Mom starts downstairs")
eq(g.flags[Game3.FLAG_HIDE_NORMAN_PETALBURG_GYM], nil, "Dad stays in the gym")
local cells = {}
for i = 1, 16 do cells[i] = 0 end
local map = {
  id = "g_hide", width = 4, height = 4, grid = cells,
  objects = {
    { localId = 1, x = 1, y = 1, graphicsId = 7, flagId = 0 },
    { localId = 2, x = 2, y = 1, graphicsId = 7,
      flagId = Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN },
    { localId = 3, x = 3, y = 1, graphicsId = 7, trainerType = 1,
      flagId = Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN },
  },
}
g:resetNpcs(map)
local npcs = g:npcsFor(map)
eq(#npcs, 1, "flagged story NPCs and trainers stay off the map")
eq(npcs[1].localId, 1, "only the unflagged object spawned")
end)()

S.finish()
