# -*- coding: utf-8 -*-
"""Patch Game3.lua for Battle Tower lobby specials + link assessment tweaks."""
from pathlib import Path

path = Path(r"C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev\src\core\Game3.lua")
text = path.read_text(encoding="utf-8")
orig = text

# ---------------------------------------------------------------------------
# 1) Constants near existing Tower specials
# ---------------------------------------------------------------------------
old_const = """Game3.BATTLE_TOWER_IDLE = 5
Game3.E_READER_TRAINER_INVALID = 1"""
new_const = """Game3.BATTLE_TOWER_IDLE = 5
Game3.BATTLE_TOWER_EREADER_TRAINER_ID = 200
Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID = 100
Game3.BATTLE_TOWER_OBJ_GFX_BOY_1 = 7
Game3.E_READER_TRAINER_INVALID = 1
-- Cable Club connect RESULT codes (cable_club.c). 5 = receptionist goodbye
-- when no GBA partner / link hardware is available.
Game3.CABLE_CLUB_RESULT_LINKED = 0
Game3.CABLE_CLUB_RESULT_NO_LINK = 5
Game3.CABLE_CLUB_NO_LINK_MSG =
  \"No link partner found.\\nCable Club battles need two GBAs.\\n(Not available in this port.)\""""
if old_const not in text:
    raise SystemExit("const block missing")
text = text.replace(old_const, new_const, 1)

# Align CABLE_CLUB_NO_LINK with named constant if still numeric 5 earlier
text = text.replace(
    "Game3.CABLE_CLUB_NO_LINK = 5",
    "Game3.CABLE_CLUB_NO_LINK = Game3.CABLE_CLUB_RESULT_NO_LINK",
    1,
)

# ---------------------------------------------------------------------------
# 2) Replace cableClubNoLink with clearer RESULT + optional field note
# ---------------------------------------------------------------------------
old_cable = """function Game3:cableClubNoLink()
  self:setScriptVar(Gen3Script.VAR_RESULT, Game3.CABLE_CLUB_NO_LINK)
  return Game3.CABLE_CLUB_NO_LINK
end"""
new_cable = """function Game3:cableClubNoLink()
  -- sub_80833EC / friends: no GBA SIO partner. RESULT 5 takes the
  -- receptionist goodbye branch (Colosseum / Trade Center / Record Mix).
  -- Full GBA multiplayer is out of scope; never beginScriptWait here.
  self.isLinkContest = false
  self:setScriptVar(Gen3Script.VAR_RESULT, Game3.CABLE_CLUB_NO_LINK)
  return Game3.CABLE_CLUB_NO_LINK
end

-- Optional explanatory banner when a PC-side link menu is opened without
-- a partner. Scripts that already print goodbye text do not call this.
function Game3:cableClubNoLinkExplain()
  self:cableClubNoLink()
  if self.sayScript then
    self:sayScript(Game3.CABLE_CLUB_NO_LINK_MSG)
  end
  return Game3.CABLE_CLUB_NO_LINK
end"""
if old_cable not in text:
    raise SystemExit("cableClubNoLink missing")
text = text.replace(old_cable, new_cable, 1)

# ---------------------------------------------------------------------------
# 3) Replace tower core: init / ensure / util / setProperty through ribbons
#    Keep prize/ribbon bodies intact; expand surrounding helpers.
# ---------------------------------------------------------------------------
marker_start = "-- battle_tower.c sub_8134548. ON_FRAME VAR_TEMP_0==0. Default"
marker_end = "function Game3:getSecretBaseNearbyMapName()"
i0 = text.find(marker_start)
i1 = text.find(marker_end)
if i0 < 0 or i1 < 0 or i1 <= i0:
    raise SystemExit("tower block markers missing %s %s" % (i0, i1))

# Extract existing prize/ribbon functions to preserve them
chunk = text[i0:i1]
# Keep Determine/Give/Award as-is from chunk
import re
prize_fn = re.search(
    r"(-- battle_tower\.c sShortStreakPrizes.*?function Game3:awardBattleTowerRibbons\(\).*?return awarded\nend\n)",
    chunk, re.S)
if not prize_fn:
    raise SystemExit("could not capture prize/ribbon block")
prize_block = prize_fn.group(1)

