local V = ...

-- Spatial microclimate layer. Macro WeatherSimulation remains authoritative for
-- the selected weather; this layer creates bounded local temperature/humidity/
-- cloud/wind differences so forests, coasts, cities, caves and distant chunks
-- need not all feel numerically identical.
local M={}
local state={pressure=1013,humidity=.45,temperature=14,cloud=.15,storm=0,wind=.12,visibility=1,precip=0,aerosol=.05,dewPoint=2,locality=0,shelter=0,built=0,canopy=0,water=0,open=1,windShadow=0,fogAffinity=0}
local elapsed=0
local CELL=384
local mapScratch={temp=0,humid=0,wind=0,cloud=0,visibility=0}
local targetScratch={}
local footprintScratch={}
local _FlatWorld=nil
local _Wind=nil
local _ConnectedWater=nil

local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function hash(x,z,s)
  local n=math.sin((x*127.1+z*311.7+s*74.7))*43758.5453123
  return n-math.floor(n)
end
local function mapModifier(scene,m)
  local id=tostring(scene and (scene.mapId or scene.map or scene.name) or ""):lower()
  m=m or mapScratch; m.temp,m.humid,m.wind,m.cloud,m.visibility=0,0,0,0,0
  if scene and scene.indoors then m.temp=.8; m.humid=-.04; m.wind=-.75 end
  if id:find("cave",1,true) or id:find("tunnel",1,true) then m.temp=-3;m.humid=.16;m.wind=-.75;m.visibility=-.05 end
  -- These name-based modifiers are only a 2D/host fallback. In voxel worlds the
  -- live horizontal footprint below is authoritative. There is deliberately no
  -- mountain/peak/orographic branch: this game world is flat.
  if id:find("forest",1,true) or id:find("woods",1,true) then m.temp=-1.0;m.humid=.08;m.wind=-.16;m.cloud=.03 end
  if id:find("sea",1,true) or id:find("coast",1,true) or id:find("island",1,true) or id:find("lake",1,true) then m.temp=-.35;m.humid=.10;m.wind=.08;m.cloud=.03 end
  if id:find("city",1,true) or id:find("town",1,true) then m.temp=.75;m.humid=-.025;m.wind=-.07 end
  if id:find("route",1,true) or id:find("field",1,true) then m.wind=.06 end
  return m
end

local function flatWorld()
  if _FlatWorld~=nil then return _FlatWorld or nil end
  local ok,m=pcall(V.require,"FlatWorldInteraction");_FlatWorld=(ok and m) or false;return _FlatWorld or nil
end
local function windModule()
  if _Wind~=nil then return _Wind or nil end
  local ok,m=pcall(V.require,"WindEngine");_Wind=(ok and m) or false;return _Wind or nil
end
local function connectedWater()
  if _ConnectedWater~=nil then return _ConnectedWater or nil end
  local ok,m=pcall(V.require,"ConnectedWater");_ConnectedWater=(ok and m) or false;return _ConnectedWater or nil
end
local function dewPoint(t,h)
  h=clamp(h,.01,1); local a,b=17.27,237.7
  local alpha=(a*t)/(b+t)+math.log(h)
  return (b*alpha)/(a-alpha)
