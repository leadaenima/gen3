-- THE FLOAT BUFFER A MOD CANNOT ALLOCATE FOR ITSELF.
--
-- src/mods/Sandbox.lua denies `ffi`, so DRAMATIC_SHAPE's ChunkMesher fell back
-- to its table sink, which has no writeRaw -- and the mod's terrain disk cache
-- therefore never wrote a byte on this engine while reporting itself enabled.
-- Every map was re-meshed from scratch on every boot.  src/mods/MeshSink.lua
-- is the seam that fixes it without handing a mod raw memory.
--
-- What is pinned here:
--
--   * the stream is byte-identical to the mesher's own FFI sink -- same six
--     floats per vertex in the same TRI_ORDER -- because a cache file written
--     under one engine has to load under the other;
--   * a caller cannot talk the sink into writing outside its jail, and the
--     jail is the engine's, not the caller's;
--   * a disagreeing vertex format is refused rather than silently reinterpreted
--     on upload;
--   * `ffi` is STILL denied to mods, which is the whole point of the seam.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

-- tests/love_stub.lua withholds love.graphics.newMesh on purpose (a save-editor
-- module keys off its absence), and has no love.data at all.  Without both,
-- MeshSink.available() is false and every assertion below would pass by not
-- running -- the exact vacuum this suite exists to avoid.  So supply them
-- here, minimally and locally: a ByteData that is a real FFI buffer, and a
-- Mesh that only has to accept setVertices.
local testFfi = select(2, pcall(require, "ffi"))
if type(testFfi) == "table" then
  _G.love.data = _G.love.data or {}
  if not _G.love.data.newByteData then
    _G.love.data.newByteData = function(n)
      if type(n) == "string" then
        local str = n
        return { getString = function() return str end,
                 getFFIPointer = function() return nil end,
                 release = function() end }
      end
      local buf = testFfi.new("uint8_t[?]", n)
      return {
        getFFIPointer = function() return buf end,
        getString = function() return testFfi.string(buf, n) end,
        release = function() end,
      }
    end
  end
  _G.love.graphics = _G.love.graphics or {}
  if not _G.love.graphics.newMesh then
    _G.love.graphics.newMesh = function(_format, count)
      return { count = count, setVertices = function() return true end,
               release = function() end }
    end
  end
end

local MeshSink = require("src.mods.MeshSink")
local Sandbox = require("src.mods.Sandbox")
local LegacyCompat = require("src.mods.LegacyCompat")

local S = require("tests.harness").suite("mod mesh sink")
local check, eq = S.check, S.eq

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexShade", "float", 1 },
}
local TRI_ORDER = { 1, 2, 3, 1, 3, 4 }

-- The seam exists precisely because this stays shut.
check(Sandbox.moduleDenial("ffi") ~= nil, "ffi is still denied to mods")
check(Sandbox.moduleDenial("ffi.something") ~= nil, "so is a submodule of it")

if not MeshSink.available() then
  -- A host with no FFI answers a reason rather than a sink, which is what
  -- lets a caller fall through to its own slow path.  Nothing else here can
  -- run, and saying so beats passing vacuously.
  local sink, why = MeshSink.new({ format = FORMAT })
  check(sink == nil and why ~= nil, "no-FFI host answers nil plus a reason")
  check(false, "this host has no FFI, so the stream checks did not run")
  return S.finish()
end

-- ------- the bytes

-- Four corners with values that cannot be confused for one another: every
-- field occupies its own decade, so a transposed x/u or a dropped shade shows
-- up as a wrong MAGNITUDE rather than a plausible near-miss.
local CORNERS = {
  { 10, 20, 30 }, { 11, 21, 31 }, { 12, 22, 32 }, { 13, 23, 33 },
}
local UVS = { { 0.1, 0.2 }, { 0.3, 0.4 }, { 0.5, 0.6 }, { 0.7, 0.8 } }

