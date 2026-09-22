-- VoxelAtmosBridge
--
-- Routes optional 3D overworld weather for Weather FX.
-- Target hosts: DRAMATIC_SHAPE, DRAMALESS_SHAPE, Gen2Recomped-DramaticShapes,
-- potato_voxel, POTATO_VOXEL, and STADIUM2_OVERWORLD_MODELS (Gen2).
-- The current Dramatic Shape 1.9.x fork uses the same exports.lib/Voxel3D
-- contract as the multi-host atmosphere bridge, so it is handled in-memory
-- rather than through the old 1.7 patch path.
--
-- Weather FX remains authority for weather state. This only upgrades
-- overworld drawing and tells Draw.lua when to skip 2D rain/fog.

local V = ...

local Bridge = {
  _impl = nil,
  _reason = "not-initialised",
}

local function loadDramaless()
  local ok, mod = pcall(V.require, "DramalessAtmos")
  if not ok or not mod then
    return nil, "DramalessAtmos-load-failed: " .. tostring(mod)
  end
  local iok, err = pcall(mod.install)
  if not iok then
    return nil, "DramalessAtmos-install-error: " .. tostring(err)
  end
  if not mod.active or not mod.active() then
    return nil, (mod.reason and mod.reason()) or "dramaless-inactive"
  end
  return mod, nil
end

function Bridge.init()
  if Bridge._impl and Bridge._impl.active and Bridge._impl.active() then
    return true
  end
  local impl, err = loadDramaless()
  if impl then
    Bridge._impl = impl
    Bridge._reason = impl.reason and impl.reason() or "voxel-host-3d"
    return true
  end
  Bridge._reason = tostring(err or "no-3d-host")
  Bridge._impl = nil
  return false
end

function Bridge.active()
  return Bridge._impl and Bridge._impl.active and Bridge._impl.active() or false
end

-- True only when the active voxel host is also the selected Weather FX
-- presentation. This is intentionally different from active(): a host may be
-- installed while WX PRESENT=2D. First-person remains 3D because the
-- implementation's wants3d() follows the same renderer authority.
function Bridge.presentation3d()
  if not Bridge.active() then return false end
  if Bridge._impl and Bridge._impl.wants3d then
    local ok, yes = pcall(Bridge._impl.wants3d)
    return ok and yes and true or false
  end
  return true
end

function Bridge.reason()
  if Bridge._impl and Bridge._impl.reason then
    return Bridge._impl.reason()
  end
  return Bridge._reason
end

function Bridge.handlesPrecipitation()
  return Bridge._impl and Bridge._impl.handlesPrecipitation
      and Bridge._impl.handlesPrecipitation() or false
end

-- Snow is a SEPARATE question from handlesPrecipitation, which is rain-family
-- only by design. Atmos.handlesSnow() has existed since 4.28.69 and was never
-- exposed here, so Draw could not ask it and the 2D snow sheet drew on top of
-- working 3D snow -- which is exactly what makes world snow look like a flat
-- overlay. Fails closed: no impl, no suppression, 2D snow still shows.
function Bridge.handlesSnow()
  return Bridge._impl and Bridge._impl.handlesSnow
      and Bridge._impl.handlesSnow() or false
end

-- Per-family precipitation ownership. Kind ids match Particles/WorldPrecip:
--   1 hail, 2 sand, 3 leaves/debris, 4 ash.
-- Fails closed so a missing/failed 3D family leaves its 2D safety layer alive.
function Bridge.handlesGrains(kind)
  return Bridge._impl and Bridge._impl.handlesGrains
      and Bridge._impl.handlesGrains(kind) or false
end

function Bridge.handlesAllPrecipitation()
  return Bridge._impl and Bridge._impl.handlesAllPrecipitation
      and Bridge._impl.handlesAllPrecipitation() or false
end

function Bridge.handlesLightning()
  return Bridge._impl and Bridge._impl.handlesLightning
      and Bridge._impl.handlesLightning() or false
end

function Bridge.handlesFog()
  return Bridge._impl and Bridge._impl.handlesFog
      and Bridge._impl.handlesFog() or false
end

function Bridge.handlesClouds()
  return false
end

function Bridge.syncFromWeatherFx(state, settings)
  if not Bridge.active() then return end
  if Bridge._impl.syncFromWeatherFx then
    pcall(Bridge._impl.syncFromWeatherFx, state, settings)
  end
end

function Bridge.update(dt)
  if not Bridge.active() then
    Bridge.init()
  end
  if Bridge._impl and Bridge._impl.update then
    pcall(Bridge._impl.update, dt)
  end
end

function Bridge.invalidate()
  if Bridge._impl and Bridge._impl.invalidate then
    pcall(Bridge._impl.invalidate)
  end
end

return Bridge
