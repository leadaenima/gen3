# Weather FX 8.1.30 — Realistic Progressive Ice

8.1.30 is a focused visual/continuity refinement of the 8.1.29 Connected Flat-World Hydrosphere. The water-body topology, tides, wind-driven wave authority, rain-ripple cap, winter thermal state, load-bearing threshold, Surf safety and collision rules are preserved.

## Ice presentation
- Replaces the old 32×32 pale/noisy ice texture and straight modular crack stripes with a 128×128 seamless procedural material.
- Clear blue ice, cloudy frost inclusions, trapped-air flecks, crack halos, long bowed primary fractures and finer secondary branches are generated deterministically.
- Ice UV scale is widened to 192 world units so large frozen bodies do not read as a rapidly repeating floor tile. Liquid water keeps its prior mapping.
- Partial freezing is now visible. From early skim ice through near-load-bearing freeze, a bounded eight-stage translucent ice skin progressively covers the still-reflective water surface.
- At the existing 0.90 load-bearing threshold the body becomes continuous, wave-free solid ice exactly as before for gameplay.

## Gameplay / water physics preservation
- No cartridge water classification, Surf movement, entity/bounds collision, freeze/thaw rate, load-bearing threshold, tide equation or wave equation is changed.
- Player world position is not modified by wave visuals in this release. 8.1.29 did not contain wave-coupled player bobbing, and 8.1.30 deliberately does not fake it by moving collision/gameplay coordinates. A future bobbing feature should be presentation-only and sample the same wave field used by Voxel Realism.
- No mountain/orographic assumptions are introduced.
