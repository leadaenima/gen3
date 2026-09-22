local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end
local optionValues={quality='auto'}
local mod={id='weather_fx',options={get=function(_,k) return optionValues[k] end}}
local cache={}
local V={mod=mod}
function V.require(name)
  if cache[name] then return cache[name] end
  local f=assert(loadfile('lib/'..name..'.lua')); local m=f(V); cache[name]=m; return m
end

-- Whole-world coarse climate is bounded, spatial and forecastable.
local WC=V.require('WorldClimate')
local macro={pressure=1003,temperature=11,humidity=.72,cloud=.68,storm=.55,wind=.62,precip=.58,visibility=.82,aerosol=.08}
for i=1,12 do WC.update(1,macro,0,0) end
local ws=WC.stats(); local a=WC.sampleAt(0,0); local b=WC.sampleAt(4096,2048)
check(ws.cells>0 and ws.cells<=256 and ws.cellSize==1024,'world climate maintains bounded lazy whole-world cells')
check(a.pressure~=b.pressure or a.humidity~=b.humidity,'distant world climate cells are spatially distinct')
local fc=WC.forecastAt(0,0,300)
check(fc.seconds==300 and type(fc.summary)=='string' and fc.pressure==fc.pressure,'world climate exposes deterministic forecast state')
local snap=WC.snapshot(256); WC.reset(); check(WC.stats().cells==0,'world climate reset clears live cells'); check(WC.restore(snap) and WC.stats().cells>0,'world climate snapshot restores persistent fronts')

-- Local flow field bends global wind without camera dependence.
local Wind=V.require('WindEngine'); Wind.update(1,{id='GALE',ch={gust=1}})
local WF=V.require('WindFlow'); for i=1,12 do WF.update(.2,0,0,{mapId='Viridian Forest'}) end
local forest=WF.sampleAt(0,0); for i=1,12 do WF.update(.2,0,0,{mapId='Open Route'}) end; local openRoute=WF.sampleAt(0,0)
check(forest.speed>=0 and openRoute.speed>=0 and WF.stats().cells==81,'wind-flow field maintains bounded 9x9 world grid')
check(openRoute.speed>=forest.speed,'open-route flow remains less sheltered than forest flow')

-- Volumetric weather state has real 3D cell occupancy and far-field metadata.
local VW=V.require('VolumetricWeather'); VW.update(1,0,0,{cloud=.8,precip=.75,storm=.7},{density=.85,charge=.7},WC.sampleAt(0,0)); local vol=VW.sample()
check(vol.cells==75 and vol.cloudVolume>0 and vol.precipVolume>0,'volumetric weather maintains bounded 5x5x3 field')
check(vol.lightTransmission<1 and vol.farPrecipScale>=.72,'weather volume exposes light transmission and far precipitation scale')

-- Predictive budget trims before measured pressure needs to react.
local PB=V.require('PredictiveBudget'); for i=1,20 do PB.update(.1,{precip=.95,storm=.95},vol) end; local pb=PB.sample()
check(pb.predicted>.5 and pb.particleScale<1 and pb.headroom<1,'predictive budget pre-trims heavy environmental workload')

-- Hydrology + accumulation geometry.
local Hy=V.require('Hydrology'); for i=1,40 do Hy.update(.25,0,0,{precip=1,temperature=12,wind=.4}) end; local hy=Hy.sampleAt(0,0)
check(hy.water>0 and hy.depth>=0,'hydrology accumulates rainwater/runoff state')
local AG=V.require('AccumulationGeometry'); for i=1,10 do AG.update(.2,{snow=.8,leaves=.5,puddle=.7,mud=.4,frost=.3,ice=.2},hy) end; local ag=AG.sample()
check(ag.snowHeight>0 and ag.leafHeight>0 and ag.puddleDepth>0,'accumulation geometry derives visible depth descriptors')

