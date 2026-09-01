-- Party menu chrome. Ruby draws this screen as two BG layers sharing one
-- 116-tile sheet: a static background tilemap underneath, and on top a
-- second tilemap that the code stamps the six mon boxes into
-- (`sub_806B9A4` / `sub_806BA94` in party_menu.c).
--
-- The important thing -- and the reason this ships a tile atlas rather
-- than finished box images -- is that a box's STATE is its palette, not
-- its tiles. `sub_806BF24` picks 3 for a healthy box, 5 for a fainted one,
-- and adds 4 when it is the one under the cursor. That is why the palette
-- is 11 sub-palettes deep and why the party menu has no cursor sprite: the
-- whole box lights up. Reproducing that needs every tile available in
-- every palette, so the atlas is 116 tiles x 11 palettes and the runtime
-- stamps the same arrays the ROM does.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Party = {}

Party.TILE = 8
Party.TILE_BYTES = 32
Party.SCREEN_W = 240
Party.SCREEN_H = 160
Party.TILE_COUNT = 116
Party.PAL_COUNT = 11
Party.MAP_COLS = 32

-- Font 4, the 8x8 font the party menu prints levels and HP with.
--
-- gWindowTemplate_81E6CAC selects font 4, which is sFonts slot 11:
-- type 1, glyphSize 32. Type 1 does NOT index its glyph pool by character
-- code -- GetGlyphTilePointers looks each character up in sFontType1Map,
-- which names an upper and a lower 8x8 tile out of a shared pool. Almost
-- every upper entry is the blank tile 0xD4, so the letter lives entirely
-- in the lower tile and the text is 8 pixels tall. That is why
-- PartyMenuDoPrintLevel copies only the window's lower tile row.
--
-- The map is resolved here rather than at runtime, so what ships is an
-- ordinary sheet indexed by character code.
Party.FONT4_POOL = 0xEA6BC4
Party.FONT4_MAP = 0x1E5FF0
-- Two byte tables sit after the map and agree on every glyph tested;
-- they are sFont1Widths and sFont4Widths, both indexed by pool tile.
Party.FONT4_WIDTHS = 0x1E62DE
Party.FONT4_BLANK_TILE = 0xD4
Party.FONT4_GLYPHS = 256
Party.FONT4_COLS = 16
Party.FONT_PATH = "assets/generated/party/font_small.png"

-- PartyMenuWriteTilemap adds 0x10C, which is where the order text sheet
-- is loaded, so the constants below are indices into this sheet directly.
Party.ORDER_TILES = 128
Party.ORDER_COLS = 16
Party.ORDER_PATH = "assets/generated/party/ordertext.png"
Party.ORDER_TILE_LV = 0x40
Party.ORDER_TILE_MALE = 0x42
Party.ORDER_TILE_FEMALE = 0x44

-- Two 8x8 frames: StartSpriteAnim picks 0 for an ordinary item and 1 for
-- mail. SpriteCB_HeldItemIcon pins the sprite to the mon icon's anchor
-- plus x2 = 4, y2 = 10; both sprites are centre-anchored, so against the
-- icon's top-left corner that lands at +16, +22.
Party.HOLD_FRAMES = 2
Party.HOLD_PATH = "assets/generated/party/holditems.png"
Party.HOLD_AT = { 16, 22 }
Party.HOLD_FRAME_ITEM = 0
Party.HOLD_FRAME_MAIL = 1

Party.TILES_PATH = "assets/generated/party/tiles.png"
Party.BG_PATH = "assets/generated/party/background.png"
Party.HPBAR_PATH = "assets/generated/party/hpbar.png"
Party.STATUS_PATH = "assets/generated/party/status.png"

