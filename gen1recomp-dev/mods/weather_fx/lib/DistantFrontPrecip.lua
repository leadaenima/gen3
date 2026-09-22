-- Weather FX 8.1.51: zero-upload remote StormCell hydrometeors.
--
-- 8.1.50 fixed front continuity by rendering the remote rain/snow field as
-- thousands of individual world-space quads.  The morphology was correct, but
-- the fallback implementation rebuilt four CPU vertices and four sine-hashes
-- per particle every frame.  This module keeps the exact particle population,
-- slab distribution, fall/shear equations and front/local handoff, while moving
-- deterministic particle synthesis to the GPU through the shared immutable
-- InstanceSeedBuffer.  Unsupported hosts keep the 8.1.50 CPU path unchanged.
local V=...
local P={}
local state={base=nil,seed=nil,seedCap=0,shader=nil,failed=false,reason=nil,drawCalls=0,instances=0,checks=0}

local SHADER=[[
#ifdef VERTEX
attribute float InstanceSeed;
uniform mat4 vp;
uniform vec3 curve;
uniform vec2 frontBase;
uniform vec2 frontCross;
uniform vec2 frontTravel;
uniform vec2 frontViewSide;
uniform vec2 frontWind;
uniform float frontWidth;
uniform float frontDepth;
uniform float frontTop;
uniform float frontBottom;
uniform float frontTime;
uniform float frontAlpha;
uniform float frontKind;
uniform float frontId;
uniform float frontGust;
uniform float instanceBase;
varying vec2 vUv;
varying float vAlpha;
varying float vKind;

float h1(float n){return fract(sin(n*12.9898+78.233)*43758.5453123);}

vec4 position(mat4 transform_projection, vec4 vertex_position){
  float id=InstanceSeed+instanceBase+1.0;
  float seed=frontId*1009.0+id*17.173;
  float a=h1(seed+.13),b=h1(seed+3.71),c=h1(seed+8.27),d=h1(seed+14.9);
  float lateral=(a*2.0-1.0)*frontWidth*.48*(.72+.28*b);
  float behind=pow(b,.72)*frontDepth;
  vec3 center=vec3(frontBase.x+frontCross.x*lateral+frontTravel.x*behind,0.0,
                   frontBase.y+frontCross.y*lateral+frontTravel.y*behind);
  float height=max(8.0,frontTop-frontBottom);
  vec3 side=vec3(frontViewSide.x,0.0,frontViewSide.y);
  vec3 axisY=vec3(0.0,1.0,0.0);
  vec3 slant=vec3(0.0);
  float halfW=0.2,halfH=0.2;
  float kind=frontKind;
  if(kind<.5){
    float fall=48.0+c*42.0;
    float travel=mod(frontTime*fall+d*height,height);
    center.y=frontTop-travel;
    float age=travel/max(1.0,fall);
    center.x+=frontWind.x*(5.0+b*12.0)*age*.34;
    center.z+=frontWind.y*(5.0+a*12.0)*age*.34;
    float size=.55+c*1.50;
    halfW=size*.12;halfH=size*1.40;
    slant=vec3(frontWind.x*size*.10,0.0,frontWind.y*size*.10);
    vAlpha=frontAlpha*(.34+.34*b);
    vKind=5.0;
  }else{
    float mul=(kind>1.5) ? 1.22 : 1.0;
    float fall=(5.0+c*6.5)*mul;
    float travel=mod(frontTime*fall+d*height,height);
    center.y=frontTop-travel;
    float age=travel/max(1.5,fall);
    float gust=(kind>1.5) ? (8.0+18.0*frontGust) : (3.0+b*7.0);
    center.x+=frontWind.x*gust*age*.36+sin(frontTime*(.7+a)+seed)*(.5+c*1.4);
    center.z+=frontWind.y*gust*age*.36+cos(frontTime*(.6+b)+seed)*(.5+a*1.4);
    float size=(kind>1.5) ? (.24+c*.34) : (.17+c*.31);
    float shear=(kind>1.5) ? (.18+.28*frontGust) : 0.0;
    halfW=size;halfH=size;
    slant=vec3(frontWind.x*shear,0.0,frontWind.y*shear);
    vAlpha=frontAlpha*(.42+.40*a);
    vKind=(kind>1.5) ? 7.0 : 6.0;
  }
  vec2 co=vertex_position.xy;
  vec3 world=center+side*(halfW*co.x)+axisY*(halfH*co.y)+slant*co.y;
  if(curve.z>0.0){vec2 cd=world.xz-curve.xy;world.y-=dot(cd,cd)*curve.z;}
  vUv=co*.5+.5;
  return vp*vec4(world,1.0);
}
#endif

#ifdef PIXEL
uniform float frontTime;
varying vec2 vUv;
varying float vAlpha;
varying float vKind;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc){
  float u=clamp(vUv.x,0.0,1.0),v=clamp(vUv.y,0.0,1.0);
  if(vKind<5.5){
    float sideP=smoothstep(0.0,0.24,u)*(1.0-smoothstep(0.76,1.0,u));
    float endP=smoothstep(0.0,0.10,v)*(1.0-smoothstep(0.90,1.0,v));
    return vec4(vec3(0.42,0.49,0.58),vAlpha*sideP*endP)*color;
  }
  vec2 fp=vec2(u,v)*2.0-1.0;float d=dot(fp,fp);
  if(vKind<6.5){
    float flake=1.0-smoothstep(0.20,1.0,d);flake*=flake;
    return vec4(vec3(0.76,0.80,0.86),vAlpha*flake)*color;
  }
  float flake=1.0-smoothstep(0.16,1.0,d);
  float gust=0.70+0.30*sin((u-v)*15.0-frontTime*8.0);
  return vec4(vec3(0.84,0.88,0.94),vAlpha*flake*gust)*color;
}
#endif
]]

