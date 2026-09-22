-- Lavaridge PC east ↔ Route112 west: walkable corridor must emit NO dirt face.
--   luajit tests/engine/seam_killwall_corridor_test.lua [Structures.lua]
--
-- Root cause under test (r19):
--   r18 cleared seamOpen on walkable edge cells, but rock-border maps leave
--   the CONNECTED ring without an apron (ringWall carve-only). occludeH then
--   returned heightAt(ring)=0, so edge gy=48 (elev 3 * COURSE) still emitted
--   a 48px dirt face — the wall Raymond still sees after r18.
-- Fix: stamp cleared ring tiles to edge height so nh==gy → faceH=0.

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
local COURSE = 16
local BLOCK = 2

local function key(tx, ty) return ty * 100000 + tx end

-- Distilled openGen3Seams mark/clear/stamp
local function openSeam(H, W, dir, walkableAt, edgeElevAt, mode)
  -- mode: "r18" | "r19"
  local open, shapeH = {}, {}
  local n, cleared, stamped = 0, 0, 0
  local function mark(tx, ty)
    local k = key(tx, ty)
    if not open[k] then open[k] = true; n = n + 1 end
  end
  local function unmark(tx, ty)
    local k = key(tx, ty)
    if open[k] then open[k] = nil; n = n - 1; cleared = cleared + 1; return true end
    return false
  end
  local function stamp(tx, ty, h)
    shapeH[key(tx, ty)] = h
    stamped = stamped + 1
  end
  local tw, th = W * BLOCK, H * BLOCK
  local RING = 12
  if dir == "east" then
    for ty = -RING, th + RING - 1 do mark(tw, ty) end
    for cy = 0, H - 1 do
      if walkableAt(W - 1, cy) then
        local h = (edgeElevAt(W - 1, cy) or 0) * COURSE
        for ty = cy * BLOCK, (cy + 1) * BLOCK - 1 do
          unmark(tw, ty)
          if mode == "r19" then stamp(tw, ty, h) end
        end
      end
    end
  elseif dir == "west" then
    for ty = -RING, th + RING - 1 do mark(-1, ty) end
    for cy = 0, H - 1 do
      if walkableAt(0, cy) then
        local h = (edgeElevAt(0, cy) or 0) * COURSE
        for ty = cy * BLOCK, (cy + 1) * BLOCK - 1 do
          unmark(-1, ty)
          if mode == "r19" then stamp(-1, ty, h) end
        end
      end
    end
  end
  return open, shapeH, n, cleared, stamped
end

local function occludeH(open, shapeH, tx, ty)
  local k = key(tx, ty)
  if open[k] then return SEAM_DATUM end
  return shapeH[k] or 0
end

local function faceH(gy, nh)
  return (nh < gy) and (gy - nh) or 0
end

-- --- Measured Lavaridge 20x20 east: walkable cy 7..13 elev 3 ---
do
  local H, W = 20, 14  -- width irrelevant for east ring; use 20 to match real
  W = 20
  local function walk(cx, cy) return cy >= 7 and cy <= 13 end
  local function elev(cx, cy) return 3 end

  -- OLD r18: clear only → nh=0 → 48px face
  local open18, sh18 = openSeam(H, W, "east", walk, elev, "r18")
  local tw = W * BLOCK
  local pathTy = 8 * BLOCK
  local gy = 3 * COURSE
  local nh18 = occludeH(open18, sh18, tw, pathTy)
  check(open18[key(tw, pathTy)] == nil, "r18: path ring not seamOpen")
  check(nh18 == 0, "r18 OLD: occludeH returns 0 (missing apron)")
  check(faceH(gy, nh18) == 48, "r18 OLD: emits 48px dirt face (repro Raymond wall)")

  -- NEW r19: clear + stamp → nh=48 → face 0
  local open19, sh19, n, cleared, stamped = openSeam(H, W, "east", walk, elev, "r19")
  local nh19 = occludeH(open19, sh19, tw, pathTy)
  check(open19[key(tw, pathTy)] == nil, "r19: path ring not seamOpen")
  check(nh19 == gy, "r19: occludeH returns edgeH=48")
  check(faceH(gy, nh19) == 0, "r19: emits NO dirt face (flush)")
  check(stamped == 7 * BLOCK, "r19 stamped 7 corridor cells * 2 tiles")
  check(cleared == 7 * BLOCK, "r19 cleared 7 corridor cells * 2 tiles")

  -- Massif cy=1 still walls to datum
  local cliffTy = 1 * BLOCK
  check(open19[key(tw, cliffTy)] == true, "r19: rock edge cy1 still seamOpen")
  check(occludeH(open19, sh19, tw, cliffTy) == SEAM_DATUM,
        "r19: rock edge still walls to SEAM_DATUM")
end

-- --- Route112 west corridor cy 47..53 ---
do
  local H, W = 60, 40
  local function walk(cx, cy) return cy >= 47 and cy <= 53 end
  local function elev(cx, cy) return 3 end
  local open19, sh19 = openSeam(H, W, "west", walk, elev, "r19")
  local pathTy = 50 * BLOCK
  local gy = 48
  check(open19[key(-1, pathTy)] == nil, "R112 corridor ring not seamOpen")
  check(occludeH(open19, sh19, -1, pathTy) == gy, "R112 corridor nh=edgeH")
  check(faceH(gy, gy) == 0, "R112 corridor no dirt face")
  check(open19[key(-1, 10 * BLOCK)] == true, "R112 massif cy10 still seamOpen")
end

-- Source file guards
local srcPath = arg[1]
if type(srcPath) == "string" and srcPath ~= "" then
  local f = io.open(srcPath, "rb")
  check(f ~= nil, "open Structures.lua")
  if f then
    local body = f:read("*a") or ""
    f:close()
    check(body:find("corridorSeam", 1, true) ~= nil,
          "Structures has corridorSeam stamp mark")
    check(body:find("stamped to edge height", 1, true) ~= nil,
          "Structures logs ring stamp count")
    check(body:find("r19:", 1, true) ~= nil,
          "Structures documents r19 root cause")
    -- Must still clear walkable (r18 behavior kept)
    check(body:find("walkable%-corridor") ~= nil
          or body:find("walkable-corridor", 1, true) ~= nil,
          "Structures still reports walkable-corridor left closed")
    -- Must NOT remove massif walls
    check(body:find("seamOpen", 1, true) ~= nil, "Structures still sets seamOpen")
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
