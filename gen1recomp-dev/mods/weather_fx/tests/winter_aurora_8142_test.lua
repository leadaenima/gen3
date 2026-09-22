-- Weather FX 8.1.42 season-weighted aurora physics / geometry regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local season='WINTER';local hour=23.5;local day=0;local events='on';local cloud=1;local moon=.15;local building=1
local modules={}
modules.Settings={get=function(k) if k=='celestialEvents' then return events end return nil end}
modules.Config={get=function() return {celestial={events=true}} end}
modules.Seasons={current=function() return season end}
modules.TimeOfDay={hour=hour,gameDaySerial=function() return day end}
modules.CelestialEngine={state=function() return {optics={skyTransmission=cloud},moonLight=moon} end}
modules.BuildingLight={factor=building}
local V={require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local A=assert(loadfile(ROOT..'lib/Aurora.lua'))(V)

-- Find a deterministic strong event so morphology tests exercise the overhead
-- corona branch rather than depending on platform RNG.
local strongKey,strongPlan
for k=0,400 do local p=A._planForTest(k);if p.eligible and p.intensity>.86 then strongKey,strongPlan=k,p;break end end
ck(strongKey~=nil,'deterministic winter schedule contains naturally strong aurora nights')
day=strongKey;hour=strongPlan.center;A.reset();local p=A._planForTest(strongKey)
local st=A._sampleForTest(1)
local state=A.state()
ck(state.active and state.season=='WINTER' and state.visibility>.30,'clear dark winter night activates visible aurora')
ck(state.class=='storm' and state.intensity>.86,'strong scheduled night resolves storm-class auroral activity')

-- Outside winter, every night receives an independent deterministic 5%
-- eligibility roll. Find one eligible and one ineligible night, then prove the
-- rule applies equally to spring/summer/autumn and survives reset/reload.
local offKey,offPlan,missKey=nil,nil,nil
local offCount,total=0,20000
for k=0,total-1 do
  local op=A._planForTest(k)
  if op.offSeasonEligible then offCount=offCount+1;if not offKey then offKey,offPlan=k,op end
  elseif not missKey then missKey=k end
end
local offRate=offCount/total
ck(offRate>.047 and offRate<.053,'non-winter schedule is statistically 5% per night over deterministic sample')
ck(offKey~=nil and missKey~=nil,'off-season schedule contains both aurora and ordinary nights')
for _,ss in ipairs({'SPRING','SUMMER','AUTUMN'}) do
  season=ss;day=offKey;hour=offPlan.center;A.reset();A._sampleForTest(1)
  ck(A.state().active and A.state().season==ss and A.state().seasonalEligible,'5% off-season aurora can activate in '..ss)
end
season='SUMMER';day=missKey;local miss=A._planForTest(missKey);hour=miss.center;A.reset();A._sampleForTest(1)
ck(not A.state().active and not A.state().seasonalEligible,'non-selected off-season night stays aurora-free')
season='SUMMER';day=offKey;hour=offPlan.center;A.reset();local first=A._sampleForTest(1);local firstState=A.state().active
A.reset();A._sampleForTest(1);ck(firstState and A.state().active,'off-season nightly roll is deterministic across reset/reload')

season='WINTER';day=strongKey;hour=strongPlan.center;A.reset();events='off';A._sampleForTest(1);ck(not A.state().active,'CELESTIAL EVENTS OFF suppresses aurora')
events='on';season='WINTER';day=strongKey;hour=strongPlan.center;A.reset();cloud=1;A._sampleForTest(1);local clearVis=A.state().visibility
cloud=.04;A._sampleForTest(1);local cloudVis=A.state().visibility
ck(cloudVis<clearVis*.18,'opaque cloud field strongly hides aurora instead of glowing through weather')
cloud=1;moon=0;building=1;A._sampleForTest(1);local darkVis=A.state().visibility
moon=1;building=.15;A._sampleForTest(1);local litVis=A.state().visibility
ck(litVis<darkVis and litVis>darkVis*.45,'moon/city light reduce apparent contrast without deleting a strong aurora')
moon=.15;building=1

-- The actual world renderer must be a dense continuous curtain mesh, not a
-- handful of rectangles/cards. Capture the emitted triangles directly.
local verts={}
local function pushTri(out,n,...)
  local a={...}
  for i=1,3 do local o=(i-1)*7;n=n+1;out[n]={a[o+1],a[o+2],a[o+3],a[o+4],a[o+5],a[o+6],a[o+7]} end
  return n
end
local n=A.appendWorld(verts,0,pushTri,{0,0,0},420,10,1)
ck(n>=12000,'storm-class aurora builds multi-sheet high-density curtain geometry')
local minY,maxY=1e9,-1e9;local redCap,purpleEdge=false,false;local alphaMax=0
for i=1,n do local v=verts[i];minY=math.min(minY,v[2]);maxY=math.max(maxY,v[2]);alphaMax=math.max(alphaMax,v[7] or 0)
  if (v[4] or 0)>(v[5] or 0)*1.18 and (v[4] or 0)>.45 then redCap=true end
  if (v[6] or 0)>(v[5] or 0)*1.08 and (v[6] or 0)>.48 then purpleEdge=true end
end
ck(maxY>405 and minY>35,'strong curtain climbs from northern horizon to near-zenith corona geometry')
ck(redCap,'high-altitude oxygen-red cap is present on active displays')
ck(purpleEdge,'low-altitude nitrogen purple/blue edge is present on active displays')
ck(alphaMax<.22,'aurora layers stay translucent and additive rather than becoming opaque neon sheets')

-- Projection fallback consumes identical spherical curtain topology.
local projected={}
local function pushScreenTri(out,n,...)
  local a={...}
  for i=1,3 do local o=(i-1)*6;n=n+1;out[n]={a[o+1],a[o+2],a[o+3],a[o+4],a[o+5],a[o+6]} end
  return n
end
local function project(x,y,z)
  -- Simple forward-facing north camera projection for topology proof.
  local f=-z;if f<=.02 then return nil end
  return 160+x/f*120,120-y/f*120
end
local pn=A.appendProjected(projected,0,pushScreenTri,project,10,1)
ck(pn>1000,'projected voxel fallback uses the same structured aurora curtain, not a flat overlay sprite')

print(string.format('season-weighted aurora 8.1.42: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
