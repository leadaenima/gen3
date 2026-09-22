local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;io.write('FAIL: ',n,'\n') end end
love={graphics={getDimensions=function() return 1280,720 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end}
local generic={}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=0,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local V={mod={id='weather_fx',options={get=function() return nil end}},weatherFxId='RAIN_LIGHT',weatherFxChannels={rain=.9}}
function V.require(n)
 if n=='Settings' then return Settings end
 if n=='WeatherSetting' then return WeatherSetting end
 if n=='ForestAtmos' then return ForestAtmos end
 if n=='MesoscaleField' then return {ready=function() return false end} end
 if n=='PerformanceGovernor' then return {scale=function() return 1 end} end
 if n=='Quality' then return {budget=function() return {worldPrecip=1} end} end
 if n=='Scene' then return {now={visible='world',outdoor=true}} end
 return generic
end
V.safeCall=pcall
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)

-- Connected map B is east of A by +512 world units in A's root frame.
C._testCloudOriginStep(480,0,1/60,'MAP_A',{{map={id='MAP_B'},ox=512,oy=0}},true)
local x0,z0,n0=C.cloudOrigin()
C._testCloudOriginStep(4,0,1/60,'MAP_B',{{map={id='MAP_A'},ox=-512,oy=0}},true)
local x1,z1,n1=C.cloudOrigin()
check(x1==x0-512 and z1==z0,'connected east-map change rebases persistent cloud lattice exactly once')
check(n1==n0+1,'connected map change records one cloud-origin rebase')
-- A normal in-map movement must not create a new origin shift.
C._testCloudOriginStep(20,0,1/60,'MAP_B',{{map={id='MAP_A'},ox=-512,oy=0}},true)
local x2,z2,n2=C.cloudOrigin()
check(x2==x1 and z2==z1 and n2==n1,'ordinary walking does not reload/reseed the cloud bank')

-- Closed rain deck: deliberately use a projection where cloud centres have a
-- huge NDC Y and would all fail the historical -2.2..0.55 centre gate. The
-- live builder must retain physically overhead deck cells anyway.
local upVox={
 eye={0,8,0},focus={0,108,0},player={0,0,0},far=800,
 -- x -> small NDC x, y -> deliberately huge NDC y; w=1
 vp={.001,0,0,0, 0,1,0,0, 0,0,.001,0, 0,0,0,1},
 size=function() return 1280,720 end,
}
local closed={coverage=1,gate=-1,softGate=0,closedDeck=true,deckBlend=1,deckWidth=1.82,deckDepth=1.12,deckY0=110,deckYSpan=24,span=1,puffs=1,bank=.72}
local frame={level=1,canopy=false,weather=closed,windState={advectX=0,advectZ=0}}
local countUp=C.cloudDescriptorProbe(upVox,frame)
check(countUp>0,'sealed rain cloud bank remains populated when camera looks straight up')
check(countUp<80,'straight-up sealed-deck admission remains bounded for low-end hardware')

-- Broken clouds still use projected-frustum behavior; this guards against
-- solving zenith coverage by globally disabling cloud culling.
local broken={coverage=.55,gate=-1,softGate=0,closedDeck=false,deckBlend=0,span=1,puffs=1,bank=.3}
frame.weather=broken
local countBroken=C.cloudDescriptorProbe(upVox,frame)
check(countBroken<=countUp,'broken cloud culling is not expanded beyond sealed-deck overhead admission')

io.write(string.format('cloudbank persistence/pitch: %d passed, %d failed\n',pass,fail))
os.exit(fail==0 and 0 or 1)
