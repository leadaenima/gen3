-- ==========================================================================
-- NPC LIGHTNING REACTION
-- ==========================================================================
-- 3D-only, cosmetic and fail-open.
--
-- Every world-space lightning bolt gets the configured independent chance to choose a non-player character
-- that is actually inside the current voxel camera view. The bolt endpoint is
-- redirected to that character's head; no entity/gameplay data is modified.
-- At impact the live sprite rapidly flashes bright/black with a procedural internal
-- cartoon skeleton, then remains a black silhouette for the configured duration
-- with face-relative white eye glints and head-level smoke puffs. When the timer expires the
-- overlay simply stops drawing, so the host's untouched original appearance is
-- automatically restored.
-- ==========================================================================

local V = ...
V.safeCall = V.safeCall or pcall
local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min
local random = math.random

local N = {
  CHANCE = 0.10,
  DURATION = 3.0,
  NEAR_RADIUS = 192.0,
  _state = nil,
  -- Current Battle Art keeps its authoritative per-frame `posed` actor list
  -- local to VoxelScene.render(). 8.1.93 receives that exact list through the
  -- public CharacterRenderers.afterActors bridge instead of guessing a second
  -- pose from raw entity coordinates. The table is host-owned/reused; Weather
  -- FX only holds the current reference for targeting and reaction placement.
  _hostPosed = nil,
  _hostActorState = nil,
  _hostVoxel3D = nil,
  _hostActorFrames = 0,
  _effects = setmetatable({}, { __mode = "k" }),
  _hits = 0,
  _last = nil,
  _rolls = 0,
  _eligibleRolls = 0,
  _noCandidateRolls = 0,
  _rawFallbacks = 0,
}

local eyeMesh, eyeShader, eyeCap = nil, nil, 0
local smokeMesh, smokeCap = nil, 0
local skeletonMesh, skeletonCap = nil, 0
local eyeVerts, smokeVerts, skeletonVerts = {}, {}, {}
local FLASH_SECONDS, FLASH_STEP = 0.72, 0.060
local SMOKE_DELAY = 0.18
local EYE_FMT = {
  { "VertexPosition", "float", 3 },
  { "EyeTint", "float", 4 },
}

local function clamp01(x)
  x = tonumber(x) or 0
  if x < 0 then return 0 elseif x > 1 then return 1 end
  return x
end


local function settings()
  local enabled, chance, duration, nearRadius = true, N.CHANCE, N.DURATION, N.NEAR_RADIUS
  local ok, C = V.safeCall(V.require, "Config")
  if ok and C and type(C.get) == "function" then
    local okGet, cfg = V.safeCall(C.get)
    local n = okGet and type(cfg)=="table" and cfg.npcLightning or nil
    if type(n)=="table" then
      if n.enabled ~= nil then enabled = n.enabled and true or false end
      if tonumber(n.chance) then chance = clamp01(n.chance) end
      if tonumber(n.duration) then duration = max(0.1, tonumber(n.duration)) end
      if tonumber(n.nearRadius) then nearRadius = max(16, min(512, tonumber(n.nearRadius))) end
    end
  end
  return enabled, chance, duration, nearRadius
end

local function safePose(entity)
  if not entity or type(entity.pose) ~= "function" then return nil end
  local ok, sprite, vx, vy, facing, phase, flip = V.safeCall(entity.pose, entity)
  if not ok or not sprite or not sprite.def then return nil end
  return sprite, tonumber(vx), tonumber(vy), facing, phase, flip
end

local function obviousNonNpc(entity)
  if not entity then return true end
  local def = type(entity.def) == "table" and entity.def or {}
  if def.pushable == true then return true end
  local s = tostring(def.sprite or def.id or ""):upper()
  if s:find("BOULDER", 1, true) or s:find("POKE_BALL", 1, true)
      or s:find("POKEBALL", 1, true) or s:find("ITEM_BALL", 1, true) then
    return true
  end
  return false
end

local function voxelScene()
  local ok, m = V.safeCall(V.require, "VoxelScene")
  return ok and m or nil
end

local _RenderDistance = nil
local function renderDistance()
  -- Optional host helper. Some supported voxel hosts (including
  -- Gen2Recomped-DramaticShapes) do not ship RenderDistance.lua. Probe it
  -- quietly with pcall so absence stays a normal compatibility fallback
  -- instead of being reported as a Weather FX protected-call failure.
  if _RenderDistance ~= nil then return _RenderDistance or nil end
  local ok, m = pcall(V.require, "RenderDistance")
  _RenderDistance = (ok and m) or false
  return _RenderDistance or nil
end

local function groundAt(map, entity)
  local VS = voxelScene()
  if VS and type(VS.groundAt) == "function" and map and entity then
    local ok, y = V.safeCall(VS.groundAt, map, entity.cellX, entity.cellY)
    if ok and type(y) == "number" and y == y then return y end
  end
  return 0
end

