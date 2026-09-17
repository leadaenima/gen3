# ORAS PBJ / PKj layout

Companion bins sit beside each battler model BCH under `garc_unpacked/a/0/0/8/`.

| Offset from model N | Role |
|---|---|
| N.bch | Mesh / skeleton bind pose |
| N+2.bch | Normal albedo textures |
| N+3.bch | Shiny albedo textures |
| N+4.bin (PT) | Material / color variant tables (`BodyA00`, `BodyAVco*`) |
| N+5.bin (PBJ) | Battle clips (GF1Motion skeletal + BCH material/visibility) |
| N+6.bin (PKj) | Overworld / amenity clips (`kw*`) |

## Sample stems

- Torchic: model `2827`, PBJ `2832`, PKj `2833`
- Oddish: model `0499`, PBJ `0504`
- Groudon: model `4171`, PBJ `4176`

## PBJ container

- Magic: `PBJ\0` (PkmnContainer-style; u16 after `PB` is section-count-ish)
- `u32` at `+0x04` = `0x130` — start of **section 0** (GF1MotionPack)
- Later `u32`s are section start offsets (nested material/visibility BCHs)

## Section 0 — GF1MotionPack (SPICA `Formats/GFL`)

Decoded by `extract/pbj_rip.py` (port of gdkchan/SPICA `GF1Motion` / `GF1MotionPack`):

1. `u32 anims_count` (typically 0x1D = 29 slots)
2. Address table; slot 0 = skeleton (`GF1MotBone.ReadSkeleton`)
3. Non-zero slots 1..N = skeletal clips (`GF1Motion` octal-packed S/R/T hermite tracks)
4. Clip names come from nested BCH strings in later sections, mapped in slot order

### Clip vocabulary

- `ba10_waitA01` / `waitB01` — idle
- `ba01_landA01` / `landB01` / `landC01` — intro land
- `ba20_buturi01` (+ sometimes `02`) — physical attack
- `ba21_tokusyu01` (+ sometimes `02`) — special attack
- `ba30_damageS01` — damage flinch
- `ba41_down01` — faint / down

## Mesh skinning

- Default mesh.json remains bind-pose posed (phase: 1_static_posed) so place/texture path stays intact.
- ch_mesh.model_to_dict(..., keep_skin=True) also writes local_vertices, one_indices, one_weights, ones (+ inv_transform) with phase: 2_skinned_bind for per-vertex skinning.

## Runtime (DRAMATIC_SHAPE)

- OrasPbjAnim.lua loads %APPDATA%/LOVE/pokemon-love2d/oras_extract/anims/.
- OrasModels on attle.moveAnim / land / damage / faint / idle:
- **SAFE DEFAULT (2026-09-14):** `OrasModels.ENABLE_SKINNING=false` — bind-pose +
  `pbj_gf1_root` / procedural until LOVE skin matrices are fixed.
- When ENABLE_SKINNING=true: Prefers **per-vertex skeletal skin** when mesh skin sidecars exist → nim=pbj_gf1_skinned
  - Else real GF1 **root-motion** (Waist/Origin/Hips) → nim=pbj_gf1_root
  - Maps ma.physical → buturi vs tokusyu when possible
  - Idle uses a10_waitA01 / waitB as skinned wait when available (else procedural)
  - Falls back to procedural_battle if the clip is missing

## Commands

`at
python mods/oras_models/extract/extract_oras.py --extract-meshes --keep-skin
python mods/oras_models/extract/pbj_rip.py --nationals-from-mesh-index
python mods/oras_models/extract/pbj_rip.py --files 2832 0504 4176
`

Writes only under oras_extract/ (cache; never ssets/ / git).

## Wait-pose bake (phase 3) — 2026-09-14

Runtime LOVE skinning stays **off**. National meshes under AppData
`oras_extract/meshes/` have `vertices` replaced with an offline-skinned
`ba10_waitA01` (else wait) mid-frame pose via `extract/bake_wait_poses.py`.
Original bind is kept as `bind_vertices`. Serpents also get `wait_loop_xyz`
(3 frames) for a cheap idle slither without enabling the morphing skinner.

Rebake: `python mods/oras_models/extract/bake_wait_poses.py --force`
