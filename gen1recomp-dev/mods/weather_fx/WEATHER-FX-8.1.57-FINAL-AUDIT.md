# Weather FX 8.1.57 — Final Release Audit

## Release identity

Weather FX **8.1.57**, “2D Gale Relocation Tornado”, is built directly from exact 8.1.56.

## Runtime delta

Only four production runtime files change relative to 8.1.56:

- `lib/Tornado.lua` — relocation-only 2D Gale scheduling, safe visited-map preflight, movement lock, mid-cross transfer and single-owner funnel clock.
- `lib/Funnel.lua` — left-to-right relocation mode with one-shot centre pickup callback and continued right-edge exit.
- `lib/Draw.lua` — funnel compositor is render-only; no second animation update.
- `lib/Settings.lua` — player-facing tornado/carry help now explains 2D relocation-only behavior.

## Player behavior

- 2D tornadoes can occur only during authored `GALE`.
- They never spawn as ambient or roaming 2D scenery.
- Weather FX resolves carry chance and an escape-safe already-visited destination before drawing anything.
- `CARRY CHANCE = OFF` produces no 2D tornado.
- No eligible previously visited destination produces no 2D tornado.
- The funnel enters from the left, travels continuously right, covers the player near screen centre, performs the guarded relocation during that cover, then continues off the right edge on the destination map.
- The existing movement-collision hook locks player movement for the short 2D carry sequence.
- 3D world-space tornado behavior remains intact.

## Qualification

Release-specific gates:

- 8.1.57 runtime delta: PASS
- 8.1.57 runtime freeze: 162/162 PASS
- 8.1.57 package surface: 10/10 PASS
- 8.1.57 source contract: 11/11 PASS
- 2D Gale relocation tornado executable test: 11/11 PASS
- left-to-right funnel executable test: 7/7 PASS

Inherited gates completed cleanly, including:

- battle precipitation continuity 8.1.56: 6/6 PASS
- 3D Gale tornado: 38/38 PASS
- tornado map persistence: 10/10 PASS
- tornado safe destinations: 23/23 PASS
- render pipeline: 352/352 PASS
- performance invariants: 66/66 PASS
- strict 3D pipeline: 117/117 PASS
- headless mod suite: 191/191 PASS
- feature integrity: 498/498 PASS
- final host/settings/sandbox/compatibility tail: `all ok — safe baseline for next revision`

The maintained runner exceeded one monolithic execution window after a long zero-failure prefix. Coverage was completed from the exact cutoff in contiguous bounded segments; the continuation through 3D pipeline and the final host/settings/compatibility segment both completed without failures. No timeout is counted as a pass.

## Visual-test boundary

The left-to-right funnel path is executable-tested against the real `Funnel.lua` draw geometry and callback timing. This container does not provide a live interactive Gen1Recomp framebuffer capture of the final event, so the release does not claim a manual in-game visual capture.

## Verdict

**PASS.** 8.1.57 supersedes 8.1.56 as the release baseline.
