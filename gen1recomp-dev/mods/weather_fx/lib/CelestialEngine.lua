-- CelestialEngine — one environmental-light authority shared by 2D and voxel.
--
-- CelestialSim answers astronomy. This module composes it with Weather FX's
-- live weather, building light pollution and cloud observations, then publishes
-- one immutable-ish frame snapshot for sky, shadows, atmosphere, water and
-- companion mods. No disk edits to voxel hosts are ever performed.

local V = ...
local Engine = {
  time=0, _cloudTransmission=nil, _cloudCoverage=nil, _cloudObservedAt=nil, _state=nil,
  -- Presentation-clock state. The authoritative TOD can arrive in coarse host
  -- ticks; sun/moon rendering uses this filtered clock so their world-space
  -- orbit advances continuously between those samples instead of jumping.
  _presentHour=nil, _clockRawHour=nil, _clockRawChangedAt=nil,
  _clockVelocity=0, _clockSourceKey=nil,
  _shadowKX=nil, _shadowKZ=nil, _shadowAlpha=0, _shadowKind=nil,
  _shadowTargetKX=nil, _shadowTargetKZ=nil,
}

local max,min,abs,exp,sqrt = math.max,math.min,math.abs,math.exp,math.sqrt
local function clamp01(x) if x<0 then return 0 elseif x>1 then return 1 end return x end
local function smooth01(x) x=clamp01(x); return x*x*(3-2*x) end
local function smoothRange(a,b,x)
  if b==a then return x>=b and 1 or 0 end
  return smooth01((x-a)/(b-a))
end
local function lerp(a,b,t) return a+(b-a)*t end
local function mix3(a,b,t) return {lerp(a[1],b[1],t),lerp(a[2],b[2],t),lerp(a[3],b[3],t)} end
local function root(name) local ok,m=pcall(V.require,name); if ok then return m end end
local function cfg()
  local C=root("Config"); local c=C and C.get and C.get() or nil
  return (c and c.celestial) or {}
end
local function enabled() return cfg().enabled ~= false end


local function hourDelta(target,current)
  return ((target-current+12)%24)-12
end

local function sourceKey()
  local TOD=root("TimeOfDay")
  local source=tostring(TOD and TOD.source or "unknown")
  local pin=TOD and TOD.pin
  local hostMode=TOD and TOD.hostMode
  local key=source.."|"..tostring(pin or "")
  if hostMode then key=key.."|host:"..tostring(hostMode) end
  return key,source,pin
end

local function nominalClockVelocity(source)
  -- Feed-forward for clocks whose rate Weather FX owns. Host voxel clocks are
  -- learned from successive samples below because their cadence is host-defined.
  if source=="cycle" then
    local C=root("Config"); local c=C and C.get and C.get() or {}
    local tc=c.time or {}
    local period=max(30,(tonumber(tc.cycleMinutes) or 24)*60)
    return 24/period
  elseif source=="system" then
    return 1/3600
  end
  return 0
end

