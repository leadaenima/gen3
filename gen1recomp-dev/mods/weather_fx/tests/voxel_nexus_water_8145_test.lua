-- Weather FX 8.1.45: Voxel Nexus exclusive water ownership + far VOID fast path.
-- Regressions covered:
--   1) Nexus WaterEngine adds a second model-space tide inside Water.draw,
--      desynchronising VoxelScene's curved depth prepass from its reflective pass.
--   2) The synthetic 32K VOID horizon used to enter a second FULL water pass,
--      forcing another framebuffer/depth copy + SSR march before near water.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

local function nexusWater()
  return {
    WAVE_TRAINS={{.150,.062,1.60,.60},{.058,.132,-1.05,.29},{-.041,.033,.55,.11}},
    WAVE_HEIGHT=5,WAVE_SWELL={.0325,.0134,.55,.35},WAVE_BEND={-.0138,.0333,.35,1.10},
    WAVE_FPS=12,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=3.5,WAVE_SLOPE_LEAN=1.5,
    _waveTime=function() return 2 end,_trainSource=function() return "structured" end,
    invalidate=function() end,begin=function() return true end,draw=function() end,finish=function() end,
  }
end

local captured=nil
local CWCap={setVoxelWaterHost=function(info) captured=info end}
local Vroot={mod={},require=function(n) if n=="ConnectedWater" then return CWCap end error(n,0) end}
local Atmos=assert(loadfile(ROOT.."lib/DramalessAtmos.lua"))(Vroot)
local W=nexusWater()
local nativeTide=function() return 1.75 end
local engine={tideOffset=nativeTide}
local U={RANGE=32768,draw=function() return true end}
local nxLib={realisticWorld={WaterEngine=engine},require=function(n)
  if n=="WorldUnderlay" then return U elseif n=="Water" then return W end error(n,0)
end}
local caps=Atmos._publishWaterHostCaps("BATTLE_ART_VOXEL_FORK",nxLib,{drawWater=function() end})
check(caps.voxelNexusWater==true and caps.publicBattleArtWater==false,"Voxel Nexus is fingerprinted by structured Water + Nexus-only WaterEngine tide seam")
check(caps.hostWaterModelTide==true,"Voxel Nexus bundled WaterEngine model-space tide seam is detected")
check(captured and captured.voxelNexusWater==true and captured.hostWaterModelTide==true,"Nexus water capabilities reach ConnectedWater")

-- Exact tide ownership transaction: zero only while owned, then byte-for-byte
-- function identity returns. This is the curved-prepass/reflection alignment fix.
Atmos._hostLib=nxLib
local on=Atmos._suppressHostWaterModelTide(true)
check(on==true and engine.tideOffset()==0,"Weather FX ownership neutralizes only the additive Nexus model-space tide")
local off=Atmos._suppressHostWaterModelTide(false)
check(off==true and engine.tideOffset==nativeTide and engine.tideOffset()==1.75,"ORIGINAL/restoration returns the exact native Nexus tide function")

-- Hot-reload/engine swap must not restore the first engine's function into a new one.
local tide2=function() return -.625 end
local engine2={tideOffset=tide2};nxLib.realisticWorld.WaterEngine=engine2
Atmos._suppressHostWaterModelTide(true);local hotZero=(engine2.tideOffset()==0)
Atmos._suppressHostWaterModelTide(false)
check(hotZero and engine2.tideOffset==tide2 and engine2.tideOffset()==-.625,"Nexus WaterEngine hot-swap captures/restores the new tide seam independently")

-- Hydrosphere retains the Nexus discriminator.
local CWa=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))({mod={},require=function() error("optional") end})
CWa.setVoxelWaterHost(caps)
local q=CWa.voxelWaterHost()
check(q.voxelNexusWater==true and q.hostWaterModelTide==true,"ConnectedWater retains Nexus renderer + host-tide ownership flags")

