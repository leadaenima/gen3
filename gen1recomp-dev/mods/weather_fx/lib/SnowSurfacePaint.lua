-- ============================================================================
-- WEATHER FX — VOXEL SNOW SURFACE REPAINT
-- 8.1.66: conformal, world-space snow coverage on the host's real terrain mesh.
-- ============================================================================
-- SnowPack remains the physical deposition/melt authority.  This module turns
-- its bounded radial impact field into a small world-space coverage texture and
-- immediately redraws the SAME host terrain mesh with a snow-only material
-- pass.  The original atlas, mesh, collision and map data are never modified.
-- Because the second pass uses the exact vertices the player already sees,
-- snow cannot hover above ledges/trees/props as an independent cap.
-- ============================================================================

local V = ...
local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
local PI2 = math.pi * 2

local P = {
  VERSION = "8.1.68",
  TEXEL_WORLD = 2,
  MIN_RADIUS = 96,
  MAX_RADIUS = 224,
  REBUILD_INTERVAL = 0.10,
  Y_MIN = -64,
  Y_RANGE = 256,
  _installed = false,
  _scene = nil,
  _sceneOutdoor = false,
  _pool = nil,
  _ctx = nil,
  _focusX = 0,
  _focusZ = 0,
  _radius = 0,
  _lastBuild = -1e9,
  _dirty = true,
  _active = 0,
  _draws = 0,
  _paintedFragments = 0,
}

local function clamp(v,a,b)
  v=tonumber(v) or 0
  if v<a then return a end
  if v>b then return b end
  return v
end

local function now()
  if love and love.timer and love.timer.getTime then
    local ok,t=pcall(love.timer.getTime)
    if ok and type(t)=="number" then return t end
  end
  return os.clock()
end

local function profileCode(profile,kind)
  profile=tostring(profile or ""):lower();kind=tostring(kind or ""):lower()
  if profile=="round" or kind=="tree" then return 0.82 end
  if profile=="thin" then return 0.58 end
  if kind=="raised" then return 0.38 end
  return 0.18
end

-- Detached mound geometry is useful only where snow really gains thickness on
-- a load-bearing horizontal field.  Scenery/ledges/trees are repainted on the
-- actual host mesh instead; drawing the old independent mound there is exactly
-- the floating-cap failure this release removes.
function P.usePhysicalBank(kind,class,profile)
  kind=tostring(kind or "ground"):lower()
  if kind=="ground" or kind=="grass" or kind=="ice" then return true end
  return false
end

function P.observeScene(state,outdoor)
  P._scene=state
  P._sceneOutdoor=(outdoor~=false)
end

function P.capture(ctx,pool,focusX,focusZ,radius)
  P._ctx=ctx
  P._pool=pool
  P._focusX=tonumber(focusX) or 0
  P._focusZ=tonumber(focusZ) or 0
  P._radius=clamp(radius or P.MIN_RADIUS,P.MIN_RADIUS,P.MAX_RADIUS)
  P._active=(pool and tonumber(pool.active)) or 0
  P._dirty=true
end

function P.clearCapture()
  P._ctx=nil;P._pool=nil;P._active=0;P._dirty=true
end

-- Pure-Lua coverage sampler used by tests/debug and by the texture rasterizer.
-- Returns coverage, impact/support height and profile code.  Overlap is summed
-- only when it belongs to the same top surface; a higher support wins over a
-- lower patch at the same X/Z, so snow beneath a tree cannot repaint the crown.
local function dirIndex(dx,dz)
  if abs(dx)+abs(dz)<1e-8 then return 1 end
  local a=atan2(dz,dx);if a<0 then a=a+PI2 end
  return (floor((a+math.pi/8)/(math.pi/4))%8)+1
end

