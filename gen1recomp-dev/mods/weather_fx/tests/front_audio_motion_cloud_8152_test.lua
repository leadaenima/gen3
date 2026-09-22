-- Weather FX 8.1.52: physical front audio, monotonic rain gravity, smooth descriptors.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function near(a,b,e) return math.abs((a or 0)-(b or 0)) <= (e or 1e-6) end
local V0={mod={}}
local Types=assert(loadfile(ROOT..'lib/Types.lua'))(V0)
local cell={id=52,weather='RAIN_LIGHT',x=0,z=0,rx=100,rz=200,age=50,life=100,vx=1,vz=0,speed=2,sizeClass='regional',charge=0,flash=0}
local S={cells=function() return {cell} end}
local V={require=function(n) if n=='StormCells' then return S elseif n=='Types' then return Types end error(n,0) end}
local D=assert(loadfile(ROOT..'lib/DistantWeather.lua'))(V)

local function sample(x,z,dt)
  D.update(dt or .1,x,z)
  local items,n=D.items();return D.rainAudio(),items[1],n
end
local a,q=sample(0,0,.1)
ck(a.present and a.inside and near(a.gain,1,1e-9),'rain bed is full spatial gain anywhere inside physical front')
ck(q and near(q.bankX,100,1e-9) and near(q.bankZ,0,1e-9),'render bank is the entity leading edge, not player-nearest ellipse point')
local bankX,bankZ=q.bankX,q.bankZ
local edgeA=sample(100,0,.1)
ck(edgeA.inside and near(edgeA.gain,1,1e-9),'rain does not start quieting at the precipitation boundary')
local outside=sample(700,0,.1)
ck((not outside.inside) and outside.gain>0 and outside.gain<1,'rain becomes quieter only after player exits front')
local half=sample(1300,0,.1)
ck(near(half.gain,.5,1e-6),'front rain uses smooth physical distance attenuation outside')
local inaudible=sample(2500,0,.1)
ck(inaudible.present and near(inaudible.gain,0,1e-9),'receding front retains authority through zero-gain tail so local bed cannot snap back')
local _,q2=sample(-900,450,.1)
ck(q2 and near(q2.bankX,bankX,1e-9) and near(q2.bankZ,bankZ,1e-9),'player/camera-relative position cannot drag front cloud anchor')

local t1=D.motionTime();D.update(.25,999,999);local t2=D.motionTime();D.update(-3,999,999);local t3=D.motionTime()
ck(t2>t1 and t3>=t2,'front precipitation clock is monotonic and cannot reverse rain phase')

-- Around old named stage boundaries the shaft/cloud values must be continuous.
local function atU(u)
  cell.age=cell.life*u
  D.update(.01,300,0)
  local items,n=D.items();local x=items[1]
  return x and x.shaft or 0,x and x.cloud or 0
end
local s119,c119=atU(.119);local s121,c121=atU(.121)
local s299,c299=atU(.299);local s301,c301=atU(.301)
ck(math.abs(s121-s119)<.08 and math.abs(s301-s299)<.08,'precipitation maturity does not jump at formation/growth/mature stage labels')
ck(math.abs(c121-c119)<.08 and math.abs(c301-c299)<.08,'front cloud opacity is continuous across lifecycle stage labels')

-- Full Audio mixer: a front must override a still-high local eased rain channel.
local function newSource(path)
  local s={path=path,playing=false,volume=0,pitch=1}
  function s:clone() return newSource(self.path) end;function s:setLooping(v) self.looping=v end
  function s:setVolume(v) self.volume=v end;function s:setPitch(v) self.pitch=v end;function s:getVolume() return self.volume end
  function s:play() self.playing=true end;function s:stop() self.playing=false end;function s:isPlaying() return self.playing end
  function s:seek() end;function s:setFilter() return false end
  return s
end
love={audio={newSource=function(path)return newSource(path)end},math={random=function() return 1 end}}
local cfg={audio={enabled=true,volume=1,indoors=.24,battle=.35,wind=false,thunder=false,thunderGain=.8}}
local scene={now={mapId='ROUTE_1',visible='world',indoors=false}}
local rainDef={id='RAIN_LIGHT',rain=1,snow=0,gust=0,strike=0}
local state={id='RAIN_LIGHT',channel=function(k) return k=='rain' and 1 or 0 end,current=function() return rainDef end}
local frontState={present=true,gain=1,weather='RAIN_LIGHT',inside=true,edge=0}
local DW={rainAudio=function() return frontState end,takeThunderEvents=function() return nil end}
local T={
  channel=function(def,k) return tonumber(def and def[k]) or 0 end,
  get=function(id) if tostring(id):upper()=='RAIN_LIGHT' then return rainDef end return {id=tostring(id):upper()} end
}
local settings={get=function(k) if k=='sfx' then return 'high' elseif k=='lightning' then return 'off' end end,weatherDisabled=function() return false end}
local lightning={age=0,justStruck=false,strikeSerial=0};local legendary={thunderSound=function() return 'thunder_clap' end}
local mod={assets={path=function(_,p) return p end},log={warn=function() end}};function mod:read() return nil end
local VA={mod=mod};function VA.require(n)
  local t={Types=T,Config={get=function() return cfg end},Settings=settings,Scene=scene,WeatherState=state,Lightning=lightning,Legendary=legendary,DistantWeather=DW}
  assert(t[n],'unexpected require '..tostring(n));return t[n]
end
local A=assert(loadfile(ROOT..'lib/Audio.lua'))(VA)
for _=1,30 do A.update(1/60) end
local bed=(A.slots[1].file and A.slots[1]) or A.slots[2]
ck(bed and near(bed.level,.55,.02),'front overhead reaches authored 100% rain-bed gain')
frontState.inside=false;frontState.edge=1200;frontState.gain=.5
for _=1,30 do A.update(1/60) end
ck(bed and near(bed.level,.275,.02),'receding physical front attenuates bed even while local eased rain channel remains high')
frontState.gain=.25;for _=1,30 do A.update(1/60) end
ck(bed and near(bed.level,.1375,.02),'front distance remains authoritative instead of local channel snapping rain back to full')

-- Indoor attenuation is allowed to muffle, never nearly mute, automatic weather.
cfg.audio.indoors=.12
scene.now.indoors=true
A._indoorMix=1
ck(near(A.masterGain(),.40,1e-9),'legacy indoor gain below 40 percent is clamped to the 40 percent retained floor')
ck((A.INDOOR_ACOUSTICS.rainHighGain or 0)>=.40 and (A.INDOOR_ACOUSTICS.windHighGain or 0)>=.40 and (A.INDOOR_ACOUSTICS.thunderHighGain or 0)>=.40,'indoor low-pass never retains less than 40 percent high-frequency energy')

print(string.format('front audio/motion/cloud 8.1.52: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
