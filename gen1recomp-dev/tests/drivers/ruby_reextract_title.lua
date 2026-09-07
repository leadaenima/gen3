-- Re-extract title cinema PNGs, then settle-capture.
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-title"
  local ok, err = pcall(function()
    local Cinema = require("src.import.RomExtractorGen3Cinema")
    local ImageWriter = require("src.import.ImageWriter")
    local romPath = "misc/Pokemon - Ruby Version (USA).gba"
    local data
    if love and love.filesystem and love.filesystem.read then
      data = love.filesystem.read(romPath)
    end
    if not data then
      local f = io.open(romPath, "rb")
      if f then data = f:read("*a"); f:close() end
    end
    if type(data) ~= "string" or #data < 1000 then
      error("ROM read failed")
    end
    local jobs = {
      { Cinema.renderTitleLava, "assets/generated/title/title_lava.png" },
      { Cinema.renderTitleLavaBubbles, "assets/generated/title/title_lava_bubbles.png" },
      { Cinema.renderTitleGroudon, "assets/generated/title/title_groudon.png" },
      { Cinema.renderPressStart, "assets/generated/title/press_start.png" },
      { Cinema.renderTitleCopyright, "assets/generated/title/title_copyright.png" },
      { Cinema.renderLogoShine, "assets/generated/title/logo_shine.png" },
    }
    for i = 1, #jobs do
      local fn, path = jobs[i][1], jobs[i][2]
      local img = fn(data)
      if img then ImageWriter.save(img, path) end
      print("[reextract]", path, img ~= nil)
    end
  end)
  if not ok then print("[reextract] FAIL", err) end
  game._cinemaCache = {}
  if game.openTitle then game:openTitle() end
  for _ = 1, 520 do
    if game.stepTitleScreen then game:stepTitleScreen(1 / 60) end
    if game.boot then
      game.boot.t = (game.boot.t or 0) + 1 / 60
      game.boot.blink = (game.boot.blink or 0) + 1 / 60
    end
    coroutine.yield()
  end
  -- Force banners visible + mid pulse + shine for verify frames.
  if game.boot then
    game.boot.showBanner = true
    game.boot.showBanners = true
    game.boot.titlePhase = 3
    game.boot.bannerY = 66
    game.boot.markFrame = 16 * 4
    game.boot.shine = { { x = 96, y = 68, flash = true, bright = 18 } }
    game.boot.blink = 0
  end
  U.wait(2)
  U.shot(game, out .. "/port_title_settle.png")
  U.shot(game, out .. "/port_title_shine.png")
  U.shot(game, out .. "/port_title_marks.png")
  print("[reextract] shots done")
end
