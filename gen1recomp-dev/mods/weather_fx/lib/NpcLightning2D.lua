-- ==========================================================================
-- 2D NPC LIGHTNING TARGET + REACTION
-- ==========================================================================
-- Presentation-only house rule shared with the 3D NPC-lightning behaviour.
-- A scheduled flat-renderer lightning event gets the configured independent
-- chance to terminate on a real, visible overworld NPC.  No NPC coordinates,
-- movement, collision, scripts, save flags or sprite assets are mutated.
--
-- The reaction is redrawn over the finished world frame: rapid white/black
-- electrocution flashes with a tiny cartoon skeleton, then a charred silhouette
-- for the configured duration.  Smoke uses deliberately large, high-contrast
-- puffs so it remains readable on a 160x144 source frame after integer scaling.
-- ==========================================================================

local V = ...
local N = {
  CHANCE = 0.10,
  DURATION = 3.0,
  _effects = setmetatable({}, { __mode = "k" }),
  _hits = 0,
  _rolls = 0,
  _eligibleRolls = 0,
  _last = nil,
}

local floor,max,min,sin,pi = math.floor,math.max,math.min,math.sin,math.pi
local random = math.random
local FLASH_SECONDS, FLASH_STEP = 0.72, 0.060
local SMOKE_DELAY = 0.18
local charShader = nil

local function clamp01(x)
  x=tonumber(x) or 0
  if x<0 then return 0 elseif x>1 then return 1 end
  return x
end

local function settings()
  local enabled,chance,duration=true,N.CHANCE,N.DURATION
  local ok,C=pcall(V.require,"Config")
  if ok and C and type(C.get)=="function" then
    local okGet,cfg=pcall(C.get)
    local n=okGet and type(cfg)=="table" and cfg.npcLightning or nil
    if type(n)=="table" then
      if n.enabled~=nil then enabled=n.enabled and true or false end
      if tonumber(n.chance) then chance=clamp01(n.chance) end
      if tonumber(n.duration) then duration=max(.1,tonumber(n.duration)) end
    end
  end
  return enabled,chance,duration
end

local function obviousNonNpc(e)
  if not e then return true end
  local d=type(e.def)=="table" and e.def or {}
  if d.pushable==true then return true end
  local s=tostring(d.sprite or d.id or e.id or ""):upper()
  if s:find("BOULDER",1,true) or s:find("POKE_BALL",1,true)
      or s:find("POKEBALL",1,true) or s:find("ITEM_BALL",1,true)
      or s:find("FOSSIL",1,true) then return true end
  return false
end

local function overworld()
  local ok,S=pcall(V.require,"Scene")
  if not ok or not S or type(S.overworld)~="function" then return nil end
  local okOw,ow=pcall(S.overworld)
  return okOw and type(ow)=="table" and ow or nil
end

local function pose(e)
  if not e then return nil end
  if type(e.pose)=="function" then
    local ok,sprite,px,py,facing,phase,flip=pcall(e.pose,e)
    if ok and sprite then
      return sprite,tonumber(px) or tonumber(e.px),tonumber(py) or tonumber(e.py),
        facing or e.facing or "down",tonumber(phase) or 0,flip and true or false
    end
  end
  local sprite=e.sprite
  local px,py=tonumber(e.px),tonumber(e.py)
  if not (sprite and px and py) then return nil end
  local phase=0
  if type(e.walkPhase)=="function" then local ok,v=pcall(e.walkPhase,e);if ok then phase=tonumber(v) or 0 end end
  return sprite,px,py,e.facing or "down",phase,e.stepFlip and true or false
end

local function geometry(sprite,facing,phase,flip,frameOverride)
  if not sprite then return nil end
  if frameOverride and type(sprite.getFrameGeometry)=="function" then
    local ok,g=pcall(sprite.getFrameGeometry,sprite,frameOverride)
    if ok and g then g.mirror=false;return g end
  end
  if type(sprite.getPoseGeometry)=="function" then
    local ok,g=pcall(sprite.getPoseGeometry,sprite,facing,phase,flip)
    if ok and g then return g end
  end
  local fw=tonumber(sprite.frameWidth) or 16
  local fh=tonumber(sprite.frameHeight) or 16
  return {width=fw,height=fh,anchorX=tonumber(sprite.anchorX) or fw*.5,
    anchorY=tonumber(sprite.anchorY) or fh,quad=nil,mirror=false}
