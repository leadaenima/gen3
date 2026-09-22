-- Weather FX 8.1.51: every player-adjustable Weather FX control is held at its
-- highest-load / fully enabled value simultaneously. This is the release stress
-- profile; manual MAX must not silently reduce authored visual ceilings.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local profile={
 quality='max',autoPerformance='off',performanceTarget='30',textureDetail='full',reflectionDetail='full',effectDistance='far',simulationDetail='full',
 always='BLIZZARD',intensity='heavy',rainIntensity='200',snowIntensity='500',snowAccumulation='on',weatherRenderDistance='100',fogIntensity='500',sandIntensity='500',dustIntensity='500',exotic='often',speed='normal',
 daytime='on',seasons='on',clouds='on',cloudHeight='raised',cloudDensity='veryhigh',cloudBankStyle='blocky',waterStyle='weatherfx',leafColor='seasonal',snowShape='flake',hemisphere='northern',seasonNotify='on',
 battles='full',battleDamage='on',amplified='on',lightning='full',weather2dLightning='3d',lightningFlash='high',lightningFrequency='extreme',stormDarkness='high',backdrops='around',sfx='high',splash='on',indoors='tint',
 tornado='on',tornadoPickup='frequent',tornadoDuration='long',present='3d',pauseMenuWeather='animated',screenEffects='full',celestialRendering='3d',nightSkyBrightness='high',transitionSpeed='slow',fronts='on',frontStrength='max',mesoscale='on',mesoscaleStrength='strong',windIntensity='200',windWalk='on',
 puddles='high',rainbows='on',godRays='on',npcLightning='on',npcStrikeChance='50',tornadoFrequency='often',celestialEvents='on',smoothSky='on',celestialMotion='on',timeSource='cycle',
 dayLength='96',seasonLength='60',indoorAudio='loud',thunderAudio='on',thunderVolume='150',windAudio='on',weatherEncounters='on',legendaryEvents='on',followerChip='on',particleCap='tier',debugRain='on',debug='on'
}
local cache={}
local V={mod={id='weather_fx',options={get=function(_,k)return profile[k]end},log={warn=function()end}}}
function V.require(n)
 if cache[n] then return cache[n] end
 local f=assert(loadfile(ROOT..'lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m
end
V.safeCall=pcall
local S=V.require('Settings')
local schemaKeys={};local valid=true
for _,row in ipairs(S.SCHEMA) do
 schemaKeys[row.key]=true
 local chosen=profile[row.key]
 if chosen==nil then valid=false;print('FAIL missing max profile value '..row.key) else
   local found=false
   if row.choices then for _,ch in ipairs(row.choices) do if ch[2]==chosen then found=true;break end end end
   if not found then valid=false;print('FAIL invalid max profile value '..row.key..'='..tostring(chosen)) end
 end
end
local count=0;for k in pairs(profile) do count=count+1;if not schemaKeys[k] then valid=false;print('FAIL unknown profile key '..k) end end
ck(valid and count==78 and #S.SCHEMA==78,'all 78 player controls have a valid simultaneous max-load value')
S.beginFrame()
local reads=true
for _,row in ipairs(S.SCHEMA) do if S.get(row.key)~=profile[row.key] then reads=false;print('FAIL live read '..row.key) end end
ck(reads,'all 78 max-load values are live together through the real Settings reader')
local G=V.require('PerformanceGovernor');G.reset();for _=1,600 do G.update(.06) end
ck(G.auto()==false and G.scale()==1 and G.particleScale()==1,'manual MAX remains 1.0 under severe sustained frame pressure')
local Q=V.require('Quality');local q=Q.budget(1)
ck(q.worldPrecip==1 and q.worldRainCap==12000 and q.worldSnowCap==100000 and q.worldBlizzardCap==200000,'simultaneous max profile preserves full rain/snow/blizzard ceilings')
ck(q.worldHailCap==45000 and q.worldSandCap==43200 and q.worldDebrisCap==3600 and q.worldAshCap==10800,'simultaneous max profile preserves hail/sand/debris/ash ceilings')
local c=Q.celestial();ck(c.starStep==1 and c.maxPlanets==9 and c.twinkle and c.meteors,'simultaneous max profile preserves full celestial catalogue/effects')
ck(profile.frontStrength=='max' and profile.mesoscale=='on' and profile.clouds=='on' and profile.effectDistance=='far','fronts, mesoscale, 3D clouds and far effect distance are all maximized together')
ck(profile.reflectionDetail=='full' and profile.waterStyle=='weatherfx' and profile.smoothSky=='on' and profile.godRays=='on','water reflections, enhanced water, smooth sky and sun optics are all enabled together')
ck(profile.rainIntensity=='200' and profile.snowIntensity=='500' and profile.fogIntensity=='500' and profile.sandIntensity=='500' and profile.dustIntensity=='500','all independent weather-density controls are simultaneously at their highest choices')
ck(profile.particleCap=='tier' and profile.windIntensity=='200' and profile.npcStrikeChance=='50' and profile.thunderVolume=='150','particle limiter follows MAX tier while wind/strike/thunder controls use their highest-load choices')
print(string.format('max settings simultaneous 8.1.51: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
