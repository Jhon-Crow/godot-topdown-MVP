# Case Study: Issue #739 - Fix Homing Bullets (Curved Smoke Trail)

## Issue Summary

**Issue**: #739 - fix наводящиеся пули
**Description**: The smoke trail from the rifle should curve toward the enemy (currently looks like a straight shot).

Original Russian text:
> дымный след от винтовки должен изгибаться во врага (сейчас выглядит как прямой выстрел)

## Related Issues and PRs

| Issue/PR | Title | Status | Description |
|----------|-------|--------|-------------|
| #677 | Add homing bullets active item | Closed | Original feature request - bullets steer toward nearest enemy (max 110°) |
| #704 | Fix homing bullets active item | Closed | Fix homing bullet implementation |
| #709 | Fix активный предмет - наводящиеся пули | Closed | PR #710 - Fixed sniper rifle curved smoke trail, increased turning speed |
| #710 | PR: Sniper homing and faster bullet turning | Merged | Added `SpawnCurvedSmokyTracer()` for sniper, increased steer speed to 50 rad/s |
| #737 | fix наводящиеся пули | Open | Bullets should turn 170°, add 4px radius rounded turn |
| #739 | fix наводящиеся пули | Open | **This issue** - Smoke trail should curve |

## Timeline of Events

1. **Issue #677**: Homing bullets feature added - bullets can turn up to 110° toward enemies
2. **Issue #704-#709**: Various fixes for homing functionality
3. **PR #710**: Fixed sniper rifle - added Bezier curve smoke trail, but only for sniper (hitscan)
4. **Issue #737/#739**: Remaining issue - assault rifle (AK) bullet trails don't show visible curves

## Technical Analysis

### Current Implementation

#### Sniper Rifle (Fixed in PR #710)
- Uses **hitscan** (instant raycast damage)
- Creates smoke trail after the fact using `SpawnCurvedSmokyTracer()`
- Trail is a **Bezier curve** with 16 segments when homing redirects the shot
- Works correctly - curved trail visible

#### Assault Rifle / Other Bullets
- Uses **projectiles** (actual bullets that fly through air)
- Trail follows bullet using `_position_history` array
- Trail updates each frame: `_position_history.push_front(global_position)`
- Trail limited to 8 points by default (`trail_length = 8`)

### Root Cause Analysis

The bullet trail for projectile-based weapons (assault rifle) stores the bullet's actual positions in `_position_history`. This should create a curved trail when the bullet turns. However:

1. **Trail is too short**: At 2500 px/s bullet speed and 60 FPS, each frame = ~42 pixels. 8 points × 42 px = only ~336 pixels of trail visible.

2. **Curve may not be visible**: With fast bullet speed and short trail, the curvature isn't obvious even when it exists.

3. **Trail clears on ricochet**: When bullet ricochets, `_position_history.clear()` is called, which loses the curved path.

### Solution Approach

For projectile-based bullets with homing, the trail needs to be longer and/or rendered with more points to show the curve clearly.

**Option A**: Increase `trail_length` when homing is enabled
- Pros: Simple change
- Cons: May affect performance, doesn't improve smoothness

**Option B**: Use interpolated points for smoother curve rendering
- Record key turning points, interpolate between them with bezier curves
- Pros: Smooth curves like sniper rifle
- Cons: More complex implementation

**Option C**: Keep more history when homing is active
- Increase `trail_length` dynamically when `homing_enabled = true`
- Add more intermediate trail points for smoother curve
- Pros: Targeted fix, good balance

## Proposed Solution

Implement **Option C** with these changes:

1. When homing is enabled on a bullet, increase `trail_length` from 8 to 24+ points
2. Keep position history longer to show the full curve
3. Optionally add sub-frame interpolation for smoother curves

## Files to Modify

| File | Changes |
|------|---------|
| `scripts/projectiles/bullet.gd` | Increase trail_length when homing, keep more history |
| `Scripts/Projectiles/Bullet.cs` | Same changes for C# version |

## Test Plan

1. Activate homing bullets (spacebar)
2. Fire assault rifle at enemy at 90° angle
3. Verify smoke trail curves visibly toward enemy
4. Verify no performance impact with longer trails
