## Stock GBA safety (important)

ORAS must **not** corrupt Gen3/GBA battle sprites:

- `APPLY TEXTURES` defaults **off**. When on, it uses an additive `Game3.battlePic` overlay only (no permanent `encounters.fronts/backs` rewrite unless explicitly opted in). Body UV atlases are refused.
- `APPLY 3D MESHES` exposes the voxel mesh API for DramaticShapes; it does **not** replace `Game3:drawBattlePic` with Body-UV 2D bakes (that opt-in is `bake2dUi`, off by default).
- Toggle ORAS / textures / meshes **off** → stock GBA returns immediately (snapshot restore + cache clear), no ROM reimport.

# ORAS Models (`oras_models`)

Separate **content / VISUAL** mod for the Pokemon Ruby (Game3) LOVE engine.
It points at **your** Omega Ruby 3DS dump, extracts into a **user-local cache
outside git**, and applies ORAS body textures onto Ruby battle pics when
indexed. **No Nintendo images or models are vendored or committed.**

## Hard rules

- Do **not** download from Spriters Resource / Models Resource.
- Do **not** put Nintendo assets under `assets/` or commit them.
- Cache lives under `%APPDATA%/LOVE/pokemon-love2d/oras_extract/` (override with
  `--cache`). Sandbox-readable copies (JSON only) live under
  `mods/oras_models/.local/` (gitignored):
  - `status.json` — probe/extract status (embeds first **500** textures only)
  - `texture_index.json` — **full** index mirror (~25k entries)
  - `battle_texture_map.json` — slim `pm####` national → front/back path map

## Enable (Raymond)

1. Keep this folder at `mods/oras_models/`.
2. Boot **Ruby** in the launcher.
3. F10 mod manager → enable **ORAS Models**, **or** in `options.lua`:

```lua
modsByVersion = {
  ruby = {
    oras_models = true,
  },
},
```

4. In-mod options (F10 / mod options):
   - **ENABLED** — master switch (default on).
   - **APPLY TEXTURES** — install battle-pic path overrides (default on).
   - **ORAS SOURCE** — path to your dump (defaults to the Desktop decrypted zip).

5. Extract (already done on this machine when `texture_count=25570`):

```bat
python mods\oras_models\extract\extract_oras.py --extract-textures
```

Re-running the script refreshes `.local/texture_index.json` +
`.local/battle_texture_map.json` from the cache (JSON only; never copies PNGs
into the mod tree).

## What should look different in-game

With **ENABLED** + **APPLY TEXTURES** and a fresh Ruby boot:

| Where | What changes |
| --- | --- |
| Wild / trainer battle mons | Front/back pics load ORAS `pm####` **body** UV textures (256×256 atlases), not GBA sprites. Early proof: Torchic / Treecko / Mudkip / Pikachu / starters. |
| Pokedex / Hall of Fame / summary | Same `Game3:battlePic` path — ORAS body sheets when that species has a `pmNNNN_00_Body*` rip. |
| Elite Four / Steven battle entrance | Mugshot opponent art tries ORAS `a/1/6/0/*.png` (512×256) for Sidney…Steven indices (provisional mapping). |

**Honest caveat:** these are 3D mesh body textures, not 2D battle sprites. They
will look like flat texture atlases / odd crops until a real mesh/`drawWorld`
pipeline exists. They prove the ORAS extract cache reaches Game3:battlePic / grabImage.

## Mapping strategy (species id ↔ pm####)

- ORAS texture names: `pmNNNN_FF_BodyA1` / `Body1` / … where **NNNN = national
  dex** (Bulbasaur `pm0001`, Torchic `pm0255`).
- Game3 battle pics key by **internal species id** via
  `data.encounters.fronts[species]` / `backs[species]`
  (`Game3:battlePic`).
- Bridge: `pokemon.byIndex[species].nationalDex` (e.g. Torchic species **280**
  → national **255** → `pm0255`).
- Prefer front: `BodyA1` > `Body1` > `BodyA2` > `BodyB1` > `Body2` (form `00`,
  skip `Nor`/`Mask`/`Env`). Back prefers `BodyB1` then mirrors.

## How apply works (Game3 reality)

1. **Game3:load** now boots `src.mods.Loader` (it previously skipped mods) and
   emits `game.ready`.
2. Mod loads the full index via `.local/texture_index.json` (not the 500-row
   status embed), preferably through `.local/battle_texture_map.json`.
3. Installs a `Game3.battlePic` wrapper + patches `encounters.fronts/backs`
   to **save-dir-relative** paths (`oras_extract/textures/...`) rewritten from
   the absolute AppData index (no PNG copies into `mods/.../assets`).
4. `Game3:grabImage` rewrites save-dir absolutes to relative PhysFS paths and
   io.open-falls-back for other host absolutes. Large body UV sheets are
   fit into the ~64px battle slot when drawn.
