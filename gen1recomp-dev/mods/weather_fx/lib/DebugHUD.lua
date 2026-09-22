-- In-game Weather FX diagnostics.
--
-- This is deliberately a normal render.hud consumer rather than a custom UI
-- state: it must remain visible while diagnosing menu/battle/voxel problems,
-- and render.hud is the engine's documented post-game HUD stage.

local V = ...
local HUD = {}

local function req(name)
  local ok, m = pcall(V.require, name)
  if ok then return m end
  return nil
end

local function call(obj, fn, ...)
  if not (obj and type(obj[fn]) == "function") then return nil end
  local ok, a, b, c, d = pcall(obj[fn], ...)
  if ok then return a, b, c, d end
  return nil
end

local function bridgeInfo(Bridge)
  if not Bridge then return false, false, false, false, "bridge-unavailable" end
  local active = call(Bridge, "active") and true or false
  local precip = call(Bridge, "handlesPrecipitation") and true or false
  local snow = call(Bridge, "handlesSnow") and true or false
  local fog = call(Bridge, "handlesFog") and true or false
  local reason = call(Bridge, "reason") or (active and "active" or "inactive")
  return active, precip, snow, fog, tostring(reason)
end

local function why(State, Settings, Scene, Bridge)
  local Config = req("Config")
  if Settings and call(Settings, "debugRain", Config) then return "debug-rain" end
  if State and (tonumber(State.level) or 0) <= 0 then return "ladder-off" end
  local now = Scene and Scene.now or {}
  if now.indoors then return "indoors" end
  local id = tostring(State and State.id or "CLEAR")
  if id == "CLEAR" then return "clear-sky" end
  local present = Settings and call(Settings, "presentMode") or "auto"
  if present == "2d" then return "2d-draw" end
  local active, precip, _, fog = bridgeInfo(Bridge)
  if active and (precip or fog) then return "3d-owned" end
  if active then return "3d-active/fallback" end
  return "2d-fallback"
end

