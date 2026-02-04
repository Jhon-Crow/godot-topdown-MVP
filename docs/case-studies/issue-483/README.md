# Case Study: Issue #483 - Missing data_GodotTopDownTemplate_windows_x86_64 Folder

## Overview

**Issue**: The compiled Windows executable doesn't run because the `data_GodotTopDownTemplate_windows_x86_64` folder is missing from the build archive.
**Title** (Russian): "fix пропала папка data_GodotTopDownTemplate_windows_x86_64 после последнего merge"

## Timeline of Events

### 2026-02-04 06:50 UTC - Last Working Build
- **Run ID**: 21661640596
- **Commit**: cb58973cf90326938ec735f73642205a5cbe6caf
- **Artifact contents**: 228 files (exe + data folder with .NET assemblies)
- **Archive size**: ~68 MB

### 2026-02-04 13:10 UTC - First Broken Build
- **Run ID**: 21672723671
- **Commit**: 6490fa70be9bda0ee3d94ce88fe21cd0ff84776a (after PR #474 merge)
- **Artifact contents**: 1 file (exe only)
- **Archive size**: ~97 MB
- **Missing**: `data_GodotTopDownTemplate_windows_x86_64` folder

### Between the builds
The following commits were merged via PR #474 (Issue #468):
- `48a3797` - Fix muzzle flash not respecting caliber effect_scale
- `1a8fea4` - Reduce 9x19mm muzzle flash to 2x smaller than M16

## Root Cause Analysis

### The Problem: Method Signature Mismatch

PR #474 changed the signature of `BaseWeapon.SpawnMuzzleFlash()`:

**Before (working):**
```csharp
protected virtual void SpawnMuzzleFlash(Vector2 position, Vector2 direction)
```

**After (PR #474):**
```csharp
protected virtual void SpawnMuzzleFlash(Vector2 position, Vector2 direction, Resource? caliber)
```

### The Bug: Override Methods Not Updated

Two weapon classes had `override` methods with the old signature:

1. **SilencedPistol.cs:732**
```csharp
protected override void SpawnMuzzleFlash(Vector2 position, Vector2 direction)  // ERROR: no matching base method
```

2. **Shotgun.cs:1416** (call site)
```csharp
SpawnMuzzleFlash(muzzleFlashPosition, fireDirection);  // ERROR: missing required parameter
```

### C# Compiler Error

When Godot attempts to export the project, the C# build fails with:
```
error CS0115: 'SilencedPistol.SpawnMuzzleFlash(Vector2, Vector2)': no suitable method found to override
error CS7036: There is no argument given that corresponds to the required parameter 'caliber'
```

### Why the Export "Succeeds" but EXE Doesn't Run

The key insight from the build logs:

**Working build (21661640596):**
```
dotnet_publish_project: begin: Publishing .NET project... steps: 1
dotnet_publish_project: step 0: Running dotnet publish
dotnet_publish_project: end
savepack: begin: Packing steps: 102
```

**Broken build (21672723671):**
```
dotnet_publish_project: begin: Publishing .NET project... steps: 1
dotnet_publish_project: step 0: Running dotnet publish
dotnet_publish_project: end
ERROR: Failed to export project: Failed to build project.
savepack: begin: Packing steps: 102
```

The export process:
1. Attempts to build .NET project (`dotnet publish`)
2. If .NET build fails, logs error but **continues** with PCK packaging
3. Creates exe with embedded PCK (game assets)
4. **Skips** creating the data folder (which requires successful .NET build)
5. CI reports "success" because the export completed

The resulting exe file is non-functional because:
- It has the Godot runtime (in the exe)
- It has game assets (embedded PCK)
- It's **missing** the .NET runtime assemblies (`data_*` folder)

## Solution

Update all calls to `SpawnMuzzleFlash` to match the new signature:

### Fix 1: SilencedPistol.cs - Override Method Signature

```diff
-    protected override void SpawnMuzzleFlash(Vector2 position, Vector2 direction)
+    protected override void SpawnMuzzleFlash(Vector2 position, Vector2 direction, Resource? caliber)
```

### Fix 2: SilencedPistol.cs - Call Site

```diff
-        SpawnMuzzleFlash(spawnPosition, direction);
+        SpawnMuzzleFlash(spawnPosition, direction, WeaponData?.Caliber);
```

### Fix 3: Shotgun.cs - Call Site

```diff
-        SpawnMuzzleFlash(muzzleFlashPosition, fireDirection);
+        SpawnMuzzleFlash(muzzleFlashPosition, fireDirection, WeaponData?.Caliber);
```

## Verification

After applying the fix:
```bash
$ dotnet build
  32 Warning(s)
  0 Error(s)
```

The build succeeds with no errors, which means:
1. The .NET project will build successfully during export
2. The `data_GodotTopDownTemplate_windows_x86_64` folder will be created
3. The exported exe will have all required components to run

## Lessons Learned

### 1. API Changes Need Full Codebase Updates
When changing a virtual/overridable method signature in a base class:
- Search for all `override` declarations
- Search for all call sites
- Update all occurrences before merging

### 2. CI "Success" Can Be Misleading
The Godot export action reports success even when:
- The .NET build fails
- The resulting exe is non-functional

Consider adding a post-export validation step to check for required files.

### 3. Silent Failures Are Dangerous
The error message in the build log was present but not prominent:
```
ERROR: Failed to export project: Failed to build project.
```

The workflow should fail if .NET build fails, not continue silently.

## Files Modified

1. `Scripts/Weapons/SilencedPistol.cs` - Updated override signature and call
2. `Scripts/Weapons/Shotgun.cs` - Updated call site

## Related Issues and PRs

- **Issue #468** - Original request to reduce Uzi muzzle flash size
- **PR #474** - Added caliber parameter to SpawnMuzzleFlash (introduced the bug)
- **Issue #483** - This case study (missing data folder)

## References

- [Godot Forum: No data folder created on export](https://forum.godotengine.org/t/no-data-folder-created-on-export/110235)
- [Godot Forum: Customizing the Name of the Data Folder in Godot Mono Export](https://forum.godotengine.org/t/customizing-the-name-of-the-data-folder-in-godot-mono-export/85183)
