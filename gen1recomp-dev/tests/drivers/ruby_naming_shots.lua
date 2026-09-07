-- Capture Ruby naming screen frames for parity check.
--   $env:POKEPORT_VERSION='ruby'; $env:POKEPORT_GAME='ruby'; $env:POKEPORT_TOUCH='0'
--   $env:POKEPORT_DRIVER='tests/drivers/ruby_naming_shots.lua'
--   $env:POKEPORT_SHOT_DIR='tmp/ruby-naming'; $env:POKEPORT_SPEED='20'
--   & 'C:\Program Files\LOVE\love.exe' .
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-naming"
  local Naming = require("src.ui.gen3.NamingScreen")

  -- Force player naming field with a seed that shows letter/underscore pitch.
  game:openNaming()
  local b = game.boot
  local f = b and b.naming
  assert(f, "naming field open")
  f.name = "BRENDAN"
  b.name = "BRENDAN"
  f.page = 0
  f.cursorX, f.cursorY = 0, 0
  f.iconAnim = 0
  U.wait(4)
  U.shot(game, out .. "/01_upper_brendan.png")

  -- Mid walk-south anim
  f.iconAnim = 24
  U.wait(2)
  U.shot(game, out .. "/02_brendan_anim.png")

  -- Cursor on side PAGE (shows next-page label = lower)
  f.cursorX, f.cursorY = 8, 0
  U.wait(2)
  U.shot(game, out .. "/03_side_page.png")

  f.cursorX, f.cursorY = 8, 1
  U.wait(2)
  U.shot(game, out .. "/04_side_back.png")

  f.cursorX, f.cursorY = 8, 2
  U.wait(2)
  U.shot(game, out .. "/05_side_ok.png")

  -- Cycle to lower page; chip should read OTHERS
  f.page = 1
  f.cursorX, f.cursorY = 0, 0
  U.wait(2)
  U.shot(game, out .. "/06_lower_page.png")

  -- Empty name: underscores only
  f.name = ""
  b.name = ""
  f.page = 0
  f.cursorX, f.cursorY = 0, 0
  U.wait(2)
  U.shot(game, out .. "/07_empty_underscores.png")

  -- Partial name for spacing check
  f.name = "ASH"
  b.name = "ASH"
  U.wait(2)
  U.shot(game, out .. "/08_ash_spacing.png")

  -- Prove D-pad path reaches side from letter grid
  f.cursorX, f.cursorY = 0, 0
  for _ = 1, 8 do Naming.moveCursor(f, 1, 0) end
  assert(f.cursorX == 8, "D-pad right reaches side col, got " .. tostring(f.cursorX))
  U.wait(2)
  U.shot(game, out .. "/09_reached_side.png")

  print("[ruby_naming_shots] wrote shots under " .. out)
end
