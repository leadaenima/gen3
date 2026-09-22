#!/usr/bin/env python3
from pathlib import Path
import math,re,sys
R=Path(__file__).resolve().parents[1]
pf=(R/'lib/ProceduralSnowField.lua').read_text()
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text()
checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
ck('fieldDensityRadiusInv' in pf and 'fieldRadialTaper' in pf,'procedural snow shader has player-radius taper uniforms')
ck('alpha*=step(seed,keep);' in pf,'distance taper reduces visible particle population rather than only opacity')
ck("snowWx=='SNOW_LIGHT' or snowWx=='SNOW' or snowWx=='BLIZZARD'" in wp,'8.2.8 SNOW_LIGHT / legacy SNOW / BLIZZARD taper remains present')
# 8.2.13 later adds TSNOW to the same mechanism; this historical regression
# now guards the original profiles rather than forbidding future weather use.
sel=re.findall(r"o\.radialTaper=\(([^\n]+)\)",wp)
ck(len(sel)>=2 and all('SNOW_LIGHT' in x and 'BLIZZARD' in x for x in sel),'original snow/blizzard taper selectors remain wired in both procedural paths')
ck("o.coreRadius,o.edgeKeep,o.taperPower=.08,.0000005,16" in wp,'BLIZZARD uses dense player core and extremely sparse far edge')
ck("o.coreRadius,o.edgeKeep,o.taperPower=.10,.000001,14" in wp,'SNOW_LIGHT uses gentle player core and extremely sparse far edge')
ck("'fieldDensityRadiusInv',1/math.max(.000001,farRadius)" in pf,'near and far LOD normalize taper to complete render radius')
ck("'fieldTaperPower',taperPower" in pf,'taper power is uploaded to procedural shader')

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)
def keep(core,edge,power,r):
    u=smooth(core,1,r)
    return edge+(1-edge)*(max(0,1-u)**power)
for name,core,edge,power in [('SNOW_LIGHT',.10,.000001,14),('BLIZZARD',.08,.0000005,16)]:
    vals=[keep(core,edge,power,r) for r in (0,.2,.4,.6,.8,1)]
    ck(all(vals[i]>=vals[i+1] for i in range(len(vals)-1)),f'{name} visible population decreases monotonically near-to-far')
    ck(vals[0]>.99 and vals[-1]>0,f'{name} is full near player but still reaches full render distance')
    ck(vals[-1]<=.0000011 and vals[-2]<.00001,f'{name} far field is sparse enough to avoid fuzzy horizon static')
    # Area-weighted annulus contribution must decrease strongly at long range;
    # this is the key anti-fuzz property for a field whose ring circumference grows with radius.
    ring=[r*keep(core,edge,power,r) for r in (.2,.4,.6,.8)]
    ck(ring[1] < ring[0]*.15 and ring[2] < ring[1]*.02 and ring[3] < ring[0]*.00001,
       f'{name} total visible ring population collapses smoothly toward horizon')
print(f'8.2.8 3D snow distance taper: {sum(checks)}/{len(checks)} PASS')
sys.exit(0 if all(checks) else 1)
