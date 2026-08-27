-- The half of the mod the arithmetic suite cannot reach: the START menu row,
-- and the screen it opens driven through the REAL ListMenu widget rather than
-- a stand-in.  Page cycling in particular only exists as a mutation of a live
-- widget's fields, so nothing short of the real one proves it.
--
-- Run: luajit mods/johto_radar/tests/menu_tests.lua   (from the repo root)

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local ModUI = require("src.ui.ModUI")

local failures, checks = 0, 0

local function check(condition, label)
  checks = checks + 1
  if not condition then
    failures = failures + 1
    print("FAIL " .. label)
  end
  return condition
end

local function eq(actual, expected, label)
  return check(actual == expected,
    label .. " (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
end

-- ------- the world this run happens in

local GRASS_BUCKETS = { 77, 154, 205, 230, 243, 253, 256 }

local function slots(list)
  local out = {}
  for _, entry in ipairs(list) do
    out[#out + 1] = { species = entry[1], level = entry[2] }
  end
  return out
end

local dayGrass = {
  rate = 24, buckets = GRASS_BUCKETS,
  slots = slots({ { "PIDGEY", 2 }, { "SENTRET", 3 }, { "PIDGEY", 4 },
                  { "HOOTHOOT", 5 }, { "RATTATA", 6 }, { "RATTATA", 7 },
                  { "SENTRET", 8 } }),
}
dayGrass.byTime = {
  morn = { rate = 24, buckets = GRASS_BUCKETS, slots = dayGrass.slots },
  nite = {
    rate = 24, buckets = GRASS_BUCKETS,
    slots = slots({ { "HOOTHOOT", 2 }, { "HOOTHOOT", 3 }, { "HOOTHOOT", 4 },
                    { "RATTATA", 5 }, { "RATTATA", 6 }, { "SPINARAK", 7 },
                    { "SPINARAK", 8 } }),
  },
}

local POKEMON = {
  PIDGEY = { name = "PIDGEY" }, SENTRET = { name = "SENTRET" },
  HOOTHOOT = { name = "HOOTHOOT" }, RATTATA = { name = "RATTATA" },
  SPINARAK = { name = "SPINARAK" },
}

local pressed = {}
local pushes = {}

-- the live world, kept as ONE table rather than rebuilt per call: the overlay
-- decides whether to draw by comparing the stack's top against this identity,
-- which a fresh table every call would silently defeat
local overworld = {
  map = { id = "ROUTE_29", def = { landmark = 2 } },
  tod = "NITE",
}
local stackTop = overworld

local game = {
  data = {
    field = {
      townMap = { landmarks = { [2] = { name = "ROUTE 29" } } },
    },
  },
  save = { pokedex = { owned = { RATTATA = true }, seen = {} } },
  stack = {
    push = function(_, state) pushes[#pushes + 1] = state end,
    pop = function() pushes[#pushes] = nil end,
    top = function() return stackTop end,
  },
  input = {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function() return false end,
  },
}

local function registry(records)
  return { get = function(_, id) return records[id] end }
end

local startMenuHook, hudHook

local options = {
  enabled = true, owned = true,
  overlay = true, overlayOdds = true, overlayRows = 4, overlayWidth = 20,
  overlayAlpha = 100,
}

local mod = {
  exports = {},
  options = {
    define = function() end,
    get = function(_, key) return options[key] end,
  },
  hooks = { wrap = function(_, name, fn)
    if name == "ui.start_menu.items" then startMenuHook = fn end
    if name == "render.hud" then hudHook = fn end
  end },
  -- ModUI itself, with only the screen push swapped out: the way back to the
  -- START menu is the engine's own screen table, not something to instantiate
  ui = setmetatable({ push = function() pushes[#pushes + 1] = "StartMenu" end },
                    { __index = ModUI }),
  content = {
    pokemon = registry(POKEMON),
    encounters = registry({ ROUTE_29 = { grass = dayGrass } }),
    maps = registry({}),
  },
  world = { overworld = function() return overworld end },
  game = game,
}

assert(loadfile("mods/johto_radar/main.lua"))()(mod)

-- ------- the START menu row

check(startMenuHook ~= nil, "the mod wrapped ui.start_menu.items")

local items = startMenuHook(function(_, list) return list end, game,
  { { label = "POKéDEX" }, { label = "SAVE" }, { label = "OPTION" } })

eq(#items, 4, "one row was added")
eq(items[2].label, "RADAR", "RADAR sits directly before SAVE")
eq(items[3].label, "SAVE", "SAVE is still where it was")

-- ------- the screen it opens

items[2].onSelect()
eq(#pushes, 1, "selecting RADAR pushed one screen")

local screen = pushes[1]
check(type(screen) == "table" and type(screen.update) == "function",
  "what was pushed is a live widget")
eq(screen.title, "GRASS NITE NOW",
  "it opens on the period the overworld clock is on")
eq(screen.rows, 5, "five rows, leaving room for the level lines and footer")

-- the nite table: HOOTHOOT slots 1-3, RATTATA 4-5, SPINARAK 6-7
eq(#screen.items, 3, "seven slots collapse to three species")
eq(screen.items[1].label, "HOOTHOOT", "the commonest is first")
eq(screen.items[1].right, "80/100", "77+77+51 of 256 rounds to 80")
eq(screen.items[1].sub, "LV 2-4", "its level range spans its three slots")
eq(screen.items[1].ball, nil, "an unowned species carries no marker")
eq(screen.items[2].label, "RATTATA", "second by weight")
eq(screen.items[2].ball, true, "an owned species is marked")
eq(screen.items[3].sub, "LV 7-8", "the rarest keeps its own range")

local total = 0
for _, item in ipairs(screen.items) do
  total = total + tonumber(item.right:match("^(%d+)"))
end
eq(total, 100, "the displayed shares add up to a hundred")

-- ------- LEFT and RIGHT page, and the pages wrap

pressed = { right = true }
screen:update(1 / 60)
eq(screen.title, "GRASS MORN", "RIGHT wraps past the last page to the first")
eq(screen.index, 1, "the cursor resets onto the new page")
eq(screen.scroll, 0, "and so does the scroll")
eq(screen.items[1].label, "PIDGEY", "morning is the day table here")

pressed = { left = true }
screen:update(1 / 60)
eq(screen.title, "GRASS NITE NOW", "LEFT comes back, still marked NOW")

pressed = { left = true }
screen:update(1 / 60)
eq(screen.title, "GRASS DAY", "and keeps going backwards")

-- ------- every page survives a draw
-- No pixels are asserted; what this catches is the row-indexing in the level
-- lines and the footer reaching past a short page.  polygon is the one call
-- the headless stub does not carry, and the page arrows are the only user.

love.graphics.polygon = love.graphics.polygon or function() end
for page = 1, 3 do
  pressed = { right = true }
  screen:update(1 / 60)
  pressed = {}
  local ok, err = pcall(screen.draw, screen)
  check(ok, "page " .. page .. " draws without error: " .. tostring(err))
end

-- ------- B hands the START menu back

pressed = { b = true }
screen:update(1 / 60)
eq(pushes[#pushes], "StartMenu", "cancelling reopens the START menu")

-- ------- the row can be switched off without unloading the mod

options.enabled = false
local plain = startMenuHook(function(_, list) return list end, game,
  { { label = "SAVE" } })
eq(#plain, 1, "with ENABLED off the START menu is untouched")
options.enabled = true

-- ------- the walking overlay
--
-- render.hud fires over every finished frame whatever is on screen, so most of
-- what matters here is the overlay declining to draw.  The two ports put the
-- world in different places -- Gen 1 pushes it on the stack, Gold leaves the
-- stack EMPTY during free roam -- and both of those have to read as "showing".

check(hudHook ~= nil, "the mod wrapped render.hud")

local Font = require("src.render.Font")
local realDraw = Font.draw
local texts, boxes = {}, {}
Font.draw = function(text, x, y)
  texts[#texts + 1] = { text = text, x = x, y = y }
  return realDraw(text, x, y)
end

-- The panel is a plain rectangle rather than Font.drawBox, because drawBox
-- forces its fill opaque; recording the rectangle is how its geometry and its
-- alpha are both observed.
local realRect = love.graphics.rectangle
love.graphics.rectangle = function(mode, x, y, w, h, ...)
  local _, _, _, a = love.graphics.getColor()
  boxes[#boxes + 1] = { tx = x / 8, ty = y / 8, tw = w / 8, th = h / 8,
                        alpha = a }
  return realRect(mode, x, y, w, h, ...)
end

local viewport = { width = 160, height = 144, gameX = 0, gameY = 0,
                   gameWidth = 160, gameHeight = 144, scale = 1 }

local function hud()
  texts, boxes = {}, {}
  local ok, err = pcall(hudHook, function() end, game, viewport)
  check(ok, "the overlay draws without error: " .. tostring(err))
  local names = {}
  for _, entry in ipairs(texts) do names[#names + 1] = entry.text end
  return names, boxes[1]
end

-- Gen 1 shape: the overworld is the top of the stack
stackTop = overworld
local names, box = hud()
check(box ~= nil, "the overlay draws a box while walking")
eq(box.ty, 0, "pinned to the top of the playfield")
eq(box.tx + box.tw, 20, "and flush with the right edge")

-- the NITE table, which is where the world's clock is: HOOTHOOT 3 slots,
-- RATTATA 2, SPINARAK 2 -- three species, so three rows and a 3+2 tall box
eq(box.th, 5, "the box is as tall as the rows it holds")
eq(#names, 6, "three species, each with its odds")
eq(names[1], "HOOTHOOT", "the commonest is on top")
eq(names[2], "80", "with its share beside it")
eq(names[3], "RATTATA", "then the next")
eq(names[5], "SPINARAK", "then the rarest")

-- Gold shape: nothing on the stack at all IS free roam
stackTop = nil
names, box = hud()
check(box ~= nil, "an empty stack still counts as the world showing")
eq(names[1], "HOOTHOOT", "and shows the same table")

-- anything over the world hides it
stackTop = { label = "a menu" }
names, box = hud()
eq(box, nil, "a menu over the world hides the overlay")
eq(#names, 0, "and draws no text at all")

-- DRAMATIC_SHAPE's battle-exit fade is a transparent lid; the world is still
-- the picture, and hiding for it left the overlay dead after voxel was off.
stackTop = { isOpaque = false, label = "a fade" }
names, box = hud()
check(box ~= nil, "a transparent lid still counts as the world showing")
stackTop = overworld

-- a script, a textbox or a fade: Gold answers busy() because it has a VM;
-- a busy() bolted onto the Gen 1 module by another mod is ignored, because
-- that is how DRAMATIC_SHAPE kept this overlay dead after voxel was off.
overworld.busy = function() return true end
names, box = hud()
check(box ~= nil, "a stray busy() on the Gen 1 world is not a cover")
overworld.stepBody = function() end
names, box = hud()
eq(box, nil, "Gold's own busy() still hides the overlay")
overworld.busy = nil
overworld.stepBody = nil

overworld.transitioning = true
names, box = hud()
eq(box, nil, "and during a map transition")
overworld.transitioning = nil

-- surfing asks a different table, and this map has no water at all
overworld.player = { surfing = true }
names, box = hud()
eq(box, nil, "surfing a map with no water table shows nothing")
overworld.player = nil

-- Gold spells the same state as one string rather than a boolean
overworld.playerState = "surf_pika"
names, box = hud()
eq(box, nil, "and Gold's surf state reads the same way")
overworld.playerState = nil

-- the options
options.overlayRows = 2
names, box = hud()
eq(box.th, 4, "OVERLAY ROWS caps how many rows are drawn")
eq(#names, 4, "two species and two shares")

options.overlayOdds = false
names, box = hud()
eq(#names, 2, "with OVERLAY ODDS off only the names are drawn")
eq(names[1], "HOOTHOOT", "still in commonest-first order")
options.overlayOdds = true
options.overlayRows = 4

-- OVERLAY WIDTH is a ceiling, not a fixed size: the box grows to what it holds
-- and stops there, which is what keeps it reading as a corner ornament
local wide = select(2, hud()).tw
options.overlayWidth = 8
names, box = hud()
eq(box.tw, 8, "OVERLAY WIDTH caps the box")
eq(box.tx + box.tw, 20, "and it stays in the corner when capped")
check(wide > 8, "the uncapped box really was wider than the cap")

options.overlayWidth = 20
names, box = hud()
eq(box.tw, wide, "a cap above what it needs leaves the box alone")

-- ------- OVERLAY ALPHA
-- The panel fades; the text does not, because seeing through the box is for
-- watching the map, not for making the names harder to read.

local function textAlpha()
  local seen
  local real = Font.drawCode
  Font.drawCode = function(code, x, y)
    local _, _, _, a = love.graphics.getColor()
    seen = seen or a
    return real(code, x, y)
  end
  -- the border glyphs draw first, so read the alpha the NAMES were drawn at
  local realFontDraw = Font.draw
  Font.draw = function(text, x, y)
    local _, _, _, a = love.graphics.getColor()
    seen = a
    return realFontDraw(text, x, y)
  end
  hud()
  Font.drawCode, Font.draw = real, realFontDraw
  return seen
end

options.overlayAlpha = 100
names, box = hud()
eq(box.alpha, 1, "ALPHA 100 is a solid panel")

options.overlayAlpha = 50
names, box = hud()
eq(box.alpha, 0.5, "ALPHA 50 is a half-transparent panel")
eq(textAlpha(), 1, "but the names stay solid")

options.overlayAlpha = 0
names, box = hud()
eq(box.alpha, 0, "ALPHA 0 leaves bare text over the world")
check(box ~= nil, "and still lays the panel out")

options.overlayAlpha = 70

-- ------- the playfield transform on a high-DPI screen
--
-- viewport.scale is fitScale(): FRAMEBUFFER pixels per Game Boy pixel.  The
-- gameX/gameY/gameWidth/gameHeight rectangle is in LOVE window units.  Those
-- agree only at DPI 1 -- every desktop -- and diverge on Android, where the
-- density is routinely 1.5 or 2.75.  Trusting `scale` there scaled the box by
-- the DPI factor on top of everything else and threw a top-right panel off the
-- side of the screen entirely.

local realTranslate, realScale = love.graphics.translate, love.graphics.scale
local xform = {}
love.graphics.translate = function(x, y)
  xform.tx, xform.ty = x, y
  return realTranslate(x, y)
end
love.graphics.scale = function(sx, sy)
  xform.sx, xform.sy = sx, sy
  return realScale(sx, sy)
end

-- a phone: density 2.75, so the unit scale is 4 while fitScale() reports 11.
-- The window equals the playfield, so the origin stays on the letterbox.
local phone = { width = 640, height = 576, gameX = 20, gameY = 40,
                gameWidth = 640, gameHeight = 576, scale = 11,
                dpiX = 2.75, dpiY = 2.75 }
local realViewport = viewport
viewport = phone
xform = {}
hud()
eq(xform.sx, 4, "the scale comes from the rectangle, not from viewport.scale")
eq(xform.tx, phone.gameX,
  "and with no spare window the origin stays on the playfield")
eq(xform.ty, phone.gameY, "on both axes")
eq(xform.tx + 160 * xform.sx, phone.gameX + phone.gameWidth,
  "so the right edge of the 160-wide layout lands on the playfield's own")

-- anisotropic density: the two axes are allowed to disagree
viewport = { gameX = 0, gameY = 0, gameWidth = 320, gameHeight = 576,
             scale = 9, dpiX = 2, dpiY = 1 }
xform = {}
hud()
eq(xform.sx, 2, "a wide-pixel display scales x on its own")
eq(xform.sy, 4, "and y on its own")

-- a viewport with no rectangle at all still draws rather than vanishing
viewport = { scale = 3 }
xform = {}
hud()
eq(xform.sx, 3, "with no rectangle it falls back to viewport.scale")

-- Voxel (and Gold's edge-to-edge overworld) fill the WINDOW; the 160x144
-- letterbox is only where the engine still thinks a Game Boy screen is.
-- Pinning to that letterbox put a "top-right" ornament in the middle of the
-- 3D view, which is why the overlay vanished next to DRAMATIC_SHAPE.
local voxel = { width = 1280, height = 720, gameX = 160, gameY = 72,
                gameWidth = 960, gameHeight = 576, scale = 6 }
viewport = voxel
xform = {}
hud()
eq(xform.sx, 6, "the GB scale is kept")
eq(xform.tx + 160 * xform.sx, voxel.width,
  "but the layout's right edge is the WINDOW's, not the letterbox's")
eq(xform.ty, 0, "and the top edge is the window's")

viewport = realViewport
love.graphics.translate, love.graphics.scale = realTranslate, realScale

-- a graphics mod that throws from this layer must not swallow the list
texts, boxes = {}, {}
local threw = false
local ok = pcall(hudHook, function() threw = true; error("hud chrome") end,
  game, viewport)
check(ok, "a throwing nextFn does not take the overlay down with it")
check(boxes[1] ~= nil, "and the overlay still draws")

-- DRAMATIC_SHAPE wraps Renderer:endFrame and can hand back no viewport
texts, boxes = {}, {}
ok = pcall(hudHook, function() end, game, nil)
check(ok, "a missing viewport does not throw")
check(boxes[1] ~= nil, "and the overlay still finds a window to sit on")

-- if the WorldAPI scan misses, game.world / game.overworld is enough
local realOverworldFn = mod.world.overworld
mod.world.overworld = function() return nil end
game.overworld = overworld
texts, boxes = {}, {}
ok = pcall(hudHook, function() end, game, viewport)
check(ok, "a WorldAPI miss does not throw")
check(boxes[1] ~= nil, "and game.overworld is enough to draw")
mod.world.overworld = realOverworldFn
game.overworld = nil

options.overlay = false
names, box = hud()
eq(box, nil, "WALK OVERLAY off draws nothing")
options.overlay = true

Font.draw = realDraw
love.graphics.rectangle = realRect

print(("radar menu: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
