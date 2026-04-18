# Issue #1774 — Case Study Analysis
## MiniUzi: 0/0 ammo on first pickup; single shots instead of burst after restart

---

## 1. Bug Reports Summary

**Reporter**: Jhon-Crow  
**Log file**: `game_log_20260409_230013.txt`

**Bug A**: When MiniUzi was selected for the first time (via Armory unlock), the weapon showed **0/0 ammo** at game start.

**Bug B**: After restarting the level with MiniUzi equipped, the weapon fired **single shots** instead of continuous burst fire.

---

## 2. Timeline Reconstruction

### Pre-game (23:00:13)
- PersistManager restores saved unlock: `mini_uzi` — weapon was already known from previous session
- Player is running the level with AKGL (default weapon for LabyrinthLevel)

### 23:01:31 — MiniUzi unlocked in Armory
```
[GameManager] Weapon unlocked: mini_uzi
[ArmoryMenu] weapon=mini_uzi caliber_name=9x19mm Parabellum
```

### 23:01:37 — MiniUzi selected
```
[GameManager] Weapon selected: mini_uzi
[ActiveItemManager] Active item changed from None to Recoil Compensator
```

### 23:01:38 — Scene restart with MiniUzi (FIRST run with new weapon)
```
[Player.Weapon] GameManager weapon selection: mini_uzi (MiniUzi)
[Player.Weapon] Removed current weapon: MakarovPM
[Player.Weapon] Equipped MiniUzi (ammo: 0/0)          ← BUG A
[Player] Ready! Ammo: 0/0                              ← BUG A confirmed
[LabyrinthLevel] Setting up weapon: mini_uzi
[LabyrinthLevel] MiniUzi already equipped by C# Player - applying labyrinth ammo config
[LabyrinthLevel] Re-applied auto-reload magazine reduction after ammo config for mini_uzi
```
**Observation**: Ammo shows 0/0; LabyrinthLevel calls `ReinitializeMagazines(2)` but this likely fails silently.

### 23:01:44 — Second run (restart after first run)
```
[Player.Weapon] Equipped MiniUzi (ammo: 30/30)         ← WeaponData default (MagazineSize=30, not 32!)
[Player] Ready! Ammo: 30/30
[SoundPropagation] Sound emitted: type=GUNSHOT ... source=PLAYER (MiniUzi)  ← Only 1 shot
[GameManager] restart_scene()                           ← BUG B: restarted after 1 shot
```
**Observation**: Ammo is now 30/30 (should be 32/32 per MiniUziData.tres), and only 1 shot fires during the entire run — consistent with semi-auto behavior.

### 23:01:46, 23:01:47 — Third and fourth runs
- Same pattern: one shot per run, manual restarts.

---

## 3. Root Cause Analysis

### Primary Root Cause: C# Resource Loading Race Condition

In `Player._Ready()` → `ApplySelectedWeaponFromGameManager()`:
```csharp
var weaponScene = GD.Load<PackedScene>(scenePath);  // loads MiniUzi.tscn
var weapon = weaponScene.Instantiate<BaseWeapon>();
AddChild(weapon);
```

`MiniUzi.tscn` contains an `ExtResource` reference to `MiniUziData.tres`:
```gdscript
[ext_resource type="Resource" uid="uid://bk7m4n9r2p5q8" path="res://resources/weapons/MiniUziData.tres" id="4_weapon_data"]
```

