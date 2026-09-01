-- pokeruby src/contest.c + contest_2.c + contest_effect.c + contest_ai.c
-- Mechanics only. Link contests and painting CG stay parked.
local DATA = require("src.data.contest_rom")

local Contest3 = {}

Contest3.PLAYER_INDEX = 3
Contest3.TURNS = 5
Contest3.STRING_NONE = 255
Contest3.NEXT_FREE = 255

Contest3.ITEM_RED_SCARF = 254
Contest3.ITEM_BLUE_SCARF = 255
Contest3.ITEM_PINK_SCARF = 256
Contest3.ITEM_GREEN_SCARF = 257
Contest3.ITEM_YELLOW_SCARF = 258

Contest3.CAT_COOL = 0
Contest3.CAT_BEAUTY = 1
Contest3.CAT_CUTE = 2
Contest3.CAT_SMART = 3
Contest3.CAT_TOUGH = 4

Contest3.EFF_HIGHLY_APPEALING = 0
Contest3.EFF_USER_MORE_EASILY_STARTLED = 1
Contest3.EFF_GREAT_APPEAL_BUT_NO_MORE_MOVES = 2
Contest3.EFF_REPETITION_NOT_BORING = 3
Contest3.EFF_AVOID_STARTLE_ONCE = 4
Contest3.EFF_AVOID_STARTLE = 5
Contest3.EFF_AVOID_STARTLE_SLIGHTLY = 6
Contest3.EFF_USER_LESS_EASILY_STARTLED = 7
Contest3.EFF_STARTLE_FRONT_MON = 8
Contest3.EFF_SLIGHTLY_STARTLE_PREV_MONS = 9
Contest3.EFF_STARTLE_PREV_MON = 10
Contest3.EFF_STARTLE_PREV_MONS = 11
Contest3.EFF_BADLY_STARTLE_FRONT_MON = 12
Contest3.EFF_BADLY_STARTLE_PREV_MONS = 13
Contest3.EFF_STARTLE_PREV_MON_2 = 14
Contest3.EFF_STARTLE_PREV_MONS_2 = 15
Contest3.EFF_SHIFT_JUDGE_ATTENTION = 16
Contest3.EFF_STARTLE_MON_WITH_JUDGES_ATTENTION = 17
Contest3.EFF_JAMS_OTHERS_BUT_MISS_ONE_TURN = 18
Contest3.EFF_STARTLE_MONS_SAME_TYPE_APPEAL = 19
Contest3.EFF_STARTLE_MONS_COOL_APPEAL = 20
Contest3.EFF_STARTLE_MONS_BEAUTY_APPEAL = 21
Contest3.EFF_STARTLE_MONS_CUTE_APPEAL = 22
Contest3.EFF_STARTLE_MONS_SMART_APPEAL = 23
Contest3.EFF_STARTLE_MONS_TOUGH_APPEAL = 24
Contest3.EFF_MAKE_FOLLOWING_MON_NERVOUS = 25
Contest3.EFF_MAKE_FOLLOWING_MONS_NERVOUS = 26
Contest3.EFF_WORSEN_CONDITION_OF_PREV_MONS = 27
Contest3.EFF_BADLY_STARTLES_MONS_IN_GOOD_CONDITION = 28
Contest3.EFF_BETTER_IF_FIRST = 29
Contest3.EFF_BETTER_IF_LAST = 30
Contest3.EFF_APPEAL_AS_GOOD_AS_PREV_ONES = 31
Contest3.EFF_APPEAL_AS_GOOD_AS_PREV_ONE = 32
Contest3.EFF_BETTER_WHEN_LATER = 33
Contest3.EFF_QUALITY_DEPENDS_ON_TIMING = 34
Contest3.EFF_BETTER_IF_SAME_TYPE = 35
Contest3.EFF_BETTER_IF_DIFF_TYPE = 36
Contest3.EFF_AFFECTED_BY_PREV_APPEAL = 37
Contest3.EFF_IMPROVE_CONDITION_PREVENT_NERVOUSNESS = 38
Contest3.EFF_BETTER_WITH_GOOD_CONDITION = 39
Contest3.EFF_NEXT_APPEAL_EARLIER = 40
Contest3.EFF_NEXT_APPEAL_LATER = 41
Contest3.EFF_MAKE_SCRAMBLING_TURN_ORDER_EASIER = 42
Contest3.EFF_SCRAMBLE_NEXT_TURN_ORDER = 43
Contest3.EFF_EXCITE_AUDIENCE_IN_ANY_CONTEST = 44
Contest3.EFF_BADLY_STARTLE_MONS_WITH_GOOD_APPEALS = 45
Contest3.EFF_BETTER_WHEN_AUDIENCE_EXCITED = 46
Contest3.EFF_DONT_EXCITE_AUDIENCE = 47

-- gContestExcitementTable[contestCategory][moveCategory]
Contest3.EXCITEMENT = {
  [0] = { [0] = 1, [1] = 0, [2] = -1, [3] = -1, [4] = 0 },
  [1] = { [0] = 0, [1] = 1, [2] = 0, [3] = -1, [4] = -1 },
  [2] = { [0] = -1, [1] = 0, [2] = 1, [3] = 0, [4] = -1 },
  [3] = { [0] = -1, [1] = -1, [2] = 0, [3] = 1, [4] = 0 },
  [4] = { [0] = 0, [1] = -1, [2] = -1, [3] = 0, [4] = 1 },
}

local function nz(v)
  return (tonumber(v) or 0) ~= 0
end

function Contest3.moveRow(moveId)
  moveId = tonumber(moveId) or 0
  return DATA.moves[moveId + 1] or DATA.moves[1]
end

function Contest3.effectRow(effect)
  effect = tonumber(effect) or 0
  return DATA.effects[effect + 1] or DATA.effects[1]
end

function Contest3.moveDescription(moveId)
  local row = Contest3.moveRow(moveId)
  return DATA.descriptions[(row.e or 0) + 1] or ""
end

function Contest3.getMoveExcitement(category, moveId)
  local row = Contest3.moveRow(moveId)
  local t = Contest3.EXCITEMENT[category or 0]
  if not t then return 0 end
  return t[row.c or 0] or 0
end

function Contest3.areMovesCombo(lastMove, nextMove)
  local last = Contest3.moveRow(lastMove)
  local nxt = Contest3.moveRow(nextMove)
  local starter = last.s or 0
  if starter == 0 then return 0 end
  local m = nxt.m or {}
  if starter == m[1] or starter == m[2] or starter == m[3] or starter == m[4] then
    return 1
  end
  return 0
end

local function rand(game)
  return game:gbaRandom()
end

local function uniqueRands(game)
  local sp4 = {}
  local i = 0
  local tries = 0
  while i < 4 do
    tries = tries + 1
    sp4[i] = rand(game)
    if tries > 32 then
      sp4[i] = (sp4[i] + i * 17 + tries) % 65536
    end
    local ok = true
    for r2 = 0, i - 1 do
      if sp4[i] == sp4[r2] then
        ok = false
        break
      end
    end
    if ok then i = i + 1 end
  end
  return sp4
