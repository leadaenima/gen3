-- HM Anywhere v1.2.6 (Ported for Gen2Recomp)
--
-- Owning an HM item in your Bag allows field usage, provided a party member can learn it.

local PATCH_KEY = "__hm_anywhere_gen2_dispatch_v1"

local HM_BADGES = {
  CUT        = "HIVEBADGE",
  FLY        = "STORMBADGE",
  SURF       = "FOGBADGE",
  STRENGTH   = "PLAINBADGE",
  FLASH      = "ZEPHYRBADGE",
  WHIRLPOOL  = "GLACIERBADGE",
  WATERFALL  = "RISINGBADGE",
  ROCK_SMASH = "ZEPHYRBADGE",
}

local FIELD_HMS = {
  CUT        = true,
  FLY        = true,
  SURF       = true,
  STRENGTH   = true,
  FLASH      = true,
  WHIRLPOOL  = true,
  WATERFALL  = true,
  ROCK_SMASH = true,
}

local HM_TO_MACHINE = {
  CUT        = { "HM01" },
  FLY        = { "HM02" },
  SURF       = { "HM03" },
  STRENGTH   = { "HM04" },
  FLASH      = { "HM05" },
  WHIRLPOOL  = { "HM06" },
  WATERFALL  = { "HM07" },
  ROCK_SMASH = { "TM08" },
}

