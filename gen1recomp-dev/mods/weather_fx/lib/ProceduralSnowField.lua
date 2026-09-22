-- Weather FX 8.0.2: zero-upload far-snow virtualization.
--
-- Weather FX 8.1.54: after a real driver proof this field owns the complete
-- visible snow population from near eye-space through the far plane. WorldPrecip
-- keeps only a tiny non-rendered face-contact probe set; ground collision and
-- settling are temporarily disabled. Before proof, the complete legacy CPU
-- population remains authoritative. The procedural field is a visual stream: LÖVE's per-instance ID attribute
-- deterministically generates their world position, tumble,
-- size, alpha and drift in the vertex shader. No per-flake Lua row or GPU
-- instance buffer exists for this field. This is deliberately fail-open: if a
-- driver cannot compile GLSL3 / instancing, WorldPrecip keeps its legacy full
-- CPU simulation and renderer.
local V = ...
local P = {}

local state={base=nil,pointBase=nil,seed=nil,seedCap=0,staticPage=nil,staticCap=0,pointPage=nil,pointCap=0,backend=nil,flakeShader=nil,ballShader=nil,pointShader=nil,failed=false,proven=false,reason=nil,drawCalls=0,instances=0,pointInstances=0,detailInstances=0,checks=0,anchorX=nil,anchorZ=nil,anchorNextX=nil,anchorNextZ=nil,anchorT0=nil,renderClock=0,renderHostTime=nil,validated=nil}
local _Meso=nil
local function mesoscaleModule()
  if _Meso then return _Meso end
  local ok,m=pcall(V.require,'MesoscaleField'); if ok and m then _Meso=m end
  return _Meso
end

local PIXEL_FLAKE=[[
#ifdef PIXEL
varying vec4 vCol;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  // 8.2.2 mobile fragment path: retain a crisp six-arm crystal silhouette
  // without transcendental angle/length/trig operations or per-pixel branch loops. The previous
  // analytic snowflake was attractive up close but catastrophically expensive
  // under thousands of translucent overlapping flakes on tile-based phone GPUs.
  vec2 p=vec2(vCol.g,vCol.b)*2.0-1.0;
  vec2 ap=abs(p);
  float r2=dot(p,p); if (r2>1.04) discard;
  float seed=clamp(vCol.r,0.0,1.0);
  float d0=ap.y;
  float d1=abs(0.8660254*p.x+0.5*p.y);
  float d2=abs(0.8660254*p.x-0.5*p.y);
  float spoke=min(d0,min(d1,d2));
  float armW=0.026+seed*0.014;
  float arms=1.0-smoothstep(armW,armW*2.25,spoke);
  arms*=smoothstep(0.018,0.075,r2)*(1.0-smoothstep(0.78,1.04,r2));
  // Two lightweight hexagonal branch/rime rings keep the flake visibly
  // crystalline at close range. Geometry tumble supplies continuous rotation.
  float hexr=max(ap.y,ap.x*0.8660254+ap.y*0.5);
  float ring1=1.0-smoothstep(0.018,0.050,abs(hexr-(0.30+seed*0.035)));
  float ring2=1.0-smoothstep(0.016,0.046,abs(hexr-(0.53-seed*0.025)));
  float branch=max(ring1*0.78,ring2*0.62)*(1.0-smoothstep(0.86,1.03,r2));
  float core=1.0-smoothstep(0.012,0.060,r2);
  float shape=max(core,max(arms,branch));
  shape*=1.0-smoothstep(0.90,1.04,r2);
  if (shape<0.018) discard;
  vec3 ice=mix(vec3(0.82,0.90,1.0),vec3(1.0),0.35+seed*0.50);
  vec3 rgb=ice*(0.74+shape*0.40);
  return vec4(rgb,vCol.a*shape)*color;
}
#endif
]]

local PIXEL_POINT=[[
#ifdef PIXEL
varying vec4 vCol;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  // 8.2.3 far-snow LOD: beyond the radius where a crystal silhouette is
  // resolvable, a flake is at most a few screen pixels. One shaded point keeps
  // the same moving world particle without paying quad raster/shape overdraw.
  vec3 ice=mix(vec3(0.82,0.90,1.0),vec3(1.0),0.45+vCol.r*0.45);
  return vec4(ice,vCol.a)*color;
}
#endif
]]

local PIXEL_BALL=[[
#ifdef PIXEL
varying vec4 vCol;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p=vec2(vCol.g,vCol.b)*2.0-1.0; float d=dot(p,p);
  float soft=1.0-smoothstep(0.10,1.0,d); soft*=soft;
  vec3 rgb=vec3(0.95,0.97,1.0)*(0.55+vCol.r*0.55);
  return vec4(rgb,vCol.a*soft)*color;
}
#endif
]]

