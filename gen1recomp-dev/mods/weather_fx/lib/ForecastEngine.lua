local V = ...
local F={}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function summarize(o)
  if (tonumber(o.storm) or 0)>.62 then return 'severe storm likely'
  elseif (tonumber(o.precip) or 0)>.55 then return 'precipitation likely'
  elseif (tonumber(o.cloud) or 0)>.62 then return 'mostly cloudy'
  elseif (tonumber(o.visibility) or 1)<.55 then return 'low visibility' end
  return 'stable'
end
function F.at(x,z,seconds)
  seconds=math.max(0,tonumber(seconds) or 300)
  local W=V.require('WorldClimate'); local o=W.forecastAt(x,z,seconds)
  local ok,M=pcall(V.require,'MesoscaleField')
  local ms=ok and M and (not M.ready or M.ready()) and M.forecastAt and M.forecastAt(x,z,seconds) or nil
  if ms then
    o.precip=clamp((tonumber(o.precip) or 0)*(tonumber(ms.precipScale) or 1),0,1)
    o.cloud=clamp((tonumber(o.cloud) or 0)*(tonumber(ms.cloudScale) or 1),0,1)
    o.storm=clamp((tonumber(o.storm) or 0)*(tonumber(ms.stormScale) or 1),0,1)
    o.visibility=clamp(math.min(tonumber(o.visibility) or 1,tonumber(ms.visibility) or 1),0,1)
    o.band=tonumber(ms.band) or 0; o.front=tonumber(ms.front) or 0; o.mesoscale=true
    o.summary=summarize(o)
  end
  return o
end
function F.timeline(x,z,steps,stepSeconds)
  steps=math.max(1,math.min(12,tonumber(steps) or 6)); stepSeconds=math.max(30,tonumber(stepSeconds) or 300); local out={}
  for i=1,steps do out[i]=F.at(x,z,i*stepSeconds) end; return out
end
return F