end

local function descriptor(e,camX,camY)
  if obviousNonNpc(e) then return nil end
  local sprite,px,py,facing,phase,flip=pose(e)
  if not (sprite and px and py) then return nil end
  local g=geometry(sprite,facing,phase,flip,e.frameOverride)
  if not g then return nil end
  local sx,sy
  if type(sprite.getScreenOrigin)=="function" then
    local ok,x,y=pcall(sprite.getScreenOrigin,sprite,px,py,camX,camY)
    if ok then sx,sy=tonumber(x),tonumber(y) end
  end
  if not (sx and sy) then
    local ax=tonumber(g.anchorX) or (tonumber(g.width) or 16)*.5
    local ay=tonumber(g.anchorY) or tonumber(g.height) or 16
    sx=floor(px-(tonumber(camX) or 0))+8-ax
    sy=floor(py-(tonumber(camY) or 0))+12-ay
  end
  local fw,fh=max(1,tonumber(g.width) or 16),max(1,tonumber(g.height) or 16)
  if sx>=160 or sy>=144 or sx+fw<=0 or sy+fh<=0 then return nil end
  return {entity=e,sprite=sprite,px=px,py=py,facing=facing,phase=phase,flip=flip,
    geometry=g,sx=sx,sy=sy,fw=fw,fh=fh,frameOverride=e.frameOverride}
end

local function currentDescriptor(entity,camX,camY)
  local ow=overworld();if not ow then return nil end
  for _,e in ipairs(ow.npcs or ow.entities or {}) do
    if e==entity then return descriptor(e,camX,camY) end
  end
  -- Some Gen2 hosts expose only entities; keep the exact object identity.
  for _,e in ipairs(ow.entities or {}) do if e==entity then return descriptor(e,camX,camY) end end
  return nil
end

local function targetRect(x,y,w,h)
  x,y=tonumber(x) or 0,tonumber(y) or 0;w,h=max(1,tonumber(w) or 160),max(1,tonumber(h) or 144)
  local ok,S=pcall(V.require,"Scene");local vp=ok and S and S.viewport or nil
  if type(vp)=="table" then
    local vx,vy,vw,vh=tonumber(vp.x),tonumber(vp.y),tonumber(vp.w),tonumber(vp.h)
    if vx and vy and vw and vh and vw>1 and vh>1
        and vx>=x-1 and vy>=y-1 and vx+vw<=x+w+1 and vy+vh<=y+h+1 then
      return vx,vy,vw,vh
    end
  end
  return x,y,w,h
end

