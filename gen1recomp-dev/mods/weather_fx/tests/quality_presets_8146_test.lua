-- Weather FX 8.1.46 whole-mod quality / low-end usability contract.
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;print((v and 'PASS ' or 'FAIL ')..n) end end
local values={quality='max',autoPerformance='balanced',performanceTarget='60',textureDetail='quality',reflectionDetail='quality',effectDistance='quality',simulationDetail='quality'}
local Settings={get=function(k) return values[k] end}
local Config={get=function() return {quality='auto',maxParticles=nil} end}
local cache={}
local V={}
function V.require(n)
  if n=='Settings' then return Settings end
  if n=='Config' then return Config end
  if cache[n] then return cache[n] end
  if n=='PerformanceGovernor' then return {particleScale=function() return 1 end} end
  error('unexpected require '..tostring(n),0)
end
local Q=assert(loadfile('lib/Quality.lua'))(V)
local order={'max','high','medium','low','potato'}
local seen={}
for _,tier in ipairs(order) do
  values.quality=tier
  local e=Q.effective();local b=Q.budget(1);local a=Q.auroraDetail()
  seen[tier]={tex=e.textureScale,dist=e.effectDistanceScale,sim=e.simulationInterval,cloud=e.cloudDetail,refl=e.reflection,radius=b.worldRadiusCap,rain=b.worldRainCap,aur=a.segments}
  check(e.tier==tier,tier..' master preset is literal')
end
for i=2,#order do
  local better,worse=seen[order[i-1]],seen[order[i]]
  check(better.tex>=worse.tex,order[i]..' does not increase generated texture resolution')
  check(better.dist>=worse.dist,order[i]..' does not increase effect distance')
  check(better.cloud>=worse.cloud,order[i]..' does not increase cloud detail')
  check(better.radius>=worse.radius,order[i]..' does not increase 3D presentation radius')
  check(better.rain>=worse.rain,order[i]..' does not increase rain allocation')
  check(better.aur>=worse.aur,order[i]..' does not increase aurora tessellation')
  check(better.sim<=worse.sim,order[i]..' slows only background simulation cadence')
end
check(seen.max.refl=='full' and seen.high.refl=='full' and seen.medium.refl=='full','MAX/HIGH/MEDIUM keep full near-water reflections')
check(seen.low.refl=='sky','LOW switches water to SKY + CELESTIAL reflection LOD')
check(seen.potato.refl=='simple','POTATO switches water to SIMPLE physical rendering')
check(seen.potato.tex<=.25 and seen.potato.radius<=180 and seen.potato.aur<=24,'POTATO has substantial texture/distance/aurora reductions')
-- Advanced rows override only their named subsystem.
values.quality='potato';values.textureDetail='full';values.reflectionDetail='full';values.effectDistance='far';values.simulationDetail='full'
local e=Q.effective()
check(e.textureScale==1 and e.reflection=='full' and e.effectDistanceScale==1 and e.simulationInterval==1,'advanced FOLLOW-QUALITY overrides can restore individual subsystems')
check(Q.budget(1).worldRainCap==550,'advanced presentation overrides do not silently raise POTATO particle allocation')
-- AUTO is bounded to POTATO..HIGH and target FPS is player-controlled.
values.quality='auto';values.textureDetail='quality';values.reflectionDetail='quality';values.effectDistance='quality';values.simulationDetail='quality';values.autoPerformance='aggressive';values.performanceTarget='40'
Q.reset();check(Q.tier()=='medium','AGGRESSIVE AUTO starts at MEDIUM for weak devices')
check(Q.autoEnabled() and Q.targetFps()==40,'AUTO PERFORMANCE and target FPS are live')
for _=1,220 do Q.update(.050) end
check(Q.tier()=='potato' or Q.tier()=='low','sustained sub-target frame pressure automatically reduces the preset')
values.autoPerformance='off';local held=Q.tier();for _=1,300 do Q.update(.060) end
check(Q.tier()==held,'AUTO PERFORMANCE OFF freezes adaptive tier changes')
print(string.format('8.1.46 quality presets: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
