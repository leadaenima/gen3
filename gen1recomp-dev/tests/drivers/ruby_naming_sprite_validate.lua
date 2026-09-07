-- Native 240x160 naming sprite captures for stock parity.
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-naming"
  local Naming = require("src.ui.gen3.NamingScreen")

  local function native(name, mutate)
    game:openNaming()
    local b = game.boot
    local f = b.naming
    f.name = "AAA"
    b.name = "AAA"
    f.page = 0
    f.cursorX, f.cursorY = 0, 0
    f.iconAnim = 8
    if mutate then mutate(f, b) end
    U.wait(2)
    f.iconAnim = (mutate and f.iconAnim) or f.iconAnim
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    -- Re-apply tick after any step() during wait.
    if f._forceAnim ~= nil then f.iconAnim = f._forceAnim end
    Naming.draw(game, f)
    love.graphics.setCanvas()
    local id = canvas:newImageData()
    local abs = out .. "/" .. name
    if not abs:match("^[A-Za-z]:") then
      abs = love.filesystem.getWorkingDirectory() .. "/" .. abs
    end
    local dir = abs:match("^(.*)[/\\][^/\\]+$")
    if dir then os.execute('mkdir "' .. dir .. '" 2>nul') end
    local png = id:encode("png")
    local fh = assert(io.open(abs, "wb"))
    fh:write(png:getString())
    fh:close()
    print("[sprite_validate]", abs, "iconAnim", f.iconAnim)
  end

  -- walk.south: 3@8, 0@8, 4@8, 0@8
  native("sprite_port_walkA.png", function(f)
    f._forceAnim = 0; f.iconAnim = 0
  end)
  native("sprite_port.png", function(f)
    f._forceAnim = 8; f.iconAnim = 8  -- idle / face-south frame in walk cycle
  end)
  native("sprite_port_idle.png", function(f)
    f._forceAnim = 8; f.iconAnim = 8
  end)
  native("sprite_port_walkB.png", function(f)
    f._forceAnim = 16; f.iconAnim = 16
  end)
  native("port_aaa.png", function(f)
    f._forceAnim = 8; f.iconAnim = 8
  end)
  native("port_anim0.png", function(f)
    f._forceAnim = 0; f.iconAnim = 0
  end)
  native("port_anim24.png", function(f)
    f._forceAnim = 24; f.iconAnim = 24  -- second idle slot
  end)

  print("[ruby_naming_sprite_validate] done")
end
