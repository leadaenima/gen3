local pass,fail=0,0
local function ok(v,msg) if v then pass=pass+1;print('PASS '..msg) else fail=fail+1;print('FAIL '..msg) end end
local events={}
local wind={x=.82,z=.24,strength=.92,envelope=1.04,phase=1.2,phase2=2.4,angle=.28}
local rainbow={wetMemory=.82,recentRain=5}
local modules={
  WindEngine={peek=function() return wind end},
  Rainbow={peek=function() return rainbow end},
  CelestialEngine={state=function() return {sun={altitudeDeg=24,discTransmission=.76,alpha=1}} end},
  EnvironmentalEvents={publish=function(kind,data) events[#events+1]={kind=kind,data=data};return #events end},
}
local V={require=function(n) if modules[n] then return modules[n] end error('unexpected require '..tostring(n),0) end}
local W=assert(loadfile('lib/WeatherWorldInteraction.lua'))(V)
local State={id='HEAVY_RAIN',ch={rain=1.0,snow=0,gust=1}}
function State.channel(k) return State.ch[k] or 0 end
local scene={visible='world',outdoor=true,indoors=false,mapId='route'}
local surface={wet=.62,snow=0}
W._reset(8188)
for i=1,60 do W.update(.1,State,surface,scene,100,200) end
local s=W.peek()
ok(s.roofLoad>.1 and s.canopyLoad>.1,'rain charges retained roof and canopy water')
ok(s.vegetation.wetLoad>.1 and s.vegetation.sag>0,'wet weather publishes vegetation load/sag')
State.id='CLEAR';State.ch.rain=0;rainbow.recentRain=6
for i=1,20 do W.update(.1,State,surface,scene,100,200) end
s=W.peek()
ok(s.roofDrip>0 and s.canopyDrip>0,'roof/canopy dripping persists after rainfall ends')
ok(s.postRainShaft>0,'recent rain plus clearing sunlight publishes post-rain shaft gain')
local roofBefore=s.roofLoad;for i=1,120 do W.update(.1,State,surface,scene,100,200) end
ok(W.peek().roofLoad<roofBefore,'retained roof water drains over time')
State.id='BLIZZARD';State.ch.snow=1;surface.snow=.9
for i=1,30 do W.update(.1,State,surface,scene,100,200) end
s=W.peek()
ok(s.vegetation.snowLoad>.4 and s.vegetation.sag>.2,'snow load increases vegetation sag')
ok(s.vegetation.windBend>0 and s.vegetation.gustStrength>0,'vegetation interop exposes wind bend and gust strength')
-- Deterministic bounded gust-front watch. It is intentionally intermittent.
local seen=false;local x0,z0
for i=1,1800 do
  W.update(.1,State,surface,scene,100,200);local g=W.peek().gustFront
  if g.active then seen=true;x0,z0=g.x,g.z;W.update(.2,State,surface,scene,100,200);local g2=W.peek().gustFront;ok((g2.x-x0)*g2.dirX+(g2.z-z0)*g2.dirZ>0,'active gust front advances through world space');break end
end
ok(seen,'strong wind eventually creates a bounded travelling gust front')
local hasBegin=false
for i=1,#events do if events[i].kind=='gust_front_begin' then hasBegin=true end end
ok(hasBegin,'gust-front start is published for optional companion reactions')
local snap=W.sample()
ok(snap.version==1 and type(snap.vegetation)=='table' and type(snap.gustFront)=='table','public interaction snapshot includes vegetation and gust descriptors')
scene.indoors=true;for i=1,20 do W.update(.1,State,surface,scene,100,200) end
ok(W.peek().roofDrip==0 and W.peek().canopyDrip==0,'indoor scenes suppress secondary outdoor dripping')
print(string.format('weather world interaction 8.1.88: %d passed, %d failed',pass,fail))
os.exit(fail==0 and 0 or 1)
