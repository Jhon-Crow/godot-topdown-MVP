# Case Study: Issue #919 — Aggression Gas Grenade Bug (Aggression Propagation)

## Issue Summary

**Title**: fix газовая граната (fix aggression gas grenade)

**Reporter**: Jhon-Crow

**Description (Russian)**: "сейчас агрессия передаётся врагу, которого атакует агрессивный враг. но агрессивный враг просто должен восприниматься другими врагами как игрок."

**Translation**: "Currently, aggression is passed/transferred to the enemy that an aggressive enemy attacks. But an aggressive enemy should simply be perceived by other enemies as the player."

**Attached logs**:
- `game_log_20260301_010737.txt` — 1493 lines
- `game_log_20260301_010813.txt` — 6284 lines

---

## Timeline / Sequence of Events (From Logs)

### Log 2 (game_log_20260301_010813.txt) — Primary Evidence

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

### Summary of the Bug Pattern

```
Player throws AggressionGasGrenade
       ↓
Enemy2 enters cloud → becomes AGGRESSIVE
       ↓
Enemy2 shoots Enemy1 (not in cloud, not intended to be aggressive)
       ↓
Enemy1 is hit → check_retaliation() triggers → on_hit_by_aggressive_enemy(Enemy2)
       ↓
Enemy1 is set AGGRESSIVE (_is_aggressive = true, target = Enemy2)
       ↓  ← BUG: aggression propagates!
Enemy1 now attacks Enemy7, Enemy10 (other non-gas enemies!)
       ↓
StatusEffectsManager.apply_aggression(Enemy1, 10.0) called — registered as aggression effect
```

---

## Root Cause Analysis

### File: `scripts/components/aggression_component.gd`

**Function: `on_hit_by_aggressive_enemy` (line 84-90)**

```gdscript
func on_hit_by_aggressive_enemy(attacker: Node2D) -> void:
    if not is_instance_valid(attacker) or not _parent or _parent.get("_is_alive") == false: return
    if not _is_aggressive: _log("Retaliating against %s" % attacker.name)
    _is_aggressive = true; _target = attacker   # ← ROOT CAUSE
    aggression_changed.emit(true)               # ← propagates through StatusEffectsManager
    var sm: Node = _parent.get_node_or_null("/root/StatusEffectsManager")
    if sm and sm.has_method("apply_aggression"): sm.apply_aggression(_parent, 10.0)  # ← further registers as aggressive
```

This function sets `_is_aggressive = true` on the victim enemy, making it:
1. Actively search for ANY enemy to attack (via `_find_nearest_enemy_target_with_los()` and `_find_nearest_enemy_any()`)
2. Registered with `StatusEffectsManager` as aggressive (tracked as an aggression effect)
3. Perceived by OTHER non-aggressive enemies as an aggressor (if they get hit, they retaliate too)

**Function: `check_retaliation` (line 72-82)**

```gdscript
func check_retaliation(hit_direction: Vector2) -> void:
    if not _parent: return
    var adir := -hit_direction.normalized(); var best: Node2D = null; var bs := -INF
    for e in _parent.get_tree().get_nodes_in_group("enemies"):
        if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
        if not (e.has_method("is_aggressive") and e.is_aggressive()) or e.get("_is_alive") == false: continue
        var dm := adir.dot((e.global_position - _parent.global_position).normalized())
        if dm > 0.5:
            var s := dm - (_parent.global_position.distance_to(e.global_position) / 1000.0)
            if s > bs: bs = s; best = e
    if best: on_hit_by_aggressive_enemy(best)  # ← triggers aggression propagation
```

Called from `enemy.gd` line 4176 whenever an enemy survives a hit:
```gdscript
if _aggression: _aggression.check_retaliation(hit_direction)  # [Issue #675] retaliate
```

---

## Expected vs Actual Behavior

