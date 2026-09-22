#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
d=(R/'lib/DramalessAtmos.lua').read_text()
cw=(R/'lib/ConnectedWater.lua').read_text()
c3=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text()
ck('publicBattleArtWater=false' in d,'bridge declares separate public Battle Art capability')
ck('caps.id=="BATTLE_ART_VOXEL_FORK"' in d,'shared legacy id is capability-probed rather than renamed')
ck('local nexusTide=type(engine)=="table" and type(engine.tideOffset)=="function"' in d and 'caps.publicBattleArtWater=structured and not caps.voxelNexusWater' in d,'current public host is distinguished from Voxel Nexus by the Nexus-only WaterEngine tide seam')
for token in ('HostWater._waveTime','HostWater.WAVE_TRAINS','HostWater.WAVE_SWELL','HostWater.WAVE_BEND','HostWater.begin','HostWater.draw','HostWater.finish'):
    ck(token in d,'public Battle Art fingerprint includes '+token.replace('HostWater.',''))
ck('q.publicBattleArtWater=info.publicBattleArtWater==true' in cw,'hydrosphere retains public Battle Art renderer fingerprint')
ck('publicBattleArt=hostCaps and hostCaps.publicBattleArtWater==true' in c3,'3D water consumes public-host fingerprint')
ck('(type(Water._trainSource)=="function" or publicBattleArt)' in c3,'public Battle Art is admitted to structured physical mesh path')
ck('Water.WAVE_HEIGHT=physical and 0 or waveH' in c3,'successful physical mesh ownership zeros host geometric relief')
ck('return origWater(draws,cast,...)' in d,'ORIGINAL/failed ownership still returns native host water')
ck('preflightVoidOwnership()' in d and '_hostUnderlaySuppressed=true' in d,'separate WorldUnderlay remains under exclusive preflight ownership')
failed=sum(not v for v,_ in checks)
print(f'8.1.44 public Battle Art source contract: {len(checks)-failed}/{len(checks)} passed')
sys.exit(1 if failed else 0)
