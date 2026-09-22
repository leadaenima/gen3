-- Compatibility bridge for Dramatic Shape 1.7.2+ within the 1.7.x line.
--
-- Kanto Dynamic Weather intentionally does not redistribute Dramatic Shape's
-- renderer.  Instead, it reads the installed dependency through the public
-- `mod.exports.lib` namespace, applies a small set of weather integration
-- patches in memory, and compiles those patched modules for this session.
-- If a future Dramatic Shape release changes an integration anchor, this file
-- fails closed with a useful compatibility error instead of silently drawing
-- broken weather.
local W = ...
local mod = W.mod
local ds = W.ds
local baseV = W.baseV

local Bridge = {}

local function normalise(text)
  text = tostring(text or "")
  text = text:gsub("^\239\187\191", "")
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  return text
end

local function linesOf(text)
  text = normalise(text)
  if text:sub(-1) ~= "\n" then text = text .. "\n" end
  local out = {}
  for line in text:gmatch("(.-)\n") do out[#out + 1] = line end
  return out
end

local function blockMatches(lines, at, block)
  if at < 1 or at + #block - 1 > #lines then return false end
  for i = 1, #block do
    if lines[at + i - 1] ~= block[i] then return false end
  end
  return true
end

local function findBlock(lines, block, hint)
  if #block == 0 then return math.max(1, math.min(#lines + 1, hint or 1)) end
  hint = math.max(1, math.min(#lines, hint or 1))
  if blockMatches(lines, hint, block) then return hint end
  -- Prefer a nearby anchor, then widen to the whole file.  This tolerates
  -- line-number drift in compatible 1.7.x releases without accepting a hunk
  -- whose actual surrounding code changed.
  for radius = 1, 180 do
    local a, b = hint - radius, hint + radius
    if blockMatches(lines, a, block) then return a end
    if blockMatches(lines, b, block) then return b end
  end
  for i = 1, #lines - #block + 1 do
    if blockMatches(lines, i, block) then return i end
  end
  return nil
end

local function parsePatch(patch)
  local raw = linesOf(patch)
  local hunks, i = {}, 1
  while i <= #raw do
    local oldStart, oldCount, newStart, newCount = raw[i]:match(
      "^@@ %-(%d+),?(%d*) %+([0-9]+),?(%d*) @@")
    if oldStart then
      local h = {
        oldStart = tonumber(oldStart),
        oldCount = tonumber(oldCount ~= "" and oldCount or "1"),
        newStart = tonumber(newStart),
        newCount = tonumber(newCount ~= "" and newCount or "1"),
        old = {}, new = {},
      }
      i = i + 1
      while i <= #raw and raw[i]:sub(1, 2) ~= "@@" do
        local line = raw[i]
        local prefix = line:sub(1, 1)
        local body = line:sub(2)
        if prefix == " " then
          h.old[#h.old + 1] = body
          h.new[#h.new + 1] = body
        elseif prefix == "-" then
          h.old[#h.old + 1] = body
        elseif prefix == "+" then
          h.new[#h.new + 1] = body
        elseif prefix == "\\" then
          -- "No newline at end of file" marker: no source content.
        else
          break
        end
        i = i + 1
      end
      hunks[#hunks + 1] = h
    else
      i = i + 1
    end
  end
  return hunks
end

local function applyPatch(source, patch, label)
  local lines = linesOf(source)
  local delta = 0
  for n, h in ipairs(parsePatch(patch)) do
    local hint = h.oldStart + delta
    local at = findBlock(lines, h.old, hint)
    if not at then
      -- A compatible dependency may already contain this exact integration
      -- block (for example a locally patched Dramatic Shape build). Treat an
      -- already-applied hunk as success instead of rejecting the whole mod.
      local already = findBlock(lines, h.new, hint)
      if already then
        at = false
      elseif label == "Voxel3D" and n == 10 then
        -- Dramatic Shape 1.7.2 changed only the commentary/viewport block
        -- surrounding the fog uniforms. The weather edit itself needs only
        -- the five-line fog send block, so use semantic anchors rather than
        -- demanding the neighbouring comments byte-for-byte.
        local fogAt, cullAt
        for i, line in ipairs(lines) do
          if not fogAt and line:match("^%s*local%s+fog%s*=%s*Voxel3D%.fog%s*$") then
            fogAt = i
          elseif fogAt and line:match("^%s*local%s+cull%s*=%s*Voxel3D%.cull%s*$") then
            cullAt = i
            break
          end
        end
        if fogAt and cullAt then
          local joined = table.concat(lines, "\n")
          if not joined:find("local fogStart = fog and %(fog%.start or 0%) or 0", 1, false) then
            local inject = {
              "  local fogStart = fog and (fog.start or 0) or 0",
              "  if fog and fog.startFromFocus and Voxel3D.eye and Voxel3D.focus then",
              "    local dx = Voxel3D.eye[1] - Voxel3D.focus[1]",
              "    local dy = Voxel3D.eye[2] - Voxel3D.focus[2]",
              "    local dz = Voxel3D.eye[3] - Voxel3D.focus[3]",
              "    local focusDistance = math.sqrt(dx * dx + dy * dy + dz * dz)",
              "    fogStart = math.max(0, focusDistance + fog.startFromFocus)",
              "  end",
            }
            for j = #inject, 1, -1 do table.insert(lines, fogAt + 1, inject[j]) end
            cullAt = cullAt + #inject
          end
          for i = fogAt, cullAt do
            if lines[i] and lines[i]:find("fog.start or 0", 1, true) then
              lines[i] = lines[i]:gsub("fog%.start%s+or%s+0", "fogStart", 1)
              break
            end
          end
          local joined2 = table.concat(lines, "\n")
          if not joined2:find('"atmosCloud"', 1, true) then
            local inject = {
              "  local ca = Voxel3D.cinematicAtmos",
              "  pcall(sh.send, sh, \"atmosCloud\", ca and ca.cloudShadow or 0)",
              "  pcall(sh.send, sh, \"atmosTime\", ca and ca.time or 0)",
              "  pcall(sh.send, sh, \"atmosWind\", ca and ca.wind or { 0, 0 })",
              "  pcall(sh.send, sh, \"puddleMask\", { 0, 0, 0, 0 })",
              "  pcall(sh.send, sh, \"puddleMaskState\", { 0, 0 })",
            }
            for j = #inject, 1, -1 do table.insert(lines, cullAt, inject[j]) end
          end
          at = false
        end
      end
      if at == nil then
        error((
          "KANTO_DYNAMIC_WEATHER: Dramatic Shape %s is not source-compatible " ..
          "with the 1.7.2+ bridge (failed %s hunk %d). Disable this add-on or " ..
          "install a supported Dramatic Shape 1.7.x build (1.7.2 or newer)."
        ):format(tostring(ds.version or "unknown"), label, n), 0)
      end
    end
    if at == false then
      -- already applied or handled by a semantic compatibility fallback
    else
      local replacement = {}
      for j = 1, at - 1 do replacement[#replacement + 1] = lines[j] end
      for _, line in ipairs(h.new) do replacement[#replacement + 1] = line end
      for j = at + #h.old, #lines do replacement[#replacement + 1] = lines[j] end
      lines = replacement
      delta = delta + #h.new - #h.old
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

local patched = {}
local proxy

local function readDependency(rel)
  local owner = baseV and baseV.mod
  local source = owner and owner.read and owner:read(rel)
  if not source then
    error("KANTO_DYNAMIC_WEATHER: Dramatic Shape is missing " .. rel, 0)
  end
  return source
end

local function compilePatched(name)
  if patched[name] ~= nil then return patched[name] end
  local source = readDependency("lib/" .. name .. ".lua")
  local patch = mod:read("compat/patches/1.7/" .. name .. ".patch")
  if not patch then
    error("KANTO_DYNAMIC_WEATHER: compatibility patch missing for " .. name, 0)
  end
  local merged = applyPatch(source, patch, name)
  local chunk, err = load(merged,
    "@" .. tostring(mod.path) .. "/compat/runtime/" .. name .. ".lua")
  if not chunk then
    error("KANTO_DYNAMIC_WEATHER: patched " .. name .. " did not compile: " ..
          tostring(err), 0)
  end
  -- Sentinel prevents accidental recursive loads from looping forever.
  patched[name] = false
  local value = chunk(proxy)
  if value == nil then
    error("KANTO_DYNAMIC_WEATHER: patched " .. name .. " returned nil", 0)
  end
  patched[name] = value
  return value
end

proxy = {
  mod = baseV.mod,
  path = baseV.path,
  data = baseV.data,
}

function proxy.require(name)
  if name == "Voxel3D" or name == "VoxelScene" or name == "Sky" then
    local hit = patched[name]
    if hit == false then
      error("KANTO_DYNAMIC_WEATHER: circular compatibility load at " .. name, 0)
    end
    return hit or compilePatched(name)
  end
  if name == "CinematicAtmos" or name == "DistantWorld"
      or name == "HorizonApron" or name == "WeatherSetting" then
    return W.require(name)
  end
  return baseV.require(name)
end

function Bridge.requirePatched(name)
  if name ~= "Sky" and name ~= "Voxel3D" and name ~= "VoxelScene" then
    error("KANTO_DYNAMIC_WEATHER: not a patched Dramatic Shape module: " .. tostring(name), 0)
  end
  local hit = patched[name]
  if hit == false then
    error("KANTO_DYNAMIC_WEATHER: circular compatibility load at " .. name, 0)
  end
  return hit or compilePatched(name)
end

function Bridge.load()
  -- Load in a stable order so VoxelScene and Voxel3D resolve the same patched
  -- Sky table and the same companion atmosphere module.
  local sky = compilePatched("Sky")
  local voxel3D = compilePatched("Voxel3D")
  local voxelScene = compilePatched("VoxelScene")
  return {
    Sky = sky,
    Voxel3D = voxel3D,
    VoxelScene = voxelScene,
  }
end

return Bridge
