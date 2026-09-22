# Weather FX 8.2.0 — Global Cloud Zenith + Continuous Snow Field + RAVE Mixed/Battle Presentation

Built directly from exact Weather FX 8.1.99.

## 3D cloud-bank look-up repair
The cloud-bank disappearance at the edge of the view while pitching upward was shared by the 3D cloud system, not just RAVE. 8.2.0 moves the bounded cloud-lattice search to the stable gameplay/world precipitation anchor and extends the existing world-space overhead admission rule to every 3D cloud family. Camera pitch now changes projection only; it no longer changes which nearby physical cloud cells exist.

## RAVE cloud population and 2D-weather support
RAVE now doubles the actual volumetric lobe count after quality and player cloud-density scaling, rather than merely increasing cloud size or tint. When WEATHER RENDERING is 2D, classic 2D weather ownership remains intact while the dedicated RAVE fog, floor pools, cloud bank (when enabled), and laser rig continue to render in the voxel scene. Ordinary 3D precipitation, puddles and weather fog are not enabled by this exception.

## RAVE lasers in battle
World-backed battles carry the pre-battle RAVE presentation independently of `battle.field.weather`, so battle rain/snow/mechanics remain authoritative while the laser show stays visible. Opaque/classic battle canvases receive a bounded additive 12-beam RAVE fallback so the party presentation is not lost when the world scene is hidden.

## SNOW / BLIZZARD moving-emitter repair
The remaining overhead snow emitter was caused by the procedural field still being a finite disk that recentered in 24-unit cells and cross-faded the complete population between old/new centers. 8.2.0 removes that whole-field handoff. Each snow identity now owns a stable point in a periodic world tile and independently selects its nearest copy; individual flakes wrap only at the far tile boundary. Walking therefore cannot relocate the entire snow field or make all visible snow disappear/reappear together. The modern native `love_InstanceID` path remains in place and MAX BLIZZARD remains 200,000 flakes.

## Validation
See `weather_fx-core-8.2.0-validation.txt` and the final audit/qualification artifacts for the exact package results.
