-- Weather FX 8.1.34 voxel VOID FILL = WATER replacement contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end

-- The exact Gen1Recomp seam is global src.render.TileRenderer. Weather FX must
-- observe this live because the player can change VOID FILL without changing map.
local TileRenderer={voidFill="water"}
package.loaded["src.render.TileRenderer"]=TileRenderer
package.preload["src.render.TileRenderer"]=function() return TileRenderer end

local deps={
  Settings={weatherFxWaterEnabled=function() return true end},
  WindEngine={peek=function() return {x=1,z=.15,strength=.9} end},
  CelestialSim={moonPhase=function() return 0 end},
  TimeOfDay={hour=12},
  Microclimate={peek=function() return {temperature=12} end},
}
local V={mod={hooks={wrap=function() end}},require=function(n) local m=deps[n];if m then return m end error(n,0) end}
local H=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))(V)
local function map(id,dw,dh,tileset,water)
  local m={id=id,def={id=id,width=dw,height=dh,tileset=tileset or "OVERWORLD"}}
  function m:isWaterCell(x,z) return water and water[x..":"..z] == true or false end
  return m
end
local root=map("ROOT",10,8,"OVERWORLD") -- 20x16 Weather FX cells
local state={map=root,neighbors={},player={cellX=4,cellY=4},channels={}}
check(H.observeVoxel(state)==true,"void-water observer accepts an OVERWORLD map")
local expected=(20+12)*(16+12)-20*16
check(#H.bodies==0 and #H.voidBodies==1,"VOID FILL water creates a visual sea even with zero cartridge-water bodies")
check(H.voidBodies[1].area==expected,"void sea reproduces the voxel host's exact 3-block / 96px apron width")
check(H.voidBodies[1].kind=="SEA" and H.voidBodies[1].visualOnly and H.voidBodies[1].voidWater,"synthetic apron is explicitly classified as visual-only exposed sea")
check(#H.renderBodies==1 and H.renderBodies[1]==H.voidBodies[1],"synthetic void sea is published to the renderer ownership list")
check(H.bodyAt(-8,-8)==nil and not H.isLoadBearingAt(-8,-8),"void sea never becomes cartridge gameplay water or walkable ice")

-- Exact VoxelScene mask semantics: a connected neighbour body suppresses the
-- current map ring under it. East neighbour starts exactly at root east edge.
local east=map("EAST",4,8,"OVERWORLD") -- 8x16 cells
state.neighbors={{map=east,ox=20*16,oy=0}}
H.invalidate();TileRenderer.voidFill="water";H.observeVoxel(state)
local maskedExpected=expected-(6*16) -- six 16px apron cells x neighbour height
check(H.voidBodies[1].area==maskedExpected,"connected neighbour body masks overlapping synthetic void-water apron cells")
local leaked=false
for _,c in ipairs(H.voidBodies[1].cells) do if c.gx>=20 and c.gx<26 and c.gz>=0 and c.gz<16 then leaked=true;break end end
check(not leaked,"void-water geometry does not leak through a connected neighbour map body")

-- Live player toggle must force topology rebuild without a map transition.
state.neighbors={};TileRenderer.voidFill="water";H.invalidate();H.observeVoxel(state)
local keyWater=H._topologyKey
TileRenderer.voidFill="trees";H.observeVoxel(state)
check(keyWater~=H._topologyKey and #H.voidBodies==0 and #H.renderBodies==0,"live VOID FILL WATER -> TREES toggle removes Weather FX void water immediately")
TileRenderer.voidFill="black";H.observeVoxel(state)
check(#H.voidBodies==0,"VOID FILL BLACK never receives synthetic water")
TileRenderer.voidFill="water";root.def.tileset="CAVERN";H.observeVoxel(state)
check(#H.voidBodies==0,"non-OVERWORLD maps never receive the overworld void sea")
root.def.tileset="OVERWORLD";H.observeVoxel(state)
check(#H.voidBodies==1,"returning to OVERWORLD + WATER restores synthetic void sea without restarting")

H.update(.1,{channels={rain=.45,snow=0}},{id="SUMMER"})
local vb=H.voidBodies[1]
check(vb.wave>0.5 and vb.ice==0 and not vb.loadBearing,"void sea responds to wind/rain waves but can never freeze or become support")
local sm=H.sample()
check(sm.bodies==0 and sm.cells==0 and sm.voidBodies==1 and sm.voidCells==vb.area and sm.renderBodies==1,"diagnostics separate visual void water from cartridge hydrology counts")

-- Renderer: a void-only map must still be OWNED by Weather FX so the original
-- flat blue Voxel Realism water draw is suppressed/replaced. Turning WATER STYLE
-- to ORIGINAL releases the same draw immediately.
local now=0
love={timer={getTime=function() return now end},image={newImageData=function() return {setPixel=function() end} end},graphics={
  newImage=function() return {setFilter=function() end,setWrap=function() end,release=function() end} end,
  newMesh=function(fmt,data,mode,usage)
    local m={}
    function m:setTexture() end;function m:setVertexMap(v) self.map=v end
    function m:setVertices(r,s,n) self.n=n end;function m:setDrawRange(a,n) self.range=n end;function m:release() end
    return m
  end
}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},draw=function() end}
local Mat4={translate=function(x,y,z) return {1,0,0,x,0,1,0,y,0,0,1,z,0,0,0,1} end}
local Water={WAVE_TRAINS={{.15,.06,1.6,.6},{.05,.13,-1,.29},{-.04,.03,.55,.11}},WAVE_HEIGHT=5,
  WAVE_SWELL={.0325,.0134,.55,.35},WAVE_BEND={-.0138,.0333,.35,1.10},WAVE_FPS=12,WAVE_PIXELS_PER_STEP=1,WAVE_SLOPE=3.5,WAVE_SLOPE_LEAN=1.5,
  _waveTime=function() return now end,_trainSource=function() return "structured" end,invalidate=function() end}
local CW={observed=true,bodies={},voidBodies={vb},renderBodies={vb},windX=1,windZ=.15,rippleState=function() return {} end,bodyAt=function() return nil end}
local mods={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water}
local RV={require=function(n) local m=mods[n];if m then return m end error(n,0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(RV)
local nativeTex={};local repl,owned=R.prepare({{{},nativeTex}});local stats=R.physicalSurfaceStats()
check(owned and repl and #repl==1 and repl[1][4].voidWater,"Weather FX replaces flat host water on a void-only map")
check(stats.active and stats.vertices>1000 and stats.waveHeight>3,"void sea uses the real tessellated 3D wave engine, not a flat replacement quad")
R.setEnabled(false);local offRepl,offOwned=R.prepare({{{},nativeTex}})
check(offRepl==nil and offOwned==false,"WATER STYLE = ORIGINAL releases void water back to the voxel host")
R.setEnabled(true);local onRepl,onOwned=R.prepare({{{},nativeTex}})
check(onOwned and onRepl and #onRepl==1,"WATER STYLE = WEATHER FX reclaims both void and authored water presentation")

print(string.format("void water 8.1.34: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
