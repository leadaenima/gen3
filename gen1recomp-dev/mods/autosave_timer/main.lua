return function(mod)
  mod.options:define({
    { key = "enabled", type = "toggle", label = "AUTOSAVE", default = true },
    { key = "interval_min", type = "choice", label = "AUTOSAVE EVERY",
      choices = { {"1 MIN","1"}, {"3 MIN","3"}, {"5 MIN","5"} },
      default = "3" },
    { key = "notify", type = "toggle", label = "SHOW SAVE TOAST", default = true },
  })

  local game
  local lastSave
  local battling = false

  mod.events:on("game.ready", function(payload)
    game = payload.game
    lastSave = love.timer.getTime()
  end)

  mod.events:on("save.loaded", function()
    lastSave = love.timer.getTime()
  end)

  -- fires on EVERY writeSave() -- ours or a manual Start Menu save
  -- (Game.lua:806). Resetting the clock here means a manual save
  -- always pushes our next autosave out by a full interval, instead
  -- of us re-firing shortly after it.
  mod.events:on("save.writing", function()
    lastSave = love.timer.getTime()
  end)

  mod.events:on("battle.started", function() battling = true end)
  mod.events:on("battle.ended", function() battling = false end)

  local function maybeAutosave()
    if not game or battling or not lastSave then return end
    if not mod.options:get("enabled") then return end

    local interval = tonumber(mod.options:get("interval_min")) * 60
    local now = love.timer.getTime()
    if now - lastSave < interval then return end

    local written = game:writeSave()  -- fires save.writing, which
                                       -- resets lastSave for us above

    if written ~= false and mod.options:get("notify") then
      game.stack:push(mod.ui.TextBox.new(
        game, "Autosaving...\nGame saved!", nil, { auto = { delay = 90 } }))
    end
  end

  mod.hooks:wrap("input.step", function(next, gameSelf, dt)
    maybeAutosave()
    return next(gameSelf, dt)
  end)
end