end

function Contest3.roundTowardsZero(score)
  score = tonumber(score) or 0
  local absScore = math.abs(score) % 10
  if score < 0 then
    if absScore ~= 0 then score = score - (10 - absScore) end
  else
    score = score - absScore
  end
  return score
end

function Contest3.roundUp(score)
  score = tonumber(score) or 0
  local absScore = math.abs(score) % 10
  if absScore ~= 0 then score = score + (10 - absScore) end
  return score
end

function Contest3.round1Points(mon, category)
  local main, sub1, sub2
  if category == 0 then
    main, sub1, sub2 = mon.cool, mon.tough, mon.beauty
  elseif category == 1 then
    main, sub1, sub2 = mon.beauty, mon.cool, mon.cute
  elseif category == 2 then
    main, sub1, sub2 = mon.cute, mon.beauty, mon.smart
  elseif category == 3 then
    main, sub1, sub2 = mon.smart, mon.cute, mon.tough
  else
    main, sub1, sub2 = mon.tough, mon.smart, mon.cool
  end
  main = tonumber(main) or 0
  sub1 = tonumber(sub1) or 0
  sub2 = tonumber(sub2) or 0
  local sheen = tonumber(mon.sheen) or 0
  return main + math.floor((sub1 + sub2 + sheen) / 2)
end

local function newStatus()
  return {
    appeal = 0, baseAppeal = 0, jam = 0, jamSafetyCount = 0,
    jamReduction = 0, resistant = 0, immune = 0, moreEasilyStartled = 0,
    usedRepeatableMove = 0, nervous = 0, condition = 0, conditionMod = 0,
    hasJudgesAttention = 0, judgesAttentionWasRemoved = 0,
    currMove = 0, prevMove = 0, moveCategory = 0,
    repeatedMove = 0, repeatedPrevMove = 0, moveRepeatCount = 0,
    repeatJam = 0, comboAppealBonus = 0, completedCombo = 0,
    usedComboMove = 0, completedComboFlag = 0,
    nextTurnOrder = Contest3.NEXT_FREE, turnOrderMod = 0, turnOrderModAction = 0,
    turnSkipped = 0, numTurnsSkipped = 0, exploded = 0, noMoreTurns = 0,
    appealTripleCondition = 0, overrideCategoryExcitementMod = 0,
    ranking = 0, pointTotal = 0, attentionLevel = 0,
    effectStringId = Contest3.STRING_NONE,
    effectStringId2 = Contest3.STRING_NONE,
    contestantAnimTarget = 0,
  }
end

local function setStr(st, key)
  st.effectStringId = key
end

local function setStr2(st, key)
  st.effectStringId2 = key
end

local function canUseTurn(st)
  return (st.numTurnsSkipped or 0) == 0 and (st.noMoreTurns or 0) == 0
end

local function allowedToCombo(st)
  return (st.repeatedMove or 0) == 0 and (st.nervous or 0) == 0
end

function Contest3.sortContestants(c, game, mode)
  local sp4 = uniqueRands(game)
  local turn = c.turnOrder
  if mode == 0 then
    local order = {}
    for i = 0, 3 do
      order[i] = i
      for r4 = 0, i - 1 do
        local left = c.round1[order[r4]] or 0
        local right = c.round1[i] or 0
        if left < right or (left == right and sp4[order[r4]] < sp4[i]) then
          for r2 = i, r4 + 1, -1 do
            order[r2] = order[r2 - 1]
          end
          order[r4] = i
          break
        end
      end
    end
    local sp0 = {}
    for i = 0, 3 do sp0[i] = order[i] end
    for i = 0, 3 do turn[sp0[i]] = i end
  else
    local sp0 = { [0] = 255, 255, 255, 255 }
    for i = 0, 3 do
      local r2 = c.status[i].ranking or 0
      while true do
        if sp0[r2] == 255 then
          sp0[r2] = i
          turn[i] = r2
          break
        end
        r2 = r2 + 1
      end
    end
    for i = 0, 2 do
      for r4 = 3, i + 1, -1 do
        local a, b = c.status[r4 - 1], c.status[r4]
        if (a.ranking or 0) == (b.ranking or 0)
          and turn[r4 - 1] < turn[r4]
          and sp4[r4 - 1] < sp4[r4] then
          local tmp = turn[r4]
          turn[r4] = turn[r4 - 1]
          turn[r4 - 1] = tmp
        end
      end
    end
  end
end

function Contest3.applyNextTurnOrder(c)
  local newTurn = {}
  local ordered = { [0] = false, false, false, false }
  for i = 0, 3 do
    newTurn[i] = c.turnOrder[i]
  end
  for i = 0, 3 do
    local found = nil
    for j = 0, 3 do
      if c.status[j].nextTurnOrder == i then
        newTurn[j] = i
        ordered[j] = true
        found = j
        break
      end
    end
    if found == nil then
      local nextC = 0
      local j = 0
      while j < 4 do
        if not ordered[j] and c.status[j].nextTurnOrder == Contest3.NEXT_FREE then
          nextC = j
          j = j + 1
          break
        end
        j = j + 1
      end
      while j < 4 do
        if not ordered[j] and c.status[j].nextTurnOrder == Contest3.NEXT_FREE
          and c.turnOrder[nextC] > c.turnOrder[j] then
          nextC = j
        end
        j = j + 1
      end
      newTurn[nextC] = i
      ordered[nextC] = true
    end
  end
  for i = 0, 3 do
    c.appealResults.turnOrder[i] = newTurn[i]
    c.status[i].nextTurnOrder = Contest3.NEXT_FREE
    c.status[i].turnOrderMod = 0
    c.turnOrder[i] = newTurn[i]
  end
end

function Contest3.rankContestants(c, game)
  local arr = {}
  for i = 0, 3 do
    local st = c.status[i]
    st.pointTotal = (st.pointTotal or 0) + (st.appeal or 0)
    arr[i] = st.pointTotal
  end
  for i = 0, 2 do
    for j = 3, i + 1, -1 do
      if arr[j - 1] < arr[j] then
        local tmp = arr[j]
        arr[j] = arr[j - 1]
        arr[j - 1] = tmp
      end
    end
  end
  for i = 0, 3 do
    for j = 0, 3 do
      if c.status[i].pointTotal == arr[j] then
        c.status[i].ranking = j
        break
      end
    end
  end
  Contest3.sortContestants(c, game, 1)
  Contest3.applyNextTurnOrder(c)
end

