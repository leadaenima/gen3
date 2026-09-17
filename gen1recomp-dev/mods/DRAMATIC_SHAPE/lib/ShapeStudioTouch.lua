-- Mobile Map Studio: finger-first Shape Studio chrome + persist helpers.
-- Active when Android/iOS or POKEPORT_TOUCH=1. Desktop F8 Studio stays intact.

local V = ...

local Overrides = V.require("ShapeOverrides")

local Studio
local function S()
  if not Studio then Studio = V.require("ShapeStudio") end
  return Studio
end

local Touch = {}

Touch.tool = "select"  -- select | level | chroma | tex | height
Touch._padWasEnabled = nil
Touch._fingers = {}    -- id -> {x,y}
Touch._drag = nil      -- {kind, x0,y0, x1,y1, id}
Touch._status = ""
Touch._statusT = 0
Touch._lastExport = nil
Touch._importBusy = false

local BTN_H = 48
local BTN_GAP = 6
local FAB_W, FAB_H = 120, 48

local function envTouch()
  local env = os.getenv("POKEPORT_TOUCH")
  if env == "1" then return true end
  if env == "0" then return false end
  return nil
end

function Touch.isTouchUi()
  local forced = envTouch()
  if forced ~= nil then return forced end
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

function Touch.isMobileOs()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

local function say(msg)
  Touch._status = tostring(msg or "")
  Touch._statusT = 4.0
  local st = S()
  if st then
    st.status = Touch._status
    st.statusT = Touch._statusT
  end
end

local function touchControls()
  local ok, TC = pcall(require, "src.core.TouchControls")
  if ok then return TC end
  return nil
end

function Touch.suppressPad(on)
  local TC = touchControls()
  if not TC then return end
  if on then
    if Touch._padWasEnabled == nil then
      Touch._padWasEnabled = (TC.enabled ~= false)
    end
    TC.enabled = false
    pcall(function() TC:reset() end)
  else
    if Touch._padWasEnabled ~= nil then
      TC.enabled = Touch._padWasEnabled
      Touch._padWasEnabled = nil
    end
  end
end

function Touch.onStudioOpened()
  if Touch.isTouchUi() then
    Touch.suppressPad(true)
    Touch.tool = "select"
    say("MAP EDIT — tap a tile; use toolbar")
  end
end

function Touch.onStudioClosed()
  Touch.suppressPad(false)
  Touch._drag = nil
  Touch._fingers = {}
  Touch.tool = "select"
end

-- ---- layout (window / LOVE units) ----

local function winSize()
  if love and love.graphics and love.graphics.getDimensions then
    return love.graphics.getDimensions()
  end
  return 800, 480
end

local function fabRect()
  local ww, wh = winSize()
  local w, h = FAB_W, math.max(BTN_H, math.floor(wh * 0.08))
  local x = ww - w - 12
  local y = 12
  -- keep clear of notches a bit
  return { x = x, y = y, w = w, h = h, id = "fab" }
end

local TOOLS = {
  { id = "select", label = "Select" },
  { id = "hplus", label = "H+" },
  { id = "hminus", label = "H-" },
  { id = "level", label = "Level" },
  { id = "class", label = "Class" },
  { id = "art", label = "Art" },
  { id = "tex", label = "Texture" },
  { id = "chroma", label = "Chroma" },
  { id = "save1", label = "Save" },
  { id = "save2", label = "Save all" },
  { id = "export", label = "Export" },
  { id = "import", label = "Import" },
  { id = "undo", label = "Undo" },
  { id = "close", label = "Close" },
}

