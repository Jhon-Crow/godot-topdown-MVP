# Case Study: Issue #1694 — Teleport Regression After Machete Fix

## Overview

After restoring the machete enemy combat logic (broken in the #1664/#1667 merge), two regressions
were discovered and confirmed through two test sessions:

1. **Drone operator dashes toward player instead of teleporting to cover**
2. **Standard teleport enemy (`is_teleporter=true`) does not teleport at all**

**Log files**:
- `game_log_20260328_175647.txt` — First test: drone operator + teleport enemy broken
- `game_log_20260328_182740.txt` — Second test: confirms drone operator dashes, teleport enemy still broken

**Build**: Release (Debug build: false), Godot 4.3-stable
**Reported by**: Jhon-Crow (PR #1702 comments, 2026-03-28T14:59:30Z and 2026-03-28T15:31:13Z)

---

## Timeline of Events

### 1. Original `develop` branch
- `DroneOperatorComponent` had a **full dash system** (4 charges, 1.2s cooldown):
  - `should_dash_instead_of_suppress()`, `try_dash_from_threat()`, `try_dash()`, etc.
  - `enemy.gd._update_suppression()` called `should_dash_instead_of_suppress()` — drone operators
    DASH toward player instead of being suppressed.
- Standard teleport enemies: `_under_fire = true` → cover-teleport fired normally.

### 2. PRs #1664 and #1667 merged to `main` (2026-03-28)
- PR #1664 replaced the **drone operator dodge** (machete-style) with **teleport evasion**.
  - `DroneOperatorComponent` ACTIVE phase now uses `EnemyTeleportComponent` (same as teleport enemy).
  - Correctly removed the dodge velocity override from `_physics_process`.
- The call to `should_dash_instead_of_suppress()` in `_update_suppression()` was also removed.
- Issue #1664 added `_drone_operator.try_teleport()` inside `_process_combat_state()`.
- Standard teleporter enemies: unchanged, still use `_teleport_component` from `enemy._ready()`.

### 3. PR #1702 — Session 1: Machete Fix (2026-03-28T14:36)
- Commit `26bd6770` restored the missing machete COMBAT state block.
- **Regression introduced**: Also added back the drone operator dash suppression:
  ```gdscript
  # In _update_suppression():
  if _drone_operator and _drone_operator.should_dash_instead_of_suppress():
      _drone_operator.try_dash_from_threat(...)
  else: _under_fire = true; _suppression_timer = 0.0
  ```
- But `should_dash_instead_of_suppress()` and `try_dash_from_threat()` didn't exist in the
  upstream `DroneOperatorComponent`. In Godot 4 **release builds**, calling nonexistent methods
  silently returns `null` — so drone operators fell through to `else: _under_fire = true`,
  which allowed them to teleport (Issue #1664 path). Behavior was still correct.

### 4. PR #1702 — Session 2: Restore Dash System (2026-03-28T15:15)
- Commit `c9e82f8d` "restored the drone operator dash system from develop".
- Added all dash constants, variables, and methods to `DroneOperatorComponent`.
- Added `is_dashing()` velocity override to `_process_combat_state()`.
- **Effect**: Drone operators now DASH (toward player) instead of teleporting to cover.
  - Evidence: `game_log_20260328_182740.txt` line 1380-1381:
    ```
    [DroneOperator] Aggressive dash toward player: dir=(-1.00, 0.07)
    [DroneOperator] Dash activated! Dir: (-1.00, 0.07), charges left: 3/4
    ```
- This was WRONG: Issue #1664 intentionally replaced dash with teleport for main branch.

### 5. Standard Teleport Enemy — Broken in Both Tests
- `@CharacterBody2D@4021` (experimental spawner, game log 2, line 1365-1383):
  ```
  [#1311] Player bullet entered threat sphere
  Hit: dmg=1, hp=2/2->1/2
  State: COMBAT -> RETREATING   ← NO TELEPORT
  ```
- Railway Station `Platform_TeleporterRight1` (game log 2, line 4244-4259):
  ```
  [#1311] Player bullet entered threat sphere
  [#1311] Player bullet entered threat sphere
  State: COMBAT -> RETREATING   ← NO TELEPORT
  ```
- Zero `[Teleporter]` log messages in either game session.
- This indicates `EnemyTeleportComponent.is_ready()` returns `false` every time it is checked.

---

## Root Causes

### A) Drone Operator Dashes Instead of Teleporting

**Root cause**: Commit `c9e82f8d` added the full dash system from `develop` to
`DroneOperatorComponent`. This is the OLD behavior that was intentionally replaced by
teleport evasion in PR #1664 for the `main` branch.

**Fix**: Revert `drone_operator_component.gd` to the upstream/main version (PR #1676).
Remove `is_dashing()` velocity override from `_process_combat_state()` in `enemy.gd`.
Remove the `should_dash_instead_of_suppress()` call from `_update_suppression()`.

### B) Standard Teleport Enemy Does Not Teleport

**Root cause**: `EnemyTeleportComponent.is_ready()` returns `false`.

The component's `is_ready()` depends on `_ready_flag`, which is set in `_ready()`:
```gdscript
func _ready() -> void:
    _parent = get_parent() as CharacterBody2D
    _ready_flag = _parent != null
```

In Godot 4, when `add_child()` is called during a parent's `_ready()`, the newly added
child's `_ready()` is normally called synchronously (if the parent is already in the scene
tree). However, edge cases exist:

1. **Deferred `_ready()` during scene initialization**: When the enemy is loaded as part of
   a scene file (Railway Station level), all `_ready()` calls are propagated in bottom-up
   order. The enemy's `_ready()` calls `add_child(_teleport_component)`, and if the Godot 4
   scene tree hasn't fully propagated `_ready()` to this subtree yet, the component's
   `_ready()` might be deferred, leaving `_ready_flag = false` on the first physics frame.

2. **Scene instantiation order**: When enemies are spawned via the experimental menu, the
   `is_teleporter` flag is set before `add_child(enemy)`, but there may be a single-frame
   window where the component's `_ready()` has not yet fired.

**Evidence**: Zero `[Teleporter] Component initialized` messages in both game logs (because
the diagnostic log was not present in those builds). Zero `[Teleporter] Rejected teleport`
messages — meaning `try_teleport()` was never called, confirming `is_ready()` always returned
`false`.

**Fix**: Add lazy parent resolution to `is_ready()` so it works even if `_ready()` was
deferred. Also add diagnostic log to `_ready()` to confirm initialization state.

---

## Evidence from Game Logs

### game_log_20260328_175647.txt
- Drone operator initializes teleport component (Phase: ACTIVE, teleport evasion).
- BUT then it transitions to SUPPRESSED → SEEKING_COVER — never gets to COMBAT state.
- Teleport check is INSIDE `_process_combat_state` — never fires in non-COMBAT states.
- No `[Teleporter]` messages at all.

### game_log_20260328_182740.txt
- Line 1054-1057: Drone operator Phase ACTIVE initialized with teleport evasion.
- Line 1380-1381: Drone operator DASHES instead of teleporting:
  ```
  [DroneOperator] Aggressive dash toward player: dir=(-1.00, 0.07)
  [DroneOperator] Dash activated! Dir: (-1.00, 0.07), charges left: 3/4
  ```
- Line 1365-1383: Standard teleporter spawned via experimental menu — shot, hit, RETREATS
  to cover instead of teleporting. No `[Teleporter]` messages.
- Lines 4244-4289: Railway Station teleporters get bullets in sphere, transition COMBAT →
  RETREATING → IN_COVER without any teleport.
- Zero `[Teleporter]` messages in the entire log.

---

## Applied Fixes

### Fix 1: Drone Operator — Restore Teleport Behavior

**Files changed**:
- `scripts/components/drone_operator_component.gd`: Replaced with upstream/main version
  (from PR #1676). Removed all dash constants, variables, and methods. Kept teleport delegation.
- `scripts/objects/enemy.gd._update_suppression()`: Removed `should_dash_instead_of_suppress()`
  check. `_under_fire = true` is now set unconditionally (after delay and force-field check).
- `scripts/objects/enemy.gd._process_combat_state()`: Removed `is_dashing()` velocity override.

### Fix 2: Standard Teleport Enemy — Robust is_ready()

**File changed**: `scripts/components/enemy_teleport_component.gd`

Added:
1. Diagnostic log in `_ready()` to confirm initialization and identify parent issues.
2. Lazy parent resolution in `is_ready()` — if `_ready_flag` is still `false` but
   `_parent == null`, re-tries `get_parent() as CharacterBody2D`. This handles the
   case where `_ready()` was deferred (Godot 4 scene initialization edge case).

```gdscript
func _ready() -> void:
    _parent = get_parent() as CharacterBody2D
    _ready_flag = _parent != null
    if _ready_flag:
        FileLogger.info("[Teleporter] Component initialized on %s" % _parent.name)
    else:
        FileLogger.warn("[Teleporter] Component parent is not CharacterBody2D ...")

func is_ready() -> bool:
    if not _ready_flag and _parent == null:
        _parent = get_parent() as CharacterBody2D
        _ready_flag = _parent != null
    return _ready_flag and _cooldown_timer <= 0.0
```

---

## Online Research: Godot 4 _ready() Deferred Behavior

According to Godot 4 documentation and community reports:
- When `add_child()` is called on a node that is **already in the scene tree**, the new
  child's `_ready()` is called **synchronously** (not deferred).
- However, during **scene file loading** (PackedScene.instantiate() + adding to tree),
  `_ready()` propagation follows bottom-up order which can cause timing surprises with
  dynamically added sub-children.
- The `_ready()` notification is sent via `NOTIFICATION_READY` which is processed as
  part of the node's lifecycle, not deferred to the next frame in normal circumstances.
- However, if a node is added via `add_child()` during `_ready()` of a parent that itself
  is being added to the tree for the first time in that same frame, the child's `_ready()`
  may be processed in the same `_ready_propagate()` call — but the exact order depends
  on the scene tree implementation.

**Conclusion**: The lazy resolution in `is_ready()` is the safest approach and handles
all edge cases regardless of Godot 4 version-specific behaviors.