-- Smooth, wrap-safe presentation time for celestial *motion only*.
-- TimeOfDay remains the authoritative gameplay/day-night clock. This layer
-- reconstructs continuous motion between coarse clock samples and eases small
-- corrections so a host tick can never visibly teleport the sun or moon.
-- Intentional clock-mode/pin changes and very large time jumps still snap.
function Engine.presentationHour(rawHour,dt)
  rawHour=(tonumber(rawHour) or 12)%24
  dt=max(0,min(tonumber(dt) or 0,0.25))
  local key,source,pin=sourceKey()
  local now=Engine.time
  local hardSource=(pin~=nil or source=="pinned" or source=="fixed" or source=="off")
  local smoothOn=cfg().motionSmoothing ~= false

  -- A zero-delta evaluation is an explicit state query/resync, not an animation
  -- frame. Follow the authoritative clock exactly so tests, debug probes and
  -- one-shot state() callers never receive a stale interpolated hour.
  if dt<=0 then
    Engine._presentHour=rawHour
    Engine._clockRawHour=rawHour
    Engine._clockRawChangedAt=now
    Engine._clockVelocity=nominalClockVelocity(source)
    Engine._clockSourceKey=key
    return rawHour
  end

  if Engine._presentHour==nil or Engine._clockSourceKey~=key or hardSource or not smoothOn then
    Engine._presentHour=rawHour
    Engine._clockRawHour=rawHour
    Engine._clockRawChangedAt=now
    Engine._clockVelocity=nominalClockVelocity(source)
    Engine._clockSourceKey=key
    return rawHour
  end

  local lastRaw=Engine._clockRawHour or rawHour
  local rawStep=hourDelta(rawHour,lastRaw)
  if abs(rawStep)>1e-7 then
    -- A multi-hour discontinuity is a save/time-mode/debug change, not motion.
    if abs(rawStep)>=2.0 then
      Engine._presentHour=rawHour
      Engine._clockVelocity=nominalClockVelocity(source)
    else
      local sampleDt=max(1/240,now-(Engine._clockRawChangedAt or now))
      local measured=max(-1.5,min(1.5,rawStep/sampleDt))
      local v=tonumber(Engine._clockVelocity) or 0
      -- First usable host sample locks onto its rate quickly; later samples are
      -- blended to reject quantization jitter without changing clock authority.
      if abs(v)<1e-7 then v=measured else v=lerp(v,measured,0.42) end
      Engine._clockVelocity=v
    end
    Engine._clockRawHour=rawHour
    Engine._clockRawChangedAt=now
  end

  local v=tonumber(Engine._clockVelocity) or 0
  local age=max(0,now-(Engine._clockRawChangedAt or now))
  -- Coast between ordinary host ticks. If the host truly stops advancing for
  -- more than 1.5 s, exponentially shed the learned velocity so we do not run
  -- away from the authoritative clock while paused/loading.
  if age>1.5 then
    v=v*exp(-3.5*dt)
    Engine._clockVelocity=v
  end

  local present=Engine._presentHour or rawHour
  local previous=present
  local feed=v*dt
  local predicted=(present+feed)%24
  local target=(rawHour+v*min(age,1.5))%24
  local error=hourDelta(target,predicted)
  local response=1-exp(-8.0*dt)
  local correction=error*response
  -- Authoritative clock corrections may SLOW the presentation clock but may
  -- never reverse it for one frame. Previously a slightly over-predicted host
  -- tick could produce a negative correction larger than the forward feed,
  -- making shadows visibly twitch backward immediately before their next
  -- forward step. Retain at least 2% of the feed-forward travel direction;
  -- large intentional time jumps are already handled above as hard resyncs.
  if feed>1e-10 and correction < -feed*0.98 then
    correction=-feed*0.98
  elseif feed< -1e-10 and correction > -feed*0.98 then
    correction=-feed*0.98
  end
  present=(predicted+correction)%24
  local frameDelta=hourDelta(present,previous)
  if feed>1e-10 and frameDelta<0 then
    present=(previous+feed*0.02)%24
  elseif feed< -1e-10 and frameDelta>0 then
    present=(previous+feed*0.02)%24
  end
  Engine._presentHour=present
  Engine._clockSourceKey=key
  return present
end

local COVER = {
  CLEAR=0.04,SUNNY=0.03,HARSH_SUN=0.01,HEATWAVE=0.06,
  RAIN_LIGHT=0.70,RAIN_HEAVY=0.92,HEAVY_RAIN=1.0,STORM=1.0,PSYSTORM=1.0,
  VERDANT_RAIN=0.76,GALE=0.88,DRAGONSTORM=0.96,
  SNOW_LIGHT=0.84,BLIZZARD=1.0,HAIL=0.95,SLEET=0.94,THUNDERSNOW=1.0,
  MIST=0.56,FOG=0.62,HAUNTED_MIST=0.70,SMOG=0.78,
  SANDSTORM=0.45,DUSTSTORM=0.52,ASHFALL=0.62,
  STRONG_WINDS=0.38,BRAWL_WIND=0.42,FLOCKSTORM=0.48,SWARM=0.42,PLAIN_FRONT=0.30,
}

