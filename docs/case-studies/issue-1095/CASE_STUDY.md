# Case Study: Issue #1095 — Armored Skin: Explosion Damage Not Absorbed

## Summary

Issue #1095 reports that when the Armored Skin passive item triggers (shards spawn), the damage that caused the trigger should be fully ignored — **including explosion damage**. PR #1046 fixed the basic case for single-hit projectiles, but multi-hit explosion damage (which calls `on_hit_with_info` in a loop) still kills the player after the shards spawn.

---

## Issue Description (Original, Russian)

> предмет добавлен в https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1046
>
> любой урон, вызвавший осколки должен игнорироваться (в том числе урон от взрывов).

Translation: "The item was added in PR #1046. Any damage that caused shards to spawn should be ignored (including explosion damage)."

---

## Timeline of Events

| Time | Event |
|---|---|
| Before PR #1046 | Armored Skin not implemented in C# at all |
| 2026-03-17 | PR #1046 merged — Armored Skin implemented in `Player.cs` |
| 2026-03-17 | Issue #1095 filed — explosion damage still kills the player after shards spawn |

---

## Root Cause Analysis

### The Problem: Multi-Hit Explosion Loops Bypass the Absorption

The Armored Skin in `Player.cs::TakeDamage()` (line 2504) works correctly for single-hit projectiles:

```csharp
if (_armoredSkinActive && HealthComponent.CurrentHealth <= 2)
{
    _armoredSkinActive = false;
    SpawnArmoredSkinShards();
    // Absorb the hit — triggering projectile deals no damage
    return;
}
```

**However**, explosion damage (`GrenadeTimer.ApplyDamage()`) calls `on_hit_with_info()` in a loop:

```csharp
private void ApplyDamage(Node2D target, Vector2 explosionPosition)
{
    Vector2 hitDirection = (target.GlobalPosition - explosionPosition).Normalized();
    if (target.HasMethod("on_hit_with_info"))
    {
        for (int i = 0; i < ExplosionDamage; i++)  // ExplosionDamage = 99 by default
        {
            target.Call("on_hit_with_info", hitDirection, (GodotObject?)null);
        }
    }
    ...
}
```

**Sequence of events when player (HP ≤ 2) is hit by an explosion:**

1. Call 1 (`on_hit_with_info` → `TakeDamage(1)`):
   - `_armoredSkinActive` is `true`, HP ≤ 2 → **trigger fires**
   - Sets `_armoredSkinActive = false`
   - Spawns 20 shards
   - **Returns early** (absorbs this hit) ✓

2. Calls 2–99 (`on_hit_with_info` → `TakeDamage(1)`):
   - `_armoredSkinActive` is now `false`
   - Falls through to `base.TakeDamage(amount)`
   - **Deals damage normally, kills player** ✗

The same pattern applies to `BreakerDetonation.ApplyDamage()` which also loops `ExplosionDamage` times.

### Why Projectile Hits Don't Have This Problem

A single projectile hit calls `on_hit_with_info` exactly once. The first call triggers the armor, absorbs the damage, and returns. There are no subsequent calls.

### The Issue Is "Trigger Once Per Damage Event"

The armored skin is designed to absorb "the hit that caused it to trigger." For explosion sources, that means absorbing **all** the looped `on_hit` calls from that single explosion event — not just the first one.

---

## Affected Code Paths

| Source | File | Method | Loop Count |
|---|---|---|---|
| Frag grenade (timer) | `Scripts/Projectiles/GrenadeTimer.cs` | `ApplyDamage()` | `ExplosionDamage` (99) |
| Frag grenade (GDScript) | `scripts/projectiles/frag_grenade.gd` | loop | `explosion_damage` |
| Breaker bullet | `Scripts/Projectiles/BreakerDetonation.cs` | `ApplyDamage()` | `ExplosionDamage` |
| Enemy grenade | `scripts/components/enemy_grenade_component.gd` | loop | damage count |
| Grenadier grenade | `scripts/components/grenadier_grenade_component.gd` | loop | damage count |
| Single projectile | `scripts/objects/hit_area.gd` | `on_hit` | 1 (no issue) |

---

## Proposed Solution

Add a short-term **post-trigger immunity** flag `_armoredSkinImmune` to `Player.cs`. When the armored skin triggers:
1. Set `_armoredSkinImmune = true`
2. Spawn shards
3. Return early (absorb the first hit)
4. While `_armoredSkinImmune` is `true`, all subsequent `TakeDamage()` calls also return early
5. After a brief delay (e.g., 0.1 seconds), reset `_armoredSkinImmune = false`

This 0.1s window is sufficient to cover all calls from a single explosion loop (which executes synchronously within one frame), while short enough to not cause unintended invincibility.

### Alternative: Absorb Based on Same Frame

Since explosion loops execute synchronously within one C# call stack (no await, no coroutines), `_armoredSkinImmune` could also be reset at the start of the next `_Process()` or `_PhysicsProcess()` tick — meaning it only covers the current frame. This is even cleaner but requires tracking frame number.

The timer-based approach is simpler and self-contained.

---

## Fix Implementation

In `Scripts/Characters/Player.cs`, within the `#region Armored Skin System (Issue #1045)`:

1. Add field: `private bool _armoredSkinImmune = false;`
2. In `TakeDamage()`, after the existing armored skin trigger check, add immunity check
3. When shards spawn, start a 0.1s SceneTreeTimer to reset `_armoredSkinImmune`

```csharp
// After existing trigger logic:
if (_armoredSkinActive && HealthComponent.CurrentHealth <= 2)
{
    _armoredSkinActive = false;
    _armoredSkinImmune = true;
    SpawnArmoredSkinShards();
    // Start timer to clear immunity after 0.1s
    GetTree().CreateTimer(0.1f).Timeout += () => _armoredSkinImmune = false;
    return;
}

// Absorb damage while immunity is active (covers multi-hit explosion loops)
if (_armoredSkinImmune)
{
    return;
}
```
