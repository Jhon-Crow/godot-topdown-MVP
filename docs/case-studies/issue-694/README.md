# Case Study: Issue #694 - Laser Glow Lag When Laser Moves

## Problem Statement

After the laser glow effect was added in PR #655 (Issue #654), the glow visually
lags behind the laser beam when the player/weapon moves. The laser line itself
tracks correctly, but the glow (specifically the dust particle effect) trails
behind with a visible delay.

Original issue (Russian): "когда лазер перемещается свечение следует за ним с
задержкой" — "when the laser moves, the glow follows with a delay."

## Timeline of Events

| Date | Event |
|------|-------|
| 2026-02-08 | PR #655 merged: smooth continuous glow for laser sights (Issue #654) |
| 2026-02-08 | Issue #694 opened: laser glow lags behind when laser moves |
| 2026-02-09 | Root cause identified and fix implemented |

## Architecture Overview

The laser glow system (from PR #655) consists of three visual components:

1. **Multi-layered Line2D glow aura** — 4 Line2D nodes with additive blending at
   progressively wider widths and lower opacities
2. **Endpoint PointLight2D** — circular glow at the laser hit point
3. **GpuParticles2D dust particles** — small glowing motes along the beam,
   simulating atmospheric dust catching laser light

All three are created as children of the weapon node in `LaserGlowEffect.Create()`.

### Node Hierarchy

```
Player (CharacterBody2D)
├── PlayerModel (Node2D)
│   └── WeaponMount (Node2D)
├── MakarovPM (Node2D) [position: (0, 6)]
│   ├── LaserSight (Line2D)        ← main laser beam
│   ├── LaserGlow_0 (Line2D)       ← core boost glow layer
│   ├── LaserGlow_1 (Line2D)       ← inner glow layer
│   ├── LaserGlow_2 (Line2D)       ← mid glow layer
│   ├── LaserGlow_3 (Line2D)       ← outer glow layer
│   ├── LaserEndpointGlow (PointLight2D)
│   └── LaserDustParticles (GpuParticles2D)  ← THIS LAGS
└── Camera2D
```

### Update Flow

1. `Player._PhysicsProcess()` — moves player via `MoveAndSlide()`
2. `Weapon._Process()` — calls `UpdateLaserSight()` which:
   - Calculates laser direction from `GlobalPosition` towards mouse
   - Performs raycast to find obstacles
   - Updates `LaserSight` Line2D points (local coords)
   - Calls `_laserGlow.Update(Vector2.Zero, endPoint)`
3. `LaserGlowEffect.Update()` — updates all glow components:
   - Sets Line2D point positions (immediate, no lag)
   - Sets PointLight2D position (immediate, no lag)
   - Sets GpuParticles2D position/rotation/emission box (**LAGS**)

## Root Cause Analysis

### Why Line2D glow layers DON'T lag

The Line2D glow layers (`LaserGlow_0` through `LaserGlow_3`) use
`SetPointPosition()` which directly updates the vertex positions in the render
buffer. Since these are children of the weapon node and use local coordinates,
they inherit the weapon's transform automatically. The visual update is immediate
within the same frame.

### Why GpuParticles2D dust particles DO lag

The `GpuParticles2D` node (`LaserDustParticles`) was created with the default
`UseLocalCoordinates = false` (corresponding to `local_coords = false` in
GDScript). This means:

1. **Particles use global (world) coordinates** for their positions
2. When a particle is emitted, its position is calculated in world space
3. When the parent node moves, **already-emitted particles stay at their old
   world positions** — they don't follow the parent
4. Only newly emitted particles appear at the new parent position
5. This creates a visible "trail" or "lag" effect where old particles are left
   behind at the previous position

This is a [well-known behavior in Godot 4](https://github.com/godotengine/godot/issues/70748):
GPU particles with global coordinates jitter and lag when attached to moving
nodes.

### Technical Details

The `UpdateDustParticles()` method correctly updates the emitter's Position and
Rotation each frame:

```csharp
_dustParticles.Position = (startPoint + endPoint) / 2.0f;
_dustParticles.Rotation = beamVector.Angle();
_dustMaterial.EmissionBoxExtents = new Vector3(beamLength / 2.0f, DustEmissionHalfHeight, 0.0f);
```

However, with global coordinates:
- The emitter moves to the new position ✓
- New particles emit from the new position ✓
- **Existing particles remain at their old world positions** ✗

With particle lifetime of 0.8 seconds and 80 particles, at any given moment there
are particles spread across multiple previous positions, creating a visible
trailing/lagging glow behind the beam.

## Solution

### Fix Applied

Set `UseLocalCoordinates = true` on the `GpuParticles2D` node:

```csharp
_dustParticles = new GpuParticles2D
{
    // ... other properties ...
    UseLocalCoordinates = true  // Fix: particles move with parent (Issue #694)
};
```

### Why This Fixes the Issue

With `UseLocalCoordinates = true`:
1. Particles are emitted and live in the **parent node's local coordinate space**
2. When the parent (weapon → player) moves, **all particles** (existing and new)
   move with it
3. The emission box position/rotation/extent updates in `UpdateDustParticles()`
   continue to work correctly — they're now relative to the particle node's own
   transform, which is relative to the weapon
4. No trailing artifact occurs because particles are anchored to the weapon's
   local space, not to world space

### Trade-offs Considered

| Aspect | Global Coords (before) | Local Coords (after) |
|--------|----------------------|---------------------|
| Particles follow parent movement | No (lag) | Yes (no lag) |
| Particles follow parent rotation | Partially | Yes |
| Trail effect when weapon rotates | Old particles stay at old angle | Old particles rotate with weapon |
| Performance | Same | Same |
| Visual quality | Laggy glow | Smooth glow |

The rotation-following behavior with local coords is actually **desirable** for
this use case. The dust particles represent atmospheric scatter along the beam,
and should always appear along the current beam direction, not at historical
positions.

### Files Modified

| File | Change |
|------|--------|
| `Scripts/Weapons/LaserGlowEffect.cs` | Added `UseLocalCoordinates = true` to GpuParticles2D |

## References

- [Issue #694](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/694) — original bug report
- [PR #655](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/655) — PR that introduced the glow effect
- [Issue #654](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/654) — original glow feature request
- [Godot Issue #70748](https://github.com/godotengine/godot/issues/70748) — GPUParticles2D jittering in global coordinates
- [Godot GPUParticles2D docs](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html) — UseLocalCoordinates property
- [Godot Issue #71480](https://github.com/godotengine/godot/issues/71480) — local_coords rotation issues
