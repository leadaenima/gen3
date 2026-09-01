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
eq(Game3.BATTLE_TEXT_INK[1], 74 / 255, "battle FONT3 is gFontDefaultPalette 1")
eq(Game3.BATTLE_TEXT_INK[2], 74 / 255, "the same gray on all channels")
check(Game3.BATTLE_TEXT_INK[1] < 0.4, "so the fight menu stays dark-on-light")
eq(Game3.BATTLE_TEXT_SHADOW[1], 65 / 255, "unused white-ink shadow is pal 8")
eq(Game3.BATTLE_TEXT_SHADOW[3], 123 / 255, "the blue channel of that shadow")
eq(Game3.BATTLE_BAR_FILL[1], 213 / 255, "fill is menu.pal index 7")
eq(Game3.BATTLE_BAR_FILL[2], 205 / 255, "the lavender behind dark battle text")
eq(Ui.BATTLE_BAR_FILL[3], 213 / 255, "extractor uses the same lavender")
eq(Game3.BATTLE_BAR_FILL[1], Ui.BATTLE_BAR_FILL[1], "runtime matches extract")
eq(Game3.BATTLE_CURSOR[1], 1, "the fight cursor is menu.pal index 2")
eq(Game3.BATTLE_CURSOR[2], 0, "pure red")
check(Game3.TEXT_INK[1] < 0.2, "field FONT3 stays dark")
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

S.finish()