function P.coverageAt(x,z,pool)
  pool=pool or P._pool
  local n=pool and tonumber(pool.active) or 0
  if n<=0 then return 0,0,0 end
  local cov,bestY,bestCode=0,nil,0
  for i=1,n do
    local px,pz=tonumber(pool.x[i]),tonumber(pool.z[i])
    local amount=tonumber(pool.amount[i]) or 0
    if px and pz and amount>0.001 then
      local dx,dz=x-px,z-pz
      local k=dirIndex(dx,dz)
      local r=tonumber(pool["r"..k] and pool["r"..k][i]) or tonumber(pool.size[i]) or 0
      if r>0.05 then
        local d2=dx*dx+dz*dz
        if d2<r*r then
          local q=sqrt(d2)/r
          local f=1-q*q;f=f*f
          local v=amount*f
          local sy=tonumber(pool.baseY[i]) or 0
          if bestY==nil or sy>bestY+0.55 then
            cov,bestY,bestCode=v,sy,profileCode(pool.profile and pool.profile[i],pool.kind and pool.kind[i])
          elseif abs(sy-bestY)<=0.55 then
            cov=min(1,cov+v)
            local code=profileCode(pool.profile and pool.profile[i],pool.kind and pool.kind[i])
            if code>bestCode then bestCode=code end
          end
        end
      end
    end
  end
  return min(1,cov),bestY or 0,bestCode
end

local SHADER = [[
#pragma language glsl3
varying highp vec3 wxSnowWorld;
varying float wxSnowShade;
#ifdef VERTEX
uniform mat4 vp;
uniform mat4 model;
uniform vec3 eye;
uniform float pull;
uniform vec3 curve;
attribute float VertexShade;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  wxSnowShade = abs(VertexShade);
  vec4 w = model * vertex_position;
  // Flat pre-curve world coordinates are the persistent SnowPack frame.
  wxSnowWorld = w.xyz;
  if (curve.z > 0.0) {
    vec2 cd = w.xz - curve.xy;
    w.y -= dot(cd, cd) * curve.z;
  }
  if (pull > 0.0) {
    w.xyz += normalize(eye - w.xyz) * pull;
  }
  return vp * w;
}
#endif
#ifdef PIXEL
uniform Image snowMap;
uniform vec2 snowOrigin;
uniform vec2 snowWorldSize;
uniform vec2 snowYDecode; // x=min, y=range
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 uv = (wxSnowWorld.xz - snowOrigin) / snowWorldSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) discard;
  vec4 s = Texel(snowMap, uv);
  float cov = s.r;
  if (cov <= 0.004) discard;
  float hi = floor(s.g * 255.0 + 0.5);
  float lo = floor(s.b * 255.0 + 0.5);
  float sy = snowYDecode.x + ((hi * 256.0 + lo) / 65535.0) * snowYDecode.y;
  // Profile channel widens the contact tolerance only for irregular real
  // scenery (tree/canopy voxel hulls).  Flat ledges remain tightly surface-bound.
  float tol = mix(0.72, 2.35, clamp(s.a, 0.0, 1.0));
  float surface = 1.0 - smoothstep(tol, tol + 0.70, abs(wxSnowWorld.y - sy));
  if (surface <= 0.002) discard;
  float whiten = clamp((cov - 0.012) * 1.42, 0.0, 0.985) * surface;
  if (whiten <= 0.002) discard;
  float lit = mix(0.82, 1.02, clamp(wxSnowShade, 0.0, 1.0));
  vec3 snow = vec3(0.945, 0.975, 1.0) * lit;
  return vec4(snow, whiten);
}
#endif
]]

