# Weather FX 7 Environment SDK

Weather FX 7 exposes a read-only/opt-in environment layer through `mod.exports`.

## Core reads
- `environmentSnapshot(x,z)` — aggregate local environment state.
- `worldClimate(x,z)` — coarse whole-world climate cell.
- `mesoscaleWeather(x,z)` — current 8.0.8 moving local moisture/front band (read-only).
- `weatherForecast(x,z,seconds)` — deterministic future climate estimate, including 8.0.8 mesoscale band advection when initialized.
- `weatherForecastTimeline(x,z,steps,stepSeconds)` — forecast series.
- `severeWeather()` — current severe-weather classification.
- `environmentLighting()` — environmental lighting state.
- `accumulationGeometry()` — snow/leaf/puddle/mud depth descriptors.
- `terrainPhysics(x,z)` — opt-in traction/speed/wind response.

## Persistence
- `environmentSave()` returns a versioned serializable table.
- `environmentRestore(data)` restores compatible climate/surface state.

## Plugin registry
`environmentPlugins.register(owner, capability, fn)` registers an in-memory namespaced provider. Weather FX never edits another mod's files. Providers should treat all Weather FX snapshots as read-only.

## Event bus
Existing `onEnvironmentEvent(kind, fn)` / `environmentEvents(since)` remain supported. Weather FX 7 adds `severe_weather_change` transitions.
