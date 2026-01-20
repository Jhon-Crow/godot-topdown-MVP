# Case Study: Enemy Threat Sphere Reaction Bug (Issue #78)

## Summary
PR #75 introduced a reaction delay for enemies responding to bullets in their threat sphere. However, this broke the enemy cover-seeking behavior because bullets pass through the threat sphere faster than the reaction delay can complete.

## Background

### Original Behavior (Before PR #75)
When a bullet entered an enemy's threat sphere:
1. `_on_threat_area_entered()` immediately set `_under_fire = true`
2. Enemy would immediately seek cover

### Changed Behavior (PR #75)
PR #75 added a `threat_reaction_delay` (600ms, later reduced to 200ms in PR #77):
1. `_on_threat_area_entered()` no longer sets `_under_fire = true` immediately
2. `_update_suppression()` checks if bullets are in the sphere
3. A timer (`_threat_reaction_timer`) increments while bullets are present
4. Only after the delay elapses does `_under_fire` become true
5. When all bullets leave the sphere, the timer resets to 0

### The Problem
**Bullets travel too fast for the reaction delay to complete:**

- Bullet speed: 2500 pixels/second
- Threat sphere radius: 100 pixels (diameter: 200 pixels)
- Time to cross threat sphere: 200 / 2500 = **0.08 seconds (80ms)**
- Reaction delay: **200ms** (or 600ms originally)

Since bullets exit the sphere in ~80ms but the reaction delay requires 200ms, the timer always resets before `_under_fire` can become true. This completely broke the cover-seeking behavior.

## Technical Analysis

### Code Flow (Before Fix)
```
1. Bullet enters threat sphere
2. _on_threat_area_entered() adds bullet to _bullets_in_threat_sphere
3. _update_suppression() starts incrementing _threat_reaction_timer
4. ~80ms later: bullet exits threat sphere
5. _on_threat_area_exited() removes bullet from array
6. _update_suppression() sees empty array, resets timer to 0
7. _under_fire never becomes true
8. Enemy never seeks cover
```

### Root Cause
The reaction timer was tied directly to the presence of bullets in the sphere. Fast-moving bullets would always exit before the timer could complete.

## Solution

### Approach: Threat Memory
Add a "threat memory" mechanism that persists after bullets exit:

1. When a bullet enters the threat sphere, set `_threat_memory_timer = 0.5 seconds`
2. The memory timer counts down independently
3. `has_active_threat` is true if either:
   - Bullets are currently in the sphere, OR
   - Threat memory timer is still positive
4. Reaction timer only resets when there's NO active threat

### Implementation
```gdscript
# New variables
var _threat_memory_timer: float = 0.0
const THREAT_MEMORY_DURATION: float = 0.5

# In _on_threat_area_entered():
_threat_memory_timer = THREAT_MEMORY_DURATION

# In _update_suppression():
var has_active_threat := not _bullets_in_threat_sphere.is_empty() or _threat_memory_timer > 0.0
```

### Code Flow (After Fix)
```
1. Bullet enters threat sphere
2. _on_threat_area_entered() adds bullet AND sets _threat_memory_timer = 0.5s
3. _update_suppression() starts incrementing _threat_reaction_timer
4. ~80ms later: bullet exits threat sphere
5. _on_threat_area_exited() removes bullet from array
6. has_active_threat is still true (memory timer > 0)
7. _update_suppression() continues incrementing reaction timer
8. After 200ms total: _threat_reaction_delay_elapsed = true
9. _under_fire = true
10. Enemy seeks cover!
```

## Timeline Values

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `threat_reaction_delay` | 200ms | Delay before enemy reacts (gives player time) |
| `THREAT_MEMORY_DURATION` | 500ms | How long to "remember" a bullet passed by |
| `suppression_cooldown` | 2000ms | How long to stay suppressed after bullets stop |
| Bullet transit time | ~80ms | Time for bullet to cross threat sphere |

The memory duration (500ms) is deliberately longer than the reaction delay (200ms) to ensure the reaction can complete even for the fastest bullets.

## Files Changed
- `scripts/objects/enemy.gd`: Added threat memory mechanism

## Related PRs
- PR #75: Added reaction delay (introduced the bug)
- PR #77: Reduced delay from 600ms to 200ms (did not fix the fundamental issue)

## Lessons Learned
1. When adding delays to reactive systems, consider if the triggering event persists long enough for the delay to complete
2. Fast-moving objects (bullets) may not stay in detection areas long enough for delayed reactions
3. "Memory" mechanisms can bridge the gap between fast events and delayed reactions