local HM_ORDER = { "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "WHIRLPOOL", "WATERFALL", "ROCK_SMASH" }

local HM_LABEL = {
  CUT        = "CUT",
  FLY        = "FLY",
  SURF       = "SURF",
  STRENGTH   = "STR",
  FLASH      = "FLSH",
  WHIRLPOOL  = "WHRL",
  WATERFALL  = "WTFL",
  ROCK_SMASH = "ROCK",
}

-- Comprehensive Gen II Learner Fallback Maps (Supports both IDs and Names)
local HARDCODED_HM_LEARNERS = {
  CUT = {
    1, "BULBASAUR", 2, "IVYSAUR", 3, "VENUSAUR", 4, "CHARMANDER", 5, "CHARMELEON", 6, "CHARIZARD",
    15, "BEEDRILL", 20, "RATICATE", 27, "SANDSHREW", 28, "SANDSLASH", 30, "NIDORINA", 31, "NIDOQUEEN",
    33, "NIDORINO", 34, "NIDOKING", 43, "ODDISH", 44, "GLOOM", 45, "VILEPLUME", 46, "PARAS",
    47, "PARASECT", 50, "DIGLETT", 51, "DUGTRIO", 69, "BELLSPROUT", 70, "WEEPINBELL", 71, "VICTREEBEL",
    72, "TENTACOOL", 73, "TENTACRUEL", 83, "FARFETCHD", 98, "KRABBY", 99, "KINGLER", 108, "LICKITUNG",
    112, "RHYDON", 114, "TANGELA", 123, "SCYTHER", 127, "PINSIR", 141, "KABUTOPS", 151, "MEW",
    152, "CHIKORITA", 153, "BAYLEEF", 154, "MEGANIUM", 156, "QUILAVA", 157, "TYPHLOSION", 158, "TOTODILE",
    159, "CROCONAW", 160, "FERALIGATR", 161, "SENTRET", 162, "FURRET", 182, "BELLOSSOM", 190, "AIPOM",
    192, "SUNFLORA", 196, "ESPEON", 197, "UMBREON", 207, "GLIGAR", 208, "STEELIX", 212, "SCIZOR",
    214, "HERACROSS", 215, "SNEASEL", 216, "TEDDIURSA", 217, "URSARING", 227, "SKARMORY", 248, "TYRANITAR", 251, "CELEBI"
  },
  FLY = {
    6, "CHARIZARD", 16, "PIDGEY", 17, "PIDGEOTTO", 18, "PIDGEOT", 21, "SPEAROW", 22, "FEAROW",
    83, "FARFETCHD", 84, "DODUO", 85, "DODRIO", 142, "AERODACTYL", 144, "ARTICUNO", 145, "ZAPDOS",
    146, "MOLTRES", 149, "DRAGONITE", 151, "MEW", 163, "HOOTHOOT", 164, "NOCTOWL", 169, "CROBAT",
    176, "TOGETIC", 177, "NATU", 178, "XATU", 198, "MURKROW", 225, "DELIBIRD", 227, "SKARMORY",
    249, "LUGIA", 250, "HO_OH"
  },
  SURF = {
    7, "SQUIRTLE", 8, "WARTORTLE", 9, "BLASTOISE", 31, "NIDOQUEEN", 34, "NIDOKING", 54, "PSYDUCK",
    55, "GOLDUCK", 60, "POLIWAG", 61, "POLIWHIRL", 62, "POLIWRATH", 72, "TENTACOOL", 73, "TENTACRUEL",
    79, "SLOWPOKE", 80, "SLOWBRO", 86, "SEEL", 87, "DEWGONG", 90, "SHELLDER", 91, "CLOYSTER",
    98, "KRABBY", 99, "KINGLER", 108, "LICKITUNG", 112, "RHYDON", 115, "KANGASKHAN", 116, "HORSEA",
    117, "SEADRA", 118, "GOLDEEN", 119, "SEAKING", 120, "STARYU", 121, "STARMIE", 128, "TAUROS",
    130, "GYARADOS", 131, "LAPRAS", 134, "VAPOREON", 138, "OMANYTE", 139, "OMASTAR", 141, "KABUTOPS",
    143, "SNORLAX", 147, "DRATINI", 148, "DRAGONAIR", 149, "DRAGONITE", 151, "MEW", 158, "TOTODILE",
    159, "CROCONAW", 160, "FERALIGATR", 162, "FURRET", 170, "CHINCHOU", 171, "LANTURN", 183, "MARILL",
    184, "AZUMARILL", 186, "POLITOED", 194, "WOOPER", 195, "QUAGSIRE", 199, "SLOWKING", 211, "QWILFISH",
    215, "SNEASEL", 222, "CORSOLA", 223, "REMORAID", 224, "OCTILLERY", 226, "MANTINE", 230, "KINGDRA",
    241, "MILTANK", 245, "SUICUNE", 248, "TYRANITAR", 249, "LUGIA"
  },
  STRENGTH = {
    6, "CHARIZARD", 7, "SQUIRTLE", 8, "WARTORTLE", 9, "BLASTOISE", 20, "RATICATE", 23, "EKANS",
    24, "ARBOK", 25, "PIKACHU", 26, "RAICHU", 27, "SANDSHREW", 28, "SANDSLASH", 31, "NIDOQUEEN",
    34, "NIDOKING", 35, "CLEFAIRY", 36, "CLEFABLE", 39, "JIGGLYPUFF", 40, "WIGGLYTUFF", 54, "PSYDUCK",
    55, "GOLDUCK", 56, "MANKEY", 57, "PRIMEAPE", 61, "POLIWHIRL", 62, "POLIWRATH", 66, "MACHOP",
    67, "MACHOKE", 68, "MACHAMP", 74, "GEODUDE", 75, "GRAVELER", 76, "GOLEM", 79, "SLOWPOKE",
    80, "SLOWBRO", 86, "SEEL", 87, "DEWGONG", 94, "GENGAR", 95, "ONIX", 98, "KRABBY", 99, "KINGLER",
    103, "EXEGGUTOR", 104, "CUBONE", 105, "MAROWAK", 106, "HITMONLEE", 107, "HITMONCHAN", 108, "LICKITUNG",
    111, "RHYHORN", 112, "RHYDON", 113, "CHANSEY", 115, "KANGASKHAN", 125, "ELECTABUZZ", 127, "PINSIR",
    128, "TAUROS", 130, "GYARADOS", 131, "LAPRAS", 139, "OMASTAR", 143, "SNORLAX", 149, "DRAGONITE",
    150, "MEWTWO", 151, "MEW", 153, "BAYLEEF", 154, "MEGANIUM", 157, "TYPHLOSION", 160, "FERALIGATR",
    162, "FURRET", 180, "FLAAFFY", 181, "AMPHAROS", 184, "AZUMARILL", 185, "SUDOWOODO", 186, "POLITOED",
    190, "AIPOM", 195, "QUAGSIRE", 199, "SLOWKING", 205, "FORRETRESS", 206, "DUNSPARCE", 207, "GLIGAR",
    208, "STEELIX", 210, "GRANBULL", 212, "SCIZOR", 213, "SHUCKLE", 214, "HERACROSS", 215, "SNEASEL",
    216, "TEDDIURSA", 217, "URSARING", 219, "MAGCARGO", 220, "SWINUB", 221, "PILOSWINE", 222, "CORSOLA",
    229, "HOUNDOOM", 231, "PHANPY", 232, "DONPHAN", 237, "HITMONTOP", 241, "MILTANK", 242, "BLISSEY",
    243, "RAIKOU", 244, "ENTEI", 245, "SUICUNE", 248, "TYRANITAR", 249, "LUGIA", 250, "HO_OH"
  },
  FLASH = {
    1, "BULBASAUR", 2, "IVYSAUR", 3, "VENUSAUR", 12, "BUTTERFREE", 25, "PIKACHU", 26, "RAICHU",
    35, "CLEFAIRY", 36, "CLEFABLE", 39, "JIGGLYPUFF", 40, "WIGGLYTUFF", 43, "ODDISH", 44, "GLOOM",
    45, "VILEPLUME", 46, "PARAS", 47, "PARASECT", 49, "VENOMOTH", 54, "PSYDUCK", 55, "GOLDUCK",
    63, "ABRA", 64, "KADABRA", 65, "ALAKAZAM", 69, "BELLSPROUT", 70, "WEEPINBELL", 71, "VICTREEBEL",
    79, "SLOWPOKE", 80, "SLOWBRO", 81, "MAGNEMITE", 82, "MAGNETON", 96, "DROWZEE", 97, "HYPNO",
    100, "VOLTORB", 101, "ELECTRODE", 102, "EXEGGCUTE", 103, "EXEGGUTOR", 113, "CHANSEY", 114, "TANGELA",
    120, "STARYU", 121, "STARMIE", 122, "MR_MIME", 125, "ELECTABUZZ", 126, "MAGMAR", 135, "JOLTEON",
    137, "PORYGON", 145, "ZAPDOS", 150, "MEWTWO", 151, "MEW", 152, "CHIKORITA", 153, "BAYLEEF",
    154, "MEGANIUM", 155, "CYNDAQUIL", 156, "QUILAVA", 157, "TYPHLOSION", 161, "SENTRET", 163, "HOOTHOOT",
    164, "NOCTOWL", 165, "LEDYBA", 166, "LEDIAN", 167, "SPINARAK", 168, "ARIADOS", 170, "CHINCHOU",
    171, "LANTURN", 172, "PICHU", 173, "CLEFFA", 174, "IGGLYBUFF", 175, "TOGEPI", 176, "TOGETIC",
    177, "NATU", 178, "XATU", 179, "MAREEP", 180, "FLAAFFY", 181, "AMPHAROS", 182, "BELLOSSOM",
    187, "HOPPIP", 188, "SKIPLOOM", 189, "JUMPLUFF", 191, "SUNKERN", 192, "SUNFLORA", 193, "YANMA",
    196, "ESPEON", 197, "UMBREON", 199, "SLOWKING", 200, "MISDREAVUS", 203, "GIRAFARIG", 204, "PINECO",
    209, "SNUBBULL", 210, "GRANBULL", 213, "SHUCKLE", 233, "PORYGON2", 234, "STANTLER", 239, "ELEKID",
    242, "BLISSEY", 243, "RAIKOU", 244, "ENTEI", 250, "HO_OH", 251, "CELEBI"
  },
  WHIRLPOOL = {
    7, "SQUIRTLE", 8, "WARTORTLE", 9, "BLASTOISE", 54, "PSYDUCK", 55, "GOLDUCK", 60, "POLIWAG",
    61, "POLIWHIRL", 62, "POLIWRATH", 72, "TENTACOOL", 73, "TENTACRUEL", 86, "SEEL", 87, "DEWGONG",
    90, "SHELLDER", 91, "CLOYSTER", 98, "KRABBY", 99, "KINGLER", 116, "HORSEA", 117, "SEADRA",
    118, "GOLDEEN", 119, "SEAKING", 120, "STARYU", 121, "STARMIE", 130, "GYARADOS", 131, "LAPRAS",
    134, "VAPOREON", 138, "OMANYTE", 139, "OMASTAR", 141, "KABUTOPS", 147, "DRATINI", 148, "DRAGONAIR",
    149, "DRAGONITE", 151, "MEW", 159, "CROCONAW", 160, "FERALIGATR", 170, "CHINCHOU", 171, "LANTURN",
    183, "MARILL", 184, "AZUMARILL", 186, "POLITOED", 194, "WOOPER", 195, "QUAGSIRE", 199, "SLOWKING",
    211, "QWILFISH", 222, "CORSOLA", 223, "REMORAID", 224, "OCTILLERY", 226, "MANTINE", 230, "KINGDRA",
    245, "SUICUNE", 249, "LUGIA"
  },
  WATERFALL = {
    7, "SQUIRTLE", 8, "WARTORTLE", 9, "BLASTOISE", 54, "PSYDUCK", 55, "GOLDUCK", 60, "POLIWAG",
    61, "POLIWHIRL", 62, "POLIWRATH", 72, "TENTACOOL", 73, "TENTACRUEL", 86, "SEEL", 87, "DEWGONG",
    116, "HORSEA", 117, "SEADRA", 118, "GOLDEEN", 119, "SEAKING", 120, "STARYU", 121, "STARMIE",
    130, "GYARADOS", 131, "LAPRAS", 134, "VAPOREON", 147, "DRATINI", 148, "DRAGONAIR", 149, "DRAGONITE",
    151, "MEW", 170, "CHINCHOU", 171, "LANTURN", 183, "MARILL", 184, "AZUMARILL", 186, "POLITOED",
    194, "WOOPER", 195, "QUAGSIRE", 211, "QWILFISH", 226, "MANTINE", 230, "KINGDRA", 245, "SUICUNE", 249, "LUGIA"
  },
  ROCK_SMASH = {
    4, "CHARMANDER", 5, "CHARMELEON", 6, "CHARIZARD", 7, "SQUIRTLE", 8, "WARTORTLE", 9, "BLASTOISE",
    19, "RATTATA", 20, "RATICATE", 27, "SANDSHREW", 28, "SANDSLASH", 30, "NIDORINA", 31, "NIDOQUEEN",
    33, "NIDORINO", 34, "NIDOKING", 46, "PARAS", 47, "PARASECT", 50, "DIGLETT", 51, "DUGTRIO",
    54, "PSYDUCK", 55, "GOLDUCK", 56, "MANKEY", 57, "PRIMEAPE", 58, "GROWLITHE", 59, "ARCANINE",
    61, "POLIWHIRL", 62, "POLIWRATH", 66, "MACHOP", 67, "MACHOKE", 68, "MACHAMP", 74, "GEODUDE",
    75, "GRAVELER", 76, "GOLEM", 79, "SLOWPOKE", 80, "SLOWBRO", 94, "GENGAR", 95, "ONIX", 98, "KRABBY",
    99, "KINGLER", 104, "CUBONE", 105, "MAROWAK", 106, "HITMONLEE", 107, "HITMONCHAN", 108, "LICKITUNG",
    111, "RHYHORN", 112, "RHYDON", 113, "CHANSEY", 115, "KANGASKHAN", 123, "SCYTHER", 125, "ELECTABUZZ",
    126, "MAGMAR", 127, "PINSIR", 128, "TAUROS", 130, "GYARADOS", 131, "LAPRAS", 138, "OMANYTE",
    139, "OMASTAR", 140, "KABUTO", 141, "KABUTOPS", 142, "AERODACTYL", 143, "SNORLAX", 144, "ARTICUNO",
    145, "ZAPDOS", 146, "MOLTRES", 149, "DRAGONITE", 150, "MEWTWO", 151, "MEW", 152, "CHIKORITA",
    153, "BAYLEEF", 154, "MEGANIUM", 155, "CYNDAQUIL", 156, "QUILAVA", 157, "TYPHLOSION", 158, "TOTODILE",
    159, "CROCONAW", 160, "FERALIGATR", 175, "TOGEPI", 176, "TOGETIC", 179, "MAREEP", 180, "FLAAFFY",
    181, "AMPHAROS", 183, "MARILL", 184, "AZUMARILL", 185, "SUDOWOODO", 186, "POLITOED", 190, "AIPOM",
    194, "WOOPER", 195, "QUAGSIRE", 199, "SLOWKING", 203, "GIRAFARIG", 204, "PINECO", 205, "FORRETRESS",
    206, "DUNSPARCE", 207, "GLIGAR", 208, "STEELIX", 209, "SNUBBULL", 210, "GRANBULL", 212, "SCIZOR",
    213, "SHUCKLE", 214, "HERACROSS", 215, "SNEASEL", 216, "TEDDIURSA", 217, "URSARING", 218, "SLUGMA",
    219, "MAGCARGO", 220, "SWINUB", 221, "PILOSWINE", 222, "CORSOLA", 228, "HOUNDOUR", 229, "HOUNDOOM",
    231, "PHANPY", 232, "DONPHAN", 236, "TYROGUE", 237, "HITMONTOP", 241, "MILTANK", 242, "BLISSEY",
    243, "RAIKOU", 244, "ENTEI", 245, "SUICUNE", 248, "TYRANITAR", 249, "LUGIA", 250, "HO_OH"
  }
}

local function hasCount(value)
  if type(value) == "number" then return value > 0 end
  return value == true
end

local function ownedHM(game, moveId)
  local inventory = game and game.save and game.save.inventory or {}
  local items = game and game.data and game.data.items or {}
  
  local targetHM = HM_TO_MACHINE[moveId] and HM_TO_MACHINE[moveId][1]

  for itemId, count in pairs(inventory) do
    if hasCount(count) then
      if itemId == targetHM or (items[itemId] and items[itemId].machine and items[itemId].machine.move == moveId) then
        return itemId, items[itemId]
      end
    end
  end
  return nil
end

local function hasAnyHM(game)
  for _, moveId in ipairs(HM_ORDER) do
    if ownedHM(game, moveId) then return true end
  end
  return false
end

local function hasBadge(game, moveId)
  local badge = HM_BADGES[moveId]
  if not badge then return true end
  
  local flags = game and game.save and (game.save.flags or game.save.badges)
  if flags then
    if flags["ENGINE_" .. badge] or flags[badge] or flags[badge:lower()] then
      return true
    end
  end

  local inventory = game and game.save and game.save.inventory or {}
  return hasCount(inventory[badge])
end

-- -------------------------------------------------------------------------
-- Ultra-Robust Multi-Key Compatibility Checker
-- -------------------------------------------------------------------------

local function isFainted(mon)
  if not mon then return true end
  if type(mon.hp) == "number" then return mon.hp <= 0 end
  if type(mon.currentHp) == "number" then return mon.currentHp <= 0 end
  if type(mon.current_hp) == "number" then return mon.current_hp <= 0 end
  return false
end

local function canLearnHM(game, mon, moveId)
  if isFainted(mon) then return false end

  -- 1. Check actively equipped moveset
  if mon.moves then
    for _, m in ipairs(mon.moves) do
      local mid = type(m) == "table" and (m.id or m.move or m.name) or m
      if mid == moveId or (type(mid) == "string" and mid:upper() == moveId) then 
        return true 
      end
    end
  end

  -- Extract all possible key forms for species identifier
  local rawSpecies = mon.species or mon.speciesId or mon.def or mon.id or mon.name or mon.species_id
  local candidateKeys = {}

  if type(rawSpecies) == "table" then
    if rawSpecies.id then table.insert(candidateKeys, rawSpecies.id) end
    if rawSpecies.name then table.insert(candidateKeys, rawSpecies.name) end
    if rawSpecies.species then table.insert(candidateKeys, rawSpecies.species) end
    if rawSpecies.nationalPokedexNumber then table.insert(candidateKeys, rawSpecies.nationalPokedexNumber) end
    if rawSpecies.dexNo then table.insert(candidateKeys, rawSpecies.dexNo) end
  elseif rawSpecies then
    table.insert(candidateKeys, rawSpecies)
  end

  local searchMap = {}
  for _, k in ipairs(candidateKeys) do
    searchMap[k] = true
    local s = tostring(k):upper()
    searchMap[s] = true
    searchMap[s:lower()] = true
    
    if s:find("^SPECIES_") then
      local clean = s:gsub("^SPECIES_", "")
      searchMap[clean] = true
      searchMap[clean:lower()] = true
    end

    local n = tonumber(k)
    if n then searchMap[n] = true end
  end

  -- Move Targets (FLASH, HM05, etc.)
  local moveTargets = { [moveId] = true, [moveId:lower()] = true }
  if HM_TO_MACHINE[moveId] then
    for _, mCode in ipairs(HM_TO_MACHINE[moveId]) do
      moveTargets[mCode] = true
      moveTargets[mCode:lower()] = true
    end
  end

  -- 2. Engine Pokedex Dynamic Inspection
  local pokedex = game and game.data and game.data.pokedex
  if type(pokedex) == "table" then
    for targetKey in pairs(searchMap) do
      local entry = pokedex[targetKey]
      if entry then
        local tmhmTable = entry.tmhm or entry.tms or entry.machines or entry.learnable_tms
        if type(tmhmTable) == "table" then
          for tKey in pairs(moveTargets) do
            if tmhmTable[tKey] == true or tmhmTable[tKey] == 1 then
              return true
            end
          end
          for _, val in ipairs(tmhmTable) do
            local sVal = tostring(val):upper()
            if moveTargets[sVal] or sVal == moveId then
              return true
            end
          end
        end
      end
    end
  end

  -- 3. Hardcoded Learners Fallback Check
  local fallbackList = HARDCODED_HM_LEARNERS[moveId]
  if fallbackList then
    for _, learnerKey in ipairs(fallbackList) do
      if searchMap[learnerKey] or searchMap[tostring(learnerKey):upper()] then
        return true
      end
    end
  end

  return false
end

local function getEligibleMon(game, moveId)
  local party = game and game.save and game.save.party or {}
  for _, mon in ipairs(party) do
    if canLearnHM(game, mon, moveId) then
      return mon
    end
  end
  return nil
end

local function contextualEnabled(mod)
  return mod.save:get("contextualActions", true) ~= false
end

local function setContextual(mod, enabled)
  mod.save:set("contextualActions", enabled and true or false)
end

local function pushText(game, text, onDone)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, onDone))
end

