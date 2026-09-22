-- AI assistants: see AGENTS.md before editing this mod.
-- =====================================================================
-- WEATHER FX -- CONFIGURATION
-- =====================================================================
--
-- Edit this file and restart the game (or press F5 in developer mode).
-- Everything here is optional: delete a key, or the whole file, and the
-- built-in default is used instead.  A syntax error here costs you the
-- config, not the mod -- the file is loaded in a sandbox, and a failure
-- is logged and then ignored.
--
-- It is a Lua table because that is what the project already uses for
-- data (`options.lua`, `save.lua`, `data/*.lua`).  Trailing commas are
-- fine, comments are fine, and the values are checked on load: an
-- unknown weather id or an out-of-range number is reported by name in
-- the mod manager's error feed and replaced with the default, rather
-- than silently doing nothing.
--
-- PRECEDENCE, highest first:
--
--   1. force            -- this file wins over everything
--   2. locations        -- per-map, wins over the menu and AUTO
--   3. the OPTIONS row  -- OFF / AUTO / a pinned weather
--   4. the AUTO clock
--
-- Weather ids (use these exact strings):
--
--   CLEAR       SUNNY       HARSH_SUN
--   RAIN_LIGHT  RAIN_HEAVY  HEAVY_RAIN  STORM
--   SNOW_LIGHT  BLIZZARD    HAIL
--   SANDSTORM   STRONG_WINDS
--   MIST        FOG
--
-- =====================================================================

