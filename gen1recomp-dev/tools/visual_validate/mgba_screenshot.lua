-- mGBA 0.10.5 GUI Lua helper (Tools > Scripting... > Load script)
-- Released win64 build has no reliable --script CLI; use this interactively
-- or paste into the scripting console after the ROM is loaded.
--
-- API: emu:screenshot(filename)  -- https://mgba.io/docs/scripting.html
--
-- Usage:
--   1. Open mGBA.exe, load Pokemon Ruby ROM
--   2. Tools > Scripting...
--   3. Load this file OR paste the run() call after editing OUT
--   4. Advance to the frame you care about, then run screenshot

local OUT = os.getenv("MGBA_SHOT")
if not OUT or OUT == "" then
  -- default next to the script when run from PORT checkout layout
  OUT = "tmp/visual_validate/stock_mgba_manual.png"
end

function capture_now(path)
  path = path or OUT
  emu:screenshot(path)
  console:log("screenshot -> " .. tostring(path))
end

-- Uncomment to auto-capture once after N frames from script load:
-- local target = emu:currentFrame() + 60
-- callbacks:add("frame", function()
--   if emu:currentFrame() >= target then
--     capture_now()
--     callbacks:remove("frame")
--   end
-- end)

console:log("mgba_screenshot.lua loaded. Call capture_now() or capture_now('C:/path/out.png')")