new_tower = r'''-- battle_tower.c sub_8134548. ON_FRAME VAR_TEMP_0==0 walks var_4AE for
-- both level modes and sets VAR_TEMP_0 so lobby scripts resume the right
-- branch (award / continue / lose / idle). Do not beginScriptWait.
function Game3:initBattleTowerOnFrame()
  local t = self:ensureBattleTower()
  local var1 = 0
  for levelType = 0, 1 do
    local state = (t.var4AE and t.var4AE[levelType]) or 0
    if state == 0 then
      self:resetBattleTowerStreak(levelType)
      if var1 == 0 then
        self:setScriptVar(Game3.VAR_TEMP_0, Game3.BATTLE_TOWER_IDLE)
      end
    elseif state == 1 then
      self:resetBattleTowerStreak(levelType)
      self:setScriptVar(Game3.VAR_TEMP_0, 1)
      var1 = var1 + 1
    elseif state == 4 then
      self:setScriptVar(Game3.VAR_TEMP_0, 2)
      var1 = var1 + 1
    elseif state == 5 then
      self:setScriptVar(Game3.VAR_TEMP_0, 3)
      var1 = var1 + 1
    elseif state == 2 then
      self:setScriptVar(Game3.VAR_TEMP_0, 4)
      var1 = var1 + 1
    elseif state == 3 or state == 6 then
      -- keep prior VAR_TEMP_0
    else
      self:resetBattleTowerStreak(levelType)
      if var1 == 0 then
        self:setScriptVar(Game3.VAR_TEMP_0, Game3.BATTLE_TOWER_IDLE)
      end
    end
  end
  local a = (t.var4AE and t.var4AE[0]) or 0
  local b = (t.var4AE and t.var4AE[1]) or 0
  if (a == 3 or a == 6) and (b == 3 or b == 6) then
    self:setScriptVar(Game3.VAR_TEMP_0, Game3.BATTLE_TOWER_IDLE)
  end
  return 0
end

function Game3:battleTowerData()
  if not Game3._battleTowerData then
    Game3._battleTowerData = require("src.data.battle_tower")
  end
  return Game3._battleTowerData
end

function Game3:ensureBattleTower()
  local t = self.battleTower
  if type(t) ~= "table" then
    t = {
      levelType = 0,
      var4AE = { [0] = 0, [1] = 0 },
      curChallengeBattleNum = { [0] = 1, [1] = 1 },
      curStreakChallengesNum = { [0] = 1, [1] = 1 },
      trainerId = 0,
      unk554 = 0,
      selectedPartyMons = { 0, 0, 0 },
      currentWinStreaks = { [0] = 0, [1] = 0 },
      recordWinStreaks = { [0] = 0, [1] = 0 },
      battledTrainerIds = { 0, 0, 0, 0, 0, 0, 0 },
      bestStreak = 0,
      prizeItem = 0,
      battleOutcome = 0,
      totalWins = 0,
      lastStreakLevelType = 0,
      records = {},
      playerRecord = nil,
    }
    self.battleTower = t
  end
  t.var4AE = t.var4AE or { [0] = 0, [1] = 0 }
  t.curChallengeBattleNum = t.curChallengeBattleNum or { [0] = 1, [1] = 1 }
  t.curStreakChallengesNum = t.curStreakChallengesNum or { [0] = 1, [1] = 1 }
  t.currentWinStreaks = t.currentWinStreaks or { [0] = 0, [1] = 0 }
  t.recordWinStreaks = t.recordWinStreaks or { [0] = 0, [1] = 0 }
  t.battledTrainerIds = t.battledTrainerIds or { 0, 0, 0, 0, 0, 0, 0 }
  t.selectedPartyMons = t.selectedPartyMons or { 0, 0, 0 }
  t.records = t.records or {}
  return t
end

-- battle_tower.c ResetBattleTowerStreak.
function Game3:resetBattleTowerStreak(levelType)
  local t = self:ensureBattleTower()
  levelType = tonumber(levelType)
  if levelType == nil then levelType = t.levelType or 0 end
  t.var4AE = t.var4AE or {}
  t.curChallengeBattleNum = t.curChallengeBattleNum or {}
  t.curStreakChallengesNum = t.curStreakChallengesNum or {}
  t.var4AE[levelType] = 0
  t.curChallengeBattleNum[levelType] = 1
  t.curStreakChallengesNum[levelType] = 1
end

-- 0x8004 selects the field. Case 0 is var_4AE[levelType]; 0 is a
-- valid idle streak. Must return. Do not beginScriptWait.
function Game3:battleTowerUtil()
  local t = self:ensureBattleTower()
  local which = self:varGet(0x8004)
  local level = t.levelType or 0
  local n = 0
  if which == 0 then
    n = (t.var4AE and t.var4AE[level]) or 0
  elseif which == 1 then
    n = level
  elseif which == 2 then
    n = (t.curChallengeBattleNum and t.curChallengeBattleNum[level]) or 0
  elseif which == 3 then
    n = (t.curStreakChallengesNum and t.curStreakChallengesNum[level]) or 0
  elseif which == 4 then
    n = t.trainerId or 0
  elseif which == 8 then
    n = t.unk554 or 0
  elseif which == 9 then
    n = self:getCurrentBattleTowerWinStreak(level)
  elseif which == 10 then
    self.gameStats = self.gameStats or {}
    self.gameStats[Game3.GAME_STAT_BATTLE_TOWER_BEST_STREAK] = t.bestStreak or 0
  elseif which == 11 then
    self:resetBattleTowerStreak(level)
  elseif which == 12 then
    if t.savedVar4AE ~= nil then
      t.var4AE = t.var4AE or {}
      t.var4AE[level] = t.savedVar4AE
    end
  elseif which == 13 then
    t.currentWinStreaks = t.currentWinStreaks or {}
    t.currentWinStreaks[level] = self:getCurrentBattleTowerWinStreak(level)
  elseif which == 14 then
    t.lastStreakLevelType = level
  end
  self:setScriptVar(Gen3Script.VAR_RESULT, n)
  return n
end

function Game3:saveCurrentBattleTowerWinStreak()
  local t = self:ensureBattleTower()
  local level = t.levelType or 0
  local streak = self:getCurrentBattleTowerWinStreak(level)
  t.recordWinStreaks = t.recordWinStreaks or { [0] = 0, [1] = 0 }
  if (t.recordWinStreaks[level] or 0) < streak then
    t.recordWinStreaks[level] = streak
  end
  local best = t.recordWinStreaks[0] or 0
  if (t.recordWinStreaks[1] or 0) > best then best = t.recordWinStreaks[1] end
  if best > 9999 then best = 9999 end
  t.bestStreak = best
  self.gameStats = self.gameStats or {}
  self.gameStats[Game3.GAME_STAT_BATTLE_TOWER_BEST_STREAK] = best
end

function Game3:setBattleTowerProperty()
  local t = self:ensureBattleTower()
  local which = self:varGet(0x8004)
  local val = self:varGet(0x8005)
  local level = t.levelType or 0
  if which == 0 then
    -- ROM also snapshots prior state into gBattleStruct->unk160FB.
    t.savedVar4AE = (t.var4AE and t.var4AE[level]) or 0
    t.var4AE = t.var4AE or {}
    t.var4AE[level] = val
  elseif which == 1 then
    t.levelType = val
  elseif which == 2 then
    t.curChallengeBattleNum = t.curChallengeBattleNum or {}
    t.curChallengeBattleNum[level] = val
  elseif which == 3 then
    t.curStreakChallengesNum = t.curStreakChallengesNum or {}
    t.curStreakChallengesNum[level] = val
  elseif which == 4 then
    t.trainerId = val
  elseif which == 5 then
    local order = self.selectedOrderFromParty or t.selectedPartyMons or { 0, 0, 0 }
    t.selectedPartyMons = {
      tonumber(order[1]) or 0,
      tonumber(order[2]) or 0,
      tonumber(order[3]) or 0,
    }
  elseif which == 6 then
    -- Win one battle in the current 7-set: bump battle num + streak.
    if (t.trainerId or 0) == Game3.BATTLE_TOWER_EREADER_TRAINER_ID then
      -- ClearEReaderTrainer: leave empty ereader slot.
      t.ereaderTrainer = nil
    end
    t.totalWins = (t.totalWins or 0) + 1
    if t.totalWins > 9999 then t.totalWins = 9999 end
    t.curChallengeBattleNum = t.curChallengeBattleNum or {}
    local nextBattle = ((t.curChallengeBattleNum[level] or 1) + 1)
    t.curChallengeBattleNum[level] = nextBattle
    self:saveCurrentBattleTowerWinStreak()
    self:setScriptVar(Gen3Script.VAR_RESULT, nextBattle)
    self:setStringVar(1, tostring(nextBattle))
  elseif which == 7 then
    t.curStreakChallengesNum = t.curStreakChallengesNum or {}
    local sets = t.curStreakChallengesNum[level] or 1
    if sets < 1430 then sets = sets + 1 end
    t.curStreakChallengesNum[level] = sets
    self:saveCurrentBattleTowerWinStreak()
    self:setScriptVar(Gen3Script.VAR_RESULT, sets)
  elseif which == 8 then
    t.unk554 = val
  elseif which == 10 then
    self.gameStats = self.gameStats or {}
    self.gameStats[Game3.GAME_STAT_BATTLE_TOWER_BEST_STREAK] = t.bestStreak or 0
  elseif which == 11 then
    if (t.var4AE and t.var4AE[level]) ~= 3 then
      self:resetBattleTowerStreak(level)
    end
  elseif which == 12 then
    if t.savedVar4AE ~= nil then
      t.var4AE = t.var4AE or {}
      t.var4AE[level] = t.savedVar4AE
    end
  elseif which == 13 then
    t.currentWinStreaks = t.currentWinStreaks or {}
    t.currentWinStreaks[level] = self:getCurrentBattleTowerWinStreak(level)
  elseif which == 14 then
    t.lastStreakLevelType = level
  end
end

'''

