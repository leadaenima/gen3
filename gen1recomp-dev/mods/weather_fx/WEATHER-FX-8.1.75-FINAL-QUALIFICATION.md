# Weather FX 8.1.75 Final Qualification

Weather FX 8.1.75 is qualified as the next installable baseline after exact-package replay.

Primary correction: WEATHER FRONTS OFF no longer falls back to a player-centred visible rain pool at low logical populations. Once validated, the world-space procedural rain renderer owns every nonzero visible rain population, while <=96 CPU drops remain only as interaction probes. A same-weather continuity latch prevents a transient live-channel zero from stopping rain while walking, without overriding explicit rain OFF or authored transitions.

All 8.1.74 uniform-field behavior and the 8.1.73/8.1.72 snow, hail, map-entry, weather-distance and fountain protections remain inherited. No fresh live-game framebuffer capture was produced for this release.
