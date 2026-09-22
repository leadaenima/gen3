local V = ...
local L={state={ambient=.75,diffuse=.72,cloudShadow=0,snowBounce=0,wetSpecular=0,moon=.0,sun=.0,stormDim=0,lightning=0}}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function L.update(dt,climate,surface,celestial,cloud)
  climate=climate or {}; surface=surface or {}; celestial=celestial or {}; cloud=cloud or {}
  local sun=clamp(tonumber(celestial.sunLight) or tonumber(celestial.sun) or 0,0,1); local moon=clamp(tonumber(celestial.moonLight) or tonumber(celestial.moon) or 0,0,1)
  local cloudD=clamp(tonumber(cloud.density) or tonumber(climate.cloud) or 0,0,1); local storm=clamp(tonumber(climate.storm) or 0,0,1)
  local snow=clamp(tonumber(surface.snow) or 0,0,1); local wet=clamp(tonumber(surface.wet) or 0,0,1); local refl=clamp(tonumber(surface.reflectivity) or 0,0,1)
  local target={sun=sun,moon=moon,cloudShadow=cloudD*(.35+.35*sun),stormDim=storm*.42,snowBounce=snow*(.18+.18*(sun+moon)),wetSpecular=wet*refl,ambient=clamp(.18+sun*.68+moon*.20+snow*.10-storm*.18,0,1),diffuse=clamp(.15+sun*.76+moon*.16-cloudD*.22-storm*.12,0,1)}
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/.45); for k,v in pairs(target) do L.state[k]=(tonumber(L.state[k]) or v)+(v-(tonumber(L.state[k]) or v))*f end
end
function L.observeLightning(v) L.state.lightning=math.max(tonumber(L.state.lightning) or 0,tonumber(v) or 0) end
function L.decay(dt) L.state.lightning=(tonumber(L.state.lightning) or 0)*math.exp(-math.max(0,tonumber(dt) or 0)*9) end
function L.peek() return L.state end
function L.sample() local o={}; for k,v in pairs(L.state) do o[k]=v end; return o end
return L
