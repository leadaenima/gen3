-- End-to-end proof for the custom in-game menu -> runtime authority chain.
-- Unlike the older settings tests, mod.options:get deliberately stays stale
-- after a custom submenu edit, matching the failure mode reported in-game.
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end

local persisted={quality='auto',intensity='normal',particleCap='tier'}
local defined={}
local emitted={}
local mod={id='weather_fx',log={info=function() end,warn=function() end},content={screens={register=function() end}},hooks={wrap=function() end}}
mod.options={
  define=function(self,rows) defined=rows; return true end,
  -- Deliberately stale source: runtime mirror/event must override this.
  get=function(self,key) return persisted[key] end,
}
mod.events={on=function() end,once=function() end}
local Types={PINNED={'RAIN_LIGHT'},byId={RAIN_LIGHT=true}}
function Types.get(id) if id=='RAIN_LIGHT' then return{id=id,label='LIGHT RAIN'} end end
local Config={get=function() return {quality='auto',maxParticles=nil,transitionSeconds=3.2} end}
local modules={Types=Types,Config=Config}
local V={mod=mod}
function V.require(n)
  if modules[n] then return modules[n] end
  error('missing '..tostring(n),0)
end
local Settings=assert(loadfile('lib/Settings.lua'))(V);modules.Settings=Settings
check(Settings.define()==true,'settings schema defines')
local Quality=assert(loadfile('lib/Quality.lua'))(V);modules.Quality=Quality
local Governor=assert(loadfile('lib/PerformanceGovernor.lua'))(V);modules.PerformanceGovernor=Governor
local Menu=assert(loadfile('lib/SettingsMenu.lua'))(V);modules.SettingsMenu=Menu

local bus={emit=function(self,name,payload) emitted[#emitted+1]={name=name,payload=payload} end}
local game={save={options={modOptions={weather_fx={quality='auto',intensity='normal',particleCap='tier'}}}},mods={modOptions={weather_fx={}},loader={modOptions={weather_fx={}},events=bus},events=bus},writeOptions=function() end}

-- Put AUTO under pressure first so stale governor state would visibly suppress a
-- newly selected manual tier if particleScale() trusted its previous mode.
for _=1,260 do Governor.update(.04) end
check(Governor.particleScale()<1,'test establishes AUTO performance trim')
check(Menu.applyOption(game,'quality','max')==true,'custom menu applies MAX')
check(Settings.get('quality')=='max','Settings runtime mirror sees MAX despite stale mod.options:get')
check(Quality.tier()=='max','QUALITY manual MAX becomes authoritative immediately')
check(Governor.particleScale()==1,'manual quality immediately clears stale AUTO particle trim')
local qb=Quality.budget(1)
check(qb.worldRainCap==12000 and qb.worldSnowCap==100000,'MAX immediately exposes authored 3D caps')
check(game.save.options.modOptions.weather_fx.quality=='max','custom menu writes save option table')
check(game.mods.modOptions.weather_fx.quality=='max','custom menu writes manager cache')
check(game.mods.loader.modOptions.weather_fx.quality=='max','custom menu writes nested loader cache')
check(#emitted>=1,'custom menu publishes option change on loader event bus')

check(Menu.applyOption(game,'intensity','soft')==true and math.abs(Settings.intensity()-.45)<1e-6,'INTENSITY SOFT reaches numeric runtime immediately')
local softRev=Settings.keyRevision('intensity')
check(Menu.applyOption(game,'intensity','heavy')==true and math.abs(Settings.intensity()-1.5)<1e-6,'INTENSITY HEAVY reaches numeric runtime immediately')
check(Settings.keyRevision('intensity')>softRev,'per-key revision changes on live intensity edit')
check(Menu.applyOption(game,'particleCap','2000')==true,'PARTICLE HARD CAP accepts live edit')
check(Settings.get('particleCap')=='2000','particle cap runtime mirror is canonical')
check(Menu.applyOption(game,'quality','HIGH')==false,'custom API rejects undeclared stored values rather than guessing labels')

print(('settings live chain: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
