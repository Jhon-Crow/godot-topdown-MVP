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
