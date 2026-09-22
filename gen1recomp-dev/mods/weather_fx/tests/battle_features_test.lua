local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local hooks, events = {}, {}
local function on(name,fn)
  events[name]=events[name] or {}
  events[name][#events[name]+1]=fn
end
local cfg={
  battle={
    enabled=true,seedFromOverworld=true,seededTurns=nil,
    effects={typePower=true,accuracy=true,solarBeam=true,residual=true,defenseBoost=true,speed=true,evasion=true,healing=true,heldItems=true,amplified=false,terrain=true,announce=false},
    terrain={},residualDamage={fraction=1/16,canFaint=true,sandImmune={'ROCK','GROUND','STEEL'},psyImmune={'PSYCHIC'},hailImmune={'ICE'}},
    suppressSet={CLOUD_NINE=true},suppressAbilities={'CLOUD_NINE'},items={extenders={DAMP_ROCK='RAINY',HEAT_ROCK='SUNNY',ICY_ROCK='HAIL',SMOOTH_ROCK='SANDSTORM'},extendBy=3,umbrella='UTILITY_UMBRELLA'},
  }
}
local Config={get=function() return cfg end,battleEffect=function(k) return cfg.battle.effects[k]~=false end}
local damageOn=true
local Settings={
  battleDamageOn=function() return damageOn end,battleAnimOn=function() return true end,
  alwaysWeather=function() return nil end,isFirstPerson=function() return false end,
  get=function(k) if k=='amplified' then return 'off' end return nil end,
}
local Types={battleWeather=function(id)
  local m={RAIN_HEAVY='HEAVY_RAIN',RAIN_LIGHT='RAINY',SUN='SUNNY',SANDSTORM='SANDSTORM'}
  return m[id]
end}
Types.get=function(id)
  local chip=({SANDSTORM='ROCK',HAIL='ICE',PSYSTORM='PSYCHIC'})[id]
  return {id=id,battle=Types.battleWeather(id),chipType=chip,frozen=(id=='HAIL')}
end
Types.forBattleWeather=function(w)
  local chip=({SANDSTORM='ROCK',HAIL='ICE',PSYSTORM='PSYCHIC'})[w]
  return {id=w,label=w,battle=w,chipType=chip,frozen=(w=='HAIL')}
end
local State={id='RAIN_LIGHT'}
local Scene={now={mapId='ROUTE_1',indoors=false,owKnown=true}}
local Compat={refresh=function() end,hasAnimeRealism=function() return false end}
local mod={
  id='weather_fx',find=function() return nil end,
  hooks={wrap=function(self,name,fn) hooks[name]=fn end},
  events={on=function(self,name,fn) on(name,fn) end},
  content={
    maps={each=function() return function() return nil end end},
  },
  save={set=function() end},
  log={info=function() end,warn=function() end,error=function() end},
}
local V={mod=mod}
function V.require(name)
  local m={Types=Types,Config=Config,Settings=Settings,WeatherState=State,Scene=Scene,Compat=Compat}
  if m[name] then return m[name] end
  error('unexpected require '..tostring(name))
end
package.loaded['src.core.Game']={save={}}
local B=assert(loadfile('lib/Battle.lua'))(V)
B._hostCrystal=false
check(B.install()==true,'Battle.install succeeds')
for _,name in ipairs({'battle.damage','battle.accuracy','battle.turn_order','battle.charge_required'}) do
  check(type(hooks[name])=='function',name..' wrapper installed')
end
for _,name in ipairs({'battle.started','battle.ended','battle.turn_ended','battle.move_used'}) do
  check(events[name] and #events[name]>0,name..' event handler installed')
end

local battle={field={weather='RAINY'},data={pokemon={}},player={},enemy={}}

-- Solar Beam charge flow: sunny weather skips only the intended charge move.
local charge=hooks['battle.charge_required']
battle.field.weather='SUNNY'
check(charge(function() return true end,{battle=battle,user={},target={},move={id='SOLARBEAM',type='GRASS'}})==false,'Solar Beam skips charge in sun')
battle.field.weather='HARSH_SUN'
check(charge(function() return true end,{battle=battle,user={},target={},move={id='SOLAR_BLADE',type='GRASS'}})==false,'Solar Blade skips charge in harsh sun')
battle.field.weather='RAINY'
check(charge(function() return true end,{battle=battle,user={},target={},move={id='SOLARBEAM',type='GRASS'}})==true,'Solar Beam keeps charge outside sun')
check(charge(function() return true end,{battle=battle,user={},target={},move={id='SKY_ATTACK',type='FLYING'}})==true,'non-Solar charge moves are untouched')
damageOn=false
battle.field.weather='SUNNY'
check(charge(function() return true end,{battle=battle,user={},target={},move={id='SOLARBEAM',type='GRASS'}})==true,'BATTLE WEATHER DMG off leaves Solar Beam charge untouched')
damageOn=true
battle.field.weather='RAINY'

local damage=hooks['battle.damage']
local function base100(ctx) return 100,{typeMult=10} end
local d=damage(base100,{battle=battle,user={},target={},move={id='SURF',type='WATER',category='special'}})
check(d==150,'rain increases Water damage to 1.5x')
d=damage(base100,{battle=battle,user={},target={},move={id='EMBER',type='FIRE',category='special'}})
check(d==50,'rain reduces Fire damage to 0.5x')
local z=damage(function() return 0,{} end,{battle=battle,user={},target={},move={id='WITHDRAW',type='WATER',category='status'}})
check(z==0,'weather never turns zero-damage status move into damage')

local acc=hooks['battle.accuracy']
check(acc(function() return false end,{battle=battle,user={},target={},move={id='THUNDER',type='ELECTRIC'}})==true,'Thunder is guaranteed in rain')
battle.field.weather='HARSH_SUN'
check(acc(function() return true end,{battle=battle,user={},target={},move={id='SURF',type='WATER'}})==false,'harsh sun nullifies Water attack')

battle.field.weather='STRONG_WINDS'
local sw=damage(function() return 100,{typeMult=20} end,{battle=battle,user={},target={curTypes={'FLYING'}},move={id='THUNDERBOLT',type='ELECTRIC',category='special'}})
check(sw==50,'Strong Winds removes Flying-type super-effective bonus')

-- Turn order: Swift Swim holder should move first under rain, but priority still wins.
battle.field.weather='RAINY'
battle.data.pokemon={FAST={ability='SWIFT_SWIM'},SLOW={}}
local a,b={mon={species='FAST'}},{mon={species='SLOW'}}
local order=hooks['battle.turn_order']
check(order(function() return false end,a,{priority=0},b,{priority=0},{battle=battle})==true,'Swift Swim overrides same-priority vanilla order in rain')
check(order(function() return false end,a,{priority=0},b,{priority=1},{battle=battle})==false,'weather speed never overrides move priority')

-- Utility Umbrella removes weather for its holder only.
local umbrella={mon={species='SLOW',heldItem='UTILITY_UMBRELLA'}}
check(B.weatherFor(battle,umbrella)==nil,'Utility Umbrella suppresses weather for holder')
check(B.weather(battle)=='RAINY','Utility Umbrella does not erase field weather globally')

-- Opening announcements follow the battle authority too. With seeding disabled,
-- a stormy overworld must not announce rain into a dry battle; explicit field
-- weather still announces normally.
cfg.battle.effects.announce=true
cfg.battle.seedFromOverworld=false
local said={}
local dry={field={},data={pokemon={}},sayNext=function(self,text) said[#said+1]=text end}
for _,fn in ipairs(events['battle.started'] or {}) do fn({battle=dry}) end
check(#said==0,'dry battle does not announce overworld weather when seeding is disabled')
local wet={field={weather='RAINY'},data={pokemon={}},sayNext=function(self,text) said[#said+1]=text end}
for _,fn in ipairs(events['battle.started'] or {}) do fn({battle=wet}) end
check(#said>0,'explicit battle weather still receives opening announcement')
cfg.battle.effects.announce=false
cfg.battle.seedFromOverworld=true

-- Terrain is independent of sky but still obeys BATTLE WEATHER DMG.
cfg.battle.terrain.ROUTE_1={GRASS=1.20}
B.mapId='ROUTE_1'
battle.field.weather=nil
local terrainHit=damage(function() return 100,{} end,{battle=battle,user={},target={},move={id='VINE_WHIP',type='GRASS',category='physical'}})
check(terrainHit==120,'configured map terrain bonus applies even under a clear battle sky')
damageOn=false
terrainHit=damage(function() return 100,{} end,{battle=battle,user={},target={},move={id='VINE_WHIP',type='GRASS',category='physical'}})
check(terrainHit==100,'BATTLE WEATHER DMG off disables terrain mechanics too')
damageOn=true

-- Sandstorm Rock special-defense behavior is a damage reduction, never a stat mutation.
battle.field.weather='SANDSTORM'
local rock={curTypes={'ROCK'},mon={species='ROCKMON'}}
local sp=damage(function() return 100,{} end,{battle=battle,user={},target=rock,move={id='PSYCHIC',type='PSYCHIC',category='special'}})
local phys=damage(function() return 100,{} end,{battle=battle,user={},target=rock,move={id='TACKLE',type='NORMAL',category='physical'}})
check(sp==66 and phys==100,'sandstorm Rock special-defense boost affects special damage only')

-- Residual weather and ability healing run from the live turn-ended event.
local normal={curTypes={'NORMAL'},mon={species='NORMALMON',hp=160,stats={hp=160}},isPlayer=true}
local rockImm={curTypes={'ROCK'},mon={species='ROCKMON',hp=160,stats={hp=160}},isPlayer=false}
battle.player,battle.enemy=normal,rockImm
battle.data.pokemon.NORMALMON={}; battle.data.pokemon.ROCKMON={}
local msgs={}; battle.sayNext=function(self,t) msgs[#msgs+1]=t end
for _,fn in ipairs(events['battle.turn_ended'] or {}) do fn({battle=battle}) end
check(normal.mon.hp==150,'sandstorm residual chips non-immune battler by 1/16')
check(rockImm.mon.hp==160,'sandstorm residual spares Rock type')

battle.field.weather='RAINY'
local healer={curTypes={'WATER'},mon={species='HEALMON',hp=100,stats={hp=160}},isPlayer=true}
battle.data.pokemon.HEALMON={ability='RAIN_DISH'}; battle.player=healer; battle.enemy=nil
for _,fn in ipairs(events['battle.turn_ended'] or {}) do fn({battle=battle}) end
check(healer.mon.hp==110,'Rain Dish heals 1/16 max HP in rain')

-- Weather rock extender fires from battle.move_used exactly on matching weather.
battle.field={weather='RAINY',weatherTurns=5}; healer.mon.heldItem='DAMP_ROCK'
for _,fn in ipairs(events['battle.move_used'] or {}) do fn({battle=battle,user=healer}) end
check(battle.field.weatherTurns==8,'matching weather rock extends field weather turns')

-- Cloud Nine suppresses field mechanics without deleting the actual field weather.
battle.field.weather='RAINY'; battle.player=healer; battle.enemy=nil; battle.data.pokemon.HEALMON={ability='CLOUD_NINE'}
check(B.weather(battle)==nil and battle.field.weather=='RAINY','Cloud Nine suppresses Weather FX mechanics without erasing field weather')

print(('battle features: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
