-- Coverage audit for the Gen 3 field-script VM.
--
-- Walks every script a Ruby cart can reach from its map tables -- object,
-- sign, coord-trigger and map-script entry points, plus everything they
-- goto/call -- and reports what the importer can and cannot read.  The
-- point is to answer "which commands does the ROM actually use?" with the
-- cart rather than a guess, so effort goes to commands that ship in Ruby
-- instead of ones that only exist in the macro file.
--
--   luajit tools/gen3_script_audit.lua "Pokemon - Ruby Version (USA).gba"
--   luajit tools/gen3_script_audit.lua <rom> --specials   also list special ids
--
-- Exit status is 1 when any entry point truncates, i.e. when the walk hits
-- a byte Gen3Script.cmdSize cannot measure and so cannot know where the
-- next command starts.  A command that has a length but no VM case is not a
-- truncation: it decodes as a nop, so the audit counts it as unimplemented
-- and keeps going.
package.path = "./?.lua;./?/init.lua;" .. package.path

local GbaBin = require("src.import.GbaBin")
local Gen3Script = require("src.import.Gen3Script")
local RomExtractorGen3 = require("src.import.RomExtractorGen3")

local NAMES = {
  [0x00] = "nop", [0x01] = "nop1", [0x02] = "end", [0x03] = "return",
  [0x04] = "call", [0x05] = "goto", [0x06] = "goto_if", [0x07] = "call_if",
  [0x08] = "gotostd", [0x09] = "callstd", [0x0A] = "gotostdif",
  [0x0B] = "callstdif", [0x0C] = "returnram", [0x0D] = "endram",
  [0x0E] = "setmysteryeventstatus", [0x0F] = "loadword", [0x10] = "loadbyte",
  [0x11] = "writebytetoaddr", [0x12] = "loadbytefromaddr",
  [0x13] = "setptrbyte", [0x14] = "copylocal", [0x15] = "copybyte",
  [0x16] = "setvar", [0x17] = "addvar", [0x18] = "subvar",
  [0x19] = "copyvar", [0x1A] = "setorcopyvar",
  [0x1B] = "compare_local_to_local", [0x1C] = "compare_local_to_value",
  [0x1D] = "compare_local_to_addr", [0x1E] = "compare_addr_to_local",
  [0x1F] = "compare_addr_to_value", [0x20] = "compare_addr_to_addr",
  [0x21] = "compare_var_to_value", [0x22] = "compare_var_to_addr",
  [0x23] = "compare_addr_to_var", [0x24] = "compare_var_to_var",
  [0x25] = "special", [0x26] = "specialvar", [0x27] = "waitstate",
  [0x28] = "delay", [0x29] = "setflag", [0x2A] = "clearflag",
  [0x2B] = "checkflag", [0x2C] = "initclock", [0x2D] = "dotimebasedevents",
  [0x2E] = "gettime", [0x2F] = "playse", [0x30] = "waitse",
  [0x31] = "playfanfare", [0x32] = "waitfanfare", [0x33] = "playbgm",
  [0x34] = "savebgm", [0x35] = "fadedefaultbgm", [0x36] = "fadenewbgm",
  [0x37] = "fadeoutbgm", [0x38] = "fadeinbgm", [0x39] = "warp",
  [0x3A] = "warpsilent", [0x3B] = "warpdoor", [0x3C] = "warphole",
  [0x3D] = "warpteleport", [0x3E] = "setwarp", [0x3F] = "setdynamicwarp",
  [0x40] = "setdivewarp", [0x41] = "setholewarp", [0x42] = "getplayerxy",
  [0x43] = "getpartysize", [0x44] = "additem", [0x45] = "removeitem",
  [0x46] = "checkitemspace", [0x47] = "checkitem", [0x48] = "checkitemtype",
  [0x49] = "addpcitem", [0x4A] = "checkpcitem", [0x4B] = "adddecoration",
  [0x4C] = "removedecoration", [0x4D] = "checkdecor",
  [0x4E] = "checkdecorspace", [0x4F] = "applymovement",
  [0x50] = "applymovementat", [0x51] = "waitmovement",
  [0x52] = "waitmovementat", [0x53] = "removeobject",
  [0x54] = "removeobjectat", [0x55] = "addobject", [0x56] = "addobjectat",
  [0x57] = "setobjectxy", [0x58] = "showobjectat", [0x59] = "hideobjectat",
  [0x5A] = "faceplayer", [0x5B] = "turnobject", [0x5C] = "trainerbattle",
  [0x5D] = "dotrainerbattle", [0x5E] = "gotopostbattlescript",
  [0x5F] = "gotobeatenscript", [0x60] = "checktrainerflag",
  [0x61] = "settrainerflag", [0x62] = "cleartrainerflag",
  [0x63] = "setobjectxyperm", [0x64] = "moveobjectoffscreen",
  [0x65] = "setobjectmovementtype", [0x66] = "waitmessage",
  [0x67] = "message", [0x68] = "closemessage", [0x69] = "lockall",
  [0x6A] = "lock", [0x6B] = "releaseall", [0x6C] = "release",
  [0x6D] = "waitbuttonpress", [0x6E] = "yesnobox", [0x6F] = "multichoice",
  [0x70] = "multichoicedefault", [0x71] = "multichoicegrid",
  [0x72] = "drawbox", [0x73] = "erasebox", [0x74] = "drawboxtext",
  [0x75] = "showmonpic", [0x76] = "hidemonpic", [0x77] = "showcontestwinner",
  [0x78] = "braillemessage", [0x79] = "givemon", [0x7A] = "giveegg",
  [0x7B] = "setmonmove", [0x7C] = "checkpartymove", [0x7D] = "bufferspeciesname",
  [0x7E] = "bufferleadmonspeciesname", [0x7F] = "bufferpartymonnick",
  [0x80] = "bufferitemname", [0x81] = "bufferdecorationname",
  [0x82] = "buffermovename", [0x83] = "buffernumberstring",
  [0x84] = "bufferstdstring", [0x85] = "bufferstring",
  [0x86] = "pokemart", [0x87] = "pokemartdecoration",
  [0x88] = "pokemartdecoration2", [0x89] = "playslotmachine",
  [0x8A] = "setberrytree", [0x8B] = "choosecontestmon",
  [0x8C] = "startcontest", [0x8D] = "showcontestresults",
  [0x8E] = "contestlinktransfer", [0x8F] = "random",
  [0x90] = "addmoney", [0x91] = "removemoney", [0x92] = "checkmoney",
  [0x93] = "showmoneybox", [0x94] = "hidemoneybox",
  [0x95] = "updatemoneybox", [0x96] = "getpokenewsactive",
  [0x97] = "fadescreen", [0x98] = "fadescreenspeed",
  [0x99] = "setflashlevel", [0x9A] = "animateflash",
  [0x9B] = "messageautoscroll", [0x9C] = "dofieldeffect",
  [0x9D] = "setfieldeffectargument", [0x9E] = "waitfieldeffect",
  [0x9F] = "setrespawn", [0xA0] = "checkplayergender",
  [0xA1] = "playmoncry", [0xA2] = "setmetatile", [0xA3] = "resetweather",
  [0xA4] = "setweather", [0xA5] = "doweather",
  [0xA6] = "setstepcallback", [0xA7] = "setmaplayoutindex",
  [0xA8] = "setobjectpriority", [0xA9] = "resetobjectpriority",
  [0xAA] = "createvobject", [0xAB] = "turnvobject",
  [0xAC] = "opendoor", [0xAD] = "closedoor", [0xAE] = "waitdooranim",
  [0xAF] = "setdooropen", [0xB0] = "setdoorclosed", [0xB1] = "addelevmenuitem",
  [0xB2] = "showelevmenu", [0xB3] = "checkcoins", [0xB4] = "addcoins",
  [0xB5] = "removecoins", [0xB6] = "setwildbattle", [0xB7] = "dowildbattle",
  [0xB8] = "setvaddress", [0xB9] = "vgoto", [0xBA] = "vcall",
  [0xBB] = "vgoto_if", [0xBC] = "vcall_if", [0xBD] = "vmessage",
  [0xBE] = "vloadptr", [0xBF] = "vbufferstring",
  [0xC0] = "showcoinsbox", [0xC1] = "hidecoinsbox",
  [0xC2] = "updatecoinsbox", [0xC3] = "incrementgamestat",
  [0xC4] = "setescapewarp", [0xC5] = "waitmoncry",
  [0xC6] = "bufferboxname", [0xC7] = "textcolor",
  [0xC8] = "loadhelp", [0xC9] = "unloadhelp", [0xCA] = "signmsg",
  [0xCB] = "normalmsg", [0xCC] = "comparehiddenvar",
}

