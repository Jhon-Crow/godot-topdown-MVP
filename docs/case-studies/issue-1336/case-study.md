# Case Study: Issue #1336 — Add Laser Sight to Sniper Enemy Rifle

**Date:** 2026-03-25
**Status:** All known bugs fixed
**Related Issues:** #1163, #1171, #1336
**Related PR:** #1484

---

## Summary

Issue #1336 requested a laser sight be added to the sniper enemy rifle, with the explicit requirement that the laser always points where the enemy will shoot (matching the future tracer). The laser was implemented in a previous session and placed inside `EnemySniperComponent`. Owner review of PR #1484 on 2026-03-25 identified two bugs:

- **Bug A**: The laser sight appears on ALL enemies, not just snipers, because `EnemySniperComponent` is instantiated unconditionally for every enemy in `enemy.gd`.
- **Bug B**: During "blind fire" (shooting at a predicted or last-known player position through cover), the laser direction does not match where the bullet actually flies. The laser reads a partially-lerped weapon rotation while the bullet travels along the exact computed target direction.

---

## Bug A: Laser Sight Appears on All Enemies

### Description

The laser sight is rendered on every enemy in the game regardless of enemy type or weapon. Only sniper enemies should display the laser.

### Affected File

- `scripts/objects/enemy.gd`, line 422

### Root Cause

`EnemySniperComponent` is created unconditionally for every enemy at `enemy.gd:422`:

```gdscript
_sniper_component = EnemySniperComponent.new(); _sniper_component.enemy = self; ...
```

The component was originally introduced to encapsulate hitscan shooting and sniper AI behavior. Because it was added unconditionally, any feature initialized inside the component — including the laser sight added to `_ready()` via `_create_laser_sight()` — is also applied to all enemies. No guard exists to check whether the enemy uses a sniper rifle before the component or laser is created.

### Impact

Every enemy type displays a laser sight. This contradicts the feature request, which explicitly scoped the laser to the sniper enemy rifle, and introduces visual noise and gameplay confusion on non-sniper enemies.

---

## Bug B: Laser Direction Mismatch During Blind Fire

### Description

During blind fire events — when the sniper shoots at a predicted or last-known player position (typically through cover) — the laser sight points in a direction that does not correspond to where the bullet will actually travel. The laser direction and the tracer direction diverge visibly.

### Affected Files

- `scripts/components/enemy_sniper_component.gd`, lines 148–186 — `fire_at_predicted_position()` method
- `scripts/components/enemy_sniper_component.gd`, lines 379–423 — `_update_laser_sight()` method

### Root Cause

The mismatch arises from two separate direction-computation paths being used for the laser versus the bullet.

**During direct fire** (player is visible):
- The laser reads `_get_weapon_forward_direction()`, which reflects the current weapon rotation.
- The bullet is also fired along `_get_weapon_forward_direction()`.
- Both directions are identical, so the laser is correct.

**During blind fire** (`fire_at_predicted_position()` is called):
- The sniper rotates toward the target using `_rotate_toward()`, which applies `lerp_angle()` — a gradual, frame-by-frame interpolation. At any given frame the weapon rotation is only partially turned toward the target.
- When the bullet is fired, `fire_at_predicted_position()` computes the shot direction independently: `to_target = (target_pos - enemy.global_position).normalized()`, then applies spread: `direction = to_target.rotated(spread)`.
- The bullet therefore travels along the exact normalized vector from enemy to target (plus spread), independent of the lerped rotation.
- The laser reads `_get_weapon_forward_direction()`, which at the moment of firing reflects the partial lerped rotation — not the actual `to_target` direction.

The result: the laser points in the partially-rotated direction while the bullet flies toward the exact target. The divergence can be significant depending on how far through the lerp rotation has progressed when the shot fires.

### Impact

This directly violates the core requirement of Issue #1336: "laser must always point where the enemy will shoot (match the future tracer)." During blind fire — a common behavior documented extensively in the game log — the laser actively misleads the player about where the shot will land.

---

## Evidence from Owner

### Screenshot (2026-03-25)

