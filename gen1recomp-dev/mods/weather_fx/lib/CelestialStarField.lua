-- Weather FX 8.0.2: static-instanced ordinary star vault.
--
-- The 5,120-star catalogue is authored/generated once by NightSky.  The old
-- world renderer rotated every star, built six billboard vertices per star and
-- uploaded that stream every frame.  This module uploads the immutable
-- catalogue ONCE and keeps all frame-varying work (vault rotation, twinkle,
-- horizon fade, light-pollution membership) in one instanced shader draw.
-- Planets, constellations, Milky Way and meteors remain owned by NightSky.
local V=...
local safe=(V.safeBind and V.safeBind("CelestialStarField")) or pcall
local F={}
local state={base=nil,instances=nil,shader=nil,projectedShader=nil,count=0,catalogue=nil,failed=false,reason=nil,drawCalls=0,frames=0,builds=0}
local eyeV={0,0,0};local rightV={1,0,0};local upV={0,1,0};local axisV={0,0,-1}

local SHADER=[[
#ifdef VERTEX
uniform mat4 vp;
uniform vec3 starEye;
uniform vec3 starRight;
uniform vec3 starUp;
uniform vec3 vaultAxis;
uniform float vaultCos;
uniform float vaultSin;
uniform float starRadius;
uniform float starTime;
uniform float starVisibility;
uniform float starScale;
uniform float buildingFactor;
uniform float twinkleEnabled;
attribute vec3 StarDir;
attribute vec4 StarColor;
attribute vec4 StarData;   // size, twinkle speed 1, twinkle speed 2, depth
attribute vec4 StarExtra;  // phase 1, phase 2, hide-near-building, reserved
varying vec4 vStarColor;

vec3 rotateVault(vec3 v){
  float d=dot(v,vaultAxis);
  vec3 c=cross(vaultAxis,v);
  return v*vaultCos+c*vaultSin+vaultAxis*d*(1.0-vaultCos);
}

vec4 position(mat4 transform_projection,vec4 vertex_position){
  vec3 d=rotateVault(StarDir);
  float hf=smoothstep(-0.035,0.13,d.y);
  float dens=mix(1.0,buildingFactor,clamp(StarExtra.z,0.0,1.0));
  float tw=1.0;
  if(twinkleEnabled>0.5){
    float w1=.65*sin(starTime*StarData.y+StarExtra.x);
    float w2=.35*sin(starTime*StarData.z+StarExtra.y);
    tw=clamp(1.0+StarData.w*(.55*w1+.45*w2),.35,1.25);
  }
  float a=StarColor.a*starScale*clamp(starVisibility,0.0,1.0)*dens*tw*hf;
  float halfSize=max(.5,StarData.x*.55);
  vec3 center=starEye+d*starRadius;
  vec3 world=center+starRight*(vertex_position.x*halfSize)+starUp*(vertex_position.y*halfSize);
  vStarColor=vec4(StarColor.rgb,a);
  // Infinite-vault depth: ordinary stars must never sit in front of distant
  // terrain simply because the authored sky radius is inside the host far plane.
  vec4 clip=vp*vec4(world,1.0);
  clip.z=clip.w;
  return clip;
}
#endif
#ifdef PIXEL
varying vec4 vStarColor;
vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){
  if(vStarColor.a<.004) discard;
  return vStarColor*color;
}
#endif
]]

local PROJECTED_SHADER=[[
#ifdef VERTEX
uniform vec3 camForward;
uniform vec3 camRight;
uniform vec3 camUp;
uniform vec3 vaultAxis;
uniform float vaultCos;
uniform float vaultSin;
uniform vec2 invFov;
uniform vec2 screenSize;
uniform float starTime;
uniform float starVisibility;
uniform float starScale;
uniform float buildingFactor;
uniform float twinkleEnabled;
attribute vec3 StarDir;
attribute vec4 StarColor;
attribute vec4 StarData;
attribute vec4 StarExtra;
varying vec4 vStarColor;
vec3 rotateVault(vec3 v){float d=dot(v,vaultAxis);vec3 c=cross(vaultAxis,v);return v*vaultCos+c*vaultSin+vaultAxis*d*(1.0-vaultCos);}
vec4 position(mat4 transform_projection,vec4 vertex_position){
  vec3 d=rotateVault(StarDir);
  float front=dot(d,camForward);
  float safeFront=max(front,0.000001);
  float nx=dot(d,camRight)*invFov.x/safeFront;
  float ny=dot(d,camUp)*invFov.y/safeFront;
  float hf=smoothstep(-0.035,0.13,d.y);
  float dens=mix(1.0,buildingFactor,clamp(StarExtra.z,0.0,1.0));
  float tw=1.0;if(twinkleEnabled>0.5){float w1=.65*sin(starTime*StarData.y+StarExtra.x);float w2=.35*sin(starTime*StarData.z+StarExtra.y);tw=clamp(1.0+StarData.w*(.55*w1+.45*w2),.35,1.25);}
  float inside=(front>0.000001 && abs(nx)<1.25 && abs(ny)<1.25)?1.0:0.0;
  float a=StarColor.a*starScale*clamp(starVisibility,0.0,1.0)*dens*tw*hf*inside;
  float halfSize=max(.72,StarData.x*.52);
  vec2 center=vec2((nx*.5+.5)*screenSize.x,(.5-ny*.5)*screenSize.y);
  vec2 pixel=center+vertex_position.xy*halfSize;
  vStarColor=vec4(StarColor.rgb,a);
  // Keep the zenith-safe projected coordinates, but place the celestial
  // fragment at the far end of the host depth buffer. Buildings, terrain and
  // NPCs written later/earlier with ordinary scene depth can therefore occlude
  // stars instead of the sky behaving like an always-on-top overlay.
  vec4 clip=transform_projection*vec4(pixel,0.0,1.0);
  clip.z=clip.w;
  return clip;
}
#endif
#ifdef PIXEL
varying vec4 vStarColor;
vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){if(vStarColor.a<.004)discard;return vStarColor*color;}
#endif
]]

