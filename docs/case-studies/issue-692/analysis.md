# Case Study: Issue #692 - Enemy Self-Destruct Protection

## Problem Statement

**Issue**: "enemies still blow up themselves and others" (ru: "враги всё ещё взрывают себя и других")

Despite previous fix attempts, enemies were still destroying themselves AND friendly allies with their own grenade explosions and shrapnel.

## Timeline of Fixes

| Date | PR | Fix Description | Result |
|------|-----|-----------------|--------|
| 2026-01-25 | #376 | Added min throw distance check: `blast_radius + safety_margin` | Reduced frequency but didn't prevent |
| 2026-02-08 | #658 | Added `MIN_ARMING_DISTANCE = 80px` in GDScript | Ineffective in exported builds (GDScript doesn't run) |
| 2026-02-09 | #695 v1 | Added `thrower_id` to exclude thrower from blast + shrapnel | Fixed self-damage but not friendly fire |
| 2026-02-09 | #695 v2 | Exclude ALL enemies from enemy-thrown grenades | **Complete fix** |

## Root Cause Analysis (v2 - After User Feedback)

### What the game logs revealed

Analysis of `game_log_20260209_034310.txt` from user's testing of PR #695 v1:

**Incident 1** (lines 4177-4208, Building Level):
- An enemy threw a frag grenade (thrower ID: `1408648614297`)
- C# GrenadeTimer correctly logged: "Skipping thrower - self-damage prevention"
- **Enemy4** (a DIFFERENT enemy at distance 155px) took 3 hits and died
- Root cause: **Friendly fire** - ally killed by teammate's grenade

**Incident 2** (lines 6735-6771):
- Enemy threw grenade (thrower ID: `1649569439176`)
- GDScript FragGrenade correctly skipped the thrower
- **Enemy3** (distance 100.7px) and **Enemy4** (distance 207.5px) both died from HE blast
- Additionally, BOTH GDScript AND C# applied damage independently (dual explosion)

**Incident 3** (lines 8608-8646):
- Enemy threw grenade (thrower ID: `1989492607073`)
- **Grenadier** (distance 146.7px) died from its ally's grenade

### Key insight

The v1 fix (`thrower_id` tracking) correctly prevented the **thrower** from being damaged. But the user's complaint was "враги всё ещё взрывают себя **и других**" - enemies still blow up themselves **AND OTHERS**. The "others" part was the unaddressed problem: enemy grenades were killing **allied enemies** within the blast radius.

### Why v1 was insufficient

The v1 fix only excluded the single enemy that threw the grenade from receiving damage. All other enemies within the 225px frag blast radius or 700px defensive blast radius still received full 99 HE damage plus shrapnel hits. Since enemies often cluster together, friendly fire was common.

### Dual explosion issue

Both GDScript (`frag_grenade.gd::_on_explode()`) and C# (`GrenadeTimer.cs::Explode()`) independently process explosion damage via their own `body_entered` handlers. This caused:
1. Double damage application in some cases
2. Both systems needed the same protection logic

## Fix Applied (v2)

### Approach: Exclude ALL enemies from enemy-thrown grenades

Changed from "exclude thrower only" to "exclude ALL enemies" when `thrower_id >= 0`:

```
Enemy grenade explosion (thrower_id >= 0):
  → HE blast: skip ALL enemies, only damage player
  → Shrapnel: skip ALL enemies, only damage player

Player grenade explosion (thrower_id == -1):
  → HE blast: damage all enemies normally
  → Shrapnel: damage all enemies normally
```

### Files changed

1. **`frag_grenade.gd`**: `_get_enemies_in_radius()` returns empty when `thrower_id >= 0`
2. **`defensive_grenade.gd`**: Same change as frag_grenade.gd
3. **`GrenadeTimer.cs`**: `ApplyFragExplosion()` skips all enemy damage when `ThrowerId >= 0`
4. **`shrapnel.gd`**: `_on_body_entered()` and `_on_area_entered()` skip all enemies via `is_in_group("enemies")` when `thrower_id >= 0`

### Design rationale

Enemy grenades are intended as a tactical threat against the **player**, not as friendly fire between enemies. This matches the game design where enemies coordinate their attacks. Enemies already have safety distance checks before throwing (`blast_radius + safety_margin`), but these can't prevent all collateral damage scenarios (e.g., enemies moving into blast zone after throw, grenades bouncing into unexpected positions).

The simplest and most robust solution is to make enemy grenades completely safe for all enemies.
