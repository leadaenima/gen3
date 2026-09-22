local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1 else fail=fail+1; print((v and 'PASS ' or 'FAIL ')..n) end end
love={graphics={getDimensions=function() return 1280,720 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end}
local generic={}
local V={mod={id='weather_fx',options={get=function() return nil end}},weatherFxId='RAIN_HEAVY',weatherFxChannels={rain=1.3}}
function V.require(n)
 if n=='Settings' then return Settings end
 if n=='WeatherSetting' then return {new=function() return {get=function() return 'full' end} end} end
 if n=='ForestAtmos' then return {time=0,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}} end
 if n=='MesoscaleField' then return {ready=function() return false end} end
 if n=='PerformanceGovernor' then return {scale=function() return 1 end} end
 if n=='Quality' then return {budget=function() return {worldPrecip=1} end} end
 if n=='Scene' then return {now={visible='world',outdoor=true}} end
 return generic
end
V.safeCall=pcall
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local closed={coverage=1,gate=-1,softGate=0,closedDeck=true,deckBlend=1,deckWidth=1.82,deckDepth=1.12,deckY0=110,deckYSpan=24,span=1,puffs=1,bank=.72}
local frame={level=1,canopy=false,weather=closed,windState={advectX=0,advectZ=0}}
-- Deliberately hostile projection: cloud centres project far outside historical Y
-- gates, forcing the physical overhead admission to be the authority.
local function cam(pitchDeg,yawDeg)
 local p=math.rad(pitchDeg); local y=math.rad(yawDeg); local cp=math.cos(p)
 return {eye={0,8,0},player={0,0,0},far=800,
   focus={math.sin(y)*cp*100,8+math.sin(p)*100,-math.cos(y)*cp*100},
   vp={.001,0,0,0, 0,1,0,0, 0,0,.001,0, 0,0,0,1},
   size=function() return 1280,720 end}
end
local forward=C.cloudDescriptorProbe(cam(0,0),frame)
local up50=C.cloudDescriptorProbe(cam(50,0),frame)
local up50turn=C.cloudDescriptorProbe(cam(50,140),frame)
local down=C.cloudDescriptorProbe(cam(-25,0),frame)
local upAgain=C.cloudDescriptorProbe(cam(50,0),frame)
ck(forward>0,'closed deck populated looking forward')
ck(up50>0,'closed deck remains populated at Battle Art maximum upward pitch')
ck(up50turn>0,'zenith bank survives upward look after yaw rotation')
ck(down>0,'bank state survives looking back down')
ck(upAgain>0,'cloud bank is still present when player looks up again')
ck(upAgain==up50,'repeat upward look does not reseed/drop cloud descriptors')
ck(up50<96 and up50turn<96,'wider zenith admission stays bounded for low-end hardware')
print(('8.2.8 repeated zenith cloud persistence: %d/%d PASS'):format(pass,pass+fail))
os.exit(fail==0 and 0 or 1)
