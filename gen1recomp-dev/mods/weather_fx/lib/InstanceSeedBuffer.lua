-- Weather FX 8.0.2: one shared static per-instance ID buffer.
--
-- LÖVE 11 can expose per-instance Mesh attributes even on some drivers that do
-- not provide GLSL3/love_InstanceID.  Procedural weather renderers attach this
-- tiny immutable buffer and add `instanceBase` per draw chunk.  Nothing here is
-- updated per frame, so a 200k field does not imply a 200k upload.
local V=...
local B={}
local state={mesh=nil,capacity=8192,failed=false,reason=nil,builds=0}

local function supportedGraphics()
  local g=love and love.graphics
  if not(g and type(g.newMesh)=='function' and type(g.drawInstanced)=='function') then return false,'instancing api unavailable' end
  if type(g.getSupported)=='function' then
    local ok,s=pcall(g.getSupported)
    if ok and type(s)=='table' and s.instancing==false then return false,'instancing unsupported' end
  end
  return true
end

function B.get()
  if state.failed then return nil,state.reason end
  if state.mesh then return state.mesh,state.capacity end
  local ok,reason=supportedGraphics(); if not ok then state.reason=reason; return nil,reason end
  local rows={}
  for i=1,state.capacity do rows[i]={i-1} end
  local mok,m=pcall(love.graphics.newMesh,{{'InstanceSeed','float',1}},rows,nil,'static')
  rows=nil
  if not mok or not m then state.failed=true;state.reason='instance seed mesh creation failed';return nil,state.reason end
  state.mesh=m;state.builds=state.builds+1
  return state.mesh,state.capacity
end

function B.supported() local m=B.get(); return m~=nil end
function B.capacity() return state.capacity end
function B.invalidate()
  if state.mesh and state.mesh.release then pcall(state.mesh.release,state.mesh) end
  state.mesh=nil;state.failed=false;state.reason=nil
end
function B.stats() return {capacity=state.capacity,built=state.mesh~=nil,failed=state.failed,reason=state.reason,builds=state.builds} end
return B
