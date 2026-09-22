-- Behavioral contract: indoor visuals may be zero while outside weather remains audible.
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name) end
end

local cur = { id="RAIN_LIGHT", rain=1.0, snow=0, gust=0.4 }
local live = { rain=0, snow=0, gust=0 }
local Types = { channel=function(def,key) return def and def[key] or 0 end }
local Config = { get=function() return { audio={enabled=true,volume=1,indoors=0.24,battle=0.35,wind=true} } end }
local sfx = "high"
local Settings = { get=function(key) if key=="sfx" then return sfx end return nil end }
local Scene = { now={mapId="HOUSE",visible="world",indoors=true} }
local State = {
  id="RAIN_LIGHT",
  channel=function(key) return live[key] or 0 end,
  current=function() return cur end,
}
local V={mod={}}
function V.require(name)
  local t={Types=Types,Config=Config,Settings=Settings,Scene=Scene,WeatherState=State,
           Lightning={},Legendary={}}
  assert(t[name],"unexpected require "..tostring(name)); return t[name]
end
local Audio=assert(loadfile("lib/Audio.lua"))(V)

check(Audio.channelForContext("rain")==1.0, "indoor rain derives from active outside weather")
check(Audio.channelForContext("gust")==0.4, "indoor wind derives from active outside weather")
check(math.abs(Audio.masterGain()-0.40)<0.0001, "legacy indoor gain is clamped to the 40% audibility floor")

-- Draw.pass reports no visible precipitation indoors by design. That signal
-- must not tear down the outside-weather bed after Audio.update started it.
Audio.slots[1].file = "rain"
Audio.slots[1].level = 0.5
Audio.nudgeFromVisual("RAIN_LIGHT", false, false)
check(Audio.slots[1].file == "rain", "indoor visual suppression does not stop weather bed")

Scene.now.indoors=false
check(Audio.channelForContext("rain")==0, "outdoor audio follows live/eased channel")
live.rain=0.65
check(Audio.channelForContext("rain")==0.65, "outdoor live rain density preserved")

Scene.now.indoors=true
sfx="off"
check(Audio.masterGain()==0, "WEATHER SFX OFF hard-mutes indoors too")

print(("indoor audio: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
