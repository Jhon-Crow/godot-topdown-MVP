# Case Study: Issue #1453 — Armored Skin Does Not Protect Against Sniper Rifle

## Timeline / Sequence of Events

1. **Issue #1453 filed**: Player reports that Armored Skin passive item does not protect against sniper rifle one-shot.
2. **Initial fix attempt (PR #1468, commit `bd22c666`)**: Armored skin logic added to `scripts/characters/player.gd` (GDScript). `on_hit_with_bullet_info()` forwarding method added, and lethal-hit detection added to `on_hit_with_info()`. Tests written.
3. **Owner reports fix did not work** (2026-03-25, comment on PR #1468): Sniper still one-shots the player. Game log attached: `game_log_20260325_043705.txt`.
4. **Root cause identified** (this commit): The fix targeted the wrong file. All gameplay levels use the **C# player** (`scenes/characters/csharp/Player.tscn` → `Scripts/Characters/Player.cs`), not the GDScript player.

---

## Root Cause Analysis

### Finding 1: Wrong file was fixed

All level scenes (`LabyrinthLevel.tscn`, `CityLevel.tscn`, etc.) reference:
```
res://scenes/characters/csharp/Player.tscn
```
…which uses `Scripts/Characters/Player.cs`, **not** `scripts/characters/player.gd`.

The GDScript player at `scripts/characters/player.gd` is present in the repo but not referenced by any gameplay level. Any fix applied there has zero effect on the running game.

**Evidence from game log** (`game_log_20260325_043705.txt` lines 485-496):
```
[Player] Spawning blood effect at (150, 360), dir=(1, 0), lethal=True (C#)
[PenultimateHit] Player damaged: 4.0 damage, current health: 0.0
...
[Enemy] [SniperHitscan] Hit Player damage=50
```
The `(C#)` suffix in the blood effect log confirms it was the C# player that was hit. The `PenultimateHit` C# component logged damage **before** the sniper hitscan log entry — the C# `TakeDamage()` path was taken entirely, and the armored skin check failed silently.

### Finding 2: C# Player lacked `on_hit_with_bullet_info()`

The sniper hitscan component (`scripts/components/enemy_sniper_component.gd`, line 287) checks:
```gdscript
if hit_node.has_method("on_hit_with_bullet_info"):
    hit_node.call("on_hit_with_bullet_info", direction, caliber, false, hit_walls > 0, damage)
elif hit_node.has_method("TakeDamage"):
    hit_node.call("TakeDamage", damage)
```

The C# `Player.cs` only had `on_hit()` and `on_hit_with_info()`. `has_method("on_hit_with_bullet_info")` returned `false`, so the fallback `TakeDamage(50)` was called **directly** — bypassing all hit-direction tracking and, crucially, any armored-skin check that depended on the damage value.

### Finding 3: C# `TakeDamage()` armored skin condition was incomplete

Even after the direct `TakeDamage(50)` call, the C# armored skin check only fired at `HealthComponent.CurrentHealth <= 2`:
```csharp
if (_armoredSkinActive && HealthComponent.CurrentHealth <= 2)
```

With the sniper dealing 50 damage, a player at 3, 4, or 5 HP would have `CurrentHealth > 2`, so the condition was `false`, the armor would not trigger, and the player would die.

---

## Fix Applied

### `Scripts/Characters/Player.cs`

**1. Added `on_hit_with_bullet_info()` method** (after `on_hit_with_info()`):
```csharp
public void on_hit_with_bullet_info(Vector2 hitDirection, Godot.Resource? caliberData,
    bool hasRicocheted, bool hasPenetrated, float damage = 1.0f, bool isFromPlayer = false)
{
    _lastHitDirection = hitDirection;
    _lastCaliberData = caliberData;
    TakeDamage(damage);
}
```
This ensures the sniper hitscan uses the correct code path with explicit damage value (50), instead of falling back to `TakeDamage(50)` that bypasses direction tracking.

**2. Fixed armored skin trigger condition in `TakeDamage()`**:
```csharp
// Before (Issue #1045 only):
if (_armoredSkinActive && HealthComponent.CurrentHealth <= 2)

// After (Issue #1453 fix):
if (_armoredSkinActive && (HealthComponent.CurrentHealth <= 2 || HealthComponent.CurrentHealth - amount <= 0))
```
Now triggers when HP is at/below threshold **OR** when the hit would be lethal at any HP.

---

## Why the GDScript Fix Was Not Sufficient

The repo has a dual-implementation architecture:
- `scripts/characters/player.gd` — GDScript player, used only by the Tutorial level
- `Scripts/Characters/Player.cs` + `Scripts/Characters/Player.ActiveItems.cs` — C# player, used by all other levels

Any gameplay fix must be applied to the C# implementation. The GDScript fix is now also correct (matching behavior), but has no runtime effect on the levels where snipers appear.

---

## Logs

- `game_log_20260325_043705.txt` — original game log from owner showing sniper one-shot with Armored Skin equipped

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1453
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1468
- `enemy_sniper_component.gd` line 287 — hitscan hit dispatch logic
- `Scripts/Characters/Player.cs` lines 2629-2640 — armored skin trigger in `TakeDamage()`
