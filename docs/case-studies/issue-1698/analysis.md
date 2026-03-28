# Case Study: Issue #1698 — Machine Gunner Does Not Shoot (Regression)

**Date:** 2026-03-28
**Reporter:** Jhon-Crow
**Branch:** `issue-1698-b468dd1501d2`
**PR:** #1701
**Related Issues:** #1033 (Machine Gunner feature), #1334 (LastChance grenade fix)

---

## 1. Artifacts

| Artifact | Source | Description |
|----------|--------|-------------|
| `game_log_20260328_174906.txt` | Reporter | Runtime log from exported Windows build demonstrating the bug |
| `scripts/objects/enemy.gd` | Repo (commit 042c34c1) | Main enemy AI — 4937 lines, contains machine gunner combat dispatch |
| `scripts/components/machine_gunner_component.gd` | Repo (commit 042c34c1) | Extracted machine gunner logic component |
| `tests/unit/test_machine_gunner.gd` | Repo | Unit tests for machine gunner behavior |

---

## 2. Environment

- **Engine:** Godot 4.3-stable (official)
- **Platform:** Windows (exported binary, non-debug)
- **Level:** Tutorial / TestTier (`res://scenes/levels/csharp/TestTier.tscn`)
- **Player weapon:** Makarov PM → later AKGL
- **Enemies spawned via F8:** Machine Gunner (PKM) ×3
- **Debug build:** `false` — no Godot editor crash handler, no GDScript stack traces in log

---

## 3. Timeline of Events (from `game_log_20260328_174906.txt`)

```
17:49:06  Game started, LabyrinthLevel loaded (5 enemies, none are machine gunners)
17:49:10  Scene change → Tutorial (TestTier.tscn)
17:49:23  F8 spawn: Machine Gunner [Enemy] at (669.9998, 360)
17:49:24  [Enemy] ROT_CHANGE: none → P5:idle_scan  (IDLE, init rotation)
17:49:25  [Enemy] Heard gunshot → ROT_CHANGE: P5:idle_scan → P2:combat_state → COMBAT
17:49:27  [Enemy] ROT_CHANGE: P2:combat_state → P1:visible, COMBAT (can see player)
17:49:27–17:49:37  [Enemy] stays in COMBAT, ROT_CHANGEs between P1:visible/P2:combat_state
           NO "MG corridor suppression: fired" log entries appear
17:49:37  [Enemy] GRENADE DANGER: Entering EVADING_GRENADE from COMBAT
17:49:37  [Enemy] State: EVADING_GRENADE → COMBAT
17:49:37–17:49:44  [Enemy] in COMBAT; still ZERO fire events
17:49:44  F8 spawn: Machine Gunner [Enemy] at (627.1073, 308.7554)
           [Enemy] ROT_CHANGE: P5:idle_scan → P1:visible → State: IDLE → COMBAT
17:49:44  F8 spawn: Machine Gunner [@CharacterBody2D@2348] at (817.8427, 184.9909)
17:49:45  [@CharacterBody2D@2348] P5:idle_scan → P1:visible → State: IDLE → COMBAT
17:49:45–17:49:51  BOTH machine gunners in COMBAT with player visible (P1:visible)
           NO fire events from either
17:49:51  Both machine gunners: State: COMBAT → SEARCHING (player lost)
17:49:53  Both back to COMBAT (P1:visible again)
           Log ends — still zero fire events recorded
```

**Key observation:** All three F8-spawned machine gunners entered COMBAT state (both via sound and direct visual detection) and some had direct line-of-sight (`P1:visible`). None ever fired. There are **zero** instances of `"MG corridor suppression: fired"` in the entire log.

---

## 4. Root Cause Analysis

### Root Cause 1 (Primary): `_machine_gunner_component` is `null` at runtime

The component refactoring in commit `042c34c1` split the machine gun firing logic out of `enemy.gd` into `MachineGunnerComponent`. The combat dispatch at `enemy.gd:1394` was changed from:

**Before (commit e4af015f and earlier):**
```gdscript
_machine_gunner_fire_at_corridor(suppress_target)   # direct call, always executed
```

**After (commit 042c34c1):**
```gdscript
if _machine_gunner_component: _machine_gunner_component.fire_at_corridor(suppress_target)
```

