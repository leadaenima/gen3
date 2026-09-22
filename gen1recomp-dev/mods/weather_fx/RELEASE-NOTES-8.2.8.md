# Weather FX 8.2.8 — 3D Cloud/Celestial Continuity + Localized Snow Fields

Built directly from exact Weather FX 8.2.7 after real first-person Battle Art testing exposed three presentation problems: cloud-bank loss when looking upward, FRONT OFF cloud cover globally erasing the celestial vault, and excessive distant 3D snow producing a fuzzy horizon.

## Clouds stay present when looking up

- The bounded world-space overhead cloud shoulder is widened for every 3D cloud family.
- Overhead cloud opacity now retains a stronger physical shoulder floor while the cloud volume is still above the player.
- This branch is based on world distance rather than projected screen Y, so pitching down and back up does not delete clouds because their centres moved outside an old NDC admission band.
- RAVE keeps its slightly larger bounded overhead shoulder without removing the low-end cloud-count cap.

## Sun, moon, stars and constellations remain a live 3D vault

- Full 3D weather always keeps Weather FX's world-space celestial renderer active, even if CELESTIAL RENDERING is set to 2D.
- 3D clouds no longer use one coarse cloud-transmission sample to globally alpha-fade the sun, moon, stars, or constellation field.
- Celestials are submitted first and cloud/weather geometry is drawn afterward. This means the sun, moon and stars appear through open cloud gaps but do **not** render directly through opaque cloud bodies.
- The coarse cloud ray is still retained for direct optics such as glare/god-ray attenuation; only the incorrect whole-vault disappearance is removed.
- The game-cycle clock continues moving the sun and moon under 3D weather with FRONTS OFF, and the night star/constellation field remains live throughout the cycle.

## 3D SNOW_LIGHT and BLIZZARD are heaviest around the player

- The procedural 3D snow field now applies a deterministic player-centred population taper to SNOW_LIGHT / legacy SNOW and BLIZZARD only.
- The near overhead/player core remains fully populated.
- Actual visible particle identities decrease smoothly through mid distance and become extremely sparse near the configured render-distance edge.
- A nonzero far continuation prevents a hard circular cutoff while avoiding the former wall of tiny distant points.
- BLIZZARD keeps a heavier authored logical population than SNOW_LIGHT, but its far rings are tapered more aggressively so the storm reads as dense local snowfall rather than screen-wide static.
- The final distance calculation uses a sqrt-free octagonal radius approximation, preserving the phone/low-end per-vertex performance contract.
- THUNDERSNOW is intentionally unchanged by this specific spatial taper.

## Fresh production-path evidence

Real Gen1Recomp 0.2.53 + Battle Art Voxel Fork 1.10.4 fixture testing verifies:

- repeated first-person up/down/up cloud viewing retains the overhead cloud bank;
- FRONT OFF day/night captures retain the world-space celestial vault behind cloud geometry;
- a production GAME CYCLE run moves the sun and moon while 3D weather remains active and stars remain live at night;
- revised SNOW_LIGHT and BLIZZARD sustained captures show a dense local field with substantially cleaner far distance;
- the procedural snow backend remains native-ID/proven and the focused run exits RC=0.

The ROM-free fixture is a renderer/game-state qualification host, not Pokémon Yellow. No fresh Yellow 8.2.8 gameplay claim is made without legitimate user-provided game data.
