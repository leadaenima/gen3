-- ORAS Models: user-owned Omega Ruby (3DS) asset bridge for Ruby (Game3).
-- Ships no Nintendo pixels. Point extract/extract_oras.py at your dump;
-- cache lands under %APPDATA%/LOVE/pokemon-love2d/oras_extract/ and a
-- sandbox-readable status copy under .local/status.json.
-- Stock Gen3/GBA battle sprites are never overwritten: APPLY TEXTURES is
-- an additive overlay (default off); APPLY 3D MESHES exposes voxel meshes
-- for DramaticShapes without replacing Game3:drawBattlePic.
local function loadLib(mod, name)
  local rel = "lib/" .. name .. ".lua"
  local src = mod:read(rel)
  assert(type(src) == "string" and src ~= "", "missing " .. rel)
  local chunk, err = load(src, "oras_models/" .. rel)
  assert(chunk, err or ("compile failed: " .. rel))
  return chunk()
end

return function(mod)
  local Extract = loadLib(mod, "extract")
  local Apply = loadLib(mod, "apply")
  local Mesh = loadLib(mod, "mesh")
  Mesh._mod = mod

  mod.options:define({
    { key = "enabled", label = "ENABLED", type = "toggle", default = true },
    { key = "apply_textures", label = "APPLY TEXTURES", type = "toggle",
      default = false },
    { key = "apply_meshes", label = "APPLY 3D MESHES", type = "toggle",
      default = true },
    { key = "source_path", label = "ORAS SOURCE", type = "text",
      default = Extract.DEFAULT_SOURCE, maxLen = 260 },
  })

  local status = Extract.readStatus(mod)
  local extractOk = status.ok == true
  local texturesReady = Extract.readyForTextures(status)
  local modelsReady = Extract.readyForModels(status)

  mod.exports.status = function() return status end
  mod.exports.extractOk = function() return extractOk end
  mod.exports.texturesReady = function() return texturesReady end
  mod.exports.modelsReady = function() return modelsReady end
  -- True-3D voxel battle API for DRAMATIC_SHAPE OrasModels adapter.
  mod.exports.meshes = Mesh.exportApi()
  -- Shared bridge for DRAMATIC_SHAPE when mod.find/exports is flaky.
  if package and package.loaded then
    package.loaded["oras_models.meshes"] = mod.exports.meshes
  end
  mod.exports.meshesEnabled = function()
    return mod.options:get("apply_meshes") ~= false
      and mod.options:get("enabled") ~= false
  end
  do
    local idx, err = Mesh.ensureIndex(mod)
    mod.log:info("ORAS voxel index boot hasIndex=%s err=%s nationals~=%s",
      tostring(type(idx) == "table"),
      tostring(err),
      tostring(idx and idx.model_count or idx and idx.national_count or "?"))
  end

  if mod.options:get("enabled") == false then
    Apply.clearTextures(mod.game)
    if Mesh.disableDrawBattlePicHook then Mesh.disableDrawBattlePicHook() end
    mod.log:info("disabled via options -- stock GBA battle pics left pristine")
    return
  end

  local source = tostring(mod.options:get("source_path") or Extract.DEFAULT_SOURCE)
  mod.log:info("source hint: %s (%s)", source, Extract.describeSourceHint(source))
  if not extractOk then
    mod.log:warn("%s", tostring(status.message or "extract not ready"))
    mod.log:info("run: python mods/oras_models/extract/extract_oras.py")
  else
    mod.log:info("extract ok kind=%s textures=%s models=%s index_total=%s",
      tostring(status.kind),
      tostring(status.texture_count or 0),
      tostring(status.model_count or 0),
      tostring(status.texture_index_total or status.texture_count or 0))
  end

  local function tryApply(reason, game)
    if mod.options:get("enabled") == false then
      Apply.clearTextures(game or mod.game)
      return
    end
    if mod.options:get("apply_textures") == false then
      -- Restore stock GBA immediately; do not leave stale hooks/maps armed.
      Apply.clearTextures(game or mod.game)
      mod.log:info("APPLY TEXTURES off (%s) -- stock GBA battle pics restored", reason)
      return
    end
    local live = Extract.readStatus(mod)
    if not Extract.readyForTextures(live) then
      mod.log:info("textures not ready (%s)", reason)
      return
    end
    local n, err, info = Apply.applyTextures(mod, live, {
      Extract = Extract,
      game = game,
    })
    if err then
      mod.log:warn("apply textures (%s): %s", reason, err)
      return
    end
    info = info or {}
    mod.log:info(
      "ORAS apply [%s]: sourceClass=%s national front=%s back=%s mugshots=%s icons=%s gamePathPatches=%s hook=%s mugHook=%s sampleLoad=%s",
      reason,
      tostring(info.sourceClass or "none"),
      tostring(info.nationalFront or 0),
      tostring(info.nationalBack or 0),
      tostring(info.mugshots or 0),
      tostring(info.iconCandidates or 0),
      tostring(n or 0),
      tostring(info.battlePicHook),
      tostring(info.mugshotHook),
      tostring(info.sampleLoadOk or 0))
    if info.note then
      mod.log:info("ORAS apply note: %s", tostring(info.note))
    end
    if info.samplePath then
      mod.log:info("ORAS sample path (%s): %s", tostring(info.sourceClass or "?"), tostring(info.samplePath))
    end
    if (info.sampleLoadOk or 0) < 1 and info.samplePath then
      mod.log:warn("ORAS sample texture failed to load -- battle pics will stay GBA")
    end
    if info.battlePicHookErr then
      mod.log:warn("battlePic hook: %s", tostring(info.battlePicHookErr))
    end
    if info.mugshotHookErr then
      mod.log:info("mugshot hook note: %s", tostring(info.mugshotHookErr))
    end
  end


  local function tryApplyMeshes(reason, game)
    if mod.options:get("enabled") == false then
      if Mesh.disableDrawBattlePicHook then Mesh.disableDrawBattlePicHook() end
      return
    end
    if mod.options:get("apply_meshes") == false then
      if Mesh.disableDrawBattlePicHook then Mesh.disableDrawBattlePicHook() end
      mod.log:info("APPLY 3D MESHES off (%s) -- stock GBA drawBattlePic restored", reason)
      return
    end
    local live = Extract.readStatus(mod)
    if not Extract.readyForModels(live) then
      mod.log:info("meshes not ready (%s) model_count=%s", reason, tostring(live.model_count or 0))
      return
    end
    local n, err, info = Mesh.applyMeshes(mod, live, {
      Extract = Extract,
      game = game,
    })
    if err then
      mod.log:warn("apply meshes (%s): %s", reason, err)
      return
    end
    info = info or {}
    mod.log:info(
      "ORAS meshes [%s]: phase=%s models=%s nationals=%s drawHook=%s bake2d=%s sampleNat=%s probe=%s",
      reason,
      tostring(info.phase or "?"),
      tostring(info.modelCount or 0),
      tostring(info.nationalCount or n or 0),
      tostring(info.drawHook),
      tostring(info.bake2dUi),
      tostring(info.sampleNat or "?"),
      info.probeOk and "ok" or ("FAIL:" .. tostring(info.probeErr or "?")))
    if info.note then
      mod.log:info("ORAS meshes note: %s", tostring(info.note))
    end
    if info.drawHookErr then
      mod.log:warn("drawBattlePic mesh hook: %s", tostring(info.drawHookErr))
    end
    -- Keep exports.meshes bound to the live Mesh module (index refreshed).
    mod.exports.meshes = Mesh.exportApi()
    if package and package.loaded then
      package.loaded["oras_models.meshes"] = mod.exports.meshes
    end
  end

  -- Install hooks as early as the entry chunk runs (Game3 class is loaded).
  if texturesReady then
    tryApply("boot", mod.game)
  end
  if modelsReady then
    tryApplyMeshes("boot", mod.game)
  end

  -- ORAS 3D pipeline stub: registers so the options row / hotkey exist, but
  -- available() stays false until extract reports models (and Game3 grows a
  -- Pipelines.install call -- see README). A present that returns the input
  -- canvas satisfies the schema without drawing anything.
  local function orasAvailable()
    if mod.options:get("enabled") == false then return false end
    return Extract.readyForModels(Extract.readStatus(mod))
  end

  mod.content.render_pipelines:register("oras_3d", {
    label = "ORAS 3D",
    levels = { "OFF", "ON" },
    hotkey = "7",
    priority = 25,
    available = orasAvailable,
    present = function(canvas, _ctx)
      return canvas
    end,
    drawWorld = function(_ctx)
      return nil
    end,
  })

  mod.events:on("game.ready", function(ev)
    local live = Extract.readStatus(mod)
    status = live
    extractOk = live.ok == true
    texturesReady = Extract.readyForTextures(live)
    modelsReady = Extract.readyForModels(live)
    if not extractOk then
      mod.log:info("ORAS extract still pending (%s)", tostring(live.kind))
    elseif modelsReady then
      mod.log:info("ORAS 3D pipeline available")
    else
      mod.log:info("textures indexed; meshes still need RomFS/BCH extract")
    end
    tryApply("game.ready", ev and ev.game)
    tryApplyMeshes("game.ready", ev and ev.game)
  end)
end
