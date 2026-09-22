local V = ...
-- Portable state snapshot. The host save layer may serialize this table; Weather
-- FX does not assume one particular save-game API.
local P={version=1}
function P.snapshot()
  local W=V.require('WorldClimate'); local S=V.require('EnvironmentSurface')
  return {version=P.version,worldClimate=W.snapshot(256),surface=S.snapshot(1024)}
end
function P.restore(data)
  if type(data)~='table' then return false end
  local ok=true
  local W=V.require('WorldClimate'); if data.worldClimate and W.restore then ok=W.restore(data.worldClimate) and ok end
  local S=V.require('EnvironmentSurface'); if data.surface and S.restore then ok=S.restore(data.surface) and ok end
  return ok
end
return P
