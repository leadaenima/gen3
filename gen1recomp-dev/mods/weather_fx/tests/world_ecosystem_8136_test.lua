-- Weather FX 8.1.36 world-ecosystem / seasonal front / celestial reachability contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

-- ---------- storm front travel + remote charged clouds ----------
math.randomseed(8136)
local wind={x=1,z=0,strength=.55}
local Types={DEFAULT="CLEAR"}
local defs={CLEAR={id="CLEAR",ch={}},STORM={id="STORM",ch={rain=.85,strike=22,gust=.9,dim=.7}},RAIN_LIGHT={id="RAIN_LIGHT",ch={rain=.35}}}
function Types.get(id) return defs[id] or defs.CLEAR end
local mods={Types=Types,WindEngine={peek=function() return wind end},WeatherWorldSpace={epoch=function() return 1 end},Fronts={approachingWeather=function() return "STORM" end}}
local V={mod={save={set=function() end,get=function() return nil end}},require=function(n) if mods[n] then return mods[n] end error(n,0) end}
local S=assert(loadfile(ROOT.."lib/StormCells.lua"))(V)
for i=1,170 do S.update(.25,"MAP","CLEAR",0,0,1) end
local cells=S.cells();local c=cells[1]
check(c and c.source=="neighbor-front","clear local map can receive a real neighbouring incoming front")
local startDist=c and math.sqrt((c.x-c.targetX)^2+(c.z-c.targetZ)^2) or 0
wind.x,wind.z=-1,0 -- hostile reversal must bend, not push pre-arrival front away
for i=1,120 do S.update(.25,"MAP","CLEAR",0,0,1) end
local newDist=c and math.sqrt((c.x-c.targetX)^2+(c.z-c.targetZ)^2) or 1e9
check(c and newDist<startDist,"pre-arrival steering keeps storm moving toward the world/map despite adverse wind")
-- 8.1.41 front reachability is leading-edge/footprint based, not a center-distance
-- divided by the old fast translation speed.  Exercise the real lifecycle until
-- the physical footprint contacts the player and prove that contact happens
-- before the storm has entered weakening/dissipation.
local contactStage=nil
for i=1,4000 do
  S.update(.25,"MAP","CLEAR",0,0,1)
  if c and c.reachedTarget then contactStage=c._lifeStage;break end
end
check(contactStage=="growth" or contactStage=="mature","incoming front leading edge reaches the target corridor while still growth/mature")