local function capability()
  local g=love and love.graphics
  if not(g and type(g.newMesh)=='function' and type(g.newShader)=='function' and type(g.drawInstanced)=='function') then return false,'instancing api unavailable' end
  if type(g.getSupported)=='function' then local ok,s=safe(g.getSupported);if ok and type(s)=='table' and s.instancing==false then return false,'instancing unsupported' end end
  return true
end

local function releaseLocal()
  if state.base and state.base.release then safe(state.base.release,state.base) end
  if state.instances and state.instances.release then safe(state.instances.release,state.instances) end
  if state.shader and state.shader.release then safe(state.shader.release,state.shader) end
  if state.projectedShader and state.projectedShader.release then safe(state.projectedShader.release,state.projectedShader) end
  state.base,state.instances,state.shader,state.projectedShader=nil,nil,nil,nil;state.count=0;state.catalogue=nil
end

local function ensure(stars)
  if state.failed then return false end
  if state.base and state.instances and state.shader and state.catalogue==stars and state.count==#stars then return true end
  local ok,reason=capability();if not ok then state.reason=reason;return false end
  if type(stars)~='table' or #stars<1 then state.reason='star catalogue unavailable';return false end
  releaseLocal()
  local g=love.graphics
  local baseFmt={{'VertexPosition','float',3}}
  local baseVerts={{-1,1,0},{1,1,0},{1,-1,0},{-1,1,0},{1,-1,0},{-1,-1,0}}
  local okB,base=safe(g.newMesh,baseFmt,baseVerts,'triangles','static');if not okB or not base then state.failed=true;state.reason='base star mesh failed';return false end
  local rows={}
  for i=1,#stars do
    local s=stars[i]
    rows[i]={s.dx or 0,s.dy or 0,s.dz or 1, s.r or 1,s.g or 1,s.b or 1,s.a or 1, s.size or 1,s.tw or 1,s.tw2 or .4,s.twDepth or .2, s.phase or 0,s.phase2 or 0,s.hideNearBuilding and 1 or 0,0}
  end
  local fmt={{'StarDir','float',3},{'StarColor','float',4},{'StarData','float',4},{'StarExtra','float',4}}
  local okI,inst=safe(g.newMesh,fmt,rows,nil,'static');rows=nil
  if not okI or not inst then safe(base.release,base);state.failed=true;state.reason='static star catalogue upload failed';return false end
  for _,name in ipairs({'StarDir','StarColor','StarData','StarExtra'}) do
    local aok=safe(base.attachAttribute,base,name,inst,'perinstance')
    if not aok then safe(base.release,base);safe(inst.release,inst);state.failed=true;state.reason='star instance attribute attach failed';return false end
  end
  local okS,sh=safe(g.newShader,SHADER)
  if not okS or not sh then safe(base.release,base);safe(inst.release,inst);state.failed=true;state.reason='star instance shader failed';return false end
  state.base,state.instances,state.shader=base,inst,sh;state.count=#stars;state.catalogue=stars;state.builds=state.builds+1
  return true
end

local function send(sh,name,value) return safe(sh.send,sh,name,value) end
local function projectedShader()
  if state.projectedShader then return state.projectedShader end
  if state.failed then return nil end
  local ok,sh=safe(love.graphics.newShader,PROJECTED_SHADER)
  if not ok or not sh then state.failed=true;state.reason='projected star shader failed';return nil end
  state.projectedShader=sh;return sh
