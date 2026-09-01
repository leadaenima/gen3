-- Ruby's on-screen pad.  Same module as Gen 1/2 (src/core/TouchControls.lua);
-- what was missing was Game3 applying the saved layout, resetting on focus
-- loss, and ignoring the phone accelerometer so a tilt cannot hide the pad.
--   luajit tests/engine/ruby_touch_controls.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby touch controls")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("ruby")

local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")
local Game3 = require("src.core.Game3")
local LauncherSettings = require("src.import.LauncherSettings")

Input:init()
TouchControls:init()

local g = Game3.new()
g.touchControls = TouchControls
eq(g.touchControls, TouchControls, "Game3 owns the shared overlay")

g:applyTouchOptions({
  touchControls = { enabled = true },
  haptics = "strong",
})
eq(TouchControls.enabled, true, "applyTouchOptions turns the pad on")
eq(TouchControls.haptics, "strong", "and takes the launcher vibration level")

g:applyTouchOptions({
  touchControls = { enabled = false },
  haptics = "off",
})
eq(TouchControls.enabled, false, "and can turn it off")

local function armOverlay()
  TouchControls.active = true
  TouchControls.enabled = true
  TouchControls.controllerHidden = false
  TouchControls.img = TouchControls.img or {}
  TouchControls.preview = false
  TouchControls:reset()
  Input:reset()
end

armOverlay()
local L = TouchControls:layout()
check(L and L.a and L.dpad, "layout has A and a d-pad")

g:touchpressed("f1", L.a.cx, L.a.cy)
eq(Input:isDown("a"), true, "a finger on A holds GBA A")
eq(Input:isTouchDown("a"), true, "under the overlay's own input source")
g:touchpressed("f2", L.dpad.cx + L.dpad.w * 0.4, L.dpad.cy)
eq(Input:isDown("right"), true, "a finger right of the d-pad holds RIGHT")
g:touchmoved("f2", L.dpad.cx, L.dpad.cy - L.dpad.w * 0.4)
eq(Input:isDown("up"), true, "sliding it up swaps the hold to UP")
eq(Input:isDown("right"), false, "and RIGHT is no longer held")
g:touchreleased("f2", L.dpad.cx, L.dpad.cy - L.dpad.w * 0.4)
eq(Input:isDown("up"), false, "lifting it drops UP")
eq(Input:isDown("a"), true, "without dropping A")
g:touchreleased("f1", L.a.cx, L.a.cy)
eq(Input:isDown("a"), false, "lifting A drops it")

armOverlay()
g:touchpressed("hold", L.b.cx, L.b.cy)
eq(Input:isDown("b"), true, "B is held before focus is taken away")
g:focus(false)
eq(Input:isDown("b"), false, "losing focus frees the held pad button")

armOverlay()
local accel = { getName = function() return "Android Accelerometer" end }
g:joystickpressed(accel, 1)
g:joystickaxis(accel, 1, 0.9)
check(TouchControls:visible(), "the phone accelerometer does not hide the pad")
g:gamepadpressed(nil, "a")
g:gamepadreleased(nil, "a")
eq(TouchControls:visible(), false, "a real controller press hides the pad")
g:touchpressed("wake", L.a.cx, L.a.cy)
check(TouchControls:visible() and not Input:isDown("a"),
  "the next touch only brings it back, it does not press")
g:touchreleased("wake", L.a.cx, L.a.cy)

love.joystick = love.joystick or {}
love.joystick.getJoystickCount = function() return 0 end
g:joystickremoved()
check(TouchControls:visible(), "unplugging the last pad shows the overlay again")

GameVersion.set("red")
local redPad = TouchControls.defaultLayout(400, 800)
GameVersion.set("ruby")
local rubyPad = TouchControls.defaultLayout(400, 800)
check(rubyPad.dpad.cx > redPad.dpad.cx,
  "Ruby default pad sits further from the portrait bezel")

local realGetOS = love.system.getOS
love.system.getOS = function() return "Android" end
local edited = 0
local ruby = LauncherSettings.open({
  editTouchControls = function() edited = edited + 1 end,
}, "ruby")
local function has(model, label)
  for _, section in ipairs(model.sections) do
    for _, row in ipairs(section.rows) do
      if row.label == label then return row end
    end
  end
end
check(has(ruby, "TOUCH PAD") ~= nil, "Ruby gear offers TOUCH PAD")
check(has(ruby, "VIBRATION") ~= nil, "and VIBRATION")
check(has(ruby, "TOUCH CONTROLS") ~= nil, "and the layout editor")
has(ruby, "TOUCH CONTROLS").action()
eq(edited, 1, "the editor row reaches the host hook")
love.system.getOS = realGetOS

local src = assert(io.open("src/core/Game3.lua", "r")):read("*a")
check(src:find("GamepadMap.isAccelerometer", 1, true) ~= nil,
  "Game3 ignores the phone accelerometer")
check(src:find("TouchControls:applyOptions", 1, true) ~= nil,
  "and applies the saved overlay at boot")
check(src:find("TouchControls:joystickremoved", 1, true) ~= nil,
  "and restores the pad when the last controller unplugs")

GameVersion.set(prevVersion)
S.finish("ruby touch controls")
