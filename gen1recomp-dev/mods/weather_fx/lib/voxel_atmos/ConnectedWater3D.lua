-- Weather FX 8.1.35 professional connected + persistent whitewater presentation bridge.
--
-- One coherent mesh is built per connected cartridge water body. The original
-- shoreline/terrain stays host-owned, while liquid bodies continue through the
-- host's mature reflective water pass. Load-bearing bodies leave that liquid
-- pass and draw as continuous ice, and rain impacts are one bounded ripple
-- batch. Failure at any point is fail-open: VoxelScene receives its original
-- water draws unchanged.
local V=...
local C={meshes={},lastSector=nil,lastWaveBucket=nil,_origDynamics=nil,currentWaveHeight=0,
  _iceDraws={},_skinDraws={},_liquidDraws={},_outerDraws={},_voidDraws={},_shoreDraws={},_pondDraws={},_pondBedDraws={},_rippleRows={},_textureSlots={},
  _surfaceEntries={},_foamRows={},_fishRows={},_bobValue=0,_bobLast=nil,_enabled=true,_usingPhysicalSurface=false,
  _whitecapQuads=0,_curlQuads=0,_rapidQuads=0,_shoreFoamQuads=0,_waveKernel=nil,_outerEntry=nil,
  _pondFishCount=0,_pondBodyCount=0,_pondFishVisible=0}
local floor,max,min,sqrt,cos,sin,pi,abs,exp=math.floor,math.max,math.min,math.sqrt,math.cos,math.sin,math.pi,math.abs,math.exp
local TAU=pi*2
local waveSampleAtT
local function req(n) local ok,m=pcall(V.require,n);return ok and m or nil end
-- Centralize optional host/GPU fault containment for this renderer. A failed
-- capability remains fail-open, but the most recent error is retained instead
-- of being silently swallowed at dozens of independent call sites.
local function hostTry(fn,...)
  local ok,a,b,c,d,e,f=pcall(fn,...)
  if not ok then C._lastHostError=tostring(a) end
  return ok,a,b,c,d,e,f
end
local function atan2(y,x)
  if math.atan2 then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) elseif x<0 and y>=0 then return math.atan(y/x)+pi elseif x<0 then return math.atan(y/x)-pi elseif y>0 then return pi*.5 elseif y<0 then return -pi*.5 end
  return 0
end
local function hash(x,y)
  local n=(x*374761393+y*668265263)%2147483647
  n=(n*48271)%2147483647
  return n/2147483647
end

local function lerp(a,b,t) return a+(b-a)*t end
local function smooth01(t) t=max(0,min(1,t));return t*t*(3-2*t) end
local function valueNoise(x,y,period)
  local x0=floor(x);local y0=floor(y);local tx=smooth01(x-x0);local ty=smooth01(y-y0)
  local function h(ix,iy)
    ix=ix%period;iy=iy%period
    return hash(ix,iy)
  end
  local a=lerp(h(x0,y0),h(x0+1,y0),tx)
  local b=lerp(h(x0,y0+1),h(x0+1,y0+1),tx)
  return lerp(a,b,ty)
end
local function iceNoise(x,y,size)
  -- Periodic multi-scale value noise. All octave periods divide the image so
  -- the generated texture wraps without a visible seam across large bodies.
  local n=0
  n=n+valueNoise(x/16,y/16,size/16)*0.52
  n=n+valueNoise(x/8,y/8,size/8)*0.28
  n=n+valueNoise(x/4,y/4,size/4)*0.14
  n=n+valueNoise(x/2,y/2,size/2)*0.06
  return n
end
local function icePixel(x,y,size,coverage)
  local n=iceNoise(x,y,size)
  local n2=iceNoise((x+37)%size,(y+71)%size,size)
  local ax=x/size*TAU;local ay=y/size*TAU
  -- Primary fractures are long, bowed, interrupted fault lines rather than
  -- the old two families of perfectly straight modular stripes. Secondary
  -- branches are finer and only appear in colder/opaquer patches.
  local warp=(n-0.5)*2.6+(n2-0.5)*1.3
  local c1=abs(sin(ax+2*ay+warp))
  local c2=abs(sin(3*ax-ay+0.72*warp+1.7))
  local c3=abs(sin(2*ax+5*ay-0.48*warp+0.4))
  local gate=iceNoise((x+83)%size,(y+19)%size,size)
  local primary=(c1<0.030 and gate>0.34) or (c2<0.018 and gate>0.50)
  local branch=(c3<0.012 and gate>0.67 and (c1<0.22 or c2<0.18))
  local nearCrack=(c1<0.070 or c2<0.048)

  -- Cloudy inclusions and tiny trapped-air flecks break the uniform floor look.
  local frost=smooth01((n-0.43)/0.42)
  local fleck=hash((x*13+7)%size,(y*17+11)%size)>0.985
  local clear=1-frost
  local r=0.34+0.28*frost+0.06*n2
  local g=0.58+0.25*frost+0.05*n2
  local b=0.69+0.24*frost+0.04*n2
  local a=0.79+0.16*frost
  if nearCrack then r,g,b,a=r*0.90,g*0.94,min(1,b*1.02),min(0.98,a+0.025) end
  if primary or branch then r,g,b,a=r*0.52,g*0.64,b*0.73,0.98 end
  if fleck and not (primary or branch) then r,g,b,a=min(1,r+0.18),min(1,g+0.18),min(1,b+0.16),0.97 end

  if coverage then
    -- Progressive freeze skin: broad world-stable islands appear and join as
    -- the body approaches load-bearing. Hairline ice reaches a little farther
    -- than opaque frost so early skim ice does not look like hard-edged decals.
    local mask=0.70*n+0.30*n2
    local threshold=1-coverage
    local edge=smooth01((mask-threshold+0.07)/0.14)
    if edge<=0 then return r,g,b,0 end
    a=a*(0.32+0.58*edge)
  end
  return r,g,b,a
end

local function textureScaleNow()
  local scale=1
  local Q=req("Quality")
  if Q and type(Q.textureScale)=="function" then
    local ok,v=hostTry(Q.textureScale)
    if ok and tonumber(v) then scale=max(.25,min(1,tonumber(v))) end
  end
  return scale
end

local function imageFrom(kind)
  local slot=kind.."Texture"
  if not (love and love.image and love.graphics and love.image.newImageData and love.graphics.newImage) then return nil end
  local isIce=kind=="ice" or kind:match("^iceSkin%d+$")
  local base=isIce and 128 or ((kind=="water" or kind=="foam" or kind=="ripple") and 64 or ((kind=="pondBed" or kind=="fish") and 32 or 4))
  local minEdge=isIce and 32 or ((kind=="water" or kind=="foam" or kind=="ripple") and 16 or ((kind=="pondBed" or kind=="fish") and 8 or 4))
  local scale=textureScaleNow()
  -- Generated materials are periodic procedural textures, so resizing them does
  -- not delete authored art. Quantise to a multiple of 16/8 where practical so
  -- the periodic ice/value-noise octaves remain exact at every tier.
  local quantum=isIce and 16 or ((base>=64) and 8 or ((base>=32) and 4 or 1))
  local size=max(minEdge,floor(base*scale/quantum+.5)*quantum)
  local sizeSlot=slot.."Size"
  if C[slot] and C[sizeSlot]==size then return C[slot] end
  if C[slot] and C[slot].release then hostTry(C[slot].release,C[slot]) end
  C[slot],C[sizeSlot]=nil,nil
  local d=love.image.newImageData(size,size)
  local skinStage=tonumber(kind:match("^iceSkin(%d+)$"))
  local coverage=skinStage and (0.10+0.105*skinStage) or nil
  for y=0,size-1 do for x=0,size-1 do
    if isIce then
      d:setPixel(x,y,icePixel(x,y,size,coverage))
    elseif kind=="water" then
      -- Broad and fine world-stable variation is material colour only. The
      -- silhouette is real displaced geometry below; this keeps the safe
      -- non-reflective fallback from ever reading as a solid blue card.
      local n=iceNoise(x,y,size);local f=valueNoise(x/2,y/2,size/2)
      local band=0.5+0.5*sin((x*0.72+y*0.31)/size*TAU*3.0+(n-0.5)*1.8)
      local r=0.055+0.035*n+0.016*band
      local g=0.205+0.100*n+0.030*f
      local b=0.385+0.135*n+0.050*band
      d:setPixel(x,y,r,g,b,1)
    elseif kind=="foam" then
      -- Broken bubbly whitewater with a hard-enough alpha field for the voxel
      -- cutout renderer. It looks like aerated water rather than a white decal.
      local n=iceNoise(x,y,size);local f=valueNoise((x+17)/2,(y+29)/2,size/2)
      local strand=0.5+0.5*sin((x*1.7+y*0.53)/size*TAU*5.0+(n-0.5)*3.2)
      local a=((0.58*n+0.42*f+0.16*strand)>0.59) and 0.92 or 0.18
      local c=0.82+0.16*max(n,f)
      d:setPixel(x,y,c,min(1,c+0.035),1.0,a)
    elseif kind=="ripple" then
      local dx,dy=(x+0.5)/size-0.5,(y+0.5)/size-0.5
      local rr=sqrt(dx*dx+dy*dy);local ring=exp(-((rr-0.34)*(rr-0.34))/0.0028)
      d:setPixel(x,y,0.76,0.93,1.0,0.12+0.48*ring)
    elseif kind=="pondBed" then
      -- A muted silt/pebble bed gives translucent authored ponds bounded depth
      -- instead of exposing the generic world-underlay colour underneath them.
      local n=iceNoise(x,y,size);local peb=hash(x*5+13,y*7+29)
      local r=0.20+0.14*n;local g=0.18+0.11*n;local b=0.105+0.075*n
      if peb>0.94 then r,g,b=r+0.12,g+0.11,b+0.09 end
      d:setPixel(x,y,min(1,r),min(1,g),min(1,b),1)
    elseif kind=="fish" then
      local n=hash(x*3+5,y*5+11);local stripe=(floor(x/4)%2)==0 and 1 or 0
      d:setPixel(x,y,0.54+0.16*n+0.08*stripe,0.47+0.16*n,0.25+0.12*n,1)
    else
      local n=hash(x,y)
      d:setPixel(x,y,0.105+n*.025,0.275+n*.035,0.39+n*.045,1)
    end
  end end
  local t=love.graphics.newImage(d);t:setFilter("linear","linear");t:setWrap("repeat","repeat")
  -- 8.1.81: once the GPU image owns the generated pixels, retire the CPU-side
  -- ImageData immediately instead of waiting for a later Lua collection.
  if d and type(d.release)=="function" then hostTry(d.release,d) end
  C[slot]=t;C[sizeSlot]=size;C._textureSlots=C._textureSlots or {};C._textureSlots[slot]=true
  return t
end

local function iceTextureForStage(stage)
  stage=max(1,min(8,floor(tonumber(stage) or 1)))
  return imageFrom("iceSkin"..stage)
end