local BASE_ROWS={{-1,-1,0},{1,-1,0},{1,1,0},{-1,1,0}}
local BASE_MAP={1,2,3,1,3,4}
local function ensure()
  if state.failed then return false end
  if state.base and state.seed and state.shader then return true end
  local g=love and love.graphics
  if not(g and type(g.newMesh)=='function' and type(g.newShader)=='function' and type(g.drawInstanced)=='function') then state.reason='instancing api unavailable';return false end
  if type(g.getSupported)=='function' then local ok,s=pcall(g.getSupported);if ok and type(s)=='table' and s.instancing==false then state.reason='instancing unsupported';return false end end
  state.checks=state.checks+1
  if not state.base then
    local ok,m=pcall(g.newMesh,{{'VertexPosition','float',3}},BASE_ROWS,'triangles','static')
    if not ok or not m then state.failed=true;state.reason='front precip base mesh creation failed';return false end
    if not(m.setVertexMap and pcall(m.setVertexMap,m,BASE_MAP)) then state.failed=true;state.reason='front precip index map creation failed';return false end
    state.base=m
  end
  if not state.seed then
    local okB,B=pcall(V.require,'InstanceSeedBuffer');local sm,cap=nil,0
    if okB and B and B.get then sm,cap=B.get() end
    if not sm then state.reason='instance seed buffer unavailable';return false end
    local okA=pcall(state.base.attachAttribute,state.base,'InstanceSeed',sm,'perinstance')
    if not okA then state.failed=true;state.reason='front precip seed attach failed';return false end
    state.seed,state.seedCap=sm,tonumber(cap) or 8192
  end
  if not state.shader then
    local ok,sh=pcall(g.newShader,SHADER)
    if not ok or not sh then state.failed=true;state.reason='front precip shader failed';return false end
    state.shader=sh
  end
  return true