function Contest3.setStatusesForNextRound(c)
  for i = 0, 3 do
    local st = c.status[i]
    st.appeal = 0
    st.baseAppeal = 0
    st.jamSafetyCount = 0
    if (st.numTurnsSkipped or 0) > 0 then
      st.numTurnsSkipped = st.numTurnsSkipped - 1
    end
    st.jam = 0
    st.resistant = 0
    st.jamReduction = 0
    st.immune = 0
    st.moreEasilyStartled = 0
    st.usedRepeatableMove = 0
    st.nervous = 0
    st.effectStringId = Contest3.STRING_NONE
    st.effectStringId2 = Contest3.STRING_NONE
    st.conditionMod = 0
    st.repeatedPrevMove = st.repeatedMove
    st.repeatedMove = 0
    st.turnOrderModAction = 0
    st.appealTripleCondition = 0
    if nz(st.turnSkipped) then
      st.numTurnsSkipped = 1
      st.turnSkipped = 0
    end
    if nz(st.exploded) then
      st.noMoreTurns = 1
      st.exploded = 0
    end
    st.overrideCategoryExcitementMod = 0
  end
  for i = 0, 3 do
    local st = c.status[i]
    st.prevMove = st.currMove
    c.moveHistory[c.appealNumber] = c.moveHistory[c.appealNumber] or {}
    c.moveHistory[c.appealNumber][i] = st.prevMove
    st.currMove = 0
  end
  c.excitement.frozen = 0
end

local function canUnnerve(c, i)
  c.appealResults.unnerved[i] = 1
  local st = c.status[i]
  if nz(st.immune) then
    setStr(st, "AVOID_SEEING")
    return false
  end
  if (st.jamSafetyCount or 0) ~= 0 then
    st.jamSafetyCount = st.jamSafetyCount - 1
    setStr(st, "AVERT_GAZE")
    return false
  end
  if (st.noMoreTurns or 0) == 0 and (st.numTurnsSkipped or 0) == 0 then
    return true
  end
  return false
end

local function jamContestant(c, i, jam)
  local st = c.status[i]
  st.appeal = (st.appeal or 0) - jam
  st.jam = (st.jam or 0) + jam
end

local function setStartledString(st, jam)
  if jam >= 60 then setStr(st, "TRIPPED_OVER")
  elseif jam >= 40 then setStr(st, "LEAPT_UP")
  elseif jam >= 30 then setStr(st, "UTTER_CRY")
  elseif jam >= 20 then setStr(st, "TURNED_BACK")
  elseif jam >= 10 then setStr(st, "LOOKED_DOWN")
  end
end

local function wasJammed(c)
  local jamBuffer = { [0] = 0, 0, 0, 0 }
  local q = c.appealResults.jamQueue
  local n = 1
  while q[n] ~= nil and q[n] ~= 255 do
    local contestant = q[n]
    if canUnnerve(c, contestant) then
      local jam2 = c.appealResults.jam
      local st = c.status[contestant]
      if nz(st.moreEasilyStartled) then jam2 = jam2 * 2 end
      if nz(st.resistant) then
        jam2 = 10
        setStr(st, "LITTLE_DISTRACTED")
      else
        jam2 = jam2 - (st.jamReduction or 0)
        if jam2 <= 0 then
          jam2 = 0
          setStr(st, "NOT_FAZED")
        else
          jamContestant(c, contestant, jam2)
          setStartledString(st, jam2)
          jamBuffer[contestant] = jam2
        end
      end
    end
    n = n + 1
  end
  for i = 0, 3 do
    if jamBuffer[i] ~= 0 then return true end
  end
  return false
end

local function startleFront(c)
  local a = c.appealResults.contestant
  local idx = false
  local to = c.appealResults.turnOrder
  if to[a] ~= 0 then
    local i = 0
    while i < 4 do
      if to[a] - 1 == to[i] then break end
      i = i + 1
    end
    c.appealResults.jamQueue = { i, 255 }
    idx = wasJammed(c)
  end
  if not idx then setStr2(c.status[a], "MESSED_UP2") end
  setStr(c.status[a], "ATTEMPT_STARTLE")
end

local function startlePrevMons(c)
  local a = c.appealResults.contestant
  local idx = false
  local to = c.appealResults.turnOrder
  if to[a] ~= 0 then
    local q = {}
    local j = 1
    for i = 0, 3 do
      if to[a] > to[i] then
        q[j] = i
        j = j + 1
      end
    end
    q[j] = 255
    c.appealResults.jamQueue = q
    idx = wasJammed(c)
  end
  if not idx then setStr2(c.status[a], "MESSED_UP2") end
  setStr(c.status[a], "ATTEMPT_STARTLE")
end

local function jamByCategory(c, category)
  local num = 0
  local user = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  for i = 0, 3 do
    if to[user] > to[i] then
      local mv = c.status[i].currMove or 0
      if category == Contest3.moveRow(mv).c then
        c.appealResults.jam = 40
      else
        c.appealResults.jam = 10
      end
      c.appealResults.jamQueue = { i, 255 }
      if wasJammed(c) then num = num + 1 end
    end
  end
  if num == 0 then setStr2(c.status[user], "MESSED_UP2") end
end

local function makeNervous(c, p)
  c.status[p].nervous = 1
  c.status[p].currMove = 0
end

local EFFECTS = {}

EFFECTS[0] = function() end

EFFECTS[1] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.moreEasilyStartled = 1
  setStr(st, "MORE_CONSCIOUS")
end

EFFECTS[2] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.exploded = 1
  setStr(st, "NO_APPEAL")
end

EFFECTS[3] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.usedRepeatableMove = 1
  st.repeatedMove = 0
  st.moveRepeatCount = 0
end

EFFECTS[4] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.jamSafetyCount = 1
  setStr(st, "SETTLE_DOWN")
end

EFFECTS[5] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.immune = 1
  setStr(st, "OBLIVIOUS_TO_OTHERS")
end

EFFECTS[6] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.jamReduction = 20
  setStr(st, "LESS_AWARE")
end

EFFECTS[7] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.resistant = 1
  setStr(st, "STOPPED_CARING")
end

EFFECTS[8] = startleFront
EFFECTS[9] = startlePrevMons
EFFECTS[10] = startleFront
EFFECTS[11] = startlePrevMons

EFFECTS[12] = startleFront
EFFECTS[13] = startlePrevMons

EFFECTS[14] = function(c, game)
  local rval = rand(game) % 10
  local jam = 60
  if rval < 2 then jam = 20
  elseif rval < 8 then jam = 40 end
  c.appealResults.jam = jam
  startleFront(c)
end

EFFECTS[15] = function(c, game)
  local num = 0
  local contestant = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  if to[contestant] ~= 0 then
    for i = 0, 3 do
      if to[contestant] > to[i] then
        c.appealResults.jamQueue = { i, 255 }
        local rval = rand(game) % 10
        local jam = 60
        if rval == 0 then jam = 0
        elseif rval <= 2 then jam = 10
        elseif rval <= 4 then jam = 20
        elseif rval <= 6 then jam = 30
        elseif rval <= 8 then jam = 40 end
        c.appealResults.jam = jam
        if wasJammed(c) then num = num + 1 end
      end
    end
  end
  setStr(c.status[contestant], "ATTEMPT_STARTLE")
  if num == 0 then setStr2(c.status[contestant], "MESSED_UP2") end