local function weatherOptics(State)
  local id=tostring(State and State.id or "CLEAR"):upper()
  local function ch(k)
    if State and type(State.channel)=="function" then local ok,v=pcall(State.channel,k); if ok then return tonumber(v) or 0 end end
    return State and State.ch and tonumber(State.ch[k]) or 0
  end
  local cloud=COVER[id] or clamp01(max(ch("rain")*0.85,ch("snow")*0.28,ch("hail")*0.75,ch("fog")*0.55))
  if Engine._cloudCoverage ~= nil then cloud=clamp01(lerp(cloud,Engine._cloudCoverage,0.55)) end
  local aerosol=clamp01(ch("fog")*0.45 + ch("sand")*0.35 + ch("ash")*0.42 + ch("veil")*0.55)
  local smoke=(id=="ASHFALL" or id=="SMOG") and max(0.45,aerosol) or aerosol
  local localT=Engine._cloudTransmission
  local geometryCloudOcclusion=type(localT)=="number"
  local localSky=1.0
  local localDisc=1.0
  -- World illumination is REGIONAL. A single player-space hole in the cloud
  -- deck may reveal the solar disc / shafts, but it must never brighten every
  -- voxel on the rendered map. Spatial cloud shadows below are the authority
  -- for which terrain actually receives that direct light.
  local direct=(1-cloud*0.86)*(1-aerosol*0.62)
  if geometryCloudOcclusion then
    localT=clamp01(localT)
    -- 8.2.8: a live 3D cloud bank is real geometry drawn AFTER the celestial
    -- vault. Do not globally fade the sun/moon/stars just because a coarse
    -- player-space cloud ray is blocked; doing so erased the entire sky with
    -- FRONTS OFF / sealed decks. The bodies and deep sky stay astronomically
    -- alive and are revealed only through actual gaps in the later cloud mesh.
    -- Keep the local ray separately for god-rays/lens optics, which must still
    -- stop when the camera is looking through cloud mass.
    localSky=1.0
    localDisc=1.0
  end
  direct=clamp01(max(0.012,direct))
  local ambient=clamp01((1-cloud*0.42)*(1-aerosol*0.28))
  -- Broken clouds produce the strongest moving contrast. Solid overcast mostly
  -- lowers the whole ambient field rather than painting black islands.
  local patch=clamp01(cloud*(1-cloud*0.72)*1.65)
  local disc=clamp01((geometryCloudOcclusion and 1 or (1-cloud*0.94))*(1-aerosol*0.76)*localDisc)
  return {id=id,cloud=cloud,aerosol=aerosol,smoke=smoke,direct=direct,ambient=ambient,patch=patch,disc=disc,skyTransmission=localSky,localCloudTransmission=localT,geometryCloudOcclusion=geometryCloudOcclusion}
end

local function pollution()
  local BL=root("BuildingLight")
  local scale=1
  if BL and BL.starScale then local ok,v=pcall(BL.starScale); if ok and type(v)=="number" then scale=v end end
  scale=clamp01(scale)
  return 1-scale,scale
end

local function atmosphericColors(sim,optics)
  local alt=sim.sun.altitudeDeg
  local sun=sim.sun.color
  local haze=sim.sky.haze
  local fog=mix3(haze,{0.70,0.76,0.84},clamp01(optics.cloud*0.45))
  if optics.id=="SANDSTORM" then fog=mix3(fog,{0.88,0.59,0.26},0.72)
  elseif optics.id=="DUSTSTORM" then fog=mix3(fog,{0.66,0.49,0.29},0.72)
  elseif optics.id=="ASHFALL" then fog=mix3(fog,{0.34,0.31,0.29},0.72)
  elseif optics.id=="SMOG" then fog=mix3(fog,{0.31,0.36,0.30},0.62) end
  -- Forward scattering: low sun warms suspended media much more strongly.
  local scatter=clamp01((1-math.min(1,abs(alt)/32))*(optics.aerosol+optics.cloud*0.35))
  fog=mix3(fog,sun,scatter*0.42)
  -- Keep low-sun colour driving the cloud bank through civil twilight even
  -- after direct solar intensity becomes weaker than moonlight. This lets the
  -- clouds hold a warm underside/rim instead of snapping immediately to a
  -- neutral/moonlit tone at sunset.
  -- 8.1.15: optical-depth-shaped golden hour. Warm scattering starts before
  -- the centre clears the horizon, peaks while the sun is low, then decays
  -- over a broad altitude band. This avoids both a narrow orange switch and a
  -- flat all-day tint; cloud shaders consume this as a directional term.
  local twilightIn=smoothRange(-12,-1.5,alt)
  local highSunOut=1-smoothRange(6,28,alt)
  local sunsetWarmth=clamp01(twilightIn*highSunOut)
  if sunsetWarmth>0 and optics.cloud>0 then
    fog=mix3(fog,sun,clamp01(sunsetWarmth*optics.cloud*0.18))
  end
  local ray=(alt>-10) and sun or (sim.sun.intensity>sim.moon.intensity and sun or sim.moon.color)
  return fog,ray,scatter,sunsetWarmth
