-- Weather FX 4.35.18 world WindEngine regression.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local Wind=assert(loadfile('lib/WindEngine.lua'))()
local function sim(id,gust,seconds)
  Wind._reset(971731)
  local state={id=id,ch={gust=gust}}
  local minS,maxS=1e9,-1
  local minA,maxA=1e9,-1
  local prev=nil
  local maxStep=0
  local signs={}
  for i=1,math.floor(seconds*60) do
    Wind.update(1/60,state)
    local s=Wind.state()
    if i > 300 then
      minS=math.min(minS,s.strength); maxS=math.max(maxS,s.strength)
      minA=math.min(minA,s.angle); maxA=math.max(maxA,s.angle)
    end
    signs[(s.x>=0 and 'E' or 'W')..(s.z>=0 and 'S' or 'N')]=true
    if prev then
      local dx=s.x-prev.x; local dz=s.z-prev.z
      maxStep=math.max(maxStep,math.sqrt(dx*dx+dz*dz))
    end
    prev=s
  end
  local n=0 for _ in pairs(signs) do n=n+1 end
  return {minS=minS,maxS=maxS,minA=minA,maxA=maxA,maxStep=maxStep,dirs=n,last=Wind.state()}
end

local calm=sim('CLEAR',0,30)
check(calm.maxS < 0.005,'clear weather with zero gust stays essentially calm')

local rain=sim('RAIN',0.25,150)
check(rain.maxS > 0.03,'rain develops real wind')
check(rain.minS < rain.maxS*0.65,'rain naturally breathes into meaningful lulls')
check((rain.maxA-rain.minA) > 0.20,'rain prevailing direction slowly changes over time')
check(rain.maxStep < 0.03,'rain wind vector changes smoothly frame to frame')

local storm=sim('STORM',0.85,120)
check(storm.maxS > rain.maxS,'storm reaches stronger wind than ordinary rain')
check(storm.minS > 0.02,'storm retains a sustained wind floor between gusts')
check(storm.maxStep < 0.06,'storm directional changes remain continuous, never snap')

local gale=sim('GALE',1.0,120)
check(gale.minS > rain.minS,'gale has a stronger sustained floor than rain')
check(gale.maxS > 0.35,'gale reaches visibly strong world wind')

local sand=sim('SANDSTORM',1.0,120)
local psy=sim('PSYSTORM',1.0,120)
check(sand.maxS > 0.35,'sandstorm remains a strong advective weather')
check((psy.maxA-psy.minA) > (sand.maxA-sand.minA),'Psychic Storm veers more than the prevailing sandstorm flow')
check(psy.maxStep < 0.08,'Psychic Storm remains smooth despite unstable direction targets')

-- Integrated advection must never teleport when a weather/profile changes.
Wind._reset(12345)
local a={id='RAIN',ch={gust=.4}}
for i=1,600 do Wind.update(1/60,a) end
local before=Wind.state()
local b={id='GALE',ch={gust=1}}
Wind.update(1/60,b)
local after=Wind.state()
local advStep=math.sqrt((after.advectX-before.advectX)^2+(after.advectZ-before.advectZ)^2)
local vecStep=math.sqrt((after.x-before.x)^2+(after.z-before.z)^2)
check(advStep < 0.05,'weather change preserves continuous integrated cloud/fog advection')
check(vecStep < 0.08,'weather change eases wind vector instead of snapping direction/strength')

local dx,dz=Wind.direction()
check(math.abs(math.sqrt(dx*dx+dz*dz)-1)<1e-5,'direction() returns a normalized world XZ vector')
local sx=Wind.screenX(52)
check(type(sx)=='number','2D projection consumes the same world wind authority')

local st=Wind.state()
check(type(st.audio)=='number' and st.audio>=0 and st.audio<=1,'wind engine publishes a normalized audio envelope')
check(type(st.pitch)=='number' and st.pitch>=0.82 and st.pitch<=1.08,'wind engine publishes bounded subtle wind pitch variation')
check(type(st.advectX)=='number' and type(st.advectZ)=='number','wind engine publishes integrated world advection')

print(('wind engine: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