local function candidates(camX,camY)
  local ow=overworld();if not ow then return {} end
  local player=ow.player or ow.hero or ow.avatar
  local out,seen={},{}
  local function add(e)
    if not e or e==player or seen[e] then return end
    seen[e]=true
    local d=descriptor(e,camX,camY)
    if d then out[#out+1]=d end
  end
  for _,e in ipairs(ow.npcs or {}) do add(e) end
  for _,e in ipairs(ow.entities or {}) do add(e) end
  return out
end

function N.rollImpact(camX,camY,viewW,viewH,chance,viewX,viewY)
  local enabled,configured=settings();if not enabled then return nil end
  chance=clamp01(chance==nil and configured or chance)
  if chance<=0 then return nil end
  N._rolls=N._rolls+1
  if random()>=chance then return nil end
  local list=candidates(camX,camY)
  if #list==0 then return nil end
  N._eligibleRolls=N._eligibleRolls+1
  local idx=1+floor(random()*#list);if idx>#list then idx=#list end
  local d=list[idx]
  local rx,ry,rw,rh=targetRect(tonumber(viewX) or 0,tonumber(viewY) or 0,viewW,viewH)
  -- Aim at the top quarter of the actual current frame, i.e. head/upper body.
  -- `hitX/hitY` are relative to the weather pass rect because Lightning.draw
  -- adds its own x/y origin.  This matters on 4:3/16:9 windows where the real
  -- 160x144 game image sits inside letterbox bars.
  local hx=d.sx+d.fw*.5
  local hy=d.sy+max(1,min(d.fh*.28,5))
  d.hitX=(rx-(tonumber(viewX) or 0))+hx/160*rw
  d.hitY=(ry-(tonumber(viewY) or 0))+hy/144*rh
  return d
end

function N.hit(target,duration)
  local e=target and target.entity;if not e then return false end
  local _,_,configured=settings()
  N._effects[e]={age=0,remaining=max(.1,tonumber(duration) or configured),target=target}
  N._hits=N._hits+1;N._last=e
  return true
end

function N.update(dt)
  dt=max(0,min(.25,tonumber(dt) or 0));if dt<=0 then return end
  for e,r in pairs(N._effects) do
    r.age=(tonumber(r.age) or 0)+dt;r.remaining=(tonumber(r.remaining) or 0)-dt
    if r.remaining<=0 then N._effects[e]=nil end
  end
end

local function shader()
  if charShader~=nil then return charShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then charShader=false;return nil end
  local ok,sh=pcall(love.graphics.newShader,[[
    extern vec3 wxTint;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p=Texel(tex,tc);
      return vec4(wxTint, p.a*color.a);
    }
  ]])
  charShader=(ok and sh) or false
  return charShader or nil
end

local function drawSprite(d,tint)
  if not (d and d.sprite and d.geometry and love and love.graphics) then return false end
  local image=nil
  if type(d.sprite.resolveImage)=="function" then local ok,v=pcall(d.sprite.resolveImage,d.sprite);if ok then image=v end end
  image=image or d.sprite.image
  if not image then return false end
  local g=d.geometry
  local q=g.quad
  if not q and type(d.sprite.getPoseGeometry)=="function" then
    local ok,gg=pcall(d.sprite.getPoseGeometry,d.sprite,d.facing,d.phase,d.flip);if ok and gg then g=gg;q=gg.quad end
  end
  if not q then return false end
  local sh=shader();if not sh then return false end
  pcall(love.graphics.setShader,sh);pcall(sh.send,sh,"wxTint",tint)
  pcall(love.graphics.setColor,1,1,1,1)
  if g.mirror then
    pcall(love.graphics.draw,image,q,d.sx+(tonumber(g.width) or d.fw),d.sy,0,-1,1)
  else
    pcall(love.graphics.draw,image,q,d.sx,d.sy)
  end
  pcall(love.graphics.setShader)
  return true
end

local function drawSkeleton(d,alpha)
  if not (love and love.graphics and d) then return end
  local x=d.sx+d.fw*.5;local top=d.sy;local h=d.fh;local w=d.fw
  local headY=top+h*.26;local chest=top+h*.48;local hip=top+h*.67;local foot=top+h*.91
  pcall(love.graphics.setColor,1,1,1,alpha)
  pcall(love.graphics.setLineWidth,max(1,min(2,w*.10)))
  pcall(love.graphics.circle,"line",x,headY,max(1,w*.11))
  pcall(love.graphics.line,x,headY+w*.11,x,chest,x,hip)
  for j=0,2 do local yy=chest+j*h*.055;local hw=w*(.20-j*.025);pcall(love.graphics.line,x-hw,yy,x+hw,yy) end
  pcall(love.graphics.line,x,top+h*.43,x-w*.28,top+h*.58)
  pcall(love.graphics.line,x,top+h*.43,x+w*.28,top+h*.58)
  pcall(love.graphics.line,x,hip,x-w*.20,foot)
  pcall(love.graphics.line,x,hip,x+w*.20,foot)
  pcall(love.graphics.setLineWidth,1)
end

local function drawEyes(d,alpha)
  local f=tostring(d.facing or "down"):lower();if f=="up" or f=="north" then return end
  local x=d.sx+d.fw*.5;local y=d.sy+d.fh*.29
  local sep=max(1,d.fw*.075);local ew=max(1,d.fw*.055);local eh=max(1,d.fh*.045)
  pcall(love.graphics.setColor,1,1,1,alpha)
  if f=="left" or f=="west" then pcall(love.graphics.rectangle,"fill",x-sep-ew*.5,y,ew,eh)
  elseif f=="right" or f=="east" then pcall(love.graphics.rectangle,"fill",x+sep-ew*.5,y,ew,eh)
  else
    pcall(love.graphics.rectangle,"fill",x-sep-ew*.5,y,ew,eh)
    pcall(love.graphics.rectangle,"fill",x+sep-ew*.5,y,ew,eh)
  end
end

local function drawSmoke(d,age,duration)
  if age<SMOKE_DELAY then return 0 end
  local tAge=age-SMOKE_DELAY
  local life=max(.25,(tonumber(duration) or N.DURATION)-SMOKE_DELAY)
  local overall=max(.20,1-tAge/life)
  local cx=d.sx+d.fw*.5;local baseY=d.sy-max(1,d.fh*.04)
  local count=0
  for j=0,5 do
    -- Keep the puffs visibly separated.  The earlier 8.1.60 candidate proved
    -- the smoke existed but six high-alpha circles overlapped into one black
    -- ball over the NPC.  This wider, faster-rising plume reads as smoke while
    -- remaining obvious at 5x integer scaling.
    local localAge=(tAge+j*.19)%1.38
    local u=localAge/1.38
    local side=(j-2.5)*.86+sin(tAge*4.7+j*1.9)*.34
    local px=cx+side;local py=baseY-localAge*7.1-j*.18
    local r=.90+1.25*u
    local a=(1-u)*.48*overall
    if a>.012 then
      pcall(love.graphics.setColor,.18,.18,.20,a)
      pcall(love.graphics.circle,"fill",px,py,r)
      pcall(love.graphics.setColor,.64,.64,.68,a*.34)
      pcall(love.graphics.circle,"fill",px-r*.16,py-r*.18,r*.52)
      count=count+1
    end
  end
  return count
end

function N.draw(x,y,w,h,camX,camY)
  if not (love and love.graphics) then return false end
  x,y=tonumber(x) or 0,tonumber(y) or 0;w,h=tonumber(w) or 160,tonumber(h) or 144
  if w<=1 or h<=1 then return false end
  local active={}
  for e,r in pairs(N._effects) do
    if (r.remaining or 0)>0 then local d=currentDescriptor(e,camX,camY);if d then active[#active+1]={d=d,r=r} end end
  end
  if #active==0 then return false end
  local rx,ry,rw,rh=targetRect(x,y,w,h)
  local sx,sy=rw/160,rh/144
  local pr,pg,pb,pa=love.graphics.getColor();local oldSh=love.graphics.getShader and love.graphics.getShader() or nil
  love.graphics.push();love.graphics.translate(rx,ry);love.graphics.scale(sx,sy)
  for _,a in ipairs(active) do
    local d,r=a.d,a.r;local age=tonumber(r.age) or 9
    local flashing=age<=FLASH_SECONDS;local white=flashing and (floor(age/FLASH_STEP)%2==0)
    drawSprite(d,white and {1,1,1} or {.01,.01,.012})
    if flashing and not white then drawSkeleton(d,1) elseif not flashing then drawEyes(d,.95) end
    drawSmoke(d,age,(tonumber(r.age) or 0)+(tonumber(r.remaining) or 0))
  end
  pcall(love.graphics.setShader,oldSh);love.graphics.pop();love.graphics.setColor(pr,pg,pb,pa)
  return true
end

function N.clearEffects() for e in pairs(N._effects) do N._effects[e]=nil end end
function N.activeCount() local n=0;for _,r in pairs(N._effects) do if (r.remaining or 0)>0 then n=n+1 end end;return n end
function N.stats() return {chance=select(2,settings()),active=N.activeCount(),hits=N._hits,rolls=N._rolls,eligibleRolls=N._eligibleRolls} end
function N.invalidate() N.clearEffects();charShader=nil end
function N._setRandom(fn) random=type(fn)=="function" and fn or math.random end

return N
