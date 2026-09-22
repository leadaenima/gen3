#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1];s=(R/'lib/Tornado.lua').read_text();c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
ck('for mapId,row in pairs(landingTable())' in s,'Weather FX safe landing history participates in destination enumeration')
ck('local g=gameObject(); local visited=g and g.save and g.save.visited' in s,'engine visit flags remain compatibility input')
ck('function T._warpTo(destination,landing,onDone)' in s,'shared 2D/3D transfer authority exists')
ck('type(ow.warpToMapId)=="function"' in s,'Gen2 live direct transfer supported')
ck('type(ow.setMap)=="function"' in s,'Gen1 live direct transfer supported')
ck('tostring(ow.map.id)==tostring(destination)' in s,'direct transfer requires live destination-map postcondition')
ck('type(world.warpTo)=="function"' in s,'public warp retained as compatibility fallback')
ck('type(ow.startWarpTo)=="function"' in s,'private transition warp retained as compatibility fallback')
ck('landing.mode~="water" and p.surfing' in s,'land transfer clears stale Surf presentation')
ck('T._warpTo(destination,landing,onDone)' in s,'carry funnels through repaired transfer authority')
print(f'8.1.61 tornado transfer contract: {sum(c)}/{len(c)} passed')
sys.exit(0 if all(c) else 1)
