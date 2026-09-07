-- Capture door open/close on Littleroot (pair_0 house door).
--   POKEPORT_VERSION=ruby POKEPORT_GAME=ruby POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/ruby_door_shot_test.lua \
--   POKEPORT_SHOT_DIR=tmp/ruby-door POKEPORT_SPEED=1 love .
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-door"

  -- Skip boot straight into Littleroot south of Brendan's door (5,8).
  game.phase = "play"
  game.boot = nil
  game.field = nil
  if not game.data or not game.data.tilesets or not game.data.tilesets.doorByMetatile then
    game:loadRomData()
  end
  local map = game:lookupMap(0, 9) or (game.data.maps and game.data.maps.maps and game.data.maps.maps.g0_9)
  if type(map) ~= "table" then
    -- Gen3MapPack may expose by id
    local pack = game.data.maps
    map = pack and (pack.g0_9 or (pack.byId and pack.byId.g0_9) or (pack.maps and pack.maps.g0_9))
  end
  U.log("map", map and map.id, "tileset", map and map.tileset)
  U.log("doorByMetatile", game.data.tilesets and game.data.tilesets.doorByMetatile and "yes" or "NO")
  game:enterMap(map, 5, 9, true)
  game.facing = "north"
  game.playerX, game.playerY = 5, 9
  game:clampCamera()
  U.wait(8)
  U.shot(game, out .. "/00_outside.png")

  local warp = game.warpAt and game.warpAt(map, 5, 8) or (map.warps and map.warps[2])
  U.log("warp", warp and warp.x, warp and warp.y)
  U.log("behavior", game:behaviorAt(map, 5, 8))
  U.log("doorEntry", game:doorEntryFor(map, 5, 8)
    and game:doorEntryFor(map, 5, 8).row)

  local ok = game:beginDoorWarp(warp, 5, 8)
  U.log("beginDoorWarp", tostring(ok), "field", game.field and game.field.kind,
    "doorAnim", game.doorAnim and "yes" or "nil")
  U.log("atlas", game:doorAtlasFor(map.tileset) and "loaded" or "MISSING")

  for i = 0, 20 do
    U.shot(game, out .. string.format("/01_open_%02d.png", i))
    game:walkHeld(1 / 60)
    U.log("f", i, "phase", game.field and game.field.phase,
      "anim", game.doorAnim and string.format("%.2f", game.doorAnim.t) or "-",
      "pos", game.playerX, game.playerY)
    if not game.field then break end
  end

  U.shot(game, out .. "/02_after.png")
  U.log("final map", game.map and game.map.id, "field", game.field and game.field.kind)
  love.event.quit()
end
