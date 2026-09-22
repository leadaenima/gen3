# Weather FX 8.1.82 Final Qualification

**Status: QUALIFIED for packaging, subject to the explicitly stated live-visual limitation.**

- Built from exact 8.1.81.
- Six requested player capabilities implemented as five new settings plus expanded WET GROUND, for 76 total settings.
- Defaults preserve 8.1.81 behavior.
- End-to-end settings schema, choices, persistence/runtime helpers, consumers and relevant subsystem regressions pass.
- CPU/GPU/RAM/VRAM optimizations from 8.1.81 remain green.
- Weather particle ceilings and render-distance contracts are unchanged.
- Wind-driven water is unchanged.
- Tornado cloud descent/attachment, waterspout conversion and pickup safety are unchanged.
- No fresh live framebuffer/device performance capture was produced.