local VERTEX=[[
#ifdef VERTEX
attribute float InstanceSeed;
extern mat4 vp;
extern vec3 fieldFocus;
extern vec3 snowEye;
extern vec3 fieldAxisR;
extern vec3 fieldAxisU;
extern vec2 fieldWind;
// 8.2.1 mobile hot path: frame-constant periodic/patch values are precomputed
// once in Lua rather than recomputed in every snow vertex.
extern float fieldTileSpan;
extern float fieldTileInv;
extern vec2 fieldTilePhase;
extern float fieldFarFadeInv;
// 8.2.8 player-centred snowfall density profile. Nonzero edge keep means the
// field still reaches the full configured render distance without a hard ring.
extern float fieldDensityRadiusInv;
extern float fieldRadialTaper;
extern float fieldCoreRadius;
extern float fieldEdgeKeep;
extern float fieldTaperPower;
extern float fieldPatchFreq;
extern float fieldPatchYFreq;
extern float fieldFrontFreq;
extern float fieldFrontCrossFreq;
extern float fieldSpawnTop;
extern float fieldTotalH;
extern float fieldFallScale;
extern float fieldTime;
extern vec2 fieldPatchOffset;
extern vec2 fieldPatchWind;
extern float fieldPatchiness;
extern float fieldPatchFloor;
extern float fieldAlpha;
#ifdef WFX_POINT_SNOW
extern float fieldDetailInner2;
extern float fieldDetailOuter2;
#endif
extern float instanceBase;
varying vec4 vCol;

// GLES2-safe hash: no transcendental trig. This compatibility path is used
// on mobile/legacy hosts which cannot use GLSL3 native instance IDs.
float h1(float n) {
  n=fract(n*0.1031);
  n*=n+33.33;
  n*=n+n;
  return fract(n);
}
// Smooth periodic sine approximation in turns. It is continuous through the
// wrap and has matched derivatives at the cycle seam, so snow sway/tumble still
// advances smoothly every rendered frame without hardware sin/cos calls.
float wfxSinTurn(float t) {
  float x=fract(t+0.5)*2.0-1.0;
  float y=4.0*x*(1.0-abs(x));
  return y*(0.775+0.225*abs(y));
}

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  float id=InstanceSeed+instanceBase+1.0;
#ifdef WFX_NATIVE_LANES
  uint iid=uint(love_InstanceID)+uint(max(0.0,instanceBase))+1u;
  uint q0=wfxMix32(iid+0x9E3779B9u);
  uint q1=wfxMix32(iid+0x7F4A7C15u);
  uint q2=wfxMix32(iid+0x94D049BBu);
  uint q3=wfxMix32(iid+0xD1B54A35u);
  float seed=wfxLane0(q0),hA=wfxLane1(q0),hB=wfxLane2(q0);
  float hC=wfxLane0(q1),hD=wfxLane1(q1),hE=wfxLane2(q1);
  float hF=wfxLane0(q2),hG=wfxLane1(q2),hH=wfxLane2(q2);
  float hI=wfxLane0(q3);
#ifdef WFX_POINT_SNOW
  // Far points do not need size/tumble identities. Reuse already-independent
  // lanes for alpha/brightness and avoid a fifth integer mix entirely.
  float hJ=hD,hK=hE,hL=hF,hM=0.0,hN=0.5;
#else
  float hJ=wfxLane1(q3),hK=wfxLane2(q3);
  uint q4=wfxMix32(iid+0xCA5A826Bu);
  float hL=wfxLane0(q4),hM=wfxLane1(q4),hN=wfxLane2(q4);
#endif
#else
  float seed=h1(id+0.17);
  float hA=h1(id*1.371+3.1), hB=h1(id*2.113+7.7), hC=h1(id*3.917+1.9);
  float hD=h1(id*5.231+9.2), hE=h1(id*7.711+4.4), hF=h1(id*11.17+6.8);
  float hG=h1(id*13.1+2.4), hH=h1(id*17.3+5.6), hI=h1(id*19.7+8.1);
#ifdef WFX_POINT_SNOW
  float hJ=hD,hK=hE,hL=hF,hM=0.0,hN=0.5;
#else
  float hJ=h1(id*23.9+1.3), hK=h1(id*29.3+4.7), hL=h1(id*31.7+7.2);
  float hM=h1(id*37.1+3.8), hN=h1(id*41.3+9.4);
#endif
#endif
  // 8.2.1: same continuous periodic WORLD field as 8.2.0, but expressed
  // in normalized tile phase.  This is algebraically equivalent to selecting
  // floor((focus-world)/span+0.5), while replacing two per-vertex dynamic
  // divisions + floor operations with one vector fract and multiplies.  The
  // player focus is continuous and each identity still wraps only at its own
  // far boundary: there is no moving whole-field emitter or anchor handoff.
  float fall=(5.0+hC*6.5)*fieldFallScale;
  float travel=mod(fieldTime*fall+hD*fieldTotalH,fieldTotalH);
  float age=travel/max(1.5,fall);
  float y=fieldSpawnTop-travel;

  float wv=0.55+hE*1.35;
  vec2 vel=fieldWind*(5.0+hF*16.0)*wv + vec2(hG-0.5,hH-0.5)*3.5;
  const float INV_TAU=0.15915494309189535;
  float ph=hI + age*(0.7+seed*1.4)*INV_TAU;
  float turb=1.1+seed*2.4;
#ifdef WFX_POINT_SNOW
  // Distant sub-pixel flakes keep continuous wind/sway/bob but need no secondary
  // high-frequency flutter: it is visually unresolvable and only burns ALU.
  float swayX=wfxSinTurn(ph)*turb;
  float swayZ=wfxSinTurn(ph+0.25)*turb*0.95;
#else
  float swayX=wfxSinTurn(ph)*turb + wfxSinTurn(ph*0.41+seed*0.8276057)*turb*0.75;
  float swayZ=wfxSinTurn(ph*0.88+seed*INV_TAU+0.25)*turb*0.95
              + wfxSinTurn(ph*0.33+seed*0.588873+0.25)*turb*0.55;
#endif
  vec2 drift=vel*age*0.55 + vec2(swayX,swayZ);
  vec2 rel=(fract(vec2(hA,hB) + drift*fieldTileInv - fieldTilePhase + 0.5)-0.5)*fieldTileSpan;
  vec2 worldXZ=fieldFocus.xz+rel;
  vec3 center=vec3(worldXZ.x,
                   y+wfxSinTurn(ph*1.15+seed*0.445634)*(0.55+seed*0.7),
                   worldXZ.y);

  vec3 toEye=snowEye-center; float dist2=max(0.0001,dot(toEye,toEye));
  float alpha=0.40+hK*0.38;
  float br=0.82+hL*0.18;
  float nearMix=1.0-clamp(dist2*fieldFarFadeInv,0.0,1.0);
  alpha*=0.30+nearMix*0.70;
  // SNOW_LIGHT / BLIZZARD only: keep the storm visually heaviest above and
  // around the player, then thin particle COUNT smoothly toward the far plane.
  // A deterministic per-flake gate changes visible population, not merely
  // opacity, and the nonzero edge keep preserves full render-distance reach.
  if (fieldRadialTaper>0.5) {
    vec2 densityDelta=center.xz-fieldFocus.xz;
    float dax=abs(densityDelta.x), daz=abs(densityDelta.y);
    // Sqrt-free octagonal radius approximation. It tracks Euclidean distance
    // closely enough for a soft density envelope without adding length()/sqrt
    // to the per-vertex hot path on phones and low-end GPUs.
    float radial=clamp((max(dax,daz)+0.375*min(dax,daz))*fieldDensityRadiusInv,0.0,1.0);
    float u=smoothstep(fieldCoreRadius,1.0,radial);
    // Preserve a dense overhead/player core, then reduce actual visible
    // population progressively toward the horizon. The high smooth exponent
    // compensates for the rapidly growing circumference of distant rings: each
    // farther band contributes fewer flakes overall instead of turning millions
    // of valid world-space identities into a fuzzy wall of sub-pixel points.
    float keep=mix(fieldEdgeKeep,1.0,pow(max(0.0,1.0-u),fieldTaperPower));
    alpha*=step(seed,keep);
  }
  float patch=1.0;
  // Uniform/fronts-off snow does not execute storm-band work at all.
  if (fieldPatchiness>0.0001) {
    vec2 delta=center.xz-fieldPatchOffset;
    vec2 wd=fieldPatchWind;
    float along=dot(delta,wd),crossp=dot(delta,vec2(-wd.y,wd.x));
    float cf=fract(crossp*fieldFrontCrossFreq); float ct=1.0-abs(cf*2.0-1.0);
    float af=fract(along*fieldFrontFreq+ct*0.23); float at=1.0-abs(af*2.0-1.0);
    float py=fract(delta.y*fieldPatchYFreq); float pt=1.0-abs(py*2.0-1.0);
    float px=fract(delta.x*fieldPatchFreq+pt*0.19); float xt=1.0-abs(px*2.0-1.0);
    float wave=smoothstep(.10,.90,at);
    float localp=smoothstep(.08,.92,xt);
    float band=smoothstep(.16,.84,localp*.64+wave*.36);
    patch=mix(1.0,mix(fieldPatchFloor,1.08,band),clamp(fieldPatchiness,0.0,1.0));
  }
#ifdef WFX_POINT_SNOW
  // 8.2.3: one vertex and roughly 1-4 fragments for distant snow instead of a
  // four-corner translucent card. The near fade hands over to the detailed
  // crystal field continuously, so this is spatial LOD rather than animation
  // throttling or density loss.
  float farOnly=smoothstep(fieldDetailInner2,fieldDetailOuter2,dist2);
  vCol=vec4(br,0.5,0.5,alpha*fieldAlpha*patch*farOnly);
  return vp*vec4(center,1.0);
#else
  float size=(0.17+hJ*0.31)*(0.50+nearMix*1.15);
  // Screen-aligned billboard axes are frame-constant. Computing and normalizing
  // a camera basis independently for every vertex was millions of redundant
  // square-roots/cross products per frame at SNOW/BLIZZARD counts.
  vec3 right=fieldAxisR;
  vec3 up=fieldAxisU;
  float roll=hM + fieldTime*((hN-0.5)*0.3819718634);
  float ca=wfxSinTurn(roll+0.25), sa=wfxSinTurn(roll);
  vec3 axisX=(right*ca+up*sa)*(size*0.55);
  vec3 axisY=(up*ca-right*sa)*(size*0.55);
  vec2 corner=vertex_position.xy;
  vec3 world=center+axisX*corner.x+axisY*corner.y;
  vec2 uv=vec2(corner.x*0.5+0.5,0.5-corner.y*0.5);
  vCol=vec4(br,uv.x,uv.y,alpha*fieldAlpha*patch);
  return vp*vec4(world,1.0);
#endif
}
#endif
]]

