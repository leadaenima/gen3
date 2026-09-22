-- Ultimate celestial engine executable proof.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function approx(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-3) end

local cfg={celestial={enabled=true,latitude=35,axialTilt=23.43928,verticalOrbit=true},time={cycleMinutes=24},seasons={daysPerSeason=28}}
local Config={get=function() return cfg end}
local TOD={hour=12,elapsed=0,source="cycle"}
local starScale=1
local BuildingLight={starScale=function() return starScale end}
local modules={Config=Config,TimeOfDay=TOD,BuildingLight=BuildingLight}
local V={}
function V.require(name)
  if modules[name] then return modules[name] end
  error("unexpected require "..tostring(name),0)
end
local Sim=assert(loadfile(ROOT.."lib/CelestialSim.lua"))(V); modules.CelestialSim=Sim

local summer=Sim.sample(12,172)
local winter=Sim.sample(12,355)
check(summer.dayLength>winter.dayLength+3,"seasonal summer day longer than winter")
local rise=Sim.sample(summer.sunrise,172)
local noon=Sim.sample(12,172)
local set=Sim.sample(summer.sunset,172)
local midnight=Sim.sample(0,172)
check(math.abs(rise.sun.altitudeDeg)<1.0,"seasonal sunrise reaches horizon")
check(rise.sun.dx>.999 and math.abs(rise.sun.dy)<.02 and math.abs(rise.sun.dz)<1e-6,"sunrise is fixed east horizon in vertical world plane")
check(noon.sun.dy>.999 and math.abs(noon.sun.dx)<.02 and math.abs(noon.sun.dz)<1e-6,"solar noon is overhead, not circling around player")
check(set.sun.dx<-.999 and math.abs(set.sun.dy)<.02 and math.abs(set.sun.dz)<1e-6,"sunset is opposite west horizon in same vertical plane")
check(midnight.sun.dy<-.999 and math.abs(midnight.sun.dz)<1e-6,"midnight sun continues below the same vertical orbit plane")
check(noon.orbitMode=="VERTICAL_EAST_UP_WEST","default celestial orbit reports vertical East-Up-West mode")
check(noon.twilight=="DAY","noon classified DAY")
check(midnight.twilight=="NIGHT","midnight classified NIGHT")
-- Optional astronomy mode remains available as the explicit house-rule switch.
cfg.celestial.verticalOrbit=false
local summerAstr=Sim.sample(12,172); local winterAstr=Sim.sample(12,355)
check(summerAstr.sun.altitudeDeg>winterAstr.sun.altitudeDeg,"optional latitude-horizon orbit retains seasonal noon altitude")
cfg.celestial.verticalOrbit=true

local new=Sim.sample(0,0)
local full=Sim.sample(0,Sim.SYNODIC_MONTH/2)
check(new.moon.illumination<0.02 and new.moon.phaseName=="NEW","new moon phase/illumination")
check(full.moon.illumination>0.98 and full.moon.phaseName=="FULL","full moon phase/illumination")
check(full.moon.dy>.98 and math.abs(full.moon.dz)<1e-6,"full moon at midnight reaches overhead in the same vertical orbit plane")
local eclipse=Sim.sample(12,-0.5)
check(eclipse.eclipse.solar>0.9,"forced node-aligned new moon produces solar eclipse")
check(eclipse.eclipse.solarObscuration>0.5,"solar eclipse actually obscures direct sun")

local rot=Sim.starRotator(math.pi/3)
local x,y,z=rot(.3,.4,.8660254)
check(approx(math.sqrt(x*x+y*y+z*z),1,1e-4),"sidereal rotation preserves unit sphere")
local x2,y2,z2=rot(x,y,z)
check(math.abs(y2-y)>1e-4 or math.abs(x2-x)>1e-4,"celestial-pole rotation advances star position")

local Weather={id="CLEAR",ch={}}
function Weather.channel(k) return Weather.ch[k] or 0 end
modules.WeatherState=Weather
local Engine=assert(loadfile(ROOT.."lib/CelestialEngine.lua"))(V); modules.CelestialEngine=Engine
TOD.hour=12
local clear=Engine.update(0,Weather)
check(clear and clear.sunLight>0.5,"clear daytime produces strong direct solar light")
check(type(_G.__weather_fx)=="table" and type(_G.__weather_fx.celestial)=="table","celestial state published to companion mods")
check(_G.__weather_fx.celestial.moonPhase~=nil and _G.__weather_fx.celestial.dayFraction~=nil,"published lunar phase/day fraction for voxel water")

