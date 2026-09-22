local V = ...
-- SDK/debug advisory budget, not the actual precipitation renderer. 8.1.47
-- removes its continuous runtime pass and derives the same budget on demand.
local G={state={densityScale=1,nearPhysics=1,midVisual=1,farVisual=1,particleBudget=0,instanceCap=0,backend='fallback',serial=0}}
local function clamp(v,a,b) v=tonumber(v) or 0; if v<a then return a elseif v>b then return b end return v end
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end
local function refresh(climate,streamer)
  if not climate then local M=req('Microclimate'); climate=M and M.peek and M.peek() or {} end
  if not streamer then local S=req('WorldStreamer'); streamer=S and S.peek and S.peek() or {} end
  local P=req('PerformanceGovernor'); local auto=not P or not P.auto or P.auto()
  local perf=auto and (P and P.particleScale and P.particleScale() or 1) or 1
  local PB=req('PredictiveBudget'); local predictive=auto and (PB and PB.particleScale and PB.particleScale() or 1) or 1
  local R=req('WorkloadRouter'); local routed=auto and (R and R.scale and R.scale('particles') or 1) or 1
  local streamScale=auto and clamp(streamer.visualScale or 1,.40,1) or 1
  G.state.densityScale=auto and clamp(perf*predictive*routed*streamScale,.30,1) or 1
  G.state.nearPhysics=auto and clamp(.72+.28*G.state.densityScale,.72,1) or 1
  G.state.midVisual=auto and clamp(.55+.45*G.state.densityScale,.55,1) or 1
  G.state.farVisual=auto and clamp(.35+.65*G.state.densityScale,.35,1) or 1
  local H=req('HostAdapter'); local caps=H and H.capabilities and H.capabilities() or {}
  G.state.backend=(caps.instancing and 'instanced') or (caps.mesh and 'mesh') or 'fallback'
  G.state.instanceCap=(G.state.backend=='instanced') and 131072 or 32768
  G.state.particleBudget=math.floor(G.state.instanceCap*((clamp(climate.precip or 0,0,1)*.7)+.3)*G.state.densityScale)
  G.state.serial=G.state.serial+1
  return G.state
end
function G.update(dt,climate,streamer) return refresh(climate,streamer) end
function G.peek() return refresh() end
function G.sample() refresh(); local o={}; for k,v in pairs(G.state) do o[k]=v end; return o end
function G.scale() return refresh().densityScale end
return G
