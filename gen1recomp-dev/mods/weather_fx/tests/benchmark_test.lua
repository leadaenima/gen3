-- Weather FX 4.35.24 in-game benchmark regression.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,msg) if ok then passed=passed+1 else failed=failed+1;print("FAIL "..msg) end end

local fakeTime=100
love={
  timer={getTime=function() return fakeTime end},
  graphics={
    getStats=function() return {drawcalls=900,drawcallsbatched=250,texturememory=256*1024*1024,images=100,canvases=8} end,
    getDimensions=function() return 1920,1080 end,
  }
}

local State={id="MIST",left=42,level=3,mode="AUTO",pinnedBy="none",elapsed=9,dirty=true,ch={rain=.1,fog=.2},softFrom="RAIN_LIGHT",softTo="MIST",softT=2,softDur=32,mapsTowardCommit=1,fresh=true,_gentleIntro=1.5,_sessionStart=false,_needOutdoorStart=false,lastMapId="ROUTE_1",_suppressPersist=false}
function State.setWeather(id,reason) State.id=id;State.pinnedBy=reason or State.pinnedBy;return true end
function State.settle() State.ch={};State.ch[State.id]=1 end
local TOD={pin=nil,tod="EVE",hour=18}
local Settings={presentMode=function() return "3d" end}
local Quality={describe=function() return "HIGH" end}
local Scene={now={mapId="ROUTE_1",outdoor=true,indoors=false}}
local Bridge={active=function() return true end}
local Atmos={benchmarkStats=function(out) out.rain=12000;out.snow=100000;out.hail=100;out.sand=200;out.debris=300;out.ash=400;out.groundSnow=900;out.footprints=100;return out end}
local SnowPack={stats=function() return 1500,120,1800,160 end}
local logs={}
local mod={log={info=function(_,fmt,...) logs[#logs+1]=string.format(fmt,...) end}}
local mods={WeatherState=State,TimeOfDay=TOD,Settings=Settings,Quality=Quality,Scene=Scene,VoxelAtmosBridge=Bridge,DramalessAtmos=Atmos,SnowPack=SnowPack}
local V={mod=mod,require=function(name) assert(mods[name],"unexpected require "..tostring(name));return mods[name] end}
local B=assert(loadfile(ROOT.."lib/Benchmark.lua"))(V)

local ok,msg=B.start("quick")
check(ok and B.active(),"quick benchmark starts")
check(msg:find("4 phases",1,true)~=nil,"quick benchmark announces deterministic phase count")
check(State.id=="CLEAR" and TOD.pin=="DAY","benchmark immediately applies first weather/time phase")

local seen={}
local iterations=0
while B.active() and iterations<5000 do
  iterations=iterations+1
  seen[State.id]=true
  B.beginUpdate();fakeTime=fakeTime+0.00035
  B.preUpdate(1/60);B.enforce();fakeTime=fakeTime+0.00065
  B.beginAtmos();fakeTime=fakeTime+0.00080;B.endAtmos()
  B.beginPresent();fakeTime=fakeTime+0.00020;B.endPresent()
  B.endUpdate(1/60)
  fakeTime=fakeTime+1/60
end
check(iterations<5000 and not B.active(),"quick benchmark finishes automatically")
check(seen.CLEAR and seen.GALE and seen.BLIZZARD and seen.PSYSTORM,"quick benchmark visits baseline, leaf, snow and lightning stress phases")
check(State.id=="MIST" and State.left==42 and State.level==3 and State.mode=="AUTO" and State.pinnedBy=="none","original WeatherState identity/mode/timer is restored")
check(State.softFrom=="RAIN_LIGHT" and State.softTo=="MIST" and State.softT==2 and State.softDur==32 and State.mapsTowardCommit==1,"original WeatherState transition internals are restored")
check(State._suppressPersist==false,"benchmark persistence suppression is restored")
check(math.abs((State.ch.rain or 0)-.1)<1e-9 and math.abs((State.ch.fog or 0)-.2)<1e-9,"original eased WeatherState channels are restored")
check(TOD.pin==nil,"original time-of-day pin is restored")

local r=B.last()
check(type(r)=="table" and #r.phases==4,"completed report contains all quick phases")
check(r.voxelActive==true and r.outdoor==true and r.mapId=="ROUTE_1","report records voxel/outdoor/map test context")
check(r.resolution[1]==1920 and r.resolution[2]==1080 and r.quality=="HIGH","report records resolution and active quality tier")
check(r.aggregate.avgFps>59 and r.aggregate.avgFps<61,"whole-frame average FPS derives from host dt")
check(r.aggregate.worstOnePct>59 and r.aggregate.worstOnePct<61,"1% low is calculated per phase")
check(r.aggregate.peakTextureMB>=255,"graphics telemetry records texture-memory proxy")
check(r.aggregate.peakDrawCalls>=900,"graphics telemetry records draw-call peak")
check(r.phases[2].peakRain==12000 and r.phases[2].peakSnow==100000,"3D particle telemetry is captured from live atmosphere bridge")
check(r.phases[3].peakSnowCells==1500 and r.phases[3].peakPackFootprints==120,"SnowPack cell/footprint telemetry is captured")
check(r.phases[1].avgUpdateMs>0 and r.phases[1].avgAtmosMs>0,"Weather FX update and 3D atmosphere timings are recorded")
check(type(r.rating)=="string" and #r.rating>0,"benchmark produces a performance classification")
check(B.summary():find("WXBENCH",1,true)~=nil,"last-result console summary is retained")
check(#logs>=5,"completed benchmark writes detailed per-phase results to mod log")

local ok2,msg2=B.start("nonsense")
check(ok2==false and msg2:find("quick or full",1,true)~=nil,"invalid benchmark mode fails clearly")
local ok3=B.start("quick")
check(ok3==true,"benchmark can be started again after completion")
local stopOk,stopMsg=B.stop()
check(stopOk and stopMsg:find("WXBENCH",1,true)~=nil,"manual stop restores state and returns summary")

print(("benchmark: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
