-- Aurora Borealis — season-weighted magnetic-sky renderer.
--
-- Realism contract:
--   * luminous THIN sheets / curtains, not fog cards;
--   * long horizon-scale arcs with folds, rays and slowly evolving structure;
--   * altitude-coded colour ordering: lower N2 purple/blue fringe, dominant
--     oxygen green body, rarer high oxygen red cap;
--   * strong events expand overhead and naturally form a corona-like
--     perspective because the curtain geometry approaches the zenith;
--   * world-vault geometry is drawn before weather clouds so cloud banks retain
--     physical occlusion authority;
--   * winter strongly favours natural displays, but every non-winter night has
--     an independent deterministic 5% eligibility chance. Real aurora can occur
--     year-round; winter mainly provides longer darkness.

local V = ...
local A = {}

local visualTime=0
local current={active=false,season="SPRING",nightKey=nil,intensity=0,envelope=0,visibility=0,class="none",cloud=1}
local cachedPlanKey=nil
local cachedPlan=nil
local rowA,rowB={},{} -- reusable curtain rows; no steady-state per-vertex table allocation
local columns={} -- reusable u-column descriptors; expensive fold/ray fields computed once per sheet

local function clamp(v,a,b) v=tonumber(v) or 0;if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function fract(x) return x-math.floor(x) end
local function hash(n)
  -- Arithmetic hash: deterministic across the supported Lua runtimes without
  -- paying for a transcendental sin() on every auroral noise sample. The
  -- integer domain is deliberately bounded before two LCG scrambles so double
  -- precision remains exact enough for stable nightly identities.
  local x=math.floor((tonumber(n) or 0)*4096+0.5)%2147483647
  x=(x*48271+12820163)%2147483647
  x=(x*40692+3791)%2147483647
  return x/2147483647
end
local function mix(a,b,t) return a+(b-a)*t end
local function noise1(seed,x)
  local i=math.floor(x);local f=smooth(x-i)
  local a=hash((tonumber(seed) or 0)*37.17+i*1.731)
  local b=hash((tonumber(seed) or 0)*37.17+(i+1)*1.731)
  return mix(a,b,f)
end
local function rad(d) return d*math.pi/180 end
local function wrappedHourDelta(h,c) return ((h-c+12)%24)-12 end

local function req(name)
  local ok,m=pcall(V.require,name)
  return ok and m or nil
end

local function eventsEnabled()
  local S=req("Settings")
  if S and S.get then
    local m=S.get("celestialEvents")
    if m=="off" then return false elseif m=="on" then return true end
  end
  local C=req("Config"); local c=C and C.get and C.get() or nil
  return not (c and c.celestial and c.celestial.events==false)
end

local function seasonNow()
  local S=req("Seasons")
  if S and S.current then local ok,v=pcall(S.current);if ok and type(v)=="string" then return v:upper() end end
  return S and type(S.id)=="string" and S.id:upper() or "SPRING"
end

local function clockNow()
  local T=req("TimeOfDay")
  local h=tonumber(T and T.hour) or 0
  local day=0
  if T and T.gameDaySerial then local ok,v=pcall(T.gameDaySerial);if ok then day=tonumber(v) or 0 end
  elseif T then day=math.floor((tonumber(T.elapsed) or 0)/math.max(30,24*60)) end
  -- Keep one deterministic plan across midnight: 01:00 belongs to the night
  -- that began on the previous game-day serial.
  local nightKey=math.floor(day)
  if h<12 then nightKey=nightKey-1 end
  return h,nightKey
end

local function planFor(nightKey)
  if cachedPlanKey==nightKey and cachedPlan then return cachedPlan end
  local winterEligible=hash(nightKey*1.73+11.2)<0.58 -- strong seasonal feature, never constant
  -- Exact requested off-season rule: every non-winter night gets one stable
  -- 5% natural-aurora roll. It is deliberately independent from the winter
  -- schedule so changing seasons cannot reroll the same night's identity.
  local offSeasonEligible=hash(nightKey*9.91+27.3)<0.05
  local q=hash(nightKey*3.11+41.7)
  local intensity=.36+q*.64
  -- A small tail of truly active nights should be memorable, while most
  -- displays remain pale enough to look like night vision rather than neon.
  if hash(nightKey*5.33+8.1)>.91 then intensity=math.max(intensity,.88) end
  local center=(23.15+hash(nightKey*7.17+9.4)*2.1)%24
  local halfSpan=2.8+hash(nightKey*2.91+13.8)*2.25
  local azCenter=rad(-14+hash(nightKey*4.07+3.6)*28)
  local spanDeg=105+intensity*72+hash(nightKey*8.3+5.2)*18
  local cls=(intensity<.56 and "quiet") or (intensity<.82 and "active") or "storm"
  cachedPlan={eligible=winterEligible,winterEligible=winterEligible,offSeasonEligible=offSeasonEligible,
    intensity=intensity,center=center,halfSpan=halfSpan,azCenter=azCenter,span=rad(spanDeg),
    seed=nightKey*17.731+5.9,class=cls}
  cachedPlanKey=nightKey
  return cachedPlan
