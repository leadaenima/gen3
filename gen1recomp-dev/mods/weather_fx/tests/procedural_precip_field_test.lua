local passed,failed=0,0
local function check(v,n)if v then passed=passed+1 else failed=failed+1;print('FAIL '..n)end end
local drawCalls,total=0,0;local sources={};local attachCount=0
love={graphics={}}
function love.graphics.getSupported()return{instancing=true,glsl3=false}end
function love.graphics.newMesh()return{release=function()end,attachAttribute=function()attachCount=attachCount+1;return true end}end
function love.graphics.newShader(src)sources[#sources+1]=src;return{send=function()end,release=function()end}end
function love.graphics.drawInstanced(_,n)drawCalls=drawCalls+1;total=total+n end
function love.graphics.setBlendMode()end;function love.graphics.setDepthMode()end;function love.graphics.setShader()end;function love.graphics.setColor()end
local cache={};local C={}
function C.require(n)if cache[n]then return cache[n]end;local f=assert(loadfile('lib/'..n..'.lua'));local m=f(C);cache[n]=m;return m end
local P=C.require('ProceduralPrecipField')
check(P.supported()==true,'procedural rain/grain field works on attribute-instancing / non-GLSL3 path')
local V={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local requested=0
for _,q in ipairs{{kind='rain',count=11000},{kind='hail',count=44000},{kind='sand',count=42000},{kind='ash',count=10000}}do local ok,n=P.draw(V,{kind=q.kind,count=q.count,eye={0,8,0},focus={0,0,0},wind={.7,.2},nearRadius=96,farRadius=600,topY=100,bottomY=-18,span=70,time=10,intensity=2,tint={1,1,1}});check(ok and n==q.count,q.kind..' preserves exact far count');requested=requested+q.count end
check(total==requested,'all procedural precipitation instances submitted exactly')
local expected=math.ceil(11000/8192)+math.ceil(44000/8192)+math.ceil(42000/8192)+math.ceil(10000/8192)
check(drawCalls==expected,'heavy far fields use bounded fixed-size zero-upload chunks')
local src=table.concat(sources,'\n');check(src:find('attribute float InstanceSeed',1,true)~=nil and src:find('love_InstanceID',1,true)==nil,'field uses shared per-instance seed without GLSL3 requirement')
check(src:find('fieldKind',1,true)~=nil,'one persistent shader handles rain/hail/sand/ash')
check(attachCount>=1,'procedural precip attaches shared immutable per-instance seed')
print(('procedural precip field: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