end

local function hostTintFor(s)
  local sun=s.sunLight or 0; local moon=s.moonLight or 0; local amb=s.ambient or 0
  local energy=clamp01(amb + sun*0.72 + moon*0.58)
  local base=mix3({0.34,0.40,0.62},{1,1,1},energy)
  local lightColor=sun>=moon and s.sim.sun.color or s.sim.moon.color
  base=mix3(base,lightColor,clamp01((sun+moon)*0.25))

  -- Golden-hour light belongs on the WORLD, not only in the sky bands. The old
  -- host tint weighted colour almost entirely by direct solar intensity, which
  -- is weakest exactly while the sun is rising/setting; the sky could turn
  -- orange while terrain, buildings and actors stayed neutral. Reuse the same
  -- continuous low-sun authority that warms clouds, but strengthen it into a
  -- broad directional colour grade on the voxel host's existing daylight tint.
  -- It is symmetric at sunrise/sunset because sunsetWarmth is altitude-based.
  local golden=clamp01((tonumber(s.sunsetWarmth) or 0)*1.90)
  if golden>0.001 then
    local sunColor=(s.sim and s.sim.sun and s.sim.sun.color) or {1,.72,.42}
    local warmTarget=mix3({1.0,.94,.84},sunColor,.72)
    local direct=(s.optics and tonumber(s.optics.direct)) or 1
    local amount=golden*(.34+.24*clamp01(direct))
    base=mix3(base,warmTarget,clamp01(amount))
  end
  s.worldGoldenHour=golden

  -- Keep outdoor navigation readable while still allowing genuinely dark nights.
  local floor=0.27
  return {max(floor,base[1]),max(floor,base[2]),max(floor,base[3])}
end

local function shadowTarget(s)
  local d=s and s.mainLight
  if not d then return 0,0,0,nil end
  local y=max(0.08,tonumber(d.dy) or 0.08)
  local kx=-(tonumber(d.dx) or 0)/y
  local kz=-(tonumber(d.dz) or 0)/y
  if kx>3 then kx=3 elseif kx< -3 then kx=-3 end
  if kz>3 then kz=3 elseif kz< -3 then kz=-3 end
  local alt=tonumber(d.altitudeDeg)
  if not alt then alt=math.deg(math.asin(max(-1,min(1,tonumber(d.dy) or 0)))) end
  -- Direct shadows fade completely at the horizon. This creates a genuinely
  -- shadowless handoff between sunset/moonrise and moonset/sunrise, so the
  -- paired bodies can swap sides without a visible east/west shadow snap.
  local elev=smoothRange(1.0,12.0,alt)
  local alpha=clamp01((0.10+(tonumber(s.directLight) or 0)*0.34)*elev)
  if (tonumber(s.directLight) or 0)<0.01 then alpha=0 end
  return kx,kz,alpha,d.kind or "light"
end