end

local function opticalVisibility(base)
  local cloud=1;local moon=0;local building=1
  local E=req("CelestialEngine")
  if E and E.state then
    local ok,s=pcall(E.state)
    if ok and type(s)=="table" then
      local o=s.optics or {}
      if type(o.skyTransmission)=="number" then cloud=clamp(o.skyTransmission,0,1)
      elseif type(o.localCloudTransmission)=="number" then cloud=clamp(o.localCloudTransmission,0,1) end
      moon=clamp(tonumber(s.moonLight) or tonumber(s.moon and s.moon.alpha) or 0,0,1)
    end
  end
  local B=req("BuildingLight")
  if B and type(B.factor)=="number" then building=clamp(B.factor,0,1) end
  -- Full moon/city light reduce apparent contrast, not intrinsic emission.
  -- Strong aurora remain readable; opaque cloud still wins later in the real 3D
  -- composition pass and this factor keeps projected fallback honest too.
  local vis=base*(.86+.14*building)*(1-.22*moon)*(.06+.94*cloud^1.35)
  return clamp(vis,0,1),cloud
end

local function sample(nightVis)
  local season=seasonNow();local hour,key=clockNow();local p=planFor(key)
  local seasonalEligible=(season=="WINTER") and p.winterEligible or p.offSeasonEligible
  local active=eventsEnabled() and seasonalEligible
  local env=0
  if active then
    local d=math.abs(wrappedHourDelta(hour,p.center))
    local inner=p.halfSpan*.56
    if d<=inner then env=1
    elseif d<p.halfSpan then env=1-smooth((d-inner)/math.max(.01,p.halfSpan-inner)) end
  end
  local base=clamp(tonumber(nightVis) or 0,0,1)*env
  local vis,cloud=opticalVisibility(base)
  current.active=active and vis>.004;current.season=season;current.nightKey=key
  current.intensity=p.intensity;current.envelope=env;current.visibility=vis;current.class=active and p.class or "none";current.cloud=cloud
  current.plan=p;current.seasonalEligible=seasonalEligible
  return p,vis
end

function A.update(dt)
  visualTime=visualTime+clamp(dt,0,.25)
  sample(1)
end

local function direction(az,el)
  local ce=math.cos(el)
  -- magnetic north = world -Z. This is a fixed celestial direction, never a
  -- camera-facing screen ribbon.
  return math.sin(az)*ce,math.sin(el),-math.cos(az)*ce
end