local function textOr(game, key, fallback)
  local text = game and game.data and game.data.text
  return (text and text[key]) or fallback
end

local function badgeRequired(game)
  return textOr(game, "_NewBadgeRequiredText", "A new BADGE is\nrequired.")
end

local function noLandingText(game)
  return textOr(game, "_SurfingNoPlaceToGetOffText", "There's no place\nto get off!")
end

local function fieldUnavailable(game, moveId, reopen)
  pushText(game, moveId .. " can't be\nused right now.", reopen)
end

-- Helper to check if facing tile or NPC ahead is a whirlpool
local function isFacingWhirlpool(ow)
    if not (ow and ow.player and ow.player.facingCell) then return false end
    local fx, fy = ow.player:facingCell()

    -- 1. NATIVE ENGINE CHECK (From OverworldController.lua)
    -- This checks the cell tile ID directly against the 0x24/0x2C hex values!
    if ow.gen2IsWhirlpool and ow:gen2IsWhirlpool(fx, fy) then
        return true
    end

    -- 2. Check Map object/NPC at target location (Original fallback)
    local npc = ow.npcAtCell and ow:npcAtCell(fx, fy)
    if npc and npc.def then
        local id = tostring(npc.def.id or npc.def.name or ""):upper()
        if id:find("WHIRLPOOL") then return true end
    end

    -- 3. Fallback tile inspection (Original fallback)
    if ow.map and ow.map.getTile then
        local tile = ow.map:getTile(fx, fy)
        if type(tile) == "string" and tile:upper():find("WHIRLPOOL") then return true end
    end

    return false
