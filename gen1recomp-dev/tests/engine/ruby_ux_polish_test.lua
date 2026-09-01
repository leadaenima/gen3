-- Starter bag, shop windows, berry frames, fade veil, doors, catch,
-- last-move cursor, heal effect, obtain fanfare, TM/HM bag move names.
--   luajit tests/engine/ruby_ux_polish_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby ux polish")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
local Input = require("src.core.Input")

Input:init()

local function press(g, name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  if g.phase == "battle" then
    g:stepBattle(0)
  else
    g:stepField()
  end
  Input.wasPressed = old
end

eq(Game3.berrySheetFrame(5, 9), 8, "ripe combined sheet uses berry frames")
eq(Game3.berrySheetFrame(5, 6), 5, "ripe late sheet uses its last pair")
eq(Game3.berrySheetFrame(1, 9), 0, "planted combined sheet is dirt")
eq(Game3.berrySheetFrame(1, 3), 0, "planted early sheet is dirt")
eq(Game3.berrySheetFrame(2, 3), 2, "sprout early sheet is the last sprout frame")
eq(Game3.berrySheetFrame(3, 6), 1, "taller late sheet is the first pair")
eq(Game3.FLDEFF_POKECENTER_HEAL, 25, "pokecenter heal field effect id")
eq(Game3.MUS_OBTAIN_ITEM, 370, "obtain-item fanfare")
eq(Game3.SE_SHOP, 95, "shop SE")
eq(Game3.STARTER_BALL_XY[2][1], 120, "Torchic's ball is the bottom-center one")

local fade = Game3.new()
fade:beginScreenFade(Game3.FADE_TO_BLACK)
eq(fade:screenFadeAlpha() < 0.01, true, "fade-to-black starts clear")
fade:stepScreenFade(16 / 60)
check(fade:screenFadeAlpha() >= 0.99, "then holds black")
check(fade.screenFade ~= nil, "and keeps the veil")
fade:beginScreenFade(Game3.FADE_FROM_BLACK)
fade:stepScreenFade(16 / 60)
eq(fade.screenFade, nil, "fade-from-black clears the veil")

local _, fadePause = Gen3Script.run(Game3.new(), {
  { op = "fadescreen", mode = Game3.FADE_TO_BLACK },
})
eq(fadePause, "delay", "fadescreen still pauses the VM")

-- Stuck FADE_TO_BLACK after object scripts: START / talk must lift the veil
-- even while scriptWait is still armed (waitstate / leftover CB2 wait).
local stuck = Game3.new()
stuck.phase = "play"
stuck:beginScreenFade(Game3.FADE_TO_BLACK)
stuck:stepScreenFade((stuck.FADE_FRAMES or 16) / 60)
stuck.scriptWait = true
stuck.field = nil
check(stuck:heldFadeShouldLift(), "free roam lifts even with scriptWait")
check(stuck:releaseHeldFade(), "and releaseHeldFade fires")
eq(stuck.screenFade and stuck.screenFade.mode, Game3.FADE_FROM_BLACK,
  "turning the held veil into a fade-in")

stuck:beginScreenFade(Game3.FADE_TO_BLACK)
stuck:stepScreenFade((stuck.FADE_FRAMES or 16) / 60)
stuck.scriptWait = true
stuck.field = { kind = "talk", text = "It's a TV." }
check(stuck:heldFadeShouldLift(), "talk after fadescreen lifts")
stuck.field = { kind = "menu", cursor = 0 }
check(stuck:heldFadeShouldLift(), "START menu lifts")
stuck.field = { kind = "clock_set", hours = 10, minutes = 0 }
check(stuck:heldFadeShouldLift(), "clock UI lifts")
stuck.field = { kind = "wait" }
eq(stuck:heldFadeShouldLift(), false, "waitstate placeholder keeps black")
stuck.field = { kind = "delay" }
eq(stuck:heldFadeShouldLift(), false, "fadescreen delay keeps black")
stuck.delayLeft = 0.1
stuck.field = nil
eq(stuck:heldFadeShouldLift(), false, "active script delay keeps black")

local door = Game3.new()
door.map = { width = 3, height = 3, grid = { 0, 0, 0, 0, 1024, 0, 0, 0, 0 } }
check(door:openDoor(1, 1), "opendoor flips collision")
check(door:doorAnimating(), "and starts a door anim")
local _, doorPause = Gen3Script.run(door, { { op = "waitdooranim" } })
eq(doorPause, "delay", "waitdooranim waits out the anim")
door:stepDoorAnim(1)
eq(door.doorAnim, nil, "the overlay is gone when the anim finishes")
check(door:openDoor(1, 1, false), "silent open is still allowed")
eq(door.doorAnim, nil, "and does not leave a square")

local indoor = {
  id = "g_in", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 1024, 0 },
  warps = { { x = 1, y = 2, warpId = 0 } },
}
local landed = Game3.new()
landed:enterMap(indoor, 1, 2, true)
eq(landed.doorAnim, nil, "warping onto an exit does not draw a door square")

