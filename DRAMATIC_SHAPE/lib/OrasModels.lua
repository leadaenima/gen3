-- ORAS BCH battler meshes as real 3D geometry in the voxel battle camera.
--
-- Parallel to StadiumModels: BattleScene asks for placements per side and
-- skips the Gen3/Gen5 sprite billboard when a placement is present. Meshes
-- are built HERE (DramaticShapes / engine_internals) from raw vertex groups
-- exported by oras_models -- GPU Mesh creation stays out of that mod's
-- lighter sandbox. Falls back to exports.meshes.getVoxelBundle when present.
--
-- Idle / battle motion: PBJ GF1Motion tracks in AppData oras_extract/anims/
-- (see OrasPbjAnim). SAFE wait-pose display (2026-09-14): only nationals whose
-- offline waitA bake passed MAX_SPAN_RATIO get posed verts. Failures (Rayquaza
-- etc.) keep bind + elong_tip_horiz + procedural idle. No wait_loop vertex-lerp.
-- Runtime LOVE skin stays OFF (ENABLE_SKINNING=false).

local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local BattleArt = V.require("BattleArt")
local BattleBillboard = V.require("BattleBillboard")
local OrasPbjAnim = V.require("OrasPbjAnim")

local OrasModels = {}

local providerHandle, meshApi
local actors = { player = {}, enemy = {} }
local warned = {}
local drawLogAt = { player = 0, enemy = 0 }

OrasModels.REF_MODEL_H = 120
OrasModels.REF_WORLD_H = 14
-- Elongated / serpentine AABB heuristic (Rayquaza, Milotic, Seviper, etc.):
-- height-fit on a Y-long bind AABB stands them as rigid poles. Tip the long
-- axis toward horizontal (~ORAS battle S-curve / floating serpent), then
-- uniform-fit on the post-tip silhouette. Aspect heuristic is primary;
-- ELONG_VERTICAL_NATS is an optional borderline supplement (not 384-only).
OrasModels.ELONG_ASPECT = 2.5
OrasModels.ELONG_TIP_ASPECT_MIN = 2.0  -- allowlist may tip only at/above this
OrasModels.ELONG_TIP_DEG = 78         -- rotateX; length runs along depth
OrasModels.ELONG_TIP_WORLD_H_MAX = 18
OrasModels.ELONG_TIP_LEN_MAX = 40     -- body length along depth (world)
OrasModels.ELONG_TIP_FLOAT = 0.14     -- fraction of post-tip height above ground
OrasModels.ELONG_HORIZ_WORLD_MAX = 48
OrasModels.ELONG_VERTICAL_NATS = {
  [95] = true, [147] = true, [148] = true, [149] = true,
  [206] = true, [336] = true, [350] = true, [367] = true,
  [368] = true, [384] = true, [445] = true, [606] = true,
  [706] = true, [718] = true,
}
OrasModels.PULL = BattleBillboard.PULL or 1.5

-- Procedural idle (whole-mesh). Tuned subtle so it reads as alive without
-- fighting the battle camera. Real PBJ skeletal wait would replace this.
OrasModels.IDLE_SOURCE = "procedural"
OrasModels.BATTLE_ANIM_SOURCE = "procedural_battle"
OrasModels.PBJ_ANIM_SOURCE = "pbj_gf1_root"
OrasModels.PBJ_IDLE_SOURCE = "pbj_gf1_wait"
OrasModels.PBJ_SKINNED_SOURCE = "pbj_gf1_skinned"
-- Runtime per-vertex skin is OFF by default: LOVE path still morphs.
-- Wait display ON only for meshes that carry wait_pose.safe from the baker;
-- failures keep bind verts. wait_loop vertex-lerp stays OFF (spike soup).
-- Do NOT flip ENABLE_SKINNING / ENABLE_WAIT_LOOP without proving on device.
OrasModels.ENABLE_SKINNING = false
OrasModels.ENABLE_WAIT_POSE_DISPLAY = true
OrasModels.ENABLE_WAIT_LOOP = false
OrasModels.WAIT_LOOP_SOURCE = "pbj_gf1_wait_loop"
OrasModels.WAIT_LOOP_HZ = 0.32  -- ~3s cycle; matches typical waitA length
OrasModels.IDLE_BREATHE_HZ = 0.42
OrasModels.IDLE_SWAY_HZ = 0.31
OrasModels.IDLE_BREATHE_AMP = 0.018   -- Y-scale +/- 
OrasModels.IDLE_BOB_FRAC = 0.012     -- of model height
OrasModels.IDLE_LEAN_RAD = 0.028     -- rotateX lean
OrasModels.IDLE_SWAY_RAD = 0.022     -- rotateY sway

-- Event-driven procedural battle clips (seconds).
OrasModels.ATK_DUR = 0.55
OrasModels.DMG_DUR = 0.45
OrasModels.FAINT_DUR = 0.95
OrasModels.LAND_DUR = 0.7

local VOXEL_FORMAT = Voxel3D.FORMAT or {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexShade", "float", 1 },
}

local function diag(line)
  local msg = tostring(line or "")
  local log = V.mod and V.mod.log
  if log and log.info then pcall(log.info, log, "%s", msg) end
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okCf and CacheFs and CacheFs.read and CacheFs.write) then return end
  local saved = CacheFs.prefix
  CacheFs.prefix = ""
  local prev = CacheFs.read("oras_extract/voxel_3d_diag.log") or ""
  if #prev > 120000 then prev = prev:sub(-60000) end
  local stamp = os.date and os.date("%H:%M:%S") or "?"
  CacheFs.write("oras_extract/voxel_3d_diag.log",
    prev .. stamp .. " " .. msg .. "\n")
  CacheFs.prefix = saved
end

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  diag("WARN " .. tostring(message))
  local log = V.mod and V.mod.log
  if log and log.warn then pcall(log.warn, log, "%s", tostring(message)) end
end

local function infoOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  diag("INFO " .. tostring(message))
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

local function cacheFsRead(rel)
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okCf and CacheFs and CacheFs.read) then return nil, "no_CacheFs" end
  local saved = CacheFs.prefix
  CacheFs.prefix = ""
  local data = CacheFs.read(rel)
  CacheFs.prefix = saved
  if type(data) ~= "string" or data == "" then
    return nil, "missing:" .. tostring(rel)
  end
  return data, nil
end

local function cacheFsJson(rel)
  local data, err = cacheFsRead(rel)
  if not data then return nil, err end
  local obj = decodeJson(data)
  if type(obj) ~= "table" then return nil, "json_fail:" .. tostring(rel) end
  return obj, nil
end

local _meshIndex
local function loadMeshIndexLocal()
  if type(_meshIndex) == "table" and type(_meshIndex.by_national) == "table" then
    return _meshIndex, nil
  end
  local obj = select(1, cacheFsJson("oras_extract/meshes/mesh_index.json"))
  if type(obj) == "table" and type(obj.by_national) == "table" then
    _meshIndex = obj
    return obj, nil
  end
  return nil, "no_cachefs_index"
end


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

-- BodyB / Body01 shaders and Petal/Flower parts sample Body2 when the shared
-- atlas split is Body1+Body2. Do not key off mesh names like BodyBSkin.
-- True when a texture path is readable (absolute disk or CacheFs save-rel).
local function texturePathExists(path)
  if type(path) ~= "string" or path == "" then return false end
  local norm = path:gsub("\\", "/")
  if norm:match("^[A-Za-z]:") or norm:sub(1, 1) == "/" then
    local f = io.open(path, "rb") or io.open(norm, "rb")
    if f then f:close() return true end
    return false
  end
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if okCf and CacheFs and CacheFs.exists then
    local saved = CacheFs.prefix
    CacheFs.prefix = ""
    local ok = CacheFs.exists(norm) or CacheFs.exists(path)
    CacheFs.prefix = saved
    if ok then return true end
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


--- Safe wait bake writes posed verts + wait_pose; failures leave bind in vertices.
--- When wait display is off, always prefer bind_vertices.
local function displayVertsOf(md)
  if type(md) ~= "table" then return nil end
  if not OrasModels.ENABLE_WAIT_POSE_DISPLAY then
    if type(md.bind_vertices) == "table" and #md.bind_vertices >= 5 then
      return md.bind_vertices
    end
    return md.vertices
  end
  -- Prefer explicit posed_vertices from safe bake; else current vertices
  -- (bind for rejects, wait mid for passes).
  if type(md.posed_vertices) == "table" and #md.posed_vertices >= 5 then
    return md.posed_vertices
  end
  return md.vertices
