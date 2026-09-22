local V = ...

local Sim = {}
local state={pressure=1013,humidity=.45,temperature=14,cloud=.15,storm=.0,wind=.12,visibility=1,precip=.0,aerosol=.05,pressureTrend=0,dewPoint=2,stormPotential=0,frontPhase=0}
local target={}
local elapsed=0

local function clamp01(v) if v<0 then return 0 elseif v>1 then return 1 end return v end
local function ch(weather,k) if weather and weather.channel then local ok,v=pcall(weather.channel,k); if ok then return tonumber(v) or 0 end end; return weather and weather.ch and tonumber(weather.ch[k]) or 0 or 0 end
local function approach(a,b,dt,tau) local f=1-math.exp(-dt/math.max(.01,tau)); return a+(b-a)*f end
local function mix(a,b,w) return (tonumber(a) or 0)+((tonumber(b) or 0)-(tonumber(a) or 0))*w end

local function derive(weather)
  local rain,snow,hail=ch(weather,"rain"),ch(weather,"snow"),ch(weather,"hail")
  local fog,veil,dim=ch(weather,"fog"),ch(weather,"veil"),ch(weather,"dim")
  local warm,cool,gust,strike=ch(weather,"warm"),ch(weather,"cool"),ch(weather,"gust"),ch(weather,"strike")
  local precip=clamp01(math.max(rain,snow,hail))
  target.humidity=clamp01(.34+rain*.55+snow*.42+fog*.32)
  target.temperature=14 + warm*16 - cool*15 - snow*9 - hail*5
  target.cloud=clamp01(.10+precip*.72+dim*.55+fog*.22)
  target.storm=clamp01(strike/36 + dim*.42 + gust*.18)
  target.wind=clamp01(.10+gust*.75+target.storm*.20)
  target.visibility=clamp01(1-fog*.58-veil*.50-precip*.18)
  target.precip=precip
  target.aerosol=clamp01(.04+veil*.42+fog*.22+ch(weather,"ash")*.62+ch(weather,"sand")*.52)
  target.pressure=1018-target.storm*24-precip*9+warm*3
end

local function dewPoint(t,h)
  h=math.max(.01,math.min(1,h)); local a,b=17.27,237.7; local alpha=(a*t)/(b+t)+math.log(h); return (b*alpha)/(a-alpha)
end

function Sim.update(dt,weather)
  dt=math.max(0,tonumber(dt) or 0); elapsed=elapsed+dt; derive(weather)

  -- Natural AUTO/front handoffs publish a synoptic plan.  It is intentionally
  -- meteorological rather than visual: cloud/humidity/wind can lead rain, and
  -- a clearing deck can linger after precipitation has weakened.  This keeps
  -- the macro climate, cloud field and renderer on the same evolving state.
  local syn=nil
  if weather and weather.synoptic then
    local v=weather.synoptic()
    if type(v)=="table" and v.active then syn=v end
  end
  if syn then
    target.cloud=clamp01(mix(target.cloud,syn.cloudTarget,.82))
    target.humidity=clamp01(mix(target.humidity,syn.humidityTarget,.64))
    target.storm=clamp01(mix(target.storm,syn.stormTarget,.72))
    target.wind=clamp01(mix(target.wind,syn.windTarget,.58))
    target.visibility=clamp01(mix(target.visibility,syn.visibilityTarget,.55))
    target.pressure=mix(target.pressure,syn.pressureTarget,.58)
    target.precip=clamp01(mix(target.precip,syn.precipTarget,.55))
  end

  local oldPressure=state.pressure
  state.pressure=approach(state.pressure,target.pressure or state.pressure,dt,syn and 12 or 32)
  state.humidity=approach(state.humidity,target.humidity or state.humidity,dt,syn and 7 or 18)
  state.temperature=approach(state.temperature,target.temperature or state.temperature,dt,28)
  state.cloud=approach(state.cloud,target.cloud or state.cloud,dt,syn and 4.5 or 15)
  state.storm=approach(state.storm,target.storm or state.storm,dt,syn and 5.5 or 12)
  state.wind=approach(state.wind,target.wind or state.wind,dt,syn and 5.5 or 9)
  state.visibility=approach(state.visibility,target.visibility or state.visibility,dt,syn and 6 or 12)
  state.precip=approach(state.precip,target.precip or state.precip,dt,syn and 4.5 or 8)
  state.aerosol=approach(state.aerosol,target.aerosol or state.aerosol,dt,18)
  local trend=(state.pressure-oldPressure)/math.max(dt,.001)
  state.pressureTrend=approach(state.pressureTrend,trend,dt,8)
  state.dewPoint=dewPoint(state.temperature,state.humidity)
  state.stormPotential=clamp01(state.storm*.62+state.humidity*.24+math.max(0,-state.pressureTrend)*.06+state.cloud*.14)
  state.frontPhase=(state.frontPhase+dt*(.004+.012*state.wind))%(math.pi*2)
end

function Sim.peek() return state end
function Sim.sample() local o={}; for k,v in pairs(state) do o[k]=v end; o.elapsed=elapsed; return o end
function Sim.target() local o={}; for k,v in pairs(target) do o[k]=v end; return o end
function Sim.reset() state={pressure=1013,humidity=.45,temperature=14,cloud=.15,storm=0,wind=.12,visibility=1,precip=0,aerosol=.05,pressureTrend=0,dewPoint=2,stormPotential=0,frontPhase=0}; elapsed=0 end
function Sim.describe() return string.format("P=%.1fhPa H=%.0f%% T=%.1fC cloud=%.0f%% storm=%.0f%% vis=%.0f%%",state.pressure,state.humidity*100,state.temperature,state.cloud*100,state.storm*100,state.visibility*100) end

return Sim
