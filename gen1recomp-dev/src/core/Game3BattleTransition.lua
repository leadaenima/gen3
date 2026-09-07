-- Ruby/Sapphire battle entrance transitions for Game3.
-- Reference: pokeruby battle_transition.c + battle_setup.c
--
-- Gen1 src/render/BattleTransition.lua (spirals) and Gen2 ui/gen2 are NOT
-- used — those belong to older gens. This approximates GBA scanline/window
-- wipes with LÖVE rects over the live overworld.
--
-- Timing is frame-based at 60 fps to track ROM task loops:
--   Phase1 CreatePhase1Task(0,0,3,2,2) → 3 grey pulses × 8+8 frames = 48f
--   Slice  Phase2_Transition_Slice_Func2 → ~37f (accelerating WIN0H)
--   Wave   Phase2_Transition_Wave_Func2  → ~35f (data[1]+=8, amp 40)
--   Grid   Phase2_Transition_GridSquares → ~56f (14×3 + hold 16)
--   Trail  PokeballsTrail                → ~98f (delays + 8px/f cross)
--   Mugshot Sydney..Steven               → ~167f Phase2 (curtain30+slides48+white73+black16)

local BT = {}

-- battle_transition.h
BT.BLUR = 0
BT.SWIRL = 1
BT.SHUFFLE = 2
BT.BIG_POKEBALL = 3
BT.POKEBALLS_TRAIL = 4
BT.CLOCKWISE_BLACKFADE = 5
BT.RIPPLE = 6
BT.WAVE = 7
BT.SLICE = 8
BT.WHITEFADE = 9
BT.GRID_SQUARES = 10
BT.SHARDS = 11
BT.SYDNEY = 12
BT.PHOEBE = 13
BT.GLACIA = 14
BT.DRAKE = 15
BT.STEVEN = 16

-- battle_setup.c gBattleTransitionTable_Wild / _Trainer
-- rows: normal, cave, cave+flash, water ; cols: weaker enemy, stronger/equal
BT.WILD_TABLE = {
  [0] = { BT.SLICE, BT.WHITEFADE },
  [1] = { BT.CLOCKWISE_BLACKFADE, BT.GRID_SQUARES },
  [2] = { BT.BLUR, BT.GRID_SQUARES },
  [3] = { BT.WAVE, BT.RIPPLE },
}
BT.TRAINER_TABLE = {
  [0] = { BT.POKEBALLS_TRAIL, BT.SHARDS },
  [1] = { BT.SHUFFLE, BT.BIG_POKEBALL },
  [2] = { BT.BLUR, BT.GRID_SQUARES },
  [3] = { BT.SWIRL, BT.RIPPLE },
}

-- Phase2 wipe lengths in frames (after Phase1). Derived / measured above.
BT.WIPE_FRAMES = {
  [BT.SLICE] = 37,
  [BT.WAVE] = 35,
  [BT.RIPPLE] = 40,
  [BT.GRID_SQUARES] = 56,
  [BT.SHARDS] = 90,
  [BT.WHITEFADE] = 70,
  [BT.CLOCKWISE_BLACKFADE] = 80,
  [BT.SWIRL] = 70,
  [BT.POKEBALLS_TRAIL] = 98,
  [BT.SHUFFLE] = 60,
  [BT.BIG_POKEBALL] = 75,
  [BT.BLUR] = 55, -- mosaic 15×4 + fade ≈
  -- Mugshot Phase2 total (battle_transition.c Phase2_Mugshot_Func1..10):
  -- curtain 30 + opp slide 24 + ply slide 24 + white BLDY 73 + black 16 + no separate setup = 167f (curtain+slides+fades).
  [BT.SYDNEY] = 167,
  [BT.PHOEBE] = 167,
  [BT.GLACIA] = 167,
  [BT.DRAKE] = 167,
  [BT.STEVEN] = 167,
}

-- Mugshot id offset: BT.SYDNEY..STEVEN map to MUGSHOT_SYDNEY..STEVEN (0..4).
BT.MUGSHOT_BASE = BT.SYDNEY
BT.SE_MUGSHOT = 104 -- songs.h SE_MUGSHOT / SE_BT_START

-- steven_bg.pal / elite-four mugshot BG accents (JASC RGB/255).
BT.MUGSHOT_PALS = {
  -- Sidney, Phoebe, Glacia, Drake, Steven
  [0] = { {0.20, 0.12, 0.28}, {0.55, 0.35, 0.70}, {0.85, 0.75, 0.35} },
  [1] = { {0.35, 0.10, 0.22}, {0.75, 0.35, 0.55}, {0.95, 0.85, 0.90} },
  [2] = { {0.10, 0.18, 0.35}, {0.35, 0.55, 0.85}, {0.85, 0.90, 0.98} },
  [3] = { {0.12, 0.22, 0.12}, {0.25, 0.55, 0.30}, {0.85, 0.80, 0.40} },
  [4] = { {0.67, 0.19, 0.19}, {0.55, 0.55, 0.55}, {0.90, 0.90, 0.40} },
}