local function toolbarLayout()
  local ww, wh = winSize()
  local margin = 8
  local h = math.max(BTN_H, math.floor(wh * 0.09))
  local cols = 7
  local rows = math.ceil(#TOOLS / cols)
  local usableW = ww - margin * 2
  local bw = math.floor((usableW - BTN_GAP * (cols - 1)) / cols)
  local totalH = rows * h + (rows - 1) * BTN_GAP + margin
  local y0 = wh - totalH
  local btns = {}
  for i, t in ipairs(TOOLS) do
    local col = ((i - 1) % cols)
    local row = math.floor((i - 1) / cols)
    btns[#btns + 1] = {
      id = t.id,
      label = t.label,
      x = margin + col * (bw + BTN_GAP),
      y = y0 + row * (h + BTN_GAP),
      w = bw,
      h = h,
    }
  end
  return btns, y0
end

local function hitRect(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function hitToolbar(x, y)
  local btns = toolbarLayout()
  for _, b in ipairs(btns) do
    if hitRect(b, x, y) then return b end
  end
  return nil
end

local function inToolbarBand(x, y)
  local _, y0 = toolbarLayout()
  return y >= y0
end

-- ---- actions ----

local function applyHeight(delta)
  if not S().selection then
    say("tap a tile first")
    return
  end
  S().nudgeHeight(delta)
  S().previewApply()
end

local function doExport()
  local path, err = Overrides.exportMobile()
  if path then
    Touch._lastExport = path
    say("exported: " .. path)
  else
    say("export failed: " .. tostring(err))
  end
end

local function doImport()
  if Touch._importBusy then return end
  Touch._importBusy = true
  local function finish(ok, note)
    Touch._importBusy = false
    say(ok and ("merged: " .. tostring(note)) or ("import failed: " .. tostring(note)))
    if ok and S().active then
      pcall(function()
        local ow = nil
        local okG, Game = pcall(require, "src.core.Game")
        ow = okG and Game and Game.overworld
        if ow and ow.map and Overrides.refreshGeometry then
          Overrides.refreshGeometry(ow.map.id)
        end
      end)
    end
  end
  -- Prefer SAF picker on Android when available.
  if love and love.system and love.system.pickFile then
    local okp, picked = pcall(love.system.pickFile, "file")
    if okp and type(picked) == "string" and picked ~= "" then
      local ok, note = Overrides.importMerge(picked)
      finish(ok, note)
      return
    end
  end
  -- Fallback: merge newest export under save-dir shape_studio/export/
  local ok, note = Overrides.importMerge(nil)  -- nil = scan save dir
  finish(ok, note)
end

local function fireTool(id)
  if id == "select" then
    Touch.tool = "select"
    S().levelMode = false
    S().chromaDrop = false
    S().texDrop = false
    say("Select tool")
  elseif id == "hplus" then
    applyHeight(1)
  elseif id == "hminus" then
    applyHeight(-1)
  elseif id == "level" then
    Touch.tool = "level"
    S().levelMode = true
    S().chromaDrop = false
    S().texDrop = false
    say("Level: drag a rectangle to player height")
  elseif id == "class" then
    S().cycleClass(1)
    S().previewApply()
    say("class " .. tostring(S().edit.class))
  elseif id == "art" then
    S().cycleArt(1)
    S().previewApply()
    say("art " .. tostring(S().edit.art))
  elseif id == "tex" then
    Touch.tool = "tex"
    S().texDrop = true
    S().chromaDrop = false
    S().levelMode = false
    say("Texture: tap source cell (same tileset)")
  elseif id == "chroma" then
    Touch.tool = "chroma"
    S().chromaDrop = true
    S().texDrop = false
    S().levelMode = false
    say("Chroma: tap the green in the world")
  elseif id == "save1" then
    S().saveThisInstance()
    S().bake()
  elseif id == "save2" then
    S().saveAllInstances()
    S().bake()
  elseif id == "export" then
    -- bake first so export is current
    pcall(function() Overrides.flushPersist() end)
    doExport()
  elseif id == "import" then
    doImport()
  elseif id == "undo" then
    if Overrides.undo and Overrides.undo() then
      pcall(function()
        local okG, Game = pcall(require, "src.core.Game")
        local map = okG and Game and Game.overworld and Game.overworld.map
        if map then Overrides.refreshGeometry(map.id) end
      end)
      say("undo")
    else
      say("nothing to undo")
    end
  elseif id == "close" then
    if S().active then S().toggle() end
  end
end

-- ---- input ----

function Touch.onTouchPressed(id, x, y)
  if not Touch.isTouchUi() then return false end
  Touch._fingers[id] = { x = x, y = y }

  -- FAB opens studio
  if not S().active then
    if hitRect(fabRect(), x, y) then
      S().toggle()
      if S().active then Touch.onStudioOpened() end
      return true
    end
    return false
  end

  -- Studio open: toolbar hits
  local btn = hitToolbar(x, y)
  if btn then
    fireTool(btn.id)
    return true
  end
  if inToolbarBand(x, y) then
    return true  -- eat empty toolbar band
  end

  -- Two-finger start => level mode drag if second finger
  local n = 0
  for _ in pairs(Touch._fingers) do n = n + 1 end
  if n >= 2 and not S().levelDrag then
    S().levelMode = true
    Touch.tool = "level"
  end

  -- World pick / level / chroma / tex — reuse Studio mouse path (window coords)
  if S().mousepressed(x, y, 1) then
    Touch._drag = { kind = "world", id = id, x0 = x, y0 = y }
    return true
  end
  return true
end

function Touch.onTouchMoved(id, x, y)
  if not Touch.isTouchUi() then return false end
  local prev = Touch._fingers[id]
  Touch._fingers[id] = { x = x, y = y }
  if not S().active then return false end

  -- Update level drag via S().update path (polls mouse); also push coords
  if S().levelDrag then
    -- ShapeStudio polls love.mouse; synthesize by calling pick update:
    local Picker = V.require("ShapePicker")
    local okG, Game = pcall(require, "src.core.Game")
    local map = okG and Game and Game.overworld and Game.overworld.map
    if map then
      local cx, cy = Picker.mouseToCanvas(x, y)
      local cell = Picker.pickCell(map, cx, cy)
      if cell then
        S().levelDrag.x1 = cell.cx
        S().levelDrag.y1 = cell.cy
      end
    end
    return true
  end

  -- One-finger pan hint: not implemented as camera (CamControl owns that);
  -- ignore moves outside tools so we don't steal.
  if Touch._drag and Touch._drag.id == id then
    return true
  end
  return false
end

function Touch.onTouchReleased(id, x, y)
  if not Touch.isTouchUi() then return false end
  Touch._fingers[id] = nil
  if not S().active then return false end

  if Touch._drag and Touch._drag.id == id then
    Touch._drag = nil
    if S().mousereleased(x, y, 1) then
      return true
    end
  elseif S().levelDrag then
    S().mousereleased(x, y, 1)
    return true
  end
  return false
end

-- Desktop mouse / POKEPORT path when studio inactive: FAB
function Touch.onMousePressed(x, y, button)
  if not Touch.isTouchUi() or button ~= 1 then return false end
  if not S().active then
    if hitRect(fabRect(), x, y) then
      S().toggle()
      if S().active then Touch.onStudioOpened() end
      return true
    end
    return false
  end
  local btn = hitToolbar(x, y)
  if btn then
    fireTool(btn.id)
    return true
  end
  if inToolbarBand(x, y) then
    return true
  end
  return false  -- let S().mousepressed handle world
end

function Touch.onMouseReleased(x, y, button)
  if not Touch.isTouchUi() or button ~= 1 then return false end
  if S().active and inToolbarBand(x, y) then return true end
  return false
end

-- ---- draw (window space, after TouchControls) ----

local function fillRect(r, R, G, B, A)
  love.graphics.setColor(R, G, B, A or 1)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)
end

local function strokeRect(r, R, G, B, A)
  love.graphics.setColor(R, G, B, A or 1)
  love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 8, 8)