local function canGraphics()
  local g=love and love.graphics
  if not (g and type(g.newMesh)=='function' and type(g.newShader)=='function' and (type(g.drawInstanced)=='function' or type(g.draw)=='function')) then
    return false,'mesh/shader draw api unavailable'
  end
  return true
end

local function instancingSupported()
  local g=love and love.graphics
  if not (g and type(g.drawInstanced)=='function') then return false end
  if type(g.getSupported)=='function' then
    local ok,s=pcall(g.getSupported)
    if ok and type(s)=='table' and s.instancing==false then return false end
  end
  return true
end

-- 8.1.99: dense BLIZZARD fields exposed a second class of driver failure that
-- the old four-seed validation could not see. The shared 8,192-row attribute
-- buffer is replayed in ~25 chunks for a 200k blizzard and each chunk depended
-- on an `instanceBase` uniform to create unique identities. Some otherwise
-- valid hosts keep the first few per-instance attributes distinct (so the
-- validation passes) but later alias/replay the attribute window across large
-- multi-draw submissions. Repeated procedural identities stack into a narrow
-- high-opacity source that looks like a snow fountain attached to the streamed
-- player field.
--
-- Prefer the shader's native GLSL3 instance id whenever the host advertises it.
-- That removes the recycled seed attribute entirely and submits each fixed
-- 100k/200k field in ONE draw. Low-end / legacy hosts without GLSL3 keep the
-- proven attribute-seed backend unchanged.
local function nativeInstanceIdSupported()
  local g=love and love.graphics
  if not g or not instancingSupported() or type(g.getSupported)~='function' then return false end
  local ok,s=pcall(g.getSupported)
  return ok and type(s)=='table' and s.glsl3==true
end

-- Strip the GLSL3-only branch entirely for attribute/static fallback
-- shaders. Some GLES2 mobile compilers parse inactive preprocessor branches
-- aggressively; keeping uint/love_InstanceID tokens out of the source makes
-- the compatibility backend genuinely portable instead of merely conditional.
local VERTEX_LEGACY = VERTEX:gsub('#ifdef WFX_NATIVE_LANES\n.-#else\n(.-)#endif','%1')

