local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function check(v,n)
  if v then pass=pass+1; io.write('PASS ',n,'\n')
  else fail=fail+1; io.write('FAIL ',n,'\n') end
end

local defs={
  MAP_A={id='MAP_A',outdoor=true,tileset='OVERWORLD',widthCells=32,heightCells=32,connections={right={map='MAP_B',offset=0}},warps={}},
  MAP_B={id='MAP_B',outdoor=true,tileset='OVERWORLD',widthCells=32,heightCells=32,connections={left={map='MAP_A',offset=0},right={map='MAP_C',offset=0}},warps={}},
  MAP_C={id='MAP_C',outdoor=true,tileset='OVERWORLD',widthCells=32,heightCells=32,connections={left={map='MAP_B',offset=0}},warps={}},
}
local MapAPI={}
function MapAPI.isOutside(def) return def and def.outdoor==true end
function MapAPI.isOutdoor(def) return def and def.outdoor==true end
function MapAPI.defIsWaterCell() return false end
package.preload['src.world.Map']=function() return MapAPI end

local cfg={tornado={enabled=true,everySeconds=999,maxActive=4,formationSeconds=8,roamSeconds=180,ropeSeconds=12,carryChance=0,waterTwister=true}}
local weather={id='GALE'}
local scene={now={visible='world',indoors=false,outdoor=true,mapId='MAP_A'}}
local settings={is=function(k,v) return k=='tornado' and v=='on' end,isFirstPerson=function() return true end,force2dPresent=function() return false end,allow3dPresent=function() return true end}
local bridge={presentation3d=function() return true end,active=function() return true end}
local flat={ready=function() return true end,sampleAt=function(x,z,out) out=out or {};out.water=false;out.solid=false;out.canopy=false;out.roof=false;out.shelter=0;out.drag=1;out.groundY=0;return out end}
local wind={direction=function() return 1,0 end}
local player={px=64,py=160,cellX=4,cellY=10,facing='right'}
local mapA={id='MAP_A',widthCells=32,heightCells=32}
local mapB={id='MAP_B',widthCells=32,heightCells=32}
local mapC={id='MAP_C',widthCells=32,heightCells=32}
local stateA={map=mapA,player=player,neighbors={{map=mapB,ox=512,oy=0}}}
local stateB={map=mapB,player=player,neighbors={{map=mapA,ox=-512,oy=0},{map=mapC,ox=512,oy=0}}}
local stateC={map=mapC,player=player,neighbors={{map=mapB,ox=-512,oy=0}}}
local ow={map=mapA,player=player}
function scene.overworld() return ow end
local modules={Config={get=function() return cfg end},Settings=settings,WeatherState={current=function() return weather end},Scene=scene,VoxelAtmosBridge=bridge,FlatWorldInteraction=flat,WindEngine=wind}
local save={d={}}
function save:set(k,v) self.d[k]=v end
function save:get(k,d) local v=self.d[k];if v==nil then return d end;return v end
local mod={game={data={maps=defs,field={outsideTilesets={OVERWORLD=true},tilesets={OVERWORLD={}}}}},save=save,hooks={wrap=function() end}}
local V={mod=mod,require=function(n) if modules[n] then return modules[n] end error('unexpected require '..tostring(n),0) end}
local T=assert(loadfile(ROOT..'lib/Tornado.lua'))(V)
T._setRandom(function() return .5 end)
T.observeVoxelState(stateA)
local list=T.renderState()
local r={id=1,x=470,z=160,mapId='MAP_A',age=20,formation=8,roamFor=180,ropeFor=12,stage='roam',roamAge=20,ropeAge=0,seeker=false,heading=0,speed=32,spin=4.1,waterBlend=0,groundY=0,wander=0}
list[1]=r
T._gale=true
T.nextSpawn=9999 -- keep the fixture to exactly one tornado
T.update(.05) -- establishes map-local ownership while A is the live root
check(tonumber(r.mapX)~=nil and tonumber(r.mapZ)~=nil,'visible tornado records map-local coordinates')
local aLocal=r.mapX

-- Player walks A -> B -> C while tornado remains back on A. A is no longer in
-- C's current+neighbor render set, so this is the exact two-hop persistence seam.
scene.now.mapId='MAP_B'; ow.map=mapB; T.observeVoxelState(stateB); T.update(.05)
scene.now.mapId='MAP_C'; ow.map=mapC; T.observeVoxelState(stateC)
local beforeX=r.mapX
T.update(.25)
check(r.mapId=='MAP_A','remote tornado keeps ownership of its real source map')
check(r.offscreen==true,'two-hop remote tornado is explicitly offscreen instead of rendered in the wrong root frame')
check(r.mapX and r.mapX>beforeX+5,'remote tornado keeps physically moving while player is two maps away')
check(r.roamAge>20.3,'remote tornado lifecycle keeps aging while offscreen')

-- Continue east far enough to leave A. The offscreen simulator must use the
-- authored outdoor A -> B connection instead of freezing at A's unseen edge.
for _=1,8 do T.update(.25) end
check(r.mapId=='MAP_B','remote tornado crosses authored outdoor connection while offscreen')
check((r.mapCrossings or 0)>=1,'offscreen map crossing increments persistent crossing telemetry')
check((r.offscreenCrossings or 0)>=1,'offscreen crossing is separately auditable')

-- B is an immediate neighbor of current C, so the same entity should project
-- back into the live root frame without respawn/reset once it reaches B.
T.update(.05)
check(r.offscreen==false,'remote tornado becomes render-visible when its map enters current neighbor set')
check(r.id==1 and r.stage=='roam','re-entry preserves tornado identity and lifecycle stage')
check(r.age>20 and r.roamAge>20,'re-entry preserves accumulated lifetime instead of respawning')
local status=T.worldPersistenceStatus()
check((status.offscreen or 0)==0 and (status.offscreenCrossings or 0)>=1,'persistence diagnostics expose remote roaming/crossing state')

io.write(string.format('tornado remote map roam 8.1.65: %d passed, %d failed\n',pass,fail))
os.exit(fail==0 and 0 or 1)
