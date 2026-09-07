-- Minimal LÖVE port frame capture driver for visual validation.
-- Does NOT navigate to naming/title; waits N frames then shoots whatever
-- is on screen. Pair with a save/boot that already shows the scene, or
-- extend this driver to press inputs like tests/drivers/*.lua.
--
-- From PORT root (Windows cmd):
--
--   set POKEPORT_GAME=ruby
--   set POKEPORT_DRIVER=%CD%\tools\visual_validate\love_capture_driver.lua
--   set POKEPORT_SHOT_DIR=%CD%\tmp\visual_validate
--   set POKEPORT_SPEED=8
--   "C:\Program Files\LOVE\love.exe" --console .
--
-- Manual alternative (no driver): run love --console ., get to the scene,
-- then either:
--   - touch/skin "screenshot" action if bound, OR
--   - set Game.capturePath from a debug hook, OR
--   - OS snipping tool (not pixel-perfect / may include window chrome)
--
-- Programmatic path used by main.lua:
--   Game.capturePath = [[C:\...\tmp\visual_validate\love_foo.png]]
--   (consumed once in love.draw via love.graphics.captureScreenshot)

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "tmp/visual_validate"
local WAIT = tonumber(os.getenv("POKEPORT_SHOT_WAIT") or "180") or 180
local NAME = os.getenv("POKEPORT_SHOT_NAME") or "love_frame"

local function ensure_dir(path)
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if not dir or dir == "" then return end
  -- Windows + Unix best-effort
  os.execute('mkdir "' .. dir .. '" 2>nul')
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
end

return function(game)
  for _ = 1, WAIT do
    coroutine.yield()
  end
  local path = SHOT_DIR .. "/" .. NAME .. ".png"
  ensure_dir(path)
  game.capturePath = path
  for _ = 1, 120 do
    if not game.capturePath then break end
    coroutine.yield()
  end
  local f = io.open(path, "rb")
  if f then
    f:close()
    print("[visual_validate] wrote " .. path)
  else
    print("[visual_validate] FAIL missing " .. path)
  end
end