-- US Ruby 1.0. graphics.c declares gPartyMenuMisc_Gfx / _Pal / _Tilemap,
-- gPartyMenuHpBar_Gfx and gPartyMenuOrderText_Gfx consecutively, so they
-- are five LZ77 streams back to back. Found by walking that chain rather
-- than guessing: the sizes 3712 / 352 / 2048 / 384 / 4096 only line up in
-- one place, and 352 is exactly the 0x160 LoadPartyMenuGraphics asks for.
-- gStatusGfx_Icons sits six streams further along the same chain.
Party.RUBY_US = {
  miscGfx = 0xE71354,
  miscGfxBytes = 3712,
  miscPal = 0xE716A0,
  miscPalBytes = 352,
  miscTilemap = 0xE71788,
  miscTilemapBytes = 2048,
  hpBarGfx = 0xE71894,
  hpBarGfxBytes = 384,
  orderTextGfx = 0xE71934,
  orderTextGfxBytes = 4096,
  -- MenuGfx_HoldIcons / MenuPal_HoldIcons. Uncompressed and adjacent, so
  -- they were found by rebuilding hold_icons.png into GBA 4bpp and
  -- matching the byte run; both are unique in the cart.
  holdGfx = 0x37657C,
  holdGfxBytes = 64,
  holdPal = 0x3765BC,
  holdPalBytes = 32,
  statusGfx = 0xE72860,
  statusGfxBytes = 896,
  statusPal = 0xE72A50,
  statusPalBytes = 32,
}

-- party_menu.c gUnknown_083769D8: the lead mon's box, 11 tiles by 7.
Party.LEAD_BOX = {
  { 0x24, 0x25, 0x25, 0x25, 0x25, 0x25, 0x25, 0x25, 0x25, 0x25, 0x27 },
  { 0x34, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x37 },
  { 0x34, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x37 },
  { 0x34, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x35, 0x37 },
  { 0x44, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x47 },
  { 0x44, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x45, 0x47 },
  { 0x54, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x57 },
}

-- gUnknown_08376A25: a filled slot, 19 by 3.
Party.SLOT_BOX = {
  { 0x50, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51,
    0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x53 },
  { 0x60, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61,
    0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x63 },
  { 0x70, 0x71, 0x71, 0x71, 0x71, 0x71, 0x71, 0x71, 0x71, 0x71, 0x71, 0x71,
    0x71, 0x71, 0x71, 0x71, 0x71, 0x71, 0x73 },
}

-- gUnknown_08376A5E: the slimmer empty-slot box, same footprint.
Party.EMPTY_BOX = {
  { 0x20, 0x21, 0x21, 0x21, 0x21, 0x21, 0x21, 0x21, 0x21, 0x21, 0x21, 0x21,
    0x21, 0x21, 0x21, 0x21, 0x21, 0x21, 0x23 },
  { 0x30, 0x31, 0x31, 0x31, 0x31, 0x31, 0x31, 0x31, 0x31, 0x31, 0x31, 0x31,
    0x31, 0x31, 0x31, 0x31, 0x31, 0x31, 0x33 },
  { 0x40, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
    0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x43 },
}

-- gUnknown_083769A8[0]: where each box is stamped, in tiles.
Party.BOX_AT = {
  { 0, 3 }, { 11, 1 }, { 11, 4 }, { 11, 7 }, { 11, 10 }, { 11, 13 },
}

-- gUnknown_08376678[PARTY_MENU_TYPE_STANDARD], the positions
-- CreatePartyMenuMonIcon passes to CreateMonIcon. CreateSprite anchors on
-- the sprite's centre, so a 32x32 icon draws from x-16, y-16; these are
-- already converted to that top-left corner.
--
-- Not to be confused with gUnknown_083768B8, which looks like an icon
-- table but positions the invisible sprite that tracks the cursor.
Party.ICON_AT = {
  { 0, 24 }, { 88, 2 }, { 88, 26 }, { 88, 50 }, { 88, 74 }, { 88, 98 },
}
Party.ICON_SIZE = 32

-- gUnknown_083768B8[0][6], the cursor's resting place on CANCEL.
Party.CANCEL_AT = { 196, 136 }

-- gUnknown_08376948[0]: the window each nickname is drawn into and cleared
-- from, {left, top, right, bottom} in tiles. Kept for the clear rect; the
-- text itself starts at NAME_AT.
Party.NAME_BOX = {
  { 2, 4, 10, 9 }, { 16, 1, 29, 3 }, { 16, 4, 29, 6 },
  { 16, 7, 29, 9 }, { 16, 10, 29, 12 }, { 16, 13, 29, 15 },
}

-- The nickname sits one column left and one row above the level, which is
-- where the slot boxes put it (col 16 on the box's top row, clear of the
-- icon) and which places the lead's name to the right of its icon too.
Party.NAME_AT = {
  { 5, 4 }, { 16, 1 }, { 16, 4 }, { 16, 7 }, { 16, 10 }, { 16, 13 },
}