local function dims(Voxel3D)
  -- Current Voxel Realism exposes size() and canvas() as functions. Older
  -- compatible hosts exposed canvas as a Canvas field. Prefer the explicit
  -- size seam, then support both canvas shapes; never index a function as if
  -- it were a Canvas (real Gen1Recomp 0.2.53 live-host regression).
  if Voxel3D and type(Voxel3D.size) == "function" then
    local ok, w, h = V.safeCall(Voxel3D.size)
    if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then return w, h end
  end
  if Voxel3D and Voxel3D.canvas then
    local ok, w, h = V.safeCall(function()
      local c = Voxel3D.canvas
      if type(c) == "function" then c = c() end
      if not c or type(c.getWidth) ~= "function" or type(c.getHeight) ~= "function" then return nil end
      return c:getWidth(), c:getHeight()
    end)
    if ok and tonumber(w) and tonumber(h) then return w, h end
  end
  local ok, w, h = V.safeCall(function() return love.graphics.getDimensions() end)
  if ok and tonumber(w) and tonumber(h) then return w, h end
  return 320, 288
end

-- Host Voxel3D.project is preferred because it knows world curvature. Older
-- compatible hosts may not expose it, so mirror their VP multiply as fallback.
local function project(Voxel3D, x, y, z)
  if Voxel3D and type(Voxel3D.project) == "function" then
    local ok, sx, sy, sc = V.safeCall(Voxel3D.project, x, y, z)
    if ok and sx and sy then return sx, sy, sc end
  end
  local m = Voxel3D and Voxel3D.vp
  if not m then return nil end
  local cx = m[1]*x + m[2]*y + m[3]*z + m[4]
  local cy = m[5]*x + m[6]*y + m[7]*z + m[8]
  local cw = m[13]*x + m[14]*y + m[15]*z + m[16]
  if not cw or cw <= 1e-6 then return nil end
  local w, h = dims(Voxel3D)
  return (cx/cw*0.5+0.5)*w, (cy/cw*0.5+0.5)*h, 1/cw
end

-- Build a strike descriptor from authoritative overworld coordinates first.
-- Voxel Realism 2.9.x intentionally keeps its per-frame `posed` list local to
-- VoxelScene.render(), while `state.entities` always carries px/py/cellX/cellY.
-- Requiring a SECOND entity:pose() call just to decide whether an NPC exists in
-- the world made live targeting fragile and could advance animation state.
--
-- Lightning targeting only needs a world body centre, so this path deliberately
-- DOES NOT call pose(). Pose data is requested later only if the optional
-- charred-silhouette reaction needs to redraw the struck actor.
local function descriptor(entity, map, ox, oz)
  if obviousNonNpc(entity) then return nil end
  local def = type(entity and entity.def) == "table" and entity.def or {}
  local rawX = tonumber(entity and (entity.px or entity.x))
  local rawZ = tonumber(entity and (entity.py or entity.y))
  local cellX = tonumber(entity and entity.cellX)
  local cellY = tonumber(entity and entity.cellY)
  if rawX == nil and cellX ~= nil then rawX = cellX * 16 end
  if rawZ == nil and cellY ~= nil then rawZ = cellY * 16 end

  -- Match the live leaf/NPC collision seam: overworld state.entities is the
  -- actor authority. Do not require def.sprite here because some NPC types only
  -- resolve their sprite through pose(), which is exactly the second call this
  -- targeting path must avoid. Known object entities were already rejected by
  -- obviousNonNpc(); valid world coordinates are enough for strike admission.
  if rawX == nil or rawZ == nil then return nil end
  N._rawFallbacks = N._rawFallbacks + 1
  return {
    entity=entity, map=map, ox=ox or 0, oz=oz or 0,
    sprite=nil, px=rawX+(ox or 0), pz=rawZ+(oz or 0),
    gh=groundAt(map, entity), lift=0,
    facing=entity.facing or "down", phase=0, flip=false, rawFallback=true,
  }
end

-- Optional redraw descriptor. This is intentionally separate from target
-- admission: if pose() is unavailable the lightning still physically strikes
-- the NPC, while only the five-second cartoon reaction is skipped.
local function visualDescriptor(entity, map, ox, oz)
  local d = descriptor(entity, map, ox, oz)
  if not d then return nil end
  local sprite, vx, vy, facing, phase, flip = safePose(entity)
  if not sprite then return d end
  local rawZ = tonumber(entity and (entity.py or entity.y))
  d.sprite = sprite
  if tonumber(vx) ~= nil then d.px = tonumber(vx) + (ox or 0) end
  if rawZ ~= nil and tonumber(vy) ~= nil then d.lift = rawZ - tonumber(vy) end
  d.facing, d.phase, d.flip = facing or d.facing, phase or 0, flip or false
  d.rawFallback = false
  return d
end

-- Current voxel hosts already resolve every actor pose once per frame before
-- drawing. Reuse that authoritative posed record whenever it is available.
-- Calling entity:pose() a second time here can advance hop/surf/spinner timers
-- and make the charred overlay disagree with the NPC the player just saw.
local function posedDescriptor(p, fallbackMap)
  if type(p) ~= "table" or obviousNonNpc(p.entity) or not p.sprite then return nil end
  local px, pz = tonumber(p.px), tonumber(p.py)
  if not px or not pz then return nil end
  return {
    entity=p.entity, map=p.map or fallbackMap, ox=0, oz=0,
    sprite=p.sprite, px=px, pz=pz, gh=tonumber(p.gh) or 0,
    lift=tonumber(p.lift) or 0, facing=p.facing, phase=p.phase, flip=p.flip,
  }
