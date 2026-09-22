-- CelestialBodies — player-centered origin, world-oriented day arc
--
-- MODEL:
--   Origin  = player / eye POSITION (sphere center follows the player)
--   Orient  = WORLD axes only (never player/camera rotation)
--   Angle   = game time only
--
-- DAY ARC (what you see looking at the sky):
--   Sunrise  → EAST,  on the horizon
--   Noon     → nearly OVERHEAD (top of sky)
--   Sunset   → WEST,  on the horizon
--
-- World basis: +X east, +Y up, +Z south.
-- The day arc lives in the East–Up plane (X/Y):
--   dir = (cos(α), sin(α), 0)  with α = 0 at east, π/2 overhead, π at west
-- That is a pure rotation about world +Z (north–south), so the sun climbs
-- the sky and sets opposite — not a flat spin around vertical, and not a
-- south-biased path that looked like the "wrong axis" in play.
--
-- Moon is always opposite: α_moon = α_sun + π (below when sun is above).

local V = ...
local Celestial = {}
local TOD = V.require("TimeOfDay")

-- 8.1.15: 40% smaller than the previous 3D presentation. Real celestial
-- angular diameter is effectively constant across one rise/set arc, so do not
-- swell the discs toward zenith.
local SUN_HALF, MOON_HALF = 15.84, 10.08
local SKY_RADIUS = 280  -- closer so FPV look-up clearly sees overhead disc

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function normAngle(a)
  local two = math.pi * 2
  a = a % two
  if a < 0 then a = a + two end
  return a
end

-- α: 0 = east horizon, π/2 = overhead, π = west horizon, 3π/2 = below.
local function worldDirFromAlpha(alpha)
  local dx = math.cos(alpha)   -- east (+) / west (−)
  local dy = math.sin(alpha)   -- up (+) / below (−)
  local dz = 0                 -- arc in East–Up plane (no south bias)
  local L = math.sqrt(dx * dx + dy * dy + dz * dz)
  if L > 1e-8 then dx, dy, dz = dx / L, dy / L, dz / L end
  return dx, dy, dz
end

function Celestial.bodies(hour)
  -- CelestialEngine is the weather-adjusted authority. Explicit hour requests
  -- (tests/pinned previews) still sample CelestialSim directly.
  if hour == nil then
    local okE, E = pcall(V.require, "CelestialEngine")
    if okE and E and E.state then
      local okS, st = pcall(E.state)
      if okS and st and st.sun and st.moon then
        return {hour=st.hour, sun=st.sun, moon=st.moon, sim=st.sim, eclipse=st.sim and st.sim.eclipse}
      end
    end
  end
  local Sim
  pcall(function() Sim = V.require("CelestialSim") end)
  if Sim and Sim.sample then return Sim.sample(hour) end
  hour = tonumber(hour) or ((TOD and TOD.hour) or 12)
  hour = hour % 24
  local alpha = ((hour - 6.0) / 24.0) * math.pi * 2
  local dx, dy, dz = math.cos(alpha), math.sin(alpha), 0
  local moonA = alpha + math.pi
  local mx, my, mz = math.cos(moonA), math.sin(moonA), 0
  return {hour=hour, sun={dx=dx,dy=dy,dz=dz,theta=alpha,el=math.asin(dy),alpha=dy>0.02 and .9 or 0,kind="sun",above=dy>0},
    moon={dx=mx,dy=my,dz=mz,theta=moonA,el=math.asin(my),alpha=my>0.02 and .9 or 0,kind="moon",above=my>0,illumination=1,phase=.5,phaseAngle=math.pi,phaseName="FULL"}}
end

function Celestial.direction(hour)
  local b = Celestial.bodies(hour)
  if b.sun.alpha > 0.02 then
    local s = b.sun
    return s.dx, s.dy, s.dz, "sun", s.alpha, s.theta, s.el
  end
  if b.moon.alpha > 0.02 then
    local m = b.moon
    return m.dx, m.dy, m.dz, "moon", m.alpha, m.theta, m.el
  end
  return nil
end

function Celestial.bodyDir(hour)
  local b = Celestial.bodies(hour)
  if b.sun.alpha >= b.moon.alpha and b.sun.alpha > 0.02 then
    return b.sun.dx, b.sun.dy, b.sun.dz
  end
  if b.moon.alpha > 0.02 then
    return b.moon.dx, b.moon.dy, b.moon.dz
  end
  return b.sun.dx, b.sun.dy, b.sun.dz
end

