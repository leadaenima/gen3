local V = ...

-- Weather FX 8.0.8 mesoscale weather field.
--
-- Purpose: bridge the gap between the 1 km-ish WorldClimate cells and the
-- particle/cloud renderers. Real weather is not spatially uniform around an
-- observer: showers have edges, storm decks contain denser bands, fog pools,
-- and broken cloud moves through otherwise stable synoptic conditions.
--
-- This is deliberately NOT a fluid solver. A pair of deterministic smooth
-- world-space noise fields plus one moving front coordinate reconstructs the
-- local state on demand. Runtime memory is O(1), there are no per-frame cell
-- allocations, and callers may use sampleInto() on hot paths.
local M={}
local Types=V.require("Types")

local abs,floor,sin,cos,pi=math.abs,math.floor,math.sin,math.cos,math.pi
local TWO_PI=pi*2
local PATCH_SCALE=520
local FRONT_SCALE=1180
local elapsed=0
local serial=0
local lastSpeed=0
local advectX,advectZ=0,0
local windX,windZ=.8,.25
local base={pressure=1013,temperature=14,humidity=.45,cloud=.15,storm=0,wind=.12,precip=0,visibility=1,aerosol=.05}
local localState={}
local renderState={scale=PATCH_SCALE,frontScale=FRONT_SCALE,offsetX=0,offsetZ=0,windX=.8,windZ=.25,patchiness=.35,floor=.45,fogScale=1,storm=0,cloud=.15,precip=0,serial=0}
local BASE_KEYS={'pressure','temperature','humidity','cloud','storm','wind','precip','visibility','aerosol'}
local _Wind=nil
local fieldEnabled=true
local fieldStrength=1.0
local _StormCells=nil
local stormScratch={}

local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function smooth(v) v=clamp(v,0,1); return v*v*(3-2*v) end
local function mix(a,b,t) return a+(b-a)*t end
local function hash(x,z,s)
  local n=sin(x*127.17+z*311.71+s*73.13)*43758.5453
  return n-floor(n)
end
local function valueNoise(x,z,scale,seed)
  local fx=x/scale; local fz=z/scale
  local ix,iz=floor(fx),floor(fz); local tx,tz=smooth(fx-ix),smooth(fz-iz)
  local a=hash(ix,iz,seed); local b=hash(ix+1,iz,seed)
  local c=hash(ix,iz+1,seed); local d=hash(ix+1,iz+1,seed)
  return mix(mix(a,b,tx),mix(c,d,tx),tz)
end
local function copyBase(src)
  src=src or base
  for i=1,#BASE_KEYS do local k=BASE_KEYS[i]
    local v=tonumber(src[k]); if v~=nil then base[k]=v end
  end
end
local function windState()
  if not _Wind then local ok,W=pcall(V.require,'WindEngine'); if ok and W then _Wind=W end end
  local W=_Wind
  if W then
    local s=W.peek and W.peek() or (W.state and W.state())
    if type(s)=='table' then return s end
  end
end

function M.update(dt,macro,world,x,z)
  dt=math.max(0,tonumber(dt) or 0); elapsed=elapsed+dt; serial=serial+1
  -- Read the player/config switch once per mesoscale update, never per particle.
  -- The Settings overlay is applied inside Config.get(), so this remains one
  -- authority for folder installs and packed in-game options.
  pcall(function()
    local C=V.require("Config"); local c=C and C.get and C.get(); local m=c and c.mesoscale
    if type(m)=="table" then
      fieldEnabled=m.enabled~=false
      fieldStrength=clamp(tonumber(m.strength) or 1.0,0,1.5)
    end
  end)
  -- WorldClimate is already spatially biased; prefer its local sample over the
  -- macro state, while retaining macro as the fallback during early boot.
  copyBase(world or macro or base)
  local w=windState()
  if w then
    local wx,wz=tonumber(w.x) or 0,tonumber(w.z) or 0
    local wl=math.sqrt(wx*wx+wz*wz)
    if wl>1e-5 then windX,windZ=wx/wl,wz/wl end
    -- Move mesoscale structures in world space. This is intentionally faster
    -- than the cloud-lobe advection itself: it represents a broad pressure/
    -- moisture field carrying cloud-generating conditions across the world.
    local speed=1.2+math.min(1.4,tonumber(w.strength) or tonumber(base.wind) or 0)*7.5
    lastSpeed=speed
    advectX=advectX+windX*speed*dt
    advectZ=advectZ+windZ*speed*dt
  else
    local speed=.8+math.min(1.2,tonumber(base.wind) or 0)*5
    lastSpeed=speed
    advectX=advectX+windX*speed*dt; advectZ=advectZ+windZ*speed*dt
  end
  M.sampleInto(x or 0,z or 0,localState)
  local coherence=clamp((tonumber(base.storm) or 0)*.72+(tonumber(base.precip) or 0)*.28,0,1)
  renderState.scale=PATCH_SCALE; renderState.frontScale=FRONT_SCALE
  renderState.offsetX=advectX; renderState.offsetZ=advectZ
  renderState.windX=windX; renderState.windZ=windZ
  if fieldEnabled then
    renderState.patchiness=clamp((.78-coherence*.62)*fieldStrength,0.02,.92)
    renderState.floor=clamp(1-(1-(.03+coherence*.80))*fieldStrength,.03,1.0)
  else
    renderState.patchiness=0
    renderState.floor=1
  end
  renderState.storm=tonumber(localState.storm) or 0
  renderState.cloud=tonumber(localState.cloud) or 0
  renderState.precip=tonumber(localState.precip) or 0
  renderState.fogScale=tonumber(localState.fogScale) or 1
  renderState.serial=serial
  return localState
