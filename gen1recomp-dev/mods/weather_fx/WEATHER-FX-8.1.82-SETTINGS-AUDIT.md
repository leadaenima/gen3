# Weather FX 8.1.82 — New Settings Audit

## Schema

Weather FX 8.1.82 exposes **76** player-facing settings. This is five new rows plus an expansion of the existing WET GROUND row.

### LIGHTNING FREQUENCY
- RARE = 0.45 cadence multiplier
- LOW = 0.70
- NORMAL = 1.00 (exact 8.1.81 behavior)
- HIGH = 1.50
- EXTREME = 2.25
- Consumers: main `Lightning.update` scheduler and regional `StormCells` scheduler.

### TORNADO DURATION
- SHORT = 0.50 mature roam duration
- NORMAL = 1.00 (exact 8.1.81 behavior)
- LONG = 1.75
- Only `roamFor` is scaled. Formation/descent, waterspout conversion, pickup/transfer safety and rope dissipation are unchanged.

### CLOUD DENSITY
- LOW = 0.72 puff scale / +0.14 occupancy gate bias
- NORMAL = 1.00 / 0.00 (exact 8.1.81 behavior)
- HIGH = 1.22 / -0.08
- VERY HIGH = 1.45 / -0.14
- Consumers: primary persistent cloud lattice plus integrated front cloud-bank puff density.
- Precipitation authority is not changed.

### NIGHT SKY BRIGHTNESS
- LOW = 0.65
- NORMAL = 1.00 (exact 8.1.81 behavior)
- HIGH = 1.30
- Applies to stars, planets, constellations and Milky Way in world, flat-2D and projected fallback paths.
- Does not scale sun/moon body alpha, aurora or meteors.

### WEATHER SCREEN EFFECTS
- FULL = 1.00 (exact 8.1.81 behavior)
- REDUCED = 0.50
- OFF = 0.00
- Applies to camera-sized 2D/battle grading, lightning wash, psychic wash, compatibility veil and glare.
- Does not attenuate world precipitation, clouds, tornadoes, physical lightning bolts, thunder or 3D physical atmosphere/lightning.

### WET GROUND
- DEFAULT = installed config authority
- OFF = 0.00 visible wetness
- LOW = 0.50
- NORMAL = legacy stored token `on` at 1.00
- HIGH = 1.35
- Visible puddle/wetness strength changes; rainfall and underlying surface wetness simulation do not.

## Executable evidence

- release-specific additions: 50/50 PASS
- negative control on exact 8.1.81: 8 PASS / 42 FAIL (expected failure)
- settings runtime: 731/731 PASS
- descriptions/completeness: 1,869/1,869 PASS
- live-change chain: 17/17 PASS
- advanced settings pipeline: 42/42 PASS
- complete menu interaction: 2,226/2,226 PASS
- runtime consumer audit: 267/267 PASS
- simultaneous MAX profile: 10/10 PASS

No fresh live framebuffer inspection of all new choices was available in this environment.
