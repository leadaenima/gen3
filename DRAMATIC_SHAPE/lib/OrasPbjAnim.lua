-- ORAS PBJ / GF1Motion clip playback helpers for OrasModels.
-- Loads AppData anims/anim_by_national.json + *_clips.json (written by pbj_rip.py).
-- Evaluates Waist/Origin/Hips channels for whole-mesh root motion (real tracks).
-- Full per-vertex skinning when mesh.json has keep_skin sidecars (phase 2).
-- KNOWN ISSUE (2026-09-14): runtime LOVE skin (buildSkinMatrices / skinVertices)
-- morphs nationals. Offline Python skin (bch_mesh / bake_wait_poses) err~0.
-- OrasModels.ENABLE_SKINNING=false; display uses baked wait_pose vertices +
-- optional wait_loop_xyz serpent blend (no runtime skinner).

local V = ...

local OrasPbjAnim = {}

OrasPbjAnim.FPS = 30
OrasPbjAnim.SLOPE_SCALE = 1 / 30
OrasPbjAnim.ROOT_BONES = { "Waist", "Origin", "Hips", "Spine1", "Spine2" }
OrasPbjAnim.SKINNED_SOURCE = "pbj_gf1_skinned"
OrasPbjAnim.SKINNED_IDLE_SOURCE = "pbj_gf1_skinned"

local indexCache
local clipCache = {} -- national -> clip file table | false

local function decodeJson(text)
  if type(text) ~= "string" or text == "" then return nil end
  local ok, Json = pcall(require, "src.link.Json")
  if ok and Json and Json.decode then
    local obj = Json.decode(text)
    if type(obj) == "table" then return obj end
  end
  local ok2, dkjson = pcall(require, "dkjson")
  if ok2 and dkjson and dkjson.decode then
    local obj = dkjson.decode(text)
    if type(obj) == "table" then return obj end
  end
  return nil
end

local function cacheFsRead(rel)
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okCf and CacheFs and CacheFs.read) then return nil end
  local saved = CacheFs.prefix
  CacheFs.prefix = ""
  local data = CacheFs.read(rel)
  CacheFs.prefix = saved
  if type(data) ~= "string" or data == "" then return nil end
  return data
end

function OrasPbjAnim.loadIndex()
  if indexCache ~= nil then return indexCache ~= false and indexCache or nil end
  local raw = cacheFsRead("oras_extract/anims/anim_by_national.json")
  local obj = raw and decodeJson(raw)
  if type(obj) == "table" and type(obj.by_national) == "table" then
    indexCache = obj
    return obj
  end
  indexCache = false
  return nil
end

function OrasPbjAnim.loadClips(national)
  national = tonumber(national)
  if not national then return nil end
  local key = tostring(national)
  if clipCache[key] ~= nil then
    return clipCache[key] ~= false and clipCache[key] or nil
  end
  local idx = OrasPbjAnim.loadIndex()
  local row = idx and idx.by_national and idx.by_national[key]
  if type(row) ~= "table" or type(row.rel) ~= "string" then
    clipCache[key] = false
    return nil
  end
  local raw = cacheFsRead("oras_extract/anims/" .. row.rel)
  local obj = raw and decodeJson(raw)
  if type(obj) ~= "table" or type(obj.clips) ~= "table" then
    clipCache[key] = false
    return nil
  end
  clipCache[key] = obj
  return obj
end

local function findChannel(clip, boneNames, axis)
  if type(clip) ~= "table" or type(clip.bones) ~= "table" then return nil end
  for _, want in ipairs(boneNames) do
    for _, b in ipairs(clip.bones) do
      if b and b.name == want and b.channels and b.channels[axis] then
        return b.channels[axis], b.name
      end
    end
  end
  -- First bone that has this axis
  for _, b in ipairs(clip.bones) do
    if b and b.channels and b.channels[axis] and #b.channels[axis] > 0 then
      return b.channels[axis], b.name
    end
  end
  return nil
end

local function findBoneChannels(clip, boneName)
  if type(clip) ~= "table" or type(clip.bones) ~= "table" then return nil end
  for _, b in ipairs(clip.bones) do
    if b and b.name == boneName then
      return b.channels
    end
  end
  return nil
end

