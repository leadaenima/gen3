-- Weather FX 8.1.36 storm-front near-field handoff + volumetric presentation contract.
local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print('PASS '..m) else failed=failed+1;print('FAIL '..m) end end
local Types={get=function(id) return {id=id,ch={rain=.9,strike=22,dim=.7}} end}
local remote={id=9,weather='STORM',x=700,z=0,rx=400,rz=330,age=100,life=260,_lifeStage='mature',charge=.9,flash=0,strikeSerial=0,vx=-1,vz=.1}
local D=assert(loadfile(ROOT..'lib/DistantWeather.lua'))({require=function(n) if n=='StormCells' then return {cells=function() return {remote} end} elseif n=='Types' then return Types end error(n,0) end})
local function sampleAt(centerDist)
  remote.x=centerDist;D.update(.016,0,0);local a,n=D.items();local q=a[1];return q and tonumber(q.handoff),n
end
local h1,n1=sampleAt(800) -- ~400 outside the physical edge
local h2,n2=sampleAt(600) -- ~200 outside
local h3,n3=sampleAt(450) -- ~50 outside
local h4,n4=sampleAt(400) -- physical leading edge
local h5,n5=sampleAt(250) -- well inside: local bank is also active
check(n1==1 and n2==1 and n3==1 and n4==1 and n5==1,'world-space storm descriptor survives approach, contact and local overlap')
check(h1 and h2 and h3 and h4 and h1>.99 and h2>.99 and h3>.99 and h4>.99,'approaching front cloud does not fade away before physical contact')
check(h5 and h5>=.50 and h5<h4,'only post-contact overlap hands density to the local bank, with a visible remote floor')
local ws=assert(io.open(ROOT..'lib/WeatherState.lua','rb')):read('*a')
check(ws:find('_cellCloudWeather',1,true)~=nil and ws:find('q.cloudWeather or q.weather',1,true)~=nil,'WeatherState consumes cloud-only storm identity before precipitation core arrives')
check(ws:find('return State._cellCloudWeather,true',1,true)~=nil,'cloud-only front can own local 3D cloud target during handoff')
local cs=assert(io.open(ROOT..'lib/StormCells.lua','rb')):read('*a')
check(cs:find('cloudCellId',1,true)~=nil and cs:find('cloudWeather',1,true)~=nil,'StormCells publishes independent nearest cloud identity, not precipitation-only identity')
local cin=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
check(cin:find('_appendFrontCloudDescriptors',1,true)~=nil,'8.1.37 supersedes the 8.1.36 standalone storm-volume renderer with shared cloud-bank descriptors')
check(cin:find('local function ellipsoid',1,true)==nil and cin:find('vKind > 5.5',1,true)==nil,'legacy dark ellipsoid presentation cannot regress back into current runtime')
check(cin:find('tonumber(a.vx)',1,true)~=nil and cin:find('tonumber(a.vz)',1,true)~=nil,'front bank orientation still follows the real front travel direction')
check(cin:find('_frontCloudDeck',1,true)~=nil,'front cloud altitude is resolved through the live cloud-bank deck authority')
print(string.format('storm handoff continuity + 8.1.37 presentation supersession: %d passed, %d failed',passed,failed));if failed>0 then os.exit(1) end