-- Voxel Nexus 2.0.17's cinematic vegetation renderer intentionally cached the
-- host draw function before Weather FX loads, so those replacement tree meshes
-- do not flow through the terrain-mesh wrapper above.  The public companion API
-- gives us a better seam: a final opaque callback runs AFTER the cinematic
-- trees but BEFORE actors/water.  With the host's readable depth texture we
-- reconstruct the exact visible world point and whiten only upper tree/canopy
-- geometry covered by SnowPack.  This is geometry-aware screen composition,
-- not a flat weather overlay: the depth buffer decides the surface pixel.
local SCREEN_SHADER = [[
#pragma language glsl3
uniform highp Image depthTex;
uniform mat4 invVP;
uniform vec3 curve;
uniform Image snowMap;
uniform vec2 snowOrigin;
uniform vec2 snowWorldSize;
uniform vec2 snowYDecode;
uniform vec2 screenSize;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 uv = sc / screenSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) discard;
  float dz = Texel(depthTex, uv).r;
  if (dz >= 0.999999) discard;
  vec4 clip = vec4(uv * 2.0 - 1.0, dz * 2.0 - 1.0, 1.0);
  vec4 world = invVP * clip;
  if (abs(world.w) <= 1e-7) discard;
  world.xyz /= world.w;
  // Undo only the host's Y-only curved-world displacement. X/Z are unchanged.
  if (curve.z > 0.0) {
    vec2 cd = world.xz - curve.xy;
    world.y += dot(cd, cd) * curve.z;
  }
  vec2 suv = (world.xz - snowOrigin) / snowWorldSize;
  if (suv.x < 0.0 || suv.y < 0.0 || suv.x >= 1.0 || suv.y >= 1.0) discard;
  vec4 s = Texel(snowMap, suv);
  // The depth companion covers cinematic replacement geometry that bypasses
  // Voxel3D.draw after Weather FX installs. 8.1.66 handled only tree crowns;
  // Voxel Nexus also replaces authored ledges with separate stone meshes. Use
  // the SnowPack profile channel to select the real visible surface family.
  if (s.r <= 0.004) discard;
  float hi = floor(s.g * 255.0 + 0.5);
  float lo = floor(s.b * 255.0 + 0.5);
  float sy = snowYDecode.x + ((hi * 256.0 + lo) / 65535.0) * snowYDecode.y;
  float mask = 0.0;
  if (s.a >= 0.70) {
    // Cinematic trees are taller than stock collision hulls. Whiten their real
    // upper geometry while leaving trunks/lower terrain untouched.
    mask = smoothstep(sy + 2.0, sy + 10.0, world.y);
  } else if (s.a >= 0.30) {
    // Raised/ledge geometry: cinematic boulder-wall ledges sit slightly below
    // the stock authored top plane and have irregular stone tops. Accept only
    // the upper ~3 world units around that support, never an independent cap.
    float nearTop = 1.0 - smoothstep(0.55, 3.25, abs(world.y - sy));
    float upper = smoothstep(sy - 3.35, sy - 0.20, world.y);
    mask = nearTop * upper;
  } else {
    discard; // ground/grass/ice are already handled by the exact terrain mesh
  }
  float whiten = clamp((s.r - 0.010) * 1.34, 0.0, 0.96) * mask;
  if (whiten <= 0.002) discard;
  return vec4(vec3(0.95, 0.98, 1.0), whiten);
}
]]