-- Deterministic distant charged storm descriptor: developing cloud can be seen
-- before rain and a real remote strike is queued for delayed thunder.
local remote={id=77,weather="STORM",x=1100,z=0,rx=300,rz=260,age=12,life=240,_lifeStage="formation",charge=.55,flash=0,strikeSerial=0}
local D=assert(loadfile(ROOT.."lib/DistantWeather.lua"))({require=function(n) if n=="StormCells" then return {cells=function() return {remote} end} elseif n=="Types" then return Types end error(n,0) end})
D.update(.1,0,0);local items,n=D.items();local q=items[1]
check(n==1 and q and q.cloud>.05,"distant developing storm publishes cloud mass before the rain core arrives")
check(q and q.stage=="formation" and q.shaft<q.cloud,"developing distant front is not rendered as rain-only weather")
remote.age=100;remote._lifeStage="mature";remote.charge=1;remote.flash=1;remote.strikeSerial=1;remote.strikeX=1050;remote.strikeZ=20
D.update(.1,0,0);local ev=D.takeThunderEvents()
check(ev and #ev==1 and ev[1].distance>700,"electrically charged distant cloud queues thunder/lightning at true remote distance")
D.update(.1,0,0);check(D.takeThunderEvents()==nil,"same remote strike is consumed once rather than double-triggered")
check(D.stats().max==4,"far-field weather descriptor pool remains bounded")

-- ---------- seasonal climatology ----------
local Config={get=function() return {seasons={enabled=true},time={source="fixed"}} end}
local Settings={get=function(k) if k=="hemisphere" then return "northern" end end,is=function() return false end}
local TOD={source="fixed",elapsed=0}
local TypeSeason={channel=function(d,k) return d.ch and tonumber(d.ch[k]) or 0 end,get=function(id) return defs[id] end}
local SV={mod={save={get=function() return nil end,set=function() end},find=function() return nil end,log={info=function() end}},require=function(n) return ({Config=Config,Settings=Settings,TimeOfDay=TOD,Types=TypeSeason})[n] end}
local Seasons=assert(loadfile(ROOT.."lib/Seasons.lua"))(SV)
local seasonalDefs={
  SNOW_LIGHT={id="SNOW_LIGHT",frozen=true,ch={snow=.5}},BLIZZARD={id="BLIZZARD",frozen=true,ch={snow=1}},SLEET={id="SLEET",frozen=true,wet=true,ch={snow=.4,rain=.4}},THUNDERSNOW={id="THUNDERSNOW",frozen=true,ch={snow=.8,strike=10}},
  SUNNY={id="SUNNY",sunny=true,ch={}},HARSH_SUN={id="HARSH_SUN",sunny=true,ch={}},HEATWAVE={id="HEATWAVE",sunny=true,ch={}},RAIN_LIGHT={id="RAIN_LIGHT",wet=true,ch={rain=.4}},FOG={id="FOG",ch={fog=.6}}
}
TypeSeason.get=function(id) return seasonalDefs[id] end
Seasons._setForTest("SUMMER")
check(Seasons.weatherMultiplier("SNOW_LIGHT")==0 and Seasons.weatherMultiplier("BLIZZARD")==0 and Seasons.weatherMultiplier("SLEET")==0 and Seasons.weatherMultiplier("THUNDERSNOW")==0,"summer hard-gates snow/blizzard/sleet/thundersnow")
Seasons._setForTest("WINTER")
check(Seasons.weatherMultiplier("SUNNY")==0 and Seasons.weatherMultiplier("HARSH_SUN")==0 and Seasons.weatherMultiplier("HEATWAVE")==0,"winter hard-gates sunny/harsh-sun/heatwave")
Seasons._setForTest("SPRING");local springRain=Seasons.weatherMultiplier("RAIN_LIGHT")
Seasons._setForTest("AUTUMN");local autumnFog=Seasons.weatherMultiplier("FOG")
check(springRain>1.5 and autumnFog>1.5,"spring rain and autumn fog receive strong seasonal climatology bias")

-- ---------- celestial rare-event natural reachability ----------
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))({require=function(n) if n=="Config" then return {get=function() return {celestial={events=true,verticalOrbit=true,latitude=35}} end} elseif n=="TimeOfDay" then return {hour=22} end error(n,0) end})
local found={solar=false,lunar=false,super=false,harvest=false,blue=false,blood=false};local examples={}
for day=-2200,-1500,.25 do
  for _,h in ipairs({12,18,21,0}) do
    local s=Sim.sample(h,day);local e=s.events or {}
    if e.solarEclipse and s.sun.alpha>.01 then found.solar=true;examples.solar={day,h} end
    if e.lunarEclipse and s.moon.alpha>.01 then found.lunar=true;examples.lunar={day,h} end
    if e.supermoon and s.moon.alpha>.01 then found.super=true;examples.super={day,h} end
    if e.harvestMoon and s.moon.alpha>.01 then found.harvest=true;examples.harvest={day,h} end
    if e.blueMoon and s.moon.alpha>.01 then found.blue=true;examples.blue={day,h} end
    if e.bloodMoon and s.moon.alpha>.01 then found.blood=true;examples.blood={day,h} end
  end
  if found.solar and found.lunar and found.super and found.harvest and found.blue and found.blood then break end
end
check(found.solar,"solar eclipse is naturally reachable by the celestial calendar")
check(found.lunar and found.blood,"lunar eclipse/blood moon are naturally reachable and visible")
check(found.super,"supermoon is naturally reachable and visible")
check(found.harvest,"harvest moon is naturally reachable and visible")
check(found.blue,"blue moon is naturally reachable and visible")

-- Meteor family has deterministic qualification seams but still uses the same real renderer path.
local NS=assert(loadfile(ROOT.."lib/NightSky.lua"))({safeBind=function() return pcall end,require=function(n) if n=="TimeOfDay" then return {hour=22,isNight=function() return true end} end error(n,0) end})
NS._forceMeteorEvent("single");local p1=NS.celestialEventProof();NS._forceMeteorEvent("shower");local p2=NS.celestialEventProof();NS._forceMeteorEvent("fireball");local p3=NS.celestialEventProof()
local function has(t,k) for _,v in ipairs(t.active or {}) do if v==k then return true end end end
check(#(p1.active or {})>=1,"ordinary shooting-star renderer path can be forced for visual qualification")
check(#(p2.active or {})>=2,"meteor-shower renderer path can be forced for visual qualification")
check(has(p3,"fireball"),"fireball/bolide renderer path can be forced for visual qualification")

print(string.format("world ecosystem 8.1.36: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
