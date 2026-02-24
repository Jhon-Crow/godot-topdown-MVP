# Case Study: Issue #910 - Enemies Don't React When Player Is Invisible

## Issue Summary

**Issue Number:** #910
**Title:** fix враги не выходят из idle когда игрок в Невидимости
**Translation:** Enemies should shoot approximately toward the sound source (in a fan/spread) or at the muzzle flash when the player is invisible.
**Status:** Open
**Author:** Jhon-Crow

### Original Description (Russian)
> когда игрок в Невидимости (активен предмет Невидимость) враги должны стрелять примерно в источник звука (веером) или по вспышке от ствола. можешь использовать наработки из https://github.com/Jhon-Crow/godot-topdown-MVP/pull/800 если здесь есть что то полезное.

### Translation
> When the player is Invisible (Invisibility item is active), enemies should shoot approximately at the sound source (in a fan pattern) or at the muzzle flash. You can use the work from PR #800 if there is something useful there.

---

## Root Cause Analysis

### The Bug

When the player has the Invisibility Suit active and fires their weapon:
1. `SoundPropagation` emits a `GUNSHOT` sound event at the muzzle position
2. The enemy's `on_sound_heard_with_intensity()` is called → updates `_last_known_player_position` → calls `_transition_to_combat()`
3. In `_process_combat_state()`: since `_can_see_player == false` (player is invisible), the enemy quickly transitions to `PURSUING`
4. In `_process_pursuing_state()`: enemy tries to find pursuit cover or moves toward `_last_known_player_position` (the sound position)
5. **BUT: the enemy never shoots** - all existing shooting code checks `_can_see_player` first

### Evidence from Code (enemy.gd)

**Check `_check_player_visibility()` at line 3593-3596:**
```gdscript
# If player is invisible (invisibility suit active), cannot see player (Issue #673)
if _player.has_method("is_invisible") and _player.is_invisible():
    _continuous_visibility_timer = 0.0
    return  # _can_see_player stays false
```

**In COMBAT state (line 1586):**
```gdscript
if _can_see_player and _player and _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
    _aim_at_player()
    _shoot()
```
→ Never shoots because `_can_see_player` is false.

**In PURSUING state (line 1952-1979):** Only shoots if `_can_see_player` is true.

### What Enemies DO Correctly (Before Fix)

When player fires while invisible:
1. ✅ Enemy hears gunshot sound → updates `_last_known_player_position`
2. ✅ Enemy memory is updated with sound confidence (0.7)
3. ✅ Enemy transitions from IDLE to COMBAT → PURSUING
4. ✅ Enemy moves toward the sound position (cover-to-cover)
5. ❌ **Enemy NEVER fires toward the sound source**

---

## Related Code Analysis

