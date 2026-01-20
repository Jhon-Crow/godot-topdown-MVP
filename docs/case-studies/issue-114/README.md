# Case Study: Issue #114 - Update AI (Player Distraction Attack)

## Issue Summary

**Issue Link:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/114

**Original Request (Russian):**
> Если игрок в прямой видимости врага и отводит прицел более чем на 23 градуса от направления врага - враг должен атаковать игрока, не важно, в каком состоянии он находится (с высшим приоритетом).
> Впиши это в существующую систему GOAP.
> Не сломай старый функционал в exe.

**Translation:**
> If the player is in direct line of sight of the enemy and turns their aim more than 23 degrees away from the enemy's direction, the enemy should attack the player with the highest priority, regardless of the enemy's current state.
> Integrate this into the existing GOAP system.
> Don't break the old functionality in the exe.

## Game Logs Analysis

### Logs Collected

Two game log files were provided from real gameplay testing:

1. `logs/game_log_20260118_135255.txt` (788KB, 8933 lines) - Extended gameplay session
2. `logs/game_log_20260118_140230.txt` (66KB, 802 lines) - Focused testing session

### Key Observations from Logs

#### Initial Implementation Problem

The logs revealed a critical issue: **enemies were detecting player distraction but not shooting**.

Example from `game_log_20260118_140230.txt`:
```
[14:02:33] [ENEMY] [Enemy3] Player distracted - priority attack triggered
[14:02:33] [ENEMY] [Enemy3] Player distracted - priority attack triggered
[14:02:33] [ENEMY] [Enemy3] Player distracted - priority attack triggered
... (29 more times)
[14:02:33] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(578.4397, 855.3252), source=ENEMY (Enemy3)
```

The enemy logged "Player distracted - priority attack triggered" 29+ times in a row before finally shooting once. This indicated that:

1. **Detection was working** - The `_is_player_distracted()` function correctly identified when the player wasn't aiming at the enemy
2. **State transition was happening** - The enemy transitioned to COMBAT state
3. **Shooting was blocked** - Internal timers and state phases prevented immediate shooting

#### Root Cause Identified

The original implementation only **transitioned to COMBAT state**, but the COMBAT state itself had multiple phases:
- Phase 0: Seeking clear shot
- Phase 1: Approaching player
- Phase 2: Exposed (shooting phase)
- Phase 3: Return to cover

Shooting only occurred in Phase 2, and required:
- `_combat_exposed = true`
- `_shoot_timer >= shoot_cooldown`
- `_detection_delay_elapsed = true`

When transitioning from states like RETREATING, SUPPRESSED, or IN_COVER, the enemy would:
1. Enter COMBAT state
2. Start in Phase 0/1 (not shooting phase)
3. Have `_combat_exposed = false`
4. Need to wait for phase transitions before shooting

## Problem Analysis

### Root Cause
The original AI system lacked awareness of the player's aiming direction. After the initial fix, enemies would:
- Detect player distraction correctly
- Transition to COMBAT state
- BUT still wait for combat phase timers before shooting
- Miss the window of opportunity when player was distracted

### Key Requirements (Updated)
1. **Detection:** Enemy must detect when player's aim is >23° away from the enemy
2. **IMMEDIATE Shooting:** Enemy must shoot instantly, bypassing ALL timers
3. **State Independence:** Must work from ANY state (RETREATING, SUPPRESSED, IN_COVER, etc.)
4. **Backward Compatibility:** Existing behavior must remain intact when player is aiming at enemy

## Solution Implementation

### 1. Player Distraction Detection (`scripts/objects/enemy.gd`)

Added a new function `_is_player_distracted()` that:
- Gets the player's aim direction (from player position to mouse cursor)
- Calculates the angle between player's aim and the direction to the enemy
- Returns `true` if the angle exceeds 23 degrees (0.4014 radians)

```gdscript
## Threshold angle for considering the player "distracted"
const PLAYER_DISTRACTION_ANGLE: float = 0.4014  # 23 degrees in radians

func _is_player_distracted() -> bool:
    # Calculate direction from player to enemy
    var dir_to_enemy = (enemy_pos - player_pos).normalized()

    # Calculate player's aim direction (toward mouse cursor)
    var aim_direction = (global_mouse_pos - player_pos).normalized()

    # Calculate angle between the two directions using dot product
    var dot = dir_to_enemy.dot(aim_direction)
    var angle = acos(clampf(dot, -1.0, 1.0))

    # Player is distracted if angle > 23 degrees
    return angle > PLAYER_DISTRACTION_ANGLE
```

### 2. GOAP World State Update

Added `player_distracted` to the GOAP world state:
- Initialized in `_initialize_goap_state()`
- Updated every frame in `_update_goap_state()`

### 3. New GOAP Action (`scripts/ai/enemy_actions.gd`)

