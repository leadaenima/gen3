-- Gen 3 wall clock CB2 stand-in (pokeruby src/wallclock.c).
-- Drawn in the 240x160 HUD letterbox over the bedroom (WORLD_FIELD path)
-- so a held FADE_TO_BLACK cannot bury it on GLES drivers.

local WallClock = {}

local CENTER_X, CENTER_Y = 120, 80
local HAND_W, HAND_H = 64, 64
local AMPM_W, AMPM_H = 16, 16

local function tagFor(game)
  if game and game.isFemale and game:isFemale() then
    return "female"
  end
  return "male"
end

local function cache(game)
  local c = game._wallClockGfx
  local tag = tagFor(game)
  if c and c.tag == tag then return c end
  c = { tag = tag }
  local grab = game.grabImage
  local function load(path)
    if grab then return game:grabImage(path) end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end
  end
  local base = "assets/generated/wallclock/"
  c.bgEdit = load(base .. "bg_edit_" .. tag .. ".png")
  c.bgView = load(base .. "bg_view_" .. tag .. ".png")
  c.hands = load(base .. "hands_" .. tag .. ".png")
  c.ampm = load(base .. "ampm_" .. tag .. ".png")
  if c.hands and love and love.graphics then
    c.qMinute = love.graphics.newQuad(0, 0, HAND_W, HAND_H, c.hands:getDimensions())
    c.qHour = love.graphics.newQuad(0, HAND_H, HAND_W, HAND_H, c.hands:getDimensions())
  end
  if c.ampm and love and love.graphics then
    -- clock_ampm: tile 128 = PM (row 0), tile 132 = AM (row 1)
    local sw, sh = c.ampm:getDimensions()
    c.qPm = love.graphics.newQuad(0, 0, AMPM_W, AMPM_H, sw, sh)
    c.qAm = love.graphics.newQuad(0, AMPM_H, AMPM_W, AMPM_H, sw, sh)
  end
  game._wallClockGfx = c
  return c
end

-- pokeruby wallclock.c: tMinuteHandAngle = minutes * 6,
-- tHourHandAngle = (hours % 12) * 30 + (minutes / 10) * 5.
-- Angle 0 is 12 o'clock. The sheet points up, so LÖVE rotation is
-- math.rad(deg) (clockwise, y+ down). Do NOT subtract 90 — that put
-- 10:00 on the 8.
-- SpriteCB_* also adds sClockHandCoords[angle] so the hub, not the
-- 64x64 box center, sits on (120,80). Angle 0 is {0,-24}.
local function anglesFor(hours, minutes)
  hours = tonumber(hours) or 0
  minutes = tonumber(minutes) or 0
  local minAng = minutes * 6
  local hourAng = (hours % 12) * 30 + math.floor(minutes / 10) * 5
  return hourAng, minAng
end

local function handPose(deg)
  deg = tonumber(deg) or 0
  local r = math.rad(deg)
  return math.sin(r) * 24, -math.cos(r) * 24, r
end

local function ampmOffset(deg)
  -- SpriteCB_AM/PMIndicator: Cos2/Sin2 * 30 / 4096, 0 deg = +X.
  local r = math.rad(deg)
  return math.cos(r) * 30, math.sin(r) * 30
end

function WallClock.draw(game, f)
  if not f then return end
  local G = love.graphics
  local gfx = cache(game)
  local kind = f.kind
  local hours, minutes
  if kind == "clock_view" then
    local t = game.localTime and game:localTime() or {}
    hours = t.hours or 0
    minutes = t.minutes or 0
  else
    hours = f.hours or 10
    minutes = f.minutes or 0
  end
  local bg = (kind == "clock_view") and gfx.bgView or gfx.bgEdit
  G.setColor(1, 1, 1, 1)
  if bg then
    G.draw(bg, 0, 0)
  else
    -- Fallback if assets missing: solid teal like the ROM BG.
    G.setColor(0.25, 0.63, 0.66, 1)
    G.rectangle("fill", 0, 0, 240, 160)
    G.setColor(1, 1, 1, 1)
    if game.drawText then
      game:drawText(kind == "clock_view" and "WALL CLOCK" or "SET THE CLOCK", 16, 52)
      local shown = game.clockString and game:clockString({
        hours = hours, minutes = minutes,
      }) or ""
      game:drawText(shown, 16, 72)
    end
  end

  local hourAng, minAng = anglesFor(hours, minutes)
  if gfx.hands and gfx.qMinute and gfx.qHour then
    G.setColor(1, 1, 1, 1)
    local mx, my, mr = handPose(minAng)
    local hx, hy, hr = handPose(hourAng)
    G.draw(gfx.hands, gfx.qMinute, CENTER_X + mx, CENTER_Y + my, mr,
      1, 1, HAND_W / 2, HAND_H / 2)
    G.draw(gfx.hands, gfx.qHour, CENTER_X + hx, CENTER_Y + hy, hr,
      1, 1, HAND_W / 2, HAND_H / 2)
  end

  if gfx.ampm and gfx.qAm and gfx.qPm then
    local periodAm = hours < 12
    -- Settled ROM angles: AM period AM@45 PM@90; PM period AM@90 PM@135.
    local amDeg = periodAm and 45 or 90
    local pmDeg = periodAm and 90 or 135
    local ax, ay = ampmOffset(amDeg)
    local px, py = ampmOffset(pmDeg)
    G.setColor(1, 1, 1, 1)
    G.draw(gfx.ampm, gfx.qAm, CENTER_X + ax - AMPM_W / 2, CENTER_Y + ay - AMPM_H / 2)
    G.draw(gfx.ampm, gfx.qPm, CENTER_X + px - AMPM_W / 2, CENTER_Y + py - AMPM_H / 2)
  end

  if kind == "clock_yesno" then
    -- Task_SetClock3: prompt window + YES/NO (cursor starts on NO in ROM).
    if game.drawWindow then
      game:drawWindow(16, 128, 208, 28)
      game:drawWindow(184, 64, 48, 48)
    else
      G.setColor(0.93, 0.93, 0.86, 1)
      G.rectangle("fill", 16, 128, 208, 28)
      G.rectangle("fill", 184, 64, 48, 48)
    end
    G.setColor(0.10, 0.10, 0.12, 1)
    local ask = (game.TEXT_CLOCK_ASK) or "Is this the correct time?"
    if game.drawText then
      game:drawText(ask, 24, 136)
      local labels = { "YES", "NO" }
      for i = 0, 1 do
        local y = 72 + i * 16
        if i == (f.cursor or 1) and game.drawCursor then
          game:drawCursor(188, y)
        end
        G.setColor(0.10, 0.10, 0.12, 1)
        game:drawText(labels[i + 1], 198, y)
      end
    end
  end
end

return WallClock