local function evalChannel(kfs, frame)
  if type(kfs) ~= "table" or #kfs < 1 then return 0 end
  if #kfs == 1 then return tonumber(kfs[1].value) or 0 end
  local f = frame
  if f <= (tonumber(kfs[1].frame) or 0) then
    return tonumber(kfs[1].value) or 0
  end
  local last = kfs[#kfs]
  if f >= (tonumber(last.frame) or 0) then
    return tonumber(last.value) or 0
  end
  for i = 1, #kfs - 1 do
    local a, b = kfs[i], kfs[i + 1]
    local fa, fb = tonumber(a.frame) or 0, tonumber(b.frame) or 0
    if f >= fa and f <= fb then
      local span = fb - fa
      if span <= 1e-6 then return tonumber(a.value) or 0 end
      local t = (f - fa) / span
      local v0, v1 = tonumber(a.value) or 0, tonumber(b.value) or 0
      local s0 = (tonumber(a.slope) or 0) * OrasPbjAnim.SLOPE_SCALE * span
      local s1 = (tonumber(b.slope) or 0) * OrasPbjAnim.SLOPE_SCALE * span
      local t2, t3 = t * t, t * t * t
      return (2 * t3 - 3 * t2 + 1) * v0
        + (t3 - 2 * t2 + t) * s0
        + (-2 * t3 + 3 * t2) * v1
        + (t3 - t2) * s1
    end
  end
  return tonumber(last.value) or 0
end

function OrasPbjAnim.pickClip(pack, role, preferShort)
  if type(pack) ~= "table" or type(pack.clips) ~= "table" then return nil end
  if preferShort then
    for _, c in ipairs(pack.clips) do
      if c and c.short == preferShort then return c end
    end
  end
  -- Prefer first matching role (waitA before waitB if roles dict points at B —
  -- scan clips in file order for role).
  local preferSub
  if role == "wait" then preferSub = "waitA" end
  if role == "land" then preferSub = "landA" end
  local fallback
  for _, c in ipairs(pack.clips) do
    if c and c.role == role and not c.error then
      if preferSub and c.short and c.short:find(preferSub, 1, true) then
        return c
      end
      fallback = fallback or c
    end
  end
  if fallback then return fallback end
  -- roles dict short name
  local short = pack.roles and pack.roles[role]
  if type(short) == "string" then
    for _, c in ipairs(pack.clips) do
      if c and c.short == short then return c end
    end
  end
  return nil
end

function OrasPbjAnim.roleForBattleKind(kind, physical)
  if kind == "attack" then
    if physical == false then return "attack_special" end
    return "attack_physical"
  end
  if kind == "damage" then return "damage" end
  if kind == "faint" then return "faint" end
  if kind == "land" then return "land" end
  if kind == "idle" or kind == "wait" then return "wait" end
  return nil
end

--- Delta root motion at normalized u in [0,1] relative to frame 0.
-- Returns tx,ty,tz, rx,ry,rz (radians) suitable for Mat4 composition.
function OrasPbjAnim.rootDelta(clip, u)
  if type(clip) ~= "table" then return 0, 0, 0, 0, 0, 0 end
  local frames = math.max(1, tonumber(clip.frames) or 1)
  local frame = (tonumber(u) or 0) * frames
  if frame < 0 then frame = 0 end
  if frame > frames then frame = frames end
  local bones = OrasPbjAnim.ROOT_BONES
  local function delta(axis)
    local kfs = findChannel(clip, bones, axis)
    if not kfs then return 0 end
    return evalChannel(kfs, frame) - evalChannel(kfs, 0)
  end
  return delta("translation_x"), delta("translation_y"), delta("translation_z"),
    delta("rotation_x"), delta("rotation_y"), delta("rotation_z")
end

function OrasPbjAnim.clipDuration(clip)
  local frames = tonumber(clip and clip.frames) or 0
  if frames <= 0 then return nil end
  return frames / OrasPbjAnim.FPS
end

function OrasPbjAnim.hasMoveClips(national)
  local pack = OrasPbjAnim.loadClips(national)
  if not pack then return false end
  return OrasPbjAnim.pickClip(pack, "attack_physical") ~= nil
    or OrasPbjAnim.pickClip(pack, "attack_special") ~= nil
end

function OrasPbjAnim.clipFrame(clip, u)
  if type(clip) ~= "table" then return 0 end
  local frames = math.max(1, tonumber(clip.frames) or 1)
  local frame = (tonumber(u) or 0) * frames
  if frame < 0 then frame = 0 end
  if frame > frames then frame = frames end
  return frame, frames
end

--------------------------------------------------------------------------
-- Per-vertex skeletal skinning (Ohana / BCH conventions)
-- Matrices are [col][row] like bch_mesh.py; xform is row-vector * matrix.
--------------------------------------------------------------------------

local function m4id()
  return {
    { 1, 0, 0, 0 },
    { 0, 1, 0, 0 },
    { 0, 0, 1, 0 },
    { 0, 0, 0, 1 },
  }
end

local function m4mul(a, b)
  local out = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
  for i = 1, 4 do
    for j = 1, 4 do
      out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j]
        + a[i][3] * b[3][j] + a[i][4] * b[4][j]
    end
  end
  return out
