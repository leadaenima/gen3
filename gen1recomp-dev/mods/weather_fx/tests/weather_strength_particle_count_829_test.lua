-- 8.2.9: fixed WEATHER STRENGTH must scale actual 3D logical populations,
-- including families whose NORMAL count already reaches a quality-tier cap.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1 else fail=fail+1; print((v and 'PASS ' or 'FAIL ')..n) end end
local budget={worldPrecip=1.00,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,worldBlizzardCap=200000,
  worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,splash=0,snowPackDrawCap=0,footDrawCap=0,
  rain=720,snow=720,grain=260}
local function build(id,strength)
  local V={weatherFxId=id}
  function V.require(name)
    if name=='Quality' then return {budget=function() return budget end} end
    if name=='Settings' then return {
      isFirstPerson=function() return false end,is=function() return false end,
      get=function(k) if k=='intensity' then return strength end end,
    } end
    if name=='Scene' then return {now={visible='world'}} end
    if name=='WindEngine' then return {vector=function() return 1,0 end} end
    error('no module '..tostring(name),0)
  end
  return assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
end
local S={soft=.45,normal=1,heavy=1.5}
local cases={
  {'RAIN_HEAVY','rainIntensity',1.5,'rain'},
  {'SNOW_LIGHT','snowIntensity',1.9,'snow'},
  {'BLIZZARD','snowIntensity',2.2,'snow'},
  {'HAIL','hailIntensity',1.25,'hail'},
  {'SANDSTORM','sandIntensity',2.35,'sand'},
  {'ASHFALL','ashIntensity',1.45,'ash'},
  {'GALE','debrisIntensity',1.15,'debris'},
}
for _,c in ipairs(cases) do
  local out={}
  for _,name in ipairs{'soft','normal','heavy'} do
    local W=build(c[1],name)
    local w={wxId=c[1],_wxChannelsResolved=true,rainWind=1,snowWind=1}
    w[c[2]]=c[3]*S[name]
    W.update(1/60,{0,24,0},w,{})
    out[name]=(W.liveCounts({})[c[4]] or 0)
  end
  ck(out.soft<out.normal and out.normal<out.heavy,c[1]..' count is SOFT < NORMAL < HEAVY')
  ck(math.abs(out.soft/out.normal-.45)<.012,c[1]..' SOFT count is about 45% of NORMAL')
  ck(math.abs(out.heavy/out.normal-1.5)<.012,c[1]..' HEAVY count is about 150% of NORMAL')
end
-- AUTO must not apply a second fixed budget multiplier.
do
  local W=build('RAIN_HEAVY','auto')
  W.update(1/60,{0,24,0},{wxId='RAIN_HEAVY',_wxChannelsResolved=true,rainIntensity=1.5,rainWind=1,snowWind=1},{})
  ck((W.liveCounts({}).rain or 0)==12000,'AUTO retains existing channel-driven rain budget')
end
print(('8.2.9 WEATHER STRENGTH particle counts: %d/%d PASS'):format(pass,pass+fail))
os.exit(fail==0 and 0 or 1)
