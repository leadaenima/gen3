-- Player's PC: ITEM STORAGE + MAILBOX (player_pc.c).
-- Pokémon Storage System (Lanette's / Someone's) lives in Game3Pc.lua.
local Input = require("src.core.Input")

local PlayerPc = {}

function PlayerPc.attach(Game3)
  Game3.PC_ITEMS_COUNT = 50
  Game3.PC_ITEM_STACK_MAX = 999
  Game3.PC_MAIL_COUNT = 10 -- gSaveBlock1.mail[6..15]
  Game3.TEXT_PC_NO_ITEMS = "There are no items."
  Game3.TEXT_PC_NO_MAIL = "There's no MAIL here."
  Game3.TEXT_PC_NO_MORE_ROOM = "There is no more\nroom in the BAG."
  Game3.TEXT_PC_BAG_FULL = "The BAG is full."
  Game3.TEXT_PC_TOO_IMPORTANT = "That's too important\nto toss!"
  Game3.TEXT_PC_MAILBOX_FULL = "Your PC's MAILBOX is full."
  Game3.TEXT_PC_WHAT_WILL_YOU_DO = "What would you like to do?"
  Game3.ITEM_STORAGE_MENU = {
    { "WITHDRAW ITEM", "Take out items from the PC." },
    { "DEPOSIT ITEM", "Store items in the PC." },
    { "TOSS ITEM", "Throw away items stored in the PC." },
    { "EXIT", "Return to the previous menu." },
  }

  function Game3:ensurePcItems()
    if type(self.pcItems) ~= "table" then self.pcItems = {} end
    return self.pcItems
  end

  function Game3:ensurePcMail()
    if type(self.pcMail) ~= "table" then self.pcMail = {} end
    return self.pcMail
  end

  function Game3:newGameInitPcItems()
    self.pcItems = {}
    self:addPcItem(Game3.ITEM_POTION, 1)
  end

  function Game3:countUsedPcItemSlots()
    local n = 0
    local items = self:ensurePcItems()
    for i = 1, #items do
      local slot = items[i]
      if slot and (tonumber(slot.id) or 0) ~= 0 then n = n + 1 end
    end
    return n
  end

  function Game3:compactPcItems()
    local items = self:ensurePcItems()
    local packed = {}
    for i = 1, #items do
      local slot = items[i]
      if slot and (tonumber(slot.id) or 0) ~= 0 and (tonumber(slot.count) or 0) > 0 then
        packed[#packed + 1] = {
          id = tonumber(slot.id) or 0,
          count = math.floor(tonumber(slot.count) or 0),
        }
      end
    end
    self.pcItems = packed
    return packed
  end

  function Game3:addPcItem(itemId, count)
    itemId = tonumber(itemId) or 0
    count = math.floor(tonumber(count) or 0)
    if itemId < 1 or count < 1 then return false end
    local items = self:ensurePcItems()
    local max = Game3.PC_ITEM_STACK_MAX
    for i = 1, #items do
      local slot = items[i]
      if slot and slot.id == itemId then
        local room = max - (slot.count or 0)
        if room >= count then
          slot.count = (slot.count or 0) + count
          return true
        end
        if room > 0 then
          slot.count = max
          count = count - room
        end
      end
    end
    while count > 0 do
      if #items >= Game3.PC_ITEMS_COUNT then return false end
      local put = count
      if put > max then put = max end
      items[#items + 1] = { id = itemId, count = put }
      count = count - put
    end
    return true
  end

  function Game3:removePcItemAt(index, count)
    index = math.floor(tonumber(index) or 0)
    count = math.floor(tonumber(count) or 0)
    local items = self:ensurePcItems()
    local slot = items[index]
    if not slot or count < 1 then return false end
    local have = tonumber(slot.count) or 0
    if have < count then return false end
    slot.count = have - count
    if slot.count <= 0 then
      slot.id = 0
      slot.count = 0
      self:compactPcItems()
    end
    return true
  end

  function Game3:pcItemLabel(slot)
    if not slot then return "" end
    local name = self:itemName(slot.id)
    local pocket = self:itemPocket(slot.id)
    if pocket == Game3.POCKET_KEY then return name end
    if Game3.isTmHm and Game3.isTmHm(slot.id) and Game3.tmhmIndex
        and Game3.tmhmIndex(slot.id) and Game3.tmhmIndex(slot.id) >= 50 then
      return name
    end
    return ("%s x%d"):format(name, slot.count or 0)
  end

  function Game3:pcItemIsImportant(id)
    id = tonumber(id) or 0
    if id < 1 then return true end
    local pocket = self:itemPocket(id)
    return pocket == Game3.POCKET_KEY
  end

  function Game3:pcMailCount()
    local n = 0
    local mail = self:ensurePcMail()
    for i = 1, #mail do
      local m = mail[i]
      if m and (tonumber(m.itemId) or 0) ~= 0
          and (tonumber(m.itemId) or 0) ~= Game3.ITEM_NONE then
        n = n + 1
      end
    end
    return n
  end

  function Game3:compactPcMail()
    local mail = self:ensurePcMail()
    local packed = {}
    for i = 1, #mail do
      local m = mail[i]
      if m and (tonumber(m.itemId) or 0) ~= 0
          and (tonumber(m.itemId) or 0) ~= Game3.ITEM_NONE then
        packed[#packed + 1] = {
          itemId = tonumber(m.itemId) or 0,
          otName = m.otName or "",
          nick = m.nick or "",
        }
      end
    end
    self.pcMail = packed
    return packed
  end

  function Game3:addPcMail(mail)
    if type(mail) ~= "table" then return false end
    local itemId = tonumber(mail.itemId) or 0
    if itemId == 0 or itemId == Game3.ITEM_NONE then return false end
    if self:pcMailCount() >= Game3.PC_MAIL_COUNT then return false end
    local list = self:ensurePcMail()
    list[#list + 1] = {
      itemId = itemId,
      otName = mail.otName or self:playerName(),
      nick = mail.nick or "",
    }
    return true
  end

  function Game3:removePcMailAt(index)
    index = math.floor(tonumber(index) or 0)
    local list = self:ensurePcMail()
    if index < 1 or index > #list then return nil end
    local mail = list[index]
    table.remove(list, index)
    return mail
  end

  function Game3:pcOwnerTitle()
    if self.flags and self.flags[Game3.FLAG_SYS_PC_LANETTE] then
      return "LANETTE'S PC"
    end
    return "SOMEONE'S PC"
  end

  function Game3:openItemStorage()
    local f = self.field
    local bedroom = f and f.bedroom
    local scripted = f and f.scripted
    self.field = {
      kind = "item_storage",
      labels = {
        Game3.ITEM_STORAGE_MENU[1][1],
        Game3.ITEM_STORAGE_MENU[2][1],
        Game3.ITEM_STORAGE_MENU[3][1],
        Game3.ITEM_STORAGE_MENU[4][1],
      },
      descs = {
        Game3.ITEM_STORAGE_MENU[1][2],
        Game3.ITEM_STORAGE_MENU[2][2],
        Game3.ITEM_STORAGE_MENU[3][2],
        Game3.ITEM_STORAGE_MENU[4][2],
      },
      cursor = 0,
      bedroom = bedroom,
      scripted = scripted,
      note = Game3.ITEM_STORAGE_MENU[1][2],
    }
  end

  function Game3:returnToPlayerPc()
    local f = self.field
    self:openPlayerPc(f and f.bedroom)
  end

  function Game3:returnToItemStorage(note)
    self:openItemStorage()
    if note then self.field.note = note end
  end

  function Game3:pickItemStorage(index)
    index = math.floor(tonumber(index) or 0)
    if index >= 3 then
      self:returnToPlayerPc()
      return
    end
    if index == 0 then
      self:openPcItemList("withdraw")
    elseif index == 1 then
      self:openPcDepositList()
    elseif index == 2 then
      self:openPcItemList("toss")
    end
  end

  function Game3:openPcItemList(mode)
    self:compactPcItems()
    local items = self:ensurePcItems()
    if #items < 1 then
      self:returnToItemStorage(Game3.TEXT_PC_NO_ITEMS)
      return
    end
    local labels, ids = {}, {}
    for i = 1, #items do
      labels[#labels + 1] = self:pcItemLabel(items[i])
      ids[#ids + 1] = i
    end
    labels[#labels + 1] = "CANCEL"
    local f = self.field
    self.field = {
      kind = "pc_item_list",
      mode = mode or "withdraw",
      labels = labels,
      ids = ids,
      cursor = 0,
      bedroom = f and f.bedroom,
      scripted = f and f.scripted,
    }
  end

  function Game3:openPcDepositList()
    local bag = self.bag or {}
    local labels, slots = {}, {}
    for i = 1, #bag do
      local slot = bag[i]
      if slot and (tonumber(slot.id) or 0) > 0 and (tonumber(slot.count) or 0) > 0 then
        labels[#labels + 1] = self:pcItemLabel(slot)
        slots[#slots + 1] = { id = slot.id, count = slot.count, bagIndex = i }
      end
    end
    if #slots < 1 then
      self:returnToItemStorage(Game3.TEXT_PC_NO_ITEMS)
      return
    end
    labels[#labels + 1] = "CANCEL"
    local f = self.field
    self.field = {
      kind = "pc_deposit_list",
      labels = labels,
      slots = slots,
      cursor = 0,
      bedroom = f and f.bedroom,
      scripted = f and f.scripted,
    }
  end

  function Game3:openPcQty(opts)
    opts = opts or {}
    local f = self.field
    self.field = {
      kind = "pc_qty",
      mode = opts.mode,
      itemId = opts.itemId,
      max = opts.max or 1,
      qty = opts.max or 1,
      pcIndex = opts.pcIndex,
      bedroom = f and f.bedroom,
      scripted = f and f.scripted,
      prompt = opts.prompt or "How many?",
    }
  end

  function Game3:finishPcWithdraw(pcIndex, qty)
    local items = self:ensurePcItems()
    local slot = items[pcIndex]
    if not slot then
      self:returnToItemStorage()
      return
    end
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 or qty > (slot.count or 0) then
      self:openPcItemList("withdraw")
      return
    end
    local id = slot.id
    if not self:addItem(id, qty) then
      self:returnToItemStorage(Game3.TEXT_PC_NO_MORE_ROOM)
      return
    end
    self:removePcItemAt(pcIndex, qty)
    local name = self:itemName(id)
    self:returnToItemStorage(("Withdrew %d\n%s(s)."):format(qty, name))
  end

  function Game3:finishPcDeposit(itemId, qty)
    itemId = tonumber(itemId) or 0
    qty = math.floor(tonumber(qty) or 0)
    if itemId < 1 or qty < 1 then
      self:returnToItemStorage()
      return
    end
    if self:itemCount(itemId) < qty then
      self:openPcDepositList()
      return
    end
    if not self:addPcItem(itemId, qty) then
      self:returnToItemStorage("There's no more room in the PC.")
      return
    end
    self:takeItem(itemId, qty)
    local name = self:itemName(itemId)
    self:returnToItemStorage(("Deposited %d\n%s(s)."):format(qty, name))
  end

  function Game3:finishPcToss(pcIndex, qty)
    local items = self:ensurePcItems()
    local slot = items[pcIndex]
    if not slot then
      self:returnToItemStorage()
      return
    end
    if self:pcItemIsImportant(slot.id) then
      self:returnToItemStorage(Game3.TEXT_PC_TOO_IMPORTANT)
      return
    end
    qty = math.floor(tonumber(qty) or 0)
    if qty < 1 or qty > (slot.count or 0) then
      self:openPcItemList("toss")
      return
    end
    local name = self:itemName(slot.id)
    self:removePcItemAt(pcIndex, qty)
    self:returnToItemStorage(("Threw away %d\n%s(s)."):format(qty, name))
  end

  function Game3:pickPcItemList(index)
    local f = self.field
    local ids = (f and f.ids) or {}
    index = math.floor(tonumber(index) or 0)
    if index < 0 or index >= #ids then
      self:returnToItemStorage()
      return
    end
    local pcIndex = ids[index + 1]
    local slot = self.pcItems and self.pcItems[pcIndex]
    if not slot then
      self:returnToItemStorage()
      return
    end
    local mode = f.mode or "withdraw"
    if mode == "toss" and self:pcItemIsImportant(slot.id) then
      self:returnToItemStorage(Game3.TEXT_PC_TOO_IMPORTANT)
      return
    end
    local max = slot.count or 1
    if max <= 1 then
      if mode == "toss" then
        self:finishPcToss(pcIndex, 1)
      else
        self:finishPcWithdraw(pcIndex, 1)
      end
      return
    end
    self:openPcQty({
      mode = mode,
      itemId = slot.id,
      max = max,
      pcIndex = pcIndex,
      prompt = mode == "toss"
        and "How many do you\nwant to toss?"
        or "How many do you\nwant to withdraw?",
    })
  end

  function Game3:pickPcDepositList(index)
    local f = self.field
    local slots = (f and f.slots) or {}
    index = math.floor(tonumber(index) or 0)
    if index < 0 or index >= #slots then
      self:returnToItemStorage()
      return
    end
    local slot = slots[index + 1]
    local max = slot.count or 1
    if max <= 1 then
      self:finishPcDeposit(slot.id, 1)
      return
    end
    self:openPcQty({
      mode = "deposit",
      itemId = slot.id,
      max = max,
      prompt = "How many do you\nwant to deposit?",
    })
  end

  function Game3:confirmPcQty()
    local f = self.field
    if not f then return end
    local qty = f.qty or 1
    if f.mode == "deposit" then
      self:finishPcDeposit(f.itemId, qty)
    elseif f.mode == "toss" then
      self:finishPcToss(f.pcIndex, qty)
    else
      self:finishPcWithdraw(f.pcIndex, qty)
    end
  end

  function Game3:openMailbox()
    self:compactPcMail()
    if self:pcMailCount() < 1 then
      if self.field and self.field.kind == "player_pc" then
        self.field.note = Game3.TEXT_PC_NO_MAIL
      else
        self:returnToPlayerPc()
        if self.field then
          self.field.note = Game3.TEXT_PC_NO_MAIL
          self.field.cursor = 1
        end
      end
      return
    end
    local mail = self:ensurePcMail()
    local labels, ids = {}, {}
    for i = 1, #mail do
      local m = mail[i]
      local who = (m.otName and m.otName ~= "" and m.otName)
        or (m.nick and m.nick ~= "" and m.nick)
        or self:itemName(m.itemId)
      labels[#labels + 1] = who
      ids[#ids + 1] = i
    end
    labels[#labels + 1] = "CANCEL"
    local f = self.field
    self.field = {
      kind = "pc_mailbox",
      labels = labels,
      ids = ids,
      cursor = 0,
      bedroom = f and f.bedroom,
      scripted = f and f.scripted,
    }
  end

  function Game3:openMailboxActions(mailIndex)
    local mail = self.pcMail and self.pcMail[mailIndex]
    if not mail then
      self:returnToPlayerPc()
      return
    end
    local who = mail.otName or mail.nick or "MAIL"
    local f = self.field
    self.field = {
      kind = "pc_mail_actions",
      labels = { "READ", "MOVE TO BAG", "GIVE", "CANCEL" },
      cursor = 0,
      mailIndex = mailIndex,
      bedroom = f and f.bedroom,
      scripted = f and f.scripted,
      note = ("What would you like to do with\n%s's MAIL?"):format(who),
    }
  end

  function Game3:pickMailbox(index)
    local f = self.field
    local ids = (f and f.ids) or {}
    index = math.floor(tonumber(index) or 0)
    if index < 0 or index >= #ids then
      self:returnToPlayerPc()
      return
    end
    self:openMailboxActions(ids[index + 1])
  end

  function Game3:pickMailboxAction(index)
    local f = self.field
    local mailIndex = f and f.mailIndex
    index = math.floor(tonumber(index) or 0)
    if index >= 3 or not mailIndex then
      self:openMailbox()
      return
    end
    local mail = self.pcMail and self.pcMail[mailIndex]
    if not mail then
      self:returnToPlayerPc()
      return
    end
    if index == 0 then
      self.field = {
        kind = "mail_read",
        item = mail.itemId,
        thenMailbox = true,
        mailIndex = mailIndex,
        bedroom = f.bedroom,
        scripted = f.scripted,
      }
      return
    end
    if index == 1 then
      if not self:addItem(mail.itemId, 1) then
        self:returnToPlayerPc()
        if self.field then
          self.field.note = Game3.TEXT_PC_BAG_FULL
          self.field.cursor = 1
        end
        return
      end
      self:removePcMailAt(mailIndex)
      self:returnToPlayerPc()
      if self.field then
        self.field.note = "The MAIL was returned to the BAG\nwith its message erased."
        self.field.cursor = 1
      end
      return
    end
    if index == 2 then
      local party = self.party or {}
      if #party < 1 then
        self.field = {
          kind = "pc_mail_actions",
          labels = { "READ", "MOVE TO BAG", "GIVE", "CANCEL" },
          cursor = 0,
          mailIndex = mailIndex,
          bedroom = f.bedroom,
          scripted = f.scripted,
          note = "There is no\nPOKéMON.",
        }
        return
      end
      self.field = {
        kind = "pc_mail_give",
        cursor = 0,
        mailIndex = mailIndex,
        bedroom = f.bedroom,
        scripted = f.scripted,
      }
    end
  end

  function Game3:givePcMailToParty(partyIndex)
    local f = self.field
    local mailIndex = f and f.mailIndex
    local mail = mailIndex and self.pcMail and self.pcMail[mailIndex]
    local mon = self.party and self.party[partyIndex]
    if not (mail and mon) or mon.isEgg then
      self:openMailboxActions(mailIndex or 1)
      return
    end
    local held = tonumber(mon.item) or 0
    if held ~= 0 and held ~= Game3.ITEM_NONE then
      self.field = {
        kind = "pc_mail_actions",
        labels = { "READ", "MOVE TO BAG", "GIVE", "CANCEL" },
        cursor = 2,
        mailIndex = mailIndex,
        bedroom = f.bedroom,
        scripted = f.scripted,
        note = "This POKéMON is holding\nan item already.",
      }
      return
    end
    self:giveMailToMon(mon, mail)
    self:removePcMailAt(mailIndex)
    self:returnToPlayerPc()
    if self.field then
      self.field.note = "MAIL was transferred from\nthe MAILBOX."
      self.field.cursor = 1
    end
  end

  function Game3:stepPlayerPcMenus()
    local f = self.field
    if not f then return false end
    local kind = f.kind
    if kind == "item_storage" or kind == "pc_item_list"
        or kind == "pc_deposit_list" or kind == "pc_mailbox"
        or kind == "pc_mail_actions" then
      local labels = f.labels or { "CANCEL" }
      local n = #labels
      if n < 1 then n = 1 end
      local descNote = kind == "item_storage" and f.descs
        and f.descs[(f.cursor or 0) + 1] or nil
      local statusNote = f.note and f.note ~= descNote
      if Input:wasPressed("b") then
        if statusNote and kind == "item_storage" then
          f.note = descNote
          return true
        end
        if kind == "item_storage" then
          self:returnToPlayerPc()
        elseif kind == "pc_mail_actions" then
          self:openMailbox()
        elseif kind == "pc_mailbox" then
          self:returnToPlayerPc()
        else
          self:returnToItemStorage()
        end
        return true
      end
      if Input:wasPressed("down") then
        if statusNote and kind == "item_storage" then
          f.note = descNote
          return true
        end
        f.cursor = ((f.cursor or 0) + 1) % n
        if kind == "item_storage" and f.descs then
          f.note = f.descs[(f.cursor or 0) + 1]
        end
      elseif Input:wasPressed("up") then
        if statusNote and kind == "item_storage" then
          f.note = descNote
          return true
        end
        f.cursor = ((f.cursor or 0) - 1) % n
        if f.cursor < 0 then f.cursor = n - 1 end
        if kind == "item_storage" and f.descs then
          f.note = f.descs[(f.cursor or 0) + 1]
        end
      elseif Input:wasPressed("a") then
        if statusNote and kind == "item_storage" then
          f.note = descNote
          return true
        end
        if kind == "item_storage" then
          self:pickItemStorage(f.cursor or 0)
        elseif kind == "pc_item_list" then
          self:pickPcItemList(f.cursor or 0)
        elseif kind == "pc_deposit_list" then
          self:pickPcDepositList(f.cursor or 0)
        elseif kind == "pc_mailbox" then
          self:pickMailbox(f.cursor or 0)
        elseif kind == "pc_mail_actions" then
          self:pickMailboxAction(f.cursor or 0)
        end
      end
      return true
    end
    if kind == "pc_qty" then
      local max = f.max or 1
      if Input:wasPressed("b") then
        if f.mode == "deposit" then
          self:openPcDepositList()
        else
          self:openPcItemList(f.mode)
        end
        return true
      end
      if Input:wasPressed("up") then
        f.qty = (f.qty or 1) + 1
        if f.qty > max then f.qty = 1 end
      elseif Input:wasPressed("down") then
        f.qty = (f.qty or 1) - 1
        if f.qty < 1 then f.qty = max end
      elseif Input:wasPressed("a") then
        self:confirmPcQty()
      end
      return true
    end
    if kind == "pc_mail_give" then
      local n = #(self.party or {})
      if n < 1 then n = 1 end
      if Input:wasPressed("b") then
        self:openMailboxActions(f.mailIndex)
        return true
      end
      if Input:wasPressed("down") then
        f.cursor = ((f.cursor or 0) + 1) % n
      elseif Input:wasPressed("up") then
        f.cursor = ((f.cursor or 0) - 1) % n
        if f.cursor < 0 then f.cursor = n - 1 end
      elseif Input:wasPressed("a") then
        self:givePcMailToParty((f.cursor or 0) + 1)
      end
      return true
    end
    return false
  end

  function Game3:drawPlayerPcMenus(f)
    f = f or self.field
    if not f then return end
    local kind = f.kind
    if kind == "item_storage" or kind == "pc_item_list"
        or kind == "pc_deposit_list" or kind == "pc_mailbox"
        or kind == "pc_mail_actions" then
      if f.note then
        love.graphics.setColor(0.10, 0.10, 0.12, 1)
        local y = 100
        for part in (f.note .. "\n"):gmatch("(.-)\n") do
          self:drawText(part, 8, y)
          y = y + 12
        end
      end
      self:drawMenuListWindow(0, 1, f.labels, f.cursor)
      return true
    end
    if kind == "pc_qty" then
      love.graphics.setColor(0.10, 0.10, 0.12, 1)
      local y = 100
      for part in ((f.prompt or "How many?") .. "\n"):gmatch("(.-)\n") do
        self:drawText(part, 8, y)
        y = y + 12
      end
      self:drawText(("x%d"):format(f.qty or 1), 8, y + 4)
      return true
    end
    if kind == "pc_mail_give" then
      self:drawPartyScreen({
        kind = "party",
        cursor = f.cursor or 0,
        prompt = "Give to which POKéMON?",
      })
      return true
    end
    return false
  end
end

return PlayerPc
