-- In-battle weather overlays + status-condition particles for Game3.
-- Reference: pokeruby data/battle_anim_scripts.s
--   gBattleAnims_StatusConditions @ 81C76F8
--   StatusCondition_Poison/Burn/Sleep/Paralysis/Ice/Confusion
--   gBattleAnims_General @ 81C771C
--   General_Rain / General_Sun / General_Sandstorm / General_Hail
--
-- Sheets: misc/pokeruby-master/.../graphics/battle_anims/sprites/
-- Palette index 0 keyed to alpha (same approach as Game3MoveAnim.keyPalette0Alpha).
-- Does NOT alter move-anim drawing.

local BF = {}

BF.FPS = 60
BF.SPRITE_DIR = "misc/pokeruby-master/pokeruby-master/graphics/battle_anims/sprites/"

-- ANIM_TAG_* true indices (ANIM_SPRITES_START + N) — files use N as %03d.png
BF.TAG = {
  ICE_CUBE = 10,       -- ANIM_TAG_ICE_CUBE (010_0.png)
  SPARK_2 = 11,        -- ANIM_TAG_SPARK_2
  SMALL_EMBER = 29,    -- ANIM_TAG_SMALL_EMBER
  DUCK = 73,           -- ANIM_TAG_DUCK
  RAIN_DROPS = 115,    -- ANIM_TAG_RAIN_DROPS
  SUNLIGHT = 157,      -- ANIM_TAG_SUNLIGHT
  LETTER_Z = 228,      -- ANIM_TAG_LETTER_Z
  FLYING_DIRT = 261,   -- ANIM_TAG_FLYING_DIRT
  HAIL = 263,          -- ANIM_TAG_HAIL
}

-- ROM pulse lengths (frames @ 60fps) from battle_anim_scripts.s delays.
BF.PULSE = {
  psn = 24,   -- StatusCondition_Poison: ShakeMon2 18f + purple blend
  tox = 24,
  brn = 28,   -- ConditionBurnFire x3, delay 4
  slp = 70,   -- LETTER_Z x2, delay 30
  par = 28,   -- ElectricityEffect ~16f + shake 10
  frz = 48,   -- ICE_CUBE overlay
  confuse = 90, -- ConfusionEffect orbit arg 90
}

-- Idle re-pulse while status persists (ROM is on-inflict; idle keeps feel).
-- Confuse must NOT idle-loop: ducks orbiting forever looked like a stuck
-- anim (bugs.txt). Pulse once on inflict / confuse check only.
BF.IDLE_GAP = {
  psn = 150, tox = 150, brn = 120, slp = 100, par = 110, frz = 140, confuse = 0,
}
BF.NO_IDLE_REPULSE = { confuse = true }

local SHEET_OBJ_ALPHA = 0.72
local _imgCache = {}

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function fileExists(path)
  if love and love.filesystem and love.filesystem.getInfo then
    if love.filesystem.getInfo(path) then return true end
  end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- Same as Game3MoveAnim: indexed PNGs have no tRNS; GBA OBJ palette 0 is clear.
local function keyPalette0Alpha(data)
  if not (data and data.getPixel and data.mapPixel) then return data end
  local kr, kg, kb = data:getPixel(0, 0)
  local eps = 0.002
  data:mapPixel(function(_, _, r, g, b, a)
    if (a or 1) <= 0 then return r, g, b, a end
    if math.abs(r - kr) <= eps and math.abs(g - kg) <= eps and math.abs(b - kb) <= eps then
      return r, g, b, 0
    end
    return r, g, b, a
  end)
  return data
end

local function loadTagImage(tagIndex)
  if _imgCache[tagIndex] ~= nil then return _imgCache[tagIndex] or nil end
  local candidates = {
    string.format("%s%03d.png", BF.SPRITE_DIR, tagIndex),
    string.format("%s%03d_0.png", BF.SPRITE_DIR, tagIndex),
  }
  if not (love and love.graphics and love.graphics.newImage) then
    _imgCache[tagIndex] = false
    return nil
  end
  for i = 1, #candidates do
    local path = candidates[i]
    if fileExists(path) then
      local img
      if love.image and love.image.newImageData then
        local okData, data = pcall(love.image.newImageData, path)
        if okData and data then
          keyPalette0Alpha(data)
          local okImg, keyed = pcall(love.graphics.newImage, data)
          if okImg and keyed then img = keyed end
        end
      end
      if not img then
        local ok, raw = pcall(love.graphics.newImage, path)
        if ok and raw then img = raw end
      end
      if img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        _imgCache[tagIndex] = img
        return img
      end
    end
  end
  _imgCache[tagIndex] = false
  return nil
