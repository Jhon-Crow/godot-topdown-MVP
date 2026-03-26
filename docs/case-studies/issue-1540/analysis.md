# Case Study: Issue #1540 — Drone Operator dodges in place, should sidestep visibly

## Summary

The Drone Operator enemy (дроновод) in ACTIVE phase was performing an **aggressive closing dash toward the player** when threatened by bullets, instead of a visible **sideways evasion**. The result was that the dodge was hard to perceive — the operator was moving toward the player (already the expected combat behaviour) rather than stepping out of the bullet's path.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| ~09:49:22 | EnemyDroneOperator spawned at (669, 360). VR headset + tablet confirmed. Drone deployed successfully. |
| ~09:49:37 | Drone entered COMBAT/kamikaze mode. |
| ~09:49:38 | Drone destroyed (2 hits). Operator → ACTIVE phase, silenced pistol, laser sight, reaction_delay=0. |
| ~09:49:58 | First bullet entered threat sphere. `try_dash_from_threat` called. |
| ~09:49:58 | Dash direction logged as `(-0.99, 0.14)` — pointing **toward the player**, not sideways. |
| ~09:49:58 | `[DroneOperator] Aggressive dash toward player` logged ~50+ times per second (log spam during active dash). |
| ~09:49:59 | Operator hit (hp 2→1), then killed. |
| ~09:50:06 | Second operator spawned. Cover seek timed out (3.0s). |
| ~09:50:19 | Same pattern: dash dir `(-0.84,-0.54)` toward player, operator killed. |

---

## Root Cause Analysis

### Primary Bug: Wrong Dash Direction

**File:** `scripts/components/drone_operator_component.gd`, function `try_dash_from_threat()` (line 271).

The function computed the dash direction as:
```gdscript
var to_player: Vector2 = (player.global_position - enemy_pos).normalized()
try_dash(to_player)
```

This is the **vector pointing directly at the player** — so the operator dashed *toward* the player whenever a bullet entered the threat sphere. The comment even stated "aggressive closing dash".