-- gUnknown_08376738[0]: where the level (or the status icon that replaces
-- it) is printed, in tiles. The status icon goes one tile left and one
-- down from here, the gender symbol three right and one down.
Party.LEVEL_AT = {
  { 6, 5 }, { 17, 2 }, { 17, 5 }, { 17, 8 }, { 17, 11 }, { 17, 14 },
}

-- gUnknown_08376858[0], converted from VRAM addresses to tile coordinates
-- against the 0xF000 screen block: (addr - 0xF000) / 2 is the entry index
-- in a 32-wide map. PartyMenuDoDrawHPBar then steps two entries back for
-- the "HP" label and eight forward for the right end cap, so each row
-- reads label, six bar tiles, cap -- which is exactly the width of the box
-- it sits in.
Party.HP_BAR_AT = {
  { 4, 7 }, { 23, 2 }, { 23, 5 }, { 23, 8 }, { 23, 11 }, { 23, 14 },
}

-- party_menu.h PARTY_MENU_LAYOUT_*. DrawPartyMonBackground writes
-- STANDARD when IsDoubleBattle() is false, DOUBLE when it is an in-game
-- double, LINK_DOUBLE only for a real link double. CreateMonIcon indexes
-- gUnknown_08376678 with the same 0/1/2 values (TYPE_STANDARD / BATTLE /
-- CONTEST coincidentally share those numbers).
Party.LAYOUT_STANDARD = 0
Party.LAYOUT_DOUBLE = 1
Party.LAYOUT_LINK_DOUBLE = 2

-- CreateSprite anchors on the sprite centre, so a 32x32 icon's top-left
-- is (cx - 16, cy - 16). ICON_AT above is already converted; these helpers
-- keep the other layouts honest against the ROM pixel tables.
function Party.iconTopLeft(cx, cy)
  return { cx - 16, cy - 16 }
end

-- (BG_VRAM + off) on screen block 0xF000, 32-wide map, 2 bytes per entry.
function Party.vramToTile(addr)
  local i = math.floor((addr - 0xF000) / 2)
  return { i % 32, math.floor(i / 32) }
end

-- gUnknown_083769A8 row 1: two tall boxes stacked on the left.
Party.BOX_AT_DOUBLE = {
  { 0, 1 }, { 0, 8 }, { 11, 1 }, { 11, 5 }, { 11, 9 }, { 11, 13 },
}
-- gUnknown_08376678[PARTY_MENU_TYPE_BATTLE], converted to top-left.
Party.ICON_AT_DOUBLE = {
  { 0, 8 }, { 0, 64 }, { 88, 2 }, { 88, 34 }, { 88, 66 }, { 88, 98 },
}
-- gUnknown_08376738[PARTY_MENU_LAYOUT_DOUBLE_BATTLE]
Party.LEVEL_AT_DOUBLE = {
  { 6, 3 }, { 6, 10 }, { 17, 2 }, { 17, 6 }, { 17, 10 }, { 17, 14 },
}
-- Nickname is one column left and one row above the level, which is also
-- gUnknown_08376948[1]'s left/top for each window.
Party.NAME_AT_DOUBLE = {
  { 5, 2 }, { 5, 9 }, { 16, 1 }, { 16, 5 }, { 16, 9 }, { 16, 13 },
}
Party.NAME_BOX_DOUBLE = {
  { 2, 2, 10, 7 }, { 2, 9, 10, 14 },
  { 16, 1, 29, 3 }, { 16, 5, 29, 7 }, { 16, 9, 29, 11 }, { 16, 13, 29, 15 },
}
-- gUnknown_08376858[PARTY_MENU_LAYOUT_DOUBLE_BATTLE]
Party.HP_BAR_VRAM_DOUBLE = { 0xF148, 0xF308, 0xF0AE, 0xF1AE, 0xF2AE, 0xF3AE }
Party.HP_BAR_AT_DOUBLE = {
  { 4, 5 }, { 4, 12 }, { 23, 2 }, { 23, 6 }, { 23, 10 }, { 23, 14 },
}

