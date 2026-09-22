-- Dump the real vertex stream WorldPrecip emits, so it can be rasterized
-- offline and LOOKED AT.
--
-- Everything else in this repo tests the simulation: where particles are, how
-- long they live, how evenly they cover the map. None of it can see the
-- screen, and several things that decide whether snow is visible at all are
-- purely a property of the geometry as projected:
--
--   * the billboard basis -- get it wrong and flakes are edge-on and invisible
--   * flake size in PIXELS -- chosen here from arithmetic, never once looked at
--   * whether looking up actually puts flakes overhead
--   * degenerate or inside-out quads, which draw as nothing
--
-- So: capture the vertices, project them in Python, rasterize, write a PNG.
-- This tests the geometry, NOT the GPU. It cannot see shader compile failures,
-- depth/blend state, or draw order against the cloud bank. Those still need
-- real hardware and a human.
--
-- Output format, one batch per draw call, in draw order:
--   BATCH <shader> <r> <g> <b> <a>      -- shader label + the setColor in force
--   <x> <y> <z> <tr> <tg> <tb> <ta>     -- one line per vertex
--
-- Usage: from the mod root, with an EYE/AIM injected by the caller.

local ROOT = "./"
local OUT = os.getenv("WP_DUMP_OUT") or "/tmp/wp_verts.txt"

-- Camera the caller wants. The eye MUST match the one the Python side projects
-- with, because billboarding orients every quad toward Voxel3D.eye -- feeding
-- one eye to the sim and rendering from another would silently fake a failure.
local EX = tonumber(os.getenv("WP_EYE_X")) or 100
local EY = tonumber(os.getenv("WP_EYE_Y")) or 10
local EZ = tonumber(os.getenv("WP_EYE_Z")) or 100
local WX = os.getenv("WP_WX") or "SNOW"
local SECONDS = tonumber(os.getenv("WP_SECONDS")) or 25

local out = assert(io.open(OUT, "w"))

-- Which shader a pass uses decides how its pixels are shaded, so the label has
-- to come from the shader source rather than from the order of draw calls.
-- Order matters. This originally tested for "smoothstep" first, which was fine
-- until the rain shader gained a tapered falloff and started using smoothstep
-- too -- at which point rain streaks were silently labelled "snow" and shaded
-- with the wrong pixel maths, and the rain pass vanished from the dump entirely.
-- Test the distinctive constant colour first; it is the thing that actually
-- identifies the rain shader.
-- Order matters: test the most specific marker first. The hail shader also
-- contains "smoothstep", so a smoothstep-first test would label it "snow" and
-- shade it with snow's soft falloff -- the render would show snowflakes and the
-- hail work would look like it had not landed.
local function labelFor(src)
  if src:find("length(p - vec2", 1, true) then return "hail" end
  if src:find("0.72, 0.82, 0.95", 1, true) then return "rain" end
  if src:find("smoothstep", 1, true) then return "snow" end
  return "grain"
end

-- Output is gated: the warm-up frames must be DRAWN, not just updated, because
-- face contact cannot arm until a draw has recorded the eye position (draw is
-- the only place Voxel3D.eye is available). Updating without drawing during
-- warm-up leaves fpv=false and face=0 forever, which would look like a broken
-- feature rather than a harness artifact.
local dumping = false
local curColor = { 1, 1, 1, 1 }
local curShader = "grain"
local pending = nil

local function newMockMesh(fmt, cap)
  local m = { verts = nil, n = 0 }
  function m:setVertices(v, startv, count)
    self.verts, self.n = v, count or #v
  end
  function m:setDrawRange(s, n) self.n = n end
  return m
end

love = {
  graphics = {
    newMesh = function(fmt, a) return newMockMesh(fmt, a) end,
    newShader = function(src) return { label = labelFor(src), send = function() end } end,
    setBlendMode = function() end,
    setDepthMode = function() end,
    setShader = function(sh) curShader = sh and sh.label or curShader end,
    setColor = function(r, g, b, a)
      curColor = { r or 1, g or 1, b or 1, a or 1 }
    end,
    draw = function(mesh)
      if not dumping then return end
      if not mesh or not mesh.verts or mesh.n < 3 then return end
      out:write(string.format("BATCH %s %.4f %.4f %.4f %.4f\n",
        curShader, curColor[1], curColor[2], curColor[3], curColor[4]))
      for i = 1, mesh.n do
        local v = mesh.verts[i]
        out:write(string.format("%.4f %.4f %.4f %.5f %.5f %.5f %.5f\n",
          v[1], v[2], v[3], v[4], v[5], v[6], v[7]))
      end
    end,
  },
}

local V = { require = function(n)
  if n == "Quality" then return { budget = function() return { worldPrecip = 1.0 } end } end
  if n == "Settings" then return { isFirstPerson = function() return true end } end
  error("no " .. n, 0)
end }

local WP = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)

local focus = { EX, EY - 10, EZ }   -- focus is the player's feet-ish, eye above
local weather = { wxId = WX }
-- Rain has no wxId fallback the way snow does, so intensity must be explicit.
if tonumber(os.getenv("WP_RAIN")) then
  weather.rainIntensity = tonumber(os.getenv("WP_RAIN"))
end
if tonumber(os.getenv("WP_SNOW")) then
  weather.snowIntensity = tonumber(os.getenv("WP_SNOW"))
end
if tonumber(os.getenv("WP_ASH")) then
  weather.ashIntensity = tonumber(os.getenv("WP_ASH"))
end
if tonumber(os.getenv("WP_HAIL")) then
  weather.hailIntensity = tonumber(os.getenv("WP_HAIL"))
end
if tonumber(os.getenv("WP_SAND")) then
  weather.sandIntensity = tonumber(os.getenv("WP_SAND"))
end
if tonumber(os.getenv("WP_DEBRIS")) then
  weather.debrisIntensity = tonumber(os.getenv("WP_DEBRIS"))
end
-- A far plane, so the streaming radius resolves the same way it would in game.
local Voxel3D = { vp = {}, eye = { EX, EY, EZ }, far = 400 }

-- Warm to steady state WITHOUT dumping, or the first frames (a young, top-heavy
-- field) would be what gets rendered.
for _ = 1, math.floor(SECONDS * 60) do
  WP.update(1 / 60, focus, weather)
  WP.draw(Voxel3D, { weather = weather })
end

-- One frame, dumped.
dumping = true
WP.update(1 / 60, focus, weather)
WP.draw(Voxel3D, { weather = weather })

out:close()
io.write(WP.describe(), "\n")
