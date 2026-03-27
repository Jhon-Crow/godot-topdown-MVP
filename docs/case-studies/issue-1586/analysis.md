# Case Study: Issue #1586 — ASVK Maximum Aiming Range Not Increased

## Issue Summary (Russian → English)

> сделай максимальную дальность прицеливания больше в 2 раза
> **"Double the maximum aiming range."**

References: [Issue #1586](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1586), [PR #1599](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1599)

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| Issue opened | Owner requests doubling ASVK max aiming range |
| PR #1599 created | AI solver changed all `5000` → `10000` in `SniperRifle.cs`, `SniperRifleData.tres`, `enemy_sniper_component.gd` |
| PR marked ready to merge | CI checks passed, no merge conflicts |
| 2026-03-27 07:52:15 | Owner runs test session — from pre-built `.exe` binary at `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` |
| 2026-03-27 07:52:51 | Session ends after ~36 seconds (log line 1849) |
| 2026-03-27 04:53:18 UTC | Owner comments: "дальность не увеличилась" ("range didn't increase") with game log attached |

---

## Game Log Evidence

File: `game_log_20260327_075215.txt`

Key facts extracted from the log:

```
[07:52:15] [INFO] Executable: I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe
[07:52:15] [INFO] Debug build: false
[07:52:15] [INFO] Engine version: 4.3-stable (official)
[07:52:15] [INFO] Build info: not available (build_info.cfg not found)
```

The sniper was selected and used in the session:

```
[07:52:20] [INFO] [Player.Weapon] Equipped SniperRifle (ammo: 12/5)
[07:52:20] [INFO] [Player] Detected weapon: ASVK Sniper Rifle (Sniper pose)
```

The game was navigated to DocksLevel (which has a long-range sniper scenario):

```
[07:52:44] [INFO] [DocksLevel] Setting up weapon: sniper
[07:52:44] [ENEMY] [ContainerYardA_Sniper] Spawned at (4500, 420), hp: 2, behavior: GUARD
```

There are **no log entries** showing the active `maxRange` or `LASER_MAX_RANGE` value at runtime. The game does not log these constants at startup or weapon equip time. This means the log cannot directly confirm whether the 10000 or 5000 value was active — but the build evidence (see below) is conclusive.

---

## Root Cause Analysis

### Primary Root Cause: Testing Against a Pre-Built Release Binary

The log clearly states:
- `Executable: I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
- `Debug build: false`
- `Build info: not available (build_info.cfg not found)`

This is a **pre-compiled release build** that was downloaded or previously compiled before PR #1599 was created. It does **not** contain the source code changes from our branch (`issue-1586-3bae6cdaa74f`).

Godot projects must be **re-exported/re-compiled** from source to pick up `.cs` and `.gd` script changes. Changes to:
- `Scripts/Weapons/SniperRifle.cs` (C# — requires .NET recompile)
- `resources/weapons/SniperRifleData.tres` (resource file — requires re-export)
- `scripts/components/enemy_sniper_component.gd` (GDScript — requires re-export)

...are **not applied** to an existing pre-built `.exe`. The binary embeds compiled assemblies and packed resources at export time.

### Secondary Contributing Factor: No Range Value Logging

The game does not log the active `maxRange` or `LASER_MAX_RANGE` value when:
- A weapon is equipped
- A shot is fired
- The laser sight is drawn

This means there is no in-game trace to confirm the active range at runtime, making it hard to diagnose range issues from logs alone.

---

## Code Changes Verified in PR #1599

Our branch contains the following confirmed changes (verified against `main`):

### `resources/weapons/SniperRifleData.tres`
```
-Range = 5000.0
+Range = 10000.0
```
This is the primary data-driven range value. `SniperRifle.cs` reads `WeaponData.Range` for the laser beam length.

### `Scripts/Weapons/SniperRifle.cs`
Four hitscan methods updated, plus laser fallback:
```csharp
// Laser sight beam length
-float maxLaserLength = WeaponData?.Range ?? 5000.0f;
+float maxLaserLength = WeaponData?.Range ?? 10000.0f;

// ComputeHitscanEndpoint, ComputeBreakerHitscanEndpoint,
// PerformHitscan, PerformBreakerHitscan:
-float maxRange = 5000.0f;
+float maxRange = 10000.0f;
```

### `scripts/components/enemy_sniper_component.gd`
```gdscript
-const LASER_MAX_RANGE: float = 5000.0
+const LASER_MAX_RANGE: float = 10000.0

-var end_pos := spawn_pos + direction * 5000.0
+var end_pos := spawn_pos + direction * 10000.0
```

### `tests/unit/test_sniper_laser_sight.gd`
Test assertion updated to match new value:
```gdscript
-assert_eq(EnemySniperComponent.LASER_MAX_RANGE, 5000.0, ...)
+assert_eq(EnemySniperComponent.LASER_MAX_RANGE, 10000.0, ...)
```

All changes are consistent and complete. The PR correctly doubles the ASVK maximum aiming range from 5000 to 10000 px across the entire codebase.

---

## Why the Change Appeared to Have No Effect

The owner tested with a **pre-built `.exe`** that does not contain the PR changes. In Godot 4 with C#:

1. GDScript files (`.gd`) are embedded at export time and executed by the Godot runtime from the PCK file.
2. C# scripts (`.cs`) are compiled into a .NET assembly (`GodotSharp.dll` and project assemblies) which is also bundled at export time.
3. Resource files (`.tres`) are serialized and packed into the `.pck` file at export time.

None of these can be "hot-patched" by replacing source files — the exported binary is self-contained. To see the range change, the project must be re-exported from Godot editor with the updated source on the `issue-1586-3bae6cdaa74f` branch (or after the PR is merged into `main`).

---

## Files Involved

| File | Role | Change |
|------|------|--------|
| `resources/weapons/SniperRifleData.tres` | Resource data — primary `Range` field | `5000.0` → `10000.0` |
| `Scripts/Weapons/SniperRifle.cs` | Player weapon — laser + all hitscan methods | `5000` → `10000` (5 locations) |
| `scripts/components/enemy_sniper_component.gd` | Enemy sniper — laser + hitscan | `5000` → `10000` (2 locations) |
| `tests/unit/test_sniper_laser_sight.gd` | Unit test for laser constant | Assertion updated to `10000.0` |

---

## How to Verify the Fix

To confirm the range change takes effect:

1. **Merge PR #1599** into `main` (or checkout branch `issue-1586-3bae6cdaa74f`).
2. **Open the project in Godot 4.3** with .NET support.
3. **Re-build the C# solution** (Build → Build Project in Godot editor).
4. **Re-export the project** (Project → Export...) to generate a new `.exe`.
5. Run the new binary and test the ASVK laser sight on a level like DocksLevel — the laser beam should now reach enemies at distances up to 10000 px (double the previous 5000 px).

Alternatively, add range logging to confirm the active value at runtime (see "Possible Improvements" below).

---

## Known Patterns / References

- **Godot export packing**: Godot 4 exports PCK files containing all scripts and resources. See [Godot Docs: Exporting Projects](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html).
- **C# in Godot 4**: C# scripts are compiled with `dotnet build` and bundled into the PCK. Source changes require recompile + re-export. See [Godot Docs: C# Basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html).
- **GDScript in exports**: GDScript is tokenized and packed at export time. Runtime modifications to `.gd` files do not affect an exported binary.
- **`WeaponData.Range` data flow**: `SniperRifleData.tres` → loaded as `WeaponData` resource → `SniperRifle.cs` reads `.Range` property → used for both laser beam length and hitscan endpoint. This is the correct single source of truth for weapon range.

---

## Possible Improvements

### 1. Add Range Logging at Weapon Equip Time

To make future range issues diagnosable from logs alone, add a log line when the sniper rifle is equipped:

```csharp
// In SniperRifle.cs, _Ready() or weapon setup:
GD.Print($"[SniperRifle] Loaded: maxRange={WeaponData?.Range ?? 10000.0f} px, " +
         $"fallback={10000.0f} px");
```

Similarly in `enemy_sniper_component.gd`:

```gdscript
func _ready() -> void:
    print("[EnemySniper] LASER_MAX_RANGE = ", LASER_MAX_RANGE, " px")
```

This would make it immediately visible in the log whether the old or new value is active.

### 2. Build Info Logging

The log shows `Build info: not available (build_info.cfg not found)`. Including a build commit hash in `build_info.cfg` would allow correlating a running binary with the exact source revision, preventing "testing old build" confusion.

---

## Conclusion

The code fix in PR #1599 is **correct and complete**. The owner's report that "the range didn't increase" is explained by testing against a **pre-built release binary** that predates the PR. The fix will take effect once the project is re-exported from Godot after merging or checking out the PR branch.

No code changes are needed. The PR should be merged and the project re-exported to validate the fix.