-- sMugshotsOpponentRotationScales / 0x100 and start offsets (battle_transition.c).
BT.MUGSHOT_OPP_SCALE = { 2.00, 2.00, 1.69, 1.63, 1.53 }
BT.MUGSHOT_OPP_Y = { 42, 42, 46, 47, 49 }

-- Phase2_Mugshot_* frame budgets (see verify / battle_transition.c).
BT.MUG_CURTAIN_FRAMES = 30   -- Func3: data[2]+=8 from 1 to 0xF0
BT.MUG_OPP_SLIDE_FRAMES = 24 -- +12 px/f x12 then decelerate 12f
BT.MUG_PLY_SLIDE_FRAMES = 24
BT.MUG_WHITE_FRAMES = 73     -- Func7 BLDY expand-to-center
BT.MUG_BLACK_FRAMES = 16     -- Func9 BLDY 1..16
-- Opponent start x = coords[0]-32; player starts at 272 (Mugshots_CreateOpponentPlayerSprites).
BT.MUG_OPP_START_X = { -32, -32, -36, -32, -32 }
BT.MUG_OPP_STOP_X = 103
BT.MUG_PLY_START_X = 272
BT.MUG_PLY_STOP_X = 133
BT.MUG_SLIDE_SPEED = 12

-- CreatePhase1Task(0, 0, 3, 2, 2): 3 cycles, blend ±2/frame → 8 up + 8 down
BT.PHASE1_FRAMES = 48
BT.PHASE1_CYCLES = 3
BT.PHASE1_HALF = 8 -- frames per fade direction
BT.HOLD_FRAMES = 5 -- brief black after wipe (ROM load gap stand-in)

local W, H = 240, 160
local FPS = 60

-- PokeballsTrail: sUnknown_083FD7E4 / 083FD7E8 / 083FD7F2
local TRAIL_START_X = { -16, 256 }
local TRAIL_DELAYS = { 0, 32, 64, 18, 48 }
local TRAIL_SPEED = 8 -- |dx| per frame

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function resolveStyle(id)
  id = tonumber(id) or BT.SLICE
  if BT.WIPE_FRAMES[id] then return id end
  return BT.SLICE
end

local function isMugshot(id)
  id = tonumber(id) or -1
  return id >= BT.SYDNEY and id <= BT.STEVEN
end

local function mugshotIndex(id)
  return (tonumber(id) or BT.STEVEN) - BT.MUGSHOT_BASE
end

-- Precompute Slice data[1] progression (Phase2_Transition_Slice_Func2).
local SLICE_PROG = {}
do
  local d1, d2, d3 = 0, 256, 1
  for frame = 1, 80 do
    d1 = d1 + math.floor(d2 / 256)
    if d1 > 0xF0 then d1 = 0xF0 end
    if d2 <= 0xFFF then d2 = d2 + d3 end
    if d3 < 128 then d3 = d3 * 2 end
    SLICE_PROG[frame] = d1
    if d1 > 0xEF then break end
  end
end

