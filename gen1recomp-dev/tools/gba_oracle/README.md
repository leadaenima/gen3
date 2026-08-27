# GBA oracle

Runs the real Ruby cart headlessly and reads its RAM, so the Lua engine
can be checked against hardware instead of against a human reading of
pokeruby.

The question this answers is "what is the game actually supposed to do
here?" — and it answers it in the engine's own vocabulary: set flags,
script vars, map, position, party.

## Why a libretro core

mGBA is the accuracy reference, but the released build (0.10.5) has no
`--script` flag — script autorun is master-only — so it cannot be driven
unattended, and building master needs a C toolchain. The libretro core is
the same emulator as a plain DLL, and Python's `ctypes` can drive it with
no build step and no GUI. IodineGBA would also work but needs a JS
runtime.

## Setup

Fetch the core (about 3 MB, not committed):

```bash
mkdir -p tools/gba_oracle/vendor
curl -sL -o /tmp/core.zip \
  https://buildbot.libretro.com/nightly/windows/x86_64/latest/mgba_libretro.dll.zip
unzip -o /tmp/core.zip -d tools/gba_oracle/vendor
```

On Windows PowerShell, `Expand-Archive` replaces `unzip`. For Linux or
macOS use the matching `latest/<platform>/mgba_libretro.*.zip` and pass
the resulting path as `Core(dll=...)`.

Flag and var names come from a pokeruby checkout, which is optional —
without one the reports fall back to bare numbers. Set `POKERUBY` to
point at it, or leave it beside the project on the Desktop.

No BIOS is needed; the core's HLE BIOS boots Ruby fine.

## Use

Start a new game and checkpoint the first playable moment. This drives
the intro from RAM state rather than frame counts, so it stops when it is
genuinely in the world:

```bash
python tools/gba_oracle/newgame.py "Pokemon - Ruby Version (USA).gba"
```

Ask what a scene changes — the output is the specification for
implementing it:

```bash
python tools/gba_oracle/snapshot.py "Pokemon - Ruby Version (USA).gba" \
    --state tools/gba_oracle/states/newgame.state \
    --advance 1500 --keys down,left,down,right,a --delta
```

```
== what the cart changed (14 differences)
   location.mapGroup: 25 vs 0
   location.mapNum: 40 vs 9
   FLAG_HIDE_MAY_MOM_DOWNSTAIRS (0x2F7): SET
   FLAG_HIDE_BRENDAN_UPSTAIRS (0x2F8): SET
   FLAG_HIDE_MOVING_TRUCK_MAY (0x2FA): SET
   FLAG_HIDE_BRENDAN_MOM (0x310): SET
   VAR_LITTLEROOT_INTRO_STATE (0x4092): 0 vs 1
```

Check that the engine's special ids name the functions it thinks they do:

```bash
python tools/gba_oracle/check_specials.py
```

Diff a cart snapshot against Game3's NEW GAME constants (hide flags, TV watch,
size records, truck dummy-warp coords):

```bash
python tools/gba_oracle/compare_engine.py --json %TEMP%/ruby_newgame.json
python tools/gba_oracle/compare_engine.py "Pokemon - Ruby Version (USA).gba" \
    --state tools/gba_oracle/states/newgame.state
```

## Layout

| File | What it does |
| --- | --- |
| `libretro.py` | ctypes wrapper: load, run, input, memory, savestates |
| `ruby.py` | Reads SaveBlock1/SaveBlock2 into a snapshot; diffs two |
| `names.py` | Flag, var and special names from pokeruby |
| `newgame.py` | Boots, starts a new game, writes a checkpoint savestate |
| `snapshot.py` | Dumps state, or the delta a scene produces |
| `check_specials.py` | Cross-checks `Game3.SPECIAL_*` against `gSpecials` |
| `compare_engine.py` | Diffs a cart snapshot against Game3 NEW GAME inits |

## Things worth knowing

`SaveBlock1.pos` only updates on a map transition, not on every step. It
is the right field for scene-level comparison and the wrong one for
per-step movement; the live position lives in `gObjectEvents[0]` in IWRAM.

The core publishes its memory map from `retro_reset`, not from
`retro_load_game`, so `libretro.py` resets after loading. Skipping that
leaves only `RETRO_MEMORY_SYSTEM_RAM`, which for this core is IWRAM — and
reading save-block offsets out of IWRAM produces confident nonsense
rather than an error, so the wrapper refuses to run without a real EWRAM
mapping.

This is a developer tool, not a test: it needs a cart on disk, and the
suites stay ROM-free.
