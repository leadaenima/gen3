local V = ...
-- SDK/debug descriptor only. Actual voxel wet/puddle/snow/leaf rendering reads
-- SurfaceVisualState and the dedicated renderers directly. Compute this legacy
-- summary only on demand instead of maintaining a duplicate pass.
local S={state={geometryBudget=512,wetOverlay=0,puddleCoverage=0,snowDisplacement=0,leafDisplacement=0,mudDisplacement=0,frostOverlay=0,scorchOverlay=0,serial=0}}
local function clamp(v,a,b) v=tonumber(v) or 0; if v<a then return a elseif v>b then return b end return v end
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end
local function refresh(visual,stream)
  if not visual then local VZ=req('SurfaceVisualState'); visual=VZ and VZ.peek and VZ.peek() or {} end
  if not stream then local W=req('WorldStreamer'); stream=W and W.peek and W.peek() or {} end
  local G=req('PerformanceGovernor'); local auto=not G or not G.auto or G.auto(); local W=req('WorkloadRouter'); local routed=auto and (W and W.scale and W.scale('surface') or 1) or 1
  local q=S.state; q.geometryBudget=math.floor((64+448*clamp(stream.physicsScale or 1,.5,1))*clamp(routed,.55,1)+.5)
  q.wetOverlay=clamp(visual.wet or 0,0,1); q.puddleCoverage=clamp(math.max(visual.puddle or 0,(visual.puddleDepth or 0)*4),0,1); q.snowDisplacement=math.max(0,visual.snowHeight or 0); q.leafDisplacement=math.max(0,visual.leafHeight or 0); q.mudDisplacement=math.max(0,visual.mudDepth or 0); q.frostOverlay=clamp(visual.frost or 0,0,1); q.scorchOverlay=clamp(visual.scorch or 0,0,1); q.serial=q.serial+1
  return q
end
function S.update(dt,visual,stream) return refresh(visual,stream) end
function S.peek() return refresh() end
function S.sample() refresh(); local o={}; for k,v in pairs(S.state) do o[k]=v end; return o end
return S
