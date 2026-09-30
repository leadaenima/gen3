-- Project a Game3 `gen3-ruby-1` snapshot into the save editor's Gen 1-shaped
-- tables (player / inventory / pokedex / boxes / FLAG_G3_* flags), then
-- harvest those edits back onto the snapshot Game3:applySave already reads.
--
-- The snapshot's own keys stay on the table.  Play never sees the editor
-- aliases; harvest writes party, bag, flags, map and dex in the engine's
-- spellings before SaveIO.encode.

local Game3EditorSave = {}

Game3EditorSave.FORMAT = "gen3-ruby-1"

local IV_ALIAS = {
  attack = "atk", defense = "def", speed = "spe",
  spatk = "spa", spdef = "spd",
}
local EV_ALIAS = {
  hp = "hpEv", attack = "atkEv", defense = "defEv",
  speed = "speEv", spatk = "spaEv", spdef = "spdEv",
}

function Game3EditorSave.isSnapshot(save)
  if type(save) ~= "table" then return false end
  if save.engine == "gen3" then return true end
  local fmt = save.format
  return type(fmt) == "string" and fmt:find("^gen3%-ruby") ~= nil
end

local function flagKey(n)
  if type(n) == "string" then return n end
  if type(n) ~= "number" then return tostring(n) end
  return string.format("FLAG_G3_%04X", n)
end

local function flagNum(k)
  if type(k) == "number" then return k end
  if type(k) ~= "string" then return nil end
  local hex = k:match("^FLAG_G3_(%x+)$")
  if hex then return tonumber(hex, 16) end
  return tonumber(k)
end