Weather.id="STORM"; Weather.ch={rain=1.4,fog=.4,veil=.3}
local storm=Engine.update(0,Weather)
check(storm.sunLight<clear.sunLight*.4,"storm clouds materially block sunlight")
check(storm.cloudShadowStrength>=0,"storm exposes cloud-shadow strength")
TOD.hour=0; Weather.id="CLEAR"; Weather.ch={}; starScale=1
local dark=Engine.update(0,Weather); local starsClear=dark.starVisibility
starScale=.45
local polluted=Engine.update(0,Weather)
check(approx(polluted.starVisibility,starsClear,1e-6),"building star dimming is not double-applied inside CelestialEngine")
check(polluted.lightPollution>dark.lightPollution,"building light pollution remains published separately")
check(polluted.milkyWayVisibility<dark.milkyWayVisibility,"light pollution suppresses Milky Way more strongly")
TOD.hour=12; starScale=1
local daySky=Engine.update(0,Weather)
check(daySky.starVisibility==0 and daySky.milkyWayVisibility==0,"deep sky is hard-off during DAY")
local currentSolar=Sim.sample(12)
TOD.hour=currentSolar.sunrise; local dawnHorizon=Engine.update(0,Weather)
TOD.hour=(currentSolar.sunrise-0.5)%24; local dawnTwilight=Engine.update(0,Weather)
TOD.hour=currentSolar.sunset; local duskHorizon=Engine.update(0,Weather)
TOD.hour=(currentSolar.sunset+0.5)%24; local duskTwilight=Engine.update(0,Weather)
check(dawnHorizon.starVisibility==0 and duskHorizon.starVisibility==0,"deep sky is zero while sun is on the dawn/dusk horizon")
check(dawnTwilight.starVisibility>0 and dawnTwilight.starVisibility<1,"stars fade down gradually before dawn")
check(duskTwilight.starVisibility>0 and duskTwilight.starVisibility<1,"stars fade up gradually after dusk")
check(dark.starVisibility>duskTwilight.starVisibility and dark.starVisibility>dawnTwilight.starVisibility,"deep night is brighter than twilight")

-- 8.2.8 cloud-gap optical authority: in 3D, the cloud bank is real geometry
-- drawn after the celestial vault. A coarse blocked player ray must therefore
-- never erase the entire sun/moon/star layer; geometry supplies per-pixel
-- occlusion and reveals the vault only through actual gaps. Keep the coarse ray
-- separately so camera optics (glare/god rays) still stop behind cloud bodies.
TOD.hour=12; Weather.id="CLEAR"; Weather.ch={}; Engine.observeCloudField(1,0)
local clearDisc=Engine.update(0,Weather)
Engine.observeCloudField(.05,.95)
local bankDisc=Engine.update(0,Weather)
check(bankDisc.geometryCloudOcclusion==true,"observed 3D cloud field selects geometry occlusion")
check(bankDisc.sun.alpha >= clearDisc.sun.alpha*.95,"3D cloud sample does not globally erase visible sun disc")
check((bankDisc.sun.cloudLineTransmission or 1) < .10,"blocked cloud ray remains available to stop direct camera optics")
TOD.hour=0; Engine.observeCloudField(1,0); local clearNight=Engine.update(0,Weather)
Engine.observeCloudField(.05,.95); local bankNight=Engine.update(0,Weather)
check(bankNight.starVisibility >= clearNight.starVisibility*.95,"3D cloud sample does not globally erase stars/constellations")
check(bankNight.moon.alpha >= clearNight.moon.alpha*.95 or clearNight.moon.alpha<0.01,"3D cloud sample does not globally erase moon disc")
Engine.observeCloudField(1,0)

-- Sunset colour must evolve across a broad interval rather than flip within a
-- narrow horizon band. Sample the rendered solar path at fine time steps.
local sunsetRef=Sim.sample(12,172).sunset
local cBefore=Sim.sample(sunsetRef-1.0,172).sun.color
local cHorizon=Sim.sample(sunsetRef,172).sun.color
check(cBefore[2] > cHorizon[2]+0.12 and cHorizon[1] > cHorizon[2],"sun warms gradually toward orange/red at horizon")
local maxJump=0
local prev=nil
for off=-1.2,0.40,0.05 do
  local c=Sim.sample(sunsetRef+off,172).sun.color
  if prev then
    local d=math.max(math.abs(c[1]-prev[1]),math.abs(c[2]-prev[2]),math.abs(c[3]-prev[3]))
    if d>maxJump then maxJump=d end
  end
  prev=c
end
check(maxJump<0.065,"sunset solar colour changes continuously without frame-like colour jumps")
local currentSunset=Sim.sample(12).sunset
TOD.hour=currentSunset-0.2; Weather.id="STORM"; Weather.ch={rain=1}
local sunsetCloud=Engine.update(0,Weather)
TOD.hour=12; local noonCloud=Engine.update(0,Weather)
check((sunsetCloud.cloudSunsetStrength or 0) > (noonCloud.cloudSunsetStrength or 0)+0.20,"low sun publishes strong warm-cloud sunset response")
Weather.id="CLEAR"; Weather.ch={}; Engine.observeCloudField(1,0)

