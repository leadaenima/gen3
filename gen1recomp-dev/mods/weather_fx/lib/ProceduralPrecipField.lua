-- Weather FX 8.0.2: zero-upload far-field rain / hail / sand / ash.
--
-- The renderer keeps a physical near shell in WorldPrecip and synthesizes the
-- remaining authored population from a shared immutable instance seed. There is no per-particle
-- Lua table and no dynamic per-instance GPU upload. Leaves are deliberately not
-- virtualized: their voxel/NPC collision and settling behavior remains fully
-- physical at every distance.
local V=...
local P={}
local state={base=nil,seed=nil,seedCap=0,shader=nil,failed=false,proven=false,reason=nil,drawCalls=0,instances=0,checks=0,validated=nil,anchorX=nil,anchorZ=nil,anchorNextX=nil,anchorNextZ=nil,anchorT0=nil}
local _Meso=nil

-- 8.1.73: rain/hail procedural fields use fixed world anchors just like snow.
-- The previous renderer uploaded the live player focus every frame, so the
-- entire procedural precipitation pattern translated when the player walked.
-- A fixed 256-unit world cell plus short identity handoff keeps particles
-- world-space while still streaming indefinitely as the player travels.
local ANCHOR_CELL=24
local ANCHOR_CELL_MIN=4
local ANCHOR_HANDOFF=1.60
local NEXT_ID_BASE=1048576
local function smooth01(u)
  if u<0 then u=0 elseif u>1 then u=1 end
  return u*u*(3-2*u)
end
local function anchorCellForRadius(radius)
  local r=tonumber(radius) or ANCHOR_CELL*2
  -- Keep a world-fixed anchor, but keep it very close to the observer so a
  -- camera turn cannot expose the opposite edge of the rain disk. 8.1.75 used
  -- 8% of radius (up to 64 units), leaving as much as ~4% of the configured
  -- weather radius uncovered in one viewing direction between handoffs. Use a
  -- 4% cell capped at 24 units; maximum centre offset is about 2% of radius.
  return math.max(ANCHOR_CELL_MIN,math.min(ANCHOR_CELL,r*0.04))
end
local function anchorTarget(focus,radius)
  local x=tonumber(focus and focus[1]) or 0
  local z=tonumber(focus and focus[3]) or 0
  local cell=anchorCellForRadius(radius)
  return math.floor(x/cell+0.5)*cell,math.floor(z/cell+0.5)*cell,cell
end
local function anchorState(focus,now,radius)
  local tx,tz,cell=anchorTarget(focus,radius)
  if state.anchorX==nil then
    state.anchorX,state.anchorZ=tx,tz;state.anchorCell=cell;state.anchorNextX,state.anchorNextZ=nil,nil;state.anchorT0=now
    return state.anchorX,state.anchorZ,nil,nil,0
  end
  local function handoffU()
    if state.anchorNextX==nil then return 0 end
    return smooth01((now-(tonumber(state.anchorT0) or now))/ANCHOR_HANDOFF)
  end
  local u=handoffU()
  if state.anchorNextX~=nil and u>=.999999 then
    state.anchorX,state.anchorZ=state.anchorNextX,state.anchorNextZ
    state.anchorCell=state.anchorNextCell or cell
    state.anchorNextX,state.anchorNextZ,state.anchorNextCell=nil,nil,nil;state.anchorT0=now;u=0
  end
  if state.anchorNextX==nil then
    if tx~=state.anchorX or tz~=state.anchorZ or cell~=(state.anchorCell or cell) then
      state.anchorNextX,state.anchorNextZ,state.anchorNextCell=tx,tz,cell;state.anchorT0=now;u=0
    end
  elseif tx==state.anchorX and tz==state.anchorZ and cell==(state.anchorCell or cell) then
    state.anchorNextX,state.anchorNextZ,state.anchorNextCell=nil,nil,nil;state.anchorT0=now;u=0
  elseif tx~=state.anchorNextX or tz~=state.anchorNextZ or cell~=(state.anchorNextCell or cell) then
    if u>=.5 then state.anchorX,state.anchorZ,state.anchorCell=state.anchorNextX,state.anchorNextZ,state.anchorNextCell or cell end
    state.anchorNextX,state.anchorNextZ,state.anchorNextCell=tx,tz,cell;state.anchorT0=now;u=0
  end
  u=handoffU()
  return state.anchorX,state.anchorZ,state.anchorNextX,state.anchorNextZ,u
