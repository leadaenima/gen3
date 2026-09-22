# Weather FX — full reference

This is the complete reference: every config key, every compatibility note,
every implementation detail. **If you just installed the mod, read
[../README.md](../README.md) instead** — it covers everything most people
need in about a tenth the length.

## Weather FX 8.1.4

8.1.4 fixes the live strict-3D/FPV rain visibility regression found in 8.1.3. `WorldPrecip` no longer assumes `Voxel3D.focus` is a camera look target: rain prefers `lookFlat`, accepts explicit camera-forward vectors, rejects mostly vertical player-anchor focus vectors, and disables CPU rear-culling when the host cannot provide a trustworthy heading. Manual `RAIN_LIGHT` is release-tested to spawn from the precipitation/cloud-deck band and submit nonzero 3D vertices under the failing FPV camera shape. Root `V.safeCall` is also bound to preserve the expected `(fn, ...)` protected-call contract.

## Weather FX 8.1.3

8.1.3 centralizes fail-soft host/render calls through `SafeCall`. `mod.exports.engineHealth()` now includes `safeCallErrors`, `safeCallLastScope`, and `safeCallLastError`; FULL DEBUG HUD adds a `safe:errN <scope>` line whenever a protected host/render operation has failed. Repeated failures are rate-limited in the log and successful calls allocate no temporary result table.

## Weather FX 8.1.2

> **Testing it? Mod manager → Weather FX → DEBUG RAIN → ON.**
> (Or `debugRain = true` in `config.lua` for a folder install.) Heavy rain
> everywhere, indoors and out, diagnostic readout on, and the system
> switched on even if the OPTIONS row is on OFF. It is the only setting
> that overrides OFF, and it exists precisely so that "is this mod
> working" has an unambiguous answer.

Dynamic weather for Gen1Recomp — overworld **and** battle — plus a
Gold/Silver/Crystal-style day/night grade with its own clock.

Twenty-nine weather types are defined by the live catalogue. They cover clear,
sun/heat, rain/storm, snow/hail, sand/dust/ash, wind, fog/mist and the typed
fronts (including verdant rain, dragonstorm and psystorm). Twenty-eight are
pinnable; MIST remains an AUTO-only fog variation.

**The simulation is renderer-independent, but presentation is not.** Flat modes use the 2D compositor; supported voxel hosts use the strict 3D atmosphere when AUTO/3D is selected, and FPV intentionally forces strict 3D so weather remains spatial. If a supported 3D path is unavailable, AUTO falls back to 2D. The two presentations share the same weather authority rather than running separate simulations.

### 8.1.2 tornado landing safety, rainbows and wind walking

Tornado carry destinations are **outdoor overworld only**. A map being visited or a cell being flat is not enough: Weather FX validates the exact landing cell and performs a bounded reachability search that must reach a real connection to another outdoor map. Exact door/warp cells, buildings, caves, dungeons/interiors and dead-end islands are rejected. If an otherwise valid escape route needs water, the live overworld must report Surf as currently legal. Water landings enter surfing state before control returns; if that cannot be confirmed after transfer, Weather FX returns to the saved origin instead of releasing the player into a possible softlock.

`rainbow.enabled` controls the post-rain primary rainbow system (`memorySeconds` and `fadeSeconds` tune persistence/easing). The strict 3D/FPV bow only becomes visible after recent rain when the real sun is low and visible and cloud transmission is opening. It is far-depth/LEQUAL sky geometry drawn before clouds/weather so solid world geometry and cloud banks can occlude it.

`wind.playerMovement` enables the optional walking response to the existing WindEngine/WindFlow. `headwindSlow` defaults to 0.10, `tailwindBoost` to 0.04, and `minimumStrength` to 0.10. Grid walking uses `movement.speed`; supported FPV/free-move hosts receive an in-memory wrapper. Bicycle and Surf movement are deliberately excluded.


---

## Install

1. Drop the `weather_fx` folder into your `mods/` directory, so you have
   `mods/weather_fx/manifest.json`.
2. Start the game.
3. **OPTIONS → WEATHER** — set it to `AUTO`.

Or install the `.modpkg` through the in-game mod manager (`F10`).

To configure it, open `mods/weather_fx/config.lua` in any text editor and
restart the game (or press `F5` in developer mode). The file is optional —
delete it and the built-in defaults are used.

The code targets the engine's desktop and Android-compatible mod surfaces. AUTO starts at HIGH because the mod sandbox exposes no safe OS query; the frame-time governor then adapts from measured frame time. This standalone audit does not substitute for a real device run, so platform-specific final rendering/FPS must be validated on the target device.

---

## Controls

**OPTIONS → WEATHER** mirrors the primary weather ladder: OFF/AUTO/CYCLE plus the 28 pinnable weather definitions (MIST remains AUTO-only). The Weather FX in-game menu exposes **53 controls in 11 nested submenus**, and **SELECT: HELP** opens the description attached to every row.

