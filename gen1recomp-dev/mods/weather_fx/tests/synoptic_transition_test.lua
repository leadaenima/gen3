-- 8.0.7 executable staged-weather behavior proof.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local Types=assert(loadfile(ROOT.."lib/Types.lua"))()
local V={}
function V.require(name)
  if name=="Types" then return Types end
  error("unexpected require "..tostring(name),0)
end
local T=assert(loadfile(ROOT.."lib/SynopticTransition.lua"))(V)

local dur,kind=T.begin("CLEAR","RAIN_HEAVY",3.2)
check(kind=="onset" and dur>=28,"dry-to-rain is a real synoptic onset")
local s=T.update(0,"CLEAR","RAIN_HEAVY",dur*.10,dur)
check(s.cloudU>0 and s.precipU==0 and s.stormU==0,"clouds begin before first rain")
s=T.update(0,"CLEAR","RAIN_HEAVY",dur*.50,dur)
local rainHalf=T.goal("rain",0,Types.channel(Types.get("RAIN_HEAVY"),"rain"))
check(s.cloudU>.98 and rainHalf>0 and s.stormU==0,"deck establishes before mature precipitation/convection")

-- A normal heavy shower developing into a thunderstorm keeps the established
-- rainfall while wind/cloud character changes before electrical activity.
dur,kind=T.begin("RAIN_HEAVY","STORM",3.2)
check(kind=="intensify","heavy-rain to storm classifies as intensification")
s=T.update(0,"RAIN_HEAVY","STORM",dur*.30,dur)
local strikeEarly=T.goal("strike",0,Types.channel(Types.get("STORM"),"strike"))
check(s.cloudU>0 and s.windU>0 and strikeEarly<0.001,"storm cloud/wind can build before lightning charge")
s=T.update(0,"RAIN_HEAVY","STORM",dur*.80,dur)
local strikeLate=T.goal("strike",0,Types.channel(Types.get("STORM"),"strike"))
check(strikeLate>0,"lightning arrives later in the developing storm")

-- Clearing is deliberately asymmetric: rain can stop while broken cloud remains,
-- allowing the sun/sky to return through an opening instead of one hard swap.
dur,kind=T.begin("RAIN_HEAVY","CLEAR",3.2)
check(kind=="clearing","rain-to-clear classifies as clearing")
s=T.update(0,"RAIN_HEAVY","CLEAR",dur*.75,dur)
local rainLate=T.goal("rain",Types.channel(Types.get("RAIN_HEAVY"),"rain"),0)
check(rainLate<0.001 and s.cloudU>0 and s.cloudU<1,"rain can finish before the cloud deck fully parts")

-- Cross-family changes overlap only a bounded amount; no 2x precipitation spike.
dur,kind=T.begin("SNOW_LIGHT","RAIN_LIGHT",3.2)
check(kind=="phase_change","snow-to-rain uses phase-change handoff")
s=T.update(0,"SNOW_LIGHT","RAIN_LIGHT",dur*.50,dur)
local snow=T.goal("snow",Types.channel(Types.get("SNOW_LIGHT"),"snow"),0)
local rain=T.goal("rain",0,Types.channel(Types.get("RAIN_LIGHT"),"rain"))
check(snow>0 and rain>0,"phase change has a brief physical overlap instead of a one-frame swap")
check(snow<=Types.channel(Types.get("SNOW_LIGHT"),"snow")*1.06+1e-6 and rain<=Types.channel(Types.get("RAIN_LIGHT"),"rain")*1.06+1e-6,
      "phase overlap remains bounded")

T.reset()
check(not T.active(),"planner reset fully ends handoff")
print(("synoptic transition behavior: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
