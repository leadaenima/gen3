-- Read-only Gen 3 battle state for companion UIs and accessibility mods.
--
-- The Gen 1 arm's counterpart, and deliberately the same SHAPE: a mod that
-- reads `snapshot()` should not care which game it is attached to, so the
-- payload keys are Gen 1's even where Ruby spells its own state differently.
-- `mod.battle` was nil on a Ruby boot for one reason -- Loader's
-- GENERATION_HOMES had no BattleAPI entry for generation 3 -- and a nil facade
-- gives a mod nothing to fall back to.
--
-- WHAT RUBY SPELLS DIFFERENTLY, and what that costs here:
--
--   * Gen 1 keeps a battle STATE on the stack (`states[i].isBattleState`) with
--     battlers that wrap a mon (`battle.player.mon`).  Ruby keeps a plain
--     table on the game (`Game3.battle`) whose `player` and `enemy` ARE the
--     mons.  So there is no battler layer to read curTypes/curMoves from and
--     the mon's own `type1`/`type2`/`moves` are the live values.
--   * Gen 1's phase is a string on the battle (`menu` / `moveSelect` /
--     `messages`); Ruby's is `battle.kind`, which also names screens that are
--     not menus at all (`intro`, `bag`, `fight`).  `prompt` maps the ones that
--     have a Gen 1 meaning and answers "locked" for the rest rather than
--     inventing one.
--   * Ruby has no `battleKind()`; wild vs trainer is `battle.npc` /
--     `battle.isTrainer`, and Safari is `battle.safari`.
--
-- WHY `submit` REFUSES.  Gen 1's battle exposes choice verbs (chooseMenu,
-- chooseMove, cancelMove) that a mod can call directly.  Ruby's battle has no
-- such verbs: it is driven from the pad through Game3's own input handling,
-- with `cursor` / `fightCursor` / `partyCursor` as the live selection.  Poking
-- those fields and hoping the next frame reads them is not a contract, so this
-- arm says so and names the seam that IS one -- `mod.input`, whose tap/press
-- are source-safe and land in the same input the player's pad does.

local BattleAPI = {}
BattleAPI.__index = BattleAPI

function BattleAPI.new(game)
  return setmetatable({ game = game, revision = 0, signature = nil }, BattleAPI)
end

-- Ruby's battle lives on the game, not on a stack state.  A finished battle
-- leaves the field nil, which is the same "no battle" answer Gen 1 gives.
local function activeBattle(game)
  local battle = game and game.battle
  if type(battle) ~= "table" then return nil end
  return battle
end

local function speciesName(game, mon)
  if not mon then return nil end
  if mon.name and mon.name ~= "" then return mon.name end
  local row = game.speciesRow and game:speciesRow(mon.species)
  return (row and row.name) or tostring(mon.species)
end

local function monCopy(game, mon, active)
  if not mon then return nil end
  return {
    species = mon.species,
    name = speciesName(game, mon),
    level = mon.level,
    hp = mon.hp,
    maxHp = mon.maxHp or mon.hp,
    -- Ruby leaves the field absent rather than storing a "none" token, and a
    -- reader that expects Gen 1's nil-for-healthy sees the same thing
    status = mon.status,
    active = active and true or false,
  }
end

-- Which fight this is, in Gen 1's vocabulary.  Ruby has no battleKind(), so
-- the markers are read directly; "wild" is the default because that is what a
-- battle with neither a trainer nor a Safari context is.
local function battleKind(battle)
  if battle.safari then return "safari" end
  if battle.isTrainer or battle.npc then return "trainer" end
  return "wild"
end

-- Ruby's `kind` names screens as well as menus.  Only the ones with a Gen 1
-- meaning are translated; everything else is "locked", which is the honest
-- answer for a state a mod has no verb for anyway.
local PROMPT_BY_KIND = {
  menu = "menu",
  fight = "moves",
  bag = "locked",
  intro = "advance",
}

