-- Ruby naming_screen.c keyboard (UPPER/LOWER/OTHERS + PAGE/BACK/OK).
--   luajit tests/engine/ruby_naming_screen_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby naming screen")
local check = S.check
local eq = S.eq

local Naming = require("src.ui.gen3.NamingScreen")
local Input = require("src.core.Input")
Input:init()

local function pressKey(f, name)
  local host = {
    finishNickname = function()
      f._done = true
      return true
    end,
  }
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  Naming.step(host, f, Input)
  Input.wasPressed = old
end

;(function()
local f = Naming.open({ template = "mon", speciesName = "TORCHIC", initial = "TORCHIC" })
eq(f.maxChars, 10, "mon nicknames are 10")
eq(f.title, "TORCHIC's nickname?", "mon title uses species")
eq(Naming.charAt(0, 0, 0), "A", "UPPER starts at A")
pressKey(f, "a")
eq(f.name, "TORCHICA", "A appends when under the cap")
pressKey(f, "select")
eq(f.page, 1, "SELECT cycles to lower")
pressKey(f, "select")
eq(f.page, 2, "then OTHERS")
pressKey(f, "select")
eq(f.page, 0, "and wraps to UPPER")
pressKey(f, "b")
eq(f.name, "TORCHIC", "B deletes one")
pressKey(f, "start")
check(f._done, "START confirms via OK")
eq(f.cursorX, 8, "START parks on the OK column")
eq(f.cursorY, 2, "and the OK row")
end)()

;(function()
local f = Naming.open({ template = "player", initial = "BRENDAN" })
eq(f.maxChars, 7, "player names are 7")
eq(f.title, "YOUR NAME?", "player title")
f.name = "ABCDEFG"
pressKey(f, "a")
eq(f.name, "ABCDEFG", "full buffer refuses another letter")
f.cursorX, f.cursorY = 8, 0
pressKey(f, "a")
eq(f.page, 1, "PAGE button cycles")
f.cursorX, f.cursorY = 8, 1
pressKey(f, "a")
eq(f.name, "ABCDEF", "BACK button deletes")
f.cursorX, f.cursorY = 8, 2
pressKey(f, "a")
check(f._done, "OK button confirms")
end)()

;(function()
local f = Naming.open({ template = "box", initial = "BOX1" })
eq(f.maxChars, 8, "box names are 8")
eq(f.title, "BOX NAME?", "box title")
Naming.moveCursor(f, 1, 0)
eq(f.cursorX, 1, "right moves across letters")
for _ = 1, 7 do Naming.moveCursor(f, 1, 0) end
eq(f.cursorX, 8, "far right is PAGE/BACK/OK")
Naming.moveCursor(f, 0, 1)
eq(f.cursorY, 1, "side column has three rows")
end)()

S.finish()
