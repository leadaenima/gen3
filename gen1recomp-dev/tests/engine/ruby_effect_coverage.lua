-- B0: move-effect coverage ratchet.
--
-- The cart's 355 moves use 198 distinct EFFECT_* ids. The engine dispatches
-- them through scattered `move.effect == Game3.EFFECT_X` comparisons rather
-- than one table, so coverage can only be measured at the source level: an
-- effect counts as handled when Game3 declares a constant for its id AND
-- references that constant somewhere beyond the declaration line.
--
-- Anything else silently falls through to plain damage, which is exactly the
-- failure this guards: a move that looks implemented because it deals damage.
--
-- UNHANDLED_CEILING only ever goes down. Implement a family, watch the number
-- drop, lower the ceiling. It is not allowed to rise.
--
--   luajit tests/engine/ruby_effect_coverage.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby move effect coverage")
local check = S.check
local eq = S.eq

-- Distinct `effect` values across the cart's move table, generated from the
-- extracted moves.lua. Fixed ROM data -- regenerate only if the extractor's
-- move parsing changes.
local ROM_EFFECTS = {
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 16, 17, 18, 19, 20, 23, 24,
  25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
  43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 57, 58, 59, 60, 62, 65,
  66, 67, 68, 69, 70, 71, 72, 73, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84,
  85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 97, 98, 99, 100, 101, 102,
  103, 104, 105, 106, 107, 108, 109, 111, 112, 113, 114, 115, 116, 117,
  118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 132,
  133, 134, 135, 136, 137, 138, 139, 140, 142, 143, 144, 145, 146, 147,
  148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161,
  162, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
  177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190,
  191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204,
  205, 206, 207, 208, 209, 210, 211, 212, 213,
}

-- EFFECT_PLACEHOLDER: id 0 is "no secondary effect", so a move with it is
-- correct as plain damage and is not counted as a gap.
local PLAIN_DAMAGE = 0

-- EFFECT_QUICK_ATTACK (103) shares BattleScript_EffectQuickAttack with a
-- dozen other effects and carries no behaviour of its own: what makes
-- Quick Attack early is gBattleMoves[].priority, which the extractor pulls
-- and turnOrder reads. There is nothing for Game3 to dispatch on, so it is
-- exempt rather than outstanding. The probe below proves the priority path
-- actually works.
local NO_MOVE_BEHAVIOUR = { [103] = true }

-- Lower this as families land. Never raise it.
local UNHANDLED_CEILING = 0

