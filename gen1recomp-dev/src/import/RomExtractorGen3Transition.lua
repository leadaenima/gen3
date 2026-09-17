-- Gen 3 battle-transition mugshot backgrounds, read from the player's own cart.
--
-- Baked from the decomp into assets/generated/battle/transitions/ by
-- tools/bake_champion_endgame.py; that tree is excluded from game.love, so
-- Game3BattleTransition found none of it on device.
--
-- Reached from the literal pool at 0x11C284, which holds the tilemap, the tile
-- graphics, and both palette pointer tables. Two details are not guessable and
-- cost real time to establish:
--
--   * The tiles are stored with each 4bpp nibble INVERTED relative to the
--     decomp's grayscale strip (which encodes index = gray // 17). Rendering is
--     therefore pal[15 - n]. Searching the cart for the strip's own bytes finds
--     nothing; searching for the inverted form lands exactly on the pool's gfx
--     pointer, 0x3FC348.
--   * The final palette is the opponent's with slots 10..15 overwritten by the
--     player's first six colours -- battle_transition.c's LoadPalette(0xFA, 0xC).
--     For Brendan this happens to be a no-op against every Elite Four palette;
--     for May it is not, which is what separates the _may variants.
--
-- All 15 backgrounds reproduce the baked art with zero differing pixels.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Transition = {}

Transition.RUBY_US = {
  tiles = 0x3FC348,        -- nibble-inverted 4bpp, uncompressed
  tilemap = 0x3FDFF4,      -- 32x20 entries
  opponentPals = 0x3FDB00, -- pointer table: sidney, phoebe, glacia, drake, steven
  playerPals = 0x3FDB14,   -- pointer table: brendan, may
  stevenGfx = 0xE4EE14,    -- 64x64 mugshot, lz77
  stevenPal = 0xE5A460,    -- lz77
}

Transition.NAMES = { "sidney", "phoebe", "glacia", "drake", "steven" }
Transition.DIR = "assets/generated/battle/transitions/"
Transition.COLS, Transition.ROWS = 32, 20
Transition.FULL_W, Transition.SCREEN_W, Transition.SCREEN_H = 256, 240, 160

local function bgr555(v)
  return (v % 32) / 31,
    (math.floor(v / 32) % 32) / 31,
    (math.floor(v / 1024) % 32) / 31
end

local function romOffset(ptr)
  if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
  return ptr - 0x08000000
end

local function palAt(data, off)
  local pal = {}
  for i = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(data, off + i * 2))
    pal[i] = { r, g, b }
  end
  return pal
end

local function palFromTable(data, base, index)
  local off = romOffset(GbaBin.u32(data, base + index * 4))
  if not off then return nil end
  return palAt(data, off)
end

-- LoadPalette(0xFA, 0xC): the player's six colours land in the opponent's
-- slots 10..15.
function Transition.mergedPalette(data, opponent, player)
  local pal = palFromTable(data, Transition.RUBY_US.opponentPals, opponent)
  local pl = palFromTable(data, Transition.RUBY_US.playerPals, player)
  if not (pal and pl) then return nil end
  for i = 0, 5 do pal[10 + i] = pl[i] end
  return pal
end

function Transition.renderBackground(data, opponent, player, width)
  local u = Transition.RUBY_US
  local pal = Transition.mergedPalette(data, opponent, player)
  if not pal then return nil end
  width = width or Transition.FULL_W
  local image = ImageWriter.blank(width, Transition.SCREEN_H, 0, 0, 0, 1)
  for row = 0, Transition.ROWS - 1 do
    for col = 0, Transition.COLS - 1 do
      if col * 8 < width then
        local e = GbaBin.u16(data, u.tilemap + (row * Transition.COLS + col) * 2)
        local tile = e % 1024
        local hflip = math.floor(e / 1024) % 2 == 1
        local vflip = math.floor(e / 2048) % 2 == 1
        for y = 0, 7 do
          for x = 0, 7 do
            local sx = hflip and (7 - x) or x
            local sy = vflip and (7 - y) or y
            local byte = GbaBin.u8(data, u.tiles + tile * 32 + sy * 4 + math.floor(sx / 2))
            local n
            if sx % 2 == 0 then n = byte % 16 else n = math.floor(byte / 16) end
            local c = pal[15 - n] or pal[0]
            image:setPixel(col * 8 + x, row * 8 + y, c[1], c[2], c[3], 1)
          end
        end
      end
    end
  end
  return image
end

-- Steven's portrait is an ordinary 64x64 trainer pic, index 0 keyed.
function Transition.renderStevenMugshot(data)
  local u = Transition.RUBY_US
  local gfx = GbaLz77.decompress(data, u.stevenGfx)
  local raw = GbaLz77.decompress(data, u.stevenPal)
  if not (gfx and raw and #gfx >= 2048 and #raw >= 32) then return nil end
  local pal = {}
  for i = 0, 15 do
    local lo, hi = raw:byte(i * 2 + 1, i * 2 + 2)
    local r, g, b = bgr555(lo + hi * 256)
    pal[i] = { r, g, b }
  end
  local image = ImageWriter.blank(64, 64, 0, 0, 0, 0)
  for tile = 0, 63 do
    local tx, ty = (tile % 8) * 8, math.floor(tile / 8) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local byte = gfx:byte(tile * 32 + y * 4 + math.floor(x / 2) + 1) or 0
        local idx
        if x % 2 == 0 then idx = byte % 16 else idx = math.floor(byte / 16) end
        if idx == 0 then
          image:setPixel(tx + x, ty + y, 0, 0, 0, 0)
        else
          local c = pal[idx]
          image:setPixel(tx + x, ty + y, c[1], c[2], c[3], 1)
        end
      end
    end
  end
  return image
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

function Transition.extract(data)
  local u = Transition.RUBY_US
  if type(data) ~= "string" or #data < u.stevenPal + 64 then return 0 end
  local written = 0
  for i, name in ipairs(Transition.NAMES) do
    local opp = i - 1
    -- Full 256 wide (the tilemap wraps), plus the 240 the screen shows.
    if save(Transition.renderBackground(data, opp, 0), Transition.DIR .. "mugshot_bg_" .. name .. ".png") then
      written = written + 1
    end
    if save(Transition.renderBackground(data, opp, 0, Transition.SCREEN_W),
        Transition.DIR .. "mugshot_bg_" .. name .. "_240.png") then
      written = written + 1
    end
    if save(Transition.renderBackground(data, opp, 1, Transition.SCREEN_W),
        Transition.DIR .. "mugshot_bg_" .. name .. "_may.png") then
      written = written + 1
    end
  end
  if save(Transition.renderStevenMugshot(data), Transition.DIR .. "steven_mugshot.png") then
    written = written + 1
  end
  return written
end

return Transition
