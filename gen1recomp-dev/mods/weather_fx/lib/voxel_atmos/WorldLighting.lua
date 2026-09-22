-- ============================================================================
-- WORLD-SPACE WEATHER LIGHTING
-- ============================================================================
-- Weather FX 3D lighting lives in the same coordinate space as the voxel world.
-- This pass intentionally does NOT paint a screen flash. It renders depth-tested
-- additive light volumes at the real strike locations published by
-- WorldLightning. Camera motion only changes the view into those volumes.
--
-- The voxel host already owns directional sun/moon terrain lighting and shadows;
-- DramalessAtmos aligns that host light direction to Weather FX celestial shear.
-- This module supplies the missing LOCAL weather-light layer: lightning light at
-- the cloud source and terrain impact.
-- ============================================================================

local V = ...
local floor, min, max, sin, cos = math.floor, math.min, math.max, math.sin, math.cos
local PI2 = math.pi * 2

local Lighting = {}

local GROUND_SEGMENTS = 24
local CLOUD_SEGMENTS = 20
local GROUND_LIFT = 0.20
local MAX_LIGHTS = 4

local mesh, shader
local meshCap = 0
local drawnVerts = 0
local drawCalls = 0

local FMT = {
  { "VertexPosition", "float", 3 },
  { "LightTint", "float", 4 },
}

local verts = {}
local vcap = 0
local vn = 0

local function reserve(n)
  for i = vcap + 1, n do verts[i] = {0,0,0,0,0,0,0} end
  if n > vcap then vcap = n end
end

local function reset() vn = 0 end
local function push(x,y,z,r,g,b,a)
  local n = vn + 1
  vn = n
  local t = verts[n]
  if not t then t = {0,0,0,0,0,0,0}; verts[n] = t; vcap = n end
  t[1],t[2],t[3],t[4],t[5],t[6],t[7] = x,y,z,r,g,b,a
end

local function disc(cx, cy, cz, radius, alpha, r, g, b, segments)
  if radius <= 0 or alpha <= 0 then return end
  segments = segments or 20
  for i = 0, segments - 1 do
    local a0 = PI2 * i / segments
    local a1 = PI2 * (i + 1) / segments
    push(cx, cy, cz, r,g,b, alpha)
    push(cx + cos(a0)*radius, cy, cz + sin(a0)*radius, r,g,b, 0)
    push(cx + cos(a1)*radius, cy, cz + sin(a1)*radius, r,g,b, 0)
  end
end

local function verticalGlow(cx, cy, cz, radius, height, alpha, r, g, b)
  -- Two crossed world planes. They are not camera billboards and therefore do
  -- not move with the camera; they simply give the ionised channel a local air
  -- glow from more than one viewing direction.
  local y0, y1 = cy, cy + height
  local function quad(ax,az,bx,bz)
    push(cx+ax, y0, cz+az, r,g,b, 0)
    push(cx+bx, y0, cz+bz, r,g,b, 0)
    push(cx+bx, y1, cz+bz, r,g,b, alpha)
    push(cx+ax, y0, cz+az, r,g,b, 0)
    push(cx+bx, y1, cz+bz, r,g,b, alpha)
    push(cx+ax, y1, cz+az, r,g,b, alpha)
  end
  quad(-radius,0, radius,0)
  quad(0,-radius, 0,radius)
end

local function getShader()
  if shader ~= nil then return shader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    shader = false
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 LightTint;
  varying vec4 vLight;
  vec4 position(mat4 t, vec4 v) {
    vLight = LightTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vLight;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return vec4(vLight.rgb, max(0.0, vLight.a)) * color;
  }
#endif
]])
  shader = (ok and sh) or false
  return shader or nil
end

local function upload()
  if vn < 3 then return nil end
  if not mesh or meshCap < vn then
    local want = floor(vn * 1.35) + 96
    reserve(want)
    local ok, m = pcall(love.graphics.newMesh, FMT, want, "triangles", "stream")
    if not ok or not m then return nil end
    mesh, meshCap = m, want
  end
  if not pcall(mesh.setVertices, mesh, verts, 1, vn) then
    local slice = {}
    for i=1,vn do slice[i] = verts[i] end
    if not pcall(mesh.setVertices, mesh, slice) then return nil end
  end
  pcall(mesh.setDrawRange, mesh, 1, vn)
  return mesh
end

function Lighting.draw(Voxel3D, WorldLightning)
  drawnVerts, drawCalls = 0, 0
  local flashScale=1
  local okS,S=pcall(V.require,"Settings")
  if okS and S and S.lightningFlashScale then local okV,v=pcall(S.lightningFlashScale); if okV and tonumber(v) then flashScale=max(0,tonumber(v)) end end
  if not (Voxel3D and Voxel3D.vp and WorldLightning and WorldLightning.lights) then return false end
  local lights = WorldLightning.lights()
  if type(lights) ~= "table" or #lights == 0 then return true end

  reset()
  local used = 0
  for i=1,#lights do
    local L = lights[i]
    if L and (L.intensity or 0) > 0.005 then
      used = used + 1
      if used > MAX_LIGHTS then break end
      local p = max(0, min(1, (tonumber(L.intensity) or 0) * flashScale))
      local power = max(0.12, min(1, tonumber(L.power) or 0.4))
      local groundR = 22 + 82 * power
      local cloudR = 28 + 72 * power
      -- Ground bounce: just above the sampled terrain so the depth buffer lets
      -- buildings/world geometry occlude it naturally.
      disc(L.x or 0, (L.y or 0) + GROUND_LIFT, L.z or 0,
           groundR, p * 0.42, 0.70,0.82,1.00, GROUND_SEGMENTS)
      -- Cloud illumination is a real world-space disc at the bolt source, not a
      -- full-screen white flash.
      disc(L.topX or L.x or 0, L.topY or 100, L.topZ or L.z or 0,
           cloudR, p * 0.30, 0.78,0.88,1.00, CLOUD_SEGMENTS)
      verticalGlow(L.x or 0, (L.y or 0)+1.0, L.z or 0,
                   8 + 18*power, max(18, (L.topY or 80) - (L.y or 0)),
                   p * 0.11, 0.68,0.80,1.00)
    end
  end
  drawnVerts = vn
  if vn < 3 then return true end

  local m = upload()
  local sh = getShader()
  if not (m and sh) then return false end

  pcall(love.graphics.setBlendMode, "add", "alphamultiply")
  pcall(love.graphics.setDepthMode, "lequal", false)
  local began = false
  if Voxel3D.beginEffect then began = Voxel3D.beginEffect(sh) and true or false end
  if not began then pcall(love.graphics.setShader, sh) end
  pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
  pcall(sh.send, sh, "vp", Voxel3D.vp)
  pcall(love.graphics.setColor, 1,1,1,1)
  local ok = pcall(love.graphics.draw, m)
  if ok then drawCalls = drawCalls + 1 end
  if Voxel3D.endEffect then pcall(Voxel3D.endEffect) else pcall(love.graphics.setShader) end
  pcall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  pcall(love.graphics.setDepthMode, "lequal", true)
  return ok
end

function Lighting.status()
  return { vertices = drawnVerts, draws = drawCalls }
end

function Lighting.invalidate()
  mesh, shader, meshCap = nil, nil, 0
  drawnVerts, drawCalls = 0, 0
end

return Lighting
