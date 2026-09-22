# Weather FX 8.1.74 — Continuous Precipitation / Fronts-Off Uniform Field

## What is fixed

### Rain no longer starts/stops as you walk
The 8.1.73 rain field was correctly world-anchored, but one older system was still tied to the player position: the mesoscale shower-band sampler. As the player crossed invisible world-space moisture/noise cells, that sampler could multiply the active rain channel down enough to make WorldPrecip allocate zero drops, then bring the rain back when the player entered a wetter cell.

8.1.74 separates those responsibilities. With **WEATHER FRONTS OFF**, rain/snow/hail intensity is no longer modulated by the player-position mesoscale precipitation sample. The active weather owns the entire configured 3D WEATHER DISTANCE continuously.

### Procedural precipitation is uniform when fronts are OFF
The procedural rain/hail and snow shaders previously still consumed mesoscale `patchiness` / `floor` values even with WEATHER FRONTS disabled. 8.1.74 forces `fieldPatchiness = 0` and `fieldPatchFloor = 1` in fronts-OFF mode, preventing hidden dry bands inside an otherwise global weather field.

### Fronts-ON banding remains, without hard allocation dropouts
With WEATHER FRONTS ON, regional/mesoscale variation remains intact. However, if the authored rain/snow/hail channel is active, mesoscale thinning can no longer push the final value through WorldPrecip's `> 0.02` allocation threshold and abruptly switch the precipitation engine off. It may become very light, but the active weather does not hard-toggle solely because the player crossed a mesoscale trough.

## Preserved from 8.1.73

- Fixed world-space rain/hail anchors instead of player-following precipitation.
- Immediate map-entry reprime/reanchor.
- Snow accumulation coverage matching effective 3D WEATHER DISTANCE.
- First-frame snow/blizzard procedural preflight and fountain fail-open behavior.
- Stale distant-front suppression while WEATHER FRONTS is OFF.
- 3D WEATHER DISTANCE 25/50/75/100%.
- SNOW ACCUMULATION ON/OFF.
- Approved snow-bank height profile.

## New regression

`tests/fronts_off_continuous_precip_8174_test.lua` exercises both shader and WorldPrecip allocation behavior. The corrected build passes 16/16. Exact 8.1.73 fails 8 of those behaviors, including the direct simulated case where fronts-OFF rain population changes as the mesoscale sample changes while the player walks.
