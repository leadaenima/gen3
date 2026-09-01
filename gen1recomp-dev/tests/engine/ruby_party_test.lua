-- Ruby party menu: where the chrome lives in the cart, and the palette
-- and animation rules that party_menu.c drives the screen with. See
-- RomExtractorGen3Party.lua and RomExtractorGen3Icons.lua.
-- Offsets and pure logic only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_party_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby party menu")
local check = S.check
local eq = S.eq

local Party = require("src.import.RomExtractorGen3Party")
local Icons = require("src.import.RomExtractorGen3Icons")
local CacheContract = require("src.import.CacheContract")
local Game3 = require("src.core.Game3")

-- ------- 1. Where the graphics group sits
-- graphics.c declares the five party menu symbols consecutively, so they
-- are one run of LZ77 streams. Walking that chain in the cart lands here,
-- and three separate things agree it is the right place: the palette is
-- the 0x160 bytes LoadPartyMenuGraphics asks for, the tile sheet is
-- exactly big enough for the highest tile the box arrays name, and the
-- status icons land where char base 0x4000 puts tile 0x18C.
eq(Party.RUBY_US.miscGfx, 0xE71354, "gPartyMenuMisc_Gfx")
eq(Party.RUBY_US.miscPal, 0xE716A0, "gPartyMenuMisc_Pal")
eq(Party.RUBY_US.miscTilemap, 0xE71788, "gPartyMenuMisc_Tilemap")
eq(Party.RUBY_US.hpBarGfx, 0xE71894, "gPartyMenuHpBar_Gfx")
eq(Party.RUBY_US.orderTextGfx, 0xE71934, "gPartyMenuOrderText_Gfx")
eq(Party.RUBY_US.statusGfx, 0xE72860, "gStatusGfx_Icons")
eq(Party.RUBY_US.statusPal, 0xE72A50, "gStatusPal_Icons")

eq(Party.RUBY_US.miscPalBytes, 0x160,
  "LoadPartyMenuGraphics loads 0x160 bytes of palette")
eq(Party.RUBY_US.miscPalBytes / 32, Party.PAL_COUNT,
  "which is 11 sub-palettes")
eq(Party.RUBY_US.miscGfxBytes / Party.TILE_BYTES, Party.TILE_COUNT,
  "the sheet is 116 tiles")

-- ------- 2. The box shapes fit the sheet
local function maxTile(shape)
  local top = 0
  for r = 1, #shape do
    for c = 1, #shape[r] do
      if shape[r][c] > top then top = shape[r][c] end
    end
  end
  return top
end

