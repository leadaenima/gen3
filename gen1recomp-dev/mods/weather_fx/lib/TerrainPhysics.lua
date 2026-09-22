local V = ...
-- Read-only environmental movement physics. Hosts/companions opt in to apply
-- these coefficients; Weather FX does not seize player movement authority.
local T={}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function T.response(surface,accum,wind)
  surface=surface or {}; accum=accum or {}; wind=wind or {}
  local friction=clamp(tonumber(surface.friction) or .9,.05,1.2)
  local ice=clamp(tonumber(surface.ice) or 0,0,1); local mud=clamp(tonumber(surface.mud) or 0,0,1); local snow=clamp(tonumber(surface.snow) or 0,0,1); local puddle=clamp(tonumber(surface.puddle) or 0,0,1)
  local traction=clamp(friction*(1-ice*.72)*(1-mud*.28),.06,1)
  local speed=clamp(1-snow*.20-mud*.18-puddle*.06,.58,1)
  local push=clamp((tonumber(wind.speed) or 0)*.08,0,.12)
  return {traction=traction,speedScale=speed,windPush=push,slip=clamp(1-traction,0,1),deepSnow=(tonumber(accum.snowHeight) or 0)>1.8}
end
function T.at(x,z)
  local S=V.require('EnvironmentSurface'); local A=V.require('AccumulationGeometry'); local W=V.require('WindFlow')
  return T.response(S.sample(x,z),A.sample(),W.sampleAt(x,z))
end
return T
