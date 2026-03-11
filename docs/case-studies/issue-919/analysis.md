# Case Study: Issue #919 — Aggression Gas Grenade Bug (Aggression Propagation)

## Issue Summary

**Title**: fix газовая граната (fix aggression gas grenade)

**Reporter**: Jhon-Crow

**Description (Russian)**: "сейчас агрессия передаётся врагу, которого атакует агрессивный враг. но агрессивный враг просто должен восприниматься другими врагами как игрок."

**Translation**: "Currently, aggression is passed/transferred to the enemy that an aggressive enemy attacks. But an aggressive enemy should simply be perceived by other enemies as the player."

**Attached logs**:
- `game_log_20260301_010737.txt` — 1493 lines (old build, bug present)
- `game_log_20260301_010813.txt` — 6284 lines (old build, bug present)
- `game_log_20260301_031619.txt` — 15154 lines (new build, added via PR comment)

---

## Timeline / Sequence of Events (From Logs)

### Log 2 (game_log_20260301_010813.txt) — Primary Evidence of Bug

1. **01:08:13** — Game starts, `AggressionGasGrenade` loaded, grenade type set to `Aggression Gas`
2. **01:08:14** — BuildingLevel loaded with 10 enemies: Enemy1-Enemy4, Grenadier, Enemy6-Enemy10
3. **01:08:17** — Player throws Aggression Gas grenade (GrenadeTimer initialized)
4. **01:08:21** — Gas released at `(608.955, 642.788)`, radius=300, duration=20s
   - `AggressionCloud` spawned
5. **01:08:22** — `Enemy2` enters gas cloud area → **AGGRESSIVE** state logged: `[Enemy2] [#675] AGGRESSIVE`
   - Enemy2 starts `Moving to Enemy1 (no LOS)` — seeking to attack Enemy1
6. **01:08:24** — More enemies enter gas cloud:
   - `Enemy4` → **AGGRESSIVE**
   - `Enemy3` → **AGGRESSIVE**
7. **01:08:24** — **BUG TRIGGERED**: `Enemy1` logs `[#675] Retaliating against Enemy2`
   - Enemy1 was NOT in the gas cloud but was shot by aggressive Enemy2
   - Enemy1 then starts `Moving to Enemy4 (no LOS)`, `Moving to Enemy7 (no LOS)`, `Moving to Enemy10 (no LOS)` — randomly targeting non-aggressive enemies
8. **01:08:25** — Enemy1 continues targeting arbitrary enemies: Enemy7, Enemy10
9. **01:08:36** — Gas cloud stops emitting (dissipating phase starts)
10. **01:08:37** — `Enemy1` logs `[#675] Aggression expired` — Enemy1's aggression ends
11. **01:08:39** — Enemy1 becomes **AGGRESSIVE** again (re-enters cloud or refreshed)

### Log 3 (game_log_20260301_031619.txt) — After First Fix (PR Feedback)

After the initial fix (removing `check_retaliation`), the owner reported (2026-03-01):
> "теперь враги не атакуют агрессивного врага" — "now enemies do not attack the aggressive enemy"

The log confirms: multiple enemies (Enemy2, Enemy3, Enemy4, Enemy1) become **AGGRESSIVE** via gas cloud and attack each other, but non-aggressive enemies (Enemy7, Enemy8, Enemy9, Enemy10) do NOT engage aggressive enemies at all. They simply ignore them.

---

## Root Cause Analysis

### Bug 1: Aggression Propagation via `check_retaliation` (Fixed in First Commit)

**File**: `scripts/components/aggression_component.gd`

The removed functions:

```gdscript
func check_retaliation(hit_direction: Vector2) -> void:
    # ...finds aggressive enemy in hit direction...
    if best: on_hit_by_aggressive_enemy(best)

func on_hit_by_aggressive_enemy(attacker: Node2D) -> void:
    _is_aggressive = true; _target = attacker   # ← ROOT CAUSE: propagates aggression
    aggression_changed.emit(true)
    sm.apply_aggression(_parent, 10.0)  # registers as aggressive in StatusEffectsManager
```

Called from `enemy.gd` whenever an enemy survived a non-lethal hit. Result: any enemy shot by an aggressive enemy became aggressive itself, creating a chain reaction.

### Bug 2: Non-Aggressive Enemies Not Engaging Aggressors (Fixed in Second Commit)

After removing `check_retaliation`, non-aggressive enemies no longer respond to aggressive enemies at all. The owner's intent: "aggressive enemies should be perceived as the player by other enemies" — non-aggressive enemies should fight back against aggressors.

