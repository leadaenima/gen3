"""Headless GBA emulation for use as a behaviour oracle.

Drives the mGBA libretro core (tools/gba_oracle/vendor/mgba_libretro.dll)
through ctypes so a real cart can be booted, fed inputs and read out of
memory without a GUI or a C toolchain.  The point is to check the Lua
engine against hardware rather than against a human reading of pokeruby:
run the same scene on both, diff the flags, vars, party and coordinates.

The core is loaded through the plain libretro C API, so nothing here is
specific to mGBA beyond the DLL name -- any libretro GBA core exposing
memory maps would work.

Not a test: tests must stay ROM-free.  This is a developer tool that needs
a cart on disk, like tools/gen3_script_audit.lua.
"""

import ctypes
import os
import sys

DLL = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "vendor", "mgba_libretro.dll")

# libretro environment commands this harness answers.  Anything else is
# refused, which the API defines as "unsupported" rather than an error.
ENV_GET_CAN_DUPE = 3
ENV_SET_PIXEL_FORMAT = 10
ENV_GET_SYSTEM_DIRECTORY = 9
ENV_GET_VARIABLE = 15
ENV_SET_VARIABLES = 16
ENV_GET_VARIABLE_UPDATE = 17
ENV_GET_SAVE_DIRECTORY = 31
ENV_SET_MEMORY_MAPS = 36

RETRO_MEMORY_SAVE_RAM = 0
RETRO_MEMORY_SYSTEM_RAM = 2

RETRO_DEVICE_JOYPAD = 1

# The core leaves addrspace null, so name the blocks by their GBA bases.
GBA_REGIONS = {
    0x00000000: "bios", 0x02000000: "ewram", 0x03000000: "iwram",
    0x04000000: "io", 0x05000000: "pal", 0x06000000: "vram",
    0x07000000: "oam", 0x08000000: "rom", 0x0A000000: "rom1",
    0x0C000000: "rom2", 0x0E000000: "sram",
}

# libretro joypad ids, in the order the GBA maps onto them.
BUTTONS = {
    "b": 0, "select": 2, "start": 3, "up": 4, "down": 5, "left": 6,
    "right": 7, "a": 8, "l": 10, "r": 11,
}


class retro_game_info(ctypes.Structure):
    _fields_ = [
        ("path", ctypes.c_char_p),
        ("data", ctypes.c_void_p),
        ("size", ctypes.c_size_t),
        ("meta", ctypes.c_char_p),
    ]


class retro_system_info(ctypes.Structure):
    _fields_ = [
        ("library_name", ctypes.c_char_p),
        ("library_version", ctypes.c_char_p),
        ("valid_extensions", ctypes.c_char_p),
        ("need_fullpath", ctypes.c_bool),
        ("block_extract", ctypes.c_bool),
    ]


class retro_memory_descriptor(ctypes.Structure):
    _fields_ = [
        ("flags", ctypes.c_uint64),
        ("ptr", ctypes.c_void_p),
        ("offset", ctypes.c_size_t),
        ("start", ctypes.c_size_t),
        ("select", ctypes.c_size_t),
        ("disconnect", ctypes.c_size_t),
        ("len", ctypes.c_size_t),
        ("addrspace", ctypes.c_char_p),
    ]


class retro_memory_map(ctypes.Structure):
    _fields_ = [
        ("descriptors", ctypes.POINTER(retro_memory_descriptor)),
        ("num_descriptors", ctypes.c_uint),
    ]


class retro_variable(ctypes.Structure):
    _fields_ = [("key", ctypes.c_char_p), ("value", ctypes.c_char_p)]


CB_ENV = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_uint, ctypes.c_void_p)
CB_VIDEO = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint,
                            ctypes.c_uint, ctypes.c_size_t)
CB_AUDIO = ctypes.CFUNCTYPE(None, ctypes.c_int16, ctypes.c_int16)
CB_AUDIO_BATCH = ctypes.CFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p,
                                  ctypes.c_size_t)
CB_POLL = ctypes.CFUNCTYPE(None)
CB_INPUT = ctypes.CFUNCTYPE(ctypes.c_int16, ctypes.c_uint, ctypes.c_uint,
                            ctypes.c_uint, ctypes.c_uint)


