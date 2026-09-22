-- SmoothSky — continuous voxel-sky presentation for Weather FX.
--
-- Voxel hosts intentionally paint the sky as a handful of flat 8-bit palette
-- bands with checkerboard dithering. That look is faithful to the source art,
-- but Weather FX's celestial/atmospheric system is aiming for a clear natural
-- sky. This module keeps the host/Weather-FX colours and horizon placement but
-- interpolates continuously between them on the GPU, eliminating the visible
-- horizontal stripes without editing the host mod on disk.
--
-- Fail-closed: if Mesh drawing is unavailable we use a bounded strip fallback;
-- if even that cannot draw, the caller simply keeps the host sky it already
-- painted.

local V = ...
local SmoothSky = {}

local mesh
local meshCount = 0

local function clamp(x,a,b)
  if x<a then return a end
  if x>b then return b end
  return x
end

local function lerp(a,b,t) return a + (b-a)*t end

local function colorAt(bands,t)
  local n=#bands
  if n<=1 then
    local c=bands[1] or {0.35,0.62,0.88}
    return c[1] or 0,c[2] or 0,c[3] or 0
  end
  t=clamp(t,0,1)
  local p=t*(n-1)
  local i=math.floor(p)+1
  if i>=n then
    local c=bands[n]
    return c[1] or 0,c[2] or 0,c[3] or 0
  end
  local f=p-(i-1)
  local a,b=bands[i],bands[i+1]
  return lerp(a[1] or 0,b[1] or 0,f),
         lerp(a[2] or 0,b[2] or 0,f),
         lerp(a[3] or 0,b[3] or 0,f)
end

local function buildVerts(w,edge,bands,alpha)
  local out={}
  local n=#bands
  if n<2 then
    local c=bands[1] or {0.35,0.62,0.88}
    bands={c,c}; n=2
  end
  local k=0
  local function push(x,y,c)
    k=k+1
    out[k]={x,y,0,0,c[1] or 0,c[2] or 0,c[3] or 0,alpha}
  end
  for i=1,n-1 do
    local y0=edge*((i-1)/(n-1))
    local y1=edge*(i/(n-1))
    local c0,c1=bands[i],bands[i+1]
    -- Two triangles. Shared boundary vertices use exactly the same colour, so
    -- adjacent gradient segments cannot create a seam.
    push(0,y0,c0); push(w,y0,c0); push(w,y1,c1)
    push(0,y0,c0); push(w,y1,c1); push(0,y1,c1)
  end
  return out
end

local function drawMesh(g,w,edge,bands,alpha)
  if not (g.newMesh and g.draw) then return false end
  local verts=buildVerts(w,edge,bands,alpha)
  local count=#verts
  local ok=false
  if mesh and meshCount==count and mesh.setVertices then
    ok=pcall(mesh.setVertices,mesh,verts)
    if not ok and mesh.release then pcall(mesh.release,mesh) end
    if not ok then mesh=nil; meshCount=0 end
  end
  if not mesh then
    local made,m=pcall(g.newMesh,verts,"triangles","dynamic")
    if not (made and m) then return false end
    mesh,meshCount=m,count
  end
  local drew=pcall(g.draw,mesh)
  return drew
end

local function drawFallback(g,w,edge,bands,alpha)
  if not (g.rectangle and g.setColor) then return false end
  -- Bounded fallback: enough strips that even a full-height 1080p sky has
  -- ~11px transitions, and each strip samples the continuous palette rather
  -- than exposing the host's six large colour blocks/checker rows.
  local strips=96
  local h=edge/strips
  for i=0,strips-1 do
    local t=(i+0.5)/strips
    local r,gg,b=colorAt(bands,t)
    g.setColor(r,gg,b,alpha)
    g.rectangle("fill",0,i*h,w,h+1)
  end
  return true
end

function SmoothSky.draw(w,h,sky,edge)
  -- The live player setting is authoritative. Reading Config alone was too
  -- indirect: on some host/menu orders CONFIG overrides had not yet been
  -- mirrored into Config when Sky.paint ran, so the row could say ON while the
  -- old checker-banded host sky remained. ON/OFF is now read directly here;
  -- CONFIG falls through to the authored config default.
  local enabled=nil
  local okSet,Set=pcall(V.require,"Settings")
  if okSet and Set and Set.get then
    local okChoice,choice=pcall(Set.get,"smoothSky")
    choice=okChoice and tostring(choice or "config"):lower() or "config"
    if choice=="on" then enabled=true elseif choice=="off" then enabled=false end
  end
  if enabled==nil then
    local okCfg,Cfg=pcall(V.require,"Config")
    if okCfg and Cfg and Cfg.get then
      local okData,data=pcall(Cfg.get)
      local cel=okData and data and data.celestial
      if cel and cel.smoothSky~=nil then enabled=cel.smoothSky~=false end
    end
  end
  if enabled==nil then enabled=true end
  SmoothSky._lastEnabled=enabled
  if not enabled then SmoothSky._lastPath="host";return false end
  local bands=sky and sky.bands
  if not (type(bands)=="table" and bands[1]) then return false end
  if not (w and h and w>0 and h>0) then return false end
  edge=math.min(h,math.max(1,tonumber(edge) or h))

  local loveObj=rawget(_G,"love")
  local g=loveObj and loveObj.graphics
  if not g then return false end

  local alpha=clamp(tonumber(sky[4]) or 1,0,1)
  local prevShader=g.getShader and g.getShader() or nil
  local cmp,write
  if g.getDepthMode then cmp,write=g.getDepthMode() end
  local blend,blendAlpha
  if g.getBlendMode then blend,blendAlpha=g.getBlendMode() end
  local cr,cg,cb,ca
  if g.getColor then cr,cg,cb,ca=g.getColor() end

  if g.setDepthMode then pcall(g.setDepthMode,"always",false) end
  if g.setBlendMode then pcall(g.setBlendMode,"alpha") end
  if g.setShader then pcall(g.setShader) end
  if g.setColor then pcall(g.setColor,1,1,1,1) end

  local ok=drawMesh(g,w,edge,bands,alpha)
  local path=ok and "mesh" or nil
  if not ok then ok=drawFallback(g,w,edge,bands,alpha); if ok then path="fallback" end end
  SmoothSky._lastPath=path or "host"
  if ok then SmoothSky._drawSerial=(SmoothSky._drawSerial or 0)+1 end

  if g.setColor then
    if cr then pcall(g.setColor,cr,cg,cb,ca or 1) else pcall(g.setColor,1,1,1,1) end
  end
  if g.setBlendMode and blend then pcall(g.setBlendMode,blend,blendAlpha) end
  if g.setDepthMode then pcall(g.setDepthMode,cmp or "always",write or false) end
  if g.setShader then pcall(g.setShader,prevShader) end
  return ok
end

function SmoothSky.status()
  return {enabled=SmoothSky._lastEnabled~=false,path=SmoothSky._lastPath or "never",drawSerial=tonumber(SmoothSky._drawSerial) or 0}
end
function SmoothSky.invalidate()
  if mesh and mesh.release then pcall(mesh.release,mesh) end
  mesh=nil; meshCount=0;SmoothSky._lastPath="never";SmoothSky._drawSerial=0
end

return SmoothSky
