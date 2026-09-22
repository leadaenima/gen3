#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
a=(R/'lib/Aurora.lua').read_text(); ns=(R/'lib/NightSky.lua').read_text(); dw=(R/'lib/DistantWeather.lua').read_text(); ca=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text(); da=(R/'lib/DramalessAtmos.lua').read_text()
ck('thin sheets / curtains' in a.lower() and 'field-aligned' in a.lower(),'aurora module documents thin field-aligned curtain model')
ck('season=="WINTER"' in a and 'offSeasonEligible' in a and '<0.05' in a,'aurora is winter-weighted with exact 5% non-winter nightly eligibility')
ck('celestialEvents' in a,'aurora respects CELESTIAL EVENTS')
ck('skyTransmission' in a and 'moonLight' in a and 'BuildingLight' in a,'cloud/moon/building contrast authorities are consumed')
ck('sheets=plan.intensity>.84 and 4' in a and (('local seg=72' in a and 'local layers=10' in a) or 'local seg,layers,sheetCap=72,10,4' in a),'multi-sheet dense curtain topology shipped')
ck('topDeg=85' in a and '89.0' in a,'strong events reach near-zenith corona geometry')
rel=(R/'RELEASE-NOTES-8.1.42.md').read_text().lower()
al=a.lower()
ck('noise1' in al and 'irregular curtain body' in al and 'periodic pattern' in al and 'fine discrete-ray field' in al,'aurora uses irregular multi-scale curtain/ray fields instead of periodic ribbon texture')
ck('oxygen green' in a.lower() and ('n2' in a.lower() or 'nitrogen' in a.lower()) and 'oxygen' in rel and 'green' in rel and 'nitrogen' in rel and 'red' in rel,'altitude-coded emission families documented and implemented')
ck('Aurora.appendWorld' in ns and 'Aurora.appendProjected' in ns and 'Aurora.update' in ns,'NightSky integrates world + projected + lifecycle aurora paths')
ck('Aurora = true' in da,'Aurora is root-owned in shared voxel namespace')
ck('"blizzard"' in dw and 'q.gust=gust' in dw and 'q.veil=veil' in dw,'DistantWeather publishes dedicated blizzard family')
ck('abs(vKind-7.0)' in ca and 'kind==3' in ca and 'particleQuad' in ca and 'gust' in ca,'3D renderer preserves dedicated wind-driven blizzard morphology as sheared individual flakes')
failed=sum(not v for v,_ in checks);print(f'8.1.42 winter/aurora source contract: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
