# Case Study: Issue #129 - Enemies Not Reacting to Reload/Empty Click Sounds Through Walls

## Summary

**Issue**: Enemies were supposed to hear player reload and empty click sounds through walls and pursue the player, but in practice they were not attacking even when very close (65 pixels) to the player.

**Root Cause**: The attack logic required `_can_see_player` to be true, which negated the entire purpose of sound propagation through walls.

**Status**: Fixed by adding a new "heard vulnerability sound" state that allows enemies to attack without requiring line-of-sight.

## Timeline of Events

### Initial Implementation (PR #128)
- Added vulnerability signals (`player_reloading`, `player_ammo_empty`) to enemy state
- Modified `on_sound_heard_with_intensity()` to transition enemies to PURSUING state when hearing reload/empty click sounds
- Sound propagation ranges were set: RELOAD = 900px, EMPTY_CLICK = 600px

### User Report (Issue #129)
- User: "я проверяю exe, нужное поведение не работает (проверил на подавленных врагах практически в упор)"
- Translation: "I'm testing the exe, the required behavior doesn't work (tested with suppressed enemies almost point-blank)"
- Attached game log: `game_log_20260120_034822.txt`

### Log Analysis

Key log entries showing the problem:

```
[03:48:40] [ENEMY] [Enemy10] Heard player RELOAD at (713.9331, 983.9337), intensity=0.58, distance=66
[03:48:40] [ENEMY] [Enemy10] Player vulnerable (reloading) but cannot attack: close=true (dist=66), can_see=false
```

**Observation**: Enemy DID hear the reload sound at 66 pixels (very close), but logged "cannot attack" because `can_see=false`.

The log shows multiple instances of this pattern:
- Enemy1 at 295px, Enemy2 at 191px, Enemy3 at 168px, Enemy4 at 251px all heard EMPTY_CLICK sounds
- All logged "cannot attack" with `can_see=false`

## Root Cause Analysis

### Code Flow

1. **Sound Propagation** (working correctly):
   - `SoundPropagation` emits RELOAD/EMPTY_CLICK sounds
   - `enemy.gd:on_sound_heard_with_intensity()` receives the sound
   - Sets `_goap_world_state["player_reloading"] = true` or `player_ammo_empty = true`
   - Transitions to PURSUING state if in cover/suppressed

2. **Attack Logic** (the bug):
   - In `_physics_process()`, line 1058:
   ```gdscript
   if player_is_vulnerable and _can_see_player and _player and player_close:
   ```
   - Requires `_can_see_player` to be true
   - But the whole point of sound propagation is to work **through walls**
   - If enemy can't see player, they never attack even when close

3. **Pursuit Logic** (also affected):
   - Line 1088:
   ```gdscript
   if player_is_vulnerable and _can_see_player and _player and not player_close:
   ```
   - Also requires `_can_see_player`, preventing pursuit through walls

### Why This Happened

The original implementation logic was:
1. Enemy hears sound through wall
2. Enemy transitions to PURSUING state
3. Enemy pursues using navigation
4. When close enough and can see player, attack

The flaw: The PURSUING state handler also checks `_can_see_player` before attacking:
```gdscript
# Line 1818-1826 in _process_pursuing_state()
if _can_see_player and _player:
    var can_hit := _can_hit_player_from_current_position()
    if can_hit:
        _transition_to_combat()
```

This creates a deadlock:
- Enemy can't attack because they can't see player
- Enemy can't transition to combat because they can't see player
- Enemy just keeps pursuing forever without attacking

## Solution

The fix involves:

1. **Track "heard vulnerability sound"** - Add a new state variable `_pursuing_vulnerability_sound` that is set when enemy hears reload/empty click
2. **Sound handler changes** - When hearing RELOAD or EMPTY_CLICK sounds, set the flag and always transition to PURSUING (not COMBAT which requires vision)
3. **PURSUING state changes** - Add special handling when `_pursuing_vulnerability_sound` is true:
   - Move directly toward `_last_known_player_position` (the sound position) using navigation
   - Navigation will automatically route around walls
   - When close to sound position, check if player is visible
   - If visible, transition to COMBAT; if not, continue normal pursuit

