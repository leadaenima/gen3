local V = ...
local R={state={cloudSteps=28,shadowSteps=11,precipSlices=20,cloudScale=1,lightTransmission=1,farPrecipScale=1,shadowScale=1,backend='analytic-volume',serial=0}}
local function clamp(v,a,b) v=tonumber(v) or 0; if v<a then return a elseif v>b then return b end return v end
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end
function R.update(dt,volume,atmosphere)
  volume=volume or {}; atmosphere=atmosphere or {}
  local G=req('PerformanceGovernor'); local auto=not G or not G.auto or G.auto()
  local P=req('PredictiveBudget'); local ps=P and P.peek and P.peek() or (P and P.sample and P.sample() or {})
  local W=req('WorkloadRouter'); local routed=auto and (W and W.scale and W.scale('clouds') or 1) or 1
  local perf=auto and (G and G.scale and G.scale() or 1) or 1
  local predictive=auto and (tonumber(ps.volumeScale) or 1) or 1
  local scale=auto and clamp(predictive*routed*perf,.42,1) or 1
  R.state.cloudScale=scale
  R.state.cloudSteps=math.max(6,math.floor(8+20*scale+.5)); R.state.shadowSteps=math.max(3,math.floor(3+8*scale+.5)); R.state.precipSlices=math.max(5,math.floor(6+14*scale+.5))
  R.state.lightTransmission=clamp((tonumber(volume.lightTransmission) or 1)*(tonumber(atmosphere.sunTransmission) or 1),.02,1)
  R.state.farPrecipScale=clamp((tonumber(volume.farPrecipScale) or 1)*(.72+.28*scale),.60,1.25)
  R.state.shadowScale=clamp((tonumber(volume.shadowScale) or 1)*(.88+.12*scale),.78,1.22)
  R.state.serial=R.state.serial+1
end
function R.peek() return R.state end
function R.sample() local o={}; for k,v in pairs(R.state) do o[k]=v end; return o end
return R
