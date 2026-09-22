local V = ...
local A={state={snowHeight=0,leafHeight=0,puddleDepth=0,mudDepth=0,frost=0,ice=0,displacement=0}}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
function A.update(dt,surface,hydro)
  surface=surface or {}; hydro=hydro or {}
  local s=A.state
  local targetSnow=clamp(tonumber(surface.snow) or 0,0,1)*3.2
  local targetLeaf=clamp(tonumber(surface.leaves) or 0,0,1)*1.35
  local targetPuddle=math.max(clamp(tonumber(surface.puddle) or 0,0,1)*.18,tonumber(hydro.depth) or 0)
  local targetMud=clamp(tonumber(surface.mud) or 0,0,1)*.22
  local f=1-math.exp(-math.max(0,tonumber(dt) or 0)/1.4)
  s.snowHeight=s.snowHeight+(targetSnow-s.snowHeight)*f; s.leafHeight=s.leafHeight+(targetLeaf-s.leafHeight)*f; s.puddleDepth=s.puddleDepth+(targetPuddle-s.puddleDepth)*f; s.mudDepth=s.mudDepth+(targetMud-s.mudDepth)*f
  s.frost=clamp(tonumber(surface.frost) or 0,0,1); s.ice=clamp(tonumber(surface.ice) or 0,0,1); s.displacement=math.max(s.snowHeight,s.leafHeight,s.mudDepth)
end
function A.peek() return A.state end
function A.sample() local o={}; for k,v in pairs(A.state) do o[k]=v end; return o end
return A
