# Case Study: Issue #692 - Enemy Self-Destruct Protection

## Problem Statement

**Issue**: "enemies still sometimes blow themselves up" (ru: "враги всё ещё иногда взрывают сами себя")

Despite two previous attempts to fix enemy self-damage from their own grenades (PR #376 and PR #658), enemies were still occasionally destroying themselves with their own grenade explosions and shrapnel.

## Timeline of Previous Fixes

| Date | PR | Fix Description |
|------|-----|-----------------|
| 2026-01-25 | #376 | Added min throw distance check: `blast_radius + safety_margin` (275px for frag grenades) |
| 2026-02-08 | #658 | Added `MIN_ARMING_DISTANCE = 80px` in GDScript frag_grenade.gd to prevent impact explosion near thrower |

## Root Cause Analysis

The self-destruct bug persisted because **5 independent damage vectors** were not addressed by previous fixes:

### Vector 1: C# Arming Distance Bypass (CRITICAL)

**File**: `Scripts/Projectiles/GrenadeTimer.cs`, method `OnBodyEntered()`

The GDScript `frag_grenade.gd` had `MIN_ARMING_DISTANCE = 80px` protection (added in PR #658), but the C# `GrenadeTimer` component - which is the code that **actually runs in exported builds** (GDScript `_physics_process()` doesn't run in exports per Issue #432) - had **NO arming distance check**. It would trigger explosion on ANY body contact as long as `IsThrown == true`.

This meant the PR #658 fix was essentially ineffective in production builds.

### Vector 2: No Thrower Exclusion from HE Blast Damage

**Files**: `frag_grenade.gd` method `_get_enemies_in_radius()`, `defensive_grenade.gd` method `_get_enemies_in_radius()`, `GrenadeTimer.cs` method `ApplyFragExplosion()`

ALL enemies in the "enemies" group within effect radius received 99 HE damage. There was **no check** to exclude the enemy who threw the grenade. If the enemy was within 225px of the explosion position (e.g., grenade bounced back, hit a wall nearby, or enemy moved toward explosion), they would take full lethal damage.

### Vector 3: C# Shrapnel Missing source_id

**File**: `GrenadeTimer.cs` method `SpawnShrapnel()`

When C# code spawned shrapnel (which happens in exported builds), it did NOT set `source_id` on shrapnel instances. The code set `direction` but omitted `source_id`, leaving it at the default value of `-1`. This means shrapnel from C#-spawned explosions had no collision exclusion at all.

### Vector 4: Shrapnel Has No Thrower Tracking

**File**: `scripts/projectiles/shrapnel.gd`

Shrapnel's `source_id` only tracked the **grenade** instance (to avoid hitting the grenade RigidBody2D itself), not the **enemy** that threw it. Even when `source_id` was correctly set, shrapnel could freely hit and damage the throwing enemy.

### Vector 5: Defensive Grenade Same Vulnerabilities

**File**: `scripts/projectiles/defensive_grenade.gd`

The defensive grenade (700px blast radius, 40 shrapnel pieces) had identical vulnerabilities to the frag grenade - no thrower exclusion from blast damage and no thrower tracking on shrapnel.

## Fix Implementation

### Approach: Thrower ID Pipeline

Added `thrower_id` tracking throughout the complete grenade-to-damage pipeline:

```
Enemy throws grenade
  → thrower_id set on GDScript grenade (frag/defensive)
  → thrower_id set on C# GrenadeTimer via SetThrower()
    → Explosion damage excludes thrower (both GDScript and C# paths)
    → Shrapnel inherits thrower_id from grenade
      → Shrapnel collision checks exclude thrower (body_entered + area_entered)
```

### Changes by File

1. **GrenadeTimer.cs** (C# - runs in exports):
   - Added `ThrowerId` property and `SetThrower()` method
   - Added `MinArmingDistance`, `_spawnPosition`, `_impactArmed` for arming distance check
   - `OnBodyEntered()`: Added arming distance check matching GDScript
   - `ApplyFragExplosion()`: Skip thrower in damage loop
   - `SpawnShrapnel()`: Set `source_id` and `thrower_id` on shrapnel

2. **GrenadeTimerHelper.cs** (C# autoload for GDScript interop):
   - Added `SetThrower(RigidBody2D grenade, long throwerId)` method

3. **frag_grenade.gd** (GDScript):
   - Added `thrower_id` variable
   - `_get_enemies_in_radius()`: Skip thrower
   - `_spawn_shrapnel()`: Pass `thrower_id` to shrapnel

4. **defensive_grenade.gd** (GDScript):
   - Same changes as frag_grenade.gd

5. **shrapnel.gd** (GDScript):
   - Added `thrower_id` variable
   - `_on_body_entered()`: Check `thrower_id` for exclusion
   - `_on_area_entered()`: Check parent's instance ID against `thrower_id`

6. **enemy_grenade_component.gd** (GDScript):
   - Set `thrower_id` on GDScript grenade before adding to scene
   - Call `_set_grenade_thrower()` to set on C# GrenadeTimer
   - Added `_set_grenade_thrower()` helper method

7. **grenadier_grenade_component.gd** (GDScript):
   - Same thrower tracking as enemy_grenade_component.gd

## Design Decisions

### Why thrower_id instead of invulnerability window?

A time-based invulnerability window would be fragile and could interfere with legitimate damage from other sources. Tracking the specific thrower provides precise exclusion without affecting any other game mechanics.

### Why -1 as default thrower_id?

Player-thrown grenades should still damage enemies (and the player themselves). Using `-1` as "no thrower" means player grenades behave exactly as before - only enemy-thrown grenades get the self-damage protection.

### Why check in both GDScript and C#?

Due to Issue #432 (GDScript failing in exports), the game has dual GDScript/C# paths for grenade logic. Both paths must implement the protection to ensure it works in all build configurations.
