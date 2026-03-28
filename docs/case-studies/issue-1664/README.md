# Case Study: Issue #1664 — Fix drone operator dodges (уворот дроновода)

## Summary

The drone operator enemy has a broken evasion mechanic in ACTIVE phase.
The fix requested: in ACTIVE phase the drone operator should behave **exactly like the teleport enemy** —
teleport to cover when under fire, teleport on first bullet hit, teleport when flanking, etc.

Owner feedback (2026-03-28): **"не телепортируется"** ("doesn't teleport") — the drone operator
enters ACTIVE phase, picks up a silenced pistol, and fights the player normally, but **never teleports**.
A game log was provided to diagnose the problem.

---

## Game Log Analysis (`game_log_20260328_082927.txt`)

The log (collected 2026-03-28 08:29:27–08:30:50, Windows, Godot 4.3-stable) records two encounters:

### Encounter 1 (08:30:28)

```
[08:30:28] [DroneOperator] Drone destroyed! Transitioning to ACTIVE
[08:30:28] [DroneOperator] Teleport component set up (teleport evasion, Issue #1664)
[08:30:28] [DroneOperator] Phase: ACTIVE (silenced pistol + laser, teleport evasion)
[08:30:28] [EnemyDroneOperator] ROT_CHANGE: ... state=COMBAT
[08:30:29] [EnemyDroneOperator] State: COMBAT -> PURSUING
[08:30:30] [PenultimateHit] Player damaged: 1.0 damage, current health: 3.0
[08:30:30] [PenultimateHit] Player damaged: 1.0 damage, current health: 2.0
...
```

**Observation**: The teleport component is set up, but **there is no `[Teleporter]` log entry**
for the entire ACTIVE phase. The drone operator simply fires at the player and kills them without
ever teleporting. This is consistent with `is_ready()` returning `false` on every call.

### Encounter 2 (08:30:37) — same outcome

```
[08:30:37] [DroneOperator] Teleport component set up (teleport evasion, Issue #1664)
[08:30:37] [DroneOperator] Phase: ACTIVE (silenced pistol + laser, teleport evasion)
... (combat, shooting, player dies — still no [Teleporter] log)
```

**Conclusion**: The teleport component is created and attached, but `is_ready()` always returns
`false`, so every call to `try_teleport()` / `try_damage_teleport()` silently fails.

---

## Root Cause — Iteration 1: Wrong add_child target

### The original bug (pre-PR #1676)

The ACTIVE phase used `MacheteComponent` (lateral dodge) instead of `EnemyTeleportComponent`.
That was the reported bug in the issue: "dodge doesn't work."

### The introduced bug (in PR #1676, session 1)

After replacing `MacheteComponent` with `EnemyTeleportComponent`, the component was added as a
child of the `DroneOperatorComponent` (a plain `Node2D`/`Node`):

```gdscript
# drone_operator_component.gd  ← BUG
_teleport_component = EnemyTeleportComponent.new()
add_child(_teleport_component)  # ← parent is DroneOperatorComponent (Node), NOT enemy
```

`EnemyTeleportComponent._ready()` resolves its enemy reference by:

```gdscript
func _ready() -> void:
    _parent = get_parent() as CharacterBody2D   # cast fails!
    _ready_flag = _parent != null               # → false
```

Because `DroneOperatorComponent` is a `Node` (not `CharacterBody2D`), the cast returns `null`.
`_ready_flag` is set to `false`, and `is_ready()` returns `false` forever:

```gdscript
func is_ready() -> bool:
    return _ready_flag and _cooldown_timer <= 0.0  # always false
```

Every call in `enemy.gd` to `_drone_operator.is_teleport_ready()` / `try_teleport()` /
`try_damage_teleport()` silently does nothing. The drone operator fights normally with no evasion.

### Contrast with real teleporter enemy

`enemy.gd` (for `is_teleporter == true`) adds the component directly to the enemy node:

```gdscript
if is_teleporter:
    _teleport_component = EnemyTeleportComponent.new()
    add_child(_teleport_component)  # ← self = CharacterBody2D ✓
```

Here `get_parent() as CharacterBody2D` succeeds, `_ready_flag = true`, and teleport works.

---

## Fix

In `drone_operator_component.gd`, add the `EnemyTeleportComponent` to `_parent`
(the enemy `CharacterBody2D`) instead of `self`:

```gdscript
func _setup_teleport_component() -> void:
    if _teleport_component != null:
        return
    _teleport_component = EnemyTeleportComponent.new()
    _teleport_component.name = "TeleportComponent"
    # Must be added to _parent (CharacterBody2D), not self (Node).
    if _parent != null:
        _parent.add_child(_teleport_component)
    else:
        add_child(_teleport_component)
    FileLogger.info("[DroneOperator] Teleport component set up (teleport evasion, Issue #1664)")
```

This ensures `EnemyTeleportComponent._ready()` sees a `CharacterBody2D` parent, so `_ready_flag`
is set to `true` and all teleport calls succeed.

---

## Timeline of Events

| Time | Event |
|------|-------|
| Issue #1664 opened | Owner reports drone operator dodge is broken in ACTIVE phase |
| PR #1676 session 1 | Replaced `MacheteComponent` with `EnemyTeleportComponent`; component added to wrong parent → `_ready_flag = false` |
| 2026-03-28 08:30 | Owner tests: drone operator enters ACTIVE, teleport never fires, player killed |
| 2026-03-28 comment | Owner posts game log: "не телепортируется" |
| 2026-03-28 PR #1676 session 2 | Log analysis finds root cause; fix: add component to `_parent` |

---

## Files Changed

- `scripts/components/drone_operator_component.gd` — add teleport component to `_parent`
- `tests/unit/test_drone_operator.gd` — add test that checks `_ready_flag` via `is_teleport_ready()` after proper parent setup
- `docs/case-studies/issue-1664/game_log_20260328_082927.txt` — game log from owner's report

## Related Issues / PRs

- Issue #752: Original teleporter enemy implementation (`EnemyTeleportComponent`)
- Issue #1355: Damage-triggered teleport on first bullet
- Issue #1397: Drone operator initial implementation
- PR #1676: This fix