end

local function label(r, text)
  love.graphics.setColor(1, 1, 1, 1)
  local font = love.graphics.getFont()
  local tw = font and font:getWidth(text) or (#text * 7)
  local th = font and font:getHeight() or 12
  love.graphics.print(text, r.x + (r.w - tw) * 0.5, r.y + (r.h - th) * 0.5)
end

function Touch.drawWindow()
  if not Touch.isTouchUi() then return end
  if not love or not love.graphics then return end

  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setLineWidth(2)

  if not S().active then
    -- Only show FAB when voxel overworld is plausible
    local show = true
    pcall(function()
      local Voxel = V.require("VoxelState")
      if Voxel and Voxel.on and not Voxel.on() then show = false end
    end)
    if show then
      local fab = fabRect()
      fillRect(fab, 0.12, 0.45, 0.22, 0.92)
      strokeRect(fab, 0.4, 0.95, 0.55, 1)
      label(fab, "MAP EDIT")
    end
  else
    local btns = toolbarLayout()
    for _, b in ipairs(btns) do
      local active = (b.id == Touch.tool)
        or (b.id == "level" and S().levelMode)
        or (b.id == "chroma" and S().chromaDrop)
        or (b.id == "tex" and S().texDrop)
      if active then
        fillRect(b, 0.2, 0.55, 0.85, 0.95)
      else
        fillRect(b, 0.1, 0.1, 0.14, 0.88)
      end
      strokeRect(b, 0.85, 0.85, 0.9, 0.9)
      label(b, b.label)
    end
    -- Status + save path
    local ww, wh = winSize()
    local msg = Touch._status
    if (not msg or msg == "") and S().status and S().status ~= "" then
      msg = S().status
    end
    if Touch._lastExport then
      msg = (msg and msg ~= "" and (msg .. " | ") or "") .. "export:" .. Touch._lastExport
    end
    if msg and msg ~= "" then
      love.graphics.setColor(0, 0, 0, 0.65)
      love.graphics.rectangle("fill", 8, 8, ww - 16, 28, 6, 6)
      love.graphics.setColor(0.95, 0.95, 0.7, 1)
      love.graphics.print(msg, 14, 14)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

function Touch.update(dt)
  if Touch._statusT > 0 then
    Touch._statusT = Touch._statusT - (dt or 0)
    if Touch._statusT <= 0 then Touch._status = "" end
  end
end

return Touch
