# Weather FX 8.1.86 Final Qualification

Status: **PASS**.

Built directly from exact Weather FX 8.1.85.

## RAVE-specific gates
- RAVE regression: 24/24 PASS.
- Negative control on exact 8.1.85: 4 PASS / 20 FAIL, exit 1 as required.
- RAVE is manually selectable and `natural=false`.
- AUTO and CYCLE exclusion contracts PASS.
- Heavy closed cloud-bank profile PASS.
- Volumetric rainbow/pulse path PASS.
- BLOCKY rainbow/pulse path PASS.
- World-space multicolour laser construction, strobe variation, cloud-altitude origin, and draw submission PASS.

## Full regression gates
- Developer sweep: 86/86 programs PASS.
- Runtime Lua compilation: 123/123 PASS.
- Weather catalogue: 30 definitions.
- Settings runtime: 735/735 PASS.
- Complete player-setting interactions: 2243/2243 PASS.
- Render pipeline audit: 354/354 PASS.
- Existing 8.1.85 cloud-bank style and dual weather-selector regressions remain PASS.

## Package/source integrity
- Source/package tree comparison: 813/813 files identical before final documentation-only freeze; final archive is replayed again after this document is frozen.
- No RAVE runtime change touches precipitation ownership, water, tornado, lightning, battle, settings count, celestial, or audio engines outside the three-file runtime delta.

## Limitation
No fresh live-game framebuffer/device visual session was available. This qualification is executable/source/exact-package evidence and does not claim a manual visual playtest.
