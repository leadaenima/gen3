-- Weather FX 8.1.83 developer-sweep regression: ownership, smooth snow,
-- rendered-world grain coverage, reversible OFF, 3D battles and sun optics.
local envRoot=os.getenv and os.getenv('WFX_TEST_ROOT') or nil
if envRoot=='' then envRoot=nil end
local ROOT=envRoot or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end
if ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(rel)local f=assert(io.open(ROOT..rel,'rb'));local s=f:read('*a');f:close();return s end

local settings=read('lib/Settings.lua');local main=read('main.lua');local draw=read('lib/Draw.lua')
local battle=read('lib/Battle.lua');local bd=read('lib/BattleDraw.lua');local da=read('lib/DramalessAtmos.lua')
local wp=read('lib/voxel_atmos/WorldPrecip.lua');local pp=read('lib/ProceduralPrecipField.lua')

local manifest=read('manifest.json');local ma,mi,mp=manifest:match('\"version\"%s*:%s*\"(%d+)%.(%d+)%.(%d+)\"');ma,mi,mp=tonumber(ma) or 0,tonumber(mi) or 0,tonumber(mp) or 0;ck(ma>8 or (ma==8 and (mi>1 or (mi==1 and mp>=83))),'manifest includes Weather FX 8.1.83 feature baseline')

