# Gen 3 (Ruby)

Ruby lives beside Gen 1 and Gen 2, not as a skin over either. Gold already
proved that path: `Game2.lua` is a second engine, not a branch inside
`Game.lua`. Ruby is `Game3.lua`.

Do not copy Nintendo graphics, audio, or maps into git. Extract at import
time from the player's ROM.

## Phase 1 — cart + stub cache

Detect US Ruby (`AXVE`), import header + species names, boot 240×160.

## Phase 2 — one walkable town

LZ77 + metatiles + collision on Littleroot, baked as a pair of map PNGs.
That slice proved the cart; it is not how Hoenn is stored.

## Phase 3 — Hoenn field

1. Walk `gMapGroups` (group length = next group start).
2. Write every map's grid, warps, and connections into `maps.lua`.
3. Dedup `(primary, secondary)` tileset pairs; one bottom/top atlas each,
   only the metatiles those maps actually use.
4. `Game3` composes the visible 16px cells, follows warps (including
   solid house doors you walk into), and crosses map connections.
   The GBA scene is drawn to a 240×160 nearest canvas (`PixelCanvas`,
   dpiscale 1) and integer-scaled so large-map scrolling does not flash
   atlas seams. Connected neighbor maps are drawn in the same view, and
   the camera may look a screen into them instead of clamping to a
   blue void at the map edge.
5. Object events and the player use overworld sprites from the ROM
   (`ow_{graphicsId}.png` is a horizontal strip of frames). NPCs face
   according to their movement type, look around, and wander in their
   range. The player turns with the D-pad and plays the walk cycle
   while stepping. The camera follows the interpolated feet, not the
   destination tile, so a step on a large map does not hitch 16px
   for a frame.    Missing sprites still fall back to the colored rects.

## Phase 4 — wild battle

1. `gBaseStats` (Bulbasaur HP 45 as the scan needle).
2. `gWildMonHeaders` (Route 101 = `g0_16`, Wurmple in slot 0).
3. Metatile behavior bytes on each tileset pair so tall grass is
   detectable at runtime.
4. LZ77 64×64 front pics for every wild species plus the Hoenn
   starters; Torchic's back pic for the player.
5. `Game3` rolls a land encounter after a grass step (`rate * 16 / 2880`),
   then a FIGHT / RUN screen. BAG and POKéMON stay parked. You start
   with a level-5 Torchic.

## Phase 4b — real moves

1. `gBattleMoves` (12-byte rows; Pound is power 40, type Normal) and
   the 13-byte Latin name table.
2. The type-effectiveness triples (`20` = 2×, `10` = 1×, `5` = 0.5×,
   `0` = immune). Foresight rows (`0xFE`) are skipped.
3. Level-up learnsets (`move | (level << 9)`, terminator `0xFFFF`).
   A Pokémon keeps the last four moves it would have learned.
4. FIGHT opens a four-move list with PP. Damage uses the Gen 3
   type-based physical/special split (types 0–8 physical, 10–17
   special), STAB, the type chart, and Blaze / Overgrow / Torrent
   at low HP. Growl and String Shot drop a stage. RUN still always
   works.

## Phase 5 — catching

BAG throws a Poké Ball (you start with five). The Gen 3 catch
value and four 16-bit shake checks are the pokeemerald math;
a catch joins the party, or goes to a PC stub if you already
have six. A miss spends the ball and the wild Pokémon still
attacks. POKéMON lists the party. No item table extract, so
no cache bump.

## Phase 6 — exp, switch, blackout

A KO (or a catch) gives the battler Gen 3 wild EXP
(`baseYield * level / 7`). Medium Slow / Fast / Slow / Erratic /
Fluctuating tables level them; new level-up moves are learned
(oldest dropped if the set is full). POKéMON can send out a
healthy party member; if the lead faints, switch is required.
If the whole party faints you warp back to Littleroot and
everyone is healed — catches are kept. `growthRate` is written
on the next import; missing caches default to Medium Slow.

## Phase 7 — field menu, nurse, evolution

START on the overworld opens POKéMON / BAG / EXIT. A facing an
NPC talks: the nurse (graphics 58) heals, the mart clerk says
not yet, everyone else is "...". B no longer dumps you to the
title. Level-up can evolve: Wurmple at 7 is Silcoon or Cascoon
from the personality high word, Torchic at 16 is Combusken.
`gEvolutionTable` is extracted on the next import; until then
a small fallback table covers the Route 101 line.

## Phase 8 — trainer battles

`gTrainers` (40-byte rows, `CALVIN` as the scan needle) and class
names are written to `trainers.lua`. Object events keep
`trainerType` / `trainerRange` / `flagId`; the `trainerbattle`
script command (`0x5C`) supplies the trainer id so the party is
attached to that NPC.

After a completed step, a facing cone (`TRAINER_TYPE_NORMAL`) or
all four ways (`SEE_ALL_DIRECTIONS`) can start a fight. Collision
and other NPCs block sight. RUN is refused. BAG opens; balls are
blocked and not spent; potions still work. A KO sends the next party member (1.5× EXP). Winning
sets the object flag so they stay beaten after you leave the map.
Talking to an undefeated trainer with A also starts the fight.
A stub prize (`16 * last level * party size`) is paid on a win.

Route 101 has no trainers; walk west from Oldale onto Route 102
(Youngster Calvin). Doubles and a real script VM stay parked.
Re-import after this cache bump (`rom-cache-v10-ruby5`).

Start map is still Littleroot (`g0_9`, north onto Route 101). Walk
onto Route 101's grass. The script VM stays parked.

## Phase 9 — items, bag, mart, item balls

`gItems` (44-byte rows, `MASTER BALL` as the scan needle) is written
to `items.lua`. Object scripts are scanned for `finditem` /
`giveitem` (`setorcopyvar` `0x1A` into `VAR_0x8000` / `VAR_0x8001`)
and `pokemart` (`0x86` plus a `u16` list). Item balls pick up with
A, set their flag, and stay gone. Mart clerks (graphics 83) sell
from that list (Poké Balls at $200 if the list is missing). START
→ BAG lists what you own; Potions heal on the field. Battle BAG
lists the same bag (Phase 13). You start with $3000 and five balls.

Re-import after this cache bump (`rom-cache-v10-ruby8`).

## Phase 10 — hidden items and signs

Map `bgEvents` (12-byte rows) are written into `maps.lua`. Kind 7 is a
hidden item (`item` + `hiddenId`); kinds 0–4 are signs. Sign scripts
are scanned for `loadword` (`0x0F`) so the Latin text is cached — no
script VM. A on the facing tile (and one more past a counter) picks
up a hidden item once (`FLAG_HIDDEN_ITEMS_START` `0x258` + id) or
prints the sign. Taken items stay silent.

Re-import after this cache bump (`rom-cache-v10-ruby9`).

## Phase 11 — save / continue

START → SAVE writes `save3_ruby.lua` (party, bag, money, flags, map
and facing) through the same Lua-source serializer Gen 1 uses. The
title's START is CONTINUE when that file is present; A is always NEW
GAME. Battles cannot be saved. No cache bump.

## Phase 12 — status

Damaging secondary effects (Ember burn, Poison Sting, Thunder Shock,
Ice Beam freeze) roll `secondary` chance. Thunder Wave / Sleep Powder
/ Toxic / Will-O-Wisp apply as primary status. Fire cannot burn, Ice
cannot freeze, Poison and Steel cannot be poisoned. Burn halves
physical Attack and residual HP/8; poison is HP/8; paralysis quarters
Speed and 25% full para; sleep lasts 1–3 turns; freeze has a 20% thaw
(Fire moves always thaw). Sleep and freeze 2× the catch value; para /
burn / poison 1.5×. The nurse clears status. No cache bump.

## Phase 13 — in-battle items

Battle BAG lists the same bag as the field. A uses the selected item.
Balls (ids 1–12) throw in wild fights: Master 255, Ultra 2×, Great
1.5×, Poké 1×. Trainers block balls (`The trainer blocked the BALL!`)
and do not spend one; potions still work. A Potion heals the battler,
then the enemy moves. Antidote / Burn Heal / Full Heal / Full Restore
clear matching status on the field and in battle. Super Potion is item
22 (50 HP); the old 14/15/17 heal table was Antidote / Burn Heal /
Awakening. No cache bump.

## Phase 14 — extra move effects

Absorb heals half the damage dealt. Fury Attack / Double Kick hit 2–5
or exactly 2 times (Gen 3 `Random() & 3` table). Bite can flinch if
it moves first. Take Down recoils 1/4; Double-Edge 1/3. Confuse Ray
confuses for 2–5 turns (50% self-hit, 40 power typeless physical).
Recover heals half max HP; Rest fully heals and sleeps two turns;
Splash does nothing. No cache bump.

## Phase 15 — abilities

Personality bit 0 picks `ability2` when it is set. Intimidate drops
Attack on send-out (intro A, switch, trainer send-out). Inner Focus
blocks flinch; Rock Head skips recoil; Own Tempo / Immunity / Limber /
Water Veil / Magma Armor / Insomnia / Vital Spirit block matching
status. Static / Flame Body / Poison Point / Rough Skin proc on
contact. Levitate, Volt Absorb, Water Absorb, Flash Fire, and
Lightningrod absorb or ignore the matching type. Shed Skin can cure
status; Liquid Ooze reverses Absorb; Shield Dust blocks secondaries;
Hyper Cutter / Clear Body block stat drops; Guts / Thick Fat /
Marvel Scale / Huge Power / Swarm / Compound Eyes / Serene Grace /
Wonder Guard / Natural Cure / Synchronize / Early Bird are wired.
No cache bump.

## Phase 16 — script VM

NPC talk that is not a nurse, item ball, mart, or live trainer runs
extracted script IR. Import walks `lock` / `faceplayer` / `loadword` /
`callstd` / `goto_if` / `setflag` / `finditem` and stores decoded Latin
plus op indices in `maps.lua` (no ROM pointers at play time). A/B
advances a message queue. `trainerbattle` is a nop after the fight so
defeated trainers can still msgbox. Yes/no and `givemon` stay parked
until Phase 17.
Re-import after this cache bump (`rom-cache-v10-ruby10`).

## Phase 17 — starter choice

New game starts with an empty party. Talking to Birch's bag on Route
101 (gfx 97) or Birch in the lab (gfx 64) opens Treecko / Torchic /
Mudkip (cursor starts on Torchic). A confirms, B goes back. The pick
sets `FLAG_SYS_POKEMON_GET`, hides the bag, and `givemon` in NPC
scripts also joins the party. Saves before the pick are allowed.
Grass and trainers already no-op without a healthy mon. No cache bump
(optional re-import writes Treecko/Mudkip back pics).

## Phase 18 — natures and IVs

Each mon rolls 0–31 IVs and takes its nature from `pid % 25` (Hardy
through Quirky). Attack / Defense / Speed / Sp. Atk / Sp. Def get
×1.1 or ×0.9 when the nature is not neutral; HP is un-natured.
`recalcStats` (level-up, evolution, save load) uses both. Old saves
without IVs load as zeros. The party list shows the nature name. No
cache bump.

## Phase 19 — PC boxes

Ruby has 14 boxes of 30. A catch with a full party is stored in the
first box that has room (`transferred to BOX n`). A on a PC tile
(`MB_PC` 0x83, bedroom 0xC5, secret base 0xB0) opens WITHDRAW /
DEPOSIT / SEE YA. You cannot deposit your last party mon or the last
one that can battle. Saves store the boxes; old saves load an empty
PC. No cache bump.

## Phase 20 — special balls

Net Ball is 3× on Water or Bug. Dive Ball is 3.5× on underwater
maps (`mapType` 5). Nest Ball is `(40 - level) / 10` (min 1×; Ruby
clamps levels 31–39 to 1×). Repeat Ball is 3× if that species is
already owned (party, PC, or a prior catch). Timer Ball is
`(turns + 10) / 10`, max 4×. Safari Ball is 1.5× like a Great Ball.
Owned species persist in the save. No cache bump.

## Phase 21 — script yes/no

`callstd` 5 (`MSGBOX_YESNO`) and `yesnobox` pause the script VM.
YES writes 1 to `VAR_RESULT` (0x800D), NO writes 0; `compare` /
`goto_if` then pick the branch. Messages before the prompt still
queue. B chooses NO. No cache bump (`callstd` 5 is already in the IR;
re-import only needed for native `yesnobox`).

## Phase 22 — weather

Rain Dance / Sunny Day / Sandstorm / Hail last 5 turns. Fire is 1.5×
and Water 0.5× in sun (reversed in rain). Thunder cannot miss in rain.
Sandstorm chips 1/16 unless Rock / Steel / Ground; hail chips Ice.
Drizzle / Drought / Sand Stream set weather for the rest of the fight.
Trace copies the foe's ability on send-out. Swift Swim / Chlorophyll
double Speed; Rain Dish heals 1/16 in rain. Cloud Nine / Air Lock
suppress weather. No cache bump.

## Phase 23 — Truant and Pickup

Truant loafs every other turn (`"%s is loafing around!"`), after freeze /
sleep / paralysis so those still skip the toggle. Send-out clears the
loaf flag. Pickup is 10% after a win or catch (not RUN / blackout).
Ruby uses the RS item/chance pairs (Super Potion 30%, … King's Rock 1%),
not Emerald's level bands. The find goes in the bag (`"%s found a %s!"`)
because this engine has no held-item UI yet. No cache bump.

## Phase 24 — Protect, stat-ups, OHKO, two-turn

Protect (effect 111) has +3 priority and a 100/50/25/12.5% streak. Self
stat-ups cover +1/+2 and Bulk Up / Calm Mind / Dragon Dance / Cosmic
Power / Defense Curl. OHKO (Fissure etc.) uses `(level diff)+30%` and
fails on a higher-level or immune foe. Fly / Dig / Dive charge then
go semi-invulnerable; Thunder / Gust hit Fly, Earthquake hits Dig for
2×. Solarbeam charges unless it is sunny, and is halved in rain / sand
/ hail. No cache bump.

## Phase 25 — Skull Bash, Sky Attack, Endure

Razor Wind / Sky Attack / Skull Bash charge on the first turn (no
semi-invulnerability). Skull Bash raises Defense while tucking in.
Sky Attack can flinch on the hit. Endure shares Protect's success
streak and leaves the user at 1 HP (`"%s braced itself!"` /
`"%s endured the hit!"`). High-crit moves (Slash, Razor Wind, Sky
Attack) are 1/8; everything else is 1/16. No cache bump.

## Phase 26 — Birch chase and the moving truck

New game hides lab Birch (`FLAG_HIDE_BIRCH_IN_LAB` 0x2D1) and, when
the cache has it, starts inside the moving truck (small indoor map,
no connections, boxes at (0,0)/(0,3)/(2,3)). Walking to x≥3 or a
`0xFF`/`0x7F` warp leaves the truck in Littleroot.

Birch's bag still gives a starter. Closing `Got TREECKO!` (or
Torchic / Mudkip) starts a wild Poochyena (286) at level 2; RUN is
blocked. A win or a blackout warps to Birch's lab (`g1_4` at 6,5),
shows lab Birch, and hides Route 101 Birch plus the chase Poochyena.
JOG_IN_PLACE movement types 84–87 stay in place. Object `flagId`s
hide NPCs. No cache bump.