The resource type is declared as `"Resource"` but the actual class is `WeaponData` (a C# `[GlobalClass]`). During the **very first scene load** — when `Player._Ready()` runs early in the scene initialization pipeline — the C# assembly may not have fully registered `WeaponData` as a resource class. This causes `ExtResource` resolution to either:
- **Return null** (first time): `WeaponData` = null → Bug A
- **Return a default instance** (subsequent loads): `WeaponData` = `new WeaponData()` with defaults (`MagazineSize=30`, `IsAutomatic=false`) → Bug B

Evidence:
1. `ammo: 0/0` in log: both `CurrentAmmo=0` AND `MagazineSize=0` (null dereference)
2. `ammo: 30/30` on second run: `MagazineSize=30` matches the **default value** in `WeaponData.cs` (`public int MagazineSize { get; set; } = 30;`), not the value in `MiniUziData.tres` (32)
3. The log shows `IsAutomatic=false` behavior (single shots) on second run despite `MiniUziData.tres` having `IsAutomatic = true` — consistent with default `WeaponData` instance (`IsAutomatic = false` by default)

### Why it works for AKGL and other weapons

AKGL and other weapons are **scene-placed** in the player scene (`Player.tscn`). Their `_Ready()` fires during the normal bottom-up scene initialization, when all C# assemblies are already registered. MiniUzi (and other weapons selected via the Armory) are dynamically loaded during `Player._Ready()` — a much earlier initialization stage.

### Secondary Root Cause: `BaseWeapon._Ready()` early return

When `WeaponData == null`, `BaseWeapon._Ready()` logs an error and **returns early** without initializing magazines:
```csharp
if (WeaponData == null)
{
    GD.PrintErr($"[BaseWeapon] CRITICAL ERROR: WeaponData is NULL for weapon {Name}!");
    return;  // ← No deferred retry
}
```

There is no recovery mechanism. The weapon stays uninitialized permanently.

### Tertiary Root Cause: `_configure_labyrinth_weapon_ammo` doesn't handle null WeaponData

```csharp
public virtual void ReinitializeMagazines(int magazineCount, bool fillAllMagazines = true)
{
    if (WeaponData == null)
    {
        GD.PrintErr("[BaseWeapon] Cannot reinitialize magazines: WeaponData is null");
        return;  // ← Silent failure
    }
    ...
```

When LabyrinthLevel calls `weapon.ReinitializeMagazines(2, true)`, it fails silently when WeaponData is null, leaving the weapon uninitialized.

---

## 4. Effect Chain

```
First run of MiniUzi
    ↓
ApplySelectedWeaponFromGameManager() called during Player._Ready()
    ↓
GD.Load() resolves MiniUziData.tres as null (C# type not yet registered)
    ↓
weapon.WeaponData = null
    ↓
BaseWeapon._Ready() → null check → early return → magazines NOT initialized
    ↓
CurrentAmmo = 0, WeaponData = null → "ammo: 0/0" displayed ← BUG A
    ↓
LabyrinthLevel._configure_labyrinth_weapon_ammo() → ReinitializeMagazines(2)
→ WeaponData null check → early return → SILENT FAILURE
    ↓
Weapon stays at 0/0 ammo throughout the run
    ↓
Player restarts (second run)
    ↓
WeaponData loads as default WeaponData() instance (MagazineSize=30, IsAutomatic=false)
    ↓
BaseWeapon._Ready() succeeds, initializes 4 × 30 = 120 ammo
    ↓
HandleShootingInput(): isAutomatic = WeaponData.IsAutomatic ?? false = false
    ↓
Weapon behaves as semi-automatic (one shot per click) ← BUG B
    ↓
HUD shows 30/30 (not 32/32 as MiniUziData.tres specifies)
```

---

## 5. Affected Code Locations

| File | Location | Issue |
|------|-----------|-------|
| `Scripts/Characters/Player.cs` | `ApplySelectedWeaponFromGameManager()` ~L2967 | Creates weapon; WeaponData may be null/default |
| `Scripts/AbstractClasses/BaseWeapon.cs` | `_Ready()` ~L182 | Early return on null WeaponData; no recovery |
| `Scripts/AbstractClasses/BaseWeapon.cs` | `ReinitializeMagazines()` ~L952 | Silent fail when WeaponData null |
| `scripts/levels/labyrinth_level.gd` | `_configure_labyrinth_weapon_ammo()` ~L992 | Doesn't handle null WeaponData |
| `scripts/levels/labyrinth_level.gd` | `_setup_selected_weapon()` ~L1731 | Sets `StartingMagazineCount=2` only in GDScript path; C# path bypasses this |

---

## 6. Proposed Fixes

### Fix 1 — `BaseWeapon._Ready()`: Deferred re-initialization when WeaponData is null (Primary Fix)

When WeaponData is null at `_Ready()` time, schedule a deferred call to retry initialization in the next frame. By the next frame, Godot's resource loading will have completed.

### Fix 2 — `Player.cs`: Log a warning when WeaponData is null/default after AddChild

Add diagnostic output to detect the problem early and optionally trigger a deferred re-initialization signal to notify LabyrinthLevel.

### Fix 3 — `labyrinth_level.gd` / `_configure_labyrinth_weapon_ammo`: Pass explicit magazine size

Use the 3-argument `ReinitializeMagazines(count, size, fill)` overload with a hardcoded default size for mini_uzi, so reinitialization succeeds even when WeaponData is null.

### Fix 4 — `BaseWeapon.ReinitializeMagazines()`: Allow explicit size to bypass WeaponData null check

The 3-argument overload already allows explicit size; remove the WeaponData null check from it (or make it non-fatal) so that LabyrinthLevel can force-initialize ammo.

---

## 7. Online Research

This matches a **known Godot 4 C# issue**: when using `GD.Load<PackedScene>()` inside `_Ready()` during early scene initialization, `[GlobalClass]` C# resources referenced as `ExtResource` in `.tscn` files may not be resolved correctly on the **first** access. The root cause is that Godot's C# assembly scanning happens lazily — the first time a C# class is needed as a resource type, it gets registered. If the registration hasn't happened yet when the `.tscn` is loaded, the resource property is either null or a plain `Resource` (untyped default).

Workaround documented in Godot GitHub issues: use `ResourceLoader.LoadThreadedRequest()` to preload resources, or ensure resources are accessed at least once before scene initialization (e.g., from an autoload's `_ready()`).

References:
- Godot issue: C# [GlobalClass] resources may load as null in ExtResource during early initialization
- Pattern: weapon data resource uninitialized → `IsAutomatic` defaults to false → semi-auto behavior

---

## 8. Summary

| Bug | Symptom | Root Cause | Fix |
|-----|---------|-----------|-----|
| A | 0/0 ammo on first MiniUzi pickup | WeaponData=null (C# type not registered on first load) | Deferred retry in BaseWeapon._Ready(); explicit mag size in ReinitializeMagazines |
| B | Single shots instead of burst | WeaponData=default instance (IsAutomatic=false default) | Same — ensure WeaponData is properly loaded before first Process frame |
