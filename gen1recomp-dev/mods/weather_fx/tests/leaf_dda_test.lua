-- Weather FX 4.35.22 exact voxel-grid leaf traversal regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local map={def={width=16,height=16}}
local solids={}
local VS={}
function VS.groundAt(_,cx,cz)
  return solids[tostring(cx)..':'..tostring(cz)] or 0
end
local V={require=function() error('root loader has no host module',0) end}
local LP=assert(loadfile(ROOT..'lib/LeafPhysics.lua'))(V)
local ctx=LP.beginFrame({map=map,neighbors={}},0,VS)
check(ctx.collisionEnabled==true,'explicit host VoxelScene enables DDA collision')
check(LP.SWEEP_STEP<=0.5,'secondary fallback sweep remains <=0.5 world units')
check(type(LP.ddaCells)=='function' and type(LP.ddaWall)=='function','exact DDA traversal is exported for regression proof')

-- Every crossed 16-unit cell is visited in order.
local seen={}
LP.ddaCells(1,8,79,8,function(cx,cz,t)
  local k=cx..':'..cz
  if seen[#seen]~=k then seen[#seen+1]=k end
end)
local expected={'0:0','1:0','2:0','3:0','4:0'}
local same=#seen==#expected
for i=1,#expected do same=same and seen[i]==expected[i] end
check(same,'DDA visits every crossed voxel cell boundary exactly along long sweep')

-- Helper pool for resolve tests.
local function poolAt(x,y,z,vx,vz)
  return {x={[1]=x},y={[1]=y},z={[1]=z},vx={[1]=vx or 0},vy={[1]=0},vz={[1]=vz or 0},seed={[1]=0.5},
    leafSettled={[1]=false},leafSettleT={[1]=0},leafSettleLife={[1]=0},leafNpcT={[1]=0},leafWallT={[1]=0}}
end

-- 1. Slow wall hit.
solids['1:0']=20
local p=poolAt(17,5,8,4,0)
local r=LP.resolve(p,1,0.1,15,5,8,ctx,1,0,true)
check(r=='wall' and p.x[1]<16,'slow leaf is blocked at first solid voxel boundary')

-- 2. Fast entire-cell tunnelling attempt.
solids={['2:0']=20}
VS.groundAt=function(_,cx,cz) return solids[tostring(cx)..':'..tostring(cz)] or 0 end
ctx=LP.beginFrame({map=map,neighbors={}},0,VS)
p=poolAt(60,5,8,48,0)
r=LP.resolve(p,1,0.1,4,5,8,ctx,1,0,true)
check(r=='wall' and p.x[1]<32,'fast leaf crossing an entire voxel cell is blocked by DDA')

-- 3. Diagonal corner. The path crosses exactly through (16,16); supercover
-- must test side-adjacent cell 1:0 instead of only diagonal 1:1.
solids={['1:0']=20}
VS.groundAt=function(_,cx,cz) return solids[tostring(cx)..':'..tostring(cz)] or 0 end
ctx=LP.beginFrame({map=map,neighbors={}},0,VS)
p=poolAt(25,5,25,20,20)
r=LP.resolve(p,1,0.1,7,5,7,ctx,1,1,true)
check(r=='wall','supercover DDA blocks diagonal corner crossing against side-adjacent solid cell')

-- 4. Shallow angle across a thin wall.
solids={['2:0']=20}
VS.groundAt=function(_,cx,cz) return solids[tostring(cx)..':'..tostring(cz)] or 0 end
ctx=LP.beginFrame({map=map,neighbors={}},0,VS)
p=poolAt(58,5,11,50,1.2)
r=LP.resolve(p,1,0.1,5,5,9.7,ctx,1,0,true)
check(r=='wall' and p.x[1]<32,'shallow-angle leaf cannot tunnel through one-cell wall')

-- 5. DDA is primary when center path crosses a solid cell.
local hit=LP.ddaWall(ctx,5,5,9.7,58,5,11)
check(hit and hit.dda==true and hit.cellX==2,'primary collision reports exact DDA-hit voxel')

-- Existing swept NPC safeguard remains intact.
local npc={def={sprite='SPRITE_LASS'},px=64,py=64,cellX=4,cellY=4}
local state={map=map,entities={npc},player=nil,ghosts={}}
ctx=LP.beginFrame({map=map,state=state,posed={}},0,VS)
p=poolAt(90,7,72,40,0)
r=LP.resolve(p,1,0.1,50,7,72,ctx,0.7,0.2,true)
check(r=='npc','fast leaf still cannot tunnel through NPC cylinder')
check(p.leafSettled[1]~=true,'NPC collision never creates pile state')
local ejected=false
for _=1,21 do
  p.x[1],p.y[1],p.z[1]=72,7,72
  local rr=LP.resolve(p,1,0.1,71,7,72,ctx,0.7,0.2,true)
  if rr=='npc-eject' then ejected=true; break end
end
check(ejected,'continuous NPC contact forcibly ends within two seconds')

print(('leaf DDA: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
