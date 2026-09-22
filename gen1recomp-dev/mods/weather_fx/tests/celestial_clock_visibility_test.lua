-- Regression: voxel effective in-game clock must drive astronomy, and building
-- light pollution must change star brightness gradually in both directions.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name) end end
local function approx(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-4) end

local hostT=0
local hostDN={CYCLE=1200,DAY_LEN=600}
function hostDN.time() return hostT end
function hostDN.hours() return 13.5 end -- deliberately stale/raw wall clock
local cfg={time={source="auto",cycleMinutes=24,fixedPhase="DAY",grade=true,gradeStrength=1,publishTod=true,indoors=.35},celestial={enabled=true,latitude=35,axialTilt=23.43928},seasons={daysPerSeason=28}}
local Config={get=function() return cfg end}
local Settings={get=function(k) if k=="daytime" then return "on" elseif k=="indoors" then return "tint" end end}
local Interop={dayNight=function() return hostDN,"BATTLE_ART_VOXEL_FORK" end}
local modules={Config=Config,Settings=Settings,Interop=Interop}
local V={mod={log={warn=function() end}}}
function V.require(name) if modules[name] then return modules[name] end error("unexpected require "..tostring(name),0) end

local TOD=assert(loadfile(ROOT.."lib/TimeOfDay.lua"))(V); modules.TimeOfDay=TOD
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))(V); modules.CelestialSim=Sim
local function at(t) hostT=t; TOD.update(.1); return TOD.hour,Sim.sample() end
local h0,s0=at(0)
local h1,s1=at(300)
local h2,s2=at(600)
local h3,s3=at(900)
check(approx(h0,6,.01) and approx(h1,12,.01) and approx(h2,18,.01) and approx(h3,0,.01),"AUTO follows host effective CYCLE dial, not raw hours()")
check(math.abs(s0.sun.dx-s1.sun.dx)>.15 or math.abs(s0.sun.dy-s1.sun.dy)>.15,"sun world direction advances with in-game time")
check(math.abs(s1.moon.dx-s2.moon.dx)>.05 or math.abs(s1.moon.dy-s2.moon.dy)>.05,"moon world direction advances with in-game time")
check(TOD.source=="voxel","time source reports voxel host authority")

-- The same moving clock must drive a materially different environmental state.
local Weather={id="CLEAR",ch={}}
function Weather.channel(k) return 0 end
modules.WeatherState=Weather
local Engine=assert(loadfile(ROOT.."lib/CelestialEngine.lua"))(V); modules.CelestialEngine=Engine
hostT=300; TOD.update(.1); local noon=Engine.update(0,Weather)
hostT=900; TOD.update(.1); local midnight=Engine.update(0,Weather)
local function lum(c) return ((c and c[1] or 0)+(c and c[2] or 0)+(c and c[3] or 0))/3 end
check(noon.twilight~="NIGHT" and midnight.twilight=="NIGHT","in-game clock crosses real day/night celestial states")
check(noon.sunLight>midnight.sunLight and lum(noon.hostTint)>lum(midnight.hostTint),"day/night cycle changes world light, not only sky-object positions")
check(noon.starVisibility==0 and midnight.starVisibility>0,"deep sky is off in daylight and visible at night")

-- Standalone AUTO must fall back to accelerated game cycle rather than wall clock.
Interop.dayNight=function() return nil end
TOD.setHostOwnsClock(false)
TOD.elapsed=0
TOD.update(.1)
local c0=TOD.hour
TOD.elapsed=(cfg.time.cycleMinutes*60)*.25
TOD.update(0)
check(math.abs(((TOD.hour-c0+24)%24)-6)<.1,"AUTO fallback advances its own game cycle")

-- Building falloff proof.
local map={id="TEST_TOWN",widthCells=80,heightCells=40,events={{x=10,y=10,type="door"}}}
local Scene={now={mapId="TEST_TOWN",indoors=false,playerPosKnown=true,playerWorldX=10*16,playerWorldY=10*16}}
function Scene.overworld() return {map=map} end
modules.Scene=Scene
-- Force true night independently of the earlier cycle test.
TOD.tod="NITE"; TOD.hour=0; TOD.source="cycle"
local BL=assert(loadfile(ROOT.."lib/BuildingLight.lua"))(V); modules.BuildingLight=BL
local function targetAt(tileX)
  Scene.now.playerWorldX=tileX*16; Scene.now.playerWorldY=10*16
  BL.update(.1)
  return BL.debugInfo().factorRaw, BL.factor
end
local rNear=select(1,targetAt(10))
local r12=select(1,targetAt(22))
local r24=select(1,targetAt(34))
local r36=select(1,targetAt(46))
local rFar=select(1,targetAt(62))
check(rNear<=.01 and rNear<r12 and r12<r24 and r24<r36 and r36<rFar,"building star target brightens continuously with distance")
check(r12>.01 and r12<.5 and r24>.1 and r24<.8 and r36>.4 and r36<1,"building falloff spans broad intermediate brightness levels")
-- settle near, then prove one far frame cannot pop to full brightness
for i=1,120 do targetAt(10) end
local _,fNear=targetAt(10)
local _,fAway1=targetAt(62)
check(fNear<.1 and fAway1<.2,"moving away starts gradual star brightening without a one-frame pop")
for i=1,240 do targetAt(62) end
local _,fFar=targetAt(62)
local _,fBack1=targetAt(10)
check(fFar>.9 and fBack1>.75,"approaching building starts gradual dimming without a one-frame drop")
for i=1,240 do targetAt(10) end
check(BL.factor<.1,"continued approach eventually reaches dim near-building state")

-- Twilight envelope must be continuous and independent from building distance.
local solar=Sim.sample(12)
TOD.hour=solar.sunset; local atHorizon=Engine.update(0,Weather)
TOD.hour=(solar.sunset+0.5)%24; local atTwilight=Engine.update(0,Weather)
TOD.hour=(solar.sunset+1.2)%24; local atNight=Engine.update(0,Weather)
check(atHorizon.starVisibility==0 and atTwilight.starVisibility>0 and atTwilight.starVisibility<atNight.starVisibility,"time-of-day star visibility rises gradually sunset -> twilight -> night")
local farTime=atTwilight.starVisibility * BL.starScale()
for i=1,240 do targetAt(10) end
local nearTime=atTwilight.starVisibility * BL.starScale()
check(nearTime<farTime,"building proximity multiplies the same twilight visibility instead of overriding it")

print(("celestial clock/night/building fade: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