local mart = Game3.new()
mart.money = 3000
mart:openMartList({ Game3.ITEM_POTION, Game3.ITEM_POKE_BALL })
eq(mart.field.kind, "mart", "shop keeps kind mart")
eq(mart.field.mode, "root", "and opens on BUY/SELL/QUIT")
eq(mart.field.items[1], Game3.ITEM_POTION, "stock stays on the field")
press(mart, "b")
eq(mart.field, nil, "B on the root menu still quits")

local buy = Game3.new()
buy.money = 3000
buy.bag = {}
buy:openMartList({ Game3.ITEM_POKE_BALL })
press(buy, "a")
eq(buy.field.mode, "buy", "A on BUY opens the stock list")
press(buy, "a")
eq(buy.field.mode, "qty", "A on an item asks for a quantity")
eq(buy.field.qty, 1, "starting at 1")
press(buy, "a")
eq(buy:itemCount(Game3.ITEM_POKE_BALL), 1, "confirming buys one")

local starter = Game3.new()
starter.phase = "play"
starter:openStarterMenu()
eq(starter.field.cursor, 1, "cursor starts on Torchic")
press(starter, "left")
eq(starter.field.cursor, 0, "left from Torchic is Treecko")
press(starter, "right")
press(starter, "right")
eq(starter.field.cursor, 2, "right lands on Mudkip")
press(starter, "up")
eq(starter.field.cursor, 1, "up still cycles")

local fight = Game3.new()
fight.phase = "battle"
fight.battle = {
  kind = "menu",
  cursor = 0,
  fightCursor = 2,
  player = {
    name = "TORCHIC", hp = 19, maxHp = 19,
    moves = {
      { name = "SCRATCH", pp = 35, maxPp = 35, type = 0 },
      { name = "GROWL", pp = 40, maxPp = 40, type = 0 },
      { name = "EMBER", pp = 25, maxPp = 25, type = 10 },
      { name = "PECK", pp = 35, maxPp = 35, type = 2 },
    },
  },
  enemy = { name = "WURMPLE", hp = 10, maxHp = 10, species = 290 },
}
press(fight, "a")
eq(fight.battle.kind, "fight", "FIGHT opens the move grid")
eq(fight.battle.fightCursor, 2, "and stays on the last move")

local catcher = Game3.new()
catcher.party = { { name = "TORCHIC", hp = 19, maxHp = 19, species = 280 } }
catcher.balls = 5
catcher.rng = function() return 1 end
catcher.phase = "battle"
catcher.battle = {
  kind = "menu",
  player = catcher.party[1],
  enemy = {
    name = "WURMPLE", hp = 13, maxHp = 13, species = 290, catchRate = 255,
    level = 2,
  },
}
catcher:throwBall()
check(catcher.battle.catchAnim ~= nil, "a throw starts a catch anim")
eq(catcher.battle.kind, "text", "and still queues the catch lines")
eq(catcher.battle.caught, true, "rand=1 still catches")

