# AGENTS

Guidance for automated assistants working on **Weather FX**.
Humans: see README.md. Assistants: read this before editing.

You are looking at **Weather FX**, a weather mod for Pokémon Gen1Recomp. It
runs on Red, Blue, Yellow **and Gold**, which is the source of most of the
non-obvious problems in it.

Before you change anything, two minutes here will save you a wasted release.

---

## 0. Three voxel hosts — all first-class

**Every 3D-path change must work on all of these** (not one host at a time):

| Host mod id | Typical game |
|-------------|--------------|
| `DRAMATIC_SHAPE` | Gen 1 (Dramatic Shape 1.9.x) |
| `DRAMALESS_SHAPE` | Gen 1 (+ some Gen 2 setups) |
| `potato_voxel` / `POTATO_VOXEL` | Gen 1 / Gen 2 |
| `STADIUM2_OVERWORLD_MODELS` | Gold/Silver (Gen2-3D-Sprites) |

Rules:

1. Prefer **shared** code in `lib/DramalessAtmos.lua` (name is historical; it is the multi-host bridge).
2. Host differences go behind small branches (`Voxel` vs `VoxelState`, `Sky.paint` arity, etc.) — never a separate fork of the whole atmos stack.
3. **Do not edit** those mods on disk. Only in-memory wraps via `exports.lib`.
4. After any 3D change: reason about all three hosts, and keep **WX PRESENT → 2D** fail-closed if a host is missing.
5. DEBUG `v3:` should report which host attached (`full-atmos:<id>`).


## 1. There are tools. Run them first.

```bash
cd weather_fx                      # the mod root, where this file is

python3 tools/run_all.py           # everything: structure, contracts, tests
python3 tools/run_all.py --lua     # ...including the Lua suite, if lua/luajit exists
```

`tools/README.md` lists all eight. The ones you will actually reach for:

| When | Run |
|---|---|
| Before you touch anything | `python3 tools/run_all.py` |
| After any edit | `python3 tools/edit_guard.py` |
| "Where does X live?" | `python3 tools/mod_map.py`, `tools/symbol_index.py` |
| The user pastes a DEBUG HUD line | `python3 tools/runtime_hints.py "<the line>"` |

That last one matters more than it looks. The mod prints its own state on
screen — `wx:`, `v3:`, `btl:`, `draw:`, `map:`, `terr:` — and each field names
the exact gate that is closed. If a user says "the weather isn't working", the
fastest correct move is to ask for that line and decode it, **not** to start
reading source.

### The Lua suites

```bash
# from the ENGINE repo root, with the mod in mods/:
POKEPORT_DATA_DIR=<data> luajit mods/weather_fx/tests/weather_fx_engine_test.lua
WEATHER_FX_GEN=2 POKEPORT_DATA_DIR=<data> luajit .../weather_fx_engine_test.lua
```

`WEATHER_FX_GEN=1|2` picks which generation to load as. **Run both.** Several
bugs only existed on one.

One test fails on purpose (`NORMAL is a share you would actually notice`). It
is a balance question for the mod's owner, not a defect. Do not "fix" it by
changing the threshold.

---

## 2. Five ways this codebase has actually broken

Every one of these shipped. None of them errored. That is the pattern: **in
this engine, wrong things fail silently.**

**Engine modules must be required at CALL time, never file scope.** A module
captured at the top of a file gives you the Gen 1 implementation *permanently*,
even on a Gold boot. Proven: `Map.isOutdoor({environment="ROUTE"})` returns
`false` when captured early and `true` when captured late — different tables.
This is what made weather invisible on Gold for three releases.

**The two generations describe the world differently.** Gen 1 maps have
`tileset`; Gold maps have `environment` (ROUTE/TOWN/INDOOR/CAVE/DUNGEON/GATE).
Gen 1's overworld carries an `isOverworld` marker on a state stack; Gold's does
not. Test for the *thing*, not the shape you remember.

**`love` is sandboxed.** `filesystem`, `thread`, `system`, `event` all throw —
and they throw on the **index**, so `if love and love.system then` does not
protect you; asking is the crash. One such call in a per-frame path blanks the
entire screen. `tools/test_love_sandbox.py` walks every shipped runtime Lua file
automatically, so new modules are covered without a manual list.

**Six registries have no Gen 2 home:** `rulesets`, `transitions`, `field`,
`text_pointers`, `link_fields`, `map_scripts`. Writes are dropped *and*
reported as boot errors. Gate them on generation.

**Tests here lie in a specific way.** Fixtures encode assumptions. A test that
hands the mod a Gen-1-shaped map can only ever produce the Gen 1 answer — that
is why 1000+ passing assertions never caught the Gold bug. A stub written from
documentation rather than a live load proves nothing.

> **So: after every fix, break it again on purpose and confirm the suite
> fails.** Four decorative tests in this repo were found exactly that way. If
> reverting your fix leaves the suite green, you have not tested your fix.

---

## 3. House style

- Comments explain **why**, especially why an obvious alternative was rejected.
  There is a lot of hard-won reasoning in this code; do not strip it.
- Every non-reference behaviour is labelled as a house rule and gets its own
  config switch. Do not quietly change what the games do.
- `lib/voxel_atmos/` and `compat/kanto/` are **third-party MIT code** by Campo
  (`1-Camp0-1`). The licence and notice live beside them. If you move, copy or
  re-vendor those files, the licence goes with them.
- The mod must degrade silently when a companion mod is absent, and say *why*
  in the debug readout when it declines.

---

## 4. Before you say you are done

```bash
python3 tools/run_all.py --lua
# both generations of the engine harness
python3 tools/modkit.py validate mods/weather_fx --strict
python3 tools/modkit.py gen2check mods/weather_fx --strict
python3 tools/modkit.py lint mods/weather_fx
python3 tools/modkit.py pack mods/weather_fx -o out.modpkg
```

And the honest one: **none of this can see the screen.** Every visual bug in
this mod's history was found by a human playing it, not by a test. If your
change is a *look* — fog density, particle scale, colour — say plainly that it
needs eyes on it, and give the user the specific thing to look at.