function BT.attach(Game3)
  Game3.B_TRANSITION_SLICE = BT.SLICE
  Game3.B_TRANSITION_WAVE = BT.WAVE
  Game3.B_TRANSITION_GRID_SQUARES = BT.GRID_SQUARES
  Game3.B_TRANSITION_SHARDS = BT.SHARDS
  Game3.B_TRANSITION_WHITEFADE = BT.WHITEFADE
  Game3.B_TRANSITION_CLOCKWISE = BT.CLOCKWISE_BLACKFADE
  Game3.B_TRANSITION_POKEBALLS_TRAIL = BT.POKEBALLS_TRAIL
  Game3.B_TRANSITION_SYDNEY = BT.SYDNEY
  Game3.B_TRANSITION_PHOEBE = BT.PHOEBE
  Game3.B_TRANSITION_GLACIA = BT.GLACIA
  Game3.B_TRANSITION_DRAKE = BT.DRAKE
  Game3.B_TRANSITION_STEVEN = BT.STEVEN
  Game3.SE_MUGSHOT = BT.SE_MUGSHOT

  -- GetBattleTransitionTypeByMap (battle_setup.c)
  function Game3:battleTransitionMapKind()
    local map = self.map
    local t = map and (map.mapType or 0) or 0
    -- Overworld_GetFlashLevel()
    if (self.flashLevel or 0) > 0 then
      return 2
    end
    local behavior = self:behaviorAt(map, self.playerX, self.playerY)
    local surfable = Game3.isSurfable(behavior) and true or false
    if self.surfing then surfable = true end
    if not surfable then
      if t == Game3.MAP_TYPE_UNDERGROUND then return 1 end
      if t == Game3.MAP_TYPE_UNDERWATER then return 3 end
      return 0
    end
    return 3
  end

  -- GetSumOfPlayerPartyLevel
  function Game3:sumPlayerPartyLevel(numMons)
    numMons = tonumber(numMons) or 1
    local sum = 0
    local party = self.party or {}
    for i = 1, #party do
      local mon = party[i]
      if mon and self:canBattle(mon) then
        sum = sum + (tonumber(mon.level) or 1)
        numMons = numMons - 1
        if numMons <= 0 then break end
      end
    end
    return sum
  end

  -- GetWildBattleTransition
  function Game3:pickWildBattleTransition(enemyLevel)
    local kind = self:battleTransitionMapKind()
    local row = BT.WILD_TABLE[kind] or BT.WILD_TABLE[0]
    local playerLevel = self:sumPlayerPartyLevel(1)
    enemyLevel = tonumber(enemyLevel) or 1
    if enemyLevel < playerLevel then
      return row[1]
    end
    return row[2]
  end

  -- GetTrainerBattleTransition (battle_setup.c). Elite Four + Champion use
  -- mugshot transitions (trainer front pic + elite_four_bg palette), not SHARDS.
  -- Gym leaders stay on the normal trainer table in RS.
  function Game3:pickTrainerBattleTransition(npc)
    local id = npc and tonumber(npc.trainerId) or 0
    local tr = id > 0 and self:trainerRow(id) or nil
    -- Class may be a string name, numeric TRAINER_CLASS_*, or missing (use row).
    local classRaw = (npc and npc.trainerClass) or (npc and npc.className)
      or (tr and tr.className) or (tr and tr.class)
    local classId = tonumber(classRaw) or tonumber(npc and npc.class)
      or tonumber(tr and tr.class) or tonumber(tr and tr.trainerClass)
    local classUpper = tostring(classRaw or ""):upper()
    local elite = (classId == (Game3.TRAINER_CLASS_ELITE_FOUR or 24))
      or classUpper:find("ELITE", 1, true) ~= nil
    local champion = (classId == (Game3.TRAINER_CLASS_CHAMPION or 32))
      or classUpper:find("CHAMPION", 1, true) ~= nil
    -- Direct trainer-id shortcuts (ROM compares opponent id inside E4 class).
    if id == (Game3.TRAINER_SIDNEY or 261) then return BT.SYDNEY end
    if id == (Game3.TRAINER_PHOEBE or 262) then return BT.PHOEBE end
    if id == (Game3.TRAINER_GLACIA or 263) then return BT.GLACIA end
    if id == (Game3.TRAINER_DRAKE or 264) then return BT.DRAKE end
    if id == (Game3.TRAINER_STEVEN or 335) or champion then return BT.STEVEN end
    if elite then
      -- Unknown Elite Four row: Steven mugshot is the ROM fallback.
      return BT.STEVEN
    end
    local kind = self:battleTransitionMapKind()
    local row = BT.TRAINER_TABLE[kind] or BT.TRAINER_TABLE[0]
    local minCount = (npc and npc.doubleBattle) and 2 or 1
    local enemyLevel = 0
    local party = npc and npc.party
    if type(party) == "table" then
      local n = math.min(minCount, #party)
      for i = 1, n do
        enemyLevel = enemyLevel + (tonumber(party[i].level) or 1)
      end
    end
    local playerLevel = self:sumPlayerPartyLevel(minCount)
    if enemyLevel < playerLevel then
      return row[1]
    end
    return row[2]
  end

  -- Mugshots_CreateOpponentPlayerSprites stand-in: reuse battle trainer sheets.
  function Game3:buildMugshotState(transitionId, npc)
    local mi = mugshotIndex(transitionId)
    if mi < 0 then mi = 4 end
    if mi > 4 then mi = 4 end
    local oppImg = nil
    if self.opponentTrainerImage then
      oppImg = self:opponentTrainerImage(npc)
    end
    -- Mugshot trainer-pic fallbacks (sMugshotsTrainerPicIDsTable).
    -- Sidney/Phoebe/Glacia/Drake/Steven = ruby_79..82 / ruby_29.
    if not oppImg then
      local picFallback = ({ [0]=79, [1]=80, [2]=81, [3]=82, [4]=29 })[mi]
      local path = picFallback and self.trainerRubyPicPath and self:trainerRubyPicPath(picFallback)
      if path and self.grabImage then
        oppImg = self:grabImage(path)
      end
      if not oppImg and mi == 4 and self.grabImage then
        oppImg = self:grabImage("assets/generated/battle/transitions/steven_mugshot.png")
      end
    end
    local playerImg = self.playerTrainerBattleImage and self:playerTrainerBattleImage() or nil
    local bgNames = { [0]="sidney", [1]="phoebe", [2]="glacia", [3]="drake", [4]="steven" }
    local bgKey = bgNames[mi] or "steven"
    local bgPath = "assets/generated/battle/transitions/mugshot_bg_" .. bgKey .. "_240.png"
    -- Female player: may-tint BG (player pal slots 10-15); male uses Brendan merge default.
    if self.isFemale and self:isFemale() then
      bgPath = "assets/generated/battle/transitions/mugshot_bg_" .. bgKey .. "_may.png"
    end
    local bgImg = self.grabImage and self:grabImage(bgPath) or nil
    if not bgImg and self.grabImage then
      bgImg = self:grabImage("assets/generated/battle/transitions/mugshot_bg_" .. bgKey .. "_240.png")
    end
    local startX = BT.MUG_OPP_START_X[mi + 1] or -32
    return {
      index = mi,
      opponent = oppImg,
      player = playerImg,
      scale = BT.MUGSHOT_OPP_SCALE[mi + 1] or 1.53,
      oppY = BT.MUGSHOT_OPP_Y[mi + 1] or 49,
      pal = BT.MUGSHOT_PALS[mi] or BT.MUGSHOT_PALS[4],
      bg = bgImg,
      bgName = bgKey,
      sePlayed = false,
      -- Sprite slide state (sub_811C984 / sub_811C9B8).
      mugPhase = "curtain",
      curtainF = 0,
      scrollL = 0,
      scrollR = 0,
      oppX = startX,
      oppVel = BT.MUG_SLIDE_SPEED,
      oppSliding = true,
      oppDecel = false,
      plyX = BT.MUG_PLY_START_X,
      plyVel = -BT.MUG_SLIDE_SPEED,
      plySliding = false,
      plyDecel = false,
      whiteF = 0,
      blackF = 0,
      whiteLevel = 0, -- 0..16 approximate BLDY peak
    }
  end

  function Game3:beginBattleEntrance(transitionId, onDone, mugshot)
    local style = resolveStyle(transitionId)
    self.battleEntrance = {
      id = style,
      rawId = transitionId,
      phase = "phase1",
      frame = 0,
      -- Slice acceleration state mirrors ROM task data[1..3]
      sliceD1 = 0,
      sliceD2 = 256,
      sliceD3 = 1,
      -- Wave
      waveD1 = 0,
      waveD2 = 0,
      mugshot = mugshot,
      onDone = onDone,
    }
    self.phase = "battle_transition"
    return true
  end

  function Game3:finishBattleEntrance()
    local e = self.battleEntrance
    local cb = e and e.onDone
    self.battleEntrance = nil
    if cb then cb() end
  end

  -- Advance one logical frame (logicStep already scales by GAME SPEED).
  function Game3:stepBattleEntrance(dt)
    local e = self.battleEntrance
    if not e then return end
    -- Accumulate real dt into 60 Hz frames so variable dt still tracks ROM.
    e.acc = (e.acc or 0) + (dt or 0)
    local step = 1 / FPS
    while e.acc >= step do
      e.acc = e.acc - step
      if not self:tickBattleEntranceFrame() then
        break
      end
    end
  end

  function Game3:tickBattleEntranceFrame()
    local e = self.battleEntrance
    if not e then return false end
    e.frame = (e.frame or 0) + 1

    if e.phase == "phase1" then
      if e.frame >= BT.PHASE1_FRAMES then
        e.phase = "wipe"
        e.frame = 0
        e.sliceD1, e.sliceD2, e.sliceD3 = 0, 256, 1
        e.waveD1, e.waveD2 = 0, 0
      end
      return true
    end

    if e.phase == "wipe" then
      -- Advance style-specific ROM counters for draw.
      if isMugshot(e.id) then
        BT.tickMugshot(e)
        if e.mugshot and e.mugshot.mugPhase == "done" then
          e.phase = "hold"
          e.frame = 0
        end
        return true
      end
      if e.id == BT.SLICE then
        e.sliceD1 = e.sliceD1 + math.floor(e.sliceD2 / 256)
        if e.sliceD1 > 0xF0 then e.sliceD1 = 0xF0 end
        if e.sliceD2 <= 0xFFF then e.sliceD2 = e.sliceD2 + e.sliceD3 end
        if e.sliceD3 < 128 then e.sliceD3 = e.sliceD3 * 2 end
      elseif e.id == BT.WAVE or e.id == BT.RIPPLE then
        e.waveD2 = e.waveD2 + 16
        e.waveD1 = e.waveD1 + 8
      end

      local need = BT.WIPE_FRAMES[e.id] or 40
      local done = e.frame >= need
      if e.id == BT.SLICE and e.sliceD1 > 0xEF then done = true end
      if (e.id == BT.WAVE or e.id == BT.RIPPLE) and e.waveD1 >= 280 then
        done = true
      end
      if done then
        e.phase = "hold"
        e.frame = 0
      end
      return true
    end

    if e.phase == "hold" then
      if e.frame >= BT.HOLD_FRAMES then
        self:finishBattleEntrance()
        return false
      end
    end
    return true
  end

  -- Phase1 grey alpha from BlendPalettes(..., coeff, RGB(11,11,11)).
  -- coeff walks 2,4,..16 then 14,..0 per half; 3 cycles.
  function Game3:battleEntranceGreyAlpha()
    local e = self.battleEntrance
    if not (e and e.phase == "phase1") then return 0 end
    local f = e.frame or 0
    local cycleLen = BT.PHASE1_HALF * 2 -- 16
    local into = (f - 1) % cycleLen
    local coeff
    if into < BT.PHASE1_HALF then
      coeff = (into + 1) * 2 -- 2..16
    else
      coeff = 16 - ((into - BT.PHASE1_HALF + 1) * 2) -- 14..0
      if coeff < 0 then coeff = 0 end
    end
    -- RGB(11,11,11) blend at coeff/16
    return (coeff / 16) * 0.55
  end

  function Game3:battleEntranceWipeU()
    local e = self.battleEntrance
    if not e then return 0 end
    if e.phase == "hold" then return 1 end
    if e.phase ~= "wipe" then return 0 end
    if isMugshot(e.id) then
      local mug = e.mugshot or {}
      local phase = mug.mugPhase or "curtain"
      local c, o, p, w, b = BT.MUG_CURTAIN_FRAMES, BT.MUG_OPP_SLIDE_FRAMES,
        BT.MUG_PLY_SLIDE_FRAMES, BT.MUG_WHITE_FRAMES, BT.MUG_BLACK_FRAMES
      local total = c + o + p + w + b
      local done = 0
      if phase == "curtain" then
        done = mug.curtainF or 0
      elseif phase == "opp_slide" then
        done = c + math.min(o, (e.frame or 0)) -- approximate; prefer exact below
        -- Recompute from physics progress when possible.
        done = c + (mug.oppDecel and (12 + (BT.MUG_SLIDE_SPEED - (mug.oppVel or 0))) or
          math.max(0, math.floor(((mug.oppX or -32) + 32) / BT.MUG_SLIDE_SPEED)))
      elseif phase == "ply_slide" then
        done = c + o
        done = done + (mug.plyDecel and (12 + (BT.MUG_SLIDE_SPEED + (mug.plyVel or 0))) or
          math.max(0, math.floor((BT.MUG_PLY_START_X - (mug.plyX or BT.MUG_PLY_START_X)) / BT.MUG_SLIDE_SPEED)))
      elseif phase == "white_fade" then
        done = c + o + p + (mug.whiteF or 0)
      elseif phase == "black_fade" then
        done = c + o + p + w + (mug.blackF or 0)
      else
        done = total
      end
      return clamp(done / total, 0, 1)
    end
    if e.id == BT.SLICE then
      return clamp(e.sliceD1 / 0xF0, 0, 1)
    end
    if e.id == BT.WAVE or e.id == BT.RIPPLE then
      return clamp(e.waveD1 / 280, 0, 1)
    end
    local need = BT.WIPE_FRAMES[e.id] or 40
    return clamp((e.frame or 0) / need, 0, 1)
  end

  function Game3:drawBattleEntrance(w, h)
    local e = self.battleEntrance
    if not e then return end
    w = w or W
    h = h or H
    local G = love.graphics

    local grey = self:battleEntranceGreyAlpha()
    if grey > 0 then
      -- RGB(11,11,11) ≈ (11/31)
      G.setColor(11 / 31, 11 / 31, 11 / 31, grey)
      G.rectangle("fill", 0, 0, w, h)
      G.setColor(1, 1, 1, 1)
    end

    if e.phase == "phase1" then return end

    local u = self:battleEntranceWipeU()
    -- Mugshot SE is armed in BT.tickMugshot (Func4) and consumed in drawMugshot.
    BT.drawWipe(G, e, u, w, h, self)
  end

  function Game3:launchBattleWithEntrance(opts)
    opts = opts or {}
    local mode = opts.mode or "wild"
    local skipIntro = opts.skipIntroCinema and true or false

    local function enter()
      self.phase = "battle"
      self.battleEntrance = nil
      local b = self.battle
      local noIntro = skipIntro or (b and b.noIntroCinema)
      if noIntro and b then
        b.kind = "menu"
        b.text = nil
        b.introT = 1
        self:armIntroCinema(mode)
        if b.introCinema then
          b.introCinema.phase = "done"
          self:introMarkAllReleased(b.introCinema)
        end
      else
        self:armIntroCinema(mode)
      end
    end

    -- Battle Scene OFF skips the fancy field wipe (task requirement /
    -- ROM-spirit for “scenes off”). Intro cinema still respects battleSceneOn.
    if not self:battleSceneOn() then
      enter()
      return true
    end

    local id = opts.transitionId
    local npc = opts.npc or (self.battle and self.battle.npc)
    if not id then
      if mode == "trainer" then
        id = self:pickTrainerBattleTransition(npc)
      else
        local enemy = self.battle and self.battle.enemy
        id = self:pickWildBattleTransition(enemy and enemy.level)
      end
    end
    local mug = nil
    if isMugshot(id) then
      mug = self:buildMugshotState(id, npc)
    end
    return self:beginBattleEntrance(id, enter, mug)
  end
end

-- Phase2_Mugshot_Func3..9 stand-in (battle_transition.c).
function BT.tickMugshot(e)
  local mug = e.mugshot
  if not mug then
    return
  end
  -- BG halves scroll opposite directions every frame once curtain starts (HBlankCB).
  mug.scrollL = (mug.scrollL or 0) - 8
  mug.scrollR = (mug.scrollR or 0) + 8
  local phase = mug.mugPhase or "curtain"

  if phase == "curtain" then
    mug.curtainF = (mug.curtainF or 0) + 1
    if mug.curtainF >= BT.MUG_CURTAIN_FRAMES then
      mug.mugPhase = "opp_slide"
      mug.oppSliding = true
      mug.oppDecel = false
      mug.oppVel = BT.MUG_SLIDE_SPEED
      if not mug.sePlayed then
        mug.sePlayed = true
        -- SE played when opponent starts sliding (Phase2_Mugshot_Func4).
        e._mugPlaySe = true
      end
    end
    return
  end

  if phase == "opp_slide" then
    if not mug.oppDecel then
      mug.oppX = (mug.oppX or -32) + (mug.oppVel or BT.MUG_SLIDE_SPEED)
      if mug.oppX > BT.MUG_OPP_STOP_X then
        mug.oppDecel = true
      end
    else
      mug.oppVel = (mug.oppVel or BT.MUG_SLIDE_SPEED) - 1
      mug.oppX = mug.oppX + mug.oppVel
      if mug.oppVel == 0 then
        mug.mugPhase = "ply_slide"
        mug.plySliding = true
        mug.plyDecel = false
        mug.plyVel = -BT.MUG_SLIDE_SPEED
      end
    end
    return
  end

  if phase == "ply_slide" then
    if not mug.plyDecel then
      mug.plyX = (mug.plyX or BT.MUG_PLY_START_X) + (mug.plyVel or -BT.MUG_SLIDE_SPEED)
      if mug.plyX < BT.MUG_PLY_STOP_X then
        mug.plyDecel = true
      end
    else
      mug.plyVel = (mug.plyVel or -BT.MUG_SLIDE_SPEED) + 1
      mug.plyX = mug.plyX + mug.plyVel
      if mug.plyVel == 0 then
        mug.mugPhase = "white_fade"
        mug.whiteF = 0
        mug.whiteLevel = 0
      end
    end
    return
  end

  if phase == "white_fade" then
    mug.whiteF = (mug.whiteF or 0) + 1
    -- Approximate Func7: BLDY grows from center over 73f to full white.
    mug.whiteLevel = math.min(16, math.floor(mug.whiteF * 16 / BT.MUG_WHITE_FRAMES))
    if mug.whiteF >= BT.MUG_WHITE_FRAMES then
      mug.mugPhase = "black_fade"
      mug.blackF = 0
      mug.whiteLevel = 16
    end
    return
  end

  if phase == "black_fade" then
    mug.blackF = (mug.blackF or 0) + 1
    if mug.blackF >= BT.MUG_BLACK_FRAMES then
      mug.mugPhase = "done"
    end
    return
  end
end

function BT.drawWipe(G, e, u, w, h, game)
  local id = e.id
  if isMugshot(id) then
    BT.drawMugshot(G, e, u, w, h, game)
    return
  end
  G.setColor(0, 0, 0, 1)
  if id == BT.SLICE then
    BT.drawSlice(G, e, w, h)
  elseif id == BT.WAVE or id == BT.RIPPLE then
    BT.drawWave(G, e, w, h, id == BT.RIPPLE)
  elseif id == BT.GRID_SQUARES then
    BT.drawGridSquares(G, u, w, h)
  elseif id == BT.SHARDS then
    BT.drawShards(G, u, w, h)
  elseif id == BT.WHITEFADE then
    BT.drawWhiteFade(G, u, w, h)
  elseif id == BT.CLOCKWISE_BLACKFADE or id == BT.SWIRL then
    BT.drawClockwise(G, u, w, h)
  elseif id == BT.POKEBALLS_TRAIL then
    BT.drawPokeballTrail(G, e.frame or 0, w, h)
  elseif id == BT.SHUFFLE then
    BT.drawShuffle(G, u, w, h)
  elseif id == BT.BIG_POKEBALL then
    BT.drawBigCircle(G, u, w, h)
  elseif id == BT.BLUR then
    G.setColor(0, 0, 0, u)
    G.rectangle("fill", 0, 0, w, h)
  else
    BT.drawSlice(G, e, w, h)
  end
  G.setColor(1, 1, 1, 1)
end

-- Phase2_Mugshot: elite_four_bg tilemap + opponent/player pals (battle_transition.c
-- Phase2_Mugshot_Func2) baked to mugshot_bg_<name>_240.png; chevron fallback.
-- Uses existing ruby_<pic>.png / cinema trainer fronts (TRAINER_PIC_STEVEN=29).
function BT.drawMugshot(G, e, u, w, h, game)
  local mug = e.mugshot or {}
  local pal = mug.pal or BT.MUGSHOT_PALS[4]
  local dark, mid, accent = pal[1], pal[2], pal[3]
  local sx = w / W
  local sy = h / H

  -- Play SE once when opponent slide begins (set by tickMugshot).
  if e._mugPlaySe and game and game.playSe then
    e._mugPlaySe = false
    game:playSe(game.SE_MUGSHOT or BT.SE_MUGSHOT)
  end

  -- Prefer decoded elite_four_bg_map.bin render; fall back to procedural chevrons.
  local bg = mug.bg
  if (not bg) and game and game.grabImage and mug.bgName then
    -- Prefer 256-wide sheet for HOFS wrap; fall back to 240 crop.
    bg = game:grabImage("assets/generated/battle/transitions/mugshot_bg_" .. mug.bgName .. ".png")
      or game:grabImage("assets/generated/battle/transitions/mugshot_bg_" .. mug.bgName .. "_240.png")
    mug.bg = bg
  end

  local phase = mug.mugPhase or "curtain"
  local curtainU = 1
  if phase == "curtain" then
    curtainU = clamp((mug.curtainF or 0) / BT.MUG_CURTAIN_FRAMES, 0, 1)
  end

  -- Draw BG with opposite HOFS on top/bottom halves (HBlankCB_Phase2_Mugshots).
  local function drawBgHalf(y0, y1, scroll)
    local clipH = y1 - y0
    if clipH <= 0 then return end
    if bg and bg.getDimensions then
      local bw, bh = bg:getDimensions()
      local scx, scy = w / W, h / H
      if G.setScissor then G.setScissor(0, y0, w, clipH) end
      G.setColor(1, 1, 1, 1)
      local period = bw
      local ox = -((((scroll % period) + period) % period) * scx)
      G.draw(bg, ox, 0, 0, scx, scy)
      G.draw(bg, ox + period * scx, 0, 0, scx, scy)
      if G.setScissor then G.setScissor() end
    else
      local band = math.max(6, math.floor(8 * sy))
      for y = y0, y1 - 1, band do
        local shift = math.floor(scroll * 0.5 + (y - y0) * 0.35) % w
        local c = ((math.floor((y - y0) / band) % 2) == 0) and dark or mid
        G.setColor(c[1], c[2], c[3], 1)
        G.rectangle("fill", 0, y, w, math.min(band, y1 - y))
        G.setColor(accent[1], accent[2], accent[3], 0.35)
        local x0 = (shift % (band * 2)) - band
        while x0 < w do
          G.polygon("fill",
            x0, y,
            x0 + band, y,
            x0 + band * 2, y + band,
            x0 + band, y + band)
          x0 = x0 + band * 2
        end
      end
    end
  end

  local midY = math.floor(h * 0.5)
  drawBgHalf(0, midY, mug.scrollL or 0)
  drawBgHalf(midY, h, mug.scrollR or 0)

  -- Curtain reveal: black windows close from sides (Func3 WIN0H sine stand-in).
  if curtainU < 1 then
    local open = curtainU
    local left = math.floor((1 - open) * w * 0.5)
    local right = w - left
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, left, h)
    G.rectangle("fill", right, 0, w - right, h)
  end

  -- Sprites after curtain (hidden during curtain like ROM until Func4).
  if phase ~= "curtain" then
    -- ROM CreateTrainerSprite y: opponent = coords[1]+42 (= MUGSHOT_OPP_Y), player = 106.
    -- drawBattleTrainerPic treats (x,y) as top-left of the 64x64 frame before scale.
    local scale = mug.scale or 1.53
    local oppY = (mug.oppY or 49) * sy
    local plyY = (106 - 32) * sy
    local oppX = (mug.oppX or -32) * sx
    local plyX = (mug.plyX or BT.MUG_PLY_START_X) * sx - 32 * sx
    if game and game.drawBattleTrainerPic then
      if mug.opponent then
        game:drawBattleTrainerPic(mug.opponent, oppX, oppY, scale * (w / W), 1, false)
      end
      -- Player exists off-screen during opp_slide (x=272); draw once curtain opens.
      if mug.player then
        game:drawBattleTrainerPic(mug.player, plyX, plyY, 1.0 * (w / W), 1, true)
      end
    end
  end

  -- White fade from center (Func7/8): rising white overlay.
  if phase == "white_fade" or phase == "black_fade" or phase == "done" then
    local wl = (mug.whiteLevel or 0) / 16
    if wl > 0 then
      G.setColor(1, 1, 1, wl)
      G.rectangle("fill", 0, 0, w, h)
    end
  end

  -- Black fade (Func9): BLDY toward black after full white.
  if phase == "black_fade" or phase == "done" then
    local bf = clamp((mug.blackF or 0) / BT.MUG_BLACK_FRAMES, 0, 1)
    G.setColor(0, 0, 0, bf)
    G.rectangle("fill", 0, 0, w, h)
  end

  if e.phase == "hold" then
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, w, h)
  end
  G.setColor(1, 1, 1, 1)
