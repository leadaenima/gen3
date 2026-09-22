local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

-- ---------------------------------------------------------------------------
-- Scene viewport: the render.hud-fed geometry must be usable, not a dead setter.
-- ---------------------------------------------------------------------------
do
  local V={mod={}}
  function V.require(name)
    if name=='Config' then return {get=function() return {indoorMaps={}} end} end
    if name=='Interop' then return {} end
    error('unexpected '..tostring(name))
  end
  local Scene=assert(loadfile('lib/Scene.lua'))(V)
  Scene.setViewport({gameX=12,gameY=18,gameWidth=640,gameHeight=576,scale=4,dpiX=2,dpiY=2,width=1280,height=720})
  check(Scene.viewport and Scene.viewport.x==12 and Scene.viewport.y==18,'Scene.setViewport stores render.hud origin')
  check(Scene.viewport and Scene.viewport.w==640 and Scene.viewport.h==576,'Scene.setViewport stores playfield dimensions')
  check(Scene.viewport and Scene.viewport.dpiX==2 and Scene.viewport.windowW==1280,'Scene.setViewport preserves DPI/window metadata')
end

-- ---------------------------------------------------------------------------
-- Regional fronts: map resolution, autonomous ticking, save/restore.
-- ---------------------------------------------------------------------------
do
  local saved={}
  local cfg={fronts={enabled=true,drift=0}}
  local Config={get=function() return cfg end}
  local Types={DEFAULT='CLEAR'}
  function Types.get(id)
    local known={CLEAR=true,RAIN_LIGHT=true,SNOW_LIGHT=true}
    if not known[id] then id='CLEAR' end
    return {id=id,label=id,minMin=1,maxMin=1}
  end
  local mod={save={set=function(self,k,v) saved[k]=v end,get=function(self,k,d) if saved[k]==nil then return d end return saved[k] end}}
  local V={mod=mod}
  function V.require(name) if name=='Types' then return Types elseif name=='Config' then return Config end error(name) end
  love={math={random=function() return 0.5 end}}
  local Fronts=assert(loadfile('lib/Fronts.lua'))(V)
  Fronts.pick=function(map,exclude) return exclude and 'RAIN_LIGHT' or 'SNOW_LIGHT' end
  check(Fronts.regionFor('ROUTE_30_NORTH').id=='CHERRYGROVE','front regions resolve extended route map ids by prefix')
  check(Fronts.regionFor('CERULEAN_CITY').id=='CERULEAN','front regions resolve Kanto map ids')
  Fronts.update(0.1,1)
  local snap=Fronts.snapshot()
  check(#snap==#Fronts.REGIONS,'front update materializes every regional sky')
  local active=0
  for _,r in ipairs(snap) do if r.weather~='CLEAR' then active=active+1 end end
  check(active>0,'fresh world opens with real regional weather instead of all-clear dead state')
  local before=select(1,Fronts.weatherFor('ROUTE_30'))
  check(before~=nil,'front weatherFor returns live regional weather')
  Fronts.persist()
  check(type(saved.fronts)=='string' and #saved.fronts>20,'front state persists atomically')
  Fronts.state={}; Fronts.fresh=true; Fronts.restore()
  check(select(1,Fronts.weatherFor('ROUTE_30'))==before,'front save/restore recovers regional weather')
end

-- ---------------------------------------------------------------------------
-- Psystorm: guaranteed chamber and per-arrival state.
-- ---------------------------------------------------------------------------
do
  local cfg={psystorm={enabled=true,carrierChance=0.7,scale=1}}
  local V={mod={},require=function(name) if name=='Config' then return {get=function() return cfg end} end error(name) end}
  love={math={random=function() return 0.99 end}}
  local P=assert(loadfile('lib/Psystorm.lua'))(V)
  check(P.placeChance('CERULEAN_CAVE_B1F_ROOM')==1,'Mewtwo chamber psystorm chance is guaranteed')
  check(P.weatherFor('CERULEAN_CAVE_B1F_ROOM')=='PSYSTORM','Mewtwo chamber actually activates PSYSTORM')
  check(P.weatherFor('CERULEAN_CAVE_B1F_ROOM')=='PSYSTORM','psystorm remains stable for the same map arrival')
  check(P.weatherFor('PALLET_TOWN')==nil,'psystorm releases on non-qualifying map')
  cfg.psystorm.enabled=false
  check(P.weatherFor('CERULEAN_CAVE_B1F_ROOM')==nil,'psystorm config OFF is a hard gate')
end

-- ---------------------------------------------------------------------------
-- Legendary weather: rouse, encounter claim, one-per-rousing, expiry.
-- ---------------------------------------------------------------------------
do
  local cfg={legendary={enabled=true,chance=1,encounters=true,rateBoost=1.05,encounterChance=1,level=50,minutes=1}}
  local Scene={now={indoors=false,mapId='ROUTE_1'}}
  local Battle={isGen2=function() return false end}
  local logs=0
  local V={mod={log={info=function() logs=logs+1 end}}}
  function V.require(name)
    if name=='Config' then return {get=function() return cfg end} end
    if name=='Scene' then return Scene end
    if name=='Battle' then return Battle end
    error(name)
  end
  love={math={random=function() return 0.01 end}}
  local L=assert(loadfile('lib/Legendary.lua'))(V)
  local weather=L.update('ROUTE_1',false)
  check(weather~=nil and L.roused~=nil,'legendary chance=100% rouses a live weather event')
  local species,level=L.claimEncounter()
  check(type(species)=='string' and level==50,'roused legendary can substitute one configured encounter')
  check(L.claimEncounter()==nil,'legendary rousing is spent after one encounter')
  L.tick(999)
  check(L.roused==nil and L.spent==false,'legendary rousing expires and fully resets')
end

-- ---------------------------------------------------------------------------
-- Seasons: live multiplier and hard OFF gate.
-- ---------------------------------------------------------------------------
do
  local seasonsOn=true
  local seasonNote='on'
  local hemi='northern'
  local Config={get=function() return {seasons={enabled=true,notify=true,daysPerSeason=28},time={source='cycle',cycleMinutes=24}} end}
  local Settings={is=function(key,val)
    if key=='seasons' then return (seasonsOn and 'on' or 'off')==val end
    if key=='hemisphere' then return hemi==val end
    if key=='seasonNotify' then return seasonNote==val end
    return false
  end,get=function(key) if key=='seasons' then return seasonsOn and 'on' or 'off' elseif key=='hemisphere' then return hemi elseif key=='seasonNotify' then return seasonNote end end}
  local Types={channel=function(def,key) return (def.ch and def.ch[key]) or 0 end}
  local TOD={source='cycle',elapsed=0}
  local mod={save={get=function() return nil end,set=function() end},log={info=function() end},find=function() return nil end}
  local V={mod=mod}
  function V.require(name)
    local m={Config=Config,Settings=Settings,Types=Types,TimeOfDay=TOD}
    if m[name] then return m[name] end
    error(name)
  end
  local S=assert(loadfile('lib/Seasons.lua'))(V)
  S.id='WINTER'
  check(S.multiplier({frozen=true,ch={}})>1,'winter actually increases frozen-weather AUTO weight')
  -- Hemisphere flips the same in-game date by six months. Day zero of the
  -- accelerated year is spring in the north and autumn in the south.
  seasonsOn=true; TOD.elapsed=0; S._bootstrapped=true; S._lastPersisted='SPRING'
  hemi='northern'; S.update(0,nil)
  check(S.id=='SPRING','HEMISPHERE northern resolves cycle day zero to spring')
  hemi='southern'; S.update(0,nil)
  check(S.id=='AUTUMN','HEMISPHERE southern flips cycle day zero to autumn')
  hemi='northern'
  seasonsOn=false
  check(S.multiplier({frozen=true,ch={}})==1,'SEASONS OFF removes seasonal weighting')
  -- Turning the notification setting off while a banner is live must hide it
  -- immediately; it is a live UI switch, not only a future-event preference.
  S.notifyT=3; S.notifyText='WINTER has begun!'; S.notifyPlace='PALLET TOWN'
  seasonNote='off'
  check(S.drawNotify()==false and S.notifyT==0 and S.notifyText==nil and S.notifyPlace==nil,
    'SEASON NOTE OFF immediately clears an active season banner')
end

-- ---------------------------------------------------------------------------
-- Tornado: flat 2D Gale uses relocation-only visited-map safety.
-- The full world-space Gale lifecycle is covered by tornado_3d_test.lua.
-- ---------------------------------------------------------------------------
do
  local setting='on'; local started=0; local callback=nil; local carried=nil
  local cfg={tornado={enabled=true,everySeconds=120,minVisited=2,carryChance=.10,sandstorms=true,funnel=true,funnelSeconds=2}}
  local Settings={is=function(k,v) return k=='tornado' and setting==v end,tornadoPickupChance=function() return 1 end}
  local ow={map={id='ROUTE_1',isWaterCell=function() return false end},player={cellX=1,cellY=2,facing='down',surfing=false}}
  function ow:partyKnows() return false end
  local Scene={now={visible='world',indoors=false,outdoor=true,mapId='ROUTE_1'},overworld=function() return ow end}
  local pickup=nil; local optsSeen=nil
  local Funnel={active=false,update=function() end}
  function Funnel.start(sec,fn,opts) started=started+1; callback=fn; optsSeen=opts; pickup=opts and opts.onPickup; Funnel.active=true end
  local State={level=1,current=function() return {id='GALE'} end}
  local game={save={visited={ROUTE_1=true,PALLET=true,CERULEAN=true}},data={maps={
    ROUTE_1={id='ROUTE_1',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={right={map='PALLET',offset=0}},warps={}},
    PALLET={id='PALLET',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='ROUTE_1',offset=0}},warps={}},
    CERULEAN={id='CERULEAN',outdoor=true,tileset='OVERWORLD',width=8,height=8,connections={left={map='ROUTE_1',offset=0}},warps={}},
  },field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}},flyWarps={PALLET={x=3,y=4},CERULEAN={x=5,y=6}}}}}
  local Map={}
  function Map.isOutside(def) return def and def.outdoor==true end
  function Map.isOutdoor(def) return def and def.outdoor==true end
  function Map.defIsWaterCell() return false end
  function Map.defIsWalkableCell(def,ts,x,y) return x>=0 and y>=0 and x<def.width and y<def.height end
  function Map.defPassable(def,ts,x,y) return x>=0 and y>=0 and x<def.width and y<def.height end
  package.preload['src.world.Map']=function() return Map end
  local save={}; local world={warpTo=function(self,d,x,y) assert(type(x)=='number' and type(y)=='number');carried=d;return true end}
  local mod={game=game,world=world,save={set=function(self,k,v) save[k]=v end,get=function(self,k,d) return save[k] or d end},log={info=function() end}}
  local V={mod=mod}
  function V.require(name)
    local m={Config={get=function() return cfg end},Settings=Settings,Scene=Scene,Funnel=Funnel,WeatherState=State,VoxelAtmosBridge={active=function() return false end}}
    if m[name] then return m[name] end error(name)
  end
  love={math={random=function() return 0 end}}
  local T=assert(loadfile('lib/Tornado.lua'))(V);T._setRandom(function() return 0 end)
  local d=T.destinations('ROUTE_1')
  check(#d==2 and d[1]~='ROUTE_1','tornado destinations require visited escape-safe outdoor maps and exclude current map')
  for _=1,480 do T.update(0.25) end
  check(started==1 and type(callback)=='function' and type(pickup)=='function','2D Gale starts a funnel only after relocation is approved')
  check(optsSeen and optsSeen.mode=='relocate2d','2D Gale relocation uses camera-locked sweep/blackout/sweep-in mode')
  pickup()
  check(carried~=nil and save.tornadoFrom=='ROUTE_1','mid-funnel pickup carries only through guarded visited-map path and records origin')
  callback(); Funnel.active=false
  check(not T.isCarrying(),'2D relocation carry clears after funnel exits')
  setting='off'; T.timer=10; T.update(0.1)
  check(T.timer==0,'TORNADOES OFF immediately clears spawn timer')
end

print(('world features: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
