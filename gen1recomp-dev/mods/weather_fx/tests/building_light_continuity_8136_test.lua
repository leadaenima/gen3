-- Weather FX 8.1.36 connected-map building-light continuity contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local currentMap,playerX,playerY,neighbors
local root={id="ROOT",def={id="ROOT",width=10,height=8,tileset="OVERWORLD"}}
local east={id="EAST",def={id="EAST",width=10,height=8,tileset="OVERWORLD",warps={{x=1,y=5,type="door"}}}}
currentMap=root;neighbors={{map=east,ox=10*32,oy=0}}
local Scene={overworld=function() return {map=currentMap} end}
local Player={position=function() return playerX,playerY end}
local Atmos={_lastMap=root,_lastNeighbors=neighbors}
local V={require=function(n) return ({Scene=Scene,DramalessAtmos=Atmos,TimeOfDay={hour=22},Settings={get=function() end,is=function() return false end},Config={get=function() return {} end}})[n] or error(n,0) end}
local B=assert(loadfile(ROOT.."lib/BuildingLight.lua"))(V)
-- verify exact map dims conversion: Voxel def width/height are 32px blocks => 2 movement cells each.
local w,h=B._testDims(root);check(w==20 and h==16,"voxel map block dimensions convert to the correct movement-cell dimensions")
-- A building entrance just inside EAST must influence ROOT before crossing.
local bs,ctx=B._testNeighborhoodBuildings(root)
check(ctx and #bs>=1 and (B.debugInfo().neighborhoodMaps or 0)>=2,"building scan includes connected neighboring maps in one shared world coordinate system")
local dA=B._testNearestDist(18,6,bs);local fA=B._testDistToFactor(dA)
local dB=B._testNearestDist(20,6,bs);local fB=B._testDistToFactor(dB)
check(dA and dB and math.abs(dA-dB)<=2,"physical approach to neighboring building changes distance continuously across map seam")
check(math.abs(fA-fB)<.35,"star/constellation light-pollution target does not jump solely because map root changes")
local src=assert(io.open(ROOT.."lib/BuildingLight.lua","rb")):read("*a")
check(src:find("Do NOT clear the prior physical distance",1,true)~=nil,"map transition explicitly preserves prior physical building distance until connected context arrives")
print(string.format("building light continuity 8.1.36: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
