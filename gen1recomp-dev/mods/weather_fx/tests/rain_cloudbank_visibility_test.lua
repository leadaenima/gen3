-- 8.1.5 live visibility regression: selecting rain must immediately populate a
-- real cloud-to-ground column. Geometry existing only at the cloud ceiling is
-- not enough to prove that a forward-facing voxel/FPV camera can see rain.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function check(v,n) if v then pass=pass+1 else fail=fail+1;io.write('FAIL: ',n,'\n') end end
local function mesh(fmt,a)
  local m={cap=type(a)=='number' and a or #(a or {})}
  function m:setVertices(v,s,n) if n and n>self.cap then error('overflow',0) end end
  function m:setDrawRange() end
  return m
end
love={graphics={newMesh=function(fmt,a)return mesh(fmt,a)end,newShader=function()return{send=function()end}end,
 setBlendMode=function()end,setDepthMode=function()end,setShader=function()end,setColor=function()end,draw=function()end}}
local V={weatherFxId='RAIN_LIGHT'}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))()
function V.require(n)
 if n=='Types' then return Types end
 if n=='Quality' then return {budget=function()return{worldPrecip=.01}end} end
 if n=='Settings' then return {isFirstPerson=function()return true end,splashOn=function()return false end} end
 if n=='Scene' then return {now={visible='world'}} end
 error('no module '..tostring(n),0)
end
local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
local anchor={0,0,0};local deck={anchorKind='player',deckY=120,deckSpan=2}
W.update(1/120,anchor,{},deck)
local minY,maxY=1e9,-1e9;local n=0
for _,line in ipairs(W.sample(12)) do
 if line:match('^Rain#') then
  local y=tonumber(line:match('pos=%([^,]+,([%-0-9.]+),'))
  if y then minY=math.min(minY,y);maxY=math.max(maxY,y);n=n+1 end
 end
end
check(n>=8,'first rain activation has enough physical near-field drops to inspect')
check(maxY>108,'first rain activation keeps drops near the real cloud-bank origin')
check(minY<88,'first rain activation also warm-starts drops down the cloud-to-ground column')
check((maxY-minY)>30,'first rain frame spans enough vertical depth to be immediately visible')
local fpv={eye={0,12,0},focus={0,0,0},player={0,0,0},lookFlat={0,0,1},far=260,
 vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}}
W.draw(fpv,{weather={}})
local st=W.drawStatus()
check((st.rain.verts or 0)>0 and st.rain.healthy==true,'warm-started rain still reaches healthy strict-3D draw submission')
-- Pool memory is intentionally retained when weather turns off. A later rain
-- activation must still refresh/prime that stale pool rather than resume old
-- hidden drop positions from the previous storm.
V.weatherFxId='CLEAR';W.update(1/60,anchor,{},deck)
local offLo,offHi,offN=W.rainColumnRange();check(offN==0 and offLo==nil and offHi==nil,'CLEAR immediately releases live rain ownership')
V.weatherFxId='RAIN_LIGHT';W.update(1/120,anchor,{},deck)
local rlo,rhi,rn=W.rainColumnRange()
check(rn>=8 and rhi>108 and rlo<88 and (rhi-rlo)>30,'rain reactivation refreshes stale pool into visible cloud-to-ground column')
-- Normal simulation/recycling after the initial fill must continue to use the
-- actual cloud deck. The production source is checked structurally here so a
-- later change cannot accidentally warm-start every recycled drop.
local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
check(src:find('primeRain',1,true)~=nil,'rain activation has an explicit one-shot prime state')
check(src:find('spawnRainAt(i, rainSpawnX, py, rainSpawnZ, rainI, windX, windZ, rain.simRadius, false)',1,true)~=nil,
 'ordinary rain recycling explicitly respawns at cloud bank without warm-start, using stable world anchor')
io.write(string.format('rain cloudbank visibility: %d passed, %d failed\n',pass,fail))
os.exit(fail==0 and 0 or 1)