| Submenu | Main controls |
| --- | --- |
| WEATHER | weather, intensity, rare-weather rate, rotation speed, presentation, indoor behavior |
| SIMULATION | natural-transition speed, fronts/strength, mesoscale localized weather/strength, wind walking |
| ATMOSPHERE | clouds, fog/sand/dust intensity, splashes, puddles, post-rain rainbows, snow shape, leaf color |
| STORMS | lightning, NPC lightning/chance, tornadoes/frequency |
| CELESTIAL | sun god rays, celestial events, smooth sky, motion smoothing |
| TIME & SEASONS | time source/day length, seasons/length, hemisphere, notifications |
| AUDIO | master SFX, indoor attenuation, thunder, wind |
| GAMEPLAY | weather encounters, legendary events, follower weather damage |
| BATTLE | presentation, battle visuals/mechanics, amplified rules, backdrops |
| PERFORMANCE | quality tier, optional hard particle cap |
| DEBUG | forced-rain diagnostic, debug HUD |

Rows with a **CONFIG** choice preserve `config.lua` until the player deliberately overrides that setting. Developer console weather commands remain available when developer mode is enabled.

---

## config.lua

The menu answers "what do I want to see right now" and has to work on a
handheld with a d-pad, so it is short. The file answers "how should this
mod behave in my playthrough", and none of that belongs on a row you cycle
with a d-pad. Both exist, with one documented precedence order:

```
1. config.force        the file pins one weather everywhere
2. config.locations    the file pins one weather on this map
3. the OPTIONS row     OFF / AUTO / a pinned weather
4. the AUTO clock
```

A malformed config file cannot break the mod. It is loaded in a sandbox
and walked against the defaults: a syntax error, a file that throws, a
non-table return, a typo'd key, an out-of-range number or an unknown
weather id all end with a usable config, a running mod, and a message
naming the problem in the mod manager's error feed.

### Force weather

```lua
return {
  force = "RAIN_HEAVY",   -- always a downpour, everywhere
}
```

Valid ids: `CLEAR` `SUNNY` `HARSH_SUN` `RAIN_LIGHT` `RAIN_HEAVY`
`HEAVY_RAIN` `STORM` `SNOW_LIGHT` `BLIZZARD` `HAIL` `SANDSTORM`
`STRONG_WINDS` `MIST` `FOG`.

### Location overrides

By the engine's map id, in either of two forms:

```lua
return {
  locations = {
    -- always, no exceptions
    LAVENDER_TOWN    = "FOG",

    -- with detail
    ROUTE_23         = { weather = "HAIL",  chance = 0.6 },
    INDIGO_PLATEAU   = { weather = "SNOW_LIGHT", chance = 0.7 },
    POKEMON_TOWER_1F = { weather = "MIST",  indoors = true },
    ROUTE_12         = { weather = "SANDSTORM", chance = 0.4 },
  },
}
```

- `chance` is rolled **once per arrival**, not per frame, so `0.6` means
  "hail three visits in five" rather than a flicker.
- `indoors` decides whether the override reaches interiors. A fog override
  on a town should not fog the houses in it; a mist override on the
  Pokémon Tower should.
- A hard override (`chance = 1`) **parks the AUTO clock** while you are on
  that map and resumes it where it left off when you leave — otherwise ten
  minutes in Lavender Town would silently roll the sky six times.

The shipped `config.lua` already enables Lavender Town fog, Route 23 hail,
Indigo Plateau snow, sea-route mist, Viridian Forest mist and Cinnabar
sun. Delete any you don't want.

For a softer nudge there is `bias`, a per-map multiplier on AUTO's
weighting rather than an override:

```lua
bias = {
  ROUTE_22       = { frozen = 2.0 },
  VERMILION_CITY = { fog = 1.8 },
},
```

### Which weathers exist

```lua
weathers = { THUNDERSNOW = false, ASHFALL = false },
```

Switches a weather off absolutely — checked before any weighting. To make
one rarer or commoner instead, use `tuning.<ID>.weight`. For how often the
out-of-place weathers appear at all, the **RARE WX** row is the quicker
dial: the built-in geography suppresses snow and grit hard away from the
maps that argue for them, and RARE WX scales that suppression rather than
the weather, so a cold/snow-biased route keeps its snow bonus at every setting.

### Per-weather tuning

```lua
tuning = {
  ALL      = { density = 1.0, intensity = 1.0, speed = 1.0, duration = 1.0, weight = 1.0 },
  STORM    = { density = 1.4, duration = 0.5 },
  BLIZZARD = { density = 0.6 },
},
```

`ALL` multiplies with the specific entry. `density` scales the particle
**cap**, so turning it up genuinely puts more drops in the sky and turning
it down frees the memory. `duration` scales how long an AUTO spell lasts.

### Auto intensity and splashes

```lua
autoIntensity = { min = 0.5, max = 1.4, seconds = 1.0 },
splashSpread  = 1.0,
```

`autoIntensity` is used only when the INTENSITY row is set to AUTO. Rain,
snow, grains, haze and lightning each breathe on an unrelated period, so
they never swell together — one shared oscillator would read as the
brightness moving rather than the weather. The grade channels (gloom,
warmth, glare) never breathe, on purpose: a pulsing full-screen multiply
looks like a fault.

`splashSpread` is how far up the screen drops may land. This is a
top-down game, so the whole screen is ground and the default lets rain
burst at every depth at once. `0` puts every splash back on the bottom
edge, which is what a side-on game would do.

### Coverage

