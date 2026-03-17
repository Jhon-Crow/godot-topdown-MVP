# Case Study: Teleporting Enemy Breaks All Enemies on All Maps (Issue #752)

## Overview

**Issue**: Add one teleporting enemy to the City map — enemy teleports ≤1 viewport per 10 seconds, uses cover and flanking teleport, has a blue backpack visual indicator.

**Reported failures**: Three separate game logs all showing `has_died_signal=false` / `0 enemies registered` on every map.

**Root cause**: Each implementation introduced a GDScript 4 parse error in `enemy.gd`. When `enemy.gd` fails to parse, *all* enemy instances fail to initialize — including their `died` signal — which is why every enemy on every map registered as broken.

---

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| 2026-03-11 | First PR attempt — adds TeleporterEnemy to City map, introduces semicolon-chained `@export` annotations |
| 2026-03-12 | Log `game_log_20260312_015055.txt`: 0 enemies registered on all maps |
| 2026-03-16 (attempt 2) | "Fix" splits the @export lines — but refactor commit `17a2c4d6` introduced new semicolon issues in teleport functions |
| 2026-03-16 (evening) | Log `game_log_20260316_223230.txt`: still 0 enemies on all maps |
| 2026-03-17 | Log `game_log_20260317_013124.txt`: still 0 enemies on all maps — user requests fresh start from `main` |
| 2026-03-17 | Third attempt: reset to `main`, implement using the `EnemyForceFieldComponent` pattern |
| 2026-03-17 | User confirms "it works now", requests: resolve conflict + remove progress bar + blue backpack |
| 2026-03-17 | Fourth session: merge main (adds ShieldIcon for force field), replace tiny 2×2 blue pixel with 16×20 backpack sprite |

---

## Root Cause Analysis

### GDScript 4 Parse Error Pattern

Each iteration introduced different but related parse errors in `enemy.gd`:

**Attempt 1** (`31b24c93`):
```gdscript
# BROKEN: semicolon-chained @export annotations
@export var is_teleporter: bool = false; @export var teleport_cooldown: float = 10.0; @export var teleport_max_distance: float = 0.0
```
In GDScript 4, each `@export` must be on its own line. This caused a parse error.

**Attempt 2** (`17a2c4d6`):
```gdscript
# BROKEN: semicolon-chained if statements with nested if
func try_teleport_to_cover() -> bool:
    if not _teleport or not _teleport.is_ready(): return false; if not _has_valid_cover: _find_cover_position(); return _has_valid_cover and _teleport.try_teleport(_cover_position)
```
The pattern `if condition: stmt; if condition2:` is invalid in GDScript 4. The second `if` after a semicolon is not a continuation.

**Why this broke all enemies, not just the teleporter:**
GDScript parses the entire file before executing any of it. A parse error anywhere in `enemy.gd` means zero enemy instances can load. This is why `has_signal("died")` returns `false` — the script never attaches to the node, so no signals are declared.

### Historical Pattern

This is the **3rd recurrence** of the same category of bug:
1. Issue #169: Similar batch-commit pattern introduced invalid GDScript syntax
2. Issue #328: CI line limit exceeded, causing indirect parse failures
3. Issue #752 (this): Semicolon-chained @export and nested if statements

### Why the Previous "Fix" Didn't Help

The second game log (`2026-03-16 22:32`) still showed the broken pattern. The fix commit (`5dca3bf1`) split the @export lines, but a separate refactor commit (`17a2c4d6`) introduced new invalid syntax in the teleport functions. The EXE in `враг с телепортом` folder was built from a broken state.

---

## Online Research Findings

1. **GDScript 4 statement rules**: Unlike Python, GDScript 4 does not allow arbitrary `if` statement chaining with semicolons. Semicolons can chain *simple statements* (assignments, returns, function calls) but NOT compound statements (`if`, `for`, `while`, `match`).

2. **Export annotation rules**: `@export` in Godot 4 must always be on its own line immediately before its variable declaration. It cannot be mixed with other statements on the same line.

3. **Parse error propagation**: In Godot 4, a script with a parse error fails entirely at the ClassDB level — no signals, no methods, no properties. Any node with that script attached becomes a plain `Node` with no custom behavior.

---

## Solution: Fresh Implementation Using EnemyForceFieldComponent Pattern

The fix follows the exact same pattern as PR #1042 (Force Field Enemy):

### 1. `scripts/components/enemy_teleport_component.gd` (new file)

A `Node`-based component class (not `RefCounted`, so it can have `_ready()`) that:
- Manages teleport cooldown via `COOLDOWN = 10.0` constant
- Limits range to 1 viewport diagonal (`VIEWPORT_FRACTION = 1.0`)
- Provides `is_ready()`, `update(delta)`, `try_teleport(target)` methods
- Has `add_backpack(model)` static method for the blue backpack visual indicator
- Spawns blue particle burst effects on teleport (origin + destination)

### 2. `scripts/objects/enemy.gd` (minimal changes)

```gdscript
# After is_grenadier:
@export var is_teleporter: bool = false  ## Whether this enemy can teleport (Issue #752).

# Variable declaration:
var _teleport_component: EnemyTeleportComponent = null

# In _ready() after _setup_machete_component():
if is_teleporter: _teleport_component = EnemyTeleportComponent.new(); ...

# In _physics_process():
if _teleport_component: _teleport_component.update(delta)

# In _process_ai_state():
if _teleport_component and _teleport_component.is_ready() and _under_fire and _current_state != AIState.IN_COVER:
    if not _has_valid_cover: _find_cover_position()
    if _has_valid_cover and _teleport_component.try_teleport(_cover_position): _transition_to_in_cover(); return
if _teleport_component and _teleport_component.is_ready() and not _can_see_player and _current_state == AIState.FLANKING:
    _teleport_component.try_teleport(_flank_target)
```

### 3. `scenes/levels/CityLevel.tscn`

Added `TeleporterEnemy` at position `(2400, 2800)` — center-city area:
```ini
[node name="TeleporterEnemy" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(2400, 2800)
behavior_mode = 1
destroy_on_death = true
enable_flanking = true
enable_cover = true
is_teleporter = true
```

The blue backpack sprite is added programmatically by `EnemyTeleportComponent.add_backpack()`.
The sprite (`assets/sprites/characters/enemy/teleporter_backpack.png`, 16×20 px) is a recognizable
blue backpack shape positioned on the enemy body — no progress bar or stripe above the enemy head.

---

## Prevention Recommendations

1. **Never chain `@export` on one line** — each annotation must be on its own line.
2. **Never chain `if` statements with semicolons** — use separate lines.
3. **Semicolons are safe only for**: assignments, simple function calls, `return`.
4. **Follow the component pattern from PR #1042**: new feature = new component file + one-line setup in `_ready()`.
5. **Test parse validity**: before committing, the CI architecture check validates line count. A parse-level check would catch these earlier.

---

## Game Logs

| Log | Date | Key Symptom |
|-----|------|-------------|
| `game_log_20260312_015055.txt` | 2026-03-12 01:50 | 0 enemies registered, all maps |
| `game_log_20260316_223230.txt` | 2026-03-16 22:32 | 0 enemies registered, all maps |
| `game_log_20260317_013124.txt` | 2026-03-17 01:31 | 0 enemies registered, TeleporterEnemy `has_died_signal=False` |
