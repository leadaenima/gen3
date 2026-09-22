# Stereo & 5.1 Audio

Pokémon Crystal's SOUND option, ported to the 8-bit music of Red/Blue/Yellow:
**MONO** sums every music channel into both speakers, **STEREO** splits the
channels: 1-2 to the left speaker, 3-4 to the right. On top of that, every sound effect (menu beeps,
battle hits, cries, fanfares, the low-health alarm) plays from the center
channel on 5.1 output, or the middle of the image on stereo.

## Try it

```sh
python3 tools/modkit.py validate mods/surround_audio --base imported
luajit mods/surround_audio/tests/surround_audio_test.lua
```

Enable it (`surround_audio = true` under `mods` in `options.lua`, or via the
mod manager), then:

1. Press **M** (keyboard) or **Select + R** (gamepad) to switch between
   MONO and STEREO. The current song restarts (Crystal's
   `RestartMapMusic`) so you hear the change immediately. A confirm blip
   plays: high note for STEREO, low note for MONO.
2. Or open **OPTIONS** and cycle the **SOUND** row.
3. The choice is saved to `options.lua`, so it survives restarts and
   New Game.

## How it works

Crystal's option is two lines of asm: when STEREO is on, the song's pan
bytes are honored; when off, the pan byte is skipped — every channel to
both speakers. This mod implements the same contract on this engine's
synthesizer, with one twist: **Gen 1 songs never write the pan register**
(measured: 0/24 real songs differ between the speakers), so honoring the
song would be silent. STEREO therefore forces Crystal's split — channels
1-2 to the left, 3-4 to the right:

- **STEREO** renders each buffer as two mixes: channels 1+2 scaled /2 to
  the left speaker, channels 3+4 scaled /2 to the right.
- **MONO** renders through `Engine:sample()` — the pan-less sum of all four
  channels — written to both speakers.

With the forced split, 23/24 real songs separate audibly between the
speakers.

The chip music mix happens on the synthesis worker thread
(`src/core/chip_worker.lua`), created once by
`love.thread.newThread("src/core/chip_worker.lua")`. The mod substitutes a
pan-aware copy of that worker — LÖVE treats a newline-bearing string as
inline source — and steers it with a `pan` command pushed onto the engine's
`chipaudio_cmd` channel. Toggling also restarts the current song, so the
new mode is heard on the next buffer instead of after the ~6s playback
look-ahead. If the engine ever changes the worker so the substitution can't
be made, the mod degrades to the vanilla worker instead of breaking.

The engine's mod sandbox blocks `love.thread` and `love.filesystem`, and
`mod.fetch` only covers background HTTP — it can't reach the worker. The mod
gets the real LÖVE table through `require("love")` (the deny list refuses
`love.*` but lets the bare root through) and degrades to routing-only if a
future engine closes that path.

**Why not a filter/effect plugin?** This LÖVE build compiles OpenAL's EFX
extension out (`love.audio.isEFXsupported()` is false), which disables every
DSP — `Source:setFilter` beyond the basic types, all reverb/echo effects,
and the engine's own MUSIC FILTER option. Only the render-level mix above
can change the music, so the mod works at the synth instead of the speaker.

The SFX half uses positional audio: every `Source` is created through
`love.audio.newSource` / `newQueueableSource`, so the mod wraps those two
factories and classifies by kind — `static` is SFX, `stream` and queueable
are music. SFX sources get `setPosition(0, 0, -1)` + `setRelative(true)`
(azimuth zero = the center channel on 5.1), and the distance model is set
to `none` so nothing attenuates. Toggling off restores the engine defaults.

## Diagnostics

If STEREO ever sounds identical to MONO, the save dir gets a one-line
probe file (`surround_audio_probe.txt`):

- `efx=false` means the build has no DSP (expected for this LÖVE build).
- `worker=1` means the pan-aware worker was substituted; `worker=0` means
  the engine's worker changed shape and the mod degraded to vanilla.

## Notes

- On stereo speakers, MONO vs STEREO is the audible difference: the music
  snaps between the centered mix and the per-channel L/R split. The center
  SFX channel is what lights up on a real 5.1 device.
- The engine's own audio options (volumes, filter) are unaffected; the
  MUSIC FILTER is inert on this LÖVE build anyway.
- Thanks to pret/pokecrystal for the option semantics this ports.
