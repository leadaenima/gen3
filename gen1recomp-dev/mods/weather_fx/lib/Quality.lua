-- Weather FX whole-mod quality authority.
--
-- 8.1.46 turns QUALITY from a mostly-particle selector into a coherent preset
-- that every expensive presentation family can query. Advanced PERFORMANCE
-- rows default to FOLLOW QUALITY and only override their named subsystem.
-- Manual tiers are literal player choices; AUTO alone adapts from sustained
-- frame/memory pressure and never changes game/weather time.

local V = ...
local Settings = V.require("Settings")
local Config = V.require("Config")
local Quality = {}

Quality.TIERS = {
  max = {
    rain=1100,snow=4800,grain=800,splash=180,fogLayers=4,bolt=true,
    worldPrecip=1.00,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,
    worldBlizzardCap=200000,worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,
    snowPackDrawCap=4800,footDrawCap=192,snowProbeCap=96,atmosphereScale=1.00,
    textureScale=1.00,reflection="full",effectDistanceScale=1.00,simulationInterval=1.00,
    cloudDetail=1.00,auroraSegments=72,auroraLayers=10,auroraSheets=4,
    starStep=1,maxPlanets=9,twinkle=true,sunLayers=4,meteors=true,
  },
  high = {
    rain=720,snow=3200,grain=520,splash=120,fogLayers=3,bolt=true,
    worldPrecip=0.88,worldRadiusCap=600,worldRainCap=7000,worldSnowCap=45000,
    worldBlizzardCap=70000,worldHailCap=22000,worldSandCap=18000,worldDebrisCap=2600,worldAshCap=7200,
    snowPackDrawCap=3400,footDrawCap=160,snowProbeCap=72,atmosphereScale=0.92,
    textureScale=0.75,reflection="full",effectDistanceScale=0.90,simulationInterval=1.10,
    cloudDetail=0.92,auroraSegments=64,auroraLayers=9,auroraSheets=4,
    starStep=1,maxPlanets=9,twinkle=true,sunLayers=4,meteors=true,
  },
  medium = {
    rain=380,snow=1640,grain=260,splash=55,fogLayers=2,bolt=true,
    worldPrecip=0.62,worldRadiusCap=420,worldRainCap=3500,worldSnowCap=15000,
    worldBlizzardCap=24000,worldHailCap=8000,worldSandCap=7000,worldDebrisCap=1400,worldAshCap=3600,
    snowPackDrawCap=2200,footDrawCap=112,snowProbeCap=48,atmosphereScale=0.76,
    textureScale=0.50,reflection="full",effectDistanceScale=0.72,simulationInterval=1.35,
    cloudDetail=0.76,auroraSegments=48,auroraLayers=7,auroraSheets=3,
    starStep=1,maxPlanets=9,twinkle=true,sunLayers=3,meteors=true,
  },
  low = {
    rain=160,snow=720,grain=110,splash=0,fogLayers=1,bolt=false,
    worldPrecip=0.42,worldRadiusCap=280,worldRainCap=1400,worldSnowCap=5000,
    worldBlizzardCap=8000,worldHailCap=2500,worldSandCap=2500,worldDebrisCap=650,worldAshCap=1500,
    snowPackDrawCap=1200,footDrawCap=72,snowProbeCap=28,atmosphereScale=0.58,
    textureScale=0.375,reflection="sky",effectDistanceScale=0.52,simulationInterval=1.75,
    cloudDetail=0.60,auroraSegments=36,auroraLayers=6,auroraSheets=3,
    starStep=1,maxPlanets=9,twinkle=true,sunLayers=2,meteors=true,
  },
  potato = {
    rain=90,snow=360,grain=60,splash=0,fogLayers=1,bolt=false,
    worldPrecip=0.28,worldRadiusCap=180,worldRainCap=550,worldSnowCap=1600,
    worldBlizzardCap=2400,worldHailCap=800,worldSandCap=900,worldDebrisCap=260,worldAshCap=600,
    snowPackDrawCap=600,footDrawCap=40,snowProbeCap=16,atmosphereScale=0.42,
    textureScale=0.25,reflection="simple",effectDistanceScale=0.36,simulationInterval=2.40,
    cloudDetail=0.45,auroraSegments=24,auroraLayers=4,auroraSheets=2,
    starStep=1,maxPlanets=9,twinkle=true,sunLayers=1,meteors=true,
  },
}

Quality.ORDER={"potato","low","medium","high"}
local RANK={potato=1,low=2,medium=3,high=4,max=5}
local auto={tier=nil,ema=1/60,hold=0}

local function clamp(v,a,b) v=tonumber(v) or a;if v<a then return a elseif v>b then return b end return v end
local function platformDefault()
  return Settings.get("autoPerformance")=="aggressive" and "medium" or "high"
end
local function menuAuto()
  local m=Settings.get("quality")
  if m and m~="auto" then return false end
  local c=Config.get().quality
  return not(c and c~="auto")
end
function Quality.autoEnabled()
  return menuAuto() and Settings.get("autoPerformance")~="off"
end
function Quality.targetFps()
  return clamp(tonumber(Settings.get("performanceTarget")) or 60,30,60)
end

