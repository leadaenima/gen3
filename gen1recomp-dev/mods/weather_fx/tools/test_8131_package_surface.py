#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.31','manifest 8.1.31')
ck((R/'BASELINE').read_text().strip()=='8.1.31','BASELINE marker 8.1.31')
for f in ['RELEASE-NOTES-8.1.31.md','lib/voxel_atmos/ConnectedWater3D.lua','lib/DramalessAtmos.lua','lib/ConnectedWater.lua','lib/Settings.lua','lib/SettingsMenu.lua','tests/wave_realism_8131_test.lua','tests/water_style_8131_test.lua','tools/test_8131_runtime_delta.py','tools/baselines/8.1.30-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
s=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text()
ck('REAL CRESTS + TROUGHS' in s and 'centreDrop' in s,'centered crest/trough renderer present')
ck('playerBob' in s and 'VISUAL Y ONLY' in (R/'lib/DramalessAtmos.lua').read_text(),'presentation-only Surf bob bridge present')
settings=(R/'lib/Settings.lua').read_text();menu=(R/'lib/SettingsMenu.lua').read_text();root=(R/'lib/ConnectedWater.lua').read_text()
ck('key = "waterStyle"' in settings and '"WEATHER FX", "weatherfx"' in settings and '"ORIGINAL", "original"' in settings,'WATER STYLE player control present')
ck('waterStyle' in menu and 'weatherFxWaterEnabled' in settings,'WATER STYLE in-game menu/live reader present')
ck('if not presentationEnabled() then return false end' in root,'ORIGINAL mode masks hidden load-bearing ice gameplay')
failed=sum(not v for v,_ in checks);print(f'8.1.31 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
