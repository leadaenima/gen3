-- Celestial presentation-clock smoothing + monotonic correction proof (4.35.13).
-- Protects against coarse host clock ticks visibly teleporting the sun/moon.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function hdelta(a,b) return ((a-b+12)%24)-12 end

local cfg={celestial={enabled=true,motionSmoothing=true},time={cycleMinutes=24}}
local tod={hour=18.0,source="voxel",pin=nil}
local modules={
  Config={get=function() return cfg end},
  TimeOfDay=tod,
}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local E=assert(loadfile(ROOT.."lib/CelestialEngine.lua"))(V)

-- First sample establishes the presentation clock exactly.
E.time=0
local h=E.presentationHour(18.0,1/60)
check(math.abs(h-18.0)<1e-9,"initial presentation clock matches authority")

-- A coarse normal host tick is eased, never applied as a one-frame teleport.
E.time=0.10
local h1=E.presentationHour(18.10,1/60)
check(h1>18.0 and h1<18.10,"small host tick is interpolated instead of snapped")
local firstStep=math.abs(hdelta(h1,18.0))
check(firstStep<0.05,"first visible motion step is bounded")

-- While the raw host sample is held, learned clock velocity keeps presentation
-- moving continuously rather than freezing until the next raw tick.
local prev=h1
local movedFrames=0
for i=1,12 do
  E.time=0.10+i/60
  local hn=E.presentationHour(18.10,1/60)
  local d=hdelta(hn,prev)
  if math.abs(d)>1e-6 then movedFrames=movedFrames+1 end
  check(math.abs(d)<0.05,"inter-frame celestial motion remains smooth #"..i)
  prev=hn
end
check(movedFrames>=10,"presentation clock coasts continuously between host ticks")

-- Regression: the smoothed presentation may temporarily be ahead of a coarse
-- raw host sample. Reconciliation is allowed to reduce forward speed, but it
-- must never pull the celestial rig backward for a frame. That backward pull
-- was visible as a shadow nudge opposite its travel immediately before a step.
E._presentHour=18.05; E._clockRawHour=18.00; E._clockRawChangedAt=E.time; E._clockVelocity=0.01
E._clockSourceKey="voxel|"
local beforeForward=E._presentHour
E.time=E.time+1/60
local hm=E.presentationHour(18.00,1/60)
check(hdelta(hm,beforeForward)>=-1e-12,"forward clock correction never reverses presentation")
check(hdelta(hm,beforeForward)>0,"forward correction retains micro forward travel")

-- The same contract is symmetric if an external/debug clock genuinely runs
-- backward: correction may slow reverse travel but cannot twitch forward.
E._presentHour=17.95; E._clockRawHour=18.00; E._clockRawChangedAt=E.time; E._clockVelocity=-0.01
E._clockSourceKey="voxel|"
local beforeReverse=E._presentHour
E.time=E.time+1/60
local hr=E.presentationHour(18.00,1/60)
check(hdelta(hr,beforeReverse)<=1e-12,"reverse clock correction never twitches forward")

-- Midnight wrap uses shortest circular time distance, not a 24-hour reverse jump.
E._presentHour=23.98; E._clockRawHour=23.98; E._clockRawChangedAt=E.time; E._clockVelocity=0
E.time=E.time+0.10
local hw=E.presentationHour(0.02,1/60)
check(math.abs(hdelta(hw,23.98))<0.05,"midnight wrap remains a small forward movement")

-- Intentional large jumps remain immediate so changing a time mode/save/debug pin
-- does not spend seconds flying the bodies across the sky.
E.time=E.time+0.10
local hj=E.presentationHour(5.0,1/60)
check(math.abs(hdelta(hj,5.0))<1e-9,"multi-hour intentional jump snaps immediately")

tod.pin="NITE"; tod.source="pinned"
E.time=E.time+1/60
local hp=E.presentationHour(1.0,1/60)
check(math.abs(hp-1.0)<1e-9,"explicit time pin remains immediate")

-- Config escape hatch is live, not inert.
tod.pin=nil; tod.source="voxel"; cfg.celestial.motionSmoothing=false
E.time=E.time+1/60
local hoff=E.presentationHour(2.0,1/60)
check(math.abs(hoff-2.0)<1e-9,"motion smoothing config OFF follows raw clock immediately")

print(("celestial motion smoothing: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