end

local function cellSize(img, prefer)
  prefer = prefer or 16
  local w = (img.getWidth and img:getWidth()) or prefer
  local h = (img.getHeight and img:getHeight()) or prefer
  local cw = math.min(prefer, w)
  if prefer >= 32 and w >= 32 then cw = 32 end
  if prefer >= 64 and w >= 64 then cw = 64 end
  local ch = cw
  if h < cw then ch = h end
  if prefer == 16 and w == 16 then
    cw, ch = 16, 16
  elseif prefer == 32 and w >= 32 then
    cw, ch = 32, math.min(32, h)
  elseif prefer == 64 then
    cw, ch = math.min(64, w), math.min(64, h)
  end
  local frames = math.max(1, math.floor(h / ch))
  return cw, ch, frames, w, h
end

local function drawSheetCell(img, frame, x, y, cw, ch, scale, r, g, b, a)
  local G = love.graphics
  if not (img and G and G.draw) then return false end
  scale = scale or 1
  local w = (img.getWidth and img:getWidth()) or cw
  local h = (img.getHeight and img:getHeight()) or ch
  local frames = math.max(1, math.floor(h / ch))
  frame = (frame or 0) % frames
  local aa = clamp01((a or 1) * SHEET_OBJ_ALPHA)
  G.setColor(r or 1, g or 1, b or 1, aa)
  local ok = pcall(function()
    if love.graphics.newQuad then
      local q = love.graphics.newQuad(0, frame * ch, cw, ch, w, h)
      G.draw(img, q, x - cw * scale * 0.5, y - ch * scale * 0.5, 0, scale, scale)
    else
      G.draw(img, x - cw * scale * 0.5, y - ch * scale * 0.5, 0, scale, scale)
    end
  end)
  return ok
end

local function circle(G, x, y, rad, mode)
  if G.circle then G.circle(mode or "fill", x, y, rad)
  else G.rectangle(mode or "fill", x - rad, y - rad, rad * 2, rad * 2) end
end

local function statusKey(mon)
  if not mon then return nil end
  if (mon.confuseTurns or 0) > 0 then return "confuse" end
  local s = mon.status
  if s == "psn" or s == "tox" or s == "brn" or s == "par" or s == "slp" or s == "frz" then
    return s
  end
  return nil
end

local function battlerCenter(self, slot)
  local cx = (self.BATTLER_CX or {})[slot]
  local cy = (self.BATTLER_CY or {})[slot]
  if not cx then
    local map = { player = 72, enemy = 176, player2 = 48, enemy2 = 112 }
    local may = { player = 80, enemy = 40, player2 = 40, enemy2 = 80 }
    cx, cy = map[slot] or 120, may[slot] or 60
  end
  return cx, cy
end

local function ensureState(b)
  if not b._battleFx then
    b._battleFx = {
      tick = 0,
      weatherKind = nil,
      rain = nil,
      sand = nil,
      hail = nil,
      sun = nil,
      status = {},
    }
  end
  return b._battleFx
end

---------------------------------------------------------------------------
-- Weather particle builders (continuous while b.weather set)
---------------------------------------------------------------------------

local function buildRain()
  local drops = {}
  for i = 1, 28 do
    drops[i] = {
      x = (i * 37 + 13) % 248 - 4,
      y = (i * 53) % 140,
      frame = i % 6,
      speed = 3.2 + (i % 4) * 0.45,
      phase = (i * 11) % 20,
    }
  end
  return drops
end

local function buildSand()
  local grains = {}
  for i = 1, 18 do
    grains[i] = {
      x = (i * 41) % 260 - 10,
      y = 20 + (i * 29) % 100,
      speed = 1.6 + (i % 5) * 0.35,
      bob = (i % 7) * 0.4,
    }
  end
  return grains
end

local function buildHail()
  local flakes = {}
  for i = 1, 20 do
    flakes[i] = {
      x = (i * 43) % 248,
      y = (i * 57) % 130,
      speed = 2.0 + (i % 3) * 0.5,
      drift = ((i % 5) - 2) * 0.15,
    }
  end
  return flakes
end

