-- Gen 3 Collision adapter for Gen 1-shaped mods (free_fly and friends).
--
-- Exactly one of Gen 1's two verbs carries over, and the split is the point:
-- `occupied` reads ONLY the entity list it is handed, so the same answer is
-- right on either generation, while `canMove` reads Red's block tables -- a
-- structure Ruby does not have at all, because Game3 answers passability
-- through the map view (isWalkableCell / isWaterCell / elevationAt).
local Collision = {}

-- Returns the ACTOR that occupies the cell, not a boolean.
--
-- Handing back the body rather than `true` is what lets a caller say something
-- useful about the refusal -- which NPC is in the way, whether it is the one
-- it was trying to talk to -- and a table is still truthy, so a caller that
-- only wanted a yes/no is unaffected.
--
-- A cell is occupied by an actor STANDING on it or one STEPPING INTO it.  The
-- second half is the reservation, and without it two bodies mid-step both see
-- the cell as free and converge on it.
--
-- `ignore` is the asker: a body never blocks itself, or it could never leave
-- the cell it is standing on.  `passable` marks an actor you walk through.
function Collision.occupied(entities, cellX, cellY, ignore)
  if type(entities) ~= "table" then return nil end
  for i = 1, #entities do
    local e = entities[i]
    if type(e) == "table" and e ~= ignore and not e.passable then
      if e.cellX == cellX and e.cellY == cellY then return e end
      -- the reservation: where it will be at the end of this step
      if e.targetX == cellX and e.targetY == cellY then return e end
    end
  end
  return nil
end

-- REFUSES rather than guessing, and that is deliberate.
--
-- Answering `true` was tried and is worse than answering nothing: it tells a
-- Gen 1-shaped caller that every tile on the map is walkable, which reads as a
-- working answer right up until a mod walks the player through a wall.  nil is
-- distinguishable from both verdicts, so a caller can tell it was refused and
-- go through the map view, which is where Ruby keeps the truth.
--
-- src/mods/Gen3Compat.lua publishes this as `warned` for the same reason.
function Collision.canMove()
  return nil
end

return Collision
