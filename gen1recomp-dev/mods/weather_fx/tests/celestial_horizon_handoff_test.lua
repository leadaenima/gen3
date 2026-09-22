-- Celestial horizon / renderer-handoff regression (4.35.9).
-- Protects against the historical post-sunset ghost sun and sunrise snap:
-- every visible path must use CelestialEngine's composed presentation hour,
-- and 3D/fallback discs must clip the below-horizon portion geometrically.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function read(rel)
  local f=assert(io.open(ROOT..rel,"rb")); local s=f:read("*a"); f:close(); return s
end

local main=read("main.lua")
local bodiesSrc=read("lib/CelestialBodies.lua")
local skySrc=read("lib/NightSky.lua")

check(main:find('CB.projectBoth(w,h,edge,nil,nil)',1,true)~=nil,
  "fallback sky consumes composed/smoothed celestial state")
check(main:find('CB.projectBoth(w,h,edge,TOD and TOD.hour,nil)',1,true)==nil,
  "fallback sky no longer bypasses smoothing with raw TOD.hour")
check(main:find('_wxAltitudeDeg',1,true)~=nil and main:find('pixelAlt < 0',1,true)~=nil,
  "fallback pixel disc clips below-horizon pixels")
check(bodiesSrc:find('vWorldY < horizonY',1,true)~=nil and bodiesSrc:find('horizonClip",1.0',1,true)~=nil,
  "CelestialBodies 3D disc uses geometric horizon clipping")
check(skySrc:find('altitudeDeg - p.y*radiusDeg < 0.0',1,true)~=nil and skySrc:find('_projectedBodyShaderSource',1,true)~=nil,
  "NightSky analytic 3D sun/moon path uses geometric limb clipping")
check(skySrc:find('horizonClip", 0.0',1,true)~=nil,
  "star/planet shader path explicitly disables body-only horizon clip")

-- Runtime proof that a nil hour resolves through CelestialEngine.state instead
-- of the raw host TOD. The raw clock is deliberately far away from the engine
-- presentation sample so an accidental fallback is easy to detect.
local cfg={celestial={enabled=true,verticalOrbit=true,pairedMoonOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=28}}
local tod={hour=22.0,source="voxel",elapsed=0}
local sun={dx=-0.25,dy=0.15,dz=0,kind="sun",alpha=0.4,horizonFraction=0.7,altitudeDeg=8.5,intensity=0.4,color={1,1,1}}
local moon={dx=0.25,dy=-0.15,dz=0,kind="moon",alpha=0,horizonFraction=0,altitudeDeg=-8.5,intensity=0,illumination=.5,phase=.25,color={1,1,1}}
local engine={state=function() return {hour=18.25,sun=sun,moon=moon,sim={eclipse={}}} end}
local modules={Config={get=function() return cfg end},TimeOfDay=tod,CelestialEngine=engine}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local CB=assert(loadfile(ROOT.."lib/CelestialBodies.lua"))(V)
local ps,pm=CB.projectBoth(320,240,200,nil,nil)
check(ps~=nil and pm==nil,"projectBoth nil-hour uses live engine visibility")
check(ps and math.abs(ps.x-(0.5+0.40*sun.dx)*320)<1e-6,
  "projected sun position comes from engine presentation state, not raw TOD")
check(ps and math.abs((ps._wxAltitudeDeg or 0)-8.5)<1e-9,
  "fallback projection carries altitude for horizon clipping")

-- Fully hidden bodies may never project. A tiny last visible limb may project,
-- but the renderer then clips the portion below the horizon rather than drawing
-- a full faded disc outside the world.
engine.state=function()
  return {hour=18.4,
    sun={dx=-.99,dy=-.09,dz=0,kind="sun",alpha=0,horizonFraction=0,altitudeDeg=-5,intensity=0,color={1,1,1}},
    moon={dx=.99,dy=.09,dz=0,kind="moon",alpha=.2,horizonFraction=.6,altitudeDeg=5,intensity=.1,illumination=.5,phase=.25,color={1,1,1}},
    sim={eclipse={}}}
end
local hs,hm=CB.projectBoth(320,240,200,nil,nil)
check(hs==nil and hm~=nil,"fully below-horizon sun cannot survive fallback projection")

print(("celestial horizon/handoff: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
