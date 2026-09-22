# Weather FX 8.1.98 Final Audit

## Scope

Built directly from exact Weather FX 8.1.97. This release is limited to the reported RAVE cloud-bank density/zenith persistence issue, direction-dependent 3D snow dropout while walking, and the remaining BLIZZARD single-pixel/fountain presentation seam.

## Runtime changes

Only two shipped runtime Lua files change versus exact 8.1.97:

- `lib/voxel_atmos/CinematicAtmos.lua`
  - RAVE volumetric profile increases span/puff overlap and sealed-deck X/Z overlap only for RAVE.
  - RAVE sealed clouds receive a wider but bounded world-space overhead admission/fade so zenith pitch cannot cull the nearby party ceiling solely because cloud centres leave the normal projected NDC band.
  - Distant snow/blizzard slab retirement now uses the authoritative current/root snow-family weather id as a backstop if the snow channel momentarily publishes zero. Transition targets are deliberately not used, preserving genuinely distant incoming snow before local ownership begins.
- `lib/ProceduralSnowField.lua`
  - Fixed-world snow anchors remain immutable during each field lifetime and keep the existing constant-count 1.6-second identity handoff.
  - The snap cell changes from up to 256 units / 50% of snow radius to 4% of radius capped at 24 units. Maximum centre lag is therefore 12 units instead of as much as 128, preventing the far edge from becoming directionally sparse while walking without adding instances or doubling the handoff field.

The inherited `snow_motion_8155_test.lua` was updated only to exercise its existing no-sliding/fixed-anchor contract at the new 24-unit boundary. Release/test tooling is updated to include the 8.1.98 regression in maintained package checks.

## Regression results

- New `rave_snow_continuity_8198_test.lua`: **12/12 PASS**.
- Exact 8.1.97 negative control: **8/12 checks fail** as required.
- Inherited focused RAVE/cloud/snow regressions: PASS, including cloud zenith persistence, RAVE show/fog, 8.1.90/8.1.91 fountain guards, 8.1.92 full-render-distance snow, procedural snow virtualization, snow motion, and snow intensity.
- Revision gate: **80/80 PASS**.
- Maintained parallel developer sweep: **113/113 programs PASS**.
- `test_mod.py --lua`: **194 passed, 0 failed, 0 skipped**.
- Runtime Lua syntax compilation: **129/129 PASS**.

One historical 8.1.55 exact-freeze performance script still reports two stale failures on both this source and untouched exact 8.1.97; it is not used as evidence of this release and was not rewritten to manufacture a green result.

## Performance / ownership boundary

The snow fix does not increase logical snow population, hard caps, instance count, or total handoff instance submissions. It only reduces the maximum fixed-anchor offset. Ordinary weather cloud descriptor/puff rules are unchanged; the cloud-density increase and wider overhead admission are RAVE-only and remain under the existing bounded cloud-lattice search and quality/performance scaling.

Rain, hail, sand, ash, debris, normal cloud families, precipitation distance settings, RAVE music/strobe controls, Battle Art water/NPC-lightning ownership, tornadoes, celestial systems, seasons, battles, and 2D weather are not re-authored by this release.

## Truth boundary

The deterministic tests exercise the real cloud descriptor builder, real snow streaming-anchor state and real distant-front ownership policy, but this environment does not provide a live interactive Gen1Recomp framebuffer/player session. Therefore this audit does not claim a new human visual capture of RAVE zenith clouds or a long in-game walking reproduction. The package is code/test-qualified; the final subjective cloud thickness should still be judged in the real game.
