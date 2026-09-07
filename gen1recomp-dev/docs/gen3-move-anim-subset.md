# Gen3 Ruby move-animation subset (wave 5)

Scaffold for ROM-accurate move FX in Game3. Does **not** use Gen1
`data/generated/battle_anims.lua` / `src/battle/AnimPlayer.lua`.

## ROM call path (read before this work)

1. `data/battle_scripts_1.s` — `attackanimation` / `waitanimation`
2. Controllers emit `CONTROLLER_MOVEANIMATION` (`BtlController_EmitMoveAnimation`)
3. `*HandleMoveAnimation` → `DoMoveAnim(move)` in `src/battle_anim.c`
4. `DoMoveAnim` → `LaunchBattleAnimation(gBattleAnims_Moves, move, TRUE)`
5. `sBattleAnimScriptPtr = gBattleAnims_Moves[move]` → `RunAnimScriptCommand`
6. Scripts live in `data/battle_anim_scripts.s` (`Move_POUND`, `Move_EMBER`, …)
7. Two-turn moves use `choosetwoturnanim charge, hit` (Dig/Fly/Dive/Solar Beam/Skull Bash).
   Brick Break reuses that opcode for no-screen vs screen-shatter paths.

## Engine wiring

| Piece | Location |
|-------|----------|
| Player module | `src/core/Game3MoveAnim.lua` |
| Hook | `Game3MoveAnim.attach(Game3)` from `Game3.lua` |
| Arm | wraps `Game3:armMoveAnim` — scripted moves set `b.moveAnim.ruby`; `kind=="charge"` selects `chargeFx`/`chargeFrames` |
| Draw | wraps `Game3:drawMoveAnimBurst` → scripted FX |
| Shake/lunge | wraps `Game3:battlerTopLeft` with `MA.offsetsFor` |
| Hide | `drawBattle` skips battler pic while `mon.invuln` (fly/dig/dive) |
| Shatter | `breakScreens` sets `b.brickBreakShatter` for Brick Break wall-tear FX |
| Fallback | unimplemented moves keep generic typed burst (0.42s / 0.32s) |

Damage is still applied **before** the anim (existing Game3 order). Text
queues immediately; `animT` / `moveAnim.dur` only drive visuals. Transitions,
send-out, catch, money, and toxic *damage-tick* paths are untouched (Toxic
**move** FX is scripted here; residual Toxic HP ticks are separate).

Palette-0 alpha keying + `SHEET_OBJ_ALPHA` (0.72) remain on sheet draws.
`SE_M_*` plays on arm via `playSe(seId)` (Growl still uses cry).

## Coverage (135 moves = 102 prior + 33 wave-5 new IDs; 31 scripts)

### Waves 1–3 (kept)

Pound, Tackle, Scratch, Ember, Water Gun, Vine Whip, Absorb, Thunder Shock,
Quick Attack, Growl, Tail Whip; Mud-Slap, Sand-Attack, Rock Throw, Bubble,
Bubblebeam, Razor Leaf, Bite, String Shot, Harden, Leer, Gust, Peck, Wing
Attack, Mega Drain, Fire Spin, Flamethrower, Confusion, Psybeam, Rock Smash,
Poison Sting, Poison Powder, Stun Spore, Sleep Powder, Headbutt, Body Slam,
Take Down, Strength, Cut, Aerial Ace, Metal Claw, Protect, Rest, Toxic, Dig
(two-turn), Surf, Hyper Beam, Double Team; Magnitude, Brick Break, Bulk Up,
Calm Mind, Shadow Ball, Earthquake, Hydro Pump, Ice Beam, Thunderbolt,
Thunder, Blizzard, Psychic, Crunch, Dragon Claw, Slam, Facade, Return,
Frustration, Hidden Power, Overheat, Eruption, Focus Punch, Revenge,
Endeavor, Fake Out, Will-O-Wisp, Thunder Wave, Attract, Safeguard, Light
Screen, Reflect, Spikes — see `Game3MoveAnim.lua` for ROM VAs / frames / SE.

### Wave 4 — new (22)

