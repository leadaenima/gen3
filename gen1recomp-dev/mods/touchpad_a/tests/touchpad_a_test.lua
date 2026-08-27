-- Standalone: luajit mods/touchpad_a/tests/touchpad_a_test.lua
-- Uncaptured taps fire A; a hold re-taps a few times per second; the
-- on-screen pad still keeps first refusal.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")

local function fakeGame(loader, data)
  return setmetatable({ input = Input, mods = loader, data = data },
    { __index = Game })
end

local function step(game, dt)
  Runtime.call("input.step", function() end, game, dt or 1 / 60)
  Input:step()
end

local run = T.sdk.loadMod("mods/touchpad_a")
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local game = fakeGame(run.loader, run.data)
Input:init()
TouchControls:init()

-- a tap on empty glass is one A press, not a hold
do
  Game.touchpressed(game, 1, 8, 8, 0, 0, 1)
  T.eq(Input:isDown("a"), false, "a tap does not hold A down")
  Input:step()
  T.eq(Input:wasPressed("a"), true, "the first uncaptured tap queues A")
  Input:step()
  T.eq(Input:wasPressed("a"), false, "that edge lasts one step")
  Game.touchreleased(game, 1, 8, 8, 0, 0, 1)
end

-- a hold re-taps after the interval (default 5 / sec)
do
  Game.touchpressed(game, 2, 8, 8, 0, 0, 1)
  Input:step()
  T.eq(Input:wasPressed("a"), true, "press still fires immediately")
  Input:step()
  T.eq(Input:wasPressed("a"), false, "the first edge is consumed")
  step(game, 0.1)
  T.eq(Input:wasPressed("a"), false, "too soon to repeat")
  step(game, 0.1)
  T.eq(Input:wasPressed("a"), true, "holding re-taps A after 1/rate seconds")
  Game.touchreleased(game, 2, 8, 8, 0, 0, 1)
  Input:step()
  step(game, 1)
  T.eq(Input:wasPressed("a"), false, "lifting stops the repeat")
end

-- two fingers: the second one does not extra-tap, and repeat lasts
-- until the last finger lifts
do
  Game.touchpressed(game, "t1", 8, 8, 0, 0, 1)
  Input:step()
  T.eq(Input:wasPressed("a"), true, "first finger taps once")
  Game.touchpressed(game, "t2", 20, 20, 0, 0, 1)
  Input:step()
  T.eq(Input:wasPressed("a"), false, "a second finger does not extra-tap")
  Game.touchreleased(game, "t1", 8, 8, 0, 0, 1)
  step(game, 0.2)
  T.eq(Input:wasPressed("a"), true, "repeat continues while another finger is down")
  Game.touchreleased(game, "t2", 20, 20, 0, 0, 1)
  Input:step()
  step(game, 1)
  T.eq(Input:wasPressed("a"), false, "the last lift stops the repeat")
end

-- focus loss cancels the repeat
do
  Game.touchpressed(game, 3, 8, 8, 0, 0, 1)
  Input:step()
  Game.focus(game, false)
  Input:step()
  step(game, 1)
  T.eq(Input:wasPressed("a"), false, "a cancelled pointer stops repeating")
end

-- mouse clicks do nothing unless the option is on
do
  Game.mousepressed(game, 30, 30, 1, false)
  Input:step()
  T.eq(Input:wasPressed("a"), false, "a mouse click is ignored by default")
  Game.mousereleased(game, 30, 30, 1, false)
end

-- the virtual pad still captures first: a press on the drawn A is the
-- overlay's A, not this mod's, so d-pad / B / START / SELECT are untouched
do
  TouchControls.active, TouchControls.enabled = true, true
  TouchControls.img = { stub = true }
  local L = TouchControls:layout()
  Game.touchpressed(game, 21, L.a.cx, L.a.cy)
  T.eq(Input:isDown("a"), true, "the overlay still captures its own A button")
  Game.touchreleased(game, 21, L.a.cx, L.a.cy)
  T.eq(Input:isDown("a"), false, "lifting off the overlay A releases it")
  Game.touchpressed(game, 22, L.b.cx, L.b.cy)
  T.eq(Input:isDown("b"), true, "the overlay B button is unchanged")
  T.eq(Input:isDown("a"), false, "tapping overlay B does not fire touchpad A")
  Game.touchreleased(game, 22, L.b.cx, L.b.cy)
  Game.touchpressed(game, 23, L.dpad.cx, L.dpad.cy)
  T.eq(Input:isDown("a"), false, "tapping the d-pad does not fire touchpad A")
  Game.touchreleased(game, 23, L.dpad.cx, L.dpad.cy)
  TouchControls.active = false
  TouchControls.img = nil
  TouchControls:reset()
end

run.release()
T.finish("touchpad_a")
