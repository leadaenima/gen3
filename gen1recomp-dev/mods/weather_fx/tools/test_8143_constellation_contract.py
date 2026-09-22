#!/usr/bin/env python3
from pathlib import Path
import csv,io,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
co=(R/'lib/Constellations.lua').read_text(); ns=(R/'lib/NightSky.lua').read_text()
ck('C.PEAK_LUMA_TARGET = 0.82' in co,'shared 0.82 display-luma target is runtime authority')
ck('C.BRIGHTNESS_GAINS[name] = 1' in co and 'bag[i].constGain = 1' in co,'density-based per-subject gain spread is removed')
ck('sourceR=col[1],sourceG=col[2],sourceB=col[3]' in co,'authored source RGB is retained per star')
ck('equalPeakColor' in co and 'colorLuma' in co,'runtime performs tint-preserving luminance normalization')
ck('(s.a or .34)*(s.constGain or 1)' in co and '(cs.a or .34)*(cs.constGain or 1)' in ns,'world and projected paths consume the same normalized constellation authority')
rows=list(csv.DictReader((R/'CONSTELLATION-BRIGHTNESS-AUDIT-8.1.43.csv').open()))
ck(len(rows)==25,'audit enumerates exactly 25 constellations')
ck(sum(int(r['stars']) for r in rows)==8507,'audit covers all 8,507 traced stars')
ck(all(abs(float(r['gain'])-1)<1e-9 for r in rows),'audit proves exact 1.0 gain for every constellation')
ck(max(float(r['primary_peak']) for r in rows)-min(float(r['primary_peak']) for r in rows)<1e-9,'audit proves identical primary peak across all 25')
ck(max(float(r['secondary_peak']) for r in rows)-min(float(r['secondary_peak']) for r in rows)<1e-9,'audit proves identical secondary peak across all 25')
failed=sum(not v for v,_ in checks);print(f'8.1.43 constellation source contract: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