| | **Actual (Buggy)** | **Expected (per Issue #919)** |
|---|---|---|
| Enemy hit by aggressive enemy | Becomes AGGRESSIVE itself (targets all enemies) | Enters combat against the aggressor only (treats aggressor as "the player") |
| Aggression spread | Cascades to hit enemies | Does NOT spread via hits |
| Non-gas enemies | Can become aggressive through chain | Only gas-exposed enemies are aggressive |

---

## Proposed Solutions

### Solution A: Remove `check_retaliation` (Simplest)

Remove the call to `check_retaliation` in `enemy.gd` line 4176. This stops aggression from propagating entirely.

**Pros**: Simple, precise fix
**Cons**: Non-aggressive enemies hit by aggressive enemies won't defend themselves (they'll just stand there getting shot)

### Solution B: Make victim enter combat vs attacker WITHOUT becoming aggressive (Recommended)

The victim should perceive the aggressive attacker as "the player" — meaning it should fight back against the specific aggressive enemy — but NOT set `_is_aggressive = true` and NOT use the aggression system.

**Implementation**: Remove the `_is_aggressive = true` and `aggression_changed.emit(true)` calls from `on_hit_by_aggressive_enemy`. Instead, make the enemy retarget the attacker using normal combat mechanics (treating the aggressor as a pseudo-player target).

**Pros**: Correct behavior — enemies fight back but don't spread aggression
**Cons**: Requires more architectural changes to support "target override" in combat AI

### Solution C: Track "aggressor targets" separately from the aggression flag

Add a new `_aggressor_target: Node2D` variable that is distinct from `_is_aggressive`. When hit by an aggressive enemy, the victim enters combat against this specific target but the `_is_aggressive` flag remains false (and thus won't propagate further).

**Pros**: Clean solution, maintains the aggressive/non-aggressive distinction
**Cons**: Requires changes to the process_combat logic

---

## Chosen Fix: Simplest Correct Fix

Based on the issue description, the correct behavior is that aggressive enemies should be "perceived as the player" by other enemies. This means other enemies should fight back against the aggressive attacker.

The simplest correct fix: **Modify `on_hit_by_aggressive_enemy` to NOT set `_is_aggressive = true`**. Instead, just target the attacker directly (set `_target = attacker`) and transition to combat. The enemy fights back against the specific aggressor without becoming aggressive itself.

This requires:
1. In `aggression_component.gd`: `on_hit_by_aggressive_enemy` should NOT set `_is_aggressive = true` and should NOT call `apply_aggression`
2. The victim enemy needs a way to engage combat with the specific attacker without using the aggression system

However, the problem is: the victim needs a combat target that isn't the player. The simplest approach that fits the existing architecture:

**Remove `check_retaliation` entirely** and implement a simpler mechanism:
- When a non-aggressive enemy is hit by an aggressive attacker, just have it retarget the aggressor using the existing combat state (without the aggression flag)
- This can be done in `enemy.gd` by setting a temporary "threatened by" target

Or even simpler: just **remove `check_retaliation`** — non-aggressive enemies that get shot by aggressive enemies should simply have their normal reaction to being shot (become alert, pursue the threat direction), not become aggressive themselves.

**Final Decision**: Remove `check_retaliation` from `on_hit_with_bullet_info` and remove `on_hit_by_aggressive_enemy`. When a non-aggressive enemy is shot, it should use its normal enemy-detection logic (which won't target the aggressor since they're "in the enemies group", not "the player").

Wait — but then non-aggressive enemies can't fight back at all against aggressive enemies. The issue says they should perceive aggressive enemies AS the player.

The minimal correct fix: In `on_hit_by_aggressive_enemy`, do NOT set `_is_aggressive = true`. Instead, the fix in `check_retaliation` should make the victim enter COMBAT with the attacker (transition state), treating the attacker as a combat target, without the aggression propagation.

---

## Files Involved

- `scripts/components/aggression_component.gd` — Primary fix location
- `scripts/objects/enemy.gd` — May need adjustment for combat state targeting
- `tests/unit/test_aggression_component.gd` — Tests to update/add
