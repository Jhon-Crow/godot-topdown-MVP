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

## Impact

- **Realistic behavior:** Enemies only react to grenades they can actually perceive
- **Tactical gameplay:** Players can use walls for cover when throwing grenades
- **No "sixth sense":** Enemies behave consistently with what they can see/hear
- **Backward compatible:** Fallback behavior when no raycast available

## Files Modified

1. `scripts/components/grenade_avoidance_component.gd` - Added LOS checks
2. `scripts/objects/enemy.gd` - Pass raycast reference to component
3. `scripts/projectiles/grenade_base.gd` - Added `is_thrown()` method (Phase 1)
4. `tests/unit/test_grenade_avoidance_component.gd` - New test file
5. `tests/unit/test_grenade_base.gd` - Added `is_thrown()` tests (Phase 1)