end

local function m4scale(sx, sy, sz)
  local m = m4id()
  m[1][1], m[2][2], m[3][3] = sx, sy, sz
  return m
end

local function m4rotx(a)
  local c, s = math.cos(a), math.sin(a)
  local m = m4id()
  m[2][2], m[3][2] = c, -s
  m[2][3], m[3][3] = s, c
  return m
end

local function m4roty(a)
  local c, s = math.cos(a), math.sin(a)
  local m = m4id()
  m[1][1], m[3][1] = c, s
  m[1][3], m[3][3] = -s, c
  return m
end

local function m4rotz(a)
  local c, s = math.cos(a), math.sin(a)
  local m = m4id()
  m[1][1], m[2][1] = c, -s
  m[1][2], m[2][2] = s, c
  return m
end

local function m4trans(x, y, z)
  local m = m4id()
  m[4][1], m[4][2], m[4][3] = x, y, z
  return m
end

local function m4xform(m, x, y, z)
  return
    x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
    x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
    x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
end

-- Row-major flat (16) from mesh.json inv_transform -> Ohana [col][row]
local function invFromRowMajor(flat)
  local m = m4id()
  if type(flat) ~= "table" or #flat < 16 then return m end
  for r = 0, 3 do
    for c = 0, 3 do
      m[c + 1][r + 1] = tonumber(flat[r * 4 + c + 1]) or 0
    end
  end
  return m
end

local function localFromSRT(sx, sy, sz, rx, ry, rz, tx, ty, tz)
  -- Ohana: scale * rotX * rotY * rotZ * translate
  local t = m4scale(sx, sy, sz)
  t = m4mul(t, m4rotx(rx))
  t = m4mul(t, m4roty(ry))
  t = m4mul(t, m4rotz(rz))
  t = m4mul(t, m4trans(tx, ty, tz))
  return t
end

local function sampleAxis(channels, axis, frame, fallback)
  if not channels or not channels[axis] then return fallback end
  return evalChannel(channels[axis], frame)
end

--- Build per-bone skin matrices for clip at normalized u (or rest if clip nil).
-- bones: mesh.json bones list (name, parent_id, scale, rotation, translation, inv_transform)
-- Returns { matrices = {m4,...}, boneCount = N }
function OrasPbjAnim.buildSkinMatrices(bones, clip, u)
  if type(bones) ~= "table" or #bones < 1 then return nil end
  local frame = 0
  if clip then
    frame = select(1, OrasPbjAnim.clipFrame(clip, u or 0))
  end
  local n = #bones
  local locals = {}
  for i = 1, n do
    local b = bones[i]
    local sx = tonumber(b.scale and b.scale[1]) or 1
    local sy = tonumber(b.scale and b.scale[2]) or 1
    local sz = tonumber(b.scale and b.scale[3]) or 1
    local rx = tonumber(b.rotation and b.rotation[1]) or 0
    local ry = tonumber(b.rotation and b.rotation[2]) or 0
    local rz = tonumber(b.rotation and b.rotation[3]) or 0
    local tx = tonumber(b.translation and b.translation[1]) or 0
    local ty = tonumber(b.translation and b.translation[2]) or 0
    local tz = tonumber(b.translation and b.translation[3]) or 0
    if clip then
      local ch = findBoneChannels(clip, b.name)
      if ch then
        sx = sampleAxis(ch, "scale_x", frame, sx)
        sy = sampleAxis(ch, "scale_y", frame, sy)
        sz = sampleAxis(ch, "scale_z", frame, sz)
        rx = sampleAxis(ch, "rotation_x", frame, rx)
        ry = sampleAxis(ch, "rotation_y", frame, ry)
        rz = sampleAxis(ch, "rotation_z", frame, rz)
        tx = sampleAxis(ch, "translation_x", frame, tx)
        ty = sampleAxis(ch, "translation_y", frame, ty)
        tz = sampleAxis(ch, "translation_z", frame, tz)
      end
    end
    locals[i] = localFromSRT(sx, sy, sz, rx, ry, rz, tx, ty, tz)
  end
  local world = {}
  local function buildWorld(idx)
    if world[idx] then return world[idx] end
    local b = bones[idx]
    local t = locals[idx]
    local pid = tonumber(b.parent_id) or -1
    -- JSON may use 0-based parent_id matching BCH
    if pid >= 0 and pid < n then
      t = m4mul(t, buildWorld(pid + 1))
    end
    world[idx] = t
    return t
  end
  for i = 1, n do buildWorld(i) end
  local skin = {}
  for i = 1, n do
    local inv = invFromRowMajor(bones[i].inv_transform)
    -- smooth default: world * invBind; caller may use world-only for rigid
    skin[i] = m4mul(world[i], inv)
  end
  return { matrices = skin, worlds = world, boneCount = n }
