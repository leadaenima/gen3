-- Distance-aware thunder regression.
-- Every world-space bolt gets one independent thunder voice. Propagation delay
-- and volume must follow the actual bolt distance published by WorldLightning.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end
local function near(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end

local created={}
local function source(path)
  local s={path=path,playing=false,playCount=0,stopCount=0,volume=0}
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:play() self.playing=true; self.playCount=self.playCount+1 end
  function s:stop() self.playing=false; self.stopCount=self.stopCount+1 end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:setFilter() return true end
  function s:clone() return source(self.path) end
  created[#created+1]=s
  return s
end
love={audio={newSource=function(path) return source(path) end},math={random=function(n) if n then return 1 end return .37 end}}

local LV={}
local Lightning=assert(loadfile('lib/Lightning.lua'))(LV)
local cfg={audio={enabled=true,volume=1,indoors=.24,battle=.35,wind=false,thunder=true,thunderGain=.8,
  indoorRainHighGain=.2,indoorWindHighGain=.12,indoorThunderHighGain=.08,indoorTransition=.45}}
local Settings={get=function(k) if k=='sfx' then return 'high' elseif k=='lightning' then return 'full' end end}
local Scene={now={mapId='ROUTE_1',visible='world',indoors=false}}
local current={id='STORM',rain=1.5,snow=0,gust=0,strike=84}
local State={id='STORM'}
function State.current() return current end
function State.channel(k) return current[k] or 0 end
local Types={}
function Types.channel(def,k) return def and def[k] or 0 end
function Types.hasLightning(id) return tostring(id or ''):upper()=='STORM' end
function Types.strikeRate(id) return Types.hasLightning(id) and 84 or 0 end
function Types.get(id) if tostring(id or ''):upper()=='STORM' then return current end end
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

check(near(Audio.thunderDistanceDelay(343),1,0.001),'343 world units produces about 1 second sound delay')
check(near(Audio.thunderDistanceDelay(686),2,0.001),'686 world units produces about 2 second sound delay')
check(Audio.thunderDistanceGain(100) > Audio.thunderDistanceGain(450),'mid-distance thunder is quieter than near thunder')
check(Audio.thunderDistanceGain(450) > Audio.thunderDistanceGain(900),'far thunder is quieter than mid-distance thunder')
check(Audio.thunderDistanceGain(900) >= .54,'far thunder remains audible instead of fading away')

local function advance(sec)
  local n=math.floor(sec*60+.5)
  for _=1,n do Audio.update(1/60) end
end

-- Prime the weather/audio state.
Audio.update(1/60)
local visualAt=Audio._audioClock
Lightning.strikeSerial=1
Lightning.justStruck=true
Lightning.burstCount=3
Audio.update(1/60) -- queues serial 1 but deliberately waits for world distances
check(#(Audio._oneshots or {})==0,'thunder does not fire before world bolt distance is known')
check(#(Audio._pendingStrikeEvents or {})==1,'scheduler strike waits in distance-resolution queue')

check(Lightning.publishWorldStrikeBatch(1,{100,450,900})==true,'world renderer can publish one distance per bolt')
advance(.34)
local n1=select(1,Audio.thunderVoiceCounts())
check(n1==1,'near bolt thunder arrives first while other bolt sounds remain pending')
local first=Audio._oneshots[1]
local m1=first and Audio._oneshotMeta[first]
check(m1 and near(m1.distance,100,.001),'first thunder voice keeps near bolt distance metadata')
local v1=first and first.volume or 0

advance(1.05)
local n2=select(1,Audio.thunderVoiceCounts())
check(n2==2,'mid-distance bolt gets its own overlapping thunder voice')
local second=Audio._oneshots[2]
local m2=second and Audio._oneshotMeta[second]
check(m2 and near(m2.distance,450,.001),'second thunder voice keeps mid bolt distance metadata')
local v2=second and second.volume or 0
check(v2 < v1,'mid-distance thunder is quieter than near thunder in actual playback volume')
check(first and first.stopCount==0,'second bolt does not stop/restart first thunder file')

advance(1.35)
local n3=select(1,Audio.thunderVoiceCounts())
check(n3==3,'far bolt gets a third independent thunder voice before prior files finish')
local third=Audio._oneshots[3]
local m3=third and Audio._oneshotMeta[third]
check(m3 and near(m3.distance,900,.001),'third thunder voice keeps far bolt distance metadata')
local v3=third and third.volume or 0
check(v3 < v2,'far thunder is quieter than mid-distance thunder in actual playback volume')
check(first and first.stopCount==0 and second and second.stopCount==0,'overlapping bolt sounds are not chopped')
check(m1 and m2 and m3 and m1.burstSize==3 and m2.burstSize==3 and m3.burstSize==3,'all three sounds remain tied to one three-bolt visual burst')

-- A new bolt is still allowed while every earlier sound file is active.
Lightning.strikeSerial=2
Lightning.justStruck=true
Lightning.burstCount=1
Audio.update(1/60)
Lightning.publishWorldStrikeBatch(2,{120})
advance(.40)
local n4=select(1,Audio.thunderVoiceCounts())
check(n4==4,'new strike sounds while previous thunder files are still playing')
check((Audio.THUNDER_MIX.maxVoices or 0)>=32,'voice ceiling has enough headroom for dense storms')

print(('distance thunder: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
