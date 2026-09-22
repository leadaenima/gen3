#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
t=(R/'lib/Tornado.lua').read_text(); f=(R/'lib/Funnel.lua').read_text(); d=(R/'lib/Draw.lua').read_text(); s=(R/'lib/Settings.lua').read_text()
checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
block=t[t.find('local function update2d'):t.find('function T.update',t.find('local function update2d'))]
ck('galeNow()' in block and 'T.windy(d)' not in block,'2D tornado is authored GALE-only')
ck('carryChance<=0 or rnd()>=carryChance' in block,'carry roll occurs before 2D tornado start')
ck('local dest=T.destinations(mapId)' in block and 'local landing=T.landingFor(target)' in block,'visited escape-safe destination resolved before visual spawn')
ck(block.find('local landing=T.landingFor(target)') < block.find('Funnel.start('),'landing is proven before Funnel.start')
ck('mode="carry2d"' in block and 'pickupAt=.55' in block and 'onPickup=function()' in block,'2D event requests left-right carry funnel with mid-cross pickup')
ck('function T.isCarrying() return T._carry~=nil or T._legacyCarry~=nil end' in t,'2D carry locks player through existing movement hook')
ck('traveling and (x - margin + (w + margin * 2) * travel)' in f,'funnel moves continuously from left offscreen to right offscreen')
ck('Funnel.mode == "carry2d"' in f and 'Funnel.pickupFired' in f,'funnel pickup callback is one-shot')
ck('Funnel.update(dt)' not in d,'Draw compositor no longer double-advances funnel clock')
ck('if Funnel and Funnel.active and Funnel.update then Funnel.update(dt) end' in t,'Tornado simulation owns funnel clock once per frame')
ck('In 2D, tornadoes never roam or appear as scenery' in s,'player-facing setting explains relocation-only 2D behavior')
print(f'8.1.57 2D tornado source contract: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
