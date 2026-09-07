# Champions Room -> Hall of Fame -> Credits (pokeruby)

Validated against stock pokeruby map scripts before fixing the Lua port.

## ROM sequence (facts)

Source: `misc/pokeruby-master/pokeruby-master/data/maps/EverGrandeCity_ChampionsRoom/scripts.inc`,
`.../HallOfFame/scripts.inc`, `src/post_battle_event_funcs.c` (`GameClear`),
`src/hall_of_fame.c` (then `CB2_StartCreditsSequence`), `src/credits.c`,
`src/battle_setup.c` (`GetTrainerBattleTransition`), `src/battle_transition.c`
(`Phase2Task_Transition_Steven` / mugshots), `src/data/credits_en.h`.

1. **ON_WARP**: face north (`VAR_TEMP_1 == 0`).
2. **ON_FRAME**: `lockall`, walk up 4 + 2 toward Steven, `setvar VAR_TEMP_1, 1`,
   champion BGM (`MUS_ENCOUNTER_CHAMPION` 454), intro speech,
   `trainerbattle_no_intro TRAINER_STEVEN` (335).
3. **No party heal** in the Champions Room script (heal is only inside `GameClear`
   later, and on whiteout).
4. Post-battle: door metatiles + `DrawWholeMapView`, post speech, rival music,
   **`addobject` rival (May/Brendan)** then Birch - they are **hidden** at map
   load via `FLAG_HIDE_RIVAL_CHAMPIONS_ROOM` (0x398) /
   `FLAG_HIDE_BIRCH_CHAMPIONS_ROOM` (0x399) until then.
5. Pokedex rating (`ProfBirch_EventScript_RatePokedex`), Steven leads north,
   `warp` Hall of Fame.
6. HoF walk + `FLDEFF_HALL_OF_FAME_RECORD`, `special GameClear` (heal, clear flag,
   ribbons, save, HoF cinema callback).
7. After HoF team board: **credits**, then SoftReset to title (bedroom heal set by
   GameClear). Port matches: credits then `softResetToBoot` (copyright/title).

## Port bugs fixed (2026-09-06)

- `lockall` only set NPC `talkLock`; player could walk if `self.field` dropped,
  aborting ON_FRAME after `VAR_TEMP_1=1` (Steven has script `0x0` -> soft-lock).
  Now `fieldControlsLocked` mirrors ScriptContext2 until `releaseall`.
- May/Birch could appear on the entrance warp tile if hide flags were unset;
  engine re-asserts flags while `VAR_TEMP_1==0`, with soft-lock recovery.
- HoF cinema previously warped home and skipped credits; now runs credits
  (`MUS_CREDITS` 455) then SoftReset to boot/title.

## Polish (2026-09-06 evening)

### Champion / Elite Four mugshot transition
- `GetTrainerBattleTransition` now returns `B_TRANSITION_STEVEN` for Champion /
  `TRAINER_STEVEN`, and `B_TRANSITION_SYDNEY..DRAKE` for Elite Four ids 261-264
  (`battle_setup.c`), instead of the SHARDS stand-in.
- Mugshot wipe (`Game3BattleTransition.lua`): decoded `elite_four_bg` tilemap BG
  (`mugshot_bg_<e4|steven>_240.png`), Steven front pic
  (`assets/generated/battle/trainers/ruby_29.png` = `TRAINER_PIC_STEVEN`), player
  front from cinema trainer sheets, optional `vs.png`, `SE_MUGSHOT` (104).
- Gym leaders still use the normal trainer transition table (RS behavior).

### Credits
- Page cards from full `credits_en.h` `gCreditsEntryPointerTable` (52 pages,
  LINES_PER_PAGE=5) rather than a condensed scroll stub.
- Mon parade corner uses party / caught species front pics (`CreateCreditsMonSprite` spirit).
- Bike-scene dayparts baked from pokeruby `intro2_*` tilemaps / pals via
  `tools/bake_champion_endgame.py` (mirrors `credits.c` `LoadBikeScene` /
  `intro_credits_graphics.c` `sub_8148CB0`):
  ocean morning -> ocean sunset -> forest sunset -> town night, with grass strips +
  bicycle / Brendan / May sheets under `assets/generated/credits/`.
- `assets/generated/credits/the_end.png` on the final hold; A/B (or hold timeout)
  calls `softResetToBoot` (ROM SoftReset), not bedroom warp.

### Mugshot BG decode
- `elite_four_bg.png` (15 tiles) + `elite_four_bg_map.bin` (32x20) + per-opponent
  `*_bg.pal` (player Brendan/May slots 10-15) baked to
  `assets/generated/battle/transitions/mugshot_bg_<name>_240.png`.
- `Game3BattleTransition.lua` draws the baked BG; procedural chevrons remain only
  as a missing-asset fallback.

Cache contract: **not bumped** -- assets live under `assets/generated/` and load
via `grabImage` (optional); trainer / mon fronts already in the ruby extract pipeline.

## Re-test

1. Save before Elite Four or use a debug warp to `g16_4` (Champions Room) with
   a full healed team and `VAR_TEMP_1` cleared (re-enter map clears temps).
2. Enter from Corridor4: player must be locked through walk-up, Steven intro,
   **Steven mugshot transition** (not shards), battle, rival/Birch, warp HoF.
3. Confirm May/Birch are **absent** until after Steven is beaten.
4. HoF record -> A on team board -> **paginated credits** (names + mon parade +
   bike dayparts) -> THE END -> **title/boot** (SoftReset), save still loadable.
