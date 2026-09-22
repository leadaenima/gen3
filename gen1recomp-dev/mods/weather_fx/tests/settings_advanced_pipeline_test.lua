local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end
local values={}
local defined
local mod={id='weather_fx',path='.',
  options={define=function(self,rows) defined=rows; return true end,get=function(self,key) return values[key] end},
  events={on=function() end},
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
  local c=assert(loadfile('lib/'..name..'.lua'))
  local m=c(V); modules[name]=m; return m
end
local Settings=V.require('Settings')
modules.Settings=Settings
assert(Settings.define())
local Config=V.require('Config'); modules.Config=Config
Config.load()
local c=Config.get()
check(c.npcLightning.chance==0.10,'fallback NPC lightning chance is 10 percent')
check(c.npcLightning.duration==3.0,'fallback NPC lightning duration is 3 seconds')
check(c.mesoscale.enabled==true and c.mesoscale.strength==1.0,'mesoscale config default is enabled natural')
check(c.rainbow.enabled==true,'post-rain rainbow config default is enabled')
check(c.wind.playerMovement==true,'wind walking config default is enabled')

local function set(k,v)
  values[k]=v
  Settings.handleOptionChanged({mod='weather_fx',key=k,value=v})
  return Config.get()
end
c=set('transitionSpeed','slow'); check(math.abs(c.transitionSeconds-6.0)<.001,'TRANSITION SPEED reaches WeatherState config')
c=set('fronts','off'); check(c.fronts.enabled==false,'WEATHER FRONTS OFF reaches Fronts config'); check(c.mesoscale.enabled==false,'WEATHER FRONTS OFF forces full-map mesoscale fallback')
c=set('fronts','on'); check(c.fronts.enabled==true,'WEATHER FRONTS ON restores spatial authority');
c=set('frontStrength','strong'); check(math.abs(c.fronts.drift-.75)<.001,'FRONT STRENGTH reaches drift')
c=set('mesoscale','off'); check(c.mesoscale.enabled==false,'LOCAL WEATHER FIELDS OFF reaches mesoscale config')
c=set('mesoscaleStrength','strong'); check(math.abs(c.mesoscale.strength-1.35)<.001,'LOCAL VARIATION reaches mesoscale strength')
c=set('windWalk','off'); check(c.wind.playerMovement==false,'WIND WALKING OFF reaches movement consumer')
c=set('puddles','off'); check(c.visuals.puddles==false,'PUDDLES OFF reaches visual authority')
c=set('rainbows','off'); check(c.rainbow.enabled==false,'POST-RAIN RAINBOWS OFF reaches rainbow authority')
c=set('godRays','off'); check(c.visuals.glare==false,'SUN GOD RAYS OFF reaches glare authority')
c=set('npcLightning','off'); check(c.npcLightning.enabled==false,'NPC LIGHTNING OFF reaches bolt targeting')
c=set('npcStrikeChance','35'); check(math.abs(c.npcLightning.chance-.35)<.001,'NPC STRIKE CHANCE reaches probability')
c=set('tornadoFrequency','rare'); check(c.tornado.everySeconds==180,'TORNADO FREQUENCY reaches shared 2D/3D Gale opportunity interval')
c=set('celestialEvents','off'); check(c.celestial.events==false,'CELESTIAL EVENTS OFF reaches CelestialSim')
c=set('smoothSky','off'); check(c.celestial.smoothSky==false,'SMOOTH SKY OFF reaches sky authority')
c=set('celestialMotion','off'); check(c.celestial.motionSmoothing==false,'SMOOTH SUN MOON OFF reaches celestial interpolation')
c=set('timeSource','cycle'); check(c.time.source=='cycle','CLOCK SOURCE reaches TimeOfDay')
c=set('dayLength','48'); check(c.time.cycleMinutes==48,'GAME DAY LENGTH reaches TimeOfDay')
c=set('seasonLength','30'); check(c.seasons.daysPerSeason==30,'SEASON LENGTH reaches Seasons')
c=set('indoorAudio','muted'); check(math.abs(c.audio.indoors-.40)<.001,'MAX MUFFLE preserves the 40% minimum indoor weather bed')
c=set('indoorAudio','quiet'); check(math.abs(c.audio.indoors-.50)<.001,'QUIET indoor weather retains half outdoor volume')
c=set('indoorAudio','natural'); check(math.abs(c.audio.indoors-.60)<.001,'NATURAL indoor weather retains 60% outdoor volume')
c=set('indoorAudio','loud'); check(math.abs(c.audio.indoors-.75)<.001,'LOUD indoor weather retains 75% outdoor volume')
c=set('thunderAudio','off'); check(c.audio.thunder==false,'THUNDER AUDIO OFF reaches audio authority')
c=set('windAudio','off'); check(c.audio.wind==false,'WIND AUDIO OFF reaches audio authority')
c=set('weatherEncounters','off'); check(c.encounters.enabled==false,'WEATHER ENCOUNTERS OFF reaches encounter authority')
c=set('legendaryEvents','off'); check(c.legendary.enabled==false,'LEGENDARY WEATHER EVENTS OFF reaches legendary authority')
c=set('followerChip','off'); check(c.followerChip.enabled==false,'FOLLOWER WEATHER DAMAGE OFF reaches follower authority')
c=set('particleCap','8000'); check(c.maxParticles==8000,'PARTICLE HARD CAP reaches Quality authority')
c=set('particleCap','tier'); check(c.maxParticles==nil,'QUALITY TIER removes extra particle cap')

-- CONFIG restores the authored base instead of hardcoding the menu's nominal value.
c=set('npcStrikeChance','config'); check(c.npcLightning.chance==0.10,'CONFIG restores authored NPC chance')
c=set('godRays','config'); check(c.visuals.glare==true,'CONFIG restores authored glare')
c=set('rainbows','config'); check(c.rainbow.enabled==true,'CONFIG restores authored rainbow choice')
c=set('windWalk','config'); check(c.wind.playerMovement==true,'CONFIG restores authored wind-walking choice')


-- CONFIG truly means authored config.lua, not merely the built-in default.
mod.read=function(self,path)
  if path=='config.lua' then return 'return { npcLightning={ chance=0.33 }, visuals={ glare=false } }' end
end
Config.load(); c=Config.get()
check(math.abs(c.npcLightning.chance-.33)<.001,'CONFIG preserves folder-authored NPC chance')
check(c.visuals.glare==false,'CONFIG preserves folder-authored glare choice')
print(('advanced settings pipeline: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
