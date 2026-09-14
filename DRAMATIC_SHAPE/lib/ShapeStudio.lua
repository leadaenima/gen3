-- Shape Studio: in-game voxel shape editor overlay (presentational only).
-- Toggle with F8 while the voxel pipeline is on.

local V = ...

local ModSetting = V.require("ModSetting")
local Overrides = V.require("ShapeOverrides")
local Picker = V.require("ShapePicker")
local TileShape = V.require("TileShape")
local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local Gen3 = V.require("Gen3")

local TouchUI
local function Touch()
  if TouchUI == false then return nil end
  if TouchUI then return TouchUI end
  local ok, mod = pcall(V.require, "ShapeStudioTouch")
  if ok and type(mod) == "table" then
    TouchUI = mod
  else
    TouchUI = false
  end
  return TouchUI or nil
end

local Studio = {}

Studio.setting = ModSetting.new(
  "shapeStudioHint", "SHAPE STUDIO",
  { false, true }, { "OFF", "F8/MAP" }, 2)

Studio.active = false
Studio.mode = "tile"          -- "tile" | "sprite"
Studio.dragPaint = false
Studio.chromaDrop = false
Studio.texDrop = false
Studio.helpOpen = false
Studio.previewFail = nil      -- why preview is empty (shown in panel)
Studio.status = ""
Studio.statusT = 0
Studio.selection = nil        -- inspect table
Studio.edit = {               -- working values for HUD
  class = "ground",
  h = 0,
  art = "flat",
  zOff = 0,
  yOff = 0,
  chromaTol = 32,
  tex = nil,              -- { tileset, metatile } or { tileset, tiles={..} }
}
Studio.lastPoses = {}         -- sprite poses from last frame (for picking)
Studio.panel = { x = 0, y = 0, w = 112, h = 160 }
Studio.preview = nil          -- ImageData for eyedropper
Studio.previewImg = nil
Studio.hoverBtn = nil
Studio.rectAnchor = nil       -- {cx,cy,canvasX,canvasY} potential drag start
Studio.levelMode = false      -- L key: sticky always-drag = level (optional)
Studio.levelDrag = nil        -- {x0,y0,x1,y1} canvas cells while dragging
Studio.bakeSnapshot = nil     -- last successful bake / open baseline
Studio.needImmediateRemesh = false  -- first nudge after select remeshes now

local CLASS_LIST = {}
local ART_LIST = { "flat", "top", "upright", "billboard", "post", "grass",
                   "cylinder", "relief", "bookcase", "stair" }

