-- Desktop HostShell.restart must not use love.event.quit("restart") when a
-- process spawn is available: in-process restart re-enters love's boot.lua,
-- calls love.filesystem.init again, and crashes with
-- "Failed to initialize filesystem: already initialized" whenever PHYSFS
-- deinit failed (open handles after a long DRAMATIC_SHAPE mesh session --
-- same class of failure as AppImage / Android #575).
--   luajit tests/engine/host_restart_desktop_physfs.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local quits = {}
love.event = {
  quit = function(...)
    quits[#quits + 1] = { n = select("#", ...), arg = (...) }
  end,
}

local osName = "Windows"
love.system = love.system or {}
love.system.getOS = function() return osName end

-- Pretend we are a fused Windows build with a real executable path so
-- spawnSelfDetached can build a command (we stub os.execute below).
love.filesystem = love.filesystem or {}
love.filesystem.getExecutablePath = function() return "C:\\Game\\gen1recomp.exe" end
love.filesystem.getSource = function() return "C:\\Source\\gen1recomp" end
love.filesystem.isFused = function() return true end

package.loaded["src.core.Platform"] = {
  canSpawnProcess = function() return true end,
}

local spawned = 0
local execute = os.execute
os.execute = function(cmd)
  spawned = spawned + 1
  check(type(cmd) == "string" and #cmd > 0, "spawn command non-empty")
  return 0
end

-- Fresh load so HostShell picks up the Platform stub
package.loaded["src.core.HostShell"] = nil
local HostShell = require("src.core.HostShell")

HostShell.restart()
eq(spawned, 1, "Windows restart spawns a detached sibling process")
eq(#quits, 1, "and queues exactly one quit")
eq(quits[1].n, 0, "clean quit(), never quit(\"restart\") -- avoids PHYSFS double-init")

-- macOS / Linux non-AppImage take the same path
osName = "OS X"
quits, spawned = {}, 0
HostShell.restart()
eq(spawned, 1, "macOS restart also process-relaunches")
eq(quits[1] and quits[1].n, 0, "macOS also clean-quits")

osName = "Linux"
quits, spawned = {}, 0
HostShell.restart()
eq(spawned, 1, "Linux (non-AppImage) restart also process-relaunches")
eq(quits[1] and quits[1].n, 0, "Linux also clean-quits")

-- When spawn cannot run, fall back to in-process restart (last resort)
package.loaded["src.core.Platform"] = {
  canSpawnProcess = function() return false end,
}
package.loaded["src.core.HostShell"] = nil
HostShell = require("src.core.HostShell")
osName = "Windows"
quits, spawned = {}, 0
HostShell.restart()
eq(spawned, 0, "no spawn when Platform forbids it")
eq(quits[1] and quits[1].arg, "restart", "last resort is still quit(\"restart\")")

os.execute = execute
T.finish("host_restart_desktop_physfs")
