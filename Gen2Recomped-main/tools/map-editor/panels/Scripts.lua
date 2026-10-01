-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The script attached to a map object.
--
-- Gen 2 is a list of `{ "command", args... }` rows. `ScriptRunner` walks that,
-- with `{"label", name}` as jump targets. Hoenn is a list of `{ op = name, ... }`
-- rows, which is what Game3 already runs, including a nested `body` on call
-- and an `after` script on a trainer battle. Both are edited here as the
-- table the game reads. There is nothing to compile.
--
-- IT VALIDATES WITH THE ENGINE'S OWN VALIDATOR. `ScriptRunner.validate` already
-- reports unknown commands, duplicate labels, malformed rows and jumps to
-- missing labels. Writing a second opinion here would drift from the first, and
-- the drift would show up as a script the editor called fine and the game
-- refused -- so this calls that one and prints what it says.
--
-- A row's arguments are typed on the way IN, not stored as text: `"5"` and `5`
-- are different things to a command handler, and a script that only works
-- because the handler happened to be tolerant is a trap for the next command
-- that is not. Numbers become numbers, `true`/`false` become booleans, anything
-- else stays a string.

local MapEdits = require("tools.map-editor.MapEdits")

local Scripts = {}

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

-- Every command the engine can actually run. Offering a name nothing
-- implements would produce a script that saves, loads, validates as text and
-- then does nothing at the one moment it matters.
local function commandNames(S)
  if S.scrCommands then return S.scrCommands end
  local out = {}
  local ok, Commands = pcall(require, "src.script.Gen2Commands")
  if ok and type(Commands) == "table" then
    for name in pairs(Commands) do
      if type(name) == "string" and type(Commands[name]) == "function" then
        out[#out + 1] = name
      end
    end
  end
  table.sort(out)
  -- `label` is not a command -- ScriptRunner handles it itself -- but it is a
  -- row the player needs to be able to add, so it is offered alongside them.
  table.insert(out, 1, "label")
  S.scrCommands = out
  return out
end

local function typed(text)
  if text == "true" then return true end
  if text == "false" then return false end
  local n = tonumber(text)
  if n ~= nil then return n end
  return text
end

local function argText(v)
  if v == nil then return "" end
  return tostring(v)
end

-- Ruby stores a script as `{ op = "message", text = "..." }`.  That table is
-- what Game3 runs, so editing it here is editing the script, not a preview
-- of one.  `body` and `after` are nested scripts of the same shape.
local function hoennRow(row)
  return type(row) == "table" and type(row.op) == "string"
end

local NESTED = {
  body = true, after = true, steps = true, items = true, cells = true, win = true,
}
local TEXT_FIELD = { text = true, intro = true, defeat = true, cannot = true }

-- Field names are the ones Script.run reads.  A row decoded from the ROM can
-- carry an extra scalar; the panel still shows it.  Changing the op builds a
-- fresh row from this list so a new `setflag` has a `flag` the game will see.
local OP_FIELDS = {
  ["end"] = {}, ["return"] = {}, lock = {}, lockall = {}, release = {},
  releaseall = {}, faceplayer = {}, waitmessage = {}, waitbuttonpress = {},
  closemessage = {}, waitstate = {}, waitse = {}, waitfanfare = {},
  waitdooranim = {}, waitmoncry = {}, fadedefaultbgm = {}, resetweather = {},
  doweather = {}, checkplayergender = {}, getpartysize = {}, dowildbattle = {},
  nop = {}, choosecontestmon = {}, startcontest = {}, showcontestresults = {},
  contestlinktransfer = {},
  message = { "text" }, loadword = { "text" },
  setflag = { "flag" }, clearflag = { "flag" }, checkflag = { "flag" },
  setvar = { "var", "val" }, addvar = { "var", "val" }, subvar = { "var", "val" },
  setorcopyvar = { "var", "val" }, compare = { "var", "val" },
  compare_vars = { "var", "other" },
  ["goto"] = { "to" }, goto_if = { "cond", "to" },
  call = {}, call_if = { "cond" },
  callstd = { "id" }, gotostd = { "id" },
  special = { "id" }, specialvar = { "var", "id" },
  delay = { "frames" }, fadescreen = { "mode", "speed" },
  warp = { "mapGroup", "mapNum", "warpId", "x", "y" },
  warphole = { "mapGroup", "mapNum" },
  setdynamicwarp = { "mapGroup", "mapNum", "warpId", "x", "y" },
  setwarp = { "mapGroup", "mapNum", "warpId", "x", "y" },
  setholewarp = { "mapGroup", "mapNum", "warpId", "x", "y" },
  setdivewarp = { "mapGroup", "mapNum", "warpId", "x", "y" },
  setescapewarp = { "mapGroup", "mapNum", "warpId", "x", "y" },
  yesno = { "x", "y" },
  multichoice = { "x", "y", "list", "default", "perRow", "ignoreB" },
  applymovement = { "localId" },
  waitmovement = { "localId" },
  addobject = { "localId" }, removeobject = { "localId" },
  showobject = { "localId", "mapGroup", "mapNum" },
  hideobject = { "localId", "mapGroup", "mapNum" },
  turnobject = { "localId", "dir" },
  setobjectxy = { "localId", "x", "y" },
  setobjectxyperm = { "localId", "x", "y" },
  setobjectmovementtype = { "localId", "movementType" },
  moveobjectoffscreen = { "localId" },
  setobjectpriority = { "localId", "mapGroup", "mapNum", "priority" },
  resetobjectpriority = { "localId", "mapGroup", "mapNum" },
  opendoor = { "x", "y" }, closedoor = { "x", "y" },
  setmetatile = { "x", "y", "tile", "collision" },
  trainerbattle = { "kind", "trainerId", "intro", "defeat", "cannot" },
  givemon = { "species", "level", "item" }, giveegg = { "species" },
  setwildbattle = { "species", "level", "item" },
  additem = { "item", "count" }, removeitem = { "item", "count" },
  checkitem = { "item", "count" }, checkitemspace = { "item", "count" },
  addmoney = { "amount", "ignore" }, removemoney = { "amount", "ignore" },
  checkmoney = { "amount", "ignore" },
  addcoins = { "count" }, removecoins = { "count" }, checkcoins = { "var" },
  playse = { "id" }, playfanfare = { "id" }, playbgm = { "id", "save" },
  savebgm = { "id" }, fadenewbgm = { "id" },
  fadeoutbgm = { "speed" }, fadeinbgm = { "speed" },
  setweather = { "weather" },
  dofieldeffect = { "id" }, waitfieldeffect = { "id" },
  setfieldeffectargument = { "index", "value" },
  setrespawn = { "id" },
  checktrainerflag = { "id" }, settrainerflag = { "id" },
  cleartrainerflag = { "id" },
  random = { "limit" },
  bufferspecies = { "slot", "species" }, bufferitem = { "slot", "item" },
  bufferdecoration = { "slot", "id" }, buffernumber = { "slot", "val" },
  bufferleadmon = { "slot" },
  bufferpartymonnick = { "slot", "partyIndex" },
  buffermovename = { "slot", "move" },
  checkpartymove = { "move" },
  getplayerxy = { "x", "y" },
  showmoneybox = { "x", "y" }, hidemoneybox = { "x", "y" },
  updatemoneybox = { "x", "y" },
  showcoinsbox = { "x", "y" }, hidecoinsbox = { "x", "y" },
  updatecoinsbox = { "x", "y" },
  playmoncry = { "species", "mode" },
  adddecoration = { "id" }, removedecoration = { "id" },
  checkdecor = { "id" }, checkdecorspace = { "id" },
  braillemessage = { "text" },
  setberrytree = { "tree", "berry", "stage" },
  setflashradius = { "level" }, animateflash = { "level" },
  setstepcallback = { "id" }, setmaplayoutindex = { "index" },
  incrementgamestat = { "id" }, getpricereduction = { "index" },
  playslotmachine = { "id" }, showcontestwinner = { "contestId" },
  pokemart = { "martType" }, pokemartdecoration = { "martType" },
}

local COMMON_OPS = {
  "lock", "lockall", "faceplayer", "message", "loadword",
  "waitmessage", "waitbuttonpress", "closemessage",
  "release", "releaseall", "end", "return",
}

local function playingHoenn(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and GV and GV.engine and GV.engine() == "gen3" then return true end
  local id = tostring(S.mapId or "")
  return id:match("^g%d+_%d+$") ~= nil or id:match("^MAP_G%d+_N%d+$") ~= nil
end

local function useHoenn(S, script)
  if type(script) == "table" and hoennRow(script[1]) then return true end
  if type(script) == "table" and script[1] ~= nil then return false end
  return playingHoenn(S)
end

local function hoennOpNames()
  local seen, out = {}, {}
  for _, name in ipairs(COMMON_OPS) do
    seen[name] = true
    out[#out + 1] = name
  end
  local rest = {}
  for name in pairs(OP_FIELDS) do rest[#rest + 1] = name end
  table.sort(rest)
  for _, name in ipairs(rest) do
    if not seen[name] then out[#out + 1] = name end
  end
  return out
end

local function freshOp(name, prev)
  local row = { op = name }
  for _, k in ipairs(OP_FIELDS[name] or {}) do
    local old = prev and prev[k]
    if old ~= nil and type(old) ~= "table" then
      row[k] = old
    elseif TEXT_FIELD[k] or k == "to" then
      -- An empty `to` means "the next row".  0 is a real index to the
      -- runner and would stop the script instead of falling through.
      row[k] = TEXT_FIELD[k] and "" or nil
    else
      row[k] = 0
    end
  end
  if name == "call" or name == "call_if" then
    row.body = (prev and type(prev.body) == "table") and prev.body or {}
  end
  if name == "trainerbattle" and prev and type(prev.after) == "table" then
    row.after = prev.after
  end
  if name == "applymovement" then
    row.steps = (prev and type(prev.steps) == "table") and prev.steps or {}
  end
  if (name == "pokemart" or name == "pokemartdecoration")
      and prev and type(prev.items) == "table" then
    row.items = prev.items
  end
  return row
end

local function adoptOp(row, name)
  local fresh = freshOp(name, row)
  for k in pairs(row) do row[k] = nil end
  for k, v in pairs(fresh) do row[k] = v end
end

local function scalarFields(row)
  local keys, seen = {}, {}
  for _, k in ipairs(OP_FIELDS[row.op] or {}) do
    if not NESTED[k] then
      keys[#keys + 1] = k
      seen[k] = true
    end
  end
  local extra = {}
  for k, v in pairs(row) do
    if k ~= "op" and not seen[k] and not NESTED[k] and type(v) ~= "table" then
      extra[#extra + 1] = k
    end
  end
  table.sort(extra)
  for _, k in ipairs(extra) do keys[#keys + 1] = k end
  return keys
end

-- The list on screen is either the object's script or a nested `body` /
-- `after` the reader opened.  The stack is indices into each parent, so a
-- reload of another NPC cannot keep showing the previous NPC's inner script.
local function viewOf(S, obj)
  local key = tostring(S.mapId) .. "#" .. tostring(obj.index or obj.localId)
  if S.scrViewKey ~= key then
    S.scrViewKey = key
    S.scrStack = nil
    S.scrSelected = nil
    S.scrScroll = 0
    S.scrCmdOpen = false
  end
  local rows = obj.script
  if type(rows) ~= "table" then rows = {} end
  local stack = S.scrStack
  if type(stack) == "table" then
    for i = 1, #stack do
      local step = stack[i]
      local parent = rows[step.index]
      local inner = parent and parent[step.key]
      if type(inner) ~= "table" then
        while stack[i] do table.remove(stack) end
        break
      end
      rows = inner
    end
  end
  local hoenn = useHoenn(S, obj.script)
  if type(S.scrStack) == "table" and S.scrStack[1] then hoenn = true end
  return rows, hoenn
end

local function rowText(row)
  if hoennRow(row) then
    local parts = { row.op }
    local keys = {}
    for k in pairs(row) do
      if k ~= "op" and k ~= "body" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = row[k]
      if type(v) ~= "table" then
        local text = tostring(v)
        if #text > 72 then text = text:sub(1, 69) .. "..." end
        parts[#parts + 1] = k .. "=" .. text
      end
    end
    return table.concat(parts, "  ")
  end
  local parts = { tostring(row[1] or "?") }
  for i = 2, #row do parts[#parts + 1] = argText(row[i]) end
  return table.concat(parts, "  ")
end

-- The object the OBJECTS tab has selected. Sharing that selection rather than
-- having a second list is what makes the two tabs feel like one editor.
local function selectedObject(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId]
  local objs = (def and def.objects) or {}
  return objs[S.objSelected or 0]
end

local function writeScript(S, obj, rows)
  obj.script = rows
  local st, g = store(S), game(S)
  if obj.added then
    local m = MapEdits.bucket(st, g, S.mapId, true)
    local slot = m.added and m.added[obj.editorSlot]
    if slot then slot.script = rows end
  else
    MapEdits.setObject(st, g, S.mapId, obj.index, { script = rows })
  end
  S.mapEditsDirty = true
end

function Scripts.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad, gap = 16 * s, 20 * s

  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map on the MAPS tab first.")
    return
  end
  local obj = selectedObject(S)
  if not obj then
    Kit.emptyBox(x, y, w, h,
      "Select an object on the OBJECTS tab, then write its script here.")
    return
  end

  local rows, hoenn = viewOf(S, obj)

  local sideW = math.max(220 * s, math.min(300 * s, w * 0.3))
  local listX, listW = x, w - sideW - gap
  local sideX = x + listW + gap

  -- --------------------------------------------------------------- rows
  Kit.card(listX, y, listW, h)
  local depth = (type(S.scrStack) == "table") and #S.scrStack or 0
  local title = string.format("SCRIPT - object #%s", tostring(obj.index or "?"))
  if depth > 0 then title = title .. "  /  inner " .. depth end
  Kit.caption(listX + pad, y + pad, title)
  if depth > 0 then
    local backW = 72 * s
    if Kit.button(listX + listW - pad - backW, y + pad - 4 * s, backW, 26 * s,
                  "BACK", { font = "small" }) then
      table.remove(S.scrStack)
      S.scrSelected = nil
      S.scrScroll = 0
    end
  end
  local top = y + pad + Kit.textHeight("caption") + 10 * s
  local rowH = 30 * s
  local addH = 32 * s
  local listBottom = y + h - pad - addH - 8 * s
  local perPage = math.max(1, math.floor((listBottom - top) / rowH))
  S.scrScroll = math.max(0, math.min(S.scrScroll or 0,
                                     math.max(0, #rows - perPage)))

  if #rows == 0 then
    if hoenn then
      Kit.text("body", "No script yet. Add a row, then pick the command",
               listX + pad, top)
      Kit.text("body", "it should run: message, lock, setflag, warp.",
               listX + pad, top + 18 * s)
    else
      Kit.text("body", "No script. Plain dialogue on the OBJECTS tab is",
               listX + pad, top)
      Kit.text("body", "enough for most NPCs; this is for the rest.",
               listX + pad, top + 18 * s)
    end
  end

  for r = 1, math.min(perPage, #rows - S.scrScroll) do
    local i = r + S.scrScroll
    local ry = top + (r - 1) * rowH
    local selected = S.scrSelected == i
    if Kit.press(listX + pad, ry, listW - 2 * pad, rowH - 4 * s) then
      S.scrSelected = i
    end
    Kit.row(listX + pad, ry, listW - 2 * pad, rowH - 4 * s, selected)
    Kit.text("small", string.format("%2d", i), listX + pad + 6 * s, ry + 7 * s)
    Kit.text("body", rowText(rows[i]), listX + pad + 34 * s, ry + 6 * s)
  end

  local third = (listW - 2 * pad - 16 * s) / 3
  local ay = y + h - pad - addH
  if Kit.button(listX + pad, ay, third, addH, "+ ROW") then
    if hoenn then
      if type(obj.script) ~= "table" then
        obj.script = {}
        rows = obj.script
      end
      rows[#rows + 1] = { op = "message", text = "" }
      writeScript(S, obj, obj.script)
    else
      rows[#rows + 1] = { "label", "step" .. tostring(#rows + 1) }
      writeScript(S, obj, rows)
    end
    S.scrSelected = #rows
  end
  if S.scrSelected and rows[S.scrSelected] then
    if Kit.button(listX + pad + third + 8 * s, ay, third, addH, "MOVE UP")
       and S.scrSelected > 1 then
      rows[S.scrSelected], rows[S.scrSelected - 1] =
        rows[S.scrSelected - 1], rows[S.scrSelected]
      S.scrSelected = S.scrSelected - 1
      writeScript(S, obj, hoenn and obj.script or rows)
    end
    if Kit.button(listX + pad + 2 * (third + 8 * s), ay, third, addH, "DELETE") then
      table.remove(rows, S.scrSelected)
      S.scrSelected = rows[S.scrSelected] and S.scrSelected or nil
      writeScript(S, obj, hoenn and obj.script or rows)
    end
  end

  -- ------------------------------------------------------------ the row
  Kit.card(sideX, y, sideW, h)
  local row = rows[S.scrSelected or 0]
  if not row then
    Kit.emptyBox(sideX + pad, y + pad, sideW - 2 * pad, h - 2 * pad,
                 "Select a row.")
    return
  end

  local fy = y + pad
  Kit.caption(sideX + pad, fy, "ROW " .. tostring(S.scrSelected))
  fy = fy + Kit.textHeight("caption") + 10 * s
  local fieldH = 30 * s
  local inner = sideW - 2 * pad

  if hoennRow(row) then
    local actH = 34 * s
    local ay2 = y + h - pad - actH
    if Kit.button(sideX + pad, fy, inner, fieldH, row.op) then
      S.scrCmdOpen = not S.scrCmdOpen
      S.scrCmdQuery = ""
    end
    fy = fy + fieldH + 6 * s
    if S.scrCmdOpen then
      S.scrCmdQuery = Kit.textfield("scr-op", sideX + pad, fy, inner, fieldH,
                                    S.scrCmdQuery or "", "search commands...")
      fy = fy + fieldH + 4 * s
      local shown = 0
      local q = (S.scrCmdQuery or ""):lower()
      for _, name in ipairs(hoennOpNames()) do
        if q == "" or name:find(q, 1, true) then
          shown = shown + 1
          if shown <= 6 then
            if Kit.button(sideX + pad, fy, inner, fieldH - 4 * s, name,
                          { font = "small",
                            kind = (name == row.op) and "accent" or nil }) then
              adoptOp(row, name)
              writeScript(S, obj, obj.script)
              S.scrCmdOpen = false
            end
            fy = fy + fieldH - 2 * s
          end
        end
      end
      if shown == 0 then
        Kit.text("small", "no command matches", sideX + pad, fy)
      elseif shown > 6 then
        Kit.text("small", string.format("%d more - keep typing", shown - 6),
                 sideX + pad, fy)
      end
      return
    end

    for _, key in ipairs({ "body", "after" }) do
      local inner = row[key]
      if type(inner) == "table" and (inner[1] == nil or hoennRow(inner[1])) then
        local n = 0
        for _ in ipairs(inner) do n = n + 1 end
        local label = (key == "body" and "INNER SCRIPT" or "AFTER SCRIPT")
          .. string.format("  -  %d", n)
        if Kit.button(sideX + pad, fy, inner, fieldH, label, { font = "small" }) then
          S.scrStack = S.scrStack or {}
          S.scrStack[#S.scrStack + 1] = { index = S.scrSelected, key = key }
          S.scrSelected = nil
          S.scrScroll = 0
        end
        fy = fy + fieldH + 4 * s
      end
    end

    if type(row.steps) == "table" then
      Kit.text("small", string.format("%d movement steps, kept with this row",
                                      #row.steps),
               sideX + pad, fy)
      fy = fy + 16 * s
    end
    if type(row.items) == "table" then
      Kit.text("small", string.format("%d mart items, kept with this row",
                                      #row.items),
               sideX + pad, fy)
      fy = fy + 16 * s
    end

    for _, k in ipairs(scalarFields(row)) do
      if fy + fieldH > ay2 - 8 * s then break end
      Kit.text("small", k, sideX + pad, fy + 8 * s)
      local was = argText(row[k])
      local got = Kit.textfield("scr-h" .. tostring(S.scrSelected) .. k,
                                sideX + pad + 78 * s, fy, inner - 78 * s,
                                fieldH, was, "")
      if got ~= was then
        if got == "" then
          row[k] = TEXT_FIELD[k] and "" or nil
        else
          row[k] = typed(got)
        end
        writeScript(S, obj, obj.script)
      end
      fy = fy + fieldH + 4 * s
    end

    if depth == 0 and type(obj.script) == "table" then
      local entry = tonumber(obj.script.entry) or 1
      if fy + fieldH <= ay2 - 8 * s then
        Kit.text("small", "START", sideX + pad, fy + 8 * s)
        if Kit.stepper(sideX + pad + 78 * s, fy, 28 * s, fieldH, "-") then
          obj.script.entry = math.max(1, entry - 1)
          writeScript(S, obj, obj.script)
        end
        Kit.textCenter("small", tostring(entry),
                       sideX + pad + 110 * s, fy + 8 * s, 36 * s)
        if Kit.stepper(sideX + pad + 148 * s, fy, 28 * s, fieldH, "+") then
          obj.script.entry = math.min(#obj.script, entry + 1)
          writeScript(S, obj, obj.script)
        end
      end
    end

    if Kit.button(sideX + pad, ay2, inner, actH, "SAVE") then
      local ok, err = MapEdits.save(store(S))
      S.mapEditsDirty = not ok or nil
      S.scrNotice = ok and "saved" or ("save failed: " .. tostring(err))
    end
    if S.scrNotice then
      Kit.text("small", S.scrNotice, sideX + pad, ay2 - 16 * s)
    end
    return
  end

  if Kit.button(sideX + pad, fy, inner, fieldH, tostring(row[1] or "?")) then
    S.scrCmdOpen = not S.scrCmdOpen
    S.scrCmdQuery = ""
  end
  fy = fy + fieldH + 6 * s
  if S.scrCmdOpen then
    S.scrCmdQuery = Kit.textfield("scr-cmd", sideX + pad, fy, inner, fieldH,
                                  S.scrCmdQuery or "", "search commands...")
    fy = fy + fieldH + 4 * s
    local shown = 0
    for _, name in ipairs(commandNames(S)) do
      if (S.scrCmdQuery or "") == ""
         or name:lower():find((S.scrCmdQuery or ""):lower(), 1, true) then
        shown = shown + 1
        if shown <= 7 then
          if Kit.button(sideX + pad, fy, inner, fieldH - 4 * s, name) then
            row[1] = name
            writeScript(S, obj, rows)
            S.scrCmdOpen = false
          end
          fy = fy + fieldH - 2 * s
        end
      end
    end
    if shown == 0 then
      Kit.text("small", "no command matches", sideX + pad, fy)
      fy = fy + 16 * s
    elseif shown > 7 then
      Kit.text("small", string.format("%d more - keep typing", shown - 7),
               sideX + pad, fy)
      fy = fy + 16 * s
    end
  end

  -- Arguments. Four slots is enough for every lowered command in the engine
  -- and keeps the panel a fixed height; a row needing more is a sign the
  -- command wants a table argument rather than a fifth field.
  for a = 2, 5 do
    Kit.text("small", "arg " .. (a - 1), sideX + pad, fy + 8 * s)
    local was = argText(row[a])
    local got = Kit.textfield("scr-arg" .. a, sideX + pad + 52 * s, fy,
                              inner - 52 * s, fieldH, was, "")
    if got ~= was then
      row[a] = (got == "") and nil or typed(got)
      writeScript(S, obj, rows)
    end
    fy = fy + fieldH + 6 * s
  end

  local actH = 34 * s
  local ay2 = y + h - pad - actH
  local halfW = (inner - 8 * s) / 2
  if Kit.button(sideX + pad, ay2, halfW, actH, "VALIDATE") then
    local ok, problems = pcall(function()
      return require("src.script.ScriptRunner").validate(rows)
    end)
    problems = (ok and problems) or {}
    S.scrProblems = problems
    S.scrNotice = (#problems == 0) and "no problems"
      or string.format("%d problem(s)", #problems)
  end
  if Kit.button(sideX + pad + halfW + 8 * s, ay2, halfW, actH, "SAVE") then
    local ok, err = MapEdits.save(store(S))
    S.mapEditsDirty = not ok or nil
    S.scrNotice = ok and "saved" or ("save failed: " .. tostring(err))
  end

  -- The validator's own words, not a summary of them: it names the row and the
  -- reason, and paraphrasing would lose both.
  local py = ay2 - 18 * s
  for i = math.min(#(S.scrProblems or {}), 4), 1, -1 do
    Kit.text("small", tostring(S.scrProblems[i]), sideX + pad, py)
    py = py - 15 * s
  end
  if S.scrNotice then Kit.text("small", S.scrNotice, sideX + pad, py) end
end

function Scripts.wheelmoved(S, dy)
  S.scrScroll = math.max(0, (S.scrScroll or 0) - (dy or 0))
end

function Scripts.keypressed(S, key)
  if key ~= "delete" or not S.scrSelected then return end
  local obj = selectedObject(S)
  if not obj or type(obj.script) ~= "table" then return end
  local rows = viewOf(S, obj)
  if not rows[S.scrSelected] then return end
  table.remove(rows, S.scrSelected)
  writeScript(S, obj, obj.script)
  S.scrSelected = nil
end

return Scripts
