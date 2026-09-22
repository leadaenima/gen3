-- Weather FX 8.1.28: radial deposition follows exact voxel support boundaries.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end
local map={id='SURFACE_RADIAL',def={width=5,height=2}}
function map:isWaterCell(cx,cz) return cx==2 end
function map:cellTile(cx,cz) if cx==2 then return 2 elseif cx==3 then return 3 elseif cx==4 then return 4 end return 1 end
function map:tileAt(tx,tz) return self:cellTile(math.floor(tx/2),math.floor(tz/2)) end
local shapes={
 [1]={class='ground',art='flat',h=0}, [2]={class='water',art='flat',h=-2},
 [3]={class='sign',art='billboard',h=12}, [4]={class='tree',art='canopy',h=18},
}
local TS={forMap=function() return shapes end};function TS.at(_,sh,tile) return sh[tile] end
local VS={};function VS.groundAt(_,cx,cz) if cx==3 then return 12 elseif cx==4 then return 18 end return 0 end
local SP=assert(loadfile(ROOT..'lib/SnowPack.lua'))({require=function() return nil end});SP._reset()
local ctx=SP.beginFrame({map=map,neighbors={}},0,VS,TS)
check(SP.ACCUMULATION_ENABLED==true,'radial accumulation is live')
local sy,sk=SP.surfaceAt(ctx,56,8); local gy,gk=SP.surfaceAt(ctx,49,2)
check(sk~='ground' and sy>=11.9,'sign top remains point-accurate collision support')
check(gk=='ground' and gy<1,'outside sign footprint falls to ground instead of invisible cell box')
local ty,tk=SP.surfaceAt(ctx,72,8); local ey,ek=SP.surfaceAt(ctx,65,1)
check(tk=='tree' and ty>16,'tree center retains raised canopy collision')
check(ek=='ground' and ey<1,'outside tree crown falls to real ground')
local wy,wk=SP.surfaceAt(ctx,40,8)
check(wk=='water','water surface remains classified as water')
for _=1,80 do SP.resolveFlake(ctx,56,30,8,56,-4,8,1.0) end
for _=1,80 do SP.resolveFlake(ctx,72,34,8,72,-4,8,1.0) end
for _=1,80 do SP.resolveFlake(ctx,40,20,8,40,-4,8,1.0) end
check(SP.depthAtMapCell(map,3,0)>0,'thin raised support can retain a bounded radial patch')
check(SP.depthAtMapCell(map,4,0)>0,'tree crown can retain a bounded radial patch')
check(SP.depthAtMapCell(map,2,0)==0,'shore/water cell remains non-accumulating')
local pool={x={},y={},z={},amount={},size={},kind={}}
check(SP.fillGroundPool(pool,128,ctx,56,8,200)>0,'radial mound geometry reaches dedicated draw staging')
print(('snow radial surfaces 8.1.28: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
