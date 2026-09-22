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

-- Multi-rate render graph: simulation may run at 10 Hz while presentation can
-- remain frame-rate smooth, and the pass receives accumulated dt.
local RG=V.require('RenderGraph'); local g=RG.new('multi',{'sim'}); local calls,got=0,0
g:register('sim','slow',function(c) calls=calls+1; got=c.dt end,{interval=.1})
for i=1,5 do g:executeStage('sim',{dt=.02}) end
check(calls==1 and math.abs(got-.1)<.0001,'render graph executes fixed-rate simulation with accumulated dt')
check((g:stats().passes.slow.skipped or 0)==4,'render graph reports skipped multi-rate work')

-- Performance governor cuts AUTO internal workload under sustained bad frame
-- time without changing manual tiers.
local Config=V.require('Config'); Config.data={quality='auto',maxParticles=999999}
local PG=V.require('PerformanceGovernor'); PG.reset()
for i=1,180 do PG.update(.040) end
check(PG.scale()<.90 and PG.particleScale()<.95,'AUTO governor reduces transient work under sustained late frames')
optionValues.quality='high'; PG.reset(); for i=1,180 do PG.update(.040) end
check(math.abs(PG.scale()-1)<.0001,'manual quality remains literal and is not silently downscaled')
optionValues.quality='auto'; PG.reset()

-- Spatial microclimate differentiates biome-like maps while remaining bounded.
local MC=V.require('Microclimate')
local base={pressure=1010,humidity=.5,temperature=15,cloud=.4,storm=.2,wind=.3,visibility=.9,precip=.2,aerosol=.1}
for i=1,20 do MC.update(.25,base,100,100,{mapId='Viridian Forest',indoors=false}) end
local forest=MC.sample()
for i=1,20 do MC.update(.25,base,100,100,{mapId='Celadon City',indoors=false}) end
local city=MC.sample()
check(forest.humidity>city.humidity and forest.temperature<city.temperature,'forest/city microclimates diverge in humidity and temperature')
check(forest.dewPoint==forest.dewPoint and forest.visibility>=0 and forest.visibility<=1,'microclimate derives bounded dew point/visibility')

-- Cloud field is spatial, bounded and charge-aware.
local CF=V.require('CloudField'); CF.update(3,{cloud=.8,humidity=.8,storm=.7,wind=.5},0,0); local cfs=CF.stats(); local cf=CF.sampleAt(0,0)
check(cfs.cells==49 and cf.density>0 and cf.transmission>0 and cf.transmission<=1,'cloud field maintains bounded 7x7 spatial volume cells')
check(cfs.charge>0,'storm climate produces electrical cloud charge')

-- Material response and sparse environmental surface state.
local Mat=V.require('MaterialSystem'); local dry=Mat.response('stone',{wet=0,ice=0,snow=0}); local wet=Mat.response('stone',{wet=1,ice=0,snow=0})
check(wet.reflectivity>dry.reflectivity and wet.roughness<dry.roughness,'wet materials become shinier/smoother')
local ES=V.require('EnvironmentSurface'); ES.setMaterial(32,32,'pavement'); ES.depositWet(32,32,1)
for i=1,20 do ES.update(.25,32,32,{temperature=10,humidity=.9}) end
local surf=ES.sample(32,32)
check(surf.material=='pavement' and surf.wet>0 and surf.puddle>0,'nonporous wet surface develops persistent puddle state')
check(surf.reflectivity>Mat.profile('pavement').reflectivity,'surface sample exposes material-derived wet reflectivity')
ES.setMaterial(48,48,'soil'); ES.depositWet(48,48,1); for i=1,20 do ES.update(.25,48,48,{temperature=8,humidity=.9}) end
check(ES.sample(48,48).mud>0,'wet soil develops mud state')

-- Dormant surface state compacts without losing data.
ES.depositLeaves(0,0,.4); ES.update(.25,2000,2000,{temperature=10,humidity=.4})
for i=1,20 do ES.update(.25,2000,2000,{temperature=10,humidity=.4}) end
check((ES.stats().packedChunks or 0)>=1,'sleeping environmental chunks compact persistent cell data')
check(#ES.snapshot(256)>=1,'compacted environmental cells remain recoverable')

-- Spatial index can update/remove records without stale duplicate cells.
local SI=V.require('SpatialIndex'); local idx=SI.new(64); idx:insert('npc',0,0,0,{}); idx:update('npc',256,0,0,{moved=true})
check(#idx:queryRadius(0,0,32,{})==0 and #idx:queryRadius(256,0,32,{})==1,'spatial index update removes stale cell membership')
idx:remove('npc'); check(idx:stats().count==0,'spatial index remove releases record')

-- Environmental acoustics and event API.
local AM=V.require('AcousticModel'); AM.update(1,{storm=.8,wind=.8,humidity=.8},{wet=.9},{indoors=false}); local outdoor=AM.sample(); AM.update(2,{storm=.8,wind=.8,humidity=.8},{wet=.9},{indoors=true}); local indoor=AM.sample()
check(indoor.rainGain<outdoor.rainGain and indoor.windGain<outdoor.windGain,'environmental acoustics attenuate rain/wind indoors')
local EE=V.require('EnvironmentalEvents'); local seen=0; EE.subscribe('*',function() seen=seen+1 end); EE.update(.2,{storm=.8,temperature=-4,precip=.9,visibility=.4},{wet=.5},{mapId='test'})
check(seen>=3 and EE.stats().queued>=3,'environment event bus publishes severe-condition transitions')
check(#EE.recent(0,{})==EE.stats().queued,'environment event history is readable by companion mods')
local EB=V.require('EnvironmentBehavior'); local npc=EB.npc({storm=.9,precip=.8,wind=.7,temperature=8},{ice=.2,mud=.1}); local water=EB.pokemon('WATER',{precip=.9,humidity=.9,storm=.2,temperature=15},{})
check(npc.seekShelter>.7 and npc.avoidOpen>.7,'NPC behavior hints react strongly to severe weather')
check(water>1,'Pokémon environment affinity API boosts water-type activity in wet weather')
local EH=V.require('EngineHealth'); local health=EH.sample({passes={a={calls=5,skipped=3,errors=0,max=.002}},performance={scale=.8,memoryKB=1024}})
check(health.healthy and health.skipped==3 and health.workScale==.8,'engine health summarizes pass/performance diagnostics')

print(('environment engine 2: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
