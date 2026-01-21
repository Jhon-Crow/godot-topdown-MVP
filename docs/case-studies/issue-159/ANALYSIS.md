# Case Study: Issue 159 - Wall Penetration System Analysis

## Issue Summary

This document analyzes the implementation and debugging of the wall penetration system for bullets in the game.

## Reported Problems

### Initial Issues (First Round)
1. **Hole display not working** - Entry/exit holes were circular decals, not bullet trails
2. **Penetration not working for player** - Player bullets may not have been triggering penetration
3. **Enemy bullets don't disappear after 48px travel** - Bullets were not being destroyed at max penetration distance

### Follow-up Issues (Second Round - User Feedback)
1. **Player bullets pass through walls only due to a bug** - No trail drawn, bullets don't disappear after penetration
2. **Enemy bullet trails are "floating in the air"** - Trails incorrectly positioned, not drawn along bullet path

## Root Cause Analysis

### Problem 1: Visual Holes (First Round)

**Original Implementation:**
- `spawn_penetration_hole()` in ImpactEffectsManager spawned `BulletHole.tscn` (circular radial gradient)
- Entry and exit holes were separate circular decals at penetration points

**Issue:**
- User expected a continuous dark trail through the wall (bullet path), not separate circular holes
- The visual feedback didn't clearly show the bullet trajectory through the wall

**Fix:**
- Disabled circular entry/exit hole spawning in `_spawn_penetration_hole_effect()`
- The visual trail is now created entirely by the `PenetrationHole` collision hole (Line2D drawing a dark line from entry to exit)
- Dust effects are still spawned at entry/exit for realism

### Problem 2: Player Bullets Not Penetrating (Critical Root Cause)

**Root Cause Discovery:**
Analysis of game logs revealed that penetration logs (e.g., `[Bullet] _get_distance_to_shooter`) appeared ONLY for enemy bullets, never for player bullets. This led to tracing the scene hierarchy:

