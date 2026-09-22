local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end

-- ---------------------------------------------------------------------------
-- Backgrounds.draw: OFF must be a hard gate; AROUND must really draw.
-- ---------------------------------------------------------------------------
local backdrop = 'around'
local readCount, drawCount, dimCount = 0, 0, 0
local mod = {
  read=function(self,path) readCount=readCount+1; return 'fake-image-bytes' end,
  log={warn=function() end, info=function() end},
}
local Settings={is=function(key,val) return key=='backdrops' and backdrop==val end}
local Config={get=function() return {battleBackdrops=true,battleBackdropDim=0,battleFieldArt='auto'} end}
local TOD={tod='DAY'}
local Scene={now={visible='battle',mapId='CELADON_CITY'}}
local State={id='CLEAR'}
local Types={get=function(id) return {id=id} end}
local V={mod=mod}
function V.require(name)
  local m={TimeOfDay=TOD,Scene=Scene,WeatherState=State,Types=Types,Config=Config,Settings=Settings}
  if m[name] then return m[name] end
  error('unexpected require '..tostring(name))
end
love={
  data={newByteData=function(bytes) return {bytes=bytes} end},
  image={newImageData=function(data) return data end},
  graphics={
    newImage=function(data)
      return {setFilter=function() end,getDimensions=function() return 240,112 end}
    end,
    getColor=function() return 1,1,1,1 end,
    getBlendMode=function() return 'alpha','alphamultiply' end,
    setBlendMode=function() end,
    setColor=function() end,
    draw=function() drawCount=drawCount+1 end,
    rectangle=function() dimCount=dimCount+1 end,
  }
}
local BG=assert(loadfile('lib/Backgrounds.lua'))(V)
backdrop='off'
check(BG.draw({ww=640,wh=480})==false,'BATTLE ART OFF prevents letterbox draw')
check(drawCount==0 and readCount==0,'BATTLE ART OFF avoids even loading backdrop asset')
backdrop='around'
check(BG.draw({ww=640,wh=480})==true,'BATTLE ART AROUND draws through Backgrounds.draw')
check(drawCount==1 and readCount==1,'AROUND loads and submits exactly one backdrop on first draw')
check(BG.draw({ww=640,wh=480})==true and readCount==1,'backdrop image is cached after first load')
Scene.now.visible='world'
check(BG.draw({ww=640,wh=480})==false,'battle backdrop never leaks into overworld')

-- ---------------------------------------------------------------------------
-- BattleField wrapper: a false drawField return must restore vanilla paper.
-- ---------------------------------------------------------------------------
local fieldMode='behind'
local fieldDidDraw=false
local originalRects=0
local Settings2={is=function(key,val) return key=='backdrops' and fieldMode==val end}
local Config2={get=function() return {battleFieldArt='on'} end}
local Backgrounds2={drawField=function() return fieldDidDraw end}
local Interop2={}
local mod2={find=function() return nil end,log={warn=function() end,info=function() end}}
local V2={mod=mod2}
function V2.require(name)
  local m={Settings=Settings2,Config=Config2,Interop=Interop2,Backgrounds=Backgrounds2}
  if m[name] then return m[name] end
  if name=='Compat' then return {battleProfile=function() return {} end} end
  error('unexpected require '..tostring(name))
end
love.graphics={
  rectangle=function(mode,x,y,w,h) originalRects=originalRects+1 end,
}
local BF=assert(loadfile('lib/BattleField.lua'))(V2)
local function engineDraw(self)
  love.graphics.rectangle('fill',0,0,160,144)
  return 'ok'
end
local wrapped=BF.wrap(engineDraw)
local battle={uiSize=function() return 160,144 end}
fieldDidDraw=false; originalRects=0
check(wrapped(battle)=='ok','BEHIND wrapper preserves engine draw return value when art unavailable')
check(originalRects==1,'BEHIND false drawField falls back to vanilla battle paper')
fieldDidDraw=true; originalRects=0
check(wrapped(battle)=='ok','BEHIND wrapper preserves return value when art draws')
check(originalRects==0,'BEHIND successful art replaces the vanilla paper fill')
fieldMode='around'; originalRects=0
wrapped(battle)
check(originalRects==1,'AROUND leaves battle field fill untouched')

print(('battle art: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
