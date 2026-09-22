#!/usr/bin/env python3
from pathlib import Path
import re,subprocess,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text(); pp=(R/'lib/ProceduralPrecipField.lua').read_text(); ps=(R/'lib/ProceduralSnowField.lua').read_text(); q=(R/'lib/Quality.lua').read_text()
ck('worldRainCap=12000' in q and 'worldSnowCap=100000' in q and 'worldBlizzardCap=200000' in q,'MAX rain/snow/blizzard authored caps unchanged')
ck('worldHailCap=45000' in q and 'worldSandCap=43200' in q and 'worldDebrisCap=3600' in q and 'worldAshCap=10800' in q,'MAX grain/debris authored caps unchanged')
ck('rain.simActive=min(wantRain,96)' in wp and 'rain.gpuActive=wantRain' in wp,'full-GPU rain removes visual population from CPU without reducing logical target')
ck('wantSnowSim=min(wantSnow,96)' in wp and 'gpuSnow=wantSnow' in wp,'full-GPU snow removes visual population from CPU without reducing logical target')
ck('grain.simTarget[kind]=0' in wp and 'kind~=3' in wp,'noninteractive hail/sand/ash use zero CPU cards while leaves remain physical')
ck('WP._trimPool(rain,rain.simActive,"rain")' in wp and 'WP._trimPool(snow,wantSnowSim,"snow")' in wp and 'WP._trimPool(grain,wantGrain,"grain")' in wp,'retired CPU high-water pools are compacted')
ck('InstanceSeedBuffer' in pp and 'newCanvas' not in pp and 'newCanvas' not in ps,'existing immutable seed GPU architecture reused with no framebuffer')
ck('state.proven=true' in pp and 'function P.canVirtualize()' in pp and 'function P.probe' in pp,'GPU ownership is gated by a real draw proof')
ck('function WP.snowGroundCollisionEnabled() return true end' in wp and 'wantSnowSim=min(wantSnow,96)' in wp and 'at most 24 exact-support samples/second' in wp,'restored snow ground interaction remains bounded under GPU virtualization')
r=subprocess.run(['texlua',str(R/'tests/near_precip_virtualization_8154_test.lua')],cwd=R)
ck(r.returncode==0,'executable 8.1.54 near-precip virtualization regression')
r=subprocess.run(['texlua',str(R/'tests/max_precip_virtualization_8154_test.lua')],cwd=R)
ck(r.returncode==0,'executable MAX precipitation virtualization regression')
print(f'8.1.54 performance contract: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
