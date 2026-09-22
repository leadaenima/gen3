-- 2D tornado presentation. 8.1.58 adds a real relocation cutscene: the camera
-- is held by Tornado.lua, the real player sprite is replayed inside the vortex,
-- blackout is held until the engine confirms the destination map, and the
-- player is swept back in from the left before the tornado exits right.
local V=...
local Funnel={active=false,t=0,duration=2.5,onDone=nil,onPickup=nil,onCapture=nil,onDrop=nil,
  playerDrawer=nil,pickupAt=.55,pickupFired=false,captureFired=false,dropFired=false,
  mode="stationary",phase=nil,phaseT=0,destinationReady=false,waterTwister=false}
local motes={};local MOTES=90
local function rnd(a,b) local r=(love and love.math and love.math.random and love.math.random()) or math.random();return a+r*(b-a) end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function lerp(a,b,t) return a+(b-a)*t end
local function resetCallbacks()
  Funnel.onDone=nil;Funnel.onPickup=nil;Funnel.onCapture=nil;Funnel.onDrop=nil;Funnel.playerDrawer=nil
end
local function finish()
  local done=Funnel.onDone
  Funnel.active=false;resetCallbacks();Funnel.pickupFired=false;Funnel.captureFired=false;Funnel.dropFired=false
  Funnel.mode="stationary";Funnel.phase=nil;Funnel.phaseT=0;Funnel.destinationReady=false;Funnel.waterTwister=false
  if done then pcall(done) end
end
function Funnel.start(seconds,onDone,opts)
  opts=type(opts)=="table" and opts or nil
  Funnel.active=true;Funnel.t=0;Funnel.duration=math.max(.4,tonumber(seconds) or 2.5)
  Funnel.onDone=onDone;Funnel.onPickup=opts and opts.onPickup or nil;Funnel.onCapture=opts and opts.onCapture or nil;Funnel.onDrop=opts and opts.onDrop or nil
  Funnel.playerDrawer=opts and opts.playerDrawer or nil
  Funnel.pickupAt=math.max(.15,math.min(.85,tonumber(opts and opts.pickupAt) or .55))
  Funnel.pickupFired=false;Funnel.captureFired=false;Funnel.dropFired=false
  Funnel.mode=opts and tostring(opts.mode or "stationary") or "stationary";if Funnel.mode=="carry2d" then Funnel.mode="relocate2d" end
  Funnel.phase=Funnel.mode=="relocate2d" and "approach" or nil;Funnel.phaseT=0;Funnel.destinationReady=false
  Funnel.waterTwister=opts and opts.waterTwister and true or false
  motes={};for i=1,MOTES do motes[i]={h=rnd(0,1),a=rnd(0,math.pi*2),spin=rnd(1.8,4.2),size=rnd(.8,2.4),rise=rnd(.05,.30)} end
end
function Funnel.stop()
  if Funnel.active and Funnel.onDrop and Funnel.captureFired and not Funnel.dropFired then Funnel.dropFired=true;pcall(Funnel.onDrop) end
  Funnel.active=false;resetCallbacks();Funnel.pickupFired=false;Funnel.captureFired=false;Funnel.dropFired=false
  Funnel.mode="stationary";Funnel.phase=nil;Funnel.phaseT=0;Funnel.destinationReady=false;Funnel.waterTwister=false
end
function Funnel.relocationArrived() if Funnel.active and Funnel.mode=="relocate2d" then Funnel.destinationReady=true;return true end return false end
function Funnel.phaseName() return Funnel.phase end
function Funnel.blackoutActive()
  return Funnel.active and Funnel.mode=="relocate2d" and Funnel.phase=="blackout"