local function updateShadowRig(s,dt)
  local tx,tz,ta,kind=shadowTarget(s)
  dt=max(0,min(tonumber(dt) or 0,0.25))
  if dt<=0 or Engine._shadowKX==nil then
    Engine._shadowKX,Engine._shadowKZ,Engine._shadowAlpha,Engine._shadowKind=tx,tz,ta,kind
    Engine._shadowTargetKX,Engine._shadowTargetKZ=tx,tz
    return
  end
  -- Never rotate a still-visible shadow through 180 degrees when direct-light
  -- authority changes from sun to moon or back. Switch direction while the
  -- shadow is invisible, then fade the new body in from zero.
  if Engine._shadowKind~=kind then
    Engine._shadowKX,Engine._shadowKZ=tx,tz
    Engine._shadowAlpha=0
    Engine._shadowKind=kind
    Engine._shadowTargetKX,Engine._shadowTargetKZ=tx,tz
    return
  end
  -- High-response critically smooth handoff: values advance every rendered
  -- frame but reject tiny upstream timing noise. At ordinary 60/120 Hz this
  -- is sub-pixel on even the tallest supported voxel casters.
  local k=1-exp(-24.0*dt)
  local ka=1-exp(-18.0*dt)
  local oldX,oldZ=Engine._shadowKX,Engine._shadowKZ
  local nextX,nextZ=lerp(oldX,tx,k),lerp(oldZ,tz,k)
  -- Vertical-orbit shadows have a known one-way shear progression during each
  -- visible half-cycle. Enforce that invariant at the lighting handoff too:
  -- even if an upstream host sample jitters by a few ulps, the shadow rig may
  -- slow or hold for a frame but it may never reverse direction. The source
  -- switch is handled above while alpha is zero, so no 180-degree clamp is
  -- needed here.
  if cfg().verticalOrbit ~= false then
    local ptx,ptz=Engine._shadowTargetKX,Engine._shadowTargetKZ
    if ptx~=nil then
      local d=tx-ptx
      if d>1e-10 and nextX<oldX then nextX=oldX
      elseif d< -1e-10 and nextX>oldX then nextX=oldX end
    end
    if ptz~=nil then
      local d=tz-ptz
      if d>1e-10 and nextZ<oldZ then nextZ=oldZ
      elseif d< -1e-10 and nextZ>oldZ then nextZ=oldZ end
    end
  end
  Engine._shadowKX,Engine._shadowKZ=nextX,nextZ
  Engine._shadowAlpha=lerp(tonumber(Engine._shadowAlpha) or 0,ta,ka)
  Engine._shadowKind=kind
  Engine._shadowTargetKX,Engine._shadowTargetKZ=tx,tz
end

function Engine.observeCloudField(transmission,coverage)
  if type(transmission)=="number" then Engine._cloudTransmission=clamp01(transmission) end
  if type(coverage)=="number" then Engine._cloudCoverage=clamp01(coverage) end
  if Engine._cloudTransmission~=nil or Engine._cloudCoverage~=nil then
    Engine._cloudObservedAt=Engine.time
  end
end

local function expireCloudObservation()
  local seen=Engine._cloudObservedAt
  if seen~=nil and Engine.time-seen>0.50 then
    Engine._cloudTransmission=nil; Engine._cloudCoverage=nil; Engine._cloudObservedAt=nil
  end
end