end

local function rendered(Voxel3D,d,player)
  local x,z=d.px+8,d.pz+8
  local RD=renderDistance()
  if RD and type(RD.point)=="function" and player then
    local ok,on=V.safeCall(RD.point,x,z,player); if ok and on==false then return false end
  end
  return true
end

local function screenVisible(Voxel3D,d)
  local x,z=d.px+8,d.pz+8
  local sx,sy=project(Voxel3D,x,d.gh+d.lift+12,z)
  if not sx then return false end
  local w,h=dims(Voxel3D)
  return sx>=3 and sx<=w-3 and sy>=3 and sy<=h-3
end

local function playerXZ(player)
  if not player then return nil,nil end
  local x=tonumber(player.px or player.x); local z=tonumber(player.py or player.y)
  if x==nil and tonumber(player.cellX) then x=tonumber(player.cellX)*16 end
  if z==nil and tonumber(player.cellY) then z=tonumber(player.cellY)*16 end
  return x,z
end

local _SpatialIndex=nil
local _npcIndex=nil
local function spatialIndexModule()
  if _SpatialIndex~=nil then return _SpatialIndex or nil end
  local ok,m=V.safeCall(V.require,"SpatialIndex"); _SpatialIndex=(ok and m) or false; return _SpatialIndex or nil
end

