-- Gen 3 Poke Ball sprites, read from the player's own cart.
--
-- These lived in assets/generated/battle/ruby_balls/, baked from the pokeruby
-- decomp. Its README called them a "ROM extract" but the body listed decomp PNG
-- paths as the source, and assets/generated is excluded from game.love, so on
-- device Game3:loadRubyBallSheet found nothing.
--
-- gBallSpriteSheets / gBallSpritePalettes were located by matching the poke
-- ball's graphics pointer; tags run 55000..55011 in the order below. Each sheet
-- is 0x180 bytes -- twelve 4bpp tiles, three 16x16 frames stacked vertically in
-- the ROM. The engine wants them side by side (48x16), which is the one
-- rearrangement this module performs; every visible pixel is identical to the
-- baked art it replaces.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Balls = {}

Balls.RUBY_US = {
  sheets = 0x20A92C,       -- gBallSpriteSheets, 12 x { ptr, u16 size, u16 tag }
  palettes = 0x20A98C,     -- gBallSpritePalettes, 12 x { ptr, u16 tag, u16 pad }
  entry = 8,
  count = 12,
  tradeBallGfx = 0x20C3F8,   -- graphics/trade/ball.png, 16x192, uncompressed
  tradeBallPal = 0x20C3D8,   -- sits immediately before the pixels
  tradeBallFrames = 12,
  displayGfx = 0xD129AC,     -- battle_interface/ball_display.png, 32x8
  displayPal = 0xD1214C,
  displayTiles = 4,
}

-- Tag order in gBallSpriteSheets, which is not the item order.
Balls.NAMES = {
  [0] = "poke", "great", "safari", "ultra", "master", "net",
  "dive", "nest", "repeat", "timer", "luxury", "premier",
}

Balls.DIR = "assets/generated/battle/ruby_balls/"
Balls.FRAME = 16

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
  local raw
  if GbaBin.u8(data, off) == 0x10 then
    raw = GbaLz77.decompress(data, off)
  end
  if not raw or #raw < 32 then raw = data:sub(off + 1, off + 32) end
  if #raw < 32 then return nil end
  local pal = {}
  for i = 0, 15 do
    local lo, hi = raw:byte(i * 2 + 1, i * 2 + 2)
    local r, g, b = bgr555(lo + hi * 256)
    pal[i] = { r, g, b }
  end
  return pal
end

-- Index 0 is emitted as fully transparent black, matching the files this
-- replaces: the ball loader treats the sheets as already keyed.
local function blitTile(image, pixels, tile, px, py, pal)
  for y = 0, 7 do
    for x = 0, 7 do
      local byte = pixels:byte(tile * 32 + y * 4 + math.floor(x / 2) + 1) or 0
      local idx
      if x % 2 == 0 then idx = byte % 16 else idx = math.floor(byte / 16) end
      if idx == 0 then
        image:setPixel(px + x, py + y, 0, 0, 0, 0)
      else
        local c = pal[idx] or pal[0]
        image:setPixel(px + x, py + y, c[1], c[2], c[3], 1)
      end
    end
  end
end

-- Frames are four tiles each in 2x2 OBJ order; ROM stacks them down, the
-- engine quads across, so frame f moves from row f to column f.
local function renderStrip(pixels, pal, frames)
  local size = Balls.FRAME
  local image = ImageWriter.blank(size * frames, size, 0, 0, 0, 0)
  for frame = 0, frames - 1 do
    for t = 0, 3 do
      blitTile(image, pixels, frame * 4 + t,
        frame * size + (t % 2) * 8, math.floor(t / 2) * 8, pal)
    end
  end
  return image
end

function Balls.renderBall(data, index)
  local u = Balls.RUBY_US
  local gfx = romOffset(GbaBin.u32(data, u.sheets + index * u.entry))
  local pal = romOffset(GbaBin.u32(data, u.palettes + index * u.entry))
  if not (gfx and pal) then return nil end
  local pixels = GbaLz77.decompress(data, gfx)
  local colors = palAt(data, pal)
  if not (pixels and colors and #pixels >= 12 * 32) then return nil end
  return renderStrip(pixels, colors, 3), pixels, colors
end

function Balls.renderTradeBall(data)
  local u = Balls.RUBY_US
  local colors = palAt(data, u.tradeBallPal)
  if not colors then return nil end
  local need = u.tradeBallFrames * 4 * 32
  local pixels = data:sub(u.tradeBallGfx + 1, u.tradeBallGfx + need)
  if #pixels < need then return nil end
  return renderStrip(pixels, colors, u.tradeBallFrames)
end

function Balls.renderDisplay(data)
  local u = Balls.RUBY_US
  local colors = palAt(data, u.displayPal)
  if not colors then return nil end
  local need = u.displayTiles * 32
  local pixels = data:sub(u.displayGfx + 1, u.displayGfx + need)
  if #pixels < need then return nil end
  local image = ImageWriter.blank(u.displayTiles * 8, 8, 0, 0, 0, 0)
  for t = 0, u.displayTiles - 1 do
    blitTile(image, pixels, t, t * 8, 0, colors)
  end
  return image
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

function Balls.extract(data)
  local u = Balls.RUBY_US
  if type(data) ~= "string" or #data < u.displayGfx + 128 then return 0 end
  local written = 0
  for index = 0, u.count - 1 do
    local name = Balls.NAMES[index]
    local strip, pixels, colors = Balls.renderBall(data, index)
    if strip and save(strip, Balls.DIR .. name .. ".png") then
      written = written + 1
      -- Frame 0 alone: the closed ball, drawn before the catch animation.
      local closed = ImageWriter.blank(Balls.FRAME, Balls.FRAME, 0, 0, 0, 0)
      for t = 0, 3 do
        blitTile(closed, pixels, t, (t % 2) * 8, math.floor(t / 2) * 8, colors)
      end
      if save(closed, Balls.DIR .. name .. "_closed.png") then
        written = written + 1
      end
    end
  end
  if save(Balls.renderTradeBall(data), Balls.DIR .. "trade_ball.png") then
    written = written + 1
  end
  if save(Balls.renderDisplay(data), Balls.DIR .. "ball_display.png") then
    written = written + 1
  end
  return written
end

return Balls