function Celestial.bodyAt(hour)
  local b = Celestial.bodies(hour)
  if b.sun.alpha > 0.02 then
    return math.deg(b.sun.theta), math.deg(b.sun.el), false
  end
  if b.moon.alpha > 0.02 then
    return math.deg(b.moon.theta), math.deg(b.moon.el), true
  end
  return math.deg(b.sun.theta), math.deg(b.sun.el), false
end

function Celestial.shearAt(hour)
  if hour == nil then
    local ok,E=pcall(V.require,"CelestialEngine")
    if ok and E and E.shadowRig then
      local ok2,kx,kz=pcall(E.shadowRig)
      if ok2 and type(kx)=="number" and type(kz)=="number" then return kx,kz end
    end
  end
  local b=Celestial.bodies(hour)
  local s=(b.moon and (b.moon.intensity or 0)>(b.sun.intensity or 0)) and b.moon or b.sun
  local dy=s.dy; if dy<0.08 then dy=0.08 end
  local kx,kz=-s.dx/dy,-s.dz/dy
  if kx>3 then kx=3 elseif kx< -3 then kx=-3 end
  if kz>3 then kz=3 elseif kz< -3 then kz=-3 end
  return kx,kz
end

function Celestial.pose(hour)
  local b = Celestial.bodies(hour)
  return {
    hour = b.hour,
    sunAz = math.deg(b.sun.theta), sunAlt = math.deg(b.sun.el),
    moonAz = math.deg(b.moon.theta), moonAlt = math.deg(b.moon.el),
    sepDeg = math.deg(normAngle(b.moon.theta - b.sun.theta)),
  }
end

function Celestial.debugSnapshot(hour)
  local b = Celestial.bodies(hour)
  local s, m = b.sun, b.moon
  return string.format(
    "[WX] t=%.2f arc=East-Zenith-West | SUN (%.2f,%.2f,%.2f) a=%.2f | MOON (%.2f,%.2f,%.2f) a=%.2f",
    b.hour, s.dx, s.dy, s.dz, s.alpha, m.dx, m.dy, m.dz, m.alpha)
end

local function billboardAxes(Voxel3D)
  local e, fo = Voxel3D.eye, Voxel3D.focus
  if not e then return nil, nil end
  if not fo then fo = { e[1], e[2], e[3] - 1 } end
  local fx, fy, fz = fo[1] - e[1], fo[2] - e[2], fo[3] - e[3]
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
  if fl < 1e-6 then return nil, nil end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local rx, ry, rz = -fz, 0, fx
  local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
  if rl < 1e-6 then rx, ry, rz = 1, 0, 0 else rx, ry, rz = rx / rl, ry / rl, rz / rl end
  local ux = ry * fz - rz * fy
  local uy = rz * fx - rx * fz
  local uz = rx * fy - ry * fx
  local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
  if ul < 1e-6 then return { rx, ry, rz }, { 0, 1, 0 } end
  return { rx, ry, rz }, { ux / ul, uy / ul, uz / ul }
end

local function pushQuad(verts, n, cx, cy, cz, half, axisR, axisU, r, g, b, a)
  local hx, hy, hz = axisR[1] * half, axisR[2] * half, axisR[3] * half
  local vx, vy, vz = axisU[1] * half, axisU[2] * half, axisU[3] * half
  local function v(ox, oy, oz)
    n = n + 1
    local t = verts[n]
    if not t then t = { 0, 0, 0, 0, 0, 0, 0 }; verts[n] = t end
    t[1], t[2], t[3] = cx + ox, cy + oy, cz + oz
    t[4], t[5], t[6], t[7] = r, g, b, a
    return n
  end
  n = v(-hx - vx, -hy - vy, -hz - vz)
  n = v( hx - vx,  hy - vy,  hz - vz)
  n = v( hx + vx,  hy + vy,  hz + vz)
  n = v(-hx - vx, -hy - vy, -hz - vz)
  n = v( hx + vx,  hy + vy,  hz + vz)
  n = v(-hx + vx, -hy + vy, -hz + vz)
  return n
end

local function pushRectQuad(verts, n, cx, cy, cz, halfR, halfU, axisR, axisU, r, g, b, a)
  local hx, hy, hz = axisR[1] * halfR, axisR[2] * halfR, axisR[3] * halfR
  local vx, vy, vz = axisU[1] * halfU, axisU[2] * halfU, axisU[3] * halfU
  local function v(ox, oy, oz)
    n=n+1; local t=verts[n]
    if not t then t={0,0,0,0,0,0,0}; verts[n]=t end
    t[1],t[2],t[3]=cx+ox,cy+oy,cz+oz; t[4],t[5],t[6],t[7]=r,g,b,a
  end
  v(-hx-vx,-hy-vy,-hz-vz); v(hx-vx,hy-vy,hz-vz); v(hx+vx,hy+vy,hz+vz)
  v(-hx-vx,-hy-vy,-hz-vz); v(hx+vx,hy+vy,hz+vz); v(-hx+vx,-hy+vy,-hz+vz)
  return n
