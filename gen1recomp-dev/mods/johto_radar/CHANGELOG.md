# Changelog

All notable changes to this mod are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version
numbers match `manifest.version`.

## [1.4.3]

### Fixed

- DRAMATIC_SHAPE (and its Battle Art fork) still hid the overlay after voxel
  mode was switched off. That mod wraps `Renderer:endFrame`, pushes transparent
  fade states, and can leave a `busy()` on the overworld module. The overlay
  treated any of those as "the world is not showing" and stayed dark for the
  rest of the session.
- Transparent stack lids (`isOpaque == false`) no longer count as a cover.
- A `busy()` bolted onto the Gen 1 overworld module is ignored; Gold's own
  `World:busy` (textboxes, the script VM) still hides the list.
- `render.hud` wrappers that throw, and an `endFrame` that returns no
  viewport, no longer swallow the overlay: the next function is pcall'd, the
  draw is pcall'd, and a missing viewport becomes a full-window one.
- If `mod.world:overworld()` misses, `game.world` / `game.overworld` is enough.

## [1.4.2]

### Fixed

- The walking overlay vanished next to DRAMATIC_SHAPE (and any other world
  pipeline that fills the window). `render.hud` still hands over the 160x144
  letterbox, even while the voxel pass has already covered the whole window, so
  a box anchored to that letterbox's top-right sat in the middle of the 3D
  view. The overlay now pins to the *window's* top-right whenever the playfield
  is letterboxed, and keeps the Game Boy scale so the type stays the same size.
- Leftover 3D graphics state (depth test, mesh cull, stencil, a bound shader)
  is cleared before the box draws. LÖVE's `push("all")` does not cover those on
  every runtime, and a leaked depth test is how a perfectly-placed 2D overlay
  fails the test and draws nothing.
- The overlay paints *after* other `render.hud` wrappers, at wrap priority
  1000, so a graphics mod that also uses that layer cannot bury the list.

## [1.4.1]

### Fixed

- The walking overlay was invisible on high-DPI screens — in practice, on some
  Android builds, while every desktop was fine. It was scaling the box by
  `viewport.scale`, which both ports fill with `fitScale()`: framebuffer pixels
  per Game Boy pixel. The rest of the viewport (`gameX`, `gameY`, `gameWidth`,
  `gameHeight`) is in LOVE window units. Those two are the same number only when
  the display density is exactly 1, which is every desktop and no phone. At a
  density of 2.75 the overlay was drawn 2.75× too large from a correctly placed
  origin, which puts a box anchored to the top *right* somewhere off the side of
  the screen — hence present, drawing every frame, and impossible to see.
- The scale is now derived from the playfield rectangle (`gameWidth / 160`,
  `gameHeight / 144`), which is self-consistent whatever the density, and taken
  per axis, since `dpiX` and `dpiY` are not always equal.

## [1.4.0]

### Added

- **OVERLAY ALPHA** (0–100, default 70): the walking overlay's panel is now
  see-through. The names stay solid at every setting, because the point of
  seeing through the box is to keep watching the map rather than to make the
  list harder to read — at 0 that leaves bare text over the world, which is a
  setting rather than a bug.

### Notes

- The panel is no longer drawn with `Font.drawBox`. That helper forces its
  interior fill to full opacity, reasonably, since every vanilla box is meant
  to hide what is under it. The overlay now draws the same six border glyphs
  (`Font.BORDER`, charmap `$79`–`$7E`) around a fill whose alpha it controls.
- The blend mode is pinned to `alpha` inside the overlay's own
  `push("all")`/`pop`. `render.hud` runs straight off the end of the composite
  pass, which is exactly the sort of place a premultiplied mode is left set,
  and a translucent panel is the one thing that would quietly come out wrong.

## [1.3.0]

### Added

- **OVERLAY WIDTH** (5–20 tiles, default 10), a ceiling on how wide the walking
  overlay may grow. The box still sizes itself to what it is holding; the cap
  only stops a ten-letter name from turning a corner ornament into a panel.
  Names longer than the cap are clipped by glyph rather than by byte, so the
  multi-byte charmap entries in NIDORAN♂ / NIDORAN♀ survive it.

### Changed

- The overlay is smaller by default: 3 rows instead of 4, odds off instead of
  on, and the new width cap. On a Johto night route that takes it from 104x48
  pixels starting at x=56 — which read as a panel sitting over the middle of
  the screen — to 80x40 starting at x=80, which is genuinely the top-right
  corner. A short-named Kanto route comes out narrower still, at 72x40.

## [1.2.0]

### Added

- A live overlay in the top right of the overworld, drawn through `render.hud`,
  listing what the tile you are standing on can produce right now — the grass
  table the clock is on, or the water table while surfing. It answers the
  "what changed?" question on a map change or a time change without opening
  anything.
- Options: **WALK OVERLAY**, **OVERLAY ODDS** and **OVERLAY ROWS** (1–6).

### Notes

- The overlay hides itself whenever anything is stacked over the world, and
  while the world is busy with a script, a textbox or a map fade. The two ports
  disagree about where the world lives — Gen 1 pushes it onto the state stack,
  Gold keeps it on `game.world` and an *empty* stack is what free roam looks
  like — so the test is "nothing is stacked on top of it", which is true on
  both.
- It deliberately does not use the engine's own `acceptsMenuInput`, which goes
  false between tiles while the player is mid-step and would strobe the box on
  every stride.
- The page is rebuilt only when the map, the clock period or the surf state
  changes, so walking a route does not re-read the registries every frame.

## [1.1.0]

### Added

- Runs on gen1recomp as well as Gen2Recomped, and on either generation either
  of them can load. Three dataset adapters, chosen by the shape of the tables
  rather than by asking which engine is running: Kanto's per-map ten-slot
  tables scored off `constants.encounterBuckets`, Johto's per-map tables with
  their own `buckets`, and Johto's per-kind tables scored out of 100.
- Kanto fishing from `field.fishing`: the Old Rod's guaranteed hook, the Good
  Rod's fixed pair, and the Super Rod's per-map group, with the uniform pick
  and the `size / (size + 4)` bite odds of the `ItemUseGoodRod` rejection loop.
- A second fishing walk for the per-kind dataset, which compares `roll < chance`
  from 0 where the per-map one compares `roll <= chance` from −1, and which may
  carry a timed row's day/night pair inline instead of by index.

### Changed

- Pages turn through a wrapper around the list's own update rather than the
  widget's pocket-switch option, which only one of the two ports has.
- `report()` pages now carry `total`, the denominator their `weight` values are
  out of. It is 256 for a per-map table, 100 for a per-kind one, and the group
  size for a Kanto rod, so a percentage is `weight / total`.

### Fixed

- The threshold fallback chain never fired: it walked its candidates with
  `ipairs` over a table whose first entry is usually `nil`, which stops at once.
  Any record that did not carry its own `buckets` — every Kanto one — silently
  produced no rows at all.

## [1.0.0]

### Added

- A **RADAR** row in the START menu, anchored before SAVE, opening a paged
  read-out of the current map's wild encounter tables.
- Separate pages for morning, day and night grass, read from the Gen 2
  `byTime` slot sets; the page matching the clock opens first and is titled
  **NOW**.
- A **SURF** page from the map's water table.
- One page per fishing rod, walked out of `field.fishGroups` with
  `field.timeFishGroups` rows resolved against the current time of day.
- Per-species odds summed across slots, level ranges collapsed to a span, and
  an owned marker read from the Pokédex.
- Options: **ENABLED** and **MARK OWNED**.
- `mod.exports.report(mapId, tod, mapDef)` publishing the same page table the
  screen draws.