# Re-append existing banlist/party/validate/streak/prize/ribbon from original chunk
# Extract from marker_start chunk the parts we still need:
banlist_start = chunk.find("-- CheckMonBattleTowerBanlist")
prize_start = chunk.find("-- battle_tower.c sShortStreakPrizes")
if banlist_start < 0 or prize_start < 0:
    raise SystemExit("banlist/prize anchors missing in chunk")

# Keep banlist through getBestBattleTowerStreak (before prizes)
mid = chunk[banlist_start:prize_start]

new_block = new_tower + mid + prize_block + "\n" + '''
function Game3:chooseNextBattleTowerTrainer()
  local t = self:ensureBattleTower()
  local level = t.levelType or 0
  local data = self:battleTowerData()
  if self:chooseSpecialBattleTowerTrainer() then
    self:setBattleTowerTrainerGfxId(t.trainerId or 0)
    local battleNum = (t.curChallengeBattleNum and t.curChallengeBattleNum[level]) or 1
    if battleNum >= 1 and battleNum <= 7 then
      t.battledTrainerIds = t.battledTrainerIds or {}
      t.battledTrainerIds[battleNum] = t.trainerId or 0
    end
    return t.trainerId
  end

  local sets = (t.curStreakChallengesNum and t.curStreakChallengesNum[level]) or 1
  local battleNum = (t.curChallengeBattleNum and t.curChallengeBattleNum[level]) or 1
  local trainerId = 0
  local function alreadyBattled(id)
    local n = battleNum - 1
    for i = 1, n do
      if (t.battledTrainerIds and t.battledTrainerIds[i]) == id then return true end
    end
    return false
  end

  if sets <= 7 then
    if battleNum == 7 then
      while true do
        trainerId = math.floor(((self:gbaRandom() % 256) * 5) / 128)
        trainerId = trainerId + (sets - 1) * 10 + 20
        if not alreadyBattled(trainerId) then break end
      end
    else
      while true do
        trainerId = math.floor(((self:gbaRandom() % 256) * 5) / 64)
        trainerId = trainerId + (sets - 1) * 10
        if not alreadyBattled(trainerId) then break end
      end
    end
  else
    while true do
      trainerId = math.floor(((self:gbaRandom() % 256) * 30) / 256) + 70
      if not alreadyBattled(trainerId) then break end
    end
  end

  t.trainerId = trainerId
  self:setBattleTowerTrainerGfxId(trainerId)
  if battleNum < 7 then
    t.battledTrainerIds = t.battledTrainerIds or {}
    t.battledTrainerIds[battleNum] = trainerId
  end
  return trainerId
end

-- Record-mix / e-reader opponents. Without mixed records or an e-reader
-- card this always returns false and the roster path above runs.
function Game3:chooseSpecialBattleTowerTrainer()
  local t = self:ensureBattleTower()
  local level = t.levelType or 0
  local streak = self:getCurrentBattleTowerWinStreak(level)
  -- E-reader: only when a valid card matching streak/level is present.
  if t.ereaderTrainer and type(t.ereaderTrainer) == "table" then
    -- validateEReaderTrainer already returns invalid by default.
  end
  local candidates = {}
  local records = t.records or {}
  for i = 1, 5 do
    local rec = records[i]
    if type(rec) == "table"
        and (tonumber(rec.winStreak) or 0) == streak
        and (tonumber(rec.battleTowerLevelType) or 0) == level
        and rec.hasData then
      candidates[#candidates + 1] = (i - 1) + Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID
    end
  end
  if #candidates == 0 then return false end
  local pick = candidates[(self:gbaRandom() % #candidates) + 1]
  t.trainerId = pick
  return true
end

function Game3:setBattleTowerTrainerGfxId(trainerIndex)
  trainerIndex = tonumber(trainerIndex) or 0
  local data = self:battleTowerData()
  local trainerClass = nil
  if trainerIndex < Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID then
    local row = data.trainers and data.trainers[trainerIndex]
    trainerClass = row and row.trainerClass
  elseif trainerIndex < Game3.BATTLE_TOWER_EREADER_TRAINER_ID then
    local rec = self:ensureBattleTower().records
      and self:ensureBattleTower().records[
        trainerIndex - Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID + 1]
    trainerClass = rec and rec.trainerClass
  else
    local er = self:ensureBattleTower().ereaderTrainer
    trainerClass = er and er.trainerClass
  end
  local gfx = Game3.BATTLE_TOWER_OBJ_GFX_BOY_1
  if trainerClass ~= nil then
    local males = data.maleClasses or {}
    local maleGfx = data.maleGfx or {}
    for i = 1, #males do
      if males[i] == trainerClass then
        gfx = maleGfx[i] or gfx
        self:setScriptVar(Game3.VAR_OBJ_GFX_ID_0, gfx)
        return gfx
      end
    end
    local females = data.femaleClasses or {}
    local femaleGfx = data.femaleGfx or {}
    for i = 1, #females do
      if females[i] == trainerClass then
        gfx = femaleGfx[i] or gfx
        self:setScriptVar(Game3.VAR_OBJ_GFX_ID_0, gfx)
        return gfx
      end
    end
  end
  self:setScriptVar(Game3.VAR_OBJ_GFX_ID_0, gfx)
  return gfx
end

function Game3:setEReaderTrainerGfxId()
  return self:setBattleTowerTrainerGfxId(Game3.BATTLE_TOWER_EREADER_TRAINER_ID)
end

function Game3:battleTowerTrainerRow(trainerId)
  trainerId = tonumber(trainerId)
  if trainerId == nil then
    trainerId = self:ensureBattleTower().trainerId or 0
  end
  local data = self:battleTowerData()
  if trainerId < Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID then
    return data.trainers and data.trainers[trainerId]
  end
  return nil
end

function Game3:battleTowerTrainerName(trainerId)
  local t = self:ensureBattleTower()
  trainerId = tonumber(trainerId) or (t.trainerId or 0)
  if trainerId == Game3.BATTLE_TOWER_EREADER_TRAINER_ID then
    local er = t.ereaderTrainer
    return (er and er.name) or "E-READER"
  end
  if trainerId >= Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID then
    local rec = t.records
      and t.records[trainerId - Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID + 1]
    return (rec and rec.name) or "TRAINER"
  end
  local row = self:battleTowerTrainerRow(trainerId)
  return (row and row.name) or "TRAINER"
end

function Game3:battleTowerTrainerClassName(trainerId)
  local row = self:battleTowerTrainerRow(trainerId)
  if row and row.className then return row.className end
  return "TRAINER"
end

-- Easy-Chat greetings are not decoded here; scripts still msgbox
-- string var 4 via ShowFieldMessageStringVar4.
function Game3:printBattleTowerTrainerGreeting()
  local name = self:battleTowerTrainerName()
  local className = self:battleTowerTrainerClassName()
  local text = ("%s %s wants to battle!"):format(className, name)
  self:setStringVar(4, text)
  return text
end

function Game3:printEReaderTrainerGreeting()
  self:setStringVar(4, "The E-READER TRAINER wants to battle!")
end

function Game3:bufferEReaderTrainerName()
  local er = self:ensureBattleTower().ereaderTrainer
  self:setStringVar(1, (er and er.name) or "E-READER")
end

-- CreateMonWithEVSpread: fixed IV on every stat, 510 EVs split across
-- the set bits of evSpread.
function Game3:makeBattleTowerMon(entry, level, fixedIV)
  if type(entry) ~= "table" then return nil end
  local moves = entry.moves or {}
  local mon = self:makeMon(entry.species, level, moves, { trainer = true })
  if not mon then return nil end
  fixedIV = tonumber(fixedIV) or 0
  if fixedIV < 0 then fixedIV = 0 end
  if fixedIV > 31 then fixedIV = 31 end
  mon.ivs = {
    hp = fixedIV, atk = fixedIV, def = fixedIV,
    spe = fixedIV, spa = fixedIV, spd = fixedIV,
  }
  local spread = tonumber(entry.evSpread) or 0
  local bits = {}
  for i = 0, 5 do
    if (spread % 2) == 1 then bits[#bits + 1] = i end
    spread = math.floor(spread / 2)
  end
  local evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  local keys = { "hp", "atk", "def", "spe", "spa", "spd" }
  if #bits > 0 then
    local amount = math.floor(510 / #bits)
    for i = 1, #bits do
      evs[keys[bits[i] + 1]] = amount
    end
  end
  mon.evs = evs
  local data = self:battleTowerData()
  local heldIdx = tonumber(entry.heldItem) or 0
  mon.item = (data.heldItems and data.heldItems[heldIdx + 1]) or 0
  -- Frustration cares about low friendship.
  local friendship = 255
  for i = 1, 4 do
    if (moves[i] or 0) == 218 then friendship = 0 end -- MOVE_FRUSTRATION
  end
  mon.friendship = friendship
  self:recalcStats(mon)
  mon.hp = mon.maxHp
  -- Anti-shiny OT like makeTrainerMon.
  local pid = mon.pid or 0
  local ot
  for _ = 1, 64 do
    local lo = self:rand(65536) - 1
    local hi = self:rand(65536) - 1
    if lo < 0 then lo = 0 end
    if hi < 0 then hi = 0 end
    ot = hi * 65536 + lo
    if not Game3.isShinyOtIdPersonality(ot, pid) then break end
  end
  mon.otId = ot
  mon.otName = "TRAINER"
  return mon
end

function Game3:fillBattleTowerTrainerParty()
  local t = self:ensureBattleTower()
  local trainerId = t.trainerId or 0
  local data = self:battleTowerData()
  local party = {}

  if trainerId == Game3.BATTLE_TOWER_EREADER_TRAINER_ID then
    -- No e-reader card loaded in this port.
    return party
  end
  if trainerId >= Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID then
    local rec = t.records
      and t.records[trainerId - Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID + 1]
    if rec and type(rec.party) == "table" then
      for i = 1, 3 do
        local slot = rec.party[i]
        if slot then party[#party + 1] = slot end
      end
    end
    return party
  end

  local fixedIV, offset, poolSize = 6, 0, 60
  if trainerId < 20 then
    fixedIV, offset, poolSize = 6, 0, 60
  elseif trainerId < 30 then
    fixedIV, offset, poolSize = 9, 30, 60
  elseif trainerId < 40 then
    fixedIV, offset, poolSize = 12, 60, 60
  elseif trainerId < 50 then
    fixedIV, offset, poolSize = 15, 90, 60
  elseif trainerId < 60 then
    fixedIV, offset, poolSize = 18, 120, 60
  elseif trainerId < 70 then
    fixedIV, offset, poolSize = 21, 150, 60
  elseif trainerId < 80 then
    fixedIV, offset, poolSize = 31, 180, 60
  else
    fixedIV, offset, poolSize = 31, 200, 100
  end

  local level = ((t.levelType or 0) ~= 0) and 100 or 50
  local pool = ((t.levelType or 0) ~= 0) and data.level100Mons or data.level50Mons
  local row = data.trainers and data.trainers[trainerId]
  local teamFlags = (row and row.teamFlags) or 0
  local chosen = {}
  local slots = {}
  local guard = 0
  while #slots < 3 and guard < 10000 do
    guard = guard + 1
    local idx = math.floor(((self:gbaRandom() % 256) * poolSize) / 256) + offset
    local entry = pool and pool[idx]
    if entry and (teamFlags == 0 or ((entry.teamFlags or 0) % 256) and
        (((entry.teamFlags or 0) % 256) & teamFlags) == teamFlags) then
      -- bitand: Lua 5.1 may lack &; emulate
    end
    if entry then
      local okFlags = true
      if teamFlags ~= 0 then
        local tf = entry.teamFlags or 0
        okFlags = (math.floor(tf / 1) % 256)
        -- proper bit and:
        okFlags = (tf % (teamFlags * 2) ) -- placeholder replaced below
      end
    end
  end
  -- Bitwise AND helper for LuaJIT / 5.1
  local function band(a, b)
    local res, bit = 0, 1
    a = math.floor(tonumber(a) or 0)
    b = math.floor(tonumber(b) or 0)
    while a > 0 and b > 0 do
      if (a % 2 == 1) and (b % 2 == 1) then res = res + bit end
      a = math.floor(a / 2)
      b = math.floor(b / 2)
      bit = bit * 2
    end
    return res
  end

  guard = 0
  while #slots < 3 and guard < 10000 do
    guard = guard + 1
    local idx = math.floor(((self:gbaRandom() % 256) * poolSize) / 256) + offset
    local entry = pool and pool[idx]
    if not entry then goto continue end
    if teamFlags ~= 0 and band(entry.teamFlags or 0, teamFlags) ~= teamFlags then
      goto continue
    end
    local dupSpecies, dupItem, dupIdx = false, false, false
    for i = 1, #slots do
      local prev = pool[slots[i]]
      if prev and prev.species == entry.species then dupSpecies = true end
      local held = (data.heldItems and data.heldItems[(entry.heldItem or 0) + 1]) or 0
      local prevHeld = (data.heldItems and data.heldItems[(prev.heldItem or 0) + 1]) or 0
      if held ~= 0 and held == prevHeld then dupItem = true end
      if slots[i] == idx then dupIdx = true end
    end
    if dupSpecies or dupItem or dupIdx then goto continue end
    slots[#slots + 1] = idx
    ::continue::
  end

  for i = 1, #slots do
    local mon = self:makeBattleTowerMon(pool[slots[i]], level, fixedIV)
    if mon then party[#party + 1] = mon end
  end
  return party
end

function Game3:startSpecialBattle()
  local mode = self:varGet(0x8004)
  if mode == 0 then
    -- Battle Tower.
    local party = self:fillBattleTowerTrainerParty()
    if #party < 1 then
      -- Soft-fail: do not wait forever if roster fill failed.
      self:setScriptVar(Gen3Script.VAR_RESULT, 0)
      return false
    end
    local npc = {
      trainerId = 0,
      trainerName = self:battleTowerTrainerName(),
      trainerClass = self:battleTowerTrainerClassName(),
      party = party,
      battleTower = true,
      doubleBattle = false,
    }
    self:beginScriptWait()
    self.battleOutcome = 0
    if not self:startTrainerBattle(npc) then
      self:endScriptWait()
      return false
    end
    if self.battle then
      self.battle.battleTower = true
      self.battle.isTrainer = true
      -- Tower battles: no RUN (handled like trainers already).
    end
    return true
  elseif mode == 1 then
    -- Secret-base battle path: already covered by other specials.
    return false
  elseif mode == 2 then
    -- E-reader trainer battle: no card.
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    return false
  end
  return false
end

-- battle_tower.c SaveBattleTowerProgress. Persists streak state; ROM also
-- soft-resets after some modes. We write the save and arm unk554 without
-- forcing a reboot unless the script then calls BattleTower_SoftReset.
function Game3:saveBattleTowerProgress()
  local t = self:ensureBattleTower()
  local level = t.levelType or 0
  local mode = self:varGet(0x8004)
  if mode == 3 or mode == 0 then
    local sets = (t.curStreakChallengesNum and t.curStreakChallengesNum[level]) or 1
    local battle = (t.curChallengeBattleNum and t.curChallengeBattleNum[level]) or 1
    if sets > 1 or battle > 1 then
      self:snapshotBattleTowerPlayerRecord()
    end
  end
  self:recordBattleTowerDefeatMeta()
  t.battleOutcome = tonumber(self.battleOutcome) or 0
  if mode ~= 3 then
    t.var4AE = t.var4AE or {}
    t.var4AE[level] = mode
  end
  self:setScriptVar(Game3.VAR_TEMP_0, 0)
  t.unk554 = 1
  self:writeSave()
  return true
end

function Game3:snapshotBattleTowerPlayerRecord()
  local t = self:ensureBattleTower()
  local level = t.levelType or 0
  local record = {
    battleTowerLevelType = level,
    trainerClass = 0,
    name = self:playerName(),
    winStreak = self:getCurrentBattleTowerWinStreak(level),
    hasData = true,
    greeting = {},
    party = {},
  }
  t.playerRecord = record
  self:saveCurrentBattleTowerWinStreak()
end

function Game3:recordBattleTowerDefeatMeta()
  local t = self:ensureBattleTower()
  t.defeatedByTrainerName = self:battleTowerTrainerName()
  local b = self.battle
  if b and b.enemy then
    t.defeatedBySpecies = b.enemy.species or 0
    t.firstMonSpecies = (b.player and b.player.species) or 0
    t.firstMonNickname = (b.player and (b.player.name or b.player.nickname)) or ""
  end
end

-- field_specials.c TryInitBattleTowerAwardManObjectEvent ->
-- TryInitLocalObjectEvent(6). Without local-object templates this is a
-- no-op so lobby scripts never hang.
function Game3:tryInitBattleTowerAwardManObjectEvent()
  return 0
end

-- Enables Bravo Trainer Battle Tower TV show when a streak is mid-run.
-- TV pipeline is best-effort; never wait.
function Game3:tryEnableBravoTrainerBattleTower()
  local t = self:ensureBattleTower()
  for level = 0, 1 do
    if ((t.var4AE and t.var4AE[level]) or 0) == 1 then
      -- sub_80BFD20: mark a pending Bravo Trainer episode if TV helpers exist.
      if self.queueBravoTrainerBattleTowerShow then
        self:queueBravoTrainerBattleTowerShow()
      end
    end
  end
  return 0
end

'''