local FAST_HASH_NATIVE=[[
uint wfxMix32(uint x) {
  x ^= x >> 16u;
  x *= 2146121005u;
  x ^= x >> 15u;
  x *= 2221713035u;
  x ^= x >> 16u;
  return x;
}
float wfxLane0(uint x) { return float(x & 1023u) * 0.0009775171065493646; }
float wfxLane1(uint x) { return float((x >> 10u) & 1023u) * 0.0009775171065493646; }
float wfxLane2(uint x) { return float((x >> 20u) & 1023u) * 0.0009775171065493646; }
]]
local VERTEX_NATIVE = '#pragma language glsl3\n#define WFX_NATIVE_LANES 1\n' .. FAST_HASH_NATIVE .. VERTEX
  :gsub('attribute float InstanceSeed;\n','')
  :gsub('float id=InstanceSeed%+instanceBase%+1%.0;','float id=float(love_InstanceID)+instanceBase+1.0;')
local VERTEX_POINT_LEGACY = '#define WFX_POINT_SNOW 1\n' .. VERTEX_LEGACY
local VERTEX_POINT_NATIVE = '#pragma language glsl3\n#define WFX_NATIVE_LANES 1\n#define WFX_POINT_SNOW 1\n' .. FAST_HASH_NATIVE .. VERTEX
  :gsub('attribute float InstanceSeed;\n','')
  :gsub('float id=InstanceSeed%+instanceBase%+1%.0;','float id=float(love_InstanceID)+instanceBase+1.0;')

local VALIDATE_SHADER_ATTRIBUTE=[[
#ifdef VERTEX
attribute float InstanceSeed;
extern float instanceBase;
vec4 position(mat4 transform_projection, vec4 vertex_position){
  float slot=mod(InstanceSeed+instanceBase,4.0);
  vec2 center=vec2(8.0+slot*16.0,8.0);
  vec2 pos=center+vertex_position.xy*vec2(2.5,2.5);
  return transform_projection*vec4(pos,0.0,1.0);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc){ return vec4(1.0,1.0,1.0,1.0); }
#endif
]]

local VALIDATE_SHADER_NATIVE=[[
#pragma language glsl3
#ifdef VERTEX
extern float instanceBase;
vec4 position(mat4 transform_projection, vec4 vertex_position){
  float slot=mod(float(love_InstanceID)+instanceBase,4.0);
  vec2 center=vec2(8.0+slot*16.0,8.0);
  vec2 pos=center+vertex_position.xy*vec2(2.5,2.5);
  return transform_projection*vec4(pos,0.0,1.0);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc){ return vec4(1.0,1.0,1.0,1.0); }
#endif
]]

-- 8.2.2 universal GPU fallback for phones/drivers without working instancing.
-- The old fail-open path rebuilt thousands of camera-facing snow vertices in
-- Lua and uploaded them every frame. A 2,048-flake immutable detail page plus an 8,192-point far page
-- keeps ALL fall/sway/tumble/world-wrap animation in the vertex shader instead.
-- Low/potato snow fits in one or a few ordinary Mesh draws; max-settings PCs
-- continue to use the one-draw native instance-ID path.
local STATIC_DETAIL_FLAKES=2048
local STATIC_POINT_FLAKES=8192
local function ensureStaticPage()
  if state.staticPage then return true end
  local g=love and love.graphics
  if not (g and type(g.newMesh)=='function' and type(g.draw)=='function') then return false end
  local rows,imap={},{}
  local corners={{-1,1,0},{1,1,0},{1,-1,0},{-1,-1,0}}
  for i=0,STATIC_DETAIL_FLAKES-1 do
    local b=#rows
    for c=1,4 do
      local q=corners[c]
      rows[b+c]={q[1],q[2],q[3],i}
    end
    local m=#imap
    imap[m+1],imap[m+2],imap[m+3]=b+1,b+2,b+3
    imap[m+4],imap[m+5],imap[m+6]=b+1,b+3,b+4
  end
  local fmt={{'VertexPosition','float',3},{'InstanceSeed','float',1}}
  local ok,m=pcall(g.newMesh,fmt,rows,'triangles','static')
  rows=nil
  if not ok or not m then return false end
  if not (m.setVertexMap and pcall(m.setVertexMap,m,imap)) then
    if m.release then pcall(m.release,m) end
    return false
  end
  imap=nil
  state.staticPage,state.staticCap=m,STATIC_DETAIL_FLAKES
  return true
end

-- 8.2.3 far-snow static page: one immutable POINT vertex per identity. This is
-- the low-end-phone fallback equivalent of the native one-point instanced base.
-- It removes the six-index translucent quad from the distant field even when
-- hardware instancing is unavailable.
local function ensurePointPage()
  if state.pointPage then return true end
  local g=love and love.graphics
  if not (g and type(g.newMesh)=='function' and type(g.draw)=='function') then return false end
  local rows={}
  for i=0,STATIC_POINT_FLAKES-1 do rows[i+1]={0,0,0,i} end
  local fmt={{'VertexPosition','float',3},{'InstanceSeed','float',1}}
  local ok,m=pcall(g.newMesh,fmt,rows,'points','static');rows=nil
  if not ok or not m then return false end
  state.pointPage,state.pointCap=m,STATIC_POINT_FLAKES
  return true
end

