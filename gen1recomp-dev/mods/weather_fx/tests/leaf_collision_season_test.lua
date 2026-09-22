-- Weather FX 4.35.20 leaf collision / pile / seasonal colour regression.
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local passed, failed = 0, 0
local function check(ok, msg)
  if ok then passed=passed+1 else failed=failed+1; io.write("FAIL: ",msg,"\n") end
end

-- -------------------------------------------------------------------------
-- Gale is wind/rain/debris, never lightning.
-- -------------------------------------------------------------------------
local Types = assert(loadfile(ROOT.."lib/Types.lua"))()
check(Types.strikeRate("GALE") == 0, "GALE authored strike rate is zero")
check(Types.hasLightning("GALE") == false, "GALE is not lightning-capable")
local f=assert(io.open(ROOT.."lib/voxel_atmos/CinematicAtmos.lua","rb")); local cin=f:read("*a"); f:close()
local galeProfile = cin:match("gale%s*=%s*%b{}") or ""
check(galeProfile:find("storm=0.00",1,true)~=nil, "GALE atmospheric cloud profile has no lightning flash storm channel")
local af=assert(io.open(ROOT.."lib/Audio.lua","rb")); local audioSrc=af:read("*a"); af:close()
local galeBed=audioSrc:match("GALE%s*=%s*%b{}") or ""
check(galeBed:find('file = "rain_heavy"',1,true)~=nil and galeBed:find('file = "storm"',1,true)==nil,
      "GALE ambience is rain-only plus WindEngine, never the generic storm bed")

-- -------------------------------------------------------------------------
-- LeafPhysics uses voxel surface height and dynamic posed NPC bodies.
-- -------------------------------------------------------------------------
local calls=0
local VS={}
function VS.groundAt(map,cx,cz)
  calls=calls+1
  -- A one-cell-wide building column at X=2. Both endpoints of the tunnelling
  -- test are flat ground, so endpoint-only collision would miss it completely.
  if cx == 2 then return 20 end
  -- Corner-graze test: center path stays in cz=1, but the leaf footprint can
  -- overlap this raised cx=4,cz=2 cell.
  if cx == 4 and cz == 2 then return 20 end
  return 0
end
-- Root Weather FX loader deliberately DOES NOT expose VoxelScene. This mirrors
-- the installed architecture and guards the exact 4.35.20 false-positive test.
local V={}
function V.require(name)
  error("root loader has no host module "..tostring(name),0)
end
local LP=assert(loadfile(ROOT.."lib/LeafPhysics.lua"))(V)
check(math.abs(LP.NPC_MAX_CONTACT-2.0)<1e-6, "NPC contact hard cap is exactly two seconds")
check(LP.MAX_SETTLED_FRACTION <= 0.30, "pile cap preserves majority airborne leaves")
check(LP.SWEEP_STEP <= 0.5, "leaf collision uses sub-unit swept-path sampling")
check(LP.GROUND_SWEEP_STEP <= 0.5, "leaf ground collision uses sub-unit continuous sweep")
check(LP.LEAF_RADIUS >= 1.2, "leaf collision samples a physical footprint, not only particle center")
check(LP.PILE_MIN >= 35 and LP.PILE_MAX >= 90, "settled pile lifetime is at least five times the old 7-18 second window")

