-- Weather FX 8.1.36 liquid-water / OOB player safety contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print('PASS '..m) else failed=failed+1;print('FAIL '..m) end end
local modules={WindEngine={peek=function() return {x=1,z=0,strength=.4} end},CelestialSim={sample=function() return {moon={phase=.25}} end},TimeOfDay={hour=12},Microclimate={peek=function() return {temperature=-12} end},Settings={weatherFxWaterEnabled=function() return true end}}
local wrapped
local V={mod={hooks={wrap=function(self,n,fn) if n=='movement.collision' then wrapped=fn end end}},require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local CW=assert(loadfile(ROOT..'lib/ConnectedWater.lua'))(V);modules.ConnectedWater=CW
local function map(id,water)
  return {id=id,widthCells=3,heightCells=3,
    inBounds=function(self,x,z) return x>=0 and z>=0 and x<3 and z<3 end,
    isWaterCell=function(self,x,z) return water[x..':'..z] or false end,
    isWalkableCell=function() return false end}
end
local A=map('A',{['1:1']=true});local B=map('B',{['1:1']=true})
local p={px=0,py=0,cellX=0,cellY=0,surfing=false}
CW.observeVoxel({map=A,neighbors={},player=p});CW.installHooks()
check(type(wrapped)=='function','water safety collision hook is installed')
local function call(ctx) return wrapped(function(v) return v end,false,ctx) end
check(call({map=A,mover=p,toX=3,toY=1,reason='bounds'})==false,'true out-of-bounds refusal can never be widened')
check(call({map=A,mover=p,toX=3,toY=1,reason='tile'})==false,'even a corrupted tile reason cannot widen an out-of-bounds destination')
check(call({map=A,mover=p,toX=1,toY=1,reason='tile'})==false,'ordinary liquid water remains non-walkable')
check(call({map=A,mover=p,toX=1,toY=1,reason='entity'})==false,'entity collision is never rewritten by water/ice hook')
-- Freeze exact authored A:1,1.
local state={channel=function(k) return k=='snow' and 1 or 0 end}
for i=1,320 do CW.observeVoxel({map=A,neighbors={},player=p});CW.update(.25,state,{id='WINTER'}) end
check(CW.isLoadBearingMapCell(A,1,1),'exact authored frozen cell becomes load-bearing')
local iceCtx={map=A,mover=p,toX=1,toY=1,reason='tile'}
check(call(iceCtx)==true and iceCtx.reason=='weather_fx_ice','only exact in-bounds frozen authored water widens tile collision')
-- Same local coordinate on a different map must not alias A's ice.
CW.observeVoxel({map=A,neighbors={},player=p})
local fakeB={id='B',widthCells=3,heightCells=3,inBounds=B.inBounds,isWaterCell=B.isWaterCell,isWalkableCell=B.isWalkableCell}
check(call({map=fakeB,mover=p,toX=1,toY=1,reason='tile'})==false,'same-coordinate water on another map cannot inherit frozen support')
-- Visual-only host water must never become movement support.
local host={id='HOST',widthCells=1,heightCells=1,inBounds=function() return true end,isWaterCell=function() return false end,isWalkableCell=function() return true end}
CW.observeVoxel({map=host,neighbors={},player=p,hostWaterCells={{map=host,cx=0,cz=0,gx=0,gz=0,size=8}}})
check(not CW.isLoadBearingMapCell(host,0,0),'presentation-only host water can never authorize walking')
-- Stale observation must fail closed.
CW.observationAge=CW.OBSERVATION_TTL+1
check(call({map=A,mover=p,toX=1,toY=1,reason='tile'})==false,'stale water observation cannot change collision')
-- Surf presentation bob must be read-only with respect to gameplay coordinates.
local C=assert(loadfile(ROOT..'lib/voxel_atmos/ConnectedWater3D.lua'))({require=function(n) if n=='ConnectedWater' then return {windX=1,windZ=0,windStrength=.6,rain=0,renderBodies={}} end error(n,0) end})
local p2={px=123,py=456,cellX=7,cellY=8,surfing=true};local before={p2.px,p2.py,p2.cellX,p2.cellY}
pcall(function() C.playerBob({player=p2}) end)
check(p2.px==before[1] and p2.py==before[2] and p2.cellX==before[3] and p2.cellY==before[4],'Surf wave bob cannot mutate gameplay position/cell coordinates')
local dr=assert(io.open(ROOT..'lib/DramalessAtmos.lua','rb')):read('*a')
check(dr:find('player.pose,player.py=originalPose,oldPy',1,true)~=nil,'temporary Surf presentation pose is restored after draw')
print(string.format('water player safety 8.1.36: %d passed, %d failed',passed,failed));if failed>0 then os.exit(1) end
