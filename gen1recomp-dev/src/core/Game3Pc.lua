-- Pokémon Storage System (Bill's / Lanette's PC).
-- pokeruby src/pokemon_storage_system.c + _2.c + _3.c + _4.c, strings.c.
local Input = require("src.core.Input")

local Pc = {}

function Pc.attach(Game3)
  Game3.BOX_NAME_LEN = 8
  Game3.PC_ICON = 32
  Game3.PC_CELL = 24
  -- Sprite centres from PSS_SpawnMonIconSprite / sub_809AACC. Draw at centre-16.
  Game3.PC_BOX_CX = 0x64
  Game3.PC_BOX_CY = 0x2c
  Game3.PC_PARTY_LEAD_CX = 0x68
  Game3.PC_PARTY_LEAD_CY = 0x40
  Game3.PC_PARTY_REST_CX = 0x98
  Game3.PC_PARTY_REST_CY = 0x10
  Game3.PC_CLOSE_CX = 0x98
  Game3.PC_CLOSE_CY = 0x84
  Game3.PC_TITLE_CX = 0xa2
  Game3.PC_TITLE_CY = 0x0c
  Game3.PC_BTN_Y = 14
  Game3.PC_BTN_X = { 0x78, 0x78 + 0x58 }
  Game3.PC_MSG_LEFT = 10
  Game3.PC_MSG_TOP = 16
  Game3.PC_MSG_RIGHT = 29
  Game3.PC_MSG_BOTTOM = 19
  Game3.PC_ROOT_RIGHT = 13
  Game3.PC_ROOT_BOTTOM = 9

  Game3.PC_ROOT = {
    { "WITHDRAW POKéMON", "Move POKéMON stored in BOXES to\nyour party." },
    { "DEPOSIT POKéMON", "Store POKéMON in your party in BOXES." },
    { "MOVE POKéMON", "Organize the POKéMON in BOXES and\nin your party." },
    { "SEE YA!", "Return to the previous menu." },
  }
  Game3.PC_PSS = { "withdraw", "deposit", "move" }
  Game3.PC_WALLPAPERS = {
    { "FOREST", 0.22, 0.48, 0.24 },
    { "CITY", 0.42, 0.44, 0.50 },
    { "DESERT", 0.72, 0.58, 0.28 },
    { "SAVANNA", 0.55, 0.62, 0.30 },
    { "CRAG", 0.42, 0.34, 0.28 },
    { "VOLCANO", 0.58, 0.22, 0.18 },
    { "SNOW", 0.78, 0.84, 0.90 },
    { "CAVE", 0.30, 0.26, 0.34 },
    { "BEACH", 0.32, 0.62, 0.72 },
    { "SEAFLOOR", 0.16, 0.26, 0.52 },
    { "RIVER", 0.22, 0.48, 0.62 },
    { "SKY", 0.38, 0.60, 0.88 },
    { "POLKA-DOT", 0.72, 0.42, 0.58 },
    { "POKéCENTER", 0.72, 0.28, 0.38 },
    { "MACHINE", 0.38, 0.42, 0.48 },
    { "PLAIN", 0.52, 0.56, 0.40 },
  }
  Game3.PC_THEMES = {
    { "SCENERY 1", { 0, 1, 2, 3 } },
    { "SCENERY 2", { 4, 5, 6, 7 } },
    { "SCENERY 3", { 8, 9, 10, 11 } },
    { "ETCETERA", { 12, 13, 14, 15 } },
  }
  Game3.PC_MARKS = { "●", "■", "▲", "♥" }

  function Game3.boxOccupancy(box)
    local n = 0
    if type(box) ~= "table" then return 0 end
    for i = 1, Game3.BOX_SIZE do
      if box[i] then n = n + 1 end
    end
    return n
  end

  function Game3.boxFirstFree(box)
    for i = 1, Game3.BOX_SIZE do
      if not (box and box[i]) then return i end
    end
  end

  function Game3:defaultBoxName(index)
    return "BOX" .. tostring(index)
  end

  function Game3:ensurePc()
    if type(self.pc) ~= "table" then self.pc = {} end
    for b = 1, Game3.BOX_COUNT do
      if type(self.pc[b]) ~= "table" then self.pc[b] = {} end
    end
    local box = tonumber(self.pcCurrentBox) or 1
    if box < 1 then box = 1 elseif box > Game3.BOX_COUNT then box = Game3.BOX_COUNT end
    self.pcCurrentBox = box
    if type(self.boxNames) ~= "table" then self.boxNames = {} end
    if type(self.boxWallpapers) ~= "table" then self.boxWallpapers = {} end
    for b = 1, Game3.BOX_COUNT do
      if type(self.boxNames[b]) ~= "string" or self.boxNames[b] == "" then
        self.boxNames[b] = self:defaultBoxName(b)
      end
      if type(self.boxWallpapers[b]) ~= "number" then
        -- ResetPokemonStorageSystem: wallpaper[boxId] = boxId & 3
        self.boxWallpapers[b] = (b - 1) % 4
      end
    end
  end

  function Game3:pcFree()
    self:ensurePc()
    local n = 0
    for b = 1, Game3.BOX_COUNT do
      n = n + (Game3.BOX_SIZE - Game3.boxOccupancy(self.pc[b]))
    end
    return n
  end

  function Game3:hasMonSpace()
    return #(self.party or {}) < Game3.PARTY_MAX or self:pcFree() > 0
  end

  function Game3:sendToPc(mon)
    if not mon then return nil end
    self:ensurePc()
    self:stampPlayerOt(mon)
    local start = self.pcCurrentBox or 1
    local b = start
    repeat
      local box = self.pc[b]
      local slot = Game3.boxFirstFree(box)
      if slot then
        box[slot] = self:cloneMon(mon)
        if not mon.isEgg then self:markCaught(mon.species) end
        return b
      end
      b = b % Game3.BOX_COUNT + 1
    until b == start
  end

  function Game3:canDepositToPc(index)
    local party = self.party or {}
    if #party < 2 then return false, "That's your last POKéMON!" end
    local mon = party[index]
    if not mon then return false, "There's nothing here." end
    if self:canBattle(mon) and self:healthyCount(mon) < 1 then
      return false, "That's your last POKéMON!"
    end
    return true
  end

  function Game3:depositFromParty(index)
    local ok, msg = self:canDepositToPc(index)
    if not ok then return false, msg end
    local mon = self.party[index]
    local box = self:sendToPc(mon)
    if not box then return false, "The BOX is full." end
    table.remove(self.party, index)
    return true, (mon.name or "POKéMON") .. " was deposited."
  end

  function Game3:withdrawFromBox(boxIndex, slot)
    self:ensurePc()
    local box = self.pc[boxIndex]
    if type(box) ~= "table" then return false, "The BOX is empty." end
    local mon = box[slot]
    if not mon then return false, "There's nothing here." end
    if not self:addToParty(mon) then return false, "Your party's full!" end
    box[slot] = nil
    return true, ("Took %s."):format(mon.name)
  end

  function Game3:pcMonName(mon)
    if not mon then return "" end
    if mon.isEgg then return "EGG" end
    return mon.name or self:speciesName(mon.species) or "POKéMON"
  end

  function Game3:pcIconSpecies(mon)
    if not mon then return 0 end
    if mon.isEgg then return Game3.SPECIES_EGG end
    return mon.species or 0
  end

  function Game3:openPc()
    self:ensurePc()
    self.field = {
      kind = "pc",
      mode = "root",
      cursor = 0,
      box = self.pcCurrentBox or 1,
      note = nil,
    }
    return true
  end

  function Game3:tryPc()
    local map = self.map
    if not map then return false end
    local dx, dy = Game3.deltaFromFacing(self.facing)
    local x, y = self.playerX + dx, self.playerY + dy
    if Game3.isPc(self:behaviorAt(map, x, y)) then return self:openPc() end
    if Game3.isCounter(self:behaviorAt(map, x, y))
        and Game3.isPc(self:behaviorAt(map, x + dx, y + dy)) then
      return self:openPc()
    end
    return false
  end

  function Game3:enterPcStorage(pss)
    local f = self.field
    self:ensurePc()
    self.pcCurrentBox = self.pcCurrentBox or 1
    self.field = {
      kind = "pc",
      mode = "storage",
      pss = pss or "withdraw",
      area = pss == "deposit" and "party" or "box",
      cursor = 0,
      box = self.pcCurrentBox,
      held = nil,
      menu = nil,
      prompt = nil,
      msg = pss == "withdraw" and "Which one will you take?"
        or "What would you like to do?",
      quick = false,
      scripted = f and f.scripted or nil,
      returnTo = f and f.returnTo or nil,
      bedroom = f and f.bedroom or nil,
    }
    self:playSe(Game3.SE_PC_ON)
    self:pcRefreshMsg()
  end

  function Game3:closePcToRoot()
    local f = self.field
    self:playSe(Game3.SE_PC_OFF)
    self.pcCurrentBox = (f and f.box) or self.pcCurrentBox or 1
    self.field = {
      kind = "pc",
      mode = "root",
      cursor = (f and f.pss == "deposit" and 1)
        or (f and f.pss == "move" and 2) or 0,
      box = self.pcCurrentBox,
      scripted = f and f.scripted or nil,
      returnTo = f and f.returnTo or nil,
      bedroom = f and f.bedroom or nil,
    }
  end

  function Game3:closePc()
    local f = self.field
    if f and f.scripted then
      if f.returnTo == "player_pc" then
        self:openPlayerPc(f.bedroom)
        return
      end
      self.field = nil
      self:endScriptWait()
      return
    end
    self:closeField()
  end

  function Game3:pcBox()
    self:ensurePc()
    local f = self.field
    local id = (f and f.box) or self.pcCurrentBox or 1
    return self.pc[id], id
  end

  function Game3:pcShiftBox(delta)
    local f = self.field
    if not f then return end
    local n = Game3.BOX_COUNT
    f.box = ((f.box or 1) - 1 + delta) % n + 1
    self.pcCurrentBox = f.box
    self:playSe(Game3.SE_SELECT)
    self:pcRefreshMsg()
  end

  function Game3:pcMonAt(area, cursor)
    local f = self.field
    area = area or (f and f.area) or "box"
    cursor = cursor or (f and f.cursor) or 0
    if area == "party" then
      if cursor >= 6 then return nil end
      return (self.party or {})[cursor + 1]
    end
    if area == "box" then
      local box = self:pcBox()
      return box and box[cursor + 1]
    end
  end

  function Game3:pcRefreshMsg()
    local f = self.field
    if not f or f.mode ~= "storage" then return end
    if f.prompt or f.menu or f.list or f.wait then return end
    if f.held then
      f.msg = self:pcMonName(f.held) .. " is selected."
      return
    end
    local mon = self:pcMonAt()
    if mon then
      f.msg = self:pcMonName(mon) .. " is selected."
    elseif f.area == "title" then
      f.msg = "What would you like to do?"
    elseif f.area == "buttons" then
      f.msg = (f.cursor or 0) == 0 and "Jump to the party." or "Exit from the BOX."
    elseif f.area == "party" and (f.cursor or 0) >= 6 then
      f.msg = "Exit from the BOX."
    else
      f.msg = "What would you like to do?"
    end
  end

  local function menuItems(labels)
    local items = {}
    for i = 1, #labels do
      items[i] = { id = labels[i][1], text = labels[i][2] }
    end
    return items
  end

  function Game3:pcOpenMenu()
    local f = self.field
    local mon = self:pcMonAt()
    local pss = f.pss or "withdraw"
    local holding = f.held ~= nil
    local items
    if f.area == "title" then
      items = menuItems({
        { "jump", "JUMP" },
        { "wallpaper", "WALLPAPER" },
        { "name", "NAME" },
        { "cancel", "CANCEL" },
      })
    elseif holding then
      if mon then
        items = menuItems({ { "switch", "SWITCH" } })
      else
        items = menuItems({ { "place", "PLACE" } })
      end
      items[#items + 1] = { id = "summary", text = "SUMMARY" }
      if pss == "move" then
        if f.area == "party" then
          items[#items + 1] = { id = "deposit", text = "DEPOSIT" }
        else
          items[#items + 1] = { id = "withdraw", text = "WITHDRAW" }
        end
      end
      items[#items + 1] = { id = "release", text = "RELEASE" }
      items[#items + 1] = { id = "mark", text = "MARK" }
      items[#items + 1] = { id = "cancel", text = "CANCEL" }
    else
      if not mon then return false end
      if pss == "deposit" then
        items = menuItems({ { "deposit", "DEPOSIT" } })
      elseif pss == "withdraw" then
        items = menuItems({ { "withdraw", "WITHDRAW" } })
      else
        items = menuItems({ { "move", "MOVE" } })
      end
      items[#items + 1] = { id = "summary", text = "SUMMARY" }
      if pss == "move" then
        if f.area == "party" then
          items[#items + 1] = { id = "deposit", text = "DEPOSIT" }
        else
          items[#items + 1] = { id = "withdraw", text = "WITHDRAW" }
        end
      end
      items[#items + 1] = { id = "release", text = "RELEASE" }
      items[#items + 1] = { id = "mark", text = "MARK" }
      items[#items + 1] = { id = "cancel", text = "CANCEL" }
    end
    f.menu = { items = items, cursor = 0 }
    f.msg = "What would you like to do?"
    return true
  end

  function Game3:pcTakeFromCursor()
    local f = self.field
    local mon = self:pcMonAt()
    if not mon then return nil end
    if f.area == "party" then
      local ok, msg = self:canDepositToPc((f.cursor or 0) + 1)
      if not ok then
        self:playSe(Game3.SE_FAILURE)
        f.msg = msg
        f.wait = true
        return nil
      end
      local copy = self:cloneMon(mon)
      table.remove(self.party, (f.cursor or 0) + 1)
      return copy
    end
    local box, id = self:pcBox()
    local copy = self:cloneMon(mon)
    box[f.cursor + 1] = nil
    return copy, id
  end

  function Game3:pcPutHeld(destArea, destCursor)
    local f = self.field
    local held = f.held
    if not held then return false end
    if destArea == "party" then
      if destCursor >= 6 then return false end
      local party = self.party or {}
      if party[destCursor + 1] then return false end
      if #party >= Game3.PARTY_MAX then
        self:playSe(Game3.SE_FAILURE)
        f.msg = "Your party's full!"
        f.wait = true
        return false
      end
      table.insert(party, destCursor + 1, held)
      self.party = party
      f.held = nil
      return true
    end
    local box = self:pcBox()
    if box[destCursor + 1] then return false end
    box[destCursor + 1] = held
    f.held = nil
    return true
  end

  function Game3:pcSwitchHeld()
    local f = self.field
    local held = f.held
    local there = self:pcMonAt()
    if not held or not there then return false end
    if f.area == "party" then
      if f.cursor >= 6 then return false end
      if self:canBattle(there) and self:healthyCount(there) < 1
          and not self:canBattle(held) then
        self:playSe(Game3.SE_FAILURE)
        f.msg = "That's your last POKéMON!"
        f.wait = true
        return false
      end
      self.party[f.cursor + 1] = held
      f.held = self:cloneMon(there)
      return true
    end
    local box = self:pcBox()
    box[f.cursor + 1] = held
    f.held = self:cloneMon(there)
    return true
  end

  function Game3:pcDoMove()
    local f = self.field
    if f.held then
      if self:pcMonAt() then
        return self:pcSwitchHeld()
      end
      return self:pcPutHeld(f.area, f.cursor)
    end
    local taken = self:pcTakeFromCursor()
    if not taken then return false end
    f.held = taken
    return true
  end

  function Game3:pcDoWithdraw()
    local f = self.field
    if f.area ~= "box" then return false end
    if f.held then
      if #(self.party or {}) >= Game3.PARTY_MAX then
        self:playSe(Game3.SE_FAILURE)
        f.msg = "Your party's full!"
        f.wait = true
        return false
      end
      self.party[#self.party + 1] = f.held
      f.held = nil
      return true
    end
    local ok, msg = self:withdrawFromBox(f.box, (f.cursor or 0) + 1)
    if not ok then
      self:playSe(Game3.SE_FAILURE)
      f.msg = msg == "Your party's full!" and "Your party's full!" or msg
      f.wait = true
      return false
    end
    return true
  end

  function Game3:pcDoDeposit()
    local f = self.field
    local box, id = self:pcBox()
    local slot = Game3.boxFirstFree(box)
    if not slot then
      self:playSe(Game3.SE_FAILURE)
      f.msg = "The BOX is full."
      f.wait = true
      return false
    end
    if f.held then
      box[slot] = f.held
      f.held = nil
      f.msg = self:pcMonName(box[slot]) .. " was deposited."
      f.wait = true
      return true
    end
    if f.area ~= "party" then return false end
    local ok, msg = self:depositFromParty((f.cursor or 0) + 1)
    if not ok then
      self:playSe(Game3.SE_FAILURE)
      f.msg = msg
      f.wait = true
      return false
    end
    if f.cursor >= #(self.party or {}) and f.cursor > 0 then
      f.cursor = f.cursor - 1
    end
    f.msg = msg
    f.wait = true
    return true
  end

  function Game3:pcDoSummary()
    local f = self.field
    local mon = f.held or self:pcMonAt()
    if not mon then return false end
    local resume = {}
    for k, v in pairs(f) do resume[k] = v end
    resume.menu = nil
    resume.list = nil
    resume.prompt = nil
    self.field = {
      kind = "party_summary",
      cursor = 0,
      monIndex = 1,
      page = 0,
      mon = mon,
      fromPc = resume,
    }
    return true
  end

  function Game3:pcStartRelease()
    local f = self.field
    local mon = f.held or self:pcMonAt()
    if not mon then return false end
    if mon.isEgg then
      self:playSe(Game3.SE_FAILURE)
      f.msg = "You can't release an EGG."
      f.wait = true
      return false
    end
    if f.area == "party" and not f.held then
      local ok, msg = self:canDepositToPc((f.cursor or 0) + 1)
      if not ok then
        self:playSe(Game3.SE_FAILURE)
        f.msg = msg
        f.wait = true
        return false
      end
    end
    f.prompt = "release"
    f.yes = 0
    f.releaseName = self:pcMonName(mon)
    f.msg = "Release this POKéMON?"
    return true
  end

  function Game3:pcFinishRelease()
    local f = self.field
    if f.held then
      f.held = nil
    elseif f.area == "party" then
      table.remove(self.party, (f.cursor or 0) + 1)
    else
      local box = self:pcBox()
      box[(f.cursor or 0) + 1] = nil
    end
    f.prompt = "released"
    f.msg = f.releaseName .. " was released."
  end

  function Game3:pcDoMark()
    local f = self.field
    local mon = f.held or self:pcMonAt()
    if not mon then return false end
    f.list = { kind = "mark", cursor = 0, mon = mon }
    f.msg = "Mark your POKéMON."
    return true
  end

  function Game3:pcPickMenu(id)
    local f = self.field
    f.menu = nil
    if id == "cancel" or not id then
      self:pcRefreshMsg()
      return
    end
    self:playSe(Game3.SE_SELECT)
    if id == "move" or id == "place" or id == "switch" then
      self:pcDoMove()
    elseif id == "withdraw" then
      self:pcDoWithdraw()
    elseif id == "deposit" then
      self:pcDoDeposit()
    elseif id == "summary" then
      self:pcDoSummary()
      return
    elseif id == "release" then
      self:pcStartRelease()
    elseif id == "mark" then
      self:pcDoMark()
    elseif id == "jump" then
      f.list = { kind = "jump", cursor = (f.box or 1) - 1 }
      f.msg = "Jump to which BOX?"
    elseif id == "wallpaper" then
      f.list = { kind = "theme", cursor = 0 }
      f.msg = "Please pick a theme."
    elseif id == "name" then
      self:pcOpenBoxName()
      return
    end
    if self.field and self.field.kind == "pc" then self:pcRefreshMsg() end
  end

  function Game3:pcOpenBoxName()
    local f = self.field
    local resume = {}
    for k, v in pairs(f) do resume[k] = v end
    local name = (self.boxNames and self.boxNames[f.box]) or self:defaultBoxName(f.box)
    self.field = {
      kind = "nickname",
      nameBox = true,
      fromPc = resume,
      name = name:sub(1, Game3.BOX_NAME_LEN),
      keys = Game3.nameKeys(),
      cursor = 0,
      box = f.box,
    }
  end

  function Game3:pcCursorXY(area, cursor)
    area = area or "box"
    cursor = cursor or 0
    if area == "box" then
      local col = cursor % 6
      local row = math.floor(cursor / 6)
      return Game3.PC_BOX_CX + col * Game3.PC_CELL,
        Game3.PC_BOX_CY + row * Game3.PC_CELL
    end
    if area == "party" then
      if cursor <= 0 then
        return Game3.PC_PARTY_LEAD_CX, Game3.PC_PARTY_LEAD_CY
      end
      if cursor >= 6 then
        return Game3.PC_CLOSE_CX, Game3.PC_CLOSE_CY
      end
      return Game3.PC_PARTY_REST_CX, Game3.PC_PARTY_REST_CY + (cursor - 1) * Game3.PC_CELL
    end
    if area == "title" then
      return Game3.PC_TITLE_CX, Game3.PC_TITLE_CY
    end
    local x = Game3.PC_BTN_X[(cursor or 0) + 1] or Game3.PC_BTN_X[1]
    return x, Game3.PC_BTN_Y
  end

  function Game3:pcMoveBoxCursor(dir)
    local f = self.field
    local c = f.cursor or 0
    if dir == "up" then
      if c >= 6 then f.cursor = c - 6 else f.area = "title"; f.cursor = 0 end
    elseif dir == "down" then
      if c + 6 < 30 then
        f.cursor = c + 6
      else
        f.area = "buttons"
        f.cursor = math.floor((c - 24) / 3)
        if f.cursor < 0 then f.cursor = 0 elseif f.cursor > 1 then f.cursor = 1 end
      end
    elseif dir == "left" then
      if c % 6 == 0 then f.cursor = c + 5 else f.cursor = c - 1 end
    elseif dir == "right" then
      if (c + 1) % 6 == 0 then f.cursor = c - 5 else f.cursor = c + 1 end
    end
  end

  function Game3:pcMovePartyCursor(dir)
    local f = self.field
    local c = f.cursor or 0
    if dir == "up" then
      f.cursor = c <= 0 and 6 or (c - 1)
    elseif dir == "down" then
      f.cursor = c >= 6 and 0 or (c + 1)
    elseif dir == "left" then
      if c ~= 0 then
        f.partyReturn = c
        f.cursor = 0
      end
    elseif dir == "right" then
      if c == 0 then
        f.cursor = f.partyReturn or 1
        if f.cursor < 1 then f.cursor = 1 end
        if f.cursor > 6 then f.cursor = 6 end
      else
        f.area = "box"
        f.cursor = 0
      end
    end
  end

  function Game3:stepPcRoot(f)
    local n = #Game3.PC_ROOT
    if f.note then
      if Input:wasPressed("a") or Input:wasPressed("b") then
        f.note = nil
      elseif Input:wasPressed("up") then
        f.cursor = ((f.cursor or 0) - 1) % n
        if f.cursor < 0 then f.cursor = n - 1 end
        f.note = nil
      elseif Input:wasPressed("down") then
        f.cursor = ((f.cursor or 0) + 1) % n
        f.note = nil
      end
      return
    end
    if Input:wasPressed("b") then
      self:playSe(Game3.SE_SELECT)
      self:closePc()
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("a") then
      local c = f.cursor or 0
      self:playSe(Game3.SE_SELECT)
      if c == 0 then
        if #(self.party or {}) >= Game3.PARTY_MAX then
          f.note = "Your party is full!"
        else
          self:enterPcStorage("withdraw")
        end
      elseif c == 1 then
        if #(self.party or {}) <= 1 then
          f.note = "There is just one POKéMON with you."
        else
          self:enterPcStorage("deposit")
        end
      elseif c == 2 then
        self:enterPcStorage("move")
      else
        self:closePc()
      end
    end
  end

  function Game3:stepPcMenu(f)
    local items = f.menu.items or {}
    local n = #items
    if n < 1 then f.menu = nil return end
    if Input:wasPressed("up") then
      f.menu.cursor = ((f.menu.cursor or 0) - 1) % n
      if f.menu.cursor < 0 then f.menu.cursor = n - 1 end
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("down") then
      f.menu.cursor = ((f.menu.cursor or 0) + 1) % n
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("b") then
      self:playSe(Game3.SE_SELECT)
      f.menu = nil
      self:pcRefreshMsg()
    elseif Input:wasPressed("a") then
      local item = items[(f.menu.cursor or 0) + 1]
      self:pcPickMenu(item and item.id)
    end
  end

  function Game3:stepPcPrompt(f)
    if f.prompt == "released" then
      if Input:wasPressed("a") or Input:wasPressed("b") then
        f.prompt = "bye"
        f.msg = "Bye-bye, " .. (f.releaseName or "") .. "!"
      end
      return
    end
    if f.prompt == "bye" then
      if Input:wasPressed("a") or Input:wasPressed("b") then
        f.prompt = nil
        f.releaseName = nil
        self:pcRefreshMsg()
      end
      return
    end
    if Input:wasPressed("up") or Input:wasPressed("down") then
      f.yes = 1 - (f.yes or 0)
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("b") then
      self:playSe(Game3.SE_SELECT)
      if f.prompt == "continue" then
        self:closePcToRoot()
      else
        f.prompt = nil
        self:pcRefreshMsg()
      end
    elseif Input:wasPressed("a") then
      self:playSe(Game3.SE_SELECT)
      local yes = (f.yes or 0) == 0
      if f.prompt == "exit" then
        if yes then self:closePcToRoot() else f.prompt = nil; self:pcRefreshMsg() end
      elseif f.prompt == "continue" then
        if yes then f.prompt = nil; self:pcRefreshMsg() else self:closePcToRoot() end
      elseif f.prompt == "release" then
        if yes then self:pcFinishRelease() else f.prompt = nil; self:pcRefreshMsg() end
      end
    end
  end

  function Game3:stepPcList(f)
    local list = f.list
    local n
    if list.kind == "jump" then
      n = Game3.BOX_COUNT
    elseif list.kind == "theme" then
      n = #Game3.PC_THEMES
    elseif list.kind == "paper" then
      n = #(list.ids or {})
    elseif list.kind == "mark" then
      n = 5
    else
      n = 1
    end
    if Input:wasPressed("up") then
      list.cursor = ((list.cursor or 0) - 1) % n
      if list.cursor < 0 then list.cursor = n - 1 end
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("down") then
      list.cursor = ((list.cursor or 0) + 1) % n
      self:playSe(Game3.SE_SELECT)
    elseif Input:wasPressed("b") then
      self:playSe(Game3.SE_SELECT)
      if list.kind == "paper" then
        f.list = { kind = "theme", cursor = list.theme or 0 }
        f.msg = "Please pick a theme."
      else
        f.list = nil
        self:pcRefreshMsg()
      end
    elseif Input:wasPressed("a") then
      self:playSe(Game3.SE_SELECT)
      local c = list.cursor or 0
      if list.kind == "jump" then
        f.box = c + 1
        self.pcCurrentBox = f.box
        f.list = nil
        self:pcRefreshMsg()
      elseif list.kind == "theme" then
        local theme = Game3.PC_THEMES[c + 1]
        f.list = { kind = "paper", cursor = 0, ids = theme and theme[2], theme = c }
        f.msg = "Please pick out wallpaper."
      elseif list.kind == "paper" then
        local id = (list.ids or {})[c + 1]
        if id then
          self.boxWallpapers = self.boxWallpapers or {}
          self.boxWallpapers[f.box] = id
        end
        f.list = nil
        self:pcRefreshMsg()
      elseif list.kind == "mark" then
        if c >= 4 then
          f.list = nil
          self:pcRefreshMsg()
        else
            local mon = list.mon
          if mon then
            local flag = 2 ^ c
            local marks = tonumber(mon.markings) or 0
            if math.floor(marks / flag) % 2 == 1 then
              mon.markings = marks - flag
            else
              mon.markings = marks + flag
            end
          end
        end
      end
    end
  end

  function Game3:pcAskExit(kind)
    local f = self.field
    if f.held then
      self:playSe(Game3.SE_FAILURE)
      f.msg = "You're holding a POKéMON!"
      f.wait = true
      return
    end
    self:playSe(Game3.SE_SELECT)
    f.prompt = kind
    f.yes = 0
    if kind == "exit" then
      f.msg = "Exit from the BOX."
    else
      f.msg = "Continue BOX operations?"
    end
  end

  function Game3:pcPressA()
    local f = self.field
    if f.area == "title" then
      self:playSe(Game3.SE_SELECT)
      self:pcOpenMenu()
      return
    end
    if f.area == "buttons" then
      if (f.cursor or 0) == 0 then
        f.area = "party"
        f.cursor = 0
        self:playSe(Game3.SE_SELECT)
        self:pcRefreshMsg()
      else
        self:pcAskExit("exit")
      end
      return
    end
    if f.area == "party" and (f.cursor or 0) >= 6 then
      if f.pss == "deposit" then
        self:pcAskExit("exit")
      else
        f.area = "box"
        f.cursor = 0
        self:playSe(Game3.SE_SELECT)
        self:pcRefreshMsg()
      end
      return
    end
    local opened = self:pcOpenMenu()
    if not opened then return end
    self:playSe(Game3.SE_SELECT)
    if f.quick and f.menu and f.menu.items[1] then
      local first = f.menu.items[1].id
      if first == "move" or first == "place" or first == "switch"
          or first == "withdraw" or first == "deposit" then
        self:pcPickMenu(first)
      end
    end
  end

  function Game3:stepPcStorage(f)
    if f.wait then
      if Input:wasPressed("a") or Input:wasPressed("b")
          or Input:wasPressed("up") or Input:wasPressed("down")
          or Input:wasPressed("left") or Input:wasPressed("right") then
        f.wait = nil
        self:pcRefreshMsg()
      end
      return
    end
    if f.menu then
      self:stepPcMenu(f)
      return
    end
    if f.prompt then
      self:stepPcPrompt(f)
      return
    end
    if f.list then
      self:stepPcList(f)
      return
    end
    if Input:wasPressed("select") then
      f.quick = not f.quick
      self:playSe(Game3.SE_SELECT)
      return
    end
    if Input:wasPressed("start") then
      f.area = "title"
      f.cursor = 0
      self:playSe(Game3.SE_SELECT)
      self:pcRefreshMsg()
      return
    end
    if Input:wasPressed("b") then
      if f.area == "party" and f.pss ~= "deposit" then
        f.area = "box"
        f.cursor = 0
        self:playSe(Game3.SE_SELECT)
        self:pcRefreshMsg()
        return
      end
      self:pcAskExit("continue")
      return
    end
    if Input:wasPressed("a") then
      self:pcPressA()
      return
    end
    if f.area == "title" and Input:wasPressed("left") then
      self:pcShiftBox(-1)
      return
    end
    if f.area == "title" and Input:wasPressed("right") then
      self:pcShiftBox(1)
      return
    end
    local dir
    if Input:wasPressed("up") then dir = "up"
    elseif Input:wasPressed("down") then dir = "down"
    elseif Input:wasPressed("left") then dir = "left"
    elseif Input:wasPressed("right") then dir = "right"
    end
    if not dir then return end
    self:playSe(Game3.SE_SELECT)
    if f.area == "box" then
      self:pcMoveBoxCursor(dir)
    elseif f.area == "party" then
      self:pcMovePartyCursor(dir)
    elseif f.area == "title" then
      if dir == "down" then f.area = "box"; f.cursor = 2
      elseif dir == "up" then f.area = "buttons"; f.cursor = 0
      end
    elseif f.area == "buttons" then
      if dir == "up" then
        f.area = "box"
        f.cursor = (f.cursor or 0) == 0 and 24 or 29
      elseif dir == "down" then
        f.area = "title"
        f.cursor = 0
      elseif dir == "left" or dir == "right" then
        f.cursor = 1 - (f.cursor or 0)
      end
    end
    self:pcRefreshMsg()
  end

  function Game3:stepPc()
    local f = self.field
    if not f or f.kind ~= "pc" then return end
    if (f.mode or "root") == "root" then
      self:stepPcRoot(f)
    else
      self:stepPcStorage(f)
    end
  end

  function Game3:drawPcRoot(f)
    self:drawDialogueFrame()
    local desc = f.note or (Game3.PC_ROOT[(f.cursor or 0) + 1] or {})[2] or ""
    love.graphics.setColor(0.10, 0.10, 0.12, 1)
    local y = Game3.DLG_TEXT_ROW * Game3.MENU_TILE
    local x = Game3.DLG_TEXT_COL * Game3.MENU_TILE
    local line = 0
    for part in (desc .. "\n"):gmatch("(.-)\n") do
      if line < Game3.MSG_LINES then
        self:drawText(part, x, y + line * Game3.MSG_LINE_H)
      end
      line = line + 1
    end
    self:drawStdWindow(0, 0, Game3.PC_ROOT_RIGHT, Game3.PC_ROOT_BOTTOM)
    local tx = Game3.MENU_TILE
    for i = 0, #Game3.PC_ROOT - 1 do
      local row = 1 + i * 2
      local ty = row * Game3.MENU_TILE
      if i == (f.cursor or 0) then self:drawCursor(tx, ty) end
      love.graphics.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(Game3.PC_ROOT[i + 1][1], tx + Game3.MENU_TILE, ty)
    end
  end

  function Game3:drawPcIcon(mon, cx, cy)
    if not mon then return end
    local x, y = cx - 16, cy - 16
    if not self:drawMonIcon(self:pcIconSpecies(mon), x, y, self:monIconFrame(mon)) then
      love.graphics.setColor(0.85, 0.35, 0.28, 1)
      love.graphics.rectangle("fill", x + 4, y + 4, 24, 24)
    end
  end

  function Game3:drawPcStorage(f)
    local G = love.graphics
    local paper = (self.boxWallpapers or {})[f.box or 1] or 0
    local wp = Game3.PC_WALLPAPERS[paper + 1] or Game3.PC_WALLPAPERS[16]
    G.setColor(wp[2], wp[3], wp[4], 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    G.setColor(wp[2] * 0.7, wp[3] * 0.7, wp[4] * 0.7, 1)
    G.rectangle("fill", 80, 16, 152, 112)

    self:drawWindow(8, 8, 72, 24)
    G.setColor(0.10, 0.10, 0.12, 1)
    local boxName = (self.boxNames and self.boxNames[f.box]) or self:defaultBoxName(f.box)
    self:drawText(boxName, 14, 12)

    local box = self:pcBox()
    for i = 0, 29 do
      local col, row = i % 6, math.floor(i / 6)
      local cx = Game3.PC_BOX_CX + col * Game3.PC_CELL
      local cy = Game3.PC_BOX_CY + row * Game3.PC_CELL
      G.setColor(0, 0, 0, 0.18)
      G.rectangle("fill", cx - 12, cy - 12, 24, 24)
      self:drawPcIcon(box and box[i + 1], cx, cy)
    end

    local party = self.party or {}
    for i = 0, 5 do
      local cx, cy = self:pcCursorXY("party", i)
      G.setColor(0, 0, 0, 0.22)
      G.rectangle("fill", cx - 12, cy - 12, 24, 24)
      self:drawPcIcon(party[i + 1], cx, cy)
    end

    local closeX, closeY = self:pcCursorXY("party", 6)
    self:drawWindow(closeX - 28, closeY - 10, 56, 20)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("CLOSE", closeX - 20, closeY - 6)

    local partyBtnX, partyBtnY = self:pcCursorXY("buttons", 0)
    local closeBtnX = self:pcCursorXY("buttons", 1)
    self:drawWindow(partyBtnX - 28, partyBtnY - 8, 56, 18)
    self:drawWindow(closeBtnX - 28, partyBtnY - 8, 56, 18)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("PARTY", partyBtnX - 22, partyBtnY - 4)
    self:drawText("CLOSE", closeBtnX - 22, partyBtnY - 4)

    if f.held then
      local cx, cy = self:pcCursorXY(f.area, f.cursor)
      self:drawPcIcon(f.held, cx, cy - 8)
    end

    local cx, cy = self:pcCursorXY(f.area, f.cursor)
    self:drawCursor(cx - 22, cy - 8, { 0.95, 0.22, 0.18, 1 })

    self:drawStdWindow(Game3.PC_MSG_LEFT, Game3.PC_MSG_TOP,
      Game3.PC_MSG_RIGHT, Game3.PC_MSG_BOTTOM)
    G.setColor(0.10, 0.10, 0.12, 1)
    local mx = (Game3.PC_MSG_LEFT + 1) * Game3.MENU_TILE
    local my = (Game3.PC_MSG_TOP + 1) * Game3.MENU_TILE
    local wrapped = Game3.wrapDialogue(f.msg or "", 144, self:font3WidthTable())
    self:drawText(wrapped[1] or "", mx, my)
    if wrapped[2] then self:drawText(wrapped[2], mx, my + 12) end

    if f.menu then
      local labels = {}
      for i = 1, #f.menu.items do labels[i] = f.menu.items[i].text end
      self:drawMenuListWindow(18, 1, labels, f.menu.cursor)
    end
    if f.prompt == "exit" or f.prompt == "continue" or f.prompt == "release" then
      self:drawYesNoWindow(20, 8, f.yes or 0)
    end
    if f.list then
      local labels = {}
      if f.list.kind == "jump" then
        for i = 1, Game3.BOX_COUNT do
          labels[i] = (self.boxNames and self.boxNames[i]) or self:defaultBoxName(i)
        end
      elseif f.list.kind == "theme" then
        for i = 1, #Game3.PC_THEMES do labels[i] = Game3.PC_THEMES[i][1] end
      elseif f.list.kind == "paper" then
        for i = 1, #(f.list.ids or {}) do
          local wp = Game3.PC_WALLPAPERS[(f.list.ids[i] or 0) + 1]
          labels[i] = wp and wp[1] or "PLAIN"
        end
      elseif f.list.kind == "mark" then
        local bits = tonumber(f.list.mon and f.list.mon.markings) or 0
        for i = 1, 4 do
          local on = math.floor(bits / (2 ^ (i - 1))) % 2 == 1
          labels[i] = (on and "* " or "  ") .. Game3.PC_MARKS[i]
        end
        labels[5] = "CANCEL"
      end
      self:drawMenuListWindow(16, 1, labels, f.list.cursor)
    end
  end

  function Game3:drawPc(f)
    f = f or self.field
    if not f then return end
    if (f.mode or "root") == "root" then
      self:drawPcRoot(f)
    else
      self:drawPcStorage(f)
    end
  end
end

return Pc