-- gUnknown_083769A8[gPartyMenuType=2] lands in gUnknown_083769C0.
-- Tables are here so a later link-double slice does not re-derive them;
-- the runtime does not select this layout unless asked.
Party.BOX_AT_LINK_DOUBLE = {
  { 0, 1 }, { 0, 8 }, { 11, 2 }, { 11, 5 }, { 11, 9 }, { 11, 12 },
}
Party.ICON_AT_LINK_DOUBLE = {
  { 0, 8 }, { 0, 64 }, { 88, 10 }, { 88, 34 }, { 88, 66 }, { 88, 90 },
}
Party.LEVEL_AT_LINK_DOUBLE = {
  { 6, 3 }, { 6, 10 }, { 17, 3 }, { 17, 6 }, { 17, 10 }, { 17, 13 },
}
Party.NAME_AT_LINK_DOUBLE = {
  { 5, 2 }, { 5, 9 }, { 16, 2 }, { 16, 5 }, { 16, 9 }, { 16, 12 },
}
Party.HP_BAR_VRAM_LINK_DOUBLE = { 0xF148, 0xF308, 0xF0EE, 0xF1AE, 0xF2AE, 0xF36E }
Party.HP_BAR_AT_LINK_DOUBLE = {
  { 4, 5 }, { 4, 12 }, { 23, 3 }, { 23, 6 }, { 23, 10 }, { 23, 13 },
}

-- DrawPartyMonBackground: slots 0 and 1 use the 11x7 lead box in any
-- double layout; STANDARD only stamps it on slot 0.
function Party.isLeadSlot(layout, slot)
  if slot == 0 then return true end
  return slot == 1 and (layout == Party.LAYOUT_DOUBLE
    or layout == Party.LAYOUT_LINK_DOUBLE)
end

function Party.layoutFields(layout)
  if layout == Party.LAYOUT_DOUBLE then
    return {
      boxAt = Party.BOX_AT_DOUBLE,
      iconAt = Party.ICON_AT_DOUBLE,
      nameAt = Party.NAME_AT_DOUBLE,
      nameBox = Party.NAME_BOX_DOUBLE,
      levelAt = Party.LEVEL_AT_DOUBLE,
      hpBarAt = Party.HP_BAR_AT_DOUBLE,
    }
  end
  if layout == Party.LAYOUT_LINK_DOUBLE then
    return {
      boxAt = Party.BOX_AT_LINK_DOUBLE,
      iconAt = Party.ICON_AT_LINK_DOUBLE,
      nameAt = Party.NAME_AT_LINK_DOUBLE,
      levelAt = Party.LEVEL_AT_LINK_DOUBLE,
      hpBarAt = Party.HP_BAR_AT_LINK_DOUBLE,
    }
  end
  return {
    boxAt = Party.BOX_AT,
    iconAt = Party.ICON_AT,
    nameAt = Party.NAME_AT,
    nameBox = Party.NAME_BOX,
    levelAt = Party.LEVEL_AT,
    hpBarAt = Party.HP_BAR_AT,
  }
end
Party.HP_BAR_TILES = 6
Party.HP_LABEL_TILES = 2

-- The last three tiles of gPartyMenuHpBar_Gfx: 0x109 and 0x10A spell "HP"
-- and 0x10B closes the bar. Everything below them is bar fill.
Party.HP_TILE_LABEL = 9
Party.HP_TILE_LABEL2 = 10
Party.HP_TILE_CAP = 11
Party.HP_TILE_PAL = 3

-- battleInterface.unkC_0 in PartyMenuDoDrawHPBar, keyed by GetHPBarLevel.
Party.HP_FILL_PAL = { [3] = 4, [2] = 5, [1] = 6, [0] = 6 }

-- sub_806BF24. A box's colour is entirely its palette.
Party.PAL_NORMAL = 3
Party.PAL_FAINTED = 5
Party.PAL_SELECTED = 4 -- added to either of the above

-- The order gStatusGfx_Icons stores them, four tiles each. Matches
-- GetMonStatusAndPokerus minus one.
Party.STATUS_ORDER = { "psn", "par", "slp", "frz", "brn", "pkrs", "faint" }
Party.STATUS_TILES = 4

local function bgr555(c)
  return (c % 32) * 8 / 255,
    (math.floor(c / 32) % 32) * 8 / 255,
    (math.floor(c / 1024) % 32) * 8 / 255
end

local function palsFromRaw(raw, count)
  local pals = {}
  for p = 0, count - 1 do
    local pal = {}
    for c = 0, 15 do
      local lo = raw:byte(p * 32 + c * 2 + 1) or 0
      local hi = raw:byte(p * 32 + c * 2 + 2) or 0
      pal[c] = { bgr555(lo + hi * 256) }
    end
    pals[p] = pal
  end
  return pals
end