end

-- -------------------------------------------------------------------------
-- Contextual A-button actions 
-- -------------------------------------------------------------------------

local function tryRockSmash(game, ow)
  if not ownedHM(game, "ROCK_SMASH") then return false end
  local fn = ow.useRockSmashFieldMove or ow.useRockSmash
  if not fn then return false end

  local reason = fn(ow)
  if reason ~= "ok" and reason ~= true then return false end

  if not hasBadge(game, "ROCK_SMASH") then
    pushText(game, badgeRequired(game))
    return true
  end

  if not getEligibleMon(game, "ROCK_SMASH") then return false end

  local fx, fy = ow.player:facingCell()
  if ow.tryRockSmash then ow:tryRockSmash(fx, fy) end
  return true
end

local function tryStrength(game, ow)
  if not ownedHM(game, "STRENGTH") then return false end
  local Map = require("src.world.Map")
  local player = ow.player
  local fx, fy = player:facingCell()
  local npc = ow:npcAtCell(fx, fy)
  if not (npc and npc.def and Map.isPushable(npc.def)) then return false end

  if not hasBadge(game, "STRENGTH") then
    pushText(game, badgeRequired(game))
    return true
  end

  if not getEligibleMon(game, "STRENGTH") then return false end

  local function pushNow()
    if not (ow.map and ow.player) then return end
    ow.strengthActive = true
    ow.boulderTried = nil
    ow:checkBoulderPush(player.facing)
    ow:checkBoulderPush(player.facing)
  end

  if not ow.strengthActive then
    ow.strengthActive = true
    pushText(game, "The HM device used\nSTRENGTH!\fBoulders can now\nbe moved.", pushNow)
  else
    pushNow()
  end
  return true