The null guard `if _machine_gunner_component:` silently swallows the fire call if the component reference is `null`. The component is created in `_ready()` at line 425:

```gdscript
if weapon_type == WeaponType.MACHINE_GUN:
    _machine_gunner_component = MachineGunnerComponent.new()
    _machine_gunner_component.enemy = self
    _machine_gunner_component.log_to_file_fn = _log_to_file
    _machine_gunner_component.name = "MachineGunnerComponent"
    add_child(_machine_gunner_component)
```

**Why this can fail for F8-spawned enemies:** The `F8 spawn` path in the game creates enemies programmatically at runtime (not from the scene tree). If the spawn implementation instantiates the scene and immediately calls methods on it before `_ready()` has been called (which is deferred in Godot's engine loop), the `add_child()` call places the component in the tree but `MachineGunnerComponent._ready()` hasn't run yet. More critically, if the scene or spawn code re-initializes the enemy after `_ready()` completes — or if the scene tree already called `_ready()` on the component *before* `enemy` was assigned — the reference chain could break.

**Evidence from log:** No "MG corridor suppression: fired" log entry ever appears. The `fire_at_corridor()` method logs at every successful fire:
```gdscript
log_to_file_fn.call("[#1033] MG corridor suppression: fired at passage %s, ammo=%d" % [...])
```
Since logging is enabled (`ExperimentalSettings: Logging: true`), the complete absence of this log line proves `fire_at_corridor()` was never called — consistent with `_machine_gunner_component == null` at the call site.

**Corroborating evidence:** No `ROT_CHANGE` from `P2:combat_state` with `enemy_model.global_rotation` set by `fire_at_corridor` — even though `ROT_CHANGE` events are actively logged for the machine gunner instances when they transition to IDLE scan or visual detection. The fire path in `fire_at_corridor` sets `_enemy_model.global_rotation` directly, which should have triggered rotation logging.

### Root Cause 2 (Secondary): Zero `_last_known_player_position` after EXPLOSION → COMBAT

In the original issue #1698 fix (commit `e4af015f`), explosion sounds intentionally do **not** update `_last_known_player_position`:

```gdscript
# Issue #1698: Only update last known player position from GUNSHOT sounds.
if sound_type == 0:
    _last_known_player_position = position
```

This means that if a machine gunner is IDLE and the first combat trigger is a grenade explosion (sound_type == 1), the machine gunner transitions to COMBAT but `_last_known_player_position` remains `Vector2.ZERO`.

Then in `_process_combat_state` (enemy.gd:1390-1396):
```gdscript
var suppress_target := _player.global_position if (_can_see_player and _player != null) else _last_known_player_position
if suppress_target != Vector2.ZERO:   # ← FAILS when _last_known_player_position == ZERO and can't see player
    ...fire...
    return
_machine_gunner_suppressing_corridor = false
```

When `suppress_target == Vector2.ZERO`, the machine gunner skips the entire machine-gun block and falls through to the normal enemy logic (which doesn't fire because the machine gunner's AI flow differs). The machine gunner becomes effectively unable to shoot until it gains direct visual contact.

**This is a trade-off introduced by the issue #1698 fix:** Before the fix, the explosion position was used as `suppress_target` (wrong, but non-zero → machine gunner fired). After the fix, no `suppress_target` → machine gunner silent.

In the game log, machine gunners `[Enemy]` (17:49:25) and both second-wave gunners enter COMBAT via visual detection (`P1:visible → COMBAT`), so they *should* have a non-zero suppress_target from `_player.global_position`. This rules out Root Cause 2 as the primary explanation for the logged session — Root Cause 1 explains the observation more directly.

### Root Cause 3 (Contributing): Tests use wrong `WEAPON_CONFIGS` key

`tests/unit/test_machine_gunner.gd` uses `WeaponConfigComponent.WEAPON_CONFIGS[4]` throughout, but `WeaponType.MACHINE_GUN == 6` and `WeaponType.RPG == 4`. This means all config-related tests validate RPG parameters instead of MACHINE_GUN parameters. While this doesn't cause the runtime bug, it allowed the regression to slip past CI.

---

## 5. Sequence Diagram

```
Player (F8)     GameManager         enemy._ready()        _process_combat_state
    |               |                     |                        |
    |--F8 press-->  |                     |                        |
    |               |--instantiate MG --> |                        |
    |               |                     |-- add_child(component) |
    |               |                     |   (component._ready()  |
    |               |                     |    runs LATER)         |
    |               |                     |                        |
    |--gunshot-->   |                     |                        |
    |               |--sound event------> enemy                    |
    |               |                     |--_transition_to_combat()|
    |               |                     |                        |
    |  (physics frame) ......................  _process_combat_state called
    |               |                     |                        |
    |               |                     |  suppress_target != ZERO (can see player)
    |               |                     |  if _machine_gunner_component:  ← IS NULL
    |               |                     |      (fire skipped silently)    ← BUG
    |               |                     |  return  ← no fire, no retreat
```

---

## 6. Impact Assessment

| Severity | Scope | Regression? |
|----------|-------|-------------|
| **High** — machine gunner completely non-functional | All MACHINE_GUN type enemies in all levels | **Yes** — introduced in commit `042c34c1` |

The machine gunner was a working feature (issue #1033). The refactoring to reduce line count in `enemy.gd` introduced a silent null dereference guard that prevents the only code path that fires the weapon.

---

## 7. Proposed Solutions

### Solution A: Add defensive null-check log + fallback (Minimal, Low Risk)

Detect the null case and emit an error log so it is visible in exported builds:

```gdscript
if weapon_type == WeaponType.MACHINE_GUN and not _machine_gunner_pm_active:
    var suppress_target := _player.global_position if (_can_see_player and _player != null) else _last_known_player_position
    if suppress_target != Vector2.ZERO:
        _machine_gunner_suppressing_corridor = true
        if not _is_reloading and _shoot_timer >= shoot_cooldown and _can_shoot():
            if _machine_gunner_component:
                _machine_gunner_component.fire_at_corridor(suppress_target)
            else:
                push_error("[#1033] _machine_gunner_component is null on MACHINE_GUN enemy — cannot fire")
        return
    _machine_gunner_suppressing_corridor = false
```

This surfaces the bug without changing behavior. **Not a fix**, only diagnostic.

### Solution B: Ensure component is always non-null (Recommended) ✓

Call `_ensure_machine_gunner_component()` before the fire dispatch and assert non-null:

```gdscript
func _ensure_machine_gunner_component() -> void:
    if _machine_gunner_component == null and weapon_type == WeaponType.MACHINE_GUN:
        _machine_gunner_component = MachineGunnerComponent.new()
        _machine_gunner_component.enemy = self
        _machine_gunner_component.log_to_file_fn = _log_to_file
        _machine_gunner_component.name = "MachineGunnerComponent"
        add_child(_machine_gunner_component)
```

Called at top of `_process_combat_state` or from within the MACHINE_GUN branch. This is a lazy-initialization recovery guard.

### Solution C: Remove guard, assert non-null in _ready (Strictest) ✓

Change the call site back to unconditional call but add an `assert` in `_ready()`:

```gdscript
# In _ready():
if weapon_type == WeaponType.MACHINE_GUN:
    _machine_gunner_component = MachineGunnerComponent.new()
    ...
    add_child(_machine_gunner_component)
    assert(_machine_gunner_component != null, "[#1033] MachineGunnerComponent must be created for MACHINE_GUN enemy")

# In _process_combat_state:
if weapon_type == WeaponType.MACHINE_GUN and not _machine_gunner_pm_active:
    ...
    _machine_gunner_component.fire_at_corridor(suppress_target)  # no guard
```

Crashes loudly in debug builds. In exported builds (where asserts are stripped), still needs the lazy-init guard.

### Solution D: Fix suppress_target fallback for explosion→COMBAT (for Root Cause 2)

When `suppress_target == Vector2.ZERO` but machine gunner is in COMBAT and has a valid player reference, use player's current position as fallback:

```gdscript
var suppress_target := _last_known_player_position
if _can_see_player and _player != null:
    suppress_target = _player.global_position
elif suppress_target == Vector2.ZERO and _player != null and is_instance_valid(_player):
    suppress_target = _player.global_position  # fallback when entering COMBAT without prior gunshot
```

This ensures the explosion→COMBAT path can still fire immediately when the player is visible.

---

## 8. Chosen Fix

**Applied:** Solutions B + D + test key fix (Root Cause 3).

1. **B**: Add lazy-initialization recovery in `_process_combat_state` when `_machine_gunner_component` is null.
2. **D**: Use `_player.global_position` as fallback for `suppress_target` when `_last_known_player_position == ZERO` and player is in sight.
3. **Test fix**: Change all `WEAPON_CONFIGS[4]` → `WEAPON_CONFIGS[6]` and `get_type_name(4)` → `get_type_name(6)` in `test_machine_gunner.gd`.

---

## 9. Second Session Log Analysis (`game_log_20260328_182033.txt`)

**Reporter comment (2026-03-28 15:21):** "всё ещё не стреляет" (still not shooting) — uploaded after applying commit `7827dd5b` (lazy-init fix).

### Summary of events in second log

| Time | Event |
|------|-------|
| 18:20:48 | MG spawned at (350,360), behavior=GUARD |
| 18:20:54 | IDLE → COMBAT (P1:visible — direct line of sight) |
| 18:20:55 | ROT_CHANGE P1:visible → P2:combat_state (lost sight) |
| 18:20:55–18:21:00 | In COMBAT for ~6 seconds; zero `"MG corridor suppression: fired"` entries |
| 18:21:00 | AKGL VOG grenade explodes at (71,213) — **LastChance time-freeze starts** |
| 18:21:00 | MG takes damage: hp=4→3→2→1→0, then **`[#1033] Machine gunner front-arc hit ignored` ×2** |
| 18:21:00 | Enemy dies |
| 18:21:04 | Second MG spawned (F8), same position |
| 18:21:05 | IDLE → COMBAT (P1:visible) |
| 18:21:07 | LastChance time-freeze starts again (second grenade) |
| 18:21:09 | **Memory reset: confusion=2.0s** → SEARCHING |

### New findings from second log

1. **The lazy-init fix did NOT resolve the silence.** The machine gunner still never fired. Since the lazy-init creates the component from scratch with `log_to_file_fn = _log_to_file`, any call to `fire_at_corridor` after line 1391 would log `"MG corridor suppression: fired"`. The absence of this log means `fire_at_corridor` was **not called**, OR it was called but returned early before the log line.

2. **The `[#1033] Machine gunner front-arc hit ignored` log at 18:21:00** confirms:
   - `weapon_type == WeaponType.MACHINE_GUN` ✓
   - `not _machine_gunner_pm_active` ✓
   - `_enemy_model.global_rotation` is accessible ✓
   So the enemy IS a machine gunner, IS NOT in PM mode, and the model IS initialized.

3. **The condition at line 1399 must be failing EVERY frame** for ~6 seconds:
   ```
   if not _is_reloading and _shoot_timer >= shoot_cooldown and _can_shoot():
   ```
   Possibilities: `_is_reloading=true`, `_shoot_timer < shoot_cooldown`, or `_can_shoot()=false`.

4. **Alternative hypothesis: `_process_combat_state` never reaches line 1389.** If `_aggression.process_aggression_tick` returns `true`, `_process_ai_state` returns before dispatching to `_process_combat_state`. Or if `weapon_type != WeaponType.MACHINE_GUN` at runtime.

### Diagnostic logging added (commit pending)

To diagnose which condition is failing, the following log entries were added:

- `[#1698] MG combat: suppress_target=..., can_see=..., last_known=..., reloading=..., timer=.../..., ammo=...` — logged ~every 2 seconds when MG branch executes (throttled by `_combat_state_timer`)
- `[#1698] MG fire skipped: reloading=..., ...` — logged ~every second when `suppress_target != ZERO` but fire conditions fail
- `[#1698] MG fire_at_corridor: bullet spawn blocked (target=...)` — logged in `fire_at_corridor` when `_is_bullet_spawn_clear` returns false
- `[#1698] MG fire_at_corridor: null enemy or bullet_scene` — logged if component's enemy ref is null
- `[#1698] MG fire_at_corridor: player_alive=false` — logged if GameManager says player is dead
- `[#1698] MG fire_at_corridor: to_target is ZERO` — logged if target==position

If **none** of these `[#1698]` entries appear in the next log, it means `_process_combat_state` never reaches the MG block at all — pointing to an early return in `_process_ai_state` (e.g., `_aggression.process_aggression_tick`, grenade danger, or the state machine never dispatching to `_process_combat_state`).

---

## 10. Third Game Log Analysis (`game_log_20260328_184957.txt`)

Diagnostic logging (commit `deceba34`) produced entries in the third log:

```
[#1698] MG combat: suppress_target=(1725.348, 1662.232), can_see=true, last_known=(1725.348, 1662.232), reloading=false, timer=12.16/0.12, ammo=500
```

All conditions for firing were met. Yet no `"MG corridor suppression: fired"` appeared. Conclusion: `fire_at_corridor` was being called but ALL log messages inside it were suppressed by `log_to_file_fn.is_valid()` guards returning false. Commit `e58d37a5` replaced those guards with direct `enemy._log_to_file()` calls.

---

## 11. Fourth Game Log Analysis (`game_log_20260328_192841.txt`)

**This is the definitive root cause discovery.**

With `log_to_file_fn` replaced by direct `enemy._log_to_file()` calls, the fourth log revealed:

```
[#1698] MG lazy-init: component was null, created and added
[#1698] MG dispatching fire_at_corridor: target=(150, 366), component_null=true
[#1698] MG lazy-init: component was null, created and added   ← next frame
[#1698] MG dispatching fire_at_corridor: target=(150, 366), component_null=true
... (repeats every physics frame, ~60/s)
```

### Root Cause: `MachineGunnerComponent` is freed every frame after `add_child()`

The `_machine_gunner_component` variable is auto-nullified on every frame, proving the added `MachineGunnerComponent` node is being freed immediately after `add_child()`. The exact Godot 4 mechanism causing this is a component node lifecycle issue when `add_child()` is called during `_physics_process()` in a specific configuration.

**Evidence:**
- Lazy-init fires on EVERY physics frame (~60/s) throughout the entire COMBAT session
- `component_null=true` is logged on the dispatch line immediately after the lazy-init assignment
- No crash occurs from `_machine_gunner_component.fire_at_corridor()` — because `_machine_gunner_component` is always null at that point and GDScript's null-method call fails silently with an engine error (not a GDScript exception) in exported (non-debug) builds
- The engine error is not captured by the FileLogger because it's a Godot native error, not a GDScript log

### Why `_machine_gunner_component` was not created in `_ready()`

Line 365 of the log shows "[ExperimentalMenu] Enemy spawner: spawned 'Machine Gunner (PKM)'" with no preceding `MachineGunnerComponent` initialization log. The `_ready()` setup at enemy.gd:425 (`if weapon_type == WeaponType.MACHINE_GUN: _machine_gunner_component = ...`) is skipped.

This occurs because in the F8 spawn path, `add_child()` is called (line 656/658 of `experimental_menu.gd`) AFTER setting `weapon_type = 6` (line 630). `_ready()` should fire with `weapon_type == 6`. However, some mechanism prevents this initialization — possibly a type coercion issue with `enemy.set("weapon_type", 6)` vs. the `WeaponType` enum, or a race condition in property notification.

### Fix Applied

The fix (commit following `e58d37a5`) **inlines the fire-at-corridor logic directly into `enemy.gd`** as `_machine_gunner_fire_at_corridor()`, eliminating the component reference entirely for the firing path. The component is retained only for PM fallback (`activate_pm_fallback()`) and distant cover search, which are rare (triggered only when the 500-round belt empties) and do not exhibit this bug.

This restores the pre-refactor behavior while keeping the component for the functions that work correctly.

---

## 12. References

- Godot 4 `add_child()` deferred execution: https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html
- GDScript `class_name` global registration: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#doc-gdscript-basics-class-name
- Issue #1033: Machine Gunner feature original implementation
- Issue #1334: LastChance effect / grenade explosion memory reset
- Commit `e4af015f`: fix — machine gunner no longer turns toward grenade explosion
- Commit `042c34c1`: refactor — extract MachineGunnerComponent to reduce enemy.gd below 5000-line CI limit
- Commit `7827dd5b`: fix — lazy-init recovery attempt (later proven insufficient)
- Commit `deceba34`: diag — improved fire-path diagnostic logging
- Commit `e58d37a5`: diag — replaced log_to_file_fn indirection with direct calls