local function syncWeather(fx, kind)
  if fx.weatherKind == kind then return end
  fx.weatherKind = kind
  fx.rain, fx.sand, fx.hail, fx.sun = nil, nil, nil, nil
  if kind == "rain" then
    fx.rain = buildRain()
  elseif kind == "sand" then
    fx.sand = buildSand()
  elseif kind == "hail" then
    fx.hail = buildHail()
  elseif kind == "sun" then
    fx.sun = { phase = 0 }
  end
end

local function stepWeather(fx, frames)
  if fx.rain then
    for i = 1, #fx.rain do
      local d = fx.rain[i]
      d.y = d.y + d.speed * frames
      d.x = d.x + 0.35 * frames
      d.phase = d.phase + frames
      if d.phase >= 8 then
        d.phase = 0
        d.frame = (d.frame + 1) % 8
      end
      if d.y > 150 then
        d.y = -8 - (i % 12)
        d.x = (d.x + 47) % 248
      end
      if d.x > 250 then d.x = d.x - 260 end
    end
  end
  if fx.sand then
    for i = 1, #fx.sand do
      local g = fx.sand[i]
      g.x = g.x + g.speed * frames
      g.y = g.y + math.sin((fx.tick + i * 9) * 0.08) * 0.15 * frames
      if g.x > 260 then
        g.x = -20
        g.y = 16 + (i * 29) % 100
      end
    end
  end
  if fx.hail then
    for i = 1, #fx.hail do
      local h = fx.hail[i]
      h.y = h.y + h.speed * frames
      h.x = h.x + h.drift * frames
      if h.y > 150 then
        h.y = -10
        h.x = (h.x + 61) % 248
      end
    end
  end
  if fx.sun then
    fx.sun.phase = (fx.sun.phase or 0) + frames
  end
end

---------------------------------------------------------------------------
-- Status pulse state
---------------------------------------------------------------------------

local function armPulse(st, key, immediate)
  st.key = key
  st.pulse = 0
  st.active = true
  if immediate then
    st.gap = 0
  else
    st.gap = BF.IDLE_GAP[key] or 120
  end
end

local function stepStatusSlot(st, mon, frames)
  local key = statusKey(mon)
  if not key then
    st.key, st.active, st.pulse, st.gap = nil, false, 0, 0
    return
  end
  if st.key ~= key then
    armPulse(st, key, true)
  end
  if st.active then
    st.pulse = (st.pulse or 0) + frames
    local dur = BF.PULSE[key] or 30
    if st.pulse >= dur then
      st.active = false
      st.pulse = 0
      if BF.NO_IDLE_REPULSE[key] then
        st.gap = 1e9 -- park until key changes or pulseStatus armed
      else
        st.gap = BF.IDLE_GAP[key] or 120
      end
    end
  else
    if BF.NO_IDLE_REPULSE[key] then
      return
    end
    st.gap = (st.gap or 0) - frames
    if st.gap <= 0 then
      armPulse(st, key, true)
    end
  end
end

---------------------------------------------------------------------------
-- Draw: weather
---------------------------------------------------------------------------

local function drawRain(fx)
  local G = love.graphics
  local img = loadTagImage(BF.TAG.RAIN_DROPS)
  -- Soft blue wash (General_Rain sub_80E2A38 blend)
  G.setColor(0.12, 0.22, 0.45, 0.16)
  G.rectangle("fill", 0, 0, 240, 112)
  for i = 1, #(fx.rain or {}) do
    local d = fx.rain[i]
    local a = 0.7
    if img then
      if not drawSheetCell(img, d.frame, d.x, d.y, 16, 16, 1, 0.75, 0.85, 1, a) then
        G.setColor(0.55, 0.7, 1, a * SHEET_OBJ_ALPHA)
        G.rectangle("fill", d.x, d.y, 2, 6)
      end
    else
      G.setColor(0.55, 0.7, 1, a)
      G.rectangle("fill", d.x, d.y, 2, 6)
    end
  end
end

local function drawSand(fx)
  local G = love.graphics
  local img = loadTagImage(BF.TAG.FLYING_DIRT)
  G.setColor(0.72, 0.58, 0.28, 0.20)
  G.rectangle("fill", 0, 0, 240, 112)
  for i = 1, #(fx.sand or {}) do
    local g = fx.sand[i]
    local a = 0.65
    if img then
      if not drawSheetCell(img, 0, g.x, g.y, 32, 32, 0.55, 0.9, 0.78, 0.45, a) then
        G.setColor(0.75, 0.62, 0.35, a)
        circle(G, g.x, g.y, 3)
      end
    else
      G.setColor(0.75, 0.62, 0.35, a)
      circle(G, g.x, g.y, 3 + (i % 3))
    end
  end
