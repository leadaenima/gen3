# Encounter Radar

A **RADAR** row in the START menu that lists every wild Pokémon the map you
are standing on can produce, with each one's share of the roll and its level
range.

Gen 2 is the generation this is worth building for. A Johto route does not
have *a* wild table — it has one for morning, one for day, one for night, one
for surfing, and one row list per fishing rod, all keyed off the same tile you
are standing on. The radar pages through every one of them and marks the page
the clock is currently on with **NOW**.

Kanto is the simpler half and works too: one ten-slot table per map, one for
surfing, and rods that are a rule per rod rather than a group per map. There
the radar is one or two pages, plus a rod page wherever the map has water.

**Persona: the Tool Builder.** Read the merged encounter tables through
`mod.content.encounters`, put a screen on the stack through `mod.ui`, and
change nothing about how the game rolls.

## Engines

Runs on both ports, and on either generation each of them can load. Nothing
detects which engine is running — the adapters key off the *shape* of the
tables they are handed:

| Dataset | Looks like | Slot odds | Rods |
|---|---|---|---|
| Kanto, per map | `encounters[MAP].grass.slots[10]` | `constants.encounterBuckets`, /256 | `field.fishing` |
| Johto, per map | the same, plus `grass.byTime.morn/.nite` and a per-record `buckets` | the record's own, /256 | `field.fishGroups[GROUP].rods` |
| Johto, per kind | `encounters.grass[MAP].slots.MORN` | fixed 30/30/20/10/5/4/1, /100 | `encounters.fishGroups[GROUP][rod]` |

The two Johto shapes are the two ports' extractors disagreeing about how to
store the same cartridge; the third column is why the odds cannot simply be
hard-coded. The two fishing walks also disagree about the comparison — one is
`roll <= chance` starting at −1, the other `roll < chance` starting at 0 — so
each gets its own walk rather than a shared one that is subtly wrong on one.

## Try it

Copy this folder to `mods/johto_radar`, then enable **Encounter Radar** in the
in-game mod manager (F10 on desktop; the MODS row in the START menu on a
phone).

- Stand anywhere in the overworld, open START, choose **RADAR**.
- **LEFT / RIGHT** page between GRASS MORN / GRASS DAY / GRASS NITE / SURF /
  OLD ROD / GOOD ROD / SUPER ROD — only the pages the map actually has.
- **B** goes back to the START menu.

There is also a small overlay in the top right of the overworld, so the answer
stays on screen while you walk and you do not have to reopen the menu every
time you cross a map boundary or the clock rolls over. See below.

Reading a row:

```
GRASS DAY NOW              ◀▶
▶ PIDGEY               30/100
    LV 2-4
  SENTRET              30/100
    LV 3
ROUTE 29
STEP 24/256               2/5
```

`30/100` is the species' share **of an encounter**, summed over every slot it
occupies. `STEP 24/256` is the separate question of whether a step produces an
encounter at all — the raw byte the engine compares a `rand(0,255)` against,
not a rounded percentage. On a Johto rod page that bottom line reads
`BITE 64/256` instead, which is the fishing group's own bite chance.

Kanto's rods say it differently, because the engine asks differently. The Old
Rod reads `ALWAYS BITES`: it hooks a level 5 Magikarp every single time. The
other two read `BITE 2/6` and `BITE 3/7`, which is not a byte comparison but
the rejection loop in `ItemUseGoodRod` — an odd roll is no bite, and an even
one takes a two-bit index that is rerolled until it lands inside the group, so
the odds work out to `size / (size + 4)`. Inside a bite the pick is uniform.

A Pokéball next to a name means you already own that species. Turn that off
with the **MARK OWNED** option if you would rather not see it.

## The walking overlay

A small box in the top right of the overworld showing what the tile you are
standing on can produce *right now* — the grass table the clock is on, or the
water table while surfing:

```
                      HOOTHOOT
                      RATTATA
                      SPINARAK
```

At its defaults that is 80x40 pixels in the corner, and a short-named Kanto
route comes out narrower still at 72x40. It disappears entirely on a map with
nothing to catch.

| Option | Default | Does |
|---|---|---|
| **WALK OVERLAY** | on | turns it off entirely |
| **OVERLAY ODDS** | off | adds each species' share beside its name |
| **OVERLAY ROWS** | 3 | how many species it lists (1–6) |
| **OVERLAY WIDTH** | 10 | ceiling on its width, in 8-pixel tiles (5–20) |
| **OVERLAY ALPHA** | 70 | how solid the panel is, 0–100 |

The width is a *ceiling*, not a fixed size — the box still shrinks to fit a
route of PIDGEYs. Names too long for it are clipped by glyph rather than by
byte, so NIDORAN♂ and NIDORAN♀ survive the cut.

Worth knowing if you turn **OVERLAY ODDS** on: the numbers and their gap eat
three of the ten columns, leaving five characters for the name. Widen
**OVERLAY WIDTH** to about 14 at the same time and you get nine back.

**OVERLAY ALPHA** fades the panel only — the names stay solid at every setting,
because the reason to see through the box is to keep watching the map, not to
make the list harder to read. At 0 you get bare text over the world, which is a
legitimate setting rather than a broken one.

That transparency is why the panel is not drawn with `Font.drawBox`. The
engine's helper forces its interior fill to full opacity, quite reasonably —
every vanilla box exists to hide what is under it. The overlay draws the same
six border glyphs (`Font.BORDER`, charmap `$79`–`$7E`) around a fill whose alpha
it controls. It also pins the blend mode to `alpha` inside its own
`push("all")`/`pop`, because `render.hud` fires straight off the end of the
composite pass and inherits whatever mode that left set.

