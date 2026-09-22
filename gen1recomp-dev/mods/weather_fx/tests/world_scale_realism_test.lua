-- Weather FX 8.1.28 World-Scale Realism executable contract.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end

-- 1) Live flat-world voxel footprint: buildings cast directional wind shelter,
-- forests cool/humidify, water humidifies/fogs, open routes stay exposed.
do
  local map={id='FLAT_REALISM',widthCells=14,heightCells=8}
  function map:cellTile(cx,cz)
    if cx==4 and cz>=2 and cz<=4 then return 2 end
    if cx>=8 and cx<=9 and cz>=2 and cz<=5 then return 3 end
    if cx>=11 then return 4 end
    return 1
  end
  function map:isWaterCell(cx,cz) return cx>=11 end
  local shapes={
    [1]={class='ground',art='flat',h=0},
    [2]={class='building',art='roof',h=24},
    [3]={class='tree',art='canopy',h=18},
    [4]={class='water',art='water',h=-2},
  }
  local TS={forMap=function() return shapes end}
  local VS={groundAt=function(_,cx) if cx==4 then return 24 elseif cx>=8 and cx<=9 then return 18 end return 0 end}
  local F=assert(loadfile(ROOT..'lib/FlatWorldInteraction.lua'))({})
  check(F.observeVoxel({map=map,neighbors={}},VS,TS)==true,'flat-world footprint observes live voxel map')
  local open=F.sampleAt(1*16+8,3*16+8,{},1,0)
  local lee=F.sampleAt(5*16+8,3*16+8,{},1,0)
  local forest=F.sampleAt(8*16+8,3*16+8,{},1,0)
  local water=F.sampleAt(12*16+8,3*16+8,{},1,0)
  check(lee.windShadow>0.45 and lee.windExposure<open.windExposure,'building creates leeward wind shadow on flat route')
  check(forest.canopyFraction>0 and forest.tempBias<0 and forest.humidityBias>0,'forest footprint is cooler and more humid')
  check(water.water==true and water.waterFraction>0 and water.humidityBias>0 and water.fogAffinity>0.5,'large water footprint raises humidity/fog affinity')
  check(open.openFraction>0.7 and open.windExposure>0.7,'open route remains wind exposed')
  check(F.exposureAt(4*16+8,3*16+8)<0.1,'roof/building footprint strongly shelters precipitation')
  check(F.exposureAt(8*16+8,3*16+8)>0.3 and F.exposureAt(8*16+8,3*16+8)<0.6,'canopy is partial shelter rather than indoor ceiling')
end

-- 2) Microclimate consumes horizontal footprint metrics, not mountain labels.
do
  local function run(x,fp)
    local FW={ready=function() return true end,sampleAt=function(_,_,out) for k,v in pairs(fp) do out[k]=v end return out end}
    local V={require=function(name) if name=='FlatWorldInteraction' then return FW elseif name=='WindEngine' then return {peek=function() return {x=1,z=0} end} end end}
    local M=assert(loadfile(ROOT..'lib/Microclimate.lua'))(V)
    M.update(30,{temperature=14,humidity=.45,cloud=.15,storm=.2,wind=.5,visibility=1,precip=.8,aerosol=.05,pressure=1013},x,32,{mapId='FLAT_TEST',indoors=false})
    return M.sample()
  end
  local open=run(32,{shelter=0,built=0,canopyFraction=0,waterFraction=0,openFraction=1,windShadow=0,windExposure=1,tempBias=0,humidityBias=0,fogAffinity=0})
  local town=run(32,{shelter=.45,built=.72,canopyFraction=0,waterFraction=0,openFraction=.28,windShadow=.45,windExposure=.45,tempBias=1.1,humidityBias=-.02,fogAffinity=.05})
  local forest=run(32,{shelter=.58,built=0,canopyFraction=.8,waterFraction=0,openFraction=.2,windShadow=.4,windExposure=.38,tempBias=-1.4,humidityBias=.12,fogAffinity=.30})
  local water=run(32,{shelter=0,built=0,canopyFraction=0,waterFraction=.9,openFraction=.1,windShadow=0,windExposure=1.1,tempBias=-.5,humidityBias=.18,fogAffinity=.85})
  check(town.temperature>open.temperature,'town footprint retains local heat')
  check(forest.temperature<open.temperature and forest.humidity>open.humidity,'forest canopy cools and humidifies local weather')
  check(water.humidity>open.humidity and water.fogAffinity>open.fogAffinity,'water footprint raises local humidity/fog tendency')
  check(town.precip<open.precip and forest.precip<open.precip,'shelter reduces precipitation reaching the local player space')
  check(open.wind>forest.wind and open.wind>town.wind,'open routes remain windier than forest/town shelter')
