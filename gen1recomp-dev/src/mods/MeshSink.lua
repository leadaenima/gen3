-- The float buffer a mod is not allowed to allocate for itself.
--
-- src/mods/Sandbox.lua denies `ffi` to mods, and rightly: raw io/os/ffi are
-- the only way to name a file outside the game tree at all, and an unchecked
-- `float[?]` store is an arbitrary memory write.  But a voxel mesher needs a
-- flat float stream -- a route is millions of quads, and a Lua table of
-- six-number tables is both far slower to fill and impossible to hand to
-- love.graphics or to disk as bytes.  DRAMATIC_SHAPE's ChunkMesher has an FFI
-- sink for exactly this and falls back to a table sink when `require("ffi")`
-- fails, which on this engine is always: the fallback cannot be persisted, so
-- the mod's terrain disk cache never wrote a single byte and every map was
-- re-meshed from scratch on every boot.
--
-- So the ENGINE owns the buffer and the mod drives it.  One Lua call per quad
-- (the shape ChunkMesher already had), the cdata stores happen in here, and
-- the mod never sees a pointer, a ctype or an index it could run off the end
-- of.  `ffi` stays denied.
--
-- IT ALSO WRITES, BUT ONLY WHERE THE ENGINE SAYS.  love.filesystem is already
-- rerouted per-mod into private compat storage, so a sink that opened whatever
-- path it was handed would be a hole straight through that jail.  The caller
-- does not choose the destination: Loader injects a `jail` that maps a mod
-- relative path to the same real location that mod's own writes land at, and
-- anything that does not map is refused.  Without a jail there is no writeRaw
-- at all, only `eachChunk`, and the caller writes the bytes itself.
--
-- Why not just let the mod stream through its own shimmed file handle?  That
-- handle is quadratic -- LegacyCompat rebuilds the whole buffer per write and
-- flushes it to disk each time -- which is nothing for a settings file and
-- tens of gigabytes of copying for a 400 MB vertex stream.  One real streaming
-- File, on a path the mod cannot pick, is the honest version.

local MeshSink = {}

local ffi = nil
do
  local ok, mod = pcall(require, "ffi")
  if ok then ffi = mod end
end

-- A block list rather than one buffer that doubles.  Same reasoning as the
-- mod's own sink: Route 119 is ~429 MB of vertex stream, and reaching that by
-- doubling costs ~600 MB of copies inside single uninterruptible calls that
-- no frame budget can break up.  Fixed blocks never move, so the peak is the
-- stream's own size and a block boundary is a natural yield point.
local DEFAULT_BLOCK = 65532            -- vertices; a multiple of 6
local FLOATS_PER_VERTEX = 6            -- x y z u v shade
local DEFAULT_TRI_ORDER = { 1, 2, 3, 1, 3, 4 }

function MeshSink.available()
  return (ffi and love and love.data and love.data.newByteData
    and love.graphics and love.graphics.newMesh) and true or false
end

-- The caller's vertex format has to agree with what `push` writes, or the
-- upload reinterprets the stream.  Checked rather than trusted: a format that
-- silently disagreed would draw garbage geometry, not raise.
local function formatFloats(format)
  if type(format) ~= "table" then return nil end
  local total = 0
  for _, attr in ipairs(format) do
    if type(attr) ~= "table" or attr[2] ~= "float" then return nil end
    total = total + (tonumber(attr[3]) or 0)
  end
  return total
end

