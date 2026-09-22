local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1 else fail=fail+1; print((v and 'PASS ' or 'FAIL ')..n) end end
local cfg={celestial={enabled=true,latitude=35,axialTilt=23.43928,verticalOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=28}}
local TOD={hour=12,elapsed=0,source='cycle'}
local modules={Config={get=function() return cfg end},TimeOfDay=TOD,BuildingLight={starScale=function() return 1 end}}
local V={}
function V.require(n) if modules[n] then return modules[n] end error('unexpected require '..tostring(n),0) end
local Sim=assert(loadfile(ROOT..'lib/CelestialSim.lua'))(V); modules.CelestialSim=Sim
local Weather={id='RAIN_HEAVY',ch={rain=1.0}}
function Weather.channel(k) return Weather.ch[k] or 0 end
modules.WeatherState=Weather
local E=assert(loadfile(ROOT..'lib/CelestialEngine.lua'))(V)

-- A real 3D cloud observation means later cloud geometry, not a whole-sky alpha mask.
E.observeCloudField(.025,.96)
local noon=E.update(0,Weather)
ck(noon.geometryCloudOcclusion==true,'3D cloud observation selects geometry occlusion')
ck((noon.sun.alpha or 0)>.90,'sun remains present in the world-space vault behind dense clouds')
ck((noon.sun.cloudLineTransmission or 1)<.05,'dense cloud ray still blocks direct glare/god-ray optics')

TOD.hour=0
E.observeCloudField(.025,.96)
local night=E.update(0,Weather)
ck((night.starVisibility or 0)>.70,'stars/constellations remain astronomically alive behind dense cloud geometry')
ck(night.geometryCloudOcclusion==true,'night sky uses the same geometry-occlusion ownership')

-- The cycle must continue while 3D clouds are present; cloud cover may shade world
-- lighting but cannot freeze celestial directions.
TOD.hour=10; E.observeCloudField(.03,.94); local a=E.update(0,Weather)
TOD.hour=11; E.observeCloudField(.03,.94); local b=E.update(0,Weather)
local moved=math.abs((a.sun.dx or 0)-(b.sun.dx or 0))+math.abs((a.sun.dy or 0)-(b.sun.dy or 0))+math.abs((a.sun.dz or 0)-(b.sun.dz or 0))
ck(moved>.02,'sun cycle continues moving behind 3D weather clouds')

-- If no 3D cloud geometry is being observed, the old scalar weather attenuation
-- remains available to flat/non-geometry renderers. This prevents the repair from
-- making 2D overcast skies transparent.
E._cloudTransmission=nil; E._cloudCoverage=nil; E._cloudObservedAt=nil
TOD.hour=12; local flat=E.update(0,Weather)
ck(flat.geometryCloudOcclusion==false,'non-3D path retains scalar weather attenuation mode')
ck((flat.sun.alpha or 1)<(noon.sun.alpha or 0),'flat/non-geometry overcast still attenuates the sun')

print(('8.2.8 celestial cloud-gap persistence: %d/%d PASS'):format(pass,pass+fail))
os.exit(fail==0 and 0 or 1)
