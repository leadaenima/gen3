-- Lightweight physical rainbow state.
-- A primary rainbow is possible only after recent rain, with the sun visible
-- above the horizon and below ~42 degrees. The state is presentation-agnostic;
-- strict 3D/FPV consumes it as depth-tested sky geometry.
local V=...
local R={alpha=0,target=0,wetMemory=0,recentRain=0,lastRain=0,serial=0}
local exp=math.exp
local function clamp(v,a,b) v=tonumber(v) or 0;if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function req(n) local ok,m=pcall(V.require,n);return ok and m or nil end
local function enabled()
  local C=req("Config");local c=C and C.get and C.get() or {};return not (type(c.rainbow)=="table" and c.rainbow.enabled==false),type(c.rainbow)=="table" and c.rainbow or {}
end
function R.update(dt,state,scene)
  dt=clamp(dt,0,.5);if dt<=0 then return R end
  local on,cfg=enabled();local outdoor=not scene or (scene.visible=="world" and scene.outdoor and not scene.indoors)
  local rain=0
  if state and type(state.channel)=="function" then local ok,v=pcall(state.channel,"rain");if ok then rain=clamp(v,0,2) end end
  if rain>.08 and outdoor then
    R.wetMemory=math.min(1,R.wetMemory+dt*(.16+.34*math.min(1,rain)))
    R.recentRain=0;R.lastRain=rain
  else
    R.recentRain=R.recentRain+dt
    local memory=math.max(20,tonumber(cfg.memorySeconds) or 120)
    R.wetMemory=math.max(0,R.wetMemory-dt/memory)
    R.lastRain=rain
  end
  local target=0
  if on and outdoor and R.wetMemory>.01 and rain<.10 then
    local CE=req("CelestialEngine");local s=CE and CE.state and CE.state() or nil;local sun=s and s.sun
    if sun then
      local alt=tonumber(sun.altitudeDeg) or -90
      -- A primary rainbow is geometrically possible only with the sun low.
      -- Ease both ends so sunrise/42-degree cutoffs cannot pop.
      local low=smooth((alt-.5)/3.5);local high=smooth((42.5-alt)/7.5);local geo=low*high
      local trans=clamp(tonumber(sun.discTransmission) or 0,0,1)*clamp(tonumber(sun.alpha) or 0,0,1)
      local cloud=clamp(s.optics and s.optics.cloud or 0,0,1)
      local breakFactor=clamp((trans-.08)/.55,0,1)*(1-.28*cloud)
      local postRain=smooth(clamp((R.recentRain+.5)/4,0,1))
      target=clamp(R.wetMemory*geo*breakFactor*postRain,0,1)
    end
  end
  if not on or not outdoor then target=0 end
  R.target=target
  local fade=math.max(.5,tonumber(cfg.fadeSeconds) or 8)
  local tau=target>R.alpha and fade or fade*1.25
  local f=1-exp(-dt/tau);R.alpha=R.alpha+(target-R.alpha)*f
  if R.alpha<.0005 and target==0 then R.alpha=0 end
  R.serial=R.serial+1;return R
end
function R.state()
  local CE=req("CelestialEngine");local s=CE and CE.state and CE.state() or nil;local sun=s and s.sun
  return {alpha=R.alpha,target=R.target,wetMemory=R.wetMemory,recentRain=R.recentRain,
    sun=sun and {dx=sun.dx,dy=sun.dy,dz=sun.dz,altitudeDeg=sun.altitudeDeg,discTransmission=sun.discTransmission} or nil,serial=R.serial}
end
function R.peek() return R end
function R.invalidate() R.alpha,R.target,R.wetMemory,R.recentRain,R.lastRain=0,0,0,0,0;R.serial=0 end
return R