end

EFFECTS[16] = function(c)
  local hit = false
  local contestant = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  if to[contestant] ~= 0 then
    for i = 0, 3 do
      if to[contestant] > to[i] and nz(c.status[i].hasJudgesAttention)
        and canUnnerve(c, i) then
        c.status[i].hasJudgesAttention = 0
        c.status[i].judgesAttentionWasRemoved = 1
        setStr(c.status[i], "JUDGE_LOOK_AWAY2")
        hit = true
      end
    end
  end
  setStr(c.status[contestant], "DAZZLE_ATTEMPT")
  if not hit then setStr2(c.status[contestant], "MESSED_UP2") end
end

EFFECTS[17] = function(c)
  local num = 0
  local contestant = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  if to[contestant] ~= 0 then
    for i = 0, 3 do
      if to[contestant] > to[i] then
        if nz(c.status[i].hasJudgesAttention) then
          c.appealResults.jam = 50
        else
          c.appealResults.jam = 10
        end
        c.appealResults.jamQueue = { i, 255 }
        if wasJammed(c) then num = num + 1 end
      end
    end
  end
  setStr(c.status[contestant], "ATTEMPT_STARTLE")
  if num == 0 then setStr2(c.status[contestant], "MESSED_UP2") end
end

EFFECTS[18] = function(c)
  c.status[c.appealResults.contestant].turnSkipped = 1
  startlePrevMons(c)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end

EFFECTS[19] = function(c)
  local move = c.status[c.appealResults.contestant].currMove
  jamByCategory(c, Contest3.moveRow(move).c)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end

EFFECTS[20] = function(c)
  jamByCategory(c, 0)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end
EFFECTS[21] = function(c)
  jamByCategory(c, 1)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end
EFFECTS[22] = function(c)
  jamByCategory(c, 2)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end
EFFECTS[23] = function(c)
  jamByCategory(c, 3)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end
EFFECTS[24] = function(c)
  jamByCategory(c, 4)
  setStr(c.status[c.appealResults.contestant], "ATTEMPT_STARTLE")
end

EFFECTS[25] = function(c)
  local hit = false
  local user = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  if to[user] ~= 3 then
    for i = 0, 3 do
      if to[user] + 1 == to[i] then
        if canUnnerve(c, i) then
          makeNervous(c, i)
          setStr(c.status[i], "NERVOUS")
        else
          setStr(c.status[i], "UNAFFECTED")
        end
        hit = true
      end
    end
  end
  setStr(c.status[user], "UNNERVE_ATTEMPT")
  if not hit then setStr2(c.status[user], "MESSED_UP2") end
end

EFFECTS[26] = function(c, game)
  local ids = { [0] = 255, 255, 255, 255, 255 }
  local numAfter = 0
  local user = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  for i = 0, 3 do
    if to[user] < to[i] and (c.status[i].nervous or 0) == 0
      and canUseTurn(c.status[i]) then
      ids[numAfter] = i
      numAfter = numAfter + 1
    end
  end
  local odds = { [0] = 0, 0, 0, 0 }
  if numAfter == 1 then odds[0] = 60
  elseif numAfter == 2 then odds[0], odds[1] = 30, 30
  elseif numAfter == 3 then odds[0], odds[1], odds[2] = 20, 20, 20 end
  local oddsMod = { [0] = 0, 0, 0, 0 }
  for i = 0, 3 do
    if nz(c.status[i].hasJudgesAttention) and allowedToCombo(c.status[i]) then
      local starter = Contest3.moveRow(c.status[i].prevMove).s or 0
      oddsMod[i] = (starter ~= 0 and 10 or 0)
    end
    oddsMod[i] = oddsMod[i] - math.floor((c.status[i].condition or 0) / 10) * 10
  end
  local numUnnerved = 0
  if odds[0] ~= 0 then
    local i = 0
    while ids[i] ~= 255 do
      local who = ids[i]
      local contestantUnnerved = false
      if (rand(game) % 100) < (odds[i] + oddsMod[who]) then
        if canUnnerve(c, who) then
          makeNervous(c, who)
          setStr(c.status[who], "NERVOUS")
          numUnnerved = numUnnerved + 1
        else
          contestantUnnerved = true
        end
      else
        contestantUnnerved = true
      end
      if contestantUnnerved then
        setStr(c.status[who], "UNAFFECTED")
        numUnnerved = numUnnerved + 1
      end
      c.appealResults.unnerved[who] = 1
      i = i + 1
    end
  end
  setStr(c.status[user], "UNNERVE_WAITING")
  if numUnnerved == 0 then setStr2(c.status[user], "MESSED_UP2") end
end

EFFECTS[27] = function(c)
  local num = 0
  local user = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  for i = 0, 3 do
    if to[user] > to[i] and (c.status[i].condition or 0) > 0 and canUnnerve(c, i) then
      c.status[i].condition = 0
      c.status[i].conditionMod = 2
      setStr(c.status[i], "REGAINED_FORM")
      num = num + 1
    end
  end
  setStr(c.status[user], "TAUNT_WELL")
  if num == 0 then setStr2(c.status[user], "IGNORED") end
end

EFFECTS[28] = function(c)
  local num = 0
  local user = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  for i = 0, 3 do
    if to[user] > to[i] then
      if (c.status[i].condition or 0) > 0 then
        c.appealResults.jam = 40
      else
        c.appealResults.jam = 10
      end
      c.appealResults.jamQueue = { i, 255 }
      if wasJammed(c) then num = num + 1 end
    end
  end
  setStr(c.status[user], "JAM_WELL")
  if num == 0 then setStr2(c.status[user], "IGNORED") end
end

EFFECTS[29] = function(c)
  local who = c.appealResults.contestant
  if c.turnOrder[who] == 0 then
    local move = c.status[who].currMove
    local row = Contest3.effectRow(Contest3.moveRow(move).e)
    c.status[who].appeal = (c.status[who].appeal or 0) + 2 * (row.a or 0)
    setStr(c.status[who], "HUSTLE_STANDOUT")
  end
end

EFFECTS[30] = function(c)
  local who = c.appealResults.contestant
  if c.turnOrder[who] == 3 then
    local move = c.status[who].currMove
    local row = Contest3.effectRow(Contest3.moveRow(move).e)
    c.status[who].appeal = (c.status[who].appeal or 0) + 2 * (row.a or 0)
    setStr(c.status[who], "WORK_HARD_UNNOTICED")
  end
end