local function blitTile(image, px, py, tiles, id, pal, hflip, vflip, skip0)
  local base = id * Party.TILE_BYTES
  if base + Party.TILE_BYTES > #tiles then return end
  local w, h = image:getWidth(), image:getHeight()
  for ty = 0, 7 do
    for tx = 0, 7 do
      local sx = hflip and (7 - tx) or tx
      local sy = vflip and (7 - ty) or ty
      local byte = tiles:byte(base + sy * 4 + math.floor(sx / 2) + 1) or 0
      local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      if not (skip0 and ci == 0) then
        local col = pal[ci] or { 0, 0, 0 }
        local x, y = px + tx, py + ty
        if x >= 0 and y >= 0 and x < w and y < h then
          image:setPixel(x, y, col[1], col[2], col[3], 1)
        end
      end
    end
  end
end

function Party.readAll(data)
  local u = Party.RUBY_US
  if type(data) ~= "string" then return nil end
  local gfx = GbaLz77.decompress(data, u.miscGfx)
  local pal = GbaLz77.decompress(data, u.miscPal)
  local map = GbaLz77.decompress(data, u.miscTilemap)
  local hp = GbaLz77.decompress(data, u.hpBarGfx)
  local st = GbaLz77.decompress(data, u.statusGfx)
  local stPal = GbaLz77.decompress(data, u.statusPal)
  local order = GbaLz77.decompress(data, u.orderTextGfx)
  if not (gfx and pal and map and hp and st and stPal and order) then
    return nil
  end
  if #gfx ~= u.miscGfxBytes or #pal ~= u.miscPalBytes then return nil end
  if #map ~= u.miscTilemapBytes or #hp ~= u.hpBarGfxBytes then return nil end
  if #st ~= u.statusGfxBytes or #stPal ~= u.statusPalBytes then return nil end
  if #order ~= u.orderTextGfxBytes then return nil end
  return { gfx = gfx, pal = pal, map = map, hp = hp,
    status = st, statusPal = stPal, order = order }
end

-- One row per palette, one column per tile. Index 0 stays transparent so
-- a box stamped over the background does not blank it out.
function Party.renderTiles(parts)
  local pals = palsFromRaw(parts.pal, Party.PAL_COUNT)
  local image = ImageWriter.blank(Party.TILE_COUNT * Party.TILE,
    Party.PAL_COUNT * Party.TILE, 0, 0, 0, 0)
  for p = 0, Party.PAL_COUNT - 1 do
    for t = 0, Party.TILE_COUNT - 1 do
      blitTile(image, t * Party.TILE, p * Party.TILE, parts.gfx, t, pals[p],
        false, false, true)
    end
  end
  return image
end

-- gPartyMenuOrderText_Gfx: 128 tiles carrying the "Lv" glyph, the gender
-- symbols and the ordering captions for the multi-battle layouts.
-- PartyMenuWriteTilemap writes a bare tile id with no palette bits, so
-- these always draw in palette 0 whatever state the box behind is in.
function Party.renderOrderText(parts)
  local pals = palsFromRaw(parts.pal, Party.PAL_COUNT)
  local image = ImageWriter.blank(Party.ORDER_COLS * Party.TILE,
    (Party.ORDER_TILES / Party.ORDER_COLS) * Party.TILE, 0, 0, 0, 0)
  for t = 0, Party.ORDER_TILES - 1 do
    blitTile(image, (t % Party.ORDER_COLS) * Party.TILE,
      math.floor(t / Party.ORDER_COLS) * Party.TILE,
      parts.order, t, pals[0], false, false, true)
  end
  return image
end

-- The hold icons are raw sprite graphics rather than part of the party
-- menu's own sheet, so they carry their own palette.
function Party.renderHoldIcons(data)
  local u = Party.RUBY_US
  local raw = data:sub(u.holdGfx + 1, u.holdGfx + u.holdGfxBytes)
  if #raw ~= u.holdGfxBytes then return nil end
  local pal = palsFromRaw(data:sub(u.holdPal + 1, u.holdPal + u.holdPalBytes), 1)
  local image = ImageWriter.blank(Party.HOLD_FRAMES * Party.TILE,
    Party.TILE, 0, 0, 0, 0)
  for t = 0, Party.HOLD_FRAMES - 1 do
    blitTile(image, t * Party.TILE, 0, raw, t, pal[0], false, false, true)
  end
  return image
end

