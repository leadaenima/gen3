local ROOT=(arg and arg[0] and arg[0]:match("^(.*[/\\])")) or "tests/";ROOT=ROOT:gsub("tests[/\\]$","")
local passed,failed=0,0
local function check(v,m) if v then passed=passed+1;print("PASS "..m) else failed=failed+1;print("FAIL "..m) end end
local function close(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end

local now=10
local created,draws,invalid={},{},0
love={timer={getTime=function() return now end},image={newImageData=function(w,h)
  local d={w=w,h=h,pixels={}}
  function d:setPixel(x,y,r,g,b,a) self.pixels[#self.pixels+1]={r,g,b,a} end
  created[#created+1]=d;return d
end},graphics={
  newImage=function(d) return {data=d,setFilter=function() end,setWrap=function() end,release=function() end} end,
  newMesh=function(fmt,data,usage,mode) local m={data=data};function m:setTexture() end;function m:setVertices(r,s,n) self.n=n end;function m:setDrawRange(a,n) self.range=n end;function m:release() end;return m end}}

local V3={FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}},draw=function(m,t,tr) draws[#draws+1]={m=m,t=t,tr=tr} end}
local Mat4={translate=function(x,y,z) return {x=x,y=y,z=z} end}
local original={
  trains={{.150,.062,1.60,.60},{.058,.132,-1.05,.29},{-.041,.033,.55,.11}},
  height=5,swell={.0325,.0134,.55,.35},bend={-.0138,.0333,.35,1.10},fps=12,pixels=1,slope=3.5,slopeLean=1.5
}
local Water={WAVE_TRAINS={},WAVE_HEIGHT=original.height,WAVE_SWELL={table.unpack(original.swell)},WAVE_BEND={table.unpack(original.bend)},
  WAVE_FPS=original.fps,WAVE_PIXELS_PER_STEP=original.pixels,WAVE_SLOPE=original.slope,WAVE_SLOPE_LEAN=original.slopeLean,
  _waveTime=function() return 0 end,_trainSource=function() return "structured" end,invalidate=function() invalid=invalid+1 end}
for i,t in ipairs(original.trains) do Water.WAVE_TRAINS[i]={table.unpack(t)} end

local body={signature="sea",rects={{x0=0,z0=0,x1=256,z1=256}},cells={},area=256,loadBearing=false,tide=.20,wave=1.20,ice=0}
for gz=0,15 do for gx=0,15 do body.cells[#body.cells+1]={gx=gx,gz=gz} end end
local CW={observed=true,bodies={body},sample=function() return {windX=1,windZ=0} end,rippleState=function() return {} end}
function CW.bodyAt(x,z) if x>=0 and x<256 and z>=0 and z<256 then return body end end
local modules={ConnectedWater=CW,Voxel3D=V3,Mat4=Mat4,Water=Water}
local V={require=function(n) if modules[n] then return modules[n] end error(n,0) end}
local R=assert(loadfile(ROOT.."lib/voxel_atmos/ConnectedWater3D.lua"))(V)

local liquid,owned=R.prepare({{nil,{}}})
check(owned and #liquid==1,"structured Voxel water remains host-reflective")
check(R.currentWaveHeight>6.0 and R.currentWaveHeight<=8.0,"strong sea state expands to large peak-to-trough relief")
local model=liquid[1] and liquid[1][3]
check(model and close(model.y,body.tide-R.currentWaveHeight*.5,.001),"wave slab is centered around tide datum instead of sitting entirely above it")

local mn,mx,sum,n=1e9,-1e9,0,0;local maxX,maxZ=0,0
for z=4,252,4 do for x=4,252,4 do
  local d=R.waveDisplacementAt(x,z,true);mn=math.min(mn,d);if d>mx then mx,maxX,maxZ=d,x,z end;sum=sum+d;n=n+1
end end
check(mn < -0.75,"real troughs fall below mean water level")
check(mx > 0.75,"real crests rise above mean water level")
check(math.abs(sum/n) < R.currentWaveHeight*.12,"wave field remains approximately zero-mean across the body")
check((mx-mn) > R.currentWaveHeight*.45,"wave surface uses substantial vertical range rather than tiny texture wobble")

local datum=-2+body.tide
local y=R.visualSurfaceYAt(maxX,maxZ,true)
check(y and y>datum,"visual surface sampler follows the same crest field as rendering")
local p={surfing=true,px=maxX-8,py=maxZ-8,cellX=math.floor(maxX/16),cellY=math.floor(maxZ/16)}
local state={player=p};local px0,py0=p.px,p.py
local b1=R.playerBob(state);now=now+.08;local b2=R.playerBob(state)
check(b1>0 and b2>0,"Surf presentation bob follows the sampled crest")
check(p.px==px0 and p.py==py0,"Surf bob never mutates gameplay x/z coordinates")
p.surfing=false;check(R.playerBob(state)==0,"non-Surf player receives no wave bob")

R.drawAfterWater()
check(#draws>=1,"shoreline trough seal is submitted as bounded world geometry")
local seal=nil
for _,d in ipairs(draws) do if d.m and d.m.data and #d.m.data>0 then
  for _,v in ipairs(d.m.data) do if type(v)=="table" and v[2] and v[2] < -6 then seal=d;break end end
end;if seal then break end end
check(seal~=nil,"below-datum shoreline seal reaches beneath maximum trough without covering land")

R.invalidate()
check(close(Water.WAVE_HEIGHT,original.height),"hot teardown restores host wave height")
check(close(Water.WAVE_FPS,original.fps) and close(Water.WAVE_SLOPE,original.slope) and close(Water.WAVE_SLOPE_LEAN,original.slopeLean),"hot teardown restores host timing and reflection slope")
local restored=true
for i,t in ipairs(original.trains) do for j=1,4 do if not close(Water.WAVE_TRAINS[i][j],t[j]) then restored=false end end end
for j=1,4 do if not close(Water.WAVE_SWELL[j],original.swell[j]) or not close(Water.WAVE_BEND[j],original.bend[j]) then restored=false end end
check(restored,"hot teardown restores host trains, swell and bend exactly")

print(string.format("real rolling waves 8.1.31: %d passed, %d failed",passed,failed));if failed>0 then os.exit(1) end
