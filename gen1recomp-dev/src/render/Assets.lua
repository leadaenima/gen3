-- Central image cache plus the mod-visible asset search path.  Every
-- renderer that used to call love.graphics.newImage(path) straight goes
-- through Assets.image, so an enabled mod shadows a generated asset with
-- its own file without editing a single record, and one flush() drops
-- every downstream cache for dev-mode hot reload.
--
-- No loader installed means resolve() is the identity.  The NX Blue/Yellow
-- versioned-cache fallback lives in src/core/NxAssetOverlay.lua (installed
-- once at boot on NX only), not here, so this module stays platform-free.

local Assets = {}

-- resolved path -> love Image
local cache = {}
-- asked-for path -> resolved path.
--
-- resolve() walks the enabled mods and asks the filesystem whether each one
-- overrides this asset. That is a getInfo per mod PER CALL, and it runs
-- before the image cache is consulted, so even a cache hit paid it -- every
-- texture, every frame. Profiling the voxel diorama put this function at the
-- top of the samples with the whole frame in draw, and the answer cannot
-- change without the mod set changing, which invalidate() and installLoader()
-- already announce.
local resolvedPaths = {}
-- resolved path -> function building that Image, for art the engine derives
-- at runtime rather than loading from disk (see Assets.provide)
local providers = {}
-- downstream caches that must empty when the search path changes
local invalidators = {}
-- optional GPU release hooks for session end (never run on hot reload flush)
local releasers = {}

-- The loader bridge: overrideOrder() yields mods highest-priority-first
-- and derivedPath(rel) yields an existing save/mod-derived/<id>/<rel>.
-- nil until the loader installs one.
Assets.loader = nil

local GENERATED = "assets/generated/"

local function exists(path)
  local fs = love and love.filesystem
  if not (fs and fs.getInfo) then return false end
  return fs.getInfo(path) ~= nil
end
Assets.exists = exists

-- Mod overrides win; on NX, Blue/Yellow then use the prefixed save-dir file;
-- otherwise the caller's unprefixed path (Red / mounted overlay).
function Assets.resolve(path)
  if type(path) ~= "string" then return path end
  if path:sub(1, #GENERATED) ~= GENERATED then return path end
  local hit = resolvedPaths[path]
  if hit ~= nil then return hit end

  local rel = path:sub(#GENERATED + 1)
  local loader = Assets.loader
  if loader then
    for _, mod in ipairs(loader:overrideOrder()) do
      local candidate = mod.path .. "/overrides/" .. rel
      if exists(candidate) then
        resolvedPaths[path] = candidate
        return candidate
      end
    end
    local derived = loader:derivedPath(rel)
    if derived then
      resolvedPaths[path] = derived
      return derived
    end
  end

  -- NX Blue/Yellow: no rewrite here -- NxAssetOverlay (installed once at
  -- boot on NX only) covers every loader globally, so this module stays
  -- the mod-override choke point it always was.
  resolvedPaths[path] = path
  return path
end

-- DERIVED ART, ASKED FOR BY PATH.
--
-- Some art is not a file: it is built from a file, and the consumer only
-- knows how to ask for a path. A renderer in a MOD is the case that forced
-- this -- it takes `def.image` and loads it through this module, so the only
-- way to hand it a sheet the engine rearranged is to answer for a path that
-- has no file behind it.
--
-- Registered rather than inserted, because `invalidate` empties the cache and
-- the next reader would otherwise reach love.graphics.newImage with a name
-- PhysFS has never heard of. The builder is kept and rerun instead.
function Assets.provide(path, build)
  if type(path) ~= "string" or type(build) ~= "function" then return false end
  providers[path] = build
  return true
end

function Assets.provides(path)
  return providers[Assets.resolve(path)] ~= nil
end

function Assets.image(path)
  local resolved = Assets.resolve(path)
  local image = cache[resolved]
  if not image then
    local build = providers[resolved]
    if build then image = build() else image = love.graphics.newImage(resolved) end
    cache[resolved] = image
  end
  return image
end

-- pixel-level reads (tile-shift variants, the spinner strip blit) resolve
-- the same way but stay uncached: the caller keeps the derived product
function Assets.imageData(path)
  return love.image.newImageData(Assets.resolve(path))
end

-- Register a cache invalidator, or { invalidate = fn, release = fn } when a
-- module caches LOVE Images/Canvases and can eagerly free them at session end.
-- release is optional and is NOT run on flush/invalidate (HotReload safe).
-- MapLoader is the canonical split-hook example: invalidateAll clears tables
-- without GPU release; releaseAll evicts every resident map renderer.
function Assets.register(hooks)
  if type(hooks) == "function" then
    invalidators[#invalidators + 1] = hooks
    return
  end
  if hooks.invalidate then invalidators[#invalidators + 1] = hooks.invalidate end
  if hooks.release then releasers[#releasers + 1] = hooks.release end
end

-- hot reload's single entry point (20-developer-tooling): drop the central
-- cache and fan out to every registered downstream one.  A cache whose
-- invalidator throws must not strand the ones behind it in the list.
function Assets.invalidate()
  cache = {}
  resolvedPaths = {}
  for _, fn in ipairs(invalidators) do pcall(fn) end
end

Assets.flush = Assets.invalidate

-- In-process return-to-launcher / editor close: release central Images and
-- run release hooks only.  Does not call invalidate hooks (MapLoader must
-- keep invalidateAll separate from releaseAll).
function Assets.releaseSession()
  resolvedPaths = {}
  for _, img in pairs(cache) do
    if img and img.release then pcall(img.release, img) end
  end
  cache = {}
  for _, fn in ipairs(releasers) do pcall(fn) end
end

-- Loader:load hands over the live mod set once the merge is done.  Load
-- order is priority ascending, so the search walks it backwards: the mod
-- that wins the record merge wins the asset lookup too.
function Assets.installLoader(loader)
  if not loader then
    Assets.loader = nil
    Assets.invalidate()
    return
  end
  local bridge = {}
  function bridge:overrideOrder()
    local order = {}
    local loaded = loader.loaded or {}
    for i = #loaded, 1, -1 do
      order[#order + 1] = { id = loaded[i].manifest.id, path = loaded[i].path }
    end
    return order
  end
  function bridge:derivedPath(rel)
    for _, mod in ipairs(self:overrideOrder()) do
      local candidate = "save/mod-derived/" .. mod.id .. "/" .. rel
      if exists(candidate) then return candidate end
    end
    return nil
  end
  Assets.loader = bridge
  Assets.invalidate()
end

return Assets
