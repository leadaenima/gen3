-- Small player-movement response to the existing authoritative WindEngine.
-- No second wind simulation: this only consumes local WindFlow. Walking into
-- strong exposed wind is slightly slower; a tailwind is very slightly faster.
local V=...
local mod=V.mod
local W={_hooked=false,_freeMoveHosts=setmetatable({},{__mode="k"})}
local sqrt=math.sqrt
local function clamp(v,a,b) v=tonumber(v) or 0;if v<a then return a elseif v>b then return b end return v end
local function req(n) local ok,m=pcall(V.require,n);return ok and m or nil end
local function config()
  local C=req("Config");local c=C and C.get and C.get() or {};return type(c.wind)=="table" and c.wind or {}
end
local function playerPos()
  local S=req("Scene");local n=S and S.now or {};return tonumber(n.playerWorldX),tonumber(n.playerWorldY)
end
function W.distanceMultiplier(dx,dz)
  local c=config();if c.playerMovement==false then return 1 end
  local T=req("Tornado");if T and T.isCarrying and T.isCarrying() then return 1 end
  dx,dz=tonumber(dx) or 0,tonumber(dz) or 0;local dl=sqrt(dx*dx+dz*dz);if dl<1e-6 then return 1 end
  local px,pz=playerPos();local F=req("WindFlow");local f=F and F.sampleAt and F.sampleAt(px or 0,pz or 0) or nil
  local wx,wz,sp=f and tonumber(f.x),f and tonumber(f.z),f and tonumber(f.speed)
  if not wx or not wz then local E=req("WindEngine");local e=E and E.peek and E.peek() or {};wx,wz,sp=tonumber(e.x) or 0,tonumber(e.z) or 0,tonumber(e.strength) or 0 end
  sp=tonumber(sp) or sqrt(wx*wx+wz*wz);local min=tonumber(c.minimumStrength) or .10;if sp<=min then return 1 end
  local wl=sqrt(wx*wx+wz*wz);if wl<1e-6 then return 1 end
  local dot=(dx/dl)*(wx/wl)+(dz/dl)*(wz/wl);local force=clamp((sp-min)/math.max(.15,1.20-min),0,1)
  local slow=clamp(c.headwindSlow or .10,0,.25);local boost=clamp(c.tailwindBoost or .04,0,.12)
  if dot<0 then return 1-slow*force*(-dot) end
  return 1+boost*force*dot
end
local DIR={up={0,-1},down={0,1},left={-1,0},right={1,0},north={0,-1},south={0,1},west={-1,0},east={1,0}}
function W.installHooks()
  if W._hooked then return true end
  if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then return false end
  local ok=pcall(function()
    mod.hooks:wrap("movement.speed",function(next,frames,ctx)
      frames=next(frames,ctx);local p=ctx and ctx.player
      if not p or ctx.onBike or ctx.surfing or p.surfing then return frames end
      local d=DIR[tostring(p.facing or ""):lower()];if not d then return frames end
      local m=W.distanceMultiplier(d[1],d[2]);if math.abs(m-1)<.002 then return frames end
      local base=tonumber(frames)
      if base==nil then return frames end
      -- Preserve the host's exact game-speed scale, including legitimate
      -- sub-1-frame fast modes. Weather FX only applies the wind ratio.
      return base/m
    end)
  end)
  W._hooked=ok and true or false;return W._hooked
end
function W.installFreeMove(hostLib)
  if not hostLib or W._freeMoveHosts[hostLib] then return false end
  local okFM,FM=pcall(hostLib.require,"FreeMove");local okFP,FP=pcall(hostLib.require,"FirstPerson")
  if not (okFM and okFP and type(FM)=="table" and type(FM.tick)=="function" and type(FP)=="table" and type(FP.moveWorld)=="function") then return false end
  local original=FM.tick
  FM.tick=function(...)
    local old=FP.moveWorld
    FP.moveWorld=function(...)
      local a,b,c,d=old(...)
      if type(a)=="number" and type(b)=="number" then local m=W.distanceMultiplier(a,b);return a*m,b*m,c,d end
      return a,b,c,d
    end
    local ok,a,b,c,d,e=pcall(original,...);FP.moveWorld=old
    if not ok then error(a,0) end
    return a,b,c,d,e
  end
  W._freeMoveHosts[hostLib]=true;return true
end
return W
