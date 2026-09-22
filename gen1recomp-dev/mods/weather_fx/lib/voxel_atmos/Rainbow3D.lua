-- Depth-tested primary rainbow for strict voxel/FPV presentation.
-- Geometry is a far-sky ribbon around the antisolar point; terrain/buildings
-- can occlude it and the cloud/weather pass is drawn afterward, so cloud banks
-- naturally cover/soften it instead of the arc floating on top of the world.
local V=...
local R3={verts={},capacity=0,mesh=nil,shader=nil,lastVertices=0}
local sin,cos,sqrt,rad=math.sin,math.cos,math.sqrt,math.rad
local COLORS={{1,.18,.12},{1,.47,.08},{1,.83,.12},{.30,.85,.24},{.18,.55,1},{.30,.28,.92},{.58,.25,.85}}
local SHADER=[[
#ifdef VERTEX
varying vec4 vProjectedColor;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vProjectedColor = VertexColor;
  vec4 clip = transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
  clip.z = clip.w;
  return clip;
}
#endif
#ifdef PIXEL
varying vec4 vProjectedColor;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) { return vProjectedColor * color; }
#endif
]]
local function req(n) local ok,m=pcall(V.require,n);return ok and m or nil end
local function norm(x,y,z) local l=sqrt(x*x+y*y+z*z);if l<1e-8 then return nil end;return x/l,y/l,z/l end
local function basis(ax,ay,az)
  local ux,uy,uz=az,0,-ax;local l=sqrt(ux*ux+uz*uz)
  if l<1e-5 then ux,uy,uz=1,0,0 else ux,uz=ux/l,uz/l end
  local vx=ay*uz-az*uy;local vy=az*ux-ax*uz;local vz=ax*uy-ay*ux
  vx,vy,vz=norm(vx,vy,vz);return ux,uy,uz,vx,vy,vz
end
local function dir(ax,ay,az,ux,uy,uz,vx,vy,vz,r,t)
  local cr,sr,ct,st=cos(r),sin(r),cos(t),sin(t)
  return ax*cr+(ux*ct+vx*st)*sr,ay*cr+(uy*ct+vy*st)*sr,az*cr+(uz*ct+vz*st)*sr
end
local function push(v,n,x,y,r,g,b,a)
  n=n+1;local q=v[n];if not q then q={0,0,0,0,0,0,0,0};v[n]=q end
  q[1],q[2],q[3],q[4],q[5],q[6],q[7],q[8]=x,y,0,0,r,g,b,a;return n
end
local function tri(v,n,a,b,c,col,alpha)
  n=push(v,n,a[1],a[2],col[1],col[2],col[3],alpha)
  n=push(v,n,b[1],b[2],col[1],col[2],col[3],alpha)
  return push(v,n,c[1],c[2],col[1],col[2],col[3],alpha)
end
local function shader()
  if R3.shader~=nil then return R3.shader or nil end
  if not (love and love.graphics and love.graphics.newShader) then R3.shader=false;return nil end
  local ok,s=pcall(love.graphics.newShader,SHADER);R3.shader=ok and s or false;return R3.shader or nil
end
function R3.draw(Voxel3D)
  local R=req("Rainbow");local state=R and R.state and R.state() or nil;local sun=state and state.sun;local alpha=state and tonumber(state.alpha) or 0
  if alpha<.01 or not sun or not (Voxel3D and Voxel3D.vp and love and love.graphics) then R3.lastVertices=0;return false end
  local NS=req("NightSky");if not (NS and NS.projectDirection) then return false end
  local w,h=160,144;if Voxel3D.size then local ok,a,b=pcall(Voxel3D.size);if ok then w,h=tonumber(a) or w,tonumber(b) or h end end
  local ax,ay,az=norm(-(tonumber(sun.dx) or 0),-(tonumber(sun.dy) or 0),-(tonumber(sun.dz) or 0));if not ax then return false end
  local ux,uy,uz,vx,vy,vz=basis(ax,ay,az);local verts=R3.verts;local n=0;local seg=96
  -- Red is the outer/larger angular band, violet the inner band.
  for bi=1,#COLORS do
    local outer=rad(42.15-(bi-1)*.245);local inner=outer-rad(.235);local col=COLORS[bi]
    local bandA=alpha*(.18+.025*(#COLORS-bi))
    local prev=nil
    for i=0,seg do
      local t=(i/seg)*math.pi*2
      local x1,y1,z1=dir(ax,ay,az,ux,uy,uz,vx,vy,vz,outer,t)
      local x2,y2,z2=dir(ax,ay,az,ux,uy,uz,vx,vy,vz,inner,t)
      local p1x,p1y,p2x,p2y
      if y1>-.015 and y2>-.015 then p1x,p1y=NS.projectDirection(Voxel3D,x1,y1,z1,w,h);p2x,p2y=NS.projectDirection(Voxel3D,x2,y2,z2,w,h) end
      local cur=(p1x and p2x) and {{p1x,p1y},{p2x,p2y}} or nil
      if prev and cur then n=tri(verts,n,prev[1],prev[2],cur[2],col,bandA);n=tri(verts,n,prev[1],cur[2],cur[1],col,bandA) end
      prev=cur
    end
  end
  for i=n+1,#verts do verts[i]=nil end
  if n<3 then R3.lastVertices=0;return false end
  if not R3.mesh or R3.capacity<n then
    local oldMesh=R3.mesh
    local ok,m=pcall(love.graphics.newMesh,verts,"triangles","stream");if not ok or not m then return false end
    R3.mesh=m;R3.capacity=n
    if oldMesh and oldMesh~=m and oldMesh.release then pcall(oldMesh.release,oldMesh) end
  else
    if not pcall(R3.mesh.setVertices,R3.mesh,verts,1) then return false end
  end
  if R3.mesh.setDrawRange then pcall(R3.mesh.setDrawRange,R3.mesh,1,n) end
  local ps,pd,pw,pb,pa,cr,cg,cb,ca
  pcall(function() ps=love.graphics.getShader() end);pcall(function() pd,pw=love.graphics.getDepthMode() end);pcall(function() pb,pa=love.graphics.getBlendMode() end);pcall(function() cr,cg,cb,ca=love.graphics.getColor() end)
  local sh=shader();if sh then pcall(love.graphics.setShader,sh) else pcall(love.graphics.setShader) end
  pcall(love.graphics.setDepthMode,"lequal",false);pcall(love.graphics.setBlendMode,"alpha","alphamultiply");pcall(love.graphics.setColor,1,1,1,1)
  local ok=pcall(love.graphics.draw,R3.mesh)
  if ps then pcall(love.graphics.setShader,ps) else pcall(love.graphics.setShader) end
  if pd then pcall(love.graphics.setDepthMode,pd,pw) else pcall(love.graphics.setDepthMode,"lequal",true) end
  if pb then pcall(love.graphics.setBlendMode,pb,pa) end;if cr then pcall(love.graphics.setColor,cr,cg,cb,ca) end
  R3.lastVertices=n;return ok
end
function R3.invalidate() if R3.mesh and R3.mesh.release then pcall(R3.mesh.release,R3.mesh) end;R3.mesh=nil;R3.capacity=0;R3.lastVertices=0 end
return R3