end

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexColor", "float", 4 },
}

local function ensureShader()
  if Celestial._sh then return Celestial._sh end
  if not (love and love.graphics and love.graphics.newShader) then return nil end
  local ok, sh = pcall(love.graphics.newShader, [[
    varying vec4 vColor;
    varying float vWorldY;
#ifdef VERTEX
    uniform mat4 vp;
    attribute vec4 VertexColor;
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
      vColor = VertexColor;
      vWorldY = vertex_position.y;
      // Sun/moon are infinitely distant sky bodies. Keep their projected
      // fragments at far scene depth so world geometry always occludes them.
      vec4 clip = vp * vertex_position;
      clip.z = clip.w;
      return clip;
    }
#endif
#ifdef PIXEL
    uniform float horizonY;
    uniform float horizonClip;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      // A celestial billboard may straddle the geometric horizon. Clip the
      // below-horizon pixels instead of fading/drawing the entire disc through
      // the terrain. This lets the visible limb shrink naturally as it sets.
      if (horizonClip > 0.5 && vWorldY < horizonY) discard;
      return vColor * color;
    }
#endif
  ]])
  if ok then Celestial._sh = sh end
  return Celestial._sh
end

local function bodyColor(body, fallback)
  local c=body and body.color
  if type(c)=="table" and type(c[1])=="number" then return c[1],c[2] or c[1],c[3] or c[1] end
  return fallback[1],fallback[2],fallback[3]
end

local function bodyVisible(body)
  if not body then return false end
  local a=tonumber(body.alpha) or 0
  -- Live composed bodies expose horizonFraction separately from atmospheric
  -- transmission. Allow the last horizon limb to render below the historical
  -- 0.02 alpha cutoff, but still let dense weather/cloud transmission hide the
  -- whole disc. Synthetic/legacy callers without these fields retain the old
  -- 0.02 safety threshold.
  if body.discTransmission~=nil and (tonumber(body.discTransmission) or 0)<=0.02 then return false end
  if body.horizonFraction~=nil then return (tonumber(body.horizonFraction) or 0)>0 and a>0.0001 end
  return a>=0.02
end

local function appendSun(verts,n,body,half,axisR,axisU,origin,radius,layers)
  if not bodyVisible(body) then return n end
  local cx,cy,cz=origin[1]+body.dx*radius,origin[2]+body.dy*radius,origin[3]+body.dz*radius
  local a=body.alpha -- constant angular size; no zenith swelling
  local cr,cg,cb=bodyColor(body,{1.0,0.88,0.42})
  -- Halo-free physical photosphere. Camera god rays are a separate post pass.
  if layers>=2 then n=pushQuad(verts,n,cx,cy,cz,half,axisR,axisU,math.min(1,cr),math.min(.94,cg*.94),math.min(.70,cb*.70),a*.94) end
  n=pushQuad(verts,n,cx,cy,cz,half*.38,axisR,axisU,1,math.min(.96,cg+.08),math.min(.76,cb+.14),a*.88)
  return n
end

