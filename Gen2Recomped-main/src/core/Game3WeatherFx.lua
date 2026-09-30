-- Field weather OBJ sheets (field_weather_effects.c). Tint stays in Game3;
-- this module scrolls the extracted Nintendo tiles on top.
local WeatherFx = {}

-- CreateSprite positions from field_weather_effects.c (screen space).
WeatherFx.RAIN_COORDS = {
  { 0, 0 }, { 0, 160 }, { 0, 64 }, { 144, 224 }, { 144, 128 },
  { 32, 32 }, { 32, 192 }, { 32, 96 }, { 72, 128 }, { 72, 32 },
  { 72, 192 }, { 216, 96 }, { 216, 0 }, { 104, 160 }, { 104, 64 },
  { 104, 224 }, { 144, 0 }, { 144, 160 }, { 144, 64 }, { 32, 224 },
  { 32, 128 }, { 72, 32 }, { 72, 192 }, { 48, 96 },
}

WeatherFx.CLOUD_COORDS = {
  { 7, 73 }, { 12, 80 }, { 17, 85 },
}

local function rainKind(ow)
  if ow == 3 then return "rain_light" end
  if ow == 5 then return "rain_med" end
  if ow == 13 then return "rain_heavy" end
  return "rain"
end

-- field_weather_effects.c CreateFog1Sprites, CreateAshSprites and
-- CreateSandstormSprites_1 all build the same thing: twenty 64x64 sprites laid
-- out 5 across and 4 down, x = (i % 5) * 64 + 32 and y = (i / 5) * 64 + 32.
-- Edge to edge, nothing overlapping, and the whole grid scrolls as one.
--
-- This engine scattered them instead -- fog puffs 48px apart when the sprite
-- is 64 wide, sandstorm rows 32px apart, ash at (i * 29) % 256 -- so they
-- piled on top of each other and the alpha accumulated into a mess. 5 by 4 is
-- also exactly what covers 240x160 with one cell of scroll margin, so the grid
-- both matches the cart and is the right answer for a full screen.
WeatherFx.GRID_COLS = 5
WeatherFx.GRID_ROWS = 4
WeatherFx.GRID_CELL = 64

