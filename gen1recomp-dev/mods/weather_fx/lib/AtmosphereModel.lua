local V = ...

-- Weather FX 7 compact physical-atmosphere model. It is deliberately analytical
-- rather than a costly per-pixel ray marcher: Rayleigh wavelength response,
-- aerosol/Mie extinction, ozone warmth, cloud transmission and solar elevation
-- are computed once at low frequency and fed to the proven render paths.
local Atmosphere = {}
local current={rayleigh=1,mie=.10,haze=.04,cloud=.1,visibility=1,warmth=0,turbidity=2.2,ozone=.30,sunElevation=45,horizonExtinction=.1,
  rayleighR=.17,rayleighG=.40,rayleighB=1,skyR=.35,skyG=.58,skyB=.96,horizonR=.60,horizonG=.68,horizonB=.78}

local function clamp01(v) if v<0 then return 0 elseif v>1 then return 1 end return v end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function inv4(nm) return 1/((nm/440)^4) end
local RB,GB,BB=inv4(680),inv4(550),inv4(440)
local RN=math.max(RB,GB,BB); RB,GB,BB=RB/RN,GB/RN,BB/RN

function Atmosphere.update(dt,sim,celestial,cloudField)
  sim=sim or {}; cloudField=cloudField or {}; local sun=(celestial and celestial.sun) or {}; local alt=tonumber(sun.altitudeDeg) or 45
  current.sunElevation=alt
  current.cloud=clamp01(math.max(tonumber(sim.cloud) or .1,tonumber(cloudField.density) or 0))
  current.visibility=clamp01(tonumber(sim.visibility) or 1)
  current.haze=clamp01((tonumber(sim.aerosol) or .05)+current.cloud*.08)
  current.turbidity=clamp(1.8+current.haze*5.2+current.cloud*.9,1.8,8)
  current.ozone=clamp01(.24+current.haze*.12)
  current.mie=.07+current.haze*.82
  current.rayleigh=.76+.24*current.visibility
  current.rayleighR,current.rayleighG,current.rayleighB=RB*current.rayleigh,GB*current.rayleigh,BB*current.rayleigh
  local horizon=clamp01(1-math.max(0,alt)/18)
  -- 8.1.26: make golden hour a real low-sun atmospheric state rather than a
  -- tiny tint coefficient. It rises through pre-sunrise twilight, peaks around
  -- the horizon and decays smoothly as the sun climbs out of the long optical
  -- path. This changes sky scattering, not game/world time.
  local warmRise=clamp01((alt+10)/10)
  local warmFall=1-clamp01((alt-2)/18)
  current.warmth=clamp01(warmRise*warmFall)
  current.cloudTransmission=clamp01(tonumber(cloudField.transmission) or math.exp(-current.cloud*1.3))
  current.horizonExtinction=clamp01(.08+current.haze*.58+horizon*.30)
  current.fogDensity=clamp01((1-current.visibility)*.72+current.haze*.20+horizon*current.haze*.10)
  current.sunTransmission=clamp01(current.cloudTransmission*math.exp(-current.mie*(.35+horizon*1.8)))
  current.skyLuminance=clamp01((.20+.80*clamp01((alt+8)/35))*current.sunTransmission+.08*(1-current.cloudTransmission))
  -- Analytical RGB estimate used by gradients/world lighting. Blue Rayleigh
  -- dominates high sun; Mie/ozone and long optical path warm the horizon.
  local day=clamp01((alt+8)/24); local warm=current.warmth
  current.skyR=clamp01((.18+.24*RB)*day + warm*.34 + current.haze*.10)
  current.skyG=clamp01((.28+.38*GB)*day + warm*.18 + current.haze*.10)
  current.skyB=clamp01((.38+.55*BB)*day - warm*.26 + current.haze*.06)
  current.horizonR=clamp01(current.skyR+.18+warm*.28)
  current.horizonG=clamp01(current.skyG+.10+warm*.08)
  current.horizonB=clamp01(current.skyB-.10-warm*.22)
end

function Atmosphere.applyBands(bands)
  if type(bands)~="table" then return bands end
  local out={}
  for i,b in ipairs(bands) do
    if type(b)=="table" then
      local c={}; for k,v in pairs(b) do c[k]=v end
      local r,g,bl = tonumber(c[1] or c.r) or 0, tonumber(c[2] or c.g) or 0, tonumber(c[3] or c.b) or 0
      local t=(#bands>1) and ((i-1)/(#bands-1)) or .5
      -- `bands[1]` is zenith/top and the final band is the horizon. The old
      -- interpolation was reversed, applying horizon warmth to the zenith and
      -- blue-sky colour to the horizon; that muted sunrise/sunset exactly where
      -- players expected it to be strongest.
      local physR=current.skyR*(1-t)+current.horizonR*t; local physG=current.skyG*(1-t)+current.horizonG*t; local physB=current.skyB*(1-t)+current.horizonB*t
      local strength=.12+.18*current.haze+.10*current.warmth
      r=clamp01(r*(1-strength)+physR*strength); g=clamp01(g*(1-strength)+physG*strength); bl=clamp01(bl*(1-strength)+physB*strength)
      if c[1]~=nil then c[1],c[2],c[3]=r,g,bl else c.r,c.g,c.b=r,g,bl end
      out[i]=c
    else out[i]=b end
  end
  return out
end

function Atmosphere.peek() return current end
function Atmosphere.grade() local o={}; for k,v in pairs(current) do o[k]=v end; return o end
function Atmosphere.describe() return string.format("rayleigh=%.2f mie=%.2f turbidity=%.2f haze=%.2f cloud=%.2f vis=%.2f warm=%.2f",current.rayleigh,current.mie,current.turbidity,current.haze,current.cloud,current.visibility,current.warmth) end
return Atmosphere
