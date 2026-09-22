local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1;print('FAIL '..n) end end
local function newSource(path)
  local s={path=path,playing=false,volume=0,pitch=1,stopCount=0}
  function s:clone() return newSource(self.path) end
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:setPitch(v) self.pitch=v end
  function s:getVolume() return self.volume end
  function s:play() self.playing=true end
  function s:stop() self.playing=false; self.stopCount=self.stopCount+1 end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:setFilter() return false end
  return s
end
love={audio={newSource=function(path)return newSource(path)end},math={random=function()return 1 end}}
local cfg={audio={enabled=true,volume=1,indoors=.24,battle=.35,wind=true,thunder=true,thunderGain=.8}}
local cur={id='STORM',rain=1,snow=0,gust=.7,strike=.5};local live={rain=1,snow=0,gust=.7,strike=.5}
local Types={channel=function(def,k)return def and def[k] or 0 end}
local Settings={get=function(k) if k=='sfx'then return'high'elseif k=='lightning'then return'full'end end}
local Scene={now={mapId='ROUTE_1',visible='world',indoors=false}}
local State={id='STORM',channel=function(k)return live[k]or 0 end,current=function()return cur end}
local Lightning={age=0,justStruck=false,strikeSerial=0};local Legendary={thunderSound=function()return'thunder_clap'end}
local mod={assets={path=function(_,p)return p end},log={warn=function()end}};function mod:read()return nil end
local V={mod=mod};function V.require(n)local t={Types=Types,Config={get=function()return cfg end},Settings=Settings,Scene=Scene,WeatherState=State,Lightning=Lightning,Legendary=Legendary};assert(t[n],'unexpected require '..tostring(n));return t[n]end
local A=assert(loadfile('lib/Audio.lua'))(V)
-- Cold title/home boot must be complete non-interference: Weather FX has no
-- world audio to clean up and must not call stop() on any Source each frame.
local coldStops=0
Scene.now={visible='menu'}
for _=1,10 do A.update(1/60) end
for _,slot in ipairs(A.slots or {}) do if slot.src then coldStops=coldStops+(slot.src.stopCount or 0) end end
check(coldStops==0,'cold title frames do not touch audio Sources')
Scene.now={mapId='ROUTE_1',visible='world',indoors=false}
-- Ordinary running gameplay, with NO draw/nudge calls, must start and sustain weather audio.
for _=1,30 do A.update(1/60) end
local bed=(A.slots[1].file and A.slots[1]) or A.slots[2]
check(bed and bed.src and bed.src.playing,'running gameplay starts weather bed without visual callback')
check((bed.level or 0)>.2 and (bed.src.volume or 0)>0,'running gameplay weather bed is audible')
local clock=A._audioClock;for _=1,30 do A.update(1/60) end
check(A._audioClock>clock and bed.src.playing,'independent audio clock advances while gameplay runs')
-- A draw path that reports no precip may only update diagnostics.
A.nudgeFromVisual('STORM',false,false)
check(bed.src.playing and (bed.level or 0)>.2,'visual no-precip signal cannot stop live weather audio')
-- Indoor visual suppression attenuates/muffles but does not kill the outside weather bed.
Scene.now.indoors=true;for _=1,40 do A.update(1/60) end
check(bed.src.playing and (bed.src.volume or 0)>0,'indoor/hidden visual precipitation remains audibly attenuated')
-- Leaving the world performs one Weather FX cleanup, but subsequent title
-- frames are silent/non-invasive and cannot keep suppressing the game's cry.
local bedSrc=bed.src
local beforeStops=(bedSrc.stopCount or 0)
Scene.now.mapId=nil; Scene.now.visible='menu'
A.update(1/60)
local transitionStops=(bedSrc.stopCount or 0)
for _=1,20 do A.update(1/60) end
check(transitionStops>beforeStops,'world-to-title transition cleans Weather FX bed once')
check((bedSrc.stopCount or 0)==transitionStops,'repeated title frames do not repeatedly stop Sources')
print(('audio realtime authority: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