```lua
coverage = "screen",   -- "screen" | "playfield"
```

`screen` (the default) draws weather across the whole window. `playfield`
restricts it to the integer-scaled 160x144 game rect, leaving letterbox
bars clean — useful windowed on a desktop, wrong on most handhelds, where
the engine composites the world across the full screen and the 160x144
rect is a much smaller box inside it.

### Visual toggles

Every drawn layer switches off individually, and switching one off removes
its code path rather than making it transparent:

```lua
visuals = {
  precipitation = true,  splashes = true,  fog  = true,
  veil  = true,  tint = true,  glare = true,  lightning = true,
  battleWeather = true,  textBoxClear = true,
},
```

### Everything else

`quality`, `maxParticles`, `transitionSeconds`, `debug`,
the whole `time` block and the whole `battle` block. Every key is
documented inline in the shipped file.

---

## Testing and troubleshooting

If you see no weather, the diagnostic readout (`debug = true`, or
`debugRain = true` which implies it) names the reason on the first line:

| Readout says | Meaning | Fix |
| --- | --- | --- |
| `btl -!indoors` | An indoor battle inherits no sky, by design | Fight outdoors, or set a `locations` override with `indoors = true` |
| `btl -!seed-off` / `btl -!battle-off` | `seedFromOverworld` or `battle.enabled` is false in `config.lua` | Set it back to `true` |
| `Wx OFF (row is OFF)` | The ladder is at level 0. Nothing ticks, nothing draws, the frame is vanilla | OPTIONS → WEATHER → anything |
| `Wx OFF (force ignored - row is OFF)` | `config.force` is set but the row is OFF | Same. `force` says *which* weather, not *whether* |
| `AUTO CLEAR 412s` | AUTO has rolled clear skies for the next 412 seconds. Working as intended | Wait, or pin a weather on the row |
| `r0 s0 g0` with a weather named | Weather is set but no particles exist | You are indoors, or `visuals.precipitation = false`, or `density = 0` |
| `Day 13:00/none` | The clock never ran, which only happens at level 0 | Same as the first row |
| `L0` | The raw ladder level the engine handed the mod. `L0` is OFF | OPTIONS → WEATHER, or DEBUG RAIN → ON |
| ` DBG ` after the weather | DEBUG RAIN is on — it forces heavy rain and deliberately ignores the indoor rule | Mod manager → DEBUG RAIN → OFF |
| `in` / `out` / `hid` after the clock | Whether the game thinks you are under a sky, indoors, or looking at a menu | — |
| `cfg:NONE` | There is no readable `config.lua` — normal for a `.modpkg` install | Use the mod-manager rows, or install as a folder to edit the file |
| `/cycle`, `/system`, `/voxel`, `/fixed` | The clock is running from that source | — |

**`force` deliberately cannot turn the system on.** OFF is the player's
off switch and the guarantee that the frame is byte-for-byte vanilla, so
nothing in the config overrides it — except `debugRain`, whose entire job
is to answer "is this running", and which would be useless if the most
likely reason it is *not* running also silenced it.

Two more things that make a working mod look broken:

- **Rain never falls indoors, in caves, or in dungeons** (except under
  `debugRain`, which ignores the rule on purpose). Test outside.
  Inside you only get the storm's gloom, which is easy to read as nothing.
- **Clear skies at midday draw literally nothing** — `available()` returns
  false and the engine skips allocating the present canvas. That is
  intentional, but it means "I set AUTO and saw nothing" is inconclusive.
  Pin `HEAVY` instead.

---

## Time of day

The grade has **its own pipeline and its own OPTIONS row**, separate from
weather. Turning weather off does not turn the night off, and pinning
`TIME` to `NITE` is the quickest way to confirm the grade is drawing at
all — it does not need a config file or a keyboard.

`DAY` is exactly neutral, so midday genuinely costs nothing: `available()`
answers false and the engine skips the present canvas entirely.


Version 1 borrowed Dramatic Shape's clock, which meant no night without
that mod. Version 2 carries its own and defers to Dramatic Shape only when
it is there.

```lua
time = {
  source        = "system", -- system | auto | cycle | fixed | off
  cycleMinutes  = 24,
  fixedPhase    = "DAY",
  grade         = true,
  gradeStrength = 1.0,
  publishTod    = true,
  indoors       = 0.24,
  indoorRainHighGain = 0.20,
  indoorWindHighGain = 0.12,
  indoorThunderHighGain = 0.08,
  indoorTransition = 0.45,
},
```

| Source | Clock |
| --- | --- |
| `system` | **Default.** The device's real clock — what GSC actually did |
| `auto` | Dramatic Shape's if installed, otherwise `cycle` |
| `cycle` | This mod's own accelerated day, `cycleMinutes` long |
| `fixed` | Pinned to one phase, for screenshots |
| `off` | No clock, no grade, no `world.tod`. Vanilla lighting |

**Phases are GSC's, plus one.** Gold and Silver shipped morning, day and
night palettes and Crystal kept them; this adds `EVE` between day and
night, because the interesting half of a sunset is the half GSC had no
palette for. A palette mod that only knows `MORN`/`DAY`/`NITE` never
matches `EVE` and falls through to its default, which is correct
behaviour, not a bug.