**Root cause of Bug 2**: The enemy's normal AI only monitors `_player` as a target. There was no mechanism for a non-aggressive enemy to recognize and engage an aggressive enemy.

---

## Expected vs Actual Behavior

| Scenario | **Buggy (Original)** | **After First Fix** | **Correct (Final)** |
|---|---|---|---|
| Non-aggressive enemy hit by aggressive enemy | Becomes AGGRESSIVE itself (chain reaction) | Nothing — ignores it | Fights back against aggressor without becoming aggressive |
| Aggression flag | Spreads via hits | Does NOT spread ✓ | Does NOT spread ✓ |
| Non-gas enemies vs aggressive enemies | Randomly attack other non-aggressive enemies | Ignore aggressive enemies | Attack the aggressive enemy only (treat as player) |
| Gas-exposed enemies | Attack all enemies ✓ | Attack all enemies ✓ | Attack all enemies ✓ |

---

## Solution

### Fix 1: Remove Aggression Propagation (PR Commit 1)

Removed `check_retaliation()` and `on_hit_by_aggressive_enemy()` from `AggressionComponent`.
Removed the call `_aggression.check_retaliation(hit_direction)` from `enemy.gd`.

**Result**: Aggression no longer propagates via hits. Only gas-exposed enemies become aggressive.

### Fix 2: Non-Aggressive Enemies Engage Aggressors (PR Commit 2)

**Files modified**:
- `scripts/components/aggression_component.gd` — Added detection and combat logic
- `scripts/objects/enemy.gd` — Replaced 2-line check with unified 1-line tick

**New mechanism in `AggressionComponent`**:

```gdscript
var _hostile_aggressor: Node2D = null  # [#919] Detected aggressive enemy (not aggressive ourselves)

## Unified tick: handles both aggressive combat and non-aggressive aggressor detection.
func process_aggression_tick(delta, rotation_speed, shoot_cooldown, combat_move_speed) -> bool:
    if not _parent: return false
    if _is_aggressive:
        process_combat(...)  # Existing behavior: gas-exposed enemy attacks enemies
        return true
    # Non-aggressive: scan for visible aggressive enemies
    if _hostile_aggressor is invalid or no longer aggressive:
        _hostile_aggressor = _find_nearest_aggressive_enemy_with_los()
    if _hostile_aggressor == null: return false  # Normal AI handles this
    # Engage the aggressor as if it were the player (face, aim, shoot)
    ...shoot at _hostile_aggressor...
    return true  # AI override active

## [#919] Only finds enemies where is_aggressive() == true
func _find_nearest_aggressive_enemy_with_los() -> Node2D:
    ...iterates "enemies" group, skips non-aggressive...
```

**Change in `enemy.gd`** (`_process_ai_state`):

```gdscript
# OLD (2 lines):
if _aggression and _aggression.is_aggressive():  # [Issue #675] Aggression override
    _aggression.process_combat(delta, rotation_speed, shoot_cooldown, combat_move_speed); return

# NEW (1 line, -1 from total):
if _aggression and _aggression.process_aggression_tick(delta, rotation_speed, shoot_cooldown, combat_move_speed): return  # [Issue #675,#919]
```

**Why this works**:
- `process_aggression_tick()` is called before `_process_ai_state()` for every enemy every frame
- For gas-exposed (aggressive) enemies: identical behavior to before (calls `process_combat()`)
- For non-aggressive enemies: the method scans for nearby aggressive enemies with LOS
  - If one found: engages it directly (face, aim, shoot) and returns `true` (bypasses normal AI)
  - If none found: returns `false` (normal AI handles the enemy as usual)
- Non-aggressive enemies NEVER set `_is_aggressive = true` — aggression does not propagate

**Key properties of the fix**:
1. Non-aggressive enemies attack ONLY the aggressive enemy (not random other enemies)
2. They ONLY attack if they can see the aggressive enemy (line of sight required)
3. They remain non-aggressive throughout — no aggression propagation
4. When the aggressive enemy dies or aggression expires, `_hostile_aggressor` becomes invalid and the enemy returns to normal AI behavior
5. Line count maintained: enemy.gd reduced from 4998 to 4997 lines

---

## Files Involved

- `scripts/components/aggression_component.gd` — Primary fix location (both fixes)
- `scripts/objects/enemy.gd` — Call site update (1-line change)
- `tests/unit/test_aggression_component.gd` — Tests for both fixes
- `docs/case-studies/issue-919/` — This analysis + game logs
