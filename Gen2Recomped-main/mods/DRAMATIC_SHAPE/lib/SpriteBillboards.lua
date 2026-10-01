-- Voxel world mode: characters as flat forward-facing sprite billboards.
--
-- Gen2 patch: SPRITE_BIG_SNORLAX / SPRITE_BIG_LAPRAS (and any def.big sheet)
-- are 32x32 over a 2x2 cell footprint.  The stock card was hard-coded 16x16
-- and only sampled the top-left face tile — that is why DramaticShapes showed
-- a quarter of Snorlax.  Big sheets get a 32x32 card; 16-wide mirrored strips
-- get a dual-quad card that mirrors the left half in UV space.

local V = ...

local Assets = require("src.render.Assets")
local Voxel3D = V.require("Voxel3D")

local SpriteBillboards = {}

local meshes = {}

local function isBigDef(def)
  if not def then return false end
  if def.big then return true end
  local id = def.id or ""
  return id == "SPRITE_BIG_SNORLAX"
    or id == "SPRITE_BIG_LAPRAS"
    or id == "SPRITE_BIG_DOLL"
end

-- Standard 16x16 walker frame (Gen1 / normal Gen2 NPCs).
local function buildCard16(img, frame)
  local iw, ih = img:getDimensions()
  local fy = frame * 16
  if fy + 16 > ih then fy = 0 end
  local u0, u1 = 0.02 / iw, (16 - 0.02) / iw
  local v0, v1 = (fy + 0.05) / ih, (fy + 15.95) / ih
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { 16, 0, 0, u1, v1, 1 },
    { 16, 16, 0, u1, v0, 1 }, { 0, 16, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

-- Full 32x32 body (extractor already mirrored the left half into the sheet).
local function buildCard32(img)
  local iw, ih = img:getDimensions()
  local u0, u1 = 0.02 / iw, (math.min(32, iw) - 0.02) / iw
  local v0, v1 = 0.05 / ih, (math.min(32, ih) - 0.05) / ih
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { 32, 0, 0, u1, v1, 1 },
    { 32, 32, 0, u1, v0, 1 }, { 0, 32, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

-- 16x32 left-half strip: two side-by-side quads, right one mirrors U.
local function buildCardMirrored16x32(img)
  local iw, ih = img:getDimensions()
  local h = math.min(32, ih)
  local u0, u1 = 0.02 / iw, (16 - 0.02) / iw
  local v0, v1 = 0.05 / ih, (h - 0.05) / ih
  -- left half
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { 16, 0, 0, u1, v1, 1 },
    { 16, h, 0, u1, v0, 1 }, { 0, h, 0, u0, v0, 1 },
    -- right half = mirror of left (u1→u0)
    { 16, 0, 0, u1, v1, 1 }, { 32, 0, 0, u0, v1, 1 },
    { 32, h, 0, u0, v0, 1 }, { 16, h, 0, u1, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  Voxel3D.pushQuad(indices, 4)
  return Voxel3D.newMesh(verts, indices)
end

-- ---------------------------------------------------------------------------
-- A CARD FROM A SHEET THAT STATES ITS OWN FRAME BOX.
--
-- Everything above assumes the Gen 1/Gen 2 shape: a one-frame-wide sheet of
-- SQUARE frames, so a 16-wide sheet has 16px rows and `frame * 16` finds the
-- one you want.  Gen 3 breaks both halves of that. Its overworld sprites come
-- in 16x32, 32x32 and 16x16, and the common walker -- the player included --
-- is 16 wide and THIRTY-TWO tall.
--
-- Read as 16px rows, frame 3 (walk south) lands at y=48, which is the middle
-- of frame 1: the card showed the bottom of "stand north" and the top of
-- "stand west" at once, in a 16px box that cropped it to the hair. On screen
-- that is a small brown smudge on the ground that changes to a DIFFERENT
-- wrong smudge as you walk -- which reads exactly like a sprite facing the
-- wrong way, and is really a sprite sliced between two frames.
--
-- The defs say so themselves (`frameWidth` / `frameHeight`, straight off
-- gObjectEventGraphicsInfo), so where they do, believe them. Where they do
-- not -- every Gen 1, Gen 2 and Prism sheet -- nothing below this line runs
-- and the original path is taken unchanged.
local function statedFrame(def)
  local fw = tonumber(def.frameWidth)
  local fh = tonumber(def.frameHeight)
  if fw and fh and fw > 0 and fh > 0 then return fw, fh end
  return nil
end

-- Gen3 / Ruby OW sheets live under GameVersion.cachePrefix (e.g. ruby/assets/...).
-- Assets.image alone only sees the unprefixed source tree when the version
-- overlay is not mounted, so every ow_*.png failed here, SpriteBillboards.mesh
-- returned nil, and drawEntity dropped the card. Flat OW drawing uses
-- Game3:grabImage; billboards must match that resolution.
-- Prefixed / live grabImage FIRST: an unprefixed miss often answers a 16x16
-- placeholder, which would cache a dummy card and hide every NPC.
local sheetCache = {}

local function canvasBound()
  if not (love and love.graphics and love.graphics.getCanvas) then return false end
  local ok, canvas = pcall(love.graphics.getCanvas)
  return ok and canvas ~= nil
end

local function loadSheet(path)
  if type(path) ~= "string" or path == "" then return nil end
  local cached = sheetCache[path]
  if cached then return cached end
  -- newImage while the sun pass has its canvas bound detaches that target.
  -- The rest of the casters then miss the map, and the next recast paints a
  -- different broken frame: the whole town's shadows strobe. Warm the cache
  -- before the pass; a miss during it waits for the next unbound frame.
  if canvasBound() then return nil end
  -- Follower sheets live in the mod tree. Assets.image and grabImage look
  -- at the cartridge cache and answer a placeholder, or nothing, so the
  -- billboard was dropped and the follower vanished in voxel. The file
  -- itself is on the game filesystem; load that when it is there.
  if love and love.filesystem and love.filesystem.getInfo
      and love.graphics and love.graphics.newImage
      and love.filesystem.getInfo(path) then
    local okN, img = pcall(love.graphics.newImage, path)
    if okN and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      sheetCache[path] = img
      return img
    end
  end
  if Assets.provides and Assets.provides(path) then
    local ok, img = pcall(Assets.image, path)
    if ok and img then return img end
  end
  -- Ruby/Sapphire: _G.Game is the live Game3 instance (grabImage + CacheFs).
  -- require("src.core.Game") is the empty Emerald module and has no grabImage.
  -- Ask grabImage BEFORE Assets.image: a miss there is a placeholder, not nil.
  local host = rawget(_G, "Game")
  if type(host) == "table" and type(host.grabImage) == "function" then
    local okI, got = pcall(host.grabImage, host, path)
    if okI and got then return got end
  end
  local prefix = ""
  do
    local okGV, GameVersion = pcall(require, "src.core.GameVersion")
    if okGV and GameVersion and GameVersion.cachePrefix then
      prefix = GameVersion.cachePrefix() or ""
    end
  end
  if prefix ~= "" then
    local prefixed = prefix .. path
    if Assets.exists and Assets.exists(prefixed) then
      local ok, img = pcall(Assets.image, prefixed)
      if ok and img then return img end
    end
  end
  if Assets.exists and Assets.exists(path) then
    local ok, img = pcall(Assets.image, path)
    if ok and img then return img end
  end
  do
    local okG, Game = pcall(require, "src.core.Game")
    if okG and Game and type(Game.grabImage) == "function" then
      local okI, got = pcall(Game.grabImage, Game, path)
      if okI and got then return got end
    end
  end
  return nil
end

function SpriteBillboards.sheet(path)
  return loadSheet(path)
end

-- Load a sheet even if a playfield canvas is already bound. The sun pass
-- must not call this: restoring that canvas would drop its depth buffer.
-- VoxelScene warms every posed image before ShadowMap.begin instead.
function SpriteBillboards.warm(path)
  if type(path) ~= "string" or path == "" then return nil end
  if sheetCache[path] then return sheetCache[path] end
  local prev
  if love and love.graphics and love.graphics.getCanvas then
    local ok, canvas = pcall(love.graphics.getCanvas)
    if ok then prev = canvas end
  end
  if prev and love.graphics.setCanvas then love.graphics.setCanvas() end
  local img = loadSheet(path)
  if prev and love.graphics.setCanvas then pcall(love.graphics.setCanvas, prev) end
  return img
end

-- A follow sheet is a grid: columns are walk frames, rows are facings.
-- A normal walker strip is one column or one row, and must not take this.
local function followerSheet(def)
  if type(def) ~= "table" then return false end
  local id = tostring(def.id or "")
  local image = tostring(def.image or def.path or "")
  if id:find("OW_WILD", 1, true) or id:find("WILDS", 1, true) then return true end
  if image:find("followsprites", 1, true) then return true end
  if image:find("enhanced_overworld", 1, true) then return true end
  return false
end

local function gridCell(def, iw, ih)
  if not followerSheet(def) then return nil end
  iw, ih = tonumber(iw), tonumber(ih)
  if not iw or not ih or iw < 16 or ih < 16 then return nil end
  local cw = tonumber(def.width) or tonumber(def.frameWidth)
  local ch = tonumber(def.height) or tonumber(def.frameHeight)
  if cw and ch and cw >= 8 and ch >= 8 and iw % cw == 0 and ih % ch == 0 then
    local cols, rows = iw / cw, ih / ch
    if cols >= 2 and rows >= 2 and cols <= 8 and rows <= 8 then
      return cw, ch, cols, rows
    end
  end
  if iw >= 64 and ih >= 64 and iw % 4 == 0 then
    local cell = math.floor(iw / 4)
    if cell >= 16 and ih % cell == 0 and math.floor(ih / cell) >= 2 then
      return cell, cell, 4, math.floor(ih / cell)
    end
  end
  return nil
end

-- Packed frame index (row * cols + col) for a follow grid, or nil when
-- this sheet is an ordinary strip. Facing rows match the enhanced sheet:
-- down, left, right, up. Phase 0/1 plus the step mirror pick the column.
function SpriteBillboards.gridFrame(def, iw, ih, facing, phase, flip)
  local cw, ch, cols, rows = gridCell(def, iw, ih)
  if not cols then return nil end
  local dir = tostring(facing or "down"):lower()
  local row = ({
    down = 0, south = 0, front = 0,
    left = 1, west = 1,
    right = 2, east = 2,
    up = 3, north = 3, back = 3,
  })[dir] or 0
  local col = 0
  if type(phase) == "number" and phase > 0 then col = 1 end
  if cols >= 4 and flip then col = col + 2 end
  return (row % rows) * cols + (col % cols), cw, ch
end

-- sampleW/H = sheet frame UVs. worldW/H = on-ground card (True Size may
-- be larger than the strip it was sampled from).
local function buildCardStated(img, frame, sampleW, sampleH, worldW, worldH)
  local iw, ih = img:getDimensions()
  sampleW, sampleH = math.min(sampleW, iw), math.min(sampleH, ih)
  worldW = tonumber(worldW) or sampleW
  worldH = tonumber(worldH) or sampleH
  if worldW < 8 then worldW = sampleW end
  if worldH < 8 then worldH = sampleH end
  frame = tonumber(frame) or 0
  local fx, fy = 0, 0
  -- A follow grid packs the cell as row * cols + col. A strip still walks
  -- the one axis that actually holds more than one frame.
  local cols = math.floor(iw / sampleW)
  local rows = math.floor(ih / sampleH)
  local across
  if cols >= 2 and rows >= 2 then
    fx = (frame % cols) * sampleW
    fy = (math.floor(frame / cols) % rows) * sampleH
    across = nil
  else
  -- Ruby extracts a HORIZONTAL strip (frames across). Emerald / stacked
  -- sheets are a column (frames down). Walk the axis that actually holds
  -- more than one frame so an unstacked Game3 sheet still shows a card.
  across = iw >= (sampleW * 2) and ih <= (sampleH + 1)
  if across then
    fx = frame * sampleW
    if fx + sampleW > iw then fx = 0 end
  else
    fy = frame * sampleH
    if fy + sampleH > ih then fy = 0 end
  end
  end
  local u0, u1 = (fx + 0.02) / iw, (fx + sampleW - 0.02) / iw
  local v0, v1 = (fy + 0.05) / ih, (fy + sampleH - 0.05) / ih
  -- The card is worldW x worldH in WORLD pixels, so a 16x32 walker stands
  -- two courses tall on a one-cell footprint -- which is what the flat
  -- game draws too. True Size stamps a species box (22x24, 48x48, ...) on
  -- a 16x96 follow-strip: UVs stay one sheet frame, the slab uses the box.
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { worldW, 0, 0, u1, v1, 1 },
    { worldW, worldH, 0, u1, v0, 1 }, { 0, worldH, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

-- Vertical (or horizontal Ruby) strip geometry when the def forgot to
-- name frameWidth/Height. Six-frame 16×96 follow-sprites and 32×192 True
-- Size walkers both land here; a 64×64 still does not.
local function inferStrip(def, iw, ih)
  if type(def) ~= "table" then return nil end
  iw, ih = tonumber(iw), tonumber(ih)
  if not iw or not ih or iw < 8 or ih < 8 then return nil end
  local n = tonumber(def.frames) or 1
  local walker = def.walker == true
  if n < 2 and not walker then return nil end
  if n < 2 then n = 6 end
  if ih >= n * 8 then
    local fh = math.floor(ih / n)
    local fw = iw
    if fh >= 8 and fw >= 8 and fw <= fh * 2 + 4 then
      return fw, fh
    end
  end
  if iw >= n * 8 then
    local fw = math.floor(iw / n)
    local fh = ih
    if fw >= 8 and fh >= 8 and fh <= fw * 2 + 4 then
      return fw, fh
    end
  end
  return nil
end

-- True Size names a SPECIES box (48×48, 64×64, ...) on a 16×96 walk
-- strip. Trusting that as the sheet frame UVs a stack of poses into one
-- card and stretches it -- the voxel follower squash.
local function statedTilesSheet(fw, fh, iw, ih)
  fw, fh, iw, ih = tonumber(fw), tonumber(fh), tonumber(iw), tonumber(ih)
  if not (fw and fh and iw and ih) then return false end
  if fw < 8 or fh < 8 or fw > iw or fh > ih then return false end
  local across = (iw % fw == 0)
  local down = (ih % fh == 0)
  return across or down
end

local function gbaObjectSize(fw, fh)
  fw, fh = tonumber(fw), tonumber(fh)
  if not (fw and fh) then return false end
  return (fw == 16 or fw == 32) and (fh == 16 or fh == 32)
end

-- Public: the frame box the card actually samples. `iw`/`ih` optional;
-- without them a True Size walker still falls back to 16×16 rather than
-- stretching the species box.
function SpriteBillboards.sheetFrame(def, iw, ih)
  local gw, gh = gridCell(def, iw, ih)
  if gw then return gw, gh end
  local fw, fh = statedFrame(def)
  if fw and fh then
    if iw and ih then
      if statedTilesSheet(fw, fh, iw, ih) then return fw, fh end
      fw, fh = nil, nil
    elseif not gbaObjectSize(fw, fh) then
      local n = tonumber(def.frames) or 1
      if def.walker == true or n >= 6 then
        fw, fh = nil, nil
      end
    end
  end
  if not fw then
    fw, fh = inferStrip(def, iw, ih)
  end
  return fw, fh
end

-- Public: on-ground card size. True Size names a SPECIES box that does
-- not tile the walk strip; sample UVs via sheetFrame, stand the slab at
-- this box. Gen3 16×32 walkers tile their sheet, so both answers match.
-- VoxelScene.halfWidth calls this WITHOUT image dims, so the species box
-- must still win there.
function SpriteBillboards.worldSize(def, iw, ih)
  local dw, dh = statedFrame(def)
  local sw, sh = SpriteBillboards.sheetFrame(def, iw, ih)
  if dw and dh then
    if iw and ih then
      if not statedTilesSheet(dw, dh, iw, ih) then return dw, dh end
    elseif not gbaObjectSize(dw, dh) then
      local n = tonumber(def.frames) or 1
      if def.walker == true or n >= 6 then return dw, dh end
    end
  end
  if sw and sh then return sw, sh end
  if dw and dh then return dw, dh end
  return nil
end

local function buildCard(def, frame, img)
  img = img or loadSheet(def.image)
  if not img then return nil end
  local iw, ih = img:getDimensions()

  local fw, fh = SpriteBillboards.sheetFrame(def, iw, ih)
  if fw then
    local ww, wh = SpriteBillboards.worldSize(def, iw, ih)
    return buildCardStated(img, frame or 0, fw, fh, ww, wh)
  end

  -- A multi-frame / walker sheet is NEVER a frozen 32×32 doll crop.
  -- Wilds True Size and 16×96 follow-sprite strips are ≥32px wide after
  -- geometry is stripped; collapsing them here froze every wild on the
  -- top-left still, with no facing and no walk cycle.
  local nframes = tonumber(def.frames) or 1
  local walker = def.walker == true or nframes >= 6
  if (not walker) and nframes <= 1 and (isBigDef(def) or iw >= 32) then
    if iw >= 32 and ih >= 32 then
      return buildCard32(img)
    end
    -- Still a 16-wide FacingBigDollSymmetric strip
    return buildCardMirrored16x32(img)
  end

  return buildCard16(img, frame or 0)
end

function SpriteBillboards.mesh(def, frame, img)
  if type(def) ~= "table" or type(def.image) ~= "string" or def.image == "" then
    return nil
  end
  -- Gen3 OW sheets state frameWidth/Height (16x32 walkers). Those are
  -- MULTI-FRAME tall strips: collapsing them under isBigDef/def.big to a
  -- single "#big" mesh froze every card on whatever frame was first built.
  -- Inferred Wilds strips (16×96 / True Size) are the same: the key must
  -- keep `frame` so facing and the walk cycle can change.
  local stated = statedFrame(def)
  local nframes = tonumber(def.frames) or 1
  local walker = def.walker == true or nframes >= 6
  local big = (not stated) and (not walker) and nframes <= 1 and isBigDef(def)
  local extra = ""
  local iw, ih
  if img and img.getDimensions then
    iw, ih = img:getDimensions()
    extra = "@" .. tostring(iw) .. "x" .. tostring(ih)
  end
  local ww, wh = SpriteBillboards.worldSize(def, iw, ih)
  if ww then extra = extra .. "w" .. tostring(ww) .. "x" .. tostring(wh or 0) end
  local key = def.image .. "#" .. (big and "big" or tostring(frame)) .. extra
  local hit = meshes[key]
  if hit then return hit end
  -- Do not cache failures. First voxel frames can run before Game3 overlay
  -- binds grabImage; a sticky false left every NPC undrawn for the session.
  local ok, m = pcall(buildCard, def, frame, img)
  if ok and m then
    meshes[key] = m
    return m
  end
  return nil
end

SpriteBillboards.shadowQuad = SpriteBillboards.mesh

function SpriteBillboards.invalidate()
  meshes = {}
end

-- WHERE THE FEET ARE, WHICH IS NOT THE SAME QUESTION AS HOW WIDE THE CARD IS.
--
-- In-game location: THE SEA OFF ROUTE 118 -- a surfing player wears
-- SPRITE_G3_003, a 32x32 sheet, and stands on ONE 16px cell; and every bike
-- lane in Hoenn, where SPRITE_G3_001 / _002 do the same thing.
--
-- The flat path states the rule itself. SpriteRenderer.new gives a sheet that
-- DECLARES its frame box `offsetX = (frameWidth - 16) / 2` and
-- `offsetY = frameHeight - 16`, i.e. it centres the frame on the 16px cell and
-- hangs the surplus over the edges -- so a 32-wide sheet is blitted from
-- px - 8 and its middle lands on the middle of the cell, at px + 8.
--
-- `halfWidth` above is the card's OWN half, and billboardMatrix used that one
-- number for two different things: how far to slide the card left to centre
-- it, and which point to centre it ON. Those coincide for a Gen 2 BIG DOLL,
-- whose footprint really is 2x2 cells (Snorlax, Lapras stand on four), and
-- for nothing else. 61 of Hoenn's 256 overworld sheets are wider than 16px --
-- 55 at 32 wide, one 48, three 64, one 88, one 96 -- and every one of them was
-- drawn (frameWidth/2 - 8) px EAST and the same distance SOUTH of the cell the
-- flat game draws it on: half a cell for the surfing and cycling player, two
-- and a half cells for the widest.
--
-- nil for a sheet that does not state a frame box, and every Gen 1, Gen 2 and
-- Prism sheet is one of those (see statedFrame above -- nothing below that
-- line runs for them). A nil answer leaves both the card matrix and the sun's
-- record built from exactly the arithmetic they were built from before, big
-- dolls included.
function SpriteBillboards.footAnchor(def, iw, ih)
  -- One-cell footprint even when the True Size card is wider than 16px.
  if SpriteBillboards.worldSize(def, iw, ih) then return 8 end
  local stated = def and tonumber(def.frameWidth)
  if stated and gbaObjectSize(stated, def.frameHeight or stated) then
    return 8
  end
  return nil
end

-- World-space half-width used by VoxelScene to centre the card on the
-- footprint (8 for 16px walkers, 16 for 32px big dolls). True Size uses
-- the species box (24 for a 48-wide card) so the slab is not a 16px speck.
function SpriteBillboards.halfWidth(def, iw, ih)
  local ww = select(1, SpriteBillboards.worldSize(def, iw, ih))
  if ww and ww > 0 then return ww / 2 end
  if isBigDef(def) then return 16 end
  return 8
end

Assets.register(SpriteBillboards.invalidate)

return SpriteBillboards
