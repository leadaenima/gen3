#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
s=(R/'lib/Settings.lua').read_text();sp=(R/'lib/SnowPack.lua').read_text();wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text();checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck('key = "snowAccumulation", label = "SNOW ACCUMULATION"' in s,'player-facing snow accumulation row exists')
ck('default = "on"' in s[s.find('key = "snowAccumulation"'):s.find('key = "snowAccumulation"')+250],'snow accumulation defaults ON')
ck('"snowIntensity","snowAccumulation","fogIntensity"' in s,'snow accumulation is in PRECIPITATION directly after snow amount')
ck('function Settings.snowAccumulationEnabled()' in s,'typed snow accumulation reader exists')
ck('function SP.setEnabled(on)' in sp and 'function SP.isEnabled()' in sp,'SnowPack exposes live enable/disable authority')
ck('if not nextEnabled and SP._reset then SP._reset() end' in sp,'OFF clears existing SnowPack state immediately')
ck('S.snowAccumulationEnabled' in wp and 'SP.setEnabled,accumulationOn' in wp,'WorldPrecip consumes live setting')
ck('if accumulationOn and snowCtx and snowCtx.collisionEnabled' in wp,'OFF blocks bank/footprint staging')
ck('MAX_GROUND_HEIGHT = 3.60' in sp and 'MAX_GRASS_HEIGHT = 3.20' in sp,'approved accumulation heights are unchanged')
r=subprocess.run(['texlua',str(R/'tests/snow_accumulation_setting_8169_test.lua'),str(R)],cwd=R)
ck(r.returncode==0,'executable ON/OFF accumulation regression')
print(f'8.1.69 snow accumulation setting contract: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
