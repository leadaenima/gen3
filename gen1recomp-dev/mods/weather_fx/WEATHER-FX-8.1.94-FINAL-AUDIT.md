# Weather FX 8.1.94 Final Audit

## Scope

Built directly from exact Weather FX 8.1.93. This release adds a RAVE-only streamed soundtrack/shuffle authority and synchronizes the existing RAVE presentation to the active song's exact decoder playhead and authored BPM. The prior snow, Battle Art water, and Battle Art NPC-lightning repairs remain preserved.

## RAVE soundtrack

Eight original, procedurally synthesized electronic songs are bundled as stereo OGG assets. No third-party recordings or samples are included.

| Song | Style | BPM | Light show |
|---|---|---:|---|
| Neon Conveyor | Techno | 134 | parallel lane chase |
| Steel Pulse | Techno | 142 | opposing hard banks |
| Pixel Rush | Rave | 150 | quarter-beat lattice chase |
| Laser Floor | Rave | 160 | spiral/floor-drop choreography |
| Voxel Wobble | Dubstep | 140 | half-time pendulum banks |
| Subspace Drop | Dubstep | 150 | radial drop bursts |
| Route 4 AM | House | 124 | smooth four-on-floor fan |
| Moonlit Club | House | 128 | mirrored soft club banks |

The playlist uses a Fisher-Yates shuffle bag, plays all titles before reshuffling, prevents an immediate repeat across bag boundaries, advances at EOF, and streams audio rather than statically loading full songs.

## Exact song/light synchronization

`RaveMusic.showSync()` exposes the active track record, current streamed decoder position, and song serial. When available, `CinematicAtmos` derives beat/bar phase from that exact playhead and the track's exact BPM. The legacy 128-BPM clock remains only as the fail-open path when streamed RAVE audio is unavailable.

Every track has a distinct choreography ID/profile. Per-song profiles independently tune fixture motion, hue progression, off-beat gating, bar accents, strobe density, beam width, fog/floor gains, speed, and authored arrangement cue bars. Laser geometry cache keys include the show identity and song serial so a newly shuffled song cannot reuse the previous song's beam state at the same timestamp.

The synchronized clock is presentation-only and cannot change weather simulation, lightning authority, precipitation, fronts, gameplay timing, or encounter logic.

## Audio ownership

RAVE music owns native map/battle music only while a RAVE source is actually desired and audible. WEATHER SFX=OFF releases that ownership. Leaving RAVE, leaving the world, disabling weather, reset, or audio invalidation cleanly stops/releases the streamed source. Weather FX never selects or restarts the host's native music.

## Verification

- Song/BPM/package synchronization: **47/47 PASS**.
- RAVE music shuffle/ownership test: **24/24 PASS**.
- Existing RAVE weather regression: **24/24 PASS**.
- Existing RAVE light-show regression: **22/22 PASS**.
- Per-song light-show executable test: **40/40 PASS**.
- Target LÖVE 11.5 OGG decoder test: **8/8 PASS**, all stereo 44.1-kHz streams and first decode blocks valid.
- Runtime LuaJIT syntax compile under LÖVE 11.5: **128/128 PASS**.
- Maintained developer sweep: **106/106 programs PASS**.

## Preserved behavior

8.1.93 Battle Art 1.10.4 NPC-lightning actor bridge/reaction, 8.1.92 full-render-distance snow, and 8.1.91 one-pixel snow plus Battle Art water ownership remain in the maintained sweep. The stale 8.1.93 manifest identity is corrected to 8.1.94.

## Truth boundary

The eight OGG files were decoded by the target LÖVE 11.5 runtime and the synchronization/choreography paths were executed in focused engine tests. No new live gameplay framebuffer capture of the RAVE soundtrack/light show is claimed in this release audit.