class Region:
    """One mapped block of the GBA address space."""

    def __init__(self, start, length, ptr, name):
        self.start = start
        self.length = length
        self.ptr = ptr
        self.name = name

    def __repr__(self):
        return "%-6s %08X..%08X (%d KiB)" % (
            self.name, self.start, self.start + self.length - 1,
            self.length // 1024)


class Core:
    def __init__(self, dll=DLL, system_dir=None):
        if not os.path.exists(dll):
            raise RuntimeError("core not found: %s" % dll)
        self.lib = ctypes.CDLL(dll)
        self.regions = []
        self.frame = None
        self.frame_size = (0, 0)
        self._keys = set()
        self._loaded = False
        self._system_dir = (system_dir or
                            os.path.join(os.path.dirname(dll), "system"))
        os.makedirs(self._system_dir, exist_ok=True)
        self._sysdir_buf = ctypes.c_char_p(
            self._system_dir.encode("utf-8"))

        self._declare()
        # ctypes does not own callbacks; dropping these would let Python
        # collect the trampolines while the core still holds pointers.
        self._cb = {
            "env": CB_ENV(self._on_env),
            "video": CB_VIDEO(self._on_video),
            "audio": CB_AUDIO(lambda l, r: None),
            "audio_batch": CB_AUDIO_BATCH(lambda data, frames: frames),
            "poll": CB_POLL(lambda: None),
            "input": CB_INPUT(self._on_input),
        }
        self.lib.retro_set_environment(self._cb["env"])
        self.lib.retro_set_video_refresh(self._cb["video"])
        self.lib.retro_set_audio_sample(self._cb["audio"])
        self.lib.retro_set_audio_sample_batch(self._cb["audio_batch"])
        self.lib.retro_set_input_poll(self._cb["poll"])
        self.lib.retro_set_input_state(self._cb["input"])
        self.lib.retro_init()

    def _declare(self):
        lib = self.lib
        lib.retro_api_version.restype = ctypes.c_uint
        lib.retro_load_game.argtypes = [ctypes.POINTER(retro_game_info)]
        lib.retro_load_game.restype = ctypes.c_bool
        lib.retro_get_system_info.argtypes = [
            ctypes.POINTER(retro_system_info)]
        lib.retro_get_memory_data.argtypes = [ctypes.c_uint]
        lib.retro_get_memory_data.restype = ctypes.c_void_p
        lib.retro_get_memory_size.argtypes = [ctypes.c_uint]
        lib.retro_get_memory_size.restype = ctypes.c_size_t
        lib.retro_serialize_size.restype = ctypes.c_size_t
        lib.retro_serialize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        lib.retro_serialize.restype = ctypes.c_bool
        lib.retro_unserialize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        lib.retro_unserialize.restype = ctypes.c_bool

    # ---- libretro callbacks

    def _on_env(self, cmd, data):
        # EXPERIMENTAL commands carry a high bit that is not part of the id.
        base = cmd & 0xFFFF
        if base == ENV_SET_PIXEL_FORMAT:
            return True
        if base == ENV_GET_CAN_DUPE:
            ctypes.cast(data, ctypes.POINTER(ctypes.c_bool))[0] = True
            return True
        if base in (ENV_GET_SYSTEM_DIRECTORY, ENV_GET_SAVE_DIRECTORY):
            ctypes.cast(data, ctypes.POINTER(ctypes.c_char_p))[0] = \
                self._sysdir_buf
            return True
        if base == ENV_GET_VARIABLE_UPDATE:
            ctypes.cast(data, ctypes.POINTER(ctypes.c_bool))[0] = False
            return True
        if base == ENV_GET_VARIABLE:
            # No overrides: the core keeps its defaults.
            ctypes.cast(data, ctypes.POINTER(retro_variable))[0].value = None
            return False
        if base == ENV_SET_VARIABLES:
            return True
        if base == ENV_SET_MEMORY_MAPS:
            self._read_memory_maps(data)
            return True
        return False

    def _read_memory_maps(self, data):
        mmap = ctypes.cast(data, ctypes.POINTER(retro_memory_map))[0]
        self.regions = []
        for i in range(mmap.num_descriptors):
            d = mmap.descriptors[i]
            if not d.ptr or not d.len:
                continue
            name = d.addrspace.decode() if d.addrspace else ""
            if not name:
                name = GBA_REGIONS.get(d.start, "%08X" % d.start)
            self.regions.append(Region(d.start, d.len, d.ptr, name))

    def _on_video(self, data, width, height, pitch):
        if not data:
            return
        # RGB565 by default in this core; kept as raw rows so a caller can
        # decide whether it wants pixels at all.
        size = pitch * height
        buf = ctypes.string_at(data, size)
        self.frame = (buf, pitch)
        self.frame_size = (width, height)

    def _on_input(self, port, device, index, button_id):
        if port != 0 or device != RETRO_DEVICE_JOYPAD:
            return 0
        return 1 if button_id in self._keys else 0

    # ---- lifecycle

    def load(self, rom_path):
        info = retro_system_info()
        self.lib.retro_get_system_info(ctypes.byref(info))
        self.library = "%s %s" % (info.library_name.decode(),
                                  info.library_version.decode())
        with open(rom_path, "rb") as fh:
            self._rom = fh.read()
        buf = ctypes.create_string_buffer(self._rom, len(self._rom))
        self._rom_buf = buf
        game = retro_game_info(
            path=rom_path.encode("utf-8"),
            data=ctypes.cast(buf, ctypes.c_void_p),
            size=len(self._rom),
            meta=None,
        )
        if not self.lib.retro_load_game(ctypes.byref(game)):
            raise RuntimeError("core refused the ROM: %s" % rom_path)
        self._loaded = True
        # mGBA publishes its memory map from retro_reset, not from
        # retro_load_game, so without this the address space is unknown.
        # Guessing it instead (say, assuming RETRO_MEMORY_SYSTEM_RAM is
        # EWRAM -- it is IWRAM here) reads the wrong addresses and reports
        # confident nonsense, which is the one thing an oracle must not do.
        self.lib.retro_reset()
        if not self._region_for(0x02000000):
            raise RuntimeError(
                "core published no EWRAM mapping; refusing to guess "
                "addresses (regions: %s)" % [r.name for r in self.regions])
        return self

    def close(self):
        if self._loaded:
            self.lib.retro_unload_game()
            self._loaded = False
        self.lib.retro_deinit()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    # ---- running

    def set_keys(self, *names):
        """Hold exactly these buttons from the next frame on."""
        self._keys = set()
        for n in names:
            if n not in BUTTONS:
                raise KeyError("unknown button %r" % n)
            self._keys.add(BUTTONS[n])

    def run(self, frames=1):
        for _ in range(frames):
            self.lib.retro_run()

    def press(self, *names, hold=4, release=4):
        """Tap buttons, then let go -- the shape most menus expect."""
        self.set_keys(*names)
        self.run(hold)
        self.set_keys()
        self.run(release)

    def run_until(self, predicate, timeout=3600, step=1):
        """Advance until predicate() is true.  Returns frames spent, or
        None on timeout, so callers can wait on game state instead of
        guessing frame counts."""
        spent = 0
        while spent < timeout:
            if predicate():
                return spent
            self.run(step)
            spent += step
        return None

    # ---- memory

    def _region_for(self, addr):
        for r in self.regions:
            if r.start <= addr < r.start + r.length:
                return r
        return None

    def read(self, addr, length):
        out = bytearray()
        while length > 0:
            r = self._region_for(addr)
            if r is None:
                raise ValueError("address %08X is not mapped" % addr)
            off = addr - r.start
            n = min(length, r.length - off)
            out += ctypes.string_at(r.ptr + off, n)
            addr += n
            length -= n
        return bytes(out)

    def u8(self, addr):
        return self.read(addr, 1)[0]

    def u16(self, addr):
        return int.from_bytes(self.read(addr, 2), "little")

    def u32(self, addr):
        return int.from_bytes(self.read(addr, 4), "little")

    # ---- savestates: the cheap way to pin a scene for repeated runs

    def save_state(self):
        size = self.lib.retro_serialize_size()
        buf = ctypes.create_string_buffer(size)
        if not self.lib.retro_serialize(buf, size):
            raise RuntimeError("serialize failed")
        return buf.raw

    def load_state(self, blob):
        buf = ctypes.create_string_buffer(blob, len(blob))
        if not self.lib.retro_unserialize(buf, len(blob)):
            raise RuntimeError("unserialize failed")


def png(path, rgb565, pitch, width, height):
    """Write the current frame out so a boot can be eyeballed."""
    import struct
    import zlib

    rows = bytearray()
    for y in range(height):
        rows.append(0)
        base = y * pitch
        for x in range(width):
            px = rgb565[base + x * 2] | (rgb565[base + x * 2 + 1] << 8)
            r = (px >> 11) & 0x1F
            g = (px >> 5) & 0x3F
            b = px & 0x1F
            rows += bytes(((r * 255) // 31, (g * 255) // 63, (b * 255) // 31))

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR",
                       struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(rows), 6)))
        fh.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: python libretro.py <rom.gba> [frames] [shot.png]")
    rom = sys.argv[1]
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    shot = sys.argv[3] if len(sys.argv) > 3 else None

    with Core() as core:
        core.load(rom)
        print("core       %s" % core.library)
        print("regions:")
        for r in core.regions:
            print("  %r" % r)
        core.run(frames)
        print("ran        %d frames" % frames)
        print("video      %dx%d" % core.frame_size)
        ewram = core.read(0x02000000, 0x1000)
        print("ewram head %s" % ewram[:16].hex())
        print("nonzero    %d of first 4096 bytes"
              % sum(1 for b in ewram if b))
        if shot and core.frame:
            buf, pitch = core.frame
            png(shot, buf, pitch, *core.frame_size)
            print("shot       %s" % shot)
