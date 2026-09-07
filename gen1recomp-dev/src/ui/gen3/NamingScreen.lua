-- Ruby / pokeruby naming_screen.c: YOUR NAME? / BOX NAME? / mon nickname.
-- Three keyboard pages (UPPER / LOWER / OTHERS), PAGE/BACK/OK on the right
-- column, SELECT cycles pages, START jumps to OK, B deletes.
--
-- Chrome sprites live in assets/naming/ (shipped, not ROM-generated).
-- Letters use Game3 Font3 the way Menu_PrintText does on the cart.
-- Decomp PNGs bake GBA color 0 as opaque black; we key it transparent.

local Assets = require("src.render.Assets")

local Naming = {}

Naming.PAGE_UPPER = 0
Naming.PAGE_LOWER = 1
Naming.PAGE_OTHERS = 2
Naming.COLS = 9
Naming.ROWS = 4
Naming.SIDE_COLS = 3 -- PAGE / BACK / OK

Naming.ROLE_CHAR = 0
Naming.ROLE_PAGE = 1
Naming.ROLE_BACK = 2
Naming.ROLE_OK = 3

Naming.TEMPLATE_PLAYER = 0
Naming.TEMPLATE_BOX = 1
Naming.TEMPLATE_MON = 2

-- sKeyboardCharacters ENGLISH + sKeyboardSymbolPositions.
-- Each page is 4 rows × 8 letter columns; column 8 is the function strip.
local PAGE_CHARS = {
  [0] = {
    { "A", "B", "C", "D", "E", "F", " ", "." },
    { "G", "H", "I", "J", "K", "L", " ", "," },
    { "M", "N", "O", "P", "Q", "R", "S", " " },
    { "T", "U", "V", "W", "X", "Y", "Z", " " },
  },
  [1] = {
    { "a", "b", "c", "d", "e", "f", " ", "." },
    { "g", "h", "i", "j", "k", "l", " ", "," },
    { "m", "n", "o", "p", "q", "r", "s", " " },
    { "t", "u", "v", "w", "x", "y", "z", " " },
  },
  -- ENGLISH sKeyboardCharacters: male/female/ellipsis/quotes -> FONT3 B5/B6/B0-B3.
  [2] = {
    { "0", "1", "2", "3", "4", " ", " ", " " },
    { "5", "6", "7", "8", "9", " ", " ", " " },
    { "!", "?", "♂", "♀", "/", "-", " ", " " },
    { "…", "“", "”", "‘", "'", " ", " ", " " },
  },
}

-- sKeyboardSymbolPositions ENGLISH (9 entries; last col is PAGE/BACK/OK).
local COL_X = {
  [0] = { 1, 3, 5, 8, 10, 12, 14, 17, 19 },
  [1] = { 1, 3, 5, 8, 10, 12, 14, 17, 19 },
  [2] = { 1, 4, 7, 10, 13, 16, 16, 16, 19 },
}

local SIDE_Y = { 0, 1, 2 } -- maps to PAGE / BACK / OK

local ASSET = {
  menu = "assets/naming/menu.png",
  -- Pret tilemaps painted offline (naming_screen.c BG3 + BG1/BG2 maps).
  bg = "assets/naming/bg_stripes.png",
  kbUpper = "assets/naming/keyboard_upper.png",
  kbLower = "assets/naming/keyboard_lower.png",
  kbOthers = "assets/naming/keyboard_others.png",
  ok = "assets/naming/ok_button.png",
  back = "assets/naming/back_button.png",
  pageBox = "assets/naming/change_keyboard_box.png",
  pageBtn = "assets/naming/change_keyboard_button.png",
  pageUpper = "assets/naming/upper_text.png",
  pageLower = "assets/naming/lower_text.png",
  pageOthers = "assets/naming/others_text.png",
  cursor = "assets/naming/cursor.png",
  cursorSmall = "assets/naming/active_cursor_small.png",
  cursorBig = "assets/naming/active_cursor_big.png",
  caret = "assets/naming/right_pointing_triangle.png",
  under = "assets/naming/underscore.png",
  pc0 = "assets/naming/pc_icon/0.png",
  pc1 = "assets/naming/pc_icon/1.png",
}

