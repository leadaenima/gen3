-- Engine-owned contract for generated ROM caches.
--
-- A cache is playable only when its versioned marker matches the ROM and every
-- required output for that version exists. Extraction writers may differ by
-- platform, but they must publish through this contract so partial staging
-- cannot look ready to the runtime.
local GameVersion = require("src.core.GameVersion")

local CacheContract = {}

CacheContract.FORMAT = "rom-cache-v10:"
CacheContract.VERSION_FORMAT = {
  crystal = "rom-cache-v10-crystal2:",
  ruby = "rom-cache-v10-ruby101:",
}
CacheContract.MARKER_PATH = "rom-cache.complete"

CacheContract.REQUIRED_FILES = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/text.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
  "assets/generated/trade/game_boy.png",
}

CacheContract.VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png",
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
  },
}

CacheContract.VERSION_REQUIRED_FILES_OVERRIDE = {
  gold = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    -- The engine's label-keyed strings are separate from Gen 2 script text.
    -- Caches made before RomExtractorGen2:extractText must be rebuilt so
    -- src/core/RomText.lua does not silently fall back to built-in wording.
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/tilesets.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/pokemon_logo.png",
    "assets/generated/title/title_screen.png",
    "assets/generated/title/hooh.png",
    "assets/generated/title/hooh_5.png",
    "assets/generated/title/clouds.png",
    "assets/generated/title/copyright_splash.png",
    "data/generated/oak_speech.lua",
    "assets/generated/intro/oak.png",
    "assets/generated/intro/cal.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/front/marill.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    -- engine/events/fishing_gfx.asm:23
    "assets/generated/emotes/fishing.png",
  },
  crystal = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/encounters.lua",
    "data/generated/tilesets.lua",
    "data/generated/landmarks.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "data/generated/oak_speech.lua",
    "data/generated/title.lua",
    "data/generated/intro.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/crystal_logo.png",
    "assets/generated/title/crystal_wordmark.png",
    "assets/generated/title/crystal_suicune.png",
    "assets/generated/title/copyright_splash.png",
    "assets/generated/splash/ditto.png",
    "assets/generated/intro/chris.png",
    "assets/generated/intro/kris.png",
    "assets/generated/intro/suicune_run_sprites.png",
    "assets/generated/intro/unowns_tiles.png",
    "assets/generated/intro/oak.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/sprites/kris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/wooper.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    "assets/generated/trainer_card/card_f.png",
    "data/generated/mobile_gfx.lua",
    "assets/generated/battle/player_back_female.png",
    "assets/generated/battle/trainers/kris.png",
    "assets/generated/battle/trainers/chris.png",
    -- ../pokecrystal/engine/events/fishing_gfx.asm:38-42
    "assets/generated/emotes/fishing.png",
  },
}
CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.silver =
  CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.gold
CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.ruby = {
  "data/generated/constants.lua",
  "data/generated/pokemon.lua",
  "data/generated/header.lua",
  "data/generated/maps.lua",
  "data/generated/tilesets.lua",
  "assets/generated/tilesets/pair_0_bottom.png",
  "assets/generated/tilesets/pair_0_top.png",
  "assets/generated/tilesets/pair_0_doors.png",
  "data/generated/sprites.lua",
  "assets/generated/sprites/ow_0.png",
  "assets/generated/sprites/ow_2.png",
  "data/generated/encounters.lua",
  "data/generated/moves.lua",
  "data/generated/trainers.lua",
  "data/generated/items.lua",
  "assets/generated/battle/front/280.png",
  "assets/generated/battle/back/280.png",
  "assets/generated/battle/front_shiny/280.png",
  "assets/generated/battle/back_shiny/280.png",
  "assets/generated/battle/gold_stars.png",
  -- Previously baked into assets/generated (excluded from game.love) or read
  -- from the decomp tree at runtime; both vanish on device. Required here so
  -- a cache without them is rebuilt rather than validating half-empty.
  "assets/generated/trainer_card/ruby_front_0.png",
  "assets/generated/trainer_card/ruby_badges.png",
  "assets/generated/battle_anims/135.png",
  "assets/generated/battle_anims/115.png",
  "assets/generated/battle/ruby_balls/poke.png",
  "assets/generated/battle/ruby_balls/poke_closed.png",
  "assets/generated/battle/ruby_balls/trade_ball.png",
  "assets/generated/battle/transitions/mugshot_bg_steven_240.png",
  "assets/generated/battle/transitions/steven_mugshot.png",
  -- Pokenav art: the screens were flat rectangles and nothing was extracted.
  "assets/generated/pokenav/outline.png",
  "assets/generated/pokenav/background.png",
  "assets/generated/pokenav/screen.png",
  "assets/generated/pokenav/pokeball.png",
  -- The screen headers are composed from two OBJ anim frames at extraction
  -- (renderHeader); requiring them keeps a pre-ruby89 cache from surviving
  -- with the old scrambled single-blit versions.
  -- the POKeMON NAVIGATOR title bar (BG1) and the root menu message box
  -- (BG0); without them the menu opens with a bare field at top and bottom
  -- the bag pocket name is cart art, not text
  "assets/generated/bag/bag_labels.png",
  "assets/generated/bag/bag_dots.png",
  -- menu_helpers.c scroll indicators: the bag and every scrolling list
  -- fall back to typed carets without them
  "assets/generated/ui/scroll_arrows.png",
  "assets/generated/pokenav/banner.png",
  "assets/generated/pokenav/misc_layer.png",
  "assets/generated/pokenav/condition_screen.png",
  -- the pokenav data pack: the radius curve plus all three help tables.
  -- v97 wrote a four-entry search table (TOUGH and CANCEL missing) and a
  -- condition screen with its interlace flood-filled away, so a v97 cache
  -- must not be reused.
  "data/generated/pokenav.lua",
  -- data/generated/tilesets.lua gained primaryKey / secondaryKey in v100 --
  -- the cartridge's own names for a pair's two halves. A v99 cache has the
  -- art but not the names, and a renderer mod keys its per-tileset shape
  -- profiles by exactly those strings, so without them every lookup misses
  -- and every cell falls to the wall profile.
  "data/generated/tilesets.lua",
  -- the CONDITION menu and the condition search. The search needs both
  -- sheets: sub_80F1BC8 repoints its last three rows to sprite palette tag
  -- 1 (condition7), so one sheet renders SMART, TOUGH and CANCEL wrong.
  "assets/generated/pokenav/condition_menu.png",
  "assets/generated/pokenav/condition_search.png",
  "assets/generated/pokenav/condition_search_alt.png",
  "assets/generated/pokenav/ribbon_icons.png",
  "assets/generated/pokenav/menu_options_alt.png",
  "assets/generated/pokenav/main_menu_header.png",
  "assets/generated/pokenav/condition_header.png",
  "assets/generated/pokenav/ribbons_header.png",
  "assets/generated/pokenav/trainer_eyes_header.png",
  "assets/generated/pokenav/map_header.png",
  "assets/generated/pokenav/map_header_zoom.png",
  "data/generated/font.lua",
  "assets/generated/fonts/font.png",
  "data/generated/title.lua",
  "data/generated/ui.lua",
  "assets/generated/ui/window_frames.png",
  -- the message and move bars are drawn now too, not just actions
  -- the naming screen reads these straight out of the cart now, so a cache
  -- without them would leave the keyboard chrome blank
  "assets/generated/naming/back_button.png",
  "assets/generated/naming/ok_button.png",
  "assets/generated/naming/change_keyboard_button.png",
  "assets/generated/naming/cursor.png",
  -- ...and the BG layers and box icons, which were the last art baked from
  -- pokeruby in the tree. A cache from before they were extracted has the
  -- sprites but no screen behind them, so it must be rebuilt.
  "assets/generated/naming/bg_stripes.png",
  "assets/generated/naming/keyboard_upper.png",
  "assets/generated/naming/keyboard_lower.png",
  "assets/generated/naming/keyboard_others.png",
  "assets/generated/naming/pc_icon_0.png",
  "assets/generated/naming/pc_icon_1.png",
  "assets/generated/ui/battle_message.png",
  "assets/generated/ui/battle_moves.png",
  -- the HP bar needs the hpbar-palette element sheet, the EXP bar the
  -- window-palette one; both are blitted per tile now
  "assets/generated/ui/healthbox_hp.png",
  "assets/generated/ui/battle_actions.png",
  "assets/generated/ui/healthbox_player.png",
  "assets/generated/ui/battle_status_pills.png",
  "data/generated/audio.lua",
  "assets/generated/audio/mp2k.bin",
  "data/generated/menus.lua",
  "data/generated/decorations.lua",
  "assets/generated/icons/mon_icons.png",
  "assets/generated/party/tiles.png",
  "assets/generated/party/background.png",
    "assets/generated/party/status.png",
    "assets/generated/party/font_small.png",
    "assets/generated/party/ordertext.png",
    "assets/generated/party/holditems.png",
    "assets/generated/cable_car/mountain.png",
    "assets/generated/egg_hatch/egg.png",
    "assets/generated/trade/cable.png",
    "assets/generated/rotating_gates/3.png",
    "assets/generated/sprites/ow_62.png",
    "assets/generated/sprites/ow_191.png",
    "assets/generated/sprites/ow_141.png",
    -- Mauville PC VAR_0 -> Bard..Giddy (special SetMauvilleOldManObjEventGfx)
    "assets/generated/sprites/ow_69.png",
    "assets/generated/sprites/ow_70.png",
    "assets/generated/sprites/ow_71.png",
    "assets/generated/sprites/ow_72.png",
    "assets/generated/sprites/ow_73.png",
    "assets/generated/field/pokeball_glow.png",
    "assets/generated/weather/rain.png",
    "assets/generated/weather/sand.png",
    "assets/generated/pokenav/region_map.png",
    "assets/generated/starter/bg.png",
    "assets/generated/title/logo_shine.png",
    "assets/generated/title/title_logo.png",
    "assets/generated/title/title_lava_bubbles.png",
    "assets/generated/birch/bg.png",
    "assets/generated/birch/portrait.png",
    "assets/generated/intro/intro2_may.png",
    "assets/generated/pokedex/entry.png",
    "assets/generated/pokedex/footprints.png",
    "assets/generated/pc/header.png",
    "assets/generated/pc/wallpapers/forest.png",
}