function Quality.update(dt)
  if not auto.tier then auto.tier=platformDefault() end
  dt=tonumber(dt) or 0;if dt<=0 then return end;if dt>.25 then dt=.25 end
  auto.ema=auto.ema+(dt-auto.ema)*math.min(1,dt/1.5)
  if not Quality.autoEnabled() then auto.hold=0;return end
  local target=Quality.targetFps()
  local mode=Settings.get("autoPerformance")
  local slowFps=target*(mode=="aggressive" and .90 or .82)
  local fastFps=target*(mode=="aggressive" and .985 or .94)
  local dwell=mode=="aggressive" and 1.5 or 3.0
  local want=0
  if auto.ema>1/math.max(1,slowFps) then want=-1 elseif auto.ema<1/math.max(1,fastFps) then want=1 end
  if want==0 then auto.hold=0;return end
  auto.hold=auto.hold+dt;if auto.hold<dwell then return end;auto.hold=0
  local rank=RANK[auto.tier] or 3
  auto.tier=Quality.ORDER[math.max(1,math.min(#Quality.ORDER,rank+want))]
end

function Quality.tier()
  local m=Settings.get("quality")
  if m and m~="auto" then return m end
  local c=Config.get().quality
  if c and c~="auto" then return c end
  if not auto.tier then auto.tier=platformDefault() end
  return auto.tier
end
function Quality.profile() return Quality.TIERS[Quality.tier()] or Quality.TIERS.medium end

local TEXTURE={full=1.00,high=.75,medium=.50,low=.375,minimum=.25}
local DISTANCE={far=1.00,medium=.72,near=.52,minimum=.36}
local SIM={full=1.00,balanced=1.35,light=1.75,minimum=2.40}
function Quality.textureScale()
  local v=Settings.get("textureDetail");if v and v~="quality" then return TEXTURE[v] or 1 end
  return Quality.profile().textureScale or 1
end
function Quality.reflectionMode()
  local v=Settings.get("reflectionDetail");if v and v~="quality" then return v end
  return Quality.profile().reflection or "full"
end
function Quality.effectDistanceScale()
  local v=Settings.get("effectDistance");if v and v~="quality" then return DISTANCE[v] or 1 end
  return Quality.profile().effectDistanceScale or 1
end
function Quality.simulationIntervalMultiplier()
  local v=Settings.get("simulationDetail");if v and v~="quality" then return SIM[v] or 1 end
  return Quality.profile().simulationInterval or 1
end
function Quality.cloudDetailScale() return Quality.profile().cloudDetail or 1 end
function Quality.auroraDetail()
  local p=Quality.profile()
  return {segments=p.auroraSegments or 72,layers=p.auroraLayers or 10,sheets=p.auroraSheets or 4}
end
function Quality.worldRadiusCap()
  local override=Settings.get("effectDistance")
  if override and override~="quality" then
    return ({far=750,medium=420,near=280,minimum=180})[override] or 750
  end
  return Quality.profile().worldRadiusCap or 750
end

function Quality.effective()
  return {
    tier=Quality.tier(), auto=Quality.autoEnabled(), targetFps=Quality.targetFps(),
    textureScale=Quality.textureScale(), reflection=Quality.reflectionMode(),
    effectDistanceScale=Quality.effectDistanceScale(), worldRadiusCap=Quality.worldRadiusCap(),
    simulationInterval=Quality.simulationIntervalMultiplier(), cloudDetail=Quality.cloudDetailScale(),
    aurora=Quality.auroraDetail(),
  }
end

function Quality.celestial()
  local p=Quality.profile()
  -- Catalogue identity is preserved on every tier. Lower quality reduces only
  -- expensive disc/aurora geometry, never which constellations or planets exist.
  return {starStep=1,maxPlanets=9,twinkle=true,sunLayers=p.sunLayers or 4,meteors=true}
end

function Quality.budget(density)
  local tier=Quality.profile();local perfScale=1
  pcall(function() local G=V.require("PerformanceGovernor");if G and G.particleScale then perfScale=G.particleScale() end end)
  density=clamp(tonumber(density) or 1,0,3)
  local cap=Config.get().maxParticles
  local function one(v) v=math.floor(v*density*perfScale+.5);if cap and v>cap then v=math.floor(cap) end;return math.max(0,v) end
  local function world(v) v=math.max(0,math.floor((tonumber(v) or 0)*perfScale));if cap and v>cap then v=math.floor(cap) end;return v end
  return {
    rain=one(tier.rain),snow=one(tier.snow),grain=one(tier.grain),splash=one(tier.splash),
    worldPrecip=tier.worldPrecip or 1,worldRadiusCap=Quality.worldRadiusCap(),
    worldRainCap=world(tier.worldRainCap or 12000),worldSnowCap=world(tier.worldSnowCap or 100000),
    worldBlizzardCap=world(tier.worldBlizzardCap or tier.worldSnowCap or 100000),worldHailCap=world(tier.worldHailCap or 45000),
    worldSandCap=world(tier.worldSandCap or 43200),worldDebrisCap=world(tier.worldDebrisCap or 3600),worldAshCap=world(tier.worldAshCap or 10800),
    snowPackDrawCap=world(tier.snowPackDrawCap or 4800),footDrawCap=world(tier.footDrawCap or 192),
    snowProbeCap=math.max(8,math.floor((tonumber(tier.snowProbeCap) or 96)*math.max(0.35,perfScale)+0.5)),
    atmosphereScale=tier.atmosphereScale or 1,fogLayers=tier.fogLayers,bolt=tier.bolt,
  }
end

function Quality.reset() auto.tier=nil;auto.ema=1/60;auto.hold=0 end
function Quality.describe()
  local tier=Quality.tier();local c=Config.get().quality;local m=Settings.get("quality")
  if (m==nil or m=="auto") and (c==nil or c=="auto") then
    local mode=Settings.get("autoPerformance") or "balanced"
    return ("AUTO/%s %s %.1ffps"):format(tier:upper(),mode:upper(),1/math.max(auto.ema,1e-6))
  end
  return tier:upper()
end
return Quality
