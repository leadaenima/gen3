# Weather FX 8.1.84 — Unified Weather Selector Authority

Built directly from exact Weather FX 8.1.83.

## Fix
The base-game OPTIONS `WEATHER` pipeline row and the Weather FX Mod Manager `WEATHER MODE` row are now two synchronized views of one authoritative player weather selection.

- Changing either selector immediately changes the live weather authority.
- The other selector mirrors the same weather in the same session.
- Both engine pipeline persistence and Weather FX mod-option persistence are updated.
- `OFF -> AUTO` and `OFF -> named weather` are reversible from either menu.
- Named weather selected from either menu still disables WEATHER FRONTS so fronts cannot silently steal authority.
- The OPTIONS selector is reconciled before the hard-OFF gate, eliminating the stale-OFF trap.
- Synchronization writes only on an actual value change; normal climate ticks do not rewrite option storage every frame.

No precipitation counts, rendered distances, 2D/3D ownership rules, snow smoothing, sun glare, water, wind, tornado, lightning, audio, cloud, celestial, or performance budgets were intentionally changed from 8.1.83.
