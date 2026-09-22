# Weather FX 8.1.60 — 2D NPC Lightning / Visible Strike Smoke

## 2D NPC lightning

A normal 2D lightning event may now use the existing **CHARACTER STRIKES** house rule instead of always landing on terrain. Each scheduled flat-renderer strike receives the configured independent character-strike roll (default **10%**). When the roll succeeds and a valid NPC is currently visible outdoors, the already-scheduled bolt is rebuilt so its endpoint lands on that NPC's current head/upper-body sprite position. Thunder timing, strike serial, flash timing and ordinary strike scheduling are preserved.

Targeting is based on the actual live overworld object and current sprite pose at call time. It understands the real 160×144 game viewport inside letterboxed windows, excludes the player and obvious non-character field objects such as boulders/item balls/fossils, and fails open to ordinary terrain lightning if no valid target exists.

## 2D reaction

The struck NPC is never modified in gameplay state. Weather FX temporarily redraws the live sprite as:

1. rapid white/black electrical flashes;
2. a cartoon skeleton silhouette during dark flash frames;
3. a charred silhouette with bright eyes;
4. a visible smoke plume rising from the head;
5. automatic restoration after the configured reaction duration (default **3 seconds**).

The reaction compositor stays alive long enough to finish even if the storm channel itself eases away immediately after impact. NPC coordinates, collision, AI, scripts, dialogue, save flags and sprite assets remain untouched.

## Smoke visibility repair

The prior 3D smoke path could technically submit puffs but still be visually absent because the puffs were small, dark and close enough to the struck actor for normal third-person perspective/depth to reduce them to a sub-pixel smudge. 8.1.60 keeps smoke world-anchored and depth-tested but makes it readable: six puffs use a larger bounded footprint, a dark charcoal outer body, a lighter inner body, stronger alpha and a small camera-facing offset.

The 2D reaction uses the same readability intent with large source-resolution circles that remain visible after integer scaling. Smoke begins after the initial electrical flash rather than being hidden inside the brightest impact frames.

## Preservation

- default character-strike chance remains **10%**;
- default reaction duration remains **3 seconds**;
- ordinary terrain lightning remains unchanged when the NPC roll misses;
- 3D per-bolt targeting and simultaneous burst behavior remain intact;
- 8.1.59 snow point-plume repair and all earlier tornado/blackout fixes remain mandatory regressions.
