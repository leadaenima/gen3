-- FOG AND MIST: banks of drifting cloud, generated at runtime.
--
-- WHY THERE IS NO FOG TEXTURE IN assets/.  Two reasons, and the second is
-- the real one.  A tiling noise sheet would be a few kilobytes, which is
-- nothing -- but it would also be a hand-authored asset that has to look
-- right at every zoom on both renderers, and value noise is four lines of
-- arithmetic that always does.  Generating it means the mod ships no
-- pixels at all: nothing derived from the ROM, nothing to license, nothing
-- to keep in step with a palette mode.
--
-- HOW IT READS AS DEPTH WITHOUT ANY DEPTH.  Three things, none of which
-- need the scene:
--
--   * LAYERS AT DIFFERENT SCALES AND SPEEDS.  The near bank is large and
--     fast, the far bank small and slow.  Parallax between them is the
--     whole illusion, and it costs one extra quad per layer.
--   * A VERTICAL GRADIENT.  Fog pools low.  The mesh carries per-vertex
--     alpha, so the bottom of the screen is dense and the top is nearly
--     clear in a single draw rather than a stack of scissored bands.
--   * DRIFT TIED TO THE CAMERA, not just to the clock.  Walking east
--     slides the banks west at a fraction of the world's speed, so they
--     sit at a distance instead of being stuck to the glass.  The fraction
--     is small (fog is close), which is what separates it from Dramatic
--     Shape's horizon backdrop, which is pinned to the player precisely
--     because it is far away.
--
-- COST.  One 128x128 texture built once, one four-vertex mesh reused per
-- layer, and one draw per layer -- so the LOW tier's single layer is a
-- single quad.  Nothing here scales with particle count.

local V = ...

local Fog = {}

local NOISE = 128          -- texture edge, power of two so wrapping is exact
local LATTICE = 16         -- value-noise grid; NOISE/LATTICE = cell size

local texture, mesh = nil, nil
local textureEdge = nil

-- ------- the noise
--
-- Value noise: a lattice of random values, smoothly interpolated, summed
-- over three octaves.  Seeded deterministically so the sheet is the same
-- every launch -- a fog bank that differed between sessions would be an
-- invisible difference bought with an unreproducible bug report.

local function smoothstep(t)
  return t * t * (3 - 2 * t)
end

local function buildLattice(size, seed)
  local grid = {}
  local s = seed
  for y = 0, size - 1 do
    grid[y] = {}
    for x = 0, size - 1 do
      -- a cheap deterministic hash; quality here only has to beat "looks
      -- like a grid", which it does
      s = (s * 1103515245 + 12345) % 2147483648
      grid[y][x] = (s % 65536) / 65535
    end
  end
  return grid
end

local function sampleLattice(grid, size, x, y)
  local x0, y0 = math.floor(x), math.floor(y)
  local fx, fy = smoothstep(x - x0), smoothstep(y - y0)
  local xa, xb = x0 % size, (x0 + 1) % size
  local ya, yb = y0 % size, (y0 + 1) % size
  local v00, v10 = grid[ya][xa], grid[ya][xb]
  local v01, v11 = grid[yb][xa], grid[yb][xb]
  local top = v00 + (v10 - v00) * fx
  local bot = v01 + (v11 - v01) * fx
  return top + (bot - top) * fy
end

local function desiredNoiseEdge()
  local scale=1
  pcall(function()
    local Q=V.require("Quality")
    if Q and Q.textureScale then scale=tonumber(Q.textureScale()) or 1 end
  end)
  if scale<=.30 then return 32 elseif scale<.75 then return 64 end
  return NOISE
end