local function invert4(m,inv,a)
  if type(m)~="table" or #m<16 then return nil end
  a=a or {};inv=inv or {}
  for i=1,16 do a[i]=tonumber(m[i]) or 0 end
  inv[1]=a[6]*a[11]*a[16]-a[6]*a[12]*a[15]-a[10]*a[7]*a[16]+a[10]*a[8]*a[15]+a[14]*a[7]*a[12]-a[14]*a[8]*a[11]
  inv[2]=-a[2]*a[11]*a[16]+a[2]*a[12]*a[15]+a[10]*a[3]*a[16]-a[10]*a[4]*a[15]-a[14]*a[3]*a[12]+a[14]*a[4]*a[11]
  inv[3]=a[2]*a[7]*a[16]-a[2]*a[8]*a[15]-a[6]*a[3]*a[16]+a[6]*a[4]*a[15]+a[14]*a[3]*a[8]-a[14]*a[4]*a[7]
  inv[4]=-a[2]*a[7]*a[12]+a[2]*a[8]*a[11]+a[6]*a[3]*a[12]-a[6]*a[4]*a[11]-a[10]*a[3]*a[8]+a[10]*a[4]*a[7]
  inv[5]=-a[5]*a[11]*a[16]+a[5]*a[12]*a[15]+a[9]*a[7]*a[16]-a[9]*a[8]*a[15]-a[13]*a[7]*a[12]+a[13]*a[8]*a[11]
  inv[6]=a[1]*a[11]*a[16]-a[1]*a[12]*a[15]-a[9]*a[3]*a[16]+a[9]*a[4]*a[15]+a[13]*a[3]*a[12]-a[13]*a[4]*a[11]
  inv[7]=-a[1]*a[7]*a[16]+a[1]*a[8]*a[15]+a[5]*a[3]*a[16]-a[5]*a[4]*a[15]-a[13]*a[3]*a[8]+a[13]*a[4]*a[7]
  inv[8]=a[1]*a[7]*a[12]-a[1]*a[8]*a[11]-a[5]*a[3]*a[12]+a[5]*a[4]*a[11]+a[9]*a[3]*a[8]-a[9]*a[4]*a[7]
  inv[9]=a[5]*a[10]*a[16]-a[5]*a[12]*a[14]-a[9]*a[6]*a[16]+a[9]*a[8]*a[14]+a[13]*a[6]*a[12]-a[13]*a[8]*a[10]
  inv[10]=-a[1]*a[10]*a[16]+a[1]*a[12]*a[14]+a[9]*a[2]*a[16]-a[9]*a[4]*a[14]-a[13]*a[2]*a[12]+a[13]*a[4]*a[10]
  inv[11]=a[1]*a[6]*a[16]-a[1]*a[8]*a[14]-a[5]*a[2]*a[16]+a[5]*a[4]*a[14]+a[13]*a[2]*a[8]-a[13]*a[4]*a[6]
  inv[12]=-a[1]*a[6]*a[12]+a[1]*a[8]*a[10]+a[5]*a[2]*a[12]-a[5]*a[4]*a[10]-a[9]*a[2]*a[8]+a[9]*a[4]*a[6]
  inv[13]=-a[5]*a[10]*a[15]+a[5]*a[11]*a[14]+a[9]*a[6]*a[15]-a[9]*a[7]*a[14]-a[13]*a[6]*a[11]+a[13]*a[7]*a[10]
  inv[14]=a[1]*a[10]*a[15]-a[1]*a[11]*a[14]-a[9]*a[2]*a[15]+a[9]*a[3]*a[14]+a[13]*a[2]*a[11]-a[13]*a[3]*a[10]
  inv[15]=-a[1]*a[6]*a[15]+a[1]*a[7]*a[14]+a[5]*a[2]*a[15]-a[5]*a[3]*a[14]-a[13]*a[2]*a[7]+a[13]*a[3]*a[6]
  inv[16]=a[1]*a[6]*a[11]-a[1]*a[7]*a[10]-a[5]*a[2]*a[11]+a[5]*a[3]*a[10]+a[9]*a[2]*a[7]-a[9]*a[3]*a[6]
  local det=a[1]*inv[1]+a[2]*inv[5]+a[3]*inv[9]+a[4]*inv[13]
  if abs(det)<1e-10 then return nil end
  det=1/det;for i=1,16 do inv[i]=inv[i]*det end
  return inv
end
P._invert4=function(m) return invert4(m) end

-- 8.1.79: persistent CPU/uniform scratch removes per-frame tables from the
-- snow repaint and cinematic depth companion while preserving public inversion semantics.
P._invInputScratch={}
P._invOutputScratch={}
P._radiiScratch={}
local EYE_FALLBACK={0,40,0}
local PAINT_CURVE={0,0,0}
local PAINT_ORIGIN={0,0}
local PAINT_WORLD_SIZE={1,1}
local PAINT_Y_DECODE={P.Y_MIN,P.Y_RANGE}
local PAINT_SCREEN_SIZE={1,1}

