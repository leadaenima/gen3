local V = ...

-- Flat-world far-field weather observer.
--
-- With no mountains blocking the horizon, finite StormCells are valuable long
-- before they reach the player. This module converts the already-simulated
-- cells into a tiny bounded set of far-field descriptors for the 3D renderer.
-- It does not create weather, particles, or another spatial grid.
local D={}
local pool={}
local count=0
local MAX=4
local _StormCells=nil
local _Types=nil
local thunderQueue={}
local lastStrikeByCell={}
local remoteSerial=0
local motionTime=0
local RAIN_HEARING_RANGE=2400
local rainAudioState={present=false,gain=0,weather=nil,cellId=nil,edge=1e9,distance=1e9,inside=false,hearingRange=RAIN_HEARING_RANGE}

local function clamp(v,a,b) v=tonumber(v) or 0;if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function ellipseRadius(c,dx,dz,dist)
  local rx=math.max(1,tonumber(c.rx) or 1);local rz=math.max(1,tonumber(c.rz) or 1)
  if (tonumber(dist) or 0)<=.001 then return math.max(rx,rz) end
  local ux,uz=dx/dist,dz/dist
  local vx,vz=tonumber(c.vx) or 1,tonumber(c.vz) or 0
  local vl=math.sqrt(vx*vx+vz*vz);if vl>.001 then vx,vz=vx/vl,vz/vl else vx,vz=1,0 end
  local along=ux*vx+uz*vz;local cross=-ux*vz+uz*vx
  local denom=math.sqrt((along/rx)^2+(cross/rz)^2)
  if denom<=.000001 then return math.max(rx,rz) end
  return 1/denom
end
local function modules()
  if not _StormCells then local ok,m=pcall(V.require,"StormCells");if ok and m then _StormCells=m end end
  if not _Types then local ok,m=pcall(V.require,"Types");if ok and m then _Types=m end end
  return _StormCells,_Types
end
local function lifeProfile(c)
  local age,life=tonumber(c.age) or 0,math.max(1,tonumber(c.life) or 1)
  local u=clamp(age/life,0,1)
  local amp,rs,stage
  if u<.12 then local q=smooth(u/.12);amp=.08+.42*q;rs=.35+.30*q;stage="formation"
  elseif u<.30 then local q=smooth((u-.12)/.18);amp=.50+.50*q;rs=.65+.35*q;stage="growth"
  elseif u<.72 then amp=1;rs=1;stage="mature"
  elseif u<.90 then local q=smooth((u-.72)/.18);amp=1-.42*q;rs=1-.12*q;stage="weakening"
  else local q=smooth((u-.90)/.10);amp=.58*(1-q);rs=.88-.28*q;stage="dissipation" end
  -- StormCells already caches the same values; prefer those when present so
  -- renderer/audio geometry exactly matches the physical footprint.
  rs=tonumber(c._lifeRadius) or rs
  stage=tostring(c._lifeStage or stage)
  return amp,u,rs,stage
end
local function shaftStageFor(stage,u)
  -- Continuous precipitation maturity. The old stage constants jumped at
  -- formation -> growth and mature -> weakening boundaries, which could make a
  -- front's rain curtain and its audio envelope visibly/audibly step. Keep the
  -- named stage only for diagnostics; the actual strength is a C1-like smooth
  -- function of normalized life.
  u=clamp(u,0,1)
  if u<.12 then return .06*smooth(u/.12) end
  if u<.30 then return .06+.94*smooth((u-.12)/.18) end
  if u<.72 then return 1 end
  if u<.90 then return 1-.28*smooth((u-.72)/.18) end
  return .72*(1-smooth((u-.90)/.10))
end
local function kindFor(T,id)
  local d=T and T.get and T.get(id) or nil;local ch=d and d.ch or {}
  local rain=tonumber(ch.rain) or 0;local snow=tonumber(ch.snow) or 0;local hail=tonumber(ch.hail) or 0
  local strike=tonumber(ch.strike) or 0;local fog=tonumber(ch.fog) or 0;local dim=tonumber(ch.dim) or 0
  local gust=tonumber(ch.gust) or 0;local veil=tonumber(ch.veil) or 0
  -- Only hydrometeors form these visible far-field curtains. Sand/ash are
  -- handled by their own local visibility fields; painting them as blue rain
  -- shafts on a flat horizon would be visually wrong. Heavy wind-driven snow
  -- is its own BLIZZARD morphology rather than a recoloured rain shaft.
  local precip=math.max(rain,snow,hail)
  local snowDominant=(snow>rain and snow>=hail)
  local kind=snowDominant and ((gust>.72 or veil>.20 or snow>4.4) and "blizzard" or "snow")
    or ((rain>0 or hail>0) and "rain" or ((fog>0) and "fog" or "none"))
  return kind,clamp(precip,0,1),clamp(strike/22,0,1),clamp(dim,0,1),clamp(fog,0,1),clamp(gust,0,1),clamp(veil,0,1),math.max(0,rain)
