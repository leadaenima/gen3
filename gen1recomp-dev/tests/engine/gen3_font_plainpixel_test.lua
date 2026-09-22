#!/usr/bin/env luajit
-- Prove Gen3Compat Font: no "no glyph" spam, draw/width via Plain Pixel path.
package.path = "./?.lua;./?/init.lua;" .. package.path


package.preload["src.render.Assets"] = function()
  return {
    image = function() error("no image in headless test") end,
    imageData = function() return nil end,
    provide = function() end,
    provides = function() return false end,
  }
end

local warnings = {}
package.preload["src.core.Logger"] = function()
  return {
    info = function() end,
    warn = function(a, b, ...)
      -- support Logger.warn(fmt, ...) and Logger:warn(fmt, ...)
      local fmt, args
      if type(a) == "table" then
        fmt, args = b, { ... }
      else
        fmt, args = a, { b, ... }
      end
      warnings[#warnings + 1] = string.format(tostring(fmt), unpack(args))
    end,
    error = function() end,
    debug = function() end,
  }
end

local prints = {}
local fakeFont = {
  getWidth = function(_, text) return #tostring(text or "") * 8 end,
  setFilter = function() end,
  getHeight = function() return 8 end,
  getBaseline = function() return 7 end,
}
love = {
  graphics = {
    newFont = function() return fakeFont end,
    print = function(text, x, y)
      prints[#prints + 1] = { text = tostring(text), x = x, y = y }
    end,
    getFont = function() return nil end,
    setFont = function() end,
    getColor = function() return 0, 0, 0, 1 end,
    setColor = function() end,
    rectangle = function() end,
  },
  filesystem = {
    load = function(rel)
      local fh = io.open(rel, "rb") or io.open("./" .. rel, "rb")
      if not fh then return nil end
      local src = fh:read("*a")
      fh:close()
      return loadstring(src) or load(src)
    end,
  },
}

local failed = 0
local function check(cond, msg)
  if cond then
    io.write("ok  " .. msg .. "\n")
  else
    failed = failed + 1
    io.write("FAIL " .. msg .. "\n")
  end
end

local function resetMods()
  package.loaded["src.mods.Gen3Compat"] = nil
  package.loaded["src.render.Font"] = nil
  package.preload["src.render.Font"] = nil
  warnings = {}
  prints = {}
end

---------------------------------------------------------------- scenario 1
resetMods()
local Gen3Compat = require("src.mods.Gen3Compat")
local Font = Gen3Compat.resolve("src.render.Font", "test")
check(type(Font) == "table", "resolve returns Font table")
check(type(Font.draw) == "function", "Font.draw exists")
check(type(Font.encode) == "function", "Font.encode exists")

local codes = Font.encode("POISON SAVE")
check(type(codes) == "table" and #codes == 0, "encode returns empty table")
local glyphWarn = false
for _, w in ipairs(warnings) do
  if tostring(w):find("no glyph", 1, true) then glyphWarn = true end
end
check(not glyphWarn, "encode: no glyph warnings")

local w = Font.width("QOL TOGGLES")
check(type(w) == "number" and w > 0, "width positive")

prints = {}
warnings = {}
Font.draw("POISON SAVE", 16, 16)
check(#prints >= 1 and prints[1].text == "POISON SAVE", "draw prints label")
glyphWarn = false
for _, w in ipairs(warnings) do
  if tostring(w):find("no glyph", 1, true) then glyphWarn = true end
end
check(not glyphWarn, "draw: no glyph warnings")
check(pcall(Font.drawBox, 0, 1, 20, 3), "drawBox ok")
check(pcall(Font.load, { font = { kind = "font3" } }), "load ok")
prints = {}
Font.draw("RUN HOLD B", 8, 8)
check(#prints >= 1 and prints[1].text == "RUN HOLD B", "draw after load")

warnings = {}
prints = {}
for _, label in ipairs({
  "POISON SAVE", "FULL HEAL CATCH", "RUN (HOLD B)", "INFINITE REPEL", "CANCEL",
}) do
  Font.drawBox(1, 1, 8, 6)
  Font.draw(label, 16, 24)
end
glyphWarn = false
for _, w in ipairs(warnings) do
  if tostring(w):find("no glyph", 1, true) then glyphWarn = true end
end
check(not glyphWarn, "QOL label loop: no glyph spam")
check(#prints >= 5, "QOL label loop: printed")

---------------------------------------------------------------- scenario 2
-- Engine already has a Font module in package.loaded (raw encode spams).
resetMods()
local rawFont = {}
function rawFont.encode(text)
  text = tostring(text or "")
  local Logger = require("src.core.Logger")
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch:byte() >= 32 then
      Logger.warn("font: no glyph for %q", ch)
    end
  end
  return {}
end
function rawFont.draw(text, x, y)
  rawFont.encode(text) -- the broken path
end
function rawFont.width(text) return #tostring(text or "") * 8 end
function rawFont.drawBox() end
function rawFont.load() end
package.loaded["src.render.Font"] = rawFont

-- Baseline: raw encode spams
warnings = {}
rawFont.encode("AB")
local baseline = false
for _, w in ipairs(warnings) do
  if tostring(w):find("no glyph", 1, true) then baseline = true end
end
check(baseline, "baseline: raw Font.encode spams (proves the bug)")

local Gen3Compat = require("src.mods.Gen3Compat")
Gen3Compat.bind(function() return nil end)
check(rawFont._gen3PlainPixel == true, "bind marks preloaded Font as armed")
warnings = {}
prints = {}
rawFont.encode("POISON SAVE")
rawFont.draw("POISON SAVE", 0, 0)
local glyphWarn = false
for _, w in ipairs(warnings) do
  if tostring(w):find("no glyph", 1, true) then glyphWarn = true end
end
check(not glyphWarn, "after bind: preloaded Font has no glyph spam")
check(#prints >= 1 and prints[1].text == "POISON SAVE", "after bind: preloaded Font draws via print")

io.write(string.format("\ngen3 font plainpixel: %d failed\n", failed))
os.exit(failed == 0 and 0 or 1)
