# Weather FX 8.2.2 — Mobile 3D Snow Universal GPU Path + Zenith Sky Repair

Built directly from exact Weather FX 8.2.1.

## 3D snow performance

The critical failure was structural: low 3D-snow populations could remain on the legacy CPU simulator/dynamic-mesh renderer, so even the lowest setting could be slower than the higher procedural path on weak phones. 8.2.2 probes the procedural renderer before any visible CPU snow mesh is constructed and permits every nonzero snow population to use it. Devices without usable instancing now receive immutable GPU snow pages instead of per-frame vertex construction/upload.

The procedural shaders are also cheaper: the flake fragment shape avoids angle, length and trigonometric operations; snow billboard axes are calculated once per draw; smooth sway/tumble uses a continuous trig-free periodic approximation; and storm patch modulation is transcendental-free. These changes do not reduce the authored 100,000 SNOW or 200,000 MAX BLIZZARD ceilings, render distance, or per-render-frame animation.

## Cloud bank / sun / moon zenith repair

Cloud billboards now derive a robust screen basis from the live view-projection matrix before falling back to camera vectors, preventing the billboard basis from collapsing when the player looks straight up. Sun/moon direction projection likewise uses a complete perspective VP matrix when available, while retaining the prior basis path for identity/legacy compatibility matrices so constellation and planet rendering remains intact.

## Preserved behavior

The continuous no-emitter SNOW/BLIZZARD world field, RAVE 2D support, doubled RAVE cloud population, battle lasers, 2D lightning selector, water, tornado, celestial timing and all other 8.2.1 behavior are retained.
