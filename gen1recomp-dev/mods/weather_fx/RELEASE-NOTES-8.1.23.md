# Weather FX 8.1.23 — Player Fallback Controls

## Cloud height
The ATMOSPHERE submenu adds **CLOUD HEIGHT** with **RAISED** and **ORIGINAL**. RAISED is the 8.1.22 default (150% of the historical deck). ORIGINAL is exactly the pre-8.1.22 height (100%) for players who prefer the lower deck or need a lighter view on low-end hardware. Cloud geometry, precipitation origins, lightning tops and tornado attachment share this one setting.

## Full-map weather fallback
The existing **WEATHER FRONTS** setting is now the master spatial-weather switch. ON/CONFIG keeps the 8.1.22 moving regional fronts/StormCells/local edges. OFF disables regional fronts, StormCells and mesoscale localization together and returns weather to uniform full-map coverage. Normal weather changes still occur; only spatial fronts/partial-map coverage are disabled.

## Preserved contracts
WEATHER DURATION remains lifetime-only. CLOUD HEIGHT and WEATHER FRONTS never change particle speed, wind/cloud advection speed, audio speed, game/celestial time, lightning cadence or transition-animation speed.
