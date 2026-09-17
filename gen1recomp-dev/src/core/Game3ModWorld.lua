-- THE OVERWORLD A MOD SEES.
--
-- `Game.overworld` is the object every renderer mod written for this project
-- reaches for: the map, the player, the neighbours, the camera. Gen 1 has an
-- OverworldController to hand over and Gen 2 has a World. Ruby has neither --
-- main.lua branches to src/core/Game3.lua and that ONE object is the
-- overworld, the battle, every menu and the renderer.
--
-- So this file builds the shape rather than aliasing an object, and the whole
-- discipline of it is in one rule: EVERY FIELD IS A LIVE READ OFF THE GAME,
-- and anything Ruby genuinely does not have is absent with a reason rather
-- than filled in with something plausible. A fabricated field that merely
-- looks right is worse than a missing one -- a mod reads it, gets a number
-- that means nothing, and has no way to tell. That is exactly what happened
-- when the loader handed Gen 3 mods Gold's modules, and building the shape is
-- not a licence to repeat it in a different place.
--
-- Nothing here caches. A warp replaces the map, a step moves the player, and
-- a view built once would keep reporting where the player used to be.

local ModWorld = {}

local Logger = require("src.core.Logger")
local MapNames = require("src.world.gen3.MapNames")

-- one line per unbacked push verb, not one per push
local warnedPush = {}

-- TWO VOCABULARIES FOR THE SAME FOUR DIRECTIONS.
--
-- Gen 1 names them for the d-pad -- up, down, left, right -- and that is the
-- mod API's vocabulary: a walk-replacing mod hands "up" to the push verbs and
-- assigns "up" to the player's facing. Ruby names them for the compass, and
-- every one of its own readers is written against those: deltaFromFacing
-- answers SOUTH for anything it does not recognise, so an untranslated "up"
-- does not fail loudly -- it silently means "down".
--
-- Translated here, at the boundary, in one place. Compass names pass through
-- unchanged so a mod that already speaks Ruby's is not mangled.
local COMPASS = {
  up = "north", down = "south", left = "west", right = "east",
  north = "north", south = "south", west = "west", east = "east",
}

local function compassOf(dir)
  return COMPASS[dir] or nil
end

-- Inverse of COMPASS: Gen 1 renderers (SpriteRenderer, FirstPerson.apparentFacing)
-- speak down/up/left/right. pose() translates at the boundary so STAND tables
-- and camera-relative facing keep working.
local PAD = {
  north = "up", south = "down", west = "left", east = "right",
  up = "up", down = "down", left = "left", right = "right",
}

local function padOf(dir)
  return PAD[dir] or nil
end

-- Gen 3 metatile geometry, and the two numbers a renderer uses to tell the
-- generations apart without asking which game is running: a Gen 3 METATILE is
-- 16x16 and IS one collision cell, where a Gen 1/2 block is 32x32 holding
-- four of them.
local BLOCK_TILES = 2
local BLOCK_CELLS = 1
local METATILE_PX = 16