local imgCache = {}

-- LOVE 11 ImageData is 0..1; some paths still hand back 0..255. Treat both.
local function isKeyedTransparent(r, g, b, a, alsoWhite, noKey)
  if noKey then
    -- Trust source alpha (OW sheets). Only drop already-transparent texels.
    a = a or 1
    if a > 1 then a = a / 255 end
    return a < 0.02
  end
  r, g, b, a = r or 0, g or 0, b or 0, a or 1
  local scale = 1
  if r > 1 or g > 1 or b > 1 or a > 1 then scale = 255 end
  r, g, b, a = r / scale, g / scale, b / scale, a / scale
  if a < 0.02 then return true end
  if r <= 0.02 and g <= 0.02 and b <= 0.02 then return true end
  if alsoWhite and r >= 0.96 and g >= 0.96 and b >= 0.96 then return true end
  return false
end

-- GBA OBJ color 0 is transparent; pret PNGs often ship it as opaque black.
-- Prefer ImageData keying; never fall back to an unkeyed Image for chrome.
local function img(path, opts)
  if type(path) ~= "string" then return nil end
  opts = opts or {}
  local alsoWhite = opts.alsoWhite and true or false
  local noKey = opts.noKey and true or false
  local key = path .. (alsoWhite and "#w" or "") .. (noKey and "#nk" or "")
  local cached = imgCache[key]
  if cached ~= nil then return cached or nil end
  local data
  if Assets.imageData then
    local ok, d = pcall(Assets.imageData, path)
    if ok then data = d end
  end
  if not data and love and love.image and love.image.newImageData then
    local ok, d = pcall(love.image.newImageData, path)
    if ok then data = d end
  end
  if data and data.mapPixel then
    data:mapPixel(function(_, _, r, g, b, a)
      if isKeyedTransparent(r, g, b, a, alsoWhite, noKey) then
        return 0, 0, 0, 0
      end
      -- Normalize to 0..1 in case the source used 0..255.
      if (r or 0) > 1 or (g or 0) > 1 or (b or 0) > 1 then
        return (r or 0) / 255, (g or 0) / 255, (b or 0) / 255, (a or 255) / 255
      end
      return r, g, b, a
    end)
    local ok, image = pcall(love.graphics.newImage, data)
    if ok and image then
      if image.setFilter then image:setFilter("nearest", "nearest") end
      imgCache[key] = image
      return image
    end
  end
  -- Last resort: raw image (shipped naming PNGs are now pre-keyed on disk).
  local ok, image = pcall(Assets.image, path)
  if ok and image then
    imgCache[key] = image
    return image
  end
  if love and love.graphics and love.graphics.newImage then
    ok, image = pcall(love.graphics.newImage, path)
    if ok then
      imgCache[key] = image
      return image
    end
  end
  imgCache[key] = false
  return nil
end

function Naming.templateFor(kind)
  if kind == "box" or kind == Naming.TEMPLATE_BOX then
    return {
      kind = "box",
      maxChars = 8,
      title = "BOX NAME?",
      icon = "pc",
      gender = false,
    }
  end
  if kind == "player" or kind == Naming.TEMPLATE_PLAYER then
    return {
      kind = "player",
      maxChars = 7,
      title = "YOUR NAME?",
      icon = "player",
      gender = false,
    }
  end
  return {
    kind = "mon",
    maxChars = 10,
    title = nil, -- filled with "{species}'s nickname?"
    icon = "mon",
    gender = true,
  }
end

function Naming.nameLeftOffset(maxChars)
  maxChars = math.floor(tonumber(maxChars) or 10)
  return 14 - math.floor(maxChars / 2)
end