end
function M.update(dt,base,x,z,scene)
  dt=math.max(0,tonumber(dt) or 0); elapsed=elapsed+dt; base=base or {}
  x,z=tonumber(x) or 0,tonumber(z) or 0
  local cx,cz=math.floor(x/CELL),math.floor(z/CELL)
  -- Slow advection makes local pockets move rather than stick permanently to a tile.
  local ax=elapsed*.010*(tonumber(base.wind) or .1); local az=elapsed*.006
  local n=hash(cx+ax,cz+az,1)-.5; local n2=hash(cx+ax*.7,cz-az*.8,2)-.5
  local mm=mapModifier(scene,mapScratch)
  local fw=flatWorld();local fp=footprintScratch
  for k in pairs(fp) do fp[k]=nil end
  if fw and fw.ready and fw.ready() and fw.sampleAt then
    local wx,wz=0,0;local W=windModule();local ws=W and W.peek and W.peek() or nil
    if ws then wx,wz=tonumber(ws.x) or 0,tonumber(ws.z) or 0 end
    fw.sampleAt(x,z,fp,wx,wz)
  else
    fp.shelter,fp.built,fp.canopyFraction,fp.waterFraction,fp.openFraction=0,0,0,0,1
    fp.windShadow,fp.windExposure,fp.tempBias,fp.humidityBias,fp.fogAffinity=0,1,0,0,0
  end
  local target=targetScratch
  local liquidScale=1
  local CW=connectedWater()
  if CW and CW.liquidFractionNear then liquidScale=clamp(CW.liquidFractionNear(x,z,2),0,1) end
  local waterFraction=clamp(tonumber(fp.waterFraction) or 0,0,1)
  local liquidWater=waterFraction*liquidScale
  local iceWater=waterFraction-liquidWater
  target.pressure=(tonumber(base.pressure) or 1013)+n*3.8
  target.temperature=(tonumber(base.temperature) or 14)+n*2.2+mm.temp+(tonumber(fp.tempBias) or 0)-iceWater*1.9
  -- Open water contributes humidity; a frozen body retains the cold thermal
  -- signature but largely shuts down evaporation and water fog.
  target.humidity=clamp((tonumber(base.humidity) or .45)+n2*.13+mm.humid+(tonumber(fp.humidityBias) or 0)-iceWater*.11,0,1)
  target.cloud=clamp((tonumber(base.cloud) or .15)+n*.12+target.humidity*.05+mm.cloud+liquidWater*.025,0,1)
  target.storm=clamp((tonumber(base.storm) or 0)+math.max(0,n2)*.10,0,1)
  local exposure=clamp(tonumber(fp.windExposure) or 1,.05,1.18)
  target.wind=clamp(((tonumber(base.wind) or .12)*(1+mm.wind)+math.abs(n)*.08)*exposure,0,1)
  local fogAffinity=(tonumber(fp.fogAffinity) or 0)*(0.12+0.88*liquidScale)
  target.visibility=clamp((tonumber(base.visibility) or 1)+mm.visibility-target.humidity*.035-fogAffinity*math.max(0,target.humidity-.58)*.16,0,1)
  local precipShelter=scene and scene.indoors and .08 or (1-clamp(tonumber(fp.shelter) or 0,0,.96)*.78)
  target.precip=clamp((tonumber(base.precip) or 0)*precipShelter,0,1)
  target.aerosol=clamp((tonumber(base.aerosol) or .05)+math.abs(n2)*.04,0,1)
  target.shelter=clamp(tonumber(fp.shelter) or 0,0,1)
  target.built=clamp(tonumber(fp.built) or 0,0,1)
  target.canopy=clamp(tonumber(fp.canopyFraction) or 0,0,1)
  target.water=liquidWater
  target.ice=iceWater
  target.open=clamp(tonumber(fp.openFraction) or 1,0,1)
  target.windShadow=clamp(tonumber(fp.windShadow) or 0,0,1)
  target.fogAffinity=clamp(fogAffinity,0,1)
  local f=1-math.exp(-dt/5.0)
  for k,v in pairs(target) do state[k]=(tonumber(state[k]) or v)+(v-(tonumber(state[k]) or v))*f end
  state.dewPoint=dewPoint(state.temperature,state.humidity)
  state.locality=math.abs(n)+math.abs(n2)
  state.cellX,state.cellZ=cx,cz
end
function M.peek() return state end
function M.sample() local o={}; for k,v in pairs(state) do o[k]=v end; return o end
function M.describe() return string.format("micro T=%.1fC dew=%.1fC H=%.0f%% cloud=%.0f%% wind=%.0f%%",state.temperature,state.dewPoint,state.humidity*100,state.cloud*100,state.wind*100) end
return M