local function prepareColumns(plan,sheet,seg)
  local intensity=plan.intensity
  local slow=visualTime*.010
  for i=0,seg do
    local u=i/seg
    local q=columns[i+1]
    if not q then q={};columns[i+1]=q end

    -- Slow irregular curtain body. All u-only fields are solved once here and
    -- reused by every altitude layer, which keeps the dense mesh cheap without
    -- reducing its spatial resolution.
    local fold=(noise1(plan.seed+sheet*3.1,u*7.2+slow)-.5)*(.105+.060*intensity)
      +(noise1(plan.seed*1.7+sheet*5.3,u*19.0-slow*.72)-.5)*.050
      +math.sin(u*math.pi*2*(1.17+sheet*.11)+plan.seed*.21+visualTime*.018)*.018
    local az=plan.azCenter+(u-.5)*plan.span+fold+(sheet-2)*rad(1.75)
    local bottomDeg=7.2+sheet*1.05
      +(noise1(plan.seed+sheet*8.6,u*11.5+slow*.24)-.5)*4.8
    local bottom=rad(clamp(bottomDeg,4.5,14.5))
    local topDeg=43+intensity*41
    if intensity>.82 then topDeg=85+(intensity-.82)/.18*3.2 end
    local ruffle=(noise1(plan.seed*2.3+sheet*9.7,u*10.5-slow*.40)-.5)*(12+18*intensity)
      +(noise1(plan.seed+sheet*13.2,u*27+slow*.26)-.5)*(4+7*intensity)
    local top=rad(clamp(topDeg+ruffle,34,89.0))

    -- Fine discrete-ray field. Broad bundles evolve slowly while narrow rays
    -- scintillate faster. These values are also u-only and therefore shared by
    -- all vertices up the same magnetic-field-aligned column.
    local broad=noise1(plan.seed+sheet*2.7,u*8.5+visualTime*.010*(.8+sheet*.05))
    local fine=noise1(plan.seed*1.9+sheet*7.1,u*62-visualTime*.080*(.9+sheet*.04))
    local needle=noise1(plan.seed*3.2+sheet*11.4,u*138+visualTime*.135*(.8+sheet*.03))
    fine=smooth(clamp((fine-.48)/.52,0,1));fine=fine*fine*fine
    needle=smooth(clamp((needle-.67)/.33,0,1));needle=needle*needle*needle*needle
    local ray=clamp(.12+.22*broad+.70*fine+.62*needle,.10,1.18)
    local activation=.52+.48*smooth(noise1(plan.seed+31+sheet,u*4.2-visualTime*.006))
    local he=math.sqrt(math.max(0,math.sin(math.pi*clamp(u,0,1))))
    local phase=hash(plan.seed*5.7+sheet*29.1+i*1.13)*math.pi*2

    q[1],q[2]=math.sin(az),math.cos(az)
    q[3],q[4]=bottom,top
    q[5],q[6],q[7],q[8]=ray,activation,he,phase
  end
end

local function vertexColor(v,plan,visibility,sheet,q)
  local intensity=plan.intensity
  local lower=(1-smooth((v-.02)/.20))*clamp((intensity-.44)*1.8,0,1)
  local upper=smooth((v-.68)/.30)*clamp((intensity-.50)*2.10,0,1)
  -- Pale oxygen green dominates. Low-activity aurora stay desaturated because
  -- faint displays are commonly perceived as whitish/grey-green rather than
  -- camera-saturated neon. Energetic lower N2 and high oxygen emissions are
  -- layered by altitude instead of tinting the whole curtain.
  local sat=.24+.43*intensity
  local grr,grg,grb=mix(.57,.28,sat),mix(.78,.94,sat),mix(.62,.43,sat)
  local pr,pg,pb=.43,.25,.78
  local rr,rg,rb=.86,.23,.29
  local r,g,b=grr,grg,grb
  if lower>0 then r=mix(r,pr,lower*.64);g=mix(g,pg,lower*.64);b=mix(b,pb,lower*.64) end
  if upper>0 then r=mix(r,rr,upper*.82);g=mix(g,rg,upper*.82);b=mix(b,rb,upper*.82) end
  -- Crisp lower border, then a translucent ray field extending upward. The
  -- extreme top fades rather than ending on a hard polygon edge.
  local ve=smooth(v/.035)*(1-smooth((v-.91)/.09))
  local lowerEdge=1+.46*(1-smooth(math.abs(v-.10)/.085))
  local a=visibility*(.016+.062*intensity)*q[5]*q[6]*ve*lowerEdge*q[7]*(1-.14*(sheet-1))
  return r,g,b,a
end

local function fillRow(row,plan,visibility,sheet,v,seg)
  local intensity=plan.intensity
  local waveAmp=rad(.55+.50*intensity)
  for i=0,seg do
    local q=columns[i+1]
    local el=q[3]+(q[4]-q[3])*v
    -- One inexpensive coherent phase per column is enough to keep rays alive;
    -- irregular column phases prevent a ruled or flag-like periodic pattern.
    el=el+math.sin(q[8]+v*4.2+visualTime*.11)*waveAmp
    local ce=math.cos(el)
    local x,y,z=q[1]*ce,math.sin(el),-q[2]*ce
    local r,g,b,a=vertexColor(v,plan,visibility,sheet,q)
    local dst=row[i+1]
    if not dst then dst={};row[i+1]=dst end
    dst[1],dst[2],dst[3],dst[4],dst[5],dst[6],dst[7]=x,y,z,r,g,b,a
  end
end