function Naming.open(opts)
  opts = opts or {}
  local tpl = Naming.templateFor(opts.template or opts.kind or "mon")
  local maxChars = opts.maxChars or tpl.maxChars
  local title = opts.title
  if not title then
    if tpl.kind == "mon" then
      local species = opts.speciesName or "POKeMON"
      title = species .. "'s nickname?"
    else
      title = tpl.title
    end
  end
  local seed = opts.initial or opts.name or ""
  if #seed > maxChars then seed = seed:sub(1, maxChars) end
  return {
    kind = "nickname",
    naming = true,
    template = tpl.kind,
    title = title,
    maxChars = maxChars,
    name = seed,
    page = opts.page or Naming.PAGE_UPPER,
    cursorX = 0,
    cursorY = 0,
    -- naming_screen.c CursorInit objMode=1 + sub_80B6998 pulse / anims.
    cursorPulse = 0,
    cursorPulseDir = 1,
    cursorPulseWait = 2,
    cursorBlink = 0,
    cursorPress = 0,
    -- sub_80B6D9C caret bob; sub_80B6DE8 underscore bounce.
    caretPhase = 0,
    caretWait = 8,
    underPhase = 0,
    underWait = 0,
    iconAnim = 0,
    sideRow = 0,
    scripted = opts.scripted,
    slot = opts.slot,
    mon = opts.mon,
    nameBox = opts.nameBox,
    box = opts.box,
    fromCatch = opts.fromCatch,
    fromHatch = opts.fromHatch,
    fromPc = opts.fromPc,
    speciesName = opts.speciesName,
    monGender = opts.monGender,
    iconPath = opts.iconPath,
    playerGender = opts.playerGender,
    -- Kept for older tests that looked for END in .keys; START confirms.
    keys = { "END" },
  }
end

function Naming.charAt(page, x, y)
  page = page or 0
  local grid = PAGE_CHARS[page] or PAGE_CHARS[0]
  local row = grid[(y or 0) + 1]
  if not row then return " " end
  return row[(x or 0) + 1] or " "
end

function Naming.roleAt(x, y)
  if (x or 0) < Naming.COLS - 1 then return Naming.ROLE_CHAR end
  local roles = { Naming.ROLE_PAGE, Naming.ROLE_BACK, Naming.ROLE_OK }
  return roles[((y or 0) % 3) + 1]
end

local function wrapSideY(y)
  if y < 0 then return 2 end
  if y > 2 then return 0 end
  return y
end

local function wrapLetterY(y)
  if y < 0 then return 3 end
  if y > 3 then return 0 end
  return y
end

-- s4RowTo3RowTableY / gUnknown_083CE274 when entering / leaving the OK column.
local TO_SIDE = { [0] = 0, [1] = 1, [2] = 1, [3] = 2 }
local FROM_SIDE = { [0] = 0, [1] = 0, [2] = 3 }

function Naming.moveCursor(f, dx, dy)
  local x = f.cursorX or 0
  local y = f.cursorY or 0
  local prevX = x
  x = x + (dx or 0)
  y = y + (dy or 0)
  if x < 0 then x = Naming.COLS - 1 end
  if x > Naming.COLS - 1 then x = 0 end

  if (dx or 0) ~= 0 then
    if (f.page or 0) == Naming.PAGE_OTHERS and (x == 6 or x == 7) then
      if dx > 0 then x = Naming.COLS - 1 else x = 5 end
    end
    if x == Naming.COLS - 1 then
      f.sideRow = y
      y = TO_SIDE[y] or 0
    elseif prevX == Naming.COLS - 1 then
      if y == 1 then
        y = f.sideRow or 0
      else
        y = FROM_SIDE[y] or 0
      end
    end
  end

  if x == Naming.COLS - 1 then
    y = wrapSideY(y)
  else
    y = wrapLetterY(y)
  end
  f.cursorX, f.cursorY = x, y
end

function Naming.cyclePage(f)
  f.page = ((f.page or 0) + 1) % 3
end

local function utf8Len(s)
  s = tostring(s or "")
  local n, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if not b then break end
    if b < 0x80 then i = i + 1
    elseif b < 0xE0 then i = i + 2
    elseif b < 0xF0 then i = i + 3
    else i = i + 4 end
    n = n + 1
  end
  return n
end

local function utf8ChopLast(s)
  s = tostring(s or "")
  if s == "" then return "" end
  local i, last = 1, 1
  while i <= #s do
    last = i
    local b = s:byte(i)
    if b < 0x80 then i = i + 1
    elseif b < 0xE0 then i = i + 2
    elseif b < 0xF0 then i = i + 3
    else i = i + 4 end
  end
  return s:sub(1, last - 1)
