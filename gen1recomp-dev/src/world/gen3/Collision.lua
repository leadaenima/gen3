-- COLLISION, AS A WALK-REPLACING MOD ASKS FOR IT.
--
-- src.world.Collision is a Gen 1 engine module and is listed as one, so a Gen
-- 3 mod requiring it is logged as a mistake and then handed Gen 1's file
-- anyway. For most of that module that is exactly the hazard the facade
-- exists to stop: its canMove reads Gen 1 blocks, a Gen 1 tile-pair table and
-- Gen 1 warp rules, none of which describe a Gen 3 map.
--
-- ONE function on it is generation-agnostic, and it is the only one the mod
-- actually calls: `occupied` asks whether any entity in a list stands on a
-- cell. It reads nothing but the list it is handed -- cellX, cellY, the cell
-- an actor is stepping into, and whether it is walk-through -- so the same
-- answer is right on either generation. That one is backed; the rest are
-- named and refuse, because a plausible wrong answer about what blocks is
-- worse than no answer.

local Collision = {}

local Logger = require("src.core.Logger")

-- Gen 1's own implementation, restated rather than delegated: requiring the
-- Gen 1 module to reach it would pull the whole thing -- and its Gen 1 tile
-- tables -- into a Gen 3 game, which is the import this adapter exists to
-- avoid.
--
-- `targetX/targetY` is the cell an actor is MOVING INTO. A walker reserves
-- its destination, so two bodies cannot converge on one cell; an actor that
-- publishes neither simply never reserves, which is the honest answer for a
-- Gen 3 NPC standing still.
function Collision.occupied(entities, cx, cy, ignore)
  if type(entities) ~= "table" then return nil end
  for i = 1, #entities do
    local e = entities[i]
    if e and e ~= ignore and not e.passable then
      if (e.cellX == cx and e.cellY == cy)
          or (e.targetX == cx and e.targetY == cy) then
        return e
      end
    end
  end
  return nil
end

local UNIMPLEMENTED = {
  canMove =
    "Gen 1's verdict reads a block table, a Gen 1 tile-pair list and Gen 1 "
    .. "warp rules; Ruby answers the same question through the map view's "
    .. "isWalkableCell / isWaterCell / elevationAt",
  load =
    "there is no Gen 3 tile-pair table to load; Game3 carries its collision "
    .. "in the metatile word and its behaviour byte",
  blocked =
    "same reason as canMove -- the Gen 1 shape of the answer does not "
    .. "describe a Gen 3 cell",
}

local warned = {}
for name, why in pairs(UNIMPLEMENTED) do
  Collision[name] = function()
    if not warned[name] then
      warned[name] = true
      Logger.info("collision api: %s has no Gen 3 backing: %s", name, why)
    end
    return nil
  end
end

Collision.UNIMPLEMENTED = UNIMPLEMENTED

return Collision
