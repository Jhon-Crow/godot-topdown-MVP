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

---

## Follow-up Bug Report (2026-03-27): Operator Still Goes to Corner After Dash

After Session 5 fix, owner reported: "всё ещё идёт в одну сторону" (still going in one direction).

### Evidence (`game_log_20260327_084941.txt`)

Key sequence:
- 08:50:47: Player bullet enters threat sphere. `Dash activated! Dir: (0.82, -0.57)` (northeast)
- 08:50:47: `Sideways evade: dir=...` logged many times as new bullets arrive (direction display only; `try_dash()` returns `false` because `_dash_active=true`, so `_dash_direction` is NOT changed)
- 08:50:47-48: Operator gunshots from `(1004, 249)` → `(1127, 163)` — moving northeast along top wall
- 08:50:50: `No valid cover found (enemy at (1529,88))` → `COMBAT → SEEKING_COVER`
- 08:50:50+: Repeated `No valid cover found (enemy at (1775,88))` until death — stuck in corner again

### Root Cause Analysis (Session 6)

Session 5's fix zeroed velocity and reset COMBAT approach state. The operator correctly had `_clear_shot_target = Vector2.ZERO` and `_seeking_clear_shot = false`. However, after the dash landed near the top wall, the following frame of `_process_combat_state()` found:
- `has_clear_shot = false` — bullet spawn is blocked by the top wall
- `_seeking_clear_shot = false` → starts seeking again immediately (line 1556)
- `_calculate_clear_shot_exit_position()` returns a target **perpendicular to the player direction** from the current (wall-adjacent) position

Since the operator is above the player (operator at ~y=250, player at ~y=600), `direction_to_player ≈ (−0.23, 0.97)` (south). Perpendicular to south = **east or west**. The function picks east (away from player laterally), placing the target along the top wall heading toward `(1775, 88)`.

The COMBAT clear-shot seeking logic uses **simple wall avoidance** (`_apply_wall_avoidance`) — not navmesh pathfinding. It slides the operator along the wall until reaching the corner where no cover exists.

**Why Session 5 was insufficient:** Resetting `_seeking_clear_shot = false` and `_clear_shot_target = Vector2.ZERO` only clears stale pre-dash data. On the very next frame, the same problematic navigation logic restarts from the post-dash (wall-adjacent) position with the same broken perpendicular target.

### Fix Applied (Session 6)

The root cause is that COMBAT's clear-shot seeking uses simple direction math rather than proper navmesh pathfinding. After a dash the operator needs to be re-routed using the navmesh.

**In `enemy.gd::_on_drone_operator_dash_ended()`:** Transition to `SEEKING_COVER` after the dash if currently in COMBAT:

```gdscript
func _on_drone_operator_dash_ended() -> void:
    _combat_exposed = false; _combat_approaching = false; _seeking_clear_shot = false; _clear_shot_target = Vector2.ZERO; _combat_approach_timer = 0.0; _combat_shoot_timer = 0.0
    if enable_cover and _current_state == AIState.COMBAT: _transition_to_seeking_cover()
```

`_transition_to_seeking_cover()` calls `_find_cover_position()` immediately to find a new cover point, then `_process_seeking_cover_state()` uses `_move_to_target_nav()` (navmesh-based pathfinding) to route the operator to cover. If no cover is found, it transitions back to COMBAT via the normal `time_in_state >= SEEKING_COVER_MIN_DURATION` check. This ensures the operator uses proper pathfinding after a dash instead of wall-sliding toward corners.

- Log file: `game_log_20260327_084941.txt`

---

## Session 7 — Dash Too Late + Far Cover After Dodge

After Session 6 fix, owner reported two issues (comment 2026-03-27T06:17:31Z):
1. "рывок срабатывает, но не спасает от пули (слишком поздно)" — dash works but doesn't save from bullet (too late)
2. "всё ещё враг идёт в одном направлении после уворота" — enemy still goes in one direction after dodging

### Evidence (`game_log_20260327_091519.txt`)

**Issue 1 (dash too late):**
```
[09:16:17] [ENEMY] [EnemyDroneOperator] [#1311] Player bullet entered threat sphere — suppression triggered
[09:16:17] [INFO] [DroneOperator] Sideways evade: dir=(0.88, 0.47)
[09:16:17] [INFO] [DroneOperator] Dash activated! Dir: (0.88, 0.47), charges left: 3/4
[09:16:17] [ENEMY] [EnemyDroneOperator] Hit: dmg=2, hp=3/3->1/3   ← hit same timestamp!
```
The dash starts and the operator is hit at the same timestamp. The bullet entered the 100px sphere, the dash was triggered (0 reaction delay), but the bullet was still close enough to connect.

**Issue 2 (far cover after dodge):**
```
[09:16:17] → Dash at dir=(0.88, 0.47) from ~(540, 568)
[09:16:21] → Operator shoots from (1775.924, 1175.999) — 1220px away!
```
Session 6's `_transition_to_seeking_cover()` found cover at (1775, 1175) — a valid cover (hidden from player) but 1220px away. Operator spent 4 seconds traveling there. Once there, it stays and shoots from that far corner.

