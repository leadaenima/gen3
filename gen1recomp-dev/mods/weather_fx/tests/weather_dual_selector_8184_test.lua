-- Weather FX 8.1.84: both player weather selectors are one live authority.
local ROOT=((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end
if ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(rel)local f=assert(io.open(ROOT..rel,'rb'));local s=f:read('*a');f:close();return s end

local values={always='off',fronts='off'}
local liveLevel=0
local P={}
function P.setLevel(_,v) liveLevel=tonumber(v) or 0 end
function P.level() return liveLevel end
function P.syncOptions(opts) if opts then opts.pipelines=opts.pipelines or {};opts.pipelines.weather=liveLevel end end
package.loaded['src.render.Pipelines']=P

local game={save={options={pipelines={weather=0},modOptions={weather_fx={always='off'}}}},mods={modOptions={weather_fx={always='off'}},loader={modOptions={weather_fx={always='off'}}}}}
package.loaded['src.core.Game']=game
local mod={id='weather_fx',options={}}
function mod.options:get(k)return values[k]end
function mod.options:set(k,v)values[k]=v;return true end
mod.events={on=function()end};mod.log={warn=function()end,info=function()end}
local cache={}
local V={mod=mod,safeCall=pcall}
function V.require(n)
  if cache[n] then return cache[n] end
  if n=='Types' then
    local t={PINNED={'CLEAR','RAIN_LIGHT','SNOWY'},byId={CLEAR=true,RAIN_LIGHT=true,SNOWY=true}}
    function t.get(id) if id=='CLEAR' or id=='RAIN_LIGHT' or id=='SNOWY' then return{id=id,label=id} end return{id=id,label=tostring(id)} end
    cache[n]=t;return t
  end
  if n=='WeatherState' then local w={LEVEL_IDS={false,'AUTO','CYCLE','CLEAR','RAIN_LIGHT','SNOWY'}};cache[n]=w;return w end
  if n=='Config' then local c={get=function()return{fronts={enabled=false}}end};cache[n]=c;return c end
  if n=='Quality' then local q={};cache[n]=q;return q end
  if n=='DramalessAtmos' then local a={};cache[n]=a;return a end
  local f=assert(loadfile(ROOT..'lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m
end
local S=V.require('Settings')
local M=V.require('SettingsMenu')

-- Mod Manager -> engine OPTIONS + every persisted/live mirror.
ck(M.applyOption(game,'always','RAIN_LIGHT')==true,'Mod Manager WEATHER accepts named weather')
ck(liveLevel==4,'Mod Manager WEATHER immediately moves engine OPTIONS rung')
ck(S.alwaysWeather()=='RAIN_LIGHT' and S.get('always')=='RAIN_LIGHT','Mod Manager WEATHER immediately owns runtime weather')
ck(game.save.options.pipelines.weather==4,'Mod Manager WEATHER persists engine pipeline rung')

-- Engine OPTIONS -> Mod Manager + every persisted/live mirror.
liveLevel=5; game.save.options.pipelines.weather=5
local optionChangedOk=type(S.handleWeatherLadderChanged)=='function' and S.handleWeatherLadderChanged(5,game)==true
ck(optionChangedOk,'OPTIONS WEATHER change is accepted immediately')
ck(S.get('always')=='SNOWY' and S.alwaysWeather()=='SNOWY','OPTIONS WEATHER immediately changes Weather FX runtime weather')
ck(values.always=='SNOWY','OPTIONS WEATHER mirrors Mod Manager option backing value')
ck(game.save.options.modOptions.weather_fx.always=='SNOWY','OPTIONS WEATHER persists Mod Manager save mirror')
ck(game.mods.modOptions.weather_fx.always=='SNOWY' and game.mods.loader.modOptions.weather_fx.always=='SNOWY','OPTIONS WEATHER updates loader caches used by Mod Manager')

-- The reported trap: Options must escape a stale OFF selected by the other menu.
values.always='off';S._runtimeValues.always='off';S._runtimeAlways='off';liveLevel=1;game.save.options.pipelines.weather=1
local offAutoOk=type(S.handleWeatherLadderChanged)=='function' and S.handleWeatherLadderChanged(1,game)==true
ck(offAutoOk,'OPTIONS OFF -> AUTO supersedes stale Mod Manager OFF')
ck(not S.weatherDisabled() and S.get('always')=='auto','OPTIONS AUTO clears hard-disable authority in same frame')

-- And the reverse: Mod Manager OFF/named remains immediate and authoritative.
ck(M.applyOption(game,'always','off')==true and liveLevel==0 and S.weatherDisabled(),'Mod Manager OFF immediately disables engine and runtime')
ck(M.applyOption(game,'always','CLEAR')==true and liveLevel==3 and S.alwaysWeather()=='CLEAR','Mod Manager OFF -> named weather immediately re-enables and changes weather')

-- Static integration guards: WeatherState reconciles the newest ladder before OFF,
-- and the real OPTIONS row is decorated with the same live mirror callback.
local ws=read('lib/WeatherState.lua'); local main=read('main.lua')
local syncPos=ws:find('Settings.syncWeatherFromLadder(level)',1,true)
local offPos=ws:find('Settings.weatherDisabled and Settings.weatherDisabled()',1,true)
ck(syncPos~=nil and offPos~=nil and syncPos<offPos,'WeatherState accepts OPTIONS rung before evaluating hard OFF')
ck(main:find('local function unifiedWeatherRow(row)',1,true)~=nil and main:find('Settings.handleWeatherLadderChanged(level, game)',1,true)~=nil,'OPTIONS menu row publishes changes through unified Weather FX authority')

print(('8.1.84 dual weather selector: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
