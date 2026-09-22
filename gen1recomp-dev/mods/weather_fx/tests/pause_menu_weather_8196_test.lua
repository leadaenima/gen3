local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local ow={isOverworld=true,map={id='VIRIDIAN_CITY',def={environment='TOWN'}},camera={x=0,y=0},player={px=80,py=80}}
local Game={stack={states={ow}},overworld=ow}
package.loaded['src.core.Game']=Game
package.loaded['src.battle.BattleState']=nil
package.loaded['src.world.Map']={isOutdoor=function(def) return def.outdoor==true or def.tileset=='OVERWORLD' end}
package.loaded['src.render.TextBox']={}
local Config={get=function() return {battleView='auto'} end}
local Interop={wideBattle=function() return false end}
local Battle={current=function() return nil end}
local modules={Config=Config,Interop=Interop,Battle=Battle}
local mod={world={overworld=function() return ow end},find=function() return nil end}
local V={mod=mod}
function V.require(name)
  if modules[name] then return modules[name] end
  local m=assert(loadfile('lib/'..name..'.lua'))(V); modules[name]=m; return m
end
local Scene=V.require('Scene')

local fakeSettings={battleScale=function() return 1 end,debugRain=function() return false end,get=function(_,key) if key=='indoors' then return 'tint' end end}
-- Settings.get is called with dot syntax in Scene; provide a second compatible form.
fakeSettings.get=function(key) if key=='indoors' then return 'tint' end end

local function sample(states)
  Game.stack.states=states
  Scene.sample()
  return Scene.now
end

local n=sample({ow})
check(n.visible=='world' and not n.pauseMenu,'plain overworld is visible and not paused')

n=sample({ow,{screenId='StartMenu'}})
check(n.visible=='world','Gen1 StartMenu keeps world visible')
check(n.pauseMenu==true,'Gen1 StartMenu is pause context')
local scale,precip=Scene.drawScale(fakeSettings)
check(scale>0 and precip==true,'2D precipitation remains eligible under pause menu')

n=sample({ow,{screenId='OptionsMenu'}})
check(n.visible=='world' and n.pauseMenu,'pause submenu keeps weather visible')

n=sample({ow,{screenId='StartMenu'},{kind='savePanel'}})
check(n.visible=='world' and n.pauseMenu,'anonymous helper above pause anchor remains pause context')

n=sample({ow,{screenId='Gen2StartMenu'}})
check(n.visible=='world' and n.pauseMenu,'Gen2 StartMenu keeps weather visible')

n=sample({ow,{screenId='SomeUnrelatedFullScreenMenu'}})
check(n.visible=='hidden' and not n.pauseMenu,'unrelated unknown UI remains fail-closed')

Scene.resetWeatherAnimationClock(10)
check(math.abs(Scene.updateWeatherAnimationClock(.25,false,10)-10.25)<1e-9,'visual clock advances during gameplay')
check(math.abs(Scene.updateWeatherAnimationClock(.50,true,10)-10.25)<1e-9,'visual clock freezes in paused/frozen mode')
check(Scene.animationPaused==true,'animationPaused flag is true while frozen')
check(math.abs(Scene.updateWeatherAnimationClock(.25,false,10)-10.50)<1e-9,'visual clock resumes from frozen phase')

local Settings=V.require('Settings')
local row=Settings.row('pauseMenuWeather')
check(row~=nil,'pause-menu weather setting exists')
check(row and row.default=='animated','pause-menu weather default preserves animated behavior')
local vals={}
if row then for _,c in ipairs(row.choices or {}) do vals[c[2]]=true end end
check(vals.animated and vals.frozen,'pause-menu setting exposes ANIMATED and FROZEN')
local group=Settings.group('weather')
local found=false
if group then for _,k in ipairs(group.keys or {}) do if k=='pauseMenuWeather' then found=true end end end
check(found,'pause-menu weather setting is in WEATHER in-game group')

local main=assert(io.open('main.lua','r')):read('*a')
local rt=assert(io.open('lib/EngineRuntime.lua','r')):read('*a')
local ca=assert(io.open('lib/voxel_atmos/CinematicAtmos.lua','r')):read('*a')
check(main:find('pauseWeatherFrozen',1,true)~=nil and main:find('animationPaused = pauseWeatherFrozen',1,true)~=nil,'main routes pause setting into runtime')
check(rt:find('Draw.update(c.animDt,c.level)',1,true)~=nil,'2D draw update receives frozen animation dt')
check(rt:find('c.dt=c.animationPaused and 0 or realDt',1,true)~=nil,'frozen mode holds Weather FX climate/channel evolution as well as motion')
check(rt:find('VoxelAtmos.update(c.animDt)',1,true)~=nil,'3D atmosphere receives frozen animation dt')
check(rt:find('Tornado.update(c.animDt)',1,true)~=nil,'visible tornado animation receives frozen animation dt')
check(ca:find('local dt = CinematicAtmos._weatherAnimationDt',1,true)~=nil,'3D procedural precipitation uses update-owned animation dt')
check(ca:find('_raveAnimationFrozen',1,true)==nil,'removed RAVE-specific pause clock is absent')

print(('pause menu weather 8.1.96: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