-- Pixel-cell lunar disc. Unlike the old layered square, this actually renders
-- the synodic phase in the 3D sky. The dark hemisphere is faint earthshine in
-- ordinary nights and becomes an opaque silhouette during a solar eclipse.
local function appendMoon(verts,n,body,half,axisR,axisU,origin,radius,layers)
  if not bodyVisible(body) then
    Celestial._moonProof={cells=0,lit=0,dark=0,alpha=body and body.alpha or 0,phase=body and body.phase or nil,illumination=body and body.illumination or nil}
    return n
  end
  local cx,cy,cz=origin[1]+body.dx*radius,origin[2]+body.dy*radius,origin[3]+body.dz*radius
  local a=body.alpha; half=half*(tonumber(body.apparentScale) or 1)
  local illum=clamp01(tonumber(body.illumination) or 1); local phase=(tonumber(body.phase) or .5)%1
  local eclipse=clamp01(tonumber(body.solarEclipse) or 0)
  local lunar=clamp01(tonumber(body.lunarEclipse) or 0)
  local br,bg,bb=bodyColor(body,{0.82,0.86,0.98})
  local grid=layers>=4 and 14 or (layers>=3 and 12 or 9) -- slightly rounder enlarged moon limb
  local cell=half*2/grid; local hr=cell*.53; local hu=cell*.53
  local cells,litCells,darkCells=0,0,0
  for iy=1,grid do
    local ny=((iy-.5)/grid)*2-1
    for ix=1,grid do
      local nx=((ix-.5)/grid)*2-1
      local rr=nx*nx+ny*ny
      if rr<=1 then
        local lit
        local okSim,Sim=pcall(V.require,"CelestialSim")
        if okSim and Sim and Sim.moonPhaseLit then lit=Sim.moonPhaseLit(phase,illum,nx,ny)
        else
          local limb=math.sqrt(math.max(0,1-ny*ny)); local term=(1-2*illum)*limb
          lit=(phase<.5 and nx>=term) or (phase>=.5 and nx<=-term)
        end
        cells=cells+1
        if lit then litCells=litCells+1 else darkCells=darkCells+1 end
        local rr0,gg0,bb0,aa
        if lit then
          local edge=math.sqrt(rr); local shade=1-0.20*edge
          local crater=((ix*7+iy*11)%23==0) and .62 or 1
          rr0,gg0,bb0=br*shade*crater,bg*shade*crater,bb*shade*crater
          aa=a*(0.82+0.18*(1-edge))
        else
          local earth=.018+eclipse*.922
          rr0,gg0,bb0=0.028,0.034,0.052
          aa=a*earth
        end
        if lunar>.15 and lit then
          rr0=rr0*(1-lunar*.20)+0.72*lunar
          gg0=gg0*(1-lunar*.68)+0.12*lunar
          bb0=bb0*(1-lunar*.78)+0.07*lunar
        end
        local ox=axisR[1]*(nx*half)+axisU[1]*(ny*half)
        local oy=axisR[2]*(nx*half)+axisU[2]*(ny*half)
        local oz=axisR[3]*(nx*half)+axisU[3]*(ny*half)
        n=pushRectQuad(verts,n,cx+ox,cy+oy,cz+oz,hr,hu,axisR,axisU,rr0,gg0,bb0,aa)
      end
    end
  end
  Celestial._moonProof={cells=cells,lit=litCells,dark=darkCells,alpha=a,phase=phase,illumination=illum,solarEclipse=eclipse,lunarEclipse=lunar,darkAlpha=a*(.018+eclipse*.922)}
  return n
end

function Celestial.moonProof()
  return Celestial._moonProof
end

local function celestialLayers()
  local layers=4
  pcall(function() local Q=V.require("Quality"); if Q and Q.celestial then local c=Q.celestial(); if c and c.sunLayers then layers=tonumber(c.sunLayers) or 4 end end end)
  return math.max(1,math.min(4,math.floor(layers)))
end

