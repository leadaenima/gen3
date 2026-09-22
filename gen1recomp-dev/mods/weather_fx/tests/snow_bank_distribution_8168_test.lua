-- Weather FX 8.1.68 distributed/coalescing snow-bank regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local map={id='FLAT_8168',def={width=32,height=32},cellTile=function() return 1 end,isWaterCell=function() return false end,tileAt=function() return 1 end}
local TS={forMap=function() return {[1]={class='ground',art='flat',h=0}} end,at=function(_,sh,t) return sh[t] end}
local VS={groundAt=function() return 0 end}
local V={require=function() return nil end}
local SP=assert(loadfile(ROOT..'lib/SnowPack.lua'))(V);SP._reset()
local player={px=64,py=64};local ctx=SP.beginFrame({map=map,state={map=map,player=player},player=player},0,VS,TS)

ck(SP.PATCH_RADIUS_MAX>=9,'mature banks can spread broadly instead of staying small blobs')
ck(math.abs((SP.MAX_GROUND_HEIGHT or 0)-3.60)<1e-9 and math.abs((SP.MAX_GRASS_HEIGHT or 0)-3.20)<1e-9,'8.1.67 ground/grass accumulation height constants are unchanged')
ck(math.abs(SP.heightForDepth('ground','ground',1)-3.60)<1e-9,'full ground drift keeps the exact 8.1.67 maximum height')

-- Seed two distinct nearby patches just outside the direct merge threshold.
for _=1,18 do SP.depositAggregate(ctx,72,72,1.0) end
for _=1,18 do SP.depositAggregate(ctx,78,72,1.0) end
local _,_,_,_,patches=SP.stats()
ck(patches==1,'overlapping same-surface deposits coalesce into one physical bank')
local gp={x={},y={},z={},amount={},size={},kind={},class={},profile={},baseY={},height={},r1={},r2={},r3={},r4={},r5={},r6={},r7={},r8={}}
SP.fillGroundPool(gp,64,ctx,75,72,100)
ck((gp.active or 0)==1,'coalesced bank stages one mound instead of stacked blob geometry')
ck((gp.size[1] or 0)>=5.0,'coalesced bank grows wider as snow merges')

-- Active snow is lifetime authority: no timer or walking should erase bank mass.
SP.update(0.1,ctx,true,'BLIZZARD')
local d0=SP.depthAtPoint(ctx,75,72)
for _=1,500 do SP.update(0.1,ctx,true,'BLIZZARD') end
local d1=SP.depthAtPoint(ctx,75,72)
ck(d1>=d0-1e-9,'accumulated bank does not age or melt while snow weather stays active')
player.px=72;SP.update(0.1,ctx,true,'BLIZZARD')
player.px=78;SP.update(0.1,ctx,true,'BLIZZARD')
local d2=SP.depthAtPoint(ctx,75,72)
ck(d2>=d1-1e-6,'walking during snowfall does not subtract persistent bank mass')

local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'));local wp=src:read('*a');src:close()
ck(wp:find('((qn%9)-4)*4',1,true)==nil and wp:find('9x9 interaction lattice',1,true)==nil,'old straight 4px accumulation lattice is absent')
ck(wp:find('2.399963229728653',1,true)~=nil,'distributed sampler uses golden-angle placement')
ck(wp:find('_snowPackStormAge/45',1,true)~=nil,'snow accumulation ramps in over the opening 45 seconds')
ck(wp:find('min(18,max(2.0,snowI*3.6))',1,true)~=nil,'aggregate support work tops out at 18 samples per second')
ck(wp:find('local i1=r1*0.72',1,true)~=nil,'bank renderer uses a broad flat interior instead of a narrow dome')

print(('snow bank distribution 8.1.68: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
