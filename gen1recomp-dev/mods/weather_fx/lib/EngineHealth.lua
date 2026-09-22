local V = ...
local SafeCall = V.require("SafeCall")

-- Compact runtime-health summary for diagnostics and release field reports.
local H={}
function H.sample(runtimeStats)
  runtimeStats=runtimeStats or {}
  local errors=0; local worst=0; local worstId=nil; local calls=0; local skipped=0
  for id,p in pairs(runtimeStats.passes or {}) do
    errors=errors+(tonumber(p.errors) or 0); calls=calls+(tonumber(p.calls) or 0); skipped=skipped+(tonumber(p.skipped) or 0)
    if (tonumber(p.max) or 0)>worst then worst=tonumber(p.max) or 0; worstId=id end
  end
  local perf=runtimeStats.performance or {}
  local safe = SafeCall and SafeCall.stats and SafeCall.stats() or {}
  local safeErrors = tonumber(safe.failures) or 0
  return {healthy=(errors==0 and safeErrors==0),errors=errors,safeCallErrors=safeErrors,safeCallLastScope=safe.lastScope,safeCallLastError=safe.lastError,worstPass=worstId,worstPassSeconds=worst,calls=calls,skipped=skipped,workScale=tonumber(perf.scale) or 1,memoryKB=tonumber(perf.memoryKB) or 0}
end
return H
