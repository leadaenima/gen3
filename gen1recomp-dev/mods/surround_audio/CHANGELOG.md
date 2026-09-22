# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 1.7.0

### Changed

- The pan-aware worker no longer touches the sandboxed `love.thread` /
  `love.filesystem` (both are blocked to mods on the new API). The mod now
  reaches the real LÖVE table through `require("love")` — the deny list
  blocks `love.*` but lets the bare root through — and degrades to
  routing-only instead of crashing if a future engine closes that gap.

## 1.6.1

### Changed

- Display name is now "Stereo 5.1 Audio": the Gen 1 font has no "&"
  glyph, so the old name rendered with a blank gap in menus.

## 1.6.0

### Changed

- The toggle hotkey moved: **M** on keyboard, **Select + R** on a
  controller (the combo fires when the second half goes down; either
  order works). The old L / Q binding is gone.

## 1.5.0

### Changed

- STEREO now forces Crystal's split: channels 1-2 to the left speaker,
  3-4 to the right. Gen 1 songs never write the pan register (measured:
  0/24 real songs differed between the speakers), so honoring the song's
  panning was silent. With the forced split, 23/24 real songs separate
  audibly between the speakers.
- Each split side scales /2 so STEREO is as loud as MONO.

## 1.4.0

### Added

- The pan-aware synthesis worker is back as the MONO/STEREO engine: it
  mixes the chip music at the render level, so it works on any audio
  backend. STEREO honors the song's per-channel panning, MONO sums every
  channel into both speakers.
- A one-line probe (`surround_audio_probe.txt` in the save dir) recording
  the LÖVE version, whether EFX is available, and whether the worker
  substitution took -- so a silent failure is diagnosable.
- Toggling restarts the current song (Crystal's RestartMapMusic) with the
  new pan mode, so the change is heard immediately.

### Changed

- The EFX reverb widening is gone. This LÖVE build compiles EFX out
  (`love.audio.isEFXsupported() == false`), which also disables the
  engine's own MUSIC FILTER -- no filter/effect DSP can work here, only
  the render-level mix can.

### Fixed

- The song restart no longer swallows the wrong arguments: the replay now
  actually starts, so toggling no longer silences the music until the
  next map change.

## 1.2.0

### Added

- The widening is now an EFX reverb applied through the same
  `Source:setFilter` slot the engine's MUSIC FILTER option uses: a small,
  dark room sent across every output channel — the rear speakers on 5.1,
  extra width on stereo. STEREO = widened, MONO = the straight Game Boy mix.
- Everything now rides the public LÖVE audio API (`setFilter`, `setPosition`,
  `setDistanceModel`); no engine internals, no thread substitution.

### Removed

- The pan-aware worker-thread substitution (replaced by the filter effect).

### Fixed

- Toggling no longer stops the current song: the effect applies live to the
  playing source, so the change is heard instantly and the music keeps
  playing. (The previous restart path could leave the music silent until
  the next map change.)

## 1.1.0

### Added

- The Crystal SOUND option: **MONO** mixes every music channel into both
  speakers, **STEREO** honors the song's per-channel panning. Modeled on
  pokecrystal's `Options_Sound` / `Music_StereoPanning`.
- A pan-aware synthesis worker: the mod substitutes `src/core/chip_worker.lua`
  through `love.thread.newThread` and steers it with a `pan` command, so the
  mix changes without any engine modification.
- Toggling restarts the current song, like Crystal's `RestartMapMusic`, so
  the change is heard immediately instead of after the ~6s playback buffer.
- A confirm blip on every toggle (higher note for STEREO, lower for MONO).
- A toggle hotkey: **L** (gamepad `leftshoulder`, keyboard `Q`).

### Changed

- The OPTIONS row is now Crystal's `SOUND: MONO / STEREO`.
- The SFX bus (beeps, hits, cries, fanfares, the low-health alarm) is
  routed to the center channel in both modes.

### Fixed

- Dev-mode hot reload no longer double-wraps the input handlers, which used
  to make one L press toggle twice and cancel out.

## 1.0.0

### Added

- Surround routing: music stays on the L/R speakers, every SFX, cry,
  fanfare and alarm is centered (the center channel on 5.1 output).
- A SURROUND row in the OPTIONS menu, persisted in `options.lua`.