### Code Changes in `enemy.gd`

```gdscript
# New variable (line 533)
var _pursuing_vulnerability_sound: bool = false

# Sound handler changes (lines 700-711, 724-736)
# When hearing RELOAD or EMPTY_CLICK:
_pursuing_vulnerability_sound = true
if _current_state == AIState.IDLE:
    _transition_to_pursuing()  # Changed from _transition_to_combat()

# PURSUING state changes (lines 1840-1870)
# New vulnerability sound pursuit handling:
if _pursuing_vulnerability_sound and _last_known_player_position != Vector2.ZERO:
    var distance_to_sound := global_position.distance_to(_last_known_player_position)
    if distance_to_sound < 50.0:
        # Reached sound position - check if can see player
        if _can_see_player and _player:
            _transition_to_combat()
            return
        # Otherwise continue with normal pursuit
        _pursuing_vulnerability_sound = false
    else:
        # Keep moving toward sound position via navigation
        _move_to_target_nav(_last_known_player_position, combat_move_speed)
        return
```

The key insight: Navigation-based pathfinding (`_move_to_target_nav`) will automatically route the enemy around walls. Once they have line-of-sight to the player, the existing check at the start of `_process_pursuing_state` will transition them to COMBAT.

## Files Changed

- `scripts/objects/enemy.gd`:
  - Added `_pursuing_vulnerability_sound` flag
  - Modified sound handler to set flag and transition to PURSUING
  - Added vulnerability sound pursuit handling in `_process_pursuing_state`
  - Clear flag in state transitions and respawn

## Testing

- [x] Unit tests verify sound propagation ranges
- [ ] Manual testing: reload near suppressed enemy behind cover - should pursue and attack when line of sight established
- [ ] Manual testing: empty click near enemy behind cover - should pursue and attack

## Lessons Learned

1. **Integration testing is critical**: The sound propagation and attack systems worked individually but failed when combined
2. **State transitions need clear ownership**: The attack logic and state machine had conflicting requirements
3. **Edge cases matter**: The "behind wall" scenario is exactly why this feature was requested

---

## Second Bug Report (2026-01-20): State Thrashing

### User Report

After the initial fix was deployed, user reported:
> "подавленные противники не выходят из подавленного состояния"
> (Translation: "suppressed enemies do not exit from suppressed state")

Attached logs: `game_log_20260120_040247.txt`, `game_log_20260120_040520.txt`

### Log Analysis

Analysis of the logs revealed a severe **state thrashing bug** where Enemy7 was rapidly switching between COMBAT and PURSUING states:

```
[04:04:01] [ENEMY] [Enemy7] State: PURSUING -> COMBAT
[04:04:01] [ENEMY] [Enemy7] State: COMBAT -> PURSUING
[04:04:01] [ENEMY] [Enemy7] State: PURSUING -> COMBAT
[04:04:01] [ENEMY] [Enemy7] State: COMBAT -> PURSUING
... (543 PURSUING->COMBAT and 555 COMBAT->PURSUING transitions in one session!)
```

The log showed Enemy7's distance to player remained constant (~530px) despite being in PURSUING state, indicating the enemy was effectively frozen due to rapid state switching.

### Root Cause

The state thrashing occurred due to **flickering line-of-sight** at wall/obstacle edges:

1. **PURSUING state** (line 1854-1862): If `_can_see_player and can_hit`, transition to COMBAT
2. **COMBAT state** (line 1188-1194): If `not _can_see_player`, transition to PURSUING

