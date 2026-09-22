# Weather FX 8.1.77 Final Qualification

Weather FX 8.1.77 is qualified as the next installable baseline after focused executable regression, exact 8.1.76 negative control, Lua/LuaJIT checks, inherited precipitation and snow regressions, performance/feature audits, compatibility checks, settings validation, revision gate, and exact-package replay.

Primary correction: the remaining map-edge/turn rain interruption path is removed from both possible render backends. CPU fallback rain is now stable world-space/no-camera-cull, while procedural rain advances on a monotonic render clock with tighter world-anchor handoffs.

No fresh live-game framebuffer capture was produced; the user's real host remains the final visual confirmation.
