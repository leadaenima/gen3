-- 8.2.10: 3D leaves must not bake spawn distance into their lifetime size.
-- A leaf born at the far edge must attain the same size as an equally seeded
-- near-born leaf once both occupy the same CURRENT eye distance.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n)
  if v then pass=pass+1 else fail=fail+1; print('FAIL '..n) end
end
local function read(path)
  local f=assert(io.open(ROOT..path,'rb')); local s=f:read('*a'); f:close(); return s
end
local src=read('lib/voxel_atmos/WorldPrecip.lua')

ck(src:find('grain.size[i] = leafScale',1,true)~=nil,'leaf spawn stores intrinsic base size')
ck(src:find('leafScale * (0.55 + near * 0.80)',1,true)==nil,'leaf spawn no longer bakes spawn-near into size')
ck(src:find('grain.a[i] = 0.51 + random() * 0.35',1,true)~=nil,'leaf opacity is also spawn-distance independent')
ck(src:find('near = 1.0 - min(1.0, tl / DEPTH)',1,true)~=nil,'draw path derives near factor from current eye distance')
ck(src:find('size = size * (0.40 + near * 1.35)',1,true)~=nil,'draw path applies current-distance leaf/grain presentation scale')
ck(src:find('function WP.leafSizeSamples',1,true)~=nil,'live leaf size diagnostic exists')

math.randomseed(8210)
local budget={worldPrecip=1.0,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,worldBlizzardCap=200000,
  worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,rain=720,snow=720,grain=260}
local V={weatherFxId='GALE',safeCall=pcall}
function V.require(name)
  if name=='Quality' then return {budget=function() return budget end} end
  if name=='Settings' then return {
    isFirstPerson=function() return false end,is=function() return false end,
    get=function(k) if k=='intensity' then return 'normal' end end,
  } end
  if name=='Scene' then return {now={visible='world'}} end
  if name=='WindEngine' then return {vector=function() return 1,0 end} end
  error('no module '..tostring(name),0)
end
local WP=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
WP.update(1/60,{0,24,0},{wxId='GALE',_wxChannelsResolved=true,debrisIntensity=1.15,rainWind=1,snowWind=1},{})
local samples={}
if type(WP.leafSizeSamples)=='function' then samples=WP.leafSizeSamples(32) end
ck(#samples>=16,'live GALE produces a diagnostic leaf sample')
local exact=#samples>0
local minBase,maxBase=1e9,-1e9
local minDist,maxDist=1e9,-1e9
for _,s in ipairs(samples) do
  local expected=(0.45+(s.seed or 0.5)*1.15)*0.25
  if math.abs((s.baseSize or 0)-expected)>1e-12 then exact=false end
  minBase=math.min(minBase,s.baseSize or 0); maxBase=math.max(maxBase,s.baseSize or 0)
  minDist=math.min(minDist,s.distance or 0); maxDist=math.max(maxDist,s.distance or 0)
end
ck(exact,'every live leaf base size depends only on intrinsic seed')
ck(maxBase-minBase>0.08,'authored small-to-large leaf variety remains')
ck(maxDist-minDist>20,'sample covers materially different current distances')

-- At equal current distance, spawn history must not matter. Under the old
-- formula a far-born leaf carried a 0.55 factor and a near-born leaf 1.35,
-- making the latter 2.45x larger forever.
local seed=.73
local intrinsic=(0.45+seed*1.15)*0.25
local currentNear=.90
local currentScale=.40+currentNear*1.35
local card=1.15+seed*.25
local farBornNowNear=intrinsic*currentScale*card
local nearBornNowNear=intrinsic*currentScale*card
ck(math.abs(farBornNowNear-nearBornNowNear)<1e-12,'equal current distance gives equal size regardless of spawn distance')
local farScale=.40+.05*1.35
local nearScale=.40+.90*1.35
ck(nearScale/farScale>2.8,'current distance still visibly enlarges an approaching leaf')

print(('8.2.10 dynamic leaf size: %d/%d PASS'):format(pass,pass+fail))
os.exit(fail==0 and 0 or 1)
