-- Behavioral contract: indoor weather is acoustically occluded, not merely quieter.
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed=passed+1 else failed=failed+1; print("FAIL "..name) end
end
local function near(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 0.0001) end

local sources = {}
local function newMockSource(path)
  local s = { path=path, playing=false, volume=0, filters={}, filter=nil }
  function s:clone() return newMockSource(self.path) end
  function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end
  function s:getVolume() return self.volume end
  function s:play() self.playing=true end
  function s:stop() self.playing=false end
  function s:isPlaying() return self.playing end
  function s:seek() end
  function s:setFilter(f)
    self.filter = f
    self.filters[#self.filters+1] = f or false
    return true
  end
  sources[#sources+1]=s
  return s
end

love = {
  audio = { newSource=function(path) return newMockSource(path) end },
  math = { random=function(n) return 1 end },
}

local cfg={ audio={enabled=true,volume=1,indoors=0.55,battle=0.35,wind=true,thunder=true,
  thunderGain=0.8,indoorRainHighGain=0.55,indoorWindHighGain=0.45,
  indoorThunderHighGain=0.40,indoorTransition=0.45} }
local cur={id="STORM",rain=1,snow=0,gust=0.8,strike=1}
local live={rain=1,snow=0,gust=0.8,strike=1}
local Types={channel=function(def,key) return def and def[key] or 0 end}
local Settings={get=function(key) if key=="sfx" then return "high" elseif key=="lightning" then return "full" end end}
local Scene={now={mapId="ROUTE_1",visible="world",indoors=false}}
local State={id="STORM",channel=function(k) return live[k] or 0 end,current=function() return cur end}
local Lightning={age=0,justStruck=false}
local Legendary={thunderSound=function() return "thunder_clap" end}
local mod={assets={path=function(_,p) return p end},log={warn=function() end}}
function mod:read() return nil end
local V={mod=mod}
function V.require(name)
  local t={Types=Types,Config={get=function() return cfg end},Settings=Settings,Scene=Scene,
    WeatherState=State,Lightning=Lightning,Legendary=Legendary}
  assert(t[name],"unexpected require "..tostring(name)); return t[name]
end
local Audio=assert(loadfile("lib/Audio.lua"))(V)

-- Outdoor first frame: no filter, full context gain.
Audio.update(1/60)
local bed=Audio.slots[1].src or Audio.slots[2].src
check(bed~=nil,"rain bed starts outdoors")
check(near(Audio.masterGain(),1),"outdoor master gain is full")
check(bed and bed.filter==nil,"outdoor rain has no low-pass")

-- Enter building: transition begins rather than snapping, then reaches full occlusion.
Scene.now.indoors=true
Audio.update(1/60)
local early=Audio._indoorMix
check(early>0 and early<1,"doorway starts a smooth indoor acoustic transition")
check(bed.filter and bed.filter.type=="lowpass","rain receives low-pass indoors")
check(bed.filter and bed.filter.highgain<1,"indoor rain removes high frequencies")
for _=1,40 do Audio.update(1/60) end
check(near(Audio._indoorMix,1,0.001),"indoor acoustic transition reaches full occlusion")
check(near(Audio.masterGain(),0.55,0.01),"default indoor volume retains 55% of the outdoor bed")
check(bed.filter and near(bed.filter.highgain,0.55,0.02),"rain stays intelligible through the indoor low-pass")
local wind=Audio.wind.src
check(wind and wind.filter and near(wind.filter.highgain,0.45,0.02),"wind is darker indoors without falling below the audibility contract")
local filterCalls = #bed.filters
Audio.update(1/60)
check(#bed.filters == filterCalls, "settled indoor rain does not reapply identical filter every frame")

-- Old configs/saves can still carry the pre-8.1.52 near-silent values. The
-- runtime floor must upgrade them in place without requiring a settings reset.
cfg.audio.indoors=0.05
cfg.audio.indoorRainHighGain=0.10
cfg.audio.indoorWindHighGain=0.05
cfg.audio.indoorThunderHighGain=0.01
check(near(Audio.masterGain(),0.40,0.001),"legacy/custom indoor volume cannot drop below 40%")
check(near(Audio.indoorHighGain("rain",1),0.40,0.001),"legacy rain filter cannot remove more than 60% highs")
check(near(Audio.indoorHighGain("wind",1),0.40,0.001),"legacy wind filter cannot remove more than 60% highs")
check(near(Audio.indoorHighGain("thunder",1),0.40,0.001),"legacy thunder filter cannot remove more than 60% highs")
-- Restore authored 8.1.52 values for the thunder/doorway checks below.
cfg.audio.indoors=0.55
cfg.audio.indoorRainHighGain=0.55
cfg.audio.indoorWindHighGain=0.45
cfg.audio.indoorThunderHighGain=0.40

-- Thunder: no old 45% floor indoors, and strongest low-pass.
Lightning.justStruck=true
Audio.update(1/60)
for _=1,70 do Audio.update(1/60) end
local one=Audio._oneshots and Audio._oneshots[#Audio._oneshots]
check(one~=nil,"thunder one-shot starts indoors")
check(one and one.filter and near(one.filter.highgain,0.40,0.02),"thunder reaches the maximum permitted 60% high-frequency muffling")
check(one and one.volume >= 0.40,"indoor thunder retains at least 40% building-context gain before distance/tone shaping")

-- Leave building: filter and volume recover smoothly, then filter is cleared.
Scene.now.indoors=false
Audio.update(1/60)
check(Audio._indoorMix>0 and Audio._indoorMix<1,"leaving building cross-fades acoustic occlusion")
for _=1,40 do Audio.update(1/60) end
check(near(Audio._indoorMix,0,0.001),"outdoor acoustic transition completes")
check(near(Audio.masterGain(),1,0.01),"outdoor volume is restored")
check(bed.filter==nil,"rain low-pass is cleared outdoors")

-- Unsupported filter API must not mute or crash the source.
local noFilter={setVolume=function(self,v) self.volume=v end}
check(Audio.applyIndoorFilter(noFilter,"rain",1)==false,"host without Source:setFilter falls back safely")
local rejects={calls=0,setFilter=function(self) self.calls=self.calls+1; return false end}
check(Audio.applyIndoorFilter(rejects,"rain",1)==false,"backend setFilter=false is treated as unsupported")
Audio.applyIndoorFilter(rejects,"rain",1)
check(rejects.calls==1,"unsupported filter backend is cached instead of retried every frame")

print(("indoor muffle: %d passed, %d failed"):format(passed,failed))
os.exit(failed==0 and 0 or 1)
