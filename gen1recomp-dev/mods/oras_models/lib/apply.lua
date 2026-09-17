-- Early apply: optional ORAS 2D overlays for Game3 battle pics.
-- Ships no pixels; only remaps absolute/cache paths from the extract index.
--
-- CRITICAL (stock GBA safety):
--   * NEVER mutate shared Gen3 sprite ImageData / CacheFs / Assets cache.
--   * NEVER permanently overwrite encounters.fronts/backs without a snapshot.
--   * Prefer additive overlay via Game3.battlePic hook; leave ROM tables pristine.
--   * When disabled / empty maps / Body UV only: stock GBA path is used unchanged.
--   * ORAS battles are 3D -- RomFS has no Gen5-style 2D battle sprites.
--     a/0/0/8 pm####_Body* sheets are model UV atlases and MUST NOT be
--     battlePic (noisy rectangular blocks).
local M = {}

-- Snapshot of pristine encounter path tables so disable/toggle restores stock.
local _encounterSnapshots = setmetatable({}, { __mode = "k" })

-- battle_texture_map stores absolute AppData paths. PhysFS / love.graphics
-- newImage only resolve game source + save-dir *relative* paths, so rewrite
-- save-dir absolutes to "oras_extract/..." before patching or hooking.
-- Sandbox blocks love.filesystem; strip to oras_extract/... without it.
local function normalizeImagePath(path)
  if type(path) ~= "string" or path == "" then return path end
  local norm = path:gsub("\\", "/")
  local idx = norm:lower():find("oras_extract/", 1, true)
  if idx then
    return norm:sub(idx)
  end
  local abs = norm:match("^[A-Za-z]:/") or norm:sub(1, 1) == "/"
  if not abs then
    return norm
  end
  -- Keep absolute; Game3:grabImage io.open-falls-back for host paths.
  return path
end

local function normalizeBucket(bucket)
  if type(bucket) ~= "table" then return bucket end
  for nat, row in pairs(bucket) do
    if type(row) == "table" and type(row.path) == "string" then
      row.path = normalizeImagePath(row.path)
    end
  end
  return bucket
end

local function normalizeMugshots(list)
  if type(list) ~= "table" then return list end
  for i = 1, #list do
    list[i] = normalizeImagePath(list[i])
  end
  return list
end

-- Fit oversized sheets into the Gen3 ~64px battle slot. Skip known UV atlas
-- sizes rather than shrink-wrapping Body* noise into the slot.
-- Returns a NEW canvas; never mutates the source Image / ImageData.
local function fitBattleSlot(img, sourceClass)
  if not (img and img.getDimensions) then return img end
  if sourceClass == "body_uv" then
    return nil -- refuse UV atlases even if somehow queued
  end
  local iw, ih = img:getDimensions()
  local slot = 64
  if iw <= slot + 16 and ih <= slot + 16 then return img end
  -- Huge sheets that aren't icons/battle sprites are almost certainly atlases.
  if iw >= 128 and ih >= 128 and sourceClass ~= "battle_front" and sourceClass ~= "battle_back" then
    return nil
  end
  if not (love and love.graphics and love.graphics.newCanvas) then return img end
  local sc = slot / math.max(iw, ih)
  local tw = math.max(1, math.floor(iw * sc + 0.5))
  local th = math.max(1, math.floor(ih * sc + 0.5))
  local ok, canvas = pcall(love.graphics.newCanvas, slot, slot)
  if not (ok and canvas) then return img end
  local prev = love.graphics.getCanvas and love.graphics.getCanvas()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, (slot - tw) / 2, (slot - th) / 2, 0, sc, sc)
  love.graphics.setCanvas(prev)
  if canvas.setFilter then canvas:setFilter("nearest", "nearest") end
  return canvas
end

local function pathLooksLikeBodyUv(path)
  if type(path) ~= "string" then return false end
  local p = path:gsub("\\", "/")
  if p:find("BodyA", 1, true) or p:find("BodyB", 1, true) or p:find("_Body", 1, true) then
    return true
  end
  if p:find("a/0/0/8/", 1, true) and p:find("pm", 1, true) and p:find("Body", 1, true) then
    return true
  end
  return false
end

local function isAllowedBattleSource(sourceClass, path)
  if pathLooksLikeBodyUv(path) then return false end
  if sourceClass == "body_uv" then return false end
  if sourceClass == "battle_front" or sourceClass == "battle_back" then return true end
  if sourceClass == "poke_icon" then return true end
  -- Unknown class: allow only small-sprite-looking paths under icon GARC.
  if type(path) == "string" then
    local p = path:gsub("\\", "/")
    if p:find("a/0/9/1/", 1, true) then return true end
  end
  return false
