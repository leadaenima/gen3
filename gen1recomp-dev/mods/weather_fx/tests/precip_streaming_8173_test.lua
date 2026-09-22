-- Weather FX 8.1.73: accumulation radius, map-entry continuity, fixed rain field.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function near(a,b,e) return math.abs((tonumber(a)or -999)-(tonumber(b)or -777))<=(e or 1e-6) end

-- 1) WorldPrecip accumulation must use the effective snow render radius, not 108.
do
  local deposits={};local groundRadius=nil
  local SnowPack={ACCUMULATION_ENABLED=true}
  function SnowPack.setEnabled() return true end
  function SnowPack.beginFrame() return {collisionEnabled=true} end
  function SnowPack.update() end
  function SnowPack.depositAggregate(_,x,z) deposits[#deposits+1]={x=x,z=z}; return {},{} end
  SnowPack.deposit=SnowPack.depositAggregate
  function SnowPack.fillGroundPool(pool,cap,ctx,x,z,r) groundRadius=r;pool.active=0;return 0 end
  function SnowPack.fillFootPool(pool) pool.active=0;return 0 end
  local Settings={isFirstPerson=function() return false end,splashOn=function() return false end,cloudHeightScale=function() return 1.5 end,
    snowAccumulationEnabled=function() return true end,weatherRenderDistanceScale=function() return .5 end,
    get=function(k) if k=='fronts' then return 'off' end return 'config' end}
  local Config={get=function() return {fronts={enabled=false}} end}
  local Quality={budget=function() return {worldPrecip=.001,worldRadiusCap=128,worldSnowCap=48,worldBlizzardCap=48,worldRainCap=48,worldHailCap=48,worldSandCap=48,worldAshCap=48,worldDebrisCap=48,snowPackDrawCap=64,footDrawCap=0,splash=0} end}
  local V={safeCall=pcall}
  function V.require(name)
    if name=='Settings' then return Settings elseif name=='Config' then return Config elseif name=='Quality' then return Quality elseif name=='SnowPack' then return SnowPack end
    error('no module '..tostring(name),0)
  end
  local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
  local meta={anchorKind='live-player',deckY=120,deckSpan=2,Voxel3D={far=1000},player={px=0,py=0},map={id='A'}}
  for i=1,180 do W.update(.1,{8,0,8},{wxId='SNOW',snowIntensity=1.9},meta) end
  ck(near(W.snowVirtualization().fieldRadius,500),'fronts OFF 50% snow field is 500 at voxel far 1000')
  ck(near(groundRadius,500),'SnowPack draw/staging radius receives exact effective weather distance')
  local farthest=0
  for _,d in ipairs(deposits) do local dx,dz=d.x-8,d.z-8;farthest=math.max(farthest,math.sqrt(dx*dx+dz*dz)) end
  ck(farthest>220 and farthest<=500.01,'aggregate deposits spread well beyond old 108-unit circle and stay inside weather radius')
end

-- 2) Live gameplay player X/Z must win over a stale voxel focus on map entry.
do
  local Settings={isFirstPerson=function() return false end,splashOn=function() return false end,cloudHeightScale=function() return 1.5 end,
    snowAccumulationEnabled=function() return false end,weatherRenderDistanceScale=function() return 1 end,
    get=function(k) if k=='fronts' then return 'off' end return 'config' end}
  local Config={get=function() return {fronts={enabled=false}} end}
  local Quality={budget=function() return {worldPrecip=.001,worldRadiusCap=96,worldRainCap=24,worldSnowCap=24,worldBlizzardCap=24,worldHailCap=24,worldSandCap=24,worldAshCap=24,worldDebrisCap=24,snowPackDrawCap=0,footDrawCap=0,splash=0} end}
  local V={safeCall=pcall}
  function V.require(name) if name=='Settings'then return Settings elseif name=='Config'then return Config elseif name=='Quality'then return Quality end error('no '..name,0) end
  local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
  local function firstRainX()
    for _,s in ipairs(W.sample(16)) do if s:match('^Rain#') then return tonumber(s:match('pos=%(([-0-9.]+),')) end end
  end
  W.update(.016,{0,0,0},{wxId='RAIN',rainIntensity=1},{anchorKind='player',deckY=120,deckSpan=2,Voxel3D={far=96},player={px=320,py=160},map={id='A'}})
  local x1=firstRainX();ck(x1 and x1>220,'first map-entry rain spawns around live gameplay player, not stale focus')
  W.update(.016,{0,0,0},{wxId='RAIN',rainIntensity=1},{anchorKind='player',deckY=120,deckSpan=2,Voxel3D={far=96},player={px=640,py=160},map={id='B'}})
  local x2=firstRainX();ck(x2 and x2>540,'map change immediately re-primes rain at destination without player movement')
