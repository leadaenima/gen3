local passed,failed=0,0
local function check(v,n)if v then passed=passed+1 else failed=failed+1;print('FAIL '..n)end end
local Types=assert(loadfile('lib/Types.lua'))()
local function setup(supported,id)
 love={graphics={}}
 function love.graphics.getSupported()return{instancing=supported,glsl3=supported}end
 function love.graphics.newMesh()return{release=function()end,attachAttribute=function()return true end}end
 function love.graphics.newShader()return{send=function()end,release=function()end}end
 function love.graphics.drawInstanced()end;function love.graphics.setBlendMode()end;function love.graphics.setDepthMode()end;function love.graphics.setShader()end;function love.graphics.setColor()end
 local V={weatherFxId=id};local cache={}
 function V.require(name)
  if cache[name]then return cache[name]end
  if name=='Types'then return Types end
  if name=='Quality'then return{budget=function()return{worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,worldBlizzardCap=200000,worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,rain=1100,grain=800,splash=1}end}end
  if name=='Settings'then return{isFirstPerson=function()return false end,splashOn=function()return false end,leafColor=function()return'green'end,snowShape=function()return'flake'end}end
  if name=='Scene'then return{now={visible='world'}}end
  if name=='WindEngine'then return{peek=function()return{x=.7,z=.2,strength=.8}end,vector=function(s)return .7*(s or 1),.2*(s or 1)end}end
  if name=='InstanceSeedBuffer'then local m=assert(loadfile('lib/InstanceSeedBuffer.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralSnowField'then local m=assert(loadfile('lib/ProceduralSnowField.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralPrecipField'then local m=assert(loadfile('lib/ProceduralPrecipField.lua'))(V);cache[name]=m;return m end
  error('no module '..name,0)
 end
 local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
 if supported then
  local P=V.require('ProceduralPrecipField');local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
  check(P.probe(Vox,{kind='rain',eye={0,4,0},focus={0,0,0},wind={0,0},nearRadius=4,farRadius=600,topY=120,bottomY=-20,span=24,time=0,intensity=2})==true,'successful GPU probe enables precipitation virtualization')
 end
 W.update(1/60,{0,0,0},{},{anchorKind='player',deckY=120,deckSpan=24});return W
end
for _,c in ipairs{{id='RAIN_HEAVY',key='rain',idx=nil},{id='HAIL',key='hail',idx=1},{id='SANDSTORM',key='sand',idx=2},{id='ASHFALL',key='ash',idx=4}}do
 local W=setup(true,c.id);local p=W.precipVirtualization();local st=W.spawnStatus();local v
 if c.key=='rain'then v=p.rain else v={logical=p.grain.logical[c.idx],simulated=p.grain.simulated[c.idx],procedural=p.grain.procedural[c.idx]}end
 check((st[c.key]or 0)>0,c.id..' keeps live authored logical population')
 check(v.logical==st[c.key],c.id..' virtualization logical count equals spawn authority')
 check(v.procedural==v.logical,c.id..' procedural field owns exact complete visual population')
 if c.key=='rain' then check(v.simulated<=96,c.id..' keeps only <=96 CPU interaction probes') else check(v.simulated==0,c.id..' keeps zero CPU visual cards') end
end
local W=setup(true,'GALE');local p=W.precipVirtualization();check(p.grain.procedural[3]==0 and p.grain.simulated[3]==p.grain.logical[3],'leaves remain fully physical for collision/settling')
local F=setup(false,'SANDSTORM');local f=F.precipVirtualization();check(f.grain.procedural[2]==0 and f.grain.simulated[2]<=800 and f.grain.simulated[2]<f.grain.logical[2],'unsupported GPU uses bounded quality-tier sand fallback instead of full world population')
print(('precip virtualization: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
