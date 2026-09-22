local V = ...
local mod=V.mod
local Types=V.require("Types")
local C={}
local cells={}
local nextId=1
local elapsed=0
local lastEpoch=0
local lastSpawn=0
local current={strength=1,precip=1,cloud=1,core=0,edge=0,weather=nil,stage="none",distance=1e9,cellId=nil}
local scratch={}
local MAX_CELLS=6
local AMBIENT_MIN_SPAWN=26
local FRONT_MIN_SPAWN=38
local enabled=true

local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function rand()
  if love and love.math and love.math.random then return love.math.random() end
  return math.random()
end
local _Settings
local function lightningFrequencyScale()
  if not _Settings then
    local ok,m=pcall(V.require,"Settings")
    if ok and m then _Settings=m end
  end
  if _Settings and _Settings.lightningFrequencyScale then
    local ok,v=pcall(_Settings.lightningFrequencyScale)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return 1
end
local function spatial(id)
  local d=Types.get(id); local ch=d and d.ch or {}
  return (tonumber(ch.rain) or 0)>0 or (tonumber(ch.snow) or 0)>0 or (tonumber(ch.hail) or 0)>0
    or (tonumber(ch.sand) or 0)>0 or (tonumber(ch.ash) or 0)>0 or (tonumber(ch.debris) or 0)>0
    or (tonumber(ch.strike) or 0)>0 or ((tonumber(ch.gust) or 0)>.55 and not d.sunny)
end
local function refreshLife(c)
  local age,life=tonumber(c.age) or 0,math.max(1,tonumber(c.life) or 1)
  if c._lifeAge==age and c._lifeLife==life then return c._lifeAmp,c._lifeRadius,c._lifeStage,c._lifeU end
  local u=clamp(age/life,0,1)
  local amp,stage,radius
  if u<.12 then local q=smooth(u/.12);amp=.08+.42*q;radius=.35+.30*q;stage="formation"
  elseif u<.30 then local q=smooth((u-.12)/.18);amp=.50+.50*q;radius=.65+.35*q;stage="growth"
  elseif u<.72 then amp=1;radius=1;stage="mature"
  elseif u<.90 then local q=smooth((u-.72)/.18);amp=1-.42*q;radius=1-.12*q;stage="weakening"
  else local q=smooth((u-.90)/.10);amp=.58*(1-q);radius=.88-.28*q;stage="dissipation" end
  c._lifeAge,c._lifeLife,c._lifeAmp,c._lifeRadius,c._lifeStage,c._lifeU=age,life,amp,radius,stage,u
  return amp,radius,stage,u
end
local function lifeProfile(c) return refreshLife(c) end
local function footprintMetric(c,x,z)
  local dx,dz=(tonumber(x) or 0)-(tonumber(c.x) or 0),(tonumber(z) or 0)-(tonumber(c.z) or 0)
  local vx,vz=tonumber(c.vx) or 1,tonumber(c.vz) or 0
  local vl=math.sqrt(vx*vx+vz*vz);if vl>.001 then vx,vz=vx/vl,vz/vl else vx,vz=1,0 end
  local along=dx*vx+dz*vz;local cross=-dx*vz+dz*vx
  local rx=math.max(1,tonumber(c.rx) or 1);local rz=math.max(1,tonumber(c.rz) or 1)
  return math.sqrt((along/rx)^2+(cross/rz)^2),math.sqrt(dx*dx+dz*dz)
end
local function dims()
  -- A storm FRONT is normally much wider across its travel direction than it
  -- is deep along it. Older builds overwhelmingly generated 1-3-map blobs.
  -- Keep genuine local cells, but make regional/broad/synoptic fronts common
  -- enough to span many connected maps on the flat world.
  local r=rand()
  if r<.18 then
    return 280+rand()*240,420+rand()*340,"cell",1.12,.86
  elseif r<.55 then
    return 500+rand()*360,820+rand()*620,"regional",1.00,1.00
  elseif r<.84 then
    return 760+rand()*520,1450+rand()*1050,"broad",.84,1.24
  else
    return 1050+rand()*760,2500+rand()*1900,"synoptic",.68,1.52
  end
