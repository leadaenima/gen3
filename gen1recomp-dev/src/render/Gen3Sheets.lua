-- THE GEN 3 TILESET, AS A MOD ASKS FOR IT.
--
-- A renderer mod asks the host for a map's art through
-- `TileRenderer.gen3SheetsFor(tilesetDef, data, layout)`, and what it wants
-- back is an object it can call `bakeLayer(layer, plot)` on -- `plot(x, y, r,
-- g, b)` per pixel, in metatile-sheet coordinates, with 0..255 colour. It then
-- re-lays those pixels into whatever layout it works in (DRAMATIC_SHAPE turns
-- the 16x16 metatile grid into an ordinary 8px tile sheet, because sixty-odd
-- places in its shape passes read tiles rather than metatiles).
--
-- WHY THIS IS NOT A PORT.
--
-- The engine this contract comes from answers it with src/render/Gen3Tiles.lua,
-- which composites a tileset PAIR from the raw cartridge records --
-- `data.map_tilesets[key]` holding tiles, metatiles, palettes, attributes and
-- animations -- every time a sheet is wanted. Ruby does that compositing ONCE,
-- at import: src/import/RomExtractorGen3.lua writes each unique (primary,
-- secondary) pair out as two finished atlases, `pair_N_bottom.png` and
-- `pair_N_top.png`, on a 32x32 grid of 16px metatiles.
--
-- That grid IS the layout Gen3Tiles bakes to. So taking the other engine's
-- code would mean shipping a second, raw copy of data we already process and
-- keeping the two in step -- to arrive at the sheet we have already got. This
-- reads the atlas instead.
--
-- WHAT IS BORROWED is the animation idea, which is the non-obvious part. The
-- cartridge animates by swapping tiles in VRAM and a composited sheet cannot,
-- so the other engine makes the SHEET LONGER: only the metatiles containing an
-- animated tile are re-baked into slots past the end of the static grid, and
-- drawing picks a different quad for those cells. Ruby's importer already
-- emits whole per-frame atlases (`pair_0_bottom_f1.png` ... `_f8`), so the
-- frames are on disk; `frameLayer` below reaches them and `animFrameCount`
-- reports how many there are.

local Gen3Sheets = {}

-- The metatile grid every Ruby atlas is written on. Read from the pack when it
-- says, so a re-import that changes the grid is followed rather than fought.
local DEFAULT_COLS = 32
local CELL = 16

-- THE WIDTH THE CONTRACT IS IN, which is not the width our atlas is in.
--
-- A consumer of bakeLayer works out which metatile a pixel belongs to from
-- the coordinates it is handed:
--
--   m = floor(y / 16) * SHEET_COLS + floor(x / 16)
--
-- and SHEET_COLS is SIXTEEN -- the width the other engine's Gen3Tiles bakes
-- to, hard-coded on both sides of that calculation. Ruby's importer lays a
-- pair out 32 metatiles wide instead, so handing over our own coordinates
-- makes every row past the first alias onto the next row's ids: metatile 32
-- arrives as 16, 33 as 17, and the whole sheet reads as a repeating scramble.
-- On screen that is a chequerboard of mismatched ground.
--
-- So bakeLayer walks our atlas BY METATILE and emits each one at the place it
-- would occupy in a 16-wide sheet. The pixels are ours; the frame they arrive
-- in is the contract's.
local CONTRACT_COLS = 16

local cache = {}



-- Emerald never plots palette index 0 (Gen3Tiles.drawLayer: `if v ~= 0`).
-- Ruby bakes that into PNGs via skip0, then LOVE's ImageData:encode writes a
-- paletted PNG (color type 3) WITH NO tRNS on the mostly-opaque BOTTOM sheet.
-- skip0 holes survive import as (0,0,0,0) and die on disk as opaque black.
-- Lime/magenta punch therefore never fired: pair_0_bottom is 0 lime, 54042
-- opaque black. The mesher treated those texels as solid and the GPU atlas
-- (bakeLinear always writes a=1 for plotted pixels) never saw a hole.
--
-- Punch lime/magenta always. If the loaded sheet has NO alpha, also punch
-- near-black -- that is the skip0 leftover, not GBA paint (real blacks on
-- these sheets are (24,40,80) etc.). Top sheets already carry tRNS, so they
-- keep their authored black outlines.
-- r11: pair PNGs on disk are rebaked RGBA with index-0 clear, so every
-- consumer (Gen3Sheets, Assets.imageData, external tools) sees holes without
-- depending on this punch. Punch remains the safety net for stale caches.
local function norm01(r, g, b, a)
  a = a or 0
  if r > 1 or g > 1 or b > 1 or a > 1 then
    return r / 255, g / 255, b / 255, a / 255
  end
  return r, g, b, a