EFFECTS[31] = function(c)
  local who = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  local sum = 0
  for i = 0, 3 do
    if to[who] > to[i] then sum = sum + (c.status[i].appeal or 0) end
  end
  if sum < 0 then sum = 0 end
  if to[who] == 0 or sum == 0 then
    setStr(c.status[who], "APPEAL_NOT_WELL")
  else
    c.status[who].appeal = (c.status[who].appeal or 0) + math.floor(sum / 2)
    setStr(c.status[who], "WORK_BEFORE")
  end
  c.status[who].appeal = Contest3.roundTowardsZero(c.status[who].appeal)
end

EFFECTS[32] = function(c)
  local who = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  local appeal = 0
  if to[who] ~= 0 then
    for i = 0, 3 do
      if to[who] - 1 == to[i] then appeal = c.status[i].appeal or 0 end
    end
  end
  if to[who] == 0 or appeal <= 0 then
    setStr(c.status[who], "APPEAL_NOT_WELL2")
  else
    c.status[who].appeal = (c.status[who].appeal or 0) + appeal
    setStr(c.status[who], "WORK_PRECEDING")
  end
end

EFFECTS[33] = function(c)
  local who = c.appealResults.contestant
  local which = c.appealResults.turnOrder[who]
  if which == 0 then
    c.status[who].appeal = 10
    setStr(c.status[who], "APPEAL_NOT_SHOWN_WELL")
  else
    c.status[who].appeal = 20 * which
    if which == 1 then setStr(c.status[who], "APPEAL_SLIGHTLY_WELL")
    elseif which == 2 then setStr(c.status[who], "APPEAL_PRETTY_WELL")
    else setStr(c.status[who], "APPEAL_EXCELLENTLY") end
  end
end

EFFECTS[34] = function(c, game)
  local who = c.appealResults.contestant
  local rval = rand(game) % 10
  local appeal, key
  if rval < 3 then appeal, key = 10, "APPEAL_NOT_VERY_WELL"
  elseif rval < 6 then appeal, key = 20, "APPEAL_SLIGHTLY_WELL2"
  elseif rval < 8 then appeal, key = 40, "APPEAL_PRETTY_WELL2"
  elseif rval < 9 then appeal, key = 60, "APPEAL_VERY_WELL"
  else appeal, key = 80, "APPEAL_EXCELLENTLY2" end
  c.status[who].appeal = appeal
  setStr(c.status[who], key)
end

EFFECTS[35] = function(c)
  local who = c.appealResults.contestant
  local turnOrder = c.appealResults.turnOrder[who]
  if turnOrder == 0 then return end
  local i = turnOrder - 1
  local j
  while true do
    j = 0
    while j < 4 do
      if c.appealResults.turnOrder[j] == i then break end
      j = j + 1
    end
    local st = c.status[j]
    if nz(st.noMoreTurns) or nz(st.nervous) or nz(st.numTurnsSkipped) then
      i = i - 1
      if i < 0 then return end
    else
      break
    end
  end
  local move = c.status[who].currMove
  if Contest3.moveRow(move).c == Contest3.moveRow(c.status[j].currMove).c then
    local row = Contest3.effectRow(Contest3.moveRow(move).e)
    c.status[who].appeal = (c.status[who].appeal or 0) + (row.a or 0) * 2
    setStr(c.status[who], "SAME_TYPE_GOOD")
  end
end

EFFECTS[36] = function(c)
  local who = c.appealResults.contestant
  if c.appealResults.turnOrder[who] ~= 0 then
    local move = c.status[who].currMove
    for i = 0, 3 do
      if c.appealResults.turnOrder[who] - 1 == c.appealResults.turnOrder[i]
        and Contest3.moveRow(move).c ~= Contest3.moveRow(c.status[i].currMove).c then
        local row = Contest3.effectRow(Contest3.moveRow(move).e)
        c.status[who].appeal = (c.status[who].appeal or 0) + (row.a or 0) * 2
        setStr(c.status[who], "DIFF_TYPE_GOOD")
        break
      end
    end
  end
end

EFFECTS[37] = function(c)
  local who = c.appealResults.contestant
  if c.appealResults.turnOrder[who] ~= 0 then
    for i = 0, 3 do
      if c.appealResults.turnOrder[who] - 1 == c.appealResults.turnOrder[i] then
        if (c.status[who].appeal or 0) > (c.status[i].appeal or 0) then
          c.status[who].appeal = (c.status[who].appeal or 0) * 2
          setStr(c.status[who], "STOOD_OUT_AS_MUCH")
        elseif (c.status[who].appeal or 0) < (c.status[i].appeal or 0) then
          c.status[who].appeal = 0
          setStr(c.status[who], "NOT_AS_WELL")
        end
      end
    end
  end
end

EFFECTS[38] = function(c)
  local st = c.status[c.appealResults.contestant]
  if (st.condition or 0) < 30 then
    st.condition = (st.condition or 0) + 10
    st.conditionMod = 1
    setStr(st, "CONDITION_ROSE")
  else
    setStr(st, "NO_CONDITION_IMPROVE")
  end
end

EFFECTS[39] = function(c)
  local st = c.status[c.appealResults.contestant]
  st.appealTripleCondition = 1
  if (st.condition or 0) ~= 0 then
    setStr(st, "HOT_STATUS")
  else
    setStr(st, "BAD_CONDITION_WEAK_APPEAL")
  end
end

EFFECTS[40] = function(c)
  if c.appealNumber == 4 then return end
  local who = c.appealResults.contestant
  local turnOrder = {}
  for i = 0, 3 do turnOrder[i] = c.status[i].nextTurnOrder end
  turnOrder[who] = 255
  for i = 0, 3 do
    local j = 0
    local hit = false
    while j < 4 do
      if j ~= who and i == turnOrder[j] and turnOrder[j] == c.status[j].nextTurnOrder then
        turnOrder[j] = turnOrder[j] + 1
        hit = true
        break
      end
      j = j + 1
    end
    if not hit then break end
  end
  turnOrder[who] = 0
  c.status[who].turnOrderMod = 1
  for i = 0, 3 do c.status[i].nextTurnOrder = turnOrder[i] end
  c.status[who].turnOrderModAction = 1
  setStr(c.status[who], "MOVE_UP_LINE")
end

EFFECTS[41] = function(c)
  if c.appealNumber == 4 then return end
  local who = c.appealResults.contestant
  local turnOrder = {}
  for i = 0, 3 do turnOrder[i] = c.status[i].nextTurnOrder end
  turnOrder[who] = 255
  for i = 3, 0, -1 do
    local j = 0
    local hit = false
    while j < 4 do
      if j ~= who and i == turnOrder[j] and turnOrder[j] == c.status[j].nextTurnOrder then
        turnOrder[j] = turnOrder[j] - 1
        hit = true
        break
      end
      j = j + 1
    end
    if not hit then break end
  end
  turnOrder[who] = 3
  c.status[who].turnOrderMod = 1
  for i = 0, 3 do c.status[i].nextTurnOrder = turnOrder[i] end
  c.status[who].turnOrderModAction = 2
  setStr(c.status[who], "MOVE_BACK_LINE")