### Root Cause Analysis (Session 7)

**Bug 1 — Threat sphere too small:**
At `threat_sphere_radius=100px` and bullet speed ~1350px/s, a bullet crosses the entire sphere in 74ms. With `reaction_delay=0`, the dash triggers immediately — but the bullet is still inside the sphere flying toward the operator. A 0.15s sidestep at ~375px/s = 56px perpendicular displacement may not be enough if the bullet was already less than 56px off-axis when the dash started.

Increasing the sphere to 200px gives 148ms before the bullet reaches the operator center — enough time for the 56px sidestep to move the hitbox clear of a bullet aimed at the original position.

**Bug 2 — Session 6's seeking-cover sends operator far away:**
`_transition_to_seeking_cover()` → `_find_cover_position()` picks the **closest** cover point that is hidden from the player. In a large level, "closest hidden cover" can still be 1200px away. After reaching it, the operator is far from the player and gets stuck in a corner shooting from max range.

The real goal after a dash is: **stay in COMBAT at the new position**, not run to distant cover. Resetting `_has_valid_cover = false` is sufficient — COMBAT will call `_find_cover_position()` on the next frame and use the result for its approach cycle.

### Fixes Applied (Session 7)

**Fix 1 — Larger threat sphere for ACTIVE phase:**
In `drone_operator_component.gd`:
- Added `ACTIVE_THREAT_SPHERE_RADIUS = 200.0` constant
- Added `_resize_threat_sphere(radius)` helper that resizes the parent's ThreatSphere CollisionShape2D
- Called `_resize_threat_sphere(ACTIVE_THREAT_SPHERE_RADIUS)` in `_transition_to_active()`

**Fix 2 — Stay in COMBAT after dash (no far cover travel):**
In `enemy.gd::_on_drone_operator_dash_ended()`: removed `_transition_to_seeking_cover()` call; replaced with `_has_valid_cover = false` to invalidate cached cover and trigger a fresh nearby search on the next COMBAT frame.

```gdscript
func _on_drone_operator_dash_ended() -> void:
    _combat_exposed = false; _combat_approaching = false
    _seeking_clear_shot = false; _clear_shot_target = Vector2.ZERO
    _combat_approach_timer = 0.0; _combat_shoot_timer = 0.0
    _has_valid_cover = false  # Force cover re-search from new post-dash position
```

- Log file: `game_log_20260327_091519.txt`

---

## Session 8 — 2026-03-27 (game_log_20260327_094721.txt)

