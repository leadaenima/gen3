-- Weather FX 8.1.39 universal voxel VOID-water ownership contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

local TileRenderer={voidFill="water"}
package.loaded["src.render.TileRenderer"]=TileRenderer
package.preload["src.render.TileRenderer"]=function() return TileRenderer end
-- This is deliberately Gen2-shaped: no tileset and no Gen1 overworld marker.
local Map={isOutdoor=function(def)
  local e=tostring(def and def.environment or ""):upper()
  if e~="" then return e=="ROUTE" or e=="TOWN" or e=="OUTDOOR" or e=="CITY" end
  return tostring(def and def.tileset or ""):upper()=="OVERWORLD"
end}
package.loaded["src.world.Map"]=Map
package.preload["src.world.Map"]=function() return Map end
local deps={
  Settings={weatherFxWaterEnabled=function() return true end},
  WindEngine={peek=function() return {x=1,z=.2,strength=.6} end},
  CelestialSim={moonPhase=function() return .25 end},
  TimeOfDay={hour=12},Microclimate={peek=function() return {temperature=12} end},
}
local Vroot={mod={hooks={wrap=function() end}},require=function(n) local m=deps[n];if m then return m end error(n,0) end}
local H=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))(Vroot)
local function mkMap(id,env)
  local m={id=id,def={id=id,width=8,height=7,environment=env}}
  function m:isWaterCell() return false end
  return m
end
local state={map=mkMap("GOLD_ROUTE","ROUTE"),neighbors={},player={cellX=2,cellY=2},channels={rain=0,snow=0}}
check(H._voidWaterMode(state)==true,"Gen2 ROUTE with VOID FILL WATER is recognized without a Gen1 tileset")
check(H.observeVoxel(state)==true and H.outerSea and H.outerSea.outerSea,"Gen2 route publishes Weather FX finite + outer VOID water")
check(H.outerSea.innerRing==96,"shared Dramatic-lineage VOID apron defaults to exact 96px")
state.map=mkMap("GOLD_HOUSE","INDOOR");H.observeVoxel(state)
check(H.outerSea==nil and #H.voidBodies==0,"Gen2 indoor map never receives synthetic outdoor ocean")
state.map=mkMap("GOLD_ROUTE","ROUTE")

local hosts={
  {id="DRAMATIC_SHAPE",outerRange=32768,voidRingWorld=96,drawWater=true},
  {id="DRAMALESS_SHAPE",outerRange=32768,voidRingWorld=96,drawWater=true},
  {id="potato_voxel",outerRange=32768,voidRingWorld=96,drawWater=true},
  {id="POTATO_VOXEL",outerRange=32768,voidRingWorld=96,drawWater=true},
  {id="PotatoVoxel",outerRange=32768,voidRingWorld=96,drawWater=true},
  {id="BATTLE_ART_VOXEL_FORK",outerRange=32768,voidRingWorld=96,drawWater=true,worldUnderlay=true},
  {id="STADIUM2_OVERWORLD_MODELS",outerRange=32768,voidRingWorld=96,drawWater=false},
}
for _,cap in ipairs(hosts) do
  H.setVoxelWaterHost(cap);H.observeVoxel(state)
  local c=H.voxelWaterHost()
  check(H.outerSea and H.outerSea.range==cap.outerRange and H.outerSea.innerRing==cap.voidRingWorld,
    cap.id.." consumes shared Weather FX VOID-ocean range/ring capability")
  check(c.id==cap.id and c.drawWater==cap.drawWater,cap.id.." capability identity survives into hydrosphere authority")
end
-- Prove capability values are live rather than decorative constants.
H.setVoxelWaterHost({id="TEST_WIDE_HOST",outerRange=24576,voidRingWorld=128,drawWater=false});H.observeVoxel(state)
check(H.outerSea.range==24576 and H.outerSea.innerRing==128,"host-published outer range/ring actually changes generated VOID sea")

-- Restore the common 96px host shape for renderer fallback qualification.
H.setVoxelWaterHost({id="STADIUM2_OVERWORLD_MODELS",outerRange=32768,voidRingWorld=96,drawWater=false});H.observeVoxel(state)
local draws=0
love={timer={getTime=function() return 2 end},image={newImageData=function() return {setPixel=function() end} end},graphics={
  newImage=function() return {setFilter=function() end,setWrap=function() end,getDimensions=function() return 64,64 end,release=function() end} end,
  newMesh=function(fmt,data,mode,usage)
    local m={};function m:setTexture() end;function m:setVertexMap() end;function m:setVertices() end;function m:setDrawRange() end;function m:release() end;return m
  end,
}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},curveX=0,curveZ=0,curveK=0,
  vp={},eye={},cell=16,fovY=1,skyEdge=.4,lookFlat={1,0},descent=0,draw=function() draws=draws+1 end,size=function() return 640,480 end}
local Mat4={identity=function() return {} end,translate=function(x,y,z) return {1,0,0,x,0,1,0,y,0,0,1,z,0,0,0,1} end}
local Water={WAVE_TRAINS={{.08,.02,1,.46}},WAVE_HEIGHT=2,WAVE_FPS=30,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=4,WAVE_SLOPE_LEAN=1,
  _waveTime=function() return 2 end,_trainSource=function() return "structured" end,invalidate=function() end}
local mods={ConnectedWater=H,Voxel3D=V3,Mat4=Mat4,Water=Water}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))({require=function(n) local m=mods[n];if m then return m end error(n,0) end})
local repl,owned=R.prepare({{{},{}}})
check(owned and #R.outerDraws()==1 and #R.voidDraws()==1,"renderer isolates outer + finite VOID rows independently of authored water")
check(R.drawStandaloneVoid(nil)==true and draws==2,"host without drawWater still receives Weather FX outer + finite VOID water exactly once")

local src=assert(io.open(ROOT.."lib/DramalessAtmos.lua","rb")):read("*a")
for _,id in ipairs({"DRAMATIC_SHAPE","DRAMALESS_SHAPE","potato_voxel","POTATO_VOXEL","PotatoVoxel","BATTLE_ART_VOXEL_FORK","STADIUM2_OVERWORLD_MODELS"}) do
  check(src:find('"'..id..'"',1,true)~=nil,"shared bridge explicitly recognizes "..id)
end
check(src:find("publishWaterHostCaps",1,true)~=nil and src:find("WorldUnderlay",1,true)~=nil,"bridge capability-probes optional host underlay instead of hardcoding Voxel Nexus")
check(src:find("drawStandaloneVoid",1,true)~=nil and src:find("not Atmos._wxWaterDrawn",1,true)~=nil,"shared endScene fallback covers voxel hosts without a drawWater seam")
check(src:find("return origWater(draws,cast,...)",1,true)~=nil,"WATER STYLE ORIGINAL / failed ownership preserves native host water fail-open")

print(string.format("universal voxel void water 8.1.39: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