local function validateInstancing()
  if state.backend=='static-page' then state.validated=true; return true end
  if state.validated~=nil then return state.validated end
  local g=love and love.graphics
  if not g then state.validated=true; return true end
  if type(g.newCanvas)~='function' or type(g.setCanvas)~='function' or type(g.clear)~='function' or type(g.drawInstanced)~='function' then
    state.validated=true; return true
  end
  local canvasOk,canvas=pcall(g.newCanvas,64,16)
  if not canvasOk or not canvas or type(canvas.newImageData)~='function' then state.validated=true; return true end
  local validateSource=(state.backend=='native-id') and VALIDATE_SHADER_NATIVE or VALIDATE_SHADER_ATTRIBUTE
  local shaderOk,sh=pcall(g.newShader,validateSource)
  if not shaderOk or not sh then
    if canvas.release then pcall(canvas.release,canvas) end
    state.validated=true; return true
  end
  local ok=pcall(function()
    if g.push then g.push('all') end
    if g.origin then g.origin() end
    g.setCanvas(canvas)
    g.clear(0,0,0,1)
    if g.setBlendMode then g.setBlendMode('alpha','alphamultiply') end
    if g.setShader then g.setShader(sh) end
    if sh.send then sh:send('instanceBase',0) end
    g.drawInstanced(state.base,4)
    if g.setShader then g.setShader() end
    g.setCanvas()
    local img=canvas:newImageData()
    local function litAt(cx,cy)
      for dy=-1,1 do
        for dx=-1,1 do
          local x,y=cx+dx,cy+dy
          if x>=0 and x<64 and y>=0 and y<16 then
            local r,gc,b,a=img:getPixel(x,y)
            if (r or 0)+(gc or 0)+(b or 0) > 1.5 and (a or 0) > 0.1 then return true end
          end
        end
      end
      return false
    end
    local hits=0
    for _,cx in ipairs({8,24,40,56}) do if litAt(cx,8) then hits=hits+1 end end
    state.validated = hits >= 3
    if g.pop then g.pop() end
  end)
  if not ok then
    pcall(g.setCanvas)
    if g.setShader then pcall(g.setShader) end
    if g.pop then pcall(g.pop) end
    state.validated=true
  end
  if sh.release then pcall(sh.release,sh) end
  if canvas.release then pcall(canvas.release,canvas) end
  if state.validated==false then state.failed=true;state.reason='instance seed validation failed' end
  return state.validated
end

local function ensure()
  if state.failed then return false end
  if state.flakeShader and state.ballShader and state.pointShader and ((state.backend=='static-page' and state.staticPage and state.pointPage) or (state.base and state.pointBase and state.backend)) then return true end
  state.checks=state.checks+1
  local ok,reason=canGraphics(); if not ok then state.reason=reason; return false end
  local g=love.graphics

  if state.backend==nil then
    if nativeInstanceIdSupported() then state.backend='native-id'
    elseif instancingSupported() then state.backend='attribute-seed'
    else state.backend='static-page' end
  end

  local function ensureInstancedBase()
    if state.base then return true end
    local fmt={{'VertexPosition','float',3}}
    local verts={{-1,1,0},{1,1,0},{-1,-1,0},{1,-1,0}}
    local mok,m=pcall(g.newMesh,fmt,verts,'strip','static')
    if not mok or not m then return false end
    state.base=m; return true
  end

  local function ensurePointBase()
    if state.pointBase then return true end
    local fmt={{'VertexPosition','float',3}}
    local mok,m=pcall(g.newMesh,fmt,{{0,0,0}},'points','static')
    if not mok or not m then return false end
    state.pointBase=m; return true
  end

  local function ensureAttributeBackend()
    if not instancingSupported() or not ensureInstancedBase() or not ensurePointBase() then return false end
    if not state.seed then
      local okB,B=pcall(V.require,'InstanceSeedBuffer'); local sm,cap=nil,0
      if okB and B and B.get then sm,cap=B.get() end
      if not sm then return false end
      local aok=pcall(state.base.attachAttribute,state.base,'InstanceSeed',sm,'perinstance')
      local pok=pcall(state.pointBase.attachAttribute,state.pointBase,'InstanceSeed',sm,'perinstance')
      if not aok or not pok then return false end
      state.seed,state.seedCap=sm,tonumber(cap) or 8192
    end
    return true
  end

  if state.backend=='native-id' then
    if not ensureInstancedBase() or not ensurePointBase() then state.backend=instancingSupported() and 'attribute-seed' or 'static-page' end
  end
  if state.backend=='attribute-seed' and not ensureAttributeBackend() then state.backend='static-page' end
  if state.backend=='static-page' and (not ensureStaticPage() or not ensurePointPage()) then
    state.reason='static GPU snow page unavailable'; return false
  end

  local vertexSource=(state.backend=='native-id') and VERTEX_NATIVE or VERTEX_LEGACY
  local pointSource=(state.backend=='native-id') and VERTEX_POINT_NATIVE or VERTEX_POINT_LEGACY
  local function compileSet(source,pSource)
    local sok,flake=pcall(g.newShader,source..PIXEL_FLAKE)
    if not sok or not flake then return false end
    local bok,ball=pcall(g.newShader,source..PIXEL_BALL)
    if not bok or not ball then if flake.release then pcall(flake.release,flake) end; return false end
    local pok,point=pcall(g.newShader,pSource..PIXEL_POINT)
    if not pok or not point then
      if flake.release then pcall(flake.release,flake) end
      if ball.release then pcall(ball.release,ball) end
      return false
    end
    state.flakeShader,state.ballShader,state.pointShader=flake,ball,point
    return true
  end

  if not (state.flakeShader and state.ballShader and state.pointShader) and not compileSet(vertexSource,pointSource) then
    -- A GLSL3/mobile driver may advertise native instance IDs but reject them
    -- in LÖVE's shader dialect. Fall through to progressively more universal
    -- GPU paths before ever exposing the per-frame CPU snow mesh.
    if state.backend=='native-id' then
      state.backend='attribute-seed'; state.validated=nil
      if not ensureAttributeBackend() then state.backend='static-page' end
    elseif state.backend=='attribute-seed' then state.backend='static-page' end
    if state.backend=='static-page' and (not ensureStaticPage() or not ensurePointPage()) then
      state.failed=true; state.reason='all GPU snow backends unavailable'; return false
    end
    vertexSource=VERTEX_LEGACY;pointSource=VERTEX_POINT_LEGACY
    if not compileSet(vertexSource,pointSource) then state.failed=true;state.reason='snow shader set failed';return false end
  end
  if not validateInstancing() then return false end
  return true
end

function P.supported() return ensure() end
function P.canVirtualize() return ensure() and state.proven==true end

local function send(sh,name,value)
  local ok=pcall(sh.send,sh,name,value); return ok
end

local function uniform(sh,name,value)
  if send(sh,name,value) then return true end
  state.failed=true;state.reason='uniform upload failed: '..tostring(name);return false