return {

  -- -------------------------------------------------------------------
  -- FORCE WEATHER
  -- -------------------------------------------------------------------
  -- Pin one weather everywhere, overriding the OPTIONS row and AUTO.
  -- nil (the default) means "don't force anything".
  --
  --   force = "RAIN_HEAVY",     -- always a downpour
  --   force = "CLEAR",          -- weather system on, sky always clear
  --
  force = nil,

  -- -------------------------------------------------------------------
  -- LOCATION OVERRIDES
  -- -------------------------------------------------------------------
  -- Per-map weather, by the engine's map id (upper snake case, exactly as
  -- the game names them: LAVENDER_TOWN, ROUTE_23, MT_MOON_1F, ...).
  --
  -- Two forms:
  --
  --   ["MAP_ID"] = "FOG"                        always this weather here
  --   ["MAP_ID"] = { weather = "FOG",           ...with detail
  --                  chance = 0.75,             how often (0..1, default 1)
  --                  indoors = false }          apply inside too?
  --
  -- `chance` is rolled once each time AUTO picks, so 0.75 means "fog
  -- three visits in four" rather than a flicker.  A hard override
  -- (chance 1) also freezes the AUTO clock for as long as you are on
  -- that map, and it resumes where it left off when you leave.
  --
  -- The examples below are ON by default because they are the ones the
  -- geography argues for.  Delete any you don't want.
  locations = {

    -- The tower town is famous for it.
    LAVENDER_TOWN     = "FOG",
    POKEMON_TOWER_1F  = { weather = "MIST", indoors = true },

    -- The climb to the League: thin air, hard weather.
    ROUTE_23          = { weather = "HAIL", chance = 0.6 },
    INDIGO_PLATEAU    = { weather = "SNOW_LIGHT", chance = 0.7 },

    -- The sea routes south of Pallet.
    ROUTE_19          = { weather = "MIST", chance = 0.5 },
    ROUTE_20          = { weather = "MIST", chance = 0.5 },
    ROUTE_21          = { weather = "RAIN_LIGHT", chance = 0.4 },

    -- The damp under the canopy.
    VIRIDIAN_FOREST   = { weather = "MIST", chance = 0.55 },

    -- Volcanic island: dry heat.
    CINNABAR_ISLAND   = { weather = "SUNNY", chance = 0.5 },

    -- Grit blowing through the caves.  `indoors = true` is what makes
    -- these work at all: a cave counts as indoors, and indoors nothing
    -- falls unless an override says this place has weather inside.
    MT_MOON_1F        = { weather = "SANDSTORM", chance = 0.45, indoors = true },
    MT_MOON_B1F       = { weather = "SANDSTORM", chance = 0.45, indoors = true },
    MT_MOON_B2F       = { weather = "SANDSTORM", chance = 0.45, indoors = true },
    ROCK_TUNNEL_1F    = { weather = "SANDSTORM", chance = 0.5,  indoors = true },
    ROCK_TUNNEL_B1F   = { weather = "SANDSTORM", chance = 0.5,  indoors = true },
    DIGLETTS_CAVE     = { weather = "SANDSTORM", chance = 0.55, indoors = true },
    VICTORY_ROAD_1F   = { weather = "SANDSTORM", chance = 0.45, indoors = true },
    VICTORY_ROAD_2F   = { weather = "SANDSTORM", chance = 0.45, indoors = true },
    VICTORY_ROAD_3F   = { weather = "SANDSTORM", chance = 0.45, indoors = true },

    -- ROUTE_12       = { weather = "SANDSTORM", chance = 0.4 },
  },

  -- Region weighting for AUTO on every map with no explicit override
  -- above.  A multiplier per capability tag; anything unlisted is 1.
  -- This is the softer knob: `locations` decides, `bias` nudges.
  bias = {
    ROUTE_22        = { frozen = 2.0 },
    VERMILION_CITY  = { fog = 1.8 },
    ROUTE_12        = { fog = 1.8, wet = 1.2 },
    SEAFOAM_ISLANDS_1F = { frozen = 4.0, indoors = true },
  },

  -- -------------------------------------------------------------------
  -- PER-WEATHER TUNING
  -- -------------------------------------------------------------------
  -- Multipliers applied on top of a weather's own channel values.
  --
  --   density   particle count      (0..3, default 1)
  --   intensity tint / haze / fog   (0..3, default 1)
  --   speed     fall and drift      (0.25..3, default 1)
  --   duration  how long a spell lasts under AUTO (0.1..10, default 1)
  --
  -- The keys are weather ids; `ALL` applies to every weather and is
  -- multiplied with the specific one.
  -- -------------------------------------------------------------------
  -- INDOOR EXCEPTIONS
  -- -------------------------------------------------------------------
  -- Maps that should count as indoors even though their tileset says
  -- otherwise.  Caves already work without this -- Rock Tunnel, Mt Moon
  -- and Victory Road use the CAVERN tileset -- so this is only for a map
  -- laid out with outdoor tiles that should have no sky.
  --
  --   indoorMaps = { "SOME_MAP", "ANOTHER_MAP" },
  -- Force no outdoor weather (buildings/caves/ships). SS Anne uses outdoor-looking
  -- tiles on some floors; these ids guarantee weather pauses aboard and resumes on leave.
  indoorMaps = {
    "SSAnne1F", "SSAnne2F", "SSAnne3F", "SSAnneB1F",
    "SSAnneBow", "SSAnneKitchen", "SSAnneCaptainsRoom",
    "SSAnne1FRooms", "SSAnne2FRooms",
    "SSANNE1F", "SSANNE2F", "SSANNE3F", "SSANNEB1F",
    "SSANNEBOW", "SSANNEKITCHEN", "SSANNECAPTAINSROOM",
    "SSANNE1FROOMS", "SSANNE2FROOMS",
  },

  -- -------------------------------------------------------------------
  -- WHICH WEATHERS EXIST
  -- -------------------------------------------------------------------
  -- Switch any weather off entirely.  Checked before any weighting, so
  -- this is absolute rather than merely unlikely.  Anything not listed
  -- stays on.
  --
  --   weathers = { THUNDERSNOW = false, ASHFALL = false },
  --
  -- To make one RARER or COMMONER rather than removing it, use the
  -- `weight` multiplier in `tuning` below.  For how often snow, hail,
  -- sleet, sandstorms and ashfall appear away from the maps that suit
  -- them, the RARE WX row in the mod manager is the quicker dial.
  weathers = {},

  tuning = {
    -- `weight` multiplies how often AUTO picks this weather.
    ALL         = { density = 1.0, intensity = 1.0, speed = 1.0, duration = 1.0, weight = 1.0 },
    -- SNOW_LIGHT = { weight = 4.0 },     -- snow four times as often
    -- ASHFALL    = { weight = 0.0 },     -- same as weathers.ASHFALL = false
    -- STORM    = { density = 1.4, duration = 0.5 },
    -- FOG      = { intensity = 0.7 },
    -- BLIZZARD = { density = 0.6 },     -- if a blizzard is too busy
  },

  -- -------------------------------------------------------------------
  -- VISUAL EFFECT TOGGLES
  -- -------------------------------------------------------------------
  -- Every drawn layer, individually switchable.  These are cheaper than
  -- the quality tier: switching one off removes its code path entirely.
  visuals = {
    precipitation = true,   -- rain, snow, hail, sand, debris
    splashes      = true,   -- drops bursting where they land
    fog           = true,   -- the drifting noise banks
    veil          = true,   -- flat haze (whiteout, murk, dust)
    tint          = true,   -- the multiply grade (gloom, warmth)
    glare         = true,   -- additive sun bloom
    lightning     = true,   -- master lightning capability; menu LIGHTNING controls presentation
    battleWeather = true,   -- weather drawn over the battle screen
    textBoxClear  = true,   -- keep precipitation off an open text box
    puddles       = true,   -- wet ground that lingers after the rain stops
  },

  -- -------------------------------------------------------------------
  -- AUTO INTENSITY
  -- -------------------------------------------------------------------
  -- Only used when the INTENSITY row is set to AUTO.  Each family of
  -- effect -- rain, snow, grains, haze, lightning -- swells and eases on
  -- its own slow rhythm, so a downpour is not the same downpour for six
  -- minutes and a storm's strikes cluster and then go quiet.
  --
  --   min/max   the range the multiplier moves between
  --   seconds   stretches or compresses every rhythm at once; 2.0 is half
  --             as fast, 0.5 twice as fast
  --
  -- The grade channels (gloom, warmth, glare) deliberately do NOT breathe:
  -- a full-screen multiply that pulses reads as a fault, not as weather.
  autoIntensity = { min = 0.5, max = 1.4, seconds = 1.0 },

  -- -------------------------------------------------------------------
  -- NPC LIGHTNING GAG (3D ONLY)
  -- -------------------------------------------------------------------
  -- House rule: each individual 3D lightning bolt has a 10% chance to hit
  -- a visible non-player character. The NPC is only redrawn as a temporary
  -- black silhouette with white eyes; no NPC sprite/entity data is modified.
  npcLightning = { enabled = true, chance = 0.10, duration = 3.0, nearRadius = 192.0 },


  -- -------------------------------------------------------------------
  -- SPLASHES
  -- -------------------------------------------------------------------
  -- How far up the screen drops are allowed to land, 0..1.
  --
  -- This is a top-down game, so the whole screen is ground: rain landing
  -- only along the bottom edge is what a side-on game would do, and it
  -- reads as the rain falling behind the world rather than onto it.
  --
  --   1.0  drops land anywhere on screen (the default)
  --   0.4  only the lower part of the screen
  --   0.0  the bottom edge only, the pre-2.3 behaviour
  splashSpread = 1.0,

  -- -------------------------------------------------------------------
  -- BATTLE VIEW
  -- -------------------------------------------------------------------
  -- Where battle weather is drawn.
  --
  --   "canvas"  inside the engine's 160x144 battle canvas, through the
  --             battle.overlay hook.  Scales with the battle and passes
  --             through the palette handling, so it looks like part of
  --             the game -- but it only covers that classic 4:3 box.
  --   "screen"  across the whole window instead.  Correct when another
  --             mod draws a WIDER battle than 160x144, because then the
  --             canvas is a small box in the middle of a larger scene.
  --   "auto"    "screen" when StadiumBattleFX or either voxel diorama
  --             (DRAMATIC_SHAPE / DRAMALESS_SHAPE) is installed,
  --             "canvas" otherwise.  The default.
  battleView = "auto",

  -- -------------------------------------------------------------------
  -- BATTLE BACKDROPS
  -- -------------------------------------------------------------------
  -- Painted scenery behind and around the battle screen, chosen by the
  -- weather first and the map second: a blizzard puts you on the snow
  -- field wherever you are, a sandstorm on the desert one, and otherwise
  -- a cave is a cave and a route is tall grass.  Night variants follow
  -- this mod's own clock.
  --
  -- Art: CDRX73, DerxwnaKapsyla, http404error, Game Freak.
  --
  -- These draw in the LETTERBOX, around the battle screen -- not behind
  -- the Pokemon.  That is a limit of the engine, not a setting: there is
  -- no hook between the battle filling its field and drawing its sprites,
  -- and the two seams that look like they would work (battleBg = "world",
  -- render.compose) either leave the battle's own field opaque or demand
  -- the mod take over the entire window composite.  See lib/Backgrounds.lua.
  battleBackdrops = true,

  -- Art BEHIND the Pokemon, replacing the battle's white field.  Needs
  -- BATTLE ART set to BEHIND in the mod manager as well; this decides how
  -- careful to be about it.
  --
  --   "auto"  on.  The default.
  --   "on"    the same; kept so an explicit setting reads clearly.
  --   "mono"  skip it whenever the game is running in colour.  The SGB and
  --           GBC paths draw the field into a canvas that is then
  --           recoloured by zone, so a painted backdrop can come out
  --           tinted.  Use this if you dislike the result in colour.
  --   "off"   never; scenery stays in the bars.
  --
  -- This is THE ONLY part of the mod that patches engine internals
  -- (BattleState.draw).  Everything else is hooks and registries.  It
  -- degrades to "no backdrop" if the engine changes, not to a broken
  -- battle -- but it is the one piece that can break on an update.
  battleFieldArt = "auto",

  -- How much to darken the backdrop, 0..1, so it reads as a setting
  -- behind the fight rather than a brighter picture competing with it.
  battleBackdropDim = 0.25,

  -- -------------------------------------------------------------------
  -- THE LEGENDARY BIRDS
  -- -------------------------------------------------------------------
  -- A thunderstorm for Zapdos, ashfall for Moltres, hail for Articuno.
  -- Each has a small chance on any outdoor map, and while one is running
  -- the bird itself may turn up in the grass.
  --
  -- The sky really is an ordinary thunderstorm -- what makes it Zapdos's
  -- is that something is in it.  So nothing about the drawing, the battle
  -- effects or the audio changes; only the encounter does.
  --
  --   chance           per map arrival, that a bird stirs at all
  --   encounterChance  per wild encounter while one is roused
  --   level            the bird's level; the roll's own level would put a
  --                    level 3 Zapdos on Route 1
  --
  -- A rousing is spent once the bird appears, so one storm cannot produce
  -- two, and it ends when you leave the map -- the bird belongs to that
  -- sky rather than following you.
  legendary = { enabled = true, chance = 0.05, encounters = true,
                rateBoost = 1.05, -- +5% relative on bird/beast claim chance
                encounterChance = 0.15, level = 50 },

  -- -------------------------------------------------------------------
  -- THE PSYSTORM
  -- -------------------------------------------------------------------
  -- Violet cloud, hard wind and lightning, and it wears down anything that
  -- is not Psychic (1/16 max HP per turn in battle, the same fraction the
  -- sandstorm and hail use).
  --
  -- It never rolls on the AUTO clock and no front can drift it in.  It is
  -- summoned: by Mewtwo's cave, or by carrying Mew or Mewtwo at the front
  -- of the party.  Mewtwo's own chamber is ALWAYS storming -- a chance
  -- there would mean standing in front of him under a clear sky.
  --
  --   carrierChance  chance per map when Mew or Mewtwo leads the party
  --   scale          multiplies every chance; 0 disables without changing
  --                  the individual numbers
  psystorm = { enabled = true, carrierChance = 0.7, scale = 1.0 },

  -- -------------------------------------------------------------------
  -- WEATHER FRONTS
  -- -------------------------------------------------------------------
  -- Weather belongs to a PLACE rather than following you.  The world is
  -- divided into regions -- a town and the routes around it -- and each
  -- runs its own weather on its own clock.  Walk out of a blizzard and it
  -- keeps snowing behind you; come back and it is still there unless it
  -- has blown out.
  --
  -- Regions are bigger than a map on purpose: per-map weather would change
  -- the sky every twenty steps, and weather systems are bigger than a
  -- screen.
  --
  --   drift   how often a region inherits a neighbour's weather instead of
  --           rolling its own (0..1).  This is what makes fronts MOVE
  --           across the map rather than nineteen regions blinking
  --           independently.  0 gives independent regions.
  fronts = { enabled = true, drift = 0.5 },

  -- Lightweight world-space rain/cloud/fog band simulation. This is O(1)
  -- memory and does not increase particle ceilings; strength only changes
  -- how different nearby parts of one weather system can be.
  mesoscale = { enabled = true, strength = 1.0 },

  -- Natural post-rain primary rainbow. The 3D/FPV renderer places it on the
  -- antisolar sky only while recent rain moisture, low visible sun and a cloud
  -- break agree. It fades in/out instead of appearing as a screen overlay.
  rainbow = { enabled = true, memorySeconds = 120, fadeSeconds = 8 },

  -- Wind-to-player response. Uses the same WindEngine/WindFlow that moves the
  -- weather: headwinds can slow walking by at most 10%, tailwinds can help by
  -- at most 4%. Bike and Surf movement are deliberately unaffected.
  wind = { playerMovement = true, headwindSlow = 0.10,
           tailwindBoost = 0.04, minimumStrength = 0.10 },

  -- A WEATHER card on the Gen 2 Pokegear showing where the fronts are.
  -- Needs the `pokegear_cards` library; without it there is simply no card.
  pokegear = { enabled = true },

  -- -------------------------------------------------------------------
  -- WEATHER SOUND
  -- -------------------------------------------------------------------
  -- A looping bed under the rain, cross-faded when the weather turns, and
  -- thunder on the strike.
  --
  -- Rain-family weather has looping rain/storm beds. Wind is a separate
  -- layer driven by gust, so blizzards, sandstorms, ashfall and strong winds
  -- can still sound correct without borrowing a rain recording. Fog remains
  -- quiet. Indoors, exterior rain/wind/thunder are attenuated and low-pass
  -- filtered to sound as though they are heard through walls/windows.
  --
  --   volume       overall, on top of the WEATHER SFX row
  --   indoors      volume that reaches the player through walls/windows
  --   indoor*HighGain  high-frequency energy left by the indoor low-pass
  --                   (smaller = more muffled; 1.0 = no muffling)
  --   indoorTransition seconds to fade the acoustic filter at door/map changes
  --   battle       how much reaches the battle screen
  --   wind         a loop over any bed, at the strength of the gust the
  --                weather is blowing -- which is what a blizzard, a
  --                sandstorm and the strong winds actually sound like
  --   thunder      the one-shot fired with each visible strike
  audio = { enabled = true, volume = 1.0, indoors = 0.55, battle = 0.35,
            indoorRainHighGain = 0.55, indoorWindHighGain = 0.45,
            indoorThunderHighGain = 0.40, indoorTransition = 0.45,
            thunder = true, thunderGain = 0.8,
            wind = true },

  -- -------------------------------------------------------------------
  -- TORNADOES -- 3D GALE VORTEXES
  --
  -- When TORNADOES is ON and the strict voxel atmosphere is active, GALE can
  -- grow world-space funnels down from the cloud deck. Each funnel roams for
  -- about three minutes, bends around solid voxel footprints where possible,
  -- and becomes a waterspout while crossing water. Rare same-storm secondary
  -- funnels and rarer multi-funnel outbreaks are bounded by maxActive.
  --
  -- carryChance is PER NEW TORNADO. The requested default is 10%. A carry
  -- funnel forms in the distance and visibly approaches first; it can only warp
  -- to a map already present in the engine's visited-map table. During pickup
  -- the real gameplay player stays on a valid cell while the voxel renderer
  -- receives a temporary orbit/lift pose.
  --
  -- everySeconds      opportunity spacing after the first funnel in a Gale
  -- roamSeconds       mature roaming lifetime before rope-out
  -- formationSeconds  condensation time from cloud bank to ground
  -- ropeSeconds       time spent retracting back into the cloud bank
  -- secondaryChance   rare additional funnel opportunity in the same storm
  -- outbreakChance    rarer simultaneous 2-3 funnel event
  -- waterTwister      turn the lower vortex into a water-loaded waterspout
  tornado = { enabled = true, everySeconds = 90, minVisited = 4,
              carryChance = 0.10, roamSeconds = 180, formationSeconds = 8, ropeSeconds = 12,
              spawnDistanceMin = 150, spawnDistanceMax = 250, maxActive = 3,
              secondaryChance = 0.12, outbreakChance = 0.035, waterTwister = true,
              sandstorms = false, funnel = true, funnelSeconds = 2.5 },

  -- -------------------------------------------------------------------
  -- WEATHER IN THE GRASS AND ON THE WATER
  -- -------------------------------------------------------------------
  -- Fog draws out Ghosts, sunshine draws out Fire types, snow draws out
  -- Ice, and rain brings the fish up.
  --
  -- These REROLL rather than substitute: on an affected step the encounter
  -- is rolled again through the normal chain and the second roll kept only
  -- if it is the type the weather favours.  So only species the map
  -- already contains can appear, a map with no Ghost on its table is
  -- simply unaffected by fog, and a mod that rewrites the encounter tables
  -- is respected automatically.
  --
  --   strength       scales how often a reroll is taken (0 disables)
  --   fishingBonus   chance of a second cast in the rain
  --   inject         pull a dex species of the favoured type when the
  --                  map's table has none (rain -> Water, Dragonstorm ->
  --                  Dragon, …).  Uses the merged Pokédex so expanded-dex
  --                  mods are included automatically.
  --   injectChance   base chance of that injection after rerolls fail
  -- encounters.bans: hard type exclusions by weather tag (100% not that type).
  --   wet / sunny / frozen / sandy / foggy / ash → list of type names.
  --   Set bans = false to disable all hard bans.
  -- encounters.bansById: optional per-weather-id overrides, e.g.
  --   bansById = { RAIN_HEAVY = { "FIRE", "GRASS" } }
  encounters = { enabled = true, species = true, fishing = true,
                 strength = 1.0, rateBoost = 1.5, fishingBonus = 0.5,
                 inject = true, injectChance = 0.35,
                 -- Gen 1 + Gen 2 types (DARK, STEEL). Steel not banned in sand.
                 bans = {
                   wet     = { "FIRE", "STEEL" },
                   sunny   = { "WATER", "ICE" },
                   frozen  = { "BUG", "GRASS", "FLYING" },
                   sandy   = { "WATER", "BUG" },
                   foggy   = { "FIRE" },
                   ash     = { "BUG", "GRASS", "ICE" },
                   psychic = { "DARK" },
                 },
                 bansById = {} },

  followerChip = { enabled = true, seconds = 6, fraction = 1 / 32, canFaint = false },

  -- Where the weather is allowed to draw on the flat renderer.
  --
  --   "screen"     the whole window.  The default, because the engine
  --                draws the world across the whole window on most
  --                handhelds and filling only the 160x144 rect leaves a
  --                dry box in the middle of a wet screen.
  --   "playfield"  only the integer-scaled 160x144 game rect, leaving
  --                any letterbox bars clean.  Use this if you play
  --                windowed on a desktop with visible black borders.
  coverage = "screen",

  -- -------------------------------------------------------------------
  -- TIME OF DAY
  -- -------------------------------------------------------------------
  -- A Gold/Silver/Crystal-style day/night grade over the overworld, plus
  -- the engine's `world.tod` value so palette mods and AUTO weather can
  -- key off morning / day / night.
  --
  --   source = "auto"    use the active voxel host's effective IN-GAME clock
  --                      when available, otherwise this mod's own cycle.
  --                      This is the default so sun/moon/day-night stay synced.
  --            "system"  use the real clock on the device
  --            "cycle"   this mod's own cycle, `cycleMinutes` long
  --            "fixed"   pinned to `fixedPhase`
  --            "off"     no clock, no grade, no world.tod
  --
  --   phases are GSC's: MORN (04-09), DAY (09-17), EVE (17-20), NITE.
  time = {
    source       = "auto",
    cycleMinutes = 24,        -- real minutes for a whole in-game day
    fixedPhase   = "DAY",
    grade        = true,      -- draw the colour grade
    gradeStrength = 1.0,      -- 0..2; 0 is the same as grade = false
    publishTod   = true,      -- answer the engine's world.tod hook
    indoors      = 0.35,      -- how much of the grade reaches interiors
  },

  -- -------------------------------------------------------------------
  -- SEASONS
  -- -------------------------------------------------------------------
  -- Four seasons that lean AUTO weather weights (more snow in winter,
  -- more sun in summer).  Hemisphere and the on/off switch also live on
  -- the mod options page; values here are the defaults for a fresh install.
  --
  -- On SYSTEM time the real calendar is used.  On CYCLE / AUTO the in-game
  -- year is `daysPerSeason * 4` days long, advanced by the day/night clock.
  seasons = {
    enabled        = true,
    notify         = true,    -- on-screen banner when the season changes
    notifySeconds  = 3.5,
    daysPerSeason  = 15,      -- 15 in-game days = 6 real hours at default cycleMinutes=24
    placeBanner    = false,    -- location + season when entering a map / the game
  },

  -- -------------------------------------------------------------------
  -- CELESTIAL / SKY PRESENTATION
  -- -------------------------------------------------------------------
  -- `smoothSky` is Weather FX's natural-sky house rule. Voxel hosts normally
  -- paint a small set of checker-dithered horizontal palette bands. ON keeps
  -- the same live day/night/weather colours but continuously interpolates
  -- between them so the sky is clear and smooth instead of visibly striped.
  celestial = {
    enabled       = true,
    latitude      = 35.0,
    axialTilt     = 23.43928,
    verticalOrbit = true,
    pairedMoonOrbit = true,
    motionSmoothing = true, -- continuously interpolate sun/moon motion between coarse host clock ticks
    shadowMotionPrecision = 65536, -- fine in-memory shadow-map invalidation; host default is only 128
    discSupersample = 16, -- 16x local sun/moon raster; downsampled for extremely fine subpixel motion
    smoothSky     = true,
    events        = true, -- eclipses, special full moons, shooting stars/meteor showers/fireballs
  },

  -- -------------------------------------------------------------------
  -- BATTLE WEATHER
  -- -------------------------------------------------------------------
  -- `enabled` is the master config switch. The current mod menu then splits
  -- visuals (BATTLE WEATHER FX) from mechanics (BATTLE WEATHER DMG), both ON
  -- by default. The old WX RULES row was removed in 4.18.0.
  battle = {
    enabled = true,

    -- Carry the overworld's weather into a battle fought outdoors.
    -- false = battles only get weather from moves and abilities.
    seedFromOverworld = true,

    -- How many turns seeded weather lasts.  nil = the whole battle,
    -- which is what standing in a storm should mean.
    seededTurns = nil,

    -- Individual effects. Kanto-Reforged overlap is detected at load for
    -- the abilities Weather FX also implements, so multipliers never land twice.
    effects = {
      typePower      = true,   -- FIRE / WATER under sun and rain
      accuracy       = true,   -- THUNDER, BLIZZARD, HURRICANE
      solarBeam      = true,   -- one-turn in sun/harsh sun; half power in
                               -- weather that weakens Solar Beam
      residual       = true,   -- sandstorm and hail chip damage
      defenseBoost   = true,   -- ROCK special defence in a sandstorm
      speed          = true,   -- Chlorophyll / Swift Swim / Slush Rush
      evasion        = true,   -- Sand Veil / Snow Cloak
      healing        = true,   -- Ice Body / Rain Dish / Dry Skin
      heldItems      = true,   -- weather rocks, Utility Umbrella

      -- The two below are HOUSE RULES, not reference behaviour. They have
      -- their own switches so turning them off leaves a strictly faithful
      -- weather system behind.
      --
      -- They default differently on purpose: `amplified` CONTRADICTS
      -- reference multipliers (a sandstorm powering up ROCK is not a
      -- thing in any generation), so it is opt-in; `terrain` ADDS
      -- something the reference has no opinion on, so it is on.
      amplified      = false,  -- flip to true; see the note below
      terrain        = true,   -- see the `terrain` table below
    },

    -- AMPLIFIED WEATHER -- not how the real games work.
    --
    -- In the reference, a primal sky boosts its matching type by exactly
    -- the same 1.5 an ordinary one does; the nullification IS the
    -- difference. And no generation's sandstorm has ever boosted a move's
    -- power at all. With `amplified = true`:
    --
    --   HARSH_SUN    FIRE x2.0   (instead of x1.5)
    --   HEAVY_RAIN   WATER x2.0  (instead of x1.5)
    --   SANDSTORM    ROCK and GROUND x1.5
    --   HAIL/SNOWY   ICE x1.5
    --
    -- The amplified row REPLACES the reference row rather than stacking
    -- with it. Ordinary SUNNY and RAINY are untouched either way.

    -- TERRAIN -- also not reference behaviour.
    --
    -- A per-map type bonus that applies whatever the sky is doing, so a
    -- forest fight gets the canopy bonus in clear weather too. Inspired
    -- by the Gen 6+ Terrain moves, but Gen 1 has no terrain-setting move
    -- to hang it on, so it is a property of the place instead.
    --
    -- Keys are map ids, values are TYPE = multiplier (clamped 0-4). A map
    -- with no entry gets nothing. Add your own freely -- unlike most of
    -- this file, the keys here are yours and are not typo-checked against
    -- a known list.
    --
    -- The ids below are verified against tools/rom_manifest.json (the
    -- engine's own list of all 222 map ids). Ids you add are not checked
    -- against anything at runtime and fail silently if wrong -- if a bonus
    -- never fires, turn the DEBUG HUD on and compare the `map:` it reports
    -- against the key you used.
    terrain = {
      VIRIDIAN_FOREST = { BUG = 1.5, GRASS = 1.5 },
      POWER_PLANT     = { ELECTRIC = 1.5 },
      POKEMON_TOWER_1F = { GHOST = 1.5 },
      POKEMON_TOWER_2F = { GHOST = 1.5 },
      POKEMON_TOWER_3F = { GHOST = 1.5 },
      POKEMON_TOWER_4F = { GHOST = 1.5 },
      POKEMON_TOWER_5F = { GHOST = 1.5 },
      POKEMON_TOWER_6F = { GHOST = 1.5 },
      POKEMON_TOWER_7F = { GHOST = 1.5 },

      -- Johto (Gold). Only 76 of Gen 1's 222 maps survive into Gold, and
      -- Pokemon Tower and Viridian Forest are not among them -- so without
      -- these, eight of the Kanto rows above would silently do nothing on a
      -- Gold save. The table is keyed by map id, so both sets can ship: an
      -- id the running game does not have simply never matches.
      ILEX_FOREST      = { BUG = 1.5, GRASS = 1.5 },
      SPROUT_TOWER_1F  = { GHOST = 1.5 },
      SPROUT_TOWER_2F  = { GHOST = 1.5 },
      SPROUT_TOWER_3F  = { GHOST = 1.5 },
      BURNED_TOWER_1F  = { GHOST = 1.5 },
      BURNED_TOWER_B1F = { GHOST = 1.5 },
      -- POWER_PLANT exists in both games under the same id.
      -- e.g. add your own:
      -- SEAFOAM_ISLANDS_1F = { WATER = 1.5, ICE = 1.5 },   -- note the _1F
    },

    -- Residual damage: the sandstorm and hail chip.
    residualDamage = {
      fraction  = 1 / 16,   -- every typed weather chips 1/16 max HP
      canFaint  = true,
      -- Legacy compatibility for older configs.  The typed-weather system
      -- now derives immunity from each weather's Gen-1 chipType.
      sandImmune = { "ROCK", "GROUND", "STEEL" },
      hailImmune = { "ICE" },
    },

    -- Suppression: an ability that switches the weather off for the
    -- battle.  Kanto-Reforged already clears the field on AIR_LOCK entry;
    -- these are for the ones it does not handle.
    suppressAbilities = { "CLOUD_NINE" },

    -- Held items this mod recognises.  It does NOT register them -- it
    -- reads `mon.heldItem` and reacts if some other mod (Kanto-Reforged,
    -- say) provides them.  With no held-item mod installed these never
    -- match and cost one table lookup per battler per turn.
    items = {
      extenders = {                  -- add turns to a weather from a move
        DAMP_ROCK   = "RAINY",
        HEAT_ROCK   = "SUNNY",
        ICY_ROCK    = "HAIL",
        SMOOTH_ROCK = "SANDSTORM",
      },
      extendBy = 3,                  -- extra turns the rock grants
      umbrella = "UTILITY_UMBRELLA", -- holder ignores weather entirely
    },
  },

  -- -------------------------------------------------------------------
  -- PERFORMANCE
  -- -------------------------------------------------------------------
  -- "auto" | "max" | "high" | "medium" | "low" | "potato".  AUTO starts HIGH and adapts between POTATO..HIGH from frame timing. MAX is
  -- manual-only. An explicit in-game/mod-manager QUALITY selection wins over this file.
  quality = "auto",

  -- Hard ceiling on particles regardless of tier, for a very slow device.
  -- nil = no extra cap.
  maxParticles = nil,

  -- -------------------------------------------------------------------
  -- MISC
  -- -------------------------------------------------------------------
  -- Seconds a weather takes to fade in or out.  Lower is snappier.
  transitionSeconds = 3.2,

  -- Show the one-line diagnostic readout.
  debug = false,

  -- -------------------------------------------------------------------
  -- DEBUG RAIN -- the "is this mod working at all" switch
  -- -------------------------------------------------------------------
  -- Set true and the answer is unambiguous: heavy rain everywhere,
  -- indoors and out, the diagnostic readout on, and the weather system
  -- switched on even if the OPTIONS row is on OFF.
  --
  -- This is THE ONE SETTING THAT OVERRIDES OFF, and it is deliberate.
  -- Everything else in this mod treats OFF as sacred, because that is the
  -- player's off switch and the guarantee that the frame is byte-for-byte
  -- vanilla.  But a diagnostic whose whole job is to answer "is the mod
  -- running" is useless if the most common reason it is not running also
  -- silences the diagnostic -- which is exactly the trap `force` falls
  -- into: `force` is about WHICH weather, so it cannot turn the system on,
  -- and a config with `force` set and the row on OFF looks broken.
  --
  -- Turn it off again when you are done: it ignores every other setting
  -- here on purpose.
  debugRain = false,
}
