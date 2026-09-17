-- Phase-1 ORAS 3D battle meshes: load JSON (bind-pose skinned) + Body texture.
-- Two consumers:
--   * 2D bake path (OPT-IN bake2dUi): project to a 96px canvas for Game3:drawBattlePic (menus /
--     non-voxel battles). Still looks flat in a 3D arena — fallback only.
--   * Voxel / DramaticShapes path: build real LOVE 3D meshes (Voxel3D vertex
--     format) so BattleScene can draw them with the battle camera / depth.
--
-- IMPORTANT: this file runs inside the mod sandbox. love.filesystem and io are
-- unavailable here (Sandbox blocks them). Read save-dir JSON via engine
-- CacheFs / mod:read only; pass texture paths to Game3:grabImage (engine FS).
local M = {}

local missLog = {} -- "nat:which" -> true (once per key per apply)
local hitLog = {}

local function logInfo(fmt, ...)
  local logger = M._log
  if logger and logger.info then
    logger:info(fmt, ...)
  else
    local ok, Logger = pcall(require, "src.core.Logger")
    if ok and Logger and Logger.info then
      Logger.info("[oras_models] " .. fmt, ...)
    end
  end
end

local function logWarn(fmt, ...)
  local logger = M._log
  if logger and logger.warn then
    logger:warn(fmt, ...)
  else
    local ok, Logger = pcall(require, "src.core.Logger")
    if ok and Logger and Logger.warn then
      Logger.warn("[oras_models] " .. fmt, ...)
    end
  end
end

-- Rewrite AppData/.../oras_extract/... absolutes to save-dir relative without
-- touching love.filesystem (blocked in the mod sandbox).

local function shaderWantsSecondarySheet(shader)
  -- Body01 sheet-index, or CamelCase BodyB* token (not BodyBuffron).
  local sh = tostring(shader or "")
  local low = sh:lower():gsub("%s+", "")
  if low:match("^body01") or low:find("_body01", 1, true) then
    return true
  end
  if sh:match("BodyB$") or sh:match("BodyB[%d_]") or sh:match("BodyB[A-Z]") then
    return true
  end
  return false
end

local function preferColorizedPath(path)
  if type(path) ~= "string" or path == "" then return path end
  local function exists(p)
    if type(p) ~= "string" or p == "" then return false end
    local f = io.open(p, "rb")
    if f then f:close() return true end
    local okCf, CacheFs = pcall(require, "src.import.CacheFs")
    if okCf and CacheFs and CacheFs.exists then
      local saved = CacheFs.prefix
      CacheFs.prefix = ""
      local ok = CacheFs.exists(p:gsub("\\", "/")) or CacheFs.exists(p)
      CacheFs.prefix = saved
      return ok and true or false
    end
    return false
  end
  local candidates = {
    path:gsub("%.png$", "_colorized.png"),
    path:gsub("%.png$", "_petal.png"),
    path:gsub("Body2%.png$", "Body2_colorized.png"),
    path:gsub("Body2%.png$", "Body2_petal.png"),
    path:gsub("FireCoreA1%.png$", "FireCoreA1_colorized.png"),
    path:gsub("FireStenA1%.png$", "FireStenA1_colorized.png"),
  }
  for _, c in ipairs(candidates) do
    if c ~= path and exists(c) then return c end
  end
  return path
end

local function pathExists(p)
  if type(p) ~= "string" or p == "" then return false end
  local f = io.open(p, "rb")
  if f then f:close() return true end
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if okCf and CacheFs and CacheFs.exists then
    local saved = CacheFs.prefix
    CacheFs.prefix = ""
    local ok = CacheFs.exists(p:gsub("\\", "/")) or CacheFs.exists(p)
    CacheFs.prefix = saved
    return ok and true or false
  end
  return false
end

local function cloneMd(md, shader, tex, path)
  return {
    name = md.name,
    material_id = md.material_id,
    material_shader = md.material_shader or shader,
    texture = tex,
    texture_path = path,
    vertices = md.vertices,
    indices = md.indices,
    local_vertices = md.local_vertices,
    bone_indices = md.bone_indices,
    bone_weights = md.bone_weights,
    skinning_mode = md.skinning_mode,
    influences = md.influences,
  }
