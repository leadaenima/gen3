-- Weather-wide lightning/thunder authority regression.
-- Proves authored strike weather thunders, and pure RAIN/HEAVY never inherits
-- stale strike state from a prior storm transition.
local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

local realV={}
function realV.require(n) error('Types unexpectedly required '..tostring(n)) end
local Types=assert(loadfile('lib/Types.lua'))(realV)

local expected={HEAVY_RAIN=6,STORM=18,DRAGONSTORM=7,THUNDERSNOW=5,PSYSTORM=84}
for _,d in ipairs(Types.list) do
  local got=Types.strikeRate(d.id)
  check(got==(expected[d.id] or 0),d.id..' authored strike rate')
  check(Types.hasLightning(d.id)==(expected[d.id]~=nil),d.id..' lightning authority')
end
check(Types.strikeRate('RAIN_LIGHT')==0,'RAIN is hard rain-only')
check(Types.strikeRate('RAIN_HEAVY')==0,'HEAVY is hard rain-only')
check(Types.strikeRate('GALE')==0 and not Types.hasLightning('GALE'),'GALE is hard wind/rain/debris-only with no lightning')

local created={}
local function source(path)
  local s={path=path,playing=false,playCount=0,stopCount=0}
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:play() self.playing=true; self.playCount=self.playCount+1 end
  function s:stop() self.playing=false; self.stopCount=self.stopCount+1 end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:setFilter() return true end
  function s:clone() return source(self.path) end
  created[#created+1]=s; return s
end
love={audio={newSource=function(path) return source(path) end},math={random=function(n) if n then return 1 end return .37 end}}
local cfg={audio={enabled=true,volume=1,indoors=.24,battle=.35,wind=false,thunder=true,thunderGain=.8,
  indoorRainHighGain=.2,indoorWindHighGain=.12,indoorThunderHighGain=.08,indoorTransition=.45}}
local Settings={get=function(k) if k=='sfx' then return 'high' elseif k=='lightning' then return 'full' end end}
local Scene={now={mapId='ROUTE_1',visible='world',indoors=false}}
local current=Types.get('PSYSTORM')
local State={id='PSYSTORM'}
function State.current() return current end
-- Deliberately stale/incorrect live strike channel. Audio must ignore it.
function State.channel(k) if k=='strike' then return 99 end return Types.channel(current,k) end
local Lightning={age=0,justStruck=false,strikeSerial=0}
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

for _,d in ipairs(Types.list) do
  check(Audio.strikeWeatherId(d.id)==Types.hasLightning(d.id),d.id..' thunder gate matches lightning gate')
end

local function reset(id)
  Audio.stopAllBeds(); Audio._audioClock=10; Audio._lastThunderAt=-1e9; Audio._lastStrikeSerial=Lightning.strikeSerial
  State.id=id; current=Types.get(id)
end
local function fireSerial()
  Lightning.justStruck=false
  Lightning.strikeSerial=Lightning.strikeSerial+1
  Audio.update(1/60)
  -- Legacy/2D distance fallback is ~320 world units, so thunder arrives about
  -- 0.93 s after the flash rather than immediately.
  for _=1,70 do Audio.update(1/60) end
end

-- PSYSTORM keeps durable serial authority but intentionally sounds only every
-- second actual bolt. The first is silent; the second produces the normal
-- distance-shaped crack/body.
reset('PSYSTORM'); fireSerial()
check(#(Audio._oneshots or {})==0,'first PSYSTORM serial bolt is intentionally silent')
fireSerial()
check(#(Audio._oneshots or {})>=2,'second PSYSTORM serial bolt produces crack plus thunder body')
local psyCrack=false
for _,src in ipairs(Audio._oneshots or {}) do
  local m=Audio._oneshotMeta[src]
  if m and m.name=='thunder_clap' and m.psychicRole=='crack' then psyCrack=true end
end
check(psyCrack,'audible PSYSTORM bolt keeps one softened crack layer')

-- Every OTHER authored 3D lightning weather remains one thunder per bolt.
for id in pairs(expected) do
  if id ~= 'PSYSTORM' then
    reset(id); fireSerial()
    check(#(Audio._oneshots or {})>=1,id..' authored lightning produces thunder')
  end
end

-- GALE and pure rain selections must stay silent even with a stale live strike=99.
reset('GALE'); fireSerial()
check(#(Audio._oneshots or {})==0,'GALE never thunders from stale transition strike')
check(Audio.strikeRateNow()==0,'GALE audio rate is hard zero')
-- Pure rain selections must stay silent even with a stale live strike=99.
reset('RAIN_LIGHT'); fireSerial()
check(#(Audio._oneshots or {})==0,'RAIN never thunders from stale transition strike')
check(Audio.strikeRateNow()==0,'RAIN audio rate ignores stale live strike channel')
reset('RAIN_HEAVY'); fireSerial()
check(#(Audio._oneshots or {})==0,'HEAVY never thunders from stale transition strike')
check(Audio.strikeRateNow()==0,'HEAVY audio rate ignores stale live strike channel')

-- A thunder voice already in flight from the outgoing storm must be cancelled
-- on the first RAIN/HEAVY frame, not allowed to ring for seconds/minutes.
reset('PSYSTORM'); fireSerial(); fireSerial()
local outgoing=Audio._oneshots and Audio._oneshots[1]
check(outgoing~=nil,'transition setup has a live PSYSTORM thunder voice')
State.id='RAIN_LIGHT'; current=Types.get('RAIN_LIGHT'); Audio.update(1/60)
check(#(Audio._oneshots or {})==0,'RAIN transition immediately cancels outgoing storm thunder')
check(not outgoing or outgoing.stopCount>0,'RAIN transition stops the actual outgoing thunder source')

reset('STORM'); fireSerial()
local outgoingHeavy=Audio._oneshots and Audio._oneshots[1]
State.id='RAIN_HEAVY'; current=Types.get('RAIN_HEAVY'); Audio.update(1/60)
check(#(Audio._oneshots or {})==0,'HEAVY transition immediately cancels outgoing storm thunder')
check(not outgoingHeavy or outgoingHeavy.stopCount>0,'HEAVY transition stops the actual outgoing thunder source')

-- The scheduler itself must kill an already-active visual bolt/flash at zero rate.
local LV={}; local VisualLightning=assert(loadfile('lib/Lightning.lua'))(LV)
VisualLightning.timer=0
VisualLightning.update(1/60,18,'full',0,0,320,240,1,'STORM')
check(VisualLightning.age>=0 and VisualLightning.strikeSerial==1,'transition setup creates a live visual lightning strike')
VisualLightning.update(1/60,0,'full',0,0,320,240,1,'RAIN_LIGHT')
check(VisualLightning.age<0 and VisualLightning.bolt==nil and VisualLightning.flash('full')==0,'RAIN zero-rate immediately clears active visual lightning')

print(('weather thunder authority: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
