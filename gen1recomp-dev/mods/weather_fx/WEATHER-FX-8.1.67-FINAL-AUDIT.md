# Weather FX 8.1.67 — Final Audit

## Release scope

8.1.67 is the live-runtime hotfix to 8.1.66. It fixes four player-reported areas together:

1. Snow accumulation/voxel repaint alignment, including real raised Route 4 ledges and mixed ground/ledge cells.
2. 2D Gale tornado relocation opportunity timing.
3. Player-facing tornado-frequency control.
4. Camera-correct 2D celestial projection plus an independent 2D/3D celestial presentation selector.

## Snow repair

The real framebuffer run exposed defects that the 8.1.66 deterministic mocks did not:

- camera/focus Y could become SnowPack's fallback surface and lift banks/repaint above the voxel floor;
- in-place map hydration could leave a stale shape classification;
- a host TileShape wrapper could flatten an authored raised ledge despite current voxel support proving Y=6;
- six ordinary-ground patches could saturate a mixed 16×16 cell and reject a later distinct ledge support.

8.1.67 uses the player's exact `VoxelScene.groundAt` floor as fallback, refreshes live TileShape authority, refuses to downgrade proven raised host support to flat ground, and preserves at least one representative patch for a new distinct support without increasing `MAX_PATCHES_PER_CELL=6`.

Raised scenery remains repaint-only: no detached ledge/tree cap mesh is reintroduced. Ground/grass/load-bearing ice may retain physical snow thickness.

## 2D Gale tornadoes

The normal/default opportunity interval is exactly **90 seconds** while outdoor GALE is active. At each opportunity the normal relocation chance remains **10%**. Successful rolls use the existing safe-destination relocation choreography.

`TORNADO FREQUENCY` exposes the opportunity cadence:

- RARE: 180 s
- NORMAL: 90 s
- OFTEN: 60 s
- EXTREME: 30 s

Frequency changes opportunity spacing; it does not silently change the separate 10% normal relocation roll.

## Celestial presentation

`CELESTIAL RENDERING` is now independent from weather-particle presentation:

- MATCH WEATHER
- 2D SKY
- 3D WORLD

Therefore players can use 2D weather animations and still select the world-space 3D celestial system. The 2D sun/moon projection now consumes the active voxel camera basis, so a fixed world sun/moon no longer follows camera rotation as though glued to the screen.

## Verification

Current-source gates after the final mixed-support SnowPack allocator repair:

- 8.1.67 tornado frequency executable: 5/5 PASS
- 8.1.67 celestial world-lock: 3/3 PASS
- 8.1.67 celestial presentation setting: 5/5 PASS
- 8.1.67 live snow alignment: 7/7 PASS
- 8.1.67 structural contract: 14/14 PASS
- exact Voxel Nexus 2.0.17 ledge/depth contract: 10/10 PASS
- inherited surface repaint: 24/24 PASS
- exact tree hull: 5/5 PASS
- SnowPack live restore: 7/7 PASS
- 2D relocation: 8/8 PASS
- tornado pickup semantics: 20/20 PASS
- 3D tornado: 38/38 PASS
- celestial engine: 49/49 PASS
- accumulation/footprints: 14/14 PASS
- radial snow surfaces: 10/10 PASS
- snow virtualization: 10/10 PASS
- snow motion: 10/10 PASS
- settings/runtime: 249/249 PASS
- `test_mod.py --lua`: 191/191 PASS
- performance invariants: 66/66 PASS
- 3D pipeline: 117/117 PASS
- feature integrity: 505/505 PASS
- voxel-host contract: 27/27 PASS
- aggressive compatibility: 30 PASS / 0 MED / 0 HIGH
- benchmark: 26/26 + integration 24/24 PASS
- full audit: HIGH=0

Untouched 8.1.66 fails all three core new bug regressions: 2D tornado cadence, 2D celestial camera world-lock, and live snow floor/alignment.

## Maintained runner completion

The monolithic `tools/run_all.py --lua` invocation exceeded the outer five-minute shell ceiling after a PASS-only prefix through the 8.1.26 celestial-player-experience gates. No timeout is counted as a pass. The exact remaining command sequence was then completed in bounded continuation segments:

- corrected path-sensitive `test_shader_attrs.py`: PASS;
- corrected path-sensitive `test_scope_hygiene.py`: PASS;
- continuation segment A (8.0.3 regressions through lightning bursts): PASS, 0 failed commands;
- continuation segment B (LuaJIT/3D/celestial/settings/sandbox/mod/compatibility/full audits through `mod_map.py`): PASS, 0 failed commands.

The five stale maintained expectations initially exposed by the earlier completed runner were updated to the 8.1.67 architecture (69 settings, 180-second RARE tornado cadence, independent world-celestial ownership, and camera-aware floating-point 2D celestial projection) and individually pass before the final segmented replay.

## Live visual qualification

See `WEATHER-FX-8.1.67-LIVE-FRAMEBUFFER-PROOF.md` and the externally preserved raw framebuffer evidence. The real Route 4 run demonstrates Y=6 ledge support, real falling snow, raised-surface repaint population, ground snow at terrain level rather than player-chest height, and complete melt-back to zero SnowPack/repaint population.

## Boundary

No claim is made that every GPU/driver/device has been manually inspected. The changed snow path has real Gen1Recomp/LÖVE framebuffer evidence on the exact Voxel Nexus 2.0.17 host, while the remaining host/quality combinations are covered by deterministic and structural compatibility gates.
