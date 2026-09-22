local V = ...
local U={state={ambient=.7,diffuse=.7,specular=.1,cloudShadow=0,snowBounce=0,wetSpecular=0,lightning=0,finalDiffuse=.7,finalAmbient=.7,serial=0}}
local function clamp(v,a,b) v=tonumber(v) or 0; if v<a then return a elseif v>b then return b end return v end
function U.update(dt,dyn,atmos,volume,surface)
  dyn=dyn or {}; atmos=atmos or {}; volume=volume or {}; surface=surface or {}
  local a=clamp((tonumber(dyn.ambient) or .7)*(tonumber(atmos.skyLuminance) or 1)+.08*(tonumber(dyn.snowBounce) or 0),0,1.3)
  local d=clamp((tonumber(dyn.diffuse) or .7)*(tonumber(volume.lightTransmission) or 1),0,1.4)
  local spec=clamp((tonumber(surface.reflectivity) or 0)*(tonumber(surface.wet) or 0)*.8,0,1)
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/.25); local s=U.state
  s.ambient=s.ambient+(a-s.ambient)*f; s.diffuse=s.diffuse+(d-s.diffuse)*f; s.specular=s.specular+(spec-s.specular)*f
  s.cloudShadow=s.cloudShadow+(clamp(dyn.cloudShadow or 0,0,1)-s.cloudShadow)*f; s.snowBounce=s.snowBounce+(clamp(dyn.snowBounce or 0,0,1)-s.snowBounce)*f
  s.wetSpecular=s.wetSpecular+(clamp(dyn.wetSpecular or 0,0,1)-s.wetSpecular)*f; s.lightning=s.lightning+(clamp(dyn.lightning or 0,0,1.5)-s.lightning)*f
  s.finalDiffuse=clamp(s.diffuse+s.lightning*.8,0,1.5); s.finalAmbient=clamp(s.ambient+s.snowBounce*.2+s.lightning*.45,0,1.5); s.serial=s.serial+1
end
function U.peek() return U.state end
function U.sample() local o={}; for k,v in pairs(U.state) do o[k]=v end; return o end
return U
