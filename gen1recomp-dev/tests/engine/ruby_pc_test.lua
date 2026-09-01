-- Pokémon Storage System: primary menu, 6×5 box, sparse slots.
--   luajit tests/engine/ruby_pc_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby pc storage")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
Input:init()

eq(#Game3.PC_ROOT, 4, "primary menu is four items")
eq(Game3.PC_ROOT[1][1], "WITHDRAW POKéMON", "PCText_WithdrawPoke")
eq(Game3.PC_ROOT[2][1], "DEPOSIT POKéMON", "PCText_DepositPoke")
eq(Game3.PC_ROOT[3][1], "MOVE POKéMON", "PCText_MovePoke")
eq(Game3.PC_ROOT[4][1], "SEE YA!", "PCText_SeeYa")
eq(Game3.PC_BOX_CX, 0x64, "box icon centre x")
eq(Game3.PC_BOX_CY, 0x2c, "box icon centre y")
eq(Game3.PC_PARTY_LEAD_CX, 0x68, "party lead centre x")
eq(#Game3.PC_WALLPAPERS, 16, "16 wallpapers")

local function withGame()
  local g = Game3.new()
  g.phase = "play"
  g.rng = function() return 1 end
  g.party = { g:makeMon(280, 5) }
  return g
end

local function press(g, name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local g = withGame()
g:ensurePc()
eq(g.boxNames[1], "BOX1", "ResetPokemonStorageSystem names BOX1")
eq(g.boxNames[14], "BOX14", "through BOX14")
eq(g.boxWallpapers[1], 0, "wallpaper[i] = i & 3")
eq(g.boxWallpapers[4], 3, "box 4 is SAVANNA")
eq(g.boxWallpapers[5], 0, "then it repeats")

g:addToParty(g:makeMon(290, 2))
local egg = g:makeMon(280, 5)
egg.isEgg = true
egg.name = "EGG"
g:addToParty(egg)
check(g:canDepositToPc(3), "the PC accepts an EGG")
check(g:depositFromParty(3), "an EGG deposits")
eq(g.pc[1][1].isEgg, true, "into the first free slot")
eq(Game3.boxOccupancy(g.pc[1]), 1, "occupancy counts the egg")
eq(g:withdrawFromBox(1, 1), true, "withdraw leaves a hole, not a packed list")
eq(g.pc[1][1], nil, "slot 1 is empty")
eq(Game3.boxOccupancy(g.pc[1]), 0, "and occupancy is zero")

-- Holes stay. Depositing after withdrawing slot 1 of a later fill would
-- reuse the first free index, matching GetIndexOfFirstEmptySpaceInBoxN.
g.pc[1][5] = g:cloneMon(g.party[1])
eq(Game3.boxFirstFree(g.pc[1]), 1, "the first hole is slot 1")
eq(g:sendToPc(g.party[1]), 1, "sendToPc fills the hole")
eq(g.pc[1][1].species, 280, "Torchic lands in slot 1")
eq(g.pc[1][5].species, 280, "slot 5 is still occupied")

g:openPc()
eq(g:fieldShowsWorld(), true, "the primary menu sits on the overworld")
eq(g.field.mode, "root", "openPc is the 4-item menu")
while #g.party < 6 do g:addToParty(g.party[1]) end
press(g, "a")
eq(g.field.mode, "root", "WITHDRAW with a full party stays on the menu")
eq(g.field.note, "Your party is full!", "gPCText_PartyFull2")
press(g, "a")
eq(g.field.note, nil, "A dismisses the error")

g.party = { g:makeMon(280, 5) }
g:openPc()
press(g, "down")
press(g, "a")
eq(g.field.note, "There is just one POKéMON with you.", "gPCText_OnlyOne")

g:addToParty(g:makeMon(290, 2))
g:openPc()
press(g, "a")
eq(g.field.mode, "storage", "WITHDRAW enters the box screen")
eq(g:fieldShowsWorld(), false, "the box screen is a 240×160 letterbox")
eq(g.field.area, "box", "withdraw starts on the box")
local cx, cy = g:pcCursorXY("box", 0)
eq(cx, 0x64, "slot 0 centre x")
eq(cy, 0x2c, "slot 0 centre y")
cx, cy = g:pcCursorXY("box", 7)
eq(cx, 0x64 + 24, "col 1 row 1")
eq(cy, 0x2c + 24, "row pitch is 24")
cx, cy = g:pcCursorXY("party", 0)
eq(cx, 0x68, "party lead x")
eq(cy, 0x40, "party lead y")

press(g, "down")
eq(g.field.cursor, 6, "down from slot 0 is row 1")
press(g, "up")
press(g, "up")
eq(g.field.area, "title", "up from row 0 is the box name")
press(g, "left")
eq(g.field.box, 14, "left on the title wraps to BOX14")
press(g, "right")
eq(g.field.box, 1, "right wraps back to BOX1")

g:openPc()
press(g, "down")
press(g, "a")
eq(g.field.pss, "deposit", "DEPOSIT mode")
eq(g.field.area, "party", "starts on the party")
press(g, "a")
check(g.field.menu ~= nil, "A on a party mon opens the context menu")
eq(g.field.menu.items[1].text, "DEPOSIT", "first item is DEPOSIT")
press(g, "a")
eq(#g.party, 1, "deposit moved the party mon")
eq(Game3.boxOccupancy(g.pc[1]) >= 1, true, "into the current box")

g:openPc()
press(g, "down")
press(g, "down")
press(g, "a")
eq(g.field.pss, "move", "MOVE POKéMON")
eq(g.field.area, "box", "starts on the box")
-- Leave one mon in slot 1 and pick it up, then PLACE on the hole at slot 2.
g.pc[1] = {}
g.pc[1][1] = g:cloneMon(g.party[1])
press(g, "a")
eq(g.field.menu.items[1].id, "move", "MOVE is first")
press(g, "a")
check(g.field.held ~= nil, "MOVE picks the mon up")
press(g, "right")
press(g, "a")
eq(g.field.menu.items[1].id, "place", "empty slot offers PLACE")
press(g, "a")
eq(g.field.held, nil, "PLACE puts it down")
eq(g.pc[1][1], nil, "the old slot is a hole")
eq(g.pc[1][2] ~= nil, true, "the dest slot has the mon")

g:drawPc(g.field)
check(true, "the box screen draws without error")

S.finish()