function CacheContract.requiredFilesFor(version)
  local override = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE[version]
  if override then return override, true end
  return CacheContract.REQUIRED_FILES, false
end

function CacheContract.formatFor(version)
  return CacheContract.VERSION_FORMAT[version] or CacheContract.FORMAT
end

function CacheContract.markerFor(version, sha1)
  return CacheContract.formatFor(version)
    .. (sha1 or GameVersion.info(version).sha1)
end

function CacheContract.markerMatches(version, marker)
  for _, revision in ipairs(GameVersion.revisions(version)) do
    if marker == CacheContract.markerFor(version, revision.sha1) then return true end
  end
  return false
end

-- Keep the process-global CacheFs prefix isolated even when a filesystem
-- adapter raises while probing or publishing.  The real CacheFs methods
-- return errors, but this also makes the contract safe for platform adapters
-- that surface I/O failures as Lua errors.
local function withVersionPrefix(version, fs, action)
  local saved = fs.prefix
  fs.prefix = GameVersion.cachePrefix(version)
  local ok, first, second = pcall(action)
  fs.prefix = saved
  if not ok then return false, first end
  return true, first, second
end

function CacheContract.allRequiredFilesExist(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, complete, missing = withVersionPrefix(version, fs, function()
    local required, isOverride = CacheContract.requiredFilesFor(version)
    local missingPath
    for _, path in ipairs(required) do
      if not fs.exists(path) then missingPath = path; break end
    end
    if not missingPath and not isOverride then
      for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
        if not fs.exists(path) then missingPath = path; break end
      end
    end
    return missingPath == nil, missingPath
  end)
  if not ok then return false, complete end
  return complete, missing
end

function CacheContract.readMarker(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, marker, readError = withVersionPrefix(version, fs, function()
    return fs.read(CacheContract.MARKER_PATH)
  end)
  if not ok then return nil, marker end
  -- LÖVE may return contents plus a byte count; only a nil contents result
  -- makes the auxiliary value an error.  CacheFs' portable reader returns
  -- just the contents, so this remains adapter-neutral.
  if marker == nil then return nil, readError end
  return marker
end

function CacheContract.isReady(version, fs)
  fs = fs or require("src.import.CacheFs")
  if CacheContract.sourceTreeHasData(version) then return true end
  local marker, readError = CacheContract.readMarker(version, fs)
  if readError or not CacheContract.markerMatches(version, marker) then return false end
  return CacheContract.allRequiredFilesExist(version, fs)
end

function CacheContract.publish(version, fs, sha1)
  fs = fs or require("src.import.CacheFs")
  local complete, missing = CacheContract.allRequiredFilesExist(version, fs)
  if not complete then
    -- A caller may be retrying over a partially replaced cache.  Do not
    -- leave its old marker advertising readiness after this failed check.
    local removed, removeError = withVersionPrefix(version, fs, function()
      if not fs.remove then
        error("cache filesystem cannot remove the completion marker")
      end
      return fs.remove(CacheContract.MARKER_PATH)
    end)
    if not removed then
      return false, "cache is incomplete; missing " .. tostring(missing)
        .. "; could not remove completion marker: " .. tostring(removeError)
    end
    return false, "cache is incomplete; missing " .. tostring(missing)
  end
  local changed, ok, err = withVersionPrefix(version, fs, function()
    return fs.write(CacheContract.MARKER_PATH, CacheContract.markerFor(version, sha1))
  end)
  if not changed then return false, tostring(ok) end
  return ok, err
end

function CacheContract.sourceTreeHasData(version)
  if not (love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getRealDirectory and love.filesystem.getSource) then
    return false
  end
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local required, isOverride = CacheContract.requiredFilesFor(version)
  local source = love.filesystem.getSource()
  for _, path in ipairs(required) do
    local fullPath = prefix .. path
    if love.filesystem.getInfo(fullPath, "file") == nil
        or love.filesystem.getRealDirectory(fullPath) ~= source then
      return false
    end
  end
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      local fullPath = prefix .. path
      if love.filesystem.getInfo(fullPath, "file") == nil
          or love.filesystem.getRealDirectory(fullPath) ~= source then
        return false
      end
    end
  end
  return true
end

return CacheContract
