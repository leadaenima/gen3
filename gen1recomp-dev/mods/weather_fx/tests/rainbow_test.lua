local ROOT=(arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;io.write("FAIL: ",n,"\n") end end
local rain=0
local cel={sun={dx=.96,dy=.22,dz=.18,altitudeDeg=13,discTransmission=.9,alpha=1},optics={cloud=.35}}
local cfg={rainbow={enabled=true,memorySeconds=120,fadeSeconds=2}}
local modules={Config={get=function() return cfg end},CelestialEngine={state=function() return cel end}}
local V={require=function(n) local m=modules[n];if m then return m end;error("missing "..n,0) end}
local state={channel=function(k) if k=="rain" then return rain end return 0 end}
local scene={visible="world",outdoor=true,indoors=false}
local R=assert(loadfile(ROOT.."lib/Rainbow.lua"))(V);modules.Rainbow=R
for _=1,20 do R.update(.25,state,scene) end
check(R.state().alpha==0,"no rain history means no rainbow")
rain=1
for _=1,24 do R.update(.25,state,scene) end
check(R.state().wetMemory>.7 and R.state().alpha==0,"active rain charges atmospheric moisture but does not pop rainbow")
rain=0
for _=1,24 do R.update(.25,state,scene) end
local a1=R.state().alpha
check(a1>.15,"rainbow gradually appears after rain clears with low visible sun")
check(a1<1,"rainbow fade-in remains gradual rather than instant")
cel.sun.altitudeDeg=55
for _=1,24 do R.update(.25,state,scene) end
check(R.state().alpha<a1,"sun above primary-rainbow geometry fades the arc")
cel.sun.altitudeDeg=13;cel.sun.discTransmission=.02
for _=1,24 do R.update(.25,state,scene) end
check(R.state().alpha<a1*.5,"blocked/overcast sun cannot sustain bright rainbow")
scene.indoors=true;scene.outdoor=false
for _=1,24 do R.update(.25,state,scene) end
check(R.state().target==0,"indoors never targets a sky rainbow")
scene.indoors=false;scene.outdoor=true;cfg.rainbow.enabled=false
R.update(.25,state,scene);check(R.state().target==0,"rainbow setting disables effect without erasing weather state")

-- Strict 3D renderer proof: far-depth LEQUAL ribbon around antisolar direction.
cfg.rainbow.enabled=true
local depthMode=nil;local draws=0;local vertices=0
love={graphics={
 newShader=function() return {} end,
 newMesh=function(v) vertices=math.max(vertices,#v);return {setVertices=function(self,vv) vertices=math.max(vertices,#vv) end,setDrawRange=function() end} end,
 getShader=function() return nil end,getDepthMode=function() return "lequal",true end,getBlendMode=function() return "alpha","alphamultiply" end,getColor=function() return 1,1,1,1 end,
 setShader=function() end,setDepthMode=function(m) depthMode=m end,setBlendMode=function() end,setColor=function() end,draw=function() draws=draws+1 end,
}}
modules.NightSky={projectDirection=function(Vox,x,y,z,w,h) if y<-.02 then return nil end return (w or 160)*.5+x*55,(h or 144)*.72-y*55 end}
modules.Rainbow={state=function() return {alpha=.85,sun={dx=.96,dy=.22,dz=.18,altitudeDeg=13,discTransmission=.9}} end}
local R3=assert(loadfile(ROOT.."lib/voxel_atmos/Rainbow3D.lua"))(V)
local vox={vp={1},size=function() return 160,144 end}
check(R3.draw(vox)==true and draws==1,"voxel rainbow submits a real procedural sky mesh")
check(vertices>100,"large rainbow uses dense smooth arc geometry")
check(depthMode=="lequal","rainbow uses world depth occlusion instead of screen overlay")
io.write(string.format("rainbow: %d passed, %d failed\n",pass,fail));os.exit(fail==0 and 0 or 1)
