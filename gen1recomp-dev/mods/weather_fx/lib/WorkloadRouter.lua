local V = ...
local R={}; local families={'particles','clouds','lighting','surface','audio','simulation','environment'}; local state={target='none',pressure=0,serial=0,manual=false}; for _,f in ipairs(families) do state[f]=1 end
local function clamp(v,a,b) v=tonumber(v) or 0; if v<a then return a elseif v>b then return b end return v end
local function req(n) local ok,m=pcall(V.require,n); if ok then return m end end
function R.update(dt)
  local G=req('PerformanceGovernor'); local manual=G and G.auto and not G.auto() or false; state.manual=manual
  if manual then for _,f in ipairs(families) do state[f]=1 end; state.target='none'; state.pressure=0; state.serial=state.serial+1; return end
  local P=req('SystemProfiler'); local prof=P and P.peek and P.peek() or {}; local perf=G and G.peek and G.peek() or {}; state.pressure=clamp(math.max(tonumber(prof.pressure) or 0,tonumber(perf.pressure) or 0),0,1)
  local target=tostring(prof.recommendation or ''):match('^trim:(.+)$') or 'none'; state.target=target; dt=math.max(0,tonumber(dt) or 0)
  for _,fam in ipairs(families) do local wanted=1; if target~='none' then if target=='environment' then wanted=clamp(1-state.pressure*.23,.74,1) elseif fam==target then local floor=(fam=='particles' or fam=='clouds') and .52 or (fam=='surface' and .66 or .72); wanted=clamp(1-state.pressure*.43,floor,1) end end; local cur=state[fam]; local tau=(wanted<cur) and .45 or 4.8; state[fam]=clamp(cur+(wanted-cur)*(1-math.exp(-dt/math.max(.01,tau))),.45,1) end
  state.serial=state.serial+1
end
function R.scale(f) local G=req('PerformanceGovernor'); if G and G.auto and not G.auto() then return 1 end; return math.max(.45,math.min(1,state[tostring(f or 'environment')] or 1)) end
function R.peek() return state end
function R.sample() local o={}; for k,v in pairs(state) do o[k]=v end; return o end
function R.reset() for _,f in ipairs(families) do state[f]=1 end; state.target='none'; state.pressure=0; state.serial=0; state.manual=false end
return R
