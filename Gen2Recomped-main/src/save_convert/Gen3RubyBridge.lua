-- Bridge between Gen3Save's Emerald-shaped decode/encode tables and Game3's
-- gen3-ruby-1 snapshot (numeric species/flags, bag arrays, g{group}_{num} maps).
-- Used for vanilla US Ruby/Sapphire 128 KiB flash import and export.

local Gen3RubyBridge = {}

Gen3RubyBridge.SAVE_FORMAT = "gen3-ruby-1"
Gen3RubyBridge.ENGINE = "gen3"

local POCKET_NAME = {
  [1] = "ITEM", [2] = "BALL", [3] = "TM_HM", [4] = "BERRY", [5] = "KEY_ITEM",
  ITEM = "ITEM", BALL = "BALL", TM_HM = "TM_HM", BERRY = "BERRY",
  KEY_ITEM = "KEY_ITEM",
}

local function stampIndex(src)
  local out = {}
  if type(src) ~= "table" then return out end
  local rows = src.byIndex or src.byId or src
  for k, def in pairs(rows) do
    if type(def) == "table" then
      local idx = tonumber(def.index) or tonumber(def.id) or tonumber(k)
      if idx then
        local copy = {}
        for fk, fv in pairs(def) do copy[fk] = fv end
        copy.index = idx
        copy.id = copy.id or idx
        if copy.pocket ~= nil then
          copy.pocket = POCKET_NAME[copy.pocket] or copy.pocket
        end
        out[idx] = copy
      end
    end
  end
  return out
end

function Gen3RubyBridge.prepareData(data)
  data = data or {}
  return {
    pokemon = stampIndex(data.pokemon),
    moves = stampIndex(data.moves),
    items = stampIndex(data.items),
    maps = type(data.maps) == "table" and data.maps or {},
    eventFlags = data.eventFlags or {},
  }
end

function Gen3RubyBridge.gbaCharmap()
  local ok, GbaText = pcall(require, "src.import.GbaText")
  local map = {}
  if not (ok and type(GbaText) == "table" and GbaText.decodeByte) then
    return map
  end
  for b = 0, 255 do
    local g = GbaText.decodeByte(b)
    if type(g) == "string" and g ~= "" then
      map[b] = g
      map[tostring(b)] = g
    end
  end
  map[0] = " "
  map["0"] = " "
  return map
end

local function speciesNumber(id)
  if type(id) == "number" then return id end
  if type(id) == "string" then
    local n = id:match("SPECIES_(%d+)") or id:match("^(%d+)$")
    return tonumber(n)
  end
  return nil
end

local function itemNumber(id)
  if type(id) == "number" then return id end
  if type(id) == "string" then
    local n = id:match("ITEM_(%d+)") or id:match("^(%d+)$")
    return tonumber(n)
  end
  return nil
end

local function moveNumber(id)
  if type(id) == "number" then return id end
  if type(id) == "string" then
    local n = id:match("MOVE_(%d+)") or id:match("^(%d+)$")
    return tonumber(n)
  end
  return nil
end

local function flagId(key)
  if type(key) == "number" then return key end
  if type(key) == "string" then
    local hex = key:match("^FLAG_G3_(%x+)$")
    if hex then return tonumber(hex, 16) end
    return tonumber(key)
  end
  return nil
end

local function statusFromWord(word)
  word = math.floor(tonumber(word) or 0)
  if word <= 0 then return nil, nil end
  local sleep = word % 8
  if sleep > 0 then return "slp", sleep end
  if math.floor(word / 8) % 2 == 1 then return "psn" end
  if math.floor(word / 16) % 2 == 1 then return "brn" end
  if math.floor(word / 32) % 2 == 1 then return "frz" end
  if math.floor(word / 64) % 2 == 1 then return "par" end
  if math.floor(word / 128) % 2 == 1 then return "tox" end
  return nil, nil
end

local function wordFromStatus(status, sleepTurns)
  if status == "slp" then
    return math.max(1, math.min(7, math.floor(tonumber(sleepTurns) or 2)))
  end
  if status == "psn" then return 8 end
  if status == "brn" then return 16 end
  if status == "frz" then return 32 end
  if status == "par" then return 64 end
  if status == "tox" then return 128 end
  return nil
end

local function toGame3Ivs(ivs)
  ivs = ivs or {}
  return {
    hp = ivs.hp or 0,
    atk = ivs.atk or ivs.attack or 0,
    def = ivs.def or ivs.defense or 0,
    spe = ivs.spe or ivs.speed or 0,
    spa = ivs.spa or ivs.spatk or ivs.spAttack or 0,
    spd = ivs.spd or ivs.spdef or ivs.spDefense or 0,
  }
end

