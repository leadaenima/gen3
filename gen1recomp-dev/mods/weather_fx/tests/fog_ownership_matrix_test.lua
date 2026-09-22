local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end
local dummySetting={get=function() return 'full' end,level=function() return 1 end}
local ModSetting={new=function() return dummySetting end}
local DayNight={isCanopy=function() return false end,isNight=function() return false end}
local modules={DayNight=DayNight,ForestAtmos={time=0},ShadowMap={},WeatherSetting=ModSetting,TileShape={},Sky={},Mat4={},SpriteBillboards={},TerrainAtlas={}}
local V={safeCall=pcall,weatherFxId='CLEAR'}
function V.require(n)
  if n=='WorldPrecip' then return {} end
  if modules[n] then return modules[n] end
  error('optional '..tostring(n),0)
end
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local f,m=C._mistPolicy(0,1)
check(f==0 and m==false,'zero authored fog cannot create ground mist')
f,m=C._mistPolicy(.01,1.3)
check(f==0 and m==false,'trace/noise fog below threshold cannot create mist')
f,m=C._mistPolicy(.5,1)
check(math.abs(f-.5)<1e-9 and m==true,'authored fog weather creates mist at authored strength')
f,m=C._mistPolicy(.5,2)
check(math.abs(f-.66)<1e-9 and m==true,'mesoscale fog scale remains bounded at 1.32x')
f,m=C._mistPolicy(.5,.01)
check(math.abs(f-.14)<1e-9 and m==true,'mesoscale fog scale remains bounded at 0.28x')
local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
check(src:find('weather.fog,weather._mistVisual=CinematicAtmos._mistPolicy(authoredFog,fogScale)',1,true)~=nil,'live 3D weather frame uses explicit fog policy')
local Types=assert(loadfile(ROOT..'lib/Types.lua'))()
for _,id in ipairs({'SNOW_LIGHT','BLIZZARD','HAIL','THUNDERSNOW','RAIN_LIGHT','RAIN_HEAVY','HEAVY_RAIN','STORM','GALE'}) do
  check((Types.channel(Types.get(id),'fog') or 0)<=.02,id..' does not author explicit fog')
end
for _,id in ipairs({'FOG','MIST','SMOG','HAUNTED_MIST'}) do
  check((Types.channel(Types.get(id),'fog') or 0)>.02,id..' explicitly owns fog')
end
print(('fog ownership matrix: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
