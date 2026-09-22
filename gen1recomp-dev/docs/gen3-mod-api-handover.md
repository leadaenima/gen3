# Handover: finishing the Gen 3 (Ruby) mod API

You are continuing work that makes the community's `gen1recomp` mods run on the
**Gen 3 / Ruby** arm of this engine (`src/core/Game3.lua`). Read this whole file
before writing code. It is short on purpose; the traps in it cost real bugs.

---

## 1. The one thing to understand first

Mods do not fail on Ruby because they fail to *load*. They load fine. They fail
because **Game3 never calls the hook names they wrap or emits the events they
listen for.**

The engine's mod API is a set of named hooks (`Runtime.call`) and events
(`Runtime.emit`). Gen 1 fires them from `src/core/Game.lua`,
`src/battle/BattleState.lua`, `src/world/OverworldController.lua`. Gen 2 fires
them from its own `gen2/` modules. **A Ruby boot runs neither.**

Measured across the nine community mods forced onto Ruby: they wrap **27
distinct hook names** and listen for **17 events** between them. Before this
work a Ruby boot reached **one hook** and about **five events**. The mods
loaded, registered, and sat inert.

Registries and compat facades stop mods *dying*. Hooks and events are what make
them *work*. Your job is the second half.

---

## 2. Current state

Refresh date: 2026-09-21 (phase-4 object-model / Screens / music.volume). Counts are against the nine
community mods' **27 hooks / 17 events**. Sites verified in
`src/core/Game3.lua` unless noted.

### Hooks — 30 wired in Game3 (incl. phase-2)

Phase-2 additions: `exp.gain`, `pokemon.sprite`, `render.compose`,
`render.letterbox`, `map.palette`, `catch.rate`, `held_item.trigger`,
`script.command` (conditional). Event: `map.reloaded`.

| Wired | Where (approx) |
|---|---|
| `battle.accuracy` | `Game3:accuracyRoll` |
| `battle.catch_exp` | catch-success exp gate |
| `battle.charge_required` | charge-move setup (`needsCharge`) |
| `battle.damage` | `modBattleDamage` → dealDamage paths (before Endure) |
| `battle.enemy_action` | `Game3:pickEnemyMove` (AI pick) |
| `battle.exp_award` | `awardExp` continuation |
| `battle.overlay` | end of `Game3:drawBattle` (draw-only no-op vanilla) |
| `battle.run` | `Game3:tryRunFromBattle` |
| `battle.turn_order` | `Game3:turnOrder` |
| `catch.rate` | `Game3:tryCatch` after species/safari rate, before shake math |
| `encounter.fishing` | fishing encounter path |
| `encounter.roll` | `Game3:startWildFrom` |
| `exp.gain` | `Game3:giveMonExp` after cart multipliers, before level-up |
| `fieldmove.eligibility` | field-move gate |
| `held_item.trigger` | `Game3:holdEffectOf` (continuation; trigger="check") |
| `input.step` | `Game3:logicStep`, before `Input:step()` |
| `map.palette` | `Game3:mapPaletteName` (name only; true-colour art not remapped) |
| `movement.collision` | `Game3:canStep` (wraps `canStepVanilla`) |
| `movement.speed` | `Game3:walkPeriod` (Trap A units) |
| `music.select` | BGM select path |
| `music.volume` | `Game3:applyMusicVolume` (per-frame from `updateMusic` + after `playSong`) |
| `pokemon.sprite` | `Game3:battlePic` after path resolve, before cache/load |
| `render.compose` | end of `Game3:draw` after `GameViewport.finish` (boolean takeover) |
| `render.hud` | battle/overworld HUD draw (skipped when compose handled) |
| `render.letterbox` | same post-finish seam; void bars around 240×160 |
| `save.write` | save serialise path |
| `script.command` | conditional wrap of Gen3Script per-op entry when exposed |
| `ui.list_menu` | list-menu open path |
| `ui.party.submenu` | `Game3:partyActions` + `Game3:stepPartyAction` (Trap B/D) |
| `ui.start_menu.items` | `Game3:startMenuItems` + A-press dispatch (Trap B) |
| `world.tod` | TOD query (+ `world.tod_changed` emit) |

