local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local map={id='FLAT',def={width=8,height=8},cellTile=function() return 1 end,isWaterCell=function() return false end,tileAt=function() return 1 end}
local TS={forMap=function() return {[1]={class='ground',art='flat',h=0}} end,at=function(_,sh,t) return sh[t] end}
local VS={groundAt=function() return 0 end}
local V={require=function() return nil end}
local SP=assert(loadfile(ROOT..'lib/SnowPack.lua'))(V);SP._reset()
local player={px=64,py=64};local ctx=SP.beginFrame({map=map,state={map=map,player=player},player=player},0,VS,TS)
ck(ctx.collisionEnabled==true,'exact flat support enables bounded SnowPack collision')
for i=1,12 do SP.depositAggregate(ctx,72+((i%3)-1)*2,72+((math.floor(i/3)%3)-1)*2,1.0) end
local d=SP.depthAtPoint(ctx,72,72);ck(d>=SP.MIN_TRACK_DEPTH,'aggregate procedural snowfall reaches physical footprint depth')
SP.update(.1,ctx,true,'BLIZZARD');player.px=72;SP.update(.1,ctx,true,'BLIZZARD')
local fp={x={},y={},z={},angle={},size={},a={},side={},depression={}}
ck(SP.fillFootPool(fp,32,ctx)>0,'real player displacement through aggregate snow creates drawable footprints')
local gp={x={},y={},z={},amount={},size={},kind={}}
ck(SP.fillGroundPool(gp,32,ctx,72,72,100)>0,'aggregate banks stage visible ground geometry')
local wp=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
ck(wp:find('wantSnowSim=min(wantSnow,96)',1,true)~=nil,'GPU snow retains <=96 CPU interaction probes')
ck(wp:find('at most 24 exact-support samples/second',1,true)~=nil,'aggregate support sampling remains capped at 24 per second')
ck(wp:find('if snowCtx and snowCtx.collisionEnabled and SP and SP.fillGroundPool and SP.fillFootPool then',1,true)~=nil,'bank/foot staging requires proven exact collision support')
print(('SnowPack live restore 8.1.64: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