end

EFFECTS[42] = function() end

EFFECTS[43] = function(c, game)
  if c.appealNumber == 4 then return end
  local who = c.appealResults.contestant
  local turnOrder = {}
  local unselected = {}
  for i = 0, 3 do
    turnOrder[i] = c.status[i].nextTurnOrder
    unselected[i] = i
  end
  for i = 0, 3 do
    local rval = rand(game) % (4 - i)
    for j = 0, 3 do
      if unselected[j] ~= 255 then
        if rval == 0 then
          turnOrder[j] = i
          unselected[j] = 255
          break
        else
          rval = rval - 1
        end
      end
    end
  end
  for i = 0, 3 do
    c.status[i].nextTurnOrder = turnOrder[i]
    c.status[i].turnOrderMod = 2
  end
  c.status[who].turnOrderModAction = 3
  setStr(c.status[who], "SCRAMBLE_ORDER")
end

EFFECTS[44] = function(c)
  local who = c.appealResults.contestant
  if Contest3.moveRow(c.status[who].currMove).c ~= c.category then
    c.status[who].overrideCategoryExcitementMod = 1
  end
end

EFFECTS[45] = function(c)
  local num = 0
  local who = c.appealResults.contestant
  local to = c.appealResults.turnOrder
  for i = 0, 3 do
    if to[who] > to[i] then
      if (c.status[i].appeal or 0) > 0 then
        c.appealResults.jam = Contest3.roundUp(math.floor((c.status[i].appeal or 0) / 2))
      else
        c.appealResults.jam = 10
      end
      c.appealResults.jamQueue = { i, 255 }
      if wasJammed(c) then num = num + 1 end
    end
  end
  if num == 0 then setStr2(c.status[who], "MESSED_UP2") end
  setStr(c.status[who], "ATTEMPT_STARTLE")
end

EFFECTS[46] = function(c)
  local who = c.appealResults.contestant
  local level = c.applauseLevel or 0
  local appeal, key
  if level == 0 then appeal, key = 10, "APPEAL_NOT_VERY_WELL"
  elseif level == 1 then appeal, key = 20, "APPEAL_SLIGHTLY_WELL2"
  elseif level == 2 then appeal, key = 30, "APPEAL_PRETTY_WELL2"
  elseif level == 3 then appeal, key = 50, "APPEAL_VERY_WELL"
  else appeal, key = 60, "APPEAL_EXCELLENTLY2" end
  c.status[who].appeal = appeal
  setStr(c.status[who], key)
end

EFFECTS[47] = function(c)
  if (c.excitement.frozen or 0) == 0 then
    c.excitement.frozen = 1
    c.excitement.freezer = c.appealResults.contestant
    setStr(c.status[c.appealResults.contestant], "ATTRACTED_ATTENTION")
  end
end

function Contest3.calculateAppealImpact(c, game, contestant)
  local st = c.status[contestant]
  st.appeal = 0
  st.baseAppeal = 0
  if not canUseTurn(st) then return end
  local move = st.currMove or 0
  local row = Contest3.moveRow(move)
  local effect = row.e or 0
  local erow = Contest3.effectRow(effect)
  st.moveCategory = row.c or 0
  if move == st.prevMove and move ~= 0 then
    st.repeatedMove = 1
    st.moveRepeatCount = (st.moveRepeatCount or 0) + 1
  else
    st.moveRepeatCount = 0
  end
  st.baseAppeal = erow.a or 0
  st.appeal = erow.a or 0
  c.appealResults.jam = erow.j or 0
  c.appealResults.jam2 = erow.j or 0
  c.appealResults.contestant = contestant
  for i = 0, 3 do
    c.status[i].jam = 0
    c.appealResults.unnerved[i] = 0
  end
  if nz(st.hasJudgesAttention) and Contest3.areMovesCombo(st.prevMove, st.currMove) == 0 then
    st.hasJudgesAttention = 0
  end
  local fn = EFFECTS[effect]
  if fn then fn(c, game) end
  if st.conditionMod == 1 then
    st.appeal = (st.appeal or 0) + (st.condition or 0) - 10
  elseif nz(st.appealTripleCondition) then
    st.appeal = (st.appeal or 0) + (st.condition or 0) * 3
  else
    st.appeal = (st.appeal or 0) + (st.condition or 0)
  end
  st.completedCombo = 0
  st.usedComboMove = 0
  if allowedToCombo(st) then
    local completed = Contest3.areMovesCombo(st.prevMove, st.currMove)
    if completed ~= 0 and nz(st.hasJudgesAttention) then
      st.completedCombo = completed
      st.usedComboMove = 1
      st.hasJudgesAttention = 0
      st.comboAppealBonus = (st.baseAppeal or 0) * st.completedCombo
      st.completedComboFlag = 1
    else
      if (row.s or 0) ~= 0 then
        st.hasJudgesAttention = 1
        st.usedComboMove = 1
      else
        st.hasJudgesAttention = 0
      end
    end
  end
  if nz(st.repeatedMove) then
    st.repeatJam = ((st.moveRepeatCount or 0) + 1) * 10
  else
    st.repeatJam = 0
  end
  if nz(st.nervous) then
    st.hasJudgesAttention = 0
    st.appeal = 0
    st.baseAppeal = 0
  end
  local exc = Contest3.getMoveExcitement(c.category, st.currMove)
  c.excitement.moveExcitement = exc
  if nz(st.overrideCategoryExcitementMod) then
    c.excitement.moveExcitement = 1
    exc = 1
  end
  if exc > 0 then
    if (c.applauseLevel or 0) + exc > 4 then
      c.excitement.bonus = 60
    else
      c.excitement.bonus = 10
    end
  else
    c.excitement.bonus = 0
  end
  local rnd = rand(game) % 3
  local target = contestant
  for i = 0, 3 do
    if i ~= contestant then
      if rnd == 0 then
        target = i
        break
      end
      rnd = rnd - 1
    end
  end
  st.contestantAnimTarget = target
end

