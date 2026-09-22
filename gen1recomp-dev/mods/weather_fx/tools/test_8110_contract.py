#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
passed=failed=0
def ck(v,m):
 global passed,failed
 if v: passed+=1
 else: failed+=1;print('FAIL '+m)
def txt(p): return (ROOT/p).read_text(errors='replace')
m=json.loads(txt('manifest.json'))
ck(tuple(map(int,m.get('version','0.0.0').split('.'))) >= (8,1,10),'manifest retains 8.1.10+ contract')
ck(tuple(map(int,(ROOT/'BASELINE').read_text().strip().split('.'))) >= (8,1,10),'BASELINE retains 8.1.10+ contract')
S=txt('lib/Settings.lua'); W=txt('lib/WeatherState.lua'); P=txt('lib/voxel_atmos/WorldPrecip.lua'); C=txt('lib/voxel_atmos/CinematicAtmos.lua'); T=txt('lib/Types.lua'); WP=txt('lib/WindPlayer.lua')
ck('key = "snowIntensity", label = "SNOW INTENSITY"' in S,'Snow Intensity setting exists')
ck('function Settings.snowIntensity()' in S and 'function Settings.snowOff()' in S,'Snow Intensity runtime helper exists')
ck('"snowIntensity","fogIntensity"' in S,'Snow Intensity grouped beside atmosphere intensity controls')
m=re.search(r'local CONTROL_KEYS=\{([^}]*)\}',W)
ck(m is not None and '"snowIntensity"' in m.group(1),'Snow Intensity participates in rapid live retarget')
ck('if key == "snow" then' in W and 'snowMul' in W,'WeatherState snow-specific multiplier path')
ck('math.min(45.0, goal * scale * snowMul)' in W,'snow bypasses generic 2.0 cap')
ck(re.search(r'id = "SNOW_LIGHT".*?snow = 3\.60',T,re.S) is not None,'Snow authored density 3.60')
ck(re.search(r'id = "BLIZZARD".*?snow = 5\.50',T,re.S) is not None,'Blizzard authored density 5.50')
ck('min(5.0, snowI / 1.9)' in P,'WorldPrecip allows stronger snow density inside caps')
ck('weather._snowExplicitOff' in P and 'weather._wxChannelsResolved ~= true' in P,'WorldPrecip preserves explicit/live zero')
ck('function CinematicAtmos._mistPolicy' in C and 'weather.fog,weather._mistVisual=CinematicAtmos._mistPolicy' in C,'3D fog has explicit authored-channel policy')
ck('return base/m' in WP and 'math.max(1,' not in WP,'wind hook preserves host fractional game speed')
ck('snow_intensity_pipeline_test.lua' in txt('tools/run_all.py'),'snow-intensity regression wired into runner')
ck('fog_ownership_matrix_test.lua' in txt('tools/run_all.py'),'fog-ownership regression wired into runner')
print(f'8.1.10 retained contract: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
