-- Procedural flat-world continuation beyond the loaded voxel maps.
--
-- This is deliberately NOT another sky texture and it does not invent terrain.
-- It paints a low-cost, haze-weighted continuation of the world's flat ground
-- after the sky but before the live 3D depth pass. The playable voxel maps draw
-- over it. No mountains, hills, cliffs, or artificial elevation are generated.
--
-- The only purpose is to prevent an empty blue void beyond streamed map edges
-- on hosts that use this legacy backdrop path. Current strict-3D hosts normally
-- use HorizonApron/depth geometry instead, but legacy compatibility patches can
-- still call this module, so it must obey the same flat-world contract.

local V = ...

local Sky = V.require("Sky")
local DayNight = V.require("DayNight")

local DistantWorld = {}

local max, min = math.max, math.min

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function mix(a, b, t)
  return a + (b - a) * t
end

local function mix3(a, b, t)
  return { mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t) }
end

-- `edge` is the sky/horizon join in canvas pixels. `cx/cy` are accepted for
-- compatibility but intentionally do not create fake parallax/elevation: the
-- game world is a flat voxel plane and distant continuation stays flat.
function DistantWorld.draw(w, h, edge, sky, cx, cy)
  if not (w and h and w > 0 and h > 0 and sky and sky.bands) then return end
  local g = love and love.graphics
  if not g then return end

  edge = edge or Sky.region(h, nil) or h * Sky.SPAN
  edge = max(1, min(h * 0.55, edge))

  local haze = sky.bands[#sky.bands] or { sky[1] or 0.55, sky[2] or 0.72, sky[3] or 0.84 }
  local upper = sky.bands[max(1, #sky.bands - 1)] or haze
  local tint = DayNight.tint(true)
  local ground = mix3(haze, { 0.16 * tint[1], 0.30 * tint[2], 0.18 * tint[3] }, 0.58)
  local nearGround = mix3(haze, ground, 0.78)

  local oldShader = g.getShader and g.getShader() or nil
  local oldBlend, oldAlpha
  if g.getBlendMode then oldBlend, oldAlpha = g.getBlendMode() end
  g.setShader()
  if g.setBlendMode then g.setBlendMode("alpha", "alphamultiply") end

  -- Flat atmospheric ground continuation. Horizontal strips only change haze
  -- with viewing distance; their geometry remains level and creates no relief.
  local bandH = max(10, h * 0.055)
  for i = 0, 5 do
    local y0 = edge + i * bandH
    local t = i / 5
    local c = mix3(nearGround, ground, t)
    g.setColor(clamp01(c[1]), clamp01(c[2]), clamp01(c[3]), 1)
    g.rectangle("fill", 0, y0, w, max(bandH + 2, h - y0))
  end

  -- A thin atmospheric veil hides the sky/ground seam without adding a fake
  -- ridge silhouette. Actual buildings, trees, water and terrain come only
  -- from streamed game maps and therefore remain authoritative.
  local veil = mix3(haze, upper, 0.20)
  g.setColor(veil[1], veil[2], veil[3], 0.18)
  g.rectangle("fill", 0, edge - h * 0.006, w, h * 0.034)

  g.setColor(1, 1, 1, 1)
  if g.setBlendMode and oldBlend then g.setBlendMode(oldBlend, oldAlpha) end
  if oldShader then g.setShader(oldShader) else g.setShader() end
end

return DistantWorld
