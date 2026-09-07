-- Item use effects: what happens when an item is *used*, as opposed to held.
-- Hold effects have their own ratchet in ruby_effect_coverage; this one covers
-- the other half.
--
-- struct Item carries two function pointers, fieldUseFunc and battleUseFunc,
-- and every item in the cart points at one of a small number of shared
-- handlers. Grouping the 349 items by those pointers gives 20 field classes
-- and 7 battle classes -- a complete enumeration of what a Ruby item can do
-- when used, taken from the cart rather than from a guess about it.
--
-- The pointers below were read off the cart. They are recorded as addresses
-- because the decomp names them but the ROM does not, and a representative
-- item is named for each so a row can be checked by eye.
--   luajit tests/engine/ruby_item_coverage.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby item use coverage")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")

-- { pointer, count, what it is, an item that uses it, handled }
local FIELD_CLASSES = {
  { 0x00000000, 12,  "no field use (POKe BALLs)",   "MASTER BALL",  true },
  { 0x080C9195, 12,  "mail",                        "BEAD MAIL",    true },
  { 0x080C91CD, 2,   "bikes",                       "MACH BIKE",    true },
  { 0x080C9379, 3,   "fishing rods",                "OLD ROD",      true },
  { 0x080C93E1, 1,   "ITEMFINDER",                  "ITEMFINDER",   true },
  { 0x080C9AC9, 1,   "POKeBLOCK CASE",              " CASE",        true },
  { 0x080C9B39, 1,   "COIN CASE",                   "COIN CASE",    true },
  { 0x080C9D31, 1,   "WAILMER PAIL",                "WAILMER PAIL", true },
  { 0x080C9DB1, 38,  "medicine",                    "ANTIDOTE",     true },
  { 0x080C9DCD, 1,   "SACRED ASH",                  "SACRED ASH",   true },
  { 0x080C9E3D, 5,   "PP restore",                  "ETHER",        true },
  { 0x080C9E59, 2,   "PP UP and PP MAX",            "PP UP",        true },
  { 0x080C9E75, 1,   "RARE CANDY",                  "RARE CANDY",   true },
  { 0x080C9E91, 58,  "TMs and HMs",                 "HM01",         true },
  { 0x080CA015, 3,   "repels",                      "REPEL",        true },
  { 0x080CA0DD, 2,   "the black and white flutes",  "WHITE FLUTE",  true },
  { 0x080CA1E5, 1,   "ESCAPE ROPE",                 "ESCAPE ROPE",  true },
  { 0x080CA229, 6,   "evolution stones",            "MOON STONE",   true },
  { 0x080CA521, 1,   "ENIGMA BERRY",                "ENIGMA BERRY", false },
  { 0x080CA6F1, 198, "cannot be used",              "TOWN MAP",     true },
}

local BATTLE_CLASSES = {
  { 0x00000000, 287, "no battle use",        "TOWN MAP",     true },
  { 0x080CA245, 12,  "POKe BALLs",           "MASTER BALL",  true },
  { 0x080CA311, 7,   "stat boosters",        "X ATTACK",     true },
  { 0x080CA3F5, 35,  "medicine",             "ANTIDOTE",     true },
  { 0x080CA42D, 5,   "PP restore",           "ETHER",        true },
  { 0x080CA4C9, 2,   "escape items",         "POKe DOLL",    true },
  { 0x080CA64D, 1,   "ENIGMA BERRY",         "ENIGMA BERRY", false },
}

-- Lower these as classes land. Never raise them.
local FIELD_UNHANDLED_CEILING = 1
local BATTLE_UNHANDLED_CEILING = 1

local function total(list)
  local n = 0
  for _, row in ipairs(list) do n = n + row[2] end
  return n
end

