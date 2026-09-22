local V = ...

-- Central protected-call authority.
--
-- Older Weather FX modules used many independent protected calls so optional
-- host APIs could fail open. That kept the game alive, but it also meant a
-- host-specific fault could be swallowed with no common diagnostic trail.
-- SafeCall preserves the exact boolean/result contract while recording every
-- failure in one bounded health table and rate-limiting warnings by scope.
local S = {}

local stats = {
  calls = 0,
  failures = 0,
  lastScope = nil,
  lastError = nil,
  scopes = {},
}

local function scopeStat(scope)
  scope = tostring(scope or "unknown")
  local hit = stats.scopes[scope]
  if not hit then
    hit = {calls=0, failures=0, lastError=nil, logged=0}
    stats.scopes[scope] = hit
  end
  return hit, scope
end

local function warn(scope, st, err)
  -- Log the first failure and then only powers of two. This keeps a broken
  -- per-frame optional host callback from flooding the log while still making
  -- persistent faults visible (1, 2, 4, 8, ...).
  local n = st.failures
  local x = n
  while x > 1 and x % 2 == 0 do x = x / 2 end
  if n < 1 or x ~= 1 then return end
  st.logged = st.logged + 1
  local mod = V and V.mod
  if not (mod and mod.log and type(mod.log.warn) == "function") then return end
  pcall(function()
    mod.log:warn("Weather FX protected call failed [%s] #%d: %s", scope, n, tostring(err))
  end)
end

function S.call(scope, fn, ...)
  local st, name = scopeStat(scope)
  stats.calls = stats.calls + 1
  st.calls = st.calls + 1
  if type(fn) ~= "function" then
    local err = "attempted protected call on non-function: " .. type(fn)
    stats.failures = stats.failures + 1
    st.failures = st.failures + 1
    st.lastError = err
    stats.lastScope, stats.lastError = name, err
    warn(name, st, err)
    return false, err
  end

  -- Keep this allocation-free on success. Protected calls sit on rendering and
  -- host-compatibility seams, so wrapping every result in a temporary table
  -- would turn robustness into avoidable GC pressure on low-end devices.
  local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
  if not ok then
    local err = a
    stats.failures = stats.failures + 1
    st.failures = st.failures + 1
    st.lastError = tostring(err)
    stats.lastScope, stats.lastError = name, tostring(err)
    warn(name, st, err)
  end
  return ok, a, b, c, d, e, f, g, h, i, j, k, l
end

function S.bind(scope)
  scope = tostring(scope or "unknown")
  return function(fn, ...)
    return S.call(scope, fn, ...)
  end
end

function S.stats()
  return stats
end

function S.reset()
  stats.calls = 0
  stats.failures = 0
  stats.lastScope = nil
  stats.lastError = nil
  stats.scopes = {}
end

return S