**The grade is a multiply plus an add, not a palette swap.** A palette
swap is what the hardware did and would be more faithful, but it needs a
second full set of palettes authored per map per colour mode and would
fight every other palette mod for the same registry. A grade over the
finished world costs one rectangle, works identically in every colour
mode, rides through GBC FX because that runs after it, and composes with
the weather because the same compositor draws both.

`DAY` is exactly neutral, so **midday costs nothing at all** — the grade
is skipped rather than drawn as an identity multiply.

The mod also answers the engine's `world.tod` hook, so palette mods can
key off the hour through `map.palette` without knowing where the hour came
from, and anything listening to `world.tod_changed` gets morning and night
for free.

---

## How it works with Dramatic Shape

This mod does **not** patch Dramatic Shape, splice into it, read its
files, or require it.

The engine's `render_pipelines` registry lets one record declare more than
one draw stage, and this mod declares both whole-frame stages plus a
battle hook:

| Stage | Runs | Used for |
| --- | --- | --- |
| `worldPresent` | over the finished world image, before the UI composites — **only when some pipeline rendered the world** | the diorama |
| `present` | over the whole finished frame — **always** | flat, tilt, zoom, every colour mode |
| `battle.overlay` | inside the battle's own 160×144 canvas | battles |

Per frame exactly one whole-frame stage draws: `worldPresent` sets a flag,
`present` sees it, clears it, and hands its canvas straight back. So with
the diorama on, rain falls *behind* the dialog box; with it off, `present`
covers the frame instead, scissored to the playfield so nothing falls in
the letterbox bars — and clipped above an open text box so it lands behind
the text rather than on it. Add a third-party world pipeline tomorrow and
this mod supports it unchanged, because **nothing on the draw path names
any renderer**.

Priority is `5`, below Dramatic Shape's `voxel` (20) and `tiltshift` (10).
Three things follow from that one number:

1. The OPTIONS rows sort VOXEL → T-SHIFT → WEATHER.
2. A world pipeline keeps the world pass; this mod declares no `drawWorld`
   at all, so it never competes for it.
3. The `worldPresent` fold reaches this pass *after* the tilt-shift blur,
   so **rain stays sharp over a blurred diorama** instead of being smeared
   into it.

For the clock, Dramatic Shape publishes its whole module namespace as
`mod.exports.lib`, so the bridge is the documented one with no patching:

```lua
mod.find("DRAMATIC_SHAPE").exports.lib.require("DayNight")
```

The handle is resolved **lazily, on first use** — a handle taken at load
could be taken before that mod's entry chunk assigned its exports on some
orderings, and a `nil` cached then would be a `nil` forever. Every probe
is guarded: if that mod changes its internals in a future version, this
one loses a lighting nuance and logs a warning, it does not crash.

---

## Battle view, and wide-battle mods

```lua
battleView = "auto",   -- "auto" | "canvas" | "screen"
```

`battle.overlay` draws inside the engine's 160x144 battle canvas, which
scales with the battle and passes through its palette handling — the right
place normally, and the wrong place when another mod draws a battle wider
than that, because then it covers only the classic 4:3 box inside a larger
scene.

`auto` picks `screen` when **StadiumBattleFX**, **DRAMATIC_SHAPE** or
**DRAMALESS_SHAPE** is installed, and `canvas` otherwise. Force either if
the guess is wrong for your setup.

## How it works with Dramaless Shape

`DRAMALESS_SHAPE` is a fork of `DRAMATIC_SHAPE` (it declares a conflict
with it, so only one ever loads). It keeps the same `mod.exports.lib`
seam and ships the same `lib/DayNight.lua`, so everything this mod does
with the original works with the fork: the day/night clock, compositing
under the UI through `worldPresent`, and switching battle weather to the
whole screen for its 3D arenas. `lib/Interop.lua` treats them as one
family, and shape-checks what it finds rather than trusting a name.

## How it works with Kanto-Reforged

**Kanto-Reforged already implements battle weather**, and this mod does
not build a second one.

Reforged's Sunny Day / Rain Dance / Sandstorm / Hail moves, its Drought /
Drizzle / Sand Stream / Air Lock abilities, its Weather Ball, its Forecast
Castform, its Sand Veil and its Chlorophyll and Swift Swim multipliers all
read `battle.field.weather` and expect the strings `SUNNY`, `RAINY`,
`SANDSTORM`, `HAIL`, `SNOWY`.

So **that field is the single source of truth**, this mod writes it in
that vocabulary, and both systems read the same value. The alternative — a
parallel field — would mean a Rain Dance that made it rain for Swift Swim
but not for this mod's Water boost, which is exactly the class of bug that
makes two mods "incompatible".

`HARSH_SUN`, `HEAVY_RAIN`, `STRONG_WINDS` and `FOG` extend the vocabulary.
Reforged passes a value it does not recognise straight through, so
extending is safe.

**Capability detection, not version checking.** On load this mod asks what
is already implemented and switches off its own copy:

| Effect | With Kanto-Reforged | Standalone |
| --- | --- | --- |
| Weather Ball type/power | Reforged | n/a — the move doesn't exist in Gen 1 |
| Forecast / Castform | Reforged | n/a — the species doesn't exist |
| Sand Veil evasion | Reforged | this mod |
| Chlorophyll / Swift Swim speed | Reforged | this mod |
| Everything in the table below | this mod | this mod |

