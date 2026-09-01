-- The mobile on-screen pad, on Ruby.  Same module, same art, same
-- options.touchControls layout as Gen 1/2 -- what was missing was every seam
-- in src/core/Game3.lua that has to reach it, plus ignoring the phone
-- accelerometer so a tilt cannot hide the pad.
--
--   POKEPORT_TOUCH=1 POKEPORT_GAME=ruby \
--     POKEPORT_DRIVER=tests/drivers/ruby_touch_controls.lua love .
--   POKEPORT_SHOT_DIR=/tmp/ruby-touch   (default)
local U = require("tests.drivers.util")

local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/ruby-touch"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[touch] ok   " .. label)
    else
      failures = failures + 1
      print("[touch] FAIL " .. label .. " " .. tostring(detail))
    end
  end

  U.wait(20)
  ok("Game3 owns the shared overlay", game.touchControls == TouchControls)
  ok("POKEPORT_TOUCH=1 forces it on for this desktop run",
    TouchControls.active == true)
  ok("and it has art to draw", TouchControls:visible(),
    tostring(TouchControls.img))
  if not TouchControls:visible() then
    print("FAIL ruby_touch_controls (no overlay)")
    love.event.quit(1)
    return
  end

  local L = TouchControls:layout()
  U.shot(game, out .. "/01-pad.png")

  game:touchpressed("f1", L.a.cx, L.a.cy)
  ok("a finger on A holds GBA A", Input:isDown("a"))
  ok("under the overlay's own input source", Input:isTouchDown("a"))

  game:touchpressed("f2", L.dpad.cx + L.dpad.w * 0.4, L.dpad.cy)
  ok("a finger right of the d-pad centre holds RIGHT", Input:isDown("right"))
  U.shot(game, out .. "/02-pressed.png")
  game:touchmoved("f2", L.dpad.cx, L.dpad.cy - L.dpad.w * 0.4)
  ok("sliding it up swaps the hold to UP", Input:isDown("up"))
  ok("and RIGHT is no longer held", not Input:isDown("right"))

  game:touchreleased("f2", L.dpad.cx, L.dpad.cy - L.dpad.w * 0.4)
  ok("lifting it drops UP", not Input:isDown("up"))
  ok("without dropping A, which another finger still owns", Input:isDown("a"))
  game:touchreleased("f1", L.a.cx, L.a.cy)
  ok("and lifting that finger drops A", not Input:isDown("a"))

  local accel = { getName = function() return "Android Accelerometer" end }
  game:joystickpressed(accel, 1)
  game:joystickaxis(accel, 1, 0.9)
  ok("the phone accelerometer does not hide the pad", TouchControls:visible())

  game:gamepadpressed(nil, "a")
  game:gamepadreleased(nil, "a")
  ok("a controller press hides the pad", not TouchControls:visible())
  game:touchpressed("f6", L.a.cx, L.a.cy)
  ok("and the next touch only brings it back, it does not press",
    TouchControls:visible() and not Input:isDown("a"))
  game:touchreleased("f6", L.a.cx, L.a.cy)

  love.touchpressed("hold", L.a.cx, L.a.cy, 0, 0, 1)
  U.wait(2)
  ok("love.touchpressed reaches Input during boot", Input:isDown("a"))
  ok("under the overlay's source", Input:isTouchDown("a"))
  love.touchreleased("hold", L.a.cx, L.a.cy, 0, 0, 1)
  U.wait(2)
  ok("and lifting it releases", not Input:isDown("a"))

  print(failures == 0 and "PASS ruby_touch_controls"
    or ("FAIL ruby_touch_controls (%d)"):format(failures))
  love.event.quit(failures == 0 and 0 or 1)
end