end

local function remapBodySheetTexture(md)
  -- Safety net for cached mesh.json.
  -- * Prefer *_colorized / *_petal sidecars when present.
  -- * Petal/Flower parts may use Body2 (+ colorize).
  -- * Body01/BodyB without petal: Body2 is often inverse-shadow greyscale —
  --   keep Body1 (Charmander belly / Squirtle shell accents) unless a bake exists.
  if type(md) ~= "table" then return md end
  local shader = tostring(md.material_shader or "")
  local tex = tostring(md.texture or "")
  local path = tostring(md.texture_path or "")
  local part = tostring(md.name or "")
  local isPetal = part:find("Petal", 1, true) ~= nil
    or part:find("Flower", 1, true) ~= nil
    or part:find("Blossom", 1, true) ~= nil
  local wantSecondary = shaderWantsSecondarySheet(shader) or isPetal

  -- Fire / intensity sheets: prefer colorized sidecar.
  if path ~= "" then
    local pref = preferColorizedPath(path)
    if pref ~= path and pathExists(pref) then
      md = cloneMd(md, shader, tex ~= "" and tex or md.texture, pref)
      path = pref
      tex = tostring(md.texture or tex)
    end
  end

  local onBody2 = tex:find("Body2", 1, true) ~= nil or path:find("Body2", 1, true) ~= nil
  if onBody2 then
    local pref = preferColorizedPath(path)
    if pref ~= path and pathExists(pref) then
      return cloneMd(md, shader, tex, pref)
    end
    -- Non-petal Body01 bound to greyscale Body2 shadow map: fall back to Body1.
    if wantSecondary and not isPetal then
      local body1Path = path:gsub("Body2", "Body1")
      local body1Tex = tex:gsub("Body2", "Body1")
      if body1Path ~= path and pathExists(body1Path) then
        return cloneMd(md, shader, body1Tex, body1Path)
      end
    end
    return md
  end

  if not wantSecondary then return md end
  if tex:find("BodyB", 1, true) or path:find("BodyB", 1, true) then return md end
  local lowTex = tex:lower()
  if lowTex == "" or lowTex:find("dummy", 1, true) then return md end
  if not tex:find("Body1", 1, true) and not path:find("Body1", 1, true) then
    return md
  end
  local newTex = tex:gsub("Body1", "Body2")
  local newPath = path:gsub("Body1", "Body2")
  if newPath == path then
    newPath = path:gsub("Body1%.png", "Body2.png")
  end
  local colorized = preferColorizedPath(newPath)
  -- Petal: Body2 or colorized. Non-petal Body01: only if colorized bake exists.
  if isPetal then
    if colorized ~= newPath and pathExists(colorized) then
      return cloneMd(md, shader, newTex, colorized)
    end
    if pathExists(newPath) then
      return cloneMd(md, shader, newTex, newPath)
    end
    return md
  end
  if colorized ~= newPath and pathExists(colorized) then
    return cloneMd(md, shader, newTex, colorized)
  end
  -- Keep Body1 for Charmander/Squirtle-style Body01 (Body2 = shadow map).
  return md
end




local function toSaveRel(path)
  if type(path) ~= "string" or path == "" then return path end
  local norm = path:gsub("\\", "/")
  local lower = norm:lower()
  local marker = "oras_extract/"
  local idx = lower:find(marker, 1, true)
  if idx then
    return norm:sub(idx)
  end
  -- Already relative (no drive / root)
  if not norm:match("^[A-Za-z]:") and norm:sub(1, 1) ~= "/" then
    return norm
  end
  return path
end

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

local function readModFile(mod, rel)
  if not (mod and mod.read) then return nil end
  local ok, data = pcall(function() return mod:read(rel) end)
  if ok and type(data) == "string" and data ~= "" then return data end
  return nil
end