end
-- 8.1.79: persistent uniform/vector scratch keeps the zero-upload snow field
-- free of per-draw option-table churn without changing authored inputs.
local ZERO3={0,0,0}
local ZERO2={0,0}
local WHITE={1,1,1}
local patchOffset={0,0}
local patchWind={0,0}
local tilePhase={0,0}
local snowAxisR={1,0,0}
local snowAxisU={0,1,0}

-- 8.2.2: one robust screen-aligned billboard basis per draw. Prefer the exact
-- view-projection rows (valid even at zenith); fall back to camera vectors only
-- on hosts that do not expose a conventional 4x4 VP matrix.
local function snowBillboardAxes(Voxel3D)
  local m=Voxel3D and Voxel3D.vp
  if type(m)=='table' then
    local rx,ry,rz=tonumber(m[1]),tonumber(m[2]),tonumber(m[3])
    local ux,uy,uz=tonumber(m[5]),tonumber(m[6]),tonumber(m[7])
    if rx and ry and rz and ux and uy and uz then
      local rl=math.sqrt(rx*rx+ry*ry+rz*rz)
      if rl>1e-7 then
        rx,ry,rz=rx/rl,ry/rl,rz/rl
        local dot=ux*rx+uy*ry+uz*rz;ux,uy,uz=ux-dot*rx,uy-dot*ry,uz-dot*rz
        local ul=math.sqrt(ux*ux+uy*uy+uz*uz)
        if ul>1e-7 then
          snowAxisR[1],snowAxisR[2],snowAxisR[3]=rx,ry,rz
          snowAxisU[1],snowAxisU[2],snowAxisU[3]=ux/ul,uy/ul,uz/ul
          return snowAxisR,snowAxisU
        end
      end
    end
  end
  local lf=Voxel3D and Voxel3D.lookFlat
  local x,z=type(lf)=='table' and tonumber(lf[1]) or nil,type(lf)=='table' and tonumber(lf[3] or lf[2]) or nil
  if x and z then
    local l=math.sqrt(x*x+z*z)
    if l>1e-7 then snowAxisR[1],snowAxisR[2],snowAxisR[3]=-z/l,0,x/l;snowAxisU[1],snowAxisU[2],snowAxisU[3]=0,1,0 end
  end
  return snowAxisR,snowAxisU
end

-- 8.1.55: the full visible snow field is now close enough to expose any
-- simulation-clock quantisation. Drive visual fall/tumble from a dedicated
-- monotonic presentation clock when the host provides one. A long pause or
-- debugger stall is clamped so flakes do not jump a huge distance on resume.
local function presentationTime(sourceTime,paused)
  local source=tonumber(sourceTime) or 0
  local host=nil
  if love and love.timer and type(love.timer.getTime)=='function' then
    local ok,v=pcall(love.timer.getTime)
    if ok and tonumber(v) then host=tonumber(v) end
  end
  if host then
    if state.renderHostTime==nil then
      state.renderHostTime=host
      state.renderClock=source
    else
      local dt=host-state.renderHostTime
      state.renderHostTime=host
      if dt<0 then dt=0 elseif dt>.10 then dt=.10 end
      if not paused then state.renderClock=(tonumber(state.renderClock) or source)+dt end
    end
    return state.renderClock
  end
  -- Headless/legacy hosts: preserve the caller clock, but never allow a
  -- backward phase that could reverse or jitter visible fall motion.
  if source>(tonumber(state.renderClock) or 0) then state.renderClock=source end
  return tonumber(state.renderClock) or source
end

-- Weather FX 8.2.0: there is no finite player-centered snow anchor or
-- old/new population handoff. The shader keeps stable flake identities in a
-- periodic world tile and selects each identity's nearest copy independently.
-- This prevents a moving overhead emitter and whole-screen snow reset while walking.
-- Map transitions record the exact new local-world focus. No population
-- handoff is required because the periodic snow field has no snapped origin.
function P.reanchor(focus,radius)
  local x=tonumber(focus and focus[1]) or 0
  local z=tonumber(focus and focus[3]) or 0
  state.anchorX,state.anchorZ,state.anchorCell=x,z,0
  state.anchorNextX,state.anchorNextZ,state.anchorNextCell=nil,nil,nil
  state.anchorT0=tonumber(focus and focus.time) or 0
  return x,z
end

