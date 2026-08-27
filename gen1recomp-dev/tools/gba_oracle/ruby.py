"""Reads Pokemon Ruby (USA) game state out of emulated RAM.

Every address and offset below is quoted from pokeruby, not inferred:
`include/global.h` carries the base addresses in the struct comments
(`struct SaveBlock1 /* 0x02025734 */`) and the field offsets in per-field
comments.  Sizes that the header states as named counts are derived from
the neighbouring offsets so they cannot drift out of step:

    flags     0x1220 .. 0x1340   0x120 bytes   2304 flags
    vars      0x1340 .. 0x1540   0x200 bytes   256 u16 vars

The snapshot this produces is deliberately the same shape as the Lua
engine's own state (set flags, non-zero vars, position, map, party), so
the two can be diffed field by field.
"""

SAVEBLOCK1 = 0x02025734
SAVEBLOCK2 = 0x02024EA4

# SaveBlock1 field offsets, from include/global.h.
OFF_POS = 0x0000          # struct Coords16 { s16 x, y }
OFF_LOCATION = 0x0004     # struct WarpData
OFF_FLASH_LEVEL = 0x0030  # u8; 0 lit, 4 darkest
OFF_MAP_LAYOUT_ID = 0x0032
OFF_PARTY_COUNT = 0x0234
OFF_PARTY = 0x0238        # struct Pokemon[6], 100 bytes each
OFF_OBJECT_EVENTS = 0x09E0
OFF_FLAGS = 0x1220
OFF_VARS = 0x1340
OFF_GAME_STATS = 0x1540

# global.fieldmap.h struct ObjectEvent, size 0x24.
OBJECT_EVENT_SIZE = 0x24
OBJECT_EVENTS_COUNT = 16
OFF_OBJ_LOCAL_ID = 0x08
OFF_OBJ_CURRENT_XY = 0x10
MAP_OFFSET = 7            # fieldmap.h; object xy is map-local + 7
LOCALID_PLAYER = 0xFF

FLAG_BYTES = OFF_VARS - OFF_FLAGS
VAR_COUNT = (OFF_GAME_STATS - OFF_VARS) // 2
VARS_START = 0x4000       # include/constants/vars.h

# SaveBlock2 field offsets.
OFF_PLAYER_NAME = 0x00
OFF_PLAYER_GENDER = 0x08
OFF_TRAINER_ID = 0x0A
OFF_PLAY_TIME_HOURS = 0x0E
OFF_PLAY_TIME_MINUTES = 0x10

MON_SIZE = 100
MON_OFF_LEVEL = 84        # struct Pokemon substruct, unencrypted region

# WarpData is s8 mapGroup, s8 mapNum, s8 warpId, then s16 x, y -- the
# s16s force a pad byte at +3, which is why the struct is 8 wide.
WARP_MAP_GROUP = 0
WARP_MAP_NUM = 1
WARP_ID = 2
WARP_X = 4
WARP_Y = 6


def _s16(v):
    return v - 0x10000 if v >= 0x8000 else v


def _s8(v):
    return v - 0x100 if v >= 0x80 else v


