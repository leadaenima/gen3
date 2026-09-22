-- Headless preload for gen3_mod_hooks_test when the full Ruby tree is absent.
-- Real modules on the player's machine win; these only fill package.preload
-- for names that are not already loadable.
local function stub(name)
  local M = {}
  if name == "src.core.Mp2kAudio" then
    M._vol = 7
    M._song = nil
    function M.setVolumeLevel(level) M._vol = tonumber(level) or 7 end
    function M.setEffectVolumeLevel() end
    function M.setVolume(vol) M._floatVol = tonumber(vol) end
    function M.currentSong() return M._song end
    function M.playSong(_, songId) M._song = songId end
    function M.stop() M._song = nil end
    function M.update() end
    function M.isPlaying() return M._song ~= nil end
    function M.fadeOut() end
    function M.playEffect() return nil end
    function M.voicePlaying() return false end
    function M.playVoice() return nil end
    return M
  end
  if name == "src.core.StateStack" then
    M.states = {}
    function M:init() self.states = {} end
    function M:push(state)
      self.states[#self.states + 1] = state
      if state and type(state.enter) == "function" then state:enter() end
    end
    function M:pop()
      local s = table.remove(self.states)
      if s and type(s.exit) == "function" then s:exit() end
      return s
    end
    function M:top() return self.states[#self.states] end
    function M:update(dt)
      local s = self:top()
      if s and type(s.update) == "function" then s:update(dt) end
    end
    function M:draw()
      local s = self:top()
      if s and type(s.draw) == "function" then s:draw() end
    end
    return M
  end
  setmetatable(M, {
    __call = function() return M end,
    __index = function() return function() return M end end,
  })
  return M
end

local NAMES = {
  "src.core.Contest3", "src.core.FixedStep", "src.core.Game3BattleFx",
  "src.core.Game3BattleTransition", "src.core.Game3Boot", "src.core.Game3ModWorld",
  "src.core.Game3MoveAnim", "src.core.Game3Pc", "src.core.Game3PlayerPc",
  "src.core.Game3RegionMap", "src.core.Game3Tv", "src.core.Game3WeatherFx",
  "src.core.GameSpeed", "src.core.GameVersion", "src.core.GamepadMap",
  "src.core.Input", "src.core.Mp2kAudio", "src.core.Mp2kSynth",
  "src.core.SaveData", "src.core.SaveSerializer", "src.core.StateStack",
  "src.core.TouchControls", "src.data.battle_tower", "src.import.CacheFs",
  "src.import.Gen3MapPack", "src.import.Gen3Script",
  "src.import.RomExtractorGen3Battle", "src.import.RomExtractorGen3Party",
  "src.mods.Loader", "src.render.Assets", "src.render.Font",
  "src.render.GameViewport", "src.render.Pipelines", "src.render.PixelCanvas",
  "src.render.Renderer", "src.render.Tilt", "src.render.Zoom",
  "src.ui.Theme", "src.ui.gen3.NamingScreen", "src.ui.gen3.WallClock", "src.world.gen3.MapNames",
}

return function()
  for _, name in ipairs(NAMES) do
    local ok = pcall(require, name)
    if not ok then
      package.preload[name] = function() return stub(name) end
    end
  end
end
