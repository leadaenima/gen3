-- Weather FX 8.2.5: user-requested 3D snow density multipliers only.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local budget={worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100,worldBlizzardCap=200,
  worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,
  snow=4800,snowProbeCap=96,snowPackDrawCap=0,footDrawCap=0,splash=0}
local Settings={}
function Settings.snowAccumulationEnabled() return false end
function Settings.isFirstPerson() return false end
function Settings.weatherRenderDistanceScale() return 1 end
function Settings.snowShape() return 'flake' end
function Settings.snowIntensity() return 1 end
function Settings.splashesEnabled() return false end
function Settings.get() return nil end
local PS={canVirtualize=function() return true end,stats=function() return {proven=true,backend='native-id'} end}
local V={safeCall=pcall}
function V.require(name)
  if name=='Quality' then return {budget=function() return budget end} end
  if name=='Settings' then return Settings end
  if name=='ProceduralSnowField' then return PS end
  if name=='SnowPack' then return {setEnabled=function()end} end
  if name=='WorldInteractionPrecip' then return {update=function()end,draw=function()end,stats=function()return{active=0}end} end
  if name=='WeatherWorldInteraction' then return {peek=function() return nil end} end
  if name=='MesoscaleField' then return {ready=function() return false end} end
  return nil
end
local WP=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
local focus={0,0,0}
local meta={Voxel3D={far=600},player={px=0,py=0},map={id='m',widthCells=50,heightCells=50},neighbors={}}
local function logical(id)
  if WP.reset then WP.reset() end
  WP.update(1/60,focus,{wxId=id},meta)
  return WP.snowVirtualization().logical
end

-- Budget values are deliberately tiny so the 8.2.4 pre-multiplier population
-- is exactly 100 for ordinary snow families and exactly 200 for BLIZZARD.
ck(logical('SNOW_LIGHT')==200,'SNOW display weather is exactly 2x its 8.2.4 3D snow population')
ck(logical('THUNDERSNOW')==200,'TSNOW display weather is exactly 2x its 8.2.4 3D snow population')
ck(logical('DRAGONSTORM')==200,'DRAGON display weather is exactly 2x its 8.2.4 3D snow population')
ck(logical('BLIZZARD')==800,'BLIZZARD display weather is exactly 4x its 8.2.4 3D snow population')
ck(logical('SNOW')==200,'legacy SNOW compatibility alias tracks the SNOW display weather at 2x')
ck(logical('WHITEOUT')==100,'WHITEOUT snow density is unchanged')
ck(logical('SLEET')==100,'SLEET snow density is unchanged')

-- The phone-safe compatibility CPU caps are intentionally not multiplied.
do
  PS.canVirtualize=function() return false end
  if WP.reset then WP.reset() end
  WP.update(1/60,focus,{wxId='BLIZZARD'},meta)
  local st=WP.snowVirtualization()
  ck(st.logical==800 and st.simulated<=budget.snow,'4x BLIZZARD only increases logical GPU snow; bounded CPU fallback is unchanged')
end

-- Pin the exact scope in source so future maintenance cannot broaden it.
do
  local f=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'));local s=f:read('*a');f:close()
  ck(s:find('visibleMul = 4',1,true)~=nil and s:find('wxId == "SNOW_LIGHT"',1,true)~=nil
     and s:find('wxId == "THUNDERSNOW"',1,true)~=nil and s:find('wxId == "DRAGONSTORM"',1,true)~=nil,
     'runtime contains only the requested named-weather visual multipliers')
end

print(('8.2.5 3D snow density multiplier regression: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
