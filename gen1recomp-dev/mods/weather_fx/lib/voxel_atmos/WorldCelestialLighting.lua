-- WorldCelestialLighting — terrain-conforming cloud shadows from real 3D clouds.
--
-- Clouds already live in persistent world coordinates. This pass projects a
-- bounded set of soft shadow tiles from those cloud centres onto actual voxel
-- terrain using the same celestial light shear as the host shadow rig. The
-- camera is never used to choose shadow positions; it only views them.

local V = ...
local L = { _drawn=0, _patches=0 }
local floor,max,min = math.floor,math.max,math.min
local TILE=16

local FMT={{"VertexPosition","float",3},{"VertexColor","float",4}}
local shader,mesh,cap=nil,nil,0
local verts={}

local function root(name) local ok,m=pcall(V.require,name); if ok then return m end end
local function dims(map)
  if not map then return 0,0 end
  local w,h=tonumber(map.widthCells),tonumber(map.heightCells)
  if (not w or w<=0) and map.def then local q=tonumber(map.def.width); if q then w=q*2 end end
  if (not h or h<=0) and map.def then local q=tonumber(map.def.height); if q then h=q*2 end end
  return max(0,floor(w or 0)),max(0,floor(h or 0))
end
local function regions(map,neighbors)
  local out={}
  local function add(m,ox,oz)
    local w,h=dims(m); if m and w>0 and h>0 then out[#out+1]={map=m,ox=ox or 0,oz=oz or 0,w=w,h=h} end
  end
  add(map,0,0)
  for _,nb in ipairs(neighbors or {}) do if nb and nb.map then add(nb.map,nb.ox or 0,nb.oy or nb.oz or 0) end end
  return out
end
local function regionFor(rs,x,z)
  for i=1,#rs do local r=rs[i]
    local cx=floor((x-r.ox)/TILE); local cz=floor((z-r.oz)/TILE)
    if cx>=0 and cz>=0 and cx<r.w and cz<r.h then return r,cx,cz end
  end
end
local function groundAt(r,cx,cz)
  local VS=root("VoxelScene")
  if VS and VS.groundAt then local ok,y=pcall(VS.groundAt,r.map,cx,cz); if ok and type(y)=="number" then return y+.10 end end
  return .10
end
local function push(x,y,z,hx,hz,a,angle)
  local n=#verts
  local ca,sa=math.cos(tonumber(angle) or 0),math.sin(tonumber(angle) or 0)
  local function v(lx,lz)
    -- Cloud descriptors carry a real world-space orientation. Rotate the
    -- terrain mask with the same body instead of painting axis-aligned tiles.
    local px=x+lx*ca+lz*sa; local pz=z-lx*sa+lz*ca
    n=n+1; local t=verts[n] or {0,0,0,0,0,0,0}; verts[n]=t
    t[1],t[2],t[3]=px,y,pz; t[4],t[5],t[6],t[7]=0.02,0.025,0.04,a
  end
  v(-hx,-hz); v(hx,-hz); v(hx,hz)
  v(-hx,-hz); v(hx,hz); v(-hx,hz)
end
local function ensureShader()
  if shader then return shader end
  if not (love and love.graphics and love.graphics.newShader) then return nil end
  local ok,s=pcall(love.graphics.newShader,[[
    varying vec4 vColor;
#ifdef VERTEX
    uniform mat4 vp; attribute vec4 VertexColor;
    vec4 position(mat4 transform_projection, vec4 vertex_position){vColor=VertexColor; return vp*vertex_position;}
#endif
#ifdef PIXEL
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc){return vColor*color;}
#endif
  ]]); if ok then shader=s end; return shader
end
local function upload()
  local n=#verts; if n<3 then return nil end
  if not mesh or cap<n then
    cap=floor(n*1.35)+48
    local ok,m=pcall(love.graphics.newMesh,FMT,cap,"triangles","stream"); if not ok then return nil end; mesh=m
  end
  local ok=pcall(mesh.setVertices,mesh,verts,1,n)
  if not ok then return nil end
  pcall(mesh.setDrawRange,mesh,1,n)
  return mesh