local function buildTexture()
  local edge=desiredNoiseEdge()
  if texture and textureEdge==edge then return texture end
  if texture and texture.release then pcall(texture.release,texture) end
  if mesh and mesh.release then pcall(mesh.release,mesh) end
  texture,mesh,textureEdge=nil,nil,nil
  if not (love and love.graphics and love.image) then return nil end
  local ok, image = pcall(function()
    local lattice=math.max(4,math.floor(edge/8))
    local data = love.image.newImageData(edge, edge)
    local octaves = {
      { grid = buildLattice(lattice, 20260805), cells = lattice, gain = 0.55 },
      { grid = buildLattice(lattice * 2, 991), cells = lattice * 2, gain = 0.30 },
      { grid = buildLattice(lattice * 4, 7717), cells = lattice * 4, gain = 0.15 },
    }
    data:mapPixel(function(px, py)
      local v = 0
      for _, oct in ipairs(octaves) do
        local sx = px / edge * oct.cells
        local sy = py / edge * oct.cells
        v = v + sampleLattice(oct.grid, oct.cells, sx, sy) * oct.gain
      end
      -- Bias toward transparency: raw noise averages 0.5, which would be a
      -- flat grey sheet.  The curve keeps the bright wisps and clears the
      -- middle, which is what makes it read as separate banks.
      v = math.max(0, (v - 0.42) / 0.58)
      v = v * v * (3 - 2 * math.min(1, v))
      return 1, 1, 1, math.min(1, v)
    end)
    local img = love.graphics.newImage(data)
    img:setFilter("linear", "linear")
    img:setWrap("repeat", "repeat")
    return img
  end)
  if not ok then return nil end
  texture = image
  textureEdge = edge
  return texture
end

local function buildMesh()
  if mesh then return mesh end
  if not buildTexture() then return nil end
  local ok, made = pcall(function()
    local m = love.graphics.newMesh({
      { 0, 0, 0, 0, 1, 1, 1, 1 },
      { 1, 0, 1, 0, 1, 1, 1, 1 },
      { 1, 1, 1, 1, 1, 1, 1, 1 },
      { 0, 1, 0, 1, 1, 1, 1, 1 },
    }, "fan", "stream")
    m:setTexture(texture)
    return m
  end)
  if not ok then return nil end
  mesh = made
  return mesh
end

function Fog.invalidate()
  if texture and texture.release then pcall(texture.release,texture) end
  if mesh and mesh.release then pcall(mesh.release,mesh) end
  texture, mesh, textureEdge = nil, nil, nil
end

function Fog.ready()
  return buildTexture() ~= nil
end

-- ------- layers
--
-- scale  how many texture tiles fit across the screen (small = far)
-- speed  drift in tiles per second
-- para   how much of the camera's motion the layer takes, 0..1
-- top    alpha at the top edge, bot at the bottom -- the gradient
-- weight share of the fog channel this layer carries

Fog.LAYERS = {
  -- Long-distance visibility loss: stronger far (top) + heavy weights.
  { scale = 1.00, speed = 0.012, para = 0.16, top = 0.62, bot = 1.00, weight = 2.80 },
  { scale = 2.00, speed = 0.028, para = 0.09, top = 0.50, bot = 1.00, weight = 2.20 },
  { scale = 3.50, speed = 0.048, para = 0.05, top = 0.38, bot = 0.98, weight = 1.70 },
  -- Extra banks for top-down / lower quality (still capped by layers arg)
  { scale = 1.40, speed = 0.018, para = 0.12, top = 0.45, bot = 1.00, weight = 2.40 },
  { scale = 2.80, speed = 0.036, para = 0.07, top = 0.32, bot = 0.96, weight = 1.90 },
}

-- Ground fog: pools in the lower screen (top-down / diorama). top alpha
-- near 0 so sky stays readable; bot heavy so the map floor is hazed.
Fog.GROUND_LAYERS = {
  { scale = 0.85, speed = 0.010, para = 0.20, top = 0.05, bot = 1.00, weight = 3.20, y0 = 0.35 },
  { scale = 1.60, speed = 0.022, para = 0.12, top = 0.08, bot = 1.00, weight = 2.60, y0 = 0.48 },
  { scale = 2.40, speed = 0.038, para = 0.06, top = 0.04, bot = 0.95, weight = 2.00, y0 = 0.55 },
}

local FOG_R, FOG_G, FOG_B = 0.86, 0.89, 0.93   -- a cool white, never pure