end

function Naming.backspace(f)
  f.name = utf8ChopLast(f.name or "")
end

function Naming.typeChar(f, ch)
  if not ch or ch == "" or ch == " " then return end
  local name = f.name or ""
  local maxLen = f.maxChars or 10
  if utf8Len(name) < maxLen then
    f.name = name .. ch
  end
end

function Naming.step(host, f, Input)
  Input = Input or require("src.core.Input")
  -- sub_80B6998: every 2 frames pulse 0..16..0 while selection stable.
  f.cursorPulseWait = (f.cursorPulseWait or 2) - 1
  if (f.cursorPulseWait or 0) <= 0 then
    local pulse = f.cursorPulse or 0
    local d = f.cursorPulseDir or 1
    pulse = pulse + d
    if pulse >= 16 or pulse <= 0 then
      d = -d
      pulse = math.max(0, math.min(16, pulse))
    end
    f.cursorPulse, f.cursorPulseDir = pulse, d
    f.cursorPulseWait = 2
  end
  f.cursorBlink = (f.cursorBlink or 0) + 1
  if (f.cursorPress or 0) > 0 then
    f.cursorPress = f.cursorPress - 1
  end
  -- Caret horizontal bob (sub_80B6D9C): {0,-4,-2,-1} every 8 frames.
  f.caretWait = (f.caretWait or 8) - 1
  if (f.caretWait or 0) <= 0 then
    f.caretWait = 8
    f.caretPhase = ((f.caretPhase or 0) + 1) % 4
  end
  -- Underscore vertical bob at caret (sub_80B6DE8): {2,3,2,1} every 9 frames.
  f.underWait = (f.underWait or 0) + 1
  if (f.underWait or 0) > 8 then
    f.underWait = 0
    f.underPhase = ((f.underPhase or 0) + 1) % 4
  end
  f.iconAnim = (f.iconAnim or 0) + 1

  local function moved()
    f.cursorPulse, f.cursorPulseDir, f.cursorPulseWait = 0, 1, 2
  end

  -- naming_screen.c HandleDpadMovement uses JOY_REPT: initial delay then
  -- autorepeat so the side PAGE/BACK/OK column is reachable by holding.
  local function dpadEdge(dir, dx, dy)
    if Input:wasPressed(dir) then
      Naming.moveCursor(f, dx, dy); moved()
      f.dpadRepeat = dir
      f.dpadWait = 16
      return true
    end
    return false
  end
  local gotDpad = dpadEdge("left", -1, 0)
    or dpadEdge("right", 1, 0)
    or dpadEdge("up", 0, -1)
    or dpadEdge("down", 0, 1)
  if not gotDpad then
    local held, dx, dy = nil, 0, 0
    if Input:isDown("left") then held, dx, dy = "left", -1, 0
    elseif Input:isDown("right") then held, dx, dy = "right", 1, 0
    elseif Input:isDown("up") then held, dx, dy = "up", 0, -1
    elseif Input:isDown("down") then held, dx, dy = "down", 0, 1 end
    if held then
      f.dpadWait = (f.dpadWait or 0) - 1
      if (f.dpadWait or 0) <= 0 then
        Naming.moveCursor(f, dx, dy); moved()
        f.dpadWait = 6
        f.dpadRepeat = held
      end
    else
      f.dpadWait, f.dpadRepeat = 0, nil
    end
  end
  if Input:wasPressed("select") then
    Naming.cyclePage(f)
  elseif Input:wasPressed("b") then
    Naming.backspace(f)
  elseif Input:wasPressed("start") then
    f.cursorX, f.cursorY = Naming.COLS - 1, 2
    if host.finishNickname then return host:finishNickname() end
    return "ok"
  elseif Input:wasPressed("a") then
    local role = Naming.roleAt(f.cursorX, f.cursorY)
    if role == Naming.ROLE_PAGE then
      Naming.cyclePage(f)
    elseif role == Naming.ROLE_BACK then
      Naming.backspace(f)
    elseif role == Naming.ROLE_OK then
      if host.finishNickname then return host:finishNickname() end
      return "ok"
    else
      -- Anim 1 (frames 4,8): brief press flash, then back to blink.
      f.cursorPress = 10
      Naming.typeChar(f, Naming.charAt(f.page, f.cursorX, f.cursorY))
    end
  end
