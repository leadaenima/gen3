#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1]
def txt(p): return (R/p).read_text(encoding='utf-8',errors='replace')
ns=txt('lib/NightSky.lua'); sim=txt('lib/CelestialSim.lua'); da=txt('lib/DramalessAtmos.lua'); ca=txt('lib/voxel_atmos/CinematicAtmos.lua'); eng=txt('lib/CelestialEngine.lua'); man=json.loads(txt('manifest.json'))
f=0
def ck(v,m):
 global f; print(('PASS' if v else 'FAIL'),m); f += 0 if v else 1
ver=tuple(int(x) for x in str(man.get('version','0.0.0')).split('.')[:3]); ck(ver >= (8,0,5),'manifest preserves 8.0.5+ celestial/rain/event lineage')
# Sun is not night-gated: body draw is always attempted by CelestialRenderer2 and has its own visibility test.
cr=txt('lib/CelestialRenderer2.lua')
ck('NS.drawSunMoonProjectedWorld' in cr and 'bodies=ok and v==true' in cr,'strict compositor always attempts sun/moon body path')
ck('if visible(b.sun) then' in ns and '_pushProjectedBodyQuad' in ns and '_drawProjectedBody("_projectedSunMesh"' in ns,'projected sun has analytic live geometry/submission path')
ck('altitudeDeg - p.y*radiusDeg < 0.0' in ns and 'discHorizonFraction' in sim and '3.24' in ns,'sun reveals/hides analytic limb-by-limb at horizon')
ck('motionSmoothing = true' in txt('lib/Config.lua') and 'presentationHour' in eng,'presentation clock smoothing remains enabled')
ck('sunColor' in sim and 'sunsetWarmth' in eng and 'golden' in eng,'gradual sunrise/sunset color and world-light authority remain')
ck('local glareStart=18.0' in da and 'local rayAlign=smooth01((15.0-angleDeg)/13.0)' in da and 'local whiteAlign=smooth01((11.5-angleDeg)/10.5)' in da and 'for i=1,28 do' in da and 'math.min(.94,white*.94)' in da,'staged direct-look god rays/whiteout preserved')
ck('sunBlockedByWorld(Voxel3D,sun)' in da,'god rays remain world-occlusion gated')
# 8.1.15 removes the tiled projected body raster entirely: one analytic quad
# per body is shaded continuously, and the world fallback delegates to it.
ck('_projectedBodyShaderSource' in ns and 'float mu=sqrt(max(0.0,1.0-rr));' in ns and 'local cells=20; local pix=rad/cells' not in ns,'projected sun/moon use continuous analytic surfaces without cell seams')
ck('return NightSky.drawSunMoonProjectedWorld(Voxel3D)' in ns,'world fallback shares the analytic seam-free body path')
# Ground mist is now stricter than the old rain-only exception: live 3D mist/fog
# requires an authored WeatherState fog channel, so snow/blizzard/hail/etc cannot
# inherit decorative profile fog either.
ck('function CinematicAtmos._mistPolicy' in ca and 'if f<=0.02 then return 0,false end' in ca,'explicit 3D ground mist requires authored fog channel')
ck('weather.fog,weather._mistVisual=CinematicAtmos._mistPolicy(authoredFog,fogScale)' in ca,'live 3D fog/mist uses authored-channel policy')
# Events.
for token,label in [('Sim.ANOMALISTIC_MONTH','anomalistic/perigee clock'),("moonEvent='SUPERMOON'",'supermoon'),("moonEvent='HARVEST_MOON'",'harvest moon'),("moonEvent='BLUE_MOON'",'blue moon'),("moonEvent='BLOOD_MOON'",'blood moon')]: ck(token in sim,label)
ck('events={primary=moonEvent' in sim and 'solarEclipse=' in sim and 'lunarEclipse=' in sim,'celestial event state exported')
ck('apparentScale=moonScale' in sim and 'tonumber(b.moon.apparentScale)' in ns,'supermoon apparent scale reaches renderer')
ck('appendMeteorsProjected' in ns and 'n=appendMeteorsProjected(verts,n,project)' in ns,'shooting stars render inside strict far-depth projected sky')
ck('FIREBALL_CHANCE = 0.025' in ns and 'fireballEligible=math.random()<FIREBALL_CHANCE' in ns and 'spawnFireball' in ns and 'kind=="fireball"' in ns,'rare fireball/bolide event added and naturally reachable')
ck('setDepthMode, "lequal", false' in ns and 'clip.z = clip.w;' in ns,'projected celestial events retain far-depth LEQUAL occlusion')
print(f'8.0.5+ regression gate: {21-f}/{21} passed, {f} failed'); sys.exit(1 if f else 0)
