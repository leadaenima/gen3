# Weather FX 8.1.65 — Final Audit

## Baseline and runtime scope

Built directly from exact 8.1.64 (`0be4d9f362f61ea2e14194a46c36949c3da8944493da81678e09e998c7c9b443`).

Behavioral runtime delta:

- `lib/Tornado.lua`
- `lib/voxel_atmos/Tornado3D.lua`

All other frozen runtime files must remain byte-identical to the 8.1.64 runtime baseline.

## Root cause and repair

The old persistent tornado root-frame rebasing was correct only while the funnel remained on the current map or one immediate rendered neighbor. The voxel snapshot deliberately does not contain an unlimited map graph, so a funnel left two maps behind had no live region in which to advance and was pushed back/frozen at the load-radius edge.

8.1.65 stores map-local tornado coordinates, resolves off-screen motion against canonical authored outdoor connections, and keeps remote lifecycle state advancing. Remote entities are isolated from current-root terrain/contact sampling. `Tornado3D` culls entities flagged off-screen. Re-entry is a projection of the same persistent entity, not a spawn.

## Regression proof

- `tests/tornado_remote_map_roam_8165_test.lua`: 12/12 PASS.
- exact 8.1.64 negative control for the same regression: 4/12 PASS, 8 failures.
- `tests/tornado_remote_render_cull_8165_test.lua`: 4/4 PASS.
- exact 8.1.64 negative control: 2/4 PASS, 2 failures.
- maintained `tornado_3d_test.lua`: 38/38 PASS.
- maintained pickup semantics: 20/20 PASS.
- maintained map persistence: 10/10 PASS.
- maintained real transfer: 5/5 PASS.
- maintained walk contact: 8/8 PASS.
- maintained safe destinations: 23/23 PASS.
- maintained waterspout presentation: 5/5 PASS.

The historical 8.1.57 relocation test still has the same two stale expectations on exact 8.1.64 and 8.1.65; it is not a new regression and is not counted as a release pass.

## Performance / presentation

Maximum active tornado count remains bounded by the existing configuration. Off-screen funnels now update only compact storm state and do not build Tornado3D geometry. Visible funnel geometry/density is unchanged.

## Audit boundary

This release fixes a state/persistence seam primarily observable when the funnel is outside the rendered map set. Executable contracts prove movement, connection crossing, culling and same-entity re-entry. No new manual real-host framebuffer capture is claimed for 8.1.65.