end

local function tryCut(game, ow)
  if not ownedHM(game, "CUT") then return false end
  local fn = ow.useCutFieldMove or ow.useCut
  if not fn then return false end

  local reason = fn(ow)
  if reason ~= "ok" and reason ~= true then return false end

  if not hasBadge(game, "CUT") then
    pushText(game, badgeRequired(game))
    return true
  end

  if not getEligibleMon(game, "CUT") then return false end

  local fx, fy = ow.player:facingCell()
  if ow.tryCut then ow:tryCut(fx, fy) end
  return true
end

local function tryWhirlpool(game, ow)
    if not ownedHM(game, "WHIRLPOOL") then return false end
    local isWhirl = isFacingWhirlpool(ow)
    if not isWhirl then return false end

    if not hasBadge(game, "WHIRLPOOL") then pushText(game, badgeRequired(game)) return true end
    if not getEligibleMon(game, "WHIRLPOOL") then return false end

    local fx, fy = ow.player:facingCell()
    
    local function dispel()
        -- Query the engine for the whirlpool tile block
        local row, bx, by = ow:gen2WhirlpoolSwap(fx, fy)
        if row then
            -- 1. Cache the change so the whirlpool stays cleared!
            ow.cutBlocks = ow.cutBlocks or {}
            ow.cutBlocks[ow.map.id] = ow.cutBlocks[ow.map.id] or {}
            table.insert(ow.cutBlocks[ow.map.id], { bx = bx, by = by, block = row.before })
            
            -- 2. Physically swap the map block in memory
            ow.map:setBlock(bx, by, row.after)
            
            -- 3. Force the renderer to redraw the map so the change is visible
            if ow.map.renderer and ow.map.renderer.rebuild then
                ow.map.renderer:rebuild()
            end
        end

        -- 4. Play the native overworld dust animation and "Cut" sound effect!
        if ow.startDustAnim then
            ow:startDustAnim(fx, fy, function()
                pcall(function()
                    require("src.core.Sound").play(game.data, "Cut")
                end)
            end)
        end
    end

    pushText(game, "The HM device used\nWHIRLPOOL!", dispel)
    return true
