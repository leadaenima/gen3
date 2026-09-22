# Weather FX 8.1.86 Final Audit

## Scope
Manual-only 3D RAVE weather added on top of exact 8.1.85.

## Runtime delta
Exactly three runtime Lua files differ from exact 8.1.85:
- `lib/Types.lua`
- `lib/DramalessAtmos.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

## RAVE behavior
- Manual-selectable via shared weather ladder / Mod Manager choices.
- `natural=false`: AUTO, CYCLE, seasons, and fronts cannot schedule it.
- Heavy closed cloud-bank profile with no precipitation channels.
- Deterministic per-cloud rainbow hue.
- Rhythmic cloud pulse in volumetric and blocky renderers.
- World-space multicolour laser ribbons emitted from live cloud descriptors.
- Lasers strobe on/off and depth-test in the 3D world.
- No lightning/thunder or battle mechanic is fabricated for the effect.

## Regression evidence
- RAVE 8.1.86: 24/24 PASS.
- Negative control exact 8.1.85: 4 PASS / 20 FAIL.
- Full developer sweep: 86/86 programs PASS.
- Runtime compile: 123/123 PASS.
- Catalogue: 30 weather definitions.
- Settings remain 77 player-facing controls; RAVE is a choice within WEATHER, not a new settings row.

## Limitation
No fresh manual live-game framebuffer/device visual session was available for this release.
