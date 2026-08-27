-- GBA BIOS LZ77 (GBATEK type 0x10).  Used for Gen 3 tileset graphics.
-- Displacement copies are byte-by-byte so a distance of 1 is RLE.
--
-- Header: 0x10, then a 24-bit uncompressed size.  Each following flags
-- byte covers 8 blocks, MSB first: 0 = literal byte, 1 = 2-byte reference
--   length = (b1 >> 4) + 3
--   disp   = ((b1 & 0xF) << 8 | b2) + 1

local GbaLz77 = {}

local unpack = table.unpack or unpack
local CHUNK = 256

local function toString(bytes)
  local n = #bytes
  if n == 0 then return "" end
  local parts, p = {}, 0
  for i = 1, n, CHUNK do
    p = p + 1
    parts[p] = string.char(unpack(bytes, i, math.min(i + CHUNK - 1, n)))
  end
  return table.concat(parts)
end

function GbaLz77.decompress(data, offset)
  if type(data) ~= "string" then return nil, "not a string" end
  local i = (offset or 0) + 1
  if i + 3 > #data then return nil, "truncated lz77 header" end
  local typ, s0, s1, s2 = data:byte(i, i + 3)
  if typ ~= 0x10 then return nil, "not gba lz77" end
  local size = s0 + s1 * 256 + s2 * 65536
  if size == 0 then return "" end
  i = i + 4
  local out = {}
  local written = 0
  while written < size do
    if i > #data then return nil, "truncated lz77 flags" end
    local flags = data:byte(i)
    i = i + 1
    for bit = 0, 7 do
      if written >= size then break end
      local mask = 2 ^ (7 - bit)
      if math.floor(flags / mask) % 2 == 1 then
        if i + 1 > #data then return nil, "truncated lz77 reference" end
        local b1, b2 = data:byte(i, i + 1)
        i = i + 2
        local length = math.floor(b1 / 16) + 3
        local disp = (b1 % 16) * 256 + b2 + 1
        if disp > written then return nil, "lz77 displacement past start" end
        for _ = 1, length do
          if written >= size then break end
          written = written + 1
          out[written] = out[written - disp]
        end
      else
        if i > #data then return nil, "truncated lz77 literal" end
        written = written + 1
        out[written] = data:byte(i)
        i = i + 1
      end
    end
  end
  return toString(out)
end

-- Literal-only encoder for fixture ROMs.  The decoder stops at `size`, so
-- a short final flags byte is fine.
function GbaLz77.compressLiterals(payload)
  if type(payload) ~= "string" then error("lz77 payload must be a string") end
  local size = #payload
  local parts = {
    string.char(
      0x10,
      size % 256,
      math.floor(size / 256) % 256,
      math.floor(size / 65536) % 256),
  }
  local i = 1
  while i <= size do
    local n = math.min(8, size - i + 1)
    parts[#parts + 1] = string.char(0)
    parts[#parts + 1] = payload:sub(i, i + n - 1)
    i = i + n
  end
  return table.concat(parts)
end

return GbaLz77
