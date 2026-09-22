local V = ...

local HostAdapter = {}
local cached={host=nil,voxel=nil,scene=nil,capabilities={},serial=0}

local function safeRequire(name)
  local ok,v=pcall(V.require,name); if ok then return v end
  return nil
end

function HostAdapter.refresh()
  cached.serial=cached.serial+1
  local Interop=safeRequire("Interop")
  local host=nil
  if Interop and Interop.hostLib then pcall(function() host=Interop.hostLib() end) end
  cached.host=host
  local voxel=nil
  if host and type(host.require)=="function" then pcall(function() voxel=host.require("Voxel3D") end) end
  cached.voxel=voxel
  local g=love and love.graphics
  cached.capabilities={
    voxel=voxel~=nil,
    mesh=not not (g and g.newMesh),
    instancing=not not (g and g.drawInstanced and g.newMesh),
    shader=not not (g and g.newShader),
    depth=not not (g and g.setDepthMode),
  }
  return cached
end

function HostAdapter.state() if cached.serial==0 then HostAdapter.refresh() end; return cached end
function HostAdapter.voxel() return HostAdapter.state().voxel end
function HostAdapter.capabilities() local o={}; for k,v in pairs(HostAdapter.state().capabilities) do o[k]=v end; return o end

function HostAdapter.camera()
  local v=HostAdapter.voxel(); if not v then return nil end
  return {eye=v.eye,focus=v.focus,far=v.far or (v.camera and v.camera.far),vp=v.vp}
end

function HostAdapter.worldPosition()
  -- The weather simulation must follow the PLAYER, never the camera look target.
  -- Voxel3D.focus is a view/orbit target on several hosts and changes when the
  -- camera rotates; using it first made StormCells steer and cloud fronts slide
  -- around a stationary player. Scene publishes the authoritative continuous
  -- player position, so prefer it before any camera-facing voxel fallback.
  local Scene=safeRequire("Scene"); local n=Scene and Scene.now or {}
  if n and n.playerPosKnown then
    return tonumber(n.playerWorldX) or 0, tonumber(n.playerWorldY) or 0
  end
  -- Compatibility fallback for older Scene shapes used by a few forks.
  local p=n and n.player
  if p then return tonumber(p.px or p.x) or 0,tonumber(p.py or p.y) or 0 end
  local v=HostAdapter.voxel()
  if v and v.player then return tonumber(v.player[1]) or 0,tonumber(v.player[3]) or 0 end
  -- Last-resort legacy fallback only. A host exposing only focus gives us no
  -- better world anchor, but modern supported hosts hit one of the paths above.
  if v and v.focus then return tonumber(v.focus[1]) or 0,tonumber(v.focus[3]) or 0 end
  return 0,0
end

function HostAdapter.describe()
  local c=HostAdapter.capabilities()
  return string.format("voxel=%s mesh=%s instancing=%s shader=%s depth=%s",tostring(c.voxel),tostring(c.mesh),tostring(c.instancing),tostring(c.shader),tostring(c.depth))
end

return HostAdapter
