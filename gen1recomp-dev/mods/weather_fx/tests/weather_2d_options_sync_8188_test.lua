-- Weather FX 8.1.88: 2D overlay final-frame ownership + menu cache independence.
local ROOT=os.getenv('WX_ROOT') or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end
if ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(rel)local f=assert(io.open(ROOT..rel,'rb'));local s=f:read('*a');f:close();return s end

local values={always='off',present='auto',fronts='off'}
local liveLevel=0
local P={}
function P.setLevel(_,v) liveLevel=tonumber(v) or 0 end
function P.level() return liveLevel end
function P.syncOptions(opts) if opts then opts.pipelines=opts.pipelines or {};opts.pipelines.weather=liveLevel end end
package.loaded['src.render.Pipelines']=P

local coreGame={save={options={pipelines={weather=0},modOptions={weather_fx={always='off',present='auto'}}}},mods={modOptions={weather_fx={always='off',present='auto'}},loader={modOptions={weather_fx={always='off',present='auto'}}}}}
package.loaded['src.core.Game']=coreGame

local mod={id='weather_fx',options={}}
function mod.options:get(k)return values[k]end
function mod.options:define()return true end
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

-- Re-registering settings during save/game boot must not erase a live custom
-- submenu edit just because mod.options:get still reports an older loader cache.
S.handleOptionChanged({mod='weather_fx',key='present',value='2d'})
values.present='auto' -- emulate stale loader-facing mod.options:get
S.define()
ck(S.get('present')=='2d' and S.force2dPresent(),'settings re-define preserves live 2D OVERLAY authority')

-- A base OPTIONS ladder change must be discovered without relying on the row's
-- decorated step callback (UI mods/generation-specific menus can replace it).
S._runtimeAlways='off';S._runtimeValues.always='off';S._lastLadderLevel=0
liveLevel=1;coreGame.save.options.pipelines.weather=1
local polled=type(S.pollWeatherLadder)=='function' and S.pollWeatherLadder(coreGame) or false
ck(polled and S.get('always')=='auto' and not S.weatherDisabled(),'always-running ladder poll applies OPTIONS OFF -> AUTO without Mod Manager')

-- Custom Weather FX submenu may receive a lightweight game facade without a
-- .mods loader. It still has to update the real core Game loader caches that
-- Mod Manager/mod.options:get read.
local M=V.require('SettingsMenu')
local screenGame={save={options={pipelines={weather=liveLevel},modOptions={weather_fx={}}}}}
M.applyOption(screenGame,'present','2d')
ck(coreGame.mods.modOptions.weather_fx.present=='2d' and coreGame.mods.loader.modOptions.weather_fx.present=='2d','OPTIONS submenu mirrors real core loader caches without opening Mod Manager')

-- Forced classic 2D weather must be drawn in final present(), not claimed by
-- an intermediate voxel worldPresent target that a host can later replace.
local main=read('main.lua')
local wp=assert(main:find('worldPresent = function(canvas, ctx)',1,true))
local fp=main:find('Settings.force2dPresent and Settings.force2dPresent()',wp,true)
local defer=fp and main:find('drewThisFrame = false',fp,true) or nil
local draw=main:find('local ok = Draw.frame',wp,true)
ck(fp~=nil and defer~=nil and draw~=nil and fp<draw and defer<draw,'forced 2D worldPresent defers ownership to final-frame present')

print(('8.1.88 2D/options synchronization: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