local function expectedStream(shade)
  local out = {}
  for k = 1, 6 do
    local i = TRI_ORDER[k]
    local c, t = CORNERS[i], UVS[i]
    out[#out + 1] = c[1]
    out[#out + 1] = c[2]
    out[#out + 1] = c[3]
    out[#out + 1] = t[1]
    out[#out + 1] = t[2]
    out[#out + 1] = type(shade) == "table" and shade[i] or shade
  end
  return out
end

-- read the sink back as floats, through the only route a caller has
local function streamOf(sink)
  local bytes = {}
  sink.eachChunk(function(chunk) bytes[#bytes + 1] = chunk end)
  local blob = table.concat(bytes)
  local floats = {}
  for i = 1, #blob / 4 do
    -- LuaJIT has no string.unpack; love.data.unpack is the portable route and
    -- the stub provides it, so decode the little-endian float by hand instead
    local b1, b2, b3, b4 = blob:byte(i * 4 - 3, i * 4)
    local sign = (b4 >= 128) and -1 or 1
    local exponent = ((b4 % 128) * 2) + math.floor(b3 / 128)
    local mantissa = ((b3 % 128) * 65536) + (b2 * 256) + b1
    local value
    if exponent == 0 then
      value = (mantissa == 0) and 0 or (mantissa / 2 ^ 23) * 2 ^ -126
    elseif exponent == 255 then
      value = (mantissa == 0) and math.huge or (0 / 0)
    else
      value = (1 + mantissa / 2 ^ 23) * 2 ^ (exponent - 127)
    end
    floats[i] = sign * value
  end
  return floats
end

local function closeEnough(a, b)
  return math.abs(a - b) <= math.max(1e-4, math.abs(b) * 1e-6)
end

do
  local sink = MeshSink.new({ format = FORMAT, triOrder = TRI_ORDER })
  check(sink ~= nil, "a sink is handed back on an FFI host")
  eq(sink.vertexCount(), 0, "an empty sink has no vertices")

  sink.push(CORNERS, UVS, 0.75)
  eq(sink.vertexCount(), 6, "one quad is six vertices")

  local got = streamOf(sink)
  local want = expectedStream(0.75)
  eq(#got, #want, "six floats a vertex, six vertices a quad")
  local wrong = nil
  for i = 1, #want do
    if not closeEnough(got[i], want[i]) then
      wrong = wrong or ("float " .. i .. ": " .. tostring(got[i])
        .. " wanted " .. tostring(want[i]))
    end
  end
  check(wrong == nil,
    "the stream matches the mesher's own layout" .. (wrong and (" -- " .. wrong) or ""))
end

do
  -- per-corner shade is the other arm of push, and the one a flat-shade bug
  -- would leave looking fine
  local sink = MeshSink.new({ format = FORMAT, triOrder = TRI_ORDER })
  local shade = { 0.11, 0.22, 0.33, 0.44 }
  sink.push(CORNERS, UVS, shade)
  local got, want = streamOf(sink), expectedStream(shade)
  local ok = true
  for i = 1, #want do ok = ok and closeEnough(got[i], want[i]) end
  check(ok, "a per-corner shade lands on its own corner")
end

do
  -- the block boundary is where push has to roll over to a fresh buffer, and
  -- a quad that straddled two blocks would corrupt the stream silently
  local sink = MeshSink.new({ format = FORMAT, triOrder = TRI_ORDER, block = 12 })
  for _ = 1, 5 do sink.push(CORNERS, UVS, 0.5) end
  eq(sink.vertexCount(), 30, "five quads across three blocks")
  local got = streamOf(sink)
  eq(#got, 30 * 6, "no vertex is lost at a block boundary")
  local want = expectedStream(0.5)
  local ok = true
  for q = 0, 4 do
    for i = 1, 36 do ok = ok and closeEnough(got[q * 36 + i], want[i]) end
  end
  check(ok, "every block holds whole quads")
end

-- ------- what it refuses

do
  local sink, why = MeshSink.new({ format = { { "VertexPosition", "float", 3 } } })
  check(sink == nil and why ~= nil, "a format that is not six floats is refused")
end

do
  local sink = MeshSink.new({ format = FORMAT, block = 7 })
  check(sink == nil, "a block that is not a multiple of six is refused")
end

do
  local sink = MeshSink.new({ format = FORMAT, triOrder = { 1, 2, 3, 1, 3, 9 } })
  check(sink == nil, "a triOrder that indexes past the fourth corner is refused")
end

-- ------- the jail

do
  -- no jail, no writeRaw: that absence is how the caller knows it has to
  -- write the bytes itself
  local sink = MeshSink.new({ format = FORMAT })
  check(sink.writeRaw == nil, "an unjailed sink offers no writeRaw")
  check(type(sink.eachChunk) == "function", "but still offers the stream")
end

do
  -- A refusal has to be the JAIL refusing, not the test's filesystem being
  -- absent -- those look identical from the return value, and a sink that
  -- wrote the caller's own path would pass a check that only reads `false`.
  -- So the filesystem RECORDS what it was asked to open, and the assertions
  -- are about that record.
  local opened, made, removed = {}, {}, {}
  local realFs = _G.love.filesystem
  _G.love.filesystem = setmetatable({
    newFile = function(path)
      opened[#opened + 1] = path
      local written = {}
      return {
        open = function() return true end,
        write = function(_, bytes) written[#written + 1] = bytes return true end,
        close = function() return true end,
        bytes = written,
      }
    end,
    createDirectory = function(path) made[#made + 1] = path return true end,
    remove = function(path) removed[#removed + 1] = path return true end,
  }, { __index = realFs })

  local asked = {}
  local sink = MeshSink.new({ format = FORMAT }, {
    resolve = function(path)
      asked[#asked + 1] = path
      if path == "allowed/x.bin" then return "jail_root/allowed/x.bin" end
      return nil
    end,
  })
  check(type(sink.writeRaw) == "function", "a jailed sink offers writeRaw")
  sink.push(CORNERS, UVS, 0.5)

  -- the refusal: nothing may be opened at all
  local ok, why = sink.writeRaw("../../escape.bin")
  check(ok == false and why ~= nil, "a path the jail will not resolve is refused")
  eq(asked[#asked], "../../escape.bin", "and the jail was the one consulted")
  eq(#opened, 0, "a refused path opens no file whatsoever")

  local okNum = sink.writeRaw(12)
  check(okNum == false, "a non-path is refused before the jail sees it")
  eq(#opened, 0, "and a non-path opens no file either")

  -- the grant: the file opened is the jail's answer, never the caller's path
  local okWrite = sink.writeRaw("allowed/x.bin")
  check(okWrite == true, "a path the jail resolves is written")
  eq(#opened, 1, "exactly one file was opened")
  eq(opened[1], "jail_root/allowed/x.bin", "the sink opened the JAIL's path")
  check(opened[1] ~= "allowed/x.bin", "and never the path the caller named")
  check(#made > 0, "the parent directories were created first")

  _G.love.filesystem = realFs
end

do
  -- the mapping itself: a mod's relative path resolves under its own overlay,
  -- and the escapes do not resolve at all
  local target = LegacyCompat.overlayTarget("SomeMod", "voxel_cache/g0_9.bin")
  check(target == "mod_compat/SomeMod/voxel_cache/g0_9.bin", "a relative path lands under the mod's own overlay")
  check(LegacyCompat.overlayTarget("SomeMod", "../../elsewhere.bin") == nil, "a parent climb does not resolve")
  check(LegacyCompat.overlayTarget("SomeMod", "/etc/passwd") == nil, "an absolute path does not resolve")
  check(LegacyCompat.overlayTarget("SomeMod", "C:/Windows/system.ini") == nil, "a drive letter does not resolve")
  check(LegacyCompat.overlayTarget("SomeMod", "cache/x.bin", "a mod cannot write as another mod")
      ~= LegacyCompat.overlayTarget("OtherMod", "cache/x.bin"))
end

return S.finish()
