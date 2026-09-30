-- Little-endian reads against a GBA ROM image (Lua string).  Offsets are
-- 0-based file positions; Lua's string API is 1-based, so byte 0 is
-- data:byte(1).  Pointers in the cart are 0x08xxxxxx and convert to file
-- offsets by subtracting ROM_BASE.

local GbaBin = {}

GbaBin.ROM_BASE = 0x08000000
GbaBin.ROM_END = 0x09000000

function GbaBin.u8(data, offset)
  return data:byte(offset + 1) or 0
end

function GbaBin.u16(data, offset)
  local i = offset + 1
  local lo, hi = data:byte(i, i + 1)
  if not hi then return 0 end
  return lo + hi * 256
end

function GbaBin.u32(data, offset)
  local i = offset + 1
  local a, b, c, d = data:byte(i, i + 3)
  if not d then return 0 end
  return a + b * 256 + c * 65536 + d * 16777216
end

function GbaBin.s16(data, offset)
  local v = GbaBin.u16(data, offset)
  if v >= 0x8000 then return v - 0x10000 end
  return v
end

function GbaBin.s32(data, offset)
  local v = GbaBin.u32(data, offset)
  if v >= 0x80000000 then return v - 0x100000000 end
  return v
end

function GbaBin.isRomPtr(ptr, romSize)
  if type(ptr) ~= "number" or ptr < GbaBin.ROM_BASE or ptr >= GbaBin.ROM_END then
    return false
  end
  if type(romSize) == "number" and (ptr - GbaBin.ROM_BASE) >= romSize then
    return false
  end
  return true
end

function GbaBin.romOffset(ptr)
  return ptr - GbaBin.ROM_BASE
end

function GbaBin.packU16(value)
  value = value % 0x10000
  return string.char(value % 256, math.floor(value / 256) % 256)
end

function GbaBin.packU32(value)
  value = value % 0x100000000
  return string.char(
    value % 256,
    math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 16777216) % 256)
end

function GbaBin.packPtr(fileOffset)
  return GbaBin.packU32(GbaBin.ROM_BASE + fileOffset)
end

return GbaBin
