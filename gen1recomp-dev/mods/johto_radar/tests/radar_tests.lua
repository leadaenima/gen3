-- The radar's arithmetic, driven through mod.exports.report against synthetic
-- tables in all three dataset shapes it has to read.
--
-- Everything that can be quietly wrong here is a number.  A slot share is a
-- DIFFERENCE between cumulative thresholds, not a threshold.  The two Gen 2
-- fishing walks disagree about the comparison -- one is `roll <= chance` and
-- starts at -1, the other is `roll < chance` and starts at 0 -- so the same
-- rows mean different odds depending on which dataset they came out of.  And
-- the totals differ: 256 for the per-map shapes, 100 for the kind-keyed one,
-- and the group size for a Gen 1 rod.  All of that looks plausible on screen.
--
-- Run: luajit mods/johto_radar/tests/radar_tests.lua   (from the repo root)

local failures, checks = 0, 0

local function check(condition, label)
  checks = checks + 1
  if not condition then
    failures = failures + 1
    print("FAIL " .. label)
  end
  return condition
end

local function eq(actual, expected, label)
  return check(actual == expected,
    label .. " (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
end

-- ------- the stub mod api

local function registry(records)
  return { get = function(_, id) return records[id] end }
end

local function newMod(opts)
  local mod = {
    exports = {},
    options = {
      define = function() end,
      get = function(_, key) return (opts.options or {})[key] end,
    },
    hooks = { wrap = function() end },
    ui = {},
    content = {
      pokemon = registry(opts.pokemon or {}),
      encounters = registry(opts.encounters or {}),
      maps = registry(opts.maps or {}),
    },
    game = {
      data = {
        field = opts.field or {},
        constants = opts.constants or {},
      },
      save = { pokedex = {} },
    },
  }
  local chunk = assert(loadfile("mods/johto_radar/main.lua"))
  chunk()(mod)
  return mod
end

local function pageByTitle(pages, title)
  for _, page in ipairs(pages) do
    if page.title == title then return page end
  end
  return nil
end

local function slots(list)
  local out = {}
  for _, entry in ipairs(list) do
    out[#out + 1] = { species = entry[1], level = entry[2] }
  end
  return out
end

local function totalWeight(rows)
  local sum = 0
  for _, row in ipairs(rows) do sum = sum + row.weight end
  return sum
end

local GEN2_GRASS_BUCKETS = { 77, 154, 205, 230, 243, 253, 256 }
local KANTO_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

-- ================= per-map, Gen 2: three tables on one map

do
  local day = {
    rate = 24, buckets = GEN2_GRASS_BUCKETS,
    slots = slots({ { "PIDGEY", 2 }, { "SENTRET", 3 }, { "PIDGEY", 4 },
                    { "HOOTHOOT", 5 }, { "RATTATA", 6 }, { "RATTATA", 7 },
                    { "SPINARAK", 8 } }),
  }
  day.byTime = {
    morn = { rate = 24, buckets = GEN2_GRASS_BUCKETS, slots = day.slots },
    nite = {
      rate = 0, buckets = GEN2_GRASS_BUCKETS,
      slots = slots({ { "HOOTHOOT", 2 }, { "HOOTHOOT", 3 }, { "HOOTHOOT", 4 },
                      { "RATTATA", 5 }, { "RATTATA", 6 }, { "SPINARAK", 7 },
                      { "SPINARAK", 8 } }),
    },
  }

  local mod = newMod({ encounters = { ROUTE_29 = { grass = day } } })
  local pages = mod.exports.report("ROUTE_29", "DAY")

  eq(#pages, 3, "one page per period")
  eq(pages[1].title, "GRASS MORN", "morning comes first")
  eq(pages[2].tod, "DAY", "the day page is tagged DAY")
  eq(pages[3].tod, "NITE", "the night page is tagged NITE")

  local page = pageByTitle(pages, "GRASS DAY")
  local rows = page.rows
  eq(page.total, 256, "a per-map table is scored out of 256")
  eq(#rows, 5, "seven slots collapse to five species")
  eq(rows[1].species, "PIDGEY", "the heaviest species sorts first")
  -- slots 1 and 3: (77-0) + (205-154)
  eq(rows[1].weight, 128, "PIDGEY sums its two slots")
  eq(rows[1].min, 2, "PIDGEY keeps its lowest level")
  eq(rows[1].max, 4, "PIDGEY keeps its highest level")
  -- slots 5 and 6: (243-230) + (253-243), which lands BELOW the single
  -- 25-weight slot 4 -- two common slots do not automatically outrank one
  eq(rows[4].species, "RATTATA", "RATTATA sorts under HOOTHOOT")
  eq(rows[4].weight, 23, "RATTATA sums its two slots")
  eq(rows[3].species, "HOOTHOOT", "one heavier slot beats two lighter ones")
  eq(rows[5].weight, 3, "the last slot is the rarest")
  eq(totalWeight(rows), 256, "the shares add up to the whole roll")
  eq(page.note, "STEP 24/256", "the step rate is reported raw")

  local night = pageByTitle(pages, "GRASS NITE")
  eq(#night.rows, 0, "a rate of zero lists nothing")
  eq(night.note, "NEVER HERE", "and says why")
end

-- surf rides its own three-slot bucket table
do
  local mod = newMod({
    encounters = {
      ROUTE_32 = {
        water = {
          rate = 2, buckets = { 154, 230, 256 },
          slots = slots({ { "TENTACOOL", 15 }, { "TENTACOOL", 20 },
                          { "QUAGSIRE", 20 } }),
        },
      },
    },
  })
  local pages = mod.exports.report("ROUTE_32", "DAY")
  eq(#pages, 1, "water alone is one page")
  eq(pages[1].title, "SURF", "titled SURF")
  eq(pages[1].rows[1].species, "TENTACOOL", "TENTACOOL dominates the water")
  eq(pages[1].rows[1].weight, 230, "its two slots are 154 + 76")
  eq(pages[1].rows[1].min, 15, "level range spans both slots")
  eq(pages[1].rows[1].max, 20, "level range spans both slots")
  eq(pages[1].rows[2].weight, 26, "QUAGSIRE takes the last 26")
end

-- rods under field.fishGroups: inclusive walk, TimeFishGroups by index
do
  local field = {
    fishGroups = {
      [5] = {
        chance = 64,
        rods = {
          old = { { chance = 127, species = "MAGIKARP", level = 10 },
                  { chance = 255, species = "TENTACOOL", level = 10 } },
          super = { { chance = 63, timeGroup = 3 },
                    { chance = 255, species = "SEAKING", level = 40 } },
        },
      },
    },
    timeFishGroups = {
      [3] = { day = { species = "GOLDEEN", level = 20 },
              nite = { species = "REMORAID", level = 20 } },
    },
  }

  local mod = newMod({
    encounters = { OLIVINE_CITY = {} },
    maps = { OLIVINE_CITY = { fishGroup = 5 } },
    field = field,
  })
  local day = mod.exports.report("OLIVINE_CITY", "DAY")
  eq(#day, 2, "only the rods the group actually carries get a page")

  local old = pageByTitle(day, "OLD ROD")
  eq(old.note, "BITE 64/256", "the group's bite chance is the page note")
  eq(old.total, 256, "the rod list covers the whole byte")
  eq(old.rows[1].species, "MAGIKARP", "the first row owns 0..127")
  eq(old.rows[1].weight, 128, "which is 128 of the 256 rolls")
  eq(old.rows[2].weight, 128, "and the last row takes the rest")

  local super = pageByTitle(day, "SUPER ROD")
  eq(super.rows[1].species, "SEAKING", "the heavier row sorts first")
  eq(super.rows[2].species, "GOLDEEN", "a timed row resolves to its day half")
  eq(super.rows[2].weight, 64, "the timed row owns 0..63")

  local night = pageByTitle(mod.exports.report("OLIVINE_CITY", "NITE"),
                            "SUPER ROD")
  eq(night.rows[2].species, "REMORAID", "and to its nite half after dark")
end

-- ================= per-map, Gen 1: ten slots off the constants table

do
  local mod = newMod({
    constants = { encounterBuckets = KANTO_BUCKETS },
    field = {
      fishing = {
        OLD_ROD = { always = { species = "MAGIKARP", level = 5 } },
        GOOD_ROD = { pool = slots({ { "GOLDEEN", 10 }, { "POLIWAG", 10 } }) },
        SUPER_ROD = { perMap = "superRod" },
      },
      superRod = {
        ROUTE_12 = slots({ { "SEAKING", 23 }, { "KINGLER", 38 },
                           { "SEADRA", 23 } }),
      },
    },
    encounters = {
      ROUTE_1 = {
        grass = { rate = 25, slots = slots({
          { "PIDGEY", 3 }, { "RATTATA", 3 }, { "RATTATA", 4 }, { "PIDGEY", 5 },
          { "PIDGEY", 4 }, { "RATTATA", 2 }, { "RATTATA", 5 }, { "PIDGEY", 2 },
          { "PIDGEY", 6 }, { "PIDGEY", 7 } }) },
      },
      ROUTE_12 = {
        grass = { rate = 0, slots = {} },
        water = { rate = 20, slots = slots({
          { "TENTACOOL", 15 }, { "TENTACOOL", 15 }, { "TENTACOOL", 15 },
          { "TENTACOOL", 15 }, { "TENTACOOL", 15 }, { "TENTACOOL", 15 },
          { "TENTACOOL", 15 }, { "TENTACOOL", 15 }, { "TENTACOOL", 15 },
          { "TENTACOOL", 15 } }) },
      },
    },
  })

  local pages = mod.exports.report("ROUTE_1", "DAY")
  eq(#pages, 1, "Gen 1 has one grass page and, inland, no rods")
  eq(pages[1].title, "GRASS", "titled plainly, with no period")
  eq(pages[1].tod, nil, "and tagged with no period")
  eq(pages[1].total, 256, "the Kanto table is scored out of 256")
  -- PIDGEY holds slots 1, 4, 5, 8, 9, 10: 51+25+25+13+11+3
  eq(pages[1].rows[1].species, "PIDGEY", "PIDGEY owns six of the ten slots")
  eq(pages[1].rows[1].weight, 128, "which is exactly half the roll")
  eq(pages[1].rows[1].min, 2, "its levels span the slots it holds")
  eq(pages[1].rows[1].max, 7, "its levels span the slots it holds")
  eq(pages[1].rows[2].weight, 128, "RATTATA takes the other half")
  eq(totalWeight(pages[1].rows), 256, "ten slots still add up to the roll")

  local water = mod.exports.report("ROUTE_12", "DAY")
  eq(pageByTitle(water, "GRASS"), nil, "an empty grass table is no page")
  eq(pageByTitle(water, "SURF").total, 256, "Gen 1 water uses the same table")

  -- the Old and Good Rods are global rules, so they appear only where there
  -- is water; the Super Rod's own per-map group is its own proof
  eq(pageByTitle(pages, "OLD ROD"), nil, "no rods on a landlocked route")
  local old = pageByTitle(water, "OLD ROD")
  eq(old.note, "ALWAYS BITES", "the Old Rod never misses")
  eq(old.rows[1].species, "MAGIKARP", "and only ever hooks one thing")
  eq(old.total, 1, "so its share is the whole of it")

  local good = pageByTitle(water, "GOOD ROD")
  eq(good.note, "BITE 2/6", "a pair bites two times in six")
  eq(good.total, 2, "and picks uniformly between them")

  local super = pageByTitle(water, "SUPER ROD")
  eq(super.note, "BITE 3/7", "a three-mon group bites three in seven")
  eq(#super.rows, 3, "all three are listed")
  eq(super.rows[1].weight, 1, "uniformly")
end

-- ================= kind-keyed Gen 2: tables per kind, scored out of 100

do
  local sevenDay = slots({ { "PIDGEY", 2 }, { "PIDGEY", 3 }, { "SENTRET", 4 },
                           { "SENTRET", 5 }, { "HOOTHOOT", 6 },
                           { "HOOTHOOT", 7 }, { "RATTATA", 8 } })
  local sevenNite = slots({ { "HOOTHOOT", 2 }, { "HOOTHOOT", 3 },
                            { "HOOTHOOT", 4 }, { "RATTATA", 5 },
                            { "RATTATA", 6 }, { "SPINARAK", 7 },
                            { "SPINARAK", 8 } })

  local mod = newMod({
    encounters = {
      grass = {
        ROUTE_29 = {
          rates = { MORN = 4, DAY = 4, NITE = 4 },
          slots = { MORN = sevenDay, DAY = sevenDay, NITE = sevenNite },
        },
      },
      water = {
        ROUTE_32 = { rate = 2,
                     slots = slots({ { "TENTACOOL", 15 }, { "QUAGSIRE", 20 },
                                     { "TENTACRUEL", 25 } }) },
      },
      fishGroups = {
        FISHGROUP_POND = {
          chance = 64,
          old = { { chance = 128, species = "MAGIKARP", level = 10 },
                  { chance = 256, species = "POLIWAG", level = 10 } },
          -- the inline day/nite pair, and the indexed one, in one list
          super = { { chance = 64, day = { species = "GOLDEEN", level = 20 },
                                   nite = { species = "REMORAID", level = 20 } },
                    { chance = 128, timeGroup = 7, species = 0, level = 0 },
                    { chance = 256, species = "SEAKING", level = 40 } },
        },
      },
      timeFishGroups = {
        [7] = { day = { species = "QWILFISH", level = 20 },
                nite = { species = "GYARADOS", level = 20 } },
      },
    },
    maps = { ROUTE_29 = { fishGroup = "FISHGROUP_POND" } },
  })

  local pages = mod.exports.report("ROUTE_29", "MORN")
  eq(#pages, 5, "three grass periods plus two rods")
  eq(pages[1].title, "GRASS MORN", "the periods come out in clock order")
  eq(pages[1].tod, "MORN", "tagged with the short period name")
  eq(pages[1].total, 100, "a kind-keyed table is scored out of 100")
  eq(pages[1].note, "STEP 4/256", "but the step rate is still out of 256")
  eq(pages[1].rows[1].species, "PIDGEY", "30 + 30 puts PIDGEY on top")
  eq(pages[1].rows[1].weight, 60, "two slots of thirty")
  eq(pages[1].rows[4].weight, 1, "and the seventh slot is worth one")
  eq(totalWeight(pages[1].rows), 100, "the shares add up to a hundred")

  local nite = pageByTitle(pages, "GRASS NITE")
  eq(nite.rows[1].species, "HOOTHOOT", "the night list is a different table")
  eq(nite.rows[1].weight, 80, "30 + 30 + 20")

  -- MORN was asked for, so that page is the one marked live
  eq(pageByTitle(pages, "GRASS DAY").tod, "DAY", "the day page is still there")

  local super = pageByTitle(pages, "SUPER ROD")
  eq(super.total, 256, "a rod list is out of 256 in either shape")
  eq(super.note, "BITE 64/256", "with the group's own bite chance")
  -- exclusive walk from 0: rows own 0..63, 64..127 and 128..255
  eq(super.rows[1].species, "SEAKING", "the widest row sorts first")
  eq(super.rows[1].weight, 128, "which owns 128..255")
  eq(super.rows[2].species, "GOLDEEN", "an inline day pair resolves")
  eq(super.rows[2].weight, 64, "and owns the first 64")
  eq(super.rows[3].species, "QWILFISH", "an indexed day pair resolves too")
  eq(totalWeight(super.rows), 256, "and the rod list covers the byte")

  -- both timed rows weigh 64 after dark, so they fall to the name tiebreak
  local dark = pageByTitle(mod.exports.report("ROUTE_29", "DARK"), "SUPER ROD")
  eq(dark.rows[2].species, "GYARADOS", "DARK reads as night for the indexed pair")
  eq(dark.rows[3].species, "REMORAID", "and for the inline one")

  local water = mod.exports.report("ROUTE_32", "DAY")
  eq(pageByTitle(water, "SURF").total, 100, "kind-keyed water is out of 100")
  eq(pageByTitle(water, "SURF").rows[1].weight, 60, "60 / 30 / 10")
end

-- ================= nothing at all

do
  local mod = newMod({ encounters = { PLAYERS_HOUSE_1F = {} } })
  local empty = mod.exports.report("PLAYERS_HOUSE_1F", "DAY")
  eq(#empty, 1, "an indoor map still opens")
  eq(empty[1].title, "NO WILD DATA", "with an honest title")
  eq(#empty[1].rows, 0, "and nothing listed")

  eq(mod.exports.report("NOT_A_MAP", "DAY")[1].title, "NO WILD DATA",
    "an unknown map does not crash")
end

print(("radar: %d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
