-- Android APK source is read-only. Import must write generated PNGs
-- through love.filesystem (save directory). Desktop io.open still works
-- as a fallback so existing ImageWriter.save keeps working.
local ImageWriter = require("src.import.ImageWriter")

local function parentDir(path)
  return path and path:match("^(.*)[/\\][^/\\]+$")
end

local function encodePng(image)
  if not image then return nil end
  
  -- 1. Try native encoding if the object supports it directly
  if image.encode then
    local ok, data = pcall(image.encode, image, "png")
    if ok and data then
      if type(data) == "string" then return data end
      if type(data) == "userdata" and data.getString then return data:getString() end
    end
    
    -- Old LÖVE 0.10 fallback syntax for image:encode("png") variant
    local ok2, data2 = pcall(image.encode, image, "png", "temp_encode_check.png")
    if ok2 and data2 then
      if type(data2) == "string" then return data2 end
      if type(data2) == "userdata" and data2.getString then return data2:getString() end
    end
  end
  
  -- 2. Fallback pixel loop (Only used if the image is a custom/non-LOVE data structure)
  if love and love.image and image.getWidth and image.getPixel then
    local w = image:getWidth()
    local h = image:getHeight()
    local ok, id = pcall(love.image.newImageData, w, h)
    if ok and id then
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local pok, r, g, b, a = pcall(image.getPixel, image, x, y)
          if pok then
            id:setPixel(x, y, r, g, b, a or 1)
          end
        end
      end
      
      -- Handle encoding version differences safely
      local enc
      local eok1, res1 = pcall(id.encode, id, "png") -- Modern syntax
      if eok1 then enc = res1 end
      
      if not enc then
        local eok2, res2 = pcall(id.encode, id, "png", "temp.png") -- Legacy syntax
        if eok2 then enc = res2 end
      end
      
      if enc then
        if type(enc) == "string" then return enc end
        if type(enc) == "userdata" and enc.getString then return enc:getString() end
      end
    end
  end
  return nil
end

if not ImageWriter._generatedFsWrapped then
  local raw = ImageWriter.save
  function ImageWriter.save(image, path)
    if type(path) ~= "string" or path == "" then return nil end
    if love and love.filesystem then
      local dir = parentDir(path)
      if dir and dir ~= "" then
        love.filesystem.createDirectory(dir)
      end
      local png = encodePng(image)
      if png then
        local ok = love.filesystem.write(path, png)
        if ok then return path end
      end
    end
    if type(raw) == "function" then
      return raw(image, path)
    end
    return nil
  end
  ImageWriter._generatedFsWrapped = true
end

return ImageWriter
