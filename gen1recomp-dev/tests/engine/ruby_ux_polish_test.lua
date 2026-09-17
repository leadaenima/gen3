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

eq(Game3.WORLD_FIELD.door_enter, true, "door enter keeps the zoomed overworld")
eq(Game3.WORLD_FIELD.door_arrival, true, "door arrival keeps the zoomed overworld")
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
eq(Game3.STARTER_HAND_XY[2][2], 56, "and the hand sits above that ball")
eq(Game3.STARTER_LABEL_AT[1][1], 0, "Treecko's label is the left tile column")
eq(Game3.STARTER_LABEL_AT[3][2], 4, "Mudkip's label is the high row")
eq(Game3.starterBallAnimFrame(false, 0), 0, "idle balls stay on frame 0")
eq(Game3.starterBallAnimFrame(true, 0), 1, "the selected ball starts on tile 16")
eq(Game3.starterBallAnimFrame(true, 4 / 60), 0, "then returns to idle")
eq(Game3.starterBallAnimFrame(true, 8 / 60), 2, "then tile 32")
eq(Game3.starterBallAnimFrame(true, 32 / 60), 0, "and rests for 32 frames")
eq(Game3.starterHandBob(0), 0, "hand bob starts at Sin(0)")
eq(math.abs(Game3.starterHandBob(16 / 60) - 8) < 0.01, true,
  "quarter-turn of the 256-step table is amplitude 8")
local rx, ry, cs, ps = Game3.starterRevealState(60, 64, 0)
eq(rx, 60, "Treecko's reveal starts on its ball")
eq(ry, 64, "same y")
eq(cs, 20 / 256, "circle affine starts at 20/256")
eq(ps, 16 / 256, "front pic starts at 16/256")
rx, ry, cs, ps = Game3.starterRevealState(60, 64, 15 / 60)
eq(rx, 120, "15 frames at 4px reaches centre x")
eq(ry, 64, "already on the centre row")
eq(cs, 320 / 256, "circle ends at 320/256")
eq(ps, 1, "front pic ends at 1")
rx, ry = Game3.starterRevealState(120, 88, 12 / 60)
eq(rx, 120, "Torchic is already centred in x")
eq(ry, 64, "12 frames at 2px reaches centre y")

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

-- DoDoorWarp: north into an animated door opens → walks in → closes → warps.
local outdoor = {
  id = "g_out", width = 3, height = 4,
  grid = {
    0, 0, 0,
    0, 0, 0,
    0, Game3.MB_ANIMATED_DOOR + 1024, 0, -- collision door mat
    0, 0, 0,
  },
  warps = { { x = 1, y = 2, mapGroup = 1, mapNum = 0, warpId = 0 } },
  tileset = "pair_0",
}
-- behaviorAt reads tileset; stub it.
local enter = Game3.new()
enter.data = { tilesets = { doorByMetatile = { [Game3.MB_ANIMATED_DOOR] = { row = 0, sound = 0 } } } }
enter.map = outdoor
enter.playerX, enter.playerY = 1, 3
enter.facing = "north"
function enter:behaviorAt(map, x, y)
  if x == 1 and y == 2 then return Game3.MB_ANIMATED_DOOR end
  return 0
end
function enter:playSe() end
local warped
function enter:followWarp(w) warped = w; return true end
check(enter:beginDoorWarp(outdoor.warps[1], 1, 2), "beginDoorWarp starts")
eq(enter.field.kind, "door_enter", "field is door_enter")
eq(enter.field.phase, "open", "phase open")
check(enter:doorAnimating(), "door is opening")
-- walkHeld drives door_enter: open → walk north → close → warp.
-- Finish the open anim, then tick until each phase advances.
enter.doorAnim = nil
enter.phase = "play"
enter:walkHeld(0)
eq(enter.field.phase, "walk", "then walks north")
-- scriptMoving also watches walkCooldown; drain both jobs and cooldown.
enter.moveJobs = {}
enter.walkCooldown = 0
enter.walkAccum = 0
enter:walkHeld(0)
eq(enter.field.phase, "close", "then closes")
check(enter.invisible, "player hides while door closes")
enter.doorAnim = nil
enter:walkHeld(0)
check(warped == outdoor.warps[1], "finally follows the warp")
eq(enter.field, nil, "and clears the field")
eq(enter.invisible, nil, "player visible again after warp handoff")

