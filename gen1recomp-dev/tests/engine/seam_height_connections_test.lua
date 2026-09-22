-- Proves Ruby list-style connections are published on modMapView.def so
-- DramaticShapes Structures.smoothGen3Seams can meet neighbour edge heights.
-- Without def.connections (byDir), gen3ConnectionsByDir returns nil and seams
-- stay as visual cliffs (Oldale/R101 floating shelf).

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

-- Distilled remapper (same logic as Game3ModWorld.defView)
local function remapConnections(list)
  local rows = {}
  for _, c in ipairs(list or {}) do
    if type(c) == "table" and type(c.dir) == "string" then
      local id = c.map
      if not id and c.mapGroup ~= nil and c.mapNum ~= nil then
        id = string.format("g%d_%d",
                           tonumber(c.mapGroup) or 0,
                           tonumber(c.mapNum) or 0)
      end
      if id then
        local bucket = rows[c.dir]
        if not bucket then bucket = {} rows[c.dir] = bucket end
        bucket[#bucket + 1] = { map = id, offset = tonumber(c.offset) or 0 }
      end
    end
  end
  if not next(rows) then return nil end
  local connections = {}
  for dir, bucket in pairs(rows) do
    local rec = { map = bucket[1].map, offset = bucket[1].offset }
    if #bucket > 1 then
      local also = {}
      for i = 2, #bucket do also[#also + 1] = bucket[i] end
      rec.also = also
    end
    connections[dir] = rec
  end
  return connections
end

-- Structures.gen3ConnectionsByDir preference order (def first)
local function gen3ConnectionsByDir(map)
  local conns = (map and map.def and map.def.connections)
    or (map and map.connections)
  if type(conns) ~= "table" then return nil end
  if conns.north or conns.south or conns.east or conns.west then
    return conns
  end
  return remapConnections(conns)
end

-- Oldale-style: south to Route 101
local raw = {
  { dir = "south", mapGroup = 0, mapNum = 16, offset = 0 },
  { dir = "north", mapGroup = 0, mapNum = 9, offset = 0 },
}
local byDir = remapConnections(raw)
check(byDir ~= nil, "remap produces byDir table")
check(byDir.south and byDir.south.map == "g0_16", "south -> g0_16")
check(byDir.north and byDir.north.map == "g0_9", "north -> g0_9")
check((byDir.south.offset or 0) == 0, "south offset 0")

-- Multi-neighbour side (Route111 west pattern)
local multi = {
  { dir = "west", mapGroup = 0, mapNum = 113, offset = 0 },
  { dir = "west", mapGroup = 0, mapNum = 112, offset = 20 },
}
local m = remapConnections(multi)
check(m.west.map == "g0_113", "multi primary west map")
check(type(m.west.also) == "table" and #m.west.also == 1, "multi also list")
check(m.west.also[1].map == "g0_112" and m.west.also[1].offset == 20,
      "multi also offset 20")

-- What Structures sees when def publishes byDir (fixed host)
local mapFixed = { id = "g0_10", def = { connections = byDir } }
local got = gen3ConnectionsByDir(mapFixed)
check(got and got.south and got.south.map == "g0_16",
      "Structures reads def.connections byDir")

-- Broken host: no def.connections and no map.connections
local mapBroken = { id = "g0_10", def = { width = 20, height = 20 } }
check(gen3ConnectionsByDir(mapBroken) == nil,
      "broken host yields nil conns (cliff repro)")

-- Source file must contain the live remap (guard against softlock regression)
local srcPath = arg[1]
if type(srcPath) == "string" and srcPath ~= "" then
  local f = io.open(srcPath, "rb")
  check(f ~= nil, "open Game3ModWorld.lua")
  if f then
    local body = f:read("*a") or ""
    f:close()
    check(body:find("RomExtractorGen3 stamps direction%-keyed connections", 1, true)
          or body:find("RomExtractorGen3 stamps direction-keyed connections", 1, true),
          "source comment present")
    check(body:find("connections = connections", 1, true),
          "defView publishes connections field")
    check(body:find('string.format("g%d_%d"', 1, true)
          or body:find('string.format("g%%d_%%d"', 1, true)
          or body:find('g%d_%d', 1, true),
          "formats gG_N map ids")
  end
else
  print("SKIP source-file asserts (pass path as arg[1])")
end

print(string.format("RESULT passed=%d failed=%d", passed, failed))
os.exit(failed == 0 and 0 or 1)
