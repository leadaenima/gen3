-- Natural sunset halo continuity proof.
-- The local solar halo must be a horizon-contact effect, never a broad
-- all-around low-sun glow with hard altitude thresholds.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function close(a,b,eps) return math.abs(a-b) <= (eps or 1e-6) end

local cfg={celestial={enabled=true,latitude=35,axialTilt=23.43928,verticalOrbit=true,pairedMoonOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=28}}
local modules={Config={get=function() return cfg end},TimeOfDay={hour=12,elapsed=0,source="cycle"}}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))(V); modules.CelestialSim=Sim

-- 8.1.15 reduces the authored 3D sun by 40%: 5.4 -> 3.24 degrees.
check(close(Sim.sunHorizonHalo(3.74,3.24),0),"halo is off before lower limb touches horizon")
check(close(Sim.sunHorizonHalo(3.24,3.24),0),"halo begins from exact zero at first horizon contact")
local h4=Sim.sunHorizonHalo(2.88,3.24)
local h2=Sim.sunHorizonHalo(1.44,3.24)
local h0=Sim.sunHorizonHalo(0.0,3.24)
local hm2=Sim.sunHorizonHalo(-1.44,3.24)
local hm4=Sim.sunHorizonHalo(-2.88,3.24)
check(h4>0 and h4<h2,"halo eases in after setting actually begins")
check(h2>0 and h2<h0,"halo strengthens continuously toward half-set")
check(close(h0,1,1e-6),"halo peaks smoothly at half-visible sun")
check(hm2>0 and hm2<h0,"halo eases down after center crosses horizon")
check(hm4>0 and hm4<hm2,"halo keeps fading with last visible limb")
check(close(Sim.sunHorizonHalo(-3.24,3.24),0),"halo reaches exact zero as last limb disappears")
check(close(Sim.sunHorizonHalo(-3.74,3.24),0),"halo stays off after full sunset")

-- No cliff near either endpoint: tiny limb changes produce tiny halo changes.
local onset=Sim.sunHorizonHalo(3.23,3.24)
local tail=Sim.sunHorizonHalo(-3.23,3.24)
check(onset>0 and onset<0.01,"first-contact halo starts extremely gently")
check(tail>0 and tail<0.01,"last-limb halo dies extremely gently")
check(math.abs(onset-tail)<0.001,"rise/set endpoint envelope is symmetric and continuous")

-- Live simulation publishes the same envelope on the sun body.
local day=172
local ref=Sim.sample(12,day)
local set=ref.sunset
local fullyClear,contact,fading,gone
for i=-100,100 do
  local q=Sim.sample(set+i*0.005,day)
  local f=q.sun.horizonFraction or 0; local halo=q.sun.haloStrength or 0
  if not fullyClear and f>=0.999 and halo<0.001 then fullyClear=q end
  if not contact and f<0.995 and f>0.52 and halo>0 then contact=q end
  if not fading and f<0.48 and f>0 and halo>0 then fading=q end
  if not gone and f==0 and halo==0 and i>0 then gone=q end
end
local half=Sim.sample(set,day)
check(fullyClear~=nil,"live halo stays off while full disc is clear")
check(contact~=nil,"live halo begins only after disc intersection")
check((half.sun.haloStrength or 0)>0.95,"live halo strongest around center-horizon")
check(fading~=nil and (fading.sun.haloStrength or 0)<(half.sun.haloStrength or 0),"live halo fades after half-set")
check(gone~=nil,"live halo is gone when whole disc is below horizon")

print(("sunset halo continuity: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