end

-- Classic importer / editor keys. GBA leaf paints like (128,192,96) are NOT
-- keys -- they are real foliage. Only near-pure lime/magenta.
local function isLimeOrMagenta(r, g, b)
  -- Neon importer keys. Slightly wider than pure (0,255,0) so fence-gap
  -- GBA lime that survived a bake still punches; real foliage (leaf greens
  -- with meaningful R/B) stays opaque.
  if g > 0.62 and r < 0.22 and b < 0.22 and g >= r * 2.2 and g >= b * 2.2 then
    return true
  end
  if r > 0.72 and b > 0.72 and g < 0.14 then return true end
  return false
end

local function isSkip0Fill(r, g, b)
  return r < 0.02 and g < 0.02 and b < 0.02
end

local punchLog = {}

local function logPunch(path, w, h, alpha0, keyed)
  local key = tostring(path)
  if punchLog[key] then return end
  punchLog[key] = true
  local n = w * h
  local line = ("gen3 sheets punch: %s %dx%d alpha0=%d keyed=%d opaque=%d -- GPU bakeLayer skips a==0"):format(
    key, w, h, alpha0, keyed, n - alpha0 - keyed)
  pcall(function() require("src.core.Logger").info("%s", line) end)
  pcall(function()
    if not (love and love.filesystem and love.filesystem.append) then return end
    love.filesystem.append("world-pass.log",
      os.date("%H:%M:%S ") .. line .. string.char(10))
  end)
end

local function punchChromaKey(data, path)
  if not (data and data.mapPixel) then return data end
  local keyed, alpha0 = 0, 0
  local hasAlpha = false
  data:mapPixel(function(_, _, r, g, b, a)
    local rn, gn, bn, an = norm01(r, g, b, a)
    if an <= 0 then
      hasAlpha = true
      alpha0 = alpha0 + 1
      return 0, 0, 0, 0
    end
    if isLimeOrMagenta(rn, gn, bn) then
      keyed = keyed + 1
      return 0, 0, 0, 0
    end
    -- Shape Studio extra chromakeys (DRAMATIC_SHAPE), if loaded.
    do
      local V = rawget(_G, '__DRAMATIC_SHAPE_V')
      if V and V.require then
        local ok, SO = pcall(V.require, 'ShapeOverrides')
        if ok and SO and SO.matchesChroma and SO.matchesChroma(rn, gn, bn, path) then
          keyed = keyed + 1
          return 0, 0, 0, 0
        end
      end
    end
    return r, g, b, a
  end)
  if not hasAlpha then
    data:mapPixel(function(_, _, r, g, b, a)
      local rn, gn, bn = norm01(r, g, b, a)
      if isSkip0Fill(rn, gn, bn) then
        keyed = keyed + 1
        return 0, 0, 0, 0
      end
      return r, g, b, a
    end)
  end
  local w, h = data:getDimensions()
  logPunch(path, w, h, alpha0, keyed)
  return data
end

local function resolveSheetPath(path)
  if type(path) ~= "string" or path == "" then return nil end
  if not (love and love.filesystem and love.filesystem.getInfo) then return path end
  if love.filesystem.getInfo(path) then return path end
  local okGV, GameVersion = pcall(require, "src.core.GameVersion")
  if okGV and GameVersion and GameVersion.cachePrefix then
    local prefix = GameVersion.cachePrefix() or ""
    if prefix ~= "" then
      local pth = prefix .. path
      if love.filesystem.getInfo(pth) then return pth end
    end
  end
  return path
end

local function imageDataFor(path)
  if type(path) ~= "string" or path == "" then return nil end
  if not (love and love.image and love.image.newImageData) then return nil end
  path = resolveSheetPath(path)
  if love.filesystem and love.filesystem.getInfo
      and not love.filesystem.getInfo(path) then
    return nil
  end
  local ok, data = pcall(love.image.newImageData, path)
  if not ok then return nil end
  return punchChromaKey(data, path)
end

-- One tileset's atlases, read once. `bottom` is BG3+BG2 -- the ground and the
-- second course over it -- and `top` is BG1, the half that can draw above the
-- player. A missing top is not a failure: plenty of indoor pairs have none.
local function loadPair(spec)
  local bottom = imageDataFor(spec and spec.bottom)
  if not bottom then return nil end
  return { bottom = bottom, top = imageDataFor(spec and spec.top) }