-- 8.0.2: fog can submit many banks per frame. Reuse one four-row staging
-- quad instead of allocating four nested vertex tables for each layer/bank.
Fog._quadVerts = Fog._quadVerts or {
  {0,0,0,0,1,1,1,1},{0,0,0,0,1,1,1,1},
  {0,0,0,0,1,1,1,1},{0,0,0,0,1,1,1,1},
}
local function setQuad(m,x0,y0,x1,y1,u0,v0,u1,v1,a0,a1,a2,a3)
  local q=Fog._quadVerts
  local r=q[1];r[1],r[2],r[3],r[4],r[5],r[6],r[7],r[8]=x0,y0,u0,v0,FOG_R,FOG_G,FOG_B,a0
  r=q[2];r[1],r[2],r[3],r[4],r[5],r[6],r[7],r[8]=x1,y0,u1,v0,FOG_R,FOG_G,FOG_B,a1
  r=q[3];r[1],r[2],r[3],r[4],r[5],r[6],r[7],r[8]=x1,y1,u1,v1,FOG_R,FOG_G,FOG_B,a2
  r=q[4];r[1],r[2],r[3],r[4],r[5],r[6],r[7],r[8]=x0,y1,u0,v1,FOG_R,FOG_G,FOG_B,a3
  m:setVertices(q)
end
local FOG_DIR = 1   -- +1 = autonomous drift to the right of the screen
-- Camera parallax sign is separate from wind/time drift. Gen1Recomp exposes
-- the 2D camera here as a render translation, not a positive world-scroll
-- distance. Sand/dust therefore need the inverse sign so walking east makes
-- the suspended haze slide west on screen (and likewise on Y), rather than
-- looking glued to/following the player. Ordinary fog keeps its historical
-- sign; Draw selects -1 only for the 2D sand/dust bank.
local FOG_CAM_DIR = 1

function Fog.setTint(r, g, b, dir, camDir)
  if r then FOG_R, FOG_G, FOG_B = r, g, b end
  if dir ~= nil then FOG_DIR = dir end
  if camDir ~= nil then FOG_CAM_DIR = (camDir < 0) and -1 or 1 end
end

function Fog.resetTint()
  FOG_R, FOG_G, FOG_B = 0.86, 0.89, 0.93
  FOG_DIR = 1
  FOG_CAM_DIR = 1
end

