-- Fullscreen A touchpad: any gameplay pointer the on-screen pad does not
-- capture taps GB A.  The overlay keeps first refusal, so the visible
-- A/B/d-pad/START/SELECT buttons still do their own jobs; this only fills
-- the empty glass around them.  A short tap fires once.  A hold re-taps
-- a few times per second -- a held A would only produce one wasPressed
-- edge, which is why this is tap-repeat rather than a hold.
return function(mod)
  mod.options:define({
    { key = "enabled", label = "ENABLED", type = "toggle", default = true },
    { key = "mouse", label = "MOUSE CLICKS", type = "toggle", default = false },
    { key = "rate", label = "HOLD TAPS / SEC", type = "number",
      default = 5, min = 2, max = 10, step = 1 },
  })

  local fingers = {}
  local fingerCount = 0
  local wait = 0

  local function wanted(ev)
    if mod.options:get("enabled") == false then return false end
    if ev.source == "touch" then return true end
    if ev.source == "mouse" and mod.options:get("mouse") then
      return ev.button == nil or ev.button == 1
    end
    return false
  end

  local function interval()
    local n = tonumber(mod.options:get("rate")) or 5
    if n < 2 then n = 2 end
    if n > 10 then n = 10 end
    return 1 / n
  end

  local function fire(game)
    if not (game and game.input) then return end
    mod.input:tap(game, "a")
  end

  local function down(game, id)
    if id == nil or fingers[id] then return end
    fingers[id] = true
    fingerCount = fingerCount + 1
    if fingerCount == 1 then
      fire(game)
      wait = 0
    end
  end

  local function up(id)
    if id == nil or not fingers[id] then return end
    fingers[id] = nil
    fingerCount = fingerCount - 1
    if fingerCount <= 0 then
      fingerCount = 0
      wait = 0
    end
  end

  mod.hooks:wrap("input.pointer", function(nextFn, game, ev)
    local result = nextFn(game, ev)
    if type(ev) ~= "table" then return result end
    if ev.phase == "pressed" and wanted(ev) then
      down(game, ev.id)
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      up(ev.id)
    end
    return result
  end)

  -- fire the repeats on the same fixed-step boundary as a real pad so
  -- each tap is visible to that logic tick, not the next one
  mod.hooks:wrap("input.step", function(nextFn, game, dt)
    nextFn(game, dt)
    if fingerCount <= 0 then return end
    wait = wait + (tonumber(dt) or 0)
    if wait >= interval() then
      wait = 0
      fire(game)
    end
  end)
end
