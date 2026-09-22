local V = ...

local Batcher={}
local meshCap=setmetatable({}, {__mode="k"})
local stats={uploads=0,reallocs=0,vertices=0,instancedDraws=0,fallbackDraws=0,frameUploads=0,frameVertices=0,peakFrameVertices=0}

local function graphics() return love and love.graphics end

function Batcher.capabilities()
  local g=graphics()
  return {mesh=not not(g and g.newMesh),instancing=not not(g and g.drawInstanced),attachAttribute=not not(g and g.newMesh)}
end

function Batcher.upload(mesh,fmt,vertices,n,usage,headroom)
  local g=graphics(); if not(g and g.newMesh) or not vertices then return nil end
  n=tonumber(n) or #vertices; if n<3 then return nil end
  usage=usage or "stream"; headroom=tonumber(headroom) or .30
  local cap=mesh and meshCap[mesh] or 0
  if not mesh or cap<n then
    local want=math.max(n,math.floor(n*(1+headroom))+64)
    local oldMesh=mesh
    local ok,m=pcall(g.newMesh,fmt,want,"triangles",usage)
    if not ok or not m then return nil end
    mesh=m; meshCap[mesh]=want; stats.reallocs=stats.reallocs+1
    -- 8.1.81: once the replacement exists, explicitly retire the superseded
    -- GPU buffer instead of waiting for Lua GC to eventually release VRAM.
    if oldMesh and oldMesh~=m and type(oldMesh.release)=="function" then pcall(oldMesh.release,oldMesh) end
  end
  local ok=pcall(mesh.setVertices,mesh,vertices,1,n)
  if not ok then
    local slice={}; for i=1,n do slice[i]=vertices[i] end
    if not pcall(mesh.setVertices,mesh,slice) then return nil end
  end
  if mesh.setDrawRange then pcall(mesh.setDrawRange,mesh,1,n) end
  stats.uploads=stats.uploads+1; stats.vertices=stats.vertices+n; stats.frameUploads=stats.frameUploads+1; stats.frameVertices=stats.frameVertices+n; if stats.frameVertices>stats.peakFrameVertices then stats.peakFrameVertices=stats.frameVertices end
  return mesh
end

function Batcher.draw(mesh,instances)
  local g=graphics(); if not(g and mesh) then return false end
  instances=math.max(1,math.floor(tonumber(instances) or 1))
  if instances>1 and g.drawInstanced then
    local ok=pcall(g.drawInstanced,mesh,instances); if ok then stats.instancedDraws=stats.instancedDraws+1; return true end
  end
  local ok=pcall(g.draw,mesh); if ok then stats.fallbackDraws=stats.fallbackDraws+1; return true end
  return false
end

function Batcher.beginFrame() stats.frameUploads=0; stats.frameVertices=0 end
function Batcher.stats() local o={}; for k,v in pairs(stats) do o[k]=v end; local c=Batcher.capabilities(); for k,v in pairs(c) do o[k]=v end; return o end
function Batcher.resetStats() for k in pairs(stats) do stats[k]=0 end end
return Batcher
