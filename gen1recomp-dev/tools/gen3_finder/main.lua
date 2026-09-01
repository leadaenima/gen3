-- Dev harness: re-extract the menu assets into the ruby cache and render
-- the party screen through the real Game3, so the small-font change can
-- be checked against the box edges.
--
-- Run from the repo:  lovec tools/gen3_finder
-- PNG dumps go to tmp/debug/ (never the process CWD / Desktop).
local ROM = "C:/Users/Feces/Desktop/Pokemon - Ruby Version (USA).gba"

local function repoRoot()
  local src = (love.filesystem.getSource() or ""):gsub("\\", "/")
  return src:match("^(.*)/tools/gen3_finder/?$")
    or "C:/Users/Feces/Desktop/pkmn gen1recomp/gen1recomp-dev"
end

local REPO = repoRoot()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local SCALE = 3
local OUT = REPO .. "/tmp/debug"

local function ensureDir(path)
  local ok, ffi = pcall(require, "ffi")
  if not ok then return end
  pcall(ffi.cdef,
    "int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);")
  pcall(ffi.C.CreateDirectoryA, path, nil)
end

local function writePng(img, name)
  ensureDir(REPO .. "/tmp")
  ensureDir(OUT)
  local fd = img:encode("png")
  local f = assert(io.open(OUT .. "/" .. name, "wb"))
  f:write(fd:getString())
  f:close()
  print("wrote " .. OUT .. "/" .. name)
end

local function run()
  local CacheFs = require("src.import.CacheFs")
  local LuaWriter = require("src.import.LuaWriter")
  local Icons = require("src.import.RomExtractorGen3Icons")
  local Party = require("src.import.RomExtractorGen3Party")

  local f = io.open(ROM, "rb")
  local rom = f:read("*a")
  f:close()

  CacheFs.prefix = "ruby/"
  CacheFs.mountVersion("ruby")
  print("font4 valid: " .. tostring(Party.validFont4(rom)))
  local icons = Icons.extract(rom)
  local party = Party.extract(rom)
  print("icons: " .. tostring(icons ~= nil) .. "  party: " .. tostring(party ~= nil))
  if not party then return end
  print(string.format("font sheet %s, width of '0' = %s, of '/' = %s",
    tostring(party.font), tostring(party.fontWidths[0xA1]),
    tostring(party.fontWidths[0xBA])))
  LuaWriter.write("data/generated/menus.lua", { icons = icons, party = party })

  local Game3 = require("src.core.Game3")
  local game = Game3.new()
  game:load()

  -- Internal species numbers, not dex numbers: 277 Treecko, 25 Pikachu.
  game.party = {
    { species = 277, name = "TREECKO", level = 14, hp = 41, maxHp = 41,
      gender = "male" },
    { species = 25, name = "PIKACHU", level = 12, hp = 20, maxHp = 33,
      status = "psn", gender = "female", item = 13 },
    { species = 288, name = "MUDKIP", level = 100, hp = 9, maxHp = 248,
      gender = "male" },
    { species = 290, name = "ZIGZAGOON", level = 9, hp = 0, maxHp = 27,
      gender = "female" },
    { species = 183, name = "MARILL", level = 11, hp = 30, maxHp = 30,
      item = 121 },
  }
  game.vblank = 0

  local canvas = love.graphics.newCanvas(240, 160)
  canvas:setFilter("nearest", "nearest")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  game:drawPartyScreen({ kind = "party", cursor = 1,
    prompt = "Choose a POKeMON." })
  love.graphics.setCanvas()

  local big = love.graphics.newCanvas(240 * SCALE, 160 * SCALE)
  big:setFilter("nearest", "nearest")
  love.graphics.setCanvas(big)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, 0, 0, 0, SCALE, SCALE)
  love.graphics.setCanvas()
  writePng(big:newImageData(), "party_runtime_big.png")
end

function love.load()
  local ok, err = pcall(run)
  if not ok then print("HARNESS ERROR: " .. tostring(err)) end
  love.event.quit()
end
