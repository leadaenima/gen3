-- Weather FX 8.1.72 player-facing 3D weather render-distance cap, with the
-- 8.1.92 snow-coverage correction: snow obeys the distance percentage in both
-- front modes while rain/hail retain their regional fronts-ON reach.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

-- Settings/menu contract.
local values={weatherRenderDistance='100'}
local Types={PINNED={},byId={}}; function Types.get() return nil end
local defined
local mod={id='weather_fx',options={define=function(_,rows) defined=rows;return true end,get=function(_,k)return values[k] end},events={on=function()end},log={info=function()end,warn=function()end}}
local modules={Types=Types};local V={mod=mod,safeCall=pcall}
function V.require(name)
  if modules[name] then return modules[name] end
  if name=='ConnectedWater' or name=='Microclimate' then return nil end
  local m=assert(loadfile(ROOT..'lib/'..name..'.lua'))(V);modules[name]=m;return m
end
local S=V.require('Settings');S.define()
local row=S.row('weatherRenderDistance')
ck(row and row.label=='3D PRECIP DISTANCE' and row.default=='100','3D PRECIP DISTANCE is exposed and defaults to 100%')
local choice={};for _,c in ipairs((row and row.choices) or {}) do choice[c[2]]=c[1] end
ck(choice['25']=='25%' and choice['50']=='50%' and choice['75']=='75%' and choice['100']=='100%','weather distance exposes only decreasing 25/50/75/100 choices')
local precipGroup
for _,g in ipairs(S.GROUPS or {}) do if g.id=='precipitation' then precipGroup=g end end
local inGroup=0;for _,k in ipairs((precipGroup and precipGroup.keys) or {}) do if k=='weatherRenderDistance' then inGroup=inGroup+1 end end
ck(inGroup==1,'3D PRECIP DISTANCE appears exactly once in PRECIPITATION submenu')
local hasScaleHelper=type(S.weatherRenderDistanceScale)=='function'
ck(hasScaleHelper,'Settings exposes live weatherRenderDistanceScale helper')
for k,want in pairs({['25']=.25,['50']=.50,['75']=.75,['100']=1.0}) do
  values.weatherRenderDistance=k;S.beginFrame()
  ck(hasScaleHelper and math.abs(S.weatherRenderDistanceScale()-want)<1e-12,'menu '..k..'% resolves to '..want..'x weather-only scale')
end

-- Runtime contract.
local fronts=false
local scale=1.0
local RuntimeSettings={
  isFirstPerson=function() return false end,
  splashOn=function() return false end,
  cloudHeightScale=function() return 1.5 end,
  get=function(_,k) if k=='fronts' then return fronts and 'on' or 'off' end return 'config' end,
  snowAccumulationEnabled=function() return false end,
  weatherRenderDistanceScale=function() return scale end,
}
local Config={get=function() return {fronts={enabled=fronts}} end}
local Quality={budget=function() return {
  worldPrecip=.001, worldRadiusCap=128,
  worldSnowCap=64, worldBlizzardCap=64, worldRainCap=64, worldHailCap=64,
  worldSandCap=64, worldAshCap=64, worldDebrisCap=64,
  snowPackDrawCap=0, footDrawCap=0, splash=0,
} end}
local RV={safeCall=pcall}
function RV.require(name)
  if name=='Settings' then return RuntimeSettings end
  if name=='Config' then return Config end
  if name=='Quality' then return Quality end
  error('no module '..tostring(name),0)
end
local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(RV)
local focus={0,0,0}
local function meta(far)
  return {anchorKind='player',deckY=120,deckSpan=2,Voxel3D={far=far},volume={farPrecipScale=.72}}
end
local function near(a,b) return math.abs((tonumber(a) or -999)-(tonumber(b) or -777))<1e-9 end

fronts=false
scale=1.0
local m=meta(1600); W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},m)
ck(near(W.snowVirtualization().fieldRadius,1600),'fronts OFF + 100%: snow equals voxel render distance exactly')
ck(m.Voxel3D.far==1600,'100% weather distance does not modify voxel render distance')
scale=.75;W.update(1/60,focus,{wxId='RAIN',rainIntensity=1.0},meta(1600))
ck(near(W.precipVirtualization().rain.radius,1200),'fronts OFF + 75%: rain reach is exactly 75% of voxel render distance')
scale=.50;W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(1600))
ck(near(W.snowVirtualization().fieldRadius,800),'fronts OFF + 50%: snow reach is exactly half voxel render distance')
scale=.25;W.update(1/60,focus,{wxId='HAIL',hailIntensity=1.25},meta(1600))
local hv=W.precipVirtualization()
ck(near(hv.grain.radius[1],400),'fronts OFF + 25%: hail reach is exactly one quarter voxel render distance')
local lowHail=(hv.grain.logical and hv.grain.logical[1]) or 0
scale=1.0;W.update(1/60,focus,{wxId='HAIL',hailIntensity=1.25},meta(1600))
local fullHail=(W.precipVirtualization().grain.logical and W.precipVirtualization().grain.logical[1]) or 0
ck(fullHail>0 and lowHail>0 and math.abs(lowHail/fullHail-.0625)<.04,'hail population scales by covered area so lower distance does not artificially increase hail density')

-- 8.1.92: fronts may vary snow density/patchiness, but no longer shrink the
-- snow volume below the user-selected voxel-distance percentage.
fronts=true
scale=1.0;W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(2048));local s100=W.snowVirtualization().fieldRadius
scale=.25;W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(2048));local s25=W.snowVirtualization().fieldRadius
ck(near(s100,2048) and near(s25,512),'fronts ON: snow follows 3D WEATHER DISTANCE against the live voxel far plane')
scale=1.0;W.update(1/60,focus,{wxId='RAIN',rainIntensity=1.0},meta(2048));local r100=W.precipVirtualization().rain.radius
scale=.25;W.update(1/60,focus,{wxId='RAIN',rainIntensity=1.0},meta(2048));local r25=W.precipVirtualization().rain.radius
ck(near(r100,r25) and r100<=128,'fronts ON: regional rain keeps inherited quality/front radius')

print(('3D weather render distance 8.1.72: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