-- Commands whose effect the VM reproduces.  Anything else with a length
-- still parses (as a nop) but silently does nothing at runtime, which is
-- what this audit is meant to surface.
local IMPLEMENTED = {}
for _, cmd in ipairs({
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0F, 0x16,
  0x17, 0x18, 0x19, 0x1A, 0x21, 0x22, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A,
  0x2B, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x39, 0x3A, 0x3B, 0x3C,
  0x3D, 0x3E, 0x3F, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x4B, 0x4F, 0x51, 0x53, 0x55,
  0x57, 0x58, 0x59, 0x5A, 0x5B, 0x5C, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65,
  0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x79, 0x7A, 0x7C, 0x7D, 0x7E,
  0x7F, 0x80, 0x81, 0x82, 0x83, 0x86, 0x8A, 0x8B, 0x8C, 0x8D, 0x8F, 0x90, 0x91, 0x92, 0x93,
  0x94, 0x95, 0x97, 0x9F,
  0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xAC, 0xAD, 0xAE, 0xAF, 0xB0, 0xB6, 0xB7, 0xC3, 0xC4, 0xC5,
}) do IMPLEMENTED[cmd] = true end

local BRANCH = { [0x05] = 1, [0x06] = 2 }        -- goto, goto_if: target off
local CALL = { [0x04] = 1, [0x07] = 2 }          -- call, call_if: target off
local STOP = { [0x02] = true, [0x03] = true, [0x05] = true,
               [0x0C] = true, [0x0D] = true }