end

local function sampleCore(x,z,out,extraX,extraZ)
  out=out or {}; local rawX,rawZ=tonumber(x) or 0,tonumber(z) or 0
  x=rawX-advectX-(tonumber(extraX) or 0); z=rawZ-advectZ-(tonumber(extraZ) or 0)
  local n1=valueNoise(x,z,PATCH_SCALE,11)
  local n2=valueNoise(x+173,z-291,PATCH_SCALE*1.83,23)
  local along=x*windX+z*windZ
  local cross=-x*windZ+z*windX
  local wave=.5+.5*sin(along/FRONT_SCALE*TWO_PI + sin(cross/(FRONT_SCALE*.71)*TWO_PI)*.72)
  local moisture=clamp(n1*.52+n2*.26+wave*.22,0,1)
  local stormBase=clamp(tonumber(base.storm) or 0,0,1)
  local precipBase=clamp(tonumber(base.precip) or 0,0,1)
  local cloudBase=clamp(tonumber(base.cloud) or .15,0,1)
  local humidityBase=clamp(tonumber(base.humidity) or .45,0,1)
  local coherence=clamp(stormBase*.72+precipBase*.28,0,1)

  -- Finite physical storm cells override the old infinite periodic field where
  -- present. Their cloud precursor extends beyond the rain core, so a player
  -- can see a storm gathering one or two maps before walking into rain.
  if not _StormCells then local ok,S=pcall(V.require,"StormCells");if ok and S then _StormCells=S end end
  local cellQ=_StormCells and _StormCells.sampleInto and _StormCells.sampleInto(rawX,rawZ,stormScratch) or nil
  if cellQ and (tonumber(cellQ.cloud) or 0)>.001 then
    local wid=cellQ.weather or cellQ.cloudWeather
    -- Types is Weather FX-owned and generation-independent; resolving it once
    -- removes a protected module lookup from every cloud/mesoscale probe.
    local d=Types and Types.get and Types.get(wid) or nil;local ch=d and d.ch or {}
    local p=math.max(tonumber(ch.rain) or 0,tonumber(ch.snow) or 0,tonumber(ch.hail) or 0,tonumber(ch.sand) or 0,tonumber(ch.ash) or 0)
    p=clamp(p,0,1)
    local cs=clamp(tonumber(cellQ.cloud) or 0,0,1);local ps=clamp(tonumber(cellQ.precip) or 0,0,1)
    local ss=clamp((tonumber(ch.strike) or 0)/24+(tonumber(ch.gust) or 0)*.45+(tonumber(ch.dim) or 0)*.45,0,1)
    precipBase=math.max(precipBase,p*ps)
    cloudBase=math.max(cloudBase,clamp((.20+p*.66+(tonumber(ch.dim) or 0)*.32)*cs,0,1))
    stormBase=math.max(stormBase,ss*ps)
    coherence=clamp(stormBase*.72+precipBase*.28,0,1)
  end

  -- Light precipitation keeps pronounced shower bands. Severe systems become
  -- broad/continuous, which is why a manually-selected thunderstorm still
  -- covers the sky immediately instead of producing arbitrary dry holes.
  local precipFloor=.03+coherence*.80
  local precipShape=precipFloor+(1-precipFloor)*smooth(clamp((moisture-.16)/.78,0,1))
  local localPrecip=clamp(precipBase*precipShape,0,1)
  local cloudFloor=cloudBase*(.52+coherence*.34)
  local cloudShape=clamp(cloudBase*(.68+moisture*.48)+humidityBase*.055+stormBase*.055,0,1)
  local localCloud=math.max(cloudFloor,cloudShape)
  local localStorm=clamp(stormBase*(.76+moisture*.34),0,1)
  local localHumidity=clamp(humidityBase+(moisture-.5)*.10+localPrecip*.035,0,1)
  local spatial=fieldEnabled and fieldStrength or 0
  localPrecip=clamp(mix(precipBase,localPrecip,spatial),0,1)
  localCloud=clamp(mix(cloudBase,localCloud,spatial),0,1)
  localStorm=clamp(mix(stormBase,localStorm,spatial),0,1)
  localHumidity=clamp(mix(humidityBase,localHumidity,spatial),0,1)

  out.pressure=mix(tonumber(base.pressure) or 1013,(tonumber(base.pressure) or 1013)+(moisture-.5)*2.6-localStorm*1.1,spatial)
  out.temperature=mix(tonumber(base.temperature) or 14,(tonumber(base.temperature) or 14)+(n2-.5)*1.05-localPrecip*.35,spatial)
  out.humidity=localHumidity
  out.cloud=localCloud
  out.storm=localStorm
  out.wind=clamp(mix(tonumber(base.wind) or .12,(tonumber(base.wind) or .12)*( .94+wave*.12 ),spatial),0,1.3)
  out.precip=localPrecip
  local baseVisibility=clamp(tonumber(base.visibility) or 1,0,1)
  local baseObscure=1-baseVisibility
  local fogShape=clamp(mix(1,.42+moisture*.76,spatial),0.28,1.22)
  local fogObscure=baseObscure*fogShape
  out.visibility=clamp(1-fogObscure-localPrecip*.055-math.max(0,localHumidity-.88)*.055,0,1)
  out.fogScale=baseObscure>.02 and clamp(fogObscure/baseObscure,.28,1.32) or 1
  out.aerosol=clamp(mix(tonumber(base.aerosol) or .05,(tonumber(base.aerosol) or .05)+(n1-.5)*.025,spatial),0,1)
  out.precipScale=precipBase>0.001 and clamp(localPrecip/precipBase,.05,1.15) or 0
  out.cloudScale=cloudBase>0.001 and clamp(localCloud/cloudBase,.20,1.35) or 1
  out.stormScale=stormBase>0.001 and clamp(localStorm/stormBase,.35,1.25) or 0
  out.band=moisture
  out.front=wave
  if cellQ then out.cellStrength=tonumber(cellQ.precip) or 0;out.cellCloud=tonumber(cellQ.cloud) or 0;out.cellStage=cellQ.stage;out.cellWeather=cellQ.weather or cellQ.cloudWeather end
  out.patchiness=clamp(.78-coherence*.62,0.10,.78)
  out.cellSize=PATCH_SCALE
  out.serial=serial
  return out