text = text[:i0] + new_block + text[i1:]

# Fix fillBattleTowerTrainerParty: the first draft had a broken band/goto
# placeholder. The second loop with band() is the real one, but leftover
# broken first while may remain. Clean it by rewriting fill function only.
# Find and replace the broken fill function with a clean version.
fill_start = text.find("function Game3:fillBattleTowerTrainerParty()")
fill_end = text.find("function Game3:startSpecialBattle()")
if fill_start < 0 or fill_end < 0:
    raise SystemExit("fill/start markers missing after insert")

clean_fill = r'''function Game3:fillBattleTowerTrainerParty()
  local t = self:ensureBattleTower()
  local trainerId = t.trainerId or 0
  local data = self:battleTowerData()
  local party = {}

  local function band(a, b)
    local res, bitval = 0, 1
    a = math.floor(tonumber(a) or 0)
    b = math.floor(tonumber(b) or 0)
    while a > 0 and b > 0 do
      if (a % 2 == 1) and (b % 2 == 1) then res = res + bitval end
      a = math.floor(a / 2)
      b = math.floor(b / 2)
      bitval = bitval * 2
    end
    return res
  end

  if trainerId == Game3.BATTLE_TOWER_EREADER_TRAINER_ID then
    return party
  end
  if trainerId >= Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID then
    local rec = t.records
      and t.records[trainerId - Game3.BATTLE_TOWER_RECORD_MIXING_BASE_ID + 1]
    if rec and type(rec.party) == "table" then
      for i = 1, 3 do
        if rec.party[i] then party[#party + 1] = rec.party[i] end
      end
    end
    return party
  end

  local fixedIV, offset, poolSize = 6, 0, 60
  if trainerId >= 80 then
    fixedIV, offset, poolSize = 31, 200, 100
  elseif trainerId >= 70 then
    fixedIV, offset, poolSize = 31, 180, 60
  elseif trainerId >= 60 then
    fixedIV, offset, poolSize = 21, 150, 60
  elseif trainerId >= 50 then
    fixedIV, offset, poolSize = 18, 120, 60
  elseif trainerId >= 40 then
    fixedIV, offset, poolSize = 15, 90, 60
  elseif trainerId >= 30 then
    fixedIV, offset, poolSize = 12, 60, 60
  elseif trainerId >= 20 then
    fixedIV, offset, poolSize = 9, 30, 60
  end

  local level = ((t.levelType or 0) ~= 0) and 100 or 50
  local pool = ((t.levelType or 0) ~= 0) and data.level100Mons or data.level50Mons
  local row = data.trainers and data.trainers[trainerId]
  local teamFlags = (row and row.teamFlags) or 0
  local slots = {}
  local guard = 0
  while #slots < 3 and guard < 10000 do
    guard = guard + 1
    local idx = math.floor(((self:gbaRandom() % 256) * poolSize) / 256) + offset
    local entry = pool and pool[idx]
    if entry then
      local ok = true
      if teamFlags ~= 0 and band(entry.teamFlags or 0, teamFlags) ~= teamFlags then
        ok = false
      end
      if ok then
        for i = 1, #slots do
          local prev = pool[slots[i]]
          if prev and prev.species == entry.species then ok = false end
          if ok then
            local held = (data.heldItems and data.heldItems[(entry.heldItem or 0) + 1]) or 0
            local prevHeld = (data.heldItems and data.heldItems[(prev.heldItem or 0) + 1]) or 0
            if held ~= 0 and held == prevHeld then ok = false end
          end
          if ok and slots[i] == idx then ok = false end
          if not ok then break end
        end
      end
      if ok then slots[#slots + 1] = idx end
    end
  end

  for i = 1, #slots do
    local mon = self:makeBattleTowerMon(pool[slots[i]], level, fixedIV)
    if mon then
      party[#party + 1] = {
        species = mon.species,
        level = mon.level,
        moves = {},
        iv = math.floor((fixedIV * 255) / 31),
        _towerMon = mon,
      }
      -- Prefer raw mon objects for startTrainerBattle via makeTrainerMon bypass.
    end
  end
  -- Prefer returning prep-ready mons directly for startTrainerBattle.
  local live = {}
  for i = 1, #slots do
    local mon = self:makeBattleTowerMon(pool[slots[i]], level, fixedIV)
    if mon then live[#live + 1] = mon end
  end
  return live
end

'''
text = text[:fill_start] + clean_fill + text[fill_end:]

