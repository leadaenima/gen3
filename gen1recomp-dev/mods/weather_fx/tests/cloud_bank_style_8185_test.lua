local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function ck(v,msg) if v then passed=passed+1;print('PASS '..msg) else failed=failed+1;print('FAIL '..msg) end end

local drawCalls=0
love={graphics={
  getDimensions=function() return 1280,720 end,
  newShader=function() return {send=function() end} end,
  newMesh=function() return {setVertices=function() return true end,release=function() end} end,
  setBlendMode=function() end,setDepthMode=function() end,
  draw=function() drawCalls=drawCalls+1;return true end,
}}
local values={}
local defined
local Types={PINNED={},byId={},get=function() return nil end}
local mod={id='weather_fx',options={
  define=function(self,rows) defined=rows;return true end,
  get=function(self,key) return values[key] end,
},events={on=function() end},log={info=function() end,warn=function() end}}
local V={mod=mod,weatherFxId='CLEAR',weatherFxChannels={}}
local S
local generic={}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=0,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
function V.require(n)
  if n=='Types' then return Types end
  if n=='DayNight' then return {tint=function() return {1,1,1} end} end
  if n=='WeatherState' then return {LEVEL_IDS={false,'AUTO'}} end
  if n=='Settings' then return S end
  if n=='WeatherSetting' then return WeatherSetting end
  if n=='ForestAtmos' then return ForestAtmos end
  if n=='MesoscaleField' then return {ready=function() return false end} end
  if n=='PerformanceGovernor' then return {scale=function() return 1 end} end
  if n=='Quality' then return {budget=function() return {worldPrecip=1} end} end
  if n=='Scene' then return {now={visible='world',outdoor=true}} end
  return generic
end
V.safeCall=pcall
S=assert(loadfile(ROOT..'lib/Settings.lua'))(V)
S.define()

local by={}; for _,row in ipairs(S.SCHEMA) do by[row.key]=row end
ck(#S.SCHEMA==78,'schema has 78 player settings after RAVE controls removal')
ck(by.cloudBankStyle~=nil,'CLOUD BANK STYLE exists')
ck(by.cloudBankStyle and by.cloudBankStyle.default=='volumetric','default preserves the 8.1.84 volumetric bank')
ck(by.cloudBankStyle and #by.cloudBankStyle.choices==2 and by.cloudBankStyle.choices[1][2]=='volumetric' and by.cloudBankStyle.choices[2][2]=='blocky','style exposes VOLUMETRIC and BLOCKY')
ck(by.cloudBankStyle and (by.cloudBankStyle.help or ''):find('flat',1,true)~=nil and (by.cloudBankStyle.help or ''):find('translucent',1,true)~=nil,'help describes flat translucent block geometry')
local found=0
for _,g in ipairs(S.GROUPS) do for _,k in ipairs(g.keys) do if k=='cloudBankStyle' then found=found+1;ck(g.id=='world','CLOUD BANK STYLE is in WORLD & CLOUDS') end end end
ck(found==1,'CLOUD BANK STYLE appears in exactly one submenu')
values.cloudBankStyle='blocky';ck(type(S.cloudBankStyle)=='function' and S.cloudBankStyle()=='blocky','BLOCKY resolves through runtime settings helper')
values.cloudBankStyle='volumetric';ck(type(S.cloudBankStyle)=='function' and S.cloudBankStyle()=='volumetric','VOLUMETRIC resolves through runtime settings helper')

local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local hasBuilder=type(C._buildBlockCloudRows)=='function'
local hasDraw=type(C._drawBlockClouds)=='function'
ck(hasBuilder,'block cloud geometry builder is executable')
ck(hasDraw,'block cloud draw path is executable')
local frame={level=1,rayColor={1,.9,.8},weather={cloudShade=1}}
local clouds={{ix=4,iz=7,cx=100,cy=150,cz=220,spanX=100,spanY=34,spanZ=60,deckBlend=.35,fadeAlpha=1,styleA=.2,styleB=.5,styleC=.7}}
if hasBuilder then
  local rows,n=C._buildBlockCloudRows(frame,clouds)
  ck(n>0 and n%6==0,'block cloud builds complete horizontal tile triangles')
  local minY,maxY=1e9,-1e9; local minA,maxA=1,0
  local ys={}
  for i=1,n do local r=rows[i]; minY=math.min(minY,r[2]);maxY=math.max(maxY,r[2]);minA=math.min(minA,r[5]);maxA=math.max(maxA,r[5]);ys[r[2]]=true end
  ck((maxY-minY)<2.0,'block cloud bank remains genuinely flat')
  ck(minA>0 and maxA<=.78,'block cloud alpha stays slightly translucent and bounded')
  local ycount=0;for _ in pairs(ys) do ycount=ycount+1 end
  ck(ycount==1,'one descriptor is a single shallow cloud plane rather than stacked puffs')
  local xset,zset={},{}
  for i=1,n do xset[rows[i][1]]=true;zset[rows[i][3]]=true end
  local xc,zc=0,0;for _ in pairs(xset) do xc=xc+1 end;for _ in pairs(zset) do zc=zc+1 end
  ck(xc>=4 and zc>=3,'block silhouette spans a rectangular pixel grid')
else
  for _,msg in ipairs({'block cloud builds complete horizontal tile triangles','block cloud bank remains genuinely flat','block cloud alpha stays slightly translucent and bounded','one descriptor is a single shallow cloud plane rather than stacked puffs','block silhouette spans a rectangular pixel grid'}) do ck(false,msg) end
end

local f=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','r'));local cin=f:read('*a');f:close()
ck(cin:find('if CinematicAtmos._cloudBankStyle()=="blocky"',1,true)~=nil,'BLOCKY selects dedicated renderer before volumetric fallback')
ck(cin:find('buildCloudDescriptors',1,true)~=nil and cin:find('_appendFrontCloudDescriptors',1,true)~=nil,'block renderer shares authoritative local/front cloud descriptors')
ck(cin:find('setDepthMode,"lequal",false',1,true)~=nil,'block cloud renderer stays in the world depth pipeline')
if hasDraw and type(C._cloudBankStyle)=='function' then
  values.cloudBankStyle='blocky'
  local vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function() return true end,endEffect=function() end}
  local okDraw=C._drawCloudBank(vox,frame,clouds)
  ck(okDraw==true and drawCalls==1,'BLOCKY executes the dedicated mesh draw path')
  values.cloudBankStyle='volumetric'
else ck(false,'BLOCKY executes the dedicated mesh draw path') end

print(('cloud bank style 8.1.85: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
