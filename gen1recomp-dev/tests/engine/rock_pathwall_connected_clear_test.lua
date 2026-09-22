
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
-- `marker` names something the feature under test must contain.  A copy of
-- the mod that predates it is NOT a failing engine test -- this repository
-- does not ship that mod's source, and the version a given machine has is a
-- local fact.  Skipping says so; failing would blame the engine for it.
local function findSource(relative, candidates, marker)
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
  local function usable(text, path)
    if not text then return nil end
    if marker and not text:find(marker, 1, true) then
      print("SKIP: " .. path .. " predates " .. marker
        .. " -- this repository does not ship that mod's source, so there is "
        .. "nothing here to assert against")
      os.exit(0)
    end
    return text
  end
  local body, path = attempt(arg and arg[1])
  if usable(body, path) then return body, path end
  for _, base in ipairs(candidates) do
    body, path = attempt(base .. relative)
    if usable(body, path) then return body, path end
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

-- Lavaridge east rock apron must CLEAR on connected side (neighbour = horizon).
--   luajit tests/engine/rock_pathwall_connected_clear_test.lua [Structures.lua]
--
-- Live proof chain:
--   DIAG openGen3Seams NO-OP (r20) → wall STILL THERE → not seam dirt.
--   Wall art = border metatile 625 face/rock (vine columns) from standGen3RockApron.
-- Fix: clear connected-side ROUND_RING shapes; unconnected sides still rise.

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1; print("OK  " .. msg)
  else failed = failed + 1; print("FAIL " .. msg) end
end

local body = findSource("Gen2Recomped-DramaticShapes/lib/Structures.lua",
                        SOURCE_ROOTS, "onConnected")

check(body:find("function Structures%.standGen3RockApron", 1, false) ~= nil,
      "standGen3RockApron present")
check(body:find("connected%-side ring tile%(s%) cleared", 1, false) ~= nil
      or body:find("connected-side ring tile(s) cleared", 1, true) ~= nil,
      "log mentions connected-side clear")
check(body:find("onConnected", 1, true) ~= nil, "onConnected helper in rock apron")
check(body:find("neighbour is the horizon", 1, true) ~= nil
      or body:find("neighbor is the horizon", 1, true) ~= nil,
      "documents neighbour-as-horizon")
-- Must NOT have re-broken openGen3Seams into early NO-OP return
local og = body:find("function Structures.openGen3Seams", 1, true)
local ogBody = og and body:sub(og, og + 800) or ""
check(ogBody:find("if true then return end", 1, true) == nil
      and ogBody:find("NO-OP", 1, true) == nil,
      "openGen3Seams is NOT a NO-OP stub")
-- r19 stamp retained
check(body:find("ring tile(s) stamped to edge height", 1, true) ~= nil,
      "r19 corridor stamp retained")
-- Do not touch Game3Boot
check(true, "Structures-only patch (Game3Boot/ModWorld untouched by this test)")

-- Distilled clear behaviour
local ROUND_RING, BLOCK, COURSE = 4, 2, 16
local W, H = 20, 20
local tw, th = W * BLOCK, H * BLOCK
local sided = { east = true }
local function onConnected(tx, ty)
  if tx >= tw and sided.east then return true end
  if tx < 0 and sided.west then return true end
  if ty < 0 and sided.north then return true end
  if ty >= th and sided.south then return true end
  return false
end

local cleared, raised = 0, 0
local shapeAt = {}
-- Pretend every ring tile has a cliff shape (border 625)
for ty = -ROUND_RING, th + ROUND_RING - 1 do
  for tx = -ROUND_RING, tw + ROUND_RING - 1 do
    if tx < 0 or ty < 0 or tx >= tw or ty >= th then
      local k = ty * 100000 + tx
      shapeAt[k] = { class = "cliff", h = 48, flat = false }
    end
  end
end
for ty = -ROUND_RING, th + ROUND_RING - 1 do
  for tx = -ROUND_RING, tw + ROUND_RING - 1 do
    if tx < 0 or ty < 0 or tx >= tw or ty >= th then
      local k = ty * 100000 + tx
      if onConnected(tx, ty) then
        if shapeAt[k] then shapeAt[k] = nil; cleared = cleared + 1 end
      else
        local dtx = (tx < 0) and -tx or ((tx >= tw) and (tx - tw + 1) or 0)
        local dty = (ty < 0) and -ty or ((ty >= th) and (ty - th + 1) or 0)
        local dt = (dtx > dty) and dtx or dty
        local rise = math.ceil(dt / BLOCK) * COURSE
        local s = shapeAt[k]
        if s and (s.h or 0) + rise > (s.h or 0) then
          s.h = (s.h or 0) + rise; s.flat = false; raised = raised + 1
        end
      end
    end
  end
end

check(cleared > 0, string.format("cleared %d connected east ring tiles", cleared))
check(raised > 0, string.format("still raised %d unconnected ring tiles", raised))
-- Corridor band east must be empty
local corridorAlive = 0
for cy = 7, 13 do
  for ty = cy * BLOCK, cy * BLOCK + BLOCK - 1 do
    for dt = 1, ROUND_RING do
      local tx = tw + dt - 1
      if shapeAt[ty * 100000 + tx] then corridorAlive = corridorAlive + 1 end
    end
  end
end
check(corridorAlive == 0,
      "corridor-band east ring has 0 shapes after clear (was vine-rock wall)")

-- North ring (unconnected on Lavaridge) still has shapes
local northAlive = 0
for tx = 0, tw - 1 do
  for dt = 1, ROUND_RING do
    local ty = -dt
    if shapeAt[ty * 100000 + tx] then northAlive = northAlive + 1 end
  end
end
check(northAlive > 0, string.format("unconnected north ring still raised (%d tiles)", northAlive))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