-- The background layer is static, so it is composed once here rather than
-- rebuilt from the tilemap every frame.
function Party.renderBackground(parts)
  local pals = palsFromRaw(parts.pal, Party.PAL_COUNT)
  local image = ImageWriter.blank(Party.SCREEN_W, Party.SCREEN_H, 0, 0, 0, 1)
  for row = 0, Party.SCREEN_H / Party.TILE - 1 do
    for col = 0, Party.SCREEN_W / Party.TILE - 1 do
      local entry = GbaBin.u16(parts.map, (row * Party.MAP_COLS + col) * 2)
      local pal = pals[math.floor(entry / 4096) % 16] or pals[0]
      blitTile(image, col * Party.TILE, row * Party.TILE, parts.gfx,
        entry % 1024, pal,
        math.floor(entry / 0x400) % 2 == 1,
        math.floor(entry / 0x800) % 2 == 1, false)
    end
  end
  return image
end

-- 12 tiles in a row. The bar is recoloured per fill level by palette, the
-- same trick the boxes use, so all 11 are rendered.
function Party.renderHpBar(parts)
  local pals = palsFromRaw(parts.pal, Party.PAL_COUNT)
  local tiles = #parts.hp / Party.TILE_BYTES
  local image = ImageWriter.blank(tiles * Party.TILE,
    Party.PAL_COUNT * Party.TILE, 0, 0, 0, 0)
  for p = 0, Party.PAL_COUNT - 1 do
    for t = 0, tiles - 1 do
      blitTile(image, t * Party.TILE, p * Party.TILE, parts.hp, t, pals[p],
        false, false, true)
    end
  end
  return image
end

-- 4 tiles wide, one row per condition, in gStatusGfx_Icons order.
function Party.renderStatus(parts)
  local pals = palsFromRaw(parts.statusPal, 1)
  local tiles = #parts.status / Party.TILE_BYTES
  local rows = math.floor(tiles / Party.STATUS_TILES)
  local image = ImageWriter.blank(Party.STATUS_TILES * Party.TILE,
    rows * Party.TILE, 0, 0, 0, 0)
  for t = 0, tiles - 1 do
    blitTile(image, (t % Party.STATUS_TILES) * Party.TILE,
      math.floor(t / Party.STATUS_TILES) * Party.TILE,
      parts.status, t, pals[0], false, false, true)
  end
  return image
end

-- ApplyColors_ShadowedFont expands the pool's indices into the window's
-- colours: 0 is the hole, 1 the shadow the ROM drops under the letter and
-- 14/15 the letter itself. gWindowTemplate_81E6CAC asks for foreground 15,
-- shadow 1, background 0.
local FONT4_INK = {
  [0] = { 0, 0, 0, 0 },
  [1] = { 0.63, 0.63, 0.69, 1 },
  [14] = { 0.24, 0.24, 0.29, 1 },
  [15] = { 0.06, 0.06, 0.10, 1 },
}

local function blitFont4Tile(image, px, py, data, tile)
  local base = Party.FONT4_POOL + tile * Party.TILE_BYTES
  for row = 0, 7 do
    for col = 0, 7 do
      local b = data:byte(base + row * 4 + math.floor(col / 2) + 1) or 0
      local ci = (col % 2 == 0) and (b % 16) or math.floor(b / 16)
      local c = FONT4_INK[ci] or FONT4_INK[15]
      if c[4] > 0 then image:setPixel(px + col, py + row, c[1], c[2], c[3], 1) end
    end
  end
end

function Party.font4LowerTile(data, code)
  return data:byte(Party.FONT4_MAP + code * 2 + 2) or Party.FONT4_BLANK_TILE
end

function Party.font4UpperTile(data, code)
  return data:byte(Party.FONT4_MAP + code * 2 + 1) or Party.FONT4_BLANK_TILE
end

-- One 8x8 cell per character code, so the runtime can treat this like any
-- other font sheet. Characters whose upper tile is not blank are rare and
-- would need a second row; none of them appear in a level or an HP count.
function Party.renderFont4(data)
  local cols = Party.FONT4_COLS
  local rows = Party.FONT4_GLYPHS / cols
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 0)
  for code = 0, Party.FONT4_GLYPHS - 1 do
    blitFont4Tile(image, (code % cols) * 8, math.floor(code / cols) * 8,
      data, Party.font4LowerTile(data, code))
  end
  return image
end