local function listToSet(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for k, v in pairs(list) do
    if v == true then
      out[k] = true
    elseif type(v) == "number" then
      out[v] = true
    end
  end
  return out
end

local function setToList(set)
  local out = {}
  if type(set) ~= "table" then return out end
  for k, v in pairs(set) do
    if v then out[#out + 1] = k end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

local function bagToInventory(bag)
  local inv = {}
  if type(bag) ~= "table" then return inv end
  for i = 1, #bag do
    local slot = bag[i]
    local id = slot and slot.id
    local n = slot and tonumber(slot.count) or 0
    if id ~= nil and n > 0 then
      inv[id] = (inv[id] or 0) + n
    end
  end
  return inv
end

local function inventoryToBag(inv)
  local bag = {}
  if type(inv) ~= "table" then return bag end
  local ids = {}
  for id, n in pairs(inv) do
    if type(n) == "number" and n > 0 then
      if type(id) == "number" then
        ids[#ids + 1] = id
      elseif type(id) == "string" and not id:find("BADGE", 1, true)
          and not id:find("^FLAG_") then
        local num = tonumber(id:match("ITEM_(%d+)$") or id)
        if num then ids[#ids + 1] = num end
      end
    end
  end
  table.sort(ids, function(a, b)
    return (tonumber(a) or 0) < (tonumber(b) or 0)
  end)
  local seen = {}
  for _, id in ipairs(ids) do
    if not seen[id] then
      seen[id] = true
      local n = inv[id] or inv[tostring(id)]
      if type(n) == "number" and n > 0 then
        bag[#bag + 1] = { id = id, count = n }
      end
    end
  end
  return bag
end

local function pcItemsToMap(list)
  local map = {}
  if type(list) ~= "table" then return map end
  if list[1] and type(list[1]) == "table" then
    for i = 1, #list do
      local slot = list[i]
      local id = slot and slot.id
      local n = slot and tonumber(slot.count) or 0
      if id ~= nil and n > 0 then map[id] = (map[id] or 0) + n end
    end
    return map
  end
  return list
end

local function mapToPcItems(map)
  local out = {}
  if type(map) ~= "table" then return out end
  local ids = {}
  for id, n in pairs(map) do
    if type(n) == "number" and n > 0 then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  for _, id in ipairs(ids) do
    out[#out + 1] = { id = id, count = map[id] }
  end
  return out
end

local function projectMon(mon)
  if type(mon) ~= "table" then return mon end
  local ivs = mon.ivs
  if type(ivs) == "table" then
    ivs.attack = ivs.attack or ivs.atk
    ivs.defense = ivs.defense or ivs.def
    ivs.speed = ivs.speed or ivs.spe
    ivs.spatk = ivs.spatk or ivs.spa
    ivs.spdef = ivs.spdef or ivs.spd
  else
    mon.ivs = { hp = 0, attack = 0, defense = 0, speed = 0, spatk = 0, spdef = 0,
                atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  end
  if type(mon.evs) ~= "table" then
    mon.evs = {
      hp = mon.hpEv or 0, attack = mon.atkEv or 0, defense = mon.defEv or 0,
      speed = mon.speEv or 0, spatk = mon.spaEv or 0, spdef = mon.spdEv or 0,
    }
  end
  if mon.otName and not mon.ot then mon.ot = mon.otName end
  if mon.name and not mon.nickname then mon.nickname = mon.name end
  return mon
end

local function harvestMon(mon)
  if type(mon) ~= "table" then return mon end
  local ivs = mon.ivs
  if type(ivs) == "table" then
    for editor, gba in pairs(IV_ALIAS) do
      local v = ivs[editor] or ivs[gba] or 0
      ivs[gba] = v
      ivs[editor] = v
    end
    ivs.hp = ivs.hp or 0
  end
  if type(mon.evs) == "table" then
    for editor, field in pairs(EV_ALIAS) do
      local v = mon.evs[editor] or mon[field] or 0
      mon[field] = v
    end
  end
  if type(mon.ot) == "string" and mon.ot ~= "" then
    mon.otName = mon.ot
  end
  if type(mon.nickname) == "string" and mon.nickname ~= "" then
    mon.name = mon.nickname
  end
  return mon
end

function Game3EditorSave.project(save)
  if not Game3EditorSave.isSnapshot(save) then return save end
  save.player = save.player or {}
  local player = save.player
  if player.name == nil then player.name = save.playerName or "BRENDAN" end
  if player.map == nil then player.map = save.mapId end
  if player.x == nil then player.x = save.x or 0 end
  if player.y == nil then player.y = save.y or 0 end
  if player.id == nil then player.id = save.trainerId end
  if player.gender == nil then player.gender = save.gender end
  if player.money == nil then player.money = save.money or 0 end
  save.money = save.money or player.money or 0
  save.playerName = save.playerName or player.name

  if type(save.inventory) ~= "table" or not next(save.inventory) then
    save.inventory = bagToInventory(save.bag)
  end
  save.pcItems = pcItemsToMap(save.pcItems)

  local projectedFlags = {}
  for k, v in pairs(save.flags or {}) do
    if v then
      local n = flagNum(k)
      if n then
        projectedFlags[flagKey(n)] = true
      elseif type(k) == "string" then
        projectedFlags[k] = true
      end
    end
  end
  save.flags = projectedFlags

  if type(save.pokedex) ~= "table" then
    save.pokedex = {
      seen = listToSet(save.seen),
      owned = listToSet(save.caught),
    }
  else
    save.pokedex.seen = save.pokedex.seen or listToSet(save.seen)
    save.pokedex.owned = save.pokedex.owned or listToSet(save.caught)
  end

  if type(save.boxes) ~= "table" then
    save.boxes = {}
    local pc = save.pc or {}
    for b = 1, 14 do
      save.boxes[b] = pc[b] or {}
    end
    save.currentBox = save.pcCurrentBox or 1
  end

  if save.lastHeal == nil and save.healMapId then
    save.lastHeal = { map = save.healMapId, x = save.healX or 0, y = save.healY or 0 }
  end

  for _, mon in ipairs(save.party or {}) do projectMon(mon) end
  for _, box in ipairs(save.boxes or {}) do
    if type(box) == "table" then
      for i = 1, 30 do
        if box[i] then projectMon(box[i]) end
      end
    end
  end
  save.meta = save.meta or { mods = {} }
  return save
end

function Game3EditorSave.harvest(save)
  if not Game3EditorSave.isSnapshot(save) then return save end
  local player = save.player or {}
  if type(player.name) == "string" and player.name ~= "" then
    save.playerName = player.name
  end
  if player.map ~= nil then save.mapId = player.map end
  if player.x ~= nil then save.x = player.x end
  if player.y ~= nil then save.y = player.y end
  if player.id ~= nil then save.trainerId = player.id end
  if player.gender ~= nil then save.gender = player.gender end
  if save.money == nil and player.money ~= nil then save.money = player.money end

  save.bag = inventoryToBag(save.inventory)
  save.pcItems = mapToPcItems(save.pcItems)

  local numeric = {}
  for k, v in pairs(save.flags or {}) do
    if v then
      local n = flagNum(k)
      if n then numeric[n] = true end
    end
  end
  save.flags = numeric

  local dex = save.pokedex or {}
  save.seen = setToList(dex.seen)
  save.caught = setToList(dex.owned)

  save.pc = save.pc or {}
  local boxes = save.boxes or {}
  for b = 1, 14 do
    local src = boxes[b] or save.pc[b] or {}
    local box = {}
    for i = 1, 30 do
      if src[i] then box[i] = harvestMon(src[i]) end
    end
    save.pc[b] = box
  end
  save.pcCurrentBox = save.currentBox or save.pcCurrentBox or 1

  if save.lastHeal and save.lastHeal.map then
    save.healMapId = save.lastHeal.map
    save.healX = save.lastHeal.x
    save.healY = save.lastHeal.y
  end

  for _, mon in ipairs(save.party or {}) do harvestMon(mon) end

  save.format = save.format or Game3EditorSave.FORMAT
  save.engine = "gen3"
  return save
end

function Game3EditorSave.newStub(version)
  return Game3EditorSave.project({
    format = Game3EditorSave.FORMAT,
    engine = "gen3",
    version = version or "ruby",
    mapId = "g0_9",
    x = 10,
    y = 8,
    money = 3000,
    coins = 0,
    playerName = "BRENDAN",
    gender = 0,
    party = {},
    bag = {},
    flags = {},
    vars = {},
    pc = {},
    pcItems = {},
    caught = {},
    seen = {},
    playSeconds = 0,
  })
end

return Game3EditorSave