-- `jail` is the ENGINE's, never the caller's: { resolve = fn }, where resolve
-- maps a caller-relative path to the real path it may be written at, or nil to
-- refuse it.  Nothing here ever writes a path the caller supplied directly.
function MeshSink.new(opts, jail)
  if not MeshSink.available() then return nil, "no ffi sink on this host" end
  opts = type(opts) == "table" and opts or {}
  if type(jail) ~= "table" or type(jail.resolve) ~= "function" then
    jail = nil
  end

  local format = opts.format
  if formatFloats(format) ~= FLOATS_PER_VERTEX then
    return nil, "mesh sink needs a 6-float vertex format"
  end

  local block = math.floor(tonumber(opts.block) or DEFAULT_BLOCK)
  if block < 6 or block % 6 ~= 0 then
    return nil, "mesh sink block must be a positive multiple of 6"
  end

  local triOrder = opts.triOrder
  if type(triOrder) ~= "table" or #triOrder ~= 6 then
    triOrder = DEFAULT_TRI_ORDER
  end
  -- a quad has four corners; an out-of-range index here would read nil and
  -- store a non-number into cdata, which raises deep inside push.  Copied
  -- rather than used in place, so the caller cannot mutate it afterwards.
  local order = {}
  for i = 1, 6 do
    local k = tonumber(triOrder[i])
    if not k or k < 1 or k > 4 or k % 1 ~= 0 then
      return nil, "mesh sink triOrder must index the four corners"
    end
    order[i] = k
  end

  local budget = type(opts.budget) == "function" and opts.budget or nil

  local blocks = { ffi.new("float[?]", block * FLOATS_PER_VERTEX) }
  local nb = 1      -- blocks in use
  local fill = 0    -- vertices written into blocks[nb]
  local n = 0       -- vertices in the whole stream

  -- the stream as (block, vertex count) pairs in order; only the last block
  -- is ever partial, because push advances on an exact fill
  local function eachBlock(fn)
    for bi = 1, nb do
      local count = (bi < nb) and block or fill
      if count > 0 then fn(blocks[bi], count) end
    end
  end

  -- one block as a byte string, for whoever is going to write it
  local function blockBytes(buf, count)
    local bytes = count * FLOATS_PER_VERTEX * 4
    local data = love.data.newByteData(bytes)
    ffi.copy(data:getFFIPointer(), buf, bytes)
    local str = data:getString()
    if data.release then pcall(data.release, data) end
    return str
  end

  local sink = {}

  -- c: four corners {x,y,z}.  uv: four {u,v}.  shade: a number for the whole
  -- quad, or four per corner.  Mirrors ChunkMesher's own push exactly -- the
  -- emitted float stream has to be byte-identical to the FFI sink's, or a
  -- cache entry written under one engine would not load under the other.
  function sink.push(c, uv, shade)
    if fill + 6 > block then
      nb = nb + 1
      local nxt = blocks[nb]
      if nxt == nil then
        nxt = ffi.new("float[?]", block * FLOATS_PER_VERTEX)
        blocks[nb] = nxt
      end
      fill = 0
      -- 1.5 MB of geometry has just been emitted; a frame that wants its
      -- slice back can have it here
      if budget then budget() end
    end
    local buf = blocks[nb]
    local flat = type(shade) ~= "table"
    local base = fill * FLOATS_PER_VERTEX
    for k = 1, 6 do
      local i = order[k]
      local cc, t = c[i], uv[i]
      buf[base] = cc[1]
      buf[base + 1] = cc[2]
      buf[base + 2] = cc[3]
      buf[base + 3] = t[1]
      buf[base + 4] = t[2]
      buf[base + 5] = flat and shade or shade[i]
      base = base + FLOATS_PER_VERTEX
    end
    fill = fill + 6
    n = n + 6
  end

  function sink.vertexCount()
    return n
  end

  -- The stream as byte strings, in the same slices the upload uses, with a
  -- budget tick between them.  This is the whole of what the caller gets for
  -- persistence: it writes them itself, wherever it is allowed to write.
  -- Called as `sink:eachChunk(fn)` or `sink.eachChunk(fn)`.
  function sink.eachChunk(a, b)
    local fn = b
    if fn == nil and type(a) == "function" then fn = a end
    if type(fn) ~= "function" then return false, "eachChunk needs a function" end
    local ok, err = pcall(function()
      eachBlock(function(buf, count)
        fn(blockBytes(buf, count))
        if budget then budget() end
      end)
    end)
    if not ok then return false, tostring(err) end
    return true
  end

  -- Upload in slices with budget ticks between: a route-sized mesh is
  -- 10-20 MB and one atomic setVertices is a frame spike on its own.
  function sink.finish()
    if n == 0 then return nil end
    local ok, mesh = pcall(function()
      local m = love.graphics.newMesh(format, n, "triangles", "static")
      local at = 0
      eachBlock(function(buf, count)
        local bytes = count * FLOATS_PER_VERTEX * 4
        local data = love.data.newByteData(bytes)
        ffi.copy(data:getFFIPointer(), buf, bytes)
        m:setVertices(data, at + 1)
        data:release()
        at = at + count
        if budget then budget() end
      end)
      return m
    end)
    return ok and mesh or nil
  end

  -- Spill the stream to disk under the engine's jail, in the same slices the
  -- upload uses and with a budget tick between them, so baking a region never
  -- stalls a frame.  One real File held open across the whole write: no
  -- accumulating buffer, so the peak is one block rather than the stream.
  -- Absent entirely when there is no jail, which is how a caller detects that
  -- it has to write the bytes itself.
  if jail then
    function sink.writeRaw(a, b)
      local path = b
      if path == nil and type(a) == "string" then path = a end
      if type(path) ~= "string" then return false, "writeRaw needs a path" end
      local okKey, target = pcall(jail.resolve, path)
      if not okKey or type(target) ~= "string" or target == "" then
        return false, "writeRaw refused " .. tostring(path)
      end
      if not (love.filesystem and love.filesystem.newFile) then
        return false, "no filesystem"
      end
      -- PhysFS will not create the parents for you, and a missing one fails
      -- the open rather than the write
      local dir = target:match("^(.*)/[^/]+$")
      if dir then
        local built = nil
        for segment in dir:gmatch("[^/]+") do
          built = built and (built .. "/" .. segment) or segment
          pcall(love.filesystem.createDirectory, built)
        end
      end
      local okFile, file = pcall(love.filesystem.newFile, target)
      if not okFile or not file then
        return false, "could not create " .. target
      end
      local okOpen, opened = pcall(file.open, file, "w")
      if not okOpen or opened == false then
        pcall(file.close, file)
        return false, "could not open " .. target
      end
      local okWrite, err = pcall(function()
        eachBlock(function(buf, count)
          if file:write(blockBytes(buf, count)) == false then
            error("short write")
          end
          if budget then budget() end
        end)
      end)
      pcall(file.close, file)
      if not okWrite then
        pcall(love.filesystem.remove, target)
        return false, tostring(err)
      end
      return true
    end
  end

  -- Drop the blocks.  A mesher that builds a region and throws the geometry
  -- away (the prebake pass) would otherwise hold every block alive until the
  -- sink itself is collected.
  function sink.release()
    blocks, nb, fill = {}, 0, 0
    return true
  end

  return sink
end

return MeshSink
