#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
night=(ROOT/'lib/NightSky.lua').read_text(); bod=(ROOT/'lib/CelestialBodies.lua').read_text(); da=(ROOT/'lib/DramalessAtmos.lua').read_text(); sim=(ROOT/'lib/CelestialSim.lua').read_text(); failed=0
def ck(x,m):
 global failed; print(('PASS' if x else 'FAIL'),m); failed += 0 if x else 1
ck('function Sim.sunHorizonHalo' in sim,'simulation retains smooth horizon optical metadata for atmospheric scattering')
world=night.split('function NightSky.drawSunMoonWorld',1)[1].split('local _CelestialSim',1)[0]
ck('core*2.2' not in world and 'core*1.35' not in world,'world sun/moon bodies have no passive billboard halo')
ck('local MOON_CRATERS' in night and 'moonSurface' in night,'moon is cratered reflected-light geometry')
ck('glowAmt=0' in bod,'legacy projected body glow is hard-zero')
ck('a*0.22*halo' not in bod and 'a*0.42*halo' not in bod,'CelestialBodies does not attach solar halo quads')
ck('local glareStart=18.0' in da and 'if angleDeg>=glareStart then' in da and 'outside-look-cone' in da,'sun can sit in frame without glare outside staged direct-look cone')
ck('for i=1,28 do' in da and 'love.graphics.polygon' in da,'direct look generates radial god rays')
ck('local whiteAlign=smooth01((11.5-angleDeg)/10.5)' in da and 'local white=(whiteAlign^1.55)*trans*bodyA*rise' in da and 'math.min(.94,white*.94)' in da,'near-perfect aim produces strong staged full-frame whiteout')
ck('discTransmission' in da and '^1.25' in da,'cloud transmission attenuates god rays')
ck('function DayNight.glow' in da and 'return 0,nil' in da,'host celestial glow is suppressed under Weather FX ownership')
ck('altitudeDeg - p.y*radiusDeg < 0.0' in night and '3.24' in night and '2.16' in night,'analytic projected sun/moon reveal limb-by-limb at horizon')
print(f'halo-free direct-sun static gate: {11-failed} passed, {failed} failed'); sys.exit(1 if failed else 0)