# Fix startSpecialBattle to use live mons with a custom path that doesn't
# call makeTrainerMon again (which would re-roll IVs). startTrainerBattle
# always calls makeTrainerMon on party slots. So pass slots that makeTrainerMon
# understands OR bypass by patching party after.
# Better: store species/level/moves/iv and also apply held item after.
# makeTrainerMon uses slot.iv (0-255 scale). Our makeBattleTowerMon already
# built full mons — change startSpecialBattle to inject them after start.

# Actually startTrainerBattle does:
#   enemy = self:prepBattler(self:makeTrainerMon(party[1]))
# So we need party entries as slots OR we need a different start path.
# Simplest fix: put tower mons as slot tables with species/level/moves/iv
# and set item after makeTrainerMon in a custom start.

start_fn = r'''function Game3:startSpecialBattle()
  local mode = self:varGet(0x8004)
  if mode == 0 then
    local built = self:fillBattleTowerTrainerParty()
    if #built < 1 then
      self:setScriptVar(Gen3Script.VAR_RESULT, 0)
      return false
    end
    -- Convert live mons into trainer party slots makeTrainerMon understands,
    -- then re-apply tower IVs / EVs / item / friendship after creation.
    local party = {}
    for i = 1, #built do
      local mon = built[i]
      local moveIds = {}
      for m = 1, 4 do
        local mv = mon.moves and mon.moves[m]
        moveIds[m] = (type(mv) == "table" and mv.id) or (tonumber(mv) or 0)
      end
      party[i] = {
        species = mon.species,
        level = mon.level,
        moves = moveIds,
        iv = 255, -- overwritten from tower mon below
        _tower = mon,
      }
    end
    local npc = {
      trainerId = 0,
      trainerName = self:battleTowerTrainerName(),
      trainerClass = self:battleTowerTrainerClassName(),
      party = party,
      battleTower = true,
      doubleBattle = false,
    }
    self:beginScriptWait()
    self.battleOutcome = 0
    -- Build battlers from tower mons directly to keep IVs/EVs/items.
    local player = self:firstHealthy()
    if not player then
      self:endScriptWait()
      return false
    end
    local enemy = self:prepBattler(built[1])
    if not enemy then
      self:endScriptWait()
      return false
    end
    self:prepBattler(player)
    self:markSeen(enemy.species)
    self:clearPoisonStepCounter()
    self.walkAgo = 0
    self.field = nil
    self.battle = {
      kind = "intro",
      cursor = 0,
      fightCursor = 0,
      partyCursor = 0,
      isTrainer = true,
      battleTower = true,
      doubles = nil,
      chooser = "player",
      npc = npc,
      trainerParty = built,
      trainerIndex = 1,
      player = player,
      enemy = enemy,
      text = ("%s would like to battle!"):format(self:trainerLabel(npc)),
      enterBoth = true,
      switchInDone = false,
      turns = 0,
      introT = 0,
      animT = 0,
      trainerItems = { 0, 0, 0, 0 },
      numItems = 0,
    }
    self:playBattleMusic("trainer")
    self:resetBattleResults()
    self:applyOverworldBattleWeather()
    self:markSentIn(player)
    self:launchBattleWithEntrance({ mode = "trainer", npc = npc })
    return true
  elseif mode == 2 then
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    return false
  end
  return false
end

'''
start_start = text.find("function Game3:startSpecialBattle()")
start_end = text.find("function Game3:saveBattleTowerProgress()")
if start_start < 0 or start_end < 0:
    raise SystemExit("start/save markers missing")
