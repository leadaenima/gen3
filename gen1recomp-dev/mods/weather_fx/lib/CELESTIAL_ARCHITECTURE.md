# Weather FX 5.0 Celestial Ownership

`CelestialRenderer2` is the single public Weather FX celestial facade. Strict-3D projected presentation calls `CelestialRenderer2.drawProjected()` once per scene; it orders the deep-sky and sun/moon fallback passes while `CelestialEngine` remains the astronomy/optics authority and `NightSky` remains the fixed-world geometry catalogue. This removes direct duplicate Dramaless celestial ownership without changing the established world-space VP projection.

Deep sky uses a continuous 0.25x presentation phase around the established latitude-tilted celestial-pole axis. The normal star catalogue contains 5,120 stars; all nine planets survive every quality tier; the restored 25-subject high-detail constellation catalogue from 8.1.6 spans both celestial hemispheres and receives stronger cloud attenuation.

# Celestial architecture — Weather FX 4.35.0

## Core rule
The camera is only the observer. Celestial bodies, stars, lighting and cloud shadows live in world coordinates and are driven by one astronomical/environment snapshot.

```text
Host/game clock
      ↓
CelestialSim (astronomy)
      ↓
CelestialEngine (weather + clouds + pollution + eclipses)
      ├─→ sky bands / 2D sun + moon
      ├─→ NightSky / constellations / Milky Way
      ├─→ CelestialBodies 3D sun + phased moon
      ├─→ voxel DayNight + ShadowMap (in-memory adapter)
      ├─→ WorldCelestialLighting cloud shadows
      ├─→ fog / rays / precipitation scattering
      └─→ puddle + voxel-water reflection state
```

## Astronomy
- World basis: +X east, +Y up, +Z south.
- Latitude defaults to 35° and can be changed in config.
- Solar declination follows a 365.2422-day tropical year.
- Sunrise/sunset/day length vary continuously with season.
- Twilight stages: DAY → GOLDEN → CIVIL → NAUTICAL → ASTRONOMICAL → NIGHT.
- Moon phase uses a 29.530588-day synodic month; nodal alignment uses 27.212221 days.
- Sun and moon are independently solved celestial directions; the moon is not a camera-locked or permanently-opposite prop.
- Solar/lunar eclipses require phase alignment plus lunar-node proximity and produce smooth partial-to-near-total severity.

## Stars and deep sky
- 2,560 fixed directions cover the full celestial sphere.
- The vault rotates at sidereal rate around the north celestial pole.
- Pokémon constellations use that same physical vault transform.
- A Milky Way band shares the same sphere.
- Building light pollution removes faint stars gradually across a broad 4–48-cell distance field, suppresses the Milky Way more strongly and brightens the low night horizon. Deep-sky objects are NIGHT-only; twilight never renders stars/planets.

## World lighting
- Direct sun/moon direction is published once per frame.
- Voxel DayNight/ShadowMap receives the same in-memory rig; host files/options are never edited.
- Live cloud transmission attenuates direct light/disc visibility along the celestial ray.
- Moving cloud shadows are terrain-conforming world geometry sampled against `VoxelScene.groundAt()`.
- Fog/rays and weather particles use the same celestial colour/intensity.
- Wet/puddle and compatible voxel-water paths receive sun/moon reflection direction, colour, strength, phase and day fraction.

## Rendering ownership
- Weather FX owns its celestial simulation even when a voxel host owns the clock. The host clock is an input, not a competing astronomical system.
- 3D moon phase is actual generated geometry (lit/dark cells + earthshine), not metadata on a permanently full disc.
- The moon is alpha-blended after the additive sun so eclipse silhouettes are possible.
- Cloud/weather attenuation can physically hide either disc while diffuse ambient light remains.