end

-- Legacy helper retained for diagnostics only - NOT used for battle apply.
function M.buildNationalBodyMap(textures)
  local front, back = {}, {}
  -- Intentionally empty: Body UV atlases must not feed battlePic.
  return front, back
end

-- Prefer real battle sprites / poke icons from the texture index.
-- Never selects a/0/0/8 Body* UV sheets.
function M.buildNationalBattleMap(textures)
  local front, back = {}, {}
  local sourceClass = "none"
  if type(textures) ~= "table" then return front, back, sourceClass end
  local iconFront, iconBack = {}, {}
  for i = 1, #textures do
    local t = textures[i]
    if type(t) == "table" then
      local name = tostring(t.name or "")
      local rel = tostring(t.rel or ""):gsub("\\", "/")
      local path = t.path
      local role = tostring(t.role or "")
      local w = tonumber(t.width) or 0
      local h = tonumber(t.height) or 0
      if type(path) == "string" and path ~= "" then
        if role == "battle_front" or rel:find("battle_front", 1, true) then
          local nat = tonumber((name:match("(%d+)") or rel:match("/(%d+)%.")))
          if nat then
            front[nat] = { path = path, sourceClass = "battle_front", score = 100 }
            sourceClass = "battle_front"
          end
        elseif role == "battle_back" or rel:find("battle_back", 1, true) then
          local nat = tonumber((name:match("(%d+)") or rel:match("/(%d+)%.")))
          if nat then
            back[nat] = { path = path, sourceClass = "battle_back", score = 100 }
            if sourceClass == "none" then sourceClass = "battle_back" end
          end
        elseif rel:sub(1, 8) == "a/0/9/1/" then
          local idx = tonumber(rel:match("/(%d+)%.") or name:match("^(%d+)$"))
          if idx and idx > 0 and w >= 20 and w <= 64 and h >= 20 and h <= 64 then
            -- Icons exist but BCLIM decode is not battle-ready yet; do not
            -- auto-bind. Keep detection so logs can report icon_candidates.
            iconFront[idx] = { path = path, sourceClass = "poke_icon", score = 50 }
            iconBack[idx] = { path = path, sourceClass = "poke_icon", score = 40 }
          end
        end
      end
    end
  end
  -- Auto-enable poke_icon mapping only when explicitly allowed (future).
  local USE_POKE_ICONS = false
  if USE_POKE_ICONS then
    front, back = iconFront, iconBack
    sourceClass = "poke_icon"
  end
  local iconCandidates = 0
  for _ in pairs(iconFront) do iconCandidates = iconCandidates + 1 end
  return front, back, sourceClass, iconCandidates
end