class RubyState:
    """Reads the live save block out of a running Core."""

    def __init__(self, core):
        self.core = core

    # ---- raw blocks

    def flag_bytes(self):
        return self.core.read(SAVEBLOCK1 + OFF_FLAGS, FLAG_BYTES)

    def var_bytes(self):
        return self.core.read(SAVEBLOCK1 + OFF_VARS, VAR_COUNT * 2)

    # ---- decoded views

    def flags(self):
        """Ids of every set flag."""
        out = []
        for i, byte in enumerate(self.flag_bytes()):
            if not byte:
                continue
            for bit in range(8):
                if byte & (1 << bit):
                    out.append(i * 8 + bit)
        return out

    def vars(self):
        """Non-zero script vars, keyed by their VAR_* id (0x4000 based)."""
        raw = self.var_bytes()
        out = {}
        for i in range(VAR_COUNT):
            v = raw[i * 2] | (raw[i * 2 + 1] << 8)
            if v:
                out[VARS_START + i] = v
        return out

    def position(self):
        x = _s16(self.core.u16(SAVEBLOCK1 + OFF_POS))
        y = _s16(self.core.u16(SAVEBLOCK1 + OFF_POS + 2))
        return (x, y)

    def flash_level(self):
        return self.core.u8(SAVEBLOCK1 + OFF_FLASH_LEVEL)

    def player_xy(self):
        """Map-local feet from gSaveBlock1.objectEvents.

        SaveBlock1.pos only refreshes on a warp.  The live object copy is
        what SetPlayerCoordsFromWarp / walking write; subtract MAP_OFFSET
        so the number matches Game3.playerX/Y.  Falls back to pos when
        the player object has not been spawned yet.
        """
        for i in range(OBJECT_EVENTS_COUNT):
            base = SAVEBLOCK1 + OFF_OBJECT_EVENTS + i * OBJECT_EVENT_SIZE
            if self.core.u8(base + OFF_OBJ_LOCAL_ID) != LOCALID_PLAYER:
                continue
            x = _s16(self.core.u16(base + OFF_OBJ_CURRENT_XY))
            y = _s16(self.core.u16(base + OFF_OBJ_CURRENT_XY + 2))
            return (x - MAP_OFFSET, y - MAP_OFFSET)
        return self.position()

    def location(self):
        base = SAVEBLOCK1 + OFF_LOCATION
        return {
            "mapGroup": _s8(self.core.u8(base + WARP_MAP_GROUP)),
            "mapNum": _s8(self.core.u8(base + WARP_MAP_NUM)),
            "warpId": _s8(self.core.u8(base + WARP_ID)),
            "x": _s16(self.core.u16(base + WARP_X)),
            "y": _s16(self.core.u16(base + WARP_Y)),
        }

    def party(self):
        n = self.core.u8(SAVEBLOCK1 + OFF_PARTY_COUNT)
        if n > 6:
            n = 6
        out = []
        for i in range(n):
            base = SAVEBLOCK1 + OFF_PARTY + i * MON_SIZE
            out.append({
                "personality": self.core.u32(base),
                "otId": self.core.u32(base + 4),
                "level": self.core.u8(base + MON_OFF_LEVEL),
            })
        return out

    def player(self):
        return {
            "gender": self.core.u8(SAVEBLOCK2 + OFF_PLAYER_GENDER),
            "trainerId": self.core.u16(SAVEBLOCK2 + OFF_TRAINER_ID),
            "playTimeHours": self.core.u16(SAVEBLOCK2 + OFF_PLAY_TIME_HOURS),
            "playTimeMinutes": self.core.u8(
                SAVEBLOCK2 + OFF_PLAY_TIME_MINUTES),
        }

    def snapshot(self):
        return {
            "position": self.position(),
            "playerXY": self.player_xy(),
            "flashLevel": self.flash_level(),
            "location": self.location(),
            "mapLayoutId": self.core.u16(SAVEBLOCK1 + OFF_MAP_LAYOUT_ID),
            "flags": self.flags(),
            "vars": self.vars(),
            "party": self.party(),
            "player": self.player(),
        }

    # ---- liveness

    def looks_initialised(self):
        """True once the save block holds a started game.

        A fresh boot leaves the block zeroed, and the intro runs long
        before NEW GAME is picked, so this is what tells a driver that it
        is actually in the world rather than still in a menu.
        """
        loc = self.location()
        if not (0 <= loc["mapGroup"] <= 40 and 0 <= loc["mapNum"] <= 120):
            return False
        return self.core.u8(SAVEBLOCK1 + OFF_PARTY_COUNT) <= 6 and any(
            self.flag_bytes())


def diff(a, b, flag_name=None, var_name=None):
    """Human-readable difference between two snapshots.

    Returns a list of lines; empty means the two states agree.
    """
    lines = []

    def name_flag(i):
        return flag_name(i) if flag_name else "flag 0x%03X" % i

    def name_var(i):
        return var_name(i) if var_name else "var 0x%04X" % i

    for key in ("position", "playerXY", "flashLevel", "mapLayoutId"):
        if a.get(key) != b.get(key):
            lines.append("%s: %r vs %r" % (key, a.get(key), b.get(key)))

    la, lb = a.get("location", {}), b.get("location", {})
    for key in ("mapGroup", "mapNum", "warpId", "x", "y"):
        if la.get(key) != lb.get(key):
            lines.append("location.%s: %r vs %r"
                         % (key, la.get(key), lb.get(key)))

    fa, fb = set(a.get("flags", [])), set(b.get("flags", []))
    for i in sorted(fa - fb):
        lines.append("%s: set on left only" % name_flag(i))
    for i in sorted(fb - fa):
        lines.append("%s: set on right only" % name_flag(i))

    va, vb = a.get("vars", {}), b.get("vars", {})
    for i in sorted(set(va) | set(vb)):
        if va.get(i, 0) != vb.get(i, 0):
            lines.append("%s: %d vs %d" % (name_var(i), va.get(i, 0),
                                           vb.get(i, 0)))

    pa, pb = a.get("party", []), b.get("party", [])
    if len(pa) != len(pb):
        lines.append("party size: %d vs %d" % (len(pa), len(pb)))
    for i in range(min(len(pa), len(pb))):
        if pa[i]["level"] != pb[i]["level"]:
            lines.append("party[%d].level: %d vs %d"
                         % (i, pa[i]["level"], pb[i]["level"]))

    return lines
