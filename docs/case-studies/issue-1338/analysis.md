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

## Follow-up Report (game_log_20260322_182023.txt)

After the initial fix, the repo owner reported that enemies still sometimes run toward the player or stay in place instead of seeking cover when bullets hit their threat zone. Analysis of the second log revealed two additional root causes:

### Root Cause 2: Delayed threat reaction allows exposed transitions

The `_update_suppression()` function has a `threat_reaction_delay` (0.2s) before setting `_under_fire = true`. During this delay window:
- COMBAT enemies see "can't see player + not under fire" → transition to PURSUING
- PURSUING enemies see "can see player + can hit" → transition to COMBAT
- Both transitions happen while bullets are actively flying past

Log evidence:
```
[18:20:36] Enemy3 [#1311] Player bullet entered threat sphere — suppression triggered
[18:20:36] Enemy3 State: COMBAT -> PURSUING   ← should have retreated!
[18:20:36] Enemy1 State: COMBAT -> PURSUING   ← no bullets in THEIR zone, but nearby fire
```

### Root Cause 3: Hit handler pulls enemies out of cover-seeking

Issue #910 added logic: "when hit in RETREATING/SEEKING_COVER → transition to COMBAT". This directly conflicts with suppression:
```
[18:20:34] Enemy2 [#910] Hit triggered COMBAT from SEEKING_COVER  ← was trying to take cover!
```

## Solution

### Fix 1: Post-suppression cover timer (initial fix)

Added `POST_SUPPRESSION_COVER_DURATION = 3.0 seconds` timer that keeps the enemy in cover after suppression ends.

### Fix 2: Immediate retreat on bullet threat (follow-up)

Modified `_on_threat_area_entered()` to immediately:
1. Set `_under_fire = true` (bypassing `threat_reaction_delay`)
2. Set `_threat_reaction_delay_elapsed = true`
3. Transition COMBAT/PURSUING enemies to RETREATING

This ensures enemies react to bullets in the same frame they enter the threat zone.

### Fix 3: Protect cover-seeking from hit handler (follow-up)

Modified the Issue #910 hit handler to NOT transition from RETREATING/SEEKING_COVER to COMBAT when:
- `_under_fire` is true, OR
- Bullets are present in the threat sphere

This preserves the original #910 behavior (hit from IDLE/SEARCHING → COMBAT) while protecting enemies that are actively seeking cover under fire.

### Fixed State Flow

```
Player bullet enters threat zone
    |  [_on_threat_area_entered: immediate _under_fire + retreat]
    v
RETREATING (seeking cover, protected from #910 hit handler)
    |  [reaches cover]
    v
IN_COVER → SUPPRESSED (if still under fire)
    |  [fire stops]
    v
IN_COVER (post-suppression period: 3.0s)
    |  [after 3.0s, timer expires]
    v
PURSUING (delayed pursuit, realistic behavior)
```

## Follow-up Report 2 (PR comment feedback)

The repo owner reported two additional issues:

### Root Cause 4: Cover selection not choosing nearest cover

The `_find_cover_position()` scoring weighted the "blocking" score (dot product with player direction) at 0.7 and the distance-from-enemy score at only 0.3. This meant enemies sometimes chose farther cover that happened to score better on the blocking metric, even when nearer valid cover existed.

**Original scoring** (among hidden covers):
```
total_score = hidden_score(10.0) + distance_score * 0.3 + blocking_score * 0.7
```

The user's expectation: nearest cover to the enemy that blocks raycasts from the player. The `is_hidden` check already validates raycast blocking. Among hidden covers, distance should dominate.

### Root Cause 5: Enemies stop shooting after initial burst during retreat

In ONE_HIT and MULTIPLE_HITS retreat modes, after the initial burst of 2-4 shots, the enemy runs to cover silently (`_move_to_target_nav` only). The FULL_HP mode already shoots while retreating, but the other modes did not continue firing after their burst phase.

## Solution (continued)

### Fix 4: Prioritize nearest hidden cover

Changed cover scoring weights in `_find_cover_position()`:
```
# Before: distance * 0.3 + blocking * 0.7
# After:  distance * 0.8 + blocking * 0.2
```

This ensures that among covers that are hidden from the player (verified via raycast), the nearest one to the enemy is selected.

### Fix 5: Shoot while retreating in all modes

After the burst phase completes in ONE_HIT/MULTIPLE_HITS modes, the enemy now continues shooting with reduced accuracy while running to cover (same as FULL_HP mode). This makes retreat behavior consistent: enemies always shoot while falling back.

## Files Changed

- `scripts/objects/enemy.gd` - Post-suppression timer, immediate threat reaction, hit handler protection, cover distance priority, retreat shooting
- `tests/unit/test_post_suppression_cover_1338.gd` - Regression tests

## Test Coverage

19 test cases covering:
- Timer set correctly on suppression end
- Enemy stays in cover during post-suppression period
- Enemy pursues after timer expires
- Player visibility during post-suppression
- Timer resets on new suppression
- Timer doesn't go negative
- No timer without prior suppression (normal IN_COVER behavior preserved)
- Under-fire still prevents pursuing (existing behavior preserved)
- COMBAT enemy immediately retreats on bullet threat
- PURSUING enemy immediately retreats on bullet threat
- IDLE enemy does not retreat on bullet threat (different handling)
- Force field blocks immediate retreat
- Cover disabled does not trigger retreat
- Hit does not pull RETREATING enemy to COMBAT when under fire
- Hit does not pull SEEKING_COVER enemy to COMBAT when under fire
- Hit does not pull RETREATING enemy with bullets in threat sphere
- Hit still triggers COMBAT from IDLE (Issue #910 preserved)
- Hit triggers COMBAT from RETREATING when not under fire (Issue #910 preserved)
