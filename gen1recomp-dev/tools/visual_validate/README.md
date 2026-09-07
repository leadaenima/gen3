# visual_validate — stock GBA vs LÖVE capture path

Reusable tooling to grab reference frames from **stock Pokémon Ruby (GBA)** and
matching frames from the **LÖVE port**. This folder does **not** assert that
naming/title parity is fixed; it only documents how to capture and compare.

## Paths on this machine

| Role | Path |
| --- | --- |
| PORT | `C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev` |
| Ruby ROM | `PORT\misc\Pokemon - Ruby Version (USA).gba` (also Desktop copy) |
| mGBA 0.10.5 | `C:\Users\Feces\Desktop\mGBA-0.10.5-win64\mGBA.exe` |
| mGBA scripts | `...\mGBA-0.10.5-win64\scripts\` (`pokemon.lua`, sockets) |
| Libretro core | `PORT\tools\gba_oracle\vendor\mgba_libretro.dll` |
| LÖVE | `C:\Program Files\LOVE\love.exe` |
| VGBA | `C:\Users\Feces\Desktop\VGBA64-W\VGBA.exe` (GUI; no useful shot CLI) |
| Output | `PORT\tmp\visual_validate\stock_*.png` / `love_*.png` |

## 1) Stock GBA capture (preferred: headless libretro)

Released **mGBA 0.10.5** exposes Lua via **Tools → Scripting…**
(`emu:screenshot(path)`), but **no reliable `--script` / headless CLI** for
unattended shots. Automated capture uses the existing **gba_oracle** libretro
wrapper (same emulator as a DLL).

From PORT:

```bat
cd /d "C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev"

python tools\visual_validate\capture_stock.py --scene boot --out tmp\visual_validate\stock_boot.png

python tools\visual_validate\capture_stock.py --scene title --out tmp\visual_validate\stock_title.png

python tools\visual_validate\capture_stock.py --scene naming-path --out-dir tmp\visual_validate --prefix stock_naming

REM equivalent one-shot via oracle directly:
python tools\gba_oracle\snapshot.py "misc\Pokemon - Ruby Version (USA).gba" --advance 900 --shot tmp\visual_validate\stock_oracle.png
```

Also useful: `python tools\gba_oracle\newgame.py "misc\Pokemon - Ruby Version (USA).gba" --shots tmp\visual_validate\newgame_seq`

### mGBA GUI Lua (manual / interactive)

1. Run `mGBA.exe`, load the Ruby ROM.
2. **Tools → Scripting…** → load `tools\visual_validate\mgba_screenshot.lua`.
3. Navigate to the frame; in the console: `capture_now([[C:\...\tmp\visual_validate\stock_mgba.png]])`.

`mgba-sdl.exe` / `mGBA.exe --help` on 0.10.5 do not provide a documented
unattended screenshot flag usable from this tooling path.

### VGBA

`VGBA.exe` is GUI-oriented; passing `/?` attempted to open a cartridge named
`/?` and failed. No screenshot CLI found — skip for automation.

## 2) LÖVE port capture

### A. Driver + `Game.capturePath` (pixel buffer, preferred)

`main.lua` writes PNG when `Game.capturePath` is set (via
`love.graphics.captureScreenshot`). Drivers live under `tests\drivers\`;
helpers in `tests\drivers\util.lua` (`U.shot`).

```bat
cd /d "C:\Users\Feces\Desktop\pkmn gen1recomp\gen1recomp-dev"
set POKEPORT_GAME=ruby
set POKEPORT_DRIVER=%CD%\tools\visual_validate\love_capture_driver.lua
set POKEPORT_SHOT_DIR=%CD%\tmp\visual_validate
set POKEPORT_SHOT_NAME=love_frame
set POKEPORT_SHOT_WAIT=180
set POKEPORT_SPEED=8
"C:\Program Files\LOVE\love.exe" --console .
```

Extend `love_capture_driver.lua` (or copy a `tests\drivers\*.lua` pattern) to
press inputs until the desired scene, then set `game.capturePath`.

Launcher-only auto-quit shot (not in-game):

```bat
set POKEPORT_LAUNCHER_SHOT=%CD%\tmp\visual_validate\love_launcher.png
set POKEPORT_WIN=1024x768
"C:\Program Files\LOVE\love.exe" --console .
```

### B. Interactive

```bat
"C:\Program Files\LOVE\love.exe" --console .
```

Reach the scene manually. Touch-skin maps a `screenshot` action
(`src\core\TouchSkin.lua`). There is no dedicated F12 handler in `main.lua`;
use a driver hook or OS capture if needed (OS capture may include chrome).

## 3) Compare

```bat
python tools\compare_shots.py tmp\visual_validate\golden tmp\visual_validate\shots --diff-dir tmp\visual_validate\diffs
```

## Notes

- Stock shots from libretro are **240×160** RGB from the core framebuffer.
- LÖVE shots are host-window sized unless the driver/viewport is constrained —
  compare carefully (scale or letterbox) before pixel-diffing.
- Do not treat `naming-path` sequence filenames as proof of a specific UI state;
  open the PNGs and pick the reference you need.


## Captured on this machine (2026-09-06)

Headless libretro captures written under `tmp\visual_validate\`:

| File | What it shows (inspect; not a pass/fail claim) |
| --- | --- |
| `stock_boot.png` | Near-blank boot frame after reset |
| `stock_title.png` | Pokémon logo on black (title sequence) |
| `stock_naming_p*.png` | Intro path samples (Birch speech / gender prompt / …) |
| `stock_naminglong_*.png` | Longer mash; by ~300 presses already in moving truck |

**Naming UI caveat:** mashing A/START accepts defaults and often **skips** a stable
naming-keyboard frame. For a naming reference, use interactive mGBA +
`mgba_screenshot.lua` `capture_now(...)`, or write a slower driver that stops
when the naming UI is up (RAM/callback), rather than relying on `--scene naming-path`.

### mGBA 0.10.5 CLI (verified)

`mgba-sdl.exe --help` exposes bios/cheats/config/gdb/log/savestate/patch/frameskip/scale —
**no `--script`, no screenshot flag**. Use GUI Scripting or libretro tooling above.
