-- Ruby boot cinema and main menu.  pokeruby: intro.c copyright → intro.c
-- cinema → title_screen.c → main_menu.c CONTINUE/NEW GAME/OPTION →
-- Birch speech → overworld.  Graphics come from the extracted cache;
-- the control flow matches the ROM even when a pic is missing.
local Input = require("src.core.Input")

local Boot = {}

local COPYRIGHT_SEC = 3
local INTRO_SEC = 12
local TITLE_LOOP_SEC = 80
local BLINK = 16 / 60
local NAME_LEN = 7
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local FALLBACK = {
  birch = {
    welcome = {
      "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!",
      "My name is BIRCH. But everyone calls me the POKeMON PROFESSOR.",
    },
    thisIsPokemon = "This is what we call a POKeMON.",
    world = {
      "This world is widely inhabited by creatures known as POKeMON.",
      "To unravel POKeMON mysteries, I've been undertaking research. That's what I do.",
    },
    andYouAre = "And you are?",
    boyOrGirl = { "Are you a boy? Or are you a girl?" },
    whatsYourName = { "All right. What's your name?" },
    soItsPlayer = "So it's {PLAYER}?",
    ahOkay = {
      "Ah, okay! You're {PLAYER} who's moving to my hometown of LITTLEROOT. I get it now!",
    },
    areYouReady = {
      "All right, are you ready?",
      "Your very own adventure is about to unfold.",
      "Well, I'll be expecting you later. Come see me in my POKeMON LAB.",
    },
  },
  menu = {
    newGame = "NEW GAME",
    continue = "CONTINUE",
    option = "OPTION",
    player = "PLAYER",
    time = "TIME",
    pokedex = "POKeDEX",
    badges = "BADGES",
    boy = "BOY",
    girl = "GIRL",
    newName = "NEW NAME",
  },
  names = {
    male = { "NEW NAME", "BRENDAN", "SETH", "TERRELL", "CHAZ" },
    female = { "NEW NAME", "MAY", "KIMMY", "CELIA", "KIRA" },
  },
  species = { azurill = 350, groudon = 405 },
}

local function pagesOf(value, fallback)
  if type(value) == "table" and #value > 0 then return value end
  if type(value) == "string" and value ~= "" then return { value } end
  if type(fallback) == "table" then return fallback end
  return { fallback or "..." }
end

local function withPlayer(text, name)
  text = tostring(text or "")
  name = name or "BRENDAN"
  return (text:gsub("{PLAYER}", name))
end

