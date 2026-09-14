-- ORAS move-effect billboards for DramaticShapes voxel battles.
--
-- Loads ripped TXOB PNGs from AppData oras_extract/effects/ (see
-- mods/oras_models/extract/extract_oras_effects.py). When battle.moveAnim
-- runs, prefers these real ORAS textures over Game3MoveAnim Gen3 procedural FX.
--
-- Gap (honest): NW particle sim (spawn rates / velocity / lifetime curves)
-- is not executed - we billboard the actual ORAS effect textures/meshes that
-- compose each move (e.g. Fire Blast ew126 font/moji + fire patterns).
--
-- Thickness knobs (v2 — "make it thicker"): larger world scale, multi-TXOB
-- layering from each move's CGFX set, opacity stacking, denser spawns.
-- Fire Blast (heavy packs) reads much thicker than Ember (light packs).

local V = ...

local OrasMoveFx = {}

OrasMoveFx.INDEX_REL = "oras_extract/effects/move_fx_index.json"
OrasMoveFx.MOVES_REL = "oras_extract/effects/moves/"
OrasMoveFx.ENABLED = true

-- ---------------------------------------------------------------------------
-- Visual thickness knobs (tune here; no Gen3 procedural inflation)
-- ---------------------------------------------------------------------------
OrasMoveFx.HEAVY_SCALE      = 4.15   -- was 2.4  — Fire Blast / multi-CGFX packs
OrasMoveFx.LIGHT_SCALE      = 1.85   -- was 1.15 — Ember / few-CGFX packs
OrasMoveFx.HEAVY_PULSE      = 0.32   -- was 0.18
OrasMoveFx.LIGHT_PULSE      = 0.16   -- was 0.18 (shared)
OrasMoveFx.HEAVY_RAD_BASE   = 6     -- was 10 — keep layers overlapping for thickness
OrasMoveFx.HEAVY_RAD_GROW   = 22    -- was 18
OrasMoveFx.LIGHT_RAD_BASE   = 4     -- was 6
OrasMoveFx.LIGHT_RAD_GROW   = 22    -- was 28 (slightly tighter travel spray)
OrasMoveFx.HEAVY_STACKS     = 3     -- draw each primary TXOB N times (opacity stack)
OrasMoveFx.LIGHT_STACKS     = 2
OrasMoveFx.HEAVY_MAX_TEX    = 16    -- pull extra TXOBs from move folder beyond index
OrasMoveFx.LIGHT_MAX_TEX    = 6
OrasMoveFx.HEAVY_SPAWN_COPIES = 2   -- angular copies of rings/aura for density
OrasMoveFx.LIGHT_SPAWN_COPIES = 1
OrasMoveFx.HEAVY_DUR_MULT   = 1.65  -- visual linger vs ma.dur (screen-filling hold)
OrasMoveFx.LIGHT_DUR_MULT   = 1.20
OrasMoveFx.HEAVY_FADE_IN    = 0.06
OrasMoveFx.HEAVY_FADE_OUT   = 0.18  -- hold opaque longer (was fade after 0.75)
OrasMoveFx.LIGHT_FADE_IN    = 0.10
OrasMoveFx.LIGHT_FADE_OUT   = 0.28
OrasMoveFx.LAYER_ALPHA_MAIN = 0.95
OrasMoveFx.LAYER_ALPHA_SUB  = 0.78
OrasMoveFx.STACK_ALPHA_STEP = 0.55  -- per stacked redraw under the main hit

local index
local imgCache = {}
local packTexCache = {}
local warned = {}
local status = { loaded = false, reason = "init" }

local function diag(msg)
  local log = V.mod and V.mod.log
  if log and log.info then pcall(log.info, log, "[OrasMoveFx] %s", tostring(msg)) end
end

local function warnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  diag("WARN " .. tostring(msg))
end

local function decodeJson(text)
  if type(text) ~= "string" or text == "" then return nil end
  local ok, Json = pcall(require, "src.link.Json")
  if ok and Json and Json.decode then
    local obj = Json.decode(text)
    if type(obj) == "table" then return obj end
  end
  local ok2, obj2 = pcall(function()
    return (loadstring or load)("return " .. text)()
  end)
  if ok2 and type(obj2) == "table" then return obj2 end
  return nil
end

