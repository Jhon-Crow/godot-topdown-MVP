# Case Study: Issue #1334 — Game crashes on restart at DocksLevel (sniper death)

## Issue Summary

**Title:** игра вылетает при перезапуске на карте Доки (Game crashes on restart on the Docks map)
**Reported condition:** Crash occurs especially when dying from a sniper shot.
**Evidence:** `game_log_20260322_164021.txt` — 9143-line game log that ends abruptly mid-frame.

## Timeline Reconstruction

| Time | Event | Log Line |
|------|-------|----------|
| 16:41:43 | Player enters DocksLevel (20 enemies, including ContainerYardA_Sniper) | 4959 |
| 16:42:10 | ContainerYardA_Rifle2 fires at player | 9084 |
| 16:42:10 | Player spawns blood effect, `lethal=True` | 9087 |
| 16:42:10 | PenultimateHit reports `current health: 0.0` | 9089 |
| 16:42:10 | CinemaEffects triggers death effects | 9091–9092 |
| 16:42:10 | PenultimateHit/LastChance register player death | 9093–9094 |
| 16:42:10 | **ContainerYardA_Sniper hitscan deals 50 damage to already-dead player** | 9095 |
| 16:42:11 | Log continues for ~48 more lines (enemy AI, blood decals) | 9096–9143 |
| — | **Log ends abruptly — game crashed** | 9143 |

## Root Cause Analysis

### Primary crash vector: `Player.ShowHitFlash()` — async coroutine on freed node

When the player takes lethal damage:

1. `Player.TakeDamage()` calls `ShowHitFlash()` (line 2588) **before** calling `base.TakeDamage()` which triggers death.
2. `ShowHitFlash()` is `async void` — it calls `await ToSignal(GetTree().CreateTimer(HitFlashDuration), "timeout")`.
3. The `Died` signal fires → `_on_player_died()` in the level script → `await 0.5s` → `GameManager.on_player_death()` → `restart_scene()` → `reload_current_scene()`.
4. Scene reload frees the old Player node.
5. When `ShowHitFlash()` resumes from the await, it calls `GetTree()` on a **disposed C# object** → `ObjectDisposedException` → engine crash.

### Secondary crash vector: `SniperRifle.FadeOutTracer()` — async coroutine

`FadeOutTracer()` runs `await ToSignal(GetTree(), "process_frame")` in a loop. If the SniperRifle weapon node is freed during scene reload while a tracer fade is still running, the same `ObjectDisposedException` occurs.

### Tertiary concern: Double restart

The sniper's hitscan fires on the same frame as the rifle shot that killed the player (log lines 9084 and 9095). While `Player.TakeDamage()` has an `IsAlive` guard that prevents double death, `GameManager.on_player_death()` had no guard against being called twice — so if two separate death code paths converged, `reload_current_scene()` could be called twice.

## Fixes Applied

### 1. `Player.ShowHitFlash()` — guard before and after await

```csharp
if (!IsInsideTree())
    return;
await ToSignal(GetTree().CreateTimer(HitFlashDuration), "timeout");
if (!IsInstanceValid(this) || !IsInsideTree())
    return;
```

### 2. `Player.FineMotorSkillsActivateAsync()` — same guard pattern

### 3. `SniperRifle.FadeOutTracer()` — guard inside animation loop

```csharp
if (!IsInstanceValid(this) || !IsInsideTree())
    return;
await ToSignal(GetTree(), "process_frame");
```

### 4. `SniperRifle._ExitTree()` — clear pending deferred shots

```csharp
_pendingSniperShots.Clear();
```

### 5. All level scripts `_on_player_died()` — guard after await

```gdscript
await get_tree().create_timer(0.5).timeout
if not is_inside_tree():
    return
GameManager.on_player_death()
```

Applied to: `docks_level.gd`, `city_level.gd`, `decadence_level.gd`, `labyrinth_level.gd`, `building_level.gd`, `castle_level.gd`, `beach_level.gd`, `test_tier.gd`, `factory_level.gd`, `revolver_level.gd`.

### 6. `GameManager.on_player_death()` — double-restart guard

```gdscript
if not player_alive:
    return
```

## Pattern: Async Use-After-Free in Godot

This is a recurring pattern in Godot C# and GDScript projects:

1. Node starts an `async void` / `await` coroutine.
2. Scene is reloaded or node is freed.
3. Coroutine resumes and accesses `GetTree()` / `get_tree()` on a freed object.
4. Engine crashes with `ObjectDisposedException` (C#) or silent null-reference crash (GDScript).

**Prevention:** Always guard `GetTree()` calls in async methods:
- **Before await:** `if (!IsInsideTree()) return;`
- **After await:** `if (!IsInstanceValid(this) || !IsInsideTree()) return;`

This pattern was previously identified and fixed in Issue #1323 (pedestal tween crash).