end

local function blit(path, x, y)
  local image = img(path)
  if not image then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, x, y)
  return true
end

local function fillBg()
  local G = love.graphics
  -- Stock BG3 (unknown_E86258) + pal 0: red/purple horizontal stripes +
  -- white name-entry chrome + "A BUTTON TO SELECT".
  local bg = img(ASSET.bg)
  if bg then
    G.setColor(1, 1, 1, 1)
    G.draw(bg, 0, 0)
  else
    -- Fallback from naming_screen 0.pal reds if asset missing.
    G.setColor(98 / 255, 57 / 255, 82 / 255, 1)
    G.rectangle("fill", 0, 0, 240, 160)
    G.setColor(180 / 255, 32 / 255, 24 / 255, 1)
    for y = 0, 160, 4 do
      G.rectangle("fill", 0, y, 240, 2)
    end
  end
end

local function keyboardSheet(page)
  if page == Naming.PAGE_LOWER then return ASSET.kbLower end
  if page == Naming.PAGE_OTHERS then return ASSET.kbOthers end
  return ASSET.kbUpper
end

function Naming.draw(host, f)
  local G = love.graphics
  fillBg()

  -- Keyboard panel from pret tilemaps (green chrome + side-column slots).
  -- Drawn under letters / side-button sprites. Includes no letter glyphs.
  local page = f.page or 0
  blit(keyboardSheet(page), 0, 0)

  -- Title lives inside the white BG3 name box (no drawStdWindow wash).
  G.setColor(0.10, 0.10, 0.12, 1)
  local title = f.title or "NICKNAME?"
  if host.drawText then
    host:drawText(title, 9 * 8, 2 * 8)
  end

  local maxChars = f.maxChars or 10
  local left = Naming.nameLeftOffset(maxChars)
  local nameX = left * 8
  local nameY = 4 * 8
  local name = f.name or ""

  -- Caret bob (sub_80B6D9C) + underscore bounce at caret (sub_80B6DE8).
  local caretXOff = ({0, -4, -2, -1})[((f.caretPhase or 0) % 4) + 1]
  local underYOff = ({2, 3, 2, 1})[((f.underPhase or 0) % 4) + 1]
  local caretPos = utf8Len(name)
  if caretPos > maxChars - 1 then caretPos = maxChars - 1 end
  -- Stock CreateSprite coords are 8x8 OBJ; pret underscore ink sits on
  -- rows 6-7 / cols 1-6. Empirically stock pixels land at nameX+i*8,y=0x28
  -- (ink at y=46), matching letter centers from FC CLEAR 1 + spacing 8.
  blit(ASSET.caret, nameX - 8 + 4 + caretXOff, 0x28)
  for i = 0, maxChars - 1 do
    local uy = 0x28
    if i == caretPos then uy = uy + underYOff end
    blit(ASSET.under, nameX + i * 8, uy)
  end
  -- sub_80B7960: FC MIN_LETTER_SPACING 8 + FC CLEAR 1 so glyphs sit on
  -- the same 8px pitch as underscore sprites (nameLeftOffset*8+4 + i*8).
  G.setColor(0.10, 0.10, 0.12, 1)
  if host.drawText then
    local gi, gx = 1, 0
    while gi <= #name do
      local b = name:byte(gi)
      local skip = 1
      if b >= 0xF0 then skip = 4
      elseif b >= 0xE0 then skip = 3
      elseif b >= 0xC0 then skip = 2 end
      local ch = name:sub(gi, gi + skip - 1)
      host:drawText(ch, nameX + 1 + gx * 8, nameY)
      gx = gx + 1
      gi = gi + skip
    end
  end

  if f.monGender == 0 then
    G.setColor(0.20, 0.45, 0.90, 1)
    if host.drawText then host:drawText("♂", 20 * 8, nameY) end
  elseif f.monGender == 1 then
    G.setColor(0.90, 0.30, 0.45, 1)
    if host.drawText then host:drawText("♀", 20 * 8, nameY) end
  end

  -- Icon (player OW / PC / mon front).
  -- OW sheets already ship with correct alpha from the extractor. Do NOT
  -- alsoWhite/black-key them here: that punches out Brendan's white hat and
  -- black outlines (stock naming_screen.c uses the raw OBJ tiles).
  if f.iconPath then
    local custom = img(f.iconPath, { alsoWhite = true })
    if custom then
      G.setColor(1, 1, 1, 1)
      G.draw(custom, 0x34, 0x18)
    end
  elseif f.template == "pc" or f.template == "box" then
    -- PC icon frames 0/1 (stock subsprite anim).
    local pc = ASSET.pc0
    if (math.floor((f.iconAnim or 0) / 16) % 2) == 1 then pc = ASSET.pc1 end
    blit(pc, 0x38, 0x18)
  elseif f.template == "player" and host.playerGraphicsId and host.spriteImage then
    -- Stock sub_80B6E68: AddPseudoObjectEvent(rivalGfx) + StartSpriteAnim(..., 4)
    -- = gMoveDirectionAnimNums[DIR_SOUTH] walk-south (frames 3,0,4,0 @ 8).
    -- Prefer same-gender rival OW id (GetRivalAvatarGraphicsIdByStateIdAndGender).
    local gid = host:playerGraphicsId()
    local byId = host.data and host.data.sprites and host.data.sprites.byId
    if host.isFemale and host.GFX_RIVAL_BRENDAN then
      local rival = host:isFemale() and host.GFX_RIVAL_MAY or host.GFX_RIVAL_BRENDAN
      if byId and byId[rival] then gid = rival end
    end
    local spec = byId and byId[gid]
    if spec and spec.path then
      -- Same loader as field OW — preserves hat whites + outline blacks.
      local sheet = host:spriteImage(gid)
      if not sheet then sheet = img(spec.path, { noKey = true }) end
      if sheet and host.owQuad then
        local w = spec.width or 16
        local h = spec.height or 32
        local fr, flip = 0, false
        local walk = spec.walk and spec.walk.south
        if type(walk) == "table" and #walk > 0 then
          local total = 0
          for i = 1, #walk do total = total + (walk[i].duration or 8) end
          if total < 1 then total = #walk * 8 end
          local tick = (f.iconAnim or 0) % total
          local acc = 0
          for i = 1, #walk do
            acc = acc + (walk[i].duration or 8)
            if tick < acc then
              fr = walk[i].frame or 0
              flip = walk[i].flip and true or false
              break
            end
          end
        elseif spec.face and spec.face.south then
          fr = spec.face.south.frame or 0
          flip = spec.face.south.flip and true or false
        end
        local quad = host:owQuad(spec, sheet, fr)
        if not quad then quad = host:owQuad(spec, sheet, 0) end
        G.setColor(1, 1, 1, 1)
        if quad then
          -- AddPseudoObjectEvent(0x38,0x18): treat as sprite center.
          local dx = 0x38 - w / 2
          local dy = 0x18 - h / 2
          if flip then
            G.draw(sheet, quad, dx + w, dy, 0, -1, 1)
          else
            G.draw(sheet, quad, dx, dy, 0, 1, 1)
          end
        end
      end
    end
  elseif f.mon and host.drawBattlePic then
    -- Small front pic stand-in via grabImage of battle front.
    local species = f.mon.species
    local path = ("assets/generated/battle/front/%d.png"):format(species or 0)
    local front = img(path)
    if front then
      G.setColor(1, 1, 1, 1)
      local sw, sh = front:getDimensions()
      local scale = math.min(32 / sw, 32 / sh)
      G.draw(front, 0x34, 0x10, 0, scale, scale)
    end
  end

  -- Letters over the green keyboard tilemap (Menu_PrintText positions).
  local cols = COL_X[page] or COL_X[0]
  G.setColor(0.10, 0.10, 0.12, 1)
  for row = 0, 3 do
    for col = 0, 7 do
      local ch = Naming.charAt(page, col, row)
      if ch ~= " " then
        local tx = 3 * 8 + (cols[col + 1] or 1) * 8
        local ty = (9 + row * 2) * 8
        if host.drawText then host:drawText(ch, tx, ty) end
      end
    end
  end

  -- Side column chrome (naming_screen.c sub_80B6A80 / sub_80B6CA8).
  -- Sprites already bake SELECT / (B) BUTTON / START hints (stock OBJ).
  -- Stock gUnknown_083CE2CA tags {4,6,5} = Lower/Others/Upper text for
  -- currentPage 0/1/2: the chip shows the NEXT page you cycle into.
  local pageText = ({
    [0] = ASSET.pageLower,
    [1] = ASSET.pageOthers,
    [2] = ASSET.pageUpper,
  })[page] or ASSET.pageLower
  -- Subsprite anchors (gSubspriteTable_83CE4B0/500/510): CreateSprite(0xCC,*)
  -- is the pivot; PNGs are composed sheets so apply the table offsets.
  blit(ASSET.pageBox, 0xCC - 20, 0x50 - 16)
  -- Skip change_keyboard_button.png: pret sheet is opaque white (GBA palettes
  -- recolor it). Drawing it unpaletted washed the chip. pageBox + pageText
  -- (already colored) match stock once subsprite offsets are applied.
  blit(pageText, 0xCC - 12, 0x4C - 4)
  blit(ASSET.back, 0xCC - 20, 0x6C - 12)
  blit(ASSET.ok, 0xCC - 20, 0x84 - 12)

  -- Cursor: SetCursorPos uses KeyboardCol*8+27, y*16+80 for all columns
  -- including the side strip (col 19). Sprite is 16x16; draw top-left so the
  -- frame centers on the key (same -8 origin the letter lit-cursor uses).
  -- CursorInit sets objMode=1 (semi-transparent); sub_80B6998 pulses pal.
  local cx, cy = f.cursorX or 0, f.cursorY or 0
  local kcol = cols[cx + 1] or (cx >= Naming.COLS - 1 and 19 or 1)
  local kx = kcol * 8 + 27
  local ky = cy * 16 + 80
  local pulse = (f.cursorPulse or 0) / 16
  local press = (f.cursorPress or 0) > 0
  local blinkOn = ((f.cursorBlink or 0) % 4) < 2
  local alpha = 0.40 + 0.45 * pulse
  if press then alpha = math.min(1, alpha + 0.35) end
  if not blinkOn and not press then alpha = alpha * 0.55 end
  if cx < Naming.COLS - 1 then
    local lit = ASSET.cursorSmall
    if page == Naming.PAGE_OTHERS then lit = ASSET.cursorBig end
    local image = img(lit)
    if image then
      -- Additive-ish highlight (stock blend objMode), not opaque solid fill.
      if G.setBlendMode then G.setBlendMode("add") end
      G.setColor(1.0, 0.55 + 0.45 * pulse, 0.55 + 0.45 * pulse, alpha * 0.85)
      G.draw(image, kx - 8, ky - 8)
      if G.setBlendMode then G.setBlendMode("alpha") end
    end
    -- Letter-grid outline cursor (stock hides this sprite on the side col).
    do
      local image2 = img(ASSET.cursor)
      if image2 then
        if G.setBlendMode then G.setBlendMode("alpha") end
        G.setColor(1, 1, 1, 0.55 + 0.40 * pulse)
        G.draw(image2, kx - 8, ky - 8)
        G.setColor(1, 1, 1, 1)
      elseif host.drawCursor then
        host:drawCursor(kx - 8, ky - 8)
      end
    end
  else
    -- Side PAGE/BACK/OK focus: stock cursor sprite is invisible here, so
    -- pulse a rect over the active chip so D-pad focus is visible.
    local sideX = 0xCC - 20
    local sideY = ({ [0] = 0x50 - 16, [1] = 0x6C - 12, [2] = 0x84 - 12 })[cy] or (0x50 - 16)
    local sideH = (cy == 0) and 32 or 24
    G.setColor(1, 1, 1, 0.25 + 0.35 * pulse)
    G.rectangle("line", sideX, sideY, 40, sideH)
    G.setColor(1, 1, 1, 1)
  end
end

Naming.ASSET = ASSET
Naming.PAGE_CHARS = PAGE_CHARS
Naming.COL_X = COL_X

return Naming
