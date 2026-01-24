# Case Study: Issue #228 - Fix Enemy Weapon Fire Rate

## Issue Summary
**Title**: fix скорострельность оружия врагов (fix enemy weapon fire rate)
**Description**: Enemies should not shoot faster than their weapon allows (they have the same M16 as the player).

## Timeline/Sequence of Events
1. Issue reported: Enemies can shoot faster than their weapon's fire rate permits
2. Investigation began by analyzing `scripts/objects/enemy.gd`
3. Root cause identified in priority attack handlers

## Root Cause Analysis

### Expected Behavior
Both the player and enemies use the M16 assault rifle, which has a fire rate of 10 shots per second (0.1 second cooldown between shots).

- **Player**: `fire_rate: float = 10.0` (player.gd:62)
- **Enemy**: `shoot_cooldown: float = 0.1` (enemy.gd:60)

### Actual Behavior
Enemies in certain conditions can shoot every physics frame (60+ shots per second) instead of respecting the 0.1 second cooldown.

### Root Cause
In `scripts/objects/enemy.gd`, there are two "priority attack" code paths that bypass the `shoot_cooldown` timer check:

1. **Distraction Attack** (lines 1115-1125):
   - Triggered when player's aim is more than 23 degrees away from the enemy
   - Only checks `_can_shoot()` which verifies ammo and reload status
   - Does NOT check `_shoot_timer >= shoot_cooldown`
   - Can fire every frame while the distraction condition persists

2. **Vulnerability Attack** (lines 1171-1181):
   - Triggered when player is reloading or has empty weapon AND enemy is close
   - Same issue: only checks `_can_shoot()` without cooldown verification
   - Can fire every frame while the vulnerability condition persists

### Code Evidence

```gdscript
# Line 1115 - Distraction attack condition (missing cooldown check):
if has_clear_shot and _can_shoot():
    _shoot()
    _shoot_timer = 0.0  # Reset AFTER shooting, not checked BEFORE

# Line 1171 - Vulnerability attack condition (missing cooldown check):
if has_clear_shot and _can_shoot():
    _shoot()
    _shoot_timer = 0.0  # Reset AFTER shooting, not checked BEFORE
```

Compare with regular combat shooting at line 1348 which properly checks the cooldown:
```gdscript
if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
    _shoot()
    _shoot_timer = 0.0
```

## Solution
Add `_shoot_timer >= shoot_cooldown` to the priority attack conditions to enforce the fire rate limit:

```gdscript
# Fixed distraction attack:
if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
    _shoot()
    _shoot_timer = 0.0

# Fixed vulnerability attack:
if has_clear_shot and _can_shoot() and _shoot_timer >= shoot_cooldown:
    _shoot()
    _shoot_timer = 0.0
```

## Files Changed
- `scripts/objects/enemy.gd`: Added cooldown checks to priority attack handlers

## Testing
The fix ensures:
1. Distraction attacks respect the 0.1 second cooldown
2. Vulnerability attacks respect the 0.1 second cooldown
3. All other shooting behavior remains unchanged
