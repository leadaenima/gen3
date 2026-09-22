-- LuaJIT hard-limit gate for the real WorldPrecip closure graph.
-- Upstream LuaJIT 2.1 rejects any Lua function with more than 60 upvalues.
-- Lua 5.3 can compile a wider closure, so running this under texlua/lua5.3 is
-- useful: debug.getupvalue lets us count what LuaJIT would reject BEFORE ship.
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local V = { require=function(name) error("unused " .. tostring(name), 0) end }
local W = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)

local LIMIT = 60
local seen, rows = {}, {}
local function walk(label, fn)
  if seen[fn] then return end
  seen[fn] = true
  local n = 0
  while true do
    local name, value = debug.getupvalue(fn, n + 1)
    if not name then break end
    n = n + 1
    if type(value) == "function" then
      walk(label .. "->" .. name, value)
    end
  end
  rows[#rows + 1] = { label=label, count=n }
end
for name, value in pairs(W) do
  if type(value) == "function" then walk("WP." .. tostring(name), value) end
end

table.sort(rows, function(a,b) return a.count > b.count end)
local failures = 0
for _, row in ipairs(rows) do
  if row.count > LIMIT then
    failures = failures + 1
    io.write(string.format("FAIL: %s has %d upvalues (LuaJIT limit %d)\n", row.label, row.count, LIMIT))
  end
end
local updateCount = 0
for _, row in ipairs(rows) do if row.label == "WP.update" then updateCount = row.count end end
io.write(string.format("luajit_upvalue_probe: WP.update=%d, max=%d, functions=%d\n",
  updateCount, rows[1] and rows[1].count or 0, #rows))
if failures > 0 then os.exit(1) end