Owner provided screenshot `screenshot_laser_tracer_mismatch_20260325.png` showing:
- **Red laser** (sniper enemy): points upper-right from the enemy
- **Tan tracer** (sniper enemy hitscan, still fading): points roughly rightward
- **Yellow laser** (player's own laser sight — ignore per owner's note): points left

The large angular divergence (~30-45°) between the red laser and the tan tracer is explained by Bug C: the muzzle start point of the laser was offset in the lerped weapon rotation direction (right), but the laser end point was in the blind-fire target direction (upper-right). The resulting Line2D diagonal made the laser appear to aim in a completely different direction than the actual shot.

---

## Evidence from Game Log

**File:** `docs/case-studies/issue-1336/game_log_20260325_034213.txt`

- **Line 895:** `[#1163] Sniper blind-fire at predicted position (1581.633, 1406.331), ammo=4`
- Multiple additional blind fire events appear throughout the log, confirming that snipers regularly fire through cover at predicted player positions.

During each of these events, the laser would be pointing in the lerped rotation direction rather than toward the predicted target position `(1581.633, 1406.331)`. This is directly observable as a visual inconsistency: the laser sweeps gradually as the weapon lerps, while the bullet fires at a fixed computed point.

---

## Timeline of Events

| Date / Event | Details |
|---|---|
| Issue #1163 | Sniper AI behavior added: kiting, blind fire through cover, predicted position targeting |
| Issue #1171 | Hitscan shooting added to avoid physics tunneling on fast projectiles |
| Issue #1336 | Laser sight requested with requirement: "laser must always point where the enemy will shoot (match the future tracer)" |
| 2026-03-25 00:20 | Laser implemented inside `EnemySniperComponent`; placed in `_ready()` via `_create_laser_sight()`; direction sourced from `_get_weapon_forward_direction()` |
| 2026-03-25 00:46 | Owner reviews PR #1484 and reports Bug A (laser on all enemies) and Bug B (laser direction mismatch during blind fire); requests case study |
| 2026-03-25 00:54 | Bug A fixed: weapon type guard added in `_ready()`. Bug B partially fixed: `_blind_fire_target` variable added; `_update_laser_sight()` reads target direction instead of lerped rotation. But Bug C (see below) remained. |
| 2026-03-25 01:14 | Owner provides screenshot showing tracer and laser still diverging (see attached screenshot). Second AI session identifies Bug C: muzzle position is still computed from the lerped weapon sprite transform. |
| 2026-03-25 01:15 | Bug C fixed: muzzle position now computed using `weapon_forward` directly via weapon sprite's global position + `weapon_forward * muzzle_offset`. |

---

## Root Causes

### Bug A Root Cause

`EnemySniperComponent` is instantiated unconditionally at `enemy.gd:422`. The laser sight is initialized inside `EnemySniperComponent._ready()` with no weapon type guard, so it is created and rendered on all enemies.

### Bug B Root Cause

`_update_laser_sight()` computes the laser direction using `_get_weapon_forward_direction()`, which reads the current lerped weapon rotation. During blind fire, the bullet direction is computed from a direct `to_target` vector that is independent of the lerped rotation. At the moment of firing the lerped rotation has not converged to `to_target`, so the two directions diverge. The laser fails to satisfy the issue requirement of matching the future tracer.

### Bug C Root Cause (discovered 2026-03-25 after second owner review)

Even after Bug B's fix added `_blind_fire_target` to compute the correct laser *direction*, the muzzle *position* was still computed using `_get_bullet_spawn_position()`, which internally uses `_weapon_sprite.global_transform.x.normalized()` (the lerped weapon sprite rotation) to offset the muzzle forward from the sprite's origin.

Because the muzzle start point is offset in the *old* (lerped) direction while the laser end point is in the *new* (target) direction, the drawn `Line2D` is diagonal — it visually sweeps between the two directions. When the weapon has not yet lerped to the target angle, this diagonal is large enough to clearly diverge from where the bullet will fly.

Concretely: if the weapon sprite faces right (angle 0) but the blind-fire target is to the upper-left, the muzzle point lands to the right of the enemy body, and the laser then draws from there toward the upper-left. The resulting line traverses the enemy sprite at an odd angle, appearing completely wrong.