It scales itself from the `gameWidth`/`gameHeight` the hook hands it, not from
`viewport.scale`. Both ports fill that field with `fitScale()`, which counts
framebuffer pixels per Game Boy pixel, while the rest of the viewport is in LOVE
window units — the same number only at a display density of exactly 1. That
holds on every desktop and on no phone, so trusting it drew the box two or three
times too large and slid a top-right panel off the edge of the screen. The
rectangle agrees with the origin at any density, and the two axes are taken
separately, since `dpiX` and `dpiY` need not match.

When the window is larger than that letterbox — DRAMATIC_SHAPE's voxel world,
Gold's edge-to-edge overworld, a tall phone — the overlay pins to the
*window's* top-right instead of the letterbox's. The engine still reports the
160x144 playfield even while a world pipeline has already filled the screen, and
a box stuck to that playfield sat in the middle of the 3D view. Depth test,
mesh cull and stencil are also cleared before it draws, because a leaked 3D
state is how a correctly placed 2D overlay still comes out blank.

It stays out of the way on its own. An *opaque* state stacked over the world —
a menu, a battle, the save prompt — hides it, as does a script, a map fade or
a fly animation. A transparent lid (DRAMATIC_SHAPE's battle-exit fade) does
not: the world is still the picture, and treating that lid as a cover left the
overlay dark after voxel mode was switched off. It is rebuilt only when the
map, the clock period or the surf state actually changes, so walking a route
does not re-read the encounter tables every frame.

Two details worth knowing if you go changing it. The ports disagree about where
the world lives: Gen 1 pushes the overworld onto the state stack, while Gold
keeps it on `game.world` and an *empty* stack is exactly what free roam looks
like. The overlay therefore asks "is an opaque state stacked on top of the
world?", which is true on both rather than only one. And it deliberately does
**not** use the engine's `acceptsMenuInput`, which goes false between tiles
while the player is mid-step — that would strobe the box on every stride. A
`busy()` bolted onto the Gen 1 overworld module by another mod is ignored for
the same reason; Gold's own `World:busy` still hides the list over a textbox.

## What it reads

| Seam | Used for |
|---|---|
| `mod.content.encounters:get` | the map's grass / water tables, or the per-kind tables keyed by map |
| `mod.content.pokemon:get` | species display names |
| `mod.content.maps:get` | the map's `fishGroup` when called through the export |
| `mod.world:overworld()` | the live map and the cached time of day |
| `hooks:wrap("ui.start_menu.items")` | the RADAR row, anchored before SAVE |
| `hooks:wrap("render.hud")` | the walking overlay, over the finished frame |
| `mod.ui.ListMenu` / `mod.ui.push` | the screen and the way back to START |
| `mod.options:define` / `:get` | ENABLED and MARK OWNED |

Fishing data never lives in the encounter record. In Johto the map header
carries a `FISHGROUP_*`, the group carries a bite chance and one row list per
rod, and a row with no species of its own names a `timeFishGroups` pair that
resolves to a day or night slot — so the Super Rod page genuinely changes after
dark. That is the same walk `engine/events/fish.asm` does. In Kanto there is no
group at all: `field.fishing` holds one rule per rod, and only the Super Rod is
per-map (`field.superRod[MAP]`).

Because Kanto's Old and Good Rods are global rules rather than map data, they
would otherwise offer a Magikarp inside every house in the region. They are
shown only where the map has a water table; a Super Rod group is its own proof
that the map can be fished, so it is never gated.

`data.field` is deliberately unbacked on one of the Gen 2 paths, so every read
of it goes through a `pcall` and a missing table just means one fewer page.

## Export

Other mods can read the same table the screen draws:

```lua
local radar = mod.find("johto_radar")
local pages = radar.exports.report("ROUTE_29", "NITE")
-- pages[i] = { title, tod, note, total,
--              rows = { { species, min, max, weight }, ... } }
```

`weight` is out of `page.total`, not a percentage, because that is the number
the roll actually uses — and the denominator is genuinely different between
datasets: 256 for a per-map table, 100 for a per-kind one, and the group size
for a Kanto rod. Divide by `page.total` if you want a percentage.

## Tests

```sh
luajit mods/johto_radar/tests/radar_tests.lua
luajit mods/johto_radar/tests/menu_tests.lua
```

`menu_tests` also covers the overlay: that it draws flush to the top right
while walking, that an empty stack (Gold's free roam) counts as the world
showing just as much as the world being top-of-stack (Gen 1's), and that it
declines to draw over a menu, a busy world, a transition, or a water table the
map does not have.

`radar_tests` is 84 assertions over synthetic tables in all three shapes,
covering the threshold-difference arithmetic, level-range merging, both rod
walks, timed-row resolution in its indexed and inline forms, the Kanto rejection
loop, a rate of zero, and a map with no wild data at all. `menu_tests` drives
the START row and the screen through the **real** `ListMenu` of whichever repo
it is run from, which is what proves the paging and the second-line drawing
against both ports. Both are listed in `.modkitignore` so they stay out of the
packaged archive.

## Known limits

- Swarms, the Bug Catching Contest and roaming legendaries are not encounter
  tables and do not appear here.
- Headbutt and Rock Smash get no page. Only the per-kind dataset extracts
  `trees` / `rocks` / `treeSets` at all, and a page that exists on one port and
  not the other is worse than one that exists on neither.
- Kanto's Old and Good Rods are hidden on maps with no water table. A map with
  water tiles but no water *encounters* is fishable in the engine and will show
  no rod page.
- Odds are the vanilla slot shares. A mod that hooks `encounter.roll` or
  `encounter.species` to change what actually appears will not be reflected —
  the radar reads the tables, not the roll.

## Credits

- gen1recomp and Gen2Recomped — the `encounters` registry, `field.fishing` /
  `field.fishGroups`, and the `ui.start_menu.items` / `mod.ui` seams.
