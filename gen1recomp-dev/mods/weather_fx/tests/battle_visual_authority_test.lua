-- Battle visuals must read the battle's weather authority, never silently
-- inherit the overworld when the field is dry.
local passed, failed = 0,0
local function check(c,m) if c then passed=passed+1 else failed=failed+1; io.stderr:write('FAIL: '..m..'\n') end end

local Types=assert(loadfile('lib/Types.lua'))()
local State={id='STORM'}
local Settings={
  battleScale=function() return 1 end,
  get=function(k) if k=='lightning' then return 'off' end return nil end,
}
local Config={visual=function() return true end}
local Quality={budget=function() return {rain=100} end}
local Lightning={flash=function() return 0 end}
local Battle={animEnabled=function() return true end}
local Compat={}
local req={Types=Types,WeatherState=State,Settings=Settings,Config=Config,Quality=Quality,Lightning=Lightning,Battle=Battle,Compat=Compat}
local V={require=function(name) local v=req[name]; if v==nil then error('unexpected require '..tostring(name)) end; return v end}
local BD=assert(loadfile('lib/BattleDraw.lua'))(V)

BD.reset()
for _=1,360 do BD.tick(1/60,{field={weather=nil}}) end
check(BD.channel('rain')==0,'dry battle field stays dry under stormy overworld')
check(BD.channel('veil')==0,'dry battle field has no inherited storm veil')

for _=1,360 do BD.tick(1/60,{field={weather='RAINY'}}) end
check(BD.channel('rain')>0.25,'field RAINY drives battle rain')

-- Host/Crystal alternate battle.weather remains a valid battle authority.
BD.reset()
for _=1,360 do BD.tick(1/60,{field={},weather='rain'}) end
check(BD.channel('rain')>0.25,'host battle.weather rain drives battle rain')

-- Removing field weather eases back toward dry instead of falling back to sky.
for _=1,720 do BD.tick(1/60,{field={weather=nil}}) end
check(BD.channel('rain')<0.005,'clearing battle field weather clears visuals despite stormy overworld')

print(('battle visual authority: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