end

local function framePaths(spec, frame)
  local anim = spec and spec.anim
  local layers = anim and anim.layers
  local row = layers and layers[frame]
  if type(row) ~= "table" then return nil end
  return row
end

-- The object the mod calls. Deliberately small: `bakeLayer` is the only thing
-- DRAMATIC_SHAPE actually uses, and the rest answer the questions the other
-- engine's Gen3Tiles answers so a mod that asks them gets a real reply rather
-- than a nil index.
local function makeTiles(spec, cols, rows)
  local pair = loadPair(spec)
  if not pair then return nil end

  local frames = {}          -- frame index -> { bottom = ImageData, top = ... }
  local current = 0

  local tiles = {}

  function tiles:metatileCount()
    return cols * rows
  end

  -- cols, rows, width, height -- the shape of the sheet bakeLayer plots into
  -- Reported in the CONTRACT's frame, to match what bakeLayer emits. A
  -- caller sizing a surface from this and then reading the coordinates we
  -- send must get one answer, not two.
  function tiles:sheetLayout()
    local total = cols * rows
    local contractRows = math.ceil(total / CONTRACT_COLS)
    return CONTRACT_COLS, contractRows,
      CONTRACT_COLS * CELL, contractRows * CELL
  end

  function tiles:attributes(id)
    local b = spec.behavior and spec.behavior[id] or 0
    local l = spec.layerType and spec.layerType[id] or 0
    return b, l
  end

  -- The top half draws above the player unless the layer type is COVERED
  -- (bottom + middle BG, include/global.fieldmap.h). This read `l == 1`, the
  -- exact inverse; see the note on the world record in Game3ModWorld.
  function tiles:topIsAbovePlayer(id)
    local _, l = self:attributes(id)
    return l ~= 1
  end

  function tiles:animFrameCount()
    local n = spec.anim and tonumber(spec.anim.frames) or 1
    if n < 1 then return 1 end
    return n
  end

  function tiles:animStep()
    return spec.anim and spec.anim.step or nil
  end

  -- Which metatiles move. Ruby's importer records that a pair animates at all
  -- (`overworldAnim`) but not WHICH metatiles do, and answering with a guess
  -- would send a caller re-baking the wrong hundred cells. An empty list is
  -- the truthful answer: a caller then bakes the static sheet, which is what
  -- the cartridge shows on the first field frame anyway.
  function tiles:animatedMetatiles()
    return {}
  end

  function tiles:setAnimFrame(frame)
    current = tonumber(frame) or 0
  end

  -- The pixels. `layer` is 1 for the bottom atlas and 2 for the top, matching
  -- the other engine's numbering, and `plot` is handed metatile-sheet
  -- coordinates with 0..255 colour -- which is the unit its callers divide by
  -- 255 to get back to LOVE's floats.
  --
  -- Fully transparent pixels are SKIPPED rather than plotted black: the top
  -- atlas is mostly empty, and a caller compositing both layers into one
  -- surface would otherwise have the second erase the first.
  function tiles:bakeLayer(layer, plot)
    if type(plot) ~= "function" then return false end
    local source = pair
    if current and current > 0 then
      local row = framePaths(spec, current + 1)
      if row then
        local f = frames[current]
        if f == nil then
          f = { bottom = imageDataFor(row.bottom), top = imageDataFor(row.top) }
          frames[current] = f
        end
        if f and f.bottom then source = f end
      end
    end
    local image = (layer == 2) and source.top or source.bottom
    if not image then return false end
    local w, h = image:getDimensions()
    local srcCols = math.floor(w / CELL)
    if srcCols < 1 then return false end
    local total = srcCols * math.floor(h / CELL)
    -- one metatile at a time, so its destination can be restated in the
    -- contract's 16-wide frame rather than our 32-wide one
    for m = 0, total - 1 do
      local sx = (m % srcCols) * CELL
      local sy = math.floor(m / srcCols) * CELL
      local dx = (m % CONTRACT_COLS) * CELL
      local dy = math.floor(m / CONTRACT_COLS) * CELL
      for oy = 0, CELL - 1 do
        for ox = 0, CELL - 1 do
          local r, g, b, a = image:getPixel(sx + ox, sy + oy)
          if (a or 0) > 0 then
            plot(dx + ox, dy + oy, r * 255, g * 255, b * 255)
          end
        end
      end
    end
    return true
  end

  -- Not served, and named rather than left to a nil index. Re-baking ONE
  -- metatile into a slot past the end of the static grid is the other engine's
  -- animation trick, and it needs animatedMetatiles above to be real first.
  function tiles:bakeMetatileInto()
    return false
  end

  return tiles