Nothing is applied twice in either case. The test suite drives both
configurations and asserts that Sand Veil fires exactly once.

**Held items** are recognised, not registered: this mod reads
`mon.heldItem` (Reforged's storage) and reacts. With no held-item mod
installed the lookups never match and cost one nil check.

---

## Battle weather

### What is implemented

| Effect | Detail |
| --- | --- |
| **Type power** | Sun: FIRE ×1.5, WATER ×0.5. Rain: WATER ×1.5, FIRE ×0.5 |
| **Primal nullification** | Harsh sunshine evaporates Water attacks; heavy rain fizzles Fire attacks, with a message |
| **Accuracy** | THUNDER and HURRICANE never miss in rain, halved in sun. BLIZZARD never misses in hail or snow. Fog costs everyone accuracy |
| **Solar Beam** | Charge skipped in sun/harsh sun; power halved in rain, sand, hail, snow and fog |
| **Residual damage** | Sandstorm and hail chip 1/16 max HP per turn, configurable fraction, with type immunities |
| **Special defence** | ROCK takes ⅔ special damage in a sandstorm |
| **Strong Winds** | Super-effective hits on FLYING types are halved |
| **Speed** | Chlorophyll, Swift Swim, Sand Rush, Slush Rush — same-priority turns only |
| **Evasion** | Sand Veil, Snow Cloak (20%) |
| **Healing** | Ice Body, Rain Dish, Dry Skin heal; Dry Skin and Solar Power burn in sun |
| **Residual immunity** | Overcoat, Magic Guard, and the sand/ice ability families |
| **Suppression** | Cloud Nine. (Air Lock is Reforged's — it clears the field outright on entry, same outcome by a different route) |
| **Held items** | Damp / Heat / Icy / Smooth Rock extend a weather by 3 turns; Utility Umbrella makes its holder ignore weather entirely |
| **Weather Ball, Forecast** | Reforged's, deferred to |
| **Terrain** *(house rule, on)* | A per-map type bonus, applied whatever the sky is doing |
| **Amplified** *(house rule, off)* | A stronger primal sky, and power for the type that lives in a sandstorm or a blizzard |

The battle screen's weather is driven by `battle.field.weather` too, not by
the overworld — so an indoor battle is dry unless a move or ability makes
weather, and a Rain Dance rains wherever it is cast.

### Which generation each of those comes from

The table above is often described as "reference behaviour", and that is too
generous. Gen 1 has **no weather at all** -- not one move or mechanic -- and
Gen 2 has only three weathers (Rain Dance, Sunny Day, Sandstorm) with no
hail, no fog and no primal skies. So most of the list is later-generation
behaviour brought back, which is a feature, not a problem -- it just should
not be called faithful.

| From | Effects |
| --- | --- |
| **Gen 2** | Fire/Water type power, Thunder's accuracy in rain and sun, sandstorm chip damage, Solar Beam's charge behaviour in sun |
| **Gen 3** | Hail itself, Solar Beam's halved power in other weather, Weather Ball, Castform, the weather-extending rocks |
| **Gen 4** | Blizzard never missing in hail, ROCK's special-defence boost in sandstorm |
| **Gen 5+** | Ice Body / Rain Dish / Dry Skin healing, Overcoat, Cloud Nine's modern form |
| **Gen 6** | Primal weather (harsh sun and heavy rain nullifying the opposing type), Strong Winds |
| **Gen 8** | Utility Umbrella |
| **This mod** | Terrain bonuses, and Amplified -- see below |

Two things in the table exist in **no** generation and are this mod's own, so
they carry their own switches rather than riding on `typePower`, and they
default differently.

**TERRAIN — on by default.** A per-map type multiplier, applied whatever
the weather: Bug and Grass under the Viridian Forest canopy, Electric in
the Power Plant, Ghost on every floor of the tower. Inspired by the Gen 6+
Terrain moves, but Gen 1 has no terrain-setting move to hang it on, so it
is a property of the place instead. Because it is *additive* — the
reference has no opinion about forests powering up Bug moves — it
contradicts nothing this mod already promises, which is why it is on.

```lua
battle = {
  terrain = {
    VIRIDIAN_FOREST = { BUG = 1.5, GRASS = 1.5 },
    SEAFOAM_ISLANDS_1F = { WATER = 1.5, ICE = 1.5 },  -- add your own
  },
}
```

Keys are map ids and are **yours** — unlike most of `config.lua`, they are
not typo-checked against a known list, because there is no list to check
against. Multipliers clamp to 0–4 and type names are case-insensitive. A
user table replaces the bundled defaults rather than merging into them.

**AMPLIFIED — off by default.** Harsh sun takes FIRE to ×2.0 and heavy
rain takes WATER to ×2.0 instead of the reference ×1.5; a sandstorm powers
up ROCK and GROUND; hail and snow power up ICE. Ordinary sun and rain are
untouched.

```lua
battle = { effects = { amplified = true } }
```

It is off by default because it *contradicts* reference multipliers this
mod implements and tests — the suite asserts that a sandstorm does not
power up ROCK, and that assertion is correct. Switching a house rule on by
default would mean the mod quietly stopped doing what its own tests say it
does. The amplified row **replaces** the reference row rather than
stacking with it; there is a test for the ×3.0 that stacking would
otherwise produce.

The bundled map ids are **verified** against `tools/rom_manifest.json` in
the engine repo — all 222 real map ids — so the shipped entries are correct.
(The tower floors are `POKEMON_TOWER_1F`, with the underscore; an earlier
draft of this feature had them wrong and every Ghost bonus was silently
dead.)

Ids you add yourself are still yours to get right, and a wrong one fails
silently by design — there is no list to typo-check against at runtime. If a
bonus never seems to fire, turn the DEBUG HUD on: the readout ends with
`map:` and `terr:`, which answers whether the id you used is the id the game
is using.

### Gen 1 limitations, stated plainly

- **No abilities and no held items in vanilla.** Everything above that
  touches one is inert without a mod that adds them — by construction, not
  by a version check: `abilityOf` simply never returns anything and
  `mon.heldItem` is always nil.
- **No Weather Ball, no Castform, no Synthesis/Moonlight.** These moves and
  species do not exist in Gen 1. With Reforged they do, and it implements
  the first two.
- **Solar Beam's sunny charge skip is implemented through `battle.charge_required`.**
  Weather FX returns `false` for Solar Beam/Solar Blade in sun or harsh sun and
  preserves the engine/other-mod charge decision in every other condition.
- **Special is one stat in Gen 1.** "Special Defence up in a sandstorm"
  would raise the attacker's side too, so it is applied as a damage
  reduction on incoming special moves only — the half that behaves like
  the modern stat.
- **Weather-based evolution** (Sliggoo → Goodra) has no Gen 1 analogue and
  is not attempted.

### What gates it

```lua
battle = {
  enabled = true,             -- master config switch
  seedFromOverworld = true,   -- carry the outdoor sky into a battle
  effects = { typePower = true, accuracy = true, ... },
},
```

The mod-manager rows **BATTLE WEATHER FX** and **BATTLE WEATHER DMG** are the
player-facing authorities for visuals and mechanics. The old WEATHER/WX RULES
ruleset gate was retired in 4.18 and is no longer registered or consulted.
Older configs may still contain `requireRuleset`; the loader accepts and drops
that obsolete key so upgrades remain clean without advertising a switch that
does nothing.

Effects apply to whatever weather is **already in the field**. With no weather
running and seeding disabled, every hook is a pass-through. Outdoor seeding
copies the overworld weather into an otherwise-clear battle; indoor/cave
battles do not inherit the sky, and weather already set by a move/ability is
never overwritten.

No `statuses` record is registered — that is one of the engine's link
registries, and writing to it would oblige this mod to declare `affects_link`,
which would be a lie.

---

## Performance

- **One draw call for every particle.** Every drop, flake, grain, leaf and
  splash tick goes into a single `SpriteBatch` on a 1×1 white texture.
- **Nothing is allocated after warmup.** Flat parallel arrays sized once to
  the quality cap; a drop that falls off the bottom is rewound, not freed
  and recreated. Density changes by moving an `active` count, so a drizzle
  is the same memory as a storm and the GC never sees weather.
- **Three pools, not six.** Rain and snow get their own because they
  coexist. Hail, sand and debris share the **grain** pool — they are all
  "a hard little thing thrown across the screen" and differ only in
  colour, speed, angle and whether they tumble. Each grain carries its
  kind, rolled at spawn against the live channel mix, so a sandstorm
  turning to hail reads as the storm turning over rather than as one
  effect being swapped for another.
- **Clear weather costs nothing.** The pipeline's `available()` callback,
  re-read every frame, answers `false` whenever there is nothing to draw —
  OFF, clear skies at midday, indoors, or a full-screen menu over the
  world. On those frames the engine does not even allocate the present
  canvas (`Pipelines.wantsPresent`), so the composite is the vanilla one.
- **Quality caps**, per tier:

  | Tier | Rain | Snow | Grain | Splashes | Fog layers | 3D precip scale | Star step | Sun layers | Drawn bolt |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
  | HIGH | 720 | 3200 | 520 | 120 | 3 | 1.00 | 1 | 4 | yes |
  | MEDIUM | 380 | 1640 | 260 | 55 | 2 | 0.70 | 2 | 3 | yes |
  | LOW | 160 | 720 | 110 | 0 | 2 | 0.45 | 4 | 2 | no |
  | POTATO | 90 | 360 | 60 | 0 | 2 | 0.28 | 6 | 1 | no |

  AUTO starts at HIGH on every platform. A governor watches a slow
  average of *whole-frame* time and steps the tier down after three
  sustained seconds of late frames, back up after three sustained seconds
  of headroom. A single hitch — a load, a window drag — is clamped out and
  never moves it. Pick a tier by hand, or set `quality` in `config.lua`,
  and it is never overridden. `maxParticles` is a hard ceiling on top.
- **Particles are sized in Game Boy pixels**, multiplied by the frame's
  scale at draw time, so weather looks the same at 1× in a small window, at
  6× fullscreen, through the survey zoom, and over a diorama.
- **The battle overlay is deliberately thinner** — a battle screen is
  mostly HUD and the HUD has to stay readable. Particle counts are a
  fraction of the overworld budget and ground splashes are dropped
  entirely (there is no ground).

---

## Turning it off

Set **OPTIONS → WEATHER** to `OFF`. At level 0 nothing ticks, the pipeline
is not eligible, no present canvas is allocated, and the frame is
byte-for-byte vanilla. Disabling the mod in the manager or deleting the
folder does the same; the ladder level is remembered in
`save.options.pipelines`, so re-enabling restores what you had.

---

## Battle backdrops

23 painted scenes behind and around the battle screen, day and night
variants. **Art: CDRX73 · DerxwnaKapsyla · http404error · Game Freak.**

Picked by the weather first and the map second: a blizzard puts you on the
snow field wherever you are, a sandstorm on the desert one, and otherwise
a cave is a cave, the plateau keeps its dedicated plateau battle art, Cinnabar is a beach and a route is tall grass. These are battle-scene categories only; Weather FX does not create mountain terrain in the voxel world. Night variants follow the mod's own clock.

Switched by **BATTLE ART** in the mod manager, or `battleBackdrops` in
`config.lua`; `battleBackdropDim` controls how far they are darkened so
they read as a setting rather than competing with the fight.

**BATTLE ART** has three settings: `OFF`, `AROUND` (scenery in the bars
beside the battle, the default) and `BEHIND` (also replaces the battle's
white field, so the scene continues inside the box).

`BEHIND` is the one part of this mod that patches engine internals -- it
intercepts the battle's field fill, because there is no hook for it. It
stands down for the nickname screen, for SGB colour mode, and when another
mod is staging battles. `AROUND` uses only the documented
`render.letterbox` hook and cannot contend with anything.

The reason `BEHIND` needs a patch at all: there is no hook between the battle
filling its field and drawing its sprites. `battleBg = "world"` exposes
the voids only -- the battle still paints an opaque field over its own
area -- and `render.compose` would demand this mod take over the entire
window composite, SGB zones and palette pass included, to place one image.
`render.letterbox` is the documented hook for art behind the playfield,
and it is what this uses. Drawing behind the sprites needs one new engine
hook: a `battle.background` called after the field fill, the natural
sibling of the `battle.overlay` that already exists.

## Credits

Battle backdrop art, as supplied by the packager:

  Battle backdrops:  CDRX73 · DerxwnaKapsyla · http404error · Game Freak
  Rain/storm loops:  Relic Castle weather tutorial pack
  Thunder:           Pixabay (royalty-free)

Roles were not specified alongside the names, so they are listed together
rather than guessed at. If you know who did what, correct this file --
attribution is worth getting exactly right, and a wrong role is worse than
no role.

Everything else in this mod -- the particles, the fog, the lightning, the
day/night grade -- is generated at runtime and ships no pixels at all.

## Assets

The particle and fog art is generated at runtime, deliberately. Rain streaks, flakes, hail, sand
and leaves are a 1×1 white pixel generated at runtime, scaled and rotated;
the fog banks are three octaves of value noise generated into a 128×128
texture on first use, seeded so it is identical every launch. Nothing is
shipped, nothing is derived from a ROM, and nothing has to be kept in step
with a palette mode. The only shipped assets are the battle backdrops above; nothing in
the mod is derived from a ROM, and `python3 tools/modkit.py lint
mods/weather_fx` confirms it.

---

## Extending it

Adding a weather type is adding one entry to `lib/Types.lua`:

```lua
{
  id = "DRIZZLE_FOG", label = "SMOG", wet = true, battle = "FOG",
  weight = 3, minMin = 2, maxMin = 5,
  follows = { RAIN_LIGHT = true },
  ch = { rain = 0.15, fog = 0.6, veil = 0.15, dim = 0.12, cool = 0.1 },
},
```

Nothing else needs touching. The OPTIONS ladder, the AUTO picker, the
region bias, the transitions, the config validator and the battle layer
all read that table.

That works because a weather is not a thing with its own renderer — it is
a set of numbers, one per **channel** (`rain`, `hail`, `sand`, `debris`,
`fog`, `veil`, `dim`, `cool`, `warm`, `glare`, `gust`, `strike`, and the
speed/angle/length modifiers). Each draw system reads its own channels and
nothing else, and the state machine eases every channel toward the active
type's value. So:

- **transitions are free** — rain stopping as fog rolls in is the rain
  channel easing to 0 while the fog channel eases to 1, with no cross-fade
  code and no second weather kept alive;
- **a new channel is backward compatible** — channels absent from a
  definition read as 0, so adding one to a single type does not require
  touching the other thirteen;
- **nothing can desync** — there is one authority for "how much rain is
  falling", and it is a number, so an unknown weather id degrades to
  `CLEAR` rather than to a half-drawn frame;
- **capability tags do the rest** — `wet`, `frozen`, `sunny`, `sandy` are
  read by the battle layer *and* the region bias, so a new type is covered
  by both without being added to a second list anywhere.

To add a channel with new *behaviour*, add it to one type's `ch` table and
read it in the system that should respond. `lib/Draw.lua` is the whole
compositor and the order of the pass is documented at the top of it.

---

## Files

```
weather_fx/
├── manifest.json
├── config.lua                the editable configuration, documented inline
├── main.lua                  pipeline record, hooks, events, console, exports
├── lib/
│   ├── Types.lua             the weather catalogue — the extension point
│   ├── Config.lua            loading, validating and resolving config.lua
│   ├── WeatherState.lua      state machine, AUTO scheduler, channel easing
│   ├── TimeOfDay.lua         the clock, the GSC grade, world.tod
│   ├── Settings.lua          the mod-manager rows and typed readers
│   ├── Scene.lua             what the frame shows, from the state stack
│   ├── Quality.lua           tiers, budgets, the adaptive governor
│   ├── Particles.lua         rain, snow, grains, splashes — one draw call
│   ├── Fog.lua               runtime noise, parallax banks
│   ├── Lightning.lua         strike scheduler, flash envelope, bolts
│   ├── Draw.lua              the compositor: the order of the pass
│   ├── BattleDraw.lua        weather inside the battle's own canvas
│   └── Battle.lua            the whole battle weather layer
├── tests/
│   ├── maintained focused suites  standalone, no engine needed
│   └── weather_fx_engine_test.lua engine harness, needs imported data
└── README.md
```

---

## Validation

```sh
# from the mod folder — needs no engine, no ROM, no graphics context
python3 tools/run_all.py --lua            # maintained standalone release gate

# from the repo root — drives the real engine loader headlessly
# When working inside the full Gen1Recomp repository, run that repository
# version's supported mod validation/lint/package commands. This standalone
# Weather FX archive does not ship the engine repository's modkit.
```

The maintained focused suites exercise the catalogue, config/settings
contracts, state authority, AUTO/CYCLE/pinned weather behavior, regional
fronts, time-of-day publication, quality governor, battle mechanics and visual
authority, 2D haze/particles, renderer ownership/fallbacks, audio, BuildingLight,
DEBUG HUD, and gameplay integrations against headless stubs. The focused suites
replace the retired pre-4.18 monolithic test so current behavior is tested
without carrying obsolete expectations in the package.

---

## What is verified, and how

The standalone suite drives every battle hook against a stub battle, which
checks the LOGIC but not the assumptions. The context shapes themselves are
verified by reading the engine source, and 2.5.1 fixed three bugs that only
that reading could have found — including `battle.turn_order` needing a
boolean return rather than a battler, and its context carrying no `battle`
at all.

Confirmed against the engine: `battle.field` exists in vanilla,
`BattleState:onFaint` exists, `Damage.compute` returns
`(damage, { crit, typeMult })` with effectiveness in tenths and 0 for
status moves, `accuracyRoll` returns a boolean, `mon.stats.hp` is max HP,
`curTypes` and `isPlayer` are real battler fields, and `battle.move_used`
carries `user`.

Still unverified in play: nothing in the battle layer has been seen running
against a real ROM by the author. If something misbehaves, `DEBUG HUD`
shows the latched battle weather on the `btl` field.

## Permissions

The manifest declares `engine_internals`. It buys exactly four read-only
requires in `lib/Scene.lua` — `src.core.Game` for the state stack,
`src.battle.BattleState` to recognise a battle, `src.render.TextBox` to
find an open dialog box, and `src.world.Map` for `isOutdoor` — and nothing
is written through any of them. `mod.world` would give the overworld
without the permission, but not the stack top, and "is a menu covering the
world" is the question that keeps rain off the item screen. Every require
is `pcall`'d: on a headless run the modules resolve to `nil`, the scene
reports `hidden`, and the mod draws nothing.

---

## A note on the reference mod

Version 1 was written after reading
[`mrmushrooms11/kanto-first-person`](https://github.com/mrmushrooms11/kanto-first-person),
whose README describes rain with NPC umbrellas, Lavender fog, cloud decks
and a particle system. **That code is not in its published source** — the
repository at tag `firstperson1.8` ships `main.lua` plus the backdrop,
ceiling and jump payloads, and contains no rain, snow, fog or particle
code. So nothing was ported. What was taken from it is the *conventions*:
presentational-only, a clean companion rather than a fork, and a weather
clock that runs on its own rather than on the player's steps. This mod is
standard third-person view throughout and adds no camera of any kind.

## Weather Encounter API

Weather FX publishes a read-only encounter API for companion overlays. It is
intended to keep route encounter displays in sync with the actual Weather FX
rules without making the companion mod responsible for weather logic.

Exports:

- `weatherEncounters(mapId)` / `encounterOverlay(mapId)` — current route
  forecast plus weather-variant entries.
- `weatherPokemon(species)` — species metadata, including types, catch rate,
  stats, moves, evolutions and Weather FX variant metadata when applicable.
- `weatherEncounterAPI` — stable provider object with `route`, `species`,
  `currentWeather` and `enabled`.

Weather variant encounter probability is derived from the route's real slot
weight and the variant's configured substitution chance. A variant is listed
only when its mapped weather is active and its base species is actually found
on that route in the relevant encounter habitat.

Kanto Companion Mobile can consume this provider through its optional
in-memory weather-provider registration points. Weather FX never modifies the
companion's files.