-- Read JSON from the LOVE save directory (oras_extract/...) via engine CacheFs.
-- Never call love.filesystem or io from this sandboxed module.
local function loadJsonFile(path)
  if type(path) ~= "string" or path == "" then return nil, "empty_path" end
  local rel = toSaveRel(path)
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okCf and CacheFs and CacheFs.read) then
    return nil, "no_CacheFs"
  end
  -- Extract cache sits at saveDir/oras_extract, not under GameVersion prefix.
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  local data = CacheFs.read(rel)
  CacheFs.prefix = savedPrefix
  if type(data) ~= "string" or data == "" then
    return nil, "missing:" .. tostring(rel)
  end
  local obj = decodeJson(data)
  if type(obj) ~= "table" then
    return nil, "json_fail:" .. tostring(rel)
  end
  return obj, nil
end

function M.loadMeshIndex(mod)
  local raw = readModFile(mod, ".local/mesh_index.json")
  if raw then
    local obj = decodeJson(raw)
    if type(obj) == "table" then return obj end
  end
  -- Fallback: save-dir copy written by extract_oras.py
  local obj = select(1, loadJsonFile("oras_extract/meshes/mesh_index.json"))
  if type(obj) == "table" then return obj end
  return nil
end

local cache = {} -- nat -> { front=canvas/img, back=canvas/img, raw=model }
local voxelCache = {} -- nat -> bundle | false

-- Matches DRAMATIC_SHAPE Voxel3D.FORMAT so BattleScene can Voxel3D.draw us.
local VOXEL_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexShade", "float", 1 },
}

local function projectVertex(x, y, z, cx, cy, cz, yaw, pitch, scale, ox, oy)
  x = x - cx; y = y - cy; z = z - cz
  local cosy, siny = math.cos(yaw), math.sin(yaw)
  local cosp, sinp = math.cos(pitch), math.sin(pitch)
  local xz = x * cosy - z * siny
  local zz = x * siny + z * cosy
  local yy = y * cosp - zz * sinp
  return ox + xz * scale, oy - yy * scale
end

local function grabTex(game, path)
  if not (game and game.grabImage and type(path) == "string") then return nil end
  -- Game3:grabImage rewrites save-dir absolutes itself (real love.filesystem).
  local img = game:grabImage(path)
  if img then return img end
  -- If shiny-pack path (model+3) fails or is missing, try normal pack (model+2).
  local norm = path:gsub("\\", "/")
  local folder = norm:match("/(%d+)/[^/]+$")
  local id = folder and tonumber(folder)
  if id and id >= 1 then
    local alt = norm:gsub("/" .. folder .. "/", "/" .. string.format("%04d", id - 1) .. "/", 1)
    if alt ~= norm then
      img = game:grabImage(alt)
      if img then return img end
    end
  end
  return nil
end

