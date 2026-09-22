local V=...

-- Bounded secondary precipitation for Weather FX 8.1.88.
-- Owns only roof/canopy beads and their tiny render pool. Falling rain, terrain,
-- wind and surface wetness remain owned by the existing authoritative systems.
local P={}
local floor,max,min,sqrt,cos,sin=math.floor,math.max,math.min,math.sqrt,math.cos,math.sin
local PI=math.pi;local TWO_PI=PI*2;local TILE=16;local MAX=128
local rng=428188
local function rand() rng=(rng*48271)%2147483647;return rng/2147483647 end
local function hash(x,z,s) local n=sin((x*127.1+z*311.7+s*74.7))*43758.5453123;return n-floor(n) end
local pool={n=0,alive={},x={},y={},z={},groundY={},age={},hang={},speed={},size={},kind={}}
local cursor=0
local live=0
local roofBudget,canopyBudget=0,0
local mesh,shader=nil,nil
local verts={};local rows={}

function P.impactProfile(kind,class,art)
  kind=tostring(kind or "ground"):lower();class=tostring(class or ""):lower();art=tostring(art or ""):lower();local text=class.." "..art
  if kind=="water" or text:find("water",1,true) then return "water",4,1.32,.56,1.04 end
  if kind=="ice" or text:find("ice",1,true) then return "ice",5,1.06,.34,1.12 end
  if kind=="tree" or kind=="grass" or text:find("grass",1,true) or text:find("plant",1,true) then return "grass",2,.58,.24,.58 end
  if kind=="raised" then
    if text:find("metal",1,true) then return "metal",3,.72,.25,1.28 end
    if text:find("wood",1,true) then return "wood",3,.72,.28,1.05 end
    return "roof",3,.72,.25,1.20
  end
  if text:find("road",1,true) or text:find("pave",1,true) then return "pavement",3,.82,.30,1.12 end
  if text:find("stone",1,true) or text:find("rock",1,true) or text:find("brick",1,true) then return "stone",3,.78,.30,1.10 end
  return "soil",1,.70,.30,.78
end

local function ensure()
  if pool.n==MAX then return end
  for i=pool.n+1,MAX do
    pool.alive[i]=false;pool.x[i],pool.y[i],pool.z[i],pool.groundY[i]=0,0,0,0
    pool.age[i],pool.hang[i],pool.speed[i],pool.size[i],pool.kind[i]=99,0,20,.1,1
  end
  pool.n=MAX
end
local function spawn(x,y,z,groundY,hang,size,kind)
  ensure();cursor=cursor%MAX+1;local i=cursor
  if not pool.alive[i] then live=live+1 end
  pool.alive[i]=true;pool.x[i],pool.y[i],pool.z[i]=x,y,z;pool.groundY[i]=tonumber(groundY) or (y-18)
  pool.age[i]=0;pool.hang[i]=max(.08,tonumber(hang) or .25);pool.speed[i]=18+rand()*13;pool.size[i]=max(.045,tonumber(size) or .075);pool.kind[i]=kind or 1
  return true
end
local DIR={{1,0},{0,1},{-1,0},{0,-1}}
local function findEave(ctx,SP,x,topY,z,seed)
  if not (ctx and SP and SP.surfaceAt) then return nil end
  local cx=floor((tonumber(x) or 0)/TILE)*TILE+TILE*.5;local cz=floor((tonumber(z) or 0)/TILE)*TILE+TILE*.5
  local pick=floor(hash(floor(cx/TILE),floor(cz/TILE),tonumber(seed) or 17)*4)+1
  for pass=0,3 do
    local d=DIR[((pick-1+pass)%4)+1];local dx,dz=d[1],d[2];local px,pz=cx,cz
    for step=1,4 do
      local nx,nz=cx+dx*TILE*step,cz+dz*TILE*step;local ny,nk=SP.surfaceAt(ctx,nx,nz);ny=tonumber(ny) or (ctx.fallbackGroundY or 0)
      if nk~="raised" or ny<(tonumber(topY) or ny)-1.25 then return px+dx*TILE*.48,(tonumber(topY) or ny)-.18,pz+dz*TILE*.48,ny end
      px,pz=nx,nz
    end
  end
end
function P.spawnRoof(ctx,SP,x,topY,z,seed,force)
  if roofBudget<=0 then return false end
  if not force and rand()>.30 then return false end
  roofBudget=roofBudget-1
  local ex,ey,ez,gy=findEave(ctx,SP,x,topY,z,seed);if not ex then return false end
  return spawn(ex,ey,ez,gy,.14+rand()*.36,.055+rand()*.045,2)
end
function P.spawnCanopy(ctx,x,topY,z,force)
  if canopyBudget<=0 then return false end
  if not force and rand()>.24 then return false end
  canopyBudget=canopyBudget-1
  local gy=ctx and tonumber(ctx.fallbackGroundY) or ((tonumber(topY) or 0)-18)
  return spawn(x+(rand()-.5)*5,(tonumber(topY) or gy+16)-.8,z+(rand()-.5)*5,gy,.28+rand()*.95,.060+rand()*.055,3)
end