end
-- The normal weather compositor can be skipped/rebuilt while the engine swaps
-- overworld maps. A blackout drawn only there can therefore be replaced by the
-- destination map in the very frame where it matters. render.hud runs after
-- Renderer:endFrame(), so this post-composite guard paints the *actual window*
-- after the map transfer and before the host captures/presents the frame.
function Funnel.drawBlackoutOverlay(viewport)
  if not Funnel.blackoutActive() or not (love and love.graphics) then return false end
  local G=love.graphics
  if not (G.rectangle and G.setColor) then return false end
  -- push("all") is intentional: render.hud is shared mod territory and may
  -- inherit a transform, scissor, shader, blend mode or colour from another
  -- tool. The blackout must be absolute, then leave every bit of state intact.
  local pushed=false
  if G.push then pushed=pcall(G.push,"all") end
  if G.origin then pcall(G.origin) end
  if G.setScissor then pcall(G.setScissor) end
  if G.setShader then pcall(G.setShader) end
  if G.setBlendMode then pcall(G.setBlendMode,"alpha") end
  local w,h
  if G.getDimensions then
    local ok,a,b=pcall(G.getDimensions)
    if ok then w,h=tonumber(a),tonumber(b) end
  end
  if not (w and h and w>0 and h>0) then
    w=tonumber(viewport and viewport.width) or tonumber(viewport and viewport.windowW) or tonumber(viewport and viewport.gameWidth) or 160
    h=tonumber(viewport and viewport.height) or tonumber(viewport and viewport.windowH) or tonumber(viewport and viewport.gameHeight) or 144
  end
  G.setColor(0,0,0,1)
  G.rectangle("fill",0,0,w,h)
  if pushed and G.pop then pcall(G.pop) end
  return true
end
local function phaseDuration(ph)
  local d=Funnel.duration
  if ph=="approach" then return math.max(.80,d*.40) elseif ph=="sweepout" then return math.max(.85,d*.38)
  elseif ph=="blackout" then return .38 elseif ph=="sweepin" then return math.max(.95,d*.42) elseif ph=="exit" then return math.max(.85,d*.36) end
  return d
end
local function advanceRelocation(dt)
  Funnel.phaseT=Funnel.phaseT+dt;local ph=Funnel.phase;local pd=phaseDuration(ph)
  if ph=="approach" and Funnel.phaseT>=pd then Funnel.phase="sweepout";Funnel.phaseT=0;if not Funnel.captureFired then Funnel.captureFired=true;local cb=Funnel.onCapture;Funnel.onCapture=nil;if cb then pcall(cb) end end
  elseif ph=="sweepout" and Funnel.phaseT>=pd then Funnel.phase="blackout";Funnel.phaseT=0;if not Funnel.pickupFired then Funnel.pickupFired=true;local cb=Funnel.onPickup;Funnel.onPickup=nil;if cb then pcall(cb) end end
  elseif ph=="blackout" and Funnel.phaseT>=pd and Funnel.destinationReady then Funnel.phase="sweepin";Funnel.phaseT=0
  elseif ph=="sweepin" and Funnel.phaseT>=pd then Funnel.phase="exit";Funnel.phaseT=0;if not Funnel.dropFired then Funnel.dropFired=true;local cb=Funnel.onDrop;Funnel.onDrop=nil;if cb then pcall(cb) end end
  elseif ph=="exit" and Funnel.phaseT>=pd then finish() end
end
function Funnel.update(dt)
  if not Funnel.active then return end;dt=tonumber(dt) or 0;if dt<=0 then return end;if dt>.25 then dt=.25 end;Funnel.t=Funnel.t+dt
  if Funnel.mode=="relocate2d" then advanceRelocation(dt) else local p=math.min(1,Funnel.t/math.max(.001,Funnel.duration));if not Funnel.pickupFired and Funnel.onPickup and p>=Funnel.pickupAt then Funnel.pickupFired=true;local cb=Funnel.onPickup;Funnel.onPickup=nil;if cb then pcall(cb) end end;if Funnel.t>=Funnel.duration then finish() end end
  for i=1,#motes do local m=motes[i];m.a=m.a+m.spin*(1.6-m.h)*dt;m.h=m.h+m.rise*dt;if m.h>1 then m.h=0;m.a=rnd(0,math.pi*2) end end
end
local function relocationPose(x,y,w,h,px)
  local ph=Funnel.phase or "approach";local q=smooth(Funnel.phaseT/math.max(.001,phaseDuration(ph)));local margin=math.max(44*px,w*.18);local center=x+w*.5;local left=x-margin;local right=x+w+margin
  if ph=="approach" then return lerp(left,center,q),q,0,false elseif ph=="sweepout" then return lerp(center,right,q),1,math.min(1,q*1.18),true elseif ph=="blackout" then return right,1,1,false elseif ph=="sweepin" then return lerp(left,center,q),1,1-q,true elseif ph=="exit" then return lerp(center,right,q),1,0,false end
  return center,1,0,false
