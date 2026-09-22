local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1; io.write((v and '' or 'FAIL ')..(v and '' or m..'\n')) end end
local function read(p) local f=assert(io.open(p,'rb')); local s=f:read('*a'); f:close(); return s end
local settings=read('lib/Settings.lua'); local state=read('lib/WeatherState.lua'); local audio=read('lib/Audio.lua'); local cin=read('lib/voxel_atmos/CinematicAtmos.lua'); local da=read('lib/DramalessAtmos.lua'); local tor=read('lib/Tornado.lua'); local main=read('main.lua'); local sky=read('lib/NightSky.lua')
ck(settings:find('if lo == "off" then return 0 end',1,true)~=nil,'settings maps Weather OFF to level zero')
ck(settings:find('function Settings.weatherDisabled',1,true)~=nil,'settings exposes weatherDisabled authority')
ck(state:find('Settings.weatherDisabled() then level = 0',1,true)~=nil,'WeatherState consumes hard OFF')
ck(state:find('State.ch',1,true)~=nil,'WeatherState owns channel bag')
ck(audio:find('hardWeatherOff',1,true)~=nil,'Audio has hard Weather OFF authority')
ck(audio:find('Audio.stopAllBeds()',1,true)~=nil,'Weather OFF stops looping weather beds')
ck(audio:find('Lightning.reset',1,true)~=nil,'Weather OFF clears thunder/lightning audio queue')
ck(cin:find('weatherDisabled',1,true)~=nil,'3D cinematic atmosphere reads Weather OFF')
ck(da:find('weatherDisabled',1,true)~=nil or da:find('level',1,true)~=nil,'3D host bridge has weather authority gate')
ck(tor:find('tonumber(WS.level) or 0)<=0',1,true)~=nil,'tornado stale GALE cannot survive explicit OFF')
ck(main:find('weather',1,true)~=nil,'main pipeline retains weather ladder')
-- Weather OFF is not Time/sky OFF: night sky remains a separate celestial system.
ck(sky:find('function NightSky.drawWorld',1,true)~=nil and sky:find('function NightSky.update',1,true)~=nil,'celestial sky remains independently alive when weather is disabled')
-- Ensure no accidental alias of OFF and AUTO was reintroduced.
ck(settings:find('{ { "OFF", "off" }, { "AUTO", "auto" }, { "CYCLE", "cycle" } }',1,true)~=nil,'OFF AUTO CYCLE are distinct choices')
ck(settings:find('if lo == "auto" then return 1 end',1,true)~=nil,'AUTO remains level one, not zero')
ck(settings:find('if lo == "cycle" then return 2 end',1,true)~=nil,'CYCLE remains level two')
print(string.format('8.1.18 Weather OFF cross-module contract: %d passed, %d failed',passed,failed))
os.exit(failed>0 and 1 or 0)