5. If previously soft-locked in the room: stand still one frame (or re-enter);
   undefeated Steven + free controls resets `VAR_TEMP_1` and restarts ON_FRAME.



## Endgame visual / Continue fixes (2026-09-06 night)

Validated against `hall_of_fame.c` positions, `credits.c` /
`intro_credits_graphics.c` (`LoadBikeScene` VOFS=34, cyclist y=46,
`sMonSpritePos`), and `post_battle_event_funcs.c` `GameClear` +
`CB2_ContinueSavedGame` (`SetSecretBase2Field_9` / `specialSaveWarp` ->
`warp1` bedroom).

### 1. Hall of Fame party sprites too high
- **Cause:** `drawHofCinema` passed top-left (`x - HOF_PIC/2`) into
  `drawGbaFieldSprite`, which already treats coords as CreateSprite
  centres -- double offset shifted the team up ~32px (top row clipped).
- **Fix:** pass dest centres from `HOF_FULL_TEAM_POS` / `HOF_HALF_TEAM_POS`
  unchanged (same tables as `sHallOfFame_Mons*Positions`).

### 2. Credits bike scene seam / black box / floating mon
- **Cause:** (a) bike/Brendan/May sheets saved as opaque indexed PNGs
  (palette 0 = black padding); (b) BG/grass baked without
  `gUnknown_02039358` VOFS=34 window, and grass drawn by squashing the
  full 256x256 map (black upper tiles) into a 48px strip; (c) mon parade
  used a corner plaque at y=12 instead of `sMonSpritePos` centres.
- **Fix:** rebake via `tools/bake_champion_endgame.py` (VOFS crop,
  grass tile0 alpha, OBJ index0 alpha); `drawCreditsBikeBackdrop` draws
  pre-windowed sheets, cyclist at (120,46); `drawCreditsMonParade` uses
  `{104,36}/{120,36}/{136,36}` centres with no opaque plaque.

### 3. Continue after credits lands in Champions Room
- **Cause:** `gameClear` wrote `lastHeal`=bedroom but save `mapId` stayed
  on Champions Room / HoF; Continue always restored `mapId`. ROM sets
  `SaveBlock2.specialSaveWarp` and `warp1`=bedroom; Continue warps home.
- **Fix:** persist `specialSaveWarp` from GameClear; on Continue, if set
  (or GAME_CLEAR + still on a champion-endgame map for older saves),
  enter bedroom heal coords instead of the serialized map.

### Re-test
1. HoF cinema: top-row heads fully visible; team sits above
   "Welcome to the HALL OF FAME!" without a large empty gap; single-mon
   "Lv100" view is centred at dest Y (40/64), not clipped.
2. Credits: no horizontal mid-screen seam; Brendan+bike without black
   rectangle; parade mons at mid-upper centres over the road/grass.
3. After THE END -> title -> Continue: Littleroot bedroom (`g1_1` /
   `g1_3`), not `g16_4` Champions Room. Existing post-clear saves stuck
   in the room should also recover on Continue.

## Remaining gaps / stubs

- Mugshot BG is a full tilemap decode; HBlank wavy window wipe / scanline split
  from `Phase2_Mugshot_Func3+` is still approximated by the port's slide+fade.
- Credits bike dayparts use baked scrolling sheets (not live GBA affine BG regs /
  `CycleSceneryPalette` hue cycling). Grass-only interludes (`TDA_11==2`) are not
  a separate scene -- daypart BG stays up. Mon parade still skips ROM national-dex
  tile-slot packing / Spinda-Unown personality path.
- SoftReset path returns to copyright->title via `softResetToBoot` (closest engine
  equivalent); does not literally call GBA SoftReset(0xFF).

## Credits stacking + Continue layout (2026-09-06 late night)

### Credits: Tentacruel on Brendan / black THE END box
- **Cause:** (1) drawCreditsCinema drew mon parade after the bike/rider, and still drew parade sprites during stage==the_end. ROM Task_CreditsTheEnd1 sets gIntroCredits_MovingSceneryState, which SpriteCB_CreditsMon uses to DestroySprite before DrawTheEnd. (2) the_end.png was white-on-opaque-black (no alpha); ROM letter tiles use color 0 transparent over the grass BG.
- **Fix:** parade is drawn under the cyclist inside drawCreditsBikeBackdrop and skipped on THE END; the_end.png black->alpha; draw at 2x over grass. Positions remain sMonSpritePos {104,36}/{120,36}/{136,36}; cyclist (120,46).

### Continue still looked like Champions / Corridor after force home
- **Cause:** specialSaveWarp + bedroom lastHeal did call enterMap on Littleroot, but Continue then always re-applied data.mapLayoutId (e.g. Corridor4 layout 316 from save mapId=g16_8) via setMapLayoutIndex, painting league tiles onto the bedroom. Recovery also only treated g16_4/g16_11 as endgame, missing Corridor4 (g16_8).
- **Fix:** skip saved-layout restore when redirected home; treat all IndoorEverGrande maps g16_0..g16_11 as endgame; if GAME_CLEAR and heal is not a bedroom, force Brendan/May 2F spawn. gameClear / HoF->credits re-flush writeSave even if phase was still battle.

### Re-test
1. Credits late pages / THE END: Brendan+bike alone on grass; white THE END with grass visible through letter holes (no black tile rectangle); no mon stacked on the rider.
2. Title -> Continue on a cleared save (even mapId=g16_8 Corridor4): real Littleroot bedroom tiles (g1_1/g1_3), not league corridor graphics.