end

function L.draw(Voxel3D,frame,clouds,map,neighbors)
  L._drawn,L._patches=0,0
  for i=#verts,1,-1 do verts[i]=nil end
  if not (Voxel3D and Voxel3D.vp and map and type(clouds)=="table" and #clouds>0) then return false end
  local E=root("CelestialEngine"); local st=E and E.state and E.state()
  local strength=st and tonumber(st.cloudShadowStrength) or 0
  if strength<=.015 then return false end
  local kx,kz=0,0
  if E and E.shadowRig then local a,b=E.shadowRig(); kx,kz=tonumber(a) or 0,tonumber(b) or 0 end
  local rs=regions(map,neighbors); if #rs==0 then return false end
  local maxClouds=math.min(#clouds,18)
  for i=1,maxClouds do
    local c=clouds[i]
    local cy=tonumber(c.cy) or 0
    -- Shadow displacement from cloud altitude down to the world plane.
    local sx=(c.cx or 0)+kx*cy; local sz=(c.cz or 0)+kz*cy
    local bodyX=max(TILE,math.min(132,tonumber(c._bodySx) or (c.spanX or 50)*1.22))
    local bodyZ=max(TILE,math.min(106,tonumber(c._bodySz) or (c.spanZ or 36)*1.18))
    local fade=math.max(0,math.min(1,c.fadeAlpha or 1))
    local angle=tonumber(c.angle) or 0
    local ca,sa=math.cos(angle),math.sin(angle)
    local kind=tonumber(c.kind) or 1
    -- Match the same four macro lobes used by CinematicAtmos cloud occlusion.
    -- This keeps the map-wide direct-light baseline regional while the actual
    -- terrain remains bright only where the projected cloud body is absent.
    local lobes={
      {0,0,.55,.56,.26},
      {-bodyX*.46,bodyZ*.05,.43,.43,.20},
      { bodyX*.44,-bodyZ*.06,.42,.45,.20},
      {0,bodyZ*(kind==0 and .25 or kind==2 and .18 or .31),kind==0 and .50 or kind==2 and .34 or .40,kind==0 and .34 or kind==2 and .34 or .37,.18},
    }
    for j=1,#lobes do
      local q=lobes[j]; local ox,oz=q[1],q[2]
      local px=sx+ox*ca+oz*sa; local pz=sz-ox*sa+oz*ca
      local r,cx,cz=regionFor(rs,px,pz)
      if r then
        local y=groundAt(r,cx,cz)
        local alpha=math.min(.46,strength*fade*q[5])
        if alpha>.004 then
          push(px,y,pz,bodyX*q[3],bodyZ*q[4],alpha,angle); L._patches=L._patches+1
        end
      end
    end
  end
  local sh=ensureShader(); local m=sh and upload(); if not m then return false end
  local prev; pcall(function() prev={love.graphics.getBlendMode()} end)
  pcall(love.graphics.setBlendMode,"alpha","alphamultiply")
  local began=Voxel3D.beginEffect and Voxel3D.beginEffect(sh)
  if not began then pcall(love.graphics.setShader,sh); pcall(love.graphics.setDepthMode,"lequal",false) end
  if not pcall(sh.send,sh,"vp","row",Voxel3D.vp) then pcall(sh.send,sh,"vp",Voxel3D.vp) end
  pcall(love.graphics.setColor,1,1,1,1); pcall(love.graphics.draw,m)
  if Voxel3D.endEffect then pcall(Voxel3D.endEffect) else pcall(love.graphics.setShader) end
  pcall(love.graphics.setDepthMode,"lequal",true); if prev then pcall(love.graphics.setBlendMode,prev[1],prev[2]) end
  L._drawn=#verts; return true
end
function L.status() return {patches=L._patches,vertices=L._drawn} end
return L
