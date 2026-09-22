#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, sys, re
ROOT=Path(__file__).resolve().parents[1]
fail=[]
def ck(v,m):
    if not v: fail.append(m)
ty=(ROOT/'lib/Types.lua').read_text()
dr=(ROOT/'lib/Draw.lua').read_text()
au=(ROOT/'lib/Audio.lua').read_text()
ck('function Types.strikeRate' in ty and 'function Types.hasLightning' in ty,'central authored strike authority missing')
ck('State.channel("strike")' in dr and 'State.current' in dr,'Draw scheduler does not use localized storm-cell strike authority')
# Hard proof that pure rain definitions themselves have no strike channel.
for wid in ('RAIN_LIGHT','RAIN_HEAVY'):
    m=re.search(r'id = "'+wid+r'".*?\n  \},',ty,re.S)
    ck(m is not None and 'strike =' not in m.group(0),wid+' unexpectedly authored with lightning')
ck('Audio.strikeWeatherId = strikeWeatherId' in au,'audio thunder authority is not testable/exported')
ck('Lightning.strikeSerial' in au and '_lastStrikeSerial' in au,'audio still relies only on consumable justStruck flag')
ck('thunderDistanceDelay' in au and 'speedOfSound = 343.0' in au,
   'thunder does not use physical distance propagation delay')
ck('thunderDistanceGain' in au and 'farGain = 0.55' in au,
   'thunder does not attenuate with bolt distance')
ck('psychicFarStart' in au and 'farBoom' in au and 'farTail' in au,
   'Psychic Storm distant thunder lacks heavy low-frequency role transition')
ck('_pendingStrikeEvents' in au and '_scheduledThunder' in au,
   'per-bolt queued thunder pipeline missing')
ck('minGap = ' not in au and 'denseMinGap = ' not in au,
   'legacy thunder cooldown still present')
cin=(ROOT/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
light=(ROOT/'lib/Lightning.lua').read_text()
ck('publishWorldStrikeBatch' in cin and 'distances' in cin,
   '3D renderer does not publish each bolt distance to audio')
ck('function L.publishWorldStrikeBatch' in light and 'function L.takeWorldStrikeBatch' in light,
   'shared Lightning distance-batch bridge missing')
exe=next((shutil.which(x) for x in ('luajit','lua','texlua') if shutil.which(x)),None)
if exe:
    for test in ('tests/weather_thunder_authority_test.lua','tests/audio_thunder_distance_test.lua','tests/audio_psystorm_distance_weight_test.lua'):
        r=subprocess.run([exe,test],cwd=ROOT,text=True,capture_output=True)
        sys.stdout.write(r.stdout); sys.stderr.write(r.stderr)
        ck(r.returncode==0,test+' failed')
else:
    fail.append('no Lua runtime available for thunder authority proof')
if fail:
    for x in fail: print('FAIL '+x)
    sys.exit(1)
print('PASS weather lightning/thunder authority')
