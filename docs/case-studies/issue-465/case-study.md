# Case Study: Issue #465 - Muzzle Flash Passing Through Player/Enemy

## Issue Description

**Original (Russian)**: "вспышка оружия проходит сквозь игрока/врага - за спиной стреляющего должна быть 'тень', то есть свет не должен проходить сквозь его."

**Translation**: "weapon flash passes through player/enemy - there should be a 'shadow' behind the shooter, meaning light should not pass through them."

## Root Cause Analysis

### Background

In the previous issue #455, the muzzle flash effect was implemented with:
- `PointLight2D` with `shadow_enabled = true`
- Shadow color, PCF5 filtering, and smoothing configured
- `LightOccluder2D` nodes added to walls and obstacles in level scenes

However, the **player and enemy characters** were missing `LightOccluder2D` nodes.

### Why Light Passes Through Characters

In Godot 4's 2D lighting system, `PointLight2D` shadows work by detecting `LightOccluder2D` nodes in the scene:

1. **PointLight2D** emits light and checks for occluders when `shadow_enabled = true`
2. **LightOccluder2D** defines geometry that blocks light using `OccluderPolygon2D`
3. Without an occluder, light passes through objects regardless of collision shapes

The muzzle flash light was correctly casting shadows on walls (which have occluders), but passing through characters (which lacked occluders).

### Solution

Add `LightOccluder2D` nodes with appropriate `OccluderPolygon2D` resources to all character scenes:

| Scene | Collision Shape | Occluder Polygon |
|-------|----------------|------------------|
| Player.tscn (GDScript) | CircleShape2D, r=16 | 12-point circle, r=16 |
| Player.tscn (C#) | CircleShape2D, r=16 | 12-point circle, r=16 |
| Enemy.tscn (GDScript) | CircleShape2D, r=24 | 12-point circle, r=24 |
| Enemy.tscn (C#) | RectangleShape2D, 48x48 | Rectangle 48x48 |

## Technical Implementation

### Circle Polygon Approximation

For circular collision shapes, a 12-point polygon provides a good approximation:

```
Angle   X (r*cos)   Y (r*sin)
0°      r           0
30°     r*0.866     r*0.5
60°     r*0.5       r*0.866
90°     0           r
120°    -r*0.5      r*0.866
150°    -r*0.866    r*0.5
180°    -r          0
210°    -r*0.866    -r*0.5
240°    -r*0.5      -r*0.866
270°    0           -r
300°    r*0.5       -r*0.866
330°    r*0.866     -r*0.5
```

For radius 16 (player):
```
PackedVector2Array(16, 0, 13.86, 8, 8, 13.86, 0, 16, -8, 13.86, -13.86, 8, -16, 0, -13.86, -8, -8, -13.86, 0, -16, 8, -13.86, 13.86, -8)
```

For radius 24 (enemy):
```
PackedVector2Array(24, 0, 20.78, 12, 12, 20.78, 0, 24, -12, 20.78, -20.78, 12, -24, 0, -20.78, -12, -12, -20.78, 0, -24, 12, -20.78, 20.78, -12)
```

### Rectangle Polygon (C# Enemy)

For the 48x48 rectangle collision shape:
```
PackedVector2Array(-24, -24, 24, -24, 24, 24, -24, 24)
```

## Files Modified

1. **scenes/characters/Player.tscn** (GDScript)
   - Added `OccluderPolygon2D_player` sub-resource (12-point circle, r=16)
   - Added `LightOccluder2D` node with the occluder

2. **scenes/characters/csharp/Player.tscn** (C#)
   - Added `OccluderPolygon2D_player` sub-resource (12-point circle, r=16)
   - Added `LightOccluder2D` node with the occluder

3. **scenes/objects/Enemy.tscn** (GDScript)
   - Added `OccluderPolygon2D_enemy` sub-resource (12-point circle, r=24)
   - Added `LightOccluder2D` node with the occluder

4. **scenes/objects/csharp/Enemy.tscn** (C#)
   - Added `OccluderPolygon2D_enemy` sub-resource (48x48 rectangle)
   - Added `LightOccluder2D` node with the occluder

## Expected Result

After this fix:
- When the player fires, a shadow appears behind them (opposite the muzzle flash direction)
- When enemies fire, shadows appear behind them
- Characters now properly block the muzzle flash light, creating realistic shadowing

## Related Issues

- Issue #455: Muzzle flash effect implementation (added lighting, shadows on walls)
- This issue (#465): Extension to make characters cast shadows

## References

- Godot 4 PointLight2D documentation
- Godot 4 LightOccluder2D documentation
- Previous case study: `docs/case-studies/issue-455/case-study.md`