function Engine.update(dt,State)
  dt=tonumber(dt) or 0
  if dt>0 then Engine.time=Engine.time+math.min(dt,1.0) end
  expireCloudObservation()
  local Sim=root("CelestialSim"); if not (enabled() and Sim and Sim.sample) then Engine._state=nil; return nil end
  local rawHour=Sim.hour and Sim.hour() or nil
  local presentHour=Engine.presentationHour(rawHour,dt)
  local sim=Sim.sample(presentHour)
  local weatherId=tostring(State and State.id or "CLEAR"):upper()
  if Engine._lastWeatherId and Engine._lastWeatherId~=weatherId then
    Engine._cloudTransmission=nil; Engine._cloudCoverage=nil; Engine._cloudObservedAt=nil
  end
  Engine._lastWeatherId=weatherId
  local optics=weatherOptics(State)
  local geometryCloudOcclusion=optics.geometryCloudOcclusion==true
  local poll,starScale=pollution()
  local solarE=((sim.sun and sim.sun.above) and sim.eclipse and sim.eclipse.solarObscuration) or 0
  local sunLight=sim.sun.intensity*optics.direct
  local moonLight=sim.moon.intensity*optics.direct
  local ambient=max(0.045,sim.daylight*0.48 + (1-sim.daylight)*(0.075+moonLight*0.48))
  ambient=ambient*optics.ambient
  -- Town/building light pollution is not only "fewer stars". At night it
  -- also raises the local ambient floor slightly, which is what makes the sky
  -- above civilization look washed-out while the wild remains genuinely dark.
  ambient=clamp01(ambient + poll*(1-sim.daylight)*0.075)
  local fogColor,rayColor,scatter,sunsetWarmth=atmosphericColors(sim,optics)
  -- 8.1.15 solar optics are independent from main shadow ownership. Around
  -- dawn/dusk the moon can still own the shadow map while the first solar limb
  -- is already visible; using mainLight for god rays made them switch on late
  -- and could illuminate clouds from the wrong side. Start at the first visible
  -- limb and ramp continuously to full solar shafts by the low-morning sky.
  local solarDisc=clamp01(tonumber(sim.sun.horizonFraction) or 0)
  local solarAlt=tonumber(sim.sun.altitudeDeg) or -90
  local solarRise=smoothRange(-3.24,14.0,solarAlt)
  local solarRayRamp=solarDisc>0 and clamp01(0.18*sqrt(solarDisc)+0.82*solarRise) or 0
  -- The first exposed limb is already bright enough to create extremely faint
  -- shafts even though the centre-altitude daylight curve is still near zero.
  -- Keep a small physical energy floor only while the disc is actually visible;
  -- the limb ramp still guarantees exact zero below the horizon.
  local solarEnergy=0.12+0.88*clamp01(tonumber(sim.sun.intensity) or 0)
  local solarRayStrength=clamp01(solarRayRamp*solarEnergy*optics.direct)
  local main=sim.sun
  if moonLight>sunLight and sim.moon.above then main=sim.moon end
  local s={
    sim=sim, hour=sim.hour, rawHour=rawHour, dayIndex=sim.dayIndex, twilight=sim.twilight,
    sunrise=sim.sunrise,sunset=sim.sunset,dayLength=sim.dayLength,
    optics=optics,lightPollution=poll,starScale=starScale,
    sunLight=sunLight,moonLight=moonLight,ambient=ambient,
    directLight=max(sunLight,moonLight),mainLight=main,
    fogColor=fogColor,rayColor=rayColor,forwardScatter=scatter,
    sunsetWarmth=sunsetWarmth, solarDiscVisibility=solarDisc,
    solarRayRamp=solarRayRamp, solarRayStrength=solarRayStrength,
    cloudSunsetStrength=clamp01((sunsetWarmth or 0)*(0.30+optics.cloud*0.85)),
    cloudShadowStrength=optics.patch*sunLight,
    -- Time-of-day visibility is continuous: zero in daylight, faint after
    -- sunset/before sunrise, and full at deep astronomical night. Building
    -- proximity remains a separate multiplier in NightSky so distance and time
    -- compose instead of overriding or double-applying each other.
    -- In 3D, cloud geometry is the per-pixel occluder. Preserve the complete
    -- astronomical vault behind it so stars/constellations remain visible in
    -- real cloud cracks instead of the whole night sky being globally muted.
    starVisibility=clamp01((sim.starVisibility or 0)*(geometryCloudOcclusion and 1 or (1-optics.cloud*0.92))*(1-optics.aerosol*0.48)*(optics.skyTransmission or 1)),
    milkyWayVisibility=clamp01((sim.starVisibility or 0)^1.65*(1-poll)^2.2*(geometryCloudOcclusion and 1 or (1-optics.cloud)^1.8)*(1-optics.aerosol)^1.2*(optics.skyTransmission or 1)^1.2),
    geometryCloudOcclusion=geometryCloudOcclusion,
  }
  -- Weather visibility of the actual discs. Clouds can hide the body while
  -- leaving diffuse daylight/moonlight in the atmosphere.
  s.sun={}; for k,v in pairs(sim.sun) do s.sun[k]=v end
  s.moon={}; for k,v in pairs(sim.moon) do s.moon[k]=v end
  s.sun.discTransmission=optics.disc
  s.moon.discTransmission=optics.disc
  -- Separate coarse cloud-ray transmission from body existence. 3D cloud
  -- geometry owns visible occlusion; this scalar is retained only for direct
  -- camera optics such as glare/god rays.
  s.sun.cloudLineTransmission=optics.localCloudTransmission
  s.moon.cloudLineTransmission=optics.localCloudTransmission
  s.sun.geometryCloudOcclusion=optics.geometryCloudOcclusion==true
  s.moon.geometryCloudOcclusion=optics.geometryCloudOcclusion==true
  -- The local sunset halo is derived from limb contact in CelestialSim, then
  -- attenuated by the same optical path as the real disc. sqrt keeps a soft
  -- diffuse glow through thin haze while still reaching exact zero when the
  -- sun is fully hidden.
  s.sun.haloStrength=clamp01((tonumber(s.sun.haloStrength) or 0)*sqrt(clamp01(optics.disc)))
  s.sun.alpha=s.sun.alpha*optics.disc
  s.moon.alpha=s.moon.alpha*optics.disc
  -- Suspended media changes the apparent celestial disc itself, not only the
  -- whole frame. Dust/ash redden the low sun; fog/smog soften both bodies.
  if optics.id=="SANDSTORM" or optics.id=="DUSTSTORM" then
    s.sun.color=mix3(s.sun.color,{1.0,0.34,0.08},0.62)
  elseif optics.id=="ASHFALL" or optics.id=="SMOG" then
    s.sun.color=mix3(s.sun.color,{0.78,0.18,0.08},0.58)
  elseif optics.id=="FOG" or optics.id=="MIST" or optics.id=="HAUNTED_MIST" then
    s.sun.color=mix3(s.sun.color,{0.92,0.88,0.78},0.45)
    s.moon.color=mix3(s.moon.color,{0.78,0.82,0.90},0.38)
  end
  s.sun.solarEclipse=sim.eclipse and sim.eclipse.solarObscuration or 0
  s.moon.solarEclipse=sim.eclipse and sim.eclipse.solarObscuration or 0
  s.moon.lunarEclipse=sim.eclipse and sim.eclipse.lunarDarkening or 0
  if sim.eclipse and sim.eclipse.solarObscuration>0.05 then
    -- Keep the eclipsed solar disc visible enough for the moon silhouette/corona.
    s.sun.alpha=max(s.sun.alpha,0.35*sim.sun.alpha)
    s.moon.alpha=max(s.moon.alpha,0.82*sim.eclipse.solar)
  end
  s.hostTint=hostTintFor(s)
  updateShadowRig(s,dt)
  Engine._state=s
  Engine.publish(State)
  return s