function Contest3.applyAftermath(c, contestant)
  local st = c.status[contestant]
  local texts = {}
  if not canUseTurn(st) then
    texts[#texts + 1] = { who = contestant, key = "CANT_APPEAL_NEXT_TURN" }
    return texts
  end
  if nz(st.nervous) then
    texts[#texts + 1] = { who = contestant, key = "TOO_NERVOUS" }
    return texts
  end
  texts[#texts + 1] = { who = contestant, key = "APPEALED_WITH" }
  if st.effectStringId ~= Contest3.STRING_NONE then
    texts[#texts + 1] = { who = contestant, key = st.effectStringId }
  end
  if st.effectStringId2 ~= Contest3.STRING_NONE then
    texts[#texts + 1] = { who = contestant, key = st.effectStringId2 }
  end
  for i = 0, 3 do
    if i ~= contestant then
      local other = c.status[i]
      if other.effectStringId ~= Contest3.STRING_NONE
        and other.effectStringId ~= st.effectStringId then
        texts[#texts + 1] = { who = i, key = other.effectStringId }
      end
    end
  end
  if (st.hasJudgesAttention or 0) == 0 then
    st.appeal = (st.appeal or 0) + (st.comboAppealBonus or 0)
    if nz(st.completedCombo) then
      texts[#texts + 1] = { who = contestant, key = "WENT_OVER_WELL" }
    end
  end
  if nz(st.repeatedMove) then
    texts[#texts + 1] = { who = contestant, key = "DISAPPOINTED_REPEAT" }
    st.appeal = (st.appeal or 0) - (st.repeatJam or 0)
  end
  local frozen = nz(c.excitement.frozen) and contestant ~= (c.excitement.freezer or 0)
  if not frozen then
    local r4 = c.excitement.moveExcitement or 0
    if nz(st.overrideCategoryExcitementMod) then r4 = 1 end
    if r4 > 0 and nz(st.repeatedMove) then r4 = 0 end
    c.applauseLevel = (c.applauseLevel or 0) + r4
    if c.applauseLevel < 0 then c.applauseLevel = 0 end
    if r4 ~= 0 then
      if r4 < 0 then
        texts[#texts + 1] = { who = contestant, key = "DIDNT_GO_WELL" }
      elseif (c.applauseLevel or 0) <= 4 then
        texts[#texts + 1] = { who = contestant, key = "WENT_OVER_GREAT" }
      else
        texts[#texts + 1] = { who = contestant, key = "GOT_CROWD_GOING" }
      end
      if r4 > 0 then
        st.appeal = (st.appeal or 0) + (c.excitement.bonus or 0)
      end
    end
    if (c.applauseLevel or 0) > 4 then c.applauseLevel = 0 end
  end
  return texts
end

-- CONTEST_AI_COMMON scoring (dummy bits are no-ops in the ROM).
function Contest3.aiPickMove(c, game, who)
  local mon = c.mons[who]
  local moves = mon.moves or { 0, 0, 0, 0 }
  local st = c.status[who]
  local scores = { [0] = 100, 100, 100, 100 }
  local turn = c.turnOrder[who] or 0
  for slot = 0, 3 do
    local move = moves[slot + 1] or 0
    if move == 0 then
      scores[slot] = 0
    else
      local row = Contest3.moveRow(move)
      local erow = Contest3.effectRow(row.e)
      if Contest3.areMovesCombo(st.prevMove, move) ~= 0 and nz(st.hasJudgesAttention) then
        scores[slot] = scores[slot] + 80
      elseif (row.s or 0) ~= 0 then
        scores[slot] = scores[slot] + 15
      end
      if move == st.prevMove and (row.e or 0) ~= Contest3.EFF_REPETITION_NOT_BORING then
        scores[slot] = scores[slot] - ((st.moveRepeatCount or 0) + 1) * 20
      end
      local exc = Contest3.getMoveExcitement(c.category, move)
      if exc > 0 then scores[slot] = scores[slot] + 20
      elseif exc < 0 then scores[slot] = scores[slot] - 15 end
      scores[slot] = scores[slot] + math.floor((erow.a or 0) / 5)
      if turn > 0 and (erow.j or 0) > 0 then
        scores[slot] = scores[slot] + 10
      end
      if (row.e or 0) == Contest3.EFF_BETTER_IF_FIRST and turn == 0 then
        scores[slot] = scores[slot] + 25
      end
      if (row.e or 0) == Contest3.EFF_BETTER_IF_LAST and turn == 3 then
        scores[slot] = scores[slot] + 25
      end
      scores[slot] = scores[slot] + (rand(game) % 21) - 10
    end
  end
  while true do
    local rval = rand(game) % 4
    local r2 = scores[rval]
    local i = 0
    while i < 4 do
      if r2 < scores[i] then break end
      i = i + 1
    end
    if i == 4 then return rval end
  end
end

function Contest3.chooseMoves(c, game, playerSlot)
  playerSlot = playerSlot or 0
  for i = 0, 3 do
    local st = c.status[i]
    if not canUseTurn(st) then
      st.currMove = 0
    elseif i == c.playerIndex then
      local moves = c.mons[i].moves or {}
      st.currMove = moves[playerSlot + 1] or 0
    else
      local choice = Contest3.aiPickMove(c, game, i)
      st.currMove = (c.mons[i].moves or {})[choice + 1] or 0
    end
  end
end

function Contest3.runRound(c, game, playerSlot)
  Contest3.chooseMoves(c, game, playerSlot)
  local texts = {}
  for turn = 0, 3 do
    local who = 0
    while who < 4 and c.appealResults.turnOrder[who] ~= turn do
      who = who + 1
    end
    if who > 3 then who = 0 end
    Contest3.calculateAppealImpact(c, game, who)
    local chunk = Contest3.applyAftermath(c, who)
    for i = 1, #chunk do
      chunk[i].text = Contest3.formatString(c, game, chunk[i])
      texts[#texts + 1] = chunk[i]
    end
  end
  Contest3.rankContestants(c, game)
  Contest3.setStatusesForNextRound(c)
  c.appealNumber = (c.appealNumber or 0) + 1
  c.texts = texts
  c.textAt = 1
  if c.appealNumber >= Contest3.TURNS then
    Contest3.calculateFinalScores(c, game)
  end
  return texts
end

local function didPlaceHigher(a, b, stand)
  if stand[a].total < stand[b].total then return true end
  if stand[a].total > stand[b].total then return false end
  if stand[a].round1 < stand[b].round1 then return true end
  if stand[a].round1 > stand[b].round1 then return false end
  if stand[a].random < stand[b].random then return true end
  return false
end

function Contest3.determineFinalStandings(c, game)
  local randomOrdering = uniqueRands(game)
  local stand = {}
  for i = 0, 3 do
    stand[i] = {
      total = c.totalPoints[i] or 0,
      round1 = c.round1[i] or 0,
      random = randomOrdering[i],
      contestant = i,
    }
  end
  for i = 0, 2 do
    for j = 3, i + 1, -1 do
      if didPlaceHigher(j - 1, j, stand) then
        local tmp = stand[j - 1]
        stand[j - 1] = stand[j]
        stand[j] = tmp
      end
    end
  end
  local final = {}
  for i = 0, 3 do
    final[stand[i].contestant] = i
  end
  c.finalStandings = final
  return final
end

function Contest3.calculateFinalScores(c, game)
  for i = 0, 3 do
    c.appealPointTotals[i] = c.status[i].pointTotal or 0
    c.round2[i] = (c.appealPointTotals[i] or 0) * 2
    c.totalPoints[i] = (c.round1[i] or 0) + (c.round2[i] or 0)
  end
  Contest3.determineFinalStandings(c, game)
  c.done = true
end

function Contest3.formatString(c, game, entry)
  local key = entry.key
  local who = entry.who or 0
  local tpl = DATA.strings[key] or key
  local mon = c.mons[who]
  local st = c.status[who]
  local moveId = st.currMove
  if (moveId or 0) == 0 then moveId = st.prevMove or 0 end
  local moveName = game:moveName(moveId)
  local catNames = { [0] = "COOLNESS", "BEAUTY", "CUTENESS", "SMARTNESS", "TOUGHNESS" }
  local cat = catNames[Contest3.moveRow(moveId).c or 0] or "COOLNESS"
  local nick = (mon and mon.nickname) or "POKeMON"
  local out = tpl
  out = out:gsub("%$1", nick)
  out = out:gsub("%$2", moveName)
  out = out:gsub("%$3", cat)
  return out
end

function Contest3.pickOpponents(game, category, rank)
  local pool = {}
  for i = 1, #DATA.opponents do
    local o = DATA.opponents[i]
    if o.rank == rank then
      local bit = (o.pool or {})[category + 1] or 0
      if bit ~= 0 then pool[#pool + 1] = o end
    end
  end
  local chosen = {}
  local count = #pool
  for n = 1, 3 do
    if count < 1 then break end
    local rnd = (rand(game) % count) + 1
    local src = pool[rnd]
    chosen[n] = {
      species = src.species,
      nickname = src.nick,
      trainerName = src.trainer,
      trainerGfxId = src.gfx,
      cool = src.cool, beauty = src.beauty, cute = src.cute,
      smart = src.smart, tough = src.tough, sheen = src.sheen,
      moves = { src.moves[1], src.moves[2], src.moves[3], src.moves[4] },
    }
    for j = rnd, count - 1 do pool[j] = pool[j + 1] end
    pool[count] = nil
    count = count - 1
  end
  while #chosen < 3 and chosen[1] do
    local src = chosen[1]
    chosen[#chosen + 1] = {
      species = src.species, nickname = src.nickname,
      trainerName = src.trainerName, trainerGfxId = src.trainerGfxId,
      cool = src.cool, beauty = src.beauty, cute = src.cute,
      smart = src.smart, tough = src.tough, sheen = src.sheen,
      moves = { src.moves[1], src.moves[2], src.moves[3], src.moves[4] },
    }
  end
  return chosen
end

function Contest3.createPlayerMon(game, partyIndex)
  local mon = game.party and game.party[partyIndex]
  if not mon then return nil end
  local cool = tonumber(mon.cool) or 0
  local beauty = tonumber(mon.beauty) or 0
  local cute = tonumber(mon.cute) or 0
  local smart = tonumber(mon.smart) or 0
  local tough = tonumber(mon.tough) or 0
  local item = tonumber(mon.item) or 0
  if item == Contest3.ITEM_RED_SCARF then cool = cool + 20
  elseif item == Contest3.ITEM_BLUE_SCARF then beauty = beauty + 20
  elseif item == Contest3.ITEM_PINK_SCARF then cute = cute + 20
  elseif item == Contest3.ITEM_GREEN_SCARF then smart = smart + 20
  elseif item == Contest3.ITEM_YELLOW_SCARF then tough = tough + 20 end
  if cool > 255 then cool = 255 end
  if beauty > 255 then beauty = 255 end
  if cute > 255 then cute = 255 end
  if smart > 255 then smart = 255 end
  if tough > 255 then tough = 255 end
  local moves = { 0, 0, 0, 0 }
  for i = 1, 4 do
    local m = mon.moves and mon.moves[i]
    moves[i] = (m and (m.id or m)) or 0
  end
  local gfx = 216
  if (game.gender or 0) == 1 then gfx = 217 end
  return {
    species = mon.species or 0,
    nickname = mon.name or "POKeMON",
    trainerName = game:playerName(),
    trainerGfxId = gfx,
    cool = cool, beauty = beauty, cute = cute,
    smart = smart, tough = tough,
    sheen = tonumber(mon.sheen) or 0,
    moves = moves,
    personality = mon.pid or 0,
    otId = mon.otId or 0,
  }
end

function Contest3.prepareMons(game, partyIndex, category, rank)
  category = category or 0
  rank = rank or 0
  local npcs = Contest3.pickOpponents(game, category, rank)
  local player = Contest3.createPlayerMon(game, partyIndex)
  if not player then return nil end
  return {
    [0] = npcs[1],
    [1] = npcs[2],
    [2] = npcs[3],
    [3] = player,
  }, category, rank
end

function Contest3.makeEngine(game, mons, partyIndex, category, rank)
  if not (mons and mons[3]) then return nil end
  category = category or 0
  rank = rank or 0
  local status = {}
  for i = 0, 3 do status[i] = newStatus() end
  local c = {
    monIndex = partyIndex,
    category = category,
    rank = rank,
    playerIndex = Contest3.PLAYER_INDEX,
    mons = mons,
    status = status,
    turnOrder = { [0] = 0, 1, 2, 3 },
    round1 = {},
    round2 = {},
    totalPoints = {},
    appealPointTotals = {},
    finalStandings = {},
    applauseLevel = 0,
    appealNumber = 0,
    excitement = { frozen = 0, freezer = 0, moveExcitement = 0, bonus = 0 },
    appealResults = {
      turnOrder = { [0] = 0, 1, 2, 3 },
      jam = 0, jam2 = 0, jamQueue = { 255 },
      unnerved = { [0] = 0, 0, 0, 0 },
      contestant = 0,
    },
    moveHistory = {},
    texts = {},
    textAt = 1,
    done = false,
    phase = "select",
  }
  for i = 0, 3 do
    c.round1[i] = Contest3.round1Points(mons[i] or {}, category)
  end
  Contest3.sortContestants(c, game, 0)
  for i = 0, 3 do
    status[i].nextTurnOrder = Contest3.NEXT_FREE
  end
  Contest3.applyNextTurnOrder(c)
  return c
end

function Contest3.start(game, partyIndex, category, rank)
  local mons = Contest3.prepareMons(game, partyIndex, category, rank)
  if not mons then return nil end
  return Contest3.makeEngine(game, mons, partyIndex, category, rank)
end

function Contest3.hearts(points)
  points = tonumber(points) or 0
  if points < 0 then points = 0 end
  return math.floor(points / 10)
end

function Contest3.currentText(c, game)
  local entry = c.texts and c.texts[c.textAt]
  if not entry then return nil end
  if entry.text then return entry.text end
  return Contest3.formatString(c, game, entry)
end

function Contest3.advanceText(c)
  c.textAt = (c.textAt or 1) + 1
  if not (c.texts and c.texts[c.textAt]) then
    c.texts = {}
    c.textAt = 1
    if c.done then
      c.phase = "done"
    else
      c.phase = "select"
    end
    return false
  end
  return true
end

return Contest3
