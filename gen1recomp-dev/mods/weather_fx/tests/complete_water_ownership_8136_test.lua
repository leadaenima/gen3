-- Weather FX 8.1.36 complete host-water ownership + seasonal ice contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local temperature=12
local Settings={weatherFxWaterEnabled=function() return true end}
local mods={Settings=Settings,WindEngine={peek=function() return {x=1,z=.1,strength=.7} end},CelestialSim={moonPhase=function() return 0 end},TimeOfDay={hour=12},Microclimate={peek=function() return {temperature=temperature} end}}
local hooks={}
local V={mod={hooks={wrap=function(self,name,fn) hooks[name]=fn end}},require=function(n) if mods[n] then return mods[n] end error(n,0) end}
local W=assert(loadfile(ROOT.."lib/ConnectedWater.lua"))(V)

-- One 16px gameplay cell is NOT water, but its upper-right 8px visual tile is.
-- This recreates the exact host granularity that leaked old voxel water before 8.1.36.
local map={id="MIXED",def={id="MIXED",width=2,height=2,tileset="OVERWORLD"}}
function map:isWaterCell() return false end
function map:tileAt(tx,ty) return ty*4+tx end
local Shape={}
function Shape.forMap(m) return {ok=true} end
function Shape.at(m,shapes,tile,tx,ty) return {class=(tx==1 and ty==0) and "water" or "solid"} end
local state={map=map,neighbors={},player={cellX=0,cellY=0},channels={}}
W.observeVoxel(state,Shape)
local sm=W.sample()
check(sm.bodies==0 and sm.hostBodies==1 and sm.hostTiles==1,"8px host-semantic water missed by 16px gameplay scan is captured as Weather FX water")
check(#W.renderBodies==1 and W.renderBodies[1].hostWater and W.renderBodies[1].cellSize==8,"captured host fragment enters professional renderer at exact 8px boundary")
check(W.bodyAt(12,4)==nil and not W.isLoadBearingAt(12,4),"extra host visual water never becomes gameplay water/collision authority")

-- Visual fragments freeze with the same climate so no old blue patch leaks through a winter scene,
-- but they remain presentation-only.
temperature=-18
for i=1,5200 do W.update(.25,{channels={snow=1,rain=0}},{id="WINTER"}) end
local hb=W.hostBodies[1]
check(hb and hb.presentationFrozen and hb.ice>=W.LOAD_BEARING,"host-semantic visual water follows winter freeze into a solid ice presentation")
check(not hb.loadBearing and W.bodyAt(12,4)==nil,"presentation-only frozen fragment still cannot create walkable gameplay support")

-- Real authored water does become load-bearing and then thaws back to liquid.
function map:isWaterCell(x,z) return x==0 and z==0 end
map.revision=1 -- authored water topology changed; host revision invalidates the cached water mask
state.player={cellX=1,cellY=1} -- do not park the player on open water; safety correctly prevents freezing under a surfer/player
W.invalidate();W.observeVoxel(state,Shape);temperature=-18
for i=1,5200 do W.update(.25,{channels={snow=1,rain=0}},{id="WINTER"}) end
W.observeVoxel(state,Shape) -- live renderer refreshes observation freshness every frame
local b=W.bodyAt(4,4)
check(b and b.loadBearing and W.isLoadBearingAt(4,4),"real cartridge water freezes into a load-bearing walkable ice block")
temperature=24
for i=1,5200 do W.update(.25,{channels={snow=0,rain=0}},{id="SUMMER"}) end
b=W.bodyAt(4,4)
check(b and not b.loadBearing and b.ice<.25,"warm spring/summer climate thaws load-bearing ice back into water")

-- Renderer-level material contract must use real block side geometry for load-bearing ice.
local src=assert(io.open(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua","rb")):read("*a")
check(src:find('meshForBody%(b,V3,192,"iceBlock"%)')~=nil,"load-bearing/presentation-frozen water uses solid ice-block geometry")
check(src:find('local cellSize=tonumber%(b.cellSize%) or 16')~=nil,"ice/water renderer honors body tile granularity instead of assuming 16px everywhere")

-- Secondary Voxel Realism water pass suppression is runtime-only and reversible.
local dsrc=assert(io.open(ROOT.."lib/DramalessAtmos.lua","rb")):read("*a")
check(dsrc:find("_suppressSecondaryHostWater",1,true)~=nil and dsrc:find("nativeWater",1,true)~=nil,"Weather FX suppresses secondary host water ownership to prevent double-render/old-water leaks")
check(dsrc:find("_hostRealisticNativeWater",1,true)~=nil and dsrc:find("rw.nativeWater=Atmos._hostRealisticNativeWater",1,true)~=nil,"ORIGINAL water mode retains and restores exact host secondary-water state")

print(string.format("complete water ownership 8.1.36: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
