# Weather FX 8.2.10 — Dynamic 3D Leaf Size Continuity

Built directly from exact Weather FX 8.2.9.

## Fix
3D wind-blown leaves no longer bake their spawn distance into their lifetime world size. A leaf spawned far from the player now becomes appropriately larger as it blows closer, and becomes smaller again as it moves away. The same repair removes the permanent spawn-distance opacity bias.

The leaf itself keeps one intrinsic size for its lifetime. Current camera/player distance remains the only distance-dependent presentation scale.

## Preserved
Leaf count, wind trajectories, flutter/tumble, voxel/NPC collision, wall response, settling/piles, seasonal color, weather ownership, and non-leaf precipitation are unchanged.
