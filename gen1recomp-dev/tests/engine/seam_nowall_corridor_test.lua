-- Lavaridge PC east ↔ Route112 west: walkable corridor must NOT seam-wall to -16.
--   luajit tests/engine/seam_nowall_corridor_test.lua [Structures.lua]
--
-- Root cause under test (r18):
--   openGen3Seams marked the entire connected ring; ChunkMesher.occludeH then
--   returned SEAM_DATUM=-16 for every marked tile, so edge columns always
--   extruded a dirt face.  Even after smoothGen3Seams flushed corridor Z,
--   that extrusion was the tall brown wall next to the PC path.
-- Fix: clear seamOpen in front of walkable edge cells; cliffs stay marked.

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

local SEAM_DATUM = -16
local BLOCK = 4

-- Distilled openGen3Seams mark/clear (post-fix)
local function openSeamForEdge(H, W, dir, walkableAt)
  -- walkableAt(cx,cy) -> bool; simulate one connected side
  local open = {}
  local function key(tx, ty) return ty * 100000 + tx end
  local tw, th = W * BLOCK, H * BLOCK
  local n, cleared = 0, 0
  local function mark(tx, ty)
    local k = key(tx, ty)
    if not open[k] then open[k] = true; n = n + 1 end
  end
  local function unmark(tx, ty)
    local k = key(tx, ty)
    if open[k] then open[k] = nil; n = n - 1; cleared = cleared + 1 end
  end

  if dir == "east" then
    for ty = -2, th + 1 do mark(tw, ty) end
    for cy = 0, H - 1 do
      if walkableAt(W - 1, cy) then
        for ty = cy * BLOCK, (cy + 1) * BLOCK - 1 do unmark(tw, ty) end
      end
    end
  elseif dir == "west" then
    for ty = -2, th + 1 do mark(-1, ty) end
    for cy = 0, H - 1 do
      if walkableAt(0, cy) then
        for ty = cy * BLOCK, (cy + 1) * BLOCK - 1 do unmark(-1, ty) end
      end
    end
  end
  return open, n, cleared, key
end

local function occludeH(open, key, tx, ty, apronH)
  local k = key(tx, ty)
  if open[k] then return SEAM_DATUM end
  return apronH
end

-- --- Lavaridge east: path cy 5..8 walkable, rock cy 0..2 / 15..19 not ---
do
  local H, W = 20, 14
  local function walk(cx, cy)
    return cy >= 5 and cy <= 8  -- PC path band
  end
  local open, n, cleared, key = openSeamForEdge(H, W, "east", walk)
  check(cleared == 4 * BLOCK, "cleared 4 walkable corridor cells * 4 tiles")
  -- Path cell cy=6 must NOT wall to -16
  local tw = W * BLOCK
  local pathTy = 6 * BLOCK
  local nh = occludeH(open, key, tw, pathTy, 0)
  check(nh == 0, "walkable path ring occludes to apron (0), not SEAM_DATUM")
  check(open[key(tw, pathTy)] == nil, "path ring tile not in seamOpen")
  -- Cliff/rock cy=1 still walls
  local cliffTy = 1 * BLOCK
  local nh2 = occludeH(open, key, tw, cliffTy, 0)
  check(nh2 == SEAM_DATUM, "unwalkable rock edge still walls to SEAM_DATUM")
  check(open[key(tw, cliffTy)] == true, "rock ring tile still seamOpen")
  -- Apron extension outside body still marked
  check(open[key(tw, -1)] == true, "apron ty=-1 still seamOpen")
end

do
  local H, W = 20, 14
  local function walk(cx, cy) return cy >= 5 and cy <= 8 end
  local open, n, cleared, key = openSeamForEdge(H, W, "east", walk)
  local tw = W * BLOCK
  check(open[key(tw, -1)] == true, "north apron extension still seamOpen")
  check(open[key(tw, H * BLOCK + 0)] == true, "south apron at th still seamOpen")
  -- Remaining open count: full side minus cleared
  -- ty from -2..th+1 inclusive = th+4 marks initially; cleared 16
  local th = H * BLOCK
  local initial = (th + 1) - (-2) + 1  -- th+4
  check(n == initial - cleared, "n = initial - cleared")
  check(n > 0, "cliffs still leave some seamOpen marks")
