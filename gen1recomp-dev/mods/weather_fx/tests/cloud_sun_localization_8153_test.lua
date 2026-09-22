-- Weather FX 8.1.53 cloud/sun localisation executable regression.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1; io.write("PASS ",name,"\n")
  else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function near(a,b,e) return math.abs((tonumber(a) or 0)-(tonumber(b) or 0)) <= (e or 1e-6) end

local cfg={celestial={enabled=true,latitude=35,axialTilt=23.43928,verticalOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=28}}
local Config={get=function() return cfg end}
local TOD={hour=12,elapsed=0,source="cycle"}
local modules={Config=Config,TimeOfDay=TOD,BuildingLight={starScale=function() return 1 end}}
local V={}
function V.require(name) if modules[name] then return modules[name] end; error("unexpected require "..tostring(name),0) end
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))(V); modules.CelestialSim=Sim
local Weather={id="CLEAR",ch={}}
function Weather.channel(k) return Weather.ch[k] or 0 end
local Engine=assert(loadfile(ROOT.."lib/CelestialEngine.lua"))(V); modules.CelestialEngine=Engine

-- Same regional cloud field, two very different player-space sun rays. The
-- visible sun may hide, but world direct light must not change map-wide.
Engine.observeCloudField(1.00,.52); local inGap=Engine.update(0,Weather)
Engine.observeCloudField(.045,.52); local underCloud=Engine.update(0,Weather)
check(near(inGap.sunLight,underCloud.sunLight,1e-9),"player-local cloud hole cannot change map-wide sunLight")
check(near(inGap.directLight,underCloud.directLight,1e-9),"player-local cloud ray cannot change map-wide directLight")
check((underCloud.sun.discTransmission or 1) < (inGap.sun.discTransmission or 0)*.12,"local cloud still hides solar disc")
check((underCloud.sun.alpha or 1) < (inGap.sun.alpha or 0)*.12,"local cloud still hides visible sun")

-- Regional coverage remains authoritative for the shared world baseline.
Engine.observeCloudField(.60,.12); local broken=Engine.update(0,Weather)
Engine.observeCloudField(.60,.88); local overcast=Engine.update(0,Weather)
check((overcast.sunLight or 1) < (broken.sunLight or 0)*.68,"regional cloud coverage lowers world sunlight")
check((overcast.cloudShadowStrength or 0) >= 0 and (broken.cloudShadowStrength or 0) >= 0,"regional states retain cloud-shadow authority")

-- Terrain pass stays bounded and emits real depth-tested world geometry from
-- visible cloud descriptors rather than a full-screen lighting overlay.
local map={def={width=40,height=30}}
modules.VoxelScene={groundAt=function(m,cx,cz) return 2+((cx+cz)%3) end}
local drawCalls,lastVerts=0,nil
love={graphics={
  newShader=function() return {send=function() end} end,
  newMesh=function(fmt,cap) local m={}; function m:setVertices(v,a,n) self.n=n; lastVerts=v end; function m:setDrawRange() end; return m end,
  setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,setColor=function() end,
  getBlendMode=function() return "alpha","alphamultiply" end,
  draw=function() drawCalls=drawCalls+1 end,
}}
Engine.observeCloudField(.62,.48); Engine.update(0,Weather)
local Light=assert(loadfile(ROOT.."lib/voxel_atmos/WorldCelestialLighting.lua"))(V)
local Voxel3D={vp={},beginEffect=function() return true end,endEffect=function() end}
local clouds={
  {cx=240,cy=90,cz=220,spanX=78,spanZ=52,fadeAlpha=1,angle=.72,kind=1},
  {cx=380,cy=84,cz=245,spanX=62,spanZ=44,fadeAlpha=.8,angle=-.46,kind=2},
}
local drew=Light.draw(Voxel3D,{},clouds,map,{})
local st=Light.status()
check(drew and drawCalls==1,"localized cloud terrain mask submits one bounded draw")
check(st.patches>0 and st.patches<=#clouds*4,"terrain mask is bounded to four macro lobes per cloud")
check(st.vertices==st.patches*6,"each localized terrain lobe is one six-vertex quad")
check(type(lastVerts)=="table" and #lastVerts>=6,"localized mask uploads terrain geometry")

io.write(string.format("cloud sun localisation 8.1.53: %d passed, %d failed\n",passed,failed))
os.exit(failed==0 and 0 or 1)