function HUD.lines()
  local Settings = req("Settings")
  local Config = req("Config")
  local mode = Settings and call(Settings, "debugHudMode", Config) or "off"
  if mode == nil or mode == "off" then return {}, "off" end

  local State = req("WeatherState")
  local Scene = req("Scene")
  local TOD = req("TimeOfDay")
  local Quality = req("Quality")
  local Bridge = req("VoxelAtmosBridge")
  local Battle = req("Battle")
  local Particles = req("Particles")
  local Audio = req("Audio")
  local Fronts = req("Fronts")
  local Seasons = req("Seasons")
  local BuildingLight = req("BuildingLight")

  local active, p3, s3, f3, reason = bridgeInfo(Bridge)
  local present = Settings and call(Settings, "presentMode") or "auto"
  local id = tostring(State and State.id or "-")
  local now = Scene and Scene.now or {}
  local mapId = tostring(now.mapId or "-")
  local place = now.indoors and "in" or (now.outdoor and "out" or "?")
  local tod = (TOD and (TOD.pin or TOD.tod)) or "-"
  local q = Quality and call(Quality, "describe") or "-"
  local out = {}

  if mode == "3d" then
    out[#out+1] = ("wx:%s | present:%s"):format(id, tostring(present))
    out[#out+1] = ("v3:%s precip:%s snow:%s fog:%s"):format(
      active and "on" or "off", p3 and "yes" or "no", s3 and "yes" or "no", f3 and "yes" or "no")
    out[#out+1] = "v3:" .. reason
    out[#out+1] = "why:" .. why(State, Settings, Scene, Bridge)
    return out, mode
  end

  out[#out+1] = ("wx:%s | tod:%s | q:%s"):format(id, tostring(tod), tostring(q))
  out[#out+1] = ("map:%s %s | present:%s"):format(mapId, place, tostring(present))
  out[#out+1] = ("v3:%s | %s"):format(active and "on" or "off", reason)
  out[#out+1] = "why:" .. why(State, Settings, Scene, Bridge)

  if mode == "full" then
    local stateDesc = State and call(State, "describe") or "-"
    local battleDesc = Battle and call(Battle, "describe") or "-"
    out[#out+1] = ("state:%s | btl:%s"):format(tostring(stateDesc), tostring(battleDesc))

    local r, sn, gr, sp
    if Particles then r, sn, gr, sp = call(Particles, "counts") end
    out[#out+1] = ("2d:r%s s%s g%s sp%s"):format(
      tostring(r or 0), tostring(sn or 0), tostring(gr or 0), tostring(sp or 0))
    out[#out+1] = "audio:" .. tostring(Audio and call(Audio, "describe") or "-")
    out[#out+1] = "front:" .. tostring(Fronts and call(Fronts, "describe", now.mapId) or "-")
    out[#out+1] = "season:" .. tostring(Seasons and call(Seasons, "describe") or "-")
    local CE=req("CelestialEngine")
    if CE then out[#out+1] = "cel:" .. tostring(call(CE,"describe") or "-") end
    local PG=req("PerformanceGovernor"); if PG then out[#out+1]="perf:"..tostring(call(PG,"describe") or "-") end
    local SC=req("SafeCall"); local scs=SC and call(SC,"stats"); if type(scs)=="table" and (tonumber(scs.failures) or 0)>0 then out[#out+1] = ("safe:err%d %s"):format(tonumber(scs.failures) or 0,tostring(scs.lastScope or "?")) end
    local MC=req("Microclimate"); if MC then out[#out+1]=tostring(call(MC,"describe") or "micro:-") end
    local MF=req("MesoscaleField"); local mfs=MF and call(MF,"stats"); if type(mfs)=="table" then out[#out+1]=("meso:p%.2f c%.2f b%.2f %s"):format(tonumber(mfs.precip) or 0,tonumber(mfs.cloud) or 0,tonumber(mfs.band) or 0,tostring(mfs.memory or "-")) end
    local CF=req("CloudField"); local cfs=CF and call(CF,"stats"); if type(cfs)=="table" then out[#out+1]=("cloudfield:d%.2f q%.2f cells%d"):format(tonumber(cfs.density) or 0,tonumber(cfs.charge) or 0,tonumber(cfs.cells) or 0) end
    local bi = BuildingLight and call(BuildingLight, "debugInfo")
    if type(bi) == "table" then
      out[#out+1] = ("light:d%.1f f%.2f star%.2f"):format(
        tonumber(bi.dist) or -1, tonumber(bi.factor) or 0, tonumber(bi.starMul) or 1)
    end
  end
  return out, mode
end

function HUD.draw(viewport)
  local lines, mode = HUD.lines()
  if mode == "off" or #lines == 0 then return false end
  local g = love and love.graphics
  if not g or type(g.print) ~= "function" then return false end

  local x = tonumber(viewport and (viewport.gameX or viewport.x)) or 4
  local y = tonumber(viewport and (viewport.gameY or viewport.y)) or 4
  x, y = x + 4, y + 4
  local lh = 12
  local pad = 4
  local width = 156
  pcall(function()
    local font = g.getFont and g.getFont()
    if font and font.getWidth then
      width = 0
      for i=1,#lines do width = math.max(width, font:getWidth(lines[i])) end
      width = width + pad * 2
      if font.getHeight then lh = math.max(10, font:getHeight() + 2) end
    end
  end)
  local height = #lines * lh + pad * 2

  local pushed = false
  if g.push then pushed = pcall(g.push, "all") end
  pcall(g.setBlendMode, "alpha")
  pcall(g.setColor, 0, 0, 0, 0.72)
  pcall(g.rectangle, "fill", x, y, width, height)
  pcall(g.setColor, 1, 1, 1, 1)
  for i=1,#lines do pcall(g.print, lines[i], x + pad, y + pad + (i-1)*lh) end
  if pushed and g.pop then pcall(g.pop) end
  return true
end

return HUD
