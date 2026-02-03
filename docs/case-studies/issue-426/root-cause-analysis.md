# Root Cause Analysis - Issue #426

## Issue Summary

**Title:** fix враги не должны разбегаться от гранаты игрока, пока не знают о ней
(fix: enemies should not flee from player's grenade until they know about it)

## Expected Behavior

Enemies should only flee from grenades when they:
1. **SEE** the grenade being thrown or in flight, OR
2. **HEAR** the grenade land nearby, OR
3. Have **direct line-of-sight** to the grenade

Enemies should **NOT** react to grenades:
- When the player is holding the grenade (pin pulled but not thrown)
- When the grenade is behind a wall (no line-of-sight)

## Bug Evolution

### Phase 1: Held Grenade Detection (Fixed in first commit)

**Problem:** Enemies fled when the player pulled the pin, before throwing.

**Root Cause:** `GrenadeAvoidanceComponent` used `is_timer_active()` to check if grenade was a threat, but the timer activates when the pin is pulled, not when thrown.

**Solution:** Added `is_thrown()` method to `GrenadeBase` that returns `true` only when `freeze == false` (grenade physically moving/resting).

### Phase 2: Wall Penetration Detection (Fixed in second commit)

**Problem:** Enemies still fled from grenades behind walls.

**Timeline from game_log_20260203_164039.txt (user-provided log):**
| Time | Event | Enemy Positions | Issue |
|------|-------|-----------------|-------|
| 16:40:46 | Grenade thrown at player position (334, 759) | Enemy1 at ~(274, 247), Enemy2 at ~(396, 231) | - |
| 16:40:46 | Enemy1, Enemy2, Enemy3, Enemy4 enter EVADING_GRENADE | All enemies in separate rooms/areas | **BUG** |

**Key evidence from log:**
```
[16:40:46] [ENEMY] [Enemy1] GRENADE DANGER: Entering EVADING_GRENADE state from IDLE
[16:40:46] [ENEMY] [Enemy1] EVADING_GRENADE started: escaping to (274.0811, 247.0762)
[16:40:46] [ENEMY] [Enemy2] GRENADE DANGER: Entering EVADING_GRENADE state from IDLE
```

Enemies at positions like (274, 247) are clearly in different rooms from the player at (334, 759) based on escape directions and map layout.

**Root Cause:** The `update()` function in `GrenadeAvoidanceComponent` only checked **distance** to determine if enemy was in danger:

```gdscript
# Calculate distance to grenade
var distance := _enemy.global_position.distance_to(grenade.global_position)

# Check if we're in danger zone
if distance < danger_radius:
    _grenades_in_range.append(grenade)  # ← No visibility check!
```

This caused enemies to react to grenades they couldn't possibly know about (no "sixth sense" through walls).

**Solution:** Added line-of-sight (LOS) check using raycast before considering a grenade as a threat:

```gdscript
if distance < danger_radius:
    # Issue #426: Check line-of-sight - enemies should only react to grenades
    # they can actually see or hear. A grenade behind a wall is not a threat
    # they would know about (no "sixth sense" through walls).
    if not _can_see_position(grenade.global_position):
        continue  # Skip grenades blocked by walls
```

## Solution Architecture

### Changes to `grenade_avoidance_component.gd`

1. **Added `_raycast` property** - Reference to RayCast2D for visibility checks
2. **Added `set_raycast()` method** - To configure the raycast reference
3. **Added `_can_see_position()` method** - Line-of-sight check implementation
4. **Modified `update()` function** - Added LOS check before considering grenade as threat

### Changes to `enemy.gd`

1. **Updated `_setup_grenade_avoidance()`** - Pass raycast reference to component

### Changes to `grenade_base.gd` (from Phase 1)

1. **Added `is_thrown()` method** - Returns `true` when grenade is unfrozen

## Test Coverage

Unit tests added in `tests/unit/test_grenade_avoidance_component.gd`:
- Line-of-sight visibility checks
- Danger zone detection with/without wall blocking
- Thrown state detection
- Exploded grenade handling
- Cooldown behavior
- Multiple grenade scenarios

### Phase 3: Field of View Detection (Fixed in third commit)

**Problem:** Enemies still fled from grenades behind them (outside their field of view).

**Timeline from game_log_20260203_165243.txt (user-provided log):**
| Time | Event | Details | Issue |
|------|-------|---------|-------|
| 16:52:55 | Grenade thrown by player | Position near (325, 949) | - |
| 16:52:55 | Enemy3 enters EVADING_GRENADE | Current rotation: -85.9° to -40.9°, indicating facing away | **BUG** |
| 16:52:55 | Enemy1 enters EVADING_GRENADE | Rotation: 147.4° (facing opposite direction) | **BUG** |
| 16:52:55 | Enemy2 enters EVADING_GRENADE | Rotation: -84.8° | **BUG** |

**Key evidence from log:**
```
[16:52:55] [ENEMY] [Enemy3] ROT_CHANGE: P5:idle_scan -> P4:velocity, state=EVADING_GRENADE, target=-42.8°, current=-85.9°
[16:52:55] [ENEMY] [Enemy1] ROT_CHANGE: P5:idle_scan -> P4:velocity, state=EVADING_GRENADE, target=-128.1°, current=147.4°
```

The rotation logs show enemies were facing in different directions when they detected the grenade. An enemy facing 147.4° cannot see a grenade at -128.1° (nearly 180° behind them).

**User feedback (translated from Russian):**
> "враги не должны убегать от гранаты вне своего поля зрения (то есть не должны видеть летящую гранату спиной)"
> Translation: "enemies should not flee from a grenade outside their field of view (i.e., they should not see a flying grenade with their back)"

**Root Cause:** The Phase 2 fix added line-of-sight (raycast) checks but not field-of-view (FOV cone) checks. Enemies have a 100° FOV defined in their configuration (`fov_angle: float = 100.0`), but `GrenadeAvoidanceComponent` was not checking if the grenade was within this FOV cone.

**Solution:** Added FOV check to `GrenadeAvoidanceComponent`:

1. Added `_enemy_model`, `_fov_angle`, and `_fov_enabled` properties
2. Added `set_fov_parameters()` method to configure FOV settings
3. Added `_is_position_in_fov()` method to check if position is within vision cone
4. Modified `update()` to check FOV in addition to LOS

```gdscript
# Issue #426: Check field of view - enemies should only react to grenades
# within their vision cone. They can't see grenades behind them.
if not _is_position_in_fov(grenade.global_position):
    continue  # Skip grenades outside field of view
```

The FOV check uses the same logic as the enemy's `_is_position_in_fov()` function:
- Gets enemy's facing direction from `_enemy_model.global_rotation`
- Calculates angle to grenade position using dot product
- Compares against half of `fov_angle` (cone is symmetric)

## Impact

- **Realistic behavior:** Enemies only react to grenades they can actually perceive
- **Tactical gameplay:** Players can use walls for cover when throwing grenades
- **No "sixth sense":** Enemies behave consistently with what they can see/hear
- **FOV-aware:** Enemies cannot see grenades behind them (respects FOV settings)
- **Backward compatible:** Fallback behavior when no raycast or FOV settings available

## Files Modified

1. `scripts/components/grenade_avoidance_component.gd` - Added LOS and FOV checks
2. `scripts/objects/enemy.gd` - Pass raycast and FOV parameters to component
3. `scripts/projectiles/grenade_base.gd` - Added `is_thrown()` method (Phase 1)
4. `tests/unit/test_grenade_avoidance_component.gd` - Unit tests for LOS and FOV
5. `tests/unit/test_grenade_base.gd` - Added `is_thrown()` tests (Phase 1)