end

-- Alternating scanline WIN0H from Phase2_Transition_Slice_Func2.
-- Odd lines: black from right by data[1]; even: black from left by data[1].
-- (BG HOFS shift omitted — black windows carry the read.)
function BT.drawSlice(G, e, w, h)
  local prog = e.sliceD1 or 0
  -- Scale 240-space progress to current draw width.
  local sx = w / W
  prog = prog * sx
  for y = 0, h - 1 do
    if (y % 2) == 1 then
      local left = w - prog
      if left < w then
        G.rectangle("fill", math.max(0, left), y, w - math.max(0, left), 1)
      end
    else
      if prog > 0 then
        G.rectangle("fill", 0, y, math.min(w, prog), 1)
      end
    end
  end
end

-- Wave: WIN0H left edge = data[1] + Sin(r5, 40); r5 += 4 per line, data[1]+=8/f
function BT.drawWave(G, e, w, h, ripple)
  local base = e.waveD1 or 0
  local phase = e.waveD2 or 0
  local amp = ripple and 28 or 40
  local sx = w / W
  for y = 0, h - 1 do
    -- GBA Sin(index, amp): index is 0..255 angle. r5 starts at data[2], +=4/line.
    local idx = (phase + y * 4) % 256
    local sinv = math.sin(idx / 256 * math.pi * 2) * amp
    local edge = (base + sinv) * sx
    edge = clamp(edge, 0, w)
    if edge > 0 then
      G.rectangle("fill", 0, y, edge, 1)
    end
  end
