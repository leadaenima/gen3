-- Continuous sky-gradient executable proof.
local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL ",name,"\n") end
end
local function approx(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end

local newMeshCalls,setVerticesCalls,drawCalls,rectCalls=0,0,0,0
local lastVerts
local currentColor={1,1,1,1}
love={graphics={
  getShader=function() return "host-shader" end,
  setShader=function() end,
  getDepthMode=function() return "lequal",true end,
  setDepthMode=function() end,
  getBlendMode=function() return "alpha","alphamultiply" end,
  setBlendMode=function() end,
  getColor=function() return currentColor[1],currentColor[2],currentColor[3],currentColor[4] end,
  setColor=function(r,g,b,a) currentColor={r,g,b,a} end,
  newMesh=function(verts,mode,usage)
    newMeshCalls=newMeshCalls+1; lastVerts=verts
    check(mode=="triangles" and usage=="dynamic","smooth sky uses dynamic triangle mesh")
    local m={}
    function m:setVertices(v) setVerticesCalls=setVerticesCalls+1; lastVerts=v end
    function m:release() end
    return m
  end,
  draw=function() drawCalls=drawCalls+1 end,
  rectangle=function() rectCalls=rectCalls+1 end,
}}

local smoothCfg=true
local smoothChoice="config"
local V={}
function V.require(name)
  if name=="Settings" then return {get=function(k) if k=="smoothSky" then return smoothChoice end end} end
  if name=="Config" then return {get=function() return {celestial={smoothSky=smoothCfg}} end} end
  error("unexpected require "..tostring(name),0)
end
local Smooth=assert(loadfile(ROOT.."lib/SmoothSky.lua"))(V)
local sky={0.5,0.7,0.9,1,bands={
  {0.08,0.22,0.55},
  {0.22,0.52,0.88},
  {0.66,0.82,0.96},
}}

check(Smooth.draw(200,120,sky,100)==true,"smooth sky draw succeeds")
check(newMeshCalls==1 and drawCalls==1,"smooth sky reaches one GPU mesh submission")
check(rectCalls==0,"GPU path does not paint horizontal rectangle bands")
check(type(lastVerts)=="table" and #lastVerts==12,"three sky stops become two continuous gradient segments")
-- Segment 1 bottom and segment 2 top both use the exact middle color.
local mid=sky.bands[2]
local boundary={}
for _,v in ipairs(lastVerts or {}) do
  if approx(v[2],50) then boundary[#boundary+1]=v end
end
check(#boundary==6,"shared middle boundary is represented by both adjacent triangles")
local same=true
for _,v in ipairs(boundary) do
  if not (approx(v[5],mid[1]) and approx(v[6],mid[2]) and approx(v[7],mid[3])) then same=false end
end
check(same,"adjacent gradient segments share an identical boundary color with no seam")
check(approx(lastVerts[1][5],sky.bands[1][1]) and approx(lastVerts[1][6],sky.bands[1][2]),"top gradient color preserved")
check(approx(lastVerts[#lastVerts][5],sky.bands[3][1]) and approx(lastVerts[#lastVerts][7],sky.bands[3][3]),"horizon gradient color preserved")

check(Smooth.draw(200,120,sky,100)==true,"smooth sky redraw succeeds")
check(newMeshCalls==1 and setVerticesCalls==1,"mesh is reused instead of reallocated every frame")

smoothCfg=false
local beforeDraw=drawCalls
check(Smooth.draw(200,120,sky,100)==false,"smooth-sky CONFIG can disable the overlay")
check(drawCalls==beforeDraw,"disabled smooth sky leaves host presentation untouched")
-- Direct menu ON/OFF must override a stale/opposite config mirror immediately.
smoothChoice="on"
check(Smooth.draw(200,120,sky,100)==true,"SMOOTH SKY menu ON overrides stale config OFF on the same draw")
local st=Smooth.status();check(st.enabled and st.path=="mesh" and st.drawSerial>0,"smooth sky exposes positive live mesh-draw telemetry")
smoothChoice="off";smoothCfg=true;beforeDraw=drawCalls
check(Smooth.draw(200,120,sky,100)==false,"SMOOTH SKY menu OFF immediately leaves host sky untouched")
st=Smooth.status();check(st.enabled==false and st.path=="host","smooth sky telemetry reports deliberate host fallback when OFF")
smoothChoice="config";smoothCfg=true

-- Force the bounded fallback and prove it samples continuously rather than
-- falling back to the host's few large checker-dithered bands.
Smooth.invalidate()
love.graphics.newMesh=nil
rectCalls=0
local seen={}
love.graphics.rectangle=function(kind,x,y,w,h)
  rectCalls=rectCalls+1
  seen[#seen+1]={currentColor[1],currentColor[2],currentColor[3]}
end
check(Smooth.draw(200,120,sky,100)==true,"strip fallback succeeds when Mesh API is unavailable")
check(rectCalls==96,"fallback uses bounded 96-step continuous sampling")
check(#seen==96 and seen[1][1]~=seen[48][1] and seen[48][1]~=seen[96][1],"fallback colors evolve gradually through the sky")


local function readFile(path)
  local f=assert(io.open(path,"rb")); local x=f:read("*a"); f:close(); return x
end
local main=readFile(ROOT.."main.lua")
local hostPaint=assert(main:find("pcall%(orig,w,h,skyArg,horizonY,cell,nil",1,false) or main:find("safe%(orig,w,h,skyArg,horizonY,cell,nil",1,false))
local smoothRequire=assert(main:find('V.require%("SmoothSky"%)',1,false))
local smoothDraw=assert(main:find("SmoothSky%.draw%(w,h,skyArg,edge%)",1,false))
check(smoothRequire>hostPaint,"smooth overlay is integrated after host sky paint")
check(smoothDraw>smoothRequire,"integrated wrapper actually submits SmoothSky draw")
check(smoothDraw < (main:find("NightSky%.draw",smoothDraw) or math.huge),"smooth sky is painted before deep-sky objects")

io.write(string.format("smooth sky: %d passed, %d failed\n",passed,failed))
os.exit(failed==0 and 0 or 1)