end

local function tryWaterfall(game, ow)
  if not ownedHM(game, "WATERFALL") then return false end
  local fn = ow.useWaterfallFieldMove or ow.useWaterfall or ow.tryWaterfall
  if not fn then return false end

  local reason = fn(ow)
  if reason ~= "ok" and reason ~= true then return false end

  if not hasBadge(game, "WATERFALL") then
    pushText(game, badgeRequired(game))
    return true
  end

  if not getEligibleMon(game, "WATERFALL") then return false end

  if ow.tryWaterfall then ow:tryWaterfall() end
  return true
end

local function dismountSurf(game, ow)
  local player = ow.player
  player.surfing = false
  require("src.core.Music").setSurfing(game.data, false)
  local Transition = require("src.render.Transition")
  game.stack:push(Transition.whiteFlash(game, nil, function()
    ow:stepForwardOrCrossEdge(player.facing)
  end))
end

local function trySurf(game, ow)
  if not ownedHM(game, "SURF") then return false end
  local fn = ow.useSurfFieldMove or ow.useSurf
  if not fn then return false end

  local reason = fn(ow)
  if reason == "no_water" or reason == "forced_bike" or reason == "current" then
    return false
  end

  if not hasBadge(game, "SURF") then
    if reason == "ok" then
      pushText(game, badgeRequired(game))
      return true
    end
    return false
  end

  if not getEligibleMon(game, "SURF") then return false end

  if reason == "ok" then
    local fx, fy = ow.player:facingCell()
    if ow.trySurf then ow:trySurf(fx, fy) end
    return true
  elseif reason == "dismount" then
    dismountSurf(game, ow)
    return true
  elseif reason == "no_place" then
    pushText(game, noLandingText(game))
    return true
  end
  return false
end

local function directNpcAhead(ow)
  local player = ow and ow.player
  if not (player and ow.npcAtCell) then return nil end
  local fx, fy = player:facingCell()
  return ow:npcAtCell(fx, fy)
end

local function contextualInteract(game, mod, baseInteract, ow, ...)
  if not (ow and ow.player and ow.map) then return baseInteract(ow, ...) end

  if not contextualEnabled(mod) then
    return baseInteract(ow, ...)
  end

  -- Check interactions that can occupy target cells before standard NPC interaction
  if tryStrength(game, ow) then return end
  if tryWhirlpool(game, ow) then return end
  if tryCut(game, ow) then return end
  if tryRockSmash(game, ow) then return end

  if directNpcAhead(ow) then
    return baseInteract(ow, ...)
  end

  if tryWaterfall(game, ow) then return end
  if trySurf(game, ow) then return end

  return baseInteract(ow, ...)
end

-- -------------------------------------------------------------------------
-- Manual Start -> HM actions
-- -------------------------------------------------------------------------

local function isOutside(game, ow)
  if not (ow and ow.map and ow.map.def) then return false end
  local Map = require("src.world.Map")
  local FieldDefaults = require("src.world.FieldDefaults")
  return Map.isOutside(ow.map.def, FieldDefaults.field(game.data, "outsideTilesets"))
end