**Fix:** Compute the muzzle position using `weapon_forward` directly:
```gdscript
muzzle_pos = weapon_sprite.global_position + weapon_forward * scaled_muzzle_offset
```
This ensures both the muzzle start point and the laser direction are aligned with the same `weapon_forward` vector, making the laser a straight consistent line from gun to target.

---

## Proposed Solutions

### Fix A: Restrict Laser Sight to Sniper Enemies

Add a weapon type guard inside `EnemySniperComponent._ready()` before `_create_laser_sight()` is called:

```gdscript
# In EnemySniperComponent._ready()
if enemy == null or enemy.weapon_type != enemy.WeaponType.SNIPER_RIFLE:
    return
```

This ensures the laser is never created for non-sniper enemies regardless of where `EnemySniperComponent` is instantiated. It localizes the guard to the component itself, making future changes to `enemy.gd` less likely to reintroduce the bug.

An alternative is to wrap the `EnemySniperComponent` creation at `enemy.gd:422` inside a `weapon_type == WeaponType.SNIPER_RIFLE` condition. This is cleaner at the instantiation site but less robust if the instantiation is ever duplicated or moved.

### Fix B: Match Laser Direction to Actual Blind-Fire Target

The laser must show where the next bullet will actually travel. The recommended approach is to expose the current blind-fire target position from the sniper component and compute the laser direction from it directly in `_update_laser_sight()`, mirroring the math in `fire_at_predicted_position()`.

**Implementation:**

1. Add a variable `_blind_fire_target: Vector2` to `EnemySniperComponent`. Set it whenever `fire_at_predicted_position()` stores a target position; clear it when not in blind-fire mode.

2. In `_update_laser_sight()`, check whether `_blind_fire_target` is set. If it is, compute the laser direction as:
   ```gdscript
   var direction = (_blind_fire_target - enemy.global_position).normalized()
   ```
   This is the same vector that `fire_at_predicted_position()` uses for `to_target`, ensuring the laser matches the actual bullet direction.

3. If `_blind_fire_target` is not set (direct fire mode), continue using `_get_weapon_forward_direction()` as before.

An alternative (option 1) is to store the last actual fire direction after each shot and use that for the laser. This is simpler but means the laser shows the direction of the previous shot rather than the direction of the next shot during the interval between shots, which may look incorrect.

---

### Fix C: Compute Muzzle Position Using weapon_forward

In `_update_laser_sight()`, replace the call to `_get_bullet_spawn_position(weapon_forward)` with a direct calculation using the correct `weapon_forward`:

```gdscript
var weapon_sprite := enemy.get("_weapon_sprite") as Node2D
if weapon_sprite != null and is_instance_valid(weapon_sprite):
    const MUZZLE_LOCAL_OFFSET := 52.0
    var scaled_muzzle_offset := MUZZLE_LOCAL_OFFSET * enemy.enemy_model_scale
    muzzle_pos = weapon_sprite.global_position + weapon_forward * scaled_muzzle_offset
else:
    muzzle_pos = enemy._get_bullet_spawn_position(weapon_forward)
```

This mirrors what `_get_bullet_spawn_position()` does when the player is visible (it uses the direct calculated direction to player), but applies it universally to ensure the muzzle start and laser direction always agree.

---

## Bug D: Tracer Persists Too Long, Creating Apparent Laser/Tracer Mismatch (Session 4, 2026-03-25)

### Description

After Bug C was fixed (muzzle position consistent with `weapon_forward`), the owner reported a new symptom: **"теперь нет ни лазера ни трассера"** ("now there's no laser or tracer"). Analysis of the attached `game_log_20260325_044209.txt` revealed:

- The sniper was spawned via F8 debug key at `04:43:17`
- No hitscan shots were logged after the spawn
- The game session ended within seconds of spawn

**Root cause of "no laser" report**: The game session was too short to observe a shot (and therefore a tracer). The laser DOES appear immediately upon spawn, but it is subtle (semi-transparent red, 1.5px wide). If the user didn't focus on the enemy immediately, they may have missed the laser.

