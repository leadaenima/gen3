-- THE FOUR ADAPTERS A FORCED GEN 1 / GEN 2 MOD REACHES FOR.
--
-- The community's mods are written against Red's modules.  Forced onto a Ruby
-- game they resolve what Gen3Compat serves and are refused the rest -- and
-- four names accounted for every hard refusal across the nine mods measured:
-- src.world.PikachuFollower, src.ui.OptionRows, src.ui.PartyMenu and
-- src.world.NPC.
--
-- Each is adapted to what Ruby can HONESTLY answer, which is not the same as
-- reimplementing Red:
--
--   * Hoenn has no follower, so PikachuFollower answers "no follower" rather
--     than being absent -- a mod that wraps its update installs a wrap that
--     does nothing, which is correct, instead of crashing on a nil module;
--   * OptionRows' arithmetic is generation-neutral and its draw is not;
--   * PartyMenu's icon helpers route to Game3's own atlas; its menu does not;
--   * an NPC record translates, but PLACING one does not -- Ruby draws the
--     object events its map declares and has no runtime-object store.
--
-- The regression this suite also exists to stop: a builder must not require
-- the module it stands in for.  buildOptionRows first borrowed the real
-- OptionRows for its arithmetic, the loader's require gate routed that
-- facaded name back into the builder, and qol_toggles died with a stack
-- overflow at load.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Gen3Compat = require("src.mods.Gen3Compat")

local S = require("tests.harness").suite("gen3 compat adapters")
local check, eq = S.check, S.eq

local FOUR = { "src.world.PikachuFollower", "src.ui.OptionRows",
               "src.ui.PartyMenu", "src.world.NPC" }

-- ------- served at all, and described

for _, name in ipairs(FOUR) do
  check(Gen3Compat.serves(name), name .. " is served on Gen 3")
  local mod = Gen3Compat.resolve(name, "test_mod")
  check(type(mod) == "table", name .. " resolves a table")
  local cover = Gen3Compat.coverage(name)
  check(type(cover) == "table", name .. " publishes coverage")
  check(next(cover.members) ~= nil, name .. " names its members")
  check(type(cover.target) == "string" and cover.target ~= "",
    name .. " names what backs it")
end

