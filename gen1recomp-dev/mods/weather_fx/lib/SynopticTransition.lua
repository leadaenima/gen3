local V = ...

-- SynopticTransition
-- ------------------
-- A zero-allocation transition planner for natural AUTO/front weather changes.
-- WeatherState remains the single weather authority; this module only answers
-- *how* one set of channels should become another.  It deliberately stages the
-- atmosphere in the order real weather is perceived:
--
--   clouds / pressure / wind -> precipitation -> convection / lightning
--
-- Clearing runs in the opposite perceptual order:
--
--   lightning -> heavy precipitation -> showers -> cloud break -> sunlight
--
-- Manual/config pins do not use this planner.  They keep the immediate sky
-- response players expect from selecting a weather in the menu.

local Types = V.require("Types")
local T = {}

local state = {
  active=false, from="CLEAR", to="CLEAR", kind="none", elapsed=0, duration=0,
  u=1, cloudU=1, precipU=1, stormU=1, atmosU=1, lightU=1, windU=1,
  cloudTarget=.10, humidityTarget=.34, stormTarget=0, windTarget=.10,
  visibilityTarget=1, pressureTarget=1018, precipTarget=0,
  serial=0,
}

local fromM = {}
local toM = {}

local PRECIP = { rain=true, snow=true, hail=true, sand=true, ash=true, debris=true }
local PRECIP_RATE = {
  rainSpeed=true, rainAngle=true, rainLen=true, splash=true,
  snowSpeed=true, snowDrift=true, fogSpeed=true,
}
local ATMOS = { fog=true, veil=true, dim=true, cool=true }
local LIGHT = { warm=true, glare=true }
local WIND = { gust=true }

local function clamp01(v)
  v=tonumber(v) or 0
  if v<0 then return 0 elseif v>1 then return 1 end
  return v
end
local function lerp(a,b,u) return a+(b-a)*u end
local function smooth01(v)
  v=clamp01(v)
  return v*v*(3-2*v)
end
local function range(u,a,b)
  if u<=a then return 0 end
  if u>=b then return 1 end
  return smooth01((u-a)/math.max(1e-6,b-a))
end
local function ch(def,key)
  return def and (tonumber(Types.channel(def,key)) or 0) or 0
end
local function precipAmount(def)
  return math.max(ch(def,"rain"),ch(def,"snow"),ch(def,"hail"),ch(def,"sand"),ch(def,"ash"),ch(def,"debris"))
end
local function dominant(def)
  local best,bv="none",0
  for k in pairs(PRECIP) do
    local v=ch(def,k)
    if v>bv then best,bv=k,v end
  end
  return best,bv
end
local function derive(def,out)
  local rain,snow,hail=ch(def,"rain"),ch(def,"snow"),ch(def,"hail")
  local fog,veil,dim=ch(def,"fog"),ch(def,"veil"),ch(def,"dim")
  local warm,cool,gust,strike=ch(def,"warm"),ch(def,"cool"),ch(def,"gust"),ch(def,"strike")
  local precip=clamp01(math.max(rain,snow,hail,ch(def,"sand"),ch(def,"ash"),ch(def,"debris")))
  out.precip=precip
  out.humidity=clamp01(.34+rain*.55+snow*.42+fog*.32+hail*.16)
  out.cloud=clamp01(.10+precip*.72+dim*.55+fog*.22+veil*.08)
  out.storm=clamp01(strike/36+dim*.42+gust*.18)
  out.wind=clamp01(.10+gust*.75+out.storm*.20)
  out.visibility=clamp01(1-fog*.58-veil*.50-precip*.18)
  out.pressure=1018-out.storm*24-precip*9+warm*3
  out.sun=clamp01(warm*.55+ch(def,"glare")*.75)
  return out
end

local function classify(a,b)
  local pa,pb=precipAmount(a),precipAmount(b)
  local fa=dominant(a); local fb=dominant(b)
  local sa,sb=ch(a,"strike"),ch(b,"strike")
  local ga,gb=ch(a,"gust"),ch(b,"gust")
  if pa<=.04 and pb>.04 then return "onset" end
  if pa>.04 and pb<=.04 then return "clearing" end
  if pa>.04 and pb>.04 and fa~=fb then return "phase_change" end
  if pb>pa+.08 or sb>sa+1 or gb>ga+.16 then return "intensify" end
  if pa>pb+.08 or sa>sb+1 or ga>gb+.16 then return "weaken" end
  return "dry_shift"
end

local BASE_DURATION = {
  onset=58, clearing=66, intensify=52, weaken=56, phase_change=62, dry_shift=46,
}

function T.duration(fromDef,toDef,baseSeconds)
  local kind=classify(fromDef,toDef)
  local scale=(tonumber(baseSeconds) or 3.2)/3.2
  if scale<.55 then scale=.55 elseif scale>2.25 then scale=2.25 end
  local d=(BASE_DURATION[kind] or 52)*scale
  -- Severe convective targets deserve time for the cloud deck to build before
  -- the first close strikes.  This costs no additional particles.
  if ch(toDef,"strike")>=12 then d=d+8*scale end
  return math.max(28,d),kind
end

