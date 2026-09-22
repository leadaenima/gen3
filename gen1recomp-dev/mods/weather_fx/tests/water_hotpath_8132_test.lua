-- Weather FX 8.1.32 zero-quality-loss connected-water hot-path regression.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

local reqCount,sampleCount,translateCount,newMeshCount=0,0,0,0
love={graphics={newMesh=function() newMeshCount=newMeshCount+1;return {release=function() end} end}}
local V3={FORMAT={{"VertexPosition","float",3}}}
local Mat4={translate=function(x,y,z) translateCount=translateCount+1;return {1,0,0,x,0,1,0,y,0,0,1,z,0,0,0,1} end}
local Water={WAVE_TRAINS={{.1,0,1,.68},{0,.1,.7,.22},{-.1,0,-.4,.1}},WAVE_HEIGHT=5,
 WAVE_SWELL={.01,.01,.5,.28},WAVE_BEND={.01,.02,.3,.82},WAVE_FPS=10,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=3.5,WAVE_SLOPE_LEAN=1.3,
 _trainSource=function() return "structured" end,_waveTime=function() return 0 end,invalidate=function() end}
local bodies={}
for i=1,4 do bodies[i]={signature="b"..i,rects={{x0=(i-1)*32,z0=0,x1=i*32,z1=32}},cells={},area=4,loadBearing=false,tide=.2,wave=1.2,ice=0} end
local CW={observed=true,bodies=bodies,windX=.8,windZ=.6}
function CW.sample() sampleCount=sampleCount+1;return {windX=CW.windX,windZ=CW.windZ} end
local mods={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water}
local V={require=function(n) reqCount=reqCount+1;local m=mods[n];if not m then error(n,0) end;return m end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(V)
local original={{{}, {native=true}}}
local first=assert(R.prepare(original));local rows,models={},{}
for i,r in ipairs(first) do rows[i]=r;models[i]=r[3] end
for frame=1,200 do
  for i,b in ipairs(bodies) do b.tide=.2+frame*.0001+i*.00001 end
  local q,owned=R.prepare(original);assert(owned and #q==4)
end
check(reqCount==4,"steady water prepare resolves four host modules once, not once per frame")
check(sampleCount==0,"structured Weather FX water reads published wind directly without diagnostics-table allocation")
check(translateCount==4,"structured reflective water allocates one translation matrix per body, then reuses it")
local same=true;for i,r in ipairs(R._liquidDraws) do if r~=rows[i] or r[3]~=models[i] then same=false end end
check(same,"reflective water draw rows and matrices remain stable across steady frames")
local expected=bodies[1].tide-(R.currentWaveHeight or 0)*.5
check(math.abs((R._liquidDraws[1][3][8] or 0)-expected)<1e-9,"reused translation matrix still tracks changing tide and centered wave datum")
check(newMeshCount==4,"steady connected bodies do not rebuild cached surface meshes")
local before=reqCount;R.invalidate();local q,owned=R.prepare(original)
check(owned and q and #q==4 and reqCount==before+4,"invalidate clears dependency handles so hot handoff/reload re-resolves safely")

-- ConnectedWater's own per-tick dependencies should also resolve once.
local depReq=0
local deps={Settings={weatherFxWaterEnabled=function() return true end},WindEngine={peek=function() return {x=1,z=0,strength=1} end},CelestialSim={moonPhase=function() return .25 end},TimeOfDay={hour=12},Microclimate={peek=function() return {temperature=10} end}}
local WV={mod={hooks={wrap=function() end}},require=function(n) depReq=depReq+1;local m=deps[n];if not m then error(n,0) end;return m end}
local H=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))(WV)
H.bodies={{area=100,ice=0,temp=10,tide=0,wave=0,loadBearing=false,touchesBoundary=true,cells={{gx=0,gz=0}}}};H.bodyByCell["0:0"]=H.bodies[1];H.observed=true;H.observationAge=0
local state={channel=function() return 0 end,channels={}}
for i=1,200 do H.update(1/60,state,{id="SUMMER"});H.isLoadBearingAt(8,8) end
check(depReq==5,"hydrosphere update/settings dependencies resolve once and are reused")
check(H.bodies[1].wave>0 and H.bodies[1].ice==0,"dependency caching does not change summer liquid-water physics")

print(string.format("water hot path 8.1.32: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