end
local function send(sh,n,v) return pcall(sh.send,sh,n,v) end
function P.supported() return ensure() end
function P.draw(Voxel3D,o)
  o=o or{};local count=math.max(0,math.floor(tonumber(o.count) or 0));if count<=0 then return true,0 end
  if not ensure() then return false,0 end
  local g=love.graphics;local sh=state.shader;local began=false
  pcall(g.setColor,1,1,1,1);pcall(g.setBlendMode,'alpha','alphamultiply');pcall(g.setDepthMode,'lequal',false)
  if Voxel3D and Voxel3D.beginEffect then local ok,v=pcall(Voxel3D.beginEffect,sh);began=ok and v and true or false end
  if not began then pcall(g.setShader,sh) end
  -- Hot path deliberately avoids per-front uniform tables. Reuse tiny vector
  -- scratch records and send every scalar directly, keeping steady-state draws
  -- allocation-flat on the CPU side.
  state.v2=state.v2 or {0,0};state.v3=state.v3 or {0,0,0}
  local v2,v3=state.v2,state.v3;local uniformsOK=true
  uniformsOK=pcall(sh.send,sh,'vp','row',Voxel3D and Voxel3D.vp) and uniformsOK
  v3[1],v3[2],v3[3]=Voxel3D and Voxel3D.curveX or 0,Voxel3D and Voxel3D.curveZ or 0,Voxel3D and Voxel3D.curveK or 0;uniformsOK=send(sh,'curve',v3) and uniformsOK
  v2[1],v2[2]=tonumber(o.bx) or 0,tonumber(o.bz) or 0;uniformsOK=send(sh,'frontBase',v2) and uniformsOK
  v2[1],v2[2]=tonumber(o.crossX) or 1,tonumber(o.crossZ) or 0;uniformsOK=send(sh,'frontCross',v2) and uniformsOK
  v2[1],v2[2]=tonumber(o.tx) or 0,tonumber(o.tz) or 1;uniformsOK=send(sh,'frontTravel',v2) and uniformsOK
  v2[1],v2[2]=tonumber(o.viewX) or tonumber(o.crossX) or 1,tonumber(o.viewZ) or tonumber(o.crossZ) or 0;uniformsOK=send(sh,'frontViewSide',v2) and uniformsOK
  v2[1],v2[2]=tonumber(o.windX) or 0,tonumber(o.windZ) or 0;uniformsOK=send(sh,'frontWind',v2) and uniformsOK
  uniformsOK=send(sh,'frontWidth',tonumber(o.width) or 100) and uniformsOK
  uniformsOK=send(sh,'frontDepth',tonumber(o.depth) or 100) and uniformsOK
  uniformsOK=send(sh,'frontTop',tonumber(o.top) or 48) and uniformsOK
  uniformsOK=send(sh,'frontBottom',tonumber(o.bottom) or 2) and uniformsOK
  uniformsOK=send(sh,'frontTime',tonumber(o.time) or 0) and uniformsOK
  uniformsOK=send(sh,'frontAlpha',tonumber(o.alpha) or 0) and uniformsOK
  uniformsOK=send(sh,'frontKind',tonumber(o.kind) or 0) and uniformsOK
  uniformsOK=send(sh,'frontId',tonumber(o.frontId) or 1) and uniformsOK
  uniformsOK=send(sh,'frontGust',tonumber(o.gust) or 0) and uniformsOK
  if not uniformsOK then state.failed=true;state.reason='front precip uniform upload failed' end
  local drawn,base=0,0;local cap=math.max(1,state.seedCap or 8192)
  while drawn<count and not state.failed do
    local n=math.min(cap,count-drawn)
    if not send(sh,'instanceBase',base) then state.failed=true;state.reason='front precip instanceBase upload failed';break end
    local ok=pcall(g.drawInstanced,state.base,n)
    if not ok then state.failed=true;state.reason='front precip drawInstanced failed';break end
    drawn=drawn+n;base=base+n;state.drawCalls=state.drawCalls+1
  end
  state.instances=state.instances+drawn
  if Voxel3D and Voxel3D.endEffect and began then pcall(Voxel3D.endEffect) else pcall(g.setShader) end
  pcall(g.setColor,1,1,1,1);pcall(g.setDepthMode,'lequal',true)
  return (not state.failed) and drawn==count,drawn
end
function P.invalidate()
  if state.base and state.base.release then pcall(state.base.release,state.base) end
  if state.shader and state.shader.release then pcall(state.shader.release,state.shader) end
  state.base,state.seed,state.seedCap,state.shader=nil,nil,0,nil;state.failed=false;state.reason=nil
end
function P.stats() return {supported=(not state.failed and state.base~=nil),failed=state.failed,reason=state.reason,drawCalls=state.drawCalls,instances=state.instances,checks=state.checks,seedCapacity=state.seedCap} end
return P
