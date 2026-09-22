#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text()
bd=(R/'lib/BattleDraw.lua').read_text()
sc=(R/'lib/Scene.lua').read_text()
main=(R/'main.lua').read_text()
checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
ck('B.current and B.current()' in wp,'WorldPrecip uses frame-live Battle.current authority')
u=wp.find('function WP.update')
g=wp.find('if battleActive() then return end',u)
f=wp.find('local px = focus[1] or 0',u)
sh=wp.find('shiftPool(',u)
ck(g!=-1 and f!=-1 and g<f,'battle suspension occurs before reading transition focus')
ck(g!=-1 and sh!=-1 and g<sh,'battle suspension occurs before stream/pool carry')
d=wp.find('function WP.draw')
dg=wp.find('if battleActive() then',d)
ds=wp.find('wpDrawSerial = wpDrawSerial + 1',d)
ck(dg!=-1 and ds!=-1 and dg<ds,'WorldPrecip draw fails closed before stale world precipitation')
ck('simTime - battleAt < 1.0' not in wp,'old one-second battle cache removed')
ck('function BD.begin(battle)' in bd and 'ch[key]=def and Types.channel(def,key) or 0' in bd,'BattleDraw begin primes finalized battle weather directly')
ck('BattleDraw.begin(ev and ev.battle or nil)' in main,'main primes BattleDraw after Battle.install battle-start seeding handlers')
ck('B.current and B.current()' in sc and 'return scale,false' in sc,'flat overworld precipitation stands down during battle opening transition')
print(f'8.1.56 battle precipitation source contract: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