local function releaseGPU()
  if P._image and P._image.release then pcall(P._image.release,P._image) end
  if P._data and P._data.release then pcall(P._data.release,P._data) end
  if P._shader and P._shader.release then pcall(P._shader.release,P._shader) end
  if P._screenShader and P._screenShader.release then pcall(P._screenShader.release,P._screenShader) end
  P._image,P._data,P._shader,P._screenShader=nil,nil,nil,nil
  P._w,P._h=nil,nil
  P._cov,P._height,P._code,P._touched={},{},{},{}
  P._touchedN=0
end

local function ensureShader()
  if P._shader then return true end
  if not (love and love.graphics and love.graphics.newShader) then return false end
  local ok,sh=pcall(love.graphics.newShader,SHADER)
  if not ok or not sh then return false end
  P._shader=sh
  return true
end

local function ensureScreenShader()
  if P._screenShader then return true end
  if not (love and love.graphics and love.graphics.newShader) then return false end
  local ok,sh=pcall(love.graphics.newShader,SCREEN_SHADER)
  if not ok or not sh then return false end
  P._screenShader=sh
  return true
end

local function ensureTexture(w,h)
  if P._image and P._data and P._w==w and P._h==h then return true end
  if not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then return false end
  if P._image or P._data then releaseGPU(); if not ensureShader() then return false end end
  local okD,data=pcall(love.image.newImageData,w,h)
  if not okD or not data then return false end
  local okI,img=pcall(love.graphics.newImage,data)
  if not okI or not img then if data.release then pcall(data.release,data) end;return false end
  pcall(img.setFilter,img,"nearest","nearest")
  P._data,P._image,P._w,P._h=data,img,w,h
  P._cov,P._height,P._code,P._touched={},{},{},{}
  P._touchedN=0
  return true
end

local function encodeHeight(y)
  local t=clamp(((tonumber(y) or 0)-P.Y_MIN)/P.Y_RANGE,0,1)
  local q=floor(t*65535+0.5)
  local hi=floor(q/256);local lo=q-hi*256
  return hi/255,lo/255
end

local function clearTouched()
  local data=P._data
  for j=1,(P._touchedN or 0) do
    local idx=P._touched[j]
    if idx then
      local x=(idx-1)%P._w;local y=floor((idx-1)/P._w)
      P._cov[idx],P._height[idx],P._code[idx]=nil,nil,nil
      data:setPixel(x,y,0,0,0,0)
      P._touched[j]=nil
    end
  end
  P._touchedN=0
end

local function writeTexel(ix,iz,v,sy,code)
  if ix<0 or iz<0 or ix>=P._w or iz>=P._h or v<=0.001 then return end
  local idx=iz*P._w+ix+1
  local oldY=P._height[idx]
  if oldY==nil then
    P._touchedN=P._touchedN+1;P._touched[P._touchedN]=idx
    P._height[idx]=sy;P._cov[idx]=min(1,v);P._code[idx]=code
  elseif sy>oldY+0.55 then
    P._height[idx]=sy;P._cov[idx]=min(1,v);P._code[idx]=code
  elseif abs(sy-oldY)<=0.55 then
    P._cov[idx]=min(1,(P._cov[idx] or 0)+v)
    P._code[idx]=max(P._code[idx] or 0,code)
  else
    return
  end
  local g,b=encodeHeight(P._height[idx])
  P._data:setPixel(ix,iz,P._cov[idx] or 0,g,b,P._code[idx] or 0)
end

