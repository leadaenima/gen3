-- ============================================================================
-- WEATHER FX 3D LEAF COLLISION / PILE PHYSICS
-- ============================================================================
-- Leaves remain world-space particles owned by WorldPrecip. This helper only
-- resolves their contact with the rendered voxel world and posed NPC bodies.
--
-- Building/terrain collision uses the host's VoxelScene.groundAt(map,cx,cz)
-- surface-height authority. A leaf travelling into a cell whose solid surface
-- rises above the leaf is treated as hitting a wall/roof edge. It bounces/slides
-- down that face; if it reaches the ground shortly after wall contact it can
-- settle into a temporary pile at the obstacle base.
--
-- NPCs are dynamic cylinders built from the posed actor list already produced
-- by VoxelScene. Leaves NEVER settle on an NPC. Repeated contact is capped at
-- two seconds; after that the leaf is forcibly ejected into the wind so a
-- moving/animating character can never collect stuck leaves.
-- ============================================================================

local V = ...
local floor, ceil, sqrt, abs, max, min = math.floor, math.ceil, math.sqrt, math.abs, math.max, math.min
local TILE = 16

local LP = {}

LP.NPC_RADIUS = 6.4
LP.LEAF_RADIUS = 1.25
LP.NPC_HEIGHT = 17.5
LP.NPC_MAX_CONTACT = 2.0
LP.WALL_STEP = 1.5
LP.SWEEP_STEP = 0.5
LP.GROUND_EPS = 0.30
LP.GROUND_SWEEP_STEP = 0.5
LP.GROUND_CLEARANCE_MIN = 0.38
LP.GROUND_CLEARANCE_MAX = 0.90
LP.WALL_MEMORY = 1.65
LP.PILE_MIN = 35.0
LP.PILE_MAX = 90.0
LP.MAX_SETTLED_FRACTION = 0.28

local _VoxelScene
local function voxelScene()
  if _VoxelScene then return _VoxelScene end
  local ok, m = pcall(V.require, "VoxelScene")
  if ok and m then _VoxelScene = m end
  return _VoxelScene
end

local function mapDims(map)
  if not map then return 0, 0 end
  local w, h = tonumber(map.widthCells), tonumber(map.heightCells)
  if (not w or w <= 0) and map.def then
    local bw = tonumber(map.def.width)
    if bw and bw > 0 then w = bw * 2 end
  end
  if (not h or h <= 0) and map.def then
    local bh = tonumber(map.def.height)
    if bh and bh > 0 then h = bh * 2 end
  end
  return max(0, floor(w or 0)), max(0, floor(h or 0))
end

local FRAME_CTX = { regions={}, npcs={}, frameSerial=0, regionCount=0, npcCount=0 }

local function addRegion(ctx, map, ox, oz)
  local w, h = mapDims(map)
  if not (map and w > 0 and h > 0) then return end
  local n = (ctx.regionCount or 0) + 1
  ctx.regionCount = n
  local r = ctx.regions[n]
  if not r then
    r = { groundValue={}, groundStamp={} }
    ctx.regions[n] = r
  elseif r.map ~= map or r.w ~= w or r.h ~= h then
    -- Map changes are infrequent; reset the cache only then. Same-map frames use
    -- generation stamps and never clear/allocate the hot height cache.
    r.groundValue, r.groundStamp = {}, {}
  end
  r.map, r.ox, r.oz, r.w, r.h = map, tonumber(ox) or 0, tonumber(oz) or 0, w, h
end

local function obviousNonNpc(entity)
  if not entity then return true end
  local def = type(entity.def) == "table" and entity.def or {}
  if def.pushable == true then return true end
  local name = tostring(def.sprite or def.id or ""):upper()
  if name:find("BOULDER", 1, true) or name:find("POKE_BALL", 1, true)
      or name:find("POKEBALL", 1, true) or name:find("ITEM_BALL", 1, true) then
    return true
  end
  return false
end

local function putNpc(ctx, entity, x, z, y0, radius)
  local n = (ctx.npcCount or 0) + 1
  ctx.npcCount = n
  local d = ctx.npcs[n]
  if not d then d = {}; ctx.npcs[n] = d end
  d.entity, d.x, d.z = entity, x, z
  d.y0 = y0
  d.y1 = y0 + LP.NPC_HEIGHT
  d.r = radius or LP.NPC_RADIUS
  return d
