-- Ruby boot cinema and main menu.  pokeruby: intro.c copyright graphic →
-- intro.c part 1 (GAME FREAK / water) → part 2 (bike grass) →
-- title_screen.c (logo + Groudon + RUBY VERSION) →
-- main_menu.c CONTINUE/NEW GAME/OPTION → Birch speech → overworld.
-- Title logo is the affine 8bpp tilemap; intro BGs scroll at runtime.
-- Affine bike / pokeball zoom uses a pre-rendered 256x256 sheet.
local Input = require("src.core.Input")
local GameSpeed = require("src.core.GameSpeed")

local Boot = {}

local COPYRIGHT_SEC = 3
-- intro.c gIntroFrameCounter: part 1 ends ~1026, bike ride ~2068,
-- then the counter resets for the pokeball / fake battle.
local INTRO_PART1_SEC = 1027 / 60
local INTRO2_END = 2069
local INTRO3_BALL_FADE = 44
local INTRO3_STREAKS = 60
local INTRO3_END = 946
local INTRO_SEC = (INTRO2_END + INTRO3_END) / 60
local INTRO_GF_SEC = 560 / 60
-- CreateGameFreakLogo's task: fade in 64, hold 128, fade out 62, then 16.
local INTRO_GF_END_SEC = 831 / 60
local INTRO_SCROLL_START = 739
local INTRO_SCROLL_END = 904
local INTRO2_PX_PER_FRAME = 4
-- sub_8148EC0(1, 0x4000, 0x400, 0x10): BG1 4px, BG2 0.25px, BG3 1/256.
local INTRO2_BG2_PX_PER_FRAME = INTRO2_PX_PER_FRAME * (0x400 / 0x4000)
local INTRO2_TREE_PX_PER_FRAME = INTRO2_PX_PER_FRAME * (0x10 / 0x4000)
local INTRO1_VOFS = { 0x28, 0x18, 0x50, 0 }
local INTRO1_RATE = { 1.5, 1.0, 0.75, 0 }
-- BGCNT_TXT256x512. The LZ tilemap fills one screenblock (256px); the
-- second is DmaClear'd. Wrapping at 256 replayed the puddle over the sky.
local INTRO1_MAP_H = 512
local INTRO1_CONTENT_H = 256
local INTRO1_EON_FRAME = 880
local INTRO1_FADE_FRAME = 1008
local INTRO2_START = 1027
local INTRO2_FADE_FRAME = 1823
local INTRO2_BIKE_Y = 100
local INTRO2_LATIOS_X = -64
local INTRO2_LATIOS_Y = 0x3C
local TITLE_LOOP_SEC = 80
local BLINK = 16 / 60
local NAME_LEN = 7
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local FALLBACK = {
  birch = {
    welcome = {
      "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!",
      "My name is BIRCH. But everyone calls me the POKeMON PROFESSOR.",
    },
    thisIsPokemon = "This is what we call a POKeMON.",
    world = {
      "This world is widely inhabited by creatures known as POKeMON.",
      "To unravel POKeMON mysteries, I've been undertaking research. That's what I do.",
    },
    andYouAre = "And you are?",
    boyOrGirl = { "Are you a boy? Or are you a girl?" },
    whatsYourName = { "All right. What's your name?" },
    soItsPlayer = "So it's {PLAYER}?",
    ahOkay = {
      "Ah, okay! You're {PLAYER} who's moving to my hometown of LITTLEROOT. I get it now!",
    },
    areYouReady = {
      "All right, are you ready?",
      "Your very own adventure is about to unfold.",
      "Well, I'll be expecting you later. Come see me in my POKeMON LAB.",
    },
  },
  menu = {
    newGame = "NEW GAME",
    continue = "CONTINUE",
    option = "OPTION",
    player = "PLAYER",
    time = "TIME",
    pokedex = "POKeDEX",
    badges = "BADGES",
    boy = "BOY",
    girl = "GIRL",
    newName = "NEW NAME",
  },
  names = {
    male = { "NEW NAME", "BRENDAN", "SETH", "TERRELL", "CHAZ" },
    female = { "NEW NAME", "MAY", "KIMMY", "CELIA", "KIRA" },
  },
  species = { azurill = 350, groudon = 405 },
}

local function pagesOf(value, fallback)
  if type(value) == "table" and #value > 0 then return value end
  if type(value) == "string" and value ~= "" then return { value } end
  if type(fallback) == "table" then return fallback end
  return { fallback or "..." }
end

local function withPlayer(text, name)
  text = tostring(text or "")
  name = name or "BRENDAN"
  return (text:gsub("{PLAYER}", name))
end

local SINE = {}
for i = 0, 255 do
  local v = math.sin(i * math.pi / 128) * 256
  if v >= 0 then SINE[i] = math.floor(v + 0.5) else SINE[i] = math.ceil(v - 0.5) end
end

local function truncDiv(a, b)
  if a >= 0 then return math.floor(a / b) else return math.ceil(a / b) end
end

local function gbaSin(index, amp)
  local s = SINE[(index % 256 + 256) % 256]
  if amp == nil then return s end
  return truncDiv(s * amp, 256)
end

local function introFrame(t)
  return math.floor((t or 0) * 60 + 1e-9)
end

local function newDrop(x, y, c, d, splashY, fallNow)
  return {
    x = x, y = y, x2 = 0, y2 = 0,
    d = d, splashY = splashY,
    data4 = 0, data2 = c, data3 = 0,
    phase = fallNow and "fall" or "wait",
    kind = "drop",
    hidden = false,
    scale = 256 / (c + 32),
  }
end

local function stepDrop(sp, goFly, goFall)
  if not sp.kind then return end
  if sp.phase == "wait" then
    if goFly then sp.phase = "fly" end
    return
  end
  if sp.phase == "fly" then
    if sp.x <= 116 then
      sp.y = sp.y + sp.y2
      sp.y2 = 0
      sp.x = sp.x + 4
      sp.x2 = -4
      sp.data4 = 128
      sp.phase = "settle"
    else
      local sin1 = SINE[sp.data4 % 256]
      sp.data4 = sp.data4 + 2
      sp.y2 = truncDiv(sin1, 32)
      sp.x = sp.x - 1
      if sp.x % 2 ~= 0 then sp.y = sp.y + 1 end
    end
    return
  end
  if sp.phase == "settle" then
    if sp.data4 ~= 64 then
      sp.data4 = sp.data4 - 8
      sp.x2 = truncDiv(SINE[(sp.data4 + 64) % 256], 64)
      sp.y2 = truncDiv(SINE[sp.data4 % 256], 64)
    else
      sp.data4 = 0
      sp.phase = "bob"
    end
    return
  end
  if sp.phase == "bob" then
    if goFall then
      sp.phase = "fall"
    else
      sp.data4 = sp.data4 + 8
      local r2 = truncDiv(SINE[sp.data4 % 256], 16) + 64
      sp.x2 = truncDiv(SINE[(r2 + 64) % 256], 64)
      sp.y2 = truncDiv(SINE[r2 % 256], 64)
    end
    return
  end
  if sp.phase == "fall" then
    if sp.y < sp.splashY then
      sp.y = sp.y + 4
    else
      sp.x = sp.x + sp.x2
      sp.y = sp.y + sp.y2
      sp.x2, sp.y2 = 0, 0
      sp.data2 = 1024
      sp.data3 = 8 * (sp.d % 4)
      sp.phase = "splash"
      sp.kind = "splash"
      sp.hidden = true
    end
    return
  end
  if sp.phase == "splash" then
    if sp.data2 >= 192 then
      if sp.data3 ~= 0 then
        sp.data3 = sp.data3 - 1
        sp.hidden = true
      else
        sp.hidden = false
        sp.scale = 256 / sp.data2
        sp.data2 = truncDiv(sp.data2 * 95, 100)
      end
    else
      sp.kind = nil
    end
  end
end

