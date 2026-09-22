# Weather FX 8.2.5 — Requested 3D Snow Density Multipliers

Built directly from exact Weather FX 8.2.4. This release changes only the logical visible 3D snow population for the requested player-facing weather types.

- SNOW (`SNOW_LIGHT`; legacy `SNOW` compatibility alias): **2x** 8.2.4.
- TSNOW (`THUNDERSNOW`): **2x** 8.2.4.
- DRAGON (`DRAGONSTORM`): **2x** 8.2.4.
- BLIZZARD: **4x** 8.2.4.

No other weather density or behavior is changed. The 8.2.4 phone-safe CPU fallback budgets are intentionally not multiplied; the requested increase applies to the logical/procedural 3D visual population. Accumulation, LOD, render distance, smooth animation, no-emitter continuity, clouds, RAVE, celestial and battle behavior remain unchanged.
