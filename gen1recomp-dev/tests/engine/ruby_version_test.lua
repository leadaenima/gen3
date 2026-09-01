-- Ruby registration: VERSIONS row, Gen 3 engine, ORDER slot, SHA-1 routing,
-- GBA header / species-name decode, importer cache override, Game3 stub.
--   luajit tests/engine/ruby_version_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby version registration")
local check = S.check
local eq = S.eq

local GameVersion = require("src.core.GameVersion")
local GbaHeader = require("src.import.GbaHeader")
local GbaText = require("src.import.GbaText")
local RomExtractorGen3 = require("src.import.RomExtractorGen3")
local CacheContract = require("src.import.CacheContract")
local Game3 = require("src.core.Game3")

local RUBY_SHA1 = "f28b6ffc97847e94a6c21a63cacf633ee5c8df1e"

-- ------- 1. the VERSIONS row

local row = GameVersion.VERSIONS.ruby
check(row ~= nil, "GameVersion.VERSIONS carries a ruby row")
eq(row.id, "ruby", "row id")
eq(row.label, "Ruby", "row label")
eq(row.displayName, "Pokemon Ruby", "row display name")
eq(row.launcherName, "Ruby (Alpha)", "launcher says Alpha")
eq(row.sha1, RUBY_SHA1, "US Ruby 1.0 sha1")
eq(row.manifest, "tools/rom_manifest_ruby.json", "row manifest path")
eq(row.cachePrefix, "ruby/", "cache prefix")
eq(row.saveSuffix, "_ruby", "save suffix")
eq(row.generation, 3, "generation field")
eq(row.engine, "gen3", "engine lineage")
eq(row.gameCode, "AXVE", "US Ruby game code")
eq(GameVersion.generation("ruby"), 3, "generation() is 3")
eq(GameVersion.engine("ruby"), "gen3", "engine() is gen3")
eq(GameVersion.cachePrefix("ruby"), "ruby/", "cachePrefix() agrees")
eq(GameVersion.saveSuffix("ruby"), "_ruby", "saveSuffix() agrees")

local prefixes, suffixes = {}, {}
for _, id in ipairs(GameVersion.ORDER) do
  local info = GameVersion.info(id)
  eq(prefixes[info.cachePrefix], nil, id .. " cache prefix is unique")
  eq(suffixes[info.saveSuffix], nil, id .. " save suffix is unique")
  prefixes[info.cachePrefix] = id
  suffixes[info.saveSuffix] = id
end

-- ------- 2. launcher ORDER is append-only

local index
for i, id in ipairs(GameVersion.ORDER) do
  if id == "ruby" then index = i end
