local V = ...

local ChunkSim = {}
ChunkSim.__index = ChunkSim

local floor, abs = math.floor, math.abs
local function key(x,z) return tostring(x)..":"..tostring(z) end

function ChunkSim.new(opts)
  opts=opts or {}
  return setmetatable({
    chunkSize=math.max(64,tonumber(opts.chunkSize) or 256),
    activeRadius=math.max(1,floor(tonumber(opts.activeRadius) or 2)),
    sleepRadius=math.max(2,floor(tonumber(opts.sleepRadius) or 4)),
    chunks={}, active={}, frame=0, centerX=0, centerZ=0,
    onCreate=opts.onCreate, onWake=opts.onWake, onSleep=opts.onSleep,
  },ChunkSim)
end

function ChunkSim:coords(x,z)
  return floor((tonumber(x) or 0)/self.chunkSize),floor((tonumber(z) or 0)/self.chunkSize)
end

function ChunkSim:get(cx,cz,create)
  local k=key(cx,cz); local c=self.chunks[k]
  if not c and create~=false then
    c={cx=cx,cz=cz,key=k,active=false,lastFrame=self.frame,data={}}
    self.chunks[k]=c
    if self.onCreate then pcall(self.onCreate,c) end
  end
  return c
end

function ChunkSim:at(x,z,create) local cx,cz=self:coords(x,z); return self:get(cx,cz,create),cx,cz end

function ChunkSim:updateCenter(x,z)
  self.frame=self.frame+1
  local ccx,ccz=self:coords(x,z); self.centerX,self.centerZ=ccx,ccz
  local nextActive={}
  for dz=-self.activeRadius,self.activeRadius do
    for dx=-self.activeRadius,self.activeRadius do
      local c=self:get(ccx+dx,ccz+dz,true); c.lastFrame=self.frame; nextActive[c.key]=c
      if not c.active then c.active=true; if self.onWake then pcall(self.onWake,c) end end
    end
  end
  for k,c in pairs(self.active) do
    if not nextActive[k] then c.active=false; if self.onSleep then pcall(self.onSleep,c) end end
  end
  self.active=nextActive
  -- Forget empty sleeping chunks outside the sleep radius. Non-empty data is
  -- intentionally retained as sparse persistent environmental state.
  for k,c in pairs(self.chunks) do
    if not c.active and math.max(abs(c.cx-ccx),abs(c.cz-ccz))>self.sleepRadius then
      local empty=true; for _ in pairs(c.data) do empty=false; break end
      if empty then self.chunks[k]=nil end
    end
  end
end

function ChunkSim:forActive(fn)
  if type(fn)~="function" then return end
  for _,c in pairs(self.active) do fn(c) end
end

function ChunkSim:stats()
  local chunks,active,nonEmpty=0,0,0
  for _,c in pairs(self.chunks) do chunks=chunks+1; if c.active then active=active+1 end; for _ in pairs(c.data) do nonEmpty=nonEmpty+1; break end end
  return {chunks=chunks,active=active,nonEmpty=nonEmpty,chunkSize=self.chunkSize,activeRadius=self.activeRadius,sleepRadius=self.sleepRadius}
end

return ChunkSim