end

local function waitLoopOf(md)
  if not OrasModels.ENABLE_WAIT_LOOP then return nil, nil end
  if type(md) ~= "table" then return nil, nil end
  return md.wait_loop_xyz, md.wait_loop_us
end

local function cloneMd(md, shader, tex, path)
  return {
    name = md.name,
    material_id = md.material_id,
    material_shader = md.material_shader or shader,
    texture = tex,
    texture_path = path,
    vertices = displayVertsOf(md),
    indices = md.indices,
    local_vertices = md.local_vertices,
    bone_indices = md.bone_indices,
    bone_weights = md.bone_weights,
    skinning_mode = md.skinning_mode,
    influences = md.influences,
    wait_loop_xyz = select(1, waitLoopOf(md)),
    wait_loop_us = select(2, waitLoopOf(md)),
    bind_vertices = md.bind_vertices,
    posed_vertices = OrasModels.ENABLE_WAIT_POSE_DISPLAY and md.posed_vertices or nil,
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


local function shaderIsFaceSheet(shader)
  local sh = tostring(shader or "")
  if sh == "" then return false end
  if sh:find("Eye", 1, true) or sh:find("Mouth", 1, true) then return true end
  if sh:find("Iris", 1, true) then return true end
  return false
end

local function loveUv(u, v, shader)
  u = tonumber(u) or 0
  v = tonumber(v) or 0
  local vf = v - math.floor(v)
  if shaderIsFaceSheet(shader) then
    return u, vf
  end
  return u, 1 - vf
end

local function prepareTex(tex)
  if not tex then return nil end
  if tex.setWrap then pcall(tex.setWrap, tex, "repeat", "repeat") end
  return tex
end

local function toSaveRel(path)
  if type(path) ~= "string" or path == "" then return path end
  local norm = path:gsub("\\", "/")
  local lower = norm:lower()
  local marker = "oras_extract/"
  local idx = lower:find(marker, 1, true)
  if idx then return norm:sub(idx) end
  if not norm:match("^[A-Za-z]:") and norm:sub(1, 1) ~= "/" then return norm end
  return path
end

local function indexRowLocal(index, national)
  if not (index and index.by_national) then return nil end
  local key = tostring(national)
  return index.by_national[key] or index.by_national[national], key
end

-- Raw species id from Gen1 (.mon.species) or Gen3/Ruby (battler IS the mon).
-- Do NOT run through BattleArt.speciesAlias: that remaps numbers via a
-- national-dex name table and would turn Game3 SPECIES_TORCHIC (280) into
-- the name for national #280, breaking nationalDexOf.
local function rawSpeciesOf(battler)
  if not battler then return nil, "no_battler" end
  if battler.__battleArtTransformed ~= nil then
    return battler.__battleArtTransformed, "transformed"
  end
  if battler.species ~= nil then
    return battler.species, "battler.species"
  end
  if battler.mon and battler.mon.species ~= nil then
    return battler.mon.species, "mon.species"
  end
  if battler.pokemon and battler.pokemon.species ~= nil then
    return battler.pokemon.species, "pokemon.species"
  end
  return nil, "no_species"
end

local function findMod(id)
  local finder = V.mod and V.mod.find
  if type(finder) ~= "function" then return nil, "no_mod_find" end
  local ok, handle = pcall(finder, id)
  if ok and handle then return handle end
  ok, handle = pcall(finder, V.mod, id)
  if ok and handle then return handle end
  return nil, "find_nil:" .. tostring(id)
end

local function connect()
  if meshApi and (type(meshApi.getVoxelSource) == "function"
      or type(meshApi.getVoxelBundle) == "function") then
    return meshApi
  end
  local handle, why = findMod("oras_models")
  local candidate = nil
  if handle then
    local exports = handle.exports
    candidate = type(exports) == "table" and exports.meshes or nil
  end
  -- Bridge: shared package.loaded table if mod find / exports flaky.
  if type(candidate) ~= "table" then
    local pl = package and package.loaded
    local bridge = pl and (pl["oras_models.meshes"] or pl["oras_models.exports.meshes"])
    if type(bridge) == "table" then candidate = bridge end
  end
  if type(candidate) ~= "table" then
    warnOnce("connect:nomesh",
      "ORAS connect fail: exports.meshes nil (" .. tostring(why or "no_handle")
        .. "); CacheFs dual-path still available")
    return nil
  end
  local ver = tonumber(candidate.apiVersion) or 0
  if ver < 1 then
    warnOnce("connect:api", "ORAS connect fail: apiVersion=" .. tostring(ver))
    return nil
  end
  if type(candidate.getVoxelSource) ~= "function"
      and type(candidate.getVoxelBundle) ~= "function" then
    warnOnce("connect:fn", "ORAS connect fail: no getVoxelSource/Bundle")
    return nil
  end
  providerHandle, meshApi = handle, candidate
  infoOnce("connect:ok",
    ("ORAS meshes API connected apiVersion=%s hasSource=%s hasBundle=%s")
      :format(tostring(ver),
        tostring(type(candidate.getVoxelSource) == "function"),
        tostring(type(candidate.getVoxelBundle) == "function")))
  return meshApi
end

function OrasModels.installed()
  return connect() ~= nil
end

local function exportEnabled(exports, name)
  local fn = exports and exports[name]
  if type(fn) ~= "function" then return nil end
  local ok, enabled = pcall(fn)
  if not ok then ok, enabled = pcall(fn, exports) end
  if ok then return enabled end
  return nil
end

function OrasModels.active()
  local api = connect()
  local handle = providerHandle
  local exports = handle and handle.exports or nil
  if exportEnabled(exports, "meshesEnabled") == false then
    return false, "meshesEnabled_off"
  end
  if exportEnabled(exports, "modelsReady") == false then
    -- Still allow CacheFs dual-path if mesh_index is on disk.
    local idx = select(1, loadMeshIndexLocal())
    if type(idx) == "table" then
      return true, "cachefs_despite_modelsReady_false"
    end
    return false, "modelsReady_false"
  end
  if api then
    if type(api.ensureIndex) == "function" then
      pcall(api.ensureIndex)
    end
    if type(api.hasIndex) == "function" then
      local ok, has = pcall(api.hasIndex)
      if ok and not has then
        local idx = select(1, loadMeshIndexLocal())
        if type(idx) ~= "table" then return false, "hasIndex_false" end
        return true, "cachefs_index"
      end
    end
    return true, "ok"
  end
  local idx = select(1, loadMeshIndexLocal())
  if type(idx) == "table" then
    return true, "cachefs_only"
  end
  return false, "no_api_no_cachefs"
end

local function releaseActor(actor)
  if type(actor.parts) == "table" then
    for _, part in ipairs(actor.parts) do
      if part and part.mesh and part.mesh.release and part.owned then
        pcall(function() part.mesh:release() end)
      end
    end
  end
  for key in pairs(actor) do actor[key] = nil end
end

function OrasModels.release()
  releaseActor(actors.player)
  releaseActor(actors.enemy)
  OrasModels.animWasPlaying = false
end

local function safeCall(object, name, ...)
  local fn = object and object[name]
  if type(fn) ~= "function" then return nil end
  local ok, value, extra = pcall(fn, object, ...)
  if not ok then return nil, value end
  return value, extra
end

local function nationalFor(battle, battler)
  local species, speciesHow = rawSpeciesOf(battler)
  if species == nil then
    -- Last-chance: aliased BattleArt path (Gen1/2 name tables).
    local aliased = BattleArt.speciesFor(battler)
    if aliased ~= nil then
      species, speciesHow = aliased, "BattleArt.speciesFor"
    else
      return nil, "no_species"
    end
  end
  local direct = tonumber(battler and (battler.nationalDex or battler.national))
  if direct and direct >= 1 and direct <= 721 then
    return direct, "battler.nationalDex"
  end
  local game = battle and (battle.game or battle._game)
  if not (game and type(game.nationalDexOf) == "function") then
    local okG, Game = pcall(require, "src.core.Game")
    if okG and Game then
      local cands = {
        Game.game, Game.current,
        Game.stack and Game.stack.top and Game.stack:top(),
        Game.overworld and Game.overworld.game,
        Game,
      }
      local top = cands[3]
      if type(top) == "table" then
        cands[#cands + 1] = top.game
        cands[#cands + 1] = top.battle and top or nil
      end
      for i = 1, #cands do
        local g = cands[i]
        if type(g) == "table" and type(g.nationalDexOf) == "function" then
          game = g
          break
        end
      end
    end
  end
  -- Game3:nationalDexOf expects the internal species INDEX, not a dex name.
  if game and game.nationalDexOf then
    local ok, n = pcall(function() return game:nationalDexOf(species) end)
    if ok and tonumber(n) then
      return tonumber(n), "nationalDexOf:" .. tostring(speciesHow)
    end
  end
  local pokemon = (battle and battle.data and battle.data.pokemon)
    or (game and game.data and game.data.pokemon)
  if type(pokemon) == "table" then
    local row = pokemon.byIndex and pokemon.byIndex[species]
    if type(row) == "table" and tonumber(row.nationalDex) then
      return tonumber(row.nationalDex), "byIndex.nationalDex:" .. tostring(speciesHow)
    end
    local def = pokemon[species]
    if type(def) == "table" then
      local n = tonumber(def.nationalDex or def.dex or def.index)
      if n then return n, "pokemon[species]:" .. tostring(speciesHow) end
    end
  end
  local n = tonumber(species)
  -- Gen1/2: species id == national. Gen3 internal ids go well above 386 and
  -- MUST go through nationalDexOf; do not treat a Hoenn species index as nat.
  if n and n >= 1 and n <= 251 then return n, "species_as_nat:" .. tostring(speciesHow) end
  return nil, "unresolved:" .. tostring(species) .. " how=" .. tostring(speciesHow)
end

local function gameOf(battle)
  local candidates = {
    battle and battle.game,
    battle and battle._game,
    V.mod and V.mod.game,
  }
  local okG, Game = pcall(require, "src.core.Game")
  if okG and Game then
    candidates[#candidates + 1] = Game.game
    candidates[#candidates + 1] = Game.current
    local stack = Game.stack
    local top = stack and stack.top and stack:top()
    if top then
      candidates[#candidates + 1] = top.game
      candidates[#candidates + 1] = top
    end
    if Game.overworld then
      candidates[#candidates + 1] = Game.overworld.game
    end
  end
  for i = 1, #candidates do
    local g = candidates[i]
    if type(g) == "table" and type(g.grabImage) == "function" then
      return g
    end
  end
  return nil
end

local function grabTex(game, path)
  if not (game and game.grabImage and type(path) == "string") then return nil end
  local ok, img = pcall(function() return game:grabImage(path) end)
  if ok and img then return img end
  -- Prefer normal albedo pack (folder-1) if shiny sibling path fails.
  local norm = tostring(path):gsub("\\", "/")
  local folder = norm:match("/(%d+)/[^/]+$")
  local id = folder and tonumber(folder)
  if id and id >= 1 then
    local alt = norm:gsub("/" .. folder .. "/", "/" .. string.format("%04d", id - 1) .. "/", 1)
    if alt ~= norm then
      ok, img = pcall(function() return game:grabImage(alt) end)
      if ok and img then return img end
    end
  end
  return nil
end

local function buildPartsFromSource(game, source)
  local G = love and love.graphics
  if not (G and G.newMesh) then return nil, "no_newMesh" end
  local groups = source and source.groups
  if type(groups) ~= "table" then return nil, "no_groups" end
  local parts = {}
  for i = 1, #groups do
    local md = groups[i]
    local verts, inds = md.vertices, md.indices
    if type(verts) == "table" and type(inds) == "table" and #inds >= 3 then
      local out = {}
      local uvs = {}
      local vcount = math.floor(#verts / 5)
      for vi = 0, vcount - 1 do
        local o = vi * 5
        local x, y, z = verts[o + 1], verts[o + 2], verts[o + 3]
        local u, v = verts[o + 4] or 0, verts[o + 5] or 0
        if x and y and z then
          local uu, vv = loveUv(u, v, md.material_shader)
          out[#out + 1] = { x, y, z, uu, vv, 1 }
          uvs[#uvs + 1] = uu
          uvs[#uvs + 1] = vv
        end
      end
      if #out >= 3 then
        local map = {}
        for j = 1, #inds do
          local idx = inds[j]
          if type(idx) == "number" then map[#map + 1] = idx + 1 end
        end
        local hasSkin = type(md.local_vertices) == "table"
          and type(md.bone_indices) == "table"
          and #md.local_vertices >= 3
        local usage = hasSkin and "dynamic" or "static"
        local ok, loveMesh = pcall(G.newMesh, VOXEL_FORMAT, out, "triangles", usage)
        if ok and loveMesh then
          if #map > 0 then pcall(loveMesh.setVertexMap, loveMesh, map) end
          local tex = prepareTex(grabTex(game, md.texture_path))
          if tex and loveMesh.setTexture then loveMesh:setTexture(tex) end
          if not tex then
            warnOnce(("texmiss:%s:%s"):format(tostring(source and source.national), tostring(md.name)),
              ("ORAS tex MISS nat=%s part=%s path=%s"):format(
                tostring(source and source.national), tostring(md.name),
                tostring(md.texture_path)))
          end
          local part = {
            mesh = loveMesh,
            tex = tex,
            name = md.name,
            owned = true,
            uvs = uvs,
            rest_vertices = verts,
            texture_path = md.texture_path,
            wait_loop_xyz = md.wait_loop_xyz,
            wait_loop_us = md.wait_loop_us,
          }
          if hasSkin then
            part.local_vertices = md.local_vertices
            part.bone_indices = md.bone_indices
            part.bone_weights = md.bone_weights
            part.skinning_mode = md.skinning_mode or 1
            part.skinned = true
          end
          parts[#parts + 1] = part
        end
      end
    end
  end
  if #parts < 1 then return nil, "build_zero" end
  return parts, nil
end

local function loadCacheFsSource(nat)
  local index, idxErr = loadMeshIndexLocal()
  if not index then return nil, idxErr or "no_index" end
  local row = indexRowLocal(index, nat)
  if not row then return nil, "no_index_row" end
  local model, loadErr = nil, nil
  if type(row.mesh_rel) == "string" and row.mesh_rel ~= "" then
    model, loadErr = cacheFsJson(
      "oras_extract/meshes/" .. row.mesh_rel:gsub("\\", "/"))
  end
  if not model and type(row.front) == "string" then
    model, loadErr = cacheFsJson(toSaveRel(row.front))
  end
  if type(model) ~= "table" or type(model.meshes) ~= "table" then
    return nil, loadErr or "bad_model"
  end
  local groups = {}
  for i = 1, #model.meshes do
    local md = model.meshes[i]
    if type(md) == "table"
        and not tostring(md.name or ""):find("OpenMouth", 1, true) then
      local verts, inds = md.vertices, md.indices
      if type(verts) == "table" and type(inds) == "table" and #inds >= 3 then
        md = remapBodySheetTexture(md)
        local disp = displayVertsOf(md) or verts
        local loopXyz, loopUs = waitLoopOf(md)
        groups[#groups + 1] = {
          name = md.name,
          material_shader = md.material_shader,
          texture = md.texture,
          vertices = disp,
          indices = inds,
          texture_path = toSaveRel(md.texture_path),
          local_vertices = md.local_vertices,
          bone_indices = md.bone_indices,
          bone_weights = md.bone_weights,
          skinning_mode = md.skinning_mode,
          influences = md.influences,
          wait_loop_xyz = loopXyz,
          wait_loop_us = loopUs,
          bind_vertices = md.bind_vertices,
          posed_vertices = OrasModels.ENABLE_WAIT_POSE_DISPLAY and (md.posed_vertices or verts) or nil,
        }
      end
    end
  end
  if #groups < 1 then return nil, "no_groups" end
  local bmin = model.bounds_min or { -1, 0, -1 }
  local bmax = model.bounds_max or { 1, 1, 1 }
  -- Always derive AABB from selected display verts (safe wait or bind).
  do
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
    end
  end
  local height = math.max((bmax[2] or 1) - (bmin[2] or 0), 1e-3)
  local floor = bmin[2] or 0
  local has_skin = type(model.bones) == "table" and #model.bones > 0
  return {
    national = nat,
    groups = groups,
    bones = has_skin and model.bones or nil,
    bone_count = has_skin and (model.bone_count or #model.bones) or nil,
    phase = model.phase,
    height = height,
    floor = floor,
    bounds_min = bmin,
    bounds_max = bmax,
    name = model.name or row.name,
    wait_pose = (OrasModels.ENABLE_WAIT_POSE_DISPLAY
      and type(model.wait_pose) == "table"
      and model.wait_pose.safe ~= false
      and model.wait_pose) or nil,
    source_class = ((OrasModels.ENABLE_WAIT_POSE_DISPLAY
      and type(model.wait_pose) == "table"
      and model.wait_pose.safe ~= false) and "oras_cachefs_wait_posed")
      or (has_skin and "oras_cachefs_skinned") or "oras_cachefs_source",
  }, nil
end

local function loadBundle(api, game, nat)
  local reasons = {}
  -- Prefer raw source + local GPU build (apiVersion>=2).
  if api and type(api.getVoxelSource) == "function" then
    local ok, source, err = pcall(api.getVoxelSource, nat)
    if not ok then
      reasons[#reasons + 1] = "pcall_source:" .. tostring(source)
    elseif type(source) == "table" and type(source.groups) == "table" then
      local parts, buildErr = buildPartsFromSource(game, source)
      if parts then
        local hasSkin = type(source.bones) == "table" and #source.bones > 0
        local skinnedParts = 0
        for _, p in ipairs(parts) do
          if p and p.skinned then skinnedParts = skinnedParts + 1 end
        end
        return {
          national = nat,
          parts = parts,
          bones = hasSkin and source.bones or nil,
          bone_count = hasSkin and (source.bone_count or #source.bones) or nil,
          hasSkin = hasSkin and skinnedParts > 0,
          height = source.height,
          floor = source.floor,
          bounds_min = source.bounds_min,
          bounds_max = source.bounds_max,
          name = source.name,
          wait_pose = source.wait_pose,
          source_class = source.source_class or "oras_ds_built",
        }, nil
      end
      reasons[#reasons + 1] = tostring(buildErr or "build_fail")
    else
      reasons[#reasons + 1] = tostring(err or source or "source_nil")
    end
  end
  -- Dual path: read mesh_index + mesh.json from CacheFs directly.
  do
    local source, err = loadCacheFsSource(nat)
    if type(source) == "table" and type(source.groups) == "table" then
      local parts, buildErr = buildPartsFromSource(game, source)
      if parts then
        local hasSkin = type(source.bones) == "table" and #source.bones > 0
        local skinnedParts = 0
        for _, p in ipairs(parts) do
          if p and p.skinned then skinnedParts = skinnedParts + 1 end
        end
        return {
          national = nat,
          parts = parts,
          bones = hasSkin and source.bones or nil,
          bone_count = hasSkin and (source.bone_count or #source.bones) or nil,
          hasSkin = hasSkin and skinnedParts > 0,
          height = source.height,
          floor = source.floor,
          bounds_min = source.bounds_min,
          bounds_max = source.bounds_max,
          name = source.name,
          wait_pose = source.wait_pose,
          source_class = source.source_class or "oras_ds_built",
        }, nil
      end
      reasons[#reasons + 1] = "cachefs_build:" .. tostring(buildErr or "build_fail")
    else
      reasons[#reasons + 1] = "cachefs:" .. tostring(err or "source_nil")
    end
  end
  -- Legacy: provider already built LOVE meshes.
  if api and type(api.getVoxelBundle) == "function" then
    local ok, bundle, err = pcall(api.getVoxelBundle, game, nat)
    if not ok then
      ok, bundle, err = pcall(api.getVoxelBundle, api, game, nat)
      if not ok then
        reasons[#reasons + 1] = "pcall_bundle:" .. tostring(bundle)
        return nil, table.concat(reasons, "|")
      end
    end
    if type(bundle) == "table" and type(bundle.parts) == "table" then
      return bundle, nil
    end
    reasons[#reasons + 1] = tostring(err or "bundle_nil")
  end
  if #reasons < 1 then reasons[1] = "no_voxel_api" end
  return nil, table.concat(reasons, "|")
end

local function skinAllowed()
  return OrasModels.ENABLE_SKINNING and true or false
end

--- Rebuild LOVE mesh verts from bind-pose rest_vertices (x,y,z,u,v flat).
local function restoreBindPose(actor)
  if not (actor and actor.bundle and actor.bundle.parts) then return false end
  local parts = actor.bundle.parts
  local restored = 0
  for i = 1, #parts do
    local part = parts[i]
    local verts = part and part.rest_vertices
    if part and part.mesh and type(verts) == "table" and #verts >= 5 then
      local vcount = math.floor(#verts / 5)
      local out = {}
      for vi = 0, vcount - 1 do
        local o = vi * 5
        local x, y, z = verts[o + 1], verts[o + 2], verts[o + 3]
        local u, v = verts[o + 4] or 0, verts[o + 5] or 0
        local uu, vv = loveUv(u, v)
        out[vi + 1] = { x, y, z, uu, vv, 1 }
      end
      local ok = pcall(function()
        part.mesh:setVertices(out)
        if part.tex and part.mesh.setTexture then
          part.mesh:setTexture(part.tex)
        end
      end)
      if ok then restored = restored + 1 end
    end
  end
  if restored > 0 then actor._skinApplied = false end
  return restored > 0
end

local function battleBag(battle)
  -- Ruby keeps the fight in game.battle while the stack top is still the
  -- overworld proxy. Prefer the live bag when the outer table has no mons.
  if type(battle) ~= "table" then return battle end
  local inner = battle.battle
  if type(inner) == "table" and (inner.player or inner.enemy)
      and not (battle.player and (battle.player.species or (battle.player.mon and battle.player.mon.species))) then
    return inner
  end
  return battle
end

local function syncSide(battle, side)
  local actor = actors[side]
  battle = battleBag(battle)
  local battler = battle and battle[side]
  local nat, natHow = nationalFor(battle, battler)
  if actor.bundle and actor.battler == battler and actor.national == nat then
    return actor
  end
  if actor.failedBattler == battler and actor.failedNational == nat
      and actor.failedWhy then
    return actor
  end

  releaseActor(actor)
  actor.battler, actor.national = battler, nat
  local rawSp, rawHow = rawSpeciesOf(battler)
  diag(("ORAS place attempt side=%s nat=%s how=%s battler=%s rawSpecies=%s rawHow=%s")
    :format(side, tostring(nat), tostring(natHow), tostring(battler ~= nil),
      tostring(rawSp), tostring(rawHow)))
  if not (battler and nat) then
    actor.failedBattler, actor.failedNational = battler, nat
    actor.failedWhy = "no_nat:" .. tostring(natHow)
    -- Always log (not warnOnce) so every failed place attempt is visible.
    diag(("ORAS %s place FAIL reason=no_nat how=%s rawSpecies=%s")
      :format(side, tostring(natHow), tostring(rawSp)))
    return actor
  end

  local api = connect()
  local game = gameOf(battle)
  local bundle, err = loadBundle(api, game, nat)
  if type(bundle) ~= "table" or type(bundle.parts) ~= "table" or #bundle.parts < 1 then
    actor.failedBattler, actor.failedNational = battler, nat
    actor.failedWhy = tostring(err)
    diag(("ORAS %s place FAIL nat=%s reason=%s; Gen3 billboard kept")
      :format(side, tostring(nat), tostring(err)))
    return actor
  end
  actor.bundle = bundle
  actor.failedWhy = nil
  actor.animSource = OrasModels.IDLE_SOURCE
  actor.idlePhase = actor.idlePhase or ((side == "enemy") and 1.7 or 0.0)
  actor.idleTime = actor.idleTime or actor.idlePhase
  actor.battleAnim = nil
  actor.lastGrow = false
  actor.lastFainted = false
  actor.lastPicKind = nil
  actor.lastMoveAnim = nil
  actor.lastHp = nil
  actor.context = "idle"
  bundle.anim_source = actor.animSource
  -- Safe default: never start on pbj_gf1_skinned (morphs). Keep bind-pose
  -- mesh; battle clips use pbj_gf1_root / procedural until ENABLE_SKINNING.
  if bundle.hasSkin and skinAllowed() then
    actor.animSource = OrasModels.PBJ_SKINNED_SOURCE
    bundle.anim_source = actor.animSource
  elseif bundle.hasSkin then
    restoreBindPose(actor)
    actor._bindPoseRestored = true
    actor._skinApplied = false
    diag(("ORAS skin SAFE side=%s nat=%s -> wait_pose bake + non-skinned anim (ENABLE_SKINNING=false)")
      :format(side, tostring(nat)))
  end
  do
    local texBound, texMiss = 0, 0
    for _, p in ipairs(bundle.parts) do
      if p and p.tex then texBound = texBound + 1 else texMiss = texMiss + 1 end
    end
    diag(("ORAS place OK side=%s nat=%s parts=%s class=%s path=voxel_3d anim=%s skin=%s bones=%s skinning=%s texBound=%s texMiss=%s")
      :format(side, tostring(nat), tostring(#bundle.parts),
        tostring(bundle.source_class), tostring(actor.animSource),
        tostring(bundle.hasSkin and true or false),
        tostring(bundle.bone_count or 0),
        tostring(skinAllowed()),
        tostring(texBound), tostring(texMiss)))
  end
  -- Game3 has no growInScale; request land once updatePresentation can call
  -- startBattleAnim (defined later in this file — Lua local scoping).
  actor.pendingLand = true
  if api and type(api.noteHit3D) == "function" then
    pcall(api.noteHit3D, nat, side == "player" and "back" or "front")
  end
  return actor
end

function OrasModels.sync(battle)
  local on, why = OrasModels.active()
  if not on then
    warnOnce("active:" .. tostring(why),
      "ORAS inactive: " .. tostring(why) .. " — Gen3 billboards will draw")
    OrasModels.release()
    return false
  end
  syncSide(battle, "player")
  syncSide(battle, "enemy")
  return true
end

local function nowTime()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

local function actorHasSkin(actor)
  return actor and actor.bundle and actor.bundle.hasSkin
    and type(actor.bundle.bones) == "table" and #actor.bundle.bones > 0
end


--- Cheap idle slither: lerp offline-baked wait_loop_xyz frames (no runtime skin).
local function applyWaitLoopToActor(actor)
  if not OrasModels.ENABLE_WAIT_LOOP then return false end
  if not (actor and actor.bundle and actor.bundle.parts) then return false end
  local parts = actor.bundle.parts
  local hz = OrasModels.WAIT_LOOP_HZ or 0.32
  local phase = tonumber(actor.idlePhase) or 0
  local t = nowTime() + phase
  local cycle = 1 / math.max(hz, 1e-3)
  local u = (t % cycle) / cycle
  local updated = 0
  for i = 1, #parts do
    local part = parts[i]
    local frames = part and part.wait_loop_xyz
    local us = part and part.wait_loop_us
    if part and part.mesh and type(frames) == "table" and #frames >= 2 then
      us = us or { 0, 0.33, 0.66 }
      local i0, i1, frac = 1, 2, 0
      if u <= (us[1] or 0) then
        i0, i1, frac = 1, 1, 0
      elseif u >= (us[#us] or 1) then
        i0, i1 = #us, 1
        local span = 1 - (us[#us] or 0) + (us[1] or 0)
        if span < 1e-6 then frac = 0 else frac = (u - (us[#us] or 0)) / span end
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
      else
        for k = 1, #us - 1 do
          local a, b = us[k], us[k + 1]
          if u >= a and u <= b then
            i0, i1 = k, k + 1
            local span = b - a
            frac = (span > 1e-6) and ((u - a) / span) or 0
            break
          end
        end
      end
      local A, B = frames[i0], frames[i1]
      if type(A) == "table" and type(B) == "table" then
        local uvs = part.uvs
        local vcount = math.floor(#A / 3)
        local verts = {}
        local omt = 1 - frac
        for vi = 0, vcount - 1 do
          local x = (A[vi * 3 + 1] or 0) * omt + (B[vi * 3 + 1] or 0) * frac
          local y = (A[vi * 3 + 2] or 0) * omt + (B[vi * 3 + 2] or 0) * frac
          local z = (A[vi * 3 + 3] or 0) * omt + (B[vi * 3 + 3] or 0) * frac
          local uu = uvs and uvs[vi * 2 + 1] or 0
          local vv = uvs and uvs[vi * 2 + 2] or 0
          verts[vi + 1] = { x, y, z, uu, vv, 1 }
        end
        local ok = pcall(function()
          part.mesh:setVertices(verts)
        end)
        if ok then updated = updated + 1 end
      end
    end
  end
  return updated > 0
end

local function actorHasWaitLoop(actor)
  if not OrasModels.ENABLE_WAIT_LOOP then return false end
  if not (actor and actor.bundle and actor.bundle.parts) then return false end
  for i = 1, #actor.bundle.parts do
    local p = actor.bundle.parts[i]
    if p and type(p.wait_loop_xyz) == "table" and #p.wait_loop_xyz >= 2 then
      return true
    end
  end
  return false
end

local function applySkinToActor(actor, clip, u)
  if not actorHasSkin(actor) then return false end
  if not OrasPbjAnim or not OrasPbjAnim.buildSkinMatrices then return false end
  local pack = OrasPbjAnim.buildSkinMatrices(actor.bundle.bones, clip, u or 0)
  if not pack then return false end
  local parts = actor.bundle.parts
  if type(parts) ~= "table" then return false end
  local updated = 0
  for i = 1, #parts do
    local part = parts[i]
    if part and part.skinned and part.mesh and part.local_vertices then
      local posed = OrasPbjAnim.skinVertices(
        part.local_vertices, part.bone_indices, part.bone_weights,
        pack, part.skinning_mode)
      if posed then
        local uvs = part.uvs
        local vcount = math.floor(#posed / 3)
        local verts = {}
        for vi = 0, vcount - 1 do
          local uu = uvs and uvs[vi * 2 + 1] or 0
          local vv = uvs and uvs[vi * 2 + 2] or 0
          verts[vi + 1] = {
            posed[vi * 3 + 1], posed[vi * 3 + 2], posed[vi * 3 + 3],
            uu, vv, 1,
          }
        end
        local ok = pcall(function()
          part.mesh:setVertices(verts)
        end)
        if ok then updated = updated + 1 end
      end
    end
  end
  return updated > 0
end

local function idleWaitClip(actor)
  if not (actor and actor.national and OrasPbjAnim) then return nil end
  if actor._waitClip ~= nil then
    return actor._waitClip ~= false and actor._waitClip or nil
  end
  local pack = OrasPbjAnim.loadClips(actor.national)
  local clip = pack and OrasPbjAnim.pickClip(pack, "wait")
  actor._waitClip = clip or false
  return clip
end

local function startBattleAnim(actor, kind, dur, extra)
  if not actor then return end
  local physical = extra and extra.physical
  if physical == nil and extra and extra.moveAnim then
    physical = extra.moveAnim.physical
  end
  local clip, pack, role = nil, nil, nil
  if actor.national and OrasPbjAnim then
    pack = OrasPbjAnim.loadClips(actor.national)
    role = OrasPbjAnim.roleForBattleKind(kind, physical)
    if role then
      clip = OrasPbjAnim.pickClip(pack, role)
    end
    if kind == "attack" and not clip and pack then
      clip = OrasPbjAnim.pickClip(pack, "attack_physical")
        or OrasPbjAnim.pickClip(pack, "attack_special")
    end
  end
  local clipDur = clip and OrasPbjAnim.clipDuration(clip) or nil
  local useDur = clipDur or tonumber(dur) or 0.4
  local src
  if clip and actorHasSkin(actor) and skinAllowed() then
    src = OrasModels.PBJ_SKINNED_SOURCE
  elseif clip then
    src = OrasModels.PBJ_ANIM_SOURCE
  else
    src = OrasModels.BATTLE_ANIM_SOURCE
  end
  actor.battleAnim = {
    kind = kind,
    t0 = nowTime(),
    dur = math.max(0.05, useDur),
    sign = extra and extra.sign or ((actor == actors.enemy) and -1 or 1),
    clip = clip,
    role = role,
    physical = physical,
    source = src,
  }
  actor.context = kind
  actor.animSource = src
  if actor.bundle then
    actor.bundle.anim_source = src
    if clip then
      actor.bundle.pbj_clip = clip.short or clip.name
      actor.bundle.pbj_role = role
    end
  end
  diag(("anim START kind=%s side=%s dur=%.2f src=%s clip=%s"):format(
    tostring(kind),
    (actor == actors.player) and "player" or ((actor == actors.enemy) and "enemy" or "?"),
    actor.battleAnim.dur,
    tostring(src),
    tostring(clip and (clip.short or clip.name) or "procedural")))
end

local function battlerHp(battler)
  if not battler then return nil end
  local hp = battler.hp or battler.HP
  if hp == nil and battler.mon then hp = battler.mon.hp or battler.mon.HP end
  return tonumber(hp)
end

local function updatePresentation(battle, side, actor)
  if not (actor and actor.bundle) then return end
  local battler = battle and battle[side]
  if actor.pendingLand then
    actor.pendingLand = nil
    startBattleAnim(actor, "land", OrasModels.LAND_DUR)
  end
  -- Gen1 BattleState send-out grow-in.
  local grow = battler and safeCall(battle, "growInScale", battler) or nil
  if grow and not actor.lastGrow then
    startBattleAnim(actor, "land", OrasModels.LAND_DUR)
  end
  actor.lastGrow = grow and true or false

  local fainted = battler and (battler.fainted or battler.hp == 0
    or (battler.mon and (battler.mon.hp == 0 or battler.mon.fainted))) and true or false
  local faintFx = battler and safeCall(battle, "fxFaintActive", battler) or false
  if (faintFx or fainted) and not actor.lastFainted then
    startBattleAnim(actor, "faint", OrasModels.FAINT_DUR)
  end
  actor.lastFainted = fainted or faintFx or false

  -- Gen1 picFx blink (damage).
  local picFx = battler and battle.picFx and battle.picFx[battler] or nil
  local kind = picFx and picFx.kind or nil
  if kind == "blink" and actor.lastPicKind ~= "blink" then
    startBattleAnim(actor, "damage", OrasModels.DMG_DUR)
  end
  actor.lastPicKind = kind

  -- Game3 / any battle: HP drop => flinch (covers missing picFx).
  local hp = battlerHp(battler)
  if hp and actor.lastHp and hp < actor.lastHp - 0.5 then
    if not (actor.battleAnim and actor.battleAnim.kind == "damage") then
      startBattleAnim(actor, "damage", OrasModels.DMG_DUR)
    end
  end
  if hp then actor.lastHp = hp end
end

-- Advance procedural idle + event battle anims. Mirrors StadiumModels.update.
function OrasModels.update(battle, dt)
  if not OrasModels.sync(battle) then return false end
  battle = battleBag(battle)

  for _, side in ipairs({ "player", "enemy" }) do
    updatePresentation(battle, side, actors[side])
  end

  -- Gen1: BattleState.animPlaying rising edge.
  local playing = battle and battle.animPlaying and true or false
  if playing and not OrasModels.animWasPlaying then
    local atkSide = battle.animAttackerIsPlayer and "player" or "enemy"
    local defSide = atkSide == "player" and "enemy" or "player"
    startBattleAnim(actors[atkSide], "attack", OrasModels.ATK_DUR)
    startBattleAnim(actors[defSide], "damage", OrasModels.DMG_DUR)
  end
  OrasModels.animWasPlaying = playing

  -- Game3: battle.moveAnim armed by Game3:armMoveAnim (NOT animPlaying).
  -- Do NOT key on ma.t — it advances every frame and would re-trigger.
  local ma = battle and battle.moveAnim
  local maKey = nil
  if type(ma) == "table" then
    maKey = table.concat({
      tostring(ma.moveId or ""),
      tostring(ma.kind or ""),
      tostring(ma.dur or ""),
      tostring(ma.onEnemy and true or false),
      tostring(ma.physical and true or false),
    }, ":")
  end
  if maKey and maKey ~= OrasModels.lastMoveAnimKey then
    -- armMoveAnim: onEnemy=true when attacker is the player (hit lands on foe).
    local atkSide = ma.onEnemy and "player" or "enemy"
    local defSide = atkSide == "player" and "enemy" or "player"
    local extra = { physical = ma.physical, moveAnim = ma }
    if ma.kind == "status" then
      startBattleAnim(actors[atkSide], "attack", OrasModels.ATK_DUR * 0.75, extra)
    else
      startBattleAnim(actors[atkSide], "attack", OrasModels.ATK_DUR, extra)
      startBattleAnim(actors[defSide], "damage", OrasModels.DMG_DUR)
    end
  end
  OrasModels.lastMoveAnimKey = maKey

  for _, side in ipairs({ "player", "enemy" }) do
    local actor = actors[side]
    if actor and actor.bundle then
      actor.idlePhase = actor.idlePhase or ((side == "enemy") and 1.7 or 0.0)
      local anim = actor.battleAnim
      local skinClip, skinU = nil, 0
      if anim then
        local u = (nowTime() - anim.t0) / anim.dur
        if u >= 1 then
          if anim.kind == "faint" and (actor.lastFainted) then
            actor.animSource = anim.source or OrasModels.BATTLE_ANIM_SOURCE
            skinClip, skinU = anim.clip, 1
          else
            actor.battleAnim = nil
            actor.context = "idle"
            anim = nil
          end
        else
          if u < 0 then u = 0 end
          actor.animSource = anim.source or OrasModels.BATTLE_ANIM_SOURCE
          skinClip, skinU = anim.clip, u
        end
      end
      if not anim then
        local waitClip = skinAllowed() and actorHasSkin(actor) and idleWaitClip(actor) or nil
        if waitClip then
          local dur = OrasPbjAnim.clipDuration(waitClip) or 2
          local phase = tonumber(actor.idlePhase) or 0
          local t = nowTime() + phase
          skinU = (t % dur) / dur
          skinClip = waitClip
          actor.animSource = OrasModels.PBJ_SKINNED_SOURCE
          actor.context = "idle"
          if actor.bundle then
            actor.bundle.pbj_clip = waitClip.short or waitClip.name
            actor.bundle.pbj_role = "wait"
          end
        else
          -- Prefer real GF1 root wait when skinning is disabled.
          local rootWait = (not skinAllowed()) and idleWaitClip(actor) or nil
          if rootWait and OrasPbjAnim and OrasPbjAnim.rootDelta then
            actor.animSource = OrasModels.PBJ_IDLE_SOURCE
            actor._rootWaitClip = rootWait
          else
            actor.animSource = OrasModels.IDLE_SOURCE
            actor._rootWaitClip = nil
          end
          if actor.context ~= "faint" then
            actor.context = "idle"
          end
        end
      end
      if skinAllowed() and skinClip and actorHasSkin(actor) then
        applySkinToActor(actor, skinClip, skinU)
        actor._skinApplied = true
        actor._bindPoseRestored = false
        actor._waitLoopApplied = false
      elseif (not skinAllowed()) and actorHasWaitLoop(actor) and not anim then
        if applyWaitLoopToActor(actor) then
          actor._waitLoopApplied = true
          actor._skinApplied = false
          actor._bindPoseRestored = true
          actor.animSource = OrasModels.WAIT_LOOP_SOURCE
          if actor.bundle then
            actor.bundle.pbj_clip = (actor.bundle.wait_pose and actor.bundle.wait_pose.clip)
              or "wait_loop"
            actor.bundle.pbj_role = "wait"
          end
        end
      elseif actorHasSkin(actor) and not skinAllowed()
          and (actor._skinApplied or not actor._bindPoseRestored) then
        -- One-shot restore to wait-posed rest (baked vertices), never morph.
        if restoreBindPose(actor) then
          actor._bindPoseRestored = true
          actor._skinApplied = false
          diag(("ORAS bind_pose restored side=%s nat=%s")
            :format(side, tostring(actor.national)))
        else
          actor._bindPoseRestored = true
        end
      end
      actor.bundle.anim_source = actor.animSource
    end
  end
  return true
end

local function idleLocalMatrix(actor)
  -- Skinned wait clips own idle motion; keep placement rigid.
  if skinAllowed() and actorHasSkin(actor) and idleWaitClip(actor) then
    return Mat4.identity()
  end
  -- Prefer wall-clock so idle keeps moving even if a frame skips update().
  local now = nowTime()
  local phase = tonumber(actor and actor.idlePhase) or 0
  local t = now + phase
  if actor then
    actor.idleTime = t
  end
  local height = tonumber(actor and actor.bundle and actor.bundle.height) or OrasModels.REF_MODEL_H
  local breathe = math.sin(t * (OrasModels.IDLE_BREATHE_HZ * 2 * math.pi))
  local sway = math.sin(t * (OrasModels.IDLE_SWAY_HZ * 2 * math.pi) + 0.9)
  local lean = math.sin(t * (OrasModels.IDLE_SWAY_HZ * 2 * math.pi) + 2.1)
  -- Serpents without safe wait bake: slightly stronger float/slither (Rayquaza).
  local amp = 1.0
  local nat = tonumber(actor and actor.national)
    or tonumber(actor and actor.bundle and actor.bundle.national)
  local hasSafeWait = type(actor and actor.bundle and actor.bundle.wait_pose) == "table"
    and actor.bundle.wait_pose.safe ~= false
  if (not hasSafeWait) and nat and OrasModels.ELONG_VERTICAL_NATS
      and OrasModels.ELONG_VERTICAL_NATS[nat] then
    amp = 1.85
  end
  local sy = 1 + OrasModels.IDLE_BREATHE_AMP * amp * breathe
  -- Slight XZ tuck so volume feels conserved while breathing.
  local sxz = 1 - OrasModels.IDLE_BREATHE_AMP * 0.45 * amp * breathe
  local bob = height * OrasModels.IDLE_BOB_FRAC * amp * (0.5 + 0.5 * breathe)
  local swayRad = OrasModels.IDLE_SWAY_RAD * amp
  local leanRad = OrasModels.IDLE_LEAN_RAD * amp
  -- Soft Z-axis undulation for tipped serpents (reads as body slither).
  local twist = OrasModels.IDLE_SWAY_RAD * 0.55 * amp * math.sin(t * (OrasModels.IDLE_SWAY_HZ * 2 * math.pi) + 0.3)
  -- Feet planted at y=0 after floor offset: scale then bob/lean/sway.
  return Mat4.mul(Mat4.translate(0, bob, 0),
    Mat4.mul(Mat4.rotateY(swayRad * sway),
      Mat4.mul(Mat4.rotateX(leanRad * lean),
        Mat4.mul(Mat4.rotateZ(twist),
          Mat4.scale(sxz, sy, sxz)))))
end

-- Event-driven battle motion: prefer real PBJ GF1 root channels; else procedural.
local function battleLocalMatrix(actor)
  local anim = actor and actor.battleAnim
  if not anim then
    return idleLocalMatrix(actor)
  end
  local height = tonumber(actor.bundle and actor.bundle.height) or OrasModels.REF_MODEL_H
  local u = (nowTime() - anim.t0) / anim.dur
  if u < 0 then u = 0 end
  if u > 1 then u = 1 end
  local sign = tonumber(anim.sign) or 1
  local kind = anim.kind
  if anim.clip and OrasPbjAnim then
    -- Skinned path already deforms limbs; do not also apply root Mat4.
    if skinAllowed() and actorHasSkin(actor) then
      return Mat4.identity()
    end
    local tx, ty, tz, rx, ry, rz = OrasPbjAnim.rootDelta(anim.clip, u)
    local damp = 0.35
    local m = Mat4.mul(Mat4.translate(tx * damp, ty * damp, tz * damp),
      Mat4.mul(Mat4.rotateX(rx * damp),
        Mat4.mul(Mat4.rotateY(ry * damp),
          Mat4.rotateZ(rz * damp))))
    if kind == "attack" or kind == "land" or kind == "damage" then
      return Mat4.mul(m, idleLocalMatrix(actor))
    end
    return m
  end
  if kind == "attack" then
    local pulse = math.sin(u * math.pi)
    return Mat4.mul(Mat4.translate(0, height * 0.06 * pulse, -height * 0.42 * pulse),
      Mat4.mul(Mat4.rotateX(-0.45 * pulse), idleLocalMatrix(actor)))
  elseif kind == "damage" then
    local pulse = math.sin(u * math.pi * 3) * (1 - u)
    return Mat4.mul(Mat4.translate(height * 0.22 * pulse * sign, height * 0.04 * math.abs(pulse), height * 0.05 * pulse),
      Mat4.mul(Mat4.rotateZ(0.35 * pulse * sign), idleLocalMatrix(actor)))
  elseif kind == "faint" then
    local s = 1 - 0.65 * u
    return Mat4.mul(Mat4.translate(0, -height * 0.55 * u, 0),
      Mat4.mul(Mat4.rotateX(1.25 * u), Mat4.scale(s, math.max(0.12, s * (1 - 0.3 * u)), s)))
  elseif kind == "land" then
    local bounce = math.sin(u * math.pi)
    local drop = (1 - u) * (1 - u)
    return Mat4.mul(Mat4.translate(0, height * 0.55 * drop, 0),
      Mat4.mul(Mat4.scale(1 + 0.12 * bounce, 1 - 0.22 * bounce, 1 + 0.12 * bounce),
        idleLocalMatrix(actor)))
  end
  return idleLocalMatrix(actor)
end

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end

local function bundleExtents(bundle)
  local bmin = bundle and bundle.bounds_min
  local bmax = bundle and bundle.bounds_max
  local dx, dy, dz = 1, 1, 1
  if type(bmin) == "table" and type(bmax) == "table" then
    dx = math.max((bmax[1] or 1) - (bmin[1] or 0), 1e-3)
    dy = math.max((bmax[2] or 1) - (bmin[2] or 0), 1e-3)
    dz = math.max((bmax[3] or 1) - (bmin[3] or 0), 1e-3)
  end
  return dx, dy, dz
end

-- Placement scale for ORAS meshes. Normal-proportion mons keep uniform
-- height-fit. Tall serpentine AABBs (aspect high, Y longest) tip long-axis
-- toward horizontal so they read as floating dragons/serpents, not poles.
-- Long ground snakes (Onix / Furret-class Z-long) keep uniform + length clamp.
local function placementScale(bundle, grow)
  local height = tonumber(bundle and bundle.height) or OrasModels.REF_MODEL_H
  if height <= 0 then return nil end
  local dx, dy, dz = bundleExtents(bundle)
  -- Prefer live Y extent when bounds exist (matches floor planting).
  if dy > 1e-3 then height = dy end
  local worldHeight = OrasModels.REF_WORLD_H * math.sqrt(height / OrasModels.REF_MODEL_H)
  worldHeight = math.max(5, math.min(28, worldHeight))
  grow = math.max(0, math.min(1, tonumber(grow) or 1))
  local k = worldHeight / height * grow
  local maxE = math.max(dx, dy, dz)
  local minE = math.max(math.min(dx, dy, dz), 1e-6)
  local aspect = maxE / minE
  local nat = tonumber(bundle and bundle.national)
  local forceVert = nat and OrasModels.ELONG_VERTICAL_NATS
    and OrasModels.ELONG_VERTICAL_NATS[nat]
  local heightDominant = dy >= dx and dy >= dz
  local elongated = aspect >= (OrasModels.ELONG_ASPECT or 2.5)
  local tipMin = OrasModels.ELONG_TIP_ASPECT_MIN or 2.0
  -- Tip when Y is the long axis and aspect says serpent; allowlist only
  -- helps borderline aspects (never tip stocky Y-tall mons like Garchomp).
  -- Safe wait_pose already carries ORAS idle silhouette — skip tip for those.
  -- Failures (Rayquaza etc.) keep bind verts and still get elong_tip_horiz.
  local hasSafeWait = type(bundle and bundle.wait_pose) == "table"
    and bundle.wait_pose.safe ~= false
  local wantTip = (not hasSafeWait) and heightDominant and (
    elongated or (forceVert and aspect >= tipMin))
  local sx, sy, sz = k, k, k
  local mode = "uniform_height"
  local yawExtra = 0
  local pitchExtra = 0
  local floorAdj = tonumber(bundle and bundle.floor) or 0
  if wantTip then
    local tipDeg = OrasModels.ELONG_TIP_DEG or 78
    pitchExtra = math.rad(tipDeg)
    local ca = math.abs(math.cos(pitchExtra))
    local sa = math.abs(math.sin(pitchExtra))
    -- AABB extents after rotateX(tip): width unchanged; height/depth swap mix.
    local dy2 = ca * dy + sa * dz
    local dz2 = sa * dy + ca * dz
    local worldH = OrasModels.REF_WORLD_H * math.sqrt(dy2 / OrasModels.REF_MODEL_H)
    local hMax = OrasModels.ELONG_TIP_WORLD_H_MAX or 18
    worldH = math.max(6, math.min(hMax, worldH))
    local kTip = worldH / math.max(dy2, 1e-6) * grow
    local worldLen = dz2 * kTip
    local lenMax = OrasModels.ELONG_TIP_LEN_MAX or 40
    if worldLen > lenMax then
      kTip = kTip * (lenMax / worldLen)
      worldH = dy2 * kTip
      worldLen = lenMax
    end
    sx, sy, sz = kTip, kTip, kTip
    -- Plant lowest post-tip AABB corner, then float a bit (ORAS flyers).
    local bmin = bundle and bundle.bounds_min
    local bmax = bundle and bundle.bounds_max
    local ymin = 0
    if type(bmin) == "table" and type(bmax) == "table" then
      local cs = math.cos(pitchExtra)
      local ss = math.sin(pitchExtra)
      local y0, y1 = bmin[2] or 0, bmax[2] or 0
      local z0, z1 = bmin[3] or 0, bmax[3] or 0
      ymin = math.huge
      for _, y in ipairs({ y0, y1 }) do
        for _, z in ipairs({ z0, z1 }) do
          local yp = cs * y - ss * z
          if yp < ymin then ymin = yp end
        end
      end
      if ymin == math.huge then ymin = 0 end
    else
      ymin = floorAdj
    end
    local floatFrac = OrasModels.ELONG_TIP_FLOAT or 0.14
    floorAdj = ymin - floatFrac * dy2
    mode = ("elong_tip_horiz tip=%d aspect=%.2f len=%.1f"):format(
      tipDeg, aspect, worldLen)
    -- Prefer broad side toward opponent when former depth was the thin axis.
    if dx > dz * 1.35 then
      yawExtra = math.pi * 0.5
      mode = mode .. " yaw+90"
    end
  elseif elongated then
    local maxHoriz = math.max(dx, dz) * k
    local cap = OrasModels.ELONG_HORIZ_WORLD_MAX or 48
    if maxHoriz > cap then
      local s = cap / maxHoriz
      sx, sy, sz = k * s, k * s, k * s
      mode = ("elong_horiz_clamp aspect=%.2f"):format(aspect)
    else
      mode = ("uniform_elong aspect=%.2f"):format(aspect)
    end
  end
  return sx, sy, sz, yawExtra, pitchExtra, floorAdj, mode, aspect, height, worldHeight
end

local function modelMatrix(arena, groundY, battle, side, actor)
  local point = arena and arena[side]
  local target = arena and arena[side == "player" and "enemy" or "player"]
  if not (point and target and actor.bundle) then return nil end
  local battler = battle and battle[side]
  local grow = battler and safeCall(battle, "growInScale", battler) or 1
  local sx, sy, sz, yawExtra, pitchExtra, floorAdj, mode = placementScale(actor.bundle, grow)
  if not sx then return nil end
  local yaw = atan2(target[1] - point[1], target[2] - point[2]) + (yawExtra or 0)
  pitchExtra = pitchExtra or 0
  floorAdj = floorAdj or (tonumber(actor.bundle.floor) or 0)
  infoOnce(("scale:%s:%s"):format(tostring(side), tostring(actor.bundle.national)),
    ("ORAS scale side=%s nat=%s mode=%s sx=%.4f sy=%.4f sz=%.4f pitch=%.1f"):format(
      tostring(side), tostring(actor.bundle.national), tostring(mode), sx, sy, sz,
      math.deg(pitchExtra)))
  -- Order: plant -> scale -> tip long-axis into depth -> face opponent -> arena.
  local localM = Mat4.mul(Mat4.scale(sx, sy, sz), Mat4.translate(0, -floorAdj, 0))
  if math.abs(pitchExtra) > 1e-6 then
    localM = Mat4.mul(Mat4.rotateX(pitchExtra), localM)
  end
  local base = Mat4.mul(Mat4.translate(point[1], groundY, point[2]),
    Mat4.mul(Mat4.rotateY(yaw), localM))
  -- Procedural idle / battle after bind-pose placement.
  return Mat4.mul(base, battleLocalMatrix(actor))
end

function OrasModels.placements(arena, groundY, textures, battle, skip)
  if not OrasModels.sync(battle) then return {} end
  skip = skip or {}
  local out = {}
  for _, side in ipairs({ "enemy", "player" }) do
    if not skip[side] then
      local texture = textures and textures[side]
      local actor = actors[side]
      -- Billboard texture is only required to detect trainer-intro cards.
      -- ORAS 3D draws from actor.bundle mesh textures, so a brief nil
      -- billboard (player send-out / sideVisible=false) must NOT skip the
      -- mesh -- that was flooding diag with no_texture while texMiss=0.
      if texture and texture.trainer then
        diag(("ORAS skip side=%s reason=trainer_intro"):format(side))
      elseif not (actor and actor.bundle) then
        if not texture then
          diag(("ORAS skip side=%s reason=no_texture"):format(side))
        end
        -- else already logged in syncSide
      else
        local matrix = modelMatrix(arena, groundY, battle, side, actor)
        if matrix then
          out[side] = {
            side = side,
            actor = actor,
            bundle = actor.bundle,
            modelMatrix = matrix,
          }
        else
          warnOnce(("matrix:%s"):format(side),
            ("ORAS %s place FAIL reason=no_matrix"):format(side))
        end
      end
    end
  end
  return out
end

function OrasModels.draw(placement, _context, _pass)
  if not (placement and placement.bundle and placement.modelMatrix) then
    return false
  end
  local parts = placement.bundle.parts
  if type(parts) ~= "table" then return false end
  local drawn = 0
  for i = 1, #parts do
    local part = parts[i]
    if part and part.mesh then
      Voxel3D.draw(part.mesh, part.tex, placement.modelMatrix, OrasModels.PULL)
      drawn = drawn + 1
    end
  end
  if drawn > 0 then
    local side = placement.side or "?"
    local now = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
    if (now - (drawLogAt[side] or 0)) > 2.5 then
      drawLogAt[side] = now
      local anim = placement.bundle.anim_source
        or (placement.actor and placement.actor.animSource)
        or OrasModels.IDLE_SOURCE
      diag(("drawing ORAS 3D side=%s nat=%s parts=%s path=voxel_3d anim=%s")
        :format(side, tostring(placement.bundle.national), tostring(drawn),
          tostring(anim)))
    end
  end
  return drawn > 0
end

function OrasModels.drawShadow(placement, shadowMap)
  if not (placement and placement.bundle and placement.modelMatrix and shadowMap) then
    return false
  end
  local parts = placement.bundle.parts
  if type(parts) ~= "table" then return false end
  local drawn = 0
  for i = 1, #parts do
    local part = parts[i]
    if part and part.mesh and shadowMap.draw then
      pcall(shadowMap.draw, part.mesh, part.tex, placement.modelMatrix)
      drawn = drawn + 1
    end
  end
  return drawn > 0
end

function OrasModels.uses(placements, side)
  return type(placements) == "table" and placements[side] ~= nil
end

function OrasModels.logBillboard(side, reason)
  local now = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
  local key = "bb:" .. tostring(side)
  if (now - (drawLogAt[key] or 0)) > 2.5 then
    drawLogAt[key] = now
    diag(("drawing Gen3 billboard side=%s reason=%s"):format(
      tostring(side), tostring(reason or "no_oras_placement")))
  end
end

function OrasModels.status()
  local on, why = OrasModels.active()
  local pbj = OrasPbjAnim and OrasPbjAnim.status and OrasPbjAnim.status() or nil
  return {
    apiVersion = 2,
    installed = OrasModels.installed(),
    active = on,
    activeWhy = why,
    providerId = providerHandle and "oras_models" or nil,
    idleSource = OrasModels.IDLE_SOURCE,
    battleAnimSource = OrasModels.BATTLE_ANIM_SOURCE,
    pbjAnimSource = OrasModels.PBJ_ANIM_SOURCE,
    pbjSkinnedSource = OrasModels.PBJ_SKINNED_SOURCE,
    skinningEnabled = OrasModels.ENABLE_SKINNING and true or false,
    waitPoseDisplay = OrasModels.ENABLE_WAIT_POSE_DISPLAY and true or false,
    waitLoopEnabled = OrasModels.ENABLE_WAIT_LOOP and true or false,
    waitPoseBaked = false,  -- unsafe; display uses bind until bake fixed
    waitLoopSource = OrasModels.WAIT_LOOP_SOURCE,
    pbj = pbj,
    sides = {
      player = actors.player.bundle and true or false,
      enemy = actors.enemy.bundle and true or false,
    },
    anim = {
      player = actors.player.animSource,
      enemy = actors.enemy.animSource,
      playerPhase = actors.player.idlePhase,
      enemyPhase = actors.enemy.idlePhase,
      playerContext = actors.player.context,
      enemyContext = actors.enemy.context,
    },
  }
end

return OrasModels