end

function LP.beginFrame(meta, fallbackGroundY, hostVoxelScene)
  meta = type(meta) == "table" and meta or {}
  local ctx = FRAME_CTX
  local oldRegions, oldNpcs = ctx.regionCount or 0, ctx.npcCount or 0
  ctx.frameSerial = (ctx.frameSerial or 0) + 1
  ctx.regionCount, ctx.npcCount = 0, 0
  ctx.VS = hostVoxelScene or meta.voxelScene or meta.VoxelScene or voxelScene()
  ctx.fallbackGroundY = tonumber(fallbackGroundY) or 0
  ctx.player = meta.player

  addRegion(ctx, meta.map, 0, 0)
  for _, nb in ipairs(meta.neighbors or {}) do
    if nb and nb.map then addRegion(ctx, nb.map, nb.ox or 0, nb.oy or nb.oz or 0) end
  end
  for i = oldRegions, ctx.regionCount + 1, -1 do ctx.regions[i] = nil end
  ctx.collisionEnabled = ctx.VS ~= nil and type(ctx.VS.groundAt) == "function" and ctx.regionCount > 0

  local function actorGround(map, entity, fallback)
    if ctx.VS and type(ctx.VS.groundAt) == "function" and map and entity then
      local cx, cz = tonumber(entity.cellX), tonumber(entity.cellY)
      if cx and cz then
        local ok, h = pcall(ctx.VS.groundAt, map, cx, cz)
        if ok and type(h) == "number" and h == h then return h end
      end
    end
    return tonumber(fallback) or ctx.fallbackGroundY
  end

  local posed = meta.posed or {}
  if #posed > 0 then
    -- Reuse an exposed host posed list when one really exists.
    for _, p in ipairs(posed) do
      local entity = p and p.entity
      if p and entity and entity ~= meta.player and not obviousNonNpc(entity) then
        local px, pz = tonumber(p.px), tonumber(p.py)
        if px and pz then
          local y0 = (tonumber(p.gh) or actorGround(p.map or meta.map, entity, ctx.fallbackGroundY))
              + (tonumber(p.lift) or 0)
          putNpc(ctx, entity, px+8.0, pz+8.0, y0, LP.NPC_RADIUS)
        end
      end
    end
  else
    -- Voxel Realism 2.9.x computes `posed` as a LOCAL inside render(); it is
    -- not state.posed. Build collision cylinders from the authoritative
    -- overworld state instead so visible NPCs cannot disappear from physics.
    local state = meta.state
    if type(state) == "table" then
      local function addEntity(entity, map, ox, oz)
        if not entity or entity == (meta.player or state.player) or obviousNonNpc(entity) then return end
        local ex = tonumber(entity.px)
        local ez = tonumber(entity.py)
        if ex == nil and tonumber(entity.cellX) then ex = tonumber(entity.cellX) * TILE end
        if ez == nil and tonumber(entity.cellY) then ez = tonumber(entity.cellY) * TILE end
        if ex == nil or ez == nil then return end
        ex, ez = ex + (tonumber(ox) or 0), ez + (tonumber(oz) or 0)
        local y0 = actorGround(map or meta.map, entity, ctx.fallbackGroundY)
        putNpc(ctx, entity, ex+8.0, ez+8.0, y0, LP.NPC_RADIUS)
      end
      for _, entity in ipairs(state.entities or {}) do addEntity(entity, state.map or meta.map, 0, 0) end
      for _, g in ipairs(state.ghosts or {}) do
        if g and g.npc then addEntity(g.npc, g.map or state.map or meta.map, g.ox or 0, g.oy or 0) end
      end
    end
  end

  for i = oldNpcs, ctx.npcCount + 1, -1 do ctx.npcs[i] = nil end
  return ctx
end