This direction was intentionally set in the previous fix (#1532, commit `3f67ac87`) to close the distance to the player. However, that created a new issue (#1540): a dash toward the player is indistinguishable from normal combat movement, making the evasion invisible to the player.

### Secondary Issue: Dash Distance Too Large

With `DASH_SPEED_MULTIPLIER=6.0` and `DASH_DURATION=0.2s` at `combat_move_speed≈320 px/s`:
```
displacement = 320 × 6.0 × 0.2 = 384 px
```
This is far too large for a "sidestep" — it would fling the operator across the room sideways.

---

## Fix Applied

### 1. Dash direction: perpendicular to bullet trajectory

`try_dash_from_threat()` now:
1. Reads the velocity of the first bullet in the threat sphere.
2. Computes both perpendicular directions (left and right of bullet travel).
3. Picks the side that moves **away from the player** (lower dot product with `to_player`).
4. Falls back to 90° perpendicular to the player direction if no bullet velocity is available.

This makes the evasion clearly visible — the operator visibly steps out of the bullet path.

### 2. Dash parameters tuned for 20-100 px sidestep

| Parameter | Before (Issue #1532) | After (Issue #1540) |
|-----------|---------------------|---------------------|
| `DASH_DURATION` | 0.20 s | 0.15 s |
| `DASH_SPEED_MULTIPLIER` | 6.0 | 1.25 |
| Displacement @ 320 px/s | 384 px | **60 px** ✓ |

60 px is within the requested 20–100 px range, clearly visible, and does not fling the operator across the map.

### 3. Log message updated

`"Aggressive dash toward player"` → `"Sideways evade: dir=(...)"` to reflect the new behaviour.

---

## Tests Added (`tests/unit/test_drone_operator.gd`)

- `test_operator_dash_duration_is_short_for_sidestep` — verifies `DASH_DURATION = 0.15s`
- `test_operator_sidestep_distance_within_range` — verifies 20–100 px at 320 px/s
- `test_evade_direction_is_perpendicular_to_bullet_velocity` — verifies perpendicularity
- `test_evade_picks_side_away_from_player` — verifies correct side selection

---

## Follow-up Bug Report (2026-03-26): Operator Not Dodging At All

After the perpendicular-sidestep fix was merged, the owner reported that the operator no longer dodges **at all** ("сейчас вообще не уворачивается").

### Root Cause: Dash Velocity Overwritten by AI State Processor

**Log evidence** (`game_log_20260326_105350.txt`):
- `[DroneOperator] Dash activated!` is logged (dash activates correctly)
- `[DroneOperator] Dash ended` is **never** logged
- The operator takes damage immediately after the dash is activated and dies in seconds

**Code path analysis** (`scripts/objects/enemy.gd`, `_physics_process`):

1. Line 892: `_update_suppression(delta)` calls `try_dash_from_threat()` → `try_dash()` → sets `velocity` to sidestep direction + `_dash_active = true`
2. Line 892 (continued): `_drone_operator.update(delta)` calls `_update_active()` → `_update_dash()` → maintains `velocity` at sidestep direction
3. **Line 918: `_process_ai_state(delta)` is called AFTER the drone operator update** — it immediately overwrites `velocity` (e.g. `velocity = Vector2.ZERO` in `AIState.COMBAT`) before `move_and_slide()` is called at line 933

The operator's sidestep velocity was set correctly in step 2 but **silently overwritten** in step 3 on every frame, resulting in zero movement. The operator appeared stuck in place while the dash timer was decrementing normally. After 0.15s `_end_dash()` fires and chain window / cooldown starts, but since the operator never moved, new dashes produce the same silent failure.

### Fix Applied

In `enemy.gd`, `_physics_process`, `_process_ai_state` is now conditionally skipped while the drone operator is mid-dash:

```gdscript
if not (_drone_operator and _drone_operator.is_dashing()):  # Issue #1540
    _process_ai_state(delta)
```

This preserves the sidestep velocity through to `move_and_slide()` while `_update_walk_animation`, separation force, knockback, and the physics step itself still execute.

---

---

## Follow-up Bug Report (2026-03-26 10:10): Operator Stops Attacking After Dodge

After the Session 2 fix, the owner reported: "після уворота дроновод залишається у стані combat але перестає атакувати та адекватно рухатися" (after dodge, operator stays in COMBAT but stops attacking and moving properly).

### Root Cause: Suppression Triggered During Cooldown

**Log evidence** (`game_log_20260326_130728.txt`):
- `Dash activated!` fires at T+0
- After the dash ends (0.15s) + chain window (0.4s) → charges drop to 0, cooldown starts (1.2s)
- Next bullet arrives during cooldown → `should_dash_instead_of_suppress()` returned `false` (old check: `charges <= 0 AND cooldown > 0`)
- `_under_fire = true` → COMBAT → RETREATING → IN_COVER → SUPPRESSED chain

### Fix Applied (Session 3)

Simplified `should_dash_instead_of_suppress()` to always return `true` in ACTIVE phase:
```gdscript
func should_dash_instead_of_suppress() -> bool:
    return _phase == Phase.ACTIVE
```
ACTIVE phase operators now NEVER get suppressed regardless of charge/cooldown state.

---

## Follow-up Bug Report (2026-03-26 11:19): Operator Still Not Attacking After Dash

After Session 3 fix, owner reported: "після рывка всь ще не атакуют" (after the dash they still don't attack).

### Root Cause: _process_ai_state Permanently Blocked by Stuck _dash_active

**Log evidence** (`game_log_20260326_141747.txt`):
- `Dash activated!` fires at 14:18:09 (charges 3/4)
- `Sideways evade: dir=...` continues ~30 times at 14:18:09 (frames during dash)
- `Dash ended` **never** appears
- After 14:18:09, the operator produces NO logs (no gunshots, no state transitions) until death at 14:18:15
- Second and subsequent operators (different instances) dodge correctly at 14:18:28+

**Analysis:** The Session 2 fix (`if not is_dashing(): _process_ai_state(delta)`) blocked `_process_ai_state` permanently if `_dash_active` ever became stuck at `true`. The COMBAT state — including shooting logic — lives inside `_process_ai_state`, so the operator froze completely after the first dash.

The root cause of `_dash_active` becoming stuck is not fully determined from logs alone (missing "Dash ended" entries suggest `_update_dash` was not being called), but the consequence is clear: any stuck `_dash_active` would permanently freeze the operator.

### Fix Applied (Session 4)

Instead of **skipping** `_process_ai_state` during a dash, **re-apply the dash velocity AFTER** `_process_ai_state`. This ensures:
1. The operator keeps attacking during and after a dash (COMBAT state always runs)
2. Dash velocity is preserved through to `move_and_slide()` regardless of what COMBAT state sets

**In `drone_operator_component.gd`:** Added `get_dash_velocity()` getter.

**In `enemy.gd`:**
```gdscript
# Before (Session 2 — caused freeze if _dash_active stuck):
if not (_drone_operator and _drone_operator.is_dashing()): _process_ai_state(delta)

# After (Session 4 — always runs, restores velocity if dashing):
_process_ai_state(delta); if _drone_operator and _drone_operator.is_dashing(): velocity = _drone_operator.get_dash_velocity()
```

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1540
- Related fix (changed direction to toward player): commit `3f67ac87` (Issue #1532)
- Log file (original): `game_log_20260326_094908.txt`
- Log file (session 2 regression): `game_log_20260326_105350.txt`
- Log file (session 3 regression): `game_log_20260326_130728.txt`
- Log file (session 4 regression): `game_log_20260326_141747.txt`

---

## Follow-up Bug Report (2026-03-26 12:01): Operator Walks to Corner After Dash

After Session 4 fix, owner reported: "Уже лучше — теперь он стреляет после рывка, но он всё ещё идёт куда то в угол, а не действует как нормальный враг" (now shoots after dash, but still walks to a corner and doesn't act like a normal enemy).

### Evidence (`game_log_20260326_145840.txt`)

Key sequence:
- 14:59:27: Player bullet enters threat sphere. `Dash activated! Dir: (0.71, -0.71)` (northeast)
- During dash: `Sideways evade: dir=...` logged every frame as direction rotates from `(0.71,-0.71)` → `(1.00,-0.05)` (new bullets arriving at different angles)
- 14:59:28: Operator position shifts from `(916,386)` to `(1120,183)` — moved ~300px NE during/after dash
- 14:59:29-30: Operator continues northeast, reaching y=88 (top wall): positions `(1293,88)`, `(1466,88)`, `(1638,88)`, `(1775,88)`
- 14:59:30: `State: COMBAT → SEEKING_COVER` — COMBAT exposure timer expired
- 14:59:30+: Repeated `No valid cover found` — operator is in corner with no reachable cover
- Operator stays stuck at `(1775,88)` (top-right corner) and shoots from there until killed

### Root Cause Analysis

**Two compounding issues:**

**1. Residual velocity after dash (`_end_dash`):**  
After 0.15s the dash ends. `_end_dash()` set `_parent.velocity = _dash_direction * base_speed * 0.5` — 50% of the NE dash velocity. This residual velocity, applied BEFORE the AI could correct course, pushed the operator further NE against the wall.

**2. Stale COMBAT approach state:**  
When the dash fired, the operator was mid-approach with `_combat_approaching = true` and a stale `_clear_shot_target` computed from the pre-dash position. After the dash the operator was at a completely different location, but `_process_combat_state()` kept using the old approach variables. Additionally, `_combat_exposed = true` was reached at the new (bad) position, and after `_combat_shoot_duration` expired the operator transitioned to `SEEKING_COVER` — only to find no cover in the corner.

Because `should_dash_instead_of_suppress()` returns `true` (ACTIVE phase), `_under_fire` is never set, so the `COMBAT → RETREATING` path at line 1468 never fires. The only way to leave COMBAT is via the exposure-timer → SEEKING_COVER path, which leads to the corner cycle.

### Fix Applied (Session 5)

**In `drone_operator_component.gd::_end_dash()`:**
- Set velocity to `Vector2.ZERO` instead of 50% dash direction — stops post-dash coasting into walls
- Call `_parent._on_drone_operator_dash_ended()` if available

**In `enemy.gd`:** Added `_on_drone_operator_dash_ended()` (2-line compact method):
```gdscript
func _on_drone_operator_dash_ended() -> void:
    _combat_exposed = false; _combat_approaching = false
    _seeking_clear_shot = false; _clear_shot_target = Vector2.ZERO
    _combat_approach_timer = 0.0; _combat_shoot_timer = 0.0
```

This forces the COMBAT state to re-evaluate from the post-dash position: recalculate the approach direction toward the player, recompute `_clear_shot_target`, and avoid navigating toward the pre-dash corner waypoint.

- Log file: `game_log_20260326_145840.txt`
