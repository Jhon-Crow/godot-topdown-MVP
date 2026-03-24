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

### Follow-up fix (PR #1151 v2 — Bug 2 & 3)
1. `_has_triggered: bool` state flag prevents the Armored Skin from triggering more than once.
2. `_remove_armor_visual()` removes the shader overlay from all enemy `Sprite2D` children when shards spawn, so the enemy visually becomes a regular enemy.

### Follow-up fix (PR #1151 v3 — Bug 4: grenade burst kills enemy after trigger)

A third round of playtesting (game log `game_log_20260318_080738.txt`, 2026-03-18) showed the enemy still dying from a direct grenade hit despite the armored skin triggering. Log excerpt:

```
[08:08:01] [ENEMY] [ArmoredSkinEnemy] Hit: dmg=1, hp=3/3->2/3   ← first frag hits (above threshold)
[08:08:01] [INFO]  [EnemyArmoredSkin] Spawning 20 glass shards (hp <= 2)
[08:08:01] [INFO]  [EnemyArmoredSkin] Armor visual removed from 4 sprites (triggered)
[08:08:01] [ENEMY] [ArmoredSkinEnemy] [ArmoredSkin] Triggering hit absorbed — damage ignored
[08:08:01] [ENEMY] [ArmoredSkinEnemy] Hit: dmg=1, hp=2/3->1/3   ← second frag hits (post-trigger)
[08:08:01] [ENEMY] [ArmoredSkinEnemy] Hit: dmg=1, hp=1/3->0/3   ← third frag hits → DEAD
[08:08:01] [ENEMY] [ArmoredSkinEnemy] Enemy died
```

**Root cause:** The VOGGrenade (grenade launcher) uses a fragmentation explosion that fires multiple `on_hit_with_bullet_info()` calls in the **same physics frame** (all logged at the same timestamp). The `_has_triggered` flag correctly blocks re-triggering on subsequent frames, but on the trigger frame itself the remaining frag hits still deal damage.

This mirrors how `Player.cs` handles Issue #1095: it sets `_armoredSkinImmune = true` immediately after triggering, and clears it after a 100 ms timer — absorbing all hits in the same burst.

**Fix:** Record `_trigger_frame = Engine.get_physics_frames()` when the effect triggers. In `try_spawn_shards()`, if `_has_triggered` is already true AND the current physics frame equals `_trigger_frame`, return `true` (absorb the hit). This absorbs all same-frame burst hits without any timer, and does not affect hits from subsequent frames.

```gdscript
func try_spawn_shards(current_health: int) -> bool:
    # Absorb all hits on the same physics frame as the trigger (grenade burst fix).
    if _has_triggered and Engine.get_physics_frames() == _trigger_frame:
        return true
    if _has_triggered:
        return false
    if current_health > HP_THRESHOLD:
        return false
    _has_triggered = true
    _trigger_frame = Engine.get_physics_frames()
    _spawn_shards()
    _remove_armor_visual()
    return true
```

The pattern is confirmed across 4 separate grenade encounters in the log (lines 815–824, 3586–3595, 6511–6524, 9062–9075), each showing the same 3-hit burst killing the enemy after armored skin triggered.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/components/enemy_armored_skin_component.gd` | `try_spawn_shards` returns `bool`, adds `_has_triggered`+`_trigger_frame` flags, absorbs same-frame burst hits, adds `_remove_armor_visual()` |
| `scripts/objects/enemy.gd` | Return early when `try_spawn_shards` returns `true` |
| `tests/unit/test_enemy_armored_skin.gd` | Add tests: single-trigger guarantee, visual removal, second-hit damage applied, same-frame burst absorption |
| `docs/case-studies/issue-1143/game_log_20260318_075312.txt` | Game log from bug report by Jhon-Crow (2026-03-18, Bug 2) |
| `docs/case-studies/issue-1143/game_log_20260318_080738.txt` | Game log from bug report by Jhon-Crow (2026-03-18, Bug 4) |
