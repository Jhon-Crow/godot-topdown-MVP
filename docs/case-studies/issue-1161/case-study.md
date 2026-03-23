# Case Study: Issue #1161 — Fix Sniper Enemy

## Summary

Three bugs were identified with the sniper enemy (`ContainerYardA_Sniper` on DocksLevel, `WeaponType.SNIPER_RIFLE`):

1. **Burst firing** — Sniper fires rapid bursts; it should only fire one shot at a time (semi-automatic bolt-action).
2. **Wrong ammo count** — Sniper should have 70 total rounds, but currently has only 15.
3. **Missing bolt-action animation** — After each shot, the sniper should perform a bolt-action cycle (like the player's ASVK).

---

## Data Sources

- Game log: `game_log_20260318_091610.txt` (session recorded 2026-03-18 09:16–09:19, Windows, release build, LabyrinthLevel + DocksLevel)
- Source code: `scripts/objects/enemy.gd`, `scripts/components/weapon_config_component.gd`, `scenes/levels/DocksLevel.tscn`, `Scripts/Weapons/SniperRifle.cs`, `resources/weapons/SniperRifleData.tres`

---

## Timeline of Events (Reconstructed)

| Time | Log Line | Event |
|------|----------|-------|
| 09:16:22 | 666 | `ContainerYardA_Sniper` spawned at (4500, 420), hp=2, behavior=GUARD |
| 09:16:36 | 2073 | Shot #1 (COMBAT state, approaching player) |
| 09:16:37 | 2380 | Shot #2 — 1s gap (normal, respects `shoot_cooldown=3s`?) |
| 09:16:42 | 3028 | Shot #3 — RETREATING state, `_process_retreat_full_hp` (normal shot) |
| **09:16:43** | **3164** | **Shot #4 — 1s after shot #3, same position!** Triggered by rapid state cycle RETREATING→SUPPRESSED→SEEKING_COVER→COMBAT→RETREATING→SUPPRESSED |
| 09:16:48 | 3371 | Shot #5 — RETREATING→COMBAT |
| **09:16:49** | **3397** | **Shot #6 — 1s gap!** Same rapid state cycling |
| 09:17:45 | 5284 | Shot #7 — respawn, 56s later (normal) |
| **09:17:58** | **6810** | **Shot #8 — RETREATING→SUPPRESSED** |
| **09:17:59** | **6889** | **Shot #9 — 1s gap, same position!** Player ammo empty triggered priority attack |
| 09:18:03 | 7076 | Shot #10 — 4s gap (near-normal) |
| **09:18:50** | **12592** | **Shot #13 — COMBAT** |
| **09:18:51** | **12738** | **Shot #14 — 1s gap!** State COMBAT→RETREATING→SUPPRESSED triggered shot |
| **09:18:52** | **12898** | **Shot #15 — 1s gap!** State SUPPRESSED→SEEKING_COVER→COMBAT→RETREATING→SUPPRESSED |
| **09:19:10** | **13572** | **Shot #19 — COMBAT** |
| **09:19:10** | **13577** | **Shot #20 — <1s gap, same position!** COMBAT→RETREATING→SUPPRESSED |
| **09:19:11** | **13584** | **Shot #21 — 1s gap!** SUPPRESSED→SEEKING_COVER→COMBAT→RETREATING→SUPPRESSED |

**Burst pattern observed**: Multiple shots fired at the same position within 1–2 seconds (should be 3s minimum between shots for ASVK).

---

## Root Cause Analysis

### Bug 1: Burst Firing

**Root cause**: The `_shoot_timer` is reset to 0 each time a state transition occurs that triggers `_transition_to_combat()`:

```gdscript
func _transition_to_combat() -> void:
    _current_state = AIState.COMBAT
    ...
    _combat_shoot_timer = 0.0
    # _shoot_timer is NOT reset here, but...
```

However, the real issue is: each state (`RETREATING`, `SUPPRESSED`, `COMBAT`) has its own independent shooting logic. When a rapid state cycle happens (COMBAT→RETREATING→SUPPRESSED→SEEKING_COVER→COMBAT), the _shoot_timer reaches `shoot_cooldown=3.0` across these short transitions and each state independently fires a shot.

Additionally, `_process_retreat_full_hp` fires via `_shoot_with_inaccuracy()` using `shoot_cooldown`, and `_process_suppressed_state` also has an independent firing block. Within a 2-second window of rapid cycling, both can fire — each checking `_shoot_timer >= shoot_cooldown` but with the timer NOT reset between state transitions.

Furthermore, `_shoot_burst_shot()` uses `RETREAT_BURST_COOLDOWN = 0.06s` (60ms!) for its burst mechanism, completely bypassing the 3-second bolt-action delay. A 2–4 shot burst at 60ms intervals is automatic fire behavior — completely wrong for a bolt-action sniper.

**Fix needed**:
1. For `SNIPER_RIFLE` weapon type, skip all burst fire logic in `_shoot_burst_shot()`.
2. In `_process_retreat_one_hit()` and `_process_suppressed_state()` burst sequences, check weapon type.
3. Ensure `_shoot_timer` is not allowed to fire a second shot within less than `shoot_cooldown` even through state transitions by NOT resetting `_shoot_timer` in transitions.

### Bug 2: Wrong Ammo Count (Should be 70)

**Root cause**: `weapon_config_component.gd` has:

```gdscript
7: {  # SNIPER_RIFLE (ASVK)
    "magazine_size": 5,    # 5-round magazine
    "total_magazines": 3,  # 5 + 10 = 15 total
```

Calculation: `_current_ammo = magazine_size = 5`, `_reserve_ammo = (total_magazines - 1) * magazine_size = 2 * 5 = 10`. Total = **15**.

**Fix needed**: Change `total_magazines` from `3` to `14`:
- 14 magazines × 5 rounds = 70 total rounds ✓

### Bug 3: Missing Bolt-Action Animation

**Root cause**: The `_execute_shoot()` function fires a bullet but does nothing special for `SNIPER_RIFLE` weapon type beyond playing the sound. No bolt-action animation is triggered.

The player's `SniperRifle.cs` has a full `BoltActionStep` state machine (Ready → NeedsBoltCycle → WaitExtractCasing → WaitChamberRound → WaitCloseBolt → Ready) triggered by arrow keys. For the enemy, we cannot replicate this exact mechanic, but the enemy's weapon already has `shoot_cooldown = 3.0s`, which represents the time between shots. A visual bolt-action animation should be triggered after each shot.

Looking at existing patterns, the casing ejection already happens at fire time. For bolt-action, we need a visible "bolt cycling" animation — likely a sprite change or a temporary pose. However, examining the codebase, there is no dedicated bolt-action animation system for enemies.

**Fix needed**: Add a `_is_bolt_cycling` flag for `SNIPER_RIFLE` that:
1. Gets set `true` after each shot (triggered in `_execute_shoot`)
2. Plays a bolt-cycle animation/sound after `bolt_cycle_delay` (e.g., 0.5s after shot)
3. Gets cleared after the animation, preventing burst and giving visual feedback

---

## Additional Observations

- The sniper has `enable_flanking = false` in the scene (correct for a sniper).
- The sniper uses `enable_cover = true`, which causes the rapid state cycling observed in the burst patterns.
- The `RETREAT_BURST_COOLDOWN = 0.06s` is designed for automatic weapons (M16, UZI) and must not apply to bolt-action snipers.
- The "priority attack" system (triggered when player ammo is empty) can bypass `_shoot_timer` checks, contributing to shots 8-9 in the timeline.

---

## Proposed Solutions

### Fix 1: Prevent Burst Fire for Sniper
In `_shoot_burst_shot()`, `_process_retreat_one_hit()`, and `_process_suppressed_state()` burst blocks, add a weapon type check:
```gdscript
if weapon_type == WeaponType.SNIPER_RIFLE:
    return  # No burst fire for bolt-action sniper
```

Also, ensure `_shoot_timer` is NOT reset during state transitions (it should persist across states so the 3s cooldown always applies).

### Fix 2: Fix Ammo Count
In `weapon_config_component.gd`, change `total_magazines` for SNIPER_RIFLE from `3` to `14`.

### Fix 3: Bolt-Action Animation
Add `_is_bolt_cycling: bool` and `_bolt_cycle_timer: float` variables. After each sniper shot in `_execute_shoot()`, set `_is_bolt_cycling = true` and `_bolt_cycle_timer = 0`. In `_physics_process`, increment the timer and trigger the bolt cycle visual/sound at an appropriate delay (e.g., 0.5s). Clear the flag when done.

For the animation, reuse the casing ejection event or add a dedicated "bolt pull" sound via `AudioManager` when available.