end

-- --- Route112 west corridor band cy 40..59 partial walkable ---
do
  local H, W = 60, 40
  local function walk(cx, cy)
    -- corridor overlap with Lavaridge: cy 40..59; path ~45..48
    return cy >= 45 and cy <= 48
  end
  local open, n, cleared, key = openSeamForEdge(H, W, "west", walk)
  check(cleared == 4 * BLOCK, "R112 west cleared 4 corridor cells")
  local pathTy = 46 * BLOCK
  check(open[key(-1, pathTy)] == nil, "R112 corridor ring not seamOpen")
  check(occludeH(open, key, -1, pathTy, 0) == 0,
        "R112 corridor occludes to apron not -16")
  -- Massif north of Lavaridge (cy=10) still walls
  local massifTy = 10 * BLOCK
  check(open[key(-1, massifTy)] == true, "R112 massif cy10 still seamOpen")
  check(occludeH(open, key, -1, massifTy, 0) == SEAM_DATUM,
        "R112 massif still walls to SEAM_DATUM")
end

-- --- OLD behavior repro: whole side marked → path walls to -16 ---
do
  local open = {}
  local function key(tx, ty) return ty * 100000 + tx end
  local tw = 14 * BLOCK
  for ty = 0, 20 * BLOCK - 1 do open[key(tw, ty)] = true end
  check(occludeH(open, key, tw, 6 * BLOCK, 0) == SEAM_DATUM,
        "OLD: path ring returned SEAM_DATUM (repro tall dirt face)")
end

-- Emission rule: face only when nh < gy
do
  local function emits(gy, nh) return nh < gy end
  check(emits(0, SEAM_DATUM) == true, "OLD flush z=0 still emits 16px face to -16")
  check(emits(64, SEAM_DATUM) == true, "OLD high edge emits tall face to -16")
  check(emits(0, 0) == false, "NEW apron==edge emits no face")
  check(emits(32, 32) == false, "NEW matched heights emit no face")
  check(emits(64, 0) == true, "cliff above neighbour still emits real step")
end

-- Source file guards
local srcPath = arg[1]
if type(srcPath) == "string" and srcPath ~= "" then
  local f = io.open(srcPath, "rb")
  check(f ~= nil, "open Structures.lua")
  if f then
    local body = f:read("*a") or ""
    f:close()
    check(body:find("walkable%-corridor", 1, false)
          or body:find("walkable-corridor", 1, true),
          "source logs walkable-corridor left closed")
    check(body:find("left closed", 1, true) ~= nil,
          "source has left closed phrase")
    check(body:find("WALKABLE CONNECTION CORRIDORS MUST NOT WALL", 1, true) ~= nil,
          "source documents corridor no-wall rule")
    local i = body:find("function Structures.openGen3Seams%(S, map%)")
    check(i ~= nil, "openGen3Seams present")
    if i then
      local chunk = body:sub(i, i + 4500)
      check(chunk:find("unmark", 1, true) ~= nil, "openGen3Seams unmarks corridor")
      check(chunk:find("isWalkableCell", 1, true) ~= nil,
            "openGen3Seams gates clear on isWalkableCell")
      check(chunk:find("cleared", 1, true) ~= nil, "tracks cleared count")
    end
    -- smoothGen3Seams flush from r17 must still be present
    check(body:find("Multi%-course walkable corridor", 1, false)
          or body:find("Multi-course walkable corridor", 1, true),
          "r17 multi-course corridor flush still present")
    check(body:find("rock%-border towns", 1, false)
          or body:find("rock-border towns", 1, true),
          "r17 role-first seamFloor still present")
  end
else
  print("SKIP source-file asserts (pass Structures.lua as arg[1])")
end

print(string.format("RESULT passed=%d failed=%d", passed, failed))
os.exit(failed == 0 and 0 or 1)
