# Case Study: Issue #1143 — Enemy with Armored Skin: triggering hit damage not absorbed

## Summary

The enemy's Armored Skin component (`EnemyArmoredSkinComponent`) spawned glass shards when hit at ≤2 HP but did **not** absorb the damage from the triggering hit. The player's implementation (Issue #1045, `Player.cs`) correctly returns early after spawning shards, fully ignoring the triggering projectile's damage. The enemy implementation lacked this behaviour.

---

## Timeline / Sequence of Events

1. **Issue #1045** (closed): Player's Armored Skin passive implemented in C#. When the player is hit at ≤2 HP with `_armoredSkinActive == true`, `TakeDamage()` calls `SpawnArmoredSkinShards()` and then `return`s — the triggering hit is fully absorbed. Post-trigger immunity (`_armoredSkinImmune`) absorbs any remaining calls from multi-hit explosions (Issue #1095).

2. **Issue #1123** (closed, PR #1124): Enemy Armored Skin feature added. `EnemyArmoredSkinComponent.try_spawn_shards()` was introduced as a `void` method. `enemy.gd` calls it before applying damage, but because `try_spawn_shards` returned nothing, the caller always continued to apply damage — regardless of whether shards were spawned.

3. **Issue #1143** (this issue): Bug reported — a direct grenade hit (or any hit) at ≤2 HP triggers shards but the damage is **not** ignored. The enemy loses HP from the triggering hit, which can kill it even though the Armored Skin should have protected it.

---

## Root Cause Analysis

### Location
- `scripts/components/enemy_armored_skin_component.gd` — `try_spawn_shards()` (line 78)
- `scripts/objects/enemy.gd` — `on_hit_with_bullet_info()` (line 4182)

### Root Cause
`try_spawn_shards(current_health: int) -> void` has no return value, so `enemy.gd` cannot tell whether the activation actually fired. The call site:

```gdscript
if _armored_skin_component: _armored_skin_component.try_spawn_shards(_current_health)
# ... damage applied unconditionally
_current_health -= actual_damage
```

The damage is applied regardless of whether the armored skin triggered.

### Contrast with Player
`Player.cs TakeDamage()`:
```csharp
if (_armoredSkinActive && HealthComponent.CurrentHealth <= 2)
{
    _armoredSkinActive = false;
    _armoredSkinImmune = true;
    SpawnArmoredSkinShards();
    GetTree().CreateTimer(0.1f).Timeout += () => _armoredSkinImmune = false;
    return;  // <-- triggering hit absorbed
}
```

The player uses an explicit `return` to absorb the triggering hit.

---

## Additional Bugs Found (Game Log — 2026-03-18)

The game log `game_log_20260318_075312.txt` captured a real playthrough and revealed two further bugs in the initial fix:

### Bug 2: Enemy becomes immortal (re-triggering)

Log lines 1041–1062 show the Armored Skin triggering **repeatedly** on every hit after the first:

```
[07:53:31] [EnemyArmoredSkin] Spawning 20 glass shards (hp <= 2)
[07:53:31] [ArmoredSkinEnemy] [ArmoredSkin] Triggering hit absorbed — damage ignored
[07:53:31] [EnemyArmoredSkin] Spawning 20 glass shards (hp <= 2)    ← repeat
[07:53:31] [ArmoredSkinEnemy] [ArmoredSkin] Triggering hit absorbed — damage ignored
... (continues for every subsequent hit)
```

**Root cause:** `try_spawn_shards()` had no state — it checked `current_health <= HP_THRESHOLD` every call, so a grenade's multiple simultaneous fragment hits all triggered independently.

**Fix:** Added `_has_triggered: bool = false` flag. Once the effect fires, the flag is set to `true` and all subsequent calls return `false` immediately.

### Bug 3: Armor visual not removed after trigger

When shards spawn, the enemy's glassy shader overlay remained — making it look armored even though the effect was spent.

**Fix:** Added `_remove_armor_visual()` called immediately after `_spawn_shards()`. Iterates `EnemyModel` sprites and sets `material = null` for any `ShaderMaterial`.

---

## Proposed Solution

### Initial fix (PR #1151 v1)
Change `try_spawn_shards` to return `bool`:
- `true` → shards were spawned, the triggering hit's damage must be absorbed.
- `false` → HP was above threshold, proceed normally.

In `enemy.gd`, check the return value and `return` early (after emitting `hit` signal and visual feedback) to absorb the damage, mirroring the player behaviour.

### Follow-up fix (PR #1151 v2 — this update)
1. `_has_triggered: bool` state flag prevents the Armored Skin from triggering more than once.
2. `_remove_armor_visual()` removes the shader overlay from all enemy `Sprite2D` children when shards spawn, so the enemy visually becomes a regular enemy.

Note: The player (`Player.cs`) additionally uses a brief post-trigger immunity window (`_armoredSkinImmune`) to absorb remaining hits from the same multi-projectile burst (Issue #1095). The enemy fix uses `_has_triggered` which persists for the entire lifetime of the enemy — a stricter but simpler approach that satisfies the stated requirement.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/components/enemy_armored_skin_component.gd` | `try_spawn_shards` returns `bool`, adds `_has_triggered` flag, adds `_remove_armor_visual()` |
| `scripts/objects/enemy.gd` | Return early when `try_spawn_shards` returns `true` |
| `tests/unit/test_enemy_armored_skin.gd` | Add tests: single-trigger guarantee, visual removal, second-hit damage applied |
| `docs/case-studies/issue-1143/game_log_20260318_075312.txt` | Game log from bug report by Jhon-Crow (2026-03-18) |