### Invisibility System (player.gd, Issue #673)
- `player.is_invisible()` → returns true when suit is active
- `_reset_all_enemy_memories("invisibility activation")` → called when invisibility activates, causing enemies to enter search mode (Issue #723)
- The suit deactivates after a timer, then enemies can see the player again

### Sound Propagation System (sound_propagation.gd)
- `GUNSHOT` sound type (0) propagates 1469px (full viewport diagonal)
- `emit_player_gunshot(position, source_node)` called when player fires
- Enemy `on_sound_heard_with_intensity()` receives the position of the shot

### Memory System (enemy.gd, line 687-689)
```gdscript
_last_known_player_position = position  # Set to gunshot position
if _memory:
    _memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)  # 0.7 confidence
```

### Existing Suppressive Fire Patterns (enemy.gd)
- `_shoot_with_inaccuracy()` - fires with spread for retreat shooting
- `_shoot_burst_shot()` - fires arc burst for ONE_HIT retreat
- The `RETREAT_INACCURACY_SPREAD = 0.15` rad is already used

---

## Solution Design

### Approach: "Spray-at-Sound" Mode for Invisible Player

When the player is invisible and has recently fired their weapon:
1. Enemy knows the gunshot position (`_last_known_player_position`)
2. Enemy should **aim toward the sound source** and fire a **fan/spread pattern**
3. This simulates realistic suppressive fire behavior - shooting where sound came from even without visual confirmation
4. Should work in COMBAT, PURSUING, IN_COVER, and SUPPRESSED states

### Key Design Decisions

#### When to Spray
The spray behavior activates when **all** of:
- `_player.is_invisible()` is true
- `_last_known_player_position != Vector2.ZERO` (have sound position)
- Enemy is in PURSUING or COMBAT or IN_COVER or SUPPRESSED state
- `_shoot_timer >= shoot_cooldown` (ready to shoot)

#### Fan Fire Parameters
- **Spread angle:** `INVISIBLE_PLAYER_FAN_SPREAD = 0.5` rad (~28°) - wider than normal inaccuracy
- **Number of fan shots:** Fires single shots with large spread (existing ammo economy)
- **Aim position:** `_last_known_player_position` (the gunshot/sound position)
- **Check:** `_is_bullet_spawn_clear()` to avoid shooting into walls

#### Where to Add the Behavior

New function `_shoot_suppressive_at_sound_position()`:
- Aims enemy toward sound position
- Fires with fan spread
- Checks bullet spawn is clear

Integrated into:
1. `_process_pursuing_state()` - when pursuing but can't see player and player is invisible
2. `_process_combat_state()` - when in combat but player is invisible

---

## Implementation Plan

### 1. New Constants
```gdscript
## Issue #910: Fan spread angle when shooting toward invisible player's sound source.
const INVISIBLE_PLAYER_FAN_SPREAD: float = 0.5  ## ~28° spread

## Issue #910: Range within which enemies fire suppressive shots at sound position.
const INVISIBLE_PLAYER_SUPPRESSIVE_RANGE: float = 600.0
```

### 2. New State Variable
```gdscript
## Issue #910: Whether currently tracking invisible player by sound.
var _suppressing_invisible_player: bool = false

## Issue #910: Timer for suppressive fire bursts (so enemy doesn't fire too fast).
var _suppressive_fire_timer: float = 0.0
const SUPPRESSIVE_FIRE_COOLDOWN: float = 0.3  ## Fire every 0.3s = ~3 shots/sec
```

### 3. New Helper Function
```gdscript
## Issue #910: Aim at a position (not the player directly).
func _aim_at_position(pos: Vector2) -> void:
    var direction := (pos - global_position).normalized()
    var target_angle := direction.angle()
    var angle_diff := wrapf(target_angle - rotation, -PI, PI)
    var delta := get_physics_process_delta_time()
    if abs(angle_diff) <= rotation_speed * delta:
        rotation = target_angle
    elif angle_diff > 0:
        rotation += rotation_speed * delta
    else:
        rotation -= rotation_speed * delta

## Issue #910: Fire suppressive rounds at estimated position of invisible player.
## Shoots in a fan pattern toward the last known sound/gunshot position.
func _shoot_suppressive_at(target_pos: Vector2) -> void:
    if bullet_scene == null:
        return
    if not _can_shoot():
        return
    var weapon_forward := _get_weapon_forward_direction()
    var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)
    var to_target := (target_pos - global_position).normalized()
    # Aim check - only fire if barrel is roughly aimed (wider tolerance for suppressive fire)
    var aim_dot := weapon_forward.dot(to_target)
    if aim_dot < 0.5:  # ~60° tolerance (wider than normal 30°)
        return
    var direction := weapon_forward
    var fan_angle := randf_range(-INVISIBLE_PLAYER_FAN_SPREAD, INVISIBLE_PLAYER_FAN_SPREAD)
    direction = direction.rotated(fan_angle)
    if not _is_bullet_spawn_clear(direction):
        return
    _spawn_projectile(direction, bullet_spawn_pos)
    _spawn_muzzle_flash(bullet_spawn_pos, direction)
    var audio: Node = get_node_or_null("/root/AudioManager")
    if audio and audio.has_method("play_m16_shot"):
        audio.play_m16_shot(global_position)
    var sp: Node = get_node_or_null("/root/SoundPropagation")
    if sp and sp.has_method("emit_sound"):
        sp.emit_sound(0, global_position, 1, self, weapon_loudness)
    _play_delayed_shell_sound()
    _current_ammo -= 1; _shot_count += 1; _spread_timer = 0.0
    ammo_changed.emit(_current_ammo, _reserve_ammo)
    if _current_ammo <= 0 and _reserve_ammo > 0: _start_reload()
```

### 4. Integration Points

**In `_process_pursuing_state()`** - after the initial guard clauses:
```gdscript
# Issue #910: If player is invisible but we heard their gunshot,
# aim at the sound position and fire suppressive rounds in a fan pattern.
if not _can_see_player and _last_known_player_position != Vector2.ZERO:
    if _player and _player.has_method("is_invisible") and _player.is_invisible():
        var dist := global_position.distance_to(_last_known_player_position)
        if dist <= INVISIBLE_PLAYER_SUPPRESSIVE_RANGE:
            _aim_at_position(_last_known_player_position)
            if _shoot_timer >= shoot_cooldown:
                _shoot_suppressive_at(_last_known_player_position)
                _shoot_timer = 0.0
```

**In `_process_in_cover_state()`** - in the "not visible, not under fire" branch:
```gdscript
# Issue #910: Suppress toward sound when player is invisible
if not _can_see_player and _last_known_player_position != Vector2.ZERO:
    if _player and _player.has_method("is_invisible") and _player.is_invisible():
        # Aim and fire suppressive rounds
        ...
```

---

## Test Plan

### Unit Tests (`tests/unit/test_invisible_player_suppressive_fire.gd`)

1. **test_enemy_knows_sound_position** - When gunshot is heard while player invisible, `_last_known_player_position` is set
2. **test_aim_at_position_rotates_toward_target** - `_aim_at_position()` rotates toward target
3. **test_suppressive_fire_spread** - Shots have random spread within fan angle
4. **test_no_suppressive_fire_when_player_visible** - Normal behavior when player visible
5. **test_no_suppressive_fire_when_no_sound_position** - No fire when position unknown
6. **test_suppressive_fire_range_check** - No fire when target too far
7. **test_suppressive_fire_bullet_spawn_clear_check** - No fire when wall blocks spawn
8. **test_fan_spread_angle_constants** - Constants have correct values

---

## References

- Issue #673: Invisibility Suit implementation (player.gd)
- Issue #723: Enemy memory reset when player becomes invisible
- Issue #754: Muzzle flash detection (PR #800 - similar concept for visual flash)
- Issue #322: SEARCHING state for methodical search
- `_shoot_with_inaccuracy()`: Pattern for inaccurate suppressive fire
- `_shoot_burst_shot()`: Pattern for arc/spread burst fire