-- `amount` is the eased fog channel, `layers` the quality cap, `t` the
-- weather clock, `camX/camY` the world camera in world pixels, `scale` the
-- frame's pixels-per-GB-pixel, and `w/h` the rect.
function Fog.draw(amount, alpha, layers, t, camX, camY, scale, w, h, speedCh)
  if amount <= 0 or alpha <= 0 then return end
  local m = buildMesh()
  if not m then return end
  local drift = 0.6 + 0.9 * (speedCh or 0.5)

  love.graphics.setBlendMode("alpha")
  for i = 1, math.min(layers or 1, #Fog.LAYERS) do
    local L = Fog.LAYERS[i]
    -- tiles across the screen: keeping this proportional to the rect's
    -- aspect means a wide window shows more fog, not stretched fog
    local tilesX = L.scale * (w / (160 * scale))
    local tilesY = L.scale * (h / (144 * scale))
    -- Wrapped into 0..1 before it reaches the mesh.  The texture repeats,
    -- so subtracting whole tiles is invisible -- and it keeps the uv a
    -- small number after an hour of play instead of one large enough to
    -- start losing precision against the tile size.
    -- FOG_DIR > 0 → banks travel right (matches sand/dust grain motion).
    local ox = ((-FOG_DIR * t * L.speed * drift) + FOG_CAM_DIR * (camX / (160 * 16)) * L.para) % 1
    local oy = ((t * L.speed * drift * 0.35) + FOG_CAM_DIR * (camY / (144 * 16)) * L.para) % 1
    -- Extreme amounts (FOG INTENSITY 200%+) stack dense; soft-cap per layer at 1.
    local a = alpha * amount * L.weight
    if a > 1.35 then a = 1.35 end
    -- per-vertex uv (the scroll) and alpha (the gradient) in one update
    setQuad(m,0,0,w,h,ox,oy,ox+tilesX,oy+tilesY,a*L.top,a*L.top,a*L.bot,a*L.bot)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(m)
  end
end

-- Top-down / diorama ground fog: dense banks in the lower portion of the
-- frame so fog remains readable when the camera is not in first person.
-- `strength` is scaled by FOG INTENSITY × weather intensity × quality.
function Fog.drawGround(amount, alpha, layers, t, camX, camY, scale, w, h, speedCh, strength)
  if amount <= 0 or alpha <= 0 then return end
  strength = strength or 1
  if strength <= 0.01 then return end
  if not Fog.GROUND_LAYERS then return end
  local m = buildMesh()
  if not m then return end
  local drift = 0.55 + 0.85 * (speedCh or 0.5)
  local n = math.max(1, math.min(layers or 2, #Fog.GROUND_LAYERS))
  love.graphics.setBlendMode("alpha")
  for i = 1, n do
    local L = Fog.GROUND_LAYERS[i]
    local y0 = (L.y0 or 0.4) * h
    local gh = h - y0
    if gh < 4 then gh = h * 0.4; y0 = h - gh end
    local tilesX = L.scale * (w / (160 * scale))
    local tilesY = L.scale * (gh / (144 * scale))
    local ox = ((-FOG_DIR * t * L.speed * drift) + FOG_CAM_DIR * (camX / (160 * 16)) * L.para) % 1
    local oy = ((t * L.speed * drift * 0.4) + FOG_CAM_DIR * (camY / (144 * 16)) * L.para) % 1
    local a = alpha * amount * L.weight * strength
    if a > 1.45 then a = 1.45 end
    local topA = a * (L.top or 0.05)
    local botA = a * (L.bot or 1)
    setQuad(m,0,y0,w,h,ox,oy,ox+tilesX,oy+tilesY,topA,topA,botA,botA)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(m)
  end
end

-- ------- world-anchored sand / dust field
--
-- Ordinary 2D fog is intentionally a screen-filling atmospheric layer. Sand
-- and dust are different: they need to read as suspended banks that occupy
-- the MAP, not as a texture pasted to the glass.  These layers therefore use
-- deterministic world cells. Each cell owns a translucent noise bank; camera
-- movement changes the bank geometry's screen position, and cells outside the
-- view are recycled by integer wrapping. Nothing is stored per frame, so the
-- field is stable across map walking and has no allocation churn.
--
-- Dimensions are in Game-Boy/world pixels and multiplied by the active 2D
-- scale at draw time. `cam` on Gen1Recomp's flat renderer is a render
-- translation, so subtracting camX/camY from an anchored world coordinate makes the
-- bank move opposite player travel. `camFactor` gives depth parallax while
-- preserving that direction.
Fog.WORLD_LAYERS = {
  -- Bank footprints overlap their cells slightly, so the field remains continuous
  -- while needing far fewer draw calls than a screen-sized particle cloud.
  -- No bank is allowed to become a viewport-sized sheet at the reference 160x144
  -- playfield, even at its deterministic maximum size variation.
  { cellX=64, cellY=52, bankW=88,  bankH=58, speed=7.5, camFactor=1.00, weight=0.60, uv=1.25 },
  { cellX=92, cellY=72, bankW=118, bankH=82, speed=4.6, camFactor=0.72, weight=0.50, uv=1.05 },
}

local function fract(x) return x - math.floor(x) end
local function fieldHash(ix, iy, salt)
  return fract(math.sin(ix * 12.9898 + iy * 78.233 + salt * 37.719) * 43758.5453)
end

-- Draw a wrapping world-space haze field. Unlike Fog.draw(), this never uses a
-- viewport-sized quad. Every draw is a local bank whose position is derived
-- from a stable world cell. The returned count is used only by tests/audits.
function Fog.drawWorldField(amount, alpha, layers, t, camX, camY, scale, w, h, speedCh, motionMul, intensityMul)
  if amount <= 0 or alpha <= 0 then return 0 end
  local m = buildMesh()
  if not m then return 0 end
  scale = math.max(0.25, tonumber(scale) or 1)
  camX, camY, t = tonumber(camX) or 0, tonumber(camY) or 0, tonumber(t) or 0
  motionMul = math.max(0, tonumber(motionMul) or 1)
  intensityMul = math.max(0, tonumber(intensityMul) or 1)
  -- `motionMul` scales TIME rather than only displacement so every autonomous
  -- component (linear wind plus vertical meander) actually changes speed.
  -- Player/camera parallax is deliberately independent and remains 1:1.
  local motionT = t * motionMul
  local drift = 0.55 + 0.90 * (tonumber(speedCh) or 0.5)
  local viewWorldW, viewWorldH = w / scale, h / scale
  local total = 0

  love.graphics.setBlendMode("alpha")
  for li = 1, math.min(layers or 2, #Fog.WORLD_LAYERS) do
    local L = Fog.WORLD_LAYERS[li]
    local cf = L.camFactor or 1
    -- Match culling to the same camera sign used by the final bank transform.
    -- Visible banks satisfy wx ~= camX*cf-drift (and likewise on Y) because
    -- sx=(wx-camX*cf+drift)*scale. Using the opposite sign here selects
    -- cells behind the camera and can cull the entire haze field far from
    -- map origin.
    local obsX, obsY = camX * cf, camY * cf
    local driftX = FOG_DIR * motionT * L.speed * drift
    local driftY = math.sin(motionT * (0.11 + li * 0.017) + li * 1.7) * (2.0 + li * 0.8)

    local ix0 = math.floor((obsX - driftX) / L.cellX) - 1
    local ix1 = math.floor((obsX + viewWorldW - driftX) / L.cellX) + 1
    local iy0 = math.floor((obsY - driftY) / L.cellY) - 1
    local iy1 = math.floor((obsY + viewWorldH - driftY) / L.cellY) + 1

    for iy = iy0, iy1 do
      for ix = ix0, ix1 do
        -- Stable offsets/shape from WORLD cell id; walking away and back gives
        -- the same bank rather than a newly generated screen-space puff.
        local jx = (fieldHash(ix, iy, li) - 0.5) * L.cellX * 0.42
        local jy = (fieldHash(ix, iy, li + 11) - 0.5) * L.cellY * 0.40
        local ws = 0.78 + fieldHash(ix, iy, li + 23) * 0.50
        local hs = 0.72 + fieldHash(ix, iy, li + 37) * 0.52
        local wx = ix * L.cellX + jx
        local wy = iy * L.cellY + jy
        local sx = (wx - camX * cf + driftX) * scale
        local sy = (wy - camY * cf + driftY) * scale
        local bw = L.bankW * ws * scale
        local bh = L.bankH * hs * scale

        -- Cull generously so banks cross the viewport edge instead of popping.
        if sx + bw > -bw * 0.35 and sx < w + bw * 0.35
            and sy + bh > -bh * 0.35 and sy < h + bh * 0.35 then
          local uv0x = fieldHash(ix, iy, li + 51)
          local uv0y = fieldHash(ix, iy, li + 67)
          local uvx = (L.uv or 1) * ws
          local uvy = (L.uv or 1) * hs
          local density = 0.68 + fieldHash(ix, iy, li + 79) * 0.42
          local a = alpha * amount * (L.weight or 0.4) * density * intensityMul
          if a > 1.0 then a = 1.0 end
          -- Noise already provides the irregular perimeter. Slightly lighter
          -- top corners prevent each local bank from reading as a rectangle.
          setQuad(m,sx,sy,sx+bw,sy+bh,uv0x,uv0y,uv0x+uvx,uv0y+uvy,a*.28,a*.34,a*.78,a*.72)
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(m)
          total = total + 1
        end
      end
    end
  end
  return total
end

return Fog

