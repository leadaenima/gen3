-- Lavaridge east ↔ Route112 west: walkable path corridor must flush.
--   luajit tests/engine/seam_flush_corridor_test.lua [Structures.lua]
--
-- Root cause under test:
--   (A) seamFloor used to require shape class ground/grass/slope — rock-border
--       towns stamp path edges as cliff class → skipped → openGen3Seams wall.
--   (B) gap > COURSE skipped even for walkable floor — R112 west 0..208 vs
--       Lavaridge path leaves a multi-course dirt face you walk through.

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

local COURSE = 16
local HALF = COURSE / 2

-- Distilled seamFloor (post-fix)
local function seamFloor(cell)
  if not cell.walkable then return false end
  if cell.role ~= nil then
    local rr = cell.role
    return rr == "floor" or rr == "grass" or rr == "stair"
  end
  local c = cell.class
  return c == "ground" or c == "grass" or c == "slope"
end

-- Distilled mid picker (post-fix)
local function pickMid(mine, theirs)
  local gap = mine - theirs
  if gap < 0 then gap = -gap end
  if gap <= COURSE then
    local mid = (mine + theirs) / 2
    return math.floor(mid / HALF + 0.5) * HALF, "half"
  end
  return (mine < theirs) and mine or theirs, "min"
end

-- --- A: class cliff + role floor is corridor ---
check(seamFloor({ walkable = true, role = "floor", class = "cliff" }) == true,
      "walkable floor+cliff class is seamFloor (Lavaridge path)")
check(seamFloor({ walkable = true, role = "grass", class = "rock" }) == true,
      "walkable grass+rock class is seamFloor")
check(seamFloor({ walkable = true, role = "cliff", class = "ground" }) == false,
      "cliff role is NOT seamFloor (massif stays cliff)")
check(seamFloor({ walkable = false, role = "floor", class = "ground" }) == false,
      "unwalkable floor is not seamFloor")
check(seamFloor({ walkable = true, role = "stair", class = "slope" }) == true,
      "stair role is seamFloor")

-- Old filter would have rejected cliff class:
local function oldSeamFloor(cell)
  if not cell.walkable then return false end
  if cell.role ~= nil and cell.role ~= "floor" and cell.role ~= "grass" then
    return false
  end
  local c = cell.class
  return c == "ground" or c == "grass" or c == "slope"
end
check(oldSeamFloor({ walkable = true, role = "floor", class = "cliff" }) == false,
      "OLD filter rejected floor+cliff (repro)")
check(seamFloor({ walkable = true, role = "floor", class = "cliff" }) == true,
      "NEW filter accepts floor+cliff")

-- --- B: within COURSE halfway (Emerald parity) ---
do
  local mid, how = pickMid(0, 16)
  check(mid == 8 and how == "half", "0↔16 → mid 8 halfway")
end
do
  local mid, how = pickMid(32, 16)
  check(mid == 24 and how == "half", "32↔16 → mid 24 halfway")
end

-- --- B: multi-course walkable → lower edge ---
do
  local mid, how = pickMid(0, 48)
  check(mid == 0 and how == "min", "0↔48 corridor → min 0 (not mid 24)")
end
do
  local mid, how = pickMid(64, 16)
  check(mid == 16 and how == "min", "64↔16 corridor → min 16")
end
do
  local mid, how = pickMid(208, 0)
  check(mid == 0 and how == "min", "208↔0 (mispaired high) → drop to 0")
end

-- Simulate both sides converging from raw (order-independent)
do
  local lav_raw, r112_raw = 32, 0  -- Lavaridge path up, R112 corridor low
  local lav_mid = select(1, pickMid(lav_raw, r112_raw))
  local r112_mid = select(1, pickMid(r112_raw, lav_raw))
  check(lav_mid == r112_mid and lav_mid == 0,
        "both sides converge on same lower edge from raw")
end

-- --- Offset alignment Lavaridge 20h ↔ Route112 60h, off -40 / +40 ---
-- Lavaridge east cy → R112 west[cy+40]; PC area cy≈5..8 → R112 cy 45..48
do
  local lavH, r112H = 20, 60
  local lavOff, r112Off = -40, 40
  local function theirsIndex(i, off) return i - off end
  check(theirsIndex(6, lavOff) == 46, "Lavaridge cy6 → R112 west[46]")
  check(theirsIndex(46, r112Off) == 6, "R112 cy46 → Lavaridge east[6]")
  check(theirsIndex(0, lavOff) == 40, "Lavaridge cy0 → R112 west[40] (corridor band)")
  check(theirsIndex(19, lavOff) == 59, "Lavaridge cy19 → R112 west[59]")
  -- Northern massif of R112 (cy<40) has no Lavaridge partner
  check(theirsIndex(10, r112Off) == -30, "R112 cy10 has no Lavaridge cell (nil)")
end

-- Rock role with large gap must NOT be treated as corridor mid-move target
-- (openGen3Seams still walls these)
check(seamFloor({ walkable = false, role = "cliff", class = "cliff" }) == false,
      "unwalkable cliff massif not corridor")

-- Source file guards
local srcPath = arg[1]
if type(srcPath) == "string" and srcPath ~= "" then
  local f = io.open(srcPath, "rb")
  check(f ~= nil, "open Structures.lua")
  if f then
    local body = f:read("*a") or ""
    f:close()
    check(body:find("Multi%-course walkable corridor", 1, false)
          or body:find("Multi-course walkable corridor", 1, true),
          "source has multi-course corridor branch")
    check(body:find("rock%-border towns", 1, false)
          or body:find("rock-border towns", 1, true),
          "source documents rock-border seamFloor fix")
    check(body:find('rr == "stair"', 1, true)
          or body:find("rr == \"stair\"", 1, true),
          "seamFloor accepts stair role")
    -- Ensure we no longer gate ONLY on class after role
    local i = body:find("local function seamFloor%(cx, cy%)")
    check(i ~= nil, "seamFloor function present")
    if i then
      local chunk = body:sub(math.max(1, i - 700), i + 900)
      check(chunk:find('rr == "floor"', 1, true) ~= nil, "role-first seamFloor")
      check(chunk:find("rock-border towns", 1, true) ~= nil,
            "seamFloor comment mentions rock-border")
    end
  end
else
  print("SKIP source-file asserts (pass Structures.lua as arg[1])")
end

print(string.format("RESULT passed=%d failed=%d", passed, failed))
os.exit(failed == 0 and 0 or 1)