-- Dynamic lighting responds to snow/wet/cloud/storm/celestial state.
local DL=V.require('DynamicLighting'); for i=1,10 do DL.update(.1,{storm=.7,cloud=.8},{snow=.8,wet=.9,reflectivity=.6},{sunLight=.8,moonLight=0},{density=.8}) end; local dl=DL.sample()
check(dl.snowBounce>0 and dl.wetSpecular>0 and dl.cloudShadow>0,'dynamic lighting reacts to snow wetness and clouds')
local At=V.require('AtmosphereModel'); At.update(.2,{cloud=.2,visibility=.95,aerosol=.03},{sun={altitudeDeg=45}},{density=.2,transmission=.9}); local day=At.grade(); At.update(.2,{cloud=.25,visibility=.9,aerosol=.08},{sun={altitudeDeg=2}},{density=.25,transmission=.82}); local dusk=At.grade()
check(day.rayleighB>day.rayleighR and day.skyB>day.skyR,'physical atmosphere preserves blue Rayleigh dominance at high sun')
check(dusk.warmth>day.warmth and dusk.horizonR>dusk.horizonB,'physical atmosphere warms and reddens the low-sun horizon')

-- Severe weather classification + ecosystem reactions.
local SW=V.require('SevereWeather'); local EE=V.require('EnvironmentalEvents'); local before=EE.stats().serial
for i=1,20 do SW.update(.2,{storm=.95,precip=.9,temperature=15,aerosol=.1},{},{charge=.95},{speed=1.2}) end
local sev=SW.sample(); check(sev.type=='supercell' or sev.type=='squall','severe-weather engine classifies convective events')
check(EE.stats().serial>before,'severe-weather transitions publish environmental events')
local Eco=V.require('EcosystemEngine'); for i=1,20 do Eco.update(.2,{storm=.9,precip=.85,wind=.9,temperature=8,visibility=.5},nil,{ice=.3}) end; local eco=Eco.sample()
check(eco.shelter>.6 and eco.flyingActivity<eco.waterActivity,'ecosystem engine produces weather-aware shelter/activity state')

-- Terrain physics stays opt-in/read-only and derives traction/speed.
local TP=V.require('TerrainPhysics'); local dry=TP.response({friction=.9,ice=0,mud=0,snow=0,puddle=0},{},{speed=.2}); local icy=TP.response({friction=.9,ice=.9,mud=.2,snow=.7,puddle=.5},{snowHeight=2.2},{speed=1})
check(icy.traction<dry.traction and icy.speedScale<dry.speedScale and icy.deepSnow,'terrain physics exposes lower traction/speed for ice/deep snow')

-- Surface persistence round-trip.
local ES=V.require('EnvironmentSurface'); ES.setMaterial(64,64,'stone'); ES.depositWet(64,64,.8); ES.depositLeaves(64,64,.4); local rows=ES.snapshot(128)
check(#rows>0,'environment surface produces persistent snapshot')
check(ES.restore(rows)==true,'environment surface restores snapshot')
local restored=ES.sample(64,64); check(restored.wet>0 and restored.leaves>0,'restored surface keeps wetness and leaves')
local EP=V.require('EnvironmentPersistence'); local saved=EP.snapshot(); check(type(saved.worldClimate)=='table' and type(saved.surface)=='table','versioned environment persistence captures climate and surface state'); check(EP.restore(saved)==true,'environment persistence restores its own snapshot')

-- SDK / forecast / plugin registry contracts.
local SDK=V.require('EnvironmentSDK'); local ss=SDK.snapshot(0,0); local timeline=V.require('ForecastEngine').timeline(0,0,4,120)
check(type(ss)=='table' and ss.worldClimate and ss.volume and ss.lighting,'environment SDK aggregates advanced world state')
check(#timeline==4 and timeline[4].seconds==480,'forecast timeline returns future world-climate samples')
local Reg=V.require('WeatherPluginRegistry'); check(Reg.register('test','surface_overlay',function(v) return v+1 end),'plugin registry accepts namespaced provider'); local calls=Reg.call('surface_overlay',2)
check(#calls==1 and calls[1].value==3,'plugin registry calls companion provider safely')

print(('environment engine 3: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
