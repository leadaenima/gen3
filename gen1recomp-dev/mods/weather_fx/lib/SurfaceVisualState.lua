local V = ...
local S={state={wet=0,puddle=0,mud=0,frost=0,ice=0,snow=0,leaves=0,scorch=0,reflectivity=0,roughness=1,friction=1,snowHeight=0,leafHeight=0,puddleDepth=0,mudDepth=0,serial=0}}
function S.update(surface,accum,hydro)
  surface=surface or {}; accum=accum or {}; hydro=hydro or {}; local q=S.state
  for _,k in ipairs({'wet','puddle','mud','frost','ice','snow','leaves','scorch','reflectivity','roughness','friction'}) do if surface[k]~=nil then q[k]=surface[k] end end
  q.snowHeight=tonumber(accum.snowHeight) or 0; q.leafHeight=tonumber(accum.leafHeight) or 0; q.puddleDepth=math.max(tonumber(accum.puddleDepth) or 0,tonumber(hydro.depth) or 0); q.mudDepth=tonumber(accum.mudDepth) or 0; q.serial=q.serial+1
end
function S.peek() return S.state end
function S.sample() local o={}; for k,v in pairs(S.state) do o[k]=v end; return o end
return S
