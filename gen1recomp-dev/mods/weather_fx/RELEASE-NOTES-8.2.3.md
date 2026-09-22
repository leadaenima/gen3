# Weather FX 8.2.3 — Mobile 3D Snow Performance Repair

This release is a structural 3D-snow performance redesign for low-powered phones while retaining max-settings desktop behavior.

## Falling snow

The full authored logical field is preserved and continues to advance every rendered frame. Distant flakes that are too small to resolve as individual snow crystals are represented by one-vertex GPU points with the same world-space motion. Only the near area uses the detailed crystalline billboard shader. This dramatically reduces vertex work and translucent overdraw without lowering the logical snow count, render distance, weather intensity, or animation cadence.

POTATO's 1,600-flake field uses 1,600 point carriers and 64 detailed near crystals. MAX SNOW keeps 100,000 point carriers plus 1,778 detailed crystals. MAX BLIZZARD keeps 200,000 point carriers plus 3,556 detailed crystals.

## Snow-only CPU/upload work

The persistent ground snow system no longer rescans and reuploads identical accumulated banks every rendered frame. SnowPack staging updates at 10 Hz or immediately after meaningful movement/map changes, the physical bank mesh is reused until the staged snapshot changes, and an unchanged snow-surface coverage texture is not rerasterized/reuploaded. Invisible exact-terrain snow probes are quality-bounded from 16 on POTATO to 96 on MAX; visible GPU snow density is unaffected.

## Preserved behavior

The 8.2.0+ continuous no-moving-emitter/no-whole-field-reset model is retained. Snow motion remains smooth per rendered frame. The full 3D precipitation distance contract, accumulation visuals, RAVE behavior, cloud-bank zenith repair, sun/moon repair, battle behavior, and existing weather families remain intact.

## Truth boundary

The release has executable workload/invariant tests but this environment cannot measure live FPS on the user's exact phone or desktop GPU. Real-device FPS remains the final performance measurement.
