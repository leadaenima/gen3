local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name) end end
local daytime="on"
local cfg={ time={ source="fixed", fixedPhase="NITE", grade=true, gradeStrength=1, indoors=0.55, cycleMinutes=24, publishTod=true } }
local Config={get=function() return cfg end}
local Settings={get=function(key) if key=="daytime" then return daytime end if key=="indoors" then return "tint" end end}
local hostDayNight=nil
local Interop={dayNight=function() return hostDayNight, 'DRAMALESS_SHAPE' end}
local V={mod={}}
function V.require(name)
  if name=="Config" then return Config end
  if name=="Interop" then return Interop end
  if name=="Settings" then return Settings end
  if name=="BuildingLight" then return {nightAmbientScale=function() return 1 end} end
  error("unexpected require "..tostring(name))
end
local TOD=assert(loadfile("lib/TimeOfDay.lua"))(V)
TOD.update(0.1)
check(TOD.source=="fixed" and TOD.tod=="NITE", "TIME OF DAY ON uses configured clock source")
check(TOD.grade(false)~=nil, "TIME OF DAY ON permits grade")
check(TOD.worldTod("DAY")=="NITE", "world.tod publishes Weather FX live phase while enabled")
cfg.time.publishTod=false
check(TOD.worldTod("MORN")=="MORN", "publishTod=false passes host world.tod through")
cfg.time.publishTod=true
daytime="off"
TOD.update(0.1)
check(TOD.source=="off" and TOD.tod=="DAY" and TOD.hour==13, "TIME OF DAY OFF neutralizes Weather FX clock")
check(TOD.grade(false)==nil, "TIME OF DAY OFF disables Weather FX grade")
check(TOD.worldTod("NITE")=="NITE", "TIME OF DAY OFF does not overwrite host world.tod")
-- With a supported host, OFF is passive rather than a frozen-noon override:
-- Weather FX observes the host hour only so celestial placement stays aligned.
hostDayNight={time=function() return 21.25 end}
TOD.setHostOwnsClock(false) -- reset the lazy host probe
TOD.update(0.1)
check(TOD.source=="host-passive" and math.abs(TOD.hour-21.25)<0.0001,
  "TIME OF DAY OFF passively follows supported host hour")
check(TOD.grade(false)==nil and TOD.worldTod("EVE")=="EVE",
  "TIME OF DAY OFF host-passive path still leaves grade/world.tod to host")
hostDayNight=nil
TOD.setHostOwnsClock(false)
daytime="on"
TOD.update(0.1)
check(TOD.source=="fixed" and TOD.tod=="NITE", "TIME OF DAY ON restores configured source without config rewrite")
check(cfg.time.source=="fixed", "menu toggle never mutates configured time source")
TOD.setHostOwnsClock(true)
check(TOD._hostOwnsGrade==true, "host clock owns legacy screen grade without disabling astronomy")
check(TOD.worldTod("EVE")=="NITE", "host clock does not disable Weather FX celestial phase publication")
check(TOD.grade(false)==nil, "host-owned 3D lighting suppresses duplicate Weather FX screen grade")
check(cfg.time.source=="fixed", "host clock adapter never rewrites configured time source")
TOD.setHostOwnsClock(false)
cfg.time.source="fixed"
TOD.update(0.1)
check(TOD.worldTod("DAY")=="NITE", "world.tod ownership resumes after host stand-down")
print(("time-of-day setting: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
