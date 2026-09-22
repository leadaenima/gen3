#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,n):
    checks.append((bool(v),n))
    if not v: print('FAIL',n)
def t(p): return (R/p).read_text(encoding='utf-8',errors='replace')
rt=t('lib/EngineRuntime.lua'); main=t('main.lua'); wp=t('lib/voxel_atmos/WorldPrecip.lua'); ca=t('lib/voxel_atmos/CinematicAtmos.lua'); pg=t('lib/PerformanceGovernor.lua')
mods=['WorldClimate','WindFlow','Hydrology','AccumulationGeometry','DynamicLighting','VolumetricWeather','EcosystemEngine','ForecastEngine','EnvironmentSDK','PredictiveBudget','SevereWeather','TerrainPhysics','EnvironmentPersistence','WeatherPluginRegistry']
for m in mods: ck((R/'lib'/f'{m}.lua').is_file() and (R/'lib'/f'{m}.lua').stat().st_size>0,f'{m} runtime module present')
for pid in ['world_climate','volumetric_weather','wind_flow','hydrology','accumulation_geometry','dynamic_lighting','severe_weather','ecosystem','predictive_budget']:
    ck(pid in rt,f'EngineRuntime schedules {pid}')
ck(('WC.sampleAt(x,z)' in rt or 'WC.sampleAt(c.worldX,c.worldZ)' in rt) and ('M.update(c.dt,base,x,z,c.scene)' in rt or 'M.update(c.dt,base,c.worldX,c.worldZ,c.scene)' in rt),'microclimate consumes spatial whole-world climate')
ck('meta.volume=frame.volumeWeather' in ca and 'volumeWeather.shadowScale' in ca,'3D atmosphere/precip paths consume volumetric weather descriptors')
ck('V.require,"WindFlow"' in wp and 'farPrecipScale' in wp,'world precipitation consumes local flow and far-field volume scale')
ck('PredictiveBudget' in pg and 'math.min(base,tonumber(v))' in pg,'performance governor combines reactive and predictive particle budgets')
atm=t('lib/AtmosphereModel.lua')
ck('rayleighR' in atm and 'turbidity' in atm and 'horizonExtinction' in atm and 'skyR' in atm,'atmosphere model exposes wavelength scattering/turbidity/horizon colour state')
ck('mod.exports.environmentSDK' in main and 'mod.exports.weatherForecast' in main and 'mod.exports.worldClimate' in main,'public SDK/forecast/world climate APIs exported')
ck('mod.exports.environmentSave' in main and 'mod.exports.environmentRestore' in main and 'mod.exports.environmentPlugins' in main,'persistence and plugin registry APIs exported')
failed=sum(not ok for ok,_ in checks)
print(f'environment engine 3 static gate: {len(checks)-failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
