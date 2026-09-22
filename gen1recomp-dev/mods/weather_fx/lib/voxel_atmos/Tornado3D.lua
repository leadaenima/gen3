-- World-space 3D Gale tornado renderer.
-- Procedural geometry only: no texture assets, no per-particle simulation and
-- no persistent GPU uploads. At most three ordinary funnels are expected; the
-- config hard-caps four. Terrain/buildings occlude the translucent funnel via
-- the host depth buffer.
local V = ...
local T3={}
local floor,sin,cos,sqrt,max,min,pi=math.floor,math.sin,math.cos,math.sqrt,math.max,math.min,math.pi
local verts={}; local vertCount=0; local mesh=nil; local meshCap=0; local shader=nil
local FMT={{"VertexPosition","float",3},{"TornadoTint","float",4}}

local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function hash(a,b,c)
  local n=sin((a or 0)*12.9898+(b or 0)*78.233+(c or 0)*37.719)*43758.5453
  return n-floor(n)
end
local function clear() vertCount=0 end
local function push(x,y,z,r,g,b,a)
  vertCount=vertCount+1
  local row=verts[vertCount]
  if not row then row={0,0,0,0,0,0,0};verts[vertCount]=row end
  row[1],row[2],row[3],row[4],row[5],row[6],row[7]=x,y,z,r,g,b,a
end
local function quadS(x1,y1,z1,x2,y2,z2,x3,y3,z3,x4,y4,z4,r,g,b,a)
  push(x1,y1,z1,r,g,b,a);push(x2,y2,z2,r,g,b,a);push(x3,y3,z3,r,g,b,a)
  push(x1,y1,z1,r,g,b,a);push(x3,y3,z3,r,g,b,a);push(x4,y4,z4,r,g,b,a)
end

local function shaderGet()
  if shader~=nil then return shader or nil end
  if not (love and love.graphics and love.graphics.newShader) then shader=false;return nil end
  local ok,s=pcall(love.graphics.newShader,[[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 TornadoTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v){vCol=TornadoTint;return vp*vec4(v.xyz,1.0);}
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){return vCol*color;}
#endif
]])
  shader=(ok and s) or false;return shader or nil
end

local function cloudY(T)
  local ok,C=pcall(V.require,"CinematicAtmos")
  if ok and C and C.precipitationDeck then
    local good,y=pcall(C.precipitationDeck); if good and tonumber(y) then return tonumber(y)+5 end
  end
  return tonumber(T.cloudBase and T.cloudBase()) or 122
end
local function stageGeometry(r,T)
  local top=cloudY(T); local gy=tonumber(r.groundY) or 0
  local form=smooth((tonumber(r.age) or 0)/max(1,tonumber(r.formation) or 8))
  local rope=(r.stage=="rope") and smooth((tonumber(r.ropeAge) or 0)/max(1,tonumber(r.ropeFor) or 12)) or 0
  local bottom
  if r.stage=="forming" then bottom=top-5-(top-gy-5)*form
  elseif r.stage=="rope" then bottom=gy+.25+(top-gy-6)*rope
  else bottom=gy+.25 end
  local alpha=max(.05,form)*(1-rope)
  if r.stage=="pickup" or r.stage=="depart" or r.stage=="transfer" or r.stage=="arrival" or r.stage=="landing" then alpha=1 end
  return bottom,top,alpha,form,rope
end

local function centerAt(r,yf,time)
  -- Keep the ground contact centred on the simulated funnel while letting the
  -- condensation column lean/writhe progressively with height. Real funnels
  -- are rarely perfect vertical cones; the broad wall cloud can be displaced
  -- several metres from the surface circulation.
  local lean=.35+2.85*yf
  local bend=sin(yf*pi)*.85
  return r.x+sin(time*.47+r.id*1.9+yf*4.2)*lean+cos(time*.21+r.id)*bend,
         r.z+cos(time*.41+r.id*2.3+yf*3.7)*lean+sin(time*.19+r.id*.7)*bend
end

