-- Ruby's service owner: the Gen 3 peer of src/core/Game.lua / Game2.lua.
-- Hoenn overworld: shared tileset atlases, warps, map connections.
-- Wild battles use ROM moves, catching, EXP, switching, evolution,
-- status, extra move effects, and abilities.  Trainers spot you on a
-- facing cone (or all four ways), and there is no RUN.  Battle BAG
-- throws balls (wild) and uses potions; trainers block balls.  The
-- field has START, talking, a nurse heal, item balls, a mart, hidden
-- items, and signs.  START saves; the title CONTINUE reloads.
-- NPC talk runs extracted script IR (msgbox, flags, finditem, yes/no).
-- New game starts with an empty party; Birch's bag (or Birch) offers
-- Treecko / Torchic / Mudkip.  Stats use IVs, EVs, and pid%25 natures.
-- 14 PC boxes of 30; A on a PC tile (behavior 0x83) opens storage.
-- Net/Dive/Nest/Repeat/Timer balls use Ruby's catch multipliers.
-- Weather (Rain/Sun/Sand/Hail), Drought/Drizzle/Sand Stream, and Trace.
-- Truant loafs every other turn; Pickup can find an item after a win.
-- Protect, self stat-ups, OHKO, and two-turn Fly / Dig / Solarbeam.
-- Skull Bash / Sky Attack / Razor Wind charge; Endure survives on 1 HP.
-- Birch's bag starts a Poochyena chase, then warps to the lab.  New games
-- begin in the moving truck when that map is in the cache, at the layout
-- centre (WarpToTruck dummy warp). NEW GAME wipes
-- party/flags/vars and respawns there so CONTINUE leftovers cannot drop
-- you on the old save tile. Walking off the truck drops you in Littleroot
-- (3,10 boy / 12,10 girl) with VAR_LITTLEROOT_INTRO_STATE set so the town
-- ON_FRAME script can run Mom's moving-in scene; warp/warpsilent
-- (0x39/0x3A) enter the house. A warp while a script is running defers
-- the dest ON_FRAME until that script ends, matching pokeruby.
-- Stepping onto a tile runs coord events before warps (GoSeeRoom on the
-- house doormat), so leaving before the clock cannot skip the rival.
-- setdynamicwarp (0x3F) is the truck's MAP_DYNAMIC dest; setrespawn (0x9F)
-- is the bedroom heal. playse is skipped so Mom's ROM script still parses.
-- MSGBOX_DEFAULT waits for A; then jump_right, Mom walks out, and both
-- enter the house.
-- After GivePokedex, Oldale's mart employee (gfx 83) is parked at (13,14)
-- and walks you to the shop for a Potion. Indoor clerks run pokemart
-- (0x86): basic stock until FLAG_ADVENTURE_STARTED, then Poké Balls.
-- A clerk with no script still opens the shop stand-in.
-- First visit to Petalburg (VAR_PETALBURG_STATE 0) parks the gym boy at
-- (5,11) so the Route 102 approach can lead you to the gym. Talking to
-- Dad at the gym entrance (4,107) is the Wally send-off; gym-state 1 is
-- the return ("did it work out?" then Rustboro). City state 2 is the
-- catch tutorial: SavePlayerParty / PutZigzagoon / Wally vs a lv5 Ralts,
-- then warp back to the gym door (4,108).
-- The wall clock still sets FLAG_SET_WALL_CLOCK; Mom (gfx 215) heals.
-- Doubles trainers send two; the partner picks a move, each side hits
-- the opposite slot, and a faint fills that slot from the remaining party.
-- Spread moves hit every listed target at half damage; FIGHT can pick a
-- foe in doubles. Sand Veil evades in a sandstorm and skips the residual.
-- After a starter, lab Birch hands over the POKeDEX; START lists seen
-- species.  special 0 heals the party only (Route 101 after the bag);
-- setrespawn (truck / Center ON_TRANSITION) writes lastHeal.  special 212
-- writes dex counts, 213 rates the catch.
-- Catching 200 Hoenn species and talking to lab Birch upgrades to the
-- National Dex (FLAG_SYS_NATIONAL_DEX); special 212 then sets VAR_0x8006.
-- Route 102 berry trees (gfx 60) run S_BerryTree: specials 43-49 plus
-- setberrytree (0x8A); new game plants EventScript_ResetAllBerryTrees.
-- Oran/Sitrus heal from the bag; Cheri-family berries cure status.
-- Trees grow on play time (1s = 1 RTC minute); new-game sparkle holds
-- ripe plots until you talk to them. Empty plots hide the sprite (stage 0).
-- Route 104's WAILMER PAIL (key item 268) waters a facing growing tree;
-- empty or ripe plots get Dad's advice. Talking still uses checkitem.
-- Oran restores HP in battle at half, Pecha cures poison.
-- Petalburg Woods ON_TRANSITION runs SetupEvilTeamGfxIds (VAR_OBJ_GFX_ID_1
-- = Magma M on Ruby). GFX_VAR_1..F resolve through those vars. Coord
-- triggers use trainerbattle_no_intro (kind 3): no "would like to battle"
-- line. Story vars 0x4000-0x7FFF persist in the save so woods state 1
-- survives CONTINUE.
-- applymovement walks one tile per step using the walk lerp; waitmovement
-- holds the script until that queue is empty. Delays, emotes, and
-- set_invisible / set_visible are real movement actions. Acro Bike hops
-- and jumps walk; affine/diagonal steps move; levitate lifts the sprite.
-- lockface keeps the last facing through walks; a nurse bow faces south;
-- rock smash / cut hide the obstacle; reveal pops a disguised trainer.
-- Script delay (0x28) pauses the VM for that many frames.
-- waitstate (0x27) pauses while a special has asked for a callback.
-- Rustboro house 1's NPC trade is gIngameTrades[0]: Slakoth for MAKIT
-- (Makuhita). SelectMonForNPCTrade B is PARTY_MENU 255.
-- trainerbattle DOUBLE (kind 4) is Gina & Mia on Route 104: two usable
-- party mons, or the 3rd pointer (cannot-battle speech) and no fight.
-- Doubles sprite centres are gUnknown_0837F578 row 1; FIGHT is chosen
-- per battler (lead, then partner).
-- GetPlayerBigGuyGirlString fills {STR_VAR_1} with Big guy / Big girl.
-- Petalburg Center's woman (special 302 IsStarterInParty) only explains
-- the starter's type while that species is still in the party.
-- Dewford Hall (specials 126-129) buffers the current trendy phrase
-- from InitDewfordTrend. ShowEasyChatScreen (special 95, mode 9) is the
-- phrase-boy editor: two Easy Chat words, then sub_80FA364.
-- Mr. Stone's EXP. SHARE (item 182, HOLD_EFFECT_EXP_SHARE 25) splits
-- EXP: participants and holders each get half of yield*level/7, then
-- trainer 1.5x, then traded-OT 1.5x (IsTradedMon). A fainted mon does
-- not count. Roxanne's Rock Tomb (EFFECT_SPEED_DOWN_HIT) and Steven's
-- Steel Wing (EFFECT_DEFENSE_UP_HIT) apply their secondary on a hit.
-- Sand-Attack / Flash (EFFECT_ACCURACY_DOWN) drop ACCURACY; the hit
-- roll uses gAccuracyStageRatios. Keen Eye blocks the drop.
-- Taillow's Focus Energy (effect 47) sets STATUS2_FOCUS_ENERGY: +2
-- crit stages (1/4), and fails if already pumped. Lost on switch.
-- Double Team (EFFECT_EVASION_UP) raises EVASION; Swift / Aerial Ace
-- (accuracy 0, EFFECT_ALWAYS_HIT) and Vital Throw cannot miss.
-- Granite Cave Abra's Teleport (EFFECT_TELEPORT 153) flees a wild fight
-- with no accuracy roll; trainers and Birch/Wally fail. Shadow Tag /
-- Arena Trap / Magnet Pull print MadeIneffective2. Smoke Ball and
-- Run Away bypass those. No EXP.
-- Hideki's Low Kick (EFFECT_LOW_KICK 196, ROM power 1) uses the
-- weightdamagecalculation table on the target's dex weight. Dewford
-- Meditite Bide (EFFECT_BIDE 26) stores two turns then deals 2x HP
-- taken, no 85-100 roll; Ghost still immune.
-- Granite Cave Geodude's Mud Sport (EFFECT_MUD_SPORT 201) sets
-- STATUS3_MUDSPORT; Water Sport (210) sets WATERSPORT. Either battler
-- halves Electric / Fire gBattleMovePower. A second use fails. Switch
-- (not Baton Pass) clears it.
-- Mawile's Fake Tears (EFFECT_SPECIAL_DEFENSE_DOWN_2 62) is a Dark
-- status: -2 SP. DEF, "harshly fell!". Metal Sound is the same
-- effect. Already -6 prints "won't go lower!". Protect blocks it.
-- Museum Carvanha's Rage (EFFECT_RAGE 81, power 20) is a Normal hit
-- that sets STATUS2_RAGE on a successful accuracy check. A miss or
-- Protect clears it. A later damaging hit on that battler raises
-- Attack one stage ("RAGE is building!") unless already +6. Choosing
-- any other move drops the bit (TryClearRageStatuses).
-- Seashore House Soda Pop (27) and the other drinks (Fresh Water 26 /
-- Lemonade 28 / Moomoo Milk 29) are ItemUseInBattle_Medicine with
-- gItemEffect_* heal amounts 50/60/80/100. Extra cans cost $300.
-- Route 110's rival giveitem ITEMFINDER (261). BAG use scans this
-- map's untaken hidden items in a 15x11 window (dx -7..7, dy -5..5),
-- faces the closest (Manhattan, then smaller |dy|), and prints
-- gOtherText_ItemfinderResponding / ItemUnderfoot / NoResponse.
-- Route 110 Shroomish Leech Seed (EFFECT_LEECH_SEED 84) is a Grass
-- status (90%). setseeded fails on Grass ("doesn't affect") or a
-- second seed ("evaded"). End of turn saps maxHP/8 (min 1) into the
-- sower's battler slot; Liquid Ooze reverses that heal. Switch-out
-- drops STATUS3_LEECHSEED.
-- Route 110 Marshtomp Foresight (EFFECT_FORESIGHT 113) is a Normal
-- status (100%). setforesight ORs STATUS2_FORESIGHT: later hits skip
-- the foe's evasion stage and the Ghost immunities after the type
-- chart's 0xFE sentinel. A second use still identifies. Switch-out
-- clears STATUS2.
-- Route 110 Edward / Jaclyn Abra only know Hidden Power
-- (EFFECT_HIDDEN_POWER 135). hiddenpowercalc sets type from IV bit0
-- (Fighting..Dark, skipping ???) and power 30+(bit1*40/63). Trainer
-- iv 0 is all-zero IVs so that Abra is Fighting / 30.
-- Route 110 Edwin's Lombre / Nuzleaf (lv14) know Nature Power
-- (EFFECT_NATURE_POWER 173). callenvironmentattack swaps in
-- sNaturePowerMoves[gBattleEnvironment]: tall grass Stun Spore,
-- long grass Razor Leaf, cave Shadow Ball, building/plain Swift.
-- Nature Power's own flags are 0 (Protect does not stop the swap);
-- the called move still checks Protect. PP comes off Nature Power.
-- Brawly's Seismic Toss deals the user's level; Knock Off strips a held
-- item (Sticky Hold / Shield Dust keep it). Gym leaders spend the
-- Potions on their trainer row when HP is low (ShouldUseItem).
-- multichoice / multichoicedefault / multichoicegrid (0x6F-0x71) pause
-- for a list from gMultichoiceLists. B is 127 unless ignoreB.
-- BAG HM01 / HM06 cut the tree or smash the rock in front, or mow grass.
-- HM03 Surfs onto water; HM04 Strength pushes boulders; HM05 Flash lights
-- a cave; HM07 climbs a waterfall while surfing.  HM02 Fly opens a visited
-- town list (Feather Badge) and warps to that map's spawn.  HM08 Dive
-- drops through deep water onto the paired underwater map (Mind Badge)
-- and the same HM surfaces again.  Wattson's gym (specials 139/140/144)
-- toggles the beam puzzle on MapGrid coords (MAP_OFFSET 7); DrawWholeMapView
-- (142) is a nop because we already draw map.grid.  SELECT registers a Key
-- Item from the BAG; field SELECT uses it. Norman's doors snap open.
-- Trick House end-room flag is 0x259. Cable car warps Route 112 <-> Chimney.
-- Rotating gates (201/202) are Fortree gym and Trick House puzzle 6:
-- bump an arm to spin it, a wall in the sweep blocks. Game Corner
-- GetSlotMachineId (286) picks a payout table; HasEnoughMoneyFor /
-- PayMoneyFor (197/198) use VAR_0x8005.
-- Granite B1F/B2F; setflashradius / animateflash are Brawly's gym lights
-- (sFlashLevelPixelRadii 72/56/40/24).  Flash is only legal at max
-- darkness.  The hole is the ROM WIN0 scanline circle at 120,80; while
-- it is up the camera does not clamp (GBA MAP_OFFSET 7 keeps the player
-- in that hole; our layouts have no border).  animateflash (Brawly) tweens
-- the hole at ±1px every 2
-- frames from field_screen_effect.c, then the script continues.  Old/Good/Super Rod run pokeruby Task_Fishing (wait, dots,
-- 50% bite, reel window, extra rounds) on facing water; Surf steps roll
-- water slots; Rock Smash can start a rock fight.
-- BAG Mach / Acro Bike hop on; B with running shoes (FLAG_SYS_B_DASH)
-- dashes on foot.  BAG Repel / Super / Max Repel last 100/200/250 steps
-- and skip land/water/smash fights at or below the lead's level.  Escape
-- Rope and DIG warp from a cave to warp4 (the outdoor tile you walked
-- in from: Dewford's cave mouth, not the last nurse). TELEPORT and a
-- blackout still use lastHeal. setescapewarp (0xC4) overwrites warp4.
-- showmoneybox (0x93) draws the $ window the museum fee / Seashore House
-- soda use; hidemoneybox / updatemoneybox close or reprint it.
-- playmoncry / waitmoncry (0xA1 / 0xC5) are Peeko and the Route 109
-- Zigzagoon. Cached IR still nops those until a re-import.
-- START POKeMON A uses TELEPORT from a town/route (same warp) or DIG
-- from a cave (same as Escape Rope). Neither is an HM and neither spends
-- an item.  SWEET SCENT (230) forces a land or water fight on that tile
-- (no rate roll, Repel does not block); otherwise "nothing here."
-- The Route 117 DAY CARE lady (OLD_WOMAN_2) takes up to two party mons.
-- Each step adds 1 EXP; taking one back costs $100 + $100 per level and
-- does not evolve.  Two compatible parents can leave an EGG (man on the
-- route, OLD_MAN_2). Party eggs hatch after egg-cycle steps.
-- Indoor TEALA (gfx 85) runs a CONTEST: category, rank, five appeal turns.
-- Matching-category moves score full appeal; a win stamps that ribbon.
-- Eggs cannot enter.
-- SECRET POWER (290) / TM43 on a cave or tree spot (behaviors 0x90–0x9D
-- or a BG event kind 8) makes one SECRET BASE. The interior is a small
-- room with a PC; the south wall warps you back out. A second spot asks
-- to move. CONTINUE stores the entrance.
-- Menus and dialogue use extracted latin FONT3 (8x16 4bpp) and GBA-style
-- windows. START is the right-side list. OPTION is the same menu as the
-- title: TEXT SPEED (6/3/1 frames), BATTLE SCENE, BATTLE STYLE SHIFT/SET,
-- SOUND. SHIFT asks to switch when a trainer sends the next POKeMON.
-- START on the player name opens the TRAINER CARD (ID, money, dex, time,
-- badges). SAVE asks first, matching pokeruby save_menu_util.c.
-- Dialogue typewrites at the chosen speed; A finishes the line, then
-- pages a 2-line FONT3 box (26 glyphs) the way pokeruby does.
-- Bike, Surf, and Dive swap the player to those overworld graphics. Map
-- ON_TRANSITION / ON_LOAD /
-- ON_FRAME and coord events run from the ROM so story flags are not
-- hardcoded per map. setobjectxyperm / setobjectmovementtype land before
-- NPCs spawn. A msgbox queued before waitmovement stays on screen.
-- Boot is copyright → intro → title PRESS START → CONTINUE/NEW GAME/OPTION
-- then Birch's speech, matching pokeruby intro.c / title_screen.c / main_menu.c.
-- hideobjectat / showobjectat toggle the sprite; showobjectat the player
-- on another map is Mr. Briney's landing (Dewford / Route 104 / 109).
-- setobjectpriority / resetobjectpriority pin GBA subpriority (byte+83)
-- so boarding draws in front of the boat. moveobjectoffscreen writes the
-- live xy into this visit's template (Briney's dock after the sail).
-- Hidden-player applymovement still uses ROM ministep speeds so the
-- camera can follow Briney's sail; snapping jumped the sprite off
-- Dewford and left the boat walking. The parser reads up to 512
-- actions so DewfordTown_Movement_SailToPetalburg is not cut at 48.
-- removeobject / addobject
-- use the hide flag. Cracked-floor step callback 7 breaks the tile and
-- falls through: walking (not the Mach Bike) drops on the crack itself,
-- a hole always drops. setholewarp / warphole land on the dest map at
-- the same xy (Granite Cave B1F → B2F). Ash (1) wipes the grass and counts soot;
-- Fortree (2) dips the bridge; Pacifidlog (3) sinks the log pair.
-- NEW GAME picks BOY/GIRL; the rival is the other one, uses gfx VAR_0,
-- and takes the starter with type advantage.  Route 103 starts that fight.
-- main.lua's bootGame picks this when GameVersion.generation() == 3.
--
-- IMPORTANT: do not use a catch-all __index that returns functions.  main.lua
-- also reads optional fields like Game.capturePath every frame; a truthy
-- function there is treated as a path and crashes io.open.

local GameVersion = require("src.core.GameVersion")
local GameViewport = require("src.render.GameViewport")
local Input = require("src.core.Input")
local PixelCanvas = require("src.render.PixelCanvas")
local TouchControls = require("src.core.TouchControls")
local SaveSerializer = require("src.core.SaveSerializer")
local Gen3Script = require("src.import.Gen3Script")
local Game3Boot = require("src.core.Game3Boot")

local Game3 = {}
Game3.__index = Game3

Game3.SCREEN_W = 240
Game3.SCREEN_H = 160
Game3.TILE = 16
-- pokeruby gWindows[] message box: 27 tiles wide, 2 FONT3 rows (8x16).
-- Inner text is 208px after the 8px frame, i.e. 26 glyphs.
Game3.MSG_LINES = 2
Game3.MSG_GLYPH_PX = 8
Game3.MSG_WIDTH_PX = 208
Game3.MSG_LINE_H = 16
-- pokeruby menu.c windows are 8x8 tiles. yesnobox 20, 8 is Std_MsgboxYesNo.
Game3.MENU_TILE = 8
Game3.YESNO_LEFT = 20
Game3.YESNO_TOP = 8
Game3.YESNO_RIGHT_OFF = 6
Game3.YESNO_BOTTOM_OFF = 5
Game3.MULTI_MAX_RIGHT = 29
-- pokeruby sTextSpeedDelays: SLOW / MID / FAST frames at 60 Hz.
Game3.TEXT_DELAY = { [1] = 6 / 60, [2] = 3 / 60, [3] = 1 / 60 }
Game3.WALK_PERIOD = 16 / 60
Game3.RUN_PERIOD = Game3.WALK_PERIOD / 2
Game3.MACH_PERIOD = Game3.WALK_PERIOD / 4
-- event_object_movement.c gUnknown_08376194 / sub_806468C.
-- speed 0 walk, 1 walk_fast, 2 ride current, 3 walk_fastest; slow is 32.
Game3.SCRIPT_STEP_FRAMES = {
  slow = 32,
  [0] = 16,
  [1] = 8,
  [2] = 6,
  [3] = 4,
  [4] = 2,
}

function Game3.scriptStepPeriod(step)
  local frames = Game3.SCRIPT_STEP_FRAMES[step and step.speed]
  if not frames then frames = 16 end
  return frames / 60
end
Game3.EMOTE_PERIOD = 32 / 60
Game3.SMASH_PERIOD = 32 / 60
-- scrcmd.c setobjectpriority adds 83; sUnknown_08376050[0]+1 is the
-- default Y-based subpriority when elevation is 0.
Game3.OBJECT_SUBPRIORITY_ADD = 83
Game3.DEFAULT_OBJ_SUBPRIORITY = 0x73 + 1
Game3.LEVITATE_PX = 8
Game3.FLY_PX = 16
Game3.EMOTE_GLYPH = { exclaim = "!", question = "?", heart = "<3" }
Game3.ATLAS_COLS = 32
Game3.STARTER_SPECIES = 280
Game3.TACKLE_POWER = 35
Game3.TACKLE_TYPE = 0
Game3.TYPE_FLYING = 2
Game3.TYPE_FIGHTING = 1
Game3.TYPE_POISON = 3
Game3.TYPE_GROUND = 4
Game3.TYPE_ROCK = 5
Game3.TYPE_BUG = 6
Game3.TYPE_GHOST = 7
Game3.TYPE_STEEL = 8
Game3.TYPE_MYSTERY = 9
Game3.TYPE_FIRE = 10
Game3.TYPE_WATER = 11
Game3.TYPE_GRASS = 12
Game3.TYPE_ELECTRIC = 13
Game3.TYPE_ICE = 15
Game3.TYPE_DRAGON = 16
Game3.TYPE_DARK = 17
Game3.STATUS_PSN = "psn"
Game3.STATUS_BRN = "brn"
Game3.STATUS_PAR = "par"
Game3.STATUS_SLP = "slp"
Game3.STATUS_FRZ = "frz"
Game3.EFFECT_SLEEP = 1
Game3.EFFECT_POISON_HIT = 2
Game3.EFFECT_ABSORB = 3
Game3.EFFECT_BURN_HIT = 4
Game3.EFFECT_FREEZE_HIT = 5
Game3.EFFECT_PARALYZE_HIT = 6
Game3.EFFECT_ATTACK_UP = 10
Game3.EFFECT_DEFENSE_UP = 11
Game3.EFFECT_SPEED_UP = 12
Game3.EFFECT_SPATK_UP = 13
Game3.EFFECT_SPDEF_UP = 14
Game3.EFFECT_EVASION_UP = 16
Game3.EFFECT_ALWAYS_HIT = 17
Game3.EFFECT_ATTACK_DOWN = 18
Game3.EFFECT_DEFENSE_DOWN = 19
Game3.EFFECT_SPEED_DOWN = 20
Game3.EFFECT_ACCURACY_DOWN = 23
Game3.EFFECT_EVASION_DOWN = 24
Game3.EFFECT_BIDE = 26
Game3.EFFECT_MULTI_HIT = 29
Game3.EFFECT_FLINCH_HIT = 31
Game3.EFFECT_RESTORE_HP = 32
Game3.EFFECT_TOXIC = 33
Game3.EFFECT_REST = 37
Game3.EFFECT_OHKO = 38
Game3.EFFECT_RAZOR_WIND = 39
Game3.EFFECT_HIGH_CRITICAL = 43
Game3.EFFECT_DOUBLE_HIT = 44
Game3.EFFECT_VITAL_THROW = 78
Game3.EFFECT_FOCUS_ENERGY = 47
Game3.EFFECT_RECOIL = 48
Game3.EFFECT_LEVEL_DAMAGE = 87
Game3.EFFECT_CONFUSE = 49
Game3.EFFECT_ATTACK_UP_2 = 50
Game3.EFFECT_DEFENSE_UP_2 = 51
Game3.EFFECT_SPEED_UP_2 = 52
Game3.EFFECT_SPATK_UP_2 = 53
Game3.EFFECT_SPDEF_UP_2 = 54
Game3.EFFECT_ATTACK_DOWN_2 = 58
Game3.EFFECT_DEFENSE_DOWN_2 = 59
Game3.EFFECT_SPEED_DOWN_2 = 60
Game3.EFFECT_SPECIAL_ATTACK_DOWN_2 = 61
Game3.EFFECT_SPECIAL_DEFENSE_DOWN_2 = 62
Game3.EFFECT_ACCURACY_DOWN_2 = 63
Game3.EFFECT_EVASION_DOWN_2 = 64
Game3.EFFECT_POISON = 66
Game3.EFFECT_PARALYZE = 67
Game3.EFFECT_ATTACK_DOWN_HIT = 68
Game3.EFFECT_DEFENSE_DOWN_HIT = 69
Game3.EFFECT_SPEED_DOWN_HIT = 70
Game3.EFFECT_SPECIAL_ATTACK_DOWN_HIT = 71
Game3.EFFECT_SPECIAL_DEFENSE_DOWN_HIT = 72
Game3.EFFECT_ACCURACY_DOWN_HIT = 73
Game3.EFFECT_SKY_ATTACK = 75
Game3.EFFECT_CONFUSE_HIT = 76
Game3.EFFECT_SPLASH = 85
Game3.EFFECT_LEECH_SEED = 84
Game3.EFFECT_PROTECT = 111
Game3.EFFECT_FORESIGHT = 113
Game3.EFFECT_HIDDEN_POWER = 135
Game3.EFFECT_ENDURE = 116
Game3.EFFECT_NATURE_POWER = 173
Game3.EFFECT_SKULL_BASH = 145
Game3.EFFECT_FLINCH_MINIMIZE_HIT = 150
Game3.EFFECT_SOLARBEAM = 151
Game3.EFFECT_THUNDER = 152
Game3.EFFECT_GUST = 149
Game3.EFFECT_TWISTER = 146
Game3.EFFECT_EARTHQUAKE = 147
Game3.EFFECT_MAGNITUDE = 126
Game3.EFFECT_FLY = 155
Game3.EFFECT_DEFENSE_CURL = 156
Game3.EFFECT_WILL_O_WISP = 167
Game3.EFFECT_KNOCK_OFF = 188
Game3.EFFECT_TELEPORT = 153
Game3.EFFECT_LOW_KICK = 196
Game3.EFFECT_MUD_SPORT = 201
Game3.EFFECT_WATER_SPORT = 210
Game3.EFFECT_RAGE = 81
Game3.MOVE_RAGE = 99
-- pokeruby sWeightToDamageTable: first threshold greater than weight (hg).
Game3.LOW_KICK_WEIGHTS = { 100, 20, 250, 40, 500, 60, 1000, 80, 2000, 100 }
-- gPokedexEntries[].weight via SpeciesToNationalPokedexNum (tenths of kg).
Game3.DEX_WEIGHT = {
  [0]=0, 69, 130, 1000, 85, 190, 905, 90, 225, 855, 29, 99, 320, 32, 100, 295, 18,
  300, 395, 35, 185, 20, 380, 69, 650, 60, 300, 120, 295, 70, 200, 600, 90,
  195, 620, 75, 400, 99, 199, 55, 120, 75, 550, 54, 86, 186, 54, 295, 300,
  125, 8, 333, 42, 320, 196, 766, 280, 320, 190, 1550, 124, 200, 540, 195, 565,
  480, 195, 705, 1300, 40, 64, 155, 455, 550, 200, 1050, 3000, 300, 950, 360, 785,
  60, 600, 150, 392, 852, 900, 1200, 300, 300, 40, 1325, 1, 1, 405, 2100, 324,
  756, 65, 600, 104, 666, 25, 1200, 65, 450, 498, 502, 655, 10, 95, 1150, 1200,
  346, 350, 800, 80, 250, 150, 390, 345, 800, 545, 560, 406, 300, 445, 550, 884,
  100, 2350, 2200, 40, 65, 290, 245, 250, 365, 75, 350, 115, 405, 590, 4600, 554,
  526, 600, 33, 165, 2100, 1220, 40, 64, 158, 1005, 79, 190, 795, 95, 250, 888,
  60, 325, 212, 408, 108, 356, 85, 335, 750, 120, 225, 20, 30, 10, 15, 32,
  20, 150, 78, 133, 615, 58, 85, 285, 380, 339, 5, 10, 30, 115, 18, 85,
  380, 85, 750, 265, 270, 21, 795, 10, 50, 285, 415, 72, 1258, 140, 648, 4000,
  78, 487, 39, 1180, 205, 540, 280, 88, 1258, 350, 550, 65, 558, 50, 120, 285,
  160, 2200, 505, 108, 350, 1520, 335, 1200, 325, 712, 580, 210, 480, 60, 235, 214,
  755, 468, 1780, 1980, 1870, 720, 1520, 2020, 2160, 1990, 50, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 50, 216, 522, 25, 195, 520, 76, 280, 819, 136, 370, 175,
  325, 36, 100, 284, 115, 316, 26, 325, 550, 40, 280, 596, 55, 120, 12, 23,
  198, 45, 392, 50, 95, 280, 17, 36, 1300, 3980, 110, 326, 220, 215, 1080, 970,
  804, 110, 19, 236, 87, 115, 328, 74, 1620, 208, 888, 150, 153, 820, 864, 2538,
  152, 402, 240, 2200, 395, 876, 1506, 513, 774, 168, 2565, 1680, 1540, 20, 306, 715,
  42, 42, 115, 112, 315, 12, 206, 140, 150, 306, 20, 240, 465, 1305, 103, 800,
  1000, 163, 405, 840, 525, 270, 226, 470, 23, 125, 525, 403, 234, 600, 1200, 3600,
  8, 177, 177, 238, 604, 125, 682, 66, 202, 484, 421, 1105, 1026, 952, 2025, 5500,
  2300, 1750, 2050, 3520, 9500, 2065, 400, 600, 11, 608, 10,
}
Game3.EFFECT_DOUBLE_EDGE = 198
Game3.EFFECT_SANDSTORM = 115
Game3.EFFECT_RAIN_DANCE = 136
Game3.EFFECT_SUNNY_DAY = 137
Game3.EFFECT_DEFENSE_UP_HIT = 138
Game3.EFFECT_ATTACK_UP_HIT = 139
Game3.EFFECT_HAIL = 164
Game3.EFFECT_COSMIC_POWER = 206
Game3.EFFECT_SKY_UPPERCUT = 207
Game3.EFFECT_BULK_UP = 208
Game3.EFFECT_CALM_MIND = 211
Game3.EFFECT_DRAGON_DANCE = 212
Game3.EFFECT_BLAZE_KICK = 200
Game3.EFFECT_POISON_TAIL = 209
Game3.TARGET_SELECTED = 0
Game3.TARGET_BOTH = 8
Game3.TARGET_USER = 16
Game3.TARGET_FOES_AND_ALLY = 32
Game3.WEATHER_RAIN = "rain"
Game3.WEATHER_SUN = "sun"
Game3.WEATHER_SAND = "sand"
Game3.WEATHER_HAIL = "hail"
Game3.WEATHER_TURNS = 5
Game3.CONFUSION_POWER = 40
Game3.FLAG_CONTACT = 1
Game3.FLAG_PROTECT = 2
Game3.ABILITY_LIMBER = 7
Game3.ABILITY_DRIZZLE = 2
Game3.ABILITY_SAND_VEIL = 8
Game3.ABILITY_STATIC = 9
Game3.ABILITY_VOLT_ABSORB = 10
Game3.ABILITY_WATER_ABSORB = 11
Game3.ABILITY_COMPOUND_EYES = 14
Game3.ABILITY_CLOUD_NINE = 13
Game3.ABILITY_INSOMNIA = 15
Game3.ABILITY_IMMUNITY = 17
Game3.ABILITY_FLASH_FIRE = 18
Game3.ABILITY_SHIELD_DUST = 19
Game3.ABILITY_OWN_TEMPO = 20
Game3.ABILITY_INTIMIDATE = 22
Game3.ABILITY_SHADOW_TAG = 23
Game3.ABILITY_ROUGH_SKIN = 24
Game3.ABILITY_WONDER_GUARD = 25
Game3.ABILITY_LEVITATE = 26
Game3.ABILITY_SYNCHRONIZE = 28
Game3.ABILITY_CLEAR_BODY = 29
Game3.ABILITY_NATURAL_CURE = 30
Game3.ABILITY_LIGHTNING_ROD = 31
Game3.ABILITY_SERENE_GRACE = 32
Game3.ABILITY_SWIFT_SWIM = 33
Game3.ABILITY_CHLOROPHYLL = 34
Game3.ABILITY_TRACE = 36
Game3.ABILITY_HUGE_POWER = 37
Game3.ABILITY_POISON_POINT = 38
Game3.ABILITY_INNER_FOCUS = 39
Game3.ABILITY_MAGMA_ARMOR = 40
Game3.ABILITY_WATER_VEIL = 41
Game3.ABILITY_MAGNET_PULL = 42
Game3.ABILITY_THICK_FAT = 47
Game3.ABILITY_RAIN_DISH = 44
Game3.ABILITY_SAND_STREAM = 45
Game3.ABILITY_EARLY_BIRD = 48
Game3.ABILITY_FLAME_BODY = 49
Game3.ABILITY_RUN_AWAY = 50
Game3.ABILITY_KEEN_EYE = 51
Game3.ABILITY_HYPER_CUTTER = 52
Game3.ABILITY_PICKUP = 53
Game3.ABILITY_TRUANT = 54
Game3.ABILITY_STICKY_HOLD = 60
Game3.ABILITY_SHED_SKIN = 61
Game3.ABILITY_GUTS = 62
Game3.ABILITY_MARVEL_SCALE = 63
Game3.ABILITY_LIQUID_OOZE = 64
Game3.ABILITY_OVERGROW = 65
Game3.ABILITY_BLAZE = 66
Game3.ABILITY_TORRENT = 67
Game3.ABILITY_SWARM = 68
Game3.ABILITY_ROCK_HEAD = 69
Game3.ABILITY_DROUGHT = 70
Game3.ABILITY_ARENA_TRAP = 71
Game3.ABILITY_VITAL_SPIRIT = 72
Game3.ABILITY_WHITE_SMOKE = 73
Game3.ABILITY_PURE_POWER = 74
Game3.ABILITY_AIR_LOCK = 76
Game3.PARTY_MAX = 6
Game3.BOX_COUNT = 14
Game3.BOX_SIZE = 30
Game3.START_BALLS = 5
Game3.START_MONEY = 3000
Game3.SAVE_FORMAT = "gen3-ruby-1"
Game3.SAVE_FILE = "save3_ruby.lua"
Game3.ITEM_MASTER_BALL = 1
Game3.ITEM_ULTRA_BALL = 2
Game3.ITEM_GREAT_BALL = 3
Game3.ITEM_POKE_BALL = 4
Game3.ITEM_SAFARI_BALL = 5
Game3.ITEM_NET_BALL = 6
Game3.ITEM_DIVE_BALL = 7
Game3.ITEM_NEST_BALL = 8
Game3.ITEM_REPEAT_BALL = 9
Game3.ITEM_TIMER_BALL = 10
Game3.ITEM_LUXURY_BALL = 11
Game3.ITEM_PREMIER_BALL = 12
Game3.ITEM_POTION = 13
Game3.ITEM_ANTIDOTE = 14
Game3.ITEM_BURN_HEAL = 15
Game3.ITEM_ICE_HEAL = 16
Game3.ITEM_AWAKENING = 17
Game3.ITEM_PARALYZE_HEAL = 18
Game3.ITEM_FULL_RESTORE = 19
Game3.ITEM_MAX_POTION = 20
Game3.ITEM_HYPER_POTION = 21
Game3.ITEM_SUPER_POTION = 22
Game3.ITEM_FULL_HEAL = 23
Game3.ITEM_REVIVE = 24
Game3.ITEM_FRESH_WATER = 26
Game3.ITEM_SODA_POP = 27
Game3.ITEM_LEMONADE = 28
Game3.ITEM_MOOMOO_MILK = 29
Game3.ITEM_PROTEIN = 64
Game3.ITEM_SUPER_REPEL = 83
Game3.ITEM_MAX_REPEL = 84
Game3.ITEM_ESCAPE_ROPE = 85
Game3.ITEM_REPEL = 86
Game3.REPEL_STEPS = {
  [83] = 200,
  [84] = 250,
  [86] = 100,
}
Game3.ITEM_RARE_CANDY = 68
Game3.ITEM_PP_UP = 69
Game3.ITEM_NUGGET = 110
Game3.ITEM_KINGS_ROCK = 187
Game3.ITEM_MACH_BIKE = 259
Game3.ITEM_ITEMFINDER = 261
Game3.ITEM_OLD_ROD = 262
Game3.ITEM_GOOD_ROD = 263
Game3.ITEM_SUPER_ROD = 264
Game3.OLD_ROD = 0
Game3.GOOD_ROD = 1
Game3.SUPER_ROD = 2
-- pokeruby Task_Fishing / sFishingStateFuncs (field_player_avatar.c).
Game3.FISH_WAIT = 2
Game3.FISH_START_ROUND = 3
Game3.FISH_DOTS = 4
Game3.FISH_NO_BITE = 11
Game3.FISH_GOT_AWAY = 12
Game3.FISH_SHOW_RESULT = 13
Game3.FISH_MIN_BASE = { [0] = 1, [1] = 1, [2] = 1 }
Game3.FISH_MIN_SPAN = { [0] = 1, [1] = 3, [2] = 6 }
Game3.FISH_REEL = { [0] = 36, [1] = 33, [2] = 30 }
Game3.FISH_EXTRA = {
  [0] = { [0] = 0, [1] = 0 },
  [1] = { [0] = 40, [1] = 10 },
  [2] = { [0] = 70, [1] = 30 },
}
Game3.FISH_DOT = "·"
Game3.FISH_TEXT_BITE = "Oh! A bite!"
Game3.FISH_TEXT_HOOK = "A POKéMON's on the hook!"
Game3.FISH_TEXT_NIBBLE = "Not even a nibble..."
Game3.FISH_TEXT_AWAY = "It got away..."
Game3.ITEM_WAILMER_PAIL = 268
Game3.ITEM_DEVON_GOODS = 269
Game3.ITEM_SOOT_SACK = 270
Game3.ITEM_ACRO_BIKE = 272
Game3.ITEM_LETTER = 274
Game3.ITEM_HM_CUT = 339
Game3.ITEM_HM_FLY = 340
Game3.ITEM_HM_SURF = 341
Game3.ITEM_HM_STRENGTH = 342
Game3.ITEM_HM_FLASH = 343
Game3.ITEM_HM_ROCK_SMASH = 344
Game3.ITEM_HM_WATERFALL = 345
Game3.ITEM_HM_DIVE = 346
Game3.MOVE_CUT = 15
Game3.MOVE_FLY = 19
Game3.MOVE_SURF = 57
Game3.MOVE_STRENGTH = 70
Game3.MOVE_DIG = 91
Game3.MOVE_TELEPORT = 100
Game3.MOVE_WATERFALL = 127
Game3.MOVE_FLASH = 148
Game3.MOVE_SWEET_SCENT = 230
Game3.MOVE_ROCK_SMASH = 249
Game3.MOVE_SECRET_POWER = 290
Game3.MOVE_DIVE = 291
-- pokeruby gHMMoves[] / IsHMMove2.
Game3.HM_MOVES = {
  [Game3.MOVE_CUT] = true,
  [Game3.MOVE_FLY] = true,
  [Game3.MOVE_SURF] = true,
  [Game3.MOVE_STRENGTH] = true,
  [Game3.MOVE_FLASH] = true,
  [Game3.MOVE_ROCK_SMASH] = true,
  [Game3.MOVE_WATERFALL] = true,
  [Game3.MOVE_DIVE] = true,
}
Game3.ITEM_TM43 = 331
Game3.ITEM_TM01 = 289
Game3.ITEM_TM39 = 327
Game3.TMHM_MOVES = require("src.import.RomExtractorGen3Battle").TMHM_MOVES
Game3.ITEM_CHERI_BERRY = 133
Game3.ITEM_CHESTO_BERRY = 134
Game3.ITEM_PECHA_BERRY = 135
Game3.ITEM_RAWST_BERRY = 136
Game3.ITEM_ASPEAR_BERRY = 137
Game3.ITEM_ORAN_BERRY = 139
Game3.ITEM_LUM_BERRY = 141
Game3.ITEM_SITRUS_BERRY = 142
Game3.ITEM_ENIGMA_BERRY = 175
Game3.ITEM_MIRACLE_SEED = 205
Game3.ITEM_SOOTHE_BELL = 184
Game3.HOLD_EFFECT_HAPPINESS_UP = 27
Game3.ITEM_QUICK_CLAW = 183
Game3.HOLD_EFFECT_QUICK_CLAW = 26
Game3.QUICK_CLAW_PARAM = 20
Game3.QUICK_CLAW_SPEED = 0xFFFFFFFF
Game3.ITEM_MACHO_BRACE = 181
Game3.HOLD_EFFECT_MACHO_BRACE = 24
Game3.ITEM_EXP_SHARE = 182
Game3.HOLD_EFFECT_EXP_SHARE = 25
Game3.ITEM_SMOKE_BALL = 194
Game3.HOLD_EFFECT_CAN_ALWAYS_RUN = 37
-- pokeruby gHoldEffectToType: HOLD_EFFECT_*_POWER -> move type.
Game3.HOLD_EFFECT_BUG_POWER = 31
Game3.HOLD_EFFECT_STEEL_POWER = 42
Game3.HOLD_EFFECT_GROUND_POWER = 46
Game3.HOLD_EFFECT_ROCK_POWER = 47
Game3.HOLD_EFFECT_GRASS_POWER = 48
Game3.HOLD_EFFECT_DARK_POWER = 49
Game3.HOLD_EFFECT_FIGHTING_POWER = 50
Game3.HOLD_EFFECT_ELECTRIC_POWER = 51
Game3.HOLD_EFFECT_WATER_POWER = 52
Game3.HOLD_EFFECT_FLYING_POWER = 53
Game3.HOLD_EFFECT_POISON_POWER = 54
Game3.HOLD_EFFECT_ICE_POWER = 55
Game3.HOLD_EFFECT_GHOST_POWER = 56
Game3.HOLD_EFFECT_PSYCHIC_POWER = 57
Game3.HOLD_EFFECT_FIRE_POWER = 58
Game3.HOLD_EFFECT_DRAGON_POWER = 59
Game3.HOLD_EFFECT_NORMAL_POWER = 60
Game3.HOLD_EFFECT_TYPE = {
  [31] = 6, [42] = 8, [46] = 4, [47] = 5, [48] = 12, [49] = 17,
  [50] = 1, [51] = 13, [52] = 11, [53] = 2, [54] = 3, [55] = 15,
  [56] = 7, [57] = 14, [58] = 10, [59] = 16, [60] = 0,
}
-- Fallback when items.lua predates holdEffect (no cache bump).
Game3.TYPE_POWER_ITEM = {
  [188] = 31, [199] = 42, [203] = 46, [204] = 47, [205] = 48,
  [206] = 49, [207] = 50, [208] = 51, [209] = 52, [210] = 53,
  [211] = 54, [212] = 55, [213] = 56, [214] = 57, [215] = 58,
  [216] = 59, [217] = 60,
}
Game3.BERRY_REGROW_LIMIT = 10
Game3.BERRY_STAGE_NO_BERRY = 0
Game3.BERRY_STAGE_PLANTED = 1
Game3.BERRY_STAGE_SPROUTED = 2
Game3.BERRY_STAGE_TALLER = 3
Game3.BERRY_STAGE_FLOWERING = 4
Game3.BERRY_STAGE_BERRIES = 5
Game3.BERRY_STAGE_SPARKLING = 255
-- pokeruby gBerries[].name; index is ITEM_TO_BERRY (Cheri = 1).
Game3.BERRY_NAMES = {
  "CHERI", "CHESTO", "PECHA", "RAWST", "ASPEAR", "LEPPA", "ORAN", "PERSIM",
  "LUM", "SITRUS", "FIGY", "WIKI", "MAGO", "AGUAV", "IAPAPA", "RAZZ",
  "BLUK", "NANAB", "WEPEAR", "PINAP", "POMEG", "KELPSY", "QUALOT", "HONDEW",
  "GREPA", "TAMATO", "CORNN", "MAGOST", "RABUTA", "NOMEL", "SPELON", "PAMTRE",
  "WATMEL", "DURIN", "BELUE", "LIECHI", "GANLON", "SALAC", "PETAYA", "APICOT",
  "LANSAT", "STARF", "ENIGMA",
}
-- EventScript_ResetAllBerryTrees: treeId, berryType pairs, all stage 5.
Game3.NEW_GAME_BERRY_TREES = {
  2, 7, 1, 3, 11, 7, 13, 3, 4, 7, 76, 1, 8, 1, 10, 6,
  25, 20, 26, 2, 66, 2, 67, 20, 69, 22, 70, 22, 71, 22,
  55, 17, 56, 17, 5, 1, 6, 6, 7, 1,
  16, 18, 17, 18, 18, 18, 29, 19, 28, 19, 27, 19,
  24, 4, 23, 3, 22, 3, 21, 4, 19, 16, 20, 16,
  80, 7, 81, 7, 77, 8, 78, 8, 68, 8,
  31, 10, 33, 10, 34, 21, 35, 21, 36, 21,
  83, 24, 84, 24, 85, 10, 86, 6,
  37, 5, 38, 5, 39, 5, 40, 3, 41, 3, 42, 3,
  46, 19, 45, 20, 44, 18, 43, 16,
  47, 8, 48, 5, 49, 4, 50, 2, 52, 18, 53, 18,
  62, 6, 64, 6, 58, 21, 59, 21, 60, 25, 61, 25,
  79, 23, 14, 23, 15, 21, 30, 21, 65, 25, 72, 25,
  73, 23, 74, 23, 87, 3, 88, 10, 89, 4, 82, 36,
}
Game3.LAST_BALL = 12
-- pokeruby POCKET_ITEMS .. POCKET_KEY_ITEMS (pocket 0 is none).
Game3.POCKET_ITEMS = 1
Game3.POCKET_BALLS = 2
Game3.POCKET_TMHM = 3
Game3.POCKET_BERRIES = 4
Game3.POCKET_KEY = 5
Game3.POCKET_COUNT = 5
Game3.POCKET_NAMES = {
  "ITEMS", "POKe BALLS", "TMs & HMs", "BERRIES", "KEY ITEMS",
}
-- pokeruby gMultichoiceLists / strings.c. B cancel is MULTI_B_PRESSED 127.
Game3.MULTI_B_PRESSED = 127
Game3.MULTICHOICE = {
  [0] = { "PETALBURG", "SLATEPORT", "CANCEL" },
  [12] = { "MACH", "ACRO" },
  [13] = { "PSN", "PAR", "SLP", "BRN", "FRZ", "CANCEL" },
  [14] = { "DEWFORD", "CANCEL" },
  [50] = { "Excellent!", "Not so hot" },
}
Game3.PARTY_SUMMARY_PAGES = 3
Game3.PARTY_FIELD_MOVES = {
  { id = Game3.MOVE_CUT, name = "CUT" },
  { id = Game3.MOVE_FLASH, name = "FLASH" },
  { id = Game3.MOVE_ROCK_SMASH, name = "ROCK SMASH" },
  { id = Game3.MOVE_STRENGTH, name = "STRENGTH" },
  { id = Game3.MOVE_SURF, name = "SURF" },
  { id = Game3.MOVE_FLY, name = "FLY" },
  { id = Game3.MOVE_DIVE, name = "DIVE" },
  { id = Game3.MOVE_WATERFALL, name = "WATERFALL" },
  { id = Game3.MOVE_TELEPORT, name = "TELEPORT" },
  { id = Game3.MOVE_DIG, name = "DIG" },
  { id = Game3.MOVE_SECRET_POWER, name = "SECRET POWER" },
  { id = Game3.MOVE_SWEET_SCENT, name = "SWEET SCENT" },
}
Game3.TYPE_NAMES = {
  [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK",
  "BUG", "GHOST", "STEEL", "???", "FIRE", "WATER", "GRASS",
  "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK",
}
Game3.POKE_BALL_BONUS = 1
Game3.GROWTH_MEDIUM_FAST = 0
Game3.GROWTH_ERRATIC = 1
Game3.GROWTH_FLUCTUATING = 2
Game3.GROWTH_MEDIUM_SLOW = 3
Game3.GROWTH_FAST = 4
Game3.GROWTH_SLOW = 5
Game3.GFX_NURSE = 58
Game3.GFX_BERRY_TREE = 60
Game3.GFX_BERRY_TREE_EARLY = 61
Game3.GFX_BERRY_TREE_LATE = 62
Game3.GFX_MOM = 215
Game3.GFX_ITEM_BALL = 59
Game3.GFX_BIRCH = 64
Game3.GFX_CUTTABLE_TREE = 82
Game3.GFX_MART = 83
Game3.GFX_MART_EMPLOYEE = 83
Game3.GFX_BREAKABLE_ROCK = 86
Game3.GFX_PUSHABLE_BOULDER = 87
Game3.GFX_BRINEY_BOAT = 88
Game3.GFX_TRUCK = 94
Game3.GFX_BRENDAN = 0
Game3.GFX_BRENDAN_MACH_BIKE = 1
Game3.GFX_BRENDAN_SURFING = 2
Game3.GFX_BRENDAN_ACRO_BIKE = 63
Game3.GFX_MAY = 89
Game3.GFX_MAY_MACH_BIKE = 90
Game3.GFX_MAY_ACRO_BIKE = 91
Game3.GFX_MAY_SURFING = 92
Game3.GFX_BIRCHS_BAG = 97
Game3.GFX_RIVAL_BRENDAN = 100
Game3.GFX_RIVAL_MAY = 105
Game3.GFX_BRENDAN_UNDERWATER = 111
Game3.GFX_MAY_UNDERWATER = 112
Game3.GFX_OLD_MAN_2 = 29
Game3.GFX_OLD_WOMAN_2 = 30
Game3.GFX_DAYCARE_MAN = 29
Game3.GFX_DAYCARE_LADY = 30
Game3.GFX_TEALA = 85
Game3.GFX_CONTEST_RECEPTIONIST = 85
Game3.GFX_AQUA_MEMBER_M = 117
Game3.GFX_AQUA_MEMBER_F = 118
Game3.GFX_MAGMA_MEMBER_M = 119
Game3.GFX_MAGMA_MEMBER_F = 120
Game3.GFX_ARCHIE = 195
Game3.GFX_MAXIE = 196
Game3.GFX_VAR_0 = 240
Game3.GFX_VAR_1 = 241
Game3.GFX_VAR_F = 255
Game3.VAR_OBJ_GFX_ID_0 = 0x4010
Game3.VARS_START = 0x4000
Game3.SPECIAL_VARS_START = 0x8000
Game3.MAP_OFFSET = 7
Game3.MAPGRID_COLLISION_MASK = 0x0C00
Game3.TRAINER_BATTLE_CONTINUE_NO_MUSIC = 1
Game3.TRAINER_BATTLE_CONTINUE = 2
Game3.TRAINER_BATTLE_NO_INTRO = 3
Game3.TRAINER_BATTLE_DOUBLE = 4
Game3.TRAINER_BATTLE_REMATCH = 5
Game3.TRAINER_BATTLE_CONTINUE_DOUBLE = 6
Game3.TRAINER_BATTLE_REMATCH_DOUBLE = 7
Game3.TRAINER_BATTLE_CONTINUE_DOUBLE_NO_MUSIC = 8
Game3.PLAYER_HAS_TWO_USABLE_MONS = 0
Game3.PLAYER_HAS_ONE_MON = 1
Game3.PLAYER_HAS_ONE_USABLE_MON = 2
Game3.TRAINER_ROXANNE = 265
Game3.TRAINER_PETALBURG_WOODS_GRUNT = 575
Game3.GENDER_MALE = 0
Game3.GENDER_FEMALE = 1
Game3.SPECIES_POOCHYENA = 286
Game3.SPECIES_TREECKO = 277
Game3.SPECIES_TORCHIC = 280
Game3.SPECIES_MUDKIP = 283
Game3.SPECIES_MACHOP = 66
Game3.SPECIES_ZIGZAGOON = 288
Game3.SPECIES_RALTS = 392
Game3.MOVE_TACKLE = 33
Game3.MOVE_STUN_SPORE = 78
Game3.MOVE_RAZOR_LEAF = 75
Game3.MOVE_EARTHQUAKE = 89
Game3.MOVE_HYDRO_PUMP = 56
Game3.MOVE_SURF = 57
Game3.MOVE_BUBBLE_BEAM = 61
Game3.MOVE_ROCK_SLIDE = 157
Game3.MOVE_SHADOW_BALL = 247
Game3.MOVE_SWIFT = 129
Game3.BATTLE_ENV_GRASS = 0
Game3.BATTLE_ENV_LONG_GRASS = 1
Game3.BATTLE_ENV_SAND = 2
Game3.BATTLE_ENV_UNDERWATER = 3
Game3.BATTLE_ENV_WATER = 4
Game3.BATTLE_ENV_POND = 5
Game3.BATTLE_ENV_MOUNTAIN = 6
Game3.BATTLE_ENV_CAVE = 7
Game3.BATTLE_ENV_BUILDING = 8
Game3.BATTLE_ENV_PLAIN = 9
-- pokeruby gUnknown_0837F578: affine 64x64, x/y is the centre.
-- Row 0 is singles (GetBattlerPosition 0..3); row 1 is doubles.
Game3.BATTLER_CX = { player = 72, enemy = 176, player2 = 48, enemy2 = 112 }
Game3.BATTLER_CY = { player = 80, enemy = 40, player2 = 40, enemy2 = 80 }
Game3.BATTLER_CX_DOUBLES = { player = 32, enemy = 200, player2 = 90, enemy2 = 152 }
Game3.BATTLER_CY_DOUBLES = { player = 80, enemy = 40, player2 = 88, enemy2 = 32 }
Game3.HEALTHBOX_XY = { player = { 118, 74 }, enemy = { 8, 8 } }
Game3.HEALTHBOX_XY_DOUBLES = {
  player = { 118, 90 }, player2 = { 118, 54 },
  enemy = { 8, 8 }, enemy2 = { 8, 36 },
}
-- pokeruby sNaturePowerMoves, indexed by gBattleEnvironment.
Game3.NATURE_POWER_MOVES = {
  [0] = 78,
  [1] = 75,
  [2] = 89,
  [3] = 56,
  [4] = 57,
  [5] = 61,
  [6] = 157,
  [7] = 247,
  [8] = 129,
  [9] = 129,
}
Game3.WALLY_TUTORIAL_ZIGZAGOON_LEVEL = 7
Game3.WALLY_TUTORIAL_RALTS_LEVEL = 5
Game3.STARTERS = { 277, 280, 283 }
Game3.STARTER_LEVEL = 5
Game3.NICKNAME_LEN = 10
Game3.NICKNAME_COLS = 9
Game3.NAME_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
Game3.CHASE_LEVEL = 2
Game3.LAB_GROUP = 1
Game3.LAB_NUM = 4
Game3.LAB_X = 6
Game3.LAB_Y = 5
Game3.ROUTE101_CHOOSE_X = 6
Game3.ROUTE101_CHOOSE_Y = 13
Game3.FADE_TO_BLACK = 1
Game3.FADE_FROM_BLACK = 0
Game3.FADE_FRAMES = 16
Game3.FLAG_RESCUED_BIRCH = 0x52
Game3.FLAG_SET_WALL_CLOCK = 0x51
Game3.FLAG_HIDE_MOM_LITTLEROOT = 0x2F0
Game3.FLAG_HIDE_MACHOKE_MOVER_1 = 0x2F2
Game3.FLAG_HIDE_MACHOKE_MOVER_2 = 0x2F3
Game3.FLAG_HIDE_MOM_UPSTAIRS = 0x2F5
Game3.FLAG_HIDE_BIRCH_STARTERS_BAG = 0x2BC
Game3.FLAG_HIDE_BIRCH_BATTLE_POOCHYENA = 0x2D0
Game3.FLAG_HIDE_POOCHYENA_ROUTE101 = 0x2EE
Game3.FLAG_HIDE_BIRCH_IN_LAB = 0x2D1
Game3.FLAG_HIDE_MAY_UPSTAIRS = 0x2D2
Game3.FLAG_HIDE_RIVAL_ROUTE103 = 0x2D3
Game3.FLAG_DEFEATED_RIVAL_ROUTE103 = 0x82
Game3.FLAG_HIDE_BRENDAN_MOM_DOWNSTAIRS = 0x2F6
Game3.FLAG_HIDE_MAY_MOM_DOWNSTAIRS = 0x2F7
Game3.FLAG_HIDE_BRENDAN_UPSTAIRS = 0x2F8
Game3.FLAG_HIDE_MOVING_TRUCK_BRENDAN = 0x2F9
Game3.FLAG_HIDE_MOVING_TRUCK_MAY = 0x2FA
Game3.FLAG_HIDE_BRENDAN_MOM = 0x310
Game3.FLAG_HIDE_MAY_MOM = 0x311
Game3.FLAG_HIDE_RIVAL_BIRCH_LAB = 0x379
Game3.FLAG_HIDE_BIRCH_ROUTE101 = 0x381
Game3.FLAG_HIDE_BOY_ROUTE101 = 0x3DF
Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN = 0x3D3
Game3.FLAG_HIDE_WALLY_PETALBURG = 0x2D6
Game3.FLAG_HIDE_WALLY_MOM_PETALBURG_1 = 0x2D8
Game3.FLAG_HIDE_WALLY_FATHER_PETALBURG = 0x32B
Game3.FLAG_HIDE_WALLY_MOTHER_PETALBURG = 0x32C
Game3.FLAG_HIDE_WALLY_PETALBURG_GYM = 0x362
Game3.FLAG_HIDE_NORMAN_PETALBURG_GYM = 0x304
Game3.FLAG_HIDE_PETALBURG_GYM_GUIDE = 0x30D
Game3.FLAG_DONT_TRANSITION_MUSIC = 0x4001
Game3.FLAG_MET_RIVAL_MOM = 0x57
Game3.FLAG_BIRCH_AIDE_MET = 0x58
Game3.FLAG_ADVENTURE_STARTED = 0x74
Game3.FLAG_RECEIVED_POTION_OLDALE = 0x84
Game3.FLAG_RECEIVED_RUNNING_SHOES = 0x112
Game3.FLAG_TEMP_1 = 0x1
Game3.FLAG_MET_RIVAL_LILYCOVE = 0x124
Game3.FLAG_RIVAL_LEFT_FOR_ROUTE103 = 0x12D
Game3.VAR_STARTER_MON = 0x4023
Game3.VAR_LITTLEROOT_STATE = 0x4050
Game3.VAR_ROUTE102_ACCESSIBLE = 0x4051
Game3.VAR_PETALBURG_STATE = 0x4057
Game3.VAR_PETALBURG_WOODS_STATE = 0x4098
Game3.FLAG_HIDE_DEVON_PETALBURG_WOODS = 0x2D4
Game3.FLAG_HIDE_EVIL_TEAM_PETALBURG_WOODS = 0x2D5
Game3.FLAG_HIDE_GRUNT_RUSTBORO = 0x2DB
Game3.FLAG_HIDE_DEVON_RUSTBORO = 0x2DC
Game3.VAR_RUSTBORO_STATE = 0x405A
Game3.VAR_ROUTE101_STATE = 0x4060
Game3.VAR_ROUTE103_STATE = 0x4062
Game3.VAR_LITTLEROOT_HOUSES_STATE = 0x4082
Game3.VAR_BIRCH_LAB_STATE = 0x4084
Game3.VAR_PETALBURG_GYM_STATE = 0x4085
Game3.VAR_LITTLEROOT_HOUSES_STATE_2 = 0x408C
Game3.VAR_LITTLEROOT_RIVAL_STATE = 0x408D
Game3.VAR_BOARD_BRINEY_BOAT_ROUTE104_STATE = 0x408E
Game3.VAR_BRINEY_HOUSE_STATE = 0x4090
Game3.VAR_BRINEY_LOCATION = 0x4096
Game3.VAR_LITTLEROOT_INTRO_STATE = 0x4092
Game3.VAR_OLDALE_STATE = 0x40C7
Game3.VAR_TEMP_1 = 0x4001
Game3.VAR_FACING = 0x800C
Game3.VAR_LAST_TALKED = 0x800F
Game3.FLAG_HIDE_MAP_NAME_POPUP = 0x4000
Game3.WARP_ID_NONE = 0xFF
Game3.WARP_ID_DYNAMIC = 0x7F
Game3.MAP_UNDEFINED_GROUP = 0xFF
Game3.MAP_UNDEFINED_NUM = 0xFF
-- pokeruby gMapGroup_Dungeons: GraniteCave_B1F / B2F.
Game3.GRANITE_CAVE_GROUP = 24
Game3.GRANITE_CAVE_B1F_NUM = 8
Game3.GRANITE_CAVE_B2F_NUM = 9
Game3.HEAL_LITTLEROOT_BRENDAN_2F = 1
Game3.HEAL_LITTLEROOT_MAY_2F = 2
Game3.HEAL_BEDROOM_X = 4
Game3.HEAL_BEDROOM_Y = 2
Game3.TRUCK_TOWN_MALE_X = 3
Game3.TRUCK_TOWN_MALE_Y = 10
Game3.TRUCK_TOWN_FEMALE_X = 12
Game3.TRUCK_TOWN_FEMALE_Y = 10
Game3.TRAINER_BRENDAN_1 = 520
Game3.TRAINER_BRENDAN_4 = 523
Game3.TRAINER_BRENDAN_7 = 526
Game3.TRAINER_MAY_1 = 529
Game3.TRAINER_MAY_4 = 532
Game3.TRAINER_MAY_7 = 535
Game3.FLAG_SYS_POKEMON_GET = 0x800
Game3.FLAG_SYS_POKEDEX_GET = 0x801
Game3.FLAG_SYS_POKENAV_GET = 0x802
Game3.FLAG_SYS_CHAT_USED = 0x805
Game3.FLAG_SYS_POPWORD_INPUT = 0x833
Game3.FLAG_SYS_MIX_RECORD = 0x834
Game3.FLAG_BADGE01_GET = 0x807
Game3.FLAG_BADGE02_GET = 0x808
Game3.FLAG_BADGE03_GET = 0x809
Game3.FLAG_BADGE04_GET = 0x80A
Game3.FLAG_BADGE05_GET = 0x80B
Game3.FLAG_BADGE06_GET = 0x80C
Game3.FLAG_BADGE07_GET = 0x80D
Game3.FLAG_BADGE08_GET = 0x80E
Game3.BADGE_NAMES = {
  "STONE", "KNUCKLE", "DYNAMO", "HEAT",
  "BALANCE", "FEATHER", "MIND", "RAIN",
}
Game3.FLAG_VISITED_LITTLEROOT_TOWN = 0x80F
Game3.FLAG_VISITED_OLDALE_TOWN = 0x810
Game3.FLAG_VISITED_DEWFORD_TOWN = 0x811
Game3.FLAG_VISITED_LAVARIDGE_TOWN = 0x812
Game3.FLAG_VISITED_FALLARBOR_TOWN = 0x813
Game3.FLAG_VISITED_VERDANTURF_TOWN = 0x814
Game3.FLAG_VISITED_PACIFIDLOG_TOWN = 0x815
Game3.FLAG_VISITED_PETALBURG_CITY = 0x816
Game3.FLAG_VISITED_SLATEPORT_CITY = 0x817
Game3.FLAG_VISITED_MAUVILLE_CITY = 0x818
Game3.FLAG_VISITED_RUSTBORO_CITY = 0x819
Game3.FLAG_VISITED_FORTREE_CITY = 0x81A
Game3.FLAG_VISITED_LILYCOVE_CITY = 0x81B
Game3.FLAG_VISITED_MOSSDEEP_CITY = 0x81C
Game3.FLAG_VISITED_SOOTOPOLIS_CITY = 0x81D
Game3.FLAG_VISITED_EVER_GRANDE_CITY = 0x81E
Game3.FLAG_SYS_CYCLING_ROAD = 0x82B
Game3.FLAG_SYS_RIBBON_GET = 0x83B
Game3.FLAG_SYS_USE_FLASH = 0x828
Game3.MAX_FLASH_LEVEL = 4
-- field_screen_effect.c sFlashLevelPixelRadii (level 0 is unused: no mask).
Game3.FLASH_RADII = { [0] = 200, [1] = 72, [2] = 56, [3] = 40, [4] = 24 }
-- UpdateFlashLevelEffect: radius += delta every other frame, delta 1.
Game3.FLASH_ANIM_DELTA = 1
Game3.FLAG_SYS_USE_STRENGTH = 0x829
Game3.FLAG_SYS_TV_HOME = 0x830
Game3.FLAG_SYS_TV_WATCH = 0x831
Game3.FLAG_SYS_B_DASH = 0x860
Game3.FLAG_SYS_NATIONAL_DEX = 0x836
Game3.VAR_NATIONAL_DEX = 0x4046
Game3.VAR_SHROOMISH_SIZE_RECORD = 0x4047
Game3.VAR_ASH_GATHER_COUNT = 0x4048
Game3.VAR_BARBOACH_SIZE_RECORD = 0x404F
Game3.SIZE_RECORD_DEFAULT = 0x8100
Game3.NATIONAL_DEX_ENABLED = 0x302
Game3.HOENN_DEX_COUNT = 202
Game3.NATIONAL_DEX_COUNT = 386
Game3.HOENN_DEX_COMPLETE = 200
Game3.SPECIAL_HEAL_PARTY = 0
Game3.SPECIAL_CHECK_PLAYER_HAS_SECRET_BASE = 7
Game3.SPECIAL_MOVE_OUT_OF_SECRET_BASE = 10
Game3.SPECIAL_TURN_OFF_TV_SCREEN = 62
Game3.SPECIAL_GET_RIVAL_SON_DAUGHTER_STRING = 149
Game3.TEXT_SON = "son"
Game3.TEXT_DAUGHTER = "daughter"
Game3.SPECIAL_GET_PLAYER_BIG_GUY_GIRL_STRING = 148
Game3.TEXT_BIG_GUY = "Big guy"
Game3.TEXT_BIG_GIRL = "Big girl"
Game3.TEXT_NOT_ENOUGH_MONS = "You need two POKeMON to battle!"
Game3.TRAINER_GINA_AND_MIA_1 = 483
Game3.SPECIAL_GET_NUM_VALID_DAYCARE_PARTY_MONS = 132
Game3.SPECIAL_CHOOSE_STARTER = 156
Game3.SPECIAL_START_WALLY_TUTORIAL_BATTLE = 157
Game3.SPECIAL_CHANGE_POKEMON_NICKNAME = 158
Game3.SPECIAL_SELECT_MON_FOR_NPC_TRADE = 159
-- specials.inc: TV_PutNameRaterShowOnTheAirIfNicnkameChanged and friends.
Game3.SPECIAL_SWAP_REGISTERED_BIKE = 130
Game3.SPECIAL_GET_LEAD_MON_FRIENDSHIP = 230
Game3.SPECIAL_TV_NAME_RATER_SHOW = 123
Game3.SPECIAL_TV_COPY_NICKNAME = 124
Game3.SPECIAL_TV_CHECK_MON_OT_ID = 125
Game3.SPECIAL_GET_RECORDED_CYCLING_ROAD = 225
Game3.SPECIAL_BEGIN_CYCLING_ROAD = 226
Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE = 227
Game3.SPECIAL_FINISH_CYCLING_ROAD = 228
Game3.SPECIAL_UPDATE_CYCLING_ROAD_STATE = 229
Game3.SPECIAL_GET_PLAYER_FACING = 287
Game3.SPECIAL_LEAD_MON_HAS_EFFORT_RIBBON = 292
Game3.SPECIAL_GIVE_LEAD_MON_EFFORT_RIBBON = 293
Game3.SPECIAL_ARE_LEAD_MON_EVS_MAXED = 294
Game3.SPECIAL_SCRIPT_GET_PARTY_MON_SPECIES = 327
Game3.SPECIAL_IS_SELECTED_MON_EGG = 328
Game3.SPECIAL_MON_OT_NAME_MATCHES_PLAYER = 336
Game3.SPECIES_EGG = 412
Game3.SPECIAL_GET_IN_GAME_TRADE_SPECIES = 252
Game3.SPECIAL_CREATE_IN_GAME_TRADE = 253
Game3.SPECIAL_DO_IN_GAME_TRADE_SCENE = 254
Game3.SPECIAL_GET_TRADE_SPECIES = 255
Game3.PARTY_MENU_CANCEL = 255
Game3.SPECIES_SLAKOTH = 364
Game3.SPECIES_MAKUHITA = 335
Game3.ITEM_X_ATTACK = 75
-- pokeruby gIngameTrades (trade.c). Index is VAR_0x8004 / VAR_0x8008.
Game3.INGAME_TRADES = {
  [0] = {
    name = "MAKIT", species = 335, playerSpecies = 364,
    ivs = { hp = 5, atk = 5, def = 4, spe = 4, spa = 4, spd = 4 },
    secondAbility = true, otId = 49562, pid = 0x9C40, item = 75,
    otName = "ELYSSA", otGender = 0, sheen = 10,
    cool = 5, beauty = 5, cute = 5, smart = 5, tough = 30,
  },
  [1] = {
    name = "SKITIT", species = 315, playerSpecies = 25,
    ivs = { hp = 5, atk = 4, def = 4, spe = 5, spa = 4, spd = 4 },
    secondAbility = false, otId = 2259, pid = 0x498A2E17, item = 123,
    otName = "DARRELL", otGender = 1, sheen = 10,
    cool = 5, beauty = 5, cute = 30, smart = 5, tough = 5,
  },
  [2] = {
    name = "COROSO", species = 222, playerSpecies = 182,
    ivs = { hp = 4, atk = 4, def = 5, spe = 4, spa = 4, spd = 5 },
    secondAbility = true, otId = 50183, pid = 0x4C970B7F, item = 129,
    otName = "LANE", otGender = 1, sheen = 10,
    cool = 5, beauty = 30, cute = 5, smart = 5, tough = 5,
  },
}
Game3.SPECIAL_SAVE_PLAYER_PARTY = 39
Game3.SPECIAL_LOAD_PLAYER_PARTY = 40
Game3.SPECIAL_GET_BERRY_TREE_DATA = 43
Game3.SPECIAL_BERRY_BAG_MENU = 44
Game3.SPECIAL_PLANT_BERRY_TREE = 45
Game3.SPECIAL_PICK_BERRY_TREE = 46
Game3.SPECIAL_REMOVE_BERRY_TREE = 47
Game3.SPECIAL_WATER_BERRY_TREE = 48
Game3.SPECIAL_PLAYER_HAS_BERRIES = 49
Game3.VAR_ITEM_ID = 0x800E
Game3.SPECIAL_PUT_ZIGZAGOON = 301
Game3.SPECIAL_IS_STARTER_IN_PARTY = 302
Game3.SPECIAL_SHOULD_TRY_REMATCH = 57
Game3.SPECIAL_IS_TRAINER_READY_REMATCH = 58
Game3.SPECIAL_CALCULATE_PARTY_COUNT = 131
Game3.SPECIAL_SHOW_EASY_CHAT = 95
Game3.SPECIAL_BUFFER_TRENDY_PHRASE = 126
Game3.SPECIAL_IS_TRENDY_PHRASE_BORING = 127
Game3.SPECIAL_BUFFER_RANDOM_HOBBY = 128
Game3.SPECIAL_DEWFORD_HALL_PAINTING = 129
Game3.EC_TYPE_TRENDY_PHRASE = 9
Game3.EC_GROUP_CONDITIONS = 10
Game3.EC_GROUP_LIFESTYLE = 12
Game3.EC_GROUP_HOBBIES = 13
-- pokeruby easy_chat.h groups used by InitDewfordTrend.
Game3.EC_WORDS = {
  [10] = {
    "HOT", "EXISTS", "EXCESS", "APPROVED", "HAS", "GOOD", "LESS",
    "MOMENTUM", "GOING", "WEIRD", "BUSY", "TOGETHER", "FULL", "ABSENT",
    "BEING", "NEED", "TASTY", "SKILLED", "NOISY", "BIG", "LATE", "CLOSE",
    "DOCILE", "AMUSING", "ENTERTAINING", "PERFECTION", "PRETTY",
    "HEALTHY", "EXCELLENT", "UPSIDE DOWN", "COLD", "REFRESHING",
    "UNAVOIDABLE", "MUCH", "OVERWHELMING", "FABULOUS", "ELSE",
    "EXPENSIVE", "CORRECT", "IMPOSSIBLE", "SMALL", "DIFFERENT", "TIRED",
    "SKILL", "TOP", "NON STOP", "PREPOSTEROUS", "NONE", "NOTHING",
    "NATURAL", "BECOMES", "LUKEWARM", "FAST", "LOW", "AWFUL", "ALONE",
    "BORED", "SECRET", "MYSTERY", "LACKS", "BEST", "LOUSY", "MISTAKE",
    "KIND", "WELL", "WEAKENED", "SIMPLE", "SEEMS", "BADLY",
  },
  [12] = {
    "CHORES", "HOME", "MONEY", "ALLOWANCE", "BATH", "CONVERSATION",
    "SCHOOL", "COMMEMORATE", "HABIT", "GROUP", "WORD", "STORE",
    "SERVICE", "WORK", "SYSTEM", "TRAIN", "CLASS", "LESSONS",
    "INFORMATION", "LIVING", "TEACHER", "TOURNAMENT", "LETTER", "EVENT",
    "DIGITAL", "TEST", "DEPT STORE", "TELEVISION", "PHONE", "ITEM",
    "NAME", "NEWS", "POPULAR", "PARTY", "STUDY", "MACHINE", "MAIL",
    "MESSAGE", "PROMISE", "DREAM", "KINDERGARTEN", "LIFE", "RADIO",
    "RENTAL", "WORLD",
  },
  [13] = {
    "IDOL", "ANIME", "SONG", "MOVIE", "SWEETS", "CHAT", "CHILD'S PLAY",
    "TOYS", "MUSIC", "CARDS", "SHOPPING", "CAMERA", "VIEWING",
    "SPECTATOR", "GOURMET", "GAME", "RPG", "COLLECTION", "COMPLETE",
    "MAGAZINE", "WALK", "BIKE", "HOBBY", "SPORTS", "SOFTWARE", "SONGS",
    "DIET", "TREASURE", "TRAVEL", "DANCE", "CHANNEL", "MAKING",
    "FISHING", "DATE", "DESIGN", "LOCOMOTIVE", "PLUSH DOLL", "PC",
    "FLOWERS", "HERO", "NAP", "HEROINE", "FASHION", "ADVENTURE",
    "BOARD", "BALL", "BOOK", "FESTIVAL", "COMICS", "HOLIDAY", "PLANS",
    "TRENDY", "VACATION", "LOOK",
  },
}
Game3.SPECIAL_MAUVILLE_GYM_2 = 139
Game3.SPECIAL_MAUVILLE_GYM_1 = 140
Game3.SPECIAL_DRAW_WHOLE_MAP_VIEW = 142
Game3.SPECIAL_STORE_PLAYER_COORDS = 143
Game3.SPECIAL_MAUVILLE_GYM_3 = 144
Game3.SPECIAL_SHOW_FIELD_MESSAGE_VAR4 = 141
Game3.SPECIAL_PETALBURG_GYM_SLIDE = 145
Game3.SPECIAL_PETALBURG_GYM_OPEN = 146
Game3.SPECIAL_GET_PLAYER_TRAINER_ID_ONES = 147
Game3.SPECIAL_SET_HIDDEN_ITEM_FLAG = 150
Game3.SPECIAL_CABLE_CAR_WARP = 151
Game3.SPECIAL_CABLE_CAR = 152
Game3.SPECIAL_RESET_TRICK_HOUSE_END = 260
Game3.SPECIAL_SET_TRICK_HOUSE_END = 261
Game3.FLAG_TRICK_HOUSE_END_ROOM = 0x259
Game3.MAP_INDOOR_ROUTE112_GROUP = 19
Game3.MAP_ROUTE112_CABLE_CAR_NUM = 0
Game3.MAP_MT_CHIMNEY_CABLE_CAR_NUM = 1
Game3.MT_PETALBURG_DOOR_OPEN = 0x21C
Game3.TEXT_NO_REGISTERED_ITEM =
  "An item in the BAG can be registered\non SELECT for convenience."
Game3.SPECIAL_HAS_ENOUGH_MONEY_FOR = 197
Game3.SPECIAL_PAY_MONEY_FOR = 198
Game3.SPECIAL_ROTATING_GATE_INIT = 201
Game3.SPECIAL_ROTATING_GATE_GFX = 202
Game3.SPECIAL_GET_SLOT_MACHINE_ID = 286
-- map_groups.json: IndoorFortree gym is index 1; IndoorRoute110 puzzle 6 is 8.
Game3.MAP_FORTREE_GYM_GROUP = 12
Game3.MAP_FORTREE_GYM_NUM = 1
Game3.MAP_TRICK_HOUSE_PUZZLE6_GROUP = 29
Game3.MAP_TRICK_HOUSE_PUZZLE6_NUM = 8
Game3.GATE_ROT_NONE = 255
Game3.ROTATE_NONE = 0
Game3.ROTATE_ACW = 1
Game3.ROTATE_CW = 2
Game3.GATE_ORIENTATION_270 = 3
Game3.PUZZLE_FORTREE = 1
Game3.PUZZLE_TRICK_HOUSE_6 = 2
function Game3.gateRot(dir, arm, longArm)
  return (tonumber(dir) or 0) * 16 + (tonumber(arm) or 0) * 2
    + (tonumber(longArm) or 0)
end
do
  local none = Game3.GATE_ROT_NONE
  local cw, acw = Game3.ROTATE_CW, Game3.ROTATE_ACW
  local n, e, s, w = 0, 1, 2, 3
  local r = Game3.gateRot
  Game3.ROTATING_GATE_INFO_NORTH = {
    none, none, none, none,
    r(cw, w, 1), r(cw, w, 0), r(acw, e, 0), r(acw, e, 1),
    none, none, none, none,
    none, none, none, none,
  }
  Game3.ROTATING_GATE_INFO_SOUTH = {
    none, none, none, none,
    none, none, none, none,
    r(acw, w, 1), r(acw, w, 0), r(cw, e, 0), r(cw, e, 1),
    none, none, none, none,
  }
  Game3.ROTATING_GATE_INFO_WEST = {
    none, r(acw, n, 1), none, none,
    none, r(acw, n, 0), none, none,
    none, r(cw, s, 0), none, none,
    none, r(cw, s, 1), none, none,
  }
  Game3.ROTATING_GATE_INFO_EAST = {
    none, none, r(cw, n, 1), none,
    none, none, r(cw, n, 0), none,
    none, none, r(acw, s, 0), none,
    none, none, r(acw, s, 1), none,
  }
end
Game3.ROTATING_GATE_CW_POS = {
  { 0, -1 }, { 1, -2 }, { 0, 0 }, { 1, 0 },
  { -1, 0 }, { -1, 1 }, { -1, -1 }, { -2, -1 },
}
Game3.ROTATING_GATE_ACW_POS = {
  { -1, -1 }, { -1, -2 }, { 0, -1 }, { 1, -1 },
  { 0, 0 }, { 0, 1 }, { -1, 0 }, { -2, 0 },
}
-- rotating_gate.c sRotatingGate_ArmLayout: north/east/south/west, short then long.
Game3.ROTATING_GATE_ARMS = {
  { 1, 0, 1, 0, 0, 0, 0, 0 },
  { 1, 1, 1, 0, 0, 0, 0, 0 },
  { 1, 0, 1, 1, 0, 0, 0, 0 },
  { 1, 1, 1, 1, 0, 0, 0, 0 },
  { 1, 0, 1, 0, 1, 0, 0, 0 },
  { 1, 1, 1, 0, 1, 0, 0, 0 },
  { 1, 0, 1, 1, 1, 0, 0, 0 },
  { 1, 0, 1, 0, 1, 1, 0, 0 },
  { 1, 1, 1, 1, 1, 0, 0, 0 },
  { 1, 1, 1, 0, 1, 1, 0, 0 },
  { 1, 0, 1, 1, 1, 1, 0, 0 },
  { 1, 1, 1, 1, 1, 1, 0, 0 },
}
Game3.ROTATING_GATE_ARM_DELTA = {
  { 0, -1 }, { 0, -2 }, { 1, 0 }, { 2, 0 },
  { 0, 1 }, { 0, 2 }, { -1, 0 }, { -2, 0 },
}
-- {x, y, shape, orientation}; map-local, same as rotating_gate.c.
Game3.ROTATING_GATE_FORTREE = {
  { 12, 5, 3, 0 }, { 14, 7, 3, 3 }, { 16, 4, 5, 1 },
  { 15, 14, 1, 0 }, { 18, 13, 4, 2 }, { 8, 20, 4, 2 },
  { 16, 20, 7, 1 },
}
Game3.ROTATING_GATE_TRICK_HOUSE = {
  { 13, 3, 4, 3 }, { 12, 6, 4, 2 }, { 3, 6, 4, 2 },
  { 3, 9, 5, 3 }, { 8, 8, 0, 1 }, { 2, 12, 6, 2 },
  { 9, 13, 1, 0 }, { 3, 14, 2, 1 }, { 9, 15, 3, 2 },
  { 3, 18, 5, 2 }, { 2, 19, 4, 0 }, { 5, 21, 0, 0 },
  { 9, 19, 3, 3 }, { 12, 20, 4, 1 },
}
-- field_specials.c GetSlotMachineId. 12 cabinets; easy-chat salt is 0
-- until TV interviews fill it.
Game3.SLOT_MACHINE_SALT = { 12, 2, 4, 5, 1, 8, 7, 11, 3, 10, 9, 6 }
Game3.SLOT_MACHINE_NORMAL = { 0, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5 }
Game3.SLOT_MACHINE_DISCOUNT = { 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5 }
-- field_specials.c SetPetalburgGymDoorTiles: map xy, then +MAP_OFFSET.
Game3.PETALBURG_GYM_DOORS = {
  [1] = { { 1, 0x68 }, { 7, 0x68 } },
  [2] = { { 1, 0x4E }, { 7, 0x4E } },
  [3] = { { 1, 0x5B }, { 7, 0x5B } },
  [4] = { { 7, 0x27 } },
  [5] = { { 1, 0x34 }, { 7, 0x34 } },
  [6] = { { 1, 0x41 } },
  [7] = { { 7, 0x0D } },
  [8] = { { 1, 0x1A } },
}
-- tileset_mauville_gym.json / metatile_labels.h. MapGrid coords
-- already include MAP_OFFSET 7.
Game3.MT_MAUVILLE_PRESSED = 0x206
Game3.MT_MAUVILLE_RAISED = 0x205
Game3.MT_MAUVILLE_FLOOR = 0x21A
Game3.MT_MAUVILLE_GREEN_H1_ON = 0x220
Game3.MT_MAUVILLE_GREEN_H1_OFF = 0x230
Game3.MT_MAUVILLE_GREEN_H3_ON = 0x228
Game3.MT_MAUVILLE_GREEN_H3_OFF = 0x238
Game3.MT_MAUVILLE_GREEN_V1 = 0x240
Game3.MT_MAUVILLE_GREEN_V2 = 0x248
Game3.MT_MAUVILLE_RED_V1 = 0x241
Game3.MT_MAUVILLE_RED_V2 = 0x249
Game3.MT_MAUVILLE_POLE_BOTTOM_ON = 0x242
Game3.MT_MAUVILLE_POLE_BOTTOM_OFF = 0x243
Game3.MT_MAUVILLE_POLE_TOP_ON = 0x250
Game3.MT_MAUVILLE_POLE_TOP_OFF = 0x251
Game3.MAUVILLE_GYM_SWITCHES = { { 7, 16 }, { 15, 18 }, { 11, 22 } }
Game3.MAUVILLE_GYM_TOGGLE = {
  [0x220] = 0x230, [0x221] = 0x231, [0x228] = 0x238, [0x229] = 0x239,
  [0x230] = 0x220, [0x231] = 0x221,
  [0x238] = 0x228 + 0x0C00, [0x239] = 0x229 + 0x0C00,
  [0x222] = 0x232, [0x223] = 0x233, [0x22A] = 0x23A, [0x22B] = 0x23B,
  [0x232] = 0x222, [0x233] = 0x223,
  [0x23A] = 0x22A + 0x0C00, [0x23B] = 0x22B + 0x0C00,
  [0x240] = 0x242 + 0x0C00, [0x248] = 0x21A,
  [0x241] = 0x243 + 0x0C00, [0x249] = 0x21A,
  [0x242] = 0x240 + 0x0C00, [0x243] = 0x241 + 0x0C00,
  [0x251] = 0x250 + 0x0C00, [0x250] = 0x251,
}
Game3.MAUVILLE_GYM_OFF = {
  [0x220] = 0x230, [0x221] = 0x231, [0x228] = 0x238, [0x229] = 0x239,
  [0x222] = 0x232, [0x223] = 0x233, [0x22A] = 0x23A, [0x22B] = 0x23B,
  [0x240] = 0x242 + 0x0C00, [0x241] = 0x243 + 0x0C00,
  [0x248] = 0x21A, [0x249] = 0x21A, [0x250] = 0x251,
}
Game3.SPECIAL_IS_POKERUS_IN_PARTY = 308
Game3.SPECIAL_INIT_BIRCH_STATE = 211
Game3.SPECIAL_GET_DAYCARE_MON_NICKNAMES = 181
Game3.SPECIAL_GET_DAYCARE_STATE = 182
Game3.SPECIAL_REJECT_EGG_FROM_DAYCARE = 183
Game3.SPECIAL_GIVE_EGG_FROM_DAYCARE = 184
Game3.SPECIAL_SET_DAYCARE_COMPAT_STRING = 185
Game3.SPECIAL_STORE_SELECTED_IN_DAYCARE = 187
Game3.SPECIAL_CHOOSE_SEND_DAYCARE_MON = 188
Game3.SPECIAL_SHOW_DAYCARE_LEVEL_MENU = 189
Game3.SPECIAL_GET_DAYCARE_LEVELS_GAINED = 190
Game3.SPECIAL_GET_DAYCARE_COST = 191
Game3.SPECIAL_TAKE_POKEMON_FROM_DAYCARE = 192
Game3.SPECIAL_GET_POKEDEX_INFO = 212
Game3.SPECIAL_SHOW_POKEDEX_RATING = 213
Game3.SPECIAL_GET_CONTEST_WINNER_IDX = 76
Game3.SPECIAL_GET_CONTEST_PLAYER_MON_IDX = 77
Game3.SPECIAL_CHECK_SELECTED_MON_CONTEST = 84
Game3.SPECIAL_GET_MON_CONDITION = 87
Game3.SPECIAL_GIVE_CONTEST_RIBBON = 89
Game3.SPECIAL_HAS_MON_WON_THIS_CONTEST = 90
Game3.SPECIAL_SHOW_CONTEST_WINNER = 138
Game3.SPECIAL_COMPLETED_HOENN_POKEDEX = 335
Game3.SPECIAL_CHECK_LEAD_MON_COOL = 265
Game3.SPECIAL_CHECK_LEAD_MON_BEAUTY = 266
Game3.SPECIAL_CHECK_LEAD_MON_CUTE = 267
Game3.SPECIAL_CHECK_LEAD_MON_SMART = 268
Game3.SPECIAL_CHECK_LEAD_MON_TOUGH = 269
Game3.DAYCARE_SLOTS = 2
Game3.DAYCARE_MAX_LEVEL = 100
Game3.DAYCARE_BASE_COST = 100
Game3.FLAG_PENDING_DAYCARE_EGG = 0x86
Game3.EGG_GROUP_NONE = 0
Game3.EGG_GROUP_DITTO = 13
Game3.EGG_GROUP_UNDISCOVERED = 15
Game3.EGG_HATCH_LEVEL = 5
Game3.EGG_CYCLE_STEPS = 255
Game3.SPECIES_DITTO = 132
Game3.MON_MALE = 0
Game3.MON_FEMALE = 1
Game3.MON_GENDERLESS = 2
Game3.DAYCARE_COMPAT_TEXT = {
  [70] = "The two seem to get along very well.",
  [50] = "The two seem to get along.",
  [20] = "The two don't seem to like each other much.",
  [0] = "The two prefer to play with other POKeMON than each other.",
}
Game3.VAR_CONTEST_RANK = 0x8010
Game3.VAR_CONTEST_CATEGORY = 0x8011
Game3.CONTEST_CATEGORY_COOL = 0
Game3.CONTEST_CATEGORY_BEAUTY = 1
Game3.CONTEST_CATEGORY_CUTE = 2
Game3.CONTEST_CATEGORY_SMART = 3
Game3.CONTEST_CATEGORY_TOUGH = 4
Game3.CONTEST_RANK_NORMAL = 0
Game3.CONTEST_RANK_SUPER = 1
Game3.CONTEST_RANK_HYPER = 2
Game3.CONTEST_RANK_MASTER = 3
Game3.CONTEST_TURNS = 5
Game3.CONTEST_DEFAULT_APPEAL = 20
-- field_specials.c CheckLeadMonCool: MON_DATA_COOL >= 200.
Game3.CONTEST_LEAD_STAT = 200
Game3.MAX_TOTAL_EVS = 510
Game3.GAME_STAT_RECEIVED_RIBBONS = 42
Game3.VAR_CYCLING_ROAD_RECORD_COLLISIONS = 0x4027
Game3.VAR_CYCLING_ROAD_RECORD_TIME_L = 0x4028
Game3.VAR_CYCLING_ROAD_RECORD_TIME_H = 0x4029
Game3.VAR_CYCLING_CHALLENGE_STATE = 0x40A9
-- map_groups.json gMapGroup_IndoorRoute110 index 12.
Game3.MAP_ROUTE110_CYCLING_NORTH_GROUP = 29
Game3.MAP_ROUTE110_CYCLING_NORTH_NUM = 12
Game3.CYCLING_ROAD_MAX_COLLISIONS = 100
Game3.TEXT_TIMES = " times"
Game3.TEXT_99_TIMES = "99 times"
Game3.TEXT_SECONDS = " seconds"
Game3.TEXT_1_MINUTE = "1 minute"
Game3.VAR_HAPPINESS_STEP_COUNTER = 0x402A
Game3.BASE_FRIENDSHIP = 70
Game3.HATCH_FRIENDSHIP = 120
Game3.MAX_FRIENDSHIP = 255
Game3.FRIENDSHIP_EVENT_GROW_LEVEL = 0
Game3.FRIENDSHIP_EVENT_VITAMIN = 1
Game3.FRIENDSHIP_EVENT_BATTLE_ITEM = 2
Game3.FRIENDSHIP_EVENT_LEAGUE_BATTLE = 3
Game3.FRIENDSHIP_EVENT_LEARN_TMHM = 4
Game3.FRIENDSHIP_EVENT_WALKING = 5
Game3.FRIENDSHIP_EVENT_FAINT_SMALL = 6
Game3.FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE = 7
Game3.FRIENDSHIP_EVENT_FAINT_LARGE = 8
-- pokemon_3.c sFriendshipEventDeltas[event][level 0/1/2]
Game3.FRIENDSHIP_DELTAS = {
  [0] = { 5, 3, 2 },
  [1] = { 5, 3, 2 },
  [2] = { 1, 1, 0 },
  [3] = { 3, 2, 1 },
  [4] = { 1, 1, 0 },
  [5] = { 1, 1, 1 },
  [6] = { -1, -1, -1 },
  [7] = { -5, -5, -10 },
  [8] = { -5, -5, -10 },
}
Game3.TRAINER_CLASS_ELITE_FOUR = 24
Game3.TRAINER_CLASS_LEADER = 25
Game3.TRAINER_CLASS_CHAMPION = 32
Game3.CONTEST_KEYS = { "cool", "beauty", "cute", "smart", "tough" }
Game3.EV_KEYS = { "hpEv", "atkEv", "defEv", "speEv", "spaEv", "spdEv" }
Game3.EV_YIELD_KEYS = {
  "evYieldHp", "evYieldAtk", "evYieldDef",
  "evYieldSpe", "evYieldSpa", "evYieldSpd",
}
Game3.CONTEST_CAT_NAMES = { "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
Game3.CONTEST_RANK_NAMES = { "NORMAL", "SUPER", "HYPER", "MASTER" }
Game3.CONTEST_NPC_SCORES = { 50, 55, 60 }
-- Move type → contest category when ROM contest tables are missing.
Game3.CONTEST_TYPE_CATEGORY = {
  [0] = 4, [1] = 4, [2] = 0, [3] = 3, [4] = 4, [5] = 4, [6] = 3, [7] = 3,
  [8] = 4, [10] = 1, [11] = 1, [12] = 3, [13] = 0, [14] = 3, [15] = 1,
  [16] = 0, [17] = 3,
}
Game3.LOCALID_PLAYER = 0xFF
Game3.LOCALID_MOM_LITTLEROOT = 4
Game3.LOCALID_PLAYERS_HOUSE_1F_MOM = 1
Game3.LOCALID_RIVAL_MOM = 4
Game3.LOCALID_RIVAL = 1
Game3.LOCALID_TWIN = 1
Game3.LOCALID_ROUTE101_BIRCH = 2
Game3.LOCALID_ROUTE101_BAG = 3
Game3.LOCALID_ROUTE101_POOCHYENA = 4
Game3.LOCALID_LAB_AIDE = 1
Game3.LOCALID_LAB_BIRCH = 2
Game3.LOCALID_LAB_RIVAL = 3
Game3.LOCALID_OLDALE_MART = 2
Game3.LOCALID_OLDALE_FOOTPRINTS = 3
Game3.LOCALID_OLDALE_RIVAL = 4
Game3.LOCALID_PETALBURG_GYM_BOY = 9
-- Default object is (12,15). ON_TRANSITION at VAR_PETALBURG_STATE 0
-- parks them at (5,11) to catch you coming in from Route 102.
Game3.PETALBURG_GYM_BOY_DOOR_X = 12
Game3.PETALBURG_GYM_BOY_DOOR_Y = 15
Game3.PETALBURG_GYM_BOY_WEST_X = 5
Game3.PETALBURG_GYM_BOY_WEST_Y = 11
Game3.LOCALID_PETALBURG_GYM_NORMAN = 1
Game3.LOCALID_PETALBURG_GYM_WALLY = 10
-- Default Norman is (4,3) at the badge desk. ON_TRANSITION gym-state < 6
-- parks him at the entrance (4,107). Return-from-tutorial parks Wally at
-- (5,108). Warp dest after the send-off is the city gym door (15,8).
Game3.PETALBURG_GYM_NORMAN_DESK_X = 4
Game3.PETALBURG_GYM_NORMAN_DESK_Y = 3
Game3.PETALBURG_GYM_NORMAN_ENTRANCE_X = 4
Game3.PETALBURG_GYM_NORMAN_ENTRANCE_Y = 107
Game3.PETALBURG_GYM_WALLY_RETURN_X = 5
Game3.PETALBURG_GYM_WALLY_RETURN_Y = 108
Game3.PETALBURG_CITY_GROUP = 0
Game3.PETALBURG_CITY_NUM = 0
Game3.PETALBURG_GYM_GROUP = 8
Game3.PETALBURG_GYM_NUM = 1
Game3.PETALBURG_GYM_EXIT_X = 15
Game3.PETALBURG_GYM_EXIT_Y = 8
Game3.PETALBURG_GYM_RETURN_X = 4
Game3.PETALBURG_GYM_RETURN_Y = 108
Game3.LOCALID_PETALBURG_WALLY = 2
Game3.PETALBURG_WALLY_X = 15
Game3.PETALBURG_WALLY_Y = 10
-- Default object is (13,7) by the door. ON_TRANSITION parks them at
-- (13,14) FACE_DOWN until FLAG_RECEIVED_POTION_OLDALE.
Game3.OLDALE_MART_EMPLOYEE_DOOR_X = 13
Game3.OLDALE_MART_EMPLOYEE_DOOR_Y = 7
Game3.OLDALE_MART_EMPLOYEE_OUTSKIRTS_X = 13
Game3.OLDALE_MART_EMPLOYEE_OUTSKIRTS_Y = 14
Game3.MOVEMENT_TYPE_FACE_UP = 7
Game3.MOVEMENT_TYPE_FACE_DOWN = 8
Game3.MOVEMENT_TYPE_FACE_LEFT = 9
Game3.MOVEMENT_TYPE_FACE_RIGHT = 10
-- pokeruby MOVEMENT_TYPE_INVISIBLE. Dummy objects (Devon 3F's second
-- Mr. Stone on the conference table) must not draw or collide.
Game3.MOVEMENT_TYPE_INVISIBLE = 0x4C
Game3.GRASS_RUSTLE = 0.32
Game3.EVOLVE_ANIM = 1.4
Game3.FONT_MALE = 0xB5
Game3.FONT_FEMALE = 0xB6
Game3.DIR_SOUTH = 1
Game3.DIR_NORTH = 2
Game3.DIR_WEST = 3
Game3.DIR_EAST = 4
Game3.DIR_FACING = { "south", "north", "west", "east" }
Game3.TRAINER_FLAG_START = 0x500
-- EventScript_ResetAllMapFlags (data/scripts/new_game.inc): these start SET
-- so story NPCs stay hidden until a later script clears them. Game3.new()
-- stays empty for tests. A ROM import overwrites this via constants.resetMapFlags.
Game3.NEW_GAME_HIDE_FLAGS = {
  0x56, 0x301, 0x302, 0x303, 0x2D1, 0x379, 0x2D6, 0x363,
  0x2DB, 0x2DC, 0x32E, 0x364, 0x2E3, 0x371, 0x2E2, 0x2E4,
  0x2E5, 0x2E7, 0x2E8, 0x38A, 0x2E1, 0x2EB, 0x2EC, 0x2ED,
  0x2F4, 0x306, 0x37F, 0x308, 0x309, 0x30A, 0x30B, 0x30C,
  0x30D, 0x30E, 0x30F, 0x2DE, 0x351, 0x315, 0x316, 0x317,
  0x318, 0x31D, 0x31E, 0x31F, 0x385, 0x386, 0x387, 0x388,
  0x320, 0x321, 0x323, 0x322, 0x326, 0x328, 0x329, 0x3D8,
  0x32B, 0x32C, 0x362, 0x32F, 0x330, 0x365, 0x337, 0x33C,
  0x33D, 0x33F, 0x35B, 0x349, 0x34B, 0x34C, 0x34F, 0x34D,
  0x34E, 0x35C, 0x35D, 0x343, 0x348, 0x350, 0x353, 0x357,
  0x358, 0x3CD, 0x366, 0x368, 0x36D, 0x36F, 0x37B, 0x370,
  0x36E, 0x327, 0x3D7, 0x376, 0x374, 0x375, 0x3C1, 0x378,
  0x3AD, 0x2F0, 0x2F5, 0x37C, 0x380, 0x381, 0x382, 0x38D,
  0x38E, 0x38F, 0x393, 0x390, 0x398, 0x399, 0x39A, 0x39B,
  0x39D, 0x3A1, 0x3A2, 0x3A6, 0x3AB, 0x3AC, 0x3A0, 0x342,
  0x3B0, 0x3B1, 0x3B3, 0x3B4, 0x35A, 0x3B6, 0x3C8, 0x46D,
  0x2D7, 0x3D3, 0x2EF, 0x3DF,
}
Game3.RIVAL_BRENDAN_2F_X = 1
Game3.RIVAL_BRENDAN_2F_Y = 2
Game3.RIVAL_MAY_2F_X = 7
Game3.RIVAL_MAY_2F_Y = 2
Game3.TWIN_SAVE_BIRCH_X = 10
Game3.TWIN_SAVE_BIRCH_Y = 1
Game3.TWIN_GUARD_X = 7
Game3.TWIN_GUARD_Y = 2
Game3.STARTER_NAMES = {
  [286] = "POOCHYENA",
  [277] = "TREECKO",
  [278] = "GROVYLE",
  [279] = "SCEPTILE",
  [280] = "TORCHIC",
  [281] = "COMBUSKEN",
  [282] = "BLAZIKEN",
  [283] = "MUDKIP",
  [284] = "MARSHTOMP",
  [285] = "SWAMPERT",
}
Game3.STAT_ATK = 0
Game3.STAT_DEF = 1
Game3.STAT_SPE = 2
Game3.STAT_SPA = 3
Game3.STAT_SPD = 4
Game3.NATURE_NAMES = {
  [0] = "HARDY", "LONELY", "BRAVE", "ADAMANT", "NAUGHTY",
  "BOLD", "DOCILE", "RELAXED", "IMPISH", "LAX",
  "TIMID", "HASTY", "SERIOUS", "JOLLY", "NAIVE",
  "MODEST", "MILD", "QUIET", "BASHFUL", "RASH",
  "CALM", "GENTLE", "SASSY", "CAREFUL", "QUIRKY",
}
Game3.BG_HIDDEN_ITEM = 7
Game3.BG_SECRET_BASE = 8
Game3.FLAG_HIDDEN_ITEMS_START = 0x258
Game3.VAR_CURRENT_SECRET_BASE = 0x4054
Game3.SECRET_BASE_MAP_ID = "secret_base"
Game3.MB_SECRET_BASE_SPOT_MIN = 0x90
Game3.MB_SECRET_BASE_SPOT_MAX = 0x9D
Game3.HEAL_AMOUNT = {
  [13] = 20,   -- Potion
  [19] = 999,  -- Full Restore
  [20] = 999,  -- Max Potion
  [21] = 200,  -- Hyper Potion
  [22] = 50,   -- Super Potion
  [26] = 50,   -- Fresh Water
  [27] = 60,   -- Soda Pop (Seashore House)
  [28] = 80,   -- Lemonade
  [29] = 100,  -- Moomoo Milk
  [139] = 10,  -- Oran Berry
  [142] = 30,  -- Sitrus Berry
}
Game3.STATUS_HEAL = {
  [14] = "psn",  -- Antidote
  [15] = "brn",  -- Burn Heal
  [16] = "frz",  -- Ice Heal
  [17] = "slp",  -- Awakening
  [18] = "par",  -- Parlyz Heal
  [19] = true,   -- Full Restore
  [23] = true,   -- Full Heal
  [133] = "par", -- Cheri Berry
  [134] = "slp", -- Chesto Berry
  [135] = "psn", -- Pecha Berry
  [136] = "brn", -- Rawst Berry
  [137] = "frz", -- Aspear Berry
  [141] = true,  -- Lum Berry
}
Game3.MB_JUMP_EAST = 0x38
Game3.MB_JUMP_WEST = 0x39
Game3.MB_JUMP_NORTH = 0x3A
Game3.MB_JUMP_SOUTH = 0x3B
Game3.MB_JUMP_NORTHEAST = 0x3C
Game3.MB_JUMP_NORTHWEST = 0x3D
Game3.MB_JUMP_SOUTHEAST = 0x3E
Game3.MB_JUMP_SOUTHWEST = 0x3F
Game3.MB_COUNTER = 0x80
Game3.MB_PC = 0x83
Game3.MB_TELEVISION = 0x86
Game3.MB_SECRET_BASE_PC = 0xB0
Game3.MB_PLAYER_ROOM_PC = 0xC5
Game3.MB_CRACKED_FLOOR_HOLE = 0x66
Game3.MB_THIN_ICE = 0x26
Game3.MB_CRACKED_ICE = 0x27
Game3.MB_ASHGRASS = 0x24
Game3.MB_PACIFIDLOG_VERTICAL_LOG_1 = 0x74
Game3.MB_PACIFIDLOG_VERTICAL_LOG_2 = 0x75
Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_1 = 0x76
Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_2 = 0x77
Game3.MB_FORTREE_BRIDGE = 0x78
Game3.MB_CRACKED_FLOOR = 0xD2
Game3.STEP_CB_ASH = 1
Game3.STEP_CB_FORTREE = 2
Game3.STEP_CB_PACIFIDLOG = 3
Game3.STEP_CB_ICE = 4
Game3.STEP_CB_CRACKED_FLOOR = 7
-- Fallarbor / Lavaridge ash grass -> the matching normal grass metatile.
Game3.ASH_CLEAR = {
  [0x20A] = 0x212,
  [0x207] = 0x206,
}
-- Pacifidlog floating / half / fully-submerged ids for each log half.
Game3.PACIFIDLOG_STAGE = {
  [0x250] = { 0x250, 0x252, 0x254 },
  [0x252] = { 0x250, 0x252, 0x254 },
  [0x254] = { 0x250, 0x252, 0x254 },
  [0x251] = { 0x251, 0x253, 0x255 },
  [0x253] = { 0x251, 0x253, 0x255 },
  [0x255] = { 0x251, 0x253, 0x255 },
  [0x258] = { 0x258, 0x259, 0x25A },
  [0x259] = { 0x258, 0x259, 0x25A },
  [0x25A] = { 0x258, 0x259, 0x25A },
  [0x260] = { 0x260, 0x261, 0x262 },
  [0x261] = { 0x260, 0x261, 0x262 },
  [0x262] = { 0x260, 0x261, 0x262 },
}
Game3.LAYER_NORMAL = 0
Game3.LAYER_COVERED = 1
Game3.LAYER_SPLIT = 2
Game3.MAP_TYPE_TOWN = 1
Game3.MAP_TYPE_CITY = 2
Game3.MAP_TYPE_ROUTE = 3
Game3.MAP_TYPE_UNDERGROUND = 4
Game3.MAP_TYPE_UNDERWATER = 5
Game3.MAP_TYPE_OCEAN_ROUTE = 6
Game3.MAP_TYPE_INDOOR = 8
Game3.MAP_TYPE_SECRET_BASE = 9
-- Official group-0 town/city order from pokeruby map_groups, listed in
-- FLAG_VISITED / MAPSEC order so the Fly picker matches the region map.
Game3.FLY_DESTINATIONS = {
  { mapId = "g0_9",  name = "LITTLEROOT TOWN",  flag = 0x80F },
  { mapId = "g0_10", name = "OLDALE TOWN",      flag = 0x810 },
  { mapId = "g0_11", name = "DEWFORD TOWN",     flag = 0x811 },
  { mapId = "g0_12", name = "LAVARIDGE TOWN",   flag = 0x812 },
  { mapId = "g0_13", name = "FALLARBOR TOWN",   flag = 0x813 },
  { mapId = "g0_14", name = "VERDANTURF TOWN",  flag = 0x814 },
  { mapId = "g0_15", name = "PACIFIDLOG TOWN",  flag = 0x815 },
  { mapId = "g0_0",  name = "PETALBURG CITY",   flag = 0x816 },
  { mapId = "g0_1",  name = "SLATEPORT CITY",   flag = 0x817 },
  { mapId = "g0_2",  name = "MAUVILLE CITY",    flag = 0x818 },
  { mapId = "g0_3",  name = "RUSTBORO CITY",    flag = 0x819 },
  { mapId = "g0_4",  name = "FORTREE CITY",     flag = 0x81A },
  { mapId = "g0_5",  name = "LILYCOVE CITY",    flag = 0x81B },
  { mapId = "g0_6",  name = "MOSSDEEP CITY",    flag = 0x81C },
  { mapId = "g0_7",  name = "SOOTOPOLIS CITY",  flag = 0x81D },
  { mapId = "g0_8",  name = "EVER GRANDE CITY", flag = 0x81E },
}
Game3.FLY_BY_ID = {}
for i = 1, #Game3.FLY_DESTINATIONS do
  local d = Game3.FLY_DESTINATIONS[i]
  Game3.FLY_BY_ID[d.mapId] = d
end
Game3.MB_POND_WATER = 0x10
Game3.MB_INTERIOR_DEEP_WATER = 0x11
Game3.MB_DEEP_WATER = 0x12
Game3.MB_WATERFALL = 0x13
Game3.MB_SOOTOPOLIS_DEEP_WATER = 0x14
Game3.MB_OCEAN_WATER = 0x15
Game3.MB_NO_SURFACING = 0x18
Game3.MB_SEAWEED = 0x22
Game3.MB_SEAWEED_NO_SURFACING = 0x28
Game3.TRAINER_TYPE_NORMAL = 1
Game3.TRAINER_TYPE_SEE_ALL = 2
Game3.EVO_LEVEL = 4
Game3.EVO_LEVEL_ATK_GT_DEF = 8
Game3.EVO_LEVEL_ATK_EQ_DEF = 9
Game3.EVO_LEVEL_ATK_LT_DEF = 10
Game3.EVO_LEVEL_SILCOON = 11
Game3.EVO_LEVEL_CASCOON = 12
Game3.EVO_LEVEL_NINJASK = 13
Game3.FALLBACK_EVOS = {
  [280] = { { method = 4, param = 16, target = 281 } },
  [281] = { { method = 4, param = 36, target = 282 } },
  [277] = { { method = 4, param = 16, target = 278 } },
  [278] = { { method = 4, param = 36, target = 279 } },
  [283] = { { method = 4, param = 16, target = 284 } },
  [284] = { { method = 4, param = 36, target = 285 } },
  [290] = {
    { method = 11, param = 7, target = 291 },
    { method = 12, param = 7, target = 292 },
  },
  [291] = { { method = 4, param = 10, target = 293 } },
  [292] = { { method = 4, param = 10, target = 294 } },
}

function Game3.snapPixel(n)
  n = n or 0
  if n >= 0 then return math.floor(n + 0.5) end
  return -math.floor(-n + 0.5)
end

-- pokeemerald gInitialMovementTypeFacingDirections (DIR_SOUTH=south, …).
local MT_FACING = {
  "south", "south", "south", "north", "south", "west", "east",
  "north", "south", "west", "east", "south", "south", "south", "west",
  "north", "north", "south", "south", "south", "south", "north", "south",
  "south", "south", "north", "south", "west", "east",
  "north", "east", "south", "west", "north", "west", "south", "east",
  "west", "north", "east", "south", "east", "north", "west", "south",
  "north", "south", "west", "east", "north", "south", "west", "east",
  "north", "south", "west", "east",
  "south", "south",
  "north", "south", "west", "east",
  "south",
  "south", "north", "west", "east",
  "south", "north", "west", "east",
  "south", "north", "west", "east",
  "south",
}

local function loadGenerated(path)
  local CacheFs = require("src.import.CacheFs")
  return CacheFs.loadActive(path)
end

local function namedList(pokemon)
  local list = {}
  local byIndex = pokemon and pokemon.byIndex or {}
  local count = (pokemon and pokemon.count) or 0
  for index = 0, count - 1 do
    local row = byIndex[index]
    local name = row and row.name or ""
    if name ~= "" and not name:match("^[?%-]+$") then
      list[#list + 1] = { id = index, name = name }
    end
  end
  return list
end

function Game3.mapId(group, index)
  return ("g%d_%d"):format(group, index)
end

function Game3.collisionOf(cell)
  return math.floor((cell or 0) / 1024) % 4
end

function Game3.metatileOf(cell)
  return (cell or 0) % 1024
end

function Game3.walkable(map, x, y)
  if type(map) ~= "table" or type(map.grid) ~= "table" then return false end
  local w, h = map.width or 0, map.height or 0
  if x < 0 or y < 0 or x >= w or y >= h then return false end
  return Game3.collisionOf(map.grid[y * w + x + 1]) == 0
end

function Game3.warpAt(map, x, y)
  if type(map) ~= "table" or type(map.warps) ~= "table" then return nil end
  for i = 1, #map.warps do
    local w = map.warps[i]
    if w and w.x == x and w.y == y then return w end
  end
  return nil
end

function Game3.objectAt(map, x, y)
  if type(map) ~= "table" or type(map.objects) ~= "table" then return nil end
  for i = 1, #map.objects do
    local o = map.objects[i]
    if o and o.x == x and o.y == y then return o end
  end
  return nil
end

function Game3.bgAt(map, x, y)
  if type(map) ~= "table" or type(map.bgEvents) ~= "table" then return nil end
  for i = 1, #map.bgEvents do
    local e = map.bgEvents[i]
    if e and e.x == x and e.y == y then return e end
  end
end

function Game3.hiddenFlag(hiddenId)
  return Game3.FLAG_HIDDEN_ITEMS_START + (hiddenId or 0)
end

local BG_FACE = { [1] = "north", [2] = "south", [3] = "east", [4] = "west" }

function Game3.bgFacingOk(kind, facing)
  if not kind or kind == 0 then return true end
  local need = BG_FACE[kind]
  if not need then return true end
  return need == facing
end

function Game3.new()
  local self = setmetatable({
    speedOverride = nil,
    capturePath = nil,
    world = nil,
    status = nil,
    phase = "boot", -- boot | play | roster | battle
    input = Input,
    data = { pokemon = {}, constants = {}, header = {}, maps = {}, tilesets = {}, sprites = {}, encounters = {}, moves = {}, trainers = {}, items = {}, title = {} },
    scroll = 1,
    playerX = 0,
    playerY = 0,
    camX = 0,
    camY = 0,
    walkCooldown = 0,
    walkFromX = 0,
    walkFromY = 0,
    facing = "south",
    map = nil,
    ignoreWarp = false,
    atlasCache = {},
    spriteCache = {},
    npcByMap = {},
    tileBatches = {},
    gbaCanvas = nil,
    quads = {},
    balls = Game3.START_BALLS,
    bag = {},
    money = Game3.START_MONEY,
    party = {},
    pc = {},
    caught = {},
    seen = {},
    gender = Game3.GENDER_MALE,
    flags = {},
    saveExists = false,
    playSeconds = 0,
    customName = nil,
    options = { textSpeed = 2, battleScene = true, battleStyle = "shift", stereo = false },
  }, Game3)
  self:applyGender(Game3.GENDER_MALE)
  self:ensureTrainerId()
  self:resetBoot()
  return self
end

function Game3:lookupMap(group, index)
  local pack = self.data.maps
  if not pack or not pack.maps then return nil end
  return pack.maps[Game3.mapId(group, index)]
end

function Game3:lookupMapById(id)
  local pack = self.data.maps
  if not pack or not pack.maps or not id then return nil end
  return pack.maps[id]
end

-- pokeruby showobjectat LOCALID_PLAYER, MAP_DEWFORD_TOWN (and the
-- Route 104 / 109 returns) puts the sprite on Mr. Briney's boat.
function Game3:objectGfxXY(map, gfxId)
  local objs = map and map.objects or {}
  for i = 1, #objs do
    local o = objs[i]
    if o and o.graphicsId == gfxId then
      return o.x or 0, o.y or 0
    end
  end
end

function Game3.isTruckMap(map)
  if type(map) ~= "table" then return false end
  if map.connections and #map.connections > 0 then return false end
  local w, h = map.width or 0, map.height or 0
  if w < 4 or w > 8 or h < 4 or h > 8 then return false end
  local objs = map.objects or {}
  if #objs < 2 or #objs > 5 then return false end
  local hits = 0
  for i = 1, #objs do
    local o = objs[i]
    if o and o.x == 0 and o.y == 0 then hits = hits + 1 end
    if o and o.x == 0 and o.y == 3 then hits = hits + 1 end
    if o and o.x == 2 and o.y == 3 then hits = hits + 1 end
  end
  return hits >= 2
end

function Game3:findTruckMap()
  local maps = self.data.maps and self.data.maps.maps
  if type(maps) ~= "table" then return nil end
  for _, map in pairs(maps) do
    if Game3.isTruckMap(map) then return map end
  end
end

function Game3:birchLabMap()
  local preferred = self:lookupMap(Game3.LAB_GROUP, Game3.LAB_NUM)
  if preferred then return preferred end
  local maps = self.data.maps and self.data.maps.maps
  if type(maps) ~= "table" then return nil end
  for _, map in pairs(maps) do
    local objects = map and map.objects or {}
    for i = 1, #objects do
      local o = objects[i]
      if o and (o.graphicsId or 0) == Game3.GFX_BIRCH
          and o.x == Game3.LAB_X and o.y == Game3.LAB_Y - 1 then
        return map
      end
    end
  end
end

function Game3.clockEvent(map)
  local evs = map and map.bgEvents or {}
  for i = 1, #evs do
    local t = evs[i] and evs[i].text
    if type(t) == "string" and t:find("clock is stopped", 1, true) then
      return evs[i]
    end
  end
end

function Game3.isBedroomMap(map)
  return Game3.clockEvent(map) ~= nil
end

function Game3.isBrendanBedroom(map)
  local ev = Game3.clockEvent(map)
  return ev ~= nil and (ev.x or 0) >= 4
end

function Game3.coordAt(map, x, y)
  local events = map and map.coordEvents
  if type(events) ~= "table" then return nil end
  for i = 1, #events do
    local ev = events[i]
    if ev and ev.x == x and ev.y == y then return ev end
  end
end

function Game3:bedroomMap(wantBrendan)
  local maps = self.data.maps and self.data.maps.maps
  if type(maps) ~= "table" then return nil end
  local fallback
  for _, map in pairs(maps) do
    if Game3.isBedroomMap(map) then
      fallback = fallback or map
      if Game3.isBrendanBedroom(map) == wantBrendan then return map end
    end
  end
  return fallback
end

function Game3:playerBedroomMap()
  return self:bedroomMap(not self:isFemale())
end

function Game3:setHealLocation(id)
  id = tonumber(id) or 0
  local room
  if id == Game3.HEAL_LITTLEROOT_BRENDAN_2F then
    room = self:bedroomMap(true)
  elseif id == Game3.HEAL_LITTLEROOT_MAY_2F then
    room = self:bedroomMap(false)
  end
  if not room then return false end
  local x, y = Game3.HEAL_BEDROOM_X, Game3.HEAL_BEDROOM_Y
  if not Game3.walkable(room, x, y) then
    local spawn = room.spawn or {}
    x, y = spawn.x or x, spawn.y or y
  end
  self.lastHeal = {
    mapId = room.id,
    x = x,
    y = y,
  }
  return true
end

function Game3:setBedroomHeal()
  return self:setHealLocation(self:isFemale()
    and Game3.HEAL_LITTLEROOT_MAY_2F or Game3.HEAL_LITTLEROOT_BRENDAN_2F)
end

function Game3:setDynamicWarp(group, num, warpId, x, y)
  self.dynamicWarp = {
    mapGroup = tonumber(group) or 0,
    mapNum = tonumber(num) or 0,
    warpId = tonumber(warpId) or Game3.WARP_ID_NONE,
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
  }
  return true
end

function Game3:setHoleWarp(group, num, warpId, x, y)
  self.holeWarp = {
    mapGroup = tonumber(group) or 0,
    mapNum = tonumber(num) or 0,
    warpId = tonumber(warpId) or Game3.WARP_ID_NONE,
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
  }
  return true
end

-- pokeruby gSaveBlock1.warp4. Outdoor (town/city/route/ocean/underwater)
-- into indoor/underground/secret base records the current map at xy.
function Game3.isOutdoorMapType(t)
  t = t or 0
  return t == Game3.MAP_TYPE_TOWN
    or t == Game3.MAP_TYPE_CITY
    or t == Game3.MAP_TYPE_ROUTE
    or t == Game3.MAP_TYPE_UNDERWATER
    or t == Game3.MAP_TYPE_OCEAN_ROUTE
end

function Game3:setEscapeWarp(group, num, warpId, x, y)
  group = tonumber(group) or 0
  num = tonumber(num) or 0
  local dest = self:lookupMap(group, num)
  self.escapeWarp = {
    mapId = dest and dest.id,
    mapGroup = group,
    mapNum = num,
    warpId = tonumber(warpId) or Game3.WARP_ID_NONE,
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
  }
  return true
end

function Game3:maybeSetEscapeWarp(dest, x, y)
  local from = self.map
  if not from or not dest then return end
  if not Game3.isOutdoorMapType(from.mapType) then return end
  if Game3.isOutdoorMapType(dest.mapType) then return end
  self.escapeWarp = {
    mapId = from.id,
    mapGroup = from.group,
    mapNum = from.index,
    x = tonumber(x) or self.playerX or 0,
    y = tonumber(y) or self.playerY or 0,
  }
end

function Game3:warpHole(group, num)
  group = tonumber(group) or 0
  num = tonumber(num) or 0
  local x, y = self.playerX or 0, self.playerY or 0
  if group == Game3.MAP_UNDEFINED_GROUP and num == Game3.MAP_UNDEFINED_NUM then
    local h = self.holeWarp
    if h then
      group, num = h.mapGroup, h.mapNum
    else
      return self:fallDownHole()
    end
  end
  self.walkCooldown = 0
  self.moveJobs = {}
  if self:scriptWarp(group, num, Game3.WARP_ID_NONE, x, y) then
    self.field = { kind = "talk", text = "You fell through!" }
    return true
  end
  return self:fallDownHole()
end

function Game3:followDynamicWarp()
  local d = self.dynamicWarp
  if not d then return false end
  return self:scriptWarp(d.mapGroup, d.mapNum, d.warpId, d.x, d.y)
end

function Game3:truckTownXY()
  if self:isFemale() then
    return Game3.TRUCK_TOWN_FEMALE_X, Game3.TRUCK_TOWN_FEMALE_Y
  end
  return Game3.TRUCK_TOWN_MALE_X, Game3.TRUCK_TOWN_MALE_Y
end

function Game3:setTruckIntroFlags()
  self.flags = self.flags or {}
  self.scriptVars = self.scriptVars or {}
  if self:isFemale() then
    self.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE] = 2
    self.scriptVars[Game3.VAR_LITTLEROOT_HOUSES_STATE] = 1
  else
    self.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE] = 1
    self.scriptVars[Game3.VAR_LITTLEROOT_HOUSES_STATE_2] = 1
  end
  self:setBedroomHeal()
end

function Game3:littlerootTownMap()
  local start = self:startMap()
  if start and not Game3.isTruckMap(start) then return start end
end

function Game3:scriptWarp(group, num, warpId, x, y)
  group, num = tonumber(group) or 0, tonumber(num) or 0
  warpId = tonumber(warpId) or Game3.WARP_ID_NONE
  x, y = tonumber(x) or 0, tonumber(y) or 0
  local dest = self:lookupMap(group, num)
  if not dest then return false end
  if warpId ~= Game3.WARP_ID_NONE then
    local dw = dest.warps and dest.warps[warpId + 1]
    if dw then
      x, y = dw.x or x, dw.y or y
    end
  end
  self:rememberLastWarp()
  self:enterMap(dest, x, y, true)
  return true
end

function Game3:exitTruck()
  self:setTruckIntroFlags()
  local town = self:littlerootTownMap()
  if town then
    local x, y = self:truckTownXY()
    local w, h = town.width or 0, town.height or 0
    if x >= 0 and y >= 0 and x < w and y < h then
      self:enterMap(town, x, y, true)
      self.facing = "south"
      return true
    end
  end
  local room = self:playerBedroomMap()
  if room then
    local spawn = room.spawn or {}
    local x, y = spawn.x or 4, spawn.y or 4
    if not Game3.walkable(room, x, y) then
      x, y = spawn.x or 0, spawn.y or 0
    end
    self:enterMap(room, x, y, true)
    self.facing = "south"
    return true
  end
  if not town then return false end
  local spawn = town.spawn or {}
  self:enterMap(town, spawn.x or 0, spawn.y or 0, false)
  self.facing = "south"
  return true
end

function Game3:revealBirchLab()
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB] = nil
  self.flags[Game3.FLAG_HIDE_BIRCH_ROUTE101] = true
  self.flags[Game3.FLAG_HIDE_BIRCH_BATTLE_POOCHYENA] = true
  self.flags[Game3.FLAG_HIDE_POOCHYENA_ROUTE101] = true
end

function Game3:warpToBirchLab()
  local lab = self:birchLabMap()
  if not lab then return false end
  local x, y = Game3.LAB_X, Game3.LAB_Y
  if not Game3.walkable(lab, x, y) then
    local spawn = lab.spawn or {}
    x, y = spawn.x or 0, spawn.y or 0
  end
  self:enterMap(lab, x, y, true)
  self.facing = "north"
  return true
end

function Game3:startBirchChase()
  if not self:startWildBattle(Game3.SPECIES_POOCHYENA, Game3.CHASE_LEVEL) then
    return false
  end
  self.battle.chase = true
  return true
end

function Game3:finishBirchChase()
  self:revealBirchLab()
  self:warpToBirchLab()
  self.field = {
    kind = "talk",
    text = "PROF. BIRCH: Thanks! Let's talk in my lab.",
  }
end

function Game3:savePlayerParty()
  local src = self.party or {}
  local copy = {}
  for i = 1, #src do
    copy[i] = self:cloneMon(src[i])
  end
  self.savedParty = copy
  return true
end

function Game3:loadPlayerParty()
  local saved = self.savedParty
  if type(saved) ~= "table" then return false end
  local copy = {}
  for i = 1, #saved do
    copy[i] = self:cloneMon(saved[i])
  end
  self.party = copy
  self.savedParty = nil
  return true
end

function Game3:putZigzagoonInPlayerParty()
  local mon = self:makeMon(
    Game3.SPECIES_ZIGZAGOON, Game3.WALLY_TUTORIAL_ZIGZAGOON_LEVEL)
  mon.ivs = {
    hp = 32, atk = 32, def = 32, spa = 32, spd = 32, spe = 32,
  }
  self:recalcStats(mon)
  mon.hp = mon.maxHp
  mon.moves = { self:copyMove(Game3.MOVE_TACKLE) }
  -- pokeruby SetMonData MON_DATA_ALT_ABILITY TRUE: Zigzagoon's second
  -- slot is none, so Pickup does not fire on the loaner.
  mon.ability = 0
  self.party = self.party or {}
  self.party[1] = mon
  return true
end

function Game3:startWallyTutorialBattle()
  self:beginScriptWait()
  if not self:startWildBattle(
      Game3.SPECIES_RALTS, Game3.WALLY_TUTORIAL_RALTS_LEVEL) then
    self:endScriptWait()
    return false
  end
  self.battle.wallyTutorial = true
  return true
end

function Game3:tryWallyTutorialAction()
  local b = self.battle
  if not (b and b.wallyTutorial and b.kind == "menu") then return false end
  if not b.wallyTackled then
    b.wallyTackled = true
    local move = b.player and b.player.moves and b.player.moves[1]
    self:beginTurn(move)
    return true
  end
  if not b.wallyThrew then
    b.wallyThrew = true
    self:throwBall(Game3.ITEM_POKE_BALL)
    return true
  end
  return false
end

function Game3:saveFs()
  return self._saveFs or (love and love.filesystem)
end

function Game3:snapshotMon(mon)
  if type(mon) ~= "table" then return nil end
  local moves = {}
  for i = 1, #(mon.moves or {}) do
    local m = mon.moves[i]
    if m then moves[#moves + 1] = { id = m.id, pp = m.pp } end
  end
  return {
    species = mon.species,
    level = mon.level,
    hp = mon.hp,
    exp = mon.exp,
    pid = mon.pid,
    ivs = Game3.copyIvs(mon.ivs),
    status = mon.status,
    sleepTurns = mon.sleepTurns,
    moves = moves,
    otId = mon.otId,
    otName = mon.otName,
    name = mon.name,
    isEgg = mon.isEgg and true or nil,
    hatchLeft = mon.hatchLeft,
    cool = mon.cool,
    beauty = mon.beauty,
    cute = mon.cute,
    smart = mon.smart,
    tough = mon.tough,
    sheen = mon.sheen,
    item = mon.item,
    effortRibbon = mon.effortRibbon and true or nil,
    hpEv = mon.hpEv,
    atkEv = mon.atkEv,
    defEv = mon.defEv,
    speEv = mon.speEv,
    spaEv = mon.spaEv,
    spdEv = mon.spdEv,
    friendship = mon.friendship,
    ribbons = type(mon.ribbons) == "table" and {
      cool = mon.ribbons.cool,
      beauty = mon.ribbons.beauty,
      cute = mon.ribbons.cute,
      smart = mon.ribbons.smart,
      tough = mon.ribbons.tough,
    } or nil,
  }
end

function Game3:restoreMon(row)
  if type(row) ~= "table" or not row.species then return nil end
  local moveIds = {}
  for i = 1, #(row.moves or {}) do
    local m = row.moves[i]
    if m and m.id then moveIds[#moveIds + 1] = m.id end
  end
  local mon = self:makeMon(row.species, row.level, #moveIds > 0 and moveIds or nil)
  if type(row.pid) == "number" then mon.pid = row.pid end
  if type(row.ivs) == "table" then
    mon.ivs = Game3.copyIvs(row.ivs)
  else
    mon.ivs = Game3.zeroIvs()
  end
  self:setAbility(mon)
  if type(row.exp) == "number" then mon.exp = row.exp end
  if row.status then
    mon.status = row.status
    mon.sleepTurns = row.sleepTurns
  end
  for i = 1, #(mon.moves or {}) do
    local src = row.moves and row.moves[i]
    if src and type(src.pp) == "number" then
      mon.moves[i].pp = math.max(0, math.min(mon.moves[i].maxPp or src.pp, src.pp))
    end
  end
  if type(row.otId) == "number" then mon.otId = row.otId end
  if type(row.otName) == "string" and row.otName ~= "" then
    mon.otName = row.otName
  end
  if row.isEgg then
    mon.isEgg = true
    mon.name = "EGG"
    mon.hatchLeft = tonumber(row.hatchLeft) or self:eggCyclesFor(mon.species)
  elseif type(row.name) == "string" and row.name ~= "" then
    mon.name = row.name
  end
  for _, key in ipairs(Game3.CONTEST_KEYS) do
    if type(row[key]) == "number" then mon[key] = row[key] end
  end
  if type(row.sheen) == "number" then mon.sheen = row.sheen end
  if type(row.friendship) == "number" then mon.friendship = row.friendship end
  if row.effortRibbon then mon.effortRibbon = true end
  for _, key in ipairs(Game3.EV_KEYS) do
    if type(row[key]) == "number" then mon[key] = row[key] end
  end
  self:recalcStats(mon)
  if type(row.hp) == "number" then
    mon.hp = math.max(0, math.min(mon.maxHp, row.hp))
  end
  local held = tonumber(row.item)
  if held and held > 0 then mon.item = held end
  if type(row.ribbons) == "table" then
    mon.ribbons = {}
    for _, key in ipairs(Game3.CONTEST_KEYS) do
      mon.ribbons[key] = tonumber(row.ribbons[key]) or nil
    end
  end
  return mon
end

function Game3:snapshotScriptVars()
  local out = {}
  for k, v in pairs(self.scriptVars or {}) do
    local id = tonumber(k)
    local n = tonumber(v)
    if id and n and n ~= 0
        and id >= Game3.VARS_START and id < Game3.SPECIAL_VARS_START then
      out[id] = n
    end
  end
  return out
end

function Game3:loadScriptVars(vars)
  self.scriptVars = {}
  if type(vars) ~= "table" then return end
  for k, v in pairs(vars) do
    local id = tonumber(k)
    local n = tonumber(v)
    if id and n and id >= Game3.VARS_START and id < Game3.SPECIAL_VARS_START then
      self.scriptVars[id] = n
    end
  end
end

function Game3:snapshotSave()
  local party = {}
  for i = 1, #(self.party or {}) do
    party[i] = self:snapshotMon(self.party[i])
  end
  local bag = {}
  for i = 1, #(self.bag or {}) do
    local slot = self.bag[i]
    if slot then bag[#bag + 1] = { id = slot.id, count = slot.count } end
  end
  local flags = {}
  for k, v in pairs(self.flags or {}) do
    if v then flags[k] = true end
  end
  local pc = {}
  self:ensurePc()
  for b = 1, Game3.BOX_COUNT do
    local box = {}
    local src = self.pc[b] or {}
    for i = 1, #src do
      box[i] = self:snapshotMon(src[i])
    end
    pc[b] = box
  end
  self:harvestCaught()
  return {
    format = Game3.SAVE_FORMAT,
    engine = "gen3",
    version = "ruby",
    mapId = self.map and self.map.id,
    x = self.playerX or 0,
    y = self.playerY or 0,
    facing = self.facing or "south",
    money = self.money or 0,
    balls = self.balls or 0,
    bag = bag,
    party = party,
    pc = pc,
    caught = self:snapshotCaught(),
    seen = self:snapshotSeen(),
    gender = self.gender or Game3.GENDER_MALE,
    rivalSpecies = self.rivalSpecies,
    rivalTookStarter = self.rivalTookStarter and true or nil,
    flags = flags,
    vars = self:snapshotScriptVars(),
    healMapId = self.lastHeal and self.lastHeal.mapId,
    healX = self.lastHeal and self.lastHeal.x,
    healY = self.lastHeal and self.lastHeal.y,
    escapeMapId = self.escapeWarp and self.escapeWarp.mapId,
    escapeMapGroup = self.escapeWarp and self.escapeWarp.mapGroup,
    escapeMapNum = self.escapeWarp and self.escapeWarp.mapNum,
    escapeX = self.escapeWarp and self.escapeWarp.x,
    escapeY = self.escapeWarp and self.escapeWarp.y,
    repelSteps = self.repelSteps or 0,
    daycare = self:snapshotDaycare(),
    daycarePending = self.daycarePending,
    eggCycleSteps = self.eggCycleSteps or 0,
    secretBase = self:snapshotSecretBase(),
    berryTrees = self:snapshotBerryTrees(),
    berryMinuteAcc = self.berryMinuteAcc or 0,
    easyChatPairs = self:snapshotEasyChatPairs(),
    playerName = self:playerName(),
    playSeconds = math.floor(self.playSeconds or 0),
    dexCount = self:dexCount(),
    badgeCount = self:badgeCount(),
    options = self.options,
    trainerId = self:ensureTrainerId(),
    registeredItem = self.registeredItem or 0,
  }
end

function Game3:hasSave()
  local data = self:readSave()
  return data ~= nil
end

function Game3:readSave()
  local fs = self:saveFs()
  if not (fs and fs.read) then return nil, "no filesystem" end
  local raw = fs.read(Game3.SAVE_FILE)
  if type(raw) ~= "string" or raw == "" then return nil, "missing" end
  local data, err = SaveSerializer.decode(raw)
  if not data then return nil, err end
  if data.format ~= Game3.SAVE_FORMAT or data.engine ~= "gen3" then
    return nil, "wrong format"
  end
  if type(data.party) ~= "table" then
    return nil, "unreadable"
  end
  return data
end

function Game3:writeSave()
  if self.phase == "battle" then return false, "Can't save now." end
  local fs = self:saveFs()
  if not (fs and fs.write) then return false, "Save failed." end
  local encoded = SaveSerializer.encode(self:snapshotSave())
  local ok = fs.write(Game3.SAVE_FILE, encoded)
  if not ok then return false, "Save failed." end
  self.saveExists = true
  return true
end

function Game3:applySave(data)
  if type(data) ~= "table" then return false, "unreadable" end
  local rows = data.party
  if type(rows) ~= "table" then rows = {} end
  local party = {}
  for i = 1, #rows do
    local mon = self:restoreMon(rows[i])
    if mon then party[#party + 1] = mon end
  end
  self.party = party
  self.bag = {}
  self.balls = 0
  for i = 1, #(data.bag or {}) do
    local slot = data.bag[i]
    if slot then self:addItem(slot.id, slot.count or 1) end
  end
  if self:itemCount(Game3.ITEM_POKE_BALL) < 1 then
    self.balls = data.balls or 0
  end
  self.money = data.money or 0
  self.flags = {}
  for k, v in pairs(data.flags or {}) do
    if v then self.flags[k] = true end
  end
  self:loadScriptVars(data.vars)
  self.pc = {}
  self:ensurePc()
  if type(data.pc) == "table" then
    for b = 1, Game3.BOX_COUNT do
      local src = data.pc[b]
      if type(src) == "table" then
        for i = 1, #src do
          local mon = self:restoreMon(src[i])
          if mon then
            local box = self.pc[b]
            box[#box + 1] = mon
          end
        end
      end
    end
  end
  self.caught = {}
  self.seen = {}
  if type(data.caught) == "table" then
    for i = 1, #data.caught do
      self:markCaught(data.caught[i])
    end
    for k, v in pairs(data.caught) do
      if v == true then self:markCaught(k) end
    end
  end
  if type(data.seen) == "table" then
    for i = 1, #data.seen do
      self:markSeen(data.seen[i])
    end
    for k, v in pairs(data.seen) do
      if v == true then self:markSeen(k) end
    end
  end
  self:harvestCaught()
  if self.flags and self.flags[Game3.FLAG_SYS_NATIONAL_DEX] then
    self.scriptVars = self.scriptVars or {}
    self.scriptVars[Game3.VAR_NATIONAL_DEX] = Game3.NATIONAL_DEX_ENABLED
  end
  self.gender = data.gender == Game3.GENDER_FEMALE
    and Game3.GENDER_FEMALE or Game3.GENDER_MALE
  if type(data.playerName) == "string" and data.playerName ~= "" then
    self.customName = data.playerName
  end
  self.playSeconds = tonumber(data.playSeconds) or 0
  if type(data.options) == "table" then self.options = data.options end
  if tonumber(data.trainerId) then
    self.trainerId = math.floor(tonumber(data.trainerId))
  else
    self:ensureTrainerId()
  end
  self.registeredItem = tonumber(data.registeredItem) or 0
  self.rivalSpecies = tonumber(data.rivalSpecies)
  self.rivalTookStarter = data.rivalTookStarter and true or nil
  if data.healMapId then
    self.lastHeal = {
      mapId = data.healMapId,
      x = data.healX or 0,
      y = data.healY or 0,
    }
  else
    self.lastHeal = nil
  end
  if data.escapeMapId or data.escapeMapGroup then
    self.escapeWarp = {
      mapId = data.escapeMapId,
      mapGroup = data.escapeMapGroup,
      mapNum = data.escapeMapNum,
      x = data.escapeX or 0,
      y = data.escapeY or 0,
    }
  else
    self.escapeWarp = nil
  end
  local steps = tonumber(data.repelSteps) or 0
  self.repelSteps = steps > 0 and steps or nil
  self:loadDaycare(data.daycare)
  local pending = tonumber(data.daycarePending) or 0
  self.daycarePending = pending > 0 and pending or nil
  self.eggCycleSteps = tonumber(data.eggCycleSteps) or 0
  self:loadSecretBase(data.secretBase)
  self:loadBerryTrees(data.berryTrees)
  self.berryMinuteAcc = tonumber(data.berryMinuteAcc) or 0
  self:loadEasyChatPairs(data.easyChatPairs)
  self.facing = data.facing or "south"
  local map = self:lookupMapById(data.mapId)
  if not map and data.mapId == Game3.SECRET_BASE_MAP_ID then
    map = self:secretBaseMap()
  end
  if not map and self.map and self.map.id == data.mapId then
    map = self.map
  end
  if map then
    self:enterMap(map, data.x or 0, data.y or 0, true)
  else
    self.playerX = data.x or 0
    self.playerY = data.y or 0
  end
  self.battle = nil
  self.field = nil
  return true
end

function Game3:continueSave()
  local data, err = self:readSave()
  if not data then return false, err or "No save file." end
  local ok, why = self:applySave(data)
  if not ok then return false, why end
  if not self.map then self:spawnAtNewGame() end
  self.phase = "play"
  self.boot = nil
  return true
end

function Game3.facingFromDelta(dx, dy)
  if dy and dy < 0 then return "north" end
  if dy and dy > 0 then return "south" end
  if dx and dx < 0 then return "west" end
  if dx and dx > 0 then return "east" end
  return "south"
end

function Game3.deltaFromFacing(facing)
  if facing == "north" then return 0, -1 end
  if facing == "south" then return 0, 1 end
  if facing == "west" then return -1, 0 end
  if facing == "east" then return 1, 0 end
  return 0, 1
end

function Game3.oppositeFacing(facing)
  if facing == "north" then return "south" end
  if facing == "south" then return "north" end
  if facing == "west" then return "east" end
  if facing == "east" then return "west" end
  return "south"
end

-- pokeruby MOVEMENT_TYPE_WALK_SEQUENCE_* (0x1D–0x34). Briney 0x32 /
-- Peeko 0x33 after VAR_BRINEY_HOUSE_STATE is the cottage chase.
Game3.WALK_SEQUENCES = {
  [0x1D] = { "north", "east", "west", "south" },
  [0x1E] = { "east", "west", "south", "north" },
  [0x1F] = { "south", "north", "east", "west" },
  [0x20] = { "west", "south", "north", "east" },
  [0x21] = { "north", "west", "east", "south" },
  [0x22] = { "west", "east", "south", "north" },
  [0x23] = { "south", "north", "west", "east" },
  [0x24] = { "east", "south", "north", "west" },
  [0x25] = { "west", "north", "south", "east" },
  [0x26] = { "north", "south", "east", "west" },
  [0x27] = { "east", "west", "north", "south" },
  [0x28] = { "south", "east", "west", "north" },
  [0x29] = { "east", "north", "south", "west" },
  [0x2A] = { "north", "south", "west", "east" },
  [0x2B] = { "west", "east", "north", "south" },
  [0x2C] = { "south", "west", "east", "north" },
  [0x2D] = { "north", "west", "south", "east" },
  [0x2E] = { "south", "east", "north", "west" },
  [0x2F] = { "west", "south", "east", "north" },
  [0x30] = { "east", "north", "west", "south" },
  [0x31] = { "north", "east", "south", "west" },
  [0x32] = { "south", "west", "north", "east" },
  [0x33] = { "west", "north", "east", "south" },
  [0x34] = { "east", "south", "west", "north" },
}

function Game3.wanderDirs(movementType)
  local mt = movementType or 0
  if mt == 1 then return "look" end
  if mt == 2 then return { "north", "south", "west", "east" } end
  if mt == 3 or mt == 4 or mt == 25 or mt == 26 then
    return { "north", "south" }
  end
  if mt == 5 or mt == 6 or mt == 27 or mt == 28 then
    return { "west", "east" }
  end
  if Game3.WALK_SEQUENCES[mt] then return "seq" end
  if mt >= 64 and mt <= 75 then return "place" end
  if mt >= 84 and mt <= 87 then return "place" end
  return nil
end

function Game3.neighborOrigin(conn, src, dest)
  if type(conn) ~= "table" or type(src) ~= "table" or type(dest) ~= "table" then
    return nil
  end
  local off = conn.offset or 0
  if conn.dir == "north" then return off, -(dest.height or 0) end
  if conn.dir == "south" then return off, src.height or 0 end
  if conn.dir == "west" then return -(dest.width or 0), off end
  if conn.dir == "east" then return src.width or 0, off end
  return nil
end

function Game3.facingFromMovementType(movementType)
  return MT_FACING[(movementType or 0) + 1] or "south"
end

function Game3.poseFor(spec, facing, moving, t)
  facing = facing or "south"
  local pose
  if moving and spec and spec.walk and spec.walk[facing] and #spec.walk[facing] > 0 then
    local poses = spec.walk[facing]
    local i = math.floor((t or 0) * #poses) + 1
    if i < 1 then i = 1 elseif i > #poses then i = #poses end
    pose = poses[i]
  else
    pose = spec and spec.face and spec.face[facing]
  end
  if not pose then return { frame = 0, flip = false } end
  -- Inanimate sheets (bag, truck) are one frame. LOOK_AROUND still
  -- changes facing, and a borrowed walk script can index past the PNG.
  local n = spec and spec.frameCount
  local frame = pose.frame or 0
  if n and frame >= n then
    return { frame = 0, flip = pose.flip and true or false }
  end
  return pose
end

function Game3.spriteSpec(sprites, graphicsId)
  local byId = sprites and sprites.byId
  if type(byId) ~= "table" then return nil end
  return byId[graphicsId]
end

function Game3.spriteDrawPos(tileX, tileY, width, height, lift)
  width = width or Game3.TILE
  height = height or Game3.TILE
  local px = Game3.snapPixel(tileX * Game3.TILE + math.floor((Game3.TILE - width) / 2))
  local py = Game3.snapPixel(tileY * Game3.TILE + Game3.TILE - height - (lift or 0))
  return px, py
end

function Game3:grabImage(path)
  if type(path) ~= "string" then return nil end
  local Assets = require("src.render.Assets")
  local ok, img = pcall(Assets.image, path)
  if not ok or not img then
    ok, img = pcall(love.graphics.newImage, path)
  end
  if ok and img then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  return nil
end

function Game3:layersFor(tilesetId)
  if not tilesetId then return nil, nil end
  local cached = self.atlasCache[tilesetId]
  if cached then return cached.bottom, cached.top end
  local spec = self.data.tilesets and self.data.tilesets.byId
    and self.data.tilesets.byId[tilesetId]
  if not spec then return nil, nil end
  local bottom = self:grabImage(spec.bottom)
  local top = self:grabImage(spec.top)
  self.atlasCache[tilesetId] = { bottom = bottom, top = top }
  return bottom, top
end

function Game3:loadTileset()
  self.layerBottom, self.layerTop = nil, nil
  local map = self.map
  if not map then return end
  self.layerBottom, self.layerTop = self:layersFor(map.tileset)
end

function Game3:quadFor(mid, image)
  local cols = (self.data.tilesets and self.data.tilesets.atlasCols) or Game3.ATLAS_COLS
  local sw, sh = 512, 512
  if image and image.getDimensions then
    sw, sh = image:getDimensions()
  end
  local key = mid .. ":" .. sw .. "x" .. sh
  local q = self.quads[key]
  if not q then
    local col = mid % cols
    local row = math.floor(mid / cols)
    q = love.graphics.newQuad(
      col * Game3.TILE, row * Game3.TILE,
      Game3.TILE, Game3.TILE, sw, sh)
    self.quads[key] = q
  end
  return q
end

function Game3:quadFor8(mid, corner, image)
  local cols = (self.data.tilesets and self.data.tilesets.atlasCols) or Game3.ATLAS_COLS
  local sw, sh = 512, 512
  if image and image.getDimensions then
    sw, sh = image:getDimensions()
  end
  local key = "8:" .. mid .. ":" .. corner .. ":" .. sw
  local q = self.quads[key]
  if not q then
    local col = mid % cols
    local row = math.floor(mid / cols)
    q = love.graphics.newQuad(
      col * Game3.TILE + (corner % 2) * 8,
      row * Game3.TILE + math.floor(corner / 2) * 8,
      8, 8, sw, sh)
    self.quads[key] = q
  end
  return q
end

function Game3:drawAnimCorners(image, map, mid, px, py, topPass, batch, behavior, mode)
  if Game3.ledgeDelta(behavior) then return end
  local spec = self.data.tilesets and self.data.tilesets.byId
    and map and self.data.tilesets.byId[map.tileset]
  local tiles = spec and spec.overworldAnim and spec.tiles and spec.tiles[mid]
  if not tiles then return end
  if not self:tileAnimFlip() then return end
  local start = topPass and 5 or 1
  local i0, i1 = 0, 3
  if mode == "top8" then i1 = 1 elseif mode == "bottom8" then i0 = 2 end
  local G = love.graphics
  for i = i0, i1 do
    if Game3.shouldAnimCorner(tiles[start + i], behavior, tiles, start) then
      local q = self:quadFor8(mid, i, image)
      local ox = (i % 2) * 8
      local oy = math.floor(i / 2) * 8
      if batch then
        batch:add(q, px + ox + 8, py + oy, 0, -1, 1)
      else
        G.draw(image, q, px + ox + 8, py + oy, 0, -1, 1)
      end
    end
  end
end

function Game3:beginScriptRun()
  self._scriptDepth = (self._scriptDepth or 0) + 1
end

function Game3:endScriptRun()
  local d = self._scriptDepth
  if not d then return end
  d = d - 1
  if d < 1 then
    self._scriptDepth = nil
    self:flushPendingMapScripts()
  else
    self._scriptDepth = d
  end
end

function Game3:flushPendingMapScripts()
  if not self._pendingMapFrame then return false end
  if self.field then return false end
  if (self._scriptDepth or 0) > 0 then return false end
  self._pendingMapFrame = nil
  if self:tryMapFrameScript() then return true end
  return self:tryCoordEvent(self.playerX, self.playerY)
end

function Game3:wipeNewGameState()
  self.party = {}
  self.pc = {}
  self.caught = {}
  self.seen = {}
  self.bag = {}
  self.money = Game3.START_MONEY
  self.balls = 0
  self:addItem(Game3.ITEM_POKE_BALL, Game3.START_BALLS)
  self.flags = {}
  self:applyNewGameHideFlags()
  self.scriptVars = {}
  -- pokemon_size_record.c InitShroomish/BarboachSizeRecord: 0x8100 is Marco.
  self.scriptVars[Game3.VAR_SHROOMISH_SIZE_RECORD] = Game3.SIZE_RECORD_DEFAULT
  self.scriptVars[Game3.VAR_BARBOACH_SIZE_RECORD] = Game3.SIZE_RECORD_DEFAULT
  self.field = nil
  self.battle = nil
  self._scriptPause = nil
  self._scriptReturn = nil
  self._scriptSays = nil
  self._scriptLoaded = nil
  self._scriptCmp = 0
  self._scriptDepth = nil
  self._pendingMapFrame = nil
  self.scriptWait = nil
  self.delayLeft = nil
  self.moveJobs = {}
  self.stepCallback = nil
  self.dynamicWarp = nil
  self.escapeWarp = nil
  self.lastUsedWarp = nil
  self.bikeCyclingChallenge = nil
  self.bikeCollisions = nil
  self.bikeCyclingTimer = nil
  self.vblankCounter = 0
  self.moneyBox = nil
  self.monCrySrc = nil
  self.waitingCry = nil
  self.invisible = nil
  self.flashLevel = 0
  self.facingLocked = nil
  self.lockAnim = nil
  self.playSeconds = 0
  self.lastHeal = nil
  self.repelSteps = nil
  self.daycare = {}
  self.daycarePending = nil
  self.eggCycleSteps = 0
  self.secretBase = nil
  self:initBerryTrees()
  self.berryMinuteAcc = 0
  self:initDewfordTrend()
  self.rivalSpecies = nil
  self.rivalTookStarter = nil
  self.gameStats = nil
  self.registeredItem = nil
  self.npcByMap = {}
  self.facing = "south"
end

function Game3:spawnAtNewGame()
  local truck = self:findTruckMap()
  if truck then
    -- WarpToTruck writes dummy xy (-1,-1). SetPlayerCoordsFromWarp then
    -- uses layout width/2, height/2, not the first walkable cell.
    local w, h = truck.width or 5, truck.height or 5
    self:enterMap(truck, math.floor(w / 2), math.floor(h / 2), false)
    self:setBedroomHeal()
    return true
  end
  local pack = self.data and self.data.maps
  local start = pack and pack.maps and pack.maps[pack.start]
  if start then
    local spawn = start.spawn or {}
    self:enterMap(start, spawn.x or 0, spawn.y or 0, false)
    self:setBedroomHeal()
    return true
  end
  return self.map ~= nil
end

function Game3:resetWorldForNewGame()
  self:wipeNewGameState()
  self:spawnAtNewGame()
end

function Game3:enterMap(map, x, y, ignoreWarp)
  self.map = map
  self.playerX = x
  self.playerY = y
  self.walkFromX = x
  self.walkFromY = y
  self.walkCooldown = 0
  self.moveJobs = {}
  self.invisible = nil
  self.fixedPriority = nil
  self.objSubpriority = nil
  self.ignoreWarp = ignoreWarp and true or false
  self.grassRustle = nil
  -- ROM templates keep their extracted xy. ON_TRANSITION may park a
  -- blocker for this visit only; leftover perm from the last visit would
  -- leave the Littleroot twin / Oldale footprints man on the map edge.
  self:clearObjectPerms(map)
  self:setDefaultFlashLevel(map)
  self:runMapScript("onTransition")
  self:runMapScript("onLoad")
  self:runMapScript("onResume")
  self:resetNpcs(map)
  -- tv.c UpdateTVScreensOnMap FlagSet(FLAG_SYS_TV_WATCH) on every load.
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SYS_TV_WATCH] = true
  self:lightExitDoors()
  self:clampCamera()
  self:loadTileset()
  if self.surfing and not Game3.isSurfable(self:behaviorAt(map, x, y)) then
    self.surfing = nil
    self.climbing = nil
    self.diving = nil
  end
  if self.bike and not Game3.canBikeOn(map) then
    self.bike = nil
  end
  self:markFlyVisited(map)
  self:runMapScriptTable("onWarp", false)
  -- pokeruby runs the dest ON_FRAME after the warp script finishes, not
  -- nested inside warpsilent. Boot cinema also must not run field scripts
  -- or NEW GAME can leave the map mid-scene and fall through to the roster.
  if (self._scriptDepth or 0) > 0 or self.phase == "boot" then
    self._pendingMapFrame = true
  else
    self:tryMapFrameScript()
    self:tryCoordEvent(x, y)
  end
end

function Game3:load()
  Input:init()
  TouchControls:init()
  self.touchControls = TouchControls
  self.data.header = loadGenerated("data/generated/header.lua") or {}
  self.data.constants = loadGenerated("data/generated/constants.lua") or {}
  self.data.pokemon = loadGenerated("data/generated/pokemon.lua") or {}
  self.data.maps = require("src.import.Gen3MapPack").load() or {}
  self.data.tilesets = loadGenerated("data/generated/tilesets.lua") or {}
  self.data.sprites = loadGenerated("data/generated/sprites.lua") or {}
  self.data.encounters = loadGenerated("data/generated/encounters.lua") or {}
  self.data.moves = loadGenerated("data/generated/moves.lua") or {}
  self.data.trainers = loadGenerated("data/generated/trainers.lua") or {}
  self.data.items = loadGenerated("data/generated/items.lua") or {}
  self.data.font = loadGenerated("data/generated/font.lua") or {}
  self.data.title = loadGenerated("data/generated/title.lua") or {}
  self.named = namedList(self.data.pokemon)
  self.atlasCache = {}
  self.spriteCache = {}
  self.battlePicCache = {}
  self.npcByMap = {}
  self.tileBatches = {}
  self.quads = {}
  self:resetWorldForNewGame()
  self.gender = nil
  self.phase = "boot"
  self.scroll = 1
  self.walkCooldown = 0
  self.facing = "south"
  self.saveExists = self:hasSave()
  self.playSeconds = 0
  self.customName = nil
  self.options = {
    textSpeed = 2, battleScene = true, battleStyle = "shift", stereo = false,
  }
  self.trainerId = nil
  self:ensureTrainerId()
  self:resetBoot()
end

function Game3:visualTile()
  local x, y = self.playerX, self.playerY
  if (self.walkCooldown or 0) > 0 then
    local t = self:walkProgress()
    x = (self.walkFromX or x) + (self.playerX - (self.walkFromX or x)) * t
    y = (self.walkFromY or y) + (self.playerY - (self.walkFromY or y)) * t
  end
  return x, y
end

function Game3:walkProgress()
  if (self.walkCooldown or 0) <= 0 then return 1 end
  local dur = self.walkDuration or Game3.WALK_PERIOD
  if dur <= 0 then return 1 end
  local t = 1 - self.walkCooldown / dur
  if t < 0 then return 0 end
  if t > 1 then return 1 end
  return t
end

function Game3:worldBounds()
  local map = self.map
  if not map then return 0, 0, 0, 0 end
  local x0, y0 = 0, 0
  local x1 = (map.width or 0) * Game3.TILE
  local y1 = (map.height or 0) * Game3.TILE
  for i = 1, #(map.connections or {}) do
    local c = map.connections[i]
    local dest = c and self:lookupMap(c.mapGroup, c.mapNum)
    if dest then
      local ox, oy = Game3.neighborOrigin(c, map, dest)
      if ox then
        local dx0, dy0 = ox * Game3.TILE, oy * Game3.TILE
        local dx1 = dx0 + (dest.width or 0) * Game3.TILE
        local dy1 = dy0 + (dest.height or 0) * Game3.TILE
        if dx0 < x0 then x0 = dx0 end
        if dy0 < y0 then y0 = dy0 end
        if dx1 > x1 then x1 = dx1 end
        if dy1 > y1 then y1 = dy1 end
      end
    end
  end
  return x0, y0, x1, y1
end

function Game3:clampCamera()
  local map = self.map
  if not map then
    self.camX, self.camY = 0, 0
    return
  end
  local vx, vy = self:visualTile()
  local spec = Game3.spriteSpec(self.data and self.data.sprites, self:playerGraphicsId())
  local sw = spec and spec.width or Game3.TILE
  local sh = spec and spec.height or Game3.TILE
  local px, py = Game3.spriteDrawPos(vx, vy, sw, sh, self.levitate or 0)
  local focusX = px + sw / 2
  local focusY = py + sh / 2
  local camX = focusX - Game3.SCREEN_W / 2
  local camY = focusY - Game3.SCREEN_H / 2
  -- fieldmap.h MAP_OFFSET 7: the GBA camera can look into the border, so
  -- the player stays at 120,80. Our layouts have no border. Clamping to
  -- the grid puts Granite B1F's 24px Flash hole on empty floor. Briney's
  -- sail walks the hidden player off Dewford; keep them centered too.
  local jobs = self.moveJobs
  local scriptWalk = type(jobs) == "table" and #jobs > 0
  if self:flashRadius() < 1 and not scriptWalk then
    local x0, y0, x1, y1 = self:worldBounds()
    local maxX = math.max(x0, x1 - Game3.SCREEN_W)
    local maxY = math.max(y0, y1 - Game3.SCREEN_H)
    if camX < x0 then camX = x0 elseif camX > maxX then camX = maxX end
    if camY < y0 then camY = y0 elseif camY > maxY then camY = maxY end
  end
  -- Integer SCX/SCY.  Fractional cameras put nearest-neighbour tiles on
  -- half-pixels and the seams flash while walking a map bigger than the
  -- 240×160 window.
  self.camX, self.camY = Game3.snapPixel(camX), Game3.snapPixel(camY)
end

function Game3:connectionDest(map, x, y, dx, dy)
  local dir
  if dy < 0 then dir = "north"
  elseif dy > 0 then dir = "south"
  elseif dx < 0 then dir = "west"
  else dir = "east"
  end
  for i = 1, #(map.connections or {}) do
    local c = map.connections[i]
    if c and c.dir == dir then
      local dest = self:lookupMap(c.mapGroup, c.mapNum)
      if not dest then return nil end
      local ox = c.offset or 0
      if dir == "north" then return dest, x - ox, dest.height - 1 end
      if dir == "south" then return dest, x - ox, 0 end
      if dir == "west" then return dest, dest.width - 1, y - ox end
      return dest, 0, y - ox
    end
  end
  return nil
end

-- pokeruby ApplyCurrentWarp: gLastUsedWarp = gSaveBlock1.location
-- before writing gWarpDestination. Connections do not update it.
function Game3:rememberLastWarp()
  local m = self.map
  if type(m) ~= "table" then
    self.lastUsedWarp = nil
    return
  end
  self.lastUsedWarp = {
    mapGroup = tonumber(m.group) or 0,
    mapNum = tonumber(m.index) or 0,
  }
end

function Game3:followWarp(w)
  if not w then return false end
  if self.map and self.map.id == Game3.SECRET_BASE_MAP_ID then
    return self:exitSecretBase()
  end
  if w.warpId == Game3.WARP_ID_NONE or w.warpId == Game3.WARP_ID_DYNAMIC then
    if self:followDynamicWarp() then return true end
    if Game3.isTruckMap(self.map) then
      return self:exitTruck()
    end
    return true
  end
  local dest = self:lookupMap(w.mapGroup, w.mapNum)
  if not dest then return true end
  self:maybeSetEscapeWarp(dest, w.x or self.playerX, w.y or self.playerY)
  local dw = dest.warps and dest.warps[w.warpId + 1]
  local x = dw and dw.x or (dest.spawn and dest.spawn.x) or 0
  local y = dw and dw.y or (dest.spawn and dest.spawn.y) or 0
  -- House doors are solid.  RSE walks you one step out (usually south)
  -- after the warp so you are not stuck in the wall.
  local ignore = true
  if not Game3.walkable(dest, x, y) then
    local dirs = { { 0, 1, "south" }, { 0, -1, "north" }, { -1, 0, "west" }, { 1, 0, "east" } }
    for i = 1, #dirs do
      local sx, sy = x + dirs[i][1], y + dirs[i][2]
      if Game3.walkable(dest, sx, sy) then
        x, y, ignore = sx, sy, false
        self.facing = dirs[i][3]
        break
      end
    end
  end
  self:rememberLastWarp()
  self:enterMap(dest, x, y, ignore)
  self:settleAfterWarp()
  return true
end

-- Indoor stairs land you on a walkable warp facing the wall you walked
-- into. Hold-through would bump that wall forever. Face a free tile and
-- ignore the d-pad until it is released.
function Game3:settleAfterWarp()
  self.warpSettle = true
  local map = self.map
  if not map then return end
  local x, y = self.playerX, self.playerY
  if not Game3.warpAt(map, x, y) then return end
  local function free(dx, dy)
    local nx, ny = x + dx, y + dy
    return Game3.walkable(map, nx, ny)
      and not Game3.warpAt(map, nx, ny)
      and not self:npcAt(map, nx, ny)
  end
  local fdx, fdy = Game3.deltaFromFacing(self.facing)
  if free(fdx, fdy) then return end
  local dirs = {
    { 0, 1, "south" }, { 1, 0, "east" }, { -1, 0, "west" }, { 0, -1, "north" },
  }
  for i = 1, #dirs do
    if free(dirs[i][1], dirs[i][2]) then
      self.facing = dirs[i][3]
      return
    end
  end
end

function Game3:tryWalk(dx, dy)
  local map = self.map
  if not map then return false end
  self.facing = Game3.facingFromDelta(dx, dy)
  local nx = self.playerX + dx
  local ny = self.playerY + dy
  if Game3.isTruckMap(map) and nx >= 3 then
    local warp = Game3.warpAt(map, nx, ny)
    if warp and not self.ignoreWarp then
      return self:followWarp(warp)
    end
    if not Game3.coordAt(map, nx, ny) then
      return self:exitTruck()
    end
  end
  if nx < 0 or ny < 0 or nx >= (map.width or 0) or ny >= (map.height or 0) then
    local dest, dx_, dy_ = self:connectionDest(map, self.playerX, self.playerY, dx, dy)
    if dest and self:canStep(dest, dx_, dy_) and not self:npcAt(dest, dx_, dy_) then
      self:maybeSetEscapeWarp(dest, self.playerX, self.playerY)
      self:enterMap(dest, dx_, dy_, false)
      self:tickWalkCounters()
      return true
    end
    self:tryAdvanceCyclingRoadCollisions()
    return false
  end
  -- Gen 3 doors sit on collision.  Walking into that tile is the warp.
  -- pokeruby TryStartStepBasedScript runs coord events first, so the
  -- house doormat's GoSeeRoom (intro 4) beats the door warp to town.
  local warp = Game3.warpAt(map, nx, ny)
  if warp and not self.ignoreWarp and not self:coordEventWouldRun(nx, ny) then
    return self:followWarp(warp)
  end
  if self:isOwnedSecretBaseTile(map, nx, ny) then
    return self:enterSecretBase()
  end
  local blocker = self:npcAt(map, nx, ny)
  if blocker then
    if blocker.graphicsId == Game3.GFX_PUSHABLE_BOULDER then
      if not self:strengthOn() or not self:pushBoulder(blocker, dx, dy) then
        self:tryAdvanceCyclingRoadCollisions()
        return false
      end
    else
      self:tryAdvanceCyclingRoadCollisions()
      return false
    end
  end
  if not self:canStep(map, nx, ny) then
    if self:tryLedgeHop(map, dx, dy) then return true end
    self:tryAdvanceCyclingRoadCollisions()
    return false
  end
  if self:checkRotatingGateCollision(nx, ny, Game3.dirId(self.facing)) then
    self:tryAdvanceCyclingRoadCollisions()
    return false
  end
  if self.surfing and Game3.walkable(map, nx, ny)
      and not Game3.isSurfable(self:behaviorAt(map, nx, ny)) then
    self.surfing = nil
    self.climbing = nil
    self.diving = nil
  end
  local ox, oy = self.playerX, self.playerY
  self.walkFromX, self.walkFromY = ox, oy
  self.playerX, self.playerY = nx, ny
  self.walkDuration = self:walkPeriod()
  self.walkCooldown = self.walkDuration
  self:clampCamera()
  if self.ignoreWarp and not Game3.warpAt(map, nx, ny) then
    self.ignoreWarp = false
  end
  self:runStepCallback(ox, oy)
  self:tickWalkCounters()
  self:tryCoordEvent(nx, ny)
  self:beginGrassRustle(nx, ny)
  return true
end

function Game3:gridIndex(map, x, y)
  local w, h = map and map.width or 0, map and map.height or 0
  if not map or x < 0 or y < 0 or x >= w or y >= h then return nil end
  return y * w + x + 1
end

function Game3:setMetatile(x, y, tile, collision)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i or type(map.grid) ~= "table" then return false end
  local col = (collision and collision ~= 0) and 1 or 0
  map.grid[i] = (tonumber(tile) or 0) % 1024 + col * 1024
  return true
end

-- fieldmap.c MapGrid*At: x/y include MAP_OFFSET 7. Collision lives in
-- bits 10-11; elevation (12-15) is preserved on write.
function Game3:mapGridGetMetatileId(gx, gy)
  local x = (tonumber(gx) or 0) - Game3.MAP_OFFSET
  local y = (tonumber(gy) or 0) - Game3.MAP_OFFSET
  local i = self:gridIndex(self.map, x, y)
  if not i then return 0 end
  return Game3.metatileOf(self.map.grid[i])
end

function Game3:mapGridGetCollision(gx, gy)
  local x = (tonumber(gx) or 0) - Game3.MAP_OFFSET
  local y = (tonumber(gy) or 0) - Game3.MAP_OFFSET
  local i = self:gridIndex(self.map, x, y)
  if not i then return 1 end
  return Game3.collisionOf(self.map.grid[i])
end

function Game3:mapGridSetMetatileId(gx, gy, metatile)
  local x = (tonumber(gx) or 0) - Game3.MAP_OFFSET
  local y = (tonumber(gy) or 0) - Game3.MAP_OFFSET
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i or type(map.grid) ~= "table" then return false end
  local elev = math.floor((map.grid[i] or 0) / 4096) * 4096
  map.grid[i] = elev + ((tonumber(metatile) or 0) % 4096)
  return true
end

function Game3:mauvilleGymSpecial1()
  local which = tonumber(self:varGet(0x8004)) or 0
  local switches = Game3.MAUVILLE_GYM_SWITCHES
  for i = 1, #switches do
    local tile = Game3.MT_MAUVILLE_RAISED
    if i - 1 == which then tile = Game3.MT_MAUVILLE_PRESSED end
    self:mapGridSetMetatileId(switches[i][1], switches[i][2], tile)
  end
end

function Game3:mauvilleGymSpecial2()
  local toggle = Game3.MAUVILLE_GYM_TOGGLE
  local floor = Game3.MT_MAUVILLE_FLOOR
  local greenV1 = Game3.MT_MAUVILLE_GREEN_V1
  local coll = Game3.MAPGRID_COLLISION_MASK
  for y = 12, 23 do
    for x = 7, 15 do
      local id = self:mapGridGetMetatileId(x, y)
      if id == floor then
        if self:mapGridGetMetatileId(x, y - 1) == greenV1 then
          self:mapGridSetMetatileId(x, y, Game3.MT_MAUVILLE_GREEN_V2 + coll)
        else
          self:mapGridSetMetatileId(x, y, Game3.MT_MAUVILLE_RED_V2 + coll)
        end
      else
        local to = toggle[id]
        if to then self:mapGridSetMetatileId(x, y, to) end
      end
    end
  end
end

function Game3:mauvilleGymSpecial3()
  local switches = Game3.MAUVILLE_GYM_SWITCHES
  for i = 1, #switches do
    self:mapGridSetMetatileId(switches[i][1], switches[i][2],
      Game3.MT_MAUVILLE_PRESSED)
  end
  local off = Game3.MAUVILLE_GYM_OFF
  for y = 12, 23 do
    for x = 7, 15 do
      local to = off[self:mapGridGetMetatileId(x, y)]
      if to then self:mapGridSetMetatileId(x, y, to) end
    end
  end
end

function Game3:drawWholeMapView()
  -- field_camera.c copies the grid into BG VRAM. We already draw from
  -- map.grid every frame.
end

function Game3:storePlayerCoordsInVars()
  self:setScriptVar(0x8004, self.playerX or 0)
  self:setScriptVar(0x8005, self.playerY or 0)
end

function Game3:setPetalburgGymDoorTiles(room, metatile)
  room = tonumber(room) or 0
  metatile = tonumber(metatile) or Game3.MT_PETALBURG_DOOR_OPEN
  local doors = Game3.PETALBURG_GYM_DOORS[room]
  if not doors then return end
  local coll = Game3.MAPGRID_COLLISION_MASK
  for i = 1, #doors do
    local x, y = doors[i][1], doors[i][2]
    self:mapGridSetMetatileId(x + Game3.MAP_OFFSET, y + Game3.MAP_OFFSET,
      metatile + coll)
    self:mapGridSetMetatileId(x + Game3.MAP_OFFSET, y + Game3.MAP_OFFSET + 1,
      metatile + 8 + coll)
  end
end

function Game3:petalburgGymOpenDoors()
  self:setPetalburgGymDoorTiles(self:varGet(0x8004), Game3.MT_PETALBURG_DOOR_OPEN)
end

function Game3:setTrickHouseEndRoomFlag(on)
  self:setScriptVar(0x8004, Game3.FLAG_TRICK_HOUSE_END_ROOM)
  self.flags = self.flags or {}
  if on then
    self.flags[Game3.FLAG_TRICK_HOUSE_END_ROOM] = true
  else
    self.flags[Game3.FLAG_TRICK_HOUSE_END_ROOM] = nil
  end
end

function Game3:setHiddenItemFlag()
  local flag = tonumber(self:varGet(0x8004)) or 0
  self.flags = self.flags or {}
  if flag ~= 0 then self.flags[flag] = true end
end

function Game3:playerTrainerIdOnesDigit()
  return (self:ensureTrainerId() % 65536) % 10
end

function Game3:showFieldMessageStringVar4()
  local text = (self.stringVars and self.stringVars[4]) or ""
  if self._scriptSays then
    self:sayScript(text)
  elseif text ~= "" then
    self.field = { kind = "talk", text = text }
  end
end

function Game3:cableCarWarp()
  local down = (tonumber(self:varGet(0x8004)) or 0) ~= 0
  if down then
    self.cableCarDest = {
      group = Game3.MAP_INDOOR_ROUTE112_GROUP,
      num = Game3.MAP_ROUTE112_CABLE_CAR_NUM,
      x = 6, y = 4,
    }
  else
    self.cableCarDest = {
      group = Game3.MAP_INDOOR_ROUTE112_GROUP,
      num = Game3.MAP_MT_CHIMNEY_CABLE_CAR_NUM,
      x = 6, y = 4,
    }
  end
end

function Game3:cableCar()
  local d = self.cableCarDest
  self.cableCarDest = nil
  if not d then return end
  self:scriptWarp(d.group, d.num, Game3.WARP_ID_NONE, d.x, d.y)
end

function Game3:canRegisterItem(id)
  return self:itemPocket(id) == Game3.POCKET_KEY
end

function Game3:toggleRegisteredItem(id)
  id = tonumber(id) or 0
  if not self:canRegisterItem(id) then
    return false, "It can't be registered."
  end
  if (self.registeredItem or 0) == id then
    self.registeredItem = 0
    return true, "SELECT icon was removed."
  end
  self.registeredItem = id
  return true, "Registered to SELECT."
end

function Game3:useRegisteredItem()
  local id = tonumber(self.registeredItem) or 0
  if id < 1 or self:itemCount(id) < 1 then
    self.registeredItem = 0
    self.field = { kind = "talk", text = Game3.TEXT_NO_REGISTERED_ITEM }
    return true
  end
  local _, msg = self:useFieldItem(id)
  if type(msg) == "string" and msg ~= "" then
    self.field = { kind = "talk", text = msg }
  end
  return true
end

function Game3:rotatingGatePuzzleType()
  local map = self.map
  if not map then return 0 end
  local id = map.id
  if id == Game3.mapId(Game3.MAP_FORTREE_GYM_GROUP, Game3.MAP_FORTREE_GYM_NUM)
      or (map.group == Game3.MAP_FORTREE_GYM_GROUP
        and map.index == Game3.MAP_FORTREE_GYM_NUM) then
    return Game3.PUZZLE_FORTREE
  end
  if id == Game3.mapId(Game3.MAP_TRICK_HOUSE_PUZZLE6_GROUP,
        Game3.MAP_TRICK_HOUSE_PUZZLE6_NUM)
      or (map.group == Game3.MAP_TRICK_HOUSE_PUZZLE6_GROUP
        and map.index == Game3.MAP_TRICK_HOUSE_PUZZLE6_NUM) then
    return Game3.PUZZLE_TRICK_HOUSE_6
  end
  return 0
end

function Game3:rotatingGateConfig()
  local kind = self:rotatingGatePuzzleType()
  if kind == Game3.PUZZLE_FORTREE then return Game3.ROTATING_GATE_FORTREE end
  if kind == Game3.PUZZLE_TRICK_HOUSE_6 then
    return Game3.ROTATING_GATE_TRICK_HOUSE
  end
end

function Game3:rotatingGateLoadConfig()
  local cfg = self:rotatingGateConfig()
  self.rotatingGates = cfg
  if not cfg then
    self.rotatingGateOrients = nil
    return
  end
  if not self.rotatingGateOrients then self.rotatingGateOrients = {} end
end

function Game3:rotatingGateResetOrients()
  local cfg = self.rotatingGates
  if not cfg then return end
  local orients = {}
  for i = 1, #cfg do
    orients[i] = cfg[i][4] or 0
  end
  self.rotatingGateOrients = orients
end

function Game3:rotatingGateInitPuzzle()
  self:rotatingGateLoadConfig()
  self:rotatingGateResetOrients()
end

function Game3:rotatingGateInitGfx()
  self:rotatingGateLoadConfig()
  if self.rotatingGates and not self.rotatingGateOrients then
    self:rotatingGateResetOrients()
  end
end

function Game3:rotatingGateOrient(gateId)
  local orients = self.rotatingGateOrients
  if not orients then return 0 end
  return orients[gateId] or 0
end

function Game3:rotatingGateSetOrient(gateId, ori)
  self.rotatingGateOrients = self.rotatingGateOrients or {}
  self.rotatingGateOrients[gateId] = (tonumber(ori) or 0) % 4
end

function Game3:rotatingGateHasArm(gateId, arm, isLong)
  local cfg = self.rotatingGates
  local gate = cfg and cfg[gateId]
  if not gate then return false end
  local layout = Game3.ROTATING_GATE_ARMS[(gate[3] or 0) + 1]
  if not layout then return false end
  local face = ((tonumber(arm) or 0) - self:rotatingGateOrient(gateId) + 4) % 4
  local idx = face * 2 + (isLong and 1 or 0) + 1
  return layout[idx] == 1
end

function Game3:rotatingGateCanRotate(gateId, dir)
  local cfg = self.rotatingGateConfig
  local gate = cfg and cfg[gateId]
  if not gate then return false end
  local armPos
  if dir == Game3.ROTATE_ACW then
    armPos = Game3.ROTATING_GATE_ACW_POS
  elseif dir == Game3.ROTATE_CW then
    armPos = Game3.ROTATING_GATE_CW_POS
  else
    return false
  end
  local layout = Game3.ROTATING_GATE_ARMS[(gate[3] or 0) + 1]
  if not layout then return false end
  local gx = gate[1] + Game3.MAP_OFFSET
  local gy = gate[2] + Game3.MAP_OFFSET
  local orientation = self:rotatingGateOrient(gateId)
  for i = 0, 3 do
    for j = 0, 1 do
      if layout[i * 2 + j + 1] == 1 then
        local armIndex = 2 * ((orientation + i) % 4) + j
        local pos = armPos[armIndex + 1]
        if self:mapGridGetCollision(gx + pos[1], gy + pos[2]) == 1 then
          return false
        end
      end
    end
  end
  return true
end

function Game3:rotatingGateRotate(gateId, dir)
  local ori = self:rotatingGateOrient(gateId)
  if dir == Game3.ROTATE_ACW then
    if ori ~= 0 then
      ori = ori - 1
    else
      ori = Game3.GATE_ORIENTATION_270
    end
  else
    ori = (ori + 1) % 4
  end
  self:rotatingGateSetOrient(gateId, ori)
end

function Game3:rotatingGateRotationInfo(direction, cx, cy)
  if cx < 0 or cx > 3 or cy < 0 or cy > 3 then
    return Game3.GATE_ROT_NONE
  end
  local ptr
  if direction == Game3.DIR_NORTH then
    ptr = Game3.ROTATING_GATE_INFO_NORTH
  elseif direction == Game3.DIR_SOUTH then
    ptr = Game3.ROTATING_GATE_INFO_SOUTH
  elseif direction == Game3.DIR_WEST then
    ptr = Game3.ROTATING_GATE_INFO_WEST
  elseif direction == Game3.DIR_EAST then
    ptr = Game3.ROTATING_GATE_INFO_EAST
  else
    return Game3.GATE_ROT_NONE
  end
  return ptr[cy * 4 + cx + 1] or Game3.GATE_ROT_NONE
end

-- field_player_avatar.c: dest is MapGrid. Returns true when the step is
-- blocked (collision 8). A successful spin still lets the player through.
function Game3:checkRotatingGateCollision(x, y, direction)
  local cfg = self.rotatingGateConfig or self:rotatingGateConfig()
  if not cfg then return false end
  if not self.rotatingGateConfig then self.rotatingGateConfig = cfg end
  local gx = (tonumber(x) or 0) + Game3.MAP_OFFSET
  local gy = (tonumber(y) or 0) + Game3.MAP_OFFSET
  for i = 1, #cfg do
    local gateX = cfg[i][1] + Game3.MAP_OFFSET
    local gateY = cfg[i][2] + Game3.MAP_OFFSET
    if gateX - 2 <= gx and gx <= gateX + 1
        and gateY - 2 <= gy and gy <= gateY + 1 then
      local info = self:rotatingGateRotationInfo(
        direction, gx - gateX + 2, gy - gateY + 2)
      if info ~= Game3.GATE_ROT_NONE then
        local spin = math.floor(info / 16) % 16
        local armInfo = info % 16
        local arm = math.floor(armInfo / 2)
        local long = (armInfo % 2) == 1
        if self:rotatingGateHasArm(i, arm, long) then
          if self:rotatingGateCanRotate(i, spin) then
            self:rotatingGateRotate(i, spin)
            return false
          end
          return true
        end
      end
    end
  end
  return false
end

function Game3:drawRotatingGates()
  local cfg = self.rotatingGateConfig
  if not cfg or not love or not love.graphics then return end
  local G = love.graphics
  local t = Game3.TILE
  local deltas = Game3.ROTATING_GATE_ARM_DELTA
  for i = 1, #cfg do
    local gx, gy = cfg[i][1], cfg[i][2]
    G.setColor(0.42, 0.28, 0.14, 1)
    G.rectangle("fill", gx * t + 5, gy * t + 5, 6, 6)
    for arm = 0, 3 do
      for long = 0, 1 do
        if self:rotatingGateHasArm(i, arm, long) then
          local d = deltas[arm * 2 + long + 1]
          local px = (gx + d[1]) * t
          local py = (gy + d[2]) * t
          G.setColor(0.55, 0.38, 0.18, 1)
          if arm == 0 or arm == 2 then
            G.rectangle("fill", px + 5, py + 1, 6, t - 2)
          else
            G.rectangle("fill", px + 1, py + 5, t - 2, 6)
          end
        end
      end
    end
  end
  G.setColor(1, 1, 1, 1)
end

function Game3:hasEnoughMoneyFor()
  local need = tonumber(self:varGet(0x8005)) or 0
  if (self.money or 0) >= need then return 1 end
  return 0
end

function Game3:payMoneyFor()
  local need = tonumber(self:varGet(0x8005)) or 0
  local n = (self.money or 0) - need
  if n < 0 then n = 0 end
  self.money = n
end

function Game3:getPriceReduction()
  return false
end

function Game3:getSlotMachineId()
  local slot = tonumber(self:varGet(0x8004)) or 0
  local salt = Game3.SLOT_MACHINE_SALT[(slot % 12) + 1] or 0
  local pair = self.easyChatPairs and self.easyChatPairs[1]
  local extra = 0
  if type(pair) == "table" then
    extra = (tonumber(pair[1]) or 0) + (tonumber(pair[2]) or 0)
  end
  local v0 = extra + salt
  local table_ = Game3.SLOT_MACHINE_NORMAL
  if self:getPriceReduction(2) then
    table_ = Game3.SLOT_MACHINE_DISCOUNT
  end
  return table_[(v0 % 12) + 1] or 0
end

function Game3:openDoor(x, y)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i or type(map.grid) ~= "table" then return false end
  map.grid[i] = Game3.metatileOf(map.grid[i])
  return true
end

function Game3:closeDoor(x, y)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i or type(map.grid) ~= "table" then return false end
  map.grid[i] = Game3.metatileOf(map.grid[i]) + 1024
  return true
end

function Game3:lightExitDoors()
  local map = self.map
  if not map or Game3.isTruckMap(map) then return end
  if map.connections and #map.connections > 0 then return end
  local px, py = self.playerX or 0, self.playerY or 0
  local spots = {
    { px, py }, { px, py - 1 }, { px, py + 1 }, { px - 1, py }, { px + 1, py },
  }
  for i = 1, #spots do
    local w = Game3.warpAt(map, spots[i][1], spots[i][2])
    if w then self:openDoor(w.x, w.y) end
  end
end

function Game3:setStepCallback(id)
  id = tonumber(id) or 0
  if id == 0 then
    self.stepCallback = nil
  else
    self.stepCallback = id
    if id == Game3.STEP_CB_PACIFIDLOG then
      self:setPacifidlogPair(self.playerX, self.playerY, 2)
    end
  end
end

function Game3:npcByLocalId(localId)
  localId = tonumber(localId)
  local npcs = self:npcsFor(self.map)
  if not localId or not npcs then return nil end
  for i = 1, #npcs do
    if npcs[i] and npcs[i].localId == localId then return npcs[i] end
  end
end

function Game3:objectTemplate(localId)
  localId = tonumber(localId)
  local objects = self.map and self.map.objects
  if not localId or type(objects) ~= "table" then return nil end
  for i = 1, #objects do
    if objects[i] and objects[i].localId == localId then return objects[i] end
  end
end

function Game3:npcFromTemplate(o, i)
  i = i or 1
  local x = o.permX
  if x == nil then x = o.x end
  local y = o.permY
  if y == nil then y = o.y end
  local movementType = o.permMovementType or o.movementType or 0
  local npc = {
    x = x, y = y,
    fromX = x, fromY = y,
    homeX = x, homeY = y,
    facing = Game3.facingFromMovementType(movementType),
    graphicsId = self:resolveGraphicsId(o.graphicsId or 0),
    movementType = movementType,
    rangeX = o.rangeX or 0,
    rangeY = o.rangeY or 0,
    trainerType = o.trainerType or 0,
    trainerRange = o.trainerRange or 0,
    trainerId = o.trainerId,
    trainerName = o.trainerName,
    trainerClass = o.trainerClass,
    doubleBattle = o.doubleBattle,
    party = o.party,
    items = o.items,
    itemId = o.itemId,
    itemCount = o.itemCount,
    mart = o.mart,
    script = o.script,
    flagId = o.flagId,
    localId = o.localId,
    defeated = self:isNpcDefeated(o),
    cooldown = 0,
    wait = ((i * 37) % 90) / 60,
    placeT = 0,
    invisible = movementType == Game3.MOVEMENT_TYPE_INVISIBLE or nil,
  }
  self:applyBerryTreeSprite(npc)
  return npc
end

function Game3:hideObject(localId)
  self:setActorInvisible(self:scriptActor(localId), true)
  return true
end

function Game3:showObject(localId, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  if localId == Game3.LOCALID_PLAYER
      and mapGroup ~= nil and mapNum ~= nil then
    local dest = self:lookupMap(mapGroup, mapNum)
    if dest and dest ~= self.map then
      local x, y = self:objectGfxXY(dest, Game3.GFX_BRINEY_BOAT)
      if not x then
        local spawn = dest.spawn or {}
        x, y = spawn.x or 0, spawn.y or 0
      end
      self:scriptWarp(mapGroup, mapNum, Game3.WARP_ID_NONE, x, y)
    end
  end
  self:setActorInvisible(self:scriptActor(localId), false)
  return true
end

function Game3:removeObject(localId)
  localId = tonumber(localId) or 0
  if localId == Game3.LOCALID_PLAYER then
    self.invisible = true
    return true
  end
  local o = self:objectTemplate(localId)
  if o and o.flagId and o.flagId ~= 0 then
    self.flags = self.flags or {}
    self.flags[o.flagId] = true
  end
  local npc = self:npcByLocalId(localId)
  if npc then npc.hidden = true end
  return npc ~= nil or o ~= nil
end

function Game3:addObject(localId)
  localId = tonumber(localId) or 0
  if localId == Game3.LOCALID_PLAYER then
    self.invisible = nil
    return true
  end
  local o = self:objectTemplate(localId)
  if o and o.flagId and o.flagId ~= 0 then
    self.flags = self.flags or {}
    self.flags[o.flagId] = nil
  end
  local npc = self:npcByLocalId(localId)
  if npc then
    npc.hidden = nil
    self:applyBerryTreeSprite(npc)
    return true
  end
  if not o then return false end
  local map = self.map
  if not map then return false end
  if not self.npcByMap then self.npcByMap = {} end
  local list = self:npcsFor(map)
  if not list then
    list = {}
    self.npcByMap[map.id or map] = list
  end
  list[#list + 1] = self:npcFromTemplate(o, #list + 1)
  return true
end

-- pokeruby TrySpawnObjectEvent: a clear FLAG_HIDE_* brings the template
-- back at xyperm. removeobject only hides the sprite; StolenGoods then
-- clearflag FLAG_HIDE_DEVON_RUSTBORO without addobject, so the employee
-- at Devon Corp stayed invisible.
function Game3:trySpawnObject(localId)
  localId = tonumber(localId) or 0
  if localId < 1 then return false end
  local o = self:objectTemplate(localId)
  if not o then return false end
  local fid = o.flagId or 0
  if fid ~= 0 and self.flags and self.flags[fid] then return false end
  local npc = self:npcByLocalId(localId)
  if npc then
    if npc.hidden then
      npc.hidden = nil
      local x = o.permX
      if x == nil then x = npc.homeX or o.x end
      local y = o.permY
      if y == nil then y = npc.homeY or o.y end
      npc.x, npc.y = x, y
      npc.fromX, npc.fromY = x, y
      npc.homeX, npc.homeY = x, y
      npc.graphicsId = self:resolveGraphicsId(o.graphicsId or npc.graphicsId or 0)
      self:applyBerryTreeSprite(npc)
    end
    return true
  end
  return self:addObject(localId)
end

function Game3:trySpawnByFlag(flag)
  flag = tonumber(flag)
  if not flag or flag == 0 then return false end
  local objects = self.map and self.map.objects
  if type(objects) ~= "table" then return false end
  local spawned = false
  for i = 1, #objects do
    local o = objects[i]
    if o and o.flagId == flag and o.localId then
      if self:trySpawnObject(o.localId) then spawned = true end
    end
  end
  return spawned
end

function Game3:setObjectXY(localId, x, y)
  local actor = self:scriptActor(localId)
  if actor == "player" then
    self.playerX, self.playerY = x, y
    self.walkFromX, self.walkFromY = x, y
    self.walkCooldown = 0
    self:clampCamera()
    return true
  elseif actor then
    actor.x, actor.y = x, y
    actor.fromX, actor.fromY = x, y
    actor.cooldown = 0
    return true
  end
  return false
end

function Game3:clearObjectPerms(map)
  local objects = map and map.objects
  if type(objects) ~= "table" then return end
  for i = 1, #objects do
    local o = objects[i]
    if o then
      o.permX, o.permY = nil, nil
      o.permMovementType = nil
    end
  end
end

function Game3:setObjectXYPerm(localId, x, y)
  x, y = tonumber(x) or 0, tonumber(y) or 0
  local o = self:objectTemplate(localId)
  if o then
    o.permX, o.permY = x, y
  end
  local npc = self:npcByLocalId(localId)
  if npc then
    npc.homeX, npc.homeY = x, y
  end
  return self:setObjectXY(localId, x, y) or o ~= nil
end

function Game3:setObjectMovementType(localId, movementType)
  movementType = tonumber(movementType) or 0
  local o = self:objectTemplate(localId)
  if o then o.permMovementType = movementType end
  local npc = self:npcByLocalId(localId)
  if npc then
    npc.movementType = movementType
    npc.facing = Game3.facingFromMovementType(movementType)
  end
  return o ~= nil or npc ~= nil
end

function Game3:mapMatches(mapGroup, mapNum)
  local map = self.map
  if not map then return false end
  local id = map.id
  if type(id) ~= "string" then return true end
  local g, n = id:match("^g(%d+)_(%d+)$")
  if not g then return true end
  return tonumber(g) == (tonumber(mapGroup) or 0)
      and tonumber(n) == (tonumber(mapNum) or 0)
end

function Game3:setObjectPriority(localId, priority, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  local sub = (tonumber(priority) or 0) + Game3.OBJECT_SUBPRIORITY_ADD
  if localId == Game3.LOCALID_PLAYER then
    self.fixedPriority = true
    self.objSubpriority = sub
    return true
  end
  if not self:mapMatches(mapGroup, mapNum) then return false end
  local actor = self:npcByLocalId(localId)
  if not actor then return false end
  actor.fixedPriority = true
  actor.objSubpriority = sub
  return true
end

function Game3:resetObjectPriority(localId, mapGroup, mapNum)
  localId = tonumber(localId) or 0
  if localId == Game3.LOCALID_PLAYER then
    self.fixedPriority = nil
    self.objSubpriority = nil
    return true
  end
  if not self:mapMatches(mapGroup, mapNum) then return false end
  local actor = self:npcByLocalId(localId)
  if not actor then return false end
  actor.fixedPriority = nil
  actor.objSubpriority = nil
  return true
end

function Game3:moveObjectOffscreen(localId)
  local npc = self:npcByLocalId(localId)
  if not npc then return false end
  local x, y = npc.x, npc.y
  npc.homeX, npc.homeY = x, y
  local o = self:objectTemplate(localId)
  if o then
    o.permX, o.permY = x, y
  end
  return true
end

function Game3:turnObject(localId, dir)
  local facing = Game3.DIR_FACING[tonumber(dir) or 0] or "south"
  local actor = self:scriptActor(localId)
  if actor == "player" then
    self.facing = facing
    return true
  elseif actor then
    actor.facing = facing
    return true
  end
  return false
end

function Game3:faceScriptNpc()
  local npc = self._scriptNpc
  if npc then self:faceActorAt(npc, self.playerX, self.playerY) end
  return true
end

function Game3:lockScriptNpcs(all)
  local function lockOne(npc)
    if npc and npc ~= "player" then
      npc.talkLock = true
      npc.facingLocked = true
    end
  end
  if all then
    local npcs = self:npcsFor(self.map)
    if npcs then
      for i = 1, #npcs do lockOne(npcs[i]) end
    end
  else
    lockOne(self._scriptNpc)
  end
  return true
end

function Game3:unlockScriptNpcs()
  local npcs = self:npcsFor(self.map)
  if not npcs then return true end
  for i = 1, #npcs do
    local n = npcs[i]
    if n and n.talkLock then
      n.talkLock = nil
      n.facingLocked = nil
    end
  end
  return true
end

function Game3:scriptActor(localId)
  localId = tonumber(localId) or 0
  if localId == Game3.LOCALID_PLAYER then return "player" end
  return self:npcByLocalId(localId)
end

function Game3:actorBusy(actor)
  if actor == "player" then return (self.walkCooldown or 0) > 0 end
  return actor and (actor.cooldown or 0) > 0
end

function Game3:tickActorCooldown(actor, dt)
  if actor == "player" then
    if (self.walkCooldown or 0) > 0 then
      self.walkCooldown = self.walkCooldown - dt
      if self.walkCooldown <= 0 then
        self.walkCooldown = 0
        self.hopping = nil
        self.emote = nil
      end
    end
  elseif actor and (actor.cooldown or 0) > 0 then
    actor.cooldown = actor.cooldown - dt
    if actor.cooldown <= 0 then
      actor.cooldown = 0
      actor.emote = nil
    end
  end
end

function Game3:holdActor(actor, seconds)
  seconds = seconds or 0
  if seconds < 0 then seconds = 0 end
  if actor == "player" then
    self.walkFromX, self.walkFromY = self.playerX, self.playerY
    self.walkDuration = seconds
    self.walkCooldown = seconds
  elseif actor then
    actor.fromX, actor.fromY = actor.x, actor.y
    actor.walkDuration = seconds
    actor.cooldown = seconds
  end
end

function Game3:setActorInvisible(actor, hidden)
  if actor == "player" then
    self.invisible = hidden and true or nil
  elseif actor then
    actor.invisible = hidden and true or nil
  end
end

function Game3:actorFacingLocked(actor)
  if actor == "player" then return self.facingLocked end
  return actor and actor.facingLocked
end

function Game3:setActorFacing(actor, dir)
  if not dir then return end
  if self:actorFacingLocked(actor) then return end
  if actor == "player" then
    self.facing = dir
  elseif actor then
    actor.facing = dir
  end
end

function Game3:setActorFacingLocked(actor, locked)
  if actor == "player" then
    self.facingLocked = locked and true or nil
  elseif actor then
    actor.facingLocked = locked and true or nil
  end
end

function Game3:setActorLockAnim(actor, locked)
  if actor == "player" then
    self.lockAnim = locked and true or nil
  elseif actor then
    actor.lockAnim = locked and true or nil
  end
  self:setActorFacingLocked(actor, locked)
end

function Game3:setActorFlag(actor, key, on)
  if type(key) ~= "string" or key == "" then return end
  local val = on and true or nil
  if actor == "player" then
    self[key] = val
  elseif actor then
    actor[key] = val
  end
end

function Game3:scriptEmote(actor, emote)
  if actor == "player" then
    self.emote = emote
  elseif actor then
    actor.emote = emote
  end
  self:holdActor(actor, Game3.EMOTE_PERIOD)
end

function Game3:faceActorAt(actor, tx, ty)
  local x, y
  if actor == "player" then
    x, y = self.playerX, self.playerY
  elseif actor then
    x, y = actor.x, actor.y
  else
    return
  end
  local dx, dy = (tx or 0) - (x or 0), (ty or 0) - (y or 0)
  if dx == 0 and dy == 0 then return end
  local dir
  if math.abs(dx) > math.abs(dy) then
    dir = dx > 0 and "east" or "west"
  else
    dir = dy > 0 and "south" or "north"
  end
  if actor == "player" then
    self.facing = dir
  else
    actor.facing = dir
  end
end

function Game3:faceActorAwayFrom(actor, tx, ty)
  self:faceActorAt(actor, tx, ty)
  if actor == "player" then
    self.facing = Game3.oppositeFacing(self.facing)
  elseif actor then
    actor.facing = Game3.oppositeFacing(actor.facing)
  end
end

function Game3:faceActorOriginal(actor)
  local mt = 0
  if actor and actor ~= "player" then mt = actor.movementType or 0 end
  self:setActorFacing(actor, Game3.facingFromMovementType(mt))
end

function Game3:scriptMoveDelta(actor, dx, dy, tiles, animated, period)
  tiles = tiles or 1
  dx, dy = dx or 0, dy or 0
  period = period or Game3.WALK_PERIOD
  local fromX, fromY
  if actor == "player" then
    fromX, fromY = self.playerX, self.playerY
  elseif actor then
    fromX, fromY = actor.x, actor.y
  else
    return
  end
  local x, y = fromX, fromY
  for _ = 1, tiles do
    x, y = x + dx, y + dy
  end
  if actor == "player" then
    if animated then
      self.walkFromX, self.walkFromY = fromX, fromY
      self.walkDuration = period
      self.walkCooldown = period
    else
      self.walkFromX, self.walkFromY = x, y
      self.walkCooldown = 0
    end
    self.playerX, self.playerY = x, y
  else
    if animated then
      actor.fromX, actor.fromY = fromX, fromY
      actor.walkDuration = period
      actor.cooldown = period
    else
      actor.fromX, actor.fromY = x, y
      actor.cooldown = 0
    end
    actor.x, actor.y = x, y
  end
end

function Game3:scriptMoveActor(actor, dir, tiles, animated, period)
  local dx, dy = Game3.deltaFromFacing(dir)
  self:scriptMoveDelta(actor, dx, dy, tiles, animated, period)
end

function Game3:setActorLevitate(actor, px)
  if actor == "player" then
    self.levitate = px
  elseif actor then
    actor.levitate = px
  end
  self:holdActor(actor, Game3.WALK_PERIOD)
end

function Game3:playScriptStep(actor, step)
  if not (actor and step) then return end
  local kind = step.kind
  if kind == "delay" then
    if not self.invisible then
      self:holdActor(actor, (step.frames or 1) / 60)
    end
    return
  end
  if kind == "emote" then
    self:scriptEmote(actor, step.emote)
    return
  end
  if kind == "walkplace" then
    self:setActorFacing(actor, step.dir)
    self:holdActor(actor, Game3.scriptStepPeriod(step))
    return
  end
  if kind == "invisible" then
    self:setActorInvisible(actor, true)
    return
  end
  if kind == "visible" then
    self:setActorInvisible(actor, false)
    return
  end
  if kind == "faceplayer" then
    self:faceActorAt(actor, self.playerX, self.playerY)
    return
  end
  if kind == "faceaway" then
    self:faceActorAwayFrom(actor, self.playerX, self.playerY)
    return
  end
  if kind == "faceoriginal" then
    self:faceActorOriginal(actor)
    return
  end
  if kind == "lockface" then
    self:setActorFacingLocked(actor, true)
    return
  end
  if kind == "unlockface" then
    self:setActorFacingLocked(actor, false)
    return
  end
  if kind == "bow" then
    if actor == "player" then
      self.facing = "south"
    elseif actor then
      actor.facing = "south"
    end
    self:holdActor(actor, Game3.EMOTE_PERIOD)
    return
  end
  if kind == "reveal" then
    self:setActorInvisible(actor, false)
    if actor ~= "player" then actor.revealed = true end
    self:holdActor(actor, Game3.WALK_PERIOD)
    return
  end
  if kind == "smash" or kind == "cut" then
    self:setActorInvisible(actor, true)
    self:holdActor(actor, Game3.SMASH_PERIOD)
    return
  end
  if kind == "lockanim" then
    self:setActorLockAnim(actor, true)
    return
  end
  if kind == "unlockanim" then
    self:setActorLockAnim(actor, false)
    return
  end
  if kind == "place" then
    self:holdActor(actor, Game3.WALK_PERIOD)
    return
  end
  if kind == "flag" then
    self:setActorFlag(actor, step.key, step.on)
    return
  end
  if kind == "levitate" then
    self:setActorLevitate(actor, Game3.LEVITATE_PX)
    return
  end
  if kind == "land" or kind == "flydown" then
    self:setActorLevitate(actor, 0)
    return
  end
  if kind == "flyup" then
    self:setActorLevitate(actor, Game3.FLY_PX)
    return
  end
  if not step.dir and not step.dx then return end
  local prevX, prevY
  if actor == "player" then
    self:setActorFacing(actor, step.dir)
    prevX, prevY = self.playerX, self.playerY
  else
    self:setActorFacing(actor, step.dir)
  end
  if kind == "walk" or kind == "jump" then
    local period = Game3.scriptStepPeriod(step)
    if step.dx then
      self:scriptMoveDelta(actor, step.dx, step.dy, 1, true, period)
    else
      self:scriptMoveActor(actor, step.dir, 1, true, period)
    end
    if actor == "player" then self:runStepCallback(prevX, prevY) end
  elseif kind == "jump2" then
    self:scriptMoveActor(actor, step.dir, 2, true, Game3.scriptStepPeriod(step))
    if actor == "player" then self:runStepCallback(prevX, prevY) end
  end
end

function Game3:expandMoveSteps(steps)
  local out = {}
  for i = 1, #(steps or {}) do
    local step = steps[i]
    if step and step.kind == "jump2" then
      out[#out + 1] = { kind = "walk", dir = step.dir }
      out[#out + 1] = { kind = "walk", dir = step.dir }
    elseif step then
      out[#out + 1] = step
    end
  end
  return out
end

function Game3:scriptMoving()
  if (self.walkCooldown or 0) > 0 then return true end
  local jobs = self.moveJobs
  if type(jobs) == "table" and #jobs > 0 then return true end
  return false
end

function Game3:startScriptDelay(frames)
  self.delayLeft = (tonumber(frames) or 0) / 60
end

function Game3:scriptDelaying()
  return (self.delayLeft or 0) > 0
end

function Game3:beginScriptWait()
  self.scriptWait = true
end

function Game3:scriptWaiting()
  return self.scriptWait and true or false
end

function Game3:endScriptWait()
  self.scriptWait = nil
  if self._scriptPause then
    return self:resumeMoveScript()
  end
  return false
end

function Game3:pumpScriptMove()
  local jobs = self.moveJobs
  if type(jobs) ~= "table" then return end
  local i = 1
  while i <= #jobs do
    local job = jobs[i]
    local actor = self:scriptActor(job.localId)
    if not actor then
      table.remove(jobs, i)
    elseif self:actorBusy(actor) then
      i = i + 1
    else
      local step = job.steps[job.i]
      if not step then
        table.remove(jobs, i)
      else
        job.i = job.i + 1
        self:playScriptStep(actor, step)
        if self:actorBusy(actor) then
          i = i + 1
        end
      end
    end
  end
  if self:scriptActor(Game3.LOCALID_PLAYER) then self:clampCamera() end
end

function Game3:stepScriptMove(dt)
  dt = dt or 0
  self:tickActorCooldown("player", dt)
  local jobs = self.moveJobs or {}
  for i = 1, #jobs do
    local actor = self:scriptActor(jobs[i].localId)
    if actor and actor ~= "player" then self:tickActorCooldown(actor, dt) end
  end
  self:pumpScriptMove()
end

function Game3:finishScriptMoves()
  local n = 0
  while self:scriptMoving() and n < 1024 do
    self:stepScriptMove(Game3.WALK_PERIOD)
    n = n + 1
  end
end

function Game3:applyMovement(localId, steps)
  localId = tonumber(localId) or 0
  local actor = self:scriptActor(localId)
  if not actor then return false end
  local expanded = self:expandMoveSteps(steps)
  self.moveJobs = self.moveJobs or {}
  local jobs = self.moveJobs
  for i = #jobs, 1, -1 do
    if jobs[i].localId == localId then table.remove(jobs, i) end
  end
  jobs[#jobs + 1] = { localId = localId, steps = expanded, i = 1 }
  self:pumpScriptMove()
  return true
end

function Game3:resumeMoveScript()
  local pause = self._scriptPause
  if type(pause) ~= "table" or type(pause.ops) ~= "table" then
    self.field = nil
    self:endScriptRun()
    return false
  end
  local fromMsg = self.field and self.field.thenContinue
  local jobs = self.moveJobs
  local hasJobs = type(jobs) == "table" and #jobs > 0
  if fromMsg then
    if hasJobs or self:scriptDelaying() or self:scriptWaiting() then
      return true
    end
  else
    if self:scriptMoving() then return true end
    if self:scriptDelaying() then return true end
    if self:scriptWaiting() then return true end
  end
  self._scriptPause = nil
  self._scriptSays = {}
  local _, again = self:continueScript(pause.ops, pause.at)
  return self:presentScript(again)
end

function Game3:fallDownHole()
  local x, y = self.playerX or 0, self.playerY or 0
  local h = self.holeWarp
  if h and self:lookupMap(h.mapGroup, h.mapNum) then
    self.walkCooldown = 0
    self.moveJobs = {}
    self:scriptWarp(h.mapGroup, h.mapNum, Game3.WARP_ID_NONE, x, y)
    self.field = { kind = "talk", text = "You fell through!" }
    return true
  end
  local map = self.map
  if map and map.group == Game3.GRANITE_CAVE_GROUP
      and map.index == Game3.GRANITE_CAVE_B1F_NUM
      and self:lookupMap(Game3.GRANITE_CAVE_GROUP, Game3.GRANITE_CAVE_B2F_NUM) then
    self.walkCooldown = 0
    self.moveJobs = {}
    self:scriptWarp(Game3.GRANITE_CAVE_GROUP, Game3.GRANITE_CAVE_B2F_NUM,
      Game3.WARP_ID_NONE, x, y)
    self.field = { kind = "talk", text = "You fell through!" }
    return true
  end
  local spawn = map and map.spawn or {}
  self.playerX = spawn.x or 0
  self.playerY = spawn.y or 0
  self.walkFromX, self.walkFromY = self.playerX, self.playerY
  self.walkCooldown = 0
  self.moveJobs = {}
  self.field = { kind = "talk", text = "You fell through!" }
  return true
end

function Game3:writeMetatile(x, y, mid)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i or type(map.grid) ~= "table" then return false end
  local cell = map.grid[i] or 0
  map.grid[i] = (tonumber(mid) or 0) % 1024 + Game3.collisionOf(cell) * 1024
  return true
end

function Game3:crackTileAt(x, y)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i or type(map.grid) ~= "table" then return false end
  return self:writeMetatile(x, y, Game3.metatileOf(map.grid[i]) + 1)
end

function Game3:behaviorOf(mid)
  local map = self.map
  local spec = map and self.data.tilesets and self.data.tilesets.byId
    and self.data.tilesets.byId[map.tileset]
  local behavior = spec and spec.behavior
  if type(behavior) ~= "table" then return 0 end
  return behavior[mid] or 0
end

function Game3:clearAshAt(x, y)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i then return false end
  local mid = Game3.metatileOf(map.grid[i])
  local dest = Game3.ASH_CLEAR[mid] or (mid + 1)
  self:writeMetatile(x, y, dest)
  if self:itemCount(Game3.ITEM_SOOT_SACK) > 0 then
    self.scriptVars = self.scriptVars or {}
    local n = (self.scriptVars[Game3.VAR_ASH_GATHER_COUNT] or 0) + 1
    if n > 9999 then n = 9999 end
    self.scriptVars[Game3.VAR_ASH_GATHER_COUNT] = n
  end
  return true
end

function Game3:shiftFortreeAt(x, y, delta)
  if self:behaviorAt(self.map, x, y) ~= Game3.MB_FORTREE_BRIDGE then return false end
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i then return false end
  local mid = Game3.metatileOf(map.grid[i])
  local dest = mid + delta
  if self:behaviorOf(dest) ~= Game3.MB_FORTREE_BRIDGE then return false end
  return self:writeMetatile(x, y, dest)
end

function Game3.pacifidlogPartner(behavior)
  if behavior == Game3.MB_PACIFIDLOG_VERTICAL_LOG_1 then return 0, 1 end
  if behavior == Game3.MB_PACIFIDLOG_VERTICAL_LOG_2 then return 0, -1 end
  if behavior == Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_1 then return 1, 0 end
  if behavior == Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_2 then return -1, 0 end
end

function Game3.isPacifidlogLog(behavior)
  return Game3.pacifidlogPartner(behavior) ~= nil
end

function Game3:setPacifidlogTile(x, y, state)
  local map = self.map
  local i = self:gridIndex(map, x, y)
  if not i then return false end
  local mid = Game3.metatileOf(map.grid[i])
  local row = Game3.PACIFIDLOG_STAGE[mid]
  if row then
    return self:writeMetatile(x, y, row[state + 1] or row[1])
  end
  return self:writeMetatile(x, y, mid - (mid % 3) + state)
end

function Game3:setPacifidlogPair(x, y, state)
  local b = self:behaviorAt(self.map, x, y)
  local dx, dy = Game3.pacifidlogPartner(b)
  if dx == nil then return false end
  self:setPacifidlogTile(x, y, state)
  self:setPacifidlogTile(x + dx, y + dy, state)
  return true
end

function Game3:runStepCallback(prevX, prevY)
  local id = self.stepCallback
  if not id then return false end
  local x, y = self.playerX, self.playerY
  local b = self:behaviorAt(self.map, x, y)
  local moved = prevX ~= nil and (prevX ~= x or prevY ~= y)
  if id == Game3.STEP_CB_ASH then
    if b == Game3.MB_ASHGRASS then return self:clearAshAt(x, y) end
  elseif id == Game3.STEP_CB_FORTREE then
    if moved then self:shiftFortreeAt(prevX, prevY, -1) end
    return self:shiftFortreeAt(x, y, 1)
  elseif id == Game3.STEP_CB_PACIFIDLOG then
    if moved and Game3.isPacifidlogLog(self:behaviorAt(self.map, prevX, prevY)) then
      self:setPacifidlogPair(prevX, prevY, 0)
    end
    if Game3.isPacifidlogLog(b) then return self:setPacifidlogPair(x, y, 2) end
  elseif id == Game3.STEP_CB_CRACKED_FLOOR then
    if b == Game3.MB_CRACKED_FLOOR_HOLE then return self:fallDownHole() end
    if b == Game3.MB_CRACKED_FLOOR then
      self:crackTileAt(x, y)
      -- pokeruby PerStepCallback: Mach Bike (speed 4) cracks the floor
      -- but does not fall; walking sets VAR_ICE_STEP_COUNT and drops.
      if self.bike == "mach" then return true end
      return self:fallDownHole()
    end
  elseif id == Game3.STEP_CB_ICE then
    if b == Game3.MB_CRACKED_ICE then return self:fallDownHole() end
    if b == Game3.MB_THIN_ICE then return self:crackTileAt(x, y) end
  end
  return false
end

function Game3:advance()
  if self.phase == "boot" then
    return self:beginNewGame()
  end
end

function Game3:moveScroll(delta)
  if self.phase ~= "roster" then return end
  local max = math.max(1, #self.named)
  self.scroll = ((self.scroll - 1 + delta) % max) + 1
end

local LAND_GRASS = {
  [0x02] = true, -- MB_TALL_GRASS
  [0x03] = true, -- MB_LONG_GRASS
  [0x07] = true, -- MB_SHORT_GRASS
  [0x24] = true, -- MB_ASHGRASS
}

-- pokeruby sTileBitAttributes: wildEncounter and not surfable.
-- MB_SHORT_GRASS 0x07 has no encounter bit; cave floors are 0x0B.
local LAND_WILD = {
  [0x02] = true, -- MB_TALL_GRASS
  [0x03] = true, -- MB_LONG_GRASS
  [0x05] = true, -- MB_UNUSED_05
  [0x06] = true, -- MB_UNUSED_DEEP_SAND
  [0x08] = true, -- MB_UNUSED_CAVE
  [0x0B] = true, -- MB_INDOOR_ENCOUNTER
  [0x24] = true, -- MB_ASHGRASS
  [0x25] = true, -- MB_FOOTPRINTS
}

local SURFABLE = {
  [0x10] = true, -- MB_POND_WATER
  [0x11] = true, -- MB_INTERIOR_DEEP_WATER
  [0x12] = true, -- MB_DEEP_WATER
  [0x13] = true, -- MB_WATERFALL
  [0x14] = true, -- MB_SOOTOPOLIS_DEEP_WATER
  [0x15] = true, -- MB_OCEAN_WATER
  [0x18] = true, -- MB_NO_SURFACING
  [0x22] = true, -- MB_SEAWEED
  [0x28] = true, -- MB_SEAWEED_NO_SURFACING
}

function Game3.isLandGrass(behavior)
  return LAND_GRASS[behavior or 0] == true
end

function Game3.isLandWildEncounter(behavior)
  return LAND_WILD[behavior or 0] == true
end

-- pokeruby BattleSetup_GetEnvironmentId.
function Game3:battleEnvironment()
  local b = 0
  local map = self.map
  if map then
    b = self:behaviorAt(map, self.playerX or 0, self.playerY or 0) or 0
  end
  if b == 0x02 then return Game3.BATTLE_ENV_GRASS end
  if b == 0x03 then return Game3.BATTLE_ENV_LONG_GRASS end
  if b == 0x21 or b == 0x06 then return Game3.BATTLE_ENV_SAND end
  local t = map and (map.mapType or 0) or 0
  if t == Game3.MAP_TYPE_UNDERGROUND then
    if b == 0x0B then return Game3.BATTLE_ENV_BUILDING end
    if Game3.isSurfable(b) then return Game3.BATTLE_ENV_POND end
    return Game3.BATTLE_ENV_CAVE
  end
  if t == Game3.MAP_TYPE_INDOOR or t == Game3.MAP_TYPE_SECRET_BASE then
    return Game3.BATTLE_ENV_BUILDING
  end
  if t == Game3.MAP_TYPE_UNDERWATER then return Game3.BATTLE_ENV_UNDERWATER end
  if t == Game3.MAP_TYPE_OCEAN_ROUTE then
    if Game3.isSurfable(b) then return Game3.BATTLE_ENV_WATER end
    return Game3.BATTLE_ENV_PLAIN
  end
  if b == 0x15 or b == 0x11 or b == 0x12 then
    return Game3.BATTLE_ENV_WATER
  end
  if Game3.isSurfable(b) then return Game3.BATTLE_ENV_POND end
  if b == 0x0C then return Game3.BATTLE_ENV_MOUNTAIN end
  if self.surfing then return Game3.BATTLE_ENV_WATER end
  return Game3.BATTLE_ENV_PLAIN
end

function Game3.isWaterfall(behavior)
  return (behavior or 0) == Game3.MB_WATERFALL
end

function Game3.isSurfable(behavior)
  return SURFABLE[behavior or 0] == true
end

function Game3.isSurfStart(behavior)
  return Game3.isSurfable(behavior) and not Game3.isWaterfall(behavior)
end

function Game3.isDiveable(behavior)
  local b = behavior or 0
  return b == Game3.MB_DEEP_WATER or b == Game3.MB_SOOTOPOLIS_DEEP_WATER
end

function Game3.isUnableToEmerge(behavior)
  local b = behavior or 0
  return b == Game3.MB_NO_SURFACING or b == Game3.MB_SEAWEED_NO_SURFACING
end

function Game3.isCounter(behavior)
  return (behavior or 0) == Game3.MB_COUNTER
end

function Game3.isPc(behavior)
  local b = behavior or 0
  return b == Game3.MB_PC
    or b == Game3.MB_PLAYER_ROOM_PC
    or b == Game3.MB_SECRET_BASE_PC
end

function Game3.topIsOverlay(layerType)
  return (layerType or 0) ~= Game3.LAYER_COVERED
end

-- GBA tile 0 on BG1 is blank. Our top atlas still has a quad there, so a
-- LAYER_NORMAL metatile whose top four tiles are 0 must not ride overlay.
function Game3:metatileTopEmpty(map, mid)
  local byId = self.data.tilesets and self.data.tilesets.byId
  local spec = byId and map and byId[map.tileset]
  local row = spec and spec.tiles and spec.tiles[mid]
  if type(row) ~= "table" then return false end
  return (row[5] or 0) == 0 and (row[6] or 0) == 0
    and (row[7] or 0) == 0 and (row[8] or 0) == 0
end

function Game3:topIsOverlayAt(map, x, y)
  if Game3.isLandGrass(self:behaviorAt(map, x, y)) then return false end
  if not Game3.topIsOverlay(self:layerTypeAt(map, x, y)) then return false end
  if not (map and map.grid) then return true end
  local mid = Game3.metatileOf(map.grid[(y or 0) * (map.width or 0) + (x or 0) + 1])
  if self:metatileTopEmpty(map, mid) then return false end
  return true
end

-- pokeruby METATILE_LAYER_TYPE_SPLIT: BG1's top 8px overlay sprites, the
-- bottom 8px sit on BG2 with the ground. Blitting the whole 16x16 overlay
-- buries a 16x32 OW sprite's head (tree trunks, Devon Corp door/sign).
function Game3.metatileTopPassMode(layerType, topPass, overlay)
  if not topPass then return "full" end
  if overlay and (layerType or 0) == Game3.LAYER_SPLIT then
    if topPass == "overlay" then return "top8" end
    return "bottom8"
  end
  if topPass == "overlay" then
    return overlay and "full" or "skip"
  end
  return overlay and "skip" or "full"
end

-- General-tileset VRAM slots that TilesetCB_General DMAs (water / flowers).
function Game3.isGeneralAnimTile(tid)
  tid = (tid or 0) % 1024
  return tid >= 108 and tid <= 137
end

-- Flowers are tiles 127-130 (0x80 bytes at BG_TILE_ADDR(127)). Water is
-- 108-137, but ledges and treetops reuse those numbers in other
-- tilesets — only flip water on surfable metatiles, flowers otherwise.
function Game3.isFlowerAnimTile(tid)
  tid = (tid or 0) % 1024
  return tid >= 127 and tid <= 130
end

-- Flower DMA is VRAM 127-130. Rock/cliff metatiles reuse those numbers
-- next to tiles 131+; flipping them makes mountain ledges shimmer.
function Game3.blocksFlowerAnim(tid)
  tid = (tid or 0) % 1024
  return tid > 130 and tid < 512
end

function Game3.shouldAnimCorner(tid, behavior, tiles, start)
  if not Game3.isGeneralAnimTile(tid) then return false end
  if Game3.ledgeDelta(behavior) then return false end
  if Game3.isSurfable(behavior) then return true end
  if not Game3.isFlowerAnimTile(tid) then return false end
  if type(tiles) == "table" then
    start = start or 1
    for i = 0, 3 do
      if Game3.blocksFlowerAnim(tiles[start + i]) then return false end
    end
  end
  return true
end

function Game3:tileAnimFlip()
  return math.floor((self.playSeconds or 0) * 4) % 2 == 1
end

function Game3.chooseLandSlot(roll100)
  local r = roll100 or 0
  if r < 20 then return 0 end
  if r < 40 then return 1 end
  if r < 50 then return 2 end
  if r < 60 then return 3 end
  if r < 70 then return 4 end
  if r < 80 then return 5 end
  if r < 85 then return 6 end
  if r < 90 then return 7 end
  if r < 94 then return 8 end
  if r < 98 then return 9 end
  if r < 99 then return 10 end
  return 11
end

function Game3.chooseWaterRockSlot(roll100)
  local r = roll100 or 0
  if r < 60 then return 0 end
  if r < 90 then return 1 end
  if r < 95 then return 2 end
  if r < 99 then return 3 end
  return 4
end

function Game3.chooseFishSlot(rod, roll100)
  local r = roll100 or 0
  rod = rod or 0
  if rod == Game3.GOOD_ROD then
    if r < 60 then return 2 end
    if r < 80 then return 3 end
    return 4
  end
  if rod == Game3.SUPER_ROD then
    if r < 40 then return 5 end
    if r < 80 then return 6 end
    if r < 95 then return 7 end
    if r < 99 then return 8 end
    return 9
  end
  if r < 70 then return 0 end
  return 1
end

function Game3.statHP(base, level, iv, ev)
  base = base or 1
  level = level or 1
  iv = iv or 0
  ev = math.floor((tonumber(ev) or 0) / 4)
  return math.floor(((2 * base + iv + ev) * level) / 100) + level + 10
end

function Game3.statOther(base, level, iv, natureTenths, ev)
  base = base or 1
  level = level or 1
  iv = iv or 0
  natureTenths = natureTenths or 10
  ev = math.floor((tonumber(ev) or 0) / 4)
  local n = math.floor(((2 * base + iv + ev) * level) / 100) + 5
  if natureTenths ~= 10 then
    n = math.floor(n * natureTenths / 10)
  end
  if n < 1 then n = 1 end
  return n
end

function Game3.natureIndex(pid)
  return (pid or 0) % 25
end

function Game3.natureName(pid)
  return Game3.NATURE_NAMES[Game3.natureIndex(pid)] or "HARDY"
end

-- stat is 0=Atk, 1=Def, 2=Spe, 3=SpA, 4=SpD.  Returns tenths (9/10/11).
function Game3.natureMul(pid, stat)
  local n = Game3.natureIndex(pid)
  local boost, drop = math.floor(n / 5), n % 5
  if boost == drop then return 10 end
  if stat == boost then return 11 end
  if stat == drop then return 9 end
  return 10
end

function Game3.zeroIvs()
  return { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
end

function Game3.copyIvs(ivs)
  ivs = ivs or {}
  return {
    hp = ivs.hp or 0,
    atk = ivs.atk or 0,
    def = ivs.def or 0,
    spe = ivs.spe or 0,
    spa = ivs.spa or 0,
    spd = ivs.spd or 0,
  }
end

-- pokeruby atkC1_hiddenpowercalc: bit 0 of each IV packed hp..spd.
function Game3.hiddenPowerTypeBits(ivs)
  ivs = ivs or {}
  local function b0(n) return (tonumber(n) or 0) % 2 end
  return b0(ivs.hp) + b0(ivs.atk) * 2 + b0(ivs.def) * 4
    + b0(ivs.spe) * 8 + b0(ivs.spa) * 16 + b0(ivs.spd) * 32
end

function Game3.hiddenPowerPowerBits(ivs)
  ivs = ivs or {}
  local function b1(n) return math.floor((tonumber(n) or 0) / 2) % 2 end
  return b1(ivs.hp) + b1(ivs.atk) * 2 + b1(ivs.def) * 4
    + b1(ivs.spe) * 8 + b1(ivs.spa) * 16 + b1(ivs.spd) * 32
end

function Game3.hiddenPowerType(ivs)
  local t = math.floor(Game3.hiddenPowerTypeBits(ivs) * 15 / 63) + 1
  if t >= Game3.TYPE_MYSTERY then t = t + 1 end
  return t
end

function Game3.hiddenPowerPower(ivs)
  return 30 + math.floor(Game3.hiddenPowerPowerBits(ivs) * 40 / 63)
end

function Game3:attackType(attacker, move)
  if (move and move.effect or 0) == Game3.EFFECT_HIDDEN_POWER then
    return Game3.hiddenPowerType(attacker and attacker.ivs)
  end
  return (move and move.type) or 0
end

-- pokeemerald gExperienceTables.  Level 1 is 0; Medium Slow is negative
-- below that so it is clamped.
function Game3.expAtLevel(growth, level)
  level = math.floor(level or 1)
  if level <= 1 then return 0 end
  if level > 100 then level = 100 end
  growth = growth or Game3.GROWTH_MEDIUM_SLOW
  local n, n2, n3 = level, level * level, level * level * level
  if growth == Game3.GROWTH_MEDIUM_FAST then return n3 end
  if growth == Game3.GROWTH_FAST then return math.floor(4 * n3 / 5) end
  if growth == Game3.GROWTH_SLOW then return math.floor(5 * n3 / 4) end
  if growth == Game3.GROWTH_MEDIUM_SLOW then
    return math.floor(6 * n3 / 5) - 15 * n2 + 100 * n - 140
  end
  if growth == Game3.GROWTH_ERRATIC then
    if n < 50 then return math.floor(n3 * (100 - n) / 50) end
    if n < 68 then return math.floor(n3 * (150 - n) / 100) end
    if n < 98 then
      return math.floor(n3 * math.floor((1911 - 10 * n) / 3) / 500)
    end
    return math.floor(n3 * (160 - n) / 100)
  end
  if growth == Game3.GROWTH_FLUCTUATING then
    local k
    if n < 15 then k = math.floor((n + 1) / 3) + 24
    elseif n < 36 then k = n + 14
    else k = math.floor(n / 2) + 32 end
    return math.floor(n3 * k / 50)
  end
  return n3
end

function Game3.expBarFill(mon)
  if not mon then return 0 end
  local growth = mon.growth or Game3.GROWTH_MEDIUM_SLOW
  local lv = mon.level or 1
  if lv >= 100 then return 1 end
  local at = Game3.expAtLevel(growth, lv)
  local nxt = Game3.expAtLevel(growth, lv + 1)
  local exp = mon.exp or at
  if nxt <= at then return 1 end
  local t = (exp - at) / (nxt - at)
  if t < 0 then return 0 end
  if t > 1 then return 1 end
  return t
end

function Game3.wildExp(yield, level, trainer)
  local a = math.max(1, math.floor((yield or 0) * (level or 1) / 7))
  if trainer then a = math.floor(a * 3 / 2) end
  return a
end

function Game3.damage(level, power, attack, defense, stab, typeMul)
  attack = math.max(1, attack or 1)
  defense = math.max(1, defense or 1)
  typeMul = typeMul or 10
  if typeMul <= 0 then return 0 end
  local base = math.floor(math.floor((2 * (level or 1) / 5 + 2)
    * (power or 1) * attack / defense) / 50) + 2
  if stab then base = math.floor(base * 3 / 2) end
  if typeMul ~= 10 then base = math.floor(base * typeMul / 10) end
  return math.max(1, base)
end

function Game3.stageMul(stage)
  stage = stage or 0
  if stage >= 0 then return (2 + stage) / 2 end
  return 2 / (2 - stage)
end

-- pokeruby gAccuracyStageRatios: indexes 0-12 are stages -6..+6.
Game3.ACC_STAGE_RATIOS = {
  { 33, 100 }, { 36, 100 }, { 43, 100 }, { 50, 100 }, { 60, 100 }, { 75, 100 },
  { 1, 1 },
  { 133, 100 }, { 166, 100 }, { 2, 1 }, { 233, 100 }, { 133, 50 }, { 3, 1 },
}

function Game3.accuracyFromStages(moveAcc, atkAcc, defEva)
  local buff = (tonumber(atkAcc) or 0) - (tonumber(defEva) or 0) + 6
  if buff < 0 then buff = 0 elseif buff > 12 then buff = 12 end
  local r = Game3.ACC_STAGE_RATIOS[buff + 1]
  return math.floor((tonumber(moveAcc) or 0) * r[1] / r[2])
end

function Game3.isPhysical(moveType)
  return (moveType or 0) < 9
end

function Game3.chartMul(chart, atkType, defType, identified)
  if type(chart) ~= "table" then return 10 end
  for i = 1, #chart do
    local row = chart[i]
    if row and row[1] == atkType and row[2] == defType then
      -- Rows after TYPE_FORESIGHT (0xFE): Normal/Fighting vs Ghost.
      if identified and defType == Game3.TYPE_GHOST
          and (atkType == 0 or atkType == Game3.TYPE_FIGHTING)
          and (row[3] or 0) == 0 then
        return 10
      end
      return row[3]
    end
  end
  return 10
end

function Game3.typeMul(chart, atkType, type1, type2, identified)
  local m = Game3.chartMul(chart, atkType, type1 or 0, identified)
  if type2 and type2 ~= type1 then
    m = math.floor(m * Game3.chartMul(chart, atkType, type2, identified) / 10)
  end
  return m
end

function Game3:speciesRow(id)
  local byIndex = self.data.pokemon and self.data.pokemon.byIndex
  if type(byIndex) ~= "table" then return nil end
  return byIndex[id]
end

function Game3:speciesName(id)
  local row = self:speciesRow(id)
  local name = row and row.name or ""
  if name == "" or name:match("^[?%-]+$") then
    return Game3.STARTER_NAMES[id] or ("POKeMON %d"):format(id or 0)
  end
  return name
end

function Game3.abilityFor(row, pid)
  local a1 = (row and row.ability1) or 0
  local a2 = (row and row.ability2) or 0
  if a2 ~= 0 and ((pid or 0) % 2 == 1) then return a2 end
  return a1
end

function Game3:setAbility(mon)
  if not mon then return end
  mon.ability = Game3.abilityFor(self:speciesRow(mon.species), mon.pid)
end

function Game3:hasAbility(mon, id)
  return mon and (mon.ability or 0) == id
end

function Game3.isContact(move)
  return ((move and move.flags) or 0) % 2 == Game3.FLAG_CONTACT
end

function Game3.abilityName(id)
  local names = {
    [7] = "LIMBER", [8] = "SAND VEIL", [2] = "DRIZZLE", [9] = "STATIC", [10] = "VOLT ABSORB",
    [11] = "WATER ABSORB", [13] = "CLOUD NINE", [14] = "COMPOUND EYES",
    [15] = "INSOMNIA",
    [17] = "IMMUNITY", [18] = "FLASH FIRE", [19] = "SHIELD DUST",
    [20] = "OWN TEMPO", [22] = "INTIMIDATE", [23] = "SHADOW TAG",
    [24] = "ROUGH SKIN",
    [25] = "WONDER GUARD", [26] = "LEVITATE", [28] = "SYNCHRONIZE",
    [29] = "CLEAR BODY", [30] = "NATURAL CURE", [31] = "LIGHTNINGROD",
    [32] = "SERENE GRACE", [33] = "SWIFT SWIM", [34] = "CHLOROPHYLL",
    [36] = "TRACE", [37] = "HUGE POWER", [38] = "POISON POINT",
    [39] = "INNER FOCUS", [40] = "MAGMA ARMOR", [41] = "WATER VEIL",
    [42] = "MAGNET PULL", [44] = "RAIN DISH", [45] = "SAND STREAM",
    [47] = "THICK FAT", [48] = "EARLY BIRD", [49] = "FLAME BODY",
    [50] = "RUN AWAY", [51] = "KEEN EYE", [52] = "HYPER CUTTER", [53] = "PICKUP", [54] = "TRUANT",
    [60] = "STICKY HOLD", [61] = "SHED SKIN", [62] = "GUTS",
    [63] = "MARVEL SCALE", [64] = "LIQUID OOZE", [65] = "OVERGROW",
    [66] = "BLAZE", [67] = "TORRENT", [68] = "SWARM", [69] = "ROCK HEAD",
    [70] = "DROUGHT", [71] = "ARENA TRAP", [72] = "VITAL SPIRIT", [73] = "WHITE SMOKE",
    [74] = "PURE POWER", [76] = "AIR LOCK",
  }
  return names[id] or ("ABILITY %d"):format(id or 0)
end

function Game3:rollIvs()
  return {
    hp = self:rand(32) - 1,
    atk = self:rand(32) - 1,
    def = self:rand(32) - 1,
    spe = self:rand(32) - 1,
    spa = self:rand(32) - 1,
    spd = self:rand(32) - 1,
  }
end

function Game3:makeMon(species, level, moveIds)
  level = level or 5
  local row = self:speciesRow(species) or {}
  local mon = {
    species = species or Game3.STARTER_SPECIES,
    name = self:speciesName(species),
    level = level,
    type1 = row.type1 or 0,
    type2 = row.type2 or row.type1 or 0,
    catchRate = row.catchRate or 45,
    expYield = row.expYield or 0,
    growth = row.growthRate or Game3.GROWTH_MEDIUM_SLOW,
    exp = Game3.expAtLevel(row.growthRate or Game3.GROWTH_MEDIUM_SLOW, level),
    pid = (self:rand(65536) - 1) + (self:rand(65536) - 1) * 65536,
    ivs = self:rollIvs(),
    stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
    moves = self:movesFor(species, level),
    friendship = tonumber(row.friendship) or Game3.BASE_FRIENDSHIP,
  }
  self:setAbility(mon)
  self:recalcStats(mon)
  mon.hp = mon.maxHp
  if type(moveIds) == "table" and #moveIds > 0 then
    mon.moves = {}
    for i = 1, math.min(4, #moveIds) do
      mon.moves[#mon.moves + 1] = self:copyMove(moveIds[i])
    end
  end
  return mon
end

function Game3:copyMove(id)
  local spec = self.data.moves and self.data.moves.byId and self.data.moves.byId[id]
  if spec then
    local acc = spec.accuracy
    if acc == nil then acc = 100 end
    return {
      id = spec.id or id,
      name = spec.name or ("MOVE %d"):format(id),
      effect = spec.effect or 0,
      power = spec.power or 0,
      type = spec.type or 0,
      accuracy = acc,
      pp = spec.pp or 20,
      maxPp = spec.pp or 20,
      priority = spec.priority or 0,
      secondary = spec.secondary or 0,
      flags = spec.flags or 0,
      target = spec.target or 0,
      contestCategory = spec.contestCategory,
      contestAppeal = spec.contestAppeal,
    }
  end
  return {
    id = id or 33, name = "TACKLE", effect = 0, power = 35, type = 0,
    accuracy = 95, pp = 35, maxPp = 35, priority = 0, secondary = 0, flags = 0,
    target = 0,
  }
end

function Game3:movesFor(species, level)
  level = level or 1
  local row = self:speciesRow(species)
  local learn = row and row.learnset or {}
  local ids = {}
  for i = 1, #learn do
    local e = learn[i]
    if e and (e.level or 1) <= level then
      if #ids >= 4 then table.remove(ids, 1) end
      ids[#ids + 1] = e.move
    end
  end
  local moves = {}
  for i = 1, #ids do
    moves[i] = self:copyMove(ids[i])
  end
  if #moves == 0 then moves[1] = self:copyMove(33) end
  return moves
end

function Game3:behaviorAt(map, x, y)
  map = map or self.map
  if not (map and map.grid) then return 0 end
  local w, h = map.width or 0, map.height or 0
  if x < 0 or y < 0 or x >= w or y >= h then return 0 end
  local i = y * w + x + 1
  if type(map.behavior) == "table" and map.behavior[i] ~= nil then
    return map.behavior[i]
  end
  local mid = Game3.metatileOf(map.grid[i])
  local spec = self.data.tilesets and self.data.tilesets.byId
    and self.data.tilesets.byId[map.tileset]
  local behavior = spec and spec.behavior
  if type(behavior) ~= "table" then return 0 end
  return behavior[mid] or 0
end

function Game3:layerTypeAt(map, x, y)
  map = map or self.map
  if not (map and map.grid) then return Game3.LAYER_NORMAL end
  local w, h = map.width or 0, map.height or 0
  if x < 0 or y < 0 or x >= w or y >= h then return Game3.LAYER_NORMAL end
  local mid = Game3.metatileOf(map.grid[y * w + x + 1])
  local spec = self.data.tilesets and self.data.tilesets.byId
    and self.data.tilesets.byId[map.tileset]
  local layerType = spec and spec.layerType
  if type(layerType) ~= "table" then return Game3.LAYER_NORMAL end
  return layerType[mid] or Game3.LAYER_NORMAL
end

function Game3:encountersFor(map)
  map = map or self.map
  local pack = self.data.encounters
  if not (map and pack and pack.byMap) then return nil end
  return pack.byMap[map.id]
end

function Game3:rand(n)
  n = n or 1
  if self.rng then return self.rng(n) end
  if love and love.math and love.math.random then
    return love.math.random(n)
  end
  return math.random(n)
end

-- pokeruby Random(): 16-bit 0..65535.
function Game3:gbaRandom()
  local v = (tonumber(self:rand(65536)) or 1) - 1
  if v < 0 then v = 0 end
  return math.floor(v) % 65536
end

function Game3:hasFishingMons(map)
  local enc = self:encountersFor(map)
  local fish = enc and enc.fish
  return fish ~= nil and type(fish.slots) == "table" and #fish.slots > 0
end

-- arr1[rod] + Random() % arr2[rod]
function Game3.fishMinRounds(rod, randomValue)
  rod = rod or 0
  local span = Game3.FISH_MIN_SPAN[rod] or 1
  return (Game3.FISH_MIN_BASE[rod] or 1) + ((randomValue or 0) % span)
end

function Game3:tryWildEncounter()
  local map = self.map
  if not map then return false end
  local enc = self:encountersFor(map)
  local info, picker
  local b = self:behaviorAt(map, self.playerX, self.playerY)
  if self.surfing and Game3.isSurfable(b) then
    info, picker = enc and enc.water, Game3.chooseWaterRockSlot
  elseif Game3.isLandWildEncounter(b) then
    info, picker = enc and enc.land, Game3.chooseLandSlot
  else
    return false
  end
  if not (info and info.slots and #info.slots > 0) then return false end
  local rate = info.rate or 0
  if (self:rand(2880) - 1) >= rate * 16 then return false end
  if not self:firstHealthy() then return false end
  return self:startWildFrom(info, picker(self:rand(100) - 1))
end

function Game3:startWildFrom(info, slotIndex, skipRepel)
  if not (info and info.slots) then return false end
  local slot = info.slots[(slotIndex or 0) + 1] or info.slots[1]
  if not slot or not slot.species then return false end
  local minL, maxL = slot.minLevel or 2, slot.maxLevel or slot.minLevel or 2
  if maxL < minL then maxL = minL end
  local level = minL
  if maxL > minL then level = minL + self:rand(maxL - minL + 1) - 1 end
  if not skipRepel and self:repelBlocks(level) then return false end
  return self:startWildBattle(slot.species, level)
end

function Game3:tryRockSmashEncounter()
  local enc = self:encountersFor(self.map)
  local rock = enc and enc.rock
  if not (rock and rock.slots and #rock.slots > 0) then return false end
  local rate = rock.rate or 0
  if (self:rand(2880) - 1) >= rate * 16 then return false end
  if not self:firstHealthy() then return false end
  return self:startWildFrom(rock, Game3.chooseWaterRockSlot(self:rand(100) - 1))
end

function Game3:trySweetScentEncounter()
  local map = self.map
  if not map then return false end
  local enc = self:encountersFor(map)
  local b = self:behaviorAt(map, self.playerX, self.playerY)
  local info, picker
  if Game3.isLandWildEncounter(b) then
    info, picker = enc and enc.land, Game3.chooseLandSlot
  elseif Game3.isSurfable(b) and not Game3.isWaterfall(b) then
    info, picker = enc and enc.water, Game3.chooseWaterRockSlot
  else
    return false
  end
  if not (info and info.slots and #info.slots > 0) then return false end
  if not self:firstHealthy() then return false end
  return self:startWildFrom(info, picker(self:rand(100) - 1), true)
end

function Game3:trainerLabel(npc)
  local class = (npc and npc.trainerClass) or "TRAINER"
  local name = (npc and npc.trainerName) or "TRAINER"
  if class == "" then class = "TRAINER" end
  if name == "" then name = "TRAINER" end
  return class .. " " .. name
end

function Game3:makeTrainerMon(slot)
  if type(slot) ~= "table" then return nil end
  local mon = self:makeMon(slot.species, slot.level, slot.moves)
  if not mon then return nil end
  local iv = tonumber(slot.iv)
  if iv ~= nil then
    local v = math.floor(iv * 31 / 255)
    mon.ivs = { hp = v, atk = v, def = v, spe = v, spa = v, spd = v }
    self:recalcStats(mon)
    mon.hp = mon.maxHp
  end
  return mon
end

function Game3.aliveMon(mon)
  return mon ~= nil and (mon.hp or 0) > 0
end

-- Living foes still to beat: the active battler(s) plus unsent party.
function Game3:trainerMonsLeft()
  local b = self.battle
  if not b then return 0 end
  local n = 0
  if Game3.aliveMon(b.enemy) then n = n + 1 end
  if Game3.aliveMon(b.enemy2) then n = n + 1 end
  local party = b.trainerParty or {}
  for i = (b.trainerIndex or 1) + 1, #party do n = n + 1 end
  return n
end

-- ShouldUseItem AI_ITEM_HEAL_HP / FULL_RESTORE.
function Game3:shouldUseHealItem(mon, itemId)
  local amount = self:healAmount(itemId)
  if not amount or not mon then return false end
  local hp, maxHp = mon.hp or 0, mon.maxHp or 1
  if hp == 0 then return false end
  if itemId == Game3.ITEM_FULL_RESTORE then
    return hp < math.floor(maxHp / 4)
  end
  return hp < math.floor(maxHp / 4) or (maxHp - hp) > amount
end

function Game3:takeTrainerHealItem(mon)
  local b = self.battle
  if not (b and b.isTrainer and mon) then return nil end
  local items = b.trainerItems
  if type(items) ~= "table" then return nil end
  local valid = self:trainerMonsLeft()
  local num = b.numItems or 0
  for i = 1, 4 do
    local item = items[i] or 0
    if item ~= 0 then
      local hold = i > 1 and valid > (num - (i - 1)) + 1
      if not hold and self:shouldUseHealItem(mon, item) then
        items[i] = 0
        return item
      end
    end
  end
end

function Game3:applyTrainerItem(mon, itemId)
  local amount = self:healAmount(itemId) or 0
  local heal = amount >= 999 and (mon.maxHp or amount) or amount
  mon.hp = math.min(mon.maxHp or heal, (mon.hp or 0) + heal)
  local label = self:trainerLabel(self.battle and self.battle.npc)
  local itemName = self:itemName(itemId)
  return {
    ("%s used %s!"):format(label, itemName),
    ("%s's %s restored health!"):format(mon.name, itemName),
  }
end

function Game3:queueEnemyAction(queue)
  local b = self.battle
  if not b or not Game3.aliveMon(b.enemy) then return end
  if b.player and (b.player.hp or 0) <= 0 then return end
  local item = self:takeTrainerHealItem(b.enemy)
  if item then
    local texts = self:applyTrainerItem(b.enemy, item)
    for i = 1, #texts do queue[#queue + 1] = texts[i] end
    return
  end
  local move = self:pickEnemyMove(b.enemy)
  local texts = self:useMove(b.enemy, b.player, move)
  for i = 1, #texts do queue[#queue + 1] = texts[i] end
end

function Game3:prepBattler(mon)
  if not mon then return nil end
  self:recalcStats(mon)
  mon.hp = math.min(mon.hp or mon.maxHp or 0, mon.maxHp or mon.hp or 0)
  mon.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  mon.focusEnergy = nil
  mon.mudSport = nil
  mon.waterSport = nil
  mon.rage = nil
  mon.leechSeed = nil
  mon.leechSeedSlot = nil
  mon.leechSeedFrom = nil
  mon.foresight = nil
  if type(mon.moves) ~= "table" or #mon.moves < 1 then
    mon.moves = self:movesFor(mon.species, mon.level)
  end
  return mon
end

function Game3:menuBattler()
  local b = self.battle
  if not b then return nil end
  if b.chooser == "player2" and Game3.aliveMon(b.player2) then
    return b.player2
  end
  if Game3.aliveMon(b.player) then return b.player end
  if Game3.aliveMon(b.player2) then return b.player2 end
  return b.player
end

function Game3:defaultTarget(attacker)
  local b = self.battle
  if not b or not attacker then return nil end
  local a1, a2, f1, f2 = b.player, b.player2, b.enemy, b.enemy2
  local primary, secondary
  if attacker == a1 or attacker == a2 then
    primary = attacker == a2 and f2 or f1
    secondary = attacker == a2 and f1 or f2
  else
    primary = attacker == f2 and a2 or a1
    secondary = attacker == f2 and a1 or a2
  end
  if Game3.aliveMon(primary) then return primary end
  if Game3.aliveMon(secondary) then return secondary end
end

function Game3.isSpreadTarget(target)
  target = target or 0
  return target == Game3.TARGET_BOTH or target == Game3.TARGET_FOES_AND_ALLY
end

function Game3:isPlayerSide(mon)
  local b = self.battle
  return b ~= nil and (mon == b.player or mon == b.player2)
end

function Game3:foesOf(mon)
  local b = self.battle
  if not b then return {} end
  if self:isPlayerSide(mon) then return { b.enemy, b.enemy2 } end
  return { b.player, b.player2 }
end

function Game3:allyOf(mon)
  local b = self.battle
  if not b then return nil end
  if mon == b.player then return b.player2 end
  if mon == b.player2 then return b.player end
  if mon == b.enemy then return b.enemy2 end
  if mon == b.enemy2 then return b.enemy end
end

function Game3:livingOf(list)
  local out = {}
  for i = 1, #(list or {}) do
    if Game3.aliveMon(list[i]) then out[#out + 1] = list[i] end
  end
  return out
end

function Game3:spreadTargets(attacker, move)
  local t = (move and move.target) or 0
  if t == Game3.TARGET_USER then return { attacker } end
  local foes = self:livingOf(self:foesOf(attacker))
  if t == Game3.TARGET_BOTH then return foes end
  if t == Game3.TARGET_FOES_AND_ALLY then
    local ally = self:allyOf(attacker)
    if Game3.aliveMon(ally) then foes[#foes + 1] = ally end
    return foes
  end
  return {}
end

function Game3:selectableTargets(attacker, move)
  local t = (move and move.target) or 0
  if t == Game3.TARGET_USER or Game3.isSpreadTarget(t) then return {} end
  return self:livingOf(self:foesOf(attacker))
end

function Game3:fillTrainerSlots()
  local b = self.battle
  if not b or not b.isTrainer then return {} end
  local party = b.trainerParty or {}
  local sent = {}
  local function fill(slot)
    if Game3.aliveMon(b[slot]) then return end
    local nextIdx = (b.trainerIndex or 1) + 1
    if nextIdx > #party then return end
    b.trainerIndex = nextIdx
    local mon = self:prepBattler(self:makeTrainerMon(party[nextIdx]))
    if mon then self:markSeen(mon.species) end
    b[slot] = mon
    sent[#sent + 1] = mon
  end
  fill("enemy")
  if b.doubles then fill("enemy2") end
  return sent
end

function Game3:canOfferShift()
  local opt = self.options or {}
  if opt.battleStyle == "set" then return false end
  local b = self.battle
  if not (b and b.isTrainer) then return false end
  local party = b.trainerParty or {}
  if (b.trainerIndex or 1) >= #party then return false end
  return self:firstHealthy(b.player, b.player2) ~= nil
end

function Game3:sendTrainerReplacement()
  local b = self.battle
  local sent = self:fillTrainerSlots()
  if #sent < 1 then return false end
  b.kind = "intro"
  b.switchInDone = false
  b.enterBoth = false
  b.queue = nil
  if #sent == 1 then
    b.text = ("%s sent out %s!"):format(
      self:trainerLabel(b.npc), sent[1].name)
  else
    b.text = ("%s sent out %s and %s!"):format(
      self:trainerLabel(b.npc), sent[1].name, sent[2].name)
  end
  return true
end

function Game3:emptyPlayerSlot()
  local b = self.battle
  if not b then return nil end
  if not Game3.aliveMon(b.player) then return "player" end
  if b.doubles and not Game3.aliveMon(b.player2) then return "player2" end
end

function Game3:afterFaintContinue()
  local b = self.battle
  local slot = self:emptyPlayerSlot()
  if slot then
    local mon, i = self:firstHealthy(b.player, b.player2)
    if mon then
      b.kind = "party"
      b.mustSwitch = true
      b.switchSlot = slot
      b.partyCursor = (i or 1) - 1
      b.text = nil
      return
    end
    if not Game3.aliveMon(b.player) and not Game3.aliveMon(b.player2) then
      b.kind = "blackout"
      b.text = "You scurried back to safety!"
      b.queue = nil
      return
    end
  end
  b.kind = "menu"
  b.text = nil
  self:tryWallyTutorialAction()
end

function Game3:trainerFlagId(id)
  id = tonumber(id) or 0
  if id < 1 then return nil end
  return Game3.TRAINER_FLAG_START + id
end

function Game3:trainerDefeated(id)
  local fid = self:trainerFlagId(id)
  return fid and self.flags and self.flags[fid] and true or false
end

function Game3:setTrainerDefeated(id)
  local fid = self:trainerFlagId(id)
  if not fid then return end
  self.flags = self.flags or {}
  self.flags[fid] = true
end

function Game3:isNpcDefeated(o)
  if not o then return false end
  if o.defeated then return true end
  if self:trainerDefeated(o.trainerId) then return true end
  local fid = o.flagId or 0
  if fid ~= 0 and self.flags and self.flags[fid] then return true end
  return false
end

function Game3:trainerRow(id)
  id = tonumber(id) or 0
  local pack = self.data and self.data.trainers
  return pack and pack.byId and pack.byId[id]
end

function Game3:markTrainerDefeated(npc)
  if not npc then return end
  npc.defeated = true
  if npc.trainerId then self:setTrainerDefeated(npc.trainerId) end
  if npc.flagId and npc.flagId ~= 0 then
    self.flags = self.flags or {}
    self.flags[npc.flagId] = true
  end
end

function Game3:trainerSeeInfo(npc, map)
  map = map or self.map
  if not (npc and map) then return end
  if npc.defeated or self:isNpcDefeated(npc) then return end
  if (npc.trainerType or 0) < 1 then return end
  local party = npc.party
  if type(party) ~= "table" or #party < 1 then return end
  local range = npc.trainerRange or 0
  if range < 1 then return end
  local px, py = self.playerX, self.playerY
  local dirs
  if npc.trainerType == Game3.TRAINER_TYPE_SEE_ALL then
    dirs = { "north", "south", "west", "east" }
  else
    dirs = { npc.facing or "south" }
  end
  for i = 1, #dirs do
    local dir = dirs[i]
    local dx, dy = Game3.deltaFromFacing(dir)
    for dist = 1, range do
      local x, y = npc.x + dx * dist, npc.y + dy * dist
      if x == px and y == py then
        local clear = true
        for s = 1, dist - 1 do
          local sx, sy = npc.x + dx * s, npc.y + dy * s
          if not Game3.walkable(map, sx, sy) then
            clear = false
            break
          end
          if self:npcAt(map, sx, sy) then
            clear = false
            break
          end
        end
        if clear then return dx, dy, dist, dir end
        break
      end
      if not Game3.walkable(map, x, y) then break end
      if self:npcAt(map, x, y) then break end
    end
  end
end

function Game3:seesPlayer(npc, map)
  return self:trainerSeeInfo(npc, map) ~= nil
end

function Game3:completeTrainerApproach(npc)
  npc = npc or (self.field and self.field.npc)
  self.moveJobs = {}
  self.field = nil
  if not npc then return false end
  if npc.script then
    self._scriptNpc = npc
    self:rememberTalk(npc)
    if self:runNpcScript(npc.script) then
      if self.phase == "battle" then return true end
    end
  end
  if npc.defeated or self:isNpcDefeated(npc) then return false end
  return self:startTrainerBattle(npc)
end

function Game3:stepTrainerApproach(dt)
  local f = self.field
  if not (f and f.kind == "trainer_approach") then return end
  local npc = f.npc
  dt = dt or 0
  if f.stage == "emote" then
    f.wait = (f.wait or 0) - dt
    if npc then self:tickActorCooldown(npc, dt) end
    if (f.wait or 0) > 0 then return end
    local dist = f.dist or 1
    local dir = f.dir or (npc and npc.facing) or "south"
    if npc then npc.facing = dir end
    if npc and npc.localId and dist > 1 then
      local steps = {}
      for _ = 1, dist - 1 do
        steps[#steps + 1] = { kind = "walk", dir = dir }
      end
      self:applyMovement(npc.localId, steps)
      f.stage = "walk"
    else
      f.stage = "trans"
      f.wait = 0.35
    end
  elseif f.stage == "walk" then
    self:stepScriptMove(dt)
    if not self:scriptMoving() then
      f.stage = "trans"
      f.wait = 0.35
    end
  elseif f.stage == "trans" then
    f.wait = (f.wait or 0) - dt
    if (f.wait or 0) <= 0 then
      self:completeTrainerApproach(npc)
    end
  end
end

function Game3:beginTrainerApproach(npc)
  local dx, dy, dist, dir = self:trainerSeeInfo(npc)
  if not dist then return false end
  if npc then npc.facing = dir end
  self.field = {
    kind = "trainer_approach",
    npc = npc,
    stage = "emote",
    wait = Game3.EMOTE_PERIOD,
    dx = dx, dy = dy, dist = dist, dir = dir,
  }
  if npc then self:scriptEmote(npc, "exclaim") end
  if not (npc and npc.localId) then
    return self:completeTrainerApproach(npc)
  end
  return true
end

function Game3:tryTrainerSpot()
  local map = self.map
  local npcs = self:npcsFor(map)
  if not npcs then return false end
  for i = 1, #npcs do
    local npc = npcs[i]
    if npc and self:seesPlayer(npc, map) then
      return self:beginTrainerApproach(npc)
    end
  end
  return false
end

function Game3:startTrainerBattle(npc)
  local party = npc and npc.party
  if type(party) ~= "table" or #party < 1 then return false end
  local player = self:firstHealthy()
  if not player then return false end
  local enemy = self:prepBattler(self:makeTrainerMon(party[1]))
  if not enemy then return false end
  local doubles = npc.doubleBattle and #party >= 2 and true or false
  local enemy2 = doubles and self:prepBattler(self:makeTrainerMon(party[2])) or nil
  if doubles and not enemy2 then doubles = false end
  local player2 = doubles and self:firstHealthy(player) or nil
  self:prepBattler(player)
  if player2 then self:prepBattler(player2) end
  self:markSeen(enemy.species)
  if enemy2 then self:markSeen(enemy2.species) end
  self.walkCooldown = 0
  self.field = nil
  self.phase = "battle"
  local packed, nItems = {}, 0
  local src = npc.items
  if type(src) ~= "table" or #src < 1 then
    local tr = self:trainerRow(npc.trainerId)
    src = tr and tr.items
  end
  if type(src) == "table" then
    for i = 1, 4 do
      local id = tonumber(src[i]) or 0
      packed[i] = id
      if id > 0 then nItems = nItems + 1 end
    end
  end
  self.battle = {
    kind = "intro",
    cursor = 0,
    fightCursor = 0,
    partyCursor = 0,
    isTrainer = true,
    doubles = doubles or nil,
    chooser = "player",
    npc = npc,
    trainerParty = party,
    trainerIndex = (doubles and enemy2) and 2 or 1,
    player = player,
    player2 = player2,
    enemy = enemy,
    enemy2 = enemy2,
    text = ("%s would like to battle!"):format(self:trainerLabel(npc)),
    enterBoth = true,
    switchInDone = false,
    turns = 0,
    introT = 0,
    animT = 0,
    trainerItems = packed,
    numItems = nItems,
  }
  self:markSentIn(player)
  self:markSentIn(player2)
  self:applyLeagueFriendship(npc)
  return true
end

function Game3:isDoubleTrainerKind(kind)
  kind = kind or 0
  return kind == Game3.TRAINER_BATTLE_DOUBLE
    or kind == Game3.TRAINER_BATTLE_CONTINUE_DOUBLE
    or kind == Game3.TRAINER_BATTLE_REMATCH_DOUBLE
    or kind == Game3.TRAINER_BATTLE_CONTINUE_DOUBLE_NO_MUSIC
end

-- pokeruby GetMonsStateToDoubles: one party slot is PLAYER_HAS_ONE_MON,
-- otherwise count non-egg HP>0. Gina & Mia need two usable mons.
function Game3:monsStateToDoubles()
  local party = self.party or {}
  if #party == 1 then return Game3.PLAYER_HAS_ONE_MON end
  local alive = 0
  for i = 1, #party do
    if self:canBattle(party[i]) then alive = alive + 1 end
  end
  if alive > 1 then return Game3.PLAYER_HAS_TWO_USABLE_MONS end
  return Game3.PLAYER_HAS_ONE_USABLE_MON
end

function Game3:scriptTrainerBattle(op)
  op = op or {}
  local npc = self._scriptNpc
  local id = tonumber(op.trainerId) or (npc and tonumber(npc.trainerId)) or 0
  if id > 0 and self:trainerDefeated(id) then return false end
  if npc and (npc.defeated or self:isNpcDefeated(npc)) then return false end
  local battler = npc or {}
  local party = battler.party
  if type(party) ~= "table" or #party < 1 then
    local tr = self:trainerRow(id)
    if not (tr and type(tr.party) == "table" and #tr.party > 0) then
      return false
    end
    battler = {
      party = tr.party,
      trainerName = tr.name,
      trainerClass = tr.className,
      doubleBattle = tr.doubleBattle,
      trainerId = id,
      items = tr.items,
    }
  else
    battler.trainerId = battler.trainerId or id
  end
  if self:isDoubleTrainerKind(op.kind) then
    battler.doubleBattle = true
    if self:monsStateToDoubles() ~= Game3.PLAYER_HAS_TWO_USABLE_MONS then
      return false, op.cannot or Game3.TEXT_NOT_ENOUGH_MONS
    end
  end
  if not self:startTrainerBattle(battler) then return false end
  if (op.kind or 0) == Game3.TRAINER_BATTLE_NO_INTRO then
    -- EventScript_DoNoIntroTrainerBattle: trainerbattlebegin, no intro
    -- speech and no "would like to battle" wait.
    self.battle.kind = "menu"
    self.battle.text = nil
    self.battle.introT = 1
  elseif op.intro then
    self.battle.text = self:expandScriptText(op.intro)
  end
  -- pokeruby GetTrainerLoseText / B_TXT_TRAINER1_LOSE_TEXT: the
  -- trainerbattle defeat pointer prints before "player defeated".
  self.battle.defeat = op.defeat and self:expandScriptText(op.defeat) or op.defeat
  return true
end

function Game3:trainerLoseText(npc)
  local b = self.battle
  local t = b and b.defeat
  if type(t) == "string" and t ~= "" then
    return self:expandScriptText(t)
  end
  npc = npc or (b and b.npc)
  local ops = npc and npc.script
  if type(ops) ~= "table" then return nil end
  for i = 1, #ops do
    local op = ops[i]
    if op and op.op == "trainerbattle" then
      t = op.defeat
      if type(t) == "string" and t ~= "" then
        return self:expandScriptText(t)
      end
    end
  end
end

function Game3:openTrainerVictory()
  local b = self.battle
  if not b then return end
  b.kind = "won_trainer"
  local pay = Game3.trainerPay(b)
  if pay > 0 then
    self.money = (self.money or 0) + pay
  end
  local prize
  if pay > 0 then
    prize = ("You defeated %s! Got $%d!"):format(
      self:trainerLabel(b.npc), pay)
  else
    prize = ("You defeated %s!"):format(self:trainerLabel(b.npc))
  end
  local lose = self:trainerLoseText(b.npc)
  if lose then
    b.text = lose
    b.queue = { lose, prize }
    b.qi = 1
  else
    b.text = prize
    b.queue = nil
  end
end

function Game3:confirmTrainerWin()
  local b = self.battle
  if not b then return end
  local queue = b.queue
  local qi = b.qi or 1
  if type(queue) == "table" and qi < #queue then
    b.qi = qi + 1
    b.text = queue[b.qi]
    b.textPage = 0
    b.printSrc = nil
    return
  end
  self:markTrainerDefeated(b.npc)
  if b.rivalRoute103 then self:finishRoute103Rival(b.npc) end
  self:finishBattle()
end

function Game3:canBattle(mon)
  return mon and not mon.isEgg and (mon.hp or 0) > 0
end

function Game3:firstHealthy(except, except2)
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon and mon ~= except and mon ~= except2 and self:canBattle(mon) then
      return mon, i
    end
  end
end

function Game3:healParty()
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon then
      mon.hp = mon.maxHp or mon.hp
      mon.status = nil
      mon.sleepTurns = nil
      mon.confuseTurns = nil
      mon.flinch = nil
      mon.flashFire = nil
      local moves = mon.moves or {}
      for m = 1, #moves do
        if moves[m] then moves[m].pp = moves[m].maxPp or moves[m].pp end
      end
    end
  end
end

function Game3:itemRow(id)
  local pack = self.data and self.data.items
  return pack and pack.byId and pack.byId[id]
end

function Game3.typeName(id)
  return Game3.TYPE_NAMES[id or 0] or "???"
end

function Game3:itemPocket(id)
  id = tonumber(id) or 0
  local row = self:itemRow(id)
  local pocket = row and tonumber(row.pocket)
  if pocket and pocket >= Game3.POCKET_ITEMS and pocket <= Game3.POCKET_KEY then
    return pocket
  end
  if Game3.isBall(id) then return Game3.POCKET_BALLS end
  if id >= Game3.ITEM_CHERI_BERRY and id <= Game3.ITEM_ENIGMA_BERRY then
    return Game3.POCKET_BERRIES
  end
  if id >= Game3.ITEM_TM01 and id <= Game3.ITEM_HM_DIVE then
    return Game3.POCKET_TMHM
  end
  if id == Game3.ITEM_MACH_BIKE or id == Game3.ITEM_ACRO_BIKE
      or id == Game3.ITEM_SOOT_SACK or id == Game3.ITEM_WAILMER_PAIL
      or id == Game3.ITEM_DEVON_GOODS or id == Game3.ITEM_LETTER
      or id == Game3.ITEM_ITEMFINDER
      or Game3.rodKind(id) ~= nil then
    return Game3.POCKET_KEY
  end
  return Game3.POCKET_ITEMS
end

function Game3:bagSlotsIn(pocket)
  pocket = tonumber(pocket) or Game3.POCKET_ITEMS
  local list = {}
  local bag = self.bag or {}
  for i = 1, #bag do
    local slot = bag[i]
    if slot and self:itemPocket(slot.id) == pocket then
      list[#list + 1] = slot
    end
  end
  return list
end

function Game3:pocketName(pocket)
  pocket = tonumber(pocket) or Game3.POCKET_ITEMS
  return Game3.POCKET_NAMES[pocket] or "ITEMS"
end

function Game3:firstFilledPocket()
  for p = 1, Game3.POCKET_COUNT do
    if #self:bagSlotsIn(p) > 0 then return p end
  end
  return Game3.POCKET_ITEMS
end

function Game3:itemName(id)
  local row = self:itemRow(id)
  if row and row.name and row.name ~= "" then
    local n = row.name
    n = n:gsub("é", "e"):gsub("É", "E")
    n = n:gsub("POK BALL", "POKe BALL")
    n = n:gsub("POK MON", "POKeMON")
    return n
  end
  if id == Game3.ITEM_POKE_BALL then return "POKe BALL" end
  if id == Game3.ITEM_GREAT_BALL then return "GREAT BALL" end
  if id == Game3.ITEM_ULTRA_BALL then return "ULTRA BALL" end
  if id == Game3.ITEM_MASTER_BALL then return "MASTER BALL" end
  if id == Game3.ITEM_SAFARI_BALL then return "SAFARI BALL" end
  if id == Game3.ITEM_NET_BALL then return "NET BALL" end
  if id == Game3.ITEM_DIVE_BALL then return "DIVE BALL" end
  if id == Game3.ITEM_NEST_BALL then return "NEST BALL" end
  if id == Game3.ITEM_REPEAT_BALL then return "REPEAT BALL" end
  if id == Game3.ITEM_TIMER_BALL then return "TIMER BALL" end
  if id == Game3.ITEM_LUXURY_BALL then return "LUXURY BALL" end
  if id == Game3.ITEM_PREMIER_BALL then return "PREMIER BALL" end
  if id == Game3.ITEM_POTION then return "POTION" end
  if id == Game3.ITEM_ANTIDOTE then return "ANTIDOTE" end
  if id == Game3.ITEM_FULL_RESTORE then return "FULL RESTORE" end
  if id == Game3.ITEM_MAX_POTION then return "MAX POTION" end
  if id == Game3.ITEM_HYPER_POTION then return "HYPER POTION" end
  if id == Game3.ITEM_SUPER_POTION then return "SUPER POTION" end
  if id == Game3.ITEM_FULL_HEAL then return "FULL HEAL" end
  if id == Game3.ITEM_REVIVE then return "REVIVE" end
  if id == Game3.ITEM_FRESH_WATER then return "FRESH WATER" end
  if id == Game3.ITEM_SODA_POP then return "SODA POP" end
  if id == Game3.ITEM_LEMONADE then return "LEMONADE" end
  if id == Game3.ITEM_MOOMOO_MILK then return "MOOMOO MILK" end
  if id == Game3.ITEM_RARE_CANDY then return "RARE CANDY" end
  if id == Game3.ITEM_PP_UP then return "PP UP" end
  if id == Game3.ITEM_NUGGET then return "NUGGET" end
  if id == Game3.ITEM_PROTEIN then return "PROTEIN" end
  if id == Game3.ITEM_KINGS_ROCK then return "KING'S ROCK" end
  if id == Game3.ITEM_SUPER_REPEL then return "SUPER REPEL" end
  if id == Game3.ITEM_MAX_REPEL then return "MAX REPEL" end
  if id == Game3.ITEM_ESCAPE_ROPE then return "ESCAPE ROPE" end
  if id == Game3.ITEM_REPEL then return "REPEL" end
  if id == Game3.ITEM_OLD_ROD then return "OLD ROD" end
  if id == Game3.ITEM_GOOD_ROD then return "GOOD ROD" end
  if id == Game3.ITEM_SUPER_ROD then return "SUPER ROD" end
  if id == Game3.ITEM_MACH_BIKE then return "MACH BIKE" end
  if id == Game3.ITEM_ACRO_BIKE then return "ACRO BIKE" end
  if id == Game3.ITEM_WAILMER_PAIL then return "WAILMER PAIL" end
  if id == Game3.ITEM_ITEMFINDER then return "ITEMFINDER" end
  if id == Game3.ITEM_DEVON_GOODS then return "DEVON GOODS" end
  if id == Game3.ITEM_LETTER then return "LETTER" end
  if id == Game3.ITEM_EXP_SHARE then return "EXP. SHARE" end
  if id == Game3.ITEM_HM_CUT then return "HM01" end
  if id == Game3.ITEM_HM_FLY then return "HM02" end
  if id == Game3.ITEM_HM_SURF then return "HM03" end
  if id == Game3.ITEM_HM_STRENGTH then return "HM04" end
  if id == Game3.ITEM_HM_FLASH then return "HM05" end
  if id == Game3.ITEM_HM_ROCK_SMASH then return "HM06" end
  if id == Game3.ITEM_HM_WATERFALL then return "HM07" end
  if id == Game3.ITEM_HM_DIVE then return "HM08" end
  if id == Game3.ITEM_TM43 then return "TM43" end
  if id >= Game3.ITEM_CHERI_BERRY and id <= Game3.ITEM_ENIGMA_BERRY then
    local name = Game3.BERRY_NAMES[id - Game3.ITEM_CHERI_BERRY + 1]
    if name then return name .. " BERRY" end
  end
  return ("ITEM %d"):format(id or 0)
end

function Game3:itemPrice(id)
  local row = self:itemRow(id)
  if row and type(row.price) == "number" then return row.price end
  if id == Game3.ITEM_POKE_BALL then return 200 end
  if id == Game3.ITEM_GREAT_BALL then return 600 end
  if id == Game3.ITEM_ULTRA_BALL then return 1200 end
  if id == Game3.ITEM_POTION then return 300 end
  if id == Game3.ITEM_MAX_POTION then return 2500 end
  if id == Game3.ITEM_HYPER_POTION then return 1200 end
  if id == Game3.ITEM_SUPER_POTION then return 700 end
  if id == Game3.ITEM_FRESH_WATER then return 200 end
  if id == Game3.ITEM_SODA_POP then return 300 end
  if id == Game3.ITEM_LEMONADE then return 350 end
  if id == Game3.ITEM_MOOMOO_MILK then return 500 end
  return 0
end

function Game3:itemCount(id)
  local n = 0
  local bag = self.bag or {}
  for i = 1, #bag do
    local slot = bag[i]
    if slot and slot.id == id then n = n + (slot.count or 0) end
  end
  return n
end

function Game3:syncPokeBalls()
  self.balls = self:itemCount(Game3.ITEM_POKE_BALL)
end

function Game3:addItem(id, count)
  id = tonumber(id)
  count = tonumber(count) or 1
  if not id or id < 1 or count < 1 then return false end
  self.bag = self.bag or {}
  for i = 1, #self.bag do
    local slot = self.bag[i]
    if slot and slot.id == id then
      slot.count = (slot.count or 0) + count
      if id == Game3.ITEM_POKE_BALL then self:syncPokeBalls() end
      return true
    end
  end
  self.bag[#self.bag + 1] = { id = id, count = count }
  if id == Game3.ITEM_POKE_BALL then self:syncPokeBalls() end
  return true
end

function Game3:takeItem(id, count)
  count = count or 1
  self.bag = self.bag or {}
  for i = 1, #self.bag do
    local slot = self.bag[i]
    if slot and slot.id == id and (slot.count or 0) >= count then
      slot.count = slot.count - count
      if slot.count <= 0 then table.remove(self.bag, i) end
      if id == Game3.ITEM_POKE_BALL then self:syncPokeBalls() end
      return true
    end
  end
  return false
end

function Game3.itemToBerryType(item)
  item = tonumber(item) or 0
  if item < Game3.ITEM_CHERI_BERRY or item > Game3.ITEM_ENIGMA_BERRY then
    return 1
  end
  return item - Game3.ITEM_CHERI_BERRY + 1
end

function Game3.berryTypeToItem(berry)
  berry = tonumber(berry) or 0
  if berry < 1 then return Game3.ITEM_CHERI_BERRY end
  local item = berry + Game3.ITEM_CHERI_BERRY - 1
  if item > Game3.ITEM_ENIGMA_BERRY then return Game3.ITEM_CHERI_BERRY end
  return item
end

function Game3.berryMinYield(berry)
  berry = tonumber(berry) or 0
  if berry == 9 or berry >= 36 then return 1 end
  return 2
end

function Game3.berryStageMinutes(berry)
  berry = tonumber(berry) or 0
  if berry == 9 then return 12 * 60 end
  if berry == 10 then return 6 * 60 end
  return 3 * 60
end

function Game3:berryName(berry)
  berry = tonumber(berry) or 0
  local names = Game3.BERRY_NAMES
  if names and names[berry] then return names[berry] end
  local name = self:itemName(Game3.berryTypeToItem(berry))
  name = name:gsub("%s+BERRY%s*$", "")
  if name:find("^ITEM ") then return "BERRY" end
  return name
end

function Game3:scriptBerryTreeId()
  local npc = self._scriptNpc
  return (npc and tonumber(npc.trainerRange)) or 0
end

function Game3.isBerryTreeGfx(gid)
  gid = gid or 0
  return gid == Game3.GFX_BERRY_TREE
    or gid == Game3.GFX_BERRY_TREE_EARLY
    or gid == Game3.GFX_BERRY_TREE_LATE
end

-- pokeruby get_berry_tree_graphics: stage 0 is invisible (loamy soil).
-- gBerryTreeGraphicsIdTable: planted/sprouted = gfx 61, taller+ = gfx 62.
function Game3:applyBerryTreeSprite(npc)
  if not npc or not Game3.isBerryTreeGfx(npc.graphicsId) then return npc end
  local tree = self:berryTreeInfo(npc.trainerRange)
  local stage = (tree and tree.stage) or 0
  if stage == Game3.BERRY_STAGE_NO_BERRY then
    npc.invisible = true
    return npc
  end
  npc.invisible = nil
  if stage <= Game3.BERRY_STAGE_SPROUTED then
    npc.graphicsId = Game3.GFX_BERRY_TREE_EARLY
  else
    npc.graphicsId = Game3.GFX_BERRY_TREE_LATE
  end
  return npc
end

function Game3:refreshBerryTreeSprites()
  local npcs = self:npcsFor(self.map)
  if not npcs then return end
  for i = 1, #npcs do
    self:applyBerryTreeSprite(npcs[i])
  end
end

function Game3:tryWaterBerryTree()
  local npc = self:facingNpc()
  if not npc or not Game3.isBerryTreeGfx(npc.graphicsId) then return false end
  self._scriptNpc = npc
  return self:waterBerryTree()
end

function Game3:useWailmerPail()
  if self:tryWaterBerryTree() then
    local tree = self:berryTreeInfo(self:scriptBerryTreeId())
    local name = self:berryName(tree.berry)
    return true, ("Watered the %s. The plant seems to be delighted."):format(name)
  end
  return false, ("DAD's advice... %s, there's a time and place for everything!"):format(
    self:playerName())
end

-- pokeruby ItemfinderCheckForHiddenItems: (u16)(dx+7)<15 and
-- dy in [-5, 5]. Cells are already map xy (no 7-tile border).
function Game3.itemfinderInRange(dx, dy)
  dx = tonumber(dx) or 0
  dy = tonumber(dy) or 0
  return dx >= -7 and dx <= 7 and dy >= -5 and dy <= 5
end

-- sub_80C9838: smaller Manhattan, then smaller |dy|, then larger dy.
function Game3.itemfinderCloser(ax, ay, bx, by)
  ax, ay = tonumber(ax) or 0, tonumber(ay) or 0
  bx, by = tonumber(bx) or 0, tonumber(by) or 0
  local da = math.abs(ax) + math.abs(ay)
  local db = math.abs(bx) + math.abs(by)
  if da > db then return true end
  if da == db and (math.abs(ay) > math.abs(by)
      or (math.abs(ay) == math.abs(by) and ay < by)) then
    return true
  end
  return false
end

-- GetPlayerDirectionTowardsHiddenItem then gItemFinderDirections[dir-1].
function Game3.itemfinderFacing(dx, dy)
  dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
  if dx == 0 and dy == 0 then return nil end
  local abx, aby = math.abs(dx), math.abs(dy)
  if abx > aby then
    if dx < 0 then return "west" end
    return "east"
  end
  if dy < 0 then return "north" end
  return "south"
end

function Game3:hiddenItemAvailable(ev)
  if not ev then return false end
  local kind = ev.kind or 0
  if kind ~= Game3.BG_HIDDEN_ITEM and kind ~= 5 and kind ~= 6 then
    return false
  end
  if not ev.itemId or ev.itemId < 1 then return false end
  local flag = Game3.hiddenFlag(ev.hiddenId)
  return not (self.flags and self.flags[flag])
end

-- Relative dx, dy of the closest in-range hidden item, or nil.
function Game3:nearestHiddenItem()
  local map = self.map
  local evs = map and map.bgEvents
  if type(evs) ~= "table" then return nil end
  local px, py = self.playerX or 0, self.playerY or 0
  local bestX, bestY
  for i = 1, #evs do
    local ev = evs[i]
    if self:hiddenItemAvailable(ev) then
      local dx = (ev.x or 0) - px
      local dy = (ev.y or 0) - py
      if Game3.itemfinderInRange(dx, dy) then
        if not bestX or Game3.itemfinderCloser(bestX, bestY, dx, dy) then
          bestX, bestY = dx, dy
        end
      end
    end
  end
  return bestX, bestY
end

function Game3:useItemfinder()
  local dx, dy = self:nearestHiddenItem()
  if dx == nil then
    return true, "... ... ... ... Nope!\nThere's no response."
  end
  if dx == 0 and dy == 0 then
    return true, "The machine's indicating something\nright underfoot!"
  end
  local face = Game3.itemfinderFacing(dx, dy)
  if face then self.facing = face end
  return true, "Oh!\nThe machine's responding!\nThere's an item buried around here!"
end

function Game3:ensureBerryTrees()
  if type(self.berryTrees) == "table" then return self.berryTrees end
  return self:initBerryTrees()
end

function Game3:initBerryTrees()
  self.berryTrees = {}
  local src = Game3.NEW_GAME_BERRY_TREES
  for i = 1, #src, 2 do
    self:plantBerryTree(src[i], src[i + 1], Game3.BERRY_STAGE_BERRIES, false)
  end
  return self.berryTrees
end

function Game3:plantBerryTree(id, berry, stage, sparkle)
  id = tonumber(id) or 0
  if id < 1 then return false end
  if type(self.berryTrees) ~= "table" then self.berryTrees = {} end
  berry = tonumber(berry) or 0
  stage = tonumber(stage) or 0
  if berry == 0 or stage == Game3.BERRY_STAGE_NO_BERRY then
    self.berryTrees[id] = { berry = 0, stage = 0, yield = 0, watered = 0 }
    return true
  end
  local minutes = Game3.berryStageMinutes(berry)
  local yield = 0
  if stage == Game3.BERRY_STAGE_BERRIES then
    yield = Game3.berryMinYield(berry)
    minutes = minutes * 4
  end
  self.berryTrees[id] = {
    berry = berry,
    stage = stage,
    yield = yield,
    watered = 0,
    minutes = minutes,
    sparkle = not sparkle,
    regrowth = 0,
  }
  return true
end

function Game3:berryTreeInfo(id)
  self:ensureBerryTrees()
  id = tonumber(id) or 0
  local tree = self.berryTrees[id]
  if type(tree) ~= "table" then
    return { berry = 0, stage = 0, yield = 0, watered = 0 }
  end
  return self:normalizeBerryTree(tree)
end

function Game3:snapshotBerryTrees()
  self:ensureBerryTrees()
  local out = {}
  for id, tree in pairs(self.berryTrees) do
    if type(tree) == "table" then
      out[#out + 1] = {
        id = id,
        berry = tree.berry or 0,
        stage = tree.stage or 0,
        yield = tree.yield or 0,
        watered = tree.watered or 0,
        minutes = tree.minutes or 0,
        sparkle = tree.sparkle and true or nil,
        regrowth = tree.regrowth or 0,
      }
    end
  end
  table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
  return out
end

function Game3:loadBerryTrees(data)
  if type(data) ~= "table" or #data < 1 then
    self:initBerryTrees()
    return
  end
  self.berryTrees = {}
  for i = 1, #data do
    local row = data[i]
    local id = row and tonumber(row.id)
    if id and id > 0 then
      self.berryTrees[id] = {
        berry = tonumber(row.berry) or 0,
        stage = tonumber(row.stage) or 0,
        yield = tonumber(row.yield) or 0,
        watered = tonumber(row.watered) or 0,
        minutes = tonumber(row.minutes),
        sparkle = row.sparkle and true or nil,
        regrowth = tonumber(row.regrowth) or 0,
      }
      self:normalizeBerryTree(self.berryTrees[id])
    end
  end
  if not next(self.berryTrees) then self:initBerryTrees() end
end

function Game3.ecPack(group, index)
  return (tonumber(group) or 0) * 512 + (tonumber(index) or 0)
end

function Game3.ecWordText(word)
  word = tonumber(word) or 0
  local group = math.floor(word / 512)
  local index = word % 512
  local list = Game3.EC_WORDS[group]
  return list and list[index + 1] or ""
end

function Game3.easyChatPhrase(pair)
  if type(pair) ~= "table" then return "" end
  local a = Game3.ecWordText(pair[1] or pair.w0)
  local b = Game3.ecWordText(pair[2] or pair.w1)
  if a == "" then return b end
  if b == "" then return a end
  return a .. " " .. b
end

function Game3:ecRandomWord(group)
  local list = Game3.EC_WORDS[group]
  if type(list) ~= "table" or #list < 1 then return 0 end
  return Game3.ecPack(group, self:rand(#list) - 1)
end

-- pokeruby sub_80FA740: max popularity 30..127, current 30..max.
function Game3:rollTrendPopularity()
  local r4 = (self:rand(65536) - 1) % 98
  if r4 > 50 then
    r4 = (self:rand(65536) - 1) % 98
    if r4 > 80 then r4 = (self:rand(65536) - 1) % 98 end
  end
  local maxp = r4 + 30
  local cur = ((self:rand(65536) - 1) % (r4 + 1)) + 30
  return cur, maxp
end

-- pokeruby InitDewfordTrend: 5 condition+hobby/lifestyle pairs, then
-- sort so slot 0 is the current phrase (BufferTrendyPhraseString).
function Game3:initDewfordTrend()
  local pairs = {}
  for i = 1, 5 do
    local w1
    if (self:rand(65536) - 1) % 2 == 0 then
      w1 = self:ecRandomWord(Game3.EC_GROUP_LIFESTYLE)
    else
      w1 = self:ecRandomWord(Game3.EC_GROUP_HOBBIES)
    end
    local cur, maxp = self:rollTrendPopularity()
    pairs[i] = {
      Game3.ecPack(Game3.EC_GROUP_CONDITIONS,
        self:rand(#Game3.EC_WORDS[Game3.EC_GROUP_CONDITIONS]) - 1),
      w1,
      pop = cur,
      maxPop = maxp,
      rising = ((self:rand(65536) - 1) % 2) == 1,
    }
  end
  table.sort(pairs, function(a, b)
    return (a.pop or 0) > (b.pop or 0)
  end)
  self.easyChatPairs = pairs
  return pairs
end

function Game3:ensureDewfordTrend()
  if type(self.easyChatPairs) == "table" and #self.easyChatPairs >= 1 then
    return self.easyChatPairs
  end
  return self:initDewfordTrend()
end

function Game3:snapshotEasyChatPairs()
  local src = self:ensureDewfordTrend()
  local out = {}
  for i = 1, #src do
    local p = src[i]
    out[i] = {
      p[1], p[2],
      pop = p.pop, maxPop = p.maxPop, rising = p.rising and true or nil,
    }
  end
  return out
end

function Game3:loadEasyChatPairs(data)
  if type(data) ~= "table" or #data < 1 then
    self:initDewfordTrend()
    return
  end
  local pairs = {}
  for i = 1, math.min(5, #data) do
    local row = data[i]
    if type(row) == "table" then
      pairs[#pairs + 1] = {
        tonumber(row[1]) or 0,
        tonumber(row[2]) or 0,
        pop = tonumber(row.pop) or 30,
        maxPop = tonumber(row.maxPop) or 30,
        rising = row.rising and true or nil,
      }
    end
  end
  if #pairs < 1 then
    self:initDewfordTrend()
  else
    self.easyChatPairs = pairs
  end
end

function Game3:bufferTrendyPhraseString()
  local pairs = self:ensureDewfordTrend()
  local idx = (self:varGet(0x8004) or 0) + 1
  local pair = pairs[idx] or pairs[1]
  return self:setStringVar(1, Game3.easyChatPhrase(pair))
end

-- pokeruby IsTrendyPhraseBoring: the lead is only barely ahead of #2,
-- the lead is falling, and #2 is rising.
function Game3:isTrendyPhraseBoring()
  local pairs = self:ensureDewfordTrend()
  local a, b = pairs[1], pairs[2]
  if not (a and b) then return false end
  if (a.pop or 0) - (b.pop or 0) > 1 then return false end
  if a.rising then return false end
  if not b.rising then return false end
  return true
end

function Game3:bufferRandomHobbyOrLifestyle()
  local group = Game3.EC_GROUP_HOBBIES
  if (self:rand(65536) - 1) % 2 == 0 then
    group = Game3.EC_GROUP_LIFESTYLE
  end
  return self:setStringVar(2, Game3.ecWordText(self:ecRandomWord(group)))
end

function Game3:dewfordHallPaintingIndex()
  local pair = self:ensureDewfordTrend()[1]
  if not pair then return 0 end
  return ((tonumber(pair[1]) or 0) + (tonumber(pair[2]) or 0)) % 8
end

-- Dewford editor: word 0 is Conditions; word 1 is Hobbies then Lifestyle
-- (InitDewfordTrend's groups). Full Easy Chat groups stay later.
function Game3:easyChatOptions(slot)
  local labels, packs = {}, {}
  local function add(group)
    local list = Game3.EC_WORDS[group]
    if type(list) ~= "table" then return end
    for i = 1, #list do
      labels[#labels + 1] = list[i]
      packs[#packs + 1] = Game3.ecPack(group, i - 1)
    end
  end
  if (tonumber(slot) or 0) == 0 then
    add(Game3.EC_GROUP_CONDITIONS)
  else
    add(Game3.EC_GROUP_HOBBIES)
    add(Game3.EC_GROUP_LIFESTYLE)
  end
  return labels, packs
end

function Game3:openEasyChatSlot(field, slot)
  if type(field) ~= "table" then return end
  field.slot = tonumber(slot) or 0
  local labels, packs = self:easyChatOptions(field.slot)
  field.labels = labels
  field.packs = packs
  field.cursor = 0
  local want = field.words and field.words[field.slot + 1]
  for i = 1, #packs do
    if packs[i] == want then
      field.cursor = i - 1
      break
    end
  end
  field.text = Game3.easyChatPhrase(field.words)
end

function Game3:phraseAlreadyTrendy(w0, w1)
  w0, w1 = tonumber(w0) or 0, tonumber(w1) or 0
  local pairs = self:ensureDewfordTrend()
  for i = 1, #pairs do
    local p = pairs[i]
    if (tonumber(p[1]) or 0) == w0 and (tonumber(p[2]) or 0) == w1 then
      return true
    end
  end
  return false
end

-- pokeruby sub_80FA670 case 0: higher pop, then higher maxPop, else Random()&1.
function Game3:trendBeats(a, b)
  if not a or not b then return false end
  local ap, bp = a.pop or 0, b.pop or 0
  if ap > bp then return true end
  if ap < bp then return false end
  local am, bm = a.maxPop or 0, b.maxPop or 0
  if am > bm then return true end
  if am < bm then return false end
  return ((self:rand(65536) - 1) % 2) == 1
end

-- pokeruby sub_80FA364. TRUE only if the pair becomes slot 0.
function Game3:submitDewfordPhrase(w0, w1)
  w0, w1 = tonumber(w0) or 0, tonumber(w1) or 0
  if self:phraseAlreadyTrendy(w0, w1) then return false end
  self.flags = self.flags or {}
  if not self.flags[Game3.FLAG_SYS_POPWORD_INPUT] then
    self.flags[Game3.FLAG_SYS_POPWORD_INPUT] = true
    if not self.flags[Game3.FLAG_SYS_MIX_RECORD] then
      local lead = self:ensureDewfordTrend()[1]
      if lead then
        lead[1], lead[2] = w0, w1
      end
      return true
    end
  end
  local cur, maxp = self:rollTrendPopularity()
  local neu = { w0, w1, pop = cur, maxPop = maxp, rising = true }
  local pairs = self:ensureDewfordTrend()
  for i = 1, 5 do
    local row = pairs[i]
    if row and self:trendBeats(neu, row) then
      for r = 5, i + 1, -1 do
        pairs[r] = pairs[r - 1]
      end
      pairs[i] = neu
      return i == 1
    end
  end
  pairs[5] = neu
  return false
end

function Game3:showEasyChatScreen()
  local mode = (self.scriptVars and self.scriptVars[0x8004]) or 0
  if mode ~= Game3.EC_TYPE_TRENDY_PHRASE then
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    return false
  end
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SYS_CHAT_USED] = true
  local pair = self:ensureDewfordTrend()[1] or { 0, 0 }
  local orig = { pair[1], pair[2] }
  self:beginScriptWait()
  self.field = {
    kind = "easy_chat",
    orig = orig,
    words = { orig[1], orig[2] },
    scripted = true,
  }
  self:openEasyChatSlot(self.field, 0)
  return true
end

function Game3:finishEasyChat(ok)
  local f = self.field
  local words = f and f.words
  local orig = f and f.orig
  self.field = nil
  if ok and type(words) == "table" then
    local same = Game3.easyChatPhrase(words) == Game3.easyChatPhrase(orig)
    if same then
      self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    else
      self:setScriptVar(Gen3Script.VAR_RESULT, 1)
      local trendy = self:submitDewfordPhrase(words[1], words[2])
      self:setScriptVar(0x8004, trendy and 1 or 0)
    end
  else
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
  end
  return self:endScriptWait()
end

function Game3:stepEasyChat(f)
  local n = #(f.labels or {})
  if n < 1 then n = 1 end
  if Input:wasPressed("down") then
    local nxt = (f.cursor or 0) + 1
    if nxt >= n then f.cursor = 0 else f.cursor = nxt end
  elseif Input:wasPressed("up") then
    local prev = (f.cursor or 0) - 1
    if prev < 0 then f.cursor = n - 1 else f.cursor = prev end
  elseif Input:wasPressed("a") then
    local pack = f.packs and f.packs[(f.cursor or 0) + 1]
    if pack then f.words[(f.slot or 0) + 1] = pack end
    if (f.slot or 0) == 0 then
      self:openEasyChatSlot(f, 1)
    else
      self:finishEasyChat(true)
    end
  elseif Input:wasPressed("b") then
    if (f.slot or 0) == 0 then
      self:finishEasyChat(false)
    else
      self:openEasyChatSlot(f, 0)
    end
  end
end

function Game3:berryGetTreeData()
  local tree = self:berryTreeInfo(self:scriptBerryTreeId())
  tree.sparkle = nil
  self:setScriptVar(0x8004, tree.stage or 0)
  self:setScriptVar(0x8005, tree.watered or 0)
  self:setScriptVar(0x8006, tree.yield or 0)
  if (tree.berry or 0) > 0 then
    self:setStringVar(1, self:berryName(tree.berry))
  end
end

function Game3:chooseBerryFromBag()
  local slots = self:bagSlotsIn(Game3.POCKET_BERRIES)
  local id = 0
  if slots[1] then id = slots[1].id or 0 end
  self:setScriptVar(Game3.VAR_ITEM_ID, id)
end

function Game3:pickBerryTree()
  local id = self:scriptBerryTreeId()
  local tree = self:berryTreeInfo(id)
  if (tree.stage or 0) ~= Game3.BERRY_STAGE_BERRIES or (tree.berry or 0) < 1 then
    self:setScriptVar(0x8004, 0)
    return
  end
  local n = tree.yield or Game3.berryMinYield(tree.berry)
  local ok = self:addItem(Game3.berryTypeToItem(tree.berry), n)
  self:setScriptVar(0x8004, ok and 1 or 0)
end

function Game3:removeBerryTree()
  self:plantBerryTree(self:scriptBerryTreeId(), 0, 0, false)
end

function Game3:waterBerryTree()
  local tree = self:berryTreeInfo(self:scriptBerryTreeId())
  local stage = tree.stage or 0
  if stage >= Game3.BERRY_STAGE_PLANTED and stage <= Game3.BERRY_STAGE_FLOWERING then
    tree.watered = math.min(4, (tree.watered or 0) + 1)
    return true
  end
  return false
end

function Game3:normalizeBerryTree(tree)
  if type(tree) ~= "table" or (tree.berry or 0) < 1 then return tree end
  if tree.minutes == nil and tree.sparkle == nil
      and (tree.stage or 0) == Game3.BERRY_STAGE_BERRIES then
    tree.sparkle = true
    tree.minutes = Game3.berryStageMinutes(tree.berry) * 4
  elseif tree.minutes == nil then
    tree.minutes = Game3.berryStageMinutes(tree.berry)
  end
  return tree
end

function Game3:growBerryTree(tree)
  if type(tree) ~= "table" or tree.sparkle then return false end
  local stage = tree.stage or 0
  if stage == Game3.BERRY_STAGE_NO_BERRY then return false end
  if stage == Game3.BERRY_STAGE_FLOWERING then
    tree.yield = Game3.berryMinYield(tree.berry)
  end
  if stage >= Game3.BERRY_STAGE_PLANTED
      and stage <= Game3.BERRY_STAGE_FLOWERING then
    tree.stage = stage + 1
    return true
  end
  if stage == Game3.BERRY_STAGE_BERRIES then
    tree.watered = 0
    tree.yield = 0
    tree.stage = Game3.BERRY_STAGE_SPROUTED
    tree.regrowth = (tree.regrowth or 0) + 1
    if tree.regrowth >= Game3.BERRY_REGROW_LIMIT then
      tree.berry = 0
      tree.stage = 0
      tree.minutes = 0
    end
    return true
  end
  return false
end

function Game3:advanceBerryTree(tree, minutesPassed)
  if type(tree) ~= "table" or (tree.berry or 0) < 1 then return end
  self:normalizeBerryTree(tree)
  if tree.sparkle or (tree.stage or 0) == 0 then return end
  minutesPassed = tonumber(minutesPassed) or 0
  if minutesPassed < 1 then return end
  local dur = Game3.berryStageMinutes(tree.berry)
  if minutesPassed >= dur * 71 then
    tree.berry = 0
    tree.stage = 0
    tree.yield = 0
    tree.watered = 0
    tree.minutes = 0
    return
  end
  local time = minutesPassed
  local left = tree.minutes or dur
  while time > 0 do
    if left > time then
      tree.minutes = left - time
      return
    end
    time = time - left
    left = dur
    if not self:growBerryTree(tree) then
      tree.minutes = left
      return
    end
    if (tree.berry or 0) < 1 then
      tree.minutes = 0
      return
    end
    if tree.stage == Game3.BERRY_STAGE_BERRIES then
      left = dur * 4
    end
  end
  tree.minutes = left
end

function Game3:tickBerryTrees(dt)
  if type(self.berryTrees) ~= "table" then return end
  local acc = (self.berryMinuteAcc or 0) + (dt or 0)
  local minutes = math.floor(acc)
  self.berryMinuteAcc = acc - minutes
  if minutes < 1 then return end
  for _, tree in pairs(self.berryTrees) do
    self:advanceBerryTree(tree, minutes)
  end
  self:refreshBerryTreeSprites()
end

function Game3:runBerrySpecial(id)
  if id == Game3.SPECIAL_GET_BERRY_TREE_DATA then
    self:berryGetTreeData()
  elseif id == Game3.SPECIAL_BERRY_BAG_MENU then
    self:chooseBerryFromBag()
  elseif id == Game3.SPECIAL_PLANT_BERRY_TREE then
    self:plantBerryTree(
      self:scriptBerryTreeId(),
      Game3.itemToBerryType(self:varGet(Game3.VAR_ITEM_ID)),
      Game3.BERRY_STAGE_PLANTED, true)
    self:berryGetTreeData()
    self:refreshBerryTreeSprites()
  elseif id == Game3.SPECIAL_PICK_BERRY_TREE then
    self:pickBerryTree()
  elseif id == Game3.SPECIAL_REMOVE_BERRY_TREE then
    self:removeBerryTree()
    self:refreshBerryTreeSprites()
  elseif id == Game3.SPECIAL_WATER_BERRY_TREE then
    self:waterBerryTree()
  elseif id == Game3.SPECIAL_PLAYER_HAS_BERRIES then
    local has = #self:bagSlotsIn(Game3.POCKET_BERRIES) > 0
    self:setScriptVar(Gen3Script.VAR_RESULT, has and 1 or 0)
  end
end

function Game3:ballCount()
  local n = self:itemCount(Game3.ITEM_POKE_BALL)
  if n > 0 then return n end
  return self.balls or 0
end

function Game3:spendPokeBall()
  if self:takeItem(Game3.ITEM_POKE_BALL, 1) then return true end
  if (self.balls or 0) > 0 then
    self.balls = self.balls - 1
    return true
  end
  return false
end

function Game3:healAmount(id)
  return Game3.HEAL_AMOUNT[id]
end

function Game3:statusHeal(id)
  return Game3.STATUS_HEAL[id]
end

function Game3.isBall(id)
  id = tonumber(id) or 0
  return id >= Game3.ITEM_MASTER_BALL and id <= Game3.LAST_BALL
end

function Game3.ballBonus(id)
  if id == Game3.ITEM_MASTER_BALL then return 255 end
  if id == Game3.ITEM_ULTRA_BALL then return 2 end
  if id == Game3.ITEM_GREAT_BALL then return 1.5 end
  if id == Game3.ITEM_SAFARI_BALL then return 1.5 end
  return Game3.POKE_BALL_BONUS
end

-- pokeruby atkEF_handleballthrow: multipliers are tenths (10 = 1x).
function Game3:catchBallBonus(id, mon)
  id = tonumber(id)
  if id == Game3.ITEM_NET_BALL then
    if Game3.hasType(mon, Game3.TYPE_WATER) or Game3.hasType(mon, Game3.TYPE_BUG) then
      return 3
    end
    return 1
  end
  if id == Game3.ITEM_DIVE_BALL then
    if (self.map and self.map.mapType) == Game3.MAP_TYPE_UNDERWATER then
      return 3.5
    end
    return 1
  end
  if id == Game3.ITEM_NEST_BALL then
    local level = (mon and mon.level) or 1
    if level <= 39 then
      local tenths = 40 - level
      if tenths < 10 then tenths = 10 end
      return tenths / 10
    end
    return 1
  end
  if id == Game3.ITEM_REPEAT_BALL then
    if mon and self:hasCaught(mon.species) then return 3 end
    return 1
  end
  if id == Game3.ITEM_TIMER_BALL then
    local tenths = ((self.battle and self.battle.turns) or 0) + 10
    if tenths > 40 then tenths = 40 end
    return tenths / 10
  end
  return Game3.ballBonus(id)
end

function Game3:itemTarget(id)
  local amount = self:healAmount(id)
  local clears = self:statusHeal(id)
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon and (mon.hp or 0) > 0 then
      local hurt = amount and (mon.hp or 0) < (mon.maxHp or 0)
      local sick = clears and mon.status
        and (clears == true or mon.status == clears)
      if hurt or sick then return mon end
    end
  end
end

function Game3:useItemOnMon(mon, id)
  if not mon or (mon.hp or 0) <= 0 then
    return false, "It won't have any effect."
  end
  local amount = self:healAmount(id)
  local clears = self:statusHeal(id)
  local willHeal = amount and (mon.hp or 0) < (mon.maxHp or 0)
  local willCure = clears and mon.status
    and (clears == true or mon.status == clears)
  if not willHeal and not willCure then
    return false, "It won't have any effect."
  end
  if not self:takeItem(id, 1) then
    return false, "You have none left!"
  end
  local texts = {}
  if willHeal then
    local heal = amount >= 999 and (mon.maxHp or amount) or amount
    mon.hp = math.min(mon.maxHp or heal, (mon.hp or 0) + heal)
    texts[#texts + 1] = ("%s recovered HP!"):format(mon.name or "POKeMON")
  end
  if willCure then
    mon.status = nil
    mon.sleepTurns = nil
    texts[#texts + 1] = ("%s's status returned to normal!"):format(
      mon.name or "POKeMON")
  end
  return true, table.concat(texts, " ")
end

function Game3:useFieldItem(id)
  if Game3.isBall(id) then
    return false, "Use this in battle."
  end
  if Game3.isTmHm(id) then
    return self:openPartyTeach(id)
  end
  if Game3.rodKind(id) ~= nil then
    return self:useRod(id)
  end
  if id == Game3.ITEM_MACH_BIKE or id == Game3.ITEM_ACRO_BIKE then
    return self:useBike(id)
  end
  if id == Game3.ITEM_WAILMER_PAIL then
    return self:useWailmerPail()
  end
  if id == Game3.ITEM_ITEMFINDER then
    return self:useItemfinder()
  end
  if Game3.REPEL_STEPS[id] then
    return self:useRepel(id)
  end
  if id == Game3.ITEM_ESCAPE_ROPE then
    return self:useEscapeRope()
  end
  local mon = self:itemTarget(id)
  if not mon then return false, "It won't have any effect." end
  return self:useItemOnMon(mon, id)
end

function Game3:battleBagList()
  local list = {}
  for i = 1, #(self.bag or {}) do
    local slot = self.bag[i]
    if slot then list[#list + 1] = slot end
  end
  if self:itemCount(Game3.ITEM_POKE_BALL) < 1 and (self.balls or 0) > 0 then
    list[#list + 1] = { id = Game3.ITEM_POKE_BALL, count = self.balls }
  end
  return list
end

function Game3:spendBall(id)
  id = id or Game3.ITEM_POKE_BALL
  if id == Game3.ITEM_POKE_BALL then return self:spendPokeBall() end
  return self:takeItem(id, 1)
end

function Game3:buyMartItem(id)
  if not id then return false, "There's nothing to buy." end
  local price = self:itemPrice(id)
  if (self.money or 0) < price then
    return false, "You don't have enough money."
  end
  self.money = (self.money or 0) - price
  self:addItem(id, 1)
  return true, ("Got %s!"):format(self:itemName(id))
end

function Game3:pickupItem(npc)
  local id = npc and npc.itemId
  if not id or id < 1 then return false end
  local n = npc.itemCount or 1
  self:addItem(id, n)
  if npc.flagId and npc.flagId ~= 0 then
    self.flags = self.flags or {}
    self.flags[npc.flagId] = true
  end
  npc.hidden = true
  npc.defeated = true
  local name = self:itemName(id)
  if n > 1 then
    self.field = { kind = "talk", text = ("Found %s x%d!"):format(name, n) }
  else
    self.field = { kind = "talk", text = ("Found %s!"):format(name) }
  end
  return true
end

function Game3.isStarterSpecies(id)
  return id == Game3.SPECIES_TREECKO
    or id == Game3.SPECIES_TORCHIC
    or id == Game3.SPECIES_MUDKIP
end

function Game3:hasStarter()
  if self.flags and self.flags[Game3.FLAG_SYS_POKEMON_GET] then return true end
  return #(self.party or {}) > 0
end

function Game3:isFemale()
  return (self.gender or 0) == Game3.GENDER_FEMALE
end

function Game3:playerName()
  if type(self.customName) == "string" and self.customName ~= "" then
    return self.customName
  end
  return self:isFemale() and "MAY" or "BRENDAN"
end

function Game3:rivalName()
  return self:isFemale() and "BRENDAN" or "MAY"
end

function Game3:rivalGraphicsId()
  return self:isFemale() and Game3.GFX_RIVAL_BRENDAN or Game3.GFX_RIVAL_MAY
end

function Game3:playerGraphicsId()
  local female = self:isFemale()
  if self.diving or self:isUnderwater() then
    return female and Game3.GFX_MAY_UNDERWATER or Game3.GFX_BRENDAN_UNDERWATER
  end
  if self.surfing then
    return female and Game3.GFX_MAY_SURFING or Game3.GFX_BRENDAN_SURFING
  end
  if self.bike == "acro" then
    return female and Game3.GFX_MAY_ACRO_BIKE or Game3.GFX_BRENDAN_ACRO_BIKE
  end
  if self.bike == "mach" then
    return female and Game3.GFX_MAY_MACH_BIKE or Game3.GFX_BRENDAN_MACH_BIKE
  end
  if female then
    local byId = self.data and self.data.sprites and self.data.sprites.byId
    if byId and byId[Game3.GFX_MAY] then return Game3.GFX_MAY end
    return Game3.GFX_RIVAL_MAY
  end
  return Game3.GFX_BRENDAN
end

function Game3:resolveGraphicsId(gid)
  gid = gid or 0
  if gid >= Game3.GFX_VAR_0 and gid <= Game3.GFX_VAR_F then
    local resolved = self:varGet(Game3.VAR_OBJ_GFX_ID_0 + (gid - Game3.GFX_VAR_0))
    if resolved ~= 0 then return resolved end
    if gid == Game3.GFX_VAR_0 then return self:rivalGraphicsId() end
  end
  return gid
end

function Game3.isRivalGfx(gid)
  return gid == Game3.GFX_RIVAL_BRENDAN or gid == Game3.GFX_RIVAL_MAY
    or gid == Game3.GFX_VAR_0
end

function Game3.starterIndex(species)
  species = tonumber(species)
  for i = 1, #Game3.STARTERS do
    if Game3.STARTERS[i] == species then return i - 1 end
  end
end

function Game3.starterSpecies(index)
  index = math.floor(tonumber(index) or 0)
  if index < 0 or index > 2 then index = 0 end
  return Game3.STARTERS[index + 1]
end

-- pokeruby IsStarterInParty: SPECIES2 (eggs are SPECIES_EGG) equals
-- GetStarterPokemon(VAR_STARTER_MON).
function Game3:isStarterInParty()
  local want = Game3.starterSpecies(self:varGet(Game3.VAR_STARTER_MON))
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon and not mon.isEgg and mon.species == want then return true end
  end
  return false
end

function Game3.rivalStarterSpecies(species)
  local i = Game3.starterIndex(species)
  if not i then return Game3.SPECIES_TORCHIC end
  return Game3.STARTERS[(i + 1) % 3 + 1]
end

function Game3:resetMapFlagList()
  local cached = self.data and self.data.constants and self.data.constants.resetMapFlags
  if type(cached) == "table" and #cached > 0 then return cached end
  return Game3.NEW_GAME_HIDE_FLAGS
end

function Game3:applyNewGameHideFlags()
  self.flags = self.flags or {}
  local list = self:resetMapFlagList()
  for i = 1, #list do
    self.flags[list[i]] = true
  end
  return true
end

function Game3:applyGender(gender)
  self.gender = gender == Game3.GENDER_FEMALE
    and Game3.GENDER_FEMALE or Game3.GENDER_MALE
  self.flags = self.flags or {}
  local male = {
    Game3.FLAG_HIDE_MAY_MOM_DOWNSTAIRS,
    Game3.FLAG_HIDE_MOVING_TRUCK_MAY,
    Game3.FLAG_HIDE_BRENDAN_MOM,
    Game3.FLAG_HIDE_BRENDAN_UPSTAIRS,
  }
  local female = {
    Game3.FLAG_HIDE_BRENDAN_MOM_DOWNSTAIRS,
    Game3.FLAG_HIDE_MOVING_TRUCK_BRENDAN,
    Game3.FLAG_HIDE_MAY_MOM,
    Game3.FLAG_HIDE_MAY_UPSTAIRS,
  }
  for i = 1, #male do self.flags[male[i]] = nil end
  for i = 1, #female do self.flags[female[i]] = nil end
  local set = self:isFemale() and female or male
  for i = 1, #set do self.flags[set[i]] = true end
end

function Game3:openGenderMenu()
  self.field = { kind = "gender", cursor = 0 }
  return true
end

function Game3:chooseGender(gender)
  self:applyGender(gender)
  if self.map then
    self:runMapScript("onTransition")
    self:resetNpcs(self.map)
    self:tryMapFrameScript()
  end
  self.field = nil
  return true
end

function Game3:isRivalNpc(npc)
  if not npc then return false end
  return Game3.isRivalGfx(self:resolveGraphicsId(npc.graphicsId))
end

function Game3:isLabRival(npc)
  return npc and (npc.flagId or 0) == Game3.FLAG_HIDE_RIVAL_BIRCH_LAB
end

function Game3:isRoute103Rival(npc)
  return npc and (npc.flagId or 0) == Game3.FLAG_HIDE_RIVAL_ROUTE103
end

function Game3:hasDefeatedRoute103Rival()
  return self.flags and self.flags[Game3.FLAG_DEFEATED_RIVAL_ROUTE103] == true
end

function Game3:playerStarterSpecies()
  local party = self.party or {}
  for i = 1, #party do
    local s = party[i] and party[i].species
    if Game3.isStarterSpecies(s) then return s end
  end
end

function Game3:rivalTrainerId()
  local idx = Game3.starterIndex(self:playerStarterSpecies()) or 1
  if self:isFemale() then
    local ids = {
      [0] = Game3.TRAINER_BRENDAN_4,
      [1] = Game3.TRAINER_BRENDAN_7,
      [2] = Game3.TRAINER_BRENDAN_1,
    }
    return ids[idx]
  end
  local ids = {
    [0] = Game3.TRAINER_MAY_4,
    [1] = Game3.TRAINER_MAY_7,
    [2] = Game3.TRAINER_MAY_1,
  }
  return ids[idx]
end

function Game3:rivalParty()
  local id = self:rivalTrainerId()
  local pack = self.data and self.data.trainers
  local tr = pack and pack.byId and pack.byId[id]
  if tr and type(tr.party) == "table" and #tr.party > 0 then
    return tr.party, tr
  end
  local species = self.rivalSpecies
    or Game3.rivalStarterSpecies(self:playerStarterSpecies())
  return { { level = Game3.STARTER_LEVEL, species = species } }, nil
end

function Game3:startRivalBattle(npc)
  if not self:hasStarter() then
    self.field = {
      kind = "talk",
      text = ("%s: You don't have a POKeMON yet!"):format(self:rivalName()),
    }
    return true
  end
  if self:hasDefeatedRoute103Rival() then
    self.field = {
      kind = "talk",
      text = ("%s: Where should I go next?"):format(self:rivalName()),
    }
    return true
  end
  local party, tr = self:rivalParty()
  npc = npc or {}
  npc.party = party
  npc.trainerName = (tr and tr.name) or self:rivalName()
  npc.trainerClass = "RIVAL"
  npc.flagId = npc.flagId or Game3.FLAG_HIDE_RIVAL_ROUTE103
  if not self:startTrainerBattle(npc) then return false end
  self.battle.rivalRoute103 = true
  self.battle.text = ("%s would like to battle!"):format(self:rivalName())
  return true
end

function Game3:finishRoute103Rival(npc)
  self.flags = self.flags or {}
  self.scriptVars = self.scriptVars or {}
  self.flags[Game3.FLAG_HIDE_RIVAL_ROUTE103] = true
  self.flags[Game3.FLAG_DEFEATED_RIVAL_ROUTE103] = true
  self.flags[Game3.FLAG_HIDE_RIVAL_BIRCH_LAB] = nil
  self.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN] = nil
  self.scriptVars[Game3.VAR_BIRCH_LAB_STATE] = 4
  self.scriptVars[Game3.VAR_ROUTE103_STATE] = 1
  self.scriptVars[Game3.VAR_OLDALE_STATE] = 1
  if npc then npc.hidden = true; npc.defeated = true end
  if self.battle then
    self.battle.afterText = ("%s: Let's go back to PROF. BIRCH's lab!"):format(
      self:rivalName())
  end
end

function Game3:talkRival(npc)
  if not self:isRivalNpc(npc) then return false end
  if self:isRoute103Rival(npc) then
    return self:startRivalBattle(npc)
  end
  if not self:isLabRival(npc) then return false end
  local species = self.rivalSpecies
  if not species then
    local lead = self.party and self.party[1]
    species = Game3.rivalStarterSpecies(lead and lead.species)
    self.rivalSpecies = species
  end
  local name = self:rivalName()
  if not self.rivalTookStarter then
    self.rivalTookStarter = true
    self:addItem(Game3.ITEM_POKE_BALL, 5)
    self.field = {
      kind = "talk",
      text = ("%s: I'll take this %s!"):format(name, self:speciesName(species)),
    }
    return true
  end
  self.field = {
    kind = "talk",
    text = ("%s: Where should I go next?"):format(name),
  }
  return true
end

function Game3:isStarterGiver(npc)
  if not npc then return false end
  local gid = npc.graphicsId or 0
  return gid == Game3.GFX_BIRCHS_BAG or gid == Game3.GFX_BIRCH
end

function Game3:giveMon(species, level)
  species = tonumber(species)
  if not species or species < 1 then return false end
  local mon = self:makeMon(species, level or Game3.STARTER_LEVEL)
  if not self:addToParty(mon) then
    if Game3.isStarterSpecies(species) then return false end
    if not self:sendToPc(mon) then return false end
    return true, mon
  end
  if Game3.isStarterSpecies(species) then
    self.flags = self.flags or {}
    self.flags[Game3.FLAG_SYS_POKEMON_GET] = true
    self.flags[Game3.FLAG_RESCUED_BIRCH] = true
    self.flags[Game3.FLAG_HIDE_BIRCH_STARTERS_BAG] = true
    self.rivalSpecies = Game3.rivalStarterSpecies(species)
    self.scriptVars = self.scriptVars or {}
    self.scriptVars[Game3.VAR_STARTER_MON] = Game3.starterIndex(species)
  end
  return true, mon
end

function Game3:giveStarter(species, npc)
  if self:hasStarter() then return false, "You already have a POKeMON." end
  local ok, mon = self:giveMon(species, Game3.STARTER_LEVEL)
  if not ok then return false, "The party is full." end
  if npc and (npc.graphicsId or 0) == Game3.GFX_BIRCHS_BAG then
    npc.hidden = true
    self.pendingChase = true
    self.scriptVars = self.scriptVars or {}
    self.scriptVars[Game3.VAR_BIRCH_LAB_STATE] = 2
    self.scriptVars[Game3.VAR_ROUTE101_STATE] = 3
  else
    self:revealBirchLab()
  end
  return true, ("Got %s!"):format((mon and mon.name) or self:speciesName(species))
end

function Game3:openStarterMenu(npc)
  self.field = {
    kind = "starter",
    cursor = 1,
    npc = npc,
  }
  return true
end

function Game3:openMartList(list)
  if type(list) ~= "table" or #list < 1 then
    list = { Game3.ITEM_POKE_BALL }
  end
  self.field = {
    kind = "mart",
    items = list,
    cursor = 0,
    note = ("$%d"):format(self.money or 0),
  }
  return true
end

function Game3:openMart(npc)
  return self:openMartList(npc and npc.mart)
end

function Game3.trainerPay(b)
  if not b then return 0 end
  local n = #(b.trainerParty or {})
  if n < 1 then n = 1 end
  local level = (b.enemy and b.enemy.level) or 5
  return 16 * level * n
end

function Game3:markHealPoint()
  if not (self.map and self.map.id) then return false end
  self.lastHeal = {
    mapId = self.map.id,
    x = self.playerX or 0,
    y = self.playerY or 0,
  }
  return true
end

function Game3:startMap()
  local pack = (self.data or {}).maps or {}
  return pack.maps and pack.maps[pack.start]
end

function Game3:warpToHeal()
  local dest, x, y
  local heal = self.lastHeal
  if heal and heal.mapId then
    dest = self:lookupMapById(heal.mapId)
    x, y = heal.x or 0, heal.y or 0
    -- Heal locations are towns / cities / the bedroom. special 0 on
    -- Route 101 used to stamp the starter bag tile as lastHeal.
    if dest and dest.mapType == Game3.MAP_TYPE_ROUTE then
      dest = nil
    end
  end
  -- Early-game blackout (no Center yet, or bedroom lookup failed at
  -- setrespawn) must land in the player's room, not the start map
  -- (truck / Route 101).
  if not dest then
    dest = self:playerBedroomMap()
    if dest then
      x, y = Game3.HEAL_BEDROOM_X, Game3.HEAL_BEDROOM_Y
      if not Game3.walkable(dest, x, y) then
        local spawn = dest.spawn or {}
        x, y = spawn.x or x, spawn.y or y
      end
    end
  end
  if not dest then
    dest = self:startMap()
    if dest and Game3.isTruckMap(dest) then
      dest = self:littlerootTownMap() or dest
    end
    local spawn = dest and dest.spawn or {}
    x, y = spawn.x or 0, spawn.y or 0
  end
  if not dest then return false end
  self.surfing = nil
  self.climbing = nil
  self.diving = nil
  self.bike = nil
  self:enterMap(dest, x or 0, y or 0, false)
  return true
end

-- pokeruby sub_8053678: Dig / Escape Rope land on warp4.
function Game3:warpToEscape()
  local w = self.escapeWarp
  local dest
  if w then
    dest = self:lookupMapById(w.mapId)
    if not dest then dest = self:lookupMap(w.mapGroup, w.mapNum) end
  end
  if not dest then return self:warpToHeal() end
  self.surfing = nil
  self.climbing = nil
  self.diving = nil
  self.bike = nil
  self:enterMap(dest, w.x or 0, w.y or 0, true)
  return true
end

function Game3:blackout()
  local chase = self.battle and self.battle.chase
  local scripted = chase and self.scriptWait
  self:healParty()
  self.phase = "play"
  self.battle = nil
  if scripted then
    self:endScriptWait()
    return
  end
  if chase then
    self:finishBirchChase()
    return
  end
  self:warpToHeal()
end

function Game3:startWildBattle(species, level)
  local enemy = self:makeMon(species, level)
  self:markSeen(species)
  local player = self:firstHealthy()
  if not player then return false end
  self:recalcStats(player)
  player.hp = math.min(player.hp or player.maxHp, player.maxHp)
  player.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  player.focusEnergy = nil
  player.mudSport = nil
  player.waterSport = nil
  player.rage = nil
  player.leechSeed = nil
  player.leechSeedSlot = nil
  player.leechSeedFrom = nil
  player.foresight = nil
  if type(player.moves) ~= "table" or #player.moves < 1 then
    player.moves = self:movesFor(player.species, player.level)
  end
  self.walkCooldown = 0
  self.phase = "battle"
  self.battle = {
    kind = "intro",
    cursor = 0,
    fightCursor = 0,
    partyCursor = 0,
    player = player,
    enemy = enemy,
    text = ("Wild %s appeared!"):format(enemy.name),
    enterBoth = true,
    switchInDone = false,
    turns = 0,
    introT = 0,
    animT = 0,
  }
  self:markSentIn(player)
  return true
end

function Game3:endBattle()
  local chase = self.battle and self.battle.chase
  local after = self.battle and self.battle.afterText
  local scripted = self.scriptWait
  local pending = self.pendingEvo
  self.phase = "play"
  self.battle = nil
  if pending and #pending > 0 then
    self.pendingEvo = pending
    self:startPendingEvolve()
    return
  end
  if scripted then
    self:endScriptWait()
    return
  end
  if chase then
    self:finishBirchChase()
  elseif type(after) == "string" and after ~= "" then
    self.field = { kind = "talk", text = after }
  end
end

-- pokeruby sPickupItems: (item, cumulative chance) pairs.  RS ignores
-- level.  The ROM stores King's Rock's threshold as 1, so roll 99 walks
-- off the table; 100 makes that 1% slot work.
Game3.PICKUP_ITEMS = {
  22, 30,
  23, 40,
  2, 50,
  68, 60,
  19, 70,
  24, 80,
  110, 90,
  64, 95,
  69, 99,
  187, 100,
}

function Game3.rollPickupItem(_level, roll)
  if roll == nil then roll = _level end
  roll = tonumber(roll) or 0
  if roll < 0 then roll = 0 elseif roll > 99 then roll = 99 end
  local pairs = Game3.PICKUP_ITEMS
  for i = 1, #pairs, 2 do
    if pairs[i + 1] > roll then
      return pairs[i]
    end
  end
  return pairs[#pairs - 1]
end

function Game3:tryPickup()
  local texts = {}
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon and (mon.species or 0) > 0
        and self:hasAbility(mon, Game3.ABILITY_PICKUP) then
      if self:rand(10) == 1 then
        local id = Game3.rollPickupItem(mon.level or 1, self:rand(100) - 1)
        if id then
          self:addItem(id, 1)
          texts[#texts + 1] = ("%s found a %s!"):format(
            mon.name, self:itemName(id))
        end
      end
    end
  end
  return texts
end

function Game3:finishBattle()
  local b = self.battle
  if not b or b.pickupDone then
    self:endBattle()
    return
  end
  b.pickupDone = true
  local lines = self:tryPickup()
  if #lines > 0 then
    b.kind = "text"
    b.queue = lines
    b.qi = 1
    b.text = lines[1]
    return
  end
  self:endBattle()
end

function Game3:dismissIntro()
  local b = self.battle
  if not b then return end
  local lines = {}
  local function addEnter(mon, foe)
    if not mon or not foe then return end
    local extra = self:activateEnter(mon, foe)
    for i = 1, #extra do lines[#lines + 1] = extra[i] end
  end
  if not b.switchInDone then
    b.switchInDone = true
    addEnter(b.enemy, b.player or b.player2)
    addEnter(b.enemy2, b.player2 or b.player)
    if b.enterBoth then
      addEnter(b.player, b.enemy or b.enemy2)
      addEnter(b.player2, b.enemy2 or b.enemy)
    end
    b.enterBoth = nil
  end
  if #lines > 0 then
    b.queue = lines
    b.qi = 1
    b.kind = "text"
    b.text = lines[1]
  else
    b.kind = "menu"
    b.text = nil
  end
  self:tryWallyTutorialAction()
end

function Game3:recalcStats(mon)
  local row = self:speciesRow(mon.species) or {}
  local level = mon.level or 1
  local ivs = mon.ivs or Game3.zeroIvs()
  local pid = mon.pid or 0
  local oldMax = mon.maxHp or 0
  mon.maxHp = Game3.statHP(row.hp or 45, level, ivs.hp, mon.hpEv)
  mon.atk = Game3.statOther(row.atk or 49, level, ivs.atk,
    Game3.natureMul(pid, Game3.STAT_ATK), mon.atkEv)
  mon.def = Game3.statOther(row.def or 49, level, ivs.def,
    Game3.natureMul(pid, Game3.STAT_DEF), mon.defEv)
  mon.spe = Game3.statOther(row.spe or 45, level, ivs.spe,
    Game3.natureMul(pid, Game3.STAT_SPE), mon.speEv)
  mon.spa = Game3.statOther(row.spa or 65, level, ivs.spa,
    Game3.natureMul(pid, Game3.STAT_SPA), mon.spaEv)
  mon.spd = Game3.statOther(row.spd or 65, level, ivs.spd,
    Game3.natureMul(pid, Game3.STAT_SPD), mon.spdEv)
  local delta = (mon.maxHp or 0) - oldMax
  local hp = (mon.hp or 0) + delta
  if (mon.hp or 0) <= 0 then
    mon.hp = 0
  else
    mon.hp = math.max(1, hp)
    if mon.hp > mon.maxHp then mon.hp = mon.maxHp end
  end
end

function Game3.isHmMove(id)
  return Game3.HM_MOVES[tonumber(id) or 0] == true
end

function Game3:knowsMove(mon, id)
  local moves = mon and mon.moves or {}
  for i = 1, #moves do
    if moves[i] and moves[i].id == id then return true end
  end
  return false
end

function Game3:partyKnowsMove(id)
  local party = self.party or {}
  for i = 1, #party do
    if self:knowsMove(party[i], id) then return true end
  end
  return false
end

function Game3:hasBadge(n)
  n = tonumber(n) or 0
  if n < 1 or n > 8 then return false end
  return self.flags and self.flags[Game3.FLAG_BADGE01_GET + n - 1] == true
end

function Game3:facingCell()
  local dx, dy = Game3.deltaFromFacing(self.facing or "south")
  return (self.playerX or 0) + dx, (self.playerY or 0) + dy
end

function Game3:npcInFront()
  local x, y = self:facingCell()
  return self:npcAt(self.map, x, y)
end

function Game3:cutGrassAround(cx, cy)
  local n = 0
  for dy = -1, 1 do
    for dx = -1, 1 do
      local x, y = cx + dx, cy + dy
      if Game3.isLandGrass(self:behaviorAt(self.map, x, y)) then
        self:writeMetatile(x, y, 0)
        n = n + 1
      end
    end
  end
  return n > 0
end

function Game3:useCut()
  if not self:partyKnowsMove(Game3.MOVE_CUT) then
    return false, "No one in your party knows CUT."
  end
  if not self:hasBadge(1) then
    return false, "You need the STONE BADGE to use CUT."
  end
  local npc = self:npcInFront()
  if npc and npc.graphicsId == Game3.GFX_CUTTABLE_TREE then
    self:removeObject(npc.localId)
    return true, "Used CUT!"
  end
  local x, y = self:facingCell()
  if self:cutGrassAround(x, y) then
    return true, "Used CUT!"
  end
  return false, "You can't use that here!"
end

function Game3:useRockSmash()
  if not self:partyKnowsMove(Game3.MOVE_ROCK_SMASH) then
    return false, "No one in your party knows ROCK SMASH."
  end
  if not self:hasBadge(3) then
    return false, "You need the DYNAMO BADGE to use ROCK SMASH."
  end
  local npc = self:npcInFront()
  if npc and npc.graphicsId == Game3.GFX_BREAKABLE_ROCK then
    self:removeObject(npc.localId)
    self:tryRockSmashEncounter()
    return true, "Used ROCK SMASH!"
  end
  return false, "You can't use that here!"
end

function Game3:canStep(map, x, y)
  map = map or self.map
  local b = self:behaviorAt(map, x, y)
  if Game3.isWaterfall(b) then
    return self.surfing and self.climbing and true or false
  end
  if Game3.isSurfable(b) then
    return self.surfing and true or false
  end
  return Game3.walkable(map, x, y)
end

-- pokeruby GetLedgeJumpDirection: walking into a solid jump metatile
-- facing that way hops two tiles, landing past the ledge.
function Game3.ledgeDelta(behavior)
  local b = behavior or 0
  if b == Game3.MB_JUMP_EAST then return 1, 0 end
  if b == Game3.MB_JUMP_WEST then return -1, 0 end
  if b == Game3.MB_JUMP_NORTH then return 0, -1 end
  if b == Game3.MB_JUMP_SOUTH then return 0, 1 end
  if b == Game3.MB_JUMP_NORTHEAST then return 1, -1 end
  if b == Game3.MB_JUMP_NORTHWEST then return -1, -1 end
  if b == Game3.MB_JUMP_SOUTHEAST then return 1, 1 end
  if b == Game3.MB_JUMP_SOUTHWEST then return -1, 1 end
end

function Game3:tryLedgeHop(map, dx, dy)
  map = map or self.map
  if not map or self.surfing then return false end
  local nx = self.playerX + dx
  local ny = self.playerY + dy
  local jx, jy = Game3.ledgeDelta(self:behaviorAt(map, nx, ny))
  if not jx or jx ~= dx or jy ~= dy then return false end
  local lx = self.playerX + dx * 2
  local ly = self.playerY + dy * 2
  if self:npcAt(map, lx, ly) then return false end
  if not self:canStep(map, lx, ly) then return false end
  local ox, oy = self.playerX, self.playerY
  self.walkFromX, self.walkFromY = ox, oy
  self.playerX, self.playerY = lx, ly
  self.walkDuration = (self:walkPeriod() or Game3.WALK_PERIOD) * 2
  self.walkCooldown = self.walkDuration
  self.hopping = true
  self:clampCamera()
  if self.ignoreWarp and not Game3.warpAt(map, lx, ly) then
    self.ignoreWarp = false
  end
  self:runStepCallback(ox, oy)
  self:tickWalkCounters()
  self:tryCoordEvent(lx, ly)
  return true
end

function Game3:strengthOn()
  return self.flags and self.flags[Game3.FLAG_SYS_USE_STRENGTH] == true
end

function Game3:pushBoulder(npc, dx, dy)
  if not npc then return false end
  local map = self.map
  local nx, ny = npc.x + dx, npc.y + dy
  if not Game3.walkable(map, nx, ny) then return false end
  if self:npcAt(map, nx, ny) then return false end
  if Game3.warpAt(map, nx, ny) then return false end
  npc.fromX, npc.fromY = npc.x, npc.y
  npc.x, npc.y = nx, ny
  npc.walkDuration = Game3.WALK_PERIOD
  npc.cooldown = Game3.WALK_PERIOD
  return true
end

function Game3:isDarkMap(map)
  if map and map ~= self.map then
    return map.cave and true or false
  end
  return (self.flashLevel or 0) > 0
end

function Game3:setDefaultFlashLevel(map)
  map = map or self.map
  if not map or not map.cave then
    self.flashLevel = 0
  elseif self.flags and self.flags[Game3.FLAG_SYS_USE_FLASH] then
    self.flashLevel = 1
  else
    self.flashLevel = Game3.MAX_FLASH_LEVEL
  end
end

function Game3:setFlashLevel(level)
  level = tonumber(level) or 0
  if level < 0 or level > Game3.MAX_FLASH_LEVEL then
    level = 0
  end
  self.flashLevel = level
  self.flashAnim = nil
end

function Game3:flashRadius()
  local a = self.flashAnim
  if a then return a.cur or 0 end
  local level = self.flashLevel or 0
  if level < 1 then return 0 end
  return Game3.FLASH_RADII[level] or 24
end

-- pokeruby UpdateFlashLevelEffect: every other frame, radius += delta
-- (±1). Stops when cur > dest (so shrinking almost instantly finishes).
function Game3.flashAnimFrames(fromR, destR)
  fromR = tonumber(fromR) or 0
  destR = tonumber(destR) or 0
  if fromR == destR then return 0 end
  local delta = Game3.FLASH_ANIM_DELTA
  if fromR >= destR then delta = -delta end
  local cur, frames, guard = fromR, 0, 0
  while guard < 400 do
    frames = frames + 2
    cur = cur + delta
    guard = guard + 1
    if cur > destR then break end
  end
  return frames
end

function Game3:animateFlash(level)
  level = tonumber(level) or 0
  if level < 0 or level > Game3.MAX_FLASH_LEVEL then
    level = 0
  end
  local from = Game3.FLASH_RADII[self.flashLevel or 0] or 200
  local dest = Game3.FLASH_RADII[level] or 200
  if from == dest then
    self.flashLevel = level
    return
  end
  local delta = Game3.FLASH_ANIM_DELTA
  if from >= dest then delta = -delta end
  self.flashAnim = {
    cur = from,
    dest = dest,
    destLevel = level,
    delta = delta,
    phase = 0,
  }
  self:beginScriptWait()
end

function Game3:finishFlashAnim()
  local a = self.flashAnim
  if not a then return false end
  self.flashLevel = a.destLevel or 0
  self.flashAnim = nil
  if self:scriptWaiting() then
    return self:endScriptWait()
  end
  return false
end

function Game3:stepFlashAnim()
  local a = self.flashAnim
  if not a then return false end
  if (a.phase or 0) == 0 then
    a.phase = 1
    return true
  end
  a.phase = 0
  a.cur = (a.cur or 0) + (a.delta or 1)
  if a.cur > (a.dest or 0) then
    self:finishFlashAnim()
    return false
  end
  return true
end

function Game3:stepFlashAnimDt(dt)
  if not self.flashAnim then return end
  self.flashAcc = (self.flashAcc or 0) + (dt or 0)
  local add = math.floor(self.flashAcc * 60 + 1e-6)
  self.flashAcc = self.flashAcc - add / 60
  local i = 1
  while i <= add do
    if not self:stepFlashAnim() then break end
    i = i + 1
  end
end

function Game3:driveFlashAnim()
  local n = 0
  while self.flashAnim and n < 500 do
    self:stepFlashAnim()
    n = n + 1
  end
end

function Game3:useSurf()
  if not self:partyKnowsMove(Game3.MOVE_SURF) then
    return false, "No one in your party knows SURF."
  end
  if not self:hasBadge(5) then
    return false, "You need the BALANCE BADGE to use SURF."
  end
  local x, y = self:facingCell()
  if not Game3.isSurfStart(self:behaviorAt(self.map, x, y)) then
    return false, "You can't use that here!"
  end
  self.bike = nil
  self.surfing = true
  local dx, dy = Game3.deltaFromFacing(self.facing or "south")
  if not self:tryWalk(dx, dy) then
    self.surfing = nil
    return false, "You can't use that here!"
  end
  return true, "Used SURF!"
end

function Game3:useStrength()
  if not self:partyKnowsMove(Game3.MOVE_STRENGTH) then
    return false, "No one in your party knows STRENGTH."
  end
  if not self:hasBadge(4) then
    return false, "You need the HEAT BADGE to use STRENGTH."
  end
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SYS_USE_STRENGTH] = true
  return true, "Used STRENGTH!"
end

function Game3:useFlash()
  if not self:partyKnowsMove(Game3.MOVE_FLASH) then
    return false, "No one in your party knows FLASH."
  end
  if not self:hasBadge(2) then
    return false, "You need the KNUCKLE BADGE to use FLASH."
  end
  if (self.flashLevel or 0) ~= Game3.MAX_FLASH_LEVEL then
    return false, "You can't use that here!"
  end
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SYS_USE_FLASH] = true
  self:setFlashLevel(1)
  return true, "Used FLASH!"
end

function Game3:useWaterfall()
  if not self:partyKnowsMove(Game3.MOVE_WATERFALL) then
    return false, "No one in your party knows WATERFALL."
  end
  if not self:hasBadge(8) then
    return false, "You need the RAIN BADGE to use WATERFALL."
  end
  if not self.surfing then
    return false, "You can't use that here!"
  end
  local x, y = self:facingCell()
  if not Game3.isWaterfall(self:behaviorAt(self.map, x, y)) then
    return false, "You can't use that here!"
  end
  self.climbing = true
  local dx, dy = Game3.deltaFromFacing(self.facing or "south")
  if not self:tryWalk(dx, dy) then
    self.climbing = nil
    return false, "You can't use that here!"
  end
  return true, "Used WATERFALL!"
end

function Game3:isUnderwater(map)
  map = map or self.map
  return map and (map.mapType or 0) == Game3.MAP_TYPE_UNDERWATER
end

function Game3:connectionByDir(map, dir)
  map = map or self.map
  for i = 1, #(map and map.connections or {}) do
    local c = map.connections[i]
    if c and c.dir == dir then return c end
  end
end

function Game3:warpDive(dir)
  local c = self:connectionByDir(self.map, dir)
  if not c then return false end
  local dest = self:lookupMap(c.mapGroup, c.mapNum)
  if not dest then return false end
  self:enterMap(dest, self.playerX or 0, self.playerY or 0, false)
  return true
end

function Game3:useDive()
  if not self:partyKnowsMove(Game3.MOVE_DIVE) then
    return false, "No one in your party knows DIVE."
  end
  if not self:hasBadge(7) then
    return false, "You need the MIND BADGE to use DIVE."
  end
  if self:isUnderwater() then
    if Game3.isUnableToEmerge(self:behaviorAt(self.map, self.playerX, self.playerY)) then
      return false, "You can't use that here!"
    end
    if not self:warpDive("emerge") then
      return false, "You can't use that here!"
    end
    self.diving = nil
    self.surfing = true
    self.climbing = nil
    return true, "Used DIVE!"
  end
  if not self.surfing then
    return false, "You can't use that here!"
  end
  if not Game3.isDiveable(self:behaviorAt(self.map, self.playerX, self.playerY)) then
    return false, "You can't use that here!"
  end
  if not self:warpDive("dive") then
    return false, "You can't use that here!"
  end
  self.diving = true
  self.surfing = true
  self.climbing = nil
  return true, "Used DIVE!"
end

function Game3.rodKind(id)
  if id == Game3.ITEM_OLD_ROD then return Game3.OLD_ROD end
  if id == Game3.ITEM_GOOD_ROD then return Game3.GOOD_ROD end
  if id == Game3.ITEM_SUPER_ROD then return Game3.SUPER_ROD end
end

function Game3:canFish()
  if not self.map then return false end
  if self:isUnderwater() then return false end
  local x, y = self:facingCell()
  local b = self:behaviorAt(self.map, x, y)
  if Game3.isWaterfall(b) then return false end
  return Game3.isSurfable(b)
end

function Game3:startFishingWild(rod)
  local enc = self:encountersFor()
  local fish = enc and enc.fish
  if not (fish and fish.slots and #fish.slots > 0) then return false end
  if not self:firstHealthy() then return false end
  return self:startWildFrom(fish, Game3.chooseFishSlot(rod, self:gbaRandom() % 100), true)
end

function Game3:fishingTick(f, joyA)
  local step = f.step or 0
  if step == Game3.FISH_WAIT then
    f.frames = (f.frames or 0) + 1
    if f.frames >= 60 then f.step = Game3.FISH_START_ROUND end
    return false
  end
  if step == Game3.FISH_START_ROUND then
    f.step = Game3.FISH_DOTS
    f.frames = 0
    f.numDots = 0
    local randVal = self:gbaRandom() % 10
    local need = randVal + 1
    if (f.roundsPlayed or 0) == 0 then need = randVal + 4 end
    if need >= 10 then need = 10 end
    f.dotsRequired = need
    f.dotsLine = ""
    f.text = ""
    return true
  end
  if step == Game3.FISH_DOTS then
    if joyA then
      if (f.roundsPlayed or 0) ~= 0 then
        f.step = Game3.FISH_GOT_AWAY
      else
        f.step = Game3.FISH_NO_BITE
      end
      return true
    end
    f.frames = (f.frames or 0) + 1
    if f.frames >= 20 then
      f.frames = 0
      if (f.numDots or 0) >= (f.dotsRequired or 1) then
        f.step = step + 1
        if (f.roundsPlayed or 0) ~= 0 then f.step = f.step + 1 end
        f.roundsPlayed = (f.roundsPlayed or 0) + 1
      else
        f.dotsLine = (f.dotsLine or "") .. Game3.FISH_DOT
        f.numDots = (f.numDots or 0) + 1
        f.text = f.dotsLine
      end
    end
    return false
  end
  if step == 5 then
    f.step = 6
    if (not self:hasFishingMons()) or ((self:gbaRandom() % 2) == 1) then
      f.step = Game3.FISH_NO_BITE
    end
    return true
  end
  if step == 6 then
    f.text = Game3.FISH_TEXT_BITE
    f.step = 7
    f.frames = 0
    return false
  end
  if step == 7 then
    f.frames = (f.frames or 0) + 1
    local limit = Game3.FISH_REEL[f.rod or 0] or 36
    if f.frames >= limit then
      f.step = Game3.FISH_GOT_AWAY
    elseif joyA then
      f.step = 8
    end
    return false
  end
  if step == 8 then
    f.step = 9
    local played = f.roundsPlayed or 0
    if played < (f.minRounds or 1) then
      f.step = Game3.FISH_START_ROUND
    elseif played < 2 then
      local extra = Game3.FISH_EXTRA[f.rod or 0]
      extra = extra and extra[played] or 0
      if extra > (self:gbaRandom() % 100) then
        f.step = Game3.FISH_START_ROUND
      end
    end
    return false
  end
  if step == 9 then
    f.text = Game3.FISH_TEXT_HOOK
    f.step = 10
    f.frames = 0
    return false
  end
  if step == 10 then
    if joyA then
      local rod = f.rod or 0
      self.field = nil
      self:startFishingWild(rod)
    end
    return false
  end
  if step == Game3.FISH_NO_BITE then
    f.text = Game3.FISH_TEXT_NIBBLE
    f.step = Game3.FISH_SHOW_RESULT
    return true
  end
  if step == Game3.FISH_GOT_AWAY then
    f.text = Game3.FISH_TEXT_AWAY
    f.step = Game3.FISH_SHOW_RESULT
    return true
  end
  if step == Game3.FISH_SHOW_RESULT then
    f.step = 14
    return false
  end
  if step == 14 then
    f.step = 15
    return false
  end
  if step == 15 then
    if joyA then self:closeField() end
    return false
  end
  return false
end

function Game3:pumpFishing(joyA)
  local f = self.field
  local guard = 0
  while f and f.kind == "fishing" do
    guard = guard + 1
    if guard > 8 then break end
    if not self:fishingTick(f, joyA) then break end
    f = self.field
  end
end

function Game3:stepFishing(dt)
  local f = self.field
  if not (f and f.kind == "fishing") then return end
  local joyA = f.joyA and true or false
  f.joyA = nil
  if not joyA and Input and Input.pressed and Input.wasPressed then
    joyA = Input:wasPressed("a") and true or false
  end
  f.acc = (f.acc or 0) + (dt or 0)
  local add = math.floor(f.acc * 60 + 1e-6)
  f.acc = f.acc - add / 60
  if add < 1 then
    if joyA then add = 1 else return end
  end
  local i = 1
  while i <= add do
    self:pumpFishing(joyA)
    joyA = false
    if not (self.field and self.field.kind == "fishing") then break end
    if self.phase ~= "play" then break end
    i = i + 1
  end
end

function Game3:driveFishingDots()
  self:stepFishing(61 / 60)
  local n = 0
  while self.field and self.field.kind == "fishing"
      and self.field.step == Game3.FISH_DOTS do
    self:stepFishing(20 / 60)
    n = n + 1
    if n > 24 then break end
  end
  if self.field and self.field.kind == "fishing" and self.field.step == 5 then
    self:stepFishing(1 / 60)
  end
end

function Game3:driveFishingA()
  local f = self.field
  if not (f and f.kind == "fishing") then return end
  f.joyA = true
  self:stepFishing(1 / 60)
end

function Game3:driveFishingHook()
  self:driveFishingDots()
  self:driveFishingA()
  self:stepFishing(1 / 60)
  self:stepFishing(1 / 60)
  self:driveFishingA()
end

function Game3:useRod(id)
  local kind = Game3.rodKind(id)
  if kind == nil then
    return false, "You can't use that here!"
  end
  if not self:canFish() then
    return false, "You can't use that here!"
  end
  local span = Game3.FISH_MIN_SPAN[kind] or 1
  local minRounds = (Game3.FISH_MIN_BASE[kind] or 1) + (self:gbaRandom() % span)
  self.field = {
    kind = "fishing",
    rod = kind,
    step = Game3.FISH_WAIT,
    frames = 0,
    acc = 0,
    roundsPlayed = 0,
    minRounds = minRounds,
    numDots = 0,
    dotsRequired = 0,
    dotsLine = "",
    text = "",
  }
  return true
end

function Game3.canBikeOn(map)
  if not map then return false end
  local t = map.mapType or 0
  if t == Game3.MAP_TYPE_INDOOR then return false end
  if t == Game3.MAP_TYPE_SECRET_BASE then return false end
  if t == Game3.MAP_TYPE_UNDERWATER then return false end
  return true
end

function Game3:wantRun()
  if self.bike or self.surfing or self.diving then return false end
  if not (self.flags and self.flags[Game3.FLAG_SYS_B_DASH]) then return false end
  return Input:isDown("b")
end

function Game3:walkPeriod()
  if self.bike == "mach" then return Game3.MACH_PERIOD end
  if self.running then return Game3.RUN_PERIOD end
  return Game3.WALK_PERIOD
end

function Game3:useBike(id)
  local kind
  if id == Game3.ITEM_MACH_BIKE then
    kind = "mach"
  elseif id == Game3.ITEM_ACRO_BIKE then
    kind = "acro"
  else
    return false, "You can't use that here!"
  end
  local name = kind == "mach" and "MACH BIKE" or "ACRO BIKE"
  if self.surfing or self:isUnderwater() then
    return false, "You can't use that here!"
  end
  if self.bike == kind then
    self.bike = nil
    return true, ("Got off the %s."):format(name)
  end
  if not Game3.canBikeOn(self.map) then
    return false, "You can't use that here!"
  end
  self.bike = kind
  self.running = nil
  return true, ("Got on the %s."):format(name)
end

function Game3.flyDestFor(map)
  if not map then return nil end
  local id = type(map) == "table" and map.id or map
  return Game3.FLY_BY_ID[id]
end

function Game3.canFlyFrom(map)
  if not map then return false end
  local t = map.mapType or 0
  return t == Game3.MAP_TYPE_TOWN
    or t == Game3.MAP_TYPE_CITY
    or t == Game3.MAP_TYPE_ROUTE
    or t == Game3.MAP_TYPE_OCEAN_ROUTE
end

function Game3:repelBlocks(level)
  if (self.repelSteps or 0) < 1 then return false end
  local mon = self:firstHealthy()
  if not mon then return false end
  return (level or 1) <= (mon.level or 1)
end

function Game3:tickWalkCounters()
  self:tickRepel()
  self:tickDaycare()
  self:tickEggCycles()
  self:tickHappinessSteps()
end

function Game3:tickRepel()
  local n = self.repelSteps or 0
  if n < 1 then return end
  n = n - 1
  if n < 1 then
    self.repelSteps = nil
    if not self.field then
      self.field = { kind = "talk", text = "REPEL's effect wore off!" }
    end
  else
    self.repelSteps = n
  end
end

function Game3:useRepel(id)
  local steps = Game3.REPEL_STEPS[id]
  if not steps then return false, "You can't use that here!" end
  if not self:takeItem(id, 1) then
    return false, "You can't use that here!"
  end
  self.repelSteps = steps
  return true, ("Used the %s."):format(self:itemName(id))
end

function Game3.canEscapeFrom(map)
  if not map then return false end
  local t = map.mapType or 0
  if t == Game3.MAP_TYPE_UNDERWATER then return false end
  if map.allowEscaping then return true end
  if map.cave then return true end
  return t == Game3.MAP_TYPE_UNDERGROUND
end

function Game3:useEscapeRope()
  if self.surfing or self.diving or self:isUnderwater() then
    return false, "You can't use that here!"
  end
  if not Game3.canEscapeFrom(self.map) then
    return false, "You can't use that here!"
  end
  if not self:takeItem(Game3.ITEM_ESCAPE_ROPE, 1) then
    return false, "You can't use that here!"
  end
  self:warpToEscape()
  return true, "Used the ESCAPE ROPE!"
end

function Game3.canTeleportFrom(map)
  return Game3.canFlyFrom(map)
end

function Game3:useTeleport()
  if not self:partyKnowsMove(Game3.MOVE_TELEPORT) then
    return false, "No one in your party knows TELEPORT."
  end
  if not Game3.canTeleportFrom(self.map) then
    return false, "You can't use that here!"
  end
  self:warpToHeal()
  return true, "Used TELEPORT!"
end

function Game3:useDig()
  if not self:partyKnowsMove(Game3.MOVE_DIG) then
    return false, "No one in your party knows DIG."
  end
  if self.surfing or self.diving or self:isUnderwater() then
    return false, "You can't use that here!"
  end
  if not Game3.canEscapeFrom(self.map) then
    return false, "You can't use that here!"
  end
  self:warpToEscape()
  return true, "Used DIG!"
end

function Game3:usePartyFieldMove(mon)
  if not mon then return false, "No POKeMON." end
  if self:knowsMove(mon, Game3.MOVE_TELEPORT)
      and Game3.canTeleportFrom(self.map) then
    return self:useTeleport()
  end
  if self:knowsMove(mon, Game3.MOVE_DIG) and Game3.canEscapeFrom(self.map)
      and not (self.surfing or self.diving or self:isUnderwater()) then
    return self:useDig()
  end
  if self:knowsMove(mon, Game3.MOVE_SWEET_SCENT) then
    return self:useSweetScent()
  end
  if self:knowsMove(mon, Game3.MOVE_SECRET_POWER) then
    return self:useSecretPower()
  end
  if self:knowsMove(mon, Game3.MOVE_TELEPORT)
      or self:knowsMove(mon, Game3.MOVE_DIG) then
    return false, "You can't use that here!"
  end
  return false, "No moves to use here."
end

function Game3:hasPartyFieldMove(mon)
  local list = Game3.PARTY_FIELD_MOVES
  for i = 1, #list do
    if self:knowsMove(mon, list[i].id) then return true end
  end
  return false
end

function Game3:partyFieldMoves(mon)
  local moves = {}
  local list = Game3.PARTY_FIELD_MOVES
  for i = 1, #list do
    local row = list[i]
    if self:knowsMove(mon, row.id) then
      moves[#moves + 1] = row.name
    end
  end
  return moves
end

function Game3:partyActions(mon)
  local actions = { "SUMMARY", "SWITCH" }
  if mon and not mon.isEgg then
    actions[#actions + 1] = "ITEM"
  end
  local moves = self:partyFieldMoves(mon)
  for i = 1, #moves do
    actions[#actions + 1] = moves[i]
  end
  actions[#actions + 1] = "CANCEL"
  return actions
end

function Game3:partyItemActions(mon)
  local actions = { "GIVE" }
  if mon and mon.item then actions[#actions + 1] = "TAKE" end
  actions[#actions + 1] = "CANCEL"
  return actions
end

function Game3:canGiveHeld(id)
  id = tonumber(id) or 0
  if id < 1 then return false end
  local pocket = self:itemPocket(id)
  if pocket == Game3.POCKET_KEY or pocket == Game3.POCKET_TMHM then
    return false
  end
  return true
end

function Game3:giveHeldItem(monIndex, itemId)
  local mon = (self.party or {})[monIndex]
  if not mon or mon.isEgg then
    return false, "It won't have any effect."
  end
  if not self:canGiveHeld(itemId) then
    return false, "This can't be given."
  end
  if not self:takeItem(itemId, 1) then
    return false, "You have none left!"
  end
  local old = mon.item
  mon.item = itemId
  if old then self:addItem(old, 1) end
  return true, ("%s was given the %s to hold."):format(
    mon.name or "POKeMON", self:itemName(itemId))
end

function Game3:takeHeldItem(monIndex)
  local mon = (self.party or {})[monIndex]
  local id = mon and mon.item
  if not id then
    return false, ("%s isn't holding anything."):format(
      (mon and mon.name) or "POKeMON")
  end
  self:addItem(id, 1)
  mon.item = nil
  return true, ("Received the %s from %s."):format(
    self:itemName(id), mon.name or "POKeMON")
end

function Game3:tickHeldItem(mon)
  if not mon or (mon.hp or 0) <= 0 then return {} end
  local id = mon.item
  if not id then return {} end
  local texts = {}
  local amount = self:healAmount(id)
  local clears = self:statusHeal(id)
  local used = false
  if amount and (mon.hp or 0) * 2 <= (mon.maxHp or 0) then
    local heal = math.min(amount, (mon.maxHp or 0) - (mon.hp or 0))
    if heal > 0 then
      mon.hp = (mon.hp or 0) + heal
      texts[#texts + 1] = ("The %s restored %s's HP!"):format(
        self:itemName(id), mon.name or "POKeMON")
      used = true
    end
  end
  if not used and clears and mon.status then
    if clears == true or mon.status == clears then
      mon.status = nil
      mon.sleepTurns = nil
      texts[#texts + 1] = ("%s's %s cured its status!"):format(
        mon.name or "POKeMON", self:itemName(id))
      used = true
    end
  end
  if used then mon.item = nil end
  return texts
end

function Game3:openBagForGive(monIndex)
  self:openBag()
  self.field.giveTo = monIndex
  return true
end

function Game3:usePartyFieldMoveNamed(mon, name)
  if name == "CUT" then return self:useCut() end
  if name == "FLASH" then return self:useFlash() end
  if name == "ROCK SMASH" then return self:useRockSmash() end
  if name == "STRENGTH" then return self:useStrength() end
  if name == "SURF" then return self:useSurf() end
  if name == "FLY" then return self:useFly() end
  if name == "DIVE" then return self:useDive() end
  if name == "WATERFALL" then return self:useWaterfall() end
  if name == "TELEPORT" then return self:useTeleport() end
  if name == "DIG" then return self:useDig() end
  if name == "SECRET POWER" then return self:useSecretPower() end
  if name == "SWEET SCENT" then return self:useSweetScent() end
  return self:usePartyFieldMove(mon)
end

function Game3:swapParty(a, b)
  local party = self.party or {}
  a, b = tonumber(a), tonumber(b)
  if not a or not b or a == b then return false end
  if not party[a] or not party[b] then return false end
  party[a], party[b] = party[b], party[a]
  return true
end

function Game3:useSweetScent()
  if not self:partyKnowsMove(Game3.MOVE_SWEET_SCENT) then
    return false, "No one in your party knows SWEET SCENT."
  end
  if self:trySweetScentEncounter() then
    return true, "Used SWEET SCENT!"
  end
  return true, "Looks like there's nothing here."
end

function Game3.isSecretBaseSpot(behavior)
  local b = behavior or 0
  return b >= Game3.MB_SECRET_BASE_SPOT_MIN
    and b <= Game3.MB_SECRET_BASE_SPOT_MAX
end

function Game3.makeSecretBaseMap()
  local w, h = 7, 6
  local grid = {}
  local behavior = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local wall = x == 0 or y == 0 or x == w - 1 or y == h - 1
      grid[#grid + 1] = wall and 1024 or 0
    end
  end
  local pc = 1 * w + 3 + 1
  grid[pc] = 1024
  behavior[pc] = Game3.MB_SECRET_BASE_PC
  return {
    id = Game3.SECRET_BASE_MAP_ID,
    name = "SECRET BASE",
    mapType = Game3.MAP_TYPE_SECRET_BASE,
    width = w,
    height = h,
    grid = grid,
    behavior = behavior,
    spawn = { x = 3, y = 4 },
    warps = { { x = 3, y = 5, warpId = 0, mapGroup = 0, mapNum = 0 } },
  }
end

function Game3:secretBaseMap()
  if type(self._secretBaseMap) ~= "table" then
    self._secretBaseMap = Game3.makeSecretBaseMap()
  end
  return self._secretBaseMap
end

function Game3:secretBaseSpot(map, x, y)
  map = map or self.map
  if not map then return nil end
  local bg = Game3.bgAt(map, x, y)
  if bg and bg.kind == Game3.BG_SECRET_BASE then
    return {
      id = tonumber(bg.secretBaseId) or 0,
      mapId = map.id,
      x = x,
      y = y,
    }
  end
  if Game3.isSecretBaseSpot(self:behaviorAt(map, x, y)) then
    return { id = 0, mapId = map.id, x = x, y = y }
  end
  return nil
end

function Game3:ownsSecretBaseAt(spot)
  local sb = self.secretBase
  if type(sb) ~= "table" or type(spot) ~= "table" then return false end
  return sb.mapId == spot.mapId and sb.x == spot.x and sb.y == spot.y
end

function Game3:isOwnedSecretBaseTile(map, x, y)
  local sb = self.secretBase
  if type(sb) ~= "table" or not map then return false end
  return map.id == sb.mapId and x == sb.x and y == sb.y
end

function Game3:setCurrentSecretBaseVar()
  local id = 0
  if type(self.secretBase) == "table" then
    id = tonumber(self.secretBase.id) or 0
  end
  self:setScriptVar(Game3.VAR_CURRENT_SECRET_BASE, id)
end

function Game3:snapshotSecretBase()
  local sb = self.secretBase
  if type(sb) ~= "table" then return nil end
  return {
    id = sb.id or 0,
    mapId = sb.mapId,
    x = sb.x or 0,
    y = sb.y or 0,
    outX = sb.outX or 0,
    outY = sb.outY or 0,
  }
end

function Game3:loadSecretBase(data)
  if type(data) ~= "table" then
    self.secretBase = nil
    self:setCurrentSecretBaseVar()
    return
  end
  self.secretBase = {
    id = tonumber(data.id) or 0,
    mapId = data.mapId,
    x = tonumber(data.x) or 0,
    y = tonumber(data.y) or 0,
    outX = tonumber(data.outX) or 0,
    outY = tonumber(data.outY) or 0,
  }
  self:setCurrentSecretBaseVar()
end

function Game3:createSecretBase(spot)
  if type(spot) ~= "table" then return false end
  self.secretBase = {
    id = tonumber(spot.id) or 0,
    mapId = spot.mapId or (self.map and self.map.id),
    x = spot.x or 0,
    y = spot.y or 0,
    outX = self.playerX or 0,
    outY = self.playerY or 0,
  }
  self:setCurrentSecretBaseVar()
  return true
end

function Game3:enterSecretBase()
  if type(self.secretBase) ~= "table" then return false end
  if self.map and self.map.id ~= Game3.SECRET_BASE_MAP_ID then
    self.secretBase.outX = self.playerX or 0
    self.secretBase.outY = self.playerY or 0
    if self.map.id then self.secretBase.mapId = self.map.id end
  end
  local dest = self:secretBaseMap()
  local spawn = dest.spawn or { x = 3, y = 4 }
  self:enterMap(dest, spawn.x, spawn.y, false)
  return true
end

function Game3:exitSecretBase()
  local sb = self.secretBase
  if type(sb) ~= "table" or not sb.mapId then return false end
  local dest = self:lookupMapById(sb.mapId)
  if not dest then return false end
  self:enterMap(dest, sb.outX or sb.x or 0, sb.outY or sb.y or 0, true)
  return true
end

function Game3:hasSecretBase()
  return type(self.secretBase) == "table" and self.secretBase.mapId ~= nil
end

function Game3:useSecretPower()
  if not self:partyKnowsMove(Game3.MOVE_SECRET_POWER) then
    return false, "No one in your party knows SECRET POWER."
  end
  local x, y = self:facingCell()
  local spot = self:secretBaseSpot(self.map, x, y)
  if not spot then
    return false, "You can't use that here!"
  end
  if self:ownsSecretBaseAt(spot) then
    self:enterSecretBase()
    return true, "Used SECRET POWER!"
  end
  if self:hasSecretBase() then
    self.field = {
      kind = "secret_base_move",
      cursor = 0,
      spot = spot,
      text = "Move your SECRET BASE here?",
    }
    return true, "Used SECRET POWER!"
  end
  self:createSecretBase(spot)
  self:enterSecretBase()
  return true, "Used SECRET POWER!"
end

function Game3:ensureDaycare()
  if type(self.daycare) ~= "table" then self.daycare = {} end
end

function Game3:daycareCount()
  self:ensureDaycare()
  local n = 0
  for i = 1, Game3.DAYCARE_SLOTS do
    if self.daycare[i] and self.daycare[i].mon then n = n + 1 end
  end
  return n
end

function Game3:daycareState()
  if (self.daycarePending or 0) ~= 0 then return 1 end
  local n = self:daycareCount()
  if n < 1 then return 0 end
  return n + 1
end

function Game3:snapshotDaycare()
  self:ensureDaycare()
  local out = {}
  for i = 1, Game3.DAYCARE_SLOTS do
    local row = self.daycare[i]
    if row and row.mon then
      out[i] = {
        mon = self:snapshotMon(row.mon),
        steps = row.steps or 0,
      }
    end
  end
  return out
end

function Game3:loadDaycare(data)
  self.daycare = {}
  if type(data) ~= "table" then return end
  for i = 1, Game3.DAYCARE_SLOTS do
    local row = data[i]
    if row and row.mon then
      local mon = self:restoreMon(row.mon)
      if mon then
        self.daycare[i] = { mon = mon, steps = tonumber(row.steps) or 0 }
      end
    end
  end
end

function Game3:tickDaycare()
  self:ensureDaycare()
  for i = 1, Game3.DAYCARE_SLOTS do
    local row = self.daycare[i]
    if row and row.mon then
      row.steps = (row.steps or 0) + 1
    end
  end
  self:maybePendingEgg()
end

function Game3:compactDaycare()
  self:ensureDaycare()
  if not (self.daycare[1] and self.daycare[1].mon)
      and self.daycare[2] and self.daycare[2].mon then
    self.daycare[1] = self.daycare[2]
    self.daycare[2] = nil
  end
end

function Game3:applyDaycareExp(mon, steps)
  if not mon then return 0 end
  local from = mon.level or 1
  if from >= Game3.DAYCARE_MAX_LEVEL then return 0 end
  local growth = mon.growth or Game3.GROWTH_MEDIUM_SLOW
  mon.exp = (mon.exp or Game3.expAtLevel(growth, from)) + (steps or 0)
  while (mon.level or 1) < Game3.DAYCARE_MAX_LEVEL do
    local need = Game3.expAtLevel(growth, (mon.level or 1) + 1)
    if (mon.exp or 0) < need then break end
    mon.level = (mon.level or 1) + 1
    self:recalcStats(mon)
    self:tryLearnLevelMoves(mon)
  end
  return (mon.level or 1) - from
end

function Game3:daycarePreview(slot)
  self:ensureDaycare()
  local row = self.daycare[slot]
  if not (row and row.mon) then return nil end
  local mon = self:cloneMon(row.mon)
  local from = mon.level or 1
  local gained = self:applyDaycareExp(mon, row.steps or 0)
  return {
    slot = slot,
    name = mon.name or "POKeMON",
    fromLevel = from,
    toLevel = mon.level or from,
    gained = gained,
    cost = Game3.DAYCARE_BASE_COST + Game3.DAYCARE_BASE_COST * gained,
  }
end

function Game3:daycareCost(slot)
  local preview = self:daycarePreview(slot)
  return preview and preview.cost or 0
end

function Game3:daycareLevelsGained(slot)
  local preview = self:daycarePreview(slot)
  return preview and preview.gained or 0
end

function Game3:depositToDaycare(index)
  self:ensureDaycare()
  if self:daycareCount() >= Game3.DAYCARE_SLOTS then
    return false, "The DAY CARE is full."
  end
  local ok, msg = self:canDeposit(index)
  if not ok then return false, msg end
  local mon = self.party[index]
  local slot
  for i = 1, Game3.DAYCARE_SLOTS do
    if not (self.daycare[i] and self.daycare[i].mon) then
      slot = i
      break
    end
  end
  if not slot then return false, "The DAY CARE is full." end
  self.daycare[slot] = { mon = self:cloneMon(mon), steps = 0 }
  table.remove(self.party, index)
  return true, ("I'll raise your %s."):format(mon.name or "POKeMON")
end

function Game3:takeFromDaycare(slot)
  self:ensureDaycare()
  slot = tonumber(slot) or 1
  local row = self.daycare[slot]
  if not (row and row.mon) then
    return false, "There's no POKeMON here."
  end
  if #(self.party or {}) >= Game3.PARTY_MAX then
    return false, "Your party's full!"
  end
  local preview = self:daycarePreview(slot)
  local cost = preview and preview.cost or Game3.DAYCARE_BASE_COST
  if (self.money or 0) < cost then
    return false, "You don't have enough money."
  end
  local mon = row.mon
  self:applyDaycareExp(mon, row.steps or 0)
  self.money = (self.money or 0) - cost
  self.daycare[slot] = nil
  self:compactDaycare()
  self:addToParty(mon)
  return true, ("Here's your %s back! You paid $%d."):format(
    mon.name or "POKeMON", cost)
end

function Game3:openDaycare()
  local n = self:daycareCount()
  local canLeave = n < Game3.DAYCARE_SLOTS and #(self.party or {}) >= 2
  local canTake = n >= 1
  if canLeave and not canTake then
    self.field = { kind = "daycare_send", cursor = 0 }
    return true
  end
  if canTake and not canLeave then
    self.field = { kind = "daycare_take", cursor = 0 }
    return true
  end
  if canLeave and canTake then
    self.field = { kind = "daycare", cursor = 0 }
    return true
  end
  self.field = { kind = "talk", text = "You don't have enough POKeMON." }
  return true
end

function Game3:daycareTakeRows()
  local list = {}
  for i = 1, Game3.DAYCARE_SLOTS do
    local row = self:daycarePreview(i)
    if row then list[#list + 1] = row end
  end
  return list
end

function Game3:genderRatioFor(species)
  local row = self:speciesRow(species) or {}
  if type(row.genderRatio) == "number" then return row.genderRatio end
  if species == Game3.SPECIES_DITTO then return 0xFF end
  if species == 280 or species == 281 or species == 282 then return 31 end
  return 127
end

function Game3:monGender(mon)
  if not mon then return Game3.MON_GENDERLESS end
  local ratio = self:genderRatioFor(mon.species)
  if ratio == 0xFF then return Game3.MON_GENDERLESS end
  if ratio == 0xFE then return Game3.MON_FEMALE end
  if ratio == 0x00 then return Game3.MON_MALE end
  if ratio > ((mon.pid or 0) % 256) then return Game3.MON_FEMALE end
  return Game3.MON_MALE
end

function Game3:eggGroupsFor(species)
  local row = self:speciesRow(species) or {}
  local a, b = row.eggGroup1, row.eggGroup2
  if type(a) == "number" then return a, type(b) == "number" and b or a end
  if species == Game3.SPECIES_DITTO then
    return Game3.EGG_GROUP_DITTO, Game3.EGG_GROUP_DITTO
  end
  if species == 280 or species == 281 or species == 282 then return 5, 5 end
  if species == 290 or species == 291 or species == 292 then return 3, 3 end
  return Game3.EGG_GROUP_NONE, Game3.EGG_GROUP_NONE
end

function Game3:eggCyclesFor(species)
  local row = self:speciesRow(species) or {}
  if type(row.eggCycles) == "number" and row.eggCycles > 0 then
    return row.eggCycles
  end
  return 20
end

function Game3:daycareCompatibility()
  self:ensureDaycare()
  local a = self.daycare[1] and self.daycare[1].mon
  local b = self.daycare[2] and self.daycare[2].mon
  if not (a and b) then return 0 end
  local a1, a2 = self:eggGroupsFor(a.species)
  local b1, b2 = self:eggGroupsFor(b.species)
  if a1 == Game3.EGG_GROUP_UNDISCOVERED or b1 == Game3.EGG_GROUP_UNDISCOVERED then
    return 0
  end
  if a1 == Game3.EGG_GROUP_DITTO and b1 == Game3.EGG_GROUP_DITTO then
    return 0
  end
  local sameOt = (a.otId or 0) == (b.otId or 0)
  if a1 == Game3.EGG_GROUP_DITTO or b1 == Game3.EGG_GROUP_DITTO then
    return sameOt and 20 or 50
  end
  local ga, gb = self:monGender(a), self:monGender(b)
  if ga == gb or ga == Game3.MON_GENDERLESS or gb == Game3.MON_GENDERLESS then
    return 0
  end
  local overlap = a1 == b1 or a1 == b2 or a2 == b1 or a2 == b2
  if not overlap then return 0 end
  if a.species == b.species then
    return sameOt and 50 or 70
  end
  return sameOt and 20 or 50
end

function Game3:daycareCompatText()
  local score = self:daycareCompatibility()
  return Game3.DAYCARE_COMPAT_TEXT[score] or Game3.DAYCARE_COMPAT_TEXT[0]
end

function Game3:clearPendingEgg()
  self.daycarePending = nil
  if self.flags then self.flags[Game3.FLAG_PENDING_DAYCARE_EGG] = nil end
end

function Game3:maybePendingEgg()
  if (self.daycarePending or 0) ~= 0 then return end
  if self:daycareCount() < 2 then return end
  local row = self.daycare[2]
  if not (row and row.mon) then return end
  if ((row.steps or 0) % 256) ~= 255 then return end
  local score = self:daycareCompatibility()
  local roll = self:rand(65536) - 1
  if score > math.floor(roll * 100 / 65535) then
    self.daycarePending = self:rand(65534)
    self.flags = self.flags or {}
    self.flags[Game3.FLAG_PENDING_DAYCARE_EGG] = true
  end
end

function Game3:prevoOf(species)
  species = tonumber(species)
  if not species then return nil end
  local function scan(from, list)
    if type(list) ~= "table" then return nil end
    for i = 1, #list do
      if list[i] and list[i].target == species then return from end
    end
  end
  for from, list in pairs(Game3.FALLBACK_EVOS) do
    local hit = scan(from, list)
    if hit then return hit end
  end
  local pack = self.data.pokemon and self.data.pokemon.byIndex
  if type(pack) == "table" then
    for from, row in pairs(pack) do
      local hit = scan(from, row and row.evolutions)
      if hit then return hit end
    end
  end
end

function Game3:eggMotherSpecies()
  self:ensureDaycare()
  local a = self.daycare[1] and self.daycare[1].mon
  local b = self.daycare[2] and self.daycare[2].mon
  if not (a and b) then return nil end
  if a.species == Game3.SPECIES_DITTO then return b.species end
  if b.species == Game3.SPECIES_DITTO then return a.species end
  if self:monGender(a) == Game3.MON_FEMALE then return a.species end
  return b.species
end

function Game3:eggSpeciesFrom(species, pid)
  species = tonumber(species) or 0
  for _ = 1, 5 do
    local pre = self:prevoOf(species)
    if not pre then break end
    species = pre
  end
  if species == 360 then species = 202 end
  if species == 298 then species = 183 end
  pid = pid or 0
  if species == 29 and math.floor(pid / 32768) % 2 == 1 then species = 32 end
  if species == 314 and math.floor(pid / 32768) % 2 == 1 then species = 313 end
  return species
end

function Game3:inheritDaycareIvs(egg)
  self:ensureDaycare()
  local a = self.daycare[1] and self.daycare[1].mon
  local b = self.daycare[2] and self.daycare[2].mon
  if not (egg and a and b) then return end
  local keys = { "hp", "atk", "def", "spa", "spd", "spe" }
  for _ = 1, 3 do
    if #keys < 1 then break end
    local key = table.remove(keys, self:rand(#keys))
    local parent = self:rand(2) == 1 and a or b
    egg.ivs = egg.ivs or Game3.zeroIvs()
    egg.ivs[key] = (parent.ivs and parent.ivs[key]) or 0
  end
end

function Game3:giveDaycareEgg()
  local pid = self.daycarePending or 0
  if pid == 0 then return false, "There's no EGG." end
  if #(self.party or {}) >= Game3.PARTY_MAX then
    return false, "Your party's full!"
  end
  local species = self:eggSpeciesFrom(self:eggMotherSpecies(), pid)
  if not species or species < 1 then return false, "There's no EGG." end
  local egg = self:makeMon(species, Game3.EGG_HATCH_LEVEL)
  egg.pid = pid
  egg.isEgg = true
  egg.name = "EGG"
  egg.hatchLeft = self:eggCyclesFor(species)
  self:inheritDaycareIvs(egg)
  self:setAbility(egg)
  self:recalcStats(egg)
  egg.hp = egg.maxHp
  self.party = self.party or {}
  self.party[#self.party + 1] = egg
  self:clearPendingEgg()
  return true, "Take good care of it."
end

function Game3:rejectDaycareEgg()
  self:clearPendingEgg()
  return true, "We'll keep it, then."
end

function Game3:hatchEgg(mon)
  if not (mon and mon.isEgg) then return false end
  mon.isEgg = nil
  mon.hatchLeft = nil
  mon.name = self:speciesName(mon.species)
  mon.friendship = Game3.HATCH_FRIENDSHIP
  self:setAbility(mon)
  self:recalcStats(mon)
  mon.hp = mon.maxHp
  self:markCaught(mon.species)
  self.field = {
    kind = "talk",
    text = ("The EGG hatched into %s!"):format(mon.name),
  }
  return true
end

function Game3:tickEggCycles()
  local n = (self.eggCycleSteps or 0) + 1
  if n < Game3.EGG_CYCLE_STEPS then
    self.eggCycleSteps = n
    return
  end
  self.eggCycleSteps = 0
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon and mon.isEgg then
      local left = (mon.hatchLeft or 1) - 1
      if left < 1 then
        self:hatchEgg(mon)
      else
        mon.hatchLeft = left
      end
    end
  end
end

function Game3:talkDaycareMan()
  if (self.daycarePending or 0) ~= 0 then
    self.field = {
      kind = "daycare_egg",
      cursor = 0,
      text = "Ah, it's you! Your POKeMON were having a good time, so we kept an EGG for you. Want it?",
    }
    return true
  end
  if self:daycareCount() >= 2 then
    self.field = { kind = "talk", text = self:daycareCompatText() }
    return true
  end
  self.field = {
    kind = "talk",
    text = "I'm the DAY CARE Man. See my wife if you'd like me to raise a POKeMON.",
  }
  return true
end

function Game3.contestKey(category)
  return Game3.CONTEST_KEYS[(category or 0) + 1] or "cool"
end

function Game3:contestCondition(mon, category)
  if not mon then return 0 end
  return tonumber(mon[Game3.contestKey(category)]) or 0
end

function Game3:contestRibbon(mon, category)
  if not (mon and mon.ribbons) then return 0 end
  return tonumber(mon.ribbons[Game3.contestKey(category)]) or 0
end

function Game3:canEnterContest(mon)
  if not mon or mon.isEgg then return false, "Eggs can't enter." end
  if type(mon.moves) ~= "table" or #mon.moves < 1 then
    return false, "It has no moves to appeal with."
  end
  return true
end

function Game3:canEnterContestRank(mon, category, rank)
  rank = rank or 0
  if rank < 1 then return true end
  return self:contestRibbon(mon, category) >= rank
end

function Game3:contestRanksFor(mon, category)
  local list = { 0 }
  local have = self:contestRibbon(mon, category)
  for rank = 1, Game3.CONTEST_RANK_MASTER do
    if have >= rank then list[#list + 1] = rank end
  end
  return list
end

function Game3.contestCategoryForType(moveType)
  return Game3.CONTEST_TYPE_CATEGORY[moveType or 0] or Game3.CONTEST_CATEGORY_TOUGH
end

function Game3:contestAppealOf(move, category)
  if not move then return 0 end
  local cat = move.contestCategory
  if cat == nil then cat = Game3.contestCategoryForType(move.type) end
  local appeal = move.contestAppeal or Game3.CONTEST_DEFAULT_APPEAL
  if cat ~= category then appeal = math.floor(appeal / 2) end
  return appeal
end

function Game3:giveContestRibbon(mon, category, rank)
  if not mon then return false end
  mon.ribbons = mon.ribbons or {}
  local key = Game3.contestKey(category)
  local need = (rank or 0) + 1
  if (mon.ribbons[key] or 0) < need then mon.ribbons[key] = need end
  return true
end

function Game3:openContest()
  if #(self.party or {}) < 1 then
    self.field = { kind = "talk", text = "You don't have a POKeMON." }
    return true
  end
  self.field = { kind = "contest_cat", cursor = 0 }
  return true
end

function Game3:chooseContestMon()
  self:beginScriptWait()
  self.field = { kind = "contest_mon", cursor = 0, scripted = true }
  return true
end

function Game3:beginContest(monIndex, category, rank)
  local mon = self.party and self.party[monIndex]
  local ok, msg = self:canEnterContest(mon)
  if not ok then return false, msg end
  category = category or 0
  rank = rank or 0
  if not self:canEnterContestRank(mon, category, rank) then
    return false, "It hasn't won the previous rank yet."
  end
  self.contest = {
    monIndex = monIndex,
    category = category,
    rank = rank,
    turn = 0,
    player = self:contestCondition(mon, category),
    npc = { Game3.CONTEST_NPC_SCORES[1], Game3.CONTEST_NPC_SCORES[2],
      Game3.CONTEST_NPC_SCORES[3] },
  }
  self:setScriptVar(Game3.VAR_CONTEST_CATEGORY, category)
  self:setScriptVar(Game3.VAR_CONTEST_RANK, rank)
  self.field = { kind = "contest_move", cursor = 0 }
  return true
end

function Game3:startContest()
  local idx = self.contestMonIndex
    or (((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1)
  local category = (self.scriptVars and self.scriptVars[Game3.VAR_CONTEST_CATEGORY]) or 0
  local rank = (self.scriptVars and self.scriptVars[Game3.VAR_CONTEST_RANK]) or 0
  local ok, msg = self:beginContest(idx, category, rank)
  if not ok then
    self.field = { kind = "talk", text = msg or "You can't enter." }
    return false
  end
  self:beginScriptWait()
  if self.field then self.field.scripted = true end
  return true
end

function Game3:applyContestTurn(moveIndex)
  local c = self.contest
  if not c then return false end
  local mon = self.party and self.party[c.monIndex]
  local move = mon and mon.moves and mon.moves[moveIndex]
  local appeal = self:contestAppealOf(move, c.category)
  c.player = (c.player or 0) + appeal
  c.turn = (c.turn or 0) + 1
  c.lastAppeal = appeal
  if (c.turn or 0) >= Game3.CONTEST_TURNS then
    self:finishContest()
  end
  return true
end

function Game3:finishContest()
  local c = self.contest
  if not c then return end
  local totals = { c.player or 0, c.npc[1], c.npc[2], c.npc[3] }
  local winner, best = 1, totals[1]
  for i = 2, 4 do
    if (totals[i] or 0) > best then
      best = totals[i]
      winner = i
    end
  end
  c.totals = totals
  c.winner = winner - 1
  c.won = winner == 1
  if c.won then
    self:giveContestRibbon(self.party[c.monIndex], c.category, c.rank)
  end
  self.field = {
    kind = "contest_results",
    scripted = self.field and self.field.scripted,
  }
end

function Game3:contestResultsText()
  local c = self.contest
  if not c then return "The CONTEST is over." end
  local cat = Game3.CONTEST_CAT_NAMES[(c.category or 0) + 1] or "COOL"
  local rank = Game3.CONTEST_RANK_NAMES[(c.rank or 0) + 1] or "NORMAL"
  if c.won then
    return ("You won the %s %s CONTEST!"):format(rank, cat)
  end
  local place = (c.winner or 1) + 1
  return ("You placed %d in the %s %s CONTEST."):format(place, rank, cat)
end

function Game3:showContestResults()
  self:beginScriptWait()
  if not self.contest then
    self.field = { kind = "talk", text = "The CONTEST is over." }
    return true
  end
  self.field = { kind = "contest_results", scripted = true }
  return true
end

function Game3:setScriptVar(id, value)
  self.scriptVars = self.scriptVars or {}
  self.scriptVars[id] = value
end

function Game3:setStringVar(slot, text)
  self.stringVars = self.stringVars or {}
  self.stringVars[tonumber(slot) or 1] = text or ""
  return true
end

function Game3.nameKeys()
  local out = {}
  local letters = Game3.NAME_LETTERS
  for i = 1, #letters do out[i] = letters:sub(i, i) end
  out[#out + 1] = "DEL"
  out[#out + 1] = "END"
  return out
end

function Game3:bufferLeadMonSpecies(slot)
  local dest = (tonumber(slot) or 0) + 1
  local mon = self.party and self.party[1]
  local name = ""
  if mon then name = self:speciesName(mon.species) end
  return self:setStringVar(dest, name)
end

function Game3:openNickname()
  local idx = ((self.scriptVars and self.scriptVars[Gen3Script.VAR_0x8004]) or 0) + 1
  local mon = self.party and self.party[idx]
  if not mon then return false end
  -- ChangePokemonNickname copies MON_DATA_NICKNAME to gStringVar3
  -- (old) and gStringVar2 (naming buffer).
  local nick = mon.name or ""
  self:setStringVar(3, nick)
  self:setStringVar(2, nick)
  self:beginScriptWait()
  self.field = {
    kind = "nickname",
    scripted = true,
    slot = idx,
    cursor = 0,
    name = nick:sub(1, Game3.NICKNAME_LEN),
    keys = Game3.nameKeys(),
  }
  return true
end

function Game3:finishNickname()
  local f = self.field
  local slot = (f and f.slot) or 1
  local mon = self.party and self.party[slot]
  local name = (f and f.name) or ""
  if mon and name ~= "" then
    mon.name = name:sub(1, Game3.NICKNAME_LEN)
  end
  local scripted = f and f.scripted
  self.field = nil
  if scripted then return self:endScriptWait() end
  return true
end

function Game3:expandScriptText(text)
  if type(text) ~= "string" then return text end
  local vars = self.stringVars or {}
  text = text:gsub("{PLAYER}", self:playerName())
  text = text:gsub("{RIVAL}", self:rivalName())
  text = text:gsub("{KUN}", "")
  text = text:gsub("{STR_VAR_1}", vars[1] or "")
  text = text:gsub("{STR_VAR_2}", vars[2] or "")
  text = text:gsub("{STR_VAR_3}", vars[3] or "")
  -- decodeText used to drop GBA \p (0xFB), so cached IR glued the next
  -- sentence on: "TRAINER!You" / "says.Do". A real break sits on . ! ?
  text = text:gsub("([.!?])(%u)", "%1 %2")
  return text
end

function Game3:varGet(id)
  id = tonumber(id) or 0
  if id == Game3.VAR_FACING then
    local stored = Gen3Script.varGet(self.scriptVars, id)
    if stored ~= 0 then return stored end
    return Game3.dirId(self.facing)
  end
  return Gen3Script.varGet(self.scriptVars, id)
end

function Game3:runMapOps(ops, present)
  if type(ops) ~= "table" or #ops < 1 then return false end
  if present then return self:runNpcScript(ops) end
  Gen3Script.run(self, ops)
  return true
end

function Game3:runMapScript(key)
  local ms = self.map and self.map.mapScripts
  return self:runMapOps(ms and ms[key], false)
end

function Game3:runMapScriptTable(key, present)
  local ms = self.map and self.map.mapScripts
  local rows = ms and ms[key]
  if type(rows) ~= "table" then return false end
  for i = 1, #rows do
    local row = rows[i]
    if row and self:varGet(row.var) == self:varGet(row.value) then
      return self:runMapOps(row.script, present)
    end
  end
  return false
end

function Game3:tryMapFrameScript()
  if self.field then return false end
  return self:runMapScriptTable("onFrame", true)
end

function Game3:coordEventWouldRun(x, y)
  local events = self.map and self.map.coordEvents
  if type(events) ~= "table" then return false end
  x, y = tonumber(x) or self.playerX, tonumber(y) or self.playerY
  for i = 1, #events do
    local ev = events[i]
    if ev and ev.x == x and ev.y == y and ev.script
        and (ev.trigger or 0) ~= 0
        and (self:varGet(ev.trigger) % 256) == ((ev.index or 0) % 256) then
      return true
    end
  end
  return false
end

function Game3:tryCoordEvent(x, y)
  local events = self.map and self.map.coordEvents
  if type(events) ~= "table" then return false end
  x, y = tonumber(x) or self.playerX, tonumber(y) or self.playerY
  for i = 1, #events do
    local ev = events[i]
    if ev and ev.x == x and ev.y == y then
      if not ev.script then
        -- Weather coords have a null script; overworld weather is later.
      elseif (ev.trigger or 0) == 0 then
        self:runMapOps(ev.script, false)
      elseif (self:varGet(ev.trigger) % 256) == ((ev.index or 0) % 256) then
        return self:runMapOps(ev.script, true)
      end
    end
  end
  return false
end

function Game3:markFlyVisited(map)
  local dest = Game3.flyDestFor(map or self.map)
  if not dest then return false end
  self.flags = self.flags or {}
  self.flags[dest.flag] = true
  return true
end

function Game3:flyList()
  local out = {}
  local pack = ((self.data or {}).maps or {}).maps or {}
  for i = 1, #Game3.FLY_DESTINATIONS do
    local d = Game3.FLY_DESTINATIONS[i]
    if self.flags and self.flags[d.flag] and pack[d.mapId] then
      out[#out + 1] = d
    end
  end
  return out
end

function Game3:useFly()
  if not self:partyKnowsMove(Game3.MOVE_FLY) then
    return false, "No one in your party knows FLY."
  end
  if not self:hasBadge(6) then
    return false, "You need the FEATHER BADGE to use FLY."
  end
  if not Game3.canFlyFrom(self.map) then
    return false, "You can't use that here!"
  end
  local list = self:flyList()
  if #list < 1 then
    return false, "You can't use that here!"
  end
  self.field = { kind = "fly", cursor = 0, list = list }
  return true, "Where do you want to FLY?"
end

function Game3:flyTo(dest)
  if type(dest) == "string" then
    dest = Game3.FLY_BY_ID[dest]
  elseif type(dest) == "number" then
    dest = Game3.FLY_DESTINATIONS[dest]
  end
  if type(dest) ~= "table" then
    return false, "You can't use that here!"
  end
  local pack = ((self.data or {}).maps or {}).maps or {}
  local map = pack[dest.mapId]
  if not map then
    return false, "You can't use that here!"
  end
  local spawn = map.spawn or {}
  self.surfing = nil
  self.climbing = nil
  self:enterMap(map, spawn.x or 0, spawn.y or 0, false)
  return true, ("Flew to %s!"):format(dest.name or dest.mapId)
end

function Game3:tryLearnLevelMoves(mon)
  local texts = {}
  local row = self:speciesRow(mon.species)
  local learn = row and row.learnset or {}
  for i = 1, #learn do
    local e = learn[i]
    if e and e.level == mon.level and e.move and not self:knowsMove(mon, e.move) then
      local slot = self:copyMove(e.move)
      mon.moves = mon.moves or {}
      if #mon.moves >= 4 then
        self:queueLearnMove(mon, e.move)
      else
        mon.moves[#mon.moves + 1] = slot
        texts[#texts + 1] = ("%s learned %s!"):format(mon.name, slot.name)
      end
    end
  end
  return texts
end

function Game3:queueLearnMove(mon, moveId)
  self.pendingLearn = self.pendingLearn or {}
  self.pendingLearn[#self.pendingLearn + 1] = { mon = mon, move = moveId }
end

function Game3:learnMoveName(moveId)
  local slot = self:copyMove(moveId)
  return (slot and slot.name) or "MOVE"
end

function Game3:startPendingLearn()
  if self.learnMove then return true end
  local q = self.pendingLearn
  if not (q and q[1]) then return false end
  local e = table.remove(q, 1)
  local mon = e.mon
  local moveName = self:learnMoveName(e.move)
  local name = (mon and mon.name) or "POKeMON"
  self.learnMove = { mon = mon, move = e.move, name = moveName }
  local texts = {
    ("%s is trying to learn %s."):format(name, moveName),
    ("But, %s can't learn more than four moves."):format(name),
    ("Delete a move to make room for %s?"):format(moveName),
  }
  if self.phase == "battle" and self.battle then
    local b = self.battle
    b.kind = "text"
    b.queue = texts
    b.qi = 1
    b.text = texts[1]
    b.printSrc = nil
    b.textPage = 0
    b.thenLearnAsk = true
  else
    self.field = {
      kind = "talk", text = texts[1], queue = texts, qi = 1, thenLearnAsk = true,
    }
  end
  return true
end

function Game3:openLearnYesNo()
  local lm = self.learnMove
  local text = ("Delete a move to make room for %s?"):format(
    (lm and lm.name) or "MOVE")
  if self.phase == "battle" and self.battle then
    local b = self.battle
    b.kind = "learn_yesno"
    b.text = text
    b.cursor = 0
    b.queue = nil
    b.thenLearnAsk = nil
    b.printSrc = nil
    b.textPage = 0
  else
    self.field = { kind = "learn_yesno", text = text, cursor = 0 }
  end
end

function Game3:openLearnStop()
  local lm = self.learnMove
  local text = ("Stop learning %s?"):format((lm and lm.name) or "MOVE")
  if self.phase == "battle" and self.battle then
    local b = self.battle
    b.kind = "learn_stop"
    b.text = text
    b.cursor = 0
    b.printSrc = nil
    b.textPage = 0
  else
    self.field = { kind = "learn_stop", text = text, cursor = 0 }
  end
end

function Game3:openLearnForget()
  local lm = self.learnMove
  local mon = lm and lm.mon
  if self.phase == "battle" and self.battle then
    local b = self.battle
    b.kind = "learn_forget"
    b.cursor = 0
    b.text = ("Which move should be forgotten?")
    b.printSrc = nil
    b.textPage = 0
  else
    self.field = {
      kind = "learn_forget", cursor = 0, mon = mon,
      text = "Which move should be forgotten?",
    }
  end
end

function Game3:showLearnMessage(text, thenKind)
  self:showLearnMessages({ text }, thenKind)
end

function Game3:showLearnMessages(texts, thenKind)
  if type(texts) ~= "table" or #texts < 1 then
    texts = { tostring(texts or "") }
  end
  if self.phase == "battle" and self.battle then
    local b = self.battle
    b.kind = "learn_msg"
    b.queue = texts
    b.qi = 1
    b.text = texts[1]
    b.thenLearn = thenKind
    b.printSrc = nil
    b.textPage = 0
  else
    self.field = {
      kind = "talk", text = texts[1], queue = texts, qi = 1, thenLearn = thenKind,
    }
  end
end

function Game3:afterLearnPrompt()
  self.learnMove = nil
  if self:startPendingLearn() then return end
  if self.phase == "battle" and self.battle then
    self:afterBattleMessages()
  else
    if self:startPendingEvolve() then return end
    self:closeField()
  end
end

function Game3:answerLearnYesNo(yes)
  if yes then
    self:openLearnForget()
  else
    self:openLearnStop()
  end
end

function Game3:answerLearnStop(yes)
  local lm = self.learnMove
  if yes then
    local mon = lm and lm.mon
    local name = (mon and mon.name) or "POKeMON"
    local moveName = (lm and lm.name) or "MOVE"
    self:showLearnMessage(
      ("%s did not learn %s."):format(name, moveName), "done")
  else
    self:openLearnYesNo()
  end
end

function Game3:chooseLearnForget(slot)
  local lm = self.learnMove
  local mon = lm and lm.mon
  local moves = mon and mon.moves or {}
  slot = tonumber(slot) or 0
  if slot < 1 or slot > #moves then
    self:openLearnStop()
    return false
  end
  local old = moves[slot]
  if Game3.isHmMove(old and old.id) then
    self:showLearnMessage("HM moves can't be forgotten now.", "forget")
    return false
  end
  local learned = self:copyMove(lm.move)
  local oldName = (old and old.name) or "MOVE"
  local name = mon.name or "POKeMON"
  moves[slot] = learned
  self:showLearnMessages({
    ("%s forgot %s."):format(name, oldName),
    ("%s learned %s!"):format(name, learned.name or lm.name),
  }, "done")
  return true
end

function Game3:finishLearnMessage()
  local thenKind = nil
  if self.phase == "battle" and self.battle then
    thenKind = self.battle.thenLearn
    self.battle.thenLearn = nil
  elseif self.field then
    thenKind = self.field.thenLearn
  end
  if thenKind == "forget" then
    self:openLearnForget()
  else
    self:afterLearnPrompt()
  end
end

function Game3:evolutionsFor(species)
  local row = self:speciesRow(species)
  if row and type(row.evolutions) == "table" and #row.evolutions > 0 then
    return row.evolutions
  end
  return Game3.FALLBACK_EVOS[species]
end

function Game3:checkEvolution(mon)
  local list = self:evolutionsFor(mon.species)
  if type(list) ~= "table" then return nil end
  local level = mon.level or 1
  local upper = math.floor((mon.pid or 0) / 65536)
  for i = 1, #list do
    local e = list[i]
    local method, param, target = e.method, e.param or 0, e.target
    if not target then
    elseif method == Game3.EVO_LEVEL and level >= param then
      return target
    elseif method == Game3.EVO_LEVEL_ATK_GT_DEF and level >= param
        and (mon.atk or 0) > (mon.def or 0) then
      return target
    elseif method == Game3.EVO_LEVEL_ATK_EQ_DEF and level >= param
        and (mon.atk or 0) == (mon.def or 0) then
      return target
    elseif method == Game3.EVO_LEVEL_ATK_LT_DEF and level >= param
        and (mon.atk or 0) < (mon.def or 0) then
      return target
    elseif method == Game3.EVO_LEVEL_SILCOON and level >= param
        and (upper % 10) <= 4 then
      return target
    elseif method == Game3.EVO_LEVEL_CASCOON and level >= param
        and (upper % 10) > 4 then
      return target
    elseif method == Game3.EVO_LEVEL_NINJASK and level >= param then
      return target
    end
  end
end

function Game3:applyEvolution(mon, target)
  local oldName = mon.name
  mon.species = target
  mon.name = self:speciesName(target)
  local row = self:speciesRow(target) or {}
  if row.type1 then mon.type1 = row.type1 end
  if row.type2 or row.type1 then mon.type2 = row.type2 or row.type1 end
  if row.ability1 or row.ability2 then self:setAbility(mon) end
  if row.catchRate then mon.catchRate = row.catchRate end
  if row.expYield then mon.expYield = row.expYield end
  if row.growthRate then mon.growth = row.growthRate end
  self:recalcStats(mon)
  return oldName, mon.name
end

function Game3:tryEvolve(mon)
  local target = self:checkEvolution(mon)
  if not target then return {} end
  self.pendingEvo = self.pendingEvo or {}
  self.pendingEvo[#self.pendingEvo + 1] = {
    mon = mon,
    from = mon.species,
    fromName = mon.name,
    target = target,
  }
  return {}
end

function Game3:resolvePendingEvolve()
  local n = 0
  while self.pendingEvo and self.pendingEvo[1] and n < 8 do
    n = n + 1
    local e = table.remove(self.pendingEvo, 1)
    self:applyEvolution(e.mon, e.target)
    self:tryLearnLevelMoves(e.mon)
    self:tryEvolve(e.mon)
  end
end

function Game3:startPendingEvolve()
  local q = self.pendingEvo
  if not (q and q[1]) then return false end
  local e = table.remove(q, 1)
  self.evolve = {
    mon = e.mon,
    from = e.from,
    fromName = e.fromName,
    target = e.target,
    t = 0,
    stage = "announce",
  }
  local text = ("What? %s is evolving!"):format(e.fromName)
  if self.phase == "battle" and self.battle then
    self.battle.kind = "evolve"
    self.battle.text = text
    self.battle.printSrc = nil
    self.battle.textPage = 0
    self.battle.queue = nil
  else
    self.field = { kind = "evolve", text = text }
  end
  return true
end

function Game3:finishEvolveStage()
  local evo = self.evolve
  if not evo then return end
  local learned = self:tryLearnLevelMoves(evo.mon)
  self.evolve = nil
  if #learned > 0 then
    if self.phase == "battle" and self.battle then
      self.battle.kind = "text"
      self.battle.queue = learned
      self.battle.qi = 1
      self.battle.text = learned[1]
      self.battle.printSrc = nil
    else
      self.field = { kind = "talk", text = learned[1], queue = learned, qi = 1 }
    end
    return
  end
  if self:startPendingLearn() then return end
  if self:startPendingEvolve() then return end
  if self.phase == "battle" and self.battle then
    self.battle.kind = "text"
    self.battle.queue = nil
    self:advanceBattleText()
  else
    self:closeField()
  end
end

function Game3:stepEvolve(dt)
  local evo = self.evolve
  if not evo then return false end
  dt = dt or 0
  local box = (self.phase == "battle" and self.battle) or self.field
  if evo.stage == "announce" then
    if Input:wasPressed("a") or Input:wasPressed("b") then
      if box and self:printerBusy(box) then
        self:printerFinish(box)
        return true
      end
      evo.stage = "anim"
      evo.t = 0
    end
    return true
  end
  if evo.stage == "anim" then
    evo.t = (evo.t or 0) + dt
    if evo.t >= Game3.EVOLVE_ANIM then
      self:applyEvolution(evo.mon, evo.target)
      evo.stage = "done"
      if box then
        box.text = ("%s evolved into %s!"):format(evo.fromName, evo.mon.name)
        box.printSrc = nil
        box.textPage = 0
      end
    end
    return true
  end
  if evo.stage == "done" then
    if Input:wasPressed("a") or Input:wasPressed("b") then
      if box and self:printerBusy(box) then
        self:printerFinish(box)
        return true
      end
      self:finishEvolveStage()
    end
  end
  return true
end

function Game3:evolveDraw()
  local evo = self.evolve
  if not (evo and evo.stage == "anim") then
    return 1, false, evo and evo.mon and evo.mon.species
  end
  local t = evo.t or 0
  local half = Game3.EVOLVE_ANIM / 2
  local flash = math.floor(t * 16) % 2 == 1
  if t < half then
    return 1 - (t / half) * 0.85, flash, evo.from
  end
  return 0.15 + ((t - half) / half) * 0.85, flash, evo.target
end

function Game3:partyIndexOf(mon)
  if not mon then return nil end
  local party = self.party or {}
  for i = 1, #party do
    if party[i] == mon then return i end
  end
end

function Game3:markSentIn(mon)
  local i = self:partyIndexOf(mon)
  local b = self.battle
  if not (i and b) then return end
  b.sentIn = b.sentIn or {}
  b.sentIn[i] = true
end

function Game3:holdsExpShare(mon)
  local effect = self:holdEffectOf(mon)
  return effect == Game3.HOLD_EFFECT_EXP_SHARE
end

-- pokeruby IsOtherTrainer: a different OT id is always traded; the
-- same id still trades if the OT name disagrees. Missing otId is the
-- pre-Phase-114 save (caught / starter) and counts as own.
function Game3:isOtherTrainer(otId, otName)
  if otId == nil then return false end
  if otId ~= self:ensureTrainerId() then return true end
  if type(otName) ~= "string" or otName == "" then return false end
  return otName ~= self:playerName()
end

function Game3:isTradedMon(mon)
  return mon ~= nil and self:isOtherTrainer(mon.otId, mon.otName)
end

function Game3:giveMonExp(mon, amount, trainer)
  if not mon then return {} end
  amount = math.floor(tonumber(amount) or 0)
  if trainer then amount = math.floor(amount * 3 / 2) end
  local boosted = self:isTradedMon(mon)
  if boosted then amount = math.floor(amount * 3 / 2) end
  if amount < 1 then return {} end
  local verb = boosted and "gained a boosted" or "gained"
  local texts = { ("%s %s %d EXP. Points!"):format(mon.name, verb, amount) }
  local growth = mon.growth or Game3.GROWTH_MEDIUM_SLOW
  mon.exp = (mon.exp or Game3.expAtLevel(growth, mon.level)) + amount
  while (mon.level or 1) < 100 do
    local need = Game3.expAtLevel(growth, (mon.level or 1) + 1)
    if (mon.exp or 0) < need then break end
    mon.level = (mon.level or 1) + 1
    self:recalcStats(mon)
    self:adjustFriendship(mon, Game3.FRIENDSHIP_EVENT_GROW_LEVEL)
    texts[#texts + 1] = ("%s grew to LV. %d!"):format(mon.name, mon.level)
    local learned = self:tryLearnLevelMoves(mon)
    for i = 1, #learned do texts[#texts + 1] = learned[i] end
  end
  local evolved = self:tryEvolve(mon)
  if not (self.phase == "battle" and self.battle) then
    self:resolvePendingEvolve()
  end
  for i = 1, #evolved do texts[#texts + 1] = evolved[i] end
  return texts
end

function Game3:awardExp(winner, fainted, trainer)
  local yield = fainted and fainted.expYield
  if not yield then
    local row = fainted and self:speciesRow(fainted.species)
    yield = row and row.expYield or 0
  end
  local calculated = math.max(1, math.floor((yield or 0)
    * ((fainted and fainted.level) or 1) / 7))
  local party = self.party or {}
  local winnerIdx = self:partyIndexOf(winner)
  if not winnerIdx then
    self:gainEVs(winner, fainted)
    return self:giveMonExp(winner, calculated, trainer)
  end
  local sent = self.battle and self.battle.sentIn
  local hasSent = false
  if type(sent) == "table" then
    for i = 1, #party do
      if sent[i] then hasSent = true break end
    end
  end
  if not hasSent then sent = { [winnerIdx] = true } end
  local viaSent, viaShare = 0, 0
  for i = 1, #party do
    local mon = party[i]
    if self:canBattle(mon) then
      if sent[i] then viaSent = viaSent + 1 end
      if self:holdsExpShare(mon) then viaShare = viaShare + 1 end
    end
  end
  if viaSent < 1 then viaSent = 1 end
  local partShare, shareShare
  if viaShare > 0 then
    partShare = math.max(1, math.floor(calculated / 2 / viaSent))
    shareShare = math.max(1, math.floor(calculated / 2 / viaShare))
  else
    partShare = math.max(1, math.floor(calculated / viaSent))
    shareShare = 0
  end
  local texts = {}
  for i = 1, #party do
    local mon = party[i]
    if self:canBattle(mon) then
      local amount = 0
      if sent[i] then amount = partShare end
      if self:holdsExpShare(mon) then amount = amount + shareShare end
      if amount > 0 then
        self:gainEVs(mon, fainted)
        local lines = self:giveMonExp(mon, amount, trainer)
        for j = 1, #lines do texts[#texts + 1] = lines[j] end
      end
    end
  end
  return texts
end

function Game3:switchTo(index)
  local b = self.battle
  local mon = self.party and self.party[index]
  if not mon then return false, "No POKeMON." end
  if (mon.hp or 0) <= 0 then return false, "It's out of HP!" end
  if b and (mon == b.player or mon == b.player2) then
    return false, "Already in battle!"
  end
  local slot = (b and b.switchSlot) or "player"
  if slot ~= "player" and slot ~= "player2" then slot = "player" end
  local outgoing = b and b[slot]
  local extra = {}
  if outgoing then
    if self:hasAbility(outgoing, Game3.ABILITY_NATURAL_CURE) then
      outgoing.status = nil
      outgoing.sleepTurns = nil
    end
    outgoing.confuseTurns = nil
    outgoing.flinch = nil
    outgoing.flashFire = nil
    outgoing.charging = nil
    outgoing.invuln = nil
    outgoing.bideTurns = nil
    outgoing.bideTaken = nil
    outgoing.bideFrom = nil
    outgoing.protected = nil
    outgoing.protectStreak = nil
    outgoing.endured = nil
    outgoing.mudSport = nil
    outgoing.waterSport = nil
    outgoing.rage = nil
    outgoing.leechSeed = nil
    outgoing.leechSeedSlot = nil
    outgoing.leechSeedFrom = nil
    outgoing.foresight = nil
  end
  if b then
    b[slot] = mon
    b.switchSlot = nil
    self:markSentIn(mon)
  end
  mon.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  mon.focusEnergy = nil
  mon.confuseTurns = nil
  mon.flinch = nil
  mon.flashFire = nil
  mon.charging = nil
  mon.invuln = nil
  mon.bideTurns = nil
  mon.bideTaken = nil
  mon.bideFrom = nil
  mon.protected = nil
  mon.protectStreak = nil
  mon.endured = nil
  mon.mudSport = nil
  mon.waterSport = nil
  mon.rage = nil
  mon.leechSeed = nil
  mon.leechSeedSlot = nil
  mon.leechSeedFrom = nil
  mon.foresight = nil
  if type(mon.moves) ~= "table" or #mon.moves < 1 then
    mon.moves = self:movesFor(mon.species, mon.level)
  end
  local foe = b and (Game3.aliveMon(b.enemy) and b.enemy or b.enemy2)
  if b and foe then
    extra = self:activateEnter(mon, foe)
  end
  return true, ("Go! %s!"):format(mon.name), extra
end

function Game3.isqrt(n)
  n = math.floor(n or 0)
  if n <= 0 then return 0 end
  local x = n
  local y = math.floor((n + 1) / 2)
  while y < x do
    x = y
    y = math.floor((x + math.floor(n / x)) / 2)
  end
  return x
end

-- pokeemerald: a = (3*max - 2*hp) * catchRate * ballBonus / (3*max)
function Game3.catchValue(hp, maxHp, catchRate, ballBonus)
  maxHp = math.max(1, maxHp or 1)
  hp = math.max(0, math.min(hp or 0, maxHp))
  local a = math.floor(
    (3 * maxHp - 2 * hp) * (catchRate or 45) * (ballBonus or 1) / (3 * maxHp))
  if a < 1 then a = 1 end
  return a
end

-- Four 16-bit rolls must each be < this threshold.
function Game3.shakeThreshold(a)
  if a >= 255 then return 65535 end
  if a < 1 then a = 1 end
  local inner = Game3.isqrt(math.floor(16711680 / a))
  local outer = Game3.isqrt(inner)
  if outer < 1 then outer = 1 end
  return math.floor(1048560 / outer)
end

function Game3.catchFailText(shakes)
  if shakes <= 0 then return "Oh no! The POKeMON broke free!" end
  if shakes == 1 then return "Aww! It appeared to be caught!" end
  if shakes == 2 then return "Aargh! Almost had it!" end
  return "Shoot! It was so close too!"
end

function Game3:cloneMon(mon)
  local copy = {}
  for k, v in pairs(mon or {}) do
    if k ~= "moves" and k ~= "stages" and k ~= "ivs" then copy[k] = v end
  end
  copy.ivs = Game3.copyIvs(mon and mon.ivs)
  copy.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  copy.moves = {}
  local moves = mon and mon.moves or {}
  for i = 1, #moves do
    local src = moves[i]
    local slot = {}
    if type(src) == "table" then
      for k, v in pairs(src) do slot[k] = v end
    end
    copy.moves[i] = slot
  end
  return copy
end

function Game3:markSeen(species)
  species = tonumber(species)
  if not species or species < 1 then return end
  self.seen = self.seen or {}
  self.seen[species] = true
end

function Game3:hasSeen(species)
  species = tonumber(species)
  return species and ((self.seen and self.seen[species] == true)
    or self:hasCaught(species))
end

function Game3:markCaught(species)
  species = tonumber(species)
  if not species or species < 1 then return end
  self.caught = self.caught or {}
  self.caught[species] = true
  self:markSeen(species)
end

function Game3:hasCaught(species)
  species = tonumber(species)
  return species and self.caught and self.caught[species] == true
end

function Game3:harvestCaught()
  local function take(mon)
    if mon and not mon.isEgg then self:markCaught(mon.species) end
  end
  for i = 1, #(self.party or {}) do take(self.party[i]) end
  self:ensurePc()
  for b = 1, Game3.BOX_COUNT do
    local box = self.pc[b] or {}
    for i = 1, #box do take(box[i]) end
  end
end

function Game3:snapshotCaught()
  local list = {}
  for id, yes in pairs(self.caught or {}) do
    if yes then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

function Game3:snapshotSeen()
  local list = {}
  for id, yes in pairs(self.seen or {}) do
    if yes then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

function Game3:hasPokedex()
  return self.flags and self.flags[Game3.FLAG_SYS_POKEDEX_GET] == true
end

function Game3:hasPokenav()
  return self.flags and self.flags[Game3.FLAG_SYS_POKENAV_GET] == true
end

function Game3:hoennDexOf(species)
  local row = self:speciesRow(species)
  return row and tonumber(row.hoennDex)
end

function Game3:hasHoennDexTable()
  local by = self.data and self.data.pokemon and self.data.pokemon.byIndex
  if type(by) ~= "table" then return false end
  for _, row in pairs(by) do
    if row and tonumber(row.hoennDex) then return true end
  end
  return false
end

function Game3:inCurrentDex(species)
  species = tonumber(species)
  if not species or species < 1 then return false end
  if self:hasNationalDex() then return species <= Game3.NATIONAL_DEX_COUNT end
  local n = self:hoennDexOf(species)
  if n then return n >= 1 and n <= Game3.HOENN_DEX_COUNT end
  if self:hasHoennDexTable() then return false end
  return true
end

function Game3:hasNationalDex()
  return self.flags and self.flags[Game3.FLAG_SYS_NATIONAL_DEX] == true
end

function Game3:enableNationalDex()
  if self:hasNationalDex() then return false end
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SYS_NATIONAL_DEX] = true
  self.scriptVars = self.scriptVars or {}
  self.scriptVars[Game3.VAR_NATIONAL_DEX] = Game3.NATIONAL_DEX_ENABLED
  return true
end

function Game3:completedHoennPokedex()
  local caught = 0
  local mapped = self:hasHoennDexTable()
  for id, yes in pairs(self.caught or {}) do
    if yes then
      if mapped then
        local n = self:hoennDexOf(id)
        if n and n >= 1 and n <= Game3.HOENN_DEX_COMPLETE then
          caught = caught + 1
        end
      else
        caught = caught + 1
      end
    end
  end
  return caught >= Game3.HOENN_DEX_COMPLETE
end

function Game3:giveNationalDex()
  if not self:hasPokedex() then return false end
  if self:hasNationalDex() then return false end
  if not self:completedHoennPokedex() then return false end
  self:enableNationalDex()
  self.field = {
    kind = "talk",
    text = "PROF. BIRCH: Your POKeDEX was upgraded to the National mode!",
  }
  return true
end

function Game3:dexCounts()
  local seen, caught = 0, 0
  local counted = {}
  for id, yes in pairs(self.seen or {}) do
    if yes and self:inCurrentDex(id) and not counted[id] then
      counted[id] = true
      seen = seen + 1
    end
  end
  for id, yes in pairs(self.caught or {}) do
    if yes and self:inCurrentDex(id) then
      if not counted[id] then counted[id] = true; seen = seen + 1 end
      caught = caught + 1
    end
  end
  return seen, caught
end

function Game3:dexEntries()
  local ids = {}
  local have = {}
  for id, yes in pairs(self.seen or {}) do
    if yes and self:inCurrentDex(id) then have[id] = true end
  end
  for id, yes in pairs(self.caught or {}) do
    if yes and self:inCurrentDex(id) then have[id] = true end
  end
  for id, _ in pairs(have) do ids[#ids + 1] = id end
  table.sort(ids)
  local list = {}
  for i = 1, #ids do
    local id = ids[i]
    list[i] = {
      id = id,
      name = self:speciesName(id),
      caught = self:hasCaught(id),
    }
  end
  return list
end

function Game3:pokedexRating(caught)
  caught = caught or 0
  if caught >= 200 then return "You've become a genuine PROFESSOR!" end
  if caught >= 50 then return "Keep going! You're getting somewhere." end
  return "You've still got lots to do. Look for POKeMON in grassy areas!"
end

function Game3:givePokedex()
  if self:hasPokedex() then return false end
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SYS_POKEDEX_GET] = true
  self.flags[Game3.FLAG_HIDE_RIVAL_BIRCH_LAB] = nil
  self:harvestCaught()
  local objects = self.map and self.map.objects
  if type(objects) == "table" and #objects > 0 then
    self:resetNpcs(self.map)
  end
  self.field = {
    kind = "talk",
    text = "PROF. BIRCH: Here's a POKeDEX! Record data on all the POKeMON you see!",
  }
  return true
end

function Game3:openDex()
  self.field = { kind = "dex", cursor = 0, list = self:dexEntries() }
  return true
end

function Game3:startMenuItems()
  local items = {}
  if self:hasPokedex() then items[#items + 1] = "POKeDEX" end
  items[#items + 1] = "POKeMON"
  items[#items + 1] = "BAG"
  if self:hasPokenav() then items[#items + 1] = "POKeNAV" end
  items[#items + 1] = self:playerName()
  items[#items + 1] = "SAVE"
  items[#items + 1] = "OPTION"
  items[#items + 1] = "EXIT"
  return items
end

function Game3:startMenuIndex(name)
  local labels = self:startMenuItems()
  for i = 1, #labels do
    if labels[i] == name then return i - 1 end
  end
  return 0
end

function Game3:backToStart(name)
  self.field = { kind = "menu", cursor = self:startMenuIndex(name) }
  return true
end

function Game3:openBag()
  local pocket = self.lastBagPocket
  if type(pocket) ~= "number"
      or pocket < Game3.POCKET_ITEMS or pocket > Game3.POCKET_KEY then
    pocket = self:firstFilledPocket()
  end
  self.lastBagPocket = pocket
  self.field = { kind = "bag", pocket = pocket, cursor = 0 }
  return true
end

function Game3:openPokeNav()
  self.field = { kind = "pokenav", text = "HOENN region map." }
  return true
end

function Game3:openParty()
  self.field = { kind = "party", cursor = 0 }
  return true
end

function Game3.isTmHm(id)
  id = tonumber(id) or 0
  return id >= Game3.ITEM_TM01 and id <= Game3.ITEM_HM_DIVE
end

function Game3.tmhmIndex(id)
  if not Game3.isTmHm(id) then return nil end
  return id - Game3.ITEM_TM01
end

function Game3:tmhmMove(item)
  local tm = Game3.tmhmIndex(item)
  if not tm then return nil end
  local list = self.data and self.data.moves and self.data.moves.tmhmMoves
  if type(list) ~= "table" then list = Game3.TMHM_MOVES end
  return list[tm + 1]
end

function Game3:canLearnTMHM(mon, item)
  if not mon or mon.isEgg then return false end
  local tm = Game3.tmhmIndex(item)
  if not tm then return false end
  local row = self:speciesRow(mon.species)
  local bits = row and row.tmhm
  if type(bits) ~= "table" then return false end
  local word = tm < 32 and (bits[1] or 0) or (bits[2] or 0)
  local bit = tm < 32 and tm or (tm - 32)
  return math.floor(word / (2 ^ bit)) % 2 == 1
end

function Game3:openPartyTeach(item)
  self.field = { kind = "party_teach", cursor = 0, item = item }
  return true
end

function Game3:teachTMHM(index, item, forgetSlot)
  local mon = (self.party or {})[index]
  if not mon then return false, "There's no one here." end
  local moveId = self:tmhmMove(item)
  if not moveId then return false, "It won't have any effect." end
  local slot = self:copyMove(moveId)
  local name = (slot and slot.name) or "MOVE"
  if self:knowsMove(mon, moveId) then
    return false, ("%s already knows %s."):format(mon.name or "POKeMON", name)
  end
  if not self:canLearnTMHM(mon, item) then
    return false, ("%s can't learn %s."):format(mon.name or "POKeMON", name)
  end
  local moves = mon.moves or {}
  mon.moves = moves
  if forgetSlot then
    forgetSlot = tonumber(forgetSlot) or 0
    if forgetSlot < 1 or forgetSlot > #moves then
      return false, "Which move should be forgotten?"
    end
    moves[forgetSlot] = slot
  elseif #moves >= 4 then
    return false, ("%s wants to learn %s."):format(
      mon.name or "POKeMON", name), true
  else
    moves[#moves + 1] = slot
  end
  if item < Game3.ITEM_HM_CUT then self:takeItem(item, 1) end
  return true, ("%s learned %s!"):format(mon.name or "POKeMON", name)
end

function Game3:chooseTeachMon(index)
  local item = self.field and self.field.item
  local ok, msg, needForget = self:teachTMHM(index, item)
  if needForget then
    self.field = {
      kind = "party_forget", cursor = 0, monIndex = index, item = item,
    }
    return true
  end
  self.field = { kind = "talk", text = msg }
  return ok
end

function Game3:openPartyAction(index)
  local mon = (self.party or {})[index]
  if not mon then return false end
  self.field = {
    kind = "party_action",
    cursor = 0,
    monIndex = index,
    actions = self:partyActions(mon),
  }
  return true
end

function Game3:openPartySummary(index)
  local mon = (self.party or {})[index]
  if not mon then return false end
  self.field = {
    kind = "party_summary",
    cursor = 0,
    monIndex = index,
    page = 0,
  }
  return true
end

function Game3:ensureTrainerId()
  if type(self.trainerId) == "number" and self.trainerId >= 0 then
    return self.trainerId
  end
  local lo = self:rand(65536) - 1
  local hi = self:rand(65536) - 1
  if lo < 0 then lo = 0 end
  if hi < 0 then hi = 0 end
  self.trainerId = hi * 65536 + lo
  return self.trainerId
end

function Game3:trainerIdString()
  return ("%05d"):format(self:ensureTrainerId() % 65536)
end

function Game3:moneyString(n)
  n = math.floor(tonumber(n) or self.money or 0)
  if n < 0 then n = 0 end
  if n > 999999 then n = 999999 end
  local s = tostring(n)
  local grouped = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return "$" .. grouped
end

-- pokeruby OpenMoneyWindow: 8x8 tiles, 14x4 frame. Museum / Seashore
-- House use (0, 0). hidemoneybox closes it; updatemoneybox reprints.
function Game3:showMoneyBox(x, y)
  self.moneyBox = { x = tonumber(x) or 0, y = tonumber(y) or 0 }
end

function Game3:hideMoneyBox()
  self.moneyBox = nil
end

function Game3:updateMoneyBox()
  if self.moneyBox then return true end
end

function Game3:drawMoneyBox()
  local box = self.moneyBox
  if not box then return end
  local f = self.field
  if f then
    local kind = f.kind
    if kind == "menu" or kind == "bag" or kind == "option"
        or kind == "trainer_card" or kind == "save_ask"
        or kind == "party" or kind == "party_switch"
        or kind == "party_teach" or kind == "party_action"
        or kind == "party_item" or kind == "party_summary"
        or kind == "party_forget" or kind == "learn_forget"
        or kind == "learn_yesno" or kind == "learn_stop"
        or kind == "fishing" then
      return
    end
  end
  local tile = 8
  local x = (box.x or 0) * tile
  local y = (box.y or 0) * tile
  self:drawWindow(x, y, 14 * tile, 4 * tile)
  love.graphics.setColor(0.10, 0.10, 0.12, 1)
  self:drawText(self:moneyString(), x + 16, y + 8)
end

function Game3:playMonCry(species, _mode)
  local name = self:speciesName(tonumber(species) or 0)
  local ok, Sound = pcall(require, "src.core.Sound")
  if not ok or type(Sound) ~= "table" or not Sound.playCry then
    self.monCrySrc = nil
    return
  end
  self.monCrySrc = Sound.playCry(self.data or {}, name)
end

function Game3:cryPlaying()
  local src = self.monCrySrc
  if not src then return false end
  local playing = false
  if type(src.isPlaying) == "function" then
    playing = src:isPlaying() and true or false
  end
  if not playing then self.monCrySrc = nil end
  return playing
end

function Game3:waitMonCry()
  if not self:cryPlaying() then return end
  self.waitingCry = true
  self:beginScriptWait()
end

function Game3:saveMapName()
  local map = self.map
  if type(map) ~= "table" then return "?????" end
  local name = map.name or map.id or "?????"
  return tostring(name)
end

function Game3:cardStars()
  local n = 0
  if self:hasPokedex() then n = n + 1 end
  if self:completedHoennPokedex() then n = n + 1 end
  return n
end

function Game3:openTrainerCard()
  self:ensureTrainerId()
  self.field = { kind = "trainer_card" }
  return true
end

function Game3:openSaveAsk()
  self.field = {
    kind = "save_ask",
    cursor = 0,
    text = "Would you like to SAVE the game?",
  }
  return true
end

function Game3:confirmSave()
  local ok, msg = self:writeSave()
  if ok then
    self.field = {
      kind = "talk",
      text = (self:playerName() .. " saved the game."),
    }
  else
    self.field = { kind = "talk", text = msg or "Save failed." }
  end
  return ok
end

function Game3:inGameTradeRow(id)
  return Game3.INGAME_TRADES[tonumber(id) or 0]
end

function Game3:getInGameTradeSpeciesInfo()
  local row = self:inGameTradeRow(self:varGet(0x8004))
  if not row then
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    return 0
  end
  self:setStringVar(1, self:speciesName(row.playerSpecies))
  self:setStringVar(2, self:speciesName(row.species))
  self:setScriptVar(Gen3Script.VAR_RESULT, row.playerSpecies)
  return row.playerSpecies
end

function Game3:selectMonForNpcTrade()
  self:beginScriptWait()
  self.field = { kind = "npc_trade", cursor = 0, scripted = true }
  return true
end

function Game3:getTradeSpecies()
  local idx = (self:varGet(0x8005) or 0) + 1
  local mon = self.party and self.party[idx]
  local species = 0
  if mon and not mon.isEgg then species = tonumber(mon.species) or 0 end
  self:setScriptVar(Gen3Script.VAR_RESULT, species)
  return species
end

function Game3:createInGameTradePokemon()
  local trade = self:inGameTradeRow(self:varGet(0x8004))
  local idx = (self:varGet(0x8005) or 0) + 1
  local given = self.party and self.party[idx]
  if not trade or not given then return false end
  local mon = self:makeMon(trade.species, given.level or 5)
  mon.name = trade.name
  mon.pid = trade.pid or mon.pid
  mon.otId = trade.otId
  mon.otName = trade.otName
  mon.otGender = trade.otGender
  mon.item = trade.item
  mon.cool = trade.cool
  mon.beauty = trade.beauty
  mon.cute = trade.cute
  mon.smart = trade.smart
  mon.tough = trade.tough
  mon.sheen = trade.sheen
  mon.metLocation = 0xFE
  if trade.ivs then
    mon.ivs = {
      hp = trade.ivs.hp, atk = trade.ivs.atk, def = trade.ivs.def,
      spe = trade.ivs.spe, spa = trade.ivs.spa, spd = trade.ivs.spd,
    }
  end
  self:setAbility(mon)
  if trade.secondAbility then
    local row = self:speciesRow(mon.species)
    if row and (row.ability2 or 0) ~= 0 then mon.ability = row.ability2 end
  end
  self:recalcStats(mon)
  mon.hp = mon.maxHp
  self.party[idx] = mon
  self:markCaught(mon.species)
  return true
end

-- pokeruby GetLeadMonIndex: first party slot that is not SPECIES_NONE
-- or SPECIES_EGG (SPECIES2).
function Game3:partyMonSpecies2(mon)
  if not mon then return 0 end
  if mon.isEgg then return Game3.SPECIES_EGG end
  return tonumber(mon.species) or 0
end

function Game3:leadMonIndex()
  local party = self.party or {}
  for i = 1, #party do
    local sp = self:partyMonSpecies2(party[i])
    if sp ~= 0 and sp ~= Game3.SPECIES_EGG then return i end
  end
  return 1
end

function Game3:leadMon()
  return self.party and self.party[self:leadMonIndex()]
end

function Game3:selectedPartyMon()
  local idx = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
  return self.party and self.party[idx]
end

function Game3:monEvCount(mon)
  if not mon then return 0 end
  local n = 0
  for i = 1, #Game3.EV_KEYS do
    n = n + (mon[Game3.EV_KEYS[i]] or 0)
  end
  return n
end

-- pokeruby pokemon_3.c MonGainEVs: each exp-getter gets the full
-- defeated-species evYield. Pokerus (byte != 0) is 2x; Macho Brace is
-- another 2x. Per-stat 255 and party total 510.
function Game3:gainEVs(mon, fainted)
  if not mon or mon.isEgg then return end
  local row = fainted and self:speciesRow(fainted.species) or {}
  local multiplier = 1
  if (mon.pokerus or 0) ~= 0 then multiplier = 2 end
  local hold = self:holdEffectOf(mon)
  if hold == Game3.HOLD_EFFECT_MACHO_BRACE then
    multiplier = multiplier * 2
  end
  local total = self:monEvCount(mon)
  for i = 1, #Game3.EV_KEYS do
    if total >= Game3.MAX_TOTAL_EVS then break end
    local key = Game3.EV_KEYS[i]
    local yieldKey = Game3.EV_YIELD_KEYS[i]
    local yield = tonumber(row[yieldKey])
    if not yield and fainted then
      yield = tonumber(fainted[yieldKey])
    end
    local evIncrease = (yield or 0) * multiplier
    if total + evIncrease > Game3.MAX_TOTAL_EVS then
      evIncrease = Game3.MAX_TOTAL_EVS - total
    end
    local current = mon[key] or 0
    if current + evIncrease > 255 then
      evIncrease = 255 - current
    end
    if evIncrease > 0 then
      mon[key] = current + evIncrease
      total = total + evIncrease
    end
  end
end

function Game3:incrementGameStat(id)
  id = tonumber(id) or 0
  self.gameStats = self.gameStats or {}
  local n = (self.gameStats[id] or 0) + 1
  if n > 0xFFFFFF then n = 0xFFFFFF end
  self.gameStats[id] = n
end

function Game3:adjustFriendship(mon, event)
  if not mon or mon.isEgg then return false end
  event = tonumber(event) or 0
  local deltas = Game3.FRIENDSHIP_DELTAS[event]
  if not deltas then return false end
  if event == Game3.FRIENDSHIP_EVENT_WALKING
      and (self:gbaRandom() % 2) ~= 0 then
    return false
  end
  if event == Game3.FRIENDSHIP_EVENT_LEAGUE_BATTLE
      and not self:isLeagueTrainer(self.battle and self.battle.npc) then
    return false
  end
  local friendship = tonumber(mon.friendship) or Game3.BASE_FRIENDSHIP
  local level = 0
  if friendship > 99 then level = level + 1 end
  if friendship > 199 then level = level + 1 end
  local delta = deltas[level + 1] or 0
  if delta > 0 then
    local hold = self:holdEffectOf(mon)
    if hold == Game3.HOLD_EFFECT_HAPPINESS_UP then
      delta = math.floor(150 * delta / 100)
    end
  end
  friendship = friendship + delta
  if friendship < 0 then friendship = 0 end
  if friendship > Game3.MAX_FRIENDSHIP then friendship = Game3.MAX_FRIENDSHIP end
  mon.friendship = friendship
  return true
end

function Game3:isLeagueTrainer(npc)
  local class = npc and tonumber(npc.trainerClass)
  if not class then
    local tr = npc and self:trainerRow(npc.trainerId)
    class = tr and tonumber(tr.class)
  end
  return class == Game3.TRAINER_CLASS_LEADER
    or class == Game3.TRAINER_CLASS_ELITE_FOUR
    or class == Game3.TRAINER_CLASS_CHAMPION
end

function Game3:applyLeagueFriendship(npc)
  if not self:isLeagueTrainer(npc) then return end
  local party = self.party or {}
  for i = 1, #party do
    self:adjustFriendship(party[i], Game3.FRIENDSHIP_EVENT_LEAGUE_BATTLE)
  end
end

function Game3:maybeFaintFriendship(fainted, foe)
  if not fainted then return end
  if (fainted.hp or 0) > 0 then
    fainted._faintFriend = nil
    return
  end
  if not self:isPlayerBattler(fainted) then return end
  if fainted._faintFriend then return end
  fainted._faintFriend = true
  local foeLevel = (foe and foe.level) or 0
  local myLevel = fainted.level or 1
  if foeLevel <= myLevel then return end
  local event = Game3.FRIENDSHIP_EVENT_FAINT_SMALL
  if foeLevel - myLevel > 29 then
    event = Game3.FRIENDSHIP_EVENT_FAINT_LARGE
  end
  self:adjustFriendship(fainted, event)
end

function Game3:tickHappinessSteps()
  local n = self:varGet(Game3.VAR_HAPPINESS_STEP_COUNTER) + 1
  n = n % 128
  self:setScriptVar(Game3.VAR_HAPPINESS_STEP_COUNTER, n)
  if n ~= 0 then return end
  local party = self.party or {}
  for i = 1, #party do
    self:adjustFriendship(party[i], Game3.FRIENDSHIP_EVENT_WALKING)
  end
end

function Game3:leadMonFriendshipScore()
  local mon = self:leadMon()
  local n = (mon and tonumber(mon.friendship)) or 0
  if n == Game3.MAX_FRIENDSHIP then return 6 end
  if n >= 200 then return 5 end
  if n >= 150 then return 4 end
  if n >= 100 then return 3 end
  if n >= 50 then return 2 end
  if n >= 1 then return 1 end
  return 0
end

function Game3:swapRegisteredBike()
  local id = tonumber(self.registeredItem) or 0
  if id == Game3.ITEM_MACH_BIKE then
    self.registeredItem = Game3.ITEM_ACRO_BIKE
  elseif id == Game3.ITEM_ACRO_BIKE then
    self.registeredItem = Game3.ITEM_MACH_BIKE
  end
  return self.registeredItem or 0
end

function Game3:leadMonContestOk(key)
  local mon = self:leadMon()
  return ((mon and mon[key]) or 0) >= Game3.CONTEST_LEAD_STAT
end

function Game3:copyNicknameToStringVar1()
  local mon = self:selectedPartyMon()
  local nick = (mon and mon.name) or ""
  if #nick > Game3.NICKNAME_LEN then nick = nick:sub(1, Game3.NICKNAME_LEN) end
  self:setStringVar(1, nick)
end

function Game3:nameRaterNicknameChanged()
  local mon = self:selectedPartyMon()
  local old = (self.stringVars and self.stringVars[3]) or ""
  local now = (mon and mon.name) or ""
  if old == now then return 0 end
  return 1
end

function Game3:checkMonOtIdEqualsPlayer()
  local mon = self:selectedPartyMon()
  local ot = mon and mon.otId
  if ot == nil then return 0 end
  if ot == self:ensureTrainerId() then return 0 end
  return 1
end

function Game3:monOtNameMatchesPlayer()
  local mon = self:selectedPartyMon()
  local otName = (mon and mon.otName) or ""
  self:setStringVar(1, otName)
  if otName == "" then return 0 end
  if otName == self:playerName() then return 0 end
  return 1
end

function Game3:playerAvatarBike()
  if self.bike == "acro" then return 1 end
  if self.bike == "mach" then return 2 end
  return 0
end

function Game3:tryAdvanceCyclingRoadCollisions()
  if not self.bikeCyclingChallenge then return end
  local n = self.bikeCollisions or 0
  if n < Game3.CYCLING_ROAD_MAX_COLLISIONS then
    self.bikeCollisions = n + 1
  end
end

function Game3:beginCyclingRoadChallenge()
  self.bikeCyclingChallenge = true
  self.bikeCollisions = 0
  self.bikeCyclingTimer = self.vblankCounter or 0
end

function Game3:cyclingRoadCollisionString(n)
  n = tonumber(n) or 0
  if n > 99 then return Game3.TEXT_99_TIMES end
  return tostring(n) .. Game3.TEXT_TIMES
end

function Game3:cyclingRoadTimeString(numFrames)
  numFrames = tonumber(numFrames) or 0
  if numFrames >= 3600 then return Game3.TEXT_1_MINUTE end
  local sec = math.floor(numFrames / 60)
  local frac = math.floor(((numFrames % 60) * 100) / 60)
  return ("%2d.%02d"):format(sec, frac) .. Game3.TEXT_SECONDS
end

function Game3:determineCyclingRoadResults(numFrames, collisions)
  numFrames = tonumber(numFrames) or 0
  collisions = tonumber(collisions) or 0
  local result = 0
  if collisions == 0 then
    result = 5
  elseif collisions < 4 then
    result = 4
  elseif collisions < 10 then
    result = 3
  elseif collisions < 20 then
    result = 2
  elseif collisions < 100 then
    result = 1
  end
  local sec = math.floor(numFrames / 60)
  if sec <= 10 then
    result = result + 5
  elseif sec <= 15 then
    result = result + 4
  elseif sec <= 20 then
    result = result + 3
  elseif sec <= 40 then
    result = result + 2
  elseif sec < 60 then
    result = result + 1
  end
  self:setStringVar(1, self:cyclingRoadCollisionString(collisions))
  self:setStringVar(2, self:cyclingRoadTimeString(numFrames))
  self:setScriptVar(Gen3Script.VAR_RESULT, result)
  return result
end

function Game3:recordCyclingRoadResults(numFrames, collisions)
  numFrames = tonumber(numFrames) or 0
  collisions = tonumber(collisions) or 0
  local low = self:varGet(Game3.VAR_CYCLING_ROAD_RECORD_TIME_L)
  local high = self:varGet(Game3.VAR_CYCLING_ROAD_RECORD_TIME_H)
  local framesRecord = low + high * 65536
  if framesRecord > numFrames or framesRecord == 0 then
    self:setScriptVar(Game3.VAR_CYCLING_ROAD_RECORD_TIME_L, numFrames % 65536)
    self:setScriptVar(Game3.VAR_CYCLING_ROAD_RECORD_TIME_H,
      math.floor(numFrames / 65536))
    self:setScriptVar(Game3.VAR_CYCLING_ROAD_RECORD_COLLISIONS, collisions)
  end
end

function Game3:finishCyclingRoadChallenge()
  local numFrames = (self.vblankCounter or 0) - (self.bikeCyclingTimer or 0)
  if numFrames < 0 then numFrames = 0 end
  local collisions = self.bikeCollisions or 0
  local result = self:determineCyclingRoadResults(numFrames, collisions)
  self:recordCyclingRoadResults(numFrames, collisions)
  return result
end

function Game3:getRecordedCyclingRoadResults()
  local low = self:varGet(Game3.VAR_CYCLING_ROAD_RECORD_TIME_L)
  local high = self:varGet(Game3.VAR_CYCLING_ROAD_RECORD_TIME_H)
  local framesRecord = low + high * 65536
  if framesRecord == 0 then return 0 end
  self:determineCyclingRoadResults(framesRecord,
    self:varGet(Game3.VAR_CYCLING_ROAD_RECORD_COLLISIONS))
  return 1
end

function Game3:updateCyclingRoadState()
  local last = self.lastUsedWarp
  if last
      and last.mapGroup == Game3.MAP_ROUTE110_CYCLING_NORTH_GROUP
      and last.mapNum == Game3.MAP_ROUTE110_CYCLING_NORTH_NUM then
    return
  end
  local state = self:varGet(Game3.VAR_CYCLING_CHALLENGE_STATE)
  if state == 2 or state == 3 then
    self:setScriptVar(Game3.VAR_CYCLING_CHALLENGE_STATE, 0)
  end
end

function Game3:runSpecial(id)
  id = tonumber(id) or 0
  local before = self:varGet(Gen3Script.VAR_RESULT)
  if id == Game3.SPECIAL_HEAL_PARTY then
    self:healParty()
  elseif id == Game3.SPECIAL_GET_POKEDEX_INFO then
    local seen, caught = self:dexCounts()
    self.scriptVars = self.scriptVars or {}
    self.scriptVars[0x8004] = seen
    self.scriptVars[0x8005] = caught
    self.scriptVars[0x8006] = self:hasNationalDex() and 1 or 0
  elseif id == Game3.SPECIAL_SHOW_POKEDEX_RATING then
    local _, caught = self:dexCounts()
    if self.sayScript then self:sayScript(self:pokedexRating(caught)) end
  elseif id == Game3.SPECIAL_COMPLETED_HOENN_POKEDEX then
    self.scriptVars = self.scriptVars or {}
    self.scriptVars[Gen3Script.VAR_RESULT] = self:completedHoennPokedex() and 1 or 0
  elseif id == Game3.SPECIAL_GET_CONTEST_WINNER_IDX then
    self:setScriptVar(Gen3Script.VAR_RESULT, (self.contest and self.contest.winner) or 0)
  elseif id == Game3.SPECIAL_GET_CONTEST_PLAYER_MON_IDX then
    local idx = self.contestMonIndex or (self.contest and self.contest.monIndex) or 1
    self:setScriptVar(Gen3Script.VAR_RESULT, idx - 1)
  elseif id == Game3.SPECIAL_CHECK_SELECTED_MON_CONTEST then
    local idx = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
    local mon = self.party and self.party[idx]
    local ok = self:canEnterContest(mon)
    if ok then self.contestMonIndex = idx end
    self:setScriptVar(Gen3Script.VAR_RESULT, ok and 1 or 0)
  elseif id == Game3.SPECIAL_GET_MON_CONDITION then
    local idx = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
    local cat = (self.scriptVars and self.scriptVars[Game3.VAR_CONTEST_CATEGORY]) or 0
    local mon = self.party and self.party[idx]
    self:setScriptVar(Gen3Script.VAR_RESULT, self:contestCondition(mon, cat))
  elseif id == Game3.SPECIAL_GIVE_CONTEST_RIBBON then
    local c = self.contest
    if c and c.won then
      self:giveContestRibbon(self.party[c.monIndex], c.category, c.rank)
    end
  elseif id == Game3.SPECIAL_HAS_MON_WON_THIS_CONTEST then
    local idx = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
    local cat = (self.scriptVars and self.scriptVars[Game3.VAR_CONTEST_CATEGORY]) or 0
    local rank = (self.scriptVars and self.scriptVars[Game3.VAR_CONTEST_RANK]) or 0
    local mon = self.party and self.party[idx]
    self:setScriptVar(Gen3Script.VAR_RESULT,
      (self:contestRibbon(mon, cat) > rank) and 1 or 0)
  elseif id == Game3.SPECIAL_SHOW_CONTEST_WINNER then
    if self.sayScript then self:sayScript(self:contestResultsText()) end
  elseif id == Game3.SPECIAL_CHECK_LEAD_MON_COOL then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:leadMonContestOk("cool") and 1 or 0)
  elseif id == Game3.SPECIAL_CHECK_LEAD_MON_BEAUTY then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:leadMonContestOk("beauty") and 1 or 0)
  elseif id == Game3.SPECIAL_CHECK_LEAD_MON_CUTE then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:leadMonContestOk("cute") and 1 or 0)
  elseif id == Game3.SPECIAL_CHECK_LEAD_MON_SMART then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:leadMonContestOk("smart") and 1 or 0)
  elseif id == Game3.SPECIAL_CHECK_LEAD_MON_TOUGH then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:leadMonContestOk("tough") and 1 or 0)
  elseif id == Game3.SPECIAL_GET_NUM_VALID_DAYCARE_PARTY_MONS then
    self:setScriptVar(Gen3Script.VAR_RESULT, #(self.party or {}))
  elseif id == Game3.SPECIAL_GET_DAYCARE_STATE then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:daycareState())
  elseif id == Game3.SPECIAL_REJECT_EGG_FROM_DAYCARE then
    self:rejectDaycareEgg()
  elseif id == Game3.SPECIAL_GIVE_EGG_FROM_DAYCARE then
    self:giveDaycareEgg()
  elseif id == Game3.SPECIAL_SET_DAYCARE_COMPAT_STRING then
    if self.sayScript then self:sayScript(self:daycareCompatText()) end
  elseif id == Game3.SPECIAL_STORE_SELECTED_IN_DAYCARE then
    local idx = (self.scriptVars and self.scriptVars[0x8004]) or 0
    self:depositToDaycare(idx + 1)
  elseif id == Game3.SPECIAL_CHOOSE_SEND_DAYCARE_MON then
    self:beginScriptWait()
    self.field = { kind = "daycare_send", cursor = 0, scripted = true }
  elseif id == Game3.SPECIAL_SHOW_DAYCARE_LEVEL_MENU then
    self:beginScriptWait()
    self.field = { kind = "daycare_take", cursor = 0, scripted = true }
  elseif id == Game3.SPECIAL_GET_DAYCARE_LEVELS_GAINED then
    local slot = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
    self:setScriptVar(Gen3Script.VAR_RESULT, self:daycareLevelsGained(slot))
  elseif id == Game3.SPECIAL_GET_DAYCARE_COST then
    local slot = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
    self:setScriptVar(0x8005, self:daycareCost(slot))
  elseif id == Game3.SPECIAL_TAKE_POKEMON_FROM_DAYCARE then
    local slot = ((self.scriptVars and self.scriptVars[0x8004]) or 0) + 1
    self:takeFromDaycare(slot)
  elseif id == Game3.SPECIAL_CHECK_PLAYER_HAS_SECRET_BASE then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:hasSecretBase() and 1 or 0)
  elseif id == Game3.SPECIAL_MOVE_OUT_OF_SECRET_BASE then
    self:exitSecretBase()
  elseif id == Game3.SPECIAL_TURN_OFF_TV_SCREEN then
    self.tvOn = false
  elseif id == Game3.SPECIAL_GET_PLAYER_BIG_GUY_GIRL_STRING then
    self:setStringVar(1, self:isFemale() and Game3.TEXT_BIG_GIRL or Game3.TEXT_BIG_GUY)
  elseif id == Game3.SPECIAL_GET_RIVAL_SON_DAUGHTER_STRING then
    self:setStringVar(1, self:isFemale() and Game3.TEXT_SON or Game3.TEXT_DAUGHTER)
  elseif id == Game3.SPECIAL_CHOOSE_STARTER then
    self:beginScriptWait()
    self.field = { kind = "starter", cursor = 1, scripted = true }
  elseif id == Game3.SPECIAL_CHANGE_POKEMON_NICKNAME then
    self:openNickname()
  elseif id == Game3.SPECIAL_SELECT_MON_FOR_NPC_TRADE then
    self:selectMonForNpcTrade()
  elseif id == Game3.SPECIAL_GET_IN_GAME_TRADE_SPECIES then
    self:getInGameTradeSpeciesInfo()
  elseif id == Game3.SPECIAL_CREATE_IN_GAME_TRADE then
    self:createInGameTradePokemon()
  elseif id == Game3.SPECIAL_DO_IN_GAME_TRADE_SCENE then
    -- Link-cable cinema is a waitstate on hardware; the swap already
    -- happened in CreateInGameTradePokemon.
  elseif id == Game3.SPECIAL_GET_TRADE_SPECIES then
    self:getTradeSpecies()
  elseif id == Game3.SPECIAL_SAVE_PLAYER_PARTY then
    self:savePlayerParty()
  elseif id == Game3.SPECIAL_LOAD_PLAYER_PARTY then
    self:loadPlayerParty()
  elseif id == Game3.SPECIAL_PUT_ZIGZAGOON then
    self:putZigzagoonInPlayerParty()
  elseif id == Game3.SPECIAL_IS_STARTER_IN_PARTY then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:isStarterInParty() and 1 or 0)
  elseif id == Game3.SPECIAL_START_WALLY_TUTORIAL_BATTLE then
    self:startWallyTutorialBattle()
  elseif id == Game3.SPECIAL_SHOULD_TRY_REMATCH
      or id == Game3.SPECIAL_IS_TRAINER_READY_REMATCH
      or id == Game3.SPECIAL_IS_POKERUS_IN_PARTY then
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
  elseif id == Game3.SPECIAL_CALCULATE_PARTY_COUNT then
    self:setScriptVar(Gen3Script.VAR_RESULT, #(self.party or {}))
  elseif id == Game3.SPECIAL_SHOW_EASY_CHAT then
    self:showEasyChatScreen()
  elseif id == Game3.SPECIAL_BUFFER_TRENDY_PHRASE then
    self:bufferTrendyPhraseString()
  elseif id == Game3.SPECIAL_IS_TRENDY_PHRASE_BORING then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:isTrendyPhraseBoring() and 1 or 0)
  elseif id == Game3.SPECIAL_BUFFER_RANDOM_HOBBY then
    self:bufferRandomHobbyOrLifestyle()
  elseif id == Game3.SPECIAL_DEWFORD_HALL_PAINTING then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:dewfordHallPaintingIndex())
  elseif id == Game3.SPECIAL_TV_NAME_RATER_SHOW then
    return self:nameRaterNicknameChanged()
  elseif id == Game3.SPECIAL_TV_COPY_NICKNAME then
    self:copyNicknameToStringVar1()
  elseif id == Game3.SPECIAL_TV_CHECK_MON_OT_ID then
    self:setScriptVar(Gen3Script.VAR_RESULT, self:checkMonOtIdEqualsPlayer())
  elseif id == Game3.SPECIAL_SCRIPT_GET_PARTY_MON_SPECIES then
    return self:partyMonSpecies2(self:selectedPartyMon())
  elseif id == Game3.SPECIAL_IS_SELECTED_MON_EGG then
    local mon = self:selectedPartyMon()
    self:setScriptVar(Gen3Script.VAR_RESULT, (mon and mon.isEgg) and 1 or 0)
  elseif id == Game3.SPECIAL_MON_OT_NAME_MATCHES_PLAYER then
    return self:monOtNameMatchesPlayer()
  elseif id == Game3.SPECIAL_LEAD_MON_HAS_EFFORT_RIBBON then
    local mon = self:leadMon()
    return (mon and mon.effortRibbon) and 1 or 0
  elseif id == Game3.SPECIAL_GIVE_LEAD_MON_EFFORT_RIBBON then
    local mon = self:leadMon()
    if mon then mon.effortRibbon = true end
    self:incrementGameStat(Game3.GAME_STAT_RECEIVED_RIBBONS)
    self.flags = self.flags or {}
    self.flags[Game3.FLAG_SYS_RIBBON_GET] = true
  elseif id == Game3.SPECIAL_ARE_LEAD_MON_EVS_MAXED then
    return (self:monEvCount(self:leadMon()) >= Game3.MAX_TOTAL_EVS) and 1 or 0
  elseif id == Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE then
    return self:playerAvatarBike()
  elseif id == Game3.SPECIAL_BEGIN_CYCLING_ROAD then
    self:beginCyclingRoadChallenge()
  elseif id == Game3.SPECIAL_FINISH_CYCLING_ROAD then
    self:finishCyclingRoadChallenge()
  elseif id == Game3.SPECIAL_GET_RECORDED_CYCLING_ROAD then
    return self:getRecordedCyclingRoadResults()
  elseif id == Game3.SPECIAL_UPDATE_CYCLING_ROAD_STATE then
    self:updateCyclingRoadState()
  elseif id == Game3.SPECIAL_GET_PLAYER_FACING then
    return Game3.dirId(self.facing)
  elseif id == Game3.SPECIAL_GET_LEAD_MON_FRIENDSHIP then
    return self:leadMonFriendshipScore()
  elseif id == Game3.SPECIAL_SWAP_REGISTERED_BIKE then
    self:swapRegisteredBike()
  elseif id == Game3.SPECIAL_MAUVILLE_GYM_2 then
    self:mauvilleGymSpecial2()
  elseif id == Game3.SPECIAL_MAUVILLE_GYM_1 then
    self:mauvilleGymSpecial1()
  elseif id == Game3.SPECIAL_DRAW_WHOLE_MAP_VIEW then
    self:drawWholeMapView()
  elseif id == Game3.SPECIAL_STORE_PLAYER_COORDS then
    self:storePlayerCoordsInVars()
  elseif id == Game3.SPECIAL_MAUVILLE_GYM_3 then
    self:mauvilleGymSpecial3()
  elseif id == Game3.SPECIAL_SHOW_FIELD_MESSAGE_VAR4 then
    self:showFieldMessageStringVar4()
  elseif id == Game3.SPECIAL_PETALBURG_GYM_SLIDE
      or id == Game3.SPECIAL_PETALBURG_GYM_OPEN then
    self:petalburgGymOpenDoors()
  elseif id == Game3.SPECIAL_GET_PLAYER_TRAINER_ID_ONES then
    return self:playerTrainerIdOnesDigit()
  elseif id == Game3.SPECIAL_SET_HIDDEN_ITEM_FLAG then
    self:setHiddenItemFlag()
  elseif id == Game3.SPECIAL_CABLE_CAR_WARP then
    self:cableCarWarp()
  elseif id == Game3.SPECIAL_CABLE_CAR then
    self:cableCar()
  elseif id == Game3.SPECIAL_SET_TRICK_HOUSE_END then
    self:setTrickHouseEndRoomFlag(true)
  elseif id == Game3.SPECIAL_RESET_TRICK_HOUSE_END then
    self:setTrickHouseEndRoomFlag(false)
  elseif id >= Game3.SPECIAL_GET_BERRY_TREE_DATA
      and id <= Game3.SPECIAL_PLAYER_HAS_BERRIES then
    self:runBerrySpecial(id)
  end
  local after = self:varGet(Gen3Script.VAR_RESULT)
  if after ~= before then return after end
  return 0
end

-- pokeruby GiveMonToPlayer: stamp OT unless the mon already has one
-- (in-game trade / already owned).
function Game3:stampPlayerOt(mon)
  if not mon or mon.otId ~= nil then return mon end
  mon.otId = self:ensureTrainerId()
  mon.otName = self:playerName()
  return mon
end

function Game3:addToParty(mon)
  self.party = self.party or {}
  if #self.party >= Game3.PARTY_MAX then return false end
  self:stampPlayerOt(mon)
  self.party[#self.party + 1] = self:cloneMon(mon)
  if not mon.isEgg then self:markCaught(mon.species) end
  return true
end

function Game3:ensurePc()
  if type(self.pc) ~= "table" then self.pc = {} end
  for b = 1, Game3.BOX_COUNT do
    if type(self.pc[b]) ~= "table" then self.pc[b] = {} end
  end
end

function Game3:pcFree()
  self:ensurePc()
  local n = 0
  for b = 1, Game3.BOX_COUNT do
    n = n + (Game3.BOX_SIZE - #(self.pc[b] or {}))
  end
  return n
end

function Game3:hasMonSpace()
  return #(self.party or {}) < Game3.PARTY_MAX or self:pcFree() > 0
end

function Game3:sendToPc(mon)
  if not mon then return nil end
  self:ensurePc()
  self:stampPlayerOt(mon)
  for b = 1, Game3.BOX_COUNT do
    local box = self.pc[b]
    if #box < Game3.BOX_SIZE then
      box[#box + 1] = self:cloneMon(mon)
      self:markCaught(mon.species)
      return b
    end
  end
end

function Game3:healthyCount(except)
  local n = 0
  local party = self.party or {}
  for i = 1, #party do
    local mon = party[i]
    if mon and mon ~= except and self:canBattle(mon) then n = n + 1 end
  end
  return n
end

function Game3:canDeposit(index)
  local party = self.party or {}
  if #party < 2 then return false, "You can't deposit your last POKeMON!" end
  local mon = party[index]
  if not mon then return false, "There's nothing here." end
  if mon.isEgg then return false, "You can't leave an EGG." end
  if self:canBattle(mon) and self:healthyCount(mon) < 1 then
    return false, "You can't deposit the last POKeMON that can battle!"
  end
  return true
end

function Game3:depositFromParty(index)
  local ok, msg = self:canDeposit(index)
  if not ok then return false, msg end
  local mon = self.party[index]
  local box = self:sendToPc(mon)
  if not box then return false, "The BOX is full." end
  table.remove(self.party, index)
  return true, ("Deposited %s in BOX %d."):format(mon.name, box)
end

function Game3:withdrawFromBox(boxIndex, slot)
  self:ensurePc()
  local box = self.pc[boxIndex]
  if type(box) ~= "table" then return false, "The BOX is empty." end
  local mon = box[slot]
  if not mon then return false, "There's nothing here." end
  if not self:addToParty(mon) then return false, "Your party's full!" end
  table.remove(box, slot)
  return true, ("Took %s."):format(mon.name)
end

function Game3:openPc()
  self:ensurePc()
  self.field = { kind = "pc", mode = "root", cursor = 0, box = 1, note = nil }
  return true
end

function Game3:tryPc()
  local map = self.map
  if not map then return false end
  local dx, dy = Game3.deltaFromFacing(self.facing)
  local x, y = self.playerX + dx, self.playerY + dy
  if Game3.isPc(self:behaviorAt(map, x, y)) then return self:openPc() end
  if Game3.isCounter(self:behaviorAt(map, x, y))
      and Game3.isPc(self:behaviorAt(map, x + dx, y + dy)) then
    return self:openPc()
  end
  return false
end

function Game3:tryCatch(mon, ballBonus)
  ballBonus = ballBonus or Game3.POKE_BALL_BONUS
  if ballBonus >= 255 then return true, 3 end
  local rate = (mon and mon.catchRate) or 45
  local row = mon and self:speciesRow(mon.species)
  if row and row.catchRate then rate = row.catchRate end
  local a = Game3.catchValue(mon.hp, mon.maxHp, rate, ballBonus)
  a = math.floor(a * Game3.statusCatchMul(mon and mon.status) / 10)
  if a >= 255 then return true, 3 end
  local b = Game3.shakeThreshold(a)
  local shakes = 0
  for _ = 1, 4 do
    if (self:rand(65536) - 1) >= b then
      return false, shakes
    end
    if shakes < 3 then shakes = shakes + 1 end
  end
  return true, 3
end

function Game3:throwBall(itemId)
  local b = self.battle
  if not b then return end
  itemId = itemId or Game3.ITEM_POKE_BALL
  if b.isTrainer then
    b.text = "The trainer blocked the BALL!"
    b.kind = "menu_msg"
    return
  end
  if not Game3.isBall(itemId) then
    b.text = "You can't use that here!"
    b.kind = "menu_msg"
    return
  end
  if not self:hasMonSpace() then
    b.text = "There's no more room for POKeMON!"
    b.kind = "menu_msg"
    return
  end
  if not b.wallyTutorial then
    if not self:spendBall(itemId) then
      b.text = "You have no more!"
      b.kind = "menu_msg"
      return
    end
  end
  local bonus = self:catchBallBonus(itemId, b.enemy)
  local queue = { ("You used a %s!"):format(self:itemName(itemId)) }
  local ok, shakes
  if b.wallyTutorial then
    ok, shakes = true, 3
  else
    ok, shakes = self:tryCatch(b.enemy, bonus)
  end
  if ok then
    for _ = 1, 3 do queue[#queue + 1] = "The ball shook!" end
    queue[#queue + 1] = ("Gotcha! %s was caught!"):format(b.enemy.name)
    if (b.player.hp or 0) > 0 and not b.wallyTutorial then
      local texts = self:awardExp(b.player, b.enemy, b.isTrainer)
      for i = 1, #texts do queue[#queue + 1] = texts[i] end
    end
    if not b.wallyTutorial then
      if not self:addToParty(b.enemy) then
        local box = self:sendToPc(b.enemy)
        if box then
          queue[#queue + 1] = ("%s was transferred to BOX %d."):format(b.enemy.name, box)
        else
          queue[#queue + 1] = "The BOX is full."
        end
      end
    end
    b.caught = true
  else
    for _ = 1, shakes do queue[#queue + 1] = "The ball shook!" end
    queue[#queue + 1] = Game3.catchFailText(shakes)
    if (b.player.hp or 0) > 0 and (b.enemy.hp or 0) > 0 then
      self:queueEnemyAction(queue)
    end
  end
  b.queue = queue
  b.qi = 1
  b.kind = "text"
  b.text = queue[1]
  b.turns = (b.turns or 0) + 1
end

function Game3:useBattleItem(itemId)
  local b = self.battle
  if not b then return false end
  itemId = tonumber(itemId)
  if Game3.isBall(itemId) then
    self:throwBall(itemId)
    return true
  end
  if not self:healAmount(itemId) and not self:statusHeal(itemId) then
    b.text = "This can't be used now."
    b.kind = "menu_msg"
    return false
  end
  local ok, msg = self:useItemOnMon(b.player, itemId)
  if not ok then
    b.text = msg or "It won't have any effect."
    b.kind = "menu_msg"
    return false
  end
  local queue = { msg }
  if (b.enemy.hp or 0) > 0 and (b.player.hp or 0) > 0 then
    self:queueEnemyAction(queue)
  end
  b.queue = queue
  b.qi = 1
  b.kind = "text"
  b.text = queue[1]
  b.turns = (b.turns or 0) + 1
  return true
end

local function hasStab(mon, moveType)
  return mon and (mon.type1 == moveType or mon.type2 == moveType)
end

local function staged(mon, stat)
  local base = mon[stat] or 1
  local stage = mon.stages and mon.stages[stat] or 0
  return math.max(1, math.floor(base * Game3.stageMul(stage)))
end

function Game3.lowKickPower(weight)
  weight = tonumber(weight) or 0
  local t = Game3.LOW_KICK_WEIGHTS
  for i = 1, #t, 2 do
    if t[i] > weight then return t[i + 1] end
  end
  return 120
end

function Game3:monWeight(mon)
  if not mon then return 0 end
  local w = tonumber(mon.weight)
  if w then return w end
  local row = self:speciesRow(mon.species)
  w = row and tonumber(row.weight)
  if w then return w end
  return Game3.DEX_WEIGHT[mon.species or 0] or 0
end

function Game3:boostedPower(attacker, move, defender)
  local power = move.power or 0
  local effect = move.effect or 0
  local moveType = self:attackType(attacker, move)
  if effect == Game3.EFFECT_LOW_KICK then
    power = Game3.lowKickPower(self:monWeight(defender))
  end
  if effect == Game3.EFFECT_HIDDEN_POWER then
    power = Game3.hiddenPowerPower(attacker and attacker.ivs)
  end
  if attacker.flashFire and moveType == Game3.TYPE_FIRE then
    power = math.floor(power * 3 / 2)
  end
  -- calculate_base_damage.c: gBattleMovePower /= 2 when any battler
  -- has STATUS3_MUDSPORT / WATERSPORT (AbilityBattleEffects 0xFD / 0xFE).
  if moveType == Game3.TYPE_ELECTRIC and self:fieldHasSport("mudSport") then
    power = math.floor(power / 2)
  end
  if moveType == Game3.TYPE_FIRE and self:fieldHasSport("waterSport") then
    power = math.floor(power / 2)
  end
  local hp, maxHp = attacker.hp or 0, attacker.maxHp or 1
  if hp * 3 > maxHp then return power end
  local ab = attacker.ability or 0
  if ab == Game3.ABILITY_BLAZE and moveType == Game3.TYPE_FIRE then
    return math.floor(power * 3 / 2)
  end
  if ab == Game3.ABILITY_TORRENT and moveType == Game3.TYPE_WATER then
    return math.floor(power * 3 / 2)
  end
  if ab == Game3.ABILITY_OVERGROW and moveType == Game3.TYPE_GRASS then
    return math.floor(power * 3 / 2)
  end
  if ab == Game3.ABILITY_SWARM and moveType == Game3.TYPE_BUG then
    return math.floor(power * 3 / 2)
  end
  if move.effect == Game3.EFFECT_SOLARBEAM and not self:weatherSuppressed() then
    local w = self.battle and self.battle.weather
    if w == Game3.WEATHER_RAIN or w == Game3.WEATHER_SAND
        or w == Game3.WEATHER_HAIL then
      power = math.floor(power / 2)
    end
  end
  return power
end

function Game3.hasType(mon, typeId)
  return mon and (mon.type1 == typeId or mon.type2 == typeId)
end

function Game3.statusTag(status)
  if status == Game3.STATUS_PSN then return "PSN" end
  if status == Game3.STATUS_BRN then return "BRN" end
  if status == Game3.STATUS_PAR then return "PAR" end
  if status == Game3.STATUS_SLP then return "SLP" end
  if status == Game3.STATUS_FRZ then return "FRZ" end
  return ""
end

function Game3.statusCatchMul(status)
  if status == Game3.STATUS_SLP or status == Game3.STATUS_FRZ then return 20 end
  if status == Game3.STATUS_PAR or status == Game3.STATUS_BRN
      or status == Game3.STATUS_PSN then
    return 15
  end
  return 10
end

function Game3:canStatus(mon, status)
  if not mon or (mon.hp or 0) <= 0 then return false end
  if mon.status then return false end
  if status == Game3.STATUS_BRN then
    if Game3.hasType(mon, Game3.TYPE_FIRE)
        or self:hasAbility(mon, Game3.ABILITY_WATER_VEIL) then
      return false
    end
  end
  if status == Game3.STATUS_FRZ then
    if Game3.hasType(mon, Game3.TYPE_ICE)
        or self:hasAbility(mon, Game3.ABILITY_MAGMA_ARMOR) then
      return false
    end
  end
  if status == Game3.STATUS_PSN then
    if Game3.hasType(mon, Game3.TYPE_POISON)
        or Game3.hasType(mon, Game3.TYPE_STEEL)
        or self:hasAbility(mon, Game3.ABILITY_IMMUNITY) then
      return false
    end
  end
  if status == Game3.STATUS_PAR
      and self:hasAbility(mon, Game3.ABILITY_LIMBER) then
    return false
  end
  if status == Game3.STATUS_SLP
      and (self:hasAbility(mon, Game3.ABILITY_INSOMNIA)
        or self:hasAbility(mon, Game3.ABILITY_VITAL_SPIRIT)) then
    return false
  end
  return true
end

function Game3:applyStatus(mon, status)
  if not self:canStatus(mon, status) then return nil end
  mon.status = status
  if status == Game3.STATUS_SLP then
    mon.sleepTurns = self:rand(3)
  end
  local name = mon.name or "POKeMON"
  if status == Game3.STATUS_BRN then return ("%s was burned!"):format(name) end
  if status == Game3.STATUS_PSN then return ("%s was poisoned!"):format(name) end
  if status == Game3.STATUS_PAR then
    return ("%s is paralyzed! It may be unable to move!"):format(name)
  end
  if status == Game3.STATUS_SLP then return ("%s fell asleep!"):format(name) end
  if status == Game3.STATUS_FRZ then return ("%s was frozen solid!"):format(name) end
end

function Game3.statusFromEffect(effect)
  if effect == Game3.EFFECT_POISON_HIT or effect == Game3.EFFECT_POISON
      or effect == Game3.EFFECT_TOXIC then
    return Game3.STATUS_PSN
  end
  if effect == Game3.EFFECT_BURN_HIT or effect == Game3.EFFECT_WILL_O_WISP then
    return Game3.STATUS_BRN
  end
  if effect == Game3.EFFECT_FREEZE_HIT then return Game3.STATUS_FRZ end
  if effect == Game3.EFFECT_PARALYZE_HIT or effect == Game3.EFFECT_PARALYZE then
    return Game3.STATUS_PAR
  end
  if effect == Game3.EFFECT_SLEEP then return Game3.STATUS_SLP end
end

function Game3:statusBlocks(mon, move)
  local texts = {}
  local status = mon and mon.status
  if status == Game3.STATUS_FRZ then
    local thaw = (self:attackType(mon, move) == Game3.TYPE_FIRE)
      or (self:rand(100) <= 20)
    if thaw then
      mon.status = nil
      texts[1] = ("%s thawed out!"):format(mon.name)
      return false, texts
    end
    texts[1] = ("%s is frozen solid!"):format(mon.name)
    return true, texts
  end
  if status == Game3.STATUS_SLP then
    local left = mon.sleepTurns or 0
    if left <= 0 then
      mon.status = nil
      mon.sleepTurns = nil
      texts[1] = ("%s woke up!"):format(mon.name)
      return false, texts
    end
    mon.sleepTurns = left - 1
    if self:hasAbility(mon, Game3.ABILITY_EARLY_BIRD) and mon.sleepTurns > 0 then
      mon.sleepTurns = mon.sleepTurns - 1
    end
    texts[1] = ("%s is fast asleep!"):format(mon.name)
    return true, texts
  end
  if status == Game3.STATUS_PAR and self:rand(100) <= 25 then
    texts[1] = ("%s is paralyzed! It can't move!"):format(mon.name)
    return true, texts
  end
  if self:hasAbility(mon, Game3.ABILITY_TRUANT) then
    if mon.truant then
      mon.truant = nil
      texts[#texts + 1] = ("%s is loafing around!"):format(mon.name)
      return true, texts
    end
    mon.truant = true
  end
  return false, texts
end

function Game3:applyConfuse(mon)
  if not mon or (mon.hp or 0) <= 0 then return nil end
  if self:hasAbility(mon, Game3.ABILITY_OWN_TEMPO) then return nil end
  if (mon.confuseTurns or 0) > 0 then return nil end
  mon.confuseTurns = (self:rand(4) - 1) + 2
  return ("%s became confused!"):format(mon.name or "POKeMON")
end

function Game3:confusionDamage(mon)
  if not mon then return 0 end
  local attack = staged(mon, "atk")
  if mon.status == Game3.STATUS_BRN then
    attack = math.max(1, math.floor(attack / 2))
  end
  local defense = staged(mon, "def")
  local dmg = Game3.damage(
    mon.level, Game3.CONFUSION_POWER, attack, defense, false, 10)
  local roll = 85 + self:rand(16) - 1
  dmg = math.max(1, math.floor(dmg * roll / 100))
  if mon.endured and dmg >= (mon.hp or 0) then
    dmg = math.max(0, (mon.hp or 1) - 1)
  end
  mon.hp = math.max(0, (mon.hp or 0) - dmg)
  return dmg
end

function Game3:confuseBlocks(mon)
  local texts = {}
  local left = mon and mon.confuseTurns or 0
  if left < 1 then return false, texts end
  mon.confuseTurns = left - 1
  if mon.confuseTurns < 1 then
    texts[1] = ("%s snapped out of confusion!"):format(mon.name)
    return false, texts
  end
  texts[1] = ("%s is confused!"):format(mon.name)
  if self:rand(100) <= 50 then
    self:confusionDamage(mon)
    texts[#texts + 1] = "It hurt itself in its confusion!"
    if (mon.hp or 0) <= 0 then
      texts[#texts + 1] = ("%s fainted!"):format(mon.name)
    end
    return true, texts
  end
  return false, texts
end

-- pokeemerald: Random() & 3; if > 1 then (Random() & 3) + 2 else + 2.
function Game3.multiHitCount(first, second)
  first = (first or 0) % 4
  if first > 1 then return ((second or 0) % 4) + 2 end
  return first + 2
end

function Game3:rollMultiHits()
  local first = self:rand(4) - 1
  if first > 1 then return Game3.multiHitCount(first, self:rand(4) - 1) end
  return Game3.multiHitCount(first, 0)
end

function Game3.isFlinchEffect(effect)
  return effect == Game3.EFFECT_FLINCH_HIT
    or effect == Game3.EFFECT_FLINCH_MINIMIZE_HIT
    or effect == Game3.EFFECT_SKY_ATTACK
end

function Game3.critStage(effect, focused)
  local n = focused and 2 or 0
  if effect == Game3.EFFECT_HIGH_CRITICAL
      or effect == Game3.EFFECT_RAZOR_WIND
      or effect == Game3.EFFECT_SKY_ATTACK
      or effect == Game3.EFFECT_BLAZE_KICK
      or effect == Game3.EFFECT_POISON_TAIL then
    n = n + 1
  end
  if n > 4 then n = 4 end
  return n
end

-- pokeruby sCriticalHitChance: 1/N at stages 0-4.
Game3.CRIT_CHANCES = { 16, 8, 4, 3, 2 }

function Game3.critDenom(effect, focused)
  return Game3.CRIT_CHANCES[Game3.critStage(effect, focused) + 1]
end

function Game3.recoilDenom(effect)
  if effect == Game3.EFFECT_RECOIL then return 4 end
  if effect == Game3.EFFECT_DOUBLE_EDGE then return 3 end
end

function Game3:hitCountFor(effect)
  if effect == Game3.EFFECT_MULTI_HIT then return self:rollMultiHits() end
  if effect == Game3.EFFECT_DOUBLE_HIT then return 2 end
  return 1
end

function Game3:useRestoreHp(attacker, texts)
  local hp, maxHp = attacker.hp or 0, attacker.maxHp or 0
  if maxHp < 1 or hp >= maxHp then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  local heal = math.max(1, math.floor(maxHp / 2))
  attacker.hp = math.min(maxHp, hp + heal)
  texts[#texts + 1] = ("%s regained health!"):format(attacker.name)
  return texts
end

function Game3:useRest(attacker, texts)
  if attacker.status == Game3.STATUS_SLP then
    texts[#texts + 1] = ("%s is already asleep!"):format(attacker.name)
    return texts
  end
  local hp, maxHp = attacker.hp or 0, attacker.maxHp or 0
  if maxHp < 1 or hp >= maxHp then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  attacker.hp = maxHp
  attacker.status = Game3.STATUS_SLP
  attacker.sleepTurns = 2
  texts[#texts + 1] = ("%s went to sleep and became healthy!"):format(
    attacker.name)
  return texts
end

function Game3:statusResidual(mon)
  if not mon or (mon.hp or 0) <= 0 then return {} end
  if self:hasAbility(mon, Game3.ABILITY_SHED_SKIN) and mon.status
      and self:rand(100) <= 30 then
    mon.status = nil
    mon.sleepTurns = nil
    return { ("%s's %s cured its status!"):format(
      mon.name, Game3.abilityName(Game3.ABILITY_SHED_SKIN)) }
  end
  local status = mon.status
  if status ~= Game3.STATUS_BRN and status ~= Game3.STATUS_PSN then return {} end
  local dmg = math.max(1, math.floor((mon.maxHp or 1) / 8))
  mon.hp = math.max(0, (mon.hp or 0) - dmg)
  local texts = {}
  if status == Game3.STATUS_BRN then
    texts[1] = ("%s was hurt by its burn!"):format(mon.name)
  else
    texts[1] = ("%s was hurt by poison!"):format(mon.name)
  end
  if (mon.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(mon.name)
  end
  return texts
end

function Game3:isPlayerBattler(mon)
  local b = self.battle
  if not (b and mon) then return false end
  return mon == b.player or mon == b.player2
end

function Game3:battlerSlot(mon)
  local b = self.battle
  if not (b and mon) then return nil end
  if mon == b.player then return "player" end
  if mon == b.player2 then return "player2" end
  if mon == b.enemy then return "enemy" end
  if mon == b.enemy2 then return "enemy2" end
end

function Game3:leechSeedSower(mon)
  if not mon then return nil end
  local slot = mon.leechSeedSlot
  if slot and self.battle then return self.battle[slot] end
  return mon.leechSeedFrom
end

-- pokeruby BattleScript_EffectLeechSeed / atk7F_setseeded.
function Game3:useLeechSeed(attacker, defender, texts)
  texts = texts or {}
  if not defender then return texts end
  if defender.leechSeed then
    texts[#texts + 1] = ("%s evaded the attack!"):format(defender.name)
    return texts
  end
  if Game3.hasType(defender, Game3.TYPE_GRASS) then
    texts[#texts + 1] = ("It doesn't affect %s..."):format(defender.name)
    return texts
  end
  defender.leechSeed = true
  defender.leechSeedFrom = attacker
  defender.leechSeedSlot = self:battlerSlot(attacker)
  texts[#texts + 1] = ("%s was seeded!"):format(defender.name)
  return texts
end

-- pokeruby BattleScript_EffectNaturePower / atkCC_callenvironmentattack.
function Game3:useNaturePower(attacker, defender, texts)
  texts = texts or {}
  local env = self:battleEnvironment()
  local id = Game3.NATURE_POWER_MOVES[env] or Game3.MOVE_SWIFT
  local called = self:copyMove(id)
  texts[#texts + 1] = ("NATURE POWER turned into %s!"):format(
    called.name or "MOVE")
  local more = self:useMove(attacker, defender, called, true)
  for i = 1, #more do
    texts[#texts + 1] = more[i]
  end
  return texts
end

-- pokeruby BattleScript_EffectForesight / atkB1_setforesight.
function Game3:useForesight(attacker, defender, texts)
  texts = texts or {}
  if not defender then return texts end
  defender.foresight = true
  texts[#texts + 1] = ("%s identified %s!"):format(
    attacker.name, defender.name)
  return texts
end

-- ENDTURN_LEECH_SEED: maxHP/8, min 1. Liquid Ooze hurts the sower.
function Game3:leechSeedResidual(mon)
  if not mon or not mon.leechSeed or (mon.hp or 0) <= 0 then return {} end
  local sower = self:leechSeedSower(mon)
  if not Game3.aliveMon(sower) then return {} end
  local dmg = math.max(1, math.floor((mon.maxHp or 1) / 8))
  mon.hp = math.max(0, (mon.hp or 0) - dmg)
  local texts = {}
  if self:hasAbility(mon, Game3.ABILITY_LIQUID_OOZE) then
    sower.hp = math.max(0, (sower.hp or 0) - dmg)
    texts[1] = "It sucked up the LIQUID OOZE!"
  else
    local maxHp = sower.maxHp or (sower.hp or 0)
    sower.hp = math.min(maxHp, (sower.hp or 0) + dmg)
    texts[1] = ("%s's health is sapped by LEECH SEED!"):format(mon.name)
  end
  if (mon.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(mon.name)
  end
  if (sower.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(sower.name)
  end
  return texts
end

function Game3:holdEffectOf(mon)
  local id = mon and tonumber(mon.item) or 0
  if id < 1 then return 0, 0 end
  local row = self:itemRow(id)
  local effect = row and tonumber(row.holdEffect)
  local param = row and tonumber(row.holdEffectParam)
  if not effect or effect == 0 then
    effect = Game3.TYPE_POWER_ITEM[id]
    if effect then param = 10 end
  end
  if (not effect or effect == 0) and id == Game3.ITEM_SOOTHE_BELL then
    effect = Game3.HOLD_EFFECT_HAPPINESS_UP
  end
  if (not effect or effect == 0) and id == Game3.ITEM_QUICK_CLAW then
    effect = Game3.HOLD_EFFECT_QUICK_CLAW
    param = Game3.QUICK_CLAW_PARAM
  end
  if (not effect or effect == 0) and id == Game3.ITEM_EXP_SHARE then
    effect = Game3.HOLD_EFFECT_EXP_SHARE
  end
  if (not effect or effect == 0) and id == Game3.ITEM_MACHO_BRACE then
    effect = Game3.HOLD_EFFECT_MACHO_BRACE
  end
  if (not effect or effect == 0) and id == Game3.ITEM_SMOKE_BALL then
    effect = Game3.HOLD_EFFECT_CAN_ALWAYS_RUN
  end
  return effect or 0, param or 0
end

-- pokeruby CalculateBaseDamage: matching gHoldEffectToType boosts
-- attack or Sp. Atk by (param + 100) / 100.
function Game3:applyTypePower(mon, moveType, stat)
  local effect, param = self:holdEffectOf(mon)
  if Game3.HOLD_EFFECT_TYPE[effect] ~= moveType then return stat end
  return math.max(1, math.floor(stat * (100 + (param or 10)) / 100))
end

-- pokeruby BADGE_BOOST: 10% on the player's stat in trainer battles.
function Game3:applyBadgeBoost(mon, badge, stat)
  if not (self.battle and self.battle.isTrainer) then return stat end
  if not self:isPlayerBattler(mon) then return stat end
  if not self:hasBadge(badge) then return stat end
  return math.max(1, math.floor(stat * 110 / 100))
end

function Game3:dealDamage(attacker, defender, move)
  local chart = self.data.moves and self.data.moves.typeChart
  local moveType = self:attackType(attacker, move)
  if self:hasAbility(defender, Game3.ABILITY_LEVITATE)
      and moveType == Game3.TYPE_GROUND then
    return { dmg = 0, mul = 0 }
  end
  local mul = Game3.typeMul(chart, moveType, defender.type1, defender.type2,
    defender.foresight)
  if self:hasAbility(defender, Game3.ABILITY_WONDER_GUARD)
      and mul > 0 and mul <= 10 then
    mul = 0
  end
  if mul <= 0 then return { dmg = 0, mul = 0 } end
  -- Seismic Toss / Night Shade: dmgtolevel, then clear SE/NVE for display.
  if (move.effect or 0) == Game3.EFFECT_LEVEL_DAMAGE then
    local dmg = math.max(1, attacker.level or 1)
    local endured = false
    if defender.endured and dmg >= (defender.hp or 0) then
      dmg = math.max(0, (defender.hp or 1) - 1)
      endured = true
    end
    defender.hp = math.max(0, (defender.hp or 0) - dmg)
    self:noteBideHit(defender, attacker, dmg)
    self:maybeFaintFriendship(defender, attacker)
    return { dmg = dmg, mul = 10, crit = false, endured = endured }
  end
  local physical = Game3.isPhysical(moveType)
  local attack = staged(attacker, physical and "atk" or "spa")
  if physical then
    if self:hasAbility(attacker, Game3.ABILITY_GUTS) and attacker.status then
      attack = math.max(1, math.floor(attack * 3 / 2))
    elseif attacker.status == Game3.STATUS_BRN then
      attack = math.max(1, math.floor(attack / 2))
    end
    if self:hasAbility(attacker, Game3.ABILITY_HUGE_POWER)
        or self:hasAbility(attacker, Game3.ABILITY_PURE_POWER) then
      attack = attack * 2
    end
  end
  attack = self:applyTypePower(attacker, moveType, attack)
  attack = self:applyBadgeBoost(attacker, physical and 1 or 7, attack)
  local defense = staged(defender, physical and "def" or "spd")
  if physical and self:hasAbility(defender, Game3.ABILITY_MARVEL_SCALE)
      and defender.status then
    defense = math.max(1, math.floor(defense * 3 / 2))
  end
  defense = self:applyBadgeBoost(defender, physical and 5 or 7, defense)
  local power = self:boostedPower(attacker, move, defender)
  local dmg = Game3.damage(
    attacker.level, power, attack, defense,
    hasStab(attacker, moveType), mul)
  local roll = 85 + self:rand(16) - 1
  dmg = math.max(1, math.floor(dmg * roll / 100))
  local wmul = self:weatherPowerTenths(moveType)
  if wmul ~= 10 then
    dmg = math.max(1, math.floor(dmg * wmul / 10))
  end
  if defender.invuln == "dig"
      and (move.effect == Game3.EFFECT_EARTHQUAKE
        or move.effect == Game3.EFFECT_MAGNITUDE) then
    dmg = dmg * 2
  elseif defender.invuln == "fly"
      and (move.effect == Game3.EFFECT_GUST
        or move.effect == Game3.EFFECT_TWISTER) then
    dmg = dmg * 2
  end
  if self:hasAbility(defender, Game3.ABILITY_THICK_FAT)
      and (moveType == Game3.TYPE_FIRE or moveType == Game3.TYPE_ICE) then
    dmg = math.max(1, math.floor(dmg / 2))
  end
  local crit = false
  local b = self.battle
  if not (b and (b.wallyTutorial or b.chase)) then
    local denom = Game3.critDenom(move.effect, attacker.focusEnergy)
    crit = self:rand(denom) == denom
  end
  if crit then dmg = dmg * 2 end
  if move.spreadHits then
    dmg = math.max(1, math.floor(dmg / 2))
  end
  local endured = false
  if defender.endured and dmg >= (defender.hp or 0) then
    dmg = math.max(0, (defender.hp or 1) - 1)
    endured = true
  end
  defender.hp = math.max(0, (defender.hp or 0) - dmg)
  self:noteBideHit(defender, attacker, dmg)
  self:maybeFaintFriendship(defender, attacker)
  return { dmg = dmg, mul = mul, crit = crit, endured = endured }
end

function Game3:dealTackle(attacker, defender)
  return self:dealDamage(attacker, defender, {
    power = Game3.TACKLE_POWER, type = Game3.TACKLE_TYPE,
  }).dmg
end

function Game3:blocksStatDrop(mon, stat)
  if self:hasAbility(mon, Game3.ABILITY_CLEAR_BODY)
      or self:hasAbility(mon, Game3.ABILITY_WHITE_SMOKE) then
    return true
  end
  if stat == "atk" and self:hasAbility(mon, Game3.ABILITY_HYPER_CUTTER) then
    return true
  end
  if stat == "acc" and self:hasAbility(mon, Game3.ABILITY_KEEN_EYE) then
    return true
  end
  return false
end

function Game3:dropStat(mon, stat, label, amount)
  amount = amount or 1
  local st = mon.stages
  if type(st) ~= "table" then
    st = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
    mon.stages = st
  end
  if self:blocksStatDrop(mon, stat) then
    return ("%s's %s cannot be lowered!"):format(
      mon.name, Game3.abilityName(mon.ability))
  end
  local cur = st[stat] or 0
  if cur <= -6 then
    return ("%s's %s won't go lower!"):format(mon.name, label)
  end
  st[stat] = math.max(-6, cur - amount)
  if amount >= 2 then
    return ("%s's %s harshly fell!"):format(mon.name, label)
  end
  return ("%s's %s fell!"):format(mon.name, label)
end

function Game3:raiseStat(mon, stat, amount, label)
  amount = amount or 1
  local st = mon.stages
  if type(st) ~= "table" then
    st = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
    mon.stages = st
  end
  local cur = st[stat] or 0
  if cur >= 6 then
    return ("%s's %s won't go any higher!"):format(mon.name, label)
  end
  st[stat] = math.min(6, cur + amount)
  if amount >= 2 then
    return ("%s's %s rose sharply!"):format(mon.name, label)
  end
  return ("%s's %s rose!"):format(mon.name, label)
end

function Game3.statUpSpec(effect)
  if effect == Game3.EFFECT_ATTACK_UP then return { { "atk", 1, "ATTACK" } } end
  if effect == Game3.EFFECT_DEFENSE_UP or effect == Game3.EFFECT_DEFENSE_CURL then
    return { { "def", 1, "DEFENSE" } }
  end
  if effect == Game3.EFFECT_SPEED_UP then return { { "spe", 1, "SPEED" } } end
  if effect == Game3.EFFECT_SPATK_UP then return { { "spa", 1, "SP. ATK" } } end
  if effect == Game3.EFFECT_SPDEF_UP then return { { "spd", 1, "SP. DEF" } } end
  if effect == Game3.EFFECT_EVASION_UP then return { { "eva", 1, "EVASION" } } end
  if effect == Game3.EFFECT_ATTACK_UP_2 then return { { "atk", 2, "ATTACK" } } end
  if effect == Game3.EFFECT_DEFENSE_UP_2 then return { { "def", 2, "DEFENSE" } } end
  if effect == Game3.EFFECT_SPEED_UP_2 then return { { "spe", 2, "SPEED" } } end
  if effect == Game3.EFFECT_SPATK_UP_2 then return { { "spa", 2, "SP. ATK" } } end
  if effect == Game3.EFFECT_SPDEF_UP_2 then return { { "spd", 2, "SP. DEF" } } end
  if effect == Game3.EFFECT_COSMIC_POWER then
    return { { "def", 1, "DEFENSE" }, { "spd", 1, "SP. DEF" } }
  end
  if effect == Game3.EFFECT_BULK_UP then
    return { { "atk", 1, "ATTACK" }, { "def", 1, "DEFENSE" } }
  end
  if effect == Game3.EFFECT_CALM_MIND then
    return { { "spa", 1, "SP. ATK" }, { "spd", 1, "SP. DEF" } }
  end
  if effect == Game3.EFFECT_DRAGON_DANCE then
    return { { "atk", 1, "ATTACK" }, { "spe", 1, "SPEED" } }
  end
end

-- Roxanne's Rock Tomb (70) and Crunch / Shadow Ball (72).
function Game3.statDownHitSpec(effect)
  if effect == Game3.EFFECT_ATTACK_DOWN_HIT then return "atk", "ATTACK" end
  if effect == Game3.EFFECT_DEFENSE_DOWN_HIT then return "def", "DEFENSE" end
  if effect == Game3.EFFECT_SPEED_DOWN_HIT then return "spe", "SPEED" end
  if effect == Game3.EFFECT_SPECIAL_ATTACK_DOWN_HIT then return "spa", "SP. ATK" end
  if effect == Game3.EFFECT_SPECIAL_DEFENSE_DOWN_HIT then return "spd", "SP. DEF" end
  if effect == Game3.EFFECT_ACCURACY_DOWN_HIT then return "acc", "ACCURACY" end
end

-- pokeruby BattleScript_EffectStatDown / setstatchanger. Fake Tears is
-- SPECIAL_DEFENSE_DOWN_2; Charm / Screech / Cotton Spore / Metal Sound
-- share the same script with a different stat.
function Game3.statDownSpec(effect)
  if effect == Game3.EFFECT_ATTACK_DOWN then return "atk", "ATTACK", 1 end
  if effect == Game3.EFFECT_DEFENSE_DOWN then return "def", "DEFENSE", 1 end
  if effect == Game3.EFFECT_SPEED_DOWN then return "spe", "SPEED", 1 end
  if effect == Game3.EFFECT_ACCURACY_DOWN then return "acc", "ACCURACY", 1 end
  if effect == Game3.EFFECT_EVASION_DOWN then return "eva", "EVASION", 1 end
  if effect == Game3.EFFECT_ATTACK_DOWN_2 then return "atk", "ATTACK", 2 end
  if effect == Game3.EFFECT_DEFENSE_DOWN_2 then return "def", "DEFENSE", 2 end
  if effect == Game3.EFFECT_SPEED_DOWN_2 then return "spe", "SPEED", 2 end
  if effect == Game3.EFFECT_SPECIAL_ATTACK_DOWN_2 then return "spa", "SP. ATK", 2 end
  if effect == Game3.EFFECT_SPECIAL_DEFENSE_DOWN_2 then return "spd", "SP. DEF", 2 end
  if effect == Game3.EFFECT_ACCURACY_DOWN_2 then return "acc", "ACCURACY", 2 end
  if effect == Game3.EFFECT_EVASION_DOWN_2 then return "eva", "EVASION", 2 end
end

function Game3:useStatDownMove(defender, move, effect, texts)
  texts = texts or {}
  local stat, label, amount = Game3.statDownSpec(effect)
  if not stat then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  local chart = self.data.moves and self.data.moves.typeChart
  local mul = Game3.typeMul(chart, move.type, defender.type1, defender.type2,
    defender.foresight)
  if self:hasAbility(defender, Game3.ABILITY_LEVITATE)
      and move.type == Game3.TYPE_GROUND then
    mul = 0
  end
  if mul <= 0 then
    texts[#texts + 1] = ("It doesn't affect %s..."):format(defender.name)
    return texts
  end
  texts[#texts + 1] = self:dropStat(defender, stat, label, amount)
  return texts
end

-- Steven's TM47 Steel Wing (138) and Metal Claw (139).
function Game3.statUpHitSpec(effect)
  if effect == Game3.EFFECT_ATTACK_UP_HIT then return "atk", "ATTACK" end
  if effect == Game3.EFFECT_DEFENSE_UP_HIT then return "def", "DEFENSE" end
end

-- nil means the move cannot miss (Swift, Thunder in rain).
function Game3:moveHitChance(attacker, defender, move, effect)
  effect = effect or (move and move.effect) or 0
  if effect == Game3.EFFECT_ALWAYS_HIT or effect == Game3.EFFECT_VITAL_THROW then
    return nil
  end
  local acc = tonumber(move and move.accuracy)
  if acc == nil then acc = 100 end
  if acc < 1 then return nil end
  if not self:weatherSuppressed() and self.battle then
    local w = self.battle.weather
    if w == Game3.WEATHER_RAIN
        and (effect == Game3.EFFECT_THUNDER
          or self:attackType(attacker, move) == Game3.TYPE_ELECTRIC) then
      return nil
    end
    if w == Game3.WEATHER_SUN and effect == Game3.EFFECT_THUNDER then
      acc = 50
    end
  end
  local atkAcc = attacker and attacker.stages and attacker.stages.acc or 0
  local defEva = defender and defender.stages and defender.stages.eva or 0
  if defender and defender.foresight then defEva = 0 end
  acc = Game3.accuracyFromStages(acc, atkAcc, defEva)
  if self:hasAbility(attacker, Game3.ABILITY_COMPOUND_EYES) then
    acc = math.floor(acc * 130 / 100)
  end
  if effect ~= Game3.EFFECT_OHKO
      and not self:weatherSuppressed()
      and self.battle and self.battle.weather == Game3.WEATHER_SAND
      and self:hasAbility(defender, Game3.ABILITY_SAND_VEIL) then
    acc = math.max(1, math.floor(acc * 80 / 100))
  end
  return acc
end

function Game3.protectSucceeds(streak, roll)
  local rates = { 65535, 32767, 16383, 8191 }
  local i = (streak or 0) + 1
  if i > #rates then i = #rates end
  return (roll or 0) <= rates[i]
end

function Game3.ohkoChance(atkLevel, defLevel)
  atkLevel = atkLevel or 1
  defLevel = defLevel or 1
  if defLevel > atkLevel then return 0 end
  local n = atkLevel - defLevel + 30
  if n > 100 then n = 100 end
  return n
end

function Game3.chargeKind(move)
  local effect = move and move.effect or 0
  if effect == Game3.EFFECT_SOLARBEAM then return "solarbeam" end
  if effect == Game3.EFFECT_RAZOR_WIND then return "razorwind" end
  if effect == Game3.EFFECT_SKY_ATTACK then return "skyattack" end
  if effect == Game3.EFFECT_SKULL_BASH then return "skullbash" end
  if effect ~= Game3.EFFECT_FLY then return nil end
  local t = move.type or 0
  if t == Game3.TYPE_GROUND then return "dig" end
  if t == Game3.TYPE_WATER then return "dive" end
  return "fly"
end

function Game3.chargeText(mon, kind)
  local name = mon and mon.name or "POKeMON"
  if kind == "solarbeam" then return ("%s took in sunlight!"):format(name) end
  if kind == "fly" then return ("%s flew up high!"):format(name) end
  if kind == "dig" then return ("%s dug a hole!"):format(name) end
  if kind == "dive" then return ("%s hid underwater!"):format(name) end
  if kind == "razorwind" then return ("%s whipped up a whirlwind!"):format(name) end
  if kind == "skyattack" then return ("%s is glowing!"):format(name) end
  if kind == "skullbash" then return ("%s tucked in its head!"):format(name) end
  return ("%s is charging up!"):format(name)
end

function Game3:hitsInvuln(move, kind)
  if not kind then return true end
  local effect = move and move.effect or 0
  if kind == "fly" then
    return effect == Game3.EFFECT_THUNDER or effect == Game3.EFFECT_GUST
      or effect == Game3.EFFECT_TWISTER or effect == Game3.EFFECT_SKY_UPPERCUT
  end
  if kind == "dig" then
    return effect == Game3.EFFECT_EARTHQUAKE or effect == Game3.EFFECT_MAGNITUDE
      or effect == Game3.EFFECT_OHKO
  end
  if kind == "dive" then
    local name = move and move.name or ""
    return name:find("SURF", 1, true) ~= nil
      or name:find("WHIRLPOOL", 1, true) ~= nil
  end
  return false
end

function Game3:skipsCharge(move)
  if not move or move.effect ~= Game3.EFFECT_SOLARBEAM then return false end
  return not self:weatherSuppressed()
    and self.battle and self.battle.weather == Game3.WEATHER_SUN
end

function Game3:useFocusEnergy(mon, texts)
  texts = texts or {}
  if mon.focusEnergy then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  mon.focusEnergy = true
  texts[#texts + 1] = ("%s is getting pumped!"):format(mon.name)
  return texts
end

-- pokeruby BattleScript_EffectRage / MOVE_EFFECT_RAGE / atk49 ATK49_RAGE.
-- Accuracy check first: miss and Protect run clearstatusfromeffect USER.
-- A pass sets STATUS2_RAGE on the user even if type immunity zeroes damage.
function Game3:clearRageIfOtherMove(attacker, effect)
  if attacker and effect ~= Game3.EFFECT_RAGE then
    attacker.rage = nil
  end
end

function Game3:armRage(attacker, effect, hit)
  if not attacker or effect ~= Game3.EFFECT_RAGE then return end
  attacker.rage = hit and true or nil
end

function Game3:tickRage(defender, dmg, texts)
  if not defender or not defender.rage or not texts then return end
  if (dmg or 0) < 1 or (defender.hp or 0) < 1 then return end
  local st = defender.stages
  if type(st) ~= "table" then
    st = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
    defender.stages = st
  end
  if (st.atk or 0) >= 6 then return end
  st.atk = (st.atk or 0) + 1
  texts[#texts + 1] = ("%s's RAGE is building!"):format(defender.name)
end

-- pokeruby BattleScript_EffectMudSport / atkE8_settypebasedhalvers.
-- No accuracy check. Already-set on this battler is BattleScript_ButItFailed.
function Game3:useSport(attacker, effect, texts)
  texts = texts or {}
  local key, line
  if effect == Game3.EFFECT_MUD_SPORT then
    key, line = "mudSport", "Electricity's power was weakened!"
  else
    key, line = "waterSport", "Fire's power was weakened!"
  end
  if attacker[key] then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  attacker[key] = true
  texts[#texts + 1] = line
  return texts
end

function Game3:useProtect(attacker, texts, endure)
  texts = texts or {}
  local streak = attacker.protectStreak or 0
  local roll = self:rand(65536) - 1
  if not Game3.protectSucceeds(streak, roll) then
    attacker.protectStreak = 0
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  attacker.protectStreak = streak + 1
  if endure then
    attacker.endured = true
    texts[#texts + 1] = ("%s braced itself!"):format(attacker.name)
  else
    attacker.protected = true
    texts[#texts + 1] = ("%s protected itself!"):format(attacker.name)
  end
  return texts
end

-- pokeruby CanRunFromBattle. 0 = can run, 1 = fail, 2 = ability.
function Game3:canRunFromBattle(mon)
  if not mon then return 1 end
  local hold = self:holdEffectOf(mon)
  if hold == Game3.HOLD_EFFECT_CAN_ALWAYS_RUN then return 0 end
  if self:hasAbility(mon, Game3.ABILITY_RUN_AWAY) then return 0 end
  local foes = self:foesOf(mon)
  for i = 1, #foes do
    local foe = foes[i]
    if Game3.aliveMon(foe) then
      if self:hasAbility(foe, Game3.ABILITY_SHADOW_TAG) then
        return 2, foe, Game3.ABILITY_SHADOW_TAG
      end
      if self:hasAbility(foe, Game3.ABILITY_ARENA_TRAP)
          and not self:hasAbility(mon, Game3.ABILITY_LEVITATE)
          and not Game3.hasType(mon, Game3.TYPE_FLYING) then
        return 2, foe, Game3.ABILITY_ARENA_TRAP
      end
      if self:hasAbility(foe, Game3.ABILITY_MAGNET_PULL)
          and Game3.hasType(mon, Game3.TYPE_STEEL) then
        return 2, foe, Game3.ABILITY_MAGNET_PULL
      end
    end
  end
  if mon.cannotEscape or mon.wrapped or mon.rooted then return 1 end
  local b = self.battle
  if b and (b.chase or b.wallyTutorial) then return 1 end
  return 0
end

-- Battle Teleport. Field HM-style TELEPORT is useTeleport.
function Game3:useBattleTeleport(attacker, texts)
  texts = texts or {}
  local b = self.battle
  if not b or b.isTrainer then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  local code, foe, ability = self:canRunFromBattle(attacker)
  if code == 2 then
    texts[#texts + 1] = ("%s's %s made it ineffective!"):format(
      foe.name, Game3.abilityName(ability))
    return texts
  end
  if code ~= 0 then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  texts[#texts + 1] = ("%s fled from battle!"):format(attacker.name)
  b.fled = true
  return texts
end

function Game3:noteBideHit(defender, attacker, dmg)
  if defender and defender.bideTurns and (dmg or 0) > 0 then
    defender.bideTaken = (defender.bideTaken or 0) + dmg
    defender.bideFrom = attacker
  end
end

function Game3:cancelMultiTurn(mon)
  if not mon then return end
  mon.charging = nil
  mon.invuln = nil
  mon.bideTurns = nil
  mon.bideTaken = nil
  mon.bideFrom = nil
end

-- pokeruby setbide / BattleScript_Bide*: two stored turns, then 2x HP.
function Game3:useBide(attacker, defender, move, texts)
  texts = texts or {}
  if not attacker.bideTurns then
    attacker.bideTurns = 2
    attacker.bideTaken = 0
    attacker.bideFrom = nil
    attacker.charging = { move = move, kind = "bide" }
    texts[#texts + 1] = ("%s is storing energy!"):format(attacker.name)
    return texts
  end
  attacker.bideTurns = attacker.bideTurns - 1
  if attacker.bideTurns > 0 then
    texts[#texts + 1] = ("%s is storing energy!"):format(attacker.name)
    return texts
  end
  attacker.charging = nil
  local stored = attacker.bideTaken or 0
  local from = attacker.bideFrom
  attacker.bideTurns = nil
  attacker.bideTaken = nil
  attacker.bideFrom = nil
  texts[#texts + 1] = ("%s unleashed energy!"):format(attacker.name)
  if stored <= 0 then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  local target = from
  if not Game3.aliveMon(target) or target == attacker then
    target = self:defaultTarget(attacker)
  end
  if not Game3.aliveMon(target) then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  if target.protected then
    texts[#texts + 1] = ("%s protected itself!"):format(target.name)
    return texts
  end
  if target.invuln and not self:hitsInvuln(move, target.invuln) then
    texts[#texts + 1] = "The attack missed!"
    return texts
  end
  local chance = self:moveHitChance(attacker, target, move, Game3.EFFECT_BIDE)
  if chance and chance < 100
      and (chance < 1 or self:rand(100) > chance) then
    texts[#texts + 1] = "The attack missed!"
    return texts
  end
  local chart = self.data.moves and self.data.moves.typeChart
  local mul = Game3.typeMul(chart, move.type or 0, target.type1, target.type2,
    target.foresight)
  if self:hasAbility(target, Game3.ABILITY_WONDER_GUARD)
      and mul > 0 and mul <= 10 then
    mul = 0
  end
  if mul <= 0 then
    texts[#texts + 1] = ("It doesn't affect %s..."):format(target.name)
    return texts
  end
  local dmg = stored * 2
  local endured = false
  if target.endured and dmg >= (target.hp or 0) then
    dmg = math.max(0, (target.hp or 1) - 1)
    endured = true
  end
  target.hp = math.max(0, (target.hp or 0) - dmg)
  if endured then
    texts[#texts + 1] = ("%s endured the hit!"):format(target.name)
  end
  if Game3.isContact(move) then
    self:onContact(attacker, target, texts)
  end
  if (target.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(target.name)
  end
  if (attacker.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(attacker.name)
  end
  return texts
end

function Game3:useOhko(attacker, defender, move, texts)
  local chart = self.data.moves and self.data.moves.typeChart
  local mul = Game3.typeMul(chart, move.type, defender.type1, defender.type2,
    defender.foresight)
  if self:hasAbility(defender, Game3.ABILITY_LEVITATE)
      and move.type == Game3.TYPE_GROUND then
    mul = 0
  end
  if self:hasAbility(defender, Game3.ABILITY_WONDER_GUARD)
      and mul > 0 and mul <= 10 then
    mul = 0
  end
  if mul <= 0 then
    texts[#texts + 1] = ("It doesn't affect %s..."):format(defender.name)
    return texts
  end
  local chance = Game3.ohkoChance(attacker.level, defender.level)
  if chance < 1 then
    texts[#texts + 1] = "But it failed!"
    return texts
  end
  if self:rand(100) > chance then
    texts[#texts + 1] = "The attack missed!"
    return texts
  end
  defender.hp = 0
  self:maybeFaintFriendship(defender, attacker)
  texts[#texts + 1] = "It's a one-hit KO!"
  texts[#texts + 1] = ("%s fainted!"):format(defender.name)
  return texts
end

function Game3:weatherSuppressed()
  local b = self.battle
  if not b then return true end
  local mons = { b.player, b.player2, b.enemy, b.enemy2 }
  for i = 1, 4 do
    if self:hasAbility(mons[i], Game3.ABILITY_CLOUD_NINE)
        or self:hasAbility(mons[i], Game3.ABILITY_AIR_LOCK) then
      return true
    end
  end
  return false
end

-- pokeruby AbilityBattleEffects(ABILITYEFFECT_FIELD_SPORT): any battler
-- with STATUS3_MUDSPORT / WATERSPORT. SwitchInClearSetData zeroes them
-- unless Baton Pass kept the bits.
function Game3:fieldHasSport(key)
  local b = self.battle
  if not b or not key then return false end
  local mons = { b.player, b.player2, b.enemy, b.enemy2 }
  for i = 1, 4 do
    if mons[i] and mons[i][key] then return true end
  end
  return false
end

function Game3.weatherStartText(kind)
  if kind == Game3.WEATHER_RAIN then return "It started to rain!" end
  if kind == Game3.WEATHER_SUN then return "The sunlight turned harsh!" end
  if kind == Game3.WEATHER_SAND then return "A sandstorm brewed!" end
  if kind == Game3.WEATHER_HAIL then return "It started to hail!" end
  return "The weather changed!"
end

function Game3.weatherEndText(kind)
  if kind == Game3.WEATHER_RAIN then return "The rain stopped." end
  if kind == Game3.WEATHER_SUN then return "The sunlight faded." end
  if kind == Game3.WEATHER_SAND then return "The sandstorm subsided." end
  if kind == Game3.WEATHER_HAIL then return "The hail stopped." end
  return "The weather cleared."
end

function Game3:setWeather(kind, turns)
  local b = self.battle
  if not b or not kind then return false, "But it failed!" end
  if b.weather == kind then return false, "But it failed!" end
  b.weather = kind
  b.weatherTurns = turns
  return true, Game3.weatherStartText(kind)
end

function Game3:weatherKindForEffect(effect)
  if effect == Game3.EFFECT_RAIN_DANCE then return Game3.WEATHER_RAIN end
  if effect == Game3.EFFECT_SUNNY_DAY then return Game3.WEATHER_SUN end
  if effect == Game3.EFFECT_SANDSTORM then return Game3.WEATHER_SAND end
  if effect == Game3.EFFECT_HAIL then return Game3.WEATHER_HAIL end
end

function Game3:weatherPowerTenths(moveType)
  if self:weatherSuppressed() then return 10 end
  local w = self.battle and self.battle.weather
  if w == Game3.WEATHER_SUN then
    if moveType == Game3.TYPE_FIRE then return 15 end
    if moveType == Game3.TYPE_WATER then return 5 end
  elseif w == Game3.WEATHER_RAIN then
    if moveType == Game3.TYPE_WATER then return 15 end
    if moveType == Game3.TYPE_FIRE then return 5 end
  end
  return 10
end

function Game3:sandImmune(mon)
  return Game3.hasType(mon, Game3.TYPE_ROCK)
    or Game3.hasType(mon, Game3.TYPE_STEEL)
    or Game3.hasType(mon, Game3.TYPE_GROUND)
    or self:hasAbility(mon, Game3.ABILITY_SAND_VEIL)
end

function Game3:weatherResidual(mon)
  if not mon or (mon.hp or 0) <= 0 then return {} end
  if self:weatherSuppressed() then return {} end
  local w = self.battle and self.battle.weather
  local texts = {}
  if w == Game3.WEATHER_RAIN and self:hasAbility(mon, Game3.ABILITY_RAIN_DISH) then
    local maxHp = mon.maxHp or 1
    if (mon.hp or 0) < maxHp then
      local heal = math.max(1, math.floor(maxHp / 16))
      mon.hp = math.min(maxHp, (mon.hp or 0) + heal)
      texts[#texts + 1] = ("%s restored HP using its %s!"):format(
        mon.name, Game3.abilityName(Game3.ABILITY_RAIN_DISH))
    end
    return texts
  end
  if w == Game3.WEATHER_SAND then
    if self:sandImmune(mon) then return {} end
    local dmg = math.max(1, math.floor((mon.maxHp or 1) / 16))
    mon.hp = math.max(0, (mon.hp or 0) - dmg)
    texts[1] = ("%s is buffeted by the sandstorm!"):format(mon.name)
  elseif w == Game3.WEATHER_HAIL then
    if Game3.hasType(mon, Game3.TYPE_ICE) then return {} end
    local dmg = math.max(1, math.floor((mon.maxHp or 1) / 16))
    mon.hp = math.max(0, (mon.hp or 0) - dmg)
    texts[1] = ("%s is pelted by the hail!"):format(mon.name)
  else
    return {}
  end
  if (mon.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(mon.name)
  end
  return texts
end

function Game3:tickWeather()
  local b = self.battle
  if not b or not b.weather then return {} end
  local texts = {}
  local function add(mon)
    local lines = self:weatherResidual(mon)
    for i = 1, #lines do texts[#texts + 1] = lines[i] end
  end
  add(b.player)
  add(b.enemy)
  if type(b.weatherTurns) == "number" then
    b.weatherTurns = b.weatherTurns - 1
    if b.weatherTurns <= 0 then
      texts[#texts + 1] = Game3.weatherEndText(b.weather)
      b.weather = nil
      b.weatherTurns = nil
    end
  end
  return texts
end

function Game3:tryWeatherAbility(mon)
  if not mon then return nil end
  local kind, name
  if self:hasAbility(mon, Game3.ABILITY_DRIZZLE) then
    kind, name = Game3.WEATHER_RAIN, Game3.ABILITY_DRIZZLE
  elseif self:hasAbility(mon, Game3.ABILITY_DROUGHT) then
    kind, name = Game3.WEATHER_SUN, Game3.ABILITY_DROUGHT
  elseif self:hasAbility(mon, Game3.ABILITY_SAND_STREAM) then
    kind, name = Game3.WEATHER_SAND, Game3.ABILITY_SAND_STREAM
  else
    return nil
  end
  local b = self.battle
  if not b then return nil end
  if b.weather == kind and not b.weatherTurns then return nil end
  b.weather = kind
  b.weatherTurns = nil
  if kind == Game3.WEATHER_RAIN then
    return ("%s's %s made it rain!"):format(mon.name, Game3.abilityName(name))
  end
  if kind == Game3.WEATHER_SUN then
    return ("%s's %s intensified the sun's rays!"):format(
      mon.name, Game3.abilityName(name))
  end
  return ("%s's %s whipped up a sandstorm!"):format(
    mon.name, Game3.abilityName(name))
end

function Game3:activateEnter(mon, foe)
  local texts = {}
  if not mon or not foe then return texts end
  mon.truant = nil
  if self:hasAbility(mon, Game3.ABILITY_TRACE) and (foe.ability or 0) > 0
      and foe.ability ~= Game3.ABILITY_TRACE then
    mon.ability = foe.ability
    texts[#texts + 1] = ("%s's TRACE copied %s's %s!"):format(
      mon.name, foe.name, Game3.abilityName(mon.ability))
  end
  if self:hasAbility(mon, Game3.ABILITY_INTIMIDATE) then
    texts[#texts + 1] = self:dropStat(foe, "atk", "ATTACK")
    if not self:blocksStatDrop(foe, "atk") then
      texts[#texts] = ("%s's INTIMIDATE cuts %s's ATTACK!"):format(
        mon.name, foe.name)
    end
  end
  local weather = self:tryWeatherAbility(mon)
  if weather then texts[#texts + 1] = weather end
  return texts
end

function Game3:trySynchronize(from, to, status)
  if not self:hasAbility(from, Game3.ABILITY_SYNCHRONIZE) then return nil end
  if status ~= Game3.STATUS_PSN and status ~= Game3.STATUS_BRN
      and status ~= Game3.STATUS_PAR then
    return nil
  end
  return self:applyStatus(to, status)
end

function Game3:typeAbsorb(defender, move, attacker)
  local t = self:attackType(attacker, move)
  if t == Game3.TYPE_ELECTRIC then
    if self:hasAbility(defender, Game3.ABILITY_VOLT_ABSORB) then
      local heal = math.max(1, math.floor((defender.maxHp or 1) / 4))
      defender.hp = math.min(defender.maxHp or heal, (defender.hp or 0) + heal)
      return ("%s restored HP using its %s!"):format(
        defender.name, Game3.abilityName(Game3.ABILITY_VOLT_ABSORB))
    end
    if self:hasAbility(defender, Game3.ABILITY_LIGHTNING_ROD) then
      local st = defender.stages
      if type(st) ~= "table" then
        st = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
        defender.stages = st
      end
      st.spa = math.min(6, (st.spa or 0) + 1)
      return ("%s's %s raised SP. ATK!"):format(
        defender.name, Game3.abilityName(Game3.ABILITY_LIGHTNING_ROD))
    end
  end
  if t == Game3.TYPE_WATER
      and self:hasAbility(defender, Game3.ABILITY_WATER_ABSORB) then
    local heal = math.max(1, math.floor((defender.maxHp or 1) / 4))
    defender.hp = math.min(defender.maxHp or heal, (defender.hp or 0) + heal)
    return ("%s restored HP using its %s!"):format(
      defender.name, Game3.abilityName(Game3.ABILITY_WATER_ABSORB))
  end
  if t == Game3.TYPE_FIRE
      and self:hasAbility(defender, Game3.ABILITY_FLASH_FIRE) then
    defender.flashFire = true
    return ("%s's %s raised the power of its FIRE moves!"):format(
      defender.name, Game3.abilityName(Game3.ABILITY_FLASH_FIRE))
  end
end

-- Knock Off (effect 188). Shield Dust does not block it: SetMoveEffect
-- only filters MOVE_EFFECT_BYTE <= 9, and KNOCK_OFF is 0x36.
function Game3:knockOffItem(attacker, defender, move)
  local item = defender.item or 0
  if item == 0 then return nil end
  if self:hasAbility(defender, Game3.ABILITY_STICKY_HOLD) then
    return ("%s's %s made %s ineffective!"):format(
      defender.name, Game3.abilityName(Game3.ABILITY_STICKY_HOLD),
      (move and move.name) or "KNOCK OFF")
  end
  defender.item = 0
  return ("%s knocked off %s's %s!"):format(
    attacker.name, defender.name, self:itemName(item))
end

function Game3:applyHitSecondaries(attacker, defender, move, effect, texts)
  local chance = move.secondary or 0
  if self:hasAbility(attacker, Game3.ABILITY_SERENE_GRACE) then
    chance = math.min(100, chance * 2)
  end
  if chance < 1 then return end
  local dust = self:hasAbility(defender, Game3.ABILITY_SHIELD_DUST)
  if not dust then
    local status = Game3.statusFromEffect(effect)
    if status and self:rand(100) <= chance then
      local line = self:applyStatus(defender, status)
      if line then
        texts[#texts + 1] = line
        local sync = self:trySynchronize(defender, attacker, status)
        if sync then texts[#texts + 1] = sync end
      end
    end
    if Game3.isFlinchEffect(effect) and self:rand(100) <= chance
        and not self:hasAbility(defender, Game3.ABILITY_INNER_FOCUS) then
      defender.flinch = true
    end
    if effect == Game3.EFFECT_CONFUSE_HIT and self:rand(100) <= chance then
      local line = self:applyConfuse(defender)
      if line then texts[#texts + 1] = line end
    end
    local downStat, downLabel = Game3.statDownHitSpec(effect)
    if downStat and self:rand(100) <= chance then
      texts[#texts + 1] = self:dropStat(defender, downStat, downLabel)
    end
  end
  local upStat, upLabel = Game3.statUpHitSpec(effect)
  if upStat and self:rand(100) <= chance then
    texts[#texts + 1] = self:raiseStat(attacker, upStat, 1, upLabel)
  end
  if effect == Game3.EFFECT_KNOCK_OFF and self:rand(100) <= chance then
    local line = self:knockOffItem(attacker, defender, move)
    if line then texts[#texts + 1] = line end
  end
end

function Game3:onContact(attacker, defender, texts)
  if not attacker or not defender or (attacker.hp or 0) <= 0 then return end
  if self:hasAbility(defender, Game3.ABILITY_ROUGH_SKIN) then
    local dmg = math.max(1, math.floor((attacker.maxHp or 1) / 16))
    attacker.hp = math.max(0, (attacker.hp or 0) - dmg)
    texts[#texts + 1] = ("%s was hurt by %s's %s!"):format(
      attacker.name, defender.name, Game3.abilityName(Game3.ABILITY_ROUGH_SKIN))
  end
  local function proc(ability, status)
    if self:hasAbility(defender, ability) and self:rand(100) <= 30 then
      local line = self:applyStatus(attacker, status)
      if line then texts[#texts + 1] = line end
    end
  end
  proc(Game3.ABILITY_STATIC, Game3.STATUS_PAR)
  proc(Game3.ABILITY_FLAME_BODY, Game3.STATUS_BRN)
  proc(Game3.ABILITY_POISON_POINT, Game3.STATUS_PSN)
end

function Game3:useMove(attacker, defender, move, extra)
  local texts = extra and {}
    or { ("%s used %s!"):format(attacker.name, move.name or "TACKLE") }
  local effect = move.effect or 0
  local power = move.power or 0
  local finishing = attacker.charging ~= nil
  if not extra then
    self:clearRageIfOtherMove(attacker, effect)
    if finishing then
      if not (attacker.charging and attacker.charging.kind == "bide") then
        attacker.charging = nil
        attacker.invuln = nil
      end
    else
      move.pp = math.max(0, (move.pp or 1) - 1)
      if effect ~= Game3.EFFECT_PROTECT and effect ~= Game3.EFFECT_ENDURE then
        attacker.protectStreak = 0
      end
    end
    if effect == Game3.EFFECT_SPLASH then
      texts[#texts + 1] = "But nothing happened!"
      return texts
    end
    if effect == Game3.EFFECT_RESTORE_HP then
      return self:useRestoreHp(attacker, texts)
    end
    if effect == Game3.EFFECT_REST then
      return self:useRest(attacker, texts)
    end
    local kind = self:weatherKindForEffect(effect)
    if kind then
      local ok, msg = self:setWeather(kind, Game3.WEATHER_TURNS)
      texts[#texts + 1] = msg
      return texts
    end
    if effect == Game3.EFFECT_MUD_SPORT
        or effect == Game3.EFFECT_WATER_SPORT then
      return self:useSport(attacker, effect, texts)
    end
    if effect == Game3.EFFECT_BIDE then
      return self:useBide(attacker, defender, move, texts)
    end
    if not finishing then
      if effect == Game3.EFFECT_PROTECT then
        return self:useProtect(attacker, texts)
      end
      if effect == Game3.EFFECT_ENDURE then
        return self:useProtect(attacker, texts, true)
      end
      if effect == Game3.EFFECT_FOCUS_ENERGY then
        return self:useFocusEnergy(attacker, texts)
      end
      if effect == Game3.EFFECT_TELEPORT then
        return self:useBattleTeleport(attacker, texts)
      end
      local ups = Game3.statUpSpec(effect)
      if ups then
        for i = 1, #ups do
          local spec = ups[i]
          texts[#texts + 1] = self:raiseStat(attacker, spec[1], spec[2], spec[3])
        end
        return texts
      end
      local charge = Game3.chargeKind(move)
      if charge and not self:skipsCharge(move) then
        attacker.charging = { move = move, kind = charge }
        if charge == "fly" or charge == "dig" or charge == "dive" then
          attacker.invuln = charge
        end
        texts[#texts + 1] = Game3.chargeText(attacker, charge)
        if charge == "skullbash" then
          texts[#texts + 1] = self:raiseStat(attacker, "def", 1, "DEFENSE")
        end
        return texts
      end
    end
  end
  if not defender then return texts end
  if effect == Game3.EFFECT_NATURE_POWER then
    return self:useNaturePower(attacker, defender, texts)
  end
  if defender.protected then
    self:armRage(attacker, effect, false)
    texts[#texts + 1] = ("%s protected itself!"):format(defender.name)
    return texts
  end
  if defender.invuln and not self:hitsInvuln(move, defender.invuln) then
    self:armRage(attacker, effect, false)
    texts[#texts + 1] = "The attack missed!"
    return texts
  end
  if effect ~= Game3.EFFECT_OHKO then
    local chance = self:moveHitChance(attacker, defender, move, effect)
    if chance and chance < 100
        and (chance < 1 or self:rand(100) > chance) then
      self:armRage(attacker, effect, false)
      if effect == Game3.EFFECT_LEECH_SEED then
        texts[#texts + 1] = ("%s evaded the attack!"):format(defender.name)
      else
        texts[#texts + 1] = "The attack missed!"
      end
      return texts
    end
  end
  self:armRage(attacker, effect, true)
  if effect == Game3.EFFECT_OHKO then
    return self:useOhko(attacker, defender, move, texts)
  end
  local absorbed = self:typeAbsorb(defender, move, attacker)
  if absorbed then
    texts[#texts + 1] = absorbed
    return texts
  end
  local hit = false
  if effect == Game3.EFFECT_CONFUSE then
    local line = self:applyConfuse(defender)
    if line then
      texts[#texts + 1] = line
    elseif (defender.confuseTurns or 0) > 0 then
      texts[#texts + 1] = ("%s is already confused!"):format(defender.name)
    elseif self:hasAbility(defender, Game3.ABILITY_OWN_TEMPO) then
      texts[#texts + 1] = ("It doesn't affect %s..."):format(defender.name)
    else
      texts[#texts + 1] = "But it failed!"
    end
    return texts
  end
  if effect == Game3.EFFECT_LEECH_SEED then
    return self:useLeechSeed(attacker, defender, texts)
  end
  if effect == Game3.EFFECT_FORESIGHT then
    return self:useForesight(attacker, defender, texts)
  end
  if power > 0 then
    local hits = self:hitCountFor(effect)
    local total, lastMul, landed = 0, 10, 0
    local critHit, enduredHit = false, false
    for _ = 1, hits do
      if (defender.hp or 0) <= 0 then break end
      local result = self:dealDamage(attacker, defender, move)
      lastMul = result.mul
      if result.mul <= 0 then
        texts[#texts + 1] = ("It doesn't affect %s..."):format(defender.name)
        landed = 0
        break
      end
      landed = landed + 1
      total = total + result.dmg
      if result.crit then critHit = true end
      if result.endured then enduredHit = true end
    end
    if landed > 0 then
      hit = true
      if critHit then texts[#texts + 1] = "A critical hit!" end
      if lastMul > 10 then texts[#texts + 1] = "It's super effective!" end
      if lastMul < 10 and lastMul > 0 then
        texts[#texts + 1] = "It's not very effective..."
      end
      if enduredHit then
        texts[#texts + 1] = ("%s endured the hit!"):format(defender.name)
      end
      if hits > 1 then
        texts[#texts + 1] = ("Hit %d time%s!"):format(
          landed, landed == 1 and "" or "s")
      end
      if effect == Game3.EFFECT_ABSORB and total > 0 then
        local heal = math.max(1, math.floor(total / 2))
        if self:hasAbility(defender, Game3.ABILITY_LIQUID_OOZE) then
          attacker.hp = math.max(0, (attacker.hp or 0) - heal)
          texts[#texts + 1] = ("It was sucked into %s's %s!"):format(
            defender.name, Game3.abilityName(Game3.ABILITY_LIQUID_OOZE))
        else
          local maxHp = attacker.maxHp or (attacker.hp or 0)
          attacker.hp = math.min(maxHp, (attacker.hp or 0) + heal)
          texts[#texts + 1] = ("%s had its energy drained!"):format(defender.name)
        end
      end
      local denom = Game3.recoilDenom(effect)
      if denom and total > 0 and (attacker.hp or 0) > 0
          and not self:hasAbility(attacker, Game3.ABILITY_ROCK_HEAD) then
        local recoil = math.max(1, math.floor(total / denom))
        attacker.hp = math.max(0, (attacker.hp or 0) - recoil)
        texts[#texts + 1] = ("%s is hit with recoil!"):format(attacker.name)
      end
      self:tickRage(defender, total, texts)
    end
  elseif Game3.statDownSpec(effect) then
    return self:useStatDownMove(defender, move, effect, texts)
  else
    local status = Game3.statusFromEffect(effect)
    if status then
      local line = self:applyStatus(defender, status)
      if line then
        texts[#texts + 1] = line
        local sync = self:trySynchronize(defender, attacker, status)
        if sync then texts[#texts + 1] = sync end
      elseif not self:canStatus(defender, status) and not defender.status then
        texts[#texts + 1] = ("It doesn't affect %s..."):format(defender.name)
      else
        texts[#texts + 1] = "But it failed!"
      end
    else
      texts[#texts + 1] = "But it failed!"
    end
  end
  if hit and (defender.hp or 0) > 0 then
    self:applyHitSecondaries(attacker, defender, move, effect, texts)
  end
  if hit and Game3.isContact(move) then
    self:onContact(attacker, defender, texts)
  end
  if (defender.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(defender.name)
  end
  if (attacker.hp or 0) <= 0 then
    texts[#texts + 1] = ("%s fainted!"):format(attacker.name)
  end
  return texts
end

function Game3:pickEnemyMove(mon)
  if mon and mon.charging and mon.charging.move then
    return mon.charging.move
  end
  local moves = mon.moves or {}
  local damaging = {}
  local ready = {}
  for i = 1, #moves do
    local m = moves[i]
    if m and (m.pp or 0) > 0 then
      ready[#ready + 1] = m
      if (m.power or 0) > 0 then damaging[#damaging + 1] = m end
    end
  end
  local pool = #damaging > 0 and damaging or ready
  if #pool < 1 then return self:copyMove(33) end
  return pool[self:rand(#pool)]
end

function Game3:speedOf(mon)
  if not mon then return 0 end
  local s = staged(mon, "spe")
  if mon.status == Game3.STATUS_PAR then
    s = math.max(1, math.floor(s / 4))
  end
  if not self:weatherSuppressed() then
    local w = self.battle and self.battle.weather
    if w == Game3.WEATHER_RAIN
        and self:hasAbility(mon, Game3.ABILITY_SWIFT_SWIM) then
      s = s * 2
    elseif w == Game3.WEATHER_SUN
        and self:hasAbility(mon, Game3.ABILITY_CHLOROPHYLL) then
      s = s * 2
    end
  end
  return s
end

-- pokeruby battle_main.c: one gRandomTurnNumber per turn. Quick Claw
-- (param 20) sets speed to UINT_MAX when roll < (param * 0xFFFF) / 100.
function Game3.quickClawThreshold(param)
  return math.floor((tonumber(param) or 0) * 65535 / 100)
end

function Game3:turnSpeed(mon, turnRoll)
  local s = self:speedOf(mon)
  local effect, param = self:holdEffectOf(mon)
  if effect == Game3.HOLD_EFFECT_QUICK_CLAW
      and (tonumber(turnRoll) or 0) < Game3.quickClawThreshold(param) then
    return Game3.QUICK_CLAW_SPEED
  end
  return s
end

function Game3:turnOrder(playerMove, enemyMove)
  local pp = (playerMove and playerMove.priority) or 0
  local ep = (enemyMove and enemyMove.priority) or 0
  if pp ~= ep then return pp > ep end
  return self:speedOf(self.battle.player) >= self:speedOf(self.battle.enemy)
end

function Game3:queueBattlerMove(move, target)
  local b = self.battle
  if not b then return end
  local lead = self:menuBattler()
  if b.doubles and lead == b.player and Game3.aliveMon(b.player2) then
    b.pendingMove = move
    b.pendingTarget = target
    b.chooser = "player2"
    b.kind = "menu"
    b.cursor = 0
    b.fightCursor = 0
    return
  end
  self:beginTurn(move, target)
end

function Game3:beginTurn(playerMove, chosen)
  local b = self.battle
  local lead = self:menuBattler()
  if lead and lead.charging and lead.charging.move then
    playerMove = lead.charging.move
  end
  local mons = { b.player, b.player2, b.enemy, b.enemy2 }
  for i = 1, 4 do
    local mon = mons[i]
    if mon then
      mon.flinch = nil
      mon.protected = nil
      mon.endured = nil
    end
  end
  local turnRoll = self:rand(65536) - 1
  local actions = {}
  local function add(mon, move, side, slot, pick, item)
    if not Game3.aliveMon(mon) then return end
    if not move and not item then return end
    actions[#actions + 1] = {
      mon = mon, move = move, item = item, side = side, slot = slot,
      chosen = pick,
      pri = item and 7 or ((move and move.priority) or 0),
      spe = self:turnSpeed(mon, turnRoll),
    }
  end
  local function moveFor(mon)
    if mon == lead then return playerMove, chosen end
    if mon == b.player and b.pendingMove then
      return b.pendingMove, b.pendingTarget
    end
    return self:pickEnemyMove(mon)
  end
  if Game3.aliveMon(b.player) then
    local mv, pick = moveFor(b.player)
    add(b.player, mv, 0, 0, pick)
  end
  if Game3.aliveMon(b.player2) then
    local mv, pick = moveFor(b.player2)
    add(b.player2, mv, 0, 1, pick)
  end
  if Game3.aliveMon(b.enemy) then
    local item = self:takeTrainerHealItem(b.enemy)
    if item then
      add(b.enemy, nil, 1, 0, nil, item)
    else
      add(b.enemy, self:pickEnemyMove(b.enemy), 1, 0)
    end
  end
  if Game3.aliveMon(b.enemy2) then
    add(b.enemy2, self:pickEnemyMove(b.enemy2), 1, 1)
  end
  b.pendingMove, b.pendingTarget = nil, nil
  b.chooser = "player"
  table.sort(actions, function(a, c)
    if a.pri ~= c.pri then return a.pri > c.pri end
    if a.spe ~= c.spe then return a.spe > c.spe end
    if a.side ~= c.side then return a.side < c.side end
    return a.slot < c.slot
  end)
  local queue = {}
  local function run(attacker, pick, move)
    if (attacker.hp or 0) <= 0 then return end
    local targets
    local t = (move and move.target) or 0
    if t == Game3.TARGET_USER then
      targets = { attacker }
    elseif Game3.isSpreadTarget(t) then
      targets = self:spreadTargets(attacker, move)
    else
      local one = pick
      if not Game3.aliveMon(one) then one = self:defaultTarget(attacker) end
      targets = one and { one } or {}
    end
    if #targets < 1 then return end
    local skip, msgs = self:statusBlocks(attacker, move)
    for i = 1, #msgs do queue[#queue + 1] = msgs[i] end
    if skip then
      self:cancelMultiTurn(attacker)
      return
    end
    skip, msgs = self:confuseBlocks(attacker)
    for i = 1, #msgs do queue[#queue + 1] = msgs[i] end
    if skip then
      self:cancelMultiTurn(attacker)
      return
    end
    if attacker.flinch then
      attacker.flinch = nil
      self:cancelMultiTurn(attacker)
      queue[#queue + 1] = ("%s flinched and couldn't move!"):format(
        attacker.name)
      return
    end
    move.spreadHits = #targets > 1
    for i = 1, #targets do
      if (attacker.hp or 0) <= 0 then break end
      if Game3.aliveMon(targets[i]) then
        local texts = self:useMove(attacker, targets[i], move, i > 1)
        for j = 1, #texts do queue[#queue + 1] = texts[j] end
        if attacker.charging then break end
      end
    end
    move.spreadHits = nil
  end
  for i = 1, #actions do
    local act = actions[i]
    if act.item then
      local texts = self:applyTrainerItem(act.mon, act.item)
      for j = 1, #texts do queue[#queue + 1] = texts[j] end
    else
      run(act.mon, act.chosen, act.move)
    end
    if b.fled then break end
  end
  if not b.fled then
    local function residual(mon)
      if not mon then return end
      local texts = self:leechSeedResidual(mon)
      for i = 1, #texts do queue[#queue + 1] = texts[i] end
      texts = self:statusResidual(mon)
      for i = 1, #texts do queue[#queue + 1] = texts[i] end
      texts = self:tickHeldItem(mon)
      for i = 1, #texts do queue[#queue + 1] = texts[i] end
    end
    residual(b.player)
    residual(b.player2)
    residual(b.enemy)
    residual(b.enemy2)
    local wtexts = self:tickWeather()
    for i = 1, #wtexts do queue[#queue + 1] = wtexts[i] end
    local function awardFoe(foe)
      if not foe or (foe.hp or 0) > 0 or foe.expPaid then return end
      local winner = Game3.aliveMon(b.player) and b.player
        or (Game3.aliveMon(b.player2) and b.player2)
      if not winner then return end
      foe.expPaid = true
      local texts = self:awardExp(winner, foe, b.isTrainer)
      for i = 1, #texts do queue[#queue + 1] = texts[i] end
    end
    awardFoe(b.enemy)
    awardFoe(b.enemy2)
  end
  b.turns = (b.turns or 0) + 1
  b.queue = queue
  b.qi = 1
  b.kind = "text"
  b.text = queue[1] or ""
  b.animT = 0.28
end

function Game3:advanceBattleText()
  local b = self.battle
  b.qi = (b.qi or 1) + 1
  if b.queue and b.qi <= #b.queue then
    b.text = b.queue[b.qi]
    b.textPage = 0
    b.printSrc = nil
    return
  end
  if b.thenLearnAsk then
    b.thenLearnAsk = nil
    self:openLearnYesNo()
    return
  end
  self:afterBattleMessages()
end

function Game3:afterBattleMessages()
  local b = self.battle
  if self:startPendingLearn() then return end
  if self:startPendingEvolve() then return end
  if b.pickupDone then
    self:endBattle()
    return
  end
  if b.fled then
    self:endBattle()
    return
  end
  if b.caught then
    self:finishBattle()
  elseif (not Game3.aliveMon(b.enemy) and not Game3.aliveMon(b.enemy2))
      or (b.doubles and (not Game3.aliveMon(b.enemy) or not Game3.aliveMon(b.enemy2))) then
    local noEnemies = not Game3.aliveMon(b.enemy) and not Game3.aliveMon(b.enemy2)
    if b.isTrainer then
      if self:canOfferShift() then
        b.kind = "switch_ask"
        b.cursor = 0
        b.text = "Will you switch POKeMON?"
        b.queue = nil
        return
      elseif self:sendTrainerReplacement() then
        return
      elseif noEnemies then
        self:openTrainerVictory()
      else
        self:afterFaintContinue()
      end
    elseif noEnemies then
      self:finishBattle()
    else
      self:afterFaintContinue()
    end
  else
    self:afterFaintContinue()
  end
end

function Game3:stepBattle(dt)
  local b = self.battle
  if not b then return end
  dt = dt or 0
  if b.kind == "intro" then
    b.introT = math.min(1, (b.introT or 0) + dt / 0.45)
  end
  if (b.animT or 0) > 0 then
    b.animT = b.animT - dt
    if b.animT < 0 then b.animT = 0 end
  end
  if b.kind == "intro" or b.kind == "menu_msg" or b.kind == "text"
      or b.kind == "ran" or b.kind == "won_trainer" or b.kind == "blackout"
      or b.kind == "switch_ask" or b.kind == "evolve"
      or b.kind == "learn_yesno" or b.kind == "learn_stop"
      or b.kind == "learn_msg" or b.kind == "learn_forget" then
    self:stepPrinter(b, dt)
  end
  if b.kind == "evolve" then
    self:stepEvolve(dt)
    return
  end
  if b.kind == "switch_ask" then
    if Input:wasPressed("up") or Input:wasPressed("down") then
      b.cursor = 1 - (b.cursor or 0)
    elseif Input:wasPressed("a") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      if (b.cursor or 0) == 0 then
        b.kind = "party"
        b.shiftSwitch = true
        b.mustSwitch = false
        b.partyCursor = 0
        b.text = nil
      else
        self:sendTrainerReplacement()
      end
    elseif Input:wasPressed("b") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      self:sendTrainerReplacement()
    end
    return
  end
  if b.kind == "learn_yesno" then
    if Input:wasPressed("up") or Input:wasPressed("down") then
      b.cursor = 1 - (b.cursor or 0)
    elseif Input:wasPressed("a") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      self:answerLearnYesNo((b.cursor or 0) == 0)
    elseif Input:wasPressed("b") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      self:answerLearnYesNo(false)
    end
    return
  end
  if b.kind == "learn_stop" then
    if Input:wasPressed("up") or Input:wasPressed("down") then
      b.cursor = 1 - (b.cursor or 0)
    elseif Input:wasPressed("a") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      self:answerLearnStop((b.cursor or 0) == 0)
    elseif Input:wasPressed("b") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      self:answerLearnStop(false)
    end
    return
  end
  if b.kind == "learn_forget" then
    local mon = self.learnMove and self.learnMove.mon
    local moves = mon and mon.moves or {}
    local n = #moves + 1
    if n < 1 then n = 1 end
    if Input:wasPressed("down") then
      b.cursor = ((b.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      b.cursor = ((b.cursor or 0) - 1) % n
      if b.cursor < 0 then b.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      self:chooseLearnForget((b.cursor or 0) + 1)
    elseif Input:wasPressed("b") then
      self:openLearnStop()
    end
    return
  end
  if b.kind == "learn_msg" then
    if Input:wasPressed("a") or Input:wasPressed("b") then
      if self:printerBusy(b) then
        self:printerFinish(b)
        return
      end
      if self:advanceDialogue(b) then return end
      b.qi = (b.qi or 1) + 1
      if b.queue and b.qi <= #b.queue then
        b.text = b.queue[b.qi]
        b.textPage = 0
        b.printSrc = nil
        return
      end
      self:finishLearnMessage()
    end
    return
  end
  if b.kind == "menu" then
    local lead = self:menuBattler()
    if lead and lead.charging then
      self:beginTurn(lead.charging.move)
      return
    end
    if Input:wasPressed("b") and b.doubles and b.chooser == "player2" then
      b.chooser = "player"
      b.pendingMove, b.pendingTarget = nil, nil
      b.cursor = 0
      return
    end
    if Input:wasPressed("right") or Input:wasPressed("left") then
      b.cursor = b.cursor % 2 == 0 and b.cursor + 1 or b.cursor - 1
    elseif Input:wasPressed("down") or Input:wasPressed("up") then
      b.cursor = (b.cursor + 2) % 4
    elseif Input:wasPressed("a") then
      if b.cursor == 0 then
        b.kind = "fight"
        b.fightCursor = 0
      elseif b.cursor == 1 then
        b.kind = "bag"
        b.bagCursor = 0
      elseif b.cursor == 2 then
        b.kind = "party"
        b.partyCursor = 0
      elseif b.cursor == 3 then
        if b.isTrainer or b.chase or b.wallyTutorial then
          b.text = (b.chase or b.wallyTutorial)
            and "There's no running from this battle!"
            or "No! There's no running from a TRAINER battle!"
          b.kind = "menu_msg"
        else
          b.text = "Got away safely!"
          b.kind = "ran"
        end
      end
    end
    return
  end
  if b.kind == "bag" then
    local list = self:battleBagList()
    local n = #list
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      b.kind = "menu"
    elseif Input:wasPressed("down") then
      b.bagCursor = ((b.bagCursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      b.bagCursor = ((b.bagCursor or 0) - 1) % n
      if b.bagCursor < 0 then b.bagCursor = n - 1 end
    elseif Input:wasPressed("a") then
      local slot = list[(b.bagCursor or 0) + 1]
      if not slot then
        b.text = "The BAG is empty."
        b.kind = "menu_msg"
      else
        self:useBattleItem(slot.id)
      end
    end
    return
  end
  if b.kind == "party" then
    local n = #(self.party or {})
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      if b.mustSwitch then
        return
      elseif b.shiftSwitch then
        b.shiftSwitch = false
        self:sendTrainerReplacement()
      else
        b.kind = "menu"
      end
    elseif Input:wasPressed("down") then
      b.partyCursor = ((b.partyCursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      b.partyCursor = ((b.partyCursor or 0) - 1) % n
      if b.partyCursor < 0 then b.partyCursor = n - 1 end
    elseif Input:wasPressed("a") then
      local ok, msg, extra = self:switchTo((b.partyCursor or 0) + 1)
      if not ok then return end
      if b.shiftSwitch then
        b.shiftSwitch = false
        self:sendTrainerReplacement()
        return
      end
      local queue = { msg }
      for i = 1, #(extra or {}) do queue[#queue + 1] = extra[i] end
      if b.mustSwitch then
        b.mustSwitch = false
      elseif (b.enemy.hp or 0) > 0 then
        self:queueEnemyAction(queue)
      end
      b.queue = queue
      b.qi = 1
      b.kind = "text"
      b.text = queue[1]
    end
    return
  end
  if b.kind == "fight" then
    local battler = self:menuBattler() or b.player
    local n = #((battler and battler.moves) or {})
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      b.kind = "menu"
    elseif Input:wasPressed("down") then
      b.fightCursor = ((b.fightCursor or 0) + 1) % 4
      if b.fightCursor >= n then b.fightCursor = 0 end
    elseif Input:wasPressed("up") then
      b.fightCursor = ((b.fightCursor or 0) - 1) % 4
      if b.fightCursor < 0 then b.fightCursor = math.max(0, n - 1) end
      if b.fightCursor >= n then b.fightCursor = math.max(0, n - 1) end
    elseif Input:wasPressed("right") or Input:wasPressed("left") then
      -- ROM fight list is vertical; left/right still wrap one slot.
      local d = Input:wasPressed("right") and 1 or -1
      b.fightCursor = ((b.fightCursor or 0) + d) % 4
      if b.fightCursor >= n then b.fightCursor = 0 end
      if b.fightCursor < 0 then b.fightCursor = math.max(0, n - 1) end
    elseif Input:wasPressed("a") then
      local move = battler and battler.moves and battler.moves[b.fightCursor + 1]
      if not move then return end
      if (move.pp or 0) <= 0 then
        b.text = "There's no PP left!"
        b.kind = "menu_msg"
      else
        local opts = self:selectableTargets(battler, move)
        if b.doubles and #opts > 1 then
          b.kind = "target"
          b.targetMove = move
          b.targetList = opts
          b.targetCursor = 0
        else
          self:queueBattlerMove(move)
        end
      end
    end
    return
  end
  if b.kind == "target" then
    local list = b.targetList or {}
    local n = #list
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      b.kind = "fight"
    elseif Input:wasPressed("right") or Input:wasPressed("left")
        or Input:wasPressed("down") or Input:wasPressed("up") then
      b.targetCursor = ((b.targetCursor or 0) + 1) % n
    elseif Input:wasPressed("a") then
      local pick = list[(b.targetCursor or 0) + 1]
      self:queueBattlerMove(b.targetMove, pick)
    end
    return
  end
  if not Input:wasPressed("a") then return end
  if self:advanceDialogue(b) then
    return
  end
  if b.kind == "intro" or b.kind == "menu_msg" then
    if b.kind == "intro" then
      self:dismissIntro()
    else
      b.kind = "menu"
      b.text = nil
    end
  elseif b.kind == "text" then
    self:advanceBattleText()
  elseif b.kind == "ran" then
    self:endBattle()
  elseif b.kind == "won_trainer" then
    self:confirmTrainerWin()
  elseif b.kind == "blackout" then
    self:blackout()
  end
end

function Game3:battlePic(species, which)
  species = tonumber(species)
  if not species then return nil end
  local pack = self.data.encounters or {}
  local paths = pack.fronts
  if which == "back" then paths = pack.backs end
  local path = paths and (paths[species] or paths[tostring(species)])
  if type(path) ~= "string" then
    local folder = "front"
    if which == "back" then folder = "back" end
    path = ("assets/generated/battle/%s/%d.png"):format(folder, species)
  end
  self.battlePicCache = self.battlePicCache or {}
  local key = which .. ":" .. species
  if self.battlePicCache[key] ~= nil then
    return self.battlePicCache[key] or nil
  end
  local img = self:grabImage(path)
  self.battlePicCache[key] = img or false
  return img
end

function Game3.fontCode(ch)
  if type(ch) ~= "string" or ch == "" then return 0x00 end
  if ch == "é" or ch == "è" or ch == "ê" or ch == "ë" then return 0xD9 end
  if ch == "É" or ch == "È" or ch == "Ê" or ch == "Ë" then return 0xBF end
  if #ch > 1 then ch = ch:sub(1, 1) end
  local b = ch:byte()
  if ch == " " then return 0x00 end
  if b >= 65 and b <= 90 then return 0xBB + (b - 65) end
  if b >= 97 and b <= 122 then return 0xD5 + (b - 97) end
  if b >= 48 and b <= 57 then return 0xA1 + (b - 48) end
  if ch == "!" then return 0xAB end
  if ch == "?" then return 0xAC end
  if ch == "." then return 0xAD end
  if ch == "-" then return 0xAE end
  if ch == "'" then return 0xB4 end
  if ch == "," then return 0xB8 end
  if ch == "/" then return 0xAE end
  if ch == ":" then return 0xF0 end
  return 0x00
end

function Game3:fontImage()
  if self._fontImage ~= nil then return self._fontImage or nil end
  local spec = self.data and self.data.font
  local path = spec and spec.image or "assets/generated/fonts/font.png"
  local img = self:grabImage(path)
  self._fontImage = img or false
  return img
end

function Game3:uiFont()
  if self._uiFont ~= nil then return self._uiFont or nil end
  if not (love and love.graphics and love.graphics.newFont) then
    self._uiFont = false
    return nil
  end
  local ok, font = pcall(love.graphics.newFont, 8)
  self._uiFont = (ok and font) or false
  return self._uiFont or nil
end

function Game3:drawFallbackText(text, x, y)
  local G = love.graphics
  local font = self:uiFont()
  local prev
  if font and G.setFont then
    if G.getFont then prev = G.getFont() end
    G.setFont(font)
  end
  G.print(text, x, y)
  if prev and G.setFont then G.setFont(prev) end
end

function Game3:drawGlyph(code, x, y)
  local img = self:fontImage()
  local quad, gw = self:fontQuad(code)
  if img and quad then
    local G = love.graphics
    G.setColor(1, 1, 1, 1)
    G.draw(img, quad, x, y)
  end
  return gw or 8
end

function Game3:fontQuad(code)
  code = tonumber(code) or 0
  local spec = self.data and self.data.font or {}
  local gw = spec.glyphW or 8
  local gh = spec.glyphH or 16
  local cols = spec.cols or 16
  local img = self:fontImage()
  local sw, sh = cols * gw, 16 * gh
  if img and img.getDimensions then
    sw, sh = img:getDimensions()
  end
  local col = code % cols
  local row = math.floor(code / cols)
  local key = ("font:%d:%d:%d"):format(code, sw, sh)
  self.quads = self.quads or {}
  local q = self.quads[key]
  if not q and love.graphics.newQuad then
    q = love.graphics.newQuad(col * gw, row * gh, gw, gh, sw, sh)
    self.quads[key] = q
  end
  return q, gw, gh
end

function Game3:drawText(text, x, y)
  text = tostring(text or "")
  local G = love.graphics
  local img = self:fontImage()
  if not img then
    self:drawFallbackText(text, x, y)
    return
  end
  local cr, cg, cb, ca = 1, 1, 1, 1
  if G.getColor then
    cr, cg, cb, ca = G.getColor()
  end
  G.setColor(1, 1, 1, 1)
  local gx = x
  local i = 1
  while i <= #text do
    local b = text:byte(i)
    local ch = text:sub(i, i)
    local skip = 1
    local code
    if b == 0xC3 and i < #text then
      local n = text:byte(i + 1)
      if n == 0xA9 or n == 0xA8 or n == 0xAA or n == 0xAB then
        ch = "e"
        skip = 2
      elseif n == 0x89 or n == 0x88 or n == 0x8A or n == 0x8B then
        ch = "E"
        skip = 2
      end
    elseif b == 0xE2 and i + 2 <= #text and text:byte(i + 1) == 0x99 then
      local n = text:byte(i + 2)
      if n == 0x82 then
        code = Game3.FONT_MALE
        skip = 3
      elseif n == 0x80 then
        code = Game3.FONT_FEMALE
        skip = 3
      end
    end
    if not code then code = Game3.fontCode(ch) end
    local quad, gw = self:fontQuad(code)
    if quad then
      G.draw(img, quad, gx, y)
    end
    gx = gx + (gw or 8)
    i = i + skip
  end
  G.setColor(cr, cg, cb, ca)
end

function Game3:textDelay()
  local n = (self.options and self.options.textSpeed) or 2
  return Game3.TEXT_DELAY[n] or Game3.TEXT_DELAY[2]
end

function Game3:printerBusy(box)
  if type(box) ~= "table" or not box.printLive then return false end
  local text = box.fullText or box.text or ""
  return (box.printN or 0) < #text
end

function Game3:printedText(box)
  if type(box) ~= "table" then return "" end
  local text = box.fullText or box.text or ""
  if not box.printLive then return text end
  return text:sub(1, box.printN or 0)
end

function Game3.wrapDialogue(text, maxPx)
  maxPx = maxPx or Game3.MSG_WIDTH_PX
  local gw = Game3.MSG_GLYPH_PX
  text = tostring(text or ""):gsub("\r\n", "\n")
  local lines = {}
  local function emit(line)
    if line and line ~= "" then lines[#lines + 1] = line end
  end
  local function wrapPara(para)
    local line, width = "", 0
    local function flush()
      emit(line)
      line, width = "", 0
    end
    local function take(word)
      local wpx = #word * gw
      if line ~= "" and width + gw + wpx > maxPx then
        flush()
      end
      if line == "" and wpx > maxPx then
        local col = math.max(1, math.floor(maxPx / gw))
        while #word > col do
          emit(word:sub(1, col))
          word = word:sub(col + 1)
        end
        line, width = word, #word * gw
        return
      end
      if line == "" then
        line, width = word, wpx
      else
        line = line .. " " .. word
        width = width + gw + wpx
      end
    end
    for word in para:gmatch("%S+") do
      take(word)
    end
    flush()
  end
  if text:find("\n", 1, true) then
    local start = 1
    while true do
      local at = text:find("\n", start, true)
      if not at then
        wrapPara(text:sub(start))
        break
      end
      wrapPara(text:sub(start, at - 1))
      start = at + 1
    end
  else
    wrapPara(text)
  end
  if #lines < 1 then lines[1] = "" end
  return lines
end

function Game3:dialogueHasMore(box)
  if type(box) ~= "table" then return false end
  local lines = Game3.wrapDialogue(box.fullText or box.text or "")
  return (box.textPage or 0) + Game3.MSG_LINES < #lines
end

function Game3:advanceDialogue(box)
  if type(box) ~= "table" then return false end
  if self:printerBusy(box) then
    self:printerFinish(box)
    return true
  end
  if self:dialogueHasMore(box) then
    box.textPage = (box.textPage or 0) + Game3.MSG_LINES
    return true
  end
  return false
end

function Game3:drawDialogue(box, x, y)
  if type(box) ~= "table" then return end
  local page = box.textPage or 0
  local source
  if page > 0 then
    source = box.fullText or box.text or ""
  else
    source = self:printedText(box)
  end
  local lines = Game3.wrapDialogue(source)
  love.graphics.setColor(0.10, 0.10, 0.12, 1)
  for i = 0, Game3.MSG_LINES - 1 do
    local line = lines[page + i + 1]
    if line and line ~= "" then
      self:drawText(line, x, y + i * Game3.MSG_LINE_H)
    end
  end
  if self:dialogueHasMore(box) and not self:printerBusy(box) then
    self:drawText("v", x + Game3.MSG_WIDTH_PX - 8, y + Game3.MSG_LINE_H + 2)
  end
end

function Game3:printerFinish(box)
  if type(box) ~= "table" then return end
  local text = box.fullText or box.text or ""
  box.printN = #text
  box.fullText = text
end

function Game3:stepPrinter(box, dt)
  if type(box) ~= "table" then return end
  dt = dt or 0
  if dt <= 0 then return end
  local text = box.text or ""
  if box.printSrc ~= text then
    box.printSrc = text
    box.fullText = text
    box.printN = 0
    box.printWait = 0
    box.textPage = 0
  end
  box.printLive = true
  if (box.printN or 0) >= #text then return end
  local delay = self:textDelay()
  if Input:isDown("a") or Input:isDown("b") then delay = 0 end
  if delay <= 0 then
    box.printN = #text
    return
  end
  box.printWait = (box.printWait or 0) + dt
  while box.printWait >= delay and (box.printN or 0) < #text do
    box.printWait = box.printWait - delay
    box.printN = (box.printN or 0) + 1
  end
end

function Game3:drawWindow(x, y, w, h)
  local G = love.graphics
  -- pokeruby WINDOW_NORMAL: black outer, white fill, 2px blue inner frame.
  G.setColor(0.06, 0.06, 0.08, 1)
  G.rectangle("fill", x, y, w, h)
  G.setColor(0.97, 0.97, 0.94, 1)
  G.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
  G.setColor(0.36, 0.56, 0.84, 1)
  G.rectangle("fill", x + 2, y + 2, w - 4, 2)
  G.rectangle("fill", x + 2, y + h - 4, w - 4, 2)
  G.rectangle("fill", x + 2, y + 2, 2, h - 4)
  G.rectangle("fill", x + w - 4, y + 2, 2, h - 4)
end

-- pokeruby GetStringWidthInTilesForScriptMenu: 8px glyphs, ceil to tiles.
function Game3.stringWidthTiles(text)
  local n = #tostring(text or "")
  if n < 1 then return 1 end
  return math.floor((n * Game3.MSG_GLYPH_PX + 7) / Game3.MENU_TILE)
end

-- pokeruby script_menu.c DrawMultichoiceMenu: left/top/right/bottom tiles.
function Game3.multichoiceFrame(left, top, labels)
  labels = labels or {}
  local count = #labels
  if count < 1 then count = 1 end
  local width = 1
  for i = 1, #labels do
    local w = Game3.stringWidthTiles(labels[i])
    if w > width then width = w end
  end
  left = tonumber(left) or 0
  top = tonumber(top) or 0
  local right = width + left + 1
  if right > Game3.MULTI_MAX_RIGHT then
    left = left + (Game3.MULTI_MAX_RIGHT - right)
    right = Game3.MULTI_MAX_RIGHT
    if left < 0 then left = 0 end
  end
  local bottom = top + (2 * count + 1)
  return left, top, right, bottom
end

function Game3:drawMenuListWindow(left, top, labels, cursor, perRow)
  labels = labels or {}
  local count = #labels
  if count < 1 then return end
  local tile = Game3.MENU_TILE
  local cols = tonumber(perRow) or 0
  if cols < 2 then cols = 1 end
  local rows = math.ceil(count / cols)
  local left0, top0, right, bottom
  if cols > 1 then
    local width = 1
    for i = 1, count do
      local w = Game3.stringWidthTiles(labels[i])
      if w > width then width = w end
    end
    left0 = tonumber(left) or 0
    top0 = tonumber(top) or 0
    right = left0 + cols * (width + 1) + 1
    if right > Game3.MULTI_MAX_RIGHT then right = Game3.MULTI_MAX_RIGHT end
    bottom = top0 + (2 * rows + 1)
  else
    left0, top0, right, bottom = Game3.multichoiceFrame(left, top, labels)
  end
  local x = left0 * tile
  local y = top0 * tile
  local w = (right - left0 + 1) * tile
  local h = (bottom - top0 + 1) * tile
  self:drawWindow(x, y, w, h)
  local cur = cursor or 0
  local colW = cols > 1 and math.floor((right - left0) / cols) * tile or 0
  for i = 0, count - 1 do
    local col, row
    if cols > 1 then
      col = i % cols
      row = math.floor(i / cols)
    else
      col, row = 0, i
    end
    local tx = (left0 + 1) * tile + col * (colW > 0 and colW or 0)
    local ty = (top0 + 1) * tile + row * 16
    if i == cur then
      love.graphics.setColor(0.90, 0.28, 0.22, 1)
      self:drawCursor(tx, ty)
    end
    love.graphics.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(labels[i + 1] or "", tx + 10, ty)
  end
end

function Game3:drawYesNoWindow(left, top, cursor)
  local tile = Game3.MENU_TILE
  left = tonumber(left) or Game3.YESNO_LEFT
  top = tonumber(top) or Game3.YESNO_TOP
  local w = (Game3.YESNO_RIGHT_OFF + 1) * tile
  local h = (Game3.YESNO_BOTTOM_OFF + 1) * tile
  self:drawWindow(left * tile, top * tile, w, h)
  local labels = { "YES", "NO" }
  for i = 0, 1 do
    local y = (top + 1) * tile + i * 16
    local x = (left + 1) * tile
    if i == (cursor or 0) then
      love.graphics.setColor(0.90, 0.28, 0.22, 1)
      self:drawCursor(x, y)
    end
    love.graphics.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(labels[i + 1], x + 10, y)
  end
end

function Game3:drawCursor(x, y)
  local G = love.graphics
  G.setColor(0.22, 0.22, 0.28, 1)
  if G.polygon then
    G.polygon("fill", x, y + 2, x, y + 12, x + 6, y + 7)
  else
    G.rectangle("fill", x, y + 4, 6, 6)
  end
end

function Game3:drawHpBar(x, y, w, hp, maxHp)
  local G = love.graphics
  G.setColor(0.12, 0.12, 0.14, 1)
  G.rectangle("fill", x, y, w, 4)
  local fill = 0
  if maxHp and maxHp > 0 then fill = math.floor(w * (hp or 0) / maxHp) end
  if fill < 0 then fill = 0 elseif fill > w then fill = w end
  local ratio = maxHp and maxHp > 0 and (hp or 0) / maxHp or 0
  if ratio > 0.5 then G.setColor(0.35, 0.82, 0.38, 1)
  elseif ratio > 0.2 then G.setColor(0.90, 0.78, 0.22, 1)
  else G.setColor(0.90, 0.28, 0.22, 1) end
  if fill > 0 then G.rectangle("fill", x, y, fill, 4) end
end

function Game3:picYOffset(species, which)
  local pack = self.data.encounters or {}
  local ys = pack.frontY
  if which == "back" then ys = pack.backY end
  if type(ys) ~= "table" then return 0 end
  return ys[species] or ys[tostring(species)] or 0
end

function Game3.battlerCenter(side, doubles)
  local cx = doubles and Game3.BATTLER_CX_DOUBLES or Game3.BATTLER_CX
  local cy = doubles and Game3.BATTLER_CY_DOUBLES or Game3.BATTLER_CY
  return cx[side] or 72, cy[side] or 80
end

function Game3:battlerTopLeft(side, species, which)
  local cx, cy = Game3.battlerCenter(side, self.battle and self.battle.doubles)
  return cx - 32, cy - 32 + self:picYOffset(species, which)
end

function Game3:healthboxXY(side)
  local pack = (self.battle and self.battle.doubles)
    and Game3.HEALTHBOX_XY_DOUBLES or Game3.HEALTHBOX_XY
  local xy = pack[side] or Game3.HEALTHBOX_XY.player
  return xy[1], xy[2]
end

function Game3:drawBattleBackground()
  local G = love.graphics
  local env = self:battleEnvironment()
  local pack = self.data.encounters or {}
  local path = pack.bgs and (pack.bgs[env] or pack.bgs[tostring(env)])
  local img = type(path) == "string" and self:grabImage(path)
  if img then
    G.setColor(1, 1, 1, 1)
    G.draw(img, 0, 0)
    return
  end
  local fill = ({
    [0] = { 0.45, 0.72, 0.42 },
    [1] = { 0.38, 0.62, 0.32 },
    [2] = { 0.78, 0.70, 0.42 },
    [3] = { 0.18, 0.38, 0.62 },
    [4] = { 0.22, 0.48, 0.70 },
    [5] = { 0.32, 0.58, 0.62 },
    [6] = { 0.55, 0.48, 0.38 },
    [7] = { 0.32, 0.28, 0.28 },
    [8] = { 0.55, 0.52, 0.48 },
    [9] = { 0.62, 0.70, 0.48 },
  })[env] or { 0.55, 0.78, 0.62 }
  G.setColor(fill[1], fill[2], fill[3], 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, 112)
  G.setColor(fill[1] * 0.75, fill[2] * 0.75, fill[3] * 0.75, 1)
  G.ellipse("fill", 176, 56, 56, 14)
  G.ellipse("fill", 56, 96, 52, 12)
end

function Game3:drawHealthbox(mon, x, y, kind)
  if not mon then return end
  local G = love.graphics
  local player = kind == "player"
  local w = player and 118 or 110
  local h = player and 42 or 28
  G.setColor(0.22, 0.22, 0.26, 1)
  G.rectangle("fill", x, y, w, h)
  G.setColor(0.97, 0.97, 0.90, 1)
  G.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
  G.setColor(0.10, 0.10, 0.12, 1)
  local name = mon.name or "POKeMON"
  self:drawText(name, x + 6, y + 2)
  local gend = self:monGender(mon)
  local gx = x + 6 + #name * 8 + 2
  if gend == Game3.MON_MALE then
    self:drawGlyph(Game3.FONT_MALE, gx, y + 2)
  elseif gend == Game3.MON_FEMALE then
    self:drawGlyph(Game3.FONT_FEMALE, gx, y + 2)
  end
  if not player and self:hasCaught(mon.species) then
    G.setColor(0.85, 0.22, 0.22, 1)
    if G.circle then
      G.circle("fill", x + w - 8, y + 8, 3)
      G.setColor(0.97, 0.97, 0.90, 1)
      G.circle("fill", x + w - 9, y + 7, 1)
    else
      G.rectangle("fill", x + w - 11, y + 5, 6, 6)
    end
  end
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText(("Lv%d"):format(mon.level or 1), x + w - 40, y + 2)
  local tag = Game3.statusTag(mon.status)
  if tag ~= "" then
    G.setColor(0.70, 0.22, 0.22, 1)
    self:drawText(tag, x + 6, y + 14)
  end
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText("HP", x + 6, y + (player and 16 or 14))
  self:drawHpBar(x + 22, y + (player and 20 or 18), w - 30, mon.hp, mon.maxHp)
  if player then
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(("%d/%d"):format(mon.hp or 0, mon.maxHp or 0),
      x + w - 50, y + 24)
    local fill = Game3.expBarFill(mon)
    G.setColor(0.12, 0.12, 0.14, 1)
    G.rectangle("fill", x + 22, y + 34, w - 30, 3)
    local ew = math.floor((w - 30) * fill)
    if ew > 0 then
      G.setColor(0.32, 0.62, 0.95, 1)
      G.rectangle("fill", x + 22, y + 34, ew, 3)
    end
  end
end

function Game3:drawBattlePic(species, which, x, y, scale, drop, flash)
  local G = love.graphics
  scale = scale or 1
  drop = drop or 0
  local img = self:battlePic(species, which)
  if flash then
    G.setColor(1, 1, 1, 0.45)
  else
    G.setColor(1, 1, 1, 1)
  end
  if img then
    G.draw(img, x, y + drop, 0, scale, scale)
  else
    local w = math.floor(48 * scale)
    if which == "back" then
      G.setColor(0.93, 0.28, 0.22, flash and 0.45 or 1)
    else
      G.setColor(0.25, 0.18, 0.22, flash and 0.45 or 1)
    end
    G.rectangle("fill", x + 16, y + 12 + drop, w, w)
  end
end

function Game3:drawBattle()
  local G = love.graphics
  local b = self.battle
  local slide = 1
  if b and b.kind == "intro" then
    slide = b.introT or 0
    if slide < 0 then slide = 0 elseif slide > 1 then slide = 1 end
  end
  local hit = (b and b.animT) or 0
  local lunge = 0
  if hit > 0 then lunge = math.floor(8 * math.sin(hit / 0.28 * math.pi) + 0.5) end
  local flash = hit > 0 and math.floor(hit * 24) % 2 == 1
  self:drawBattleBackground()
  if b and b.enemy then
    local drop = ((b.enemy.hp or 0) <= 0) and 28 or 0
    local px, py = self:battlerTopLeft("enemy", b.enemy.species, "front")
    px = px + math.floor((1 - slide) * 90) + lunge
    self:drawBattlePic(b.enemy.species, "front", px, py + (flash and 1 or 0),
      1, drop, flash)
    local hx, hy = self:healthboxXY("enemy")
    self:drawHealthbox(b.enemy, hx, hy, "enemy")
  end
  if b and b.enemy2 then
    local drop = ((b.enemy2.hp or 0) <= 0) and 20 or 0
    local px, py = self:battlerTopLeft("enemy2", b.enemy2.species, "front")
    self:drawBattlePic(b.enemy2.species, "front", px, py, 1, drop, flash)
    local hx, hy = self:healthboxXY("enemy2")
    self:drawHealthbox(b.enemy2, hx, hy, "enemy")
  end
  if b and b.player then
    local drop = ((b.player.hp or 0) <= 0) and 20 or 0
    local evo = self.evolve
    local species = b.player.species
    local scale, evoFlash = 1, false
    if evo and evo.mon == b.player then
      scale, evoFlash, species = self:evolveDraw()
    end
    local px, py = self:battlerTopLeft("player", species, "back")
    px = px - math.floor((1 - slide) * 90) - lunge
    if scale ~= 1 then
      px = px + math.floor(32 * (1 - scale))
      py = py + math.floor(32 * (1 - scale))
    end
    self:drawBattlePic(species, "back", px, py, scale, drop, evoFlash)
    local hx, hy = self:healthboxXY("player")
    self:drawHealthbox(b.player, hx, hy, "player")
  end
  if b and b.player2 then
    local drop = ((b.player2.hp or 0) <= 0) and 16 or 0
    local px, py = self:battlerTopLeft("player2", b.player2.species, "back")
    self:drawBattlePic(b.player2.species, "back", px, py, 1, drop, false)
    local hx, hy = self:healthboxXY("player2")
    self:drawHealthbox(b.player2, hx, hy, "player")
  end
  G.setColor(0.18, 0.18, 0.22, 1)
  if b and b.kind == "menu" then
    self:drawWindow(0, 112, 120, 48)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("What will", 8, 118)
    local pname = (b.player and b.player.name) or "POKeMON"
    self:drawText(pname .. " do?", 8, 134)
    self:drawWindow(120, 112, 120, 48)
    local labels = { "FIGHT", "BAG", "POKeMON", "RUN" }
    for i = 0, 3 do
      local x = 128 + (i % 2) * 56
      local y = 118 + math.floor(i / 2) * 16
      if i == b.cursor then
        self:drawCursor(x, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(labels[i + 1], x + 10, y)
    end
  else
  self:drawWindow(0, 112, Game3.SCREEN_W, 48)
  if b and b.kind == "fight" then
    local battler = self:menuBattler() or b.player
    local moves = (battler and battler.moves) or {}
    self:drawWindow(0, 112, 152, 48)
    self:drawWindow(152, 112, 88, 48)
    for i = 0, 3 do
      local mv = moves[i + 1]
      local y = 114 + i * 11
      if i == (b.fightCursor or 0) then
        self:drawCursor(6, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if mv then
        self:drawText(mv.name or "-", 16, y)
      else
        self:drawText("-", 16, y)
      end
    end
    local cur = moves[(b.fightCursor or 0) + 1]
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("TYPE/", 160, 118)
    self:drawText(cur and Game3.typeName(cur.type) or "???", 160, 130)
    self:drawText("PP", 160, 142)
    if cur then
      self:drawText(("%d/%d"):format(cur.pp or 0, cur.maxPp or 0), 184, 142)
    else
      self:drawText("--", 184, 142)
    end
  elseif b and b.kind == "target" then
    local list = b.targetList or {}
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Aim at", 8, 118)
    for i = 1, #list do
      local mon = list[i]
      local y = 118 + i * 14
      if i - 1 == (b.targetCursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if mon then self:drawText(mon.name or "FOE", 18, y) end
    end
  elseif b and b.kind == "bag" then
    local list = self:battleBagList()
    local start = b.bagCursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
    if #list < 1 then
        self:drawText("The BAG is empty.", 18, 120)
    else
      for i = 0, 1 do
        local slot = list[start + i + 1]
        local y = 118 + i * 16
        if i == 0 then
          G.setColor(0.90, 0.28, 0.22, 1)
          self:drawCursor(8, y)
        end
        G.setColor(0.10, 0.10, 0.12, 1)
        if slot then
          self:drawText(("%s  x%d"):format(self:itemName(slot.id), slot.count or 0),
            18, y)
        end
      end
    end
        self:drawText("A use   B back", 8, 148)
  elseif b and b.kind == "party" then
    local party = self.party or {}
    local start = b.partyCursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
    for i = 0, 1 do
      local mon = party[start + i + 1]
      local y = 118 + i * 16
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if mon then
        self:drawText(("%s  %d/%d"):format(mon.name, mon.hp or 0, mon.maxHp or 0), 18, y)
      end
    end
    if b.mustSwitch then
        self:drawText("A send out", 150, 148)
    else
        self:drawText("A send   B back", 120, 148)
    end
  elseif b and b.kind == "switch_ask"
      or (b and (b.kind == "learn_yesno" or b.kind == "learn_stop")) then
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(self:printedText(b), 10, 118)
    local labels = { "YES", "NO" }
    for i = 0, 1 do
      local y = 132 + i * 10
      if i == (b.cursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(labels[i + 1], 18, y)
    end
  elseif b and b.kind == "learn_forget" then
    local mon = self.learnMove and self.learnMove.mon
    local moves = mon and mon.moves or {}
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("Forget which?", 8, 114)
    local n = #moves + 1
    for i = 0, n - 1 do
      local y = 124 + i * 8
      if i == (b.cursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if i < #moves then
        self:drawText((moves[i + 1] and moves[i + 1].name) or "MOVE", 18, y)
      else
        self:drawText("CANCEL", 18, y)
      end
    end
  else
    self:drawDialogue(b, 10, 118)
  end
  end
end

function Game3:walkHeld(dt)
  if self.phase == "play" then
    self.playSeconds = (self.playSeconds or 0) + (dt or 0)
    local frames = math.floor((dt or 0) * 60 + 0.0001)
    self.vblankCounter = (self.vblankCounter or 0) + frames
    self:tickBerryTrees(dt or 0)
    self:stepGrassRustle(dt or 0)
  end
  if self.phase == "battle" then
    self:stepBattle(dt)
    return
  end
  if self.phase ~= "play" then return end
  if self.field then
    if self.field.kind == "fishing" then
      self:stepFishing(dt or 0)
      self:clampCamera()
      return
    end
    if self.field.kind == "talk" or self.field.kind == "script_yesno"
        or self.field.kind == "learn_yesno" or self.field.kind == "learn_stop" then
      self:stepPrinter(self.field, dt or 0)
    end
    if self.field.kind == "evolve" then
      self:stepPrinter(self.field, dt or 0)
      self:stepEvolve(dt or 0)
      self:clampCamera()
      return
    end
    if self.field.kind == "trainer_approach" then
      self:stepTrainerApproach(dt or 0)
      self:clampCamera()
      return
    end
    if self.field.kind == "move" then
      self:stepScriptMove(dt or 0)
      self:clampCamera()
      if not self:scriptMoving() then self:resumeMoveScript() end
      return
    end
    if self.field.kind == "delay" then
      self.delayLeft = (self.delayLeft or 0) - (dt or 0)
      if self.delayLeft < 0 then self.delayLeft = 0 end
      if not self:scriptDelaying() then self:resumeMoveScript() end
      return
    end
    if self.field.kind == "wait" then
      -- waitstate after a sync warp never arms scriptWait; resume so the
      -- player is not frozen on an idle wait tile.
      if self.flashAnim then
        self:stepFlashAnimDt(dt or 0)
      end
      if not self:scriptWaiting() then self:resumeMoveScript() end
      return
    end
    self:clampCamera()
    if not self._scriptPause then
      self:stepNpcs(dt or 0)
    end
    return
  end
  if self:flushPendingMapScripts() then
    self:clampCamera()
    self:stepNpcs(dt or 0)
    return
  end
  if self:tryMapFrameScript() then
    self:clampCamera()
    self:stepNpcs(dt or 0)
    return
  end
  if dt and dt > 1 / 20 then dt = 1 / 20 end
  local wasWalking = (self.walkCooldown or 0) > 0
  self.walkCooldown = (self.walkCooldown or 0) - (dt or 0)
  if self.walkCooldown > 0 then
    self:clampCamera()
  else
    if wasWalking then
      self.walkCooldown = 0
      self.hopping = nil
      self:clampCamera()
      if self:tryTrainerSpot() then
        self:stepNpcs(dt or 0)
        return
      end
      if self:tryWildEncounter() then
        self:stepNpcs(dt or 0)
        return
      end
    end
    local dx, dy = 0, 0
    if Input:isDown("left") then dx = -1
    elseif Input:isDown("right") then dx = 1
    elseif Input:isDown("up") then dy = -1
    elseif Input:isDown("down") then dy = 1
    end
    if dx ~= 0 or dy ~= 0 then
      if self.warpSettle then
        -- Held input from the previous map must not walk us back into
        -- the stair warp. Wait for a release.
      else
        self.running = self:wantRun()
        local dir = Game3.facingFromDelta(dx, dy)
        if dir ~= self.facing then
          self.facing = dir
        else
          self:tryWalk(dx, dy)
        end
      end
    else
      self.running = nil
      self.warpSettle = nil
    end
  end
  self:clampCamera()
  self:stepNpcs(dt or 0)
end

function Game3:facingNpc()
  local map = self.map
  if not map then return nil end
  local dx, dy = Game3.deltaFromFacing(self.facing)
  local x, y = self.playerX + dx, self.playerY + dy
  local npc = self:npcAt(map, x, y)
  if npc then return npc end
  if Game3.isCounter(self:behaviorAt(map, x, y)) then
    return self:npcAt(map, x + dx, y + dy)
  end
end

function Game3.dirId(facing)
  local names = Game3.DIR_FACING
  for i = 1, #names do
    if names[i] == facing then return i end
  end
  return Game3.DIR_SOUTH
end

function Game3:rememberTalk(npc)
  self.scriptVars = self.scriptVars or {}
  self.scriptVars[Game3.VAR_LAST_TALKED] = (npc and npc.localId) or 0
  self.scriptVars[Game3.VAR_FACING] = Game3.dirId(self.facing)
end

function Game3:tryTalk()
  local npc = self:facingNpc()
  if npc then
    self:rememberTalk(npc)
    local opp = { north = "south", south = "north", west = "east", east = "west" }
    npc.facing = opp[self.facing] or "south"
    npc.talkLock = true
    npc.facingLocked = true
    self._scriptNpc = npc
    local gid = npc.graphicsId or 0
    if gid == Game3.GFX_NURSE
        or (gid == Game3.GFX_MOM and not npc.script) then
      self:healParty()
      self:markHealPoint()
      if gid == Game3.GFX_MOM then
        self.field = { kind = "talk", text = "MOM: You should rest a bit." }
      else
        self.field = { kind = "talk", text = "Your POKeMON were restored to full health!" }
      end
    elseif gid == Game3.GFX_DAYCARE_MAN
        and (self.map and self.map.mapType) == Game3.MAP_TYPE_ROUTE then
      return self:talkDaycareMan()
    elseif gid == Game3.GFX_DAYCARE_LADY
        and (self.map and self.map.mapType) == Game3.MAP_TYPE_INDOOR then
      return self:openDaycare()
    elseif gid == Game3.GFX_TEALA
        and (self.map and self.map.mapType) == Game3.MAP_TYPE_INDOOR then
      return self:openContest()
    elseif npc.script then
      self._scriptNpc = npc
      if self:runNpcScript(npc.script) then return true end
      if (npc.trainerType or 0) > 0 and not npc.defeated
          and type(npc.party) == "table" and #npc.party > 0 then
        return self:startTrainerBattle(npc)
      end
      self.field = { kind = "talk", text = "..." }
    elseif (npc.trainerType or 0) > 0 and not npc.defeated
        and type(npc.party) == "table" and #npc.party > 0 then
      return self:startTrainerBattle(npc)
    elseif npc.itemId and not npc.hidden then
      return self:pickupItem(npc)
    elseif gid == Game3.GFX_MART or (npc.mart and #npc.mart > 0) then
      return self:openMart(npc)
    elseif self:isStarterGiver(npc) and not self:hasStarter() then
      return self:openStarterMenu(npc)
    elseif gid == Game3.GFX_BIRCH and self:hasStarter() and not self:hasPokedex() then
      return self:givePokedex()
    elseif gid == Game3.GFX_BIRCH and self:giveNationalDex() then
      return true
    elseif self:talkRival(npc) then
      return true
    else
      self.field = { kind = "talk", text = "..." }
    end
    return true
  end
  if self:tryPc() then return true end
  return self:tryBgEvent()
end

function Game3:sayScript(text)
  if type(text) ~= "string" or text == "" then return end
  self._scriptSays = self._scriptSays or {}
  self._scriptSays[#self._scriptSays + 1] = self:expandScriptText(text)
end

function Game3:openScriptYesNo(text)
  local box = self._scriptYesNo or {}
  self._scriptYesNo = nil
  local x, y = box.x, box.y
  if x == nil then x = Game3.YESNO_LEFT end
  if y == nil then y = Game3.YESNO_TOP end
  self.field = {
    kind = "script_yesno",
    text = text or "...",
    cursor = 0,
    boxX = x,
    boxY = y,
  }
  return true
end

function Game3:multichoiceLabels(id)
  local row = Game3.MULTICHOICE[tonumber(id) or 0]
  if type(row) == "table" and #row > 0 then return row end
end

function Game3:openScriptChoice(text, choice)
  choice = choice or self._scriptChoice or {}
  local labels = choice.labels or { "CANCEL" }
  local cursor = choice.cursor or 0
  if cursor < 0 or cursor >= #labels then cursor = 0 end
  self.field = {
    kind = "script_choice",
    text = text,
    labels = labels,
    cursor = cursor,
    ignoreB = choice.ignoreB and true or nil,
    boxX = choice.x or 0,
    boxY = choice.y or 0,
    perRow = choice.perRow,
  }
  return true
end

function Game3:answerScriptChoice(index)
  self.scriptVars = self.scriptVars or {}
  self.scriptVars[Gen3Script.VAR_RESULT] = tonumber(index) or Game3.MULTI_B_PRESSED
  self._scriptChoice = nil
  local pause = self._scriptPause
  self._scriptPause = nil
  if type(pause) ~= "table" or type(pause.ops) ~= "table" then
    self:closeField()
    self:endScriptRun()
    return false
  end
  self._scriptSays = {}
  local _, again = self:continueScript(pause.ops, pause.at)
  return self:presentScript(again)
end

function Game3:presentScript(pause)
  local says = self._scriptSays or {}
  self._scriptSays = nil
  if pause == "yesno" then
    local prompt = says[#says] or "..."
    local prior = {}
    for i = 1, #says - 1 do prior[i] = says[i] end
    if #prior > 0 then
      self.field = {
        kind = "talk", text = prior[1], queue = prior, qi = 1,
        thenYesNo = prompt,
      }
    else
      self:openScriptYesNo(prompt)
    end
    return true
  end
  if pause == "choice" then
    local prompt = says[#says]
    if not prompt and self.field and self.field.kind == "talk" then
      prompt = self.field.text
    end
    self:openScriptChoice(prompt, self._scriptChoice)
    return true
  end
  if pause == "msg" then
    if #says < 1 then return self:resumeMoveScript() end
    self.field = {
      kind = "talk", text = says[1], queue = says, qi = 1,
      thenContinue = true,
    }
    return true
  end
  if pause == "mart" then
    if not (self.field and self.field.kind == "mart") then
      self:openMartList(nil)
    end
    return true
  end
  if pause == "move" or pause == "delay" or pause == "wait" then
    -- msgbox then waitmovement is the Route 101 shove: keep the line on
    -- screen and only start the walk after A, matching pokeruby.
    if #says > 0 then
      self.field = {
        kind = "talk", text = says[1], queue = says, qi = 1,
        thenPause = pause,
      }
      return true
    end
    if pause == "wait" and self.phase == "battle" then
      return true
    end
    if pause == "wait" and self.field and self.field.kind
        and self.field.kind ~= "wait" and self.field.kind ~= "talk" then
      return true
    end
    self.field = { kind = pause }
    return true
  end
  if #says > 0 then
    self.field = { kind = "talk", text = says[1], queue = says, qi = 1 }
    self:endScriptRun()
    return true
  end
  self:closeField()
  self:endScriptRun()
  return false
end

function Game3:continueScript(ops, at)
  local said, pause = Gen3Script.run(self, ops, at)
  while not pause do
    local stack = self._scriptReturn
    if type(stack) ~= "table" or #stack < 1 then break end
    local frame = table.remove(stack)
    self._scriptLoaded = frame.loaded
    self._scriptCmp = frame.result
    local more
    more, pause = Gen3Script.run(self, frame.ops, frame.at)
    if more then said = true end
  end
  return said, pause
end

function Game3:answerScriptYesNo(yes)
  self.scriptVars = self.scriptVars or {}
  self.scriptVars[Gen3Script.VAR_RESULT] = yes and 1 or 0
  local pause = self._scriptPause
  self._scriptPause = nil
  if type(pause) ~= "table" or type(pause.ops) ~= "table" then
    self:closeField()
    self:endScriptRun()
    return false
  end
  self._scriptSays = {}
  local _, again = self:continueScript(pause.ops, pause.at)
  return self:presentScript(again)
end

function Game3:runNpcScript(ops)
  if type(ops) ~= "table" or #ops < 1 then return false end
  self._scriptSays = {}
  self._scriptPause = nil
  self._scriptReturn = nil
  self._scriptLoaded = nil
  self._scriptCmp = 0
  self:beginScriptRun()
  local _, pause = Gen3Script.run(self, ops)
  return self:presentScript(pause)
end

function Game3:pickupHidden(ev)
  if not ev or not ev.itemId or ev.itemId < 1 then return false end
  local flag = Game3.hiddenFlag(ev.hiddenId)
  self.flags = self.flags or {}
  if self.flags[flag] then return false end
  self:addItem(ev.itemId, 1)
  self.flags[flag] = true
  self.field = { kind = "talk", text = ("Found %s!"):format(self:itemName(ev.itemId)) }
  return true
end

function Game3:isClockBg(ev)
  local t = ev and ev.text
  return type(t) == "string" and t:find("clock is stopped", 1, true) ~= nil
end

function Game3:setWallClock()
  self.flags = self.flags or {}
  self.flags[Game3.FLAG_SET_WALL_CLOCK] = true
  self.flags[Game3.FLAG_HIDE_MACHOKE_MOVER_1] = true
  self.flags[Game3.FLAG_HIDE_MACHOKE_MOVER_2] = true
  self.scriptVars = self.scriptVars or {}
  self.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE] = 6
  self.field = { kind = "talk", text = "The clock started!" }
  return true
end

function Game3:activateBg(ev)
  if not ev then return false end
  local kind = ev.kind or 0
  if kind == Game3.BG_HIDDEN_ITEM or kind == 5 or kind == 6 then
    return self:pickupHidden(ev)
  end
  if kind > 4 then return false end
  if not Game3.bgFacingOk(kind, self.facing) then return false end
  if type(ev.script) == "table" and #ev.script > 0 then
    return self:runNpcScript(ev.script)
  end
  if self:isClockBg(ev) then
    if self.flags and self.flags[Game3.FLAG_SET_WALL_CLOCK] then
      self.field = { kind = "talk", text = "It's the wall clock." }
      return true
    end
    return self:setWallClock()
  end
  self.field = { kind = "talk", text = ev.text or "..." }
  return true
end

function Game3:tryBgEvent()
  local map = self.map
  if not map then return false end
  local dx, dy = Game3.deltaFromFacing(self.facing)
  local x, y = self.playerX + dx, self.playerY + dy
  if self:activateBg(Game3.bgAt(map, x, y)) then return true end
  if Game3.isCounter(self:behaviorAt(map, x, y)) then
    return self:activateBg(Game3.bgAt(map, x + dx, y + dy))
  end
  return false
end

function Game3:closeField()
  local chase = self.field and self.field.chase
  self.field = nil
  self:unlockScriptNpcs()
  if self:startPendingLearn() then return end
  if chase then self:startBirchChase() end
end

function Game3:finishFieldItem(msg)
  if self.phase == "battle" then return end
  local f = self.field
  if f and (f.kind == "fly" or f.kind == "secret_base_move"
      or f.kind == "party_teach" or f.kind == "party_forget"
      or f.kind == "fishing") then
    return
  end
  if msg == nil then return end
  self.field = { kind = "talk", text = msg }
end

function Game3:stepBag(f)
  local pocket = f.pocket or self.lastBagPocket or Game3.POCKET_ITEMS
  if pocket < Game3.POCKET_ITEMS then pocket = Game3.POCKET_ITEMS end
  if pocket > Game3.POCKET_KEY then pocket = Game3.POCKET_KEY end
  f.pocket = pocket
  self.lastBagPocket = pocket
  local list = self:bagSlotsIn(pocket)
  local n = #list
  if n < 1 then n = 1 end
  if Input:wasPressed("b") then
    if f.giveTo then
      local index = f.giveTo
      self.field = {
        kind = "party_item",
        cursor = 0,
        monIndex = index,
        actions = self:partyItemActions((self.party or {})[index]),
      }
    else
      self:backToStart("BAG")
    end
  elseif Input:wasPressed("right") then
    f.pocket = pocket % Game3.POCKET_COUNT + 1
    f.cursor = 0
    self.lastBagPocket = f.pocket
  elseif Input:wasPressed("left") then
    f.pocket = (pocket - 2) % Game3.POCKET_COUNT + 1
    f.cursor = 0
    self.lastBagPocket = f.pocket
  elseif Input:wasPressed("down") then
    f.cursor = ((f.cursor or 0) + 1) % n
  elseif Input:wasPressed("up") then
    f.cursor = ((f.cursor or 0) - 1) % n
    if f.cursor < 0 then f.cursor = n - 1 end
  elseif Input:wasPressed("a") then
    local slot = list[(f.cursor or 0) + 1]
    if slot then
      if f.giveTo then
        local _, msg = self:giveHeldItem(f.giveTo, slot.id)
        self:finishFieldItem(msg)
      else
        local _, msg = self:useFieldItem(slot.id)
        self:finishFieldItem(msg)
      end
    end
  elseif Input:wasPressed("select") then
    local slot = list[(f.cursor or 0) + 1]
    if slot then
      local _, msg = self:toggleRegisteredItem(slot.id)
      f.note = msg
    end
  end
end

function Game3:stepParty(f)
  if Input:wasPressed("b") then
    if f.kind == "party_teach" then
      self:openBag()
      return
    end
    self:backToStart("POKeMON")
    return
  end
  local n = #(self.party or {})
  if n < 1 then n = 1 end
  if Input:wasPressed("down") then
    f.cursor = ((f.cursor or 0) + 1) % n
  elseif Input:wasPressed("up") then
    f.cursor = ((f.cursor or 0) - 1) % n
    if f.cursor < 0 then f.cursor = n - 1 end
  elseif Input:wasPressed("a") then
    if f.kind == "party_teach" then
      self:chooseTeachMon((f.cursor or 0) + 1)
    else
      self:openPartyAction((f.cursor or 0) + 1)
    end
  end
end

function Game3:stepPartyAction(f)
  local actions = f.actions or { "CANCEL" }
  local n = #actions
  if n < 1 then n = 1 end
  if Input:wasPressed("b") then
    if f.kind == "party_item" then
      self:openPartyAction(f.monIndex or 1)
    else
      self.field = { kind = "party", cursor = (f.monIndex or 1) - 1 }
    end
    return
  end
  if Input:wasPressed("down") then
    f.cursor = ((f.cursor or 0) + 1) % n
  elseif Input:wasPressed("up") then
    f.cursor = ((f.cursor or 0) - 1) % n
    if f.cursor < 0 then f.cursor = n - 1 end
  elseif Input:wasPressed("a") then
    local name = actions[(f.cursor or 0) + 1]
    local index = f.monIndex or 1
    if name == "SUMMARY" then
      self:openPartySummary(index)
    elseif name == "SWITCH" then
      self.field = {
        kind = "party_switch",
        cursor = index - 1,
        monIndex = index,
      }
    elseif name == "ITEM" then
      local mon = (self.party or {})[index]
      self.field = {
        kind = "party_item",
        cursor = 0,
        monIndex = index,
        actions = self:partyItemActions(mon),
      }
    elseif name == "GIVE" then
      self:openBagForGive(index)
    elseif name == "TAKE" then
      local _, msg = self:takeHeldItem(index)
      self:finishFieldItem(msg)
    elseif name == "CANCEL" or not name then
      if f.kind == "party_item" then
        self:openPartyAction(index)
      else
        self.field = { kind = "party", cursor = index - 1 }
      end
    else
      local mon = (self.party or {})[index]
      local _, msg = self:usePartyFieldMoveNamed(mon, name)
      self:finishFieldItem(msg)
    end
  end
end

function Game3:stepPartySwitch(f)
  local n = #(self.party or {})
  if n < 1 then n = 1 end
  if Input:wasPressed("b") then
    self:openPartyAction(f.monIndex or 1)
    return
  end
  if Input:wasPressed("down") then
    f.cursor = ((f.cursor or 0) + 1) % n
  elseif Input:wasPressed("up") then
    f.cursor = ((f.cursor or 0) - 1) % n
    if f.cursor < 0 then f.cursor = n - 1 end
  elseif Input:wasPressed("a") then
    local from = f.monIndex or 1
    local to = (f.cursor or 0) + 1
    self:swapParty(from, to)
    self.field = { kind = "party", cursor = (f.cursor or 0) }
  end
end

function Game3:stepPartyForget(f)
  local mon = (self.party or {})[f.monIndex or 1]
  local moves = mon and mon.moves or {}
  local n = #moves + 1
  if n < 1 then n = 1 end
  if Input:wasPressed("b") then
    self.field = { kind = "party_teach", cursor = (f.monIndex or 1) - 1, item = f.item }
    return
  end
  if Input:wasPressed("down") then
    f.cursor = ((f.cursor or 0) + 1) % n
  elseif Input:wasPressed("up") then
    f.cursor = ((f.cursor or 0) - 1) % n
    if f.cursor < 0 then f.cursor = n - 1 end
  elseif Input:wasPressed("a") then
    local slot = (f.cursor or 0) + 1
    if slot > #moves then
      self.field = { kind = "party_teach", cursor = (f.monIndex or 1) - 1, item = f.item }
      return
    end
    if Game3.isHmMove(moves[slot] and moves[slot].id) then
      self.field = { kind = "talk", text = "HM moves can't be forgotten now." }
      return
    end
    local _, msg = self:teachTMHM(f.monIndex or 1, f.item, slot)
    self.field = { kind = "talk", text = msg }
  end
end

function Game3:stepPartySummary(f)
  if Input:wasPressed("b") or Input:wasPressed("a") then
    self:openPartyAction(f.monIndex or 1)
  elseif Input:wasPressed("right") then
    f.page = ((f.page or 0) + 1) % Game3.PARTY_SUMMARY_PAGES
  elseif Input:wasPressed("left") then
    f.page = ((f.page or 0) - 1) % Game3.PARTY_SUMMARY_PAGES
    if f.page < 0 then f.page = Game3.PARTY_SUMMARY_PAGES - 1 end
  end
end

function Game3:stepField()
  local f = self.field
  if not f then return end
  if f.kind == "move" or f.kind == "delay" or f.kind == "wait"
      or f.kind == "trainer_approach" or f.kind == "evolve"
      or f.kind == "fishing" then
    return
  end
  if f.kind == "talk" then
    if Input:wasPressed("a") or Input:wasPressed("b") then
      if self:advanceDialogue(f) then
        return
      end
      local queue, qi = f.queue, f.qi or 1
      if type(queue) == "table" and qi < #queue then
        f.qi = qi + 1
        f.text = queue[f.qi]
        f.textPage = 0
        f.printSrc = nil
      elseif f.thenYesNo then
        self:openScriptYesNo(f.thenYesNo)
      elseif f.thenLearnAsk then
        self:openLearnYesNo()
      elseif f.thenLearn then
        self:finishLearnMessage()
      elseif f.thenContinue then
        self:resumeMoveScript()
      elseif f.thenPause then
        local pause = f.thenPause
        self.field = { kind = pause }
        if pause == "move" and not self:scriptMoving() then
          self:resumeMoveScript()
        elseif pause == "delay" and not self:scriptDelaying() then
          self:resumeMoveScript()
        elseif pause == "wait" and not self:scriptWaiting() then
          self:resumeMoveScript()
        end
      else
        self:closeField()
      end
    end
    return
  end
  if f.kind == "option" then
    self:stepOptionMenu(f, function()
      self:backToStart("OPTION")
    end)
    return
  end
  if f.kind == "trainer_card" then
    if Input:wasPressed("a") or Input:wasPressed("b") then
      self:backToStart(self:playerName())
    end
    return
  end
  if f.kind == "pokenav" then
    if Input:wasPressed("a") or Input:wasPressed("b")
        or Input:wasPressed("start") then
      self:backToStart("POKeNAV")
    end
    return
  end
  if f.kind == "save_ask" then
    if Input:wasPressed("up") or Input:wasPressed("down") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      if (f.cursor or 0) == 0 then
        self:confirmSave()
      else
        self:backToStart("SAVE")
      end
    elseif Input:wasPressed("b") then
      self:backToStart("SAVE")
    end
    return
  end
  if f.kind == "bag" then
    self:stepBag(f)
    return
  end
  if f.kind == "party" or f.kind == "party_teach" then
    self:stepParty(f)
    return
  end
  if f.kind == "party_action" or f.kind == "party_item" then
    self:stepPartyAction(f)
    return
  end
  if f.kind == "party_switch" then
    self:stepPartySwitch(f)
    return
  end
  if f.kind == "party_forget" then
    self:stepPartyForget(f)
    return
  end
  if f.kind == "party_summary" then
    self:stepPartySummary(f)
    return
  end
  if f.kind == "pc" then
    local mode = f.mode or "root"
    if mode == "root" then
      if Input:wasPressed("b") then
        self:closeField()
      elseif Input:wasPressed("down") then
        f.cursor = ((f.cursor or 0) + 1) % 3
      elseif Input:wasPressed("up") then
        f.cursor = ((f.cursor or 0) - 1) % 3
        if f.cursor < 0 then f.cursor = 2 end
      elseif Input:wasPressed("a") then
        local c = f.cursor or 0
        if c == 0 then
          f.mode = "box"
          f.cursor = 0
          f.note = nil
        elseif c == 1 then
          f.mode = "party"
          f.cursor = 0
          f.note = nil
        else
          self:closeField()
        end
      end
    elseif mode == "box" then
      self:ensurePc()
      local box = self.pc[f.box] or {}
      local n = #box
      if n < 1 then n = 1 end
      if Input:wasPressed("b") then
        f.mode = "root"
        f.cursor = 0
      elseif Input:wasPressed("left") then
        f.box = ((f.box or 1) - 2) % Game3.BOX_COUNT + 1
        f.cursor = 0
      elseif Input:wasPressed("right") then
        f.box = (f.box or 1) % Game3.BOX_COUNT + 1
        f.cursor = 0
      elseif Input:wasPressed("down") then
        f.cursor = ((f.cursor or 0) + 1) % n
      elseif Input:wasPressed("up") then
        f.cursor = ((f.cursor or 0) - 1) % n
        if f.cursor < 0 then f.cursor = n - 1 end
      elseif Input:wasPressed("a") then
        local ok, msg = self:withdrawFromBox(f.box, (f.cursor or 0) + 1)
        f.note = msg
        local left = #(self.pc[f.box] or {})
        if f.cursor >= left and left > 0 then f.cursor = left - 1 end
      end
    else
      local n = #(self.party or {})
      if n < 1 then n = 1 end
      if Input:wasPressed("b") then
        f.mode = "root"
        f.cursor = 1
      elseif Input:wasPressed("down") then
        f.cursor = ((f.cursor or 0) + 1) % n
      elseif Input:wasPressed("up") then
        f.cursor = ((f.cursor or 0) - 1) % n
        if f.cursor < 0 then f.cursor = n - 1 end
      elseif Input:wasPressed("a") then
        local ok, msg = self:depositFromParty((f.cursor or 0) + 1)
        f.note = msg
        local left = #(self.party or {})
        if f.cursor >= left and left > 0 then f.cursor = left - 1 end
      end
    end
    return
  end
  if f.kind == "gender" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      self:chooseGender((f.cursor or 0) == 1
        and Game3.GENDER_FEMALE or Game3.GENDER_MALE)
    end
    return
  end
  if f.kind == "nickname" then
    local keys = f.keys or Game3.nameKeys()
    local n = #keys
    local cols = Game3.NICKNAME_COLS
    if n < 1 then n = 1 end
    if Input:wasPressed("left") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("right") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - cols) % n
      if f.cursor < 0 then f.cursor = f.cursor + n end
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + cols) % n
    elseif Input:wasPressed("b") then
      local name = f.name or ""
      f.name = name:sub(1, math.max(0, #name - 1))
    elseif Input:wasPressed("a") or Input:wasPressed("start") then
      local key = keys[(f.cursor or 0) + 1]
      if key == "END" or Input:wasPressed("start") then
        self:finishNickname()
      elseif key == "DEL" then
        local name = f.name or ""
        f.name = name:sub(1, math.max(0, #name - 1))
      else
        local name = f.name or ""
        if #name < Game3.NICKNAME_LEN then f.name = name .. key end
      end
    end
    return
  end
  if f.kind == "starter" then
    local n = #Game3.STARTERS
    if Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      local species = Game3.STARTERS[(f.cursor or 0) + 1]
      f.kind = "starter_yesno"
      f.species = species
      f.pick = f.cursor
      f.cursor = 0
      f.text = ("So you want %s?"):format(self:speciesName(species))
    end
    return
  end
  if f.kind == "starter_yesno" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      if (f.cursor or 0) ~= 0 then
        f.kind = "starter"
        f.cursor = f.pick or 0
        f.text = nil
        return
      end
      if f.scripted then
        self:setScriptVar(Gen3Script.VAR_RESULT, Game3.starterIndex(f.species) or 0)
        self:giveMon(f.species, Game3.STARTER_LEVEL)
        self.field = nil
        self:startBirchChase()
        return
      end
      local ok, msg = self:giveStarter(f.species, f.npc)
      local chase = self.pendingChase
      self.pendingChase = nil
      self.field = { kind = "talk", text = msg or "Got it!", chase = chase }
    elseif Input:wasPressed("b") then
      f.kind = "starter"
      f.cursor = f.pick or 0
      f.text = nil
    end
    return
  end
  if f.kind == "script_yesno" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      self:answerScriptYesNo((f.cursor or 0) == 0)
    elseif Input:wasPressed("b") then
      self:answerScriptYesNo(false)
    end
    return
  end
  if f.kind == "learn_yesno" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      self:answerLearnYesNo((f.cursor or 0) == 0)
    elseif Input:wasPressed("b") then
      self:answerLearnYesNo(false)
    end
    return
  end
  if f.kind == "learn_stop" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      self:answerLearnStop((f.cursor or 0) == 0)
    elseif Input:wasPressed("b") then
      self:answerLearnStop(false)
    end
    return
  end
  if f.kind == "learn_forget" then
    local mon = (self.learnMove and self.learnMove.mon) or f.mon
    local moves = mon and mon.moves or {}
    local n = #moves + 1
    if n < 1 then n = 1 end
    if Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      self:chooseLearnForget((f.cursor or 0) + 1)
    elseif Input:wasPressed("b") then
      self:openLearnStop()
    end
    return
  end
  if f.kind == "script_choice" then
    local n = #(f.labels or {})
    if n < 1 then n = 1 end
    local cols = tonumber(f.perRow) or 0
    if cols > 1 then
      local rows = math.ceil(n / cols)
      if Input:wasPressed("right") then
        local col = (f.cursor or 0) % cols
        if col + 1 < cols and (f.cursor or 0) + 1 < n then
          f.cursor = (f.cursor or 0) + 1
        end
      elseif Input:wasPressed("left") then
        local col = (f.cursor or 0) % cols
        if col > 0 then f.cursor = (f.cursor or 0) - 1 end
      elseif Input:wasPressed("down") then
        local nxt = (f.cursor or 0) + cols
        if nxt < n then f.cursor = nxt end
      elseif Input:wasPressed("up") then
        local prev = (f.cursor or 0) - cols
        if prev >= 0 then f.cursor = prev end
      elseif Input:wasPressed("a") then
        self:answerScriptChoice(f.cursor or 0)
      elseif Input:wasPressed("b") then
        if not f.ignoreB then
          self:answerScriptChoice(Game3.MULTI_B_PRESSED)
        end
      end
      return
    end
    local wrap = n > 3
    if Input:wasPressed("down") then
      local next = (f.cursor or 0) + 1
      if next >= n then
        if wrap then f.cursor = 0 else f.cursor = n - 1 end
      else
        f.cursor = next
      end
    elseif Input:wasPressed("up") then
      local prev = (f.cursor or 0) - 1
      if prev < 0 then
        if wrap then f.cursor = n - 1 else f.cursor = 0 end
      else
        f.cursor = prev
      end
    elseif Input:wasPressed("a") then
      self:answerScriptChoice(f.cursor or 0)
    elseif Input:wasPressed("b") then
      if not f.ignoreB then
        self:answerScriptChoice(Game3.MULTI_B_PRESSED)
      end
    end
    return
  end
  if f.kind == "easy_chat" then
    self:stepEasyChat(f)
    return
  end
  if f.kind == "daycare_egg" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      if (f.cursor or 0) == 0 then
        local _, msg = self:giveDaycareEgg()
        self.field = { kind = "talk", text = msg }
      else
        local _, msg = self:rejectDaycareEgg()
        self.field = { kind = "talk", text = msg }
      end
    elseif Input:wasPressed("b") then
      local _, msg = self:rejectDaycareEgg()
      self.field = { kind = "talk", text = msg }
    end
    return
  end
  if f.kind == "secret_base_move" then
    if Input:wasPressed("down") or Input:wasPressed("up") then
      f.cursor = 1 - (f.cursor or 0)
    elseif Input:wasPressed("a") then
      if (f.cursor or 0) == 0 then
        self:createSecretBase(f.spot)
        self:enterSecretBase()
        self.field = { kind = "talk", text = "Used SECRET POWER!" }
      else
        self:closeField()
      end
    elseif Input:wasPressed("b") then
      self:closeField()
    end
    return
  end
  if f.kind == "contest_cat" then
    local n = #Game3.CONTEST_CAT_NAMES
    if Input:wasPressed("b") then
      self:closeField()
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      self.field = {
        kind = "contest_mon",
        cursor = 0,
        category = f.cursor or 0,
      }
    end
    return
  end
  if f.kind == "contest_mon" then
    local n = #(self.party or {})
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      if f.scripted then
        self.field = nil
        self:endScriptWait()
      else
        self.field = { kind = "contest_cat", cursor = f.category or 0 }
      end
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      local idx = (f.cursor or 0) + 1
      if f.scripted then
        self.contestMonIndex = idx
        self:setScriptVar(0x8004, f.cursor or 0)
        self.field = nil
        self:endScriptWait()
      else
        local mon = self.party and self.party[idx]
        local ok, msg = self:canEnterContest(mon)
        if not ok then
          self.field = { kind = "talk", text = msg }
        else
          local ranks = self:contestRanksFor(mon, f.category or 0)
          if #ranks <= 1 then
            local started, why = self:beginContest(idx, f.category or 0, 0)
            if not started then
              self.field = { kind = "talk", text = why }
            end
          else
            self.field = {
              kind = "contest_rank",
              cursor = 0,
              category = f.category or 0,
              monIndex = idx,
              ranks = ranks,
            }
          end
        end
      end
    end
    return
  end
  if f.kind == "contest_rank" then
    local ranks = f.ranks or { 0 }
    local n = #ranks
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      self.field = {
        kind = "contest_mon",
        cursor = (f.monIndex or 1) - 1,
        category = f.category or 0,
      }
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      local rank = ranks[(f.cursor or 0) + 1] or 0
      local started, why = self:beginContest(f.monIndex or 1, f.category or 0, rank)
      if not started then
        self.field = { kind = "talk", text = why }
      end
    end
    return
  end
  if f.kind == "contest_move" then
    local c = self.contest
    local mon = c and self.party and self.party[c.monIndex]
    local moves = mon and mon.moves or {}
    local n = #moves
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      -- Appeals cannot be cancelled mid-contest.
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      self:applyContestTurn((f.cursor or 0) + 1)
    end
    return
  end
  if f.kind == "contest_results" then
    if Input:wasPressed("a") or Input:wasPressed("b") then
      if f.scripted then
        self.field = nil
        self:endScriptWait()
      else
        self.field = { kind = "talk", text = self:contestResultsText() }
      end
    end
    return
  end
  if f.kind == "daycare" then
    local labels = { "LEAVE", "TAKE" }
    local n = #labels
    if Input:wasPressed("b") then
      self:closeField()
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      if (f.cursor or 0) == 0 then
        self.field = { kind = "daycare_send", cursor = 0 }
      else
        self.field = { kind = "daycare_take", cursor = 0 }
      end
    end
    return
  end
  if f.kind == "npc_trade" then
    local n = #(self.party or {})
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      self:setScriptVar(0x8004, Game3.PARTY_MENU_CANCEL)
      self.field = nil
      self:endScriptWait()
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      self:setScriptVar(0x8004, f.cursor or 0)
      self.field = nil
      self:endScriptWait()
    end
    return
  end
  if f.kind == "daycare_send" then
    local n = #(self.party or {})
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      if f.scripted then
        self.field = nil
        self:endScriptWait()
      else
        self:closeField()
      end
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      if f.scripted then
        self:setScriptVar(0x8004, f.cursor or 0)
        self.field = nil
        self:endScriptWait()
      else
        local _, msg = self:depositToDaycare((f.cursor or 0) + 1)
        self.field = { kind = "talk", text = msg }
      end
    end
    return
  end
  if f.kind == "daycare_take" then
    local list = self:daycareTakeRows()
    local n = #list
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      if f.scripted then
        self.field = nil
        self:endScriptWait()
      else
        self:closeField()
      end
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      local row = list[(f.cursor or 0) + 1]
      if row then
        if f.scripted then
          self:setScriptVar(0x8004, (row.slot or 1) - 1)
          self.field = nil
          self:endScriptWait()
        else
          local _, msg = self:takeFromDaycare(row.slot)
          self.field = { kind = "talk", text = msg }
        end
      end
    end
    return
  end
  if f.kind == "fly" then
    local list = f.list or {}
    local n = #list
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      self:closeField()
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      local dest = list[(f.cursor or 0) + 1]
      if dest then
        local _, msg = self:flyTo(dest)
        self.field = { kind = "talk", text = msg }
      end
    end
    return
  end
  if f.kind == "mart" then
    local n = #(f.items or {})
    if n < 1 then n = 1 end
    if Input:wasPressed("b") then
      if self._scriptPause then
        self:resumeMoveScript()
      else
        self:closeField()
      end
    elseif Input:wasPressed("down") then
      f.cursor = ((f.cursor or 0) + 1) % n
    elseif Input:wasPressed("up") then
      f.cursor = ((f.cursor or 0) - 1) % n
      if f.cursor < 0 then f.cursor = n - 1 end
    elseif Input:wasPressed("a") then
      local id = (f.items or {})[(f.cursor or 0) + 1]
      local _, msg = self:buyMartItem(id)
      f.note = msg
    end
    return
  end
  if f.kind == "dex" then
    if Input:wasPressed("b") or Input:wasPressed("start") then
      self.field = { kind = "menu", cursor = 0 }
    else
      local list = f.list or {}
      local n = #list
      if n < 1 then n = 1 end
      if Input:wasPressed("down") then
        f.cursor = ((f.cursor or 0) + 1) % n
      elseif Input:wasPressed("up") then
        f.cursor = ((f.cursor or 0) - 1) % n
        if f.cursor < 0 then f.cursor = n - 1 end
      end
    end
    return
  end
  if f.kind ~= "menu" then
    return
  end
  if Input:wasPressed("start") or Input:wasPressed("b") then
    self:closeField()
    return
  end
  local labels = self:startMenuItems()
  local n = #labels
  if n < 1 then n = 1 end
  if Input:wasPressed("up") then
    f.cursor = ((f.cursor or 0) - 1) % n
    if f.cursor < 0 then f.cursor = n - 1 end
  elseif Input:wasPressed("down") then
    f.cursor = ((f.cursor or 0) + 1) % n
  elseif Input:wasPressed("a") then
    local name = labels[(f.cursor or 0) + 1]
    if name == "POKeDEX" then
      self:openDex()
    elseif name == "POKeMON" then
      self:openParty()
    elseif name == "BAG" then
      self:openBag()
    elseif name == "POKeNAV" then
      self:openPokeNav()
    elseif name == "SAVE" then
      self:openSaveAsk()
    elseif name == "OPTION" then
      self.field = { kind = "option", cursor = 0 }
    elseif name == self:playerName() then
      self:openTrainerCard()
    else
      self:closeField()
    end
  end
end

function Game3:drawStartMenu(f)
  local labels = self:startMenuItems()
  local n = #labels
  local rowH = 14
  local boxW = 80
  local boxH = n * rowH + 10
  local boxX = Game3.SCREEN_W - boxW - 2
  local boxY = 2
  self:drawWindow(boxX, boxY, boxW, boxH)
  for i = 0, n - 1 do
    local y = boxY + 4 + i * rowH
    if i == (f.cursor or 0) then
      self:drawCursor(boxX + 4, y)
    end
    love.graphics.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(labels[i + 1], boxX + 14, y)
  end
end

function Game3:drawTrainerCard()
  local G = love.graphics
  G.setColor(0.72, 0.22, 0.32, 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  self:drawWindow(8, 8, 224, 144)
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText("TRAINER CARD", 16, 14)
  local stars = self:cardStars()
  if stars > 0 then
    local marks = ""
    for _ = 1, stars do marks = marks .. "*" end
    self:drawText(marks, 160, 14)
  end
  self:drawText("NAME", 16, 32)
  self:drawText(self:playerName(), 88, 32)
  self:drawText("IDNo.", 16, 48)
  self:drawText(self:trainerIdString(), 88, 48)
  self:drawText("MONEY", 16, 64)
  self:drawText(self:moneyString(), 88, 64)
  local y = 80
  if self:hasPokedex() then
    local seen = self:dexCounts()
    self:drawText("POKeDEX", 16, y)
    self:drawText(tostring(seen), 88, y)
    y = y + 16
  end
  self:drawText("TIME", 16, y)
  self:drawText(self:playTimeString(), 88, y)
  for i = 1, 8 do
    local col = (i - 1) % 4
    local row = math.floor((i - 1) / 4)
    local bx = 16 + col * 52
    local by = 118 + row * 16
    if self:hasBadge(i) then
      G.setColor(0.85, 0.55, 0.15, 1)
      G.rectangle("fill", bx, by, 48, 14)
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(Game3.BADGE_NAMES[i], bx + 2, by)
    else
      G.setColor(0.82, 0.78, 0.70, 1)
      G.rectangle("fill", bx, by, 48, 14)
    end
  end
end

function Game3:drawSaveAsk(f)
  local G = love.graphics
  G.setColor(0.10, 0.22, 0.45, 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  self:drawWindow(16, 8, 208, 96)
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText(self:saveMapName(), 24, 16)
  self:drawText("PLAYER", 24, 32)
  self:drawText(self:playerName(), 120, 32)
  self:drawText("BADGES", 24, 48)
  self:drawText(tostring(self:badgeCount()), 120, 48)
  local y = 64
  if self:hasPokedex() then
    local seen = self:dexCounts()
    self:drawText("POKeDEX", 24, y)
    self:drawText(tostring(seen), 120, y)
    y = y + 16
  end
  self:drawText("TIME", 24, y)
  self:drawText(self:playTimeString(), 120, y)
  self:drawWindow(16, 112, 208, 40)
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText(f and f.text or "Would you like to SAVE the game?", 24, 116)
  local cursor = f and f.cursor or 0
  local labels = { "YES", "NO" }
  for i = 0, 1 do
    local x = 48 + i * 80
    if i == cursor then self:drawCursor(x, 132) end
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(labels[i + 1], x + 12, 132)
  end
end

function Game3:drawBag(f)
  local G = love.graphics
  local pocket = (f and f.pocket) or Game3.POCKET_ITEMS
  G.setColor(0.72, 0.55, 0.22, 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  self:drawWindow(4, 4, 80, 52)
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText("BAG", 12, 10)
  self:drawText(Game3.POCKET_NAMES[pocket] or "ITEMS", 12, 28)
  self:drawWindow(88, 4, 148, 120)
  local list = self:bagSlotsIn(pocket)
  local start = f and f.cursor or 0
  if start < 0 then start = 0 end
  if #list < 1 then
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("The BAG is empty.", 96, 20)
  else
    for i = 0, 6 do
      local slot = list[start + i + 1]
      local y = 12 + i * 16
      if i == 0 then self:drawCursor(92, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      if slot then
        self:drawText(("%s  x%d"):format(
          self:itemName(slot.id), slot.count or 0), 102, y)
      end
    end
  end
  self:drawWindow(4, 128, 232, 28)
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText(self:moneyString(), 12, 136)
  if f and f.giveTo then
    self:drawText("< > pocket  A give  B back", 88, 136)
  else
    self:drawText("< > pocket  A use  B back", 88, 136)
  end
end

function Game3:drawPartySlots(f)
  local G = love.graphics
  local party = self.party or {}
  local cursor = f and f.cursor or 0
  local from = f and f.kind == "party_switch" and ((f.monIndex or 1) - 1) or nil
  local compact = f and f.compact
  local rowW = compact and 136 or 208
  for i = 0, 5 do
    local mon = party[i + 1]
    local y = 16 + i * 22
    if from ~= nil and i == from then
      G.setColor(0.85, 0.78, 0.55, 1)
      G.rectangle("fill", 16, y - 2, rowW, 20)
    end
    if i == cursor then self:drawCursor(18, y) end
    G.setColor(0.10, 0.10, 0.12, 1)
    if mon then
      self:drawText(mon.name or "POKeMON", 28, y)
      if compact then
        self:drawText(("%d/%d"):format(mon.hp or 0, mon.maxHp or 0), 100, y)
      else
        self:drawText(("Lv%d"):format(mon.level or 1), 120, y)
        self:drawHpBar(148, y + 6, 48, mon.hp, mon.maxHp)
        self:drawText(("%d/%d"):format(mon.hp or 0, mon.maxHp or 0), 200, y)
      end
    else
      G.setColor(0.55, 0.55, 0.58, 1)
      self:drawText("----", 28, y)
    end
  end
end

function Game3:drawPartyScreen(f)
  local G = love.graphics
  G.setColor(0.22, 0.48, 0.38, 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  self:drawWindow(4, 4, 232, 152)
  G.setColor(0.10, 0.10, 0.12, 1)
  local title = "POKeMON"
  if f and f.kind == "party_switch" then title = "Move to where?" end
  if f and f.kind == "party_teach" then title = "Teach which?" end
  self:drawText(title, 16, 10)
  self:drawPartySlots(f)
end

function Game3:drawPartyAction(f)
  self:drawPartyScreen({
    kind = "party",
    cursor = (f and f.monIndex or 1) - 1,
    compact = true,
  })
  local actions = (f and f.actions) or { "CANCEL" }
  local n = #actions
  local boxH = n * 14 + 12
  if boxH < 40 then boxH = 40 end
  local boxW = 88
  local boxX = Game3.SCREEN_W - boxW - 4
  local boxY = 20
  self:drawWindow(boxX, boxY, boxW, boxH)
  for i = 0, n - 1 do
    local y = boxY + 6 + i * 14
    if i == (f and f.cursor or 0) then self:drawCursor(boxX + 4, y) end
    love.graphics.setColor(0.10, 0.10, 0.12, 1)
    self:drawText(actions[i + 1], boxX + 14, y)
  end
end

function Game3:drawPartySummary(f)
  local G = love.graphics
  local mon = (self.party or {})[(f and f.monIndex) or 1]
  local page = (f and f.page) or 0
  G.setColor(0.22, 0.38, 0.62, 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  self:drawWindow(8, 8, 224, 144)
  if not mon then return end
  G.setColor(0.10, 0.10, 0.12, 1)
  local titles = { "INFO", "SKILLS", "MOVES" }
  self:drawText(mon.name or "POKeMON", 16, 14)
  self:drawText(("Lv%d"):format(mon.level or 1), 120, 14)
  self:drawText(titles[page + 1] or "INFO", 176, 14)
  if page == 0 then
    self:drawText("OT", 16, 36)
    self:drawText(self:playerName(), 88, 36)
    self:drawText("IDNo.", 16, 52)
    self:drawText(self:trainerIdString(), 88, 52)
    self:drawText("NATURE", 16, 68)
    self:drawText(Game3.natureName(mon.pid), 88, 68)
    local t1 = Game3.typeName(mon.type1)
    local t2 = Game3.typeName(mon.type2)
    self:drawText("TYPE", 16, 84)
    if mon.type2 and mon.type2 ~= mon.type1 then
      self:drawText(t1 .. "/" .. t2, 88, 84)
    else
      self:drawText(t1, 88, 84)
    end
    self:drawText("EXP", 16, 100)
    self:drawText(tostring(mon.exp or 0), 88, 100)
    self:drawText("ITEM", 16, 116)
    if mon.item then
      self:drawText(self:itemName(mon.item), 88, 116)
    else
      self:drawText("NONE", 88, 116)
    end
  elseif page == 1 then
    local rows = {
      { "HP", ("%d/%d"):format(mon.hp or 0, mon.maxHp or 0) },
      { "ATTACK", tostring(mon.atk or 0) },
      { "DEFENSE", tostring(mon.def or 0) },
      { "SP. ATK", tostring(mon.spa or 0) },
      { "SP. DEF", tostring(mon.spd or 0) },
      { "SPEED", tostring(mon.spe or 0) },
    }
    for i = 1, #rows do
      local y = 32 + (i - 1) * 14
      self:drawText(rows[i][1], 16, y)
      self:drawText(rows[i][2], 120, y)
    end
    self:drawText("ABILITY", 16, 122)
    self:drawText(Game3.abilityName(mon.ability), 88, 122)
  else
    local moves = mon.moves or {}
    for i = 1, 4 do
      local mv = moves[i]
      local y = 36 + (i - 1) * 24
      if mv then
        self:drawText(mv.name or "MOVE", 16, y)
        self:drawText(Game3.typeName(mv.type), 120, y)
        self:drawText(("%d/%d"):format(mv.pp or 0, mv.maxPp or 0), 176, y)
      else
        G.setColor(0.55, 0.55, 0.58, 1)
        self:drawText("-", 16, y)
        G.setColor(0.10, 0.10, 0.12, 1)
      end
    end
  end
  G.setColor(0.10, 0.10, 0.12, 1)
  self:drawText("< > pages  A/B back", 16, 138)
end

function Game3:drawFieldOverlay()
  local G = love.graphics
  local f = self.field
  if not f or f.kind == "move" or f.kind == "delay" or f.kind == "wait" then return end
  if f.kind == "trainer_approach" then
    if f.stage == "trans" then
      local t = 1 - ((f.wait or 0) / 0.35)
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      G.setColor(1, 1, 1, t * 0.85)
      G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
      local band = math.floor(t * 10)
      for i = 0, band do
        G.setColor(0, 0, 0, 1)
        G.rectangle("fill", 0, i * 16, Game3.SCREEN_W, 8)
        G.rectangle("fill", 0, Game3.SCREEN_H - 8 - i * 16, Game3.SCREEN_W, 8)
      end
    end
    return
  end
  if f.kind == "menu" then
    self:drawStartMenu(f)
    return
  end
  if f.kind == "option" then
    self:drawOptionMenu(f)
    return
  end
  if f.kind == "trainer_card" then
    self:drawTrainerCard()
    return
  end
  if f.kind == "save_ask" then
    self:drawSaveAsk(f)
    return
  end
  if f.kind == "bag" then
    self:drawBag(f)
    return
  end
  if f.kind == "party" or f.kind == "party_switch" or f.kind == "party_teach" then
    self:drawPartyScreen(f)
    return
  end
  if f.kind == "party_forget" then
    local mon = (self.party or {})[(f.monIndex or 1)]
    local moves = mon and mon.moves or {}
    local actions = {}
    for i = 1, #moves do
      actions[i] = (moves[i] and moves[i].name) or "MOVE"
    end
    actions[#actions + 1] = "CANCEL"
    self:drawPartyAction({
      monIndex = f.monIndex, cursor = f.cursor, actions = actions,
    })
    return
  end
  if f.kind == "learn_forget" then
    local mon = (self.learnMove and self.learnMove.mon) or f.mon
    local moves = mon and mon.moves or {}
    local actions = {}
    for i = 1, #moves do
      actions[i] = (moves[i] and moves[i].name) or "MOVE"
    end
    actions[#actions + 1] = "CANCEL"
    local index = 1
    local party = self.party or {}
    for i = 1, #party do
      if party[i] == mon then index = i break end
    end
    self:drawPartyAction({
      monIndex = index, cursor = f.cursor, actions = actions,
    })
    return
  end
  if f.kind == "party_action" or f.kind == "party_item" then
    self:drawPartyAction(f)
    return
  end
  if f.kind == "party_summary" then
    self:drawPartySummary(f)
    return
  end
  if f.kind == "fishing" then
    if (f.step or 0) < Game3.FISH_START_ROUND then return end
    self:drawWindow(0, 112, Game3.SCREEN_W, 48)
    self:drawDialogue(f, 10, 118)
    return
  end
  self:drawWindow(0, 112, Game3.SCREEN_W, 48)
  if f.kind == "dex" then
    local list = f.list or {}
    G.setColor(0.10, 0.10, 0.12, 1)
    if #list < 1 then
        self:drawText("No POKeMON seen yet.", 10, 128)
    else
      local start = f.cursor or 0
      for i = 0, 1 do
        local row = list[start + i + 1]
        local y = 118 + i * 14
        if i == 0 then
          G.setColor(0.90, 0.28, 0.22, 1)
          self:drawCursor(8, y)
        end
        G.setColor(0.10, 0.10, 0.12, 1)
        if row then
          local mark = row.caught and "GOT" or "SEEN"
          self:drawText(("%03d %s  %s"):format(row.id, row.name, mark), 18, y)
        end
      end
    end
        self:drawText("B back", 180, 148)
  elseif f.kind == "daycare" then
    local labels = { "LEAVE", "TAKE" }
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("DAY CARE", 8, 116)
    for i = 1, #labels do
      local y = 128 + (i - 1) * 12
      if (i - 1) == (f.cursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(labels[i], 18, y)
    end
  elseif f.kind == "daycare_send" or f.kind == "npc_trade" then
    local party = self.party or {}
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(f.kind == "npc_trade" and "Which POKeMON?" or "Leave which?",
          8, 116)
    for i = 0, 1 do
      local mon = party[start + i + 1]
      local y = 128 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if mon then
        self:drawText(("%s  Lv%d"):format(mon.name, mon.level or 1), 18, y)
      end
    end
  elseif f.kind == "daycare_take" then
    local list = self:daycareTakeRows()
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Take which?", 8, 116)
    for i = 0, 1 do
      local row = list[start + i + 1]
      local y = 128 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if row then
        self:drawText(("%s  Lv%d->$%d"):format(row.name, row.toLevel, row.cost), 18, y)
      end
    end
  elseif f.kind == "fly" then
    local list = f.list or {}
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("FLY where?", 8, 116)
    if #list < 1 then
        self:drawText("No towns visited yet.", 18, 128)
    else
      for i = 0, 1 do
        local dest = list[start + i + 1]
        local y = 128 + i * 12
        if i == 0 then
          G.setColor(0.90, 0.28, 0.22, 1)
          self:drawCursor(8, y)
        end
        G.setColor(0.10, 0.10, 0.12, 1)
        if dest then
          self:drawText(dest.name or dest.mapId, 18, y)
        end
      end
    end
  elseif f.kind == "mart" then
    local items = f.items or {}
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(("$%d"):format(self.money or 0), 160, 116)
    for i = 0, 1 do
      local id = items[start + i + 1]
      local y = 122 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if id then
        self:drawText(("%s  $%d"):format(self:itemName(id), self:itemPrice(id)), 18, y)
      end
    end
        self:drawText(f.note or "A buy  B leave", 8, 148)
  elseif f.kind == "pc" then
    G.setColor(0.10, 0.10, 0.12, 1)
    local mode = f.mode or "root"
    if mode == "root" then
      local labels = { "WITHDRAW", "DEPOSIT", "SEE YA" }
      for i = 0, 2 do
        local y = 118 + i * 10
        if i == (f.cursor or 0) then
          G.setColor(0.90, 0.28, 0.22, 1)
          self:drawCursor(8, y)
        end
        G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(labels[i + 1], 18, y)
      end
    else
        self:drawText(("BOX %d"):format(f.box or 1), 160, 116)
      local list
      if mode == "box" then
        self:ensurePc()
        list = self.pc[f.box] or {}
      else
        list = self.party or {}
      end
      local start = f.cursor or 0
      if #list < 1 then
        self:drawText(mode == "box" and "The BOX is empty." or "The party is empty.", 18, 128)
      else
        for i = 0, 1 do
          local mon = list[start + i + 1]
          local y = 126 + i * 10
          if i == 0 then
            G.setColor(0.90, 0.28, 0.22, 1)
            self:drawCursor(8, y)
          end
          G.setColor(0.10, 0.10, 0.12, 1)
          if mon then
            self:drawText(("%s  Lv%d"):format(mon.name, mon.level or 1), 18, y)
          end
        end
      end
        self:drawText(f.note or "A pick  B back", 8, 148)
    end
  elseif f.kind == "gender" then
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Are you a boy or a girl?", 10, 116)
    local labels = { "BOY", "GIRL" }
    for i = 0, 1 do
      local y = 130 + i * 10
      if i == (f.cursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(labels[i + 1], 18, y)
    end
  elseif f.kind == "nickname" then
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("NICKNAME?", 10, 116)
    self:drawText(f.name or "", 10, 128)
    local keys = f.keys or Game3.nameKeys()
    local key = keys[(f.cursor or 0) + 1] or ""
    self:drawText(key, 10, 140)
    self:drawText("A pick  B del  START end", 8, 148)
  elseif f.kind == "starter" then
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Choose a POKeMON!", 10, 116)
    for i = 1, #Game3.STARTERS do
      local y = 126 + (i - 1) * 10
      if (i - 1) == (f.cursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(self:speciesName(Game3.STARTERS[i]), 18, y)
    end
  elseif f.kind == "starter_yesno" then
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(f.text or "", 10, 116)
    local labels = { "YES", "NO" }
    for i = 0, 1 do
      local y = 130 + i * 10
      if i == (f.cursor or 0) then
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(labels[i + 1], 18, y)
    end
  elseif f.kind == "script_yesno"
      or f.kind == "learn_yesno" or f.kind == "learn_stop" then
    self:drawDialogue(f, 10, 118)
    self:drawYesNoWindow(f.boxX, f.boxY, f.cursor or 0)
  elseif f.kind == "script_choice" then
    if f.text then self:drawDialogue(f, 10, 118) end
    self:drawMenuListWindow(f.boxX, f.boxY, f.labels, f.cursor, f.perRow)
  elseif f.kind == "easy_chat" then
    G.setColor(0.10, 0.10, 0.12, 1)
    if f.text then self:drawText(f.text, 10, 100) end
    local labels = f.labels or {}
    local cur = f.cursor or 0
    local start = 0
    if #labels > 4 then
      start = math.max(0, math.min(cur, #labels - 4))
    end
    for i = 0, math.min(3, #labels - 1) do
      local idx = start + i
      local y = 116 + i * 10
      if idx == cur then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(labels[idx + 1] or "", 18, y)
    end
  elseif f.kind == "daycare_egg" or f.kind == "secret_base_move" then
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(f.text or (f.kind == "secret_base_move"
      and "Move your SECRET BASE here?" or "Want the EGG?"), 10, 116)
    local labels = { "YES", "NO" }
    for i = 0, 1 do
      local y = 130 + i * 10
      if i == (f.cursor or 0) then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(labels[i + 1], 18, y)
    end
  elseif f.kind == "contest_cat" then
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Which CONTEST?", 8, 116)
    local names = Game3.CONTEST_CAT_NAMES
    local start = f.cursor or 0
    for i = 0, 1 do
      local y = 128 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      local name = names[start + i + 1]
      if name then self:drawText(name, 18, y) end
    end
  elseif f.kind == "contest_mon" then
    local party = self.party or {}
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Enter which?", 8, 116)
    for i = 0, 1 do
      local mon = party[start + i + 1]
      local y = 128 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if mon then
        self:drawText(("%s  Lv%d"):format(mon.name, mon.level or 1), 18, y)
      end
    end
  elseif f.kind == "contest_rank" then
    local ranks = f.ranks or { 0 }
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText("Which rank?", 8, 116)
    for i = 0, 1 do
      local rank = ranks[start + i + 1]
      local y = 128 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if rank then
        self:drawText(Game3.CONTEST_RANK_NAMES[rank + 1] or "NORMAL", 18, y)
      end
    end
  elseif f.kind == "contest_move" then
    local c = self.contest or {}
    local mon = self.party and self.party[c.monIndex]
    local moves = mon and mon.moves or {}
    local start = f.cursor or 0
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(("Appeal %d/%d  %d"):format(
      (c.turn or 0) + 1, Game3.CONTEST_TURNS, c.player or 0), 8, 116)
    for i = 0, 1 do
      local move = moves[start + i + 1]
      local y = 128 + i * 12
      if i == 0 then
        G.setColor(0.90, 0.28, 0.22, 1)
        self:drawCursor(8, y)
      end
      G.setColor(0.10, 0.10, 0.12, 1)
      if move then self:drawText(move.name or "MOVE", 18, y) end
    end
  elseif f.kind == "contest_results" then
    G.setColor(0.10, 0.10, 0.12, 1)
        self:drawText(self:contestResultsText(), 8, 128)
        self:drawText("A continue", 160, 148)
  else
    self:drawDialogue(f, 10, 118)
  end
end

function Game3:update(dt)
  Input:reconcile()
  Input:step()
  if self.waitingCry and not self:cryPlaying() then
    self.waitingCry = nil
    self:endScriptWait()
  end
  if self.phase == "boot" then
    self:stepBoot(dt)
    return
  end
  if self.phase == "play" and self.field then
    self:stepField()
  elseif Input:wasPressed("start") and self.phase == "play" then
    self.field = { kind = "menu", cursor = 0 }
  elseif Input:wasPressed("select") and self.phase == "play"
      and (self.walkCooldown or 0) <= 0 then
    self:useRegisteredItem()
  elseif Input:wasPressed("a") and self.phase == "play" then
    self:tryTalk()
  elseif Input:wasPressed("b") and self.phase == "roster" then
    self.phase = "boot"
    self:resetBoot()
  elseif Input:wasPressed("up") then
    self:moveScroll(-1)
  elseif Input:wasPressed("down") then
    self:moveScroll(1)
  end
  self:walkHeld(dt)
end

local function letterbox(w, h)
  local scale = math.max(1, math.floor(math.min(w / Game3.SCREEN_W, h / Game3.SCREEN_H)))
  local ox = math.floor((w - Game3.SCREEN_W * scale) / 2)
  local oy = math.floor((h - Game3.SCREEN_H * scale) / 2)
  return scale, ox, oy
end

function Game3:drawFallbackMap()
  local G = love.graphics
  local map = self.map
  local x0, y0, x1, y1 = self:visibleRange()
  if not x0 then return end
  for y = y0, y1 do
    for x = x0, x1 do
      if Game3.walkable(map, x, y) then
        G.setColor(0.45, 0.72, 0.38, 1)
      else
        G.setColor(0.22, 0.28, 0.22, 1)
      end
      G.rectangle("fill", x * Game3.TILE, y * Game3.TILE,
        Game3.TILE, Game3.TILE)
    end
  end
end

function Game3:visibleRange(map, originX, originY)
  map = map or self.map
  originX, originY = originX or 0, originY or 0
  local w, h = map.width or 0, map.height or 0
  local x0 = math.floor(self.camX / Game3.TILE) - originX
  local y0 = math.floor(self.camY / Game3.TILE) - originY
  local x1 = math.floor((self.camX + Game3.SCREEN_W) / Game3.TILE) - originX
  local y1 = math.floor((self.camY + Game3.SCREEN_H) / Game3.TILE) - originY
  x0 = math.max(0, x0)
  y0 = math.max(0, y0)
  x1 = math.min(w - 1, x1)
  y1 = math.min(h - 1, y1)
  if w < 1 or h < 1 or x1 < x0 or y1 < y0 then return nil end
  return x0, y0, x1, y1
end

local function npcKey(map)
  return map and (map.id or map)
end

function Game3:npcsFor(map)
  map = map or self.map
  if not map then return nil end
  local byMap = self.npcByMap
  if not byMap then return nil end
  return byMap[npcKey(map)]
end

function Game3:resetNpcs(map)
  map = map or self.map
  if not map then return end
  if not self.npcByMap then self.npcByMap = {} end
  local list = {}
  local objects = map.objects or {}
  for i = 1, #objects do
    local o = objects[i]
    if o then
      local flagged = o.flagId and o.flagId ~= 0
        and self.flags and self.flags[o.flagId]
      -- TrySpawnObjectEvent skips any template whose flag is set. Beaten
      -- route trainers still stand because their defeat bit is 0x500+id,
      -- not ObjectEventTemplate.flagId. FLAG_HIDE_* (0x2BC..) on a trainer
      -- is a story spawn, so those stay off the map until a script clears.
      local fid = o.flagId or 0
      local storyHide = fid >= Game3.FLAG_HIDE_BIRCH_STARTERS_BAG
        and fid < Game3.TRAINER_FLAG_START
      local hidden = flagged and ((o.trainerType or 0) == 0 or storyHide)
      local bagGone = (o.graphicsId or 0) == Game3.GFX_BIRCHS_BAG
        and self.flags and (self.flags[Game3.FLAG_HIDE_BIRCH_STARTERS_BAG]
          or self.flags[Game3.FLAG_SYS_POKEMON_GET])
      if not hidden and not bagGone then
        list[#list + 1] = self:npcFromTemplate(o, i)
      end
    end
  end
  self.npcByMap[npcKey(map)] = list
end

function Game3:npcAt(map, x, y)
  local npcs = self:npcsFor(map)
  if npcs then
    for i = 1, #npcs do
      local n = npcs[i]
      if n and not n.hidden and n.x == x and n.y == y then
        if n.invisible and n.movementType == Game3.MOVEMENT_TYPE_INVISIBLE then
          return nil
        end
        return n
      end
    end
    return nil
  end
  return Game3.objectAt(map, x, y)
end

function Game3:npcInRange(npc, x, y)
  local rx, ry = npc.rangeX or 0, npc.rangeY or 0
  if Game3.wanderDirs(npc.movementType) ~= nil then
    if rx < 1 then rx = 1 end
    if ry < 1 then ry = 1 end
  end
  return math.abs(x - npc.homeX) <= rx and math.abs(y - npc.homeY) <= ry
end

function Game3:npcVisual(npc)
  local x, y = npc.x, npc.y
  if (npc.cooldown or 0) > 0 then
    local dur = npc.walkDuration or Game3.WALK_PERIOD
    if dur <= 0 then dur = Game3.WALK_PERIOD end
    local t = 1 - npc.cooldown / dur
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    x = npc.fromX + (npc.x - npc.fromX) * t
    y = npc.fromY + (npc.y - npc.fromY) * t
  end
  return x, y
end

local function roll(n)
  n = n or 1
  if love and love.math and love.math.random then
    return love.math.random(n)
  end
  return math.random(n)
end

function Game3:tryNpcWalk(npc, map, dx, dy)
  if not (npc and map) then return false end
  if npc.talkLock or npc.invisible then return false end
  if not npc.facingLocked then
    npc.facing = Game3.facingFromDelta(dx, dy)
  end
  local nx, ny = npc.x + dx, npc.y + dy
  if not Game3.walkable(map, nx, ny) then return false end
  if Game3.warpAt(map, nx, ny) then return false end
  if nx == self.playerX and ny == self.playerY then return false end
  if self:npcAt(map, nx, ny) then return false end
  if not self:npcInRange(npc, nx, ny) then return false end
  npc.fromX, npc.fromY = npc.x, npc.y
  npc.x, npc.y = nx, ny
  npc.walkDuration = Game3.WALK_PERIOD
  npc.cooldown = Game3.WALK_PERIOD
  self:beginGrassRustle(nx, ny)
  return true
end

function Game3:stepNpcSequence(npc, map)
  local seq = Game3.WALK_SEQUENCES[npc.movementType]
  if not seq then return end
  npc.seqI = npc.seqI or 0
  for _ = 1, 4 do
    local dir = seq[(npc.seqI % 4) + 1]
    local dx, dy = Game3.deltaFromFacing(dir)
    if self:tryNpcWalk(npc, map, dx, dy) then
      return
    end
    npc.seqI = npc.seqI + 1
  end
  npc.wait = 0.4
end

function Game3:stepNpcs(dt)
  local map = self.map
  local npcs = self:npcsFor(map)
  if not npcs then return end
  for i = 1, #npcs do
    local npc = npcs[i]
    if npc and not npc.hidden and not npc.invisible then
      if (npc.cooldown or 0) > 0 then
        npc.cooldown = npc.cooldown - dt
      elseif npc.talkLock then
        -- Frozen for dialogue: keep facing the player.
      else
        local mode = Game3.wanderDirs(npc.movementType)
        if mode == "place" then
          npc.placeT = (npc.placeT or 0) + dt
        else
          npc.wait = (npc.wait or 0) - dt
          if npc.wait <= 0 then
            if mode == "seq" then
              self:stepNpcSequence(npc, map)
              npc.wait = 0
            else
              npc.wait = 0.5 + roll(12) / 10
              if mode == "look" then
                if not npc.facingLocked then
                  local dirs = { "north", "south", "west", "east" }
                  npc.facing = dirs[roll(4)]
                end
              elseif type(mode) == "table" then
                local dir = mode[roll(#mode)]
                local dx, dy = Game3.deltaFromFacing(dir)
                self:tryNpcWalk(npc, map, dx, dy)
              end
            end
          end
        end
      end
    end
  end
end

function Game3:spriteImage(graphicsId)
  local spec = Game3.spriteSpec(self.data.sprites, graphicsId)
  if not spec then return nil end
  local cached = self.spriteCache[graphicsId]
  if cached ~= nil then return cached or nil end
  local img = self:grabImage(spec.path)
  self.spriteCache[graphicsId] = img or false
  return img
end

function Game3:owQuad(spec, image, frame)
  local w, h = spec.width or Game3.TILE, spec.height or Game3.TILE
  local sw, sh = w, h
  if image and image.getDimensions then
    sw, sh = image:getDimensions()
  end
  frame = frame or 0
  local key = "ow:" .. (spec.id or spec.path or "") .. ":" .. frame .. ":" .. sw
  local q = self.quads[key]
  if not q then
    q = love.graphics.newQuad(frame * w, 0, w, h, sw, sh)
    self.quads[key] = q
  end
  return q
end

function Game3:drawOwSprite(graphicsId, tileX, tileY, facing, moving, t, lift)
  local spec = Game3.spriteSpec(self.data.sprites, graphicsId)
  local img = spec and self:spriteImage(graphicsId)
  if not img then return false end
  local pose = Game3.poseFor(spec, facing, moving, t)
  local px, py = Game3.spriteDrawPos(tileX, tileY, spec.width, spec.height, lift)
  local flip = pose.flip and true or false
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local quad = self:owQuad(spec, img, pose.frame or 0)
  if flip then
    G.draw(img, quad, px + (spec.width or Game3.TILE), py, 0, -1, 1)
  else
    G.draw(img, quad, px, py)
  end
  return true
end

function Game3:tileBatch(image)
  if not image or not love.graphics.newSpriteBatch then return nil end
  self.tileBatches = self.tileBatches or {}
  local batch = self.tileBatches[image]
  if not batch then
    local ok, made = pcall(love.graphics.newSpriteBatch, image, 1024, "stream")
    if not ok or not made then return nil end
    batch = made
    self.tileBatches[image] = batch
  end
  return batch
end

function Game3:blitMetatile(image, mid, px, py, mode, batch)
  local G = love.graphics
  if not mode or mode == "full" then
    local quad = self:quadFor(mid, image)
    if batch then
      batch:add(quad, px, py)
    else
      G.draw(image, quad, px, py)
    end
    return
  end
  local i0, i1 = 0, 1
  if mode == "bottom8" then i0, i1 = 2, 3 end
  for i = i0, i1 do
    local q = self:quadFor8(mid, i, image)
    local ox = (i % 2) * 8
    local oy = math.floor(i / 2) * 8
    if batch then
      batch:add(q, px + ox, py + oy)
    else
      G.draw(image, q, px + ox, py + oy)
    end
  end
end

function Game3:drawLayer(image, map, x0, y0, x1, y1, originX, originY, topPass)
  if not image or not map or x0 == nil then return end
  originX, originY = originX or 0, originY or 0
  local G = love.graphics
  local w = map.width or 0
  local h = map.height or 0
  local batch = self:tileBatch(image)
  if batch and batch.clear then batch:clear() end
  G.setColor(1, 1, 1, 1)
  for y = y0, y1 do
    for x = x0, x1 do
      if x >= 0 and y >= 0 and x < w and y < h then
        local mode = "full"
        if topPass then
          mode = Game3.metatileTopPassMode(
            self:layerTypeAt(map, x, y), topPass,
            self:topIsOverlayAt(map, x, y))
        end
        if mode ~= "skip" then
          local mid = Game3.metatileOf(map.grid[y * w + x + 1])
          local px = (originX + x) * Game3.TILE
          local py = (originY + y) * Game3.TILE
          local behavior = self:behaviorAt(map, x, y)
          self:blitMetatile(image, mid, px, py, mode, batch)
          self:drawAnimCorners(image, map, mid, px, py, topPass, batch, behavior, mode)
        end
      end
    end
  end
  if batch then G.draw(batch) end
end

function Game3:drawConnections(which, topPass)
  local map = self.map
  for i = 1, #(map.connections or {}) do
    local c = map.connections[i]
    local dest = c and self:lookupMap(c.mapGroup, c.mapNum)
    if dest and dest.grid then
      local ox, oy = Game3.neighborOrigin(c, map, dest)
      if ox then
        local x0, y0, x1, y1 = self:visibleRange(dest, ox, oy)
        if x0 then
          local bottom, top = self:layersFor(dest.tileset)
          local image = which == "top" and top or bottom
          self:drawLayer(image, dest, x0, y0, x1, y1, ox, oy, topPass)
        end
      end
    end
  end
end

function Game3.drawOrderLess(a, b)
  local sa, sb = a.sub, b.sub
  if sa or sb then
    sa = sa or Game3.DEFAULT_OBJ_SUBPRIORITY
    sb = sb or Game3.DEFAULT_OBJ_SUBPRIORITY
    if sa ~= sb then return sa > sb end
  end
  if a.y ~= b.y then return a.y < b.y end
  if a.x ~= b.x then return a.x < b.x end
  return false
end

function Game3:drawOneObject(o, npcs)
  local G = love.graphics
  local gid = self:resolveGraphicsId(o.graphicsId or 0)
  local spec = Game3.spriteSpec(self.data.sprites, gid)
  local w = spec and spec.width or Game3.TILE
  local h = spec and spec.height or Game3.TILE
  local vx, vy = o.x, o.y
  local moving, t = false, 1
  if npcs then
    vx, vy = self:npcVisual(o)
    moving = ((o.cooldown or 0) > 0 or Game3.wanderDirs(o.movementType) == "place")
      and not o.lockAnim
    if moving and (o.cooldown or 0) > 0 then
      local dur = o.walkDuration or Game3.WALK_PERIOD
      if dur <= 0 then dur = Game3.WALK_PERIOD end
      t = 1 - o.cooldown / dur
    elseif moving then
      t = (o.placeT or 0) % 0.5 / 0.5
    end
  end
  local lift = o.levitate or 0
  local px, py = Game3.spriteDrawPos(vx, vy, w, h, lift)
  local camX, camY = self.camX, self.camY
  if px + w < camX or px > camX + Game3.SCREEN_W
      or py + h < camY or py > camY + Game3.SCREEN_H then
    return
  end
  local facing = o.facing or Game3.facingFromMovementType(o.movementType)
  if not self:drawOwSprite(gid, vx, vy, facing, moving, t, lift) then
    G.setColor(0.12, 0.10, 0.16, 1)
    G.rectangle("fill", o.x * Game3.TILE + 3, o.y * Game3.TILE + 3 - lift, 10, 13)
    G.setColor(
      0.25 + (gid % 5) * 0.12,
      0.35 + (math.floor(gid / 5) % 5) * 0.10,
      0.70 - (gid % 4) * 0.08,
      1)
    G.rectangle("fill", o.x * Game3.TILE + 4, o.y * Game3.TILE + 4 - lift, 8, 11)
  end
  self:drawEmoteAt(vx, vy, o.emote, lift)
end

function Game3:beginGrassRustle(x, y)
  if not Game3.isLandGrass(self:behaviorAt(self.map, x, y)) then return end
  x, y = math.floor(x or 0), math.floor(y or 0)
  self.grassRustle = self.grassRustle or {}
  local list = self.grassRustle
  for i = 1, #list do
    if list[i].x == x and list[i].y == y then
      list[i].t = Game3.GRASS_RUSTLE
      return
    end
  end
  list[#list + 1] = { x = x, y = y, t = Game3.GRASS_RUSTLE }
end

function Game3:stepGrassRustle(dt)
  local list = self.grassRustle
  if not list then return end
  local i = 1
  while i <= #list do
    list[i].t = (list[i].t or 0) - (dt or 0)
    if list[i].t <= 0 then
      list[i] = list[#list]
      list[#list] = nil
    else
      i = i + 1
    end
  end
end

function Game3:grassIsRustling(x, y)
  local list = self.grassRustle
  if not list then return false end
  x, y = math.floor(x or 0), math.floor(y or 0)
  for i = 1, #list do
    if list[i].x == x and list[i].y == y then return true end
  end
  return false
end

-- pokeruby FLDEFF_TALL_GRASS is a transparent 16x16. The ground metatile is
-- opaque, so a full 16x16 blit covers the body of a 16x32 OW sprite (only
-- the hat in the top 16px remains). Draw the bottom 8px over the feet.
-- ROM plays this once on step-in; standing in grass is static.
function Game3:drawGrassTuftAt(map, tileX, tileY)
  map = map or self.map
  if not (map and map.grid and self.layerBottom) then return end
  tileX = math.floor(tileX or 0)
  tileY = math.floor(tileY or 0)
  if not Game3.isLandGrass(self:behaviorAt(map, tileX, tileY)) then return end
  local w, h = map.width or 0, map.height or 0
  if tileX < 0 or tileY < 0 or tileX >= w or tileY >= h then return end
  local image = self.layerBottom
  if map.tileset and map.tileset ~= (self.map and self.map.tileset) then
    image = self:layersFor(map.tileset)
  end
  if not image then return end
  local mid = Game3.metatileOf(map.grid[tileY * w + tileX + 1])
  local px = tileX * Game3.TILE
  local py = tileY * Game3.TILE
  local G = love.graphics
  local flip = self:tileAnimFlip()
  G.setColor(1, 1, 1, 1)
  for i = 2, 3 do
    local q = self:quadFor8(mid, i, image)
    local ox = (i % 2) * 8
    if flip then
      G.draw(image, q, px + ox + 8, py + 8, 0, -1, 1)
    else
      G.draw(image, q, px + ox, py + 8)
    end
  end
end

function Game3:drawActors()
  local map = self.map
  local npcs = self:npcsFor(map)
  local list = npcs
  if not list then
    list = map.objects or {}
  end
  local actors = {}
  for i = 1, #list do
    local o = list[i]
    if o and not o.hidden and not o.invisible then
      local vx, vy = o.x, o.y
      if npcs then vx, vy = self:npcVisual(o) end
      local sub = o.fixedPriority and o.objSubpriority or nil
      actors[#actors + 1] = { kind = "npc", obj = o, x = vx, y = vy, sub = sub }
    end
  end
  if not self.invisible then
    local px, py = self:visualTile()
    local sub = self.fixedPriority and self.objSubpriority or nil
    actors[#actors + 1] = { kind = "player", x = px, y = py, sub = sub }
  end
  table.sort(actors, Game3.drawOrderLess)
  for i = 1, #actors do
    local a = actors[i]
    if a.kind == "player" then
      self:drawPlayer()
      if not self.hopping and (self.levitate or 0) <= 0 then
        if self:grassIsRustling(self.playerX, self.playerY) then
          self:drawGrassTuftAt(map, self.playerX, self.playerY)
        end
        if (self.walkCooldown or 0) > 0
            and self:grassIsRustling(self.walkFromX, self.walkFromY) then
          self:drawGrassTuftAt(map, self.walkFromX, self.walkFromY)
        end
      end
    else
      self:drawOneObject(a.obj, npcs)
      if (a.obj.levitate or 0) <= 0 then
        if self:grassIsRustling(a.obj.x, a.obj.y) then
          self:drawGrassTuftAt(map, a.obj.x, a.obj.y)
        end
        if (a.obj.cooldown or 0) > 0
            and self:grassIsRustling(a.obj.fromX, a.obj.fromY) then
          self:drawGrassTuftAt(map, a.obj.fromX, a.obj.fromY)
        end
      end
    end
  end
end

function Game3:drawEmoteAt(tileX, tileY, emote, lift)
  local glyph = emote and Game3.EMOTE_GLYPH[emote]
  if not glyph then return end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
        self:drawText(glyph, tileX * Game3.TILE + 4, tileY * Game3.TILE - 10 - (lift or 0))
end

function Game3:drawPlayer()
  local gid = self:playerGraphicsId()
  local vx, vy = self:visualTile()
  local moving = (self.walkCooldown or 0) > 0 and not self.lockAnim
  local lift = self.levitate or 0
  if self.hopping then
    local t = self:walkProgress()
    lift = lift + math.floor(8 * math.sin(t * math.pi) + 0.5)
  end
  if not self:drawOwSprite(gid, vx, vy, self.facing or "south", moving, self:walkProgress(), lift) then
    local G = love.graphics
    local px = vx * Game3.TILE
    local py = vy * Game3.TILE - lift
    G.setColor(0.18, 0.12, 0.10, 1)
    G.rectangle("fill", px + 3, py + 4, 10, 12)
    G.setColor(0.93, 0.28, 0.22, 1)
    G.rectangle("fill", px + 4, py + 5, 8, 10)
    G.setColor(0.98, 0.82, 0.55, 1)
    G.rectangle("fill", px + 5, py + 3, 6, 6)
  end
  self:drawEmoteAt(vx, vy, self.emote, lift)
end

-- pokeruby SetFlashScanlineEffectWindowBoundaries: midpoint circle into
-- WIN0H (left<<8 | right). Unwritten rows stay closed (full black).
function Game3.flashScanlineWindows(centerX, centerY, radius)
  local dest = {}
  local r = math.floor(tonumber(radius) or 0)
  if r < 1 then return dest end
  centerX = math.floor(tonumber(centerX) or 0)
  centerY = math.floor(tonumber(centerY) or 0)
  local function write(y, left, right)
    if y < 0 or y >= Game3.SCREEN_H then return end
    if left < 0 then left = 0 elseif left > 255 then left = 255 end
    if right < 0 then right = 0 elseif right > 255 then right = 255 end
    dest[y] = { left, right }
  end
  local v2, v3 = r, 0
  while r >= v3 do
    write(centerY - v3, centerX - r, centerX + r)
    write(centerY + v3, centerX - r, centerX + r)
    write(centerY - r, centerX - v3, centerX + v3)
    write(centerY + r, centerX - v3, centerX + v3)
    v2 = v2 - (v3 * 2) + 1
    v3 = v3 + 1
    if v2 < 0 then
      v2 = v2 + 2 * (r - 1)
      r = r - 1
    end
  end
  return dest
end

-- pokeruby WriteFlashScanlineEffectBuffer: a hard circle at 120,80.
-- Drawn as WIN0H scanlines so a failed LÖVE stencil cannot hide the player.
function Game3:drawFlashOverlay()
  local r = self:flashRadius()
  if r < 1 then return end
  local G = love.graphics
  local cx, cy = Game3.SCREEN_W / 2, Game3.SCREEN_H / 2
  local win = Game3.flashScanlineWindows(cx, cy, r)
  G.setColor(0, 0, 0, 1)
  for y = 0, Game3.SCREEN_H - 1 do
    local row = win[y]
    local left, right = 0, 0
    if row then
      left, right = row[1], row[2]
    end
    if left > 0 then G.rectangle("fill", 0, y, left, 1) end
    if right < Game3.SCREEN_W then
      G.rectangle("fill", right, y, Game3.SCREEN_W - right, 1)
    end
  end
end

function Game3:drawPlay()
  local G = love.graphics
  local map = self.map
  if self:flashRadius() > 0 then
    G.setColor(0, 0, 0, 1)
  else
    G.setColor(0.10, 0.22, 0.38, 1)
  end
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  G.push()
  G.translate(-self.camX, -self.camY)
  local x0, y0, x1, y1 = self:visibleRange()
  if self.layerBottom then
    self:drawLayer(self.layerBottom, map, x0, y0, x1, y1, 0, 0)
    self:drawConnections("bottom")
  else
    self:drawFallbackMap()
  end
  if self.layerTop then
    self:drawLayer(self.layerTop, map, x0, y0, x1, y1, 0, 0, "covered")
    self:drawConnections("top", "covered")
  end
  self:drawActors()
  if self.layerTop then
    self:drawLayer(self.layerTop, map, x0, y0, x1, y1, 0, 0, "overlay")
    self:drawConnections("top", "overlay")
  end
  G.pop()
  self:drawFlashOverlay()
  if self:isUnderwater() then
    G.setColor(0, 0.12, 0.35, 0.28)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  end
  G.setColor(1, 1, 1, 1)
  if self.field then
    self:drawFieldOverlay()
  end
  self:drawMoneyBox()
end

function Game3:drawScene()
  local G = love.graphics
  G.setColor(0.10, 0.22, 0.38, 1)
  G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
  G.setColor(0.93, 0.93, 0.86, 1)
  local info = GameVersion.info()
  local header = self.data.header or {}
  local constants = self.data.constants or {}
  if self.phase == "battle" then
    self:drawBattle()
    return
  end
  if self.phase == "play" and self.map then
    self:drawPlay()
    return
  end
  if self.phase == "boot" then
    self:drawBoot()
    return
  end
  self:drawText("Internal species names", 16, 8)
  local rows = 10
  local start = self.scroll
  for i = 0, rows - 1 do
    local row = self.named[start + i]
    if not row then break end
    self:drawText(("%3d  %s"):format(row.id, row.name), 16, 28 + i * 12)
  end
  self:drawText("Up/Down  scroll    B  back", 16, 148)
  G.setColor(1, 1, 1, 1)
end

function Game3:ensureCanvas()
  if self.gbaCanvas then return self.gbaCanvas end
  local ok, canvas = pcall(PixelCanvas.new,
    Game3.SCREEN_W, Game3.SCREEN_H, "nearest")
  if not ok or not canvas then return nil end
  self.gbaCanvas = canvas
  return canvas
end

function Game3:draw()
  GameViewport.begin(3)
  GameViewport.setTarget()
  local G = love.graphics
  local w, h = GameViewport.dimensions()
  G.clear(0.02, 0.04, 0.07, 1)
  local scale, ox, oy = letterbox(w, h)
  local canvas = self:ensureCanvas()
  if canvas then
    local prev = GameViewport.target()
    -- Flash overlay uses G.stencil. LÖVE 11 requires stencil=true on the
    -- active Canvas (Dewford Gym setflashradius).
    if not pcall(G.setCanvas, { canvas, stencil = true }) then
      G.setCanvas(canvas)
    end
    G.origin()
    G.clear(0.10, 0.22, 0.38, 1)
    self:drawScene()
    G.setCanvas(prev)
    G.origin()
    G.setColor(1, 1, 1, 1)
    G.draw(canvas, ox, oy, 0, scale, scale)
  else
    G.push()
    G.translate(ox, oy)
    G.scale(scale, scale)
    self:drawScene()
    G.pop()
  end
  GameViewport.finish(self)
  TouchControls:draw()
end

function Game3:keypressed(key)
  if key == "escape" and self.phase == "battle" then
    self:endBattle()
    return
  elseif key == "escape" and (self.phase == "roster" or self.phase == "play") then
    self.phase = "boot"
    self:resetBoot()
    return
  elseif key == "escape" and self.onExit then
    self.onExit()
    return
  end
  Input:keypressed(key)
end

function Game3:keyreleased(key)
  Input:keyreleased(key)
end

function Game3:wheelmoved(_x, dy)
  if dy > 0 then self:moveScroll(-1)
  elseif dy < 0 then self:moveScroll(1) end
end

function Game3:touchpressed(id, x, y)
  if TouchControls:touchpressed(id, x, y) then return end
end

function Game3:touchmoved(id, x, y)
  TouchControls:touchmoved(id, x, y)
end

function Game3:touchreleased(id, x, y)
  TouchControls:touchreleased(id, x, y)
end

function Game3:mousepressed(x, y, button, istouch)
  if istouch then return end
  if button == 1 then self:touchpressed("mouse", x, y) end
end

function Game3:mousemoved(x, y, dx, dy, istouch)
  if istouch then return end
  if love.mouse.isDown(1) then self:touchmoved("mouse", x, y) end
end

function Game3:mousereleased(x, y, button, istouch)
  if istouch then return end
  if button == 1 then self:touchreleased("mouse", x, y) end
end

function Game3:focus()
  if Input.reset then Input:reset() end
  if TouchControls.reset then TouchControls:reset() end
end

function Game3:visible() end
function Game3:onResume() end

function Game3:gamepadpressed(joystick, button)
  TouchControls:noteGamepad()
  Input:gamepadpressed(joystick, button)
end

function Game3:gamepadreleased(joystick, button)
  Input:gamepadreleased(joystick, button)
end

function Game3:gamepadaxis(joystick, axis, value)
  if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
  Input:gamepadaxis(joystick, axis, value)
end

function Game3:joystickpressed(joystick, button)
  TouchControls:noteGamepad()
  Input:joystickpressed(joystick, button)
end

function Game3:joystickreleased(joystick, button)
  Input:joystickreleased(joystick, button)
end

function Game3:joystickaxis(joystick, axis, value)
  Input:joystickaxis(joystick, axis, value)
end

function Game3:joystickhat(joystick, hat, direction)
  Input:joystickhat(joystick, hat, direction)
end

function Game3:joystickadded() end
function Game3:joystickremoved()
  if TouchControls.reset then TouchControls:reset() end
end

Game3Boot.attach(Game3)

return Game3
