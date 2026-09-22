-- Weather FX 8.1.46: Voxel Nexus continuous far-water material LOD.
-- The far 32K VOID ocean must retain the near water's optical material without
-- re-opening Voxel Nexus' expensive FULL reflection/depth transaction.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

local drawN,waterBeginN,waterDrawN,waterFinishN,depthBeginN,endWaterN=0,0,0,0,0,0
local lastCtx,lastSkyOnly,lastMesh,lastTex,lastModel=nil,nil,nil,nil,nil
love={timer={getTime=function() return 3 end},image={newImageData=function() return {setPixel=function() end} end},graphics={
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
  draw=function() drawN=drawN+1 end,size=function() return 1920,1080 end,
  depthReadable=function() return true end,beginWater=function() depthBeginN=depthBeginN+1;return {},{} end,
  endWater=function() endWaterN=endWaterN+1 end,
  vp={11},eye={1,2,3},curveX=.01,curveZ=.02,curveK=.003,cell=6,fovY=.9,skyEdge=.33,
  lookFlat={.2,0,-.98},descent=.41}
local Water={WAVE_TRAINS={{.1,.05,1,.6}},WAVE_HEIGHT=5,WAVE_SWELL={.03,.01,.5,.3},WAVE_BEND={-.01,.03,.3,1},
  WAVE_FPS=12,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=3.5,WAVE_SLOPE_LEAN=1.5,
  _waveTime=function() return 1.25 end,_trainSource=function() return "structured" end,invalidate=function() end,
  enabled=function() return true end,
  begin=function(ctx,skyOnly) waterBeginN=waterBeginN+1;lastCtx=ctx;lastSkyOnly=skyOnly and true or false;return true end,
  draw=function(mesh,tex,model) waterDrawN=waterDrawN+1;lastMesh,lastTex,lastModel=mesh,tex,model end,
  finish=function() waterFinishN=waterFinishN+1 end}
local Mat4={translate=function(x,y,z) return {kind="translate",x=x,y=y,z=z} end}
local caps={voxelNexusWater=true,publicBattleArtWater=false,structuredRelief=true,outerRange=32768,voidRingWorld=96}
local outer={id=-2,signature="continuity-outer",outerSea=true,visualOnly=true,voidWater=true,kind="SEA",loadBearing=false,
  tide=0,wave=1.0,range=32768,innerRing=96,mapWidth=128,mapHeight=112,cx=64,cz=56,
  holes={{x0=-96,z0=-96,x1=224,z1=208,inner=true}},area=0,touchesBoundary=true}
local CW={observed=true,bodies={},renderBodies={},outerSea=outer,windX=1,windZ=0,
  voxelWaterHost=function() return caps end,rippleState=function() return {} end}
local Grid={enabled=function() return true end}
local mods={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water,VoxelGrid=Grid}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))({require=function(n) local m=mods[n];if m then return m end error(n,0) end})
local repl,owned=R.prepare({})
check(owned==true and repl and #R.outerDraws()==1,"physical renderer prepares one Weather FX outer ocean")
check(Water.WAVE_HEIGHT==0,"host geometric relief remains suppressed after physical ownership")
local od=R.outerDraws()[1];local expectedMesh,expectedTex,expectedModel=od[1],od[2],od[3]
local ok=R.drawOuterFast();local stats=R.outerSeaStats()
check(ok==true,"Nexus far-water matched-material fast path succeeds")
check(waterBeginN==1 and lastSkyOnly==true,"far ocean uses host SKY-only water shader")
check(lastCtx and lastCtx.reflect==nil and lastCtx.depth==nil,"SKY-only far ocean requests no framebuffer/depth textures")
check(depthBeginN==0,"far ocean never calls Voxel3D.beginWater")
check(waterDrawN==1 and waterFinishN==1 and endWaterN==1,"one water-material draw and exact host shader restoration")
check(drawN==0,"enabled far ocean never falls back to mismatched ordinary scene shader")
check(lastMesh==expectedMesh and lastTex==expectedTex and lastModel==expectedModel,"SKY-only LOD submits the exact physical outer mesh/material/model")
check(lastCtx.vp==V3.vp and lastCtx.eye==V3.eye and lastCtx.skyEdge==V3.skyEdge,"far water uses the live near-water camera/sky context")
check(lastCtx.grid==true,"far water matches the live Nexus voxel-grid shader variant")
check(stats.fastDraws==1 and stats.skyDraws==1,"continuity/performance LOD is observable in diagnostics")

-- Material-disabled state must match the host's own plain-water fallback rather
-- than force a water shader the player explicitly disabled.
Water.enabled=function() return false end
local b0,w0=drawN,waterBeginN
check(R.drawOuterFast()==true and drawN==b0+1 and waterBeginN==w0,"host WATER=OFF uses the same plain scene-water state as the near pass")

-- If SKY-only cannot start, return false so DramalessAtmos uses the original
-- full reflective outer-water path. Visual continuity wins over silent downgrade.
Water.enabled=function() return true end;Water.begin=function() waterBeginN=waterBeginN+1;return false end
local d0=depthBeginN
check(R.drawOuterFast()==false and depthBeginN==d0,"SKY-only failure does not invent another path; bridge can fail open to FULL")

local src=assert(io.open(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua","rb")):read("*a")
check(src:find('Water.begin,ctx,true',1,true)~=nil and src:find('Water.draw(d[1],d[2],d[3])',1,true)~=nil,"source pins SKY-only host material + host Water.draw")
check(src:find('V3.beginWater',1,true)~=nil,"full reflective machinery remains available elsewhere for authored/near water")

print(string.format("Voxel Nexus water continuity 8.1.46: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