5. `mod.content.sprites:patch` is **not** used for battle art — that registry
   is overworld walkers; ORAS_TEX_* ids are not sprite constants.

## Verify

1. Confirm `.local/battle_texture_map.json` exists and lists national `255`
   (Torchic) with front/back paths under `oras_extract\textures\`.
2. Enable the mod for Ruby; boot Ruby; watch the log for
   `ORAS apply [boot]` / `[game.ready]` with non-zero `national front=…`.
3. New game → Birch bag / starter reveal: Torchic front should be an ORAS
   body sheet, not the GBA rip.
4. Or wild battle a mapped species (e.g. Zigzagoon / Poochyena if present in
   the body map).
5. Toggle **APPLY TEXTURES** off and reboot — GBA pics return.


## Mesh material texture binding (BCH units)

ORAS materials expose two texture units. Export picks the **diffuse albedo** via
`extract/bch_mesh.py` `pick_diffuse_texture()` so every national stays correct
(not just Oddish-line special cases):

| Rule | Result |
| --- | --- |
| Never bind DummyTex / Mask / Nor / bare Env | Fall back to the other unit |
| `BodyB*` shaders (CamelCase `BodyB` token; not `BodyBuffron`) with `Body1`+`Body2` | Prefer **Body2** (Gloom petals) |
| `BodyB*` shaders with `BodyB1`(+Mask/Dummy) | Prefer **BodyB1** (Bulbasaur bulb) |
| `Body01` / `Body01_*` (sheet index, not BodyA01) | Prefer **Body2** when present, else Body1 |
| `Petal` / `Flower` / `Blossom` parts + Body1+Body2 | Prefer **Body2** even on BodyVco |
| Eyes / Mouth / Iris / BodyA / Body00 / default | Prefer **unit0** (`*1` sheet) |

`material_shader` is written into each `mesh.json` part. Runtime remaps in
`lib/mesh.lua` and `DRAMATIC_SHAPE/lib/OrasModels.lua` are a safety net for old
caches — they key off **shader / Petal name only** (not mesh names like
`BodyBSkin`, which correctly stay on Body1). **Re-export is the primary fix:**

```bat
python mods\oras_models\extract\extract_oras.py --extract-meshes
```

## Phase-1 3D battle meshes (static posed)

ORAS battles are 3D. This mod extracts **BCH battler meshes** from
`a/0/0/8` (model BCHs, separate from Body texture BCHs) into
`%APPDATA%/LOVE/pokemon-love2d/oras_extract/meshes/`.

**Voxel / DramaticShapes path (preferred):** `lib/mesh.lua` builds real LOVE
3D meshes (Voxel3D vertex format). `Gen2Recomped-DramaticShapes` loads them
via `lib/OrasModels.lua` inside `BattleScene` — same camera / depth buffer as
the arena — and **skips** the flat Gen3 billboard for that side. Log line:
`ORAS mesh HIT … path=voxel_3d`.

**2D bake fallback:** still hooks `Game3:drawBattlePic` to a projected 96px
canvas for menus / non-voxel battles (`path=baked_2d`). That path alone still
looks like a paper cutout in voxel mode — do not rely on it for the arena.

```bat
python mods\oras_models\extract\extract_oras.py --extract-meshes
python mods\oras_models\extract\extract_oras.py --extract-meshes --mesh-smoke
```

- Sidecar: `.local/mesh_index.json` (JSON only; never vendored PNGs/BCH).
- Option **APPLY 3D MESHES** (default on). Falls back to Gen3 sprites if mesh missing.
- Phase-1: **static bind/rest pose**, no skeletal animation, no shiny swap, rough camera.
- RGB8 Body textures need BGR decode (fixed in `bch_tex.py`); re-rip `a/0/0/8` textures if colors look wrong.

Verify: quit LOVE → reboot Ruby → enable ORAS Models → start a battle with Torchic /
Wurmple / Groudon (or starters). Log should show `ORAS meshes [boot]` with
`drawHook=true`.

## Gaps

- Phase-1 static meshes hooked via `drawBattlePic`; no skeletal anim / shadows yet.
- Body textures ≠ faithful battle sprites; shinies still use the same sheet.
- Mugshot `a/1/6/0` → Sidney…Steven index mapping is provisional.
- Overworld NPC / player OW sheets not remapped.
- Gen3 mod API is still thin vs Game/Game2 (no `pokemon.sprite` hook on Game3;
  this mod wraps `battlePic` directly).

## Layout

```
mods/oras_models/
  manifest.json
  mod.card
  main.lua
  README.md
  .gitignore          # .local/, baseroms/, containers
  lib/extract.lua     # status + full index / battle map reads
  lib/apply.lua       # national map + Game3.battlePic / mugshot hooks
  extract/extract_oras.py
  .local/             # gitignored JSON sidecars only
```

## Non-goals

- Shipping or committing any Nintendo-owned bytes.
- Pretending BCH already draws in Game3.
- Using third-party ripped sheets from the internet.