local V = ...
-- Advisory compatibility state only. No production renderer consumes these
-- planning radii, so 8.1.47 computes them only when an SDK/debug caller asks.
local S={state={nearRadius=256,midRadius=800,farRadius=2048,extremeRadius=4096,physicsScale=1,visualScale=1,activeBands=4,serial=0}}
local function clamp(v,a,b) v=tonumber(v) or 0; if v<a then return a elseif v>b then return b end return v end
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end
local function refresh()
  local G=req('PerformanceGovernor'); local perf=G and G.peek and G.peek() or nil
  local isAuto=not perf or perf.mode=='auto'
  local scale=isAuto and clamp(perf and perf.scale or 1,.42,1) or 1
  local R=req('WorkloadRouter'); local routed=isAuto and (R and R.scale and R.scale('environment') or 1) or 1
  local p=clamp(scale*routed,.42,1)
  S.state.physicsScale=isAuto and clamp(.65+.35*p,.65,1) or 1
  S.state.visualScale=isAuto and p or 1
  S.state.nearRadius=math.floor(192+64*S.state.visualScale+.5)
  S.state.midRadius=math.floor(640+160*S.state.visualScale+.5)
  S.state.farRadius=math.floor(1536+512*S.state.visualScale+.5)
  S.state.extremeRadius=math.floor(3072+1024*S.state.visualScale+.5)
  local H=req('HostAdapter'); local c=H and H.capabilities and H.capabilities() or nil
  S.state.activeBands=(c and c.voxel) and 4 or 3; S.state.serial=S.state.serial+1
  return S.state
end
function S.update(dt,scene,climate) return refresh() end
function S.peek() return refresh() end
function S.sample() refresh(); local o={}; for k,v in pairs(S.state) do o[k]=v end; return o end
return S