local function rasterize()
  local pool=P._pool;local n=pool and tonumber(pool.active) or 0
  clearTouched()
  if n<=0 then return true end
  local ox,oz=P._originX,P._originZ;local tw=P.TEXEL_WORLD
  for i=1,n do
    local amount=tonumber(pool.amount[i]) or 0
    local px,pz=tonumber(pool.x[i]),tonumber(pool.z[i])
    if amount>0.001 and px and pz then
      local radii=P._radiiScratch
      radii[1],radii[2],radii[3],radii[4]=pool.r1,pool.r2,pool.r3,pool.r4
      radii[5],radii[6],radii[7],radii[8]=pool.r5,pool.r6,pool.r7,pool.r8
      local maxR=tonumber(pool.size[i]) or 0
      for k=1,8 do local rk=radii[k];maxR=max(maxR,tonumber(rk and rk[i]) or 0) end
      local isTree=tostring(pool.kind and pool.kind[i] or ""):lower()=="tree" or tostring(pool.profile and pool.profile[i] or ""):lower()=="round"
      local visualScale=isTree and 2.15 or 1.0
      local visualMaxR=min(16,maxR*visualScale)
      if visualMaxR>0.05 then
        local x0=max(0,floor((px-visualMaxR-ox)/tw));local x1=min(P._w-1,floor((px+visualMaxR-ox)/tw))
        local z0=max(0,floor((pz-visualMaxR-oz)/tw));local z1=min(P._h-1,floor((pz+visualMaxR-oz)/tw))
        local sy=tonumber(pool.baseY[i]) or 0
        local code=profileCode(pool.profile and pool.profile[i],pool.kind and pool.kind[i])
        for iz=z0,z1 do
          local wz=oz+(iz+0.5)*tw
          for ix=x0,x1 do
            local wx=ox+(ix+0.5)*tw
            local dx,dz=wx-px,wz-pz
            local k=dirIndex(dx,dz)
            local rk=radii[k]
            local r=(tonumber(rk and rk[i]) or maxR)*visualScale
            r=min(16,r)
            if r>0.05 then
              local d2=dx*dx+dz*dz
              if d2<r*r then
                local q=sqrt(d2)/r;local f=1-q*q;f=f*f
                writeTexel(ix,iz,amount*f,sy,code)
              end
            end
          end
        end
      end
    end
  end
  return true
end

local function rebuildCoverage(force)
  if not (P._sceneOutdoor and P._pool) then return false end
  -- 8.2.3: capture data is immutable between SnowPack staging refreshes. Do
  -- not rerasterize/re-upload the same coverage texture every 100 ms simply
  -- because terrain was drawn again. Ground snow changes slowly; WorldPrecip
  -- marks this dirty only when the staged bank set/focus window is refreshed.
  if not force and not P._dirty and P._image then return true end
  local t=now()
  if not force and t-P._lastBuild<P.REBUILD_INTERVAL then return P._image~=nil end
  P._lastBuild=t
  local radius=clamp(P._radius,P.MIN_RADIUS,P.MAX_RADIUS)
  local tw=P.TEXEL_WORLD
  local side=2*radius
  local w=max(8,floor(side/tw+0.5));local h=w
  -- Snap origin to the texel lattice so camera sub-pixel motion never makes the
  -- snow paint swim across a stationary terrain mesh.
  P._originX=floor((P._focusX-radius)/tw)*tw
  P._originZ=floor((P._focusZ-radius)/tw)*tw
  P._worldW,P._worldH=w*tw,h*tw
  if not ensureShader() or not ensureTexture(w,h) then return false end
  -- Per-texel protected calls were one of the largest Lua costs during active
  -- accumulation. Protect the raster as one unit instead; setPixel itself stays exact.
  local okRaster=pcall(rasterize)
  if not okRaster then return false end
  local ok=pcall(P._image.replacePixels,P._image,P._data)
  if not ok then return false end
  P._dirty=false
  return true
end

local function isTerrainMesh(mesh)
  local state=P._scene;local C=P._ChunkMesher
  if not (mesh and state and C and C.peek) then return false end
  local function hit(map)
    if not map then return false end
    local ok,a=pcall(C.peek,map,false);if ok and a==mesh then return true end
    local ok2,b=pcall(C.peek,map,true);return ok2 and b==mesh
  end
  if hit(state.map) then return true end
  for _,nb in ipairs(state.neighbors or {}) do if nb and hit(nb.map) then return true end end
  return false
end
P._isTerrainMesh=isTerrainMesh

local IDENTITY={1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}

