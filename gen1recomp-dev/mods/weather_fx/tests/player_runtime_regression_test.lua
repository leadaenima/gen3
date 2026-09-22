-- 8.1.11 player-runtime regressions. These are intentionally integration-ish:
-- each assertion reproduces a bug that passed narrower module tests in 8.1.10.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end
local function approx(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end

-- Scheduler: passes slower than 0.5 s must execute; AUTO stretching may create these.
do
  local RG=assert(loadfile('lib/RenderGraph.lua'))({})
  local g=RG.new('player-regression',{'x'})
  local n75,n51=0,0
  g:register('x','i75',function() n75=n75+1 end,{interval=.75})
  g:register('x','i51',function() n51=n51+1 end,{interval=.51})
  for _=1,200 do g:executeStage('x',{dt=.1}) end
  check(n75>=25 and n75<=27,'0.75 s scheduled pass executes over 20 seconds')
  check(n51>=38 and n51<=40,'0.51 s stretched pass remains schedulable')
end

-- Region prefixes: ROUTE_1 must never steal ROUTE_10 etc.
do
  local mod={save={set=function() end,get=function(_,_,d) return d end}}
  local V={mod=mod}
  local Types=assert(loadfile('lib/Types.lua'))(V)
  local cfg={fronts={enabled=true,drift=.5}}
  local Config={get=function() return cfg end,weatherEnabled=function() return true end}
  function V.require(n) if n=='Types' then return Types elseif n=='Config' then return Config end error(n) end
  local F=assert(loadfile('lib/Fronts.lua'))(V)
  local expect={
    ROUTE_10='LAVENDER',ROUTE_11='SAFFRON',ROUTE_12='LAVENDER',
    ROUTE_13='FUCHSIA',ROUTE_14='FUCHSIA',ROUTE_15='FUCHSIA',
    ROUTE_16='CELADON',ROUTE_17='CELADON',ROUTE_18='CELADON',ROUTE_19='FUCHSIA',
    ROUTE_20='CINNABAR',ROUTE_23='INDIGO',ROUTE_24='CERULEAN',
    ROUTE_25='CERULEAN',ROUTE_26='INDIGO',
  }
  for map,rid in pairs(expect) do
    local r=F.regionFor(map)
    check(r and r.id==rid,map..' maps to '..rid..' rather than a numeric-prefix collision')
  end
  -- A daytime SUNNY front is not allowed to stay sunny once night begins.
  F.fresh=false
  F.pick=function() return 'RAIN_LIGHT' end
  F.sunForbidden=function() return true end
  local r=F.regionFor('ROUTE_10'); F.state[r.id]={id='SUNNY',left=120}
  F.update(.1,1)
  check(F.state[r.id].id=='RAIN_LIGHT','regional SUNNY front breaks naturally at night')
end

-- Pokegear town-map lookup must use the same boundary-safe route family rule.
do
  package.loaded['src.core.Game']=nil
  package.preload['src.core.Game']=function()
    return {data={field={townMap={locations={ROUTE_10_NORTH={x=99,y=99}}}}}}
  end
  local stubTypes={get=function(id) return {id=id} end,channel=function() return 0 end,DEFAULT='CLEAR'}
  local V={mod={find=function() return nil end}}
  function V.require(n)
    local t={Types=stubTypes,Fronts={},WeatherState={},Config={},Scene={}}
    if t[n] then return t[n] end error(n)
  end
  local G=assert(loadfile('lib/Pokegear.lua'))(V)
  local x,y,real=G.tileFor({maps={'ROUTE_1'},at={4,12}})
  check(x==4 and y==12 and real==false,'Pokegear ROUTE_1 marker does not steal ROUTE_10 town-map coordinate')
  package.loaded['src.core.Game']=nil; package.preload['src.core.Game']=nil
end

-- Player-position fallback used by advanced climate when no voxel host export exists.
do
  local Scene={now={playerPosKnown=true,playerWorldX=640,playerWorldY=960}}
  local Interop={}
  local V={require=function(_,n) end}
  function V.require(n) if n=='Interop' then return Interop elseif n=='Scene' then return Scene end error(n) end
  love={graphics={}}
  local H=assert(loadfile('lib/HostAdapter.lua'))(V); H.refresh()
  local x,z=H.worldPosition()
  check(x==640 and z==960,'advanced environment samples actual player world position')
end

-- Weather-state continuity: save/load, OFF->AUTO, night sunny, fronts, battle carry.
do
  local save={_d={}}
  function save:set(k,v) self._d[k]=v end
  function save:get(k,d) local v=self._d[k]; if v==nil then return d end; return v end
  local mod={save=save,log={warn=function() end}}
  local V={mod=mod}
  local Types=assert(loadfile('lib/Types.lua'))(V)
  local cfg={force=nil,bias={},transitionSeconds=3.2,maxParticles=10000,fronts={enabled=true,drift=.5}}
  local Config={get=function() return cfg end,weatherEnabled=function() return true end,
    tuningFor=function() return {weight=1,intensity=1,speed=1,duration=1} end,
    locationFor=function() return nil end}
  local always=nil; local speed='normal'
  local Settings={syncWeatherFromLadder=function() end,debugRain=function() return false end,
    speedScale=function() return ({normal=1,["2x"]=0.5,["4x"]=0.25,["10x"]=0.1,["20x"]=0.05})[speed] or 1 end,alwaysWeather=function() return always end,exoticScale=function() return 1 end,
    is=function() return true end,intensity=function() return 1 end,
    get=function(k) if k=='speed' then return speed elseif k=='intensity' then return '100' elseif k=='quality' then return 'auto' end end,
    fogIntensity=function() return 1 end,fogOff=function() return false end,sandIntensity=function() return 1 end,
    dustIntensity=function() return 1 end,sandHaze=function() return 1 end,dustHaze=function() return 1 end,
    CHANNEL_FAMILY={},AUTO_FAMILIES={},autoScale=function() return 1 end}
  local TOD={night=false,day=.8}; TOD.isNight=function() return TOD.night end; TOD.daylight=function() return TOD.day end
  local Seasons={multiplier=function() return 1 end}
  local frontWeather=nil
  local Fronts={update=function() end,weatherFor=function() return frontWeather end,persist=function() end,restore=function() end,snapshot=function() return {} end}
  local Psystorm={weatherFor=function() return nil end}
  local Legendary={update=function() return nil end,tick=function() end}
  -- Deterministic finite-cell seam for WeatherState integration. STORM exists
  -- only inside |worldX|<300; its fringe is weaker while rain kinematics stay
  -- authored. Non-spatial regional weather retains ordinary whole-area state.
  local StormCells={}
  function StormCells.update(_,_,ambient,x,z)
    if ambient=='STORM' then
      local ax=math.abs(tonumber(x) or 0)
      local strength=ax<120 and 1 or (ax<300 and .25 or 0)
      return {weather=strength>0 and 'STORM' or nil,strength=strength,cloud=ax<520 and .6 or 0}
    end
    return {weather=nil,strength=1,cloud=1}
  end
  function StormCells.isSpatialWeather(id) return id=='STORM' end
  function StormCells.rescaleRemaining() end
  function StormCells.persist() end
  function StormCells.restore() end
  local Synoptic={_a=false}
  function Synoptic.reset() Synoptic._a=false end
  function Synoptic.active() return Synoptic._a end
  function Synoptic.begin(a,b,base) Synoptic._a=true; return math.max(32,(base or 3.2)*10) end
  function Synoptic.update() end
  function Synoptic.peek() return nil end
  function Synoptic.channelTarget(_,_,v) return v end
  function V.require(n)
    local t={Types=Types,Settings=Settings,Config=Config,TimeOfDay=TOD,Seasons=Seasons,Fronts=Fronts,
      Psystorm=Psystorm,Legendary=Legendary,Harden={},SynopticTransition=Synoptic,StormCells=StormCells}
    if t[n] then return t[n] end error('unexpected '..tostring(n))
  end
  local S=assert(loadfile('lib/WeatherState.lua'))(V)

  -- Mid-transition save must resume exactly instead of disappearing or inheriting stale process state.
  S.id='CLEAR'; S.left=240; S.softFrom='CLEAR'; S.softTo='STORM'; S.softT=20; S.softDur=40; S.cycleIndex=3
  S.persist(); S.id='SNOW_LIGHT'; S.softFrom='SNOW_LIGHT'; S.softTo='FOG'; S.softT=2; S.softDur=55
  S.restore()
  check(S.id=='CLEAR' and S.softFrom=='CLEAR' and S.softTo=='STORM' and approx(S.softT,20) and approx(S.softDur,40),
    'mid-transition weather survives save/load')
  check(S.cycleIndex==3 and S._sessionStart==false,'saved automatic state resumes without first-frame reroll')

  -- OFF -> AUTO starts a fresh non-clear handoff immediately, not a stale CLEAR dwell.
  S._needOutdoorStart=false; S._sessionStart=false; S.level=0; S.id='CLEAR'; S.left=120; S.softTo=nil
  love={math={random=function() return .2 end}}
  S.update(.1,1,'NO_FRONT_MAP',false)
  check(S.softTo~=nil and S.softTo~='CLEAR','OFF -> AUTO immediately starts a fresh visible weather spell')

  -- An old daytime SUNNY spell must start leaving after nightfall.
  TOD.night=true; TOD.day=.05; S.level=1; S.mode='AUTO'; S.id='SUNNY'; S.left=300; S.softTo=nil; S._battleCarry=false
  S._needOutdoorStart=false; S._sessionStart=false; frontWeather=nil
  S.update(.1,1,'NO_FRONT_MAP',false)
  check(S.softTo~=nil and not Types.get(S.softTo).sunny,'AUTO SUNNY cannot remain active deep into night')
  TOD.night=false; TOD.day=.8

  -- Battle-created weather has a fresh dwell and outranks an ordinary regional front for that dwell.
  frontWeather='FOG'; S.level=1; S.mode='AUTO'; S._needOutdoorStart=false; S._sessionStart=false
  S.adoptWeather('STORM','battle-end'); local before=S.left
  S.update(.1,1,'ROUTE_10',false)
  check(S.id=='STORM' and S.softTo==nil and S._battleCarry and S.left<before,
    'battle-created overworld weather is not immediately erased by regional front')
  -- Carry survives save/load.
  S.persist(); S._battleCarry=false; S.restore()
  check(S._battleCarry==true,'battle-weather carry authority survives save/load')
  -- Once its dwell expires, regional authority resumes rather than a random global roll.
  S.left=.05; S.update(.1,1,'ROUTE_10',false)
  check(S._battleCarry==false and S.softTo==nil,'battle carry releases cleanly at dwell end')
  S.update(.1,1,'ROUTE_10',false)
  check(S.softTo=='FOG','regional front resumes immediately after battle carry expires')

  -- Battle in a building replaces the pre-battle paused weather and starts the five-minute window anew.
  S._wasIndoors=true; S._pausedWeatherId='RAIN_LIGHT'; S._indoorAccum=299
  S.adoptWeather('STORM','battle-end')
  check(S._pausedWeatherId=='STORM' and S._indoorAccum==0,'indoor battle carry replaces paused pre-battle sky')

  -- WEATHER DURATION accelerates only the dwell clock. At 20X the next
  -- weather receives a much shorter lifetime, while the authored synoptic
  -- transition duration remains untouched.
  speed='20x'; frontWeather=nil; S._wasIndoors=false; S.level=1; S.mode='AUTO'; S.id='CLEAR'; S.left=0; S.softTo=nil; S._battleCarry=false
  S.update(.1,1,'NO_FRONT_MAP',false)
  check(S.softTo~=nil and (S.left or 99)<30,'20X weather duration shortens the next weather dwell')
  check((S.softDur or 0)>=32.0,'20X weather duration does not accelerate the visible synoptic transition')

  -- Finite storm footprint is resolved at the player's continuous world
  -- position rather than as whole-map weather. Walking outside the same STORM
  -- front makes effective weather CLEAR; walking back into the core restores
  -- it. Only rain amount is edge-scaled -- rainSpeed remains authored.
  frontWeather='STORM'; speed='normal'; S._battleCarry=false; S.level=1; S.mode='AUTO';
  S._needOutdoorStart=false; S._sessionStart=false; S.softTo=nil; S.id='STORM'; S.pinnedBy='front'
  S.ch.rain=0; S.ch.rainSpeed=0
  for _=1,30 do S.update(.1,1,'ROUTE_10',false,0,0) end
  local coreRain,coreSpeed=S.channel('rain'),S.channel('rainSpeed')
  check(S.current().id=='STORM' and coreRain>.5,'storm cell core owns effective local weather')
  for _=1,35 do S.update(.1,1,'ROUTE_10',false,1000,0) end
  local dryRain,drySpeed=S.channel('rain'),S.channel('rainSpeed')
  check(S.current().id=='CLEAR' and dryRain<coreRain*.5,'walking outside finite storm footprint becomes locally dry')
  for _=1,30 do S.update(.1,1,'ROUTE_10',false,0,0) end
  check(S.current().id=='STORM' and S.channel('rain')>dryRain,'walking back into same storm restores local precipitation')
  check(coreSpeed>0 and drySpeed>0,'localized edge does not zero or accelerate rain kinematics')
  frontWeather=nil
end

-- Clock: fresh boot, source/day-length continuity, persistence, host season authority.
do
  local cfg={time={source='cycle',cycleMinutes=24,fixedPhase='DAY',grade=true,gradeStrength=1,indoors=.55,publishTod=true},
             seasons={enabled=true,daysPerSeason=15,hemisphere='northern'}}
  local hostHour=15; local hostOn=false
  local DN={time=function() return hostHour end,hours=function() return hostHour end,mode=function() return 'cycle' end}
  local Interop={dayNight=function() if hostOn then return DN,'DRAMALESS_SHAPE' end return nil end}
  local Settings={get=function(k) if k=='daytime' or k=='seasons' then return 'on' elseif k=='hemisphere' then return 'northern' elseif k=='seasonNotify' then return 'off' end end}
  function Settings.is(k,v) return Settings.get(k)==v end
  local Config={get=function() return cfg end}
  local save={_d={}}; function save:set(k,v) self._d[k]=v end; function save:get(k,d) local v=self._d[k]; if v==nil then return d end; return v end
  local mod={save=save,log={warn=function() end,info=function() end}}
  local V={mod=mod}; local TOD,Seasons
  local Types=assert(loadfile('lib/Types.lua'))(V)
  function V.require(n)
    if n=='Config' then return Config elseif n=='Interop' then return Interop elseif n=='Settings' then return Settings
    elseif n=='Types' then return Types elseif n=='TimeOfDay' and TOD then return TOD elseif n=='Seasons' and Seasons then return Seasons
    elseif n=='CelestialSim' then error('omit sim') end
    error('unexpected '..tostring(n))
  end
  TOD=assert(loadfile('lib/TimeOfDay.lua'))(V)
  TOD.update(1/60)
  check(approx(TOD.hour,13,.01),'fresh internal cycle starts continuously at daytime instead of midnight')
  -- Move visible hour, save, and load into a fresh module instance.
  for _=1,1200 do TOD.update(.1) end
  local savedHour=TOD.hour; TOD.persist()
  TOD.hour=2; TOD.elapsed=0; TOD.restore(); TOD.update(.01)
  check(approx(TOD.hour,savedHour,.02),'internal clock resumes saved visible hour')
  -- Loading an older/different save with no TOD keys must reset instead of
  -- inheriting the previous save's live clock/day state from this process.
  save._d={}; TOD.elapsed=999; TOD.hour=22; TOD.tod='NITE'; TOD.gameDays=7.9
  TOD._trackedDayCount=7; TOD._trackedDayHour=22; TOD._trackedDaySource='cycle'
  TOD.restore()
  check(approx(TOD.elapsed,0) and approx(TOD.hour,13) and TOD._trackedDayCount==0 and TOD.gameDays<1,
    'save without TOD keys resets clock/day state instead of leaking previous save')
  -- Host -> cycle and day-length edit keep the same sky position.
  hostOn=true; cfg.time.source='auto'; TOD.setHostOwnsClock(false); TOD.update(.01); local h1=TOD.hour
  cfg.time.source='cycle'; TOD.update(.01); local h2=TOD.hour
  cfg.time.cycleMinutes=12; TOD.update(.01); local h3=TOD.hour
  check(approx(h1,h2,.02) and approx(h2,h3,.02),'clock source/day-length edits are phase-continuous')
  -- Season no longer derives from unrelated elapsed time while host owns the clock.
  cfg.time.source='auto'; cfg.time.cycleMinutes=24; hostOn=true; TOD.setHostOwnsClock(false); TOD.update(.01)
  Seasons=assert(loadfile('lib/Seasons.lua'))(V); Seasons.update(.1,'ROUTE_1'); local first=Seasons.current()
  TOD.elapsed=60*24*60; Seasons.update(.1,'ROUTE_1')
  check(Seasons.current()==first and Seasons.source=='host','host clock prevents Weather FX elapsed timer from cycling seasons independently')
end

print(('player runtime regressions: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