## Phase 27 — doubles trainers

Trainer rows store `doubleBattle` at +0x18. A doubles NPC sends two;
you send two if you have them. Each battler hits the opposite slot
(or the remaining foe). The partner picks a damaging move. A faint
fills that slot from the rest of the trainer party; both slots empty
wins. One of your slots fainting with a bench opens POKéMON for that
slot. No target menu, no spread moves, no cache bump.

## Phase 28 — spread, aim, Sand Veil

Move `target` (ROM byte 6) is copied onto battle moves. `TARGET_BOTH` (8)
hits both foes; `TARGET_FOES_AND_ALLY` (32) also hits the partner. More
than one living target halves damage. In doubles, FIGHT on a single-target
move opens an aim menu. Sand Veil (8) skips sandstorm residual and drops
incoming accuracy to 80% in sand, including 100% moves. No cache bump.

## Phase 29 — Pokédex handoff

`FLAG_SYS_POKEDEX_GET` (0x801). After a starter, lab Birch (gfx 64) hands
the dex; the Route 101 bag (gfx 97) does not. START grows a POKeDEX row.
Seen species (wild/trainer) plus caught species list in the dex. `special`
0 heals, 212 writes seen/caught into `VAR_0x8004`/`0x8005` (national
`0x8006` stays 0), 213 rates the catch. No cache bump.

## Phase 30 — lab rival

NEW GAME asks BOY/GIRL. Boy is Brendan (gfx 0); girl is May (gfx 89, or
rival-May 105 if that sheet is missing). House/truck hide flags match
the truck script. Lab object gfx 240 (`VAR_0`) is the opposite-gender
rival. They stay hidden (`FLAG_HIDE_RIVAL_BIRCH_LAB` 0x379) until the
dex, then take the starter with type advantage. No cache bump.

## Phase 31 — Route 103 rival

Route 103's gfx `240` (`FLAG_HIDE_RIVAL_ROUTE103` 0x2D3) starts a trainer
fight. The party is May/Brendan's lv5 starter with type advantage
(`TRAINER_MAY_4/7/1`, `TRAINER_BRENDAN_4/7/1`). A win sets
`FLAG_DEFEATED_RIVAL_ROUTE103` (0x82) and hides them. Other `VAR_0`
objects are not the lab take. No cache bump.

## Phase 32 — truck home

Walking off the truck (or its `0xFF`/`0x7F` warp) dropped you in the
player's bedroom when a map has `"The clock is stopped"` as BG text:
Brendan 2F if the clock is at x>=4, else May 2F. Phase 63 lands in
Littleroot Town first; the bedroom is now the heal respawn and the
fallback when the town grid is too small for tiles (3,10) / (12,10).
First A on that clock sets `FLAG_SET_WALL_CLOCK` (0x51) and hides the
Machoke movers (`0x2F2`/`0x2F3`). Later A is a running-clock line. Mom
(gfx 215) heals. No cache bump.

## Phase 33 — National Dex

`FLAG_SYS_NATIONAL_DEX` (0x836). Lab Birch upgrades the dex after 200 Hoenn
catches (`HOENN_DEX_COUNT` 202, complete at 200; Jirachi/Deoxys do not
count). That sets `VAR_NATIONAL_DEX` (0x4046) to `0x302`. `special` 212
writes `VAR_0x8006` = 1 once enabled (still 0 before). `special` 335 is
`CompletedHoennPokedex` (`VAR_RESULT`). Optional `hoennDex` on a species
row filters the Hoenn list; missing that field counts every catch, as
before. No cache bump.

## Phase 34 — applymovement / exit light

`applymovement` (0x4F) decodes walk/face/jump bytes (step_end 0xFE).
`waitmovement` is a nop so the rest of the script still extracts.
Runtime walks and faces instantly (player `0xFF`, NPCs by `localId`).
`setmetatile` (0xA2) writes a cell; `opendoor`/`setdooropen` clear
collision (the exit light); `closedoor` blocks again. Indoor maps with
no connections light the warp next to the player on enter. `setstepcallback`
stores the id. No animated VM, no cache bump.

## Phase 35 — animated applymovement / cracked floor

`waitmovement` (0x51) is a real IR op. Runtime queues each actor's steps
and plays them on the walk lerp (`WALK_PERIOD`); `waitmovement` pauses
the script (`field.kind == "move"`) until that queue and the current
lerp are empty. `jump2` is two one-tile walks. Tests call
`finishScriptMoves()` to skip the lerp. Step callback 7 cracks
`MB_CRACKED_FLOOR` (0xD2) into the next metatile, then a step onto
`MB_CRACKED_FLOOR_HOLE` (0x66) snaps to the map spawn with
"You fell through!". Callback 4 does the same for thin ice (0x26) /
cracked ice (0x27). No cache bump.

## Phase 36 — ash / Fortree / Pacifidlog step callbacks

Callback **1** clears `MB_ASHGRASS` (0x24): Fallarbor `0x20A→0x212`,
Lavaridge `0x207→0x206`, anything else `mid+1`. A soot sack (item 270)
increments `VAR_ASH_GATHER_COUNT` (0x4048), capped at 9999. Callback **2**
lowers a Fortree bridge tile whose next metatile is also `MB_FORTREE_BRIDGE`
(0x78) and raises the tile you left. Callback **3** writes the official
floating / submerged ids on both halves of a Pacifidlog log
(behaviors 0x74–0x77); `setstepcallback` 3 sinks the pair you stand on.
No cache bump.

## Phase 37 — emotes / delays / invisibility

`delay_1`..`delay_16` (0x10–0x14) stay in movement IR with a frame count
and hold `waitmovement` for that many 60fps frames. `emote_*` (0x56–0x58)
shows `!` / `?` / `<3` for 32 frames. `set_invisible` / `set_visible`
(0x54 / 0x55) hide the sprite without removing collision. `face_player`
(0x3E) turns an NPC toward the player. Existing caches need a re-import
to pick up the new steps; no required-files bump.

## Phase 38 — hideobjectat / showobjectat

`hideobjectat` (0x59) / `showobjectat` (0x58) toggle the sprite
(`invisible`) without dropping collision. `removeobject` (0x53) hides the
NPC and sets its `flagId`; `addobject` (0x55) clears that flag and
respawns if needed. `setobjectxy` (0x57) warps an actor; `turnobject`
(0x5B, 4 bytes: localId + dir 1–4) faces them; `faceplayer` (0x5A) turns
the talking NPC toward you. `_at` variants ignore the map bytes and act
on the current map. Existing caches need a re-import; no required-files
bump.

## Phase 39 — Acro Bike / affine / levitate

Affine walk down (0x62 / 0x63) is a south walk; `%4` would have faced
west or east. Acro wheelie face / hop-face / in-place (0x64–0x73,
0x7C–0x7F) face; hops (0x74–0x77) walk; jumps (0x78–0x7B) are two-tile
jumps. Diagonal walks (0x8C–0x93) carry `dx`/`dy`. Levitate (0x98)
lifts the sprite 8px; stop levitate (0x99 / 0x9A) and fly down (0x9D)
clear it; fly up (0x9C) lifts 16px. Jump-special (0x3A–0x3D) uses
explicit dirs. Existing caches need a re-import; no required-files bump.

## Phase 40 — lock facing / nurse bow / delay

`lock_facing_direction` (0x40) / `unlock` (0x41) keep the last facing
through later walks. `nurse_joy_bow` (0x4F) faces south and holds 32
frames. `reveal_trainer` (0x59) shows a disguised NPC. `rock_smash_break`
(0x5A) / `cut_tree` (0x5B) hide the obstacle after 32 frames.
`lock_anim` (0x94) / `unlock_anim` (0x95) freeze the walk cycle.
Script `delay` (0x28) pauses the VM for that many 60fps frames, the
same way `waitmovement` does. Existing caches need a re-import; no
required-files bump.

## Phase 41 — waitstate / leftover movement flags

`waitstate` (0x27) stays in IR. It pauses the VM only while a special
has called `beginScriptWait`; `endScriptWait` resumes. Idle `waitstate`
(sync specials like heal) is a no-op, so nurse scripts do not hang.
`start_anim_in_direction` (0x39) holds in place. Jump-landing (0x50 /
0x51), disable/restore anim (0x52 / 0x53), fixed priority (0x5C /
0x5D), affine init (0x5E / 0x5F), and hide/show reflection (0x60 /
0x61) set actor flags. Existing caches need a re-import; no
required-files bump.

## Phase 42 — bag Cut / Rock Smash

BAG HM01 (item 339) and HM06 (item 344) are field moves. Cut needs a
party member that knows move 15 and the Stone Badge (`FLAG_BADGE01_GET`
0x807); it chops the cuttable tree in front (gfx 82) or mows a 3x3 of
tall/ash grass around the facing tile. Rock Smash needs move 249 and
the Dynamo Badge (`FLAG_BADGE03_GET` 0x809) and breaks the rock in
front (gfx 86). HMs are not consumed; `removeobject` sets the hide
flag so the obstacle stays gone. No re-import; no required-files bump.

## Phase 43 — Surf / Strength / Flash / Waterfall

BAG HM03 (341) Surfs onto pond/ocean water in front (behaviors 0x10–0x12,
0x14–0x15) with the Balance Badge; water stays solid until then, and
stepping onto land dismounts. HM04 (342) sets `FLAG_SYS_USE_STRENGTH`
(0x829) with the Heat Badge so walking into a boulder (gfx 87) pushes it
one tile. HM05 (343) sets `FLAG_SYS_USE_FLASH` (0x828) in underground
maps (`mapType` 4) with the Knuckle Badge and lifts the cave overlay.
HM07 (345) climbs a waterfall (behavior 0x13) while already surfing,
with the Rain Badge. HMs are not consumed. No re-import; no
required-files bump.

## Phase 44 — Fly

BAG HM02 (340) opens a visited-town list with the Feather Badge
(`FLAG_BADGE06_GET` 0x80C) and move 19. Entering a group-0 town or city
sets the matching `FLAG_VISITED_*` (0x80F–0x81E). Fly works from towns,
cities, routes, and ocean routes; indoors and caves refuse. Picking a
row warps to that map's spawn and clears Surf. HMs are not consumed. No
re-import; no required-files bump.

## Phase 45 — Dive

BAG HM08 (346) Dives with the Mind Badge (`FLAG_BADGE07_GET` 0x80D) and
move 291. You must already be surfing on deep water (behavior 0x12 or
0x14) and the map must have a `dive` connection (dir 5). That warps to
the paired underwater map at the same x/y. Using Dive again on an
underwater map (`mapType` 5) follows the `emerge` connection (dir 6)
unless the tile is no-surfacing (0x18 / 0x28). The extractor now keeps
those two connection dirs; re-import an existing cache so Route 124 and
friends pick them up. No required-files bump.

## Phase 46 — Fishing / water / smash encounters

BAG Old/Good/Super Rod (262–264) cast at the facing surfable tile (not a
waterfall, not underwater). A 50% bite roll then picks from the map's
already-extracted 10 fish slots (Old 0–1, Good 2–4, Super 5–9 at Ruby's
slot weights). A miss prints "Not even a nibble..."; a hit starts the
wild fight. Surfing steps use the 5 water slots; Rock Smash can roll
the 5 rock slots after the boulder is gone. Rods are not consumed. No
re-import; no required-files bump.

## Phase 47 — Mach / Acro Bike / running shoes

BAG Mach Bike (259) and Acro Bike (272) toggle on outdoor maps (not
indoor, secret base, or underwater) and hop off on the same item. Mach
steps at 4× walk speed (`MACH_PERIOD`); Acro stays at walk speed. Biking
is refused while surfing. Entering an indoor map dismounts. Holding B
with `FLAG_SYS_B_DASH` (0x860) dashes at 2× on foot. Bikes are not
consumed. No re-import; no required-files bump.

## Phase 48 — Repels / Escape Rope / last heal

BAG Repel (86), Super Repel (83), and Max Repel (84) last 100/200/250
steps. While the counter is up, land, Surf, and Rock Smash encounters at
or below the lead's level are skipped; fishing is not. Each successful
step decrements; at 0 the field prints "REPEL's effect wore off!"
Talking to the nurse or Mom, or script special 0, stores the current
tile as the last heal. Escape Rope (85) from an underground/cave map
consumes one and warps there (same as a blackout). A missing heal point
falls back to the start map spawn. CONTINUE persists both. No
re-import; no required-files bump.

## Phase 49 — Dig / Teleport

START → POKeMON → A uses TELEPORT (move 100) from a town, city, route,
or ocean route — the same outdoor gate as Fly — and DIG (move 91) from
an underground/cave map, the same gate as Escape Rope. Both warp to the
last heal without spending an item or needing a badge. Dig is refused
while surfing, diving, or underwater; Teleport is not. A Pokémon that
knows neither stays on the party list. No re-import; no required-files
bump.

## Phase 50 — Sweet Scent

START → POKeMON → A uses SWEET SCENT (move 230) on the current tile.
Tall/long/short/ash grass rolls land slots; surfable water (not a
waterfall) rolls water slots. There is no encounter-rate dice and Repel
does not block. A miss prints "Looks like there's nothing here." The
move is not an HM and is not consumed. No re-import; no required-files
bump.