local function removeVanillaHMRows(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    local label = tostring(item.label or ""):upper()
    if not FIELD_HMS[label] then out[#out + 1] = item end
  end
  return out
end

local function rockSmashFromMenu(game, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "ROCK", reopen); return end
  if not hasBadge(game, "ROCK_SMASH") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "ROCK_SMASH") then pushText(game, "No Pokémon can\nuse ROCK SMASH.", reopen); return end

  local fn = ow.useRockSmashFieldMove or ow.useRockSmash
  if fn and fn(ow) == "ok" then
    local fx, fy = ow.player:facingCell()
    if ow.tryRockSmash then ow:tryRockSmash(fx, fy) end
  else
    pushText(game, "It's a smashable\nrock.", reopen)
  end
end

local function cutFromMenu(game, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "CUT", reopen); return end
  if not hasBadge(game, "CUT") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "CUT") then pushText(game, "No Pokémon can\nuse CUT.", reopen); return end

  local fn = ow.useCutFieldMove or ow.useCut
  local reason = fn and fn(ow)
  if reason == "ok" then
    local fx, fy = ow.player:facingCell()
    if ow.tryCut then ow:tryCut(fx, fy) end
  else
    pushText(game, textOr(game, "_NothingToCutText", "Nothing to CUT!"), reopen)
  end
end

local function surfFromMenu(game, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "SURF", reopen); return end
  if not hasBadge(game, "SURF") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "SURF") then pushText(game, "No Pokémon can\nuse SURF.", reopen); return end

  local fn = ow.useSurfFieldMove or ow.useSurf
  local reason = fn and fn(ow)
  if reason == "ok" then
    local fx, fy = ow.player:facingCell()
    if ow.trySurf then ow:trySurf(fx, fy) end
  elseif reason == "dismount" then
    dismountSurf(game, ow)
  elseif reason == "no_place" then
    pushText(game, noLandingText(game), reopen)
  else
    pushText(game, textOr(game, "_NoSurfingHereText", "No SURFing here!"), reopen)
  end
end

local function strengthFromMenu(game, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "STR", reopen); return end
  if not hasBadge(game, "STRENGTH") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "STRENGTH") then pushText(game, "No Pokémon can\nuse STRENGTH.", reopen); return end

  if ow.strengthActive then
    pushText(game, "STRENGTH is already\nbeing used.", reopen)
    return
  end

  ow.strengthActive = true
  pushText(game, "The HM device used\nSTRENGTH!\fBoulders can now\nbe moved.")
end

local function flashFromMenu(game, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "FLASH", reopen); return end
  if not hasBadge(game, "FLASH") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "FLASH") then pushText(game, "No Pokémon can\nuse FLASH.", reopen); return end
  if not ow.dark then
    pushText(game, "It is already\nbright here.", reopen)
    return
  end

  game.save.flashLit = true
  pushText(game, textOr(game, "_FlashLightsAreaText", "A blinding FLASH\nlights the area!"), function()
    local Transition = require("src.render.Transition")
    game.stack:push(Transition.whiteFlash(game, nil, function()
      if ow.setDark then ow:setDark(false) else ow.dark = false end
    end))
  end)
end

local function flyFromMenu(game, mod, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "FLY", reopen); return end
  if not hasBadge(game, "FLY") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "FLY") then pushText(game, "No Pokémon can\nuse FLY.", reopen); return end
  if not isOutside(game, ow) then
    pushText(game, "FLY can't be used\nhere.", reopen)
    return
  end

  local current = ow
  mod.ui.push(game, "TownMap", {
    fly = true,
    onFly = function(mapId)
      if current and current.flyTo then current:flyTo(mapId) end
    end,
  })
end

local function whirlpoolFromMenu(game, reopen)
    local ow = game.overworld
    if not (ow and ow.map and ow.player) then fieldUnavailable(game, "WHRL", reopen); return end
    if not hasBadge(game, "WHIRLPOOL") then pushText(game, badgeRequired(game), reopen); return end
    if not getEligibleMon(game, "WHIRLPOOL") then pushText(game, "No Pokémon can\nuse WHIRLPOOL.", reopen); return end

    local isWhirl = isFacingWhirlpool(ow)
    if isWhirl then
        local fx, fy = ow.player:facingCell()
        
        local function dispel()
            -- Query the engine for the whirlpool tile block
            local row, bx, by = ow:gen2WhirlpoolSwap(fx, fy)
            if row then
                -- 1. Cache the change
                ow.cutBlocks = ow.cutBlocks or {}
                ow.cutBlocks[ow.map.id] = ow.cutBlocks[ow.map.id] or {}
                table.insert(ow.cutBlocks[ow.map.id], { bx = bx, by = by, block = row.before })
                
                -- 2. Swap the map block
                ow.map:setBlock(bx, by, row.after)
                
                -- 3. Rebuild the map renderer
                if ow.map.renderer and ow.map.renderer.rebuild then
                    ow.map.renderer:rebuild()
                end
            end
            
            -- 4. Play dust animation and sound
            if ow.startDustAnim then
                ow:startDustAnim(fx, fy, function()
                    pcall(function()
                        require("src.core.Sound").play(game.data, "Cut")
                    end)
                end)
            end
        end
        
        pushText(game, "The HM device used\nWHIRLPOOL!", dispel)
    else
        pushText(game, "It's a vicious\nwhirlpool!", reopen)
    end
end