Created `AttackDistractedPlayerAction` with:
- **Preconditions:** `player_visible: true`, `player_distracted: true`
- **Effects:** `player_engaged: true`
- **Cost:** 0.05 (lowest of all actions, ensuring highest priority)

```gdscript
class AttackDistractedPlayerAction extends GOAPAction:
    func _init() -> void:
        super._init("attack_distracted_player", 0.1)
        preconditions = {
            "player_visible": true,
            "player_distracted": true
        }
        effects = {
            "player_engaged": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        if world_state.get("player_distracted", false):
            return 0.05  # Absolute highest priority
        return 100.0
```

### 4. State Machine Priority Override - Final Fix (`scripts/objects/enemy.gd`)

The key fix was to **bypass all state transitions and timers**, shooting directly when distraction is detected:

```gdscript
func _process_ai_state(delta: float) -> void:
    # HIGHEST PRIORITY: If player is distracted, IMMEDIATELY shoot
    # This bypasses ALL state logic, timers, and phase restrictions
    if _goap_world_state.get("player_distracted", false) and _can_see_player and _player:
        var direction_to_player := (_player.global_position - global_position).normalized()
        var has_clear_shot := _is_bullet_spawn_clear(direction_to_player)

        if has_clear_shot and _can_shoot():
            # Log and aim
            _log_to_file("Player distracted - priority attack triggered")
            rotation = direction_to_player.angle()

            # Shoot IMMEDIATELY - bypass ALL timers and state restrictions
            _shoot()
            _shoot_timer = 0.0  # Reset timer after shot

            # Ensure detection delay is bypassed for follow-up shots
            _detection_delay_elapsed = true

            # Return early - highest priority action taken
            return
```

### 5. Player Ammo Reduction (`scripts/characters/player.gd`)

Reduced player ammunition from 90 to 60 bullets:
- Changed `max_ammo` from 90 to 60
- Changed `_current_ammo` initial value from 90 to 60
- Comment updated: "60 bullets = 2 magazines of 30"

## Testing

### Unit Tests Added (`tests/unit/test_enemy_actions.gd`)

1. **Action Initialization Tests:**
   - `test_attack_distracted_player_action_initialization`
   - `test_attack_distracted_player_action_preconditions`
   - `test_attack_distracted_player_action_effects`

2. **Cost Calculation Tests:**
   - `test_attack_distracted_player_cost_when_distracted`
   - `test_attack_distracted_player_cost_when_not_distracted`

3. **Integration Tests:**
   - `test_distracted_player_attack_has_highest_priority`
   - `test_distracted_player_attack_overrides_other_states`

### Test Coverage
- Verifies action has lowest cost (0.05) when player is distracted
- Confirms GOAP planner selects `attack_distracted_player` over other actions
- Validates priority override even when enemy is under fire or in cover

## Files Modified

| File | Changes |
|------|---------|
| `scripts/objects/enemy.gd` | Added `PLAYER_DISTRACTION_ANGLE` constant, `_is_player_distracted()` function, `player_distracted` GOAP state, **immediate shooting in priority override** |
| `scripts/ai/enemy_actions.gd` | Added `AttackDistractedPlayerAction` class, updated `create_all_actions()` |
| `scripts/characters/player.gd` | Reduced `max_ammo` from 90 to 60, updated initial `_current_ammo` |
| `tests/unit/test_enemy_actions.gd` | Added 7 new unit tests for the distracted player attack feature |

## Backward Compatibility

The implementation ensures backward compatibility by:
1. Only triggering when BOTH conditions are met (player visible AND aim >23° away)
2. Only shooting when enemy has a clear shot and ammo available
3. Following established patterns from other GOAP actions
4. Not modifying any existing action behaviors or costs

## Timeline

1. Initial implementation: State transition to COMBAT on distraction
2. User feedback: "Enemy should shoot from ANY state, even with timer running"
3. Log analysis: Identified timer-blocking issue
4. Final fix: Direct shooting bypass of all timers and states
5. Ammo adjustment: Reduced from 90 to 60 bullets

## Key Lessons Learned

1. **State transitions are not enough** - When implementing priority actions, the action itself must execute, not just a state change
2. **Log analysis is crucial** - The repeated "priority attack triggered" logs clearly showed detection working but shooting failing
3. **Timers need explicit bypass** - Game systems often have multiple layers of timing/cooldown checks that must all be considered

## Conclusion

The solution successfully implements the requested feature by:
- Detecting player distraction using precise angle calculation (23° threshold)
- **Immediately shooting** when distraction is detected, bypassing ALL timers
- Working from ANY enemy state (RETREATING, SUPPRESSED, IN_COVER, etc.)
- Integrating seamlessly with the existing GOAP planning system
- Reducing player ammo to 60 bullets (2 magazines)
- Maintaining full backward compatibility with existing AI behaviors
