-- Weather FX 8.1.49 complete player-settings interaction audit.
-- Exercises every exposed choice through the same SettingsMenu.applyOption path
-- used by the in-game submenu, then checks persistence and live Settings state.
local passed,failed=0,0
local function check(ok,msg)
  if ok then passed=passed+1 else failed=failed+1; io.write('FAIL: ',msg,'\n') end
end
local values,defined={},nil
local mod={id='weather_fx',path='.',
  options={
    define=function(self,rows) defined=rows return true end,
    get=function(self,key) return values[key] end,
  },
  events={on=function() end,once=function() end},
  hooks={wrap=function() end},
  content={screens={register=function() end}},
  log={info=function() end,warn=function() end},
  read=function() return nil end,
}
local Types={PINNED={}}
function Types.get() return nil end
Types.byId={}
local modules={Types=Types}
local V={mod=mod}
function V.require(name)
  if modules[name] then return modules[name] end
  local f=assert(loadfile('lib/'..name..'.lua'))
  local m=f(V); modules[name]=m; return m
end
local Settings=V.require('Settings'); modules.Settings=Settings
assert(Settings.define())
local Menu=V.require('SettingsMenu')

check(#Settings.SCHEMA>=68,'all original 8.1.49 player settings remain exposed after later additions')
check(#Settings.GROUPS==11,'settings use 11 shallow top-level categories')
local groupSeen={}
for _,g in ipairs(Settings.GROUPS) do
  check(type(g.id)=='string' and type(g.label)=='string' and #g.label>0,'category has a clear name: '..tostring(g.id))
  check(type(g.help)=='string' and #g.help>=30,'category has a useful description: '..tostring(g.id))
  check(g.groups==nil and g.children==nil and g.submenus==nil,'category has no nested submenu: '..tostring(g.id))
  for _,k in ipairs(g.keys or {}) do groupSeen[k]=(groupSeen[k] or 0)+1 end
end

-- Public fallback schema must follow the same category order.
local expected={}
for _,g in ipairs(Settings.GROUPS) do for _,k in ipairs(g.keys) do expected[#expected+1]=k end end
check(#defined==#Settings.SCHEMA,'host fallback exposes every player setting')
for i,k in ipairs(expected) do check(defined[i] and defined[i].key==k,'fallback ordering matches category order at '..i..' ('..k..')') end

local game={save={options={}},mods={}}
for _,row in ipairs(Settings.SCHEMA) do
  check(groupSeen[row.key]==1,row.key..' appears in exactly one category')
  check(type(row.label)=='string' and #row.label>0,row.key..' has a player label')
  check(type(row.help)=='string' and #row.help>=60,row.key..' has a proper description')
  check(not row.label:find('WX',1,true),row.key..' label has no WX abbreviation')
  check(not row.label:find('SFX',1,true),row.key..' label has no SFX abbreviation')
  check(not row.label:find('DMG',1,true),row.key..' label has no DMG abbreviation')
  local sawDefault=false
  for _,choice in ipairs(row.choices or {}) do
    if choice[2]=='config' then
      sawDefault=true
      check(choice[1]=='DEFAULT',row.key..' exposes internal config state as DEFAULT')
    end
    check(choice[1]~='CONFIG',row.key..' never shows CONFIG to the player')
  end
  if row.default=='config' then check(sawDefault,row.key..' has a visible DEFAULT choice') end

  -- Exercise every selectable value through the actual custom-menu write path.
  for _,choice in ipairs(row.choices or {}) do
    local stored=choice[2]
    local before=Settings.optionRevision()
    values[row.key]=stored -- mirrors host option authority after a menu write
    local ok,err=Menu.applyOption(game,row.key,stored)
    check(ok==true,row.key..' applies choice '..tostring(choice[1])..' ('..tostring(err or '')..')')
    local saved=game.save.options.modOptions and game.save.options.modOptions.weather_fx and game.save.options.modOptions.weather_fx[row.key]
    check(saved==stored,row.key..' persists choice '..tostring(choice[1]))
    check(Settings.get(row.key)==stored,row.key..' changes live state to '..tostring(stored))
    check(Settings.optionRevision()>before,row.key..' publishes a live revision for '..tostring(stored))
  end
end

-- Derived helpers: prove the common numeric/toggle controls alter the values
-- consumed by render/gameplay code, rather than only storing menu strings.
local function set(k,v) values[k]=v; Settings.handleOptionChanged({mod='weather_fx',key=k,value=v}) end
set('intensity','soft'); check(math.abs(Settings.intensity()-.45)<.001,'WEATHER STRENGTH SOFT resolves to 45%')
set('intensity','heavy'); check(math.abs(Settings.intensity()-1.5)<.001,'WEATHER STRENGTH HEAVY resolves to 150%')
set('rainIntensity','25'); check(math.abs(Settings.rainIntensity()-.25)<.001,'RAIN AMOUNT 25% reaches rain multiplier')
set('rainIntensity','off'); check(Settings.rainOff(),'RAIN AMOUNT OFF reaches rain kill switch')
set('snowIntensity','500'); check(math.abs(Settings.snowIntensity()-5)<.001,'SNOW AMOUNT 500% reaches snow multiplier')
set('snowIntensity','off'); check(Settings.snowOff(),'SNOW AMOUNT OFF reaches snow kill switch')
set('fogIntensity','500'); check(math.abs(Settings.fogIntensity()-20)<.001,'FOG DENSITY 500% reaches fog multiplier')
set('sandIntensity','500'); check(math.abs(Settings.sandIntensity()-20)<.001,'SANDSTORM DENSITY 500% reaches sand multiplier')
set('dustIntensity','500'); check(math.abs(Settings.dustIntensity()-20)<.001,'DUST STORM DENSITY 500% reaches dust multiplier')
set('windIntensity','200'); check(math.abs(Settings.windIntensity()-2)<.001,'WIND STRENGTH 200% reaches wind multiplier')
set('lightningFlash','off'); check(Settings.lightningFlashScale()==0,'FLASH BRIGHTNESS OFF removes flash scale')
set('lightningFlash','high'); check(Settings.lightningFlashScale()>1,'FLASH BRIGHTNESS HIGH increases flash scale')
set('stormDarkness','off'); check(Settings.stormDarknessScale()==0,'STORM DARKNESS OFF removes darkening scale')
set('tornadoPickup','off'); check(Settings.tornadoPickupChance()==0,'TORNADO CARRY CHANCE OFF reaches zero chance')
set('tornadoPickup','frequent'); check(Settings.tornadoPickupChance()>=.25,'TORNADO CARRY CHANCE FREQUENT increases chance')
set('thunderVolume','25'); check(math.abs(Settings.thunderVolumeScale()-.25)<.001,'THUNDER VOLUME 25% reaches audio scale')
set('cloudHeight','raised'); check(Settings.cloudHeightScale()>1,'CLOUD HEIGHT HIGH raises 3D cloud deck')
set('cloudHeight','original'); check(math.abs(Settings.cloudHeightScale()-1)<.001,'CLOUD HEIGHT LOW restores original deck')
set('waterStyle','weatherfx'); check(Settings.weatherFxWaterEnabled(),'WATER RENDERING ENHANCED enables Weather FX water')
set('waterStyle','original'); check(not Settings.weatherFxWaterEnabled(),'WATER RENDERING ORIGINAL returns water ownership')
set('battleDamage','off'); check(not Settings.battleDamageOn(),'BATTLE WEATHER RULES OFF reaches battle rules')
set('battles','off'); check(Settings.battleScale()==0 and not Settings.battleAnimOn(),'BATTLE WEATHER OFF is the single battle visual kill switch')
set('battles','full'); check(Settings.battleScale()==1 and Settings.battleAnimOn(),'BATTLE WEATHER FULL reaches full visual scale')
set('present','2d'); check(Settings.force2dPresent(),'WEATHER RENDERING 2D OVERLAY reaches presentation gate')
set('present','3d'); check(Settings.force3dPresent(),'WEATHER RENDERING 3D WORLD reaches presentation gate')
set('speed','4x'); check(math.abs(Settings.speedScale()-.25)<.001,'WEATHER DURATION 4X shortens lifetime by four')
set('exotic','off'); check(Settings.exoticScale()==0,'RARE WEATHER OFF removes automatic rare-weather weight')

print(('8.1.49 complete player settings interaction audit: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
