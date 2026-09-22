local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end
local values={always='off'}
local defined={}
local registered={}
local onceCb=nil
local hookWrap=nil
local mod={id='weather_fx',path='.',
  options={define=function(self,rows) defined=rows return true end,get=function(self,key) return values[key] end},
  events={on=function() end,once=function(self,name,fn) if name=='mods.loaded' then onceCb=fn end end},
  hooks={wrap=function(self,name,fn) if name=='ui.options.rows' then hookWrap=fn end end},
  content={screens={register=function(self,id,def) registered[id]=def end}},
  ui={insertBefore=function(rows,before,row) table.insert(rows,1,row); return rows end},
  log={info=function() end,warn=function() end},
}
local Types={PINNED={},byId={}}; function Types.get() end
local modules={Types=Types}
local V={mod=mod}
function V.require(name)
  if modules[name] then return modules[name] end
  local m=assert(loadfile('lib/'..name..'.lua'))(V); modules[name]=m; return m
end
local Settings=V.require('Settings'); modules.Settings=Settings
Settings.define()
local pushed={}
package.loaded['src.ui.Screens']={push=function(game,id) pushed[#pushed+1]=id; if registered[id] then game.stack._top=registered[id].new(game) end; return game.stack._top end}
package.loaded['src.ui.OptionRows']={clampScroll=function(index,scroll) return scroll end,draw=function() end}
package.loaded['src.mods.ManagerState']={openOptions=function() return 'fallback' end}
package.loaded['src.render.PaletteFX']={wholeNamed=function() return {} end}

local Menu=V.require('SettingsMenu')
check(Menu.install()==true,'SettingsMenu installs')
check(registered[Menu.ROOT_ID]~=nil,'root settings screen registered')
check(#Settings.GROUPS==11,'eleven easy-to-understand settings submenus')
for _,g in ipairs(Settings.GROUPS) do check(registered['WeatherFXSettingsGroup_'..g.id]~=nil,'submenu registered '..g.id) end
check(type(hookWrap)=='function','OPTIONS opener hook installed')
check(type(onceCb)=='function','mod manager route waits for mods.loaded')

local game={save={options={}},mods={},input={wasPressed=function() return false end},stack={pop=function() end}}
local root=registered[Menu.ROOT_ID].new(game)
check(root and #root.rows==#Settings.GROUPS,'root shows one row per submenu')
check(root.rows[1].help and #root.rows[1].help>10,'submenu row has description')
root.rows[1].activate(game)
check(pushed[#pushed]=='WeatherFXSettingsGroup_weather','submenu opener pushes group screen')
local general=game.stack._top
check(general and #general.rows==8,'WEATHER submenu contains current grouped core settings without removed RAVE controls')
for _,row in ipairs(general.rows) do check(type(row.help)=='string' and #row.help>10,'setting description present '..tostring(row.label)) end

-- A custom screen edit must hit both persistence and live Settings authority.
local intensity
for _,row in ipairs(general.rows) do if row.label=='WEATHER STRENGTH' then intensity=row end end
check(intensity~=nil,'WEATHER STRENGTH found in WEATHER submenu')
intensity.step(game,1)
check(game.save.options.modOptions and game.save.options.modOptions.weather_fx and game.save.options.modOptions.weather_fx.intensity~=nil,'submenu edit writes persistent mod option backing store')
check(Settings.get('intensity')==game.save.options.modOptions.weather_fx.intensity,'submenu edit reaches live Settings.get immediately')

-- Help popup is reachable with SELECT and retains the row description.
general.index=1
game.input.wasPressed=function(self,key) return key=='select' end
general:update(0)
check(general.helpRow==general.rows[1],'SELECT opens help for selected setting')

-- OPTIONS hook adds a single opener rather than flattening every setting.
local out=hookWrap(function(g,r) return r end,game,{{id='MODS',label='MODS'}})
local count=0
for _,r in ipairs(out or {}) do if r.id=='weather_fx:settings' then count=count+1 end end
check(count==1,'base OPTIONS contains one Weather FX submenu opener')

onceCb()
local MS=package.loaded['src.mods.ManagerState']
local owner={game=game}
MS.openOptions(owner,{id='weather_fx'})
check(pushed[#pushed]==Menu.ROOT_ID,'Weather FX mod-manager card routes to grouped settings')

print(('settings menu: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
