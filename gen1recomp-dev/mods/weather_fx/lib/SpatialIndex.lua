local V = ...

local SpatialIndex = {}
SpatialIndex.__index = SpatialIndex

local floor = math.floor
local ObjectPool = V.require("ObjectPool")

local function key(cx, cz) return tostring(cx) .. ":" .. tostring(cz) end

function SpatialIndex.new(cellSize)
  cellSize = math.max(16, tonumber(cellSize) or 128)
  return setmetatable({
    cellSize = cellSize,
    cells = {},
    records = {},
    count = 0,
    serial = 0,
    recordPool = ObjectPool.new(function() return {} end, function(r) for k in pairs(r) do r[k]=nil end end, {name="spatial-records",maxFree=4096}),
  }, SpatialIndex)
end

function SpatialIndex:clear()
  for k in pairs(self.cells) do self.cells[k] = nil end
  for k,r in pairs(self.records) do self.recordPool:release(r); self.records[k] = nil end
  self.count = 0
  self.serial = self.serial + 1
end

function SpatialIndex:_cell(x, z)
  return floor((tonumber(x) or 0) / self.cellSize), floor((tonumber(z) or 0) / self.cellSize)
end

function SpatialIndex:remove(id)
  local rec=self.records[id]; if not rec then return false end
  for i=1,#(rec.cellKeys or {}) do
    local k=rec.cellKeys[i]; local bucket=self.cells[k]
    if bucket then
      for j=#bucket,1,-1 do if bucket[j]==rec then table.remove(bucket,j) end end
      if #bucket==0 then self.cells[k]=nil end
    end
  end
  self.records[id]=nil; self.count=math.max(0,self.count-1); self.recordPool:release(rec); self.serial=self.serial+1
  return true
end

function SpatialIndex:insert(id, x, z, radius, payload)
  if id == nil then return false end
  if self.records[id] then self:remove(id) end
  x, z = tonumber(x) or 0, tonumber(z) or 0
  radius = math.max(0, tonumber(radius) or 0)
  local cx0, cz0 = self:_cell(x - radius, z - radius)
  local cx1, cz1 = self:_cell(x + radius, z + radius)
  local rec = self.recordPool:acquire()
  rec.id,rec.x,rec.z,rec.radius,rec.payload=id,x,z,radius,payload; rec.cellKeys=rec.cellKeys or {}
  for i=#rec.cellKeys,1,-1 do rec.cellKeys[i]=nil end
  self.records[id] = rec
  for cz = cz0, cz1 do
    for cx = cx0, cx1 do
      local k = key(cx, cz)
      local bucket = self.cells[k]
      if not bucket then bucket = {}; self.cells[k] = bucket end
      bucket[#bucket + 1] = rec; rec.cellKeys[#rec.cellKeys+1]=k
    end
  end
  self.count = self.count + 1
  return true
end

function SpatialIndex:update(id,x,z,radius,payload)
  local rec=self.records[id]
  if rec and rec.x==(tonumber(x) or 0) and rec.z==(tonumber(z) or 0) and rec.radius==(math.max(0,tonumber(radius) or 0)) then rec.payload=payload; return true end
  self:remove(id); return self:insert(id,x,z,radius,payload)
end

function SpatialIndex:queryAABB(x0,z0,x1,z1,out)
  out=out or {}; for i=#out,1,-1 do out[i]=nil end
  x0,z0,x1,z1=tonumber(x0) or 0,tonumber(z0) or 0,tonumber(x1) or 0,tonumber(z1) or 0
  if x0>x1 then x0,x1=x1,x0 end; if z0>z1 then z0,z1=z1,z0 end
  local cx0,cz0=self:_cell(x0,z0); local cx1,cz1=self:_cell(x1,z1); local seen={}
  for cz=cz0,cz1 do for cx=cx0,cx1 do local bucket=self.cells[key(cx,cz)]; if bucket then for i=1,#bucket do local r=bucket[i]; if not seen[r.id] and r.x+r.radius>=x0 and r.x-r.radius<=x1 and r.z+r.radius>=z0 and r.z-r.radius<=z1 then seen[r.id]=true; out[#out+1]=r end end end end end
  return out
end

function SpatialIndex:queryRadius(x, z, radius, out)
  out = out or {}
  for i=#out,1,-1 do out[i]=nil end
  x, z, radius = tonumber(x) or 0, tonumber(z) or 0, math.max(0, tonumber(radius) or 0)
  local cx0, cz0 = self:_cell(x - radius, z - radius)
  local cx1, cz1 = self:_cell(x + radius, z + radius)
  local seen = {}
  local r2 = radius * radius
  for cz = cz0, cz1 do
    for cx = cx0, cx1 do
      local bucket = self.cells[key(cx,cz)]
      if bucket then
        for i=1,#bucket do
          local rec = bucket[i]
          if not seen[rec.id] then
            seen[rec.id] = true
            local dx, dz = rec.x - x, rec.z - z
            local reach = radius + (rec.radius or 0)
            if dx*dx + dz*dz <= reach*reach then out[#out+1] = rec end
          end
        end
      end
    end
  end
  return out
end

function SpatialIndex:nearest(x, z, radius)
  local list = self:queryRadius(x,z,radius,{})
  local best, bestD
  for i=1,#list do
    local r=list[i]; local dx,dz=r.x-x,r.z-z; local d=dx*dx+dz*dz
    if not bestD or d<bestD then best,bestD=r,d end
  end
  return best, bestD and math.sqrt(bestD) or nil
end

function SpatialIndex:stats()
  local cells=0; for _ in pairs(self.cells) do cells=cells+1 end
  local pool=self.recordPool:stats()
  return { count=self.count, cells=cells, cellSize=self.cellSize, serial=self.serial, pool=pool }
end

return SpatialIndex
