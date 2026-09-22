local V = ...

-- Environmental acoustic mix shared by rain/wind/thunder. It augments the
-- existing proven indoor low-pass path; unsupported audio backends still work.
local A={}
local current={rainGain=1,windGain=1,thunderGain=1,highCut=1,reverb=.08,wetReflection=0,waterStormGain=0,shelter=0,canopy=0,built=0,indoors=false}
local targetScratch={}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function approach(a,b,dt,tau) local f=1-math.exp(-dt/math.max(.01,tau)); return a+(b-a)*f end
function A.update(dt,climate,surface,scene)
  dt=math.max(0,tonumber(dt) or 0); climate=climate or {}; surface=surface or {}; scene=scene or {}
  local indoor=scene.indoors==true; local wet=clamp(tonumber(surface.wet) or 0,0,1); local storm=clamp(tonumber(climate.storm) or 0,0,1); local wind=clamp(tonumber(climate.wind) or 0,0,1); local precip=clamp(tonumber(climate.precip) or 0,0,1)
  local shelter=clamp(tonumber(climate.shelter) or 0,0,1); local canopy=clamp(tonumber(climate.canopy) or 0,0,1); local built=clamp(tonumber(climate.built) or 0,0,1); local water=clamp(tonumber(climate.water) or 0,0,1)
  local target=targetScratch
  -- Flat-world acoustic propagation: roofs/building canyons suppress direct rain
  -- and wind, forest canopy removes high-frequency rain detail, and dense town
  -- footprints partially muffle thunder. No mountain-distance model exists.
  local outdoorRain=clamp(.16+precip*.84+wet*.08,.16,1.08)
  target.rainGain=outdoorRain*(1-shelter*.52)*(1-canopy*.10)
  if indoor then target.rainGain=target.rainGain*.58 end
  target.windGain=clamp((.88+wind*.12)*(1-shelter*.68)*(1-canopy*.18),.12,1.05)
  if indoor then target.windGain=target.windGain*.44 end
  target.thunderGain=clamp((.92+wet*.06+storm*.04)*(1-built*.18-shelter*.12),.48,1.06)
  if indoor then target.thunderGain=target.thunderGain*.72 end
  target.highCut=indoor and .25 or clamp(1-(tonumber(climate.humidity) or .4)*.08-canopy*.14-built*.05,.62,1)
  target.reverb=clamp((indoor and .18 or .05)+wet*.10+storm*.06+built*.06+water*.04,0,.40)
  target.wetReflection=wet; target.waterStormGain=water*clamp(.25+wind*.45+storm*.35,0,1); target.shelter=shelter;target.canopy=canopy;target.built=built; target.indoors=indoor
  for k,v in pairs(target) do if type(v)=='number' then current[k]=approach(tonumber(current[k]) or v,v,dt,.45) else current[k]=v end end
end
function A.gain(kind) return tonumber(current[tostring(kind)..'Gain']) or 1 end
function A.peek() return current end
function A.sample() local o={}; for k,v in pairs(current) do o[k]=v end; return o end
return A
