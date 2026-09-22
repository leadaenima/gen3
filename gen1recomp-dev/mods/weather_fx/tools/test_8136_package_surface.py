#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.36','manifest 8.1.36')
ck((R/'BASELINE').read_text().strip()=='8.1.36','BASELINE marker 8.1.36')
for f in ['RELEASE-NOTES-8.1.36.md','tests/world_ecosystem_8136_test.lua','tests/storm_handoff_volume_8136_test.lua','tests/building_light_continuity_8136_test.lua','tests/complete_water_ownership_8136_test.lua','tests/water_player_safety_8136_test.lua','tools/test_8136_runtime_delta.py','tools/test_8136_package_surface.py','tools/baselines/8.1.35-runtime-sha256.json','tools/baselines/8.1.36-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
front=(R/'lib/StormCells.lua').read_text(); dist=(R/'lib/DistantWeather.lua').read_text(); state=(R/'lib/WeatherState.lua').read_text(); cin=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
water=(R/'lib/ConnectedWater.lua').read_text(); water3=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text(); dra=(R/'lib/DramalessAtmos.lua').read_text(); season=(R/'lib/Seasons.lua').read_text(); night=(R/'lib/NightSky.lua').read_text(); bl=(R/'lib/BuildingLight.lua').read_text(); rn=(R/'RELEASE-NOTES-8.1.36.md').read_text()
ck('cloudCellId' in front and 'cloudWeather' in front,'storm cells publish independent cloud identity')
ck('nearFade' in dist and 'if amp>.035 and edge>150' not in dist,'distant front uses continuous near handoff with old hard cutoff removed')
ck('_cellCloudWeather' in state,'local cloud ownership begins before precipitation core')
ck('local function ellipsoid' in cin and 'local SEG,LAT=14,8' in cin and 'anvil' in cin.lower(),'storm front uses tessellated 3D ellipsoid/anvil volume')
ck('weatherMultiplier' in season and 'summer' in season.lower() and 'winter' in season.lower(),'seasonal weather climatology authority present')
ck('_forceMeteorEvent' in night and 'fireball' in night.lower(),'celestial meteor qualification + fireball path present')
ck('hostTileShape' in water and 'hostBodies' in water,'8px host-semantic water ownership path present')
ck('bodyByMapCell' in water and 'isLoadBearingMapCell' in water,'map-exact authored ice collision authority present')
ck('nativeWater' in dra and 'secondary' in dra.lower(),'secondary host water pass suppression/restoration present')
ck('waveSampleAtT' in water3 and 'waveKernel' in water3,'one-pass cached physical wave sampler present')
ck('connected' in bl.lower() and 'map' in bl.lower(),'connected-map building light scan present')
ck('no water mesh density' in rn.lower() and 'does not claim to fix gen1recomp' in rn.lower(),'zero-quality-loss and OOB scope documented')
failed=sum(not v for v,_ in checks);print(f'8.1.36 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
