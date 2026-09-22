-- Ruby menu / battle window chrome: ROM offsets and the 9-slice mapping the
-- runtime relies on. See src/import/RomExtractorGen3Ui.lua.
-- Offsets only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_ui_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby ui chrome")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")
local Ui = require("src.import.RomExtractorGen3Ui")
local CacheContract = require("src.import.CacheContract")

-- graphics.c stores each style as 9 tiles (288 bytes) then its 16-color
-- palette, so a style pair strides 0x140. 1.gbapal was located by searching
-- the cart for the reference palette bytes.
eq(Ui.RUBY_US.framePal, 0xE9AEFC, "text window frame 1 palette")
eq(Ui.RUBY_US.frameGfx, 0xE9AEFC - 288, "its 9 tiles sit immediately before it")
eq(Ui.RUBY_US.frameStride, 0x140, "gfx+pal stride per style")
eq(Ui.FRAME_STYLES, 20, "sTextWindowFrameGraphics has 20 entries")
eq(Ui.FRAME_TILES, 9, "DrawStandardFrame uses 9 tiles")

-- The battle labels encode their own ROM addresses (gUnknown_08D1212C,
-- Tiles_D129AC), so the healthbox sheet is the gap between them.
eq(Ui.RUBY_US.windowPal, 0xD1212C, "battle_interface/window.gbapal")
eq(Ui.RUBY_US.hpBarPal, 0xD1214C, "battle_interface/hpbar.gbapal follows it")
eq(Ui.RUBY_US.healthboxGfx, 0xD1216C, "healthbox elements follow both palettes")
eq(Ui.RUBY_US.healthboxBytes, 0xD129AC - 0xD1216C,
  "and run up to ball_display")
eq(Ui.RUBY_US.healthboxBytes / 32, 66, "which is 66 tiles")

-- graphics.c lines 4-6: tiles, palette, tilemap, in that order.
eq(Ui.RUBY_US.battleTilesLz, 0xD00000, "gBattleTextboxTiles (menu.4bpp.lz)")
eq(Ui.RUBY_US.battlePalLz, 0xD004E0, "gBattleTextboxPalette follows the tiles")
eq(Ui.RUBY_US.battleMap, 0xD00524, "gBattleTextboxTilemap follows the palette")
eq(Ui.RUBY_US.battleMapBytes, 4096, "two 32x32 screenblocks")
eq(Ui.RUBY_US.battleTilesBytes / 32, 256, "256 tiles decompressed")

eq(Ui.RUBY_US.dialogGfxBytes / 32, Ui.DIALOG_TILES,
  "message_box.4bpp is 14 tiles")