-- 1. OFF must be reversible through the same SettingsMenu path players use.
do
  local values={always='auto',fronts='off'}
  local level=1
  local P={}
  function P.setLevel(_,v) level=v end
  function P.level() return level end
  function P.syncOptions() end
  package.loaded['src.render.Pipelines']=P
  local game={save={options={pipelines={weather=1},modOptions={weather_fx={}}}},mods={modOptions={weather_fx={}},loader={modOptions={weather_fx={}}}}}
  package.loaded['src.core.Game']=game
  local mod={id='weather_fx',options={}}
  function mod.options:get(k)return values[k]end
  function mod.options:set(k,v)values[k]=v;return true end
  mod.events={on=function()end};mod.log={warn=function()end,info=function()end}
  local cache={}
  local V={mod=mod,safeCall=pcall}
  function V.require(n)
    if cache[n] then return cache[n] end
    if n=='Types' then local t={PINNED={'CLEAR','RAIN_LIGHT'}};function t.get(id)return {id=id,label=id} end;cache[n]=t;return t end
    if n=='WeatherState' then local w={LEVEL_IDS={false,'AUTO','CYCLE','CLEAR','RAIN_LIGHT'}};cache[n]=w;return w end
    if n=='Config' then local c={get=function()return {}end};cache[n]=c;return c end
    if n=='Quality' then local q={};cache[n]=q;return q end
    if n=='DramalessAtmos' then local a={};cache[n]=a;return a end
    local f=assert(loadfile(ROOT..'lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m
  end
  local S=V.require('Settings'); local M=V.require('SettingsMenu')
  ck(M.applyOption(game,'always','off')==true and level==0,'WEATHER OFF writes live engine rung 0')
  ck(M.applyOption(game,'always','auto')==true and level==1,'WEATHER OFF -> AUTO immediately restores live engine rung')
  ck(M.applyOption(game,'always','RAIN_LIGHT')==true and level==4,'WEATHER OFF -> named weather immediately restores named live rung')
  ck(game.save.options.pipelines.weather==4,'re-enabled weather is persisted to engine pipeline options')
  ck(type(S.reconcileWeatherLadder)=='function' and (S.reconcileWeatherLadder(P,game.save.options,0)==0 or level==4),'reconciliation API exists to stop stale OFF ladder mirror')
end

-- 2. Virtualized grain simulation radius must never become visual radius.
ck(wp:find('visualRadius={0,0,0,0}',1,true)~=nil,'grain keeps independent visual radius state')
ck(wp:find('grain.visualRadius[kind]=(kind==3) and STREAM_RADIUS or desiredRainR',1,true)~=nil,'hail/sand/ash visual radius captures full authored radius before virtualization')
ck(wp:find('grain.simTarget[kind]=0',1,true)~=nil,'GPU hail/sand/ash path removes noninteractive CPU visual cards without reducing logical target')
ck(wp:find('grain.simRadius[kind]=4',1,true)~=nil,'GPU grain interaction radius remains low-cost')
ck(wp:find('o.farRadius=(grain.visualRadius[kind] or grain.simRadius[kind] or STREAM_RADIUS)',1,true)~=nil,'procedural grain draw uses visual radius rather than interaction radius')
ck(wp:find('o.worldGrid=(WP._uniformPrecipField==true and kind~=3)',1,true)~=nil,'fronts-off hail/sand/ash select rendered-world grid ownership')
ck(pp:find('if(fieldWorldGrid>0.5){',1,true)~=nil,'procedural shader world grid applies to all supported non-debris grain families')
ck(pp:find("local worldGrid=opts.worldGrid==true and tostring(opts.kind or 'rain')~='debris'",1,true)~=nil,'procedural CPU submission enables absolute world grid for rain/hail/sand/ash')

-- 3. Snow motion uses monotonic presentation time, not raw simulation chunks.
ck(wp:find('function WP._snowVisualTime()',1,true)~=nil,'3D snow has dedicated presentation clock')
ck(wp:find('if c.last and t<c.last then t=c.last end',1,true)~=nil,'3D snow presentation clock cannot move backward')
ck(wp:find('local snowTime=WP._snowVisualTime()',1,true)~=nil,'snow draw samples presentation clock every frame')
local snowTimeUses=select(2,wp:gsub('o%.time=snowTime',''))
ck(snowTimeUses>=2,'both procedural snow probe and visible draw use smoothed presentation time')

-- Executable snow clock proof: visible time continues between simulation ticks
-- and can never reverse if a platform timer jitters backward.
do
  local wall=100
  love={graphics={},timer={getTime=function()return wall end}}
  local Types=assert(loadfile(ROOT..'lib/Types.lua'))()
  local V={safeCall=pcall}
  function V.require(n)
    if n=='Types' then return Types end
    if n=='Quality' then return {budget=function()return{worldPrecip=.001}end} end
    if n=='Settings' then return {isFirstPerson=function()return false end,splashOn=function()return false end} end
    error('no module '..tostring(n),0)
  end
  local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
  if type(W._snowVisualTime)=='function' then
    local a=W._snowVisualTime();wall=100.016;local b=W._snowVisualTime();wall=100.010;local c=W._snowVisualTime()
    ck(type(a)=='number' and b>a and math.abs((b-a)-.016)<1e-6,'3D snow visible clock advances continuously while simulation time is unchanged')
    ck(c==b,'3D snow visible clock clamps backward wall-timer jitter')
  else
    ck(false,'3D snow visible clock advances continuously while simulation time is unchanged')
    ck(false,'3D snow visible clock clamps backward wall-timer jitter')
  end
end

-- Executable absolute-grid proof for every affected virtualized grain family.
do
  love={graphics={getSupported=function()return{instancing=true,glsl3=true}end,newMesh=function()return{release=function()end,attachAttribute=function()return true end,setVertices=function()end,setDrawRange=function()end}end,newShader=function()return{send=function()return true end,release=function()end}end,drawInstanced=function()return true end,draw=function()return true end,setBlendMode=function()end,setDepthMode=function()end,setShader=function()end,setColor=function()end}}
  local cache={}
  local V={safeCall=pcall}
  function V.require(n)
    if cache[n] then return cache[n] end
    if n=='InstanceSeedBuffer' then local m={get=function()return{release=function()end},8192 end};cache[n]=m;return m end
    error('no module '..tostring(n),0)
  end
  local P=assert(loadfile(ROOT..'lib/ProceduralPrecipField.lua'))(V)
  local Vox={eye={420,8,-260},vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
  for _,kind in ipairs({'hail','sand','ash'}) do
    local ok=P.draw(Vox,{kind=kind,count=2048,eye=Vox.eye,focus={0,0,0},wind={1,.4},nearRadius=4,farRadius=300,topY=120,bottomY=-40,span=24,time=2,intensity=1,uniformField=true,worldGrid=true})
    local g=P.stats().lastGrid
    ck(ok==true and type(g)=='table' and g.far==300,kind..' procedural visuals use full rendered-world radius')
    local bx,bz=g and g.baseX,g and g.baseZ
    P.draw(Vox,{kind=kind,count=2048,eye=Vox.eye,focus={999,0,999},wind={1,.4},nearRadius=4,farRadius=300,topY=120,bottomY=-40,span=24,time=2.1,intensity=1,uniformField=true,worldGrid=true})
    local g2=P.stats().lastGrid
    ck(g2 and g2.baseX==bx and g2.baseZ==bz,kind..' rendered-world field does not move when player/focus direction changes')
  end
end

-- 4. World-backed voxel battles are 3D-owned without breaking classic battles.
ck(draw:find('Scene.now.visible == "battle" and not worldBackedBattle3d()',1,true)~=nil,'battle checks distinguish opaque classic battle from world-backed 3D battle')
ck(select(2,draw:gsub('Scene%.now%.visible == "battle" and not worldBackedBattle3d%(%)',''))>=6,'precip/snow/grain/lightning/fog ownership all share world-backed battle rule')
ck(battle:find('Scene.now.battleOpaque==false',1,true)~=nil,'Battle exposes world-backed 3D ownership only for nonopaque battle')
ck(battle:find('if Battle.world3dWeatherOwns and Battle.world3dWeatherOwns() then',1,true)~=nil,'battle overlay suppresses flat weather under 3D ownership')
ck(not battle:find('Battle.world3dWeatherOwns and Battle.world3dWeatherOwns() then\n          pcall(function() BD.reset()',1,true),'3D battle suppression no longer destroys battle weather channels')
ck(bd:find('function BD.weatherId(battle)',1,true)~=nil,'BattleDraw exposes battle-owned weather identity to 3D atmosphere')
ck(da:find('syncWorldBackedBattleWeather(step)',1,true)~=nil and da:find('BD.tick,step,battle',1,true)~=nil,'3D atmosphere advances battle weather once per update')
ck(da:find('weatherFxChannels=(not hardOff and BD.channels and BD.channels()) or nil',1,true)~=nil,'3D world-backed battle consumes BattleDraw eased channels')

-- 5. Direct-look sun optics use real camera orientation and screen-effects policy.
ck(da:find('local function cameraViewDirection(Voxel3D)',1,true)~=nil,'sun optics have host-safe true camera-forward resolver')
ck(da:find('cam.forward or cam.look',1,true)~=nil,'sun optics prefer explicit 3D host camera vector')
ck(da:find('FP and type(FP.yaw)=="number"',1,true)~=nil,'sun optics can derive full 3D forward from first-person yaw/pitch')
ck(da:find('h2>=l2*.0625',1,true)~=nil,'sun optics reject implausible near-vertical player-anchor focus vectors')
ck(da:find('local fx,fy,fz=cameraViewDirection(Voxel3D)',1,true)~=nil,'glare alignment uses true camera resolver instead of raw focus')
ck(da:find('fallbackSunScreen(Voxel3D,sun,w,h)',1,true)~=nil,'sun glare has projection fallback when host VP projection is unavailable')
ck(da:find('screenEffectsScale()',1,true)~=nil,'3D sun glare obeys WEATHER SCREEN EFFECTS accessibility control')

-- Executable camera resolver checks: bogus downward focus must not beat a real camera.
do
  local V={mod={},safeCall=pcall,safeBind=function()return pcall end,require=function()return nil end}
  local A=assert(loadfile(ROOT..'lib/DramalessAtmos.lua'))(V)
  if type(A._cameraViewDirection)=='function' and type(A._fallbackSunScreen)=='function' then
    local x,y,z=A._cameraViewDirection({eye={0,12,0},focus={0,0,0},camera={forward={0.6,0.3,0.8}},lookFlat={0,0,1}})
    local l=x and math.sqrt(x*x+y*y+z*z) or 0
    ck(x and math.abs(l-1)<1e-9 and y>0.2,'explicit host camera forward beats player-anchor focus and stays normalized')
    A._NightSky={_FirstPerson={yaw=0,pitch=-math.rad(30)}}
    local fx,fy,fz=A._cameraViewDirection({eye={0,12,0},focus={0,0,0},lookFlat={0,0,1}})
    ck(fx and fy>0.49 and fz>0.85,'first-person pitch supplies elevated look direction when focus is player anchor')
    local sx,sy=A._fallbackSunScreen({eye={0,12,0},focus={0,0,0},lookFlat={0,0,1}}, {dx=fx,dy=fy,dz=fz}, 640,480)
    ck(sx and math.abs(sx-320)<1e-6 and math.abs(sy-240)<1e-6,'sun projection fallback centers a sun exactly on true camera forward')
  else
    ck(false,'explicit host camera forward beats player-anchor focus and stays normalized')
    ck(false,'first-person pitch supplies elevated look direction when focus is player anchor')
    ck(false,'sun projection fallback centers a sun exactly on true camera forward')
  end
end

-- Execute the actual 3D glare pass: a directly aligned, unobstructed sun must
-- produce rays/wash even when the host projector cannot decode its VP matrix.
do
  local mods={}
  local V={mod={},safeCall=pcall,safeBind=function()return pcall end,require=function(n)return mods[n] end}
  local A=assert(loadfile(ROOT..'lib/DramalessAtmos.lua'))(V)
  mods.Config={visual=function(k)return k=='glare' end}
  mods.Settings={screenEffectsScale=function()return 1 end}
  mods.WeatherState={ch={psy=0}}
  mods.NightSky={projectDirection=function()return nil end}
  mods.CelestialEngine={state=function()return {solarDiscVisibility=1,solarRayRamp=1,sun={dx=0,dy=0,dz=1,alpha=1,discTransmission=1,horizonFraction=1}} end}
  local rays,rects,circles=0,0,0
  love={graphics={
    getShader=function()return nil end,getDepthMode=function()return 'lequal',true end,getBlendMode=function()return 'alpha','alphamultiply' end,getColor=function()return 1,1,1,1 end,
    setShader=function()end,setDepthMode=function()end,setBlendMode=function()end,setColor=function()end,
    rectangle=function()rects=rects+1 end,polygon=function()rays=rays+1 end,circle=function()circles=circles+1 end,
  }}
  A._lastState={entities={}};A._lastPosed={}
  if type(A._draw3dScenePost)=='function' then
    A._draw3dScenePost({eye={0,10,0},focus={0,0,0},camera={forward={0,0,1}},lookFlat={0,0,1},size=function()return 640,480 end},true)
    ck(A._lastSunGlareReason=='drawing' and (A._lastSunGlare or 0)>.9,'actual 3D direct-look sun pass reaches active glare state')
    ck(rays>=28 and rects>=2 and circles>0,'actual 3D direct-look sun pass draws god rays, staged wash and lens response')
    mods.Settings.screenEffectsScale=function()return 0 end;rays,rects,circles=0,0,0
    A._draw3dScenePost({eye={0,10,0},focus={0,0,0},camera={forward={0,0,1}},size=function()return 640,480 end},true)
    ck(A._lastSunGlareReason=='screen-effects-off' and rays==0 and circles==0,'SCREEN EFFECTS OFF suppresses camera optics without changing sun/world state')
  else
    ck(false,'actual 3D direct-look sun pass reaches active glare state')
    ck(false,'actual 3D direct-look sun pass draws god rays, staged wash and lens response')
    ck(false,'SCREEN EFFECTS OFF suppresses camera optics without changing sun/world state')
  end
end

-- 6. Static integration guard for the pre-state reconciliation ordering.
local ri=main:find('Settings.reconcileWeatherLadder',1,true)
ck(ri~=nil,'runtime reconciles pending weather menu authority')
local wi=nil
if ri then wi=main:find('EngineRuntime.update',ri,true) end
ck(ri~=nil and wi~=nil and ri<wi,'weather OFF/on reconciliation runs before staged runtime consumes pipeline level')

print(string.format('8.1.83 feature-integrity sweep: %d passed, %d failed',pass,fail))
os.exit(fail==0 and 0 or 1)
