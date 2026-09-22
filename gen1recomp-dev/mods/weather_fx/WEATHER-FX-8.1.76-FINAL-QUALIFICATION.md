# Weather FX 8.1.76 Final Qualification

Weather FX 8.1.76 is qualified as the next installable baseline after source-level executable regression, negative control against exact 8.1.75, Lua syntax/LuaJIT checks, precipitation inheritance gates, performance/feature audits, compatibility checks, and exact-package replay.

Primary corrections: active fronts-OFF rain can no longer be hidden by a transient draw-frame weather bag; ledge elevation no longer rephases the procedural rain column; and the rain visual is now a thin tapered translucent blue-grey water streak rather than a broad white rectangle. Explicit rain OFF and authored weather transitions remain authoritative.

No fresh live-game framebuffer capture was produced for this release; final visual confirmation remains the user's in-game host test.