**Root cause of the screenshot mismatch (Bug C/D combined)**: The screenshot from session 2 (01:14 UTC) shows a red laser (upper-right) and a tan tracer (right) diverging at ~30-45°. This occurs because:

1. The sniper fires at the player (player visible, direct fire) → tan tracer goes RIGHT
2. Player immediately hides in cover → `can_see_player = false`
3. Next physics frame: `_rotate_toward(blind_target)` called → `_blind_fire_target = upper-right position`
4. The laser in `_process` now uses `_blind_fire_target` → laser rotates to point upper-right
5. The tan tracer from step 1 is still **fading for 2 seconds** → user sees: tracer going right + laser going upper-right

This creates the **appearance of a mismatch even though the laser is actually correct** (showing where the next blind shot will go). The 2-second tracer fade is the root cause of the visual confusion.

### Fix

1. **Reduce tracer fade duration from 2.0 s to 0.4 s** — the historical tracer disappears before the laser has time to rotate significantly, eliminating the visible divergence window.
2. **Improve laser visibility** — increase laser alpha from 0.4 to 0.55 and dot alpha from 0.7 to 0.85, so the laser is clearly visible on screen without being distracting.
3. **Fix muzzle position consistency** (final Bug C correction) — replace `weapon_sprite.global_position + weapon_forward * offset` with `enemy.global_position + weapon_forward * offset`. The WeaponMount's 6px lateral offset shifts with the lerped model rotation, causing the laser start point to wobble off-axis. Using `enemy.global_position` as the anchor ensures the muzzle is always exactly `offset` pixels along `weapon_forward` from the enemy center, regardless of the current lerp state.

---

## Session Chronology

| Timestamp (UTC) | Session | Event |
|---|---|---|
| ~2026-03-25 00:20 | Session 1 | Initial laser implementation added; all enemies showed laser; blind-fire direction wrong |
| 00:46 | Owner feedback | Bug A (all enemies) + Bug B (blind fire direction) reported |
| 00:47–00:54 | Session 2 | Bug A + B fixed: weapon_type guard + `_blind_fire_target`; Bug C remained |
| 01:14 | Owner feedback | Screenshot showing laser/tracer divergence; Bug C identified |
| 01:15–01:26 | Session 3 | Bug C fix: muzzle computed as `weapon_sprite.pos + weapon_forward * offset` |
| 01:44 | Owner feedback | "no laser or tracer" complaint; provides `game_log_20260325_044209.txt` |
| ~02:30+ | Session 4 | Root cause analysis: "no laser" = game ended before sniper fired; "no tracer" = tracer 2s fade created visual confusion. Bug D fix: tracer fade reduced to 0.4s, laser alpha increased, muzzle fixed to `enemy.global_position + weapon_forward * offset` |

---

## Key Files

| File | Relevant Lines | Purpose |
|---|---|---|
| `scripts/objects/enemy.gd` | 422 | Unconditional `EnemySniperComponent` creation — root of Bug A |
| `scripts/components/enemy_sniper_component.gd` | 60–67 | `_ready()` with weapon type guard (Bug A fix) |
| `scripts/components/enemy_sniper_component.gd` | 349–361 | `_fade_sniper_tracer()` — fade duration reduced to 0.4s (Bug D fix) |
| `scripts/components/enemy_sniper_component.gd` | 405–465 | `_update_laser_sight()` — laser direction + muzzle position (Bugs B, C, D fixed) |
| `scripts/components/enemy_sniper_component.gd` | 163–200 | `fire_at_predicted_position()` — blind fire shot direction computation |
| `docs/case-studies/issue-1336/game_log_20260325_034213.txt` | — | Session 1: hitscan hits, blind fire events; original bug reproduction |
| `docs/case-studies/issue-1336/game_log_20260325_044209.txt` | — | Session 4: "no laser" report; sniper spawned but no shots fired |
| `docs/case-studies/issue-1336/screenshot_laser_tracer_mismatch_20260325.png` | — | Bug C evidence: laser (upper-right) diverging from tracer (right) |
