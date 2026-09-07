-- Mobile fill scale for Ruby battles / letterbox screens, and auto zoom-in
-- on small indoor maps.
--   luajit tests/engine/ruby_mobile_scale_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby mobile scale")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")

local g = Game3.new()
local w, h = 1080, 2400 -- tall phone portrait

Game3._forceMobile = false
local fixedScale = select(1, g:frameScale(w, h))
eq(fixedScale, math.floor(math.min(w / 240, h / 160)),
  "desktop keeps integer letterbox scale")

Game3._forceMobile = true
local fillScale = select(1, g:frameScale(w, h))
check(fillScale > fixedScale,
  "mobile fill scale is larger than integer letterbox")
eq(fillScale, math.min(w / 240, h / 160),
  "mobile fill uses the window aspect fit")

check(g:wantsFillScale(), "mobile always wants fill scale")
g.options = { battleFit = "fixed" }
check(g:wantsFillScale(), "even with battleFit fixed on mobile")

Game3._forceMobile = false
g.options = { battleFit = "fill" }
check(g:wantsFillScale(), "desktop honors battleFit fill")
g.options = { battleFit = "fixed" }
eq(g:wantsFillScale(), false, "desktop fixed stays fixed")

Game3._forceMobile = true
g.phase = "play"
g.map = { width = 8, height = 8, mapType = Game3.MAP_TYPE_INDOOR }
g.fitScale = function() return 4 end
g.windowSize = function() return w, h end
local Zoom = require("src.render.Zoom")
local savedOff = Zoom.offset
Zoom.offset = 0
local base = Zoom.scale(4)
local boosted = g:overworldZoomScale()
check(boosted > base, "small indoor maps zoom in on mobile")
g.map = { width = 8, height = 8, mapType = Game3.MAP_TYPE_TOWN }
eq(g:overworldZoomScale(), base, "a small outdoor town keeps survey zoom")
g.map = { width = 40, height = 20, mapType = Game3.MAP_TYPE_ROUTE }
eq(g:overworldZoomScale(), base, "routes keep the same survey zoom")
g.map = { width = 24, height = 24, mapType = Game3.MAP_TYPE_ROUTE }
eq(g:overworldZoomScale(), base, "so do smaller routes")
g.map = { width = 8, height = 8, mapType = Game3.MAP_TYPE_INDOOR }
Zoom.offset = -2
local outIndoor = g:overworldZoomScale()
check(outIndoor < boosted, "OPTIONS OUT still zooms out inside")
g.map = { width = 40, height = 40, mapType = Game3.MAP_TYPE_ROUTE }
local outOver = g:overworldZoomScale()
check(outOver < base, "and OUT still works on the overworld")
Zoom.offset = savedOff

-- Zoom must not hard-crash when ShaderFX is absent (slim builds / stale APKs).
do
  package.loaded["src.render.Zoom"] = nil
  package.loaded["src.render.ShaderFX"] = nil
  package.preload["src.render.ShaderFX"] = function()
    error("module 'src.render.ShaderFX' not found", 2)
  end
  local ZoomNoFx = require("src.render.Zoom")
  local lo, hi = ZoomNoFx.offsetRange(4)
  check(lo <= hi, "offsetRange works without ShaderFX")
  package.preload["src.render.ShaderFX"] = nil
  package.loaded["src.render.ShaderFX"] = nil
  package.loaded["src.render.Zoom"] = nil
end

Game3._forceMobile = nil
g.options = nil
g.map = nil
g.fitScale = nil
g.windowSize = nil

S.finish("ruby mobile scale")
