-- Ruby/Sapphire move-animation subset for Game3.
-- Reference: pokeruby data/battle_anim_scripts.s + src/battle_anim.c
--
-- Battle path (ROM):
--   battle_scripts_1.s  attackanimation / waitanimation
--   battle_controllers → BtlController_EmitMoveAnimation
--   *HandleMoveAnimation → DoMoveAnim(move)
--   DoMoveAnim → LaunchBattleAnimation(gBattleAnims_Moves, move, TRUE)
--   LaunchBattleAnimation sets sBattleAnimScriptPtr = gBattleAnims_Moves[move]
--   and runs RunAnimScriptCommand until the script ends.
--
-- This module is NOT Gen1 AnimPlayer / data/generated/battle_anims.lua.
-- It plays a small set of early-game scripts with frame timings close to ROM
-- (60 fps). Unimplemented moves keep Game3's generic typed burst.

local MA = {}

MA.FPS = 60

-- pokeruby include/constants/moves.h (subset)
MA.MOVE_POUND = 1
MA.MOVE_SCRATCH = 10
MA.MOVE_VINE_WHIP = 22
MA.MOVE_TACKLE = 33
MA.MOVE_TAIL_WHIP = 39
MA.MOVE_GROWL = 45
MA.MOVE_EMBER = 52
MA.MOVE_WATER_GUN = 55
MA.MOVE_ABSORB = 71
MA.MOVE_THUNDER_SHOCK = 84
MA.MOVE_QUICK_ATTACK = 98
MA.MOVE_CUT = 15
MA.MOVE_GUST = 16
MA.MOVE_WING_ATTACK = 17
MA.MOVE_SAND_ATTACK = 28
MA.MOVE_HEADBUTT = 29
MA.MOVE_BODY_SLAM = 34
MA.MOVE_TAKE_DOWN = 36
MA.MOVE_POISON_STING = 40
MA.MOVE_LEER = 43
MA.MOVE_BITE = 44
MA.MOVE_FLAMETHROWER = 53
MA.MOVE_SURF = 57
MA.MOVE_PSYBEAM = 60
MA.MOVE_BUBBLE_BEAM = 61
MA.MOVE_HYPER_BEAM = 63
MA.MOVE_PECK = 64
MA.MOVE_STRENGTH = 70
MA.MOVE_MEGA_DRAIN = 72
MA.MOVE_RAZOR_LEAF = 75
MA.MOVE_POISON_POWDER = 77
MA.MOVE_STUN_SPORE = 78
MA.MOVE_SLEEP_POWDER = 79
MA.MOVE_STRING_SHOT = 81
MA.MOVE_FIRE_SPIN = 83
MA.MOVE_ROCK_THROW = 88
MA.MOVE_DIG = 91
MA.MOVE_TOXIC = 92
MA.MOVE_CONFUSION = 93
MA.MOVE_DOUBLE_TEAM = 104
MA.MOVE_HARDEN = 106
MA.MOVE_BUBBLE = 145
MA.MOVE_REST = 156
MA.MOVE_PROTECT = 182
MA.MOVE_MUD_SLAP = 189
MA.MOVE_METAL_CLAW = 232
MA.MOVE_ROCK_SMASH = 249
MA.MOVE_AERIAL_ACE = 332

MA.MOVE_SLAM = 21
MA.MOVE_HYDRO_PUMP = 56
MA.MOVE_ICE_BEAM = 58
MA.MOVE_BLIZZARD = 59
MA.MOVE_THUNDERBOLT = 85
MA.MOVE_THUNDER_WAVE = 86
MA.MOVE_THUNDER = 87
MA.MOVE_EARTHQUAKE = 89
MA.MOVE_PSYCHIC = 94
MA.MOVE_LIGHT_SCREEN = 113
MA.MOVE_REFLECT = 115
MA.MOVE_SPIKES = 191
MA.MOVE_ATTRACT = 213
MA.MOVE_RETURN = 216
MA.MOVE_FRUSTRATION = 218
MA.MOVE_SAFEGUARD = 219
MA.MOVE_MAGNITUDE = 222
MA.MOVE_HIDDEN_POWER = 237
MA.MOVE_CRUNCH = 242
MA.MOVE_SHADOW_BALL = 247
MA.MOVE_FAKE_OUT = 252
MA.MOVE_WILL_O_WISP = 261
MA.MOVE_FACADE = 263
MA.MOVE_FOCUS_PUNCH = 264
MA.MOVE_REVENGE = 279
MA.MOVE_BRICK_BREAK = 280
MA.MOVE_ENDEAVOR = 283
MA.MOVE_ERUPTION = 284
MA.MOVE_OVERHEAT = 315
MA.MOVE_DRAGON_CLAW = 337
MA.MOVE_BULK_UP = 339
MA.MOVE_CALM_MIND = 347

MA.MOVE_SWORDS_DANCE = 14
MA.MOVE_FLY = 19
MA.MOVE_COUNTER = 68
MA.MOVE_SOLAR_BEAM = 76
MA.MOVE_RECOVER = 105
MA.MOVE_METRONOME = 118
MA.MOVE_SELF_DESTRUCT = 120
MA.MOVE_SKULL_BASH = 130
MA.MOVE_SOFT_BOILED = 135
MA.MOVE_TRANSFORM = 144
MA.MOVE_SPLASH = 150
MA.MOVE_EXPLOSION = 153
MA.MOVE_STRUGGLE = 165
MA.MOVE_DESTINY_BOND = 194
MA.MOVE_SANDSTORM = 201
MA.MOVE_RAPID_SPIN = 229
MA.MOVE_RAIN_DANCE = 240
MA.MOVE_SUNNY_DAY = 241
MA.MOVE_MIRROR_COAT = 243
MA.MOVE_HAIL = 258
MA.MOVE_DIVE = 291
MA.MOVE_DRAGON_DANCE = 349

-- Wave 5
MA.MOVE_RAZOR_WIND = 13
MA.MOVE_DOUBLE_EDGE = 38
MA.MOVE_SUBMISSION = 66
MA.MOVE_SKY_ATTACK = 143
MA.MOVE_CRABHAMMER = 152
MA.MOVE_TRI_ATTACK = 161
MA.MOVE_DYNAMIC_PUNCH = 223
MA.MOVE_MEGAHORN = 224
MA.MOVE_IRON_TAIL = 231
MA.MOVE_CROSS_CHOP = 238
MA.MOVE_EXTREME_SPEED = 245
MA.MOVE_ANCIENT_POWER = 246
MA.MOVE_FUTURE_SIGHT = 248
MA.MOVE_SMELLING_SALT = 265
MA.MOVE_FOLLOW_ME = 266
MA.MOVE_HELPING_HAND = 270
MA.MOVE_TRICK = 271
MA.MOVE_ROLE_PLAY = 272
MA.MOVE_WISH = 273
MA.MOVE_ASSIST = 274
MA.MOVE_INGRAIN = 275
MA.MOVE_SUPERPOWER = 276
MA.MOVE_RECYCLE = 278
MA.MOVE_YAWN = 281
MA.MOVE_SKILL_SWAP = 285
MA.MOVE_IMPRISON = 286
MA.MOVE_REFRESH = 287
MA.MOVE_GRUDGE = 288
MA.MOVE_SNATCH = 289
MA.MOVE_ARM_THRUST = 292
MA.MOVE_CAMOUFLAGE = 293
MA.MOVE_SLACK_OFF = 303
MA.MOVE_BOUNCE = 340

-- Optional runtime load of pokeruby anim sheets (indexed PNGs, tinted).
-- Never copied into assets/ — load from the local pokeruby tree if present.
MA.SPRITE_DIR = "misc/pokeruby-master/pokeruby-master/graphics/battle_anims/sprites/"
MA.TAG = {
  IMPACT = 135,       -- ANIM_TAG_IMPACT
  SCRATCH = 137,      -- ANIM_TAG_SCRATCH
  SMALL_EMBER = 29,   -- ANIM_TAG_SMALL_EMBER
  SMALL_BUBBLES = 155,-- ANIM_TAG_SMALL_BUBBLES
  WATER_IMPACT = 148, -- ANIM_TAG_WATER_IMPACT
  WHIP_HIT = 287,     -- ANIM_TAG_WHIP_HIT
  ORBS = 147,         -- ANIM_TAG_ORBS
  BLUE_STAR = 31,     -- ANIM_TAG_BLUE_STAR
  NOISE_LINE = 53,    -- ANIM_TAG_NOISE_LINE
  SPARK = 1,          -- ANIM_TAG_SPARK (001_0.png multi)
  GUST = 9,           -- ANIM_TAG_GUST
  LEER = 27,          -- ANIM_TAG_LEER
  CLAW_SLASH = 39,    -- ANIM_TAG_CLAW_SLASH
  ROCKS = 58,         -- ANIM_TAG_ROCKS
  LEAF = 63,          -- ANIM_TAG_LEAF
  POISON_POWDER = 65, -- ANIM_TAG_POISON_POWDER (stun/sleep tint)
  MUD_SAND = 74,      -- ANIM_TAG_MUD_SAND (074_0.png)
  CUT = 138,          -- ANIM_TAG_CUT
  SHARP_TEETH = 139,  -- ANIM_TAG_SHARP_TEETH
  HANDS_FEET = 143,   -- ANIM_TAG_HANDS_AND_FEET
  BUBBLE = 146,       -- ANIM_TAG_BUBBLE
  POISON_BUBBLE = 150,-- ANIM_TAG_POISON_BUBBLE
  TOXIC_BUBBLE = 151, -- ANIM_TAG_TOXIC_BUBBLE
  RAZOR_LEAF = 160,   -- ANIM_TAG_RAZOR_LEAF
  NEEDLE = 161,       -- ANIM_TAG_NEEDLE
  GOLD_RING = 163,    -- ANIM_TAG_GOLD_RING
  STRING = 179,       -- ANIM_TAG_STRING
  STRING_DOT = 180,   -- ANIM_TAG_STRING_DOT
  LETTER_Z = 228,     -- ANIM_TAG_LETTER_Z
  PROTECT = 280,      -- ANIM_TAG_PROTECT
  DIRT_MOUND = 281,   -- ANIM_TAG_DIRT_MOUND

  SLAM_HIT = 56,      -- ANIM_TAG_SLAM_HIT
  LIGHTNING = 37,     -- ANIM_TAG_LIGHTNING
  BREATH = 86,        -- ANIM_TAG_BREATH
  ANGER = 87,         -- ANIM_TAG_ANGER
  ICE_CRYSTALS = 141, -- ANIM_TAG_ICE_CRYSTALS
  WATER_ORB = 149,    -- ANIM_TAG_WATER_ORB
  SPIKES = 152,       -- ANIM_TAG_SPIKES
  GREEN_LIGHT_WALL = 166, -- ANIM_TAG_GREEN_LIGHT_WALL
  BLUE_LIGHT_WALL = 167,  -- ANIM_TAG_BLUE_LIGHT_WALL
  SHOCK = 79,         -- ANIM_TAG_SHOCK
  SHADOW_BALL = 176,  -- ANIM_TAG_SHADOW_BALL
  THIN_RING = 203,    -- ANIM_TAG_THIN_RING
  RED_HEART = 216,    -- ANIM_TAG_RED_HEART
  RED_ORB = 217,      -- ANIM_TAG_RED_ORB
  WISP_ORB = 231,     -- ANIM_TAG_WISP_ORB
  WISP_FIRE = 232,    -- ANIM_TAG_WISP_FIRE
  SWEAT_DROP = 243,   -- ANIM_TAG_SWEAT_DROP
  GUARD_RING = 244,   -- ANIM_TAG_GUARD_RING
  PURPLE_SCRATCH = 245, -- ANIM_TAG_PURPLE_SCRATCH
  SHOCK_3 = 282,      -- ANIM_TAG_SHOCK_3

  SWORD = 5,          -- ANIM_TAG_SWORD
  FINGER = 64,        -- ANIM_TAG_FINGER
  RAIN_DROPS = 115,   -- ANIM_TAG_RAIN_DROPS
  ROUND_SHADOW = 156, -- ANIM_TAG_ROUND_SHADOW
  SUNLIGHT = 157,     -- ANIM_TAG_SUNLIGHT
  EXPLOSION = 198,    -- ANIM_TAG_EXPLOSION
  GHOSTLY_SPIRIT = 200, -- ANIM_TAG_GHOSTLY_SPIRIT
  TORN_METAL = 208,   -- ANIM_TAG_TORN_METAL
  RAPID_SPIN = 229,   -- ANIM_TAG_RAPID_SPIN
  SPEED_DUST = 207,   -- ANIM_TAG_SPEED_DUST
  HOLLOW_ORB = 249,   -- ANIM_TAG_HOLLOW_ORB
  HAIL = 263,         -- ANIM_TAG_HAIL
  SPLASH = 272,       -- ANIM_TAG_SPLASH

  -- Wave 5
  HORN_HIT = 20,      -- ANIM_TAG_HORN_HIT
  SPARKLE_2 = 49,     -- ANIM_TAG_SPARKLE_2
  AIR_WAVE_2 = 154,   -- ANIM_TAG_AIR_WAVE_2
  THOUGHT_BUBBLE = 209, -- ANIM_TAG_THOUGHT_BUBBLE
  ROOTS = 223,        -- ANIM_TAG_ROOTS
  ITEM_BAG = 224,     -- ANIM_TAG_ITEM_BAG
  TRI_FORCE = 230,    -- ANIM_TAG_TRI_FORCE_TRIANGLE
  GREEN_STAR = 241,   -- ANIM_TAG_GREEN_STAR
  BIRD = 284,         -- ANIM_TAG_BIRD
  CROSS_IMPACT = 285, -- ANIM_TAG_CROSS_IMPACT
}