end

-- GridSquares: shrinking box tiles; u maps 14 tile steps + hold.
function BT.drawGridSquares(G, u, w, h)
  local cell = 16
  -- data[2] 1..14 over first ~42f, then solid. Map u→inset.
  local grow = clamp(u / (42 / 56), 0, 1)
  local inset = grow * (cell * 0.5)
  for y = 0, h - 1, cell do
    for x = 0, w - 1, cell do
      local cw = math.min(cell, w - x)
      local ch = math.min(cell, h - y)
      if inset >= cell * 0.5 - 0.5 then
        G.rectangle("fill", x, y, cw, ch)
      elseif inset > 0 then
        G.rectangle("fill", x + inset, y + inset, cw - inset * 2, ch - inset * 2)
      end
    end
  end
end

-- Shards: sUnknown_083FD8F4 band sweeps (diagonal windows).
function BT.drawShards(G, u, w, h)
  local bands = {
    { y0 = 0, y1 = 32, dir = 1, delay = 0.00 },
    { y0 = 32, y1 = 56, dir = -1, delay = 0.10 },
    { y0 = 56, y1 = 88, dir = -1, delay = 0.18 },
    { y0 = 88, y1 = 112, dir = 1, delay = 0.28 },
    { y0 = 112, y1 = 140, dir = -1, delay = 0.38 },
    { y0 = 140, y1 = 160, dir = 1, delay = 0.48 },
  }
  local sy = h / H
  for _, band in ipairs(bands) do
    local localU = clamp((u - band.delay) / math.max(0.01, 1 - band.delay), 0, 1)
    local prog = localU * (w + 20)
    local y0 = band.y0 * sy
    local y1 = math.min(band.y1 * sy, h)
    if band.dir > 0 then
      G.rectangle("fill", 0, y0, prog, y1 - y0)
    else
      G.rectangle("fill", w - prog, y0, prog, y1 - y0)
    end
  end