end
eq(index, 7, "ruby is ORDER slot 7")
eq(#GameVersion.ORDER, 7, "ORDER is seven games")
eq(GameVersion.ORDER[4], "gold", "gold keeps slot 4")
eq(GameVersion.ORDER[6], "crystal", "crystal keeps slot 6")

-- ------- 3. sha1 routing

eq(GameVersion.forSha1(RUBY_SHA1), "ruby",
  "the US Ruby sha1 resolves to ruby")
eq(GameVersion.forSha1("d8b8a3600a465308c9953dfa04f0081c05bdcb94"), "gold",
  "Gold's sha1 still resolves to gold")
eq(GameVersion.forSha1("deadbeef"), nil, "an unknown ROM resolves to nothing")
check(GameVersion.acceptsSha1("ruby", RUBY_SHA1), "ruby accepts its sha1")
check(not GameVersion.acceptsSha1("ruby", "deadbeef"), "ruby rejects junk")

-- ------- 4. GBA header (fixture bytes, not the cart)

local function pad(text, n)
  return (text .. string.rep("\0", n)):sub(1, n)
end

local function gbaHeader(title, code, maker, version)
  local data = string.rep("\0", 0xA0)
    .. pad(title, 12)
    .. pad(code, 4)
    .. pad(maker, 2)
    .. string.rep("\0", 0xBC - 0xB2)
    .. string.char(version or 0)
    .. string.rep("\0", 3)
  eq(#data, 0xC0, "fixture header is 0xC0 bytes")
  return data
end

local headerBytes = gbaHeader("POKEMON RUBY", "AXVE", "01", 0)
local header = GbaHeader.parse(headerBytes)
eq(header.title, "POKEMON RUBY", "parses the 12-byte title")
eq(header.gameCode, "AXVE", "parses the game code")
eq(header.maker, "01", "parses the maker code")
eq(header.version, 0, "parses the revision byte")
check(GbaHeader.isRubyUsa(header), "AXVE is US Ruby")
check(not GbaHeader.isRubyUsa({ gameCode = "AXPE" }), "Sapphire is not Ruby")
eq(GbaHeader.parse("short"), nil, "rejects a truncated blob")

-- ------- 5. species names (encoded, not ASCII)

eq(GbaText.encodeLatin("BULBASAUR"),
  string.char(0xBC, 0xCF, 0xC6, 0xBC, 0xBB, 0xCD, 0xBB, 0xCF, 0xCC),
  "BULBASAUR is the GBA Latin encoding")
eq(GbaText.decodeName(GbaText.encodeLatin("TREECKO") .. string.char(0xFF)),
  "TREECKO", "decode round-trips TREECKO")
eq(GbaText.decodeByte(0x1B), "e", "CHAR é is ASCII e")
eq(GbaText.decodeName(string.char(
  0xCA, 0xC9, 0xC5, 0x1B, 0x00, 0xBC, 0xBB, 0xC6, 0xC6, 0xFF)),
  "POKe BALL", "POKé BALL keeps the e")

local function nameRow(text)
  if not text then
    return string.rep(string.char(GbaText.PLACEHOLDER), 10)
      .. string.char(GbaText.EOS)
  end
  local enc = GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
  if #enc < GbaText.NAME_LENGTH then
    enc = enc .. string.rep("\0", GbaText.NAME_LENGTH - #enc)
  end
  return enc:sub(1, GbaText.NAME_LENGTH)
end

local names = {}
for i = 0, 411 do names[i] = nameRow(nil) end
names[0] = nameRow(nil)
names[1] = nameRow("BULBASAUR")
names[251] = nameRow("CELEBI")
names[277] = nameRow("TREECKO")
names[411] = nameRow("CHIMECHO")

local blob = headerBytes
for i = 0, 411 do blob = blob .. names[i] end

local decoded = RomExtractorGen3.decodeSpeciesNames(blob)
check(decoded ~= nil, "extractor finds the name table in a stub ROM")
eq(decoded[1], "BULBASAUR", "index 1 is Bulbasaur")
eq(decoded[251], "CELEBI", "index 251 is Celebi")
eq(decoded[277], "TREECKO", "index 277 is Treecko (internal order, not national)")
eq(decoded[411], "CHIMECHO", "index 411 is Chimecho")
eq(RomExtractorGen3.decodeSpeciesNames("no names here"), nil,
  "missing BULBASAUR encoding is not a table")

-- ------- 6. cache contract is a short override, not the Gen 1 PNG list

local required, isOverride = CacheContract.requiredFilesFor("ruby")
check(isOverride == true, "ruby has its own required-file override")
eq(#required, 40,
  "Birch / menu copy, window and battle chrome, MP2K audio, and menu art")
local seen = {}
for _, path in ipairs(required) do seen[path] = true end
check(seen["data/generated/constants.lua"], "constants.lua is required")
check(seen["data/generated/pokemon.lua"], "pokemon.lua is required")
check(seen["data/generated/header.lua"], "header.lua is required")
check(seen["data/generated/maps.lua"], "maps.lua is required")
check(seen["data/generated/tilesets.lua"], "tilesets.lua is required")
check(seen["assets/generated/tilesets/pair_0_bottom.png"],
  "the first tileset pair bottom atlas is required")
check(seen["assets/generated/tilesets/pair_0_top.png"],
  "the first tileset pair top atlas is required")
check(seen["data/generated/sprites.lua"], "sprites.lua is required")
check(seen["assets/generated/sprites/ow_0.png"],
  "Brendan's overworld sprite is the cache sentinel")
check(seen["data/generated/encounters.lua"], "encounters.lua is required")
check(seen["data/generated/moves.lua"], "moves.lua is required")
check(seen["data/generated/trainers.lua"], "trainers.lua is required")
check(seen["data/generated/items.lua"], "items.lua is required")
check(seen["assets/generated/battle/front/280.png"],
  "Torchic's front pic is the battle sentinel")
check(seen["assets/generated/battle/back/280.png"],
  "Torchic's back pic is required")
check(seen["data/generated/font.lua"], "font.lua is required")
check(seen["assets/generated/fonts/font.png"],
  "the latin FONT3 sheet is required")
check(seen["data/generated/title.lua"], "Birch and menu copy is required")
check(not seen["assets/generated/battle/front/pikachu.png"],
  "the Gen 1 Pikachu PNG is not required")
check(seen["data/generated/audio.lua"], "the MP2K registry is required")
check(seen["assets/generated/audio/mp2k.bin"], "the MP2K blob is required")
check(seen["data/generated/menus.lua"], "the menu registry is required")
check(seen["assets/generated/icons/mon_icons.png"], "so is the icon atlas")
check(seen["assets/generated/party/tiles.png"], "and the party tile atlas")
check(seen["assets/generated/egg_hatch/egg.png"],
  "the hatch egg sheet is required")
check(seen["assets/generated/trade/cable.png"],
  "the in-game trade cable closeup is required")
check(seen["assets/generated/rotating_gates/3.png"],
  "the Fortree L4 rotating-gate sheet is required")
check(seen["assets/generated/sprites/ow_62.png"],
  "the ripe berry-tree sheet is required")
check(seen["assets/generated/sprites/ow_191.png"],
  "Brendan's watering sheet is required")
check(seen["assets/generated/field/pokeball_glow.png"],
  "the HoF pokéball glow tile is required")
check(seen["assets/generated/pokenav/region_map.png"],
  "the painted Hoenn region map is required")
eq(CacheContract.formatFor("ruby"), "rom-cache-v10-ruby41:",
  "ripe berry-tree frames bump the cache marker")

-- ------- 7. Game3 stub

eq(Game3.SCREEN_W, 240, "GBA width")
eq(Game3.SCREEN_H, 160, "GBA height")
local game = Game3.new()
eq(game.phase, "boot", "starts on the title")
eq(game.boot.kind, Game3.BOOT_COPYRIGHT, "the first screen is the copyright card")
game.named = { { id = 277, name = "TREECKO" } }
game:advance()
eq(game.phase, "roster", "A advances to the species list when no map is cached")

local town = Game3.new()
town.map = {
  id = "littleroot_town",
  name = "Littleroot Town",
  width = 2,
  height = 2,
  spawn = { x = 0, y = 0 },
  grid = { 0, 1024, 0, 0 },
}
town.playerX, town.playerY = 0, 0
town:advance()
eq(town.phase, "play", "A walks into town when a map is cached")
check(Game3.walkable(town.map, 0, 0), "spawn cell is walkable")
check(not Game3.walkable(town.map, 1, 0), "collision bit 1 is blocked")
check(town:tryWalk(1, 0) == false, "blocked step is rejected")
eq(town.playerX, 0, "blocked step does not move X")
check(town:tryWalk(0, 1) == true, "open step is accepted")
eq(town.playerY, 1, "open step moves Y")

local wet = Game3.new()
wet.phase = "play"
wet.map = {
  width = 2, height = 1, grid = { 0, 0 },
  behavior = { 0, Game3.MB_OCEAN_WATER },
}
wet.playerX, wet.playerY = 0, 0
check(not wet:canStep(wet.map, 1, 0), "ocean is blocked without Surf")
check(wet:tryWalk(1, 0) == false, "and tryWalk refuses it")
wet.surfing = true
check(wet:canStep(wet.map, 1, 0), "Surf walks ocean")

local LauncherView = require("src.import.LauncherView")
local sawRubyTab
for _, tab in ipairs(LauncherView.GAME_TABS) do
  if tab.id == "ruby" then sawRubyTab = tab end
end
check(sawRubyTab ~= nil, "Choose game lists ruby")
eq(sawRubyTab.label, "Ruby (Alpha)", "the dropdown row uses the Alpha launcher name")
eq(#LauncherView.GAME_TABS, #GameVersion.ORDER,
  "every ORDER game has a cartridge-dropdown row")

eq(table.concat(require("src.mods.ModTargets").expand("gen3"), ","), "ruby",
  "gen3 token expands to ruby")

local RomImporter = require("src.import.RomImporter")
local visited = {}
local fake = setmetatable({ tab = GameVersion.ORDER[1] }, RomImporter)
fake._switchTab = function(self, id)
  self.tab = id
  visited[#visited + 1] = id
end
for _ = 1, 14 do fake:_cycleTab(1) end
local sawRuby = false
for _, id in ipairs(visited) do
  if id == "ruby" then sawRuby = true end
end
check(sawRuby, "cycling the launcher tabs reaches ruby")

fake.tab = "ruby"
fake:_cycleTab(-1)
eq(fake.tab, "crystal", "stepping back off ruby lands on crystal")

S.finish()