function ModWorld.attach(Game3)

  local function cellAt(map, cx, cy)
    local w, h = map.width or 0, map.height or 0
    if cx < 0 or cy < 0 or cx >= w or cy >= h then return nil end
    return map.grid[cy * w + cx + 1]
  end

  -- fieldmap.c GetBorderBlockAt: outside the body the cartridge repeats a 2x2
  -- patch indexed by parity. blockAt border-extends this way because the mod's
  -- mesher walks a ring outside the map and expects the cartridge's answer,
  -- not a clamp -- clamping gives every ring cell the patch's FIRST entry, so
  -- three of every four come from the wrong quarter of the drawing.
  local function borderAt(map, cx, cy)
    local border = map.border
    if type(border) ~= "table" or #border < 4 then return nil end
    local slot = (cx + 1) % 2 + ((cy + 1) % 2) * 2
    return Game3.metatileOf(border[slot + 1])
  end

  -- The highest metatile id the importer wrote an entry for, plus one. nil
  -- when there is no behaviour table to count, so the caller falls through to
  -- the atlas size rather than to zero.
  local function definedMetatiles(spec)
    local behavior = spec and spec.behavior
    if type(behavior) ~= "table" then return nil end
    local top = -1
    for id in pairs(behavior) do
      local n = tonumber(id)
      if n and n > top then top = n end
    end
    if top < 0 then return nil end
    return top + 1
  end

  -- The tileset record, in the shape Gen3.isGen3 tests: blockTiles 2 and
  -- blockCells 1 are what identify a Gen 3 map to a mod, and `blocks` is
  -- deliberately absent -- Ruby has metatiles and no Gen 1 block table, and a
  -- mod that finds `blocks` will read it as one.
  -- Emerald DRAMATIC_SHAPE gen3_metatiles role owners are keyed
  -- P<hex>/S<hex> from Emerald ROM tileset header addresses
  -- (TILESET_03DF704 …). Ruby's extractor publishes gTileset_*
  -- names (and pair_N ids). Without this bridge, ctx.metaRole is
  -- nil on EVERY map and fences/grass/ledges/soil fall to the
  -- behaviour-only / wall-of-last-resort path.
  local EMERALD_TILESET_HEX = {
  ["gTileset_BattleArena"] = "03DFD04",
  ["gTileset_BattleDome"] = "03DFCBC",
  ["gTileset_BattleFactory"] = "03DFCD4",
  ["gTileset_BattleFrontier"] = "03DFC94",
  ["gTileset_BattleFrontierOutsideEast"] = "03DF86C",
  ["gTileset_BattleFrontierOutsideWest"] = "03DF854",
  ["gTileset_BattleFrontierRankingHall"] = "03DFDAC",
  ["gTileset_BattlePalace"] = "03DFCA4",
  ["gTileset_BattlePike"] = "03DFCEC",
  ["gTileset_BattlePyramid"] = "03DFD1C",
  ["gTileset_BattleTent"] = "03DFDC4",
  ["gTileset_BattleTower"] = "03DFC94",
  ["gTileset_BikeShop"] = "03DF9D4",
  ["gTileset_BrendansMaysHouse"] = "03DFAF4",
  ["gTileset_Building"] = "03DF884",
  ["gTileset_CableClub"] = "03DF95C",
  ["gTileset_Cave"] = "03DF8CC",
  ["gTileset_Contest"] = "03DFAC4",
  ["gTileset_Dewford"] = "03DF74C",
  ["gTileset_DewfordGym"] = "03DFBB4",
  ["gTileset_EliteFour"] = "03DFC7C",
  ["gTileset_EverGrande"] = "03DF80C",
  ["gTileset_Facility"] = "03DF9BC",
  ["gTileset_Fallarbor"] = "03DF7AC",
  ["gTileset_Fortree"] = "03DF7C4",
  ["gTileset_FortreeGym"] = "03DFC14",
  ["gTileset_General"] = "03DF704",
  ["gTileset_GenericBuilding"] = "03DFB6C",
  ["gTileset_InsideOfTruck"] = "03DFA94",
  ["gTileset_InsideShip"] = "03DFC44",
  ["gTileset_IslandHarbor"] = "03DFD64",
  ["gTileset_Lab"] = "03DFB0C",
  ["gTileset_Lavaridge"] = "03DF794",
  ["gTileset_LavaridgeGym"] = "03DFBE4",
  ["gTileset_Lilycove"] = "03DF7DC",
  ["gTileset_LilycoveMuseum"] = "03DFADC",
  ["gTileset_Mauville"] = "03DF77C",
  ["gTileset_MauvilleGameCorner"] = "03DFB84",
  ["gTileset_MauvilleGym"] = "03DFBCC",
  ["gTileset_MeteorFalls"] = "03DF92C",
  ["gTileset_MirageTower"] = "03DFD34",
  ["gTileset_Mossdeep"] = "03DF7F4",
  ["gTileset_MossdeepGameCorner"] = "03DFD4C",
  ["gTileset_MossdeepGym"] = "03DFC2C",
  ["gTileset_MysteryEventsHouse"] = "03DFDDC",
  ["gTileset_NavelRock"] = "03DFD94",
  ["gTileset_OceanicMuseum"] = "03DF944",
  ["gTileset_Pacifidlog"] = "03DF824",
  ["gTileset_Petalburg"] = "03DF71C",
  ["gTileset_PetalburgGym"] = "03DFB3C",
  ["gTileset_PokemonCenter"] = "03DF8B4",
  ["gTileset_PokemonDayCare"] = "03DF9A4",
  ["gTileset_PokemonFanClub"] = "03DF8FC",
  ["gTileset_PokemonSchool"] = "03DF8E4",
  ["gTileset_PrettyPetalFlowerShop"] = "03DF98C",
  ["gTileset_Rustboro"] = "03DF734",
  ["gTileset_RustboroGym"] = "03DFB9C",
  ["gTileset_RusturfTunnel"] = "03DF9EC",
  ["gTileset_SeashoreHouse"] = "03DF974",
  ["gTileset_SecretBase"] = "03DFC5C",
  ["gTileset_SecretBaseBlueCave"] = "03DFA4C",
  ["gTileset_SecretBaseBrownCave"] = "03DFA04",
  ["gTileset_SecretBaseRedCave"] = "03DFA7C",
  ["gTileset_SecretBaseShrub"] = "03DFA34",
  ["gTileset_SecretBaseTree"] = "03DFA1C",
  ["gTileset_SecretBaseYellowCave"] = "03DFA64",
  ["gTileset_Ship"] = "03DFC44",
  ["gTileset_Shop"] = "03DF89C",
  ["gTileset_Slateport"] = "03DF764",
  ["gTileset_Sootopolis"] = "03DF83C",
  ["gTileset_SootopolisGym"] = "03DFB54",
  ["gTileset_TrainerHill"] = "03DFD7C",
  ["gTileset_TrickHousePuzzle"] = "03DFBFC",
  ["gTileset_Underwater"] = "03DFB24",
  ["gTileset_UnionRoom"] = "03DFDF4",
  ["gTileset_Unused1"] = "03DF914",
  ["gTileset_Unused2"] = "03DFAAC",
}

  local function emeraldHex(name)
    if type(name) ~= "string" or name == "" then return nil end
    local hex = name:match("^TILESET_(%x+)$")
    if hex then return hex:upper() end
    return EMERALD_TILESET_HEX[name]
  end

  local function emeraldPairId(primaryName, secondaryName, fallback)
    local p = emeraldHex(primaryName)
    local s = emeraldHex(secondaryName)
    if p and s then return ("TILESET_%s_%s"):format(p, s) end
    if p then return ("TILESET_%s"):format(p) end
    return fallback
  end

  local function tilesetView(self, map)
    local id = map.tileset
    local spec = self.data.tilesets and self.data.tilesets.byId
      and self.data.tilesets.byId[id]
    local cols = (self.data.tilesets and self.data.tilesets.atlasCols)
      or Game3.ATLAS_COLS
    local bottom = self:layersFor(id)
    local iw = bottom and bottom.getWidth and bottom:getWidth()
      or cols * METATILE_PX
    local ih = bottom and bottom.getHeight and bottom:getHeight() or nil
    local primaryName = (spec and spec.primaryKey) or nil
    local secondaryName = spec and spec.secondaryKey or nil
    -- SEPARATE KEYS (dsvx-160-r8): roles/palings need Emerald TILESET_<p>_<s>
    -- hex, but sheet/atlas/UV lookup keys off data.tilesets.byId[pair_N].
    -- Putting emerald hex on tilesetView.id made Gen3Sheets.forTileset miss
    -- every pair -- meshes came back WHITE (water/NPC paths unaffected).
    -- Keep gTileset_* on primaryKey/secondaryKey for gen3_shapes / gen3_maps.
    local emeraldId = emeraldPairId(primaryName, secondaryName, id)
    return {
      id = id,                 -- pair_N: sheet / atlas / texture binding
      pairId = id,             -- alias of id (sheet key)
      emeraldId = emeraldId,   -- TILESET_<hex>_<hex>: owner / palings / roles
      -- THE CARTRIDGE'S OWN NAMES, and the reason this matters more than it
      -- looks. A renderer mod carries per-tileset shape profiles -- tree
      -- hulls, roof massing, counter pins -- keyed by exactly these strings.
      -- Handing over our ordinal (`pair_0`) instead meant every lookup missed
      -- and every cell fell to the profile of last resort, which is a
      -- full-height wall: Littleroot's border trees came out as a comb of
      -- black monoliths around the map.
      --
      -- Falls back to the id when the importer could not name a pair, which
      -- is a missed profile rather than a wrong one.
      primaryKey = primaryName or id,
      secondaryKey = secondaryName,
      -- both spellings: a mod may look for either
      primary = primaryName,
      secondary = secondaryName,
      -- Emerald TILESET_<hex> aliases (owner-key bridge; optional readers)
      primaryId = primaryName and emeraldHex(primaryName) and ("TILESET_" .. emeraldHex(primaryName)) or nil,
      secondaryId = secondaryName and emeraldHex(secondaryName) and ("TILESET_" .. emeraldHex(secondaryName)) or nil,
      blockTiles = BLOCK_TILES,
      blockCells = BLOCK_CELLS,
      cell = METATILE_PX,
      tilesPerRow = cols,
      imageWidth = iw,
      imageHeight = ih,
      -- HOW MANY METATILES ARE DEFINED, which is not the size of the atlas
      -- grid. The grid is always 32x32 = 1024 because that is how the
      -- importer lays a pair out; what a caller wants to know is how many of
      -- those slots the two halves actually fill, since it sizes shape tables
      -- from this. Counting the behaviour table is the honest answer: the
      -- importer writes one entry per metatile it read out of the cartridge.
      metatileCount = (spec and spec.metatileCount)
        or definedMetatiles(spec)
        or (cols * ((self.data.tilesets and self.data.tilesets.atlasRows)
          or Game3.ATLAS_COLS)),
      -- the two attribute planes the cartridge states outright, which is why
      -- a Gen 3 mesher does not have to infer them from pixels
      behavior = spec and spec.behavior or nil,
      layerType = spec and spec.layerType or nil,
    }
  end

  -- `def` is what a mod treats as the map's authored description. The two
  -- plane arrays are DERIVED from the grid word on every call rather than
  -- stored, because the word already holds both and a second copy could
  -- disagree with it.
  -- {w1, w2, w3, w4} -> the 8-byte little-endian string a Gen 3 reader
  -- decodes. nil for anything that is not a four-entry patch, so a reader
  -- falls back to borderBlock rather than decoding garbage.
  local function borderString(b)
    if type(b) ~= "table" or #b < 4 then return nil end
    local out = {}
    for i = 1, 4 do
      local w = math.floor(tonumber(b[i]) or 0) % 65536
      out[#out + 1] = string.char(w % 256, math.floor(w / 256))
    end
    return table.concat(out)
  end

  local function defView(self, map)
    local w, h = map.width or 0, map.height or 0
    local collision, elevation = {}, {}
    for i = 1, w * h do
      local word = map.grid[i] or 0
      collision[i] = Game3.collisionOf(word)
      elevation[i] = Game3.elevationOf(word)
    end
    -- Emerald RomExtractorGen3 stamps direction-keyed connections on Map.def.
    -- Ruby Gen3MapPack keeps the ROM list { dir, mapGroup, mapNum, offset }.
    -- Structures.smoothGen3Seams / openGen3Seams read byDir (c.map). Without
    -- this field on the mod map view, gen3ConnectionsByDir saw nil and never
    -- met a neighbour halfway (Oldale/R101 floating shelf).
    local connections
    do
      local rows = {}
      for _, c in ipairs(map.connections or {}) do
        if type(c) == "table" and type(c.dir) == "string" then
          local id = c.map
          if not id and c.mapGroup ~= nil and c.mapNum ~= nil then
            id = string.format("g%d_%d",
                               tonumber(c.mapGroup) or 0,
                               tonumber(c.mapNum) or 0)
          end
          if id then
            local list = rows[c.dir]
            if not list then list = {} rows[c.dir] = list end
            list[#list + 1] = { map = id, offset = tonumber(c.offset) or 0 }
          end
        end
      end
      if next(rows) then
        connections = {}
        for dir, list in pairs(rows) do
          local rec = { map = list[1].map, offset = list[1].offset }
          if #list > 1 then
            local also = {}
            for i = 2, #list do also[#also + 1] = list[i] end
            rec.also = also
          end
          connections[dir] = rec
        end
      end
    end
    return {
      id = map.id,
      -- THE CARTRIDGE'S OWN NAME FOR THIS MAP, e.g. "MauvilleCity".
      --
      -- A renderer mod keys its per-map shape data by the directory name,
      -- because that is the only identity a human can author against -- our
      -- ids are ordinals and name nothing. Stating ours lets those lookups
      -- hit; see src/world/gen3/MapNames.lua for why we state Ruby's own
      -- rather than borrowing the Emerald table's.
      name = MapNames.of(map.id),
      width = w,
      height = h,
      -- One Gen 3 map cell is one 16px metatile.  Neighbor walkers and ring
      -- mask builders use this instead of the Gen 1/2 32px block default.
      blockPx = METATILE_PX,
      tileset = map.tileset,
      mapType = map.mapType,
      outdoor = Game3.isOutdoorMapType(map.mapType) == true,
      connections = connections,
      collisionCells = collision,
      elevationCells = elevation,
      -- THE BORDER PATCH AS FOUR LITTLE-ENDIAN WORDS IN ONE 8-BYTE STRING,
      -- because that is the shape the reader decodes and nothing else is.
      --
      -- Both consumers -- the context's metatileAt and the border ring in
      -- Structures -- test `type(def.border) == "string" and #def.border >= 8`
      -- and unpack four u16s. Handed our Lua table {468, 469, 476, 477}
      -- instead, they fell back to borderBlock, which is ONE metatile, and
      -- filled the patch with it: every ring cell answered 468.
      --
      -- That is not a subtle error on screen. The crown scan groups a 2x2
      -- only when its quarters DIFFER ("a repeated metatile is a hedge and
      -- gets one small hull per cell"), so a uniform ring built a hedge of
      -- thin columns around every town where Emerald -- passing the real
      -- motif -- builds one round crown per tree. Littleroot's border,
      -- side by side, was the whole visible difference.
      border = borderString(map.border),
      borderBlock = map.border and Game3.metatileOf(map.border[1]) or nil,
      warps = map.warps,
      -- The object events, which the mod uses to tell a ROOM from a solid
      -- mass: TileShape fills every sealed pocket to eye height unless a warp
      -- or someone standing in it proves it is somewhere the player is meant
      -- to be. Behind a Pokemon Center counter there is no warp -- only the
      -- nurse -- so without these that pocket was filled from wall to wall.
      objects = map.objects,
    }
  end

  -- One map, in the shape a mod walks. Methods take (self, ...) so both
  -- `map:blockAt(x, y)` and `map.blockAt(map, x, y)` reach the same place --
  -- mods use both spellings, often pcall'd.
  -- ONE VIEW PER MAP, NOT ONE PER FRAME.
  --
  -- This used to build a fresh table on every call, and `modOverworldFields`
  -- calls it for the current map AND every neighbour. Two things made that
  -- ruinous rather than merely wasteful:
  --
  --   COST. defView materialises a collision and an elevation entry for every
  --   cell. Mauville plus its four connected routes is 22,400 cells, so a
  --   rebuild is 44,800 table stores -- and the cache signature in
  --   modOverworldFieldsCached contains camX/camY, which move every frame the
  --   player walks. That is roughly 2.7 million stores a second to re-answer
  --   questions whose answers had not changed.
  --
  --   IDENTITY. The mod caches its whole Gen 3 context as `ctxCache[map]`,
  --   keyed by THIS TABLE. A new table every frame means that cache never
  --   hits: it rebuilt the context, and with it buildElevationRanks over
  --   every cell, once per frame per map -- and kept the dead entry. The
  --   same lesson as Zoom.gateOK comparing the overworld by identity: a view
  --   that is live but freshly built is not the same thing as a live view.
  --
  -- The methods below close over `map` and read it on every call, so the view
  -- being reused does not make it a snapshot -- blockAt and friends stay live.
  -- The two eager PLANES in defView are the exception, and are what _gridRev
  -- is for: Game3.noteGridWrite bumps it wherever the engine writes a cell (a
  -- door opening, a decoration stamped, a scripted metatile), and that drops
  -- this entry so the planes are rebuilt.
  function Game3:modMapView(map)
    map = map or self.map
    if not (map and map.grid) then return nil end
    local cache = self._modMapViews
    if not cache then
      -- weak keys: a map the player has left is collectable, entry and all
      cache = setmetatable({}, { __mode = "k" })
      self._modMapViews = cache
    end
    -- THE KEY IS EVERY INPUT THE VIEW IS BUILT FROM, enumerated by reading
    -- defView and tilesetView rather than guessed at:
    --
    --   map._gridRev     defView's two per-cell planes are snapshots of the
    --                    grid; Game3.noteGridWrite bumps this on every write
    --   the pack table   tilesetView reads self.data.tilesets, which a
    --                    re-import replaces wholesale
    --   atlasCols/Rows   metatileCount and tilesPerRow come off them
    --   the tileset spec identity of byId[map.tileset], whose behavior and
    --                    layerType tables the view hands over directly
    --
    -- layersFor is deliberately NOT in here even though tilesetView calls it:
    -- it answers a DIFFERENT image per animation frame (animLayers, 4Hz), so
    -- keying on it would throw the view away several times a second -- while
    -- the only things taken from it, the atlas width and height, are the same
    -- in every frame of an animation.
    local store = self.data and self.data.tilesets
    local tsSpec = store and store.byId and store.byId[map.tileset]
    local sig = table.concat({
      tostring(tonumber(map._gridRev) or 0),
      tostring(store),
      tostring(store and store.atlasCols),
      tostring(store and store.atlasRows),
      tostring(store and store.byId and store.byId[map.tileset]),
      -- and the two attribute planes the view hands over BY REFERENCE, plus
      -- the count derived from one of them: a pack can be re-read in place
      -- without the spec table itself being replaced
      tostring(tsSpec and tsSpec.behavior),
      tostring(tsSpec and tsSpec.layerType),
      tostring(tsSpec and tsSpec.metatileCount),
    }, "|")
    local held = cache[map]
    if held and held.sig == sig and held.view then return held.view end
    local game = self
    local view = {
      id = map.id,
      generation = 3,
      def = defView(self, map),
      tileset = tilesetView(self, map),
      width = map.width or 0,
      height = map.height or 0,
      -- CELLS, which on Gen 3 is the same number as metatiles: one 16px
      -- metatile IS one collision cell (blockCells = 1), where a Gen 1/2 block
      -- holds four. Emerald's Map publishes both names; the voxel mod does
      -- arithmetic with these -- TileShape's sealed-pocket flood indexes
      -- `sealed[cy * map.widthCells + cx]` -- and WorldFillProps, finding them
      -- absent, fell back to `def.width * 2`, the Gen 1 answer, doubling
      -- every Hoenn map.
      widthCells = map.width or 0,
      heightCells = map.height or 0,
      -- THE DOOR BEHAVIOURS, as a set keyed the way cellTile answers.
      --
      -- The one missing field that cost the most: Structures.forMap caches
      -- its half-built result and THEN runs its passes, and the door fold is
      -- the first of them -- `if map.doorTiles[map:cellTile(cx, cy)]`. With
      -- no doorTiles that line threw, the caller's pcall swallowed it, and
      -- every later pass was skipped for the life of the map: no building
      -- runs, no roof massing, no carved crowns. Littleroot built 0 runs on
      -- Ruby and 277 on Emerald from the same mod, and that one line was the
      -- whole difference between textured cubes and sculpted trees.
      --
      -- Emerald's Gen 3 tileset lists these as { 0x60, 0x69, 0x6C }; pokeruby
      -- defines the same three (include/constants/metatile_behaviors.h).
      doorTiles = {
        [Game3.MB_NON_ANIMATED_DOOR] = true,
        [Game3.MB_ANIMATED_DOOR] = true,
        [Game3.MB_WATER_DOOR] = true,
      },
    }

    -- The metatile at a CELL, border-extended the cartridge's way outside the
    -- body. Gen 1's name for this, kept so a mod written against that engine
    -- reads the right thing.
    function view.blockAt(_, cx, cy)
      local word = cellAt(map, cx, cy)
      if word then return Game3.metatileOf(word) end
      return borderAt(map, cx, cy)
    end

    -- Gen 1 Map:setBlock, over this view's raw grid. Looks up Map.setBlock
    -- at call time so DRAMATIC_SHAPE's wrap (ChunkMesher.refresh) is the
    -- one that runs -- a local write here would skip the mesh invalidation.
    function view.setBlock(self, bx, by, block, impassable)
      local okM, MapMod = pcall(require, "src.world.Map")
      if okM and type(MapMod) == "table" and type(MapMod.setBlock) == "function" then
        return MapMod.setBlock(map, bx, by, block, impassable)
      end
      local i = game:gridIndex(map, bx, by)
      if not i or type(map.grid) ~= "table" then return end
      local cell = map.grid[i] or 0
      local mid = tonumber(block) or 0
      local elev = Game3.elevationBits(cell)
      local col = Game3.collisionOf(cell)
      if impassable ~= nil then
        col = impassable and 1 or 0
      end
      map.grid[i] = elev + (mid % 1024) + col * 1024
      Game3.noteGridWrite(map)
      if type(game.markTilesDirty) == "function" then
        pcall(game.markTilesDirty, game, map)
      end
    end

    function view.clearBlock(self, bx, by)
      local okM, MapMod = pcall(require, "src.world.Map")
      if okM and type(MapMod) == "table" and type(MapMod.clearBlock) == "function" then
        return MapMod.clearBlock(map, bx, by)
      end
    end

    -- CAN A WALKER STAND HERE. The engine's own verdict, not the collision
    -- bits alone.
    --
    -- Collision is only half the rule in Gen 3. WATER is collision 0 -- it has
    -- to be, you surf across it -- and what stops you walking onto it is its
    -- metatile BEHAVIOUR, which Game3:canStep tests (isSurfable, waterfalls,
    -- ledge lips, directional cliff edges, elevation). Answering from the
    -- collision bits alone said every lake and every stretch of sea was
    -- walkable, and a free walk took it at its word: the player rode a bike
    -- out across open water.
    --
    -- The contract the caller expects is the NON-surfing verdict -- it asks
    -- `isWalkableCell` first and only then allows water of its own accord
    -- when the player is surfing -- and canStep answers exactly that, because
    -- its surf branches read the same surfing flag.
    -- NON-SURFING land verdict, INDEPENDENT OF THE PLAYER.
    --
    -- canStep folds in the player's current elevation, facing and surfing
    -- flag. Structures (standGen3Ledges bank runs, apron fills, walkable
    -- ridge detection) asks this of ARBITRARY cells while the player stands
    -- somewhere else, so a zMismatch against the avatar made every terrace
    -- cell at a different elevation look impassable. Banking then failed and
    -- Oldale / Route 101 ridges stayed as sharp 90-degree walls. FreeMove
    -- also asks this first and only then allows water via isWaterCell when
    -- surfing -- so the answer here must stay the dry-land non-surfing one.
    function view.isWalkableCell(_, cx, cy)
      if not cellAt(map, cx, cy) then return false end
      if not Game3.walkable(map, cx, cy) then return false end
      local b = view.behaviorAt(_, cx, cy)
      if Game3.isSurfable(b) or Game3.isWaterfall(b) then return false end
      if Game3.ledgeDelta and Game3.ledgeDelta(b) then return false end
      return true
    end

    function view.elevationAt(_, cx, cy)
      local word = cellAt(map, cx, cy)
      if not word then return nil end
      return Game3.elevationOf(word)
    end

    -- Per-cell collision plane (bits 10-11). Emerald's Map exposes the same
    -- answer via layout collisionCells; Gen3 synthesizes from this when the
    -- def snapshot is thin.
    function view.collisionAt(_, cx, cy)
      local word = cellAt(map, cx, cy)
      if not word then return nil end
      return Game3.collisionOf(word)
    end

    -- The two attribute planes, per metatile id rather than per cell.
    function view.attributes(_, mid)
      local ts = view.tileset
      local b = ts.behavior and ts.behavior[mid] or 0
      local l = ts.layerType and ts.layerType[mid] or 0
      return b, l
    end

    -- THE REST OF THE MAP QUESTIONS A RENDERER ASKS.
    --
    -- Enumerated from the mod rather than added one crash at a time: it calls
    -- nine methods on a map and I had published two, so each run found the
    -- next missing one. Every answer below comes from Game3's own readers --
    -- the behaviour byte, the collision bits, the warp list -- so none of
    -- them is a guess.

    -- Inside the body. The ring outside is the border patch, and a caller
    -- that wants it asks blockAt, which border-extends; this is the question
    -- "is there a real cell here", which is what a camera uses to decide it
    -- has left the world.
    function view.inBounds(_, cx, cy)
      if type(cx) ~= "number" or type(cy) ~= "number" then return false end
      local w, h = map.width or 0, map.height or 0
      return cx >= 0 and cy >= 0 and cx < w and cy < h
    end

    -- metatile_behavior.c: the behaviour byte answers what a cell IS. Game3
    -- already classifies these and the renderer gets the same answer the
    -- game does rather than a second opinion.
    function view.behaviorAt(_, cx, cy)
      local word = cellAt(map, cx, cy)
      if not word then return 0 end
      local spec = game.data.tilesets and game.data.tilesets.byId
        and game.data.tilesets.byId[map.tileset]
      local behavior = spec and spec.behavior
      if type(behavior) ~= "table" then return 0 end
      return behavior[Game3.metatileOf(word)] or 0
    end

    -- WATER IS ELEVATION 1, which is how Emerald's engine answers this for a
    -- Gen 3 map (src/world/Map.lua, Map:isWaterCell) and how the cartridge
    -- itself tells surfable ground from walkable: every surfable cell in Hoenn
    -- sits at elevation 1 and nothing you walk on does. Collision must be clear
    -- as well.
    --
    -- This asked the behaviour byte instead, which also matches water-drawn
    -- cells at elevation 0 (shoreline transitions) and 3 (shallows beside
    -- land). The voxel mod builds a water cell at the water level and those at
    -- ground height, so every coast and pond came out stepped: a band of
    -- raised water around the real surface. Measured across the same eight
    -- maps in both engines, Emerald had one water height on all of them and
    -- Ruby two, with the extras exactly the elevation-0/3 cells -- Route 121
    -- matched Emerald's 186 cells at -2 and added 63 at ground level.
    function view.isWaterCell(_, cx, cy)
      local word = cellAt(map, cx, cy)
      if not word then return false end
      return Game3.elevationOf(word) == 1 and Game3.collisionOf(word) == 0
    end

    function view.isGrassCell(self, cx, cy)
      local b = view.behaviorAt(self, cx, cy)
      return b == Game3.MB_TALL_GRASS or b == Game3.MB_LONG_GRASS
    end

    -- WHAT A RENDERER GETS FOR `map:cellTile`, stated the way Emerald's engine
    -- states it for a Gen 3 map (src/world/Map.lua, Map:cellTile): 0xFF for
    -- any cell the collision bits block or that lies off the body, and the
    -- metatile's BEHAVIOUR BYTE otherwise.
    --
    -- This answered the metatile id, which is a different number in an
    -- overlapping range -- and every caller in the voxel mod was written
    -- against Emerald's meaning: the door fold compares it with `doorTiles`
    -- (door behaviours), the hop-lip rule and the collision-class shapes key
    -- off it too. A metatile id matched none of those, or matched the wrong
    -- ones by coincidence.
    function view.cellTile(_, cx, cy)
      local word = cellAt(map, cx, cy)
      if not word then return 0xFF end
      if Game3.collisionOf(word) ~= 0 then return 0xFF end
      local ts = view.tileset
      local mid = Game3.metatileOf(word)
      return (ts and ts.behavior and ts.behavior[mid]) or 0
    end

    function view.warpAtCell(_, cx, cy)
      return Game3.warpAt(map, cx, cy)
    end

    function view.isWarpTileCell(self, cx, cy)
      return view.warpAtCell(self, cx, cy) ~= nil
    end

    -- NOT SERVED, and named so. `tileAt` is a Gen 1/2 question: it reads
    -- tileset.blocks, four 8px tile ids per cell. A Gen 3 tileset has no such
    -- field -- the block id IS the metatile -- and the mod's own Gen 3 arm
    -- already branches on `tileset.blocks` being absent to take the metatile
    -- path instead. Supplying a tileAt would send it down the wrong branch.
    view.tileAt = nil

    view.game = game
    cache[map] = { view = view, sig = sig }
    return view
  end

  -- A map argument may be the live map, one of its views, or nil. Views carry
  -- the id they were built from, so a view of a NEIGHBOUR resolves to that
  -- neighbour rather than silently to the active map.
  function Game3:modResolveMap(map)
    if type(map) ~= "table" then return self.map end
    if map.grid then return map end
    local id = map.id or (map.def and map.def.id)
    if id ~= nil then
      if self.map and self.map.id == id then return self.map end
      -- Prefer the pack lookup: diorama neighbors can sit beyond one hop, and
      -- mapPlacements() only gathers CONNECTION_DRAW_HOPS by default.
      local found = self:lookupMapById(id)
      if found and found.grid then return found end
      for _, row in ipairs(self:connectedLayout(
          self.map, Game3.CONNECTION_VIEW_HOPS or 4) or {}) do
        if row.map and row.map.id == id then return row.map end
      end
    end
    return self.map
  end

  -- The world record the mod's `engineWorld` seam asks for: the atlas pair
  -- plus the metatile attributes, so the mod does not have to bake its own.
  -- Its own fallback returns `bottom = false` and sources images from an atlas
  -- it builds; this path exists so Ruby can hand over the atlas it already has.
  --
  -- nil when the tileset's art has not loaded, which the mod reads as "the
  -- host does not publish this" and falls back -- the right answer, since an
  -- atlas-less world record would texture nothing.
  function Game3:gen3WorldFor(def, map, tileset)
    -- The caller hands back what IT holds, which is the view from
    -- modMapView -- and a view has no `grid`, because the grid is the
    -- engine's. Resolving it to the live map is the whole of this line, and
    -- without it the seam answered nil for every map: the mod fell through to
    -- baking its own atlas, found no map_tilesets entry and meshed nothing.
    -- The symptom was two warnings in the MOD's log and silence in ours,
    -- which is why only running its arm found it.
    map = self:modResolveMap(map)
    if not (map and map.grid) then return nil end
    local id = map.tileset
    local bottom, top = self:layersFor(id)
    if not bottom then return nil end
    -- NEVER trust a bare tileset id string as the attribute view. Gen3.engineWorld
    -- passes map.tileset, which on the live engine map is "pair_N" / a number --
    -- truthy, so `tileset or tilesetView` used to keep the string and every
    -- world.attributes(mid) answered 0,0. Behaviour then collapsed to MB_NORMAL
    -- and the mesher extruded far fewer accurate roles than Emerald.
    local view = tileset
    if type(view) ~= "table" or type(view.behavior) ~= "table" then
      view = tilesetView(self, map)
    end
    if not view then return nil end
    local cols = view.tilesPerRow or Game3.ATLAS_COLS
    -- Keep the caller's def (usually the mod map view's planes).  A `local def`
    -- would shadow the parameter and read as nil on the RHS in Lua.
    local defRec = def
    if type(defRec) ~= "table" then defRec = map.def end
    if type(defRec) ~= "table" then defRec = {} end
    local width = tonumber(defRec.width) or (map.width or 0)
    local height = tonumber(defRec.height) or (map.height or 0)
    local collisionCells = defRec.collisionCells
    local elevationCells = defRec.elevationCells
    -- Emerald's layout extract always materialises both planes onto the map
    -- def. Ruby derives them in defView; if a caller handed a thin def (or an
    -- older cached view), rebuild from the live grid words so Gen3 ranks the
    -- same elevationCells Emerald publishes.
    local cellsNeeded = (width > 0 and height > 0) and (width * height) or 0
    local function planeOk(cells)
      return type(cells) == "table" and cellsNeeded > 0
         and cells[1] ~= nil and cells[cellsNeeded] ~= nil
    end
    if cellsNeeded > 0 and not planeOk(elevationCells) then
      elevationCells = {}
      for i = 1, cellsNeeded do
        elevationCells[i] = Game3.elevationOf(map.grid[i] or 0)
      end
      defRec.elevationCells = elevationCells
    end
    if cellsNeeded > 0 and not planeOk(collisionCells) then
      collisionCells = {}
      for i = 1, cellsNeeded do
        collisionCells[i] = Game3.collisionOf(map.grid[i] or 0)
      end
      defRec.collisionCells = collisionCells
    end
    if (not tonumber(defRec.width) or tonumber(defRec.width) == 0) and width > 0 then
      defRec.width = width
    end
    if (not tonumber(defRec.height) or tonumber(defRec.height) == 0) and height > 0 then
      defRec.height = height
    end
    local function indexOf(cx, cy)
      if not (width > 0) or cx < 0 or cy < 0 or cx >= width then return nil end
      if cy >= height then return nil end
      return cy * width + cx + 1
    end
    return {
      generation = 3,
      tileset = view,
      pair = view,
      bottom = bottom,
      top = top,
      width = bottom.getWidth and bottom:getWidth() or cols * METATILE_PX,
      height = bottom.getHeight and bottom:getHeight() or nil,
      cols = cols,
      cell = METATILE_PX,
      metatiles = view.metatileCount,
      -- Same planes Emerald's Map.def carries, so Gen3 can rank without
      -- re-deriving from the grid when the engine seam is the one asked.
      elevationCells = elevationCells,
      collisionCells = collisionCells,
      hasElevation = elevationCells ~= nil,
      hasCollisionCells = collisionCells ~= nil,
      attributes = function(mid)
        local b = view.behavior and view.behavior[mid] or 0
        local l = view.layerType and view.layerType[mid] or 0
        return b, l
      end,
      metatileAt = function(cx, cy)
        if type(map.blockAt) == "function" then
          local ok, id = pcall(map.blockAt, map, cx, cy)
          if ok then return id end
        end
        local i = indexOf(cx, cy)
        if not i then return nil end
        return Game3.metatileOf(map.grid[i] or 0)
      end,
      collisionAt = function(cx, cy)
        if not collisionCells then return nil end
        local i = indexOf(cx, cy)
        return i and collisionCells[i] or nil
      end,
      elevationAt = function(cx, cy)
        if not elevationCells then return nil end
        local i = indexOf(cx, cy)
        return i and elevationCells[i] or nil
      end,
      originOf = function(id)
        id = tonumber(id)
        if not id then return 0, 0 end
        return (id % cols) * METATILE_PX, math.floor(id / cols) * METATILE_PX
      end,
      -- WHETHER A METATILE'S TOP HALF DRAWS ABOVE THE PLAYER -- and this was
      -- BACKWARDS, which the voxel mod reads as the difference between a
      -- crown or roof and a second course of ground.
      --
      -- include/global.fieldmap.h states the three layer types by the BG
      -- layers they use:
      --   NORMAL   middle + top      -> the top half is on BG1, above sprites
      --   COVERED  bottom + middle   -> the top half is on BG2, BELOW sprites
      --   SPLIT    bottom + top      -> the top half is on BG1, above sprites
      -- So the answer is `layerType ~= COVERED`. This said `== COVERED`: every
      -- roof and treetop (NORMAL) was reported as ground, and every picket
      -- fence and path-over-grass (COVERED) as overhead cover. Ruby's own 2D
      -- pass had it right all along (metatileTopPassMode: "LAYER_COVERED is
      -- BG3 + BG2, never BG1"), and so does the mod's fallback when a host
      -- offers nothing (`layer ~= 1`) -- this copy was the only wrong one, so
      -- on Ruby the mod got the opposite of what it would have got from
      -- silence, while Emerald's engine answered correctly.
      topIsAbovePlayer = function(mid)
        local l = view.layerType and view.layerType[mid] or 0
        return l ~= Game3.LAYER_COVERED
      end,
    }
  end

  -- ------------------------------------------------------------ the actors
  --
  -- ------------------------------------------------------- A POSEABLE ACTOR
  --
  -- Gen 1 renderers walk the cast calling `entity:pose()`, which hands back a
  -- SPRITE OBJECT plus position, facing, animation phase and flip, and the
  -- object answers `:resolveImage()` and carries a `.def` describing its
  -- sheet. Ruby has none of that: its NPCs are plain records and the drawing
  -- is Game3's own, resolving a sheet and a quad at paint time.
  --
  -- So the object is built here over Ruby's real data -- data.sprites.byId
  -- keyed by the NPC's graphicsId -- rather than the cast being left out, and
  -- every field in it is a live read.
  --
  -- WHY `walker` IS FALSE (Gen 1 WALK tables are the wrong layout).
  --
  -- The consumer's default path picks a sheet row from Gen 1's tables:
  --   STAND = { down = 0, up = 1, left = 2, right = 2 }
  --   WALK  = { down = 3, up = 4, left = 5, right = 5 }
  -- Ruby's standing rows match STAND. Its walking rows do not: south is
  -- [3,0,4,0], north [5,1,6,1], west [7,2,8,2]. So `walker` stays false and
  -- VoxelScene.frameFor drives the stride through Game3.poseFor on the
  -- def's own face/walk tables -- the same answer the flat OW path draws.
  -- Resolve VAR_OBJ_GFX_ID_* (Mauville bard is GFX_VAR_0 -> GFX_BARD+n) and
  -- build a Gen1-shaped sprite object. Missing byId rows with no ow_<id>.png
  -- on disk (the bard family) return nil; VoxelScene skips that card.
  local function graphicsIdOf(self, npc)
    if not npc then return 0 end
    local gid = npc.graphicsId
    if npc.id == "player" and type(self.playerGraphicsId) == "function" then
      gid = self:playerGraphicsId()
    end
    if type(self.resolveGraphicsId) == "function" then
      gid = self:resolveGraphicsId(gid) or gid
    end
    return gid or 0
  end

  local function spriteFor(self, npc)
    local okG, gid = pcall(graphicsIdOf, self, npc)
    if not okG then return nil end
    gid = gid or 0
    local sprites = self.data and self.data.sprites
    local okS, spec = pcall(Game3.spriteSpec, sprites, gid)
    if not okS then spec = nil end
    if not spec then
      -- Same path Game3's extract writes for every OW sheet. Only publish a
      -- stub when the file actually loads: Mauville's bard (GFX_BARD+n) was
      -- never extracted. Cache misses so pose() does not retry grabImage
      -- every frame. Nil matches 2D ("no img -> skip"); VoxelScene drops
      -- the card instead of retiring the pipeline.
      local miss = self._modSpriteMiss
      if not miss then miss = {}; self._modSpriteMiss = miss end
      if miss[gid] then return nil end
      local path = ("assets/generated/sprites/ow_%d.png"):format(gid)
      local ok, image = false, nil
      if type(self.grabImage) == "function" then
        ok, image = pcall(self.grabImage, self, path)
      end
      if not (ok and image) then
        miss[gid] = true
        return nil
      end
      spec = {
        id = gid,
        path = path,
        width = METATILE_PX,
        height = METATILE_PX * 2,
        frameCount = 9,
      }
    end
    if type(spec.path) ~= "string" or spec.path == "" then return nil end
    local game = self
    local path = spec.path
    local sprite = {
      def = {
        id = spec.id or gid,
        image = path,
        frameWidth = spec.width,
        frameHeight = spec.height,
        width = spec.width,
        height = spec.height,
        frames = spec.frameCount,
        frameCount = spec.frameCount,
        walker = false,
        -- Gen 3 OW anim tables (same records Game3.poseFor / drawOwSprite use)
        face = spec.face,
        walk = spec.walk,
        monIcon = false,
        -- Ruby's overworld art is true-colour GBA and is never re-mapped, so
        -- a consumer must not run it through a palette pass.
        trueColor = true,
        -- NOT height>16: that flagged every 16x32 OW walker as big and
        -- SpriteBillboards cached one mesh per sheet (frame 0 forever).
        -- Card size comes from frameWidth/Height + footAnchor/halfWidth.
        big = false,
      },
    }
    function sprite:resolveImage()
      if type(game.grabImage) ~= "function" then return nil end
      local ok, image = pcall(game.grabImage, game, path)
      if not ok then return nil end
      return image
    end
    return sprite
  end

  -- Ruby's NPCs carry x/y in cells and the renderer derives pixels; Gen 1's
  -- carry both. Both spellings are published because mods read both, and both
  -- come off the same source rather than one being remembered.
  local function actorView(self, npc)
    local game = self
    if type(npc) ~= "table" then npc = {} end
    local okSp, sprite = pcall(spriteFor, self, npc)
    if not okSp then sprite = nil end
    local cx, cy = npc.x or 0, npc.y or 0
    local px, py = cx * METATILE_PX, cy * METATILE_PX
    -- The PLAYER's pixel position is the free walk's while one is driving:
    -- freeWalkPx is where the body actually stands, and the cell it reports
    -- is only the cell that position falls in. Every other actor is on its
    -- cell by definition.
    if npc.id == "player" and self.freeWalkPx then
      px, py = self.freeWalkPx, self.freeWalkPy or py
    end
    local actor = {
      id = npc.id or npc.localId,
      cellX = cx,
      cellY = cy,
      px = px,
      py = py,
      facing = npc.facing,
      elevation = npc.currentElevation or npc.elevation or 0,
      hidden = npc.hidden == true,
      -- Live source for VAR_OBJ_GFX refreshes (Mauville bard / hipster / ...).
      graphicsId = (function()
        local okG, gid = pcall(graphicsIdOf, self, npc)
        if okG then return gid end
        return npc.graphicsId or 0
      end)(),
      sprite = sprite,
      npc = nil,   -- filled below; the consumer poses THIS object
    }

    -- The contract, verbatim: sprite, x, y, facing, phase, flip.
    -- Facing is Gen 1 pad vocabulary for SpriteRenderer / FirstPerson.
    -- phase is 0 when still; when moving it is walk progress in (0,1] so
    -- VoxelScene.frameFor can call Game3.poseFor with the same t the flat
    -- path uses (not Gen 1's 0/1 foot phase -- Ruby sheets need the cycle).
    -- Sprite is re-resolved each pose so a VAR_OBJ_GFX_ID write (the bard's
    -- sheet) lands on the next frame instead of staying stuck on the spawn
    -- snapshot -- and so a previously-nil sheet can appear once extracted.
    function actor:pose()
      local src = npc
      if self.id == "player" then
        local gid = self.graphicsId
        if type(game.playerGraphicsId) == "function" then
          local okP, got = pcall(game.playerGraphicsId, game)
          if okP and got ~= nil then gid = got end
        end
        src = { id = "player", graphicsId = gid }
      end
      local okSp, sp = pcall(spriteFor, game, src)
      if okSp and sp then
        sprite = sp
        self.sprite = sp
        local okG, gid = pcall(graphicsIdOf, game, src)
        if okG then self.graphicsId = gid end
      end

      -- Live facing + pixels: NPC records move under us between view rebuilds.
      local compassFacing
      local px, py = self.px, self.py
      if self.id == "player" then
        compassFacing = game.facing or self.facing
        if game.freeWalkPx then
          px, py = game.freeWalkPx, game.freeWalkPy or py
        elseif type(game.visualTile) == "function" then
          local okV, vx, vy = pcall(game.visualTile, game)
          if okV and vx then
            px, py = vx * METATILE_PX, vy * METATILE_PX
          end
        end
      else
        compassFacing = npc.facing or self.facing
        if type(game.npcVisual) == "function" then
          local okV, vx, vy = pcall(game.npcVisual, game, npc)
          if okV and vx then
            px, py = vx * METATILE_PX, vy * METATILE_PX
          end
        end
        -- Snapshot only: player px/py write-through to freeWalkPx and must
        -- not be assigned here (a grid walk would latch free-walk forever).
        self.facing = compassFacing
        self.px, self.py = px, py
      end

      -- Same moving/t rules as Game3:drawPlayer / drawOneObject.
      local moving, t = false, 1
      if self.id == "player" then
        if (game.walkCooldown or 0) > 0 and not game.lockAnim then
          moving = true
          if type(game.walkProgress) == "function" then
            local okT, got = pcall(game.walkProgress, game)
            if okT and type(got) == "number" then t = got end
          end
        elseif (game.freeWalkAnim or 0) > 0 then
          -- FreeMove refreshes freeWalkAnim while covering ground; animate
          -- off playSeconds so legs cycle without a Gen 1 animClock.
          moving = true
          local period = Game3.WALK_PERIOD
          local okG, G = pcall(require, "src.core.Game")
          if (okG and G.save and G.save.onBike) or game.running then
            period = Game3.RUN_PERIOD
          end
          if period and period > 0 then
            t = ((game.playSeconds or 0) % period) / period
          end
        end
      else
        moving = ((npc.cooldown or 0) > 0
                  or Game3.wanderDirs(npc.movementType) == "place")
                 and not npc.lockAnim
        if moving and (npc.cooldown or 0) > 0 then
          local dur = npc.walkDuration or Game3.WALK_PERIOD
          if dur <= 0 then dur = Game3.WALK_PERIOD end
          t = 1 - npc.cooldown / dur
          if t < 0 then t = 0 elseif t > 1 then t = 1 end
        elseif moving then
          t = ((npc.placeT or 0) % 0.5) / 0.5
        end
      end

      -- phase > 0 means "moving" for frameFor's poseFor path; never 0 mid-stride.
      local phase = 0
      if moving then
        if t <= 0 then t = 1e-6 end
        if t > 1 then t = 1 end
        phase = t
      end

      local facing = padOf(compassFacing) or "down"
      -- nil sprite is a skipped card, never a throw: Mauville's bard and
      -- any Center NPC whose ow_<id>.png was never extracted stay invisible.
      return sprite, px, py, facing, phase, false
    end

    -- an actor is its own npc, so a consumer reaching either way lands here
    actor.npc = actor
    return actor
  end

  -- The actor data Ruby DOES have, for a mod that wants positions without
  -- Gen 1's pose contract. Published under its own name rather than in
  -- `entities`, so nothing walks it expecting to be able to :pose() it.
  function Game3:modActorLists()
    local out = { npcs = {}, ghosts = {}, poseable = false }
    if not (self.map and self.map.grid) then return out end
    for _, npc in ipairs(self:npcsFor(self.map) or {}) do
      out.npcs[#out.npcs + 1] = actorView(self, npc)
    end
    for _, row in ipairs(self:mapPlacements(self.map) or {}) do
      if row.map and row.map ~= self.map then
        for _, npc in ipairs(self:npcsFor(row.map) or {}) do
          local actor = actorView(self, npc)
          -- world pixels, like the neighbour offsets they come from; see the
          -- note on ow.ghosts below for what publishing cells here did
          actor.ox = (tonumber(row.ox) or 0) * Game3.TILE
          actor.oy = (tonumber(row.oy) or 0) * Game3.TILE
          out.ghosts[#out.ghosts + 1] = actor
        end
      end
    end
    return out
  end

  -- THE PLAYER'S ACTOR WRITES BACK.
  --
  -- Every other actor in the view is a read-only snapshot, which is right:
  -- nothing a mod does should move an NPC behind the script VM's back. The
  -- PLAYER is the exception, because the one contract Gen 1 publishes for
  -- replacing the walk is that the mod moves the player by assigning to the
  -- very fields it read -- `p.cellX`, `p.px`, `p.facing` -- on the object in
  -- `state.player`. On Gen 1 that object IS the engine's player, so the
  -- writes land; here it is a view, and they were landing on a table nobody
  -- read. First person looked like a free camera bolted to a body that could
  -- not be steered.
  --
  -- So: those fields, and only those, forward to the game. Anything else
  -- written stays local to the view, which keeps a mod stashing its own
  -- bookkeeping on the actor from corrupting engine state.
  --
  -- px/py are WORLD PIXELS and go to freeWalkPx/freeWalkPy, the continuous
  -- position Game3:visualTile returns while a free walk drives. cellX/cellY
  -- are the logical cell -- still the thing every game rule is written
  -- against -- so they go straight to playerX/playerY.
  local PLAYER_WRITES = {
    -- a mod's "up" is Ruby's "north"; an unrecognised name is DROPPED
    -- rather than stored, because storing it would read back as south from
    -- every one of Ruby's own direction readers
    facing = function(g, v)
      local dir = compassOf(v)
      if dir then g.facing = dir end
    end,
    cellX = function(g, v) g.playerX = tonumber(v) or g.playerX end,
    cellY = function(g, v) g.playerY = tonumber(v) or g.playerY end,
    px = function(g, v) g.freeWalkPx = tonumber(v) end,
    py = function(g, v) g.freeWalkPy = tonumber(v) end,
    -- Gen 1's walk-cycle clock: the legs animate off it while the engine
    -- thinks the player is standing still, which is exactly the case a
    -- continuous walk is in
    bumpFrames = function(g, v) g.freeWalkAnim = tonumber(v) end,
  }

  -- the same fields, read back off the game -- see __newindex for why a
  -- written field must never be served from a cached copy
  -- EVERY written field, read live. The `actor` the proxy wraps was built
  -- before the write and is a snapshot of that instant, so serving a written
  -- field from it reports the position as of the last rebuild -- which is the
  -- same stale answer the per-proxy store gave, reached a different way.
  local PLAYER_READS = {
    facing = function(g) return g.facing end,
    cellX = function(g) return g.playerX end,
    cellY = function(g) return g.playerY end,
    px = function(g)
      return g.freeWalkPx or (g.playerX or 0) * METATILE_PX
    end,
    py = function(g)
      return g.freeWalkPy or (g.playerY or 0) * METATILE_PX
    end,
    bumpFrames = function(g) return g.freeWalkAnim end,
    -- Live: FreeMove.blockedCell reads p.surfing every slide. A snapshot
    -- taken when the view was built stayed false after useSurf mounted,
    -- so the free walk still refused water cells in voxel first-person.
    surfing = function(g) return g.surfing == true end,
    -- Live: FreeMove.tick gates on p.moving / p.inputLocked every frame.
    -- Baking them into the cached overworld fields (and omitting walkCooldown
    -- from the rebuild signature) left moving=true after a connection
    -- lerp finished -- FreeMove stood aside forever until a menu/bike
    -- rebuild cleared the stale snapshot. Same class of bug as surfing.
    moving = function(g) return (g.walkCooldown or 0) > 0 end,
    inputLocked = function(g)
      return type(g.displayGateOK) == "function" and not g:displayGateOK()
    end,
  }

  -- THE STORE LIVES ON THE GAME, NOT ON THIS PROXY.
  --
  -- The view is rebuilt whenever its signature moves, and camX/camY are in
  -- that signature -- so on a real map, where the camera follows the player
  -- every frame, it is rebuilt every frame. A store held here would be empty
  -- again each time.
  --
  -- That is not a cosmetic loss. A continuous walk reads back the position it
  -- wrote (`if p.px ~= lastPx then adopt(p) end`) to find out whether
  -- something else moved the player. Reading back the SNAPPED cell instead
  -- looks exactly like that, so it re-adopted the cell centre every frame and
  -- threw away the fraction of a pixel it had just covered. The body creeps
  -- and never crosses a cell: the d-pad appears dead in first person, which
  -- is precisely what it did on the phone while a desk harness with a still
  -- camera walked fine.
  local function writeThroughPlayer(self, actor)
    local store = self._modPlayerStore
    if not store then
      store = {}
      self._modPlayerStore = store
    end
    return setmetatable({}, {
      __index = function(_, key)
        local read = PLAYER_READS[key]
        if read then return read(self) end
        local held = store[key]
        if held ~= nil then return held end
        return actor[key]
      end,
      __newindex = function(_, key, value)
        local write = PLAYER_WRITES[key]
        if write then
          -- WRITE THROUGH AND KEEP NO COPY. A stored copy would shadow the
          -- engine: gridHandleInput drops the free-walk position when the
          -- grid walk reclaims the wheel, and a cached px here would go on
          -- reporting where the free walk had left the body long after the
          -- engine had moved on. The read comes back off the game instead,
          -- through actorView, which is the live answer by construction.
          return write(self, value)
        end
        -- anything the contract does not name is the mod's own bookkeeping:
        -- kept, on the game so it survives a rebuild, and never forwarded
        store[key] = value
      end,
    })
  end

  -- The mod's ring-mask builder asks the host for a pure neighbor walk.  The
  -- shared OverworldController implementation is a Gen 1/2 walker: it expects
  -- direction-keyed connections and 32px blocks, while Ruby stores a numeric
  -- Gen 3 connection list and 16px metatiles.  Adapt Ruby's own map graph here
  -- so distant connected bodies are meshed/masked at the same offsets as NPCs.
  function Game3:modComputeNeighbors(rootId, hops, reachW, reachH)
    local root = self:lookupMapById(rootId)
    if not root then return {} end
    hops = math.max(0, math.floor(tonumber(hops) or 0))
    local px = Game3.TILE
    local out = {}
    local placed = { [root.id or rootId] = true }
    local queue = { { map = root, ox = 0, oy = 0, hops = 0 } }
    local qi = 1
    local function inReach(map, ox, oy)
      if not (reachW and reachH) then return false end
      return ox + (map.width or 0) * px > -reachW
         and ox < (root.width or 0) * px + reachW
         and oy + (map.height or 0) * px > -reachH
         and oy < (root.height or 0) * px + reachH
    end
    while queue[qi] do
      local cur = queue[qi]
      qi = qi + 1
      for _, conn in ipairs(cur.map.connections or {}) do
        if Game3.spatialConnection(conn) then
          local dest = self:lookupMap(conn.mapGroup, conn.mapNum)
          local id = dest and (dest.id or Game3.mapId(conn.mapGroup, conn.mapNum))
          if dest and id and not placed[id] then
            placed[id] = true
            local dx, dy = Game3.neighborOrigin(conn, cur.map, dest)
            if dx then
              local ox = cur.ox + dx * px
              local oy = cur.oy + dy * px
              local depth = cur.hops + 1
              local reaches = inReach(dest, ox, oy)
              if depth <= hops or reaches then
                out[#out + 1] = { id = id, ox = ox, oy = oy }
                if depth < hops or reaches then
                  queue[#queue + 1] = {
                    map = dest, ox = ox, oy = oy, hops = depth,
                  }
                end
              end
            end
          end
        end
      end
    end
    return out
  end

  -- The overworld view. Built per call; see the note at the top about why
  -- nothing here is remembered.
  -- The fields, rebuilt on demand. Called by the proxy below, never directly:
  -- a caller that held THIS would hold a snapshot.
  function Game3:modOverworldFields()
    if not (self.map and self.map.grid) then return nil end
    local game = self
    local ow = {
      isOverworld = true,
      generation = 3,
      game = game,
    }

    ow.map = self:modMapView(self.map)

    -- The player's own extra fields, folded onto the posed actor built below
    -- rather than a second object: a renderer that finds the player in
    -- `entities` and again in `state.player` must find the SAME table, or it
    -- draws them twice.
    local playerExtra = {
      surfing = self.surfing == true,
      -- inputLocked is a live PLAYER_READ (displayGateOK); do not bake here.
      -- DRAMATIC_SHAPE's VoxelScene culls the local OW card in first person
      -- by marking the pose `isPlayer`. Emerald can use table identity
      -- (`e == state.player`); Ruby's writeThrough proxy is rebuilt with the
      -- view, so identity alone can miss. Stamp the flag on the actor (and
      -- again on the proxy store below) so the cull still fires.
      isPlayer = true,
    }

    ow.camera = { x = self.camX or 0, y = self.camY or 0 }

    -- Signature matches OverworldController.computeNeighbors.  VoxelScene
    -- calls the function unbound and supplies a maps table first; Ruby's
    -- adapter deliberately uses the live Game3 map pack instead.
    ow.computeNeighbors = function(_, rootId, hops, reachW, reachH)
      return game:modComputeNeighbors(rootId, hops, reachW, reachH)
    end
    -- Flat id -> {width,height,blockPx} table the ring-mask builder indexes.
    -- Gen3MapPack nests real maps under `.maps` and has no blockPx, so the
    -- Emerald-shaped data.maps walk cannot be handed through unchanged.
    ow.mapsForMasks = setmetatable({}, {
      __index = function(_, id)
        local map = game:lookupMapById(id)
        if not map then return nil end
        return {
          width = map.width or 0,
          height = map.height or 0,
          blockPx = Game3.TILE,
        }
      end,
    })

    -- A script, a warp fade or a battle transition is running: a renderer
    -- that keeps drawing the diorama through one of these paints over the
    -- transition, so this is published rather than left for it to guess.
    ow.transitioning = self:modWorldBusy()

    -- Gen 1 OverworldState:paletteNameFor. Ruby's art is true-colour GBA and
    -- is never shade-remapped (see Game3 pipeline ctx.paletteFor = nil), so
    -- the honest answer is nil. Present as a method so DRAMATIC_SHAPE's
    -- BattleScene.paletteFor can call it without crashing.
    function ow.paletteNameFor(_, _map)
      return nil
    end

    -- Connected maps and where they sit relative to this one, which is what
    -- lets a mesher build the seam rather than a wall at the map edge.
    --
    -- ox/oy ARE WORLD PIXELS HERE, AND CELLS ON THE WAY IN.
    --
    -- connectedLayout answers in the current map's TILE space -- its own
    -- comment says so ("Origins are in the current map's tile space"), and
    -- the engine's draw multiplies by Game3.TILE to place one. The contract
    -- a renderer reads is pixels: Gen 1 builds these as `conn.offset * 32`
    -- (a Gen 1 block being 32px), and the mesher translates a neighbour's
    -- geometry by them outright -- `Mat4.translate(nb.ox, 0, nb.oy)` -- into
    -- a mesh whose own coordinates are world pixels.
    --
    -- Handing over cells therefore placed every neighbour at a SIXTEENTH of
    -- its distance, which is not a subtle drift: Mauville's four connected
    -- routes landed stacked on top of Mauville. It reads as one map with
    -- other maps' buildings, cliffs and NPCs painted through it, and it is
    -- also why it crawled -- five full map meshes, with their shadow casters,
    -- all competing for the same few hundred pixels of depth buffer.
    local CELL_PX = Game3.TILE
    ow.neighbors = {}
    -- Diorama cameras see past one hop.  Use the view-hop gather so maps that
    -- still intersect the camera are meshed, matching where ghost NPCs stand.
    local placements = self:connectedLayout(
      self.map, Game3.CONNECTION_VIEW_HOPS or 4) or {}
    for _, row in ipairs(placements) do
      if row.map and row.map ~= self.map then
        ow.neighbors[#ow.neighbors + 1] = {
          map = self:modMapView(row.map),
          ox = (tonumber(row.ox) or 0) * CELL_PX,
          oy = (tonumber(row.oy) or 0) * CELL_PX,
        }
      end
    end

    -- THE CAST.
    --
    -- Gen 1 calls the drawable set `entities` and the ones on neighbouring
    -- maps `ghosts`, and a renderer walks them calling `entity:pose()`. These
    -- were empty for a while because Ruby's NPCs are plain records and could
    -- not answer that; actorView builds the object over them now, so the cast
    -- appears rather than the world being unpopulated.
    --
    -- The PLAYER is one of them. Gen 1 keeps them in `entities` and marks the
    -- one that is the player through `state.player`, so a renderer can leave
    -- the card out in first person where it would fill the lens from inside.
    ow.npcs = {}
    for _, npc in ipairs(self:npcsFor(self.map) or {}) do
      ow.npcs[#ow.npcs + 1] = actorView(self, npc)
    end

    local player = actorView(self, {
      id = "player",
      x = self.playerX, y = self.playerY,
      facing = self.facing,
      graphicsId = self:playerGraphicsId(),
      currentElevation = self.currentElevation,
      hidden = false,
    })
    for key, value in pairs(playerExtra) do player[key] = value end
    -- moving / inputLocked are live PLAYER_READS (walkCooldown / displayGateOK).
    -- Do not bake onto the actor snapshot: the fields cache can survive a
    -- finished seam step and FreeMove would see a sticky moving=true.
    player = writeThroughPlayer(self, player)
    -- Also on the proxy store: view rebuilds mint a new empty proxy each
    -- time, and VoxelScene may compare across two reads. The store outlives
    -- the proxy, so `player.isPlayer` keeps answering true after a rebuild.
    player.isPlayer = true
    ow.player = player

    ow.entities = { player }
    for _, actor in ipairs(ow.npcs) do
      ow.entities[#ow.entities + 1] = actor
    end

    -- A GHOST'S OFFSET IS WORLD PIXELS TOO, for the same reason and with a
    -- louder symptom than the map one.
    --
    -- The renderer adds it straight onto a sprite's own pixel position --
    -- `px = vx + g.ox, py = g.npc.py + g.oy` -- and Gen 1 fills it from the
    -- same pixel offset its neighbour list carries. Publishing cells put all
    -- 108 people standing on Mauville's four connected routes at a sixteenth
    -- of their distance, which lands them in and around Mauville itself: a
    -- city of nine object events with a hundred and eighteen figures in it,
    -- each one also casting into the shadow pass.
    ow.ghosts = {}
    for _, row in ipairs(placements) do
      if row.map and row.map ~= self.map then
        local gx = (tonumber(row.ox) or 0) * Game3.TILE
        local gy = (tonumber(row.oy) or 0) * Game3.TILE
        for _, npc in ipairs(self:npcsFor(row.map) or {}) do
          local actor = actorView(self, npc)
          actor.ox, actor.oy = gx, gy
          actor.map = self:modMapView(row.map)
          ow.ghosts[#ow.ghosts + 1] = actor
        end
      end
    end

    -- THE TWO VERBS A REPLACED WALK CALLS BACK WITH.
    --
    -- Gen 1 puts both on the controller, and a mod that owns the walk uses
    -- them rather than reimplementing what they do: `interact` is the A
    -- button (Ruby's tryTalk -- the NPC in front, a counter reached across,
    -- the metatile underfoot), and `onStepComplete` is the landing pipeline
    -- fired once per cell crossed (Game3:stepArrived -- trainer sight lines,
    -- a field UI already up, wild encounters).
    --
    -- Written with a dot and an ignored first argument so `state:interact()`
    -- and `state.interact(state)` both reach the game, which is how mods
    -- spell these.
    function ow.interact(_)
      return game:tryTalk()
    end

    function ow.onStepComplete(_)
      -- A WARP FIRST, because the cell may not be a place to arrive at all.
      -- Ruby hangs warps off the step onto a tile (tryWalk); a continuous
      -- walk has no such step, so the exit mat it just walked onto has to be
      -- asked about here or the player is sealed inside the building.
      if game:tryWarpOnArrival() then return true end
      -- A COMPLETED CROSSING IS NO LONGER THE LANDING TILE.
      --
      -- ignoreWarp is set on entering a building so the player does not
      -- bounce straight back out through the mat they arrived on. The engine
      -- clears it in exactly two places -- at the end of a completed tryWalk
      -- step, and in gridHandleInput when the pad is released -- and a free
      -- walk runs NEITHER. So it stayed true for the whole visit and
      -- tryWarpOnArrival refused at its first line: the player could walk
      -- onto the exit mat of a Centre, a Mart or the Game Corner and nothing
      -- would ever happen.
      --
      -- Cleared AFTER the warp check, not before, which is the order tryWalk
      -- uses: the check reads the value the arrival was made under, and only
      -- a crossing that did NOT warp clears it. Clearing first would let two
      -- adjacent mats -- a house doorway is exactly that -- warp the player
      -- out the moment they shuffled sideways onto the second one.
      --
      -- And only when no warp fired: a taken warp has already entered the
      -- next map, which set its OWN ignoreWarp, and wiping that here would
      -- put the player straight back through the door they just came in.
      game.ignoreWarp = false
      return game:stepArrived()
    end

    -- the engine's bonk clock, which a free walk keeps draining so stepping
    -- back onto the grid does not inherit a cooldown frozen mid-rung
    ow.bumpCooldown = game.bumpCooldown or 0

    -- THE BLOCKED-PUSH VERBS, ON THE STATE.
    --
    -- A free walk that pushes firmly into something that refused hands the
    -- direction to these, and the engine decides whether the push means
    -- anything: walking off a map edge is a connection step, walking into a
    -- ledge is a hop. They are called as `state:checkEdgeExit(dir)` -- on THE
    -- VIEW, not on the controller module. Putting them on the module was
    -- exactly the nil-index-inside-the-mod that naming them was supposed to
    -- prevent; it crashed the moment a free walk reached a map edge.
    --
    -- Each delegates to the engine's own handler rather than restating it.
    -- Ruby's edge and ledge rules are long (connections, escape warps, the
    -- lerp-from-outside-the-map trick, ledge behaviour matching the walked
    -- direction, the catch-up discard at a seam) and a second copy would
    -- drift from the one the grid walk uses.
    local function deltaOf(dir)
      return Game3.deltaFromFacing(compassOf(dir) or game.facing or "south")
    end

    function ow.checkEdgeExit(_, dir)
      local map = game.map
      if not map then return false end
      local dx, dy = deltaOf(dir)
      local nx, ny = (game.playerX or 0) + dx, (game.playerY or 0) + dy
      -- only a genuine edge: inside the body this is not our question, and
      -- tryWalk would take an ordinary step the free walk has not asked for
      if nx >= 0 and ny >= 0
          and nx < (map.width or 0) and ny < (map.height or 0) then
        return false
      end
      return game:tryWalk(dx, dy) == true
    end

    function ow.checkLedgeHop(_, dir)
      local dx, dy = deltaOf(dir)
      return game:tryLedgeHop(game.map, dx, dy) == true
    end

    -- A GEN 3 DOOR IS A WARP ON A COLLISION TILE, which is why none of the
    -- Gen 1 verbs above can open one.
    --
    -- Gen 1 warps a walk through a CARPET: canCollisionWarp gates it and
    -- Warp.onCollision reads a carpet table. Ruby has no carpets -- its doors
    -- are warp tiles the step is refused by, and the warp fires from the
    -- refusal inside tryWalk. So a free walk pushes into a door, is told
    -- "tile", asks the four Gen 1 verbs, and every one of them correctly says
    -- no. The player stands in front of the Pokemon Center perfectly lined up
    -- and nothing happens.
    --
    -- This is the Gen 3 shaped question, under its own name. The mod calls it
    -- only if it exists (`state.checkDoorWarp and ...`), so Gen 1 and Gen 2 --
    -- where it does not -- skip the line entirely.
    --
    -- Delegates to tryWalk rather than restating the door rules, which are
    -- long and exact: arrow warps fire only from the matching direction,
    -- animated doors only walking NORTH into them, Mt Pyre holes fall
    -- instead, Petalburg gym doors are A-press only, a coord event on the mat
    -- beats the warp, and an NPC parked on the tile blocks it. Gating on
    -- warpAt first keeps this from taking an ordinary step: with no warp on
    -- the cell there is nothing here to do.
    function ow.checkDoorWarp(_, dir)
      local map = game.map
      if not map then return false end
      local dx, dy = deltaOf(dir)
      local nx, ny = (game.playerX or 0) + dx, (game.playerY or 0) + dy
      if not Game3.warpAt(map, nx, ny) then return false end
      return game:tryWalk(dx, dy) == true
    end

    -- Named and refusing, for the reasons each carries. A push simply does
    -- not fire; nothing indexes nil.
    local PUSH_UNBACKED = {
      checkBoulderPush =
        "Strength boulders are moved by Game3's script VM, which has no "
        .. "standalone verb a walk can call",
      canCollisionWarp =
        "Gen 1 asks this before consulting warp CARPETS, which Gen 3 has "
        .. "none of -- its doors are warps on collision tiles instead",
      takeWarp =
        "follows from canCollisionWarp; Ruby takes a warp from the step that "
        .. "was refused by the door tile, inside tryWalk",
    }
    for name, why in pairs(PUSH_UNBACKED) do
      ow[name] = function()
        if not warnedPush[name] then
          warnedPush[name] = true
          Logger.info("overworld view: %s has no Gen 3 backing: %s", name, why)
        end
        return false
      end
    end

    -- the seam the mod tries before baking its own atlas
    function ow.gen3WorldFor(_, def, map, tileset)
      return game:gen3WorldFor(def, map, tileset)
    end

    return ow
  end

  -- ONE SET OF FIELDS PER STATE, not per read.
  --
  -- The proxy rebuilds on demand so a reader always sees the live game, but
  -- rebuilding on EVERY read means two fields of the same view come from two
  -- different builds -- and then `state.player` and `state.entities[1]` are
  -- different tables describing the same person. A renderer that marks the
  -- player by identity (Gen 1's does, to leave the card out in first person)
  -- fails to find them and draws them twice.
  --
  -- So the build is memoized against a signature of everything it reads. The
  -- signature is cheap; the build walks the map and the cast.
  function Game3:modOverworldFieldsCached()
    local map = self.map
    if not (map and map.grid) then
      self._modOwFields, self._modOwSig = nil, nil
      return nil
    end
    local sig = table.concat({
      -- the map's identity AND its grid revision: a scripted cell write (a
      -- door, a decoration) changes neither the map table nor the player, so
      -- without the revision the whole view -- planes included -- would keep
      -- answering from before the write.
      tostring(map), tostring(map._gridRev),
      tostring(self.playerX), tostring(self.playerY),
      tostring(self.facing), tostring(self.camX), tostring(self.camY),
      tostring(self.field), tostring(self.surfing), tostring(self.phase),
      tostring(self.npcByMap),
    }, "|")
    if self._modOwSig == sig and self._modOwFields then
      return self._modOwFields
    end
    local fields = self:modOverworldFields()
    self._modOwFields, self._modOwSig = fields, sig
    return fields
  end

  -- THE OVERWORLD, with a STABLE IDENTITY.
  --
  -- The first version returned the freshly built table itself, which was live
  -- but not the same object twice -- and identity turns out to be load
  -- bearing. The engine's free-roam gate is `Zoom.gateOK(top, overworld)`, and
  -- its first test is `top ~= overworld`. A mod reads BOTH -- the stack top
  -- and Game.overworld -- and hands them to that gate, so two equally live
  -- tables fail it every time and the mode can never be switched on. The
  -- symptom is a hotkey that silently does nothing.
  --
  -- So: one table per game, whose __index resolves every field on read. Stable
  -- to compare, still never a snapshot.
  -- The proxy exists from the first ask and OUTLIVES a map change, because a
  -- mod that wrapped keypressed at load time holds whatever this returned
  -- then -- before any map existed. Its fields answer nil while there is no
  -- map, which is the same thing a nil overworld says, without the identity
  -- changing underneath a holder.
  function Game3:modOverworld()
    local proxy = self._modOverworldProxy
    if proxy then return proxy end
    local game = self
    proxy = setmetatable({}, {
      __index = function(_, key)
        if key == "overworld" or key == "world" then return proxy end
        local fields = game:modOverworldFieldsCached()
        if not fields then return nil end
        return fields[key]
      end,
      __newindex = function(t, key, value) rawset(t, key, value) end,
    })
    self._modOverworldProxy = proxy
    return proxy
  end

  -- Gen 1's state stack, as much of it as the free-roam gate needs. Ruby has
  -- no stack -- `self.field` is its one screen -- so `top()` answers the
  -- overworld exactly when the player is looking at it, which is the question
  -- Zoom.gateOK is really asking, and nil otherwise so the gate refuses during
  -- a menu, a script or the boot cinema.
  -- Publish the two names on the INSTANCE, not only through the mod facade.
  --
  -- A mod that wraps `function Game:keypressed(key)` has its wrapper called as
  -- a method on the live Game3, so inside it `self` is the raw instance and
  -- the facade is not in the path at all. DRAMATIC_SHAPE's wrapper reads
  -- `self.stack:top()` and `self.overworld` and hands both to the engine's
  -- free-roam gate; with neither on the instance the gate saw nil and refused
  -- every press, so its hotkey silently did nothing and Ruby's own key 3 --
  -- TILT -- ran instead.
  function Game3:publishModWorld()
    -- Always rebuild/upgrade the standing overlay stack (push/pop for
    -- BattleExit). Do not clobber the mod manager's real StateStack.
    local standing = self:modStack()
    local cur = rawget(self, "stack")
    if not cur or cur == standing or type(cur.push) ~= "function" then
      self.stack = standing
    end
    self.overworld = self:modOverworld()
    -- `save.options` too, and for the same reason. Every engine path around a
    -- display hotkey ends in the three lines Gen 1 runs -- syncOptions, the
    -- tilt exclusion, writeOptions -- and a mod delegating to them rather than
    -- reimplementing them reads `game.save.options` to do it. Ruby only built
    -- that table when the mod MANAGER opened, so the first hotkey press in a
    -- session indexed nil and took the game down.
    if type(self.modOptionsStore) == "function" then
      pcall(self.modOptionsStore, self)
    end
  end

  -- Gen 1 BattleExit pushes a fade state onto Game.stack. Ruby has no
  -- StateStack during play -- only this standing overlay -- so push/pop
  -- have to be real methods, not missing. Overlay states own update while
  -- they are on top (BattleExit.install pumps them from Game3:logicStep).
  local function ensureOverlay(stack, game)
    if type(stack.push) == "function" and type(stack.pop) == "function"
        and type(stack._overlay) == "table" then
      stack.states = stack._overlay
      return stack
    end
    local overlay = stack._overlay
    if type(overlay) ~= "table" then
      overlay = {}
      stack._overlay = overlay
    end
    stack.states = overlay
    local innerTop = stack.top
    function stack:push(state, ...)
      overlay[#overlay + 1] = state
      local enter = state and state.enter
      if type(enter) == "function" then pcall(enter, state, ...) end
    end
    function stack:pop()
      local state = table.remove(overlay)
      local exitfn = state and state.exit
      if type(exitfn) == "function" then pcall(exitfn, state) end
      return state
    end
    function stack:top()
      if #overlay > 0 then return overlay[#overlay] end
      if type(innerTop) == "function" then return innerTop(self) end
      if not game:displayGateOK() then return nil end
      return game:modOverworld()
    end
    return stack
  end

  function Game3:modStack()
    local game = self
    local stack = self._modStack
    if stack then return ensureOverlay(stack, game) end
    stack = {
      top = function()
        if not game:displayGateOK() then return nil end
        return game:modOverworld()
      end,
      states = {},
    }
    ensureOverlay(stack, game)
    self._modStack = stack
    return stack
  end

  -- True while something owns the screen that is not free roam: a menu, a
  -- script waiting, a fade. displayGateOK is Game3's own name for the
  -- inverse, and reusing it means this cannot drift away from what the
  -- engine actually considers free roam.
  function Game3:modWorldBusy()
    return not self:displayGateOK()
  end

end

return ModWorld