local function paint(mesh,model,pull)
  if (P._active or 0)<=0 or not P._sceneOutdoor then return false end
  if not rebuildCoverage(false) or not P._shader or not P._image then return false end
  local Voxel3D=P._Voxel3D
  if not (Voxel3D and Voxel3D.vp and love and love.graphics and love.graphics.draw) then return false end
  local sh=P._shader
  local dm=model or IDENTITY
  local ok=true
  ok=pcall(sh.send,sh,"vp","row",Voxel3D.vp) and ok
  pcall(sh.send,sh,"model","row",dm)
  PAINT_CURVE[1],PAINT_CURVE[2],PAINT_CURVE[3]=Voxel3D.curveX or 0,Voxel3D.curveZ or 0,Voxel3D.curveK or 0
  PAINT_ORIGIN[1],PAINT_ORIGIN[2]=P._originX or 0,P._originZ or 0
  PAINT_WORLD_SIZE[1],PAINT_WORLD_SIZE[2]=P._worldW or 1,P._worldH or 1
  pcall(sh.send,sh,"eye",Voxel3D.eye or EYE_FALLBACK)
  pcall(sh.send,sh,"pull",tonumber(pull) or 0)
  pcall(sh.send,sh,"curve",PAINT_CURVE)
  pcall(sh.send,sh,"snowMap",P._image)
  pcall(sh.send,sh,"snowOrigin",PAINT_ORIGIN)
  pcall(sh.send,sh,"snowWorldSize",PAINT_WORLD_SIZE)
  pcall(sh.send,sh,"snowYDecode",PAINT_Y_DECODE)
  local okS=pcall(love.graphics.setShader,sh)
  if not okS then return false end
  pcall(love.graphics.setDepthMode,"lequal",false)
  pcall(love.graphics.setColor,1,1,1,1)
  local drew=pcall(love.graphics.draw,mesh)
  -- Restore the exact scene family (including Voxel Grid variant) through the
  -- host's own state reset instead of guessing which shader was active.
  pcall(love.graphics.setDepthMode,"lequal",true)
  if Voxel3D.lighting then pcall(Voxel3D.lighting,true) else pcall(love.graphics.setShader) end
  pcall(love.graphics.setColor,1,1,1,1)
  if drew then P._draws=(P._draws or 0)+1 end
  return drew and true or false
end

local function paintCinematicTreesFromDepth()
  if (P._active or 0)<=0 or not P._sceneOutdoor then return false end
  local Voxel3D=P._Voxel3D
  if not (Voxel3D and Voxel3D.beginWater and Voxel3D.endWater and Voxel3D.vp) then return false end
  if not rebuildCoverage(false) or not ensureScreenShader() then return false end
  local inv=invert4(Voxel3D.vp,P._invOutputScratch,P._invInputScratch);if not inv then return false end
  local w,h=0,0
  if Voxel3D.size then local ok,a,b=pcall(Voxel3D.size);if ok then w,h=tonumber(a) or 0,tonumber(b) or 0 end end
  if w<=0 or h<=0 then return false end
  local okBW,mirror,depth=pcall(Voxel3D.beginWater)
  if not okBW or not depth then if okBW then pcall(Voxel3D.endWater) end;return false end
  local sh=P._screenShader
  pcall(sh.send,sh,"depthTex",depth)
  pcall(sh.send,sh,"invVP","row",inv)
  PAINT_CURVE[1],PAINT_CURVE[2],PAINT_CURVE[3]=Voxel3D.curveX or 0,Voxel3D.curveZ or 0,Voxel3D.curveK or 0
  PAINT_ORIGIN[1],PAINT_ORIGIN[2]=P._originX or 0,P._originZ or 0
  PAINT_WORLD_SIZE[1],PAINT_WORLD_SIZE[2]=P._worldW or 1,P._worldH or 1
  PAINT_SCREEN_SIZE[1],PAINT_SCREEN_SIZE[2]=w,h
  pcall(sh.send,sh,"curve",PAINT_CURVE)
  pcall(sh.send,sh,"snowMap",P._image)
  pcall(sh.send,sh,"snowOrigin",PAINT_ORIGIN)
  pcall(sh.send,sh,"snowWorldSize",PAINT_WORLD_SIZE)
  pcall(sh.send,sh,"snowYDecode",PAINT_Y_DECODE)
  pcall(sh.send,sh,"screenSize",PAINT_SCREEN_SIZE)
  local drew=false
  local okS=pcall(love.graphics.setShader,sh)
  if okS then
    pcall(love.graphics.setColor,1,1,1,1)
    local okR=pcall(love.graphics.rectangle,"fill",0,0,w,h)
    drew=okR and true or false
  end
  pcall(Voxel3D.endWater)
  if drew then P._screenDraws=(P._screenDraws or 0)+1 end
  P._screenHealthy=drew
  return drew
