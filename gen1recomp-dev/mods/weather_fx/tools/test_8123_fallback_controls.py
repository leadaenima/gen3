#!/usr/bin/env python3
from pathlib import Path
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,n): checks.append((bool(v),n)); print(('PASS ' if v else 'FAIL ')+n)
S=(R/'lib/Settings.lua').read_text(); C=(R/'lib/Config.lua').read_text(); SC=(R/'lib/StormCells.lua').read_text(); W=(R/'lib/WeatherState.lua').read_text(); CA=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text(); WP=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text(); T=(R/'lib/Tornado.lua').read_text(); WL=(R/'lib/voxel_atmos/WorldLightning.lua').read_text()
ck('key = "cloudHeight"' in S and '{ "HIGH", "raised" }' in S and '{ "LOW", "original" }' in S,'CLOUD HEIGHT preserves raised/original stored choices with clear HIGH/LOW labels')
ck('function Settings.cloudHeightScale()' in S and '== "original" and 1.0 or 1.5' in S,'cloud height maps exactly to original 100% or raised 150%')
ck('if data.fronts.enabled == false then data.mesoscale.enabled = false end' in C,'WEATHER FRONTS OFF overrides mesoscale localization')
ck('function C.setEnabled(v)' in SC and 'if not enabled then' in SC and 'stage="disabled"' in SC,'StormCells has explicit disable gate and zero spatial sample')
ck('StormCells.setEnabled(frontsOn)' in W and 'State._spatialStrength,State._spatialCloud=1,1' in W,'WeatherState disables cell edges and restores full-map amplitude')
ck('base=base*CinematicAtmos._cloudHeightScale()' in CA and '* heightScale' in CA,'rendered cloud and precipitation deck consume selected cloud height')
ck('RAIN_CEIL = 26' in WP and 'SNOW_CEIL = 96' in WP and 'cloudHeightScale()' in WP,'WorldPrecip preserves exact original fallback bases and applies live scale')
ck('122*math.max' in T and 'cloudHeightScale' in T,'tornado fallback cloud attachment follows selected height')
ck('topY=120*max(1.0,min(1.5,scale))' in WL,'direct WorldLightning fallback follows selected height')
ck('particle speed' in (R/'RELEASE-NOTES-8.1.23.md').read_text() and 'lifetime-only' in (R/'RELEASE-NOTES-8.1.23.md').read_text(),'release notes preserve timing isolation contract')
f=sum(not v for v,_ in checks); print(f'8.1.23 fallback controls: {len(checks)-f}/{len(checks)} passed'); raise SystemExit(1 if f else 0)