-- Real terrain-conforming cloud shadow submission.
local map={def={width=40,height=30}}
local VoxelScene={groundAt=function(m,cx,cz) return 3+((cx+cz)%4) end}
modules.VoxelScene=VoxelScene
TOD.hour=12; starScale=1; Weather.id="CLEAR"; Weather.ch={}; Engine.update(0,Weather)
local drawCalls=0
love={graphics={
  newShader=function() return {send=function() end} end,
  newMesh=function(fmt,cap) local m={}; function m:setVertices(v,a,n) self.n=n end; function m:setDrawRange() end; return m end,
  setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,setColor=function() end,
  getBlendMode=function() return "alpha","alphamultiply" end,
  draw=function() drawCalls=drawCalls+1 end,
}}
local Light=assert(loadfile(ROOT.."lib/voxel_atmos/WorldCelestialLighting.lua"))(V)
local Voxel3D={vp={},beginEffect=function() return true end,endEffect=function() end}
local clouds={{cx=240,cy=90,cz=220,spanX=65,spanZ=50,fadeAlpha=1}}
-- Force a broken-cloud field, the case where moving cloud shadows are strongest.
Engine.observeCloudField(.52,.48); Engine.update(0,Weather)
local drew=Light.draw(Voxel3D,{},clouds,map,{})
local status=Light.status()
check(drew and drawCalls>0,"world cloud shadow reaches actual 3D draw submission")
check(status.patches>0 and status.vertices>=status.patches*6,"cloud shadow emits terrain world geometry")


-- Actual 3D moon-phase geometry proof. This drives the real CelestialBodies
-- mesh builder from the composed CelestialEngine state and verifies that the
-- illuminated portion changes, rather than merely carrying phase metadata.
modules.Quality={celestial=function() return {sunLayers=4} end}
local Bodies=assert(loadfile(ROOT.."lib/CelestialBodies.lua"))(V)
local blendSeen={}
love.graphics.setBlendMode=function(mode) blendSeen[#blendSeen+1]=mode end
love.graphics.newMesh=function(fmt,verts) return {release=function() end} end
love.graphics.setDepthMode=function() end; love.graphics.setShader=function() end; love.graphics.setColor=function() end
love.graphics.draw=function() drawCalls=drawCalls+1 end
local celestialVoxel={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,5,0},focus={0,5,1},far=360,beginEffect=function() return true end,endEffect=function() end}
local function moonState(phase,illum,alpha,solarE,lunarE)
  Engine._state={hour=0,
    sun={dx=0,dy=-1,dz=0,alpha=0,above=false,intensity=0,color={1,1,.9}},
    moon={dx=.35,dy=.82,dz=.45,alpha=alpha or 1,above=true,intensity=.2,color={.8,.85,1},phase=phase,illumination=illum,phaseName="TEST",solarEclipse=solarE or 0,lunarEclipse=lunarE or 0}}
  blendSeen={}; Bodies.drawWorld(celestialVoxel,nil); return Bodies.moonProof()
end
local pNew=moonState(0,0,1); local pQuarter=moonState(.25,.5,1); local pFull=moonState(.5,1,1)
check(pNew and pQuarter and pFull and pNew.lit < pQuarter.lit and pQuarter.lit < pFull.lit,"3D moon mesh visibly progresses new -> quarter -> full")
check(pFull.cells>0 and pFull.dark==0,"full moon 3D disc has all visible cells illuminated")
check(pNew.dark>pNew.lit,"new moon 3D disc is predominantly dark geometry")
check((pNew.darkAlpha or 1)<=.025,"ordinary unlit moon side is near-invisible instead of an old full-moon backing disc")
local pHidden=moonState(.5,1,.01)
check(pHidden.cells==0,"cloud/weather disc alpha can fully hide the 3D moon")
local pEclipse=moonState(0,0,1,1,0)
check(pEclipse.solarEclipse>0.9 and pEclipse.dark>0,"solar-eclipse moon builds an opaque dark silhouette sector")
check((pEclipse.darkAlpha or 0)>.90,"solar eclipse restores a strong dark lunar silhouette")
local sawAlpha=false; for _,m in ipairs(blendSeen) do if m=="alpha" then sawAlpha=true end end
check(sawAlpha,"3D moon is alpha-blended so it can silhouette the additive solar disc")

-- Light-pollution horizon glow remains live while deep-sky time visibility fades independently.
TOD.hour=0; starScale=1; Weather.id="CLEAR"; Weather.ch={}; local unpolluted=Engine.update(0,Weather); local bands0=Engine.skyBands(6)
starScale=.35; local pollutedNight=Engine.update(0,Weather); local bands1=Engine.skyBands(6)
local function lum(c) return (c[1]+c[2]+c[3])/3 end
check(lum(bands1[#bands1])>lum(bands0[#bands0]),"night light pollution creates a brighter low-horizon sky dome")
check((lum(bands1[#bands1])-lum(bands0[#bands0])) > (lum(bands1[1])-lum(bands0[1])),"light-pollution glow is concentrated near horizon, not whole sky")

print(("ultimate celestial engine: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
