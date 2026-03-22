# Issue #1338 — Round 5 Analysis: FPS Regression & Cover Detection

## Timeline

| Time | Event |
|------|-------|
| 2026-03-22 17:17 | Initial issue report (game_log_20260322_171711.txt) — suppressed enemies don't seek cover |
| 2026-03-22 18:20 | Feedback round 2 (game_log_20260322_182023.txt) |
| 2026-03-22 19:13 | Feedback round 3 (game_log_20260322_191313.txt, game_log_20260322_191734.txt) |
| 2026-03-22 19:41 | Feedback round 4 (game_log_20260322_194129.txt) |
| 2026-03-22 20:17 | Feedback round 4 continued (game_log_20260322_201726.txt) — FPS drops 13-29 fps |
| 2026-03-22 20:56 | **Round 5** (game_log_20260322_205657.txt) — FPS drops 3-10 fps, cover still wrong |

## Root Cause Analysis

### Problem 1: FPS Regression (3-10 fps vs 13-29 fps baseline)

**Root cause**: `_is_visible_from_player()` runs 5 physics raycasts (center + 4 corners) and was called **every physics frame** for each enemy in RETREATING or SEEKING_COVER states.

Before our changes (commit 980ad694), enemies exited RETREATING as soon as `_is_visible_from_player()` returned false. This meant:
- Enemy enters RETREATING
- Immediately becomes hidden (behind any obstacle)
- Exits RETREATING after just a few frames
- Total `_is_visible_from_player()` calls: ~5-10 per retreat episode

After our retreat persistence fix:
- Enemy enters RETREATING
- Must reach cover position AND be hidden to exit
- Stays in RETREATING for 1-5 seconds (or until 5s timeout)
- At 60fps: 60-300 frames × 5 raycasts = 300-1500 raycasts per enemy per retreat
- With 10 enemies: up to 15,000 raycasts per retreat episode

**Fix**: Throttle `_is_visible_from_player()` using the existing `VISION_CHECK_INTERVAL` (6 frames) and `_vision_frame_offset` (staggered per enemy). Cache result per frame to avoid redundant calls within the same frame. This reduces raycast load by ~6x.

### Problem 2: Cover detection still incorrect

**User expectation**: "nearest obstacle to the enemy, behind which rays from the player won't reach it"

**Analysis**: The cover detection algorithm already works as described:
1. Cast 16 rays from enemy to find nearby obstacles
2. Position cover behind the obstacle (collision_normal * 35px)
3. Verify position is hidden from player via `_is_position_visible_from_origin()`
4. Score by hidden_score(10.0) + distance_score(0.7) + blocking_score(0.3)

The algorithm was correct, but a secondary issue existed: SEEKING_COVER was still in the #910 hit handler, causing enemies to cycle back to COMBAT when hit while seeking cover, then immediately re-enter RETREATING and repeat — giving the appearance of not properly finding cover.

**Fix**: Remove SEEKING_COVER from #910 hit handler (same treatment as RETREATING).

## FPS Drop Distribution Comparison

### Baseline (game_log_20260322_171711.txt, 10 enemies)
```
 9x 29fps  5x 22fps  3x 23fps  3x 13fps  2x 27fps  2x 24fps  2x 15fps
```
Most drops: 20-29 fps range

### After fix (game_log_20260322_205657.txt, 10 enemies)
```
11x 4fps   6x 6fps   5x 7fps   4x 9fps   4x 5fps   1x 3fps
```
Most drops: 3-10 fps range — **severe regression**

## State Cycling Evidence

Enemy4 showed rapid COMBAT -> RETREATING cycling (5 transitions in 3 seconds at 20:57:59-20:58:02), caused by hits during SEEKING_COVER triggering COMBAT via #910 handler.

## Fixes Applied

1. **`_is_visible_from_player()` throttling**: Uses `VISION_CHECK_INTERVAL` (6 frames) staggered by `_vision_frame_offset` per enemy. Caches result for same-frame lookups. Reduces raycast load ~6x.

2. **SEEKING_COVER removed from #910 hit handler**: Enemy continues seeking cover when hit instead of cycling through COMBAT -> RETREATING.
