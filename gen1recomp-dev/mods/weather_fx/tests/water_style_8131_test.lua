-- Weather FX 8.1.31 WATER STYLE ownership/persistence contract.
local passed,failed=0,0
local function check(v,msg) if v then passed=passed+1;print('PASS '..msg) else failed=failed+1;print('FAIL '..msg) end end

local values={waterStyle='weatherfx'}
local defined={}
local optionCallbacks={}
local fakeMod={id='weather_fx'}
fakeMod.options={
  define=function(_,row) defined[#defined+1]=row end,
  get=function(_,key) return values[key] end,
}
fakeMod.events={on=function(_,name,cb) optionCallbacks[name]=cb end,once=function() end}
fakeMod.hooks={wrap=function() end}
fakeMod.content={screens={register=function() end}}
local V={mod=fakeMod}
local cache={}
function V.require(name)
  if cache[name] then return cache[name] end
  if name=='Types' then
    local T={PINNED={}}
    function T.get() return nil end
    cache[name]=T;return T
  end
  if name=='DramalessAtmos' then return cache.DramalessAtmos end
  error('missing '..tostring(name))
end

local S=assert(loadfile('lib/Settings.lua'))(V);cache.Settings=S
if S.define then pcall(S.define) end
local row=S.row('waterStyle')
check(row~=nil,'WATER STYLE is present in the player settings schema')
check(row and row.default=='weatherfx','WATER STYLE defaults to WEATHER FX')
check(row and row.choices and #row.choices==2 and row.choices[1][2]=='weatherfx' and row.choices[2][2]=='original','WATER STYLE exposes WEATHER FX and ORIGINAL only')
local atmosphere=S.group('world');local inGroup=false
for _,k in ipairs(atmosphere and atmosphere.keys or {}) do if k=='waterStyle' then inGroup=true end end
check(inGroup,'WATER STYLE is reachable from the in-game WORLD & CLOUDS submenu')

values.waterStyle='original';S.handleOptionChanged({mod='weather_fx',key='waterStyle',value='original'})
check(S.waterStyle()=='original' and not S.weatherFxWaterEnabled(),'ORIGINAL disables Weather FX hydrosphere ownership immediately')
values.waterStyle='weatherfx';S.handleOptionChanged({mod='weather_fx',key='waterStyle',value='weatherfx'})
check(S.waterStyle()=='weatherfx' and S.weatherFxWaterEnabled(),'WEATHER FX re-enables connected hydrosphere ownership immediately')

-- ConnectedWater must mask hidden ice gameplay while ORIGINAL is selected.
local mode='weatherfx'
cache.Settings={weatherFxWaterEnabled=function() return mode~='original' end}
local CWV={mod={hooks={wrap=function() end}}}
function CWV.require(name)
  if name=='Settings' then return cache.Settings end
  if name=='WindEngine' then return {peek=function() return {x=0,z=0,strength=0} end} end
  if name=='CelestialSim' then return {moonPhase=function() return 0 end} end
  if name=='TimeOfDay' then return {hour=12} end
  if name=='Microclimate' then return {peek=function() return {temperature=-10} end} end
  error(name)
end
local CW=assert(loadfile('lib/ConnectedWater.lua'))(CWV)
CW.observed=true;CW.observationAge=0
local b={loadBearing=true,ice=1,tide=0}
CW.bodyByCell['0:0']=b
check(CW.isLoadBearingAt(8,8)==true,'WEATHER FX mode exposes load-bearing ice')
mode='original'
check(CW.isLoadBearingAt(8,8)==false,'ORIGINAL mode masks Weather FX ice walking')
check(CW.liquidFractionNear(8,8,0)==1,'ORIGINAL mode reports ordinary liquid water to local climate consumers')

-- 3D renderer handoff restores host water tuning and becomes fail-open.
local invalidates=0
local Water={
  WAVE_TRAINS={{1,2,3,4},{5,6,7,8},{9,10,11,12}},WAVE_HEIGHT=3,
  WAVE_SWELL={1,1,1,1},WAVE_BEND={2,2,2,2},WAVE_FPS=7,WAVE_PIXELS_PER_STEP=2,
  WAVE_SLOPE=4,WAVE_SLOPE_LEAN=1.1,invalidate=function() invalidates=invalidates+1 end,
}
local Renv={}
function Renv.require(name)
  if name=='Water' then return Water end
  if name=='ConnectedWater' then return {observed=false,bodies={}} end
  return nil
end
local R=assert(loadfile('lib/voxel_atmos/ConnectedWater3D.lua'))(Renv)
-- Seed an original snapshot exactly as a prior Weather FX prepare would have.
R._origDynamics={trains={{1,2,3,4},{5,6,7,8},{9,10,11,12}},height=3,swell={1,1,1,1},bend={2,2,2,2},fps=7,pixels=2,slope=4,slopeLean=1.1}
Water.WAVE_HEIGHT=8;Water.WAVE_FPS=10;Water.WAVE_SLOPE=5.2
R.setEnabled(false)
check(not R.enabled(),'renderer ownership is released in ORIGINAL mode')
check(Water.WAVE_HEIGHT==3 and Water.WAVE_FPS==7 and Water.WAVE_SLOPE==4,'ORIGINAL restores host water height/timing/slope immediately')
local repl,owned=R.prepare({{'native'}})
check(repl==nil and owned==false,'ORIGINAL renderer fails open to untouched native water draws')
R.setEnabled(true)
check(R.enabled(),'switching back to WEATHER FX re-arms connected water renderer')

print(string.format('water style 8.1.31: %d passed, %d failed',passed,failed));if failed>0 then os.exit(1) end