function Celestial.drawWorld(Voxel3D, hour)
  if not (Voxel3D and Voxel3D.vp and Voxel3D.eye) then return false end
  -- 8.1.15: direct/legacy callers share NightSky's analytic body pass too.
  -- This closes the last route that could still expose the old tiled sphere
  -- mesh and its latitude/longitude-looking seam grid. NightSky only asks this
  -- module for body state, so the delegation cannot recurse through drawWorld.
  local okNS,NS=pcall(V.require,"NightSky")
  if okNS and NS and type(NS.drawSunMoonProjectedWorld)=="function" then
    local okDraw,drew=pcall(NS.drawSunMoonProjectedWorld,Voxel3D)
    if okDraw then return drew==true end
  end
  -- Nil means "use the fully composed CelestialEngine frame" (weather/cloud
  -- occlusion, eclipse, pollution/light state included). Do NOT coerce nil to
  -- TOD.hour here: an explicit numeric hour intentionally requests raw
  -- astronomy for previews/tests and would bypass the live composed authority.
  local b=Celestial.bodies(hour)
  local axisR,axisU=billboardAxes(Voxel3D); if not axisR then return false end
  local origin=Voxel3D.eye; local radius=SKY_RADIUS
  local far=Voxel3D.far or (Voxel3D.camera and Voxel3D.camera.far)
  if type(far)=="number" and far>80 then radius=math.min(far*.88,math.max(radius,far*.7)) end
  local layers=celestialLayers(); local sunVerts,moonVerts={},{}
  local sn=appendSun(sunVerts,0,b.sun,SUN_HALF,axisR,axisU,origin,radius,layers)
  local mn=appendMoon(moonVerts,0,b.moon,MOON_HALF,axisR,axisU,origin,radius,layers)
  local sh=ensureShader(); if not sh then return false end
  local prev; pcall(function() prev={love.graphics.getBlendMode()} end)
  local function drawOne(verts,n,blend)
    if n<3 then return false end
    for i=n+1,#verts do verts[i]=nil end
    local ok,m=pcall(love.graphics.newMesh,FORMAT,verts,"triangles","stream"); if not (ok and m) then return false end
    pcall(love.graphics.setBlendMode,blend,"alphamultiply")
    local began=Voxel3D.beginEffect and Voxel3D.beginEffect(sh)
    pcall(love.graphics.setDepthMode,"lequal",false)
    if not began then pcall(love.graphics.setShader,sh) end
    if not pcall(sh.send,sh,"vp","row",Voxel3D.vp) then pcall(sh.send,sh,"vp",Voxel3D.vp) end
    pcall(sh.send,sh,"horizonY",tonumber(origin[2]) or 0)
    pcall(sh.send,sh,"horizonClip",1.0)
    pcall(love.graphics.setColor,1,1,1,1); pcall(love.graphics.draw,m)
    if Voxel3D.endEffect then pcall(Voxel3D.endEffect) else pcall(love.graphics.setShader) end
    pcall(m.release,m); return true
  end
  local drewSun=drawOne(sunVerts,sn,"alpha")
  -- Moon is alpha-blended after the sun. During solar eclipse its dark phase
  -- therefore genuinely silhouettes the solar disc instead of adding light.
  local drewMoon=drawOne(moonVerts,mn,"alpha")
  pcall(love.graphics.setDepthMode,"lequal",true)
  if prev then pcall(love.graphics.setBlendMode,prev[1],prev[2]) end
  Celestial._lastDraw={hour=b.hour,sun=b.sun.above and true or false,moon=b.moon.above and true or false,sunDy=b.sun.dy,moonDy=b.moon.dy,moonPhase=b.moon.phaseName}
  return drewSun or drewMoon
end

local function projectOne(body,w,h,edge,Voxel3D)
  if not bodyVisible(body) then return nil end
  local x,y
  -- 8.1.67: when a voxel scene exists but celestial presentation is 2D, the
  -- disc is still a screen-space sprite, but its position must come from the
  -- real 3D camera basis. The old dx/dy -> screen shortcut ignored camera yaw
  -- and made the sun/moon appear glued to the player's camera.
  if Voxel3D then
    local ok,NS=pcall(V.require,"NightSky")
    if ok and NS and NS.projectDirection then
      local okp,px,py=pcall(NS.projectDirection,Voxel3D,body.dx or 0,body.dy or 0,body.dz or 0,w,h)
      if okp then x,y=px,py end
    end
  end
  if not x then
    local u=0.5+0.40*(body.dx or 0)
    local elevN=clamp01(body.dy or 0)
    local v=0.72-0.68*elevN
    if u<0.05 then u=0.05 elseif u>0.95 then u=0.95 end
    if v<0.04 then v=0.04 elseif v>0.78 then v=0.78 end
    x,y=u*w,v*edge
  end
  return {x=x,y=y,moon=body.kind=="moon",glowAmt=0,
    _wxKind=body.kind,_wxAlpha=body.alpha,_wxPhase=body.phase,_wxPhaseAngle=body.phaseAngle,
    _wxIllumination=body.illumination,_wxPhaseName=body.phaseName,_wxColor=body.color,
    _wxAltitudeDeg=body.altitudeDeg,_wxHorizonFraction=body.horizonFraction,_wxHaloStrength=body.haloStrength,
    _wxSolarEclipse=body.solarEclipse,_wxLunarEclipse=body.lunarEclipse}
end

function Celestial.projectBody(w,h,edge,cell,hour,Voxel3D)
  w=tonumber(w) or 160; h=tonumber(h) or 144; edge=tonumber(edge) or h*0.42
  local b=Celestial.bodies(hour)
  local s=projectOne(b.sun,w,h,edge,Voxel3D); if s then return s end
  return projectOne(b.moon,w,h,edge,Voxel3D)
end

function Celestial.projectBoth(w,h,edge,hour,Voxel3D)
  w=tonumber(w) or 160; h=tonumber(h) or 144; edge=tonumber(edge) or h*0.42
  local b=Celestial.bodies(hour)
  return projectOne(b.sun,w,h,edge,Voxel3D),projectOne(b.moon,w,h,edge,Voxel3D)
end

return Celestial