local function candidates(Voxel3D,used)
  local state=N._state; if type(state)~="table" then return {} end
  -- Prefer the exact actor records Battle Art already resolved and rendered.
  -- `state.posed` is retained for older/custom voxel hosts that publish the
  -- list directly. The current Battle Art fork deliberately keeps it local and
  -- exposes it through CharacterRenderers.afterActors instead.
  local posed = nil
  local hostPosedActive = N._hostActorState == state and type(N._hostPosed) == "table"
  if hostPosedActive then
    posed = N._hostPosed
  elseif type(state.posed) == "table" then
    posed = state.posed
  end
  local player=state.player; local seen={}; local all={}; local onScreen={}
  local function accept(d)
    local entity=d and d.entity
    if not entity or entity==player or seen[entity] or (used and used[entity]) then return end
    seen[entity]=true
    if not rendered(Voxel3D,d,player) then return end
    all[#all+1]=d; if screenVisible(Voxel3D,d) then onScreen[#onScreen+1]=d end
  end
  for _,p in ipairs(posed or {}) do accept(posedDescriptor(p,state.map)) end
  -- When the current host has supplied its exact actor list, that list is the
  -- visibility authority. Do not append raw entities the host did not present
  -- this frame (hidden fly actor, provider-suppressed actor, stale neighbour,
  -- etc.). Older hosts without the bridge retain the proven raw fallback.
  if not hostPosedActive then
    local function addRaw(entity,map,ox,oz) if entity and not seen[entity] then accept(descriptor(entity,map,ox,oz)) end end
    for _,e in ipairs(state.entities or {}) do addRaw(e,state.map,0,0) end
    for _,g in ipairs(state.ghosts or {}) do if g and g.npc then addRaw(g.npc,g.map or state.map,g.ox or 0,g.oy or 0) end end
  end

  local px,pz=playerXZ(player); local _,_,_,nearRadius=settings()
  if px and pz and #all>0 then
    local SI=spatialIndexModule()
    if SI and SI.new then
      if not _npcIndex then _npcIndex=SI.new(math.max(32,nearRadius*.5)) else _npcIndex:clear() end
      local idx=_npcIndex
      for i=1,#all do local d=all[i]; idx:insert(d.entity,d.px+8,d.pz+8,0,d) end
      local recs=idx:queryRadius(px+8,pz+8,nearRadius,{})
      if #recs>0 then
        local visibleNear,near={},{}
        for i=1,#recs do local d=recs[i].payload; near[#near+1]=d; if screenVisible(Voxel3D,d) then visibleNear[#visibleNear+1]=d end end
        if #visibleNear>0 then return visibleNear end
        return near
      end
    end
  end
  return onScreen
end

function N.observe(state)
  if type(state) == "table" then
    -- A map/state replacement invalidates an actor-list reference from the old
    -- scene. The common Battle Art path reuses the same state table and refreshes
    -- _hostPosed later in the render through observeActors().
    if N._state ~= state then
      N._hostPosed = nil
      N._hostActorState = nil
    end
    N._state = state
  end
end

-- Public host-actor observation seam. Current Battle Art invokes registered
-- CharacterRenderers.afterActors callbacks after it has resolved every live
-- character exactly once for the frame. Consuming that context fixes the real
-- fork where VoxelScene's `posed` list is local and never assigned to
-- state.posed. No gameplay object or host render record is modified.
function N.observeActors(context)
  if type(context) ~= "table" then return false end
  local state = context.state
  local posed = context.posed
  if type(state) ~= "table" or type(posed) ~= "table" then return false end
  N._state = state
  N._hostActorState = state
  N._hostPosed = posed
  local host = context.host
  if type(host) == "table" and type(host.Voxel3D) == "table" then
    N._hostVoxel3D = host.Voxel3D
  end
  N._hostActorFrames = N._hostActorFrames + 1
  return true
end

local function enrichVisual(d)
  if not d or d.sprite or not d.entity then return d end
  local sprite,vx,vy,facing,phase,flip=safePose(d.entity)
  if not sprite then return d end
  local out={}; for k,v in pairs(d) do out[k]=v end
  out.sprite=sprite; if vx then out.px=vx+(d.ox or 0) end
  local rawZ=tonumber(d.entity.py or d.entity.y); if rawZ and vy then out.lift=rawZ-vy end
  out.facing,out.phase,out.flip=facing or out.facing,phase or 0,flip or false; out.rawFallback=false
  return out
end

-- Resolve face/head placement from the live sprite card instead of a trainer-
-- sized constant. Gen1/Gen2 overworld figures are normally 16-world-unit cards;
-- companion sprite packs can provide exact `wxEyeAnchor`, `wxEyeY`, `wxEyeSep`,
-- `wxHeadY`, `wxWorldWidth` or `wxWorldHeight` metadata on entity.def/sprite.def.
local function reactionMetrics(d)
  local ed=type(d and d.entity and d.entity.def)=="table" and d.entity.def or {}
  local sd=type(d and d.sprite and d.sprite.def)=="table" and d.sprite.def or {}
  -- Prefer explicit Weather FX anchors, but also understand neutral sprite-pack
  -- metadata names. That lets Gen1/Gen2 Pokémon follower packs provide exact
  -- per-species facial placement without Weather FX carrying a brittle 251-row
  -- species table or guessing from a trainer-sized constant.
  local meta=type(ed.wxEyeAnchor)=="table" and ed.wxEyeAnchor
    or (type(sd.wxEyeAnchor)=="table" and sd.wxEyeAnchor)
    or (type(ed.eyeAnchor)=="table" and ed.eyeAnchor)
    or (type(sd.eyeAnchor)=="table" and sd.eyeAnchor) or nil
  local h=max(8,min(32,tonumber(ed.wxWorldHeight or sd.wxWorldHeight or ed.worldHeight or sd.worldHeight or ed.spriteHeight or sd.spriteHeight or ed.frameHeight or sd.frameHeight) or 16))
  local w=max(8,min(32,tonumber(ed.wxWorldWidth or sd.wxWorldWidth or ed.worldWidth or sd.worldWidth or ed.spriteWidth or sd.spriteWidth or ed.frameWidth or sd.frameWidth) or 16))
  local facing=tostring(d and d.facing or "down"):lower()
  local yRatio=tonumber(meta and (meta.y or meta[2])) or tonumber(ed.wxEyeY or sd.wxEyeY or ed.eyeY or sd.eyeY) or 0.69
  local sepRatio=tonumber(meta and (meta.sep or meta.separation)) or tonumber(ed.wxEyeSep or sd.wxEyeSep or ed.eyeSep or sd.eyeSep) or 0.075
  local eyeWRatio=tonumber(meta and (meta.w or meta.width)) or tonumber(ed.wxEyeW or sd.wxEyeW or ed.eyeW or sd.eyeW) or 0.028
  local eyeHRatio=tonumber(meta and (meta.h or meta.height)) or tonumber(ed.wxEyeH or sd.wxEyeH or ed.eyeH or sd.eyeH) or 0.035
  local headRatio=tonumber(ed.wxHeadY or sd.wxHeadY or ed.headY or sd.headY) or 0.90
  local mode,side="front",0
  if facing=="up" or facing=="north" then mode="back"
  elseif facing=="left" or facing=="west" then mode,side="side",-1
  elseif facing=="right" or facing=="east" then mode,side="side",1 end
  local base=(tonumber(d and d.gh) or 0)+(tonumber(d and d.lift) or 0)
  return {eyeY=base+h*yRatio,headY=base+h*headRatio,sep=w*sepRatio,
    eyeW=max(.20,w*eyeWRatio),eyeH=max(.26,h*eyeHRatio),mode=mode,side=side,width=w,height=h}
end
N.reactionMetrics=reactionMetrics

-- Called once per individual 3D bolt. A successful roll with no eligible NPC
-- simply falls back to ordinary terrain targeting.
function N.rollImpact(Voxel3D, chance, used)
  local enabled, configuredChance = settings()
  if not enabled then return nil end
  chance = clamp01(chance == nil and configuredChance or chance)
  if chance <= 0 then return nil end
  N._rolls = N._rolls + 1
  if random() >= chance then return nil end
  local list = candidates(Voxel3D, used)
  if #list == 0 then
    N._noCandidateRolls = N._noCandidateRolls + 1
    return nil
  end
  N._eligibleRolls = N._eligibleRolls + 1
  local idx = 1 + floor(random() * #list)
  if idx > #list then idx = #list end
  local d = enrichVisual(list[idx])
  local x, z = d.px + 8, d.pz + 8
  -- End the visible channel at head level, but keep the localized light pool on
  -- the ground under the NPC so the strike doesn't create a floating halo.
  local rm=reactionMetrics(d)
  return {
    x=x, y=rm.headY, z=z,
    lightY=d.gh+0.08,
    zone="npc", region="npc-visible", npcTarget=d,
  }
end

function N.hit(target, duration)
  local entity = target and target.entity
  if not entity then return false end
  local _, _, configuredDuration = settings()
  local visual=enrichVisual(target)
  N._effects[entity] = {
    remaining=max(0, tonumber(duration) or configuredDuration),
    age=0,
    target=target,
    visual=visual and visual.sprite and visual or nil,
  }
  V.safeCall(function()
    local ES=V.require("EnvironmentSurface")
    if ES and ES.scorch then ES.scorch((target.px or 0)+8,(target.pz or 0)+8,.42) end
  end)
  N._hits = N._hits + 1
  N._last = entity
  return true
end

function N.update(dt)
  dt = max(0, min(0.25, tonumber(dt) or 0))
  if dt <= 0 then return end
  for entity, rec in pairs(N._effects) do
    rec.age = (tonumber(rec.age) or 0) + dt
    rec.remaining = (tonumber(rec.remaining) or 0) - dt
    if rec.remaining <= 0 then N._effects[entity] = nil end
  end
end

local function resolveActive(entity,rec)
  local state = N._state
  if type(state) ~= "table" then return rec and rec.visual or nil end
  local posed = (N._hostActorState == state and type(N._hostPosed)=="table" and N._hostPosed)
      or state.posed or {}
  for _, p in ipairs(posed) do
    if p and p.entity == entity then return posedDescriptor(p, state.map) end
  end
  for _, e in ipairs(state.entities or {}) do
    if e == entity then return visualDescriptor(e, state.map, 0, 0) end
  end
  for _, g in ipairs(state.ghosts or {}) do
    if g and g.npc == entity then
      return visualDescriptor(entity, g.map or state.map, g.ox or 0, g.oy or 0)
    end
  end
  return rec and rec.visual or nil
end

local function eyeShaderGet()
  if eyeShader ~= nil then return eyeShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then eyeShader=false return nil end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 EyeTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) { vCol=EyeTint; return vp*vec4(v.xyz,1.0); }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) { return vCol*color; }
