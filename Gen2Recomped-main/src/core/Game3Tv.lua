-- SaveBlock1.tvShows (tv.c). InterviewAfter queues; house TVs pick via
-- special_0x44 / DoTVShow. Easy Chat lines are summarized as plain text.
local Gen3Script = require("src.import.Gen3Script")

local Tv = {}

function Tv.attach(Game3)
  Game3.TV_SHOWS_COUNT = 25
  Game3.TVSHOW_FAN_CLUB_LETTER = 1
  Game3.TVSHOW_RECENT_HAPPENINGS = 2
  Game3.TVSHOW_PKMN_FAN_CLUB_OPINIONS = 3
  Game3.TVSHOW_UNKN_SHOWTYPE_04 = 4
  Game3.TVSHOW_NAME_RATER_SHOW = 5
  Game3.TVSHOW_BRAVO_TRAINER_POKEMON_PROFILE = 6
  Game3.TVSHOW_BRAVO_TRAINER_BATTLE_TOWER_PROFILE = 7
  Game3.TVSHOW_POKEMON_TODAY_CAUGHT = 21
  Game3.TVSHOW_SMART_SHOPPER = 22
  Game3.TVSHOW_POKEMON_TODAY_FAILED = 23
  Game3.TVSHOW_FISHING_ADVICE = 24
  Game3.TVSHOW_WORLD_OF_MASTERS = 25
  Game3.TVSHOW_MASS_OUTBREAK = 41

  function Game3:ensureTvShows()
    if type(self.tvShows) ~= "table" then
      self.tvShows = {}
    end
    return self.tvShows
  end

  function Game3:clearTvShowAt(idx)
    local shows = self:ensureTvShows()
    idx = (tonumber(idx) or 0) + 1
    if idx < 1 or idx > Game3.TV_SHOWS_COUNT then return end
    shows[idx] = nil
  end

  -- sub_80BF720: slots 0..4 (interview scratch / link mix).
  function Game3:findTvShowSlotEarly()
    local shows = self:ensureTvShows()
    for i = 1, 5 do
      local s = shows[i]
      if not s or (s.kind or 0) == 0 then return i - 1 end
    end
    return nil
  end

  -- sub_80BF74C: slots 5..23 (airable shows).
  function Game3:findTvShowSlotAir()
    local shows = self:ensureTvShows()
    for i = 6, 24 do
      local s = shows[i]
      if not s or (s.kind or 0) == 0 then return i - 1 end
    end
    return nil
  end

  function Game3:tvChannelByShowType(kind)
    kind = tonumber(kind) or 0
    if kind == Game3.TVSHOW_MASS_OUTBREAK then return 4 end
    if kind == Game3.TVSHOW_POKEMON_TODAY_CAUGHT
        or kind == Game3.TVSHOW_SMART_SHOPPER
        or kind == Game3.TVSHOW_POKEMON_TODAY_FAILED
        or kind == Game3.TVSHOW_FISHING_ADVICE
        or kind == Game3.TVSHOW_WORLD_OF_MASTERS then
      return 2
    end
    if kind >= Game3.TVSHOW_FAN_CLUB_LETTER
        and kind <= Game3.TVSHOW_BRAVO_TRAINER_BATTLE_TOWER_PROFILE then
      return 1
    end
    return 0
  end

  function Game3:special0x44()
    local shows = self:ensureTvShows()
    local filled = 5
    for i = 5, Game3.TV_SHOWS_COUNT - 2 do
      local s = shows[i + 1]
      if not s or (s.kind or 0) == 0 then
        filled = i
        break
      end
      filled = i + 1
    end
    if filled < 1 then filled = 1 end
    local start = self:gbaRandom() % filled
    local j = start
    repeat
      local s = shows[j + 1]
      if s and (s.kind or 0) ~= 0 and s.active then
        local ch = self:tvChannelByShowType(s.kind)
        if ch ~= 4 or (s.daysLeft or 0) == 0 then
          return j
        end
      end
      if j == 0 then
        j = Game3.TV_SHOWS_COUNT - 2
      else
        j = j - 1
      end
    until j == start
    return Game3.TV_NO_SHOW
  end

  function Game3:getTVShowType()
    local shows = self:ensureTvShows()
    local i = (tonumber(self:varGet(0x8004)) or 0) + 1
    local s = shows[i]
    local kind = (s and s.kind) or 0
    self:setScriptVar(Gen3Script.VAR_RESULT, kind)
    return kind
  end

  function Game3:getNonMassOutbreakActiveTVShow()
    local shows = self:ensureTvShows()
    local prefer = tonumber(self:varGet(0x8004)) or 0
    if prefer == Game3.TV_NO_SHOW then return Game3.TV_NO_SHOW end
    for i = 0, Game3.TV_SHOWS_COUNT - 2 do
      local s = shows[i + 1]
      if s and s.active and (s.kind or 0) ~= 0
          and (s.kind or 0) ~= Game3.TVSHOW_MASS_OUTBREAK then
        self:setScriptVar(0x8004, i)
        return i
      end
    end
    return prefer
  end

  function Game3:tvShowDone()
    local shows = self:ensureTvShows()
    local i = (tonumber(self:varGet(0x8004)) or 0) + 1
    local s = shows[i]
    if s then s.active = false end
    self.tvShowState = 0
    self:setScriptVar(Gen3Script.VAR_RESULT, 1)
    return 1
  end

  function Game3:doTVShow()
    local shows = self:ensureTvShows()
    local i = (tonumber(self:varGet(0x8004)) or 0) + 1
    local s = shows[i]
    if not s or not s.active or (s.kind or 0) == 0 then
      return self:tvShowDone()
    end
    local state = self.tvShowState or 0
    local name = s.playerName or (self:playerName() or "PLAYER")
    local species = self:speciesName(s.species or 0)
    local nick = s.nickname or species
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    if state == 0 then
      self:setStringVar(1, name)
      self:setStringVar(2, species)
      if s.kind == Game3.TVSHOW_FAN_CLUB_LETTER then
        self.field = {
          kind = "talk",
          text = ("%s's favorite POKeMON is the\n%s!"):format(name, species),
          scripted = true,
        }
      elseif s.kind == Game3.TVSHOW_RECENT_HAPPENINGS then
        self.field = {
          kind = "talk",
          text = ("Recent happenings with %s!"):format(name),
          scripted = true,
        }
      elseif s.kind == Game3.TVSHOW_PKMN_FAN_CLUB_OPINIONS then
        self.field = {
          kind = "talk",
          text = ("%s's %s is looking great!"):format(name, nick),
          scripted = true,
        }
      elseif s.kind == Game3.TVSHOW_BRAVO_TRAINER_POKEMON_PROFILE then
        local cat = Game3.CONTEST_CAT_NAMES[(s.contestCategory or 0) + 1] or "COOL"
        self.field = {
          kind = "talk",
          text = ("Bravo, %s!\nThat %s %s was amazing!"):format(name, cat, species),
          scripted = true,
        }
      elseif s.kind == Game3.TVSHOW_NAME_RATER_SHOW then
        self.field = {
          kind = "talk",
          text = ("The NAME RATER saw %s's\n%s!"):format(name, nick),
          scripted = true,
        }
      elseif s.kind == Game3.TVSHOW_POKEMON_TODAY_CAUGHT then
        self.field = {
          kind = "talk",
          text = ("%s caught a %s today!"):format(name, species),
          scripted = true,
        }
      else
        self.field = {
          kind = "talk",
          text = ("Today's show stars %s!"):format(name),
          scripted = true,
        }
      end
      self.tvShowState = 1
      return 0
    end
    return self:tvShowDone()
  end

  function Game3:interviewAfter()
    local kind = tonumber(self:varGet(0x8005)) or 0
    local slot = self:findTvShowSlotAir()
    if slot == nil then return end
    local lead = self:leadMon()
    local show = {
      kind = kind,
      active = true,
      playerName = self:playerName() or "PLAYER",
      species = (lead and lead.species) or 0,
      nickname = (lead and (lead.name or self:speciesName(lead.species))) or "",
    }
    if kind == Game3.TVSHOW_BRAVO_TRAINER_POKEMON_PROFILE then
      show.contestCategory = (self.scriptVars
        and self.scriptVars[Game3.VAR_CONTEST_CATEGORY]) or 0
    elseif kind == Game3.TVSHOW_PKMN_FAN_CLUB_OPINIONS then
      show.friendship = lead and math.floor((lead.friendship or 0) / 16) or 0
    elseif kind == 0 or kind == Game3.TVSHOW_UNKN_SHOWTYPE_04 then
      return
    end
    if kind == Game3.TVSHOW_FAN_CLUB_LETTER
        or kind == Game3.TVSHOW_RECENT_HAPPENINGS
        or kind == Game3.TVSHOW_PKMN_FAN_CLUB_OPINIONS
        or kind == Game3.TVSHOW_NAME_RATER_SHOW
        or kind == Game3.TVSHOW_BRAVO_TRAINER_POKEMON_PROFILE
        or kind == Game3.TVSHOW_BRAVO_TRAINER_BATTLE_TOWER_PROFILE then
      self:ensureTvShows()[slot + 1] = show
    end
  end

  function Game3:tvIsScriptShowKindAlreadyInQueue()
    local kind = tonumber(self:varGet(0x8004)) or 0
    local shows = self:ensureTvShows()
    for i = 1, Game3.TV_SHOWS_COUNT do
      local s = shows[i]
      if s and (s.kind or 0) == kind then
        self:setScriptVar(Gen3Script.VAR_RESULT, 1)
        return 1
      end
    end
    self:setScriptVar(Gen3Script.VAR_RESULT, 0)
    return 0
  end

  function Game3:updateTVShowsPerDay(days)
    days = tonumber(days) or 0
    if days < 1 then return end
    local shows = self:ensureTvShows()
    for i = 1, Game3.TV_SHOWS_COUNT do
      local s = shows[i]
      if s and (s.kind or 0) ~= 0 then
        if s.kind == Game3.TVSHOW_MASS_OUTBREAK then
          s.daysLeft = math.max(0, (s.daysLeft or 0) - days)
          if (s.daysLeft or 0) == 0 then s.active = true end
        elseif not s.active then
          shows[i] = nil
        end
      end
    end
  end

  function Game3:snapshotTvShows()
    local shows = self.tvShows
    if type(shows) ~= "table" then return nil end
    local out = {}
    for i = 1, Game3.TV_SHOWS_COUNT do
      local s = shows[i]
      if s and (s.kind or 0) ~= 0 then
        out[i] = {
          kind = s.kind,
          active = s.active and true or false,
          playerName = s.playerName,
          species = s.species,
          nickname = s.nickname,
          contestCategory = s.contestCategory,
          daysLeft = s.daysLeft,
          friendship = s.friendship,
        }
      end
    end
    return out
  end

  function Game3:applyTvShows(data)
    if type(data) ~= "table" then
      self.tvShows = {}
      return
    end
    local out = {}
    for i = 1, Game3.TV_SHOWS_COUNT do
      local s = data[i]
      if type(s) == "table" and (s.kind or 0) ~= 0 then
        out[i] = {
          kind = tonumber(s.kind) or 0,
          active = s.active and true or false,
          playerName = s.playerName,
          species = tonumber(s.species) or 0,
          nickname = s.nickname,
          contestCategory = tonumber(s.contestCategory) or 0,
          daysLeft = tonumber(s.daysLeft) or 0,
          friendship = tonumber(s.friendship) or 0,
        }
      end
    end
    self.tvShows = out
  end
end

return Tv