eq(#Party.LEAD_BOX, 7, "the lead box is 7 rows")
eq(#Party.LEAD_BOX[1], 11, "and 11 columns")
eq(#Party.SLOT_BOX, 3, "a slot box is 3 rows")
eq(#Party.SLOT_BOX[1], 19, "and 19 columns")
eq(#Party.EMPTY_BOX, 3, "an empty slot matches its footprint")
eq(#Party.EMPTY_BOX[1], 19, "in both directions")

eq(maxTile(Party.SLOT_BOX), 0x73, "gUnknown_08376A25 tops out at 0x73")
check(maxTile(Party.LEAD_BOX) < Party.TILE_COUNT, "lead box fits the sheet")
check(maxTile(Party.SLOT_BOX) < Party.TILE_COUNT, "slot box fits the sheet")
check(maxTile(Party.EMPTY_BOX) < Party.TILE_COUNT, "empty box fits too")
eq(maxTile(Party.SLOT_BOX) + 1, Party.TILE_COUNT,
  "and the sheet is sized to exactly that tile, nothing spare")

-- ------- 3. Layout
-- Every box has to land inside the 30x20 screen, and the slot boxes have
-- to stack without overlapping.
for slot = 1, 6 do
  local at = Party.BOX_AT[slot]
  local shape = slot == 1 and Party.LEAD_BOX or Party.SLOT_BOX
  check(at[1] >= 0 and at[1] + #shape[1] <= 30,
    "box " .. slot .. " fits horizontally")
  check(at[2] >= 0 and at[2] + #shape <= 20,
    "box " .. slot .. " fits vertically")
end
for slot = 3, 6 do
  eq(Party.BOX_AT[slot][2] - Party.BOX_AT[slot - 1][2], 3,
    "slot boxes are stacked three rows apart")
end

-- gUnknown_08376858 converted from VRAM addresses: each bar is preceded by
-- its two "HP" label tiles and followed by the end cap, and that whole run
-- has to sit inside the box it belongs to.
eq(#Party.HP_BAR_AT, 6, "one HP bar per slot")
for slot = 1, 6 do
  local bar = Party.HP_BAR_AT[slot]
  local box = Party.BOX_AT[slot]
  local shape = slot == 1 and Party.LEAD_BOX or Party.SLOT_BOX
  local left = bar[1] - Party.HP_LABEL_TILES
  local right = bar[1] + Party.HP_BAR_TILES
  check(left > box[1], "bar " .. slot .. " label starts inside the box")
  eq(right, box[1] + #shape[1] - 1,
    "bar " .. slot .. " cap lands on the box's last column")
  check(bar[2] >= box[2] and bar[2] < box[2] + #shape,
    "bar " .. slot .. " is on a row of its own box")
end

-- The lead's icon is the only one that starts at the screen edge.
eq(Party.ICON_AT[1][1], 0, "the lead icon sits flush left")
for slot = 2, 6 do
  eq(Party.ICON_AT[slot][1], 88, "slot icons share a column")
end
for slot = 3, 6 do
  eq(Party.ICON_AT[slot][2] - Party.ICON_AT[slot - 1][2], 24,
    "and are spaced a box apart")
end

-- The nickname clears the icon in every slot.
for slot = 1, 6 do
  check(Party.NAME_AT[slot][1] * 8 >= Party.ICON_AT[slot][1] + Party.ICON_SIZE,
    "nickname " .. slot .. " starts right of the icon")
end

-- ------- 4. Status icons
-- gStatusGfx_Icons is 28 tiles, four per condition.
eq(Party.RUBY_US.statusGfxBytes / Party.TILE_BYTES, 28, "28 status tiles")
eq(#Party.STATUS_ORDER * Party.STATUS_TILES, 28,
  "which is four tiles for each of the seven conditions")
eq(Party.STATUS_ORDER[1], "psn", "PSN comes first")
eq(Party.STATUS_ORDER[7], "faint", "FNT comes last")

-- ------- 5. A box's state is its palette
-- sub_806BF24: fainted swaps the base colour, the cursor adds four.
local g = setmetatable({}, { __index = Game3 })
local art = { palNormal = 3, palFainted = 5, palSelected = 4 }
local healthy = { hp = 20, maxHp = 20 }
local fainted = { hp = 0, maxHp = 20 }
eq(g:partyBoxPalette(art, healthy, false), 3, "healthy and unselected")
eq(g:partyBoxPalette(art, healthy, true), 7, "healthy under the cursor")
eq(g:partyBoxPalette(art, fainted, false), 5, "fainted and unselected")
eq(g:partyBoxPalette(art, fainted, true), 9, "fainted under the cursor")
eq(g:partyBoxPalette(art, nil, false), 3, "an empty slot uses the base colour")

-- ------- 6. GetHPBarLevel
eq(g:hpBarLevel(20, 20), 3, "full health is level 3")
eq(g:hpBarLevel(15, 20), 3, "over half is still level 3")
eq(g:hpBarLevel(10, 20), 2, "exactly half is level 2")
eq(g:hpBarLevel(5, 20), 1, "a quarter is level 1")
eq(g:hpBarLevel(1, 20), 0, "nearly dead is level 0")
eq(g:hpBarLevel(0, 20), 0, "fainted is level 0")
eq(g:hpBarLevel(5, 0), 0, "a zero maximum does not divide by zero")

-- The bar's colour follows the same level.
eq(Party.HP_FILL_PAL[3], 4, "green above half")
eq(Party.HP_FILL_PAL[2], 5, "yellow at half")
eq(Party.HP_FILL_PAL[1], 6, "red below")

-- ------- 7. Icon bobbing
-- SetMonIconAnimByHP picks from sMonIconAnims, which runs fastest first;
-- the last entry repeats frame 0 so a dying mon holds still.
eq(Game3.ICON_BOB_DELAYS[1], 6, "a healthy mon bobs every 6 frames")
eq(Game3.ICON_BOB_DELAYS[4], 22, "a badly hurt one every 22")
eq(Game3.ICON_BOB_DELAYS[5], 0, "and the lowest bracket does not bob")

g.vblank = 0
eq(g:monIconFrame(healthy), 0, "frame 0 at rest")
g.vblank = 6
eq(g:monIconFrame(healthy), 1, "a full-health mon has flipped by frame 6")
g.vblank = 12
eq(g:monIconFrame(healthy), 0, "and back again by 12")
g.vblank = 6
eq(g:monIconFrame({ hp = 5, maxHp = 20 }), 0,
  "a hurt mon is still on frame 0 there, because it bobs slower")
g.vblank = 500
eq(g:monIconFrame({ hp = 1, maxHp = 20 }), 0, "the lowest bracket never flips")
eq(g:monIconFrame(nil), 0, "an empty slot has no frame")

-- ------- 8. Icons
-- gMonIconTable is indexed by internal species number, not by dex number,
-- so the table covers the 25-entry gap between Celebi and Treecko.
eq(Icons.RUBY_US.iconTable, 0x3BBD20, "gMonIconTable")
eq(Icons.RUBY_US.paletteIndices, 0x3BC400, "gMonIconPaletteIndices")
eq(Icons.COUNT, 440, "one icon per internal species slot")
eq(Icons.CELL_W, 32, "icons are 32 wide")
eq(Icons.CELL_H, 64, "and store two 32x32 frames")
eq(Icons.FRAME_H, 32, "so one frame is 32 tall")
eq(Icons.CELL_W * Icons.CELL_H / 2, 1024, "1024 bytes of 4bpp per icon")

-- ------- 9. Cache contract
local required = select(1, CacheContract.requiredFilesFor("ruby"))
local seen = {}
for _, path in ipairs(required) do seen[path] = true end
check(seen["data/generated/menus.lua"], "the menu registry is required")
check(seen[Icons.ATLAS_PATH], "so is the icon atlas")
check(seen[Party.TILES_PATH], "and the party tile atlas")
check(seen[Party.BG_PATH], "and its backdrop")
check(seen[Party.STATUS_PATH], "and the status icons")
check(seen[Party.FONT_PATH], "and the small font the levels are printed in")
check(seen[Party.ORDER_PATH], "and the sheet the Lv and gender tiles come from")
check(seen[Party.HOLD_PATH], "and the held item icons")
eq(CacheContract.formatFor("ruby"), "rom-cache-v10-ruby41:",
  "ripe berry-tree frames bump the cache marker")

-- ------- 10. Font 4, the party menu's small text
--
-- The trap here is that a type 1 font's glyph pool is not indexed by
-- character code; every lookup goes through sFontType1Map. Rendering the
-- pool directly puts lowercase where the digits belong.
eq(Party.FONT4_POOL, 0xEA6BC4, "gFont4LatinGlyphs is the sFonts slot 11 pool")
eq(Party.FONT4_MAP, 0x1E5FF0, "sFontType1Map maps characters onto that pool")
eq(Party.FONT4_BLANK_TILE, 0xD4, "tile 0xD4 is the blank")
eq(Party.FONT4_GLYPHS, 256, "one cell per character code")

local rom = S.rom and S.rom("ruby")
if rom then
  check(Party.validFont4(rom), "the font 4 tables are where we think")

  -- Character 0 is the blank in both halves, which is what makes the
  -- upper row droppable for most text.
  eq(Party.font4UpperTile(rom, 0), Party.FONT4_BLANK_TILE,
    "the null character's upper tile is blank")
  eq(Party.font4LowerTile(rom, 0), Party.FONT4_BLANK_TILE,
    "and so is its lower tile")

  -- The digits must be a contiguous run in the pool, else the map is
  -- being read at the wrong stride.
  local zero = Party.font4LowerTile(rom, 0xA1)
  for i = 0, 9 do
    eq(Party.font4LowerTile(rom, 0xA1 + i), zero + i,
      ("digit %d follows on in the pool"):format(i))
  end

  -- Levels and HP counts only ever use digits, a slash and "Lv", and the
  -- ROM prints them 8 pixels tall by copying just the lower tile row. If
  -- any of those characters needed a non-blank upper tile that would not
  -- hold and the numbers would be clipped.
  local upperNeeded = {}
  for _, code in ipairs({ 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8,
    0xA9, 0xAA, 0xBA }) do
    if Party.font4UpperTile(rom, code) ~= Party.FONT4_BLANK_TILE then
      upperNeeded[#upperNeeded + 1] = code
    end
  end
  eq(#upperNeeded, 0, "no digit or slash needs an upper tile")

  -- Widths are indexed by pool tile, not by character, so a plain
  -- character-indexed read would give nonsense. Digits are uniform.
  local widths = Party.readFont4Widths(rom)
  local w0 = widths[0xA1]
  check(w0 >= 2 and w0 <= 8, "a digit is a sane width")
  for i = 1, 9 do
    eq(widths[0xA1 + i], w0, ("digit %d is the same width as zero"):format(i))
  end
  check(widths[0xC3] < widths[0xCD], "an I is narrower than an M")
  check(widths[0xDD] < widths[0xE1], "an i is narrower than an m")
end

-- ------- 11. Order text sheet: the Lv glyph and gender symbols
--
-- PartyMenuWriteTilemap writes a bare tile id plus 0x10C and no palette
-- bits, so these draw in palette 0 regardless of the box state behind.
eq(Party.RUBY_US.orderTextGfx, 0xE71934, "gPartyMenuOrderText_Gfx")
eq(Party.RUBY_US.orderTextGfxBytes, 4096, "128 tiles of it")
eq(Party.ORDER_TILES, 128, "which is what gets rendered")
eq(Party.ORDER_TILE_LV, 0x40, "PartyMenuDoPrintLevel stamps tile 0x40")
eq(Party.ORDER_TILE_MALE, 0x42, "male is 0x42")
eq(Party.ORDER_TILE_FEMALE, 0x44, "female is 0x44")
check(Party.ORDER_TILE_LV < Party.ORDER_TILES, "the Lv tile is on the sheet")
check(Party.ORDER_TILE_FEMALE < Party.ORDER_TILES, "so is the female symbol")

-- The slash was mapped onto the hyphen, which made every HP count read
-- "20-33". CHAR_SLASH is 0xBA and CHAR_HYPHEN is 0xAE.
eq(Game3.fontCode("/"), 0xBA, "a slash is CHAR_SLASH")
eq(Game3.fontCode("-"), 0xAE, "and a hyphen is still CHAR_HYPHEN")
check(Game3.fontCode("/") ~= Game3.fontCode("-"), "they are not the same glyph")

-- ShouldHideGenderIcon suppresses the symbol for the Nidoran lines,
-- whose gender is already in the species name, unless renamed.
local g = setmetatable({}, { __index = Game3 })
function g:speciesName(id)
  if id == Game3.SPECIES_NIDORAN_M then return "NIDORAN M" end
  if id == Game3.SPECIES_NIDORAN_F then return "NIDORAN F" end
  return "PIKACHU"
end
check(g:showsGenderIcon({ species = 25, name = "PIKACHU" }),
  "an ordinary mon shows its gender")
check(not g:showsGenderIcon({ species = Game3.SPECIES_NIDORAN_M,
  name = "NIDORAN M" }), "an unnamed NIDORAN M hides it")
check(not g:showsGenderIcon({ species = Game3.SPECIES_NIDORAN_F,
  name = "NIDORAN F" }), "and so does NIDORAN F")
check(g:showsGenderIcon({ species = Game3.SPECIES_NIDORAN_M, name = "SPIKE" }),
  "but a renamed one shows it again")
check(not g:showsGenderIcon({ species = 25, name = "EGG", isEgg = true }),
  "an egg has no gender to show")

-- PartyMenuDoPrintGenderIcon switches on GetMonGender. makeMon never
-- writes mon.gender, so the icon has to go through monGender (pid vs
-- genderRatio). The switch has no MON_GENDERLESS arm.
function g:genderRatioFor(species)
  if species == Game3.SPECIES_NIDORAN_M then return 0 end
  if species == Game3.SPECIES_NIDORAN_F then return 0xFE end
  if species == Game3.SPECIES_DITTO then return 0xFF end
  return 127
end
eq(g:partyGenderTile({ species = 25, name = "PIKACHU", pid = 200 }), 0x42,
  "pid 200 vs ratio 127 is male tile 0x42")
eq(g:partyGenderTile({ species = 25, name = "PIKACHU", pid = 50 }), 0x44,
  "pid 50 vs ratio 127 is female tile 0x44")
eq(g:partyGenderTile({ species = Game3.SPECIES_DITTO, name = "DITTO", pid = 0 }),
  nil, "a genderless mon stamps nothing")
eq(g:partyGenderTile({ species = Game3.SPECIES_NIDORAN_M, name = "NIDORAN M",
  pid = 0 }), nil, "an unnamed NIDORAN M still hides the tile")
eq(g:partyGenderTile({ species = Game3.SPECIES_NIDORAN_M, name = "SPIKE",
  pid = 0 }), 0x42, "a renamed one is male tile 0x42")
eq(g:partyGenderTile({ species = 25, name = "EGG", isEgg = true, pid = 200 }),
  nil, "an egg still stamps nothing")

local captured
function g:drawOrderTile(art, tile, x, y)
  captured = { tile = tile, x = x, y = y }
  return true
end
g:drawPartyGender({ tileMale = 0x42, tileFemale = 0x44 },
  { species = 25, name = "PIKACHU", pid = 200 }, 40, 48)
eq(captured.tile, 0x42, "drawPartyGender stamps the male tile")
eq(captured.x, 72, "four tiles right of the Lv origin")
eq(captured.y, 48, "on the same row as Lv")
captured = nil
g:drawPartyGender({ tileMale = 0x42, tileFemale = 0x44 },
  { species = Game3.SPECIES_DITTO, name = "DITTO", pid = 0 }, 40, 48)
check(captured == nil, "genderless does not call drawOrderTile")

-- ------- 13. Double-battle layout
-- DrawPartyMonBackground / CreatePartyMenuMonIcon / PartyMenuDoPrintLevel
-- all key off IsDoubleBattle(). Field START stays STANDARD; battle party
-- passes PARTY_MENU_LAYOUT_DOUBLE when b.doubles.
eq(Party.LAYOUT_STANDARD, 0, "STANDARD is layout 0")
eq(Party.LAYOUT_DOUBLE, 1, "DOUBLE is layout 1")
eq(Party.iconTopLeft(16, 40)[1], Party.ICON_AT[1][1],
  "standard lead icon is centre 16 minus 16")
eq(Party.iconTopLeft(16, 40)[2], Party.ICON_AT[1][2],
  "and centre 40 minus 16")
eq(Party.iconTopLeft(16, 24)[1], Party.ICON_AT_DOUBLE[1][1],
  "double lead icon is centre 16 minus 16")
eq(Party.iconTopLeft(16, 24)[2], Party.ICON_AT_DOUBLE[1][2],
  "and centre 24 minus 16")
eq(Party.iconTopLeft(16, 80)[2], Party.ICON_AT_DOUBLE[2][2],
  "the second lead icon sits at y 64")

eq(Party.vramToTile(0xF1C8)[1], Party.HP_BAR_AT[1][1],
  "standard lead HP VRAM 0xF1C8 is column 4")
eq(Party.vramToTile(0xF1C8)[2], Party.HP_BAR_AT[1][2],
  "and row 7")
for slot = 1, 6 do
  local tile = Party.vramToTile(Party.HP_BAR_VRAM_DOUBLE[slot])
  eq(tile[1], Party.HP_BAR_AT_DOUBLE[slot][1],
    "double HP " .. slot .. " column matches VRAM")
  eq(tile[2], Party.HP_BAR_AT_DOUBLE[slot][2],
    "double HP " .. slot .. " row matches VRAM")
end

for slot = 1, 6 do
  local at = Party.BOX_AT_DOUBLE[slot]
  local shape = Party.isLeadSlot(Party.LAYOUT_DOUBLE, slot - 1)
    and Party.LEAD_BOX or Party.SLOT_BOX
  check(at[1] >= 0 and at[1] + #shape[1] <= 30,
    "double box " .. slot .. " fits horizontally")
  check(at[2] >= 0 and at[2] + #shape <= 20,
    "double box " .. slot .. " fits vertically")
  local bar = Party.HP_BAR_AT_DOUBLE[slot]
  local left = bar[1] - Party.HP_LABEL_TILES
  local right = bar[1] + Party.HP_BAR_TILES
  check(left > at[1], "double bar " .. slot .. " label starts inside the box")
  eq(right, at[1] + #shape[1] - 1,
    "double bar " .. slot .. " cap lands on the box's last column")
  check(bar[2] >= at[2] and bar[2] < at[2] + #shape,
    "double bar " .. slot .. " is on a row of its own box")
  check(Party.NAME_AT_DOUBLE[slot][1] * 8
      >= Party.ICON_AT_DOUBLE[slot][1] + Party.ICON_SIZE,
    "double nickname " .. slot .. " starts right of the icon")
end
check(Party.isLeadSlot(Party.LAYOUT_STANDARD, 0), "standard slot 0 is the lead")
check(not Party.isLeadSlot(Party.LAYOUT_STANDARD, 1),
  "standard slot 1 is a slim box")
check(Party.isLeadSlot(Party.LAYOUT_DOUBLE, 1),
  "double slot 1 is a second lead box")
check(not Party.isLeadSlot(Party.LAYOUT_DOUBLE, 2),
  "double slot 2 is a slim box")

eq(g:partyMenuLayout({}), Game3.PARTY_MENU_LAYOUT_STANDARD,
  "field party is STANDARD")
eq(g:partyMenuLayout({ layout = Game3.PARTY_MENU_LAYOUT_DOUBLE }),
  Game3.PARTY_MENU_LAYOUT_DOUBLE, "battle doubles pass layout 1")

local art = {
  boxAt = Party.BOX_AT,
  leadBox = Party.LEAD_BOX,
  slotBox = Party.SLOT_BOX,
  emptyBox = Party.EMPTY_BOX,
  tileMale = 0x42,
}
local over = g:partyLayoutArt(art, Game3.PARTY_MENU_LAYOUT_DOUBLE)
eq(over.boxAt[1][2], 1, "double overlay moves the lead box to row 1")
eq(over.boxAt[2][1], 0, "and stacks the second lead on the left")
eq(over.leadBox, Party.LEAD_BOX, "box shapes still come from the sheet art")
eq(art.boxAt[1][2], 3, "the cached STANDARD row is left alone")
eq(g:partyBoxShape(over, Game3.PARTY_MENU_LAYOUT_DOUBLE, 0, {}),
  Party.LEAD_BOX, "double slot 0 stamps the lead shape")
eq(g:partyBoxShape(over, Game3.PARTY_MENU_LAYOUT_DOUBLE, 1, {}),
  Party.LEAD_BOX, "double slot 1 stamps the lead shape too")
eq(g:partyBoxShape(over, Game3.PARTY_MENU_LAYOUT_DOUBLE, 2, {}),
  Party.SLOT_BOX, "double slot 2 is a filled slim box")
eq(g:partyBoxShape(over, Game3.PARTY_MENU_LAYOUT_DOUBLE, 2, nil),
  Party.EMPTY_BOX, "an empty slim slot uses EMPTY_BOX")

-- Link-double tables exist for a later slice; VRAM conversion still holds.
for slot = 1, 6 do
  local tile = Party.vramToTile(Party.HP_BAR_VRAM_LINK_DOUBLE[slot])
  eq(tile[1], Party.HP_BAR_AT_LINK_DOUBLE[slot][1],
    "link-double HP " .. slot .. " column matches VRAM")
  eq(tile[2], Party.HP_BAR_AT_LINK_DOUBLE[slot][2],
    "link-double HP " .. slot .. " row matches VRAM")
end

-- ------- 12. Held item icons
--
-- MenuGfx_HoldIcons is uncompressed and only 64 bytes, so it was found by
-- rebuilding hold_icons.png into GBA 4bpp and matching the byte run. The
-- palette follows immediately after it.
eq(Party.RUBY_US.holdGfx, 0x37657C, "MenuGfx_HoldIcons")
eq(Party.RUBY_US.holdGfxBytes, 64, "two 8x8 frames")
eq(Party.RUBY_US.holdPal, 0x3765BC, "MenuPal_HoldIcons")
eq(Party.RUBY_US.holdPalBytes, 32, "one 16 colour palette")
eq(Party.RUBY_US.holdPal, Party.RUBY_US.holdGfx + Party.RUBY_US.holdGfxBytes,
  "the palette sits directly after the tiles")
eq(Party.HOLD_FRAMES, 2, "an item frame and a mail frame")
eq(Party.HOLD_FRAME_ITEM, 0, "StartSpriteAnim takes 0 for an ordinary item")
eq(Party.HOLD_FRAME_MAIL, 1, "and 1 for mail")

-- SpriteCB_HeldItemIcon offsets by x2 = 4, y2 = 10 from the mon icon's
-- anchor. Both sprites are centre-anchored and the icon is 32x32 while
-- the held marker is 8x8, so against the icon's top-left that is
-- 16 - 4 + 4 across and 16 - 4 + 10 down.
eq(Party.HOLD_AT[1], 16, "the marker sits centred across the icon")
eq(Party.HOLD_AT[2], 22, "and low down it")
check(Party.HOLD_AT[1] + 8 <= 32, "it stays within the icon's width")
check(Party.HOLD_AT[2] + 8 <= 32, "and within its height")

S.finish()
