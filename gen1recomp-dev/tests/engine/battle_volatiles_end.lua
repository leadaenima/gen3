-- Volatile status must not survive a battle.
--
-- pokemon.h: the saved party entry (struct Pokemon) carries only `status`.
-- STATUS2_CONFUSION lives in `status2` on struct BattlePokemon, which is
-- EWRAM and is discarded when the battle tears down. In this port the party
-- tables ARE the battle mons, so confuseTurns rode into the next encounter
-- and Game3BattleFx drew the confusion orbit over the trainer during the
-- intro, before the ball was even thrown.
--
--   luajit tests/engine/battle_volatiles_end.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("battle volatiles end")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")

local function mon(name, hp)
  return {
    name = name, species = 280, level = 10,
    hp = hp or 20, maxHp = 20,
    moves = { { id = 1, pp = 10, maxPp = 10 } },
    stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  }
end

-- ---------------------------------------------------------------- the report

local g = Game3.new()
local lead, benched = mon("LEAD"), mon("BENCHED")
local foe = mon("FOE")
g.party = { lead, benched }
g.battle = { player = lead, enemy = foe, isTrainer = false }

lead.confuseTurns = 3
benched.confuseTurns = 2          -- switched out while still confused
lead.status = "psn"               -- status1: persistent, must survive
lead.sleepTurns = nil
lead.stages.atk = 2
lead.substitute = true
lead.wrapped = true

g:endBattle()

eq(lead.confuseTurns, nil, "the active mon leaves the battle unconfused")
eq(benched.confuseTurns, nil, "and so does one that was switched out confused")
eq(lead.substitute, nil, "the substitute is gone")
eq(lead.wrapped, nil, "and so is being wrapped")
eq(lead.stages.atk, 0, "stat stages reset")
eq(lead.status, "psn", "but status1 persists -- POISON is in the save block")

-- ------------------------------------------------- the site actually seen

-- Not just the field: drive Game3BattleFx the way the intro does, since the
-- orbit is chosen by statusKey(mon) reading confuseTurns back off the party.
local g2 = Game3.new()
local hero = mon("HERO")
g2.party = { hero }
hero.confuseTurns = 3
g2.battle = { player = hero, enemy = mon("SPINDA"), isTrainer = false }
g2:stepBattleFx(1 / 60)
eq(g2.battle._battleFx.status.player.key, "confuse",
  "while confused in battle the orbit is armed")

g2:endBattle()
g2.battle = { player = hero, enemy = mon("SPINDA2"), isTrainer = false }
g2:stepBattleFx(1 / 60)
eq(g2.battle._battleFx.status.player.key, nil,
  "the NEXT battle's intro arms no confusion orbit")

-- ------------------------------------------------------- enemy side + switch

local g3 = Game3.new()
local mine, theirs = mon("MINE"), mon("THEIRS")
g3.party = { mine }
theirs.confuseTurns = 4
g3.battle = { player = mine, enemy = theirs, isTrainer = true,
              trainerParty = { theirs } }
g3:endBattle()
eq(theirs.confuseTurns, nil, "the trainer's party is cleared too")

-- The extracted helper is what switchTo now uses; prove that wiring still
-- clears, so the two lists cannot drift apart again.
local g4 = Game3.new()
local outgo, income = mon("OUT"), mon("IN")
g4.party = { outgo, income }
g4.battle = { player = outgo, enemy = mon("FOE2"), isTrainer = false }
income.confuseTurns = 5
income.rampage = true
check(g4:switchTo(2), "switch to the benched mon")
eq(income.confuseTurns, nil, "switching in still clears confusion")
eq(income.rampage, nil, "and the rest of status2")

eq(#Game3.BATTLE_VOLATILE_KEYS, 60, "the shared volatile list is intact")

S.finish()
