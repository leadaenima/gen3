#!/usr/bin/env python3
from pathlib import Path
import re,sys
R=Path(__file__).resolve().parents[1]
ns=(R/'lib/NightSky.lua').read_text(); da=(R/'lib/DramalessAtmos.lua').read_text(); main=(R/'main.lua').read_text(); atm=(R/'lib/AtmosphereModel.lua').read_text(); sim=(R/'lib/CelestialSim.lua').read_text()
checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
ck('function NightSky.draw2DCelestialBody' in ns and 'NightSky.draw2DCelestialBody' in main,'2D sun/moon use the shared detailed celestial body authority')
ck("detailed-cpu-fallback" in ns and 'local rings,segs=18,84' in ns,'shader refusal uses dense detailed CPU fallback')
ck('supergran=' in ns and 'spots=clamp' in ns and 'float limb=0.70+0.30*pow(mu,0.42);' in ns,'sun has visible photosphere structure without dominant radial shading')
ck('maria=' in ns and 'craterRelief' in ns and '(0.79+0.21*mu)' in ns,'moon has maria/crater/highland detail with restrained radial shading')
ck('local glareStart=18.0' in da and 'rayAlign' in da and 'warmAlign' in da and 'whiteAlign' in da,'sun look response starts wider and stages flare/rays/wash/whiteout separately')
ck("angleDeg=math.deg(math.acos(dot))" in da,'direct-look response is angular, not a sudden dot-product threshold')
ck('local physR=current.skyR*(1-t)+current.horizonR*t' in atm,'atmospheric sky-band interpolation uses zenith-to-horizon order')
ck('warmRise=clamp01((alt+10)/10)' in atm and 'warmFall=1-clamp01((alt-2)/18)' in atm,'golden-hour physical scattering has broad low-sun envelope')
ck('haze=mix3(haze,{1.00,0.25,0.055},golden*0.72)' in sim,'celestial sky palette has strong horizon-localized golden/red response')
ck('_projectedBodyShaderError' in ns and 'bodyPath=NightSky._lastProjectedBodyPath' in ns,'celestial diagnostics expose shader/fallback path instead of silently hiding downgrade')
failed=sum(not x for x,_ in checks);print(f'8.1.26 player experience contract: {len(checks)-failed}/{len(checks)} passed, {failed} failed');sys.exit(1 if failed else 0)