text = text[:start_start] + start_fn + text[start_end:]

# ---------------------------------------------------------------------------
# 4) Dispatch: replace stub group with real handlers
# ---------------------------------------------------------------------------
old_dispatch = """  elseif id == Game3.SPECIAL_CHOOSE_NEXT_BATTLE_TOWER_TRAINER
      or id == Game3.SPECIAL_PRINT_BATTLE_TOWER_TRAINER_GREETING
      or id == Game3.SPECIAL_PRINT_E_READER_TRAINER_GREETING
      or id == Game3.SPECIAL_START_SPECIAL_BATTLE
      or id == Game3.SPECIAL_SAVE_BATTLE_TOWER_PROGRESS
      or id == Game3.SPECIAL_BUFFER_E_READER_TRAINER_NAME
      or id == Game3.SPECIAL_SET_E_READER_TRAINER_GFX_ID
      or id == Game3.SPECIAL_TRY_INIT_BATTLE_TOWER_AWARD_MAN_OBJECT_EVENT
      or id == Game3.SPECIAL_TRY_ENABLE_BRAVO_TRAINER_BATTLE_TOWER then
    -- Tower / e-reader cinema and waitstate battles. Do not wait.
  elseif id == Game3.SPECIAL_INIT_BIRCH_STATE then"""

