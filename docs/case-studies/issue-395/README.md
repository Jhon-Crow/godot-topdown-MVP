# Case Study: Issue #395 - Enemies Turn Wrong Direction on Gunshot Sound

## Issue Summary

**Title (Russian):** враги слыша звук выстрела поворачиваются не в ту сторону или вообще не поворачиваются на выстрел

**Title (English):** Enemies hearing the gunshot turn in the wrong direction or don't turn toward the shot at all

**Description:** After the player shoots, the debug indicator shows that enemies assume the player's position is in a different or even opposite direction. At the same time, enemies don't turn toward the player.

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/395

---

## Timeline of Events

### 1. Sound Detection System (Working Correctly)

When the player shoots:
1. `player.gd` line 615-617 calls `sound_propagation.emit_sound(0, global_position, 0, self, weapon_loudness)`
2. `sound_propagation.gd` propagates the sound to all registered listeners within range
3. `enemy.gd` receives the callback via `on_sound_heard_with_intensity()`

### 2. Sound Position Storage (Working Correctly)

In `enemy.gd` lines 688-694:
```gdscript
# Store the position of the sound as a point of interest
_last_known_player_position = position

# Update memory system with sound-based detection (Issue #297)
if _memory:
    _memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)
```

The sound source position is correctly stored in:
- `_last_known_player_position` - legacy tracking variable
- `_memory.suspected_position` - memory system with confidence tracking

### 3. State Transition (Working Correctly)

In `enemy.gd` line 697:
```gdscript
_transition_to_combat()
```

The enemy correctly enters COMBAT state to investigate the sound.

### 4. Rotation Update (THE BUG)

In `enemy.gd` lines 895-900:
```gdscript
# Priority 2: During active combat states, maintain focus on player even without visibility (#386, #397)
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING, AIState.ASSAULT] and _player != null:
    target_angle = (_player.global_position - global_position).normalized().angle()
    has_target = true
    rotation_reason = "P2:combat_state"
```

