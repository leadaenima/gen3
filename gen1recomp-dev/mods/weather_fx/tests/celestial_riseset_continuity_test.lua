-- Celestial rise/set continuity proof.
-- This specifically protects against the 4.35.5 regressions where lunar phase
-- could place the moon near zenith at sunset and the oversized sun disc could
-- vanish while a visible portion was still above the horizon.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function dot(a,b) return a.dx*b.dx+a.dy*b.dy+a.dz*b.dz end
local function sep(a,b)
  local d=math.max(-1,math.min(1,dot(a,b)))
  return math.acos(d)
end

local cfg={celestial={enabled=true,latitude=35,axialTilt=23.43928,verticalOrbit=true,pairedMoonOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=28}}
local modules={Config={get=function() return cfg end},TimeOfDay={hour=12,elapsed=0,source="cycle"}}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))(V); modules.CelestialSim=Sim

local day=172
local ref=Sim.sample(12,day)
local rise,set=ref.sunrise,ref.sunset
local eps=0.01
local preSet=Sim.sample(set-eps,day)
local atSet=Sim.sample(set,day)
local postSet=Sim.sample(set+eps,day)
local preRise=Sim.sample((rise-eps)%24,day)
local atRise=Sim.sample(rise,day)
local postRise=Sim.sample(rise+eps,day)
local mid=Sim.sample(0,day)

check(atSet.sun.dx < -0.999 and math.abs(atSet.sun.dy)<0.02,"sun center reaches west horizon at sunset")
check(atSet.moon.dx > 0.999 and math.abs(atSet.moon.dy)<0.02,"moon begins rise on east horizon at sunset")
check(mid.moon.dy > 0.999 and math.abs(mid.moon.dx)<0.02,"moon crosses overhead around midnight")
check(atRise.sun.dx > 0.999 and math.abs(atRise.sun.dy)<0.02,"sun begins rise on east horizon")
check(atRise.moon.dx < -0.999 and math.abs(atRise.moon.dy)<0.02,"moon reaches west horizon at sunrise")

check(sep(preSet.sun,atSet.sun)<0.01 and sep(atSet.sun,postSet.sun)<0.01,"sun direction is continuous through sunset")
check(sep(preSet.moon,atSet.moon)<0.01 and sep(atSet.moon,postSet.moon)<0.01,"moon direction is continuous through sunset")
check(sep(preRise.sun,atRise.sun)<0.01 and sep(atRise.sun,postRise.sun)<0.01,"sun direction is continuous through sunrise")
check(sep(preRise.moon,atRise.moon)<0.01 and sep(atRise.moon,postRise.moon)<0.01,"moon direction is continuous through sunrise")

-- Rendered-disc horizon fraction: center on horizon = 50%, upper limb can still
-- be visible after center has set, and only the complete below-horizon disc is 0.
check(math.abs(Sim.discHorizonFraction(0,3.24)-0.5)<1e-6,"sun disc is half-visible when center is on horizon")
check(Sim.discHorizonFraction(-1.2,3.24)>0 and Sim.discHorizonFraction(-1.2,3.24)<0.5,"sun remains partially visible after center passes below horizon")
check(Sim.discHorizonFraction(-3.14,3.24)>0,"last sun limb remains visible just before full set")
check(Sim.discHorizonFraction(-3.34,3.24)==0,"sun disappears only after full disc passes below horizon")
check(Sim.discHorizonFraction(1.2,3.24)>0.5 and Sim.discHorizonFraction(1.2,3.24)<1,"sun brightens progressively after rise")

-- The composed body alpha must follow that limb visibility too, not just expose
-- the helper while still hard-cutting the live render state.
local justBelow=Sim.sample(set+0.12,day)
check(justBelow.sun.altitudeDeg<0 and justBelow.sun.alpha>0,"live sun alpha persists below center-horizon during gradual set")
local justBefore=Sim.sample((rise-0.12)%24,day)
check(justBefore.sun.altitudeDeg<0 and justBefore.sun.alpha>0,"live sun alpha begins before center-horizon during gradual rise")

-- The actual projection/render eligibility must not retain the old 0.02 alpha
-- cutoff, otherwise the mathematical fade would still pop off before the last
-- visible limb. Choose a sample that is below the horizon with alpha < 0.02.
local liveRef=Sim.sample(12)
local edgeHour,edgeState
for i=1,60 do
  local h=liveRef.sunset+i*0.005
  local q=Sim.sample(h)
  if q.sun.altitudeDeg<0 and q.sun.alpha>0 and q.sun.alpha<0.02 then edgeHour,edgeState=h,q; break end
end
check(edgeState~=nil,"test reaches faint last-limb sun state")
modules.CelestialEngine={state=function() return nil end}
local Bodies=assert(loadfile(ROOT.."lib/CelestialBodies.lua"))(V)
local projectedSun=edgeHour and select(1,Bodies.projectBoth(320,240,240,edgeHour)) or nil
check(projectedSun~=nil,"faint last-limb sun remains projection-eligible below old cutoff")

-- Escape hatch remains deliberate: phase-shifted moonrise can be opted back in.
cfg.celestial.pairedMoonOrbit=false
local phaseShifted=Sim.sample(set,day)
check(math.abs(phaseShifted.moon.dy-atSet.moon.dy)>0.05 or math.abs(phaseShifted.moon.dx-atSet.moon.dx)>0.05,"paired moon orbit house rule can be disabled explicitly")

print(("celestial rise/set continuity: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
