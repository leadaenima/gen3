-- International GBA Latin charset used by pokeruby's gSpeciesNames.
-- A-Z = 0xBB-0xD4, a-z = 0xD5-0xEE, EOS = 0xFF.  SPECIES_NONE is ten 0xAC
-- placeholders (rendered as '?') plus EOS.  Unused internal slots are a
-- hyphen run.

local GbaText = {}

GbaText.EOS = 0xFF
GbaText.SPACE = 0x00
GbaText.NAME_LENGTH = 11 -- POKEMON_NAME_LENGTH (10) + EOS
-- pokeruby SPECIES_NONE / SPECIES_EGG filler
GbaText.PLACEHOLDER = 0xAC
GbaText.HYPHEN = 0xAE
GbaText.NEWLINE = 0xFE
GbaText.EXCLAMATION = 0xAB
GbaText.PERIOD = 0xAD
GbaText.APOSTROPHE = 0xB4
GbaText.COMMA = 0xB8
-- pokeruby charmap.txt: é is 0x1B.  Dropping it turns "POKé BALL" into
-- "POK BALL".  FONT3 has no é glyph, so decode as ASCII e (POKe).
GbaText.E_ACUTE = 0x1B
GbaText.PK = 0x53
GbaText.MN = 0x54

function GbaText.decodeByte(code)
  if type(code) ~= "number" then return "" end
  if code == GbaText.EOS then return "" end
  if code == GbaText.SPACE then return " " end
  if code == GbaText.PLACEHOLDER then return "?" end
  if code == GbaText.HYPHEN then return "-" end
  if code == GbaText.NEWLINE or code == GbaText.PARA then return " " end
  if code == GbaText.EXCLAMATION then return "!" end
  if code == GbaText.PERIOD then return "." end
  if code == GbaText.APOSTROPHE then return "'" end
  if code == GbaText.COMMA then return "," end
  if code == GbaText.E_ACUTE or code == 0x1A or code == 0x1C or code == 0x1D then
    return "e"
  end
  if code == 0x06 or code == 0x05 or code == 0x07 or code == 0x08 then
    return "E"
  end
  if code == GbaText.PK then return "PK" end
  if code == GbaText.MN then return "MN" end
  if code >= 0xBB and code <= 0xD4 then
    return string.char(string.byte("A") + (code - 0xBB))
  end
  if code >= 0xD5 and code <= 0xEE then
    return string.char(string.byte("a") + (code - 0xD5))
  end
  if code >= 0xA1 and code <= 0xAA then
    return tostring(code - 0xA1) -- CHAR_0 .. CHAR_9
  end
  return ""
end

function GbaText.encodeLatin(text)
  local out = {}
  for i = 1, #text do
    local ch = text:sub(i, i)
    local b = ch:byte()
    if ch == " " then
      out[#out + 1] = string.char(GbaText.SPACE)
    elseif b >= 65 and b <= 90 then
      out[#out + 1] = string.char(0xBB + (b - 65))
    elseif b >= 97 and b <= 122 then
      out[#out + 1] = string.char(0xD5 + (b - 97))
    elseif ch == "?" then
      out[#out + 1] = string.char(GbaText.PLACEHOLDER)
    elseif ch == "-" then
      out[#out + 1] = string.char(GbaText.HYPHEN)
    elseif ch == "!" then
      out[#out + 1] = string.char(GbaText.EXCLAMATION)
    elseif ch == "." then
      out[#out + 1] = string.char(GbaText.PERIOD)
    elseif ch == "'" then
      out[#out + 1] = string.char(GbaText.APOSTROPHE)
    elseif ch == "," then
      out[#out + 1] = string.char(GbaText.COMMA)
    end
  end
  return table.concat(out)
end

function GbaText.decodeName(blob)
  if type(blob) ~= "string" then return "" end
  local chars = {}
  for i = 1, #blob do
    local code = blob:byte(i)
    if code == GbaText.EOS then break end
    chars[#chars + 1] = GbaText.decodeByte(code)
  end
  return table.concat(chars):gsub("%s+$", "")
end

GbaText.PARA = 0xFB
GbaText.EXT = 0xFC
GbaText.BUFFER = 0xFD
GbaText.PH_PLAYER = 0x01
GbaText.PH_STR_VAR_1 = 0x02
GbaText.PH_STR_VAR_2 = 0x03
GbaText.PH_STR_VAR_3 = 0x04
GbaText.PH_KUN = 0x05
GbaText.PH_RIVAL = 0x06

local BUFFER_TOKEN = {
  [GbaText.PH_PLAYER] = "{PLAYER}",
  [GbaText.PH_STR_VAR_1] = "{STR_VAR_1}",
  [GbaText.PH_STR_VAR_2] = "{STR_VAR_2}",
  [GbaText.PH_STR_VAR_3] = "{STR_VAR_3}",
  [GbaText.PH_KUN] = "{KUN}",
  [GbaText.PH_RIVAL] = "{RIVAL}",
}

function GbaText.bufferToken(id)
  return BUFFER_TOKEN[id or 0] or ""
end

function GbaText.decodeText(blob, maxLen)
  if type(blob) ~= "string" then return "" end
  maxLen = maxLen or 96
  local chars = {}
  local i, n = 1, math.min(#blob, maxLen)
  while i <= n do
    local c = blob:byte(i)
    if c == GbaText.EOS then break end
    if c == GbaText.BUFFER then
      chars[#chars + 1] = GbaText.bufferToken(blob:byte(i + 1))
      i = i + 1
    else
      chars[#chars + 1] = GbaText.decodeByte(c)
    end
    i = i + 1
  end
  return table.concat(chars):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Birch / menu copy uses \n (0xFE), \p (0xFB), and {PLAYER} (0xFD 0x01).
function GbaText.decodePages(blob, maxLen)
  if type(blob) ~= "string" then return {} end
  maxLen = maxLen or 400
  local pages, page, chars = {}, {}, {}
  local function flushLine()
    local line = table.concat(chars)
    chars = {}
    if line ~= "" then page[#page + 1] = line end
  end
  local function flushPage()
    flushLine()
    if #page > 0 then
      pages[#pages + 1] = table.concat(page, "\n")
      page = {}
    end
  end
  local i, n = 1, math.min(#blob, maxLen)
  while i <= n do
    local c = blob:byte(i)
    if c == GbaText.EOS then break end
    if c == GbaText.PARA then
      flushPage()
    elseif c == GbaText.NEWLINE then
      flushLine()
    elseif c == GbaText.BUFFER then
      chars[#chars + 1] = GbaText.bufferToken(blob:byte(i + 1))
      i = i + 1
    elseif c == GbaText.EXT then
      i = i + 1
    else
      local ch = GbaText.decodeByte(c)
      if ch ~= "" then chars[#chars + 1] = ch end
    end
    i = i + 1
  end
  flushPage()
  if #pages < 1 then
    local plain = GbaText.decodeText(blob, maxLen)
    if plain ~= "" then pages[1] = plain end
  end
  return pages
end

-- Encoded "BULBASAUR" without EOS: the first named species after SPECIES_NONE.
GbaText.BULBASAUR = GbaText.encodeLatin("BULBASAUR")

function GbaText.isBlankName(name)
  if type(name) ~= "string" or name == "" then return true end
  return name:match("^[?%-]+$") ~= nil
end

return GbaText