local function readIndex()
  if index then return index end
  local okCf, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okCf and CacheFs and CacheFs.read) then
    status = { loaded = false, reason = "no_cachefs" }
    return nil
  end
  local saved = CacheFs.prefix
  CacheFs.prefix = ""
  local text = CacheFs.read(OrasMoveFx.INDEX_REL)
  CacheFs.prefix = saved
  if type(text) ~= "string" or text == "" then
    status = { loaded = false, reason = "missing_index" }
    return nil
  end
  local obj = decodeJson(text)
  if type(obj) ~= "table" or type(obj.by_move) ~= "table" then
    status = { loaded = false, reason = "bad_index" }
    return nil
  end
  index = obj
  status = {
    loaded = true,
    reason = "ok",
    mapped = obj.gen3_mapped_ew_ea,
    fallback = obj.gen3_shared_fallback,
    oras_mapped = obj.oras_moves_1_621_mapped,
    gap = obj.gap,
  }
  diag(string.format(
    "index ok mapped=%s fallback=%s oras=%s",
    tostring(status.mapped), tostring(status.fallback), tostring(status.oras_mapped)))
  return index
end

local function loadImage(rel)
  if imgCache[rel] ~= nil then return imgCache[rel] end
  -- love.filesystem reads the save directory (AppData/.../pokemon-love2d/).
  local fs = love and love.filesystem
  local g = love and love.graphics
  if not (fs and fs.getInfo and g and g.newImage) then
    imgCache[rel] = false
    return nil
  end
  if not fs.getInfo(rel) then
    imgCache[rel] = false
    return nil
  end
  local ok, img = pcall(g.newImage, rel)
  if not (ok and img) then
    imgCache[rel] = false
    warnOnce("img:" .. rel, "failed to load " .. rel)
    return nil
  end
  pcall(img.setFilter, img, "linear", "linear")
  imgCache[rel] = img
  return img
end

--- Role weight from ORAS TXOB filename (aura/ring/moji bigger than sparks).
local function texRole(name)
  local n = (name or ""):lower()
  if n:find("font") or n:find("moji") then return "moji", 1.35 end
  if n:find("aura") then return "aura", 1.25 end
  if n:find("ring") then return "ring", 1.20 end
  if n:find("firepatern") or n:find("firepattern") or n:find("patern") then
    return "pattern", 1.10
  end
  if n:find("circle") then return "circle", 1.05 end
  if n:find("smoke") or n:find("dust") then return "smoke", 0.95 end
  if n:find("firept") or n:find("ptset") or n:find("spark") then return "spark", 0.85 end
  if n:find("leaf") then return "leaf", 0.80 end
  return "misc", 1.0
end

local function rolePriority(role)
  local order = {
    moji = 1, aura = 2, ring = 3, pattern = 4, circle = 5,
    smoke = 6, misc = 7, spark = 8, leaf = 9,
  }
  return order[role] or 7
end