-- text_window.c sDialogueFrameTilemap, including the GBA flip bits that
-- mirror the corners rather than storing them twice.
eq(#Ui.DIALOG_TILEMAP, 5, "dialogue template is 5 rows")
eq(#Ui.DIALOG_TILEMAP[1], 7, "and 7 columns")
eq(Ui.DIALOG_TILEMAP[2][6], 0x040B, "top-right corner is tile 11 h-flipped")
eq(Ui.DIALOG_TILEMAP[4][1], 0x080B, "bottom-left is tile 11 v-flipped")
eq(Ui.DIALOG_TILEMAP[4][6], 0x0C0B, "bottom-right flips both ways")

-- A cache written before the chrome was extracted must not look playable.
local ruby = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.ruby
local wanted = {
  ["data/generated/ui.lua"] = false,
  ["assets/generated/ui/window_frames.png"] = false,
}
for _, path in ipairs(ruby) do
  if wanted[path] ~= nil then wanted[path] = true end
end
for path, present in pairs(wanted) do
  check(present, path .. " is required for ruby caches")
end
-- The exact revision is pinned in ruby_version_test; here it only matters
-- that ruby has a marker of its own, so a cache predating the UI import
-- cannot satisfy it.
check(CacheContract.VERSION_FORMAT.ruby:find("ruby%d+"),
  "ruby caches carry their own versioned marker")
check(CacheContract.VERSION_FORMAT.ruby ~= CacheContract.FORMAT,
  "which is distinct from the shared one")

-- The runtime maps a rect onto the 3x3 block: index 0 for the first row or
-- column, 2 for the last, 1 for everything between.
local g = Game3.new()
eq(g:windowFrameStyle(), 0, "no options table yet means frame 1")
g.options = { windowFrame = 7 }
eq(g:windowFrameStyle(), 7, "the OPTION menu FRAME setting selects a row")
g.options = { windowFrame = 99 }
eq(g:windowFrameStyle(), 0, "out-of-range styles clamp to frame 1")
g.options = { windowFrame = -3 }
eq(g:windowFrameStyle(), 0, "negatives clamp too")

eq(Game3.WINDOW_FRAME_STYLES, Ui.FRAME_STYLES,
  "runtime and extractor agree on the style count")

-- Without a generated cache uiPic must stay nil so drawWindow falls back.
eq(g:uiPic("frames"), nil, "no ui data means no sheet")
eq(g:drawBattleBar("Message"), false, "and no battle bar either")

-- ------- battle bottom bar
--
-- LoadBattleTextboxAndBackground copies all 0x1000 bytes to one BG, so the
-- map is 64x32: two screenblocks side by side holding three 6-row bands.
eq(Ui.BATTLE_BAR_ROWS, 6, "each bottom-bar band is 6 tiles tall")
eq(Ui.BATTLE_BAR_ROWS * Ui.TILE, 48, "which is the 48px bar")
eq(Ui.BATTLE_BAR_Y, 112, "and it sits at y=112")
eq(Game3.BATTLE_BAR_Y, Ui.BATTLE_BAR_Y, "runtime agrees on the bar origin")
eq(Game3.BATTLE_BAR_H, Ui.BATTLE_BAR_ROWS * Ui.TILE, "and on its height")
local bars = Ui.BATTLE_BARS
eq(bars.message[1], 0, "the message box is in the left screenblock")
eq(bars.message[2], 14, "at rows 14..19, so it already lands at y=112")
eq(bars.actions[1], 1, "the action bar is in the right screenblock")
eq(bars.actions[2], 2, "at rows 2..7")
eq(bars.moves[1], 1, "the move bar is also in the right screenblock")
eq(bars.moves[2], 22, "at rows 22..27")
eq(Game3.BATTLE_ACTION_Y, Game3.DLG_TEXT_ROW * Game3.MENU_TILE,
  "action / message text share tile row 15")
eq(Game3.BATTLE_TEXT_INK[1], Game3.TEXT_INK[1], "battle FONT3 is the dark field ink")
eq(Game3.BATTLE_TEXT_INK[2], Game3.TEXT_INK[2], "same on all channels")
-- 0.2 was written against the old near-black approximation. The cart's ink
-- is 0x2529 = 0.29, which is still plainly dark; the property that matters
-- is that it reads against the lavender fill behind it.
check(Game3.BATTLE_TEXT_INK[1] < Game3.BATTLE_BAR_FILL[1] - 0.3,
  "so the fight menu stays dark-on-light")
eq(Game3.BATTLE_TEXT_SHADOW[1], 65 / 255, "unused white-ink shadow is pal 8")
eq(Game3.BATTLE_TEXT_SHADOW[3], 123 / 255, "the blue channel of that shadow")
eq(Game3.BATTLE_BAR_FILL[1], 213 / 255, "fill is menu.pal index 7")
eq(Game3.BATTLE_BAR_FILL[2], 205 / 255, "the lavender behind dark battle text")
eq(Ui.BATTLE_BAR_FILL[3], 213 / 255, "extractor uses the same lavender")
eq(Game3.BATTLE_BAR_FILL[1], Ui.BATTLE_BAR_FILL[1], "runtime matches extract")
eq(Game3.BATTLE_CURSOR[1], 1, "the fight cursor is menu.pal index 2")
eq(Game3.BATTLE_CURSOR[2], 0, "pure red")
check(Game3.TEXT_INK[1] < 0.5, "field FONT3 stays dark")
check(Game3.TEXT_INK[1] < Game3.TEXT_SHADOW[1] - 0.3,
  "and stays darker than the shadow under it")
eq(Game3.shadowForInk({ 1, 1, 1, 1 }), Game3.BATTLE_TEXT_SHADOW,
  "white ink still uses the dark outline")
eq(Game3.shadowForInk(Game3.BATTLE_TEXT_INK), Game3.TEXT_SHADOW,
  "dark battle ink keeps the gray 0xE outline")
eq(Game3.shadowForInk(Game3.TEXT_INK), Game3.TEXT_SHADOW,
  "dark field ink keeps the gray 0xE outline")
check(Game3.FONT_INK_SHADER:find("shadowColor", 1, true),
  "the FONT3 shader colors 0xE separately from 0xF")
check(not Game3.FONT_INK_SHADER:find("1.0 - t.r", 1, true),
  "and does not flatten the shadow into the ink")
local inkGame = Game3.new()
check(inkGame:fontInkShader(), "stub newShader yields an ink shader handle")
for name, spec in pairs(bars) do
  check(spec[2] + Ui.BATTLE_BAR_ROWS <= 32,
    name .. " band fits inside its 32-row screenblock")
end

-- ------- healthboxes
eq(Ui.RUBY_US.healthboxPlayerGfx, 0xD1F52C, "gBattleWindowLargeGfx")
eq(Ui.RUBY_US.healthboxEnemyGfx, 0xD1F7E0, "gBattleWindowSmallGfx")
eq(Ui.HEALTHBOX.player.halfH, 64, "the player half is 64x64 (it has the EXP bar)")
eq(Ui.HEALTHBOX.enemy.halfH, 32, "the opponent half is 64x32")
for kind, spec in pairs(Ui.HEALTHBOX) do
  eq(spec.halfW, 64, kind .. " healthbox halves are 64px wide")
  check(Ui.RUBY_US[spec.off] ~= nil, kind .. " healthbox has a ROM offset")
end

-- Both frames assemble to 128px wide, and the runtime must place them so
-- they stay on screen.
for _, side in ipairs({ "player", "enemy" }) do
  local L = Game3.HEALTHBOX_LAYOUT[side]
  check(L, side .. " has a healthbox layout")
  local xy = Game3.HEALTHBOX_XY[side]
  check(xy[1] + 128 - 8 <= Game3.SCREEN_W + 20,
    side .. " healthbox frame is placed on screen")
  check(L.nameX < L.levelX, side .. " name is left of the level digits")
end
-- The cart bakes "Lv" into the art, so only digits are drawn over it.
eq(Game3.HEALTHBOX_LAYOUT.player.levelX, 82, "player digits follow the baked Lv")
eq(Game3.HEALTHBOX_LAYOUT.enemy.levelX, 74, "opponent digits follow theirs")

-- ------- move selection is a 2x2 grid, not a list
--
-- battle_controller_player.c: bit 0 is the column, bit 1 the row, and a
-- press only lands on a slot that holds a move. It never wraps.
local step = Game3.moveCursorStep
eq(step(0, "right", 4), 1, "right flips bit 0")
eq(step(1, "left", 4), 0, "left clears it")
eq(step(0, "down", 4), 2, "down flips bit 1")
eq(step(2, "up", 4), 0, "up clears it")
eq(step(3, "right", 4), 3, "already in the right column, so no move")
eq(step(0, "left", 4), 0, "already in the left column")
eq(step(0, "up", 4), 0, "already on the top row")
eq(step(3, "down", 4), 3, "already on the bottom row")
-- With fewer than four moves the empty slots are unreachable.
eq(step(0, "down", 2), 0, "two moves means no bottom row")
eq(step(0, "right", 2), 1, "but the second move is still reachable")
eq(step(1, "down", 3), 1, "slot 3 is empty with three moves")
eq(step(0, "down", 3), 2, "slot 2 is not")
eq(step(0, "right", 1), 0, "a single move pins the cursor")
for c = 0, 3 do
  for _, dir in ipairs({ "left", "right", "up", "down" }) do
    local got = step(c, dir, 4)
    check(got >= 0 and got < 4, "cursor stays in range from " .. c .. " " .. dir)
    check(got == c or math.abs(got - c) == 1 or math.abs(got - c) == 2,
      "a press moves at most one grid step from " .. c .. " " .. dir)
  end
end

-- SELECT reorder: HandleAction_ChooseMove + sub_802CA60.
eq(Game3.moveSwapDest(0), 1, "SELECT on slot 0 aims at slot 1")
eq(Game3.moveSwapDest(1), 0, "SELECT on any other slot aims at 0")
eq(Game3.moveSwapDest(2), 0, "including bottom-left")
eq(Game3.moveSwapDest(3), 0, "and bottom-right")

local Input = require("src.core.Input")
local g = Game3.new()
local tackle = { name = "TACKLE", id = 33, pp = 35, maxPp = 35, type = 0 }
local growl = { name = "GROWL", id = 45, pp = 40, maxPp = 40, type = 0 }
local whip = { name = "TAIL WHIP", id = 39, pp = 30, maxPp = 30, type = 0 }
local player = {
  name = "ZIGZAGOON", hp = 20, maxHp = 20,
  moves = { tackle, growl, whip },
}
g.battle = {
  kind = "fight", fightCursor = 0, player = player,
  enemy = { name = "POOCHYENA", hp = 20, maxHp = 20 },
}
check(g:swapMoveSlots(player, 0, 2), "slots 0 and 2 swap")
eq(player.moves[1], whip, "Tail Whip is now first")
eq(player.moves[3], tackle, "Tackle moved to slot 3")
eq(player.moves[1].pp, 30, "PP travelled with the move")
check(not g:swapMoveSlots(player, 0, 0), "same-slot is a nop")

local function press(key)
  local old = Input.wasPressed
  Input.wasPressed = function(_, k) return k == key end
  g:stepBattle()
  Input.wasPressed = old
end

g:swapMoveSlots(player, 0, 2)
eq(player.moves[1], tackle, "restored Tackle first")
press("select")
eq(g.battle.moveSwap, 1, "SELECT marks dest as slot 1")
eq(g.battle.fightCursor, 0, "source cursor stays")
press("down")
eq(g.battle.moveSwap, 1, "down from slot 1 with 3 moves cannot land on empty 3")
press("left")
eq(g.battle.moveSwap, 0, "left lands dest on the source")
press("b")
eq(g.battle.moveSwap, nil, "B cancels without swapping")
eq(player.moves[1], tackle, "order unchanged")
eq(g.battle.kind, "fight", "and stays on the move grid")

press("select")
press("a")
eq(player.moves[1], growl, "A confirms the swap")
eq(player.moves[2], tackle, "Tackle is now second")
eq(g.battle.fightCursor, 1, "cursor follows the dest")
eq(g.battle.moveSwap, nil, "swap mode ends")
eq(g.battle.kind, "fight", "A does not pick the move yet")

g.battle.fightCursor = 0
press("select")
press("select")
eq(player.moves[1], tackle, "SELECT confirms the same way as A")
eq(player.moves[2], growl, "Growl is second again")

g.battle.player.moves = { { name = "TACKLE", pp = 35 } }
g.battle.fightCursor = 0
g.battle.moveSwap = nil
press("select")
eq(g.battle.moveSwap, nil, "one move cannot start a swap")

-- The dialogue box, and a DELIBERATE deviation from the cart's geometry.
-- text_window.c DrawDialogueFrame draws height + 2 rows from
-- STD_DLG_FRAME_TOP 14, so Ruby's box is rows 14..19 with a 4-row interior
-- (y 120..152), and Contest_StartTextPrinter places the text at tile
-- (2, 15). Two 16px lines fill that interior exactly, edge to edge -- the
-- second line rests on the frame. We give the box one extra row at the top
-- and centre the text in the taller interior.
;(function()
local Game3 = require("src.core.Game3")
local T = Game3.MENU_TILE
local interiorTop = (Game3.DLG_FRAME_TOP + 1) * T
local interiorBottom = Game3.DLG_FRAME_BOTTOM * T
local textTop = Game3.dialogueTextY()
local textBottom = textTop + Game3.MSG_LINES * Game3.MSG_LINE_H

eq(Game3.DLG_FRAME_TOP, 14, "STD_DLG_FRAME_TOP")
eq(Game3.DLG_FRAME_BOTTOM, 19, "and height + 2 rows puts the last one at 19")
eq(interiorBottom - interiorTop, 32, "a four-row interior")
eq(Game3.MSG_LINES * Game3.MSG_LINE_H, 32, "which two 16px lines fill")
eq(textTop, 15 * T, "text starts at Text_InitWindow's 8 * 15")
eq(Game3.DLG_TEXT_COL, 2, "at the cart's column 2")
eq(Game3.dialogueTextY(), 15 * T, "so the helper reproduces the cart exactly")

-- The cells fill the interior, but the GLYPHS do not: FONT3 ink runs from
-- about row 3 to row 13 of the 16px cell, so the second line clears the
-- frame by roughly 2px, near enough the ~3px above the first line. This is
-- the cart's own spacing, not a flush edge.
eq(textBottom, interiorBottom, "the line CELLS meet the frame")
eq(Game3.DLG_TEXT_PAD_Y, 0, "and no padding is added on top of the cart")

-- ...and drawDialogue actually uses it, rather than a copy of the old row.
local g = Game3.new()
local ys = {}
g.setTextInk = function() end
g.drawText = function(_, _, _, y) ys[#ys + 1] = y end
g.printedText = function(_, box) return box.text end
g.font3WidthTable = function() return nil end
g.dialogueHasMore = function() return false end
g:drawDialogue({ text = "HELLO" })
check(#ys >= 1, "the box drew a line")
eq(ys[1], Game3.dialogueTextY(), "drawDialogue starts at the centred y")

-- The battle action menu keeps its own fixed y and does not follow.
eq(Game3.BATTLE_ACTION_Y, Game3.DLG_TEXT_ROW * T,
  "FIGHT/BAG/POKeMON/RUN still sit at the cart's row 15")
end)()


-- ------------------------------------------------- battle bottom bars
--
-- battle_bg.c LoadBattleTextboxAndBackground puts gBattleTextboxTiles at
-- charbase 0 and gBattleTextboxTilemap at BG0 screenbase 24. BG0CNT 0x9800
-- has size bits 2, which for a text BG is 256x512 -- NOT 512x256 -- so the
-- second screen block sits BELOW the first. That is what the only three
-- scroll values the battle uses reach: gBattle_BG0_Y of 0, 160 and 320.
-- Each layout puts its 240x48 bar at y 112, i.e. 14 rows into its viewport.
eq(Ui.RUBY_US.battleTilesLz, 0xD00000, 'menu.4bpp.lz')
eq(Ui.RUBY_US.battlePalLz, 0xD004E0, 'menu.gbapal.lz')
eq(Ui.RUBY_US.battleMap, 0xD00524, 'menu_map.bin')
eq(Ui.RUBY_US.battleMapBytes, 4096, '32x64 entries')
eq(Ui.BATTLE_BAR_Y, 112, 'the bar sits at y 112 in every layout')
eq(Ui.BATTLE_BAR_ROWS, 6, 'and is six rows tall')
eq(Ui.BATTLE_BARS.message[1], 0, 'gBattle_BG0_Y 0 is the first block')
eq(Ui.BATTLE_BARS.message[2], 14, 'row 14 of it')
eq(Ui.BATTLE_BARS.actions[1], 1, 'gBattle_BG0_Y 160 crosses into block 1')
eq(Ui.BATTLE_BARS.actions[2], 2, 'at row 2')
eq(Ui.BATTLE_BARS.moves[1], 1, 'gBattle_BG0_Y 320 is block 1')
eq(Ui.BATTLE_BARS.moves[2], 22, 'at row 22')

-- drawBattleBar shipped hard-disabled with a bare `return false`, on the
-- grounds that the extracted interior was the wrong colour. The extracted
-- tiles are byte-identical to the decomp menu.png and the palette matches
-- its PLTE, so the teal IS the cart; the lavender it was measured against
-- was only menu.pal index 7, picked out for the placeholder panel.
;(function()
  local g = Game3.new()
  local drawn = {}
  g.uiPic = function(_, name) return { name = name } end
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, x, y)
    drawn[#drawn + 1] = { img and img.name, x, y }
  end
  local ok = g:drawBattleBar('Actions')
  love.graphics.draw = realDraw
  check(ok, 'the action bar draws the cart art when it is in the cache')
  eq(#drawn, 1, 'exactly one blit')
  eq(drawn[1][1], 'battleActions', 'off the actions bar')
  eq(drawn[1][2], 0, 'at x 0')
  eq(drawn[1][3], 112, 'and y 112')
end)()

;(function()
  local g = Game3.new()
  g.uiPic = function() return nil end
  check(not g:drawBattleBar('Message'),
    'and reports failure without the art so the caller can fall back')
end)()

-- ------------------------------------------------------ healthbox bars
--
-- battle_interface.c CalcBarFilledPixels: the bar is `tiles` tiles wide and
-- each tile holds 0..8 filled pixels. The division TRUNCATES -- the cart's
-- <<8 branch is only for the animated in-between values.
eq(Game3.HP_BAR_TILES, 6, 'sub_8045D58 walks six HP tiles')
eq(Game3.EXP_BAR_TILES, 8, 'and eight EXP tiles')
eq(Game3.HP_ELEMENT_GREEN, 3, 'GetHealthboxElementGfxPtr(3)')
eq(Game3.EXP_ELEMENT, 0xC, 'GetHealthboxElementGfxPtr(0xC)')
eq(Game3.HP_ELEMENT_YELLOW, 0x2F, 'GetHealthboxElementGfxPtr(0x2F)')
eq(Game3.HP_ELEMENT_RED, 0x38, 'GetHealthboxElementGfxPtr(0x38)')

;(function()
  local e, filled = Game3.barFilledEighths(27, 34, 6)
  eq(filled, 38, '27 of 34 over 48 pixels truncates to 38')
  eq(table.concat(e, ','), '8,8,8,8,6,0', 'spread eight pixels at a time')
  eq(Game3.hpBarElementBase(filled), Game3.HP_ELEMENT_GREEN, 'reads green')

  -- 7/34 is 9.88 pixels. Truncating gives 9, which the cart calls RED;
  -- rounding would give 10, which is yellow. That is the case that tells
  -- the two apart, so it is the one worth pinning.
  local e2, f2 = Game3.barFilledEighths(7, 34, 6)
  eq(f2, 9, '7 of 34 truncates to 9 pixels, it does not round to 10')
  eq(table.concat(e2, ','), '8,1,0,0,0,0', 'one pixel into tile two')
  eq(Game3.hpBarElementBase(f2), Game3.HP_ELEMENT_RED, 'nine pixels is red')

  local _, f3 = Game3.barFilledEighths(8, 34, 6)
  eq(f3, 11, '8 of 34 is eleven pixels')
  eq(Game3.hpBarElementBase(f3), Game3.HP_ELEMENT_YELLOW, 'which is yellow')

  -- alive but rounding to nothing still lights a single pixel
  local e4, f4 = Game3.barFilledEighths(1, 400, 6)
  eq(f4, 1, 'alive but under a pixel still lights one')
  eq(e4[1], 1, 'in the first tile')
  eq(Game3.hpBarElementBase(f4), Game3.HP_ELEMENT_RED, 'and it is red')

  local e5, f5 = Game3.barFilledEighths(0, 34, 6)
  eq(f5, 0, 'a fainted mon shows nothing')
  eq(table.concat(e5, ','), '0,0,0,0,0,0', 'every tile empty')

  local _, f6 = Game3.barFilledEighths(34, 34, 6)
  eq(f6, 48, 'full health fills all six tiles')

  eq(Game3.hpBarElementBase(0x19), Game3.HP_ELEMENT_GREEN,
    'green starts just above 0x18')
  eq(Game3.hpBarElementBase(0x18), Game3.HP_ELEMENT_YELLOW,
    'and 0x18 itself is still yellow')
  eq(Game3.hpBarElementBase(10), Game3.HP_ELEMENT_YELLOW, 'ten is yellow')
  eq(Game3.hpBarElementBase(9), Game3.HP_ELEMENT_RED, 'nine is red')
end)()

-- The healthbox carries BOTH palettes: window.gbapal and hpbar.gbapal. The
-- HP ramp only reads right on hpbar (indices A/B are its greens) and the EXP
-- ramp only on window -- the decomp's hpbar.png and expbar.png carry exactly
-- those two palettes. Drawn on hpbar the EXP ramp comes out peach, not cyan.
eq(Ui.RUBY_US.windowPal, 0xD1212C, 'window.gbapal')
eq(Ui.RUBY_US.hpBarPal, 0xD1214C, 'hpbar.gbapal')

-- ------------------------------------------------------ battle cursors
--
-- sub_802E3E4 / sub_802E39C build the cursor with sub_814A958, whose width
-- argument is 0x2A for the action menu and 0x48 for the moves; the pieces
-- are shape 2 size 0, i.e. 8x16, so it stands 16 tall. It is a wide outline,
-- not the field triangle. Positions are the pixel pairs at
-- gUnknown_081FAE91 and gUnknown_081FAE89.
eq(Game3.BATTLE_ACTION_CURSOR_W, 0x2A, 'sub_814A958(0x2A)')
eq(Game3.BATTLE_MOVE_CURSOR_W, 0x48, 'sub_814A958(0x48)')
eq(Game3.BATTLE_CURSOR_H, 16, 'built from 8x16 subsprites')
;(function()
  local a = Game3.BATTLE_ACTION_SLOTS
  eq(#a, 4, 'four action slots')
  eq(a[1][1] .. ',' .. a[1][2], '144,120', 'FIGHT')
  eq(a[2][1] .. ',' .. a[2][2], '190,120', 'BAG')
  eq(a[3][1] .. ',' .. a[3][2], '144,136', 'POKeMON')
  eq(a[4][1] .. ',' .. a[4][2], '190,136', 'RUN')
  local m = Game3.BATTLE_MOVE_SLOTS
  eq(m[1][1] .. ',' .. m[1][2], '8,120', 'first move')
  eq(m[2][1] .. ',' .. m[2][2], '88,120', 'second')
  eq(m[3][1] .. ',' .. m[3][2], '8,136', 'third')
  eq(m[4][1] .. ',' .. m[4][2], '88,136', 'fourth')
end)()

-- The player healthbox art is only opaque out to x=104, so right-aligning
-- the HP numbers at 112 hung the second number off the box.
check(Game3.HEALTHBOX_LAYOUT.player.hpTextRight <= 104,
  'HP numbers stay inside the frame art')
eq(Game3.HEALTHBOX_LAYOUT.player.barW, 48, 'six element tiles of HP bar')
eq(Game3.HEALTHBOX_LAYOUT.enemy.barW, 48, 'the enemy bar is the same six')
eq(Game3.HEALTHBOX_LAYOUT.player.expW, 64, 'eight element tiles of EXP bar')


-- --------------------------------------------------- healthbox level
--
-- The cart BAKES "Lv" into the healthbox frame art and sub_8043FC0 renders
-- only the digits beside it. Measured on the extracted frames the label sits
-- at x 65..72 (enemy) and 73..80 (player), so levelX already points at the
-- first digit. Painting over the label and redrawing "Lv<n>" 14px left of
-- levelX put the enemy level at x 68 -- exactly where a nine-character name
-- ends, so POOCHYENA and Lv9 ran together with no gap at all.
;(function()
  local g = Game3.new()
  local drawn = {}
  g.uiPic = function(_, name) return { name = name, getDimensions = function() return 128, 64 end } end
  g.drawText = function(_, t, x, y) drawn[#drawn + 1] = { tostring(t), x, y } end
  g.menuArt = function() return nil end
  g.monGender = function() return nil end
  g.drawHpBarTiles = function() return true end
  g.drawExpBarTiles = function() return true end
  g.healthboxStatusKey = function() return nil end
  local mon = { name = "POOCHYENA", level = 9, hp = 14, maxHp = 26 }
  g:drawHealthbox(mon, 8, 8, "enemy")
  local lv
  for _, d in ipairs(drawn) do if d[1] == "9" then lv = d end end
  check(lv ~= nil, "the enemy level draws as bare digits, not Lv9")
  eq(lv[2], 8 + Game3.HEALTHBOX_LAYOUT.enemy.levelX,
    "and sits at levelX, beside the frame art's baked Lv")
  local name
  for _, d in ipairs(drawn) do if d[1] == "POOCHYENA" then name = d end end
  local nameEnd = name[2] + Game3.textWidth("POOCHYENA")
  check(lv[2] > nameEnd,
    "so the longest early-route name still clears the level digits")
end)()


-- ------------------------------------------------- naming screen sheets
--
-- naming_screen.c LoadSpriteSheets(gUnknown_083CE6A0): twelve OBJ sheets as
-- {ptr, size, tag}. Sizes and tags are pinned against the decomp table, and
-- each sheet's width comes from its sprite's OAM rather than being guessed --
-- the tiles are 1D, so a wrong width scrambles the art.
eq(Ui.NAMING_SHEET_TABLE, 0x3CE6A0, "gUnknown_083CE6A0")
eq(Ui.NAMING_PAL_TABLE, 0x3CE708, "gUnknown_083CE708")
eq(#Ui.NAMING_SHEETS, 12, "twelve sheets before the terminator")
;(function()
  local want = {
    { "back_button", 5, 4 }, { "ok_button", 5, 4 },
    { "change_keyboard_box", 5, 4 }, { "change_keyboard_button", 4, 1 },
    { "lower_text", 3, 4 }, { "upper_text", 3, 4 }, { "others_text", 3, 4 },
    { "cursor", 2, 5 }, { "active_cursor_small", 2, 5 },
    { "active_cursor_big", 2, 5 },
    { "right_pointing_triangle", 1, 3 }, { "underscore", 1, 3 },
  }
  for i, w in ipairs(want) do
    local got = Ui.NAMING_SHEETS[i]
    eq(got.name, w[1], ("sheet %d is %s"):format(i - 1, w[1]))
    eq(got.cols, w[2], ("%s is %d tiles across"):format(w[1], w[2]))
    eq(got.pal, w[3], ("%s takes gNamingScreenPalettes[%d]"):format(w[1], w[3]))
  end
end)()

-- The change-keyboard button is the one the old baked PNG got wrong: it
-- stored the sprite inverted, so index 0 (which OBJ hardware always treats as
-- transparent) came out white and the chip came out as a hole. Palette 1's
-- entry 15 is the lavender it should be.
eq(Ui.NAMING_SHEETS[4].pal, 1,
  "the change-keyboard button is on palette 1, not the white palette 0")

-- ------------------------------------------- cart art stays out of git
--
-- pack_love.sh only excludes assets/generated, so a PNG baked anywhere else
-- under assets/ ships in the APK. The twelve OBJ sheets used to live in
-- assets/naming, and so did the four BG screens and the two box icons --
-- the last pokeruby art in the tree. All of it is read from the cart now,
-- so the directory itself must be gone: a file that reappears there ships.
;(function()
  local baked = {}
  local function check(path)
    local f = io.open(path, "r")
    if f then f:close(); baked[#baked + 1] = path end
  end
  for _, spec in ipairs(Ui.NAMING_SHEETS) do
    check("assets/naming/" .. spec.name .. ".png")
  end
  for _, spec in ipairs(Ui.NAMING_SCREENS) do
    check("assets/naming/" .. spec.name .. ".png")
  end
  check("assets/naming/menu.png")
  check("assets/naming/pc_icon/0.png")
  check("assets/naming/pc_icon/1.png")
  eq(#baked, 0,
    "nothing is baked outside assets/generated: " .. table.concat(baked, " "))
end)()

-- ...and what replaces them is read at the offsets naming_screen.c uses.
-- The stride is the part that is not guessable: sub_80B7698 walks a keyboard
-- page 30 entries to the row and sub_80B76E0 walks the frame 32, and reading
-- the frame at 30 drifts two tiles a row into a diagonal band.
eq(#Ui.NAMING_SCREENS, 4, "three keyboard pages and the frame")
;(function()
  local byName = {}
  for _, spec in ipairs(Ui.NAMING_SCREENS) do byName[spec.name] = spec end
  eq(byName.bg_stripes.map, 0xE86258, "the frame is gUnknown_08E86258...")
  eq(byName.bg_stripes.stride, 32, "...at 32 entries to the row")
  eq(byName.keyboard_lower.map, 0x3CE748, "lower is gUnknown_083CE748...")
  eq(byName.keyboard_lower.stride, 30, "...at 30")
  eq(byName.keyboard_upper.map, 0x3CEBF8, "upper is gUnknown_083CEBF8")
  eq(byName.keyboard_others.map, 0x3CF0A8, "others is gUnknown_083CF0A8")
  eq(Ui.NAMING_BG_GFX, 0xE85998, "all four paint from gNamingScreenMenu_Gfx")
  eq(Ui.NAMING_BG_GFX_SIZE, 0x800, "which is 64 tiles, as DmaCopy16 says")
  eq(#Ui.NAMING_PC_ICONS, 2, "and the box icon has two frames")
  eq(Ui.NAMING_PC_ICONS[1], 0x3CE094, "frame 0")
  eq(Ui.NAMING_PC_ICONS[2], 0x3CE154, "frame 1, one 2x3 sheet later")
  eq(Ui.NAMING_PC_ICONS[2] - Ui.NAMING_PC_ICONS[1],
    Ui.NAMING_PC_COLS * Ui.NAMING_PC_ROWS * Ui.TILE_BYTES,
    "they sit back to back in the ROM")
end)()


-- --------------------------------------------------- scroll indicators
--
-- menu_helpers.c: gSpriteTemplate_83E59D0 is H_RECTANGLE and covers BOTH
-- vertical arrows (anim frame 0 up, frame 1 down), so its two tiles sit side
-- by side for 16x8. The horizontal pair is V_RECTANGLE, so ITS two tiles
-- stack for 8x16 -- read side by side they render as diagonal shards, which
-- is what a plain row-major blit produces.
eq(Ui.SCROLL_ARROW_PAL, 0x3E5948, "Palette_3E5948")
eq(#Ui.SCROLL_ARROWS, 4, "up, down, left, right")
;(function()
  local want = {
    { "up", 0x3E5808, 2, 1 }, { "down", 0x3E5848, 2, 1 },
    { "left", 0x3E5888, 1, 2 }, { "right", 0x3E58C8, 1, 2 },
  }
  for i, w in ipairs(want) do
    local got = Ui.SCROLL_ARROWS[i]
    eq(got.name, w[1], ("arrow %d is %s"):format(i, w[1]))
    eq(got.off, w[2], ("%s comes from 0x%X"):format(w[1], w[2]))
    eq(got.w .. "x" .. got.h, w[3] .. "x" .. w[4],
      ("%s is %dx%d tiles"):format(w[1], w[3], w[4]))
  end
end)()


-- ------------------------------------------------- menu text colours
--
-- The window templates ask for foreground 1 and shadow 8 of their palette,
-- and ApplyColors_ShadowedFont writes those as 0x2529 and 0x675A. A hardware
-- capture of the bag confirms it: its list text uses exactly three colours,
-- 4A494A ink and D6D2CE shadow over the panel.
--
-- The shadow is LIGHTER than the ink. Ours was a near-black ink under a
-- DARKER grey shadow, which doubled each glyph's apparent weight -- menu text
-- came out blobby and over-bold everywhere, not just in the bag.
;(function()
  local function hex(c)
    return ('%02X%02X%02X'):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5,
      c[3] * 255 + 0.5)
  end
  eq(hex(Game3.TEXT_INK), '4A494A', 'menu ink is 0x2529')
  eq(hex(Game3.TEXT_SHADOW), 'D6D2CE', 'and its shadow 0x675A')
  local ink = Game3.TEXT_INK[1] + Game3.TEXT_INK[2] + Game3.TEXT_INK[3]
  local sh = Game3.TEXT_SHADOW[1] + Game3.TEXT_SHADOW[2] + Game3.TEXT_SHADOW[3]
  check(sh > ink, 'the shadow is lighter than the ink, not darker')
  eq(hex(Game3.shadowForInk(Game3.TEXT_INK)), 'D6D2CE',
    'and dark ink resolves to it')
end)()

S.finish()