local function intro1Drops(frame)
  local drops = { newDrop(236, -14, 0x200, 1, 0x78, false) }
  for f = 0, frame do
    if f == 368 then
      drops[#drops + 1] = newDrop(48, 0, 0x400, 5, 0x70, true)
    end
    if f == 384 then
      drops[#drops + 1] = newDrop(200, 60, 0x400, 9, 0x80, true)
    end
    for i = 1, #drops do
      stepDrop(drops[i], f >= 76, f >= 251)
    end
  end
  return drops
end

local function intro1Eon(frame)
  if frame < INTRO1_EON_FRAME then return nil end
  local age = frame - INTRO1_EON_FRAME
  local data1, data2, data3, data7 = 128, -24, 0, 0
  local x2, y2, pri = 0, 0, 0
  data7 = 1
  for _ = 1, age do
    data7 = data7 + 1
    if data3 < 0x50 then
      y2 = -gbaSin(data3, 0x78)
      x2 = -gbaSin(data3, 0x8C)
      if data3 > 64 then pri = 3 end
    end
    if data1 < 0x100 then data1 = data1 + 8 else data1 = data1 + 32 end
    if data2 < 0x18 then data2 = data2 + 1 end
    if data3 < 64 then
      data3 = data3 + 2
    elseif data7 % 4 == 0 then
      data3 = data3 + 1
    end
  end
  return { x = 200 + x2, y = 160 + y2, scale = 256 / data1, pri = pri }
end

local function intro2BobY(frame)
  if frame < INTRO2_START then return 0 end
  local task3 = math.min(512, frame - INTRO2_START + 1)
  return gbaSin(math.floor(task3 / 4) % 128, 48)
end

local function intro2Bike(frame)
  if frame < INTRO2_START then return nil end
  local x, mode = 0x110, 0
  local mode2Age, mode3Age = 0, 0
  for f = INTRO2_START, frame do
    if f == 1109 then mode = 1
    elseif f == 1214 then mode = 0
    elseif f == 1398 then mode = 2
    elseif f == 1586 then mode = 3
    elseif f == 1727 then mode = 4
    end
    if mode == 0 then
      x = x - 1
    elseif mode == 1 then
      if f % 8 == 0 then x = x + 1 end
    elseif mode == 2 then
      mode2Age = mode2Age + 1
      if x <= 120 or (f % 8 ~= 0) then x = x + 1 end
    elseif mode == 3 then
      mode3Age = mode3Age + 1
    elseif mode == 4 then
      if x > -32 then x = x - 2 end
    end
  end
  local anim = 0
  if mode == 2 then
    anim = math.min(6, 4 + math.floor((mode2Age - 1) / 4))
  elseif mode == 3 then
    local slot = math.floor((mode3Age - 1) / 16)
    anim = ({ 6, 5, 4 })[slot + 1] or 4
  else
    -- Unknown_40AE38: 4-frame pedal, duration 4, from sprite create.
    anim = math.floor((frame - INTRO2_START) / 4) % 4
  end
  return { x = x, y = INTRO2_BIKE_Y, anim = anim }
end

local function intro2Latios(frame)
  if frame < INTRO2_START then return nil end
  local x, x2, data0, data1 = INTRO2_LATIOS_X - 32, 0, 0, 0
  for f = INTRO2_START, frame do
    if f == 1394 then data0 = 1 end
    if data0 == 1 then
      if x + x2 < 304 then x2 = x2 + 8 else data0 = 2 end
    elseif data0 == 2 then
      if x + x2 > 120 then x2 = x2 - 1 else data0 = 3 end
    elseif data0 == 3 then
      if x2 > 0 then x2 = x2 - 2 end
    end
    data1 = data1 + 4
  end
  local bob = intro2BobY(frame)
  local y2 = gbaSin((frame - INTRO2_START + 1) * 4, 8) - bob
  return { x = INTRO2_LATIOS_X + x2, y = INTRO2_LATIOS_Y + y2 }
end

-- gUnknown_08416C10: 12 foreground trees. xOff is 16.16 added per frame.
local INTRO2_TREE_OBJ = {
  { 0, 16, 32, 0x2000 }, { 0, 80, 32, 0x2000 },
  { 0, 144, 32, 0x2000 }, { 0, 208, 32, 0x2000 },
  { 1, 40, 16, 0x1000 }, { 1, 104, 16, 0x1000 },
  { 1, 168, 16, 0x1000 }, { 1, 232, 16, 0x1000 },
  { 2, 56, 16, 0x800 }, { 2, 120, 16, 0x800 },
  { 2, 184, 16, 0x800 }, { 2, 248, 16, 0x800 },
}

local function intro2TreeObj(frame)
  if frame < INTRO2_START then return nil end
  local bob = intro2BobY(frame)
  local n = frame - INTRO2_START + 1
  local out = {}
  for i = 1, #INTRO2_TREE_OBJ do
    local spec = INTRO2_TREE_OBJ[i]
    local pos = spec[2] * 65536
    for _ = 1, n do
      pos = pos + spec[4]
      local x = math.floor(pos / 65536)
      if x > 255 then
        local frac = pos % 65536
        if frac < 0 then frac = frac + 65536 end
        pos = -32 * 65536 + frac
      end
    end
    out[i] = {
      anim = spec[1], x = math.floor(pos / 65536), y = 88 - bob, w = spec[3],
    }
  end
  return out
end

local INTRO3_SHARPEDO = 331
local INTRO3_DUSKULL = 361
local INTRO3_MUDKIP = 283
local INTRO3_TORCHIC = 280

local function intro3Frame(bootFrame)
  if bootFrame < INTRO2_END then return nil end
  return bootFrame - INTRO2_END
end

-- Task_IntroSpinAndZoomPokeball: data[0]+=0x400, data[1]+=data[2], data[2]++.
-- visual scale = data[1]/256 (sx = 0x10000/data[1]).
local function intro3Ball(p3)
  local rot, z, dz = 0, 0, 0
  for _ = 0, p3 do
    rot = rot + 0x400
    if z <= 0x6BF then
      z = z + dz
      dz = dz + 1
    end
  end
  if z < 1 then z = 1 end
  local fade = 0
  if p3 < 16 then
    fade = 1 - p3 / 16
  elseif p3 >= INTRO3_BALL_FADE then
    fade = (p3 - INTRO3_BALL_FADE) / 16
    if fade > 1 then fade = 1 end
  end
  return {
    angle = rot / 0x10000 * math.pi * 2,
    scale = z / 256,
    fade = fade,
  }
end

-- sub_813D084: pal 15 color 1. 0 green, 1 red, 2 blue.
local function intro3ArenaColor(p3)
  if p3 >= 781 then return 12 / 31, 12 / 31, 20 / 31 end
  if p3 >= 624 then return 22 / 31, 1, 15 / 31 end
  if p3 >= 463 then return 1, 14 / 31, 12 / 31 end
  if p3 >= 219 then return 22 / 31, 1, 15 / 31 end
  return 1, 14 / 31, 12 / 31
end

local function flyInRight(x0, y0, age, flip)
  -- sub_813DB9C case 1: y-=4, x+=2 or x-=2 until y<=96, then wait 8.
  local x, y = x0, y0
  local n = 0
  while y > 96 and n < age do
    y = y - 4
    if flip then x = x + 2 else x = x - 2 end
    n = n + 1
  end
  local rest = age - n
  if rest <= 8 then
    return x, y, 1, false
  end
  -- case 4: y2 = -t^2/8, x2 += t each frame (triangular), PA = 256-min(t*8,128).
  local t = rest - 8
  local x2 = t * (t + 1) / 2
  if not flip then x2 = -x2 end
  local y2 = -truncDiv(t * t, 8)
  if y + y2 <= -32 or x + x2 <= -64 then
    return x, y, 0, true
  end
  local pal = t * 8
  if pal > 128 then pal = 128 end
  return x + x2, y + y2, (256 - pal) / 256, false
end

local function dashIn(x0, y0, age, fromRight)
  -- sub_813E10C / sub_813E210: 7 frames of x2±8, y2∓6, then idle bob.
  local steps = math.min(age, 7)
  local x2 = (fromRight and -8 or 8) * steps
  local y2 = (fromRight and 6 or -6) * steps
  if age <= 7 then
    return x0 + x2, y0 + y2, 1, false
  end
  local bob = (math.floor((age - 7) / 2) % 2 == 1) and 1 or 0
  local bx = fromRight and -bob or bob
  local by = fromRight and bob or -bob
  return x0 + x2 + bx, y0 + y2 + by, 1, false
end

-- task_intro_20 only enables BG2 streaks while throwing / dashing.
local function intro3StreakScroll(p3)
  if p3 >= 304 and p3 < 384 then
    local vofs, hofs, step = 0, 0, 8
    for t = 0, p3 - 304 do
      vofs = vofs - step
      hofs = hofs + step
      if t % 8 == 7 and step ~= 0 then step = step - 1 end
    end
    return hofs, vofs
  end
  if p3 >= 462 and p3 < 623 then
    local age = p3 - 462
    return -age * 8, age * 6
  end
  if p3 >= 623 and p3 < 776 then
    local age = p3 - 623
    return age * 8, -age * 6
  end
  return nil
end

local INTRO3_TRAINER = 219
local INTRO3_THROW = 304
local INTRO3_POP = 384
local INTRO3_BALL_OUT = 277

local function stepThrownBall(x0, y0, flyAge, xMax, xStep)
  local x, y, y2, data2, data3, data4, data7 = x0, y0, 0, 0, 0, 36, 0
  for _ = 1, flyAge do
    data7 = data7 + 1
    if x <= xMax then
      x = x + xStep
      y = y - 1
      y2 = -gbaSin(data2, 24)
      data2 = data2 + 4
    end
    data3 = data3 - data4
    if data7 % 2 == 1 and data4 ~= 0 then data4 = data4 - 1 end
  end
  local ang = (data3 % 256 + 256) % 256
  return {
    x = x, y = y + y2,
    angle = ang / 256 * math.pi * 2,
  }
end

local function intro3ThrownBalls(p3)
  if p3 < INTRO3_BALL_OUT or p3 >= INTRO3_POP then return {} end
  local fly = 0
  if p3 >= INTRO3_THROW then fly = p3 - INTRO3_THROW end
  return {
    stepThrownBall(16, 104, fly, 144, 4),
    stepThrownBall(12, 106, fly, 96, 3),
  }
end

local function intro3Sparkles(p3)
  local age = p3 - INTRO3_POP
  if age < 0 or age >= 32 then return {} end
  if age % 2 == 1 then return {} end
  local r = gbaSin(age * 2, 40)
  local out = {}
  for i = 0, 7 do
    local a = i * 32
    out[#out + 1] = {
      x = 16 + gbaSin(a + 64, r), y = 104 + gbaSin(a, r),
    }
    out[#out + 1] = {
      x = 12 + gbaSin(a + 64, r), y = 106 + gbaSin(a, r),
    }
  end
  return out
end

-- After the 7-frame dash, x/y are baked; spawners use that, not the bob.
local INTRO3_MUDKIP_IDLE = 632
local INTRO3_TORCHIC_IDLE = 708
local INTRO3_ATK_END = 776
local EMBER_ANGLE = { 0xE6, 0xEB, 0xE4, 0xEA, 0xE5, 0xE9, 0xE7, 0xE8 }
local EMBER_PA = { 0x200, 0x1C0, 0x180, 0x140, 0x100, 0xE0, 0xC0, 0xA0, 0x80, 0x80 }

local function intro3Attacks(p3)
  local out = {}
  if p3 < INTRO3_MUDKIP_IDLE or p3 >= INTRO3_ATK_END then return out end
  local function addBeam(kind, x0, y0, ang, age, yKill, maxR, scale)
    local r = age * 8
    if maxR and r > maxR then return end
    local x = x0 + truncDiv(SINE[(ang + 64) % 256] * r, 256)
    local y = y0 + truncDiv(SINE[ang % 256] * r, 256)
    if yKill and y < yKill then return end
    local y2 = 0
    if kind == "water" then
      y2 = truncDiv(SINE[(age * 16) % 256], 64)
    end
    out[#out + 1] = { kind = kind, x = x, y = y + y2, scale = scale or 1 }
  end
  local waterScale = 1
  do
    local mag = math.min(112, (p3 - INTRO3_MUDKIP_IDLE) * 4)
    if mag < 0 then mag = 0 end
    local foo = 256 - SINE[mag % 256] / 2
    if foo < 64 then foo = 64 end
    waterScale = 256 / foo
  end
  local mx, my = 32 + 56, 152 - 42 + 12
  for s = INTRO3_MUDKIP_IDLE, math.min(p3, INTRO3_ATK_END - 1), 2 do
    addBeam("water", mx, my, 232, p3 - s, 24, nil, waterScale)
  end
  if p3 >= INTRO3_TORCHIC_IDLE then
    local tx, ty = -8 + 56, 144 - 42 + 8
    for s = INTRO3_TORCHIC_IDLE, math.min(p3, INTRO3_ATK_END - 1), 2 do
      local idx = (math.floor((s - INTRO3_TORCHIC_IDLE) / 2) % 8) + 1
      local age = p3 - s
      local r0 = math.floor(age * 8 / 16)
      if r0 > 9 then r0 = 9 end
      local pa = EMBER_PA[r0 + 1] or 0x80
      addBeam("ember", tx, ty, EMBER_ANGLE[idx], age, nil, 160, 256 / pa)
    end
  end
  return out
end

local function intro3Actors(p3)
  local out = {}
  local function add(species, which, x, y, flip, scale, hidden)
    if hidden then return end
    out[#out + 1] = {
      species = species, which = which, x = x, y = y,
      flip = flip, scale = scale or 1,
    }
  end
  if p3 >= 80 and p3 < 219 then
    local x, y, sc, hid = flyInRight(240, 160, p3 - 80, false)
    add(INTRO3_SHARPEDO, "front", x, y, false, sc, hid)
  end
  if p3 >= 152 and p3 < 219 then
    local x, y, sc, hid = flyInRight(0, 160, p3 - 152, true)
    add(INTRO3_DUSKULL, "front", x, y, true, sc, hid)
  end
  if p3 >= 219 and p3 < 462 then
    -- sub_813DE70: walk to x=40, anim 1, throw at 304, stay until Destroy at 462.
    local walk = math.min(p3 - 219, math.floor((272 - 40) / 4))
    local x = 272 - walk * 4
    if x < 40 then x = 40 end
    local anim = 3
    if x <= 40 then anim = 0 end
    if p3 >= 304 then anim = 2 end
    out[#out + 1] = {
      trainer = true, x = x, y = 96, anim = anim, flip = false, scale = 1,
    }
  end
  if p3 >= 384 and p3 < 462 then
    -- sub_813DE70 case 4: CreateSprite at the thrown balls' x+x2, y+y2
    -- (not the 16,104 / 12,106 throw origin). sub_813DD58 then grows
    -- affine 2048→256 and at 432 falls (y2=t^2/32, x2=±t/4).
    local grow = 2048 - 128 * (p3 - 384 + 1)
    if grow < 256 then grow = 256 end
    local sc = 256 / grow
    local fall = 0
    if p3 >= 432 then fall = p3 - 432 end
    local y2 = truncDiv(fall * fall, 32)
    local x2 = truncDiv(fall, 4)
    local torchBall = stepThrownBall(16, 104, INTRO3_POP - INTRO3_THROW, 144, 4)
    local mudBall = stepThrownBall(12, 106, INTRO3_POP - INTRO3_THROW, 96, 3)
    add(INTRO3_TORCHIC, "front", torchBall.x + x2, torchBall.y + y2, true, sc, false)
    add(INTRO3_MUDKIP, "front", mudBall.x - x2, mudBall.y + y2, false, sc, false)
  end
  if p3 >= 463 and p3 < 781 then
    local hide = p3 >= 623 and p3 < 781
    if not hide then
      local x, y = dashIn(208, 8, p3 - 463, true)
      add(INTRO3_SHARPEDO, "front", x, y, false, 1, false)
    end
  end
  if p3 >= 539 and p3 < 781 then
    local hide = p3 >= 623 and p3 < 781
    if not hide then
      local x, y = dashIn(248, 16, p3 - 539, true)
      add(INTRO3_DUSKULL, "front", x, y, false, 1, false)
    end
  end
  if p3 >= 624 and p3 < 781 then
    local hide = p3 >= 776
    if not hide then
      local x, y = dashIn(32, 152, p3 - 624, false)
      add(INTRO3_MUDKIP, "back", x, y, false, 1, false)
    end
  end
  if p3 >= 700 and p3 < 781 then
    local hide = p3 >= 776
    if not hide then
      local x, y = dashIn(-8, 144, p3 - 700, false)
      add(INTRO3_TORCHIC, "back", x, y, false, 1, false)
    end
  end
  if p3 >= 781 and p3 < 850 then
    -- case 3: reset to spawn, then x2±4 / y2∓3. Hidden mons reappear here.
    local t = p3 - 781
    add(INTRO3_SHARPEDO, "front", 208 - t * 4, 8 + t * 3, false, 1, false)
    add(INTRO3_DUSKULL, "front", 248 - t * 4, 16 + t * 3, false, 1, false)
    add(INTRO3_MUDKIP, "back", 32 + t * 4, 152 - t * 3, false, 1, false)
    add(INTRO3_TORCHIC, "back", -8 + t * 4, 144 - t * 3, false, 1, false)
  end
  return out
end

function Boot.attach(Game3)
  Game3.BOOT_COPYRIGHT = "copyright"
  Game3.BOOT_INTRO = "intro"
  Game3.BOOT_TITLE = "title"
  Game3.BOOT_MENU = "menu"
  Game3.BOOT_OPTION = "option"
  Game3.BOOT_BIRCH = "birch"
  Game3.BOOT_GENDER = "gender"
  Game3.BOOT_NAME = "name"
  Game3.BOOT_NAMING = "naming"
  Game3.BOOT_CONFIRM = "confirm"
  Game3.NAME_LENGTH = NAME_LEN
  Game3.intro1Drops = intro1Drops
  Game3.intro1Eon = intro1Eon
  Game3.intro2BobY = intro2BobY
  Game3.intro2Bike = intro2Bike
  Game3.intro2Latios = intro2Latios
  Game3.intro2TreeObj = intro2TreeObj
  Game3.introFrame = introFrame
  Game3.intro3Frame = intro3Frame
  Game3.intro3Ball = intro3Ball
  Game3.intro3Actors = intro3Actors
  Game3.intro3StreakScroll = intro3StreakScroll
  Game3.intro3ThrownBalls = intro3ThrownBalls
  Game3.intro3Attacks = intro3Attacks

  function Game3:bootData()
    return (self.data and self.data.title) or FALLBACK
  end

  function Game3:resetBoot()
    self.boot = { kind = Game3.BOOT_COPYRIGHT, t = 0, cursor = 0, blink = 0 }
    self.options = self.options or {
      textSpeed = 2, -- MID (pokeruby SetDefaultOptions)
      battleScene = true,
      battleStyle = "shift",
      stereo = false, -- MONO
      speedOverworld = 1, speedBattle = 1, speedMenu = 1,
    }
    return self.boot
  end

  function Game3:menuLayout()
    if self.saveExists then return "save" end
    return "new"
  end

  function Game3:menuActions()
    if self:menuLayout() == "save" then
      return { "continue", "new", "option" }
    end
    return { "new", "option" }
  end

  function Game3:continueInfo()
    local info = self:readSave()
    if type(info) ~= "table" then return nil end
    local dex = tonumber(info.dexCount)
    if not dex then
      dex = 0
      if type(info.caught) == "table" then
        for _, v in pairs(info.caught) do
          if v then dex = dex + 1 end
        end
      end
    end
    local badges = tonumber(info.badgeCount)
    if not badges then
      badges = 0
      local flags = info.flags or {}
      for i = 0, 7 do
        if flags[Game3.FLAG_BADGE01_GET + i] then badges = badges + 1 end
      end
    end
    return {
      playerName = info.playerName,
      playSeconds = info.playSeconds or 0,
      dexCount = dex,
      badgeCount = badges,
    }
  end

  function Game3:stepOptionMenu(box, onClose)
    if type(box) ~= "table" then return end
    local spec = self:optionMenuSpec()
    local rows = #spec
    if Input:wasPressed("up") then
      box.cursor = ((box.cursor or 0) - 1) % rows
      if box.cursor < 0 then box.cursor = rows - 1 end
    elseif Input:wasPressed("down") then
      box.cursor = ((box.cursor or 0) + 1) % rows
    elseif Input:wasPressed("b") then
      if onClose then onClose() end
    elseif Input:wasPressed("a") or Input:wasPressed("left")
        or Input:wasPressed("right") then
      local opt = self.options or {}
      local c = box.cursor or 0
      local dir = 1
      if Input:wasPressed("left") then dir = -1 end
      local id = spec[c + 1] and spec[c + 1][3]
      if id == "textSpeed" then
        opt.textSpeed = ((opt.textSpeed or 2) % 3) + 1
      elseif id == "battleScene" then
        opt.battleScene = not opt.battleScene
      elseif id == "battleStyle" then
        opt.battleStyle = opt.battleStyle == "set" and "shift" or "set"
      elseif id == "sound" then
        opt.stereo = not opt.stereo
      elseif id == "speedOverworld" or id == "speedBattle" or id == "speedMenu" then
        opt[id] = GameSpeed.cycle(opt[id], dir)
        self.options = opt
        if self.persistDisplayOptions then self:persistDisplayOptions() end
        return
      elseif id == "zoom" then
        local Zoom = require("src.render.Zoom")
        local scale = 1
        if self.fitScale then scale = self:fitScale() end
        Zoom.nudgeOptions(opt, dir, scale)
        self.options = opt
        if self.persistDisplayOptions then self:persistDisplayOptions() end
        return
      elseif id == "tilt" then
        local Tilt = require("src.render.Tilt")
        local level = ((opt.tilt or Tilt.level or 0) + dir) % 4
        opt.tilt = level
        Tilt.setLevel(level)
        self.options = opt
        if self.persistDisplayOptions then self:persistDisplayOptions() end
        return
      else
        if onClose then onClose() end
        return
      end
      self.options = opt
    end
  end

  function Game3:playTimeString(seconds)
    seconds = math.floor(tonumber(seconds) or self.playSeconds or 0)
    if seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local h = math.floor(m / 60)
    m = m % 60
    if h > 999 then h = 999; m = 59 end
    return ("%d:%02d"):format(h, m)
  end

  function Game3:badgeCount()
    local n = 0
    for i = 1, 8 do
      if self:hasBadge(i) then n = n + 1 end
    end
    return n
  end

  function Game3:dexCount()
    local n = 0
    for _, v in pairs(self.caught or {}) do
      if v then n = n + 1 end
    end
    return n
  end

  function Game3:expandBootText(text)
    return withPlayer(text, self:playerName())
  end

  function Game3:beginNewGame()
    self.boot = nil
    self.field = nil
    if not self.map then
      self.phase = "roster"
      return true
    end
    self.phase = "play"
    if self.gender == nil then self:openGenderMenu() end
    return true
  end

  function Game3:openMainMenu()
    self.boot = {
      kind = Game3.BOOT_MENU,
      t = 0, cursor = 0, blink = 0,
    }
    self.saveExists = self:hasSave()
    return true
  end

  -- The copyright screen is silent; the intro cinematic and the title
  -- screen each have their own theme, and the main menu keeps the title's
  -- playing rather than restarting it.
  function Game3:openTitle()
    self.boot = { kind = Game3.BOOT_TITLE, t = 0, cursor = 0, blink = 0 }
    if self.playSong then self:playSong(self:namedSong("title"), true) end
    return true
  end

  function Game3:openIntro()
    self.boot = { kind = Game3.BOOT_INTRO, t = 0, cursor = 0, blink = 0 }
    if self.playSong then self:playSong(self:namedSong("intro"), true) end
    return true
  end

  function Game3:bootPic(species)
    species = tonumber(species)
    if not species then return nil end
    return self.battlePic and self:battlePic(species, "front")
  end

  -- pokeruby SPECIES_AZURILL 350 / SPECIES_GROUDON 405.  Older caches
  -- stored national-dex 298 / Cradily 389.
  function Game3:bootSpecies()
    local spec = (self:bootData() or {}).species or FALLBACK.species
    local az = spec.azurill or FALLBACK.species.azurill
    local gr = spec.groudon or FALLBACK.species.groudon
    if az == 298 then az = 350 end
    if gr == 389 then gr = 405 end
    return az, gr
  end

  function Game3:startBirchSpeech()
    -- Wipe CONTINUE leftovers, but do not enterMap: field scripts during
    -- the cinema can drop the map and finishBirch then opens the roster.
    self:wipeNewGameState()
    self._newGamePending = true
    self.gender = nil
    self.customName = nil
    self.playSeconds = 0
    self.trainerId = nil
    self:ensureTrainerId()
    self.phase = "boot"
    local data = self:bootData()
    local birch = data.birch or FALLBACK.birch
    local queue = {}
    local function push(value, fallback)
      local pages = pagesOf(value, fallback)
      for i = 1, #pages do queue[#queue + 1] = pages[i] end
    end
    push(birch.welcome, FALLBACK.birch.welcome)
    push(birch.thisIsPokemon, FALLBACK.birch.thisIsPokemon)
    push(birch.world, FALLBACK.birch.world)
    push(birch.andYouAre, FALLBACK.birch.andYouAre)
    self.boot = {
      kind = Game3.BOOT_BIRCH,
      t = 0, cursor = 0, blink = 0,
      queue = queue, qi = 1,
      showMon = false,
    }
    return true
  end

  function Game3:finishBirch()
    if self.gender == nil then self:applyGender(Game3.GENDER_MALE) end
    if not self.customName or self.customName == "" then
      self.customName = self:isFemale() and "MAY" or "BRENDAN"
    end
    self.playSeconds = 0
    if self._newGamePending then
      self._newGamePending = nil
      self:spawnAtNewGame()
    end
    self.boot = nil
    if not self.map then
      self.phase = "roster"
      return true
    end
    self.phase = "play"
    self.field = nil
    return true
  end

  function Game3:presetNames()
    local data = self:bootData()
    local names = data.names or FALLBACK.names
    if self:isFemale() then return names.female or FALLBACK.names.female end
    return names.male or FALLBACK.names.male
  end

  function Game3:setPresetName(index)
    local names = self:presetNames()
    local name = names[(index or 1) + 1] or names[2]
    if not name or name == "NEW NAME" then
      name = self:isFemale() and "MAY" or "BRENDAN"
    end
    self.customName = name:sub(1, NAME_LEN)
    return self.customName
  end

  local function letters()
    local out = {}
    for i = 1, #LETTERS do out[i] = LETTERS:sub(i, i) end
    out[#out + 1] = "DEL"
    out[#out + 1] = "END"
    return out
  end

  function Game3:openNaming()
    local seed = self.customName
    if not seed or seed == "" then
      seed = self:isFemale() and "MAY" or "BRENDAN"
    end
    self.boot = {
      kind = Game3.BOOT_NAMING,
      t = 0, cursor = 0, blink = 0,
      name = seed:sub(1, NAME_LEN),
      keys = letters(),
    }
    return true
  end

  function Game3:confirmPlayerName()
    local data = self:bootData()
    local birch = data.birch or FALLBACK.birch
    local queue = {}
    local function push(value, fallback)
      local pages = pagesOf(value, fallback)
      for i = 1, #pages do
        queue[#queue + 1] = self:expandBootText(pages[i])
      end
    end
    push(birch.soItsPlayer, FALLBACK.birch.soItsPlayer)
    self.boot = {
      kind = Game3.BOOT_CONFIRM,
      t = 0, cursor = 0, blink = 0,
      queue = queue, qi = 1,
      after = "ready",
    }
    return true
  end

  function Game3:birchReady()
    local data = self:bootData()
    local birch = data.birch or FALLBACK.birch
    local queue = {}
    local function push(value, fallback)
      local pages = pagesOf(value, fallback)
      for i = 1, #pages do
        queue[#queue + 1] = self:expandBootText(pages[i])
      end
    end
    push(birch.ahOkay, FALLBACK.birch.ahOkay)
    push(birch.areYouReady, FALLBACK.birch.areYouReady)
    self.boot = {
      kind = Game3.BOOT_CONFIRM,
      t = 0, cursor = 0, blink = 0,
      queue = queue, qi = 1,
      after = "play",
    }
    return true
  end

  function Game3:advanceBootTalk()
    local b = self.boot
    if not b then return end
    local queue, qi = b.queue or {}, b.qi or 1
    if qi < #queue then
      b.qi = qi + 1
      b.textPage = 0
      b.printSrc = nil
      return
    end
    if b.kind == Game3.BOOT_BIRCH then
      self.boot = { kind = Game3.BOOT_GENDER, t = 0, cursor = 0, blink = 0 }
    elseif b.after == "ready" then
      self:birchReady()
    else
      self:finishBirch()
    end
  end

  function Game3:stepBoot(dt)
    dt = dt or 0
    if not self.boot then self:resetBoot() end
    local b = self.boot
    b.t = (b.t or 0) + dt
    b.blink = (b.blink or 0) + dt
    local kind = b.kind
    if kind == Game3.BOOT_COPYRIGHT then
      if b.t >= COPYRIGHT_SEC then self:openIntro() end
      return
    end
    if kind == Game3.BOOT_INTRO then
      if Input:wasPressed("a") or Input:wasPressed("b")
          or Input:wasPressed("start") or Input:wasPressed("select")
          or b.t >= INTRO_SEC then
        self:openTitle()
      end
      return
    end
    if kind == Game3.BOOT_TITLE then
      if Input:wasPressed("a") or Input:wasPressed("start") then
        self:openMainMenu()
      elseif b.t >= TITLE_LOOP_SEC then
        self:resetBoot()
      end
      return
    end
    if kind == Game3.BOOT_MENU then
      local actions = self:menuActions()
      local n = #actions
      if Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("b") then
        self:openTitle()
      elseif Input:wasPressed("a") or Input:wasPressed("start") then
        local act = actions[(b.cursor or 0) + 1]
        if act == "continue" then
          local ok, err = self:continueSave()
          if not ok then self.bootHint = err or "Save is unreadable." end
        elseif act == "new" then
          self:startBirchSpeech()
        else
          self.boot = { kind = Game3.BOOT_OPTION, t = 0, cursor = 0, blink = 0 }
        end
      end
      return
    end
    if kind == Game3.BOOT_OPTION then
      self:stepOptionMenu(b, function() self:openMainMenu() end)
      return
    end
    if kind == Game3.BOOT_BIRCH or kind == Game3.BOOT_CONFIRM then
      b.text = self:expandBootText((b.queue and b.queue[b.qi or 1]) or "")
      self:stepPrinter(b, dt)
      if Input:wasPressed("a") or Input:wasPressed("b") then
        if self:advanceDialogue(b) then
          return
        end
        if kind == Game3.BOOT_BIRCH then
          local text = b.queue and b.queue[b.qi or 1] or ""
          if tostring(text):find("call a POKeMON", 1, true)
              or tostring(text):find("This is what we call", 1, true) then
            b.showMon = true
          end
        end
        self:advanceBootTalk()
      end
      return
    end
    if kind == Game3.BOOT_GENDER then
      if Input:wasPressed("up") or Input:wasPressed("down") then
        b.cursor = 1 - (b.cursor or 0)
      elseif Input:wasPressed("b") then
        self:startBirchSpeech()
      elseif Input:wasPressed("a") then
        self:applyGender((b.cursor or 0) == 1
          and Game3.GENDER_FEMALE or Game3.GENDER_MALE)
        local data = self:bootData()
        local birch = data.birch or FALLBACK.birch
        self.boot = {
          kind = Game3.BOOT_NAME,
          t = 0, cursor = 0, blink = 0,
          queue = pagesOf(birch.whatsYourName, FALLBACK.birch.whatsYourName),
          qi = 1,
        }
      end
      return
    end
    if kind == Game3.BOOT_NAME then
      local names = self:presetNames()
      local n = #names
      if Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("b") then
        self.boot = { kind = Game3.BOOT_GENDER, t = 0, cursor = 0, blink = 0 }
      elseif Input:wasPressed("a") then
        if (b.cursor or 0) == 0 then
          self:setPresetName(1)
          self:openNaming()
        else
          self:setPresetName(b.cursor)
          self:confirmPlayerName()
        end
      end
      return
    end
    if kind == Game3.BOOT_NAMING then
      local keys = b.keys or letters()
      local n = #keys
      local cols = 9
      if Input:wasPressed("left") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("right") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - cols) % n
        if b.cursor < 0 then b.cursor = b.cursor + n end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + cols) % n
      elseif Input:wasPressed("b") then
        local name = b.name or ""
        b.name = name:sub(1, math.max(0, #name - 1))
      elseif Input:wasPressed("a") or Input:wasPressed("start") then
        local key = keys[(b.cursor or 0) + 1]
        if key == "END" or Input:wasPressed("start") then
          local name = b.name or ""
          if name == "" then name = self:isFemale() and "MAY" or "BRENDAN" end
          self.customName = name:sub(1, NAME_LEN)
          self:confirmPlayerName()
        elseif key == "DEL" then
          local name = b.name or ""
          b.name = name:sub(1, math.max(0, #name - 1))
        else
          local name = b.name or ""
          if #name < NAME_LEN then b.name = name .. key end
        end
      end
    end
  end

  function Game3:drawBootTalk(text, extra)
    -- main_menu.c Birch speech: Menu_DrawStdWindowFrame(2, 13, 27, 18)
    -- Menu_PrintText at 3, 15.
    self:drawStdWindow(2, 13, 27, 18)
    local G = love.graphics
    G.setColor(0.10, 0.10, 0.12, 1)
    local tx, ty = 3 * Game3.MENU_TILE, 15 * Game3.MENU_TILE
    if extra then
      self:drawText(text or "", tx, ty)
      self:drawText(extra, tx, ty + Game3.MSG_LINE_H)
      return
    end
    local b = self.boot
    if type(b) == "table"
        and (b.kind == Game3.BOOT_BIRCH or b.kind == Game3.BOOT_CONFIRM) then
      self:drawDialogue(b, tx, ty)
      return
    end
    local lines = Game3.wrapDialogue(text or "", nil, self:font3WidthTable())
    if lines[1] then self:drawText(lines[1], tx, ty) end
    if lines[2] then self:drawText(lines[2], tx, ty + Game3.MSG_LINE_H) end
  end

  function Game3:cinemaPic(name)
    local cinema = (self:bootData() or {}).cinema
    local path = cinema and cinema[name]
    if type(path) ~= "string" then return nil end
    self._cinemaCache = self._cinemaCache or {}
    if self._cinemaCache[name] ~= nil then
      return self._cinemaCache[name] or nil
    end
    local img = self:grabImage(path)
    self._cinemaCache[name] = img or false
    return img
  end

  function Game3:drawSpriteCenter(img, cx, cy, sx, sy, sw, sh, scale)
    if not img then return end
    local G = love.graphics
    local iw, ih = img:getDimensions()
    sw = sw or iw
    sh = sh or ih
    sx = sx or 0
    sy = sy or 0
    scale = scale or 1
    local scaleY = scale
    if scaleY < 0 then scaleY = -scaleY end
    G.setColor(1, 1, 1, 1)
    local q = love.graphics.newQuad(sx, sy, sw, sh, iw, ih)
    G.draw(img, q, math.floor(cx + 0.5), math.floor(cy + 0.5),
      0, scale, scaleY, sw / 2, sh / 2)
  end

  function Game3:drawIntro1Obj(t)
    local frame = introFrame(t)
    local eon = intro1Eon(frame)
    if eon and eon.pri >= 3 then
      self:drawSpriteCenter(self:cinemaPic("intro1eon"), eon.x, eon.y,
        0, 0, 64, 32, eon.scale)
    end
    if t >= INTRO_GF_SEC and t < INTRO_GF_END_SEC then
      local gf = self:cinemaPic("gamefreak")
      if gf then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(gf, 0, 0)
      end
    end
    if eon and eon.pri < 3 then
      self:drawSpriteCenter(self:cinemaPic("intro1eon"), eon.x, eon.y,
        0, 0, 64, 32, eon.scale)
    end
    local dropImg = self:cinemaPic("intro1drop")
    local splashImg = self:cinemaPic("intro1splash")
    local drops = intro1Drops(frame)
    for i = 1, #drops do
      local sp = drops[i]
      if sp.kind and not sp.hidden then
        local cx, cy = sp.x + sp.x2, sp.y + sp.y2
        if sp.kind == "splash" then
          self:drawSpriteCenter(splashImg, cx, cy, 0, 0, 64, 32, sp.scale)
        else
          self:drawSpriteCenter(dropImg, cx, cy, 0, 0, 32, 32, sp.scale)
        end
      end
    end
    if frame >= INTRO1_FADE_FRAME then
      local a = (frame - INTRO1_FADE_FRAME) / 18
      if a > 1 then a = 1 end
      love.graphics.setColor(1, 1, 1, a)
      love.graphics.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  function Game3:drawIntro2Obj(t)
    local frame = introFrame(t)
    local trees = intro2TreeObj(frame)
    local sheet = self:cinemaPic("intro2treesobj")
    if trees and sheet then
      for i = 1, #trees do
        local tr = trees[i]
        local sx = ({ 0, 32, 48 })[tr.anim + 1] or 0
        self:drawSpriteCenter(sheet, tr.x, tr.y, sx, 0, tr.w, 32, 1)
      end
    end
    local latios = intro2Latios(frame)
    if latios then
      self:drawSpriteCenter(self:cinemaPic("intro2latios"),
        latios.x, latios.y, 0, 0, 128, 64, 1)
    end
    local bike = intro2Bike(frame)
    if bike then
      -- intro_create_brendan_sprite(x, 100): rider 64x64 centered at y,
      -- bicycle 64x32 centered at y+8 (behind). Anim 2/3 is the look-back
      -- / wheelie on the 64x64; the 64x32 only spins the wheels.
      local ped = math.floor((frame - INTRO2_START) / 8) % 4
      local anim = bike.anim or 0
      self:drawSpriteCenter(self:cinemaPic("intro2bike"),
        bike.x, bike.y + 8, ped * 64, 0, 64, 32, 1)
      self:drawSpriteCenter(self:cinemaPic("intro2brendan"),
        bike.x, bike.y, anim * 64, 0, 64, 64, 1)
    end
    if frame >= INTRO2_FADE_FRAME then
      local a = (frame - INTRO2_FADE_FRAME) / 48
      if a > 1 then a = 1 end
      love.graphics.setColor(1, 1, 1, a)
      love.graphics.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  function Game3:drawIntro3Ball(p3)
    local G = love.graphics
    local ball = intro3Ball(p3)
    local img = self:cinemaPic("intro3ball")
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    if img then
      local iw, ih = img:getDimensions()
      -- AFF256x256 wraps; extra copies show while the ball is still small.
      local n = 0
      if ball.scale < 1.2 then n = 1 end
      if ball.scale < 0.55 then n = 2 end
      local spacing = ball.scale * 256
      local ca, sa = math.cos(ball.angle), math.sin(ball.angle)
      for iy = -n, n do
        for ix = -n, n do
          local dx, dy = ix * spacing, iy * spacing
          G.draw(img, 120 + dx * ca - dy * sa, 80 + dx * sa + dy * ca,
            ball.angle, ball.scale, ball.scale, iw / 2, ih / 2)
        end
      end
    end
    if ball.fade > 0 then
      G.setColor(1, 1, 1, ball.fade)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      G.setColor(1, 1, 1, 1)
    end
  end

  function Game3:drawIntro3Battle(p3)
    local G = love.graphics
    local bar = math.min(32, math.max(0, (p3 - 60) * 4))
    local midH = Game3.SCREEN_H - bar * 2
    local cr, cg, cb = intro3ArenaColor(p3)
    G.setColor(cr, cg, cb, 1)
    G.rectangle("fill", 0, bar, Game3.SCREEN_W, midH)
    G.setColor(1, 1, 1, 1)
    local hofs, vofs = intro3StreakScroll(p3)
    local streaks = (hofs ~= nil) and self:cinemaPic("intro3streaks")
    if streaks then
      local iw, ih = streaks:getDimensions()
      local ox = ((hofs % iw) + iw) % iw
      local oy = ((vofs % ih) + ih) % ih
      G.setColor(1, 1, 1, 1)
      local function blit(sx, sy, dx, dy, w, h)
        if w <= 0 or h <= 0 then return end
        G.draw(streaks, love.graphics.newQuad(sx, sy, w, h, iw, ih), dx, dy)
      end
      local y0, h0 = bar, midH
      local w1 = math.min(Game3.SCREEN_W, iw - ox)
      local h1 = math.min(h0, ih - oy)
      blit(ox, oy, 0, y0, w1, h1)
      if w1 < Game3.SCREEN_W then
        blit(0, oy, w1, y0, Game3.SCREEN_W - w1, h1)
      end
      if h1 < h0 then
        blit(ox, 0, 0, y0 + h1, w1, h0 - h1)
        if w1 < Game3.SCREEN_W then
          blit(0, 0, w1, y0 + h1, Game3.SCREEN_W - w1, h0 - h1)
        end
      end
    end
    G.setColor(0, 0, 0, 1)
    if bar > 0 then
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, bar)
      G.rectangle("fill", 0, Game3.SCREEN_H - bar, Game3.SCREEN_W, bar)
    end
    local actors = intro3Actors(p3)
    for i = 1, #actors do
      local a = actors[i]
      local sc = a.flip and -(a.scale or 1) or (a.scale or 1)
      if a.trainer then
        local sheet = self:cinemaPic("intro3brendan")
        local frame = a.anim or 0
        if frame > 3 then frame = 3 end
        self:drawSpriteCenter(sheet, a.x, a.y, frame * 64, 0, 64, 64, a.scale)
      else
        local img = self:battlePic(a.species, a.which or "front")
        local yo = 0
        if self.picYOffset then
          yo = self:picYOffset(a.species, a.which or "front")
        end
        self:drawSpriteCenter(img, a.x, a.y + yo, 0, 0, nil, nil, sc)
      end
    end
    local poke = self:cinemaPic("intro3poke")
    local thrown = intro3ThrownBalls(p3)
    for i = 1, #thrown do
      local b = thrown[i]
      if poke then
        G.setColor(1, 1, 1, 1)
        local iw, ih = poke:getDimensions()
        G.draw(poke, b.x, b.y, b.angle, 1, 1, iw / 2, ih / 2)
      end
    end
    local spark = self:cinemaPic("intro3spark")
    local sparks = intro3Sparkles(p3)
    for i = 1, #sparks do
      self:drawSpriteCenter(spark, sparks[i].x, sparks[i].y, 0, 0, 8, 8, 1)
    end
    local water = self:cinemaPic("intro3water")
    local ember = self:cinemaPic("intro3ember")
    local atk = intro3Attacks(p3)
    for i = 1, #atk do
      local p = atk[i]
      local img = (p.kind == "ember") and ember or water
      self:drawSpriteCenter(img, p.x, p.y, 0, 0, 16, 16, p.scale)
    end
    if p3 >= 781 and p3 < 850 then
      local blast = self:cinemaPic("intro3blast")
      if blast and p3 % 2 == 0 then
        local t = math.min(p3 - 781, 64)
        local foo = 256 - SINE[t] / 2
        if foo < 64 then foo = 64 end
        local sc = 256 / foo
        local iw, ih = blast:getDimensions()
        G.setColor(1, 1, 1, 1)
        G.draw(blast, 120, 80, 0, sc, sc, iw / 2, ih / 2)
      end
    end
    if p3 >= 850 then
      local fade = (p3 - 850) / 96
      if fade > 1 then fade = 1 end
      G.setColor(1, 1, 1, fade)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    end
    G.setColor(1, 1, 1, 1)
  end

  function Game3:drawIntro3(t)
    local p3 = intro3Frame(introFrame(t))
    if p3 == nil then return false end
    if p3 < INTRO3_STREAKS then
      self:drawIntro3Ball(p3)
    else
      self:drawIntro3Battle(p3)
    end
    return true
  end

  function Game3:drawCinemaStill(name, fallback)
    return self:drawCinemaView(name, 0, 0, fallback)
  end

  -- intro.c Task_IntroScrollDownAndShowEon: VOFS += 1 from frame 739 to 904.
  function Game3.intro1ScrollY(t)
    local frame = math.floor((t or 0) * 60 + 1e-9)
    if frame < INTRO_SCROLL_START then return 0 end
    if frame > INTRO_SCROLL_END then frame = INTRO_SCROLL_END end
    return frame - INTRO_SCROLL_START
  end

  -- Task_IntroLoadPart1Graphics sets BG0..BG3 VOFS 0x28/0x18/0x50/0, then
  -- Task_IntroScrollDownAndShowEon subtracts 1.5 / 1.0 / 0.75 / 0 per frame.
  function Game3.intro1LayerVofs(t, bg)
    local base = INTRO1_VOFS[bg + 1]
    local rate = INTRO1_RATE[bg + 1]
    if not base then return 0 end
    return base - rate * Game3.intro1ScrollY(t)
  end

  -- intro_credits_graphics.c sub_8148EC0(1, 0x4000, 0x400, 0x10).
  function Game3.intro2ScrollX(t, px)
    local frame = math.floor((t or 0) * 60 + 1e-9)
    local start = math.floor(INTRO_PART1_SEC * 60 + 1e-9)
    if frame < start then return 0 end
    return (frame - start) * (px or INTRO2_PX_PER_FRAME)
  end

  function Game3:drawCinemaView(name, ox, oy, fallback)
    local G = love.graphics
    local img = self:cinemaPic(name)
    if not img then
      if fallback then fallback() end
      return false
    end
    local iw, ih = img:getDimensions()
    local sw, sh = Game3.SCREEN_W, Game3.SCREEN_H
    G.setColor(1, 1, 1, 1)
    ox = math.floor(ox or 0)
    oy = math.floor(oy or 0)
    if iw <= sw and ih <= sh then
      G.draw(img, 0, 0)
      return true
    end
    local maxY = math.max(0, ih - sh)
    if oy < 0 then oy = 0 end
    if oy > maxY then oy = maxY end
    local tw = math.max(iw, 1)
    ox = ox % tw
    if ox < 0 then ox = ox + tw end
    local function blit(srcx, destx, w)
      if w <= 0 then return end
      local q = love.graphics.newQuad(srcx, oy, w, sh, iw, ih)
      G.draw(img, q, destx, 0)
    end
    local w1 = math.min(sw, tw - ox)
    blit(ox, 0, w1)
    if w1 < sw then blit(0, w1, sw - w1) end
    return true
  end

  function Game3:drawCopyright()
    local G = love.graphics
    if self:drawCinemaStill("copyright") then return end
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    G.setColor(1, 1, 1, 1)
    self:drawText("POKeMON RUBY VERSION", 40, 40)
    self:drawText("C2002  POKEMON", 56, 72)
    self:drawText("C1995-2002  NINTENDO", 40, 88)
    self:drawText("C1995-2002  CREATURES inc.", 24, 104)
    self:drawText("C1995-2002  GAME FREAK inc.", 16, 120)
  end

  -- A part-1 BG is BGCNT_TXT256x512. Content is the top 256px; y>=256 is
  -- empty, so a negative VOFS (the pan-up) shows sky through the hole
  -- instead of wrapping the puddle onto the top of the screen.
  function Game3.intro1MapY(vofs, screenY)
    local oy = math.floor(vofs or 0) % INTRO1_MAP_H
    if oy < 0 then oy = oy + INTRO1_MAP_H end
    local mapY = (oy + (screenY or 0)) % INTRO1_MAP_H
    if mapY < 0 then mapY = mapY + INTRO1_MAP_H end
    if mapY >= INTRO1_CONTENT_H then return nil end
    return mapY
  end

  function Game3:drawIntro1Layer(bg, vofs)
    local G = love.graphics
    local img = self:cinemaPic("intro1bg" .. bg)
    if not img then return false end
    local iw, ih = img:getDimensions()
    local sw, sh = Game3.SCREEN_W, Game3.SCREEN_H
    G.setColor(1, 1, 1, 1)
    local y = 0
    while y < sh do
      local srcY = Game3.intro1MapY(vofs, y)
      if srcY then
        local run = math.min(sh - y, ih - srcY, INTRO1_CONTENT_H - srcY)
        if run <= 0 then break end
        G.draw(img, love.graphics.newQuad(0, srcY, sw, run, iw, ih), 0, y)
        y = y + run
      else
        local oy = math.floor(vofs or 0) % INTRO1_MAP_H
        if oy < 0 then oy = oy + INTRO1_MAP_H end
        local mapY = (oy + y) % INTRO1_MAP_H
        if mapY < 0 then mapY = mapY + INTRO1_MAP_H end
        local run = math.min(sh - y, INTRO1_MAP_H - mapY)
        if run <= 0 then break end
        y = y + run
      end
    end
    return true
  end

  function Game3:drawIntro()
    -- intro.c part 1 (water BGs + drops + GAME FREAK + Latios) then
    -- part 2 (trees + grass + bike + Latios).
    local G = love.graphics
    local t = (self.boot and self.boot.t) or 0
    if t < INTRO_PART1_SEC then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      G.setColor(1, 1, 1, 1)
      local any = false
      for bg = 3, 0, -1 do
        if self:drawIntro1Layer(bg, Game3.intro1LayerVofs(t, bg)) then
          any = true
        end
      end
      self:drawIntro1Obj(t)
      if any then return end
      if t >= INTRO_GF_SEC and t < INTRO_GF_END_SEC
          and not self:cinemaPic("gamefreak") then
        G.setColor(1, 1, 1, 1)
        self:drawText("GAME FREAK", 80, 72)
      end
      return
    end
    if self:drawIntro3(t) then return end
    local bob = intro2BobY(introFrame(t))
    if self:cinemaPic("intro2trees") and self:cinemaPic("intro2grass") then
      self:drawCinemaView("intro2trees",
        Game3.intro2ScrollX(t, INTRO2_TREE_PX_PER_FRAME), 0)
      if self:cinemaPic("intro2bg2") then
        self:drawCinemaView("intro2bg2",
          Game3.intro2ScrollX(t, INTRO2_BG2_PX_PER_FRAME), bob)
      end
      self:drawCinemaView("intro2grass", Game3.intro2ScrollX(t), bob)
      self:drawIntro2Obj(t)
      return
    end
    if self:drawCinemaView("intro2", Game3.intro2ScrollX(t), 0) then
      self:drawIntro2Obj(t)
      return
    end
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    G.setColor(1, 1, 1, 1)
    self:drawText("POKeMON RUBY", 80, 72)
    self:drawIntro2Obj(t)
  end

  function Game3:drawTitleScreen()
    local G = love.graphics
    local hasCinema = self:drawCinemaStill("title")
    if not hasCinema then
      G.setColor(0.02, 0.02, 0.04, 1)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      G.setColor(1, 1, 1, 1)
      self:drawText("POKeMON", 88, 12)
      self:drawText("RUBY VERSION", 72, 28)
    end
    local b = self.boot
    local on = math.floor(((b and b.blink) or 0) / BLINK) % 2 == 0
    if not on then return end
    local banner = self:cinemaPic("pressStart")
    if banner then
      G.setColor(1, 1, 1, 1)
      G.draw(banner, 0, 0)
    elseif not hasCinema then
      G.setColor(1, 1, 1, 1)
      self:drawText("PRESS START", 72, 108)
    end
  end

  function Game3:drawMainMenu()
    -- main_menu.c Task_MainMenuCheckSave: frames (1,0,28,3)/(1,4,28,7)
    -- with a save: CONTINUE (1,0,28,7) then NEW GAME (1,8,28,11)
    -- then OPTION (1,12,28,15). Print at col 2; save info at rows 3/5.
    local G = love.graphics
    G.setColor(0.10, 0.22, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local data = self:bootData()
    local menu = data.menu or FALLBACK.menu
    local actions = self:menuActions()
    local cursor = self.boot and self.boot.cursor or 0
    local hasSave = actions[1] == "continue"
    local frames
    if hasSave then
      frames = {
        { 1, 0, 28, 7, 1 },
        { 1, 8, 28, 11, 9 },
        { 1, 12, 28, 15, 13 },
      }
    else
      frames = {
        { 1, 0, 28, 3, 1 },
        { 1, 4, 28, 7, 5 },
      }
    end
    for i = 1, #actions do
      local fr = frames[i]
      self:drawStdWindow(fr[1], fr[2], fr[3], fr[4])
      local tx = 2 * Game3.MENU_TILE
      local ty = fr[5] * Game3.MENU_TILE
      if (i - 1) == cursor then self:drawCursor(tx - 8, ty) end
      G.setColor(0.10, 0.10, 0.12, 1)
      local act = actions[i]
      if act == "continue" then
        self:drawText(menu.continue, tx, ty)
        local info = self:continueInfo()
        local name = (info and info.playerName) or "BRENDAN"
        local time = self:playTimeString(info and info.playSeconds)
        self:drawText(menu.player, tx, 3 * Game3.MENU_TILE)
        self:drawText(name, 9 * Game3.MENU_TILE, 3 * Game3.MENU_TILE)
        self:drawText(menu.time, 16 * Game3.MENU_TILE, 3 * Game3.MENU_TILE)
        self:drawText(time, 22 * Game3.MENU_TILE, 3 * Game3.MENU_TILE)
        self:drawText(menu.pokedex, tx, 5 * Game3.MENU_TILE)
        self:drawText(tostring((info and info.dexCount) or 0),
          9 * Game3.MENU_TILE, 5 * Game3.MENU_TILE)
        self:drawText(menu.badges, 16 * Game3.MENU_TILE, 5 * Game3.MENU_TILE)
        self:drawText(tostring((info and info.badgeCount) or 0),
          22 * Game3.MENU_TILE, 5 * Game3.MENU_TILE)
      elseif act == "new" then
        self:drawText(menu.newGame, tx, ty)
      else
        self:drawText(menu.option, tx, ty)
      end
    end
    if self.bootHint then
      G.setColor(1, 1, 1, 1)
      self:drawText(self.bootHint, 16, 148)
    end
  end

  function Game3:drawOptionMenu(box)
    -- option_menu.c: title (2,0,27,3), list (2,4,27,19), labels at col 4
    -- rows 5/7/9/11/13/15/17. Extra GAME SPEED rows scroll inside that.
    local G = love.graphics
    G.setColor(0.10, 0.22, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    self:drawStdWindow(2, 0, 27, 3)
    self:drawStdWindow(2, 4, 27, 19)
    local spec = self:optionMenuSpec()
    box = box or self.boot
    local cursor = box and box.cursor or 0
    local visible = Game3.OPTION_VISIBLE or 7
    local n = #spec
    local maxOff = math.max(0, n - visible)
    local off = cursor - (visible - 1)
    if off < 0 then off = 0 end
    if off > maxOff then off = maxOff end
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("OPTION", 4 * Game3.MENU_TILE, 1 * Game3.MENU_TILE)
    for i = 1, visible do
      local row = spec[off + i]
      if not row then break end
      local y = (5 + (i - 1) * 2) * Game3.MENU_TILE
      if (off + i - 1) == cursor then self:drawCursor(3 * Game3.MENU_TILE, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(row[1], 4 * Game3.MENU_TILE, y)
      if row[2] ~= "" then
        self:drawText(row[2], 20 * Game3.MENU_TILE, y)
      end
    end
  end

  function Game3:drawBirchPortrait()
    local G = love.graphics
    local spec = Game3.spriteSpec(self.data and self.data.sprites, Game3.GFX_BIRCH)
    local img = spec and self:spriteImage(Game3.GFX_BIRCH)
    if img then
      local pose = Game3.poseFor(spec, "south", false, 0)
      local quad = self:owQuad(spec, img, pose.frame or 0)
      G.setColor(1, 1, 1, 1)
      G.draw(img, quad, 96, 24, 0, 2, 2)
      return true
    end
    G.setColor(0.82, 0.62, 0.32, 1)
    G.rectangle("fill", 96, 32, 48, 56)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("BIRCH", 100, 92)
    return false
  end

  function Game3:drawBirchScene()
    local G = love.graphics
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local b = self.boot
    if b and b.showMon then
      local azurill = self:bootSpecies()
      local img = self:bootPic(azurill)
      G.setColor(1, 1, 1, 1)
      if img then
        G.draw(img, 88, 24)
      else
        G.setColor(0.85, 0.55, 0.70, 1)
        G.rectangle("fill", 96, 32, 48, 48)
      end
    else
      self:drawBirchPortrait()
    end
    local text = ""
    if b and b.queue then
      b.text = self:expandBootText(b.queue[b.qi or 1])
      text = self:printedText(b)
    end
    self:drawBootTalk(text)
  end

  function Game3:drawGenderPick()
    local G = love.graphics
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local data = self:bootData()
    local menu = data.menu or FALLBACK.menu
    local birch = data.birch or FALLBACK.birch
    self:drawBootTalk((pagesOf(birch.boyOrGirl, FALLBACK.birch.boyOrGirl))[1])
    -- CreateGenderMenu(2, 4): frame (2,4,8,9), items at (3,5).
    self:drawStdWindow(2, 4, 8, 9)
    local cursor = self.boot and self.boot.cursor or 0
    local labels = { menu.boy, menu.girl }
    for i = 0, 1 do
      local y = (5 + i * 2) * Game3.MENU_TILE
      if i == cursor then self:drawCursor(2 * Game3.MENU_TILE, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(labels[i + 1], 3 * Game3.MENU_TILE, y)
    end
  end

  function Game3:drawNamePick()
    local G = love.graphics
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local names = self:presetNames()
    local b = self.boot
    local prompt = ""
    if b and b.queue then prompt = b.queue[b.qi or 1] or "" end
    self:drawBootTalk(prompt)
    -- CreateNameMenu(2, 1): frame (2,1,12,12), 5 items at (3, 2+2*i).
    self:drawStdWindow(2, 1, 12, 12)
    local cursor = b and b.cursor or 0
    for i = 1, #names do
      local y = (2 + (i - 1) * 2) * Game3.MENU_TILE
      if (i - 1) == cursor then self:drawCursor(2 * Game3.MENU_TILE, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(names[i], 3 * Game3.MENU_TILE, y)
    end
  end

  function Game3:drawNaming()
    local G = love.graphics
    G.setColor(0.10, 0.22, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local b = self.boot
    self:drawWindow(16, 16, 208, 32)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("YOUR NAME?", 24, 24)
    self:drawText(b and b.name or "", 120, 24)
    self:drawWindow(16, 56, 208, 96)
    local keys = b and b.keys or {}
    local cursor = b and b.cursor or 0
    local cols = 9
    for i = 1, #keys do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local x = 24 + col * 22
      local y = 64 + row * 18
      if (i - 1) == cursor then self:drawCursor(x - 8, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(keys[i], x, y)
    end
  end

  function Game3:drawBoot()
    local b = self.boot
    local kind = b and b.kind or Game3.BOOT_COPYRIGHT
    if kind == Game3.BOOT_COPYRIGHT then
      self:drawCopyright()
    elseif kind == Game3.BOOT_INTRO then
      self:drawIntro()
    elseif kind == Game3.BOOT_TITLE then
      self:drawTitleScreen()
    elseif kind == Game3.BOOT_MENU then
      self:drawMainMenu()
    elseif kind == Game3.BOOT_OPTION then
      self:drawOptionMenu()
    elseif kind == Game3.BOOT_BIRCH or kind == Game3.BOOT_CONFIRM then
      self:drawBirchScene()
    elseif kind == Game3.BOOT_GENDER then
      self:drawGenderPick()
    elseif kind == Game3.BOOT_NAME then
      self:drawNamePick()
    else
      self:drawNaming()
    end
  end
end

return Boot
