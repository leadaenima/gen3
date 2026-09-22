# Weather FX 8.1.54 — Full-Visual Precipitation Virtualization / Snow Collision Suspension

Built directly from exact Weather FX 8.1.53.

## What changed

- **Near-field precipitation no longer has to exist as thousands of Lua visual particles on capable GPUs.** After the existing procedural backend completes a real invisible driver probe, rain, snow/blizzard, hail, sand and ash can move their complete authored visual population onto the zero-upload GPU fields.
- **No particle-count reduction.** The logical/visible targets stay authored at the current quality caps. At MAX this still means rain 12,000, snow 100,000, blizzard 200,000, hail 45,000, sand 43,200 and ash 10,800.
- **Tiny CPU interaction populations only where still useful.** Proven full-GPU rain retains at most 96 interaction probes; proven full-GPU snow retains at most 96 face-contact probes. Hail, sand and ash require no gameplay collision and can use zero CPU visual cards. Leaves/debris remain fully physical because their collision/settling behavior is intentional.
- **Retired CPU particle pools are released.** After GPU ownership is proven, old large rain/snow/grain high-water arrays are compacted to the remaining interaction population rather than staying resident in RAM.
- **Fail-open compatibility remains.** Until a real instanced draw succeeds, or if the procedural backend is unsupported, the existing complete CPU visual path remains authoritative.
- **Snow ground collision is temporarily disabled.** Falling snow remains fully visible, but SnowPack ground collision, settling, banks and footprints are suspended because the current ground resolver is not reliable enough. The SnowPack module remains shipped for later repair; no fake collision result is substituted.
- **Near-eye rain safety is preserved on the full GPU field.** Procedural rain shrinks/fades extremely close streaks to avoid giant camera-space bars while keeping world-space precipitation density intact.

## Preserved

8.1.54 preserves 8.1.53 spatial cloud/sun terrain lighting; 8.1.52 independent persistent storm fronts, physical distance audio and weather authority; 8.1.51 zero-upload distant-front instancing; all 68 player settings; full celestial catalogue; water systems; battles; lightning; tornadoes; wind; seasons and existing compatibility fallbacks.