function P.update(dt,ctx,SP,px,pz,impact)
  dt=max(0,min(.25,tonumber(dt) or 0));if dt<=0 then return end
  -- Direct rain contacts can be numerous on a broad roof. Bound expensive eave
  -- edge searches per update; retained water still drains over later frames.
  roofBudget,canopyBudget=3,8
  local ok,WI=pcall(V.require,"WeatherWorldInteraction");local st=ok and WI and WI.peek and WI.peek() or nil
  if st and ctx and SP and SP.surfaceAt then
    local roof=max(0,tonumber(st.roofDrip) or 0);local canopy=max(0,tonumber(st.canopyDrip) or 0);local total=roof*3.8+canopy*3.1
    if total>.01 then
      local want=total*dt;local tries=floor(want);if rand()<(want-tries) then tries=tries+1 end;if tries>2 then tries=2 end
      for _=1,tries do
        local a=rand()*TWO_PI;local r=(rand()^.55)*82;local x=(tonumber(px) or 0)+cos(a)*r;local z=(tonumber(pz) or 0)+sin(a)*r;local y,kind=SP.surfaceAt(ctx,x,z)
        if kind=="raised" and roof>0 and rand()<(roof/(roof+canopy+.001)) then P.spawnRoof(ctx,SP,x,y,z,a*97,true)
        elseif kind=="tree" and canopy>0 then P.spawnCanopy(ctx,x,y,z,true) end
      end
    end
  end
  ensure()
  for i=1,MAX do
    if pool.alive[i] then
      pool.age[i]=pool.age[i]+dt
      if pool.age[i]>pool.hang[i] then
        local fall=pool.age[i]-pool.hang[i];pool.y[i]=pool.y[i]-pool.speed[i]*dt*(1+min(1.8,fall*.75))
        if pool.y[i]<=pool.groundY[i]+.08 then
          if type(impact)=="function" then impact(pool.x[i],pool.groundY[i]+.04,pool.z[i],pool.size[i]*4.4,pool.kind[i]==3 and "grass" or "ground") end
          pool.alive[i]=false;live=max(0,live-1)
        end
      end
      if pool.alive[i] and pool.age[i]>7 then pool.alive[i]=false;live=max(0,live-1) end
    end
  end
end
function P.pool() return pool end

local FORMAT={{"VertexPosition","float",3},{"RainTint","float",4}}
local SHADER=[[
#ifdef VERTEX
  extern mat4 vp;attribute vec4 RainTint;varying vec4 vCol;
  vec4 position(mat4 t,vec4 v){vCol=RainTint;return vp*vec4(v.xyz,1.0);}
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color,Image tex,vec2 tc,vec2 sc){float along=clamp(vCol.g,0.0,1.0);float x=abs(vCol.b*2.0-1.0);float side=1.0-smoothstep(.15,1.0,x);float ends=smoothstep(.01,.16,along)*(1.0-smoothstep(.90,1.0,along));return vec4(.62,.72,.82,vCol.a*side*ends)*color;}
#endif
]]
local function getShader()
  if shader~=nil then return shader or nil end
  if not (love and love.graphics and love.graphics.newShader) then shader=false;return nil end
  local ok,sh=V.safeCall(love.graphics.newShader,SHADER);shader=(ok and sh) or false;return shader or nil
end
local function put(n,x,y,z,r,g,b,a)
  local row=rows[n];if not row then row={0,0,0,0,0,0,0};rows[n]=row end
  row[1],row[2],row[3],row[4],row[5],row[6],row[7]=x,y,z,r,g,b,a;verts[n]=row
end
function P.draw(Voxel3D)
  if live<=0 then return false end
  if not (Voxel3D and Voxel3D.vp and love and love.graphics) then return false end
  local sh=getShader();if not sh then return false end;ensure();local eye=Voxel3D.eye;local ex,ez=eye and (eye[1] or 0) or 0,eye and (eye[3] or 0) or 0;local n=0
  for i=1,MAX do
    if pool.alive[i] then
      local x,y,z=pool.x[i],pool.y[i],pool.z[i];local age,hang=pool.age[i] or 0,pool.hang[i] or 0;local dx,dz=ex-x,ez-z;local dl=sqrt(dx*dx+dz*dz);local rx,rz=1,0;if dl>1e-4 then rx,rz=-dz/dl,dx/dl end
      local falling=age>hang;local len=falling and pool.size[i]*5 or pool.size[i]*1.6;local half=max(.018,pool.size[i]*.25);local y0,y1=y-len*.5,y+len*.5;local a=falling and .54 or .36
      put(n+1,x-rx*half,y0,z-rz*half,1,0,0,a);put(n+2,x+rx*half,y0,z+rz*half,1,0,1,a);put(n+3,x+rx*half,y1,z+rz*half,1,1,1,a)
      put(n+4,x-rx*half,y0,z-rz*half,1,0,0,a);put(n+5,x+rx*half,y1,z+rz*half,1,1,1,a);put(n+6,x-rx*half,y1,z-rz*half,1,1,0,a);n=n+6
    else
      for k=1,6 do put(n+k,0,0,0,1,0,0,0) end;n=n+6
    end
  end
  if not mesh then local ok,m=V.safeCall(love.graphics.newMesh,FORMAT,verts,"triangles","stream");if not ok then return false end;mesh=m else local ok=V.safeCall(mesh.setVertices,mesh,verts);if not ok then return false end end
  V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply");V.safeCall(love.graphics.setDepthMode,"lequal",false)
  if Voxel3D.beginEffect(sh) then V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp);local ok=V.safeCall(love.graphics.draw,mesh);Voxel3D.endEffect();return ok end
  return false
end

function P.invalidate() mesh,shader=nil,nil end
function P.stats() return {active=live,max=MAX,roofBudget=roofBudget,canopyBudget=canopyBudget} end
return P