new_dispatch = """  elseif id == Game3.SPECIAL_CHOOSE_NEXT_BATTLE_TOWER_TRAINER then
    return self:chooseNextBattleTowerTrainer()
  elseif id == Game3.SPECIAL_PRINT_BATTLE_TOWER_TRAINER_GREETING then
    self:printBattleTowerTrainerGreeting()
  elseif id == Game3.SPECIAL_PRINT_E_READER_TRAINER_GREETING then
    self:printEReaderTrainerGreeting()
  elseif id == Game3.SPECIAL_START_SPECIAL_BATTLE then
    return self:startSpecialBattle()
  elseif id == Game3.SPECIAL_SAVE_BATTLE_TOWER_PROGRESS then
    return self:saveBattleTowerProgress()
  elseif id == Game3.SPECIAL_BUFFER_E_READER_TRAINER_NAME then
    self:bufferEReaderTrainerName()
  elseif id == Game3.SPECIAL_SET_E_READER_TRAINER_GFX_ID then
    self:setEReaderTrainerGfxId()
  elseif id == Game3.SPECIAL_TRY_INIT_BATTLE_TOWER_AWARD_MAN_OBJECT_EVENT then
    return self:tryInitBattleTowerAwardManObjectEvent()
  elseif id == Game3.SPECIAL_TRY_ENABLE_BRAVO_TRAINER_BATTLE_TOWER then
    return self:tryEnableBravoTrainerBattleTower()
  elseif id == Game3.SPECIAL_INIT_BIRCH_STATE then"""

