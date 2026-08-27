-- Nintendo GBA cartridge header (GBATEK).  Offset comments are 0-based file
-- positions; Lua string indices are 1-based, so title is data:sub(0xA1, 0xAC).
--
-- Zero requires: tests and the Gen 3 extractor call this from plain Lua.

local GbaHeader = {}

GbaHeader.TITLE_OFFSET = 0xA0
GbaHeader.TITLE_LENGTH = 12
GbaHeader.CODE_OFFSET = 0xAC
GbaHeader.CODE_LENGTH = 4
GbaHeader.MAKER_OFFSET = 0xB0
GbaHeader.MAKER_LENGTH = 2
GbaHeader.VERSION_OFFSET = 0xBC
GbaHeader.CHECKSUM_OFFSET = 0xBD

-- US Pokemon Ruby (AXVE).  Sapphire is AXPE; Emerald is BPEE.
GbaHeader.RUBY_USA = "AXVE"

local function asciiField(data, offset, length)
  if type(data) ~= "string" or #data < offset + length then return nil end
  local raw = data:sub(offset + 1, offset + length)
  return (raw:gsub("%z", ""):gsub("%s+$", ""))
end

function GbaHeader.parse(data)
  if type(data) ~= "string" or #data < 0xC0 then
    return nil, "not a GBA header"
  end
  local title = asciiField(data, GbaHeader.TITLE_OFFSET, GbaHeader.TITLE_LENGTH)
  local gameCode = asciiField(data, GbaHeader.CODE_OFFSET, GbaHeader.CODE_LENGTH)
  local maker = asciiField(data, GbaHeader.MAKER_OFFSET, GbaHeader.MAKER_LENGTH)
  local version = data:byte(GbaHeader.VERSION_OFFSET + 1) or 0
  return {
    title = title or "",
    gameCode = gameCode or "",
    maker = maker or "",
    version = version,
  }
end

function GbaHeader.isRubyUsa(header)
  return type(header) == "table" and header.gameCode == GbaHeader.RUBY_USA
end

return GbaHeader
