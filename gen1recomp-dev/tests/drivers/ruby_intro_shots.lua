-- Capture Ruby boot cinema at the same beats as intro.c / title_screen.c.
--   POKEPORT_VERSION=ruby POKEPORT_GAME=ruby POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/ruby_intro_shots.lua \
--   POKEPORT_SHOT_DIR=tmp/ruby-intro POKEPORT_SPEED=20 love .
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-intro"

  local function go(kind, t)
    game.boot = game.boot or { cursor = 0, blink = 0 }
    game.boot.kind = kind
    game.boot.t = t
    game.boot.blink = t
  end

  local function snap(kind, t, name)
    go(kind, t)
    U.wait(3)
    U.shot(game, out .. "/" .. name)
  end

  snap(game.BOOT_COPYRIGHT, 0, "00_copyright.png")
  snap(game.BOOT_INTRO, 0, "01_intro1_t0.png")
  snap(game.BOOT_INTRO, 200 / 60, "02_intro1_drops.png")
  snap(game.BOOT_INTRO, 560 / 60, "03_gamefreak.png")
  snap(game.BOOT_INTRO, 740 / 60, "04_intro1_panstart.png")
  snap(game.BOOT_INTRO, 820 / 60, "05_intro1_pan.png")
  snap(game.BOOT_INTRO, 904 / 60, "06_intro1_panend.png")
  snap(game.BOOT_INTRO, 880 / 60, "07_intro1_eon.png")
  snap(game.BOOT_INTRO, 1100 / 60, "08_intro2.png")
  snap(game.BOOT_INTRO, 1400 / 60, "09_intro2_latios.png")
  snap(game.BOOT_INTRO, (2069 + 20) / 60, "10_intro3_ball.png")
  snap(game.BOOT_INTRO, (2069 + 80) / 60, "11_intro3_sharpedo.png")
  snap(game.BOOT_INTRO, (2069 + 250) / 60, "12_intro3_trainer.png")
  snap(game.BOOT_INTRO, (2069 + 650) / 60, "13_intro3_starters.png")
  snap(game.BOOT_INTRO, (2069 + 800) / 60, "14_intro3_blast.png")
  snap(game.BOOT_TITLE, 8, "15_title.png")
end
