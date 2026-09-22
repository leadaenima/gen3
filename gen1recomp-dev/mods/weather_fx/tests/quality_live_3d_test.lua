-- QUALITY must change the live WorldPrecip allocator, not merely the menu/2D path.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local packCap,footCap=nil,nil
local SnowPack={ACCUMULATION_ENABLED=true}
function SnowPack.beginFrame() return {collisionEnabled=true} end
function SnowPack.resolveFlake() return nil end
function SnowPack.update() end
function SnowPack.fillGroundPool(pool,maxCount) packCap=maxCount; pool.active=0 end
function SnowPack.fillFootPool(pool,maxCount) footCap=maxCount; pool.active=0 end

local budget={
  worldPrecip=1.0, worldRadiusCap=123,
  worldRainCap=7, worldSnowCap=11, worldBlizzardCap=12,
  worldHailCap=13, worldSandCap=17, worldDebrisCap=19, worldAshCap=23,
  snowPackDrawCap=29, footDrawCap=31, splash=0,
}
local V={weatherFxId='CUSTOM'}
function V.require(name)
  if name=='Quality' then return {budget=function() return budget end} end
  if name=='Settings' then return {isFirstPerson=function() return false end,is=function() return false end} end
  if name=='Scene' then return {now={visible='world'}} end
  if name=='WindEngine' then return {vector=function() return 1,0 end} end
  if name=='SnowPack' then return SnowPack end
  error('no module '..tostring(name),0)
end

local WP=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
local weather={wxId='CUSTOM',rainIntensity=1.5,snowIntensity=1.9,hailIntensity=1.5,
  sandIntensity=2.0,debrisIntensity=1.5,ashIntensity=1.5,rainWind=1,snowWind=1}
WP.update(1/60,{0,24,0},weather,{})
local c=WP.liveCounts({})
check(c.rain==7,'live rain allocator obeys quality hard cap')
check(c.snow==11,'live snow allocator obeys quality hard cap')
check(c.hail==13,'live hail allocator obeys quality hard cap')
check(c.sand==17,'live sand allocator obeys quality hard cap')
check(c.debris==19,'live leaf/debris allocator obeys quality hard cap')
check(c.ash==23,'live ash allocator obeys quality hard cap')
check((WP.snowTunables().radius or 0)>=599,'snow coverage reaches the full rendered-world field instead of quality cap')
if WP.snowGroundCollisionEnabled and not WP.snowGroundCollisionEnabled() then
  check(packCap==nil,'disabled snow ground collision performs no SnowPack staging')
  check(footCap==nil,'disabled snow ground collision performs no footprint staging')
else
  check(packCap==29,'live SnowPack staging obeys quality pack cap')
  check(footCap==31,'live footprint staging obeys quality footprint cap')
end

-- Dropping quality while weather stays live may shrink density/work, but must
-- not collapse the snow storm into a player-following disk. Coverage remains
-- the rendered-world field on every tier.
budget={worldPrecip=.2,worldRadiusCap=96,worldRainCap=3,worldSnowCap=4,worldBlizzardCap=5,
  worldHailCap=2,worldSandCap=3,worldDebrisCap=2,worldAshCap=2,snowPackDrawCap=5,footDrawCap=6,splash=0}
for _=1,20 do WP.update(1/60,{0,24,0},weather,{}) end
c=WP.liveCounts(c)
check(c.rain<=3 and c.snow<=4,'changing to a lower tier shrinks live precip without restart')
check(c.hail<=2 and c.sand<=3 and c.debris<=2 and c.ash<=2,'changing to lower tier shrinks live grain families')
check((WP.snowTunables().radius or 0)>=599,'lower tier preserves full snow world coverage radius')
if WP.snowGroundCollisionEnabled and not WP.snowGroundCollisionEnabled() then
  check(packCap==nil and footCap==nil,'lower tier keeps disabled snow ground staging inactive')
else
  check(packCap==5 and footCap==6,'lower tier updates live SnowPack/footprint draw caps without restart')
end

print(('quality live 3D: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