if old_dispatch not in text:
    raise SystemExit("dispatch stub missing")
text = text.replace(old_dispatch, new_dispatch, 1)

# ---------------------------------------------------------------------------
# 5) Persist battleTower + linkBattleRecords in snapshot/apply
# ---------------------------------------------------------------------------
old_snap = """    tvShows = self:snapshotTvShows(),
  }
end"""
new_snap = """    tvShows = self:snapshotTvShows(),
    battleTower = self.battleTower,
    linkBattleRecords = self.linkBattleRecords,
  }
end"""
if old_snap not in text:
    raise SystemExit("snapshot tvShows tail missing")
text = text.replace(old_snap, new_snap, 1)

old_apply = """  self:applyTvShows(data.tvShows)
  if type(data.gameStats) == "table" then
    self.gameStats = data.gameStats
  else
    self.gameStats = nil
  end"""
new_apply = """  self:applyTvShows(data.tvShows)
  if type(data.gameStats) == "table" then
    self.gameStats = data.gameStats
  else
    self.gameStats = nil
  end
  if type(data.battleTower) == "table" then
    self.battleTower = data.battleTower
  end
  if type(data.linkBattleRecords) == "table" then
    self.linkBattleRecords = data.linkBattleRecords
  end"""
if old_apply not in text:
    raise SystemExit("applySave tvShows block missing")
text = text.replace(old_apply, new_apply, 1)

# Ensure CABLE_CLUB_NO_LINK still resolves after reorder (constant may now
# reference RESULT_NO_LINK defined later). Fix ordering if needed.
# We set CABLE_CLUB_NO_LINK = Game3.CABLE_CLUB_RESULT_NO_LINK before RESULT
# was defined. Move RESULT defs before CABLE_CLUB_NO_LINK usage.
# Check order:
idx_no = text.find("Game3.CABLE_CLUB_NO_LINK = Game3.CABLE_CLUB_RESULT_NO_LINK")
idx_res = text.find("Game3.CABLE_CLUB_RESULT_NO_LINK = 5")
if idx_no >= 0 and (idx_res < 0 or idx_res > idx_no):
    # revert to numeric for the early constant
    text = text.replace(
        "Game3.CABLE_CLUB_NO_LINK = Game3.CABLE_CLUB_RESULT_NO_LINK",
        "Game3.CABLE_CLUB_NO_LINK = 5",
        1,
    )

path.write_text(text, encoding="utf-8")
print("patched", path)
print("delta bytes", len(text) - len(orig))

# quick syntax-ish checks
for needle in [
    "function Game3:chooseNextBattleTowerTrainer",
    "function Game3:saveBattleTowerProgress",
    "function Game3:startSpecialBattle",
    "function Game3:fillBattleTowerTrainerParty",
    "SPECIAL_CHOOSE_NEXT_BATTLE_TOWER_TRAINER then",
    "battleTower = self.battleTower",
]:
    print(needle, "OK" if needle in text else "MISSING")