end
function P.reanchor(focus,radius)
  local x,z,cell=anchorTarget(focus,radius)
  state.anchorX,state.anchorZ,state.anchorCell=x,z,cell
  state.anchorNextX,state.anchorNextZ,state.anchorNextCell=nil,nil,nil
  state.anchorT0=tonumber(focus and focus.time) or 0
  return x,z
end
local function mesoscaleModule()
  if _Meso then return _Meso end
  local ok,m=pcall(V.require,'MesoscaleField'); if ok and m then _Meso=m end
  return _Meso
end

local VALIDATE_SHADER=[[
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

local function validateInstancing()
  if state.validated~=nil then return state.validated end
  local g=love and love.graphics
  if not g then state.validated=true; return true end
  if type(g.newCanvas)~='function' or type(g.setCanvas)~='function' or type(g.clear)~='function' or type(g.drawInstanced)~='function' then
    state.validated=true; return true
  end
  local canvasOk,canvas=pcall(g.newCanvas,64,16)
  if not canvasOk or not canvas or type(canvas.newImageData)~='function' then state.validated=true; return true end
  local shaderOk,sh=pcall(g.newShader,VALIDATE_SHADER)
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

local SHADER=[[
#ifdef VERTEX
attribute float InstanceSeed;
extern mat4 vp;
extern vec3 fieldFocus;
extern vec3 fieldEye;
extern vec2 fieldWind;
extern float fieldNear;
extern float fieldFar;
extern float fieldTop;
extern float fieldBottom;
extern float fieldSpan;
extern float fieldTime;
extern float fieldIntensity;
extern float fieldPatchScale;
extern float fieldFrontScale;
extern vec2 fieldPatchOffset;
extern vec2 fieldPatchWind;
extern float fieldPatchiness;
extern float fieldPatchFloor;
extern float fieldKind;
extern float fieldAlpha;
extern float fieldWorldGrid;
extern vec2 fieldGridBase;
extern vec2 fieldGridStep;
extern vec2 fieldGridShape;
extern float instanceBase;
varying vec3 vData;
varying float vAlpha;

float h1(float n){n=fract(n*0.1031);n*=n+33.33;n*=n+n;return fract(n);}
float wfxSinTurn(float t){float x=fract(t+0.5)*2.0-1.0;float y=4.0*x*(1.0-abs(x));return y*(0.775+0.225*abs(y));}
vec3 safeNorm(vec3 v,vec3 fallback){float l=length(v);return l<0.0001?fallback:v/l;}

vec4 position(mat4 transform_projection, vec4 vertex_position){
  float id=InstanceSeed+instanceBase+1.0;
  float particleKey=id;
  float a=h1(id*1.31+2.7),b=h1(id*2.17+8.1),c=h1(id*3.73+1.3);
  float d=h1(id*5.11+9.9),e=h1(id*7.23+4.5),f=h1(id*11.9+6.7);
  float ang=a*6.28318530718;
  float n2=fieldNear*fieldNear,f2=max(n2+0.01,fieldFar*fieldFar);
  float rad=sqrt(mix(n2,f2,b));
  vec3 center=fieldFocus+vec3(cos(ang)*rad,0.0,sin(ang)*rad);
  if(fieldWorldGrid>0.5){
    // Fronts-OFF precipitation/grain weather is a rendered-world field, not a
    // player/camera bubble. Rain, hail, sand/dust and ash all map instances to
    // absolute X/Z cells across the live voxel render window.
    // Map each instance onto an ABSOLUTE X/Z cell in the current voxel render
    // window. The window may advance as the camera moves, but cells that remain
    // visible keep the same world coordinates, jitter, fall phase and velocity.
    // Turning the camera therefore changes only which cells are viewed; it never
    // translates/reseeds the rain already occupying the world.
    float cols=max(1.0,fieldGridShape.x);
    float idx=id-1.0;
    float gx=mod(idx,cols);
    float gz=floor(idx/cols);
    vec2 cell=fieldGridBase+vec2(gx,gz);
    float key=cell.x*19.19+cell.y*73.71;
    particleKey=key;
    a=h1(key+2.7);b=h1(key*1.37+8.1);c=h1(key*2.11+1.3);
    d=h1(key*3.17+9.9);e=h1(key*4.23+4.5);f=h1(key*5.91+6.7);
    vec2 jitter=vec2(.12+.76*h1(key*7.13+3.2),.12+.76*h1(key*8.17+6.4));
    center.xz=(cell+jitter)*fieldGridStep;
    center.y=fieldFocus.y;
    rad=length(center.xz-fieldEye.xz);
  }
  float k=fieldKind;
  float size=0.25,alpha=0.6,roll=0.0;
  vec3 axisX,axisY;
  vec3 toEye;

  if(k<1.5){
    // RAIN: mirror the proven CPU streak proportions and ballistic tuning.
    // The previous procedural path used much shorter/thinner streaks, which
    // made 3D rain read like a camera-local particle effect instead of the
    // heavier world rain that shipped before GPU virtualization.
    float fall=(48.0+c*42.0)*(0.80+min(2.4,fieldIntensity)*0.28);
    float totalH=max(8.0,(fieldTop+fieldSpan)-fieldBottom);
    float travel=mod(fieldTime*fall+d*totalH,totalH);
    float age=travel/max(1.0,fall);
    center.y=fieldTop+fieldSpan-travel;
    float wv=0.65+f*0.70;
    vec2 personal=vec2(h1(particleKey*43.1)-0.5,h1(particleKey*47.3)-0.5)*3.5;
    vec3 vel=vec3(fieldWind.x*(10.0+e*14.0)*wv+personal.x,-fall,fieldWind.y*(10.0+h1(particleKey*53.9)*14.0)*wv+personal.y);
    center.xz+=vel.xz*age;
    toEye=fieldEye-center;
    vec3 view=safeNorm(toEye,vec3(0,0,1));
    vec3 dir=safeNorm(vel,vec3(0,-1,0));
    vec3 side=safeNorm(cross(dir,view),vec3(1,0,0));
    float eyeDist=max(0.001,length(toEye));
    float nearMix=1.0-clamp(eyeDist/max(1.0,fieldFar*1.15),0.0,1.0);
    float authoredSize=(0.55+c*1.50)*(0.40+nearMix*1.35);
    float closeWidth=clamp(eyeDist/9.0,0.35,1.0);
    float closeLen=clamp(eyeDist/14.0,0.20,1.0);
    // 8.1.76 water-streak profile: a rain drop is a very thin motion-blurred
    // line, not a broad billboard. Keep enough sub-pixel width to survive
    // distant rasterization, but let the pixel mask do the soft taper.
    float width=authoredSize*0.070*closeWidth;
    float len=authoredSize*3.35*closeLen;
    axisX=side*width;axisY=dir*(len*0.5);
    alpha=(0.22+e*0.26)*(0.30+nearMix*0.70)*clamp(eyeDist/3.0,0.0,1.0);
  } else if(k<2.5){
    // HAIL: small hard ice pellets, fast and nearly parallel.
    float fall=34.0+c*26.0;
    float totalH=max(8.0,(fieldTop+fieldSpan)-fieldBottom);
    float travel=mod(fieldTime*fall+d*totalH,totalH);
    float age=travel/fall;
    center.y=fieldTop+fieldSpan-travel;
    center.xz+=fieldWind*(6.0+e*10.0)*age*0.45;
    // Break perfectly parallel distant columns without turning hail into snow:
    // a tiny deterministic cross-wind wander keeps each pellet independent.
    center.xz+=vec2(h1(id*43.7)-0.5,h1(id*47.9)-0.5)*2.2
      +vec2(wfxSinTurn(fieldTime*(1.7+e*.9)*0.1591549431+id*.020690142),wfxSinTurn(fieldTime*(1.5+f*.8)*0.1591549431+id*.02705634+0.25))*.45;
    size=(0.16+c*0.20)*(0.75+0.55*(1.0-rad/max(1.0,fieldFar)));
    alpha=0.70+e*0.30;roll=0.10+c*0.10;
  } else if(k<3.5){
    // SAND/DUST: horizontal wall with the four authored altitude bands.
    float layer=c;
    float y=0.0,drive=0.0;
    if(layer<0.30){y=-0.8+d*9.0;drive=40.0+e*50.0;size=(0.38+f*0.55)*0.22;alpha=.48+h1(id*13.1)*.32;}
    else if(layer<0.58){y=3.0+d*22.0;drive=32.0+e*44.0;size=(0.22+f*0.42)*0.22;alpha=.40+h1(id*13.1)*.28;}
    else if(layer<0.82){y=14.0+d*38.0;drive=22.0+e*34.0;size=(0.12+f*0.28)*0.22;alpha=.28+h1(id*13.1)*.22;}
    else {y=6.0+d*30.0;drive=16.0+e*26.0;size=(0.10+f*0.22)*0.22;alpha=.22+h1(id*13.1)*.18;}
    center.y=fieldFocus.y+y;
    vec2 w=fieldWind;float wl=length(w);if(wl<.001)w=vec2(.7,.3);else w/=wl;
    float phase=fract(h1(id*17.7)+fieldTime*(.06+.08*e));
    center.xz+=w*((phase-.5)*fieldFar*1.45)+(vec2(-w.y,w.x)*(h1(id*19.9)-.5)*fieldFar*.35);
    center.x+=wfxSinTurn(fieldTime*(3.2+f*6.5)*0.1591549431+f*2.2281692)*8.5*.12;
    center.z+=wfxSinTurn(fieldTime*(2.4+f*4.0)*0.1591549431+f*1.4323945+0.25)*6.0*.12;
    alpha=min(1.0,alpha+(1.0-rad/max(1.0,fieldFar))*.18);
    size*=.9+(1.0-rad/max(1.0,fieldFar))*.4;
    roll=h1(id*23.1)*6.283185+fieldTime*(.6+f*2.2);
  } else {
    // ASH: slow cloud-deck fall with drifting, tumbling grey/black plates.
    float fall=5.5+c*7.5;
    float totalH=max(8.0,(fieldTop+fieldSpan)-fieldBottom);
    float travel=mod(fieldTime*fall+d*totalH,totalH);float age=travel/fall;
    center.y=fieldTop+fieldSpan-travel;
    center.xz+=fieldWind*(4.0+e*9.0)*age*.50+vec2(h1(id*29.1)-.5,h1(id*31.3)-.5)*5.0*age*.35;
    size=(.28+f*.50)*(.75+(1.0-rad/max(1.0,fieldFar))*.55);
    alpha=.28+h1(id*37.7)*.32+(1.0-rad/max(1.0,fieldFar))*.16;
    roll=h1(id*41.9)*6.283185+fieldTime*(1.4+f*3.6);
  }

  if(k>=1.5){
    toEye=fieldEye-center;vec3 view=safeNorm(toEye,vec3(0,0,1));
    vec3 right=safeNorm(vec3(-view.z,0.0,view.x),vec3(1,0,0));
    vec3 up=safeNorm(cross(view,right),vec3(0,1,0));
    float ca=cos(roll),sa=sin(roll);
    float hx=size*.5,hy=size*.5;
    if(k>=2.5&&k<3.5){float streak=1.15+min(2.4,(18.0+e*45.0)*.028);hx*=streak;hy*=.62;}
    if(k>=3.5){if(f<.333){hx*=.9;hy*=1.1;}else if(f<.666){hx*=.35;hy*=1.55;}else{hx*=.9;hy*=.9;}}
    axisX=(right*ca+up*sa)*hx;axisY=(up*ca-right*sa)*hy;
  }
  vec2 corner=vertex_position.xy;vec3 world=center+axisX*corner.x+axisY*corner.y;
  // Cheap mesoscale reconstruction: broad world-space rain/snow bands move
  // with the simulation without any per-instance CPU upload. Severe systems
  // reduce patchiness through fieldPatchFloor; sand keeps only a faint gust
  // modulation so a dust wall does not develop arbitrary holes.
  float ps=max(64.0,fieldPatchScale);
  vec2 delta=center.xz-fieldPatchOffset;
  vec2 wd=fieldPatchWind; float wdl=length(wd); if(wdl<.001)wd=vec2(.95,.30);else wd/=wdl;
  float along=dot(delta,wd),crossp=dot(delta,vec2(-wd.y,wd.x));
  float fs=max(ps,fieldFrontScale);
  float crossWave=wfxSinTurn(crossp/(fs*.71));
  float wave=.5+.5*wfxSinTurn(along/fs + crossWave*.114591559);
  vec2 wp=delta/ps;
  float localWave=wfxSinTurn(wp.y*.685957805);
  float localp=.5+.5*wfxSinTurn(wp.x + localWave*.114591559);
  float band=smoothstep(.16,.84,localp*.64+wave*.36);
  float pk=fieldPatchiness;if(k>=2.5&&k<3.5)pk*=.25;
  float patch=mix(1.0,mix(fieldPatchFloor,1.08,band),clamp(pk,0.0,1.0));
  vData=vec3(corner.x*.5+.5,.5-corner.y*.5,f);vAlpha=clamp(alpha*patch*fieldAlpha,0.0,1.0);
  return vp*vec4(world,1.0);
}
#endif

#ifdef PIXEL
extern float fieldKind;
varying vec3 vData;
varying float vAlpha;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc){
  vec2 p=vData.xy*2.0-1.0;float k=fieldKind;float shape=1.0;
  vec4 outc=color;
  float alpha=vAlpha;
  if(k<1.5){
    // 8.1.76: tapered translucent water streak. vData.y runs tail->head in
    // screen-independent streak space; the width narrows strongly toward the
    // tail, both ends feather out, and only a slim centre core catches light.
    float along=clamp(1.0-vData.y,0.0,1.0);
    float taper=.18+.82*sqrt(max(0.0,along));
    taper*=1.0-.18*smoothstep(.86,1.0,along);
    float nx=abs(p.x)/max(.12,taper);
    float side=1.0-smoothstep(.16,1.0,nx);
    float ends=smoothstep(.015,.14,along)*(1.0-smoothstep(.94,1.0,along));
    float core=1.0-smoothstep(.02,.28,nx);
    shape=side*ends*(.46+.54*core);
    alpha*=shape*.82;
    vec3 water=outc.rgb*vec3(.62,.72,.82);
    float glint=core*smoothstep(.62,.90,along)*(1.0-smoothstep(.92,1.0,along));
    outc.rgb=mix(water,min(vec3(1.0),water+vec3(.10,.12,.14)),glint*.30);
  } else if(k<2.5){float d=dot(p,p);shape=1.0-smoothstep(.35,1.0,d);shape*=shape;alpha*=shape;}
  else if(k<3.5){float d=dot(p,p);shape=1.0-smoothstep(.18,1.0,d);shape*=shape;alpha*=shape;}
  else {vec2 ap=abs(p);float hexr=max(ap.y,ap.x*.8660254+ap.y*.5);float jag=.80+(vData.z-.5)*.14;shape=1.0-smoothstep(jag-.18,jag,hexr);alpha*=shape;float dark=step(.5,vData.z);outc.rgb=mix(color.rgb,vec3(.10,.10,.11),dark*.82);}
  if(alpha<.012)discard;
  return vec4(outc.rgb,outc.a*alpha);
}
#endif
]]

local function ensure()
  if state.failed then return false end
  if state.base and state.shader then return true end
  local g=love and love.graphics
  if not(g and type(g.newMesh)=='function' and type(g.newShader)=='function' and type(g.drawInstanced)=='function')then state.reason='instancing api unavailable';return false end
  if type(g.getSupported)=='function'then local ok,s=pcall(g.getSupported);if ok and type(s)=='table'and s.instancing==false then state.reason='instancing unsupported';return false end end
  state.checks=state.checks+1
  if not state.base then local ok,m=pcall(g.newMesh,{{'VertexPosition','float',3}},{{-1,1,0},{1,1,0},{-1,-1,0},{1,-1,0}},'strip','static');if not ok or not m then state.failed=true;state.reason='base mesh creation failed';return false end;state.base=m end
  if not state.seed then local okB,B=pcall(V.require,'InstanceSeedBuffer');local sm,cap=nil,0;if okB and B and B.get then sm,cap=B.get() end;if not sm then state.reason='instance seed buffer unavailable';return false end;local aok=pcall(state.base.attachAttribute,state.base,'InstanceSeed',sm,'perinstance');if not aok then state.failed=true;state.reason='instance seed attach failed';return false end;state.seed,state.seedCap=sm,tonumber(cap)or 8192 end
  if not state.shader then local ok,sh=pcall(g.newShader,SHADER);if not ok or not sh then state.failed=true;state.reason='procedural precip shader failed';return false end;state.shader=sh end
  if not validateInstancing() then return false end
  return true
end
function P.supported()return ensure()end
function P.canVirtualize()return ensure() and state.proven==true end
local function send(sh,n,v)return pcall(sh.send,sh,n,v)end
local function uniform(sh,name,value) if send(sh,name,value) then return true end;state.failed=true;state.reason='uniform upload failed';return false end
local KIND={rain=1,hail=2,sand=3,ash=4}
-- 8.1.79: all draw-call option/uniform scratch is module-owned and reused.
-- This removes transient vector/field tables from the zero-upload precipitation
-- path without changing any shader inputs, instance counts, anchors or timing.
local ZERO3={0,0,0}
local ZERO2={0,0}
local WHITE={1,1,1}
local patchOffset={0,0}
local patchWind={0,0}
local gridBase={0,0}
local gridStep={1,1}
local gridShape={1,1}
local function renderedWorldGrid(eye,far,count)
  far=math.max(4,tonumber(far) or 400);count=math.max(1,math.floor(tonumber(count) or 1))
  local cols=math.max(3,math.ceil(math.sqrt(count)))
  local rows=math.max(3,math.ceil(count/cols))
  -- One guard cell on every side guarantees the grid covers the complete
  -- 2*far voxel window even while the absolute-cell origin snaps forward.
  local sx=(2*far)/math.max(1,cols-2)
  local sz=(2*far)/math.max(1,rows-2)
  local ex=tonumber(eye and eye[1]) or 0;local ez=tonumber(eye and eye[3]) or 0
  local bx=math.floor((ex-far)/sx)-1
  local bz=math.floor((ez-far)/sz)-1
  return bx,bz,sx,sz,cols,rows
end
function P.draw(Voxel3D,opts)
  opts=opts or{};local count=math.max(0,math.floor(tonumber(opts.count)or 0));if count<=0 then return true,0 end;if not ensure()then return false,0 end
  local g=love.graphics;local sh=state.shader;local began=false
  pcall(g.setBlendMode,'alpha','alphamultiply');pcall(g.setDepthMode,'lequal',false)
  if Voxel3D and Voxel3D.beginEffect then local ok,v=pcall(Voxel3D.beginEffect,sh);began=ok and v and true or false end;if not began then pcall(g.setShader,sh)end
  local vp=Voxel3D and Voxel3D.vp;if not vp or not send(sh,'vp',vp)then state.failed=true;state.reason='vp upload failed';return false,0 end
  local M=mesoscaleModule(); local rp=(M and (not M.ready or M.ready()) and M.renderParams and M.renderParams()) or {}
  local uniformField=opts.uniformField==true
  local worldGrid=opts.worldGrid==true and tostring(opts.kind or 'rain')~='debris'
  local focus=opts.focus or ZERO3;local eye=opts.eye or ZERO3;local now=tonumber(opts.time)or 0
  local ax,az,bx,bz,handoff
  if worldGrid then ax,az=tonumber(focus[1])or 0,tonumber(focus[3])or 0;bx,bz,handoff=nil,nil,0 else ax,az,bx,bz,handoff=anchorState(focus,now,tonumber(opts.farRadius)) end
  local gbx,gbz,gsx,gsz,gcols,grows=0,0,1,1,1,1
  if worldGrid then gbx,gbz,gsx,gsz,gcols,grows=renderedWorldGrid(eye,tonumber(opts.farRadius),count) end
  if worldGrid then
    local lg=state.lastGrid or {};state.lastGrid=lg
    lg.baseX,lg.baseZ,lg.stepX,lg.stepZ,lg.cols,lg.rows,lg.far=gbx,gbz,gsx,gsz,gcols,grows,tonumber(opts.farRadius)or 0
  else state.lastGrid=nil end
  patchOffset[1],patchOffset[2]=tonumber(rp.offsetX)or 0,tonumber(rp.offsetZ)or 0
  patchWind[1],patchWind[2]=tonumber(rp.windX)or .8,tonumber(rp.windZ)or .25
  gridBase[1],gridBase[2]=gbx,gbz;gridStep[1],gridStep[2]=gsx,gsz;gridShape[1],gridShape[2]=gcols,grows
  local wind=opts.wind or ZERO2
  if not uniform(sh,'fieldEye',eye) or not uniform(sh,'fieldWind',wind)
    or not uniform(sh,'fieldNear',tonumber(opts.nearRadius)or 96) or not uniform(sh,'fieldFar',tonumber(opts.farRadius)or 400)
    or not uniform(sh,'fieldTop',tonumber(opts.topY)or 96) or not uniform(sh,'fieldBottom',tonumber(opts.bottomY)or-18)
    or not uniform(sh,'fieldSpan',tonumber(opts.span)or 64) or not uniform(sh,'fieldTime',now)
    or not uniform(sh,'fieldIntensity',tonumber(opts.intensity)or 1) or not uniform(sh,'fieldPatchScale',tonumber(rp.scale)or 520)
    or not uniform(sh,'fieldFrontScale',tonumber(rp.frontScale)or 1180) or not uniform(sh,'fieldPatchOffset',patchOffset)
    or not uniform(sh,'fieldPatchWind',patchWind) or not uniform(sh,'fieldPatchiness',uniformField and 0 or (tonumber(rp.patchiness)or 0))
    or not uniform(sh,'fieldPatchFloor',uniformField and 1 or (tonumber(rp.floor)or 1)) or not uniform(sh,'fieldKind',KIND[opts.kind]or 1)
    or not uniform(sh,'fieldAlpha',tonumber(opts.alpha)==nil and 1 or tonumber(opts.alpha)) or not uniform(sh,'fieldWorldGrid',worldGrid and 1 or 0)
    or not uniform(sh,'fieldGridBase',gridBase) or not uniform(sh,'fieldGridStep',gridStep) or not uniform(sh,'fieldGridShape',gridShape) then
  end
  local tint=opts.tint or WHITE;pcall(g.setColor,tint[1]or 1,tint[2]or 1,tint[3]or 1,1)
  local MAX_DRAW=math.max(1,state.seedCap or 8192)
  local anchored=state._anchor or {0,0,0};state._anchor=anchored
  local function submitFixed(anchorX,anchorZ,n,baseStart)
    n=math.max(0,math.floor(tonumber(n)or 0));if n<=0 then return 0 end
    anchored[1],anchored[2],anchored[3]=anchorX,tonumber(focus[2])or 0,anchorZ
    if not send(sh,'fieldFocus',anchored)then state.failed=true;state.reason='fieldFocus upload failed';return 0 end
    local done=0;local base=tonumber(baseStart)or 0
    while done<n and not state.failed do
      local batch=math.min(MAX_DRAW,n-done)
      if not send(sh,'instanceBase',base+done)then state.failed=true;state.reason='instanceBase upload failed';break end
      local ok=pcall(g.drawInstanced,state.base,batch);if not ok then state.failed=true;state.reason='drawInstanced failed';break end
      done=done+batch;state.drawCalls=state.drawCalls+1
    end
    return done
  end
  local newCount=0
  if bx~=nil then newCount=math.floor(count*handoff+0.5);if newCount<0 then newCount=0 elseif newCount>count then newCount=count end end
  local drawn=submitFixed(ax,az,count-newCount,0)
  if not state.failed and newCount>0 then drawn=drawn+submitFixed(bx,bz,newCount,NEXT_ID_BASE) end
  state.instances=state.instances+drawn;pcall(g.setColor,1,1,1,1);if Voxel3D and Voxel3D.endEffect and began then pcall(Voxel3D.endEffect)else pcall(g.setShader)end;pcall(g.setDepthMode,'lequal',true)
  if not state.failed and drawn==count then state.proven=true end
  return not state.failed,drawn
end
function P.probe(Voxel3D,opts)
  opts=opts or{};opts.count=1;opts.alpha=0
  local ok,n=P.draw(Voxel3D,opts)
  return ok==true and n==1
end
function P.invalidate()if state.base and state.base.release then pcall(state.base.release,state.base)end;if state.shader and state.shader.release then pcall(state.shader.release,state.shader)end;state.base,state.seed,state.seedCap,state.shader=nil,nil,0,nil;state.failed=false;state.proven=false;state.reason=nil;state.validated=nil;state.lastGrid=nil;state.anchorX,state.anchorZ,state.anchorCell,state.anchorNextX,state.anchorNextZ,state.anchorNextCell,state.anchorT0=nil,nil,nil,nil,nil,nil,nil end
function P.stats()return{supported=(not state.failed and state.base~=nil),proven=state.proven,failed=state.failed,reason=state.reason,drawCalls=state.drawCalls,instances=state.instances,checks=state.checks,anchorX=state.anchorX,anchorZ=state.anchorZ,nextAnchorX=state.anchorNextX,nextAnchorZ=state.anchorNextZ,anchorCell=state.anchorCell,lastGrid=state.lastGrid}end
return P
