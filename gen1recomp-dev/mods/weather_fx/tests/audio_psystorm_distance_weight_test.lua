-- Distant Psychic Storm lightning must sound broad/heavy, not like quiet gunfire.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end
local created={}
local function source(path)
  local s={path=path,playing=false,volume=0,pitch=1,filter=nil}
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:setPitch(v) self.pitch=v end
  function s:setFilter(v) self.filter=v; return true end
  function s:play() self.playing=true end
  function s:stop() self.playing=false end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:clone() return source(self.path) end
  created[#created+1]=s; return s
end
love={audio={newSource=function(path) return source(path) end},math={random=function(n) if n then return 1 end return .5 end}}
local cfg={audio={enabled=true,volume=1,indoors=.24,battle=.35,wind=false,thunder=true,thunderGain=.8,indoorThunderHighGain=.08}}
local Settings={get=function(k) if k=='sfx' then return 'high' elseif k=='lightning' then return 'full' end end}
local Scene={now={mapId='X',visible='world',indoors=false}}
local cur={id='PSYSTORM',rain=1,gust=1,strike=84}
local State={id='PSYSTORM',current=function() return cur end,channel=function(k) return cur[k] or 0 end}
local Types={}
function Types.channel(def,k) return def and def[k] or 0 end
function Types.hasLightning() return true end
function Types.strikeRate() return 84 end
function Types.get() return cur end
local Lightning={worldStrikeBatches={}}
function Lightning.clearWorldStrikeBatches() Lightning.worldStrikeBatches={} end
local Legendary={thunderSound=function() return nil end}
local mod={assets={path=function(_,p) return p end},log={warn=function() end}}
function mod:read() return nil end
local V={mod=mod}
function V.require(n)
  local t={Types=Types,Config={get=function() return cfg end},Settings=Settings,Scene=Scene,WeatherState=State,Lightning=Lightning,Legendary=Legendary}
  assert(t[n],'unexpected require '..tostring(n)); return t[n]
end
local Audio=assert(loadfile('lib/Audio.lua'))(V)

Audio._audioClock=1
Audio.clearThunderQueues()
Audio.scheduleBoltThunder({serial=0,wxId='PSYSTORM',strikeRate=84,visualAt=.5},{80})
check(#Audio._scheduledThunder==0,'first Psychic Storm bolt is silent at any distance')
Audio._scheduledThunder={} -- preserve cadence counter
Audio.scheduleBoltThunder({serial=1,wxId='PSYSTORM',strikeRate=84,visualAt=1},{100,500,850})
local roles={}
for _,e in ipairs(Audio._scheduledThunder) do
  roles[e.psychicRole]=roles[e.psychicRole] or {}
  roles[e.psychicRole][#roles[e.psychicRole]+1]=e
end
check(roles.crack and #roles.crack==1,'near audible bolt retains one softened crack')
check(roles.farBoom and #roles.farBoom==1,'only every second distant bolt receives a broad far boom')
check(roles.farTail and #roles.farTail==1,'only an audible distant bolt receives a delayed low-frequency tail')
for _,e in ipairs(roles.farBoom or {}) do
  check(e.pitch<=0.64,'far boom pitch is substantially below gunshot-like clap pitch')
  check(e.toneHighGain<=0.055,'far boom strips nearly all high-frequency crack')
  check(e.distanceGain<1,'far boom remains physically quieter with distance')
end
for _,e in ipairs(roles.farTail or {}) do
  check(e.pitch<=0.53,'far tail is deeper than the primary far boom')
  check(e.toneHighGain<=0.035,'far tail is extremely low-passed')
  check(e.dueAt > 1 + Audio.thunderDistanceDelay(e.distance)+0.2,'far tail arrives after the broad initial boom')
end
local far850=nil
for _,e in ipairs(roles.farBoom or {}) do if e.distance==850 then far850=e end end
check(far850 and far850.distanceGain < Audio.thunderDistanceGain(500),'850-unit audible lightning remains quieter than 500-unit reference distance')
check(far850 and far850.eventGain>=0.7,'distant boom retains low-frequency body weight before distance attenuation')

-- At an all-distant burst there must be zero sharp crack roles.
Audio.clearThunderQueues()
Audio.scheduleBoltThunder({serial=2,wxId='PSYSTORM',strikeRate=84,visualAt=5},{600,700,800,900})
local sharp=0; local tails=0
for _,e in ipairs(Audio._scheduledThunder) do
  if e.psychicRole=='crack' then sharp=sharp+1 end
  if e.psychicRole=='farTail' then tails=tails+1 end
end
check(sharp==0,'fully distant Psychic Storm burst contains no rifle-like crack transient')
check(tails==2,'fully distant four-bolt burst gives rolling tails only to bolts 2 and 4')

print(('psystorm distant weight: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