end

local function drawHail(fx)
  local G = love.graphics
  local img = loadTagImage(BF.TAG.HAIL)
  G.setColor(0.75, 0.85, 1, 0.12)
  G.rectangle("fill", 0, 0, 240, 112)
  for i = 1, #(fx.hail or {}) do
    local h = fx.hail[i]
    local a = 0.8
    if img then
      if not drawSheetCell(img, 0, h.x, h.y, 16, 16, 1, 1, 1, 1, a) then
        G.setColor(0.9, 0.95, 1, a)
        G.rectangle("fill", h.x, h.y, 3, 3)
      end
    else
      G.setColor(0.9, 0.95, 1, a)
      G.rectangle("fill", h.x, h.y, 3, 3)
    end
  end
end

local function drawSun(fx)
  local G = love.graphics
  local img = loadTagImage(BF.TAG.SUNLIGHT)
  local phase = (fx.sun and fx.sun.phase) or 0
  -- White/yellow blend (Move_SUNNY_DAY / General_Sun → sub_80E2A38 rgb white)
  local pulse = 0.10 + 0.06 * math.sin(phase * 0.07)
  G.setColor(1, 0.95, 0.75, pulse)
  G.rectangle("fill", 0, 0, 240, 112)
  local spots = {
    { 40, 20 }, { 100, 12 }, { 160, 24 }, { 200, 16 },
    { 70, 40 }, { 130, 36 }, { 190, 44 },
  }
  for i = 1, #spots do
    local s = spots[i]
    local bob = math.sin((phase + i * 13) * 0.05) * 3
    local a = 0.45 + 0.25 * math.sin((phase + i * 7) * 0.08)
    if img then
      if not drawSheetCell(img, 0, s[1], s[2] + bob, 32, 32, 0.7, 1, 0.95, 0.55, a) then
        G.setColor(1, 0.9, 0.4, a)
        circle(G, s[1], s[2] + bob, 5)
      end
    else
      G.setColor(1, 0.9, 0.4, a)
      circle(G, s[1], s[2] + bob, 5)
    end
  end
end

---------------------------------------------------------------------------
-- Draw: status particles (active pulse only)
---------------------------------------------------------------------------

local function drawPoison(G, cx, cy, t, fade)
  -- StatusCondition_Poison: purple palette blend 31774 + shake (no sheet)
  local a = fade * (0.22 + 0.10 * math.sin(t * 0.5))
  G.setColor(0.72, 0.25, 0.85, a)
  circle(G, cx, cy, 22)
  G.setColor(0.55, 0.10, 0.70, a * 0.7)
  for i = 0, 3 do
    local ang = t * 0.3 + i * 1.57
    circle(G, cx + math.cos(ang) * 14, cy + math.sin(ang) * 10, 3)
  end
end

local function drawBurn(G, cx, cy, t, fade)
  local img = loadTagImage(BF.TAG.SMALL_EMBER)
  -- ConditionBurnFire x3, delay 4 → launches at 0,4,8
  local launches = { 0, 4, 8 }
  for i = 1, #launches do
    local age = t - launches[i]
    if age >= 0 and age <= 20 then
      local u = age / 20
      local x = cx - 24 + u * 24 + (i - 2) * 8
      local y = cy + 20 - u * 36
      local a = fade * (1 - u * 0.35)
      if not (img and drawSheetCell(img, math.floor(u * 4), x, y, 32, 32, 0.7, 1, 0.55, 0.2, a)) then
        G.setColor(1, 0.4, 0.1, a)
        circle(G, x, y, 3 + (1 - u) * 2)
      end
    end
  end
end

local function drawSleep(G, cx, cy, t, fade)
  local img = loadTagImage(BF.TAG.LETTER_Z)
  -- LETTER_Z x2, delay 30
  local starts = { 0, 30 }
  for i = 1, #starts do
    local age = t - starts[i]
    if age >= 0 and age < 36 then
      local u = age / 36
      local x = cx + 10 + (i - 1) * 6
      local y = cy - 12 - u * 22
      local a = fade * (1 - u)
      local sc = 0.55 + u * 0.35
      if not (img and drawSheetCell(img, 0, x, y, 32, 32, sc, 0.85, 0.85, 1, a)) then
        G.setColor(0.9, 0.9, 1, a)
        -- procedural Z
        G.rectangle("fill", x - 4, y - 6, 8, 2)
        G.rectangle("fill", x + 2, y - 4, 2, 6)
        G.rectangle("fill", x - 4, y + 2, 8, 2)
      end
    end
  end
