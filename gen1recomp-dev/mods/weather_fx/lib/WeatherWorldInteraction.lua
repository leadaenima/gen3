local V = ...

-- Weather FX 8.1.88 world/weather interaction state.
--
-- This module deliberately does not own terrain, weather selection, wind, NPCs,
-- or companion-mod geometry. It converts the already-authoritative Weather FX
-- state into a small set of physical consequences that renderers can consume:
-- retained roof/canopy water, post-rain shaft strength, vegetation loading, and
-- one bounded world-space travelling gust-front descriptor.
local W={version=1}
local exp,sqrt=math.exp,math.sqrt
local function clamp(v,a,b) v=tonumber(v) or 0;if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function req(n) local ok,m=pcall(V.require,n);return ok and m or nil end
local function channel(state,key)
  if type(state)~="table" then return 0 end
  if type(state.channel)=="function" then local ok,v=pcall(state.channel,key);if ok then return tonumber(v) or 0 end end
  if type(state.ch)=="table" then return tonumber(state.ch[key]) or 0 end
  return 0
end
local function outdoor(scene) return not (type(scene)=="table" and scene.indoors==true) end

local rng=8188
local function rand01() rng=(rng*48271)%2147483647;return rng/2147483647 end

local gust={active=false,kind="air",x=0,z=0,dirX=1,dirZ=0,width=0,height=0,speed=0,strength=0,age=0,duration=0,serial=0}
local vegetation={wetLoad=0,snowLoad=0,sag=0,windBend=0,gustPhase=0,gustStrength=0,recovery=1}
local S={rain=0,snow=0,roofLoad=0,canopyLoad=0,roofDrip=0,canopyDrip=0,postRainShaft=0,vegetation=vegetation,gustFront=gust,serial=0}
local gustCooldown=2.5
local lastGustEnvelope=0

local function gustKind(id,rain,snow)
  id=tostring(id or ""):upper()
  if snow>.08 or id:find("SNOW",1,true) or id=="BLIZZARD" or id=="WHITEOUT" then return "snow" end
  if id=="SANDSTORM" or id=="DUSTSTORM" then return "dust" end
  if id=="ASHFALL" or id=="BLACK_ASH" then return "ash" end
  if rain>.08 or id=="RAIN" or id=="HEAVY_RAIN" or id=="PRIMAL_RAIN" or id=="STORM" then return "spray" end
  return "leaves"
end

local function publish(kind,data)
  local E=req("EnvironmentalEvents");if E and E.publish then pcall(E.publish,kind,data) end
end

local function endGust()
  if not gust.active then return end
  gust.active=false
  publish("gust_front_end",{serial=gust.serial,kind=gust.kind,x=gust.x,z=gust.z})
end

local function startGust(x,z,wind,state,rain,snow)
  local mag=sqrt((tonumber(wind.x) or 0)^2+(tonumber(wind.z) or 0)^2)
  local dx,dz=tonumber(wind.x) or 0,tonumber(wind.z) or 0
  if mag<1e-5 then
    local a=tonumber(wind.angle) or 0;dx,dz=math.cos(a),math.sin(a)
  else dx,dz=dx/mag,dz/mag end
  local strength=clamp(tonumber(wind.strength) or mag,0,1.5)
  gust.serial=gust.serial+1;gust.active=true;gust.kind=gustKind(state and state.id,rain,snow)
  -- Spawn upstream in canonical world space. Camera position/orientation is never
  -- consulted, so turning the camera cannot move or respawn the gust front.
  local upstream=125+55*rand01()
  gust.x=(tonumber(x) or 0)-dx*upstream;gust.z=(tonumber(z) or 0)-dz*upstream
  gust.dirX,gust.dirZ=dx,dz
  gust.width=110+70*strength;gust.height=14+13*strength
  gust.speed=42+38*strength;gust.strength=clamp(.38+.52*strength,0,1)
  gust.age=0;gust.duration=5.0+1.8*rand01()
  publish("gust_front_begin",{serial=gust.serial,kind=gust.kind,x=gust.x,z=gust.z,dirX=dx,dirZ=dz,strength=gust.strength})
end

