-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local MonOps = {}

function MonOps.create(data, species, level)
  return Pokemon.new(data, species, level)
end

function MonOps.recalc(data, mon)
  local def = data.pokemon[mon.species]
  assert(def, "unknown species")
  if Stats.isGen3(def) then
    local ivs = mon.ivs or {}
    local evs = mon.evs or {}
    mon.stats = Stats.calcGen3(def, mon.level, {
      hp = ivs.hp or 0,
      attack = ivs.attack or ivs.atk or 0,
      defense = ivs.defense or ivs.def or 0,
      speed = ivs.speed or ivs.spe or 0,
      spatk = ivs.spatk or ivs.spa or 0,
      spdef = ivs.spdef or ivs.spd or 0,
    }, {
      hp = evs.hp or mon.hpEv or 0,
      attack = evs.attack or evs.atk or mon.atkEv or 0,
      defense = evs.defense or evs.def or mon.defEv or 0,
      speed = evs.speed or evs.spe or mon.speEv or 0,
      spatk = evs.spatk or evs.spa or mon.spaEv or 0,
      spdef = evs.spdef or evs.spd or mon.spdEv or 0,
    }, mon.nature)
  else
    mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
  end
  mon.hp = math.max(0, math.min(mon.hp or mon.stats.hp, mon.stats.hp))
end

function MonOps.setLevel(data, mon, level)
  level = math.max(1, math.min(100, math.floor(level)))
  local def = data.pokemon[mon.species]
  mon.level = level
  mon.exp = Growth.expForLevel(def.growthRate, level)
  MonOps.recalc(data, mon)
end

function MonOps.setMove(data, mon, slot, moveId)
  assert(slot >= 1 and slot <= 4)
  local mdef = data.moves[moveId]
  assert(mdef, "unknown move")
  mon.moves = mon.moves or {}
  mon.moves[slot] = {
    id = moveId,
    pp = mdef.pp + ((mon.moves[slot] and mon.moves[slot].ppUps) or 0) * math.floor(mdef.pp / 5),
    ppUps = mon.moves[slot] and mon.moves[slot].ppUps or nil,
  }
end

local IV_TO_GBA = {
  attack = "atk", defense = "def", speed = "spe",
  spatk = "spa", spdef = "spd",
}
local GBA_TO_IV = {
  atk = "attack", def = "defense", spe = "speed",
  spa = "spatk", spd = "spdef",
}

function MonOps.setIv(data, mon, key, value)
  mon.ivs = mon.ivs or {}
  local v = math.max(0, math.min(31, math.floor(value)))
  local editor = GBA_TO_IV[key] or key
  local gba = IV_TO_GBA[editor] or key
  mon.ivs[editor] = v
  if gba then mon.ivs[gba] = v end
  if editor == "hp" then mon.ivs.hp = v end
  MonOps.recalc(data, mon)
end

-- HP DV is derived from the low bits of the other four (Stats.randomDVs).
function MonOps.syncHpDv(dvs)
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
         + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

function MonOps.setDv(data, mon, key, value)
  mon.dvs[key] = math.max(0, math.min(15, math.floor(value)))
  if key ~= "hp" then
    MonOps.syncHpDv(mon.dvs)
  end
  MonOps.recalc(data, mon)
end

-- Keep level; resync exp to the species growth curve (species changes).
function MonOps.setSpecies(data, mon, species)
  assert(data.pokemon[species], "unknown species")
  mon.species = species
  MonOps.setLevel(data, mon, mon.level)
end

return MonOps
