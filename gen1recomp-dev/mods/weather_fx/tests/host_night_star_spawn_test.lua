-- Regression for real voxel-host DAYTIME pin -> Weather FX deep-sky render.
-- The draw path must recover even if the CelestialEngine cache still contains
-- the previous DAY frame when the host menu has already switched to NIGHT.
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;print('FAIL '..n) end end

local hostMode='day'
local hostDN={CYCLE=1200,DAY_LEN=600,T={dawn=0,day=300,dusk=600,night=900}}
hostDN.setting={get=function() return hostMode end}
-- Deliberately stale numeric dial: explicit pin must outrank this transient
-- value during the same menu-change frame.
function hostDN.time() return 300 end
function hostDN.hours() return 13.5 end
local cfg={
 time={source='auto',cycleMinutes=24,fixedPhase='DAY',grade=true,gradeStrength=1,publishTod=true,indoors=.35},
 celestial={enabled=true,latitude=35,axialTilt=23.43928,motionSmoothing=true},
 seasons={daysPerSeason=15},
}
local Config={get=function() return cfg end}
local Settings={get=function(k) if k=='daytime' then return 'on' elseif k=='indoors' then return 'tint' end end}
local Interop={dayNight=function() return hostDN,'BATTLE_ART_VOXEL_FORK' end}
local Weather={id='CLEAR',ch={}}
function Weather.channel() return 0 end
local BuildingLight={factor=1,starScale=function() return 1 end}
local Quality={}
local modules={Config=Config,Settings=Settings,Interop=Interop,WeatherState=Weather,BuildingLight=BuildingLight,Quality=Quality}
local V={mod={log={warn=function() end}}}
function V.require(n)
  if modules[n] then return modules[n] end
  local f=assert(loadfile('lib/'..n..'.lua'))
  local m=f(V);modules[n]=m;return m
end

-- Minimal LÖVE GPU contract used by the real instanced ordinary-star path and
-- projected constellation mesh. Count submissions rather than faking results.
local instancedCalls,instancedCount,meshDraws=0,0,0
love={graphics={}}
local g=love.graphics
function g.getSupported() return {instancing=true,glsl3=false} end
local function mesh()
  return {attachAttribute=function() end,setVertices=function() return true end,setDrawRange=function() end,release=function() end}
end
function g.newMesh(...) return mesh() end
function g.newShader(...) return {send=function() return true end,release=function() end} end
function g.drawInstanced(_,n) instancedCalls=instancedCalls+1;instancedCount=instancedCount+(tonumber(n) or 0);return true end
function g.draw(...) meshDraws=meshDraws+1;return true end
function g.setBlendMode() end; function g.setDepthMode() end; function g.setShader() end; function g.setColor() end
function g.getBlendMode() return 'alpha','alphamultiply' end
function g.getDepthMode() return 'lequal',true end
function g.getShader() return nil end
function g.getColor() return 1,1,1,1 end

local TOD=V.require('TimeOfDay')
local Sim=V.require('CelestialSim')
local Engine=V.require('CelestialEngine')
local NightSky=V.require('NightSky')
NightSky._TOD=TOD;NightSky._DayNight=hostDN

-- Establish a genuinely cached daytime frame first.
TOD.update(.1)
local day=Engine.update(.1,Weather)
check(TOD.hostMode=='day' and TOD.tod=='DAY','host DAY pin is recognized as explicit mode')
check(day and day.starVisibility==0,'day cache starts with deep sky disabled')

-- Host menu flips to NIGHT. Do not call Engine.update here: the render query
-- itself must detect stale cached time and resync, which is the real failure mode.
hostMode='night'
TOD.update(.1)
check(TOD.hostMode=='night','host NIGHT pin is recognized directly')
check(TOD.tod=='NITE' and math.abs(TOD.hour-0)<.01,'host NIGHT maps to deep-night Weather FX time even with stale numeric dial')
local vis=NightSky.computeNightVisibility()
check(vis>.45,'NightSky resyncs stale DAY celestial state to visible deep night')
check(Engine.state().starVisibility>.45,'CelestialEngine state self-resyncs on host time-mode change')

local voxel={eye={0,3,0},focus={0,3,-1},vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},fovY=math.rad(65),size=function() return 320,288 end}
local drew=NightSky.drawProjectedWorld(voxel,1,320,288)
local proof=NightSky.projectedProof()
check(drew==true,'projected world deep-sky renderer draws immediately after host NIGHT selection')
check(instancedCalls>=1 and instancedCount>=5120,'all ordinary stars reach the real instanced draw path at host NIGHT')
check(proof and proof.visibility>.45 and proof.objects>=5120,'projected proof reports visible night-star population')
check(meshDraws>=1,'constellation/planet projected mesh submits alongside ordinary stars')
local C=V.require('Constellations')
check(C.count()>=3000 and #C.NAMES==25,'retained high-detail constellation catalogue remains loaded during night spawn')

-- Returning to DAY must be equally immediate and must not leave stale night.
hostMode='day';TOD.update(.1)
check(NightSky.computeNightVisibility()==0,'host DAY immediately suppresses deep sky again')

print(('host night star spawn: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
