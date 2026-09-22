-- AN OPTIONS ROW THAT IS A BUTTON, NOT A SETTING.
--
-- Every other row type stores a value the player picked.  `action` stores
-- nothing: it starts a job the mod owns and then reports on it in the same
-- place, which is the only shape that fits a long background pass.
-- DRAMATIC_SHAPE's PREBAKE VOXELS row is the one that needed it -- it shipped
-- as `type = "action"`, our manager skipped every row type it did not know,
-- and nothing ever emitted the `mod.option_action` event the mod listens for,
-- so the row simply did not exist here and VoxelPrebake could not be started.
--
-- What is pinned here:
--
--   * an action row reaches the menu at all, and activating it emits the
--     event with the mod and key that were pressed;
--   * it has no `step`, so left/right cannot nudge it into storing a value;
--   * its right-hand text is the MOD's live status function, re-read per
--     redraw, and a status function that raises greys the row rather than
--     taking the settings page down;
--   * RESET DEFAULTS leaves it alone -- it has no default to restore, and
--     writing one would invent a stored value for a button.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local ManagerState = require("src.mods.ManagerState")

local S = require("tests.harness").suite("mod option action")
local check, eq = S.check, S.eq

-- The manager only ever reads these fields off the loader, so a table with
-- them is a truthful stand-in and needs no boot.
local function fakeLoader()
  local emitted = {}
  return {
    emitted = emitted,
    modOptions = {},
    optionSchemas = {},
    optionStatus = {},
    events = { emit = function(_, name, payload)
      emitted[#emitted + 1] = { name = name, payload = payload }
    end },
  }
end

local function manager(loader)
  local m = setmetatable({
    game = { mods = loader, save = nil },
    cursor = 1,
    notices = {},
  }, { __index = ManagerState })
  function m:notify(text) self.notices[#self.notices + 1] = text end
  function m:persistOptions() end
  return m
end

local SCHEMA = {
  { key = "sound", type = "toggle", label = "SOUND", default = true },
  { key = "runIt", type = "action", label = "RUN IT", action = "START" },
}

local function rowsOf(m)
  local built = m:buildOptionRows({ id = "TestMod" }, SCHEMA)
  local byId = {}
  for _, r in ipairs(built) do byId[r.id] = r end
  return built, byId
end

do
  local loader = fakeLoader()
  local m = manager(loader)
  local built, byId = rowsOf(m)
  check(byId.runIt ~= nil, "an action row reaches the menu")
  check(byId.sound ~= nil, "and the ordinary rows still do")
  check(byId.__reset ~= nil, "RESET DEFAULTS is still there")

  -- a button is not a dial
  check(byId.runIt.step == nil, "an action row has no step")
  check(type(byId.runIt.activate) == "function", "but it can be activated")

  -- before the mod says anything, the row shows its own verb
  eq(byId.runIt.value(), "START", "an unreported action shows its verb")

  byId.runIt.activate()
  eq(#loader.emitted, 1, "activating it emitted exactly one event")
  eq(loader.emitted[1].name, "mod.option_action", "and it is the action event")
  eq(loader.emitted[1].payload.mod, "TestMod", "carrying the mod that owns it")
  eq(loader.emitted[1].payload.key, "runIt", "and the key that was pressed")

  -- and it stored nothing, which is the whole difference from a toggle
  local stored = loader.modOptions.TestMod
  check(stored == nil or stored.runIt == nil, "pressing it stores no value")
  check(#built > 0, "rows were built")
end

do
  -- the status function is the mod's, and it is re-read rather than snapshot
  local loader = fakeLoader()
  local count = 0
  loader.optionStatus.TestMod = { runIt = function()
    count = count + 1
    return count .. "/9"
  end }
  local m = manager(loader)
  local _, byId = rowsOf(m)
  eq(byId.runIt.value(), "1/9", "the row shows the mod's status")
  eq(byId.runIt.value(), "2/9", "and re-reads it on the next redraw")
  check(count == 2, "the provider ran once per read, not once per build")
end

do
  -- a status function that raises must not take the settings page with it
  local loader = fakeLoader()
  loader.optionStatus.TestMod = { runIt = function()
    error("progress exploded")
  end }
  local m = manager(loader)
  local _, byId = rowsOf(m)
  local ok, value = pcall(byId.runIt.value)
  check(ok, "a raising status provider does not propagate")
  eq(value, "START", "and the row falls back to its own verb")
end

do
  -- an empty status is not a status: it must not blank the row
  local loader = fakeLoader()
  loader.optionStatus.TestMod = { runIt = function() return "" end }
  local m = manager(loader)
  local _, byId = rowsOf(m)
  eq(byId.runIt.value(), "START", "an empty status falls back to the verb")
end

do
  -- RESET DEFAULTS walks the rows that HAVE defaults.  An action row has none,
  -- and restoring it would write nil into the stored options as if the player
  -- had chosen something.
  local loader = fakeLoader()
  local m = manager(loader)
  local _, byId = rowsOf(m)
  loader.modOptions.TestMod = { sound = false, runIt = "leftover" }
  byId.__reset.activate()
  eq(loader.modOptions.TestMod.sound, true, "a toggle is restored to default")
  eq(loader.modOptions.TestMod.runIt, "leftover",
    "and the action row is not touched")
end

do
  -- an unknown type is still skipped: admitting `action` must not admit
  -- everything, or a typo becomes an invisible no-op row
  local loader = fakeLoader()
  local m = manager(loader)
  local built = m:buildOptionRows({ id = "TestMod" }, {
    { key = "weird", type = "carousel", label = "WEIRD" },
  })
  local found = false
  for _, r in ipairs(built) do if r.id == "weird" then found = true end end
  check(not found, "an unknown row type is still skipped")
end

return S.finish()