local map={def={width=8,height=8}}
local npc={def={sprite="SPRITE_LASS"},px=64,py=64,cellX=4,cellY=4}
local player={def={sprite="SPRITE_RED"},px=32,py=32,cellX=2,cellY=2}
local state={map=map,entities={player,npc},player=player,ghosts={}}
-- No `posed` list is supplied: Voxel Realism keeps it local inside render().
local ctx=LP.beginFrame({map=map,neighbors={},posed={},state=state,player=player},0,VS)
check(ctx.collisionEnabled==true,"host VoxelScene seam enables voxel collision even when root loader cannot resolve it")
check(#(ctx.npcs or {})==1,"NPC collision falls back to real state.entities when host posed list is private")
local inside, insideTop=LP.isPenetrating(ctx,40,5,20)
check(inside==true and insideTop>=20,"leaf spawned inside a building is detected before motion begins")
local free=LP.isPenetrating(ctx,20,5,20)
check(free==false,"ordinary free-space leaf is not falsely classified as embedded")

-- Tunnel completely through the one-cell building: start in cell 1, finish in
-- cell 3. A point/end-height test sees ground=0 at both ends; swept collision
-- must still stop the leaf on the air side of cell 2.
local pool={
  x={[1]=52}, y={[1]=5}, z={[1]=20},
  vx={[1]=30}, vy={[1]=0}, vz={[1]=0}, seed={[1]=0.5},
  leafSettled={[1]=false}, leafSettleT={[1]=0}, leafSettleLife={[1]=0},
  leafNpcT={[1]=0}, leafWallT={[1]=0},
}
local result=LP.resolve(pool,1,0.1,28,5,20,ctx,1,0,true)
check(result=="wall","swept leaf path detects a building even when both endpoints are outside it")
check(pool.x[1] < 32,"building collision leaves particle on the incoming side of the solid cell")
check(pool.vx[1] < 0,"wall collision weakly reflects incoming horizontal velocity")
check((pool.leafWallT[1] or 0)>0,"wall collision remembers obstacle contact for pile formation")

-- Footprint/corner collision: the particle CENTER never enters the raised cell
-- at cx=4,cz=2, but the leaf edge overlaps it. Center-line-only collision
-- would leak through; the 9-point footprint sweep must catch it.
local edge={
  x={[1]=84}, y={[1]=5}, z={[1]=31.2},
  vx={[1]=40}, vy={[1]=0}, vz={[1]=0}, seed={[1]=0.4},
  leafSettled={[1]=false}, leafSettleT={[1]=0}, leafSettleLife={[1]=0},
  leafNpcT={[1]=0}, leafWallT={[1]=0},
}
local er=LP.resolve(edge,1,0.1,60,5,31.2,ctx,1,0,true)
check(er=="wall","leaf footprint catches a glancing building-corner collision")
check(edge.x[1] < 64,"corner collision stops leaf before crossing the raised voxel footprint")

-- Continuous ground collision: a fast descending leaf must hit the floor at
-- the swept crossing point instead of ending underneath it or being recycled.
local gp={
  x={[1]=27}, y={[1]=-6}, z={[1]=12},
  vx={[1]=18}, vy={[1]=-28}, vz={[1]=5}, size={[1]=0.36}, seed={[1]=0.65},
  leafSettled={[1]=false}, leafSettleT={[1]=0}, leafSettleLife={[1]=0},
  leafNpcT={[1]=0}, leafWallT={[1]=0},
}
local gr=LP.resolve(gp,1,0.1,18,5,10,ctx,0.8,0.25,false)
local clearance=LP.groundClearance(gp,1)
check(gr=="ground-skip","fast descending leaf resolves as ground tumble/skip instead of passing through floor")
check(gp.y[1]>=clearance-1e-6,"ground collision keeps the visible leaf card above the terrain surface")
check(gp.vy[1]>0,"ground contact converts downward velocity into a bounded tumble bounce")
check(math.abs(gp.vx[1])+math.abs(gp.vz[1])>0.1,"ground contact preserves tangential WindEngine motion")

-- Same-cell high-speed vertical crossing uses the analytic fast path.
local gh=LP.sweptGround(ctx,20,7,20,20,-9,20,LP.GROUND_CLEARANCE_MIN)
check(gh and gh.sameCell==true and gh.y>=LP.GROUND_CLEARANCE_MIN,"same-cell vertical leaf tunnelling is caught analytically")

-- At the base after a recent wall hit, leaf becomes a temporary pile leaf.
pool.x[1],pool.z[1],pool.y[1]=31,20,0.1
result=LP.resolve(pool,1,0.1,31,0.4,20,ctx,1,0,true)
check(result=="settled" and pool.leafSettled[1]==true,"wall-hit leaf settles into obstacle-base pile")
check(pool.vx[1]==0 and pool.vy[1]==0 and pool.vz[1]==0,"settled pile leaf stops translating")
local y0=pool.y[1]
result=LP.resolve(pool,1,0.5,pool.x[1],pool.y[1],pool.z[1],ctx,1,0,true)
check(result=="settled" and pool.y[1]==y0,"pile leaf remains stable instead of tumbling through building")
pool.leafSettleT[1]=34.0; pool.leafSettleLife[1]=35.0
result=LP.resolve(pool,1,0.5,pool.x[1],pool.y[1],pool.z[1],ctx,1,0,true)
check(result=="settled","pile remains visible/alive well beyond the old 7-18 second lifetime")
pool.leafSettleT[1]=89.95; pool.leafSettleLife[1]=90.0
result=LP.resolve(pool,1,0.1,pool.x[1],pool.y[1],pool.z[1],ctx,1,0,true)
check(result=="expired-settle","long-lived pile still recycles cleanly at its new lifetime")
-- reset this slot for later tests
pool.leafSettled[1]=false; pool.leafSettleT[1]=0

-- Height cache: repeated sample of same cell should not keep calling the host.
local before=calls
LP.groundAt(ctx,18,18); LP.groundAt(ctx,18.5,18.5); LP.groundAt(ctx,19,19)
check(calls-before<=1,"voxel height samples are cached per cell for particle-scale performance")

-- NPC tunnelling: both endpoints are outside the actor cylinder but the segment
-- crosses straight through the visible body. This must register immediately.
local np={
  x={[1]=90}, y={[1]=7}, z={[1]=72},
  vx={[1]=35}, vy={[1]=0}, vz={[1]=0}, seed={[1]=0.2},
  leafSettled={[1]=false}, leafSettleT={[1]=0}, leafSettleLife={[1]=0},
  leafNpcT={[1]=0}, leafWallT={[1]=0},
}
local r=LP.resolve(np,1,0.1,54,7,72,ctx,0.7,0.2,true)
check(r=="npc","swept NPC collision catches a leaf crossing completely through an actor in one frame")
check(np.leafSettled[1]~=true,"leaf can never settle/pile on an NPC")

-- Continuous overlap is still forcibly ejected by the two-second cap.
local sawEject=false
for _=1,21 do
  np.x[1],np.y[1],np.z[1]=72,7,72
  local rr=LP.resolve(np,1,0.1,71,7,72,ctx,0.7,0.2,true)
  if rr=="npc-eject" then sawEject=true; break end
end
check(sawEject,"continuous NPC contact is forcibly ejected by two seconds")
check(np.leafSettled[1]~=true,"NPC contact never converts a leaf to settled state")
local dx,dz=np.x[1]-72,np.z[1]-72
check(dx*dx+dz*dz > LP.NPC_RADIUS*LP.NPC_RADIUS,"NPC ejection places leaf outside actor body")

-- Static integration assertions: WorldPrecip must resolve VoxelScene through its
-- VOXEL namespace and CinematicAtmos must forward the actual render state.
local wf=assert(io.open(ROOT.."lib/voxel_atmos/WorldPrecip.lua","rb")); local wsrc=wf:read("*a"); wf:close()
check((wsrc:find('pcall(V.require, "VoxelScene")',1,true)~=nil or (wsrc:find('safe(V.require, "VoxelScene")',1,true)~=nil or wsrc:find('V.safeCall(V.require, "VoxelScene")',1,true)~=nil)) and
      wsrc:find('LP.beginFrame, streamMeta, groundY, hostVoxelSceneModule()',1,true)~=nil,
      "WorldPrecip passes the host VoxelScene object into root LeafPhysics")
local cf=assert(io.open(ROOT.."lib/voxel_atmos/CinematicAtmos.lua","rb")); local csrc=cf:read("*a"); cf:close()
check((csrc:find("meta.player,meta.state,meta.Voxel3D=player,state,Voxel3D",1,true)~=nil
    or csrc:find("state = state",1,true)~=nil),
    "CinematicAtmos forwards real overworld state for NPC collision fallback")
local df=assert(io.open(ROOT.."lib/DramalessAtmos.lua","rb")); local dsrc=df:read("*a"); df:close()
check(dsrc:find("Atmos._lastState",1,true)~=nil and dsrc:find("Atmos._lastPlayer, Atmos._lastState",1,true)~=nil,
      "voxel scene wrapper forwards captured state into CinematicAtmos")
check(wsrc:find("(2.0 + random() * 2.8) * 5.0",1,true)~=nil and
      wsrc:find("(3.2 + random() * 4.2) * 5.0",1,true)~=nil,
      "airborne leaf lifetimes are five times the previous spawn windows")
check(wsrc:find("LP.isPenetrating",1,true)~=nil and wsrc:find("tries < 5",1,true)~=nil,
      "live leaf update repairs particles spawned inside building collision volume")
check(wsrc:find("grain.leafSettleT[i]",1,true)~=nil and wsrc:find("grain.leafSettleLife[i]",1,true)~=nil,
      "settled leaf draw lifetime is independent from airborne maxLife")

-- -------------------------------------------------------------------------
-- Seasonal colour is the default, explicit menu colours remain overrides.
-- -------------------------------------------------------------------------
local values={leafColor="seasonal"}
local season="SPRING"
local mod={options={get=function(_,k) return values[k] end},events={on=function() end},log={info=function() end,warn=function() end}}
local V2={mod=mod}
function V2.require(name)
  if name=="Types" then return Types end
  if name=="Seasons" then return {current=function() return season end} end
  error("unexpected require "..tostring(name),0)
end
local Settings=assert(loadfile(ROOT.."lib/Settings.lua"))(V2)
check((Settings.SCHEMA[11] and true)~=nil,"settings schema loads with seasonal leaf option")
local leafRow
for _,row in ipairs(Settings.SCHEMA) do if row.key=="leafColor" then leafRow=row end end
check(leafRow and leafRow.default=="seasonal","LEAF COLOR defaults to SEASONAL")
season="SPRING"; check(Settings.leafColor()=="green","spring leaves resolve green")
season="SUMMER"; check(Settings.leafColor()=="green","summer leaves resolve green")
season="AUTUMN"; check(Settings.leafColor()=="orange","autumn leaves resolve orange")
season="WINTER"; check(Settings.leafColor()=="brown","winter leaves resolve brown")
values.leafColor="yellow"; season="AUTUMN"
check(Settings.leafColor()=="yellow","explicit leaf colour overrides season")

io.write(string.format("leaf collision/season: %d passed, %d failed\n",passed,failed))
os.exit(failed==0 and 0 or 1)
