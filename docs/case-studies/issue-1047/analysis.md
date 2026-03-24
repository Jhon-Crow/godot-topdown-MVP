# Case Study: Issue #1047 — Combat Disposition Passive Item

## Issue Summary

**Title:** добавь пассивный предмет Боевой Настрой (Add Combat Disposition passive item)
**Repository:** Jhon-Crow/godot-topdown-MVP
**Issue:** [#1047](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1047)
**PR:** [#1048](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1048)

### Requirements (from issue)

- On run start: player damage +0.7, fire rate +1 shots/sec
- On first hit taken (once per run): damage −1, fire rate −1.2

---

## Timeline of Events

| Date/Time (UTC) | Event |
|---|---|
| 2026-03-16 19:27 | Initial implementation delivered — basic penalties, no icons, no "once per run" guard |
| 2026-03-16 20:49 | Owner feedback: (1) penalty must apply only once per run; (2) add sword icon for positive state; (3) add broken sword icon for negative state |
| 2026-03-16 21:24 | Second iteration: `_combatDispositionPenaltyApplied` flag added; icons added |
| 2026-03-17 08:45 | Owner feedback: increase penalties by 50%; resolve merge conflicts |
| 2026-03-17 08:54 | Third iteration: damage penalty −1.0 → −1.5, fire rate penalty −1.2 → −1.8; conflicts resolved |
| 2026-03-17 09:22 | Owner feedback (with [game_log_20260317_121746.txt](game_log_20260317_121746.txt)): confirm penalty works, then double it |
| 2026-03-17 09:27 | Fourth iteration: log confirmed one-time penalty; damage −1.5 → −3.0, fire rate −1.8 → −3.6 |
| 2026-03-17 10:23 | Owner feedback (with [game_log_20260317_132148.txt](game_log_20260317_132148.txt)): "after taking damage, no worsening noticeable — feels like player moves faster" |
| 2026-03-17 10:24 | Bug investigation begins |
| 2026-03-17 10:36 | Fifth iteration: root cause confirmed (weapon switch losing bonuses); `EquipWeapon()` now propagates Combat Disposition bonuses |
| 2026-03-17 18:41 | Owner feedback (with [game_log_20260317_213524.txt](game_log_20260317_213524.txt)): "make buff 10% stronger, double the penalty" |
| 2026-03-17 19:03 | Sixth iteration: positive buff +0.7→+0.77 damage, +1.0→+1.1 fire rate; penalties −3.0→−6.0 damage, −3.6→−7.2 fire rate |

---

## Game Log Analysis

### Log 1: game_log_20260317_121746.txt (pre-doubling)

Relevant entries:
```
[12:19:43] Combat Disposition initialized on AssaultRifle: +0.7 damage, +1 fire rate
[12:19:45] Combat Disposition initialized again (second _Ready call due to scene reload)
[12:19:50] First hit — penalty applied once: damage bonus: -0.8, fire rate bonus: -0.8
```

- Penalty values confirm the 50%-increased penalties were active (0.7 − 1.5 = −0.8, 1.0 − 1.8 = −0.8).
- "Once per run" guard was working — no repeat penalty entries.

### Log 3: game_log_20260317_213524.txt (post-weapon-switch-fix, balance tuning request)

Relevant entries:
```
[21:35:33] Combat Disposition initialized on AKGL: +0.7 damage, +1 fire rate
[21:35:44] First hit — penalty applied once: damage bonus: -2.3, fire rate bonus: -2.6
[21:36:06] Combat Disposition initialized on MiniUzi: +0.7 damage, +1 fire rate  ← weapon switch
[21:36:09] First hit — penalty applied once: damage bonus: -2.3, fire rate bonus: -2.6  ← penalty re-applied (per-run reset on new level)
```

- The weapon-switch fix from iteration 5 is confirmed working: the penalty value (`-2.3/-2.6`) is consistent across weapon switches.
- The "per run" reset correctly triggers on new levels (`InitCombatDisposition` is called on scene change).
- Owner requested stronger values: buff +10%, penalty ×2.

### Log 2: game_log_20260317_132148.txt (post-doubling, bug report)

Relevant entries:
```
[13:21:49] Combat Disposition initialized on Shotgun: +0.7 damage, +1 fire rate
[13:21:55] Combat Disposition initialized AGAIN on Shotgun (second _Ready call)
[13:21:59] First hit — penalty applied once: damage bonus: -2.3, fire rate bonus: -2.6
```

- Penalty math is correct: 0.7 − 3.0 = −2.3, 1.0 − 3.6 = −2.6.
- The penalty IS being applied — but the owner still observes no effect.

---

## Root Cause Analysis

### Hypothesis: Weapon Switch Loses the Penalty

The penalty is applied to `CurrentWeapon.DamageBonus` and `CurrentWeapon.FireRateBonus` at the moment the first hit is taken. However, the level script (`scripts/levels/test_tier.gd`) calls `Player.EquipWeapon(newWeapon)` when the player picks up or is assigned a different weapon. The previous `EquipWeapon()` implementation only propagated the `IsBreakerBulletActive` flag — it did **not** copy the Combat Disposition bonuses to the new weapon object.

```csharp
// BEFORE fix — Combat Disposition bonuses lost on weapon switch
public void EquipWeapon(BaseWeapon weapon)
{
    CurrentWeapon = weapon;
    if (_breakerBulletsActive)
        CurrentWeapon.IsBreakerBulletActive = true;
    // Combat Disposition bonuses NOT copied → new weapon gets DamageBonus=0, FireRateBonus=0
    AddChild(CurrentWeapon);
}
```

### Why It Looks Like "Player Moves Faster"

`FireRateBonus` affects the fire timer: `_fireTimer = 1.0 / max(FireRate + FireRateBonus, 0.1)`. With Shotgun `FireRate = 1.5` and `FireRateBonus = −2.6`, the effective rate becomes `max(−1.1, 0.1) = 0.1`, meaning 10 seconds between shots. This is severe.

After a weapon switch (e.g., entering a new room), the new weapon starts with `FireRateBonus = 0`, restoring normal fire rate. The player's *fire rate recovers*, which subjectively feels like "moving/shooting faster" compared to the intended penalised state.

### Evidence

- Log 2 shows the penalty applied at 13:21:59.
- Between 13:22:00 and 13:22:01, the player takes 6 more hits — if no weapon switch occurred, fire rate would be severely limited and the player should not be able to take that many hits in 1 second (reload/fire gap would be 10s). The rapid damage intake suggests the level was advancing and a weapon re-equip occurred.

---

## Fix

**File:** `Scripts/Characters/Player.cs`
**Method:** `EquipWeapon(BaseWeapon weapon)`

```csharp
// AFTER fix — Combat Disposition bonuses propagated to new weapon
public void EquipWeapon(BaseWeapon weapon)
{
    CurrentWeapon = weapon;
    if (_breakerBulletsActive)
        CurrentWeapon.IsBreakerBulletActive = true;
    // Propagate Combat Disposition bonuses to new weapon (Issue #1047)
    if (_combatDispositionActive)
    {
        CurrentWeapon.DamageBonus = _combatDispositionDamageBonus;
        CurrentWeapon.FireRateBonus = _combatDispositionFireRateBonus;
    }
    AddChild(CurrentWeapon);
}
```

The fields `_combatDispositionDamageBonus` and `_combatDispositionFireRateBonus` always hold the current state (positive before hit, negative after), so this correctly propagates whichever state is active at the time of the weapon switch.

---

## Tests Added

Four new unit tests were added to `tests/unit/test_combat_disposition.gd`:

1. `test_equip_weapon_carries_initial_bonus_to_new_weapon` — verifies bonuses are propagated before any hit
2. `test_equip_weapon_after_penalty_carries_penalty_to_new_weapon` — verifies penalty persists across a weapon switch
3. `test_equip_weapon_does_not_propagate_when_inactive` — verifies no side effect when item not equipped
4. `test_penalty_persists_across_multiple_weapon_switches` — verifies stability over repeated switches

---

## Lessons Learned

- When applying a persistent per-run stat modifier to `CurrentWeapon`, always also hook into `EquipWeapon()` to re-apply the modifier to future weapons — the same pattern used by `IsBreakerBulletActive`.
- Log analysis should check not only whether the penalty is being logged, but also whether subsequent weapon loads reset the bonus silently.
