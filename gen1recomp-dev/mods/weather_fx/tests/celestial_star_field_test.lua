local passed,failed=0,0
local function check(v,n)if v then passed=passed+1 else failed=failed+1;print('FAIL '..n)end end
local meshCreates,shaderCreates,drawCalls,instances,attaches=0,0,0,0,0
love={graphics={}}
function love.graphics.getSupported()return{instancing=true,glsl3=false}end
function love.graphics.newMesh(fmt,verts,mode,usage)meshCreates=meshCreates+1;return{attachAttribute=function()attaches=attaches+1 end,release=function()end}end
function love.graphics.newShader(src)shaderCreates=shaderCreates+1;return{src=src,send=function()end,release=function()end}end
function love.graphics.drawInstanced(_,n)drawCalls=drawCalls+1;instances=instances+n end
function love.graphics.setBlendMode()end;function love.graphics.setDepthMode()end;function love.graphics.setShader()end;function love.graphics.setColor()end
local cache={CelestialSim={latitude=function()return 42 end}};local V={}
function V.require(n)if cache[n]then return cache[n]end;local f=assert(loadfile('lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m end
local stars={};for i=1,5120 do stars[i]={dx=.2,dy=.6,dz=.77,r=.9,g=.95,b=1,a=.7,size=1.2,tw=.7,tw2=.3,twDepth=.2,phase=.1,phase2=.2,hideNearBuilding=(i%2==0)}end
local F=V.require('CelestialStarField');local voxel={eye={0,3,0},vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local ok,n=F.draw(voxel,stars,{axisR={1,0,0},axisU={0,1,0},radius=420,vaultAngle=.7,time=9,visibility=1,scale=1,buildingFactor=.5,twinkle=true})
check(ok and n==5120,'all 5,120 ordinary stars remain authored/rendered')
check(drawCalls==1 and instances==5120,'5,120 stars submit in one instanced draw')
check(meshCreates==2 and shaderCreates==1 and attaches==4,'catalogue/base/shader built once with four static attributes')
local ok2,n2=F.draw(voxel,stars,{axisR={1,0,0},axisU={0,1,0},radius=420,vaultAngle=.8,time=10,visibility=.8,scale=.9,buildingFactor=.3,twinkle=true})
check(ok2 and n2==5120 and meshCreates==2 and shaderCreates==1,'second frame performs zero catalogue/mesh rebuilds')
check(drawCalls==2 and instances==10240,'star instances render exactly once per frame')
local st=F.stats();check(st.builds==1 and st.count==5120 and not st.failed,'star field stats show one immutable catalogue build')
F.invalidate();check(F.stats().supported==false and not F.stats().failed,'star field invalidates cleanly')
print(('celestial star field: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