local function meshForBody(b,V3,uvScale,tag)
  uvScale=uvScale or 32;tag=tag or "water"
  local key=b.signature.."|"..tag
  local cached=C.meshes[key]
  if cached and cached.rectCount==#b.rects then return cached.mesh end
  if not (love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local verts={}
  local function v(x,y,z,u,w) verts[#verts+1]={x,y,z,u,w,1} end
  for _,r in ipairs(b.rects) do
    local y=-2
    local u0,v0,u1,v1=r.x0/uvScale,r.z0/uvScale,r.x1/uvScale,r.z1/uvScale
    v(r.x0,y,r.z0,u0,v0);v(r.x1,y,r.z0,u1,v0);v(r.x1,y,r.z1,u1,v1)
    v(r.x0,y,r.z0,u0,v0);v(r.x1,y,r.z1,u1,v1);v(r.x0,y,r.z1,u0,v1)
  end
  if tag=="iceBlock" then
    -- Load-bearing frozen water is a shallow solid slab, not just a texture on
    -- the liquid plane. Only exposed perimeter faces are emitted, so adjacent
    -- frozen cells remain one coherent block and there is no internal overdraw.
    local cells={};for _,c in ipairs(b.cells or {}) do cells[tostring(c.gx)..":"..tostring(c.gz)]=true end
    local y0,y1=-2.0,-3.05;local cellSize=tonumber(b.cellSize) or 16
    local function side(x0,z0,x1,z1)
      local len=max(abs(x1-x0),abs(z1-z0),1);local uu=len/cellSize
      v(x0,y0,z0,0,0);v(x1,y0,z1,uu,0);v(x1,y1,z1,uu,1)
      v(x0,y0,z0,0,0);v(x1,y1,z1,uu,1);v(x0,y1,z0,0,1)
    end
    for _,c in ipairs(b.cells or {}) do
      local gx,gz=c.gx,c.gz;local x0,z0=gx*cellSize,gz*cellSize;local x1,z1=x0+cellSize,z0+cellSize
      if not cells[tostring(gx-1)..":"..tostring(gz)] then side(x0,z1,x0,z0) end
      if not cells[tostring(gx+1)..":"..tostring(gz)] then side(x1,z0,x1,z1) end
      if not cells[tostring(gx)..":"..tostring(gz-1)] then side(x0,z0,x1,z0) end
      if not cells[tostring(gx)..":"..tostring(gz+1)] then side(x1,z1,x0,z1) end
    end
  end
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,verts,"triangles","static")
  if not ok then return nil end
  C.meshes[key]={mesh=m,rectCount=#b.rects};return m
end

local function meshForShoreSeal(b,V3)
  local key=b.signature.."|shoreSeal"
  local cached=C.meshes[key]
  if cached then return cached.mesh end
  if not (love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local cells={};for _,c in ipairs(b.cells or {}) do cells[tostring(c.gx)..":"..tostring(c.gz)]=true end
  local verts={};local yTop,yBottom=-2.0,-6.35;local cellSize=tonumber(b.cellSize) or 16
  local function v(x,y,z,u,w) verts[#verts+1]={x,y,z,u,w,0.78} end
  local function quad(x0,z0,x1,z1)
    local len=max(abs(x1-x0),abs(z1-z0),1);local u1=len/cellSize
    v(x0,yTop,z0,0,0);v(x1,yTop,z1,u1,0);v(x1,yBottom,z1,u1,1)
    v(x0,yTop,z0,0,0);v(x1,yBottom,z1,u1,1);v(x0,yBottom,z0,0,1)
  end
  for _,c in ipairs(b.cells or {}) do
    local gx,gz=c.gx,c.gz;local x0,z0=gx*cellSize,gz*cellSize;local x1,z1=x0+cellSize,z0+cellSize
    if not cells[tostring(gx-1)..":"..tostring(gz)] then quad(x0,z1,x0,z0) end
    if not cells[tostring(gx+1)..":"..tostring(gz)] then quad(x1,z0,x1,z1) end
    if not cells[tostring(gx)..":"..tostring(gz-1)] then quad(x0,z0,x1,z0) end
    if not cells[tostring(gx)..":"..tostring(gz+1)] then quad(x1,z1,x0,z1) end
  end
  if #verts==0 then return nil end
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,verts,"triangles","static");if not ok then return nil end
  C.meshes[key]={mesh=m,rectCount=#b.rects};return m
end

-- -------------------------------------------------------------------------
-- 8.1.38 living ponds + complete outer VOID ocean
local MAX_POND_FISH=24
local OUTER_SEA_RANGE=32768

-- Only cartridge-authored POND bodies are allowed into the living-water pass.
-- Host-semantic 8px fragments and both finite/far VOID water are presentation
-- water and must never acquire fish or shallow-pond semantics.
local function isLivingPond(b)
  return b~=nil and b.kind=="POND" and b.visualOnly~=true and b.voidWater~=true and b.hostWater~=true
end
C._isLivingPond=isLivingPond

local function pondAlpha(b)
  local area=max(1,tonumber(b and b.area) or 1)
  return 0.46+0.08*min(1,max(0,(area-1)/23))
end
C._pondAlpha=pondAlpha

local function pondFishCount(b)
  if not isLivingPond(b) then return 0 end
  local id=tonumber(b.id) or 0;local area=max(1,tonumber(b.area) or 1)
  return 2+floor(hash(id*31+area*7,area*19+11)*5) -- deterministic 2..6
end
C._pondFishCountForBody=pondFishCount

local function meshForPondBed(b,V3)
  local key=b.signature.."|pondBed";local q=C.meshes[key]
  if q then return q.mesh end
  if not (love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local rows={};local cellSize=tonumber(b.cellSize) or 16
  local function v(x,y,z,u,w) rows[#rows+1]={x,y,z,u,w,0.78} end
  for _,c in ipairs(b.cells or {}) do
    local x0,z0=c.gx*cellSize,c.gz*cellSize;local x1,z1=x0+cellSize,z0+cellSize
    local depth=5.20+0.65*hash(c.gx*17+3,c.gz*23+9);local y=-depth
    v(x0,y,z0,x0/32,z0/32);v(x1,y,z0,x1/32,z0/32);v(x1,y,z1,x1/32,z1/32)
    v(x0,y,z0,x0/32,z0/32);v(x1,y,z1,x1/32,z1/32);v(x0,y,z1,x0/32,z1/32)
  end
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,rows,"triangles","static");if not ok then return nil end
  C.meshes[key]={mesh=m,rectCount=#(b.rects or {})};return m
end

local function ensureFishMesh(V3)
  if C.fishMesh then return C.fishMesh end
  if not (love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,MAX_POND_FISH*36,"triangles","stream")
  if ok then C.fishMesh=m end;return C.fishMesh
end

local function fishPush(rows,n,x,y,z,u,v,shade)
  n=n+1;local r=rows[n];if not r then r={};rows[n]=r end
  r[1],r[2],r[3],r[4],r[5],r[6]=x,y,z,u,v,shade or 1;return n
end
local function fishTri(rows,n,a,b,c,shade)
  n=fishPush(rows,n,a[1],a[2],a[3],0,0,shade);n=fishPush(rows,n,b[1],b[2],b[3],1,0,shade);n=fishPush(rows,n,c[1],c[2],c[3],.5,1,shade);return n
end

local function buildFishRows(Water,t)
  local rows=C._fishRows;local n,visible=0,0
  for _,d in ipairs(C._pondDraws or {}) do
    local b=d[4];local want=tonumber(d[7]) or 0
    if b and want>0 and (tonumber(b.ice) or 0)<0.68 and not b.loadBearing then
      local cells=b.cells or {};local cellSize=tonumber(b.cellSize) or 16
      for i=1,min(want,#cells>0 and want or 0) do
        if visible>=MAX_POND_FISH then break end
        local id=tonumber(b.id) or 0
        local ci=(floor(hash(id*41+i*13,i*59+17)*#cells)%#cells)+1;local c=cells[ci]
        local s1=hash(id*73+i*19,c.gx*11+c.gz*29);local s2=hash(id*97+i*31,c.gx*37+c.gz*7)
        local baseX=c.gx*cellSize+4+s1*(cellSize-8);local baseZ=c.gz*cellSize+4+s2*(cellSize-8)
        local radius=1.25+1.85*hash(i*17+id,c.gx*5+c.gz*13);local speed=.72+1.05*hash(i*23+id,c.gx*31+c.gz*3)
        local a=(t or 0)*speed+s2*TAU;local x=baseX+cos(a)*radius;local z=baseZ+sin(a)*radius
        local dx,dz=-sin(a),cos(a);local sx,sz=-dz,dx
        local surf=-2+(tonumber(b.tide) or 0);local y=surf-(1.55+1.25*s1)+sin(a*1.7+s2*TAU)*.12
        local len=1.25+.75*s2;local wid=.34+.16*s1;local ht=.25+.12*s2
        local nose={x+dx*len,y,z+dz*len};local tail={x-dx*len*.72,y,z-dz*len*.72}
        local left={x+sx*wid,y,z+sz*wid};local right={x-sx*wid,y,z-sz*wid};local top={x,y+ht,z};local bot={x,y-ht,z}
        local fin={x-dx*len*1.35,y,z-dz*len*1.35};local finTop={fin[1]+sx*wid*.75,fin[2]+ht*.9,fin[3]+sz*wid*.75};local finBot={fin[1]-sx*wid*.75,fin[2]-ht*.9,fin[3]-sz*wid*.75}
        n=fishTri(rows,n,nose,left,tail,1);n=fishTri(rows,n,nose,tail,right,.92)
        n=fishTri(rows,n,nose,top,tail,1);n=fishTri(rows,n,nose,tail,bot,.82)
        n=fishTri(rows,n,tail,finTop,fin,.9);n=fishTri(rows,n,tail,fin,finBot,.76)
        visible=visible+1
      end
    end
  end
  for i=#rows,n+1,-1 do rows[i]=nil end
  C._pondFishVisible=visible
  return n
end

local function adaptiveAxis(center,range,extras)
  local vals={[center]=true};local p,step,band=0,64,512
  while p<range do
    p=min(range,p+step);vals[center+p]=true;vals[center-p]=true
    if p>=band then step=min(step*2,2048);band=band*2 end
  end
  for _,v in ipairs(extras or {}) do vals[tonumber(v) or 0]=true end
  local out={};for v in pairs(vals) do out[#out+1]=v end;table.sort(out);return out
end
local function rectContainsCell(r,x0,z0,x1,z1)
  return x0>=r.x0 and x1<=r.x1 and z0>=r.z0 and z1<=r.z1
end

local function outerSeaEntry(sea,V3)
  if not (sea and sea.outerSea and love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local key=tostring(sea.signature).."|outerPhysical"
  if C._outerEntry and C._outerEntry.key==key then return C._outerEntry end
  if C._outerEntry and C._outerEntry.mesh and C._outerEntry.mesh.release then hostTry(C._outerEntry.mesh.release,C._outerEntry.mesh) end
  local range=min(OUTER_SEA_RANGE,tonumber(sea.range) or OUTER_SEA_RANGE);local cx,cz=tonumber(sea.cx) or 0,tonumber(sea.cz) or 0
  local ex,ez={},{}
  for _,r in ipairs(sea.holes or {}) do ex[#ex+1]=r.x0;ex[#ex+1]=r.x1;ez[#ez+1]=r.z0;ez[#ez+1]=r.z1 end
  local xs,zs=adaptiveAxis(cx,range,ex),adaptiveAxis(cz,range,ez);local rows,coords,index,indices={},{},{},{}
  local function vid(x,z)
    local k=tostring(x)..":"..tostring(z);local i=index[k];if i then return i end
    i=#rows+1;index[k]=i;rows[i]={x,-2,z,x/64,z/64,1};coords[i*2-1]=x;coords[i*2]=z;return i
  end
  local holes=sea.holes or {}
  for zi=1,#zs-1 do for xi=1,#xs-1 do
    local x0,x1,z0,z1=xs[xi],xs[xi+1],zs[zi],zs[zi+1];local blocked=false
    for _,r in ipairs(holes) do if rectContainsCell(r,x0,z0,x1,z1) then blocked=true;break end end
    if not blocked then
      local a,b,c,d=vid(x0,z0),vid(x1,z0),vid(x1,z1),vid(x0,z1)
      indices[#indices+1]=a;indices[#indices+1]=b;indices[#indices+1]=c
      indices[#indices+1]=a;indices[#indices+1]=c;indices[#indices+1]=d
    end
  end end
  -- Only the near shoreline belt needs CPU-displaced silhouette geometry. The
  -- host Water shader supplies reflective/fine wave detail all the way to the
  -- horizon, so evaluating the Gerstner spectrum on thousands of 32K-distant
  -- vertices every frame would buy no visible quality. Keep a generous 768u
  -- physical belt around every loaded-map/apron hole and leave the far field at
  -- the shared tide datum. This preserves a moving 96px handoff while making
  -- outer-ocean CPU cost proportional to the playable corridor, not 32K range.
  local dynamic,dc={},0
  for i=1,#rows do
    local x,z=coords[i*2-1],coords[i*2];local near=false
    for _,r in ipairs(holes) do
      if x>=r.x0-768 and x<=r.x1+768 and z>=r.z0-768 and z<=r.z1+768 then near=true;break end
    end
    dynamic[i]=near;if near then dc=dc+1 end
  end
  -- Repack near-belt vertices first. The index map is remapped once at mesh
  -- creation so each live frame can upload only the physically displaced belt
  -- rather than copying the entire 32K far-ocean vertex table back to the GPU.
  local remap,newRows,newCoords={}, {}, {}
  local function appendOld(oldi)
    local ni=#newRows+1;remap[oldi]=ni;newRows[ni]=rows[oldi]
    newCoords[ni*2-1],newCoords[ni*2]=coords[oldi*2-1],coords[oldi*2]
  end
  for i=1,#rows do if dynamic[i] then appendOld(i) end end
  for i=1,#rows do if not dynamic[i] then appendOld(i) end end
  for i=1,#indices do indices[i]=remap[indices[i]] end
  rows,coords=newRows,newCoords
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,rows,"triangles","stream");if not ok or not m then return nil end
  if type(m.setVertexMap)~="function" or not hostTry(m.setVertexMap,m,indices) then if m.release then hostTry(m.release,m) end;return nil end
  C._outerEntry={key=key,mesh=m,rows=rows,coords=coords,indices=indices,dynamicCount=dc,vertexCount=#rows,indexCount=#indices,lastT=nil,lastH=nil};return C._outerEntry
end

local function updateOuterSea(e,Water,h,t)
  if not (e and e.mesh and e.mesh.setVertices) then return false end
  if e.lastT==t and e.lastH==h then return true end
  local dc=tonumber(e.dynamicCount) or 0
  for i=1,dc do
    local x,z=e.coords[i*2-1],e.coords[i*2];local raw,sx,sz=waveSampleAtT(Water,x,z,t,h)
    local r=e.rows[i];r[1],r[2],r[3]=x+sx,-2+(raw-0.5)*h,z+sz
  end
  local ok=true
  if dc>0 then ok=hostTry(e.mesh.setVertices,e.mesh,e.rows,1,dc) end
  if ok then e.lastT,e.lastH=t,h end;return ok
end

local function copy4(t)
  return t and {t[1],t[2],t[3],t[4]} or nil
end
local function renderBodies(CW)
  if not CW then return {} end
  return CW.renderBodies or CW.bodies or {}
end
local function liquidWave(CW)
  local sum,area=0,0
  for _,b in ipairs(renderBodies(CW)) do if not b.loadBearing then sum=sum+(tonumber(b.wave) or 0)*b.area;area=area+b.area end end
  return area>0 and sum/area or 0
end
local function trainAt(ang,wavelength,speed,weight)
  local f=TAU/max(8,tonumber(wavelength) or 64)
  return {cos(ang)*f,sin(ang)*f,speed,weight}
end
local function rotateLegacyTrain(t,ang,scale)
  local len=sqrt(t[1]*t[1]+t[2]*t[2])
  return {cos(ang)*len,sin(ang)*len,t[3]*(0.55+0.65*scale),t[4]}
end
local function rememberDynamics(Water)
  if C._origDynamics then return end
  local q={trains={}}
  for i,t in ipairs(Water.WAVE_TRAINS or {}) do q.trains[i]=copy4(t) end
  q.height=Water.WAVE_HEIGHT;q.swell=copy4(Water.WAVE_SWELL);q.bend=copy4(Water.WAVE_BEND)
  q.fps=Water.WAVE_FPS;q.pixels=Water.WAVE_PIXELS_PER_STEP;q.slope=Water.WAVE_SLOPE;q.slopeLean=Water.WAVE_SLOPE_LEAN
  C._origDynamics=q
end
local function applyWaterDynamics(Water,CW)
  if not (Water and Water.WAVE_TRAINS and Water.invalidate) then return end
  rememberDynamics(Water)
  -- ConnectedWater publishes the normalized prevailing direction directly.
  -- Do not build its public diagnostics table every render frame just to read
  -- these two scalars. Third-party/older authorities that lack the fields keep
  -- the old sample() fallback for compatibility.
  local wx,wz=CW.windX,CW.windZ
  if wx==nil or wz==nil then
    local s=(type(CW.sample)=="function" and CW.sample()) or {}
    wx,wz=s.windX,s.windZ
  end
  local ang=atan2(wz or 0,wx or 1)
  local wave=liquidWave(CW);local bucket=floor(min(1.5,max(0,wave))*4+0.25)
  local hostCaps=(CW and type(CW.voxelWaterHost)=="function" and CW.voxelWaterHost()) or (CW and CW._voxelWaterHost) or nil
  local publicBattleArt=hostCaps and hostCaps.publicBattleArtWater==true
  local structured=type(Water._waveTime)=="function"
    and type(Water.WAVE_TRAINS)=="table" and type(Water.WAVE_TRAINS[1])=="table"
    and type(Water.WAVE_SWELL)=="table" and type(Water.WAVE_BEND)=="table"
    and (type(Water._trainSource)=="function" or publicBattleArt)
  -- Upstream Battle Art 1.10.x deliberately does not export _trainSource, but
  -- its public WAVE_* tables + _waveTime use the same 0..H relief convention.
  -- The capability is proven by the bridge fingerprint above, not guessed from
  -- the shared BATTLE_ART_VOXEL_FORK id. Once physical mesh ownership succeeds,
  -- prepare() sets Water.WAVE_HEIGHT=0 so Battle Art keeps reflections/depth
  -- while its second geometric relief surface is removed.
  C._centeredRelief=structured and true or false
  if not structured then
    -- Compatibility fallback for a Water module that exposes the older public
    -- train/height seam but not Voxel Realism's 0..H relief field. Preserve the
    -- proven 8.1.30 behavior instead of assuming its height convention.
    local sector=floor(((ang%TAU)/TAU)*16+0.5)%16
    local h=max(0,min(6,floor(0.5+5*max(0.08,wave))))
    Water.WAVE_HEIGHT=h;C.currentWaveHeight=h;C._liquidWave=wave
    if C.lastSector~=sector then
      C.lastSector,C.lastWaveBucket=sector,bucket
      local a=sector/16*TAU;local scale=max(0.12,bucket/4)
      for i,t in ipairs(C._origDynamics.trains or {}) do
        local off=(i==1 and 0 or (i==2 and 1.35 or -1.12))
        Water.WAVE_TRAINS[i]=rotateLegacyTrain(t,a+off,scale)
      end
      C._waveKernel=nil
      hostTry(Water.invalidate)
    end
    return
  end
  local sector=floor(((ang%TAU)/TAU)*24+0.5)%24

  -- PHYSICAL SURFACE RELIEF. h is peak-to-trough world relief. Structured
  -- Voxel Realism hosts receive an actual tessellated moving mesh; the old
  -- fragment relief remains an automatic compatibility fallback.
  local h=(wave<=0.010) and 0 or max(1.35,min(8.50,0.95+5.45*wave))
  Water.WAVE_HEIGHT=h;C.currentWaveHeight=h
  Water.WAVE_SLOPE=3.15+1.45*min(1,wave/1.45)
  Water.WAVE_SLOPE_LEAN=1.22
  Water.WAVE_FPS=30
  Water.WAVE_PIXELS_PER_STEP=1

  -- Gerstner/trochoidal-inspired spectrum: aligned 2nd/3rd harmonics pinch the
  -- main crest and broaden the trough, oblique trains break repetition, and a
  -- long swell/bend field makes waves arrive in coherent moving sets.
  if C.lastSector==sector then C.lastWaveBucket=bucket;C._liquidWave=wave;return end
  C.lastSector,C.lastWaveBucket,C._liquidWave=sector,bucket,wave
  local a=sector/24*TAU
  Water.WAVE_TRAINS[1]=trainAt(a,78,1.00,0.46)
  Water.WAVE_TRAINS[2]=trainAt(a,39,2.00,0.17)
  Water.WAVE_TRAINS[3]=trainAt(a,26,3.00,0.06)
  Water.WAVE_TRAINS[4]=trainAt(a+0.46,51,0.72,0.20)
  Water.WAVE_TRAINS[5]=trainAt(a-0.82,23,-0.52,0.11)
  for i=6,#Water.WAVE_TRAINS do Water.WAVE_TRAINS[i]=nil end
  Water.WAVE_SWELL=trainAt(a+0.08,290,0.42,0.32)
  Water.WAVE_BEND=trainAt(a+pi*0.5,220,0.28,0.95)
  C._waveKernel=nil
  hostTry(Water.invalidate)
end

-- Exact Lua mirror of the host shader's smooth field. This is used only for
-- presentation sampling (ripple height and the surfing body/camera). Gameplay
-- collision continues to use ConnectedWater.surfaceYAt(), which intentionally
-- remains the stable tide datum.
local function waveTimeValue(Water)
  local t=0
  if Water and type(Water._waveTime)=="function" then local ok,v=hostTry(Water._waveTime);if ok then t=tonumber(v) or 0 end end
  return t
end
local function waveKernel(Water)
  local k=C._waveKernel
  if k and k.water==Water and k.trains==Water.WAVE_TRAINS and k.t1==(Water.WAVE_TRAINS and Water.WAVE_TRAINS[1]) then return k end
  k={water=Water,trains=Water and Water.WAVE_TRAINS,t1=Water and Water.WAVE_TRAINS and Water.WAVE_TRAINS[1],items={}}
  for i,tr in ipairs((Water and Water.WAVE_TRAINS) or {}) do
    local kx,kz=tonumber(tr[1]) or 0,tonumber(tr[2]) or 0
    local kl=sqrt(kx*kx+kz*kz)
    k.items[i]={kx=kx,kz=kz,speed=tonumber(tr[3]) or 0,weight=tonumber(tr[4]) or 0,
      nx=kl>1e-7 and kx/kl or 0,nz=kl>1e-7 and kz/kl or 0}
  end
  local b=Water and Water.WAVE_BEND or nil;local sw=Water and Water.WAVE_SWELL or nil
  k.b1,k.b2,k.b3,k.b4=tonumber(b and b[1]) or 0,tonumber(b and b[2]) or 0,tonumber(b and b[3]) or 0,tonumber(b and b[4]) or 0
  k.s1,k.s2,k.s3,k.s4=tonumber(sw and sw[1]) or 0,tonumber(sw and sw[2]) or 0,tonumber(sw and sw[3]) or 0,tonumber(sw and sw[4]) or 0
  C._waveKernel=k;return k
end

-- One spectrum walk returns both height and Gerstner-style horizontal orbital
-- displacement. 8.1.35 walked the same wave trains twice for every physical
-- vertex. Pre-normalized/cached train coefficients also avoid repeated tonumber
-- and vector-length work without changing a single wave, vertex or quality tier.
waveSampleAtT=function(Water,x,z,t,h)
  if not (Water and Water.WAVE_TRAINS and Water.WAVE_TRAINS[1]) then return 0.5,0,0 end
  local k=waveKernel(Water);local sum,sx,sz=0,0,0
  local bendPhase=k.b4~=0 and k.b4*sin(x*k.b1+z*k.b2+t*k.b3) or 0
  local env=1
  if k.s4~=0 then env=1-k.s4*(0.5+0.5*sin(x*k.s1+z*k.s2+t*k.s3)) end
  local hh=tonumber(h) or 0;local doHoriz=hh>0
  local items=k.items
  -- Numeric traversal is materially cheaper in the per-vertex water hot path
  -- than ipairs on low-power Lua runtimes and preserves the exact train order.
  for i=1,#items do
    local it=items[i];local phase=x*it.kx+z*it.kz+t*it.speed
    if i==1 then phase=phase+bendPhase;sum=sum+sin(phase)*it.weight*env
    else sum=sum+sin(phase)*it.weight end
    if doHoriz and (it.nx~=0 or it.nz~=0) then
      local q=0.20*hh*it.weight*cos(phase)
      sx=sx-it.nx*q;sz=sz-it.nz*q
    end
  end
  if doHoriz then
    local lim=min(1.75,0.30*hh);local l2=sx*sx+sz*sz
    -- Most vertices never hit the orbital clamp. Avoid sqrt entirely in that
    -- overwhelmingly common case; when clamping is needed, the old formula is
    -- evaluated unchanged.
    if l2>lim*lim and l2>0 then local l=sqrt(l2);sx,sz=sx*lim/l,sz*lim/l end
  end
  return max(0,min(1,sum*0.5+0.5)),sx,sz
end
local function waveRawAtT(Water,x,z,t) local raw=waveSampleAtT(Water,x,z,t,0);return raw end
local function waveRawAt(Water,x,z) return waveRawAtT(Water,x,z,waveTimeValue(Water)) end
local physicalWaveHeightForBody
local function waveHorizontalAtT(Water,x,z,t,h) local _,sx,sz=waveSampleAtT(Water,x,z,t,h);return sx,sz end

function C.waveDisplacementAt(x,z,continuous)
  if C._enabled==false then return 0 end
  local CW=C._CW or req("ConnectedWater");local Water=C._Water or req("Water")
  local b=CW and CW.bodyAt and CW.bodyAt(x,z) or nil
  if not b or b.loadBearing then return 0 end
  if not C._centeredRelief then return 0 end
  local h=C._usingPhysicalSurface and physicalWaveHeightForBody(b) or (tonumber(C.currentWaveHeight) or tonumber(Water and Water.WAVE_HEIGHT) or 0)
  if h<=0 then return 0 end
  local raw=waveRawAt(Water,tonumber(x) or 0,tonumber(z) or 0)
  if continuous then return (raw-0.5)*h end
  return floor(raw*h+0.5)-h*0.5
end
function C.visualSurfaceYAt(x,z,continuous)
  local CW=C._CW or req("ConnectedWater");local b=CW and CW.bodyAt and CW.bodyAt(x,z) or nil
  if not b then return nil end
  local datum=-2+(tonumber(b.tide) or 0)
  if b.loadBearing then return datum end
  return datum+C.waveDisplacementAt(x,z,continuous)
end


-- -------------------------------------------------------------------------
-- Real 3D liquid surface + whitewater
--
-- Voxel Realism's native reflective pass shades a flat rasterised sheet and
-- ray-marches relief in the fragment shader. From an elevated overworld view
-- that can still have the silhouette of a rectangle. Weather FX 8.1.33 keeps
-- that mature reflection/Fresnel pass but feeds it a genuinely displaced mesh
-- whose vertices follow the same wave spectrum. The cartridge mask remains the
-- shoreline authority and the collision plane remains the stable tide datum.

local function surfaceStepForBody(b)
  if (tonumber(b and b.cellSize) or 16)<=8 then return 4 end
  -- Geometry carries the large silhouette while the reflective shader carries
  -- the fine normal/detail field. 4 px is reserved for small close-scale water;
  -- broad lakes/seas use 8 px, still giving roughly ten samples across the
  -- dominant 78 px swell while cutting vertex/trig traffic by about 4x.
  local area=tonumber(b and b.area) or 0
  return area>256 and 8 or 4
end

physicalWaveHeightForBody=function(b)
  local w=max(0,tonumber(b and b.wave) or 0)
  if w<=0.010 or (tonumber(b and b.ice) or 0)>=0.985 then return 0 end
  local kind=tostring(b and b.kind or "LAKE")
  local floorH=(kind=="SEA" and 3.20) or (kind=="LAKE" and 2.65) or (kind=="RIVER" and 1.85) or 1.25
  local capH=(kind=="SEA" and 9.25) or (kind=="LAKE" and 8.25) or (kind=="RIVER" and 5.75) or 3.75
  -- The floor is what prevents calm lakes from collapsing back into the exact
  -- flat-blue-card failure this revision replaces. Weather/wind still adds
  -- substantial height above it; freezing damps b.wave before this point.
  return max(floorH,min(capH,0.95+5.55*w))
end

local function surfaceEntryForBody(b,V3)
  if not (b and b.cells and #b.cells>0 and love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local step=surfaceStepForBody(b);local cellSize=tonumber(b.cellSize) or 16;local key=b.signature.."|physical|"..tostring(step).."|"..tostring(cellSize)
  local e=C._surfaceEntries[key];if e then return e end
  local rows,coords,indexBy,indices,edges={},{},{},{},{}
  local cells={};for _,c in ipairs(b.cells) do cells[tostring(c.gx)..":"..tostring(c.gz)]=true end
  local function vkey(x,z) return tostring(floor(x+0.5))..":"..tostring(floor(z+0.5)) end
  local function vertex(x,z)
    local k=vkey(x,z);local idx=indexBy[k]
    if idx then return idx end
    idx=#rows+1;indexBy[k]=idx
    rows[idx]={x,-2,z,x/64,z/64,1};coords[idx*2-1]=x;coords[idx*2]=z
    return idx
  end
  for _,c in ipairs(b.cells) do
    local x0,z0=c.gx*cellSize,c.gz*cellSize
    for dz=0,cellSize-step,step do for dx=0,cellSize-step,step do
      local x,z=x0+dx,z0+dz
      local a=vertex(x,z);local bb=vertex(x+step,z);local cc=vertex(x+step,z+step);local d=vertex(x,z+step)
      indices[#indices+1]=a;indices[#indices+1]=bb;indices[#indices+1]=cc
      indices[#indices+1]=a;indices[#indices+1]=cc;indices[#indices+1]=d
    end end
    local gx,gz=c.gx,c.gz;local x1,z1=x0+cellSize,z0+cellSize
    -- edge normal points inward. It is used by shore-break foam and also marks
    -- vertices that must not slide horizontally under authored land.
    if not cells[tostring(gx-1)..":"..tostring(gz)] then edges[#edges+1]={x0,z0,x0,z1,1,0} end
    if not cells[tostring(gx+1)..":"..tostring(gz)] then edges[#edges+1]={x1,z1,x1,z0,-1,0} end
    if not cells[tostring(gx)..":"..tostring(gz-1)] then edges[#edges+1]={x1,z0,x0,z0,0,1} end
    if not cells[tostring(gx)..":"..tostring(gz+1)] then edges[#edges+1]={x0,z1,x1,z1,0,-1} end
  end

  -- Shore-pinning mask: 0 at the exact cartridge coastline, blended to full
  -- Gerstner orbital motion over three tessellation rings.
  local dist,queue={},{};local qh=1
  local function markEdge(x0,z0,x1,z1)
    local dx,dz=x1-x0,z1-z0;local len=max(abs(dx),abs(dz));local count=max(1,floor(len/step+0.5))
    for j=0,count do
      local x=x0+dx*j/count;local z=z0+dz*j/count;local idx=indexBy[vkey(x,z)]
      if idx and dist[idx]==nil then dist[idx]=0;queue[#queue+1]=idx end
    end
  end
  for _,edge in ipairs(edges) do markEdge(edge[1],edge[2],edge[3],edge[4]) end
  while queue[qh] do
    local idx=queue[qh];qh=qh+1;local x,z=coords[idx*2-1],coords[idx*2];local nd=dist[idx]+1
    if nd<=3 then
      -- Build-time shoreline BFS used to allocate four tiny coordinate tables
      -- for every visited vertex. Probe the same four neighbors directly.
      local ni=indexBy[vkey(x+step,z)];if ni and dist[ni]==nil then dist[ni]=nd;queue[#queue+1]=ni end
      ni=indexBy[vkey(x-step,z)];if ni and dist[ni]==nil then dist[ni]=nd;queue[#queue+1]=ni end
      ni=indexBy[vkey(x,z+step)];if ni and dist[ni]==nil then dist[ni]=nd;queue[#queue+1]=ni end
      ni=indexBy[vkey(x,z-step)];if ni and dist[ni]==nil then dist[ni]=nd;queue[#queue+1]=ni end
    end
  end
  local pins={};for i=1,#rows do pins[i]=min(1,(dist[i] or 3)/3) end

  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,rows,"triangles","stream");if not ok or not m then return nil end
  if type(m.setVertexMap)~="function" then if m.release then hostTry(m.release,m) end;return nil end
  local okMap=hostTry(m.setVertexMap,m,indices);if not okMap then if m.release then hostTry(m.release,m) end;return nil end
  e={mesh=m,rows=rows,coords=coords,pins=pins,indices=indices,edges=edges,step=step,lastT=nil,lastH=nil,vertexCount=#rows,indexCount=#indices}
  C._surfaceEntries[key]=e;return e
end

local function updatePhysicalSurface(e,Water,h,t)
  if not (e and e.mesh and e.mesh.setVertices) then return false end
  if e.lastT==t and e.lastH==h then return true end
  local rows,coords,pins=e.rows,e.coords,e.pins
  for i=1,#rows do
    local x,z=coords[i*2-1],coords[i*2]
    local raw,sx,sz=waveSampleAtT(Water,x,z,t,h);local pin=pins[i] or 0
    local r=rows[i];r[1]=x+sx*pin;r[2]=-2+raw*h;r[3]=z+sz*pin
  end
  local ok=hostTry(e.mesh.setVertices,e.mesh,rows,1,#rows)
  if ok then e.lastT,e.lastH=t,h end
  return ok
end

local function ensureFoamMesh(V3,cap)
  if C.foamMesh then return C.foamMesh end
  if not (love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,cap or 18000,"triangles","stream")
  if ok then C.foamMesh=m end;return C.foamMesh
end
local function foamPush(rows,n,x,y,z,u,v,shade)
  n=n+1;local r=rows[n];if not r then r={};rows[n]=r end
  r[1],r[2],r[3],r[4],r[5],r[6]=x,y,z,u,v,shade or 1;return n
end
local function foamQuadCoords(rows,n,x1,y1,z1,x2,y2,z2,x3,y3,z3,x4,y4,z4)
  -- Hot water frames already reuse `rows`; keep the geometry scalar too. The
  -- old helper required four freshly allocated point tables for every curl
  -- segment even though the GPU receives the same six vertices either way.
  n=foamPush(rows,n,x1,y1,z1,0,0,1);n=foamPush(rows,n,x2,y2,z2,1,0,1);n=foamPush(rows,n,x3,y3,z3,1,1,1)
  n=foamPush(rows,n,x1,y1,z1,0,0,1);n=foamPush(rows,n,x3,y3,z3,1,1,1);n=foamPush(rows,n,x4,y4,z4,0,1,1)
  return n
end
local function waterYAtT(b,Water,h,t,x,z)
  return -2+(tonumber(b.tide) or 0)-h*0.5+waveRawAtT(Water,x,z,t)*h
end
local function primaryDirection(Water)
  local tr=Water and Water.WAVE_TRAINS and Water.WAVE_TRAINS[1]
  if not tr then return 1,0,-1,0,0 end
  local kx,kz=tonumber(tr[1]) or 0,tonumber(tr[2]) or 0
  local l=sqrt(kx*kx+kz*kz);if l<1e-6 then return 1,0,-1,0,0 end
  local dx,dz=kx/l,kz/l
  -- phase=kx+wt travels opposite k for positive omega. The fifth return is
  -- physical crest speed in world pixels/second, used by temporally coherent
  -- whitewater tracks so foam rides the same dominant crest instead of hopping
  -- between fixed sample points.
  local speed=abs(tonumber(tr[3]) or 0)/l
  return dx,dz,-dx,-dz,speed
end

-- Foam in 8.1.33/8.1.34 was generated by re-testing fixed world points each
-- frame. A point could be above the crest threshold on frame N, vanish on N+1,
-- and a distant point could qualify instead. That is the white-square
-- "teleporting" failure. 8.1.35 uses analytic persistent tracks instead:
-- every candidate has a deterministic lifetime and moves continuously with the
-- dominant crest/current. A reset happens only at zero-size at the ends of the
-- envelope, so changing cycles cannot produce a visible jump.
local function foamEnvelope(q)
  q=q-floor(q)
  local rise=smooth01(min(1,q/0.20))
  local fall=smooth01(min(1,(1-q)/0.24))
  return rise*fall
end

local function trackPhase(t,period,seed)
  period=max(0.25,tonumber(period) or 1.5)
  local q=((tonumber(t) or 0)/period+(tonumber(seed) or 0))%1
  return q,foamEnvelope(q)
end

local function foamRibbon(rows,n,b,Water,h,t,cx,cz,ax,az,half,halfWidth,strength,seed,yLift)
  -- Five cross-sections make a tapered, slightly crooked ribbon. Unlike a
  -- four-corner quad it has no rectangular silhouette at distance. Both length
  -- and width collapse smoothly with strength, so birth/death is continuous.
  strength=max(0,min(1,tonumber(strength) or 0));if strength<=0 then return n end
  local al=sqrt(ax*ax+az*az);if al<1e-6 then ax,az,al=1,0,1 end;ax,az=ax/al,az/al
  local bx,bz=-az,ax
  local vis=sqrt(strength);half=half*vis;halfWidth=halfWidth*strength
  -- Keep the exact five cross-sections and exact math, but carry previous
  -- points as scalars. 8.1.35 allocated ten short-lived Lua tables per ribbon
  -- per frame; on a rough ocean that created avoidable GC pressure/stutter.
  local plx,ply,plz,prx,pry,prz,prevU=nil,nil,nil,nil,nil,nil,nil
  for j=0,4 do
    local u=j/4;local s=(u*2-1)*half
    local taper=0.10+0.90*(sin(pi*u)^0.72)
    local crooked=(hash((seed or 0)+j*37,19+j*11)-0.5)*halfWidth*0.80
    local ccx=cx+ax*s+bx*crooked;local ccz=cz+az*s+bz*crooked
    local w=halfWidth*taper
    local lx,lz=ccx+bx*w,ccz+bz*w;local rx,rz=ccx-bx*w,ccz-bz*w
    local lift=(yLift or 0.09)+(0.025*sin((u+(seed or 0)*0.013)*TAU))
    local ly=waterYAtT(b,Water,h,t,lx,lz)+lift
    local ry=waterYAtT(b,Water,h,t,rx,rz)+lift
    if plx then
      n=foamPush(rows,n,plx,ply,plz,prevU,0,1)
      n=foamPush(rows,n,prx,pry,prz,prevU,1,1)
      n=foamPush(rows,n,rx,ry,rz,u,1,1)
      n=foamPush(rows,n,plx,ply,plz,prevU,0,1)
      n=foamPush(rows,n,rx,ry,rz,u,1,1)
      n=foamPush(rows,n,lx,ly,lz,u,0,1)
    end
    plx,ply,plz,prx,pry,prz,prevU=lx,ly,lz,rx,ry,rz,u
  end
  return n
end

local function foamCurlLip(rows,n,b,Water,h,t,cx,cz,crossX,crossZ,travelX,travelZ,half,rise,reach,strength)
  -- A tapered three-stage folded lip attached to the SAME moving whitecap
  -- track. The old implementation could create a lip at an unrelated fixed
  -- sample on the next frame; this one cannot detach or teleport.
  strength=max(0,min(1,strength or 0));if strength<=0 then return n end
  local vis=sqrt(strength);half=half*vis;rise=rise*strength;reach=reach*vis
  local function pair(frac,height,width)
    local ccx=cx+travelX*reach*frac;local ccz=cz+travelZ*reach*frac
    local hw=half*width
    local lx,lz=ccx-crossX*hw,ccz-crossZ*hw;local rx,rz=ccx+crossX*hw,ccz+crossZ*hw
    return lx,waterYAtT(b,Water,h,t,lx,lz)+0.10+height,lz,rx,waterYAtT(b,Water,h,t,rx,rz)+0.10+height,rz
  end
  local l0x,l0y,l0z,r0x,r0y,r0z=pair(0,0,.70)
  local l1x,l1y,l1z,r1x,r1y,r1z=pair(.34,rise*.62,.96)
  local l2x,l2y,l2z,r2x,r2y,r2z=pair(.76,rise,.82)
  local l3x,l3y,l3z,r3x,r3y,r3z=pair(1.10,rise*.68,.48)
  n=foamQuadCoords(rows,n,l0x,l0y,l0z,r0x,r0y,r0z,r1x,r1y,r1z,l1x,l1y,l1z)
  n=foamQuadCoords(rows,n,l1x,l1y,l1z,r1x,r1y,r1z,r2x,r2y,r2z,l2x,l2y,l2z)
  n=foamQuadCoords(rows,n,l2x,l2y,l2z,r2x,r2y,r2z,r3x,r3y,r3z,l3x,l3y,l3z)
  return n
end

local function whitecapTrackAt(b,Water,t,c,rough)
  local _,_,travelX,travelZ,phaseSpeed=primaryDirection(Water)
  local crossX,crossZ=-travelZ,travelX
  local gx,gz=tonumber(c.gx) or 0,tonumber(c.gz) or 0;local cellSize=tonumber(b and b.cellSize) or 16
  local seed=hash(gx*37+11,gz*53+17);local seed2=hash(gx*71+29,gz*31+43)
  local period=1.45+0.42*seed2
  local q,life=trackPhase(t,period,seed)
  -- Actual Voxel Realism dominant crest speed is ~5-6 px/s. Cap unknown-host
  -- values so one analytic lifetime cannot leave its owning 16px water cell.
  local speed=min(7.0,max(1.8,phaseSpeed))
  local travelSpan=min(cellSize*.66,speed*period)
  local cx=gx*cellSize+cellSize*.5+crossX*(seed2-0.5)*min(3.2,cellSize*.20)+travelX*(q-0.5)*travelSpan
  local cz=gz*cellSize+cellSize*.5+crossZ*(seed2-0.5)*min(3.2,cellSize*.20)+travelZ*(q-0.5)*travelSpan
  local raw=waveRawAtT(Water,cx,cz,t)
  local a=waveRawAtT(Water,cx+travelX*2,cz+travelZ*2,t)
  local z=waveRawAtT(Water,cx-travelX*2,cz-travelZ*2,t)
  local pinch=max(0,2*raw-a-z)
  local crestGate=0.80-0.14*rough;local pinchGate=0.014-0.007*rough
  local crest=smooth01((raw-crestGate)/max(0.045,1-crestGate))
  local sharp=smooth01((pinch-pinchGate)/0.030)
  local strength=life*crest*(0.35+0.65*sharp)
  return cx,cz,strength,q,life,raw,pinch,seed,seed2,travelX,travelZ,crossX,crossZ
end

-- Small executable seam for the temporal-coherence regression test. It returns
-- numbers only and allocates nothing during the renderer's normal path.
C._whitecapTrackAt=whitecapTrackAt
C._foamEnvelope=foamEnvelope

local function buildFoamRows(CW,Water,V3,t,h)
  local mesh=ensureFoamMesh(V3,18000);local tex=imageFrom("foam")
  if not (mesh and tex and mesh.setVertices) then
    C._foamCount=0;C._whitecapQuads,C._curlQuads,C._rapidQuads,C._shoreFoamQuads=0,0,0,0;return
  end
  local rows=C._foamRows;local n=0;local cap=18000
  C._whitecapQuads,C._curlQuads,C._rapidQuads,C._shoreFoamQuads=0,0,0,0
  local _,_,travelX,travelZ=primaryDirection(Water);local crossX,crossZ=-travelZ,travelX
  local waveState=max(0,tonumber(C._liquidWave) or 0)
  for _,b in ipairs(renderBodies(CW)) do
    if n>=cap-120 then break end
    local ice=max(0,min(1,tonumber(b.ice) or 0))
    if not b.loadBearing and not b.presentationFrozen and ice<0.72 and b.cells and #b.cells>0 then
      local bodyH=C._usingPhysicalSurface and physicalWaveHeightForBody(b) or h

      -- Persistent open-water whitecaps. Candidate identity is static; its
      -- position is an analytic crest-following track. Roughness controls how
      -- many tracks are admitted, while crest height/curvature continuously
      -- scale each ribbon rather than switching a square on/off.
      if waveState>0.24 and bodyH>0.8 then
        local rough=min(1,waveState);local density=0.11+0.38*rough
        for _,c in ipairs(b.cells) do
          if n>=cap-180 then break end
          local gate=hash((tonumber(c.gx) or 0)*13+5,(tonumber(c.gz) or 0)*17+7)
          if gate<density then
            local x,z,strength,q,life,raw,pinch,seed,seed2,tx,tz,cxv,czv=whitecapTrackAt(b,Water,t,c,rough)
            if strength>0.012 then
              local half=(1.65+1.45*rough)*(0.82+0.28*seed2)
              local deep=0.34+0.34*rough
              n=foamRibbon(rows,n,b,Water,bodyH,t,x,z,cxv,czv,half,deep,strength,floor(seed*100000),0.09)
              C._whitecapQuads=C._whitecapQuads+1

              local crestGate=0.80-0.14*rough
              local pinchGate=0.014-0.007*rough
              local curlStrength=strength*smooth01((raw-(crestGate+0.055))/0.11)*smooth01((pinch-(pinchGate+0.002))/0.024)
              if waveState>0.44 and seed2>0.36 and curlStrength>0.035 and n<cap-72 then
                local rise=0.56+1.00*rough;local reach=0.74+1.02*rough
                n=foamCurlLip(rows,n,b,Water,bodyH,t,x,z,cxv,czv,tx,tz,half*.88,rise,reach,curlStrength)
                C._curlQuads=C._curlQuads+1
              end
            end
          end
        end
      end

      -- River whitewater is now a moving tapered streak, not a stationary
      -- rectangle. Each streak advects downstream, shrinks to zero, then
      -- restarts invisibly; no cycle boundary can visibly teleport it.
      if (b.kind=="RIVER" or (tonumber(b.rapidness) or 0)>0.35) and n<cap-120 then
        local fx,fz=tonumber(b.flowX) or 0,tonumber(b.flowZ) or 0;local fl=sqrt(fx*fx+fz*fz)
        if fl<0.5 then fx,fz=travelX,travelZ else fx,fz=fx/fl,fz/fl end
        local sx,sz=-fz,fx;local rapid=max(0.35,min(1,tonumber(b.rapidness) or 0.6))
        for _,c in ipairs(b.cells) do
          if n>=cap-48 then break end
          local gx,gz=tonumber(c.gx) or 0,tonumber(c.gz) or 0;local cellSize=tonumber(b.cellSize) or 16;local gate=hash(gx*7+13,gz*11+29)
          if gate<(0.34+0.42*rapid) then
            local seed=hash(gx*41+3,gz*67+19);local period=1.10+0.48*seed
            local q,life=trackPhase(t,period,seed)
            local along=(q-0.5)*(5.0+3.0*rapid)
            local side=(hash(gx*23+17,gz*47+5)-0.5)*2.6
            local x,z=gx*cellSize+cellSize*.5+fx*along+sx*side,gz*cellSize+cellSize*.5+fz*along+sz*side
            local pulse=life*(0.62+0.38*smooth01((waveRawAtT(Water,x,z,t)-0.38)/0.44))
            if pulse>0.012 then
              local len=2.5+3.1*rapid;local wid=0.36+0.62*rapid
              n=foamRibbon(rows,n,b,Water,bodyH,t,x,z,fx,fz,len,wid,pulse,floor(seed*100000)+71,0.10)
              C._rapidQuads=C._rapidQuads+1
            end
          end
        end
      end

      -- Shore break follows stable coastline segments. Static edge admission
      -- replaces the old half-second-bucket random re-roll that literally moved foam
      -- to a different segment every two seconds. Each admitted breaker pulses
      -- smoothly and slides slightly along its own edge.
      local e=surfaceEntryForBody(b,V3)
      if e and e.edges and waveState>0.18 and n<cap-120 then
        for ei,edge in ipairs(e.edges) do
          if n>=cap-48 then break end
          local x0,z0,x1,z1,nx,nz=edge[1],edge[2],edge[3],edge[4],edge[5],edge[6]
          local ex,ez=x1-x0,z1-z0;local el=sqrt(ex*ex+ez*ez);if el>0 then ex,ez=ex/el,ez/el end
          local impact=max(0,-(travelX*nx+travelZ*nz));local chance=0.08+0.30*min(1,waveState)*(0.30+0.70*impact)
          for seg=0,1 do
            local static=hash(ei*3+seg*17,(tonumber(b.id) or 0)*23+11)
            if static<chance then
              local period=1.65+0.85*hash(ei*13+seg*31,(tonumber(b.id) or 0)*7+5)
              local q,life=trackPhase(t,period,static)
              if life>0.012 then
                local mid=4+seg*8+(q-0.5)*1.8;local cx=x0+ex*mid;local cz=z0+ez*mid
                local half=2.5+1.1*impact;local inward=0.48+0.72*impact
                -- Long axis follows the coast; ribbon thickness points inward.
                n=foamRibbon(rows,n,b,Water,bodyH,t,cx+nx*inward*.55,cz+nz*inward*.55,ex,ez,half,inward*.55,life,floor(static*100000)+ei,0.075)
                C._shoreFoamQuads=C._shoreFoamQuads+1
              end
            end
          end
        end
      end
    end
  end
  for i=#rows,n+1,-1 do rows[i]=nil end
  if n>0 then
    local ok=hostTry(mesh.setVertices,mesh,rows,1,n)
    if ok then if mesh.setDrawRange then hostTry(mesh.setDrawRange,mesh,1,n) end;C._foamCount=n;C._foamTexture=tex else C._foamCount=0 end
  else C._foamCount=0 end
end

function C.physicalSurfaceStats()
  local bodies,verts,indices=0,0,0
  for _,e in pairs(C._surfaceEntries) do bodies=bodies+1;verts=verts+(e.vertexCount or 0);indices=indices+(e.indexCount or 0) end
  return {active=C._usingPhysicalSurface==true,bodies=bodies,vertices=verts,indices=indices,foamVertices=C._foamCount or 0,waveHeight=C.currentWaveHeight or 0,
    whitecaps=C._whitecapQuads or 0,curls=C._curlQuads or 0,rapids=C._rapidQuads or 0,shoreFoam=C._shoreFoamQuads or 0}
end
function C.playerBob(state)
  if C._enabled==false then C._bobValue=0;C._bobLast=nil;return 0 end
  local p=state and state.player
  if not (p and p.surfing) then C._bobValue=0;C._bobLast=nil;return 0 end
  local x=tonumber(p.px or p.x);local z=tonumber(p.py or p.y or p.z)
  if not (x and z) then return 0 end
  x,z=x+8,z+8
  -- Ride the actual rendered crest. The cap is below the roughest 8.5px
  -- peak-to-trough sea so first-person heave is readable without being violent.
  local target=max(-4.0,min(4.0,C.waveDisplacementAt(x,z,true)*0.90))
  local now=love and love.timer and love.timer.getTime and love.timer.getTime() or nil
  if not now then C._bobValue=target;return target end
  if C._bobLast==nil then C._bobLast=now;C._bobValue=target;return target end
  local dt=max(0,min(0.12,now-C._bobLast));C._bobLast=now
  local a=1-exp(-dt*8.5);C._bobValue=C._bobValue+(target-C._bobValue)*a
  return C._bobValue
end

-- Returns (replacementLiquidDraws, owns). owns=true with an empty list means
-- all visible water is frozen and the caller must NOT resurrect host tile water.
local function trimDraws(list,n)
  for i=#list,n+1,-1 do list[i]=nil end
end
local function drawRow(list,n,mesh,texture,model,body,stage)
  n=n+1
  local r=list[n]
  if not r then r={};list[n]=r end
  r[1],r[2],r[3],r[4],r[5]=mesh,texture,model,body,stage
  return n,r
end
local function reflectiveTranslation(row,Mat4,y,reuse)
  local m=row and row[3]
  -- Voxel Realism's Water.draw sends the matrix uniform on every draw, so a
  -- stable row-major table can safely be updated in place. Restrict this
  -- zero-GC fast path to the structured host whose relief contract we proved;
  -- unknown Mat4/userdata hosts continue through their own translate().
  if reuse and type(m)=="table" and #m>=16 then
    m[8]=y
    return m
  end
  return Mat4.translate(0,y,0)
end
function C.prepare(original)
  if C._enabled==false then return nil,false end
  -- Stable private-module handles retain 8.1.32's zero-GC hot-path win.
  local CW=C._CW or req("ConnectedWater");local bodies=renderBodies(CW)
  if not (CW and CW.observed and (#bodies>0 or CW.outerSea)) then return nil,false end
  local V3=C._V3 or req("Voxel3D");local Mat4=C._Mat4 or req("Mat4");if not (V3 and Mat4) then return nil,false end
  local waterTex=imageFrom("water") or (original and original[1] and original[1][2])
  local iceTex=imageFrom("ice") or waterTex
  if not waterTex then return nil,false end
  local Water=C._Water or req("Water");if Water then applyWaterDynamics(Water,CW) end
  C._CW,C._V3,C._Mat4,C._Water=CW,V3,Mat4,Water
  local waveH=tonumber(C.currentWaveHeight) or 0;local waveT=waveTimeValue(Water)

  -- One coherent mode per frame. Authored/finite void water and the 8.1.38
  -- outer sea all use the same wave clock. If true physical geometry cannot be
  -- maintained, ordinary bodies retain the proven reflective-relief fallback;
  -- the far sea stays a coarse flat reflective mesh rather than inventing
  -- gameplay water or exposing the host cyan underlay as a second material.
  local physical=C._centeredRelief and Water and love and love.graphics and love.graphics.newMesh and true or false
  local physicalEntries,physicalHeights={},{}
  local hSum,hArea=0,0
  if physical then
    for _,b in ipairs(bodies) do
      if not b.loadBearing then
        local bh=physicalWaveHeightForBody(b);local e=surfaceEntryForBody(b,V3)
        if not (e and updatePhysicalSurface(e,Water,bh,waveT)) then physical=false;break end
        physicalEntries[b],physicalHeights[b]=e,bh
        hSum=hSum+bh*(tonumber(b.area) or 1);hArea=hArea+(tonumber(b.area) or 1)
      end
    end
  end

  local outerEntry,outerH=nil,0
  if CW.outerSea then
    outerEntry=outerSeaEntry(CW.outerSea,V3)
    if not outerEntry then return nil,false end
    outerH=physicalWaveHeightForBody(CW.outerSea)
    if Water then
      if physical then
        if not updateOuterSea(outerEntry,Water,outerH,waveT) then return nil,false end
      else
        -- Reset a previously displaced hot-reload mesh before the host shader
        -- takes relief ownership again.
        updateOuterSea(outerEntry,Water,0,waveT)
      end
    end
  end

  C._usingPhysicalSurface=physical
  if physical and hArea>0 then C.currentWaveHeight=hSum/hArea;waveH=C.currentWaveHeight end
  if Water and C._centeredRelief then
    -- 8.1.91: host water shaders bake WAVE_HEIGHT into their generated source.
    -- Merely assigning WAVE_HEIGHT=0 is insufficient when Battle Art compiled
    -- its native relief shader before Weather FX physical ownership became
    -- ready; that already-compiled 0..H surface can remain visible on top of
    -- the replacement mesh. Invalidate exactly when ownership changes between
    -- host-relief fallback and Weather FX physical relief, then leave the mode
    -- stable so there is no per-frame shader rebuild. Sector changes may still
    -- invalidate normally in applyWaterDynamics; the final value below is zero
    -- before the host recompiles.
    local reliefMode=physical and "weather-fx" or "host"
    local changed=C._hostReliefMode~=reliefMode
    C._hostReliefMode=reliefMode
    Water.WAVE_HEIGHT=physical and 0 or waveH
    if changed and type(Water.invalidate)=="function" then hostTry(Water.invalidate) end
  end

  local liquid,outer,void,ice,skin,shore,pond,beds=C._liquidDraws,C._outerDraws,C._voidDraws,C._iceDraws,C._skinDraws,C._shoreDraws,C._pondDraws,C._pondBedDraws
  local nl,no,nv,ni,ns,nsh,np,nbed=0,0,0,0,0,0,0,0
  local fishBudget=MAX_POND_FISH
  local pondCapable=Water and type(Water.begin)=="function" and type(Water.draw)=="function" and type(Water.finish)=="function"
    and type(V3.endWater)=="function" and love and love.graphics and type(love.graphics.setColor)=="function"

  -- The complete VOID ocean is drawn first and occupies no gameplay cells. Its
  -- large mesh has a root-apron hole plus exact loaded-map holes, so it cannot
  -- double-paint the finite 96px replacement or authored terrain/water.
  if outerEntry then
    -- Outer vertices are centered around -2 already; translate only by tide.
    -- The near physical belt carries +/- wave relief while the far field stays
    -- on the same moving datum and receives fine wave detail in the Water shader.
    local y=tonumber(CW.outerSea.tide) or 0
    no=drawRow(outer,no,outerEntry.mesh,waterTex,Mat4.translate(0,y,0),CW.outerSea)
  end

  for _,b in ipairs(bodies) do
    if b.loadBearing or (b.visualOnly and b.presentationFrozen) then
      local iceMesh=meshForBody(b,V3,192,"iceBlock");if not iceMesh then return nil,false end
      ni=drawRow(ice,ni,iceMesh,iceTex,nil,b)
    else
      local liquidMesh=(physical and physicalEntries[b] and physicalEntries[b].mesh) or meshForBody(b,V3,32,"water")
      if not liquidMesh then return nil,false end
      local bodyWaveH=(physical and physicalHeights[b]) or waveH
      local centreDrop=C._centeredRelief and bodyWaveH*0.5 or 0
      local y=(tonumber(b.tide) or 0)-centreDrop

      if pondCapable and isLivingPond(b) then
        -- Ponds deliberately skip the host's opaque curved-water prepass. They
        -- are drawn later through the same reflective Water shader with alpha,
        -- after their shallow bed and fish have entered the real scene depth.
        local row;np,row=drawRow(pond,np,liquidMesh,waterTex,Mat4.translate(0,y,0),b)
        row[6]=pondAlpha(b)
        local fc=min(fishBudget,pondFishCount(b));row[7]=fc;fishBudget=fishBudget-fc
        local bm=meshForPondBed(b,V3);local bt=imageFrom("pondBed")
        if not (bm and bt) then return nil,false end
        nbed=drawRow(beds,nbed,bm,bt,nil,b)
      else
        local nextIndex=nl+1;local existing=liquid[nextIndex]
        local model=reflectiveTranslation(existing,Mat4,y,C._centeredRelief)
        local row
        nl,row=drawRow(liquid,nl,liquidMesh,waterTex,model,b)
        -- Keep a non-owning view of just synthetic VOID water. This lets the
        -- shared bridge draw Weather FX void water even on a voxel host that
        -- does not expose VoxelScene.drawWater, without redrawing authored
        -- lakes/rivers or creating gameplay authority outside the map.
        if b.visualOnly and b.voidWater then
          nv=nv+1;local vr=void[nv] or {};void[nv]=vr
          for j=1,7 do vr[j]=row[j] end
        end
      end

      if C._centeredRelief and waveH>0.5 then local seal=meshForShoreSeal(b,V3);if seal then nsh=drawRow(shore,nsh,seal,waterTex,nil,b) end end
      local f=max(0,min(0.899,tonumber(b.ice) or 0))
      if f>0.035 then
        local stage=max(1,min(8,floor((f/0.90)*8)+1));local skinTex=iceTextureForStage(stage)
        local skinMesh=meshForBody(b,V3,192,"ice");if skinTex and skinMesh then
          ns=drawRow(skin,ns,skinMesh,skinTex,Mat4.translate(0,(tonumber(b.tide) or 0)+0.045,0),b,stage)
        end
      end
    end
  end
  trimDraws(liquid,nl);trimDraws(outer,no);trimDraws(void,nv);trimDraws(ice,ni);trimDraws(skin,ns);trimDraws(shore,nsh);trimDraws(pond,np);trimDraws(beds,nbed)
  C._pondBodyCount=np;C._pondFishCount=MAX_POND_FISH-fishBudget
  if physical then buildFoamRows(CW,Water,V3,waveT,waveH)
  else C._foamCount=0;C._whitecapQuads,C._curlQuads,C._rapidQuads,C._shoreFoamQuads=0,0,0,0 end
  return liquid,true
end

local function ensureRippleMesh(V3,cap)
  cap=cap or (48*12*6)
  if C.rippleMesh then return C.rippleMesh end
  if not (love and love.graphics and love.graphics.newMesh and V3 and V3.FORMAT) then return nil end
  local ok,m=hostTry(love.graphics.newMesh,V3.FORMAT,cap,"triangles","stream")
  if ok then C.rippleMesh=m end;return C.rippleMesh
end
local function pushRow(rows,n,x,y,z,u,v)
  n=n+1;local r=rows[n];if not r then r={};rows[n]=r end
  r[1],r[2],r[3],r[4],r[5],r[6]=x,y,z,u,v,1
  return n
end
local function drawRipples(CW,V3)
  local rings=CW and CW.rippleState and CW.rippleState() or nil;if not rings or #rings==0 then return end
  local mesh=ensureRippleMesh(V3);local tex=imageFrom("ripple");if not (mesh and tex) then return end
  local rows=C._rippleRows;local n=0;local seg=12
  for _,r in ipairs(rings) do
    local b=r.body
    if b and not b.loadBearing then
      local t=min(1,(r.age or 0)/max(.001,r.life or 1));local rad=.45+t*(2.3+1.2*(r.strength or 0));local wid=.11+.10*(1-t)
      local y=(C.visualSurfaceYAt(r.x,r.z,true) or (-2+(tonumber(b.tide) or 0)))+0.055
      for i=0,seg-1 do
        local a0=i/seg*TAU;local a1=(i+1)/seg*TAU
        local x0,z0=r.x+cos(a0)*rad,r.z+sin(a0)*rad;local x1,z1=r.x+cos(a1)*rad,r.z+sin(a1)*rad
        local q0x,q0z=r.x+cos(a0)*(rad+wid),r.z+sin(a0)*(rad+wid);local q1x,q1z=r.x+cos(a1)*(rad+wid),r.z+sin(a1)*(rad+wid)
        n=pushRow(rows,n,x0,y,z0,0,0);n=pushRow(rows,n,q0x,y,q0z,1,0);n=pushRow(rows,n,q1x,y,q1z,1,1)
        n=pushRow(rows,n,x0,y,z0,0,0);n=pushRow(rows,n,q1x,y,q1z,1,1);n=pushRow(rows,n,x1,y,z1,0,1)
      end
    end
  end
  if n>0 then
    local ok=hostTry(mesh.setVertices,mesh,rows,1,n);if ok then if mesh.setDrawRange then hostTry(mesh.setDrawRange,mesh,1,n) end;V3.draw(mesh,tex,nil) end
  end
end

local function setDrawAlpha(a)
  if not (love and love.graphics and love.graphics.setColor) then return end
  love.graphics.setColor(1,1,1,max(0,min(1,tonumber(a) or 1)))
end
local function restoreDrawColor(old)
  if not (love and love.graphics and love.graphics.setColor) then return end
  if old then love.graphics.setColor(old[1],old[2],old[3],old[4]) else love.graphics.setColor(1,1,1,1) end
end
local function currentDrawColor()
  if love and love.graphics and love.graphics.getColor then local ok,r,g,b,a=hostTry(love.graphics.getColor);if ok then return {r,g,b,a} end end
end
local waterCtx={curve={0,0,0},screen={0,0}}
local function waterContext(V3,reflect,depth)
  local w,h=0,0;if type(V3.size)=="function" then local ok,a,b=hostTry(V3.size);if ok then w,h=a or 0,b or 0 end end
  local curve,screen=waterCtx.curve,waterCtx.screen
  curve[1],curve[2],curve[3]=V3.curveX or 0,V3.curveZ or 0,V3.curveK or 0
  screen[1],screen[2]=w,h
  waterCtx.reflect,waterCtx.depth,waterCtx.vp,waterCtx.eye=reflect,depth,V3.vp,V3.eye
  waterCtx.cell,waterCtx.fov,waterCtx.skyEdge=V3.cell,V3.fovY,V3.skyEdge
  waterCtx.grid=false;waterCtx.lookFlat,waterCtx.descent=V3.lookFlat,V3.descent
  return waterCtx
end
local function drawPondRows(rows,Water)
  local old=currentDrawColor()
  for _,d in ipairs(rows or {}) do setDrawAlpha(d[6] or 0.5);Water.draw(d[1],d[2],d[3]) end
  restoreDrawColor(old)
end

local function drawPondUnderwater(V3,Water)
  local bedTex=imageFrom("pondBed")
  if not bedTex then return false end
  for _,d in ipairs(C._pondBedDraws or {}) do V3.draw(d[1],d[2] or bedTex,d[3]) end
  local mesh=ensureFishMesh(V3);local tex=imageFrom("fish");if not (mesh and tex) then return false end
  local n=buildFishRows(Water,waveTimeValue(Water))
  if n>0 then
    local ok=hostTry(mesh.setVertices,mesh,C._fishRows,1,n);if not ok then return false end
    if mesh.setDrawRange then hostTry(mesh.setDrawRange,mesh,1,n) end
    V3.draw(mesh,tex,nil)
  end
  return true
end

-- Draw authored POND surfaces through the same reflective host Water shader but
-- deliberately without VoxelScene's opaque curved-water depth prepass. The bed
-- and tiny fish are already depth-tested world geometry below the surface, so
-- alpha blending exposes them naturally while terrain/buildings remain opaque.
-- Return false on any host capability failure; DramalessAtmos immediately
-- forwards these rows through the ordinary host water function as a safe opaque
-- fallback rather than leaving a missing pond.
function C.drawPonds(cast,mode)
  if C._enabled==false or #(C._pondDraws or {})==0 then return true end
  local V3,Water=C._V3,C._Water;if not (V3 and Water and type(Water.begin)=="function" and type(Water.draw)=="function" and type(Water.finish)=="function") then return false end
  if not drawPondUnderwater(V3,Water) then return false end
  mode=tostring(mode or "full")
  local enabled=true;if type(Water.enabled)=="function" then local ok,v=hostTry(Water.enabled);enabled=ok and v~=false end
  local done=false
  if mode=="simple" then
    local old=currentDrawColor();local ok=hostTry(function()
      for _,d in ipairs(C._pondDraws) do setDrawAlpha(d[6] or .5);V3.draw(d[1],d[2],d[3]) end
    end);restoreDrawColor(old);return ok
  end
  if enabled and mode=="full" and type(V3.depthReadable)=="function" and type(V3.beginWater)=="function" and type(V3.endWater)=="function" then
    local okDepth,depthOK=hostTry(V3.depthReadable)
    if okDepth and depthOK then
      local okBegin,mirror,depth=hostTry(V3.beginWater,cast)
      if okBegin and mirror and depth then
        local okShader,active=hostTry(Water.begin,waterContext(V3,mirror,depth),false)
        if okShader and active then
          local okDraw=hostTry(drawPondRows,C._pondDraws,Water);hostTry(Water.finish);done=okDraw
        end
      end
      hostTry(V3.endWater)
    end
  end
  if enabled and not done then
    local okShader,active=hostTry(Water.begin,waterContext(V3,nil,nil),true)
    if okShader and active then
      local okDraw=hostTry(drawPondRows,C._pondDraws,Water);hostTry(Water.finish);done=okDraw
    end
    if type(V3.endWater)=="function" then hostTry(V3.endWater) end
  end
  if not done then
    -- Last-resort translucent scene-shader fallback. If this itself fails the
    -- caller will use the host's ordinary opaque water path.
    local old=currentDrawColor();local ok=hostTry(function()
      for _,d in ipairs(C._pondDraws) do setDrawAlpha(d[6] or .5);V3.draw(d[1],d[2],d[3]) end
    end);restoreDrawColor(old);done=ok
  end
  return done
end

function C.pondDraws() return C._pondDraws end
function C.outerDraws() return C._outerDraws end

-- Voxel Nexus fast path for the presentation-only far VOID ocean. 8.1.45
-- sent this mesh through the ordinary scene shader. That avoided the second
-- beginWater/framebuffer copy, but it also discarded the near water's Fresnel,
-- reflected sky/sun/moon and wave-normal material, producing an obvious
-- bright-blue -> dark-teal seam at the 96px handoff.
--
-- Use the host's SKY-only water shader instead. This is the SAME optical water
-- material used by the full pass (base art, day tint, Fresnel, sky ramp,
-- sun/moon body reflection and the exact live wave-normal phase), but by design
-- it needs neither the frame/depth copy nor the screen-space reflection march.
-- Weather FX already owns physical displacement and has centered host relief at
-- zero, so this adds no second geometric surface. The finite 96px handoff and
-- every authored lake/river remain on the normal FULL reflective `repl` path.
local function drawRowsSimple(rows)
  local V3=C._V3
  if not (V3 and type(V3.draw)=="function") then return false end
  local n=0
  local ok=hostTry(function()
    for _,d in ipairs(rows or {}) do V3.draw(d[1],d[2],d[3]);n=n+1 end
  end)
  return ok and n>0
end

-- Draw Weather FX physical rows through the host's lightweight SKY-only water
-- material. `prepass=true` reproduces Voxel Nexus' curved-water depth prepass
-- for near/authored water. The huge synthetic outer ocean intentionally skips
-- that redundant geometry prepass: it has no nearer water body to self-occlude
-- and this is the LOD that removes the expensive distant-ocean workload.
local function drawRowsSky(rows,prepass)
  if C._enabled==false or #(rows or {})==0 then return false end
  local V3,Water=C._V3,C._Water
  if not (V3 and Water and type(Water.begin)=="function" and type(Water.draw)=="function" and type(Water.finish)=="function") then return false end
  local enabled=true
  if type(Water.enabled)=="function" then local ok,v=hostTry(Water.enabled);enabled=ok and v~=false end
  if not enabled then return drawRowsSimple(rows) end
  if prepass and (tonumber(V3.curveK) or 0)>0 and type(V3.draw)=="function" then
    local ok=hostTry(function() for _,d in ipairs(rows) do V3.draw(d[1],d[2],d[3]) end end)
    if not ok then return false end
  end
  local ctx=waterContext(V3,nil,nil)
  local Grid=req("VoxelGrid")
  if Grid and type(Grid.enabled)=="function" then local ok,v=hostTry(Grid.enabled);if ok then ctx.grid=v and true or false end end
  local okBegin,active=hostTry(Water.begin,ctx,true)
  if not (okBegin and active) then return false end
  local n=0
  local okDraw=hostTry(function()
    for _,d in ipairs(rows) do Water.draw(d[1],d[2],d[3]);n=n+1 end
  end)
  hostTry(Water.finish)
  if type(V3.endWater)=="function" then hostTry(V3.endWater) end
  return okDraw and n>0
end

function C.drawRowsSimple(rows) return drawRowsSimple(rows) end
function C.drawRowsSky(rows,prepass) return drawRowsSky(rows,prepass~=false) end

function C.drawOuterFast(mode)
  if C._enabled==false or #(C._outerDraws or {})==0 then return false end
  mode=tostring(mode or "sky")
  local ok
  if mode=="simple" then ok=drawRowsSimple(C._outerDraws)
  else ok=drawRowsSky(C._outerDraws,false) end
  if ok then
    C._outerFastDraws=(C._outerFastDraws or 0)+1
    if mode~="simple" then C._outerSkyDraws=(C._outerSkyDraws or 0)+1 end
    return true
  end
  return false
end

function C.drawStandaloneVoid(cast)
  if C._enabled==false then return false end
  local CW=C._CW or req("ConnectedWater")
  if not (CW and CW.observed and CW.outerSea) then return false end
  if not C._V3 then local _,owned=C.prepare(nil);if not owned then return false end end
  local V3=C._V3
  if not V3 then return false end
  local n=0
  -- Draw against the live scene depth. The normal host drawWater wrapper is the
  -- reflective first-class path; this compatibility seam is intentionally
  -- simpler so a renderer without drawWater still gets the SAME physical wave
  -- meshes without risking a late mirror pass over already-drawn actors.
  local ok=hostTry(function()
    for _,d in ipairs(C._outerDraws or {}) do V3.draw(d[1],d[2],d[3]);n=n+1 end
    for _,d in ipairs(C._voidDraws or {}) do V3.draw(d[1],d[2],d[3]);n=n+1 end
  end)
  return ok and n>0
end
function C.voidDraws() return C._voidDraws end
function C.hasVoidWater()
  local CW=C._CW or req("ConnectedWater")
  return C._enabled~=false and CW and CW.observed and CW.outerSea~=nil
end

function C.pondStats() return {bodies=C._pondBodyCount or 0,fish=C._pondFishCount or 0,visibleFish=C._pondFishVisible or 0,maxFish=MAX_POND_FISH} end
function C.outerSeaStats()
  local e=C._outerEntry;return {active=e~=nil,range=(C._CW and C._CW.outerSea and C._CW.outerSea.range) or 0,vertices=e and e.vertexCount or 0,indices=e and e.indexCount or 0,dynamicVertices=e and e.dynamicCount or 0,fastDraws=C._outerFastDraws or 0,skyDraws=C._outerSkyDraws or 0}
end

function C.drawAfterWater()
  if C._enabled==false then return end
  local V3,CW=C._V3,C._CW;if not (V3 and CW) then return end
  -- A narrow below-datum perimeter seal closes the space exposed when a true
  -- trough falls below the cartridge's -2 shoreline wall. It never covers
  -- land and never participates in collision; it exists only behind the bank.
  for _,d in ipairs(C._shoreDraws) do V3.draw(d[1],d[2],d[3]) end
  -- Whitecaps, curling crest lips, rapids and shore break are genuine 3D
  -- geometry slightly above the sampled wave surface, depth-tested with the
  -- world instead of painted onto the screen.
  if C._foamCount and C._foamCount>0 and C.foamMesh and C._foamTexture then V3.draw(C.foamMesh,C._foamTexture,nil) end
  -- Thin freezing skin remains above the live reflective water until the body
  -- becomes load-bearing. This exposes the progressive thermodynamics visually
  -- instead of hiding 0-89% freeze and then popping to one opaque sheet.
  for _,d in ipairs(C._skinDraws) do V3.draw(d[1],d[2],d[3]) end
  -- Load-bearing ice is wave-free, depth-tested world geometry. Large-scale UVs,
  -- translucent clear/frost variation, trapped-air flecks and branching fractures
  -- keep it reading as frozen water rather than a pale tiled floor.
  for _,d in ipairs(C._iceDraws) do V3.draw(d[1],d[2],d[3]) end
  drawRipples(CW,V3)
end

-- Live ownership handoff used by WATER STYLE. Disabling first restores every
-- host Water tuning value we touched, then leaves the native draw list entirely
-- alone. Re-enabling does not reuse stale host-specific geometry/uniform state;
-- the next prepare() rebuilds from the currently observed connected bodies.
function C.setEnabled(enabled)
  enabled=enabled~=false
  if C._enabled==enabled then return false end
  if not enabled then
    C.invalidate()
    C._enabled=false
  else
    C._enabled=true
  end
  return true
end
function C.enabled() return C._enabled~=false end

function C.invalidate()
  -- Restore the host's own water tuning before discarding our renderer state.
  -- This matters for hot unload/reload: Weather FX must never leave Voxel
  -- Realism with our prevailing-wind wave train after the mod is gone.
  local Water=C._Water or req("Water");local q=C._origDynamics
  if Water and q then
    Water.WAVE_TRAINS=Water.WAVE_TRAINS or {}
    for i,t in ipairs(q.trains or {}) do Water.WAVE_TRAINS[i]=copy4(t) end
    for i=#(q.trains or {})+1,#Water.WAVE_TRAINS do Water.WAVE_TRAINS[i]=nil end
    if q.height~=nil then Water.WAVE_HEIGHT=q.height end
    Water.WAVE_SWELL=q.swell and copy4(q.swell) or nil
    Water.WAVE_BEND=q.bend and copy4(q.bend) or nil
    if q.fps~=nil then Water.WAVE_FPS=q.fps end
    if q.pixels~=nil then Water.WAVE_PIXELS_PER_STEP=q.pixels end
    if q.slope~=nil then Water.WAVE_SLOPE=q.slope end
    if q.slopeLean~=nil then Water.WAVE_SLOPE_LEAN=q.slopeLean end
    if Water.invalidate then hostTry(Water.invalidate) end
  end
  C._origDynamics=nil;C.currentWaveHeight=0;C._Water=nil;C._CW=nil;C._V3=nil;C._Mat4=nil;C._liquidWave=nil;C._centeredRelief=nil;C._bobValue=0;C._bobLast=nil;C._usingPhysicalSurface=false
  for _,q in pairs(C.meshes) do if q.mesh and q.mesh.release then hostTry(q.mesh.release,q.mesh) end end;C.meshes={}
  for _,e in pairs(C._surfaceEntries or {}) do if e.mesh and e.mesh.release then hostTry(e.mesh.release,e.mesh) end end;C._surfaceEntries={}
  if C._outerEntry and C._outerEntry.mesh and C._outerEntry.mesh.release then hostTry(C._outerEntry.mesh.release,C._outerEntry.mesh) end;C._outerEntry=nil
  if C.rippleMesh and C.rippleMesh.release then hostTry(C.rippleMesh.release,C.rippleMesh) end;C.rippleMesh=nil
  if C.foamMesh and C.foamMesh.release then hostTry(C.foamMesh.release,C.foamMesh) end;C.foamMesh=nil;C._foamCount=0;C._foamTexture=nil
  if C.fishMesh and C.fishMesh.release then hostTry(C.fishMesh.release,C.fishMesh) end;C.fishMesh=nil
  C._whitecapQuads,C._curlQuads,C._rapidQuads,C._shoreFoamQuads=0,0,0,0
  for k in pairs(C._textureSlots or {}) do local t=C[k];if t and t.release then hostTry(t.release,t) end;C[k]=nil;C[k.."Size"]=nil end
  C._textureSlots={}
  C.lastSector,C.lastWaveBucket=nil,nil
  C._pondFishCount,C._pondBodyCount,C._pondFishVisible=0,0,0
  C._outerFastDraws=0
  C._iceDraws,C._skinDraws,C._liquidDraws,C._outerDraws,C._voidDraws,C._shoreDraws,C._pondDraws,C._pondBedDraws={},{},{},{},{},{},{},{}
  C._fishRows={}
end
C._waveSampleAtT=waveSampleAtT
return C
