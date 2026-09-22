# Weather FX 8.1.22 — Realistic Moving Storm Cells

## Player-visible behavior
A weather system is no longer forced to occupy an entire map. Finite world-space cells can cover part of one map, straddle two connected maps, or span several maps. The same physical cell continues moving while the player crosses map boundaries. Players can therefore walk from dry air into a weak fringe, into the core, back out, and back into the same moving storm.

Cells evolve through FORMATION → GROWTH → MATURE → WEAKENING → DISSIPATION. Their precipitation footprint has a strong irregular core and a pronounced smooth edge. Their cloud footprint is larger—especially downwind—so cloud banks gather and approach before rain/snow reaches the player.

## Vertical atmosphere
The strict-3D cloud deck is 50% higher than 8.1.21. Precipitation is emitted from that higher deck, world lightning begins in it, and 3D tornado funnels attach to it, naturally making bolts/funnels longer rather than visually disconnecting them from the clouds.

## Performance
StormCells is bounded to six live cells and uses analytic sampling instead of a world grid. The farther cloud-horizon search is enabled only while localized finite weather requires it; ordinary weather uses the prior search budget.

## Preserved contracts
8.1.21 player controls, 8.1.20 WEATHER DURATION lifetime-only semantics, and the 8.1.19 WeatherShadowMap engine remain in force. WEATHER DURATION never changes particle or simulation kinematic speed.