local _imgCache = {}

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function fileExists(path)
  if love and love.filesystem and love.filesystem.getInfo then
    local info = love.filesystem.getInfo(path)
    if info then return true end
  end
  -- Absolute / working-dir fallback for desktop runs that mount the repo root.
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- pokeruby graphics/battle_anims/sprites/*.png are indexed with NO tRNS.
-- GBA OBJ treats palette index 0 as transparent; LOVE loads every texel opaque
-- (pad color visible). Key that pad color (sampled at 0,0) to alpha 0.
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
    string.format("%s%03d.png", MA.SPRITE_DIR, tagIndex),
    string.format("%s%03d_0.png", MA.SPRITE_DIR, tagIndex),
  }
  if not (love and love.graphics and love.graphics.newImage) then
    _imgCache[tagIndex] = false
    return nil
  end
  for i = 1, #candidates do
    local path = candidates[i]
    if fileExists(path) then
      local img
      -- Prefer ImageData so palette-0 pad can become real alpha (enemy + player FX).
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

-- Asset provenance for the report.
MA.ASSET_NOTES = {
  IMPACT = "pokeruby sprites/135.png (palette0 keyed to alpha) when present; else procedural X-splat",
  SCRATCH = "pokeruby sprites/137.png when present; else procedural claw arcs",
  SMALL_EMBER = "pokeruby sprites/029.png when present; else procedural ember orbs",
  SMALL_BUBBLES = "pokeruby sprites/155.png when present; else procedural bubbles",
  WATER_IMPACT = "pokeruby sprites/148.png when present; else procedural splash",
  WHIP_HIT = "pokeruby sprites/287.png when present; else procedural whip slash",
  ORBS = "pokeruby sprites/147.png when present; else procedural green orbs",
  BLUE_STAR = "pokeruby sprites/031.png when present; else procedural heal stars",
  NOISE_LINE = "pokeruby sprites/053.png when present; else procedural noise wedges",
  SPARK = "pokeruby sprites/001_0.png when present; else procedural sparks",
  GUST = "pokeruby sprites/009.png when present; else procedural swirl",
  LEER = "pokeruby sprites/027.png when present; else procedural glare",
  CLAW_SLASH = "pokeruby sprites/039.png when present; else procedural claws",
  ROCKS = "pokeruby sprites/058.png when present; else procedural rocks",
  LEAF = "pokeruby sprites/063.png when present; else procedural leaves",
  POISON_POWDER = "pokeruby sprites/065.png (tint for stun/sleep); else powder dots",
  MUD_SAND = "pokeruby sprites/074_0.png when present; else dirt dots",
  CUT = "pokeruby sprites/138.png when present; else slash line",
  SHARP_TEETH = "pokeruby sprites/139.png when present; else jaw wedges",
  HANDS_FEET = "pokeruby sprites/143.png when present; else fist disc",
  BUBBLE = "pokeruby sprites/146.png when present; else bubble circles",
  POISON_BUBBLE = "pokeruby sprites/150.png when present; else purple bubbles",
  TOXIC_BUBBLE = "pokeruby sprites/151.png when present; else toxic orbs",
  RAZOR_LEAF = "pokeruby sprites/160.png when present; else leaf blades",
  NEEDLE = "pokeruby sprites/161.png when present; else stinger",
  GOLD_RING = "pokeruby sprites/163.png when present; else psy rings",
  STRING = "pokeruby sprites/179.png when present; else silk lines",
  LETTER_Z = "pokeruby sprites/228.png when present; else Z glyphs",
  PROTECT = "pokeruby sprites/280.png when present; else shield arc",
  DIRT_MOUND = "pokeruby sprites/281.png when present; else dirt pile",

  SLAM_HIT = "pokeruby sprites/056.png when present; else slam arc",
  LIGHTNING = "pokeruby sprites/037.png when present; else bolt segments",
  BREATH = "pokeruby sprites/086.png when present; else breath puff",
  ANGER = "pokeruby sprites/087.png when present; else anger veins",
  ICE_CRYSTALS = "pokeruby sprites/141.png when present; else ice shards",
  WATER_ORB = "pokeruby sprites/149.png when present; else water orbs",
  SPIKES = "pokeruby sprites/152.png when present; else spike wedges",
  GREEN_LIGHT_WALL = "pokeruby sprites/166.png when present; else green barrier",
  BLUE_LIGHT_WALL = "pokeruby sprites/167.png when present; else blue barrier",
  SHOCK = "pokeruby sprites/079.png when present; else shock disc",
  SHADOW_BALL = "pokeruby sprites/176.png when present; else purple ball",
  THIN_RING = "pokeruby sprites/203.png when present; else thin rings",
  RED_HEART = "pokeruby sprites/216.png when present; else hearts",
  RED_ORB = "pokeruby sprites/217.png when present; else red orbs",
  WISP_ORB = "pokeruby sprites/231.png when present; else wisp orbs",
  WISP_FIRE = "pokeruby sprites/232.png when present; else blue fire",
  SWEAT_DROP = "pokeruby sprites/243.png when present; else sweat drops",
  GUARD_RING = "pokeruby sprites/244.png when present; else guard rings",
  PURPLE_SCRATCH = "pokeruby sprites/245.png when present; else purple scratch",
  SHOCK_3 = "pokeruby sprites/282.png when present; else thunderbolt head",
}

---------------------------------------------------------------------------
-- Script table: frame counts derived from battle_anim_scripts.s delays +
-- AnimTask_ShakeMon / sprite travel args (see comments per move).
---------------------------------------------------------------------------

-- Each script:
--   frames  = total wait-ish duration we block the FX for (seconds = frames/60)
--   rom     = label + VA
--   se      = optional SE_* name for documentation
--   draw(frame, ctx) optional — or use built-in kind handlers via `fx`

local SCRIPTS_BY_ID = {}
local SCRIPTS_BY_NAME = {}

local function addScript(ids, names, spec)
  for i = 1, #ids do SCRIPTS_BY_ID[ids[i]] = spec end
  for i = 1, #names do SCRIPTS_BY_NAME[names[i]] = spec end
end

-- Move_POUND @ 81C7794: hit splat + AnimTask_ShakeMon(tgt,3,0,6,1)
-- ShakeMon: 6 toggles × 1f delay ≈ 6f; BasicHitSplat ~8f → ~12–14f
addScript({ MA.MOVE_POUND }, { "POUND" }, {
  frames = 14,
  rom = "Move_POUND @ 81C7794",
  fx = "pound",
  se = "SE_M_DOUBLE_SLAP",
  seId = 134, -- SE_M_DOUBLE_SLAP
})

-- Move_TACKLE @ 81C7CF2: HorizontalLunge(4,4) + delay 6 + splat + shake 6
addScript({ MA.MOVE_TACKLE }, { "TACKLE" }, {
  frames = 22,
  rom = "Move_TACKLE @ 81C7CF2",
  fx = "tackle",
  se = "SE_M_COMET_PUNCH",
  seId = 139, -- SE_M_COMET_PUNCH
})

-- Move_SCRATCH @ 81CE1D8: scratch sprite + shake 6
addScript({ MA.MOVE_SCRATCH }, { "SCRATCH" }, {
  frames = 16,
  rom = "Move_SCRATCH @ 81CE1D8",
  fx = "scratch",
  se = "SE_M_SCRATCH",
  seId = 155, -- SE_M_SCRATCH
})

-- Move_EMBER @ 81C84D9: 3 embers (delay 4) travel 20f; delay 16; 3 flares
-- 0+4+4 + 20 travel overlap + 16 + 4*3 ≈ 48–52f
addScript({ MA.MOVE_EMBER }, { "EMBER" }, {
  frames = 52,
  rom = "Move_EMBER @ 81C84D9",
  fx = "ember",
  se = "SE_M_EMBER / SE_M_FLAME_WHEEL",
  seId = 151, -- SE_M_EMBER (primary)
  -- loopsewithpan SE_M_EMBER period 5 count 2; later playse SE_M_FLAME_WHEEL
  seChain = {
    { f = 0, id = 151 },
    { f = 5, id = 151 },
    { f = 28, id = 144 }, -- SE_M_FLAME_WHEEL after ember travel
  },
})

-- Move_WATER_GUN @ 81D00CC: bubble travel 40f; splash + 3 droplets delay 10
addScript({ MA.MOVE_WATER_GUN }, { "WATER GUN", "WATERGUN" }, {
  frames = 78,
  rom = "Move_WATER_GUN @ 81D00CC",
  fx = "water_gun",
  se = "SE_M_BUBBLE / SE_M_CRABHAMMER",
  seId = 124, -- SE_M_BUBBLE
})

-- Move_VINE_WHIP @ 81C9391: lunge + delay 6 + whip + delay 6 + shake
addScript({ MA.MOVE_VINE_WHIP }, { "VINE WHIP", "VINEWHIP" }, {
  frames = 22,
  rom = "Move_VINE_WHIP @ 81C9391",
  fx = "vine_whip",
  se = "SE_M_JUMP_KICK / SE_M_SCRATCH",
  seId = 143, -- SE_M_JUMP_KICK
})

-- Move_ABSORB @ 81CF427: blend + hit + orb stream (~8×4) + heal stars
addScript({ MA.MOVE_ABSORB }, { "ABSORB" }, {
  frames = 90,
  rom = "Move_ABSORB @ 81CF427",
  fx = "absorb",
  se = "SE_M_ABSORB / SE_M_CRABHAMMER",
  seId = 180, -- SE_M_ABSORB
})

-- Move_THUNDER_SHOCK @ 81C879C: fade + bolt + flash + ElectricityEffect (~16f)
addScript({ MA.MOVE_THUNDER_SHOCK }, { "THUNDERSHOCK", "THUNDER SHOCK" }, {
  frames = 96,
  rom = "Move_THUNDER_SHOCK @ 81C879C",
  fx = "thunder_shock",
  se = "SE_M_THUNDERBOLT / SE_M_THUNDERBOLT2",
  seId = 118, -- SE_M_THUNDERBOLT
})

-- Move_QUICK_ATTACK @ 81CB224: elliptical dash + afterimage + hit
addScript({ MA.MOVE_QUICK_ATTACK }, { "QUICK ATTACK", "QUICKATTACK" }, {
  frames = 30,
  rom = "Move_QUICK_ATTACK @ 81CB224",
  fx = "quick_attack",
  se = "SE_M_JUMP_KICK / SE_M_VITAL_THROW2",
  seId = 143, -- SE_M_JUMP_KICK
})

-- Move_GROWL @ 81CE3AF: noise lines (_81CE35E) + shake 9 + delay 20
addScript({ MA.MOVE_GROWL }, { "GROWL" }, {
  frames = 72,
  rom = "Move_GROWL @ 81CE3AF",
  fx = "growl",
  se = "sub_812B18C cry",
  seCry = true, -- Growl plays species cry, not SE_M_SNORE
})

-- Move_TAIL_WHIP @ 81C8B71: AnimTask_TranslateMonEllipticalRespectSide ×3
addScript({ MA.MOVE_TAIL_WHIP }, { "TAIL WHIP", "TAILWHIP" }, {
  frames = 48,
  rom = "Move_TAIL_WHIP @ 81C8B71",
  fx = "tail_whip",
  se = "SE_M_TAIL_WHIP",
  seId = 167, -- SE_M_TAIL_WHIP
})


-- ===== Wave-2 early/mid + gym-relevant scripts =====

-- Move_MUD_SLAP @ 81CE81C: slide + 6 mud sprays (delay 2 each)
addScript({ MA.MOVE_MUD_SLAP }, { "MUD-SLAP", "MUD SLAP", "MUDSLAP" }, {
  frames = 36,
  rom = "Move_MUD_SLAP @ 81CE81C",
  fx = "mud_slap",
  se = "SE_M_SAND_ATTACK",
  seId = 159,
})

-- Move_SAND_ATTACK @ 81CE774: slide + 6 dirt sprays
addScript({ MA.MOVE_SAND_ATTACK }, { "SAND-ATTACK", "SAND ATTACK", "SANDATTACK" }, {
  frames = 36,
  rom = "Move_SAND_ATTACK @ 81CE774",
  fx = "sand_attack",
  se = "SE_M_SAND_ATTACK",
  seId = 159,
})

-- Move_ROCK_THROW @ 81CA35F: 5 rocks delay 6 + shake 20
addScript({ MA.MOVE_ROCK_THROW }, { "ROCK THROW", "ROCKTHROW" }, {
  frames = 48,
  rom = "Move_ROCK_THROW @ 81CA35F",
  fx = "rock_throw",
  se = "SE_M_ROCK_THROW",
  seId = 131,
})

-- Move_BUBBLE @ 81CE59C: 6 bubbles delay 6 travel ~100 + WaterBubbleEffect2
addScript({ MA.MOVE_BUBBLE }, { "BUBBLE" }, {
  frames = 100,
  rom = "Move_BUBBLE @ 81CE59C",
  fx = "bubble",
  se = "SE_M_BUBBLE",
  seId = 124,
})

-- Move_BUBBLE_BEAM @ 81CA573: 3×6 bubble stream + sway + WaterBubbleEffect
addScript({ MA.MOVE_BUBBLE_BEAM }, { "BUBBLEBEAM", "BUBBLE BEAM" }, {
  frames = 90,
  rom = "Move_BUBBLE_BEAM @ 81CA573",
  fx = "bubblebeam",
  se = "SE_M_BUBBLE",
  seId = 124,
})

-- Move_RAZOR_LEAF @ 81D0DDE: leaf swirl ~60f then blades + shake
addScript({ MA.MOVE_RAZOR_LEAF }, { "RAZOR LEAF", "RAZORLEAF" }, {
  frames = 110,
  rom = "Move_RAZOR_LEAF @ 81D0DDE",
  fx = "razor_leaf",
  se = "SE_M_POISON_POWDER / SE_M_RAZOR_WIND",
  seId = 169,
})

-- Move_BITE @ 81CE9E2: teeth clamp 10f + splat + shake 7
addScript({ MA.MOVE_BITE }, { "BITE" }, {
  frames = 28,
  rom = "Move_BITE @ 81CE9E2",
  fx = "bite",
  se = "SE_M_BITE",
  seId = 161,
})

-- Move_STRING_SHOT @ 81D1C98: darken + 18 string dots + wrap
addScript({ MA.MOVE_STRING_SHOT }, { "STRING SHOT", "STRINGSHOT" }, {
  frames = 90,
  rom = "Move_STRING_SHOT @ 81D1C98",
  fx = "string_shot",
  se = "SE_M_STRING_SHOT / SE_M_STRING_SHOT2",
  seId = 129,
})

-- Move_HARDEN @ 81CD909: metal gleam loopse 28×2
addScript({ MA.MOVE_HARDEN }, { "HARDEN" }, {
  frames = 56,
  rom = "Move_HARDEN @ 81CD909",
  fx = "harden",
  se = "SE_M_HARDEN",
  seId = 120,
})

-- Move_LEER @ 81D121A: leer sprite + scale + shake 9
addScript({ MA.MOVE_LEER }, { "LEER" }, {
  frames = 40,
  rom = "Move_LEER @ 81D121A",
  fx = "leer",
  se = "SE_M_LEER",
  seId = 192,
})

-- Move_GUST @ 81CFE9A: gust swirl + hit splat
addScript({ MA.MOVE_GUST }, { "GUST" }, {
  frames = 50,
  rom = "Move_GUST @ 81CFE9A",
  fx = "gust",
  se = "SE_M_GUST / SE_M_GUST2",
  seId = 132,
})

-- Move_PECK @ 81CFF88: peck impact
addScript({ MA.MOVE_PECK }, { "PECK" }, {
  frames = 16,
  rom = "Move_PECK @ 81CFF88",
  fx = "peck",
  se = "SE_M_HORN_ATTACK",
  seId = 166,
})

-- Move_WING_ATTACK @ 81CFEEB: elliptical + dual gust + hits
addScript({ MA.MOVE_WING_ATTACK }, { "WING ATTACK", "WINGATTACK" }, {
  frames = 60,
  rom = "Move_WING_ATTACK @ 81CFEEB",
  fx = "wing_attack",
  se = "SE_M_WING_ATTACK",
  seId = 157,
})

-- Move_MEGA_DRAIN @ 81CF53F: absorb-like denser orb stream + heal
addScript({ MA.MOVE_MEGA_DRAIN }, { "MEGA DRAIN", "MEGADRAIN" }, {
  frames = 110,
  rom = "Move_MEGA_DRAIN @ 81CF53F",
  fx = "mega_drain",
  se = "SE_M_ABSORB / SE_M_BUBBLE3",
  seId = 180,
})

-- Move_FIRE_SPIN @ 81C9096: ember spiral ×3 + shake 47
addScript({ MA.MOVE_FIRE_SPIN }, { "FIRE SPIN", "FIRESPIN" }, {
  frames = 52,
  rom = "Move_FIRE_SPIN @ 81C9096",
  fx = "fire_spin",
  se = "SE_M_SACRED_FIRE2",
  seId = 150,
})

-- Move_FLAMETHROWER @ 81D0267: ember stream ×10 calls delay 2
addScript({ MA.MOVE_FLAMETHROWER }, { "FLAMETHROWER" }, {
  frames = 70,
  rom = "Move_FLAMETHROWER @ 81D0267",
  fx = "flamethrower",
  se = "SE_M_FLAMETHROWER",
  seId = 146,
  -- panse_1B after delay 6
  seChain = { { f = 6, id = 146 } },
})

-- Move_CONFUSION @ 81CDC69: psychic bg + shake attacker/target
addScript({ MA.MOVE_CONFUSION }, { "CONFUSION" }, {
  frames = 50,
  rom = "Move_CONFUSION @ 81CDC69",
  fx = "confusion",
  se = "SE_M_SUPERSONIC",
  seId = 184,
})

-- Move_PSYBEAM @ 81D15A2: gold rings ×11 delay 4 + sway
addScript({ MA.MOVE_PSYBEAM }, { "PSYBEAM" }, {
  frames = 80,
  rom = "Move_PSYBEAM @ 81D15A2",
  fx = "psybeam",
  se = "SE_M_PSYBEAM",
  seId = 189,
})

-- Move_ROCK_SMASH @ 81D09F6: fist + splat + rock burst
addScript({ MA.MOVE_ROCK_SMASH }, { "ROCK SMASH", "ROCKSMASH" }, {
  frames = 40,
  rom = "Move_ROCK_SMASH @ 81D09F6",
  fx = "rock_smash",
  se = "SE_M_VITAL_THROW2 / SE_M_ROCK_THROW",
  seId = 123,
})

-- Move_POISON_STING @ 81C828D: needle travel 20 + splat + poison bubbles
addScript({ MA.MOVE_POISON_STING }, { "POISON STING", "POISONSTING" }, {
  frames = 55,
  rom = "Move_POISON_STING @ 81C828D",
  fx = "poison_sting",
  se = "SE_M_RAZOR_WIND2 / SE_M_HORN_ATTACK",
  seId = 160,
})

-- Powder trio share particle layout; tint differs
addScript({ MA.MOVE_POISON_POWDER }, { "POISONPOWDER", "POISON POWDER" }, {
  frames = 80,
  rom = "Move_POISON_POWDER @ 81C7818",
  fx = "poison_powder",
  se = "SE_M_POISON_POWDER",
  seId = 169,
})
addScript({ MA.MOVE_STUN_SPORE }, { "STUN SPORE", "STUNSPORE" }, {
  frames = 80,
  rom = "Move_STUN_SPORE @ 81C7949",
  fx = "stun_spore",
  se = "SE_M_POISON_POWDER",
  seId = 169,
})
addScript({ MA.MOVE_SLEEP_POWDER }, { "SLEEP POWDER", "SLEEPPOWDER" }, {
  frames = 80,
  rom = "Move_SLEEP_POWDER @ 81C7A77",
  fx = "sleep_powder",
  se = "SE_M_POISON_POWDER",
  seId = 169,
})

-- Move_HEADBUTT @ 81CAABD: nod ×2 + hit
addScript({ MA.MOVE_HEADBUTT }, { "HEADBUTT" }, {
  frames = 32,
  rom = "Move_HEADBUTT @ 81CAABD",
  fx = "headbutt",
  se = "SE_M_HEADBUTT / SE_M_VITAL_THROW2",
  seId = 162,
})

-- Move_BODY_SLAM @ 81C7D30: dip + slide slam
addScript({ MA.MOVE_BODY_SLAM }, { "BODY SLAM", "BODYSLAM" }, {
  frames = 55,
  rom = "Move_BODY_SLAM @ 81C7D30",
  fx = "body_slam",
  se = "SE_M_TAKE_DOWN / SE_M_MEGA_KICK2",
  seId = 152,
})

-- Move_TAKE_DOWN @ 81C80E6: WindUpLunge ~35 + hit
addScript({ MA.MOVE_TAKE_DOWN }, { "TAKE DOWN", "TAKEDOWN" }, {
  frames = 70,
  rom = "Move_TAKE_DOWN @ 81C80E6",
  fx = "take_down",
  se = "SE_M_TAKE_DOWN / SE_M_MEGA_KICK2",
  seId = 152,
})

-- Move_STRENGTH @ 81C7C5E: sink + elliptical + 3 splats
addScript({ MA.MOVE_STRENGTH }, { "STRENGTH" }, {
  frames = 80,
  rom = "Move_STRENGTH @ 81C7C5E",
  fx = "strength",
  se = "SE_M_TAKE_DOWN / SE_M_MEGA_KICK2",
  seId = 152,
})

-- Move_CUT @ 81C8B8A: cutting slice + shake 10
addScript({ MA.MOVE_CUT }, { "CUT" }, {
  frames = 28,
  rom = "Move_CUT @ 81C8B8A",
  fx = "cut",
  se = "SE_M_CUT",
  seId = 128,
})

-- Move_AERIAL_ACE @ 81CD499: elliptical + cut slice
addScript({ MA.MOVE_AERIAL_ACE }, { "AERIAL ACE", "AERIALACE" }, {
  frames = 32,
  rom = "Move_AERIAL_ACE @ 81CD499",
  fx = "aerial_ace",
  se = "SE_M_RAZOR_WIND2 / SE_M_RAZOR_WIND",
  seId = 160,
})

-- Move_METAL_CLAW @ 81D197A: harden gleam + dual claw lunges
addScript({ MA.MOVE_METAL_CLAW }, { "METAL CLAW", "METALCLAW" }, {
  frames = 50,
  rom = "Move_METAL_CLAW @ 81D197A",
  fx = "metal_claw",
  se = "SE_M_HARDEN / SE_M_RAZOR_WIND",
  seId = 120,
})

-- Move_PROTECT @ 81C97B5: protect barrier ~90
addScript({ MA.MOVE_PROTECT }, { "PROTECT" }, {
  frames = 90,
  rom = "Move_PROTECT @ 81C97B5",
  fx = "protect",
  se = "SE_M_REFLECT",
  seId = 207,
})

-- Move_REST @ 81CDC29: three Z sprites delay 20
addScript({ MA.MOVE_REST }, { "REST" }, {
  frames = 70,
  rom = "Move_REST @ 81CDC29",
  fx = "rest",
  se = "SE_M_SNORE",
  seId = 197,
})

-- Move_TOXIC @ 81CF983: toxic bubbles ×8 + PoisonBubblesAnim
addScript({ MA.MOVE_TOXIC }, { "TOXIC" }, {
  frames = 90,
  rom = "Move_TOXIC @ 81CF983",
  fx = "toxic",
  se = "SE_M_TOXIC",
  seId = 148,
})

-- Move_DIG @ 81CB0A1: true two-turn — charge dig-down; hit emerge
addScript({ MA.MOVE_DIG }, { "DIG" }, {
  frames = 50,
  chargeFrames = 40,
  rom = "Move_DIG @ 81CB0A1 choosetwoturnanim",
  fx = "dig_hit",
  chargeFx = "dig_charge",
  se = "SE_M_DIG / SE_M_MEGA_KICK2",
  seId = 175,
  chargeSeId = 175,
  -- hit: playse SE_M_MEGA_KICK2 then SE_M_DIG; charge: dig SE
  seChain = {
    { f = 0, id = 141 }, -- SE_M_MEGA_KICK2
    { f = 8, id = 175 }, -- SE_M_DIG
  },
  chargeSeChain = { { f = 0, id = 175 } },
})

-- Move_SURF @ 81D0253: AnimTask_CreateSurfWave + pan SE
addScript({ MA.MOVE_SURF }, { "SURF" }, {
  frames = 60,
  rom = "Move_SURF @ 81D0253",
  fx = "surf",
  se = "SE_M_SURF",
  seId = 163,
  -- panse_1B SE_M_SURF after delay 24
  seChain = { { f = 24, id = 163 } },
})

-- Move_HYPER_BEAM @ 81D31EA: darken + charge + orb beam
addScript({ MA.MOVE_HYPER_BEAM }, { "HYPER BEAM", "HYPERBEAM" }, {
  frames = 140,
  rom = "Move_HYPER_BEAM @ 81D31EA",
  fx = "hyper_beam",
  se = "SE_M_HYPER_BEAM / SE_M_HYPER_BEAM2",
  seId = 215,
  -- playse SE_M_HYPER_BEAM after fade; createsoundtask SE_M_HYPER_BEAM2 (247) during beam
  seChain = {
    { f = 18, id = 215 },
    { f = 50, id = 247 },
    { f = 65, id = 247 },
    { f = 80, id = 247 },
    { f = 95, id = 247 },
    { f = 110, id = 247 },
  },
})

-- Move_DOUBLE_TEAM @ 81CB30B: afterimage flashes SE×9
addScript({ MA.MOVE_DOUBLE_TEAM }, { "DOUBLE TEAM", "DOUBLETEAM" }, {
  frames = 120,
  rom = "Move_DOUBLE_TEAM @ 81CB30B",
  fx = "double_team",
  se = "SE_M_DOUBLE_TEAM",
  seId = 135,
  -- playse SE_M_DOUBLE_TEAM x9 with shrinking delays (32..8)
  seChain = {
    { f = 0, id = 135 },
    { f = 32, id = 135 },
    { f = 56, id = 135 },
    { f = 72, id = 135 },
    { f = 80, id = 135 },
    { f = 88, id = 135 },
    { f = 96, id = 135 },
    { f = 104, id = 135 },
    { f = 112, id = 135 },
  },
})

-- ===== Wave-3 gym / mid-late scripts (ROM-read battle_anim_scripts.s) =====

-- Move_MAGNITUDE @ 81CBCB0: screen shake 50 + optional flash; loopse SE_M_STRENGTH
addScript({ MA.MOVE_MAGNITUDE }, { "MAGNITUDE" }, {
  frames = 60,
  rom = "Move_MAGNITUDE @ 81CBCB0",
  fx = "magnitude",
  se = "SE_M_STRENGTH",
  seId = 214,
})

-- Move_BRICK_BREAK @ 81CC492: dual lunges + fist; shatter if screens (choosetwoturnanim)
addScript({ MA.MOVE_BRICK_BREAK }, { "BRICK BREAK", "BRICKBREAK" }, {
  frames = 100,
  rom = "Move_BRICK_BREAK @ 81CC492 (screen/no-screen)",
  fx = "brick_break",
  se = "SE_M_VITAL_THROW / SE_M_VITAL_THROW2 / SE_M_BRICK_BREAK",
  seId = 122,
})

-- Move_BULK_UP @ 81CD55E: swagger task + breath sprite
addScript({ MA.MOVE_BULK_UP }, { "BULK UP", "BULKUP" }, {
  frames = 40,
  rom = "Move_BULK_UP @ 81CD55E",
  fx = "bulk_up",
  se = "SE_M_SWAGGER",
  seId = 193,
})

-- Move_CALM_MIND @ 81CD6F7: darken + thin rings ×3 delay 14
addScript({ MA.MOVE_CALM_MIND }, { "CALM MIND", "CALMMIND" }, {
  frames = 80,
  rom = "Move_CALM_MIND @ 81CD6F7",
  fx = "calm_mind",
  se = "SE_M_SUPERSONIC",
  seId = 184,
})

-- Move_SHADOW_BALL @ 81D1AEF: ghost BG + ball travel + shake
addScript({ MA.MOVE_SHADOW_BALL }, { "SHADOW BALL", "SHADOWBALL" }, {
  frames = 70,
  rom = "Move_SHADOW_BALL @ 81D1AEF",
  fx = "shadow_ball",
  se = "SE_M_MIST / SE_M_SAND_ATTACK",
  seId = 168,
})

-- Move_EARTHQUAKE @ 81CAF31: dual shake tasks 50 + flashes
addScript({ MA.MOVE_EARTHQUAKE }, { "EARTHQUAKE" }, {
  frames = 50,
  rom = "Move_EARTHQUAKE @ 81CAF31",
  fx = "earthquake",
  se = "SE_M_EARTHQUAKE",
  seId = 234,
})

-- Move_HYDRO_PUMP @ 81CF240: water orb stream + impacts
addScript({ MA.MOVE_HYDRO_PUMP }, { "HYDRO PUMP", "HYDROPUMP" }, {
  frames = 90,
  rom = "Move_HYDRO_PUMP @ 81CF240",
  fx = "hydro_pump",
  se = "SE_M_HYDRO_PUMP",
  seId = 164,
})

-- Move_ICE_BEAM @ 81CEB4D: ice crystal beam + light ice damage
addScript({ MA.MOVE_ICE_BEAM }, { "ICE BEAM", "ICEBEAM" }, {
  frames = 90,
  rom = "Move_ICE_BEAM @ 81CEB4D",
  fx = "ice_beam",
  se = "SE_M_ICY_WIND / SE_M_MIST",
  seId = 137,
})

-- Move_THUNDERBOLT @ 81C880A: fade + 3 bolts + spark ring + ElectricityEffect
addScript({ MA.MOVE_THUNDERBOLT }, { "THUNDERBOLT" }, {
  frames = 130,
  rom = "Move_THUNDERBOLT @ 81C880A",
  fx = "thunderbolt",
  se = "SE_M_THUNDERBOLT / SE_M_HYPER_BEAM / SE_M_THUNDERBOLT2",
  seId = 118,
  -- 3x SE_M_THUNDERBOLT (delay 7), then SE_M_HYPER_BEAM spark, waitplay SE_M_THUNDERBOLT2
  seChain = {
    { f = 12, id = 118 },
    { f = 19, id = 118 },
    { f = 26, id = 118 },
    { f = 48, id = 215 }, -- SE_M_HYPER_BEAM
    { f = 78, id = 119 }, -- SE_M_THUNDERBOLT2
  },
})

-- Move_THUNDER @ 81CDDCE: thunder BG + multi lightning columns
addScript({ MA.MOVE_THUNDER }, { "THUNDER" }, {
  frames = 120,
  rom = "Move_THUNDER @ 81CDDCE",
  fx = "thunder",
  se = "SE_M_THUNDER_WAVE / SE_M_TRI_ATTACK2",
  seId = 138,
  -- delay 16 + 3x SE_M_THUNDER_WAVE, later SE_M_TRI_ATTACK2
  seChain = {
    { f = 16, id = 138 },
    { f = 39, id = 138 },
    { f = 47, id = 138 },
    { f = 88, id = 221 }, -- SE_M_TRI_ATTACK2
  },
})

-- Move_BLIZZARD @ 81CEFBA: highspeed BG + snowballs + heavy ice
addScript({ MA.MOVE_BLIZZARD }, { "BLIZZARD" }, {
  frames = 100,
  rom = "Move_BLIZZARD @ 81CEFBA",
  fx = "blizzard",
  se = "SE_M_BLIZZARD / SE_M_BLIZZARD2",
  seId = 153,
  -- playse SE_M_BLIZZARD2 after highspeed BG settle
  seChain = { { f = 16, id = 154 } },
})

-- Move_PSYCHIC @ 81CDCCA: psychic BG + shake/scale target
addScript({ MA.MOVE_PSYCHIC }, { "PSYCHIC" }, {
  frames = 60,
  rom = "Move_PSYCHIC @ 81CDCCA",
  fx = "psychic",
  se = "SE_M_SUPERSONIC",
  seId = 184,
  -- loopsewithpan SE_M_SUPERSONIC period 10 count 3
  seChain = {
    { f = 8, id = 184 },
    { f = 18, id = 184 },
    { f = 28, id = 184 },
  },
})

-- Move_CRUNCH @ 81CEA40: dark BG + dual angled teeth bites
addScript({ MA.MOVE_CRUNCH }, { "CRUNCH" }, {
  frames = 70,
  rom = "Move_CRUNCH @ 81CEA40",
  fx = "crunch",
  se = "SE_M_BITE",
  seId = 161,
})

-- Move_DRAGON_CLAW @ 81D380C: red blend + ember plumes + claw slashes
addScript({ MA.MOVE_DRAGON_CLAW }, { "DRAGON CLAW", "DRAGONCLAW" }, {
  frames = 80,
  rom = "Move_DRAGON_CLAW @ 81D380C",
  fx = "dragon_claw",
  se = "SE_M_SACRED_FIRE2 / SE_M_RAZOR_WIND",
  seId = 150,
})

-- Move_SLAM @ 81C9309: slide + slam hit + push target
addScript({ MA.MOVE_SLAM }, { "SLAM" }, {
  frames = 36,
  rom = "Move_SLAM @ 81C9309",
  fx = "slam",
  se = "SE_M_COMET_PUNCH / SE_M_MEGA_KICK2",
  seId = 139,
})

-- Move_FACADE @ 81CC136: sweat drops + swagger loop (~72)
addScript({ MA.MOVE_FACADE }, { "FACADE" }, {
  frames = 72,
  rom = "Move_FACADE @ 81CC136",
  fx = "facade",
  se = "SE_M_SWAGGER",
  seId = 193,
})

-- Move_RETURN @ 81D3F36: mid-power dips + multi hits (generic mid path)
addScript({ MA.MOVE_RETURN }, { "RETURN" }, {
  frames = 70,
  rom = "Move_RETURN @ 81D3F36 (mid power)",
  fx = "return",
  se = "SE_M_TAIL_WHIP / SE_M_VITAL_THROW2",
  seId = 167,
})

-- Move_FRUSTRATION @ 81C9830: anger veins + multi splats (mid path)
addScript({ MA.MOVE_FRUSTRATION }, { "FRUSTRATION" }, {
  frames = 90,
  rom = "Move_FRUSTRATION @ 81C9830 (mid)",
  fx = "frustration",
  se = "SE_M_DRAGON_RAGE / SE_M_COMET_PUNCH",
  seId = 171,
})

-- Move_HIDDEN_POWER @ 81C8BBC: scale pulse + orb ring + scatter
addScript({ MA.MOVE_HIDDEN_POWER }, { "HIDDEN POWER", "HIDDENPOWER" }, {
  frames = 110,
  rom = "Move_HIDDEN_POWER @ 81C8BBC",
  fx = "hidden_power",
  se = "SE_M_TAKE_DOWN / SE_M_REVERSAL / SE_M_REFLECT",
  seId = 152,
})

-- Move_OVERHEAT @ 81D4AFC: red blend + ember burst outward
addScript({ MA.MOVE_OVERHEAT }, { "OVERHEAT" }, {
  frames = 100,
  rom = "Move_OVERHEAT @ 81D4AFC",
  fx = "overheat",
  se = "SE_M_DRAGON_RAGE / SE_M_FLAME_WHEEL2",
  seId = 171,
})

-- Move_ERUPTION @ 81CC74F: red tint + warm rocks rain + shake
addScript({ MA.MOVE_ERUPTION }, { "ERUPTION" }, {
  frames = 140,
  rom = "Move_ERUPTION @ 81CC74F",
  fx = "eruption",
  se = "SE_M_EXPLOSION / SE_M_ROCK_THROW",
  seId = 178,
})

-- Move_FOCUS_PUNCH @ 81D3E6F: compressed charge windup + multi fist (BG_IMPACT)
addScript({ MA.MOVE_FOCUS_PUNCH }, { "FOCUS PUNCH", "FOCUSPUNCH" }, {
  frames = 100,
  rom = "Move_FOCUS_PUNCH @ 81D3E6F (charge+hit compressed)",
  fx = "focus_punch",
  se = "SE_M_SWAGGER / SE_M_VITAL_THROW2 / SE_M_MEGA_KICK2",
  seId = 193,
})

-- Move_REVENGE @ 81D3B99: purple scratch + swipe + dual impact
addScript({ MA.MOVE_REVENGE }, { "REVENGE" }, {
  frames = 55,
  rom = "Move_REVENGE @ 81D3B99",
  fx = "revenge",
  se = "SE_M_TAKE_DOWN / SE_M_SWAGGER / SE_M_VITAL_THROW2",
  seId = 152,
})

-- Move_ENDEAVOR @ 81CC6DA: sweat + blend + dual hits
addScript({ MA.MOVE_ENDEAVOR }, { "ENDEAVOR" }, {
  frames = 50,
  rom = "Move_ENDEAVOR @ 81CC6DA",
  fx = "endeavor",
  se = "SE_M_TAIL_WHIP / SE_M_DOUBLE_SLAP / SE_M_COMET_PUNCH",
  seId = 167,
})

-- Move_FAKE_OUT @ 81D23A8: flatter flash + shake + white flash
addScript({ MA.MOVE_FAKE_OUT }, { "FAKE OUT", "FAKEOUT" }, {
  frames = 40,
  rom = "Move_FAKE_OUT @ 81D23A8",
  fx = "fake_out",
  se = "SE_M_FLATTER / SE_M_SKETCH",
  seId = 229,
})

-- Move_WILL_O_WISP @ 81D2B83: wisp orbs travel + fire ring on target
addScript({ MA.MOVE_WILL_O_WISP }, { "WILL-O-WISP", "WILL O WISP", "WILLOWISP" }, {
  frames = 90,
  rom = "Move_WILL_O_WISP @ 81D2B83",
  fx = "will_o_wisp",
  se = "SE_M_EMBER / SE_M_FLAME_WHEEL2",
  seId = 151,
})

-- Move_THUNDER_WAVE @ 81C89C0: fade + bolt + spark_h cascade
addScript({ MA.MOVE_THUNDER_WAVE }, { "THUNDER WAVE", "THUNDERWAVE" }, {
  frames = 70,
  rom = "Move_THUNDER_WAVE @ 81C89C0",
  fx = "thunder_wave",
  se = "SE_M_THUNDER_WAVE / SE_M_THUNDERBOLT2",
  seId = 138,
})

-- Move_ATTRACT @ 81CA0BA: sway + hearts toward target + float hearts
addScript({ MA.MOVE_ATTRACT }, { "ATTRACT" }, {
  frames = 120,
  rom = "Move_ATTRACT @ 81CA0BA",
  fx = "attract",
  se = "SE_M_CHARM / SE_M_ATTRACT",
  seId = 212,
})

-- Move_SAFEGUARD @ 81C9AF7: guard rings ×3 + shiny flash
addScript({ MA.MOVE_SAFEGUARD }, { "SAFEGUARD" }, {
  frames = 50,
  rom = "Move_SAFEGUARD @ 81C9AF7",
  fx = "safeguard",
  se = "SE_M_MILK_DRINK",
  seId = 225,
})

-- Move_LIGHT_SCREEN @ 81CE47A: green wall + sparkles
addScript({ MA.MOVE_LIGHT_SCREEN }, { "LIGHT SCREEN", "LIGHTSCREEN" }, {
  frames = 70,
  rom = "Move_LIGHT_SCREEN @ 81CE47A",
  fx = "light_screen",
  se = "SE_M_REFLECT",
  seId = 207,
})

-- Move_REFLECT @ 81CE52C: blue wall + sparkles
addScript({ MA.MOVE_REFLECT }, { "REFLECT" }, {
  frames = 70,
  rom = "Move_REFLECT @ 81CE52C",
  fx = "reflect",
  se = "SE_M_REFLECT",
  seId = 207,
})

-- Move_SPIKES @ 81CFD55: 3 spikes travel delay 10
addScript({ MA.MOVE_SPIKES }, { "SPIKES" }, {
  frames = 70,
  rom = "Move_SPIKES @ 81CFD55",
  fx = "spikes",
  se = "SE_M_JUMP_KICK / SE_M_HORN_ATTACK",
  seId = 143,
})


-- ===== Wave-4 two-turn / charge / high-value scripts (ROM-read) =====

-- Move_SOLAR_BEAM @ 81CED65: charge orbs absorb; hit green beam
addScript({ MA.MOVE_SOLAR_BEAM }, { "SOLARBEAM", "SOLAR BEAM" }, {
  frames = 90,
  chargeFrames = 50,
  rom = "Move_SOLAR_BEAM @ 81CED65 choosetwoturnanim",
  fx = "solar_beam_hit",
  chargeFx = "solar_beam_charge",
  se = "SE_M_SOLAR_BEAM / SE_M_MEGA_KICK",
  seId = 201,
  chargeSeId = 140,
})

-- Move_FLY @ 81D046F: rise shadow; dive hit
addScript({ MA.MOVE_FLY }, { "FLY" }, {
  frames = 40,
  chargeFrames = 30,
  rom = "Move_FLY @ 81D046F choosetwoturnanim",
  fx = "fly_hit",
  chargeFx = "fly_charge",
  se = "SE_M_RAZOR_WIND / SE_M_FLY / SE_M_DOUBLE_TEAM",
  seId = 136,
  chargeSeId = 158,
})

-- Move_DIVE @ 81D49A5: sink splash; emerge water impact
addScript({ MA.MOVE_DIVE }, { "DIVE" }, {
  frames = 55,
  chargeFrames = 45,
  rom = "Move_DIVE @ 81D49A5 choosetwoturnanim",
  fx = "dive_hit",
  chargeFx = "dive_charge",
  se = "SE_M_EXPLOSION / SE_M_DIVE / SE_M_HEADBUTT",
  seId = 178,
  chargeSeId = 233,
})

-- Move_SKULL_BASH @ 81CB38F: tuck bob; ram impact
addScript({ MA.MOVE_SKULL_BASH }, { "SKULL BASH", "SKULLBASH" }, {
  frames = 55,
  chargeFrames = 48,
  rom = "Move_SKULL_BASH @ 81CB38F choosetwoturnanim",
  fx = "skull_bash_hit",
  chargeFx = "skull_bash_charge",
  se = "SE_M_TAKE_DOWN / SE_M_MEGA_KICK2",
  seId = 152,
  chargeSeId = 152,
})

-- Move_SOFT_BOILED @ 81D213B / Move_RECOVER @ 81D1F1F: orb gather + blue stars
addScript({ MA.MOVE_SOFT_BOILED, MA.MOVE_RECOVER }, { "SOFTBOILED", "SOFT-BOILED", "SOFT BOILED", "RECOVER" }, {
  frames = 70,
  rom = "Move_RECOVER @ 81D1F1F / Move_SOFT_BOILED @ 81D213B",
  fx = "recover",
  se = "SE_M_MEGA_KICK / SE_M_MILK_DRINK",
  seId = 140,
})

-- Move_SWORDS_DANCE @ 81C8EA4: sword spin + elliptical sway
addScript({ MA.MOVE_SWORDS_DANCE }, { "SWORDS DANCE", "SWORDSDANCE" }, {
  frames = 50,
  rom = "Move_SWORDS_DANCE @ 81C8EA4",
  fx = "swords_dance",
  se = "SE_M_SWORDS_DANCE",
  seId = 191,
})

-- Move_DRAGON_DANCE @ 81CD7F8: hollow orbs ring + teleport SE
addScript({ MA.MOVE_DRAGON_DANCE }, { "DRAGON DANCE", "DRAGONDANCE" }, {
  frames = 70,
  rom = "Move_DRAGON_DANCE @ 81CD7F8",
  fx = "dragon_dance",
  se = "SE_M_TELEPORT",
  seId = 203,
})

-- Move_RAIN_DANCE @ 81CE997: darken + rain drops ~150f compressed
addScript({ MA.MOVE_RAIN_DANCE }, { "RAIN DANCE", "RAINDANCE" }, {
  frames = 80,
  rom = "Move_RAIN_DANCE @ 81CE997",
  fx = "rain_dance",
  se = "SE_M_RAIN_DANCE",
  seId = 127,
})

-- Move_SUNNY_DAY @ 81D0B91: brighten + sunlight rays
addScript({ MA.MOVE_SUNNY_DAY }, { "SUNNY DAY", "SUNNYDAY" }, {
  frames = 70,
  rom = "Move_SUNNY_DAY @ 81D0B91",
  fx = "sunny_day",
  se = "SE_M_PETAL_DANCE",
  seId = 202,
})

-- Move_SANDSTORM @ 81D0304: sand whip overlay
addScript({ MA.MOVE_SANDSTORM }, { "SANDSTORM" }, {
  frames = 70,
  rom = "Move_SANDSTORM @ 81D0304",
  fx = "sandstorm_move",
  se = "SE_M_SANDSTORM",
  seId = 219,
})

-- Move_HAIL @ 81CC076: hail crystals rain
addScript({ MA.MOVE_HAIL }, { "HAIL" }, {
  frames = 70,
  rom = "Move_HAIL @ 81CC076",
  fx = "hail_move",
  se = "SE_M_HAIL",
  seId = 242,
})

-- Move_RAPID_SPIN @ 81CBD41: spin dust + hit
addScript({ MA.MOVE_RAPID_SPIN }, { "RAPID SPIN", "RAPIDSPIN" }, {
  frames = 55,
  rom = "Move_RAPID_SPIN @ 81CBD41",
  fx = "rapid_spin",
  se = "SE_M_RAZOR_WIND2 / SE_M_DOUBLE_SLAP",
  seId = 160,
})

-- Move_EXPLOSION @ 81C9675 / Move_SELF_DESTRUCT @ 81C9219
addScript({ MA.MOVE_EXPLOSION, MA.MOVE_SELF_DESTRUCT }, { "EXPLOSION", "SELFDESTRUCT", "SELF-DESTRUCT", "SELF DESTRUCT" }, {
  frames = 90,
  rom = "Move_EXPLOSION @ 81C9675 / Move_SELF_DESTRUCT @ 81C9219",
  fx = "explosion",
  se = "SE_M_EXPLOSION / SE_M_SELF_DESTRUCT",
  seId = 178,
  -- after settle, 5x playse SE_M_EXPLOSION delay 6
  seChain = {
    { f = 22, id = 178 },
    { f = 28, id = 178 },
    { f = 34, id = 178 },
    { f = 40, id = 178 },
    { f = 46, id = 178 },
  },
})

-- Move_DESTINY_BOND @ 81CBA2C: ghost BG + shadow link
addScript({ MA.MOVE_DESTINY_BOND }, { "DESTINY BOND", "DESTINYBOND" }, {
  frames = 80,
  rom = "Move_DESTINY_BOND @ 81CBA2C",
  fx = "destiny_bond",
  se = "SE_M_PSYBEAM / SE_M_NIGHTMARE",
  seId = 189,
})

-- Move_COUNTER @ 81D08AC / Move_MIRROR_COAT @ 81CE506: retaliate flash + splat
addScript({ MA.MOVE_COUNTER }, { "COUNTER" }, {
  frames = 40,
  rom = "Move_COUNTER @ 81D08AC",
  fx = "counter",
  se = "SE_M_VITAL_THROW2",
  seId = 123,
})
addScript({ MA.MOVE_MIRROR_COAT }, { "MIRROR COAT", "MIRRORCOAT" }, {
  frames = 45,
  rom = "Move_MIRROR_COAT @ 81CE506",
  fx = "mirror_coat",
  se = "SE_M_BARRIER / SE_M_VITAL_THROW2",
  seId = 208,
})

-- Move_METRONOME @ 81CB365: finger + thought bubble (generic)
addScript({ MA.MOVE_METRONOME }, { "METRONOME" }, {
  frames = 40,
  rom = "Move_METRONOME @ 81CB365",
  fx = "metronome",
  se = "SE_M_METRONOME",
  seId = 186,
})

-- Move_SPLASH @ 81CB720: bounce
addScript({ MA.MOVE_SPLASH }, { "SPLASH" }, {
  frames = 50,
  rom = "Move_SPLASH @ 81CB720",
  fx = "splash",
  se = "SE_M_TAIL_WHIP",
  seId = 167,
})

-- Move_STRUGGLE @ 81CB815: thrash hits
addScript({ MA.MOVE_STRUGGLE }, { "STRUGGLE" }, {
  frames = 40,
  rom = "Move_STRUGGLE @ 81CB815",
  fx = "struggle",
  se = "SE_M_COMET_PUNCH",
  seId = 139,
})

-- Move_TRANSFORM @ 81D3054: white wash morph (approx)
addScript({ MA.MOVE_TRANSFORM }, { "TRANSFORM" }, {
  frames = 50,
  rom = "Move_TRANSFORM @ 81D3054",
  fx = "transform",
  se = "SE_M_TELEPORT",
  seId = 203,
})


-- ===== Wave-5 two-turn peers + high-traffic missing (ROM-read) =====

-- Move_SKY_ATTACK @ 81CB57B: glow charge; bird dive + impact
addScript({ MA.MOVE_SKY_ATTACK }, { "SKY ATTACK", "SKYATTACK" }, {
  frames = 55,
  chargeFrames = 55,
  rom = "Move_SKY_ATTACK @ 81CB57B choosetwoturnanim",
  fx = "sky_attack_hit",
  chargeFx = "sky_attack_charge",
  se = "SE_M_VITAL_THROW2 / SE_M_STAT_INCREASE",
  seId = 123,
  chargeSeId = 239,
})

-- Move_BOUNCE @ 81D04D9: rise shadow; drop hit (EFFECT_FLY peer)
addScript({ MA.MOVE_BOUNCE }, { "BOUNCE" }, {
  frames = 40,
  chargeFrames = 30,
  rom = "Move_BOUNCE @ 81D04D9 choosetwoturnanim",
  fx = "bounce_hit",
  chargeFx = "bounce_charge",
  se = "SE_M_MEGA_KICK2 / SE_M_TELEPORT / SE_M_SWAGGER",
  seId = 141,
  chargeSeId = 203,
})

-- Move_RAZOR_WIND @ 81D1E0B: gust charge; air-wave blades
addScript({ MA.MOVE_RAZOR_WIND }, { "RAZOR WIND", "RAZORWIND" }, {
  frames = 45,
  chargeFrames = 40,
  rom = "Move_RAZOR_WIND @ 81D1E0B choosetwoturnanim",
  fx = "razor_wind_hit",
  chargeFx = "razor_wind_charge",
  se = "SE_M_RAZOR_WIND / SE_M_GUST",
  seId = 136,
  chargeSeId = 132,
})

-- Move_TRI_ATTACK @ 81D2A0F: triangle + fire/bolt/ice burst
addScript({ MA.MOVE_TRI_ATTACK }, { "TRI ATTACK", "TRIATTACK" }, {
  frames = 85,
  rom = "Move_TRI_ATTACK @ 81D2A0F",
  fx = "tri_attack",
  se = "SE_M_TRI_ATTACK / SE_M_TRI_ATTACK2",
  seId = 220,
})

-- Move_SUPERPOWER @ 81CC3A3: power-up then slam
addScript({ MA.MOVE_SUPERPOWER }, { "SUPERPOWER" }, {
  frames = 60,
  rom = "Move_SUPERPOWER @ 81CC3A3",
  fx = "superpower",
  se = "SE_M_MEGA_KICK / SE_M_VITAL_THROW2",
  seId = 140,
})

-- Move_IRON_TAIL @ 81D18B6: metal sheen + tail slam
addScript({ MA.MOVE_IRON_TAIL }, { "IRON TAIL", "IRONTAIL" }, {
  frames = 50,
  rom = "Move_IRON_TAIL @ 81D18B6",
  fx = "iron_tail",
  se = "SE_M_VITAL_THROW2 / SE_M_TAKE_DOWN",
  seId = 123,
})

-- Move_CRABHAMMER @ 81D0155: water chop
addScript({ MA.MOVE_CRABHAMMER }, { "CRABHAMMER", "CRAB HAMMER" }, {
  frames = 50,
  rom = "Move_CRABHAMMER @ 81D0159",
  fx = "crabhammer",
  se = "SE_M_VITAL_THROW2 / SE_M_MEGA_KICK2",
  seId = 123,
})

-- Move_DYNAMIC_PUNCH @ 81D07E4: fist + confuse stars
addScript({ MA.MOVE_DYNAMIC_PUNCH }, { "DYNAMIC PUNCH", "DYNAMICPUNCH" }, {
  frames = 55,
  rom = "Move_DYNAMIC_PUNCH @ 81D07E4",
  fx = "dynamic_punch",
  se = "SE_M_COMET_PUNCH / SE_M_MEGA_KICK",
  seId = 139,
})

-- Move_CROSS_CHOP @ 81D058E: crossed hands + X impact
addScript({ MA.MOVE_CROSS_CHOP }, { "CROSS CHOP", "CROSSCHOP" }, {
  frames = 55,
  rom = "Move_CROSS_CHOP @ 81D058E",
  fx = "cross_chop",
  se = "SE_M_MEGA_KICK / SE_M_RAZOR_WIND",
  seId = 140,
})

-- Move_MEGAHORN @ 81CFDAC: horn charge
addScript({ MA.MOVE_MEGAHORN }, { "MEGAHORN" }, {
  frames = 50,
  rom = "Move_MEGAHORN @ 81CFDAC",
  fx = "megahorn",
  se = "SE_M_HORN_ATTACK / SE_M_TAKE_DOWN",
  seId = 166,
})

-- Move_EXTREME_SPEED @ 81CBE3E: speed dust dashes
addScript({ MA.MOVE_EXTREME_SPEED }, { "EXTREMESPEED", "EXTREME SPEED", "EXTREME-SPEED" }, {
  frames = 55,
  rom = "Move_EXTREME_SPEED @ 81CBE3E",
  fx = "extremespeed",
  se = "SE_M_RAZOR_WIND2 / SE_M_COMET_PUNCH",
  seId = 160,
})

-- Move_ANCIENT_POWER @ 81D0EE5: rising rocks
addScript({ MA.MOVE_ANCIENT_POWER }, { "ANCIENT POWER", "ANCIENTPOWER" }, {
  frames = 60,
  rom = "Move_ANCIENT_POWER @ 81D0EE5",
  fx = "ancient_power",
  se = "SE_M_TAKE_DOWN / SE_M_ROCK_THROW",
  seId = 152,
})

-- Move_FUTURE_SIGHT @ 81CDD2D: psychic rings / delay mark
addScript({ MA.MOVE_FUTURE_SIGHT }, { "FUTURE SIGHT", "FUTURESIGHT" }, {
  frames = 70,
  rom = "Move_FUTURE_SIGHT @ 81CDD2D",
  fx = "future_sight",
  se = "SE_M_PSYBEAM / SE_M_DETECT",
  seId = 189,
})

-- Move_WISH @ 81D2D66: falling star
addScript({ MA.MOVE_WISH }, { "WISH" }, {
  frames = 70,
  rom = "Move_WISH @ 81D2D66",
  fx = "wish",
  se = "SE_M_MILK_DRINK / SE_M_MORNING_SUN",
  seId = 225,
})

-- Move_INGRAIN @ 81D255A: roots plant
addScript({ MA.MOVE_INGRAIN }, { "INGRAIN" }, {
  frames = 55,
  rom = "Move_INGRAIN @ 81D255A",
  fx = "ingrain",
  se = "SE_M_TAKE_DOWN",
  seId = 152,
})

-- Move_HELPING_HAND @ 81CC2BF: hands sparkle on partner/self
addScript({ MA.MOVE_HELPING_HAND }, { "HELPING HAND", "HELPINGHAND" }, {
  frames = 45,
  rom = "Move_HELPING_HAND @ 81CC2BF",
  fx = "helping_hand",
  se = "SE_M_SWAGGER / SE_M_DETECT",
  seId = 193,
})

-- Move_FOLLOW_ME @ 81CC1B1: finger / attention
addScript({ MA.MOVE_FOLLOW_ME }, { "FOLLOW ME", "FOLLOWME" }, {
  frames = 40,
  rom = "Move_FOLLOW_ME @ 81CC1B1",
  fx = "follow_me",
  se = "SE_M_ATTRACT",
  seId = 226,
})

-- Move_YAWN @ 81CC697: sleep Z / bubble
addScript({ MA.MOVE_YAWN }, { "YAWN" }, {
  frames = 55,
  rom = "Move_YAWN @ 81CC697",
  fx = "yawn",
  se = "SE_M_YAWN",
  seId = 237,
})

-- Move_SLACK_OFF @ 81CCF23 / Move_REFRESH @ 81D3485: heal sparkles
addScript({ MA.MOVE_SLACK_OFF, MA.MOVE_REFRESH }, { "SLACK OFF", "SLACKOFF", "REFRESH" }, {
  frames = 60,
  rom = "Move_SLACK_OFF @ 81CCF23 / Move_REFRESH @ 81D3485",
  fx = "slack_off",
  se = "SE_M_MEGA_KICK / SE_M_MILK_DRINK",
  seId = 140,
})

-- Move_ARM_THRUST @ 81D36CF: multi palm hits
addScript({ MA.MOVE_ARM_THRUST }, { "ARM THRUST", "ARMTHRUST" }, {
  frames = 55,
  rom = "Move_ARM_THRUST @ 81D36CF",
  fx = "arm_thrust",
  se = "SE_M_COMET_PUNCH / SE_M_VITAL_THROW2",
  seId = 139,
})

-- Move_SMELLING_SALT @ 81CC156: clap wake
addScript({ MA.MOVE_SMELLING_SALT }, { "SMELLING SALT", "SMELLINGSALT", "SMELLING_SALT" }, {
  frames = 45,
  rom = "Move_SMELLING_SALT @ 81CC156",
  fx = "smelling_salt",
  se = "SE_M_VITAL_THROW2 / SE_M_COMET_PUNCH",
  seId = 123,
})

-- Move_DOUBLE_EDGE @ 81C817A / Move_SUBMISSION @ 81D0AEE: recoil slam
addScript({ MA.MOVE_DOUBLE_EDGE, MA.MOVE_SUBMISSION }, { "DOUBLE EDGE", "DOUBLE-EDGE", "DOUBLEEDGE", "SUBMISSION" }, {
  frames = 55,
  rom = "Move_DOUBLE_EDGE @ 81C817A / Move_SUBMISSION @ 81D0AEE",
  fx = "double_edge",
  se = "SE_M_TAKE_DOWN / SE_M_VITAL_THROW2",
  seId = 152,
})

-- Move_TRICK @ 81D2CE8: item bag swap flash
addScript({ MA.MOVE_TRICK }, { "TRICK" }, {
  frames = 50,
  rom = "Move_TRICK @ 81D2CE8",
  fx = "trick",
  se = "SE_M_SKETCH / SE_M_DETECT",
  seId = 205,
})

-- Move_IMPRISON @ 81CC867: seal rings
addScript({ MA.MOVE_IMPRISON }, { "IMPRISON" }, {
  frames = 50,
  rom = "Move_IMPRISON @ 81CC867",
  fx = "imprison",
  se = "SE_M_DETECT / SE_M_PSYBEAM",
  seId = 209,
})

-- Move_GRUDGE @ 81CC8AA: ghost flames
addScript({ MA.MOVE_GRUDGE }, { "GRUDGE" }, {
  frames = 55,
  rom = "Move_GRUDGE @ 81CC8AA",
  fx = "grudge",
  se = "SE_M_PSYBEAM / SE_M_NIGHTMARE",
  seId = 189,
})

-- Move_SNATCH @ 81D498B: hand snatch
addScript({ MA.MOVE_SNATCH }, { "SNATCH" }, {
  frames = 40,
  rom = "Move_SNATCH @ 81D498B",
  fx = "snatch",
  se = "SE_M_SWAGGER / SE_M_DOUBLE_TEAM",
  seId = 193,
})

-- Move_SKILL_SWAP / ROLE_PLAY / CAMOUFLAGE / RECYCLE / ASSIST: self FX family
addScript({ MA.MOVE_SKILL_SWAP }, { "SKILL SWAP", "SKILLSWAP" }, {
  frames = 50,
  rom = "Move_SKILL_SWAP @ 81CC81C",
  fx = "skill_swap",
  se = "SE_M_TELEPORT / SE_M_PSYBEAM",
  seId = 203,
})
addScript({ MA.MOVE_ROLE_PLAY }, { "ROLE PLAY", "ROLEPLAY" }, {
  frames = 50,
  rom = "Move_ROLE_PLAY @ 81D3428",
  fx = "role_play",
  se = "SE_M_TELEPORT",
  seId = 203,
})
addScript({ MA.MOVE_CAMOUFLAGE }, { "CAMOUFLAGE" }, {
  frames = 45,
  rom = "Move_CAMOUFLAGE @ 81CC8D2",
  fx = "camouflage",
  se = "SE_M_DETECT",
  seId = 209,
})
addScript({ MA.MOVE_RECYCLE }, { "RECYCLE" }, {
  frames = 45,
  rom = "Move_RECYCLE @ 81CC45E",
  fx = "recycle",
  se = "SE_M_SWAGGER",
  seId = 193,
})
addScript({ MA.MOVE_ASSIST }, { "ASSIST" }, {
  frames = 40,
  rom = "Move_ASSIST @ 81CC332",
  fx = "assist",
  se = "SE_M_ATTRACT",
  seId = 226,
})


-- Dig true two-turn visual: dig-down hide + emerge (same fx; longer)
-- Move_DIG @ 81CB0A1 choosetwoturnanim dig-down / emerge

---------------------------------------------------------------------------
-- Resolve / arm
---------------------------------------------------------------------------

function MA.normalizeName(name)
  if type(name) ~= "string" then return "" end
  local n = name:upper():gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
  n = n:gsub("%s+", " ")
  return n
end

function MA.resolve(move)
  if type(move) ~= "table" then return nil end
  local id = tonumber(move.id)
  if id and SCRIPTS_BY_ID[id] then return SCRIPTS_BY_ID[id] end
  local n = MA.normalizeName(move.name)
  if n ~= "" and SCRIPTS_BY_NAME[n] then return SCRIPTS_BY_NAME[n] end
  -- Compact form: "WATERGUN"
  local compact = n:gsub("%s+", "")
  if compact ~= "" and SCRIPTS_BY_NAME[compact] then return SCRIPTS_BY_NAME[compact] end
  return nil
end

function MA.listImplemented()
  local out = {}
  local seen = {}
  for name, spec in pairs(SCRIPTS_BY_NAME) do
    if not seen[spec] then
      seen[spec] = true
      out[#out + 1] = { name = name, frames = spec.frames, rom = spec.rom, fx = spec.fx, se = spec.se }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function battlerCenters(self, onEnemy)
  local BCX = (self and self._moveAnimBattlerCX) or { player = 72, enemy = 176 }
  local BCY = (self and self._moveAnimBattlerCY) or { player = 80, enemy = 40 }
  if onEnemy then
    return BCX.player or 72, BCY.player or 80, BCX.enemy or 176, BCY.enemy or 40
  end
  return BCX.enemy or 176, BCY.enemy or 40, BCX.player or 72, BCY.player or 80
end

---------------------------------------------------------------------------
-- Drawing helpers (procedural + optional sheet tint)
---------------------------------------------------------------------------

-- Peak mul for sheet pixels: many pokeruby anim OAMs use OBJ blend
-- (semi-transparent). Without this, keyed sprites still look chalk-solid.
local SHEET_OBJ_ALPHA = 0.72

local function drawTinted(img, x, y, scale, r, g, b, a)
  local G = love.graphics
  if not img then return false end
  scale = scale or 1
  local w = (img.getWidth and img:getWidth()) or 16
  local h = (img.getHeight and img:getHeight()) or 16
  -- Many sheets are multi-frame; draw first cell ~16x16 when larger.
  local cw = math.min(32, w)
  local ch = math.min(32, h)
  local aa = clamp01((a or 1) * SHEET_OBJ_ALPHA)
  G.setColor(r, g, b, aa)
  if G.draw then
    local ok = pcall(function()
      if w > 40 and love.graphics.newQuad then
        local q = love.graphics.newQuad(0, 0, cw, ch, w, h)
        G.draw(img, q, x - cw * scale * 0.5, y - ch * scale * 0.5, 0, scale, scale)
      else
        G.draw(img, x - w * scale * 0.5, y - h * scale * 0.5, 0, scale, scale)
      end
    end)
    return ok
  end
  return false
end

local function circle(G, x, y, rad, mode)
  if G.circle then G.circle(mode or "fill", x, y, rad)
  else G.rectangle(mode or "fill", x - rad, y - rad, rad * 2, rad * 2) end
end

local function hitSplat(G, x, y, t, fade, useSheet)
  -- t in 0..1 over splat life
  local a = fade * (1 - t * 0.85)
  local s = 0.7 + t * 1.4
  if useSheet then
    local img = loadTagImage(MA.TAG.IMPACT)
    if img and drawTinted(img, x, y, s * 0.9, 1, 1, 1, a) then return end
  end
  G.setColor(1, 1, 1, a)
  local r = 4 + t * 10
  circle(G, x, y, r)
  G.setColor(0.95, 0.35, 0.25, a * 0.9)
  G.rectangle("fill", x - r - 1, y - 1, r * 2 + 2, 3)
  G.rectangle("fill", x - 1, y - r - 1, 3, r * 2 + 2)
end

local function scratchMarks(G, x, y, t, fade, onEnemy)
  local a = fade * (1 - t)
  local img = loadTagImage(MA.TAG.SCRATCH)
  if img and drawTinted(img, x, y, 1.1, 1, 1, 1, a) then return end
  G.setColor(0.95, 0.95, 0.98, a)
  local dir = onEnemy and 1 or -1
  for i = 0, 2 do
    local ox = (i - 1) * 5
    local x0 = x - 14 * dir + ox
    local y0 = y - 12 + i * 3
    local x1 = x + 10 * dir + ox
    local y1 = y + 14 + i * 2
    local u = clamp01(t * 1.6)
    local px = x0 + (x1 - x0) * u
    local py = y0 + (y1 - y0) * u
    G.rectangle("fill", px - 1, py - 6, 2, 12)
  end
end

local function lerp(a, b, u) return a + (b - a) * u end

---------------------------------------------------------------------------
-- Per-FX drawers. frame is 0-indexed integer; ctx has ax,ay,tx,ty,onEnemy,fade
---------------------------------------------------------------------------

local FX = {}

function FX.pound(G, frame, ctx)
  local life = 10
  if frame < life then
    hitSplat(G, ctx.tx, ctx.ty, frame / life, ctx.fade, true)
  end
end

function FX.tackle(G, frame, ctx)
  -- Lunge toward target for first 6f (delay 6 before splat in ROM)
  if frame >= 6 and frame < 18 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 6) / 10, ctx.fade, true)
  end
end

function FX.scratch(G, frame, ctx)
  if frame < 14 then
    scratchMarks(G, ctx.tx, ctx.ty, frame / 14, ctx.fade, ctx.onEnemy)
  end
end

function FX.ember(G, frame, ctx)
  local launches = { 0, 4, 8 }
  for i = 1, #launches do
    local start = launches[i]
    local age = frame - start
    if age >= 0 and age <= 20 then
      local u = age / 20
      local side = (i - 2) * 16
      local x = lerp(ctx.ax, ctx.tx + side, u)
      local y = lerp(ctx.ay, ctx.ty, u) - math.sin(u * math.pi) * 18
      local img = loadTagImage(MA.TAG.SMALL_EMBER)
      local a = ctx.fade * (1 - u * 0.3)
      if not (img and drawTinted(img, x, y, 0.85, 1, 0.55, 0.15, a)) then
        G.setColor(1, 0.45, 0.12, a)
        circle(G, x, y, 3 + (1 - u) * 2)
        G.setColor(1, 0.85, 0.3, a * 0.8)
        circle(G, x, y, 1.5)
      end
    end
  end
  -- Flares after delay 16 from last ember (~frame 24)
  if frame >= 24 then
    for i = 0, 2 do
      local start = 24 + i * 4
      local age = frame - start
      if age >= 0 and age < 16 then
        local ang = -0.6 + i * 0.6
        local u = age / 16
        local x = ctx.tx + math.cos(ang) * (8 + u * 22)
        local y = ctx.ty + math.sin(ang) * (8 + u * 18) - u * 10
        G.setColor(1, 0.35 + i * 0.1, 0.08, ctx.fade * (1 - u))
        circle(G, x, y, 4 - u * 2)
      end
    end
  end
end

function FX.water_gun(G, frame, ctx)
  -- Main bubble stream ~40f
  if frame <= 40 then
    local u = frame / 40
    local x = lerp(ctx.ax + 12, ctx.tx, u)
    local y = lerp(ctx.ay - 4, ctx.ty, u)
    local img = loadTagImage(MA.TAG.SMALL_BUBBLES)
    local a = ctx.fade
    if not (img and drawTinted(img, x, y, 1.0, 0.55, 0.8, 1, a)) then
      G.setColor(0.45, 0.75, 1, a)
      circle(G, x, y, 5)
      G.setColor(0.85, 0.95, 1, a * 0.7)
      circle(G, x - 1, y - 1, 2)
    end
  end
  if frame >= 40 then
    local img = loadTagImage(MA.TAG.WATER_IMPACT)
    local t = (frame - 40) / 20
    if t < 1 then
      if not (img and drawTinted(img, ctx.tx, ctx.ty, 1.0, 0.6, 0.85, 1, ctx.fade * (1 - t))) then
        G.setColor(0.4, 0.7, 1, ctx.fade * (1 - t))
        circle(G, ctx.tx, ctx.ty, 6 + t * 10)
      end
    end
    local drops = { { 0, -15, 0 }, { 15, -20, 10 }, { -15, -10, 20 } }
    for i = 1, #drops do
      local d = drops[i]
      local age = frame - (40 + d[3])
      if age >= 0 and age < 18 then
        local u = age / 18
        local x = ctx.tx + d[1]
        local y = ctx.ty + d[2] + u * 28
        G.setColor(0.5, 0.8, 1, ctx.fade * (1 - u))
        circle(G, x, y, 3)
      end
    end
  end
end

function FX.vine_whip(G, frame, ctx)
  if frame >= 6 and frame < 18 then
    local t = (frame - 6) / 12
    local img = loadTagImage(MA.TAG.WHIP_HIT)
    local a = ctx.fade * (1 - t * 0.5)
    if not (img and drawTinted(img, ctx.tx, ctx.ty, 1.0, 0.35, 0.85, 0.3, a)) then
      G.setColor(0.3, 0.8, 0.25, a)
      local dir = ctx.onEnemy and 1 or -1
      for i = 0, 2 do
        local y = ctx.ty - 10 + i * 8
        G.rectangle("fill", ctx.tx - 16 * dir, y, 28 * dir, 2)
      end
    end
  end
end

function FX.absorb(G, frame, ctx)
  if frame < 8 then
    hitSplat(G, ctx.tx, ctx.ty, frame / 8, ctx.fade, true)
  end
  -- Orbs from target → attacker (gBattleAnimSpriteTemplate_83D637C stream)
  if frame >= 10 and frame < 60 then
    local orbStarts = { 0, 4, 8, 12, 16, 20, 24, 28 }
    for i = 1, #orbStarts do
      local start = 10 + orbStarts[i]
      local age = frame - start
      if age >= 0 and age <= 26 then
        local u = age / 26
        local side = ((i % 3) - 1) * 10
        local x = lerp(ctx.tx + side, ctx.ax, u)
        local y = lerp(ctx.ty, ctx.ay, u)
        local img = loadTagImage(MA.TAG.ORBS)
        local a = ctx.fade * (0.4 + 0.6 * (1 - u))
        if not (img and drawTinted(img, x, y, 0.7, 0.4, 0.95, 0.35, a)) then
          G.setColor(0.35, 0.9, 0.35, a)
          circle(G, x, y, 2.5)
        end
      end
    end
  end
  -- Heal stars near attacker late
  if frame >= 62 and frame < 86 then
    local t = (frame - 62) / 24
    local img = loadTagImage(MA.TAG.BLUE_STAR)
    for i = 0, 2 do
      local ang = i * 2.1 + t * 3
      local x = ctx.ax + math.cos(ang) * (10 + t * 8)
      local y = ctx.ay - 8 - t * 12 + math.sin(ang) * 4
      local a = ctx.fade * (1 - t)
      if not (img and drawTinted(img, x, y, 0.6, 0.55, 0.85, 1, a)) then
        G.setColor(0.7, 0.95, 1, a)
        circle(G, x, y, 2)
      end
    end
  end
  -- Soft green wash
  if frame < 20 or frame > 70 then
    local a = ctx.fade * 0.12
    G.setColor(0.4, 0.95, 0.4, a)
    circle(G, ctx.tx, ctx.ty, 28)
  end
end

function FX.thunder_shock(G, frame, ctx)
  -- Screen darken early (sub_80E2A38 blend to 6)
  if frame < 16 then
    G.setColor(0, 0, 0, ctx.fade * 0.25 * (frame / 16))
    G.rectangle("fill", 0, 0, 240, 160)
  elseif frame < 40 then
    G.setColor(0, 0, 0, ctx.fade * 0.25 * (1 - (frame - 16) / 40))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  -- Bolt from above (~frame 10–20)
  if frame >= 10 and frame < 28 then
    local t = (frame - 10) / 18
    G.setColor(1, 1, 0.55, ctx.fade * (1 - t * 0.5))
    local x = ctx.tx
    G.rectangle("fill", x - 1, 0, 3, ctx.ty)
    G.setColor(1, 1, 0.9, ctx.fade)
    G.rectangle("fill", x - 3, ctx.ty - 8, 7, 4)
  end
  -- Flash white on target
  if frame >= 18 and frame < 32 then
    local a = ctx.fade * (1 - math.abs(frame - 24) / 8) * 0.55
    G.setColor(1, 1, 0.7, a)
    circle(G, ctx.tx, ctx.ty, 18)
  end
  -- ElectricityEffect ~frame 52–68 (8 sparks × delay 2)
  if frame >= 52 and frame < 78 then
    local sparks = {
      { 5, 0 }, { -5, 10 }, { 15, 20 }, { -15, -10 },
      { 25, 0 }, { -8, 8 }, { 2, -8 }, { -20, 15 },
    }
    local img = loadTagImage(MA.TAG.SPARK)
    for i = 1, #sparks do
      local start = 52 + (i - 1) * 2
      local age = frame - start
      if age >= 0 and age < 10 then
        local x = ctx.tx + sparks[i][1]
        local y = ctx.ty + sparks[i][2]
        local a = ctx.fade * (1 - age / 10)
        if not (img and drawTinted(img, x, y, 0.7, 1, 1, 0.4, a)) then
          G.setColor(1, 0.95, 0.35, a)
          G.rectangle("fill", x - 1, y - 4, 2, 8)
          G.rectangle("fill", x - 4, y - 1, 8, 2)
        end
      end
    end
  end
end

function FX.quick_attack(G, frame, ctx)
  -- Afterimage streak toward target
  if frame < 10 then
    local u = frame / 10
    for i = 0, 3 do
      local uu = clamp01(u - i * 0.08)
      local x = lerp(ctx.ax, ctx.tx, uu)
      local y = lerp(ctx.ay, ctx.ty, uu)
      G.setColor(0.85, 0.85, 0.9, ctx.fade * (0.35 - i * 0.07))
      circle(G, x, y, 6 - i)
    end
  end
  if frame >= 4 and frame < 20 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 4) / 14, ctx.fade, true)
  end
end

function FX.growl(G, frame, ctx)
  -- Noise lines from attacker (two bursts at 0 and 15)
  local bursts = { 0, 15 }
  local img = loadTagImage(MA.TAG.NOISE_LINE)
  for bi = 1, #bursts do
    local start = bursts[bi]
    local age = frame - start
    if age >= 0 and age < 18 then
      local t = age / 18
      for i = 0, 2 do
        local yoff = (i - 1) * 8
        local x = ctx.ax + (ctx.onEnemy and 1 or -1) * (18 + t * 28)
        local y = ctx.ay + yoff
        local a = ctx.fade * (1 - t)
        if not (img and drawTinted(img, x, y, 0.8, 1, 1, 1, a)) then
          G.setColor(0.95, 0.95, 0.7, a)
          local dir = ctx.onEnemy and 1 or -1
          if G.polygon then
            G.polygon("fill",
              ctx.ax + 10 * dir, ctx.ay + yoff - 3,
              x, y,
              ctx.ax + 10 * dir, ctx.ay + yoff + 3)
          else
            G.rectangle("fill", ctx.ax, ctx.ay + yoff - 1, (x - ctx.ax), 2)
          end
        end
      end
    end
  end
end

function FX.tail_whip(G, frame, ctx)
  -- Elliptical sway is applied via offsets; draw a soft dust arc
  local t = frame / 48
  local a = ctx.fade * 0.45 * math.sin(t * math.pi)
  G.setColor(0.9, 0.85, 0.6, a)
  local dir = ctx.onEnemy and 1 or -1
  circle(G, ctx.ax + dir * 12, ctx.ay + 10, 3)
end


---------------------------------------------------------------------------
-- Shared particle helpers used by multiple ROM scripts
---------------------------------------------------------------------------

local function dirtSpray(G, frame, ctx, brown)
  -- Shared by Mud-Slap / Sand-Attack: 6 bursts × delay 2 after short slide
  local img = loadTagImage(MA.TAG.MUD_SAND)
  local r, g, b = 0.72, 0.55, 0.28
  if brown then r, g, b = 0.45, 0.28, 0.12 end
  if frame < 4 then return end
  for burst = 0, 5 do
    local start = 4 + burst * 2
    local age = frame - start
    if age >= 0 and age < 18 then
      local u = age / 18
      local offs = { {0,0}, {10,8}, {-10,-6}, {18,4}, {-16,-4}, {6,-10} }
      for i = 1, #offs do
        local ox, oy = offs[i][1], offs[i][2]
        local x = lerp(ctx.ax, ctx.tx + ox, clamp01(u * 1.1))
        local y = lerp(ctx.ay, ctx.ty + oy, clamp01(u * 1.1))
        local a = ctx.fade * (1 - u)
        if not (img and drawTinted(img, x, y, 0.55, r, g, b, a)) then
          G.setColor(r, g, b, a)
          circle(G, x, y, 2 + (1 - u))
        end
      end
    end
  end
end

local function powderRain(G, frame, ctx, tint)
  -- Poison/Stun/Sleep Powder: particles fall over ~delay 15+30+20
  local img = loadTagImage(MA.TAG.POISON_POWDER)
  local r, g, b = tint[1], tint[2], tint[3]
  local launches = { 0, 2, 4, 15, 17, 19, 21, 45, 47, 49, 51, 65, 67, 69, 71 }
  for i = 1, #launches do
    local start = launches[i]
    local age = frame - start
    if age >= 0 and age < 28 then
      local u = age / 28
      local side = ((i % 5) - 2) * 8
      local x = ctx.tx + side + math.sin(u * 6 + i) * 4
      local y = ctx.ty - 22 + u * 36
      local a = ctx.fade * (1 - u * 0.7)
      if not (img and drawTinted(img, x, y, 0.55, r, g, b, a)) then
        G.setColor(r, g, b, a)
        circle(G, x, y, 2)
      end
    end
  end
end

local function slashCut(G, frame, ctx, life)
  life = life or 16
  if frame >= life then return end
  local t = frame / life
  local img = loadTagImage(MA.TAG.CUT)
  local a = ctx.fade * (1 - t * 0.4)
  if not (img and drawTinted(img, ctx.tx, ctx.ty, 1.1, 1, 1, 1, a)) then
    G.setColor(0.95, 0.95, 1, a)
    local dir = ctx.onEnemy and 1 or -1
    local x0 = ctx.tx + 18 * dir
    local y0 = ctx.ty - 16
    local x1 = ctx.tx - 14 * dir
    local y1 = ctx.ty + 14
    local u = clamp01(t * 1.4)
    local px = x0 + (x1 - x0) * u
    local py = y0 + (y1 - y0) * u
    G.rectangle("fill", px - 8, py - 1, 16, 3)
  end
end

local function poisonBubbles(G, frame, ctx, startFrame)
  local img = loadTagImage(MA.TAG.POISON_BUBBLE)
  local spots = { {10,10}, {20,-20}, {-20,15}, {0,0}, {-20,-20}, {16,-8} }
  for i = 1, #spots do
    local start = startFrame + (i - 1) * 6
    local age = frame - start
    if age >= 0 and age < 16 then
      local u = age / 16
      local x = ctx.tx + spots[i][1]
      local y = ctx.ty + spots[i][2] - u * 8
      local a = ctx.fade * (1 - u)
      if not (img and drawTinted(img, x, y, 0.7, 0.7, 0.3, 0.85, a)) then
        G.setColor(0.65, 0.25, 0.8, a)
        circle(G, x, y, 3)
      end
    end
  end
end


local function screenShakeFlash(G, frame, ctx, period)
  period = period or 4
  if frame % period < 2 then
    G.setColor(1, 1, 1, ctx.fade * 0.12)
    G.rectangle("fill", 0, 0, 240, 160)
  end
end

local function barrierWall(G, frame, ctx, tint, life, tag)
  life = life or 70
  local t = frame / life
  local a = ctx.fade * (0.55 + 0.2 * math.sin(frame / 6))
  if frame > life - 15 then a = a * (1 - (frame - (life - 15)) / 15) end
  local img = loadTagImage(tag)
  local x = ctx.ax + (ctx.onEnemy and 14 or -14)
  if not (img and drawTinted(img, x, ctx.ay, 1.15, tint[1], tint[2], tint[3], a)) then
    G.setColor(tint[1], tint[2], tint[3], a * 0.65)
    G.rectangle("fill", x - 6, ctx.ay - 22, 12, 44)
    G.setColor(tint[1], tint[2], tint[3], a * 0.35)
    circle(G, x, ctx.ay, 20)
  end
  -- sparkles
  for i = 0, 5 do
    local start = 10 + i * 6
    local age = frame - start
    if age >= 0 and age < 14 then
      local u = age / 14
      local sx = ctx.ax + ((i % 3) - 1) * 12
      local sy = ctx.ay - 16 + (i % 4) * 8 - u * 6
      G.setColor(1, 1, 0.85, ctx.fade * (1 - u) * 0.8)
      circle(G, sx, sy, 2)
    end
  end
end

local function iceShardBeam(G, frame, ctx)
  local img = loadTagImage(MA.TAG.ICE_CRYSTALS)
  for i = 0, 24 do
    local start = 8 + i
    local age = frame - start
    if age >= 0 and age <= 18 then
      local u = age / 18
      local side = ((i % 3) - 1) * 8
      local x = lerp(ctx.ax + 8, ctx.tx + side, u)
      local y = lerp(ctx.ay, ctx.ty + side * 0.3, u)
      local a = ctx.fade * (1 - u * 0.15)
      if not (img and drawTinted(img, x, y, 0.65, 0.7, 0.9, 1, a)) then
        G.setColor(0.65, 0.9, 1, a)
        G.rectangle("fill", x - 2, y - 3, 4, 6)
      end
    end
  end
  if frame >= 50 and frame < 80 then
    local t = (frame - 50) / 30
    G.setColor(0.55, 0.85, 1, ctx.fade * 0.25 * (1 - t))
    circle(G, ctx.tx, ctx.ty, 10 + t * 14)
    for i = 0, 4 do
      local ang = i * 1.25 + t
      G.setColor(0.8, 0.95, 1, ctx.fade * (1 - t) * 0.7)
      circle(G, ctx.tx + math.cos(ang) * (8 + t * 10), ctx.ty + math.sin(ang) * (6 + t * 8), 2)
    end
  end
end

local function fistBurst(G, frame, ctx, starts)
  local fist = loadTagImage(MA.TAG.HANDS_FEET)
  for i = 1, #starts do
    local start = starts[i][1]
    local ox, oy = starts[i][2], starts[i][3]
    local age = frame - start
    if age >= 0 and age < 12 then
      local a = ctx.fade * (1 - age / 12)
      local x, y = ctx.tx + ox, ctx.ty + oy
      if not (fist and drawTinted(fist, x, y, 1.0, 1, 1, 1, a)) then
        G.setColor(0.95, 0.85, 0.7, a)
        circle(G, x, y, 7)
      end
      hitSplat(G, x, y, age / 12, a, true)
    end
  end
end


---------------------------------------------------------------------------
-- Wave-2 FX drawers
---------------------------------------------------------------------------

function FX.mud_slap(G, frame, ctx)
  dirtSpray(G, frame, ctx, true)
end

function FX.sand_attack(G, frame, ctx)
  dirtSpray(G, frame, ctx, false)
end

function FX.rock_throw(G, frame, ctx)
  local img = loadTagImage(MA.TAG.ROCKS)
  local rocks = { {0, 0}, {19, 10}, {-23, -10}, {-15, -10}, {23, 10} }
  for i = 1, #rocks do
    local start = (i - 1) * 6
    local age = frame - start
    if age >= 0 and age < 18 then
      local u = age / 18
      local x = ctx.tx + rocks[i][1]
      local y = lerp(ctx.ty - 40, ctx.ty + rocks[i][2] * 0.2, u)
      local a = ctx.fade * (1 - u * 0.25)
      if not (img and drawTinted(img, x, y, 0.85, 0.75, 0.65, 0.45, a)) then
        G.setColor(0.55, 0.45, 0.3, a)
        G.rectangle("fill", x - 4, y - 3, 8, 6)
      end
    end
  end
  if frame >= 12 and frame < 36 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 12) / 20, ctx.fade * 0.5, true)
  end
end

function FX.bubble(G, frame, ctx)
  local img = loadTagImage(MA.TAG.BUBBLE) or loadTagImage(MA.TAG.SMALL_BUBBLES)
  local launches = { 0, 6, 12, 18, 24, 30 }
  local sides = { -15, 37, -37, 10, 33, -30 }
  for i = 1, #launches do
    local start = launches[i]
    local age = frame - start
    if age >= 0 and age <= 55 then
      local u = age / 55
      local x = lerp(ctx.ax + 10, ctx.tx + sides[i] * 0.3, u)
      local y = lerp(ctx.ay, ctx.ty + sides[i] * 0.15, u) - math.sin(u * math.pi) * 12
      local a = ctx.fade * (1 - u * 0.2)
      if not (img and drawTinted(img, x, y, 0.8, 0.55, 0.85, 1, a)) then
        G.setColor(0.5, 0.8, 1, a)
        circle(G, x, y, 4)
        G.setColor(0.9, 0.95, 1, a * 0.6)
        circle(G, x - 1, y - 1, 1.5)
      end
    end
  end
  if frame >= 70 then
    poisonBubbles(G, frame, ctx, 70) -- reuse bubble pop offsets with water tint below
    local img2 = loadTagImage(MA.TAG.SMALL_BUBBLES)
    for i = 0, 4 do
      local age = frame - (70 + i * 5)
      if age >= 0 and age < 18 then
        local u = age / 18
        local x = ctx.tx + (i - 2) * 8
        local y = ctx.ty - 6 + u * 10
        local a = ctx.fade * (1 - u)
        if not (img2 and drawTinted(img2, x, y, 0.6, 0.55, 0.85, 1, a)) then
          G.setColor(0.55, 0.85, 1, a)
          circle(G, x, y, 3)
        end
      end
    end
  end
end

function FX.bubblebeam(G, frame, ctx)
  local img = loadTagImage(MA.TAG.BUBBLE) or loadTagImage(MA.TAG.SMALL_BUBBLES)
  -- denser stream: 18 bubbles every 3f
  for i = 0, 17 do
    local start = i * 3
    local age = frame - start
    if age >= 0 and age <= 35 then
      local u = age / 35
      local wob = math.sin(i * 1.7) * 12
      local x = lerp(ctx.ax + 8, ctx.tx + wob, u)
      local y = lerp(ctx.ay, ctx.ty + math.cos(i) * 8, u)
      local a = ctx.fade * (1 - u * 0.15)
      if not (img and drawTinted(img, x, y, 0.75, 0.5, 0.8, 1, a)) then
        G.setColor(0.4, 0.75, 1, a)
        circle(G, x, y, 3.5)
      end
    end
  end
  if frame >= 55 then
    local t = (frame - 55) / 30
    if t < 1 then
      G.setColor(0.4, 0.75, 1, ctx.fade * 0.2 * (1 - t))
      circle(G, ctx.tx, ctx.ty, 10 + t * 16)
    end
  end
end

function FX.razor_leaf(G, frame, ctx)
  local img = loadTagImage(MA.TAG.LEAF)
  -- swirl near attacker first ~60f
  if frame < 60 then
    for i = 0, 9 do
      local start = i * 2
      local age = frame - start
      if age >= 0 and age < 20 then
        local ang = i * 0.7 + age * 0.25
        local rad = 8 + age * 0.8
        local x = ctx.ax + math.cos(ang) * rad
        local y = ctx.ay + math.sin(ang) * rad * 0.6
        local a = ctx.fade * (1 - age / 20)
        if not (img and drawTinted(img, x, y, 0.55, 0.35, 0.85, 0.25, a)) then
          G.setColor(0.3, 0.8, 0.25, a)
          G.rectangle("fill", x - 3, y - 1, 6, 2)
        end
      end
    end
  end
  -- blades to target ~frame 60
  if frame >= 60 then
    local blade = loadTagImage(MA.TAG.RAZOR_LEAF) or img
    for i = 0, 1 do
      local age = frame - 60
      if age >= 0 and age <= 22 then
        local u = age / 22
        local side = (i == 0) and 20 or -20
        local x = lerp(ctx.ax, ctx.tx, u)
        local y = lerp(ctx.ay - 10, ctx.ty, u) + side * (1 - u) * 0.3
        local a = ctx.fade
        if not (blade and drawTinted(blade, x, y, 0.9, 0.4, 0.9, 0.3, a)) then
          G.setColor(0.35, 0.85, 0.2, a)
          G.rectangle("fill", x - 6, y - 1, 12, 2)
        end
      end
    end
  end
  if frame >= 80 and frame < 100 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 80) / 16, ctx.fade, true)
  end
end

function FX.bite(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SHARP_TEETH)
  if frame < 14 then
    local u = clamp01(frame / 10)
    local gap = (1 - u) * 28
    local a = ctx.fade
    local topY = ctx.ty - 8 - gap
    local botY = ctx.ty + 8 + gap
    if not (img and drawTinted(img, ctx.tx, topY, 1.0, 1, 1, 1, a)) then
      G.setColor(0.95, 0.95, 0.98, a)
      G.rectangle("fill", ctx.tx - 10, topY - 4, 20, 6)
      G.rectangle("fill", ctx.tx - 10, botY - 2, 20, 6)
    else
      drawTinted(img, ctx.tx, botY, 1.0, 1, 1, 1, a)
    end
  end
  if frame >= 10 and frame < 24 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 10) / 12, ctx.fade, true)
  end
end

function FX.string_shot(G, frame, ctx)
  if frame < 12 then
    G.setColor(0, 0, 0, ctx.fade * 0.2 * (frame / 12))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local img = loadTagImage(MA.TAG.STRING) or loadTagImage(MA.TAG.STRING_DOT)
  -- silk dots stream ~18 frames
  for i = 0, 17 do
    local start = 8 + i
    local age = frame - start
    if age >= 0 and age <= 20 then
      local u = age / 20
      local x = lerp(ctx.ax, ctx.tx, u)
      local y = lerp(ctx.ay, ctx.ty + math.sin(i) * 6, u)
      local a = ctx.fade * (0.5 + 0.5 * (1 - u))
      if not (img and drawTinted(img, x, y, 0.45, 0.95, 0.95, 0.85, a)) then
        G.setColor(0.95, 0.95, 0.8, a)
        circle(G, x, y, 1.5)
      end
    end
  end
  -- wrap lines late
  if frame >= 70 then
    local t = (frame - 70) / 18
    if t < 1 then
      G.setColor(0.95, 0.95, 0.85, ctx.fade * (1 - t) * 0.7)
      for i = -1, 1 do
        G.rectangle("fill", ctx.tx - 14, ctx.ty + i * 8 - 1, 28, 2)
      end
    end
  end
end

function FX.harden(G, frame, ctx)
  local t = frame / 56
  local pulse = 0.5 + 0.5 * math.sin(frame / 7)
  G.setColor(0.75, 0.8, 0.9, ctx.fade * 0.25 * pulse)
  circle(G, ctx.ax, ctx.ay, 20 + pulse * 4)
  G.setColor(1, 1, 1, ctx.fade * 0.45 * pulse)
  circle(G, ctx.ax + 8, ctx.ay - 10, 3)
  if frame > 28 then
    G.setColor(0.85, 0.9, 1, ctx.fade * 0.2 * (1 - (frame - 28) / 28))
    circle(G, ctx.ax, ctx.ay, 24)
  end
end

function FX.leer(G, frame, ctx)
  local img = loadTagImage(MA.TAG.LEER)
  if frame < 18 then
    local a = ctx.fade * (1 - frame / 22)
    if not (img and drawTinted(img, ctx.ax + (ctx.onEnemy and 18 or -18), ctx.ay - 8, 1.0, 1, 1, 0.4, a)) then
      G.setColor(1, 1, 0.4, a)
      local dir = ctx.onEnemy and 1 or -1
      G.rectangle("fill", ctx.ax + 8 * dir, ctx.ay - 10, 16 * dir, 2)
      G.rectangle("fill", ctx.ax + 8 * dir, ctx.ay - 4, 12 * dir, 2)
    end
  end
  if frame >= 18 and frame < 36 then
    local a = ctx.fade * 0.35 * math.sin((frame - 18) / 18 * math.pi)
    G.setColor(1, 0.3, 0.2, a)
    circle(G, ctx.tx, ctx.ty, 16)
  end
end

function FX.gust(G, frame, ctx)
  local img = loadTagImage(MA.TAG.GUST)
  if frame < 36 then
    local t = frame / 36
    for i = 0, 3 do
      local ang = t * 8 + i * 1.57
      local rad = 6 + t * 18
      local x = ctx.tx + math.cos(ang) * rad
      local y = ctx.ty + math.sin(ang) * rad * 0.55
      local a = ctx.fade * (1 - t * 0.4)
      if not (img and drawTinted(img, x, y, 0.8, 0.85, 0.9, 1, a)) then
        G.setColor(0.85, 0.9, 0.95, a * 0.7)
        circle(G, x, y, 5)
      end
    end
  end
  if frame >= 30 and frame < 46 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 30) / 12, ctx.fade, true)
  end
end

function FX.peck(G, frame, ctx)
  if frame < 12 then
    hitSplat(G, ctx.tx - 6, ctx.ty, frame / 12, ctx.fade, true)
  end
end

function FX.wing_attack(G, frame, ctx)
  local img = loadTagImage(MA.TAG.GUST)
  if frame < 24 then
    for side = -1, 1, 2 do
      local x = ctx.ax + side * (18 + frame * 0.4)
      local y = ctx.ay
      local a = ctx.fade * 0.55
      if not (img and drawTinted(img, x, y, 0.7, 0.85, 0.9, 1, a)) then
        G.setColor(0.85, 0.9, 1, a)
        circle(G, x, y, 6)
      end
    end
  end
  if frame >= 36 and frame < 52 then
    hitSplat(G, ctx.tx + 10, ctx.ty, (frame - 36) / 12, ctx.fade, true)
    hitSplat(G, ctx.tx - 10, ctx.ty, (frame - 36) / 12, ctx.fade, true)
  end
end

function FX.mega_drain(G, frame, ctx)
  -- denser absorb
  if frame < 10 then
    hitSplat(G, ctx.tx, ctx.ty, frame / 10, ctx.fade, true)
  end
  if frame < 18 then
    G.setColor(0.35, 0.9, 0.35, ctx.fade * 0.15)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  if frame >= 12 and frame < 75 then
    for i = 0, 15 do
      local start = 12 + i * 4
      local age = frame - start
      if age >= 0 and age <= 28 then
        local u = age / 28
        local side = ((i % 4) - 1.5) * 10
        local x = lerp(ctx.tx + side, ctx.ax, u)
        local y = lerp(ctx.ty, ctx.ay, u)
        local img = loadTagImage(MA.TAG.ORBS)
        local a = ctx.fade * (0.45 + 0.55 * (1 - u))
        if not (img and drawTinted(img, x, y, 0.75, 0.35, 0.95, 0.35, a)) then
          G.setColor(0.3, 0.9, 0.35, a)
          circle(G, x, y, 2.8)
        end
      end
    end
  end
  if frame >= 80 and frame < 105 then
    local t = (frame - 80) / 25
    local img = loadTagImage(MA.TAG.BLUE_STAR)
    for i = 0, 3 do
      local ang = i * 1.6 + t * 3
      local x = ctx.ax + math.cos(ang) * (10 + t * 10)
      local y = ctx.ay - 6 - t * 14
      local a = ctx.fade * (1 - t)
      if not (img and drawTinted(img, x, y, 0.65, 0.55, 0.9, 1, a)) then
        G.setColor(0.7, 0.95, 1, a)
        circle(G, x, y, 2)
      end
    end
  end
end

function FX.fire_spin(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SMALL_EMBER)
  for i = 0, 17 do
    local start = i * 2
    local age = frame - start
    if age >= 0 and age < 30 then
      local u = age / 30
      local ang = i * 0.7 + u * 6
      local rad = 22 - u * 10
      local x = ctx.tx + math.cos(ang) * rad
      local y = ctx.ty + 10 + math.sin(ang) * rad * 0.45 - u * 8
      local a = ctx.fade * (1 - u * 0.5)
      if not (img and drawTinted(img, x, y, 0.7, 1, 0.5, 0.15, a)) then
        G.setColor(1, 0.4, 0.1, a)
        circle(G, x, y, 3)
      end
    end
  end
end

function FX.flamethrower(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SMALL_EMBER)
  for i = 0, 28 do
    local start = 6 + i * 2
    local age = frame - start
    if age >= 0 and age <= 16 then
      local u = age / 16
      local wob = math.sin(i * 0.9) * 6
      local x = lerp(ctx.ax + 8, ctx.tx, u)
      local y = lerp(ctx.ay, ctx.ty, u) + wob
      local a = ctx.fade * (1 - u * 0.2)
      if not (img and drawTinted(img, x, y, 0.8, 1, 0.45, 0.1, a)) then
        G.setColor(1, 0.35 + (i % 3) * 0.1, 0.08, a)
        circle(G, x, y, 4 - u * 1.5)
      end
    end
  end
end

function FX.confusion(G, frame, ctx)
  if frame < 20 then
    G.setColor(0.75, 0.45, 0.95, ctx.fade * 0.12)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local t = frame / 50
  for i = 0, 4 do
    local ang = t * 10 + i * 1.25
    local x = ctx.tx + math.cos(ang) * (10 + (frame % 12))
    local y = ctx.ty + math.sin(ang) * (8 + (frame % 10))
    G.setColor(0.9, 0.55, 1, ctx.fade * 0.55 * (1 - t * 0.5))
    circle(G, x, y, 3)
  end
  if frame >= 18 and frame < 40 then
    local a = ctx.fade * 0.35 * math.sin((frame - 18) / 22 * math.pi)
    G.setColor(1, 1, 1, a)
    circle(G, ctx.tx, ctx.ty, 14)
  end
end

function FX.psybeam(G, frame, ctx)
  local img = loadTagImage(MA.TAG.GOLD_RING)
  for i = 0, 10 do
    local start = i * 4
    local age = frame - start
    if age >= 0 and age <= 13 then
      local u = age / 13
      local x = lerp(ctx.ax, ctx.tx, u)
      local y = lerp(ctx.ay, ctx.ty, u)
      local a = ctx.fade * (1 - u * 0.2)
      if not (img and drawTinted(img, x, y, 0.7, 1, 0.85, 0.3, a)) then
        G.setColor(1, 0.85, 0.35, a)
        circle(G, x, y, 4)
        G.setColor(1, 0.95, 0.6, a * 0.5)
        circle(G, x, y, 2)
      end
    end
  end
  if frame >= 40 and frame < 70 then
    G.setColor(1, 0.5, 0.9, ctx.fade * 0.12)
    circle(G, ctx.tx, ctx.ty, 18)
  end
end

function FX.rock_smash(G, frame, ctx)
  local fist = loadTagImage(MA.TAG.HANDS_FEET)
  if frame < 10 then
    if not (fist and drawTinted(fist, ctx.tx, ctx.ty, 1.0, 1, 1, 1, ctx.fade)) then
      G.setColor(0.95, 0.85, 0.7, ctx.fade)
      circle(G, ctx.tx, ctx.ty, 7)
    end
    hitSplat(G, ctx.tx, ctx.ty, frame / 10, ctx.fade, true)
  end
  if frame >= 10 then
    local img = loadTagImage(MA.TAG.ROCKS)
    local bits = {
      {20, 24}, {-20, 24}, {20, -24}, {-20, -24},
      {30, 18}, {30, -18}, {-30, 18}, {-30, -18},
    }
    for i = 1, #bits do
      local age = frame - 10
      if age >= 0 and age < 22 then
        local u = age / 22
        local x = ctx.tx + bits[i][1] * u
        local y = ctx.ty + bits[i][2] * u - u * u * 10
        local a = ctx.fade * (1 - u)
        if not (img and drawTinted(img, x, y, 0.55, 0.7, 0.6, 0.4, a)) then
          G.setColor(0.5, 0.4, 0.28, a)
          G.rectangle("fill", x - 3, y - 2, 6, 4)
        end
      end
    end
  end
end

function FX.poison_sting(G, frame, ctx)
  local img = loadTagImage(MA.TAG.NEEDLE)
  if frame <= 20 then
    local u = frame / 20
    local x = lerp(ctx.ax + 12, ctx.tx, u)
    local y = lerp(ctx.ay, ctx.ty, u)
    local a = ctx.fade
    if not (img and drawTinted(img, x, y, 0.8, 0.85, 0.95, 0.4, a)) then
      G.setColor(0.7, 0.9, 0.4, a)
      G.rectangle("fill", x - 5, y - 1, 10, 2)
    end
  end
  if frame >= 18 and frame < 30 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 18) / 10, ctx.fade, true)
  end
  if frame >= 28 then
    poisonBubbles(G, frame, ctx, 28)
  end
end

function FX.poison_powder(G, frame, ctx)
  powderRain(G, frame, ctx, {0.7, 0.35, 0.85})
end

function FX.stun_spore(G, frame, ctx)
  powderRain(G, frame, ctx, {0.95, 0.85, 0.25})
end

function FX.sleep_powder(G, frame, ctx)
  powderRain(G, frame, ctx, {0.45, 0.85, 0.55})
end

function FX.headbutt(G, frame, ctx)
  if frame >= 14 and frame < 30 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 14) / 12, ctx.fade, true)
  end
end

function FX.body_slam(G, frame, ctx)
  if frame >= 18 and frame < 36 then
    hitSplat(G, ctx.tx - 6, ctx.ty, (frame - 18) / 14, ctx.fade, true)
  end
end

function FX.take_down(G, frame, ctx)
  if frame >= 35 and frame < 55 then
    hitSplat(G, ctx.tx - 6, ctx.ty, (frame - 35) / 14, ctx.fade, true)
    G.setColor(1, 1, 1, ctx.fade * 0.25)
    circle(G, ctx.tx, ctx.ty, 16)
  end
end

function FX.strength(G, frame, ctx)
  local hits = { 40, 44, 48 }
  for i = 1, #hits do
    local start = hits[i]
    local age = frame - start
    if age >= 0 and age < 10 then
      local ox = ({16, -16, 3})[i]
      local oy = ({12, -12, 4})[i]
      hitSplat(G, ctx.tx + ox, ctx.ty + oy, age / 10, ctx.fade, true)
    end
  end
end

function FX.cut(G, frame, ctx)
  slashCut(G, frame, ctx, 16)
end

function FX.aerial_ace(G, frame, ctx)
  if frame < 8 then
    -- motion blur via offsets; soft trail
    local u = frame / 8
    G.setColor(0.85, 0.9, 1, ctx.fade * 0.3)
    circle(G, lerp(ctx.ax, ctx.tx, u), lerp(ctx.ay, ctx.ty, u), 5)
  end
  slashCut(G, math.max(0, frame - 4), ctx, 16)
end

function FX.metal_claw(G, frame, ctx)
  if frame < 16 then
    FX.harden(G, frame, ctx)
  end
  local img = loadTagImage(MA.TAG.CLAW_SLASH) or loadTagImage(MA.TAG.SCRATCH)
  local bursts = { 16, 30 }
  for bi = 1, #bursts do
    local start = bursts[bi]
    local age = frame - start
    if age >= 0 and age < 12 then
      local a = ctx.fade * (1 - age / 12)
      local side = (bi == 1) and -10 or 10
      if not (img and drawTinted(img, ctx.tx + side, ctx.ty, 1.0, 0.85, 0.9, 1, a)) then
        scratchMarks(G, ctx.tx + side, ctx.ty, age / 12, a, ctx.onEnemy)
      end
    end
  end
end

function FX.protect(G, frame, ctx)
  local img = loadTagImage(MA.TAG.PROTECT)
  local t = frame / 90
  local a = ctx.fade * (0.55 + 0.25 * math.sin(frame / 8))
  if frame > 70 then a = a * (1 - (frame - 70) / 20) end
  if not (img and drawTinted(img, ctx.ax + (ctx.onEnemy and 10 or -10), ctx.ay, 1.2, 0.55, 0.85, 1, a)) then
    G.setColor(0.5, 0.85, 1, a * 0.7)
    circle(G, ctx.ax, ctx.ay, 22)
    G.setColor(0.7, 0.95, 1, a * 0.35)
    circle(G, ctx.ax, ctx.ay, 16)
  end
end

function FX.rest(G, frame, ctx)
  local img = loadTagImage(MA.TAG.LETTER_Z)
  local zs = { 0, 20, 40 }
  for i = 1, #zs do
    local start = zs[i]
    local age = frame - start
    if age >= 0 and age < 28 then
      local u = age / 28
      local x = ctx.ax + 10 + u * 12 + (i - 1) * 4
      local y = ctx.ay - 10 - u * 18
      local a = ctx.fade * (1 - u)
      if not (img and drawTinted(img, x, y, 0.7 + i * 0.1, 0.95, 0.85, 1, a)) then
        G.setColor(0.95, 0.9, 1, a)
        -- crude Z
        G.rectangle("fill", x - 3, y - 4, 7, 2)
        G.rectangle("fill", x - 2, y - 1, 2, 4)
        G.rectangle("fill", x - 3, y + 3, 7, 2)
      end
    end
  end
end

function FX.toxic(G, frame, ctx)
  local img = loadTagImage(MA.TAG.TOXIC_BUBBLE)
  local spots = { {-24, 16}, {8, 16}, {-8, 16}, {24, 16}, {-24, 16}, {8, 16}, {-8, 16}, {24, 16} }
  for i = 1, #spots do
    local start = (i - 1) * 15
    local age = frame - start
    if age >= 0 and age < 20 then
      local u = age / 20
      local x = ctx.tx + spots[i][1]
      local y = ctx.ty + spots[i][2] - u * 20
      local a = ctx.fade * (1 - u * 0.5)
      if not (img and drawTinted(img, x, y, 0.85, 0.55, 0.2, 0.75, a)) then
        G.setColor(0.55, 0.15, 0.7, a)
        circle(G, x, y, 5)
      end
    end
  end
  if frame >= 60 then
    poisonBubbles(G, frame, ctx, 60)
  end
end

function FX.dig_charge(G, frame, ctx)
  -- Move_DIG charge half (_81CB0AB): dirt mounds + plumes, attacker sinks
  local mound = loadTagImage(MA.TAG.DIRT_MOUND)
  local dirt = loadTagImage(MA.TAG.MUD_SAND)
  local a = ctx.fade * math.min(1, frame / 8)
  if not (mound and drawTinted(mound, ctx.ax - 8, ctx.ay + 14, 0.95, 0.55, 0.4, 0.2, a)) then
    G.setColor(0.45, 0.3, 0.15, a)
    G.rectangle("fill", ctx.ax - 14, ctx.ay + 10, 14, 8)
  end
  if not (mound and drawTinted(mound, ctx.ax + 8, ctx.ay + 14, 0.95, 0.55, 0.4, 0.2, a)) then
    G.setColor(0.45, 0.3, 0.15, a)
    G.rectangle("fill", ctx.ax, ctx.ay + 10, 14, 8)
  end
  for burst = 0, 4 do
    local bstart = 4 + burst * 7
    for i = 0, 3 do
      local age = frame - (bstart + i)
      if age >= 0 and age < 16 then
        local u = age / 16
        local x = ctx.ax + (i - 1.5) * 7
        local y = ctx.ay + 12 - u * 22
        local aa = ctx.fade * (1 - u)
        if not (dirt and drawTinted(dirt, x, y, 0.5, 0.5, 0.35, 0.15, aa)) then
          G.setColor(0.5, 0.35, 0.15, aa)
          circle(G, x, y, 2)
        end
      end
    end
  end
end

function FX.dig_hit(G, frame, ctx)
  -- Move_DIG emerge half (_81CB106): mound + hit splat
  local mound = loadTagImage(MA.TAG.DIRT_MOUND)
  local dirt = loadTagImage(MA.TAG.MUD_SAND)
  local a = ctx.fade * math.min(1, 1 - frame / 50)
  if frame < 20 then
    if not (mound and drawTinted(mound, ctx.ax, ctx.ay + 12, 1.0, 0.55, 0.4, 0.2, a)) then
      G.setColor(0.45, 0.3, 0.15, a)
      G.rectangle("fill", ctx.ax - 12, ctx.ay + 8, 24, 8)
    end
  end
  if frame >= 12 and frame < 36 then
    hitSplat(G, ctx.tx - 4, ctx.ty, (frame - 12) / 14, ctx.fade, true)
  end
  if frame >= 4 and frame < 28 then
    for i = 0, 4 do
      local age = frame - (4 + i * 3)
      if age >= 0 and age < 14 then
        local u = age / 14
        local x = ctx.ax + (i - 2) * 6
        local y = ctx.ay + 10 - u * 16
        local aa = ctx.fade * (1 - u)
        if not (dirt and drawTinted(dirt, x, y, 0.5, 0.5, 0.35, 0.15, aa)) then
          G.setColor(0.5, 0.35, 0.15, aa)
          circle(G, x, y, 2)
        end
      end
    end
  end
end

-- Back-compat alias (compressed dig-down+emerge)
function FX.dig(G, frame, ctx)
  if frame < 40 then FX.dig_charge(G, frame, ctx)
  else FX.dig_hit(G, frame - 40, ctx) end
end

function FX.surf(G, frame, ctx)
  local t = frame / 60
  -- rising wave across battlefield toward target
  local waveX = lerp(20, 220, t)
  local a = ctx.fade * (0.55 + 0.2 * math.sin(frame / 4))
  G.setColor(0.25, 0.55, 0.95, a * 0.55)
  G.rectangle("fill", 0, 90 - math.sin(t * math.pi) * 25, 240, 70)
  G.setColor(0.55, 0.85, 1, a * 0.4)
  for i = 0, 6 do
    local x = (waveX + i * 18) % 240
    circle(G, x, 100 - math.sin((frame + i * 5) / 6) * 8, 8)
  end
  if frame >= 24 and frame < 50 then
    G.setColor(0.6, 0.85, 1, ctx.fade * 0.25)
    circle(G, ctx.tx, ctx.ty, 18)
  end
end

function FX.hyper_beam(G, frame, ctx)
  if frame < 40 then
    local u = frame / 40
    G.setColor(0, 0, 0, ctx.fade * 0.45 * u)
    G.rectangle("fill", 0, 0, 240, 160)
    -- charge orbs at attacker
    local img = loadTagImage(MA.TAG.ORBS)
    for i = 0, 5 do
      local ang = frame * 0.3 + i
      local rad = 16 - u * 8
      local x = ctx.ax + math.cos(ang) * rad
      local y = ctx.ay + math.sin(ang) * rad
      local a = ctx.fade
      if not (img and drawTinted(img, x, y, 0.7, 1, 0.35, 0.35, a)) then
        G.setColor(1, 0.35, 0.35, a)
        circle(G, x, y, 3)
      end
    end
  else
    -- beam
    local img = loadTagImage(MA.TAG.ORBS)
    local beamFrame = frame - 40
    for i = 0, 24 do
      local start = i
      local age = beamFrame - start
      if age >= 0 and age < 8 then
        local u = (i / 24)
        local x = lerp(ctx.ax, ctx.tx, u)
        local y = lerp(ctx.ay, ctx.ty, u)
        local a = ctx.fade * 0.9
        if not (img and drawTinted(img, x, y, 0.85, 1, 0.4, 0.35, a)) then
          G.setColor(1, 0.3, 0.3, a)
          circle(G, x, y, 4)
        end
      end
    end
    G.setColor(1, 0.45, 0.35, ctx.fade * 0.2)
    -- thick beam body
    local steps = 12
    for s = 0, steps do
      local u = s / steps
      local x = lerp(ctx.ax, ctx.tx, u)
      local y = lerp(ctx.ay, ctx.ty, u)
      circle(G, x, y, 6)
    end
    if beamFrame > 10 then
      hitSplat(G, ctx.tx, ctx.ty, ((beamFrame - 10) % 16) / 16, ctx.fade * 0.6, true)
    end
  end
end

function FX.double_team(G, frame, ctx)
  -- afterimage clones flanking attacker
  local flashes = { 0, 32, 56, 72, 80, 88, 96, 104, 112 }
  for i = 1, #flashes do
    local start = flashes[i]
    local age = frame - start
    if age >= 0 and age < 10 then
      local a = ctx.fade * (1 - age / 10) * 0.45
      local side = ((i % 2) * 2 - 1) * (8 + i * 2)
      G.setColor(0.85, 0.9, 1, a)
      circle(G, ctx.ax + side, ctx.ay, 10)
      circle(G, ctx.ax - side * 0.6, ctx.ay + 4, 8)
    end
  end
end


---------------------------------------------------------------------------
-- Wave-3 FX drawers
---------------------------------------------------------------------------

function FX.magnitude(G, frame, ctx)
  screenShakeFlash(G, frame, ctx, 5)
  if frame >= 20 and frame < 50 then
    G.setColor(0.85, 0.7, 0.4, ctx.fade * 0.1)
    G.rectangle("fill", 0, 100, 240, 60)
  end
  if frame > 30 and frame < 55 then
    local dirt = loadTagImage(MA.TAG.MUD_SAND)
    for i = 0, 5 do
      local age = frame - (30 + i * 3)
      if age >= 0 and age < 14 then
        local u = age / 14
        local x = 40 + i * 30 + (frame % 5)
        local y = 120 - u * 18
        local a = ctx.fade * (1 - u)
        if not (dirt and drawTinted(dirt, x, y, 0.5, 0.55, 0.4, 0.2, a)) then
          G.setColor(0.5, 0.35, 0.15, a)
          circle(G, x, y, 2)
        end
      end
    end
  end
end

function FX.earthquake(G, frame, ctx)
  screenShakeFlash(G, frame, ctx, 4)
  G.setColor(0.6, 0.45, 0.25, ctx.fade * 0.15 * math.sin(frame / 50 * math.pi))
  G.rectangle("fill", 0, 110, 240, 50)
end

function FX.brick_break(G, frame, ctx)
  -- Move_BRICK_BREAK: no-screen path always; shatter shards if ctx.shatter (screens were up)
  fistBurst(G, frame, ctx, {
    {5, -18, -18}, {30, 18, 18}, {72, 0, 0},
  })
  if ctx.shatter then
    -- blue/green wall appears early then tears (TORN_METAL / wall tags)
    if frame >= 8 and frame < 72 then
      local wall = loadTagImage(MA.TAG.BLUE_LIGHT_WALL) or loadTagImage(MA.TAG.GREEN_LIGHT_WALL)
      local a = ctx.fade * 0.55
      if not (wall and drawTinted(wall, ctx.tx, ctx.ty, 1.1, 0.55, 0.75, 1, a)) then
        G.setColor(0.45, 0.7, 1, a * 0.5)
        G.rectangle("fill", ctx.tx - 18, ctx.ty - 28, 36, 56)
      end
    end
    if frame >= 72 and frame < 96 then
      local img = loadTagImage(MA.TAG.TORN_METAL) or loadTagImage(MA.TAG.ROCKS)
      for i = 0, 3 do
        local u = (frame - 72) / 24
        local ox = ((i % 2) * 2 - 1) * (8 + u * 16)
        local oy = ((i < 2) and -1 or 1) * (8 + u * 14)
        local a = ctx.fade * (1 - u)
        if not (img and drawTinted(img, ctx.tx + ox, ctx.ty + oy, 0.55, 0.7, 0.8, 1, a)) then
          G.setColor(0.55, 0.7, 0.9, a)
          G.rectangle("fill", ctx.tx + ox - 3, ctx.ty + oy - 2, 6, 4)
        end
      end
    end
  elseif frame >= 72 and frame < 90 then
    local img = loadTagImage(MA.TAG.ROCKS)
    for i = 0, 3 do
      local u = (frame - 72) / 18
      local ox = ((i % 2) * 2 - 1) * (8 + u * 10)
      local oy = ((i < 2) and -1 or 1) * (8 + u * 10)
      local a = ctx.fade * (1 - u)
      if not (img and drawTinted(img, ctx.tx + ox, ctx.ty + oy, 0.5, 0.6, 0.7, 0.9, a)) then
        G.setColor(0.55, 0.65, 0.85, a)
        G.rectangle("fill", ctx.tx + ox - 3, ctx.ty + oy - 2, 6, 4)
      end
    end
  end
end

function FX.bulk_up(G, frame, ctx)
  local img = loadTagImage(MA.TAG.BREATH)
  local t = frame / 40
  local pulse = 0.5 + 0.5 * math.sin(frame / 5)
  G.setColor(1, 0.55, 0.35, ctx.fade * 0.2 * pulse)
  circle(G, ctx.ax, ctx.ay, 18 + pulse * 4)
  if frame >= 12 and frame < 36 then
    local a = ctx.fade * (1 - (frame - 12) / 24)
    if not (img and drawTinted(img, ctx.ax, ctx.ay - 18, 1.0, 1, 0.7, 0.5, a)) then
      G.setColor(1, 0.75, 0.55, a)
      circle(G, ctx.ax, ctx.ay - 16, 6)
      circle(G, ctx.ax + 4, ctx.ay - 22, 4)
    end
  end
end

function FX.calm_mind(G, frame, ctx)
  if frame < 20 then
    G.setColor(0, 0, 0, ctx.fade * 0.35 * (frame / 20))
    G.rectangle("fill", 0, 0, 240, 160)
  elseif frame < 70 then
    G.setColor(0, 0, 0, ctx.fade * 0.35)
    G.rectangle("fill", 0, 0, 240, 160)
  else
    G.setColor(0, 0, 0, ctx.fade * 0.35 * (1 - (frame - 70) / 10))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local img = loadTagImage(MA.TAG.THIN_RING)
  local rings = { 16, 30, 44 }
  for i = 1, #rings do
    local start = rings[i]
    local age = frame - start
    if age >= 0 and age < 22 then
      local u = age / 22
      local a = ctx.fade * (1 - u)
      local s = 0.6 + u * 1.4
      if not (img and drawTinted(img, ctx.ax, ctx.ay, s, 0.7, 0.85, 1, a)) then
        G.setColor(0.7, 0.85, 1, a * 0.6)
        circle(G, ctx.ax, ctx.ay, 8 + u * 18)
      end
    end
  end
end

function FX.shadow_ball(G, frame, ctx)
  if frame < 50 then
    G.setColor(0.15, 0.05, 0.25, ctx.fade * 0.35)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local img = loadTagImage(MA.TAG.SHADOW_BALL)
  if frame >= 12 and frame <= 55 then
    local u = (frame - 12) / 43
    local x = lerp(ctx.ax, ctx.tx, u)
    local y = lerp(ctx.ay, ctx.ty, u) - math.sin(u * math.pi) * 10
    local a = ctx.fade
    if not (img and drawTinted(img, x, y, 1.1, 0.55, 0.25, 0.75, a)) then
      G.setColor(0.45, 0.15, 0.65, a)
      circle(G, x, y, 8)
      G.setColor(0.2, 0.05, 0.3, a * 0.7)
      circle(G, x - 2, y - 2, 3)
    end
  end
  if frame >= 50 and frame < 66 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 50) / 12, ctx.fade, true)
  end
end

function FX.hydro_pump(G, frame, ctx)
  local img = loadTagImage(MA.TAG.WATER_ORB) or loadTagImage(MA.TAG.SMALL_BUBBLES)
  for i = 0, 40 do
    local start = 6 + i * 2
    local age = frame - start
    if age >= 0 and age <= 14 then
      local u = age / 14
      local side = ((i % 2) * 2 - 1) * 10
      local x = lerp(ctx.ax + 6, ctx.tx + side * 0.4, u)
      local y = lerp(ctx.ay, ctx.ty, u)
      local a = ctx.fade
      if not (img and drawTinted(img, x, y, 0.75, 0.45, 0.75, 1, a)) then
        G.setColor(0.35, 0.65, 1, a)
        circle(G, x, y, 4)
      end
    end
  end
  local splash = loadTagImage(MA.TAG.WATER_IMPACT)
  local impacts = { 30, 42, 54, 66, 78 }
  for i = 1, #impacts do
    local age = frame - impacts[i]
    if age >= 0 and age < 10 then
      local oy = ((i % 2) * 2 - 1) * 12
      local a = ctx.fade * (1 - age / 10)
      if not (splash and drawTinted(splash, ctx.tx, ctx.ty + oy, 0.8, 0.5, 0.8, 1, a)) then
        G.setColor(0.4, 0.75, 1, a)
        circle(G, ctx.tx, ctx.ty + oy, 6)
      end
    end
  end
end

function FX.ice_beam(G, frame, ctx)
  if frame < 12 then
    G.setColor(0, 0, 0, ctx.fade * 0.25 * (frame / 12))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  iceShardBeam(G, frame, ctx)
end

function FX.thunderbolt(G, frame, ctx)
  if frame < 20 then
    G.setColor(0, 0, 0, ctx.fade * 0.3 * (frame / 20))
    G.rectangle("fill", 0, 0, 240, 160)
  elseif frame < 90 then
    G.setColor(0, 0, 0, ctx.fade * 0.25)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local bolts = { {16, 24}, {30, -24}, {44, 0} }
  local shock = loadTagImage(MA.TAG.SHOCK_3) or loadTagImage(MA.TAG.SHOCK)
  for i = 1, #bolts do
    local start, ox = bolts[i][1], bolts[i][2]
    local age = frame - start
    if age >= 0 and age < 14 then
      local a = ctx.fade * (1 - age / 14)
      G.setColor(1, 1, 0.55, a)
      G.rectangle("fill", ctx.tx + ox - 1, 0, 3, ctx.ty)
      if shock then drawTinted(shock, ctx.tx + ox, ctx.ty - 8, 0.9, 1, 1, 0.5, a) end
    end
  end
  if frame >= 70 and frame < 110 then
    local sparks = loadTagImage(MA.TAG.SPARK)
    for i = 0, 7 do
      local start = 70 + i * 2
      local age = frame - start
      if age >= 0 and age < 12 then
        local ang = i * 0.8
        local x = ctx.tx + math.cos(ang) * (12 + age)
        local y = ctx.ty + math.sin(ang) * (10 + age * 0.5)
        local a = ctx.fade * (1 - age / 12)
        if not (sparks and drawTinted(sparks, x, y, 0.65, 1, 1, 0.4, a)) then
          G.setColor(1, 0.95, 0.35, a)
          G.rectangle("fill", x - 1, y - 4, 2, 8)
        end
      end
    end
  end
end

function FX.thunder(G, frame, ctx)
  if frame < 100 then
    G.setColor(0.05, 0.05, 0.15, ctx.fade * 0.4)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local img = loadTagImage(MA.TAG.LIGHTNING)
  local cols = { {18, 16}, {40, -16}, {70, 24}, {95, 0} }
  for i = 1, #cols do
    local start, ox = cols[i][1], cols[i][2]
    for seg = 0, 2 do
      local age = frame - (start + seg)
      if age >= 0 and age < 10 then
        local y = ctx.ty - 36 + seg * 16
        local a = ctx.fade * (1 - age / 10)
        if not (img and drawTinted(img, ctx.tx + ox, y, 1.0, 1, 1, 0.55, a)) then
          G.setColor(1, 1, 0.6, a)
          G.rectangle("fill", ctx.tx + ox - 2, y - 8, 4, 16)
        end
      end
    end
  end
  if frame >= 100 and frame < 115 then
    local a = ctx.fade * 0.45 * math.sin((frame - 100) / 15 * math.pi)
    G.setColor(1, 1, 1, a)
    G.rectangle("fill", 0, 0, 240, 160)
  end
end

function FX.blizzard(G, frame, ctx)
  if frame < 80 then
    G.setColor(0.55, 0.7, 0.9, ctx.fade * 0.18)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local img = loadTagImage(MA.TAG.ICE_CRYSTALS)
  for i = 0, 28 do
    local start = 8 + i * 3
    local age = frame - start
    if age >= 0 and age <= 28 then
      local u = age / 28
      local side = ((i % 5) - 2) * 10
      local x = lerp(ctx.ax, ctx.tx + side, u)
      local y = lerp(ctx.ay - 8, ctx.ty + side * 0.4, u)
      local a = ctx.fade * (1 - u * 0.2)
      local s = (i % 2 == 0) and 0.7 or 0.45
      if not (img and drawTinted(img, x, y, s, 0.85, 0.95, 1, a)) then
        G.setColor(0.9, 0.95, 1, a)
        circle(G, x, y, (i % 2 == 0) and 4 or 2)
      end
    end
  end
  if frame >= 70 and frame < 95 then
    local t = (frame - 70) / 25
    G.setColor(0.7, 0.9, 1, ctx.fade * 0.25 * (1 - t))
    circle(G, ctx.tx, ctx.ty, 12 + t * 16)
  end
end

function FX.psychic(G, frame, ctx)
  if frame < 50 then
    G.setColor(0.55, 0.25, 0.75, ctx.fade * 0.18)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local t = frame / 60
  for i = 0, 5 do
    local ang = t * 8 + i * 1.05
    local rad = 10 + math.sin(frame / 4 + i) * 6
    G.setColor(0.95, 0.55, 1, ctx.fade * 0.5 * (1 - t * 0.4))
    circle(G, ctx.tx + math.cos(ang) * rad, ctx.ty + math.sin(ang) * rad * 0.7, 3)
  end
  if frame >= 16 and frame < 45 then
    local a = ctx.fade * 0.3 * math.sin((frame - 16) / 29 * math.pi)
    G.setColor(1, 1, 1, a)
    circle(G, ctx.tx, ctx.ty, 16)
  end
end

function FX.crunch(G, frame, ctx)
  if frame < 60 then
    G.setColor(0, 0, 0, ctx.fade * 0.4)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local img = loadTagImage(MA.TAG.SHARP_TEETH)
  local bites = { {0, -10, 0}, {28, 8, 0} }
  for bi = 1, #bites do
    local start, ox = bites[bi][1], bites[bi][2]
    local age = frame - start
    if age >= 0 and age < 18 then
      local u = clamp01(age / 10)
      local gap = (1 - u) * 24
      local a = ctx.fade
      local topY = ctx.ty - 6 - gap
      local botY = ctx.ty + 6 + gap
      if not (img and drawTinted(img, ctx.tx + ox, topY, 1.0, 1, 1, 1, a)) then
        G.setColor(0.95, 0.95, 0.98, a)
        G.rectangle("fill", ctx.tx + ox - 10, topY - 4, 20, 6)
        G.rectangle("fill", ctx.tx + ox - 10, botY - 2, 20, 6)
      else
        drawTinted(img, ctx.tx + ox, botY, 1.0, 1, 1, 1, a)
      end
      if age >= 8 and age < 18 then
        hitSplat(G, ctx.tx + ox, ctx.ty, (age - 8) / 10, ctx.fade, true)
      end
    end
  end
end

function FX.dragon_claw(G, frame, ctx)
  if frame < 50 then
    G.setColor(0.85, 0.15, 0.1, ctx.fade * 0.15)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local ember = loadTagImage(MA.TAG.SMALL_EMBER)
  for i = 0, 14 do
    local start = i * 2
    local age = frame - start
    if age >= 0 and age < 20 then
      local u = age / 20
      local ang = i * 0.5
      local x = ctx.ax + math.cos(ang) * (10 + u * 18)
      local y = ctx.ay + math.sin(ang) * (8 + u * 12) - u * 6
      local a = ctx.fade * (1 - u)
      if not (ember and drawTinted(ember, x, y, 0.65, 1, 0.45, 0.1, a)) then
        G.setColor(1, 0.4, 0.1, a)
        circle(G, x, y, 3)
      end
    end
  end
  local claw = loadTagImage(MA.TAG.CLAW_SLASH) or loadTagImage(MA.TAG.SCRATCH)
  local bursts = { {28, -10}, {48, 10} }
  for bi = 1, #bursts do
    local start, side = bursts[bi][1], bursts[bi][2]
    local age = frame - start
    if age >= 0 and age < 14 then
      local a = ctx.fade * (1 - age / 14)
      if not (claw and drawTinted(claw, ctx.tx + side, ctx.ty, 1.05, 1, 0.85, 0.7, a)) then
        scratchMarks(G, ctx.tx + side, ctx.ty, age / 14, a, ctx.onEnemy)
      end
    end
  end
end

function FX.slam(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SLAM_HIT)
  if frame >= 2 and frame < 16 then
    local a = ctx.fade * (1 - (frame - 2) / 14)
    if not (img and drawTinted(img, ctx.tx, ctx.ty, 1.1, 1, 1, 1, a)) then
      G.setColor(0.95, 0.9, 0.7, a)
      local dir = ctx.onEnemy and 1 or -1
      G.rectangle("fill", ctx.tx - 4, ctx.ty - 16, 8, 28)
      G.rectangle("fill", ctx.tx - 14 * dir, ctx.ty - 4, 20 * dir, 6)
    end
  end
  if frame >= 4 and frame < 20 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 4) / 12, ctx.fade, true)
  end
end

function FX.facade(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SWEAT_DROP)
  for i = 0, 5 do
    local start = 4 + i * 10
    local age = frame - start
    if age >= 0 and age < 16 then
      local u = age / 16
      local x = ctx.ax + ((i % 3) - 1) * 10
      local y = ctx.ay - 8 + u * 18
      local a = ctx.fade * (1 - u)
      if not (img and drawTinted(img, x, y, 0.6, 0.7, 0.9, 1, a)) then
        G.setColor(0.6, 0.85, 1, a)
        circle(G, x, y, 2)
      end
    end
  end
  local pulse = 0.5 + 0.5 * math.sin(frame / 6)
  G.setColor(1, 0.35, 0.25, ctx.fade * 0.15 * pulse)
  circle(G, ctx.ax, ctx.ay, 16)
end

function FX.return_(G, frame, ctx)
  -- dips via offsets; multi mid-power hits
  local hits = { {28, -10, -8}, {40, 10, 10}, {52, 3, -5}, {64, -5, 3} }
  for i = 1, #hits do
    local start, ox, oy = hits[i][1], hits[i][2], hits[i][3]
    local age = frame - start
    if age >= 0 and age < 10 then
      hitSplat(G, ctx.tx + ox, ctx.ty + oy, age / 10, ctx.fade, true)
    end
  end
end
FX["return"] = FX.return_

function FX.frustration(G, frame, ctx)
  if frame < 40 then
    G.setColor(1, 0.15, 0.1, ctx.fade * 0.2)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local anger = loadTagImage(MA.TAG.ANGER)
  local veins = { {18, 20, -28}, {32, 20, -28} }
  for i = 1, #veins do
    local start, ox, oy = veins[i][1], veins[i][2], veins[i][3]
    local age = frame - start
    if age >= 0 and age < 14 then
      local a = ctx.fade * (1 - age / 14)
      if not (anger and drawTinted(anger, ctx.ax + ox, ctx.ay + oy, 0.9, 1, 0.3, 0.2, a)) then
        G.setColor(1, 0.25, 0.15, a)
        G.rectangle("fill", ctx.ax + ox - 2, ctx.ay + oy - 6, 4, 12)
        G.rectangle("fill", ctx.ax + ox - 6, ctx.ay + oy - 2, 12, 3)
      end
    end
  end
  local hits = { {48, 0, 0}, {56, 24, 8}, {64, -24, -16}, {72, 8, 4}, {80, -16, 12} }
  for i = 1, #hits do
    local start, ox, oy = hits[i][1], hits[i][2], hits[i][3]
    local age = frame - start
    if age >= 0 and age < 8 then
      hitSplat(G, ctx.tx + ox, ctx.ty + oy, age / 8, ctx.fade, true)
    end
  end
end

function FX.hidden_power(G, frame, ctx)
  local img = loadTagImage(MA.TAG.RED_ORB) or loadTagImage(MA.TAG.ORBS)
  if frame < 50 then
    for i = 0, 5 do
      local ang = frame * 0.15 + i * (math.pi * 2 / 6)
      local rad = 18 - (frame / 50) * 6
      local x = ctx.ax + math.cos(ang) * rad
      local y = ctx.ay + math.sin(ang) * rad * 0.7
      local a = ctx.fade
      if not (img and drawTinted(img, x, y, 0.7, 1, 0.35, 0.35, a)) then
        G.setColor(1, 0.35, 0.35, a)
        circle(G, x, y, 3)
      end
    end
  else
    for i = 0, 7 do
      local age = frame - 52
      if age >= 0 and age <= 40 then
        local u = age / 40
        local ang = i * (math.pi * 2 / 8)
        local x = lerp(ctx.ax, ctx.tx + math.cos(ang) * 20, u)
        local y = lerp(ctx.ay, ctx.ty + math.sin(ang) * 14, u)
        local a = ctx.fade * (1 - u * 0.3)
        if not (img and drawTinted(img, x, y, 0.75, 1, 0.4, 0.35, a)) then
          G.setColor(1, 0.4, 0.35, a)
          circle(G, x, y, 3)
        end
      end
    end
  end
end

function FX.overheat(G, frame, ctx)
  if frame < 80 then
    local u = math.min(1, frame / 20)
    G.setColor(0.9, 0.1, 0.05, ctx.fade * 0.3 * u)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local ember = loadTagImage(MA.TAG.SMALL_EMBER)
  if frame >= 30 then
    for i = 0, 17 do
      local start = 30 + (i % 6) * 2
      local age = frame - start
      if age >= 0 and age < 28 then
        local u = age / 28
        local ang = i * 0.35
        local x = ctx.ax + math.cos(ang) * (8 + u * 50)
        local y = ctx.ay + math.sin(ang) * (6 + u * 36) - u * 10
        local a = ctx.fade * (1 - u)
        if not (ember and drawTinted(ember, x, y, 0.8, 1, 0.4, 0.1, a)) then
          G.setColor(1, 0.35, 0.08, a)
          circle(G, x, y, 4 - u * 2)
        end
      end
    end
  end
  if frame >= 55 and frame < 80 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 55) / 16, ctx.fade * 0.7, true)
  end
end

function FX.eruption(G, frame, ctx)
  if frame < 40 then
    G.setColor(0.9, 0.15, 0.05, ctx.fade * 0.25 * (frame / 40))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local rock = loadTagImage(MA.TAG.ROCKS) or loadTagImage(MA.TAG.SMALL_EMBER)
  if frame >= 50 then
    local rocks = {
      {50, 0}, {54, 30}, {58, -40}, {62, 20}, {66, -20}, {70, 40},
    }
    for i = 1, #rocks do
      local start, ox = rocks[i][1], rocks[i][2]
      local age = frame - start
      if age >= 0 and age < 40 then
        local u = age / 40
        local x = ctx.tx + ox
        local y = lerp(-20, ctx.ty + 10, u)
        local a = ctx.fade * (1 - u * 0.2)
        if not (rock and drawTinted(rock, x, y, 0.85, 1, 0.45, 0.2, a)) then
          G.setColor(0.9, 0.35, 0.15, a)
          G.rectangle("fill", x - 4, y - 4, 8, 8)
        end
      end
    end
  end
  if frame >= 80 then
    screenShakeFlash(G, frame, ctx, 6)
  end
end

function FX.focus_punch(G, frame, ctx)
  -- Compressed charge (BG darken + fist windup) then multi-splat hit (Move_FOCUS_PUNCH)
  if frame < 28 then
    local u = frame / 28
    G.setColor(0, 0, 0, ctx.fade * 0.4 * u)
    G.rectangle("fill", 0, 0, 240, 160)
    local fist = loadTagImage(MA.TAG.HANDS_FEET)
    local a = ctx.fade * (0.4 + 0.6 * u)
    local sc = 0.7 + u * 0.6
    if not (fist and drawTinted(fist, ctx.ax, ctx.ay - 8, sc, 1, 0.85, 0.6, a)) then
      G.setColor(1, 0.8, 0.5, a)
      circle(G, ctx.ax, ctx.ay - 8, 6 + u * 4)
    end
  else
    local lf = frame - 28
    if lf < 12 then
      G.setColor(0.15, 0.05, 0.05, ctx.fade * 0.25 * (1 - lf / 12))
      G.rectangle("fill", 0, 0, 240, 160)
    end
    fistBurst(G, lf, ctx, {
      {8, -10, -8}, {16, 10, 2}, {24, 10, -6}, {32, 0, 8},
    })
  end
end

function FX.revenge(G, frame, ctx)
  local scratch = loadTagImage(MA.TAG.PURPLE_SCRATCH) or loadTagImage(MA.TAG.SCRATCH)
  if frame < 16 then
    local a = ctx.fade * (1 - frame / 16)
    if not (scratch and drawTinted(scratch, ctx.ax + 10, ctx.ay - 10, 1.0, 0.7, 0.3, 0.85, a)) then
      G.setColor(0.7, 0.25, 0.85, a)
      scratchMarks(G, ctx.ax + 8, ctx.ay - 8, frame / 16, a, ctx.onEnemy)
    end
  end
  if frame >= 20 and frame < 34 then
    local a = ctx.fade * (1 - (frame - 20) / 14)
    if not (scratch and drawTinted(scratch, ctx.tx + 10, ctx.ty - 10, 1.05, 0.7, 0.3, 0.85, a)) then
      scratchMarks(G, ctx.tx, ctx.ty, (frame - 20) / 14, a, ctx.onEnemy)
    end
  end
  if frame >= 34 and frame < 50 then
    hitSplat(G, ctx.tx - 8, ctx.ty - 6, (frame - 34) / 10, ctx.fade, true)
    if frame >= 42 then
      hitSplat(G, ctx.tx + 8, ctx.ty + 6, (frame - 42) / 10, ctx.fade, true)
    end
  end
end

function FX.endeavor(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SWEAT_DROP)
  for i = 0, 3 do
    local start = 2 + i * 6
    local age = frame - start
    if age >= 0 and age < 14 then
      local u = age / 14
      local x = ctx.ax + ((i % 2) * 2 - 1) * 8
      local y = ctx.ay - 6 + u * 14
      local a = ctx.fade * (1 - u)
      if not (img and drawTinted(img, x, y, 0.55, 0.7, 0.9, 1, a)) then
        G.setColor(0.65, 0.85, 1, a)
        circle(G, x, y, 2)
      end
    end
  end
  if frame >= 12 and frame < 24 then
    hitSplat(G, ctx.tx + 10, ctx.ty - 10, (frame - 12) / 10, ctx.fade, true)
  end
  if frame >= 30 and frame < 42 then
    hitSplat(G, ctx.tx - 10, ctx.ty + 10, (frame - 30) / 10, ctx.fade, true)
  end
end

function FX.fake_out(G, frame, ctx)
  if frame < 12 then
    local a = ctx.fade * (1 - math.abs(frame - 6) / 6) * 0.7
    G.setColor(1, 1, 1, a)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  if frame >= 14 and frame < 30 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 14) / 12, ctx.fade, true)
  end
  if frame >= 28 then
    local a = ctx.fade * (1 - (frame - 28) / 12) * 0.5
    G.setColor(1, 1, 1, a)
    G.rectangle("fill", 0, 0, 240, 160)
  end
end

function FX.will_o_wisp(G, frame, ctx)
  local orb = loadTagImage(MA.TAG.WISP_ORB) or loadTagImage(MA.TAG.SMALL_EMBER)
  for i = 0, 3 do
    local start = i * 3
    local age = frame - start
    if age >= 0 and age <= 48 then
      local u = age / 48
      local x = lerp(ctx.ax, ctx.tx, u)
      local y = lerp(ctx.ay, ctx.ty, u) + math.sin(u * 6 + i) * 8
      local a = ctx.fade
      if not (orb and drawTinted(orb, x, y, 0.8, 0.4, 1, 0.7, a)) then
        G.setColor(0.55, 0.85, 1, a)
        circle(G, x, y, 4)
        G.setColor(0.9, 0.95, 1, a * 0.5)
        circle(G, x, y, 2)
      end
    end
  end
  if frame >= 50 then
    local fire = loadTagImage(MA.TAG.WISP_FIRE) or loadTagImage(MA.TAG.SMALL_EMBER)
    for i = 0, 5 do
      local ang = i * (math.pi * 2 / 6) + frame * 0.1
      local a = ctx.fade * (1 - (frame - 50) / 40)
      local x = ctx.tx + math.cos(ang) * 14
      local y = ctx.ty + math.sin(ang) * 10
      if not (fire and drawTinted(fire, x, y, 0.7, 0.45, 0.9, 1, a)) then
        G.setColor(0.5, 0.85, 1, a)
        circle(G, x, y, 3)
      end
    end
  end
end

function FX.thunder_wave(G, frame, ctx)
  if frame < 16 then
    G.setColor(0, 0, 0, ctx.fade * 0.25 * (frame / 16))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  if frame >= 10 and frame < 30 then
    local a = ctx.fade * (1 - (frame - 10) / 20)
    G.setColor(1, 1, 0.55, a)
    G.rectangle("fill", ctx.tx - 1, 0, 3, ctx.ty)
  end
  local spark = loadTagImage(MA.TAG.SPARK)
  local ys = { -16, 0, 16 }
  for i = 1, #ys do
    local start = 28 + (i - 1) * 4
    local age = frame - start
    if age >= 0 and age < 16 then
      local a = ctx.fade * (1 - age / 16)
      local x, y = ctx.tx - 12, ctx.ty + ys[i]
      if not (spark and drawTinted(spark, x, y, 0.8, 1, 1, 0.4, a)) then
        G.setColor(1, 0.95, 0.4, a)
        G.rectangle("fill", x - 6, y - 1, 12, 2)
        G.rectangle("fill", x - 1, y - 6, 2, 12)
      end
    end
  end
end

function FX.attract(G, frame, ctx)
  local img = loadTagImage(MA.TAG.RED_HEART)
  if frame >= 12 and frame < 40 then
    local u = (frame - 12) / 28
    local x = lerp(ctx.ax, ctx.tx, u)
    local y = lerp(ctx.ay, ctx.ty - 8, u) - math.sin(u * math.pi) * 12
    local a = ctx.fade
    if not (img and drawTinted(img, x, y, 0.9, 1, 0.4, 0.55, a)) then
      G.setColor(1, 0.35, 0.5, a)
      circle(G, x, y, 5)
    end
  end
  if frame >= 40 then
    local offs = { {20, -20}, {-30, -28}, {16, -10}, {28, -26}, {-18, -14}, {-26, -22} }
    for i = 1, #offs do
      local start = 40 + (i - 1) * 4
      local age = frame - start
      if age >= 0 and age < 28 then
        local u = age / 28
        local x = ctx.tx + offs[i][1] * (1 - u * 0.3)
        local y = ctx.ty + offs[i][2] - u * 10
        local a = ctx.fade * (1 - u)
        if not (img and drawTinted(img, x, y, 0.55, 1, 0.4, 0.55, a)) then
          G.setColor(1, 0.4, 0.55, a)
          circle(G, x, y, 3)
        end
      end
    end
  end
end

function FX.safeguard(G, frame, ctx)
  local img = loadTagImage(MA.TAG.GUARD_RING) or loadTagImage(MA.TAG.THIN_RING)
  for i = 0, 2 do
    local start = i * 4
    local age = frame - start
    if age >= 0 and age < 28 then
      local u = age / 28
      local a = ctx.fade * (1 - u * 0.4)
      local s = 0.7 + u * 0.8
      if not (img and drawTinted(img, ctx.ax, ctx.ay, s, 0.7, 0.95, 0.85, a)) then
        G.setColor(0.65, 0.95, 0.8, a * 0.55)
        circle(G, ctx.ax, ctx.ay, 12 + u * 14)
      end
    end
  end
  if frame >= 30 then
    local a = ctx.fade * 0.35 * math.sin((frame - 30) / 20 * math.pi)
    G.setColor(1, 1, 1, a)
    circle(G, ctx.ax, ctx.ay, 20)
  end
end

function FX.light_screen(G, frame, ctx)
  barrierWall(G, frame, ctx, {0.45, 0.95, 0.55}, 70, MA.TAG.GREEN_LIGHT_WALL)
end

function FX.reflect(G, frame, ctx)
  barrierWall(G, frame, ctx, {0.45, 0.7, 1}, 70, MA.TAG.BLUE_LIGHT_WALL)
end

function FX.spikes(G, frame, ctx)
  local img = loadTagImage(MA.TAG.SPIKES)
  local spikes = { {0, 0}, {10, -18}, {20, 18} }
  for i = 1, #spikes do
    local start, ox = spikes[i][1], spikes[i][2]
    local age = frame - start
    if age >= 0 and age <= 36 then
      local u = age / 36
      local x = lerp(ctx.ax + 8, ctx.tx + ox, u)
      local y = lerp(ctx.ay, ctx.ty + 16, u)
      local a = ctx.fade
      if not (img and drawTinted(img, x, y, 0.85, 0.75, 0.75, 0.7, a)) then
        G.setColor(0.7, 0.7, 0.65, a)
        if G.polygon then
          G.polygon("fill", x, y - 6, x - 4, y + 4, x + 4, y + 4)
        else
          G.rectangle("fill", x - 3, y - 4, 6, 8)
        end
      end
    end
  end
end



---------------------------------------------------------------------------
-- Wave-4 FX drawers
---------------------------------------------------------------------------

function FX.solar_beam_charge(G, frame, ctx)
  -- Absorb yellow-green orbs into attacker (Move_SOLAR_BEAM charge)
  local img = loadTagImage(MA.TAG.ORBS)
  G.setColor(0.95, 0.95, 0.4, ctx.fade * 0.12 * math.min(1, frame / 10))
  G.rectangle("fill", 0, 0, 240, 160)
  local offs = {
    {40,40},{-40,-40},{0,40},{0,-40},{40,-20},{40,20},{-40,-20},{-40,20},
    {-20,30},{20,-30},{-20,-30},{20,30},{-40,0},{40,0},
  }
  for i, o in ipairs(offs) do
    local start = (i - 1) * 2
    local age = frame - start
    if age >= 0 and age < 18 then
      local u = age / 18
      local x = ctx.ax + o[1] * (1 - u)
      local y = ctx.ay + o[2] * (1 - u)
      local a = ctx.fade * (1 - u * 0.3)
      if not (img and drawTinted(img, x, y, 0.7, 0.85, 1, 0.35, a)) then
        G.setColor(0.7, 1, 0.35, a)
        circle(G, x, y, 3)
      end
    end
  end
end

function FX.solar_beam_hit(G, frame, ctx)
  local img = loadTagImage(MA.TAG.ORBS)
  G.setColor(0.5, 1, 0.3, ctx.fade * 0.22)
  for s = 0, 14 do
    local u = s / 14
    circle(G, lerp(ctx.ax, ctx.tx, u), lerp(ctx.ay, ctx.ty, u), 6)
  end
  for i = 0, 18 do
    local u = i / 18
    local x = lerp(ctx.ax, ctx.tx, u)
    local y = lerp(ctx.ay, ctx.ty, u)
    local a = ctx.fade * 0.85
    if not (img and drawTinted(img, x, y, 0.9, 0.55, 1, 0.3, a)) then
      G.setColor(0.45, 1, 0.25, a)
      circle(G, x, y, 5)
    end
  end
  if frame > 16 then
    hitSplat(G, ctx.tx, ctx.ty, ((frame - 16) % 14) / 14, ctx.fade * 0.55, true)
  end
end

function FX.fly_charge(G, frame, ctx)
  -- Rise with round shadow (Move_FLY charge)
  local img = loadTagImage(MA.TAG.ROUND_SHADOW)
  local u = frame / 30
  local a = ctx.fade * (1 - u * 0.7)
  local y = ctx.ay - u * 40
  if not (img and drawTinted(img, ctx.ax, y, 1.0 + u * 0.4, 0.1, 0.1, 0.15, a)) then
    G.setColor(0.05, 0.05, 0.1, a * 0.7)
    circle(G, ctx.ax, y, 10 + u * 6)
  end
end

function FX.fly_hit(G, frame, ctx)
  local img = loadTagImage(MA.TAG.ROUND_SHADOW)
  if frame < 18 then
    local u = frame / 18
    local y = ctx.ty - 50 + u * 50
    local a = ctx.fade
    if not (img and drawTinted(img, ctx.tx, y, 1.1, 0.1, 0.1, 0.15, a)) then
      G.setColor(0.05, 0.05, 0.12, a * 0.6)
      circle(G, ctx.tx, y, 12)
    end
  end
  if frame >= 16 and frame < 36 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 16) / 14, ctx.fade, true)
  end
end

function FX.dive_charge(G, frame, ctx)
  local splash = loadTagImage(MA.TAG.SPLASH) or loadTagImage(MA.TAG.SMALL_BUBBLES)
  local u = math.min(1, frame / 20)
  G.setColor(0.2, 0.45, 0.85, ctx.fade * 0.25 * u)
  G.rectangle("fill", ctx.ax - 30, ctx.ay + 4, 60, 40)
  for i = 0, 5 do
    local age = frame - i * 6
    if age >= 0 and age < 16 then
      local t = age / 16
      local x = ctx.ax + (i - 2.5) * 6
      local y = ctx.ay + 8 + t * 10
      local a = ctx.fade * (1 - t)
      if not (splash and drawTinted(splash, x, y, 0.55, 0.5, 0.8, 1, a)) then
        G.setColor(0.55, 0.85, 1, a)
        circle(G, x, y, 3)
      end
    end
  end
end

function FX.dive_hit(G, frame, ctx)
  local bub = loadTagImage(MA.TAG.SMALL_BUBBLES) or loadTagImage(MA.TAG.WATER_IMPACT)
  for burst = 0, 4 do
    local bstart = burst * 6
    for i = 0, 2 do
      local age = frame - (bstart + i)
      if age >= 0 and age < 14 then
        local u = age / 14
        local x = ctx.tx + (i - 1) * 8
        local y = ctx.ty + 10 - u * 18
        local a = ctx.fade * (1 - u)
        if not (bub and drawTinted(bub, x, y, 0.6, 0.5, 0.85, 1, a)) then
          G.setColor(0.5, 0.8, 1, a)
          circle(G, x, y, 3)
        end
      end
    end
  end
  if frame >= 28 and frame < 50 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 28) / 14, ctx.fade, true)
  end
end

function FX.skull_bash_charge(G, frame, ctx)
  -- Tuck bob forward/back (Move_SKULL_BASH charge)
  local pulse = math.sin(frame / 6)
  G.setColor(0.9, 0.75, 0.4, ctx.fade * 0.15 * (0.5 + 0.5 * pulse))
  circle(G, ctx.ax, ctx.ay, 16)
end

function FX.skull_bash_hit(G, frame, ctx)
  if frame < 12 then
    G.setColor(1, 1, 1, ctx.fade * 0.35 * (1 - frame / 12))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  if frame >= 6 and frame < 40 then
    hitSplat(G, ctx.tx, ctx.ty, ((frame - 6) % 12) / 12, ctx.fade, true)
  end
end

function FX.recover(G, frame, ctx)
  local orb = loadTagImage(MA.TAG.ORBS)
  local star = loadTagImage(MA.TAG.BLUE_STAR)
  local offs = {{40,-10},{-35,-10},{15,-40},{-10,-32},{25,-20},{-40,-20},{5,-40}}
  for i, o in ipairs(offs) do
    for rep = 0, 2 do
      local start = rep * 22 + (i - 1) * 3
      local age = frame - start
      if age >= 0 and age < 16 then
        local u = age / 16
        local x = ctx.ax + o[1] * (1 - u)
        local y = ctx.ay + o[2] * (1 - u)
        local a = ctx.fade
        if not (orb and drawTinted(orb, x, y, 0.65, 0.55, 0.95, 1, a)) then
          G.setColor(0.55, 0.85, 1, a)
          circle(G, x, y, 3)
        end
      end
    end
  end
  if frame >= 45 then
    local a = ctx.fade * (1 - (frame - 45) / 25)
    if not (star and drawTinted(star, ctx.ax, ctx.ay - 12, 1.0, 0.6, 0.9, 1, a)) then
      G.setColor(0.7, 0.95, 1, a)
      circle(G, ctx.ax, ctx.ay - 12, 6)
    end
  end
end

function FX.swords_dance(G, frame, ctx)
  local sword = loadTagImage(MA.TAG.SWORD)
  local a = ctx.fade
  local ang = frame * 0.25
  for i = 0, 2 do
    local r = 18
    local x = ctx.ax + math.cos(ang + i * 2.1) * r
    local y = ctx.ay + math.sin(ang + i * 2.1) * r * 0.6
    if not (sword and drawTinted(sword, x, y, 0.9, 1, 1, 1, a)) then
      G.setColor(0.85, 0.9, 1, a)
      G.rectangle("fill", x - 2, y - 10, 4, 20)
    end
  end
end

function FX.dragon_dance(G, frame, ctx)
  local orb = loadTagImage(MA.TAG.HOLLOW_ORB) or loadTagImage(MA.TAG.ORBS)
  for i = 0, 5 do
    local ang = frame * 0.12 + i * (math.pi * 2 / 6)
    local rad = 14 + 4 * math.sin(frame / 8 + i)
    local x = ctx.ax + math.cos(ang) * rad
    local y = ctx.ay + math.sin(ang) * rad * 0.7
    local a = ctx.fade * 0.9
    if not (orb and drawTinted(orb, x, y, 0.7, 0.85, 0.35, 1, a)) then
      G.setColor(0.9, 0.4, 0.95, a)
      circle(G, x, y, 3)
    end
  end
  G.setColor(0.7, 0.2, 0.85, ctx.fade * 0.12)
  circle(G, ctx.ax, ctx.ay, 20)
end

function FX.rain_dance(G, frame, ctx)
  G.setColor(0, 0, 0.15, ctx.fade * 0.35 * math.min(1, frame / 10))
  G.rectangle("fill", 0, 0, 240, 160)
  local drop = loadTagImage(MA.TAG.RAIN_DROPS)
  for i = 0, 24 do
    local x = (i * 37 + frame * 2) % 240
    local y = (i * 53 + frame * 5) % 140
    local a = ctx.fade * 0.7
    if not (drop and drawTinted(drop, x, y, 0.5, 0.55, 0.75, 1, a)) then
      G.setColor(0.45, 0.65, 1, a)
      G.rectangle("fill", x, y, 2, 6)
    end
  end
end

function FX.sunny_day(G, frame, ctx)
  G.setColor(1, 0.9, 0.4, ctx.fade * 0.22 * math.min(1, frame / 10))
  G.rectangle("fill", 0, 0, 240, 160)
  local sun = loadTagImage(MA.TAG.SUNLIGHT)
  for i = 0, 3 do
    local start = i * 6
    local age = frame - start
    if age >= 0 and age < 40 then
      local a = ctx.fade * (1 - age / 50)
      local x = 40 + i * 50
      local y = 20 + (age % 20)
      if not (sun and drawTinted(sun, x, y, 1.0, 1, 0.95, 0.5, a)) then
        G.setColor(1, 0.95, 0.4, a)
        circle(G, x, y, 8)
      end
    end
  end
end

function FX.sandstorm_move(G, frame, ctx)
  local dirt = loadTagImage(MA.TAG.MUD_SAND)
  G.setColor(0.55, 0.45, 0.25, ctx.fade * 0.2)
  G.rectangle("fill", 0, 0, 240, 160)
  for i = 0, 30 do
    local x = (i * 41 + frame * 4) % 250 - 5
    local y = (i * 29 + frame * 2) % 150
    local a = ctx.fade * 0.65
    if not (dirt and drawTinted(dirt, x, y, 0.45, 0.7, 0.55, 0.3, a)) then
      G.setColor(0.7, 0.55, 0.3, a)
      circle(G, x, y, 2)
    end
  end
end

function FX.hail_move(G, frame, ctx)
  local hail = loadTagImage(MA.TAG.HAIL) or loadTagImage(MA.TAG.ICE_CRYSTALS)
  G.setColor(0.55, 0.7, 0.95, ctx.fade * 0.15)
  G.rectangle("fill", 0, 0, 240, 160)
  for i = 0, 20 do
    local x = (i * 47 + frame) % 240
    local y = (i * 31 + frame * 4) % 150
    local a = ctx.fade * 0.8
    if not (hail and drawTinted(hail, x, y, 0.5, 0.85, 0.95, 1, a)) then
      G.setColor(0.85, 0.95, 1, a)
      G.rectangle("fill", x, y, 3, 3)
    end
  end
end

function FX.rapid_spin(G, frame, ctx)
  local spin = loadTagImage(MA.TAG.RAPID_SPIN) or loadTagImage(MA.TAG.SPEED_DUST)
  for i = 0, 5 do
    local ang = frame * 0.4 + i
    local rad = 8 + (frame % 10)
    local x = ctx.ax + math.cos(ang) * rad
    local y = ctx.ay + math.sin(ang) * rad
    local a = ctx.fade * 0.8
    if not (spin and drawTinted(spin, x, y, 0.6, 1, 1, 1, a)) then
      G.setColor(0.9, 0.9, 0.95, a)
      circle(G, x, y, 2)
    end
  end
  if frame >= 28 and frame < 48 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 28) / 14, ctx.fade, true)
  end
end

function FX.explosion(G, frame, ctx)
  local exp = loadTagImage(MA.TAG.EXPLOSION)
  local spots = {{0,0},{24,-24},{-16,16},{-24,-12},{16,16},{0,-20},{-20,0},{20,10}}
  for i, s in ipairs(spots) do
    local start = (i - 1) * 6
    local age = frame - start
    if age >= 0 and age < 18 then
      local u = age / 18
      local a = ctx.fade * (1 - u)
      local x = ctx.ax + s[1]
      local y = ctx.ay + s[2]
      if not (exp and drawTinted(exp, x, y, 0.8 + u * 0.5, 1, 0.7, 0.3, a)) then
        G.setColor(1, 0.55, 0.2, a)
        circle(G, x, y, 6 + u * 10)
      end
    end
  end
  if frame > 20 then
    G.setColor(1, 1, 1, ctx.fade * 0.25 * math.sin((frame - 20) / 40 * math.pi))
    G.rectangle("fill", 0, 0, 240, 160)
  end
end

function FX.destiny_bond(G, frame, ctx)
  G.setColor(0.05, 0, 0.1, ctx.fade * 0.45 * math.min(1, frame / 12))
  G.rectangle("fill", 0, 0, 240, 160)
  local ghost = loadTagImage(MA.TAG.GHOSTLY_SPIRIT) or loadTagImage(MA.TAG.SHADOW_BALL)
  local u = math.min(1, frame / 48)
  local x = lerp(ctx.ax, ctx.tx, u)
  local y = lerp(ctx.ay, ctx.ty, u)
  local a = ctx.fade
  if not (ghost and drawTinted(ghost, x, y, 1.0, 0.7, 0.5, 1, a)) then
    G.setColor(0.6, 0.4, 0.85, a)
    circle(G, x, y, 10)
  end
  if frame >= 48 then
    G.setColor(0.7, 0.2, 0.85, ctx.fade * 0.2)
    circle(G, ctx.tx, ctx.ty, 18)
  end
end

function FX.counter(G, frame, ctx)
  if frame < 10 then
    G.setColor(1, 0.3, 0.2, ctx.fade * 0.25)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  if frame >= 8 and frame < 32 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 8) / 14, ctx.fade, true)
  end
end

function FX.mirror_coat(G, frame, ctx)
  if frame < 14 then
    G.setColor(0.4, 0.7, 1, ctx.fade * 0.3)
    G.rectangle("fill", 0, 0, 240, 160)
  end
  local ring = loadTagImage(MA.TAG.THIN_RING)
  if frame < 20 then
    local a = ctx.fade * (1 - frame / 20)
    if not (ring and drawTinted(ring, ctx.ax, ctx.ay, 1.2, 0.5, 0.8, 1, a)) then
      G.setColor(0.5, 0.85, 1, a)
      circle(G, ctx.ax, ctx.ay, 14)
    end
  end
  if frame >= 16 and frame < 40 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 16) / 14, ctx.fade, true)
  end
end

function FX.metronome(G, frame, ctx)
  local finger = loadTagImage(MA.TAG.FINGER)
  local a = ctx.fade
  local bob = math.sin(frame / 5) * 4
  if not (finger and drawTinted(finger, ctx.ax + 8, ctx.ay - 16 + bob, 1.0, 1, 1, 1, a)) then
    G.setColor(1, 0.9, 0.7, a)
    G.rectangle("fill", ctx.ax + 4, ctx.ay - 20 + bob, 6, 14)
    circle(G, ctx.ax + 7, ctx.ay - 22 + bob, 4)
  end
end

function FX.splash(G, frame, ctx)
  local bob = math.abs(math.sin(frame / 8)) * 10
  G.setColor(0.6, 0.85, 1, ctx.fade * 0.2)
  circle(G, ctx.ax, ctx.ay + 12 - bob * 0.3, 10)
  -- visual bounce via offsets; draw a little sweat/splash
  local img = loadTagImage(MA.TAG.SPLASH) or loadTagImage(MA.TAG.SWEAT_DROP)
  if frame % 16 < 8 then
    local a = ctx.fade * 0.7
    if not (img and drawTinted(img, ctx.ax, ctx.ay - bob, 0.7, 0.7, 0.9, 1, a)) then
      G.setColor(0.7, 0.9, 1, a)
      circle(G, ctx.ax, ctx.ay - bob, 4)
    end
  end
end

function FX.struggle(G, frame, ctx)
  fistBurst(G, frame, ctx, {
    {4, -8, -4}, {16, 8, 4}, {28, 0, 0},
  })
end

function FX.transform(G, frame, ctx)
  local u = frame / 50
  G.setColor(1, 1, 1, ctx.fade * (u < 0.5 and u * 2 or (1 - u) * 2) * 0.55)
  G.rectangle("fill", 0, 0, 240, 160)
  local a = ctx.fade * (1 - math.abs(u - 0.5) * 2)
  G.setColor(0.8, 0.9, 1, a)
  circle(G, ctx.ax, ctx.ay, 12 + u * 8)
end



---------------------------------------------------------------------------
-- Wave-5 FX drawers
---------------------------------------------------------------------------

function FX.sky_attack_charge(G, frame, ctx)
  local u = math.min(1, frame / 20)
  G.setColor(1, 1, 0.85, ctx.fade * 0.18 * u)
  G.rectangle("fill", 0, 0, 240, 160)
  local pulse = 0.5 + 0.5 * math.sin(frame / 4)
  G.setColor(1, 1, 1, ctx.fade * 0.35 * pulse)
  circle(G, ctx.ax, ctx.ay, 14 + pulse * 6)
  local spark = loadTagImage(MA.TAG.SPARKLE_2) or loadTagImage(MA.TAG.BLUE_STAR)
  for i = 0, 5 do
    local ang = frame * 0.2 + i * 1.05
    local rad = 18 + (i % 3) * 4
    local x = ctx.ax + math.cos(ang) * rad
    local y = ctx.ay + math.sin(ang) * rad * 0.65
    local a = ctx.fade * 0.85
    if not (spark and drawTinted(spark, x, y, 0.55, 1, 1, 0.7, a)) then
      G.setColor(1, 1, 0.6, a)
      circle(G, x, y, 2)
    end
  end
end

function FX.sky_attack_hit(G, frame, ctx)
  local bird = loadTagImage(MA.TAG.BIRD) or loadTagImage(MA.TAG.ROUND_SHADOW)
  if frame < 20 then
    local u = frame / 20
    local x = lerp(ctx.ax, ctx.tx, u)
    local y = lerp(ctx.ay - 30, ctx.ty, u)
    local a = ctx.fade
    if not (bird and drawTinted(bird, x, y, 1.1, 1, 1, 1, a)) then
      G.setColor(0.95, 0.95, 1, a)
      circle(G, x, y, 8)
    end
  end
  if frame < 12 then
    G.setColor(1, 1, 1, ctx.fade * 0.4 * (1 - frame / 12))
    G.rectangle("fill", 0, 0, 240, 160)
  end
  if frame >= 14 and frame < 50 then
    hitSplat(G, ctx.tx, ctx.ty, ((frame - 14) % 14) / 14, ctx.fade, true)
  end
end

function FX.bounce_charge(G, frame, ctx)
  local img = loadTagImage(MA.TAG.ROUND_SHADOW)
  local u = frame / 30
  local a = ctx.fade * (1 - u * 0.65)
  local y = ctx.ay - u * 44
  if not (img and drawTinted(img, ctx.ax, y, 1.0 + u * 0.35, 0.1, 0.1, 0.15, a)) then
    G.setColor(0.05, 0.05, 0.12, a * 0.7)
    circle(G, ctx.ax, y, 10 + u * 5)
  end
end

function FX.bounce_hit(G, frame, ctx)
  local img = loadTagImage(MA.TAG.ROUND_SHADOW)
  if frame < 14 then
    local u = frame / 14
    local y = ctx.ty - 55 + u * 55
    if not (img and drawTinted(img, ctx.tx, y, 1.05, 0.1, 0.1, 0.15, ctx.fade)) then
      G.setColor(0.05, 0.05, 0.12, ctx.fade * 0.6)
      circle(G, ctx.tx, y, 11)
    end
  end
  if frame >= 10 and frame < 34 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 10) / 14, ctx.fade, true)
  end
end

function FX.razor_wind_charge(G, frame, ctx)
  local gust = loadTagImage(MA.TAG.GUST)
  for i = 0, 2 do
    local ang = frame * 0.18 + i * (math.pi * 2 / 3)
    local rad = 12 + (frame % 10)
    local x = ctx.ax + math.cos(ang) * rad
    local y = ctx.ay + math.sin(ang) * rad * 0.55
    local a = ctx.fade * 0.85
    if not (gust and drawTinted(gust, x, y, 0.7, 0.85, 0.95, 1, a)) then
      G.setColor(0.8, 0.9, 1, a)
      circle(G, x, y, 4)
    end
  end
end

function FX.razor_wind_hit(G, frame, ctx)
  local wave = loadTagImage(MA.TAG.AIR_WAVE_2) or loadTagImage(MA.TAG.GUST)
  for i = 0, 2 do
    local start = i * 4
    local age = frame - start
    if age >= 0 and age < 22 then
      local u = age / 22
      local yOff = (i - 1) * 10
      local x = lerp(ctx.ax, ctx.tx, u)
      local y = lerp(ctx.ay, ctx.ty + yOff, u)
      local a = ctx.fade * (1 - u * 0.3)
      if not (wave and drawTinted(wave, x, y, 0.85, 0.9, 0.95, 1, a)) then
        G.setColor(0.85, 0.95, 1, a)
        G.rectangle("fill", x - 10, y - 2, 20, 4)
      end
    end
  end
  if frame >= 20 and frame < 40 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 20) / 12, ctx.fade, true)
  end
end

function FX.tri_attack(G, frame, ctx)
  local tri = loadTagImage(MA.TAG.TRI_FORCE) or loadTagImage(MA.TAG.GOLD_RING)
  if frame < 40 then
    local a = ctx.fade
    local spin = frame * 0.15
    for i = 0, 2 do
      local ang = spin + i * (math.pi * 2 / 3)
      local x = ctx.tx + math.cos(ang) * 14
      local y = ctx.ty + math.sin(ang) * 10
      if not (tri and drawTinted(tri, x, y, 0.7, 1, 0.9, 0.4, a)) then
        G.setColor(1, 0.85, 0.3, a)
        circle(G, x, y, 4)
      end
    end
  end
  if frame >= 40 and frame < 55 then
    local ember = loadTagImage(MA.TAG.SMALL_EMBER)
    for i = 0, 5 do
      local a = ctx.fade * 0.9
      local x = ctx.tx + (i - 2.5) * 5
      local y = ctx.ty - 6 + (i % 3) * 4
      if not (ember and drawTinted(ember, x, y, 0.7, 1, 0.55, 0.2, a)) then
        G.setColor(1, 0.45, 0.15, a)
        circle(G, x, y, 3)
      end
    end
  end
  if frame >= 55 and frame < 70 then
    local bolt = loadTagImage(MA.TAG.LIGHTNING)
    local a = ctx.fade
    if not (bolt and drawTinted(bolt, ctx.tx, ctx.ty - 10, 1.0, 1, 1, 0.5, a)) then
      G.setColor(1, 1, 0.4, a)
      G.rectangle("fill", ctx.tx - 2, ctx.ty - 24, 4, 28)
    end
  end
  if frame >= 70 then
    local ice = loadTagImage(MA.TAG.ICE_CRYSTALS)
    for i = 0, 4 do
      local a = ctx.fade * (1 - (frame - 70) / 15)
      local x = ctx.tx + (i - 2) * 6
      local y = ctx.ty + ((i % 2) * 6) - 4
      if not (ice and drawTinted(ice, x, y, 0.6, 0.7, 0.9, 1, a)) then
        G.setColor(0.7, 0.9, 1, a)
        circle(G, x, y, 2)
      end
    end
  end
end

function FX.superpower(G, frame, ctx)
  if frame < 22 then
    local pulse = math.sin(frame / 3)
    G.setColor(1, 0.55, 0.2, ctx.fade * 0.25 * (0.5 + 0.5 * pulse))
    circle(G, ctx.ax, ctx.ay, 16 + pulse * 4)
    local anger = loadTagImage(MA.TAG.ANGER)
    if anger then drawTinted(anger, ctx.ax + 12, ctx.ay - 14, 0.7, 1, 0.4, 0.2, ctx.fade) end
  else
    local fist = loadTagImage(MA.TAG.HANDS_FEET)
    local u = (frame - 22) / 20
    local x = lerp(ctx.ax, ctx.tx, clamp01(u))
    local y = lerp(ctx.ay, ctx.ty, clamp01(u))
    if not (fist and drawTinted(fist, x, y, 1.1, 1, 0.85, 0.6, ctx.fade)) then
      G.setColor(1, 0.8, 0.5, ctx.fade)
      circle(G, x, y, 7)
    end
    if frame >= 38 then
      hitSplat(G, ctx.tx, ctx.ty, (frame - 38) / 14, ctx.fade, true)
    end
  end
end

function FX.iron_tail(G, frame, ctx)
  if frame < 16 then
    G.setColor(0.75, 0.8, 0.9, ctx.fade * 0.3)
    circle(G, ctx.ax, ctx.ay, 14)
  end
  if frame >= 12 and frame < 45 then
    hitSplat(G, ctx.tx, ctx.ty, ((frame - 12) % 12) / 12, ctx.fade, true)
    local claw = loadTagImage(MA.TAG.SLAM_HIT) or loadTagImage(MA.TAG.IMPACT)
    if claw then drawTinted(claw, ctx.tx, ctx.ty, 1.0, 0.85, 0.9, 1, ctx.fade * 0.8) end
  end
end

function FX.crabhammer(G, frame, ctx)
  local bub = loadTagImage(MA.TAG.WATER_IMPACT) or loadTagImage(MA.TAG.SMALL_BUBBLES)
  if frame < 18 then
    local fist = loadTagImage(MA.TAG.HANDS_FEET)
    local u = frame / 18
    local x = lerp(ctx.ax, ctx.tx, u)
    local y = lerp(ctx.ay - 8, ctx.ty, u)
    if not (fist and drawTinted(fist, x, y, 1.0, 0.5, 0.8, 1, ctx.fade)) then
      G.setColor(0.4, 0.75, 1, ctx.fade)
      circle(G, x, y, 6)
    end
  end
  if frame >= 16 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 16) / 14, ctx.fade, true)
    for i = 0, 4 do
      local a = ctx.fade * 0.7
      local x = ctx.tx + (i - 2) * 5
      local y = ctx.ty + 6 - (frame - 16)
      if bub then drawTinted(bub, x, y, 0.5, 0.5, 0.85, 1, a) end
    end
  end
end

function FX.dynamic_punch(G, frame, ctx)
  fistBurst(G, frame, ctx, {
    {6, 0, 0}, {18, -6, 4}, {30, 6, -4},
  })
  if frame >= 28 then
    local star = loadTagImage(MA.TAG.SPARKLE_2) or loadTagImage(MA.TAG.BLUE_STAR)
    for i = 0, 4 do
      local ang = frame * 0.25 + i * 1.2
      local x = ctx.tx + math.cos(ang) * 12
      local y = ctx.ty + math.sin(ang) * 9
      if not (star and drawTinted(star, x, y, 0.55, 1, 0.9, 0.4, ctx.fade)) then
        G.setColor(1, 0.9, 0.5, ctx.fade)
        circle(G, x, y, 2)
      end
    end
  end
end

function FX.cross_chop(G, frame, ctx)
  local hand = loadTagImage(MA.TAG.HANDS_FEET)
  local cross = loadTagImage(MA.TAG.CROSS_IMPACT) or loadTagImage(MA.TAG.IMPACT)
  if frame < 36 then
    local a = ctx.fade
    if hand then
      drawTinted(hand, ctx.tx - 10, ctx.ty - 8, 0.95, 1, 0.9, 0.8, a)
      drawTinted(hand, ctx.tx + 10, ctx.ty + 8, 0.95, 1, 0.9, 0.8, a)
    else
      G.setColor(1, 0.85, 0.7, a)
      circle(G, ctx.tx - 10, ctx.ty - 8, 5)
      circle(G, ctx.tx + 10, ctx.ty + 8, 5)
    end
  end
  if frame >= 36 then
    local a = ctx.fade
    if not (cross and drawTinted(cross, ctx.tx, ctx.ty, 1.2, 1, 1, 1, a)) then
      G.setColor(1, 1, 1, a)
      G.rectangle("fill", ctx.tx - 12, ctx.ty - 2, 24, 4)
      G.rectangle("fill", ctx.tx - 2, ctx.ty - 12, 4, 24)
    end
    hitSplat(G, ctx.tx, ctx.ty, (frame - 36) / 12, ctx.fade * 0.7, true)
  end
end

function FX.megahorn(G, frame, ctx)
  local horn = loadTagImage(MA.TAG.HORN_HIT) or loadTagImage(MA.TAG.NEEDLE)
  local u = math.min(1, frame / 22)
  local x = lerp(ctx.ax, ctx.tx, u)
  local y = lerp(ctx.ay, ctx.ty, u)
  if not (horn and drawTinted(horn, x, y, 1.0, 0.95, 0.9, 0.6, ctx.fade)) then
    G.setColor(0.9, 0.85, 0.5, ctx.fade)
    G.rectangle("fill", x - 8, y - 2, 16, 4)
  end
  if frame >= 20 then
    hitSplat(G, ctx.tx, ctx.ty, (frame - 20) / 14, ctx.fade, true)
  end
end

function FX.extremespeed(G, frame, ctx)
  local dust = loadTagImage(MA.TAG.SPEED_DUST)
  local dir = ctx.onEnemy and 1 or -1
  for i = 0, 5 do
    local start = i * 3
    local age = frame - start
    if age >= 0 and age < 12 then
      local u = age / 12
      local x = ctx.ax + dir * (20 + i * 8) * u
      local y = ctx.ay + ((i % 3) - 1) * 5
      local a = ctx.fade * (1 - u)
      if not (dust and drawTinted(dust, x, y, 0.7, 0.9, 0.9, 1, a)) then
        G.setColor(0.85, 0.9, 1, a)
        G.rectangle("fill", x - 6, y - 1, 12, 2)
      end
    end
  end
  if frame >= 22 then
    hitSplat(G, ctx.tx, ctx.ty, ((frame - 22) % 12) / 12, ctx.fade, true)
  end
end

function FX.ancient_power(G, frame, ctx)
  local rocks = loadTagImage(MA.TAG.ROCKS)
  for i = 0, 5 do
    local start = i * 4
    local age = frame - start
    if age >= 0 and age < 28 then
      local u = age / 28
      local x = ctx.ax + ((i % 3) - 1) * 10
      local y = ctx.ay + 16 - u * 40
      local a = ctx.fade * (1 - u * 0.4)
      if not (rocks and drawTinted(rocks, x, y, 0.7, 0.75, 0.55, 0.35, a)) then
        G.setColor(0.7, 0.5, 0.3, a)
        circle(G, x, y, 4)
      end
    end
  end
  if frame >= 30 then
    local u = (frame - 30) / 25
    for i = 0, 3 do
      local x = lerp(ctx.ax + (i - 1.5) * 6, ctx.tx, clamp01(u))
      local y = lerp(ctx.ay - 20, ctx.ty, clamp01(u))
      if rocks then drawTinted(rocks, x, y, 0.65, 0.75, 0.55, 0.35, ctx.fade) end
    end
    if frame >= 42 then
      hitSplat(G, ctx.tx, ctx.ty, (frame - 42) / 12, ctx.fade, true)
    end
  end
end

function FX.future_sight(G, frame, ctx)
  local ring = loadTagImage(MA.TAG.GOLD_RING) or loadTagImage(MA.TAG.THIN_RING)
  G.setColor(0.55, 0.35, 0.85, ctx.fade * 0.18)
  G.rectangle("fill", 0, 0, 240, 160)
  for i = 0, 3 do
    local r = 8 + i * 6 + (frame % 10)
    local a = ctx.fade * (0.7 - i * 0.12)
    if not (ring and drawTinted(ring, ctx.tx, ctx.ty, 0.5 + i * 0.15, 0.75, 0.45, 1, a)) then
      G.setColor(0.7, 0.4, 1, a)
      circle(G, ctx.tx, ctx.ty, r, "line")
    end
  end
end

function FX.wish(G, frame, ctx)
  local star = loadTagImage(MA.TAG.GREEN_STAR) or loadTagImage(MA.TAG.BLUE_STAR)
  local u = math.min(1, frame / 50)
  local x = 120
  local y = 20 + u * 50
  local a = ctx.fade * (1 - math.max(0, (frame - 50) / 20))
  if not (star and drawTinted(star, x, y, 1.1, 0.85, 1, 0.7, a)) then
    G.setColor(0.9, 1, 0.7, a)
    circle(G, x, y, 5)
  end
  G.setColor(1, 1, 0.85, a * 0.25)
  G.rectangle("fill", 0, 0, 240, 160)
end

function FX.ingrain(G, frame, ctx)
  local roots = loadTagImage(MA.TAG.ROOTS) or loadTagImage(MA.TAG.LEAF)
  for i = 0, 4 do
    local start = i * 5
    local age = frame - start
    if age >= 0 and age < 30 then
      local u = age / 30
      local x = ctx.ax + (i - 2) * 8
      local y = ctx.ay + 10 + u * 8
      local a = ctx.fade * (0.5 + 0.5 * u)
      if not (roots and drawTinted(roots, x, y, 0.7, 0.45, 0.75, 0.35, a)) then
        G.setColor(0.4, 0.7, 0.3, a)
        G.rectangle("fill", x - 1, y, 3, 10)
      end
    end
  end
end

function FX.helping_hand(G, frame, ctx)
  local hand = loadTagImage(MA.TAG.HANDS_FEET)
  local spark = loadTagImage(MA.TAG.SPARKLE_2) or loadTagImage(MA.TAG.BLUE_STAR)
  local bob = math.sin(frame / 5) * 3
  if hand then
    drawTinted(hand, ctx.ax - 10, ctx.ay - 6 + bob, 0.85, 1, 0.95, 0.8, ctx.fade)
    drawTinted(hand, ctx.ax + 10, ctx.ay - 6 - bob, 0.85, 1, 0.95, 0.8, ctx.fade)
  end
  if spark then
    drawTinted(spark, ctx.ax, ctx.ay - 18, 0.6, 1, 1, 0.6, ctx.fade)
  end
end

function FX.follow_me(G, frame, ctx)
  local finger = loadTagImage(MA.TAG.FINGER)
  local bob = math.sin(frame / 4) * 5
  if not (finger and drawTinted(finger, ctx.ax, ctx.ay - 20 + bob, 1.0, 1, 1, 1, ctx.fade)) then
    G.setColor(1, 0.9, 0.7, ctx.fade)
    G.rectangle("fill", ctx.ax - 2, ctx.ay - 22 + bob, 5, 12)
  end
  G.setColor(1, 0.85, 0.3, ctx.fade * 0.35)
  circle(G, ctx.ax, ctx.ay - 28 + bob, 6)
end

function FX.yawn(G, frame, ctx)
  local z = loadTagImage(MA.TAG.LETTER_Z)
  local bub = loadTagImage(MA.TAG.THOUGHT_BUBBLE) or loadTagImage(MA.TAG.BREATH)
  if bub then
    drawTinted(bub, ctx.ax + 14, ctx.ay - 16, 0.9, 1, 1, 1, ctx.fade * 0.85)
  end
  for i = 0, 2 do
    local start = 8 + i * 12
    local age = frame - start
    if age >= 0 and age < 28 then
      local u = age / 28
      local x = lerp(ctx.ax + 10, ctx.tx, u)
      local y = lerp(ctx.ay - 10, ctx.ty - 8, u) - u * 10
      local a = ctx.fade * (1 - u * 0.4)
      if not (z and drawTinted(z, x, y, 0.7 + i * 0.1, 0.9, 0.7, 1, a)) then
        G.setColor(0.85, 0.7, 1, a)
        circle(G, x, y, 3)
      end
    end
  end
end

function FX.slack_off(G, frame, ctx)
  FX.recover(G, frame, ctx)
end

function FX.arm_thrust(G, frame, ctx)
  fistBurst(G, frame, ctx, {
    {4, -6, 0}, {14, 6, 2}, {24, -4, -2}, {34, 5, 1}, {44, 0, 0},
  })
end

function FX.smelling_salt(G, frame, ctx)
  local hand = loadTagImage(MA.TAG.HANDS_FEET)
  if frame < 20 then
    local gap = 14 - frame * 0.6
    if hand then
      drawTinted(hand, ctx.tx - gap, ctx.ty, 0.9, 1, 0.9, 0.8, ctx.fade)
      drawTinted(hand, ctx.tx + gap, ctx.ty, 0.9, 1, 0.9, 0.8, ctx.fade)
    end
  else
    hitSplat(G, ctx.tx, ctx.ty, (frame - 20) / 14, ctx.fade, true)
  end
end

function FX.double_edge(G, frame, ctx)
  if frame < 18 then
    local dir = ctx.onEnemy and 1 or -1
    G.setColor(1, 1, 1, ctx.fade * 0.2)
    circle(G, ctx.ax + dir * 8, ctx.ay, 12)
  end
  if frame >= 14 then
    hitSplat(G, ctx.tx, ctx.ty, ((frame - 14) % 12) / 12, ctx.fade, true)
    if frame >= 28 then
      G.setColor(1, 0.4, 0.3, ctx.fade * 0.2)
      circle(G, ctx.ax, ctx.ay, 10)
    end
  end
end

function FX.trick(G, frame, ctx)
  local bag = loadTagImage(MA.TAG.ITEM_BAG)
  local u = frame / 50
  local x1 = lerp(ctx.ax, ctx.tx, math.min(1, u * 2))
  local x2 = lerp(ctx.tx, ctx.ax, math.min(1, u * 2))
  local a = ctx.fade
  if bag then
    drawTinted(bag, x1, ctx.ay - 8, 0.85, 1, 1, 1, a)
    drawTinted(bag, x2, ctx.ty - 8, 0.85, 1, 1, 1, a)
  else
    G.setColor(0.9, 0.75, 0.4, a)
    circle(G, x1, ctx.ay - 8, 5)
    circle(G, x2, ctx.ty - 8, 5)
  end
  if frame > 20 and frame < 35 then
    G.setColor(1, 1, 1, ctx.fade * 0.35)
    G.rectangle("fill", 0, 0, 240, 160)
  end
end

function FX.imprison(G, frame, ctx)
  local ring = loadTagImage(MA.TAG.THIN_RING) or loadTagImage(MA.TAG.GOLD_RING)
  for i = 0, 2 do
    local a = ctx.fade * (0.7 - i * 0.15)
    local rscale = 0.7 + i * 0.2 + math.sin(frame / 6) * 0.05
    if not (ring and drawTinted(ring, ctx.tx, ctx.ty, rscale, 0.6, 0.4, 0.9, a)) then
      G.setColor(0.55, 0.35, 0.85, a)
      circle(G, ctx.tx, ctx.ty, 10 + i * 6, "line")
    end
  end
end

function FX.grudge(G, frame, ctx)
  local ghost = loadTagImage(MA.TAG.GHOSTLY_SPIRIT) or loadTagImage(MA.TAG.WISP_FIRE)
  G.setColor(0.35, 0.1, 0.45, ctx.fade * 0.22)
  G.rectangle("fill", 0, 0, 240, 160)
  for i = 0, 3 do
    local x = lerp(ctx.ax, ctx.tx, (i + 1) / 5)
    local y = lerp(ctx.ay, ctx.ty, (i + 1) / 5) + math.sin(frame / 5 + i) * 4
    if not (ghost and drawTinted(ghost, x, y, 0.7, 0.7, 0.3, 0.9, ctx.fade)) then
      G.setColor(0.7, 0.3, 0.85, ctx.fade)
      circle(G, x, y, 4)
    end
  end
end

function FX.snatch(G, frame, ctx)
  local hand = loadTagImage(MA.TAG.HANDS_FEET)
  local u = math.min(1, frame / 20)
  local x = lerp(ctx.ax, ctx.tx, u)
  local y = lerp(ctx.ay, ctx.ty, u)
  if not (hand and drawTinted(hand, x, y, 0.95, 1, 0.9, 0.8, ctx.fade)) then
    G.setColor(1, 0.9, 0.7, ctx.fade)
    circle(G, x, y, 6)
  end
  if frame >= 22 then
    local back = (frame - 22) / 18
    local bx = lerp(ctx.tx, ctx.ax, clamp01(back))
    if hand then drawTinted(hand, bx, ctx.ay, 0.85, 1, 0.9, 0.8, ctx.fade) end
  end
end

function FX.skill_swap(G, frame, ctx)
  local orb = loadTagImage(MA.TAG.ORBS) or loadTagImage(MA.TAG.GOLD_RING)
  for i = 0, 1 do
    local u = (frame / 50 + i * 0.5) % 1
    local x = lerp(ctx.ax, ctx.tx, i == 0 and u or (1 - u))
    local y = lerp(ctx.ay, ctx.ty, i == 0 and u or (1 - u))
    if not (orb and drawTinted(orb, x, y, 0.75, 0.6, 0.9, 1, ctx.fade)) then
      G.setColor(0.6, 0.85, 1, ctx.fade)
      circle(G, x, y, 4)
    end
  end
end

function FX.role_play(G, frame, ctx)
  local u = frame / 50
  G.setColor(0.7, 0.9, 1, ctx.fade * 0.25 * (1 - math.abs(u - 0.5) * 2))
  G.rectangle("fill", 0, 0, 240, 160)
  local ring = loadTagImage(MA.TAG.THIN_RING)
  if ring then
    drawTinted(ring, ctx.ax, ctx.ay, 1.0, 0.7, 0.9, 1, ctx.fade)
    drawTinted(ring, ctx.tx, ctx.ty, 1.0, 0.7, 0.9, 1, ctx.fade)
  end
end

function FX.camouflage(G, frame, ctx)
  local a = ctx.fade * (0.4 + 0.4 * math.sin(frame / 4))
  G.setColor(0.45, 0.55, 0.4, a)
  circle(G, ctx.ax, ctx.ay, 16)
  local spark = loadTagImage(MA.TAG.SPARKLE_2)
  if spark then drawTinted(spark, ctx.ax + 8, ctx.ay - 10, 0.5, 0.8, 1, 0.6, ctx.fade) end
end

function FX.recycle(G, frame, ctx)
  local bag = loadTagImage(MA.TAG.ITEM_BAG) or loadTagImage(MA.TAG.ORBS)
  local ang = frame * 0.25
  for i = 0, 2 do
    local a = ang + i * 2.1
    local x = ctx.ax + math.cos(a) * 12
    local y = ctx.ay + math.sin(a) * 8
    if not (bag and drawTinted(bag, x, y, 0.6, 0.6, 1, 0.6, ctx.fade)) then
      G.setColor(0.5, 0.95, 0.55, ctx.fade)
      circle(G, x, y, 3)
    end
  end
end

function FX.assist(G, frame, ctx)
  local finger = loadTagImage(MA.TAG.FINGER) or loadTagImage(MA.TAG.THOUGHT_BUBBLE)
  local bob = math.sin(frame / 5) * 4
  if not (finger and drawTinted(finger, ctx.ax + 10, ctx.ay - 16 + bob, 0.9, 1, 1, 1, ctx.fade)) then
    G.setColor(1, 0.95, 0.8, ctx.fade)
    circle(G, ctx.ax + 10, ctx.ay - 16 + bob, 5)
  end
end

---------------------------------------------------------------------------
-- Shake / lunge offsets (pixels) matching AnimTask_* args
---------------------------------------------------------------------------

function MA.offsetsFor(ma)
  local frame = math.floor((ma.t or 0) * MA.FPS + 0.0001)
  local fx = ma.fx
  local atkX, atkY, tgtX, tgtY = 0, 0, 0, 0
  if fx == "pound" or fx == "scratch" then
    -- AnimTask_ShakeMon: 3px x, 6 shakes × 1f
    if frame < 8 then
      tgtX = (math.floor(frame) % 2 == 0) and 3 or 0
    end
  elseif fx == "tackle" then
    -- HorizontalLunge amplitude 4 for ~6f, then shake
    if frame < 6 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 4
    elseif frame < 14 then
      tgtX = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "vine_whip" then
    if frame < 6 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 6
    elseif frame >= 12 and frame < 20 then
      tgtX = (frame % 2 == 0) and 2 or 0
    end
  elseif fx == "quick_attack" then
    if frame < 8 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * math.floor(12 * math.sin(frame / 8 * math.pi))
    elseif frame < 16 then
      tgtX = (frame % 2 == 0) and 5 or 0
    end
  elseif fx == "growl" then
    if frame >= 30 and frame < 48 then
      tgtX = (frame % 2 == 0) and 1 or 0
    end
  elseif fx == "tail_whip" then
    -- TranslateMonEllipticalRespectSide: 12, 4, 2, 3
    local u = (frame % 16) / 16
    local dir = ma.onEnemy and 1 or -1
    atkX = math.floor(dir * 12 * math.sin(u * math.pi * 2))
    atkY = math.floor(4 * math.sin(u * math.pi * 4))
  elseif fx == "water_gun" or fx == "ember" then
    if frame > 40 and frame < 55 then
      tgtX = (frame % 2 == 0) and 1 or 0
    end
  elseif fx == "absorb" then
    if frame >= 4 and frame < 12 then
      tgtX = (frame % 2 == 0) and 5 or 0
    end
  elseif fx == "thunder_shock" then
    if frame >= 18 and frame < 40 then
      tgtX = (frame % 2 == 0) and 2 or -2
    end
  elseif fx == "mud_slap" or fx == "sand_attack" then
    if frame < 4 then
      local dir = ma.onEnemy and 1 or -1
      atkX = -dir * 6
    end
  elseif fx == "rock_throw" then
    if frame >= 12 and frame < 36 then
      tgtY = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "bite" or fx == "peck" or fx == "cut" or fx == "aerial_ace" then
    if frame >= 8 and frame < 20 then
      tgtX = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "gust" or fx == "wing_attack" then
    if frame >= 28 and frame < 46 then
      tgtX = (frame % 2 == 0) and 2 or -1
    end
  elseif fx == "headbutt" then
    if frame < 12 then
      atkY = (frame % 4 < 2) and -2 or 2
    elseif frame < 24 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 8
      tgtX = (frame % 2 == 0) and 4 or 0
    end
  elseif fx == "body_slam" then
    if frame < 10 then
      atkY = 4
    elseif frame < 22 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 14
    elseif frame < 40 then
      tgtX = (frame % 2 == 0) and 4 or 0
    end
  elseif fx == "take_down" then
    if frame < 30 then
      local dir = ma.onEnemy and 1 or -1
      atkX = -dir * math.floor(10 * math.sin(frame / 30 * math.pi))
    elseif frame < 50 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 16
      tgtX = (frame % 2 == 0) and 5 or 0
    end
  elseif fx == "strength" then
    if frame < 30 then
      atkY = math.floor(frame / 2)
    elseif frame >= 38 and frame < 60 then
      tgtX = (frame % 2 == 0) and 3 or -2
    end
  elseif fx == "rock_smash" then
    if frame < 12 then
      tgtX = (frame % 2 == 0) and 3 or 0
    elseif frame < 28 then
      tgtY = (frame % 2 == 0) and 2 or 0
    end
  elseif fx == "confusion" or fx == "psybeam" then
    if frame >= 18 and frame < 45 then
      tgtX = (frame % 2 == 0) and 2 or -2
    end
  elseif fx == "fire_spin" or fx == "flamethrower" then
    if frame > 10 and frame < 55 then
      tgtX = (frame % 2 == 0) and 1 or -1
    end
  elseif fx == "mega_drain" then
    if frame >= 4 and frame < 14 then
      tgtX = (frame % 2 == 0) and 4 or 0
    end
  elseif fx == "poison_sting" then
    if frame >= 18 and frame < 28 then
      tgtX = (frame % 2 == 0) and 2 or 0
    end
  elseif fx == "leer" then
    if frame >= 18 and frame < 36 then
      tgtX = (frame % 2 == 0) and 1 or 0
    end
  elseif fx == "metal_claw" then
    if frame >= 16 and frame < 28 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 4
      tgtX = (frame % 2 == 0) and 2 or 0
    elseif frame >= 30 and frame < 42 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 4
      tgtX = (frame % 2 == 0) and 2 or 0
    end
  elseif fx == "dig" or fx == "dig_charge" then
    atkY = math.min(28, 4 + frame)
  elseif fx == "dig_hit" then
    if frame < 12 then
      atkY = math.max(0, 28 - frame * 2)
    elseif frame < 36 then
      tgtX = (frame % 2 == 0) and 4 or 0
    end
  elseif fx == "fly_charge" then
    atkY = -math.min(48, frame * 2)
  elseif fx == "fly_hit" then
    if frame < 18 then atkY = -40 + frame * 2 end
    if frame >= 16 and frame < 36 then tgtX = (frame % 2 == 0) and 5 or 0 end
  elseif fx == "dive_charge" then
    atkY = math.min(36, frame)
  elseif fx == "dive_hit" then
    if frame < 20 then atkY = math.max(0, 36 - frame * 2) end
    if frame >= 28 then tgtX = (frame % 2 == 0) and 4 or 0 end
  elseif fx == "skull_bash_charge" then
    local dir = ma.onEnemy and 1 or -1
    atkX = math.floor(dir * 6 * math.sin(frame / 8))
  elseif fx == "skull_bash_hit" then
    local dir = ma.onEnemy and 1 or -1
    if frame < 14 then atkX = dir * 16 end
    if frame >= 6 and frame < 40 then tgtX = (frame % 2 == 0) and 5 or -2 end
  elseif fx == "solar_beam_charge" then
    -- self glow
  elseif fx == "solar_beam_hit" then
    if frame > 12 then tgtX = (frame % 2 == 0) and 3 or -2 end
  elseif fx == "sky_attack_charge" then
    -- glow in place
  elseif fx == "sky_attack_hit" then
    if frame >= 14 and frame < 50 then tgtX = (frame % 2 == 0) and 5 or -2 end
  elseif fx == "bounce_charge" then
    atkY = -math.min(48, frame * 2)
  elseif fx == "bounce_hit" then
    if frame < 14 then atkY = -50 + frame * 3 end
    if frame >= 10 and frame < 34 then tgtY = (frame % 2 == 0) and 4 or 0 end
  elseif fx == "razor_wind_charge" then
    local u = (frame % 16) / 16
    atkX = math.floor(6 * math.sin(u * math.pi * 2))
  elseif fx == "razor_wind_hit" then
    if frame >= 20 then tgtX = (frame % 2 == 0) and 3 or -2 end
  elseif fx == "tri_attack" then
    if frame >= 40 then tgtX = (frame % 2 == 0) and 2 or -2 end
  elseif fx == "superpower" or fx == "iron_tail" or fx == "crabhammer"
      or fx == "dynamic_punch" or fx == "cross_chop" or fx == "megahorn"
      or fx == "double_edge" or fx == "smelling_salt" or fx == "arm_thrust" then
    local dir = ma.onEnemy and 1 or -1
    if frame < 12 then atkX = dir * 4 end
    if frame >= 16 then tgtX = (frame % 2 == 0) and 4 or 0 end
  elseif fx == "extremespeed" then
    local dir = ma.onEnemy and 1 or -1
    if frame < 22 then atkX = dir * math.floor(18 * math.sin(frame / 22 * math.pi)) end
    if frame >= 22 then tgtX = (frame % 2 == 0) and 5 or 0 end
  elseif fx == "ancient_power" then
    if frame >= 42 then tgtY = (frame % 2 == 0) and 3 or 0 end
  elseif fx == "focus_punch" then
    if frame < 28 then
      atkX = (frame % 4 < 2) and 2 or -2
    elseif frame < 90 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 6
      tgtX = (frame % 2 == 0) and 4 or 0
    end
  elseif fx == "hyper_beam" then
    if frame >= 10 and frame < 40 then
      atkX = (frame % 2 == 0) and 1 or -1
    elseif frame >= 50 then
      tgtX = (frame % 2 == 0) and 3 or -3
    end
  elseif fx == "double_team" then
    if frame < 100 then
      local dir = ma.onEnemy and 1 or -1
      atkX = math.floor(dir * 6 * math.sin(frame / 6))
    end
  elseif fx == "bubble" or fx == "bubblebeam" or fx == "surf" then
    if frame > 40 and frame < 70 then
      tgtX = (frame % 2 == 0) and 1 or 0
    end
  elseif fx == "razor_leaf" then
    if frame >= 80 and frame < 100 then
      tgtX = (frame % 2 == 0) and 2 or 0
    end
  elseif fx == "string_shot" then
    if frame >= 70 and frame < 88 then
      tgtX = (frame % 2 == 0) and 1 or 0
    end

  elseif fx == "magnitude" or fx == "earthquake" or fx == "eruption" then
    if frame < 55 or (fx == "eruption" and frame >= 80) then
      tgtX = (frame % 2 == 0) and 3 or -3
      atkX = (frame % 2 == 0) and -2 or 2
      tgtY = (frame % 4 < 2) and 2 or 0
    end
  elseif fx == "brick_break" then
    if frame < 10 or (frame >= 28 and frame < 38) or (frame >= 70 and frame < 90) then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 6
      tgtX = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "bulk_up" then
    if frame >= 8 and frame < 36 then
      atkX = (frame % 4 < 2) and 2 or -2
    end
  elseif fx == "calm_mind" or fx == "safeguard" or fx == "light_screen" or fx == "reflect" then
    -- self-centered; no target shake
  elseif fx == "shadow_ball" then
    if frame >= 50 and frame < 66 then
      tgtX = (frame % 2 == 0) and 3 or -2
    end
  elseif fx == "hydro_pump" or fx == "ice_beam" or fx == "blizzard" then
    if frame > 20 and frame < 80 then
      tgtX = (frame % 2 == 0) and 2 or -1
    end
  elseif fx == "thunderbolt" or fx == "thunder" or fx == "thunder_wave" then
    if frame >= 16 and frame < 100 then
      tgtX = (frame % 2 == 0) and 3 or -3
    end
  elseif fx == "psychic" then
    if frame >= 14 and frame < 50 then
      tgtX = (frame % 2 == 0) and 4 or -4
    end
  elseif fx == "crunch" or fx == "slam" then
    if frame >= 6 and frame < 28 then
      tgtX = (frame % 2 == 0) and 3 or 0
      if fx == "slam" and frame < 12 then
        local dir = ma.onEnemy and 1 or -1
        atkX = dir * 12
      end
    end
  elseif fx == "dragon_claw" or fx == "revenge" then
    if frame >= 24 and frame < 60 then
      local dir = ma.onEnemy and 1 or -1
      atkX = dir * 5
      tgtX = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "facade" or fx == "endeavor" then
    if frame < 40 then
      atkX = (frame % 6 < 3) and 2 or -2
    end
    if fx == "endeavor" and frame >= 12 and frame < 42 then
      tgtX = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "return" or fx == "frustration" then
    if frame < 24 then
      atkY = (frame % 8 < 4) and 3 or -1
    elseif frame < 85 then
      tgtX = (frame % 2 == 0) and 3 or 0
    end
  elseif fx == "hidden_power" then
    if frame < 50 then
      atkX = (frame % 2 == 0) and 1 or -1
    elseif frame < 100 then
      tgtX = (frame % 2 == 0) and 2 or -2
    end
  elseif fx == "overheat" then
    if frame >= 20 and frame < 50 then
      atkX = (frame % 2 == 0) and 2 or -2
    elseif frame >= 55 and frame < 85 then
      tgtX = (frame % 2 == 0) and 3 or -2
    end
  elseif fx == "fake_out" then
    if frame >= 12 and frame < 28 then
      tgtX = (frame % 2 == 0) and 4 or 0
    end
  elseif fx == "will_o_wisp" then
    if frame >= 50 and frame < 80 then
      tgtX = (frame % 2 == 0) and 2 or -1
    end
  elseif fx == "attract" then
    if frame < 30 then
      local dir = ma.onEnemy and 1 or -1
      atkX = math.floor(dir * 6 * math.sin(frame / 8))
    end
  elseif fx == "spikes" then
    -- projectiles only

  elseif fx == "swords_dance" or fx == "dragon_dance" then
    local dir = ma.onEnemy and 1 or -1
    atkX = math.floor(dir * 8 * math.sin(frame / 6))
  elseif fx == "splash" then
    atkY = -math.floor(math.abs(math.sin(frame / 8)) * 10)
  elseif fx == "rapid_spin" then
    atkX = math.floor(6 * math.sin(frame / 3))
    if frame >= 28 and frame < 48 then tgtX = (frame % 2 == 0) and 3 or 0 end
  elseif fx == "explosion" or fx == "struggle" then
    atkX = (frame % 2 == 0) and 3 or -3
    tgtX = (frame % 2 == 0) and -2 or 2
  elseif fx == "counter" or fx == "mirror_coat" then
    if frame >= 8 and frame < 32 then tgtX = (frame % 2 == 0) and 4 or 0 end
  elseif fx == "recover" or fx == "metronome" or fx == "transform"
      or fx == "rain_dance" or fx == "sunny_day" or fx == "sandstorm_move"
      or fx == "hail_move" or fx == "destiny_bond" then
    -- mostly self / field FX

  end
  return atkX, atkY, tgtX, tgtY
end

function MA.drawScript(ma, hitLeft, dur)
  if not (ma and ma.ruby and ma.fx) then return end
  local G = love.graphics
  if not G then return end
  local fade = 1
  if dur and dur > 0 and hitLeft then
    fade = clamp01(hitLeft / dur)
  end
  -- Soft peak so procedural particles also read translucent (ROM OBJ blend-ish),
  -- not chalk-opaque on foe or player targets.
  fade = fade * 0.88
  local frame = math.floor((ma.t or 0) * MA.FPS + 0.0001)
  local ctx = {
    ax = ma.ax or 72, ay = ma.ay or 80,
    tx = ma.tx or 176, ty = ma.ty or 40,
    onEnemy = ma.onEnemy and true or false,
    fade = fade,
    shatter = ma.shatter and true or false,
    phase = ma.phase,
  }
  local prevMode, prevAlphaMode
  if G.getBlendMode then
    prevMode, prevAlphaMode = G.getBlendMode()
  end
  if G.setBlendMode then
    -- Standard alpha over battle canvas (enemy + player move FX).
    pcall(G.setBlendMode, "alpha")
  end
  local drawer = FX[ma.fx]
  if drawer then drawer(G, frame, ctx) end
  if G.setBlendMode and prevMode then
    if prevAlphaMode ~= nil then
      pcall(G.setBlendMode, prevMode, prevAlphaMode)
    else
      pcall(G.setBlendMode, prevMode)
    end
  end
  G.setColor(1, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Fire scripted playsewithpan / loopsewithpan entries at frame offsets.
-- Reuses host:playSe (Mp2k SE voice) so BGM on the song voice is not stopped.
function MA.stepSeChain(host, ma)
  if not (host and ma and ma.seChain and host.playSe) then return end
  local chain = ma.seChain
  if type(chain) ~= "table" or #chain == 0 then return end
  local frame = math.floor((ma.t or 0) * MA.FPS + 0.0001)
  ma._seFired = ma._seFired or {}
  for i = 1, #chain do
    if not ma._seFired[i] then
      local ev = chain[i]
      local f = 0
      local id = nil
      if type(ev) == "table" then
        f = tonumber(ev.f or ev.frame or ev[1]) or 0
        id = tonumber(ev.id or ev.seId or ev[2])
      else
        id = tonumber(ev)
      end
      if frame >= f and id then
        ma._seFired[i] = true
        host:playSe(id)
      end
    end
  end
end

-- Attach to Game3
---------------------------------------------------------------------------

function MA.attach(Game3)
  MA.Game3 = Game3
  Game3._moveAnimBattlerCX = Game3.BATTLER_CX
  Game3._moveAnimBattlerCY = Game3.BATTLER_CY
  Game3.MoveAnim = MA

  local origArm = Game3.armMoveAnim
  function Game3:armMoveAnim(attacker, defender, move, kind)
    local b = self.battle
    if not b then return end
    local opt = self.options
    if opt and opt.battleScene == false then return end

    local spec = MA.resolve(move)
    if not spec then
      return origArm(self, attacker, defender, move, kind)
    end

    local moveType = self:attackType(attacker, move)
    local onEnemy = self:isPlayerBattler(attacker)
    local ax, ay, tx, ty = battlerCenters(self, onEnemy)
    local phase = (kind == "charge") and "charge" or "hit"
    local frames = spec.frames or 20
    local fx = spec.fx
    local seId = spec.seId
    local seChain = spec.seChain
    if phase == "charge" then
      frames = spec.chargeFrames or frames
      fx = spec.chargeFx or fx
      seId = spec.chargeSeId or seId
      seChain = spec.chargeSeChain or seChain
    end
    local dur = frames / MA.FPS
    local physical = Game3.isPhysical(moveType)
    local shatter = false
    if fx == "brick_break" and b.brickBreakShatter then
      shatter = true
      b.brickBreakShatter = nil
    end

    b.moveAnim = {
      t = 0,
      dur = dur,
      type = moveType,
      -- status amp is smallest generic lunge; scripted offsets do the real motion
      kind = "status",
      onEnemy = onEnemy and true or false,
      physical = physical and true or false,
      ruby = true,
      fx = fx,
      phase = phase,
      shatter = shatter and true or nil,
      rom = spec.rom,
      frames = frames,
      se = spec.se,
      seId = seId,
      seChain = seChain,
      _seFired = {},
      moveName = MA.normalizeName(move and move.name),
      moveId = move and move.id,
      ax = ax, ay = ay, tx = tx, ty = ty,
    }
    b.animT = dur
    -- Timed SE chain (playsewithpan / loopsewithpan at frame offsets).
    -- Effectiveness SE is queued separately and flushed when anim ends.
    -- playSe uses the SE voice only — does not stop BGM.
    if spec.seCry and attacker and self.playMonCry then
      self:playMonCry(attacker.species)
    elseif seChain and #seChain > 0 then
      MA.stepSeChain(self, b.moveAnim)
    elseif seId and self.playSe then
      self:playSe(seId)
    end
  end

  local origDrawBurst = Game3.drawMoveAnimBurst
  function Game3:drawMoveAnimBurst(cx, cy, ma, hitLeft, dur)
    if ma and ma.ruby then
      -- drawBattle may call this once per side; only paint scripted FX once/frame
      local frame = math.floor((ma.t or 0) * MA.FPS + 0.0001)
      if ma._drawnFrame ~= frame then
        ma._drawnFrame = frame
        MA.drawScript(ma, hitLeft, dur or ma.dur)
      end
      return
    end
    return origDrawBurst(self, cx, cy, ma, hitLeft, dur)
  end

  local origTopLeft = Game3.battlerTopLeft
  function Game3:battlerTopLeft(slot, species, which)
    local px, py = origTopLeft(self, slot, species, which)
    local b = self.battle
    local ma = b and b.moveAnim
    if not (ma and ma.ruby) then return px, py end
    local atkX, atkY, tgtX, tgtY = MA.offsetsFor(ma)
    if ma.onEnemy then
      if slot == "player" or slot == "player2" then
        return px + atkX, py + atkY
      elseif slot == "enemy" or slot == "enemy2" then
        return px + tgtX, py + tgtY
      end
    else
      if slot == "enemy" or slot == "enemy2" then
        return px + atkX, py + atkY
      elseif slot == "player" or slot == "player2" then
        return px + tgtX, py + tgtY
      end
    end
    return px, py
  end

  local origStepBattle = Game3.stepBattle
  function Game3:stepBattle(dt)
    -- Step SE against post-dt time BEFORE orig may clear moveAnim at dur.
    local b = self.battle
    local ma = b and b.moveAnim
    if ma and ma.ruby and ma.seChain then
      local saved = ma.t or 0
      ma.t = saved + (dt or 0)
      MA.stepSeChain(self, ma)
      ma.t = saved
    end
    origStepBattle(self, dt)
  end
end

return MA