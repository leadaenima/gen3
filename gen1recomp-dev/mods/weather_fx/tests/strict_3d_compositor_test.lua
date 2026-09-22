-- Weather FX strict 3D compositor ownership regression.
-- Proves that explicit 3D + active voxel host submits zero 2D weather visuals,
-- while AUTO/inactive hosts retain fail-safe behavior and opaque battles retain the 2D battle path.

local scriptPath = (arg and arg[0]) or "tests/strict_3d_compositor_test.lua"
local ROOT = scriptPath:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1
  else failed = failed + 1; io.write("  FAIL  ", label, "\n") end
end
local function eq(a,b,label)
  check(a==b, label .. " (" .. tostring(a) .. " == " .. tostring(b) .. ")")
end

local calls = { rect=0, particles=0, fog=0, lightning=0, funnel=0, glare=0 }
local function resetCalls() for k in pairs(calls) do calls[k]=0 end end
local function visualTotal()
  local n=0; for _,v in pairs(calls) do n=n+v end; return n
end

love = {
  graphics = {
    getColor=function() return 1,1,1,1 end,
    setColor=function() end,
    getBlendMode=function() return "alpha","alphamultiply" end,
    setBlendMode=function() end,
    rectangle=function() calls.rect=calls.rect+1 end,
    push=function() end, pop=function() end, translate=function() end,
    getScissor=function() return nil end, setScissor=function() end,
    newMesh=function() return { setVertices=function() end } end,
    draw=function() calls.glare=calls.glare+1 end,
  },
  timer = { getTime=function() return 0 end },
  math = { random=math.random },
}

local mode = "3d"
local bridgeActive = true
local visible = "overworld"
local ch = { dim=0.7, cool=0.2, warm=0.1, rain=1.0, snow=0.4, hail=0.3,
             sand=0.2, debris=0.2, ash=0.2, fog=1.0, veil=0.5, psy=0.6,
             glare=0.5, strike=0.4, gust=0.3, fogSpeed=0.5 }

local stubs = {}
stubs.Harden = { call=function(_,fn,...) local ok,r=pcall(fn,...); return ok,r end }
stubs.Scene = {
  now = { visible=visible, indoors=false, camX=0, camY=0 },
  viewport = { x=0,y=0,w=160,h=144,scale=1 },
  drawScale=function() return 1,true end,
}
stubs.WeatherState = { id="STORM", elapsed=1, ch=ch,
  isFogWeather=function() return true end }
stubs.Types = {
  strikeRate=function(id) return (id == "STORM") and 18 or 0 end,
  get=function(id) return { id=id, ch={ strike=(id == "STORM") and 18 or 0 } } end,
  channel=function(def,key) return (def and def.ch and def.ch[key]) or 0 end,
}
stubs.Settings = {
  force2dPresent=function() return mode=="2d" end,
  force3dPresent=function() return mode=="3d" end,
  presentMode=function() return mode end,
  get=function(_, key) if key==nil then key=_ end; if key=="lightning" then return "full" end; return nil end,
  is=function() return true end,
  fogOff=function() return false end,
  fogIntensity=function() return 1 end,
  intensity=function() return 1 end,
  isFirstPerson=function() return false end,
}
stubs.Config = {
  visual=function() return true end,
  get=function() return { splashSpread=1 } end,
  tuningFor=function() return { density=1 } end,
}
stubs.Quality = { update=function() end, budget=function() return { fogLayers=3 } end, tier=function() return "high" end }
stubs.Particles = {
  setRect=function() end, ready=function() return true end, update=function() end,
  draw=function() calls.particles=calls.particles+1 end, invalidate=function() end,
}
stubs.Lightning = {
  age=-1, tint=nil, update=function() end, flash=function() return 0 end,
  draw=function() calls.lightning=calls.lightning+1 end, reset=function() end,
}
stubs.Fog = {
  ready=function() return true end, setTint=function() end, resetTint=function() end,
  drawWorldField=function() calls.fog=calls.fog+1 end,
  draw=function() calls.fog=calls.fog+1 end, drawGround=function() calls.fog=calls.fog+1 end,
  invalidate=function() end,
}
stubs.Audio = { nudgeFromVisual=function() end }
stubs.DramalessAtmos = {}
stubs.TimeOfDay = { grade=function() return nil end }
stubs.BattleDraw = { live=false }
stubs.Legendary = { boltTint=function() return {1,1,1} end }
stubs.Funnel = { update=function() end, draw=function() calls.funnel=calls.funnel+1 end }
stubs.VoxelAtmosBridge = {
  active=function() return bridgeActive end,
  handlesPrecipitation=function() return true end,
  handlesSnow=function() return true end,
  handlesGrains=function() return true end,
  handlesLightning=function() return true end,
  handlesFog=function() return true end,
}