end

function Engine.state()
  -- Draw paths are allowed to query state before the staged updater gets its
  -- next tick (notably immediately after an options/menu time pin). Never hand
  -- them a cached DAY snapshot when TimeOfDay has already jumped to NIGHT.
  local Sim=root("CelestialSim")
  local raw=Sim and Sim.hour and Sim.hour() or nil
  local key=sourceKey()
  if Engine._state and Engine._state.rawHour~=nil and type(raw)=="number" then
    local old=tonumber(Engine._state.rawHour)
    -- A host mode/source flip (DAY -> NIGHT, fixed -> cycle, etc.) is an
    -- immediate presentation command. Ordinary sub-hour clock motion belongs
    -- to presentationHour() and must not turn state() into an eager updater.
    -- Multi-hour jumps are treated as real save/debug/host-time changes. The
    -- rawHour marker is intentionally required so test/debug callers that
    -- inject a temporary celestial state are not overwritten behind their back.
    if Engine._clockSourceKey~=key or (old and abs(hourDelta(raw,old))>=2.0) then
      return Engine.update(0,root("WeatherState"))
    end
  end
  if Engine._state then return Engine._state end
  return Engine.update(0,root("WeatherState"))
end

function Engine.skyBands(count)
  local s=Engine.state(); if not s then return nil end
  count=math.max(3,math.floor(tonumber(count) or 6))
  local out={}
  local top,mid,haze=s.sim.sky.top,s.sim.sky.mid,s.sim.sky.haze
  for i=1,count do
    local t=(i-1)/math.max(1,count-1)
    local c=t<0.55 and mix3(top,mid,t/0.55) or mix3(mid,haze,(t-0.55)/0.45)
    -- Cloud/aerosol extinction moves the visible sky toward the same atmospheric fog.
    c=mix3(c,s.fogColor,clamp01(s.optics.cloud*0.34+s.optics.aerosol*0.28))
    -- Light pollution belongs near the horizon, not over the whole vault.
    -- `t` grows toward the lowest sky band, so towns get a warm horizon dome
    -- while zenith stars remain much less affected.
    if s.lightPollution>0.01 and s.sim.sun.altitudeDeg < -4 then
      local low=clamp01((t-0.42)/0.58)
      local glow=s.lightPollution*low*0.34
      c=mix3(c,{0.30,0.22,0.18},glow)
    end
    local e=s.sim.eclipse and s.sim.eclipse.solarObscuration or 0
    if e>0 then c=mix3(c,{0.035,0.045,0.075},e*0.78) end
    out[i]=c
  end
  return out
