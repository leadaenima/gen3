"""Locate MenuGfx_HoldIcons / MenuPal_HoldIcons in the Ruby cart.

The sheet is uncompressed and tiny (8x16 4bpp = two 8x8 frames, 64 bytes),
so there is nothing structural to search for. Instead decode the decomp's
hold_icons.png, rebuild the exact bytes the build would have INCBINed, and
look for that run in the ROM.
"""
import struct
import zlib

ROM = r"C:/Users/Feces/Desktop/Pokemon - Ruby Version (USA).gba"
PNG = (r"C:/Users/Feces/Desktop/pokeruby-master/pokeruby-master/"
       r"graphics/interface/hold_icons.png")


def read_png(path):
    data = open(path, "rb").read()
    pos, idat, plte = 8, b"", b""
    width = height = depth = 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth = struct.unpack(">IIB", body[:9])
        elif kind == b"PLTE":
            plte = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    # 4bpp indexed: one filter byte then width/2 bytes per scanline. These
    # icons use filter 0 throughout, which keeps this simple.
    stride = width // 2
    pixels = []
    for y in range(height):
        line = raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)]
        row = []
        for b in line:
            row.append(b >> 4)      # PNG packs the left pixel high
            row.append(b & 0xF)
        pixels.append(row)
    return width, height, depth, plte, pixels


def to_gba_4bpp(pixels, width, height):
    """GBA packs the left pixel in the LOW nibble, the reverse of PNG."""
    out = bytearray()
    for ty in range(height // 8):
        for tx in range(width // 8):
            for y in range(8):
                for x in range(0, 8, 2):
                    lo = pixels[ty * 8 + y][tx * 8 + x]
                    hi = pixels[ty * 8 + y][tx * 8 + x + 1]
                    out.append(lo | (hi << 4))
    return bytes(out)


def to_bgr555(plte):
    out = bytearray()
    for i in range(0, len(plte), 3):
        r, g, b = plte[i] >> 3, plte[i + 1] >> 3, plte[i + 2] >> 3
        out += struct.pack("<H", r | (g << 5) | (b << 10))
    return bytes(out)


def find_all(hay, needle):
    hits, at = [], 0
    while True:
        i = hay.find(needle, at)
        if i < 0:
            return hits
        hits.append(i)
        at = i + 1


w, h, depth, plte, pixels = read_png(PNG)
print("png %dx%d depth %d, %d palette entries" % (w, h, depth, len(plte) // 3))

gfx = to_gba_4bpp(pixels, w, h)
print("tile data: %d bytes -> %s..." % (len(gfx), gfx[:12].hex()))

rom = open(ROM, "rb").read()
hits = find_all(rom, gfx)
print("MenuGfx_HoldIcons candidates: %s"
      % ", ".join("0x%06X" % o for o in hits))

pal = to_bgr555(plte)
print("palette: %d bytes -> %s..." % (len(pal), pal[:12].hex()))
for n in (len(pal), 32):
    if n <= len(pal):
        ph = find_all(rom, pal[:n])
        print("  first %2d bytes of palette: %s"
              % (n, ", ".join("0x%06X" % o for o in ph) or "none"))
