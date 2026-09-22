#!/usr/bin/env python3
from pathlib import Path
import math,re,sys
R=Path(__file__).resolve().parents[1]
pf=(R/'lib/ProceduralSnowField.lua').read_text()
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text()
checks=[]
manifest=(R/'manifest.json').read_text()
def ck(v,m):
    checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
ck(('\"version\": \"8.2.13\"' in manifest) or ('\"version\": \"8.2.14\"' in manifest),'manifest is 8.2.13 TSNOW baseline or later 8.2.14')

# TSNOW must now enter the deterministic radial population taper in both the
# procedural probe and real draw paths.
ck(wp.count("local tsnow=(snowWx=='THUNDERSNOW' or snowWx=='TSNOW')")>=2,
   'THUNDERSNOW and TSNOW alias share the TSNOW visual profile in probe + draw paths')
ck(wp.count("or tsnow)")>=2,'TSNOW is included in procedural snow radial population taper')
ck(wp.count('o.coreRadius,o.edgeKeep,o.taperPower=.16,.00000025,17')>=2,
   'TSNOW keeps a wide full-density local core and extremely sparse far edge')
ck(wp.count('o.detailRadius,o.detailDensityBoost,o.detailExtraCap=110,1.80,4096')>=2,
   'TSNOW redirects visual detail into a wider denser near/overhead shell with bounded extra cost')

# Procedural snow must honor the profile without increasing logical snow count
# or CPU simulation. Detail work is a bounded render-only shell.
for marker in ('opts.detailRadius','opts.detailDensityBoost','opts.detailExtraCap','baseDetailCount','boostedDetail'):
    ck(marker in pf,f'procedural snow consumes {marker}')
ck('local detailCount=math.min(count,boostedDetail)' in pf,
   'near-detail boost can never exceed the existing logical snow identity count')
ck('baseDetailCount+detailExtraCap' in pf,
   'MAX near-detail increase is hard bounded independent of logical storm population')

# Numeric visual-shape guard. Preserve 100% local core, collapse distant rings,
# and keep a nonzero edge so full render-distance coverage remains true.
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)
def keep(core,edge,power,r):
    u=smooth(core,1,r)
    return edge+(1-edge)*max(0,1-u)**power
core,edge,power=.16,.00000025,17
vals=[keep(core,edge,power,r) for r in (0,.10,.16,.20,.30,.40,.50,.60,.80,1.0)]
ck(vals[0]>.999 and vals[2]>.999,'TSNOW remains fully populated throughout the overhead/player core')
ck(vals[3]>.80 and vals[4]<.30,'TSNOW transitions from dense local blowing snow to a rapidly thinning mid field')
ck(vals[5]<.025 and vals[6]<.001 and vals[7]<.000003,
   'TSNOW mid/far visible population collapses enough to remove fuzzy white distance wall')
ck(0<vals[-1]<=.0000003,'TSNOW retains a nonzero full-render-distance continuation without hard cutoff')
ring=[r*keep(core,edge,power,r) for r in (.2,.4,.6,.8)]
ck(ring[1] < ring[0]*.14 and ring[2] < ring[0]*.00002 and ring[3] < ring[0]*.000002,
   'TSNOW area-weighted distant ring contribution collapses despite growing circumference')

# MAX representative near-detail budget: 200k TSNOW identities / 750 radius.
# Old path used <=80 detail radius and no boost. New path must materially raise
# detailed overhead structure but the +4096 cap must contain cost.
count,far=200000,750
oldr=min(far,max(36,min(80,far*.18)))
oldbase=max(1,math.floor(count*(oldr*oldr)/(far*far)+.5))
newr=min(far,max(24,110))
newbase=max(1,math.floor(count*(newr*newr)/(far*far)+.5))
newdetail=min(count,min(math.floor(newbase*1.80+.5),newbase+4096))
ck(newdetail >= oldbase*3.0,'representative MAX TSNOW has at least 3x as many detailed near/overhead flakes as 8.2.12')
ck(newdetail-newbase <= 4096,'representative MAX TSNOW respects bounded additional detailed submissions')

# Scope guard: ordinary SNOW and BLIZZARD parameters stay unchanged.
ck(wp.count("o.coreRadius,o.edgeKeep,o.taperPower=.08,.0000005,16")>=2,
   'BLIZZARD anti-fuzz profile is unchanged')
ck(wp.count("o.coreRadius,o.edgeKeep,o.taperPower=.10,.000001,14")>=2,
   'ordinary SNOW anti-fuzz profile is unchanged')

print(f'TSNOW 8.2.13 regression retained in current package: {sum(checks)}/{len(checks)} PASS')
sys.exit(0 if all(checks) else 1)
