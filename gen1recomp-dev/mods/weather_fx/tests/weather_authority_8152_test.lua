-- Weather FX 8.1.52: explicit weather-authority contract.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function near(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end

-- SETTINGS: choosing a named weather must turn WEATHER FRONTS off, including
-- the persisted backing option where the current host exposes it.
do
  local optionValues={always='cycle',fronts='on'}
  local saveOptions={modOptions={weather_fx={always='cycle',fronts='on'}}}
  package.loaded['src.core.Game']={save={options=saveOptions},mods={modOptions={weather_fx={always='cycle',fronts='on'}}}}
  local mod={id='weather_fx',options={get=function(_,k) return optionValues[k] end},save={}}
  local V={mod=mod}
  local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
  function V.require(n) if n=='Types' then return Types end error(n,0) end
  local S=assert(loadfile(ROOT..'lib/Settings.lua'))(V)
  S.handleOptionChanged({mod='weather_fx',key='always',value='RAIN_LIGHT'})
  ck(S.manualWeatherSelected()=='RAIN_LIGHT','named WEATHER selection is recognized as direct player authority')
  ck(S.get('fronts')=='off','named WEATHER selection immediately turns effective fronts OFF')
  ck(saveOptions.modOptions.weather_fx.fronts=='off','named WEATHER selection persists dependent WEATHER FRONTS=OFF')
  S.handleOptionChanged({mod='weather_fx',key='fronts',value='on'})
  ck(S.get('fronts')=='off','fronts cannot steal authority while a named WEATHER remains selected')
  S.handleOptionChanged({mod='weather_fx',key='always',value='cycle'})
  ck(S.manualWeatherSelected()==nil and S.get('fronts')=='off','leaving named weather keeps fronts OFF until player explicitly re-enables them')
  S.handleOptionChanged({mod='weather_fx',key='fronts',value='on'})
  ck(S.get('fronts')=='on','fronts can be explicitly re-enabled after returning WEATHER to CYCLE/AUTO')
end

-- WEATHER STATE: with CYCLE selected and fronts ON, physical fronts own weather
-- and the cycle dwell clock is frozen. Turning fronts OFF resumes that same clock.
do
  local mod={save={d={}}}
  function mod.save:set(k,v) self.d[k]=v end
  function mod.save:get(k,d) local v=self.d[k];if v==nil then return d end;return v end
  local V={mod=mod}
  local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V)
  local frontsEnabled=true
  local Settings={
    debugRain=function() return false end, alwaysWeather=function() return nil end,
    weatherDisabled=function() return false end, syncWeatherFromLadder=function() end,
    speedScale=function() return 1 end, intensity=function() return 1 end,
    get=function(k) if k=='intensity' then return 'normal' elseif k=='daytime' then return 'off' end return nil end,
    is=function() return false end, keyRevision=function() return 0 end,
    sandIntensity=function() return 1 end,dustIntensity=function() return 1 end,fogIntensity=function() return 1 end,
    rainIntensity=function() return 1 end,snowIntensity=function() return 1 end,windIntensity=function() return 1 end,
    stormDarknessScale=function() return 1 end,fogOff=function() return false end,rainOff=function() return false end,snowOff=function() return false end,
    AUTO_FAMILIES={},CHANNEL_FAMILY={}
  }
  local cfg={fronts={enabled=true},force=nil,transitionSeconds=3.2,tuning={duration=1}}
  local Config={
    get=function() cfg.fronts.enabled=frontsEnabled;return cfg end,
    locationFor=function() return nil end,
    tuningFor=function() return {duration=1,intensity=1,speed=1} end,
    weatherFor=function() return {} end
  }
  local Fronts={
    update=function() end,rescaleRemaining=function() end,
    weatherFor=function(mapId) if frontsEnabled and not tostring(mapId):match('INDOOR') then return 'RAIN_LIGHT' end return nil end,
    restore=function() end
  }
  local StormCells={setEnabled=function() end,update=function() return nil end,isSpatialWeather=function() return false end,rescaleRemaining=function() end,restore=function() end}
  local Legendary={update=function() return nil end,tick=function() end,restore=function() end}
  local Psystorm={weatherFor=function() return nil end}
  local TOD={hour=function() return 12 end,isNight=function() return false end}
  local Seasons={multiplier=function() return 1 end}
  function V.require(n)
    local t={Types=Types,Settings=Settings,Config=Config,TimeOfDay=TOD,Seasons=Seasons,Fronts=Fronts,StormCells=StormCells,Psystorm=Psystorm,Legendary=Legendary}
    if t[n] then return t[n] end
    if n=='SynopticTransition' or n=='Harden' then error('optional',0) end
    error('unexpected require '..tostring(n),0)
  end
  local State=assert(loadfile(ROOT..'lib/WeatherState.lua'))(V)
  State.level=2;State.id='CLEAR';State.left=42;State.fresh=false;State._sessionStart=false;State._needOutdoorStart=false;State.dirty=true
  State.update(.25,2,'ROUTE_1',false,0,0)
  ck(State.mode=='FRONT' and near(State.left,42,1e-9),'WEATHER FRONTS ON suspends CYCLE timer and owns outdoor automatic weather')
  local held=State.left
  State.update(.25,2,'ROUTE_2',false,50,0)
  ck(near(State.left,held,1e-9),'map changes cannot consume hidden CYCLE time while fronts are enabled')
  State.softFrom,State.softTo=nil,nil;State.softT,State.softDur=0,0
  State.left=17
  State.update(.25,2,'INDOOR_HOUSE',true,50,0)
  ck(near(State.left,17,1e-9),'CYCLE remains frozen inside buildings while fronts own the world')
  frontsEnabled=false
  State._wasIndoors=false;State.softFrom,State.softTo=nil,nil;State.softT,State.softDur=0,0
  local before=State.left
  State.update(.25,2,'ROUTE_2',false,50,0)
  ck(State.mode=='CYCLE' and State.left<before,'turning WEATHER FRONTS OFF resumes CYCLE from its preserved timer')
end

print(string.format('weather authority 8.1.52: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
