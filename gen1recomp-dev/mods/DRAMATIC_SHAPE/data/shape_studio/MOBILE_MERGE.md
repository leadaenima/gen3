# Mobile Map Studio — pull edits off the phone and merge on Desktop

Presentational voxel edits made on the **Android APK** (or `POKEPORT_TOUCH=1`)
live in the app **save directory**, not in the Desktop `mods/DRAMATIC_SHAPE`
tree. Use **Export** on the phone, copy the file to your PC, then **Import/Merge**
in Desktop Shape Studio (or run the merge tool).

## On the phone (APK)

1. Turn voxel mode on (**SELECT** cycles camera rungs / press **3** if you have a keyboard).
2. Tap **MAP EDIT** (top-right). The virtual d-pad hides while the studio is open.
3. Tap a tile → **H+** / **H−** to raise a fence, **Level** then drag a rectangle,
   **Chroma** then tap green in the world, **Texture** to eyedrop, etc.
4. Tap **Save** (or **Save all**). Status shows the save-dir path.
5. Tap **Export**. That writes:
   - `shape_studio/overrides.lua` (always loaded/merged on boot)
   - `shape_studio/export/mobile_YYYYMMDD_HHMMSS.lua` (full pack + metadata)

### Where is the save dir?

Android LOVE save identity (typical):

`Android/data/<app.id>/files/save/`  
(or the path shown in the studio status after Save / Export)

You can also use a file manager / `adb pull` on that folder. Look for
`shape_studio/export/mobile_*.lua`.

## On the Desktop

### Option A — in-game Import/Merge

1. Run the Desktop game with DRAMATIC_SHAPE (Play-Developer / folder install).
2. Open Shape Studio (**F8**, voxel on).
3. Press **I** or click **[I] import/merge** on the side panel.
   - Merges the newest `shape_studio/export/*.lua` found under the LOVE save
     dir, **or** pick a file if `love.system.pickFile` is available.
4. Or copy `mobile_….lua` into the game’s save dir under
   `shape_studio/export/`, then press **I**.
5. Press **3** / force save so Desktop writes
   `mods/DRAMATIC_SHAPE/data/shape_studio/overrides.lua`.

### Option B — tools script

From a shell with `lua` (or LOVE), after copying the export next to the tool:

```text
lua mods/DRAMATIC_SHAPE/tools/merge_mobile_overrides.lua path/to/mobile_YYYYMMDD_HHMMSS.lua
```

That deep-merges into `data/shape_studio/overrides.lua` (cells / types /
sprites / chromakey / maps). Same key → incoming wins; `rev` becomes
`max(old,new)+1`.

## Desktop testing without a phone

```text
set POKEPORT_TOUCH=1
Play-Developer.bat
```

You get the on-screen **MAP EDIT** button and the large touch toolbar.

## Next APK package

These files ship inside the mod; no special APK code change is required.
Rebuild when you want them on device:

```bash
scripts/build_android.sh
# or package-only:
scripts/build_android.sh --package-only
```

Then install the new APK / refresh the embedded `game.love` + mods as you
usually do. Restart the app after install so boot reloads overrides.

## Notes

- Presentational only — no collision rewrite.
- Desktop keyboard Shape Studio (**F8**, wheel, C/T/L, …) is unchanged.
- Virtual gamepad is suppressed while MAP EDIT is open so it cannot eat taps.