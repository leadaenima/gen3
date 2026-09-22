
-- Minimal mock of Gen1Recomp audio path
local plays = {}
local love = {
  audio = {
    newSource = function(path, kind)
      assert(type(path) == "string", "path must be string")
      local f = io.open(path, "rb")
      if not f then error("cannot open " .. path) end
      local size = f:seek("end")
      f:close()
      if size < 100 then error("too small " .. path) end
      local src = {
        path = path,
        kind = kind,
        vol = 0,
        playing = false,
        setLooping = function(self) end,
        setVolume = function(self, v) self.vol = v end,
        play = function(self) self.playing = true; plays[#plays+1] = self.path end,
        stop = function(self) self.playing = false end,
        isPlaying = function(self) return self.playing end,
        clone = function(self)
          return {
            path = self.path, vol = 0, playing = false,
            setVolume = function(s,v) s.vol=v end,
            play = function(s) s.playing=true; plays[#plays+1]=s.path end,
            stop = function(s) s.playing=false end,
          }
        end,
      }
      return src
    end
  },
  data = { newByteData = function(b) return b end },
  sound = nil,
}
_G.love = love

local MOD_PATH = (arg and arg[0] or ""):match("^(.*)tools[/\\]") or "./"
if MOD_PATH=="" then MOD_PATH="." end
if MOD_PATH:sub(-1)=="/" or MOD_PATH:sub(-1)=="\\" then MOD_PATH=MOD_PATH:sub(1,-2) end
local mod = {
  path = MOD_PATH,
  assets = {
    path = function(self, rel) return MOD_PATH .. "/" .. rel end,
  },
  read = function(self, rel)
    local f = io.open(MOD_PATH .. "/" .. rel, "rb")
    if not f then return nil end
    local d = f:read("*a"); f:close(); return d
  end,
  log = { warn = function(_, ...) print("WARN", ...) end },
}

-- Inline the path-first loader (mirror of production)
local Audio = { DIR = "assets/sounds/" }
local cache = {}
local function assetPath(relative)
  return mod.assets:path(relative)
end
local function candidatePaths(name)
  local rels = {
    Audio.DIR .. name .. ".ogg",
    Audio.DIR .. name .. ".mp3",
  }
  local out = {}
  for _, rel in ipairs(rels) do
    out[#out+1] = assetPath(rel)
  end
  return out
end
local function sourceFor(name, kind)
  kind = kind or "static"
  for _, path in ipairs(candidatePaths(name)) do
    local ok, src = pcall(love.audio.newSource, path, kind)
    if ok and src then cache[name] = src; return src end
  end
  return nil
end

local beds = { "rain", "rain_heavy", "heavy_storm", "storm", "wind", "wind_desert" }
local oneshots = { "thunder_clap", "thunder_roll", "thunder_zapdos" }
local failures = 0
for _, n in ipairs(beds) do
  local src = sourceFor(n, "stream") or sourceFor(n, "static")
  if not src then print("FAIL bed", n); failures = failures + 1
  else
    src:setVolume(0.7); src:play()
    if not src.playing then print("FAIL play", n); failures = failures + 1
    else print("PASS play bed", n, src.path) end
  end
end
for _, n in ipairs(oneshots) do
  local src = sourceFor(n, "static")
  if not src then print("FAIL oneshot", n); failures = failures + 1
  else
    local p = src:clone(); p:setVolume(0.8); p:play()
    if not p.playing then print("FAIL thunder play", n); failures = failures + 1
    else print("PASS play thunder", n) end
  end
end
print("PLAYED_COUNT", #plays)
if failures > 0 then os.exit(1) end
print("ALL_LUA_PLAY_TESTS_PASSED")
