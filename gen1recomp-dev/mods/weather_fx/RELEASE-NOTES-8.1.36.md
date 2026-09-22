# Weather FX 8.1.36 — World Front Continuity / Zero-Quality-Loss Performance

## Storm fronts and world weather
- keeps generated fronts alive long enough to reach the target world corridor and steers pre-arrival motion toward the world even under adverse wind;
- separates cloud-front identity from the precipitation core so a storm can be visible as growing cloud/anvil before rain or snow reaches the player;
- crossfades remote and local ownership over the near-field instead of deleting the front at a fixed distance;
- replaces the old flat-looking distant front shell with tessellated ellipsoid storm volumes and a flattened mature anvil, oriented along front travel;
- lets electrically charged remote cells generate real distant lightning and true-distance thunder without requiring precipitation on the player;
- applies seasonal climatology: summer excludes frozen precipitation, winter excludes heat/sun extremes, spring favors rain, and autumn favors fog/wind/rain while preserving regional/geographic weighting.

## Celestial continuity
- proves natural calendar reachability for solar eclipse, lunar eclipse/blood moon, supermoon, harvest moon and blue moon while the relevant celestial body is above the rendered horizon;
- exposes bounded qualification seams for the existing shooting-star and meteor-shower renderer plus the new fireball/bolide renderer path;
- keeps stars/constellations tied to connected-world building distance so map changes no longer cause abrupt brightness jumps.

## Complete water ownership and seasonal ice
- captures Voxel Realism host-semantic 8x8 water fragments that can be missed by 16x16 cartridge gameplay-cell discovery;
- keeps those extra fragments presentation-only while rendering them through the same Professional Physical Water/ice presentation;
- suppresses Voxel Realism's secondary water pass while WATER STYLE = WEATHER FX, eliminating double rendering and old-water leaks;
- restores the host's exact secondary-water state immediately in WATER STYLE = ORIGINAL;
- preserves progressive winter freeze, load-bearing authored ice, walkable frozen-water support, and warm spring/summer thaw back to liquid;
- presentation-only host/void water can never become collision/Surf/ice-walking authority.

## Zero-quality-loss performance sweep
- fuses vertical wave height and horizontal Gerstner/orbital displacement into one wave-spectrum traversal per physical vertex instead of calculating the spectrum twice;
- removes high-volume temporary point tables from persistent whitecap/curl construction while retaining the same ribbon geometry and segment counts;
- removes the duplicate host secondary-water render/calculation while WEATHER FX owns water;
- controlled 100-frame no-GC benchmark preserves exactly 5,799 physical water vertices, 5,934 foam vertices and 7 meshes in both versions. Three-run mean isolated water CPU falls from about 27.17 ms/frame in 8.1.35 to 17.58 ms/frame in 8.1.36 (~35.3% faster), while transient Lua allocation falls from 262.31 KB/frame to 13.11 KB/frame (~95.0% lower). These are isolated software-container measurements, not a whole-game FPS promise.
- no water mesh density, wave amplitude, foam population, cloud count, star/constellation population, weather particle population, draw distance, or player-visible quality setting is reduced.

## Scope
Weather FX retains defensive tests proving its ice hook never authorizes out-of-bounds or liquid-water walking, but **8.1.36 does not claim to fix Gen1Recomp's separate out-of-bounds bug**.