local function waterfallFromMenu(game, reopen)
  local ow = game.overworld
  if not (ow and ow.map and ow.player) then fieldUnavailable(game, "WTFL", reopen); return end
  if not hasBadge(game, "WATERFALL") then pushText(game, badgeRequired(game), reopen); return end
  if not getEligibleMon(game, "WATERFALL") then pushText(game, "No Pokémon can\nuse WATERFALL.", reopen); return end

  local fn = ow.useWaterfallFieldMove or ow.useWaterfall
  if fn and fn(ow) == "ok" then
    if ow.tryWaterfall then ow:tryWaterfall() end
  else
    pushText(game, "A wall of water is\ntumbling down.", reopen)
  end
end

local function openHMMenu(game, mod)
  local Menu = require("src.ui.Menu")
  local Screens = require("src.ui.Screens")

  local function reopen()
    openHMMenu(game, mod)
  end

  local items = {}

  for _, moveId in ipairs(HM_ORDER) do
    if ownedHM(game, moveId) then
      local label = HM_LABEL[moveId]
      if moveId == "CUT" then
        items[#items + 1] = { label = label, onSelect = function() cutFromMenu(game, reopen) end }
      elseif moveId == "FLY" then
        items[#items + 1] = { label = label, onSelect = function() flyFromMenu(game, mod, reopen) end }
      elseif moveId == "SURF" then
        items[#items + 1] = { label = label, onSelect = function() surfFromMenu(game, reopen) end }
      elseif moveId == "STRENGTH" then
        items[#items + 1] = { label = label, onSelect = function() strengthFromMenu(game, reopen) end }
      elseif moveId == "FLASH" then
        items[#items + 1] = { label = label, onSelect = function() flashFromMenu(game, reopen) end }
      elseif moveId == "WHIRLPOOL" then
        items[#items + 1] = { label = label, onSelect = function() whirlpoolFromMenu(game, reopen) end }
      elseif moveId == "WATERFALL" then
        items[#items + 1] = { label = label, onSelect = function() waterfallFromMenu(game, reopen) end }
      elseif moveId == "ROCK_SMASH" then
        items[#items + 1] = { label = label, onSelect = function() rockSmashFromMenu(game, reopen) end }
      end
    end
  end

  if #items == 0 then
    pushText(game, "No usable HM is\nin the BAG.", function()
      Screens.push(game, "StartMenu")
    end)
    return
  end

  local contextItem
  contextItem = {
    label = contextualEnabled(mod) and "CTX ON" or "CTX OFF",
    keepOpen = true,
    onSelect = function()
      local enabled = not contextualEnabled(mod)
      setContextual(mod, enabled)
      contextItem.label = enabled and "CTX ON" or "CTX OFF"
      mod.log:info("HM Anywhere contextual actions: %s", enabled and "ON" or "OFF")
    end,
  }
  items[#items + 1] = contextItem

  game.stack:push(Menu.new(game, items, {
    tx = 9,
    ty = 0,
    tw = 11,
    th = 18,
    maxVisible = 8,
    anchor = "topright",
    onCancel = function()
      Screens.push(game, "StartMenu")
    end,
  }))
end

return function(mod)
  mod.events:on("game.ready", function(event)
    local game = event and event.game
    local OverworldState = game and game.overworld
    if not (game and type(OverworldState) == "table") then
      mod.log:warn("HM Anywhere could not install: game.ready had no overworld")
      return
    end

    local dispatch = rawget(_G, PATCH_KEY)
    if not dispatch then
      dispatch = {
        baseInteract = OverworldState.interact,
        basePartyKnows = OverworldState.partyKnows,
      }
      rawset(_G, PATCH_KEY, dispatch)

      OverworldState.interact = function(self, ...)
        local handler = dispatch.interact
        if handler then return handler(self, ...) end
        return dispatch.baseInteract(self, ...)
      end

      OverworldState.partyKnows = function(self, moveId, ...)
        local handler = dispatch.partyKnows
        if handler then
          local mon = handler(self, moveId, ...)
          if mon then return mon end
        end
        return dispatch.basePartyKnows(self, moveId, ...)
      end
    end

    dispatch.interact = function(ow, ...)
      return contextualInteract(game, mod, dispatch.baseInteract, ow, ...)
    end

    dispatch.partyKnows = function(_, moveId)
      if FIELD_HMS[moveId] and ownedHM(game, moveId) and hasBadge(game, moveId) then
        local mon = getEligibleMon(game, moveId)
        if mon then return mon end
      end
      return nil
    end

    mod.log:info("HM Anywhere installed for Gen2Recomped.")
  end)

  mod.hooks:wrap("ui.party.submenu", function(next_, game, items, mon, ctx)
    local out = next_(game, items, mon, ctx)
    if type(out) ~= "table" or (ctx and ctx.battle) then return out end
    return removeVanillaHMRows(out)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(next_, game, items)
    local out = next_(game, items)
    if type(out) ~= "table" then return out end
    if not hasAnyHM(game) then return out end
    for _, item in ipairs(out) do
      if tostring(item.label):upper() == "HM" then return out end
    end
    return mod.ui.insertBefore(out, "SAVE", {
      label = "HM",
      onSelect = function()
        openHMMenu(game, mod)
      end,
    })
  end)

  mod.exports.ownedHM = function(game, moveId)
    return ownedHM(game, moveId) ~= nil
  end
  mod.exports.hasBadge = hasBadge
  mod.exports.contextualEnabled = function()
    return contextualEnabled(mod)
  end
  mod.exports.setContextual = function(enabled)
    setContextual(mod, enabled)
  end
end