end

local function drawParalysis(G, cx, cy, t, fade)
  local img = loadTagImage(BF.TAG.SPARK_2)
  -- ElectricityEffect: 8 sparks, delay 2, offsets from script
  local offs = {
    { 5, 0, 0 }, { -5, 10, 1 }, { 15, 20, 2 }, { -15, -10, 0 },
    { 25, 0, 1 }, { -8, 8, 2 }, { 2, -8, 0 }, { -20, 15, 1 },
  }
  for i = 1, #offs do
    local start = (i - 1) * 2
    local age = t - start
    if age >= 0 and age < 12 then
      local o = offs[i]
      local a = fade * (1 - age / 12)
      local x, y = cx + o[1], cy + o[2]
      if not (img and drawSheetCell(img, o[3], x, y, 16, 16, 1, 1, 1, 0.55, a)) then
        G.setColor(1, 1, 0.35, a)
        G.rectangle("fill", x - 1, y - 4, 2, 8)
        G.rectangle("fill", x - 4, y - 1, 8, 2)
      end
    end
  end
end

local function drawFreeze(G, cx, cy, t, fade)
  local img = loadTagImage(BF.TAG.ICE_CUBE)
  local a = fade * (0.55 + 0.2 * math.sin(t * 0.2))
  if img then
    if not drawSheetCell(img, 0, cx, cy, 64, 64, 0.85, 0.85, 0.95, 1, a) then
      G.setColor(0.7, 0.9, 1, a * 0.45)
      G.rectangle("fill", cx - 22, cy - 22, 44, 44)
    end
  else
    G.setColor(0.7, 0.9, 1, a * 0.4)
    G.rectangle("line", cx - 20, cy - 20, 40, 40)
    G.setColor(0.8, 0.95, 1, a * 0.25)
    G.rectangle("fill", cx - 18, cy - 18, 36, 36)
  end
end

local function drawConfusion(G, cx, cy, t, fade)
  local img = loadTagImage(BF.TAG.DUCK)
  -- ConfusionEffect: 5 ducks, phases 0/51/102/153/204, orbit ~90f
  for i = 0, 4 do
    local phase = i * 51
    local ang = (t * 4 + phase) * (math.pi / 180)
    local x = cx + math.cos(ang) * 18
    local y = cy - 15 + math.sin(ang) * 8
    local a = fade * 0.85
    local fr = math.floor(t / 4 + i) % 3
    if not (img and drawSheetCell(img, fr, x, y, 16, 16, 1, 1, 1, 1, a)) then
      G.setColor(1, 0.85, 0.2, a)
      circle(G, x, y, 3)
    end
  end
end

local function drawStatusPulse(G, cx, cy, st)
  if not (st and st.active and st.key) then return end
  local t = st.pulse or 0
  local dur = BF.PULSE[st.key] or 30
  local fade = 1
  if t > dur - 6 then fade = clamp01((dur - t) / 6) end
  if st.key == "psn" or st.key == "tox" then
    drawPoison(G, cx, cy, t, fade)
  elseif st.key == "brn" then
    drawBurn(G, cx, cy, t, fade)
  elseif st.key == "slp" then
    drawSleep(G, cx, cy, t, fade)
  elseif st.key == "par" then
    drawParalysis(G, cx, cy, t, fade)
  elseif st.key == "frz" then
    drawFreeze(G, cx, cy, t, fade)
  elseif st.key == "confuse" then
    drawConfusion(G, cx, cy, t, fade)
  end
end

---------------------------------------------------------------------------
-- Public attach API
---------------------------------------------------------------------------