end
function Funnel.draw(x,y,w,h,scale)
  if not Funnel.active or not (love and love.graphics) or w<=1 or h<=1 then return false end
  local G=love.graphics;local px=math.max(.5,scale or 1);local pr,pg,pb,pa=G.getColor();local blend,alphaMode=G.getBlendMode();G.setBlendMode("alpha")
  local relocating=Funnel.mode=="relocate2d";local cx,grow,dark,drawPlayer
  if relocating then cx,grow,dark,drawPlayer=relocationPose(x,y,w,h,px) else local p=math.min(1,Funnel.t/math.max(.001,Funnel.duration));grow=math.min(1,p/.33);grow=grow*((p>.88) and (1-(p-.88)/.12) or 1);cx=x+w*.5;dark=.55*grow end
  if Funnel.phase=="blackout" then G.setColor(.015,.018,.025,1);G.rectangle("fill",x,y,w,h);local wr=Funnel.waterTwister;G.setColor(wr and .58 or .52,wr and .78 or .55,wr and .90 or .58,.18);for i=1,10 do local yy=y+h*(.08+i*.075);local off=((Funnel.t*.9+i*.137)%1)*w;G.rectangle("fill",x+off-w*.22,yy,w*.22,math.max(1,px*.7)) end;G.setBlendMode(blend,alphaMode);G.setColor(pr,pg,pb,pa);return true end
  if relocating then G.setColor(.025,.03,.045,.10+.90*dark);G.rectangle("fill",x,y,w,h) else G.setColor(.06,.05,.09,dark);G.rectangle("fill",x,y,w,h) end
  local water=Funnel.waterTwister;local ground=y+h*(relocating and .88 or .78);local top=y-h*.05;local height=ground-top;local lean=10*px
  for i=0,13 do local f=i/13;local wide=(34-26*f)*px*grow;local yy=top+height*f;local off=lean*(1-f)*math.sin(Funnel.t*2.2+f*2);if water then G.setColor(.18+.10*f,.31+.12*f,.39+.16*f,.66*grow) else G.setColor(.16,.14,.20,.55*grow) end;G.rectangle("fill",cx+off-wide*.5,yy,wide,height/14+1) end
  if water then G.setColor(.72,.86,.94,.34*grow);for i=1,3 do local rw=(13+i*8)*px;local rh=(2.2+i*.9)*px;if G.ellipse then G.ellipse("line",cx,ground-i*.7*px,rw,rh) end end;for i=1,18 do local a=Funnel.t*(4.2+(i%4)*.35)+i*.91;local rad=(6+(i%7)*2.1)*px;local sx=cx+math.cos(a)*rad;local sy=ground-(2+(i%5)*2.4)*px;G.setColor(.68,.84,.94,.18+.18*((i%3)/2));G.rectangle("fill",sx,sy,math.max(1,px*.7),math.max(1,px*1.8)) end end
  if relocating then G.setColor(water and .76 or .72,water and .84 or .70,water and .90 or .66,.20*grow);for i=1,9 do local sy=y+h*(.12+.075*i);local phase=((i*.173+Funnel.t*.34)%1);local sx=x+phase*w;local sw=(10+(i%3)*7)*px;G.rectangle("fill",sx-sw,sy,sw,math.max(1,.6*px)) end end
  if drawPlayer and Funnel.playerDrawer then local bob=math.sin(Funnel.t*8.2)*2.2*px;local ang=math.sin(Funnel.t*6.4)*.16;pcall(Funnel.playerDrawer,cx,ground-13*px+bob,ang,x,y,px) end
  for i=1,#motes do local m=motes[i];local f=1-m.h;local radius=(30-22*f)*px*grow;local yy=top+height*f;local off=lean*(1-f)*math.sin(Funnel.t*2.2+f*2);local mx=cx+off+math.cos(m.a)*radius;local depth=(math.sin(m.a)+1)*.5;local s=m.size*px*(.6+depth*.6);if water then G.setColor(.58+.16*depth,.72+.12*depth,.82+.12*depth,(.30+depth*.50)*grow) else G.setColor(.55,.50,.42,(.35+depth*.5)*grow) end;G.rectangle("fill",mx-s*.5,yy-s*.5,s,s) end
  G.setBlendMode(blend,alphaMode);G.setColor(pr,pg,pb,pa);return true
end
return Funnel
