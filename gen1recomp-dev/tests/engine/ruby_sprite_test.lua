-- Ruby overworld sprites: ObjectEventGraphicsInfo, palettes, 4bpp blit.
-- Fixture bytes only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_sprite_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby overworld sprites")
local check = S.check
local eq = S.eq

local GbaBin = require("src.import.GbaBin")
local RomExtractorGen3 = require("src.import.RomExtractorGen3")
local Game3 = require("src.core.Game3")

local function overlay(base, off, chunk)
  return base:sub(1, off) .. chunk .. base:sub(off + #chunk + 1)
end

local function gfxInfo(palTag, size, w, h, imagesOff, dummy)
  return GbaBin.packU16(0xFFFF)
    .. GbaBin.packU16(palTag)
    .. GbaBin.packU16(0x1101)
    .. GbaBin.packU16(size)
    .. GbaBin.packU16(w)
    .. GbaBin.packU16(h)
    .. string.char(0, 0, 0, 0)
    .. GbaBin.packPtr(dummy)
    .. GbaBin.packPtr(dummy)
    .. GbaBin.packPtr(dummy)
    .. GbaBin.packPtr(imagesOff)
    .. GbaBin.packPtr(dummy)
end

-- ------- 4bpp nibble order (row-major tiles)

local tile = string.rep(string.char(0x11), 32)
eq(RomExtractorGen3.colorIndex4bpp(tile, 8, 0, 0), 1,
  "low nibble is the left pixel")
eq(RomExtractorGen3.colorIndex4bpp(tile, 8, 1, 0), 1,
  "high nibble is the right pixel")
eq(RomExtractorGen3.colorIndex4bpp(string.rep("\0", 32), 8, 0, 0), 0,
  "color 0 is transparent in OBJ")

-- Two tiles wide: tile 1 starts at byte 32.
local pair = tile .. string.rep(string.char(0x22), 32)
eq(RomExtractorGen3.colorIndex4bpp(pair, 16, 8, 0), 2,
  "tile 1 is to the right in row-major order")

-- ------- graphics + palette tables

local SIZE = 0x400
local TABLE, PAL, PIC, FRAME, INFO, PALS =
  0x040, 0x080, 0x0C0, 0x1C0, 0x1E0, 0x300
local GFX_COUNT = 8

eq(#gfxInfo(0x1100, 512, 16, 32, FRAME, FRAME), 0x24,
  "ObjectEventGraphicsInfo is 0x24 bytes")

local rom = string.rep("\0", SIZE)
rom = overlay(rom, PIC, string.rep(string.char(0x11), 256))
rom = overlay(rom, FRAME,
  GbaBin.packPtr(PIC) .. GbaBin.packU16(256) .. GbaBin.packU16(0))

local ptrs = {}
for i = 0, GFX_COUNT - 1 do
  local off = INFO + i * 0x24
  local palTag = i == 1 and 0x1103 or 0x1100
  rom = overlay(rom, off, gfxInfo(palTag, 512, 16, 32, FRAME, FRAME))
  ptrs[#ptrs + 1] = GbaBin.packPtr(off)
end
rom = overlay(rom, TABLE, table.concat(ptrs))

local palBytes = GbaBin.packU16(0x530E) .. GbaBin.packU16(0x001F)
  .. string.rep(GbaBin.packU16(0), 14)
rom = overlay(rom, PAL, palBytes)

local palRows = {}
local tags = { 0x1100, 0x1103, 0x1104, 0x1105, 0x1106, 0x1107 }
for i = 1, #tags do
  palRows[#palRows + 1] = GbaBin.packPtr(PAL)
    .. GbaBin.packU16(tags[i]) .. GbaBin.packU16(0)
end
rom = overlay(rom, PALS, table.concat(palRows))
eq(#rom, SIZE, "fixture ROM stays 0x400 bytes")

local parsed = RomExtractorGen3.parseGraphicsInfo(rom, INFO)
check(parsed ~= nil, "parseGraphicsInfo accepts Brendan's struct")
eq(parsed.width, 16, "width")
eq(parsed.height, 32, "height")
eq(parsed.paletteTag, 0x1100, "player palette tag")
eq(parsed.frameOff, PIC, "frame 0 is the first SpriteFrameImage")
eq(parsed.frameSize, 256, "16x32 4bpp is 256 bytes")
eq(parsed.frameCount, 1, "fixture has one frame then zeros")

eq(RomExtractorGen3.parseGraphicsInfo(rom, 0), nil,
  "zeros are not a graphics info")

local TRUCK_INFO, TRUCK_FRAME, TRUCK_PIC = 0x40, 0x80, 0xC0
local truckRom = string.rep("\0", 0x800)
truckRom = overlay(truckRom, TRUCK_PIC, string.rep(string.char(0x11), 1152))
truckRom = overlay(truckRom, TRUCK_FRAME,
  GbaBin.packPtr(TRUCK_PIC) .. GbaBin.packU16(1152) .. GbaBin.packU16(0))
truckRom = overlay(truckRom, TRUCK_INFO,
  gfxInfo(0x110D, 1152, 48, 48, TRUCK_FRAME, TRUCK_FRAME))
local truckInfo = RomExtractorGen3.parseGraphicsInfo(truckRom, TRUCK_INFO)
check(truckInfo ~= nil, "parseGraphicsInfo accepts the 48x48 truck")
eq(truckInfo.width, 48, "truck width")
eq(truckInfo.height, 48, "truck height")
eq(truckInfo.frameSize, 1152, "48x48 4bpp is 1152 bytes")

local graphics = RomExtractorGen3.findObjectEventGraphics(rom)
check(graphics ~= nil, "findObjectEventGraphics locates the pointer table")
eq(graphics.tableOff, TABLE, "table offset")
eq(graphics.count, GFX_COUNT, "eight consecutive ROM pointers")
eq(graphics.byId[0].offset, INFO, "gid 0 is the first info")
eq(graphics.byId[1].paletteTag, 0x1103, "gid 1 keeps its NPC palette tag")

local pals = RomExtractorGen3.findObjectEventPalettes(rom, graphics)
check(pals ~= nil, "palettes sit after the graphics infos")
eq(pals.tableOff, PALS, "palette table follows the last info")
eq(pals.count, 6, "six SpritePalette rows")
eq(pals.byTag[0x1100], PAL, "tag 0x1100 maps to palette bytes")
eq(pals.byTag[0x1103], PAL, "tag 0x1103 is present")

-- ------- used-id set always includes the player

local ids = RomExtractorGen3.collectGraphicsIds({
  g0_0 = { objects = { { graphicsId = 17 }, { graphicsId = 9 } } },
})
eq(#ids, 22, "player forms, berry stages, evil-team gfx, plus two NPCs")
eq(ids[1], 0, "gid 0 is always extracted")
local used = {}
for i = 1, #ids do used[ids[i]] = true end
check(used[1] and used[2] and used[63], "Brendan bike and surf sheets")
check(used[89] and used[90] and used[92], "May walk, bike, and surf")
check(used[9] and used[17], "map NPCs stay in the set")
eq(RomExtractorGen3.collectGraphicsIds(nil)[1], 0,
  "empty maps still extract Brendan")
eq(#RomExtractorGen3.collectGraphicsIds(nil), 20,
  "player-form sheets, berry stages, and Magma/Aqua")
check(used[61] and used[62], "early and late berry sheets")
check(used[119] and used[117], "Magma M and Aqua M for VAR gfx")
eq(RomExtractorGen3.spritePath(0), "assets/generated/sprites/ow_0.png",
  "player PNG path is the cache sentinel")

-- ------- Game3 foot-aligns 16x32 sprites on the tile

local px, py = Game3.spriteDrawPos(5, 10, 16, 32)
eq(px, 80, "16-wide sprite is centered on the tile")
eq(py, 144, "32-tall sprite's feet sit on the bottom of the tile")
local sx, sy = Game3.spriteDrawPos(5, 10, 16, 16)
eq(sx, 80, "16x16 x")
eq(sy, 160, "16x16 stays in its tile")
local wx, wy = Game3.spriteDrawPos(5, 10, 32, 32)
eq(wx, 72, "32-wide sprite is centered")
eq(wy, 144, "32-tall feet on the tile")
local _, ly = Game3.spriteDrawPos(5, 10, 16, 32, 8)
eq(ly, 136, "levitate lifts 8px")

local spec = Game3.spriteSpec({
  byId = { [9] = { path = "assets/generated/sprites/ow_9.png", width = 16, height = 32 } },
}, 9)
eq(spec.height, 32, "spriteSpec looks up by graphicsId")
eq(Game3.spriteSpec({ byId = {} }, 9), nil, "missing gid has no spec")

local game = Game3.new()
game.data.sprites = { playerGraphicsId = 0, byId = {} }
eq(game:drawOwSprite(0, 0, 0), false, "missing PNG falls back to the rect")

-- ------- anim cmds: imageValue:16 duration:6 hFlip at bit 22

local function packFrame(image, duration, hFlip)
  local u = image + duration * 65536
  if hFlip then u = u + 2 ^ 22 end
  return GbaBin.packU32(u)
end
local jump0 = GbaBin.packU32(0xFFFE)

local animRom = string.rep("\0", 0x80)
local function put(off, chunk)
  animRom = overlay(animRom, off, chunk)
end
put(0x00, packFrame(0, 16, false) .. jump0)
put(0x08, packFrame(1, 16, false) .. jump0)
put(0x10, packFrame(2, 16, false) .. jump0)
put(0x18, packFrame(2, 16, true) .. jump0)
put(0x20, packFrame(3, 8, false) .. packFrame(0, 8, false)
  .. packFrame(4, 8, false) .. packFrame(0, 8, false) .. jump0)
put(0x34, packFrame(5, 8, false) .. packFrame(1, 8, false)
  .. packFrame(6, 8, false) .. packFrame(1, 8, false) .. jump0)
put(0x48, packFrame(7, 8, false) .. packFrame(2, 8, false)
  .. packFrame(8, 8, false) .. packFrame(2, 8, false) .. jump0)
put(0x5C, packFrame(7, 8, true) .. packFrame(2, 8, true)
  .. packFrame(8, 8, true) .. packFrame(2, 8, true) .. jump0)
put(0x70, GbaBin.packPtr(0x00) .. GbaBin.packPtr(0x08)
  .. GbaBin.packPtr(0x10) .. GbaBin.packPtr(0x18)
  .. GbaBin.packPtr(0x20) .. GbaBin.packPtr(0x34)
  .. GbaBin.packPtr(0x48) .. GbaBin.packPtr(0x5C))

local south = RomExtractorGen3.parseAnimScript(animRom, 0x00)
eq(south[1].frame, 0, "face south is frame 0")
eq(south[1].flip, false, "face south is not flipped")
local east = RomExtractorGen3.parseAnimScript(animRom, 0x18)
eq(east[1].frame, 2, "face east reuses the west frame")
eq(east[1].flip, true, "face east is hFlipped")
eq(RomExtractorGen3.parseAnimScript(animRom, 0x20)[1].frame, 3,
  "go south starts on the step frame")
eq(RomExtractorGen3.parseAnimScript("\255\255\0\0", 0), nil,
  "ANIMCMD_END is not a pose")

local poses = RomExtractorGen3.parseOwAnims(animRom, 0x70)
eq(poses.face.south.frame, 0, "anim 0 is face south")
eq(poses.face.north.frame, 1, "anim 1 is face north")
eq(poses.face.west.frame, 2, "anim 2 is face west")
eq(poses.face.east.flip, true, "anim 3 is flipped west")
eq(#poses.walk.south, 4, "go south has four poses")
eq(poses.walk.east[1].flip, true, "go east is flipped")
eq(RomExtractorGen3.maxAnimFrame(poses), 8, "walk uses frames 0-8")

eq(Game3.facingFromDelta(0, -1), "north", "up is north")
eq(Game3.facingFromDelta(1, 0), "east", "right is east")
eq(Game3.facingFromMovementType(7), "north", "FACE_UP")
eq(Game3.facingFromMovementType(8), "south", "FACE_DOWN")
eq(Game3.facingFromMovementType(10), "east", "FACE_RIGHT")
eq(Game3.facingFromMovementType(99), "south", "unknown movement types face south")

local pose = Game3.poseFor(poses, "east", false, 0)
eq(pose.frame, 2, "standing east uses the face table")
eq(pose.flip, true, "standing east is flipped")
eq(Game3.poseFor(poses, "south", true, 0).frame, 3,
  "a new step uses the first walk pose")
eq(Game3.poseFor(poses, "south", true, 0.9).frame, 0,
  "the end of the step plants the standing frame")
eq(Game3.poseFor({}, "south", true, 0).frame, 0,
  "missing tables stand on frame 0")

local stepper = Game3.new()
stepper.playerX, stepper.playerY = 2, 3
stepper.walkFromX, stepper.walkFromY = 1, 3
stepper.walkCooldown = Game3.WALK_PERIOD / 2
local vx, vy = stepper:visualTile()
eq(vx, 1.5, "camera follows the in-between pixel")
eq(vy, 3, "lerp keeps the other axis")
eq(stepper:walkProgress(), 0.5, "halfway through the step")

local wall = Game3.new()
wall.data.maps = { maps = { g0_0 = { width = 2, height = 1, grid = { 0, 1024 } } } }
wall:enterMap(wall.data.maps.maps.g0_0, 0, 0, false)
check(not wall:tryWalk(1, 0), "solid tile still blocks")
eq(wall.facing, "east", "bumping a wall turns you to face it")
eq(wall.playerX, 0, "the bump does not move")

eq(Game3.wanderDirs(1), "look", "LOOK_AROUND")
eq(Game3.wanderDirs(2)[4], "east", "WANDER_AROUND has four dirs")
eq(Game3.wanderDirs(5)[1], "west", "WANDER_LEFT_AND_RIGHT")
eq(Game3.wanderDirs(8), nil, "FACE_DOWN stays put")
eq(Game3.wanderDirs(64), "place", "WALK_IN_PLACE_DOWN")
eq(Game3.wanderDirs(87), "place", "JOG_IN_PLACE_RIGHT")
local dx, dy = Game3.deltaFromFacing("west")
eq(dx, -1, "west dx")
eq(dy, 0, "west dy")

local cam = Game3.new()
cam.map = { width = 40, height = 40 }
cam.playerX, cam.playerY = 20, 20
cam:clampCamera()
eq(cam.camX, 208, "20 tiles in is pixel 208")
eq(cam.camY, 248, "vertical follow")
cam.walkFromX, cam.walkFromY = 19, 20
cam.walkCooldown = Game3.WALK_PERIOD * 0.3
cam:clampCamera()
eq(cam.camX, Game3.snapPixel(cam.camX), "large-map scroll is a whole pixel")
eq(cam.camY, Game3.snapPixel(cam.camY), "Y is snapped too")

local stepGrid = {}
for i = 1, 40 * 40 do stepGrid[i] = 0 end
local step = Game3.new()
step.map = { width = 40, height = 40, grid = stepGrid }
step.playerX, step.playerY = 20, 20
step.walkFromX, step.walkFromY = 20, 20
step.walkCooldown = 0
step:clampCamera()
eq(step.camX, 208, "standing still in the interior")
check(step:tryWalk(1, 0), "one step east on open ground")
eq(step.playerX, 21, "dest tile updates immediately")
eq(step.walkCooldown, Game3.WALK_PERIOD, "the step starts interpolating")
eq(step.camX, 208, "first frame keeps the camera on the start tile")

local canvas = Game3.new()
eq(Game3.SCREEN_W, 240, "GBA framebuffer width")
eq(Game3.SCREEN_H, 160, "GBA framebuffer height")
local gba = canvas:ensureCanvas()
check(gba ~= nil, "pixel-exact GBA canvas exists")
eq(gba.w, 240, "canvas is 240 wide")
eq(gba.h, 160, "canvas is 160 tall")

local grid = {}
for i = 1, 64 do grid[i] = 0 end
local town = Game3.new()
town.phase = "play"
town.map = {
  id = "wander",
  width = 8, height = 8, grid = grid,
  objects = { { x = 3, y = 3, graphicsId = 9, movementType = 2, rangeX = 1, rangeY = 1 } },
}
town:enterMap(town.map, 0, 0, false)
local npc = town:npcsFor(town.map)[1]
eq(npc.x, 3, "NPC starts on its template tile")
check(town:tryNpcWalk(npc, town.map, 1, 0), "one step east is in range")
eq(npc.x, 4, "NPC moved")
check(not town:tryNpcWalk(npc, town.map, 1, 0), "range 1 cannot go two tiles from home")
eq(npc.x, 4, "the out-of-range step is rejected")
town.playerX, town.playerY = 4, 4
npc.x, npc.y = 4, 3
check(not town:tryNpcWalk(npc, town.map, 0, 1), "NPC does not walk onto the player")
check(town:npcAt(town.map, 4, 3) ~= nil, "runtime NPC occupies its cell")

-- ------- latin FONT3 finder (8x16 4bpp, indexed by GBA codes)

eq(Game3.fontCode("A"), 0xBB, "A is CHAR_A")
eq(Game3.fontCode("Z"), 0xD4, "Z is CHAR_Z")
eq(Game3.fontCode("0"), 0xA1, "0 is CHAR_0")
eq(Game3.fontCode("!"), 0xAB, "bang")
eq(Game3.fontCode(" "), 0x00, "space")
eq(Game3.fontCode("e"), 0xD9, "e is CHAR_e")
eq(Game3.fontCode("é"), 0xD9, "é draws as e")

local function fontRec(typ, glyphsOff, gs, lo)
  return GbaBin.packU32(typ)
    .. GbaBin.packPtr(glyphsOff)
    .. GbaBin.packU16(gs)
    .. GbaBin.packU16(lo)
end

local TABLE, FONT3, DUMMY = 0x40, 0x200, 0x180
local fontRom = string.rep("\0", FONT3 + 256 * 64)
local slots = {
  { 0, DUMMY, 16, 8 }, { 1, DUMMY, 8, 0 }, { 2, DUMMY, 8, 0 },
  { 4, DUMMY, 64, 512 }, { 1, DUMMY, 32, 0 }, { 2, DUMMY, 32, 0 },
  { 3, DUMMY, 8, 0 },
  { 0, DUMMY, 16, 8 }, { 1, DUMMY, 8, 0 }, { 2, DUMMY, 8, 0 },
  { 0, FONT3, 64, 32 }, { 1, DUMMY, 32, 0 }, { 2, DUMMY, 32, 0 },
  { 3, DUMMY, 8, 0 },
}
local packed = {}
for i = 1, #slots do
  packed[i] = fontRec(slots[i][1], slots[i][2], slots[i][3], slots[i][4])
end
fontRom = overlay(fontRom, TABLE, table.concat(packed))
local blob = string.rep(string.char(0xFF), 64)
local function putGlyph(code)
  fontRom = overlay(fontRom, FONT3 + code * 64, blob)
end
for c = 0xA1, 0xAA do putGlyph(c) end
for c = 0xBB, 0xEE do putGlyph(c) end
eq(RomExtractorGen3.findFontTable(fontRom), TABLE, "finder lands on sFonts")
eq(RomExtractorGen3.findLatinFont3(fontRom), FONT3, "finder lands on latin FONT3")
eq(RomExtractorGen3.findLatinFont3(string.rep("\0", 5000)), nil,
  "empty padding is not a font")
eq(RomExtractorGen3.fontPath(), "assets/generated/fonts/font.png",
  "FONT3 PNG path")

local rider = Game3.new()
rider.bike = "mach"
eq(rider:playerGraphicsId(), Game3.GFX_BRENDAN_MACH_BIKE, "Mach Bike sprite")
rider.bike = "acro"
eq(rider:playerGraphicsId(), Game3.GFX_BRENDAN_ACRO_BIKE, "Acro Bike sprite")
rider.bike = nil
rider.surfing = true
eq(rider:playerGraphicsId(), Game3.GFX_BRENDAN_SURFING, "Surf sprite")
rider.surfing = nil
rider.gender = Game3.GENDER_FEMALE
eq(rider:playerName(), "MAY", "girl is MAY")
rider.data.sprites = { byId = { [Game3.GFX_MAY] = { id = 89 } } }
eq(rider:playerGraphicsId(), Game3.GFX_MAY, "May standing")
eq(#rider:startMenuItems(), 6, "START lists name, OPTION, EXIT")
eq(rider:startMenuItems()[3], "MAY", "the trainer row is the player name")
eq(rider:startMenuItems()[5], "OPTION", "OPTION is in START")

S.finish()
