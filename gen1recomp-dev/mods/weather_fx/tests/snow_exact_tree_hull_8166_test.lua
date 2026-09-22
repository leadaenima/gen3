local pass,fail=0,0
local function ok(v,msg) if v then pass=pass+1;print('PASS '..msg) else fail=fail+1;print('FAIL '..msg) end end
local V={require=function(name) error('optional '..tostring(name)) end}
local SP=assert(loadfile('lib/SnowPack.lua'))(V)
local map={id='TREE_MAP',def={width=1,height=1},widthCells=2,heightCells=2}
function map:tileAt(tx,tz) return 1 end
function map:cellTile(cx,cz) return 1 end
function map:isWaterCell(cx,cz) return false end
local shape={class='tree',art='canopy',h=36}
local TS={forMap=function(m) return {[1]=shape} end,at=function(m,sh,tile,tx,tz) return shape end}
local VS={groundAt=function(m,cx,cz) return 36 end}
-- The visible host hull has a real 8x8 top face at y=20 and vertical sides.
-- Outside that face, despite the cell-wide groundAt=36 and shape.h=36, the
-- exact Structures authority says there is a gap and SnowPack must fall to ground.
local top={{-4,20,-4},{4,20,-4},{4,20,4},{-4,20,4}}
local side={{4,0,-4},{4,0,4},{4,20,4},{4,20,-4}}
local S={roundStamps={{mx=8,mz=8,r=8,quads={top,side}}}}
local Structures={forMap=function(m) return S end}
local ctx=SP.beginFrame({map=map},0,VS,TS,Structures)
local y,k,c,a,p=SP.surfaceAt(ctx,8,8)
ok(y==20 and k=='tree' and p=='round','tree flake lands on exact visible horizontal hull face')
local gy,gk=SP.surfaceAt(ctx,2,8)
ok(gy==0 and gk=='ground','gap beside visible tree face falls to real ground instead of invisible crown')
local c1,p1=SP.deposit(ctx,8,8,nil,0.8)
ok(p1 and p1.baseY==20 and p1.kind=='tree' and p1.profile=='round','tree deposit stores exact support and patch-local profile')
SP.deposit(ctx,8,8,nil,0.8) -- reach visible repaint threshold
local c2,p2=SP.deposit(ctx,2,8,nil,0.8)
ok(p2 and p2.baseY==0 and p2.kind=='ground' and p2.profile=='full','same cell can retain independent ground patch metadata below tree gap')
local pool={x={},z={},y={},amount={},kind={},size={}}
SP.fillGroundPool(pool,32,ctx,8,8,64)
local sawTree,sawGround=false,false
for i=1,pool.active or 0 do
  if pool.kind[i]=='tree' and pool.profile[i]=='round' and pool.baseY[i]==20 then sawTree=true end
  if pool.kind[i]=='ground' and pool.profile[i]=='full' and pool.baseY[i]==0 then sawGround=true end
end
ok(sawTree and sawGround,'draw/repaint pool preserves per-patch tree and ground surface identities')
print(string.format('snow exact tree hull 8.1.66: %d passed, %d failed',pass,fail))
os.exit(fail==0 and 0 or 1)
