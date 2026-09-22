# Weather FX 8.1.77 — Map-Edge / Turn Rain Continuity

## What changed

- Fixed the remaining fronts-OFF rain slowdown/start-stop reports near map edges and when turning the camera.
- The CPU fallback is now a true world-space field: it uses fixed snapped world anchors, recycles around that world anchor rather than the avatar, and never uses camera-forward visibility culling. This matters on hosts where procedural instancing is unavailable or rejected by Weather FX's safety validation.
- Procedural rain animation now advances from a monotonic render clock rather than only the gameplay/update clock. Short map-streaming or turn-state update stalls can no longer make the whole rain phase slow/freeze before resuming.
- CPU rain integration catches up across short host cadence stalls with a bounded 0.25-second safety cap.
- Procedural anchor cells are tighter so the rain field remains much closer to the observer and a camera turn cannot expose the opposite edge of the configured weather circle.

## Preserved

- 8.1.76 thin tapered translucent blue-grey water-streak rain model.
- Ledge-hop fall-column stabilization and update-owned rain draw authority.
- WEATHER FRONTS OFF uniform precipitation behavior.
- 3D WEATHER DISTANCE 25/50/75/100% semantics.
- Map-entry reprime, SnowPack distance matching, snow/blizzard fountain protection, hail-tube validation, and SNOW ACCUMULATION toggle.

## Qualification

- New map-edge/turn continuity regression: 16/16 PASS.
- Exact 8.1.76 negative control: 7 PASS / 9 FAIL (expected).
- Rain ledge continuity: 14/14 PASS.
- Rain walk continuity: 12/12 PASS.
- Fronts-OFF continuous precipitation: 16/16 PASS.
- Precipitation streaming/map-entry: 12/12 PASS.
- Fronts-OFF exact render distance: 9/9 PASS.
- Fronts-OFF world precipitation: 9/9 PASS.
- Procedural instancing validation: 6/6 PASS.
- World-space precipitation: 33/33 PASS.
- Rain/cloud-bank visibility: 9/9 PASS.
- Precipitation virtualization: 23/23 PASS.
- Near precipitation virtualization: 17/17 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- Snow accumulation: 13/13 PASS.
- Snow point-plume: 9/9 PASS.
- Snow-bank distribution: 13/13 PASS.
- Snow motion: 10/10 PASS.
- LuaJIT update limit guard: PASS at 51 direct upvalues.
- Performance/regression static gate: 42/42 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Feature integrity: 505/505 PASS.
- Aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.
- Settings/runtime audit: 254/254 PASS.
- Revision gate: 80/80 PASS.
- `tools/test_mod.py --lua`: 191/191 PASS.

No fresh live-game framebuffer capture was produced for 8.1.77. The user's host remains the final visual confirmation.
