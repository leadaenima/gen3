local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0;local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local draws=0;local invalid=0
love={image={newImageData=function(w,h) return {setPixel=function() end} end},graphics={
 newImage=function() return {setFilter=function() end,setWrap=function() end,getDimensions=function() return 4,4 end} end,
 newMesh=function(fmt,data,usage,mode) local m={data=data};function m:setTexture() end;function m:setVertices(r,s,n) self.n=n end;function m:setDrawRange(a,n) self.range=n end;function m:release() end;return m end}}
local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},draw=function() draws=draws+1 end}
local Mat4={translate=function(x,y,z) return {x=x,y=y,z=z} end}
local Water={WAVE_TRAINS={{.15,.06,1.6,.6},{.05,.13,-1,.29},{-.04,.03,.55,.11}},WAVE_HEIGHT=5,invalidate=function() invalid=invalid+1 end}
local b1={signature="a",rects={{x0=0,z0=0,x1=32,z1=32}},area=4,loadBearing=false,tide=.3,wave=.8,ice=0}
local b2={signature="b",rects={{x0=64,z0=0,x1=96,z1=32}},area=4,loadBearing=true,tide=0,wave=0,ice=1}
local CW={observed=true,bodies={b1,b2},sample=function() return {windX=1,windZ=0,wave=.4,ice=.5} end,rippleState=function() return {{x=8,z=8,age=.1,life=.8,strength=1,body=b1}} end}
local modules={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water}
local V={require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(V)
local liquid,owned=R.prepare({{nil,{}}})
check(owned and #liquid==1,"connected renderer owns liquid water list")
check(liquid[1][3] and liquid[1][3].y==.3,"lunar tide is a body transform, not geometry rebuild")
check(type(liquid[1][1].data)=="table" and #liquid[1][1].data==6,"merged rectangle emits one quad rather than old tile quads")
R.drawAfterWater();check(draws>=2,"frozen body and rain ripple batch draw after liquid pass")
check(invalid==1,"wind sector compiles water wave direction once")
R.prepare({{nil,{}}});check(invalid==1,"unchanged prevailing wind avoids shader rebuild thrash")
CW.bodies={b2};local none,owned2=R.prepare({{nil,{}}});check(owned2 and #none==0,"all-frozen body suppresses resurrection of host tile water")
print(string.format("connected water 3D 8.1.29: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
