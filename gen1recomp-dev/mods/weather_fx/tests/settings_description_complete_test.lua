local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local values={always='off'}
local registered={}
local mod={id='weather_fx',path='.',
  options={define=function() return true end,get=function(self,key) return values[key] end},
  events={on=function() end,once=function() end},
  hooks={wrap=function() end},
  content={screens={register=function(self,id,def) registered[id]=def end}},
  ui={insertBefore=function(rows,before,row) table.insert(rows,1,row); return rows end},
  log={info=function() end,warn=function() end},
}
local Types={PINNED={'CLEAR'},byId={CLEAR={label='Clear'}}}; function Types.get(id) return Types.byId[id] end
local modules={Types=Types}
local V={mod=mod}
function V.require(name)
  if modules[name] then return modules[name] end
  local m=assert(loadfile('lib/'..name..'.lua'))(V);modules[name]=m;return m
end
local S=V.require('Settings');modules.Settings=S
S.define()
package.loaded['src.ui.Screens']={push=function(game,id) if registered[id] then game.stack._top=registered[id].new(game) end; return game.stack._top end}
package.loaded['src.ui.OptionRows']={clampScroll=function(i,s) return s end,draw=function() end}
package.loaded['src.mods.ManagerState']={openOptions=function() end}
package.loaded['src.render.PaletteFX']={wholeNamed=function() return {} end}
local M=V.require('SettingsMenu')
check(M.install()==true,'grouped settings UI installs')
check(#S.SCHEMA==78,'all 78 current player settings are present')
check(#S.GROUPS==11,'settings remain sorted into 11 focused submenus')

local membership={}
for _,g in ipairs(S.GROUPS) do
  check(type(g.id)=='string' and g.id~='','submenu has stable id '..tostring(g.label))
  check(type(g.label)=='string' and #g.label>=3,'submenu has readable label '..tostring(g.id))
  check(type(g.help)=='string' and #g.help>=25,'submenu has useful description '..tostring(g.id))
  check(type(g.keys)=='table' and #g.keys>0,'submenu is not empty '..tostring(g.id))
  local game={save={options={}},mods={},input={wasPressed=function() return false end},stack={pop=function() end}}
  local def=registered['WeatherFXSettingsGroup_'..g.id]
  check(type(def)=='table' and type(def.new)=='function','submenu screen registered '..g.id)
  local screen=def and def.new and def.new(game)
  check(screen and #screen.rows==#g.keys,'submenu renders every declared setting '..g.id)
  for i,key in ipairs(g.keys) do
    membership[key]=(membership[key] or 0)+1
    local row=S.row(key)
    check(row~=nil,'submenu key resolves to setting '..key)
    if row then
      check(type(row.help)=='string' and #row.help>=30,'setting has detailed description '..key)
      check(not row.help:lower():find('todo',1,true) and not row.help:lower():find('placeholder',1,true),'setting help is not placeholder '..key)
      check(type(row.choices)=='table' and #row.choices>=2,'setting exposes choices '..key)
      local labels,vals={},{}
      for _,c in ipairs(row.choices or {}) do
        local label,val=c[1],c[2]
        check(type(label)=='string' and label~='','choice has readable label '..key)
        check(val~=nil,'choice has stored value '..key..':'..tostring(label))
        check(not labels[tostring(label)],'choice label unique '..key..':'..tostring(label));labels[tostring(label)]=true
        check(not vals[tostring(val)],'choice value unique '..key..':'..tostring(val));vals[tostring(val)]=true
      end
      local uirow=screen and screen.rows and screen.rows[i]
      check(uirow and type(uirow.label)=='string' and #uirow.label>=2,'submenu keeps a readable setting label '..key)
      check(uirow and uirow.help==row.help,'submenu exposes exact setting description '..key)
    end
  end
end
for _,row in ipairs(S.SCHEMA) do
  check(membership[row.key]==1,'setting appears in exactly one submenu '..row.key)
end

print(('complete settings descriptions: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
