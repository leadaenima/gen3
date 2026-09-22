local V = ...
-- Predictive workload headroom. Unlike PerformanceGovernor, which reacts to
-- measured frame/memory pressure, this estimates the next-frame environmental
-- load from storm/cloud/precip state so optional work can trim before a spike.
local P={state={predicted=0,headroom=1,particleScale=1,volumeScale=1}}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function P.update(dt,climate,volume)
  climate=climate or {}; volume=volume or {}
  local load=clamp((tonumber(climate.precip) or 0)*.34+(tonumber(climate.storm) or 0)*.24+(tonumber(volume.cloudVolume) or 0)*.22+(tonumber(volume.precipVolume) or 0)*.20,0,1)
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/1.6); P.state.predicted=P.state.predicted+(load-P.state.predicted)*f
  P.state.headroom=clamp(1-P.state.predicted*.38,.62,1); P.state.particleScale=clamp(1-P.state.predicted*.28,.70,1); P.state.volumeScale=clamp(1-P.state.predicted*.22,.76,1)
end
function P.peek() return P.state end
function P.sample() local o={}; for k,v in pairs(P.state) do o[k]=v end; return o end
function P.particleScale() return P.state.particleScale end
function P.volumeScale() return P.state.volumeScale end
return P
