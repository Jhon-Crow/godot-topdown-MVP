# Case Study: Issue #1805 — Гренадер не стреляет на карте Канализация

## Overview

**Issue:** Grenadier (гренадер) enemy on the Канализация (Sewer) map does not shoot.  
**Reporter:** Jhon-Crow  
**Severity:** Bug — Grenadier is non-functional as an armed combatant on Sewer level.  
**Related Issues:** #604 (Grenadier introduction), #657 (T8/T9 triggers added), #363, #959, #1305.

---

## Screenshot from Issue

The issue screenshot shows the Grenadier enemy (wearing the grenadier vest) on the Sewer map. The enemy patrols and throws grenades, but never fires its rifle.

---

## Data Collected

### Key Files

| File | Role |
|------|------|
| `scripts/objects/enemy.gd` | Main enemy AI (4991 lines) |
| `scripts/components/grenadier_grenade_component.gd` | Grenadier-specific grenade behavior (506 lines) |
| `scripts/components/enemy_grenade_component.gd` | Base grenade component |
| `scenes/levels/SewerLevel.tscn` | Sewer level scene (TopRoomGrenadier instance) |
| `scripts/levels/sewer_level.gd` | Sewer level script |

### Grenadier Scene Configuration (SewerLevel.tscn, lines 1667–1674)

```
[node name="TopRoomGrenadier" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(400, 280)
behavior_mode = 0         # PATROL
patrol_offsets = Array[Vector2]([Vector2(100, 0), Vector2(-100, 0)])
is_grenadier = true
destroy_on_death = true
enable_flanking = true
enable_cover = true
```

Notable: No explicit `weapon_type` — defaults to `WeaponType.RIFLE` (0). No explicit `grenade_count` — uses `GrenadierGrenadeComponent` bag of 8 grenades.

---

## Timeline / Sequence of Events Reconstruction

### Issue #604 — Grenadier introduced

- Added `is_grenadier` boolean export to `enemy.gd`.
- When `is_grenadier = true`, a `GrenadierGrenadeComponent` is used instead of `EnemyGrenadeComponent`.
- `GrenadierGrenadeComponent` manages a bag of 8 grenades (3 flashbangs + 5 offensive on normal; 1 defensive + 7 offensive on hard).
- Added `try_passage_throw()`: grenadier proactively throws grenades into passages before entering them (during PURSUING state).
- Allies wait for grenadier's grenade to explode before advancing.
- Grenadier was placed in SewerLevel.tscn as `TopRoomGrenadier`.

### Issue #657 — Triggers T8 and T9 added to GrenadierGrenadeComponent

- **T8 (Direct Sight)**: After 0.5s of seeing the player at a safe throwing distance, `is_ready()` returns `true`.
- **T9 (Low Suspicion)**: After 1.0s of any suspicion (memory target) while player is hidden, `is_ready()` returns `true`.
- Both triggers were added to make the grenadier more proactively throw grenades during encounters.

### The Bug Manifests

The grenade throw priority check in `enemy.gd` at line 1322:

```gdscript
# GRENADE THROW PRIORITY (Issue #363, #959, #1305)
if _combat_allowed and _goap_world_state.get("ready_to_throw_grenade", false) and not (_pacifist and _pacifist.is_pacifist):
    if try_throw_grenade():
        return  # ← EARLY RETURN prevents state machine from executing!
```

This check is at the **TOP of `_process_ai_state()`**, before the state machine `match` block:

```gdscript
match _current_state:
    AIState.IDLE: _process_idle_state(delta)
    AIState.COMBAT: _process_combat_state(delta)  # ← This never runs!
    ...
```

**The problem flow:**

1. Grenadier detects player → transitions to COMBAT state.
2. On the **very next physics frame** where the grenadier has line-of-sight and is at safe distance, the T8 timer starts accumulating.
3. After just **0.5 seconds**, T8 fires: `is_ready()` returns `true` → `ready_to_throw_grenade = true`.
4. Line 1322 fires: `try_throw_grenade()` is called → grenade thrown → **returns early**.
5. `_process_combat_state()` is **never reached** in this frame.
6. While `_is_throwing = true` (grenade animation), state machine is interrupted each frame.
7. After throw completes, a **15-second cooldown** (`throw_cooldown`) begins.
8. During cooldown: `ready_to_throw_grenade = false`, so COMBAT state can now process... BUT:
9. Within 1 second of any suspicion/memory, **T9 fires**: `is_ready()` returns `true` again.
10. Another grenade is thrown → another 15-second wait.
11. Cycle repeats indefinitely. The grenadier **never shoots its rifle**.

---

## Root Cause Analysis

### Primary Root Cause

**The grenade throw intercept at line 1322 of `enemy.gd` fires before `_process_combat_state()` can execute the shooting phase.**

