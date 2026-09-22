#!/usr/bin/env python3
"""Weather FX 8.1.15 celestial optics / sunrise-cloud regression contract."""
from pathlib import Path
import json, math, re, sys
R=Path(__file__).resolve().parents[1]
def text(rel): return (R/rel).read_text(encoding='utf-8',errors='replace')
ns=text('lib/NightSky.lua'); sim=text('lib/CelestialSim.lua'); bodies=text('lib/CelestialBodies.lua')
eng=text('lib/CelestialEngine.lua'); da=text('lib/DramalessAtmos.lua'); ca=text('lib/voxel_atmos/CinematicAtmos.lua')
man=json.loads(text('manifest.json'))
checks=[]
def ck(v,n): checks.append((bool(v),n)); print(('PASS ' if v else 'FAIL ')+n)

ck(tuple(map(int,man.get('version','0.0.0').split('.'))) >= (8,1,15),'manifest is 8.1.15 or newer')
ck(tuple(map(int,(R/'BASELINE').read_text().strip().split('.'))) >= (8,1,15),'baseline is 8.1.15 or newer')
ck('local SUN_HALF, MOON_HALF = 15.84, 10.08' in bodies,'3D base body sizes are exactly 40% smaller')
ck('1+0.35*clamp01' not in bodies and '1+0.30*clamp01' not in bodies,'sun/moon no longer swell with altitude')
ck('discHorizonFraction(sAltDeg,3.24)' in sim and 'discHorizonFraction(mAltDeg,2.16)' in sim,'horizon contact radii match reduced 3D bodies')

analytic=ns.split('analytic celestial',1)[1].split('function NightSky.projectedProof()',1)[0]
ck('_projectedBodyShaderSource' in analytic and '_pushProjectedBodyQuad' in analytic,'active 3D bodies use one analytic quad each')
ck('local cells=20' not in analytic and 'pix*.515' not in analytic,'active analytic body path contains no tiled cell raster')
ck('float limb=0.70+0.30*pow(mu,0.42);' in analytic and 'gran=' in analytic and ('spot1=' in analytic or 'pen1=' in analytic) and 'supergran=' in analytic,'sun surface has detailed granulation/sunspots with restrained limb darkening')
ck('litMask' in analytic and 'maria=' in analytic and ('craters=' in analytic or 'craterRelief' in analytic) and 'earth=' in analytic,'moon surface has continuous phase/maria/crater/earthshine shading')
ck('altitudeDeg - p.y*radiusDeg < 0.0' in analytic,'analytic body shader clips the correct lower limb at the horizon')
ck('clip.z = clip.w;' in analytic and 'setDepthMode,"lequal",false' in analytic,'analytic bodies retain far-depth world occlusion')
ck('return NightSky.drawSunMoonProjectedWorld(Voxel3D)' in ns,'NightSky world fallback redirects to analytic body path')
ck('function NightSky._drawProjectedBodyFallback' in ns and 'FallbackMesh' in ns and 'local rings,segs=18,84' in ns and 'detailed-cpu-fallback' in ns,'shader refusal falls back to a dense textured circular body instead of a flat disc')
ck('type(NS.drawSunMoonProjectedWorld)=="function"' in bodies and 'pcall(NS.drawSunMoonProjectedWorld,Voxel3D)' in bodies,'direct CelestialBodies callers redirect to analytic path')

ck('local solarDisc=clamp01(tonumber(sim.sun.horizonFraction) or 0)' in eng,'solar optics start from visible limb fraction')
ck('local solarRise=smoothRange(-3.24,14.0,solarAlt)' in eng and '0.18*sqrt(solarDisc)+0.82*solarRise' in eng,'god-ray onset is a continuous first-limb/altitude ramp')
ck('local solarEnergy=0.12+0.88*clamp01' in eng,'first visible limb retains a faint nonzero ray-energy floor')
ck('solarDisc>0 and' in eng,'ray ramp remains exactly zero with the complete sun below horizon')
ck('local twilightIn=smoothRange(-12,-1.5,alt)' in eng and 'local highSunOut=1-smoothRange(6,28,alt)' in eng,'golden-hour warmth uses broad optical-depth envelope')

ck('tonumber(frame.sunShearX) or ShadowMap.KX' in ca and 'tonumber(frame.sunShearZ) or ShadowMap.KZ' in ca,'world god-ray geometry prefers the real solar direction')
ck('cloudTransmissionAlongRay(clouds, cx, groundY, cz, 0, 0, kx, kz)' in ca,'clouds attenuate rays along the solar path')
ck(ca.count('uniform float sunDiscVisibility;')>=2 and ca.count('uniform float solarRayRamp;')>=2,'both cloud shader backends receive limb/rise optics')
ck('float facing' in ca and 'float away' in ca and 'float warmMix' in ca and 'backShade' in ca,'cloud lighting has sun-facing scatter and cooler away-facing shading')
ck('sh.send, sh, "sunDiscVisibility"' in ca and 'sh.send, sh, "solarRayRamp"' in ca,'fallback cloud shader uploads solar visibility/ramp')
ck(ca.count('ist.shader.send,ist.shader,"sunDiscVisibility"')>=1 and ca.count('ist.shader.send,ist.shader,"solarRayRamp"')>=1,'instanced cloud shader uploads solar visibility/ramp')
ck('if (tonumber(frame.sunDiscVisibility) or 0)>0 then skx,skz=frame.sunShearX,frame.sunShearZ end' in ca,'cloud observation follows sun even while moon owns shadow map')

ck('local discVis=clamp01(tonumber(st and st.solarDiscVisibility)' in da and 'local rise=clamp01(tonumber(st and st.solarRayRamp)' in da,'direct-look optics consume first-limb solar state')
ck('(tonumber(sun.dy) or -1)<=-.02' not in da,'direct-look optics no longer wait for old sun-centre altitude cutoff')
ck('glareStart=18.0' in da and 'rayAlign' in da and 'warmAlign' in da and 'whiteAlign' in da and 'trans*bodyA*rise' in da,'flare, rays, warm wash and whiteout use separate gradual gaze ramps plus sunrise/cloud attenuation')

# Numerical proof of the authored ramp: exact zero before contact, then smooth
# monotonic growth across first limb/low sky. This mirrors the Lua formula.
def clamp01(x): return max(0.0,min(1.0,x))
def smooth01(x):
    x=clamp01(x); return x*x*(3-2*x)
def smooth(a,b,x): return smooth01((x-a)/(b-a))
def disc(alt,r=3.24):
    x=alt/r
    if x<=-1: return 0.0
    if x>=1: return 1.0
    return clamp01(0.5+(math.asin(x)+x*math.sqrt(max(0,1-x*x)))/math.pi)
def ray(alt):
    d=disc(alt); rise=smooth(-3.24,14.0,alt)
    ramp=clamp01(.18*math.sqrt(d)+.82*rise) if d>0 else 0.0
    sun_i=smooth(-4,12,alt)
    return ramp, ramp*(.12+.88*sun_i)
vals=[ray(a)[1] for a in (-3.30,-3.23,-3.0,-1.0,2.0,6.0,14.0)]
ck(vals[0]==0 and vals[1]>0,'ray strength starts immediately after first limb clears horizon')
ck(all(vals[i]<=vals[i+1]+1e-12 for i in range(len(vals)-1)),'sunrise ray strength grows monotonically through low-sun ramp')
ck(ray(14.0)[0] > .99,'solar ramp reaches authored full strength smoothly by 14 degrees')

failed=sum(not ok for ok,_ in checks)
print(f'8.1.15 celestial optics contract: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
