local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

-- ---------------------------------------------------------------------------
-- Follower overworld weather chip: damage, immunity, and no-faint floor.
-- ---------------------------------------------------------------------------
do
  local cfg={followerChip={enabled=true,seconds=1,fraction=0.1,canFaint=false}}
  local currentDef={id='SANDSTORM',sandy=true}
  local Game={save={party={{species='PIDGEY',hp=50,stats={hp=100}}}},data={pokemon={PIDGEY={types={'NORMAL'}},GEODUDE={types={'ROCK','GROUND'}}}}}
  package.loaded['src.core.Game']=Game
  local V={mod={}}
  function V.require(name)
    local m={
      Types={}, Config={get=function() return cfg end}, Settings={},
      Scene={drawScale=function() return 1,true end},
      WeatherState={level=1,current=function() return currentDef end},
    }
    if m[name] then return m[name] end error(name)
  end
  local F=assert(loadfile('lib/Follower.lua'))(V)
  for _=1,4 do F.update(0.25) end
  check(Game.save.party[1].hp==40,'sandstorm chips non-immune lead outside battle')
  Game.save.party[1]={species='GEODUDE',hp=50,stats={hp=100}}
  for _=1,4 do F.update(0.25) end
  check(Game.save.party[1].hp==50,'sandstorm respects Rock/Ground follower immunity')
  Game.save.party[1]={species='PIDGEY',hp=5,stats={hp=100}}
  cfg.followerChip.fraction=1
  for _=1,4 do F.update(0.25) end
  check(Game.save.party[1].hp==1,'follower weather cannot faint by default')
  currentDef={id='SNOW_LIGHT',frozen=true}
  Game.save.party[1].hp=50
  for _=1,4 do F.update(0.25) end
  check(Game.save.party[1].hp==50,'plain snow does not incorrectly deal hail chip')
end

-- ---------------------------------------------------------------------------
-- Encounter hooks: rate boost, fishing boost, hard indoor gate.
-- ---------------------------------------------------------------------------
do
  local hooks={}
  local mod={hooks={wrap=function(self,name,fn) hooks[name]=fn end},content={pokemon={each=function() return function() return nil end end}}}
  local def={id='RAIN_HEAVY',wet=true,chipType='WATER'}
  local cfg={encounters={enabled=true,species=false,fishing=true,strength=1,rateBoost=1.5,fishingBonus=1,inject=false,bans=false}}
  local Scene={now={indoors=false,mapId='ROUTE_1'}}
  local State={level=1,id='RAIN_HEAVY',pinnedBy=nil,current=function() return def end}
  local Types={channel=function(d,k) return 0 end,get=function() return def end}
  local Legendary={claimEncounter=function() return nil end}
  local V={mod=mod}
  function V.require(name)
    local m={Types=Types,Config={get=function() return cfg end,locationFor=function() return nil end},Scene=Scene,WeatherState=State,Legendary=Legendary}
    if m[name] then return m[name] end error(name)
  end
  love={math={random=function() return 0 end}}
  local E=assert(loadfile('lib/Encounters.lua'))(V)
  E.install()
  check(type(hooks['encounter.roll'])=='function','encounter.roll wrapper is really installed')
  check(type(hooks['encounter.fishing'])=='function','encounter.fishing wrapper is really installed')
  check(math.abs(E.rateMultiplier()-1.5)<0.001,'active outdoor weather applies configured encounter-rate boost')
  local calls=0
  local out=hooks['encounter.roll'](function()
    calls=calls+1
    if calls==1 then return nil end
    return {species='PIDGEY',level=3}
  end,{}, {rng=function() return 0 end})
  check(out and out.species=='PIDGEY' and calls==2,'weather rate boost retries a missed encounter instead of inventing one')
  local fishCalls=0
  local fish=hooks['encounter.fishing'](function()
    fishCalls=fishCalls+1
    return {species='MAGIKARP',level=(fishCalls==1 and 5 or 8)}
  end,'OLD_ROD','ROUTE_1',{})
  check(fish and fish.level==8 and fishCalls==2,'wet weather fishing bonus actually rerolls and keeps stronger catch')
  Scene.now.indoors=true
  check(E.rateMultiplier()==1,'indoor encounter rate is never boosted by exterior weather')
end

-- ---------------------------------------------------------------------------
-- Pokegear integration: both map overlay and forecast card register.
-- ---------------------------------------------------------------------------
do
  local appended,registered=nil,nil
  local api={apiVersion=1,DEFAULT_ICON='WX',helpers={},state=function() return {} end}
  api.append=function(spec) appended=spec; return {id=spec.id} end
  api.register=function(spec) registered=spec; return true end
  local Fronts={weatherFor=function() return 'RAIN_LIGHT',{id='PALLET',land='kanto',label='PALLET'} end,snapshot=function() return {} end,byId={}}
  local Scene={now={mapId='PALLET_TOWN'}}
  local Types={get=function() return {label='RAIN'} end}
  local State={id='RAIN_LIGHT'}
  local Config={get=function() return {pokegear={enabled=true}} end}
  local mod={id='weather_fx',find=function(id) if id=='pokegear_cards' then return {exports=api} end end,log={warn=function() end,info=function() end}}
  local V={mod=mod}
  function V.require(name)
    local m={Config=Config,Fronts=Fronts,Scene=Scene,Types=Types,WeatherState=State}
    if m[name] then return m[name] end error(name)
  end
  local G=assert(loadfile('lib/Pokegear.lua'))(V)
  check(G.install()==true,'Pokegear integration installs against API v1')
  check(appended and appended.host=='map' and appended.kind=='overlay','Pokegear weather map overlay registers')
  check(registered and registered.id=='weather_fx' and registered.label=='WEATHER','Pokegear WEATHER forecast card registers')
  check(G.installed==true,'Pokegear integration reports installed after both registrations')
  api.apiVersion=2
  local G2=assert(loadfile('lib/Pokegear.lua'))(V)
  check(G2.install()==false,'unknown Pokegear API version fails closed instead of guessing')
end

print(('gameplay features: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
