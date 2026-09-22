#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys,re
R=Path(__file__).resolve().parents[1];c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
cs=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
ds=(R/'lib/DramalessAtmos.lua').read_text()
ck('function CinematicAtmos._distantSnowHandoff(frame, kind)' in cs,'pure snow handoff policy exists')
ck(cs.count('alpha=alpha*CinematicAtmos._distantSnowHandoff(frame,a.kind)')==2,'CPU and GPU distant snow use identical handoff')
ck('if kind~="snow" and kind~="blizzard" then return 1 end' in cs,'rain/fog bypass snow handoff')
ck('(localSnow-.06)/.52' in cs,'handoff has bounded gradual local-snow takeover band')
ck('DistantFrontPrecip = true' in ds,'private distant-front GPU backend is Weather FX root-owned')
# The visual snow-field/front engines remain byte-identical to exact 8.1.58.
# WorldPrecip was intentionally superseded in 8.1.64 to restore bounded
# SnowPack interaction, so validate that approved replacement contract instead
# of falsely requiring an obsolete 8.1.58 hash.
base=json.loads((R/'tools/baselines/8.1.58-runtime-sha256.json').read_text())['files']
for rel in ['lib/ProceduralSnowField.lua','lib/DistantFrontPrecip.lua']:
    p=R/rel; got=hashlib.sha256(p.read_bytes()).hexdigest(); exp=base[rel]['sha256']
    ck(got==exp and p.stat().st_size==base[rel]['size'],rel+' preserved exactly from 8.1.58')
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text()
ck('8.1.64: the corrected bounded SnowPack support resolver is live again.' in wp and 'at most 24 exact-support samples/second' in wp,'WorldPrecip carries approved 8.1.64 bounded SnowPack supersession')
# The old front overlap remains in DistantWeather; 8.1.59 only removes duplicate visual snow when local snow is active.
d=(R/'lib/DistantWeather.lua').read_text()
ck('radius*.62' in d and 'shaftHandoff' in d,'physical distant-front handoff geometry remains inherited')
print(f'8.1.59 snow plume contract: {sum(c)}/{len(c)} passed')
sys.exit(0 if all(c) else 1)