local function geometry(plan,visibility,emitTri)
  if visibility<.004 then return 0 end
  local sheets=plan.intensity>.84 and 4 or (plan.intensity>.55 and 3 or 2)
  local seg,layers,sheetCap=72,10,4
  -- QUALITY changes mesh density, never auroral morphology, eligibility, colour
  -- ordering or the overhead-corona geometry. Full fidelity remains the exact
  -- 72x10 researched curtain; low-end tiers sample the same continuous field
  -- with fewer cells and sheets.
  local Q=req("Quality")
  if Q and Q.auroraDetail then
    local ok,d=pcall(Q.auroraDetail)
    if ok and type(d)=="table" then
      seg=math.max(18,math.floor(tonumber(d.segments) or seg))
      layers=math.max(3,math.floor(tonumber(d.layers) or layers))
      sheetCap=math.max(2,math.floor(tonumber(d.sheets) or sheetCap))
    end
  end
  sheets=math.min(sheets,sheetCap)
  local cells=0
  for s=1,sheets do
    prepareColumns(plan,s,seg)
    fillRow(rowA,plan,visibility,s,0,seg)
    for j=0,layers-1 do
      local v1=(j+1)/layers
      fillRow(rowB,plan,visibility,s,v1,seg)
      for i=0,seg-1 do
        local a0,a1=rowA[i+1],rowA[i+2]
        local b0,b1=rowB[i+1],rowB[i+2]
        emitTri(a0[1],a0[2],a0[3],a0[4],a0[5],a0[6],a0[7],
             a1[1],a1[2],a1[3],a1[4],a1[5],a1[6],a1[7],
             b1[1],b1[2],b1[3],b1[4],b1[5],b1[6],b1[7])
        emitTri(a0[1],a0[2],a0[3],a0[4],a0[5],a0[6],a0[7],
             b1[1],b1[2],b1[3],b1[4],b1[5],b1[6],b1[7],
             b0[1],b0[2],b0[3],b0[4],b0[5],b0[6],b0[7])
        cells=cells+1
      end
      rowA,rowB=rowB,rowA
    end
  end
  return cells
end

function A.appendWorld(verts,n,pushTri,eye,radius,time,nightVis)
  if type(pushTri)~="function" or type(eye)~="table" then return n end
  if type(time)=="number" then visualTime=math.max(visualTime,time) end
  local plan,vis=sample(nightVis);if vis<.004 then return n end
  radius=tonumber(radius) or 420;n=n or 0
  local ex,ey,ez=tonumber(eye[1]) or 0,tonumber(eye[2]) or 0,tonumber(eye[3]) or 0
  local sheetRadius=radius*.986
  local function emit(x1,y1,z1,r1,g1,b1,a1,x2,y2,z2,r2,g2,b2,a2,x3,y3,z3,r3,g3,b3,a3)
    n=pushTri(verts,n,
      ex+x1*sheetRadius,ey+y1*sheetRadius,ez+z1*sheetRadius,r1,g1,b1,a1,
      ex+x2*sheetRadius,ey+y2*sheetRadius,ez+z2*sheetRadius,r2,g2,b2,a2,
      ex+x3*sheetRadius,ey+y3*sheetRadius,ez+z3*sheetRadius,r3,g3,b3,a3)
  end
  geometry(plan,vis,emit)
  return n
end

function A.appendProjected(verts,n,pushTri,project,time,nightVis)
  if type(pushTri)~="function" or type(project)~="function" then return n end
  if type(time)=="number" then visualTime=math.max(visualTime,time) end
  local plan,vis=sample(nightVis);if vis<.004 then return n end
  n=n or 0
  local function emit(x1,y1,z1,r1,g1,b1,a1,x2,y2,z2,r2,g2,b2,a2,x3,y3,z3,r3,g3,b3,a3)
    local sx1,sy1=project(x1,y1,z1);local sx2,sy2=project(x2,y2,z2);local sx3,sy3=project(x3,y3,z3)
    if sx1 and sx2 and sx3 then n=pushTri(verts,n,sx1,sy1,r1,g1,b1,a1,sx2,sy2,r2,g2,b2,a2,sx3,sy3,r3,g3,b3,a3) end
  end
  geometry(plan,vis,emit)
  return n
end

function A.state() return current end
function A.stats()
  return {active=current.active,season=current.season,class=current.class,intensity=current.intensity,
    visibility=current.visibility,cloud=current.cloud,nightKey=current.nightKey,seasonalEligible=current.seasonalEligible,
    model="layered-field-aligned-curtains"}
end
function A._planForTest(k) return planFor(tonumber(k) or 0) end
function A._sampleForTest(nightVis) return sample(nightVis) end
function A.reset() visualTime=0;cachedPlanKey=nil;cachedPlan=nil;current={active=false,season="SPRING",intensity=0,envelope=0,visibility=0,class="none",cloud=1} end

return A
