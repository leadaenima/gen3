local passed,failed=0,0
local function check(c,m) if c then passed=passed+1;print('PASS '..m) else failed=failed+1;io.stderr:write('FAIL '..m..'\n') end end
local Types=assert(loadfile('lib/Types.lua'))()
local State={id='BLIZZARD'}
local Settings={battleScale=function() return 1 end,get=function(k) if k=='lightning' then return 'off' end end}
local Config={visual=function() return true end}
local Quality={budget=function() return {rain=1100} end}
local Lightning={flash=function() return 0 end}
local Battle={animEnabled=function() return true end}
local req={Types=Types,WeatherState=State,Settings=Settings,Config=Config,Quality=Quality,Lightning=Lightning,Battle=Battle,Compat={}}
local V={require=function(name) local v=req[name]; if v==nil then error('unexpected require '..tostring(name)) end; return v end}
local BD=assert(loadfile('lib/BattleDraw.lua'))(V)

BD.reset()
check(BD.channel('snow')==0,'battle compositor starts dry after reset')
local battle={field={weather='SNOWY'}}
BD.begin(battle)
local expected=Types.channel(Types.get('BLIZZARD'),'snow')
check(BD.live==true,'battle compositor becomes live on battle start')
check(math.abs(BD.channel('snow')-expected)<1e-9,'battle start primes snow directly to inherited authored target')
local before=BD.channel('snow')
BD.tick(1/60,battle)
check(math.abs(BD.channel('snow')-before)<1e-9,'first battle tick does not dip or restart inherited snow')

-- A battle with no field weather must remain dry; begin() cannot leak the
-- overworld blizzard merely because State.id is snowy.
BD.begin({field={weather=nil}})
check(BD.channel('snow')==0,'dry battle begin does not inherit exterior snow without battle field authority')

-- Mid-battle weather changes still ease instead of snapping.
BD.begin({field={weather=nil}})
BD.tick(1/60,battle)
check(BD.channel('snow')>0 and BD.channel('snow')<expected,'mid-battle snow activation still eases normally')

print(('battle precip continuity 8.1.56: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
