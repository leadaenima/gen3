-- Gen 3 battle animation sprite sheets, read from the player's own cart.
--
-- Game3MoveAnim / Game3BattleFx used to load these straight out of the decomp
-- checkout:
--
--   MA.SPRITE_DIR = "misc/pokeruby-master/.../graphics/battle_anims/sprites/"
--
-- misc/ is not in scripts/pack_love.sh's include list, so on a packaged build
-- every sheet was missing. loadTagImage checks fileExists and caches `false` on
-- a miss, so nothing errored -- each animation quietly fell back to its
-- procedural stand-in, which is why this survived: correct on a dev machine
-- with the decomp present, degraded on every phone.
--
-- gBattleAnimPicTable (battle_anim.c) is an array of
--   struct CompressedSpriteSheet { const u8 *data; u16 size; u16 tag; }
-- with tag = ANIM_SPRITES_START + index, and gBattleAnimPaletteTable runs
-- parallel to it. Both were located by matching a known sheet's pointer; the
-- decompressed pixels are byte-identical to the decomp PNGs for all 265 sheets
-- that have one, and the ROM palettes match those PNGs' palettes exactly.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Anim = {}

Anim.RUBY_US = {
  picTable = 0x37E164,
  palTable = 0x37EA6C,
  count = 289,
  entry = 8,
}

Anim.DIR = "assets/generated/battle_anims/"

-- Tiles are stored linearly and the sheet's shape is not in the ROM table.
-- These are the dimensions of the exact file loadTagImage used to open
-- (NNN.png, else NNN_0.png), so what the engine receives is unchanged and this
-- edit only moves the source from a decomp checkout to the cart. Several ROM
-- entries hold every frame in one strip where the decomp splits them into
-- NNN_0/NNN_1; matching the old shape matters because the draw path renders the
-- WHOLE sheet whenever its width is <= 40px. Dimensions, not artwork.
Anim.SHEET_TILES = {
  [0]={4,4}, [1]={1,8}, [2]={4,4}, [3]={4,2}, [4]={2,8}, [5]={4,8},
  [6]={2,6}, [7]={4,16}, [8]={1,1}, [9]={4,8}, [10]={8,8}, [11]={2,6},
  [12]={2,2}, [13]={2,2}, [14]={4,5}, [15]={2,2}, [16]={4,2}, [17]={1,1},
  [18]={1,4}, [19]={4,7}, [20]={4,4}, [21]={4,20}, [23]={2,14}, [24]={4,6},
  [25]={2,6}, [26]={4,20}, [27]={4,20}, [28]={4,20}, [29]={4,20}, [30]={4,20},
  [31]={4,28}, [32]={2,14}, [33]={4,32}, [34]={4,16}, [35]={4,20}, [36]={4,16},
  [37]={4,20}, [38]={4,16}, [39]={4,20}, [40]={4,20}, [41]={4,20}, [42]={4,20},
  [43]={4,20}, [44]={4,20}, [45]={4,20}, [46]={4,32}, [48]={4,32}, [50]={4,4},
  [51]={4,4}, [52]={4,4}, [53]={4,16}, [54]={2,2}, [55]={4,4}, [56]={4,32},
  [57]={2,6}, [58]={4,24}, [59]={2,4}, [60]={1,2}, [61]={2,6}, [62]={4,16},
  [63]={2,18}, [64]={4,4}, [65]={1,16}, [66]={2,4}, [70]={2,8}, [71]={4,20},
  [72]={2,12}, [73]={2,6}, [74]={1,1}, [75]={4,14}, [76]={4,8}, [77]={1,16},
  [78]={2,12}, [79]={4,24}, [80]={4,20}, [81]={2,2}, [82]={1,2}, [83]={4,26},
  [84]={4,24}, [85]={2,10}, [86]={2,8}, [87]={2,2}, [88]={1,6}, [89]={4,20},
  [90]={2,6}, [91]={2,6}, [92]={4,1}, [93]={4,32}, [94]={4,20}, [95]={2,6},
  [96]={2,14}, [97]={2,24}, [98]={4,4}, [99]={4,4}, [100]={2,8}, [101]={4,4},
  [102]={4,4}, [103]={2,2}, [104]={4,8}, [105]={4,24}, [106]={2,8}, [107]={4,32},
  [108]={4,20}, [109]={1,1}, [110]={4,28}, [111]={2,2}, [112]={4,20}, [113]={2,16},
  [114]={2,8}, [115]={2,28}, [116]={4,16}, [117]={4,20}, [118]={4,16}, [119]={4,16},
  [120]={4,4}, [121]={1,2}, [122]={2,6}, [123]={2,24}, [124]={4,12}, [125]={2,8},
  [126]={2,2}, [127]={4,4}, [128]={8,8}, [129]={2,2}, [130]={4,20}, [131]={2,10},
  [132]={2,10}, [133]={2,4}, [134]={4,4}, [135]={4,4}, [136]={1,1}, [137]={4,20},
  [138]={4,16}, [139]={8,8}, [140]={1,6}, [141]={2,2}, [142]={1,8}, [143]={4,16},
  [144]={4,4}, [145]={8,8}, [146]={2,6}, [147]={2,6}, [148]={4,4}, [149]={2,8},
  [150]={2,6}, [151]={2,16}, [152]={2,2}, [153]={4,2}, [154]={4,2}, [155]={2,5},
  [156]={8,8}, [157]={4,4}, [158]={2,4}, [159]={2,2}, [160]={4,2}, [161]={2,2},
  [162]={4,6}, [163]={2,4}, [166]={8,8}, [171]={2,2}, [173]={4,4}, [174]={4,4},
  [175]={2,2}, [176]={4,4}, [177]={2,20}, [178]={8,8}, [179]={8,4}, [180]={1,1},
  [181]={8,8}, [182]={2,4}, [183]={4,16}, [184]={2,16}, [185]={4,20}, [186]={8,16},
  [187]={8,8}, [188]={8,4}, [189]={4,4}, [190]={4,16}, [191]={8,8}, [192]={4,16},
  [193]={4,4}, [194]={8,8}, [195]={2,8}, [196]={8,8}, [197]={4,4}, [198]={4,16},
  [199]={4,8}, [200]={4,4}, [201]={4,21}, [202]={4,12}, [203]={8,8}, [204]={4,4},
  [205]={4,12}, [206]={2,32}, [207]={2,6}, [208]={16,4}, [209]={4,16}, [210]={2,2},
  [211]={1,4}, [212]={8,8}, [213]={4,16}, [214]={4,12}, [215]={4,12}, [217]={2,2},
  [218]={2,8}, [220]={4,4}, [221]={4,8}, [222]={4,20}, [223]={4,16}, [224]={4,4},
  [225]={4,8}, [226]={2,2}, [227]={8,8}, [228]={4,4}, [229]={4,6}, [230]={8,8},
  [231]={2,14}, [232]={4,16}, [233]={2,3}, [234]={4,16}, [235]={1,3}, [238]={1,4},
  [239]={2,6}, [240]={1,12}, [241]={2,8}, [242]={4,4}, [243]={1,1}, [244]={8,4},
  [245]={4,12}, [246]={8,16}, [247]={4,8}, [248]={1,1}, [249]={2,2}, [250]={8,8},
  [251]={2,2}, [252]={4,4}, [253]={2,16}, [254]={4,4}, [255]={4,4}, [256]={8,8},
  [257]={2,10}, [258]={4,4}, [260]={4,8}, [261]={4,4}, [262]={4,4}, [263]={2,2},
  [264]={1,1}, [266]={2,2}, [269]={2,2}, [270]={4,8}, [271]={2,4}, [272]={8,8},
  [273]={1,1}, [274]={8,8}, [275]={8,8}, [276]={8,8}, [277]={8,16}, [278]={8,8},
  [279]={1,5}, [280]={8,8}, [281]={4,4}, [282]={4,12}, [283]={4,4}, [284]={8,8},
  [285]={4,4},
}