local heal = Game3.new()
heal.party = { { name = "TORCHIC", hp = 5, maxHp = 19 } }
heal:doFieldEffect(Game3.FLDEFF_POKECENTER_HEAL)
check(heal:fieldEffectActive(Game3.FLDEFF_POKECENTER_HEAL),
  "the nurse heal effect is armed")
check(heal:pokecenterHealFrames() > 16, "and lasts more than a default tick")

local cam = Game3.new()
cam.playerX, cam.playerY = 7, 6
cam.walkFromX, cam.walkFromY = 7, 6
cam.map = { width = 20, height = 18, grid = {} }
cam.viewW, cam.viewH = Game3.SCREEN_W, Game3.SCREEN_H
cam:clampCamera()
local wx, wy = cam:gbaScreenToWorld(Game3.POKECENTER_BALL_X, Game3.POKECENTER_BALL_Y)
eq(wx - cam.camX, Game3.POKECENTER_BALL_X,
  "Center balls match GBA screen x at 240x160")
eq(wy - cam.camY, Game3.POKECENTER_BALL_Y,
  "and GBA screen y")
cam.viewW, cam.viewH = 480, 320
cam:clampCamera()
local zx, zy = cam:gbaScreenToWorld(Game3.POKECENTER_BALL_X, Game3.POKECENTER_BALL_Y)
eq(zx, wx, "zoom does not move the overlay in the world")
eq(zy, wy, "vertically either")
check(zx - cam.camX ~= Game3.POKECENTER_BALL_X,
  "so a zoomed HUD letterbox is not the draw space")
local stub = { getDimensions = function() return 8, 8 end }
local planted
function cam:drawStandingAt(px, py, sw, sh, body)
  planted = { px = px, py = py, sw = sw, sh = sh }
  if body then body() end
end
function cam:drawSpriteCenter() end
cam:drawGbaFieldSprite(stub, Game3.POKECENTER_BALL_X, Game3.POKECENTER_BALL_Y,
  0, 0, 8, 8)
check(planted ~= nil, "heal OBJs go through drawStandingAt")
eq(planted.sw, 8, "8x8 glow tile")
eq(planted.px, zx - 4, "CreateSprite x is the sprite centre")
eq(planted.py, zy - 4, "and y too")

local npc = { itemId = Game3.ITEM_POTION, itemCount = 1 }
local picker = Game3.new()
picker.bag = {}
check(picker:pickupItem(npc), "overworld pickup still grants the item")
eq(picker:itemCount(Game3.ITEM_POTION), 1, "into the bag")

local tmBag = Game3.new()
tmBag.data.moves = {
  byId = {
    [332] = { name = "AERIAL ACE" },
    [351] = { name = "SHOCK WAVE" },
  },
}
eq(Game3.TMHM_MOVES[34], 351, "TM34 teaches Shock Wave")
eq(tmBag:tmhmMoveName(Game3.ITEM_TM40), "AERIAL ACE", "TM40 names Aerial Ace")
eq(tmBag:tmhmMoveName(Game3.ITEM_TM01 + 33), "SHOCK WAVE", "TM34 names Shock Wave")
eq(tmBag:tmhmMoveName(Game3.ITEM_HM_FLASH), "FLASH", "HM05 names Flash")
eq(tmBag:tmhmMoveName(Game3.ITEM_POTION), nil, "a Potion has no TM move")
tmBag.data.items = { byId = { [Game3.ITEM_TM01 + 33] = { name = "TM34", pocket = 3 } } }
tmBag.bag = { { id = Game3.ITEM_TM01 + 33, count = 1 } }
local bagTexts = {}
local oldBagText = Game3.drawText
function Game3.drawText(_, text)
  bagTexts[#bagTexts + 1] = tostring(text or "")
end
tmBag:drawBag({ pocket = Game3.POCKET_TMHM, cursor = 0 })
Game3.drawText = oldBagText
local sawTm, sawMove = false, false
for i = 1, #bagTexts do
  if bagTexts[i] == "TM34" then sawTm = true end
  if bagTexts[i] == "SHOCK WAVE" then sawMove = true end
end
check(sawTm, "the desc box still names the TM")
check(sawMove, "and lists the move under it")

S.finish()
