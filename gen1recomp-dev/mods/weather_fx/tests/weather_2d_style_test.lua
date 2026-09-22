-- Weather FX 4.31.7: executable 2D-only visual contract.
-- Proves the requested snow/rain sizing, procedural particle atlas silhouettes,
-- and sand-coloured 2D haze without exercising or changing the 3D renderer.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; io.write("FAIL: ", msg, "\n") end
end
local function near(a,b,eps) return math.abs((a or 0)-(b or 0)) <= (eps or 1e-5) end

local function particleHarness(randValue)
  local atlasData, adds, drawCalls = nil, {}, 0
  love = {
    math = { random = function() return randValue or 0.5 end },
    image = {
      newImageData = function(w,h)
        local d = {w=w,h=h,p={}}
        function d:setPixel(x,y,r,g,b,a) self.p[y*w+x] = {r,g,b,a} end
        function d:getPixel(x,y)
          local v=self.p[y*w+x] or {0,0,0,0}
          return v[1],v[2],v[3],v[4]
        end
        atlasData=d
        return d
      end,
    },
    graphics = {
      newImage = function() return {setFilter=function() end} end,
      newQuad = function(x,y,w,h,tw,th) return {x=x,y=y,w=w,h=h,tw=tw,th=th,__quad=true} end,
      newSpriteBatch = function()
        return {
          clear=function() adds={} end,
          setColor=function() end,
          add=function(self,...)
            local a={...}; adds[#adds+1]=a
          end,
        }
      end,
      setBlendMode=function() end,
      setColor=function() end,
      draw=function() drawCalls=drawCalls+1 end,
    },
  }
  local P = assert(loadfile(ROOT .. "lib/Particles.lua"))({})
  P.setRect(160,144,1)
  return P, function() return atlasData end, function() return adds end, function() return drawCalls end
end

local budget={rain=100,snow=100,grain=100,splash=0}

-- Snow: full restored pool, exactly 2x old rendered diameter, round atlas cell.
do
  local P,getData,getAdds = particleHarness(0.5)
  local ch={snow=1,snowSpeed=1,snowDrift=0.6}
  P.update(1/60,ch,budget,0,0,0,false)
  check(select(2,P.counts())==100,"2D snow restores the full quality-tier particle budget")
  P.draw(1,ch)
  local adds=getAdds()
  check(#adds==100,"round 2D snow uses one atlas sprite per flake at the restored full population")
  local a=adds[1]
  check(type(a[1])=="table" and a[1].x==32,"2D snow draw selects the round atlas silhouette")
  local depth=1-(math.floor(0.5*20)/19)
  local sz=(0.45+(0.81-0.45)*0.5)*(0.55+depth*0.55)
  local oldDiameter=sz*(0.75+depth*0.55)
  local newDiameter=(a[5] or 0)*32
  check(near(newDiameter,oldDiameter*2,1e-5),"2D snow rendered diameter is exactly doubled")
  local d=getData(); local _,_,_,corner=d:getPixel(32,0); local _,_,_,center=d:getPixel(47,15)
  check(corner<0.02 and center>0.8,"2D snow atlas is circular/alpha-masked rather than square")
end

-- Heavy snow may fill the restored pool but cannot exceed the quality-tier budget.
do
  local P=particleHarness(0.5)
  P.update(1/60,{snow=9,snowSpeed=1,snowDrift=1},budget,0,0,0,false)
  check(select(2,P.counts())==100,"BLIZZARD/THUNDERSNOW fills but cannot exceed the restored 2D snow budget")
end

-- Rain: final rendered width is 1.5x the old post-clamp width.
do
  local P,_,getAdds=particleHarness(0.5)
  local ch={rain=1,rainSpeed=1,rainAngle=0,rainLen=1,splash=0}
  P.update(1/60,ch,budget,0,0,0,false); P.draw(1,ch)
  local a=getAdds()[1]
  check(type(a[1])=="table" and a[1].x==0,"2D rain uses the solid atlas cell")
  local renderedThickness=(a[6] or 0)*8
  check(near(renderedThickness,1.5,1e-5),"2D rain is 50% thicker after the old minimum-pixel clamp")
end

-- Hail: circular icy atlas body with a cool rim and specular highlight.
do
  local P,getData,getAdds=particleHarness(0.5)
  local ch={hail=1}
  P.update(1/60,ch,budget,0,0,0,true); P.draw(1,ch)
  local a=getAdds()[1]
  check(type(a[1])=="table" and a[1].x==64,"2D hail selects the procedural ice-sphere atlas cell")
  local d=getData(); local _,_,_,corner=d:getPixel(64,0); local _,_,_,center=d:getPixel(79,15)
  local hr,hg,hb,ha=d:getPixel(75,11); local lr,lg,lb,la=d:getPixel(84,20)
  check(corner<0.02 and center>0.8,"2D hail has a round hard body rather than a square")
  check(ha>0.2 and (hr+hg+hb)>(lr+lg+lb),"2D hail carries an upper-left ice highlight like the 3D hail model")
end

-- Gray and black ash: both must use one of three irregular cinder silhouettes.
local function ashCase(randValue, wantedKind, label)
  local P,getData,getAdds=particleHarness(randValue)
  local ch={ash=1}
  P.update(1/60,ch,budget,0,0,0,false); P.draw(1,ch)
  local kc=P.kindCounts()
  check((kc[wantedKind] or 0)>0,label.." is present in the active grain pool")
  local seen=false
  local ashAdd=nil
  for _,a in ipairs(getAdds()) do
    if type(a[1])=="table" and (a[1].x==96 or a[1].x==128 or a[1].x==160) then seen=true; ashAdd=a; break end
  end
  check(seen,label.." draws an irregular 3D-inspired cinder atlas silhouette")
  if ashAdd then
    -- Particle harness uses a deterministic random seed, so compare the final
    -- atlas scale against the pre-4.31.6 ash size formula.
    local renderedW=(ashAdd[5] or 0)*32
    local renderedH=(ashAdd[6] or 0)*32
    local depth=1-(math.min(19,math.floor(randValue*20))/19)
    local grainSz=(1.19+(2.17-1.19)*randValue)*(0.52+depth*0.58)
    local drawS=grainSz*(0.72+depth*0.50)
    local seed=(randValue*6.283185307179586)
    local oldW=drawS*(0.85+(seed%0.55))
    local oldH=drawS*(0.70+((seed*0.41)%0.50))
    check(near(renderedW,oldW*2,1e-4) and near(renderedH,oldH*2,1e-4),label.." is exactly 100% larger than the 4.31.5 cinder")
  end
  local d=getData()
  for _,x0 in ipairs({96,128,160}) do
    local nonzero=0
    for y=0,31 do for x=0,31 do local _,_,_,aa=d:getPixel(x0+x,y); if aa>0.05 then nonzero=nonzero+1 end end end
    check(nonzero>80 and nonzero<700,"ash silhouette cell is irregular/holed, not a filled square")
  end
end
ashCase(0.50,4,"gray 2D ash")
ashCase(0.75,5,"black 2D ash")

-- Sandstorm/duststorm: use a wrapping world-anchored bank field and NEVER a
-- full-screen sandy veil. The compositor must choose the local-bank path.
do
  local worldCalls, flatFogCalls, tint, rectColors = 0,0,nil,{}
  local current={1,1,1,1}
  love={math={random=function() return 0.5 end},graphics={
    getColor=function() return 1,1,1,1 end,getBlendMode=function() return "alpha","alphamultiply" end,
    setBlendMode=function() end,setColor=function(r,g,b,a) current={r,g,b,a or 1} end,
    push=function() end,pop=function() end,translate=function() end,
    rectangle=function() rectColors[#rectColors+1]={current[1],current[2],current[3],current[4]} end,
    newMesh=function() return {setVertices=function() end} end,draw=function() end,
  }}
  local mods={}
  mods.Scene={now={visible="world",indoors=false,camX=-80,camY=-40}}
  mods.WeatherState={id="SANDSTORM",elapsed=3,ch={sand=1,veil=0.72,warm=0.35,gust=1},isFogWeather=function() return false end}
  mods.Settings={get=function() return "on" end,force2dPresent=function() return true end,fogOff=function() return false end,
    fogIntensity=function() return 1 end,intensity=function() return 1 end,isFirstPerson=function() return false end}
  mods.Config={visual=function() return true end}
  mods.Quality={budget=function() return {fogLayers=2} end,tier=function() return "high" end}
  mods.Particles={ready=function() return true end,setRect=function() end,draw=function() end}
  mods.Lightning={flash=function() return 0 end,draw=function() end,age=-1}
  mods.Fog={ready=function() return true end,
    draw=function() flatFogCalls=flatFogCalls+1 end,
    drawWorldField=function(amount,alpha,layers,t,camX,camY,scale,w,h,speedCh,motionMul,intensityMul)
      worldCalls=worldCalls+1
      check(amount>0,"SANDSTORM derives nonzero 2D world haze from sand/veil")
      check(camX==-80 and camY==-40,"world haze receives live camera translation")
      check(near(motionMul or 1,1,0.0001) and near(intensityMul or 1,1,0.0001),
        "sand/dust keeps its existing world-bank speed and intensity")
    end,
    drawGround=function() end,setTint=function(r,g,b,dir,camDir) tint={r,g,b,dir,camDir} end,resetTint=function() end}
  mods.Types={strikeRate=function() return 0 end,get=function() return {ch={strike=0}} end,channel=function(def,key) return (def and def.ch and def.ch[key]) or 0 end}
  mods.Audio={}; mods.TimeOfDay={grade=function() return nil end}; mods.BattleDraw={live=false}
  mods.Legendary={boltTint=function() return nil end}; mods.Funnel={draw=function() return false end}; mods.Rainbow={}
  local V={}; function V.require(name) if mods[name] then return mods[name] end error("optional "..tostring(name),0) end
  local Draw=assert(loadfile(ROOT.."lib/Draw.lua"))(V)
  local ok,err=pcall(Draw.pass,0,0,640,480,4,1,true)
  check(ok,"2D sandstorm compositor executes: "..tostring(err))
  check(worldCalls>0,"2D SANDSTORM uses the world-anchored haze field")
  check(flatFogCalls==0,"2D SANDSTORM does not use the old viewport-sized fog quad")
  check(tint and tint[1]>tint[2] and tint[2]>tint[3],"2D sand world banks use a warm sandy tint")
  local sandyVeil=false
  for _,c in ipairs(rectColors) do
    if near(c[1],0.80,0.02) and near(c[2],0.64,0.02) and near(c[3],0.36,0.02) then sandyVeil=true end
  end
  check(not sandyVeil,"2D sandstorm no longer paints a flat full-screen sandy veil")

  mods.WeatherState.id="DUSTSTORM"
  mods.WeatherState.ch={sand=1,veil=0.72,warm=0.25,gust=1}
  tint=nil; worldCalls=0; flatFogCalls=0
  local okDust,errDust=pcall(Draw.pass,0,0,640,480,4,1,true)
  check(okDust,"2D duststorm compositor executes: "..tostring(errDust))
  check(worldCalls>0 and flatFogCalls==0,"2D DUSTSTORM uses world banks rather than a viewport fog quad")
  check(tint and tint[1]>tint[2] and tint[2]>tint[3],"2D dust world banks keep a warm brown tint")
end

-- All remaining active 2D haze-family weather must use the same wrapping
-- world-bank path. None may fall back to a viewport fog quad or flat veil.
do
  local profiles={
    FOG={ch={fog=1.0,fogSpeed=0.55,veil=0.12,dim=0.09,cool=0.06}, tint=function(v) return v[3]>v[1] and v[3]>v[2] end},
    MIST={ch={fog=0.45,fogSpeed=0.4,veil=0.06,dim=0.05}, tint=function(v) return v[1]>0.85 and v[2]>0.88 and v[3]>0.90 end},
    SMOG={ch={fog=1.0,fogSpeed=0.7,veil=0.30,dim=0.18,warm=0.05}, tint=function(v) return v[2]>v[1] and v[1]>v[3] end},
    HAUNTED_MIST={ch={fog=1.0,fogSpeed=0.22,veil=0.22,dim=0.20,cool=0.32,debris=0.12}, tint=function(v) return v[3]>v[2] and v[2]>v[1] end},
  }
  local current={1,1,1,1}; local rectColors={}
  love={math={random=function() return 0.5 end},graphics={
    getColor=function() return 1,1,1,1 end,getBlendMode=function() return "alpha","alphamultiply" end,
    setBlendMode=function() end,setColor=function(r,g,b,a) current={r,g,b,a or 1} end,
    push=function() end,pop=function() end,translate=function() end,
    rectangle=function() rectColors[#rectColors+1]={current[1],current[2],current[3],current[4]} end,
    newMesh=function() return {setVertices=function() end} end,draw=function() end,
  }}
  local mods={}
  mods.Scene={now={visible="world",indoors=false,camX=640,camY=576}}
  mods.WeatherState={id="FOG",elapsed=9,ch=profiles.FOG.ch,
    isFogWeather=function(id) return profiles[tostring(id or ""):upper()]~=nil end}
  mods.Settings={get=function() return "on" end,force2dPresent=function() return true end,fogOff=function() return false end,
    fogIntensity=function() return 1 end,intensity=function() return 1 end,isFirstPerson=function() return false end}
  mods.Config={visual=function() return true end}
  mods.Quality={budget=function() return {fogLayers=3} end,tier=function() return "high" end}
  mods.Particles={ready=function() return true end,setRect=function() end,draw=function() end}
  mods.Lightning={flash=function() return 0 end,draw=function() end,age=-1}
  local worldCalls,flatFogCalls,groundFogCalls,tint=0,0,0,nil
  mods.Fog={ready=function() return true end,
    draw=function() flatFogCalls=flatFogCalls+1 end,
    drawGround=function() groundFogCalls=groundFogCalls+1 end,
    drawWorldField=function(amount,alpha,layers,t,camX,camY,scale,w,h,speedCh,motionMul,intensityMul)
      worldCalls=worldCalls+1
      check(amount>0 and alpha>0,"fog-family world haze receives nonzero density")
      check(camX==640 and camY==576,"fog-family world haze receives live camera translation")
      check(near(motionMul or 1,0.25,0.0001),"fog-family haze autonomous wind speed is reduced another 50% (25% of original)")
      check(near(intensityMul or 1,3.0,0.0001),"fog-family haze bank intensity is increased by 200% (3x)")
    end,
    setTint=function(r,g,b,dir,camDir) tint={r,g,b,dir,camDir} end,resetTint=function() end}
  mods.Types={strikeRate=function() return 0 end,get=function() return {ch={strike=0}} end,channel=function(def,key) return (def and def.ch and def.ch[key]) or 0 end}
  mods.Audio={}; mods.TimeOfDay={grade=function() return nil end}; mods.BattleDraw={live=false}
  mods.Legendary={boltTint=function() return nil end}; mods.Funnel={draw=function() return false end}; mods.Rainbow={}
  local V={}; function V.require(name) if mods[name] then return mods[name] end error("optional "..tostring(name),0) end
  local Draw=assert(loadfile(ROOT.."lib/Draw.lua"))(V)

  for id,p in pairs(profiles) do
    mods.WeatherState.id=id; mods.WeatherState.ch=p.ch
    worldCalls,flatFogCalls,groundFogCalls,tint=0,0,0,nil; rectColors={}
    local ok,err=pcall(Draw.pass,0,0,640,480,4,1,true)
    check(ok,"2D "..id.." compositor executes: "..tostring(err))
    check(worldCalls>0,"2D "..id.." uses wrapping world haze banks")
    check(flatFogCalls==0 and groundFogCalls==0,"2D "..id.." does not use viewport/ground overlay fog")
    check(tint and p.tint(tint),"2D "..id.." keeps a distinct world-bank tint")
    local flatVeil=false
    for _,c in ipairs(rectColors) do
      if near(c[1],0.86,0.01) and near(c[2],0.88,0.01) and near(c[3],0.92,0.01) then flatVeil=true end
    end
    check(not flatVeil,"2D "..id.." does not paint a flat full-screen haze veil")
  end
end

-- World-field geometry contract. A screen overlay is one viewport-sized quad;
-- the replacement must be many LOCAL banks whose vertices themselves shift
-- opposite camera/player movement. This checks geometry, not just UV motion.
do
  local function sampleField(camX,camY,t,motionMul,intensityMul,amount,alpha)
    local draws={}
    love={
      image={newImageData=function()
        return {mapPixel=function() end}
      end},
      graphics={
        newImage=function() return {setFilter=function() end,setWrap=function() end} end,
        newMesh=function()
          local m={last=nil}
          function m:setTexture() end
          function m:setVertices(v) self.last=v end
          return m
        end,
        setBlendMode=function() end,setColor=function() end,
        draw=function(m)
          local cp={}
          for i,v in ipairs(m.last or {}) do local q={}; for j,x in ipairs(v) do q[j]=x end; cp[i]=q end
          draws[#draws+1]=cp
        end,
      },
    }
    local Fog=assert(loadfile(ROOT.."lib/Fog.lua"))({})
    Fog.setTint(0.85,0.72,0.48,1,-1)
    local count=Fog.drawWorldField(amount or 1,alpha or 1,3,t or 0,camX or 0,camY or 0,4,640,480,0.5,motionMul,intensityMul)
    return draws,count
  end

  local a,ac=sampleField(0,0,0)
  check(ac and ac>=8 and #a==ac,"sand/dust world haze is composed of many local banks")
  local localOnly=true
  for _,v in ipairs(a) do
    if v[1] and v[2] and v[3] then
      local bw=math.abs(v[2][1]-v[1][1]); local bh=math.abs(v[4][2]-v[1][2])
      if bw>=620 and bh>=460 then localOnly=false end
    end
  end
  check(localOnly,"world haze contains no viewport-sized overlay quad")

  -- Tiny camera translation avoids a cell-boundary rollover. Match banks by
  -- their stable per-world-cell UV seed; this proves the SAME haze bank moves
  -- in geometry, rather than comparing two unrelated screen populations.
  local b=sampleField(2,2,0)
  local function keyed(draws)
    local out={}
    for _,v in ipairs(draws) do
      if v[1] and v[3] then
        local key=string.format("%.6f:%.6f",v[1][3] or 0,v[1][4] or 0)
        out[key]={(v[1][1]+v[3][1])*0.5,(v[1][2]+v[3][2])*0.5}
      end
    end
    return out
  end
  local ka,kb=keyed(a),keyed(b)
  local matched,west,north=0,0,0
  for key,p1 in pairs(ka) do
    local p2=kb[key]
    if p2 then
      matched=matched+1
      if p2[1] < p1[1] then west=west+1 end
      if p2[2] < p1[2] then north=north+1 end
    end
  end
  check(matched>=8,"world haze preserves stable world-cell identities while walking")
  check(west==matched,"each matched world haze bank moves west when player/camera travels east")
  check(north==matched,"each matched world haze bank moves north when player/camera travels south")

  -- Visibility must survive real map traversal, not only cameras near 0,0.
  -- 4.31.8 inverted the final bank transform but left culling on the old sign,
  -- which selected cells from the opposite side of the world and reduced the
  -- field to zero once camera translation grew beyond roughly one viewport.
  for _,pos in ipairs({
    {160,144},{320,288},{640,576},{1024,768},
    {-160,-144},{-320,-288},{-640,-576},{-1024,-768},
  }) do
    local far,farCount=sampleField(pos[1],pos[2],0)
    check(farCount and farCount>=8 and #far==farCount,
      string.format("world haze remains populated at camera offset %d,%d",pos[1],pos[2]))
  end

  -- Autonomous wind must also move actual geometry while the camera is still.
  local c=sampleField(0,0,1.0)
  local kc=keyed(c); local drifted=false
  for key,p1 in pairs(ka) do
    local p2=kc[key]
    if p2 and (not near(p2[1],p1[1],0.01) or not near(p2[2],p1[2],0.01)) then drifted=true; break end
  end
  check(drifted,"world haze autonomous weather drift continues independently of player/parallax motion")

  -- 4.32.2 fog-family tuning: 0.25 autonomous speed means t=4 now lands on
  -- exactly the same geometry as t=1 at the original speed. Camera/world
  -- parallax is intentionally independent of this multiplier.
  local normalT=sampleField(0,0,1.0,1.0,1.0)
  local halfT=sampleField(0,0,4.0,0.25,1.0)
  local kn,kh=keyed(normalT),keyed(halfT)
  local speedMatched,speedSame=0,0
  for key,p1 in pairs(kn) do
    local p2=kh[key]
    if p2 then
      speedMatched=speedMatched+1
      if near(p2[1],p1[1],0.001) and near(p2[2],p1[2],0.001) then speedSame=speedSame+1 end
    end
  end
  check(speedMatched>=8 and speedSame==speedMatched,
    "fog-family 0.25 motion multiplier produces exactly one-quarter original autonomous haze speed")

  -- At a deliberately low, non-clipping density, 3x must be a true threefold
  -- alpha increase rather than merely changing a menu/state value.
  local baseLow=sampleField(0,0,0,1.0,1.0,0.15,1.0)
  local boostLow=sampleField(0,0,0,1.0,3.0,0.15,1.0)
  local function keyedAlpha(draws)
    local out={}
    for _,v in ipairs(draws) do
      if v[1] and v[3] then
        local key=string.format("%.6f:%.6f",v[1][3] or 0,v[1][4] or 0)
        out[key]=v[3][8] or 0
      end
    end
    return out
  end
  local kab,kboost=keyedAlpha(baseLow),keyedAlpha(boostLow)
  local alphaMatched,alphaTriple=0,0
  for key,a1 in pairs(kab) do
    local a3=kboost[key]
    if a3 and a1>0 then
      alphaMatched=alphaMatched+1
      if near(a3,a1*3,0.0005) then alphaTriple=alphaTriple+1 end
    end
  end
  check(alphaMatched>=8 and alphaTriple==alphaMatched,
    "fog-family 3.0 intensity multiplier triples actual haze-bank opacity before clipping")
end



-- Loading/input guard: haze parallax follows actual overworld displacement, not
-- raw camera movement. This is the exact regression where holding a direction
-- during a load made the banks keep sliding although the player could not move.
do
  local mods={Config={},Interop={}}
  local V={mod={}}; function V.require(name) return mods[name] or {} end
  local Scene=assert(loadfile(ROOT.."lib/Scene.lua"))(V)
  Scene.now.mapId="ROUTE_1"
  Scene.now.camX,Scene.now.camY=100,60
  Scene.now.playerWorldX,Scene.now.playerWorldY=64,80
  Scene.now.playerPosKnown=true
  local x0,y0=Scene.hazeCamera()
  check(near(x0,100) and near(y0,60),"haze parallax seeds from the live camera once per map")

  -- Simulate held direction/camera commands during a load: raw camera changes,
  -- actual player position does not. Haze parallax must stay frozen.
  Scene.now.camX,Scene.now.camY=164,124
  local xLoad,yLoad=Scene.hazeCamera()
  check(near(xLoad,x0) and near(yLoad,y0),"held input/camera motion during load cannot move haze banks")

  -- If the world becomes temporarily unsampleable, hold the same position too.
  Scene.now.playerPosKnown=false
  Scene.now.camX,Scene.now.camY=220,180
  local xUnknown,yUnknown=Scene.hazeCamera()
  check(near(xUnknown,x0) and near(yUnknown,y0),"unsampleable loading frames hold haze player-parallax position")

  -- Resume with a REAL one-cell movement: +16 world pixels must be accepted,
  -- regardless of however far raw camera input wandered during the load.
  Scene.now.playerPosKnown=true
  Scene.now.playerWorldX=80
  Scene.now.playerWorldY=80
  local xMove,yMove=Scene.hazeCamera()
  check(near(xMove,x0+16) and near(yMove,y0),"actual player-cell movement resumes haze parallax after load")

  -- Map load/re-entry re-anchors instead of replaying prior-map displacement.
  Scene.now.mapId="ROUTE_2"
  Scene.now.camX,Scene.now.camY=40,24
  Scene.now.playerWorldX,Scene.now.playerWorldY=16,16
  local xMap,yMap=Scene.hazeCamera()
  check(near(xMap,40) and near(yMap,24),"new map re-anchors haze without sweeping old-map movement across screen")

end

print(string.format("weather_2d_style_test: %d passed, %d failed",checks-failures,failures))
os.exit(failures==0 and 0 or 1)
