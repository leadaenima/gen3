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

-- data/text/birch_speech.inc keeps the nine intro strings back to back in
-- ROM, in exactly this order. Searching for a phrase out of each one
-- separately takes the FIRST match anywhere in the ROM, which is how
-- "are you ready" landed on the Lilycove contest MC -- "Okay, SMART
-- POKeMON and their TRAINERS, are you ready?!" -- and "And you are" on an
-- unrelated NPC's "Oh, hello. And you are?". The 400-byte window also cut
-- the long world speech off mid-word at "I've been undertak".
--
-- Anchor once on the opening line, which is unique, and walk forward one
-- $-terminated string at a time.
Boot.BIRCH_SPEECH_ORDER = {
  "welcome", "thisIsPokemon", "world", "andYouAre", "boyOrGirl",
  "whatsYourName", "soItsPlayer", "ahOkay", "areYouReady",
}

function Boot.readBirchSpeech(data)
  if type(data) ~= "string" then return nil end
  local off = findEncoded(data, "Sorry to keep you waiting")
  if not off then return nil end
  local at = stringStart(data, off) + 1
  local out = {}
  for i = 1, #Boot.BIRCH_SPEECH_ORDER do
    if at > #data then break end
    local stop = at
    while stop <= #data and data:byte(stop) ~= GbaText.EOS do
      stop = stop + 1
    end
    local pages = GbaText.decodePages(data:sub(at, stop), stop - at + 1)
    if not (pages and pages[1]) then return out end
    out[Boot.BIRCH_SPEECH_ORDER[i]] = pages
    at = stop + 1
  end
  return out
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
  local speech = Boot.readBirchSpeech(data) or {}
  local function pages(key, fallback)
    local got = speech[key]
    if got and got[1] then return got end
    return fallback
  end
  local function line(key, fallback)
    local got = speech[key]
    if got and got[1] then return got[1] end
    return fallback
  end
  local birch = {
    welcome = pages("welcome", {
      "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!",
      "My name is BIRCH. But everyone calls me the POKeMON PROFESSOR.",
    }),
    thisIsPokemon = line("thisIsPokemon", "This is what we call a POKeMON."),
    world = pages("world", {
      "This world is widely inhabited by creatures known as POKeMON.",
      "To unravel POKeMON mysteries, I've been undertaking research.",
    }),
    andYouAre = line("andYouAre", "And you are?"),
    boyOrGirl = pages("boyOrGirl", { "Are you a boy? Or are you a girl?" }),
    whatsYourName = pages("whatsYourName", { "All right. What's your name?" }),
    soItsPlayer = line("soItsPlayer", "So it's {PLAYER}?"),
    ahOkay = pages("ahOkay", {
      "Ah, okay! You're {PLAYER} who's moving to my hometown of LITTLEROOT.",
    }),
    areYouReady = pages("areYouReady", {
      "All right, are you ready?",
      "Your very own adventure is about to unfold.",
      "Well, I'll be expecting you later. Come see me in my POKeMON LAB.",
    }),
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