local function funnelShell(r,T,time)
  local bottom,top,alpha=stageGeometry(r,T); if top-bottom<2 or alpha<=.01 then return end
  local rings,segs=15,14; local water=clamp(tonumber(r.waterBlend) or 0,0,1)
  for j=0,rings-1 do
    local y0=j/rings;local y1=(j+1)/rings
    local yy0=bottom+(top-bottom)*y0;local yy1=bottom+(top-bottom)*y1
    local c0x,c0z=centerAt(r,y0,time);local c1x,c1z=centerAt(r,y1,time)
    local rr0=(2.1+18.0*(y0^1.18))*(.91+.09*sin(time*2.0+r.id+y0*9))
    local rr1=(2.1+18.0*(y1^1.18))*(.91+.09*sin(time*2.0+r.id+y1*9))
    rr0=rr0*(1+water*(1-y0)*.35);rr1=rr1*(1+water*(1-y1)*.35)
    local shade=.34+.18*y0; local br=.40*(1-water)+.28*water;local bg=.42*(1-water)+.42*water;local bb=.44*(1-water)+.55*water
    local cr,cg,cb,ca=br*shade/.42,bg*shade/.42,bb*shade/.42,alpha*(.085+.08*(1-y0))
    for k=0,segs-1 do
      local a0=(k/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*(1.25-y0*.55)+j*.09
      local a1=((k+1)/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*(1.25-y0*.55)+j*.09
      local b0=(k/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*(1.25-y1*.55)+(j+1)*.09
      local b1=((k+1)/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*(1.25-y1*.55)+(j+1)*.09
      local x0,z0=c0x+cos(a0)*rr0,c0z+sin(a0)*rr0;local x1,z1=c0x+cos(a1)*rr0,c0z+sin(a1)*rr0
      local x2,z2=c1x+cos(b1)*rr1,c1z+sin(b1)*rr1;local x3,z3=c1x+cos(b0)*rr1,c1z+sin(b0)*rr1
      quadS(x0,yy0,z0,x1,yy0,z1,x2,yy1,z2,x3,yy1,z3,cr,cg,cb,ca)
    end
  end
end

local billboardAxes

local function outerSheath(r,T,time)
  local bottom,top,alpha=stageGeometry(r,T); if top-bottom<3 or alpha<=.01 then return end
  if T3._lastLayers then T3._lastLayers.sheath=true end
  local rings,segs=10,12;local water=clamp(tonumber(r.waterBlend) or 0,0,1)
  for j=0,rings-1 do
    local y0=j/rings;local y1=(j+1)/rings
    local yy0=bottom+(top-bottom)*y0;local yy1=bottom+(top-bottom)*y1
    local c0x,c0z=centerAt(r,y0,time);local c1x,c1z=centerAt(r,y1,time)
    local base0=2.4+19.5*(y0^1.24);local base1=2.4+19.5*(y1^1.24)
    local rr0=base0*(1.16+.10*sin(time*.73+r.id+y0*13.0))
    local rr1=base1*(1.16+.10*sin(time*.73+r.id+y1*13.0))
    rr0=rr0*(1+water*(1-y0)*.22);rr1=rr1*(1+water*(1-y1)*.22)
    for k=0,segs-1 do
      if hash(r.id,j*31+k,71)>.24 then
        local a0=(k/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*.36+j*.13
        local a1=((k+1)/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*.36+j*.13
        local b0=(k/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*.36+(j+1)*.13
        local b1=((k+1)/segs)*2*pi+time*(tonumber(r.spin) or 4.5)*.36+(j+1)*.13
        local cr,cg,cb,ca=.50-.12*water,.51-.04*water,.53+.08*water,alpha*(.025+.035*(1-y0))
        quadS(c0x+cos(a0)*rr0,yy0,c0z+sin(a0)*rr0,c0x+cos(a1)*rr0,yy0,c0z+sin(a1)*rr0,
          c1x+cos(b1)*rr1,yy1,c1z+sin(b1)*rr1,c1x+cos(b0)*rr1,yy1,c1z+sin(b0)*rr1,cr,cg,cb,ca)
      end
    end
  end
end

local function wallCloud(r,T,time)
  local bottom,top,alpha=stageGeometry(r,T);if alpha<=.01 then return end
  if T3._lastLayers then T3._lastLayers.wallCloud=true end
  local segs=20;local cx,cz=centerAt(r,1,time);local water=clamp(tonumber(r.waterBlend) or 0,0,1)
  for k=0,segs-1 do
    local a0=(k/segs)*2*pi+time*.16;local a1=((k+1)/segs)*2*pi+time*.16
    local wob0=1+.10*sin(k*1.9+r.id);local wob1=1+.10*sin((k+1)*1.9+r.id)
    local ri=17;local ro0=(34+7*hash(r.id,k,81))*wob0;local ro1=(34+7*hash(r.id,k+1,81))*wob1
    local y0=top-2.4-2.2*hash(r.id,k,82);local y1=top-2.4-2.2*hash(r.id,k+1,82)
    local cr,cg,cb,ca=.34-.04*water,.35,.37+.04*water,alpha*(.045+.025*hash(r.id,k,83))
    quadS(cx+cos(a0)*ri,y0+.5,cz+sin(a0)*ri,cx+cos(a1)*ri,y1+.5,cz+sin(a1)*ri,
      cx+cos(a1)*ro1,y1,cz+sin(a1)*ro1,cx+cos(a0)*ro0,y0,cz+sin(a0)*ro0,cr,cg,cb,ca)
  end
end

local function groundSkirt(r,T,Voxel3D,time)
  local bottom,top,alpha=stageGeometry(r,T);if alpha<=.01 then return end
  local water=clamp(tonumber(r.waterBlend) or 0,0,1);if water>.88 then return end
  if T3._lastLayers then T3._lastLayers.groundSkirt=true end
  local cx,cz=centerAt(r,0,time);local gy=tonumber(r.groundY) or bottom
  for j=1,26 do
    local a=time*(2.2+.7*hash(r.id,j,90))+hash(r.id,j,91)*2*pi
    local rad=4+17*hash(r.id,j,92);local h=.5+4.8*(hash(r.id,j,93)^1.8)
    local x,z=cx+cos(a)*rad,cz+sin(a)*rad;local rx,rz=billboardAxes(Voxel3D,x,z)
    local half=.35+1.05*hash(r.id,j,94);local ca=alpha*(1-water)*(.08+.16*hash(r.id,j,95))
    quadS(x-rx*half,gy,z-rz*half,x+rx*half,gy,z+rz*half,x+rx*half,gy+h,z+rz*half,x-rx*half,gy+h,z-rz*half,.30,.26,.21,ca)
  end
end

local function waterSprayBase(r,T,Voxel3D,time)
  local bottom,top,alpha=stageGeometry(r,T);if alpha<=.01 then return end
  local water=clamp(tonumber(r.waterBlend) or 0,0,1);if water<.04 then return end
  if T3._lastLayers then T3._lastLayers.waterSpray=true end
  local cx,cz=centerAt(r,0,time);local gy=tonumber(r.groundY) or bottom;local segs=24
  for ring=1,3 do
    local ri=2.5+(ring-1)*4;local ro=ri+4.8+ring*1.7;local lift=.10+(ring-1)*.23;local phase=time*(1.65+.34*ring)+r.id*.71
    local cr,cg,cb,ca=.55+.08*ring,.76+.04*ring,.90+.02*ring,alpha*water*(.095+.035*ring)
    for k=0,segs-1 do
      local a0=(k/segs)*2*pi+phase;local a1=((k+1)/segs)*2*pi+phase
      local wob0=1+.13*sin(k*1.73+time*2.2+ring);local wob1=1+.13*sin((k+1)*1.73+time*2.2+ring)
      quadS(cx+cos(a0)*ri,gy+lift,cz+sin(a0)*ri,cx+cos(a1)*ri,gy+lift,cz+sin(a1)*ri,
        cx+cos(a1)*ro*wob1,gy+lift+.12,cz+sin(a1)*ro*wob1,cx+cos(a0)*ro*wob0,gy+lift+.12,cz+sin(a0)*ro*wob0,cr,cg,cb,ca)
    end
  end
  for j=1,40 do
    local h=hash(r.id,j,141);local a=time*(4.5+1.8*hash(r.id,j,142))+h*2*pi;local rad=3.5+15.5*hash(r.id,j,143);local rise=.3+9*(hash(r.id,j,144)^1.35)
    local x,z=cx+cos(a)*rad,cz+sin(a)*rad;local rx,rz=billboardAxes(Voxel3D,x,z);local half=.16+.48*hash(r.id,j,145);local ca=alpha*water*(.13+.25*hash(r.id,j,146))
    quadS(x-rx*half,gy,z-rz*half,x+rx*half,gy,z+rz*half,x+rx*half,gy+rise,z+rz*half,x-rx*half,gy+rise,z-rz*half,.66,.84,.95,ca)
  end
end

local function helix(r,T,time)
  local bottom,top,alpha=stageGeometry(r,T); if alpha<=.01 then return end
  local water=clamp(tonumber(r.waterBlend) or 0,0,1)
  for strand=1,4 do
    local pAx,pAy,pAz,pBx,pBy,pBz=nil,nil,nil,nil,nil,nil
    for j=0,22 do
      local yf=j/22;local y=bottom+(top-bottom)*yf;local cx,cz=centerAt(r,yf,time)
      local rad=2.8+19*yf^1.15
      local a=time*(tonumber(r.spin) or 4.5)*(1.65-yf*.55)+yf*pi*7+strand*pi*.5+r.id
      local x,z=cx+cos(a)*rad,cz+sin(a)*rad
      local tang=.60+.55*yf;local ax,az=cos(a+pi*.5)*tang,sin(a+pi*.5)*tang
      local Ax,Ay,Az=x-ax,y-.34,z-az;local Bx,By,Bz=x+ax,y+.34,z+az
      if pAx then
        local cr,cg,cb,ca=.68-.18*water,.69-.08*water,.70+.12*water,alpha*(.12+.11*(1-yf))
        quadS(pAx,pAy,pAz,pBx,pBy,pBz,Bx,By,Bz,Ax,Ay,Az,cr,cg,cb,ca)
      end
      pAx,pAy,pAz,pBx,pBy,pBz=Ax,Ay,Az,Bx,By,Bz
    end
  end
end

billboardAxes=function(Voxel3D,x,z)
  local ex,ez=(Voxel3D.eye and Voxel3D.eye[1]) or x+1,(Voxel3D.eye and Voxel3D.eye[3]) or z
  local dx,dz=ex-x,ez-z;local l=sqrt(dx*dx+dz*dz);if l<1e-4 then return 1,0 end
  dx,dz=dx/l,dz/l;return dz,-dx
end
local function debris(r,T,Voxel3D,time)
  local bottom,top,alpha=stageGeometry(r,T);if alpha<=.01 then return end
  if T3._lastLayers then T3._lastLayers.debris=true end
  local water=clamp(tonumber(r.waterBlend) or 0,0,1)
  for j=1,42 do
    local h=hash(r.id,j,3);local yf=.03+h*.62;local y=bottom+(top-bottom)*yf
    local a=time*((tonumber(r.spin) or 4.5)*(1.85-yf*.7))+hash(r.id,j,8)*2*pi
    local rad=(4+14*yf)*(1+hash(r.id,j,9)*.5)
    local cx,cz=centerAt(r,yf,time);local x,z=cx+cos(a)*rad,cz+sin(a)*rad
    local rx,rz=billboardAxes(Voxel3D,x,z);local half=.18+hash(r.id,j,12)*.58
    local cr,cg,cb,ca
    if water>.55 and yf<.68 then cr,cg,cb,ca=.60,.78,.90,alpha*water*(.18+.22*hash(j,r.id,2))
    elseif water>.15 and yf<.44 then cr,cg,cb,ca=.58,.73,.82,alpha*water*(.16+.18*hash(j,r.id,2))
    else cr,cg,cb,ca=.31,.27,.22,alpha*(1-water*.82)*(.22+.20*hash(j,r.id,5)) end
    quadS(x-rx*half,y-half,z-rz*half,x+rx*half,y-half,z+rz*half,x+rx*half,y+half,z+rz*half,x-rx*half,y+half,z-rz*half,cr,cg,cb,ca)
  end
  if water>.02 then
    for j=1,24 do
      local yf=hash(r.id,j,31)*.42;local y=bottom+.15+(top-bottom)*yf
      local a=time*6.2+hash(r.id,j,34)*2*pi+yf*8
      local rad=3+11*(1-yf)*hash(r.id,j,38);local cx,cz=centerAt(r,yf,time)
      local x,z=cx+cos(a)*rad,cz+sin(a)*rad;local rx,rz=billboardAxes(Voxel3D,x,z);local half=.22+hash(j,r.id,40)*.45;local ca=alpha*water*(.10+.22*(1-yf))
      quadS(x-rx*half,y-half,z-rz*half,x+rx*half,y-half,z+rz*half,x+rx*half,y+half,z+rz*half,x-rx*half,y+half,z-rz*half,.60,.78,.90,ca)
    end
  end
end

function T3.draw(Voxel3D)
  local T=V.require("Tornado");local list=T and T.renderState and T.renderState() or nil
  if type(list)~="table" or #list==0 then return false end
  if not (Voxel3D and Voxel3D.vp and love and love.graphics and love.graphics.newMesh) then return false end
  clear();local time=0
  local okS,S=pcall(V.require,"WeatherState");if okS and S then time=tonumber(S.elapsed) or 0 end
  T3._lastLayers={shell=false,sheath=false,wallCloud=false,groundSkirt=false,waterSpray=false,debris=false}
  for i=1,#list do
    local r=list[i]
    if not r.offscreen then
      local rt=tonumber(r.age) or time
      funnelShell(r,T,rt);T3._lastLayers.shell=true
      outerSheath(r,T,rt)
      wallCloud(r,T,rt)
      helix(r,T,rt)
      groundSkirt(r,T,Voxel3D,rt)
      waterSprayBase(r,T,Voxel3D,rt)
      debris(r,T,Voxel3D,rt)
    end
  end
  T3._lastVertexCount=vertCount
  if vertCount<3 then return false end
  if not mesh or meshCap<vertCount then
    -- Grow in small 256-vertex pages instead of reserving a fixed 4096 rows for
    -- every first funnel. A mature waterspout is ~3.5K rows, so this trims VRAM
    -- while preserving every vertex and still avoids per-frame reallocations.
    local cap=max(1024,floor((vertCount+255)/256)*256)
    local ok,m=pcall(love.graphics.newMesh,FMT,cap,"triangles","dynamic");if not ok or not m then return false end
    local old=mesh;mesh,meshCap=m,cap
    if old and old~=m and old.release then pcall(old.release,old) end
  end
  pcall(mesh.setVertices,mesh,verts,1,vertCount);if mesh.setDrawRange then pcall(mesh.setDrawRange,mesh,1,vertCount) end
  local sh=shaderGet();if not sh then return false end
  pcall(love.graphics.setBlendMode,"alpha","alphamultiply");pcall(love.graphics.setDepthMode,"lequal",false)
  local began=false;if Voxel3D.beginEffect then began=Voxel3D.beginEffect(sh) end;if not began then pcall(love.graphics.setShader,sh) end
  pcall(sh.send,sh,"vp","row",Voxel3D.vp);pcall(love.graphics.setColor,1,1,1,1);pcall(love.graphics.draw,mesh)
  if Voxel3D.endEffect then pcall(Voxel3D.endEffect) else pcall(love.graphics.setShader) end
  pcall(love.graphics.setDepthMode,"lequal",true)
  return true
end

function T3.geometryStatus() return tonumber(T3._lastVertexCount) or 0,T3._lastLayers or {} end
function T3.invalidate()
  if mesh and mesh.release then pcall(mesh.release,mesh) end
  if shader and shader~=false and shader.release then pcall(shader.release,shader) end
  mesh=nil;meshCap=0;shader=nil;T3._lastVertexCount=0;T3._lastLayers=nil
  -- Hard invalidation is the point where retained row capacity should return to
  -- the allocator too; active frames reuse rows and therefore allocate nothing.
  verts={};vertCount=0
end
return T3
