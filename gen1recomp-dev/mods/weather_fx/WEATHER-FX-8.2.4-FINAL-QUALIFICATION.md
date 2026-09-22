# Weather FX 8.2.4 Final Qualification

**Status: source and candidate-package qualified; final package requires exact-byte replay recorded in the external validation file.**

8.2.4 is the complete 3D-snow-path performance repair built directly from exact 8.2.3. It removes SnowPack/support work from pure 3D snow when accumulation is OFF, stages expensive pure-snow support/ground/foot work near 10 Hz when accumulation is ON, reduces proven-GPU CPU interaction snow to one third-person telemetry identity or at most 16 first-person probes, and hard-caps the legacy CPU-visible fallback to 360/720/1,640/3,200/4,800 flakes by quality if the procedural GPU renderer cannot run.

The full logical GPU snow field, smooth per-render-frame movement, 8.2.3 point/detail LOD, live render distance, no-emitter continuity, and all established non-snow weather behavior are preserved.

Source qualification: 7/7 full-path audit, 122/122 maintained programs, 198/198 `test_mod`, 80/80 revision gate, 129/129 runtime Lua compile. Exact 8.2.3 fails 6/7 new checks. The candidate ZIP repeats those same results after extraction.

No live FPS claim is made for the user's exact phone or desktop GPU; final real-device FPS remains a device measurement.