local function bgr555(v)
  return (v % 32) / 31,
    (math.floor(v / 32) % 32) / 31,
    (math.floor(v / 1024) % 32) / 31
end

local function romOffset(ptr)
  if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
  return ptr - 0x08000000
end

function Anim.picEntry(data, index)
  local u = Anim.RUBY_US
  local at = u.picTable + index * u.entry
  return romOffset(GbaBin.u32(data, at)), GbaBin.u16(data, at + 4),
    GbaBin.u16(data, at + 6)
end

function Anim.palette(data, index)
  local u = Anim.RUBY_US
  local off = romOffset(GbaBin.u32(data, u.palTable + index * u.entry))
  if not off then return nil end
  -- Palettes are LZ77 in this table; fall back to raw for any that are not.
  local raw = GbaLz77.decompress(data, off) or data:sub(off + 1, off + 32)
  if #raw < 32 then return nil end
  local pal = {}
  for i = 0, 15 do
    local lo, hi = raw:byte(i * 2 + 1, i * 2 + 2)
    local r, g, b = bgr555(lo + hi * 256)
    pal[i] = { r, g, b }
  end
  return pal
end

-- Sheets without a decomp layout are unused by the engine; lay them out in a
-- single row rather than skipping, so the table stays index-aligned.
function Anim.sheetTiles(index, size)
  local avail = math.floor(size / 32)
  if avail < 1 then return nil end
  local dim = Anim.SHEET_TILES[index]
  if dim then
    return dim[1], dim[2], math.min(dim[1] * dim[2], avail)
  end
  -- No decomp layout: unused by the engine, kept index-aligned as one row.
  return avail, 1, avail
end

function Anim.renderSheet(data, index)
  local off = Anim.picEntry(data, index)
  if not off then return nil end
  local pixels = GbaLz77.decompress(data, off)
  if not pixels then return nil end
  local pal = Anim.palette(data, index)
  if not pal then return nil end
  -- The table's `size` is the VRAM upload length, which is padded up on some
  -- sheets and truncated on others; the LZ77 stream's own decompressed length
  -- is what matches the sheet, on all 260 that could be checked.
  local wide, tall, total = Anim.sheetTiles(index, #pixels)
  if not wide then return nil end
  local image = ImageWriter.blank(wide * 8, tall * 8, 0, 0, 0, 1)
  for tile = 0, total - 1 do
    local tx, ty = (tile % wide) * 8, math.floor(tile / wide) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local byte = pixels:byte(tile * 32 + y * 4 + math.floor(x / 2) + 1) or 0
        local idx
        if x % 2 == 0 then idx = byte % 16 else idx = math.floor(byte / 16) end
        local c = pal[idx] or pal[0]
        image:setPixel(tx + x, ty + y, c[1], c[2], c[3], 1)
      end
    end
  end
  return image
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

-- Palette index 0 is left as its real colour: Game3MoveAnim's keyPalette0Alpha
-- samples pixel (0,0) and keys by colour, exactly as it did for the indexed
-- PNGs these replace.
function Anim.extract(data)
  local u = Anim.RUBY_US
  if type(data) ~= "string" or #data < u.picTable + u.count * u.entry then
    return 0
  end
  local written = 0
  for index = 0, u.count - 1 do
    local path = save(Anim.renderSheet(data, index),
      Anim.DIR .. string.format("%03d.png", index))
    if path then written = written + 1 end
  end
  return written
end

return Anim
