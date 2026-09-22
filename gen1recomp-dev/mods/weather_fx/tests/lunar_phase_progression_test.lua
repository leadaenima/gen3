-- 8.0.6 night-by-night lunar phase proof.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end end
local cfg={celestial={enabled=true,latitude=35,verticalOrbit=true,pairedMoonOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=15}}
local TOD={hour=22,elapsed=0,source="cycle",gameDays=0}
function TOD.gameDaySerial() return TOD.gameDays end
local modules={Config={get=function() return cfg end},TimeOfDay=TOD}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))(V); modules.CelestialSim=Sim
local names={}
for night=0,35 do TOD.gameDays=night+.75; TOD.hour=22; local p=Sim.sample(); names[#names+1]=p.moon.phaseName end
local seen={}; for _,n in ipairs(names) do seen[n]=true end
for _,n in ipairs({"NEW","WAXING_CRESCENT","FIRST_QUARTER","WAXING_GIBBOUS","FULL","WANING_GIBBOUS","LAST_QUARTER","WANING_CRESCENT"}) do check(seen[n],"cycle reaches "..n) end
TOD.gameDays=5+.75; TOD.hour=22; local eve=Sim.sample()
TOD.gameDays=6+.08; TOD.hour=2; local dawn=Sim.sample()
check(math.abs(eve.moon.ageDays-dawn.moon.ageDays)<1e-9 and eve.moon.phaseName==dawn.moon.phaseName,"phase is stable across one evening-to-morning night")
TOD.gameDays=6+.75; TOD.hour=22; local next=Sim.sample()
check(math.abs(((next.moon.ageDays-eve.moon.ageDays)%Sim.SYNODIC_MONTH)-1)<1e-9,"next night advances exactly one lunar day")
local function litFraction(phase,illum)
 local lit,total=0,0
 for iy=-80,80 do for ix=-80,80 do local x,y=ix/80,iy/80; if x*x+y*y<=1 then total=total+1; if Sim.moonPhaseLit(phase,illum,x,y) then lit=lit+1 end end end end
 return lit/total
end
check(litFraction(.25,.5)>.49 and litFraction(.25,.5)<.51,"first quarter is a true half moon")
check(litFraction(.75,.5)>.49 and litFraction(.75,.5)<.51,"last quarter is a true half moon")
check(litFraction(.125,(1-math.cos(.25*math.pi))/2)<.25,"waxing crescent is visibly crescent-shaped")
check(litFraction(.875,(1-math.cos(1.75*math.pi))/2)<.25,"waning crescent is visibly crescent-shaped")
local waxRight=Sim.moonPhaseLit(.125,.146,0.85,0); local waxLeft=Sim.moonPhaseLit(.125,.146,-.85,0)
local waneRight=Sim.moonPhaseLit(.875,.146,0.85,0); local waneLeft=Sim.moonPhaseLit(.875,.146,-.85,0)
check(waxRight and not waxLeft,"waxing crescent lights the right limb")
check(waneLeft and not waneRight,"waning crescent lights the left limb")
local new=Sim.sample(0,0); local full=Sim.sample(0,Sim.SYNODIC_MONTH/2)
check(new.moon.illumination<.02 and new.moon.alpha<.05,"ordinary new moon is essentially invisible")
check(full.moon.illumination>.98 and full.moon.alpha>.9,"full moon remains fully visible")
print(("lunar phase progression: %d passed, %d failed"):format(passed,failed)); os.exit(failed==0 and 0 or 1)