**User report:** "всё ещё идёт в одну сторону; рывок срабатывает только один раз и не спасает от урона" (still goes in one direction; dash triggers only once and doesn't prevent damage)

### Issue 8a: Dash fires but bullet still hits

**Log evidence:**
```
[09:48:04] Dash activated! Dir: (-0.18, -0.98), charges left: 3/4
[09:48:04] Hit: dmg=1, hp=2/2->1/2
```
Both events occur at the same timestamp — the bullet hits the operator the same frame the dash triggers.

**Root cause:** The perpendicular sidestep direction `(-0.18, -0.98)` is nearly vertical (north). With `DASH_SPEED_MULTIPLIER=1.25`, sidestep distance = `320 * 1.25 * 0.15 = 60px`. A sniper rifle bullet at 1350px/s closing from north gives the operator ~148ms to move 60px to the west. If the bullet was already within 60px horizontal of the operator's hitbox at the moment the dash triggered, the 60px westward movement is insufficient to clear the hitbox.

**Fix:** Increase `DASH_SPEED_MULTIPLIER` from 1.25 to 2.5, giving `320 * 2.5 * 0.15 = 120px` — twice the evasion distance. This reliably moves the operator outside a typical bullet hitbox width even against sniper fire.

### Issue 8b: Operator still goes in one direction after dodge

**Log evidence:**
```
[09:48:04] Dash activated! Dir: (-0.18, -0.98)
[09:48:04] Hit triggered COMBAT from SEEKING_COVER  (second dash at 09:48:20)
[09:48:21] State: COMBAT -> PURSUING  (rapid cycling)
[09:48:22] State: PURSUING -> COMBAT
```
After the dash, `_on_drone_operator_dash_ended()` set `_has_valid_cover = false`, which caused COMBAT to re-enter the clear-shot seeking phase. `_calculate_clear_shot_exit_position()` uses `_apply_wall_avoidance()` (simple math) to pick a perpendicular target that avoids walls, but this naive approach repeatedly targeted the east wall → operator walked to the corner.

**User suggestion confirmed:** Enable FLANKING state after the dash. FLANKING uses `_move_to_target_nav()` (navmesh-based pathfinding) to pick a lateral position around the player, which navigates around obstacles correctly and returns to COMBAT once the operator has a clear shot.

**Fix:** In `_on_drone_operator_dash_ended()`, after resetting stale state, check `_can_attempt_flanking()` and call `_transition_to_flanking()` if in COMBAT state. Falls back to COMBAT automatically if flanking is unavailable (disabled, on cooldown, or path blocked — `_transition_to_flanking()` returns false and transitions to COMBAT internally).

```gdscript
func _on_drone_operator_dash_ended() -> void:
    _combat_exposed = false; _combat_approaching = false; _seeking_clear_shot = false
    _clear_shot_target = Vector2.ZERO; _combat_approach_timer = 0.0; _combat_shoot_timer = 0.0
    _has_valid_cover = false
    if _current_state == AIState.COMBAT and _can_attempt_flanking() and _player != null:
        _transition_to_flanking()
```

### Files changed (Session 8)

| File | Change |
|------|--------|
| `scripts/components/drone_operator_component.gd` | `DASH_SPEED_MULTIPLIER`: 1.25 → 2.5 (60px → 120px sidestep) |
| `scripts/objects/enemy.gd` | `_on_drone_operator_dash_ended()`: add FLANKING transition after state reset |
| `tests/unit/test_drone_operator.gd` | Update mock constant + sidestep range test (≥100px, ≤200px) |

- Log file: `game_log_20260327_094721.txt`

---

## Session 9 — 2026-03-27T08:00 (Machete component replacement)

**User report:** "проблема сохраняется — такое ощущение что дроновод идёт на какую то глобальную координату" (problem persists — drone operator seems to walk to a global coordinate)

**User direction:** "полностью убери текущую логику уворота — вместо неё добавь логику уворота как у врага с мачете (просто уворачивается от пули без рывка)"

### Root Cause

The 8 prior sessions accumulated a complex dash-based evasion system with charges, cooldowns, and post-dash state resets. The accumulated side-effects (corner-walking, one-time dash, etc.) were repeatedly compounding. The user requested a clean break: replace with the proven MacheteComponent dodge logic.

### Fix Applied (Session 9)

- Removed all custom dash code from `drone_operator_component.gd`
- Added `_dodge_component: MacheteComponent` for ACTIVE phase dodge
- In `enemy.gd COMBAT state`: trigger `_drone_operator.try_dodge()` on threat, return if dodging

**Regression introduced:** The ACTIVE combat block after the dodge check fell through to machete-specific code:
- `_machete.perform_melee_attack()` — drone operator has no melee
- `_machete.get_backstab_approach_position()` — runs toward player like melee enemy
- `_move_to_target_nav(tp, combat_move_speed)` + `return` — prevents normal combat

---

## Session 10 — 2026-03-27 (Current — game_log_20260327_225205.txt)

**User report:** "не надо полностью копировать поведение мачете врага. сейчас дроновод просто вбегает в игрока и всё. должен вести себя как обычный враг (не мачете), но с уворотом как у мачете"

### Evidence (`game_log_20260327_225205.txt`)

- 22:52:34: Drone destroyed → ACTIVE phase, dodge component set up
- 22:52:34: Bullets enter threat sphere → `[#1311] Player bullet entered threat sphere — suppression triggered`
- 22:52:34-49: Operator keeps rotating (ROT_CHANGE logged) in COMBAT state — alive, sees player
- No shooting logged, no retreat to cover, no dodge events
- The operator never fired despite being in COMBAT and seeing the player for >15 seconds
- After ACTIVE transition, enemy constantly walks toward player (machete behavior) instead of normal ranged combat

### Root Cause Analysis (Session 10)

**Code path in `_process_combat_state`:**

```
Line 1440: if _drone_operator and phase == ACTIVE:
Line 1441:   [try_dodge on bullet]
Line 1442:   [return if dodging]  ← correct
Line 1443:   if _machete.is_in_melee_range(_player): melee_attack(); return  ← WRONG
Line 1445:   var tp := _player.global_position
Line 1446:   if backstab_opportunity: tp = backstab_position
Line 1447:   _move_to_target_nav(tp, combat_move_speed)  ← walks toward player
Line 1448-1453: machete stuck detection
Line 1454:   return  ← PREVENTS normal combat from running
```

The code after the dodge check was copy-pasted machete combat code. This caused:
1. The operator to walk directly toward the player like a machete enemy
2. Normal ranged combat (shoot, retreat to cover) never ran — `return` on line 1454 prevented it

### Fix Applied (Session 10)

Removed lines 1443-1454 from the drone operator ACTIVE block. Only the bullet-dodge trigger and `return-if-dodging` remain:

```gdscript
# Issue #1540: Drone operator ACTIVE — dodge bullets like machete enemy (lateral sidestep).
# Only the dodge is special; normal ranged combat runs below.
if _drone_operator and _drone_operator.get_phase() == DroneOperatorComponent.Phase.ACTIVE:
    if _under_fire and _bullets_in_threat_sphere.size() > 0 and not _drone_operator.is_dodging():
        var b = _bullets_in_threat_sphere[0]; if is_instance_valid(b):
            var bd: Vector2 = b.get("direction") if b.get("direction") != null else Vector2.RIGHT.rotated(b.rotation)
            _drone_operator.try_dodge(bd)
    if _drone_operator.is_dodging(): velocity = _drone_operator.get_dodge_velocity(); return
```

Normal ranged combat (suppression/retreat, shoot from cover, pursuing) now runs after this block.

- Log file: `game_log_20260327_225205.txt`