### Events — 22 emitted from Game3 (+ block_replaced via Runtime)

`battle.ended`, `battle.move_used`, `battle.started`, `battle.turn_ended`, `game.ready`, `map.entered`, `map.exited`, `map.reloaded`, `music.started`, `pokemon.before_give`, `pokemon.caught`, `save.created`, `save.loaded`, `save.writing`, `save.saving`, `save.saved`, `script.started`, `script.ended`, `world.blacked_out`, `world.block_replaced`, `world.stepped`, `world.tod_changed`.

`map.reloaded` fires from `restoreMapLayout` / `setMapLayoutIndex` only
(reason `"layout"`), **not** from `enterMap`.

`battle.started` emits from `Game3BattleTransition.launchBattleWithEntrance`
(`enter()`), with Ruby's mon-as-battler shape (`enemy.species`, never
`enemy.mon.species`). `battle.ended` emits from `Game3:endBattle` (and
Gen3Compat's finish bridge as a belt-and-braces).

### Phase-2 notes / deliberate limits

- **`render.compose` / `render.letterbox`:** Real post-`GameViewport.finish`
  seam shared by zoomed-overworld and canvas letterbox paths. Compose ctx
  omits Gen 1's `worldCanvas`/`uiCanvas` (Ruby has no dual-canvas compositor);
  free_fly / wild_skies draw with `love.graphics` using the viewport rect.
- **`map.reloaded`:** Emitted only on in-place layout reload. Emitting from
  `enterMap` would lie about the reason (still documented there).
- **`map.palette`:** Name hook only — Ruby tiles are true-colour, so nothing
  remaps pixels from the returned name; qol can still key off it.
- **`script.command`:** Optional wrap of Gen3Script per-op entry
  (`runCommand` / `execCommand` / `dispatch` / `runOp` / `execOp`). If none
  exists, the runner is untouched (documented, not a silent fake).
- **`held_item.trigger`:** Single read-wrap on `holdEffectOf` with
  `trigger="check"`. Battle timing variants are not branched yet.

### Phase-3 notes (facades + exp_share contract)

- **`battle.exp_award` / exp_share:** `ctx.participants` is a **count** (not a
  list — the mons are `alive` / `participantMons`). `ctx.applyShare(mon, split,
  announce)` takes a **divisor of `calculated`** (Gen 1 / exp_share), not an
  absolute XP amount. The battle bag is aliased with `.game` / `.party` /
  `.save` / `:sayNext` so `optionsOf(ctx.battle)` and `partyOf` work on Ruby.
- **`Gen3Compat` Screens (phase-3):** `push` backed `StartMenu`, `Option`/
  `Options`/`OptionsMenu`, `Party`/`PartyMenu`, `Bag`/`BagMenu`.
- **`Gen3Compat` Map (phase-3):** `defPassable` / `isPassable` → live
  `Game3:canStep`.

### Phase-4 notes (Screens / music.volume / Map+NPC stubs)

- **`Screens.push` custom menus:** Registered factories (`Screens.register` or
  `game.data.screens`) open via **`Game3:openModScreen`** — the same
  StateStack + 160×144 letterbox rails as the mod manager. That unblocks
  `qol_toggles`' `QolTogglesMenu` (toggle rows over `save.options`) without a
  full Gen 1 StateStack clone. `Screens.pop` forwards to `game.stack:pop`.
  Unknown ids still refuse once (logged).
- **`music.volume`:** `Game3:applyMusicVolume` runs from `updateMusic` every
  VBlank while the hook is wrapped, and once after `playSong`. Contract matches
  Gen 1 `Music.applyVolume`: absolute volume `0.7 * musicVol/7`, ctx carries
  `song` / `mapId` / `x` / `y` / `tod` / `fading` / `optionScale`. Prefers
  `Mp2kAudio.setVolume(float)`; falls back to discrete `setVolumeLevel(0–7)`
  (lossy for continuous muffling — Desktop Mp2k should expose float setVolume
  when possible).
- **`Gen3Compat` Map:** `new` / `blockAt` / `tileAt` / `isWalkableCell` /
  `isWaterCell` / `inBounds` / soft `setBlock`. Live path uses
  `Game3:modMapView` (metatile-backed). Soft stub when unbound so requires
  never throw. **Not** a Gen 1 block-table engine.
- **`Gen3Compat` NPC:** soft `NPC.new` stub (cellX/cellY/facing) — prevents
  require crashes only; Ruby object-events stay on Game3ModWorld actor views.
- **Events added:** `save.saving` + `save.saved` (alongside existing
  `save.writing`), `script.started` / `script.ended` (outermost
  beginScriptRun / endScriptRun). **`game.quitting` still not emitted** — no
  obvious Ruby quit call site on the box tree (document for a later pass).
- **OPTION row activate/step:** still owned by Desktop `Game3Boot.lua` (do not
  overwrite). Phase-4 only makes `Screens.push("QolTogglesMenu")` succeed once
  activate fires.

### Phase-4 community-mod scorecard

Smoke against installed AppData/Desktop mods. Status is **works** / **partial**
/ **still blocked** for *Ruby gameplay effect*, not merely load success.

| Mod | Status | Hooks/events used | Why |
|---|---|---|---|
| `exp_share` | **works** (expected) | `ui.options.rows`, `battle.exp_award`; reads `game.save.options` / `battle.game.save` | Award contract + battle aliases + OPTION rows wired. Verify in-battle once on Desktop. |
| `autosave_timer` | **partial** | `input.step`; `game.ready`, `save.loaded`, `save.writing`/`saving`/`saved`, `battle.started`/`ended`; `game:writeSave()`, `game.stack:push(TextBox)` | Timer + battle skip + save events fire. Toast still needs `mod.ui.TextBox` / stack — may no-op on Ruby; silent save should land. |
| `surround_audio` | **partial** | `ui.options.rows`, `music.started`, Input M / Select+R; chip_worker pan (Gen1 ChipAudio) | SOUND row + music.started work. **Gen1 chip_worker / love.thread pan path does not apply to Mp2k** — stereo split remains Gen1-only. `music.volume` is now callable for muffling-style wraps but this mod does not use it. |
| `johto_radar` | **partial** | likely `ui.start_menu.items`, `render.hud`, `input.step` (cf. dex_radar) | HUD/start-menu seams exist. Gen 3 encounter tables / Kanto map ids may leave the radar empty. |
| `hm_anywhere_gen2` | **partial** | `fieldmove.eligibility` (+ Gen2 badge tables) | Hook fires; Hoenn badges / HM item ids differ — eligibility answers may be wrong. |
| `qol_toggles` | **partial → nearly works** | many wired hooks + `ui.options.rows` + `Screens.push("QolTogglesMenu")` + `save.saving`/`saved` + `script.started`/`ended` | Custom menu opens via openModScreen. Wired toggles run. Retest OPTIONS → QOL TOGGLES on Desktop (needs Boot activate/step). `game.quitting` still missing. |
| `free_fly` | **partial** | `ui.party.submenu`, `fieldmove.eligibility`, `render.compose` / `render.letterbox` | Menu/compose seams exist. Take-off commands / Kanto `map_scripts` / voxel provider still Gen1-shaped. |
| `wild_skies` | **partial** | `render.compose`, `render.letterbox`, sky assets | Compose seam exists; sky art / camera assumptions are Gen1. |
| `weather_fx` | **partial (load further)** | Map block / voxel atmos / OverworldController wraps | Soft Map.new/blockAt + NPC stub prevent hard require fails. Full Gen1 block edits / voxel atmos host still absent — FX likely limited or no-op. |
| `overworld_wild_spawns` | **still blocked (by design)** | Map/NPC spawn tables, overworld draw; **GameCompat only Gen1+Gen2** | Mod's own `GameCompat.generation` returns nil on Ruby (`games: ["gen1","gen2"]`) and skips encounter hooks. Engine façades cannot fix a generation gate inside the mod. |

Box suite after this batch: `luajit tests/engine/gen3_mod_hooks_test.lua` →
**446 passed, 0 failed** (source + behavioral where Game3 loads).

## 3. How to wire one

Three helpers live near the **top** of `src/core/Game3.lua` (around line 310):

```lua
local function modBus()   -- the Runtime, or nil when no loader ran
local function modCall(name, vanilla, ...)   -- a hook; returns `vanilla` if unwrapped
local function modEmit(name, payload)        -- an event; silent if nobody listens
```

Use them. They already handle "no mods loaded" (headless, the importer, test
fixtures) by doing nothing.

**Hook:**
```lua
local answer = modCall("some.hook", vanillaValue, arg1, arg2)
```
`vanillaValue` is what the engine would have answered. A wrapper receives it via
`next(...)` and may pass it through, replace it, or return nil.

**Event:**
```lua
modEmit("some.event", { field = value })
```

### ⚠ A `local` must be declared ABOVE every function that uses it

Lua binds upvalues at **definition** time. The first version of these helpers
was declared halfway down this 2 MB file, so every function above them saw
`modEmit` as a **nil global** and `Game3:enterMap` killed the boot on new game.
If you add a helper, put it at the top. `tests/engine/gen3_mod_hooks_test.lua`
has a source check that enforces this — keep it passing.

---

## 4. The traps that actually bit (read these)

Every hook has a Gen 1 contract. **Do not assume it maps straight onto Ruby.**
Two of the seven wired hooks needed conversion at the boundary, and both were
silent failures — nothing crashed, the behaviour was just wrong.

### Trap A — units differ (`movement.speed`)

Gen 1 trades in **frames per cell**. Ruby's `walkPeriod` is **seconds**
(`WALK_PERIOD = 16/60`). Copying Gen 1's clamp `math.max(1, math.floor(n))`
turned `0.267 s` into `1 s` — a 4× slowdown of every step in the game.

The fix is to convert at the boundary: seconds → frames out, frames → seconds
back, clamp at one frame. **Check the units of anything numeric before wiring
it.**

### Trap B — record shapes differ (`ui.start_menu.items`, `ui.party.submenu`)

Gen 1's menu rows are **records**: `{ label = "HM", onSelect = fn }`. A real mod
reads `item.label` on every row and inserts a record of its own. **Ruby's rows
are bare strings**, drawn and dispatched by name.

Handing Ruby's strings to the hook puts a **table into a list Ruby draws as
text**. The fix: records out, strings back, and keep the row's `onSelect`
somewhere the input handler can find it (`self.modStartMenuActions`,
`self.modPartyActions`) — otherwise the mod's row appears on the menu and does
nothing when chosen.

Both are already done; `ui.list_menu` follows the same pattern.

### Trap C — Ruby's battler IS the mon (`battle.started` and the whole battle family)

Gen 1 wraps a mon in a battler, so it reads `battle.enemy.mon.species`. **Ruby's
`battle.enemy` is the mon itself** — `battle.enemy.species`. Reading one level
too deep reports `nil` for every fight and nothing errors.

This applies to every `battle.*` hook (all wired in this phase too).

### Trap D — context fields a mod branches on

`ui.party.submenu` is **also the battle switch menu**. `free_fly` refuses to
offer a take-off when `ctx.battle` is set. A ctx missing that field makes every
mod think the player is standing safely in the overworld. Pass the full
context, not just the parts that look needed.

---

## 5. Do NOT build these

Checked and deliberately skipped — building them is wasted work:

- **`map_scripts` and `commands` registries.** Every `map_scripts` id the mods
  register is a **Kanto map name** (`PALLET_TOWN`, `VERMILION_CITY`,
  `GAME_CORNER`) — zero Gen 3 ids — and all three command verbs are free_fly's,
  invoked from its Pallet Town script. The consumer would resolve nothing.
- **`sfx` registry.** Ruby has no `audio.sfx`. Its sound effects are **numbered
  MP2K tracks** played by `Game3:playSe` out of `audio.songs`. `music` is the
  route that means anything; `sfx` stays refused.

---

## 6. `battle.damage` — wired (phase 1)

Gen 1 hooks a clean `Damage.compute(ruleset, user, target, move, opts)` and
expects `(dmg, { crit, typeMult })`.

Ruby seam: local helper **`modBattleDamage`** (~line 38780) called from:

- main `dealDamage` formula path — **after** the formula, **before** Endure /
  Focus Band / HP write (and before the `dryRun` early-return)
- level-damage and endeavor early returns
- `applySetDamage`

Contract at the boundary (Trap C): `ctx.user` / `ctx.target` are the Ruby
mons themselves (`user.species`, not `user.mon.species`). `modCall` packs
`pcall` results so the multi-return survives. Temporary `attacker.isPlayer`
is set where Gen 1-style mods branch on it.

`Game3.damage(level, power, …)` stays a pure static helper and is **not** a
mod seam.

---

## 7. Verifying — do not skip this

A hook that is wrapped but never called looks identical to one that works.
Every claim below must be measured, not assumed.

### The harness

Both engines take a scripted driver. **Never run against the player's save
identity** (`pokemon-love2d`) — use the sandbox `perfmap`:

```bash
cd "97 - Copy/gen1recomp-dev"
SHOT_OUT=/tmp/out.png POKEPORT_DRIVER=/path/to/driver.lua \
  POKEPORT_IDENTITY=perfmap POKEPORT_TOUCH=0 \
  POKEPORT_VERSION=ruby POKEPORT_GAME=ruby \
  "/c/Program Files/LOVE/lovec.exe" .
```

A driver is `return function(game) ... end`. It can call Game3 directly,
press buttons via `game.input:sourcePress(btn, "drv")`, and read
`game.mods.exports.<modid>`.

### The pattern that works

Write a tiny probe mod under
`%APPDATA%/LOVE/perfmap/mods/<id>/` with `games: ["ruby"]`, wrap the hook, and
record what it saw in `mod.exports`. Then assert from the driver that the hook
fired, that the payload carried the right fields, and that **replacing** and
**suppressing** both take effect. Pass-through alone proves nothing.

### The nine real mods

They are installed in `perfmap/mods/` and forced onto Ruby via
`perfmap/options.lua` → `modsGen2 = { ["<id>"] = { ["ruby"] = true } }`. That
override already exists and is honoured for any generation despite the legacy
`gen2` naming. Baseline to keep green: **11 mods load, zero `[error]` lines.**

### Tests

```bash
luajit tests/engine/gen3_mod_hooks_test.lua      # the hook/event contracts
luajit tests/run_engine.lua                      # full tier
luajit tests/mod_graphics_tests.lua
luajit tests/mod_runtime_tests.lua
```

`tests/engine/mew_dock_private_artifact_gate.lua` fails because this folder is
not a git checkout. That failure is **pre-existing and expected** — everything
else must pass.

### Mutation-test every assertion you write

Break the code on purpose and confirm the suite goes red. Three separate
assertions in this work passed against broken code:

1. A check comparing a declaration position against a "use" its own regex
   matched in the declaration line.
2. A party-menu test that called the stored handler **directly**, so swapping
   the engine's own `(mon, game)` argument order went undetected.
3. A `canFly` fixture that left an indoor map set, so deleting the badge check
   entirely still passed — **isolate one gate per case**.

If a mutation does not turn the suite red, the test is decoration.

---

## 8. House rules

- **Never bake decomp art into the repo.** Extract from the ROM at import time.
- **Don't build an APK** unless asked.
- Work in the `perfmap` sandbox; leave the player's `pokemon-love2d` identity
  alone.
- Match the surrounding comment style: say *why*, name the failure the code
  prevents.
