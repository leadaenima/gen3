local V=...

-- Tiny world-space visualizer for WeatherWorldInteraction.gustFront.
-- The front's center/direction are simulation-owned canonical world coordinates;
-- this renderer never derives placement from camera heading or screen space.
local G={}
local sqrt,max,min=math.sqrt,math.max,math.min
local mesh,shader=nil,nil
local verts,rows={},{}
local FORMAT={{"VertexPosition","float",3},{"GustData","float",4}}
local SHADER=[[
#ifdef VERTEX
  extern mat4 vp;attribute vec4 GustData;varying vec4 vData;varying vec3 vWorld;
  vec4 position(mat4 t,vec4 v){vData=GustData;vWorld=v.xyz;return vp*vec4(v.xyz,1.0);}
#endif
#ifdef PIXEL
  extern float time;extern vec3 gustColor;varying vec4 vData;varying vec3 vWorld;
  vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){
    float u=vData.x;float v=vData.y;float phase=vData.z;float base=vData.w;
    float edge=smoothstep(0.0,.12,u)*(1.0-smoothstep(.88,1.0,u));
    float floorFade=smoothstep(0.0,.10,v);float topFade=1.0-smoothstep(.68,1.0,v);
    float streak=.5+.5*sin(vWorld.x*.082+vWorld.z*.061-v*9.0-time*2.2+phase);
    float billow=.5+.5*sin(vWorld.x*.031-vWorld.z*.047+time*.74+phase*1.73);
    float body=smoothstep(.24,.78,streak*.62+billow*.38);
    float a=base*edge*floorFade*topFade*(.18+.82*body);
    return vec4(gustColor,a)*color;
  }
#endif
]]
local function getShader()
  if shader~=nil then return shader or nil end
  if not (love and love.graphics and love.graphics.newShader) then shader=false;return nil end
  local ok,sh=V.safeCall(love.graphics.newShader,SHADER);shader=(ok and sh) or false;return shader or nil
end
local function color(kind,out)
  out=out or {1,1,1};kind=tostring(kind or "air")
  if kind=="snow" then out[1],out[2],out[3]=.86,.91,.97
  elseif kind=="dust" then out[1],out[2],out[3]=.72,.61,.43
  elseif kind=="ash" then out[1],out[2],out[3]=.47,.48,.49
  elseif kind=="spray" then out[1],out[2],out[3]=.62,.70,.78
  else out[1],out[2],out[3]=.57,.61,.48 end
  return out
end
local c3={1,1,1}
local function put(n,x,y,z,u,v,phase,a)
  local r=rows[n];if not r then r={0,0,0,0,0,0,0};rows[n]=r end
  r[1],r[2],r[3],r[4],r[5],r[6],r[7]=x,y,z,u,v,phase,a;verts[n]=r
end
function G.draw(Voxel3D,frame)
  local f=frame and frame.gustFront
  if not (f and f.active and Voxel3D and Voxel3D.vp and love and love.graphics) then return false end
  local sh=getShader();if not sh then return false end
  local dx,dz=tonumber(f.dirX) or 0,tonumber(f.dirZ) or 0;local dl=sqrt(dx*dx+dz*dz);if dl<1e-5 then return false end;dx,dz=dx/dl,dz/dl
  local px,pz=-dz,dx;local width=max(48,tonumber(f.width) or 120);local height=max(8,tonumber(f.height) or 18);local strength=min(1,max(0,tonumber(f.strength) or .5))
  local cx,cz=tonumber(f.x) or 0,tonumber(f.z) or 0;local n=0;local segments=8
  for j=0,segments-1 do
    local u0=j/segments;local u1=(j+1)/segments;local o0=(u0-.5)*width;local o1=(u1-.5)*width;local ripple=(j%2==0) and 1.8 or -1.3;local bx=cx+dx*ripple;local bz=cz+dz*ripple;local y0=.25;local y1=height*(.72+.28*((j%3)/2));local phase=(tonumber(f.serial) or 0)*.71+j*.93;local alpha=(.10+.16*strength)
    put(n+1,bx+px*o0,y0,bz+pz*o0,u0,0,phase,alpha);put(n+2,bx+px*o1,y0,bz+pz*o1,u1,0,phase,alpha);put(n+3,bx+px*o1,y1,bz+pz*o1,u1,1,phase,alpha)
    put(n+4,bx+px*o0,y0,bz+pz*o0,u0,0,phase,alpha);put(n+5,bx+px*o1,y1,bz+pz*o1,u1,1,phase,alpha);put(n+6,bx+px*o0,y1,bz+pz*o0,u0,1,phase,alpha);n=n+6
  end
  if not mesh then local ok,m=V.safeCall(love.graphics.newMesh,FORMAT,verts,"triangles","stream");if not ok then return false end;mesh=m else local ok=V.safeCall(mesh.setVertices,mesh,verts);if not ok then return false end end
  V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply");V.safeCall(love.graphics.setDepthMode,"lequal",false)
  if Voxel3D.beginEffect(sh) then V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp);V.safeCall(sh.send,sh,"time",tonumber(frame.time) or 0);V.safeCall(sh.send,sh,"gustColor",color(f.kind,c3));local ok=V.safeCall(love.graphics.draw,mesh);Voxel3D.endEffect();return ok end
  return false
end

function G.invalidate() mesh,shader=nil,nil end
return G
