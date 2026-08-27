-- Encounter Radar: what the ground you are standing on can actually produce.
--
-- Gen 1 had one wild table per map, so "what lives here" was one answer.  Gen 2
-- has up to seven for the same tile: grass splits three ways on the clock, surf
-- is its own table, and each of the three rods reads its own row list.  This
-- reads the merged tables and pages through every one of them.
--
-- THREE DATASET SHAPES REACH THIS FILE, and none of them is detected by asking
-- which engine is running -- only by what the data looks like:
--
--   per-map, Gen 1     encounters[MAP] = { grass = { rate, slots[10] }, water }
--                      slot odds come from constants.encounterBuckets, out of
--                      256, and the rods live in field.fishing
--   per-map, Gen 2     the same, plus grass.byTime.morn / .nite, each record
--                      carrying its own `buckets`; rods in field.fishGroups
--   kind-keyed, Gen 2  encounters.grass[MAP] = { rates = { MORN = ... },
--                      slots = { MORN = { ... } } }, odds out of 100, and
--                      encounters.fishGroups[GROUP][rod]
--
-- The page/render half below never sees any of that: an adapter hands it
-- { title, tod, rows, total, note } and nothing else.
--
-- Odds are the slot share within an encounter -- the cumulative threshold
-- tables the roll compares against, summed per species.  The bottom line
-- carries the other half of the story: the per-step rate for grass and surf,
-- the bite chance for a rod.  Both stay in the raw form the engine rolls
-- rather than a rounded percentage, because that is the number the cartridge
-- actually uses.
return function(mod)
  mod.options:define({
    { key = "enabled", label = "ENABLED", type = "toggle", default = true },
    { key = "owned", label = "MARK OWNED", type = "toggle", default = true },
    { key = "overlay", label = "WALK OVERLAY", type = "toggle", default = true },
    { key = "overlayOdds", label = "OVERLAY ODDS", type = "toggle",
      default = false },
    { key = "overlayRows", label = "OVERLAY ROWS", type = "number",
      default = 3, min = 1, max = 6, step = 1 },
    { key = "overlayWidth", label = "OVERLAY WIDTH", type = "number",
      default = 10, min = 5, max = 20, step = 1 },
    { key = "overlayAlpha", label = "OVERLAY ALPHA", type = "number",
      default = 70, min = 0, max = 100, step = 10 },
  })

  -- Cumulative thresholds out of 256 (GrassMonProbTable / WaterMonProbTable).
  -- A per-map Gen 2 record carries its own copy, so these are the fallback for
  -- one that arrived without.
  local GEN2_GRASS_BUCKETS = { 77, 154, 205, 230, 243, 253, 256 }
  local GEN2_WATER_BUCKETS = { 154, 230, 256 }
  -- The kind-keyed dataset states the same spread out of 100 instead
  -- (data/wild/probabilities.asm), and nothing in it carries a threshold list.
  local KIND_GRASS_CHANCES = { 30, 60, 80, 90, 95, 99, 100 }
  local KIND_WATER_CHANCES = { 60, 90, 100 }

  local RODS = {
    { key = "old", item = "OLD_ROD", label = "OLD ROD" },
    { key = "good", item = "GOOD_ROD", label = "GOOD ROD" },
    { key = "super", item = "SUPER_ROD", label = "SUPER ROD" },
  }

  -- One period vocabulary out of three engines' worth: MORNING / MORN, and
  -- NITE / NIGHT / DARK (the palette's dark rooms reuse the night list).
  local TOD_KEY = {
    MORN = "MORN", MORNING = "MORN",
    DAY = "DAY",
    NITE = "NITE", NIGHT = "NITE", DARK = "NITE",
  }

  local function todKey(tod)
    return TOD_KEY[tod or "DAY"] or "DAY"
  end

  local function percent(weight, total)
    if not (weight and total) or weight <= 0 or total <= 0 then return nil end
    local n = math.floor(weight * 100 / total + 0.5)
    if n < 1 then n = 1 end
    return n
  end

  local function speciesName(id)
    local ok, def = pcall(function() return mod.content.pokemon:get(id) end)
    if ok and type(def) == "table" and type(def.name) == "string"
        and def.name ~= "" then
      return def.name
    end
    return (tostring(id):gsub("^SPECIES_", ""))
  end

  -- The ROM writes species 0 in a fishing row to mean "no fish, roll the map's
  -- water table instead"; an imported cache may spell that NO_ITEM.
  local function realSpecies(id)
    if id == nil or id == 0 or id == "NO_ITEM" then return nil end
    return id
  end

  -- ------- tallies

  -- One species can hold several slots; the radar wants one row per species
  -- with the shares added up and the levels collapsed into a range.
  local function newTally()
    return { byId = {}, order = {} }
  end

  local function tallyAdd(tally, species, level, weight)
    species = realSpecies(species)
    if not species then return end
    local row = tally.byId[species]
    if not row then
      row = { species = species, min = level, max = level, weight = 0 }
      tally.byId[species] = row
      tally.order[#tally.order + 1] = row
    end
    row.weight = row.weight + (weight or 0)
    if level then
      if not row.min or level < row.min then row.min = level end
      if not row.max or level > row.max then row.max = level end
    end
  end

  local function tallyRows(tally)
    if #tally.order == 0 then return nil end
    table.sort(tally.order, function(a, b)
      if a.weight ~= b.weight then return a.weight > b.weight end
      return tostring(a.species) < tostring(b.species)
    end)
    return tally.order
  end

  -- A threshold list is cumulative, so a slot owns the gap below its own entry.
  -- Which list applies is decided by LENGTH: a ten-entry Kanto table and a
  -- seven-entry Johto one are both plausible here, and the slot count is the
  -- only thing that tells them apart.
  local function sized(list, n)
    if type(list) == "table" and #list == n then return list end
    return nil
  end

  local function thresholdsFor(slots, own, constants, fallback)
    local n = #slots
    return sized(own, n) or sized(constants, n) or sized(fallback, n)
  end

  local function thresholdRows(slots, thresholds)
    if type(slots) ~= "table" or #slots == 0 or not thresholds then
      return nil, nil
    end
    local tally, previous = newTally(), 0
    for i, slot in ipairs(slots) do
      local top = thresholds[i]
      if type(slot) == "table" and top then
        tallyAdd(tally, slot.species, slot.level, top - previous)
        previous = top
      end
    end
    return tallyRows(tally), thresholds[#thresholds]
  end

  -- Gen 1's Good and Super Rods pick uniformly inside their group: an odd
  -- random byte is no bite, and otherwise a two-bit index rerolls until it
  -- lands inside the group (item_effects.asm ItemUseGoodRod .RandomLoop).
  local function uniformRows(list)
    if type(list) ~= "table" or #list == 0 then return nil, nil end
    local tally = newTally()
    for _, slot in ipairs(list) do
      if type(slot) == "table" then
        tallyAdd(tally, slot.species, slot.level, 1)
      end
    end
    return tallyRows(tally), #list
  end

  -- ------- dataset access, all of it forgiving
  --
  -- data.field is deliberately unbacked on one of the Gen 2 paths, so reaching
  -- into it has to be allowed to simply fail rather than take the mod down.

  local function encounterRecord(id)
    local ok, value = pcall(function() return mod.content.encounters:get(id) end)
    return ok and value or nil
  end

  local function fieldTable(game, key)
    local ok, value = pcall(function() return game.data.field[key] end)
    if ok and type(value) == "table" then return value end
    return nil
  end

  local function constantBuckets(game)
    local ok, value = pcall(function()
      return game.data.constants.encounterBuckets
    end)
    if ok and type(value) == "table" then return value end
    return nil
  end

  -- ------- terrain pages

  -- Both per-map shapes at once: a record whose grass/water hold a flat slot
  -- list.  byTime is what makes it a Gen 2 one, and its absence is the whole
  -- difference between three grass pages and one.
  local function perMapPages(add, record, buckets)
    local function terrain(kind, title, def, fallback, tod)
      if type(def) ~= "table" then return end
      local slots = def.slots
      if type(slots) ~= "table" or #slots == 0 then return end
      local rows, total =
        thresholdRows(slots, thresholdsFor(slots, def.buckets, buckets, fallback))
      if not rows then return end
      add({ kind = kind, title = title, tod = tod, rows = rows, total = total,
            rate = tonumber(def.rate) or 0 })
    end

    local grass = record.grass
    if type(grass) == "table" then
      local byTime = grass.byTime
      if type(byTime) == "table" and (byTime.morn or byTime.nite) then
        terrain("grass", "GRASS MORN", byTime.morn or grass,
          GEN2_GRASS_BUCKETS, "MORN")
        terrain("grass", "GRASS DAY", grass, GEN2_GRASS_BUCKETS, "DAY")
        terrain("grass", "GRASS NITE", byTime.nite or grass,
          GEN2_GRASS_BUCKETS, "NITE")
      else
        terrain("grass", "GRASS", grass, GEN2_GRASS_BUCKETS, nil)
      end
    end
    terrain("water", "SURF", record.water, GEN2_WATER_BUCKETS, nil)
  end

  -- The kind-keyed shape: one table per encounter kind, each keyed by map, and
  -- a grass row that carries its three periods as two parallel maps rather
  -- than a nested table.
  local function kindPages(add, mapId)
    local grassKind = encounterRecord("grass")
    local entry = type(grassKind) == "table" and grassKind[mapId]
    if type(entry) == "table" and type(entry.slots) == "table" then
      for _, period in ipairs({ { "MORN", "GRASS MORN" }, { "DAY", "GRASS DAY" },
                                { "NITE", "GRASS NITE" } }) do
        local slots = entry.slots[period[1]]
        if type(slots) == "table" and #slots > 0 then
          local rows, total = thresholdRows(slots,
            thresholdsFor(slots, nil, nil, KIND_GRASS_CHANCES))
          if rows then
            local rate = entry.rates and entry.rates[period[1]]
            add({ kind = "grass", title = period[2], tod = period[1],
                  rows = rows, total = total, rate = tonumber(rate) or 0 })
          end
        end
      end
    end

    local waterKind = encounterRecord("water")
    local water = type(waterKind) == "table" and waterKind[mapId]
    if type(water) == "table" and type(water.slots) == "table" then
      local rows, total = thresholdRows(water.slots,
        thresholdsFor(water.slots, nil, nil, KIND_WATER_CHANCES))
      if rows then
        add({ kind = "water", title = "SURF", rows = rows, total = total,
              rate = tonumber(water.rate) or 0 })
      end
    end
  end

  -- ------- rod pages
  --
  -- Three walks, because the three datasets disagree about where a rod's rows
  -- live, whether the comparison is `<` or `<=`, and whether there is a
  -- threshold at all.

  -- field.fishGroups[GROUP].rods[rod]: rows walked until the rolled byte is
  -- <= the row's chance, so a row owns the gap ABOVE the previous threshold
  -- with the walk starting at -1 (engine/events/fish.asm `Fish`).
  local function rodRowsInclusive(rows, timeGroups, tod)
    if type(rows) ~= "table" or #rows == 0 then return nil, nil end
    local tally, previous = newTally(), -1
    for _, row in ipairs(rows) do
      local chance = tonumber(row.chance) or 0
      local weight = chance - previous
      if weight < 0 then weight = 0 end
      previous = chance
      local species, level = row.species, row.level
      if row.timeGroup then
        local pair = timeGroups and timeGroups[row.timeGroup]
        local slot = pair and ((tod == "NITE") and pair.nite or pair.day)
        species = slot and slot.species
        level = slot and slot.level
      end
      tallyAdd(tally, species, level, weight)
    end
    return tallyRows(tally), previous + 1
  end

  -- encounters.fishGroups[GROUP][rod]: the same table read with a strict `<`,
  -- so a row owns the gap BELOW its own threshold and the walk starts at 0.
  -- A row may carry its day/nite pair inline instead of an index.
  local function rodRowsExclusive(rows, timeGroups, tod)
    if type(rows) ~= "table" or #rows == 0 then return nil, nil end
    local tally, previous = newTally(), 0
    for _, row in ipairs(rows) do
      local chance = tonumber(row.chance) or 0
      local weight = chance - previous
      if weight < 0 then weight = 0 end
      previous = chance
      local key = (tod == "NITE") and "nite" or "day"
      local slot = row[key]
      if not slot and row.timeGroup and timeGroups then
        local pair = timeGroups[row.timeGroup]
        slot = pair and pair[key]
      end
      slot = slot or row
      tallyAdd(tally, slot.species, slot.level, weight)
    end
    return tallyRows(tally), previous
  end

  local function rodPages(add, game, mapId, mapDef, tod)
    local fishGroup = mapDef and mapDef.fishGroup

    -- per-map Gen 2: the groups hang off field, keyed by the map header byte
    local groups = fieldTable(game, "fishGroups")
    if groups then
      local group = fishGroup and groups[fishGroup]
      if type(group) == "table" and type(group.rods) == "table" then
        local timeGroups = fieldTable(game, "timeFishGroups")
        for _, rod in ipairs(RODS) do
          local rows, total =
            rodRowsInclusive(group.rods[rod.key], timeGroups, tod)
          if rows then
            add({ kind = "rod", title = rod.label, rows = rows, total = total,
                  note = "BITE " .. (tonumber(group.chance) or 0) .. "/256" })
          end
        end
      end
      return
    end

    -- kind-keyed Gen 2: the groups are a kind of their own, and the rod lists
    -- sit directly on the group rather than under a `rods` table
    local kindGroups = encounterRecord("fishGroups")
    if type(kindGroups) == "table" then
      local group = fishGroup and kindGroups[fishGroup]
      if type(group) == "table" then
        local timeGroups = encounterRecord("timeFishGroups")
        for _, rod in ipairs(RODS) do
          local rows, total =
            rodRowsExclusive(group[rod.key], timeGroups, tod)
          if rows then
            add({ kind = "rod", title = rod.label, rows = rows, total = total,
                  note = "BITE " .. (tonumber(group.chance) or 0) .. "/256" })
          end
        end
      end
      return
    end

    -- Gen 1: one rule per rod rather than per map.  The Old Rod always hooks,
    -- the Good Rod has a fixed pair, and only the Super Rod is per-map -- so
    -- the first two are gated on the map having water at all, or they would
    -- offer a Magikarp inside every house in Kanto.
    local fishing = fieldTable(game, "fishing")
    if not fishing then return end
    local record = encounterRecord(mapId)
    local water = record and record.water
    local hasWater = type(water) == "table" and type(water.slots) == "table"
      and #water.slots > 0 and (tonumber(water.rate) or 0) > 0
    for _, rod in ipairs(RODS) do
      local def = fishing[rod.item]
      if type(def) == "table" then
        if def.always and hasWater then
          local rows, total = uniformRows({ def.always })
          if rows then
            add({ kind = "rod", title = rod.label, rows = rows, total = total,
                  note = "ALWAYS BITES" })
          end
        else
          local list = def.pool
          if not list and def.perMap then
            local perMap = fieldTable(game, def.perMap)
            list = perMap and perMap[mapId]
          end
          -- a per-map group is its own proof that this map can be fished
          if list and (hasWater or def.perMap) then
            local rows, total = uniformRows(list)
            if rows then
              -- the rejection loop retries until it bites or rolls odd, which
              -- makes the bite odds size/(size+4) rather than a flat half
              add({ kind = "rod", title = rod.label, rows = rows,
                    total = total,
                    note = "BITE " .. #list .. "/" .. (#list + 4) })
            end
          end
        end
      end
    end
  end

  -- ------- the page list

  local function buildPages(game, mapId, mapDef, tod)
    local pages = {}
    local now = todKey(tod)

    local function add(page)
      -- a rate of zero is a table the engine can never roll; say so rather
      -- than listing mons that cannot appear
      local rate = page.rate
      local never = rate ~= nil and rate <= 0
      pages[#pages + 1] = {
        kind = page.kind,
        title = page.title,
        tod = page.tod,
        rows = never and {} or page.rows,
        total = page.total,
        note = page.note or (never and "NEVER HERE")
          or (rate and ("STEP " .. rate .. "/256")) or "",
      }
    end

    local record = encounterRecord(mapId)
    local grass = type(record) == "table" and record.grass
    local water = type(record) == "table" and record.water
    local perMap = (type(grass) == "table" and type(grass.slots) == "table")
      or (type(water) == "table" and type(water.slots) == "table")
    if perMap then
      perMapPages(add, record, constantBuckets(game))
    else
      kindPages(add, mapId)
    end

    rodPages(add, game, mapId, mapDef, now)

    if #pages == 0 then
      pages[1] = { title = "NO WILD DATA", rows = {}, note = "" }
    end
    return pages
  end

  -- Published so a companion mod -- or a test -- can read the same table the
  -- screen draws without going through the UI.  mapDef is an argument because
  -- the live map carries the def the engine's own fishing roll reads, which is
  -- not necessarily the registry's copy.
  mod.exports.report = function(mapId, tod, mapDef)
    local game = mod.game
    if not (game and mapId) then return nil end
    if mapDef == nil then
      local ok, def = pcall(function() return mod.content.maps:get(mapId) end)
      mapDef = ok and def or nil
    end
    return buildPages(game, mapId, mapDef, tod or "DAY")
  end

  -- ------- the screen

  -- The cached period the world already keeps; asking it to recompute can
  -- rebuild the tile atlases when the clock has just rolled over, which is not
  -- something a menu should trigger.
  local function timeOfDay(overworld)
    local tod = overworld and overworld.tod
    if type(tod) == "string" and tod ~= "" then return tod end
    if overworld and overworld.timeOfDay then
      local ok, value = pcall(overworld.timeOfDay, overworld)
      if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "DAY"
  end

  -- The landmark name the Gen 2 map-name sign uses, flattened out of its
  -- two-line form.  Gen 1 has no landmark table, and a map id reads well
  -- enough once the underscores are gone.
  local function placeName(game, mapId, mapDef)
    local landmarks = fieldTable(game, "townMap")
    landmarks = landmarks and landmarks.landmarks
    local entry = landmarks and mapDef and mapDef.landmark
      and landmarks[mapDef.landmark]
    local name = entry and entry.name
    if type(name) == "string" and name ~= "" then
      return (name:gsub("[\n\f\v]", " "))
    end
    return (tostring(mapId):gsub("_", " "))
  end

  local function levelText(row)
    if not row.min then return nil end
    if row.max and row.max ~= row.min then
      return "LV " .. row.min .. "-" .. row.max
    end
    return "LV " .. row.min
  end

  local function itemsFor(game, page)
    local dex = (game.save and game.save.pokedex) or {}
    local owned = dex.owned or {}
    local mark = mod.options:get("owned") ~= false
    local items = {}
    for _, row in ipairs(page.rows) do
      local odds = percent(row.weight, page.total)
      items[#items + 1] = {
        label = speciesName(row.species),
        right = odds and (odds .. "/100") or nil,
        sub = levelText(row),
        ball = (mark and owned[row.species]) and true or nil,
      }
    end
    return items
  end

  local ROWS = 5

  local function open(game)
    local overworld = mod.world and mod.world:overworld()
    local map = overworld and overworld.map
    local mapId = map and map.id
    if not mapId then return end
    -- the live map's own def where there is one; the Gen 2 world keeps its map
    -- table separately and hands the loaded map only its id
    local mapDef = map.def
    if type(mapDef) ~= "table" and type(overworld.maps) == "table" then
      mapDef = overworld.maps[mapId]
    end
    local tod = timeOfDay(overworld)
    local pages = mod.exports.report(mapId, tod, mapDef)
    if not pages then return end
    local place = placeName(game, mapId, mapDef)

    -- open on the page the clock is on, so the first thing shown is the one
    -- that answers "what will I run into if I step into that grass now"
    local now = todKey(tod)
    local index = 1
    for i, page in ipairs(pages) do
      if page.tod == now then
        index = i
        break
      end
    end

    local list
    local function applyPage()
      local page = pages[index]
      list.title = page.title .. ((page.tod == now) and " NOW" or "")
      list.items = itemsFor(game, page)
      list.index = 1
      list.scroll = 0
    end

    list = mod.ui.ListMenu.new(game, "", {}, { kind = "radar", rows = ROWS,
      -- the START menu pops itself when a row is selected, so B has to put it
      -- back the way every vanilla submenu does
      onCancel = function() mod.ui.push(game, "StartMenu") end,
    })
    applyPage()

    -- Paging is a wrapper rather than the widget's own pocket-switch option:
    -- only one of the two engines has that option, and intercepting the press
    -- before the base update is the same behaviour on both.
    local baseUpdate = list.update
    list.update = function(self, dt)
      if #pages > 1 then
        local input = self.game.input
        local delta = (input:wasPressed("right") and 1)
          or (input:wasPressed("left") and -1)
        if delta then
          index = ((index - 1 + delta) % #pages) + 1
          applyPage()
          return
        end
      end
      return baseUpdate(self, dt)
    end

    -- ListMenu draws one line per row; the level range rides underneath it in
    -- the row's second half, the way the Gen 2 pack hangs a quantity there.
    local baseDraw = list.draw
    list.draw = function(self)
      baseDraw(self)
      local Font = mod.ui.Font
      love.graphics.setColor(0, 0, 0, 1)
      for row = 1, self.rows do
        local item = self.items[self.scroll + row]
        if not item then break end
        if item.sub then Font.draw(item.sub, 24, 8 + row * 16 + 8) end
      end
      Font.draw(place, 8, 120)
      local page = pages[index]
      if page.note ~= "" then Font.draw(page.note, 8, 136) end
      if #pages > 1 then
        local tag = index .. "/" .. #pages
        Font.draw(tag, 152 - Font.width(tag), 136)
        -- the GB font has no side arrows, so the page markers are drawn the
        -- way the pack draws its pocket ones
        love.graphics.polygon("fill", 138, 8, 144, 4, 144, 12)
        love.graphics.polygon("fill", 158, 8, 152, 4, 152, 12)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end

    game.stack:push(list)
  end

  -- ------- the walking overlay
  --
  -- render.hud draws over the finished frame EVERY frame, whatever is on
  -- screen -- battle, title, save prompt -- so the overlay has to decide for
  -- itself when it is welcome.
  --
  -- The world is showing when nothing OPAQUE is stacked on top of it.
  -- DRAMATIC_SHAPE (battle-exit fade, loading veil) pushes transparent
  -- states over the overworld and never pops them on some paths; treating
  -- "anything on the stack" as a cover hid the overlay for the rest of the
  -- session, even after voxel mode was switched off.
  local function worldActive(game, ow)
    local stack = game and game.stack
    if not (stack and stack.top) then return false end
    local top = stack:top()
    if top == nil or top == ow then return true end
    if top.isOverworld then return true end
    -- explicit transparent lid: the world is still the picture
    if top.isOpaque == false then return true end
    return false
  end

  -- Deliberately NOT the engine's own `acceptsMenuInput`: that goes false
  -- between tiles while the player is mid-step, so the box would strobe on
  -- every stride. Gold's World:busy covers textboxes and scripted movement
  -- that never become stack states; a busy() left on the Gen 1 module by
  -- another mod is ignored, because that is how DRAMATIC_SHAPE kept this
  -- overlay dead after voxel was turned off.
  local function worldBusy(ow)
    if ow.transitioning or ow.flyAnim or ow.teleportOut then return true end
    if ow.textbox or ow.mapSetup or ow.choicebox or ow.fishing
        or ow.fieldMove or ow.headbutt then
      return true
    end
    local runner = ow.runner
    if type(runner) == "table" and type(runner.isRunning) == "function" then
      local ok, value = pcall(runner.isRunning, runner)
      if ok and value then return true end
    end
    if type(ow.busy) == "function"
        and (ow.vm or ow.stepBody or ow.moveState ~= nil) then
      local ok, value = pcall(ow.busy, ow)
      if ok and value then return true end
    end
    return false
  end

  -- Gen 1 and the per-map Gen 2 port keep a boolean on the player; Gold keeps
  -- one state string for walking / biking / surfing (FieldMoves.PLAYER_*).
  local function isSurfing(ow)
    local player = ow.player
    if player and player.surfing then return true end
    local state = ow.playerState
    return state == "surf" or state == "surf_pika"
  end

  -- What the tile under the player can produce right now: the water table when
  -- surfing, otherwise the grass table the clock is on. A map with only the
  -- other one gets no overlay rather than a misleading one.
  local function livePage(pages, now, wet)
    local fallback
    for _, page in ipairs(pages or {}) do
      if wet then
        if page.kind == "water" then return page end
      elseif page.kind == "grass" then
        if page.tod == now then return page end
        if page.tod == nil then fallback = fallback or page end
      end
    end
    return fallback
  end

  -- Rebuilt only when the answer can have changed. Walking a route re-enters
  -- this every frame, and re-reading the registries at 60Hz to draw four
  -- unchanged names would be the one way a read-only tool costs a frame.
  local overlay = { key = nil, page = nil }

  local function overlayPage(game, ow)
    local mapId = ow.map and ow.map.id
    if not mapId then return nil end
    local now = todKey(timeOfDay(ow))
    local wet = isSurfing(ow)
    local key = tostring(mapId) .. "|" .. now .. "|" .. tostring(wet)
    if overlay.key ~= key then
      local mapDef = ow.map.def
      if type(mapDef) ~= "table" and type(ow.maps) == "table" then
        mapDef = ow.maps[mapId]
      end
      overlay.key = key
      overlay.page = livePage(mod.exports.report(mapId, now, mapDef), now, wet)
    end
    return overlay.page
  end

  local OVERLAY_MAX_TILES = 20

  -- Font.drawBox is the engine's bordered panel, but it forces its interior
  -- fill to full opacity -- reasonably, since every vanilla box is meant to
  -- hide what is under it.  This is that box redrawn with the fill's alpha left
  -- to the caller: the same six border glyphs (Font.BORDER, charmap $79-$7E)
  -- around a rectangle you can see through.
  --
  -- The glyph pages are black on transparent, so tinting them cannot change
  -- their colour, only their alpha -- which is exactly the one thing being
  -- changed here.  White is passed anyway, because that is what every vanilla
  -- call site sets and a TTF fallback font does take the colour.
  local function drawPanel(Font, tx, ty, tw, th, alpha)
    local B = Font.BORDER
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
    Font.drawCode(B.tl, tx * 8, ty * 8)
    Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
    Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
    Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
    for i = 1, tw - 2 do
      Font.drawCode(B.h, (tx + i) * 8, ty * 8)
      Font.drawCode(B.h, (tx + i) * 8, (ty + th - 1) * 8)
    end
    for j = 1, th - 2 do
      Font.drawCode(B.v, tx * 8, (ty + j) * 8)
      Font.drawCode(B.v, (tx + tw - 1) * 8, (ty + j) * 8)
    end
  end

  local function liveWorld(game)
    local ow = mod.world and mod.world:overworld()
    if ow and ow.map then return ow end
    ow = game and (game.world or game.overworld)
    if ow and ow.map then return ow end
    return nil
  end

  local function asViewport(viewport)
    if type(viewport) == "table" then return viewport end
    local w, h = 160, 144
    if love.graphics and love.graphics.getDimensions then
      local ok, dw, dh = pcall(love.graphics.getDimensions)
      if ok and dw and dh then w, h = dw, dh end
    end
    return {
      width = w, height = h, gameX = 0, gameY = 0,
      gameWidth = w, gameHeight = h, scale = 1,
    }
  end

  local function drawOverlay(game, viewport)
    if mod.options:get("overlay") == false then return end
    local ow = liveWorld(game)
    if not ow then return end
    if not worldActive(game, ow) then return end
    if worldBusy(ow) then return end

    local page = overlayPage(game, ow)
    if not (page and page.rows and #page.rows > 0) then return end

    local Font = mod.ui.Font
    local showOdds = mod.options:get("overlayOdds") == true
    local limit = tonumber(mod.options:get("overlayRows")) or 3
    if limit < 1 then limit = 1 end
    if limit > #page.rows then limit = #page.rows end

    -- The cap is what keeps this a corner ornament. Left to grow, a
    -- ten-letter name plus its odds is thirteen of the screen's twenty
    -- columns, which stops reading as a corner and starts reading as a panel
    -- someone left open.
    local maxTiles = tonumber(mod.options:get("overlayWidth")) or 10
    if maxTiles < 5 then maxTiles = 5 end
    if maxTiles > OVERLAY_MAX_TILES then maxTiles = OVERLAY_MAX_TILES end

    local lines, oddsWidth = {}, 0
    for i = 1, limit do
      local row = page.rows[i]
      local odds = showOdds and percent(row.weight, page.total) or nil
      odds = odds and tostring(odds) or nil
      lines[i] = { name = speciesName(row.species), odds = odds }
      if odds then oddsWidth = math.max(oddsWidth, Font.width(odds)) end
    end
    if #lines == 0 then return end

    -- two columns go to the border, and the odds keep a gap of one glyph
    local budget = (maxTiles - 2) * 8
    local nameBudget = budget - ((oddsWidth > 0) and (oddsWidth + 8) or 0)
    if nameBudget < 8 then nameBudget = 8 end

    -- the box still grows to fit what it is holding; the cap is only a ceiling,
    -- so a route of PIDGEYs stays narrower than one of BELLSPROUTs
    local widest = 0
    for _, line in ipairs(lines) do
      widest = math.max(widest, math.min(Font.width(line.name), nameBudget))
    end
    local interior = widest + ((oddsWidth > 0) and (8 + oddsWidth) or 0)
    local tw = math.ceil(interior / 8) + 2
    if tw > maxTiles then tw = maxTiles end
    local tx = 20 - tw

    -- Scale from the playfield RECTANGLE, never from viewport.scale: both ports
    -- fill that field with fitScale() (framebuffer pixels per GB pixel), while
    -- gameWidth/gameHeight are LOVE window units. They agree only at DPI 1.
    local playW = tonumber(viewport.gameWidth) or 0
    local playH = tonumber(viewport.gameHeight) or 0
    local scaleX = playW / 160
    local scaleY = playH / 144
    if scaleX <= 0 then scaleX = tonumber(viewport.scale) or 1 end
    if scaleY <= 0 then scaleY = scaleX end

    -- Pin the 160x144 layout's top-right to the WINDOW's top-right whenever
    -- the playfield is letterboxed. DRAMATIC_SHAPE's voxel pass (and Gold's
    -- edge-to-edge overworld) already fill the window; the letterbox is only
    -- where the engine still thinks a Game Boy screen is. Anchoring a corner
    -- ornament to that letterbox puts it in the middle of the 3D view, which
    -- reads as "the overlay is gone".
    local originX = tonumber(viewport.gameX) or 0
    local originY = tonumber(viewport.gameY) or 0
    local winW = tonumber(viewport.width) or 0
    local winH = tonumber(viewport.height) or 0
    if winW > playW + 0.5 then originX = winW - 160 * scaleX end
    if winH > playH + 0.5 then originY = 0 end

    love.graphics.push("all")
    -- origin() because this hook can inherit a leftover transform; the 3D
    -- resets because LÖVE's push("all") does not cover depth/cull/stencil on
    -- every runtime, and a voxel pipeline that leaked any of them would make
    -- a 2D box fail the depth test and vanish.
    if love.graphics.origin then pcall(love.graphics.origin) end
    if love.graphics.setShader then love.graphics.setShader() end
    if love.graphics.setColorMask then
      pcall(love.graphics.setColorMask, true, true, true, true)
    end
    if love.graphics.setDepthMode then pcall(love.graphics.setDepthMode) end
    if love.graphics.setMeshCullMode then
      pcall(love.graphics.setMeshCullMode, "none")
    end
    if love.graphics.setStencilTest then pcall(love.graphics.setStencilTest) end
    love.graphics.translate(originX, originY)
    love.graphics.scale(scaleX, scaleY)
    -- push("all") saves the blend mode but does not reset it, and this hook
    -- runs straight off the end of the composite pass -- which is exactly the
    -- kind of place a premultiplied mode is left set.  A translucent panel is
    -- the one thing that would silently come out wrong.
    love.graphics.setBlendMode("alpha")

    local alpha = (tonumber(mod.options:get("overlayAlpha")) or 70) / 100
    if alpha < 0 then alpha = 0 end
    if alpha > 1 then alpha = 1 end
    drawPanel(Font, tx, 0, tw, #lines + 2, alpha)

    -- the names stay solid whatever the panel does: seeing through the box is
    -- for keeping an eye on the map, not for making the list harder to read.
    -- At alpha 0 that leaves bare text over the world, which is a legitimate
    -- setting rather than a broken one.
    love.graphics.setColor(0, 0, 0, 1)
    -- Clipping walks GLYPHS rather than bytes: NIDORAN♂ and NIDORAN♀ carry a
    -- multi-byte charmap entry, so cutting the string would hand Font.encode
    -- half a character.
    local function drawClipped(text, x, y, limitPx)
      if Font.width(text) <= limitPx then
        Font.draw(text, x, y)
        return
      end
      local pen = x
      for _, code in ipairs(Font.encode(text)) do
        local advance = Font.advanceOf(code)
        if pen + advance > x + limitPx then break end
        Font.drawCode(code, pen, y)
        pen = pen + advance
      end
    end

    local left, right = (tx + 1) * 8, (tx + tw - 1) * 8
    for i, line in ipairs(lines) do
      local y = i * 8
      drawClipped(line.name, left, y, nameBudget)
      if line.odds then
        Font.draw(line.odds, right - Font.width(line.odds), y)
      end
    end

    love.graphics.pop()
  end

  -- After nextFn (pcall'd so a graphics mod that throws in this layer cannot
  -- swallow the list), and at a high wrap priority, so DRAMATIC_SHAPE's HUD
  -- chrome cannot bury it. 1000 beats the default, which is the wrapping
  -- mod's own manifest priority -- 100 for this one, and 100 for that one.
  --
  -- DRAMATIC_SHAPE also wraps Renderer:endFrame and can hand back no viewport
  -- at all; asViewport synthesises a full-window one rather than going dark.
  mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
    pcall(nextFn, game, viewport)
    pcall(drawOverlay, game, asViewport(viewport))
  end, 1000)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" then return out end
    if mod.options:get("enabled") == false then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = "RADAR",
      onSelect = function() open(game) end,
    })
  end)
end
