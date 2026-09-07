from pathlib import Path
p = Path(r"C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev\src\core\Game3.lua")
text = p.read_text(encoding="utf-8")
old = """    if not mon then
      local nextIdx = (b.trainerIndex or 1) + 1
      if nextIdx > #party then return end
      b.trainerIndex = nextIdx
      mon = self:prepBattler(self:makeTrainerMon(party[nextIdx]))
    end"""
new = """    if not mon then
      local nextIdx = (b.trainerIndex or 1) + 1
      if nextIdx > #party then return end
      b.trainerIndex = nextIdx
      local slot = party[nextIdx]
      -- Battle Tower parties are pre-built mons (have maxHp); ordinary
      -- trainers store species/level/moves slots for makeTrainerMon.
      if type(slot) == \"table\" and slot.maxHp ~= nil then
        mon = self:prepBattler(slot)
      else
        mon = self:prepBattler(self:makeTrainerMon(slot))
      end
    end"""
if old not in text:
    raise SystemExit("fillTrainerSlots snippet missing")
p.write_text(text.replace(old, new, 1), encoding="utf-8")
print("patched fillTrainerSlots")