end
P.paintCinematicTreesFromDepth=paintCinematicTreesFromDepth

local function installCompanion(host)
  if P._companionHandle or not host or not host.exports then return P._companionHandle~=nil end
  local api=host.exports.voxel_companion
  if type(api)~="table" or api.api~=1 or type(api.register)~="function" then return false end
  local spec={api=1,id="weather_fx.snow_surface_repaint",name="Weather FX Snow Surface Repaint",version=P.VERSION,
    priority=99990,requires={"world_snapshot","render_phases"},render={
      opaque_after_terrain=function(ctx)
        -- Provider order is ascending. This intentionally runs after Voxel
        -- Nexus' cinematic terrain/tree providers and before actors/water.
        paintCinematicTreesFromDepth()
      end,
    }}
  local ok,h=pcall(api.register,spec)
  if ok and h then P._companionHandle=h;return true end
  return false
end

function P.install(hostLib,Voxel3D,host)
  if P._installed then return true end
  if not (hostLib and type(hostLib.require)=="function" and Voxel3D and type(Voxel3D.draw)=="function") then return false end
  local ok,C=pcall(hostLib.require,"ChunkMesher")
  if not ok or not C then return false end
  P._ChunkMesher=C;P._Voxel3D=Voxel3D
  P._origDraw=Voxel3D.draw
  local orig=P._origDraw
  P._wrappedDraw=function(mesh,texture,model,pull,sunModel)
    local r1,r2,r3,r4,r5=orig(mesh,texture,model,pull,sunModel)
    if P._sceneOutdoor and (P._active or 0)>0 and isTerrainMesh(mesh) then
      pcall(paint,mesh,model,pull)
    end
    return r1,r2,r3,r4,r5
  end
  Voxel3D.draw=P._wrappedDraw
  P._installed=true
  P._host=host
  installCompanion(host)
  return true
end

function P.invalidate()
  P._scene=nil;P._sceneOutdoor=false;P._pool=nil;P._ctx=nil;P._active=0;P._dirty=true
  P._lastBuild=-1e9
  if P._data then clearTouched() end
end

function P.uninstall()
  if P._installed and P._Voxel3D and P._Voxel3D.draw==P._wrappedDraw and P._origDraw then
    P._Voxel3D.draw=P._origDraw
  end
  if P._companionHandle and type(P._companionHandle.dispose)=="function" then pcall(P._companionHandle.dispose,P._companionHandle,"weather-fx-uninstall") end
  P._companionHandle=nil;P._host=nil
  P._installed=false;P._wrappedDraw=nil;P._origDraw=nil;P._ChunkMesher=nil;P._Voxel3D=nil
  releaseGPU();P.invalidate()
end

function P.debug()
  return {installed=P._installed,active=P._active or 0,draws=P._draws or 0,
    texture=P._image~=nil,width=P._w or 0,height=P._h or 0,screenCompanion=P._companionHandle~=nil,screenDraws=P._screenDraws or 0,screenHealthy=P._screenHealthy==true,
    originX=P._originX,originZ=P._originZ,worldW=P._worldW,worldH=P._worldH}
end

return P
