# Case Study: Issue #1378 - Fix Suppressed Enemy Cover Movement

## Problem Statement

Suppressed enemies need improved cover detection with two key features:
1. Infinite-length rays so cover can be found behind distant obstacles at any range
2. 100-degree sector rays aimed only toward the suppressed enemy, not in all directions

Both features should be configurable via experimental settings toggles.

## Timeline of Events

### Phase 1: Initial Cover Detection (Pre-Issue)

- Cover detection used 16 raycasts from the enemy position in all directions (360 degrees)
- Ray distance limited to 300px (`COVER_CHECK_DISTANCE`)
- This meant enemies could only find cover within 300px radius
- Rays were cast in all directions, wasting computation on irrelevant directions

### Phase 2: PR #1352 Attempt (2026-03-22 to 2026-03-23)

- PR #1352 attempted to implement these features but grew complex (45,994 additions)
- Multiple reverts and rewrites occurred
- The core approach was validated: rays cast FROM the player position toward the suppressed enemy
- Key commit referenced: c740ff7b79f281bf46208c1bbbff54b420785bc2

### Phase 3: Issue #1378 Filed (2026-03-23)

- Owner requested continuation from PR #1352's approach
- Two clear requirements:
  1. Infinite-length rays (10,000px instead of 300px)
  2. 100-degree sector rays toward suppressed enemy
- Both must have experimental toggles

## Root Cause Analysis

### Why 300px rays were insufficient

- Maps can have obstacles much farther than 300px from enemies
- Enemies couldn't find distant cover, leaving them exposed
- The 300px limit was arbitrary and too restrictive for large maps

### Why 360-degree rays were wasteful

- When an enemy is suppressed, only cover BETWEEN the player and the enemy matters
- Rays in the opposite direction (away from the player-enemy axis) find irrelevant cover
- A 100-degree cone from the player toward the enemy focuses on the relevant search area

## Solution Design

### Architecture

The solution modifies `_find_cover_position()` to:

1. **Cast rays FROM the player position** (not from the enemy)
   - This naturally finds obstacles between the player and enemy
   - Cover positions behind these obstacles are hidden from the player

2. **Use infinite ray distance when enabled** (10,000px)
   - Configurable via `cover_infinite_rays_enabled` toggle
   - Falls back to 300px when disabled

3. **Use 100-degree sector when enabled**
   - 120 rays in a 100-degree cone (vs 16 rays in 360 degrees)
   - Provides ~3x better angular resolution in the relevant direction
   - Configurable via `cover_sector_rays_enabled` toggle

4. **Thick obstacle probing** via `intersect_point()`
   - Steps outward from collision point in 30px increments
   - Detects inside-to-outside transition to find far edge
   - Places cover 35px past the far edge

5. **Navigation mesh snapping**
   - Cover positions snapped to nav-mesh via `NavigationServer2D.map_get_closest_point()`
   - Ensures cover is on walkable terrain

### Files Changed

| File | Changes |
|------|---------|
| `scripts/objects/enemy.gd` | Modified `_find_cover_position()` for infinite/sector rays, added `_get_far_side_cover()` helper |
| `scripts/autoload/experimental_settings.gd` | Added `cover_infinite_rays_enabled` and `cover_sector_rays_enabled` toggles with persistence |
| `scripts/ui/experimental_menu.gd` | Added UI wiring for new toggles |
| `scenes/ui/ExperimentalMenu.tscn` | Added UI elements (checkboxes + descriptions) |

### Key Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `COVER_INFINITE_RAY_DISTANCE` | 10,000 px | Extended ray distance |
| `COVER_SECTOR_HALF_ANGLE` | 50 degrees | Half of 100-degree cone |
| `COVER_SECTOR_RAY_COUNT` | 120 | Rays in sector mode |
| `COVER_FAR_SIDE_PROBE_DISTANCE` | 30,000 px | Max probe for thick obstacles |
| `COVER_FAR_SIDE_STEP` | 30 px | Probe step size |

## Compatibility

- Both toggles enabled by default (matching PR #1352 intent)
- When disabled, behavior reverts to original 300px/360-degree logic
- Teleporter skip check (Issue #1355) preserved
- Debug visualization (`get_cover_raycast_data()`) updated to show player-origin rays
- All existing cover finding variants (`_find_distant_cover_position`, `_find_cover_closest_to_player`, `_find_flank_cover_toward_target`) unchanged - they use enemy-origin rays for non-suppression scenarios

## Post-Deploy Bug: Visualization Broken (2026-03-23)

### Report

After deployment of the initial fix (PR #1379), the repository owner reported:
> "сломалось отображение лучей" (ray display broke)

Game log attached: `game_log_20260323_134837.txt` (from build `2026-03-23T13:48:37`, Windows, Godot 4.3-stable).

### Root Cause

The `CoverRaycastMonitor` overlay draws **non-colliding rays** as gray lines all the way to their `target` position. Before this fix, rays had a max length of 300px — small and readable. After enabling infinite rays (10,000px), each non-colliding ray drew a 10,000px gray line from the player position, extending far off-screen. With 120 rays in a 100° sector, the overlay became an unreadable fan of lines covering the entire screen.

Colliding rays (yellow) were unaffected — they only draw from origin to the collision point, not to the full target.

### Fix (2026-03-23)

Added `RAY_DISPLAY_MAX_LENGTH = 800.0` constant to `cover_raycast_monitor.gd`. Non-colliding rays now clip their **displayed** endpoint to 800px from the origin. The actual ray length used for physics/cover detection is unchanged (10,000px when infinite rays are enabled).

Changed file: `scripts/autoload/cover_raycast_monitor.gd`

### Key Insight

The collision detection distance and the visualization display distance are independent concerns. Functional rays need to reach 10,000px to find distant cover. Visual debug lines only need to reach ~800px to be useful on-screen without obscuring the gameplay view.
