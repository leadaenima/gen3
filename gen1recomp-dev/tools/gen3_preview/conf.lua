-- Run from the repo:  lovec tools/gen3_preview
function love.conf(t)
  t.identity = "pokemon-love2d"
  t.window.width = 480
  t.window.height = 320
  t.window.title = "gen3 preview"
  t.modules.audio = false
  t.modules.joystick = false
  t.modules.physics = false
end
