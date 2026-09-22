-- Weather FX 8.1.89: duplicate WEATHER events must never restart active 2D weather.
local ROOT=os.getenv('WX_ROOT') or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end
if ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local values={always='RAIN_LIGHT',fronts='off',present='2d'}
local liveLevel=4
local setCalls=0
local P={}
function P.setLevel(_,v) setCalls=setCalls+1;liveLevel=tonumber(v) or 0 end
function P.level() return liveLevel end
function P.syncOptions(opts) if opts then opts.pipelines=opts.pipelines or {};opts.pipelines.weather=liveLevel end end
package.loaded['src.render.Pipelines']=P

local game={save={options={pipelines={weather=4},modOptions={weather_fx={always='RAIN_LIGHT',fronts='off',present='2d'}}}},mods={modOptions={weather_fx={always='RAIN_LIGHT'}},loader={modOptions={weather_fx={always='RAIN_LIGHT'}}}}}
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
    function t.get(id) if t.byId[id] then return{id=id,label=id} end return{id=id,label=tostring(id)} end
    cache[n]=t;return t
  end
  if n=='WeatherState' then local w={LEVEL_IDS={false,'AUTO','CYCLE','CLEAR','RAIN_LIGHT','SNOWY'}};cache[n]=w;return w end
  if n=='Config' then local c={get=function()return{fronts={enabled=false}}end};cache[n]=c;return c end
  if n=='Quality' then local q={};cache[n]=q;return q end
  if n=='DramalessAtmos' then local a={};cache[n]=a;return a end
  local f=assert(loadfile(ROOT..'lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m
end

local S=V.require('Settings')
S.define()
S._runtimeAlways='RAIN_LIGHT';S._runtimeValues.always='RAIN_LIGHT';S._lastLadderLevel=4
setCalls=0

local changed=S.handleOptionChanged({mod='weather_fx',key='always',value='RAIN_LIGHT'})
ck(changed==false,'duplicate WEATHER event is explicitly ignored')
ck(setCalls==0,'duplicate WEATHER event does not call pipeline setLevel')
ck(S.alwaysWeather()=='RAIN_LIGHT' and liveLevel==4,'duplicate WEATHER event preserves live weather authority')

for i=1,20 do
  S.handleOptionChanged({mod='weather_fx',key='always',value='RAIN_LIGHT'})
  S.pollWeatherLadder(game)
end
ck(setCalls==0,'repeated same-value broadcasts and polls never reapply the weather rung')

values.always='SNOWY'
local real=S.handleOptionChanged({mod='weather_fx',key='always',value='SNOWY'})
ck(real==true and setCalls==1 and liveLevel==5,'real WEATHER change still applies immediately once')

print(('8.1.89 2D restart guard: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
