-- Share the game's save directory so this harness can read the extracted
-- ruby cache and write new assets straight into it.
-- Run from the repo:  lovec tools/gen3_finder
function love.conf(t)
  t.identity = "pokemon-love2d"
  t.window.width = 480
  t.window.height = 320
  t.window.visible = false
end