-- ------- no builder may require the module it stands in for
--
-- Checked as SOURCE rather than by calling, because the recursion only bites
-- through the loader's require gate -- a direct resolve here would not
-- reproduce it, and the test would pass while the game hung.
do
  local NL = string.char(10)
  local src = io.open("src/mods/Gen3Compat.lua"):read("a")
  local served = {}
  for n in src:gmatch('%["(src%.[%w_.]+)"%]%s*=%s*build') do served[#served + 1] = n end
  for n in src:gmatch('%["(src%.[%w_.]+)"%]%s*=%s*"') do served[#served + 1] = n end
  check(#served >= #FOUR, "the adapter table was found in the source")
  -- COMMENTS ARE NOT CALLS.  An adapter's prose legitimately names the
  -- module it stands in for, and scanning the raw source read that as a
  -- self-require -- a false alarm on correct code, which is as bad as
  -- missing a real one.  Comments are stripped line by line.
  local codeLines = {}
  for line in (src .. NL):gmatch('([^' .. NL .. ']*)' .. NL) do
    codeLines[#codeLines + 1] = (line:gsub('%-%-.*$', ''))
  end
  local code = table.concat(codeLines, NL)
  local offenders = {}
  for _, n in ipairs(served) do
    if code:find('require("' .. n .. '")', 1, true) then
      offenders[#offenders + 1] = n
    end
  end
  eq(#offenders, 0,
    "no builder requires its own facaded name (" .. table.concat(offenders, ",") .. ")")
end

-- ------- PikachuFollower: Hoenn has nobody

do
  local PF = Gen3Compat.resolve("src.world.PikachuFollower")
  eq(PF.current(), nil, "nobody is following")
  eq(PF.at(), nil, "and nobody is anywhere")
  eq(PF.shouldSpawn(), false, "nothing should spawn")
  eq(PF.isFollowingDisabled(), true,
    "following reports DISABLED, so a caller suppresses its own handling")
  eq(PF.starterInParty(), false, "no Yellow starter rules apply")
  check(type(PF.update) == "function", "update exists")
  eq(PF.update(1 / 60), nil, "and does nothing")

  -- the wrap a mod installs must survive, which is why this is a plain table
  local calls = 0
  local inner = PF.update
  PF.update = function(...) calls = calls + 1 return inner(...) end
  PF.update(1 / 60)
  eq(calls, 1, "a mod can wrap update the way free_fly does")
  PF.__modStampedField = true
  eq(PF.__modStampedField, true, "and stamp its own fields on the module")
  PF.update, PF.__modStampedField = inner, nil
end

-- ------- OptionRows: the arithmetic carries, the chrome does not

do
  local OR = Gen3Compat.resolve("src.ui.OptionRows")
  eq(OR.VISIBLE, 4, "the viewport is four boxes, as in Gen 1")
  check(type(OR.clampScroll) == "function", "clampScroll is real")

  -- the same answers src/ui/OptionRows.lua gives, which is the point of
  -- reproducing it rather than inventing a scroll rule
  eq(OR.clampScroll(1, 0, 10), 0, "a cursor already in view does not scroll")
  eq(OR.clampScroll(5, 0, 10), 1, "stepping past the bottom scrolls by one")
  eq(OR.clampScroll(2, 5, 10), 1, "stepping above the top scrolls back")
  eq(OR.clampScroll(9, 0, 10, 9), 6,
    "the fixed bottom row jumps to the tail of the list")

  -- ...and the draw is inert rather than absent, so a wrap still installs
  check(type(OR.draw) == "function", "draw exists so a mod can wrap it")
  eq(OR.draw(), nil, "but paints nothing on Ruby")
  local cover = Gen3Compat.coverage("src.ui.OptionRows")
  eq(cover.members.draw, "warned", "and it is published as degraded")
  eq(cover.members.clampScroll, "backed", "while the arithmetic is backed")
end

-- ------- PartyMenu: the icons are real, the menu is not

do
  local PM = Gen3Compat.resolve("src.ui.PartyMenu")
  -- drawIcon must route to Game3's own two verbs, not reimplement either
  local asked = {}
  local fakeGame = {
    monIconFrame = function(_, mon) asked.frameFor = mon return 3 end,
    drawMonIcon = function(_, species, x, y, frame)
      asked.drew = { species = species, x = x, y = y, frame = frame }
      return true
    end,
  }
  local mon = { species = 25, hp = 5, maxHp = 20 }
  eq(PM.drawIcon(fakeGame, mon, 16, 32), true, "an icon is drawn")
  eq(asked.frameFor, mon, "the frame was asked for from the game")
  eq(asked.drew.species, 25, "the species was passed through")
  eq(asked.drew.x, 16, "with the x")
  eq(asked.drew.y, 32, "and the y")
  eq(asked.drew.frame, 3, "and the frame the game chose")

  -- a game that cannot draw is refused rather than erroring
  eq(PM.drawIcon({}, mon, 0, 0), false, "a game with no icon verb draws nothing")
  eq(PM.drawIcon(nil, mon, 0, 0), false, "and neither does no game at all")
  eq(PM.drawIcon(fakeGame, nil, 0, 0), false, "nor no mon")

  eq(PM.mirrorsIcon("HELIX"), false,
    "Gen 3 icons are a plain atlas, so nothing is Gen 1's asymmetric case")
  eq(PM.new(), nil, "the Gen 1 menu state is not constructible")
  eq(Gen3Compat.memberStatus("src.ui.PartyMenu", "new"), "absent",
    "and that is published as absent")
  eq(Gen3Compat.memberStatus("src.ui.PartyMenu", "drawIcon"), "backed",
    "while drawIcon is backed")
end

-- ------- NPC: the record translates, the placement does not

do
  local NPC = Gen3Compat.resolve("src.world.NPC")
  -- Ruby's sprite store is keyed by the cart's graphics id under .byId
  local data = { sprites = { byId = { [7] = { path = "npc7.png",
                                              frameCount = 9 } } } }
  local npc = NPC.new(data, "g0_9", { index = 2, x = 4, y = 6,
                                      sprite = 7, range = "LEFT" })
  check(type(npc) == "table", "an NPC record is built")
  eq(npc.cellX, 4, "at the cell it was given")
  eq(npc.cellY, 6, "in both axes")
  eq(npc.px, 64, "with pixel coordinates derived from the cell")
  eq(npc.py, 96, "in both axes")
  eq(npc.facing, "left", "facing where its range says")
  -- stated before it is indexed: a builder that looked the sprite up Gen 1's
  -- way (data.sprites[name]) finds nil here, and this reports it instead of
  -- throwing on the next line
  check(type(npc.sprite) == "table",
    "the sprite resolved through Ruby's .byId store")
  eq(npc.sprite and npc.sprite.path, "npc7.png",
    "and it is RUBY's sprite def")
  -- PLACEMENT EXISTS NOW, and it is a side channel rather than a lie.
  --
  -- This asserted `false` when Ruby could not place a runtime NPC at all.  It
  -- can: src/mods/Gen3Compat.lua parks the record on game._modOwGuests and
  -- draws it beside the map's own object events, rather than injecting it into
  -- ow.entities/npcs -- that path poisoned the voxel cast list, which is why
  -- the guest list exists at all.
  eq(npc.placed, true, "and it IS placed, as a side-channel guest")
  eq(npc._modOwGuest, true,
    "marked as one, so the cast list can tell it from a map's own object")
  check(npc.id:find("g0_9", 1, true) ~= nil, "its id names the map")

  -- a name-keyed Gen 1 lookup must not silently resolve
  local noSprite = NPC.new({ sprites = { byId = {} } }, "g0_9",
                           { index = 1, x = 0, y = 0, sprite = 7 })
  eq(noSprite.sprite, nil, "an unknown sprite id resolves to nothing")
  eq(NPC.new(data, "g0_9", nil), nil, "a missing objDef is refused")

  -- movement.asm's phase window, reproduced exactly
  eq(npc:walkPhase(), 0, "a still NPC is on its rest frame")
  npc.moving = true
  npc.animClock = 0
  eq(npc:walkPhase(), 0, "the first quarter of the cycle is still rest")
  npc.animClock = 4
  eq(npc:walkPhase(), 1, "the middle half is the step frame")
  npc.animClock = 11
  eq(npc:walkPhase(), 1, "right to the end of it")
  npc.animClock = 12
  eq(npc:walkPhase(), 0, "and the last quarter is rest again")

  -- pose returns Gen 1's seven values in Gen 1's order
  npc.animClock, npc.moving = 4, true
  local sprite, px, py, facing, phase, flip, hop = npc:pose()
  eq(sprite, npc.sprite, "pose hands back the sprite")
  eq(px, 64, "the x")
  eq(py, 96, "the y")
  eq(facing, "left", "the facing")
  eq(phase, 1, "the walk phase")
  eq(type(flip), "boolean", "a flip flag")
  eq(hop, false, "and no hop, which an NPC never does")

  npc:facePlayer(10, 6)
  eq(npc.facing, "right", "facePlayer turns toward the player")
  npc:facePlayer(4, 0)
  eq(npc.facing, "up", "on whichever axis is further")

  npc.cellX, npc.cellY = 99, 99
  npc:resetToSpawn()
  eq(npc.cellX, 4, "resetToSpawn returns it to its def")
  eq(npc.cellY, 6, "in both axes")

  check(Gen3Compat.memberStatus("src.world.NPC", "draw") == "absent",
    "draw is absent: a Gen 1 renderer would paint through the wrong pipeline")
end

-- ------- the module the facade must NOT stand in for
--
-- src.core.Strings is a CALLABLE table: every call site spells it
-- `Strings("QOL TOGGLES")`, reaching __call.  A softStub answers a function
-- for any field read and carries no __call, so serving the name handed back
-- something that required cleanly and then raised "attempt to call upvalue
-- 'Strings' (a table value)" on first use -- which is what qol_toggles' option
-- rows hit on every build.
--
-- Two halves, and the second is the one that matters: not serving it is only
-- correct because the module it falls through to is callable and generation-
-- neutral.  A stub that merely stopped being reported would leave a mod's
-- text untranslated and say nothing.
do
  check(not Gen3Compat.serves("src.core.Strings"),
    "the Gen 3 facade does not stand in for src.core.Strings")
  eq(Gen3Compat.resolve("src.core.Strings"), nil,
    "so resolve has nothing to hand back and the gate falls through")

  local Strings = require("src.core.Strings")
  local meta = getmetatable(Strings)
  eq(type(meta and meta.__call), "function",
    "the real module is callable, which is how every call site uses it")
  -- the call itself, not just the metamethod's presence: with no catalog
  -- loaded it is an identity function, which is exactly what Ruby needs
  eq(Strings("QOL TOGGLES"), "QOL TOGGLES",
    "and calling it with no catalog answers the English source")
  eq(Strings("%d/%d ON", 3, 7), "3/7 ON",
    "including the formatting form the option rows use")
end

return S.finish()
