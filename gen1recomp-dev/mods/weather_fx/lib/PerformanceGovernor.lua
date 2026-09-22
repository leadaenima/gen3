local V = ...

-- Weather FX 6 performance governor.
--
-- The old Quality AUTO ladder chooses an authored quality tier. This governor
-- operates *inside* that tier: it trims simulation frequency and particle pool
-- occupancy when the whole frame or Lua heap is under pressure, then restores
-- headroom slowly. Explicit player-selected quality tiers remain untouched.
local G = {}
local Settings = V.require("Settings")
local Config = V.require("Config")

local state={
  targetFps=60, ema=1/60, jitter=0, pressure=0, frameScale=1,
  memoryKB=0, memoryPressure=0, scale=1, frames=0, late=0, early=0,
  lastDt=1/60, mode="auto", memTimer=0,
}

local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function autoMode()
  local menu=Settings.get("quality")
  if menu and menu~="auto" then return false end
  local cfg=Config.get().quality
  if cfg and cfg~="auto" then return false end
  return Settings.get("autoPerformance") ~= "off"
end

function G.setTargetFps(v) state.targetFps=clamp(tonumber(v) or 60,30,144) end
function G.targetFps() return state.targetFps end

function G.update(dt)
  dt=tonumber(dt) or 0
  if dt<=0 then return end
  -- Target is player-facing and may change while the game is running. Reading
  -- it here keeps AUTO PERFORMANCE independent from game/weather speed.
  local targetSetting=tonumber(Settings.get("performanceTarget"))
  if targetSetting then state.targetFps=clamp(targetSetting,30,60) end
  -- Sustained very slow frames are the strongest possible pressure signal,
  -- not samples to discard. Clamp a hitch to 250ms so one pause cannot force
  -- a tier change, while repeated 4-FPS frames still drive AUTO downward.
  if dt>.25 then dt=.25 end
  state.frames=state.frames+1; state.lastDt=dt
  local a=math.min(1,dt/1.35)
  local prev=state.ema
  state.ema=prev+(dt-prev)*a
  state.jitter=state.jitter+(math.abs(dt-state.ema)-state.jitter)*math.min(1,dt/2.0)
  local target=1/state.targetFps
  local framePressure=clamp((state.ema-target*.92)/(target*.78),0,1)
  -- Heap size changes slowly compared with a frame. Querying Lua's collector
  -- every frame adds VM/collector traffic to every weather, so sample at 2 Hz.
  state.memTimer=(state.memTimer or 0)+dt
  if state.memTimer>=.5 then
    state.memTimer=state.memTimer-.5
    local mem=state.memoryKB or 0
    if collectgarbage then pcall(function() mem=tonumber(collectgarbage("count")) or mem end) end
    state.memoryKB=mem
    state.memoryPressure=clamp((mem-196608)/(393216-196608),0,1)
  end
  state.pressure=math.max(framePressure,state.memoryPressure*.90)
  if autoMode() then
    state.mode="auto"
    -- Fast degradation, deliberately slow recovery prevents oscillation.
    -- AGGRESSIVE is an explicit low-end preference: it permits deeper trimming
    -- and reacts faster, while BALANCED keeps the historical visual floor.
    local aggressive=Settings.get("autoPerformance")=="aggressive"
    local wanted=aggressive and clamp(1-state.pressure*.70,.34,1)
                           or clamp(1-state.pressure*.52,.48,1)
    local tau=(wanted<state.frameScale) and (aggressive and .32 or .55)
                                             or (aggressive and 4.2 or 5.5)
    local f=1-math.exp(-dt/tau)
    state.frameScale=state.frameScale+(wanted-state.frameScale)*f
    state.scale=clamp(state.frameScale*(1-state.memoryPressure*.18),.42,1)
  else
    state.mode="manual"; state.frameScale=1; state.scale=1
  end
  if state.ema>target*1.20 then state.late=state.late+1 elseif state.ema<target*.88 then state.early=state.early+1 end
end

function G.scale() return state.scale end
function G.simulationScale()
  if not autoMode() then state.mode="manual";state.frameScale=1;state.scale=1;return 1 end
  local aggressive=Settings.get("autoPerformance")=="aggressive"
  if aggressive then return clamp(.38+.62*state.scale,.38,1) end
  return clamp(.52+.48*state.scale,.52,1)
end
function G.particleScale()
  -- Manual quality tiers are literal authored choices. Read the live setting
  -- here rather than trusting state.mode from the previous update tick, so a
  -- menu switch out of AUTO cannot spend even one frame under stale AUTO trim.
  if not autoMode() then state.mode="manual";state.frameScale=1;state.scale=1;return 1 end
  state.mode="auto"
  local aggressive=Settings.get("autoPerformance")=="aggressive"
  local base=aggressive and clamp(.30+.70*state.scale,.30,1)
                        or clamp(.46+.54*state.scale,.46,1)
  local ok,P=pcall(V.require,"PredictiveBudget")
  if ok and P and P.particleScale then local ok2,v=pcall(P.particleScale); if ok2 and tonumber(v) then base=math.min(base,tonumber(v)) end end
  return clamp(base,aggressive and .30 or .42,1)
end
function G.interval(base)
  base=math.max(0,tonumber(base) or 0)
  if base<=0 then return 0 end
  return base/G.simulationScale()
end
function G.memoryPressure() return state.memoryPressure end
function G.auto() return state.mode=="auto" end
function G.peek() return state end
function G.sample() local o={}; for k,v in pairs(state) do o[k]=v end; return o end
function G.reset()
  state.ema=1/state.targetFps; state.jitter=0; state.pressure=0; state.frameScale=1
  state.memoryKB=0; state.memoryPressure=0; state.memTimer=0; state.scale=1; state.frames=0; state.late=0; state.early=0
end
function G.describe()
  return string.format("%s %.0ffps pressure=%d%% work=%d%% mem=%.1fMiB",state.mode,1/math.max(1e-6,state.ema),state.pressure*100,state.scale*100,state.memoryKB/1024)
end
return G
