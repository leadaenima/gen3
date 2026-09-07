-- Native 240x160 naming canvas captures for stock parity diff.
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "tmp/ruby-naming"
  local Naming = require("src.ui.gen3.NamingScreen")
  love.filesystem.createDirectory(out:gsub("\\", "/"):gsub("^tmp/", "tmp/"))

  local function native(name, mutate)
    game:openNaming()
    local b = game.boot
    local f = b.naming
    f.name = ""
    b.name = ""
    f.page = 0
    f.cursorX, f.cursorY = 0, 0
    f.iconAnim = 12
    if mutate then mutate(f, b) end
    U.wait(3)
    -- Draw into a true GBA canvas and encode PNG.
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    Naming.draw(game, f)
    love.graphics.setCanvas()
    local id = canvas:newImageData()
    local path = out .. "/" .. name
    -- Prefer absolute write via io (Windows).
    local abs = path
    if not path:match("^[A-Za-z]:") then
      abs = love.filesystem.getWorkingDirectory() .. "/" .. path
    end
    local dir = abs:match("^(.*)[/\\][^/\\]+$")
    if dir then os.execute('mkdir "' .. dir .. '" 2>nul') end
    local png = id:encode("png")
    local fh = assert(io.open(abs, "wb"))
    fh:write(png:getString())
    fh:close()
    print("[native]", abs)
  end

  native("port_empty.png", function(f, b)
    f.name = ""; b.name = ""
  end)
  native("port_aaa.png", function(f, b)
    f.name = "AAA"; b.name = "AAA"
  end)
  native("port_brendan.png", function(f, b)
    f.name = "BRENDAN"; b.name = "BRENDAN"
  end)
  native("port_side_page.png", function(f, b)
    f.name = "AAA"; b.name = "AAA"
    f.cursorX, f.cursorY = 8, 0
  end)
  native("port_side_ok.png", function(f, b)
    f.name = "AAA"; b.name = "AAA"
    f.cursorX, f.cursorY = 8, 2
  end)
  native("port_lower.png", function(f, b)
    f.name = "AAA"; b.name = "AAA"
    f.page = 1
  end)
  native("port_anim0.png", function(f, b)
    f.name = "AAA"; b.name = "AAA"; f.iconAnim = 0
  end)
  native("port_anim24.png", function(f, b)
    f.name = "AAA"; b.name = "AAA"; f.iconAnim = 24
  end)

  print("[ruby_naming_native] done")
end
