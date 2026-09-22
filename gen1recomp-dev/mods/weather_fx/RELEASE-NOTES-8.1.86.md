# Weather FX 8.1.86 — Rave Weather

Built directly from exact Weather FX 8.1.85.

## New manual-only weather: RAVE

RAVE is a dedicated 3D party-weather mode. It is visible in both player weather selectors, but it is explicitly excluded from AUTO scheduling, CYCLE, seasons, and WEATHER FRONTS.

When RAVE is selected:

- the 3D cloud bank uses heavy-rain-class sealed coverage;
- clouds are assigned deterministic rainbow hues instead of ordinary grey/white shading;
- both VOLUMETRIC and BLOCKY cloud-bank styles pulse rhythmically on a shared visual beat;
- multiple coloured 3D laser ribbons originate from the live cloud descriptors, extend into the world, depth-test against world geometry, and strobe independently on/off;
- RAVE does not fake rain, snow, hail, sand, ash, lightning, thunder, or battle weather in order to produce the effect.

The beat clock is presentation-only and does not add or require a music asset.

## Qualification

- RAVE regression: 24/24 PASS
- Negative control on exact 8.1.85: 4 PASS / 20 FAIL, exit 1
- Full source developer sweep: 86/86 programs PASS
- Runtime Lua compilation: 123/123 PASS
- Existing settings runtime: 735/735 PASS
- Existing complete player-setting interaction audit: 2243/2243 PASS
- Existing render pipeline audit: 354/354 PASS

No fresh live-game framebuffer/device session was captured for 8.1.86; qualification is executable harness/source/package evidence, not a claim of manual visual playtesting.