## Phase 51 — Day Care

The indoor Route 117 lady (`OBJ_EVENT_GFX_OLD_WOMAN_2` = 30) takes up to
two party Pokémon (never the last one). Each successful step adds 1 EXP
to every deposited mon. Taking one back applies that EXP, learns
level-up moves, does **not** evolve, and costs `$100 + $100 × levels
gained`. CONTINUE stores both slots. Official specials 132 / 182 /
187–192 write `VAR_RESULT` / `0x8004` / `0x8005` so extracted lady
scripts can drive the same API. No re-import; no required-files bump.

## Phase 52 — Day Care eggs

The outdoor Route 117 man (`OBJ_EVENT_GFX_OLD_MAN_2` = 29) reports
compatibility (0 / 20 / 50 / 70) and offers a pending EGG. Two parents
roll once every 256 steps on the second slot; a hit stores
`pendingEggPersonality` and `FLAG_PENDING_DAYCARE_EGG` (`0x86`).
`GetDaycareState` (182) returns **1** while an egg is waiting.
GiveEgg / RejectEgg / SetDaycareCompatibilityString are specials 184 /
183 / 185. The egg is species of the mother (female, or the non-Ditto)
walked back through the evolution table; it is nicknamed EGG, does not
count as caught, and cannot be sent into battle. Every 255 overworld
steps decrements party hatch counters; at 0 the egg hatches at level 5
and is recorded in the dex. CONTINUE stores the pending pid, cycle
counter, and `isEgg`. Extractor copies `genderRatio` / `eggCycles` /
egg groups from base stats (no cache bump; old caches fall back).
No required-files bump.

## Phase 53 — Contests

Indoor TEALA (`OBJ_EVENT_GFX_TEALA` = 85) opens a CONTEST: pick Cool /
Beauty / Cute / Smart / Tough, then a rank you qualify for (Normal is
always open; Super needs that category's Normal ribbon, and so on). Five
appeal turns score the move's contest appeal (ROM field if present,
otherwise 20, halved on a category miss). Three NPC totals are 50 / 55 /
60, so five matching appeals win and five mismatches lose. A win stamps
that rank's ribbon on the mon. Eggs cannot enter. Script ops `0x8B` /
`0x8C` / `0x8D` choose the mon, start the contest, and show results;
specials 76 / 84 / 87 / 89 / 90 / 138 / 265–269 match pokeruby's table.
CONTINUE stores condition stats and ribbons. No cache bump.

## Phase 54 — Secret bases

SECRET POWER (move 290) or BAG TM43 (item 331, not consumed) on a cave
or tree spot makes one SECRET BASE. Spots are BG events kind 8
(`secretBaseId` at union +8) or metatile behaviors `0x90`–`0x9D`. The
interior is a generated 7×6 room (`mapType` 9) with a PC at (3,1)
(behavior `0xB0`) and a south-wall warp back to the tile you used the
move from. Walking into the owned overworld spot enters; a second spot
asks YES/NO to move. Specials 7 / 10 are CheckPlayerHasSecretBase /
MoveOutOfSecretBase; `VAR_CURRENT_SECRET_BASE` (`0x4054`) holds the id.
CONTINUE stores the entrance and rebuilds the interior. Decorations,
mixing, and the registry PC are later. Kind-8 ids need a re-import;
behavior spots work on old caches. No required-files bump.

## Phase 55 — Fonts, windows, and player forms

Extract latin FONT3 (8×16 4bpp, GBA character codes — the English
menu/dialogue face, not 1bpp FONT0) to `assets/generated/fonts/font.png`.
The sheet is found via pokeruby's `sFonts[]` table so a 1bpp ink scan
cannot land on tileset garbage. Dialogue, START, the bag, and battle
text draw those glyphs instead of Love2D's default font. Windows use the
RSE cream fill and dark frame. START is the right-side list: POKeDEX
(if owned), POKeMON, BAG, the player name, SAVE, OPTION, EXIT. The
overworld no longer prints a debug HUD. Bike, Surf, and Dive swap the
player to Brendan/May's matching overworld sheets (extracted with the
walk sprite). Re-import after this cache bump (`rom-cache-v10-ruby12`).

## Phase 56 — map scripts and coord events

NPC talk was already IR. This phase extracts the hooks that start
scenes: `ON_TRANSITION` / `ON_LOAD` / `ON_RESUME` / `ON_DIVE_WARP`,
the `ON_FRAME` / `ON_WARP` tables, and 16-byte coord events.
`call_if` is a call, not a goto. `VarGet` treats ids below `0x4000` as
literals, matching pokeruby. Entering a map runs transition then load
then resume, rebuilds NPCs from the new flags, then warp/frame/coord.
Stepping on a tile whose var matches runs that coord script. New game
does not pre-set hide flags; the map scripts do. Re-import
(`rom-cache-v10-ruby13`).

## Phase 57 — Littleroot north exit

The Route 101 twin script does `msgbox`, then `applymovement` / `waitmovement`.
The VM queued the line and then overwrote the field with `kind=move`, so the
shove played and the cutscene never appeared. `presentScript` now keeps that
line until A, then starts the walk. `ON_TRANSITION` also uses
`setobjectxyperm` / `setobjectmovementtype` (0x63 / 0x65) to plant the twin
on the road *before* NPCs spawn; those were unknown opcodes so she stayed
at her default tile off-camera. `checkplayergender` (0xA0) is decoded so
Mom's door scripts can branch. Re-import (`rom-cache-v10-ruby14`).

## Phase 58 — boot cinema and main menu

Power-on now follows pokeruby: a 3-second copyright card (not skippable),
the intro cinema (any key skips; simplified GAME FREAK / Groudon until
the affine bike ride is ported), the title PRESS START blink (A/START
open the menu; ~80s loops back), then CONTINUE / NEW GAME / OPTION.
No save file means NEW GAME / OPTION only. CONTINUE shows PLAYER / TIME /
POKeDEX / BADGES from the save. NEW GAME is Birch's speech, BOY/GIRL, the
preset names or NEW NAME keyboard, then the truck. OPTION stores TEXT
SPEED, BATTLE SCENE, BATTLE STYLE, and SOUND on the save. Tests still
call `advance()` to skip boot. Re-import (`rom-cache-v10-ruby15`) so
`data/generated/title.lua` exists.

## Phase 59 — OPTION, typewriter, SHIFT

START OPTION is the same menu as the title. TEXT SPEED uses pokeruby's
6 / 3 / 1 frame delays; A finishes the line, and tests that never tick
`dt` still advance on the first A. BATTLE STYLE SHIFT asks "Will you
switch POKeMON?" when a trainer has another mon and you have a bench;
SET sends the replacement immediately. BATTLE SCENE and SOUND store on
the save (move anims still to come). No cache bump.

## Phase 60 — TRAINER CARD and SAVE confirm

START on the player name opens the TRAINER CARD: NAME, IDNo. (five
digits from the 16-bit trainer ID), MONEY, POKeDEX (once owned), TIME,
and the eight Hoenn badge slots. A new game rolls `InitPlayerTrainerId`.
SAVE asks "Would you like to SAVE the game?" with the map / player /
badges / time summary; YES writes and says "{PLAYER} saved the game."
No cache bump.

## Phase 61 — bag pockets and party SUMMARY

START BAG uses the five pokeruby pockets (ITEMS / POKe BALLS / TMs & HMs
/ BERRIES / KEY ITEMS). Left and right change pocket; A still uses the
selected slot. ROM `pocket` bytes win when `items.lua` is present;
balls / berries / TMs / bikes / rods have fallbacks without it.

START POKeMON lists all six slots with HP bars. A opens SUMMARY / SWITCH
/ field moves / CANCEL. SUMMARY has INFO, SKILLS, and MOVES pages
(left/right). SWITCH swaps two party members. No cache bump.

## Phase 62 — two-line dialogue wrap

Talk, battle text, and Birch's speech wrap to pokeruby's 2-line FONT3
box (208px / 26 glyphs). A finishes the typewriter, then pages leftover
lines before closing. ROM `\n` (0xFE) inside a `\p` page stays a line
break; sign `decodeText` still collapses newlines to spaces. No cache bump.

## Phase 63 — truck to Littleroot

Walking off the truck lands in Littleroot Town at pokeruby's tiles
(3,10 boy / 12,10 girl) and writes `VAR_LITTLEROOT_INTRO_STATE` plus the
house-state vars so the town ON_FRAME script can run Mom's moving-in
scene. Heal respawn is the gender's bedroom 2F. `warp` / `warpsilent`
(0x39 / 0x3A) enter a map by group, number, and xy. A town too small for
those tiles still falls back to the bedroom or the spawn. No cache bump.

## Phase 64 — Mom's moving-in scene

`setdynamicwarp` (0x3F) stores the truck's MAP_DYNAMIC dest; `setrespawn`
(0x9F) writes heal location 1/2 (Brendan/May 2F). The truck coord at x=3
runs that script, then x=4 follows the dynamic warp. Town ON_FRAME can
msgbox, hide the truck, set intro state 3, and `warpsilent` into the
house. `playse` is parsed so Mom's ROM script is not truncated. No cache
bump.

## Phase 65 — walk inside with Mom

`MSGBOX_DEFAULT` waits for A before the rest of the script. `jump_right`
(0x45) is east, `walk_in_place_fastest_*` faces in place. Town ON_FRAME
jumps the player off the truck, `addobject`s Mom (local 4), walks her
out, talks, then both enter and `warpsilent` to the house. No cache bump.

## Phase 66 — house 1F moving-in

`applymovement` / `waitmovement` VarGet the localId so
`applymovement VAR_0x8004` moves house Mom (local 1). ON_TRANSITION with
intro 3 puts her at the door (9,8 boy / 1,8 girl). ON_FRAME talks, faces
the player, sets intro 4, and walks you in. Entering 2F at intro 4
becomes 5 (go set the clock); the stopped clock writes intro 6. No cache
bump.

## Phase 67 — Petalburg gym TV

Coming downstairs at intro 6 puts Mom at the TV (4,5 boy / 6,5 girl).
ON_FRAME: pin, "come quickly," walk to the TV, the gym report, then
"go introduce yourself next door." That writes intro 7, `VAR_TEMP_1`,
and `FLAG_SYS_TV_HOME`. `playbgm` (0x33) and `fadedefaultbgm` (0x35) are
kept so the ROM script is not truncated; special 62 turns the TV off.
No cache bump.

## Phase 68 — rival-Mom next door

After the gym report, the rival house ON_FRAME (`VAR_LITTLEROOT_HOUSES_STATE`
== 1 on Brendan 1F / `_STATE_2` on May 1F) pins rival-Mom (local 4 at
2,7 / 8,7), walks her to the door, and talks. Special 149
(`GetRivalSonDaughterString`) writes `son`/`daughter` into `{STR_VAR_1}`.
`{PLAYER}` / `{STR_VAR_1}` expand at say-time so ROM text matches the
cart. That sets `FLAG_MET_RIVAL_MOM` and the house-state var to 2. No cache
bump.

## Phase 69 — rival 2F notebook

