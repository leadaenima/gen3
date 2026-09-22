-- Weather FX 8.1.28 flat-world SnowPack regression.
-- Accumulation is live again through the dedicated radial-bank path; water is
-- always non-accumulating and footprints only stamp walkable ground/grass.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end

local map={id='SNOW_FLAT',def={width=5,height=3}}
function map:cellTile(cx,cz) if cx==1 then return 2 elseif cx==2 then return 3 elseif cx==3 then return 4 end return 1 end
function map:isWaterCell(cx,cz) return cx==3 end
function map:tileAt(tx,tz) return self:cellTile(math.floor(tx/2),math.floor(tz/2)) end
local shapes={
  [1]={class='ground',art='flat',h=0},
  [2]={class='tree',art='canopy',h=24},
  [3]={class='sign',art='billboard',h=12},
  [4]={class='water',art='flat',h=-2},
}
local TS={forMap=function() return shapes end}
function TS.at(_,sh,tile) return sh[tile] end
local VS={}
function VS.groundAt(_,cx,cz) if cx==1 then return 24 elseif cx==2 then return 12 end return 0 end
local V={require=function() return nil end}
local SP=assert(loadfile(ROOT..'lib/SnowPack.lua'))(V);SP._reset()
local player={px=0,py=0,cellX=0,cellY=0}
local ctx=SP.beginFrame({map=map,neighbors={},state={map=map,player=player},player=player},0,VS,TS)

check(SP.ACCUMULATION_ENABLED==true,'8.1.28 accumulation is enabled')
check(ctx.collisionEnabled==true,'falling snow keeps real voxel/model collision')
check(SP.SWEEP_STEP<=1.0,'flake-to-surface sweep remains fine-grained')

for _=1,80 do SP.resolveFlake(ctx,8,18,8,8,-2,8,1.0) end
for _=1,80 do SP.resolveFlake(ctx,24,40,8,24,18,8,1.0) end
for _=1,80 do SP.resolveFlake(ctx,40,28,8,40,6,8,1.0) end
local ground=SP.depthAtMapCell(map,0,0)
local canopy=SP.depthAtMapCell(map,1,0)
local prop=SP.depthAtMapCell(map,2,0)
check(ground>0.20,'sustained snow builds persistent ground depth')
check(canopy>0 and canopy<ground,'tree/canopy retention is shallower than open ground')
check(prop>0 and prop<canopy,'thin props retain less snow than canopy')

for _=1,120 do SP.resolveFlake(ctx,56,18,8,56,-4,8,1.0) end
check(SP.depthAtMapCell(map,3,0)==0,'water never accumulates SnowPack state')

-- Seed a short walkable strip and move across it to prove physical tracks.
for _,x in ipairs({8,10,12,14}) do for _=1,20 do SP.deposit(ctx,x,8,0,1.0) end end
SP.update(0.1,ctx,true,'BLIZZARD')
player.px=0;SP.update(0.1,ctx,true,'BLIZZARD')
player.px=7;SP.update(0.1,ctx,true,'BLIZZARD')
local footPool={x={},y={},z={},angle={},size={},a={},side={},depression={}}
check(SP.fillFootPool(footPool,128,ctx)>0,'walking through deep ground snow creates footprints')

local groundPool={x={},y={},z={},amount={},size={},kind={}}
check(SP.fillGroundPool(groundPool,128,ctx,8,8,200)>0,'radial snow bank geometry is staged for drawing')

-- Rain after the storm is a fast but gradual cleanup, not an instant pop.
local before=SP.depthAtMapCell(map,0,0)
SP.update(0.25,ctx,false,'RAIN')
local justAfter=SP.depthAtMapCell(map,0,0)
check(justAfter>0 and justAfter<=before,'snow begins rain-driven melt without disappearing instantly')
for _=1,210 do SP.update(0.25,ctx,false,'RAIN') end
check(SP.depthAtMapCell(map,0,0)==0,'rain cleanup removes the bank within its finite cleanup window')

local c,f,ct,ft,pn=SP.stats()
check(c>=0 and f>=0 and ct>=0 and ft>=0 and pn>=0,'SnowPack telemetry remains bounded/numeric')
local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'));local wp=src:read('*a');src:close()
check(wp:find('SP and SP.ACCUMULATION_ENABLED and SP.beginFrame',1,true)~=nil and wp:find('snowCtx and snowCtx.collisionEnabled and SP and SP.resolveFlake',1,true)~=nil,'WorldPrecip stages SnowPack only through restored bounded exact-support authority')
check(wp:find('drawGroundSnow(Voxel3D)',1,true)~=nil,'dedicated ground-snow renderer remains the live draw path')

print(('snow accumulation/footprints 8.1.28: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