function T.begin(fromId,toId,baseSeconds)
  local a=Types.get(fromId); local b=Types.get(toId)
  local dur,kind=T.duration(a,b,baseSeconds)
  derive(a,fromM); derive(b,toM)
  state.active=true; state.from=a.id; state.to=b.id; state.kind=kind
  state.elapsed=0; state.duration=dur; state.u=0; state.serial=state.serial+1
  T.update(0,a.id,b.id,0,dur)
  return dur,kind
end

function T.update(dt,fromId,toId,elapsed,duration)
  if not state.active then return state end
  if (fromId and Types.get(fromId).id~=state.from) or (toId and Types.get(toId).id~=state.to) then
    T.begin(fromId or state.from,toId or state.to,3.2)
  end
  state.elapsed=math.max(0,tonumber(elapsed) or (state.elapsed+math.max(0,tonumber(dt) or 0)))
  state.duration=math.max(.001,tonumber(duration) or state.duration or 1)
  local u=clamp01(state.elapsed/state.duration)
  state.u=u

  local k=state.kind
  if k=="onset" then
    state.cloudU=range(u,.00,.38)
    state.atmosU=range(u,.04,.56)
    state.windU=range(u,.08,.62)
    state.precipU=range(u,.27,.92)
    state.stormU=range(u,.58,.98)
    state.lightU=range(u,.00,.42)
  elseif k=="clearing" then
    state.stormU=range(u,.00,.28)
    state.precipU=range(u,.06,.70)
    state.windU=range(u,.12,.78)
    state.atmosU=range(u,.24,.90)
    state.cloudU=range(u,.50,1.00)
    state.lightU=range(u,.62,1.00)
  elseif k=="intensify" then
    state.cloudU=range(u,.00,.42)
    state.atmosU=range(u,.05,.58)
    state.windU=range(u,.08,.66)
    state.precipU=range(u,.16,.90)
    state.stormU=range(u,.43,.97)
    state.lightU=range(u,.00,.50)
  elseif k=="weaken" then
    state.stormU=range(u,.00,.34)
    state.windU=range(u,.12,.72)
    state.precipU=range(u,.18,.84)
    state.atmosU=range(u,.28,.91)
    state.cloudU=range(u,.38,.96)
    state.lightU=range(u,.58,1.00)
  elseif k=="phase_change" then
    state.cloudU=range(u,.04,.84)
    state.atmosU=range(u,.08,.82)
    state.windU=range(u,.08,.78)
    state.precipU=range(u,.14,.88)
    state.stormU=range(u,.30,.94)
    state.lightU=range(u,.20,.88)
  else
    local s=smooth01(u)
    state.cloudU=s; state.atmosU=s; state.windU=s; state.precipU=s; state.stormU=s; state.lightU=s
  end

  state.cloudTarget=lerp(fromM.cloud or .1,toM.cloud or .1,state.cloudU)
  state.humidityTarget=lerp(fromM.humidity or .4,toM.humidity or .4,state.atmosU)
  state.stormTarget=lerp(fromM.storm or 0,toM.storm or 0,state.stormU)
  state.windTarget=lerp(fromM.wind or .1,toM.wind or .1,state.windU)
  state.visibilityTarget=lerp(fromM.visibility or 1,toM.visibility or 1,state.atmosU)
  state.pressureTarget=lerp(fromM.pressure or 1013,toM.pressure or 1013,state.atmosU)
  state.precipTarget=lerp(fromM.precip or 0,toM.precip or 0,state.precipU)
  return state
end

local function phaseBlend(a,b,u)
  local outW=1-range(u,.30,.94)
  local inW=range(u,.08,.78)
  local mixed=a*outW+b*inW
  local cap=math.max(a,b)*1.06
  if cap>0 and mixed>cap then mixed=cap end
  return mixed
end

function T.goal(key,a,b)
  a=tonumber(a) or 0; b=tonumber(b) or 0
  if not state.active then return b end
  if state.kind=="phase_change" and PRECIP[key] then
    return phaseBlend(a,b,state.u)
  end
  local u=state.u
  if PRECIP[key] or PRECIP_RATE[key] then u=state.precipU
  elseif key=="strike" then u=state.stormU
  elseif ATMOS[key] then u=state.atmosU
  elseif LIGHT[key] then u=state.lightU
  elseif WIND[key] then u=state.windU end
  return lerp(a,b,u)
end

function T.peek() return state end
function T.active() return state.active end
function T.reset()
  state.active=false; state.from="CLEAR"; state.to="CLEAR"; state.kind="none"
  state.elapsed=0; state.duration=0; state.u=1; state.cloudU=1; state.precipU=1
  state.stormU=1; state.atmosU=1; state.lightU=1; state.windU=1
  state.cloudTarget=.10; state.humidityTarget=.34; state.stormTarget=0; state.windTarget=.10
  state.visibilityTarget=1; state.pressureTarget=1018; state.precipTarget=0
end
function T.describe()
  return string.format("%s %s>%s %d%% cloud=%d%% precip=%d%% storm=%d%%",
    state.kind,state.from,state.to,state.u*100,state.cloudU*100,state.precipU*100,state.stormU*100)
end

return T