local function readSource(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local text = f:read("*a")
  f:close()
  return text
end

local src = readSource("src/core/Game3.lua")

-- Game3.EFFECT_NAME = <number>
local declared = {}
for name, value in src:gmatch("Game3%.(EFFECT_[A-Z0-9_]+)%s*=%s*(%d+)") do
  declared[tonumber(value)] = name
end

local function referenced(name)
  local n = 0
  for _ in src:gmatch("Game3%." .. name .. "[^A-Z0-9_]") do n = n + 1 end
  -- one hit is the declaration itself
  return n > 1
end

local handled, unhandled = {}, {}
for _, id in ipairs(ROM_EFFECTS) do
  if id == PLAIN_DAMAGE then
    handled[#handled + 1] = id
  else
    local name = declared[id]
    if (name and referenced(name)) or NO_MOVE_BEHAVIOUR[id] then
      handled[#handled + 1] = id
    else
      unhandled[#unhandled + 1] = id
    end
  end
end

eq(#ROM_EFFECTS, 198, "the cart's move table uses 198 distinct effects")

check(next(declared) ~= nil, "Game3 declares EFFECT_ constants")

-- A handful of anchors, so a regex that silently stops matching is caught
-- rather than reporting perfect coverage.
for _, probe in ipairs({
  { "EFFECT_SOLARBEAM", "SolarBeam charges" },
  { "EFFECT_EXPLOSION", "Explosion halves defense" },
  { "EFFECT_LEVEL_DAMAGE", "level-damage moves" },
  { "EFFECT_PERISH_SONG", "Perish Song" },
}) do
  local id
  for v, n in pairs(declared) do if n == probe[1] then id = v end end
  check(id ~= nil, probe[1] .. " is declared")
  check(id and referenced(probe[1]), probe[2] .. " is dispatched")
end

-- Quick Attack is only "handled" because priority drives the turn order,
-- so check that rather than take the exemption on trust.
do
  local Game3 = require("src.core.Game3")
  local g = Game3.new()
  local fast = { name = "F", hp = 10, maxHp = 10, spe = 1,
    stages = { spe = 0 } }
  local slow = { name = "S", hp = 10, maxHp = 10, spe = 200,
    stages = { spe = 0 } }
  g.battle = { player = fast, enemy = slow }
  check(g:turnOrder({ priority = 1 }, { priority = 0 }),
    "a priority move goes first even off a slower mon")
  check(not g:turnOrder({ priority = 0 }, { priority = 0 }),
    "and without it the faster mon does")
end

io.write(("  move effects: %d of %d handled, %d unhandled (ceiling %d)\n")
  :format(#handled, #ROM_EFFECTS, #unhandled, UNHANDLED_CEILING))

check(#unhandled <= UNHANDLED_CEILING,
  ("unhandled effects %d must not exceed the ceiling %d")
    :format(#unhandled, UNHANDLED_CEILING))

if #unhandled < UNHANDLED_CEILING then
  io.write(("  ratchet: lower UNHANDLED_CEILING to %d\n"):format(#unhandled))
end

-- The same ratchet for held items. gItems[].holdEffect drives every one of
-- these in the cart, and 66 of the 67 defined effects sit on a real item.
-- DRAGON_SCALE and UP_GRADE are trade-evolution items with no battle or field
-- behaviour at all, so they are counted as nothing-to-do rather than gaps.
local HOLD_EFFECTS_ON_ITEMS = 66
local NO_BEHAVIOUR = { [44] = true, [61] = true }
local HOLD_UNHANDLED_CEILING = 0

local holdDeclared = {}
for name, value in src:gmatch("Game3%.(HOLD_EFFECT_[A-Z0-9_]+)%s*=%s*(%d+)") do
  holdDeclared[tonumber(value)] = name
end

-- Some effects are reached through a lookup table or a bare numeric compare
-- rather than a named constant, which is still dispatch.
local tableKeys, inlineCompares = {}, {}
for _, tbl in ipairs({ "TYPE_POWER_ITEM", "HOLD_EFFECT_CURE",
    "HOLD_EFFECT_STAT_UP", "HOLD_EFFECT_FLAVOR" }) do
  local body = src:match("Game3%." .. tbl .. " = {(.-)\n}")
  if body then
    for v in body:gmatch("%[(%d+)%]") do tableKeys[tonumber(v)] = true end
    for v in body:gmatch("=%s*(%d+)") do tableKeys[tonumber(v)] = true end
  end
end
for v in src:gmatch("hold == (%d+)") do inlineCompares[tonumber(v)] = true end

local holdMissing = {}
for id = 1, HOLD_EFFECTS_ON_ITEMS do
  local name = holdDeclared[id]
  local reached = (name and referenced(name)) or tableKeys[id] or inlineCompares[id]
  if not reached and not NO_BEHAVIOUR[id] then
    holdMissing[#holdMissing + 1] = id
  end
end

io.write(("  hold effects: %d of %d handled, %d unhandled (ceiling %d)\n")
  :format(HOLD_EFFECTS_ON_ITEMS - #holdMissing, HOLD_EFFECTS_ON_ITEMS,
    #holdMissing, HOLD_UNHANDLED_CEILING))
check(#holdMissing <= HOLD_UNHANDLED_CEILING,
  ("unhandled hold effects %d must not exceed the ceiling %d")
    :format(#holdMissing, HOLD_UNHANDLED_CEILING))

S.finish()