--- Extra PNGs sitting in moves/NNN/ beyond the index shortlist (CGFX dumps).
local function listPackTextures(mid)
  if packTexCache[mid] ~= nil then return packTexCache[mid] end
  local out = {}
  local fs = love and love.filesystem
  if not (fs and fs.getDirectoryItems) then
    packTexCache[mid] = out
    return out
  end
  local dir = OrasMoveFx.MOVES_REL .. string.format("%03d", mid)
  local ok, items = pcall(fs.getDirectoryItems, dir)
  if not (ok and type(items) == "table") then
    packTexCache[mid] = out
    return out
  end
  for _, name in ipairs(items) do
    if type(name) == "string" and name:lower():match("%.png$") then
      out[#out + 1] = name
    end
  end
  table.sort(out, function(a, b)
    local ra = select(1, texRole(a))
    local rb = select(1, texRole(b))
    local pa, pb = rolePriority(ra), rolePriority(rb)
    if pa ~= pb then return pa < pb end
    return a < b
  end)
  packTexCache[mid] = out
  return out
end

--- Merge index textures + pack folder TXOBs, capped, preferring screen-fill roles.
local function collectTextures(mid, entry, maxN)
  local seen = {}
  local list = {}
  local function add(name)
    if type(name) ~= "string" or name == "" then return end
    local key = name:lower()
    if seen[key] then return end
    seen[key] = true
    list[#list + 1] = name
  end
  if entry and type(entry.textures) == "table" then
    -- Prefer roles that fill the screen first from the index shortlist.
    local ranked = {}
    for _, name in ipairs(entry.textures) do
      ranked[#ranked + 1] = name
    end
    table.sort(ranked, function(a, b)
      return rolePriority(select(1, texRole(a))) < rolePriority(select(1, texRole(b)))
    end)
    for _, name in ipairs(ranked) do add(name) end
  end
  for _, name in ipairs(listPackTextures(mid)) do
    if #list >= maxN then break end
    add(name)
  end
  while #list > maxN do table.remove(list) end
  return list
end

local function resolveMoveId(ma)
  if type(ma) ~= "table" then return nil end
  local id = tonumber(ma.moveId) or tonumber(ma.id) or tonumber(ma.move_id)
  if id and id > 0 then return math.floor(id) end
  local move = ma.move
  if type(move) == "table" then
    id = tonumber(move.id) or tonumber(move.moveId)
    if id and id > 0 then return math.floor(id) end
  end
  -- Name fallback via Game3MoveAnim constants when present.
  local name = ma.name or (type(move) == "table" and move.name) or nil
  if type(name) == "string" then
    local ok, MA = pcall(require, "src.core.Game3MoveAnim")
    if ok and MA and MA.resolve then
      local spec = MA.resolve({ name = name, id = ma.moveId })
      if type(spec) == "table" then
        id = tonumber(spec.id) or tonumber(spec.moveId)
        if id and id > 0 then return math.floor(id) end
      end
    end
    local n = name:upper():gsub("[^A-Z0-9]", "")
    if n == "EMBER" then return 52 end
    if n == "FIREBLAST" then return 126 end
    if n == "FLAMETHROWER" then return 53 end
  end
  return nil
end

function OrasMoveFx.status()
  readIndex()
  return status
end

function OrasMoveFx.has(moveId)
  local idx = readIndex()
  if not idx then return false end
  local e = idx.by_move[tostring(moveId)]
  return type(e) == "table" and type(e.textures) == "table" and #e.textures > 0
    and e.source ~= "none"
end

function OrasMoveFx.entry(moveId)
  local idx = readIndex()
  if not idx then return nil end
  return idx.by_move[tostring(moveId)]
end

local function isHeavyMove(mid, entry)
  local cgfxN = (entry and type(entry.cgfx) == "table" and #entry.cgfx) or 0
  if entry and entry.source == "ew_ea_pack" and cgfxN >= 4 then return true end
  -- Explicit heavies: Fire Blast, Hyper Beam, Surf, Blizzard, etc.
  if mid == 126 or mid == 63 or mid == 57 or mid == 59 then return true end
  if mid == 63 or mid == 192 or mid == 126 then return true end
  return false
end

--- Draw ORAS effect textures into the current GB-space anim canvas.
-- @return true if ORAS art was drawn (caller should skip Gen3 procedural FX)
function OrasMoveFx.draw(ma, hit, dur, cx, cy)
  if not OrasMoveFx.ENABLED then return false end
  local mid = resolveMoveId(ma)
  if not mid then return false end
  local entry = OrasMoveFx.entry(mid)
  if not (entry and entry.textures and #entry.textures > 0) then return false end

  local g = love and love.graphics
  if not g then return false end

  local heavy = isHeavyMove(mid, entry)
  hit = tonumber(hit) or 0
  dur = math.max(0.05, tonumber(dur) or 0.45)
  local visDur = dur * (heavy and OrasMoveFx.HEAVY_DUR_MULT or OrasMoveFx.LIGHT_DUR_MULT)
  local t = math.max(0, math.min(1, hit / visDur))
  local fadeIn = heavy and OrasMoveFx.HEAVY_FADE_IN or OrasMoveFx.LIGHT_FADE_IN
  local fadeOut = heavy and OrasMoveFx.HEAVY_FADE_OUT or OrasMoveFx.LIGHT_FADE_OUT
  local fade = 1
  if t < fadeIn then
    fade = t / math.max(0.001, fadeIn)
  elseif t > (1 - fadeOut) then
    fade = math.max(0, (1 - t) / math.max(0.001, fadeOut))
  end

  cx = tonumber(cx) or 120
  cy = tonumber(cy) or 56
  local onEnemy = ma and ma.onEnemy
  if onEnemy == nil and ma then onEnemy = true end

  local maxTex = heavy and OrasMoveFx.HEAVY_MAX_TEX or OrasMoveFx.LIGHT_MAX_TEX
  local textures = collectTextures(mid, entry, maxTex)
  if #textures == 0 then return false end

  local baseScale = heavy and OrasMoveFx.HEAVY_SCALE or OrasMoveFx.LIGHT_SCALE
  local pulseAmt = heavy and OrasMoveFx.HEAVY_PULSE or OrasMoveFx.LIGHT_PULSE
  local pulse = 1 + pulseAmt * math.sin(t * math.pi * (heavy and 3.2 or 2.2))
  local stacks = heavy and OrasMoveFx.HEAVY_STACKS or OrasMoveFx.LIGHT_STACKS
  local spawnCopies = heavy and OrasMoveFx.HEAVY_SPAWN_COPIES or OrasMoveFx.LIGHT_SPAWN_COPIES
  local radBase = heavy and OrasMoveFx.HEAVY_RAD_BASE or OrasMoveFx.LIGHT_RAD_BASE
  local radGrow = heavy and OrasMoveFx.HEAVY_RAD_GROW or OrasMoveFx.LIGHT_RAD_GROW

  -- Ember-like travel: move from attacker toward target over time (once).
  local drawCx, drawCy = cx, cy
  if not heavy then
    local ax = tonumber(ma and ma.ax) or 40
    local ay = tonumber(ma and ma.ay) or 80
    local tx = tonumber(ma and ma.tx) or cx
    local ty = tonumber(ma and ma.ty) or cy
    drawCx = ax + (tx - ax) * t
    drawCy = ay + (ty - ay) * t
  end

  local drawn = 0
  local nTex = #textures
  for i, name in ipairs(textures) do
    local rel
    if name:sub(1, 3) == "../" then
      rel = "oras_extract/effects/" .. name:gsub("^%.%./", "")
    else
      rel = OrasMoveFx.MOVES_REL .. string.format("%03d/", mid) .. name
    end
    local img = loadImage(rel)
    if img then
      local iw, ih = img:getWidth(), img:getHeight()
      local role, roleScale = texRole(name)
      local isPrimary = (role == "moji" or role == "aura" or role == "ring" or i <= 2)
      local layerAlpha = isPrimary and OrasMoveFx.LAYER_ALPHA_MAIN or OrasMoveFx.LAYER_ALPHA_SUB
      local ang0 = (i - 1) * (math.pi * 2 / math.max(1, nTex))
      local rad = radBase + radGrow * t
      -- Keep moji/aura near center for a solid core; orbit pattern/sparks.
      local orbitMul = (role == "moji" or role == "aura") and 0.15
        or (role == "ring" and 0.45)
        or (i == 1 and 0 or 1)

      local copies = (role == "ring" or role == "aura" or role == "pattern") and spawnCopies or 1
      for c = 1, copies do
        local ang = ang0 + (c - 1) * (math.pi * 2 / math.max(1, copies)) + t * (heavy and 2.6 or 4.0)
        local ox = math.cos(ang) * rad * orbitMul
        local oy = math.sin(ang) * rad * 0.55 * orbitMul
        local rot = ang * (heavy and 0.08 or 0.15)

        for s = 1, stacks do
          -- Stacked redraws: slightly larger + lower alpha underneath = thicker core.
          local stackGrow = 1 + (s - 1) * (heavy and 0.22 or 0.12)
          local scale = baseScale * pulse * roleScale * stackGrow
          -- Heavy patterns get an extra late-bloom swell.
          if heavy and (role == "pattern" or role == "ring") then
            scale = scale * (1 + 0.35 * t)
          end
          local a = fade * layerAlpha * (OrasMoveFx.STACK_ALPHA_STEP ^ (s - 1))
          if a > 0.02 then
            g.setColor(1, 1, 1, math.min(1, a))
            g.draw(img, drawCx + ox, drawCy + oy, rot, scale, scale, iw * 0.5, ih * 0.5)
            drawn = drawn + 1
          end
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)

  if drawn == 0 then
    warnOnce("empty:" .. mid, "no textures loaded for move " .. tostring(mid))
    return false
  end
  if not warned["drew:" .. mid] then
    warned["drew:" .. mid] = true
    diag(string.format(
      "drew move %d source=%s layers=%d heavy=%s scale=%.2f stacks=%d tex=%d",
      mid, tostring(entry.source), drawn, tostring(heavy), baseScale, stacks, nTex))
  end
  return true
end

return OrasMoveFx