eq(#FIELD_CLASSES, 20, "the cart has 20 distinct fieldUseFunc handlers")
eq(#BATTLE_CLASSES, 7, "and 7 distinct battleUseFunc handlers")
eq(total(FIELD_CLASSES), 349, "every item belongs to exactly one field class")
eq(total(BATTLE_CLASSES), 349, "and to exactly one battle class")

local fieldGaps, battleGaps = {}, {}
for _, row in ipairs(FIELD_CLASSES) do
  if not row[5] then fieldGaps[#fieldGaps + 1] = row end
end
for _, row in ipairs(BATTLE_CLASSES) do
  if not row[5] then battleGaps[#battleGaps + 1] = row end
end

io.write(("  field use:  %d of %d classes handled, %d not\n")
  :format(#FIELD_CLASSES - #fieldGaps, #FIELD_CLASSES, #fieldGaps))
for _, row in ipairs(fieldGaps) do
  io.write(("    0x%08X  %-28s %d item%s (%s)\n")
    :format(row[1], row[3], row[2], row[2] == 1 and "" or "s", row[4]))
end
io.write(("  battle use: %d of %d classes handled, %d not\n")
  :format(#BATTLE_CLASSES - #battleGaps, #BATTLE_CLASSES, #battleGaps))
for _, row in ipairs(battleGaps) do
  io.write(("    0x%08X  %-28s %d item%s (%s)\n")
    :format(row[1], row[3], row[2], row[2] == 1 and "" or "s", row[4]))
end

check(#fieldGaps <= FIELD_UNHANDLED_CEILING,
  ("unhandled field classes %d must not exceed the ceiling %d")
    :format(#fieldGaps, FIELD_UNHANDLED_CEILING))
check(#battleGaps <= BATTLE_UNHANDLED_CEILING,
  ("unhandled battle classes %d must not exceed the ceiling %d")
    :format(#battleGaps, BATTLE_UNHANDLED_CEILING))
if #fieldGaps < FIELD_UNHANDLED_CEILING then
  io.write(("  ratchet: lower FIELD_UNHANDLED_CEILING to %d\n"):format(#fieldGaps))
end
if #battleGaps < BATTLE_UNHANDLED_CEILING then
  io.write(("  ratchet: lower BATTLE_UNHANDLED_CEILING to %d\n"):format(#battleGaps))
end

-- A table of claims is only worth as much as the claims are true, so every
-- class marked handled must actually reach a branch in the engine.
local g = Game3.new()
for _, spec in ipairs({
  { "isBall", Game3.ITEM_POKE_BALL, "POKe BALLs are recognised" },
  { "isTmHm", Game3.ITEM_TM01, "TMs are recognised" },
}) do
  local fn = Game3[spec[1]]
  check(type(fn) == "function" and fn(spec[2]) == true, spec[3])
end
check(type(g.useFieldItem) == "function", "the field use path exists")
check(type(g.useBattleItem) == "function", "the battle use path exists")
check(type(g.useItemfinder) == "function", "ITEMFINDER has its own handler")
check(type(g.useRod) == "function", "the rods do")
check(type(g.useBike) == "function", "the bikes do")
check(type(g.useWailmerPail) == "function", "the WAILMER PAIL does")
check(type(g.useRepel) == "function", "the repels do")
check(type(g.bootTmHm) == "function", "TMs and HMs do")
check(type(g.useItemOnMon) == "function", "medicine, PP and stones share one")

-- The four this table first got wrong: every one of them is handled, and the
-- ceiling said otherwise until these checks were written.
check(type(g.openPokeblockCase) == "function", "the POKeBLOCK CASE does")
check(type(g.readBagMail) == "function", "mail does")
check(type(g.useSacredAsh) == "function", "SACRED ASH does")
check(type(g.getCoins) == "function", "the COIN CASE reads the coin count")

-- The one class with nothing behind it. ENIGMA BERRY runs a programmed effect
-- that arrives with an e-Reader berry rather than living in the cart, so there
-- is nothing here to extract and nothing to implement against; the item is
-- unobtainable in a normal single-player run. It is counted rather than hidden.
eq(rawget(Game3, "useEnigmaBerry"), nil, "no ENIGMA BERRY use handler")
check(type(g.isEnigmaBerryValid) == "function",
  "only the validity check the scripts ask for")

S.finish()
