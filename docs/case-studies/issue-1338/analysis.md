# Issue #1338: Suppressed enemies should immediately go to cover

## Problem Statement

Suppressed enemies should go to cover and stay there when the player disappears from sight. Instead, when the player hides, suppressed enemies immediately transition to PURSUING state and chase the player.

Original description (Russian): "подавленные враги должны сразу идти в укрытие (сейчас если игрок скрылся из виду враг перестаёт быть подавленным)"

Translation: "Suppressed enemies should immediately go to cover (currently if the player goes out of sight, the enemy stops being suppressed)"

## Timeline of Events (from game_log_20260322_171711.txt)

The log reveals the pattern clearly:

1. **17:17:18** - Player bullets enter threat sphere, suppression triggered for Enemy2 and Enemy3
2. **17:17:18-19** - Enemies retreat and reach cover: `RETREATING -> IN_COVER`
3. **17:17:22** - Enemy2 enters suppressed state: `IN_COVER -> SUPPRESSED`
4. **17:17:23** - Suppression ends, enemy seeks new cover: `SUPPRESSED -> SEEKING_COVER`
5. Later sequences show the critical bug pattern:
   - **17:18:02** - `IN_COVER -> SUPPRESSED` (under fire)
   - **17:18:03** - `SUPPRESSED -> IN_COVER` (fire stops)
   - **17:18:03** - `IN_COVER -> PURSUING` (immediate pursuit!)

The `SUPPRESSED -> IN_COVER -> PURSUING` chain happens within the same second, showing the enemy instantly chases the player after suppression ends.

## Root Cause Analysis

### State Machine Flow

The enemy AI has 12 states. The relevant transition chain:

```
SUPPRESSED (under fire in cover)
    |  [_under_fire becomes false after suppression_cooldown (2s)]
    v
IN_COVER (not under fire)
    |  [can't see player + not under fire => pursue]
    v
PURSUING (chase player)
```

### Code Analysis

**File**: `scripts/objects/enemy.gd`

**Step 1 - Suppression timer expires** (line ~1070):
```gdscript
# _update_suppression(): after bullets leave threat sphere
if _suppression_timer >= suppression_cooldown:  # 2.0 seconds
    _under_fire = false
```

**Step 2 - SUPPRESSED -> IN_COVER** (line ~1853):
```gdscript
# _process_suppressed_state(): when no longer under fire
if not _under_fire:
    if time_in_state >= SUPPRESSED_MIN_DURATION:
        _transition_to_in_cover()  # <-- no memory of being suppressed
```

**Step 3 - IN_COVER -> PURSUING** (line ~1738):
```gdscript
# _process_in_cover_state(): player out of sight + not under fire
if not (_can_see_player or _can_see_companion) and not _under_fire:
    _transition_to_pursuing()  # <-- immediate! No post-suppression delay
```

The root cause is that there was **no memory of recent suppression** when transitioning from SUPPRESSED to IN_COVER. The IN_COVER state treated a just-suppressed enemy identically to one that calmly walked to cover.

## Solution

Added a **post-suppression cover timer** (`POST_SUPPRESSION_COVER_DURATION = 3.0 seconds`) that keeps the enemy in cover after suppression ends:

1. **New variable**: `_post_suppression_timer` - counts down while in IN_COVER state
2. **Set on suppression end**: When transitioning SUPPRESSED -> IN_COVER, set timer to 3.0s
3. **Block pursuit**: IN_COVER state checks this timer before transitioning to PURSUING
4. **Natural decay**: Timer counts down each frame; once expired, normal behavior resumes

### Fixed State Flow

```
SUPPRESSED (under fire in cover)
    |  [_under_fire becomes false]
    v
IN_COVER (post-suppression period: 3.0s)
    |  [timer counting down, enemy stays put]
    |  [after 3.0s, timer expires]
    v
IN_COVER (normal behavior)
    |  [can't see player => pursue]
    v
PURSUING (delayed pursuit, realistic behavior)
```

## Files Changed

- `scripts/objects/enemy.gd` - Added post-suppression timer logic
- `tests/unit/test_post_suppression_cover_1338.gd` - Regression tests

## Test Coverage

8 test cases covering:
- Timer set correctly on suppression end
- Enemy stays in cover during post-suppression period
- Enemy pursues after timer expires
- Player visibility during post-suppression
- Timer resets on new suppression
- Timer doesn't go negative
- No timer without prior suppression (normal IN_COVER behavior preserved)
- Under-fire still prevents pursuing (existing behavior preserved)