| Move | ROM script | Frames | Sec | FX id | Primary SE |
|------|------------|--------|-----|-------|------------|
| Solar Beam (hit) | `Move_SOLAR_BEAM @ 81CED65` | 90 | 1.50 | `solar_beam_hit` | SE_M_SOLAR_BEAM (201) |
| Solar Beam (charge) | same choosetwoturnanim | 50 | 0.83 | `solar_beam_charge` | SE_M_MEGA_KICK (140) |
| Fly (hit) | `Move_FLY @ 81D046F` | 40 | 0.67 | `fly_hit` | SE_M_RAZOR_WIND (136) |
| Fly (charge) | same | 30 | 0.50 | `fly_charge` | SE_M_FLY (158) |
| Dive (hit) | `Move_DIVE @ 81D49A5` | 55 | 0.92 | `dive_hit` | SE_M_EXPLOSION (178) |
| Dive (charge) | same | 45 | 0.75 | `dive_charge` | SE_M_DIVE (233) |
| Skull Bash (hit) | `Move_SKULL_BASH @ 81CB38F` | 55 | 0.92 | `skull_bash_hit` | SE_M_TAKE_DOWN (152) |
| Skull Bash (charge) | same | 48 | 0.80 | `skull_bash_charge` | SE_M_TAKE_DOWN (152) |
| Softboiled / Recover | `Move_RECOVER @ 81D1F1F` / `Move_SOFT_BOILED @ 81D213B` | 70 | 1.17 | `recover` | SE_M_MEGA_KICK (140) |
| Swords Dance | `Move_SWORDS_DANCE @ 81C8EA4` | 50 | 0.83 | `swords_dance` | SE_M_SWORDS_DANCE (191) |
| Dragon Dance | `Move_DRAGON_DANCE @ 81CD7F8` | 70 | 1.17 | `dragon_dance` | SE_M_TELEPORT (203) |
| Rain Dance | `Move_RAIN_DANCE @ 81CE997` | 80 | 1.33 | `rain_dance` | SE_M_RAIN_DANCE (127) |
| Sunny Day | `Move_SUNNY_DAY @ 81D0B91` | 70 | 1.17 | `sunny_day` | SE_M_PETAL_DANCE (202) |
| Sandstorm | `Move_SANDSTORM @ 81D0304` | 70 | 1.17 | `sandstorm_move` | SE_M_SANDSTORM (219) |
| Hail | `Move_HAIL @ 81CC076` | 70 | 1.17 | `hail_move` | SE_M_HAIL (242) |
| Rapid Spin | `Move_RAPID_SPIN @ 81CBD41` | 55 | 0.92 | `rapid_spin` | SE_M_RAZOR_WIND2 (160) |
| Explosion / Selfdestruct | `Move_EXPLOSION @ 81C9675` / `Move_SELF_DESTRUCT @ 81C9219` | 90 | 1.50 | `explosion` | SE_M_EXPLOSION (178) |
| Destiny Bond | `Move_DESTINY_BOND @ 81CBA2C` | 80 | 1.33 | `destiny_bond` | SE_M_PSYBEAM (189) |
| Counter | `Move_COUNTER @ 81D08AC` | 40 | 0.67 | `counter` | SE_M_VITAL_THROW2 (123) |
| Mirror Coat | `Move_MIRROR_COAT @ 81CE506` | 45 | 0.75 | `mirror_coat` | SE_M_BARRIER (208) |
| Metronome | `Move_METRONOME @ 81CB365` | 40 | 0.67 | `metronome` | SE_M_METRONOME (186) |
| Splash | `Move_SPLASH @ 81CB720` | 50 | 0.83 | `splash` | SE_M_TAIL_WHIP (167) |
| Struggle | `Move_STRUGGLE @ 81CB815` | 40 | 0.67 | `struggle` | SE_M_COMET_PUNCH (139) |
| Transform | `Move_TRANSFORM @ 81D3054` | 50 | 0.83 | `transform` | SE_M_TELEPORT (203) |

### Wave 4 — upgrades (3)

| Move | Change |
|------|--------|
| Dig | True two-turn: `dig_charge` (40f) on charge arm + `dig_hit` (50f) on finish; `mon.invuln="dig"` hides sprite between turns |
| Brick Break | Screen-shatter path when Reflect/Light Screen were up (`b.brickBreakShatter` → wall + TORN_METAL shards + SE_M_BRICK_BREAK) |
| Focus Punch | Compressed charge windup (darken+fist 0–28f) + multi-splat hit (~100f total) |