end

-- 3) Distant weather only describes finite existing StormCells in the useful
-- flat-horizon warning band. 8.1.41 deliberately retains a hydrometeor
-- descriptor at physical contact so the remote bank cannot disappear before the
-- local handoff; extreme-far and dry-sand cells remain excluded.
do
  local cells={
    {id=1,weather='RAIN',x=820,z=0,rx=210,rz=170,age=40,life=100},
    {id=2,weather='SNOW',x=1200,z=200,rx=250,rz=220,age=50,life=100},
    {id=3,weather='RAIN',x=100,z=0,rx=100,rz=100,age=50,life=100},
    {id=4,weather='RAIN',x=4200,z=0,rx=200,rz=200,age=50,life=100},
    {id=5,weather='SAND',x=900,z=-300,rx=220,rz=180,age=50,life=100},
  }
  local SC={cells=function() return cells end}
  local T={get=function(id)
    if id=='SNOW' then return {ch={snow=.9,dim=.3}} end
    if id=='SAND' then return {ch={sand=.9,gust=.8,dim=.3}} end
    return {ch={rain=.8,strike=8,dim=.35}}
  end}
  local V={require=function(name) if name=='StormCells' then return SC elseif name=='Types' then return T end end}
  local D=assert(loadfile(ROOT..'lib/DistantWeather.lua'))(V)
  D.update(.2,0,0)
  local items,n=D.items()
  check(n==3 and items[1].id==3,'distant observer retains contact hydrometeor handoff while rejecting extreme/dry-sand cells')
  check(items[1].edge<=items[2].edge,'distant weather descriptors are sorted nearest edge first')
  check(items[1].shaft>0 and items[2].shaft>0,'rain/snow cells publish visible shaft authority')
  check(D.stats().max==4 and D.stats().flatWorld==true,'distant observer is bounded and explicitly flat-world')
end

-- 4) Acoustic shelter is local structure/canopy physics, not terrain relief.
do
  local function mix(climate)
    local A=assert(loadfile(ROOT..'lib/AcousticModel.lua'))({})
    A.update(5,climate,{wet=.7},{indoors=false})
    return A.sample()
  end
  local open=mix({precip=.9,wind=.8,storm=.8,humidity=.6,shelter=0,canopy=0,built=0,water=0})
  local town=mix({precip=.9,wind=.8,storm=.8,humidity=.6,shelter=.75,canopy=0,built=.8,water=0})
  local forest=mix({precip=.9,wind=.8,storm=.8,humidity=.7,shelter=.55,canopy=.8,built=0,water=0})
  local shore=mix({precip=.9,wind=.8,storm=.8,humidity=.8,shelter=0,canopy=0,built=0,water=.9})
  check(town.rainGain<open.rainGain and town.windGain<open.windGain,'buildings suppress local rain/wind sound')
  check(town.thunderGain<open.thunderGain,'town structures partially muffle thunder')
  check(forest.highCut<open.highCut,'forest canopy muffles high-frequency rain detail')
  check(shore.waterStormGain>open.waterStormGain,'stormy water publishes stronger water ambience authority')
end

print(('world-scale realism 8.1.28: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