-- sFont4Widths is indexed by the pool tile, not by the character, so the
-- lookup goes through the map here too.
function Party.readFont4Widths(data)
  local widths = {}
  for code = 0, Party.FONT4_GLYPHS - 1 do
    local tile = Party.font4LowerTile(data, code)
    widths[code] = data:byte(Party.FONT4_WIDTHS + tile + 1) or 8
  end
  return widths
end

function Party.validFont4(data)
  if type(data) ~= "string" then return false end
  if Party.FONT4_POOL + 256 * Party.TILE_BYTES > #data then return false end
  if Party.FONT4_MAP + 512 > #data then return false end
  -- The map opens with the blank pair, and the digits have to be a run.
  if Party.font4UpperTile(data, 0) ~= Party.FONT4_BLANK_TILE then return false end
  if Party.font4LowerTile(data, 0) ~= Party.FONT4_BLANK_TILE then return false end
  local first = Party.font4LowerTile(data, 0xA1)
  for i = 1, 9 do
    if Party.font4LowerTile(data, 0xA1 + i) ~= first + i then return false end
  end
  return true
end

function Party.extract(data)
  local parts = Party.readAll(data)
  if not parts then return nil end
  ImageWriter.save(Party.renderTiles(parts), Party.TILES_PATH)
  ImageWriter.save(Party.renderBackground(parts), Party.BG_PATH)
  ImageWriter.save(Party.renderHpBar(parts), Party.HPBAR_PATH)
  ImageWriter.save(Party.renderStatus(parts), Party.STATUS_PATH)
  ImageWriter.save(Party.renderOrderText(parts), Party.ORDER_PATH)
  local hold = Party.renderHoldIcons(data)
  if not hold then return nil end
  ImageWriter.save(hold, Party.HOLD_PATH)
  if not Party.validFont4(data) then return nil end
  ImageWriter.save(Party.renderFont4(data), Party.FONT_PATH)
  return {
    font = Party.FONT_PATH,
    fontWidths = Party.readFont4Widths(data),
    fontH = 8,
    hold = Party.HOLD_PATH,
    holdAt = Party.HOLD_AT,
    holdFrameItem = Party.HOLD_FRAME_ITEM,
    holdFrameMail = Party.HOLD_FRAME_MAIL,
    order = Party.ORDER_PATH,
    orderCols = Party.ORDER_COLS,
    tileLv = Party.ORDER_TILE_LV,
    tileMale = Party.ORDER_TILE_MALE,
    tileFemale = Party.ORDER_TILE_FEMALE,
    tiles = Party.TILES_PATH,
    background = Party.BG_PATH,
    hpbar = Party.HPBAR_PATH,
    status = Party.STATUS_PATH,
    tileCount = Party.TILE_COUNT,
    palCount = Party.PAL_COUNT,
    leadBox = Party.LEAD_BOX,
    slotBox = Party.SLOT_BOX,
    emptyBox = Party.EMPTY_BOX,
    boxAt = Party.BOX_AT,
    iconAt = Party.ICON_AT,
    cancelAt = Party.CANCEL_AT,
    nameBox = Party.NAME_BOX,
    nameAt = Party.NAME_AT,
    iconSize = Party.ICON_SIZE,
    levelAt = Party.LEVEL_AT,
    hpBarAt = Party.HP_BAR_AT,
    hpBarTiles = Party.HP_BAR_TILES,
    hpLabelTiles = Party.HP_LABEL_TILES,
    hpTileLabel = Party.HP_TILE_LABEL,
    hpTileCap = Party.HP_TILE_CAP,
    hpTilePal = Party.HP_TILE_PAL,
    hpFillPal = Party.HP_FILL_PAL,
    palNormal = Party.PAL_NORMAL,
    palFainted = Party.PAL_FAINTED,
    palSelected = Party.PAL_SELECTED,
    statusOrder = Party.STATUS_ORDER,
    statusTiles = Party.STATUS_TILES,
    -- Extra rows for doubles. Cached ruby41 art without this field still
    -- works: Game3 overlays Party.layoutFields at draw time.
    layouts = {
      [Party.LAYOUT_STANDARD] = Party.layoutFields(Party.LAYOUT_STANDARD),
      [Party.LAYOUT_DOUBLE] = Party.layoutFields(Party.LAYOUT_DOUBLE),
      [Party.LAYOUT_LINK_DOUBLE] = Party.layoutFields(Party.LAYOUT_LINK_DOUBLE),
    },
  }
end

return Party