function P.draw(Voxel3D,opts)
  opts=opts or {}; local count=math.max(0,math.floor(tonumber(opts.count) or 0))
  if count<=0 then return true,0 end
  if not ensure() then return false,0 end
  local g=love.graphics; local detailSh=(opts.ball and state.ballShader) or state.flakeShader
  local pointSh=state.pointShader
  local vp=Voxel3D and Voxel3D.vp
  if not vp then state.failed=true;state.reason='vp unavailable';return false,0 end
  local eye=opts.eye or ZERO3; local focus=opts.focus or ZERO3; local wind=opts.wind or ZERO2
  local now=presentationTime(opts.time,opts.paused==true)
  local ax=tonumber(focus[1]) or 0; local az=tonumber(focus[3]) or 0
  state.anchorX,state.anchorZ=ax,az;state.anchorCell=0
  state.anchorNextX,state.anchorNextZ,state.anchorNextCell=nil,nil,nil;state.anchorT0=now
  local M=mesoscaleModule(); local rp=(M and (not M.ready or M.ready()) and M.renderParams and M.renderParams()) or {}
  local uniformField=opts.uniformField==true
  patchOffset[1],patchOffset[2]=tonumber(rp.offsetX) or 0,tonumber(rp.offsetZ) or 0
  local pwx,pwz=tonumber(rp.windX) or .8,tonumber(rp.windZ) or .25
  local pwl=math.sqrt(pwx*pwx+pwz*pwz)
  if pwl<.001 then patchWind[1],patchWind[2]=.95,.30 else patchWind[1],patchWind[2]=pwx/pwl,pwz/pwl end
  local farRadius=math.max(4,tonumber(opts.farRadius) or 600)
  local patchScale=math.max(64,tonumber(rp.scale) or 520)
  local frontScale=math.max(patchScale,tonumber(rp.frontScale) or 1180)
  local patchiness=uniformField and 0 or (tonumber(rp.patchiness) or 0)
  local axisR,axisU=snowBillboardAxes(Voxel3D)
  local topY=tonumber(opts.topY) or 96; local bottomY=tonumber(opts.bottomY) or -16
  local spanY=tonumber(opts.span) or 64; local intensity=tonumber(opts.intensity) or 1
  local radialTaper=opts.radialTaper==true and 1 or 0
  local coreRadius=math.max(0,math.min(.85,tonumber(opts.coreRadius) or .20))
  local edgeKeep=math.max(.0000001,math.min(1,tonumber(opts.edgeKeep) or .08))
  local taperPower=math.max(1,math.min(18,tonumber(opts.taperPower) or 1))
  local spawnTop=topY+spanY; local totalH=math.max(4,spawnTop-bottomY)
  local fallScale=(.75+math.min(2.2,intensity)*.30)*.60
  local alpha=tonumber(opts.alpha)==nil and 1 or tonumber(opts.alpha)
  local tint=opts.tint or WHITE
  local anchored=state._anchor or {0,0,0};state._anchor=anchored
  anchored[2]=tonumber(focus[2]) or 0

  local function beginShader(sh)
    local began=false
    pcall(g.setBlendMode,'alpha','alphamultiply');pcall(g.setDepthMode,'lequal',false)
    if Voxel3D and Voxel3D.beginEffect then local ok,v=pcall(Voxel3D.beginEffect,sh);began=ok and v and true or false end
    if not began then pcall(g.setShader,sh) end
    return began
  end
  local function endShader(began)
    if Voxel3D and Voxel3D.endEffect and began then pcall(Voxel3D.endEffect) else pcall(g.setShader) end
  end
  local function configure(sh,radius,isPoint,detailRadius)
    if not send(sh,'vp',vp) then return false end
    local tileSpan=math.max(32,radius*1.77245385091);local tileInv=1/tileSpan
    local fx,fz=ax*tileInv,az*tileInv;tilePhase[1],tilePhase[2]=fx-math.floor(fx),fz-math.floor(fz)
    if not uniform(sh,'snowEye',eye) or not uniform(sh,'fieldWind',wind)
      or not uniform(sh,'fieldTileSpan',tileSpan) or not uniform(sh,'fieldTileInv',tileInv) or not uniform(sh,'fieldTilePhase',tilePhase)
      or not uniform(sh,'fieldFarFadeInv',1/math.max(.000001,(radius*1.15)*(radius*1.15)))
      -- Density taper always normalizes against the COMPLETE configured snow
      -- radius, including the near-detail subpass, so the close crystal field
      -- stays fully dense while only mid/far snowfall thins out.
      or not uniform(sh,'fieldDensityRadiusInv',1/math.max(.000001,farRadius))
      or not uniform(sh,'fieldRadialTaper',radialTaper)
      or not uniform(sh,'fieldCoreRadius',coreRadius)
      or not uniform(sh,'fieldEdgeKeep',edgeKeep)
      or not uniform(sh,'fieldTaperPower',taperPower)
      or not uniform(sh,'fieldSpawnTop',spawnTop) or not uniform(sh,'fieldTotalH',totalH)
      or not uniform(sh,'fieldFallScale',fallScale) or not uniform(sh,'fieldTime',now)
      or not uniform(sh,'fieldPatchFreq',1/patchScale) or not uniform(sh,'fieldPatchYFreq',0.686/patchScale)
      or not uniform(sh,'fieldFrontFreq',1/frontScale) or not uniform(sh,'fieldFrontCrossFreq',1/(frontScale*.71))
      or not uniform(sh,'fieldPatchOffset',patchOffset) or not uniform(sh,'fieldPatchWind',patchWind)
      or not uniform(sh,'fieldPatchiness',patchiness)
      or not uniform(sh,'fieldPatchFloor',uniformField and 1 or (tonumber(rp.floor) or 1))
      or not uniform(sh,'fieldAlpha',alpha) then return false end
    if isPoint then
      local inner=math.max(0,detailRadius*.72);local outer=math.max(inner+.001,detailRadius)
      if not uniform(sh,'fieldDetailInner2',inner*inner) or not uniform(sh,'fieldDetailOuter2',outer*outer) then return false end
    else
      if not uniform(sh,'fieldAxisR',axisR) or not uniform(sh,'fieldAxisU',axisU) then return false end
    end
    return true
  end
  local MAX_DRAW=math.max(1,state.seedCap or 8192)
  local function submit(sh,mesh,page,pageCap,n,baseStart,isPoint)
    n=math.max(0,math.floor(tonumber(n) or 0));if n<=0 then return 0 end
    local base=tonumber(baseStart) or 0
    anchored[1],anchored[3]=ax,az
    if not send(sh,'fieldFocus',anchored) then state.failed=true;state.reason='fieldFocus upload failed';return 0 end
    if state.backend=='static-page' then
      local done=0
      while done<n and not state.failed do
        local batch=math.min(pageCap,n-done)
        if not send(sh,'instanceBase',base+done) then state.failed=true;state.reason='instanceBase upload failed';break end
        if page.setDrawRange then pcall(page.setDrawRange,page,1,isPoint and batch or batch*6) end
        local ok=pcall(g.draw,page)
        if not ok then state.failed=true;state.reason='static snow page draw failed';break end
        done=done+batch;state.drawCalls=state.drawCalls+1
      end
      return done
    end
    if state.backend=='native-id' then
      if not send(sh,'instanceBase',base) then state.failed=true;state.reason='instanceBase upload failed';return 0 end
      local ok=pcall(g.drawInstanced,mesh,n)
      if not ok then state.failed=true;state.reason='drawInstanced failed';return 0 end
      state.drawCalls=state.drawCalls+1;return n
    end
    local done=0
    while done<n and not state.failed do
      local batch=math.min(MAX_DRAW,n-done)
      if not send(sh,'instanceBase',base+done) then state.failed=true;state.reason='instanceBase upload failed';break end
      local ok=pcall(g.drawInstanced,mesh,batch)
      if not ok then state.failed=true;state.reason='drawInstanced failed';break end
      done=done+batch;state.drawCalls=state.drawCalls+1
    end
    return done
  end

  -- 8.2.3 mobile/desktop LOD. Distant flakes are below meaningful crystal-detail
  -- resolution, so they use one point vertex instead of four translucent card
  -- vertices. The near field retains the exact detailed flake/ball shader. The
  -- split is area-preserving: detailCount has the same particles-per-world-area
  -- density as the complete logical field, while far points fade out where the
  -- detailed field takes over. Motion remains per-render-frame in both passes.
  local defaultDetailRadius=math.max(36,math.min(80,farRadius*.18))
  local detailRadius=math.min(farRadius,math.max(24,tonumber(opts.detailRadius) or defaultDetailRadius))
  local detailRatio=math.min(1,(detailRadius*detailRadius)/(farRadius*farRadius))
  local baseDetailCount=math.min(count,math.max(1,math.floor(count*detailRatio+.5)))
  -- 8.2.13 TSNOW can redirect some of the otherwise horizon-dominated visual
  -- budget into the near/overhead detailed-card shell. This does NOT increase
  -- the logical snow population or CPU interaction population. The extra
  -- detailed submissions are bounded so MAX gains storm structure without
  -- becoming a new low-end cost cliff.
  local detailBoost=math.max(1,math.min(2.5,tonumber(opts.detailDensityBoost) or 1))
  local detailExtraCap=math.max(0,math.floor(tonumber(opts.detailExtraCap) or 0))
  local boostedDetail=math.max(baseDetailCount,math.floor(baseDetailCount*detailBoost+.5))
  if detailExtraCap>0 then boostedDetail=math.min(boostedDetail,baseDetailCount+detailExtraCap) end
  local detailCount=math.min(count,boostedDetail)
  local useHybrid=count>=192 and pointSh~=nil
  local pointDrawn,detailDrawn=0,0
  pcall(g.setColor,tint[1] or 1,tint[2] or 1,tint[3] or 1,1)

  if useHybrid then
    local began=beginShader(pointSh)
    if configure(pointSh,farRadius,true,detailRadius) then
      local oldPoint=nil
      if type(g.getPointSize)=='function' then local ok,v=pcall(g.getPointSize);if ok then oldPoint=v end end
      if type(g.setPointSize)=='function' then pcall(g.setPointSize,math.min(2.0,1.40+math.max(0,math.min(5,intensity))*.12)) end
      if state.backend=='static-page' then pointDrawn=submit(pointSh,nil,state.pointPage,state.pointCap,count,0,true)
      else pointDrawn=submit(pointSh,state.pointBase,nil,0,count,0,true) end
      if oldPoint and type(g.setPointSize)=='function' then pcall(g.setPointSize,oldPoint) end
    end
    endShader(began)
    if pointDrawn~=count then
      -- Fail open to the established detailed path if a driver rejects point
      -- meshes at draw time. This is slower but never turns snow invisible.
      pointDrawn=0;detailCount=count;useHybrid=false
    end
  else
    detailCount=count
  end

  local began=beginShader(detailSh)
  if configure(detailSh,useHybrid and detailRadius or farRadius,false,detailRadius) then
    if state.backend=='static-page' then detailDrawn=submit(detailSh,nil,state.staticPage,state.staticCap,detailCount,0,false)
    else detailDrawn=submit(detailSh,state.base,nil,0,detailCount,0,false) end
  end
  endShader(began)
  pcall(g.setColor,1,1,1,1);pcall(g.setDepthMode,'lequal',true)
  if state.failed or detailDrawn~=detailCount then return false,math.min(count,pointDrawn+detailDrawn) end
  state.instances=state.instances+count
  state.pointInstances=state.pointInstances+pointDrawn
  state.detailInstances=state.detailInstances+detailDrawn
  state.proven=true
  return true,count