end
function F.draw(Voxel3D,stars,opts)
  opts=opts or{};if not ensure(stars) then return false,0 end
  local e=Voxel3D and Voxel3D.eye;local vp=Voxel3D and Voxel3D.vp;local r=opts.axisR;local u=opts.axisU
  if not(e and vp and r and u) then state.reason='camera data unavailable';return false,0 end
  eyeV[1],eyeV[2],eyeV[3]=e[1]or 0,e[2]or 0,e[3]or 0;rightV[1],rightV[2],rightV[3]=r[1]or 1,r[2]or 0,r[3]or 0;upV[1],upV[2],upV[3]=u[1]or 0,u[2]or 1,u[3]or 0
  local lat=0;local okSim,Sim=safe(V.require,'CelestialSim');if okSim and Sim and Sim.latitude then local okL,v=safe(Sim.latitude);if okL then lat=tonumber(v)or 0 end end
  local p=lat*math.pi/180;axisV[1],axisV[2],axisV[3]=0,math.sin(p),-math.cos(p)
  local sh=state.shader;local g=love.graphics;local angle=tonumber(opts.vaultAngle)or 0
  local began=false;safe(g.setBlendMode,'add','alphamultiply');safe(g.setDepthMode,'lequal',false)
  if Voxel3D.beginEffect then local ok,v=safe(Voxel3D.beginEffect,sh);began=ok and v and true or false end;if not began then safe(g.setShader,sh) end
  local okVP=safe(sh.send,sh,'vp','row',vp);if not okVP then okVP=send(sh,'vp',vp)end
  local fields={{'starEye',eyeV},{'starRight',rightV},{'starUp',upV},{'vaultAxis',axisV},{'vaultCos',math.cos(angle)},{'vaultSin',math.sin(angle)},{'starRadius',tonumber(opts.radius)or 420},{'starTime',tonumber(opts.time)or 0},{'starVisibility',tonumber(opts.visibility)or 0},{'starScale',tonumber(opts.scale)or 1},{'buildingFactor',tonumber(opts.buildingFactor)or 1},{'twinkleEnabled',opts.twinkle==false and 0 or 1}}
  local healthy=okVP
  for i=1,#fields do if healthy and not send(sh,fields[i][1],fields[i][2]) then healthy=false;state.reason='star uniform upload failed' end end
  local drew=false
  if healthy then safe(g.setColor,1,1,1,1);local ok=safe(g.drawInstanced,state.base,state.count);drew=ok;if not ok then state.failed=true;state.reason='star drawInstanced failed' end end
  if Voxel3D.endEffect and began then safe(Voxel3D.endEffect) else safe(g.setShader) end
  safe(g.setDepthMode,'lequal',true);safe(g.setBlendMode,'alpha','alphamultiply');safe(g.setColor,1,1,1,1)
  if drew then state.drawCalls=state.drawCalls+1;state.frames=state.frames+1;return true,state.count end
  return false,0
end
function F.drawProjected(stars,opts)
  opts=opts or{};if not ensure(stars) then return false,0 end
  local sh=projectedShader();if not sh then return false,0 end
  local b=opts.basis;if type(b)~='table' then state.reason='projection basis unavailable';return false,0 end
  local lat=0;local okSim,Sim=safe(V.require,'CelestialSim');if okSim and Sim and Sim.latitude then local okL,v=safe(Sim.latitude);if okL then lat=tonumber(v)or 0 end end
  local p=lat*math.pi/180;axisV[1],axisV[2],axisV[3]=0,math.sin(p),-math.cos(p)
  rightV[1],rightV[2],rightV[3]=b.rx or 1,b.ry or 0,b.rz or 0;upV[1],upV[2],upV[3]=b.ux or 0,b.uy or 1,b.uz or 0;eyeV[1],eyeV[2],eyeV[3]=b.fx or 0,b.fy or 0,b.fz or 1
  local angle=tonumber(opts.vaultAngle)or 0;local g=love.graphics
  safe(g.setBlendMode,'add','alphamultiply');safe(g.setDepthMode,'lequal',false);safe(g.setColor,1,1,1,1)
  local began=false;safe(g.setShader,sh)
  local fields={{'camForward',eyeV},{'camRight',rightV},{'camUp',upV},{'vaultAxis',axisV},{'vaultCos',math.cos(angle)},{'vaultSin',math.sin(angle)},{'invFov',{b.invX or 1,b.invY or 1}},{'screenSize',{b.w or 160,b.h or 144}},{'starTime',tonumber(opts.time)or 0},{'starVisibility',tonumber(opts.visibility)or 0},{'starScale',tonumber(opts.scale)or 1},{'buildingFactor',tonumber(opts.buildingFactor)or 1},{'twinkleEnabled',opts.twinkle==false and 0 or 1}}
  local healthy=true;for i=1,#fields do if not send(sh,fields[i][1],fields[i][2]) then healthy=false;state.reason='projected star uniform upload failed';break end end
  local drew=false;if healthy then drew=safe(g.drawInstanced,state.base,state.count) end
  safe(g.setShader);safe(g.setDepthMode,'lequal',true);safe(g.setBlendMode,'alpha','alphamultiply');safe(g.setColor,1,1,1,1)
  if drew then state.drawCalls=state.drawCalls+1;state.frames=state.frames+1;return true,state.count end
  if healthy then state.failed=true;state.reason='projected star drawInstanced failed' end
  return false,0
end

function F.supported(stars) return ensure(stars) end
function F.invalidate() releaseLocal();state.failed=false;state.reason=nil end
function F.stats() return {supported=state.base~=nil and not state.failed,count=state.count,drawCalls=state.drawCalls,frames=state.frames,builds=state.builds,failed=state.failed,reason=state.reason} end
return F