When an enemy is at a position where the raycast to the player is at the exact edge of a wall:
- Frame N: Raycast hits player → `_can_see_player = true` → PURSUING transitions to COMBAT
- Frame N+1: Raycast hits wall edge → `_can_see_player = false` → COMBAT transitions to PURSUING
- Frame N+2: Raycast hits player → repeat...

This creates a continuous loop where the enemy rapidly switches states every physics frame, preventing any actual movement or behavior.

### Solution: Minimum State Duration

Added **minimum time requirements** before allowing state transitions due to lost/gained line of sight:

```gdscript
## Minimum time in COMBAT state before allowing transition to PURSUING due to lost line of sight.
const COMBAT_MIN_DURATION_BEFORE_PURSUE: float = 0.5

## Minimum time in PURSUING state before allowing transition to COMBAT.
const PURSUING_MIN_DURATION_BEFORE_COMBAT: float = 0.3

## Timer tracking total time spent in COMBAT state this cycle.
var _combat_state_timer: float = 0.0

## Timer tracking total time spent in PURSUING state this cycle.
var _pursuing_state_timer: float = 0.0
```

**COMBAT state changes:**
```gdscript
func _process_combat_state(delta: float) -> void:
    _combat_state_timer += delta
    # ...
    if not _can_see_player:
        # Only transition after minimum time to prevent rapid state thrashing
        if _combat_state_timer >= COMBAT_MIN_DURATION_BEFORE_PURSUE:
            _transition_to_pursuing()
            return
```

**PURSUING state changes:**
```gdscript
func _process_pursuing_state(delta: float) -> void:
    _pursuing_state_timer += delta
    # ...
    if _can_see_player and _player:
        var can_hit := _can_hit_player_from_current_position()
        # Only transition after minimum time to prevent rapid state thrashing
        if can_hit and _pursuing_state_timer >= PURSUING_MIN_DURATION_BEFORE_COMBAT:
            _transition_to_combat()
            return
```

Timers are reset:
- In `_transition_to_combat()` and `_transition_to_pursuing()`
- In `_reset()` on enemy respawn

### Why This Works

1. **Stability window**: The 0.3-0.5 second delays provide a stability window where momentary line-of-sight flickering is ignored
2. **Natural gameplay feel**: These delays are short enough to feel responsive but long enough to prevent hundreds of state changes per second
3. **Consistent behavior**: Enemies now commit to their current state for at least a fraction of a second before re-evaluating
4. **No impact on valid transitions**: Legitimate state changes (like being shot at, reaching a position, etc.) still work normally through other state transition paths

### Files Changed

- `scripts/objects/enemy.gd`:
  - Added `COMBAT_MIN_DURATION_BEFORE_PURSUE` constant (0.5s)
  - Added `PURSUING_MIN_DURATION_BEFORE_COMBAT` constant (0.3s)
  - Added `_combat_state_timer` and `_pursuing_state_timer` variables
  - Modified `_process_combat_state()` to track timer and check before PURSUING transition
  - Modified `_process_pursuing_state()` to track timer and check before COMBAT transition
  - Updated `_transition_to_combat()` and `_transition_to_pursuing()` to reset respective timers
  - Updated `_reset()` to reset both timers on enemy respawn

### Additional Lessons Learned