end

function M.sampleInto(x,z,out) return sampleCore(x,z,out,0,0) end
function M.sampleAt(x,z) local o={}; return sampleCore(x,z,o,0,0) end
function M.forecastAt(x,z,seconds)
  seconds=math.max(0,tonumber(seconds) or 0)
  local o={}; sampleCore(x,z,o,windX*lastSpeed*seconds,windZ*lastSpeed*seconds); o.seconds=seconds; return o
end
function M.ready() return serial>0 end
function M.peek() return localState end
function M.sample() local o={}; for k,v in pairs(localState) do o[k]=v end; return o end
function M.renderParams() return renderState end
function M.stats()
  return {cellSize=PATCH_SCALE,frontScale=FRONT_SCALE,serial=serial,advectX=advectX,advectZ=advectZ,speed=lastSpeed,
    cloud=tonumber(localState.cloud) or 0,precip=tonumber(localState.precip) or 0,band=tonumber(localState.band) or 0,
    patchiness=tonumber(localState.patchiness) or 0,enabled=fieldEnabled,strength=fieldStrength,memory='O(1)'}
end
function M.reset()
  elapsed,serial,advectX,advectZ,lastSpeed=0,0,0,0,0; windX,windZ=.8,.25
  for k in pairs(localState) do localState[k]=nil end
end
return M