end

-- Invisible one-instance probe. WorldPrecip keeps the full legacy CPU field
-- until this has actually passed through the host's real shader + instancing
-- draw path; capability flags alone are not enough on older drivers.
function P.probe(Voxel3D,opts)
  opts=opts or {}; opts.count=1; opts.alpha=0
  local ok,n=P.draw(Voxel3D,opts)
  return ok==true and n==1
end

function P.invalidate()
  if state.base and state.base.release then pcall(state.base.release,state.base) end
  if state.staticPage and state.staticPage.release then pcall(state.staticPage.release,state.staticPage) end
  if state.pointBase and state.pointBase.release then pcall(state.pointBase.release,state.pointBase) end
  if state.pointPage and state.pointPage.release then pcall(state.pointPage.release,state.pointPage) end
  if state.flakeShader and state.flakeShader.release then pcall(state.flakeShader.release,state.flakeShader) end
  if state.ballShader and state.ballShader.release then pcall(state.ballShader.release,state.ballShader) end
  if state.pointShader and state.pointShader.release then pcall(state.pointShader.release,state.pointShader) end
  state.base,state.pointBase,state.seed,state.seedCap,state.staticPage,state.staticCap,state.pointPage,state.pointCap,state.backend,state.flakeShader,state.ballShader,state.pointShader=nil,nil,nil,0,nil,0,nil,0,nil,nil,nil,nil;state.failed=false;state.proven=false;state.reason=nil;state.validated=nil
  state.anchorX,state.anchorZ,state.anchorCell,state.anchorNextX,state.anchorNextZ,state.anchorNextCell,state.anchorT0=nil,nil,nil,nil,nil,nil,nil
  state.renderClock,state.renderHostTime=0,nil
end

function P.stats() return {supported=(not state.failed and (state.base~=nil or state.staticPage~=nil)),proven=state.proven,failed=state.failed,reason=state.reason,backend=state.backend,drawCalls=state.drawCalls,instances=state.instances,pointInstances=state.pointInstances,detailInstances=state.detailInstances,checks=state.checks,staticCap=state.staticCap,pointCap=state.pointCap,anchorX=state.anchorX,anchorZ=state.anchorZ,nextAnchorX=state.anchorNextX,nextAnchorZ=state.anchorNextZ,anchorCell=state.anchorCell,renderClock=state.renderClock} end
return P
