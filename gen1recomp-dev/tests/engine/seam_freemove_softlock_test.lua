
-- RESOLVING A THIRD-PARTY MOD'S SOURCE, which is not part of this repository.
--
-- This suite reads DRAMATIC_SHAPE's own Lua to check a behaviour lives where
-- it says it does.  The mod ships here as a zip and is unpacked wherever the
-- player keeps it, so the path is a local fact, not a repository one -- and
-- the original hardcoded one (/workspace/..., desktop-sync-...) existed only
-- on the machine that wrote it.  Asserting on io.open there turned "the mod
-- is not unpacked" into a failing engine test.
--
-- So: take arg[1] if given, try the places it is usually found, and SKIP with
-- a stated reason if it is nowhere -- a skip is the honest answer when the
-- thing under test is not present.
local function findSource(relative, candidates)
  local tried = {}
  local function attempt(path)
    if not path then return nil end
    tried[#tried + 1] = path
    local fh = io.open(path, "r")
    if not fh then return nil end
    local body = fh:read("*a")
    fh:close()
    return body, path
  end
  local body, path = attempt(arg and arg[1])
  if body then return body, path end
  for _, base in ipairs(candidates) do
    body, path = attempt(base .. relative)
    if body then return body, path end
  end
  print("SKIP: " .. relative .. " not found (looked in "
    .. table.concat(tried, ", ") .. ")")
  print("      pass the path as the first argument to run this suite")
  os.exit(0)
end

local SOURCE_ROOTS = {
  "tmp/ds_ruby_probe/",
  "mods/",
  "../Gen2Recomped-main/mods/",
}

-- Proves the post-map-seam free-walk softlock and its fix.
--
-- Repro shape (voxel 1ST/3RD FreeMove on Ruby):
--   1. checkEdgeExit → tryWalk connection sets walkCooldown > 0 and clears
--      freeWalkPx (enterMap).
--   2. modOverworldFields builds player.moving = true from walkCooldown.
--   3. View is memoized; walkCooldown is NOT (was not) in the cache signature.
--   4. Lerp ends: walkCooldown = 0, cam/player unchanged → cache HIT.
--   5. FreeMove.tick sees stale p.moving == true → drop() every frame →
--      cannot move.
--
-- Fix: PLAYER_READS.moving / inputLocked / surfing are live off the game.

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("OK  " .. msg)
  else
    failed = failed + 1
    print("FAIL " .. msg)
  end
end

-- ------- Distilled writeThroughPlayer + PLAYER_READS (mirrors the patch)
local METATILE_PX = 16

local function makeProxy(game, actorSnapshot)
  local PLAYER_READS = {
    facing = function(g) return g.facing end,
    cellX = function(g) return g.playerX end,
    cellY = function(g) return g.playerY end,
    px = function(g)
      return g.freeWalkPx or (g.playerX or 0) * METATILE_PX
    end,
    py = function(g)
      return g.freeWalkPy or (g.playerY or 0) * METATILE_PX
    end,
    surfing = function(g) return g.surfing == true end,
    moving = function(g) return (g.walkCooldown or 0) > 0 end,
    inputLocked = function(g)
      if type(g.displayGateOK) == "function" then
        return not g:displayGateOK()
      end
      return false
    end,
  }
  local store = {}
  return setmetatable({}, {
    __index = function(_, key)
      local read = PLAYER_READS[key]
      if read then return read(game) end
      if store[key] ~= nil then return store[key] end
      return actorSnapshot[key]
    end,
    __newindex = function(_, key, value)
      store[key] = value
    end,
  })
end

-- Snapshot as the OLD host built it (moving baked from walkCooldown at build)
local function buildSnapshot(game)
  return {
    id = "player",
    cellX = game.playerX,
    cellY = game.playerY,
    facing = game.facing or "south",
    surfing = game.surfing == true,
    moving = (game.walkCooldown or 0) > 0,          -- BAKED
    inputLocked = false,                          -- BAKED
  }
end

-- FreeMove's gate (from upstream FreeMove.tick)
local function freemoveWouldWalk(p)
  if p.moving or p.inputLocked then
    return false, "dropped"
  end
  return true, "tick"
end

-- ------- Scenario: connection lerp then settle with cache hit
local game = {
  playerX = 0, playerY = 10, facing = "west",
  freeWalkPx = nil, freeWalkPy = nil,
  walkCooldown = 0.4,  -- mid-lerp after tryWalk connection
  surfing = false,
  phase = "play",
  map = { id = "MAUVILLE" },
  field = nil,
  displayGateOK = function(self)
    return self.phase == "play" and self.map ~= nil and self.field == nil
  end,
}

-- View built during lerp (as cache would hold)
local snap = buildSnapshot(game)
check(snap.moving == true, "snapshot during lerp has moving=true")

local proxy = makeProxy(game, snap)

-- OLD BUG: reading actor.moving (snapshot) while walkCooldown already 0
game.walkCooldown = 0  -- lerp finished; cache still holds snap
local staleRead = snap.moving
local okStale, whyStale = freemoveWouldWalk({ moving = staleRead, inputLocked = snap.inputLocked })
check(okStale == false and whyStale == "dropped",
  "regression: stale snapshot moving=true softlocks FreeMove after seam")

-- FIX: live PLAYER_READS.moving
check(proxy.moving == false, "live moving is false once walkCooldown hits 0")
check(proxy.inputLocked == false, "live inputLocked false while displayGateOK")
local okLive, whyLive = freemoveWouldWalk(proxy)
check(okLive == true and whyLive == "tick",
  "fix: live moving lets FreeMove.tick run after seam lerp")

-- During lerp, live moving still true (FreeMove correctly stands aside)
game.walkCooldown = 0.2
check(proxy.moving == true, "live moving true while walkCooldown > 0")
local okMid = freemoveWouldWalk(proxy)
check(okMid == false, "during lerp FreeMove still stands aside (moving)")

-- Surfing live (r13 class)
game.walkCooldown = 0
game.surfing = true
check(proxy.surfing == true, "live surfing reflects game.surfing")
check(snap.surfing == false, "snapshot surfing stayed false (proves live path)")

-- inputLocked when a field menu is up
game.field = { kind = "menu" }
check(proxy.inputLocked == true, "live inputLocked true when field menu up")
game.field = nil
check(proxy.inputLocked == false, "live inputLocked clears when field gone")

-- freeWalkPx cleared on enterMap: px falls back to cell origin
game.freeWalkPx, game.freeWalkPy = nil, nil
game.playerX, game.playerY = 0, 10
check(proxy.px == 0 and proxy.py == 160,
  "after freeWalkPx clear, px/py re-adopt cell origin (0,10)*16")

-- Cache signature includes walk-in-progress bit
local function sigOf(g)
  return table.concat({
    tostring(g.map), "0",
    tostring(g.playerX), tostring(g.playerY),
    tostring(g.facing), tostring(g.camX), tostring(g.camY),
    tostring(g.field), tostring(g.surfing), tostring(g.phase),
    "npcs",
    tostring((g.walkCooldown or 0) > 0),
  }, "|")
end
game.walkCooldown = 0.5
local s1 = sigOf(game)
game.walkCooldown = 0
local s2 = sigOf(game)
check(s1 ~= s2, "cache sig changes when walkCooldown crosses zero")

-- Source assertions on the synced Game3ModWorld.lua
-- ours, at its own path -- there is nothing to sync from
local src = assert(io.open("src/core/Game3ModWorld.lua")):read("*a")
check(src:find("moving = function%(g%) return %(g%.walkCooldown or 0%) > 0 end") ~= nil
  or src:find("moving = function(g) return (g.walkCooldown or 0) > 0 end") ~= nil,
  "Game3ModWorld has live PLAYER_READS.moving")
check(src:find("inputLocked = function") ~= nil,
  "Game3ModWorld has live PLAYER_READS.inputLocked")
check(src:find("surfing = function%(g%) return g%.surfing == true end") ~= nil
  or src:find("surfing = function(g) return g.surfing == true end") ~= nil,
  "Game3ModWorld has live PLAYER_READS.surfing")
check(src:find("walkCooldown or 0) > 0") ~= nil,
  "cache signature includes walk-in-progress bit")
check(src:find("post%-seam softlock") ~= nil
  or src:find("post-seam softlock") ~= nil,
  "comment documents the softlock")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