### Wave 5 — new (31 scripts / 33 move IDs)

Two-turn peers + high-traffic missing moves. Charge arms use `chargeFx` /
`chargeFrames` / `kind=="charge"` (same as Dig/Fly/Solar Beam). Bounce shares
`EFFECT_FLY` invuln hide with Fly; Sky Attack / Razor Wind do **not** hide.

| Move | ROM script | Frames | Sec | FX id | Primary SE |
|------|------------|--------|-----|-------|------------|
| Sky Attack (hit) | `Move_SKY_ATTACK @ 81CB57B` | 55 | 0.92 | `sky_attack_hit` | SE_M_VITAL_THROW2 (123) |
| Sky Attack (charge) | same choosetwoturnanim | 55 | 0.92 | `sky_attack_charge` | SE_M_STAT_INCREASE (239) |
| Bounce (hit) | `Move_BOUNCE @ 81D04D9` | 40 | 0.67 | `bounce_hit` | SE_M_MEGA_KICK2 (141) |
| Bounce (charge) | same | 30 | 0.50 | `bounce_charge` | SE_M_TELEPORT (203) |
| Razor Wind (hit) | `Move_RAZOR_WIND @ 81D1E0B` | 45 | 0.75 | `razor_wind_hit` | SE_M_RAZOR_WIND (136) |
| Razor Wind (charge) | same | 40 | 0.67 | `razor_wind_charge` | SE_M_GUST (132) |
| Tri Attack | `Move_TRI_ATTACK @ 81D2A0F` | 85 | 1.42 | `tri_attack` | SE_M_TRI_ATTACK (220) |
| Superpower | `Move_SUPERPOWER @ 81CC3A3` | 60 | 1.00 | `superpower` | SE_M_MEGA_KICK (140) |
| Iron Tail | `Move_IRON_TAIL @ 81D18B6` | 50 | 0.83 | `iron_tail` | SE_M_VITAL_THROW2 (123) |
| Crabhammer | `Move_CRABHAMMER @ 81D0159` | 50 | 0.83 | `crabhammer` | SE_M_VITAL_THROW2 (123) |
| Dynamic Punch | `Move_DYNAMIC_PUNCH @ 81D07E4` | 55 | 0.92 | `dynamic_punch` | SE_M_COMET_PUNCH (139) |
| Cross Chop | `Move_CROSS_CHOP @ 81D058E` | 55 | 0.92 | `cross_chop` | SE_M_MEGA_KICK (140) |
| Megahorn | `Move_MEGAHORN @ 81CFDAC` | 50 | 0.83 | `megahorn` | SE_M_HORN_ATTACK (166) |
| Extremespeed | `Move_EXTREME_SPEED @ 81CBE3E` | 55 | 0.92 | `extremespeed` | SE_M_RAZOR_WIND2 (160) |
| Ancient Power | `Move_ANCIENT_POWER @ 81D0EE5` | 60 | 1.00 | `ancient_power` | SE_M_TAKE_DOWN (152) |
| Future Sight | `Move_FUTURE_SIGHT @ 81CDD2D` | 70 | 1.17 | `future_sight` | SE_M_PSYBEAM (189) |
| Wish | `Move_WISH @ 81D2D66` | 70 | 1.17 | `wish` | SE_M_MILK_DRINK (225) |
| Ingrain | `Move_INGRAIN @ 81D255A` | 55 | 0.92 | `ingrain` | SE_M_TAKE_DOWN (152) |
| Helping Hand | `Move_HELPING_HAND @ 81CC2BF` | 45 | 0.75 | `helping_hand` | SE_M_SWAGGER (193) |
| Follow Me | `Move_FOLLOW_ME @ 81CC1B1` | 40 | 0.67 | `follow_me` | SE_M_ATTRACT (226) |
| Yawn | `Move_YAWN @ 81CC697` | 55 | 0.92 | `yawn` | SE_M_YAWN (237) |
| Slack Off / Refresh | `Move_SLACK_OFF @ 81CCF23` / `Move_REFRESH @ 81D3485` | 60 | 1.00 | `slack_off` | SE_M_MEGA_KICK (140) |
| Arm Thrust | `Move_ARM_THRUST @ 81D36CF` | 55 | 0.92 | `arm_thrust` | SE_M_COMET_PUNCH (139) |
| Smelling Salt | `Move_SMELLING_SALT @ 81CC156` | 45 | 0.75 | `smelling_salt` | SE_M_VITAL_THROW2 (123) |
| Double-Edge / Submission | `Move_DOUBLE_EDGE @ 81C817A` / `Move_SUBMISSION @ 81D0AEE` | 55 | 0.92 | `double_edge` | SE_M_TAKE_DOWN (152) |
| Trick | `Move_TRICK @ 81D2CE8` | 50 | 0.83 | `trick` | SE_M_SKETCH (205) |
| Imprison | `Move_IMPRISON @ 81CC867` | 50 | 0.83 | `imprison` | SE_M_DETECT (209) |
| Grudge | `Move_GRUDGE @ 81CC8AA` | 55 | 0.92 | `grudge` | SE_M_PSYBEAM (189) |
| Snatch | `Move_SNATCH @ 81D498B` | 40 | 0.67 | `snatch` | SE_M_SWAGGER (193) |
| Skill Swap | `Move_SKILL_SWAP @ 81CC81C` | 50 | 0.83 | `skill_swap` | SE_M_TELEPORT (203) |
| Role Play | `Move_ROLE_PLAY @ 81D3428` | 50 | 0.83 | `role_play` | SE_M_TELEPORT (203) |
| Camouflage | `Move_CAMOUFLAGE @ 81CC8D2` | 45 | 0.75 | `camouflage` | SE_M_DETECT (209) |
| Recycle | `Move_RECYCLE @ 81CC45E` | 45 | 0.75 | `recycle` | SE_M_SWAGGER (193) |
| Assist | `Move_ASSIST @ 81CC332` | 40 | 0.67 | `assist` | SE_M_ATTRACT (226) |