end

-- WhiteFade: white bars then black (BLDY 0..16).
function BT.drawWhiteFade(G, u, w, h)
  if u < 0.55 then
    local a = u / 0.55
    G.setColor(1, 1, 1, a)
    G.rectangle("fill", 0, 0, w, h)
  else
    local a = (u - 0.55) / 0.45
    G.setColor(1, 1, 1, 1 - a)
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(0, 0, 0, a)
    G.rectangle("fill", 0, 0, w, h)
  end
end

function BT.drawClockwise(G, u, w, h)
  local cx, cy = w * 0.5, h * 0.5
  local steps = 64
  local ang = u * math.pi * 2
  local r = math.max(w, h)
  for i = 0, steps - 1 do
    local a0 = (i / steps) * math.pi * 2 - math.pi * 0.5
    local a1 = ((i + 1) / steps) * math.pi * 2 - math.pi * 0.5
    if a0 >= ang then break end
    if a1 > ang then a1 = ang end
    G.polygon("fill", cx, cy,
      cx + math.cos(a0) * r, cy + math.sin(a0) * r,
      cx + math.cos(a1) * r, cy + math.sin(a1) * r)
  end
end

-- PokeballsTrail: 5 balls at y=16+i*32, start x ±, delay TRAIL_DELAYS, speed 8.
-- Paint black columns behind each ball as it crosses (VRAM stamp approx).
function BT.drawPokeballTrail(G, frame, w, h)
  local sx = w / W
  local sy = h / H
  for i = 0, 4 do
    local delay = TRAIL_DELAYS[i + 1]
    local age = frame - delay
    if age >= 0 then
      local fromRight = (i % 2) == 1
      -- Func2: Random()&1 then ^=1 per ball — alternate sides.
      local startX = fromRight and TRAIL_START_X[2] or TRAIL_START_X[1]
      local dir = fromRight and -TRAIL_SPEED or TRAIL_SPEED
      local x = startX + dir * age
      local y = (i * 32 + 16) * sy
      if fromRight then
        local coverL = math.min(w, (256 - x) * sx)
        if coverL > 0 then
          G.rectangle("fill", w - coverL, y - 16 * sy, coverL, 32 * sy)
        end
      else
        local coverR = math.min(w, (x - (-16)) * sx)
        if coverR > 0 then
          G.rectangle("fill", 0, y - 16 * sy, coverR, 32 * sy)
        end
      end
      local bx = x * sx
      if bx > -16 * sx and bx < w + 16 * sx then
        local r = 10 * sy
        G.circle("fill", bx, y, r)
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", bx - r, y - 1, r * 2, 2)
        G.setColor(0, 0, 0, 1)
      end
    end
  end
end

function BT.drawShuffle(G, u, w, h)
  local band = 8
  for y = 0, h - 1, band * 2 do
    G.rectangle("fill", 0, y, w * u, band)
    local y2 = y + band
    if y2 < h then
      G.rectangle("fill", w * (1 - u), y2, w * u, band)
    end
  end
end

function BT.drawBigCircle(G, u, w, h)
  local cx, cy = w * 0.5, h * 0.5
  local r = u * math.sqrt(cx * cx + cy * cy) * 1.15
  G.circle("fill", cx, cy, r)
end

-- Expose for tests / drivers.
BT.SLICE_PROG = SLICE_PROG
BT.FPS = FPS

return BT
