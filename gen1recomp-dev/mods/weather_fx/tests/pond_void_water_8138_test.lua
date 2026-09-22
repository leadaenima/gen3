-- Weather FX 8.1.38 living authored ponds + complete VOID ocean contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

-- --------------------------- root hydrosphere authority -------------------
local TileRenderer={voidFill="water"}
package.loaded["src.render.TileRenderer"]=TileRenderer
package.preload["src.render.TileRenderer"]=function() return TileRenderer end
local deps={
  Settings={weatherFxWaterEnabled=function() return true end},
  WindEngine={peek=function() return {x=1,z=.2,strength=.8} end},
  CelestialSim={moonPhase=function() return 0 end},
  TimeOfDay={hour=12},
  Microclimate={peek=function() return {temperature=13} end},
}
local Vroot={mod={hooks={wrap=function() end}},require=function(n) local m=deps[n];if m then return m end error(n,0) end}
local H=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))(Vroot)
local map={id="PONDROOT",def={id="PONDROOT",width=8,height=7,tileset="OVERWORLD"}}
function map:isWaterCell(x,z) return (x==3 and z==3) or (x==4 and z==3) or (x==3 and z==4) or (x==4 and z==4) end
local state={map=map,neighbors={},player={cellX=1,cellY=1},channels={rain=.3,snow=0}}
check(H.observeVoxel(state)==true,"8.1.38 observer accepts authored pond + VOID WATER map")
check(#H.bodies==1 and H.bodies[1].kind=="POND" and not H.bodies[1].visualOnly,"small authored connected body is classified as gameplay POND")
check(H.outerSea and H.outerSea.outerSea and H.outerSea.visualOnly and H.outerSea.voidWater,"VOID WATER publishes a separate presentation-only outer sea")
check(H.outerSea.range==32768 and H.outerSea.innerRing==96,"outer sea radius matches Voxel Nexus WorldUnderlay and preserves exact 96px handoff")
check(H.bodyAt(-300,-300)==nil and not H.isWaterAt(-300,-300),"outer sea never enters gameplay bodyByCell water authority")
check(#H.renderBodies==2,"renderBodies remains authored pond + finite 96px apron only; far sea stays outside gameplay/body renderer list")
H.update(.1,state,{id="SUMMER"})
check(H.voidBodies[1] and H.outerSea.tide==H.voidBodies[1].tide and H.outerSea.wave==H.voidBodies[1].wave,"outer sea copies exact finite-apron tide and wave state")
local sm=H.sample();check(sm.outerSea and sm.outerSeaRange==32768 and sm.bodies==1,"diagnostics expose far presentation sea without inflating gameplay body count")
TileRenderer.voidFill="trees";H.observeVoxel(state)
check(H.outerSea==nil and #H.voidBodies==0,"live VOID WATER -> TREES removes both finite and far Weather FX sea immediately")
TileRenderer.voidFill="water";H.observeVoxel(state)

-- --------------------------- renderer contract ----------------------------
local drawCount,waterDrawCount=0,0
local color={1,1,1,1};local alphas={}
local now=1.25
love={timer={getTime=function() return now end},image={newImageData=function() return {setPixel=function() end} end},graphics={
  setColor=function(r,g,b,a) color={r,g,b,a};alphas[#alphas+1]=a end,
  getColor=function() return color[1],color[2],color[3],color[4] end,
  newImage=function() return {setFilter=function() end,setWrap=function() end,getDimensions=function() return 64,64 end,release=function() end} end,
  newMesh=function(fmt,data,mode,usage)
    local m={data=data}
    function m:setTexture() end;function m:setVertexMap(v) self.map=v end
    function m:setVertices(r,s,n) self.rows=r;self.n=n end;function m:setDrawRange(a,n) self.range=n end;function m:release() end
    return m
  end
}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},curveX=0,curveZ=0,curveK=.002,
  vp={},eye={},cell=16,fovY=1,skyEdge=.4,lookFlat={1,0},descent=0,
  draw=function() drawCount=drawCount+1 end,size=function() return 640,480 end,depthReadable=function() return true end,
  beginWater=function() return {},{} end,endWater=function() end}
local Mat4={identity=function() return {} end,translate=function(x,y,z) return {1,0,0,x,0,1,0,y,0,0,1,z,0,0,0,1} end}
local Water={WAVE_TRAINS={{.08,.02,1,.46},{.04,.01,2,.17},{.02,.01,3,.06},{.03,.02,.7,.2},{-.02,.03,-.5,.11}},WAVE_HEIGHT=5,
  WAVE_SWELL={.02,.01,.4,.32},WAVE_BEND={-.01,.03,.3,.95},WAVE_FPS=30,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=4,WAVE_SLOPE_LEAN=1.22,
  _waveTime=function() return now end,_trainSource=function() return "structured" end,invalidate=function() end,enabled=function() return true end,
  begin=function() return true end,draw=function() waterDrawCount=waterDrawCount+1 end,finish=function() end}
local mods={ConnectedWater=H,Voxel3D=V3,Mat4=Mat4,Water=Water}
local Vr={require=function(n) local m=mods[n];if m then return m end error(n,0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(Vr)
local repl,owned=R.prepare({{{}, {}}})
local ponds=R.pondDraws();local outer=R.outerDraws();local ps=R.pondStats();local os=R.outerSeaStats()
check(owned and repl and #repl==1 and repl[1][4].voidWater and not repl[1][4].outerSea,"finite 96px apron remains in ordinary physical-water replacement list")
check(#ponds==1 and ponds[1][4].kind=="POND" and ponds[1][6]>=.46 and ponds[1][6]<=.54,"authored POND is split into 46-54% translucent reflective pass")
check(#outer==1 and outer[1][4].outerSea,"complete far VOID ocean is a separate physical-water draw")
check(ps.bodies==1 and ps.fish>=2 and ps.fish<=6 and ps.maxFish==24,"authored pond receives deterministic 2-6 tiny fish under global 24-fish cap")
check(os.active and os.range==32768 and os.vertices>0 and os.indices>0 and os.vertices<8000,"outer ocean uses bounded distance-adaptive indexed tessellation")
local okP=R.drawPonds(function() end);local after=R.pondStats()
check(okP and waterDrawCount>0 and drawCount>=2,"pond bed/fish are world geometry and pond surface uses reflective host Water pass")
local sawAlpha=false;for _,a in ipairs(alphas) do if a and a>=.46 and a<=.54 then sawAlpha=true end end
check(sawAlpha,"pond reflective surface actually submits translucent alpha to the host shader")
check(after.visibleFish>=2 and after.visibleFish<=6,"tiny fish are actually emitted while liquid pond is open")
-- Single-cell trajectories are easiest to prove geometrically; every fish vertex
-- must remain within that one authored 16px cell. Rebuild a one-cell POND body.
local one={id=91,signature="one",cells={{gx=5,gz=6}},rects={{x0=80,z0=96,x1=96,z1=112}},area=1,kind="POND",visualOnly=false,loadBearing=false,ice=0,tide=0,wave=.2}
H.renderBodies={one};H.bodies={one};H.outerSea=nil;H.voidBodies={};H.observed=true
R.invalidate();R.setEnabled(true);R.prepare({{{},{}}});R.drawPonds(function() end)
local inCell=true
for i=1,#(R._fishRows or {}) do local v=R._fishRows[i];if v[1]<80 or v[1]>96 or v[3]<96 or v[3]>112 then inCell=false;break end end
check(inCell and R.pondStats().visibleFish>=2,"every fish trajectory/geometry stays inside one authoritative authored water cell")
one.ice=.72;R.prepare({{{},{}}});R.drawPonds(function() end)
check(R.pondStats().visibleFish==0,"fish disappear once substantial pond ice closes the surface")

-- Visual-only POND-shaped fragments must never enter the living-pond path.
local fake={id=-5,signature="fake",cells={{gx=0,gz=0}},rects={{x0=0,z0=0,x1=8,z1=8}},cellSize=8,area=.25,kind="POND",visualOnly=true,hostWater=true,loadBearing=false,ice=0,tide=0,wave=.1}
H.renderBodies={fake};H.bodies={};H.hostBodies={fake};H.observed=true
R.invalidate();R.setEnabled(true);local ordinary,owned2=R.prepare({{{},{}}})
check(owned2 and #ordinary==1 and #R.pondDraws()==0 and R.pondStats().fish==0,"visual-only/host water can never spawn pond fish or translucent living-water semantics")

-- Missing specialized host capabilities must keep the authored pond in the
-- ordinary list: fail open to visible water, never fail closed to a hole.
local WaterPlain={WAVE_TRAINS={{.1,0,1,.6}},WAVE_HEIGHT=2,invalidate=function() end}
mods.Water=WaterPlain;H.renderBodies={one};H.bodies={one};one.ice=0;H.observed=true
R.invalidate();R.setEnabled(true);local fallback,owned3=R.prepare({{{},{}}})
check(owned3 and #fallback==1 and #R.pondDraws()==0,"unsupported translucent-water host fails open to ordinary pond water")

-- Shared multi-host bridge must route the far sea and living pond pass without
-- editing any host on disk.
local dsrc=assert(io.open(ROOT.."lib/DramalessAtmos.lua","rb")):read("*a")
check(dsrc:find("outerDraws",1,true)~=nil and dsrc:find("drawPonds",1,true)~=nil,"shared multi-host water bridge routes complete outer sea + living ponds")
check(dsrc:find("origWater(ponds",1,true)~=nil,"specialized pond failure has immediate ordinary-host-water fallback")

print(string.format("living ponds + complete void ocean 8.1.38: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