### Shared helpers (wave 5)

| Helper / flag | Used by |
|---------------|---------|
| `chargeFx` / `chargeFrames` / `kind=="charge"` | Sky Attack, Bounce, Razor Wind (+ Dig/Fly/Dive/Solar Beam/Skull Bash) |
| `mon.invuln="fly"` hide | Bounce (via EFFECT_FLY) same as Fly |
| shared heal drawer | Slack Off / Refresh → `FX.recover` path via `slack_off` |
| recoil flash | Double-Edge / Submission |

### Timing notes (pokeruby wave 5)

- **Sky Attack charge:** palette glow + SE_M_STAT_INCREASE loop ≈ 55f; hit bird dive + multi splat ≈ 55f.
- **Bounce:** rise shadow ≈ 30f (Fly peer); drop delay 7 + splat ≈ 40f.
- **Razor Wind charge:** triple gust orbits ≈ 40f; hit three air-waves + shake ≈ 45f.
- **Tri Attack:** triangle spin ≈ 40f then fire / bolt / ice segments (compressed to 85f).
- **Extremespeed:** speed-dust dashes then multi impact (~55f; BG scroll omitted).
- **Cross Chop:** crossed hands hold ~40f then CROSS_IMPACT flash.


### Shared helpers (wave 4)

| Helper / flag | Used by |
|---------------|---------|
| `chargeFx` / `chargeFrames` / `kind=="charge"` | Dig, Solar Beam, Fly, Dive, Skull Bash |
| `ctx.shatter` / `b.brickBreakShatter` | Brick Break |
| `mon.invuln` draw hide | Dig / Fly / Dive between turns |
| weather move FX | Rain Dance / Sunny Day / Sandstorm / Hail (setWeather still drives Game3BattleFx / Game3WeatherFx residual) |

### Timing notes (pokeruby wave 4)