local romPath, wantSpecials
for i = 1, #arg do
  if arg[i] == "--specials" then wantSpecials = true else romPath = arg[i] end
end
if not romPath then
  io.stderr:write("usage: luajit tools/gen3_script_audit.lua <rom.gba> " ..
    "[--specials]\n")
  os.exit(2)
end

local fh = assert(io.open(romPath, "rb"))
local rom = fh:read("*a")
fh:close()

local groups, err = RomExtractorGen3.findMapGroups(rom)
if not groups then
  io.stderr:write("cannot read map groups: " .. tostring(err) .. "\n")
  os.exit(2)
end

-- Every entry point, tagged with where it came from so a truncation can be
-- reported against a map rather than a bare ROM offset.
local entries, seenEntry = {}, {}
local function addEntry(off, where)
  if type(off) ~= "number" or off < 0 or off >= #rom then return end
  if seenEntry[off] then return end
  seenEntry[off] = true
  entries[#entries + 1] = { off = off, where = where }
end

local function ptrAt(off)
  local word = GbaBin.u32(rom, off)
  if not GbaBin.isRomPtr(word, #rom) then return nil end
  return GbaBin.romOffset(word)
end

local mapCount = 0
for gi, headers in ipairs(groups.groups) do
  for mi, header in ipairs(headers) do
    mapCount = mapCount + 1
    local tag = ("map %d.%d"):format(gi - 1, mi - 1)
    local ev = header.eventsOff
    if ev and ev + 20 <= #rom then
      local objOff = ptrAt(ev + 4)
      if objOff then
        for i = 0, GbaBin.u8(rom, ev) - 1 do
          local o = RomExtractorGen3.parseObjectTemplate(rom, objOff + i * 0x18)
          if not o then break end
          addEntry(o.scriptOff, tag .. " object " .. (o.localId or i))
        end
      end
      local coordOff = ptrAt(ev + 12)
      if coordOff then
        local size = RomExtractorGen3.COORD_EVENT_SIZE
        for i = 0, GbaBin.u8(rom, ev + 2) - 1 do
          local c = RomExtractorGen3.parseCoordEvent(rom, coordOff + i * size)
          if not c then break end
          addEntry(c.scriptOff, tag .. " coord " .. i)
        end
      end
      local bgOff = ptrAt(ev + 16)
      if bgOff then
        local size = RomExtractorGen3.BG_EVENT_SIZE
        for i = 0, GbaBin.u8(rom, ev + 3) - 1 do
          local o = bgOff + i * size
          if o + size > #rom then break end
          local kind = GbaBin.u8(rom, o + 5)
          -- Kinds 1 and 5..7 hold an item or base id at +8, not a pointer.
          if kind == 0 then addEntry(ptrAt(o + 8), tag .. " sign " .. i) end
        end
      end
    end
    local ms = RomExtractorGen3.parseMapScripts(rom, header.scriptsOff)
    for _, key in ipairs({ "onLoad", "onTransition", "onResume",
                           "onDiveWarp" }) do
      addEntry(ms[key], tag .. " " .. key)
    end
    for _, key in ipairs({ "onFrame", "onWarp" }) do
      local rows = ms[key]
      if type(rows) == "table" then
        for i = 1, #rows do
          addEntry(rows[i].scriptOff, ("%s %s %d"):format(tag, key, i))
        end
      end
    end
  end
end

-- Raw bytecode walk, deliberately independent of Gen3Script.parse: the
-- audit has to see the commands the parser drops as nops, and has to keep
-- following calls past the parser's recursion cap.
local uses, truncs, specials = {}, {}, {}
local totalCmds = 0
local overOps, overCall, widest, deepest = 0, 0, 0, 0

-- Counting is global while walking is per entry point.  Shared code --
-- a std script, a Pokemon Center, a common subroutine -- is reachable
-- from dozens of entries, so counting per walk multiplies it by however
-- many objects happen to call it and makes a command look far more used
-- than it is.  One tally per ROM offset keeps these numbers comparable to
-- a static count over the decomp's sources.
local counted = {}

-- Returns how many commands the entry reaches and how deep its calls nest,
-- so the caps Script.parse imposes can be checked against real scripts.
-- Those two stay per entry: they describe one parse, not the whole cart.
local function walk(entry)
  local queue, seen = { { entry.off, 0 } }, {}
  local n, depth = 0, 0
  while #queue > 0 do
    local job = table.remove(queue)
    local off, at = job[1], job[2]
    if at > depth then depth = at end
    while off and off + 1 <= #rom and not seen[off] do
      seen[off] = true
      local cmd = GbaBin.u8(rom, off)
      local size = Gen3Script.cmdSize(rom, off)
      if not size then
        if not counted[off] then
          truncs[#truncs + 1] = {
            cmd = cmd, off = off, where = entry.where, from = entry.off,
          }
          counted[off] = true
        end
        break
      end
      if not counted[off] then
        counted[off] = true
        uses[cmd] = (uses[cmd] or 0) + 1
        totalCmds = totalCmds + 1
        if cmd == 0x25 or cmd == 0x26 then
          local id = GbaBin.u16(rom, off + (cmd == 0x25 and 1 or 3))
          specials[id] = (specials[id] or 0) + 1
        end
      end
      n = n + 1
      local rel = BRANCH[cmd] or CALL[cmd]
      if rel then
        local dest = ptrAt(off + rel)
        if dest and not seen[dest] then
          queue[#queue + 1] = { dest, CALL[cmd] and at + 1 or at }
        end
      end
      if STOP[cmd] then break end
      off = off + size
    end
  end
  return n, depth
end

for i = 1, #entries do
  local n, depth = walk(entries[i])
  if n > widest then widest = n end
  if depth > deepest then deepest = depth end
  if n > Gen3Script.MAX_OPS then overOps = overOps + 1 end
  if depth > Gen3Script.MAX_CALL then overCall = overCall + 1 end
end

local function nameOf(cmd)
  return NAMES[cmd] or ("cmd_%02X"):format(cmd)
end

local used, unimpl = {}, {}
for cmd, n in pairs(uses) do
  used[#used + 1] = { cmd = cmd, n = n }
  if not IMPLEMENTED[cmd] then unimpl[#unimpl + 1] = { cmd = cmd, n = n } end
end
table.sort(used, function(a, b) return a.n > b.n end)
table.sort(unimpl, function(a, b) return a.n > b.n end)

print(("rom            %s (%.1f MiB)"):format(romPath, #rom / 1048576))
print(("maps           %d in %d groups"):format(mapCount, #groups.groups))
print(("entry points   %d"):format(#entries))
print(("commands       %d sites, %d distinct"):format(totalCmds, #used))
print(("implemented    %d of %d distinct (%.0f%% of commands by count)"):format(
  #used - #unimpl, #used,
  (function()
    local ok = 0
    for _, r in ipairs(used) do
      if IMPLEMENTED[r.cmd] then ok = ok + r.n end
    end
    return totalCmds > 0 and ok / totalCmds * 100 or 0
  end)()))
print(("truncations    %d"):format(#truncs))
print(("widest script  %d commands (MAX_OPS %d, %d entries over)"):format(
  widest, Gen3Script.MAX_OPS, overOps))
print(("deepest calls  %d (MAX_CALL %d, %d entries over)"):format(
  deepest, Gen3Script.MAX_CALL, overCall))
print("")

print("-- commands the ROM uses that the VM ignores (by frequency)")
if #unimpl == 0 then
  print("   (none)")
end
for _, r in ipairs(unimpl) do
  print(("   %6d  [0x%02X] %s"):format(r.n, r.cmd, nameOf(r.cmd)))
end
print("")

if #truncs > 0 then
  print("-- truncations: no length known, cannot find the next command")
  local byCmd = {}
  for _, t in ipairs(truncs) do
    byCmd[t.cmd] = byCmd[t.cmd] or { n = 0, first = t }
    byCmd[t.cmd].n = byCmd[t.cmd].n + 1
  end
  for cmd, r in pairs(byCmd) do
    print(("   %6d  [0x%02X] first at 0x%06X in %s"):format(
      r.n, cmd, r.first.off, r.first.where))
  end
  print("")
end

-- pokeruby's gSpecials is a flat run of def_special lines, so a special's
-- id is just its ordinal.  Naming them turns the list below from opaque
-- numbers into the actual work queue.
local function specialNames()
  -- Appended rather than listed: an unset POKERUBY would leave a nil hole
  -- at index 1 and ipairs would stop before trying anything else.
  local roots = {}
  local home = os.getenv("USERPROFILE") or os.getenv("HOME")
  if os.getenv("POKERUBY") then roots[#roots + 1] = os.getenv("POKERUBY") end
  if home then
    roots[#roots + 1] = home .. "/Desktop/pokeruby-master/pokeruby-master"
    roots[#roots + 1] = home .. "/Desktop/pokeruby-master"
  end
  for _, root in ipairs(roots) do
    if root and root ~= "" then
      local fh = io.open(root .. "/data/specials.inc", "rb")
      if fh then
        local names, i = {}, 0
        for line in fh:lines() do
          local fn = line:match("^%s*def_special%s+([%w_]+)")
          if fn then
            names[i] = fn
            i = i + 1
          end
        end
        fh:close()
        if i > 0 then return names end
      end
    end
  end
  return {}
end

if wantSpecials then
  local named = specialNames()
  local rows = {}
  for id, n in pairs(specials) do rows[#rows + 1] = { id = id, n = n } end
  table.sort(rows, function(a, b) return a.n > b.n end)
  print(("-- %d distinct specials called%s"):format(
    #rows, next(named) and "" or " (no pokeruby checkout for names)"))
  for _, r in ipairs(rows) do
    print(("   %6d  0x%03X  %s"):format(r.n, r.id, named[r.id] or "?"))
  end
  print("")
end

os.exit(#truncs > 0 and 1 or 0)