function Boot.attach(Game3)
  Game3.BOOT_COPYRIGHT = "copyright"
  Game3.BOOT_INTRO = "intro"
  Game3.BOOT_TITLE = "title"
  Game3.BOOT_MENU = "menu"
  Game3.BOOT_OPTION = "option"
  Game3.BOOT_BIRCH = "birch"
  Game3.BOOT_GENDER = "gender"
  Game3.BOOT_NAME = "name"
  Game3.BOOT_NAMING = "naming"
  Game3.BOOT_CONFIRM = "confirm"
  Game3.NAME_LENGTH = NAME_LEN

  function Game3:bootData()
    return (self.data and self.data.title) or FALLBACK
  end

  function Game3:resetBoot()
    self.boot = { kind = Game3.BOOT_COPYRIGHT, t = 0, cursor = 0, blink = 0 }
    self.options = self.options or {
      textSpeed = 2, -- MID (pokeruby SetDefaultOptions)
      battleScene = true,
      battleStyle = "shift",
      stereo = false, -- MONO
    }
    return self.boot
  end

  function Game3:menuLayout()
    if self.saveExists then return "save" end
    return "new"
  end

  function Game3:menuActions()
    if self:menuLayout() == "save" then
      return { "continue", "new", "option" }
    end
    return { "new", "option" }
  end

  function Game3:continueInfo()
    local info = self:readSave()
    if type(info) ~= "table" then return nil end
    local dex = tonumber(info.dexCount)
    if not dex then
      dex = 0
      if type(info.caught) == "table" then
        for _, v in pairs(info.caught) do
          if v then dex = dex + 1 end
        end
      end
    end
    local badges = tonumber(info.badgeCount)
    if not badges then
      badges = 0
      local flags = info.flags or {}
      for i = 0, 7 do
        if flags[Game3.FLAG_BADGE01_GET + i] then badges = badges + 1 end
      end
    end
    return {
      playerName = info.playerName,
      playSeconds = info.playSeconds or 0,
      dexCount = dex,
      badgeCount = badges,
    }
  end

  function Game3:stepOptionMenu(box, onClose)
    if type(box) ~= "table" then return end
    local rows = 5
    if Input:wasPressed("up") then
      box.cursor = ((box.cursor or 0) - 1) % rows
      if box.cursor < 0 then box.cursor = rows - 1 end
    elseif Input:wasPressed("down") then
      box.cursor = ((box.cursor or 0) + 1) % rows
    elseif Input:wasPressed("b") then
      if onClose then onClose() end
    elseif Input:wasPressed("a") or Input:wasPressed("left")
        or Input:wasPressed("right") then
      local opt = self.options or {}
      local c = box.cursor or 0
      if c == 0 then
        opt.textSpeed = ((opt.textSpeed or 2) % 3) + 1
      elseif c == 1 then
        opt.battleScene = not opt.battleScene
      elseif c == 2 then
        opt.battleStyle = opt.battleStyle == "set" and "shift" or "set"
      elseif c == 3 then
        opt.stereo = not opt.stereo
      else
        if onClose then onClose() end
      end
      self.options = opt
    end
  end

  function Game3:playTimeString(seconds)
    seconds = math.floor(tonumber(seconds) or self.playSeconds or 0)
    if seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local h = math.floor(m / 60)
    m = m % 60
    if h > 999 then h = 999; m = 59 end
    return ("%d:%02d"):format(h, m)
  end

  function Game3:badgeCount()
    local n = 0
    for i = 1, 8 do
      if self:hasBadge(i) then n = n + 1 end
    end
    return n
  end

  function Game3:dexCount()
    local n = 0
    for _, v in pairs(self.caught or {}) do
      if v then n = n + 1 end
    end
    return n
  end

  function Game3:expandBootText(text)
    return withPlayer(text, self:playerName())
  end

  function Game3:beginNewGame()
    self.boot = nil
    self.field = nil
    if not self.map then
      self.phase = "roster"
      return true
    end
    self.phase = "play"
    if self.gender == nil then self:openGenderMenu() end
    return true
  end

  function Game3:openMainMenu()
    self.boot = {
      kind = Game3.BOOT_MENU,
      t = 0, cursor = 0, blink = 0,
    }
    self.saveExists = self:hasSave()
    return true
  end

  function Game3:openTitle()
    self.boot = { kind = Game3.BOOT_TITLE, t = 0, cursor = 0, blink = 0 }
    return true
  end

  function Game3:openIntro()
    self.boot = { kind = Game3.BOOT_INTRO, t = 0, cursor = 0, blink = 0 }
    return true
  end

  function Game3:bootPic(species)
    species = tonumber(species)
    if not species then return nil end
    return self.battlePic and self:battlePic(species, "front")
  end

  -- pokeruby SPECIES_AZURILL 350 / SPECIES_GROUDON 405.  Older caches
  -- stored national-dex 298 / Cradily 389.
  function Game3:bootSpecies()
    local spec = (self:bootData() or {}).species or FALLBACK.species
    local az = spec.azurill or FALLBACK.species.azurill
    local gr = spec.groudon or FALLBACK.species.groudon
    if az == 298 then az = 350 end
    if gr == 389 then gr = 405 end
    return az, gr
  end

  function Game3:startBirchSpeech()
    -- Wipe CONTINUE leftovers, but do not enterMap: field scripts during
    -- the cinema can drop the map and finishBirch then opens the roster.
    self:wipeNewGameState()
    self._newGamePending = true
    self.gender = nil
    self.customName = nil
    self.playSeconds = 0
    self.trainerId = nil
    self:ensureTrainerId()
    self.phase = "boot"
    local data = self:bootData()
    local birch = data.birch or FALLBACK.birch
    local queue = {}
    local function push(value, fallback)
      local pages = pagesOf(value, fallback)
      for i = 1, #pages do queue[#queue + 1] = pages[i] end
    end
    push(birch.welcome, FALLBACK.birch.welcome)
    push(birch.thisIsPokemon, FALLBACK.birch.thisIsPokemon)
    push(birch.world, FALLBACK.birch.world)
    push(birch.andYouAre, FALLBACK.birch.andYouAre)
    self.boot = {
      kind = Game3.BOOT_BIRCH,
      t = 0, cursor = 0, blink = 0,
      queue = queue, qi = 1,
      showMon = false,
    }
    return true
  end

  function Game3:finishBirch()
    if self.gender == nil then self:applyGender(Game3.GENDER_MALE) end
    if not self.customName or self.customName == "" then
      self.customName = self:isFemale() and "MAY" or "BRENDAN"
    end
    self.playSeconds = 0
    if self._newGamePending then
      self._newGamePending = nil
      self:spawnAtNewGame()
    end
    self.boot = nil
    if not self.map then
      self.phase = "roster"
      return true
    end
    self.phase = "play"
    self.field = nil
    return true
  end

  function Game3:presetNames()
    local data = self:bootData()
    local names = data.names or FALLBACK.names
    if self:isFemale() then return names.female or FALLBACK.names.female end
    return names.male or FALLBACK.names.male
  end

  function Game3:setPresetName(index)
    local names = self:presetNames()
    local name = names[(index or 1) + 1] or names[2]
    if not name or name == "NEW NAME" then
      name = self:isFemale() and "MAY" or "BRENDAN"
    end
    self.customName = name:sub(1, NAME_LEN)
    return self.customName
  end

  local function letters()
    local out = {}
    for i = 1, #LETTERS do out[i] = LETTERS:sub(i, i) end
    out[#out + 1] = "DEL"
    out[#out + 1] = "END"
    return out
  end

  function Game3:openNaming()
    local seed = self.customName
    if not seed or seed == "" then
      seed = self:isFemale() and "MAY" or "BRENDAN"
    end
    self.boot = {
      kind = Game3.BOOT_NAMING,
      t = 0, cursor = 0, blink = 0,
      name = seed:sub(1, NAME_LEN),
      keys = letters(),
    }
    return true
  end

  function Game3:confirmPlayerName()
    local data = self:bootData()
    local birch = data.birch or FALLBACK.birch
    local queue = {}
    local function push(value, fallback)
      local pages = pagesOf(value, fallback)
      for i = 1, #pages do
        queue[#queue + 1] = self:expandBootText(pages[i])
      end
    end
    push(birch.soItsPlayer, FALLBACK.birch.soItsPlayer)
    self.boot = {
      kind = Game3.BOOT_CONFIRM,
      t = 0, cursor = 0, blink = 0,
      queue = queue, qi = 1,
      after = "ready",
    }
    return true
  end

  function Game3:birchReady()
    local data = self:bootData()
    local birch = data.birch or FALLBACK.birch
    local queue = {}
    local function push(value, fallback)
      local pages = pagesOf(value, fallback)
      for i = 1, #pages do
        queue[#queue + 1] = self:expandBootText(pages[i])
      end
    end
    push(birch.ahOkay, FALLBACK.birch.ahOkay)
    push(birch.areYouReady, FALLBACK.birch.areYouReady)
    self.boot = {
      kind = Game3.BOOT_CONFIRM,
      t = 0, cursor = 0, blink = 0,
      queue = queue, qi = 1,
      after = "play",
    }
    return true
  end

  function Game3:advanceBootTalk()
    local b = self.boot
    if not b then return end
    local queue, qi = b.queue or {}, b.qi or 1
    if qi < #queue then
      b.qi = qi + 1
      b.textPage = 0
      b.printSrc = nil
      return
    end
    if b.kind == Game3.BOOT_BIRCH then
      self.boot = { kind = Game3.BOOT_GENDER, t = 0, cursor = 0, blink = 0 }
    elseif b.after == "ready" then
      self:birchReady()
    else
      self:finishBirch()
    end
  end

  function Game3:stepBoot(dt)
    dt = dt or 0
    if not self.boot then self:resetBoot() end
    local b = self.boot
    b.t = (b.t or 0) + dt
    b.blink = (b.blink or 0) + dt
    local kind = b.kind
    if kind == Game3.BOOT_COPYRIGHT then
      if b.t >= COPYRIGHT_SEC then self:openIntro() end
      return
    end
    if kind == Game3.BOOT_INTRO then
      if Input:wasPressed("a") or Input:wasPressed("b")
          or Input:wasPressed("start") or Input:wasPressed("select")
          or b.t >= INTRO_SEC then
        self:openTitle()
      end
      return
    end
    if kind == Game3.BOOT_TITLE then
      if Input:wasPressed("a") or Input:wasPressed("start") then
        self:openMainMenu()
      elseif b.t >= TITLE_LOOP_SEC then
        self:resetBoot()
      end
      return
    end
    if kind == Game3.BOOT_MENU then
      local actions = self:menuActions()
      local n = #actions
      if Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("b") then
        self:openTitle()
      elseif Input:wasPressed("a") or Input:wasPressed("start") then
        local act = actions[(b.cursor or 0) + 1]
        if act == "continue" then
          local ok, err = self:continueSave()
          if not ok then self.bootHint = err or "Save is unreadable." end
        elseif act == "new" then
          self:startBirchSpeech()
        else
          self.boot = { kind = Game3.BOOT_OPTION, t = 0, cursor = 0, blink = 0 }
        end
      end
      return
    end
    if kind == Game3.BOOT_OPTION then
      self:stepOptionMenu(b, function() self:openMainMenu() end)
      return
    end
    if kind == Game3.BOOT_BIRCH or kind == Game3.BOOT_CONFIRM then
      b.text = self:expandBootText((b.queue and b.queue[b.qi or 1]) or "")
      self:stepPrinter(b, dt)
      if Input:wasPressed("a") or Input:wasPressed("b") then
        if self:advanceDialogue(b) then
          return
        end
        if kind == Game3.BOOT_BIRCH then
          local text = b.queue and b.queue[b.qi or 1] or ""
          if tostring(text):find("call a POKeMON", 1, true)
              or tostring(text):find("This is what we call", 1, true) then
            b.showMon = true
          end
        end
        self:advanceBootTalk()
      end
      return
    end
    if kind == Game3.BOOT_GENDER then
      if Input:wasPressed("up") or Input:wasPressed("down") then
        b.cursor = 1 - (b.cursor or 0)
      elseif Input:wasPressed("b") then
        self:startBirchSpeech()
      elseif Input:wasPressed("a") then
        self:applyGender((b.cursor or 0) == 1
          and Game3.GENDER_FEMALE or Game3.GENDER_MALE)
        local data = self:bootData()
        local birch = data.birch or FALLBACK.birch
        self.boot = {
          kind = Game3.BOOT_NAME,
          t = 0, cursor = 0, blink = 0,
          queue = pagesOf(birch.whatsYourName, FALLBACK.birch.whatsYourName),
          qi = 1,
        }
      end
      return
    end
    if kind == Game3.BOOT_NAME then
      local names = self:presetNames()
      local n = #names
      if Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("b") then
        self.boot = { kind = Game3.BOOT_GENDER, t = 0, cursor = 0, blink = 0 }
      elseif Input:wasPressed("a") then
        if (b.cursor or 0) == 0 then
          self:setPresetName(1)
          self:openNaming()
        else
          self:setPresetName(b.cursor)
          self:confirmPlayerName()
        end
      end
      return
    end
    if kind == Game3.BOOT_NAMING then
      local keys = b.keys or letters()
      local n = #keys
      local cols = 9
      if Input:wasPressed("left") then
        b.cursor = ((b.cursor or 0) - 1) % n
        if b.cursor < 0 then b.cursor = n - 1 end
      elseif Input:wasPressed("right") then
        b.cursor = ((b.cursor or 0) + 1) % n
      elseif Input:wasPressed("up") then
        b.cursor = ((b.cursor or 0) - cols) % n
        if b.cursor < 0 then b.cursor = b.cursor + n end
      elseif Input:wasPressed("down") then
        b.cursor = ((b.cursor or 0) + cols) % n
      elseif Input:wasPressed("b") then
        local name = b.name or ""
        b.name = name:sub(1, math.max(0, #name - 1))
      elseif Input:wasPressed("a") or Input:wasPressed("start") then
        local key = keys[(b.cursor or 0) + 1]
        if key == "END" or Input:wasPressed("start") then
          local name = b.name or ""
          if name == "" then name = self:isFemale() and "MAY" or "BRENDAN" end
          self.customName = name:sub(1, NAME_LEN)
          self:confirmPlayerName()
        elseif key == "DEL" then
          local name = b.name or ""
          b.name = name:sub(1, math.max(0, #name - 1))
        else
          local name = b.name or ""
          if #name < NAME_LEN then b.name = name .. key end
        end
      end
    end
  end

  function Game3:drawBootTalk(text, extra)
    self:drawWindow(16, 104, 208, 48)
    local G = love.graphics
    G.setColor(0.10, 0.10, 0.12, 1)
    if extra then
      self:drawText(text or "", 24, 112)
      self:drawText(extra, 24, 128)
      return
    end
    local b = self.boot
    if type(b) == "table"
        and (b.kind == Game3.BOOT_BIRCH or b.kind == Game3.BOOT_CONFIRM) then
      self:drawDialogue(b, 24, 112)
      return
    end
    local lines = Game3.wrapDialogue(text or "")
    if lines[1] then self:drawText(lines[1], 24, 112) end
    if lines[2] then self:drawText(lines[2], 24, 128) end
  end

  function Game3:drawCopyright()
    local G = love.graphics
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    G.setColor(1, 1, 1, 1)
    self:drawText("POKeMON RUBY VERSION", 40, 40)
    self:drawText("C2002  POKEMON", 56, 72)
    self:drawText("C1995-2002  NINTENDO", 40, 88)
    self:drawText("C1995-2002  CREATURES inc.", 24, 104)
    self:drawText("C1995-2002  GAME FREAK inc.", 16, 120)
  end

  function Game3:drawIntro()
    local G = love.graphics
    G.setColor(0.18, 0.04, 0.04, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    G.setColor(1, 1, 1, 1)
    self:drawText("GAME FREAK", 80, 24)
    local data = self:bootData()
    local _, groudon = self:bootSpecies()
    local img = self:bootPic(groudon)
    G.setColor(1, 1, 1, 1)
    if img then
      G.draw(img, 88, 48)
    else
      G.setColor(0.45, 0.12, 0.10, 1)
      G.rectangle("fill", 88, 56, 64, 64)
      G.setColor(1, 1, 1, 1)
    end
    self:drawText("POKeMON RUBY", 64, 132)
  end

  function Game3:drawTitleScreen()
    local G = love.graphics
    G.setColor(0.02, 0.02, 0.04, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local data = self:bootData()
    local _, groudon = self:bootSpecies()
    local img = self:bootPic(groudon)
    G.setColor(1, 1, 1, 1)
    if img then G.draw(img, 88, 48) end
    self:drawText("POKeMON", 88, 12)
    self:drawText("RUBY VERSION", 72, 28)
    local b = self.boot
    local on = math.floor(((b and b.blink) or 0) / BLINK) % 2 == 0
    if on then self:drawText("PRESS START", 72, 120) end
    self:drawText("C2002 POKEMON/NINTENDO", 32, 144)
  end

  function Game3:drawMainMenu()
    local G = love.graphics
    G.setColor(0.10, 0.22, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local data = self:bootData()
    local menu = data.menu or FALLBACK.menu
    local actions = self:menuActions()
    local cursor = self.boot and self.boot.cursor or 0
    local y = 16
    for i = 1, #actions do
      local act = actions[i]
      local h = 24
      if act == "continue" then h = 56 end
      self:drawWindow(16, y, 208, h)
      if (i - 1) == cursor then self:drawCursor(22, y + 6) end
      G.setColor(0.10, 0.10, 0.12, 1)
      if act == "continue" then
        self:drawText(menu.continue, 32, y + 4)
        local info = self:continueInfo()
        local name = (info and info.playerName) or "BRENDAN"
        local time = self:playTimeString(info and info.playSeconds)
        self:drawText(menu.player, 32, y + 20)
        self:drawText(name, 88, y + 20)
        self:drawText(menu.time, 140, y + 20)
        self:drawText(time, 180, y + 20)
        self:drawText(menu.pokedex, 32, y + 36)
        self:drawText(tostring((info and info.dexCount) or 0), 96, y + 36)
        self:drawText(menu.badges, 140, y + 36)
        self:drawText(tostring((info and info.badgeCount) or 0), 196, y + 36)
      elseif act == "new" then
        self:drawText(menu.newGame, 32, y + 4)
      else
        self:drawText(menu.option, 32, y + 4)
      end
      y = y + h + 8
    end
    if self.bootHint then
      G.setColor(1, 1, 1, 1)
      self:drawText(self.bootHint, 16, 148)
    end
  end

  function Game3:drawOptionMenu(box)
    local G = love.graphics
    G.setColor(0.10, 0.22, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    self:drawWindow(16, 16, 208, 128)
    local opt = self.options or {}
    box = box or self.boot
    local cursor = box and box.cursor or 0
    local speed = ({ "SLOW", "MID", "FAST" })[opt.textSpeed or 2] or "FAST"
    local rows = {
      { "TEXT SPEED", speed },
      { "BATTLE SCENE", opt.battleScene == false and "OFF" or "ON" },
      { "BATTLE STYLE", opt.battleStyle == "set" and "SET" or "SHIFT" },
      { "SOUND", opt.stereo == false and "MONO" or "STEREO" },
      { "CANCEL", "" },
    }
    for i = 1, #rows do
      local y = 24 + (i - 1) * 20
      if (i - 1) == cursor then self:drawCursor(24, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(rows[i][1], 36, y)
      if rows[i][2] ~= "" then self:drawText(rows[i][2], 160, y) end
    end
  end

  function Game3:drawBirchPortrait()
    local G = love.graphics
    local spec = Game3.spriteSpec(self.data and self.data.sprites, Game3.GFX_BIRCH)
    local img = spec and self:spriteImage(Game3.GFX_BIRCH)
    if img then
      local pose = Game3.poseFor(spec, "south", false, 0)
      local quad = self:owQuad(spec, img, pose.frame or 0)
      G.setColor(1, 1, 1, 1)
      G.draw(img, quad, 96, 24, 0, 2, 2)
      return true
    end
    G.setColor(0.82, 0.62, 0.32, 1)
    G.rectangle("fill", 96, 32, 48, 56)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("BIRCH", 100, 92)
    return false
  end

  function Game3:drawBirchScene()
    local G = love.graphics
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local b = self.boot
    if b and b.showMon then
      local azurill = self:bootSpecies()
      local img = self:bootPic(azurill)
      G.setColor(1, 1, 1, 1)
      if img then
        G.draw(img, 88, 24)
      else
        G.setColor(0.85, 0.55, 0.70, 1)
        G.rectangle("fill", 96, 32, 48, 48)
      end
    else
      self:drawBirchPortrait()
    end
    local text = ""
    if b and b.queue then
      b.text = self:expandBootText(b.queue[b.qi or 1])
      text = self:printedText(b)
    end
    self:drawBootTalk(text)
  end

  function Game3:drawGenderPick()
    local G = love.graphics
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local data = self:bootData()
    local menu = data.menu or FALLBACK.menu
    local birch = data.birch or FALLBACK.birch
    self:drawBootTalk((pagesOf(birch.boyOrGirl, FALLBACK.birch.boyOrGirl))[1])
    self:drawWindow(160, 40, 64, 48)
    local cursor = self.boot and self.boot.cursor or 0
    local labels = { menu.boy, menu.girl }
    for i = 0, 1 do
      local y = 48 + i * 16
      if i == cursor then self:drawCursor(168, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(labels[i + 1], 178, y)
    end
  end

  function Game3:drawNamePick()
    local G = love.graphics
    G.setColor(0.55, 0.78, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local names = self:presetNames()
    local b = self.boot
    local prompt = ""
    if b and b.queue then prompt = b.queue[b.qi or 1] or "" end
    self:drawBootTalk(prompt)
    self:drawWindow(16, 16, 120, 88)
    local cursor = b and b.cursor or 0
    for i = 1, #names do
      local y = 24 + (i - 1) * 16
      if (i - 1) == cursor then self:drawCursor(24, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(names[i], 36, y)
    end
  end

  function Game3:drawNaming()
    local G = love.graphics
    G.setColor(0.10, 0.22, 0.45, 1)
    G.rectangle("fill", 0, 0, Game3.SCREEN_W, Game3.SCREEN_H)
    local b = self.boot
    self:drawWindow(16, 16, 208, 32)
    G.setColor(0.10, 0.10, 0.12, 1)
    self:drawText("YOUR NAME?", 24, 24)
    self:drawText(b and b.name or "", 120, 24)
    self:drawWindow(16, 56, 208, 96)
    local keys = b and b.keys or {}
    local cursor = b and b.cursor or 0
    local cols = 9
    for i = 1, #keys do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local x = 24 + col * 22
      local y = 64 + row * 18
      if (i - 1) == cursor then self:drawCursor(x - 8, y) end
      G.setColor(0.10, 0.10, 0.12, 1)
      self:drawText(keys[i], x, y)
    end
  end

  function Game3:drawBoot()
    local b = self.boot
    local kind = b and b.kind or Game3.BOOT_COPYRIGHT
    if kind == Game3.BOOT_COPYRIGHT then
      self:drawCopyright()
    elseif kind == Game3.BOOT_INTRO then
      self:drawIntro()
    elseif kind == Game3.BOOT_TITLE then
      self:drawTitleScreen()
    elseif kind == Game3.BOOT_MENU then
      self:drawMainMenu()
    elseif kind == Game3.BOOT_OPTION then
      self:drawOptionMenu()
    elseif kind == Game3.BOOT_BIRCH or kind == Game3.BOOT_CONFIRM then
      self:drawBirchScene()
    elseif kind == Game3.BOOT_GENDER then
      self:drawGenderPick()
    elseif kind == Game3.BOOT_NAME then
      self:drawNamePick()
    else
      self:drawNaming()
    end
  end
end

return Boot
