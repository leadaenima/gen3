-- Settle Ruby title to phase3 and capture frames for visual_validate.
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-title"
  if game.openTitle then
    game:openTitle()
  else
    game.boot = {
      kind = game.BOOT_TITLE, t = 0, cursor = 0, blink = 0,
      titlePhase = 1, titleCounter = 256, logoBg2Y = -32,
      bannerBlend = 88, lavaY = 0, skipTitle = false,
      shine = {}, showBanner = false, showBanners = false,
      entryFade = 1,
    }
  end
  for _ = 1, 520 do
    if game.stepTitleScreen then
      game:stepTitleScreen(1 / 60)
    end
    if game.boot then
      game.boot.t = (game.boot.t or 0) + 1 / 60
      game.boot.blink = (game.boot.blink or 0) + 1 / 60
    end
    coroutine.yield()
  end
  U.shot(game, out .. "/port_title_settle.png")
  if game.boot then
    game.boot.shine = game.boot.shine or {}
    game.boot.shine[#game.boot.shine + 1] = {
      x = 80, y = 68, flash = true, bright = 20,
    }
  end
  U.wait(2)
  U.shot(game, out .. "/port_title_shine.png")
  if game.boot then
    game.boot.markFrame = 16 * 4
  end
  U.wait(2)
  U.shot(game, out .. "/port_title_marks.png")
  print("[ruby_title] captured settle/shine/marks under " .. out)
end
