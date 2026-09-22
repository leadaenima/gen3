# Weather FX 8.1.55 — Smooth World-Anchored Snow Motion

Built directly from exact Weather FX 8.1.54.

## What changed

- **Snow fall no longer stutters from a stepped/repeated simulation clock.** The complete procedural snow/blizzard visual layer now advances from a dedicated monotonic presentation clock. Long pause/debugger gaps are clamped so resume cannot jump the entire field.
- **Snow no longer moves with the player.** The old 64-unit anchor was interpolated toward each new player-centred cell, which physically dragged the whole GPU snow volume across the world. That interpolation is removed.
- **No blizzard snap-back overhead.** Snow now streams between immutable 256-unit world anchors. When a new region is needed, stable instance ownership is progressively transferred from the old fixed field to the new fixed field; no intermediate sliding anchor exists.
- **Particle density is unchanged.** Handoff preserves exactly the requested snow/blizzard instance count. This release does not increase or reduce snow density.
- **8.1.54 virtualization remains intact.** The GPU still owns the complete visible snow population after driver proof while Lua retains only the bounded interaction probes.
- **Snow ground collision remains disabled** as requested in 8.1.54.

## Performance

The handoff never draws two complete snow populations. The authored instance count is split between the old/new fixed anchors, so total submitted instances remain unchanged. A handoff can add at most one extra instanced chunk/draw boundary because one population is split across two anchors; no new framebuffer, texture, particle pool or large resident buffer is introduced.
