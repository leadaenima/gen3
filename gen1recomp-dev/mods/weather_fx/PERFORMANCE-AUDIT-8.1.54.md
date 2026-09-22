# Weather FX 8.1.54 — Precipitation CPU/RAM Virtualization Audit

## Goal

Reduce CPU integration, CPU-to-GPU staging and retained Lua particle state without lowering authored weather counts, draw distance or presentation quality.

## Architecture

Weather FX already had deterministic procedural GPU fields for the far portion of rain/snow/hail/sand/ash. 8.1.54 extends those proven fields to own the complete **visual** population after a real driver-level instanced draw has succeeded.

The CPU is then reserved only for interactions which cannot be represented by the visual shader:

- rain: <=96 interaction probes;
- snow/blizzard: <=96 face-contact probes;
- hail/sand/ash: 0 CPU visual cards;
- debris/leaves: unchanged and fully physical.

If the real GPU proof has not succeeded, Weather FX retains the complete legacy CPU visual population. This makes the optimization fail-open rather than assuming an advertised capability works.

## MAX authored population preservation

The existing MAX quality ceilings remain unchanged:

- rain: 12,000;
- snow: 100,000;
- blizzard: 200,000;
- hail: 45,000;
- sand: 43,200;
- debris/leaves: 3,600;
- ash: 10,800.

For a proven GPU backend, a 200,000-flake MAX blizzard therefore needs at most 96 Lua interaction probes for the visual-weather path: **199,904 visual flakes no longer require individual Lua integration records**. This is a state/workload accounting result, not a claim of whole-game FPS multiplication.

## RAM behavior

8.1.54 no longer keeps the retired high-water CPU arrays just because a dense weather type was previously active. Once GPU ownership is established, rain/snow/grain pools are compacted to the remaining physical interaction population. Noninteractive hail/sand/ash cards can therefore release their entire CPU visual pool.

## GPU / VRAM behavior

The release reuses the existing immutable `InstanceSeedBuffer` and procedural precipitation shaders. It adds no per-particle dynamic GPU buffer, no new framebuffer, no precipitation texture atlas, and no new large resident VRAM pool. The GPU performs more of the already-authored visual-position synthesis, while CPU vertex/card staging is removed from the fully virtualized families.

## Snow collision suspension

Ground collision/settling for falling snow is intentionally disabled in this release because the current SnowPack ground resolver is producing incorrect results. This removes broken ground-interaction work rather than pretending it is valid. Falling snow visuals are unchanged in logical population. SnowPack source/API remains present for a future corrected re-enable.
