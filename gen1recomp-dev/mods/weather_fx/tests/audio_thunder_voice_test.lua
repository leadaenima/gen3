-- Behavioral contract: ordinary lightning bolts get independent thunder voices.
-- PSYSTORM deliberately sounds every second bolt; audible bolts may overlap and
-- distance propagation spaces arrivals instead of a cooldown.
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name) end
end

local created = {}
local function newMockSource(path, cloneMode)
  local s = { path=path, playing=false, volume=0, stopCount=0, playCount=0, cloneMode=cloneMode }
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:setPitch(v) self.pitch=v end
  function s:play() self.playing=true; self.playCount=self.playCount+1 end
  function s:stop() self.playing=false; self.stopCount=self.stopCount+1 end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:setFilter() return true end
  function s:clone()
    if self.cloneMode == "self" then return self end
    return newMockSource(self.path, self.cloneMode)
  end
  created[#created+1]=s
  return s
end

local cloneMode = "normal"
love = {
  audio = { newSource=function(path) return newMockSource(path, cloneMode) end },
  -- Pick the last entry when a list has >1 item. For ordinary storms this
  -- deliberately tries to select thunder_roll so the one-roll guard is tested.
  math = { random=function(n) if n then return n end return 0.5 end },
}

local cfg={ audio={enabled=true,volume=1,indoors=0.24,battle=0.35,wind=false,thunder=true,
  thunderGain=0.8,indoorRainHighGain=0.20,indoorWindHighGain=0.12,
  indoorThunderHighGain=0.08,indoorTransition=0.45} }
local cur={id="PSYSTORM",rain=1.5,snow=0,gust=0,strike=42}
local live={rain=1.5,snow=0,gust=0,strike=42}
local Types={channel=function(def,key) return def and def[key] or 0 end}
local Settings={get=function(key) if key=="sfx" then return "high" elseif key=="lightning" then return "full" end end}
local Scene={now={mapId="CERULEAN_CAVE_B1F",visible="world",indoors=false}}
local State={id="PSYSTORM",channel=function(k) return live[k] or 0 end,current=function() return cur end}
local Lightning={age=0,justStruck=false}
local Legendary={thunderSound=function() return nil end}
local mod={assets={path=function(_,p) return p end},log={warn=function() end}}
function mod:read() return nil end
local V={mod=mod}
function V.require(name)
  local t={Types=Types,Config={get=function() return cfg end},Settings=Settings,Scene=Scene,
    WeatherState=State,Lightning=Lightning,Legendary=Legendary}
  assert(t[name],"unexpected require "..tostring(name)); return t[name]
end
local Audio=assert(loadfile("lib/Audio.lua"))(V)

local function advance(seconds)
  local n=math.floor(seconds*60+0.5)
  for _=1,n do Audio.update(1/60) end
end
local function strike()
  Lightning.justStruck=true
  Audio.update(1/60)
end

-- Dense PSYSTORM: odd bolts are silent; every second bolt is audible and
-- minute-long thunder_roll must never be selected.
advance(1.5)
strike(); advance(1.4)
check(select(1,Audio.thunderVoiceCounts())==0,"first PSYSTORM bolt is silent")
strike(); advance(1.4)
local total, rolls=Audio.thunderVoiceCounts()
check(total==2,"second PSYSTORM bolt produces a crack plus rumble body")
check(rolls==0,"PSYSTORM dense lightning never starts 60-second thunder_roll")
local first=Audio._oneshots[1]
local firstMeta=first and Audio._oneshotMeta[first]
check(firstMeta and firstMeta.name=="thunder_clap" and firstMeta.psychicRole=="crack",
  "audible dense PSYSTORM bolt uses one softened clap as its crack layer")
local sawRumble=false
for _,src in ipairs(Audio._oneshots) do
  local m=Audio._oneshotMeta[src]
  if m and m.psychicRole=="rumble" then sawRumble=true end
end
check(sawRumble,"audible PSYSTORM bolt adds a delayed rumble body")

-- Bolt 3 is silent; bolt 4 is audible and must overlap the first audible pair.
strike(); advance(1.4)
check(select(1,Audio.thunderVoiceCounts())==2,"third PSYSTORM bolt stays silent while prior thunder rings")
strike(); advance(1.4)
local total2=select(1,Audio.thunderVoiceCounts())
check(total2==4,"fourth PSYSTORM bolt overlaps the second bolt's thunder")
check(first and first.stopCount==0,"later audible strike does not stop thunder already playing")

-- The safety ceiling remains bounded without chopping voices already in flight.
Audio.THUNDER_MIX.maxVoices=6
for _=1,8 do
  strike(); advance(1.0)
end
local total3, rolls3=Audio.thunderVoiceCounts()
check(total3==6,"dense thunder voice count is bounded at configured safety ceiling")
check(rolls3==0,"voice pressure cannot introduce long rolls into PSYSTORM")
local chopped=false
for _,src in ipairs(Audio._oneshots) do if (src.stopCount or 0)>0 then chopped=true end end
check(not chopped,"voice saturation never hard-stops an active thunder sample")

-- Ordinary storm: a roll is allowed, but only ONE long roll at a time. A later
-- random roll selection is converted to a short clap instead of stacking a
-- second 60-second ambient thunder track.
Audio.stopAllBeds()
Audio.THUNDER_MIX.maxVoices=48
Audio._audioClock=0; Audio._lastThunderAt=-1e9; Audio._wxId=nil; Audio._bedFile=nil
cur={id="STORM",rain=1,snow=0,gust=0,strike=9}
live={rain=1,snow=0,gust=0,strike=9}
State.id="STORM"
advance(1.0); strike(); advance(1.0)
local n1,r1=Audio.thunderVoiceCounts()
check(n1==1 and r1==1,"ordinary storm may start one long thunder roll")
strike(); advance(1.0)
local n2,r2=Audio.thunderVoiceCounts()
check(n2==2,"second ordinary strike can overlap without restarting the first")
check(r2==1,"ordinary storm never stacks a second 60-second roll")
local names={}
for _,src in ipairs(Audio._oneshots) do
  local m=Audio._oneshotMeta[src]; names[#names+1]=m and m.name or "?"
end
local sawClap=false
for _,n in ipairs(names) do if n=="thunder_clap" then sawClap=true end end
check(sawClap,"second roll choice falls back to a short clap")
local ordinaryChopped=false
for _,src in ipairs(Audio._oneshots) do if (src.stopCount or 0)>0 then ordinaryChopped=true end end
check(not ordinaryChopped,"ordinary overlapping thunder is not chopped")

-- Leaving the world is a true hard stop. Long thunder must not leak onto the
-- launcher/title screen after a map unload.
local ringing=Audio._oneshots[1]
Scene.now.mapId=nil; Scene.now.visible="menu"
Audio.update(1/60)
check(#(Audio._oneshots or {})==0,"title/no-map transition clears thunder voices")
check(ringing and ringing.stopCount>0,"title/no-map transition actually stops ringing thunder")
Scene.now.mapId="CERULEAN_CAVE_B1F"; Scene.now.visible="world"

-- Broken/shared clone guard. A clone implementation that returns the SAME object
-- is not an independent voice; sourceFor must reject it and build a fresh Source.
Audio.stopAllBeds()
Audio._audioClock=0; Audio._lastThunderAt=-1e9; Audio._wxId=nil; Audio._bedFile=nil
cloneMode="self"
cur={id="PSYSTORM",rain=1.5,snow=0,gust=0,strike=42}
live={rain=1.5,snow=0,gust=0,strike=42}
State.id="PSYSTORM"
-- invalidate templates made with the normal clone behavior so this path is real.
Audio.invalidate()
strike(); advance(1.0) -- silent #1
strike(); advance(1.0) -- audible #2
local sharedFirst=Audio._oneshots[1]
strike(); advance(1.0) -- silent #3
strike(); advance(1.0) -- audible #4
-- Each audible close bolt owns crack+rumble; compare the crack voices from the
-- two audible strikes (indices 1 and 3 in the one-shot list).
local sharedSecond=Audio._oneshots[3]
check(sharedFirst~=nil and sharedSecond~=nil,"shared-clone host still creates thunder voices on audible PSYSTORM bolts")
check(sharedFirst~=sharedSecond,"clone(self) backend is rejected; audible strikes get independent Sources")
check((sharedFirst and sharedFirst.stopCount or 0)==0,"later audible strike does not stop/restart first shared-backend voice")

print(("thunder voice mixer: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
