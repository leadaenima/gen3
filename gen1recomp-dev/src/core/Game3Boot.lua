-- Ruby boot cinema and main menu.  pokeruby: intro.c copyright graphic ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢
-- intro.c part 1 (GAME FREAK / water) ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ part 2 (bike grass) ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢
-- title_screen.c (logo + Groudon + RUBY VERSION) ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢
-- main_menu.c CONTINUE/NEW GAME/OPTION ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ Birch speech ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ overworld.
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
-- title_screen.c / intro.c gUnknown_08393E64 BLDALPHA pairs (EVA, EVB).
local BLDALPHA = {
  0x10, 0x110, 0x210, 0x310, 0x410, 0x510, 0x610, 0x710,
  0x810, 0x910, 0xA10, 0xB10, 0xC10, 0xD10, 0xE10, 0xF10,
  0x100F, 0x100E, 0x100D, 0x100C, 0x100B, 0x100A, 0x1009, 0x1008,
  0x1007, 0x1006, 0x1005, 0x1004, 0x1003, 0x1002, 0x1001, 0x1000,
}
local function bldAlpha(coeff)
  coeff = math.floor(coeff or 0)
  if coeff < 0 then coeff = 0 end
  if coeff > 31 then coeff = 31 end
  local v = BLDALPHA[coeff + 1]
  local eva = math.floor(v / 256) % 256
  local evb = v % 256
  if eva > 16 then eva = 16 end
  return eva / 16
end
-- CreateGameFreakLogo task: fade out 64, hold transparent 128, fade in 62 (+16 settle).
local function gameFreakAlpha(frame)
  -- Logo appears at INTRO_GF frame 560; task age = frame - 560.
  -- intro.c sub_813CCE8: EVA 1->0 (64f), hold transparent (128f), EVA 0->1 (~62f).
  local age = frame - 560
  if age < 0 or age >= (831 - 560) then return 0 end
  if age < 64 then
    local foo = math.floor((63 - age) / 2)
    return bldAlpha(foo)
  end
  if age < 64 + 128 then return 0 end
  local outAge = age - 64 - 128
  if outAge <= 0x3D then
    return bldAlpha(math.floor(outAge / 2))
  end
  if outAge <= 0x3D + 16 then return 1 end
  return 0
