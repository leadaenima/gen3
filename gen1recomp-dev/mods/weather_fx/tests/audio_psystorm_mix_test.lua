-- PSYSTORM thunder mix regression.
-- Dense psychic lightning must sound like one storm event, not repeated gunshots:
-- one softened crack, darker secondary booms, and a delayed rumble body.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local created={}
local function source(path)
  local s={path=path,playing=false,volume=0,pitch=1,filter=nil,playCount=0,stopCount=0}
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:setPitch(v) self.pitch=v end
  function s:setFilter(v) self.filter=v; return true end
  function s:play() self.playing=true; self.playCount=self.playCount+1 end
  function s:stop() self.playing=false; self.stopCount=self.stopCount+1 end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:clone() return source(self.path) end
  created[#created+1]=s
  return s
end
love={
  audio={newSource=function(path) return source(path) end},
  math={random=function(n) if n then return 1 end return .5 end},
}

local cfg={audio={enabled=true,volume=1,indoors=.24,battle=.35,wind=false,thunder=true,thunderGain=.8,
  indoorRainHighGain=.2,indoorWindHighGain=.12,indoorThunderHighGain=.08,indoorTransition=.45}}
local Settings={get=function(k) if k=='sfx' then return 'high' elseif k=='lightning' then return 'full' end end}
local Scene={now={mapId='CERULEAN_CAVE_B1F',visible='world',indoors=false}}
local cur={id='PSYSTORM',rain=1.5,snow=0,gust=0,strike=42}
local State={id='PSYSTORM',current=function() return cur end,channel=function(k) return cur[k] or 0 end}
local Types={}
function Types.channel(def,k) return def and def[k] or 0 end
function Types.hasLightning(id) return tostring(id or ''):upper()=='PSYSTORM' end
function Types.strikeRate() return 42 end
function Types.get(id) if tostring(id or ''):upper()=='PSYSTORM' then return cur end end
local Lightning={strikeSerial=0,justStruck=false,worldStrikeBatches={}}
function Lightning.clearWorldStrikeBatches() Lightning.worldStrikeBatches={} end
local Legendary={thunderSound=function() return nil end}
local mod={assets={path=function(_,p) return p end},log={warn=function() end}}
function mod:read() return nil end
local V={mod=mod}
function V.require(n)
  local t={Types=Types,Config={get=function() return cfg end},Settings=Settings,Scene=Scene,
    WeatherState=State,Lightning=Lightning,Legendary=Legendary}
  assert(t[n],'unexpected require '..tostring(n)); return t[n]
end
local Audio=assert(loadfile('lib/Audio.lua'))(V)

-- PSYSTORM thunder is intentionally half-rate: bolt 1 silent, bolt 2 audible,
-- continuing across bursts. Prime one silent bolt so this three-bolt close burst
-- makes bolts 1 and 3 audible (global bolts 2 and 4).
Audio._audioClock=10
Audio.clearThunderQueues()
Audio.scheduleBoltThunder({serial=6,wxId='PSYSTORM',strikeRate=42,visualAt=9},{90})
check(#Audio._scheduledThunder==0,'first Psychic Storm bolt is silent')
Audio._scheduledThunder={} -- keep cadence counter, clear only test queue
Audio.scheduleBoltThunder({serial=7,wxId='PSYSTORM',strikeRate=42,visualAt=10},{100,120,140})
local q=Audio._scheduledThunder
check(#q==3,'three-bolt PSYSTORM at half cadence schedules two audible bolts plus one rumble')
local counts={crack=0,boom=0,rumble=0}
local crack,rumble
for _,e in ipairs(q) do
  if e.psychicRole then counts[e.psychicRole]=(counts[e.psychicRole] or 0)+1 end
  if e.psychicRole=='crack' then crack=e end
  if e.psychicRole=='rumble' then rumble=e end
end
check(counts.crack==1,'audible PSYSTORM burst contains exactly one sharp crack')
check(counts.boom==1,'only the second audible close bolt becomes a thunder boom')
check(counts.rumble==1,'audible PSYSTORM burst adds one delayed rumble tail')
check(crack and crack.boltIndex==1,'nearest AUDIBLE bolt owns the crack transient')
check(rumble and rumble.boltIndex==1,'rumble body follows the nearest audible bolt')
check(rumble and crack and rumble.dueAt>crack.dueAt,'rumble arrives after the crack instead of stacking on the same transient')

local boomPitchOk,boomGainOk,boomFilterOk=true,true,true
for _,e in ipairs(q) do
  if e.psychicRole=='boom' then
    boomPitchOk=boomPitchOk and e.pitch>=0.68 and e.pitch<=0.79
    boomGainOk=boomGainOk and e.eventGain<crack.eventGain
    boomFilterOk=boomFilterOk and e.toneHighGain<crack.toneHighGain
    check(e.dueAt > 10 + Audio.thunderDistanceDelay(e.distance),
      'secondary psychic boom has a small stagger beyond physical propagation delay')
  end
end
check(boomPitchOk,'secondary psychic booms are pitch-shifted lower than gunshot-like clap pitch')
check(boomGainOk,'secondary psychic booms are softer than the primary crack')
check(boomFilterOk,'secondary psychic booms remove more high-frequency snap')
check(rumble and rumble.pitch<=0.66,'psychic rumble is strongly pitch-shifted downward')
check(rumble and rumble.eventGain<crack.eventGain,'rumble tail sits under the primary crack')
check(rumble and rumble.toneHighGain<=0.12,'rumble tail is strongly low-passed')

-- Prove the scheduled tone actually reaches the Love Source.
for _,e in ipairs(q) do
  Audio.playThunderEvent(e,1,0)
end
local roles={}
for _,src in ipairs(Audio._oneshots) do
  local m=Audio._oneshotMeta[src]
  if m and m.psychicRole then roles[m.psychicRole]=src end
end
check(roles.crack and roles.crack.pitch and roles.crack.pitch<1,'primary PSYSTORM crack is softened below normal pitch in playback')
check(roles.boom and roles.boom.pitch and roles.boom.pitch<roles.crack.pitch,'psychic boom playback is lower-pitched than crack playback')
check(roles.rumble and roles.rumble.pitch and roles.rumble.pitch<roles.boom.pitch,'rumble playback is the lowest-pitched layer')
check(roles.crack and type(roles.crack.filter)=='table' and (roles.crack.filter.highgain or 1)<0.5,
  'primary psychic crack is low-passed to remove gunshot-like high-frequency edge')
check(roles.boom and type(roles.boom.filter)=='table' and (roles.boom.filter.highgain or 1)<0.3,
  'secondary psychic boom receives stronger low-pass filtering')
check(roles.rumble and type(roles.rumble.filter)=='table' and (roles.rumble.filter.highgain or 1)<=0.12,
  'rumble layer receives the darkest low-pass filtering')

-- Ordinary storms must keep their existing one-voice-per-bolt behavior.
Audio._scheduledThunder={}
Audio.scheduleBoltThunder({serial=8,wxId='STORM',strikeRate=9,visualAt=20},{100,120,140})
check(#Audio._scheduledThunder==3,'ordinary storm does not gain PSYSTORM rumble/role layering')
local ordinaryClean=true
for _,e in ipairs(Audio._scheduledThunder) do
  ordinaryClean=ordinaryClean and e.psychicRole==nil and e.pitch==nil and e.eventGain==nil and e.toneHighGain==nil
end
check(ordinaryClean,'ordinary thunder tone remains unchanged by PSYSTORM-specific mix')

print(('psystorm thunder mix: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