end

function Engine.applySkyBands(bands)
  if type(bands)~="table" or #bands<1 then return bands end
  local ours=Engine.skyBands(#bands); if not ours then return bands end
  local out={}
  for i=1,#bands do
    local b=bands[i] or {0,0,0}; local o=ours[i]
    -- Celestial atmosphere is authority, but preserve a little host palette identity.
    out[i]={lerp(b[1] or 0,o[1],0.88),lerp(b[2] or 0,o[2],0.88),lerp(b[3] or 0,o[3],0.88)}
  end
  return out
end

function Engine.hostTint() local s=Engine.state(); return s and s.hostTint or nil end
function Engine.shadowRig()
  local s=Engine.state(); if not s or not s.mainLight then return nil end
  if Engine._shadowKX==nil then updateShadowRig(s,0) end
  return Engine._shadowKX or 0,Engine._shadowKZ or 0,clamp01(Engine._shadowAlpha or 0),s.hostTint
end

function Engine.particleTint(kind)
  local s=Engine.state(); if not s then return 1,1,1,1 end
  local c=s.mainLight and s.mainLight.color or {1,1,1}
  local amount=clamp01(s.directLight*0.32+s.forwardScatter*0.18)
  if kind=="snow" or kind=="hail" then amount=amount*0.55 end
  return lerp(1,c[1],amount),lerp(1,c[2],amount),lerp(1,c[3],amount),1
end

function Engine.publish(State)
  local s=Engine._state; if not s then return end
  local rootg=rawget(_G,"__weather_fx")
  if type(rootg)~="table" then rootg={}; pcall(rawset,_G,"__weather_fx",rootg) end
  rootg.current=tostring(State and State.id or s.optics.id)
  rootg.weather=rootg.current
  local c=rootg.celestial
  if type(c)~="table" then c={}; rootg.celestial=c end
  c.hour=s.hour; c.dayFraction=(s.hour%24)/24; c.dayIndex=s.dayIndex
  c.sunrise=s.sunrise; c.sunset=s.sunset; c.dayLength=s.dayLength; c.twilight=s.twilight
  c.sunDir={s.sun.dx,s.sun.dy,s.sun.dz}; c.moonDir={s.moon.dx,s.moon.dy,s.moon.dz}
  c.sunAltitude=s.sun.altitudeDeg; c.moonAltitude=s.moon.altitudeDeg
  c.sunLight=s.sunLight; c.moonLight=s.moonLight; c.ambient=s.ambient
  c.solarDiscVisibility=s.solarDiscVisibility; c.solarRayRamp=s.solarRayRamp; c.solarRayStrength=s.solarRayStrength
  c.moonPhase=s.moon.phase; c.moonIllumination=s.moon.illumination; c.moonPhaseName=s.moon.phaseName
  c.cloudTransmission=s.optics.direct; c.cloudCover=s.optics.cloud
  c.solarEclipse=s.sim.eclipse.solarObscuration; c.lunarEclipse=s.sim.eclipse.lunarDarkening
end

function Engine.describe()
  local s=Engine.state(); if not s then return "OFF" end
  return string.format("%s sun%.0f° moon:%s %.0f%% %.0f° light=%.2f cloud=%.2f eclipse=%.2f/%.2f",
    s.twilight,s.sun.altitudeDeg,s.moon.phaseName,s.moon.illumination*100,s.moon.altitudeDeg,s.directLight,s.optics.cloud,
    s.sim.eclipse.solarObscuration,s.sim.eclipse.lunarDarkening)
end

return Engine