After rival-Mom, the rival is already upstairs at the notebook (pokeruby,
not emerald's Poké Ball `addobject`). ON_TRANSITION `call_if_unset
FLAG_DEFEATED_RIVAL_ROUTE103` does `setobjectxyperm 1` to (1,2) Brendan /
(7,2) May, FACE_UP. Talk script 152A9D: GettingReady, encounter BGM, pin,
WhoAreYou, walk off by `VAR_FACING`, `removeobject VAR_LAST_TALKED`, then
`VAR_LITTLEROOT_RIVAL_STATE` = 3 and `VAR_LITTLEROOT_STATE` = 1. `savebgm`
(0x34, 3 bytes) is kept so the ROM walk is not truncated. Talking stores
`VAR_LAST_TALKED` / `VAR_FACING` like `field_control_avatar.c`. No cache
bump.

## Phase 70 — empty lab and the Route 101 chase intro

Rival 2F left `VAR_LITTLEROOT_STATE` at 1. Town ON_TRANSITION then sets
`FLAG_RIVAL_LEFT_FOR_ROUTE103` and moves the twin to (10,1) FACE_UP.
Stepping onto (11,1) — or talking to the twin — is GoSaveBirch: they hear
shouting down the road and write state 2. The lab hides Birch
(`FLAG_HIDE_BIRCH_IN_LAB`); the aide says he is on fieldwork
(`FLAG_BIRCH_AIDE_MET`). Route 101 ON_FRAME writes `VAR_ROUTE101_STATE`
1; the (10,19)/(11,19) trigger is 14E948 (`H-help me!`, Birch local 2 and
Poochyena local 4 run in, then the BAG line, state 2). Picking the bag
writes lab-state 2 and route-state 3. No cache bump.

## Phase 71 — bag ChooseStarter, first battle, lab warp

Talking to a bag with ROM script 14EA7F runs that script before the
stand-in `isStarterGiver` menu. `fadescreen` (0x97, 2 bytes) parses so
the walk does not stop at the fade. Special 156 (`ChooseStarter`) parks
`waitstate` on the ball UI (cursor starts on Torchic). Confirming gives
the lv 5 starter, writes `VAR_RESULT` / `VAR_STARTER_MON` 0/1/2, and
starts `BATTLE_TYPE_FIRST_BATTLE` vs Poochyena without warping. Win or
faint returns to the field script: Birch's thanks, heal, hide flags,
`VAR_BIRCH_LAB_STATE` 2, `VAR_ROUTE101_STATE` 3, warp lab (6,5). Bags
with no script still use the Phase 26 stand-in (`Got TREECKO!` then
chase, warp from `endBattle`). While `VAR_ROUTE101_STATE` is 2, stepping
(10,18)/(11,18) shoves Birch up, the x=6 column shoves him right, and
(7,13) shoves him down ("Don't leave me like this!"). No cache bump.

## Phase 72 — lab GiveStarterEvent

Warping in with `VAR_BIRCH_LAB_STATE == 2` faces the player up (ON_WARP
turnobject 2) then runs 152CBE. `bufferleadmonspeciesname` (0x7E) writes
the lead species into `{STR_VAR_1}`. Birch gives you that mon, asks to
nickname it (special 158 / 10-letter keyboard), then whether to see the
rival on Route 103. Declining loops "don't be that way" until YES.
Agreeing clears `FLAG_HIDE_BOY_ROUTE101` and writes lab-state 3. `message`
plus `waitmessage` now wait for A like the ROM. No cache bump; re-import
picks up longer script lines (`TEXT_LEN` 512).

## Phase 73 — lab GivePokedexEvent

Beating the Route 103 rival writes lab-state 4, shows the lab rival, and
sets Route 103 / Oldale flags. Walking into the lab then runs 152D4A:
seven `walk_up` from the door, Birch hands the POKeDEX
(`FLAG_SYS_POKEDEX_GET`), the rival (local 3 at 7,4) steps down, and May
or Brendan gives five POKe BALLS. That writes lab-state 5,
`FLAG_ADVENTURE_STARTED`, `VAR_ROUTE102_ACCESSIBLE` 1, rival-state 4,
and Littleroot-state 3. Talking to Birch without a ROM script still uses
the stand-in dex handoff. No cache bump.

## Phase 74 — Oldale rival + Route 102

First visit: ON_TRANSITION parks the footprints man at (1,11) facing west
while `VAR_ROUTE102_ACCESSIBLE` is 0, so (0,10) shoves you back. After
GivePokedex (`FLAG_ADVENTURE_STARTED`) that var becomes 1 and west is
open; talking to the man is the "own footprints" line. Beating Route 103
shows the rival (local 4); stepping (8,19) while `VAR_OLDALE_STATE` is 1
has May/Brendan send you back to the lab, then hides them. New-game hide
flags cover the Oldale and lab rivals. `setorcopyvar` copies `VAR_FACING`
so `switch` walks work. No cache bump; re-import picks up longer NPC
scripts (`MAX_OPS` 200).

## Phase 75 — Running Shoes

GivePokedex writes Littleroot-state 3. Walking into town then shows Mom
in front of the house (5,9 boy / 14,9 girl). Stepping (10,9) — or talking
to her — is the gift: Wait, the shoes, B-button instructions, then she
goes inside. That sets `FLAG_RECEIVED_RUNNING_SHOES`, `FLAG_SYS_B_DASH`,
and Littleroot-state 4. Outdoor Mom with a ROM script is no longer the
heal stand-in. `playfanfare` / `waitfanfare` parse so the obtain jingle
does not stop the walk. No cache bump.

## Phase 76 — Oldale mart Potion

ON_TRANSITION `call_if_unset FLAG_RECEIVED_POTION_OLDALE` parks the
employee (local 2, gfx 83) at (13,14) FACE_DOWN. Talking is not the shop
stand-in: they ask you to come along, `switch VAR_FACING` walks to the
blue-roof mart (south / north / east; west has no case), then `giveitem`
a Potion. That sets `FLAG_RECEIVED_POTION_OLDALE` and they stay at
(13,7). Talking from the east only sets `FLAG_TEMP_1`, so the next talk
is the explanation with no gift — pokeruby, not a special case. Indoor
clerks with extracted stock still open the mart. No cache bump.

## Phase 77 — Oldale mart `pokemart`

`pokemart` (0x86 plus a `u16` list ending in `ITEM_NONE`) is parsed and
run. Talking to the indoor clerk is the ROM script: "How may I serve
you?", then basic stock (Potion / Antidote / Paralyze Heal / Awakening)
until `FLAG_ADVENTURE_STARTED`, then Poké Balls lead the expanded list.
B leaves and "Please come again!" The woman says balls are sold out
until that flag. NPC scripts run before the gfx-83 shop stand-in, so
extracted clerks no longer ignore the cart. No cache bump; re-import
picks up lists that used to stop at 0x86.

## Phase 78 — Petalburg gym boy

First visit (`VAR_PETALBURG_STATE` 0) parks the gym boy (local 9) at
(5,11). Stepping the x=8 column (y=10–13) from Route 102 is the escort:
exclaim, "Are you a rookie TRAINER?", walk to the gym, the sign, then he
walks west. pokeruby does not bump that var here — Emerald's set-to-1
is a later cart. New-game hide flags cover Wally and his parents at the
gym door; street Wally-Mom stays visible ("Where has our WALLY gone?").
No cache bump.

## Phase 79 — Petalburg gym Dad / Wally send-off

ON_TRANSITION gym-state < 6 parks Norman (local 1) at the entrance
(4,107). Talking from the door (`VAR_FACING` north) is the Wally
send-off: addobject 10, loan Zigzagoon + POKe BALL lines, then warp
`MAP_PETALBURG_CITY` (15,8) with gym-state 1 / city-state 2. Return
ON_FRAME is "So, did it work out?" then Rustboro. City catch tutorial
(state 2 ON_FRAME) is later. No cache bump.

## Phase 80 — Petalburg Wally catch tutorial

City ON_FRAME at `VAR_PETALBURG_STATE` 2: SavePlayerParty, PutZigzagoon
(lv7, TACKLE only), walk to the east grass, "Watch me catch", then
special 157 vs a lv5 Ralts. Wally auto TACKLE + guaranteed ball; the
BAG is not spent and Ralts is not the player's. LoadPlayerParty, city
state 3, warp gym (4,108). Scripted walks follow the ROM step list even
past the 30-wide layout (Route 102 connection buffer). No cache bump.

## Phase 81 — the parser reads whole scripts

Scenes were being rebuilt one at a time because the parser could not read
past a command it did not implement: `decode` returned nil for anything
missing from `SIZE`, which dropped the rest of that branch. Every Ruby
command now has a length (pokeruby `include/macros/event.inc`, `map` args
counted as two bytes), so an unimplemented effect decodes as a nop and the
walk carries on. Only a byte that is not a command at all truncates.

`trainerbattle` is the one variable-length command — a 6-byte header plus
one pointer per `TRAINER_BATTLE_*` type — and its old lengths were wrong
for DOUBLE, REMATCH_DOUBLE and both CONTINUE_SCRIPT_DOUBLE types, so
whatever followed a double battle was decoded from the middle of a
pointer. `Gen3Script.cmdSize` is now the single authority both the parser
and the audit use.

`tools/gen3_script_audit.lua <rom>` walks every script reachable from the
map tables and reports what the VM can read. On Ruby: 394 maps, 2089
entry points, 45131 commands, 144 distinct, **0 truncations**, 96% of
commands by count implemented. It also measures the runaway guards
against the cart — the widest script is 823 commands and the deepest call
chain is 5, which is why `MAX_OPS`/`MAX_CALL` moved from 200/3 (29 and 1
scripts over) to 2048/8.

What is left is effect coverage, not parsing: 77 distinct commands parse
but do nothing (`specialvar`, `waitdooranim`, `multichoice`,
`createvobject`, `gotostd` lead by use), and 264 distinct specials are
called. `--specials` ranks them so the next scene comes from the cart
instead of a hand port. No cache bump, but re-import is needed: scripts
that used to stop early now bake in full.

## Phase 82 — the cart as an oracle

Scene work was being verified by reading pokeruby and asserting by hand,
which does not scale as special coverage grows. `tools/gba_oracle/` now
runs the real cart headlessly and reads its RAM, so the engine can be
checked against hardware.

mGBA is the accuracy reference but its released build has no `--script`
flag (autorun is master-only) and building master needs a C toolchain, so
the harness drives the mGBA **libretro core** through Python `ctypes`
instead: same emulator, plain DLL, no build, no GUI. IodineGBA would also
have worked but needs a JS runtime.

Addresses are quoted from the decomp, not guessed — pokeruby's
`include/global.h` carries them in the struct comments (`struct SaveBlock1
/* 0x02025734 */`), with `flags` at `+0x1220` and `vars` at `+0x1340`,
and the sizes derived from neighbouring offsets so they cannot drift.

`newgame.py` boots, drives the intro and naming screens judged from RAM
rather than frame counts, and checkpoints the first playable moment as a
savestate. `snapshot.py --delta` then reports what a scene changes, named:
leaving the moving truck sets `FLAG_HIDE_MAY_MOM_DOWNSTAIRS`,
`FLAG_HIDE_BRENDAN_UPSTAIRS`, `FLAG_HIDE_MOVING_TRUCK_MAY`,
`FLAG_HIDE_BRENDAN_MOM` and `VAR_LITTLEROOT_INTRO_STATE` 1, and warps
`25.40` to `0.9`. That output is the specification for implementing a
scene.

Two findings fell straight out of it. `check_specials.py` cross-checks
every `Game3.SPECIAL_*` against `gSpecials` by ordinal: 38 of 39 agree and
the last is only unnamed in the decomp, so the ids are sound. And naming
the audit's specials exposed that its counts were inflated — shared code
was tallied once per entry point that reached it, so `CloseLink` read 308
against the decomp's 20. Counting each ROM offset once brings totals from
45131 to 27721 and makes `CloseLink` 20 and `HealPlayerParty` 9, matching
the decomp exactly.

Known limit: `SaveBlock1.pos` only updates on a map transition, so it is
right for scene-level comparison and wrong for per-step movement — the
live position is `gObjectEvents[0]` in IWRAM.

## Phase 83 — the VM runs the commands the cart uses

Parsing was never enough: a sized command with no decode case was dropped
as a nop, so `specialvar` / `addvar` / `checkitem` never mutated state and
every `goto_if` after them branched on stale values. The VM now executes
the high-frequency state commands from pokeruby's `scrcmd.c`:

`specialvar` stores the special's return (so `specialvar VAR_RESULT,
GetDaycareState` actually works). `addvar`/`subvar` wrap at 16 bits the
way the cart does. `compare_var_to_var`, `checkitem`/`additem`/`removeitem`,
`checkmoney`/`addmoney`/`removemoney`, `getpartysize`, `getplayerxy`,
`random`, trainer flags (`0x500 + id`), `gotostd`, buffers, `waitdooranim`,
and `incrementgamestat` all have decode + run cases. Rematch / Pokerus
specials return 0, which is the first-playthrough answer.

The runtime step cap was still 200 after the parser moved to 2048, so a
long script could parse fully and then stop mid-scene; it now uses
`MAX_OPS` too.

Audit on Ruby after this: 87 of 144 distinct commands, **97% of sites**.
What remains is mostly presentation (`createvobject`, `multichoice`,
cries, field effects) plus the long tail of specials. No cache bump;
re-import still needed from Phase 81.

## Phase 84 — NEW GAME and the truck-exit freeze

NEW GAME only ran Birch's speech. Party, flags, vars, and map stayed
wherever CONTINUE had left them, so picking NEW GAME after a save dropped
you on the old tile. `startBirchSpeech` now resets that world state and
respawns in the moving truck (tests without imported maps keep their stub).

Getting off the truck then froze because the town ON_FRAME `warpsilent`s
into the house and `waitstate`s. `enterMap` used to run the dest ON_FRAME
in the middle of that script, which zeroed `_scriptPause` / `_scriptReturn`,
and an idle `field.kind == "wait"` never read the D-pad. Dest ON_FRAME /
coord events now wait until the warp script finishes, a warp shows the
player again (`hideobjectat LOCALID_PLAYER` is a door-close trick), and
`wait` auto-resumes when no special is holding `scriptWait`.

## Phase 85 — maps.lua is too big for LuaJIT

Phase 81 inlined every script into `maps.lua`. One `return { maps = { ... } }`
chunk then has more than LuaJIT's 65536 constants, so `CacheFs.loadActive`
returns nil, `data.maps` is `{}`, and both CONTINUE and NEW GAME miss
`enterMap`. `drawScene` with no map is the species list.

The extractor now writes a small index (`start`, `ids`, counts) to
`data/generated/maps.lua` and one file per map under `data/generated/maps/`.
`Gen3MapPack.load` assembles that pack, and still text-splits a legacy
15 MB `maps.lua` on first boot so the current cache does not need a
re-import.

## Phase 86 — story NPCs wait for their scripts

`EventScript_ResetAllMapFlags` sets 132 flags at new game so rivals, team
grunts, later-game NPCs, and event trainers stay off the map until a
script `clearflag`s them. Only eight of those flags were applied, so
templates spawned at their scripted coordinates from the first step.

NEW GAME now applies the full list (and a ROM import stores it on
`constants.resetMapFlags`). Trainers whose `flagId` is a `FLAG_HIDE_*`
are skipped the same way `TrySpawnObjectEvent` skips them; beaten route
trainers still stand because their defeat bit is `0x500 + id`.

## Phase 87 — house doormat coord events beat warps

pokeruby `TryStartStepBasedScript` runs coord scripts before warps. The
Littleroot 1F doormat is both a town warp and `GoSeeRoom` while
`VAR_LITTLEROOT_INTRO_STATE` is 4. Warping first let the player walk out
before the clock, skip the rival 2F script that writes
`VAR_LITTLEROOT_STATE` 1, and stay stuck at the Route 101 twin. Stepping
onto a tile now runs a matching coord event first. Sign BG events keep
their script pointer so a re-import can run the wall-clock ROM script;
the stopped-clock text path still sets intro 6 if no script is baked.
No cache bump.

## Phase 88 — ledges, OW anims, backs, faint, intro, TV

Walking into a solid jump metatile (`MB_JUMP_SOUTH` 0x3B and the other
seven directions) hops two tiles the way pokeruby `GetLedgeJumpDirection`
does. Tall grass always overlays sprites; water and general-tileset
flower tiles sway. Battle back pics are written for every used species,
not just the starters. `recalcStats` no longer revives a 0-HP mon.
Intro Groudon is species 405 and Azurill is 350 (older caches still
remap 389/298). Birch's speech uses his overworld sprite instead of a
tan square. Script walks stop on `MB_TELEVISION` so Mom's gym report
does not plant the player on the TV.

Re-import after this cache bump (`rom-cache-v10-ruby16`) so back pics,
title species, and tileset tile maps refresh.

## Phase 89 — trainers, battles, water, POKe BALL

Defeated trainers store `FLAG_TRAINER_FLAG_START + trainerId` (`0x500+id`)
so leaving a map and coming back does not re-spot them. Sight trainers
flash `!`, walk to the player, then a white/black battle transition.
`trainerbattle` (0x5C) is a real VM op: beaten is a nop, otherwise it
starts that trainer's party so rival and Team Aqua/Magma scripts fight.
Ocean/pond metatiles are blocked unless Surf is on. `POKé BALL` keeps
the e (`é` is GBA 0x1B). The FIGHT window is four moves plus TYPE/PP.
Battle pics slide in, lunge on a hit, and drop when fainted. Walk-in-place
holds a step so follow scripts stay aligned, and the camera tracks the
player sprite's visual centre.

Re-import after this cache bump (`rom-cache-v10-ruby17`) so baked
`trainerbattle` IR carries kind, trainer id, and intro text.

## Phase 90 — house tiles, TV, anims, bag, menus, faint, truck

Indoor `setmetatile` IDs (moving boxes, the running-shoes book) were
missing from the tileset atlas, so they drew as black squares. Script
walks no longer stop on `MB_TELEVISION`, so Mom's gym report can finish
in front of the set facing north. Water/flower VRAM slots only flip on
ponds and flowers, not ledges or treetops. One-frame sprites (Birch's
bag) stay on frame 0 when LOOK_AROUND faces west. Field menus use the
GBA triangle cursor. Early blackout with no heal point warps to the
bedroom, not Route 101. The moving truck is 48×48 (`OBJ_EVENT_GFX_TRUCK`
94); the extractor no longer rejects that size.

Re-import after this cache bump (`rom-cache-v10-ruby18`) so house
metatiles and the truck sprite land in the atlas.

## Phase 91 — battle pics, grass, leftover NPCs

Ruby species ids are not National Dex numbers. The Birch chase used 261
(an Old Unown slot) so Poochyena's front pic was missing and drew as a
square; the foe is internal 286. Back pics look up that same species id
and, if a back sheet is missing, use that mon's front instead of a
neighbor. Tall grass keeps its blades in the bottom metatile (top tiles
are empty), so the overlay pass now redraws that ground tile over
sprites. `setobjectxyperm` no longer rewrites ROM templates, so the
Littleroot twin and Oldale footprints man leave the map edge once their
story flags are set.

No cache bump.

## Phase 92 — trainer approach input, finditem despawn

`stepField` treated every unhandled overlay as the Start menu, so A/B
during a trainer `!` / walk-up opened POKéDEX or party summary. Approach
now returns early; only `kind == "menu"` is the Start menu. `callstd
STD_FIND_ITEM` matches pokeruby `Std_FindItem`: on a successful
`additem` it `removeobject VAR_LAST_TALKED`, so ground balls set their
template flag and stay gone.

No cache bump.

## Phase 93 — trainer lose text

pokeruby prints `GetTrainerLoseText` (`B_TXT_TRAINER1_LOSE_TEXT`, the
`trainerbattle` defeat pointer) after the last faint and before the
prize line. A win only showed "You defeated CLASS NAME! Got $N!". The
scripted lose speech is now the first victory page; A advances to the
prize, then back to the field.

No cache bump.

## Phase 94 — script paragraph breaks

GBA `\p` (0xFB) was dropped in `decodeText`, so loadword / trainerbattle
strings glued the next sentence on (`TRAINER!You`, `says.Do`). A
paragraph break is now a space, matching how `\n` already collapsed.
Cached IR still has the old glue; `expandScriptText` inserts the missing
space after `.` `!` `?` so current maps do not need a re-import.

No cache bump.

## Phase 95 — Route 102 berry trees

Route 102 objects `graphicsId` 60 (`OBJ_EVENT_GFX_BERRY_TREE`) run
`S_BerryTree`. The engine treated specials 43–49 as nops, so
`ObjectEventInteractionGetBerryTreeData` left `VAR_0x8004` at 0 and every
tree looked like empty soil. New game never ran
`EventScript_ResetAllBerryTrees` (`setberrytree` 0x8A).

`setberrytree` is decoded and run. Specials 43/45/46/47/48/49 get, plant,
pick, remove, water, and `PlayerHasBerries`. Special 44
(`Berry_FadeAndGoToBerryBagMenu`) selects the first berry in the bag
instead of opening the pocket UI. New game (and old saves with no tree
blob) plants pokeruby's default trees — Route 102 tree 1 Pecha / tree 2
Oran, stage 5, min yield 2. Trees persist in the save. Growth over time
is still a later pass.

No cache bump.

## Phase 96 — berry medicine and growth

Picked Oran / Pecha did nothing from the bag: `HEAL_AMOUNT` / `STATUS_HEAL`
only listed potions and status sprays. Oran restores 10 HP, Sitrus 30,
Pecha/Cheri/Chesto/Rawst/Aspear match their hold-effect cures, Lum is a
Full Heal. Field and battle BAG both go through those tables.

pokeruby `BerryTreeTimeUpdate` uses RTC minutes. There is no RTC here, so
one play-second is one berry-minute (`stageDuration` hours × 60). Pecha
and Oran take four 180-second stages to ripen. `setberrytree` / new game
set `growthSparkle` so default ripe trees do not wither until
`GetBerryTreeData` (talking) clears it, matching `PlantBerryTree` /
`ResetBerryTreeSparkleFlag`. Ripe berries that sit too long fall back to
a sprout; ten cycles blank the plot.

No cache bump.

## Phase 97 — held berries

Party commands were SUMMARY / SWITCH / field moves. pokeruby's party
ITEM submenu (GIVE / TAKE) was missing, so Route 102 berries could not
be held. GIVE opens the bag; Key Items and TMs/HMs stay ungiveable; a
second give swaps and returns the old item. Held item id is in the save.

In battle, `ItemBattleEffects` case 1 eats a held Oran/Sitrus at
`hp <= maxHP / 2` and status berries on a matching status. That runs
after poison/burn residual so a half-HP Oran can still save the turn.

No cache bump.

## Phase 98 — Petalburg Woods grunt

The woods grunt is `OBJ_EVENT_GFX_VAR_1` (241). pokeruby's
`GetObjectEventGraphicsId` reads `VAR_OBJ_GFX_ID_1` (`0x4011`). Only
`VAR_0` (the rival) was resolved, so the Magma grunt was a missing
sprite. ON_TRANSITION already extracts `SetupEvilTeamGfxIds` (Ruby:
Magma M/F, Aqua as the "good" team, Maxie/Archie). `resolveGraphicsId`
now covers `GFX_VAR_0`..`F`; unset `VAR_0` still falls back to gender.

`trainerbattle_no_intro` (kind 3 / `TRAINER_GRUNT_36` = 575) skipped the
ROM intro pointer but still waited on "would like to battle!". That now
opens the fight menu, matching `EventScript_DoNoIntroTrainerBattle`.

Story vars `0x4000`–`0x7FFF` persist in the save so
`VAR_PETALBURG_WOODS_STATE` (and Petalburg / lab / Route 101) survive
CONTINUE. Special vars `0x8000+` stay scratch.

No cache bump.

## Phase 99 — Wailmer Pail and empty plots

Route 104's flower shop gives `ITEM_WAILMER_PAIL` (268). The ROM bag
use is `ItemUseOutOfBattle_WailmerPail` / `TryToWaterBerryTree`: facing
a growing tree (stages 1–4) waters it; empty soil or ripe berries print
Dad's advice. The Pail is a Key Item and cannot be given. Talking to a
tree still uses `checkitem` in `S_BerryTree`.

`get_berry_tree_graphics` hides stage 0, so a picked plot is loamy soil
instead of a leftover gfx-60 tree. Early/late stage sheets (gfx 61/62)
are not on map templates, so those pics stay a later extractor pass.

No cache bump.

## Phase 100 — Roxanne CONTINUE_SCRIPT

Rustboro gym's `trainerbattle_single TRAINER_ROXANNE, ..., RoxanneDefeated,
NO_MUSIC` is kind 1 (`TRAINER_BATTLE_CONTINUE_SCRIPT_NO_MUSIC`). pokeruby
loads the 3rd pointer into `sTrainerBattleEndScript`; after a win,
`EventScript_DoTrainerBattle` `gotobeatenscript`s there (Stone Badge,
`FLAG_BADGE01_GET`, `VAR_RUSTBORO_STATE`, TM39). Decode only kept intro
and defeat, so the engine resumed at the next opcode — the already-
defeated talk-again path — and never set the badge.

Kind 1/2 parse the 3rd pointer (6/8 the 4th) as `after`. A started
continue-script fight pauses on that body; a nop (already beaten) still
walks `i + 1`. Kind 3 (woods grunt) has no `after`, so
`gotopostbattlescript` is unchanged.

Re-import after this cache bump (`rom-cache-v10-ruby19`) so gym maps
carry the beaten scripts.

## Phase 101 — Miracle Seed and badge boosts

Petalburg Woods gives `ITEM_MIRACLE_SEED` (205). pokeruby
`CalculateBaseDamage` walks `gHoldEffectToType` and applies
`(holdEffectParam + 100) / 100` to Attack or Sp. Atk when the move
type matches. `parseOneItem` now keeps `holdEffect` / param; caches
without those fields still map the 17 type-power items by id
(Miracle Seed → `HOLD_EFFECT_GRASS_POWER` 48, param 10).

The Stone Badge's `BADGE_BOOST(1, attack)` is a 10% physical Attack
bump for the player in trainer battles (not wild, not the foe). Heat
(defense) and Mind (Sp. Atk / Sp. Def) use the same helper.

No cache bump.

## Phase 102 — bag TMs/HMs teach

Bag TM/HM use is `ItemUseOutOfBattle_TMHM` / `TeachMonTMMove`, not a
field cut. `ITEM_TM01` (289) through `ITEM_HM08` (346) index
`TMHMMoves[]`; TM39 is Rock Tomb (317), HM01 is Cut (15).
`CanMonLearnTMHM` tests `gTMHMLearnsets[species]` bit `item - ITEM_TM01`
(HM01 = bit 50). Eggs are 0. A TM is consumed; an HM is not. Four moves
opens the forget UI.

`parseTmhmLearnsets` stamps `{ lo, hi }` on each species. Bag use opens
the teach party list. Field Cut/Surf/etc. stay on the party field-move
list (`useCut()`, …). Bag HM01 facing a tree does not chop it.

Re-import after this cache bump (`rom-cache-v10-ruby20`) so species rows
carry the compatibility bits.

## Phase 103 — berry tree stage sprites

Map templates only stamp `OBJ_EVENT_GFX_BERRY_TREE` (60). pokeruby
`get_berry_tree_graphics` then swaps `gBerryTreeGraphicsIdTable`:
planted and sprouted use gfx 61, taller / flowering / berries use gfx 62.
Those two sheets are never object-event ids on a map, so the extractor
now always pulls `ow_61.png` / `ow_62.png` with the player forms.

Stage 0 stays invisible loamy soil. Per-berry pic tables (Cheri vs
Pecha fruit frames) are still one shared late sheet.

Re-import after this cache bump (`rom-cache-v10-ruby21`).

## Phase 104 — obtain item and PokéNav

Cutter's house `giveitem ITEM_HM01_CUT` and the tunnel grunt's
`giveitem ITEM_DEVON_GOODS` are `callstd STD_OBTAIN_ITEM` (0).
`Std_FindItem` (1) is the item-ball line. Both used to print
`Found %s!`. They now match `obtain_item.inc`: obtain is
`Obtained the {item}.`, find is `{PLAYER} found one {item}!`.
A full bag sets `VAR_RESULT` 0. The put-away pocket line is Phase 105.

`ITEM_DEVON_GOODS` (269) and `ITEM_LETTER` (274) are Key Items.
Mr. Stone's `FLAG_SYS_POKENAV_GET` (0x802) inserts `POKeNAV` on
START after BAG (`start_menu.c`). A is a stub HOENN map; B returns.

No cache bump.

## Phase 105 — put-away pocket and Briney's boat

`obtain_item.inc` `Text_PutItemInPocket` is the second page after a
successful `callstd` 0/1: `{PLAYER} put away the {item} in the
{pocket} POCKET.` Full bag still skips it.

Mr. Briney's first sail has no `warp MAP_DEWFORD_TOWN`. After the
hidden-player boat path, `showobjectat LOCALID_PLAYER, MAP_DEWFORD_TOWN`
is the landing (`scrcmd.c`). That now warps to that map, standing on
`OBJ_EVENT_GFX_MR_BRINEYS_BOAT` (88) when the dest has one. While the
player is hidden, remaining `applymovement` snaps so the long sail does
not walk off Route 104 into empty space. House YESNO →
`VAR_BOARD_BRINEY_BOAT_ROUTE104_STATE` 1 → warp to the dock → ON_FRAME
is already extracted.

Re-import after this cache bump (`rom-cache-v10-ruby22`) so cached IR
keeps the `showobjectat` map group/num.

## Phase 106 — Flash radius and Brawly's gym

`MapHeader.cave` at +0x15 is `requires_flash` (Granite Cave B1F/B2F),
not every `MAP_TYPE_UNDERGROUND`. 1F and Steven's room stay lit.
`SetDefaultFlashLevel` (`overworld.c`) sets `flashLevel` 4 on a dark
cave, or 1 if `FLAG_SYS_USE_FLASH` is already set. `setflashradius`
(0x99) and `animateflash` (0x9A) write the same slot — Dewford gym
ON_TRANSITION starts at 4 and brightens as Hideki / Tessa / Laura
fall, then 0 after Brawly.

HM05 Flash is legal only at max darkness (`gMaxFlashLevel` 4) and
lands on radius 72 (`sFlashLevelPixelRadii`). The overlay is a hard
circle at the screen center, matching the scanline window.

Re-import after this cache bump (`rom-cache-v10-ruby23`).

## Phase 107 — multichoice

`multichoice` (0x6F), `multichoicedefault` (0x70), and `multichoicegrid`
(0x71) were sized nops dropped from IR. Early-game uses them for the
Rustboro school blackboard (`multichoicegrid` list 13: PSN/PAR/SLP/BRN/FRZ/CANCEL),
Dewford's Old Rod follow-up (list 50: Excellent! / Not so hot, ignore B),
and Briney's sail lists (0 = PETALBURG/SLATEPORT/CANCEL, 14 = DEWFORD/CANCEL).

The VM pauses `"choice"` and writes the index to `VAR_RESULT`. B is
`MULTI_B_PRESSED` 127 unless `ignoreB`. Lists longer than 3 wrap
(`script_menu.c` `tDoWrap`). `switch` is already `copyvar` + `compare` +
`goto_if_eq`. Unknown list ids write 127 and keep going.

Re-import after this cache bump (`rom-cache-v10-ruby24`) so cached IR
keeps the three commands.

## Phase 108 — Rustboro in-game trade

House 1's trader is `gIngameTrades[0]`: your Slakoth for Elyssa's
Makuhita nicknamed MAKIT (`trade.c`). `GetInGameTradeSpeciesInfo` (252)
buffers the two species names and returns the requested id.
`SelectMonForNPCTrade` (159) is the party list; B writes 255
(`PARTY_SIZE` cancel). Eggs are species 0. A matching slot is replaced
in `CreateInGameTradePokemon` (253) at the given mon's level, with the
decomp IVs / PID / OT / X Attack. The cable scene (254) is a waitstate
nop — the swap already happened.

No cache bump.

## Phase 109 — Route 104 doubles (Gina & Mia)

`trainerbattle` DOUBLE (kind 4) and the CONTINUE_DOUBLE / REMATCH_DOUBLE
kinds load a 3rd pointer, `sTrainerCannotBattleSpeech`. The cart's
`EventScript_TryDoDoubleTrainerBattle` calls `HasEnoughMonsForDoubleBattle`
(`GetMonsStateToDoubles`): one party slot is `PLAYER_HAS_ONE_MON` (1);
otherwise non-egg HP>0 count, 0 if two or more, else 2. Short of two
usable mons, `ScrSpecial_ShowTrainerNonBattlingSpeech` shows that pointer
and `end`s — it does not fall through to Gina's post-battle
`GetPlayerBigGuyGirlString` (special 148: `"Big guy"` / `"Big girl"`).

The parser now keeps `cannot` for kinds 4 / 6 / 7 / 8 (kind 6/8 `after`
stays at the 4th pointer). The VM shows it and breaks. Kinds 4/6/7/8
force a doubles fight when the party is ready.

Re-import after this cache bump (`rom-cache-v10-ruby25`) so cached IR
keeps the 3rd pointer.

## Phase 110 — Petalburg Center starter check

The woman in Petalburg's Pokémon Center calls `specialvar VAR_RESULT,
IsStarterInParty` (special 302) and only then explains Grass / Fire /
Water. `GetStarterPokemon(VAR_STARTER_MON)` is Treecko / Torchic /
Mudkip (0/1/2). Eggs are `SPECIES_EGG` and do not count; an evolved
starter does not either. `specialvar` only keeps the return if
`VAR_RESULT` changed, so the special writes that var.

No cache bump.

## Phase 111 — Quick Claw

`battle_main.c` rolls one `gRandomTurnNumber` per turn. A held Quick
Claw (`HOLD_EFFECT_QUICK_CLAW` 26, param 20) sets that battler's speed
to `UINT_MAX` when the roll is `< (param * 0xFFFF) / 100` (13107).
Priority still wins. Both sides see the same roll. Unextracted item
rows still map item 183.

No cache bump.

## Phase 112 — Dewford trendy phrase

Dewford Hall and the town phrase-boy call `Common_EventScript_BufferTrendyPhrase`: `setvar VAR_0x8004, 0` then `BufferTrendyPhraseString` (special 126). NEW GAME's `InitDewfordTrend` rolls five condition + hobby/lifestyle Easy Chat pairs and sorts by popularity so slot 0 is the current phrase (`ConvertEasyChatWordsToString` is `"WORD WORD"`). `IsTrendyPhraseBoring` (127) is the girl who is tired of it. `BufferRandomHobbyOrLifestyleString` (128) fills `{STR_VAR_2}`. `GetDewfordHallPaintingNameIndex` (129) is `(word0 + word1) & 7` for the painting / debate scripts.

The Easy Chat editor is Phase 121 (`ShowEasyChatScreen` special 95, mode 9).

No cache bump.

## Phase 113 — Exp. Share

Mr. Stone's `ITEM_EXP_SHARE` (182, `HOLD_EFFECT_EXP_SHARE` 25) splits EXP the way `cmd_getexp` cases 1–2 do: `calculatedExp = yield * level / 7`. If any living non-egg holds Exp. Share, participants get `calculated/2/viaSentIn` (min 1) and holders get `calculated/2/viaExpShare` (min 1); a fighter holding it gets both. Otherwise participants get `calculated/viaSentIn`. Trainer 1.5× is applied per recipient after the split. A fainted Share holder does not count. `battle.sentIn` is set on wild/trainer send-out and on `switchTo`. Lucky Egg stays for a later slice.

No cache bump.

## Phase 114 — traded EXP

Rustboro house 1's Slakoth-for-Makuhita trade stamps Elyssa's OT (`otId` 49562, `otName` `"ELYSSA"`). `IsTradedMon` / `IsOtherTrainer` then apply the 1.5× in `cmd_getexp` case 2 after the trainer bonus: `floor(amount * 3 / 2)`. The line is `BattleText_BoostedExp` (`"gained a boosted"`). A missing `otId` is a pre-this-slice save and counts as own. `GiveMonToPlayer` (`addToParty` / `sendToPc`) stamps the player's id and name unless the mon already has one.

No cache bump.

## Phase 115 — Rock Tomb / Steel Wing secondaries

Roxanne's Rock Tomb is `EFFECT_SPEED_DOWN_HIT` (70) with a 100% secondary. Steven's TM47 Steel Wing is `EFFECT_DEFENSE_UP_HIT` (138) at 10%. Both go through the same hit-secondary path as burn/flinch: Serene Grace doubles the roll, Shield Dust blocks drops on the target, Clear Body still refuses the drop, and user stat-ups (Steel Wing / Metal Claw) are not Shield Dust. Crunch and Shadow Ball (`EFFECT_SPECIAL_DEFENSE_DOWN_HIT` 72) share the drop helper.

No cache bump.

## Phase 116 — Sand-Attack / accuracy stages

Poochyena's Sand-Attack and Granite Cave's Flash are `EFFECT_ACCURACY_DOWN` (23). The hit roll uses pokeruby's `gAccuracyStageRatios` (`buff = atkAcc - defEva + 6`, then `dividend * moveAcc / divisor`): -1 is 75%, -6 is 33%. A 100% move therefore can miss after Sand-Attack (`Random() % 100 + 1 > calc`). Keen Eye (Taillow, 51) blocks the drop. Flying / Levitate still ignore Ground Sand-Attack. Mud-Slap is `EFFECT_ACCURACY_DOWN_HIT` (73). Thunder in sun is 50% before stages; rain Thunder still cannot miss.

No cache bump.

## Phase 117 — Focus Energy

Route 104 Taillow learns Focus Energy at 4 (`EFFECT_FOCUS_ENERGY` 47). `atk9A_setfocusenergy` sets `STATUS2_FOCUS_ENERGY` (`mon.focusEnergy`); a second use fails. `atk04_critcalc` adds +2 stages, then +1 for Slash / Razor Wind / Sky Attack / Blaze Kick / Poison Tail, capped at 4. `sCriticalHitChance` is `{16, 8, 4, 3, 2}`. Wally's tutorial and Birch's chase cannot crit. Switching or starting a new fight clears it.

No cache bump.

## Phase 118 — Brawly gym moves

Brawly's Machop uses Seismic Toss (`EFFECT_LEVEL_DAMAGE` 87, ROM power 1). After typecalc (Ghost still immune; Wonder Guard still sees the real multiplier) `dmgtolevel` sets damage to the user's level and clears SE/NVE, so there is no crit, STAB, weather, or 85–100 roll. Endure still leaves 1 HP.

His Makuhita's Knock Off (`EFFECT_KNOCK_OFF` 188) is a 20-power Dark hit with a 100% secondary. Gen 3 has no 1.5×-if-holding-item bonus. After damage, Sticky Hold (60) keeps the item and prints `BattleText_MadeIneffective`; otherwise the item is cleared. Shield Dust does not block it (`MOVE_EFFECT_KNOCK_OFF` is 0x36, and Shield Dust only filters effects ≤ 9). A KO skips the secondary, so the fainted mon keeps the item.

No cache bump.

## Phase 119 — gym leader Potions

Roxanne carries two Potions and Brawly two Super Potions (`gTrainers[].items`, four `u16` at trainer-row +0x10). `ShouldUseItem` spends a heal when HP is below 25% or the missing HP is greater than the item's restore (so it does not top off a scratch). Items always go before moves. Sticky later slots if more living mons remain than leftover items. `BattleText_Used2` / `BattleText_RestoredHealth`. Full Restore still uses the stricter `< max/4` rule. Re-import to pick the items up from the ROM; runtime also accepts `npc.items`.

No cache bump.

## Phase 120 — Double Team / always-hit

Route 104 Taillow learns Double Team at 19 (`EFFECT_EVASION_UP` 16). That is the same +1 EVASION stage already used in `gAccuracyStageRatios` (+1 foe evasion is 75%). A seventh use prints that EVASION will not go higher. Swift and Aerial Ace are `EFFECT_ALWAYS_HIT` (17) with ROM accuracy 0; `copyMove` no longer turns 0 into 100, so Sand-Attack cannot make them miss. Vital Throw (78) skips the accuracy roll the same way, even at 100 listed accuracy.

No cache bump.

## Phase 121 — Dewford Easy Chat editor

Dewford's phrase-boy (`DewfordTown_EventScript_RejectTrendyPhrase`) does `setvar VAR_0x8004, 9` then `call Common_EventScript_ShowEasyChatScreen`. That common script is `special ShowEasyChatScreen` (special **95**) with no `waitstate`; the ROM steals `SetMainCallback2`, so the VM now pauses if the special armed `scriptWait`. Other Easy Chat modes still set `VAR_RESULT` 0 and do not wait.

Mode 9 prefills the two words from `easyChatPairs[0]` and sets `FLAG_SYS_CHAT_USED` (0x805). Slot 0 lists Conditions; slot 1 lists Hobbies then Lifestyle. A picks and advances; after both words, submit. B on slot 0 cancels (`RESULT` 0, no `sub_80FA364`); B on slot 1 goes back. Unchanged strings also `RESULT` 0 (the ROM refuses confirm via `sub_80E7FA8`).

Confirm of a changed phrase sets `RESULT` 1 and `VAR_0x8004 = sub_80FA364`: a pair already in any of the five slots is not trendy (`0x8004` 0). The first unique phrase (`FLAG_SYS_POPWORD_INPUT` 0x833 unset, and `FLAG_SYS_MIX_RECORD` 0x834 unset) overwrites slot 0's words only and returns TRUE. Later unique phrases roll popularity (`rising=1`) and insert by higher `pop`, then `maxPop`, else `Random() & 1`; TRUE only if they land at index 0. Beating nobody overwrites slot 4 and returns FALSE. Script `compare VAR_0x8004, 0` is "not trendy enough"; else "Of course I know about that."

No cache bump.

## Phase 122 — battle Teleport

Granite Cave Abra only knows Teleport (`EFFECT_TELEPORT` 153, accuracy 0, `TARGET_USER`). The ROM script has no accuracy check: trainers print `But it failed!`; a wild user calls `CanRunFromBattle`. That returns 0 unless Wrap / Mean Look / Ingrain / Birch's chase / Wally's tutorial block it (1) or Shadow Tag / Arena Trap / Magnet Pull block it (2, `BattleText_MadeIneffective2`). Smoke Ball (`HOLD_EFFECT_CAN_ALWAYS_RUN` 37) and Run Away skip those checks. Flying and Levitate ignore Arena Trap; Magnet Pull only holds Steel. Success prints `{ATTACKING_MON} fled from battle!`, sets `B_OUTCOME_PLAYER_TELEPORTED`, and skips the rest of the turn (no residual, no EXP). A ball still goes first (item priority 7).

No cache bump.

## Phase 123 — Low Kick

Hideki (Dewford gym) has Machop lv14 with default moves; Low Kick is the STAB. The ROM lists power **1** (`EFFECT_LOW_KICK` 196), then `weightdamagecalculation` (`atkDD`) sets `gDynamicBasePower` from `sWeightToDamageTable` against `GetPokedexHeightWeight(SpeciesToNationalPokedexNum(target), 1)` — tenths of a kilogram from `gPokedexEntries`, not base stats. The first threshold **greater than** the weight wins; else power 120. Starters are all 20 (Treecko 50 / Torchic 25 / Mudkip 76). Machop itself is 195 → 40; Aron 600 → 80; Wailord 3980 → 120.

Unlike Seismic Toss, this is still a normal hit: STAB, crit, 85–100, and the type chart all apply. Ghost is immune. `Game3.DEX_WEIGHT` is the pokeruby species→weight table (no cache bump). `mon.weight` overrides it.

No cache bump.

## Phase 124 — Bide

Tessa and Laura send Meditite with Bide from lv1 (`EFFECT_BIDE` 26, ROM power 1, `TARGET_USER`). The first use is `setbide`: lock the move, `gTakenDmg = 0`, two Bide turns. Each later action's atkCanceller decrements; the middle turn prints `{ATTACKING_MON} is storing energy!`; the last prints unleashed energy. Damage is `gTakenDmg * 2` with `adjustsetdamage` (no 85–100), then `typecalc` (Ghost still immune) and the SE/NVE flags cleared. No stored HP prints `But it failed!`. Flinch / paralysis / confusion self-hit run `CancelMultiTurnMoves`. PP is spent only on the opening turn.

No cache bump.

## Phase 125 — Granite Cave holes

Granite Cave B1F's ON_RESUME is `setstepcallback 7` then `setholewarp MAP_GRANITE_CAVE_B2F, 255, 0, 0`. Callback 7 already cracked `MB_CRACKED_FLOOR` (0xD2) into a hole; a second step onto `MB_CRACKED_FLOOR_HOLE` (0x66) snapped to **this** map's spawn. The ROM's `PerStepCallback_806A07C` sets `VAR_ICE_STEP_COUNT` 0 on a hole, and on a crack unless Mach Bike speed 4, then ON_FRAME runs `EventScript_FallDownHole` → `warphole MAP_UNDEFINED` → `SetFixedHoleWarpAsDestination` at the player's xy.

Walking a crack now falls (Mach Bike still cracks the tile and rides it). `setholewarp` (0x41) / `warphole` (0x3C) land on the dest map at the same cell. Cached IR still nops those two commands, so Granite B1F (`g24_8`) falls through to B2F (`g24_9`) without a re-import. Ice (callback 4) is unchanged: thin ice cracks, the next step drops.

No cache bump.

## Phase 126 — Mud Sport / Water Sport

Granite Cave 1F Geodude (lv6–9) learns Mud Sport at 6 (`EFFECT_MUD_SPORT` 201, ROM power 0, `TARGET_USER`). That used to fall through as `But it failed!`. The ROM's `BattleScript_EffectMudSport` has no accuracy check: `settypebasedhalvers` (`atkE8`) sets `STATUS3_MUDSPORT` on the user, or jumps to `ButItFailed` if that bit is already set. Water Sport (`EFFECT_WATER_SPORT` 210) is the same script with `STATUS3_WATERSPORT`. `gSportsUsedStringIds` prints `Electricity's power was weakened!` / `Fire's power was weakened!`.

`CalculateBaseDamage` then does `gBattleMovePower /= 2` when `AbilityBattleEffects(ABILITYEFFECT_FIELD_SPORT, …, 0xFD/0xFE)` finds the bit on **any** battler. Protect does not block it (move flags 0). `SwitchInClearSetData` zeroes `status3` unless Baton Pass kept those two bits.

No cache bump.

## Phase 127 — Fake Tears

Granite Cave Mawile (lv10–12) learns Fake Tears at 6 (`EFFECT_SPECIAL_DEFENSE_DOWN_2` 62, Dark, power 0). That used to fall through as `But it failed!`. The ROM's `BattleScript_EffectSpecialDefenseDown2` is `setstatchanger SP_DEFENSE, 2, TRUE` then `BattleScript_EffectStatDown`: accuracy, then `statbuffchange`. Two stages print `harshly fell!`; already at the floor prints `{stat} won't go lower!`. Protect and Clear Body / White Smoke block it. Hyper Cutter does not (Attack only). Metal Sound, Charm, Screech, and Cotton Spore share the same down-2 script.

No cache bump.

## Phase 128 — Escape warp (Dig / Escape Rope)

Granite Cave is `MAP_TYPE_UNDERGROUND`. Walking in from Dewford (`MAP_TYPE_TOWN`) runs pokeruby's `sub_80535C4`: if the current map is outdoor (town / city / route / ocean / underwater) and the dest is not, it writes `gSaveBlock1.warp4` at that xy. Dig and Escape Rope call `sub_8053678` and land there — the cave mouth — not the last nurse. TELEPORT and a blackout still use `lastHealLocation`. A deeper floor does not refresh warp4. `setescapewarp` (0xC4) overwrites it (harbors). Cached IR still nops that command until re-import; stepping through a door is enough for Granite.

No cache bump.

## Phase 129 — Museum money box / cries

Slateport's Oceanic Museum fee (`showmoneybox 0, 0` then `checkmoney 50`) and Route 109's Seashore House soda were sized nops, so the till still changed but the $ window never appeared. `OpenMoneyWindow` is a 14×4 tile frame at 8px tiles; hidemoneybox closes it and updatemoneybox reprints after `removemoney`. pokeruby's C reader consumes one extra ignore byte on show/update, which the scripts pad with `nop` — the IR drops nops, so that pad is invisible at runtime. `playmoncry` / `waitmoncry` are Peeko and the Route 109 Zigzagoon; with no extracted cry, wait is immediate. Cached IR still nops those until a re-import.

No cache bump.

## Phase 130 — Rage

Museum Magma/Aqua grunts send Carvanha (lv14–15). Default moves are Leer, Bite, Rage (lv7), Focus Energy (lv13). `MOVE_RAGE` is `EFFECT_RAGE` **81**, Normal, power 20, contact, Protect. `BattleScript_EffectRage` accuracy-checks first: a miss or Protect runs `clearstatusfromeffect USER` and drops `STATUS2_RAGE`. A pass `seteffectprimary`s the bit on the user even if Ghost immunity zeroes damage. `atk49` `ATK49_RAGE` then, when a foe's damaging hit actually lands on that battler, raises Attack one stage (`BattleText_RageBuilding`: `{DEFENDING_MON}'s RAGE is building!`) unless the stage is already +6. `TryClearRageStatuses` at turn start drops the bit if the chosen move is not Rage. Switch-out clears it.

No cache bump.

## Phase 131 — Seashore House drinks

Beating Dwayne / Johanna / Simon sets `FLAG_DEFEATED_SEASHORE_HOUSE_TRAINERS` and the clerk `giveitem ITEM_SODA_POP, 6`. Extra cans are `checkmoney 300` then `giveitem ITEM_SODA_POP`. Soda Pop is item **27**; `gItemEffect_SodaPop` is the potion heal template (`0x04`) for **60** HP (`ItemUseOutOfBattle_Medicine` / `ItemUseInBattle_Medicine`). Fresh Water **26** / Lemonade **28** / Moomoo Milk **29** are the same template at 50 / 80 / 100. Extracted item rows do not keep effect bytes, so `HEAL_AMOUNT` and the name/price fallbacks cover the drinks (and Hyper / Max Potion labels) without a cache bump.

No cache bump.

## Phase 132 — Itemfinder

Route 110's rival `giveitem ITEM_ITEMFINDER` (key item **261**). `ItemUseOutOfBattle_Itemfinder` scans this map's untaken hidden items (`BG_EVENT_HIDDEN_ITEM`, flag `FLAG_HIDDEN_ITEMS_START + hiddenId`) in a 15×11 window (`dx` −7..7, `dy` −5..5 — our cells are already map xy, so there is no +7 border). `sub_80C9838` keeps the closest Manhattan, then the smaller `|dy|`, then the larger `dy`. Standing on the tile prints `gOtherText_ItemfinderItemUnderfoot`; otherwise the player faces that item (`GetPlayerDirectionTowardsHiddenItem` through `gItemFinderDirections`) and prints `gOtherText_ItemfinderResponding`. Nothing in range is `gOtherText_NoResponse`. Connected-map tiles (`sub_80C9720`) are not scanned yet.

No cache bump.

## Phase 133 — Leech Seed

Route 110's rival (Torchic playthrough: May's Shroomish lv18) has Leech Seed from level 10. `MOVE_LEECH_SEED` is `EFFECT_LEECH_SEED` **84**, Grass, accuracy 90, Protect. `BattleScript_EffectLeechSeed` accuracy-checks into `setseeded`: a miss or a second seed prints `{DEFENDING_MON} evaded the attack!`; Grass (type1 or type2) prints `It doesn't affect {DEFENDING_MON}...`. Success sets `STATUS3_LEECHSEED` plus the sower's battler index (`STATUS3_LEECHSEED_BATTLER`). End of turn (`ENDTURN_LEECH_SEED`, before poison) saps `maxHP/8` (min 1) if both battlers are still up. The HP goes to whoever is in the sower's slot now. Liquid Ooze on the seeded mon reverses that heal (`BattleText_OozeSuckup`). Switch-out drops the bit.

No cache bump.

## Phase 134 — Foresight

Route 110's rival Marshtomp (lv20, Torchic playthrough) learns Foresight at 20. `MOVE_FORESIGHT` / `MOVE_ODOR_SLEUTH` are `EFFECT_FORESIGHT` **113**, Normal, accuracy 100, Protect. `setforesight` ORs `STATUS2_FORESIGHT` and always prints `{ATTACKING_MON} identified {DEFENDING_MON}!` — a second use does not fail. Accuracy uses only the user's accuracy stage (`buff = acc`), so Double Team / Minimize no longer apply; BrightPowder and Sand Veil still do. Damage typecalc breaks at the chart's `TYPE_FORESIGHT` (`0xFE`) sentinel, so Normal and Fighting vs Ghost become neutral instead of 0. Switch-out clears `STATUS2`. No cache bump; the extractor already drops the sentinel and keeps those two immunity rows.

No cache bump.

## Phase 135 — Hidden Power

Route 110 Edward and Jaclyn each send only Abra lv16 with Hidden Power. `MOVE_HIDDEN_POWER` is `EFFECT_HIDDEN_POWER` **135**, power 1, Normal, accuracy 100, Protect, King's Rock. `atkC1_hiddenpowercalc` then `goto BattleScript_EffectHit`. Type is IV bit 0 of hp/atk/def/spe/spa/spd packed as a 6-bit value: `floor(bits * 15 / 63) + 1`, then skip `TYPE_MYSTERY` (9) so the result is Fighting..Steel then Fire..Dark — never Normal or ???. Power is IV bit 1 of the same six: `30 + floor(bits * 40 / 63)` → 30–70. The move row's type is not mutated. Trainer `iv 0` is `fixedIV = iv * 31 / 255 = 0`, so Edward/Jaclyn are Fighting / 30. Cached trainer parties still omit `slot.iv` until a later re-import; runtime applies it when present.

No cache bump.

## Phase 136 — Nature Power

Route 110 Edwin's Lombre and Nuzleaf (lv14) learn Nature Power at 13. `MOVE_NATURE_POWER` is `EFFECT_NATURE_POWER` **173**, power 0, Normal, accuracy 95 unused (no `accuracycheck` on the wrapper), flags 0. `callenvironmentattack` sets `gCurrentMove` to `sNaturePowerMoves[gBattleEnvironment]` then runs that move's effect script. Terrain from `BattleSetup_GetEnvironmentId`: tall grass Stun Spore, long grass Razor Leaf, sand Earthquake, underwater Hydro Pump, ocean Surf, pond Bubble Beam, mountain Rock Slide, cave Shadow Ball, building and plain Swift. Nature Power itself ignores Protect; the called move does not. PP is paid on the Nature Power slot.

No cache bump.

## Phase 137 — grass cover

Tall grass is `METATILE_LAYER_TYPE_COVERED` (bottom + middle BGs, sprites on top). Phase 91 forced those cells to overlay and then blitted the whole bottom metatile over every grass tile on screen, so a 16×32 sprite walking through a patch was buried by the grass cell above its head. Cover is `FLDEFF_TALL_GRASS`: a 16×16 tuft on the object's current (and previous, while stepping) tile only, so the head stays in front. The tuft uses that cell's ground metatile and sways on the existing water/flower timer. No cache bump.

## Phase 138 — white-out home

`ScrSpecial_HealPlayerParty` (special 0) only restores HP/PP/status. Route 101 runs it after the starter bag; the truck already `setrespawn`’d the bedroom (`HEAL_LOCATION_LITTLEROOT_*_2F`, 4,2). Treating special 0 as `setrespawn` stamped the bag tile as `lastHeal`, so a wipe vs May (or any faint before a Center) warped there. White-out now leaves lastHeal alone, and a `MAP_TYPE_ROUTE` lastHeal (old saves) falls through to the bedroom like a missing heal point.

No cache bump.

## Phase 139 — grass tuft

Route 101 tall grass is `LAYER_NORMAL` in the attributes (high nibble 0) with tiles 4–7 all tile 0 (blank on GBA BG1). Phase 137 dropped the full-map grass pass but still stamped the opaque 16×16 ground metatile on every actor; that is the lower half of a 16×32 sprite, so only the hat showed. Grass (and any overlay metatile whose top tiles are 0) stays under sprites. The feet tuft is the bottom 8px of that cell, not the whole tile. No cache bump.

## Phase 140 — battle scene, menus, back pics

`gMonBackPicTable` is at `0x1E97F4`. The extractor used `0x1E9034` (the byte after the last front-pic row), so every back PNG was the wrong species — Torchic’s back was Camerupt. Front and back pointers for Bulbasaur must differ. `gMonFrontPicCoords` / `gMonBackPicCoords` y-offsets shift the 64×64 affine sprites whose centres are pokeruby `gUnknown_0837F578` (player 72,80; foe 176,40). Enemy healthboxes hide HP numbers; the player box shows them. Command menu is the ROM 2×2 FIGHT/BAG/POKéMON/RUN. Terrain BGs come from `sBattleEnvironmentTable` when that scan hits. START / BAG / party windows use the same white+blue frame. Re-import (`rom-cache-v10-ruby26`) so back pics and grass BGs rewrite.

## Phase 141 — Woods grunt, Rustboro employee, doubles

The Petalburg Woods Magma grunt is `OBJ_EVENT_GFX_VAR_1` until `SetupEvilTeamGfxIds` writes Magma M (119). Map templates never list 117–120, so `ow_119.png` was missing and the grunt rendered as the brown fallback square. Aqua/Magma M/F plus Archie/Maxie are always extracted. The woods fight is still the coord script’s `trainerbattle_no_intro` (kind 3 / trainer 575), not sight.

`METATILE_LAYER_TYPE_SPLIT` (tree trunks, the Devon Corp door/sign) was blitting the whole 16×16 top layer in front of sprites. Only the top 8px overlay; the bottom 8px stay with the ground, so a 16×32 OW sprite’s head is not buried by the cell it is standing in front of.

Rustboro’s “Oh, it’s you!” Devon employee is object 9 / `FLAG_HIDE_DEVON_RUSTBORO` (0x2DC). Stolen Goods `removeobject`s him, `setobjectxyperm` 30,10, then `clearflag` with no `addobject`. pokeruby `TrySpawnObjectEvent` brings him back; we now spawn/unhide on `clearflag` when that flag is a template hide flag.

Doubles use `gUnknown_0837F578` row 1 (`{32,80},{200,40},{90,88},{152,32}`), full 64×64 pics, and a healthbox per battler. FIGHT for the lead queues, then the partner’s command menu; B on the partner returns to the lead.

Re-import (`rom-cache-v10-ruby27`) so Magma/Aqua OW sheets exist.

## Phase 142 — talk lock, warps, field anim, battle HUD

Talking NPCs face the player and freeze (`talkLock`) until the box closes; `lock` / `lockall` / `release` now run. `MOVEMENT_TYPE_INVISIBLE` (0x4C) dummies — Devon 3F’s second gentleman on the conference table — spawn invisible and do not collide. Real Mr. Stone is object 1 at (17, 5), behind the desk, not on it.

A D-pad tap that is not the current facing only turns. Indoor stairs that land on a walkable warp facing a wall turn toward the first free tile, and held input from the previous map is ignored until release.

Ledge metatiles skip corner DMA. Surfable cells no longer shift the whole 16×16 (rocks in water were sliding). Grass tufts play once on step-in, not while standing.

Battle healthboxes show ♂/♀, a caught mark on the foe, and the player EXP bar. Evolution announces, plays a shrink/flash/grow, then applies the species — no silent swap. Message windows use the ROM white + 2px blue frame; missing FONT3 falls back to an 8px font. No cache bump.

## Phase 143 — Briney chase, Dewford Gym flash

`MOVEMENT_TYPE_WALK_SEQUENCE_*` (0x1D–0x34) now walk the four-dir loops. After rescuing Peeko (`VAR_BRINEY_HOUSE_STATE == 1`), the cottage ON_TRANSITION parks Briney at (9,3) type 0x32 and Peeko at (9,6) type 0x33 so they chase around the room instead of standing still.

Dewford Gym's `setflashradius` drew a stencil circle onto the 240×160 canvas. LÖVE 11 requires `stencil=true` on that Canvas; entering the gym crashed. The GBA canvas is bound with a stencil buffer, and the overlay falls back to a square hole if stencil still fails. No cache bump.

## Phase 144 — forget a move, static mountain ledges

Level-up no longer deletes move 1 when the set is full. pokeruby `yesnoboxlearnmove`: trying to learn → can't learn more than four → delete a move? YES opens the four slots plus CANCEL; NO asks whether to stop. An HM slot prints `HM moves can't be forgotten now` and returns to the list. CANCEL / stop-YES leaves the old set. The same prompt runs after battle EXP and after evolution.

Flower DMA tiles 127–130 sit next to rock/cliff tiles on mountain ledges. The fake water/flower flip was swaying those walls. Flower corners only animate when the 2×2 is not mixed with primary tiles above 130. No cache bump.

## Phase 145 — ROM fishing minigame

BAG Old/Good/Super Rod no longer 50%-and-battle. They run pokeruby `Task_Fishing`: lock, 1s wait, then `·` dots (first round `Random()%10+4` capped 10, later `+1`), A too early is "Not even a nibble..." / "It got away...", bite is `Random()&1` or no fish table, "Oh! A bite!" then reel 36/33/30 frames, extra rounds from `arr1+Random()%arr2` and Good/Super extra-round %, then "A POKéMON's on the hook!" and `FishingWildEncounter`. Water without a table still casts. Repel still does not block. No cache bump.

## Phase 146 — Brawly `animateflash` tween

`setflashradius` is still instant (`Overworld_SetFlashLevel`). `animateflash` was the same call, so Dewford Gym lights popped. pokeruby `sub_8081594` / `UpdateFlashLevelEffect` interpolates `sFlashLevelPixelRadii` at ±1px every other frame, stops when `cur > dest` (a shrink almost no-ops), locks the field (`ScriptContext_Stop`), then the gym's follow-up `setflashradius` matches. Hideki/Tessa/Laura and Brawly use this. No cache bump.

## Phase 147 — Dewford sail length and ministep speed

`DewfordTown_Movement_SailToPetalburg` is ~194 actions (`walk_fast_*` / `walk_fastest_*`). The IR stopped at `MAX_MOVE` 48, so the boat path was cut. The ROM walks until `STEP_END` (`0xFE`); the cap is 512.

`kindOfAction` already mapped `walk_fast` / `walk_fastest` to `"walk"`, but every tile used `WALK_PERIOD` (16 frames). pokeruby `do_go_anim` / `gUnknown_08376194` is 16 / 8 / 6 / 4 / 2 frames; slow (`sub_806468C`) is 32. Parsed walk steps now keep that speed; cached IR without `speed` still walks at 16.

A hidden player still snaps remaining applymovement (Briney hides you before the long path). The boat NPC does not: it lerps at ROM ministep speed. Re-import so the live cache stores the full sail.

No cache bump.

## Phase 148 — Dewford sail priority / offscreen

`DewfordTown_EventScript_SailToPetalburg` / `SailToSlateport` `setobjectpriority` / `resetobjectpriority` / `moveobjectoffscreen` decoded as nops, so Briney and the player Y-sorted against the boat while boarding.

pokeruby `ScrCmd_setobjectpriority` is `sub_805BCF0(..., priority + 83)` and `fixedPriority`. GBA sorts by that packed subpriority (lower first = in front). Script byte 0 is 83, 1 is 84; Y-sorted sprites sit at `0x73+1`. `resetobjectpriority` clears the pin. Player (255) ignores map group/num; other localIds only match the current `gG_N` map.

`moveobjectoffscreen` is `OverrideTemplateCoordsForObjectEvent`: copy live xy into this visit's template (no −7 border; our cells are already map-local) so Briney's wander home is the dock after he steps off. Re-import so the sail IR is no longer nops.

No cache bump.

## Phase 149 — Granite Cave Flash hole

Unlit `requires_flash` floors (Granite B1F/B2F) use `sFlashLevelPixelRadii[4]` = 24px at screen 120,80. The GBA camera can look into `MAP_OFFSET` 7 border tiles, so the player stays in that hole. Our layouts have no border; clamping to the grid put the hole on empty floor and the player in the black. While the overlay is up, the camera stays locked on the sprite (same as the padded cart).

The overlay is pokeruby's `SetFlashScanlineEffectWindowBoundaries` WIN0H midpoint circle, not a LÖVE stencil / square. Off-map void in the hole is black, not the outdoor blue.

No cache bump.

## Phase 150 — oracle NEW GAME match

The mGBA oracle's new-game snapshot (truck, layout 238, 133 flags) is now the spec for what `wipeNewGameState` / `spawnAtNewGame` must leave behind.

`EventScript_ResetAllMapFlags` still accounts for 132 of those flags. The extra one is `FLAG_SYS_TV_WATCH` (0x831): `UpdateTVScreensOnMap` sets it on every map load, including the truck. Size records are `InitShroomishSizeRecord` / `InitBarboachSizeRecord` (`0x8100` = Marco). Lottery and `VAR_OBJ_GFX_ID_0` stay random (trainer id).

`WarpToTruck` writes dummy warp xy. `SetPlayerCoordsFromWarp` then uses layout `width/2, height/2` — (2, 2) on the 5×5 truck — not the first walkable cell. Walking off the truck still matches: gender hide flags, `VAR_LITTLEROOT_INTRO_STATE` 1, `VAR_LITTLEROOT_HOUSES_STATE_2` 1, `FLAG_VISITED_LITTLEROOT_TOWN`, dest (3, 10). Gender hide flags are set at character select here and on the truck coord script on the cart; after the exit they agree.

`tools/gba_oracle/compare_engine.py` diffs a cart snapshot against those constants. `names.py` now resolves `(SYSTEM_FLAGS + n)` so visited-town flags print by name.

No cache bump.

## Phase 151 — Briney menu, Petalburg sail, cave battles

`message` + `waitmessage` stay in the 2-line FONT3 box. `multichoicedefault`
(Dewford list 0 at tile 21, 6) and `yesnobox` 20, 8 (`Std_MsgboxYesNo`) are
separate windows, matching `script_menu.c` / `menu.c`. The prompt is no
longer drawn at y=100 above that box.

Dewford → Petalburg is `showobjectat LOCALID_PLAYER, MAP_ROUTE104` then
`warp MAP_ROUTE104_MR_BRINEYS_HOUSE, 255, 5, 4` — Briney's house on Route
104, not Petalburg City. Hidden-player `applymovement` walks at ROM
ministep speed so the camera can follow the sail; snapping had jumped
off Dewford while the boat was still walking. Scripted move jobs unclamp
the camera the same way Flash does.

`tryWildEncounter` uses `MetatileBehavior_IsLandWildEncounter`: encounter
bit set and not surfable. Cave floors are `MB_INDOOR_ENCOUNTER` 0x0B (and
`MB_UNUSED_CAVE` 0x08). Short grass 0x07 is still a tuft, not a roll.

No cache bump.

## Phase 152 — Name Rater, Effort Ribbon, cycling road

Slateport's Name Rater (`SlateportCity_House1`) needs the TV / party
specials: `ScriptGetPartyMonSpecies` (SPECIES2, eggs are 412),
`IsSelectedMonEgg`, `TV_CopyNicknameToStringVar1AndEnsureTerminated`,
`TV_CheckMonOTIDEqualsPlayerID` (0 = own OT id), `MonOTNameMatchesPlayer`
(0 = own OT name), and `TV_PutNameRaterShowOnTheAirIfNicnkameChanged`
(compares `gStringVar3` from `ChangePokemonNickname` to the new nick).
The naming screen prefills the current nick the way `DoNamingScreen` does.

The Effort Ribbon woman uses `GetLeadMonIndex` (skip eggs),
`LeadMonHasEffortRibbon`, `ScrSpecial_AreLeadMonEVsMaxedOut` (sum ≥ 510),
and `GivLeadMonEffortRibbon` (`FLAG_SYS_RIBBON_GET`,
`GAME_STAT_RECEIVED_RIBBONS`). Fan Club `CheckLeadMonCool` and friends
are `>= 200`, not `> 50`.

Route 110 cycling road: `GetPlayerAvatarBike` (Acro=1, Mach=2),
`BeginCyclingRoadChallenge` / `FinishCyclingRoadChallenge` (vblank timer,
collisions on blocked `tryWalk`, score into `VAR_RESULT`, record in
`VAR_CYCLING_ROAD_RECORD_*`), `GetRecordedCyclingRoadResults` (specialvar
0/1 plus time/collision strings), and `UpdateCyclingRoadState` (clears
state 2/3 unless `gLastUsedWarp` was the north entrance, group 29 num 12).
`GetPlayerFacingDirection` is special 287.

No cache bump.

## Phase 153 — friendship, fadescreen, registered bike

Fan Club's Soothe Bell woman uses `GetLeadMonFriendshipScore` (special 230):
255→6, ≥200→5, ≥150→4, ≥100→3, ≥50→2, ≥1→1. Score 4 is the gift.

`CreateMon` starts at `gBaseStats.friendship` (70 if the live cache
predates byte 18). `AdjustFriendship` uses `sFriendshipEventDeltas`:
walking every 128 steps (`VAR_HAPPINESS_STEP_COUNTER`, 50% via
`Random() & 1`), level-up, gym/Elite Four/Champion at battle start,
and a higher-level foe faint. Eggs skip. Soothe Bell is
`HOLD_EFFECT_HAPPINESS_UP` (1.5× gains). A hatch is 120.

Museum Magma `fadescreen` is a 16-frame script delay, not a nop, so
`removeobject` happens on black. Rydel's `SwapRegisteredBike` (130)
toggles SELECT between Mach and Acro.

No cache bump.

## Phase 154 — EV yield from KOs

`MonGainEVs` runs for every party mon that receives EXP (sent-out or
Exp. Share). Yields are the 2-bit fields in `gBaseStats` at +0x0A
(HP/Atk/Def/Spe/SpA/SpD). Pokerus (`pokerus ~= 0`, including cured)
doubles; Macho Brace (`HOLD_EFFECT_MACHO_BRACE` 24) doubles again.
Per-stat 255, party total 510. Stats use `EV/4` in `CalculateMonStats`;
send-out (`prepBattler`) recals so the next fight sees them. Effort
Ribbon's 510 check is now reachable by battling.

No cache bump. Re-import to fill `evYield*` on live species rows;
a cache from before this parse still yields 0.

## Phase 155 — Mauville gym beams

Wattson's puzzle is `MauvilleGymSpecial2` (toggle beams in MapGrid
x 7..15, y 12..23), `MauvilleGymSpecial1` (press the switch in
`VAR_0x8004`, raise the other two), `MauvilleGymSpecial3` (all switches
down, every beam off), and `DrawWholeMapView` (nop: we already draw
`map.grid`). Coords include `MAP_OFFSET` 7, so switch `{7,16}` is map
tile `(0,9)`. Horizontal H3/H4 and vertical beams set
`MAPGRID_COLLISION_MASK` (bits 10-11) when they turn on.
`StorePlayerCoordsInVars` writes the player into `VAR_0x8004` /
`VAR_0x8005`.

No cache bump.

## Phase 156 — SELECT, Norman's doors, Trick House, cable car

Key Items register from the BAG with SELECT (toggle). Field SELECT
runs `UseRegisteredKeyItem`: empty/missing prints the cart's BAG hint
and clears the slot. Rydel's Mach/Acro swap can now find a registered
bike.

Norman's gym `PetalburgGymSlideOpenDoors` / `OpenDoorsInstantly`
write sliding-door frame 4 (`0x21C` / `0x224`) at the room in
`VAR_0x8004` (the five-frame slide is snapped). Trick House end-room
specials set/clear flag `0x259` (`FLAG_HIDDEN_ITEM_1`) and copy it to
`VAR_0x8004`. `SetHiddenItemFlag` is the generic version.
`GetPlayerTrainerIdOnesDigit` is the low 16 bits `% 10`.
`ShowFieldMessageStringVar4` talks `gStringVar4`.

`CableCarWarp` / `CableCar` skip the cinema and warp group 19:
`0x8004 == 0` is Mt. Chimney station (6,4), nonzero is Route 112
station (6,4).

No cache bump.

## Layout

| Piece | Where |
| --- | --- |
| Version row | `src/core/GameVersion.lua` (`ruby`, append-only `ORDER`) |
| Manifest | `tools/rom_manifest_ruby.json` |
| GBA header | `src/import/GbaHeader.lua` |
| GBA binary | `src/import/GbaBin.lua` |
| GBA LZ77 | `src/import/GbaLz77.lua` |
| Latin charset | `src/import/GbaText.lua` |
| Extractor | `src/import/RomExtractorGen3.lua` + `RomExtractorGen3Battle.lua` + `RomExtractorGen3Boot.lua` |
| Script IR | `src/import/Gen3Script.lua` |
| Script coverage audit | `tools/gen3_script_audit.lua` |
| Hardware oracle | `tools/gba_oracle/` (see its README) |
| Runtime | `src/core/Game3.lua` + `src/core/Game3Boot.lua` |
| Map cache shards | `src/import/Gen3MapPack.lua` |
| Cache contract | `CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.ruby` |

## Later engines

- The painted region map
