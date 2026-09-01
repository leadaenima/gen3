-- Ruby boot copy: copyright is a graphic, but Birch's speech and the
-- main-menu labels are Latin in the ROM.  Nintendo tiles stay out of git.
local GbaText = require("src.import.GbaText")
local Cinema = require("src.import.RomExtractorGen3Cinema")

local Boot = {}

Boot.SPECIES_AZURILL = 350
Boot.SPECIES_GROUDON = 405
Boot.MAX_STRING = 400

local function findEncoded(data, ascii)
  local needle = GbaText.encodeLatin(ascii)
  if needle == "" then return nil end
  local at = data:find(needle, 1, true)
  if not at then return nil end
  return at - 1
end

local function stringStart(data, off)
  local i = off
  while i > 0 do
    if data:byte(i) == GbaText.EOS then return i end
    i = i - 1
    if off - i > Boot.MAX_STRING then break end
  end
  return off
end

function Boot.readPages(data, ascii)
  if type(data) ~= "string" then return nil end
  local off = findEncoded(data, ascii)
  if not off then return nil end
  local start = stringStart(data, off)
  return GbaText.decodePages(data:sub(start + 1, start + Boot.MAX_STRING),
    Boot.MAX_STRING)
end

function Boot.readLine(data, ascii)
  local pages = Boot.readPages(data, ascii)
  if not pages or not pages[1] then return nil end
  return pages[1]
end

function Boot.findNameList(data, first)
  local line = Boot.readLine(data, first)
  if not line then return nil end
  local off = findEncoded(data, first)
  if not off then return { line } end
  local names = { line }
  local i = off + #GbaText.encodeLatin(first) + 1
  for _ = 1, 6 do
    if i >= #data then break end
    if data:byte(i) == GbaText.EOS then i = i + 1 end
    local name = GbaText.decodeName(data:sub(i, i + 10))
    if name == "" or #name > 7 then break end
    names[#names + 1] = name
    i = i + #name + 1
    if #names >= 5 then break end
  end
  return names
end

function Boot.extract(data)
  local birch = {
    welcome = Boot.readPages(data, "Sorry to keep you waiting") or {
      "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!",
      "My name is BIRCH. But everyone calls me the POKeMON PROFESSOR.",
    },
    thisIsPokemon = Boot.readLine(data, "This is what we call")
      or "This is what we call a POKeMON.",
    world = Boot.readPages(data, "widely inhabited") or {
      "This world is widely inhabited by creatures known as POKeMON.",
      "To unravel POKeMON mysteries, I've been undertaking research.",
    },
    andYouAre = Boot.readLine(data, "And you are") or "And you are?",
    boyOrGirl = Boot.readPages(data, "Are you a boy") or {
      "Are you a boy? Or are you a girl?",
    },
    whatsYourName = Boot.readPages(data, "Whats your name")
      or Boot.readPages(data, "What's your name")
      or { "All right. What's your name?" },
    soItsPlayer = Boot.readLine(data, "So its") or "So it's {PLAYER}?",
    ahOkay = Boot.readPages(data, "moving to my") or {
      "Ah, okay! You're {PLAYER} who's moving to my hometown of LITTLEROOT.",
    },
    areYouReady = Boot.readPages(data, "are you ready") or {
      "All right, are you ready?",
      "Your very own adventure is about to unfold.",
      "Well, I'll be expecting you later. Come see me in my POKeMON LAB.",
    },
  }
  local menu = {
    newGame = Boot.readLine(data, "NEW GAME") or "NEW GAME",
    continue = "CONTINUE",
    option = "OPTION",
    player = "PLAYER",
    time = "TIME",
    pokedex = "POKeDEX",
    badges = "BADGES",
    boy = "BOY",
    girl = "GIRL",
    newName = "NEW NAME",
  }
  return {
    birch = birch,
    menu = menu,
    names = {
      male = { "NEW NAME", "BRENDAN", "SETH", "TERRELL", "CHAZ" },
      female = { "NEW NAME", "MAY", "KIMMY", "CELIA", "KIRA" },
    },
    species = {
      azurill = Boot.SPECIES_AZURILL,
      groudon = Boot.SPECIES_GROUDON,
    },
    cinema = Cinema.extract(data),
  }
end

return Boot
