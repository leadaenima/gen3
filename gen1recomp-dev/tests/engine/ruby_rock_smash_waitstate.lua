-- S_BreakableRock pins "{mon} used ROCK SMASH." if waitstate after
-- FLDEFF_USE_ROCK_SMASH never ScriptContext_Enables.
--   luajit tests/engine/ruby_rock_smash_waitstate.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby rock smash waitstate")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
local Input = require("src.core.Input")

eq(Game3.FLDEFF_USE_ROCK_SMASH, 37, "FLDEFF_USE_ROCK_SMASH")
eq(Game3.GAME_STAT_USED_ROCK_SMASH, 19, "GAME_STAT_USED_ROCK_SMASH")
check(Game3.fieldEffectFollowedByWaitstate(37), "rock smash waitstates")

local g = Game3.new()
g.phase = "play"
g.flags[Game3.FLAG_BADGE03_GET] = true
g.party = {
  { name = "ZIGZAGOON", species = 263, moves = { { id = 249 } } },
}
g:enterMap({
  id = "g_smash_script", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 1, graphicsId = Game3.GFX_BREAKABLE_ROCK },
  },
}, 1, 1, true)
g.facing = "east"
local npc = g:npcByLocalId(1)
g:rememberTalk(npc)
g:checkPartyMove(249)
g:bufferPartyMonNick(0, 0)
g:bufferMoveName(1, 249)
g.scriptWait = true
g:runNpcScript({
  { op = "lockall" },
  { op = "loadword", text = "{STR_VAR_1} used {STR_VAR_2}." },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_DEFAULT },
  { op = "closemessage" },
  { op = "dofieldeffect", id = Game3.FLDEFF_USE_ROCK_SMASH },
  { op = "waitstate" },
  { op = "applymovement", localId = Game3.VAR_LAST_TALKED,
    steps = { { kind = "smash" } } },
  { op = "waitmovement", localId = 0 },
  { op = "removeobject", localId = Game3.VAR_LAST_TALKED },
  { op = "releaseall" },
})
eq(g:scriptWaiting(), false, "talking clears a leftover waitstate")
eq(g.field.kind, "talk", "used-move line is on screen")
check(tostring(g.field.text):find("ZIGZAGOON", 1, true), "buffers the nick")
check(tostring(g.field.text):find("ROCK SMASH", 1, true), "and the move")
g:printerFinish(g.field)
g.scriptWait = true
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
check(not (g.field and g.field.kind == "talk" and g.field.thenContinue),
  "A is not pinned on the used-move box")
local n = 0
while g.field and n < 60 do
  g:walkHeld(1 / 20)
  n = n + 1
end
local rock = g:npcByLocalId(1)
check(rock and (rock.hidden or rock.invisible), "the rock is smashed")
eq(g:getGameStat(Game3.GAME_STAT_USED_ROCK_SMASH), 1, "stat 19")
eq(g.field, nil, "and the script released")

S.finish("ruby rock smash waitstate")
