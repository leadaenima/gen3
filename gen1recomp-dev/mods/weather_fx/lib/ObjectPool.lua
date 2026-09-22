local V = ...

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new(factory, resetter, opts)
  opts = opts or {}
  return setmetatable({
    factory = factory or function() return {} end,
    resetter = resetter,
    free = {},
    inUse = 0,
    created = 0,
    highWater = 0,
    maxFree = tonumber(opts.maxFree) or math.huge,
    name = opts.name or "pool",
  }, ObjectPool)
end

function ObjectPool:acquire(...)
  local n = #self.free
  local obj
  if n > 0 then
    obj = self.free[n]
    self.free[n] = nil
  else
    obj = self.factory(...)
    self.created = self.created + 1
  end
  self.inUse = self.inUse + 1
  if self.inUse > self.highWater then self.highWater = self.inUse end
  return obj
end

function ObjectPool:release(obj)
  if obj == nil then return false end
  if self.resetter then pcall(self.resetter, obj) end
  if self.inUse > 0 then self.inUse = self.inUse - 1 end
  if #self.free < self.maxFree then self.free[#self.free + 1] = obj end
  return true
end

function ObjectPool:releaseAll(list, n)
  if type(list) ~= "table" then return end
  n = tonumber(n) or #list
  for i = 1, n do
    local obj = list[i]
    if obj ~= nil then self:release(obj); list[i] = nil end
  end
end

function ObjectPool:trim(limit)
  limit = math.max(0, tonumber(limit) or 0)
  while #self.free > limit do self.free[#self.free] = nil end
end

function ObjectPool:stats()
  return {
    name = self.name,
    created = self.created,
    inUse = self.inUse,
    free = #self.free,
    highWater = self.highWater,
  }
end

return ObjectPool
