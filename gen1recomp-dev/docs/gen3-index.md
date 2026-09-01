# Gen 3 agent index

Grep this file first. Then read pokeruby C / `specials.inc` / the map
script. Then the GBA oracle. Then edit. Do not wander `Game3.lua`
looking for a name that is listed here.

Narrative history: `docs/gen3-phase1.md`. This file is the lookup.

## Consult order

1. This index (`docs/gen3-index.md`)
2. pokeruby: `C:\Users\Feces\Desktop\pokeruby-master\pokeruby-master\`
   - `data/specials.inc` (special ordinals)
   - `src/*.c` for the function
   - `data/maps/<Map>/scripts.inc` for the scene
   - `include/constants/{flags,vars,items,maps}.h`
3. Oracle: `tools/gba_oracle/README.md`
   - `python tools/gba_oracle/check_specials.py` after adding `Game3.SPECIAL_*`
   - `python tools/gba_oracle/snapshot.py` with the US Ruby cart
4. Then `src/core/Game3.lua` / `src/import/Gen3Script.lua`

ROM (not in git): `C:\Users\Feces\Desktop\Pokemon - Ruby Version (USA).gba`
Cache: `%APPDATA%\LOVE\pokemon-love2d\ruby\` contract **ruby41**
Do not copy Nintendo graphics into git. No cache bump unless extractor/IR
must change. LÖVE does not hot-reload. PowerShell: `;` not `&&`.

## Hard rules

- Port the ROM as-is. No placeholders.
- Lua **0 is truthy**. Never `if n then` for a C `if (n)` that treats 0 as
  false. Use `n ~= 0`.
- LuaJIT **200 local** limit. New tests go in an IIFE `(function() ... end)()`.
- Special id = `def_special` **line in specials.inc minus 11** (Heal is
  line 11 = 0). Confirm with `check_specials.py`.
- MapGrid coords include **MAP_OFFSET 7**. Map-local = MapGrid − 7.
- Collision bits 10-11 = `MAPGRID_COLLISION_MASK` `0x0C00`.
- `runSpecial` must **return** values that `specialvar` stores. Setting
  `VAR_RESULT` is optional if you return.
- Cached IR still nops newly decoded commands until the player re-imports.
- Tests from repo root: `luajit tests/engine/ruby_battle_test.lua` (and
  `ruby_map_test`, `ruby_boot_test`, `ruby_sprite_test`, `ruby_save_test`).

## Paths

| Piece | Where |
| --- | --- |
| Runtime | `src/core/Game3.lua` `Game3Boot.lua` |
| Script IR | `src/import/Gen3Script.lua` |
| Extractor | `src/import/RomExtractorGen3.lua` + Battle + Boot + Cinema + Dex |
| Map shards | `src/import/Gen3MapPack.lua` |
| Audit | `tools/gen3_script_audit.lua` |
| Oracle | `tools/gba_oracle/` |
| Manifest | `tools/rom_manifest_ruby.json` |
| Phases | `docs/gen3-phase1.md` |
| Party/cinema harness | `tools/gen3_finder/` `tools/gen3_preview/` (`lovec tools/gen3_finder`) |
| Scratch dumps | `tmp/debug/` (gitignored; never the Desktop) |
| Overworld tiles | Live windowed SpriteBatch like Gen 1 (`Game3:tileWindow`); 2x2 border fill (`GetBorderBlockAt`) clipped to MAP_OFFSET (ocean/underwater skip the tree wallpaper); water DMA is a flip on surfable / flower tiles only (harbor walls that share flower VRAM do not blink) |
| Survey zoom / tilt | Same `Zoom.lua` / `Tilt.lua` as Gen 1/2. Hotkeys `3` (tilt), `4`/`-`/`=`/wheel (zoom). World fills the window at zoom scale so neighbors show; UI stays 240×160 letterbox. Camera re-follows after every view size (zoom/tilt), on the window centre; connections lerp one tile like `World:tryConnection`. Tilt: ground plane, then upright sprites, then BG1 overlay (roofs) so you cannot walk on buildings. Land NPCs cannot wander onto surfable water (Route 110 cyclists stay on the cycling road). OW reflections use `IsReflective` (pond/ice/under-bridge), including the tile a 32px sprite covers north of the feet. Trainer-see `!` / `?` / heart are the ROM 16×16 field-effect sprites (`gSpriteImage_839B308`, pal 0x1004), not FONT3 glyphs. |

Map id is `g{group}_{num}` via `Game3.mapId`. `mapMatches` returns true
for stub maps whose id is not `gN_M`.

## Map groups (map_groups.json order, 0-based)

0 towns/routes, 1 Littleroot indoor, 2 Oldale, 3 Dewford, 4 Lavaridge,
5 Fallarbor, 6 Verdanturf, 7 Pacifidlog, 8 Petalburg, 9 Slateport,
10 Mauville, 11 Rustboro, **12 Fortree** (gym = num 1), 13 Lilycove,
14 Mossdeep, 15 Sootopolis, 16 Ever Grande, 17 Route104 indoor,
18 Route111, **19 Route112** (cable car 0 / Chimney station 1),
24 dungeons (Granite 8/9), **29 Route110 indoor** (Trick House 0-8,
cycling south 11, north 12).

Fortree gym `g12_1`. Trick House puzzle 6 `g29_8`. Cable car group 19.

## Player path (done vs hole)

Story so far: NEW GAME → Littleroot → Oldale → Petalburg Woods →
Rustboro → Peeko → Briney → Dewford → Granite → Briney → Route 104 →
Slateport → museum → Route 110 → Mauville → Wattson. Next: Route 111
desert / Gabby & Ty → cable car → Lavaridge → Weather Institute →
Route 119 / Fortree (Kecleon, Winona). Then Lilycove (dept-store
elevator) → Route 121 → Route 122 Surf → Mt. Pyre (ice interiors;
exterior stairs skip them). Then Slateport Harbor → Magma Hideout.

| Stretch | Status |
| --- | --- |
| Intro / truck / Birch / starters | done |
| Mom wall clock `StartWallClock` 154 | done |
| Petalburg woods, Cut, Roxanne | done |
| Briney sail, Dewford, Brawly flash | done |
| Granite holes / escape warp | done |
| Slateport museum money box / Magma fade | money box + 16-frame fade done |
| Route 110 cycling road 225-229 | done; gates g29_11/g29_12 keep the bike (`Overworld_IsBikingAllowed`) |
| Trick House password (ones digit 147) | done |
| Trick House end flag 0x259 | done |
| Trick House puzzle 6 rotating gates | done (ROM 4bpp, ruby36) |
| SELECT Key Item / Rydel swap 130 | done |
| Wattson beams 139/140/144 | done |
| Norman doors 145/146 | slide/open done; signs A-press only, not bump-warp |
| Cable car 151/152 | ride waitstate (0x15e up / 0x109 down); mountain / car tiles from the cart (ruby33) |
| Game Corner `GetSlotMachineId` 286 | id done |
| Game Corner `playslotmachine` 0x89 | done (needs re-import) |
| Game Corner `PlayRoulette` 162 | done |
| Coins 0xB3-B5 / coin box 0xC0-C2 | done (needs re-import) |
| Mauville old man (bard/hipster 97-118) | done |
| Wall clock view 155 | done |
| New Mauville Voltorb `setwildbattle` 0xB6/0xB7 | done (needs re-import) |
| Rock Smash script path 0x7C / 171 / 298 | done (needs re-import) |
| Route 111 sandstorm `setweather` 0xA3–0xA5 | done (needs re-import) |
| Route 111 Gabby & Ty interview 172-180 | done |
| Lavaridge gym buried trainers (HIDDEN 63) | done |
| Lavaridge `giveegg` 0x7A Wynaut | done (needs re-import) |
| Route 113 Glass Workshop 274 | done |
| Route 113 flutes / wild rate | White/Black 0x84D/0x84E; Blue/Yellow/Red reusable; bike 80%; Cleanse Tag; Stench/Illuminate |
| Fallarbor Move Relearner 219/224 | done |
| Lilycove Move Deleter 220-223 | done |
| Go-Goggles 279 / hot springs stat 49 | done |
| Flannery Overheat / Light Screen / Attract / Flail | done |
| Muddy slopes 0xD0 (Route 112 / Jagged Pass) | done |
| Weather Institute | Castform Forecast + Weather Ball + givemon item (pics need re-import) |
| Route 116 BlackGlasses 316 | done |
| Route 119 / Fortree Kecleon | INVISIBLE collides; tree/mountain 0x39/0x3A; Color Change; Devon Scope 288 |
| Fortree gym Winona | Endeavor 189 + TM40 Aerial Ace; gates already done |
| Lilycove dept elevator | inbound MAP_DYNAMIC save; specials 216/273/306; temp 0x1–0x1F |
| Ice / currents / walk-slide pads | forced movement; currents surfable 0x50–0x53 |
| Route 121 Safari Zone | Enter/Exit 205/206, 30 balls / 500 steps, BALL/GO NEAR/RUN |
| Mt. Pyre holes / hideout pads / arrow warps | 0x0F fall 319; 0x67 pad; arrows match dir |
| Route 119/123 weather cycle | specials 324/325; header is SUNNY |
| FACE_DOWN_AND_* look types | 0x0D–0x16 stay put; medium delay; dash snap |
| Mossdeep gym arrows | pair_35 walk pads 0x40–0x43; `setmetatile` flips dir |
| Sootopolis gym ice | STEP_CB_ICE increments `VAR_ICE_STEP_COUNT`; special 309 |
| Cave of Origin Groudon | special 311 + `setdivewarp`; cinema 281/282 pal+WIN0 (no orb tiles) |
| E4 / Champion / Hall of Fame | doors are `setmetatile`; GameClear 272 warps home |
| Post-game Latios roamer | TV special 73; InitRoamer 297; overlay on grass/surf |
| SS Tidal | specials 203/204/270 waitstate; 205 steps; harbor lists 52/56 |
| Lavaridge / Fortree / Mossdeep / Sootopolis gyms | Lavaridge + Fortree + Mossdeep arrows + Sootopolis ice |
| PokéNav | visited FLAG_VISITED towns; FieldShowRegionMap 251 waits |
| Pokeblocks / contests / blender | lobby specials 76-91/134-138, blender 160-161/259, feeder 208 |
| PC from scripts | CreatePCMultichoice 262, BedroomPC 249, PlayerPC 250, storage 60 |
| Rotating gates Fortree | done (ROM 4bpp, ruby36) |
| Rematches / Pokerus / size / diploma | trainer-eye 57-59; Pokerus infect/spread/decay; Pacifidlog TM 333/334; fan club 163-170; diploma 264; Enigma 50/339; Southern Island 323 |
| Daycare leftover / HoF PC | selected nick 186; mail 195; GetDaycareMonNicknames 181; AccessHallOfFamePC 263; GameClear records 50 teams; cinema 94/275/276/305/315/317 skip |
| House TVs / lottery / ship keys | WATCH clear when Gabby airs; 63-66/71/74-75/175; lottery 256-258/217-218 blink/337; keys 288-291 |
| Field poison / whiteout / SaveGame | poison every 4 steps; DoWhiteOut money/2; SaveGame 93; trainer EventScript 51-56/61 |
| Herb shop / Lava Cookie / decor marts | Energy Powder/Root, Heal Powder, Revival Herb friendship; Lava Cookie; 0x87/0x88 |
| Field medicines | BAG/SELECT open `party_use` (`OtherText_UseWhat`); A applies `UseMedicine`; egg is SE_FAILURE; B/CANCEL back to bag |
| Cable Club | no GBA link; receptionist RESULT 5 goodbye; Teala with a script is not contest |
| Daily clock events | ClearDailyFlags 0x8C0–0x8FF; Dewford trends; weather cycle % 4; mirage LCG; Birch % 7; shoal 0x85F; lottery |
| Flutes / wild rate | White 43 / Black 42; flags 0x84D/0x84E last until LoadMap; Blue/Yellow/Red reusable; bike *80/100; Cleanse Tag *2/3; Stench /2 Illuminate *2; Rock Smash skips ability; Strength and CTRL_OBJ_DELETE also clear on LoadMap |
| Dialogue box | 2 FONT3 lines, 208px via `sFont3Widths`; frame tiles 0,14–29,19; text at 2,15; typewriter is the current page; `\l` 0xFA scrolls; `\p` pages; `TEXT_LEN` 1024 |
| START / menus | START `Menu_DrawStdWindowFrame(22,0,29,n*2+3)`; title CONTINUE/NEW GAME/OPTION `main_menu.c` frames; OPTION title `(2,0,27,3)` list `(2,4,27,19)`; OVERWORLD / BATTLE / MENU SPEED (GameSpeed.lua) scroll with ZOOM / TILT in the unused BUTTON MODE / FRAME rows |
| Pokédex | START POKeDEX: seen/caught list in Hoenn (or National) order; A opens INFO (front pic, category, HT/WT, flavour). Left/right is the INFO/AREA/CRY/SIZE bar; A opens that screen. SIZE uses `pokemonScale`/`trainerScale` silhouettes (256/PA). AREA habitat map parked. First catch: AddedToDex, `displaydexinfo`, cry, then `trygivecaughtmonnick`. Chrome tiles / footprints parked. |
| Boot cinema | Affine 8bpp title logo (`gUnknown_08E9F7E4`, BG2X -29, resting BG2Y 0) + glow Groudon; copyright pal `0xE9CA24` / map `0xE9CA44`; intro1 is four 256x256 parallax layers (1.5/1.0/0.75/0 px per frame from VOFS 0x28/0x18/0x50/0) + GAME FREAK OBJ at 560; intro2 grass+trees ~4px/frame. Re-import. |
| Window chrome | `RomExtractorGen3Ui`. 20 text-window styles at gfx `0xE9ADDC` / pal `0xE9AEFC`, stride `0x140` (9 tiles + 16 colors each); `drawWindow` 9-slices them (row = OPTION FRAME). Dialogue box `0xEA0108` (14 tiles) via `sDialogueFrameTilemap` 7x5 with flip bits. Pals `0xD1212C` window / `0xD1214C` hpbar; healthbox elements `0xD1216C`..`0xD129AC` (66 tiles). Re-import. |
| Battle bar | `gBattleTextboxTilemap` `0xD00524` is 4096 bytes copied to ONE bg, so it is 64x32 = two 32x32 screenblocks side by side, holding three 6-row bands all shown at y=112: message (left block row 14), action select (right block row 2), move select (right block row 22). Tiles `0xD00000` LZ (256), pal `0xD004E0` LZ (2 pals). Extracted as three 240x48 overlays. |
| Healthboxes | `gBattleWindowLargeGfx` `0xD1F52C` (player, two 64x64 OBJ halves, carries the EXP bar) and `gBattleWindowSmallGfx` `0xD1F7E0` (opponent, two 64x32). Halves blit side by side into a 128px frame. "Lv" and the EXP track are baked into the art, so only the digits and the EXP fill are drawn. Found as the only run of five consecutive LZ streams sized 4096/2048/2048/2048/4096. |
| Move select | 2x2, not a list: bit 0 is the column and bit 1 the row (`battle_controller_player.c`). A press only lands on a slot that holds a move, and never wraps -- `Game3.moveCursorStep`. SELECT (2+ moves) opens dest-cursor reorder (`Switch which?`); A/SELECT swap, B cancels. Action select (FIGHT/BAG/POKeMON/RUN) is the same shape. |
| Audio data | `RomExtractorGen3Audio`, extractor stage 8. Every MP2K structure sits in one 2.50 MB span `0x42FC88..0x6B0728`, so `mp2k.bin` is that span copied verbatim and a ROM pointer becomes a blob index with `offset - base` -- repacking would mean rewriting every GOTO/PATT/REPT target. `gSongTable` `0x45548C`, 468 entries of `{SongHeader*, u16 player, u16}`; 416 real, 52 share `dummy_song_header` (trackCount 0). 114 voicegroups, 516 samples (388 of them cries), 0.44 MB PCM. Re-import. |
| Cries | `gCryTable` `0x452590` and `gCryTable2` `0x4537C0`, 388 `ToneData` each, reachable from code rather than from any song header, so `scanCries` pulls their samples into the span explicitly. Every entry is the `cry` macro verbatim -- type **0x20**, key 60, ADSR 255/0/255/0 -- which is what validates the offset. Species -> cry id is resolved at import into `audio.cries[1..411]`: `PlayCryInternal` decrements first, so below 251 the id is the index, 251-275 (the unused `?` slots) all borrow Unown's 200, and Hoenn reads `gSpeciesIdToCryId` `0x1FDE6A` because those cries were recorded in a different order than the species were numbered (Treecko is species 277, cry 273). |
| Music players | `gSongTable`'s second field is the music player, and it is the only thing separating a jingle from a theme: player 0 is BGM and loops, players 1-3 are SE and fanfares and end on their own. Useful when checking a song id -- 375 is `mus_oceanic_museum`, not a fanfare. |
| MP2K commands | `Audio.commandLength`. 0x00–0x7F are arguments, and a bare one means running status. 0x80–0xB0 wait, 0xB1 FINE. Fixed: GOTO/PATT u32, REPT count+u32, MEMACC 3, XCMD 2, 0xBA–0xC8 one each. Variable (eat argument bytes only while they stay under 0x80): EOT 1, TIE 2, notes 0xD0–0xFF 3. Checked structurally -- MUS_TITLE's ten tracks tile end to end and the last ends one byte before its header. |
| Audio player | `Mp2kSynth` (sequencer + mixer) and `Mp2kAudio` (playback). Copies ChipSynth's *interface* only -- `newEngine`/`sampleStereo`/`finished`/`soundData` -- and renders on the main thread at ~10x realtime, so buffers are 2048 not 8192. Timing: tempoD = 2x the TEMPO byte, 150 counter units per tick, 24 ticks a quarter, at the GBA's 59.7275 Hz vblank. |
| Audio voices | `Mp2kAudio` holds four independent voices -- `bgm`, `se`, `fanfare`, `cry` -- each its own engine and `QueueableSource`, because Ruby has no separate sound system: an effect is just a song on another music player. Only `bgm` loops; the others build with `allowLoops = false` so a jingle's trailing GOTO ends it instead of repeating. A live fanfare mutes `bgm` underneath. Music volume follows the launcher's `musicVol` and the rest `sfxVol` (`Game3:applyAudioOptions`) -- Ruby's own OPTION screen has no volume rows. |
| Cry playback | `Mp2kSynth.newCryEngine`. `SetPokemonCryTone` patches one `ToneData` into a fixed one-note template; instead of rebuilding the template, point a bare engine's voicegroup straight at the cry's tone and strike middle C, which is all it amounts to. The one track is created already stopped -- there is no byte stream. The sample does not loop, so the channel dies at its end and the engine reports finished without anything timing it. |
| MP2K gotchas | Running status latches **only** for commands >= 0xBD; when waits latched too, every track wedged after ~38 notes. Game Boy envelopes are counter-based on 0..15 where rate 0 means *instant* (Ruby writes flat voices as 0/7/15/0); DirectSound is the separate 0..255 add/multiply scheme. Rhythm voices override the pitch, so EOT matches `ch.noteKey` (what the track wrote), not the drum's key. |
| Music hooks | Map BGM from the header `music` on `enterMap` (0 = MUS_NONE stops, 0x7FFF = position-dependent, keeps playing; a shared song does not retrigger). Battle themes from `audio.named` vsWild/vsTrainer, restored from the header at `endBattle`. `openIntro`/`openTitle` play MUS_INTRO/MUS_TITLE. `playbgm`/`savebgm`/`fadedefaultbgm` dispatch, and 0x36/0x37/0x38 fadenewbgm/fadeoutbgm/fadeinbgm are now decoded rather than dropped. |
| Sound hooks | `playse`/`waitse`/`playfanfare`/`waitfanfare` (script `0x2F`-`0x32`, one contiguous block with the six BGM opcodes through `0x38`). The waits suspend the script the same way `waitmoncry` does: set `waitingSe`/`waitingFanfare`, `beginScriptWait`, and `Game3:update` releases it when the voice goes quiet. `playMonCry` goes through MP2K now, with the Gen 1/2 `Sound.playCry` left only as a fallback for a cache imported before the cry tables. |
| Audio still open | Special 56 wants a trainer encounter-music field the extractor does not read. Fanfares mute the music rather than pausing it, so the BGM resumes where it would have been rather than where it stopped. MEMACC/XCMD skipped; vibrato is pitch-only (MOD as pitch, `modType 0`); volume and pan modulation ignored. |

## Specials (Game3.SPECIAL_* = ordinal)

Grep `SPECIAL_` here or in Game3. `check_specials.py` is the oracle.

| Id | Name | Status |
| --- | --- | --- |
| 0 | HealPlayerParty | done |
| 43-49 | berry tree | done |
| 95 | ShowEasyChatScreen | Dewford 9, bard 6, Gabby interview 10 |
| 97-118 | Mauville old man | bard/hipster/trader/storyteller/giddy |
| 123-125 | Name Rater TV | done |
| 126-129 | Dewford Hall | done |
| 130 | SwapRegisteredBike | done |
| 139-144 | Mauville gym + DrawWholeMapView + coords | done |
| 141 | ShowFieldMessageStringVar4 | done |
| 145-146 | Petalburg gym doors | snap to frame 4 |
| 147 | GetPlayerTrainerIdOnesDigit | done |
| 148-149 | BigGuyGirl / SonDaughter | done |
| 150 | SetHiddenItemFlag | done |
| 151-152 | CableCarWarp / CableCar | waitstate ride; WarpIntoMap after unk_0004 |
| 63 | DoTVShow | RESULT 1 (no queued interview shows) |
| 64 | DoPokeNews | RESULT 0 (no news) |
| 65 | special_0x44 | 255; must return (0 is valid later) |
| 66 | GetTVShowType | 0 |
| 71 | GetNonMassOutbreakActiveTVShow | 255 if 0x8004 is 255 |
| 74 | GetMomOrDadStringForTVMessage | STR_VAR_1; Brendan 1F male / May 1F female → MOM |
| 75 | ResetTVShowState | `tvShowState = 0` |
| 175 | DoTVShowInSearchOfTrainers | pages 0-8; last RESULT 1 + off air |
| 217-218 | Lottery computer effect | blink 7×5; End snaps Normal; no wait |
| 256 | GetWeekCount | `gLocalTime.days / 7`; cap 9999; 0 is valid |
| 257 | RetrieveLotteryNumber | u16 of VAR_LOTTERY_RND_L/H |
| 258 | PickLotteryCornerTicket | >1 digit; 0x8004 = n-1; prizes PP Up/Exp Share/Max Revive/Master Ball |
| 337 | BufferLottoTicketNumber | STR_VAR_1 5-digit pad |
| 279 | CheckRelicanthWailord | first Relicanth, last SPECIES2 Wailord; 0 is valid |
| 280 | DoBrailleWait | 7200+30 then open; 2nd JOY_NEW cancels; wait |
| 288-291 | FoundAbandonedShipRoom*Key | copy flag to 0x8004; 0 is valid |
| 299 | IsGrassTypeInParty | gBaseStats Grass; eggs skip; 0 is valid |
| 308 | IsPokerusInParty | `pokerus & 0xF`; cured `0x10` is 0 |
| 310 | ShakeCamera | 8 pans × 5 frames; wait |
| 62 | TurnOffTVScreen | TV_Off on MB_TELEVISION; no wait |
| 153 | Overworld_PlaySpecialMapMusic | nop (no OW music hook) |
| 154 | StartWallClock | done |
| 155 | ViewWallClock | done |
| 156-159 | starter / Wally / nickname / NPC trade | done |
| 162 | PlayRoulette | Game Corner table |
| 171 | ScrSpecial_RockSmashWildEncounter | smash wild; RESULT 1 + wait |
| 172 | GabbyAndTyGetBattleNum | 0 is first pair; `>=6` → `(n%3)+6` |
| 173 | GabbyAndTyAfterInterview | copies valA→valB, airing, stat 6 |
| 174 | GabbyAndTyBeforeInterview | copies `gBattleResults`; `++battleNum` |
| 176 | IsTVShowInSearchOfTrainersAiring | valA_4 |
| 177 | GabbyAndTyGetLastQuote | 0xFFFF → 0; else STR_VAR_1 and consume |
| 178 | GabbyAndTyGetLastBattleTrivia | 0 is valid |
| 179 | GetGabbyAndTyLocalIds | 0x8004 Gabby / 0x8005 Ty; no case 0 |
| 180 | GetBattleOutcome | `gBattleOutcome` (win=1 lost=2 ran=4 caught=7) |
| 298 | TryUpdateRusturfTunnelState | g24_4 hide-rock → state 4/5 |
| 181-192 | daycare | 181 nicks; 186 selected nick (0 valid); 187-192 deposit/take |
| 195 | DaycareMonReceivedMail | mail itemId; nick/OT mismatch; 0 is valid |
| 197-198 | HasEnoughMoneyFor / PayMoneyFor | `VAR_0x8005` |
| 201-202 | RotatingGate init / gfx | done |
| 205-206 | EnterSafariMode / ExitSafariMode | 30 balls, 500 steps, flag 0x82C; no wait |
| 60 | ShowPokemonStorageSystem | wait; existing box UI |
| 51 | GetTrainerBattleMode | `sTrainerBattleMode`; SINGLE is 0 |
| 52 | ShowTrainerIntroSpeech | `sayScript` intro; no wait |
| 53 | ShowTrainerNonBattlingSpeech | cannot-battle text |
| 54 | GetTrainerFlag | `trainerDefeated`; 0 is valid |
| 55 | EndTrainerApproach | 1-frame wait; next vblank DestroyTask |
| 56 | PlayTrainerEncounterMusic | nop (no OW music) |
| 57 | ShouldTryRematchBattle | rematch flag or second id fought; 0 is valid |
| 58 | IsTrainerReadyForRematch | `trainerRematches[i] ~= 0`; 0 is valid |
| 59 | BattleSetup_StartRematchBattle | rematch party from table; wait |
| 61 | HasEnoughMonsForDoubleBattle | `monsStateToDoubles`; TWO_USABLE is 0 |
| 67 | InterviewBefore | RESULT 0 (empty `tvShows`) |
| 68 | InterviewAfter | nop until `tvShows` exist |
| 69 | LeadMonNicknamed | nick ~= species; 0 is valid |
| 70 | SetContestCategoryStringVarForInterview | STR_VAR_2; 0 → COOL |
| 72 | TV_IsScriptShowKindAlreadyInQueue | 0 (slots 0-4 empty) |
| 93 | SaveGame | `writeSave`; RESULT 1/0; no wait |
| 133 | CountAlivePartyMonsExceptSelectedOne | skip `0x8004`; 0 is valid |
| 199 | ExecuteWhiteOut | poison-faint friendship + texts; RESULT 1 all down |
| 200 | sp0C8_whiteout_maybe | `DoWhiteOut` unless field `thenWhiteout` |
| 314 | SetUpTrainerMovement | visual nop |
| 326 | ScriptGetMultiplayerId | 4 when not link |
| 340 | ScriptRandom | `RESULT = gbaRandom() % RESULT`; 0 stays 0 |
| 76 | GetContestWinnerIdx | `0x8005` contestant with standing 0; player is 3 |
| 77 | GetContestPlayerMonIdx | `0x8004` = 3 after TryPutPlayerLast |
| 78 | GetNpcContestantLocalId | `0x8005` 0/1/2 → local 3/4/5 |
| 83 | SetContestTrainerGfxIds | VAR_OBJ_GFX_ID_0..2 from opponents |
| 84 | CheckSelectedMonAndInitContest | 0-4 like CanMonParticipateInContest |
| 90 | sub_80C5044 | link-contest flag; 0 is valid |
| 160 | GetFirstFreePokeblockSlot | 0-based; `-1` if the 40-slot case is full |
| 161 | DoBerryBlending | wait; berry pick; skip RPM minigame |
| 207 | SafariZoneGetPokeblockNameInFeeder | 0xFFFF until a feeder pokeblock |
| 208 | OpenPokeblockCaseOnFeeder | wait; list; RESULT 1 placed / 0 cancel |
| 214-215 | DoPCTurnOn/Off | 7×5 blink at facing tile; Off snaps; no wait |
| 26 | DoSecretBasePCTurnOffEffect | facing tile Off + SE_PC_OFF; no wait |
| 249-250 | BedroomPC / PlayerPC | wait; item/mail/[deco]/off |
| 251 | FieldShowRegionMap | wait; painted Hoenn map (ruby39) |
| 259 | ShowBerryBlenderRecordWindow | wait; 2P/3P/4P RPM |
| 262 | ScriptMenu_CreatePCMultichoice | wait; Someone's/Lanette's, Player's, Log Off, HoF |
| 277 | GetPokeblockNameByMonNature | STR_VAR_1 liked color; 0 is hardy |
| 209 | IsMirageIslandPresent | PID low 16 vs VAR_MIRAGE_RND_H; 0 is valid |
| 210 | UpdateShoalTideFlag | outdoor last warp; tide[hours]; no wait |
| 211 | InitBirchState | `VAR_BIRCH_STATE = 0`; 0 is valid |
| 216 | SetDepartmentStoreFloorVar | `dynamicWarp.mapNum`; 1F=0 rooftop=15 |
| 212-213 | Pokédex info / rating | done |
| 193 | ScriptHatchMon | AddHatchedMonToParty `0x8004`; no wait |
| 194 | EggHatch | waitstate shake + hatch line + nick YES/NO; egg tiles (ruby34) |
| 219 | SelectMoveTutorMon | party; 0x8004 index / 255; 0x8005 count |
| 220 | SelectMove | wait (no opcode); 0x8005 index / 4 cancel |
| 221 | DeleteMonMove | zero `0x8005` then compact; HMs allowed |
| 222 | GetPokemonNicknameAndMoveName | STR_VAR_1 nick / STR_VAR_2 move |
| 223 | CountPokemonMoves | RESULT count; 1 is the only-one branch |
| 224 | DisplayMoveTutorMenu | relearn list; 0x8004 1 taught / 0 cancel |
| 225-230 | cycling road + friendship | done |
| 1-2 | Set/DoCableClubWarp | dest under feet; 2 waits FADE then WarpIntoMap |
| 3 | sub_80810DC | same fade+warp wait as DoCableClubWarp |
| 4 | sub_80839A4 | LoadPlayerParty/copy warp; no wait |
| 28-30 / 36 / 341 | link connect | RESULT 5 goodbye; no wait. 0 would warp |
| 31 | CloseLink | nop |
| 196 | ShowLinkBattleRecords | field UI; A/B close; waitbuttonpress 0x6D decoded |
| 283 | ShowBattleTowerRecords | field UI; Lv50/100 current+record; A/B close |
| 231 | sub_8134548 | VAR_TEMP_0 = 5 so lobby ON_FRAME stops |
| 237-238 | SetBattleTowerProperty / BattleTowerUtil | var_4AE 0 is idle; must return |
| 233 | CheckPartyBattleTowerBanlist | 0x8004 = 0 allow |
| 245 | ChooseBattleTowerPlayerParty | RESULT 0 cancel; no wait |
| 246 | ValidateEReaderTrainer | empty checksum → 1 (door closed) |
| 247 | GetBestBattleTowerStreak | stat 32; 0 is valid |
| 12 | GetCurSecretBaseRegistrationValidity | 0 can-register |
| 252-255 | in-game trade | 253 fills incoming; 254 timed cable cinema then A swaps (ruby35) |
| 260-261 | Trick House end room | flag 0x259 |
| 73 | CheckForBigMovieOrEmergencyNewsOnTV | matching 1F; 1 Lati / 2 movie / 0 else |
| 169 | UpdateTrainerFanClubGameClear | bit 7 skip; unhide + state 1 |
| 50 | IsEnigmaBerryValid | 0 (no e-reader save) |
| 119-122 | Shroomish/Barboach size | Marco 0x8100 = 15.7 in; Compare 0/1/2/3; 0 is valid |
| 163 | ShouldMoveLilycoveFanClubMember | bit of VAR_FANCLUB_UNKNOWN_1 >> 0x8004; 0 is valid |
| 164 | GetNumMovedLilycoveFanClubMembers | bits 8-15; 0 is valid |
| 165 | BufferStreakTrainerText | 0x8004 10-14 → Winona/Steven/Wallace/Phoebe/Glacia |
| 166 | sub_810FA74 | if bit 7: UpdateMoved + hours |
| 167 | UpdateMovedLilycoveFanClubMembers | unmove if 5+ and 12h elapsed |
| 168 | sub_810FF48 | `VAR_FANCLUB_UNKNOWN_1 \|= 0x80` |
| 170 | sub_810FF60 | score add 2/1/2/1; 0 is valid |
| 264 | ScrSpecial_ShowDiploma | waitstate; A/B close |
| 263 | AccessHallOfFamePC | waitstate; newest team first; A older / close; B close |
| 94 | DoWateringBerryTreeAnim | 11 × 16-frame walk-in-place; wait |
| 275-276 | Spawn/RemoveCameraDummy | invisible local 127; camera follows; no wait |
| 305/315 | DoSealedChamberShakingEffect1/2 | 50×5 / 2×5 pans; wait |
| 317 | sub_807E25C | Route 128 BLDY flash 167 frames; wait |
| 323 | ScrSpecial_StartSouthernIslandBattle | scripted wild + legendary; wait |
| 333 | SetPacifidlogTMReceivedDay | VAR 0x40C2 = gLocalTime.days; 0 is valid |
| 334 | GetDaysUntilPacifidlogTMAvailable | 0 = ready; else 7 - elapsed; 0 is valid |
| 339 | GetNameOfEnigmaBerryInPlayerParty | held item 175 → STR_VAR_1 ENIGMA; 0 is valid |
| 203 | SetSSTidalFlag | cruise flag + step count 0; no wait |
| 204 | ResetSSTidalFlag | clear FLAG_SYS_CRUISE_MODE |
| 270 | sub_80C7958 | porthole: ocean warp + wait; A or arrive 9/10 |
| 272 | GameClear | heal, record 50-team HoF, ribbons, warp home; no wait |
| 273 | ShakeScreenInElevator | 23 pans × 3 frames; SE_ELEVATOR then ding; wait |
| 274 | ShowGlassWorkshopMenu | waitstate; RESULT 0–7 / 127 |
| 286 | GetSlotMachineId | easy-chat salt |
| 287 | GetPlayerFacing | done |
| 297 | InitRoamer | Ruby Latios lv40; `sRoamerLocations[Random()%20][0]` |
| 304 | CheckFreePokemonStorageSpace | PC boxes only; 0 is valid |
| 306 | DisplayCurrentElevatorFloor | `Now on:` + `0x8005` name |
| 309 | SetSootopolisGymCrackedIceMetatiles | VAR_TEMP bits → 0x20E |
| 281 | sub_80818A4 | orb flash 1→160 wait; pal 0x1F/0x7C00 + WIN0; no tiles |
| 282 | sub_80818FC | orb blend-out 186 frames; wait |
| 284 | WaitWeather | next-vblank wait after doweather |
| 311 | ScrSpecial_StartGroudonKyogreBattle | scripted wild + legendary + kyogre-groudon; wait |
| 312 | ScrSpecial_StartRayquazaBattle | scripted wild + legendary; wait |
| 313 | ScrSpecial_StartRegiBattle | scripted wild + legendary + regi; wait |
| 318 | sp13E_warp_to_last_warp | dest already set; no wait |
| 316 | FoundBlackGlasses | FlagGet 0x2B8; 0 is valid |
| 319 | DoFallWarp | hole warp + fall text; no wait |
| 324 | SetRoute119Weather | cycle if last warp is not outdoor |
| 325 | SetRoute123Weather | same; header is SUNNY |
| 332 | sub_8081924 | FadeOutBGM(4) then wait until BGM stopped |

## Script opcodes (IR)

Decoded + VM: most field flow, money box, fade, warps, setmetatile,
applymovement, trainerbattle, givemon, giveegg, berries, doors, cry, mart,
playslotmachine, coins, coin box, getpricereduction, setwildbattle,
dowildbattle, checkpartymove, bufferpartymonnick, buffermovename,
bufferdecorationname, adddecoration.

| Byte | Name | Notes |
| --- | --- | --- |
| 0x4B | adddecoration | `VarGet` id; RESULT 1/0; Game Corner dolls |
| 0x7A | giveegg | `VarGet` species; CreateEgg + GiveMonToPlayer; RESULT 0/1/2 |
| 0x81 | bufferdecorationname | slot u8, decor `VarGet` |
| 0x7C | checkpartymove | move u16 literal; RESULT slot or 6; 0x8004 = species |
| 0x7F | bufferpartymonnick | slot u8, party index `VarGet` |
| 0x82 | buffermovename | slot u8, move `VarGet` |
| 0xA3 | resetweather | sav1 = map header weather |
| 0xA4 | setweather | `VarGet` type; writes sav1 only |
| 0xA5 | doweather | copies sav1 → current (visual + battles) |
| 0x6D | waitbuttonpress | A/B; cached IR nops until re-import |
| 0x8B | choosecontestmon | wait; party pick; 0x8004 = 0-based slot |
| 0x8C | startcontest | wait; CB2_StartContest 5-round appeal engine (`Contest3.lua`) |
| 0x8D | showcontestresults | wait; A/B end wait |
| 0x77 | showcontestwinner | wait; painting id |
| 0x9F | setrespawn | `sHealLocations` 1–22; Centers write the outdoor door |
| 0x97 | fadescreen | `FADE_FRAMES` delay |
| 0x98 | fadescreenspeed | same as fadescreen; speed byte kept |
| 0x40 | setdivewarp | `gFixedDiveWarp`; Sootopolis has no dive connection |
| 0x89 | playslotmachine | u16 machine id (`VarGet`); pauses while the cabinet is open |
| 0x96 | getpricereduction | `VarGet` kind; RESULT 1 if PokéNews (always 0 until news) |
| 0xB6 | setwildbattle | species u16, level u8, item u16; no VarGet |
| 0xB7 | dowildbattle | starts that mon; `ScriptContext_Stop` until the fight ends |
| 0xB3 | checkcoins | writes GetCoins into the dest var |
| 0xB4 | addcoins | RESULT 0=ok 1=full (inverted vs additem) |
| 0xB5 | removecoins | RESULT 0=ok 1=not enough |
| 0xC0 | showcoinsbox | x, y tiles |
| 0xC1 | hidecoinsbox | args unused |
| 0xC2 | updatecoinsbox | args unused |
| 0x87 | pokemartdecoration | Fortree / Slateport; `AddDecoration`; no sell |
| 0x88 | pokemartdecoration2 | same shop (Lilycove 5F dolls via item ids) |
| 0x9C | dofieldeffect | `VarGet` id; FLDEFF 61 waitstates 21 frames |
| 0x9D | setfieldeffectargument | index u8, `VarGet` value into `gFieldEffectArguments` |
| 0x9E | waitfieldeffect | `SetupNativeScript` until inactive; missing effect continues |

`addcoins` RESULT polarity is **0 success**, opposite of `additem`.
`getpricereduction` needs a re-import; `PlayRoulette` 162 is already
decoded as `special` and does not. `setwildbattle` / `dowildbattle`
and `checkpartymove` / `bufferpartymonnick` / `buffermovename` /
`setweather` / `resetweather` / `doweather` / `setmaplayoutindex` /
`pokemartdecoration` 0x87 / `pokemartdecoration2` 0x88 /
`dofieldeffect` 0x9C / `setfieldeffectargument` 0x9D /
`waitfieldeffect` 0x9E / `waitbuttonpress` 0x6D need a re-import. Specials 171 / 298 are
already decoded as `special` / `specialvar`. Null-script
weather coords do not. Cached IR still nops newly decoded opcodes until
then.

## Flags / vars (grep these)

`FLAG_SYS_GAME_CLEAR` 0x804 — Hall of Fame; second HoF sets records.
`GAME_STAT_ENTERED_HOF` 10 — incremented when the team is recorded (cap 999).
`FLAG_SYS_POKEMON_LEAGUE_FLY` 0x854 — Ever Grande League ON_TRANSITION.
`FLAG_ENTERED_ELITE_FOUR` 0x107 — lobby guards.
`VAR_ELITE_4_STATE` 0x409C — Sidney 1 / Phoebe 2 / Glacia 3 / Drake 4.
`FLAG_DEFEATED_ELITE_4_SIDNEY` 0x4DD (`SYDNEY` in pokeruby) / PHOEBE 0x4DE /
GLACIA 0x4DF / DRAKE 0x4E0.
`GAME_STAT_FIRST_HOF_PLAY_TIME` 1 — packed hours<<16 \| min<<8 \| sec; 0 is unset.
`VAR_LILYCOVE_FAN_CLUB_STATE` 0x4095 — GameClear special 169 sets 1.
`FLAG_SET_WALL_CLOCK` 0x51 — story; bedroom then only *views* the clock.
`FLAG_SYS_CLOCK_SET` 0x835 — `InitTimeBasedEvents`; berries/day events.
`FLAG_SYS_HIPSTER_MEET` 0x806 — hipster script sets it; special 100/101 is the spoken flag.
`FLAG_SYS_TV_WATCH` 0x831 — set every map load; FlagClear if `FLAG_SYS_TV_START` and Gabby is airing.
`FLAG_SYS_TV_START` 0x832 — Mauville ON_TRANSITION; house TVs can air shows.
`FLAG_SYS_BRAILLE_WAIT` 0x851 — Island Cave / Regice wait.
`VAR_LOTTERY_PRIZE` 0x4045 / `VAR_LOTTERY_RND_L` 0x404B / `_H` 0x404C.
`FLAG_SYS_B_DASH` 0x860 — running shoes.
`FLAG_SYS_CTRL_OBJ_DELETE` 0x861 — ON_RESUME `removeobject VAR_LAST_TALKED`.
`FLAG_SYS_WEATHER_CTRL` 0x82A — drought over Sootopolis routes until Groudon.
`FLAG_LEGENDARY_BATTLE_COMPLETED` 0x71
`FLAG_LEGEND_ESCAPED_SEAFLOOR_CAVERN` 0x81
`VAR_SOOTOPOLIS_STATE` 0x405E
`VAR_CAVE_OF_ORIGIN_B4F_STATE` 0x409B
`FLAG_RUSTURF_TUNNEL_OPENED` 0xC7
`FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1` 0x3A3 / `_ROCK_2` 0x3A4
`VAR_RUSTURF_TUNNEL_STATE` 0x409A — smash rock 1 → 4, rock 2 → 5
`FLAG_SYS_CYCLING_ROAD` 0x82B — gate scripts after GetPlayerAvatarBike; `canBikeOn` allows indoor g29_11/g29_12
`FLAG_TRICK_HOUSE_END_ROOM` 0x259 (= FLAG_HIDDEN_ITEM_1)
`VAR_DAYS` 0x4040 — Pokerus decay + daily flags / Dewford / weather cycle / mirage / Birch / shoal / lottery after `FLAG_SYS_CLOCK_SET`.
`VAR_BIRCH_STATE` 0x4049 — `% 7` per day; InitBirchState (211) zeros it.
`VAR_SHROOMISH_SIZE_RECORD` 0x4047 / `VAR_BARBOACH_SIZE_RECORD` 0x404F — default `0x8100` (Marco).
`VAR_PACIFIDLOG_TM_RECEIVED_DAY` 0x40C2
`VAR_MIRAGE_RND_H` 0x4024 / `_L` 0x4025 — Mirage Island (PID low 16).
`FLAG_SYS_SHOAL_TIDE` 0x83A — Shoal Cave high tide.
`FLAG_SYS_SHOAL_ITEM` 0x85F — SetShoalItemFlag every day (items respawn).
`DAILY_FLAGS_START` 0x8C0 — 64 flags through 0x8FF; Route 114 berry `0x8CB`, Route 111 `0x8CC`.
`VAR_DEPT_STORE_FLOOR` 0x4043 — 0 is 1F; rooftop is 15
`FLAG_SYS_SAFARI_MODE` 0x82C
`VAR_SAFARI_ZONE_STATE` 0x40A4 — 1 = returning to the entrance
`GAME_STAT_ENTERED_SAFARI_ZONE` 17
`VAR_ICE_STEP_COUNT` 0x4022 — thin ice ++; cracked ice 0; ON_TRANSITION sets 1
`VAR_TEMP_0`..`F` 0x4000–0x400F — cleared on every map load (ice bits, gates)
`FLAG_MOSSDEEP_GYM_SWITCH_1` 0x64 / `_2` 0x65 / `_3` 0x66 / `_4` 0x67
`FLAG_MT_PYRE_ORB_STOLEN` 0x6F / `FLAG_EVIL_TEAM_ESCAPED_IN_SUBMARINE` 0x70
`FLAG_HIDE_GRUNT_1_BLOCKING_HIDEOUT` 0x335 / `_2` 0x336 (Harbor sets these)
`FLAG_HIDE_ELECTRODE_1_HIDEOUT` 0x3D1 / `_2` 0x3D2
`VAR_SLATEPORT_HARBOR_STATE` 0x40A0 / `VAR_MT_PYRE_STATE` 0x40B9
`VAR_CYCLING_CHALLENGE_STATE` 0x40A9
`VAR_0x8004` / `0x8005` — generic special args
`VAR_RESULT` 0x800D
`VAR_TEMP_0` 0x4000 — rotating-gate orients packed as bytes on cart;
  we keep `self.rotatingGateOrients` instead.

SYSTEM_FLAGS start 0x800.

## Items

`ITEM_MACH_BIKE` 259, `ITEM_COIN_CASE` 260, `ITEM_ITEMFINDER` 261,
`ITEM_WAILMER_PAIL` 268, `ITEM_DEVON_GOODS` 269, `ITEM_BASEMENT_KEY` 271,
`ITEM_ACRO_BIKE` 272, `ITEM_POKEBLOCK_CASE` 273, `ITEM_GO_GOGGLES` 279, `ITEM_DEVON_SCOPE` 288,
`ITEM_RED_ORB` 276.
Battle: Revive 24, Max Revive 25, Guard Spec 73, Dire Hit 74, X Attack 75,
X Defend 76, X Speed 77, X Accuracy 78, X Special 79, Poké Doll 80,
Fluffy Tail 81. Medicine/revive BAG A opens party; X/Dire/Guard Spec hit
the menu battler; Doll/Tail flee wild only.
Field USE leftovers: CannotUse is Dad's advice; Coin Case / Mail /
Pokéblock Case / TM boot+YES/NO / berry plant / Rare Candy stat pages.
Battle Ether opens party then the move list. Full storage is
`gOtherText_BoxIsFull`.
Key Items register on SELECT. Coins are not bag items; `self.coins`
0..9999 (`coins.c MAX_COINS`).

## Battle / field already in

EV yield from `gBaseStats` +0x0A (re-import to fill live cache).
Friendship, fadescreen = 16 frames, Macho Brace, Pokerus 2× EV.
Rotating gates: bump arm, collision==1 in sweep blocks; Lua 0-orient
ACW uses `ori ~= 0`. Mauville beams MapGrid x 7..15 y 12..23.
`switchTo` refuses eggs (`gOtherText_EGGCantBattle`); field SWITCH of
an egg into slot 1 is legal. Battle start still uses `firstHealthy`.

## Pitfalls

- Special id is line−11, not line−12.
- `mapMatches` is permissive on non-`gN_M` ids.
- `waitstate` continues if `scriptWaiting()` is false. Callback specials
  must `beginScriptWait` until the UI calls `endScriptWait`.
- `StartWallClock` default 10:00 (`wallclock.c` tHours=10, tMinutes=0).
  Confirm writes `RtcInitLocalTimeOffset` then `InitTimeBasedEvents`
  (`FLAG_SYS_CLOCK_SET`, `VAR_DAYS`).
- Existing saves that walked past Mom: `FLAG_SET_WALL_CLOCK` may be set
  while `FLAG_SYS_CLOCK_SET` is not (clock UI was a waitstate nop).
  Bedroom then only *views*. Do not secretly set the sys flag on view.
- `GetSlotMachineId`: `v0 = easyChatPairs[0] salt + table[0x8004]`, then
  `% 12` into payout-class 0-5. Discount table if `GetPriceReduction(2)`.
- Slot payouts `sSlotPayouts`: 2,4,0,6,12,3,90,300,300 for
  1cherry,2cherry,replay,lotad,azurill,power,777mix,777red,777blue.
  Left cherry alone pays 1CHERRY. Top/bottom upgrade 1CHERRY→2CHERRY.
  Replay pays 0 and free-spins.
- Rotating-gate `CheckForRotatingGatePuzzleCollision` only runs when
  dest metatile collision is already 0.
- CableCarWarp: `0x8004==0` → Mt Chimney station; nonzero → Route 112.
- Mauville old man type is `(trainerId % 10) / 2` (bard=0 … giddy=4).
  Bard id 0 is valid; `special` must still write `VAR_RESULT` (Lua 0 is
  truthy, and `after ~= before` would drop a 0 that was already 0).
- `PlayBardSong` / trader menus / storyteller list `beginScriptWait`.
  Bard 10:00 is the wall clock (154), not this man.
- `VAR_OBJ_GFX_ID_0` is also the rival. Do not set it from `Game3.new()`;
  Mauville Center ON_TRANSITION special 104 and NEW GAME wipe do.
- Roulette min bets are `{1, 3, 1, 6}` from `VAR_0x8004` bit0 = table
  and `+128` if `getpricereduction 2`. Six balls then the board clears.
  Payout is `minBet * multiplier` frozen at bet time. Consecutive wins
  (stat 29) is a high-water `SetGameStat`, not increment-each-win.
  Shroomish/Taillow drop bias is not ported. Bard 10:00 is still 154.
- `setwildbattle` is species/level/item literals (no VarGet). ITEM_NONE
  0 holds nothing (Lua 0 is truthy). `dowildbattle` increments stats 7
  and 8. Returning from battle runs ON_RESUME before the script
  continues, without clobbering `_scriptPause`.
- `checkpartymove` RESULT 0 is the lead slot (Lua 0 is truthy). 6 is
  `PARTY_SIZE` (nobody). Empty species **breaks** the loop; eggs are
  skipped. Move id is a literal, not VarGet.
- Rusturf is exact map id `g24_4`. Do not use `mapMatches` (stub ids
  that are not `gN_M` match any group/num).
- Smash wild is special 171 (`special`, must write RESULT). Rusturf is
  298 (`specialvar`). `dofieldeffect` / `waitfieldeffect` are sparkle,
  NPC fly-out, and HoF record (not waitstate).
- `setweather` writes sav1 only; `doweather` copies to current.
  Route 111 header is SUNNY (2); desert is SANDSTORM (8). Coord-event
  weather ids are not 1:1 after fog (coord 9 = sandstorm 8, coord 8 =
  ash 7). CONTINUE restores sav1 after `enterMap` so a desert save is
  not clobbered by the sunny header. Battle copies rain / sand / drought
  as permanent weather (`It is raining.` / `A sandstorm is raging.` /
  `The sunlight is strong.`). Field overlay is a tint, not ROM tiles.
- `trainerbattle_double` with an event_script is CONTINUE_SCRIPT_DOUBLE
  (kind 6), which already has an after-script pointer. Kind 4 DOUBLE
  has none. Gabby interview is kind 6.
- Gabby `battleNum` 0 is valid (Lua 0 is truthy). `quote == 0xFFFF` is
  empty, not 0. Easy Chat mode 10 writes 0xFFFF then one word.
  `GetGabbyAndTyLocalIds` has no case 0; BeforeInterview increments
  first (0→1 = Route 111 pair 1). Trivia 0 is valid.
- Trainer-eye rematches: Lua table is 1-based (`trainerRematches[30]`
  is Calvin). Specials 57/58 RESULT 0 is valid. Kind 5/7 must not skip
  because the first id is already defeated. Cindy is 1,3,4,5,6.
- `IsPokerusInParty` is the low nibble (`pokerus & 0xF`). Cured `0x10`
  is 0. EV yield still doubles on any nonzero byte. Infect is
  `Random() == 0x4000/0x8000/0xC000` after every non-link battle;
  spread is `Random() % 3 == 0` to adjacent slots with `!(pk & 0xF0)`.
  Day decay needs `FLAG_SYS_CLOCK_SET`.
- Size Compare RESULT 0 is valid (`0xFF` slot). Fan-club ShouldMove /
  GetNumMoved / Pacifidlog days / Enigma-in-party 0 are valid.
  Daycare selected nick 186 and received-mail 195 0 are valid.
- GameClear records the party (`SPECIES2`, eggs are 412) into up to 50
  HoF teams and increments stat 10. AccessHallOfFamePC 263 starts at
  the newest team; A walks older then closes; B closes. ChooseSend
  daycare B writes 255. Cinema 94 / 275 / 276 / 305 / 315 / 317 skip.
- `TRAINER_TYPE_BURIED` 3 is SEE_ALL directions, not one-way. Range 1
  is adjacent; same-tile does not count.
- `MOVEMENT_TYPE_HIDDEN` 0x3F hides the sprite but still occupies the
  tile (`npcAt` returns them). `MOVEMENT_TYPE_INVISIBLE` 0x4C also
  occupies and is talkable (`GetObjectEventIdByXY` does not skip it).
  Fortree / Route 119 Kecleon are INVISIBLE; the Devon 3F dummy is the
  same (the table metatile is already solid). Do not skip INVISIBLE in
  `npcAt`. Reveal of HIDDEN / TREE_DISGUISE 0x39 / MOUNTAIN_DISGUISE
  0x3A writes FACE_* (and template perm). `0x3C`/`0x3D` are
  `COPY_PLAYER_*_IN_GRASS`, not disguise. `clearObjectPerms` on enter
  reloads the ROM FACE_DOWN, then ON_TRANSITION buries again only if
  undefeated. Do not persist HIDDEN over FACE_DOWN after a win.
- `MOVEMENT_TYPE_FACE_DOWN_AND_UP` 0x0D through `FACE_DOWN_LEFT_AND_RIGHT`
  0x16 stay put. After `gMovementDelaysMedium` they pick a facing from
  the ROM table (`gDownAndLeftDirections` etc.). While the player is
  dashing in a Chebyshev box of `trainerRange`, NORMAL/BURIED trainers
  skip the wait and snap via `GetLimitedVectorDirection_*`. FACE_DOWN
  0x08 never turns. LOOK_AROUND 0x01 is still four-dir.
- `MOVEMENT_TYPE_ROTATE_COUNTERCLOCKWISE` 0x17 / `_CLOCKWISE` 0x18 stay
  put and turn every 48 frames (`gClockwiseDirections` S→W→N→E). Magma
  Hideout / Mt. Pyre trainers. Not rotating gates.
- Ruby Mossdeep gym (`g14_0`) is not Emerald's light-floor puzzle. It
  has two entrance warps. Red arrows `0x204/0x205/0x20C/0x20D` are walk
  pads `0x40–0x43` in pair_35. `setmetatile` changes the metatile id so
  `behaviorAt` follows the new pad dir. Switches are bg signs + flags
  `0x64–0x67` + DrawWholeMapView 142. `MB_MOSSDEEP_GYM_WARP` 0x0E is
  unused in pokeruby.
- Arrow warps (`0x62–0x65`, water-south `0x6D`, ship stairs `0x1B`,
  Shoal Cave `0x1C`) only warp when walking onto the tile from that
  direction. Do not treat them like doors.
- `MB_MT_PYRE_HOLE` 0x0F lands, then special **319** (`DoFallWarp`).
  Dest is the hole's warp event (`sub_8068C30`), not `gLastUsedWarp`.
  `sp13E` **318** is the same dest fade without the fall callback.
  Neither `beginScriptWait`s.
- `MB_AQUA_HIDEOUT_WARP` 0x67 is a walkable pad; generic `warpAt` on
  walk-into is the same dest as ROM land-then-fade.
- Route 119/123 headers are SUNNY (2). Specials **324/325** apply the
  rain cycle only when `GetLastUsedWarpMapType` is not outdoor (leaving
  Weather Institute). Connections do not update lastUsedWarp.
- Lilycove elevator exits are `MAP_DYNAMIC` 0x7F/0x7F. Walking in must
  `saved_warp2_set` the current map (source warp index + xy) when the
  **landing** warp dest is DYNAMIC. `dest_warp_id` 0 is valid; skip only
  NONE / DYNAMIC. Without that save, `followWarp` takes the DYNAMIC
  branch, `followDynamicWarp` fails, and you softlock. `setdynamicwarp`
  from the attendant overwrites after a floor pick. Floor 0 is 1F
  (Lua 0 is truthy). Rooftop is 15, not 5. `enterMap` clears flags
  0x1–0x1F (`FLAG_TEMP_2` skips SetFloor) and `VAR_TEMP_0..F`.
  `FLAG_TEMP_20` stays.
  Shake 273 must not `beginScriptWait` (`waitstate` is already a no-op).
- Sootopolis gym (`g15_0`) is cracked-ice stairs, not Emerald's ice
  maze. Callback 4 increments `VAR_ICE_STEP_COUNT` on thin ice (0x26)
  and zeros it on cracked ice (0x27). ON_FRAME at 8 / 28 / 69 opens
  stairs (`0x207`); at 0 `warphole` to B1F (`g15_1`) at the same xy.
  Do not `fallDownHole` to spawn when that ON_FRAME exists. Bits in
  `VAR_TEMP_1..A` (`gUnknown_083763E4`, x 3..13, y 6/7/8/9/12/13/14/17/18/19)
  persist only until the next map load. Special **309** paints 0x20E
  from those bits (CONTINUE / ON_LOAD). pair_36: thin 0x20D, cracked
  0x20E, broken 0x206. Space Center in Ruby is flavor + Sun Stone;
  there is no Magma attack.
- Cave of Origin B4F (`g24_42`) `setwildbattle` Groudon 45 then special
  **311** (`ScrSpecial_StartGroudonKyogreBattle`). Same as `dowildbattle`
  plus `BATTLE_TYPE_LEGENDARY | BATTLE_TYPE_KYOGRE_GROUDON`. Must
  `beginScriptWait`. Rayquaza **312** / Regi **313** are the same with
  legendary / regi. `CanRunFromBattle` does not block RUN. White-out on
  lose (`CB2_EndScriptedWildBattle`); win/run/catch continue the script
  (`GetBattleOutcome` 180). Cinema specials **281/282/284/332**
  (`sub_80818A4` / `sub_80818FC` / `WaitWeather` / `sub_8081924`) wait
  for the task then `ScriptContext_Enable`. `setmaplayoutindex` swaps `gMapLayouts[id-1]`
  (Route 131 → **320** Sky Pillar island after game clear; Route 130
  **46**/**264**; Shoal **165**/**169**). CONTINUE stores `mapLayoutId`.
  Sootopolis / underwater Sootopolis have no dive connection; ON_RESUME
  `setdivewarp` fills `gFixedDiveWarp`. Dest xy is the stored warp
  (9,6 / 29,53), not the player's tile. Seafloor Room 9 (`g24_36`)
  Maxie is `trainerbattle_no_intro`. `FLAG_SYS_WEATHER_CTRL` **0x82A**
  + `Common_EventScript_SetLegendaryWeather` is `setweather` drought
  (already in).
- Elite Four rooms (`g16_0` Sidney … `g16_4` Steven, HoF `g16_11`)
  close/open doors with `setmetatile` (frame **0x344** / opening
  **0x345**). `VAR_ELITE_4_STATE` **0x409C** is not a temp var. Sidney
  / Phoebe / Glacia / Drake / Steven are `trainerbattle_no_intro`.
  Hall of Fame `fadescreenspeed` then special **GameClear** **272**.
  Heal, `FLAG_SYS_GAME_CLEAR` **0x804**, first HoF time (stat 1, **0**
  is unset), Champion ribbon (skip eggs / empty / already-ribboned),
  bedroom heal, warp home. Do not `beginScriptWait`. Second HoF sets
  `hasHallOfFameRecords`. Fan club special **169** ORs bit 7 of
  `VAR_FANCLUB_UNKNOWN_1`; skip if that bit is set. `fadescreenspeed`
  **0x98** is the same delay as `fadescreen` (needs re-import).
- House TV after HoF: special **73** must return 1 on the matching
  gender's Littleroot 1F (`g1_0` / `g1_2`) when `FLAG_SYS_TV_LATI`
  **0x85D** is set. `InitRoamer` **297** is Ruby Latios 408 lv40.
  Grass/surf that pass the rate roll then `Random()%4==0` start the
  roamer instead of the slot; Repel TRUE does not fall through. Win
  / catch deactivate; run banks HP and jumps maps. `enterMap` runs
  `RoamerMove` (CONTINUE skips so the route persists).
- SS Tidal: specials **203/204** set/clear `FLAG_SYS_CRUISE_MODE`
  **0x82D**. Walk steps `CountSSTidalStep`; **0** and **204** (`0xCC`)
  are still sailing (Lua 0 is truthy). Step **205** is
  `gUnknown_0815FD0D`. Porthole **270** waitstates: FlagSet cruise,
  `portholeReturn`, warp to GetSSTidalLocation (Routes 134/133/132 at
  y=20). A or 0xCD steps (state **9** / **10**) warp back. Harbor lists
  **52** / **56**. White-out clears cruise.
- `setmaplayoutindex` **0xA7** is `VarGet` then `sub_8053D14`. LoadMap
  resets from the header, ON_TRANSITION may swap. Extra layouts (320,
  46, 169/170, 313, 327) live in `data/generated/layouts.lua` after
  re-import. Specials **209** / **210** are Mirage Island (PID low 16
  vs `VAR_MIRAGE_RND_H`) and Shoal tide (outdoor last warp, hour table).
- Overheat's Sp. Atk drop is AFFECTS_USER | CERTAIN. Clear Body does
  not block it. Crits skip Reflect / Light Screen. Attract's 50% lock
  is `Random() & 1` (even immobilizes). Flail scale is 48, not 64.
- Muddy slope: Mach climbs only while holding up. Idle Mach still
  slides. Slide is one tile per cycle at run speed, facing locked.
  `MB_BUMPY_SLOPE` 0xD1 is not a slide.
- `MB_HOT_SPRINGS` **0x28** is walkable land, not surf. No-surfacing
  water is **0x19**; seaweed no-surfacing is **0x2A**. Unused **0x18**
  is not water. Gym pads are B1F **0x29** and 1F **0x68**.
- Ice (`0x20`) / Trick House 8 (`0x48`) slip in `movementDirection` at
  run speed. A wall stops the slip so the keypad can turn. Walk pads
  `0x40–0x43` are walk speed; slide pads `0x44–0x47` lock facing at run
  speed. Currents `0x50–0x53` are surfable and ride Speed2. Waterfall
  stays climb-only (do not force south).
- Safari balls are `gNumSafariBalls`, not the bag. `EnterSafariMode` 205
  does not `beginScriptWait`. Step remaining **0** is time-up (Lua 0 is
  truthy). Last-ball miss is outcome 8 and warps immediately; last-ball
  catch is outcome 7 then the out-of-balls message. START has RETIRE
  and no SAVE. Feeder special 207 returns 0xFFFF until feeders exist.
  `CheckFreePokemonStorageSpace` 304 is PC boxes only (party is
  `getpartysize`). Battle menu is BALL / POKeBLOCK / GO NEAR / RUN.
- Forecast only forms SPECIES_CASTFORM. Sandstorm reverts. Cloud Nine
  / Air Lock revert. Types are battle-only: restore from the species
  row on switch-out and battle end. `givemon` third operand is the
  held item (Castform's Mystic Water 209).
- Color Change (16) does not require contact. Skip Struggle, power 0,
  immunity / miss / faint, and already-that-type. Both types become
  the move type. Restore from the species row like Forecast.
- Endeavor (189) fails if user HP ≥ target HP **before** accuracy
  (Fly is a miss only when the HP check passes). Damage is
  targetHP − userHP; no STAB / screens / crit / roll. Ghost immunity
  still applies. Endure can leave 1.

## Oracle commands

```
python tools/gba_oracle/check_specials.py
python tools/gba_oracle/newgame.py "Pokemon - Ruby Version (USA).gba"
python tools/gba_oracle/snapshot.py "Pokemon - Ruby Version (USA).gba" --state tools/gba_oracle/states/newgame.state --advance 1500 --keys down --delta
```

`SaveBlock1.pos` updates on map transition, not every step. Live xy is
`gObjectEvents[0]`.

## Tests

```
luajit tests/engine/ruby_battle_test.lua
luajit tests/engine/ruby_map_test.lua
luajit tests/engine/ruby_boot_test.lua
luajit tests/engine/ruby_sprite_test.lua
luajit tests/engine/ruby_save_test.lua
```

## Phase one-liners (latest first)

254 Party gender + double layout: `monGender` stamps 0x42/0x44; genderless skips; battle doubles use two lead boxes (`gUnknown_083769A8` row 1). Link-double tables unused
253 Dex screens + catch nickname: INFO/AREA/CRY/SIZE bar; size silhouettes use `pokemonScale`/`trainerScale` (256/PA); catch overlay cry then `trygivecaughtmonnick`
252 TradeEvolutionScene: after in-game trade take-care A, `GetEvolutionTargetSpecies` type 1; cannot B-cancel; `EVO_TRADE_ITEM` zeros the hold
251 Pokéball glow pal pulse: `MultiplyInvertedPaletteRGBComponents` `{16,12,8,0}` R/G during glow stages 2–3; B stays 0
250 Ruby launcher slots: Game3 SAVE/CONTINUE use `saves/ruby/`; `save3_ruby.lua` migrates; slotSummary reads playerName/playSeconds; GBA .sav import/export still refused
249 Region-map zoom / Fly icons / landmarks: PokéNav A is 16-frame 2× affine; Fly is the painted map with town icons; `sub_80FB758` + `GetLandmarkName`
248 Contest engine: `gContestMoves`/`gContestEffects`/`gContestOpponents`, `CalculateAppealMoveImpact` + 48 effects, combo/jam/nervous/excitement, round-1 condition, `DetermineFinalStandings`. START still aborts the hall.
247 Pokécenter heal OBJs billboard: CreateSprite centre through gbaScreenToWorld then drawStandingAt so tilt/zoom sits the balls on the machine
246 Cycling-road gates keep the bike: `Overworld_IsBikingAllowed` allows indoor g29_11/g29_12 before the indoor reject; Room9/B4F still refuse
245 Ripe berry-tree frames: skip 16×16 dirt/sprout prefix on gfx 62; six 16×32 bushes (`ow_62.png`) (ruby41)
244 OPTION GAME SPEED: OVERWORLD / BATTLE / MENU rows (Gen 1 ladder); logic clock only; 1 / shoulders cycle the active category
243 Pokédex list + catch `displaydexinfo`: `gPokedexEntries` 0x3B1858 + species↔dex maps 0x1FC1E0; A opens the entry; first catch shows AddedToDex then the overlay (ruby40)
242 FIGHT SELECT reorders moves: dest cursor, Switch which?, A/SELECT swap, B cancel (`battle_controller_player.c`)
218 Field bugs: NEW GAME has no POKe BALLs; lock does not freeze facing (Wally); small maps keep the player at 120,80; Absorb looks up effect by id; nurse runs the ROM script; string vars tostring; berries tick in RTC minutes; waitfanfare times out; OW water reflections
220 Pickup holds the find (empty hold slot, silent); Air Lock is ability 77 not 76
223 Remaining RS abilities: Speed Boost / Sturdy / Battle Armor / Shell Armor / Damp / Effect Spore / Cute Charm / Soundproof / Pressure / Hustle / Plus / Minus / Suction Cups; Explosion (effect 7) and Roar (effect 28)
227 Cable car tiles: gCableCarBG_Gfx 0xE7EC3C + mountain/tree/pylon/chimney maps; car/door/cord OBJs; HOFS/VOFS from sub_81239E4 (ruby33)
228 Field-effect cinema: dofieldeffect / waitfieldeffect (sparkle 48, NPCFLY 32, HoF record); EndTrainerApproach 1-frame wait
229 Watering / elevator / sealed-chamber / Route 128 cinema: waitstate shakes and BLDY flash; watering gfx is 191/192 (ruby37)
231 Braille wait / lottery laptop / porthole: 280 waits 7200+30; 217 blinks 7×5 no wait; 270 ocean view waitstate
230 Egg hatch tiles: sEggHatchTiles 0x209AF8 four 32x32 frames + trade GBA BG; SpriteCB_Egg_0..5 wobble then front pic (ruby34)
233 Camera dummy / PC blink / Cable Club warp / records: 275 follows local 127; 214 blinks 7×5; 2/3 wait FADE then warp; 196/283 field UI no wait
232 Egg hatch shards + white fade: sEggShardVelocities Q_8_8; Egg_4 pal fade; Egg_5 affine 0x28+0x12x12; shard anim is vid%4 not Random()
237 setrespawn all 22 heal locations: Center ON_TRANSITION writes the outdoor door; stale bedroom CONTINUE warps to the furthest visited Center
241 Contest hall unstuck: START warps LinkContestRoom1 to the 15FB64 lobby; B skips appeals; movement delay still waits while the player is hidden
240 Painted region map: 8bpp affine BG2 0x3E5DA0 + 64×64 map; cursor/player OBJs; D-pad 28×15 MAPSEC cells (ruby39)
239 HoF / Center pokéball glow 4bpp: 8×8 pal 04 + HoF 64×16/32×16 pal 05 + Center 24×16 pal 00; screen-space CreateSprite xy (ruby38)
238 Watering can 4bpp: OBJ_EVENT_GFX_BRENDAN/MAY_WATERING 191/192; special 94 still 11×16 walk-in-place (ruby37)
236 Rotating-gate 4bpp: 8 shapes + OBJ pal 5 (tag 0x1108); affine 0/-64/-128/+64 at tile top-left; orb wash is RGB555 0x1F/0x7C00 (no orb tiles) (ruby36)
235 TV metatiles / secret-base PC / waitbuttonpress: 62 snaps TV_Off; FLDEFF 61 21-frame wait; 26 Off; 0x6D A/B (cached IR nops)
234 In-game trade cable cinema: cable_closeup + gba_affine + glow/ball OBJs; timed DoTradeAnim_Cable; swap on take-care A (ruby35)
225 Heal Bell / Perish Song / Uproar / Ingrain; Soundproof skips Heal Bell (not Aromatherapy) and Perish Song; Uproar is the sound-move lock; Trace then ABILITYEFFECT_IMMUNITY
217 Field medicine party picker: BAG USE opens OtherText_UseWhat; Revive no longer auto-picks the first legal mon
219 Field vitamins / Rare Candy / PP / stones / Sacred Ash: party picker, move submenu, ITEM_USE_ALL_MONS ash
221 Remaining bag/battle item uses: Dad's advice, Coin Case, Mail, Pokéblock Case, berry plant, TM boot + YES/NO, Rare Candy stat pages, battle Ether move list, gOtherText_BoxIsFull
222 Cable car cinema: special 152 waits unk_0004 frames (0x15e up / 0x109 down) then WarpIntoMap; MUS_CABLE_CAR 425; mountain tiles still unextracted
224 Egg hatch + in-game trade cinema: EggHatch 194 waitstate (stat 13 is TakeStep); CreateInGameTradePokemon fills incoming; DoInGameTradeScene swaps
226 Cave of Origin cinema: WaitWeather 284 / orb 281-282 / fade-out-music 332 / ShakeCamera 310 wait; orb is pal+WIN0 (no tiles)
216 Roxanne Stone Badge after a starter evo: TryEvolvePokemon then gotobeatenscript; CONTINUE_SCRIPT after uses .entry
- 213 Font 4, the party menu's small text: sFontType1Map 0x1E5FF0 resolves characters onto the gFont4LatinGlyphs pool 0xEA6BC4, so nicknames, levels and HP print 8 pixels tall instead of 16 (ruby32)
- 214 Party menu chrome finished: gPartyMenuOrderText_Gfx 0xE71934 supplies the Lv tile 0x40 and the gender symbols 0x42/0x44, and CHAR_SLASH is 0xBA not the hyphen 0xAE (ruby32)
- 215 Held item icons: MenuGfx_HoldIcons 0x37657C found by repacking the decomp png into GBA 4bpp, two frames picked by ItemIsMail, parented to the mon icon at +16/+22 (ruby32)
211 Sound effects, fanfares and cries: four Mp2kAudio voices, gCryTable 0x452590 + species mapping, launcher volume (ruby30)
210 MP2K player: sequencer + mixer, map/battle/boot music, playbgm and the three fade opcodes wired
209 MP2K audio extractor: gSongTable + 416 songs, 114 voicegroups, 128 samples shipped as one 2.5 MB verbatim span (ruby29)
206 Boot cinema: affine 8bpp title logo + glow Groudon; intro1 VOFS + GAME FREAK; intro2 scroll (re-import)
207 Window chrome from the cart: 20 text-window frames, dialogue box, battle textbox tilemap, healthbox elements (ruby28)
208 Battle UI from the cart: message/action/move bars, both healthbox frames, move select is a 2x2 grid
205 ROM boot stills: copyright / intro1 / intro2 / title PNGs from LZ77 (re-import)
204 FONT3 widths + ROM menu tiles; field box (2,15); START (22,0,29,n*2+3)
203 Gym-guide freeze: typewriter is per 2-line box; `\l` 0xFA; TEXT_LEN 1024 (re-import)
202 Flutes: White/Black encounter flags; Blue/Yellow/Red reusable; bike/Cleanse/Stench/Illuminate; LoadMap FlagClear
201 Daily `UpdatePerDay`: flags 0x8C0–0x8FF, Dewford, weather cycle, mirage, Birch, shoal, lottery; InitBirchState 211
199 Lavaridge Herb Shop medicines + Mt. Chimney Lava Cookie; pokemartdecoration 0x87/0x88
200 Cable Club no-link RESULT 5; Battle Tower lobby idle; secret-base PC skip; Teala script
198 Daycare nick/mail 186/195/181; HoF PC 263 + GameClear records 50 teams; cinema 94/275/276/305/315/317 skip
197 Pokerus infect/spread/decay; Pacifidlog TM 333/334; size 119-122; fan club 163-168/170; diploma 264; Enigma 50/339; Southern Island 323
196 Trainer-eye rematches: 5 badges, 255 steps, 31% on enter map; specials 57-59
195 Field poison / whiteout money/2 / SaveGame 93 / trainer EventScript 51-56/61
192 Contest hall + blender + PokéNav + script PC: participate 0-4, gfx ids, pokeblocks 160/161, region map 251
191 Lilycove Move Deleter: SelectMove 220 wait, DeleteMonMove 221 (HMs ok), Count 223
190 Castform/Lileep/Anorith pics seeded; EggHatch 194 waitstate; FoundBlackGlasses 316
189 Fallarbor Move Relearner: SelectMoveTutorMon 219, DisplayMoveTutorMenu 224, GetMoveTutorMoves
188 Lavaridge `giveegg` 0x7A Wynaut; Glass Workshop special 274; `adddecoration` / callstd 7
187 Sceptile pics: evo collect walks full chains; TryEvolvePokemon only after B_OUTCOME_WON
186 Lavaridge: MB_HOT_SPRINGS 0x28 is land; no-surfacing is 0x19 / seaweed 0x2A
185 Route 111 two west connections: GetIncomingConnection range, not first-match (113 then 112)
184 Route 111 Winstrate fence: COVERED tops paint with the ground (dirt bottom + BG2 posts)
183 Winstrate: later trainerbattle_no_intro after removeobject hide; Route 111 ruins setmetatile keeps elevation
182 Battle items: party target, Revive/Max Revive, X items, Dire Hit, Guard Spec mist, Doll/Tail flee
181 Sky Pillar setmaplayoutindex 0xA7; layouts.lua; Mirage 209; Shoal tide 210
180 SS Tidal: Set/Reset 203/204, 205 steps, porthole 270 skip, harbor lists 52/56
179 Latios roamer: TV 73 + InitRoamer 297; overlay on grass/surf; CONTINUE keeps map
178 GameClear 272 / fan club 169 / fadescreenspeed 0x98; Champion ribbon; warp home
177 Groudon 311 + setdivewarp; cinema 281/282/284/332 wait (phase 226); no cache bump
176 Sootopolis ice: VAR_ICE_STEP_COUNT on callback 4; special 309; temp vars clear on load
175 FACE_DOWN_AND_* 0x0D–0x16 look + dash snap; Mossdeep arrows are walk pads 0x204/0x20C
174 Mt. Pyre hole 0x0F / DoFallWarp 319; hideout pad 0x67; arrow warps; rotate 0x17/0x18; 324/325
173 Safari Zone: Enter/Exit 205/206, 30 balls / 500 steps, BALL/GO NEAR, no SAVE
172 ice / currents / walk-slide pads; currents surfable; Pokéblock Case 273
171 Lilycove elevator: inbound MAP_DYNAMIC save, specials 216/273/306, temp flags 0x1–0x1F
170 Fortree Winona: Endeavor 189 + TM40 Aerial Ace
169 Route 119 / Fortree Kecleon: INVISIBLE collides, tree/mountain 0x39/0x3A, Color Change, Devon Scope
168 Weather Institute: Forecast / Weather Ball / givemon item
167 muddy slope 0xD0: Mach+up climbs, else slide south
166 Flannery Overheat 204 / screens / Attract / Flail
165 Lavaridge gym HIDDEN 63 / BURIED / Go-Goggles
164 Route 111 Gabby & Ty interview 172-180
163 Route 111 sandstorm setweather 0xA3–0xA5
162 Rock Smash script path 0x7C / 171 / 298
161 setwildbattle 0xB6 / dowildbattle 0xB7
160 PlayRoulette 162 + getpricereduction 0x96
159 Mauville old man 97-118
158 clock + coins + slots
157 rotating gates, HasEnoughMoneyFor, GetSlotMachineId
194 house TVs / Gabby show / lottery / ship keys / Pokerus / Grass / Regice wait
193 Norman gym sliding doors: sign bg, not bump-warp; A-press lock
     (Accuracy+ doors: parse entry / lockall heuristic, not ops[1] EnterRoom)
     YES/NO waits for leftover dialogue pages (waitmessage then yesnobox)
156 SELECT, Norman doors, Trick House 0x259, cable car
155 Mauville gym beams
154 EV yield from KOs
153 friendship, fadescreen 16, SwapRegisteredBike
(see gen3-phase1.md for 1-152)
