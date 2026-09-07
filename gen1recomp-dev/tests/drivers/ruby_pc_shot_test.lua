-- Capture the Ruby PC box screen (closed + party-open).
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/pc_verify"

  game.phase = "play"
  game.boot = nil
  game.map = game.map or {
    id = "pc_shot", width = 2, height = 2, grid = { 0, 0, 0, 0 },
  }
  game.party = {
    game:makeMon(280, 5),
    game:makeMon(290, 2),
    game:makeMon(290, 3),
    game:makeMon(278, 10),
  }
  game:ensurePc()
  game.pc[1][1] = game:cloneMon(game.party[1])
  game.pc[1][2] = game:cloneMon(game.party[2])
  game.pc[1][3] = game:cloneMon(game.party[3])
  game.pc[1][8] = game:cloneMon(game.party[4])
  game.boxWallpapers[1] = 0 -- forest
  game.boxNames[1] = "BOX1"

  game:enterPcStorage("move")
  game.field.partyOpen = false
  game.field.area = "box"
  game.field.cursor = 0
  game.field.msg = game:pcMonName(game.pc[1][1]) .. " is selected."
  U.log("CLOSE_BTN", game.PC_CLOSE_BTN_X, game.PC_CLOSE_BTN_Y)
  U.wait(4)
  U.shot(game, out .. "/love_box_closed.png")

  game.field.partyOpen = true
  game.field.area = "party"
  game.field.cursor = 0
  game.field.msg = game:pcMonName(game.party[1]) .. " is selected."
  U.wait(4)
  U.shot(game, out .. "/love_box_party.png")

  love.event.quit()
end
