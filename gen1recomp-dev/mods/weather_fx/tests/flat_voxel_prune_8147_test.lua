-- Weather FX 8.1.47 zero-visible-quality-loss runtime-pruning contract.
local passed,failed=0,0
local function check(v,msg)
  if v then passed=passed+1; print('PASS '..msg) else failed=failed+1; print('FAIL '..msg) end
end
local function approx(a,b) return math.abs((a or 0)-(b or 0)) < 1e-10 end
local ROOT='.'
local function loadmod(name,deps)
  local src=assert(io.open(ROOT..'/lib/'..name..'.lua','rb')):read('*a')
  local chunk=assert(load(src,'@lib/'..name..'.lua'))
  local V={require=function(n)
    local v=deps and deps[n]
    if v==nil then error('missing fake dependency '..n) end
    return v
  end}
  return chunk(V)
end

-- Volumetric aggregate must exist without resident detail, then materialize
-- exactly 75 cells only when the compatibility API is explicitly requested.
local meso={ready=function() return true end}
function meso.sampleInto(x,z,out)
  out.cloud=.64; out.precip=.52; out.storm=.31; return out
end
local VW=loadmod('VolumetricWeather',{MesoscaleField=meso})
VW.update(.016,120,240,{cloud=.5,precip=.4,storm=.2},{density=.7,charge=.4})
local before=VW.sample()
check(before.cells==75 and before.materializedCells==0,'volumetric aggregate keeps logical 75-cell coverage with zero resident cells')
check(before.cloudVolume>0 and before.precipVolume>0 and before.lightTransmission>0,'volumetric aggregate remains populated for renderer')
local cells=VW.cells()
local after=VW.sample()
check(#cells==75 and after.materializedCells==75,'cells() lazily materializes exact compatibility field')
check(approx(before.cloudVolume,after.cloudVolume) and approx(before.precipVolume,after.precipVolume) and approx(before.lightTransmission,after.lightTransmission),'materialization does not change renderer aggregate')
check(type(cells[1].charge)=='number' and type(cells[75].charge)=='number','materialized compatibility cells retain electrical detail')

-- LightProbeGrid remains formula-compatible but holds no 49-cell resident grid.
local U={peek=function() return {finalAmbient=.8,finalDiffuse=.6,specular=.25} end}
local LP=loadmod('LightProbeGrid',{UnifiedLighting=U})
local p=LP.sampleAt(144,96); local st=LP.stats()
check(st.cells==0 and st.virtualCells==49 and st.mode=='analytic-on-demand','light probe grid is virtual/on-demand')
check(p.ambient>0 and p.diffuse>0 and approx(p.specular,.25),'analytic probe still exposes lighting values')

-- Advisory modules still answer public/debug calls without continuous runtime.
local gov={peek=function() return {mode='manual',scale=.5} end,auto=function() return false end,particleScale=function() return .5 end}
local router={scale=function() return .5 end}
local host={capabilities=function() return {voxel=true,instancing=true,mesh=true} end}
local WS=loadmod('WorldStreamer',{PerformanceGovernor=gov,WorkloadRouter=router,HostAdapter=host})
local w=WS.sample()
check(w.visualScale==1 and w.physicsScale==1 and w.activeBands==4,'WorldStreamer manual-quality compatibility state remains exact/full-scale')
local GW=loadmod('GPUWeatherEngine',{Microclimate={peek=function() return {precip=.8} end},WorldStreamer=WS,PerformanceGovernor=gov,PredictiveBudget={particleScale=function() return .4 end},WorkloadRouter=router,HostAdapter=host})
local g=GW.sample()
check(g.densityScale==1 and g.backend=='instanced','GPUWeather advisory budget stays full under manual QUALITY')
local SV=loadmod('SurfaceVisuals',{SurfaceVisualState={peek=function() return {wet=.8,puddle=.3,snowHeight=.2,leafHeight=.1,mudDepth=.05,frost=.4,scorch=.1} end},WorldStreamer=WS,PerformanceGovernor=gov,WorkloadRouter=router})
local s=SV.sample()
check(approx(s.wetOverlay,.8) and approx(s.puddleCoverage,.3) and s.geometryBudget>0,'SurfaceVisuals compatibility summary remains available on demand')

print(string.format('8.1.47 flat-voxel prune executable: %d/%d passed',passed,passed+failed))
os.exit(failed==0 and 0 or 1)
