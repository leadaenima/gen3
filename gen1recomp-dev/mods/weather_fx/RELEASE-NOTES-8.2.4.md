# Weather FX 8.2.4 — Full 3D Snow Path Performance Repair

8.2.4 is built directly from exact 8.2.3 after a full executable audit of the complete 3D snow path rather than another shader-only optimization pass.

## What the audit found

Even with snow accumulation disabled, pure 3D snowfall still constructed SnowPack support context every frame, exact-resolved invisible CPU snow probes against terrain, advanced SnowPack, and ran rain-interaction bookkeeping. Separately, if the procedural GPU snow backend was unavailable or failed its real draw proof, the compatibility path could send the complete logical storm — up to 100,000 SNOW or 200,000 BLIZZARD identities — into the legacy CPU integration/dynamic-mesh renderer.

## 8.2.4 repair

With accumulation OFF, pure 3D snow now performs no SnowPack context construction, no exact support sweeps, no SnowPack update/staging, and no rain-only interaction loop. With accumulation ON, aggregate deposition remains active while support context, ground-bank staging and footprint staging refresh near 10 Hz unless a map change or meaningful movement requires an immediate refresh. Procedural visual snow does not individually exact-sweep terrain.

On the proven procedural GPU path, third-person snow retains one CPU telemetry/lifecycle identity; first-person uses at most 16 face-contact probes. If procedural GPU snow cannot run, the legacy visible CPU fallback is bounded by the established quality budgets: 360 POTATO, 720 LOW, 1,640 MEDIUM, 3,200 HIGH, and 4,800 MAX.

The existing 8.2.3 far-point/near-crystal LOD, smooth per-render-frame movement, full render-distance field, continuous no-moving-emitter behavior, and authored full GPU populations remain unchanged.

## Measured executable path evidence

The instrumented 8.2.3 accumulation-OFF path performed 600 SnowPack context builds over 600 frames and 9,600–57,600 exact flake support sweeps depending on quality. The repaired pure-snow accumulation-OFF path performs 0 context builds, 0 exact support sweeps and 0 SnowPack updates over the same 600-frame harness. Accumulation ON stages support/ground/foot data at roughly 10 Hz while falling snow remains frame-rate animated. These are code-path/work-count measurements, not claimed phone FPS.

Exact 8.2.3 fails 6 of the 7 new full-path regression checks.