local function rebuildClassList()
  CLASS_LIST = {}
  local info = TileShape.CLASS_INFO or {}
  for class in pairs(info) do CLASS_LIST[#CLASS_LIST + 1] = class end
  table.sort(CLASS_LIST)
  if #CLASS_LIST == 0 then
    CLASS_LIST = { "ground", "water", "fence", "grass", "wall", "tree",
                   "sign", "cliff", "bridge", "log", "slope", "ledge" }
  end
end

local function say(msg)
  Studio.status = tostring(msg or "")
  Studio.statusT = 3.5
end

-- Live remesh: drop debounce. Studio edits must update the drawn mesh this
-- frame (brief flash OK). invalidate + synchronous ChunkMesher.get.
local pendingRemeshT = 0
local pendingRemeshMap = nil
local pendingRemeshAll = false

local function currentMap()
  local okG, Game = pcall(require, "src.core.Game")
  local ow = okG and Game and Game.overworld
  return ow and ow.map or nil
end

local function forceUrgentRebuild(mapId)
  local ok = false
  pcall(function()
    local ChunkMesher = V.require("ChunkMesher")
    local map = currentMap()
    if not map then return end
    local id = mapId or map.id
    -- Bump rules tag so disk cache cannot revive pre-edit vertices.
    if ChunkMesher.setCacheRulesTag then
      ChunkMesher.setCacheRulesTag(Overrides.signature())
    end
    pcall(function()
      local DiskCache = V.require("VoxelDiskCache")
      if DiskCache and DiskCache.setRulesTag then
        DiskCache.setRulesTag(Overrides.signature())
      end
    end)
    -- Hard drop: Structures.forMap re-runs (ShapeStudio zOff/class stamp).
    if ChunkMesher.invalidate then
      ChunkMesher.invalidate(id)
    end
    -- Synchronous rebuild into the cache so this frame / next draw sees it.
    if ChunkMesher.get then
      ChunkMesher.get(map, false, nil)
      ok = true
    else
      ChunkMesher.request(map, false, nil, true)
      for _ = 1, 64 do
        if ChunkMesher.pending and ChunkMesher.pending() == 0 then break end
        ChunkMesher.pump(true)
      end
      ok = true
    end
  end)
  return ok
end

local function flushRemesh()
  if not pendingRemeshAll and pendingRemeshMap == nil and pendingRemeshT <= 0 then
    return
  end
  local all = pendingRemeshAll
  local id = pendingRemeshMap
  pendingRemeshAll = false
  pendingRemeshMap = nil
  pendingRemeshT = 0
  if all then
    Overrides.refreshGeometry(nil)
  else
    Overrides.refreshGeometry(id)
  end
  local ok = forceUrgentRebuild(id)
  local h = Studio.edit and Studio.edit.h
  if h ~= nil then
    say(string.format("h=%s remesh %s", tostring(h), ok and "ok" or "fail"))
  else
    say(ok and "remesh ok" or "remesh fail")
  end
end

-- Soft + heavy both rebuild NOW while Studio is open (1-frame coalesce max).
local function applyLive(mapId, opts)
  opts = opts or {}
  if opts.spriteYOff then
    return
  end
  Studio.needImmediateRemesh = false
  pendingRemeshAll = false
  pendingRemeshMap = nil
  pendingRemeshT = 0
  if opts.heavy then
    Overrides.invalidateMeshes(mapId, opts)
  else
    Overrides.refreshGeometry(mapId)
  end
  local ok = forceUrgentRebuild(mapId)
  local h = Studio.edit and Studio.edit.h
  if h ~= nil then
    say(string.format("h=%s remesh %s", tostring(h), ok and "ok" or "fail"))
  elseif opts.heavy then
    say(ok and "remesh ok" or "remesh fail")
  end
end

local function rememberBakeSnapshot()
  if Overrides.captureSnapshot then
    Studio.bakeSnapshot = Overrides.captureSnapshot()
  end
end

local function bakeNow(reason)
  local ok, note = Overrides.bake()
  if ok then
    rememberBakeSnapshot()
    say(string.format("autosaved disk:%s", tostring(note or reason or "")))
  else
    say(string.format("SAVE FAILED: %s", tostring(note or "unknown")))
  end
  return ok, note
end

-- Autosave status once after debounce lands.
pcall(function()
  Overrides.onPersisted(function(ok, note)
    if ok then
      rememberBakeSnapshot()
      say("autosaved disk:" .. tostring(note or ""))
    else
      say("SAVE FAILED: " .. tostring(note or ""))
    end
  end)
end)

local LOUPE_SRC = 9
local loupeData = nil
local loupeImg = nil
local loupeOriginX, loupeOriginY = 0, 0
local chromaHover = nil  -- {r,g,b,a}

local function releaseLoupe()
  loupeData = nil
  if loupeImg and loupeImg.release then pcall(loupeImg.release, loupeImg) end
  loupeImg = nil
  chromaHover = nil
end

local function isLimeIsh(r, g, b)
  -- 0..255
  return g >= 160 and r <= 90 and b <= 90 and g >= r * 2 and g >= b * 2
end

local function sampleCanvasAt(cx, cy)
  local c = Voxel3D.canvas and Voxel3D.canvas()
  local cw, ch = Voxel3D.size()
  if not (c and cw and ch and cw > 0 and ch > 0) then return nil end
  local ix = math.floor(cx + 0.5)
  local iy = math.floor(cy + 0.5)
  if ix < 0 or iy < 0 or ix >= cw or iy >= ch then return nil end
  local half = math.floor(LOUPE_SRC / 2)
  local x0 = math.max(0, math.min(cw - LOUPE_SRC, ix - half))
  local y0 = math.max(0, math.min(ch - LOUPE_SRC, iy - half))
  local ok, data = pcall(function()
    return c:newImageData(x0, y0, LOUPE_SRC, LOUPE_SRC)
  end)
  if not (ok and data) then
    -- Full-canvas fallback when region readback is unavailable.
    ok, data = pcall(function() return c:newImageData() end)
    if not (ok and data) then return nil end
    x0, y0 = 0, 0
  end
  loupeData = data
  loupeOriginX, loupeOriginY = x0, y0
  if loupeImg and loupeImg.release then pcall(loupeImg.release, loupeImg) end
  local okImg, img = pcall(love.graphics.newImage, data)
  if okImg and img then
    pcall(img.setFilter, img, "nearest", "nearest")
    loupeImg = img
  else
    loupeImg = nil
  end
  local lx = ix - x0
  local ly = iy - y0
  local dw, dh = data:getDimensions()
  if lx < 0 then lx = 0 end
  if ly < 0 then ly = 0 end
  if lx >= dw then lx = dw - 1 end
  if ly >= dh then ly = dh - 1 end
  local r, g, b, a = data:getPixel(lx, ly)
  if r <= 1 and g <= 1 and b <= 1 then
    r, g, b = r * 255, g * 255, b * 255
    if a and a <= 1 then a = a * 255 end
  end
  a = a or 255
  r = math.floor(r + 0.5)
  g = math.floor(g + 0.5)
  b = math.floor(b + 0.5)
  chromaHover = { r = r, g = g, b = b, a = a, ix = ix, iy = iy }
  return chromaHover
end

local function applyChromakeyRGB(r, g, b, mapId)
  local tol = math.max(tonumber(Studio.edit.chromaTol) or 32, 28)
  local s = Studio.selection
  local scopes = {}
  local seen = {}
  local function addScope(scope)
    scope = tostring(scope)
    if seen[scope] then return end
    seen[scope] = true
    scopes[#scopes + 1] = scope
  end
  if s and s.kind == "sprite" and s.sheet then
    addScope(s.sheet)
  elseif s and s.tileset then
    addScope(s.tileset)
  end
  -- Lime-like fence/grass keys: always punch globally so every sheet gets it.
  if isLimeIsh(r, g, b) or #scopes == 0 then
    addScope("*")
  end
  local first = true
  for _, scope in ipairs(scopes) do
    Overrides.addChromakey(scope, r, g, b, tol, first)
    first = false
  end
  if isLimeIsh(r, g, b) then
    for _, c in ipairs({ {0,255,0}, {0,248,0}, {24,248,24}, {0,232,0} }) do
      Overrides.addChromakey("*", c[1], c[2], c[3], tol, false)
    end
    -- Nearby loupe pixels: catch daytint / filter drift off the exact click.
    if loupeData then
      local dw, dh = loupeData:getDimensions()
      for yy = 0, dh - 1 do
        for xx = 0, dw - 1 do
          local rr, gg, bb, aa = loupeData:getPixel(xx, yy)
          if rr <= 1 and gg <= 1 and bb <= 1 then
            rr, gg, bb = rr * 255, gg * 255, bb * 255
            if aa and aa <= 1 then aa = aa * 255 end
          end
          aa = aa or 255
          if aa >= 8 then
            rr = math.floor(rr + 0.5)
            gg = math.floor(gg + 0.5)
            bb = math.floor(bb + 0.5)
            if isLimeIsh(rr, gg, bb) then
              Overrides.addChromakey("*", rr, gg, bb, tol, false)
            end
          end
        end
      end
    end
  end
  applyLive(mapId, { heavy = true })
  bakeNow("chromakey")
  say(string.format("chromakey +(%d,%d,%d) tol=%d  C: click the GREEN you see",
    r, g, b, tol))
end

local function gameRef()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game or nil
end

local function overworld()
  local G = gameRef()
  return G and G.overworld
end

local function voxelOn()
  return Voxel.active and Voxel.active()
end

local function clearGameplayInput()
  local G = gameRef()
  local input = G and G.input
  if input and input.reset then
    pcall(function() input:reset() end)
  end
  local ow = overworld()
  if ow then
    ow.joyLatch = nil
    local p = ow.player
    if p then
      -- Drop any in-progress step so Studio click-drag cannot finish a walk.
      if p.moving then
        p.moving = false
        p.walkTimer = 0
        p.walkCount = 0
      end
    end
  end
  if love and love.mouse and love.mouse.setRelativeMode then
    pcall(love.mouse.setRelativeMode, false)
  end
end

local function freezePlayer(on)
  local ow = overworld()
  local p = ow and ow.player
  if p then p.inputLocked = on and true or false end
  if on then
    clearGameplayInput()
    -- Virtual pad must not inject A/B/Select while editing.
    pcall(function()
      local TC = require("src.core.TouchControls")
      if TC then
        Studio._padPrevEnabled = TC.enabled
        TC.enabled = false
        if TC.reset then TC:reset() end
      end
    end)
  else
    pcall(function()
      local TC = require("src.core.TouchControls")
      if TC and Studio._padPrevEnabled ~= nil then
        TC.enabled = Studio._padPrevEnabled
        Studio._padPrevEnabled = nil
      end
    end)
  end
end

-- Outermost OW input guard (installed lazily so it sits outside Horde/SELECT).
local function ensureOutermostInputGuard()
  if Studio._owGuard then return end
  local OverworldState = require("src.world.OverworldController")
  local inner = OverworldState.handleInput
  function OverworldState:handleInput(...)
    if Studio.active then return end
    return inner(self, ...)
  end
  if OverworldState.useBicycle then
    local innerBike = OverworldState.useBicycle
    function OverworldState:useBicycle(...)
      if Studio.active then return false end
      return innerBike(self, ...)
    end
  end
  Studio._owGuard = true
end

function Studio.toggle()
  if Studio.active then
    Studio.active = false
    freezePlayer(false)
    Studio.chromaDrop = false
    Studio.texDrop = false
    Studio.helpOpen = false
    Studio.dragPaint = false
    Studio.levelMode = false
    Studio.levelDrag = nil
    releaseLoupe()
    flushRemesh()
    -- F8 close: discard unpersisted memory vs last successful bake snapshot.
    -- Do NOT wipe a successful disk save. Do NOT force-bake on close.
    local discarded = false
    if Overrides.isDirty and Overrides.isDirty() and Studio.bakeSnapshot
       and Overrides.restoreSnapshot then
      Overrides.restoreSnapshot(Studio.bakeSnapshot, false)
      applyLive(nil, { immediate = true })
      discarded = true
    end
    say(discarded and "Shape Studio closed (discarded unsaved)"
      or "Shape Studio closed")
    do
      local T = Touch()
      if T and T.onStudioClosed then T.onStudioClosed() end
    end
    return
  end
  if not voxelOn() then
    say("Shape Studio needs voxel mode (press 3)")
    return
  end
  rebuildClassList()
  Studio.active = true
  freezePlayer(true)
  -- Baseline = last bake (or current memory after load). Closing without
  -- bake restores this; closing after bake keeps edits.
  if not Studio.bakeSnapshot and Overrides.captureSnapshot then
    rememberBakeSnapshot()
  elseif Overrides.captureSnapshot and not (Overrides.isDirty and Overrides.isDirty()) then
    rememberBakeSnapshot()
  end
  say("Shape Studio — drag = level to player height; click = select")
  ensureOutermostInputGuard()
  clearGameplayInput()
  do
    local T = Touch()
    if T and T.onStudioOpened then T.onStudioOpened() end
  end
end

function Studio.isActive()
  return Studio.active
end

-- ---- selection / edit sync ----

local function syncEditFromSelection()
  local s = Studio.selection
  if not s then return end
  if s.kind == "cell" then
    Studio.edit.class = s.class or "ground"
    Studio.edit.h = s.h or 0
    Studio.edit.art = s.art or "flat"
    Studio.edit.zOff = s.zOff or 0
    local applied = nil
    if s.cellOverride and type(s.cellOverride.tex) == "table" then
      applied = s.cellOverride.tex
    elseif s.tex then
      applied = s.tex
    end
    Studio.edit.tex = applied
  elseif s.kind == "sprite" then
    Studio.edit.yOff = s.yOff or 0
  end
end

local function refreshSelectionCell(map, cx, cy)
  Studio.selection = Picker.inspectCell(map, cx, cy)
  syncEditFromSelection()
  Studio:loadPreview()
end

-- Resolve ImageData for a path (ImageCache, then Assets).
local function imageDataForPath(path)
  if not path then return nil end
  local okIC, ImageCache = pcall(V.require, "ImageCache")
  if okIC and ImageCache and ImageCache.get then
    local d = ImageCache.get(path)
    if d then return d end
  end
  local ok, Assets = pcall(require, "src.render.Assets")
  if ok and Assets and Assets.imageData then
    local ok2, d = pcall(Assets.imageData, path)
    if ok2 and d then return d end
  end
  return nil
end

-- Paste one 8x8 tile from a linear atlas into a 16x16 crop at (dx,dy).
local function pasteTile8(dst, src, tileId, perRow, dx, dy)
  if not (dst and src and tileId ~= nil) then return end
  perRow = perRow or 16
  local ax = (tileId % perRow) * 8
  local ay = math.floor(tileId / perRow) * 8
  local sw, sh = src:getDimensions()
  if ax < 0 or ay < 0 or ax + 8 > sw or ay + 8 > sh then return end
  pcall(dst.paste, dst, src, dx, dy, ax, ay, 8, 8)
end

-- Build a 16x16 metatile crop from the Gen3 linear (8px-tile) atlas.
local function cropMetatileFromLinear(atlasData, metatile, perRow)
  if not (atlasData and metatile ~= nil and love.image and love.image.newImageData) then
    return nil
  end
  perRow = perRow or 16
  local m = tonumber(metatile) or 0
  local crop = love.image.newImageData(16, 16)
  -- q0 TL, q1 TR, q2 BL, q3 BR — same order as Gen3.tileId / bakeLinear
  pasteTile8(crop, atlasData, m * 4 + 0, perRow, 0, 0)
  pasteTile8(crop, atlasData, m * 4 + 1, perRow, 8, 0)
  pasteTile8(crop, atlasData, m * 4 + 2, perRow, 0, 8)
  pasteTile8(crop, atlasData, m * 4 + 3, perRow, 8, 8)
  return crop
end

-- Gen1/2: assemble the cell's four 8px tiles into a 16x16 crop.
local function cropCellFromSheet(sheetData, map, cx, cy, perRow)
  if not (sheetData and map and love.image and love.image.newImageData) then
    return nil
  end
  perRow = perRow or (map.tileset and map.tileset.tilesPerRow) or 16
  local crop = love.image.newImageData(16, 16)
  local ok = false
  for dy = 0, 1 do
    for dx = 0, 1 do
      local tx, ty = cx * 2 + dx, cy * 2 + dy
      local t = Gen3.tileAt(map, tx, ty)
      if t ~= nil then
        pasteTile8(crop, sheetData, t, perRow, dx * 8, dy * 8)
        ok = true
      end
    end
  end
  return ok and crop or nil
end

-- Pair-sheet fallback: 16x16 metatile grid (SHEET_COLS). Prefer bottom.
local function cropFromPairSheets(map, metatile)
  if metatile == nil or not (love.image and love.image.newImageData) then return nil end
  local ts = map and map.tileset
  if not ts then return nil end
  local cols = Gen3.SHEET_COLS or 16
  local m = tonumber(metatile) or 0
  local sx = (m % cols) * 16
  local sy = math.floor(m / cols) * 16
  local paths = {}
  local id = tostring(ts.id or ts.image or "")
  if id ~= "" and id ~= "nil" then
    paths[#paths + 1] = id
    if not id:find("_bottom", 1, true) then
      paths[#paths + 1] = id .. "_bottom.png"
      paths[#paths + 1] = id .. "_bottom"
    end
  end
  if type(ts.image) == "string" then paths[#paths + 1] = ts.image end
  if type(ts.bottom) == "string" then paths[#paths + 1] = ts.bottom end
  -- Engine world may publish sheet images; try reading pixels if ImageData-like
  local ctx = Gen3.forMap(map)
  if ctx then
    for _, key in ipairs({ "bottom", "top" }) do
      local img = ctx[key]
      if type(img) == "userdata" and img.getPixel then
        local sw, sh = img:getDimensions()
        if sx + 16 <= sw and sy + 16 <= sh then
          local crop = love.image.newImageData(16, 16)
          pcall(crop.paste, crop, img, 0, 0, sx, sy, 16, 16)
          return crop
        end
      end
    end
  end
  for _, path in ipairs(paths) do
    local data = imageDataForPath(path)
    if data then
      local sw, sh = data:getDimensions()
      if sx + 16 <= sw and sy + 16 <= sh then
        local crop = love.image.newImageData(16, 16)
        pcall(crop.paste, crop, data, 0, 0, sx, sy, 16, 16)
        return crop
      end
    end
  end
  return nil
end

-- Most frequent opaque non-near-black color in a small ImageData (chromakey).
local function dominantKeyColor(data)
  if not data or not data.getPixel then return nil end
  local w, h = data:getDimensions()
  local counts = {}
  local best, bestN = nil, 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      if r <= 1 and g <= 1 and b <= 1 then
        r, g, b = r * 255, g * 255, b * 255
        if a and a <= 1 then a = a * 255 end
      end
      a = a or 255
      if a > 8 then
        r = math.floor(r + 0.5)
        g = math.floor(g + 0.5)
        b = math.floor(b + 0.5)
        -- skip near-black / near-transparent fillers
        if (r + g + b) >= 40 then
          local k = r * 65536 + g * 256 + b
          local n = (counts[k] or 0) + 1
          counts[k] = n
          if n > bestN then
            bestN = n
            best = { r = r, g = g, b = b }
          end
        end
      end
    end
  end
  return best
end

local function setPreviewCrop(self, data, label)
  self.preview = data
  self.previewFail = nil
  if data then
    local ok, img = pcall(love.graphics.newImage, data)
    if ok and img then
      img:setFilter("nearest", "nearest")
      self.previewImg = img
      return true
    end
  end
  self.previewFail = label or "NO PREVIEW"
  return false
end

function Studio:loadPreview()
  self.preview = nil
  self.previewFail = nil
  if self.previewImg then
    pcall(function() self.previewImg:release() end)
    self.previewImg = nil
  end
  local s = self.selection
  if not s then return end

  -- Sprites: show the sheet (full), still clickable for chromakey.
  if s.kind == "sprite" and s.sheet then
    local data = imageDataForPath(s.sheet)
    if data then
      setPreviewCrop(self, data, nil)
      return
    end
    self.previewFail = "NO PREVIEW sheet"
    say("NO PREVIEW: " .. tostring(s.sheet))
    return
  end

  if s.kind ~= "cell" then return end
  local ow = overworld()
  local map = ow and ow.map
  if not map then
    self.previewFail = "NO PREVIEW (no map)"
    return
  end
  local ts = map.tileset
  local tsId = ts and (ts.id or ts.image) or "?"
  local meta = s.metatile
  if Studio.edit.tex and Studio.edit.tex.metatile ~= nil then
    meta = Studio.edit.tex.metatile
  end

  -- 1) Prefer the live Gen3 / voxel atlas pixels ChunkMesher samples.
  local atlasData = nil
  if Gen3.mapIsGen3 and Gen3.mapIsGen3(map) then
    local ok, d = pcall(Gen3.atlasData, map)
    if ok then atlasData = d end
  end
  if not atlasData then
    -- TerrainAtlas path: Gen3.atlasDataForTileset / atlasData still preferred;
    -- for Gen1/2 try tileset art (same bake base as TerrainAtlas).
    if Gen3.atlasDataForTileset and ts and Gen3.isGen3 and Gen3.isGen3(ts) then
      local ok, d = pcall(Gen3.atlasDataForTileset, ts)
      if ok then atlasData = d end
    end
  end

  local crop = nil
  if atlasData and meta ~= nil then
    local perRow = 16
    if Gen3.atlasInfoFor and ts then
      local info = Gen3.atlasInfoFor(ts)
      if info and info.perRow then perRow = info.perRow end
    end
    crop = cropMetatileFromLinear(atlasData, meta, perRow)
  end

  -- 2) Else Gen3 pair / bottom sheet via Assets (16x16 metatile grid).
  if not crop and meta ~= nil then
    crop = cropFromPairSheets(map, meta)
  end

  -- 3) Else classic tileset.image / four 8px tiles for this cell.
  if not crop then
    local path = ts and ts.image
    local sheet = path and imageDataForPath(path) or nil
    if sheet then
      if meta ~= nil and Gen3.mapIsGen3 and Gen3.mapIsGen3(map) then
        local perRow = (ts and ts.tilesPerRow) or 16
        crop = cropMetatileFromLinear(sheet, meta, perRow)
      else
        crop = cropCellFromSheet(sheet, map, s.cx, s.cy, ts and ts.tilesPerRow)
        -- If cell tile assembly failed, fall back to a top-left zoom of sheet
        -- only when sheet is already tiny; otherwise still fail loudly.
        if not crop and sheet:getWidth() <= 64 and sheet:getHeight() <= 64 then
          crop = sheet
        end
      end
    end
  end

  if crop then
    setPreviewCrop(self, crop, nil)
    return
  end

  self.previewFail = string.format("NO PREVIEW ts=%s", tostring(tsId))
  say(self.previewFail)
end

local function patchFromEdit()
  local p = {
    class = Studio.edit.class,
    h = Studio.edit.h,
    art = Studio.edit.art,
    zOff = Studio.edit.zOff,
  }
  if Studio.edit.tex ~= nil then
    p.tex = Studio.edit.tex
  end
  return p
end


local function sameTileset(a, b)
  if a == nil or b == nil then return true end
  return tostring(a) == tostring(b)
end

-- Build a tex override from a source cell (eyedropper sample).
local function texFromCell(map, cx, cy)
  local tsId = map.tileset and (map.tileset.id or map.tileset.image)
  local Gen3 = V.require("Gen3")
  if Gen3.mapIsGen3 and Gen3.mapIsGen3(map) then
    local ctx = Gen3.forMap(map)
    if not (ctx and ctx.metatileAt) then return nil, "no metatileAt" end
    local ok, m = pcall(ctx.metatileAt, cx, cy)
    if not ok or m == nil then return nil, "no metatile" end
    return { tileset = tsId, metatile = m }
  end
  -- Gen1/2: copy the four 8px tile ids that paint this 16px cell
  local tiles = {}
  for dy = 0, 1 do
    for dx = 0, 1 do
      local tx, ty = cx * 2 + dx, cy * 2 + dy
      local ok, t = pcall(Gen3.tileAt, map, tx, ty)
      if not ok or t == nil then return nil, "no tile" end
      tiles[(ty % 2) * 2 + (tx % 2)] = t
    end
  end
  return { tileset = tsId, tiles = tiles }
end

local function applyTexLive(recordUndo)
  local s = Studio.selection
  local ow = overworld()
  local map = ow and ow.map
  if not (s and s.kind == "cell" and map and Studio.edit.tex) then return end
  Overrides.setCell(map.id, s.cx, s.cy, { tex = Studio.edit.tex }, recordUndo ~= false)
  applyLive(map.id)
end

function Studio.saveThisInstance()
  local s = Studio.selection
  local ow = overworld()
  local map = ow and ow.map
  if not (s and map) then say("nothing selected"); return end
  if s.kind == "cell" then
    Overrides.setCell(map.id, s.cx, s.cy, patchFromEdit())
    applyLive(map.id)
    say(string.format("saved cell %d,%d (this instance)", s.cx, s.cy))
  elseif s.kind == "sprite" then
    local key
    if s.objId ~= nil then
      key = Overrides.spriteInstanceKey(map.id, s.objId)
    else
      say("sprite has no instance id"); return
    end
    Overrides.setSprite(key, { yOff = Studio.edit.yOff })
    applyLive(map.id, { spriteYOff = true })
    say("saved sprite instance yOff=" .. tostring(Studio.edit.yOff))
  end
  syncEditFromSelection()
end

function Studio.saveAllInstances()
  local s = Studio.selection
  local ow = overworld()
  local map = ow and ow.map
  if not (s and map) then say("nothing selected"); return end
  local tsId = s.tileset or (map.tileset and (map.tileset.id or map.tileset.image))
  if s.kind == "cell" then
    local key
    if s.metatile ~= nil then
      key = Overrides.typeKeyMetatile(tsId, s.metatile)
    else
      key = Overrides.typeKeyTile(tsId, s.tile)
    end
    local tp = {
      class = Studio.edit.class,
      h = Studio.edit.h,
      art = Studio.edit.art,
    }
    if Studio.edit.tex ~= nil then tp.tex = Studio.edit.tex end
    Overrides.setType(key, tp)
    applyLive(nil)  -- all maps
    say("saved ALL instances: " .. tostring(key))
  elseif s.kind == "sprite" then
    local key
    if s.sheet then
      key = Overrides.spriteSheetKey(s.sheet)
    elseif s.graphicsId ~= nil then
      key = Overrides.spriteGfxKey(s.graphicsId)
    else
      say("no sheet/gfx to key on"); return
    end
    Overrides.setSprite(key, { yOff = Studio.edit.yOff })
    applyLive(nil, { spriteYOff = true })
    say("saved ALL sprites: " .. tostring(key))
  end
end

function Studio.bake()
  -- Force write now (autosave already covers normal edits).
  local ok, note = bakeNow("key3")
  applyLive(nil, { heavy = true })
  if ok then
    say("force-saved — " .. tostring(note))
  else
    say("SAVE FAILED: " .. tostring(note))
  end
end

function Studio.exportMobile()
  local path, err = Overrides.exportMobile()
  if path then
    say("exported " .. tostring(path))
  else
    say("export failed: " .. tostring(err))
  end
  return path, err
end

function Studio.importMerge(pathOrString)
  local ok, note = Overrides.importMerge(pathOrString)
  if ok then
    applyLive(nil, { heavy = true })
    rememberBakeSnapshot()
    say("Import/Merge OK — " .. tostring(note))
  else
    say("Import/Merge failed: " .. tostring(note))
  end
  return ok, note
end

function Studio.revertSelected()
  local s = Studio.selection
  if not s then say("nothing selected"); return end
  if s.kind == "cell" then
    Overrides.revertSelected("cell", Overrides.cellKey(s.mapId, s.cx, s.cy))
  elseif s.kind == "sprite" then
    if s.objId ~= nil then
      Overrides.revertSelected("sprite",
        Overrides.spriteInstanceKey(s.mapId, s.objId))
    elseif s.sheet then
      Overrides.revertSelected("sprite", Overrides.spriteSheetKey(s.sheet))
    end
  end
  applyLive(s.mapId)
  say("reverted selection override")
  local ow = overworld()
  if s.kind == "cell" and ow and ow.map then
    refreshSelectionCell(ow.map, s.cx, s.cy)
  end
end

local function cycleList(list, cur, dir)
  if #list == 0 then return cur end
  local idx = 1
  for i, v in ipairs(list) do
    if v == cur then idx = i break end
  end
  idx = ((idx - 1 + dir - 1) % #list) + 1
  -- wait, fix modular arithmetic
  idx = idx + dir
  while idx < 1 do idx = idx + #list end
  while idx > #list do idx = idx - #list end
  return list[idx]
end

-- fix cycleList properly
cycleList = function(list, cur, dir)
  if not list or #list == 0 then return cur end
  local idx = 1
  for i, v in ipairs(list) do
    if v == cur then idx = i break end
  end
  idx = idx + (dir or 1)
  if idx < 1 then idx = #list end
  if idx > #list then idx = 1 end
  return list[idx]
end

function Studio.nudgeHeight(delta)
  local s = Studio.selection
  if not s then return end
  if s.kind == "sprite" then
    Studio.edit.yOff = (Studio.edit.yOff or 0) + delta
  else
    Studio.edit.h = (Studio.edit.h or 0) + delta
  end
end

function Studio.nudgeZ(delta)
  Studio.edit.zOff = (Studio.edit.zOff or 0) + delta
end

function Studio.cycleClass(dir)
  Studio.edit.class = cycleList(CLASS_LIST, Studio.edit.class, dir)
  local info = TileShape.CLASS_INFO and TileShape.CLASS_INFO[Studio.edit.class]
  if info then
    if Studio.edit.h == nil then Studio.edit.h = info.h end
    Studio.edit.art = info.art or Studio.edit.art
  end
end

function Studio.cycleArt(dir)
  Studio.edit.art = cycleList(ART_LIST, Studio.edit.art, dir)
end

-- Live-preview: write working edit into the appropriate override scope
-- without requiring an explicit save (save still stamps permanence intent).
function Studio.previewApply(scope)
  local s = Studio.selection
  local ow = overworld()
  local map = ow and ow.map
  if not (s and map) then return end
  if s.kind == "cell" then
    if scope == "type" then
      Studio.saveAllInstances()
    else
      Overrides.setCell(map.id, s.cx, s.cy, patchFromEdit(), false)
      applyLive(map.id)
    end
  elseif s.kind == "sprite" then
    if scope == "type" then
      Studio.saveAllInstances()
    else
      if s.objId ~= nil then
        Overrides.setSprite(Overrides.spriteInstanceKey(map.id, s.objId),
          { yOff = Studio.edit.yOff }, false)
        applyLive(map.id, { spriteYOff = true })
      end
    end
  end
end

-- ---- input ----

function Studio.keypressed(key)
  if key == "f8" then
    Studio.toggle()
    return true
  end
  if not Studio.active then return false end
  if key == "escape" then
    if Studio.helpOpen then
      Studio.helpOpen = false
      say("help closed")
      return true
    end
    if Studio.texDrop then
      Studio.texDrop = false
      say("texture eyedropper cancelled")
      return true
    end
    if Studio.chromaDrop then
      Studio.chromaDrop = false
      releaseLoupe()
      say("chromakey off")
      return true
    end
    if Studio.levelMode then
      Studio.levelMode = false
      Studio.levelDrag = nil
      say("level mode off")
      return true
    end
    Studio.toggle()
    return true
  end
  if key == "h" then
    Studio.helpOpen = not Studio.helpOpen
    say(Studio.helpOpen and "help ON (Esc closes help)" or "help off")
    return true
  end
  if key == "tab" then
    Studio.mode = (Studio.mode == "tile") and "sprite" or "tile"
    say("mode: " .. Studio.mode)
    return true
  end
  if key == "1" then
    Studio.saveThisInstance()
    bakeNow("key1")
    return true
  end
  if key == "2" then
    Studio.saveAllInstances()
    bakeNow("key2")
    return true
  end
  if key == "3" then
    Studio.bake()
    return true
  end
  if key == "l" then
    Studio.levelMode = not Studio.levelMode
    Studio.texDrop = false
    Studio.chromaDrop = false
    say(Studio.levelMode
      and "LEVEL sticky: drag = level to player height"
      or "level mode off (drag still levels)")
    return true
  end
  if key == "z" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
    if Overrides.undo() then
      applyLive(nil)
      say("undo")
    end
    return true
  end
  if key == "r" then Studio.revertSelected(); return true end
  if key == "i" then Studio.importMerge(nil); return true end
  if key == "x" then Studio.exportMobile(); return true end
  if key == "c" then
    Studio.chromaDrop = not Studio.chromaDrop
    Studio.texDrop = false
    if not Studio.chromaDrop then releaseLoupe() end
    say(Studio.chromaDrop
      and "C: click the GREEN you see (fence gaps)"
      or "chromakey eyedropper off")
    return true
  end
  if key == "t" then
    local s = Studio.selection
    if not (s and s.kind == "cell") then
      say("select a cell first, then T")
      return true
    end
    Studio.texDrop = not Studio.texDrop
    Studio.chromaDrop = false
    say(Studio.texDrop
      and "TEXTURE: click a cell to copy its metatile art"
      or "texture eyedropper off")
    return true
  end
  if (key == "," or key == ".") and Studio.selection and Studio.selection.kind == "cell" then
    local dir = (key == ".") and 1 or -1
    local cur = Studio.edit.tex and Studio.edit.tex.metatile
    if cur == nil then cur = Studio.selection.metatile end
    if cur ~= nil then
      local tsId = Studio.selection.tileset
      local nu = math.max(0, (tonumber(cur) or 0) + dir)
      Studio.edit.tex = { tileset = tsId, metatile = nu }
      applyTexLive(true)
      say(string.format("tex metatile -> %d", nu))
    else
      say("no metatile to cycle (, .)")
    end
    return true
  end
  if key == "[" or key == "q" then Studio.nudgeHeight(-1); Studio.previewApply(); return true end
  if key == "]" or key == "e" then Studio.nudgeHeight(1); Studio.previewApply(); return true end
  if key == "-" or key == "kp-" then
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
      local s = Studio.selection
      local ow = overworld()
      if s and s.kind == "cell" and s.elevation ~= nil and ow and ow.map then
        local md = Overrides.maps[tostring(ow.map.id)]
        local cur = 0
        if md and md.layerOffsets and md.layerOffsets[s.elevation] then
          cur = md.layerOffsets[s.elevation]
        end
        Overrides.setLayerOffset(ow.map.id, s.elevation, cur - 1)
        applyLive(ow.map.id)
        say("layer elev " .. tostring(s.elevation) .. " z=" .. tostring(cur - 1))
      end
    else
      Studio.nudgeZ(-1); Studio.previewApply()
    end
    return true
  end
  if key == "=" or key == "kp+" then
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
      local s = Studio.selection
      local ow = overworld()
      if s and s.kind == "cell" and s.elevation ~= nil and ow and ow.map then
        local md = Overrides.maps[tostring(ow.map.id)]
        local cur = 0
        if md and md.layerOffsets and md.layerOffsets[s.elevation] then
          cur = md.layerOffsets[s.elevation]
        end
        Overrides.setLayerOffset(ow.map.id, s.elevation, cur + 1)
        applyLive(ow.map.id)
        say("layer elev " .. tostring(s.elevation) .. " z=" .. tostring(cur + 1))
      end
    else
      Studio.nudgeZ(1); Studio.previewApply()
    end
    return true
  end
  if key == "left" then Studio.cycleClass(-1); Studio.previewApply(); return true end
  if key == "right" then Studio.cycleClass(1); Studio.previewApply(); return true end
  if key == "up" then Studio.cycleArt(-1); Studio.previewApply(); return true end
  if key == "down" then Studio.cycleArt(1); Studio.previewApply(); return true end
  -- swallow movement / camera keys while studio owns input
  if key == "w" or key == "a" or key == "s" or key == "d"
     or key == "space" or key == "lshift" or key == "rshift" then
    return true
  end
  return true  -- eat other keys so they don't toggle pipelines mid-edit
end

function Studio.wheelmoved(dx, dy)
  if not Studio.active then return false end
  if dy and dy ~= 0 then
    if Studio.texDrop or (Studio.edit.tex and Studio.edit.tex.metatile ~= nil
        and (love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt"))) then
      local cur = Studio.edit.tex and Studio.edit.tex.metatile
      if cur == nil and Studio.selection then cur = Studio.selection.metatile end
      if cur ~= nil then
        local tsId = Studio.selection and Studio.selection.tileset
        local nu = math.max(0, (tonumber(cur) or 0) + (dy > 0 and 1 or -1))
        Studio.edit.tex = { tileset = tsId, metatile = nu }
        applyTexLive(true)
        say(string.format("tex metatile -> %d", nu))
      end
      return true
    end
    local step = (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")) and 8 or 1
    Studio.nudgeHeight(dy > 0 and step or -step)
    Studio.previewApply()
  end
  return true
end

local function inPanel(x, y)
  local p = Studio.panel
  return x >= p.x and x < p.x + p.w and y >= p.y and y < p.y + p.h
end

local function previewRect()
  local p = Studio.panel
  return p.x + 4, p.y + 78, 48, 48
end

local function hitPreview(cx, cy)
  local x, y, w, h = previewRect()
  return cx >= x and cx < x + w and cy >= y and cy < y + h
end

function Studio.mousepressed(x, y, button)
  if not Studio.active then return false end
  local cx, cy, cw, ch = Picker.mouseToCanvas(x, y)
  Studio.panel.x = (cw or 240) - Studio.panel.w
  Studio.panel.y = 0
  Studio.panel.h = ch or 160

  -- Panel preview is NOT the chromakey path anymore (too small / confusing).
  -- C-mode clicks always sample the world canvas under the cursor.

  if button == 1 and inPanel(cx, cy) then
    -- simple button rows at bottom of panel
    local p = Studio.panel
    local row = math.floor((cy - (p.y + p.h - 60)) / 12)
    if row == 0 then
      Studio.saveThisInstance()
      bakeNow("panel1")
    elseif row == 1 then
      Studio.saveAllInstances()
      bakeNow("panel2")
    elseif row == 2 then
      Studio.bake()
    elseif row == 3 then
      Studio.importMerge(nil)
    elseif row == 4 then
      Studio.exportMobile()
    end
    return true
  end

  local ow = overworld()
  local map = ow and ow.map
  if not map then return true end

  -- Sprite pick: Tab into sprite mode (NOT Shift-click).
  if button == 1 and Studio.mode == "sprite" then
    local ent = Picker.pickSprite(Studio.lastPoses, cx, cy)
    if ent then
      Studio.selection = Picker.inspectSprite(map, ent)
      Studio.selection.actor = ent.actor
      syncEditFromSelection()
      Studio:loadPreview()
      say(string.format("sprite %s", tostring(Studio.selection.sheet or "?")))
    else
      say("no sprite under cursor")
    end
    return true
  end

  if button == 1 and Studio.texDrop then
    local cell = Picker.pickCell(map, cx, cy)
    if not cell then
      say("no cell under cursor")
      return true
    end
    local s = Studio.selection
    if not (s and s.kind == "cell") then
      say("select a target cell first")
      return true
    end
    local srcTex, err = texFromCell(map, cell.cx, cell.cy)
    if not srcTex then
      say("eyedrop failed: " .. tostring(err))
      return true
    end
    local dstTs = s.tileset or (map.tileset and (map.tileset.id or map.tileset.image))
    if not sameTileset(srcTex.tileset, dstTs) then
      say("texture swap: same tileset only")
      return true
    end
    Studio.edit.tex = srcTex
    Studio.texDrop = false
    applyTexLive(true)
    if srcTex.metatile ~= nil then
      say(string.format("tex <- meta %s (press 1/2 to scope; autosaves)",
        tostring(srcTex.metatile)))
    else
      say("tex <- cell tiles (press 1/2 to scope; autosaves)")
    end
    return true
  end

  if button == 1 and Studio.chromaDrop then
    -- Main path: sample the voxel framebuffer pixel under the cursor
    -- (the lime in fence gaps he can see), not a panel crop.
    local hover = sampleCanvasAt(cx, cy)
    if hover and (hover.a or 255) >= 8 then
      local cell = Picker.pickCell(map, cx, cy)
      if cell then refreshSelectionCell(map, cell.cx, cell.cy) end
      applyChromakeyRGB(hover.r, hover.g, hover.b, map and map.id or nil)
      return true
    end
    -- Fallback: metatile crop dominant key if canvas readback failed.
    local cell = Picker.pickCell(map, cx, cy)
    if cell then
      refreshSelectionCell(map, cell.cx, cell.cy)
      Studio:loadPreview()
      local crop = Studio.preview
      local col = crop and dominantKeyColor(crop) or nil
      if col then
        applyChromakeyRGB(col.r, col.g, col.b, map.id)
        return true
      end
    end
    say("C: could not sample — click the GREEN in the 3D view")
    return true
  end

  -- Plain LMB: select immediately; drag (beyond ~half cell) becomes level-rect.
  -- Shift is ignored here so it never bikes / Select via mouse+shift.
  if button == 1 then
    local cell = Picker.pickCell(map, cx, cy)
    if cell then
      refreshSelectionCell(map, cell.cx, cell.cy)
      Studio.needImmediateRemesh = true
      Studio.levelDrag = nil
      Studio.rectAnchor = {
        cx = cell.cx, cy = cell.cy,
        canvasX = cx, canvasY = cy,
      }
      -- Sticky L-mode: treat press as level-drag start immediately.
      if Studio.levelMode then
        Studio.levelDrag = {
          x0 = cell.cx, y0 = cell.cy, x1 = cell.cx, y1 = cell.cy, moved = false,
        }
        Studio.rectAnchor.level = true
        say(string.format("level drag %d,%d …", cell.cx, cell.cy))
      else
        say(string.format("cell %d,%d  %s h=%s", cell.cx, cell.cy,
          tostring(Studio.selection.class), tostring(Studio.selection.h)))
      end
    end
    return true
  end

  return true
end

local function playerTargetY(map)
  local ow = overworld()
  local p = ow and ow.player
  if not (map and p) then return nil, "no player" end
  local pcx = p.cx
  local pcy = p.cy
  if pcx == nil or pcy == nil then
    local px = p.x or p.px or 0
    local py = p.y or p.py or 0
    pcx = math.floor(px / 16)
    pcy = math.floor(py / 16)
  end
  local natural = 0
  pcall(function()
    local Structures = V.require("Structures")
    if Structures.terraceAt then
      local ok, h = pcall(Structures.terraceAt, map, pcx, pcy)
      if ok and type(h) == "number" then natural = h end
    end
  end)
  local z = 0
  if Overrides.zOffFor then
    z = Overrides.zOffFor(map, pcx, pcy) or 0
  end
  return natural + z, pcx, pcy, natural
end

local function naturalTerraceAt(map, cx, cy)
  local natural = 0
  pcall(function()
    local Structures = V.require("Structures")
    if Structures.terraceAt then
      local ok, h = pcall(Structures.terraceAt, map, cx, cy)
      if ok and type(h) == "number" then natural = h end
    end
  end)
  -- Strip studio zOff already baked into synthZ by the forMap wrap by
  -- reading the raw override and subtracting — terraceAt may include it.
  local z = 0
  if Overrides.zOffFor then
    z = Overrides.zOffFor(map, cx, cy) or 0
  end
  return natural - z
end

function Studio.levelRectToPlayer(x0, y0, x1, y1)
  local ow = overworld()
  local map = ow and ow.map
  if not map then say("no map"); return end
  local target, pcx, pcy = playerTargetY(map)
  if target == nil then say("no player height"); return end
  x0, x1 = math.min(x0, x1), math.max(x0, x1)
  y0, y1 = math.min(y0, y1), math.max(y0, y1)
  local n = 0
  for yy = y0, y1 do
    for xx = x0, x1 do
      local nat = naturalTerraceAt(map, xx, yy)
      local zOff = target - nat
      Overrides.setCell(map.id, xx, yy, { zOff = zOff }, n == 0)
      n = n + 1
    end
  end
  applyLive(map.id, { immediate = true })
  bakeNow("level-rect")
  local w, h = (x1 - x0 + 1), (y1 - y0 + 1)
  say(string.format("leveled %dx%d cells to player height", w, h))
end

function Studio.mousereleased(x, y, button)
  if not Studio.active then return false end
  if button == 1 and Studio.levelDrag then
    local cx, cy = Picker.mouseToCanvas(x, y)
    local ow = overworld()
    local map = ow and ow.map
    if map then
      local cell = Picker.pickCell(map, cx, cy)
      local d = Studio.levelDrag
      if cell then
        if cell.cx ~= d.x0 or cell.cy ~= d.y0 then
          d.moved = true
        end
        d.x1, d.y1 = cell.cx, cell.cy
      end
      -- Real drag (past ~half-cell or multi-cell): level rect (1x1 OK).
      if d.moved or (d.x0 ~= d.x1) or (d.y0 ~= d.y1) then
        Studio.levelRectToPlayer(d.x0, d.y0, d.x1, d.y1)
      end
      -- else: plain click — selection already applied on press
    end
    Studio.levelDrag = nil
    Studio.rectAnchor = nil
    return true
  end
  if button == 1 and Studio.rectAnchor then
    -- Released without promoting to levelDrag: select only (done on press).
    Studio.rectAnchor = nil
  end
  return true
end

function Studio.update(dt)
  dt = dt or 0
  do
    local T = Touch()
    if T and T.update then T.update(dt) end
  end
  if Studio.statusT > 0 then
    Studio.statusT = Studio.statusT - dt
    if Studio.statusT <= 0 then Studio.status = "" end
  end
  if Studio.active then
    ensureOutermostInputGuard()
    freezePlayer(true)
    -- FirstPerson re-asserts relative mouse every frame; kill it while editing.
    clearGameplayInput()
  end
  if pendingRemeshT > 0 then
    pendingRemeshT = pendingRemeshT - dt
    if pendingRemeshT <= 0 then flushRemesh() end
  end
  if Overrides.update then Overrides.update(dt) end
  if Studio.active and Studio.chromaDrop and love and love.mouse then
    local mx, my = love.mouse.getPosition()
    local cx, cy = Picker.mouseToCanvas(mx, my)
    sampleCanvasAt(cx, cy)
  elseif loupeData then
    releaseLoupe()
  end
  -- Promote plain click → level-drag once cursor moves ~half a cell (8px).
  if Studio.active and Studio.rectAnchor and not Studio.levelDrag
     and love and love.mouse and love.mouse.isDown and love.mouse.isDown(1) then
    local mx, my = love.mouse.getPosition()
    local cx, cy = Picker.mouseToCanvas(mx, my)
    local a = Studio.rectAnchor
    local dx = (cx or 0) - (a.canvasX or 0)
    local dy = (cy or 0) - (a.canvasY or 0)
    if (dx * dx + dy * dy) >= 64 then
      Studio.levelDrag = {
        x0 = a.cx, y0 = a.cy, x1 = a.cx, y1 = a.cy, moved = true,
      }
      a.level = true
      say(string.format("level drag %d,%d …", a.cx, a.cy))
    end
  end
  if Studio.active and Studio.levelDrag and love and love.mouse
     and love.mouse.isDown and love.mouse.isDown(1) then
    local mx, my = love.mouse.getPosition()
    local cx, cy = Picker.mouseToCanvas(mx, my)
    local ow = overworld()
    local map = ow and ow.map
    if map then
      local cell = Picker.pickCell(map, cx, cy)
      if cell then
        if cell.cx ~= Studio.levelDrag.x1 or cell.cy ~= Studio.levelDrag.y1 then
          Studio.levelDrag.moved = true
        end
        Studio.levelDrag.x1 = cell.cx
        Studio.levelDrag.y1 = cell.cy
      end
    end
  end
end

-- ---- draw ----

local function text(x, y, str, r, g, b)
  love.graphics.setColor(r or 1, g or 1, b or 1, 1)
  love.graphics.print(str, x, y)
end

function Studio.drawOverlay(rw, rh, scale)
  if not Studio.active then return end
  local cw, ch = rw or select(1, Voxel3D.size()), rh or select(2, Voxel3D.size())
  if not (cw and ch) then return end
  Studio.panel.w = math.min(120, math.floor(cw * 0.42))
  Studio.panel.h = ch
  Studio.panel.x = cw - Studio.panel.w
  Studio.panel.y = 0
  local p = Studio.panel

  love.graphics.setColor(0.05, 0.08, 0.12, 0.82)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
  love.graphics.setColor(0.35, 0.75, 0.45, 1)
  love.graphics.rectangle("line", p.x + 0.5, p.y + 0.5, p.w - 1, p.h - 1)

  local x = p.x + 4
  local y = p.y + 3
  text(x, y, "SHAPE STUDIO", 0.55, 1, 0.65); y = y + 10
  local modeExtra = ""
  if Studio.texDrop then modeExtra = " T-drop"
  elseif Studio.chromaDrop then modeExtra = " C" end
  text(x, y, "mode:" .. Studio.mode .. modeExtra, 0.8, 0.9, 0.8)
  y = y + 10

  local s = Studio.selection
  if s and s.kind == "cell" then
    text(x, y, string.format("map %s", tostring(s.mapId))); y = y + 9
    text(x, y, string.format("cell %d,%d", s.cx, s.cy)); y = y + 9
    if s.behaviour then text(x, y, "beh $" .. string.format("%02X", s.behaviour)); y = y + 9 end
    if s.elevation then text(x, y, "elev " .. tostring(s.elevation)); y = y + 9 end
    text(x, y, "class " .. tostring(Studio.edit.class), 1, 1, 0.5); y = y + 9
    text(x, y, "h " .. tostring(Studio.edit.h) .. "  art " .. tostring(Studio.edit.art)); y = y + 9
    text(x, y, "zOff " .. tostring(Studio.edit.zOff)); y = y + 9
    local origM = s.metatile
    local tex = Studio.edit.tex
    if origM ~= nil then
      text(x, y, "meta " .. tostring(origM), 0.75, 0.85, 1); y = y + 9
    end
    if tex and tex.metatile ~= nil then
      text(x, y, "tex->" .. tostring(tex.metatile), 1, 0.85, 0.4); y = y + 9
    elseif tex and tex.tiles then
      text(x, y, "tex->tiles", 1, 0.85, 0.4); y = y + 9
    else
      text(x, y, "T=texture", 0.55, 0.7, 0.55); y = y + 9
    end
  elseif s and s.kind == "sprite" then
    text(x, y, "SPRITE"); y = y + 9
    text(x, y, tostring(s.sheet or "?"):sub(-18)); y = y + 9
    text(x, y, "gfx " .. tostring(s.graphicsId)); y = y + 9
    text(x, y, "obj " .. tostring(s.objId)); y = y + 9
    text(x, y, "yOff " .. tostring(Studio.edit.yOff), 1, 1, 0.5); y = y + 9
  else
    text(x, y, "click a tile"); y = y + 9
    text(x, y, "Tab: sprite"); y = y + 9
  end

  -- preview (zoomed metatile crop — nearest-neighbor into 48px)
  local px, py, pw, ph = previewRect()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", px, py, pw, ph)
  if Studio.previewImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Studio.previewImg, px, py, 0,
      pw / Studio.previewImg:getWidth(),
      ph / Studio.previewImg:getHeight())
  elseif Studio.previewFail then
    text(px + 2, py + 12, "NO PREVIEW", 1, 0.35, 0.35)
    local fail = tostring(Studio.previewFail)
    if #fail > 14 then fail = fail:sub(1, 14) end
    text(px + 2, py + 24, fail, 1, 0.55, 0.4)
  end
  if Studio.chromaDrop then
    local flash = 0.55 + 0.45 * math.abs(math.sin((love.timer.getTime() or 0) * 6))
    love.graphics.setColor(1, 1, 0.15, flash)
    love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)
    love.graphics.rectangle("line", px + 1.5, py + 1.5, pw - 3, ph - 3)
    text(px - 2, py - 9, "C: click GREEN in world", 1, 1, 0.2)
  else
    love.graphics.setColor(0.4, 0.8, 0.5, 1)
    love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)
  end
  local prevHint = "C=eyedrop"
  if Studio.texDrop then prevHint = "CLICK=tex"
  elseif Studio.chromaDrop then prevHint = "CLICK=key" end
  text(px, py + ph + 2, prevHint, 0.7, 0.85, 0.7)
  text(p.x + 4, p.y + p.h - 48, "H help", 0.65, 0.9, 0.75)

  -- chroma list (compact)
  local keys = Overrides.chromakeysFor(
    (s and s.kind == "sprite" and s.sheet) or (s and s.tileset) or nil)
  local ky = py + ph + 12
  for i, c in ipairs(keys) do
    if i > 3 then text(x, ky, "..."); break end
    text(x, ky, string.format("#%d %d,%d,%d", i, c.r or 0, c.g or 0, c.b or 0), 0.9, 0.7, 0.9)
    ky = ky + 8
  end

  -- buttons
  local by = p.y + p.h - 60
  text(x, by, "[1] this", 0.85, 0.95, 0.7)
  text(x, by + 12, "[2] all", 0.85, 0.95, 0.7)
  text(x, by + 24, "[3] save", 1, 0.85, 0.4)
  text(x, by + 36, "[I] import/merge", 0.7, 0.9, 1)
  text(x, by + 48, "[X] export mobile", 0.7, 0.9, 1)

  -- selection marker in world
  if s and s.kind == "cell" then
    local wx, wz = s.cx * 16 + 8, s.cy * 16 + 8
    local gh = (s.zOff or 0)
    local ok, Structures = pcall(V.require, "Structures")
    if ok then
      local ok2, h = pcall(Structures.terraceAt, overworld().map, s.cx, s.cy)
      if ok2 and h then gh = gh + h end
    end
    local sx, sy = Voxel3D.project(wx, gh, wz)
    if sx then
      love.graphics.setColor(1, 1, 0.2, 0.9)
      love.graphics.circle("line", sx, sy, 6)
    end
  end

  -- World chromakey loupe: zoomed nearest-neighbor crop of the voxel canvas.
  if Studio.chromaDrop and loupeImg and chromaHover then
    local mx, my = love.mouse.getPosition()
    local ccx, ccy = Picker.mouseToCanvas(mx, my)
    local scale = 1
    if rw and cw and cw > 0 then scale = (rw / cw) end
    local lx = (ccx or 0)
    local ly = (ccy or 0)
    local zoom = 6
    local side = LOUPE_SRC * zoom
    local ox = math.min((cw or 240) - Studio.panel.w - side - 8, lx + 10)
    local oy = math.max(4, ly - side - 10)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", ox - 2, oy - 2, side + 4, side + 18)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(loupeImg, ox, oy, 0, zoom, zoom)
    love.graphics.setColor(1, 1, 0.2, 1)
    local hx = ox + (math.floor(LOUPE_SRC / 2)) * zoom
    local hy = oy + (math.floor(LOUPE_SRC / 2)) * zoom
    love.graphics.rectangle("line", hx, hy, zoom, zoom)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("%d,%d,%d",
      chromaHover.r, chromaHover.g, chromaHover.b), ox, oy + side + 2)
    love.graphics.setColor(1, 1, 0.3, 1)
    love.graphics.print("C: click GREEN", ox, oy - 10)
  end

  -- Level-rect drag outline (cell rectangle in world projection approx).
  if Studio.levelDrag then
    local d = Studio.levelDrag
    local x0, x1 = math.min(d.x0, d.x1), math.max(d.x0, d.x1)
    local y0, y1 = math.min(d.y0, d.y1), math.max(d.y0, d.y1)
    love.graphics.setColor(0.2, 0.85, 1, 0.9)
    for cy = y0, y1 do
      for cx = x0, x1 do
        if cy == y0 or cy == y1 or cx == x0 or cx == x1 then
          local wx, wz = cx * 16 + 8, cy * 16 + 8
          local sx, sy = Voxel3D.project(wx, 0, wz)
          if sx then
            love.graphics.rectangle("line", sx - 4, sy - 4, 8, 8)
          end
        end
      end
    end
  end

  if Studio.status ~= "" then
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 4, ch - 14, cw - p.w - 8, 12)
    text(6, ch - 12, Studio.status, 0.95, 0.95, 0.7)
  end

  if Studio.helpOpen then
    local hx, hy, hw, hh = 8, 8, math.min(220, cw - p.w - 16), math.min(148, ch - 20)
    love.graphics.setColor(0.02, 0.05, 0.1, 0.92)
    love.graphics.rectangle("fill", hx, hy, hw, hh)
    love.graphics.setColor(0.45, 0.9, 0.55, 1)
    love.graphics.rectangle("line", hx + 0.5, hy + 0.5, hw - 1, hh - 1)
    local lines = {
      "SHAPE STUDIO HELP",
      "F8 / Esc  close studio",
      "Esc       closes help first",
      "click     select tile",
      "drag      level to player height",
      "Tab mode: sprite pick",
      "[ ] Q E   height   - =  zOff",
      "arrows    class / art",
      "T         texture eyedrop",
      "C: click the GREEN you see",
      "  (fence gaps / chroma)",
      "  loupe follows mouse",
      "1 this  2 all  3 save  I merge  X export",
      "  edits autosave to disk",
      "L         sticky level mode (optional)",
      "R revert   Ctrl+Z undo",
      "H         toggle this help",
    }
    local ly = hy + 4
    for i, line in ipairs(lines) do
      if i == 1 then
        text(hx + 4, ly, line, 0.55, 1, 0.65)
      else
        text(hx + 4, ly, line, 0.9, 0.95, 0.85)
      end
      ly = ly + 9
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- install into host ----

function Studio.install()
  rebuildClassList()
  pcall(Overrides.load)
  pcall(function()
    local ChunkMesher = V.require("ChunkMesher")
    if ChunkMesher.setCacheRulesTag then
      ChunkMesher.setCacheRulesTag(Overrides.signature())
    end
  end)

  -- Wrap terrace height so layer/cell zOff lifts walkers with the deck.
  -- Also stamp zOff into synthZ after Structures.forMap so the MESH rises
  -- too (terraceAt alone only affects post-build readers).
  do
    local Structures = V.require("Structures")
    if not Structures._shapeStudioWrapped then
      -- zOff is stamped into synthZ in forMap below, so terraceAt (which
      -- reads synthZ) already returns the lifted height -- do not add again.
      local innerForMap = Structures.forMap
      function Structures.forMap(map)
        local S = innerForMap(map)
        if not (S and map and map.def) then return S end
        local rev = Overrides.rev or 0
        -- Re-stamp when rev changes even if cache object survived.
        if S._studioZRev == rev then return S end
        local W = math.floor(tonumber(map.def.width) or 0)
        local H = math.floor(tonumber(map.def.height) or 0)
        local function stampShape(tk, class, h, art)
          if not S.shapeAt then return end
          local sh = S.shapeAt[tk]
          local nu
          if type(sh) == "table" then
            nu = {}
            for kk, vv in pairs(sh) do nu[kk] = vv end
          else
            nu = { class = "ground", h = 0, art = "flat", flat = true }
          end
          if class ~= nil then nu.class = class end
          if h ~= nil then nu.h = h end
          if art ~= nil then
            nu.art = art
            nu.flat = (art == "flat")
          end
          nu.override = true
          nu.authored = true
          S.shapeAt[tk] = nu
          if S.runs and S.runs[tk] then
            -- Drop run so coordinate override height/class wins the mesh.
            S.runs[tk] = nil
          end
        end
        for cy = 0, H - 1 do
          for cx = 0, W - 1 do
            -- class / h / art from cell or type override (TileShape.at also
            -- applies these on rebuild; stamp again so a soft refresh cannot
            -- miss them if analysis was partially reused).
            local o = nil
            if Overrides.shapeFor then
              -- shapeFor wants tile coords; use cell center tile.
              o = Overrides.shapeFor(map, nil, cx * 2, cy * 2)
            end
            if o and (o.class ~= nil or o.h ~= nil or o.art ~= nil) then
              for _, dy in ipairs({ 0, 1 }) do
                for _, dx in ipairs({ 0, 1 }) do
                  local tk = ((cy * 2 + dy) + 64) * 4096 + ((cx * 2 + dx) + 64)
                  stampShape(tk, o.class, o.h, o.art)
                end
              end
            end
            local z = Overrides.zOffFor(map, cx, cy)
            if z ~= 0 then
              local ck = cy * 8192 + cx
              if S.synthZ then
                local base = S.synthZ[ck]
                if type(base) == "number" then
                  S.synthZ[ck] = base + z
                elseif base == nil then
                  S.synthZ[ck] = z
                end
              end
              -- ChunkMesher.heightAt reads shapeAt.h / runs.h, so lift those
              -- too or the terrain mesh stays flat while walkers float.
              if S.shapeAt then
                for _, dy in ipairs({ 0, 1 }) do
                  for _, dx in ipairs({ 0, 1 }) do
                    local tk = ((cy * 2 + dy) + 64) * 4096 + ((cx * 2 + dx) + 64)
                    local sh = S.shapeAt[tk]
                    if type(sh) == "table" then
                      local nu = {}
                      for kk, vv in pairs(sh) do nu[kk] = vv end
                      if type(nu.h) == "number" then nu.h = nu.h + z end
                      if type(nu.base) == "number" then nu.base = nu.base + z end
                      S.shapeAt[tk] = nu
                    end
                  end
                end
              end
              if S.runs then
                for _, dy in ipairs({ 0, 1 }) do
                  for _, dx in ipairs({ 0, 1 }) do
                    local tk = ((cy * 2 + dy) + 64) * 4096 + ((cx * 2 + dx) + 64)
                    local run = S.runs[tk]
                    if type(run) == "table" and type(run.h) == "number" then
                      local nu = {}
                      for kk, vv in pairs(run) do nu[kk] = vv end
                      nu.h = nu.h + z
                      if type(nu.base) == "number" then nu.base = nu.base + z end
                      S.runs[tk] = nu
                    end
                  end
                end
              end
            end
            -- Texture swap: rewrite S.tileAt UVs only. Shape/collision untouched.
            local tex = Overrides.texFor(map, cx, cy)
            if tex and S.tileAt then
              local mapTs = map.tileset and (map.tileset.id or map.tileset.image)
              if sameTileset(tex.tileset, mapTs) then
                for dy = 0, 1 do
                  for dx = 0, 1 do
                    local tx, ty = cx * 2 + dx, cy * 2 + dy
                    local tk = ((ty) + 64) * 4096 + ((tx) + 64)
                    local q = (ty % 2) * 2 + (tx % 2)
                    if tex.metatile ~= nil then
                      S.tileAt[tk] = (tonumber(tex.metatile) or 0) * 4 + q
                    elseif type(tex.tiles) == "table" and tex.tiles[q] ~= nil then
                      S.tileAt[tk] = tex.tiles[q]
                    end
                  end
                end
              end
            end
          end
        end
        S._studioZRev = rev
        return S
      end
      Structures._shapeStudioWrapped = true
    end
  end

  -- Key hook: outer wrap on Game.keypressed (after main.lua's wrap).
  do
    local Game = require("src.core.Game")
    local inner = Game.keypressed
    function Game:keypressed(key)
      if key == "f8" then
        Studio.keypressed(key)
        return
      end
      if Studio.active then
        Studio.keypressed(key)
        return
      end
      return inner(self, key)
    end
  end

  -- love.keypressed OUTER: block Input from ever seeing game keys in Studio.
  -- Otherwise Select/A/B still edge into Input and bike/interact can fire via
  -- any path that still polls Input (FreeMove, SELECT hook, etc.).
  do
    local inner = love.keypressed
    love.keypressed = function(key, scancode, isrepeat)
      if key == "f8" or Studio.active then
        Studio.keypressed(key)
        return
      end
      if inner then return inner(key, scancode, isrepeat) end
    end
    local innerR = love.keyreleased
    love.keyreleased = function(key, scancode)
      if Studio.active then
        -- Drop holds so a key held across open cannot release into gameplay.
        return
      end
      if innerR then return innerR(key, scancode) end
    end
  end

  -- Gamepad / joystick: swallow while Studio owns the session.
  do
    local Game = require("src.core.Game")
    if Game.gamepadpressed then
      local inner = Game.gamepadpressed
      function Game:gamepadpressed(joystick, button)
        if Studio.active then return end
        return inner(self, joystick, button)
      end
    end
    if Game.gamepadreleased then
      local inner = Game.gamepadreleased
      function Game:gamepadreleased(joystick, button)
        if Studio.active then return end
        return inner(self, joystick, button)
      end
    end
    if Game.gamepadaxis then
      local inner = Game.gamepadaxis
      function Game:gamepadaxis(joystick, axis, value)
        if Studio.active then return end
        return inner(self, joystick, axis, value)
      end
    end
    if Game.joystickpressed then
      local inner = Game.joystickpressed
      function Game:joystickpressed(joystick, button)
        if Studio.active then return end
        return inner(self, joystick, button)
      end
    end
  end

  ensureOutermostInputGuard()

  -- FirstPerson re-enables relative mouse every frame while 1ST/3RD is on.
  -- Force it off after FP.update so Studio click-drag keeps real cursor coords
  -- and never injects A/B through the capture path.
  do
    local FP = V.require("FirstPerson")
    if FP and FP.update and not FP._shapeStudioCaptureGuard then
      local inner = FP.update
      function FP.update(...)
        local r = inner(...)
        if Studio.active and love and love.mouse and love.mouse.setRelativeMode then
          pcall(love.mouse.setRelativeMode, false)
        end
        return r
      end
      FP._shapeStudioCaptureGuard = true
    end
  end

  do
    local Game = require("src.core.Game")
    if Game.wheelmoved then
      local inner = Game.wheelmoved
      function Game:wheelmoved(dx, dy)
        if Studio.wheelmoved(dx, dy) then return end
        return inner(self, dx, dy)
      end
    end
  end

  -- Swallow overworld input while active
  do
    local OverworldState = require("src.world.OverworldController")
    if not OverworldState._shapeStudioInput then
      local inner = OverworldState.handleInput
      function OverworldState:handleInput(...)
        if Studio.active then return end
        return inner(self, ...)
      end
      OverworldState._shapeStudioInput = true
    end
  end

  -- Touch / MAP EDIT: claim fingers before TouchControls when our chrome hits.
  do
    local Game = require("src.core.Game")
    if not Game._shapeStudioTouch then
      local innerP = Game.touchpressed
      function Game:touchpressed(id, x, y, dx, dy, pressure)
        local T = Touch()
        if T and T.onTouchPressed and T.onTouchPressed(id, x, y) then
          return
        end
        -- Desktop Studio: never let TouchControls turn a finger into A/B/Select.
        if Studio.active then
          Studio.mousepressed(x, y, 1)
          return
        end
        return innerP(self, id, x, y, dx, dy, pressure)
      end
      local innerM = Game.touchmoved
      function Game:touchmoved(id, x, y, dx, dy, pressure)
        local T = Touch()
        if T and T.onTouchMoved and T.onTouchMoved(id, x, y) then
          return
        end
        if Studio.active then return end
        return innerM(self, id, x, y, dx, dy, pressure)
      end
      local innerR = Game.touchreleased
      function Game:touchreleased(id, x, y, dx, dy, pressure)
        local T = Touch()
        if T and T.onTouchReleased and T.onTouchReleased(id, x, y) then
          return
        end
        if Studio.active then
          Studio.mousereleased(x, y, 1)
          return
        end
        return innerR(self, id, x, y, dx, dy, pressure)
      end
      local innerDraw = Game.draw
      function Game:draw()
        innerDraw(self)
        local T = Touch()
        if T and T.drawWindow then T.drawWindow() end
      end
      Game._shapeStudioTouch = true
    end
  end

  -- Mouse FAB / toolbar when POKEPORT_TOUCH (outer mouse wrap already exists)
  do
    local inner = love.mousepressed
    love.mousepressed = function(x, y, button, istouch, presses)
      if Studio.active then
        local T = Touch()
        if T and T.onMousePressed and T.onMousePressed(x, y, button) then
          return
        end
        -- Never reach FirstPerson overlay A/B or OW interact.
        if not (istouch and T and T.isMobileOs and T.isMobileOs()) then
          Studio.mousepressed(x, y, button)
        end
        return
      end
      local T = Touch()
      if T and T.onMousePressed and T.onMousePressed(x, y, button) then
        return
      end
      if inner then return inner(x, y, button, istouch, presses) end
    end
  end
  do
    local inner = love.mousereleased
    love.mousereleased = function(x, y, button, istouch, presses)
      if Studio.active then
        local T = Touch()
        if T and T.onMouseReleased and T.onMouseReleased(x, y, button) then
          return
        end
        if not (istouch and T and T.isMobileOs and T.isMobileOs()) then
          Studio.mousereleased(x, y, button)
        end
        return
      end
      local T = Touch()
      if T and T.onMouseReleased and T.onMouseReleased(x, y, button) then
        return
      end
      if inner then return inner(x, y, button, istouch, presses) end
    end
  end
end

-- Called from drawWorld overlay
function Studio.onOverlay(rw, rh, scale)
  Studio.drawOverlay(rw, rh, scale)
end

function Studio.notePoses(poses)
  Studio.lastPoses = poses or {}
end

return Studio