-- Build one finite VOID handoff plus the synthetic outer ocean. The outer fast
-- 8.1.46 supersedes the ordinary-scene draw with Nexus SKY-only material;
-- it must still avoid Voxel3D.beginWater / framebuffer-copy ownership.
local drawN,waterBeginN,waterDrawN,depthBeginN,endWaterN=0,0,0,0,0
local lastSkyOnly=nil
love={timer={getTime=function() return 2 end},image={newImageData=function() return {setPixel=function() end} end},graphics={
  newImage=function() return {setFilter=function() end,setWrap=function() end,release=function() end} end,
  newMesh=function(fmt,data,mode,usage)
    local m={mode=mode,usage=usage,current=type(data)=="table" and data or {}}
    function m:setTexture() end;function m:setVertexMap(v) self.map=v end
    function m:setVertices(r,s,n) self.current={};for i=1,(n or #r) do self.current[i]=r[i] end end
    function m:setDrawRange(a,n) self.range=n end;function m:release() end
    return m
  end,
}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},
  draw=function() drawN=drawN+1 end,
  size=function() return 1280,720 end,depthReadable=function() return true end,
  beginWater=function() depthBeginN=depthBeginN+1;return {},{} end,
  endWater=function() endWaterN=endWaterN+1 end,
  vp={},eye={0,0,0},cell=1,fovY=1,skyEdge=.4,lookFlat={0,0,-1},descent=.4}
local Mat4={translate=function(x,y,z) return {x=x,y=y,z=z} end}
local body={id=-1,signature="nexus-void",rects={{x0=-96,z0=-96,x1=224,z1=0}},cells={},area=120,
  loadBearing=false,tide=0,wave=1.0,ice=0,kind="SEA",rapidness=0,flowX=1,flowZ=0,visualOnly=true,voidWater=true}
for z=-6,-1 do for x=-6,13 do body.cells[#body.cells+1]={gx=x,gz=z} end end
local outer={id=-2,signature="nexus-outer",outerSea=true,visualOnly=true,voidWater=true,kind="SEA",loadBearing=false,
  tide=0,wave=1.0,range=32768,innerRing=96,mapWidth=128,mapHeight=112,cx=64,cz=56,
  holes={{x0=-96,z0=-96,x1=224,z1=208,inner=true}},area=0,touchesBoundary=true}
local CWr={observed=true,bodies={},renderBodies={body},outerSea=outer,windX=1,windZ=.1,
  voxelWaterHost=function() return caps end,rippleState=function() return {} end}
local HostWater=nexusWater();HostWater.enabled=function() return true end
HostWater.begin=function(ctx,skyOnly) waterBeginN=waterBeginN+1;lastSkyOnly=skyOnly and true or false;return true end
HostWater.draw=function() waterDrawN=waterDrawN+1 end
local modules={ConnectedWater=CWr,Voxel3D=V3,Mat4=Mat4,Water=HostWater,VoxelGrid={enabled=function() return true end}}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))({require=function(n) local m=modules[n];if m then return m end error(n,0) end})
local repl,owned=R.prepare({{{},{},{}}})
check(owned==true and repl and #repl==1 and #R.outerDraws()==1,"Nexus preparation owns finite VOID handoff and one separate outer ocean")
check(HostWater.WAVE_HEIGHT==0,"Nexus native geometric relief is zeroed after Weather FX physical mesh ownership")
local beforeDraw,beforeBegin,beforeWater,beforeDepth=drawN,waterBeginN,waterDrawN,depthBeginN
local fast=R.drawOuterFast();local stats=R.outerSeaStats()
check(fast==true and drawN==beforeDraw,"far 32K VOID ocean no longer uses mismatched ordinary scene-water material")
check(waterBeginN==beforeBegin+1 and waterDrawN==beforeWater+1 and lastSkyOnly==true,"far VOID fast path uses Nexus SKY-only water material for optical continuity")
check(depthBeginN==beforeDepth,"far VOID SKY-only path performs no beginWater framebuffer/depth copy")
check(stats.fastDraws==1 and stats.skyDraws==1,"far VOID matched-material fast-path execution is observable for regression/performance audit")

-- Static ownership contract: fast path is Nexus-only and reflective fallback is
-- still present for other hosts/failure. 8.1.46 supersedes the 8.1.45 ordinary
-- scene-shader optimization with Nexus SKY-only water material to keep one look.
local src=assert(io.open(ROOT.."lib/DramalessAtmos.lua","rb")):read("*a")
check(src:find("hostCaps.voxelNexusWater",1,true)~=nil and src:find("CW3.drawOuterFast",1,true)~=nil,"bridge gates far-ocean fast path specifically on Voxel Nexus")
check(src:find("origWater(outer",1,true)~=nil,"non-Nexus/fast-path failure retains reflective outer-water fallback")
check(src:find("suppressHostWaterModelTide",1,true)~=nil,"bridge contains explicit reversible Nexus model-tide ownership seam")

print(string.format("Voxel Nexus water 8.1.45: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
