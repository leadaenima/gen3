-- THE OVERWORLD CONTROLLER, AS A MOD WRAPS IT.
--
-- Gen 1 keeps the grid walk behind src/world/OverworldController.lua, and one
-- method on it -- `handleInput` -- is the only place that walk reads the pad.
-- That makes it the seam: a mod replaces the walk by wrapping that method and
-- nothing else, and every gate above the call still applies.
--
-- Ruby has no controller object. The walk is Game3:gridHandleInput, called
-- through Game3:fieldHandleInput, which routes through THIS module -- so a
-- wrap installed here is genuinely in the engine's path rather than sitting
-- beside it. That distinction has already cost this port once: the voxel
-- hotkey did nothing for a session because the mod had wrapped a method on
-- the compatibility facade while Game3 went on calling its own.
--
-- `state` throughout is the overworld view (src/core/Game3ModWorld.lua), the
-- same object published as Game.overworld -- NOT the Game3 instance. That is
-- what Gen 1 passes and what a mod's wrap expects to receive as `self`.
--
-- WHERE THE PUSH VERBS LIVE, AND WHERE THEY DO NOT.
--
-- Gen 1's controller also answers checkEdgeExit, checkLedgeHop,
-- checkBoulderPush, canCollisionWarp and takeWarp. Those are called on the
-- STATE -- `state:checkEdgeExit(dir)` -- not on this module, so they belong on
-- the overworld view and are defined in src/core/Game3ModWorld.lua. Putting
-- them here instead was worse than leaving them out: the module they sat on
-- was never the object asked, so a free walk reaching a map edge indexed nil
-- and crashed inside the mod's own file, which reads as the mod's bug.
--
local OverworldAPI = {}

local Logger = require("src.core.Logger")

local function gameOf(state)
  local g = state and state.game
  if type(g) == "table" and type(g.gridHandleInput) == "function" then
    return g
  end
  return nil
end

-- The pad read. Called by Game3:fieldHandleInput once per field frame, under
-- exactly the conditions the inline block ran under.
--
-- Declared with a dot and taking `state` explicitly, because a mod redefines
-- it as `function OverworldState:handleInput()` -- a colon method on this
-- same table -- and calls the previous value as `inner(self)`. Both spellings
-- have to reach the same place.
function OverworldAPI.handleInput(state)
  local game = gameOf(state)
  if not game then return end
  return game:gridHandleInput()
end


-- Battle start seam DRAMATIC_SHAPE wraps (OverworldBattle.install).
--
-- Gen 1's OverworldController:pushBattle is the one place the overworld hands
-- a fight to the stack, and the mod stages its arena THERE -- before the wipe
-- -- so the cast is culled off-screen. Ruby has no controller push: Game3 sets
-- self.battle and calls launchBattleWithEntrance. Gen3Compat bridges that
-- launch onto THIS method so a wrap installed here is in the engine's path,
-- the same way handleInput is. The default body is a no-op: Ruby already owns
-- the fight; the wrap's job is only OverworldBattle.begin.
function OverworldAPI.pushBattle(state, battle)
  return battle
end

return OverworldAPI