-- tryWalk north into MB_ANIMATED_DOOR is what arms DoDoorWarp in the field.
local bump = Game3.new()
bump.data = enter.data
bump.map = outdoor
bump.playerX, bump.playerY = 1, 3
bump.phase = "play"
function bump:behaviorAt(map, x, y)
  if x == 1 and y == 2 then return Game3.MB_ANIMATED_DOOR end
  return 0
end
function bump:playSe() end
function bump:coordEventWouldRun() return false end
check(bump:tryWalk(0, -1), "north into an animated door starts the warp")
eq(bump.field.kind, "door_enter", "via tryWalk")
local side = Game3.new()
side.data = enter.data
side.map = outdoor
side.playerX, side.playerY = 0, 2
function side:behaviorAt(map, x, y)
  if x == 1 and y == 2 then return Game3.MB_ANIMATED_DOOR end
  return 0
end
function side:coordEventWouldRun() return false end
eq(side:tryWalk(1, 0), false, "sideways into the door is a bump")

-- Arrival side: silent open (lightExitDoors) → walk south → animated close.
local indoors = {
  id = "g_arrive", width = 3, height = 4,
  grid = {
    0, 0, 0,
    0, 0, 0,
    0, Game3.MB_ANIMATED_DOOR + 1024, 0,
    0, 0, 0,
  },
  warps = { { x = 1, y = 2, warpId = 0 } },
  tileset = "pair_0",
}
local arrive = Game3.new()
arrive.data = enter.data
arrive.map = indoors
arrive.playerX, arrive.playerY = 1, 1
arrive.phase = "play"
function arrive:behaviorAt(map, x, y)
  if x == 1 and y == 2 then return Game3.MB_ANIMATED_DOOR end
  return 0
end
function arrive:playSe() end
arrive:lightExitDoors()
eq(arrive.doorAnim, nil, "lightExitDoors opens without an overlay")
check(indoors.openDoors and next(indoors.openDoors), "but leaves the mat open")
arrive:startDoorArrival()
eq(arrive.field.kind, "door_arrival", "arrival queues the south step")
arrive.moveJobs = {}
arrive.walkCooldown = 0
arrive:walkHeld(0)
check(arrive:doorAnimating(), "then closes the door behind the player")
eq(arrive.field, nil, "and drops the arrival field")

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

-- Field-move cinema: May/Brendan pose gfx + Cut/Rock Smash/Strength VFX.
eq(Game3.GFX_MAY_FIELD_MOVE, 93, "May field-move gfx")
eq(Game3.GFX_BRENDAN_FIELD_MOVE, 3, "Brendan field-move gfx")
eq(Game3.FLDEFF_FIELD_MOVE_POSE_FRAMES, 48, "field-move pose length")
eq(Game3:fieldEffectDuration(Game3.FLDEFF_USE_CUT_ON_TREE),
  Game3.FLDEFF_FIELD_MOVE_POSE_FRAMES, "Cut waits for the pose")
eq(Game3:fieldEffectDuration(Game3.FLDEFF_USE_STRENGTH),
  Game3.FLDEFF_FIELD_MOVE_POSE_FRAMES, "Strength waits for the pose")

