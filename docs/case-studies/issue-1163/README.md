# Case Study: Issue #1163 — Sniper Enemy Special Behavior & Enemy Breaking Bug

## Issue Summary

**Title:** update враг снайпер (update enemy sniper)

**Requirements:**
1. The sniper enemy should stay at maximum distance from the player and shoot from there.
2. When the player is not visible, the sniper should shoot approximately where the player might be — even through cover — since the sniper rifle (ASVK) penetrates cover.

**Additional report (follow-up comment by Jhon-Crow):**
> все враги сломались (такое уже бывало при добавлении новых врагов).
> ("all enemies broke — this has happened before when adding new enemies.")
>
> Attached: `game_log_20260318_095818.txt`

---

## Part 1 — Sniper AI Design (Original Issue)

### Context

The sniper enemy was introduced in Issue #1125, adding the `SNIPER_RIFLE` weapon type (ASVK anti-materiel rifle) to the enemy system. However, #1125 only added the weapon type without special AI behavior. Issue #1163 requests:
1. Standoff range maintenance (stay far, retreat if player closes in)
2. Blind-fire through cover at last-known / predicted player positions

### Implementation

The sniper AI follows the same **early-return guard pattern** used by Machine Gunner (#1033) and RPG enemy (#583):

- New file: `scripts/components/enemy_sniper_component.gd` (`class_name EnemySniperComponent`)
- In `_process_combat_state`: `weapon_type == WeaponType.SNIPER_RIFLE` check routes to `_sniper_component.process_combat()`
- In `_process_pursuing_state`: `_sniper_component.process_pursuing()` holds position and blind-fires

**Constants:**
- `PREFERRED_DISTANCE = 550.0 px` — preferred engagement range
- `MIN_DISTANCE = 350.0 px` — closer than this → actively retreat
- `BLIND_FIRE_COOLDOWN = 5.0 s` — delay between blind shots through cover

**Blind-fire physics:** `SniperBulletEnemy.tscn` has `MaxWallPenetrations = 2`, so bullets physically penetrate cover walls. The sniper fires at `_last_known_player_position` or the `PlayerPredictionComponent` best estimate.

---

## Part 2 — Enemy Breaking Bug (Follow-up Report)

### Symptom

The user reported (after testing the exported build) that all enemies were non-functional:

```
[LabyrinthLevel] Found Environment/Enemies node with 5 children
[LabyrinthLevel] Child 'Enemy1': script=true, has_died_signal=false
[LabyrinthLevel] Child 'Enemy2': script=true, has_died_signal=false
...
[LabyrinthLevel] Enemy tracking complete: 0 enemies registered
```

All 5 enemies (RIFLE and SHOTGUN types — no snipers) had `has_died_signal=false`, meaning `enemy.gd` failed to declare its signals at load time.

### Root Cause Analysis

#### What `has_signal("died") = false` means

In Godot 4, `has_signal()` returns `false` when a node's script failed to **compile** (parse error). Even though `get_script() != null` (the script resource is attached), if the script has a parse error it cannot register its class, signals, or methods.

#### The Variant Inference Error in Godot 4

Godot 4 GDScript treats certain type inference warnings as **errors** during headless export:

```
SCRIPT ERROR: Parse Error: The variable type is being inferred from a Variant value,
so it will be typed as Variant. (Warning treated as error.)
```

This error occurs when:
1. A variable uses `:=` inference
2. The right-hand side is a call to a method whose return type GDScript cannot determine
3. Specifically: calling a **custom enemy method** through a variable typed as `CharacterBody2D` or `Node2D` — since these base classes don't define the custom method, GDScript cannot know the return type

#### Pre-existing Failures (Before This PR)

Even before the sniper component was added, **two pre-existing components** caused `enemy.gd` to fail in headless export:

| File | Line | Issue |
|------|------|-------|
| `scripts/components/suppressive_fire_component.gd` | 51 | `var spawn_pos := _enemy._get_bullet_spawn_position(...)` — Variant inferred from custom method call |
| `scripts/components/enemy_flashlight_component.gd` | 271 | `var angle_to_player := abs(...)` — `abs()` return type inference |
| `scripts/components/enemy_flashlight_component.gd` | 340 | `var enemy_name := _enemy.name if _enemy else "Unknown"` — `StringName` vs `String` type mismatch |
| `scripts/autoload/black_metal_lightning_effects_manager.gd` | 374, 391, 465, 470, 475, 484 | `clamp()` and `floor()` return type inference |

**Evidence from CI logs (run `23232307648`, before sniper component was added):**
```
at: GDScript::reload (res://scripts/components/suppressive_fire_component.gd:51)
at: GDScript::reload (res://scripts/components/enemy_flashlight_component.gd:271)
at: GDScript::reload (res://scripts/components/enemy_flashlight_component.gd:340)
at: GDScript::reload (res://scripts/objects/enemy.gd:-1)
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

#### How Our Sniper Component Made It Worse

Our `enemy_sniper_component.gd` added 3 additional Variant-inference parse errors:

| Line | Code | Problem |
|------|------|---------|
| 33 | `var distance_to_player := _enemy.global_position.distance_to(player.global_position)` | `player` typed as `Node` (not `Node2D`), so `player.global_position` returns `Variant` |
| 40 | `retreat_dir = _enemy._apply_wall_avoidance(retreat_dir)` | `_apply_wall_avoidance()` is a custom method, return type is `Variant` from `CharacterBody2D` perspective |
| 107 | `var spawn_pos := _enemy._get_bullet_spawn_position(to_target)` | Same pattern as `suppressive_fire_component.gd:51` |

**Evidence from CI logs (run `23232493856`, after our commit):**
```
at: GDScript::reload (res://scripts/components/enemy_sniper_component.gd:33)
at: GDScript::reload (res://scripts/components/enemy_sniper_component.gd:39)
at: GDScript::reload (res://scripts/components/enemy_sniper_component.gd:107)
ERROR: Failed to load script "res://scripts/components/enemy_sniper_component.gd" with error "Parse error".
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

#### Cascade Failure Mechanism

```
player_prediction_component.gd (parse errors at lines 273, 315, 459, 470, 582)
    ↓ PlayerPredictionComponent class not registered in global_script_class_cache
    ↓ enemy.gd references `var _prediction: PlayerPredictionComponent` → unresolved type
    ↓ enemy.gd fails to compile (Compile Error at -1)
    ↓ signal "died" not declared → has_signal("died") = false
    ↓ 0 enemies registered → level never completes, enemies don't die

enemy_sniper_component.gd (parse errors, or type mismatch with PlayerPredictionComponent param)
    ↓ EnemySniperComponent class not registered in global_script_class_cache
    ↓ enemy.gd references `var _sniper_component: EnemySniperComponent` → unresolved type
    ↓ enemy.gd fails to compile (compound failure)
```

#### Why This Is a "Known Pattern"

The user noted "this has happened before when adding new enemies." Historical context:
- Each time a new component is added that calls custom enemy methods through a base-typed reference, it causes the same cascade failure in headless export.
- Previous PRs have triggered this same issue: `suppressive_fire_component.gd` (Issue #910) and `enemy_flashlight_component.gd` (Issue #824) both have the same bug pattern.
- The pattern propagates because developers copy the access pattern from existing (broken) components.

### Timeline of Events

```
2026-03-18 06:35 UTC  Commit bd9e3f8c: feat: sniper enemy stays at range and blind-fires
2026-03-18 06:42 UTC  Commit 8d1fc892: refactor: extract sniper AI into EnemySniperComponent
                       CI passes (static analysis doesn't detect runtime parse errors)
                       Build export "succeeds" despite parse errors (export still generates EXE)
2026-03-18 06:43 UTC  Export log shows:
                         ERROR: Failed to load script enemy_sniper_component.gd (Parse error)
                         ERROR: Failed to load script enemy.gd (Parse error)
2026-03-18 ~09:58 local  User downloads and tests build
                         LabyrinthLevel: 5 enemies, has_died_signal=false, 0 registered
                         DocksLevel: Invalid resource (depends on broken enemy.gd)
                         User reports: "все враги сломались"
2026-03-18 ~10:00 UTC  AI session starts (this session)
                       Game log downloaded and analyzed
                       Root cause identified: Variant inference parse errors in components
```

### Fix

Add explicit type annotations to prevent Variant inference in all affected components:

**`enemy_sniper_component.gd` (our new code):**
```gdscript
# Before (line 33-34, caused Variant inference on player.global_position)
var distance_to_player := _enemy.global_position.distance_to(player.global_position)

# After
var player_pos: Vector2 = (player as Node2D).global_position
var distance_to_player: float = _enemy.global_position.distance_to(player_pos)

# Before (line 40, _apply_wall_avoidance() return type unknown)
retreat_dir = _enemy._apply_wall_avoidance(retreat_dir)

# After
retreat_dir = (_enemy._apply_wall_avoidance(retreat_dir) as Vector2)

# Before (line 107, _get_bullet_spawn_position() return type unknown)
var spawn_pos := _enemy._get_bullet_spawn_position(to_target)

# After
var spawn_pos: Vector2 = _enemy._get_bullet_spawn_position(to_target)
```

**`suppressive_fire_component.gd` (pre-existing bug, fixed in this PR):**
```gdscript
# Before
var spawn_pos := _enemy._get_bullet_spawn_position(...)
# After
var spawn_pos: Vector2 = _enemy._get_bullet_spawn_position(...)
```

**`enemy_flashlight_component.gd` (pre-existing bug, fixed in this PR):**
```gdscript
# Before
var angle_to_player := abs(beam_direction.angle_to(to_player))
var enemy_name := _enemy.name if _enemy else "Unknown"
# After
var angle_to_player: float = abs(beam_direction.angle_to(to_player))
var enemy_name: String = str(_enemy.name) if _enemy else "Unknown"
```

**`black_metal_lightning_effects_manager.gd` (pre-existing bug, fixed in this PR):**
```gdscript
# Before
var idx := clamp(int(t * float(points.size() - 1)), 0, points.size() - 2)
var i := floor(t)
var glow_alpha := clamp(cf * intensity * 0.5, 0.0, 1.0)
# After
var idx: int = clamp(...)
var i: float = floor(t)
var glow_alpha: float = clamp(...)
```

**`scripts/ai/player_prediction_component.gd` (pre-existing bug, fixed in this PR — critical cascade root cause):**
```gdscript
# Line 273: h from untyped Array → Variant
# Before
var shift_dir := (h.position - last_known_position).normalized()
# After
var shift_dir: Vector2 = ((h.position as Vector2) - last_known_position).normalized()

# Line 315: same pattern
# Before
var dist := h.position.distance_to(pos)
# After
var dist: float = h.position.distance_to(pos)

# Lines 459, 470: cover_pos from untyped Array → Variant
# Before
var to_cover := (cover_pos - last_pos).normalized()
var enemy_to_cover := (cover_pos - enemy_pos).normalized()
# After
var to_cover: Vector2 = ((cover_pos as Vector2) - last_pos).normalized()
var enemy_to_cover: Vector2 = ((cover_pos as Vector2) - enemy_pos).normalized()

# Line 582: abs() return type inference
# Before
var cross := abs(move_dir.x * to_enemy.y - move_dir.y * to_enemy.x)
# After
var cross: float = abs(move_dir.x * to_enemy.y - move_dir.y * to_enemy.x)
```

### Prevention

1. **Always use explicit type annotations** when calling custom methods on base-typed parent references:
   ```gdscript
   var result: Vector2 = parent._custom_method()  # ✅ correct
   var result := parent._custom_method()           # ❌ Variant inferred if return type unknown
   ```

2. **When ternary expressions mix types** (e.g., `StringName` vs `String`), use `str()` to normalize:
   ```gdscript
   var name: String = str(node.name) if node else "default"
   ```

3. **Add a CI check** that catches Variant-inference warnings in GDScript to prevent regressions.

4. **When element type of `Array` is known, use typed arrays** to allow GDScript to infer element types:
   ```gdscript
   var hypotheses: Array[Hypothesis] = []  # ✅ h.position is Vector2, not Variant
   var hypotheses: Array = []              # ❌ h is Variant, h.position is Variant
   ```

5. **Consider committing `.godot/global_script_class_cache.cfg`** to source control as additional hardening against headless export `class_name` registration failures (per godotengine/godot#75684 and godotengine/godot#77508). Modify `.gitignore`:
   ```
   /.godot/**/*
   !/.godot/global_script_class_cache.cfg
   ```
   This ensures CI never starts with an empty class cache, regardless of whether the `--import` step completes successfully.

---

## References

- Issue #1125: Added sniper weapon type (ASVK) to enemy system
- Issue #1033: Machine gunner blind fire pattern (reference implementation)
- Issue #910: Suppressive fire component (pre-existing Variant inference bug)
- Issue #824: Enemy flashlight component (pre-existing Variant inference bug)
- Godot Issue #75684: Headless export doesn't generate global_script_class_cache.cfg properly
- Godot Issue #77508: Headless import fails with --quit or --quit-after 1 (exits before cache write)
- Godot Issue #83449: Exit code 1 after importing in headless mode with --quit
- Godot Issue #72989: Global script classes not recognized after cache regeneration
- Godot Issue #79153: Parser Error cascades when class registration fails
- firebelley/godot-export v7.0.0: Added --headless --import pre-step to regenerate class cache

## Attached Data

- `game_log_20260318_095818.txt` — User's game log showing enemy breaking (0 enemies registered)

---

## Part 3 — FPS Drop Bug (Second Follow-up Report)

### Symptom

After the enemy-breaking fix was merged (Part 2), the user reported very low FPS in-game — particularly in DocksLevel with 20 enemies present:

> "хорошо, но очень мало fps (так раньше не было)."
> ("good, but very low FPS — wasn't like this before.")
>
> Attached: `game_log_20260318_110712.txt`, `game_log_20260318_110901.txt`

### Observed FPS Data

From game logs (FPS drop logging enabled, threshold = 30 fps):

| Level | Enemy count | Measured FPS | Normal expected |
|-------|------------|--------------|-----------------|
| LabyrinthLevel | 5 | 60 (stable) | 60 |
| DocksLevel (first visit) | 20 | 25 fps initial drop | 60 |
| DocksLevel (after reload) | 20 + 25 stale listeners | 1–7 fps sustained | 60 |

### Root Cause Analysis

#### Problem 1: SoundPropagation listener accumulation

SoundPropagation is an **autoload singleton** that persists across scene changes. When DocksLevel is loaded multiple times (the game reloads the level after clearing it), enemies re-register as listeners. However, the old instances from the previous load **are not cleaned up** before the new registration because:

1. The `register_listener` check `not _listeners.has(listener)` compares **object identity** — new scene instances are new objects, so duplicates slip through
2. `_unregister_sound_listener()` is only called `_die()` — not on `_exit_tree()` / scene change
3. Stale instances accumulate: after 3 level loads = 5 + 25 + 45 listeners (evidence: `total: 45` in log)

**Evidence:** Line 977 of `game_log_20260318_110712.txt`:
```
[SoundPropagation] Cleaned up 25 invalid listeners
```
This appears on the **first gunshot after** a scene reload — the `filter()` cleanup only runs inside `emit_sound()`, not proactively.

**Impact:** `emit_sound()` iterates all listeners (including stale) on every gunshot. With 45 listeners, the first shot after a reload triggers a mass cleanup. More importantly, with 45 listeners notified of every sound, `on_sound_heard_with_intensity()` fires 45 times per shot — including expensive state machine checks.

**Fix:** Add `_exit_tree()` to `enemy.gd` that calls `_unregister_sound_listener()`, ensuring cleanup happens automatically on scene change.

#### Problem 2: PlayerPredictionComponent per-frame array operations (primary FPS cause)

`PlayerPredictionComponent.update_predictions(delta)` is called **every physics frame** (via `_update_memory(delta)` → `_prediction.process_frame(...)`) for every enemy with active predictions:

```gdscript
func update_predictions(delta: float) -> void:
    # ...
    # Expand positions based on time (player could have moved further)
    for h in hypotheses:       # ← loop
        if not h.checked:
            var shift_dir: Vector2 = ((h.position as Vector2) - last_known_position).normalized()
            if shift_dir.length_squared() > 0.01:
                var expansion := PLAYER_SPEED * delta * 0.4
                h.position += shift_dir * expansion

    # Remove dead hypotheses ← creates new Array every frame
    hypotheses = hypotheses.filter(func(h: Hypothesis) -> bool: return h.probability > MIN_HYPOTHESIS_PROBABILITY)
    # ...
```

**With 20 enemies × 10 hypotheses × 60fps = 12,000 iterations/second** just for the position expansion loop, plus:
- `hypotheses.filter()` — allocates a new Array every frame (GDScript garbage pressure)
- The decay loop iterates all hypotheses again

Additionally, `update_observations()` calls `_classify_observation()` which calls `_update_style_classification()` every **3 frames** from the start (threshold = `STYLE_OBSERVATION_THRESHOLD = 3`), then on every subsequent frame — meaning every frame once enough data is collected.

**Timeline correlation:** FPS drops become sustained (5 fps) immediately after DocksLevel loads with 20 enemies. The drops are periodic (~every 1 second), suggesting the GC pressure from `filter()` allocations causes periodic pauses.

**Fix:** Throttle `update_predictions` to run every `N` frames (e.g., every 3 physics frames = 20 fps precision), since prediction positions don't need millisecond accuracy. Also replace `filter()` with an in-place removal to reduce GC pressure.

#### Problem 3: Vision raycasts at 20-enemy scale (secondary)

The existing vision stagger (`VISION_CHECK_INTERVAL = 6`) means 20 enemies × 1 raycast / 6 frames = ~3.3 raycasts per frame. With multi-point visibility checks (using `_get_player_check_points`), this could be 3–5 raycasts per frame, which compounds the prediction overhead.

### Fix Applied

**Fix 1 (SoundPropagation listener leak):** Add `_exit_tree()` to `enemy.gd`:
```gdscript
func _exit_tree() -> void:
    _unregister_sound_listener()
```

**Fix 2 (Prediction per-frame overhead):** Throttle `update_predictions` to every 3 physics frames:
```gdscript
# In PlayerPredictionComponent
var _update_frame_counter: int = 0
const UPDATE_INTERVAL: int = 3  ## Update predictions every N physics frames (~20fps precision)

func update_predictions(delta: float) -> void:
    if not has_predictions:
        return
    _update_frame_counter += 1
    if (_update_frame_counter % UPDATE_INTERVAL) != 0:
        hypothesis_age += delta  # Still track age on skipped frames
        return
    # ... rest of update (scaled delta = delta * UPDATE_INTERVAL)
```

### References

- `game_log_20260318_110712.txt` — FPS drops in DocksLevel (20 enemies)
- `game_log_20260318_110901.txt` — FPS drops in DocksLevel (second session, invincibility enabled)
- Issue #969: Previous throttling work for sound propagation (CASING_KICK throttle)
- Issue #883: Vision raycast stagger (VISION_CHECK_INTERVAL = 6)

---

## Attached Data

- `game_log_20260318_095818.txt` — User's game log showing enemy breaking (0 enemies registered)
- `game_log_20260318_110712.txt` — User's game log showing FPS drops with 20 enemies
- `game_log_20260318_110901.txt` — User's game log showing FPS drops (invincibility enabled)