local function regionCell(ctx, x, z)
  for ri = 1, (ctx.regionCount or #ctx.regions) do
    local r = ctx.regions[ri]
    local lx, lz = x - r.ox, z - r.oz
    if lx >= 0 and lz >= 0 and lx < r.w * TILE and lz < r.h * TILE then
      local cx, cz = floor(lx / TILE), floor(lz / TILE)
      return r, cx, cz, ri
    end
  end
  return nil
end

function LP.groundAt(ctx, x, z)
  if not ctx or not ctx.collisionEnabled then return ctx and ctx.fallbackGroundY or 0 end
  local r, cx, cz, ri = regionCell(ctx, x, z)
  if not r then return ctx.fallbackGroundY end
  local key = cx * (r.h + 1) + cz + 1
  if r.groundStamp[key] == ctx.frameSerial then return r.groundValue[key] end
  local y = ctx.fallbackGroundY
  local ok, h = pcall(ctx.VS.groundAt, r.map, cx, cz)
  if ok and type(h) == "number" and h == h then y = h end
  r.groundValue[key] = y
  r.groundStamp[key] = ctx.frameSerial
  return y
end

-- A leaf is not a mathematical point. Sample its footprint as well as its
-- center so thin building edges/corners cannot slip between a center-line sweep
-- and the voxel cell boundary. Nine samples are cheap because groundAt is
-- cached per cell for the frame.
function LP.surfaceEnvelope(ctx, x, z, radius)
  radius = max(0, tonumber(radius) or LP.LEAF_RADIUS)
  local d = radius * 0.70710678
  local best = LP.groundAt(ctx, x, z)
  local h
  h=LP.groundAt(ctx,x+radius,z); if h>best then best=h end
  h=LP.groundAt(ctx,x-radius,z); if h>best then best=h end
  h=LP.groundAt(ctx,x,z+radius); if h>best then best=h end
  h=LP.groundAt(ctx,x,z-radius); if h>best then best=h end
  h=LP.groundAt(ctx,x+d,z+d); if h>best then best=h end
  h=LP.groundAt(ctx,x-d,z+d); if h>best then best=h end
  h=LP.groundAt(ctx,x+d,z-d); if h>best then best=h end
  h=LP.groundAt(ctx,x-d,z-d); if h>best then best=h end
  return best
end

function LP.isPenetrating(ctx, x, y, z)
  if not ctx or not ctx.collisionEnabled then return false, nil end
  local center=LP.groundAt(ctx,x,z)
  local envelope=LP.surfaceEnvelope(ctx,x,z,LP.LEAF_RADIUS)
  -- Center below a cell's top surface means the leaf is inside the solid
  -- column. If the center is outside but the footprint overlaps a much taller
  -- neighbour, it is embedded in that wall edge/corner as well.
  local insideCenter=(tonumber(y) or 0) < center - 0.05
  local insideEdge=envelope > center + LP.WALL_STEP
      and (tonumber(y) or 0) < envelope + LP.LEAF_RADIUS
  return insideCenter or insideEdge, envelope
end

local function nearbyNpc(ctx, x, y, z)
  if not ctx then return nil end
  local count = ctx.npcCount or #ctx.npcs
  for j = 1, count do
    local n = ctx.npcs[j]
    if n and y >= n.y0 - 0.8 and y <= n.y1 + 1.0 then
      local ox, oz = x - n.x, z - n.z
      local rr = n.r + LP.LEAF_RADIUS
      if ox * ox + oz * oz <= rr * rr then return n, ox, oz, 1 end
    end
  end
  return nil
end

-- Continuous segment-vs-cylinder test. The old end-point-only check could miss
-- an actor completely on a long/stalled frame: old position on one side,
-- integrated position on the other, neither endpoint inside the NPC radius.
local function sweptNpc(ctx, x0, y0, z0, x1, y1, z1)
  if not ctx then return nil end
  local dx, dy, dz = x1-x0, y1-y0, z1-z0
  local denom = dx*dx + dz*dz
  local bestN, bestOx, bestOz, bestT
  for j=1,(ctx.npcCount or #(ctx.npcs or {})) do
    local n=ctx.npcs[j]
    local t=0
    if denom > 1e-9 then
      t=((n.x-x0)*dx + (n.z-z0)*dz)/denom
      if t<0 then t=0 elseif t>1 then t=1 end
    end
    local sx, sy, sz=x0+dx*t, y0+dy*t, z0+dz*t
    if sy >= n.y0-0.8 and sy <= n.y1+1.0 then
      local ox, oz=sx-n.x, sz-n.z
      local rr=n.r+LP.LEAF_RADIUS
      if ox*ox+oz*oz <= rr*rr and (bestT==nil or t<bestT) then
        bestN,bestOx,bestOz,bestT=n,ox,oz,t
      end
    end
  end
  if bestN then return bestN,bestOx,bestOz,bestT end
  return nearbyNpc(ctx,x1,y1,z1)
end

local function ejectNpc(pool, i, n, ox, oz, windX, windZ)
  local len = sqrt(ox * ox + oz * oz)
  local nx, nz
  if len > 1e-4 then
    nx, nz = ox / len, oz / len
  else
    local wl = sqrt((windX or 0)^2 + (windZ or 0)^2)
    if wl > 1e-4 then nx, nz = -(windX or 0) / wl, -(windZ or 0) / wl else nx, nz = 1, 0 end
  end
  local outR = n.r + 2.0
  pool.x[i], pool.z[i] = n.x + nx * outR, n.z + nz * outR
  pool.y[i] = max(pool.y[i] or n.y0, n.y0 + 3.0)
  pool.vx[i] = nx * 18 + (windX or 0) * 7
  pool.vz[i] = nz * 18 + (windZ or 0) * 7
  pool.vy[i] = max(3.5, tonumber(pool.vy[i]) or 0)
  pool.leafNpcT[i] = 0
  pool.leafSettled[i] = false
end

-- Exact 16-world-unit supercover grid traversal. This is the PRIMARY wall
-- collision path. It visits every voxel cell entered between the previous and
-- proposed X/Z positions, including both side-adjacent cells when a diagonal
-- crosses a grid corner. That makes it impossible for a fast leaf to skip a
-- one-cell building merely because no arbitrary line-sample landed inside it.
--
-- `visit(cx,cz,t,fromCx,fromCz)` may return a truthy value to stop traversal.
local function ddaCells(x0, z0, x1, z1, visit)
  local dx, dz = x1-x0, z1-z0
  local cx, cz = floor(x0 / TILE), floor(z0 / TILE)
  local ex, ez = floor(x1 / TILE), floor(z1 / TILE)
  if visit then
    local r=visit(cx,cz,0,cx,cz)
    if r then return r end
  end
  if cx==ex and cz==ez then return nil end

  local stepX = dx > 0 and 1 or (dx < 0 and -1 or 0)
  local stepZ = dz > 0 and 1 or (dz < 0 and -1 or 0)
  local inf = math.huge
  local tDeltaX = stepX ~= 0 and (TILE / abs(dx)) or inf
  local tDeltaZ = stepZ ~= 0 and (TILE / abs(dz)) or inf
  local nextX = stepX > 0 and ((cx+1)*TILE) or (cx*TILE)
  local nextZ = stepZ > 0 and ((cz+1)*TILE) or (cz*TILE)
  local tMaxX = stepX ~= 0 and ((nextX-x0)/dx) or inf
  local tMaxZ = stepZ ~= 0 and ((nextZ-z0)/dz) or inf
  if tMaxX < 0 then tMaxX=0 end
  if tMaxZ < 0 then tMaxZ=0 end

  local guard=0
  while (cx~=ex or cz~=ez) and guard < 4096 do
    guard=guard+1
    local fromCx,fromCz=cx,cz
    if abs(tMaxX-tMaxZ) <= 1e-10 then
      local t=min(1,tMaxX)
      -- Supercover the two cells touched at the corner before entering the
      -- diagonal cell. A finite-size leaf can collide with either one.
      if stepX~=0 and visit then
        local r=visit(cx+stepX,cz,t,fromCx,fromCz)
        if r then return r end
      end
      if stepZ~=0 and visit then
        local r=visit(cx,cz+stepZ,t,fromCx,fromCz)
        if r then return r end
      end
      if stepX~=0 then cx=cx+stepX; tMaxX=tMaxX+tDeltaX end
      if stepZ~=0 then cz=cz+stepZ; tMaxZ=tMaxZ+tDeltaZ end
      if visit then
        local r=visit(cx,cz,t,fromCx,fromCz)
        if r then return r end
      end
    elseif tMaxX < tMaxZ then
      local t=min(1,tMaxX)
      cx=cx+stepX; tMaxX=tMaxX+tDeltaX
      if visit then
        local r=visit(cx,cz,t,fromCx,fromCz)
        if r then return r end
      end
    else
      local t=min(1,tMaxZ)
      cz=cz+stepZ; tMaxZ=tMaxZ+tDeltaZ
      if visit then
        local r=visit(cx,cz,t,fromCx,fromCz)
        if r then return r end
      end
    end
  end
  return nil
end
LP.ddaCells = ddaCells

local function cellHeight(ctx,cx,cz)
  return LP.groundAt(ctx,cx*TILE + TILE*0.5,cz*TILE + TILE*0.5)
end

local function ddaWall(ctx,x0,y0,z0,x1,y1,z1)
  if not ctx or not ctx.collisionEnabled then return nil end
  local dx,dy,dz=x1-x0,y1-y0,z1-z0
  local startCx,startCz=floor(x0/TILE),floor(z0/TILE)
  local freeCx,freeCz=startCx,startCz
  local freeH=cellHeight(ctx,freeCx,freeCz)
  local lastT=0
  local epsWorld=0.04
  local planar=max(abs(dx),abs(dz),1e-6)
  local epsT=min(0.01,epsWorld/planar)

  return ddaCells(x0,z0,x1,z1,function(cx,cz,t,fromCx,fromCz)
    -- Initial cell establishes authority but cannot be a crossed-cell wall.
    if t<=0 then return nil end
    local h=cellHeight(ctx,cx,cz)
    local refH=cellHeight(ctx,fromCx,fromCz)
    local sy=y0+dy*t
    if h > refH + LP.WALL_STEP and sy <= h + LP.LEAF_RADIUS then
      local safeT=max(lastT,min(1,t-epsT))
      return {
        x=x0+dx*safeT,y=y0+dy*safeT,z=z0+dz*safeT,
        h=h,prevH=refH,t=t,dx=dx,dz=dz,dda=true,
        cellX=cx,cellZ=cz,
      }
    end
    freeCx,freeCz,freeH=cx,cz,h
    lastT=max(lastT,t)
    return nil
  end)
end
LP.ddaWall = ddaWall

-- Secondary fine sweep. The DDA above is exact for crossed voxel cells; this
-- 0.5-unit footprint sweep remains deliberately redundant for unusual host
-- geometry, thin non-grid features and the physical radius of the rendered
-- leaf card. Do not increase SWEEP_STEP above 0.5.
local function sweptWall(ctx, x0, y0, z0, x1, y1, z1)
  if not ctx or not ctx.collisionEnabled then return nil end
  local dx,dy,dz=x1-x0,y1-y0,z1-z0
  local span=max(abs(dx),abs(dy),abs(dz))
  local steps=max(1,ceil(span/LP.SWEEP_STEP))
  local centerBase=LP.groundAt(ctx,x0,z0)
  local baseH=LP.surfaceEnvelope(ctx,x0,z0,LP.LEAF_RADIUS)
  local lastX,lastY,lastZ,lastH=x0,y0,z0,baseH

  -- If the leaf footprint is already intersecting a raised neighbouring cell,
  -- treat the first movement as penetration recovery rather than allowing it to
  -- start from inside the wall and escape through the far face.
  if baseH > centerBase + LP.WALL_STEP and y0 <= baseH + LP.LEAF_RADIUS then
    return {x=x0,y=y0,z=z0,h=baseH,prevH=centerBase,t=0,dx=dx,dz=dz,penetrating=true}
  end

  local gridHit=ddaWall(ctx,x0,y0,z0,x1,y1,z1)
  if gridHit then return gridHit end

  for k=1,steps do
    local t=k/steps
    local sx,sy,sz=x0+dx*t,y0+dy*t,z0+dz*t
    local h=LP.surfaceEnvelope(ctx,sx,sz,LP.LEAF_RADIUS)
    -- A rising collision surface above the previous free surface is a wall /
    -- building edge. Footprint sampling means corners and one-cell slivers are
    -- included even when the particle center does not enter that cell.
    if h > lastH + LP.WALL_STEP and sy <= h + LP.LEAF_RADIUS then
      return {x=lastX,y=lastY,z=lastZ,h=h,prevH=lastH,t=t,dx=dx,dz=dz}
    end
    lastX,lastY,lastZ,lastH=sx,sy,sz,h
  end

  -- Redundant post-sweep penetration guard. This catches a discontinuity that
  -- is already under the leaf footprint at the final sample due to map seams or
  -- unusual host height functions.
  local finalCenter=LP.groundAt(ctx,x1,z1)
  local finalEnvelope=LP.surfaceEnvelope(ctx,x1,z1,LP.LEAF_RADIUS)
  if finalEnvelope > finalCenter + LP.WALL_STEP and y1 <= finalEnvelope + LP.LEAF_RADIUS then
    local t=max(0,(steps-1)/steps)
    return {x=x0+dx*t,y=y0+dy*t,z=z0+dz*t,h=finalEnvelope,prevH=finalCenter,t=1,dx=dx,dz=dz,post=true}
  end
  return nil
end

LP.sweptWall = sweptWall
LP.sweptNpc = sweptNpc

-- A leaf card has real visual extent. Keeping only its center 0.30 units above
-- the terrain can still render half of the tumbling card below the voxel floor.
-- Physics uses the authored world-size (never camera distance) to choose a
-- small bounded clearance that keeps the visible leaf on top of the surface.
local function groundClearance(pool, i)
  local size = tonumber(pool and pool.size and pool.size[i]) or 0.30
  return max(LP.GROUND_CLEARANCE_MIN,
    min(LP.GROUND_CLEARANCE_MAX, size * 1.45 + LP.GROUND_EPS))
end
LP.groundClearance = groundClearance

-- Continuous leaf-vs-ground sweep. Same-cell motion is solved analytically --
-- the host's groundAt authority is cell-constant there -- so the common case
-- is only two cached height reads and one interpolation. Only a segment that
-- crosses cells uses the <=0.5-world-unit fallback sweep. This prevents a fast
-- descending leaf from ending below the floor and being recycled on the next
-- frame instead of visibly bouncing/tumbling across the terrain.
local function sweptGround(ctx, x0, y0, z0, x1, y1, z1, clearance)
  if not ctx or not ctx.collisionEnabled then return nil end
  clearance = max(LP.GROUND_EPS, tonumber(clearance) or LP.GROUND_CLEARANCE_MIN)
  local r0,cx0,cz0 = regionCell(ctx,x0,z0)
  local r1,cx1,cz1 = regionCell(ctx,x1,z1)
  local h0 = LP.groundAt(ctx,x0,z0)
  local h1 = LP.groundAt(ctx,x1,z1)
  local t0 = h0 + clearance
  local t1 = h1 + clearance

  -- Legacy/spawn penetration recovery: do not respawn or let the leaf continue
  -- underground; lift it onto the current support and return ordinary contact.
  if y0 <= t0 then
    return {x=x0,y=t0,z=z0,h=h0,t=0,penetrating=true}
  end

  if r0 and r0==r1 and cx0==cx1 and cz0==cz1 then
    if y1 <= t1 then
      local dy=y1-y0
      local t=1
      if abs(dy)>1e-9 then t=max(0,min(1,(t1-y0)/dy)) end
      return {x=x0+(x1-x0)*t,y=t1,z=z0+(z1-z0)*t,h=h1,t=t,sameCell=true}
    end
    return nil
  end

  local dx,dy,dz=x1-x0,y1-y0,z1-z0
  local span=max(abs(dx),abs(dy),abs(dz))
  local steps=max(1,ceil(span/LP.GROUND_SWEEP_STEP))
  local prevT=0
  for k=1,steps do
    local t=k/steps
    local sx,sy,sz=x0+dx*t,y0+dy*t,z0+dz*t
    local h=LP.groundAt(ctx,sx,sz)
    local target=h+clearance
    if sy <= target then
      -- Refine the crossing inside the last half-unit interval. Host height is
      -- piecewise constant, so a few bounded bisections are enough even at a
      -- cell seam and allocate nothing.
      local lo,hi=prevT,t
      for _=1,4 do
        local mid=(lo+hi)*0.5
        local mx,my,mz=x0+dx*mid,y0+dy*mid,z0+dz*mid
        local mh=LP.groundAt(ctx,mx,mz)
        if my <= mh+clearance then hi=mid else lo=mid end
      end
      local hitT=hi
      local hx,hz=x0+dx*hitT,z0+dz*hitT
      local hh=LP.groundAt(ctx,hx,hz)
      return {x=hx,y=hh+clearance,z=hz,h=hh,t=hitT,swept=true}
    end
    prevT=t
  end
  return nil
end
LP.sweptGround = sweptGround

local _Surface=nil
local function depositLeaf(x,z,amount)
  if _Surface==false then return end
  if _Surface==nil then local ok,m=pcall(V.require,"EnvironmentSurface"); _Surface=(ok and m) or false end
  if _Surface and _Surface.depositLeaves then pcall(_Surface.depositLeaves,x,z,amount or .025) end
end

-- Resolve one already-integrated leaf. Returns:
--   "flying"  keep simulating
--   "settled" temporary pile leaf
--   "npc"     bounced/ejected from an NPC
function LP.resolve(pool, i, dt, oldX, oldY, oldZ, ctx, windX, windZ, allowSettle)
  if not pool or not i then return "flying" end
  dt = max(0, min(0.1, tonumber(dt) or 0))

  -- Existing pile leaves remain on the obstacle base for a bounded lifetime.
  if pool.leafSettled[i] then
    pool.leafSettleT[i] = (pool.leafSettleT[i] or 0) + dt
    pool.vx[i], pool.vy[i], pool.vz[i] = 0, 0, 0
    local life = pool.leafSettleLife[i] or 10
    if pool.leafSettleT[i] >= life then return "expired-settle" end
    return "settled"
  end

  local x, y, z = pool.x[i], pool.y[i], pool.z[i]

  -- Dynamic NPC collision. Never settle on a character. Use the complete
  -- movement segment so leaves cannot tunnel through a body between frames.
  local n, ox, oz, hitT = sweptNpc(ctx, oldX, oldY, oldZ, x, y, z)
  if n then
    local t = (pool.leafNpcT[i] or 0) + dt
    pool.leafNpcT[i] = t
    if t >= LP.NPC_MAX_CONTACT then
      ejectNpc(pool, i, n, ox, oz, windX, windZ)
      return "npc-eject"
    end
    if hitT and hitT < 1 then
      local hx = oldX + (x-oldX)*hitT
      local hy = oldY + (y-oldY)*hitT
      local hz = oldZ + (z-oldZ)*hitT
      pool.x[i],pool.y[i],pool.z[i]=hx,hy,hz
    end
    local len = sqrt(ox * ox + oz * oz)
    local nx, nz = 1, 0
    if len > 1e-4 then nx, nz = ox / len, oz / len end
    pool.x[i] = n.x + nx * (n.r + 0.35)
    pool.z[i] = n.z + nz * (n.r + 0.35)
    local dot = (pool.vx[i] or 0) * nx + (pool.vz[i] or 0) * nz
    if dot < 0 then
      pool.vx[i] = (pool.vx[i] or 0) - 1.45 * dot * nx
      pool.vz[i] = (pool.vz[i] or 0) - 1.45 * dot * nz
    end
    pool.vx[i] = (pool.vx[i] or 0) * 0.72 + (windX or 0) * 2.5
    pool.vz[i] = (pool.vz[i] or 0) * 0.72 + (windZ or 0) * 2.5
    pool.vy[i] = max(1.2, tonumber(pool.vy[i]) or 0)
    return "npc"
  else
    pool.leafNpcT[i] = 0
  end

  if not ctx or not ctx.collisionEnabled then return "flying" end

  local oldH = LP.groundAt(ctx, oldX, oldZ)
  local newH = LP.groundAt(ctx, x, z)
  local contactClearance=groundClearance(pool,i)

  -- Base-of-wall settling gets first priority once a previous wall hit has
  -- already established obstacle contact. With footprint collision the edge of
  -- a correctly resting leaf may still overlap the wall cell; treating that as
  -- another wall hit forever would prevent piles from ever forming.
  if y <= newH + contactClearance and allowSettle and (pool.leafWallT[i] or 0) > 0 then
    pool.y[i] = newH + contactClearance
    pool.leafSettled[i] = true
    pool.leafSettleT[i] = 0
    local seed = tonumber(pool.seed[i]) or 0.5
    pool.leafSettleLife[i] = LP.PILE_MIN + seed * (LP.PILE_MAX - LP.PILE_MIN)
    pool.vx[i], pool.vy[i], pool.vz[i] = 0, 0, 0
    depositLeaf(pool.x[i],pool.z[i],.030)
    return "settled"
  end

  local wallHit = sweptWall(ctx, oldX, oldY, oldZ, x, y, z)

  if wallHit then
    -- Stay on the air side of the first crossed solid voxel column. Reflect the
    -- dominant horizontal component only weakly so leaves slide/tumble down a
    -- wall rather than ping-pong like rubber balls.
    pool.x[i], pool.y[i], pool.z[i] = wallHit.x, max(wallHit.y,(wallHit.prevH or oldH)+contactClearance), wallHit.z
    local dx, dz = wallHit.dx, wallHit.dz
    if abs(dx) >= abs(dz) then
      pool.vx[i] = -(pool.vx[i] or 0) * 0.16
      -- Wind keeps pushing tangentially along the wall rather than being lost.
      pool.vz[i] = (pool.vz[i] or 0) * 0.58 + (windZ or 0) * 2.2
    else
      pool.vz[i] = -(pool.vz[i] or 0) * 0.16
      pool.vx[i] = (pool.vx[i] or 0) * 0.58 + (windX or 0) * 2.2
    end
    -- Small tumble/bounce, then WorldPrecip gravity pulls it toward the base.
    local ivy=tonumber(pool.vy[i]) or 0
    pool.vy[i] = max(-2.0,min(1.2,ivy*0.35 + 0.7))
    pool.leafWallT[i] = LP.WALL_MEMORY
    return "wall"
  end

  pool.leafWallT[i] = max(0, (pool.leafWallT[i] or 0) - dt)

  -- Continuous ground/roof contact. Do not wait until the next frame to notice
  -- that a leaf's endpoint is underground. Resolve at the first swept contact,
  -- keep the complete rendered card above the support, then retain horizontal
  -- momentum + WindEngine drive so the leaf visibly tumbles across the floor.
  local clearance=contactClearance
  local groundHit=sweptGround(ctx,oldX,oldY,oldZ,x,y,z,clearance)
  if groundHit then
    pool.x[i],pool.y[i],pool.z[i]=groundHit.x,groundHit.y,groundHit.z
    newH=groundHit.h or newH
    if allowSettle and (pool.leafWallT[i] or 0) > 0 then
      pool.leafSettled[i] = true
      pool.leafSettleT[i] = 0
      local seed = tonumber(pool.seed[i]) or 0.5
      pool.leafSettleLife[i] = LP.PILE_MIN + seed * (LP.PILE_MAX - LP.PILE_MIN)
      pool.vx[i], pool.vy[i], pool.vz[i] = 0, 0, 0
      depositLeaf(pool.x[i],pool.z[i],.030)
      return "settled"
    end
    -- Ground tumble/skip: lose vertical/horizontal energy but preserve enough
    -- tangent motion for the WindEngine to roll the leaf along the surface.
    local seed=tonumber(pool.seed[i]) or 0.5
    pool.vx[i] = (pool.vx[i] or 0) * 0.68 + (windX or 0) * 3.8
    pool.vz[i] = (pool.vz[i] or 0) * 0.68 + (windZ or 0) * 3.8
    local incoming=tonumber(pool.vy[i]) or 0
    local rebound=max(1.15,min(3.0,abs(min(0,incoming))*0.22 + 1.0 + seed*1.25))
    pool.vy[i]=rebound
    return "ground-skip"
  end

  return "flying"
end

function LP.debug(ctx)
  local regions = ctx and (ctx.regionCount or #(ctx.regions or {})) or 0
  local npcs = ctx and (ctx.npcCount or #(ctx.npcs or {})) or 0
  return string.format("leaf-physics regions=%d npcs=%d collision=%s",
    regions, npcs, tostring(ctx and ctx.collisionEnabled == true))
end

return LP
