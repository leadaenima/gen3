-- One-shot: bake missing player/rival OW forms into the mounted ruby cache.
--   POKEPORT_VERSION=ruby POKEPORT_GAME=ruby POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/extract_avatar_sprites.lua love .
local NEED = { 3, 93, 101, 102, 103, 104, 106, 107, 108, 109, 137, 138 }

return function(game)
  local Rom = require("src.import.RomExtractorGen3")
  local ImageWriter = require("src.import.ImageWriter")
  local CacheFs = require("src.import.CacheFs")

  local romPath = "misc/Pokemon - Ruby Version (USA).gba"
  local f = assert(io.open(romPath, "rb"))
  local data = f:read("*a")
  f:close()

  local graphics = assert(Rom.findObjectEventGraphics(data))
  local pals = assert(Rom.findObjectEventPalettes(data, graphics))
  local sprites = game.data and game.data.sprites or {}
  sprites.byId = sprites.byId or {}

  local patched = {}
  for i = 1, #NEED do
    local gid = NEED[i]
    local info = graphics.byId[gid]
    if not info then
      print("[extract]", gid, "NO INFO")
    else
      local palOff = pals.byTag[info.paletteTag]
        or pals.byTag[0x1103]
        or pals.byTag[0x1100]
      local poses = Rom.parseOwAnims(data, info.animsOff)
      local needF = Rom.maxAnimFrame(poses) + 1
      local have = info.frameCount or 1
      local frameCount = have
      if needF > 1 then
        frameCount = math.min(have, math.max(needF, 1))
      end
      local image, err = Rom.renderOwSheet(data, info, palOff, frameCount)
      if not image then
        print("[extract]", gid, "RENDER FAIL", err)
      else
        local rel = Rom.spritePath(gid)
        ImageWriter.save(image, rel)
        local entry = {
          id = gid,
          path = rel,
          width = info.width,
          height = info.height,
          frameCount = frameCount,
          face = poses.face,
          walk = poses.walk,
        }
        sprites.byId[gid] = entry
        patched[#patched + 1] = entry
        print("[extract]", gid, rel, info.width, info.height, "fc", frameCount)
      end
    end
  end

  -- Patch data/generated/sprites.lua on disk (byId entries).
  local src = CacheFs.read("data/generated/sprites.lua")
  if type(src) ~= "string" or #src < 100 then
    print("[extract] could not read sprites.lua")
    love.event.quit()
    return
  end
  local insertAt = src:find("byId = {", 1, true)
  if not insertAt then
    print("[extract] byId missing")
    love.event.quit()
    return
  end
  insertAt = insertAt + #"byId = {"
  local chunks = {}
  for i = 1, #patched do
    local e = patched[i]
    local needle = "[" .. e.id .. "] ="
    if not src:find(needle, 1, true) then
      local face, walk = {}, {}
      for _, d in ipairs({ "south", "north", "west", "east" }) do
        local p = e.face[d]
        face[#face + 1] = string.format(
          "      %s = { frame = %d, flip = %s },",
          d, p.frame, tostring(p.flip and true or false))
        local w = e.walk[d] or {}
        local frames = {}
        for j = 1, #w do
          frames[#frames + 1] = string.format(
            "{ frame = %d, duration = %d, flip = %s }",
            w[j].frame, w[j].duration or 0,
            tostring(w[j].flip and true or false))
        end
        walk[#walk + 1] = string.format(
          "      %s = {\n        %s\n      },",
          d, table.concat(frames, ",\n        "))
      end
      chunks[#chunks + 1] = string.format([[
    [%d] = {
      id = %d,
      path = %q,
      width = %d,
      height = %d,
      frameCount = %d,
      face = {
%s
      },
      walk = {
%s
      },
    },]], e.id, e.id, e.path, e.width, e.height, e.frameCount,
        table.concat(face, "\n"), table.concat(walk, "\n"))
    end
  end
  if #chunks > 0 then
    local out = src:sub(1, insertAt) .. "\n" .. table.concat(chunks, "\n")
      .. src:sub(insertAt + 1)
    CacheFs.write("data/generated/sprites.lua", out)
    print("[extract] patched sprites.lua with", #chunks, "entries")
  else
    print("[extract] sprites.lua already had all entries; PNGs refreshed")
  end

  love.event.quit()
end