- **Solar Beam charge:** orb absorb loop `_81CED9D` (~28 delays×2) ≈ 50f; hit beam + shake ≈ 90f.
- **Fly:** rise shadow ~13f + wait ≈ 30f; dive delay 20 + splat ≈ 40f.
- **Dive:** sink splash calls ×5 ≈ 45f; emerge bubbles + impact ≈ 55f.
- **Skull Bash:** tuck bob ×2 ≈ 48f; ram white flash + multi shake ≈ 55f.
- **Brick Break shatter:** same lunges as no-screen, then four torn-metal shards + SE_M_BRICK_BREAK.
- **Focus Punch:** ROM attack half after BG_IMPACT; we prepend ~28f windup in one anim.
- **Weather moves:** field tint + particle rain/sun/sand/hail; residual weather FX unchanged.

## Assets

Sprites load at runtime from

`misc/pokeruby-master/pokeruby-master/graphics/battle_anims/sprites/`

(tag index = `ANIM_TAG_* - ANIM_SPRITES_START`). Not copied into `assets/`.
Wave-4 tags: SWORD, FINGER, RAIN_DROPS, ROUND_SHADOW, SUNLIGHT, EXPLOSION,
GHOSTLY_SPIRIT, TORN_METAL, RAPID_SPIN, SPEED_DUST, HOLLOW_ORB, HAIL, SPLASH.
Wave-5 tags: BIRD, CROSS_IMPACT, AIR_WAVE_2, TRI_FORCE, HORN_HIT, ROOTS,
ITEM_BAG, GREEN_STAR, SPARKLE_2, THOUGHT_BUBBLE.

## How to verify in-game

1. Restart LÖVE (no hot-reload).
2. Two-turn: Dig/Fly/Dive/Solar Beam/Skull Bash — charge anim + hide (Dig/Fly/Dive), then hit anim next turn.
3. Brick Break through Reflect/Light Screen — wall appears then shatters.
4. Focus Punch — darken windup then multi fists.
5. Weather setters vs residual: Rain Dance/Sunny Day/Sandstorm/Hail move FX, then Game3WeatherFx continues.
6. Softboiled/Recover heal sparkles; Swords/Dragon Dance self FX; Explosion/Selfdestruct blast; Destiny Bond ghost link; Splash bounce; Struggle thrash; Metronome finger; Counter/Mirror Coat retaliate; Transform white wash.
7. Mash A: HP/text still advance; Battle Scene OFF still skips FX.
8. Spot-check catch, send-out, whiteout money, Toxic ticks, AI — unchanged.
9. Wave-5: Sky Attack / Bounce / Razor Wind two-turn; Tri Attack / Extremespeed / Cross Chop.
10. Catch/send-out: ROM `ruby_balls/poke.png` frames (palette-0 alpha), not huge.

## Next-subset follow-ups

1. Return/Frustration happiness-tier branch anims.
2. Multi-SE timelines (secondary SE_M_* mid-anim).
3. Palette-correct sheets (.pal for IMPACT/EMBER/walls).
4. Optional true waitanimation hold until moveAnim completes.
5. Doubles enemy2/player2 centers.
6. Softboiled distinct egg path vs Recover.
7. Focus Punch pre-turn “focusing” status anim (ROM turn-start task).
8. Extremespeed / Tri Attack fuller BG + multi-SE timelines.
9. Remaining specialty balls already extracted under `assets/generated/battle/ruby_balls/`
   (great/ultra/master/…) — wired by item id; spot-check open-frame art.

## ROM ball sprites (started, wave 5 Part B)

| Piece | Path |
|-------|------|
| Extract dir | `assets/generated/battle/ruby_balls/` |
| Source | `misc/pokeruby-master/pokeruby-master/graphics/interface/ball/*.png` |
| Trade strip | `…/graphics/trade/ball.png` → `ruby_balls/trade_ball.png` |
| HUD | `…/graphics/battle_interface/ball_display.png` |
| Process | palette index 0 → alpha; vertical 16×(16N) → horizontal (16N)×16 |
| Draw | `Game3:drawCatchBall` / `drawSendOutBall` → `drawRubyBallSheet` first |
| Size | 16px cells, caller scale ~1.0–1.55 (ROM-like on 240×160) |
| Fallback | cinema `tradeBall`, then generated `_sendOutBallImg16`, then procedural |

Standard Poké Ball (`poke.png`) is the primary wire; other ball types are extracted
and mapped by item id (1–12) for catch tinting when those sheets load.

No git commit for this pass.
