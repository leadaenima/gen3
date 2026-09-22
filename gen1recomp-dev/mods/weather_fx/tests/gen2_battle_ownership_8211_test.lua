-- Weather FX 8.2.11: Gen2Recomped owns retail battle-weather mechanics.
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local native = true
local HostRuntime={nativeGen2BattleWeather=function() return native end}
local cfg={battle={enabled=true,effects={heldItems=false},suppressSet={},items={}}}
local Config={get=function() return cfg end,battleEffect=function(k) return cfg.battle.effects[k] ~= false end}
local Settings={battleDamageOn=function() return true end,battleAnimOn=function() return true end}
local Types={}
local State={}
local mod={find=function() return nil end,log={info=function() end}}
local V={mod=mod}
function V.require(name)
  local m={Types=Types,Config=Config,Settings=Settings,WeatherState=State,HostRuntime=HostRuntime}
  if m[name] then return m[name] end
  error('unexpected require '..tostring(name))
end
local B=assert(loadfile('lib/Battle.lua'))(V)
B._hostCrystal=false

for _,w in ipairs({'RAIN','SUN','SANDSTORM','HAIL'}) do
  local battle={field={weather=w},player={},enemy={}}
  check(B.nativeMechanicsOwn(battle),w..' is native-owned on Gen2')
  check(B.weather(battle)==nil,w..' global Weather FX mechanics stand down')
  check(B.weatherFor(battle,{mon={}})==nil,w..' battler Weather FX mechanics stand down')
end

local custom={field={wxWeather='PSYSTORM'},player={},enemy={}}
check(not B.nativeMechanicsOwn(custom),'custom sidecar is not native-owned')
check(B.weather(custom)=='PSYSTORM','custom sidecar keeps Weather FX mechanics')
check(B.weatherFor(custom,{mon={}})=='PSYSTORM','custom sidecar reaches battler mechanics')
check(B.visualWeather('RAIN')=='RAINY','native rain maps to Weather FX visual vocabulary')
check(B.visualWeather('SUN')=='SUNNY','native sun maps to Weather FX visual vocabulary')

native=false
local gen1={field={weather='RAINY'},player={},enemy={}}
check(not B.nativeMechanicsOwn(gen1),'Gen1 does not defer weather mechanics')
check(B.weather(gen1)=='RAINY','Gen1 rain keeps original Weather FX mechanics')
check(B.weatherFor(gen1,{mon={}})=='RAINY','Gen1 battler rain path unchanged')

print(('gen2 battle ownership 8.2.11: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
