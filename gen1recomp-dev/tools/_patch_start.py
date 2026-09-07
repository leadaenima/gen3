from pathlib import Path
p = Path(r"C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev\src\core\Game3.lua")
text = p.read_text(encoding="utf-8")
start = text.find("function Game3:startSpecialBattle()")
end = text.find("function Game3:saveBattleTowerProgress()")
old = text[start:end]
new = '''function Game3:startSpecialBattle()
  local mode = self:varGet(0x8004)
  if mode == 0 then
    local built = self:fillBattleTowerTrainerParty()
    if #built < 1 then
      self:setScriptVar(Gen3Script.VAR_RESULT, 0)
      return false
    end
    local npc = {
      trainerId = 0,
      trainerName = self:battleTowerTrainerName(),
      trainerClass = self:battleTowerTrainerClassName(),
      party = built,
      battleTower = true,
      doubleBattle = false,
    }
    self:beginScriptWait()
    self.battleOutcome = 0
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
    self.walkCountdown = 0
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
    -- E-reader trainer battle: no card in this port.
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    return false
  end
  return false
end

'''
if not old.startswith("function Game3:startSpecialBattle"):
    raise SystemExit("startSpecialBattle missing")
p.write_text(text[:start] + new + text[end:], encoding="utf-8")
print("cleaned startSpecialBattle")