function WeatherFx.gridCells(each)
  local out = {}
  for i = 0, WeatherFx.GRID_COLS * WeatherFx.GRID_ROWS - 1 do
    local col = i % WeatherFx.GRID_COLS
    local row = math.floor(i / WeatherFx.GRID_COLS)
    local cell = { col = col, row = row }
    if each then each(cell, i) end
    out[#out + 1] = cell
  end
  return out
end

-- One cell's top-left, with the sheet's scroll folded in. The grid is laid
-- out from -CELL so that a scroll anywhere in [0, CELL) still covers the left
-- and top edges; 5x4 cells then reach past 240x160 on the other side.
function WeatherFx.cellXY(fx, cell)
  local c = WeatherFx.GRID_CELL
  local x = cell.col * c - ((fx.scrollX or 0) % c)
  local y = cell.row * c - ((fx.scrollY or 0) % c)
  return x, y
end

function WeatherFx.attach(Game3)
  function Game3:buildWeatherFx(ow)
    ow = tonumber(ow) or 0
    if ow == 0 or ow == 2 then return nil end
    local fx = { ow = ow, tick = 0 }
    if ow == 1 then
      fx.kind = "cloud"
      fx.clouds = {}
      for i = 1, #WeatherFx.CLOUD_COORDS do
        local c = WeatherFx.CLOUD_COORDS[i]
        fx.clouds[i] = { x = c[1], y = c[2] }
      end
    elseif ow == 3 or ow == 5 or ow == 13 then
      fx.kind = rainKind(ow)
      fx.drops = {}
      for i = 1, #WeatherFx.RAIN_COORDS do
        local c = WeatherFx.RAIN_COORDS[i]
        fx.drops[i] = {
          x = c[1], y = c[2], frame = (i * 3) % 6, phase = (i * 17) % 48,
        }
      end
    elseif ow == 4 then
      fx.kind = "snow"
      fx.flakes = {}
      for i = 1, 24 do
        fx.flakes[i] = {
          x = (i * 37) % 240,
          y = (i * 53) % 160,
          frame = i % 2,
          drift = (i % 5) - 2,
        }
      end
    elseif ow == 6 or ow == 9 or ow == 10 then
      fx.kind = "fog"
      fx.scrollX, fx.scrollY = 0, 0
      fx.puffs = WeatherFx.gridCells(function(cell, i)
        cell.useFog2 = (ow == 9) or (i % 2 == 1)
        cell.frame = 0
      end)
    elseif ow == 7 then
      fx.kind = "ash"
      fx.scrollX, fx.scrollY = 0, 0
      fx.puffs = WeatherFx.gridCells(function(cell)
        cell.frame = 0
      end)
    elseif ow == 8 then
      fx.kind = "sand"
      fx.scrollX, fx.scrollY = 0, 0
      fx.grains = WeatherFx.gridCells(function(cell)
        cell.frame = 0
      end)
    elseif ow == 14 then
      fx.kind = "bubble"
      fx.bubbles = {}
      for i = 1, 8 do
        fx.bubbles[i] = {
          x = (i * 43) % 220 + 10,
          y = 150 - (i * 19) % 140,
          frame = i % 2,
          rise = 0.4 + (i % 3) * 0.15,
        }
      end
    else
      return nil
    end
    return fx
  end

  function Game3:syncWeatherFx()
    local ow = self:getCurrentWeather()
    if ow == (self._weatherFxOw or -1) then return end
    self._weatherFxOw = ow
    self.weatherFx = self:buildWeatherFx(ow)
  end

  function Game3:stepWeatherFx()
    if self.phase ~= "play" then return end
    self:syncWeatherFx()
    local fx = self.weatherFx
    if not fx then return end
    fx.tick = (fx.tick or 0) + 1
    local t = fx.tick
    if fx.kind == "cloud" then
      for i = 1, #(fx.clouds or {}) do
        local c = fx.clouds[i]
        c.x = (c.x + 0.15) % 272
      end
    elseif fx.kind == "rain" or fx.kind == "rain_light"
        or fx.kind == "rain_med" or fx.kind == "rain_heavy" then
      local speed = 4
      if fx.kind == "rain_med" then speed = 5
      elseif fx.kind == "rain_heavy" then speed = 6 end
      for i = 1, #(fx.drops or {}) do
        local d = fx.drops[i]
        d.phase = (d.phase + 1) % 48
        d.y = (d.y + speed) % 224
        d.x = (d.x + 1) % 256
        if d.phase == 0 then
          d.frame = (d.frame + 1) % 6
        end
      end
    elseif fx.kind == "snow" then
      for i = 1, #(fx.flakes or {}) do
        local f = fx.flakes[i]
        f.y = (f.y + 0.7) % 168
        f.x = (f.x + f.drift * 0.08) % 248
        if t % 16 == 0 then f.frame = 1 - f.frame end
      end
    elseif fx.kind == "fog" then
      -- Fog1_Main scrolls the whole sheet, not each puff on its own path.
      fx.scrollX = ((fx.scrollX or 0) + 0.6) % WeatherFx.GRID_CELL
      if t % 16 == 0 then
        for i = 1, #(fx.puffs or {}) do
          local p = fx.puffs[i]
          p.frame = (p.frame + 1) % 6
        end
      end
    elseif fx.kind == "ash" then
      fx.scrollX = ((fx.scrollX or 0) + 0.35) % WeatherFx.GRID_CELL
      fx.scrollY = ((fx.scrollY or 0) + 0.2) % WeatherFx.GRID_CELL
    elseif fx.kind == "sand" then
      fx.scrollX = ((fx.scrollX or 0) + 1.2) % WeatherFx.GRID_CELL
    elseif fx.kind == "bubble" then
      for i = 1, #(fx.bubbles or {}) do
        local b = fx.bubbles[i]
        b.y = b.y - b.rise
        if b.y < -20 then
          b.y = 170 + (i * 7) % 30
          b.x = (t * 3 + i * 43) % 220 + 10
        end
        if t % 16 == 0 then b.frame = 1 - b.frame end
      end
    end
  end

  function Game3:drawScreenSprite(img, srcx, srcy, sw, sh, x, y, alpha)
    if not img then return end
    local G = love.graphics
    local iw, ih = img:getDimensions()
    G.setColor(1, 1, 1, alpha or 1)
    local q = love.graphics.newQuad(srcx, srcy, sw, sh, iw, ih)
    G.draw(img, q, math.floor(x + 0.5), math.floor(y + 0.5))
  end

  function Game3:drawWeatherTint(vw, vh)
    local w = self:getCurrentWeather()
    if w == Game3.OW_WEATHER_NONE or w == Game3.OW_WEATHER_SUNNY then return end
    local G = love.graphics
    if w == Game3.OW_WEATHER_SANDSTORM then
      G.setColor(0.75, 0.62, 0.28, 0.28)
    elseif w == Game3.OW_WEATHER_RAIN_LIGHT
        or w == Game3.OW_WEATHER_RAIN_MED
        or w == Game3.OW_WEATHER_RAIN_HEAVY then
      G.setColor(0.15, 0.25, 0.45, 0.22)
    elseif w == Game3.OW_WEATHER_ASH then
      G.setColor(0.35, 0.35, 0.35, 0.32)
    elseif w == Game3.OW_WEATHER_FOG_1
        or w == Game3.OW_WEATHER_FOG_2
        or w == Game3.OW_WEATHER_FOG_3 then
      G.setColor(0.85, 0.85, 0.90, 0.28)
    elseif w == Game3.OW_WEATHER_DROUGHT then
      G.setColor(0.85, 0.45, 0.10, 0.22)
    elseif w == Game3.OW_WEATHER_CLOUDS then
      G.setColor(0.55, 0.58, 0.62, 0.12)
    elseif w == Game3.OW_WEATHER_SNOW then
      G.setColor(0.85, 0.90, 1, 0.18)
    elseif w == Game3.OW_WEATHER_SHADE then
      G.setColor(0, 0, 0, 0.22)
    elseif w == Game3.OW_WEATHER_BUBBLES then
      G.setColor(0.10, 0.35, 0.55, 0.18)
    else
      return
    end
    local vw = vw or Game3.SCREEN_W
    local vh = vh or Game3.SCREEN_H
    G.rectangle("fill", 0, 0, vw, vh)
  end

  function Game3:drawWeatherSprites(vw, vh)
    self:syncWeatherFx()
    local fx = self.weatherFx
    if not fx or not self.cinemaPic then return end
    vw = vw or Game3.SCREEN_W
    vh = vh or Game3.SCREEN_H
    local G = love.graphics
    G.setColor(1, 1, 1, 1)
    -- The particle fields below are laid out in GBA screen space
    -- (240x160), but drawWorldFx runs after the world transform is popped,
    -- so the caller hands us WINDOW pixels. Drawing them raw put every
    -- grain in the top-left 240x160 corner of a scaled-up window while the
    -- tint (a plain rect over vw/vh) correctly covered everything. Scale
    -- the field up so the weather covers the screen the way it does on
    -- hardware.
    local scaleX = vw / Game3.SCREEN_W
    local scaleY = vh / Game3.SCREEN_H
    local scaled = scaleX ~= 1 or scaleY ~= 1
    if scaled then
      G.push()
      G.scale(scaleX, scaleY)
    end
    local function finish()
      if scaled then G.pop() end
    end
    if fx.kind == "cloud" then
      local img = self:cinemaPic("weatherCloud")
      if not img then finish() return end
      for i = 1, #(fx.clouds or {}) do
        local c = fx.clouds[i]
        self:drawScreenSprite(img, 0, 0, 64, 64, c.x - 32, c.y - 32, 0.85)
      end
    elseif fx.kind == "rain" or fx.kind == "rain_light"
        or fx.kind == "rain_med" or fx.kind == "rain_heavy" then
      local img = self:cinemaPic("weatherRain")
      if not img then finish() return end
      local alpha = 0.75
      if fx.kind == "rain_heavy" then alpha = 0.9 end
      for i = 1, #(fx.drops or {}) do
        local d = fx.drops[i]
        local sy = d.frame * 32
        self:drawScreenSprite(img, 0, sy, 16, 32, d.x, d.y - 16, alpha)
      end
    elseif fx.kind == "snow" then
      local img = self:cinemaPic("weatherSnow")
      if not img then finish() return end
      for i = 1, #(fx.flakes or {}) do
        local f = fx.flakes[i]
        local sx = f.frame * 8
        self:drawScreenSprite(img, sx, 0, 8, 8, f.x, f.y, 0.9)
      end
    elseif fx.kind == "fog" then
      for i = 1, #(fx.puffs or {}) do
        local p = fx.puffs[i]
        local key = p.useFog2 and "weatherFog2" or "weatherFog1"
        local img = self:cinemaPic(key)
        if img then
          local x, y = WeatherFx.cellXY(fx, p)
          self:drawScreenSprite(img, 0, 0, 64, 64, x, y, 0.55)
        end
      end
    elseif fx.kind == "ash" then
      local img = self:cinemaPic("weatherAsh")
      if not img then finish() return end
      for i = 1, #(fx.puffs or {}) do
        local p = fx.puffs[i]
        local x, y = WeatherFx.cellXY(fx, p)
        self:drawScreenSprite(img, 0, p.frame, 64, 64, x, y, 0.65)
      end
    elseif fx.kind == "sand" then
      local img = self:cinemaPic("weatherSand")
      if not img then finish() return end
      for i = 1, #(fx.grains or {}) do
        local g = fx.grains[i]
        local x, y = WeatherFx.cellXY(fx, g)
        self:drawScreenSprite(img, 0, g.frame, 64, 64, x, y, 0.7)
      end
    elseif fx.kind == "bubble" then
      local img = self:cinemaPic("weatherBubble")
      if not img then finish() return end
      for i = 1, #(fx.bubbles or {}) do
        local b = fx.bubbles[i]
        local sy = b.frame * 8
        self:drawScreenSprite(img, 0, sy, 8, 8, b.x - 4, b.y - 4, 0.85)
      end
    end
    finish()
  end
end

return WeatherFx
