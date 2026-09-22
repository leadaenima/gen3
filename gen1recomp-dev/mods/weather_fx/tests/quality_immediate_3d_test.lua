-- A live QUALITY/PARTICLE CAP edit must invalidate WorldPrecip's cached budget
-- on the very next update, not after the 0.25s ordinary refresh window.
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end
local rev={quality=0,particleCap=0}
local budget={worldPrecip=1,worldRadiusCap=220,worldRainCap=12000,worldSnowCap=100000,worldBlizzardCap=200000,worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,splash=1,snowPackDrawCap=0,footDrawCap=0}
local Settings={isFirstPerson=function() return false end,is=function() return false end,keyRevision=function(k) return rev[k] or 0 end}
local V={weatherFxId='CUSTOM'}
function V.require(n)
  if n=='Quality' then return {budget=function() return budget end} end
  if n=='Settings' then return Settings end
  if n=='Scene' then return {now={visible='world'}} end
  if n=='WindEngine' then return {vector=function() return 1,0 end} end
  error('missing '..tostring(n),0)
end
local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
local wx={wxId='CUSTOM',rainIntensity=1.5,snowIntensity=0,hailIntensity=0,sandIntensity=0,ashIntensity=0,debrisIntensity=0,rainWind=1}
W.update(1/60,{0,24,0},wx,{})
local before=W.liveCounts({}).rain
check(before>550,'high/MAX-style budget establishes a rain population above POTATO cap')
budget={worldPrecip=.28,worldRadiusCap=180,worldRainCap=550,worldSnowCap=1600,worldBlizzardCap=2400,worldHailCap=800,worldSandCap=900,worldDebrisCap=260,worldAshCap=600,splash=0,snowPackDrawCap=0,footDrawCap=0}
rev.quality=rev.quality+1
W.update(1/60,{0,24,0},wx,{})
local after=W.liveCounts({}).rain
check(after<=550,'QUALITY edit shrinks live 3D rain on next update without waiting for cache timeout')
check(after<before,'QUALITY edit materially changes live allocator immediately')

-- Same proof for the separate absolute particle ceiling.
budget={worldPrecip=1,worldRadiusCap=220,worldRainCap=12000,worldSnowCap=100000,worldBlizzardCap=200000,worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,splash=1,snowPackDrawCap=0,footDrawCap=0}
rev.quality=rev.quality+1
W.update(1/60,{0,24,0},wx,{})
local restored=W.liveCounts({}).rain
check(restored>550,'raising quality restores larger live rain population immediately')
budget.worldRainCap=300
rev.particleCap=rev.particleCap+1
W.update(1/60,{0,24,0},wx,{})
check(W.liveCounts({}).rain<=300,'PARTICLE HARD CAP edit invalidates 3D budget on next update')
print(('quality immediate 3D: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
