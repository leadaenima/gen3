#!/usr/bin/env python3
"""Weather FX 8.1.16 professional celestial-quality regression contract."""
from pathlib import Path
import json,re,sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,msg):
    checks.append((bool(v),msg))
    if not v: print('FAIL:',msg)
man=json.loads((R/'manifest.json').read_text())
ns=(R/'lib/NightSky.lua').read_text(); con=(R/'lib/Constellations.lua').read_text()
da=(R/'lib/DramalessAtmos.lua').read_text(); ca=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
sim=(R/'lib/CelestialSim.lua').read_text()
ck(tuple(map(int,man.get('version','0.0.0').split('.'))) >= (8,1,16),'manifest is 8.1.16 or newer')
ck(tuple(map(int,(R/'BASELINE').read_text().strip().split('.'))) >= (8,1,16),'baseline is 8.1.16 or newer')
# Sun must use continuous multi-scale material, not flat/floor-cell granulation.
for token in ('float valueNoise','float fbm','network=abs(n1-n2)','facula','pen1=softEllipse','pow(mu,0.42)','bodyTime'):
    ck(token in ns,'sun material contains '+token)
ck('h21(floor((p+1.0)*23.0)' not in ns,'old quantised solar granulation removed')
# Moon relief must be materially richer than five painted circles.
ck(ns.count('craterRelief(p,')>=10,'moon has >=10 physical crater relief calls')
for token in ('highlands=','maria=1.0','Tycho-like','earth=0.018','softEllipse'):
    ck(token in ns,'moon material contains '+token)
# Lens flare remains subordinate to the existing occlusion/rise authority.
for token in ('Atmos._lastLensFlareCount','flareStrength=(glare^1.30)','softDisc','local ghosts={','sunBlockedByWorld','solarRayRamp'):
    ck(token in da,'direct-sun optics contain '+token)
ck(re.search(r'local ghosts=\{[\s\S]*?\n\s*\}',da) is not None,'lens ghost catalogue exists')
# Existing 28-ray god-ray path remains intact.
ck('for i=1,28 do' in da and 'local rays=(rayAlign^1.25)*trans*bodyA*rise' in da,'existing 28-ray god-ray fan preserved through staged optics')
# Both cloud shader paths get directional forward scatter.
ck(ca.count('forwardGlow')>=2,'both cloud shader paths use forward scattering')
ck(ca.count('solarVis')>=2,'cloud effects remain first-limb solar gated')
# Unified constellation authored brightness; smooth building multiplier reaches world + projected paths.
ck(('a=primary and 1.00 or .84' in con) or ('a=primary and .96 or .73' in con),'all constellations share one brightness hierarchy')
ck('buildingScale=math.max' in con and '*fade*buildingScale*' in con,'world constellations consume building scale')
ck('local function constellationBuildingScale()' in ns,'constellation building authority exists')
ck('return starScaleNow()' in ns and 'if starScale < 0.4 then starScale = 0.4 end' in ns,'building dimming retains readability with shared star authority')
ck('constellationBuildingScale()' in ns and '*constVis*constBuilding*' in ns,'world/projected paths apply building dimming')
# Sunrise/sunset remains continuous and uses warmer photographic low-sun palette.
ck('local solarRayRamp=' in (R/'lib/CelestialEngine.lua').read_text(),'first-limb god-ray ramp preserved')
ck('{1.00,0.63,0.22}' in sim and '{1.00,0.985,0.94}' in sim,'sun color curve upgraded')
failed=sum(not x for x,_ in checks)
print(f'8.1.16 celestial quality contract: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