function BF.attach(Game3)
  BF.Game3 = Game3
  Game3.BattleFx = BF

  -- Arm a one-shot status pulse (confuse check / inflict).
  function Game3:pulseStatusFx(slot, key)
    local b = self.battle
    if not b then return end
    local fx = ensureState(b)
    fx.status = fx.status or {}
    slot = slot or "player"
    fx.status[slot] = fx.status[slot] or {}
    armPulse(fx.status[slot], key or "confuse", true)
  end

  function Game3:stepBattleFx(dt)
    local b = self.battle
    if not b then return end
    local opt = self.options
    if opt and opt.battleScene == false then return end
    dt = dt or 0
    local frames = dt * BF.FPS
    if frames <= 0 then frames = 1 end -- still advance lightly if zero-dt
    -- Prefer real dt; if called once per engine frame without dt, use 1f
    if dt == 0 then frames = 1 end
    local fx = ensureState(b)
    fx.tick = (fx.tick or 0) + frames
    syncWeather(fx, b.weather)
    if b.weather then
      stepWeather(fx, frames)
    end
    local slots = { "player", "enemy", "player2", "enemy2" }
    for i = 1, #slots do
      local slot = slots[i]
      local mon = b[slot]
      if mon and (mon.hp or 0) > 0 then
        fx.status[slot] = fx.status[slot] or {}
        stepStatusSlot(fx.status[slot], mon, frames)
      else
        fx.status[slot] = nil
      end
    end
  end

  function Game3:drawBattleWeatherFx()
    local b = self.battle
    if not b or not b.weather then return end
    local opt = self.options
    if opt and opt.battleScene == false then return end
    local fx = ensureState(b)
    syncWeather(fx, b.weather)
    local G = love.graphics
    if not G then return end
    if b.weather == "rain" and fx.rain then
      drawRain(fx)
    elseif b.weather == "sand" and fx.sand then
      drawSand(fx)
    elseif b.weather == "hail" and fx.hail then
      drawHail(fx)
    elseif b.weather == "sun" then
      drawSun(fx)
    end
    if G.setColor then G.setColor(1, 1, 1, 1) end
  end

  function Game3:drawBattleStatusFx()
    local b = self.battle
    if not b then return end
    local opt = self.options
    if opt and opt.battleScene == false then return end
    local fx = ensureState(b)
    local G = love.graphics
    if not G then return end
    local slots = { "enemy", "enemy2", "player", "player2" }
    for i = 1, #slots do
      local slot = slots[i]
      local mon = b[slot]
      local st = fx.status[slot]
      if mon and st and (mon.hp or 0) > 0 then
        local cx, cy = battlerCenter(self, slot)
        -- Prefer live sprite top-left + 32 when battlerTopLeft exists
        if self.battlerTopLeft and mon.species then
          local which = (slot == "player" or slot == "player2") and "back" or "front"
          local px, py = self:battlerTopLeft(slot, mon.species, which)
          if px and py then
            cx, cy = px + 32, py + 32
          end
        end
        drawStatusPulse(G, cx, cy, st)
      end
    end
    if G.setColor then G.setColor(1, 1, 1, 1) end
  end

  function Game3:drawBattleFx()
    self:drawBattleWeatherFx()
    self:drawBattleStatusFx()
  end

  -- Trigger an immediate status pulse (e.g. after inflict). Safe no-op.
  function Game3:pulseBattleStatusFx(slot)
    local b = self.battle
    if not b then return end
    local mon = b[slot]
    local key = statusKey(mon)
    if not key then return end
    local fx = ensureState(b)
    fx.status[slot] = fx.status[slot] or {}
    armPulse(fx.status[slot], key, true)
  end
end

BF.ASSET_NOTES = {
  rain = "ANIM_TAG_RAIN_DROPS 115.png + blue wash (General_Rain / CreateAnimRaindrops)",
  sand = "ANIM_TAG_FLYING_DIRT 261.png + amber wash (Move_SANDSTORM / General_Sandstorm)",
  hail = "ANIM_TAG_HAIL 263.png (Move_HAIL / General_Hail)",
  sun = "ANIM_TAG_SUNLIGHT 157.png + white blend (Move_SUNNY_DAY / General_Sun)",
  psn = "procedural purple blend (StatusCondition_Poison sub_80E1F8C color 31774)",
  brn = "ANIM_TAG_SMALL_EMBER 029.png ConditionBurnFire x3 delay 4",
  slp = "ANIM_TAG_LETTER_Z 228.png x2 delay 30",
  par = "ANIM_TAG_SPARK_2 011.png ElectricityEffect",
  frz = "ANIM_TAG_ICE_CUBE 010_0.png (StatusCondition_Ice)",
  confuse = "ANIM_TAG_DUCK 073.png x5 orbit (ConfusionEffect)",
}

return BF