end
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
  -- ExpandPlaceholder_KunChan: English gExpandedPlaceholder_Kun/Chan are "".
  text = text:gsub("{PLAYER}", name)
  text = text:gsub("{KUN}", "")
  text = text:gsub("{CHAN}", "")
  return text
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
  -- Rider callback: every 8 frames y2 is 0, else Random()&3 -> -1/1/0/0.
  local y2 = 0
  local tick = frame - INTRO2_START
  if tick >= 0 and (tick % 8) ~= 7 then
    local r = (tick * 1103515245 + 12345) % 4
    if r == 0 then y2 = -1 elseif r == 1 then y2 = 1 end
  end
  return { x = x, y = INTRO2_BIKE_Y + y2, anim = anim, y2 = y2 }
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
  -- sub_813E10C / sub_813E210: 7 frames of x2ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â±8, y2ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã¢â‚¬Â¹ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“6, then idle bob.
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
    -- affine 2048ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢256 and at 432 falls (y2=t^2/32, x2=ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â±t/4).
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
    -- case 3: reset to spawn, then x2ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â±4 / y2ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã¢â‚¬Â¹ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“3. Hidden mons reappear here.
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
      elseif id == "voidFill" then
        local Game3 = require("src.core.Game3")
        local cur = self:voidFillMode()
        local at = 1
        for i, m in ipairs(Game3.VOID_FILLS) do
          if m == cur then at = i break end
        end
        local n = #Game3.VOID_FILLS
        at = (at - 1 + dir) % n + 1
        opt.voidFill = Game3.VOID_FILLS[at]
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
    -- title_screen.c: Phase1 counter 256, logo BG2Y starts -32 (data[3]).
    self.boot = {
      kind = Game3.BOOT_TITLE, t = 0, cursor = 0, blink = 0,
      titlePhase = 1, titleCounter = 256, logoBg2Y = -32,
      bannerBlend = 88, lavaY = 0, skipTitle = false,
      shine = {}, showBanner = false, showBanners = false,
      entryFade = 1,
    }
    if self.playSong then self:playSong(self:namedSong("title"), true) end
    return true
  end

  function Game3:openIntro()
    -- intro.c gUnknown_02039318 = Random() & 1: 0 Brendan / 1 May.
    local female = (math.random(0, 1) == 1)
    self.boot = {
      kind = Game3.BOOT_INTRO, t = 0, cursor = 0, blink = 0,
      introFemale = female,
    }
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
      showMon = false, showTrainer = false,
      spriteAlpha = 0, bgAlpha = 0,
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
    -- CB2_NewGame: gFieldCallback = ExecuteTruckSequence after map load.
    if Game3.isTruckMap(self.map) then
      self:executeTruckSequence()
    else
      self.field = nil
    end
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
    local Naming = require("src.ui.gen3.NamingScreen")
    local seed = self.customName
    if not seed or seed == "" then
      seed = self:isFemale() and "MAY" or "BRENDAN"
    end
    local field = Naming.open({
      template = "player",
      initial = seed:sub(1, NAME_LEN),
      maxChars = NAME_LEN,
      title = "YOUR NAME?",
      playerGender = self:isFemale() and 1 or 0,
    })
    field.kind = "nickname"
    self.boot = {
      kind = Game3.BOOT_NAMING,
      t = 0, cursor = 0, blink = 0,
      naming = field,
      name = field.name,
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
      showTrainer = true, spriteAlpha = 1, bgAlpha = 1,
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
      self.boot = {
        kind = Game3.BOOT_GENDER, t = 0, cursor = 0, blink = 0,
        showTrainer = true, spriteAlpha = 0, bgAlpha = 1,
      }
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
      -- title_screen.c: A/B/Start/Select skip phase1/2; only A/Start open menu in phase3.
      local phase = b.titlePhase or 3
      if Input:wasPressed("a") or Input:wasPressed("b")
          or Input:wasPressed("start") or Input:wasPressed("select") then
        if phase < 3 then
          b.skipTitle = true
          b.titleCounter = 0
        elseif Input:wasPressed("a") or Input:wasPressed("start") then
          self:openMainMenu()
          return
        end
      elseif b.t >= TITLE_LOOP_SEC then
        self:resetBoot()
        return
      end
      if self.stepTitleScreen then self:stepTitleScreen(dt) end
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
      -- StartSpriteFadeIn / StartBackgroundFadeIn approximations.
      b.spriteAlpha = math.min(1, (b.spriteAlpha or 0) + dt * 3)
      b.bgAlpha = math.min(1, (b.bgAlpha or 0) + dt * 1.5)
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
            b.spriteAlpha = 0
          end
        end
        self:advanceBootTalk()
      end
      return
    end
    if kind == Game3.BOOT_GENDER then
      b.showTrainer = true
      b.spriteAlpha = math.min(1, (b.spriteAlpha or 0) + dt * 4)
      b.bgAlpha = math.min(1, (b.bgAlpha or 0) + dt * 2)
      if Input:wasPressed("up") or Input:wasPressed("down") then
        b.cursor = 1 - (b.cursor or 0)
        b.spriteAlpha = 0
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
          showTrainer = true, spriteAlpha = 1, bgAlpha = 1,
        }
      end
      return
    end
    if kind == Game3.BOOT_NAME then
      b.showTrainer = true
      b.spriteAlpha = math.min(1, (b.spriteAlpha or 0) + dt * 4)
      b.bgAlpha = 1
      local names = self:presetNames()
      local n = #names
      if Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("b") then
        self.boot = {
          kind = Game3.BOOT_GENDER, t = 0, cursor = 0, blink = 0,
          showTrainer = true, spriteAlpha = 1, bgAlpha = 1,
        }
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
      local Naming = require("src.ui.gen3.NamingScreen")
      local f = b.naming
      if not f then return end
      local Input = require("src.core.Input")
      local finish = {
        finishNickname = function()
          local name = f.name or ""
          if name == "" then name = self:isFemale() and "MAY" or "BRENDAN" end
          self.customName = name:sub(1, NAME_LEN)
          self:confirmPlayerName()
          return true
        end,
      }
      Naming.step(finish, f, Input)
      b.name = f.name
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
    -- logoShine: soften opaque extract for additive OBJ-mode-1 sweep.
    if img and name == "logoShine" and love and love.image then
      local ok, data = pcall(love.image.newImageData, path)
      if ok and data and data.mapPixel then
        data:mapPixel(function(_, _, r, g, b, a)
          if (a or 0) > 1 then r,g,b,a = r/255,g/255,b/255,a/255 end
          local lum = math.max(r or 0, g or 0, b or 0)
          if (a or 0) < 0.01 or lum < 0.02 then return 0, 0, 0, 0 end
          -- Keep color, drive alpha from luminance so additive is a thin sweep.
          return r, g, b, math.min(1, lum * 0.65)
        end)
        local ok2, keyed = pcall(love.graphics.newImage, data)
        if ok2 and keyed then
          if keyed.setFilter then keyed:setFilter("nearest", "nearest") end
          img = keyed
        end
      end
    end
    -- titleGroudon: paletted PNG encode often drops tRNS, so color 0 and the
    -- opaque fill matte hide the lava. Key clear texels to alpha. Keep Ruby
    -- blue markings (pret LEGENDARY_MARKING_COLOR RGB(0,0,c)); do NOT remap
    -- body reds to transparent (they share hues with the lost-alpha matte).
    if img and name == "titleGroudon" and love and love.image then
      local ok, data = pcall(love.image.newImageData, path)
      if ok and data and data.mapPixel then
        local function channel(v)
          v = v or 0
          if v > 1 then return v / 255 end
          return v
        end
        local tw, th = data:getWidth(), data:getHeight()
        -- Paletted PNG encode (LOVE) drops tRNS: clear texels become the
        -- opaque red fill (pal0 ~ RGB(120,0,0)). Body is near-black / dark
        -- red and MUST stay -- earlier near-black + solid-red/black matte
        -- keying punched holes through Groudon. Only key the red fill.
        local matte = {}
        for by = 0, th - 1, 8 do
          for bx = 0, tw - 1, 8 do
            local ur, ug, ub, n, same = nil, nil, nil, 0, true
            for y = by, math.min(by + 7, th - 1) do
              for x = bx, math.min(bx + 7, tw - 1) do
                local r, g, b, a = data:getPixel(x, y)
                r, g, b, a = channel(r), channel(g), channel(b), channel(a)
                if a < 0.01 then
                  same = false
                else
                  n = n + 1
                  if not ur then
                    ur, ug, ub = r, g, b
                  elseif math.abs(r - ur) > 0.02 or math.abs(g - ug) > 0.02 or
                      math.abs(b - ub) > 0.02 then
                    same = false
                  end
                end
              end
            end
            -- Fill matte only: mid/high pure red, not black body tiles.
            local solidMatte = same and n > 0 and ug ~= nil and
              ug < 0.02 and ub < 0.02 and ur ~= nil and ur > 0.20
            if solidMatte then
              for y = by, math.min(by + 7, th - 1) do
                for x = bx, math.min(bx + 7, tw - 1) do
                  matte[y * tw + x] = true
                end
              end
            end
          end
        end
        data:mapPixel(function(x, y, r, g, b, a)
          r, g, b, a = channel(r), channel(g), channel(b), channel(a)
          if a < 0.01 then return 0, 0, 0, 0 end
          -- Extract chroma (green) stamped on clear texels.
          if g > 0.85 and r < 0.08 and b < 0.08 then return 0, 0, 0, 0 end
          if matte[y * tw + x] then return 0, 0, 0, 0 end
          -- Lost-alpha fill: pure red with no green/blue (pal0 ~120,0,0).
          -- Do NOT key near-black -- that is Groudon body (stock silhouette).
          if g < 0.02 and b < 0.02 and r > 0.20 then return 0, 0, 0, 0 end
          -- Remap any leftover red/orange baked markings -> stock Ruby blue.
          -- Markings stay fully opaque; body stays opaque in the ImageData.
          -- Translucency is applied at draw time (stock BLDCNT/BLDALPHA).
          if r > b + 0.12 and g > 0.03 and g < r * 0.55 and b < 0.08 then
            return 0, 0, math.max(r, 0.35), 1
          end
          if b > r + 0.10 and b > g + 0.10 then
            return 0, 0, b, 1
          end
          return r, g, b, 1
        end)
        local ok2, keyed = pcall(love.graphics.newImage, data)
        if ok2 and keyed then
          if keyed.setFilter then keyed:setFilter("nearest", "nearest") end
          img = keyed
          -- Keep ImageData for marking-only pulse.
          self._titleGroudonData = data
        end
      end
    end
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
        local a = gameFreakAlpha(frame)
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.draw(gf, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
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
      -- intro_create_brendan/may_sprite(x, 100): rider 64x64 centered at y,
      -- bicycle 64x32 centered at y+8 (behind). Gender from intro random.
      local ped = math.floor((frame - INTRO2_START) / 8) % 4
      local anim = bike.anim or 0
      local female = self.boot and self.boot.introFemale
      local rider = female and self:cinemaPic("intro2may")
        or self:cinemaPic("intro2brendan")
      if not rider then rider = self:cinemaPic("intro2brendan") end
      self:drawSpriteCenter(self:cinemaPic("intro2bike"),
        bike.x, bike.y + 8, ped * 64, 0, 64, 32, 1)
      self:drawSpriteCenter(rider,
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
    -- Attack FX first: stock InitIntroMudkip/TorchicAttackAnim creates the
    -- beam/ember sprites at mon.subpriority+1 (behind the mon on GBA).
    local water = self:cinemaPic("intro3water")
    local ember = self:cinemaPic("intro3ember")
    local atk = intro3Attacks(p3)
    for i = 1, #atk do
      local p = atk[i]
      local img = (p.kind == "ember") and ember or water
      self:drawSpriteCenter(img, p.x, p.y, 0, 0, 16, 16, p.scale)
    end
    local actors = intro3Actors(p3)
    for i = 1, #actors do
      local a = actors[i]
      local sc = a.flip and -(a.scale or 1) or (a.scale or 1)
      if a.trainer then
        local female = self.boot and self.boot.introFemale
        local sheet = female and self:cinemaPic("intro3may")
          or self:cinemaPic("intro3brendan")
        if not sheet then sheet = self:cinemaPic("intro3brendan") end
        local frame = a.anim or 0
        if frame > 3 then frame = 3 end
        -- Soft pink tint on mons is impractical without pal RAM; keep trainer.
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
    local b = self.boot
    local t = (b and b.t) or 0
    -- SetUpCopyrightScreen: white-in, hold, black-out (FADE_COLOR_WHITE / black).
    local fadeIn = math.min(1, t / (16 / 60))
    local fadeOut = 0
    if t > COPYRIGHT_SEC - (16 / 60) then
      fadeOut = math.min(1, (t - (COPYRIGHT_SEC - 16 / 60)) / (16 / 60))
    end
    local vis = fadeIn * (1 - fadeOut)
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local img = self:cinemaPic("copyright")
    if img then
      G.setColor(1, 1, 1, vis)
      G.draw(img, 0, 0)
    else
      G.setColor(1, 1, 1, vis)
      self:drawText("POKeMON RUBY VERSION", 40, 40)
      self:drawText("C2002  POKEMON", 56, 72)
      self:drawText("C1995-2002  NINTENDO", 40, 88)
      self:drawText("C1995-2002  CREATURES inc.", 24, 104)
      self:drawText("C1995-2002  GAME FREAK inc.", 16, 120)
    end
    if fadeIn < 1 then
      G.setColor(1, 1, 1, 1 - fadeIn)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    end
    if fadeOut > 0 then
      G.setColor(0, 0, 0, fadeOut)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    end
    G.setColor(1, 1, 1, 1)
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

  function Game3:stepTitleScreen(dt)
    local b = self.boot
    if not b then return end
    local frames = math.max(1, math.floor((dt or 0) * 60 + 1e-9))
    for _ = 1, frames do
      b.entryFade = math.max(0, (b.entryFade or 0) - 1 / 16)
      local phase = b.titlePhase or 3
      if phase == 1 then
        if b.skipTitle then b.titleCounter = 0 end
        local c = b.titleCounter or 0
        if c == 160 or c == 64 then
          b.shine = b.shine or {}
          b.shine[#b.shine + 1] = { x = 0, y = 68, flash = true, bright = 0 }
        end
        if c == 256 then
          b.shine = b.shine or {}
          b.shine[#b.shine + 1] = { x = 0, y = 68, flash = false, bright = 0 }
        end
        if c > 0 then
          b.titleCounter = c - 1
        else
          b.showBanner = true
          b.bannerY = 26
          b.bannerBlend = 88
          b.titleCounter = 144
          b.titlePhase = 2
        end
      elseif phase == 2 then
        if b.skipTitle then b.titleCounter = 0 end
        local c = b.titleCounter or 0
        if c > 0 then
          b.titleCounter = c - 1
        else
          b.showBanners = true
          b.titlePhase = 3
          b.logoBg2Y = 0
        end
        -- stock SpriteCallback_VersionBanner*: tSkipToNext snaps to
        -- VERSION_BANNER_Y_GOAL (66) and fully opaque; do not leave mid-drop.
        if b.skipTitle then
          b.bannerY = 66
          b.bannerBlend = 0
          b.logoBg2Y = 0
        else
          if b.bannerBlend and b.bannerBlend > 0 then
            b.bannerBlend = b.bannerBlend - 1
          end
          if b.bannerY and b.bannerY < 66 then
            b.bannerY = b.bannerY + 1
          end
        end
        -- Phase2: every other frame data[3]++ from -32 toward 0.
        if (c % 2) == 0 and (b.logoBg2Y or 0) < 0 then
          b.logoBg2Y = (b.logoBg2Y or -32) + 1
        end
      end
      -- Lava/markings animate in every title phase (BG1 scroll + pulse).
      b.lavaY = (b.lavaY or 0) + 0.5
      b.markFrame = (b.markFrame or 0) + 1
      -- Advance shine sprites (+4 x / frame).
      local shine = b.shine or {}
      local keep = {}
      for i = 1, #shine do
        local s = shine[i]
        if s.x < 272 then
          if s.flash then
            if s.x < 120 then
              s.bright = math.min(31, (s.bright or 0) + 2)
            else
              s.bright = math.max(0, (s.bright or 0) - 2)
            end
          end
          s.x = s.x + 4
          keep[#keep + 1] = s
        end
      end
      b.shine = keep
    end
  end

  function Game3:drawTitleScreen()
    local G = love.graphics
    local b = self.boot
    local lava = self:cinemaPic("titleLava")
    local groudon = self:cinemaPic("titleGroudon")
    local logo = self:cinemaPic("titleLogo")
    local version = self:cinemaPic("versionBanner")
    local layered = lava or groudon or logo
    if layered then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      local function drawWrappedRow(img, srcY, hofs, row, alpha)
        if not img then return end
        local iw, ih = img:getDimensions()
        local ox = ((math.floor(hofs) % iw) + iw) % iw
        local w1 = math.min(Game3.SCREEN_W, iw - ox)
        G.setColor(1, 1, 1, alpha or 1)
        local q1 = love.graphics.newQuad(ox, srcY % math.max(1, ih), w1, 1, iw, ih)
        G.draw(img, q1, 0, row)
        if w1 < Game3.SCREEN_W then
          local q2 = love.graphics.newQuad(0, srcY % math.max(1, ih),
            Game3.SCREEN_W - w1, 1, iw, ih)
          G.draw(img, q2, w1, row)
        end
      end
      local bubbles = self:cinemaPic("titleLavaBubbles")
      if lava then
        local iy = math.floor(b and b.lavaY or 0)
        local ih = select(2, lava:getDimensions())
        -- Dark base + lighter bubble overlay; ScanlineEffect_InitWave HOFS wrap.
        for row = 0, Game3.SCREEN_H - 1 do
          local wave = math.floor(math.sin((row + iy) * 0.2) * 4 + 0.5)
          local srcY = (row + iy) % math.max(1, ih)
          drawWrappedRow(lava, srcY, wave, row, 1)
          if bubbles then
            -- Bubbles scroll a touch faster for dual-layer parallax.
            local bSrc = (row + math.floor(iy * 1.35)) % math.max(1, select(2, bubbles:getDimensions()))
            drawWrappedRow(bubbles, bSrc, wave + math.floor(iy * 0.25), row, 0.55)
          end
        end
      end
      G.setColor(1, 1, 1, 1)
      if groudon then
        -- Stock UpdateLegendaryMarkingColor: every 4 frames ramp pal 0xEF.
        -- Pulse ONLY blue marking pixels; body stays neutral.
        local mf = (b and b.markFrame) or 0
        local intensity = (math.floor(mf / 4) % 64)
        if intensity > 31 then intensity = 63 - intensity end
        local c = intensity / 31
        local pulsed = groudon
        local data = self._titleGroudonData
        if data and love and love.image and love.graphics then
          local key = intensity
          if self._titleMarkPulseKey ~= key then
            self._titleMarkPulseKey = key
            local out = love.image.newImageData(data:getWidth(), data:getHeight())
            out:mapPixel(function(x, y)
              local r, g, b, a = data:getPixel(x, y)
              if (a or 0) > 1 then r, g, b, a = r / 255, g / 255, b / 255, a / 255 end
              -- Pulse marking pixels only (stock pal 0xEF / RGB(0,0,c)).
              if (a or 0) > 0.01 and (b or 0) > (r or 0) + 0.10 and (b or 0) > (g or 0) + 0.10 then
                return 0, 0, c, 1
              end
              return r or 0, g or 0, b or 0, a or 0
            end)
            local ok2, img2 = pcall(love.graphics.newImage, out)
            if ok2 and img2 then
              if img2.setFilter then img2:setFilter("nearest", "nearest") end
              self._titleGroudonPulsed = img2
            end
          end
          pulsed = self._titleGroudonPulsed or groudon
        end
        -- Stock title_screen.c Phase3:
        --   REG_BLDCNT = 0x2142  (alpha: BG1 lava 1st, BG0 Groudon 2nd)
        --   REG_BLDALPHA = 0x1F0F (EVA=15, EVB=16)
        -- result = (15*lava + 16*groudon)/16 where both opaque.
        -- LOVE cannot do dual-coeff blend, so approximate: body as a dark
        -- translucent shadow over lava, then opaque (+ soft additive) markings.
        if G.setBlendMode then G.setBlendMode("alpha") end
        G.setColor(1, 1, 1, 0.55)
        G.draw(pulsed, 0, 0)
        -- Markings-only layer (blue plates / pal 0xEF).
        local markKey = tostring(self._titleMarkPulseKey or -1)
        if self._titleMarksBuiltKey ~= markKey then
          self._titleMarksBuiltKey = markKey
          local src = data
          if src then
            local out = love.image.newImageData(src:getWidth(), src:getHeight())
            -- Reuse Phase3 marking intensity (mf/c computed above).
            out:mapPixel(function(x, y)
              local r, g, bb, a = src:getPixel(x, y)
              if (a or 0) > 1 then r, g, bb, a = r / 255, g / 255, bb / 255, a / 255 end
              if (a or 0) > 0.01 and (bb or 0) > (r or 0) + 0.10 and (bb or 0) > (g or 0) + 0.10 then
                return 0, 0, c, 1
              end
              return 0, 0, 0, 0
            end)
            local okm, imgm = pcall(love.graphics.newImage, out)
            if okm and imgm then
              if imgm.setFilter then imgm:setFilter("nearest", "nearest") end
              self._titleGroudonMarks = imgm
            end
          end
        end
        local markDraw = self._titleGroudonMarks
        if markDraw then
          if G.setBlendMode then G.setBlendMode("alpha") end
          G.setColor(1, 1, 1, 1)
          G.draw(markDraw, 0, 0)
          if G.setBlendMode then G.setBlendMode("add") end
          G.setColor(0.55, 0.55, 1.0, 0.35)
          G.draw(markDraw, 0, 0)
          if G.setBlendMode then G.setBlendMode("alpha") end
        end
        G.setColor(1, 1, 1, 1)
      end
      if logo then
        -- REG_BG2X = -29*256 baked in; BG2Y negative shifts logo DOWN (stock).
        -- Bake is rest (Y=0); draw at -logoBg2Y so phase1/2 match title_screen.c.
        local yOff = (b and b.logoBg2Y) or 0
        if (b and (b.titlePhase or 3) >= 3) then yOff = 0 end
        -- Nudge logo 2px toward Groudon head / RUBY VERSION (stock-tight gap).
        G.draw(logo, 0, -yOff + 2)
      end
    else
      local hasCinema = self:drawCinemaStill("title")
      if not hasCinema then
        G.setColor(0.02, 0.02, 0.04, 1)
        G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
        G.setColor(1, 1, 1, 1)
        self:drawText("POKeMON", 88, 12)
        self:drawText("RUBY VERSION", 72, 28)
      end
    end
    -- Version banner drop + BLDALPHA (invisible until blend < 64, then EVA).
    if b and b.showBanner and version then
      local by = b.bannerY or 66
      local alpha = 1
      if b.titlePhase == 2 and b.bannerBlend then
        if (b.bannerBlend or 0) >= 64 then
          alpha = 0
        else
          -- Keep the drop readable; stock eases EVA down toward settle.
          alpha = math.max(0.55, bldAlpha(math.floor((b.bannerBlend or 0) / 2)))
        end
      end
      if alpha > 0 then
        G.setColor(1, 1, 1, alpha)
        -- Centers: left 98, right 162, sprite is 128x32.
        G.draw(version, 98 - 32, by - 16)
        G.setColor(1, 1, 1, 1)
      end
    end

    -- Logo shine sweeps (stock OBJ mode 1 -> additive sweep over the logo).
    local shineImg = self:cinemaPic("logoShine")
    if shineImg and b and b.shine then
      if G.setBlendMode then G.setBlendMode("add") end
      for i = 1, #b.shine do
        local s = b.shine[i]
        -- Soft translucent sweep (stock OBJ mode 1), not a fat opaque bar.
        local a = 0.55
        if s.flash then a = 0.28 + 0.50 * ((s.bright or 0) / 31) end
        G.setColor(1, 1, 1, a)
        G.draw(shineImg, s.x - 32, s.y - 32)
      end
      if G.setBlendMode then G.setBlendMode("alpha") end
      G.setColor(1, 1, 1, 1)
    end
    -- Title copyright banner (phase3+).
    -- Title copyright banner (phase3+).
    if b and b.showBanners then
      local copy = self:cinemaPic("titleCopyright")
      if copy then
        G.setColor(1, 1, 1, 1)
        G.draw(copy, 0, 0)
      end
    end
    -- PRESS START blink (unchanged behaviour).
    local on = math.floor(((b and b.blink) or 0) / BLINK) % 2 == 0
    if on and b and (b.showBanners or not layered) then
      local banner = self:cinemaPic("pressStart")
      if banner then
        G.setColor(1, 1, 1, 1)
        G.draw(banner, 0, 0)
      elseif not layered then
        G.setColor(1, 1, 1, 1)
        self:drawText("PRESS START", 72, 108)
      end
    end
    -- Entry white fade.
    if b and (b.entryFade or 0) > 0 then
      G.setColor(1, 1, 1, b.entryFade)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      G.setColor(1, 1, 1, 1)
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

  function Game3:drawBirchBg()
    local G = love.graphics
    local bg = self:cinemaPic("birchBg")
    if bg then
      G.setColor(1, 1, 1, 1)
      G.draw(bg, 0, 0)
      return true
    end
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    return false
  end

  function Game3:drawBirchPortrait()
    local G = love.graphics
    local alpha = 1
    if self.boot and self.boot.spriteAlpha then
      alpha = self.boot.spriteAlpha
    end
    local img = self:cinemaPic("birchPortrait")
    if img then
      -- CreateBirchSprite(136, 60): 64x64 centered.
      G.setColor(1, 1, 1, alpha)
      G.draw(img, 136 - 32, 60 - 32)
      G.setColor(1, 1, 1, 1)
      return true
    end
    local spec = Game3.spriteSpec(self.data and self.data.sprites, Game3.GFX_BIRCH)
    local ow = spec and self:spriteImage(Game3.GFX_BIRCH)
    if ow then
      local pose = Game3.poseFor(spec, "south", false, 0)
      local quad = self:owQuad(spec, ow, pose.frame or 0)
      G.setColor(1, 1, 1, alpha)
      G.draw(ow, quad, 96, 24, 0, 2, 2)
      G.setColor(1, 1, 1, 1)
      return true
    end
    G.setColor(0.82, 0.62, 0.32, alpha)
    G.rectangle("fill", 96, 32, 48, 56)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("BIRCH", 100, 92)
    return false
  end

  function Game3:drawBirchTrainer()
    local G = love.graphics
    local female = self:isFemale()
    if self.boot and self.boot.kind == Game3.BOOT_GENDER then
      female = (self.boot.cursor or 0) == 1
    end
    local img = female and self:cinemaPic("trainerFrontMay")
      or self:cinemaPic("trainerFrontBrendan")
    if not img then return false end
    local alpha = (self.boot and self.boot.spriteAlpha) or 1
    -- CreateTrainerSprite(..., 120, 60): 64x64 centered.
    G.setColor(1, 1, 1, alpha)
    G.draw(img, 120 - 32, 60 - 32)
    G.setColor(1, 1, 1, 1)
    return true
  end

  function Game3:drawBirchScene()
    local G = love.graphics
    self:drawBirchBg()
    local b = self.boot
    local bgA = (b and b.bgAlpha) or 1
    if bgA < 1 then
      G.setColor(0, 0, 0, 1 - bgA)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      G.setColor(1, 1, 1, 1)
    end
    if b and b.showMon then
      local azurill = self:bootSpecies()
      local img = self:bootPic(azurill)
      local alpha = b.spriteAlpha or 1
      G.setColor(1, 1, 1, alpha)
      if img then
        -- CreateAzurillSprite(0x68, 0x48) = (104, 72) center.
        local iw, ih = img:getDimensions()
        G.draw(img, 104 - iw / 2, 72 - ih / 2)
      else
        G.setColor(0.85, 0.55, 0.70, alpha)
        G.rectangle("fill", 80, 48, 48, 48)
      end
      G.setColor(1, 1, 1, 1)
    elseif b and b.showTrainer then
      self:drawBirchTrainer()
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
    self:drawBirchBg()
    self:drawBirchTrainer()
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
    self:drawBirchBg()
    self:drawBirchTrainer()
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
    local Naming = require("src.ui.gen3.NamingScreen")
    local b = self.boot
    local f = b and b.naming
    if not f then
      local G = love.graphics
      G.setColor(0.10, 0.22, 0.45, 1)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      return
    end
    f.name = b.name or f.name
    Naming.draw(self, f)
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
