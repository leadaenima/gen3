local V = ...
local SDK={version=5}
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end
function SDK.snapshot(x,z)
  local H=req('HostAdapter'); if x==nil and H and H.worldPosition then x,z=H.worldPosition() end; x,z=tonumber(x) or 0,tonumber(z) or 0
  local out={api=5,x=x,z=z}
  local modules={micro='Microclimate',mesoscale='MesoscaleField',worldClimate='WorldClimate',volume='VolumetricWeather',volumeRenderer='VolumetricRenderer',lighting='UnifiedLighting',ecosystem='EcosystemEngine',accumulation='AccumulationGeometry',streamer='WorldStreamer',gpuWeather='GPUWeatherEngine',surfaceVisuals='SurfaceVisuals',profiler='SystemProfiler',workloadRouter='WorkloadRouter'}
  for k,n in pairs(modules) do local m=req(n); if m and m.sample then out[k]=m.sample() end end
  local S=req('EnvironmentSurface'); if S and S.sample then out.surface=S.sample(x,z) end
  local W=req('WindFlow'); if W and W.sampleAt then out.wind=W.sampleAt(x,z) end
  local Hy=req('Hydrology'); if Hy and Hy.sampleAt then out.hydrology=Hy.sampleAt(x,z) end
  local LP=req('LightProbeGrid'); if LP and LP.sampleAt then out.lightProbe=LP.sampleAt(x,z) end
  local WI=req('WeatherWorldInteraction'); if WI and WI.sample then out.weatherInteraction=WI.sample() end
  return out
end
function SDK.forecast(x,z,seconds) local F=req('ForecastEngine'); return F and F.at and F.at(x,z,seconds) or nil end
function SDK.subscribe(kind,fn) local E=req('EnvironmentalEvents'); return E and E.subscribe and E.subscribe(kind,fn) or false end
function SDK.events(since) local E=req('EnvironmentalEvents'); return E and E.recent and E.recent(since or 0,{}) or {} end
return SDK