local function fromGame3Ivs(ivs)
  ivs = ivs or {}
  return {
    hp = ivs.hp or 0,
    attack = ivs.atk or ivs.attack or 0,
    defense = ivs.def or ivs.defense or 0,
    speed = ivs.spe or ivs.speed or 0,
    spatk = ivs.spa or ivs.spatk or 0,
    spdef = ivs.spd or ivs.spdef or 0,
  }
end

local function toGame3Mon(mon)
  if type(mon) ~= "table" then return nil end
  local species = speciesNumber(mon.species)
  if not species or species == 0 then return nil end
  local status, sleepTurns = statusFromWord(mon.statusWord)
  if mon.status and not status then
    status, sleepTurns = mon.status, mon.sleepTurns
  end
  local moves = {}
  for i = 1, #(mon.moves or {}) do
    local m = mon.moves[i]
    if type(m) == "table" then
      local id = moveNumber(m.id)
      if id and id ~= 0 then
        moves[#moves + 1] = { id = id, pp = m.pp, ppUps = m.ppUps }
      end
    end
  end
  local evs = mon.evs or {}
  local contest = mon.contest or {}
  local otId = math.floor(tonumber(mon.otId) or 0) % 65536
  local secret = math.floor(tonumber(mon.secretId) or 0) % 65536
  return {
    species = species,
    level = mon.level,
    hp = mon.hp,
    exp = mon.exp,
    pid = mon.personality or mon.pid,
    ivs = toGame3Ivs(mon.ivs),
    status = status,
    sleepTurns = sleepTurns,
    moves = moves,
    otId = secret * 65536 + otId,
    otName = mon.gen3OtName or mon.otName,
    name = mon.nickname or mon.name,
    isEgg = mon.isEgg and true or nil,
    metLocation = mon.metLocation,
    metLevel = mon.metLevel,
    cool = contest.cool,
    beauty = contest.beauty,
    cute = contest.cute,
    smart = contest.smart,
    tough = contest.tough,
    sheen = contest.sheen,
    item = itemNumber(mon.item) or itemNumber(mon.heldItem),
    hpEv = evs.hp,
    atkEv = evs.attack or evs.atk,
    defEv = evs.defense or evs.def,
    speEv = evs.speed or evs.spe,
    spaEv = evs.spatk or evs.spa,
    spdEv = evs.spdef or evs.spd,
    friendship = mon.happiness or mon.friendship,
    pokerus = mon.gen3Pokerus or mon.pokerus,
    markings = mon.gen3Markings or mon.markings,
    altAbility = mon.altAbility,
    gen3Language = mon.gen3Language,
    gen3MetGame = mon.gen3MetGame,
    ball = itemNumber(mon.ball) or mon.ball,
  }
end

local function fromGame3Mon(mon)
  if type(mon) ~= "table" then return nil end
  local species = speciesNumber(mon.species)
  if not species or species == 0 then return nil end
  local otPacked = math.floor(tonumber(mon.otId) or 0)
  local moves = {}
  for i = 1, #(mon.moves or {}) do
    local m = mon.moves[i]
    if type(m) == "table" then
      local id = moveNumber(m.id)
      if id and id ~= 0 then
        moves[#moves + 1] = { id = id, pp = m.pp, ppUps = m.ppUps }
      end
    end
  end
  local contest
  if mon.cool or mon.beauty or mon.cute or mon.smart or mon.tough or mon.sheen then
    contest = {
      cool = mon.cool, beauty = mon.beauty, cute = mon.cute,
      smart = mon.smart, tough = mon.tough, sheen = mon.sheen,
    }
  elseif type(mon.contest) == "table" then
    contest = mon.contest
  end
  local statusWord = wordFromStatus(mon.status, mon.sleepTurns)
  return {
    species = species,
    personality = mon.pid or mon.personality,
    otId = otPacked % 65536,
    secretId = math.floor(otPacked / 65536) % 65536,
    exp = mon.exp,
    happiness = mon.friendship or mon.happiness,
    ivs = fromGame3Ivs(mon.ivs),
    evs = {
      hp = mon.hpEv or (mon.evs and mon.evs.hp),
      attack = mon.atkEv or (mon.evs and (mon.evs.attack or mon.evs.atk)),
      defense = mon.defEv or (mon.evs and (mon.evs.defense or mon.evs.def)),
      speed = mon.speEv or (mon.evs and (mon.evs.speed or mon.evs.spe)),
      spatk = mon.spaEv or (mon.evs and (mon.evs.spatk or mon.evs.spa)),
      spdef = mon.spdEv or (mon.evs and (mon.evs.spdef or mon.evs.spd)),
    },
    moves = moves,
    isEgg = mon.isEgg and true or nil,
    altAbility = mon.altAbility,
    metLocation = mon.metLocation,
    metLevel = mon.metLevel,
    item = itemNumber(mon.item),
    ball = itemNumber(mon.ball) or mon.ball,
    nickname = mon.name,
    gen3OtName = mon.otName,
    gen3Language = mon.gen3Language,
    gen3Markings = mon.markings,
    gen3Pokerus = mon.pokerus,
    gen3MetGame = mon.gen3MetGame,
    contest = contest,
    level = mon.level,
    hp = mon.hp,
    maxHp = mon.maxHp,
    statusWord = statusWord,
  }
end

local function flattenInventory(inventory)
  local bag = {}
  if type(inventory) ~= "table" then return bag end
  local keys = {}
  for id in pairs(inventory) do keys[#keys + 1] = id end
  table.sort(keys, function(a, b)
    return (itemNumber(a) or 0) < (itemNumber(b) or 0)
  end)
  for _, id in ipairs(keys) do
    local n = math.floor(tonumber(inventory[id]) or 0)
    local item = itemNumber(id)
    if item and item > 0 and n > 0 then
      bag[#bag + 1] = { id = item, count = n }
    end
  end
  return bag
end

local function inventoryFromBag(bag)
  local inventory, order = {}, {}
  if type(bag) ~= "table" then return inventory, order end
  for i = 1, #bag do
    local slot = bag[i]
    local id = slot and itemNumber(slot.id)
    local n = slot and math.floor(tonumber(slot.count) or 0)
    if id and id > 0 and n and n > 0 then
      inventory[id] = (inventory[id] or 0) + n
      order[#order + 1] = id
    end
  end
  return inventory, order
end

local function nationalOf(def, species)
  if type(def) == "table" then
    return tonumber(def.nationalDex) or tonumber(def.index) or species
  end
  return species
end

local function dexLists(decoded, data)
  local caught, seen = {}, {}
  local byNat = {}
  for id, def in pairs((data and data.pokemon) or {}) do
    if type(id) == "number" then
      local nat = nationalOf(def, id)
      if nat then byNat[nat] = id end
    end
  end
  local function collect(list, dest)
    if type(list) ~= "table" then return end
    for i = 1, #list do
      local nat = tonumber(list[i])
      local species = nat and (byNat[nat] or nat)
      if species then dest[#dest + 1] = species end
    end
    table.sort(dest)
  end
  collect(decoded.pokedexOwned, caught)
  collect(decoded.pokedexSeen, seen)
  return caught, seen
end

local function dexFromSnapshot(snap, data)
  local owned, seen = {}, {}
  local function push(list, dest)
    if type(list) ~= "table" then return end
    local seenSet = {}
    local function add(species)
      species = speciesNumber(species)
      if not species then return end
      local def = data and data.pokemon and data.pokemon[species]
      local nat = nationalOf(def, species)
      if nat and nat > 0 and not seenSet[nat] then
        seenSet[nat] = true
        dest[#dest + 1] = nat
      end
    end
    for i = 1, #list do add(list[i]) end
    for k, v in pairs(list) do
      if v == true then add(k) end
    end
    table.sort(dest)
  end
  push(snap.caught, owned)
  push(snap.seen, seen)
  return owned, seen
end

local function berryToGame3(trees)
  local out = {}
  if type(trees) ~= "table" then return out end
  for i, tree in pairs(trees) do
    if type(tree) == "table" then
      local watered = 0
      if type(tree.watered) == "table" then
        for w = 1, 4 do
          if tree.watered[w] then watered = watered + 2 ^ (w - 1) end
        end
      else
        watered = tonumber(tree.watered) or 0
      end
      out[#out + 1] = {
        id = (tonumber(i) or 0) + 1,
        berry = tree.berry or 0,
        stage = tree.stage or 0,
        yield = tree.yield or 0,
        watered = watered,
        minutes = tree.minutes or 0,
        regrowth = tree.regrowth or 0,
      }
    end
  end
  table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
  return out
end

local function berryFromGame3(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for i = 1, #list do
    local row = list[i]
    local id = row and tonumber(row.id)
    if id and id > 0 then
      local bits = math.floor(tonumber(row.watered) or 0)
      local watered = {}
      for w = 1, 4 do
        if math.floor(bits / 2 ^ (w - 1)) % 2 == 1 then watered[w] = true end
      end
      out[id - 1] = {
        berry = tonumber(row.berry) or 0,
        stage = tonumber(row.stage) or 0,
        yield = tonumber(row.yield) or 0,
        minutes = tonumber(row.minutes) or 0,
        regrowth = tonumber(row.regrowth) or 0,
        watered = watered,
      }
    end
  end
  return out
end

function Gen3RubyBridge.toSnapshot(decoded, version, data)
  decoded = decoded or {}
  local player = decoded.player or {}
  local flags = {}
  for k, v in pairs(decoded.flags or {}) do
    if v then
      local id = flagId(k)
      if id then flags[id] = true end
    end
  end
  local party = {}
  for i = 1, #(decoded.party or {}) do
    local mon = toGame3Mon(decoded.party[i])
    if mon then party[#party + 1] = mon end
  end
  local pc, boxNames, boxWallpapers = {}, {}, {}
  for b = 1, 14 do
    local box = decoded.boxes and decoded.boxes[b]
    local slots = {}
    if type(box) == "table" then
      boxNames[b] = box.name
      boxWallpapers[b] = box.wallpaper
      for slot = 1, 30 do
        local mon = toGame3Mon(box[slot])
        if mon then slots[slot] = mon end
      end
    end
    pc[b] = slots
  end
  local caught, seen = dexLists(decoded, data)
  local gender = 0
  if player.gender == "girl" or player.gender == 1 then gender = 1 end
  local publicId = math.floor(tonumber(player.id) or 0) % 65536
  local secretId = math.floor(tonumber(player.secretId) or 0) % 65536
  return {
    format = Gen3RubyBridge.SAVE_FORMAT,
    engine = Gen3RubyBridge.ENGINE,
    version = version,
    mapId = player.map,
    x = player.x or 0,
    y = player.y or 0,
    money = decoded.money or 0,
    coins = decoded.coins or 0,
    bag = flattenInventory(decoded.inventory),
    pcItems = flattenInventory(decoded.pcItems),
    party = party,
    pc = pc,
    pcCurrentBox = decoded.currentBox or 1,
    boxNames = boxNames,
    boxWallpapers = boxWallpapers,
    caught = caught,
    seen = seen,
    gender = gender,
    flags = flags,
    vars = decoded.gen3Vars or {},
    healMapId = player.healMap,
    healX = player.healX,
    healY = player.healY,
    playerName = player.name,
    playSeconds = math.floor(tonumber(decoded.playTime) or 0),
    trainerId = secretId * 65536 + publicId,
    registeredItem = decoded.registeredItem or 0,
    gameStats = decoded.gen3Stats,
    berryTrees = berryToGame3(decoded.gen3BerryTrees),
    sav1Weather = decoded.sav1Weather,
    weatherCycleStage = decoded.weatherCycleStage,
    mapLayoutId = decoded.mapLayoutId,
    rawImport = decoded.rawImport,
    meta = { format = Gen3RubyBridge.SAVE_FORMAT, mods = {} },
  }
end

function Gen3RubyBridge.fromSnapshot(snap, version, data)
  snap = snap or {}
  local inventory, bagOrder = inventoryFromBag(snap.bag)
  local pcItems, pcOrder = inventoryFromBag(snap.pcItems)
  local flags = {}
  for k, v in pairs(snap.flags or {}) do
    if v then
      local id = flagId(k)
      if id then flags[("FLAG_G3_%04X"):format(id)] = true end
    end
  end
  local party = {}
  for i = 1, #(snap.party or {}) do
    local mon = fromGame3Mon(snap.party[i])
    if mon then party[#party + 1] = mon end
  end
  local boxes = {}
  for b = 1, 14 do
    local src = snap.pc and snap.pc[b]
    local box = {
      name = snap.boxNames and snap.boxNames[b],
      wallpaper = snap.boxWallpapers and snap.boxWallpapers[b],
    }
    if type(src) == "table" then
      for slot = 1, 30 do
        box[slot] = fromGame3Mon(src[slot])
      end
    end
    boxes[b] = box
  end
  local owned, seen = dexFromSnapshot(snap, data)
  local gender = snap.gender
  if gender == 1 or gender == "girl" then
    gender = "girl"
  else
    gender = "boy"
  end
  local tid = math.floor(tonumber(snap.trainerId) or 0)
  return {
    player = {
      name = snap.playerName,
      id = tid % 65536,
      secretId = math.floor(tid / 65536) % 65536,
      gender = gender,
      map = snap.mapId,
      x = snap.x or 0,
      y = snap.y or 0,
      healMap = snap.healMapId,
      healX = snap.healX,
      healY = snap.healY,
    },
    money = snap.money or 0,
    coins = snap.coins or 0,
    playTime = snap.playSeconds or 0,
    inventory = inventory,
    bagOrder = bagOrder,
    pcItems = pcItems,
    pcOrder = pcOrder,
    party = party,
    boxes = boxes,
    currentBox = snap.pcCurrentBox or 1,
    flags = flags,
    gen3Vars = snap.vars,
    gen3Stats = snap.gameStats,
    gen3BerryTrees = berryFromGame3(snap.berryTrees),
    pokedexOwned = owned,
    pokedexSeen = seen,
    registeredItem = snap.registeredItem,
    sav1Weather = snap.sav1Weather,
    weatherCycleStage = snap.weatherCycleStage,
    mapLayoutId = snap.mapLayoutId,
    rawImport = snap.rawImport,
    version = version or snap.version,
  }
end

return Gen3RubyBridge