end

-- The entry point a mod reaches through TileRenderer.gen3SheetsFor.
--
-- Returns the record shape that contract publishes: the two finished images,
-- their dimensions, the metatile count, and `tiles` -- which is the only field
-- DRAMATIC_SHAPE reads. nil for anything that is not a Gen 3 tileset, so a Gen
-- 1 or Gen 2 caller is unaffected.
-- ONE LINE PER TILESET SAYING WHETHER THE ART ARRIVED.
--
-- This seam is load-bearing in a way its size hides. A renderer mod reads the
-- atlas as an 8px tile grid and infers EVERY shape from those pixels -- tree
-- hulls, roof massing, props, grass, relief. All of it is gated on the pixels
-- arriving, and the mod's own note says what happens when they do not: "not a
-- wrong picture but NO SHAPE AT ALL ... every tree and every house fell
-- through to a plain measured box."
--
-- So a silent nil here is indistinguishable, on screen, from a world that
-- simply has no shapes authored for it -- and telling those two apart by
-- looking is exactly what I got wrong. Said out loud instead, once per
-- tileset, into the file a player on a phone can actually read.
local reported = {}

local function report(id, outcome, extra)
  local key = tostring(id) .. "|" .. outcome
  if reported[key] then return end
  reported[key] = true
  local line = ("gen3 sheets: %s -- %s%s"):format(tostring(id), outcome,
    extra and (" " .. extra) or "")
  pcall(function() require("src.core.Logger").info("%s", line) end)
  pcall(function()
    if not (love and love.filesystem and love.filesystem.append) then return end
    love.filesystem.append("world-pass.log",
      os.date("%H:%M:%S ") .. line .. string.char(10))
  end)
end

function Gen3Sheets.forTileset(tilesetDef, data)
  -- not a Gen 3 tileset at all: a Gen 1 or Gen 2 caller, and silence is the
  -- right answer -- nothing downstream expects sheets from us
  if not (tilesetDef and tonumber(tilesetDef.blockTiles) == 2) then
    if tilesetDef ~= nil then
      report(tostring(tilesetDef.id or "?"), "NOT A GEN 3 TILESET",
        "blockTiles=" .. tostring(tilesetDef.blockTiles))
    end
    return nil
  end
  -- Sheet atlases live under Ruby pair_N ids. Role/owner code may put an
  -- Emerald TILESET_<hex>_<hex> on tilesetDef.id; prefer pairId when present
  -- so texture binding never rides the role key.
  local id = tilesetDef.pairId or tilesetDef.id
  if id == nil then
    report("?", "TILESET HAS NO id -- cannot reach its atlas")
    return nil
  end
  local hit = cache[id]
  if hit ~= nil then return hit or nil end
  cache[id] = false          -- do not retry a failed read every frame

  local store = data and data.tilesets
  local spec = store and store.byId and store.byId[id]
  if not spec and tilesetDef.pairId and tilesetDef.id and tilesetDef.pairId ~= tilesetDef.id then
    spec = store and store.byId and store.byId[tilesetDef.id]
    if spec then id = tilesetDef.id end
  end
  if not spec then
    report(id, "NO SPEC in data.tilesets.byId -- every shape pass will skip")
    return nil
  end
  local cols = tonumber(store.atlasCols) or DEFAULT_COLS
  local rows = tonumber(store.atlasRows) or cols

  local tiles = makeTiles(spec, cols, rows)
  if not tiles then
    report(id, "ATLAS DID NOT LOAD", "bottom=" .. tostring(spec.bottom))
    return nil
  end

  local sheetCols, sheetRows, sheetW, sheetH = tiles:sheetLayout()
  local record = {
    tiles = tiles,
    metatiles = cols * rows,
    -- the CONTRACT's dimensions, matching sheetLayout and bakeLayer
    cols = sheetCols,
    rows = sheetRows,
    width = sheetW,
    height = sheetH,
    animFrames = tiles:animFrameCount(),
    animStep = tiles:animStep(),
  }
  report(id, "ok", ("%dx%d metatiles, %dx%d px"):format(
    sheetCols, sheetRows, sheetW, sheetH))
  cache[id] = record
  return record
end

function Gen3Sheets.invalidate()
  cache = {}
end

return Gen3Sheets
