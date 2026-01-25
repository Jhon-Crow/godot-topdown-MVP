# Technical Analysis: Current Grenade Throwing Implementation

## Current Implementation Overview

### Key Constants (scripts/objects/enemy.gd)

```gdscript
@export var grenade_max_throw_distance: float = 600.0  # Line 174
@export var grenade_min_throw_distance: float = 150.0  # Line 177
@export var grenade_throw_delay: float = 0.4           # Animation telegraph
@export var grenade_throw_cooldown: float = 15.0       # Cooldown between throws
@export var grenade_inaccuracy: float = 0.15           # ±0.15 radians = ±8.6°
```

### Frag Grenade Parameters (scripts/projectiles/frag_grenade.gd)

```gdscript
@export var effect_radius: float = 225.0        # Line 17 - Blast radius
@export var explosion_damage: int = 99          # Line 30 - Flat damage
@export var shrapnel_count: int = 4             # Line 20
```

## Critical Issue Identified

### The Problem
```
Current minimum throw distance: 150 pixels
Frag grenade blast radius:     225 pixels
Safety gap:                    -75 pixels (UNSAFE!)
```

**Enemy can throw grenade at targets 150-224 pixels away and damage itself.**

### Affected Code Path

#### 1. Grenade Throw Decision (`try_throw_grenade()` - Line 5505)
```gdscript
func try_throw_grenade() -> bool:
    if not _can_throw_grenade():
        return false

    var target_position := _get_grenade_target_position()
    if target_position == Vector2.ZERO:
        return false

    # Check distance constraints
    var distance := global_position.distance_to(target_position)
    if distance < grenade_min_throw_distance:  # 150px - TOO SMALL!
        _log_grenade("Target too close...")
        return false

    if distance > grenade_max_throw_distance:  # 600px
        # Clamp to max
        ...

    # Check throw path
    if not _is_throw_path_clear(target_position):
        return false

    # Execute - NO SAFETY CHECK FOR BLAST RADIUS!
    _execute_grenade_throw(target_position)
    return true
```

**Missing Check:** No validation that enemy is outside blast radius of target position.

#### 2. Grenade Target Selection (`_get_grenade_target_position()` - Line 5439)

Different triggers target different positions:

| Trigger | Target Position | Risk Level |
|---------|----------------|------------|
| Trigger 6 (Desperation) | Last known player position | HIGH - No constraints |
| Trigger 4 (Sound) | Vulnerable sound position | HIGH - Could be close |
| Trigger 2 (Pursuit) | 50% distance to player | CRITICAL - If player at 200px, targets 100px! |
| Trigger 3 (Witness) | Last known player position | MEDIUM |
| Trigger 5 (Fire Zone) | Fire zone center | MEDIUM |
| Trigger 1 (Suppression) | Last known position | LOW - Player hidden |

**Trigger 2 is especially dangerous:**
```gdscript
# Trigger 2: Pursuit - target halfway between enemy and player
if _should_trigger_pursuit_grenade():
    if _memory and _memory.has_target():
        var player_pos := _memory.suspected_position
        var halfway := global_position.lerp(player_pos, 0.5)  # 50% distance
        return halfway
```

Example scenario:
- Enemy at (0, 0)
- Player at (200, 0) - 200px away
- Target position: (100, 0) - **only 100px from enemy!**
- Grenade explodes at ~100px from enemy
- Blast radius is 225px
- **Enemy takes full 99 damage and dies!**

#### 3. Grenade Execution (`_execute_grenade_throw()` - Line 5557)

```gdscript
func _execute_grenade_throw(target_position: Vector2) -> void:
    # ... delay and safety checks ...

    # Calculate throw direction with inaccuracy
    var base_direction := (target_position - global_position).normalized()
    var inaccuracy_angle := randf_range(-grenade_inaccuracy, grenade_inaccuracy)
    var throw_direction := base_direction.rotated(inaccuracy_angle)

    # Calculate throw distance
    var distance := global_position.distance_to(target_position)  # Distance to TARGET

    # Instantiate and throw grenade
    var grenade: Node2D = grenade_scene.instantiate()
    grenade.global_position = global_position + throw_direction * spawn_offset

    # Activate and throw
    grenade.activate_timer()
    grenade.throw_grenade(throw_direction, distance)

    # NO CHECK: Will enemy be in blast radius when grenade lands?
}
```

