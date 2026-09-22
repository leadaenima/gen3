-- 8.2.9: pitching the camera must not create/delete/fade cloud descriptors.
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
local function cam(pitchDeg,yawDeg)
  local p=math.rad(pitchDeg); local y=math.rad(yawDeg); local cp=math.cos(p)
  return {eye={0,8,0},player={0,0,0},far=800,
    focus={math.sin(y)*cp*100,8+math.sin(p)*100,-math.cos(y)*cp*100},
    size=function() return 1280,720 end}
end
local profiles={
  closed={coverage=1,gate=-1,softGate=0,closedDeck=true,deckBlend=1,deckWidth=1.82,deckDepth=1.12,deckY0=110,deckYSpan=24,span=1,puffs=1,bank=.72},
  broken={coverage=.72,gate=.12,softGate=.08,closedDeck=false,deckBlend=.28,deckWidth=1.3,deckDepth=.82,deckY0=116,deckYSpan=26,span=1,puffs=.9,bank=.55},
}
for name,w in pairs(profiles) do
  local frame={level=1,canopy=false,weather=w,windState={advectX=0,advectZ=0}}
  local n0,f0,p0=C.cloudDescriptorProbe(cam(0,0),frame)
  ck(n0>0,name..' baseline has clouds')
  for _,pitch in ipairs{-30,15,30,45,50,70,85} do
    local n,f,p=C.cloudDescriptorProbe(cam(pitch,0),frame)
    ck(n==n0,name..' descriptor count stable at pitch '..pitch)
    ck(math.abs(f-f0)<1e-9,name..' total cloud alpha stable at pitch '..pitch)
    ck(p==p0,name..' primitive population stable at pitch '..pitch)
  end
end
-- Yaw may select a different bounded horizontal corridor; pitch at the SAME yaw
-- still must be invariant.
do
  local frame={level=1,canopy=false,weather=profiles.closed,windState={advectX=0,advectZ=0}}
  local n0,f0,p0=C.cloudDescriptorProbe(cam(0,140),frame)
  local n1,f1,p1=C.cloudDescriptorProbe(cam(50,140),frame)
  ck(n0==n1,'turned-yaw descriptor count stable through pitch')
  ck(math.abs(f0-f1)<1e-9,'turned-yaw total alpha stable through pitch')
  ck(p0==p1,'turned-yaw primitive population stable through pitch')
end
print(('8.2.9 pitch-stable cloud field: %d/%d PASS'):format(pass,pass+fail))
os.exit(fail==0 and 0 or 1)