end
local function swap(a,b)
  for k,v in pairs(a) do local t=b[k];b[k]=v;a[k]=t end
end

function D.update(dt,x,z)
  dt=clamp(tonumber(dt) or 0,0,.25)
  motionTime=motionTime+dt
  x,z=tonumber(x) or 0,tonumber(z) or 0
  local S,T=modules();local cells=S and S.cells and S.cells() or nil
  count=0
  -- Reuse one state record so Audio can sample physical front distance every
  -- frame without allocating. `present` stays true even at zero gain while a
  -- rain-bearing front remains in acoustic range; this prevents the local eased
  -- channel from reasserting a full-volume bed after the player has exited it.
  local ra=rainAudioState
  ra.present,ra.gain,ra.weather,ra.cellId=false,0,nil,nil
  ra.edge,ra.distance,ra.inside,ra.hearingRange=1e9,1e9,false,RAIN_HEARING_RANGE
  if type(cells)~="table" then return end
  local nearestRainEdge=1e9
  for i=1,#cells do
    local c=cells[i]
    local amp,u,lifeRadius,stage=lifeProfile(c)
    local vx,vz=tonumber(c.vx) or 1,tonumber(c.vz) or 0
    local vl=math.sqrt(vx*vx+vz*vz);if vl>.001 then vx,vz=vx/vl,vz/vl else vx,vz=1,0 end
    local rx=math.max(1,(tonumber(c.rx) or 1)*lifeRadius)
    local rz=math.max(1,(tonumber(c.rz) or 1)*lifeRadius)
    local dx,dz=(tonumber(c.x) or 0)-x,(tonumber(c.z) or 0)-z
    local dist=math.sqrt(dx*dx+dz*dz)
    -- Radius along the player ray, using the same rotated ellipse as StormCells.
    local radius
    if dist<=.001 then radius=math.max(rx,rz) else
      local ux,uz=dx/dist,dz/dist
      local along=ux*vx+uz*vz;local cross=-ux*vz+uz*vx
      local denom=math.sqrt((along/rx)^2+(cross/rz)^2)
      radius=(denom<=.000001) and math.max(rx,rz) or 1/denom
    end
    local edge=math.max(0,dist-radius);local inside=math.max(0,radius-dist)
    if amp>.035 and edge<3600 then
      local kind,precip,lightning,dim,fog,gust,veil,rainAmount=kindFor(T,c.weather)
      local cloudFade=1-clamp((edge-170)/3430,0,1)*.34
      -- Continuous cloud lifecycle. No stage boundary is allowed to jump the
      -- bank opacity: formation ramps from zero, growth completes the deck, and
      -- weakening/dissipation peel it away continuously.
      local build=smooth(clamp(u/.28,0,1))
      local part=1-smooth(clamp((u-.72)/.28,0,1))
      local cloud=clamp(build*part*cloudFade,0,1)
      local penetration=(radius>1) and clamp(inside/(radius*.62),0,1) or 0
      local nearFade=1-.48*smooth(penetration)
      local shaftHandoff=(edge>0) and 1 or (1-smooth(clamp(inside/math.max(1,radius*.62),0,1)))
      local shaftStage=shaftStageFor(stage,u)

      -- Physical rain acoustics. Outside the precipitation footprint the bed
      -- follows distance to the nearest edge; AT the edge it reaches full
      -- spatial gain and remains exactly full throughout the footprint. It can
      -- only begin receding after the player is physically outside again.
      if rainAmount>.02 then
        local spatial=(edge<=0) and 1 or smooth(1-clamp(edge/RAIN_HEARING_RANGE,0,1))
        local lifeAud=smooth(clamp((shaftStage-.04)/.46,0,1))
        local gain=spatial*lifeAud
        local better=(gain>ra.gain+.000001) or (math.abs(gain-ra.gain)<=.000001 and edge<nearestRainEdge)
        if better then
          ra.present,ra.gain,ra.weather,ra.cellId=true,gain,c.weather,c.id
          ra.edge,ra.distance,ra.inside=edge,dist,(edge<=0)
          nearestRainEdge=edge
        elseif not ra.present then
          -- Preserve identity even before the formation has become audible.
          ra.present,ra.gain,ra.weather,ra.cellId=true,gain,c.weather,c.id
          ra.edge,ra.distance,ra.inside=edge,dist,(edge<=0)
          nearestRainEdge=edge
        end
      end

      if (precip>.02 or fog>.04 or lightning>.02) then
        count=count+1;local q=pool[count] or {};pool[count]=q
        q.id,q.weather=c.id,c.weather;q.x,q.z=tonumber(c.x) or 0,tonumber(c.z) or 0
        q.rx,q.rz=rx,rz;q.distance,q.edge=dist,edge
        q.insideDepth,q.radius=inside,radius
        q.sizeClass=c.sizeClass or "regional"
        -- The rendered bank is the PHYSICAL LEADING EDGE of the entity, not
        -- the point on its ellipse nearest the current player. Player/camera
        -- movement therefore cannot drag the cloud wall around the storm.
        q.bankX=q.x+vx*rx
        q.bankZ=q.z+vz*rx
        q.vx,q.vz=vx,vz
        q.amp,q.lifeU=amp,u;q.kind=kind;q.stage=stage;q.gust=gust;q.veil=veil
        q.handoff=nearFade;q.cloud=cloud*nearFade
        local distanceFade=1-clamp((edge-190)/3410,0,1)*.46
        q.precip=precip*amp*distanceFade;q.lightning=lightning*amp*distanceFade
        q.charge=clamp(tonumber(c.charge) or q.lightning,0,1)
        q.flash=clamp(tonumber(c.flash) or 0,0,1)
        q.strikeSerial=tonumber(c.strikeSerial) or 0
        q.strikeX,q.strikeZ=tonumber(c.strikeX),tonumber(c.strikeZ)
        q.darkness=clamp((.20+dim*.65+q.precip*.28+cloud*.18)*amp*nearFade,0,1)
        q.shaft=(kind=="fog" and clamp(fog*amp*distanceFade*.42*shaftStage,0,1) or clamp(q.precip*shaftStage,0,1))*shaftHandoff
        q.audioGain=(rainAmount>.02) and ((edge<=0) and 1 or smooth(1-clamp(edge/RAIN_HEARING_RANGE,0,1))) or 0

        local seen=tonumber(lastStrikeByCell[c.id]) or 0
        if q.strikeSerial>seen and q.lightning>.02 then
          lastStrikeByCell[c.id]=q.strikeSerial;remoteSerial=remoteSerial+1
          thunderQueue[#thunderQueue+1]={serial=9000000+remoteSerial,cellId=c.id,wxId=c.weather,distance=dist,visualAt=nil,strikeRate=(q.lightning*22)}
          if #thunderQueue>12 then table.remove(thunderQueue,1) end
        end
      end
    end
  end
  -- Stable insertion sort by edge distance; MAX is tiny and avoids allocations.
  for i=2,count do local j=i;while j>1 and (pool[j].edge or 1e9)<(pool[j-1].edge or 1e9) do swap(pool[j],pool[j-1]);j=j-1 end end
  if count>MAX then count=MAX end
end

function D.items() return pool,count end
function D.sample()
  local out={}
  for i=1,count do local a=pool[i];local q={};for k,v in pairs(a) do q[k]=v end;out[i]=q end
  return out
end
function D.rainAudio() return rainAudioState end
function D.motionTime() return motionTime end
function D.takeThunderEvents()
  if #thunderQueue==0 then return nil end
  local out=thunderQueue;thunderQueue={}
  return out
end
function D.reset() count=0;thunderQueue={};lastStrikeByCell={};remoteSerial=0;motionTime=0;rainAudioState.present=false;rainAudioState.gain=0;rainAudioState.weather=nil;rainAudioState.cellId=nil;rainAudioState.edge=1e9;rainAudioState.distance=1e9;rainAudioState.inside=false end
function D.stats() return {count=count,max=MAX,memory="bounded",flatWorld=true,remoteThunder=#thunderQueue,motionTime=motionTime,rainAudioGain=rainAudioState.gain,rainAudioInside=rainAudioState.inside} end
return D
