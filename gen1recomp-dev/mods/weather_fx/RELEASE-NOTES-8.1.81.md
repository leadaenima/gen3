# Weather FX 8.1.81 — Resource Lifetime / Hot-Loop Efficiency

Built directly from the frozen Weather FX 8.1.80 source checkpoint.

## Goal

Lower CPU, GPU-driver, RAM and VRAM pressure on low-power devices while preserving the exact visible weather presentation, particle populations, wind-driven water behavior, tornado cloud descent/attachment, weather distance/front ownership, animation timing, settings and assets.

## Runtime changes

### Tornado renderer

- Reuses persistent vertex rows instead of allocating thousands of point/color/vertex tables every active tornado frame.
- Uses scalar quad emission for funnel shell, outer sheath, wall cloud, ground skirt, water spray, helix and debris layers.
- Keeps the generated vertex order and numeric geometry identical to 8.1.80.
- Right-sizes the dynamic GPU mesh in 256-vertex pages rather than retaining the former 4,096-vertex minimum.
- Reuses the same mesh while capacity is sufficient and explicitly releases superseded mesh/shader resources on growth/invalidation.
- Preserves cloud-deck attachment, downward formation, roaming and waterspout presentation.

### Connected water

- Keeps the same wave trains, prevailing-wind inputs and wave equations.
- Replaces generic iteration with a numeric hot loop and avoids `sqrt` unless orbital displacement actually exceeds the existing clamp.
- Reuses the water draw context and nested curve/screen vectors instead of allocating them every draw.
- Removes temporary neighbor-list tables from shoreline BFS probes.
- Releases generated CPU ImageData immediately after its GPU image has been created.
- Physical water remains CPU-deformed in this release; the cross-host GPU-deformation rewrite remains deferred until live visual proof is available.

### GPU/VRAM lifetime

- `ParticleBatcher`, `Rainbow3D` and the NightSky streamed-world recreation path explicitly retire superseded GPU meshes instead of waiting for Lua garbage collection.
- Prevents avoidable temporary VRAM overlap when dynamic buffers grow/recreate.

### Shadow renderer

- Caches sprite-mode and identity-model shader state so repeated identical uniform sends are skipped.
- Shadow resolution, caster selection and projection math are unchanged.
- Releases the CPU-side blank ImageData after the 1x1 GPU texture is created.

## Explicitly unchanged

- Rain cap: 12,000.
- Hail cap: 45,000.
- Base snow cap: 100,000; inherited MAX blizzard population unchanged.
- 3D WEATHER DISTANCE and fronts-OFF exact rendered-world precipitation rules.
- Wind-driven water direction/response and wave equations.
- Tornado live cloud attachment/downward formation, waterspout layers and gameplay behavior.
- Shadow quality/resolution.
- Weather settings, assets, front ownership and animation timing.

## Deterministic performance/equivalence proof

These are isolated software harness measurements, not whole-game FPS claims.

- 3,510-vertex waterspout, five-run median:
  - exact 8.1.80: 2.588758 ms/frame, 842.474349 KB transient Lua allocation/frame;
  - 8.1.81: 1.303108 ms/frame, 0.318099 KB/frame;
  - median CPU reduction in this isolated renderer: ~49.7%; transient allocation reduction: ~99.96%.
- Water wave kernel, 300,000 samples, five-run median:
  - exact 8.1.80: 2738.84 ns/call;
  - 8.1.81: 1978.89 ns/call;
  - isolated kernel reduction: ~27.7%.
- Water benchmark checksum is identical: `150060.45785521017`.
- Full tornado vertex differential against exact 8.1.80 reports max absolute numeric delta `0.0` for both land and waterspout cases.

## Qualification

- 8.1.81 resource-efficiency regression: 26/26 PASS.
- Negative control against exact 8.1.80: 14 of the 26 new checks fail as required.
- Tornado 3D regression: 38/38 PASS.
- Waterspout: 5/5 PASS.
- Remote tornado render/cull: 4/4 PASS.
- Connected-water and water-ownership/style/safety regression groups PASS.
- Continuous shadow projection remains 0 Weather FX reversals.
- Revision gate: 80/80 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Feature integrity: 505/505 PASS.
- Voxel-host compatibility: 27/27 PASS.
- LÖVE sandbox: 125 shipped runtime Lua files PASS.
- Maintained `test_mod --lua`: 191/191 PASS.
- All 125 shipped runtime Lua files compile with `texluac -p`.
- Inherited 8.1.71–8.1.78 precipitation/front/distance regressions PASS.

The historical `run_all.py --lua` superset still contains two stale 8.1.51 assumptions that already fail on exact 8.1.80: a hard-coded 70-setting count and a MAX profile missing the later `weatherRenderDistance` row. Current schema is 71 and the maintained settings/runtime suites are green; 8.1.81 does not alter settings to satisfy obsolete historical snapshots.

No live framebuffer or device FPS benchmark was captured in this environment.