**Missing Validation:**
- Does not check if `global_position.distance_to(target_position) >= blast_radius`
- Does not account for grenade landing position (may differ from target due to physics)
- Does not check if enemy will be in blast zone when grenade explodes

## Why Current Implementation is Unsafe

### Issue 1: Minimum Distance Too Low
```
grenade_min_throw_distance = 150px
effect_radius = 225px
Unsafe zone: 150-224px (74 pixel danger zone!)
```

### Issue 2: No Blast Radius Awareness
The enemy AI treats grenades like bullets - just checks minimum distance to prevent point-blank throws. It doesn't understand that grenades have an area of effect.

### Issue 3: Target Selection Ignores Enemy Position
Trigger calculations focus on where to throw, not whether throwing is safe. Trigger 2 (Pursuit) particularly problematic.

### Issue 4: No Prediction of Landing Position
Enemy throws toward target_position, but grenade may:
- Bounce off walls
- Slide on ground
- Hit obstacles and explode early
- All of these could bring explosion closer to enemy

## Impact Analysis

### Severity: HIGH
- Enemy can kill itself with its own grenade
- Breaks player immersion (enemies appear stupid)
- Wastes enemy resources (grenades are limited)
- Reduces enemy threat level (self-damage)

### Frequency: MODERATE
- Occurs primarily in close-range combat
- Trigger 2 (Pursuit) and Trigger 6 (Desperation) most likely to cause issue
- More common when player is aggressive

### Reproducibility: HIGH
- Predictable when player closes distance during pursuit
- Always occurs when distance < 225px and grenade triggers

## Root Cause Summary

1. **Design Flaw**: `grenade_min_throw_distance` (150px) set without considering blast radius (225px)
2. **Missing Safety Check**: No validation that enemy is outside blast radius before throwing
3. **Target Selection**: Trigger 2 can select targets too close to enemy position
4. **No Self-Preservation**: AI doesn't check if throw will harm itself

## Data Flow Diagram

```
Enemy AI Process
    ↓
Check if grenade throw triggered (6 triggers)
    ↓
try_throw_grenade()
    ↓
_can_throw_grenade() - Basic checks only
    ↓
_get_grenade_target_position() - Select target (may be close!)
    ↓
Check: distance < 150px? ← PROBLEM: Should be >= 225px + margin
    ↓
_is_throw_path_clear() - Check obstacles
    ↓
_execute_grenade_throw() ← NO BLAST RADIUS CHECK HERE
    ↓
Grenade thrown
    ↓
Grenade explodes on impact (frag grenade)
    ↓
Damage all entities in 225px radius ← Enemy may be in this radius!
```

## Files Requiring Changes

1. **scripts/objects/enemy.gd** (Primary)
   - Update `grenade_min_throw_distance` from 150 to 275+ pixels
   - Add blast radius safety check in `try_throw_grenade()`
   - Add logging for safety check failures

2. **scripts/projectiles/frag_grenade.gd** (Reference only)
   - No changes needed
   - `effect_radius` constant used for safety calculations

3. **Tests** (New)
   - Add test to verify enemy doesn't throw at unsafe distances
   - Add test for each trigger to verify safety

## Proposed Fix Location

Primary change in `scripts/objects/enemy.gd`, function `try_throw_grenade()` (line 5505):

```gdscript
# BEFORE (line 5513-5517)
var distance := global_position.distance_to(target_position)
if distance < grenade_min_throw_distance:
    _log_grenade("Target too close (%.0f < %.0f) - skipping throw" % [distance, grenade_min_throw_distance])
    return false

# AFTER (proposed)
var distance := global_position.distance_to(target_position)

# Get grenade blast radius (if available)
var blast_radius := 225.0  # FragGrenade default
var safety_margin := 50.0
var min_safe_distance := blast_radius + safety_margin  # 275px

if distance < min_safe_distance:
    _log_grenade("Unsafe throw distance (%.0f < %.0f safe distance) - skipping throw" % [distance, min_safe_distance])
    return false
```

This ensures enemy is at least 275px from target, preventing self-damage from 225px blast radius.