- `BuildingLevel.tscn` uses `Player.tscn` (C# version)
- C# `Player.tscn` has `AssaultRifle.tscn` (C# version)
- C# `AssaultRifle.tscn` spawns bullets from `Bullet.tscn` (C# version)
- C# `Bullet.tscn` uses `Scripts/Projectiles/Bullet.cs`

**Critical Finding:**
The C# `Bullet.cs` (used by player) had NO penetration logic - only ricochet mechanics. The penetration system was only implemented in the GDScript `bullet.gd` (used by enemies).

**Fix:**
Ported complete penetration system from GDScript `bullet.gd` to C# `Bullet.cs`:
- Added penetration configuration constants
- Added penetration state tracking variables
- Connected `BodyExited` signal for detecting wall exit
- Added penetration tracking in `_PhysicsProcess`
- Modified `OnBodyEntered` with distance-based penetration logic
- Added helper methods: `LogPenetration`, `OnBodyExited`, `GetDistanceToShooter`, `CalculateDistancePenetrationChance`, `IsInsidePenetrationHole`, `TryPenetration`, `IsStillInsideObstacle`, `ExitPenetration`, `SpawnDustEffect`, `SpawnCollisionHole`
- Modified `BaseWeapon.cs` to set `ShooterPosition` on spawned bullets

### Problem 3: Enemy Bullet Trails Floating (Line2D Positioning Bug)

**Root Cause:**
When `Line2D.top_level = true` is set on a node that's already positioned in the scene:
1. The Line2D's transform becomes independent of its parent
2. Its `position` property becomes its global position (where it was when top_level was set)
3. Points added with `add_point()` are in local coordinates relative to the Line2D's origin

When the bullet spawns, its trail Line2D is at the bullet's spawn position. When we then add the bullet's `global_position` as a point, the point appears at `trail.global_position + bullet.global_position` - effectively doubling the offset!

**Example:**
- Bullet spawns at global position (500, 300)
- Trail Line2D inherits position (500, 300) when `top_level = true`
- When we add point at global (550, 300), Line2D interprets it as local offset
- Point appears at (500 + 550, 300 + 300) = (1050, 600) - wrong position!

**Fix:**
Reset Line2D position to `Vector2.ZERO` immediately after setting `top_level = true`:
```gdscript
_trail.top_level = true
_trail.position = Vector2.ZERO  # Reset so points are truly global
```

Applied to:
- `scripts/projectiles/bullet.gd` - enemy bullet trails
- `Scripts/Projectiles/Bullet.cs` - player bullet trails
- `scripts/effects/penetration_hole.gd` - penetration visual trails

### Problem 4: Raycast Distance Too Short (First Round)

**Original Implementation:**
```gdscript
func _is_still_inside_obstacle() -> bool:
    var ray_end := global_position + direction * 2.0
```

**Issues:**
1. Raycast distance (2 pixels) was too short for bullet speed (2500 px/s = ~41 pixels/frame at 60 FPS)
2. When max penetration distance was exceeded, bullet was destroyed without leaving a visual trail

**Fixes:**
1. Increased raycast distance to 50 pixels
2. Added visual trail spawning before destroying bullet at max distance
3. Added dust effect at termination point

## Debug Logging

Debug logging is enabled (`_debug_penetration = true` / `DebugPenetration = true`) in both bullet scripts. Key log messages:

- `[Bullet] Starting wall penetration at ...`
- `[Bullet] Distance to wall: ... (N% of viewport)`
- `[Bullet] _get_distance_to_shooter: shooter_position=..., shooter_id=...`
- `[Bullet] Point-blank shot - 100% penetration, ignoring ricochet`
- `[Bullet] Max penetration distance exceeded: ...`
- `[Bullet] Exiting penetration at ... after traveling N pixels through wall`

## Files Modified

### First Round
1. `scripts/projectiles/bullet.gd` - Main penetration logic fixes, raycast improvements
2. `scripts/characters/player.gd` - Removed conditional shooter_position check
3. `scripts/objects/enemy.gd` - Removed conditional shooter_position check
4. `scripts/effects/penetration_hole.gd` - Collision hole with visual trail

### Second Round (Root Cause Fixes)
1. `Scripts/Projectiles/Bullet.cs` - Added complete penetration system to C# bullet (player)
2. `Scripts/AbstractClasses/BaseWeapon.cs` - Set ShooterPosition on spawned bullets
3. `scripts/projectiles/bullet.gd` - Fixed Line2D trail positioning
4. `scripts/effects/penetration_hole.gd` - Fixed Line2D trail positioning

## Key Lesson Learned

**Dual-Language Codebase Pitfall:** When a Godot project has both GDScript and C# implementations of the same entity (bullets in this case), features must be implemented in BOTH versions. The player using C# bullets and enemies using GDScript bullets meant penetration worked only for enemies.

**Line2D top_level Behavior:** Setting `top_level = true` on a child node preserves its current global position. When adding points meant to be at global coordinates, the node's position must be reset to (0,0) first.

## Game Logs Analyzed

Logs stored in `docs/case-studies/issue-159/logs/`:
- `game_log_20260121_071155.txt`
- `game_log_20260121_071551.txt`
- `game_log_20260121_072518.txt`
- `game_log_20260121_072958.txt`
- `game_log_20260121_073202.txt`
- `game_log_20260121_080441.txt` (Second round)
- `game_log_20260121_080549.txt` (Second round)
- `game_log_20260121_080741.txt` (Second round)

## Testing Recommendations

1. Test **player** shooting at thin walls (24px) at close range - should see penetration trail
2. Test **player** shooting at thick walls - bullet should stop inside and leave partial trail
3. Test enemy shooting at player through walls - should see trail and 48px limit
4. Verify bullet trails follow the bullet path correctly (not floating in air)
5. Verify dust effects appear at entry and exit points
6. Check debug logs for penetration messages from BOTH player and enemy bullets