end
local function wind()
  local ok,W=pcall(V.require,"WindEngine")
  if ok and W then
    local s=W.peek and W.peek() or (W.state and W.state())
    if type(s)=="table" then
      local x,z=tonumber(s.x) or 0,tonumber(s.z) or 0;local l=math.sqrt(x*x+z*z)
      if l>.001 then return x/l,z/l,tonumber(s.strength) or .3 end
    end
    if W.direction then local x,z=W.direction();local l=math.sqrt((x or 0)^2+(z or 0)^2);if l>.001 then return x/l,z/l,.3 end end
  end
  return .82,.28,.3
end
local function electricStrength(weather)
  local d=Types.get(weather);local ch=d and d.ch or {}
  return clamp((tonumber(ch.strike) or 0)/22,0,1)
end
local function spawn(weather,x,z,lifetimeScale,source)
  if not spatial(weather) or #cells>=MAX_CELLS then return nil end
  local rx,rz,sizeClass,speedMul,lifeMul=dims();local wx,wz,ws=wind()
  -- Spawn by LEADING-EDGE distance, not by the widest cross-front radius. A
  -- 4,000-unit-wide synoptic front therefore starts with its wall a believable
  -- distance over the horizon instead of putting its centre half a continent
  -- away. Cross-track offset remains inside the corridor so an incoming front
  -- is physically capable of intersecting the player's route.
  local edgeGap=420+rand()*720
  local approach=rx*(1.04+rand()*.18)+edgeGap
  local cross=(rand()-.5)*rz*.92
  local px,pz=-wz,wx
  -- Front translation used to run at roughly 5.5-18.5 units/s. Large systems
  -- now move slower than compact cells and all classes remain deliberately
  -- interceptable by normal player traversal.
  local speedBase=.90+ws*2.20+rand()*.80
  local speed=clamp(speedBase*(speedMul or 1),.75,4.10)
  local scale=tonumber(lifetimeScale) or 1
  local randomLife=(280+rand()*420)*scale*(lifeMul or 1)
  local edgeTravel=edgeGap/math.max(.5,speed)
  -- Guarantee the leading edge arrives during growth/maturity rather than
  -- during the weakening tail.
  local life=math.max(90,randomLife,edgeTravel/.56)
  local maxLife=life+math.max(360,720*scale*(lifeMul or 1))
  local sx,sz=x-wx*approach+px*cross,z-wz*approach+pz*cross
  -- A front samples the player's position ONCE, at creation. From that moment
  -- it is an independent world entity with a locked trajectory. The initial
  -- heading points from the spawned front centre toward that one-time target;
  -- later player movement and camera rotation can never retarget it.
  local hvx,hvz=x-sx,z-sz;local hl=math.sqrt(hvx*hvx+hvz*hvz)
  if hl>.001 then hvx,hvz=hvx/hl,hvz/hl else hvx,hvz=wx,wz end
  local c={id=nextId,weather=weather,x=sx,z=sz,
    rx=rx,rz=rz,age=0,life=life,maxLife=maxLife,vx=hvx,vz=hvz,speed=speed,
    speedMul=speedMul or 1,sizeClass=sizeClass or "regional",phase=rand()*6.28318,
    targetX=x,targetZ=z,reachedTarget=false,trajectoryLocked=true,source=source or "ambient",
    charge=0,flash=0,strikeSerial=0,strikeX=nil,strikeZ=nil,nextStrike=4+rand()*16}
  refreshLife(c)
  nextId=nextId+1;cells[#cells+1]=c;lastSpawn=elapsed;return c
end
local function influence(c,x,z,out)
  local amp,rs,stage,u=lifeProfile(c)
  local dx,dz=(x-c.x),(z-c.z)
  -- Rotate the footprint with travel direction. A few cheap analytic waves
  -- perturb the ellipse so a cell never reads as a perfect moving circle,
  -- while remaining deterministic and allocation-free at every sample.
  local along=dx*c.vx+dz*c.vz;local cross=-dx*c.vz+dz*c.vx
  local nx=along/(c.rx*rs);local nz=cross/(c.rz*rs)
  local phase=tonumber(c.phase) or ((tonumber(c.id) or 1)*1.731)
  local warp=1 + .075*math.sin(nx*3.1+phase) + .055*math.sin(nz*4.3-phase*.7)
                 + .035*math.sin((nx+nz)*6.2+phase*.3)
  local d=math.sqrt(nx*nx+nz*nz)/clamp(warp,.84,1.16)
  -- Pronounced but smooth edge: full-strength core, obvious fringe, then dry.
  -- The exponent tightens the precipitation wall without creating a hard seam.
  local edge=1-smooth((d-.36)/.64)
  local precip=amp*clamp(edge^1.55,0,1)
  -- Cloud/anvil precursor extends farther than precipitation, especially in
  -- the downwind/forward direction. The player can therefore see the storm
  -- gathering one or more connected maps before the rain core arrives.
  local forward=clamp(nx,0,1)
  local back=clamp(-nx,0,1)
  local cloudReach=1.55 + .24*forward + .08*back
  local cloudEdge=1-smooth((d/cloudReach-.38)/.62)
  -- Cloud ownership grows and parts continuously with the front entity. The
  -- previous 20% minimum made a newly spawned system already own a visible
  -- cloud mass before it had physically developed, encouraging late sky-fill
  -- handoffs. Keep the broad precursor footprint, but grow its opacity from
  -- zero and peel it away continuously near end-of-life.
  local cloudBuild=smooth(clamp((u or 0)/.28,0,1))
  local cloudPart=1-smooth(clamp(((u or 0)-.72)/.28,0,1))
  local cloud=clamp(cloudBuild*cloudPart*cloudEdge,0,1)
  out=out or {};out.strength=precip;out.precip=precip;out.cloud=cloud;out.core=clamp(1-d/.40,0,1)*amp
  out.edge=clamp((edge-precip)*2.2,0,1);out.weather=c.weather;out.stage=stage;out.distance=d;out.cellId=c.id
  out.x,out.z,out.rx,out.rz=c.x,c.z,c.rx*rs,c.rz*rs
  return out
end

function C.update(dt,mapId,ambient,x,z,lifetimeScale)
  dt=clamp(tonumber(dt) or 0,0,.25);elapsed=elapsed+dt;x=tonumber(x) or 0;z=tonumber(z) or 0
  if not enabled then return C.sampleInto(x,z,current,ambient) end
  local ok,S=pcall(V.require,"WeatherWorldSpace");local ep=(ok and S and S.epoch and S.epoch()) or 0
  if ep~=lastEpoch then
    -- A map-space epoch change means the PLAYER crossed an unproved seam; it
    -- does not mean the weather entities ceased to exist. WeatherWorldSpace
    -- now preserves old origins and isolates the new root on a distant island,
    -- so keep every front alive and simply remember the observer epoch.
    lastEpoch=ep
  end
  for i=#cells,1,-1 do
    local c=cells[i];c.age=c.age+dt
    c.flash=math.max(0,(tonumber(c.flash) or 0)-dt*3.8)

    -- LOCKED TRAJECTORY. targetX/targetZ are the one-time spawn snapshot, not a
    -- live player destination. A player who turns around, changes maps or runs
    -- sideways can let the storm miss them; the storm never bends to chase.
    local tx,tz=tonumber(c.targetX) or c.x,tonumber(c.targetZ) or c.z
    local metric,td=footprintMetric(c,tx,tz)
    local _,lifeRadius=refreshLife(c)
    if not c.reachedTarget and metric<=lifeRadius*.98 then c.reachedTarget=true;c.contactAge=c.age end

    -- Reserve enough lifetime to cross the ORIGINAL interception point. This
    -- is evaluated against the fixed snapshot only; moving away cannot extend
    -- the life of a front or turn it into a homing system.
    if not c.reachedTarget and metric>lifeRadius and metric>.001 then
      local edgeDistance=td*math.max(0,1-lifeRadius/metric)
      local scale=tonumber(lifetimeScale) or 1
      local reserve=edgeDistance/math.max(.5,tonumber(c.speed) or 1)+math.max(120,190*scale)
      local wanted=c.age+reserve
      local cap=tonumber(c.maxLife) or (c.life+720*scale)
      if wanted>c.life then c.life=math.min(cap,wanted) end
    end

    -- Heading and translation speed are spawn-owned entity state. Wind affects
    -- the heading chosen when the front is born and the precipitation inside it,
    -- but does not continuously steer the whole system afterward.
    local l=math.sqrt((tonumber(c.vx) or 0)^2+(tonumber(c.vz) or 0)^2)
    if l>.001 then c.vx,c.vz=c.vx/l,c.vz/l else c.vx,c.vz=1,0 end
    c.x=c.x+c.vx*c.speed*dt;c.z=c.z+c.vz*c.speed*dt
    -- Charge belongs to the cloud, not the player. Growing/mature electrical
    -- cells can therefore flash and strike while still several maps away.
    local amp,_,stage=refreshLife(c);local elec=electricStrength(c.weather)
    local stageCharge=(stage=="growth" and .72) or (stage=="mature" and 1) or (stage=="weakening" and .62) or .18
    c.charge=clamp(elec*amp*stageCharge,0,1)
    if c.charge>.06 then
      c.nextStrike=(tonumber(c.nextStrike) or 5)-dt*(.35+c.charge*1.25)*lightningFrequencyScale()
      if c.nextStrike<=0 then
        local along=(rand()-.5)*c.rx*.78;local cross=(rand()-.5)*c.rz*.72
        c.strikeX=c.x+c.vx*along-c.vz*cross;c.strikeZ=c.z+c.vz*along+c.vx*cross
        c.strikeSerial=(tonumber(c.strikeSerial) or 0)+1;c.flash=1
        c.nextStrike=5+rand()*16/(.45+c.charge)
      end
    end
    if c.age>=c.life then table.remove(cells,i) end
  end
  ambient=tostring(ambient or Types.DEFAULT)
  if spatial(ambient) then
    local nearby=false
    for i=1,#cells do local c=cells[i];if c.weather==ambient and ((c.x-x)^2+(c.z-z)^2)<(1800^2) then nearby=true;break end end
    if (not nearby or #cells<2) and elapsed-lastSpawn>AMBIENT_MIN_SPAWN then spawn(ambient,x,z,lifetimeScale,"local-front") end
    -- Mature severe synoptic spells can support a second embedded cell.
    local def=Types.get(ambient);local severe=(tonumber(def.ch and def.ch.strike) or 0)>0 or (tonumber(def.ch and def.ch.gust) or 0)>.8
    if severe and #cells<MAX_CELLS and elapsed-lastSpawn>70 and rand()<.035 then spawn(ambient,x,z,lifetimeScale,"embedded") end
  elseif #cells<MAX_CELLS and elapsed-lastSpawn>FRONT_MIN_SPAWN then
    -- A neighbouring coarse front can seed a real continuous-world cell before
    -- the player's own region forecast flips. This makes fronts visibly move in
    -- instead of rain suddenly beginning only after a region boundary/roll.
    local okF,F=pcall(V.require,"Fronts")
    local incoming=(okF and F and F.approachingWeather and F.approachingWeather(mapId)) or nil
    if incoming and spatial(incoming) then
      local nearby=false
      for i=1,#cells do local c=cells[i];if c.weather==incoming and ((c.x-x)^2+(c.z-z)^2)<(2400^2) then nearby=true;break end end
      if not nearby then spawn(incoming,x,z,lifetimeScale,"neighbor-front") end
    end
  end
  C.sampleInto(x,z,current,ambient)
  return current
end
function C.sampleInto(x,z,out,ambient)
  out=out or {};for k in pairs(out) do out[k]=nil end
  if not enabled then
    out.strength,out.precip,out.cloud,out.core,out.edge=0,0,0,0,0
    out.weather=nil;out.cloudWeather=nil;out.stage="disabled";out.distance=1e9;out.ambient=ambient
    return out
  end
  local bestP,bestC=0,0;local best=nil;local cloudWeather=nil
  local cloudStage,cloudDistance,cloudCellId,cloudX,cloudZ,cloudRx,cloudRz=nil,1e9,nil,nil,nil,nil,nil
  for i=1,#cells do
    local q=influence(cells[i],x,z,scratch)
    if q.cloud>bestC then
      bestC=q.cloud;cloudWeather=cells[i].weather;cloudStage=q.stage;cloudDistance=q.distance;cloudCellId=q.cellId
      cloudX,cloudZ,cloudRx,cloudRz=q.x,q.z,q.rx,q.rz
    end
    if q.precip>bestP then bestP=q.precip;best=cells[i]
      for k,v in pairs(q) do out[k]=v end
    end
  end
  if not best then out.strength,out.precip,out.core,out.edge=0,0,0,0;out.cloud=bestC;out.weather=nil;out.stage=cloudStage or "none";out.distance=cloudDistance end
  out.cloud=math.max(tonumber(out.cloud) or 0,bestC);out.cloudWeather=cloudWeather
  out.cloudStage,out.cloudDistance,out.cloudCellId=cloudStage,cloudDistance,cloudCellId
  out.cloudX,out.cloudZ,out.cloudRx,out.cloudRz=cloudX,cloudZ,cloudRx,cloudRz
  out.ambient=ambient
  return out
end
function C.sampleAt(x,z,ambient) return C.sampleInto(x,z,{},ambient) end
function C.peek() return current end
function C.isSpatialWeather(id) return spatial(id) end
function C.effectiveWeather(ambient,x,z)
  if not spatial(ambient) then return ambient,1,current end
  local q=C.sampleInto(x,z,scratch,ambient)
  if q.weather and q.precip>.012 then return q.weather,q.precip,q end
  return Types.DEFAULT,0,q
end
function C.rescaleRemaining(oldScale,newScale)
  oldScale=tonumber(oldScale) or 1;newScale=tonumber(newScale) or 1;if oldScale<=0 or newScale<=0 then return end
  local ratio=newScale/oldScale
  for i=1,#cells do local c=cells[i];local remain=math.max(0,c.life-c.age);c.life=c.age+remain*ratio;refreshLife(c) end
end
function C.cells() return cells end
function C.setEnabled(v)
  local on=(v~=false)
  if on==enabled then return false end
  enabled=on
  if not enabled then
    cells={};current={strength=0,precip=0,cloud=0,core=0,edge=0,weather=nil,stage="disabled",distance=1e9};lastSpawn=elapsed
  else
    -- Fresh spatial weather after re-enable; never resurrect a stale hidden cell.
    lastSpawn=elapsed-999
  end
  return true
end
function C.enabled() return enabled end
function C.stats() local p=C.peek();return {cells=#cells,strength=p.strength or 0,cloud=p.cloud or 0,stage=p.stage,weather=p.weather,enabled=enabled,memory="bounded"} end
function C.reset() cells={};nextId=1;elapsed=0;lastSpawn=0;current={strength=0,precip=0,cloud=0,core=0,edge=0,weather=nil,stage="none",distance=1e9};lastEpoch=0 end
function C.persist()
  pcall(function()
    local rows={}
    for i=1,#cells do local c=cells[i];rows[#rows+1]=table.concat({c.id,c.weather,c.x,c.z,c.rx,c.rz,c.age,c.life,c.vx,c.vz,c.speed,c.phase or 0,c.targetX or c.x,c.targetZ or c.z,c.reachedTarget and 1 or 0,c.charge or 0,c.flash or 0,c.strikeSerial or 0,c.strikeX or "",c.strikeZ or "",c.nextStrike or 6,c.source or "persisted",c.sizeClass or "regional",c.speedMul or 1,c.maxLife or c.life,c.contactAge or "",c.trajectoryLocked==false and 0 or 1},",") end
    mod.save:set("stormCellsV1",table.concat(rows,";"))
  end)
end
function C.restore()
  cells={}
  pcall(function()
    local s=mod.save:get("stormCellsV1",nil);if type(s)~="string" then return end
    for row in s:gmatch("[^;]+") do
      local a={};for v in row:gmatch("[^,]+") do a[#a+1]=v end
      if #a>=11 then local c={id=tonumber(a[1]) or nextId,weather=a[2],x=tonumber(a[3]) or 0,z=tonumber(a[4]) or 0,rx=tonumber(a[5]) or 700,rz=tonumber(a[6]) or 1100,age=tonumber(a[7]) or 0,life=tonumber(a[8]) or 420,vx=tonumber(a[9]) or 1,vz=tonumber(a[10]) or 0,speed=tonumber(a[11]) or 2.6,phase=tonumber(a[12]) or ((tonumber(a[1]) or nextId)*1.731),targetX=tonumber(a[13]) or tonumber(a[3]) or 0,targetZ=tonumber(a[14]) or tonumber(a[4]) or 0,reachedTarget=tonumber(a[15])==1,charge=tonumber(a[16]) or 0,flash=tonumber(a[17]) or 0,strikeSerial=tonumber(a[18]) or 0,strikeX=tonumber(a[19]),strikeZ=tonumber(a[20]),nextStrike=tonumber(a[21]) or 6,source=a[22] or "persisted",sizeClass=a[23] or "regional",speedMul=tonumber(a[24]) or 1,maxLife=tonumber(a[25]),contactAge=tonumber(a[26]),trajectoryLocked=true};c.maxLife=c.maxLife or (c.life+720);local vl=math.sqrt(c.vx*c.vx+c.vz*c.vz);if vl>.001 then c.vx,c.vz=c.vx/vl,c.vz/vl else c.vx,c.vz=1,0 end;refreshLife(c);cells[#cells+1]=c;nextId=math.max(nextId,(tonumber(a[1]) or 0)+1) end
    end
  end)
end
return C