end

-- 3) Procedural rain/hail field keeps a fixed world anchor while player walks.
do
  local sent={};local drawCalls=0
  love={graphics={}}
  function love.graphics.getSupported() return {instancing=true} end
  function love.graphics.newMesh() return {attachAttribute=function() return true end,release=function() end} end
  function love.graphics.newShader() return {send=function(self,n,v) if n=='fieldFocus' then sent[#sent+1]={v[1],v[2],v[3]} end return true end,release=function() end} end
  function love.graphics.drawInstanced(_,n) drawCalls=drawCalls+1 end
  function love.graphics.setBlendMode() end;function love.graphics.setDepthMode() end;function love.graphics.setShader() end;function love.graphics.setColor() end
  local V={}
  function V.require(name)
    if name=='InstanceSeedBuffer' then return {get=function() return {},8192 end} end
    if name=='MesoscaleField' then return {ready=function() return false end} end
    error('no '..name,0)
  end
  local P=assert(loadfile(ROOT..'lib/ProceduralPrecipField.lua'))(V)
  local vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}}
  local opts={kind='rain',count=32,eye={0,10,0},focus={10,0,10},wind={0,0},nearRadius=1,farRadius=400,topY=100,bottomY=-10,span=20,time=0,intensity=1,tint={1,1,1}}
  ck(P.draw(vox,opts)==true,'procedural rain initial fixed field draws')
  local a1=sent[#sent]
  sent={};opts.focus={50,0,20};opts.time=.2;P.draw(vox,opts);local a2=sent[#sent]
  ck(a1 and a2 and near(a1[1],a2[1]) and near(a1[3],a2[3]),'walking inside anchor cell does not translate procedural rain field')
  sent={};opts.focus={300,0,20};opts.time=.3;P.draw(vox,opts)
  sent={};opts.time=2.2;P.draw(vox,opts);local a3=sent[#sent]
  ck(a3 and a3[1]>=255,'crossing stream cell hands rain to a new fixed world anchor instead of following every step')
  -- Low weather-distance settings must still keep the player inside the fixed
  -- stream cell. A fixed 256-unit grid with a 96-unit rain radius could leave
  -- the player outside the weather disk near a cell edge.
  sent={};opts.focus={95,0,0};opts.farRadius=96;opts.time=3.0;P.reanchor(opts.focus,opts.farRadius);P.draw(vox,opts);local low=sent[#sent]
  local lowDist=low and math.sqrt((low[1]-opts.focus[1])^2+(low[3]-opts.focus[3])^2) or 1e9
  ck(lowDist<48.1,'adaptive fixed anchor remains inside reduced 96-unit weather radius')
end

-- 4) Source-level safety: manual/fronts-OFF cannot submit stale distant snow slab.
do
  local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
  ck(src:find('if CinematicAtmos._frontsEnabled and not CinematicAtmos._frontsEnabled() then return false end',1,true)~=nil,'distant weather draw is hard-gated OFF when WEATHER FRONTS is OFF')
  ck(src:find('worldPrecipAnchor(Voxel3D,player)',1,true)~=nil,'CinematicAtmos passes live player into precipitation anchor')
  ck(src:find('world%-precip%-preflight')~=nil,'procedural precipitation is preflighted before update/allocation on map/weather start')
end

print(('precip streaming 8.1.73: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
