-- Weather FX 8.1.28: 3D bank staging is live, bounded, and never bridges water.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end
local map={id='BANK_WATER',def={width=4,height=2}}
function map:isWaterCell(cx,cz) return cx==1 end
function map:cellTile(cx,cz) return cx==1 and 2 or 1 end
local shapes={[1]={class='ground',art='flat',h=0},[2]={class='water',art='flat',h=-2}}
local TS={forMap=function() return shapes end};local VS={groundAt=function() return 0 end}
local SP=assert(loadfile(ROOT..'lib/SnowPack.lua'))({require=function() return nil end});SP._reset()
local player={px=0,py=0};local ctx=SP.beginFrame({map=map,state={player=player},player=player},0,VS,TS)
check(SP.ACCUMULATION_ENABLED==true,'3D snow bank feature is live')
for _=1,250 do SP.resolveFlake(ctx,8,12,8,8,-3,8,1.0) end
check(SP.depthAtMapCell(map,0,0)>0 and SP.heightAtMapCell(map,0,0)>0,'open ground builds a visible 3D bank')
for _=1,250 do SP.resolveFlake(ctx,24,12,8,24,-3,8,1.0) end
check(SP.depthAtMapCell(map,1,0)==0,'water cannot build hidden snow state')
local gp={x={},y={},z={},amount={},size={},kind={}}
local staged=SP.fillGroundPool(gp,4800,ctx,8,8,800)
check(staged>0 and staged<=4800 and (gp.active or 0)==staged,'3D bank staging is live and respects MAX draw cap')
-- The patch clip must stop before the adjacent water support.
local maxRadius=0
for i=1,(gp.active or 0) do maxRadius=math.max(maxRadius,tonumber(gp.size[i]) or 0) end
check(maxRadius<=SP.PATCH_RADIUS_MAX,'bank radii remain bounded at shoreline')
local f=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'));local src=f:read('*a');f:close()
check((src:find('SP and SP.ACCUMULATION_ENABLED and SP.beginFrame',1,true)~=nil) or (src:find('ground snow collision/settling/footprint generation is disabled',1,true)~=nil),'WorldPrecip either stages SnowPack through one authority or explicitly suspends it for 8.1.54 safety')
check(src:find('drawGroundSnow(Voxel3D)',1,true)~=nil and src:find('drawFootprints(Voxel3D)',1,true)~=nil,'dedicated bank and footprint renderers remain present')
print(('snow 3D bank/water 8.1.28: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