local V = { require=function(name) assert(stubs[name], "missing stub "..name); return stubs[name] end }
local src=assert(io.open(ROOT.."/lib/Draw.lua","rb")):read("*a")
local chunk=assert((loadstring or load)(src,"@Draw"))
local Draw=chunk(V)

local function syncVisible(v) visible=v; stubs.Scene.now.visible=v end

io.write("\nstrict 3D compositor\n")
mode="3d"; bridgeActive=true; syncVisible("overworld"); resetCalls()
check(Draw._strict3dPresent()==true, "explicit 3d + active host enters strict ownership")
Draw.pass(0,0,160,144,1,1,true)
eq(visualTotal(),0,"strict 3d submits zero 2d weather visuals")
resetCalls(); Draw.passPrecipitationOnly(0,0,160,144,1,1)
eq(calls.particles,0,"strict 3d clipped path submits zero 2d particles")
local filtered=Draw._filter2dPrecipChannels(ch)
eq(filtered.rain,0,"strict 3d zeros rain fallback")
eq(filtered.snow,0,"strict 3d zeros snow fallback")
eq(filtered.hail,0,"strict 3d zeros hail fallback")
eq(filtered.sand,0,"strict 3d zeros sand fallback")
eq(filtered.debris,0,"strict 3d zeros debris fallback")
eq(filtered.ash,0,"strict 3d zeros ash fallback")

io.write("\nauto and fallback semantics\n")
mode="auto"; bridgeActive=true; syncVisible("overworld"); resetCalls()
check(Draw._strict3dPresent()==false, "auto is not strict 3d")
Draw.pass(0,0,160,144,1,1,true)
check(visualTotal()>0, "auto retains 2d compositor/fallback capability")

mode="3d"; bridgeActive=false; syncVisible("overworld"); resetCalls()
check(Draw._strict3dPresent()==false, "3d without active host fails open to 2d")
Draw.pass(0,0,160,144,1,1,true)
check(visualTotal()>0, "unsupported host still gets visible 2d weather")

mode="3d"; bridgeActive=true; syncVisible("battle"); stubs.Scene.now.battleOpaque=true; resetCalls()
check(Draw._strict3dPresent()==false, "opaque/classic battle keeps dedicated 2d battle compositor")

mode="3d"; bridgeActive=true; syncVisible("battle"); stubs.Scene.now.battleOpaque=false; resetCalls()
check(Draw._strict3dPresent()==true, "world-backed voxel battle enters strict 3d ownership")
Draw.pass(0,0,160,144,1,1,true)
eq(visualTotal(),0,"world-backed voxel battle submits zero flat 2d weather visuals")
local battleFiltered=Draw._filter2dPrecipChannels(ch)
eq(battleFiltered.rain,0,"world-backed voxel battle suppresses 2d rain")
eq(battleFiltered.snow,0,"world-backed voxel battle suppresses 2d snow")
eq(battleFiltered.hail,0,"world-backed voxel battle suppresses 2d hail")

io.write(string.format("\n%d passed, %d failed\n",passed,failed))
os.exit(failed==0 and 0 or 1)
