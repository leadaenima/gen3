# Shape Studio

In-game **presentational** voxel shape editor for DRAMATIC_SHAPE.
It never changes collision, scripts, or gameplay — only how voxel mode looks.

## Open / close

- **F8** toggles Shape Studio (voxel pipeline must be on — press **3** first).
- **Esc** closes the studio (does not quit the game).
- OPTIONS row: **SHAPE STUDIO** reminds you of the F8 binding.

While open, player walk input is frozen and clicks do not move the trainer.

## Pick

- **Left-click** a tile in the 3D world to select its map cell.
- **Tab** → sprite mode to select a sprite / NPC / OW object (not Shift-click).
- **Drag** a rectangle of cells to **level** them to the player tile height. **Click** (no drag) selects only.

## Edit

| Control | Action |
|--------|--------|
| Mouse wheel / `[` `]` / Q E | Height (`h`) or sprite `yOff` (±1; Shift-wheel ±8) |
| `-` `=` | Cell visual `zOff` |
| Shift + `-` `=` | Map elevation-band layer offset (Gen3) |
| ← → | Cycle **shape class** (existing TileShape classes) |
| ↑ ↓ | Cycle **art mode** (flat / top / upright / …) |
| **C** | Chromakey eyedropper — click the **green in the 3D view** (fence gaps). Loupe + RGB readout. Autosaved. |
| **T** | Texture eyedropper — with a cell selected, next click copies that cell's metatile **art** onto the selection (Esc/T cancels). Same tileset only. |
| `,` `.` | While a cell is selected, cycle pending tex metatile id (− / +). Wheel does the same in T-mode (or Alt-wheel). |
| **R** | Revert override on the current selection (clears shape **and** `tex`) |
| Ctrl+Z | Undo (session stack) |

## Save scopes

| Key | Scope |
|-----|--------|
| **1** | **This instance** — this map cell, or this object placement only |
| **2** | **All instances** — every cell with this metatile (or tile id), or every sprite on this sheet / graphics id |
| **3** | **Force-save now** — same file; normally unnecessary because edits **autosave** (~0.4s after you stop scrubbing, and on Studio close) |

Edits persist across restart via `data/shape_studio/overrides.lua` in the mod folder. Height scrubbing remeshes in place (no 2D flash) and coalesces disk writes.

## Override keys

Stored in `overrides.lua`:

- `cells["mapId:cx:cy"]` — `{ class, h, art, zOff, tex }`
- `types["ts:<tileset>:meta:<id>"]` or `types["ts:<tileset>:tile:<id>"]` — type-wide shape / tex
- `tex` — `{ tileset, metatile }` (Gen3 16×16 art swap). Applied at mesh UV time only; original map blockdata / collision / scripts unchanged. Instance `cells[..].tex` wins over `types[..].tex`. Cross-tileset swaps are rejected (one atlas per map).
- `sprites["map:<mapId>:obj:<id>"]` — one placement; `sheet:<path>` / `gfx:<id>` — all of that art
- `chromakey["*"]` or per-sheet — `{ {r,g,b,tol}, ... }` (0–255)
- `maps[mapId].layerOffsets[elev]` — visual lift for an elevation band

TileShape / Gen3 resolution consults these **before** shipped `voxel_heights.lua` / behaviour pins. Do **not** rewrite the 8k-line profile for hand tweaks; merge into the profile later only if you want.

## Merge later (optional)

If you want a tweak in the authored profile instead of overrides, copy the type key’s `class`/`h`/`art` into the right tileset group in `data/voxel_heights.lua` (or behaviour row in `data/gen3_shapes.lua`), then delete that entry from `overrides.lua` and bump cache again.

## Mobile Map Studio (Android / POKEPORT_TOUCH)

On Android/iOS (or desktop with `POKEPORT_TOUCH=1`):

- Tap **MAP EDIT** (top-right) — do not rely on F8 alone.
- Large toolbar: Select, H+/H−, Level, Class, Art, Texture, Chroma, Save, Save all, Export, Import, Undo, Close.
- Virtual d-pad is suppressed while the studio is open.
- Saves go to the LOVE **save directory** (`shape_studio/overrides.lua`), merged on boot.
- **Export** writes `shape_studio/export/mobile_YYYYMMDD_HHMMSS.lua` for Desktop merge.

See **MOBILE_MERGE.md** for pull + Import/Merge steps. Desktop: **I** / panel Import/Merge, or `tools/merge_mobile_overrides.lua`.
