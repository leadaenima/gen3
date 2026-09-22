# Weather FX 8.1.50 — Seamless 3D Front Precipitation

## Player-visible fix

Rain and snow fronts now remain the **same kind of 3D precipitation as they approach and pass over the player**.

Previously the long-range front renderer could show a broad rain/snow sheet while the local `WorldPrecip` system waited for the player-local weather channels to build. A physical `StormCell` could therefore reach the player before the local 3D drops/flakes had enough authority to replace that sheet. Even when both systems were technically correct, the player could see a visual handoff.

8.1.50 removes that mismatch:

- rain fronts use individual world-space 3D rain streaks inside the real moving StormCell slab;
- snow fronts use individual world-space 3D flakes;
- blizzard fronts use the same individual flakes with wind/gust shear rather than a white wall card;
- particle positions are stable/deterministic for the front identity, so handoff changes opacity/density instead of swapping or teleporting precipitation;
- fog keeps veil geometry because fog is physically a volume, not falling hydrometeors;
- remote lightning remains a true world-space bolt owned by the same StormCell.

## Seamless far-to-near overlap

Remote precipitation used to exhaust its handoff too early. 8.1.50 keeps the remote 3D field under the local field across **62% of physical front penetration**. This gives the normal WeatherState easing enough time to establish local rain/snow before the remote component disappears.

In the real Gen1Recomp + Pokémon Yellow + Voxel Nexus 2.0.12 controlled contact sequence:

- rain at 250 world units from the controlled cell centre retained about **51% remote-front shaft authority** while **1,626 local rain particles** were already active;
- rain at 180 units retained about **10% remote authority** while **8,819 local rain particles** were active;
- snow at 250 units retained about **51% remote authority** while **8,841 local snow particles** were active;
- snow at 180 units retained about **10% remote authority** while **49,702 local snow particles** were active.

The fronts were advanced at a physical 3 world-units/second in the final driver rather than teleported between distances, so the local weather easing had the same time relationship a player sees while watching an approaching front.

## Density and performance boundary

The distant renderer uses a shared quality-scaled hydrometeor budget rather than an unbounded particle count. At maximum quality the shared remote-front budget is capped at 9,000 particles across the visible front set, with per-front class floors/caps and the nearest systems consuming the budget first. This is intentionally bounded; it does not create a second unbounded local precipitation simulation.

## Preserved

8.1.50 is built directly from exact 8.1.49. The intended runtime delta is exactly:

- `lib/DistantWeather.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

The 8.1.49 professional settings overhaul, all setting keys/stored values, WeatherState authority, StormCell simulation, local `WorldPrecip`, clouds, water, celestial systems, audio, battles, encounters and assets are otherwise preserved.

See `FRONT-PRECIP-CONTINUITY-AUDIT-8.1.50.md` for qualification details and the live-test boundary.
