-- Weather FX 8.0.4: celestial occlusion + constellation brightness static contract.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end end
local function read(rel) local f=assert(io.open(ROOT..rel,"rb")); local s=f:read("*a"); f:close(); return s end
local ns=read("lib/NightSky.lua")
local sf=read("lib/CelestialStarField.lua")
local cb=read("lib/CelestialBodies.lua")
local da=read("lib/DramalessAtmos.lua")
local co=read("lib/Constellations.lua")

-- The historical 8.0.4 gate still named the old .92/.64 values even though
-- the preserved 8.1.35 baseline intentionally uses the later .96/.73 tuning.
-- Assert the current preserved brightness so this regression test cannot force
-- a quality reduction while validating the same occlusion contract.
check(co:find("a=primary and .96 or .73",1,true)~=nil,"current constellation brightness preserved")
check(ns:find('setDepthMode,"always",false',1,true)==nil,"NightSky sun/moon never bypass depth")
check(cb:find('setDepthMode,"always",false',1,true)==nil,"CelestialBodies never bypass depth")
check(ns:find("clip.z = clip.w",1,true)~=nil,"NightSky world celestial shader forces far depth")
check(sf:find("clip.z=clip.w",1,true)~=nil,"instanced star world shader forces far depth")
check(cb:find("clip.z = clip.w",1,true)~=nil,"body world shader forces far depth")
check(da:find("celestial occlusion authority",1,true)~=nil and da:find("after world depth exists",1,true)~=nil,"strict 3D draw has explicit depth-after-world authority")
check(da:find("sunBlockedByWorld(Voxel3D,sun)",1,true)~=nil,"direct-sun glare is world-occlusion gated")
local pWorld=assert(da:find("Atmos._worldCelestialDrew=false",1,true))
local pCin=assert(da:find("if cin.draw then",pWorld,true))
check(pWorld<pCin,"celestial draw occurs before clouds/weather")
local pBegin=assert(da:find('function Voxel3D.beginScene(...)',1,true))
local pEnd=assert(da:find('return Atmos._origBeginScene(...)',pBegin,true))
local beginBlock=da:sub(pBegin,pEnd)
check(beginBlock:find("drawProjected",1,true)==nil,"beginScene no longer paints an unoccluded celestial copy")

print(("celestial occlusion/brightness: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