local function promptFor(battle)
  local mapped = PROMPT_BY_KIND[battle.kind]
  if mapped then return mapped end
  -- a message still printing is "locked"; one that has finished and is
  -- waiting on the player is the thing Gen 1 calls "advance"
  if battle.printWait then return "advance" end
  return "locked"
end

local function visibleMessage(battle)
  local text = battle.fullText or battle.text
  if type(text) ~= "string" or text == "" then return nil end
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
  if #lines == 0 then return nil end
  return lines
end

local function moveCopies(game, battle)
  local out = {}
  local mon = battle.player
  for slot, move in ipairs((mon and mon.moves) or {}) do
    if type(move) == "table" then
      out[slot] = {
        slot = slot, id = move.id, name = move.name or tostring(move.id),
        pp = move.pp, maxPp = move.maxPp or move.pp,
        type = move.type, power = move.power, accuracy = move.accuracy,
        -- Gen 1 previews effectiveness and hit chance off its own Damage
        -- module; Ruby's damage path is Game3:useMove and has no pure
        -- preview to call, so these stay nil rather than being guessed
        displayPower = move.power, hitChance = nil, effectiveness = nil,
        disabled = false,
      }
    end
  end
  return out
end

local function partyCopies(game, battle)
  local out = {}
  for i, mon in ipairs(game.party or {}) do
    local copy = monCopy(game, mon, mon == battle.player)
    if copy then
      copy.slot = i
      out[i] = copy
    end
  end
  return out
end

-- A cheap fingerprint of everything snapshot() reports, so `revision` only
-- moves when something a reader would redraw for has changed.
local function signature(game, battle)
  local parts = { tostring(battle), tostring(battle.kind),
    tostring(battle.turns or 0), tostring(battle.cursor),
    tostring(battle.fightCursor), tostring(battle.partyCursor),
    tostring(battle.printWait), tostring(battle.text) }
  for _, mon in ipairs({ battle.player, battle.enemy }) do
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon and mon.hp)
    parts[#parts + 1] = tostring(mon and mon.status)
    parts[#parts + 1] = tostring(mon and mon.level)
  end
  for _, mon in ipairs(game.party or {}) do
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon.hp)
    parts[#parts + 1] = tostring(mon.status)
  end
  return table.concat(parts, "|")
end

function BattleAPI:_revision(battle)
  local nextSignature = signature(self.game, battle)
  if nextSignature ~= self.signature then
    self.signature = nextSignature
    self.revision = self.revision + 1
  end
  return self.revision
end

function BattleAPI:snapshot()
  local game = self.game
  local battle = activeBattle(game)
  if not battle then return nil end
  local kind = battleKind(battle)
  return {
    revision = self:_revision(battle),
    kind = kind,
    catchable = kind == "wild",
    prompt = promptFor(battle),
    message = visibleMessage(battle),
    turn = battle.turns or 0,
    player = monCopy(game, battle.player, true),
    enemy = monCopy(game, battle.enemy, true),
    party = partyCopies(game, battle),
    moves = moveCopies(game, battle),
    -- Gen 1 lists the balls and battle medicine a mod may submit.  Submitting
    -- is refused here, so publishing a list that cannot be acted on would be
    -- an invitation to a dead end; a mod that wants the bag reads it through
    -- mod.game.
    items = {},
    safariBalls = battle.safari and battle.safari.balls or nil,
    mimicMoves = {}, mimicIndex = nil,
  }
end

-- Present, and refuses for a stated reason.  A missing method would make a
-- cross-generation mod crash on a call Gen 1 answers; a refusal with a reason
-- lets it fall back.
function BattleAPI:submit(intent)
  if type(intent) ~= "table" then return nil, "intent must be a table" end
  if not activeBattle(self.game) then return nil, "no battle" end
  return nil, "Ruby's battle has no choice verbs to submit against -- it is "
    .. "driven from the pad through Game3's own input handling; use "
    .. "mod.input:tap(game, button), which is source-safe and lands in the "
    .. "same input the player's pad does"
end

return BattleAPI