local may = Game3.new()
may.phase = "play"
may.gender = Game3.GENDER_FEMALE
may.data = { sprites = { byId = {
  [Game3.GFX_MAY] = { id = Game3.GFX_MAY, frameCount = 9, width = 16, height = 32 },
  [Game3.GFX_MAY_FIELD_MOVE] = {
    id = Game3.GFX_MAY_FIELD_MOVE, frameCount = 5, width = 32, height = 32,
  },
} } }
may:enterMap({
  id = "g_fm", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
may.facing = "east"
eq(may:playerGraphicsId(), Game3.GFX_MAY, "May walks on her normal sheet")
may:doFieldEffect(Game3.FLDEFF_USE_CUT_ON_TREE)
check(may:fieldMovePosing(), "Cut arms the field-move pose")
eq(may:playerGraphicsId(), Game3.GFX_MAY_FIELD_MOVE,
  "and swaps May onto the field-move sheet")
eq(may:fieldMovePoseFrame(may.data.sprites.byId[Game3.GFX_MAY_FIELD_MOVE]),
  0, "pose starts on frame 0")
check(may:fieldEffectActive(Game3.FLDEFF_USE_CUT_ON_TREE), "Cut effect is live")
local left = may.fieldEffects[1].left
may:stepFieldEffects(8)
eq(may.fieldEffects[1].left, left - 8, "pose ticks down")
local mid = may:fieldMovePoseFrame(may.data.sprites.byId[Game3.GFX_MAY_FIELD_MOVE])
check(mid >= 0 and mid <= 4, "pose frame stays in-sheet")
-- Missing sheet must not leave a brown-square gid.
local bare = Game3.new()
bare.gender = Game3.GENDER_FEMALE
bare.data = { sprites = { byId = {
  [Game3.GFX_MAY] = { id = Game3.GFX_MAY, frameCount = 9 },
} } }
bare.fieldEffects = { {
  id = Game3.FLDEFF_USE_ROCK_SMASH, fieldMove = true,
  left = 20, dur = 48,
} }
eq(bare:playerGraphicsId(), Game3.GFX_MAY,
  "missing field-move sheet falls back to May")

local smash = Game3.new()
smash.phase = "play"
smash:enterMap({
  id = "g_fm2", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
smash.facing = "north"
smash:doFieldEffect(Game3.FLDEFF_USE_ROCK_SMASH)
check(smash.fieldEffects[1].fieldMove, "Rock Smash marks fieldMove")
eq(smash.fieldEffects[1].gy, 0, "VFX targets the tile in front")
local drawn = false
local oldStanding = Game3.drawStandingAt
function Game3.drawStandingAt(_, _, _, _, _, fn)
  drawn = true
  if fn then fn() end
end
smash.fieldEffects[1].left = smash.fieldEffects[1].dur / 2
smash:drawFieldEffects()
Game3.drawStandingAt = oldStanding
check(drawn, "Rock Smash draws shatter VFX")

-- Typed battle move FX + richer catch cinema + Surf/Fly overlays.
eq(Game3.MOVE_ANIM_DAMAGE, 0.42, "damage anim length")
local r, g, bl = Game3.typeRgb(Game3.TYPE_FIRE)
check(r > 0.8 and g < 0.6, "Fire tint is orange-red")

local bat = Game3.new()
bat.phase = "battle"
bat.battle = {
  kind = "text",
  player = { name = "TORCHIC", species = 280, hp = 20, maxHp = 20,
    type1 = Game3.TYPE_FIRE },
  enemy = { name = "WURMPLE", species = 290, hp = 15, maxHp = 15,
    type1 = Game3.TYPE_BUG },
}
bat:armMoveAnim(bat.battle.player, bat.battle.enemy,
  { name = "EMBER", type = Game3.TYPE_FIRE, power = 40 }, "damage")
check(bat.battle.moveAnim ~= nil, "armMoveAnim stores moveAnim")
-- Gen 3 splits physical/special BY TYPE, and Fire is on the special side --
-- which is what this has always been about. It used to assert it through
-- moveAnim.kind, and that stopped being the right field: once a move has a
-- ROM-scripted animation, src/core/Game3MoveAnim.lua takes the call and pins
-- kind to "status" on purpose -- "status amp is smallest generic lunge;
-- scripted offsets do the real motion", because the generic lunge would
-- fight the scripted ones.
--
-- `physical` is the field that still carries the split on BOTH paths, so the
-- question this test asks is asked of the field that answers it.
eq(bat.battle.moveAnim.physical, false,
  "Fire is on the special side of the Gen 3 split")
check(Game3.isPhysical(Game3.TYPE_FIRE) == false,
  "which is the type-level rule the whole split rests on")
check(Game3.isPhysical(Game3.TYPE_ROCK) == true,
  "and Rock is on the physical side of it")
eq(bat.battle.moveAnim.type, Game3.TYPE_FIRE, "and keeps the type")
check((bat.battle.animT or 0) > 0.3, "animT matches damage dur")
bat.options = { battleScene = false }
bat.battle.moveAnim = nil
bat:armMoveAnim(bat.battle.player, bat.battle.enemy,
  { name = "EMBER", type = Game3.TYPE_FIRE, power = 40 }, "damage")
eq(bat.battle.moveAnim, nil, "battleScene OFF skips FX")

local catchFx = Game3.new()
catchFx.party = { { name = "TORCHIC", hp = 19, maxHp = 19, species = 280 } }
catchFx.balls = 5
catchFx.rng = function() return 1 end
catchFx.phase = "battle"
catchFx.battle = {
  kind = "menu",
  player = catchFx.party[1],
  enemy = {
    name = "WURMPLE", hp = 13, maxHp = 13, species = 290, catchRate = 255,
    level = 2,
  },
}
catchFx:throwBall()
local ca = catchFx.battle.catchAnim
check(ca ~= nil, "catch cinema arms")
check((ca.open or 0) > 0, "with an open phase")
check((ca.bounce or 0) > 0, "and a bounce phase")
check(ca.ok, "rand=1 still catches")

local surfer = Game3.new()
surfer.phase = "play"
surfer.facing = "east"
surfer.flags[Game3.FLAG_BADGE05_GET] = true
surfer.party = { { name = "MUDKIP", moves = { { id = Game3.MOVE_SURF } } } }
surfer.data.tilesets = { byId = { wat = { behavior = { [1] = 0x10 } } } }
surfer:enterMap({
  id = "g_surf_fx", width = 3, height = 3, tileset = "wat",
  grid = { 0, 0, 0, 0, 3 * 4096, 1025, 0, 0, 0 },
}, 1, 1, true)
local sok = surfer:useSurf()
check(sok, "Surf still mounts")
check(surfer.owCinema and surfer.owCinema.kind == "surf_mount",
  "and arms the mount splash cinema")
surfer:stepOwCinema(1)
eq(surfer.owCinema, nil, "mount cinema expires")

local flyer = Game3.new()
flyer.phase = "play"
flyer.owCinema = nil
flyer:beginFlyInCinema()
eq(flyer.owCinema.kind, "fly_in", "Fly-in cinema arms")
check((flyer.owCinema.dur or 0) > 0.5, "and lasts nearly a second")
flyer:beginFlyOutCinema()
eq(flyer.owCinema.kind, "fly_out", "Fly-out cinema arms")

local catchDur = Game3.catchAnimDuration({
  throw = 0.35, open = 0.12, bounce = 0.18, shakes = 3, perShake = 0.4,
  stars = 0.55, breakout = 0,
})
check(math.abs(catchDur - 2.4) < 1e-9, "catch duration sums phases")

-- Draw paths must not throw headless.
local drawBat = Game3.new()
drawBat.phase = "battle"
drawBat.battle = {
  kind = "text",
  animT = 0.3,
  moveAnim = {
    t = 0, dur = 0.42, type = Game3.TYPE_WATER, kind = "special", onEnemy = true,
  },
  player = { name = "MUDKIP", species = 283, hp = 20, maxHp = 20 },
  enemy = { name = "WURMPLE", species = 290, hp = 10, maxHp = 15 },
}
drawBat:drawBattle()
check(true, "typed special FX draws without error")
drawBat.battle.moveAnim.kind = "physical"
drawBat.battle.moveAnim.type = Game3.TYPE_NORMAL
drawBat:drawBattle()
check(true, "typed physical FX draws without error")
drawBat.battle.catchAnim = {
  t = 0.2, throw = 0.35, open = 0.12, bounce = 0.18,
  shakes = 2, perShake = 0.4, stars = 0.55, ok = true,
}
drawBat.battle.animT = 0
drawBat.battle.moveAnim = nil
drawBat:drawBattle()
check(true, "catch cinema draws without error")

local ow = Game3.new()
ow.phase = "play"
ow:enterMap({
  id = "g_owfx", width = 3, height = 3, grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
ow.surfing = true
ow:drawSurfBlob()
ow:beginFlyInCinema()
ow:drawOwCinema()
ow:beginSurfMountCinema()
ow:drawOwCinema()
check(true, "Surf blob + Fly/Surf overlays draw without error")


-- ------------------------------------------------- bag pocket label
--
-- item_menu.c sub_80A39B8: sub_809D104(dest, 4, 10, gBagScreenLabels_Tilemap,
-- 0, pocket * 2, 8, 2). The pocket name is an 8x2 tile block of cart art
-- blitted to tile (4, 10) -- pixels (32, 80), sitting on the yellow bar --
-- not a string. It used to be drawn as text at (8, 74), which put it over the
-- bag sprite's shadow instead.
eq(Game3.BAG_LABEL_X, 32, "tile 4 across in pixels")
eq(Game3.BAG_LABEL_Y, 80, "tile 10 down")
eq(Game3.BAG_LABEL_W, 64, "eight tiles wide")
eq(Game3.BAG_LABEL_H, 16, "two tiles tall")
;(function()
  local drawn = {}
  local g = Game3.new()
  g.bagImage = function(_, n)
    if n ~= "bag_labels.png" then return nil end
    return { getDimensions = function() return 64, 96 end }
  end
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, quad, x, y)
    drawn[#drawn + 1] = { quad = quad, x = x, y = y }
  end
  local ok = g:drawBagPocketLabel(Game3.POCKET_ITEMS, 0)
  love.graphics.draw = realDraw
  check(ok, "the pocket label blits from the cart strip")
  eq(#drawn, 1, "exactly one blit")
  eq(drawn[1].x, 32, "at x 32")
  eq(drawn[1].y, 80, "and y 80")
end)()
;(function()
  local g = Game3.new()
  g.bagImage = function() return nil end
  check(not g:drawBagPocketLabel(1, 0),
    "and reports failure without the art so the text fallback runs")
end)()
-- row 0 of the strip is blank, so pockets index from 1 straight into it
eq(Game3.POCKET_ITEMS, 1, "the first pocket is 1, matching the strip row")


-- ------------------------------------------------ bag screen geometry
--
-- gBagScreen_Tilemap already draws the item list panel and the description
-- panel, so the engine painting standard window frames over them replaced
-- the cart's yellow and white borders with the generic grey one. Every
-- position below comes from item_menu.c:
--   Menu_PrintText(gStringVar1, 14, itemPos * 2 + 2)   -> (112, 16i + 16)
--   Menu_PrintTextPixelCoords(description, 4, 104 + 16b)
--   CreateVerticalScrollIndicators(TOP_ARROW, 172, 12) / (BOTTOM, 172, 148)
--   CreateVerticalScrollIndicators(LEFT_ARROW, 28, 88) / (RIGHT, 100, 88)
eq(Game3.BAG_LIST_X, 112, "tile 14, flush with the panel interior")
eq(Game3.BAG_LIST_Y, 16, "first row at tile row 2")
eq(Game3.BAG_LIST_ROW, 16, "two tiles a row")
eq(Game3.BAG_DESC_X, 4, "description x is pixel 4, not 12")
eq(Game3.BAG_DESC_Y, 104, "and y 104, not 112")
eq(Game3.BAG_DESC_ROW, 16, "16px a line")
eq(Game3.BAG_ARROW_X, 172, "scroll arrows at x 172, not off at 220")
eq(Game3.BAG_ARROW_TOP_Y, 12, "top arrow")
eq(Game3.BAG_ARROW_BOTTOM_Y, 148, "bottom arrow")
eq(Game3.BAG_POCKET_LEFT_X, 28, "pocket switch arrows flank the bar")
eq(Game3.BAG_POCKET_RIGHT_X, 100, "at 28 and 100")
eq(Game3.BAG_POCKET_ARROW_Y, 88, "on row 88")

-- and the two redundant frames are gone: the bag must not paint a standard
-- window anywhere, because the screen art already has both panels
;(function()
  local windows = 0
  local g = Game3.new()
  g.drawWindow = function() windows = windows + 1 end
  g.bagImage = function() return nil end
  g.bagSlotsIn = function() return {} end
  g.pocketName = function() return "ITEMS" end
  g.bagCloseDestination = function() return "the field" end
  g.drawText = function() end
  g.drawCursor = function() end
  g:drawBag({ pocket = Game3.POCKET_ITEMS, cursor = 0 })
  -- the only drawWindow left is the BAG placeholder when the sprite is
  -- missing, which this fixture triggers by returning no art at all
  check(windows <= 1,
    ("no standard frame over the cart's panels (drew %d)"):format(windows))
end)()


-- --------------------------------------------- bag rows and scroll arrows
--
-- item_menu.c prints a row as two aligned pieces, not one string:
--   AlignStringInMenuWindow(buf, ItemId_GetName(..), 0x66, 0)
--   AlignInt1InMenuWindow(buf, quantity, 0x78, 1)
-- so quantities form a column ending 0x78 past the row origin instead of
-- trailing each name wherever it happens to end. Key items and HMs have no
-- quantity at all.
eq(Game3.BAG_LIST_NAME_W, 0x66, "the name field")
eq(Game3.BAG_LIST_QTY_RIGHT, 112 + 0x78, "and the quantity column's right edge")
;(function()
  local g = Game3.new()
  g.itemName = function(_, id) return "POTION" end
  g.itemPocket = function() return Game3.POCKET_ITEMS end
  local name, qty = g:bagListParts({ id = 13, count = 5 }, Game3.POCKET_ITEMS)
  eq(name, "POTION", "the name comes back on its own")
  eq(qty, "x5", "with the quantity separate")
  local kname, kqty = g:bagListParts({ id = 260, count = 1 }, Game3.POCKET_KEY)
  eq(kqty, nil, "key items carry no quantity")
end)()

-- menu_helpers.c: one template covers both vertical arrows (anim 0 up, 1
-- down) as H_RECTANGLE 16x8; the horizontal pair is V_RECTANGLE 8x16, whose
-- two tiles STACK -- read side by side they are diagonal shards.
;(function()
  local q = Game3.SCROLL_ARROW_QUADS
  eq(q.up[3] .. "x" .. q.up[4], "16x8", "the up arrow is 16x8")
  eq(q.down[3] .. "x" .. q.down[4], "16x8", "so is the down")
  eq(q.left[3] .. "x" .. q.left[4], "8x16", "the left arrow is 8x16")
  eq(q.right[3] .. "x" .. q.right[4], "8x16", "and the right")
end)()
;(function()
  local at = {}
  local g = Game3.new()
  g.uiPic = function() return { getDimensions = function() return 16, 32 end } end
  local realDraw = love.graphics.draw
  love.graphics.draw = function(_, _, x, y) at[#at + 1] = { x, y } end
  g:drawScrollArrow("up", 172, 12)
  love.graphics.draw = realDraw
  eq(#at, 1, "the arrow blits once")
  -- CreateVerticalScrollIndicators takes the CENTRE, so 16x8 at (172,12)
  -- has its corner at (164, 8)
  eq(at[1][1], 164, "centred horizontally")
  eq(at[1][2], 8, "and vertically")
end)()


-- ------------------------------------------------ pocket indicator dots
--
-- item_menu.c DrawPocketIndicatorDots: tileMapBuffer[0x125 + i] is 0x107D
-- for the selected pocket and 0x107C otherwise. Index 0x125 is row 9 col 5,
-- so the dots run from (40, 72) in 8px steps. The cart has BOTH these and
-- the left/right switch arrows -- dropping the dots for the arrows was wrong.
eq(Game3.BAG_DOT_X, 40, "col 5")
eq(Game3.BAG_DOT_Y, 72, "row 9")
eq(Game3.BAG_DOT_STEP, 8, "one tile apart")
;(function()
  local at = {}
  local g = Game3.new()
  g.bagImage = function(_, n)
    if n ~= "bag_dots.png" then return nil end
    return { getDimensions = function() return 16, 8 end }
  end
  local realDraw = love.graphics.draw
  love.graphics.draw = function(_, quad, x, y) at[#at + 1] = { x, y } end
  local ok = g:drawBagPocketDots(2, 0)
  love.graphics.draw = realDraw
  check(ok, "the dots draw from the cart sheet")
  eq(#at, Game3.POCKET_COUNT, "one per pocket")
  eq(at[1][1], 40, "first dot at x 40")
  eq(at[1][2], 72, "and y 72")
  eq(at[2][1], 48, "second a tile along")
end)()

-- ...and drawBag must actually call it. Asserting only the helper let the
-- draw site be deleted silently, which is exactly how the dots went missing.
;(function()
  local calls = { dots = 0, label = 0 }
  local g = Game3.new()
  g.drawBagPocketDots = function() calls.dots = calls.dots + 1; return true end
  g.drawBagPocketLabel = function() calls.label = calls.label + 1; return true end
  g.bagImage = function() return nil end
  g.bagSlotsIn = function() return {} end
  g.bagCloseDestination = function() return "the field" end
  g.drawText = function() end
  g.drawCursor = function() end
  g.drawWindow = function() end
  g:drawBag({ pocket = Game3.POCKET_ITEMS, cursor = 0 })
  eq(calls.dots, 1, "drawBag paints the pocket dots")
  eq(calls.label, 1, "and the pocket label")
end)()


-- ------------------------------------ bag screen, checked off hardware
--
-- A capture of the real bag settled three things a ROM-data read could not.
--
-- 1. Tilemap entries carry hflip/vflip in bits 10 and 11. paintLzMap read
--    the id and palette but not the flips, so the list panel's left border
--    came out yellow-then-dark where the cart has dark-then-yellow, and the
--    corner tile was unreadable. 27 of the 640 visible entries are flipped.
-- 2. BGR555 is 5 bits per channel where 31 is FULL brightness. Scaling by 8
--    caps at 248/255 and darkens everything: the bag's yellow read F8C058
--    against the cart's FFC55A.
-- 3. The list selection is the wide red outline (sub_814A958), not the field
--    triangle. Measured at x 111..232, 16 tall.
eq(Game3.BAG_CURSOR_X, 111, "measured off the capture")
eq(Game3.BAG_CURSOR_W, 122, "111..232 inclusive")
eq(Game3.BAG_CURSOR_H, 16, "one row")
eq(Game3.BAG_DESC_W, 102, "descriptions stay in their own panel")
;(function()
  local boxes, tris = 0, 0
  local g = Game3.new()
  g.drawBattleCursor = function(_, x, y, w, h) boxes = boxes + 1
    eq(x, Game3.BAG_CURSOR_X, "the outline starts at 111")
    eq(w, Game3.BAG_CURSOR_W, "and is 122 wide") end
  g.drawCursor = function() tris = tris + 1 end
  g.bagImage = function() return nil end
  g.bagSlotsIn = function() return { { id = 13, count = 1 } } end
  g.itemName = function() return "POTION" end
  g.itemPocket = function() return Game3.POCKET_ITEMS end
  g.itemDescription = function() return "A useful item." end
  g.bagCloseDestination = function() return "the field" end
  g.drawText = function() end
  g.drawWindow = function() end
  g.drawBagPocketDots = function() end
  g.drawBagPocketLabel = function() return true end
  g:drawBag({ pocket = Game3.POCKET_ITEMS, cursor = 0 })
  eq(boxes, 1, "the bag list marks its selection with the wide outline")
  eq(tris, 0, "and never the field triangle")
end)()


-- --------------------------------------------- item description layout
--
-- The cart authors its own line breaks: parseOneItem decodes descriptions
-- with GbaText.decodePages, which keeps 0xFE as a newline. (decodeText, the
-- other decoder, turns 0xFE into a space and collapses runs -- descriptions
-- must not go through it or they arrive as one unbreakable line.)
--
-- So drawBagLines does not word-wrap; it honours the cart's breaks, which is
-- what the cart does. maxW is only a backstop, and it has to be wide enough
-- never to fire: the extracted panel's white interior runs x 3..105 and the
-- cart prints from x 4, so 102px is usable. At 100 the widest real line
-- (TINYMUSHROOM, 102px) would have been horizontally squashed.
eq(Game3.BAG_DESC_W, 102, "the usable width of the description panel")
;(function()
  local drawn = {}
  local g = Game3.new()
  g.drawText = function(_, t, x, y, maxW) drawn[#drawn + 1] = { t, x, y, maxW } end
  g:drawBagLines("one\ntwo\nthree", 4, 104, 16, 3)
  eq(#drawn, 3, "the cart's newlines become three lines")
  eq(drawn[1][3], 104, "first line at y 104")
  eq(drawn[2][3], 120, "second 16px below")
  eq(drawn[3][3], 136, "third below")
  eq(drawn[1][4], Game3.BAG_DESC_W, "and each is held to the panel width")
end)()
;(function()
  local g = Game3.new()
  local drawn = 0
  g.drawText = function() drawn = drawn + 1 end
  g:drawBagLines("a\nb\nc\nd", 4, 104, 16, 3)
  eq(drawn, 3, "and never more lines than the panel holds")
end)()

S.finish()
