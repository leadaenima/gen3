local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;io.write('FAIL: ',n,'\n') end end
local cfg={tornado={enabled=true,everySeconds=75,maxActive=3,formationSeconds=8,roamSeconds=180,ropeSeconds=12,carryChance=0,waterTwister=true}}
local weather={id='GALE'}
local scene={now={visible='world',indoors=false,outdoor=true,mapId='MAP_A'}}
local settings={is=function(k,v) return k=='tornado' and v=='on' end,isFirstPerson=function() return true end,force2dPresent=function() return false end,allow3dPresent=function() return true end}
local bridge={presentation3d=function() return true end,active=function() return true end}
local flat={ready=function() return true end,sampleAt=function(x,z,out) out=out or {};out.water=false;out.solid=false;out.canopy=false;out.roof=false;out.shelter=0;out.drag=1;out.groundY=0;return out end}
local wind={direction=function() return 1,0 end}
local mapA={id='MAP_A',widthCells=32,heightCells=32}
local mapB={id='MAP_B',widthCells=32,heightCells=32}
local stateA={map=mapA,player={px=480,py=200,cellX=30,cellY=12,facing='right'},neighbors={{map=mapB,ox=512,oy=0}}}
local stateB={map=mapB,player={px=4,py=200,cellX=0,cellY=12,facing='right'},neighbors={{map=mapA,ox=-512,oy=0}}}
local modules={Config={get=function() return cfg end},Settings=settings,WeatherState={current=function() return weather end},Scene=scene,VoxelAtmosBridge=bridge,FlatWorldInteraction=flat,WindEngine=wind}
local mod={save={set=function() end,get=function(_,_,d)return d end},hooks={wrap=function() end}}
local V={mod=mod,require=function(n) if modules[n] then return modules[n] end error('unexpected require '..tostring(n),0) end}
local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V)
T._setRandom(function() return .5 end)
T.observeVoxelState(stateA)
local list=T.renderState()
list[1]={id=1,x=509,z=200,mapId='MAP_A',age=30,formation=8,roamFor=180,ropeFor=12,stage='roam',roamAge=40,ropeAge=0,seeker=false,heading=0,speed=20,spin=4.5,waterBlend=0,groundY=0,wander=0}
list[2]={id=2,x=470,z=300,mapId='MAP_A',age=20,formation=8,roamFor=180,ropeFor=12,stage='roam',roamAge=20,ropeAge=0,seeker=false,heading=0,speed=1,spin=4.1,waterBlend=0,groundY=0,wander=0}
T._gale=true
local rCross,rStay=list[1],list[2]
T.update(.25)
check(rCross.mapId=='MAP_B','tornado crossing connected east boundary changes host map instead of despawning')
check(rCross.stage=='roam' and rCross.roamAge>40,'map crossing preserves tornado lifecycle/timer')
check((rCross.mapCrossings or 0)==1,'map crossing is recorded exactly once')
local preCrossX,preStayX=rCross.x,rStay.x
local preAge,preRoam=rStay.age,rStay.roamAge
-- Player crosses into MAP_B; weather entities must be re-based into the new
-- local world coordinate frame, not recreated.
scene.now.mapId='MAP_B'
T.observeVoxelState(stateB)
check(math.abs(rCross.x-(preCrossX-512))<1e-6 and rCross.mapId=='MAP_B','tornado already in destination map stays continuous through player root-map change')
check(math.abs(rStay.x-(preStayX-512))<1e-6 and rStay.mapId=='MAP_A','tornado left behind remains in old map as a connected neighbor')
check(rStay.age==preAge and rStay.roamAge==preRoam and rStay.stage=='roam','player map change does not restart tornado lifecycle')
local ps=T.worldPersistenceStatus()
check(ps.rootRebases==1,'connected player map transition performs one field rebase')
-- Indoors hides the outdoor weather but does not rope out or age away funnels.
scene.now.indoors=true;scene.now.outdoor=false
local a0,ra0,s0=rStay.age,rStay.roamAge,rStay.stage
T.update(.25)
check(rStay.stage==s0 and rStay.age==a0 and rStay.roamAge==ra0,'indoor/cave transition suspends tornado field without reloading it')
scene.now.indoors=false;scene.now.outdoor=true
T.update(.25)
check(rStay.stage=='roam' and rStay.age>a0,'same tornado resumes after returning outdoors')
-- Actual weather change, unlike a map transition, still ropes funnels out.
weather.id='CLEAR';T.update(.25)
check(rStay.stage=='rope' and rCross.stage=='rope','leaving GALE still retracts active tornadoes normally')

io.write(string.format('tornado map persistence: %d passed, %d failed\n',pass,fail))
os.exit(fail==0 and 0 or 1)