#endif
]])
  eyeShader = (ok and sh) or false
  return eyeShader or nil
end

local function pushEyeQuad(cx, cy, cz, rx, rz, halfW, halfH)
  local function push(x,y,z)
    eyeVerts[#eyeVerts+1] = {x,y,z,1,1,1,1}
  end
  local lx, lz = cx-rx*halfW, cz-rz*halfW
  local hx, hz = cx+rx*halfW, cz+rz*halfW
  push(lx,cy-halfH,lz); push(hx,cy-halfH,hz); push(hx,cy+halfH,hz)
  push(lx,cy-halfH,lz); push(hx,cy+halfH,hz); push(lx,cy+halfH,lz)
end

local function drawEyes(Voxel3D, list)
  if not (Voxel3D and Voxel3D.eye and Voxel3D.vp) then return false end
  for i=#eyeVerts,1,-1 do eyeVerts[i]=nil end
  local ex, ez = Voxel3D.eye[1] or 0, Voxel3D.eye[3] or 0
  for _, d in ipairs(list) do
    local rec=d._wxEffect
    if not rec or (tonumber(rec.age) or 0)>=FLASH_SECONDS then
    local x, z = d.px+8, d.pz+8
    local dx, dz = ex-x, ez-z
    local len = sqrt(dx*dx+dz*dz)
    if len > 1e-4 then
      dx, dz = dx/len, dz/len
      local rx, rz = dz, -dx
      -- Pull the glints slightly toward the camera so they sit on the live
      -- charred card rather than z-fighting. Facing controls which eyes can
      -- actually be visible; a back-facing Pokémon never gets eyes on its back.
      local bx, bz = x+dx*0.42, z+dz*0.42
      local rm=reactionMetrics(d)
      if rm.mode=="front" then
        pushEyeQuad(bx-rx*rm.sep,rm.eyeY,bz-rz*rm.sep,rx,rz,rm.eyeW,rm.eyeH)
        pushEyeQuad(bx+rx*rm.sep,rm.eyeY,bz+rz*rm.sep,rx,rz,rm.eyeW,rm.eyeH)
      elseif rm.mode=="side" then
        local off=rm.side*rm.sep*.55
        pushEyeQuad(bx+rx*off,rm.eyeY,bz+rz*off,rx,rz,rm.eyeW,rm.eyeH)
      end
    end
    end
  end
  if #eyeVerts < 3 then return false end
  if not (love and love.graphics and love.graphics.newMesh) then return false end
  if not eyeMesh or eyeCap < #eyeVerts then
    local ok, mesh = V.safeCall(love.graphics.newMesh, EYE_FMT, max(#eyeVerts, 24), "triangles", "dynamic")
    if not ok or not mesh then return false end
    eyeMesh, eyeCap = mesh, max(#eyeVerts, 24)
  end
  V.safeCall(eyeMesh.setVertices, eyeMesh, eyeVerts, 1, #eyeVerts)
  if eyeMesh.setDrawRange then V.safeCall(eyeMesh.setDrawRange, eyeMesh, 1, #eyeVerts) end
  local sh = eyeShaderGet()
  if not sh then return false end
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  local began = false
  if Voxel3D.beginEffect then began = Voxel3D.beginEffect(sh) end
  if not began then V.safeCall(love.graphics.setShader, sh) end
  V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
  V.safeCall(sh.send, sh, "vp", Voxel3D.vp)
  V.safeCall(love.graphics.setColor,1,1,1,1)
  V.safeCall(love.graphics.draw, eyeMesh)
  if Voxel3D.endEffect then V.safeCall(Voxel3D.endEffect) else V.safeCall(love.graphics.setShader) end
  V.safeCall(love.graphics.setDepthMode, "lequal", true)
  return true
end

local function skeletonPush(x,y,z,a)
  skeletonVerts[#skeletonVerts+1]={x,y,z,1.0,1.0,1.0,a}
end
local function skeletonQuad(baseX,baseZ,frontX,frontZ,rx,rz,ax,ay,bx,by,width,alpha)
  local dx,dy=bx-ax,by-ay;local l=sqrt(dx*dx+dy*dy);if l<1e-5 then return end
  local nx,ny=-dy/l*width,dx/l*width
  local function P(lx,ly)
    return {baseX+rx*lx+frontX*.62,ly,baseZ+rz*lx+frontZ*.62}
  end
  local p1,p2,p3,p4=P(ax+nx,ay+ny),P(bx+nx,by+ny),P(bx-nx,by-ny),P(ax-nx,ay-ny)
  skeletonPush(p1[1],p1[2],p1[3],alpha);skeletonPush(p2[1],p2[2],p2[3],alpha);skeletonPush(p3[1],p3[2],p3[3],alpha)
  skeletonPush(p1[1],p1[2],p1[3],alpha);skeletonPush(p3[1],p3[2],p3[3],alpha);skeletonPush(p4[1],p4[2],p4[3],alpha)
end
local function drawSkeleton(Voxel3D,list)
  if not (Voxel3D and Voxel3D.eye and Voxel3D.vp and love and love.graphics and love.graphics.newMesh) then return false end
  for i=#skeletonVerts,1,-1 do skeletonVerts[i]=nil end
  local ex,ez=Voxel3D.eye[1] or 0,Voxel3D.eye[3] or 0
  for _,d in ipairs(list) do
    local rec=d._wxEffect;local age=rec and tonumber(rec.age) or 9
    local phase=floor(age/FLASH_STEP)%2
    if age<=FLASH_SECONDS and phase==1 then
      local x,z=d.px+8,d.pz+8;local fx,fz=ex-x,ez-z;local ll=sqrt(fx*fx+fz*fz)
      if ll>1e-4 then
        fx,fz=fx/ll,fz/ll;local rx,rz=fz,-fx;local rm=reactionMetrics(d)
        local base=rm.headY-rm.height*.90;local h,w=rm.height,rm.width;local a=1.0
        -- Keep each x-ray phase on screen for several real frames and make the
        -- bones intentionally broad.  The former 20 ms / hairline geometry could
        -- be skipped completely at 30 FPS and became sub-pixel at distance even
        -- though the draw call technically succeeded.
        skeletonQuad(x,z,fx,fz,rx,rz,0,base+h*.75,0,base+h*.91,w*.17,a)
        skeletonQuad(x,z,fx,fz,rx,rz,0,base+h*.34,0,base+h*.77,w*.050,a)
        for j=0,4 do local yy=base+h*(.48+j*.060);skeletonQuad(x,z,fx,fz,rx,rz,-w*(.25-j*.018),yy,w*(.25-j*.018),yy,w*.038,a) end
        skeletonQuad(x,z,fx,fz,rx,rz,-w*.16,base+h*.35,w*.16,base+h*.35,w*.052,a)
        skeletonQuad(x,z,fx,fz,rx,rz,-w*.11,base+h*.69,-w*.39,base+h*.42,w*.047,a)
        skeletonQuad(x,z,fx,fz,rx,rz,w*.11,base+h*.69,w*.39,base+h*.42,w*.047,a)
        skeletonQuad(x,z,fx,fz,rx,rz,-w*.08,base+h*.35,-w*.22,base+h*.05,w*.052,a)
        skeletonQuad(x,z,fx,fz,rx,rz,w*.08,base+h*.35,w*.22,base+h*.05,w*.052,a)
      end
    end
  end
  if #skeletonVerts<3 then return false end
  if not skeletonMesh or skeletonCap<#skeletonVerts then
    local cap=max(96,#skeletonVerts);local ok,m=V.safeCall(love.graphics.newMesh,EYE_FMT,cap,"triangles","dynamic");if not ok or not m then return false end;skeletonMesh,skeletonCap=m,cap
  end
  V.safeCall(skeletonMesh.setVertices,skeletonMesh,skeletonVerts,1,#skeletonVerts);if skeletonMesh.setDrawRange then V.safeCall(skeletonMesh.setDrawRange,skeletonMesh,1,#skeletonVerts) end
  local sh=eyeShaderGet();if not sh then return false end
  V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply");V.safeCall(love.graphics.setDepthMode,"lequal",false)
  local began=false;if Voxel3D.beginEffect then began=Voxel3D.beginEffect(sh) end;if not began then V.safeCall(love.graphics.setShader,sh) end
  -- Match the eye/smoke compatibility path: some voxel hosts accept the
  -- explicit row-major form while others only populate this shader uniform via
  -- the default matrix send.  Trying both is fail-open and prevents an invisible
  -- skeleton with a valid mesh.
  V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp);V.safeCall(sh.send,sh,"vp",Voxel3D.vp)
  V.safeCall(love.graphics.setColor,1,1,1,1);V.safeCall(love.graphics.draw,skeletonMesh)
  if Voxel3D.endEffect then V.safeCall(Voxel3D.endEffect) else V.safeCall(love.graphics.setShader) end
  V.safeCall(love.graphics.setDepthMode,"lequal",true);return true
end

local function pushSmokeQuad(cx,cy,cz,rx,rz,half,a,r,g,b)
  r,g,b=tonumber(r) or .20,tonumber(g) or .20,tonumber(b) or .22
  local function push(x,y,z) smokeVerts[#smokeVerts+1]={x,y,z,r,g,b,a} end
  local lx,lz=cx-rx*half,cz-rz*half; local hx,hz=cx+rx*half,cz+rz*half
  push(lx,cy-half,lz);push(hx,cy-half,hz);push(hx,cy+half,hz)
  push(lx,cy-half,lz);push(hx,cy+half,hz);push(lx,cy+half,lz)
end

local function drawSmoke(Voxel3D,list)
  if not (Voxel3D and Voxel3D.eye and Voxel3D.vp and love and love.graphics and love.graphics.newMesh) then return false end
  for i=#smokeVerts,1,-1 do smokeVerts[i]=nil end
  local ex,ez=Voxel3D.eye[1] or 0,Voxel3D.eye[3] or 0
  for _,d in ipairs(list) do
    local rec=d._wxEffect; local age=rec and tonumber(rec.age) or 9
    local remaining=rec and tonumber(rec.remaining) or 0
    local duration=max(.25,age+remaining)
    if age>=SMOKE_DELAY and remaining>0 then
      local smokeAge=age-SMOKE_DELAY
      local x,z=d.px+8,d.pz+8; local dx,dz=ex-x,ez-z; local len=sqrt(dx*dx+dz*dz)
      if len>1e-4 then
        dx,dz=dx/len,dz/len; local rx,rz=dz,-dx; local rm=reactionMetrics(d)
        -- The old smoke was technically present but only ~0.8-1.8 world units
        -- wide and dark grey; at normal third-person distance that becomes a
        -- sub-pixel smudge.  Keep it depth-tested/world-anchored, but make the
        -- puffs large enough to read and offset them slightly toward the camera
        -- so the struck sprite's own depth cannot swallow the plume.
        local fade=max(.20,1-smokeAge/max(.25,duration-SMOKE_DELAY))
        for j=0,5 do
          local localAge=(smokeAge+j*.16)%1.22
          local t=localAge/1.22
          local half=1.35+1.75*t
          local alpha=(1-t)*.88*fade
          local side=(j-2.5)*.58+math.sin(smokeAge*4.7+j*1.73)*.28
          local cx=x+rx*side+dx*1.15
          local cy=rm.headY+1.05+localAge*4.6+j*.16
          local cz=z+rz*side+dz*1.15
          -- Dark body + lighter inner puff gives contrast against both storm
          -- clouds and bright lightning without turning smoke into white steam.
          pushSmokeQuad(cx,cy,cz,rx,rz,half,alpha,.14,.14,.16)
          pushSmokeQuad(cx-rx*.15,cy+.10,cz-rz*.15,rx,rz,half*.58,alpha*.48,.58,.58,.62)
        end
      end
    end
  end
  N._lastSmokeVerts=#smokeVerts
  if #smokeVerts<3 then return false end
  if not smokeMesh or smokeCap<#smokeVerts then
    local cap=max(24,#smokeVerts); local ok,m=V.safeCall(love.graphics.newMesh,EYE_FMT,cap,"triangles","dynamic"); if not ok or not m then return false end; smokeMesh,smokeCap=m,cap
  end
  V.safeCall(smokeMesh.setVertices,smokeMesh,smokeVerts,1,#smokeVerts); if smokeMesh.setDrawRange then V.safeCall(smokeMesh.setDrawRange,smokeMesh,1,#smokeVerts) end
  local sh=eyeShaderGet(); if not sh then return false end
  V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply"); V.safeCall(love.graphics.setDepthMode,"lequal",false)
  local began=false; if Voxel3D.beginEffect then began=Voxel3D.beginEffect(sh) end; if not began then V.safeCall(love.graphics.setShader,sh) end
  V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp); V.safeCall(sh.send,sh,"vp",Voxel3D.vp); V.safeCall(love.graphics.setColor,1,1,1,1); V.safeCall(love.graphics.draw,smokeMesh)
  if Voxel3D.endEffect then V.safeCall(Voxel3D.endEffect) else V.safeCall(love.graphics.setShader) end
  V.safeCall(love.graphics.setDepthMode,"lequal",true)
  return true
end

function N.draw(Voxel3D)
  local VS = voxelScene()
  if not (Voxel3D and VS and type(VS.drawEntity) == "function"
      and type(Voxel3D.flatten) == "function") then return false end
  local active = {}
  for entity, rec in pairs(N._effects) do
    if (rec.remaining or 0) > 0 then
      local d = resolveActive(entity,rec)
      -- A raw-coordinate target can still receive a real bolt even when the
      -- host cannot safely provide a drawable sprite a second time. The
      -- optional cartoon-charred overlay simply stands down for that target.
      if d and d.sprite then d._wxEffect=rec; active[#active+1] = d end
    end
  end
  if #active == 0 then return false end

  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  local flattened = false
  local ok = V.safeCall(function()
    if type(Voxel3D.lighting)=="function" then Voxel3D.lighting(false) end
    for _, d in ipairs(active) do
      local age=tonumber(d._wxEffect and d._wxEffect.age) or 9
      local flash=age<=FLASH_SECONDS and floor(age/FLASH_STEP)%2==0
      Voxel3D.flatten(flash and {1.0,1.0,1.0} or {0.006,0.006,0.008},1)
      flattened=true
      local px,pz=d.px,d.pz
      if Voxel3D.eye then
        local dx,dz=(Voxel3D.eye[1] or 0)-(d.px+8),(Voxel3D.eye[3] or 0)-(d.pz+8); local l=sqrt(dx*dx+dz*dz)
        if l>1e-4 then px=px+dx/l*.18; pz=pz+dz/l*.18 end
      end
      VS.drawEntity(d.sprite,px,pz,d.facing,d.phase,d.flip,d.gh,nil,d.lift)
    end
  end)
  if flattened then V.safeCall(Voxel3D.flatten, nil) end
  if type(Voxel3D.lighting)=="function" then V.safeCall(Voxel3D.lighting,true) end
  V.safeCall(love.graphics.setDepthMode, "lequal", true)
  if not ok then return false end
  drawSkeleton(Voxel3D,active)
  drawEyes(Voxel3D,active)
  drawSmoke(Voxel3D,active)
  return true
end

function N.clearEffects()
  for k in pairs(N._effects) do N._effects[k]=nil end
end

function N.activeCount()
  local n=0
  for _, rec in pairs(N._effects) do if (rec.remaining or 0)>0 then n=n+1 end end
  return n
end

function N.candidateCount(Voxel3D, used)
  return #candidates(Voxel3D, used)
end

function N.stats(Voxel3D)
  local eligible = 0
  if Voxel3D then eligible = #candidates(Voxel3D, nil) end
  return {
    chance = select(2, settings()),
    active = N.activeCount(),
    hits = N._hits,
    rolls = N._rolls,
    eligibleRolls = N._eligibleRolls,
    noCandidateRolls = N._noCandidateRolls,
    rawFallbacks = N._rawFallbacks,
    hostActorFrames = N._hostActorFrames,
    hostActorBridge = (N._hostActorState == N._state and type(N._hostPosed)=="table") and true or false,
    visibleCandidates = eligible,
    smokeVerts = tonumber(N._lastSmokeVerts) or 0,
  }
end

function N.describe(Voxel3D)
  local st = N.stats(Voxel3D)
  return string.format(
    "npc-lightning chance=%.0f%% visible=%d active=%d hits=%d rolls=%d noCandidate=%d rawFallbacks=%d hostBridge=%s hostFrames=%d",
    (st.chance or N.CHANCE)*100, st.visibleCandidates or 0, st.active or 0, st.hits or 0,
    st.rolls or 0, st.noCandidateRolls or 0, st.rawFallbacks or 0,
    tostring(st.hostActorBridge==true), st.hostActorFrames or 0)
end

function N.invalidate()
  for k in pairs(N._effects) do N._effects[k]=nil end
  eyeMesh, eyeShader, eyeCap = nil, nil, 0
  smokeMesh, smokeCap = nil, 0
  N._lastSmokeVerts=0
  N._hostPosed, N._hostActorState, N._hostVoxel3D = nil, nil, nil
  N._hostActorFrames = 0
  skeletonMesh, skeletonCap = nil, 0
  for i=#eyeVerts,1,-1 do eyeVerts[i]=nil end
  for i=#smokeVerts,1,-1 do smokeVerts[i]=nil end
  for i=#skeletonVerts,1,-1 do skeletonVerts[i]=nil end
end

-- Test-only deterministic RNG seam. Production never calls this.
function N._setRandom(fn)
  random = type(fn)=="function" and fn or math.random
end

return N