**THE PROBLEM:** Priority 2 uses `_player.global_position` (the player's actual current position) instead of:
- `_last_known_player_position` (where the sound came from), or
- `_memory.suspected_position` (the memory system's tracked position)

---

## Root Cause

The Priority 2 rotation logic was added in commit `dda239d` to fix Issue #397 (enemies turning away when they see the player). However, this fix introduced a regression:

**Before fix #397:** Enemies would face wrong directions during combat states
**After fix #397:** Enemies always face the player's **actual** position, even when they shouldn't know it

The fix was too broad - it made enemies face `_player.global_position` in ALL combat states, regardless of whether:
- The enemy can actually see the player
- The enemy only heard a sound and shouldn't know the player's exact position

### Why the Debug Shows Correct Position but Enemy Faces Wrong Direction

The debug visualization in `_draw()` (lines 4723-4744) correctly draws:
- A line to `_memory.suspected_position`
- A confidence-based circle showing uncertainty

But the rotation code ignores this and uses `_player.global_position` directly.

---

## Visual Representation

```
Player (actual position)          Sound Source Position
        P                                  S
        |                                  |
        v                                  v
  [Enemy should face S]          [Enemy actually faces P]
          \                              /
           \                            /
            \                          /
             --------ENEMY-----------
```

When player shoots from position S but then moves to position P:
- Debug indicator shows correct position S
- Enemy turns toward actual player position P (wrong!)

---

## Affected Files

| File | Lines | Issue |
|------|-------|-------|
| `scripts/objects/enemy.gd` | 897-900 | Priority 2 rotation uses wrong position |

---

## Solution Design

The fix should modify Priority 2 to:
1. Only use `_player.global_position` when the enemy **can see** the player
2. Use `_memory.suspected_position` (or `_last_known_player_position`) when the enemy **cannot see** the player but is in a combat state

### Proposed Code Change

```gdscript
# Priority 2: During active combat states, maintain focus on last known position when player not visible
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING, AIState.ASSAULT]:
    var target_position: Vector2
    if _player != null:
        # Use memory system's suspected position if available, otherwise last known
        if _memory and _memory.has_target():
            target_position = _memory.suspected_position
        elif _last_known_player_position != Vector2.ZERO:
            target_position = _last_known_player_position
        else:
            target_position = _player.global_position  # Fallback
    else:
        # No player reference, use stored position
        if _memory and _memory.has_target():
            target_position = _memory.suspected_position
        elif _last_known_player_position != Vector2.ZERO:
            target_position = _last_known_player_position
        else:
            # No target information available
            return  # or continue to next priority
    target_angle = (target_position - global_position).normalized().angle()
    has_target = true
    rotation_reason = "P2:combat_state"
```

---

## Related Issues and PRs

- **Issue #397:** Enemy turns away when seeing player (fixed by adding Priority 2)
- **Issue #386:** Enemy faces player during FLANKING state
- **Issue #347:** Smooth rotation implementation
- **Issue #297:** Memory system for enemy position tracking

---

## Testing Recommendations

1. **Basic Sound Test:**
   - Place player behind cover
   - Shoot in IDLE enemy's hearing range
   - Verify enemy turns toward sound source, not player's actual position

2. **Moving Player Test:**
   - Player shoots, then immediately moves
   - Verify enemy faces original shot position, not new player position

3. **Multiple Sounds Test:**
   - Player shoots multiple times from different positions
   - Verify enemy tracks each sound correctly

4. **Regression Test:**
   - Verify Issue #397 fix still works (enemy doesn't turn away when visible)
   - Verify Issue #386 fix still works (FLANKING state rotation)

---

## Phase 2: Debug Indicator Bug (February 3, 2026)

### Problem Report

After the initial fix was deployed, user reported that the debug indicator (yellow/orange line showing suspected position) was STILL pointing in the wrong direction, even though the rotation logic was now using `_memory.suspected_position`.

### Root Cause Analysis

Investigation of the `_draw()` function revealed a coordinate system bug:

```gdscript
# In _draw() - BUGGY CODE
var to_suspected := _memory.suspected_position - global_position
draw_line(Vector2.ZERO, to_suspected, confidence_color, 1.0)
```

**THE PROBLEM:**
- `_draw()` uses LOCAL coordinates for all drawing operations
- The enemy's `rotation` property affects the coordinate system
- `to_suspected` is calculated in GLOBAL coordinates
- When the enemy rotates (via `rotation = ...` calls in priority attacks, hit reactions, etc.), the draw coordinates are incorrectly rotated

### Evidence from Logs

In `game_log_20260203_120643.txt`, we can see multiple places where `rotation` is modified:
- Line 1167: `rotation = direction_to_player.angle()` (priority attack)
- Line 1218: `rotation = direction_to_player.angle()` (vulnerability attack)
- Line 4099: `_force_model_to_face_direction(attacker_direction)` (hit reaction)

These rotations cause the debug indicator to appear to point in the wrong direction, even though the underlying `_memory.suspected_position` is correct.

### The Fix

Added a helper function to convert global position offsets to local draw coordinates:

```gdscript
## Convert a global position offset to local draw coordinates.
## Issue #395: The enemy's body rotation affects _draw() coordinates, so we must
## counter-rotate global vectors to draw them correctly in local space.
func _global_to_local_draw(global_offset: Vector2) -> Vector2:
    return global_offset.rotated(-rotation)
```

Applied this conversion to ALL draw calls in `_draw()`:
- Line to player (when visible)
- Bullet spawn point
- Cover position
- Clear shot target
- Pursuit cover
- Flank target/cover
- **Suspected position** (the key indicator!)

### Visual Demonstration

```
Before fix:
  Enemy rotation = 45°
  Global vector to target = (100, 0) → points EAST
  _draw() interprets (100, 0) in LOCAL coords → appears to point NORTHEAST

After fix:
  Enemy rotation = 45°
  Global vector to target = (100, 0) → points EAST
  _global_to_local_draw((100,0)) = (70.7, -70.7) → rotated by -45°
  _draw() draws this in LOCAL coords → appears to point EAST (correct!)
```

### Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Added `_global_to_local_draw()` helper function |
| `scripts/objects/enemy.gd` | Fixed all `_draw()` calls to use local coordinates |

---

## Conclusion

This issue had TWO bugs:

1. **Rotation Priority Bug (Initial Fix):** Priority 2 rotation was using actual player position instead of memory/suspected position.

2. **Debug Indicator Bug (Phase 2 Fix):** The `_draw()` function was calculating positions in global coordinates but Godot's draw functions use local coordinates. When the enemy's body rotates, all debug indicators appeared rotated.

The combination of these bugs created a confusing situation where:
- The rotation logic was ACTUALLY working correctly (pointing to memory position)
- But the debug indicator showed the WRONG direction (due to coordinate system bug)
- This made it appear like the rotation was wrong, when it was actually the visualization that was wrong

---

## Phase 3: Model vs Body Rotation Bug (February 3, 2026)

### Problem Report

After the Phase 2 fix, the debug indicator was STILL showing incorrect directions in some scenarios. The user continued to report that enemies were "sharply turning in the wrong direction."

### Root Cause Analysis (Deep Dive)

A careful analysis of the game log revealed that the **rotation calculations were mathematically correct**. For example, at line 219 of the game log:

```
[Enemy2] ROT_CHANGE: P5:idle_scan -> P2:memory, state=COMBAT, target=75.6°, ...
```

- Enemy2 at (400, 550), memory position at (483, 876)
- Vector = (83, 326)
- Expected angle = atan2(326, 83) = **75.6°** ✓

The target angles were correct! So why was the visualization wrong?

### The REAL Problem

The Phase 2 fix used `rotation` (the CharacterBody2D's body rotation):

```gdscript
# Phase 2 code (STILL BUGGY):
func _global_to_local_draw(global_offset: Vector2) -> Vector2:
    return global_offset.rotated(-rotation)  # <-- WRONG rotation!
```

**BUT** the enemy's visual model rotates independently via `_enemy_model.global_rotation`!

In Godot, a CharacterBody2D and its child nodes can have different rotations:
- `rotation` = CharacterBody2D's body rotation (often 0 or set during priority attacks)
- `_enemy_model.global_rotation` = The visual model's rotation (set by `_update_enemy_model_rotation()`)

The `_update_enemy_model_rotation()` function at line 944 sets:
```gdscript
_enemy_model.global_rotation = target_angle  # Model rotation
```

But it does NOT always update the parent body's `rotation`. So:
- When enemy hears a sound → model rotates toward sound via `_update_enemy_model_rotation()`
- Body `rotation` stays at 0 or whatever it was before
- `_global_to_local_draw()` uses `rotation` (0) instead of model rotation
- Debug indicator points in completely wrong direction!

### Evidence from Code

Looking at line 4772-4773 in `_draw_fov_cone()`:
```gdscript
var global_facing := _enemy_model.global_rotation if _enemy_model else global_rotation
var local_facing := global_facing - global_rotation  # Correctly uses model rotation!
```

The FOV cone already correctly used `_enemy_model.global_rotation`, but `_global_to_local_draw()` was using the wrong `rotation` property.

### The Fix

Changed `_global_to_local_draw()` to use `_enemy_model.global_rotation`:

```gdscript
## Convert global offset to local draw coords (Issue #395 Phase 3: use model rotation).
## CRITICAL: The debug visualization must match the EnemyModel's visual rotation, NOT the
## parent CharacterBody2D's rotation. The EnemyModel rotates independently via
## _update_enemy_model_rotation(), while the parent body's rotation may lag behind or
## stay at 0 in some states.
func _global_to_local_draw(global_offset: Vector2) -> Vector2:
    var model_rot := _enemy_model.global_rotation if _enemy_model else global_rotation
    return global_offset.rotated(-model_rot)
```

### Visual Demonstration of the Bug

```
State: Enemy just heard a gunshot, model rotates to face sound

EnemyModel.global_rotation = 75° (facing toward sound source)
CharacterBody2D.rotation = 0° (not updated)

Phase 2 (buggy):
  _global_to_local_draw() uses rotation (0°)
  → No counter-rotation applied
  → Debug indicator shows global coordinates directly
  → Appears to point ~75° away from where model is facing!

Phase 3 (fixed):
  _global_to_local_draw() uses _enemy_model.global_rotation (75°)
  → Counter-rotates by -75°
  → Debug indicator correctly aligns with model's visual facing direction
```

### Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Fixed `_global_to_local_draw()` to use `_enemy_model.global_rotation` |

---

## Conclusion (Updated)

This issue had THREE bugs:

1. **Rotation Priority Bug (Initial Fix):** Priority 2 rotation was using actual player position instead of memory/suspected position.

2. **Coordinate System Bug (Phase 2):** The `_draw()` function was calculating positions in global coordinates but Godot's draw functions use local coordinates.

3. **Wrong Rotation Reference Bug (Phase 3):** The coordinate conversion was using `rotation` (CharacterBody2D body) instead of `_enemy_model.global_rotation` (visual model rotation).

The Phase 3 bug was particularly subtle because:
- The rotation logic was working correctly (model faced right direction)
- The coordinate conversion was applied (Phase 2 fix)
- But it used the WRONG rotation value, causing indicators to appear wrong
- This made it look like the rotation was buggy, when it was actually correct!

### Lessons Learned

1. **Coordinate Systems:** Always be explicit about whether you're working in global or local coordinates, especially in `_draw()` functions.

2. **Debug Tools Can Lie:** When debug visualization disagrees with expected behavior, verify the debug code itself before assuming the underlying logic is wrong.

3. **Multiple Rotations:** In Godot, CharacterBody2D can have BOTH a body `rotation` AND a child model `global_rotation`. These are independent and affect different things. **Always verify which rotation you're using and why.**

4. **Test Assumptions:** When math appears correct but behavior is wrong, trace through exactly which variable values are being used. The "obvious" variable may not be the right one.

---

## Phase 4: Visually Confusing "Turn Away First" Bug (February 3, 2026)

### Problem Report

After all previous fixes, the user continued to report: "enemies first turn away, then slowly turn toward the player" (Russian: "сначала враги отворачиваются, затем начинают медленно поворачиваться в сторону игрока").

The debug indicators were now correct, but the **visual behavior** was still confusing. Enemies appeared to turn in the "wrong" direction before eventually facing the player.

### Game Log Evidence

From `game_log_20260203_123618.txt`:

```
[12:36:25] [ENEMY] [Enemy2] ROT_CHANGE: P5:idle_scan -> P2:memory, state=COMBAT, target=76.9°, current=-157.5°, player=(483,905), memory=(483,911), last_known=(483,911)
```

Key values:
- **current** = -157.5° (enemy facing roughly left-down during idle scan)
- **target** = 76.9° (enemy should face right-down toward memory position)
- **angle_diff** = wrapf(76.9 - (-157.5), -180, 180) = wrapf(234.4, -180, 180) = **-125.6°**

### Root Cause Analysis

The rotation code at line 942-950 uses `wrapf()` to find the **shortest angular path**:

```gdscript
var angle_diff := wrapf(target_angle - current_rot, -PI, PI)
if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
    _enemy_model.global_rotation = target_angle
elif angle_diff > 0:
    _enemy_model.global_rotation = current_rot + MODEL_ROTATION_SPEED * delta
else:
    _enemy_model.global_rotation = current_rot - MODEL_ROTATION_SPEED * delta
```

With `angle_diff = -125.6°`:
- The code rotates in the **negative direction** (clockwise)
- Enemy rotates: -157.5° → -180°/+180° → +76.9°
- This IS the shortest path (126° vs 234° the other way)

**THE VISUAL PROBLEM:**
When rotating from -157.5° (facing left-down) to +76.9° (facing right-down) via the -180°/+180° wrap-around:
- The enemy first rotates FURTHER LEFT (toward -180°)
- Visually, this looks like "turning away from the target"
- Then wraps around and continues toward +76.9°
- Visually, this is the "slowly turning toward player" phase

### Why This Feels Wrong to Players

Human perception expects enemies to turn **directly toward** a threat. Even though the mathematical path is shorter, rotating through -180° (the "back" direction) creates a momentary impression that the enemy is:
1. Ignoring the threat
2. Turning the "wrong way"
3. Being confused or bugged

At MODEL_ROTATION_SPEED = 3.0 rad/s (172°/s), a 126° rotation takes about 0.73 seconds. The initial "turning away" phase (≈22.5° to reach -180°) takes about 0.13 seconds - brief but noticeable.

### The Fix

When transitioning from an idle priority (P5:idle_scan, P3:corner, P4:velocity) to a combat priority (P1:visible, P2:memory), **snap the rotation instantly** instead of smooth interpolation:

```gdscript
# Issue #395 Phase 4: Track if we're transitioning INTO combat from idle
var entering_combat_from_idle := false
if rotation_reason != _last_rotation_reason:
    # Detect transition from idle to combat priority
    if _last_rotation_reason in ["", "none", "P5:idle_scan", "P3:corner", "P4:velocity"] \
       and rotation_reason in ["P1:visible", "P2:memory", "P2:last_known", "P2:fallback"]:
        entering_combat_from_idle = true

# ... later in the rotation code ...

# Issue #395 Phase 4: When entering combat from idle, snap rotation instantly
if entering_combat_from_idle:
    _enemy_model.global_rotation = target_angle
    _log_to_file("ROT_SNAP: instant rotation on combat entry (diff=%.1f°)" % rad_to_deg(angle_diff))
```

### Why Instant Snap is Better

1. **Matches Player Expectations:** Enemies immediately face threats, appearing alert and competent
2. **No Visual Confusion:** No "turning away" moment that looks like a bug
3. **Combat-Appropriate:** In real combat, soldiers would snap to face a threat, not smoothly rotate
4. **Preserves Smooth Rotation Elsewhere:** Non-combat priorities (patrol, corner check, velocity) still use smooth rotation for visual polish

### Alternative Solutions Considered

1. **Increase rotation speed:** Would reduce the problem but not eliminate it. Also affects all rotation, not just combat entry.

2. **Always take "intuitive" path:** Complex to define "intuitive" - sometimes short path IS intuitive.

3. **Two-stage rotation:** Rotate to intermediate angle first, then to target. Adds complexity without clear benefit.

4. **Instant snap only for large angles:** Inconsistent behavior depending on angle difference.

The chosen solution (instant snap on combat entry) is simple, targeted, and matches player expectations about how enemies should react to threats.

### Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Added combat entry detection and instant rotation snap |

---

## Game Logs

The following game logs document the bug behavior across multiple phases:

1. `game_log_20260203_120643.txt` - Initial report showing rotation issues
2. `game_log_20260203_123618.txt` - Phase 4 investigation showing "turn away first" behavior

---

## Final Conclusion

This issue involved **FOUR distinct bugs** that all contributed to the perception of "enemies turning wrong direction":

1. **Rotation Priority Bug (Initial):** Used actual player position instead of memory position
2. **Coordinate System Bug (Phase 2):** Debug draw used global instead of local coordinates
3. **Wrong Rotation Reference Bug (Phase 3):** Used body rotation instead of model rotation for debug
4. **Visual Perception Bug (Phase 4):** Shortest-path rotation through -180° looked like "turning away"

The final fix ensures enemies snap to face threats immediately when entering combat, providing responsive, intuitive behavior that matches player expectations.
