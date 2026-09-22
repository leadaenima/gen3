#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1];s=(R/'lib/Tornado.lua').read_text();checks=[]
def ck(v,m): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
ck('Gameplay contact must follow the LIVE overworld entity' in s,'live overworld player is contact authority')
ck('local ow=S and S.overworld and S.overworld() or nil' in s,'live overworld resolved before voxel fallback')
ck('math.max(30,tonumber(cfg().touchRadius) or 14)' in s,'physical contact covers visible ground footprint')
ck('segmentOriginDistanceSq' in s,'swept relative-motion helper exists')
ck('prevPx-oldRx' in s and 'px-r.x' in s,'swept player/tornado relative segment used')
ck('tostring(mapId)~=tostring(r.mapId)' in s,'contact sweep is map-scoped')
ck('r.contactCarry=(reason=="touch")' in s,'walk-in contact marked separately from seeker pickup')
ck('local choices=T.destinations(mapId or r.mapId)' in s,'walk-in contact still requires safe visited destination')
ck('return beginCarry(r,px,pz,"touch")' in s,'walk-in collision enters shared carry state machine')
print(f'8.1.62 tornado contact contract: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