end

--- Skin local XYZ (3*N floats) with 4 influences -> posed XYZ (3*N).
function OrasPbjAnim.skinVertices(localVerts, boneIndices, boneWeights, skinPack, skinningMode)
  if type(localVerts) ~= "table" or type(skinPack) ~= "table" then return nil end
  local mats = skinPack.matrices
  local worlds = skinPack.worlds
  if type(mats) ~= "table" then return nil end
  local rigid = (tonumber(skinningMode) or 1) ~= 1
  local vcount = math.floor(#localVerts / 3)
  local out = {}
  for vi = 0, vcount - 1 do
    local lx = localVerts[vi * 3 + 1] or 0
    local ly = localVerts[vi * 3 + 2] or 0
    local lz = localVerts[vi * 3 + 3] or 0
    local sx, sy, sz = 0, 0, 0
    if rigid then
      local bi = (boneIndices and boneIndices[vi * 4 + 1]) or 0
      local m = worlds and worlds[bi + 1]
      if m then
        sx, sy, sz = m4xform(m, lx, ly, lz)
      else
        sx, sy, sz = lx, ly, lz
      end
    else
      local wsum = 0
      for k = 0, 3 do
        local bi = (boneIndices and boneIndices[vi * 4 + k + 1]) or 0
        local w = (boneWeights and boneWeights[vi * 4 + k + 1]) or 0
        local m = mats[bi + 1]
        if m and w ~= 0 then
          local x, y, z = m4xform(m, lx, ly, lz)
          sx = sx + x * w
          sy = sy + y * w
          sz = sz + z * w
          wsum = wsum + w
        end
      end
      if wsum > 1e-8 then
        sx, sy, sz = sx / wsum, sy / wsum, sz / wsum
      else
        sx, sy, sz = lx, ly, lz
      end
    end
    out[vi * 3 + 1] = sx
    out[vi * 3 + 2] = sy
    out[vi * 3 + 3] = sz
  end
  return out
end

function OrasPbjAnim.meshHasSkin(modelOrGroup)
  if type(modelOrGroup) ~= "table" then return false end
  if type(modelOrGroup.bones) == "table" and #modelOrGroup.bones > 0 then
    if type(modelOrGroup.meshes) == "table" then
      for _, m in ipairs(modelOrGroup.meshes) do
        if m and m.local_vertices and m.bone_indices then return true end
      end
    end
    if modelOrGroup.local_vertices and modelOrGroup.bone_indices then return true end
  end
  return false
end

function OrasPbjAnim.status()
  local idx = OrasPbjAnim.loadIndex()
  local stats = idx and idx.stats or nil
  local n = 0
  if idx and idx.by_national then
    for _ in pairs(idx.by_national) do n = n + 1 end
  end
  return {
    loaded = idx ~= nil,
    nationals = n,
    stats = stats,
    source = "oras_extract/anims (GF1Motion / PBJ)",
    skinnedSource = OrasPbjAnim.SKINNED_SOURCE,
  }
end

return OrasPbjAnim