function M.collectMugshots(textures)
  local list = {}
  if type(textures) ~= "table" then return list end
  for i = 1, #textures do
    local t = textures[i]
    local rel = t and t.rel
    if type(rel) == "string" and rel:sub(1, 8) == "a/1/6/0/"
        and type(t.path) == "string" then
      list[#list + 1] = { rel = rel, path = t.path }
    end
  end
  table.sort(list, function(a, b) return a.rel < b.rel end)
  local paths = {}
  for i = 1, #list do paths[i] = list[i].path end
  return paths
end

-- Prefer slim battle_texture_map.json; else build from full texture list.
-- Strips any legacy body_uv rows so old maps cannot reintroduce UV noise.
function M.resolveMaps(mod, status, Extract)
  local front, back, mugshots = {}, {}, {}
  local sourceClass = "none"
  local iconCandidates = 0
  local map = Extract and Extract.readBattleMap and Extract.readBattleMap(mod)
  if type(map) == "table" then
    if type(map.meta) == "table" and type(map.meta.source_class) == "string" then
      sourceClass = map.meta.source_class
    end
    if type(map.meta) == "table" then
      iconCandidates = tonumber(map.meta.icon_candidates) or 0
    end
    if type(map.by_national) == "table" then
      for k, row in pairs(map.by_national) do
        local nat = tonumber(k)
        if nat and type(row) == "table" then
          local sc = row.source_class or row.front_source or row.back_source or sourceClass
          if type(row.front) == "string" and isAllowedBattleSource(sc or row.front_source, row.front) then
            front[nat] = {
              path = row.front,
              sourceClass = row.front_source or sc or "battle_front",
            }
          end
          if type(row.back) == "string" and isAllowedBattleSource(sc or row.back_source, row.back) then
            back[nat] = {
              path = row.back,
              sourceClass = row.back_source or sc or "battle_back",
            }
          end
        end
      end
    end
    if type(map.mugshots) == "table" then mugshots = map.mugshots end
  end
  local needBuild = next(front) == nil
  if needBuild then
    local textures = Extract.loadTextureList(mod, status)
    local sc, icons
    front, back, sc, icons = M.buildNationalBattleMap(textures)
    sourceClass = sc or "none"
    iconCandidates = icons or 0
    if type(mugshots) ~= "table" or #mugshots == 0 then
      mugshots = M.collectMugshots(textures)
    end
  end
  return front, back, mugshots, sourceClass, iconCandidates
end

local function speciesNational(game, species)
  if not game then return nil end
  if game.nationalDexOf then
    local ok, n = pcall(function() return game:nationalDexOf(species) end)
    if ok and tonumber(n) then return tonumber(n) end
  end
  local pack = game.data and game.data.pokemon
  local row = pack and pack.byIndex and pack.byIndex[species]
  return row and tonumber(row.nationalDex) or nil
end

local function ensureEncounterTables(game)
  if not (game and game.data) then return nil end
  local pack = game.data.encounters
  if type(pack) ~= "table" then
    pack = {}
    game.data.encounters = pack
  end
  pack.fronts = type(pack.fronts) == "table" and pack.fronts or {}
  pack.backs = type(pack.backs) == "table" and pack.backs or {}
  pack.frontsShiny = type(pack.frontsShiny) == "table" and pack.frontsShiny or {}
  pack.backsShiny = type(pack.backsShiny) == "table" and pack.backsShiny or {}
  return pack
end

local function clonePathBucket(bucket)
  local out = {}
  if type(bucket) ~= "table" then return out end
  for k, v in pairs(bucket) do
    out[k] = v
  end
  return out
end

-- Capture pristine ROM-extracted paths once per game instance so we can
-- restore after ORAS disable without reimport.
function M.snapshotEncounterPaths(game)
  if not game then return false end
  if _encounterSnapshots[game] then return true end
  local pack = ensureEncounterTables(game)
  if not pack then return false end
  _encounterSnapshots[game] = {
    fronts = clonePathBucket(pack.fronts),
    backs = clonePathBucket(pack.backs),
    frontsShiny = clonePathBucket(pack.frontsShiny),
    backsShiny = clonePathBucket(pack.backsShiny),
  }
  return true
end

function M.restoreEncounterPaths(game)
  if not game then return 0 end
  local snap = _encounterSnapshots[game]
  local pack = ensureEncounterTables(game)
  if not (snap and pack) then
    -- No snapshot: still scrub any Body-UV pollution left by older builds.
    return M.scrubBodyUvEncounterPaths(game)
  end
  pack.fronts = clonePathBucket(snap.fronts)
  pack.backs = clonePathBucket(snap.backs)
  pack.frontsShiny = clonePathBucket(snap.frontsShiny)
  pack.backsShiny = clonePathBucket(snap.backsShiny)
  if game.battlePicCache then game.battlePicCache = {} end
  return 1
end

function M.scrubBodyUvEncounterPaths(game)
  local pack = ensureEncounterTables(game)
  if not pack then return 0 end
  local n = 0
  for _, key in ipairs({"fronts", "backs", "frontsShiny", "backsShiny"}) do
    local bucket = pack[key]
    if type(bucket) == "table" then
      for sid, p in pairs(bucket) do
        if pathLooksLikeBodyUv(p) then
          bucket[sid] = nil
          n = n + 1
        end
      end
    end
  end
  if n > 0 and game.battlePicCache then game.battlePicCache = {} end
  return n
end

-- Optional permanent path patch. Prefer the battlePic hook overlay instead;
-- this remains for callers that explicitly opt in via opts.patchPaths.
function M.patchEncounterPaths(game, frontByNat, backByNat)
  local pack = ensureEncounterTables(game)
  if not pack then return 0 end
  M.snapshotEncounterPaths(game)
  local n = 0
  local pokemon = game.data.pokemon
  local byIndex = pokemon and pokemon.byIndex
  if type(byIndex) ~= "table" then return 0 end
  for species, row in pairs(byIndex) do
    local sid = tonumber(species)
    if sid and sid > 0 and type(row) == "table" then
      local nat = tonumber(row.nationalDex) or speciesNational(game, sid)
      if nat then
        local f = frontByNat[nat]
        local b = backByNat[nat]
        if f and f.path and isAllowedBattleSource(f.sourceClass, f.path) then
          pack.fronts[sid] = f.path
          n = n + 1
        end
        if b and b.path and isAllowedBattleSource(b.sourceClass, b.path) then
          pack.backs[sid] = b.path
          n = n + 1
        end
      end
    end
  end
  game.battlePicCache = {}
  return n
end

local function clearOrasBattlePicCacheEntries(game)
  if not (game and type(game.battlePicCache) == "table") then return end
  local drop = {}
  for k in pairs(game.battlePicCache) do
    if type(k) == "string" and k:sub(1, 5) == "oras:" then
      drop[#drop + 1] = k
    end
  end
  for i = 1, #drop do
    game.battlePicCache[drop[i]] = nil
  end
end

-- Wrap Game3.battlePic as an ADDITIVE overlay. Stock encounters tables and
-- Assets/CacheFs Gen3 images stay untouched unless opts.patchPaths is set.
function M.installBattlePicHook(frontByNat, backByNat, enabled)
  local ok, Game3 = pcall(require, "src.core.Game3")
  if not ok or type(Game3) ~= "table" or type(Game3.battlePic) ~= "function" then
    return false, "Game3.battlePic unavailable"
  end
  if enabled == nil then enabled = next(frontByNat or {}) ~= nil or next(backByNat or {}) ~= nil end
  Game3._orasFrontByNat = frontByNat or {}
  Game3._orasBackByNat = backByNat or {}
  Game3._orasBattlePicEnabled = enabled and true or false
  if Game3._orasBattlePicWrapped then
    return true, "refreshed"
  end
  local orig = Game3.battlePic
  Game3._orasBattlePicOrig = orig
  function Game3:battlePic(species, which, shiny)
    if not Game3._orasBattlePicEnabled then
      return orig(self, species, which, shiny)
    end
    species = tonumber(species)
    if species then
      local nat = speciesNational(self, species) or species
      local bucket = (which == "back") and Game3._orasBackByNat or Game3._orasFrontByNat
      local row = bucket and bucket[nat]
      if row and type(row.path) == "string"
          and isAllowedBattleSource(row.sourceClass, row.path) then
        self.battlePicCache = self.battlePicCache or {}
        local key = "oras:" .. (shiny and "shiny:" or "") .. tostring(which) .. ":" .. species
        if self.battlePicCache[key] ~= nil then
          return self.battlePicCache[key] or nil
        end
        local img = self.grabImage and self:grabImage(normalizeImagePath(row.path))
        if img then img = fitBattleSlot(img, row.sourceClass) end
        -- Cache under oras: keys only -- never overwrite stock GBA cache slots.
        self.battlePicCache[key] = img or false
        if img then return img end
      end
    end
    return orig(self, species, which, shiny)
  end
  Game3._orasBattlePicWrapped = true
  return true, nil
end

function M.disableBattlePicHook(game)
  local ok, Game3 = pcall(require, "src.core.Game3")
  if ok and type(Game3) == "table" then
    Game3._orasBattlePicEnabled = false
    Game3._orasFrontByNat = {}
    Game3._orasBackByNat = {}
  end
  if game then
    clearOrasBattlePicCacheEntries(game)
    -- Also drop sticky false/miss entries so stock reloads cleanly.
    if game.battlePicCache then game.battlePicCache = {} end
  end
  return true
end

-- Provisional: Elite Four / Steven mugshot transitions use ORAS a/1/6/0 sheets.
function M.installMugshotHook(mugshotPaths, enabled)
  if type(mugshotPaths) ~= "table" or #mugshotPaths == 0 then
    return false, "no mugshots"
  end
  local ok, Game3 = pcall(require, "src.core.Game3")
  if not ok or type(Game3) ~= "table" then
    return false, "Game3 unavailable"
  end
  if type(Game3.buildMugshotState) ~= "function" then
    return false, "buildMugshotState unavailable"
  end
  Game3._orasMugshotPaths = mugshotPaths
  if enabled == nil then enabled = true end
  Game3._orasMugshotEnabled = enabled and true or false
  if Game3._orasMugshotWrapped then return true, "refreshed" end
  local orig = Game3.buildMugshotState
  Game3._orasMugshotOrig = orig
  function Game3:buildMugshotState(transitionId, npc)
    local state = orig(self, transitionId, npc)
    if not Game3._orasMugshotEnabled then return state end
    local paths = Game3._orasMugshotPaths
    if type(state) == "table" and type(paths) == "table" then
      local mi = tonumber(state.index) or 0
      local path = paths[mi + 1] or paths[1]
      if path and self.grabImage then
        local img = self:grabImage(normalizeImagePath(path))
        if img then state.opponent = img end
      end
    end
    return state
  end
  Game3._orasMugshotWrapped = true
  return true, nil
end

function M.disableMugshotHook()
  local ok, Game3 = pcall(require, "src.core.Game3")
  if ok and type(Game3) == "table" then
    Game3._orasMugshotEnabled = false
    Game3._orasMugshotPaths = nil
  end
  return true
end

-- Restore stock GBA battle pics immediately (no reimport). Safe to call often.
function M.clearTextures(game)
  M.disableBattlePicHook(game)
  M.disableMugshotHook()
  local restored = M.restoreEncounterPaths(game)
  M.scrubBodyUvEncounterPaths(game)
  return restored
end

-- Legacy no-op-ish API kept for main.lua call sites that pass status only.
function M.applyTextures(mod, status, opts)
  opts = opts or {}
  local Extract = opts.Extract
  if not Extract then
    return 0, "Extract module required"
  end
  local front, back, mugshots, sourceClass, iconCandidates =
    M.resolveMaps(mod, status, Extract)
  front = normalizeBucket(front)
  back = normalizeBucket(back)
  mugshots = normalizeMugshots(mugshots)
  local frontN, backN = 0, 0
  local sampleClass, samplePath = nil, nil
  for nat, row in pairs(front) do
    frontN = frontN + 1
    if not samplePath and row and row.path then
      samplePath = row.path
      sampleClass = row.sourceClass or sourceClass
    end
  end
  for _ in pairs(back) do backN = backN + 1 end

  local game = opts.game or (mod and mod.game)
  if game then M.snapshotEncounterPaths(game) end

  local mugOk, mugErr = false, "skipped"
  if frontN == 0 then
    -- Do not fall back to body UV. Leave Gen3 battle pics alone.
    M.clearTextures(game)
    if type(mugshots) == "table" and #mugshots > 0 and opts.applyMugshots ~= false then
      mugOk, mugErr = M.installMugshotHook(mugshots, true)
    end
    return 0, nil, {
      nationalFront = 0,
      nationalBack = 0,
      mugshots = type(mugshots) == "table" and #mugshots or 0,
      battlePicHook = false,
      battlePicHookErr = "no battle sprites (ORAS is 3D; Body UV excluded; stock GBA kept)",
      mugshotHook = mugOk and true or false,
      mugshotHookErr = mugErr,
      gamePatched = 0,
      samplePath = nil,
      sampleLoadOk = 0,
      sourceClass = sourceClass or "none",
      iconCandidates = iconCandidates or 0,
      note = "battle pics unchanged (Gen3 stock); ORAS is additive 3D only",
    }
  end

  mugOk, mugErr = M.installMugshotHook(mugshots, true)
  local hooked, hookErr = M.installBattlePicHook(front, back, true)

  -- Default: do NOT mutate encounters.fronts/backs. Hook overlay is enough.
  -- opts.patchPaths=true restores the old permanent-table behavior if needed.
  local patched = 0
  if game and opts.patchPaths then
    patched = M.patchEncounterPaths(game, front, back)
  elseif game then
    -- Ensure any prior permanent patches from older builds are undone.
    M.restoreEncounterPaths(game)
    M.scrubBodyUvEncounterPaths(game)
    clearOrasBattlePicCacheEntries(game)
  end

  local loadOk, loadSample = 0, nil
  local sample = front[1] or front[255] or front[4]
  if sample and type(sample.path) == "string" and game and game.grabImage then
    loadSample = sample.path
    sampleClass = sample.sourceClass or sampleClass
    local img = game:grabImage(normalizeImagePath(sample.path))
    if img then
      img = fitBattleSlot(img, sample.sourceClass)
      if img then loadOk = 1 end
    end
  end

  return patched, nil, {
    nationalFront = frontN,
    nationalBack = backN,
    mugshots = type(mugshots) == "table" and #mugshots or 0,
    battlePicHook = hooked and true or false,
    battlePicHookErr = hookErr,
    mugshotHook = mugOk and true or false,
    mugshotHookErr = mugErr,
    gamePatched = patched,
    samplePath = loadSample or samplePath,
    sampleLoadOk = loadOk,
    sourceClass = sampleClass or sourceClass or "none",
    iconCandidates = iconCandidates or 0,
    note = patched > 0 and "patched encounters (opt-in)" or "additive battlePic overlay only; stock tables pristine",
  }
end

return M