function W.update(dt,state,surface,scene,x,z)
  dt=clamp(dt,0,.5);surface=surface or {};local isOutdoor=outdoor(scene)
  local rain=clamp(channel(state,"rain"),0,2);local snow=clamp(channel(state,"snow"),0,2)
  S.rain,S.snow=rain,snow

  -- Retained water is deliberately tiny state, not a roof/tree scan. Actual
  -- eave/canopy emission is sampled by WorldPrecip against the live host shape
  -- resolver. This memory is what lets the world keep dripping after rain stops.
  if isOutdoor and rain>.06 then
    S.roofLoad=clamp(S.roofLoad+dt*(.18+.26*math.min(1,rain)),0,1)
    S.canopyLoad=clamp(S.canopyLoad+dt*(.15+.31*math.min(1,rain)),0,1)
  else
    S.roofLoad=math.max(0,S.roofLoad-dt/(isOutdoor and 58 or 24))
    S.canopyLoad=math.max(0,S.canopyLoad-dt/(isOutdoor and 112 or 42))
  end
  S.roofDrip=isOutdoor and S.roofLoad*(rain>.06 and .42 or 1) or 0
  S.canopyDrip=isOutdoor and S.canopyLoad*(rain>.06 and .34 or 1) or 0

  -- Post-rain shafts reuse Weather FX's real cloud-aware ray renderer. We only
  -- provide a bounded gain when retained rainwater, a clearing sun, and a dry
  -- local precipitation channel overlap.
  local rb=req("Rainbow");rb=rb and rb.peek and rb.peek() or nil
  local wet=clamp(rb and rb.wetMemory or math.max(tonumber(surface.wet) or 0,S.roofLoad*.6),0,1)
  local recent=tonumber(rb and rb.recentRain) or 999
  local CE=req("CelestialEngine");local cs=CE and CE.state and CE.state() or nil;local sun=cs and cs.sun or nil
  local shaft=0
  if isOutdoor and rain<.10 and wet>.01 and sun then
    local alt=tonumber(sun.altitudeDeg) or -90
    local trans=clamp((tonumber(sun.discTransmission) or 0)*(tonumber(sun.alpha) or 1),0,1)
    local timeWindow=smooth(recent/2.5)*smooth((95-recent)/35)
    local sunUp=smooth((alt-1.0)/8.0)
    local cloudBreak=smooth((trans-.08)/.58)
    shaft=clamp(wet*timeWindow*sunUp*cloudBreak,0,1)
  end
  S.postRainShaft=shaft

  local windM=req("WindEngine");local wind=windM and windM.peek and windM.peek() or {}
  local windStrength=clamp(tonumber(wind.strength) or 0,0,1.5)
  local env=clamp(tonumber(wind.envelope) or 0,0,1.5)
  local wetTarget=clamp(math.max(tonumber(surface.wet) or 0,S.canopyLoad*.72,rain*.18),0,1)
  local snowTarget=clamp(math.max(tonumber(surface.snow) or 0,snow*.22),0,1)
  local f=1-exp(-dt/1.8)
  vegetation.wetLoad=vegetation.wetLoad+(wetTarget-vegetation.wetLoad)*f
  vegetation.snowLoad=vegetation.snowLoad+(snowTarget-vegetation.snowLoad)*f
  vegetation.sag=clamp(vegetation.wetLoad*.22+vegetation.snowLoad*.58,0,.72)
  vegetation.windBend=clamp(windStrength*(1-vegetation.snowLoad*.24),0,1.35)
  vegetation.gustPhase=tonumber(wind.phase2) or tonumber(wind.phase) or 0
  vegetation.gustStrength=env
  vegetation.recovery=clamp(1-vegetation.sag*.72,0,1)

  gustCooldown=math.max(0,gustCooldown-dt)
  if gust.active then
    gust.age=gust.age+dt;gust.x=gust.x+gust.dirX*gust.speed*dt;gust.z=gust.z+gust.dirZ*gust.speed*dt
    local dx=gust.x-(tonumber(x) or 0);local dz=gust.z-(tonumber(z) or 0)
    if gust.age>=gust.duration or dx*dx+dz*dz>520*520 or not isOutdoor then endGust() end
  elseif isOutdoor and gustCooldown<=0 then
    local severe=windStrength*.72+env*.28
    local rising=env-lastGustEnvelope
    local chance=dt*(.018+.055*clamp(severe-.45,0,1))
    if severe>.52 and (rising>.012 or rand01()<chance) then
      startGust(x,z,wind,state,rain,snow)
      gustCooldown=9+10*rand01()
    end
  end
  lastGustEnvelope=env
  S.serial=S.serial+1
  return S
end

function W.peek() return S end
function W.sample()
  return {version=W.version,rain=S.rain,snow=S.snow,roofLoad=S.roofLoad,canopyLoad=S.canopyLoad,roofDrip=S.roofDrip,canopyDrip=S.canopyDrip,postRainShaft=S.postRainShaft,
    vegetation={wetLoad=vegetation.wetLoad,snowLoad=vegetation.snowLoad,sag=vegetation.sag,windBend=vegetation.windBend,gustPhase=vegetation.gustPhase,gustStrength=vegetation.gustStrength,recovery=vegetation.recovery},
    gustFront={active=gust.active,kind=gust.kind,x=gust.x,z=gust.z,dirX=gust.dirX,dirZ=gust.dirZ,width=gust.width,height=gust.height,speed=gust.speed,strength=gust.strength,age=gust.age,duration=gust.duration,serial=gust.serial},serial=S.serial}
end
function W.invalidate() S.roofLoad,S.canopyLoad,S.roofDrip,S.canopyDrip,S.postRainShaft=0,0,0,0,0;endGust();gustCooldown=2.5 end
function W._reset(seed) rng=tonumber(seed) or 8188;S.roofLoad,S.canopyLoad,S.roofDrip,S.canopyDrip,S.postRainShaft=0,0,0,0,0;vegetation.wetLoad,vegetation.snowLoad,vegetation.sag,vegetation.windBend=0,0,0,0;gust.active=false;gust.serial=0;gustCooldown=2.5;lastGustEnvelope=0 end
return W