The `GrenadierGrenadeComponent.is_ready()` method (which overrides the base component) includes:
- **T8**: Returns `true` after 0.5s of direct sight at throwable distance
- **T9**: Returns `true` after 1.0s of any suspicion

Both T8 and T9 were added in Issue #657 to make the grenadier "more aggressive" with grenades. However, because these triggers fire so quickly (0.5s and 1.0s), and because the grenade throw check is at the TOP of `_process_ai_state()` with an early `return`, the COMBAT state's shooting phase (`_process_combat_state()`) is never executed during the combat encounter.

### Contributing Factor

The COMBAT state's "exposed" shooting phase requires:
1. The grenadier to be in COMBAT state
2. `_combat_exposed = true` (set after approach phase completes — needs 2 seconds OR 250px proximity)
3. A clear shot exists

But because the grenade throw intercept fires after only 0.5s (T8), the COMBAT state never gets the 2 seconds needed to complete the approach phase and enter the shooting phase.

### Why Only Sewer?

Other levels may not have this issue because:
1. Grenadiers in other levels might have different combat encounter distances (if player is too close, T8 doesn't fire — safety distance check)
2. On Hard difficulty, the grenade count pattern differs
3. The Sewer map's TopRoom is a specific layout where the engagement distance keeps the grenadier perpetually in T8's "safe throw range"

---

## Possible Solutions

### Solution A (Implemented): Skip grenade throw intercept during COMBAT state for grenadiers

**Rationale**: When a grenadier is in COMBAT state, it should be focused on shooting. Grenade throwing should happen during PURSUING (passage throws) or as an interruption only in non-COMBAT states.

**Change** (enemy.gd, line 1322):
```gdscript
# Before fix:
if _combat_allowed and _goap_world_state.get("ready_to_throw_grenade", false) and not (_pacifist and _pacifist.is_pacifist):

# After fix:
# Issue #1805: Grenadiers in COMBAT state should shoot their rifle, not only throw grenades.
# Grenade throws are still available during PURSUING (passage throws), IDLE, and other states.
if _combat_allowed and _goap_world_state.get("ready_to_throw_grenade", false) and not (_pacifist and _pacifist.is_pacifist) and not (is_grenadier and _current_state == AIState.COMBAT):
```

**Pros:**
- Minimal change, surgical fix
- Grenadiers still throw passage grenades during PURSUING
- Grenadiers still throw grenades in IDLE/FLANKING/SEEKING_COVER states
- Grenadiers can now shoot their rifle during COMBAT state

**Cons:**
- Grenadiers no longer throw grenades mid-combat (this is arguably correct behavior — grenadiers should clear paths, then engage with rifles)

### Solution B: Increase T8/T9 delays significantly

Increase `DIRECT_SIGHT_DELAY` from 0.5s to 3.0s and `LOW_SUSPICION_DELAY` from 1.0s to 5.0s.

**Cons:** Doesn't fully fix the issue (same problem, just delayed). Makes grenadier less reactive.

### Solution C: Move grenade throw check AFTER state machine processing

Put grenade throw logic inside each state's processing function instead of at the top of `_process_ai_state()`.

**Cons:** Much larger refactor, risk of regression.

---

## Online Research Notes

- The pattern of grenade-first, shoot-later is a common AI design issue in tactical games. Games like Rainbow Six Siege use "utility first" AI design where grenades/gadgets have high priority, which is intentional.
- In this case, the grenadier's grenade priority was designed to make it tactically interesting, but the implementation makes it **exclusively** a grenade-thrower.
- The Godot engine's physics-based AI (using `_physics_process`) processes frame-by-frame, and the early `return` pattern means state machines can be completely bypassed by higher-priority checks.
- GDScript's `match` statement only runs if execution reaches it — any `return` before it bypasses the entire state machine.

---

## Fix Implementation

See: [`scripts/objects/enemy.gd`](../../../../scripts/objects/enemy.gd) line 1322.

The fix adds `and not (is_grenadier and _current_state == AIState.COMBAT)` to the grenade throw intercept condition.

This allows:
1. ✅ Grenadier shoots rifle during COMBAT state
2. ✅ Grenadier still throws passage grenades during PURSUING state
3. ✅ Grenadier can still throw grenades in other states (IDLE, FLANKING, etc.)
4. ✅ Regular enemies (non-grenadier) are unaffected

---

## Verification

To verify the fix works:
1. Open Sewer level
2. Trigger the grenadier (TopRoomGrenadier at Vector2(400, 280)) by approaching from below
3. Observe that after engaging, the grenadier both throws grenades AND fires its rifle
4. Confirm the grenadier enters COMBAT state and executes shooting phase

---

*Case study compiled by AI issue solver for Jhon-Crow/godot-topdown-MVP#1805*