4. **Raycast edge cases**: Line-of-sight checks using raycasts can flicker at wall edges due to floating-point precision and frame-to-frame position changes
5. **State machine hysteresis**: State machines that rely on binary conditions (can see/can't see) need hysteresis or debouncing to prevent rapid oscillation
6. **Log analysis importance**: The issue was only identifiable through careful log analysis - the user reported "stuck suppressed" but the actual bug was state thrashing

---

## Third Bug Report (2026-01-20): Only One Enemy Attacks

### User Report

After the state thrashing fix was deployed, user reported:
> "в описанных ситуациях игрока должны атаковать все враги в зоне слышимости (не только один какой то)"
> (Translation: "in the described situations, ALL enemies in hearing range should attack the player, not just one")

Attached logs: `game_log_20260120_181815.txt`, `game_log_20260120_182103.txt`, `game_log_20260120_182213.txt`

### Log Analysis

The logs showed that enemies were correctly hearing vulnerability sounds and setting the `_pursuing_vulnerability_sound` flag, but then immediately transitioning to RETREATING due to `_under_fire`:

```
[18:22:31] [ENEMY] [Enemy2] Heard player EMPTY_CLICK at (749.2318, 793.9338), intensity=0.02, distance=333
[18:22:31] [ENEMY] [Enemy3] Heard player EMPTY_CLICK at (749.2318, 793.9338), intensity=0.10, distance=161
[18:22:31] [ENEMY] [Enemy2] Pursuing vulnerability sound at (749.2318, 793.9338), distance=333
[18:22:31] [ENEMY] [Enemy3] State: PURSUING -> RETREATING  <-- BUG: Should continue pursuing!
```

### Root Cause

The bug was in `_process_pursuing_state()` and `_process_combat_state()`:

```gdscript
# Line 1841 in _process_pursuing_state():
if _under_fire and enable_cover:
    _pursuit_approaching = false
    _pursuing_vulnerability_sound = false  # <-- This clears the flag!
    _transition_to_retreating()
    return
```

When an enemy heard a vulnerability sound:
1. The `_pursuing_vulnerability_sound` flag was set to `true`
2. Enemy transitioned to PURSUING state
3. But the first check in PURSUING state is `_under_fire`
4. If enemy is being shot at, it immediately:
   - Clears the `_pursuing_vulnerability_sound` flag
   - Transitions to RETREATING
5. The vulnerability sound pursuit never happens!

This defeats the entire purpose of vulnerability sounds - the player is reloading or out of ammo, so THIS IS THE BEST TIME TO ATTACK, not retreat!

### Solution

Modified the suppression checks in PURSUING and COMBAT states to **skip retreating when `_pursuing_vulnerability_sound` is true**:

**PURSUING state (line 1841):**
```gdscript
# Before:
if _under_fire and enable_cover:

# After:
if _under_fire and enable_cover and not _pursuing_vulnerability_sound:
```

**COMBAT state (line 1182):**
```gdscript
# Before:
if _under_fire and enable_cover:

# After:
if _under_fire and enable_cover and not _pursuing_vulnerability_sound:
```

Also expanded the list of states that should transition to PURSUING when hearing vulnerability sounds:
- IDLE
- IN_COVER
- SUPPRESSED
- RETREATING (new)
- SEEKING_COVER (new)

Added logging to track vulnerability-triggered pursuits:
```gdscript
_log_to_file("Vulnerability sound triggered pursuit - transitioning from %s to PURSUING" % AIState.keys()[_current_state])
```

### Why This Works

1. **Priority system**: When player is vulnerable, attacking takes priority over self-preservation
2. **Realistic behavior**: If an enemy hears an opponent is reloading, they would press the attack, not hide
3. **Risk-reward**: This makes reload sounds a high-risk action when enemies are nearby
4. **ALL enemies react**: Every enemy in hearing range will now pursue the vulnerability sound

### Files Changed

- `scripts/objects/enemy.gd`:
  - Modified `_on_player_sound_heard()` to handle RETREATING and SEEKING_COVER states
  - Modified `_process_pursuing_state()` to skip `_under_fire` check when `_pursuing_vulnerability_sound` is true
  - Modified `_process_combat_state()` to skip `_under_fire` check when `_pursuing_vulnerability_sound` is true
  - Added logging for vulnerability-triggered state transitions

### Final Lessons Learned

7. **Priority systems**: Some conditions should override others - vulnerability sounds override suppression behavior
8. **Complete state coverage**: When adding new behavior, ensure it handles all relevant states
9. **User feedback is invaluable**: The user correctly identified that "all enemies should attack" not just one