-- Build a LOVE Mesh (triangle list) from one JSON mesh group, projected to 2D.
local function buildLoveMesh(meshData, cam, tex)
  local G = love.graphics
  if not (G and G.newMesh) then return nil end
  local verts = meshData.vertices
  local inds = meshData.indices
  if type(verts) ~= "table" or type(inds) ~= "table" or #inds < 3 then return nil end
  local cx, cy, cz = cam.cx, cam.cy, cam.cz
  local yaw, pitch, scale = cam.yaw, cam.pitch, cam.scale
  local ox, oy = cam.ox, cam.oy
  local out = {}
  for i = 1, #inds do
    local vi = inds[i]
    local o = vi * 5
    -- Exporter writes flat arrays; indices are 0-based vertex indices.
    local x = verts[o + 1]
    local y = verts[o + 2]
    local z = verts[o + 3]
    local u = verts[o + 4]
    local v = verts[o + 5]
    if x and y and z then
      local sx, sy = projectVertex(x, y, z, cx, cy, cz, yaw, pitch, scale, ox, oy)
      -- LOVE Mesh UV: V flipped vs OpenGL-ish; ORAS V is OpenGL style (0 bottom)
      do local vv = (tonumber(v) or 0); local vf = vv - math.floor(vv); out[#out + 1] = { sx, sy, u or 0, 1 - vf } end
    end
  end
  if #out < 3 then return nil end
  local ok, mesh = pcall(G.newMesh, out, "triangles", "static")
  if not (ok and mesh) then return nil end
  if tex and mesh.setTexture then mesh:setTexture(tex) end
  return mesh
end

local function makeCamera(model, which, slot)
  slot = slot or 64
  local bmin = model.bounds_min or { -1, -1, -1 }
  local bmax = model.bounds_max or { 1, 1, 1 }
  local cx = (bmin[1] + bmax[1]) * 0.5
  local cy = (bmin[2] + bmax[2]) * 0.5
  local cz = (bmin[3] + bmax[3]) * 0.5
  local ext = math.max(
    (bmax[1] - bmin[1]),
    (bmax[2] - bmin[2]),
    (bmax[3] - bmin[3]),
    1e-3
  )
  local yaw = (which == "back") and math.rad(200) or math.rad(35)
  local pitch = math.rad(-8)
  local scale = (slot * 0.42) / (ext * 0.5)
  return {
    cx = cx, cy = cy, cz = cz,
    yaw = yaw, pitch = pitch, scale = scale,
    ox = slot * 0.5, oy = slot * 0.55,
    slot = slot,
  }
end

function M.bakeBattleCanvas(game, model, which)
  local G = love.graphics
  if not (G and G.newCanvas) then return nil, "no_canvas" end
  local slot = 96
  local cam = makeCamera(model, which, slot)
  local ok, canvas = pcall(G.newCanvas, slot, slot)
  if not (ok and canvas) then return nil, "canvas_fail" end
  local meshes = model.meshes
  if type(meshes) ~= "table" then
    if canvas.release then pcall(function() canvas:release() end) end
    return nil, "no_meshes"
  end

  local prev = G.getCanvas and G.getCanvas()
  G.setCanvas(canvas)
  G.clear(0, 0, 0, 0)
  G.setColor(1, 1, 1, 1)

  local drawn = 0
  for i = 1, #meshes do
    local md = meshes[i]
    if type(md) == "table" and not tostring(md.name or ""):find("OpenMouth", 1, true) then
      local tex = grabTex(game, md.texture_path)
      local loveMesh = buildLoveMesh(md, cam, tex)
      if loveMesh then
        G.draw(loveMesh)
        drawn = drawn + 1
        if loveMesh.release then pcall(function() loveMesh:release() end) end
      end
    end
  end
  G.setCanvas(prev)
  if drawn < 1 then
    if canvas.release then pcall(function() canvas:release() end) end
    return nil, "draw_zero"
  end
  if canvas.setFilter then canvas:setFilter("linear", "linear") end
  return canvas, nil
end

local function indexRow(index, national)
  if not (index and index.by_national) then return nil end
  local key = tostring(national)
  local row = index.by_national[key] or index.by_national[national]
  return row, key
end

local function noteMiss(national, which, reason)
  local k = tostring(national) .. ":" .. tostring(which)
  if missLog[k] then return end
  missLog[k] = true
  logInfo("ORAS mesh MISS nat=%s which=%s reason=%s", tostring(national), tostring(which), tostring(reason))
end

local function noteHit(national, which, pathKind)
  local kind = pathKind or "baked_2d"
  local k = tostring(national) .. ":" .. tostring(which) .. ":" .. kind
  if hitLog[k] then return end
  hitLog[k] = true
  logInfo("ORAS mesh HIT nat=%s which=%s path=%s", tostring(national), tostring(which), kind)
end

function M.noteHit3D(national, which)
  noteHit(national, which or "front", "voxel_3d")
end


-- Skip OpenMouth extras and empty groups (same filter as bakeBattleCanvas).
local function meshGroupOk(md)
  if type(md) ~= "table" then return false end
  if tostring(md.name or ""):find("OpenMouth", 1, true) then return false end
  local verts, inds = md.vertices, md.indices
  return type(verts) == "table" and type(inds) == "table" and #inds >= 3
end

-- Build Voxel3D-format LOVE meshes from one model JSON (true 3D, not projected).
function M.buildVoxelParts(game, model)
  local G = love and love.graphics
  if not (G and G.newMesh) then return nil, "no_newMesh" end
  local meshes = model and model.meshes
  if type(meshes) ~= "table" then return nil, "no_meshes" end
  local parts = {}
  for i = 1, #meshes do
    local md = meshes[i]
    if meshGroupOk(md) then
      md = remapBodySheetTexture(md)
      local verts, inds = md.vertices, md.indices
      local out = {}
      -- Exporter: flat x,y,z,u,v per vertex; indices 0-based.
      local vcount = math.floor(#verts / 5)
      for vi = 0, vcount - 1 do
        local o = vi * 5
        local x, y, z = verts[o + 1], verts[o + 2], verts[o + 3]
        local u, v = verts[o + 4] or 0, verts[o + 5] or 0
        if x and y and z then
          -- Fold multi-sheet atlas V into [0,1]. Eye/Mouth/Iris skip LOVE
          -- flip (open frames at high frac V); Body keeps the flip.
          local vf = (tonumber(v) or 0) - math.floor(tonumber(v) or 0)
          local sh = tostring(md.material_shader or "")
          local face = sh:find("Eye", 1, true) or sh:find("Mouth", 1, true)
            or sh:find("Iris", 1, true)
          local vv = face and vf or (1 - vf)
          out[#out + 1] = { x, y, z, u, vv, 1 }
        end
      end
      if #out >= 3 then
        local map = {}
        for j = 1, #inds do
          local idx = inds[j]
          if type(idx) == "number" then
            map[#map + 1] = idx + 1 -- LOVE vertex map is 1-based
          end
        end
        local ok, loveMesh = pcall(G.newMesh, VOXEL_FORMAT, out, "triangles", "static")
        if ok and loveMesh then
          if #map > 0 then pcall(loveMesh.setVertexMap, loveMesh, map) end
          local tex = grabTex(game, md.texture_path)
          if tex and tex.setWrap then pcall(tex.setWrap, tex, "repeat", "repeat") end
          if tex and loveMesh.setTexture then loveMesh:setTexture(tex) end
          parts[#parts + 1] = {
            mesh = loveMesh,
            tex = tex,
            name = md.name,
            texture_path = toSaveRel(md.texture_path),
          }
        end
      end
    end
  end
  if #parts < 1 then return nil, "draw_zero" end
  return parts, nil
end

local function modelMetrics(model)
  local bmin = model.bounds_min or { -1, 0, -1 }
  local bmax = model.bounds_max or { 1, 1, 1 }
  local height = math.max((bmax[2] or 1) - (bmin[2] or 0), 1e-3)
  local floor = bmin[2] or 0
  return height, floor, bmin, bmax
end

-- Load + cache true-3D mesh parts for a national dex number.
function M.ensureIndex(mod)
  if type(M._index) == "table" and type(M._index.by_national) == "table" then
    return M._index, nil
  end
  local index = M.loadMeshIndex(mod or M._mod)
  if type(index) == "table" and type(index.by_national) == "table" then
    M._index = index
    return index, nil
  end
  return nil, "no_index"
end

-- Raw mesh groups + metrics (no LOVE Mesh). DRAMATIC_SHAPE builds GPU meshes.
function M.getVoxelSource(national)
  national = tonumber(national)
  if not national then return nil, "bad_national" end
  local index = select(1, M.ensureIndex(M._mod))
  local row = indexRow(index, national)
  if not row then return nil, "no_index_row" end
  local model, loadErr = nil, nil
  if type(row.mesh_rel) == "string" and row.mesh_rel ~= "" then
    model, loadErr = loadJsonFile("oras_extract/meshes/" .. row.mesh_rel:gsub("\\", "/"))
  end
  if not model and type(row.front) == "string" then
    model, loadErr = loadJsonFile(row.front)
  end
  if type(model) ~= "table" or type(model.meshes) ~= "table" then
    return nil, loadErr or "bad_model"
  end
  local groups = {}
  local meshes = model.meshes
  -- Safe selective wait: only meshes with wait_pose.safe use posed verts.
  local waitPose = (type(model.wait_pose) == "table" and model.wait_pose.safe ~= false)
    and model.wait_pose or nil
  for i = 1, #meshes do
    local md = meshes[i]
    if meshGroupOk(md) then
      md = remapBodySheetTexture(md)
      local disp
      if waitPose then
        disp = (type(md.posed_vertices) == "table" and #md.posed_vertices >= 5 and md.posed_vertices)
          or md.vertices
      else
        disp = (type(md.bind_vertices) == "table" and #md.bind_vertices >= 5 and md.bind_vertices)
          or md.vertices
      end
      groups[#groups + 1] = {
        name = md.name,
        material_shader = md.material_shader,
        texture = md.texture,
        vertices = disp,
        indices = md.indices,
        texture_path = toSaveRel(md.texture_path),
        local_vertices = md.local_vertices,
        bone_indices = md.bone_indices,
        bone_weights = md.bone_weights,
        skinning_mode = md.skinning_mode,
        influences = md.influences,
        wait_loop_xyz = nil,  -- never export; vertex-lerp spike soup
        wait_loop_us = nil,
        bind_vertices = md.bind_vertices,
        posed_vertices = waitPose and (md.posed_vertices or md.vertices) or nil,
      }
    end
  end
  if #groups < 1 then return nil, "no_groups" end
  local height, floor, bmin, bmax = modelMetrics(model)
  -- Prefer AABB of selected display verts when wait is safe.
  if waitPose then
    local xs, ys, zs = {}, {}, {}
    for gi = 1, #groups do
      local gv = groups[gi].vertices
      if type(gv) == "table" then
        for vi = 1, #gv - 2, 5 do
          xs[#xs + 1] = gv[vi]
          ys[#ys + 1] = gv[vi + 1]
          zs[#zs + 1] = gv[vi + 2]
        end
      end
    end
    if #xs > 0 then
      local function amin(t)
        local m = t[1]
        for i = 2, #t do if t[i] < m then m = t[i] end end
        return m
      end
      local function amax(t)
        local m = t[1]
        for i = 2, #t do if t[i] > m then m = t[i] end end
        return m
      end
      bmin = { amin(xs), amin(ys), amin(zs) }
      bmax = { amax(xs), amax(ys), amax(zs) }
      height = math.max((bmax[2] or 1) - (bmin[2] or 0), 1e-3)
      floor = bmin[2] or 0
    end
  end
  local has_skin = type(model.bones) == "table" and #model.bones > 0
  return {
    national = national,
    groups = groups,
    bones = has_skin and model.bones or nil,
    bone_count = has_skin and (model.bone_count or #model.bones) or nil,
    phase = model.phase,
    height = height,
    floor = floor,
    bounds_min = bmin,
    bounds_max = bmax,
    name = model.name or row.name,
    wait_pose = waitPose,
    source_class = (waitPose and "oras_mesh_wait_posed")
      or (has_skin and "oras_mesh_phase2_voxel_source")
      or "oras_mesh_phase1_voxel_source",
  }, nil
end

function M.getVoxelBundle(game, national)
  national = tonumber(national)
  if not national then return nil, "bad_national" end
  local key = tostring(national)
  if voxelCache[key] ~= nil then
    if voxelCache[key] then return voxelCache[key], nil end
    return nil, "cached_miss"
  end
  M.ensureIndex(M._mod)
  local index = M._index
  local row = indexRow(index, national)
  if not row then
    voxelCache[key] = false
    return nil, "no_index_row"
  end
  local model, loadErr = nil, nil
  if type(row.mesh_rel) == "string" and row.mesh_rel ~= "" then
    model, loadErr = loadJsonFile("oras_extract/meshes/" .. row.mesh_rel:gsub("\\", "/"))
  end
  if not model and type(row.front) == "string" then
    model, loadErr = loadJsonFile(row.front)
  end
  if type(model) ~= "table" or type(model.meshes) ~= "table" then
    voxelCache[key] = false
    return nil, loadErr or "bad_model"
  end
  local parts, buildErr = M.buildVoxelParts(game, model)
  if not parts then
    voxelCache[key] = false
    return nil, buildErr or "build_fail"
  end
  local height, floor, bmin, bmax = modelMetrics(model)
  local bundle = {
    national = national,
    parts = parts,
    height = height,
    floor = floor,
    bounds_min = bmin,
    bounds_max = bmax,
    name = model.name or row.name,
    source_class = "oras_mesh_phase1_voxel",
  }
  voxelCache[key] = bundle
  return bundle, nil
end

function M.clearVoxelCache()
  for _, bundle in pairs(voxelCache) do
    if type(bundle) == "table" and type(bundle.parts) == "table" then
      for _, part in ipairs(bundle.parts) do
        if part.mesh and part.mesh.release then
          pcall(function() part.mesh:release() end)
        end
      end
    end
  end
  voxelCache = {}
end

-- Public API consumed by DRAMATIC_SHAPE OrasModels adapter.
function M.exportApi()
  return {
    apiVersion = 2,
    source = "oras_models",
    hasIndex = function()
      M.ensureIndex(M._mod)
      return type(M._index) == "table" and type(M._index.by_national) == "table"
    end,
    getVoxelSource = function(national)
      return M.getVoxelSource(national)
    end,
    getVoxelBundle = function(game, national)
      return M.getVoxelBundle(game, national)
    end,
    noteHit3D = function(national, which)
      M.noteHit3D(national, which)
    end,
    clearCache = function()
      M.clearVoxelCache()
    end,
    ensureIndex = function(mod)
      return M.ensureIndex(mod or M._mod)
    end,
  }
end

function M.getBattleVisual(game, national, which)
  national = tonumber(national)
  if not national then return nil, "bad_national" end
  which = which or "front"
  local key = tostring(national)
  cache[key] = cache[key] or {}
  if cache[key][which] ~= nil then
    if cache[key][which] then
      return cache[key][which], nil
    end
    return nil, "cached_miss"
  end
  local index = M._index
  local row = indexRow(index, national)
  if not row then
    cache[key][which] = false
    return nil, "no_index_row"
  end
  local model, loadErr = nil, nil
  if type(row.mesh_rel) == "string" and row.mesh_rel ~= "" then
    model, loadErr = loadJsonFile("oras_extract/meshes/" .. row.mesh_rel:gsub("\\", "/"))
  end
  if not model and type(row.front) == "string" then
    model, loadErr = loadJsonFile(row.front)
  end
  if type(model) ~= "table" or type(model.meshes) ~= "table" then
    cache[key][which] = false
    return nil, loadErr or "bad_model"
  end
  local canvas, bakeErr = M.bakeBattleCanvas(game, model, which)
  cache[key][which] = canvas or false
  if not canvas then
    return nil, bakeErr or "bake_fail"
  end
  return canvas, nil
end

-- OPTIONAL 2D UI bake. Off by default: ORAS 3D is additive via DramaticShapes
-- OrasModels (voxel meshes). Replacing Game3:drawBattlePic with Body-UV
-- projected canvases is what mangled stock GBA battle sprites in menus /
-- flat battles. Keep stock drawBattlePic pristine unless opts.bake2dUi.
function M.installDrawBattlePicHook(mod, meshIndex, enabled)
  M._index = meshIndex
  M._log = mod and mod.log or M._log
  local ok, Game3 = pcall(require, "src.core.Game3")
  if not ok or type(Game3) ~= "table" or type(Game3.drawBattlePic) ~= "function" then
    return false, "Game3.drawBattlePic unavailable"
  end
  if enabled == nil then enabled = false end
  Game3._orasMeshIndex = meshIndex
  Game3._orasMeshDrawEnabled = enabled and true or false
  M._index = meshIndex
  if Game3._orasMeshDrawWrapped then
    return true, enabled and "refreshed" or "disabled"
  end
  -- Even when disabled we wrap once so a later opt-in can flip the flag
  -- without restacking hooks. Default path always calls stock GBA draw.
  local orig = Game3.drawBattlePic
  Game3._orasMeshDrawOrig = orig
  function Game3:drawBattlePic(species, which, x, y, scale, drop, flash, shiny)
    if not Game3._orasMeshDrawEnabled then
      return orig(self, species, which, x, y, scale, drop, flash, shiny)
    end
    scale = scale or 1
    drop = drop or 0
    local nat = nil
    if self.nationalDexOf then
      local ok2, n = pcall(function() return self:nationalDexOf(species) end)
      if ok2 then nat = tonumber(n) end
    end
    if not nat then
      local pack = self.data and self.data.pokemon
      local row = pack and pack.byIndex and pack.byIndex[species]
      nat = row and tonumber(row.nationalDex) or tonumber(species)
    end
    local canvas, reason = nil, "no_nat"
    if nat then
      local okV, a, b = pcall(M.getBattleVisual, self, nat, which or "front")
      if okV then
        canvas, reason = a, b
      else
        reason = "pcall:" .. tostring(a)
        canvas = nil
      end
    end
    if canvas then
      noteHit(nat, which or "front", "baked_2d")
      local G = love.graphics
      if flash then G.setColor(1, 1, 1, 0.45) else G.setColor(1, 1, 1, 1) end
      local iw = canvas:getDimensions()
      -- Fit ~64px Gen3 slot: canvas is 96; scale so width ~64*scale
      local fit = (64 / iw) * scale
      G.draw(canvas, x, y + drop, 0, fit, fit)
      return
    end
    if nat then
      noteMiss(nat, which or "front", reason or "unknown")
    else
      noteMiss(tostring(species), which or "front", "species_to_national_failed")
    end
    -- Fallback: untouched stock GBA / ROM-extracted battle pic.
    return orig(self, species, which, x, y, scale, drop, flash, shiny)
  end
  Game3._orasMeshDrawWrapped = true
  return true, nil
end

function M.disableDrawBattlePicHook()
  local ok, Game3 = pcall(require, "src.core.Game3")
  if ok and type(Game3) == "table" then
    Game3._orasMeshDrawEnabled = false
  end
  -- Drop baked canvases so we do not keep Body-UV projections around.
  cache = {}
  return true
end

function M.applyMeshes(mod, status, opts)
  opts = opts or {}
  M._mod = mod or M._mod
  M._log = mod and mod.log or M._log
  missLog = {}
  hitLog = {}
  local index = M.loadMeshIndex(mod)
  if type(index) ~= "table" then
    return 0, "no mesh_index.json — run extract_oras.py --extract-meshes"
  end
  local n = tonumber(index.model_count) or 0
  local byNat = index.by_national or {}
  local natN = 0
  for _ in pairs(byNat) do natN = natN + 1 end
  -- Default bake2dUi=false: stock GBA drawBattlePic stays pristine.
  -- DramaticShapes OrasModels consumes exportApi() for true 3D overlays.
  local bake2d = opts.bake2dUi == true
  local hooked, err = M.installDrawBattlePicHook(mod, index, bake2d)
  -- Clear bake + voxel caches on re-apply
  cache = {}
  M.clearVoxelCache()
  -- Boot probe: confirm CacheFs can see Torchic mesh (sandbox-safe).
  local probeRel = "oras_extract/meshes/a/0/0/8/2827/mesh.json"
  local probeRow = byNat["255"] or byNat[255]
  if probeRow and type(probeRow.mesh_rel) == "string" then
    probeRel = "oras_extract/meshes/" .. probeRow.mesh_rel:gsub("\\", "/")
  end
  local probeObj, probeErr = loadJsonFile(probeRel)
  if probeObj then
    logInfo("ORAS mesh probe OK rel=%s meshes=%s", probeRel, tostring(probeObj.mesh_count or (probeObj.meshes and #probeObj.meshes)))
  else
    logWarn("ORAS mesh probe FAIL rel=%s reason=%s", probeRel, tostring(probeErr))
  end
  return natN, nil, {
    modelCount = n,
    nationalCount = natN,
    drawHook = hooked and true or false,
    drawHookErr = err,
    bake2dUi = bake2d and true or false,
    phase = index.phase or "1_static_posed",
    sampleNat = byNat["255"] and 255 or (byNat["265"] and 265 or nil),
    probeOk = probeObj ~= nil,
    probeErr = probeErr,
    voxelApi = true,
    note = bake2d and "2D UI bake ON (replaces drawBattlePic)"
      or "voxel API only; stock GBA drawBattlePic untouched",
  }
end

return M
