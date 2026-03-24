# Case Study: Issue #1105 — Auto-Reload Doesn't Work for MakarovPM and Shotgun

**Date:** 2026-03-17
**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1105
**PR:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1106
**Related:** Issue #1067 (Auto-reload passive item implementation), PR #1068

---

## Problem Statement

After the auto-reload passive item was implemented (PR #1068, merged 2026-03-17), two weapons
still do not trigger the kill-based magazine refill:

1. **Makarov PM (ПМ)** — 9-round semi-automatic pistol, starting weapon
2. **Shotgun (Дробовик)** — Pump-action shotgun with tube magazine, 8-shell capacity

In both cases, the game log consistently shows:
```
[Player.AutoReload] Kill — magazine already full, no refill needed
```
…even when the player had clearly fired multiple shots before the kill.

---

## Game Log Analysis

**File:** `game_log_20260317_123619.txt`

### MakarovPM section (around 12:37:45)

```
[Player.AutoReload] Reducing magazine size: 9 -> 4, magazines: 4 -> 9 (total bullets preserved: 36)
[Player] Ready! Ammo: 4/9, Grenades: 1/3, Health: 10/10
[BuildingLevel] Setting up weapon: makarov_pm
... (4 shots fired) ...
[Player.AutoReload] Kill — magazine already full, no refill needed
```

**Key observation:** `Ammo: 4/9` means `CurrentAmmo=4, WeaponData.MagazineSize=9`. After reduction,
`_autoReloadMagazineSize=4`. The player fires 4 shots → `CurrentAmmo=0`. But no log shows
`ApplyAutoReloadAfterLevelAmmoConfig` being called for `makarov_pm`!

That means `_configure_makarov_pm_ammo()` called `ReinitializeMagazines(10, true)`, which reset
`CurrentAmmo` back to `9` (the original magazine size). Then `needed = 4 - 9 = -5 ≤ 0` → "full".

### Shotgun section (around 12:38:49)

```
[Player.AutoReload] Reducing magazine size: 8 -> 3, magazines: 4 -> 11 (total bullets preserved: 32)
[Player] Ready! Ammo: 3/8, Grenades: 1/3, Health: 10/10
[BuildingLevel] Shotgun already equipped by C# Player - applying building-level ammo config
[Player.AutoReload] Re-applying magazine size reduction after level ammo config
[Player.AutoReload] Reducing magazine size: 8 -> 3, magazines: 4 -> 11 (total bullets preserved: 32)
... (shot fired, kill) ...
[Player.AutoReload] Kill — magazine already full, no refill needed
```

**Key observations:**
1. `ApplyAutoReloadAfterLevelAmmoConfig` IS called for Shotgun — the auto-reload reduction is applied.
2. After `ReinitializeMagazines(11, 3)`: the base class sets `CurrentAmmo=3` in `CurrentMagazine`.
3. The kill handler uses `CurrentWeapon.CurrentAmmo` — which is `3`, equal to `magazineCapacity=3`.
4. `needed = 3 - 3 = 0` → "magazine already full".
5. But `ShellsInTube` was `3` and decreased to `2` after the shot — never refilled!

Additionally, `totalBullets` used `StartingMagazineCount * MagazineSize = 4 * 8 = 32`, but the
Shotgun only has 8 (tube) + 12 (reserve) = 20 real shells. This created ammo from thin air.

---

## Root Cause Analysis

### Root Cause A: MakarovPM — `_configure_makarov_pm_ammo` Missing Auto-Reload Reapplication

**File:** `scripts/levels/building_level.gd`
**Function:** `_configure_makarov_pm_ammo()`

The BuildingLevel gives MakarovPM 2.5× more magazines (Issue #636). It calls:
```gdscript
weapon.ReinitializeMagazines(pm_magazines, true)  # resets CurrentAmmo to 9 (original!)
```
But unlike `_apply_building_ammo_config()` (which handles other weapons like M16/AK/UZI),
`_configure_makarov_pm_ammo()` did **not** call `ApplyAutoReloadAfterLevelAmmoConfig()` afterwards.

**Execution order:**
1. `Player._Ready()` → `ReduceMagazineSizeForAutoReload()` → `CurrentAmmo = 4`, `_autoReloadMagazineSize = 4`
2. `BuildingLevel._Ready()` → `_configure_makarov_pm_ammo()` → `ReinitializeMagazines(10)` → `CurrentAmmo = 9` (**overwrites!**)
3. `OnEnemyKilledForAutoReload()`: `needed = 4 - 9 = -5` → skipped

**Affected levels:** Building Level (the only level with this code path not having the fix)

All other levels (`beach_level.gd`, `castle_level.gd`, `decadence_level.gd`, `docks_level.gd`,
`labyrinth_level.gd`, `test_tier.gd`) already had `ApplyAutoReloadAfterLevelAmmoConfig()` in their
`_configure_makarov_pm_ammo()` functions — Building Level was the sole exception.

### Root Cause B: Shotgun — `CurrentAmmo` Always 0 (Tube Magazine Model)

**File:** `Scripts/Weapons/Shotgun.cs`

The Shotgun uses a **tube magazine** model, not a standard detachable magazine:
- **`ShellsInTube`**: actual shells ready to fire (primary ammo counter)
- **`CurrentMagazine.CurrentAmmo`**: placeholder, always 0 (reserve shells are in spare magazines)

When `ReinitializeMagazines(count, size)` is called by the auto-reload system, the base
`BaseWeapon.ReinitializeMagazines()` sets `CurrentMagazine.CurrentAmmo = size`. The Shotgun
had no override to reset it back to 0 afterwards.

**Kill handler bug:**
```csharp
int currentAmmo = CurrentWeapon.CurrentAmmo;  // = 3 (set by base, should be 0!)
int needed = magazineCapacity - currentAmmo;  // = 3 - 3 = 0 → "already full"
// ShellsInTube is never checked! It was 2 after firing.
```

### Root Cause C: Shotgun — `ShellsInTube` Never Reduced

**File:** `Scripts/Characters/Player.cs`

`ReduceMagazineSizeForAutoReload()` calls `ReinitializeMagazines(newCount, reducedSize)` which
only modifies the `MagazineInventory` (reserve shells). `ShellsInTube` and `TubeMagazineCapacity`
are separate fields — they were never updated. So:
- `TubeMagazineCapacity = 8` (original)
- `ShellsInTube = 8` (original, full)
- `_autoReloadMagazineSize = 3` (reduced)

Even if kill handler checked `ShellsInTube`: `needed = 3 - 8 = -5` → still "already full".

### Root Cause D: Shotgun — Total Ammo Calculation Inflates Reserve

**File:** `Scripts/Characters/Player.cs`

`totalBullets = StartingMagazineCount * originalSize = 4 * 8 = 32`

But Shotgun's actual ammo is `TubeMagazineCapacity + ReserveAmmo = 8 + 12 = 20`.
Using `StartingMagazineCount = 4` (the base class default, not overridden by Shotgun)
created 12 extra shells from thin air (32 → 20 should be).

---

## Timeline

| Time | Event |
|------|-------|
| 2026-03-17 12:07 | PR #1068 merged with auto-reload implementation for all weapons |
| 2026-03-17 12:36 | Player starts new game session with auto-reload active |
| 2026-03-17 12:37:45 | Auto-reload applied to MakarovPM, but BuildingLevel resets it |
| 2026-03-17 12:38:49 | Auto-reload applied to Shotgun, but ShellsInTube never reduced |
| 2026-03-17 12:36-12:40 | All PM and Shotgun kills log "magazine already full" |
| 2026-03-17 (later) | Issue #1105 filed with game log attached |

---

## Fixes Implemented

### Fix 1: MakarovPM — `building_level.gd`

Added `ApplyAutoReloadAfterLevelAmmoConfig()` call inside `_configure_makarov_pm_ammo()`,
matching the existing pattern in `_apply_building_ammo_config()`:

```gdscript
if weapon.has_method("ReinitializeMagazines"):
    weapon.ReinitializeMagazines(pm_magazines, true)
    # NEW: re-apply auto-reload reduction after resetting magazine size
    if _player != null and _player.has_method("ApplyAutoReloadAfterLevelAmmoConfig"):
        _player.ApplyAutoReloadAfterLevelAmmoConfig()
```

### Fix 2: Shotgun — Override `ReinitializeMagazines` (`Shotgun.cs`)

Added override to keep `CurrentMagazine.CurrentAmmo = 0` after the base call:

```csharp
public override void ReinitializeMagazines(int magazineCount, int magazineSize, bool fillAllMagazines = true)
{
    base.ReinitializeMagazines(magazineCount, magazineSize, fillAllMagazines);
    // Shotgun always keeps CurrentMagazine at 0 — ShellsInTube is the real ammo
    if (MagazineInventory.CurrentMagazine != null)
        MagazineInventory.CurrentMagazine.CurrentAmmo = 0;
}
```

### Fix 3: Shotgun — Add `SetAutoReloadTubeCapacity()` (`Shotgun.cs`)

New public method to reduce `TubeMagazineCapacity` and trim `ShellsInTube`:

```csharp
public void SetAutoReloadTubeCapacity(int newCapacity)
{
    TubeMagazineCapacity = newCapacity;
    if (ShellsInTube > TubeMagazineCapacity)
        ShellsInTube = TubeMagazineCapacity;
    EmitSignal(SignalName.ShellCountChanged, ShellsInTube, TubeMagazineCapacity);
}
```

Called from `Player.ReduceMagazineSizeForAutoReload()` after the magazine count reduction.

### Fix 4: Shotgun — Add `AutoRefillTube()` (`Shotgun.cs`)

New public method to instantly refill the tube from reserve (used by kill handler):

```csharp
public int AutoRefillTube(int count)
{
    // adds 'count' shells to ShellsInTube from SpareMagazines, returns actual added
}
```

### Fix 5: Shotgun — Kill Handler Uses `ShellsInTube` (`Player.cs`)

Updated `OnEnemyKilledForAutoReload()` to handle Shotgun via dedicated path:

```csharp
if (CurrentWeapon is Shotgun shotgun)
{
    int needed = magazineCapacity - shotgun.ShellsInTube;
    if (needed > 0 && shotgun.ReserveAmmo > 0)
        shotgun.AutoRefillTube(Math.Min(needed, shotgun.ReserveAmmo));
    return;
}
```

### Fix 6: Shotgun — Correct Total Ammo Calculation (`Player.cs`)

Fixed `totalBullets` for Shotgun to use actual ammo, not `StartingMagazineCount × MagazineSize`:

```csharp
if (CurrentWeapon is Shotgun shotgunForAmmoCalc)
    totalBullets = shotgunForAmmoCalc.ShellsInTube + CurrentWeapon.ReserveAmmo;  // 8+12=20
else
    totalBullets = currentMagazineCount * originalSize;  // standard weapons
```

### Fix 7: Auto-Reload Icon (`assets/sprites/weapons/auto_reload_icon.png`)

Created a 64×64 RGBA minimalist icon: brass bullet with teal circular reload arrow,
matching the visual style of existing passive item icons.

---

## Verification

After the fixes, expected log output for Shotgun:

```
[Player.AutoReload] Reducing magazine size: 8 -> 3, magazines: ? -> 7 (total bullets preserved: 20)
[Player.AutoReload] Shotgun TubeMagazineCapacity updated to 3
[Shotgun.AutoReload] SetAutoReloadTubeCapacity: TubeMagazineCapacity=3, ShellsInTube=3
... (2 shots fired, ShellsInTube = 1) ...
[Player.AutoReload] Kill — refilled 2 shells (1 -> 3/3), reserve: 16
```

Expected log output for MakarovPM:

```
[BuildingLevel] Re-applied auto-reload magazine reduction after ammo config for makarov_pm
[Player.AutoReload] Re-applying magazine size reduction after level ammo config
[Player.AutoReload] Reducing magazine size: 9 -> 4, magazines: 10 -> 9 (total bullets preserved: 90)
... (3 shots fired, CurrentAmmo = 1) ...
[Player.AutoReload] Kill — refilled 3 rounds (1 -> 4/4), reserve: 32
```

---

## Post-Fix FPS Performance Analysis

**Date:** 2026-03-17
**Log file:** `game_log_20260317_131649.txt` (owner's session after PR #1106 fix)
**Owner query:** "вроде норм, проверить нет ли просадок fps из за нового функционала"
(Translation: "seems okay, check if there are FPS drops from the new functionality")

### Comparison: Before Fix vs After Fix

| Metric | Before Fix (game_log_20260317_123619.txt) | After Fix (game_log_20260317_131649.txt) |
|--------|------------------------------------------|------------------------------------------|
| FPS drops | 20 total | 91 total |
| Average FPS during drops | 26.1 fps | 12.6 fps |
| Min FPS | 1 fps | 2 fps |
| Max FPS | 29 fps | 29 fps |
| Debug mode | `false` | `true` |
| Session duration | ~4 min | ~2.3 min |
| Drops per minute | ~5 | ~40 |

### Root Cause of FPS Drops: Debug Mode, Not Auto-Reload

The critical difference between the two sessions is **Debug mode**:
- Old log: `Debug: false` (line 39)
- New log: `Debug: true` (line 39)

With Debug mode enabled, the game emits **extremely verbose enemy AI logging** every frame:
- `ROT_CHANGE: P3:corner -> P4:velocity, ...` (every 0.3s per enemy)
- `PATROL corner check: angle X.X°` (multiple times per second per enemy)

With 10 enemies × multiple log entries per second = thousands of log writes per minute. These disk I/O operations on the main thread cause frame time spikes.

**Evidence:** The FPS drops happen uniformly throughout gameplay with 10 enemies (not specifically correlated with auto-reload events). In the region 13:17:37–13:17:44 (7 seconds), there are 7 FPS drops — all during active combat with 10 enemies logging AI decisions constantly.

### Auto-Reload Code Performance Profile

The auto-reload implementation performs only:
1. **On level load** (`InitAutoReload`): One-time scan of enemies group, O(n) signal connections
2. **On each kill** (`OnEnemyKilledForAutoReload`): 3-5 integer comparisons, one integer mutation
3. **On weapon config** (`ApplyAutoReloadAfterLevelAmmoConfig`): One magazine count calculation

None of these operations involve loops, scene tree traversal during gameplay, or significant computation. The `ConnectAutoReloadToEnemies()` call does traverse the scene tree once per level start, but this is batched with the rest of initialization and does not repeat during gameplay.

### Conclusion

The FPS drops in the post-fix session are caused by **Debug mode being enabled** (which generates massive verbose AI logging), NOT by the new auto-reload functionality. The auto-reload code itself has O(1) per-kill complexity and does not introduce any frame rate overhead during normal gameplay.

**To reproduce without FPS drops:** Disable Debug mode in ExperimentalSettings. The drops in old log (Debug: false) were minimal: mostly at level load transitions (1 drop per level start, avg 26 fps).

---

## Regression Test Coverage

Added to `tests/unit/test_auto_reload.gd`:

- `test_issue_1105_pm_reinit_overwrites_reduction` — PM kill refills correctly after fix
- `test_issue_1105_pm_without_fix_always_full` — Demonstrates the bug before fix
- `test_issue_1105_shotgun_tube_uses_shells_not_current_ammo` — Shotgun uses ShellsInTube
- `test_issue_1105_shotgun_tube_full_no_refill` — Shotgun: no refill when tube is full
- `test_issue_1105_shotgun_total_ammo_preserved` — Shotgun ammo calculation correctness
- `test_issue_1105_shotgun_kill_per_shot_no_manual_reload` — Core mechanic end-to-end
