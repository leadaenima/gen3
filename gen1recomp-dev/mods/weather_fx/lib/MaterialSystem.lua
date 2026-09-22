local V = ...

-- Material response catalogue used by sparse EnvironmentSurface cells. These are
-- environmental coefficients, not replacement voxel materials, so host mods are
-- never modified.
local M={}
M.PROFILES={
  soil={porosity=.72,drainage=.45,roughness=.82,reflectivity=.08,friction=.92,snowRetention=.88,heat=.78},
  grass={porosity=.64,drainage=.58,roughness=.90,reflectivity=.10,friction=.95,snowRetention=.96,heat=.70},
  stone={porosity=.12,drainage=.28,roughness=.62,reflectivity=.16,friction=.82,snowRetention=.72,heat=.92},
  pavement={porosity=.08,drainage=.22,roughness=.48,reflectivity=.20,friction=.80,snowRetention=.68,heat=1.02},
  roof={porosity=.05,drainage=.82,roughness=.40,reflectivity=.24,friction=.72,snowRetention=.54,heat=.95},
  wood={porosity=.38,drainage=.42,roughness=.70,reflectivity=.12,friction=.84,snowRetention=.74,heat=.76},
  metal={porosity=.01,drainage=.88,roughness=.22,reflectivity=.46,friction=.66,snowRetention=.38,heat=1.18},
  sand={porosity=.86,drainage=.76,roughness=.88,reflectivity=.18,friction=.78,snowRetention=.30,heat=1.20},
  water={porosity=0,drainage=1,roughness=.06,reflectivity=.66,friction=.18,snowRetention=0,heat=.55},
  ice={porosity=0,drainage=.05,roughness=.08,reflectivity=.52,friction=.16,snowRetention=.62,heat=.42},
}
local ALIAS={ground='soil',dirt='soil',road='pavement',brick='stone',rock='stone',tree='wood',canopy='grass',vegetation='grass'}
function M.normalize(name)
  name=tostring(name or 'soil'):lower(); name=ALIAS[name] or name
  if not M.PROFILES[name] then name='soil' end
  return name
end
function M.profile(name) return M.PROFILES[M.normalize(name)] end
function M.responseInto(name,state,out)
  local p=M.profile(name); state=state or {}; out=out or {}; local wet=tonumber(state.wet) or 0; local ice=tonumber(state.ice) or 0; local snow=tonumber(state.snow) or 0
  out.roughness=math.max(.04,p.roughness*(1-wet*.35)*(1-ice*.55)); out.reflectivity=math.min(.92,p.reflectivity+wet*.34+ice*.28)
  out.friction=math.max(.08,p.friction*(1-wet*.16)*(1-ice*.72)*(1-snow*.18)); out.snowRetention=p.snowRetention; out.porosity=p.porosity; out.drainage=p.drainage; out.heat=p.heat
  return out
end
function M.response(name,state) return M.responseInto(name,state,{}) end
return M
