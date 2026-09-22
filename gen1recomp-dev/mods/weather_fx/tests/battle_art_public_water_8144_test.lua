-- Weather FX 8.1.44/8.1.91: public Battle Art water ownership.
-- Public Battle Art and Voxel Nexus share BATTLE_ART_VOXEL_FORK. Current Battle
-- Art also exports _trainSource, so lineage must be proven by the Nexus-only
-- realisticWorld.WaterEngine tide seam rather than that helper.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

-- Structured public API relevant to ownership. Older public Battle Art omitted
-- _trainSource; current public Battle Art exports it. Test both shapes because
-- neither one by itself is a Nexus discriminator anymore.
local function publicWater()
  return {
    WAVE_TRAINS={{.150,.062,1.60,.60},{.058,.132,-1.05,.29},{-.041,.033,.55,.11}},
    WAVE_HEIGHT=5,WAVE_SWELL={.0325,.0134,.55,.35},WAVE_BEND={-.0138,.0333,.35,1.10},
    WAVE_FPS=12,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=3.5,WAVE_SLOPE_LEAN=1.5,
    _waveTime=function() return 1.25 end,invalidate=function() end,
    begin=function() return true end,draw=function() end,finish=function() end,
  }
end
local function currentPublicWater()
  local w=publicWater();w._trainSource=function() return "structured" end;return w
end

local captured=nil
local CWCap={setVoxelWaterHost=function(info) captured=info end}
local Vroot={mod={},require=function(n) if n=="ConnectedWater" then return CWCap end error(n,0) end}
local Atmos=assert(loadfile(ROOT.."lib/DramalessAtmos.lua"))(Vroot)
local U={RANGE=32768,draw=function() return true end}
local pubW=publicWater()
local pubLib={require=function(n) if n=="WorldUnderlay" then return U elseif n=="Water" then return pubW end error(n,0) end}
local caps=Atmos._publishWaterHostCaps("BATTLE_ART_VOXEL_FORK",pubLib,{drawWater=function() end})
check(caps.publicBattleArtWater==true,"public Battle Art 1.10.1 water API is fingerprinted independently of shared mod id")
check(caps.drawWater==true and caps.worldUnderlay==true and caps.outerRange==32768,"public Battle Art publishes drawWater + WorldUnderlay capabilities")
check(captured and captured.publicBattleArtWater==true,"public Battle Art fingerprint reaches ConnectedWater authority")

local currentW=currentPublicWater()
local currentLib={require=function(n) if n=="WorldUnderlay" then return U elseif n=="Water" then return currentW end error(n,0) end}
local currentCaps=Atmos._publishWaterHostCaps("BATTLE_ART_VOXEL_FORK",currentLib,{drawWater=function() end})
check(currentCaps.publicBattleArtWater==true and currentCaps.voxelNexusWater==false,"current public Battle Art remains public even though it exports _trainSource")

local nxW=currentPublicWater();local nativeTide=function() return 1 end
local nxLib={realisticWorld={WaterEngine={tideOffset=nativeTide}},require=function(n) if n=="WorldUnderlay" then return U elseif n=="Water" then return nxW end error(n,0) end}
local nxCaps=Atmos._publishWaterHostCaps("BATTLE_ART_VOXEL_FORK",nxLib,{drawWater=function() end})
check(nxCaps.voxelNexusWater==true and nxCaps.publicBattleArtWater==false,"Nexus-only WaterEngine tide seam disambiguates Voxel Nexus from current Battle Art")

-- Hydrosphere retains the renderer fingerprint.
local CWa=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))({mod={},require=function() error("optional") end})
CWa.setVoxelWaterHost(caps)
check(CWa.voxelWaterHost().publicBattleArtWater==true,"ConnectedWater retains public Battle Art structured-water capability")

-- Now prove the exact regression: without _trainSource, public Battle Art still
-- enters Weather FX physical mesh ownership and the native 0..5px relief height
-- is forced to zero before the host reflective/depth pass draws it.
local now=1.25;local meshes={}
love={timer={getTime=function() return now end},image={newImageData=function() return {setPixel=function() end} end},graphics={
  newImage=function() return {setFilter=function() end,setWrap=function() end,release=function() end} end,
  newMesh=function(fmt,data,mode,usage)
    local m={mode=mode,usage=usage,current=type(data)=="table" and data or {}}
    function m:setTexture() end;function m:setVertexMap(v) self.map=v end
    function m:setVertices(r,s,n) self.current={};for i=1,(n or #r) do self.current[i]=r[i] end end
    function m:setDrawRange(a,n) self.range=n end;function m:release() end
    meshes[#meshes+1]=m;return m
  end,
}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},draw=function() end}
local Mat4={translate=function(x,y,z) return {x=x,y=y,z=z} end}
local body={id=-1,signature="public-ba-void",rects={{x0=-96,z0=-96,x1=224,z1=0}},cells={},area=120,
  loadBearing=false,tide=0,wave=1.0,ice=0,kind="SEA",rapidness=0,flowX=1,flowZ=0,visualOnly=true,voidWater=true}
for z=-6,-1 do for x=-6,13 do body.cells[#body.cells+1]={gx=x,gz=z} end end
local outer={id=-2,signature="public-ba-outer",outerSea=true,visualOnly=true,voidWater=true,kind="SEA",loadBearing=false,
  tide=0,wave=1.0,range=32768,innerRing=96,mapWidth=128,mapHeight=112,cx=64,cz=56,
  holes={{x0=-96,z0=-96,x1=224,z1=208,inner=true}},area=0,touchesBoundary=true}
local CWr={observed=true,bodies={},renderBodies={body},outerSea=outer,windX=1,windZ=.1,
  voxelWaterHost=function() return caps end,rippleState=function() return {} end}
local modules={ConnectedWater=CWr,Voxel3D=V3,Mat4=Mat4,Water=pubW}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))({require=function(n) local m=modules[n];if m then return m end error(n,0) end})
local repl,owned=R.prepare({{{},{},{}}})
local st=R.physicalSurfaceStats();local os=R.outerSeaStats()
check(owned==true and st.active==true,"public Battle Art without _trainSource now receives true Weather FX physical surface ownership")
check(pubW.WAVE_HEIGHT==0,"public Battle Art native geometric wave relief is disabled after Weather FX physical mesh preflight")
check(repl and #repl==1 and #R.voidDraws()==1,"native public Battle Art water list is replaced by one finite Weather FX VOID surface")
check(#R.outerDraws()==1 and os.active and os.dynamicVertices>0,"public Battle Art outer VOID ocean is one separate holed physical mesh, not a second native surface")

-- Reverting the capability must reproduce the old fallback signature: this is
-- the break-it-again check required by AGENTS.md.
R.invalidate();pubW=publicWater();modules.Water=pubW
CWr.voxelWaterHost=function() return {id="BATTLE_ART_VOXEL_FORK",publicBattleArtWater=false} end
local Rold=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))({require=function(n) local m=modules[n];if m then return m end error(n,0) end})
local _,oldOwned=Rold.prepare({{{},{},{}}});local oldStats=Rold.physicalSurfaceStats()
check(oldOwned==true and oldStats.active==false and pubW.WAVE_HEIGHT>0,"without public-host fingerprint the old double-relief fallback is reproduced")

local src=assert(io.open(ROOT.."lib/DramalessAtmos.lua","rb")):read("*a")
check(src:find("publicBattleArtWater",1,true)~=nil and src:find("nexusTide",1,true)~=nil,"bridge source contains explicit public-Battle-Art-vs-Voxel-Nexus capability split")

print(string.format("public Battle Art water 8.1.44: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
