-- Weather FX-owned voxel shadow map.
--
-- Voxel hosts still submit their normal terrain/building/tree/actor caster pass
-- through the public ShadowMap table, but Weather FX owns the texture,
-- projection, recast policy and GPU state.  This keeps compatibility without
-- inheriting the host's coarse 1/128 light cache or light-space texel snapping.
local V = ...
local M = {}

local VERSION = "WeatherShadowMap/1"
local Z01 = {1,0,0,0, 0,1,0,0, 0,0,0.5,0.5, 0,0,0,1}
local IDENTITY = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
local DEPTH_FORMATS = {"depth24", "depth24stencil8", "depth32f", "depth16"}

-- Same two-channel packed depth contract consumed by the voxel hosts' existing
-- receiver shaders.  We replace the producer, not every host material shader.
local WRITER = [[
#pragma language glsl3
varying float vDepth;
uniform mat4 lightVP;
uniform mat4 model;
uniform float sprite;
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 c = lightVP * (model * VertexPosition);
    vDepth = c.z;
    return c;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    if (Texel(tex, uv).a < 0.5) discard;
    float d = clamp(vDepth, 0.0, 1.0) * 255.0;
    return vec4(floor(d) / 255.0, fract(d), sprite, 1.0);
}
#endif
]]

local function pcallv(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function clamp(v, a, b)
  v = tonumber(v) or a
  if v < a then return a end
  if v > b then return b end
  return v
end

local function tierName()
  local ok, Q = pcall(V.require, "Quality")
  if ok and Q and type(Q.tier) == "function" then
    local ok2, t = pcall(Q.tier)
    if ok2 and t ~= nil then return tostring(t):lower() end
  end
  return "high"
end

local function targetForTier(t)
  if t == "high" or t == "max" or t == "ultra" then return 0.24 end
  if t == "medium" or t == "med" then return 0.32 end
  return 0.45
end

-- Recast by actual maximum-caster endpoint drift rather than quantised shear.
-- These values are sub-pixel in world space but avoid rendering a full shadow
-- map every frame on weak devices when the sun has barely moved.
local function driftForTier(t)
  if t == "high" or t == "max" or t == "ultra" then return 0.04 end
  if t == "medium" or t == "med" then return 0.07 end
  if t == "potato" then return 0.16 end
  return 0.12
end

-- 8.1.79: immutable clip-to-texture transforms and fit vectors are cached.
-- Shadow quality/projection math is unchanged; only transient table churn is removed.
local TO_UNIT_POS={0.5,0,0,0.5, 0,0.5,0,0.5, 0,0,1,0, 0,0,0,1}
local TO_UNIT_NEG={0.5,0,0,0.5, 0,-0.5,0,0.5, 0,0,1,0, 0,0,0,1}
local FIT_EYE={0,0,0}
local FIT_DIR={0,-1,0}
local FIT_UP={0,0,-1}
local function toUnit(sign)
  return sign == -1 and TO_UNIT_NEG or TO_UNIT_POS
end

local function transform(m, x, y, z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],
         m[5]*x+m[6]*y+m[7]*z+m[8],
         m[9]*x+m[10]*y+m[11]*z+m[12]
end

-- Current VoxelScene signatures put KX/KZ in fields 6/7. Remove only those
-- fields when the prefix is demonstrably numeric; otherwise use the complete
-- signature. This lets Weather FX own light invalidation while preserving every
-- geometry/camera/player-model invalidation the host already knows about.
local function normaliseSignature(sig)
  if type(sig) ~= "string" then return sig end
  local commas, from = {}, 1
  for i = 1, 7 do
    local p = sig:find(",", from, true)
    if not p then return sig end
    commas[i], from = p, p + 1
  end
  local fields, s = {}, 1
  for i = 1, 7 do
    fields[i] = sig:sub(s, commas[i]-1)
    s = commas[i]+1
  end
  for i = 1, 7 do
    if tonumber(fields[i]) == nil then return sig end
  end
  return sig:sub(1, commas[5]-1) .. "," .. sig:sub(commas[7]+1)
end
M.normaliseSignature = normaliseSignature

local function sanitizeSizes(src)
  local out, seen = {}, {}
  if type(src) == "table" then
    for _, v in ipairs(src) do
      local n = math.floor(tonumber(v) or 0)
      if n >= 256 and n <= 4096 and not seen[n] then
        seen[n] = true; out[#out+1] = n
      end
    end
  end
  if #out == 0 then out = {1024, 1536, 2048} end
  table.sort(out)
  return out
end

function M.install(hostLib, ShadowMap)
  if type(hostLib) ~= "table" or type(hostLib.require) ~= "function" or type(ShadowMap) ~= "table" then
    return false, "missing-host-shadow-api"
  end
  if ShadowMap._wxOwned and ShadowMap._wxEngineVersion == VERSION then return true end

  local okM, Mat4 = pcall(hostLib.require, "Mat4")
  if not okM or not (Mat4 and Mat4.lookAt and Mat4.ortho and Mat4.mul and Mat4.scale) then
    return false, "missing-mat4"
  end
  local okVS, VoxelState = pcall(hostLib.require, "VoxelState")
  if not okVS or not VoxelState then
    okVS, VoxelState = pcall(hostLib.require, "Voxel")
  end
  if not okVS or not VoxelState then return false, "missing-voxel-state" end

  local okPC, PixelCanvas = pcall(hostLib.require, "PixelCanvas")
  if not okPC then PixelCanvas = nil end

  -- love is sandboxed in Gen1Recomp. graphics/image are permitted capabilities;
  -- never probe forbidden fields such as love.system/filesystem/thread.
  local L = rawget(_G, "love")
  local lg = L and L.graphics
  if not lg or type(lg.newShader) ~= "function" or type(lg.newCanvas) ~= "function" then
    return false, "love-graphics-unavailable"
  end

  if ShadowMap._wxOwned and type(ShadowMap.invalidate) == "function" then
    pcall(ShadowMap.invalidate)
  end

  local state = {
    shader=nil, shaderTried=false, blank=nil,
    canvas=nil, depth=nil, res=nil,
    ready=false, drawing=false, fault=false,
    lastSig=nil, committedKX=nil, committedKZ=nil,
    pendingKX=nil, pendingKZ=nil, vSign=tonumber(ShadowMap.vSign),
    restore=nil, implicitDepth=false, spriteMode=nil, modelIdentity=false,
  }
  local sizes = sanitizeSizes(ShadowMap.SIZES)
  local HEIGHT = tonumber(ShadowMap.HEIGHT) or 160
  local BIAS = tonumber(ShadowMap.BIAS) or 0.5
  local SLOPE = tonumber(ShadowMap.SLOPE) or 3.1
  local FAR_CAP = tonumber(ShadowMap.FAR_CAP) or 2.5
  local SNUG = tonumber(ShadowMap.SNUG) or 0.9

  local function shadowsOff()
    local ok, S = pcall(hostLib.require, "Shadows")
    if ok and S and type(S.off) == "function" then
      local ok2, off = pcall(S.off)
      return ok2 and off and true or false
    end
    return false
  end

  local function shader()
    if state.shaderTried then return state.shader end
    state.shaderTried = true
    local ok, sh = pcall(lg.newShader, WRITER)
    if ok then state.shader = sh end
    return state.shader
  end

  local function release(obj)
    if obj and type(obj.release) == "function" then pcall(obj.release, obj) end
  end

  local function pixelCanvasNew(w,h,opts)
    if not (PixelCanvas and type(PixelCanvas.new)=="function") then return nil end
    local ok,a,b=pcall(PixelCanvas.new,w,h,opts)
    if not ok then return nil end
    -- PixelCanvas.new in current voxel hosts returns pcall's (ok, canvas);
    -- tolerate direct-return implementations too for older companions.
    if type(a)=="boolean" then return a and b or nil end
    return a
  end

  local function newColor(res)
    local pc = pixelCanvasNew(res,res)
    if pc then return pc end
    local ok, c = pcall(lg.newCanvas, res, res, {dpiscale=1})
    if ok then return c end
    ok, c = pcall(lg.newCanvas, res, res)
    return ok and c or nil
  end

  local function newDepth(res)
    for _, format in ipairs(DEPTH_FORMATS) do
      local c
      c = pixelCanvasNew(res,res,{format=format, readable=false})
      if c then return c end
      local ok; ok, c = pcall(lg.newCanvas, res, res, {format=format, readable=false, dpiscale=1})
      if ok and c then return c end
    end
    return nil
  end

  local function chooseResolution(extent)
    local target = targetForTier(tierName())
    local wanted = sizes[#sizes]
    for _, n in ipairs(sizes) do
      if extent / n <= target then wanted = n; break end
    end
    -- Grow only during a live session. Sun angle / viewport changes can ask for
    -- more precision, but we never release a larger map merely because the next
    -- frame could fit a smaller rung. This removes resize churn and frame spikes.
    if state.res and state.res > wanted then wanted = state.res end
    return wanted, target
  end

  local function ensureCanvas(wanted)
    if state.canvas and state.res and state.res >= wanted then return state.canvas, state.res end
    local c = newColor(wanted)
    if not c then
      if state.canvas then return state.canvas, state.res end
      return nil
    end
    local d = newDepth(wanted)
    local oldC, oldD = state.canvas, state.depth
    state.canvas, state.depth, state.res = c, d, wanted
    state.ready = false
    release(oldC); release(oldD)
    return c, wanted
  end

  local function blankTexture()
    if state.blank then return state.blank end
    local li = L and L.image
    if li and type(li.newImageData) == "function" and type(lg.newImage) == "function" then
      local ok, im = pcall(li.newImageData, 1, 1)
      if ok and im then
        pcall(im.setPixel, im, 0, 0, 1,1,1,1)
        local ok2, tex = pcall(lg.newImage, im)
        if ok2 then state.blank = tex end
        -- newImage owns its GPU copy; the CPU-side ImageData is no longer
        -- needed after upload and can be released immediately on capable hosts.
        if type(im.release)=="function" then pcall(im.release,im) end
      end
    end
    if not state.blank then
      local c=newColor(1)
      if c then
        local r={}
        if type(lg.getCanvas)=="function" then pcall(function() r.canvas=lg.getCanvas() end) end
        local ok=pcall(function() lg.setCanvas(c); lg.clear(1,1,1,1); lg.setCanvas() end)
        if r.canvas then pcall(lg.setCanvas,r.canvas) end
        if ok then state.blank=c else release(c) end
      end
    end
    return state.blank
  end

  local function captureGraphics()
    local r = {}
    if type(lg.getShader) == "function" then pcall(function() r.shader=lg.getShader() end) end
    if type(lg.getCanvas) == "function" then pcall(function() r.canvas=lg.getCanvas() end) end
    if type(lg.getDepthMode) == "function" then pcall(function() r.depthCompare,r.depthWrite=lg.getDepthMode() end) end
    if type(lg.getMeshCullMode) == "function" then pcall(function() r.cull=lg.getMeshCullMode() end) end
    if type(lg.getBlendMode) == "function" then pcall(function() r.blend,r.alpha=lg.getBlendMode() end) end
    if type(lg.getColor) == "function" then pcall(function() r.r,r.g,r.b,r.a=lg.getColor() end) end
    return r
  end

  local function restoreGraphics(r)
    r = r or {}
    pcall(lg.setShader, r.shader)
    if type(lg.setDepthMode) == "function" then
      if r.depthCompare ~= nil then pcall(lg.setDepthMode, r.depthCompare, r.depthWrite)
      else pcall(lg.setDepthMode) end
    end
    if type(lg.setMeshCullMode) == "function" then pcall(lg.setMeshCullMode, r.cull or "none") end
    if r.canvas then pcall(lg.setCanvas, r.canvas) else pcall(lg.setCanvas) end
    if r.blend then pcall(lg.setBlendMode, r.blend, r.alpha) end
    if r.r then pcall(lg.setColor, r.r,r.g,r.b,r.a) end
  end

  local function qCamera(v)
    -- 1/16 world-pixel anchor: far below the old 1/4 signature step and not
    -- derived from the rotating light, so camera stabilisation cannot reverse
    -- a continuously moving solar projection.
    return math.floor((tonumber(v) or 0)*16 + 0.5) / 16
  end

  local function groundReach(vh)
    local a = tonumber(VoxelState.angle) or 0
    local cap = FAR_CAP * vh
    local focal = tonumber(VoxelState.FOCAL) or 1.0
    if focal <= 0 then focal = 1.0 end
    local half = math.atan(1/(2*focal))
    local below = (math.pi/2-a)-half
    if below <= 0.02 then return cap end
    local dist = focal*vh
    local horizon = dist*math.cos(a)/math.tan(below)
    return math.max(vh/2, math.min(cap, horizon-dist*math.sin(a)))
  end

  local function requestedDirection()
    return tonumber(ShadowMap.KX) or 0, tonumber(ShadowMap.KZ) or 0
  end

  local function fit(cx, cy, vw, vh, res)
    cx,cy = qCamera(cx),qCamera(cy)
    vw,vh = math.max(1,tonumber(vw) or 1),math.max(1,tonumber(vh) or 1)
    local kx,kz = requestedDirection()
    local dx,dy,dz = kx,-1,kz
    local len = math.sqrt(dx*dx+dy*dy+dz*dz); if len < 1e-9 then len=1 end
    FIT_DIR[1],FIT_DIR[2],FIT_DIR[3]=dx/len,dy/len,dz/len
    local view = Mat4.lookAt(FIT_EYE,FIT_DIR,FIT_UP)
    local reach = HEIGHT*math.max(math.abs(kx),math.abs(kz))+24
    local north = groundReach(vh)
    local spread = north*0.5
    local x0,x1=cx-vw/2-spread,cx+vw/2+spread+reach
    local y0,y1=-32,HEIGHT
    local z0,z1=cy-north,cy+vh/2+reach
    local l,r,b,t,zn,zf
    -- Exact same eight fit corners as 8.1.78, without three temporary arrays/ipairs.
    for xi=0,1 do
      local x=xi==0 and x0 or x1
      for yi=0,1 do
        local y=yi==0 and y0 or y1
        for zi=0,1 do
          local z=zi==0 and z0 or z1
          local px,py,pz = transform(view,x,y,z)
          l=l and math.min(l,px) or px; r=r and math.max(r,px) or px
          b=b and math.min(b,py) or py; t=t and math.max(t,py) or py
          zn=zn and math.min(zn,pz) or pz; zf=zf and math.max(zf,pz) or pz
        end
      end
    end
    local w,h = math.max(1e-6,r-l),math.max(1e-6,t-b)
    -- Intentionally NO light-space floor(l/texel) or floor(b/texel). The sun
    -- rotates continuously. Only the independent camera anchor is quantised.
    local near,far = -zf-64,-zn+64
    local proj = Mat4.ortho(l,r,b,t,near,far)
    proj = Mat4.mul(Mat4.scale(1,-1,1),proj)
    proj = Mat4.mul(Z01,proj)
    local clip = Mat4.mul(proj,view)
    local sign = (state.vSign == -1) and -1 or 1
    local uv = Mat4.mul(toUnit(sign),clip)
    res = math.max(1,tonumber(res) or sizes[1])
    local slack = BIAS + SLOPE*math.max(w,h)/res
    local bias = slack/math.max(1,far-near)
    return {clip=clip,uv=uv,extent={w,h,far-near},slack=slack,bias=bias,maxExtent=math.max(w,h)}
  end

  -- A tiny one-time render/readback determines whether the host canvas has the
  -- vertical convention used by older LÖVE releases. This is the same measured
  -- producer-space question the stock host asks, not a platform/version guess.
  local function probeVSign()
    if state.vSign == 1 or state.vSign == -1 then return state.vSign end
    state.vSign = 1
    if type(lg.newMesh) ~= "function" or type(lg.draw) ~= "function" then return state.vSign end
    local sh = shader(); if not sh then return state.vSign end
    local c = newColor(4); local tex=blankTexture()
    if not c or not tex then release(c); return state.vSign end
    local restore = captureGraphics()
    local done, sign = pcall(function()
      local mesh=lg.newMesh({{-1,0,0,0},{1,0,1,0},{1,1,1,1},{-1,1,0,1}},"fan","static")
      if type(mesh.setTexture)=="function" then mesh:setTexture(tex) end
      lg.setCanvas(c); lg.clear(1,1,0,1); lg.setShader(sh); lg.setColor(1,1,1,1)
      local probeVP=Mat4.mul(Z01,Mat4.scale(1,-1,1))
      pcallv(sh.send,sh,"lightVP","row",probeVP); pcallv(sh.send,sh,"model","row",IDENTITY); pcallv(sh.send,sh,"sprite",0)
      lg.draw(mesh); lg.setShader(); lg.setCanvas()
      local data=c:newImageData(); local w,h=data:getDimensions()
      local topR=data:getPixel(math.min(1,w-1),0); local botR=data:getPixel(math.min(1,w-1),h-1)
      if type(mesh.release)=="function" then mesh:release() end
      if topR < 0.9 and botR > 0.9 then return 1 end
      if botR < 0.9 and topR > 0.9 then return -1 end
      return 1
    end)
    restoreGraphics(restore); release(c)
    if done and (sign==1 or sign==-1) then state.vSign=sign end
    return state.vSign
  end

  local function activeDirection()
    if state.drawing and state.pendingKX ~= nil then return state.pendingKX,state.pendingKZ end
    if state.ready and state.committedKX ~= nil then return state.committedKX,state.committedKZ end
    return requestedDirection()
  end

  local api = {}
  function api.available()
    -- Deliberately allocation-free for shadow canvases. The host used to call
    -- availability from the caster path and could resize a larger live map down
    -- to its smallest rung merely to answer this question.
    if shadowsOff() then return false end
    return shader() ~= nil
  end
  function api.texture()
    if state.ready and state.canvas then return state.canvas end
    return blankTexture()
  end
  function api.active() return (not shadowsOff()) and state.ready and state.canvas ~= nil end
  function api.discard()
    state.ready=false; state.lastSig=nil; state.committedKX=nil; state.committedKZ=nil
  end
  function api.sunDir()
    local kx,kz=activeDirection(); local x,y,z=kx,-1,kz
    local l=math.sqrt(x*x+y*y+z*z); if l<1e-9 then l=1 end
    return {x/l,y/l,z/l}
  end
  function api.snug(model)
    local f=api.sunDir(); local s=-(state.slack or BIAS)*SNUG
    local tr
    if type(Mat4.translate)=="function" then tr=Mat4.translate(f[1]*s,f[2]*s,f[3]*s)
    else tr={1,0,0,f[1]*s, 0,1,0,f[2]*s, 0,0,1,f[3]*s, 0,0,0,1} end
    return Mat4.mul(tr,model or IDENTITY)
  end
  function api.stale(sig)
    if not state.ready then return true end
    if normaliseSignature(sig) ~= state.lastSig then return true end
    local kx,kz=requestedDirection()
    local dx=kx-(state.committedKX or kx); local dz=kz-(state.committedKZ or kz)
    local endpoint=HEIGHT*math.sqrt(dx*dx+dz*dz)
    return endpoint >= driftForTier(tierName())
  end
  function api.begin(cx,cy,vw,vh)
    if shadowsOff() then return false end
    local sh=shader(); if not sh then return false end
    probeVSign()
    -- Fit once. Resolution affects only receiver slack/bias, not the light-space
    -- clip/UV matrices, so the 8.1.78 double-fit was redundant on every recast.
    local f=fit(cx,cy,vw,vh,state.res or sizes[1])
    local wanted,target=chooseResolution(f.maxExtent)
    local c,actual=ensureCanvas(wanted); if not c then return false end
    local fw,fh,fd=f.extent[1],f.extent[2],f.extent[3]
    f.slack=BIAS + SLOPE*math.max(fw,fh)/math.max(1,actual)
    f.bias=f.slack/math.max(1,fd)
    local restore=captureGraphics()
    local bound=false
    if state.depth then
      bound=pcallv(lg.setCanvas,{c,depthstencil=state.depth})
      if not bound then release(state.depth); state.depth=nil end
    end
    if not bound then
      bound=pcallv(lg.setCanvas,{c,depth=true})
      state.implicitDepth=bound and true or false
    end
    if not bound then restoreGraphics(restore); return false end
    local ok=pcall(function()
      lg.clear(1,1,0,1,true,true)
      if type(lg.setDepthMode)=="function" then lg.setDepthMode("lequal",true) end
      if type(lg.setMeshCullMode)=="function" then lg.setMeshCullMode("none") end
      lg.setBlendMode("replace","premultiplied")
      lg.setColor(1,1,1,1); lg.setShader(sh)
      local sent=pcallv(sh.send,sh,"lightVP","row",f.clip)
      if not sent then assert(pcallv(sh.send,sh,"lightVP",f.clip),"shadow lightVP rejected") end
      pcallv(sh.send,sh,"model","row",IDENTITY)
      pcallv(sh.send,sh,"sprite",0)
      state.modelIdentity=true;state.spriteMode=false
    end)
    if not ok then restoreGraphics(restore); state.ready=false; return false end
    state.restore=restore; state.drawing=true; state.fault=false; state.ready=false
    state.pendingKX,state.pendingKZ=requestedDirection()
    state.pendingFit=f; state.target=target; state.slack=f.slack
    ShadowMap.clipVP,ShadowMap.uvVP=f.clip,f.uv
    ShadowMap.extent,ShadowMap.slack,ShadowMap.bias=f.extent,f.slack,f.bias
    ShadowMap.res,ShadowMap.vSign=actual,state.vSign
    ShadowMap._wxTarget=target
    return true
  end
  function api.sprites(on)
    if not state.drawing or state.fault then return end
    on=on and true or false
    if state.spriteMode==on then return end
    local sh=shader(); if sh then
      local ok=pcallv(sh.send,sh,"sprite",on and 1 or 0)
      if not ok then state.fault=true else state.spriteMode=on end
    end
  end
  function api.draw(mesh,texture,model)
    if not state.drawing or state.fault or not mesh then return end
    local ok=pcall(function()
      if texture and type(mesh.setTexture)=="function" then mesh:setTexture(texture) end
      local sh=shader()
      if sh then
        -- begin() already binds IDENTITY. Repeated terrain casters that also use
        -- nil/identity no longer resend the same 4x4 uniform through the driver.
        if model~=nil or not state.modelIdentity then
          local sent=pcallv(sh.send,sh,"model","row",model or IDENTITY)
          if not sent then assert(pcallv(sh.send,sh,"model",model or IDENTITY),"shadow model rejected") end
          state.modelIdentity=(model==nil)
        end
      end
      lg.setColor(1,1,1,1); lg.draw(mesh)
    end)
    if not ok then state.fault=true end
  end
  function api.finish(sig)
    if not state.drawing then return false end
    restoreGraphics(state.restore); state.restore=nil; state.drawing=false
    if state.fault then state.ready=false; state.pendingFit=nil; return false end
    state.lastSig=normaliseSignature(sig)
    state.committedKX,state.committedKZ=state.pendingKX,state.pendingKZ
    state.slack=state.pendingFit and state.pendingFit.slack or state.slack
    state.pendingFit=nil; state.ready=true
    return true
  end
  function api.invalidate()
    if state.drawing then restoreGraphics(state.restore) end
    state.restore=nil; state.drawing=false; state.ready=false; state.lastSig=nil
    state.spriteMode=nil;state.modelIdentity=false
    release(state.canvas); release(state.depth); release(state.blank)
    state.canvas=nil; state.depth=nil; state.blank=nil; state.res=nil
    state.committedKX=nil; state.committedKZ=nil
  end

  -- Debug hooks are pure/state-readable and make the real projection/recast
  -- implementation testable without duplicating it in fixtures.
  api._fitForTest=function(cx,cy,vw,vh,res) return fit(cx,cy,vw,vh,res or state.res or sizes[1]) end
  api._normaliseSignature=normaliseSignature
  api._state=function() return state end

  -- Apply only after every required capability has been validated. If install
  -- cannot complete, the host's original table remains untouched.
  ShadowMap.HEIGHT,ShadowMap.BIAS,ShadowMap.SLOPE,ShadowMap.FAR_CAP,ShadowMap.SNUG=HEIGHT,BIAS,SLOPE,FAR_CAP,SNUG
  ShadowMap.SIZES=sizes
  ShadowMap.res=tonumber(ShadowMap.res) or sizes[1]
  ShadowMap.bias=tonumber(ShadowMap.bias) or 0
  for k,v in pairs(api) do ShadowMap[k]=v end
  ShadowMap._source=function() return WRITER end
  ShadowMap._wxOwned=true
  ShadowMap._wxEngineVersion=VERSION
  ShadowMap._wxProjectionMode="weather-owned-continuous"
  ShadowMap._wxCameraAnchorStep=1/16
  ShadowMap._wxDepthFormats=DEPTH_FORMATS
  ShadowMap._wxRecastMode="caster-endpoint-drift"
  return true
end

return M
