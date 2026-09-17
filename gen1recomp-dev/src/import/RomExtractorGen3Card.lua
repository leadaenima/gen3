-- Gen 3 trainer card graphics, read from the player's own cart.
--
-- These were previously baked out of the pokeruby decomp into
-- assets/generated/trainer_card/ by tools/bake_trainer_card.py, whose own
-- docstring notes it needed "no ROM-cache contract bump". But scripts/pack_love.sh
-- excludes assets/generated/* from game.love, so the art existed only in a source
-- checkout: on device the card drew as a flat fill with the text on top, which is
-- what a player actually saw. Nothing about the loader was wrong -- CacheFs
-- mountVersion already overlays the version cache onto these paths -- so writing
-- the same files during extraction is the whole fix.
--
-- Every offset below was found by locating the exact bytes of the corresponding
-- decomp graphic inside Pokemon - Ruby Version (USA).gba, and the composed cards
-- are pixel-identical to the baked PNGs they replace. The three .pal filenames in
-- the decomp (83B5F0C, 83B5F4C, 83B5F8C) are literally their ROM addresses.
local GbaBin = require("src.import.GbaBin")
local ImageWriter = require("src.import.ImageWriter")

local Card = {}

Card.RUBY_US = {
  -- trainer_card.png: 160 tiles, 4bpp, stored uncompressed.
  tiles = 0xE8B4E0,
  tileCount = 160,
  frontMap = 0xE8CAC0,      -- trainer_card_front.map.bin, 32x20 entries
  backMap = 0xE8CFC0,       -- trainer_card_back.map.bin
  starPal = 0xE8C8E0,       -- trainer_card_{0..4}star.pal, 48 colors each
  starPalStride = 0x60,
  starGoldPal = 0x3B5F4C,   -- TrainerCard_DrawStars palette
  starTile = 0x8F,          -- the star glyph's tile id
  badgeTiles = 0x3B5AB8,    -- badges.png, 128x16
  badgeBytes = 1024,
  badgePal = 0x3B5F2C,
}

Card.STAR_COUNT = 5
Card.MAP_COLS, Card.MAP_ROWS = 32, 20
Card.SCREEN_W, Card.SCREEN_H = 240, 160
Card.DIR = "assets/generated/trainer_card/"

local function bgr555(v)
  return (v % 32) / 31,
    (math.floor(v / 32) % 32) / 31,
    (math.floor(v / 1024) % 32) / 31
end

-- Only the first 16 entries: the card is a single 4bpp background palette even
-- though each star .pal carries three of them.
local function pal16(data, off)
  local pal = {}
  for i = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(data, off + i * 2))
    pal[i] = { r, g, b }
  end
  return pal
end

local function tilePixel(data, base, tile, x, y)
  local byte = GbaBin.u8(data, base + tile * 32 + y * 4 + math.floor(x / 2))
  if x % 2 == 0 then return byte % 16 end
  return math.floor(byte / 16)
end

local function blitTile(image, data, base, tile, px, py, pal, hflip, vflip, skip0)
  for y = 0, 7 do
    for x = 0, 7 do
      local dx, dy = px + x, py + y
      if dx >= 0 and dy >= 0 and dx < image:getWidth() and dy < image:getHeight() then
        local idx = tilePixel(data, base, tile,
          hflip and (7 - x) or x, vflip and (7 - y) or y)
        if not (skip0 and idx == 0) then
          local c = pal[idx] or pal[0]
          image:setPixel(dx, dy, c[1], c[2], c[3], 1)
        end
      end
    end
  end
end

-- The tilemap is 32 columns but the GBA only shows 30; the extra two are off
-- screen and the baked PNGs were cropped to 240 the same way.
function Card.renderMap(data, mapOff, pal)
  local u = Card.RUBY_US
  local image = ImageWriter.blank(Card.SCREEN_W, Card.SCREEN_H, 0, 0, 0, 1)
  for row = 0, Card.MAP_ROWS - 1 do
    for col = 0, Card.MAP_COLS - 1 do
      if col * 8 < Card.SCREEN_W then
        local e = GbaBin.u16(data, mapOff + (row * Card.MAP_COLS + col) * 2)
        blitTile(image, data, u.tiles, e % 1024, col * 8, row * 8, pal,
          math.floor(e / 1024) % 2 == 1, math.floor(e / 2048) % 2 == 1, false)
      end
    end
  end
  return image
end

function Card.renderFront(data, stars)
  local u = Card.RUBY_US
  return Card.renderMap(data, u.frontMap,
    pal16(data, u.starPal + stars * u.starPalStride))
end

function Card.renderBack(data, stars)
  local u = Card.RUBY_US
  return Card.renderMap(data, u.backMap,
    pal16(data, u.starPal + stars * u.starPalStride))
end

function Card.renderStar(data)
  local u = Card.RUBY_US
  local image = ImageWriter.blank(8, 8, 0, 0, 0, 0)
  blitTile(image, data, u.tiles, u.starTile, 0, 0,
    pal16(data, u.starGoldPal), false, false, true)
  return image
end

-- 128x16: sixteen tiles across, two down, eight 16x16 badges.
function Card.renderBadges(data)
  local u = Card.RUBY_US
  local image = ImageWriter.blank(128, 16, 0, 0, 0, 0)
  local pal = pal16(data, u.badgePal)
  for tile = 0, (u.badgeBytes / 32) - 1 do
    blitTile(image, data, u.badgeTiles, tile,
      (tile % 16) * 8, math.floor(tile / 16) * 8, pal, false, false, true)
  end
  return image
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

-- Brendan / May come from RomExtractorGen3Cinema, which already pulls the
-- gTrainerFrontPicTable entries for the intro.
function Card.extract(data, cinema)
  if type(data) ~= "string" or #data < Card.RUBY_US.tiles + 5120 then return {} end
  local out = {}
  for stars = 0, Card.STAR_COUNT - 1 do
    out[("front_%d"):format(stars)] = save(Card.renderFront(data, stars),
      Card.DIR .. ("ruby_front_%d.png"):format(stars))
    out[("back_%d"):format(stars)] = save(Card.renderBack(data, stars),
      Card.DIR .. ("ruby_back_%d.png"):format(stars))
  end
  out.star = save(Card.renderStar(data), Card.DIR .. "ruby_star.png")
  out.badges = save(Card.renderBadges(data), Card.DIR .. "ruby_badges.png")
  if cinema then
    out.brendan = save(cinema.renderTrainerFront(data, "brendan"),
      Card.DIR .. "ruby_brendan.png")
    out.may = save(cinema.renderTrainerFront(data, "may"),
      Card.DIR .. "ruby_may.png")
  end
  return out
end

return Card
