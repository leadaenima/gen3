local passed,failed=0,0
local function ck(v,m) if v then passed=passed+1 else failed=failed+1;print('FAIL '..m) end end
local captures={}
local function copyverts(v)
  local o={}; for i,row in ipairs(v or {}) do local r={};for j,x in ipairs(row) do r[j]=x end;o[i]=r end;return o
end
love={graphics={}}
local g=love.graphics
function g.newMesh(verts,...) local mesh={verts=copyverts(verts)};captures[#captures+1]=mesh
  function mesh:setVertices(v) self.verts=copyverts(v);captures[#captures+1]=self end
  function mesh:setDrawRange() end;function mesh:release() end;return mesh end
function g.getShader() return nil end;function g.setShader() end
function g.getDepthMode() return 'lequal',true end;function g.setDepthMode() end
function g.getBlendMode() return 'alpha','alphamultiply' end;function g.setBlendMode() end
function g.getColor() return 1,1,1,1 end;function g.setColor() end
function g.draw() return true end
function g.newShader() error('forced shader refusal') end
local V={safeBind=function() return pcall end,require=function() return {} end}
local NS=assert(loadfile('lib/NightSky.lua'))(V)
NS._projectedBodyShaderState=false;NS._projectedDepthShader=false
local function draw(kind,body)
  captures={};local q={};local n=NS._pushProjectedBodyQuad(q,0,80,60,18)
  local ok=NS._drawProjectedBody('_test'..kind,q,n,body,kind,90,kind=='moon' and 3 or 4.5)
  ck(ok,kind..' detailed fallback draws')
  ck(NS._lastProjectedBodyPath=='detailed-cpu-fallback',kind..' reports detailed CPU fallback')
  local best={}
  for _,m in ipairs(captures) do if #(m.verts or {})>#best then best=m.verts end end
  ck(#best>7000,kind..' fallback uses dense polar surface mesh')
  local seen={};local amin=1;local amax=0
  for _,r in ipairs(best) do
    local key=string.format('%.2f/%.2f/%.2f',r[5] or 0,r[6] or 0,r[7] or 0);seen[key]=true
    local a=r[8] or 0;if a<amin then amin=a end;if a>amax then amax=a end
  end
  local ncol=0;for _ in pairs(seen) do ncol=ncol+1 end
  ck(ncol>35,kind..' fallback has real surface colour variation')
  ck(amax>.5,kind..' fallback retains a bright visible surface')
  return ncol,amin,amax
end
local sc=draw('sun',{color={1,.82,.32},alpha=.95,solarEclipse=0})
local mc=draw('moon',{color={.82,.85,.90},alpha=.92,illumination=.62,phase=.36,solarEclipse=0,lunarEclipse=0})
print("colors",sc,mc); ck(mc>35,'moon fallback retains rich relief instead of four flat shades')
-- 2D facade must route through the exact same detailed body authority.
captures={};NS._projectedBodyShaderState=false;NS._projectedDepthShader=false
local ok2=NS.draw2DCelestialBody({x=70,y=35,_wxColor={.82,.85,.9},_wxAlpha=.9,_wxIllumination=.75,_wxPhase=.45,_wxAltitudeDeg=30},'moon',160,144,65,4)
ck(ok2 and NS._lastProjectedBodyPath=='detailed-cpu-fallback','2D body facade shares detailed fallback renderer')
print(('8.1.26 celestial fallback: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
