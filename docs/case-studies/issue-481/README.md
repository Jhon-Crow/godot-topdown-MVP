# Case Study: Windows Build Missing DLL/Data Folder Issue

**Issue Reference:** [#481](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/481)
**Related PR:** [#482](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/482)
**Date:** 2026-02-04
**Status:** Under Investigation

## Executive Summary

The Windows build artifact produced by GitHub Actions is missing the `data_GodotTopDownTemplate_windows_x86_64` folder (containing .NET/Mono DLLs and assemblies), causing the exported game executable to fail on launch. This is a **pre-existing issue** affecting all branches including `main`, not something introduced by PR #482.

## Problem Statement

When downloading the Windows build artifact from GitHub Actions:
1. The ZIP archive only contains the executable (EXE with embedded PCK)
2. The required `data_*` folder with .NET runtime files is missing
3. The game cannot run without these DLL files

User feedback (translated from Russian):
> "в папке с собранным exe нет папки data_GodotTopDownTemplate_windows_x86_64, так что не запускается"
> (Translation: "the folder with the built exe doesn't have the data_GodotTopDownTemplate_windows_x86_64 folder, so it won't launch")

## Timeline of Events

| Timestamp | Event |
|-----------|-------|
| 2026-02-04 14:04:52 | Main branch Windows build run #21674498883 started |
| 2026-02-04 14:09:20 | Main branch build completed with "success" status |
| 2026-02-04 14:10:52 | PR branch #482 Windows build run #21674701937 started |
| 2026-02-04 14:11:25 | Export begins, script errors detected |
| 2026-02-04 14:11:44 | **ERROR: Failed to export project: Failed to build project** |
| 2026-02-04 14:11:46 | Workflow continues despite failure, creates partial archive |
| 2026-02-04 14:11:54 | Artifact uploaded (35.3 MB, contains only EXE) |
| 2026-02-04 14:11:56 | Workflow reports "success" |
| 2026-02-04 14:17:12 | User reports missing DLL folder |

## Root Cause Analysis

### Primary Root Cause: C# Build Failure During Export

The Godot export process fails with:
```
ERROR: Failed to export project: Failed to build project.
System.InvalidOperationException: Failed to build project.
```

This failure occurs because:

1. **GDScript compilation errors** (warnings treated as errors):
   - `cinema_effects_manager.gd`: "The variable type is being inferred from a Variant value, so it will be typed as Variant."
   - `test_issue_393_fix.gd`: "There is already a variable named 'has_velocity' declared in this scope."
   - Multiple test files with various parse errors

2. **C# autoload script fails to compile**:
   - `GrenadeTimerHelper.cs` references `GodotTopdown.Scripts.Projectiles.GrenadeTimer`
   - The C# project may not be building successfully in the CI environment

3. **Cascading failures**:
   - `grenade_base.gd` depends on C# classes that fail to compile
   - `frag_grenade.gd` and `flashbang_grenade.gd` cannot resolve `class_name GrenadeBase`

### Secondary Root Cause: Workflow Doesn't Fail on Export Error

The `build-windows.yml` workflow uses `firebelley/godot-export@v7.0.0` which:
1. Reports the export failure in logs
2. Still creates a partial archive (EXE only, no .NET runtime)
3. Uploads the incomplete artifact
4. Reports overall job status as "success"

### Technical Details: Expected vs Actual Export Output

**Expected Windows .NET Export Structure:**
```
builds/windows/
├── GodotTopDownTemplate.exe
├── GodotTopDownTemplate.pck (or embedded in EXE)
└── data_GodotTopDownTemplate_windows_x86_64/
    ├── GodotSharp.dll
    ├── System.dll
    ├── System.Core.dll
    └── [other .NET runtime DLLs]
```

**Actual Export Output (Failed Build):**
```
builds/windows/
└── GodotTopDownTemplate.exe (with embedded PCK, no .NET runtime)
```

## Evidence

### Build Log Excerpts

From `windows-build-pr-branch-21674701937.log`:

```
Windows Export    Export game    2026-02-04T14:11:25.9558605Z ERROR: Failed to load script "res://scripts/autoload/cinema_effects_manager.gd" with error "Parse error".
Windows Export    Export game    2026-02-04T14:11:25.9560725Z ERROR: Failed to create an autoload, script 'res://scripts/autoload/cinema_effects_manager.gd' is not compiling.
Windows Export    Export game    2026-02-04T14:11:25.9563625Z ERROR: Failed to create an autoload, script 'res://Scripts/Autoload/GrenadeTimerHelper.cs' is not compiling.
...
Windows Export    Export game    2026-02-04T14:11:44.4382212Z ERROR: Failed to export project: Failed to build project.
Windows Export    Export game    2026-02-04T14:11:44.4406894Z System.InvalidOperationException: Failed to build project.
```

### Workflow Configuration Issues

From `.github/workflows/build-windows.yml`:
```yaml
- name: Export game
  id: export
  uses: firebelley/godot-export@v7.0.0
  with:
    godot_executable_download_url: https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_mono_linux_x86_64.zip
    godot_export_templates_download_url: https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_mono_export_templates.tpz
    relative_project_path: ./
    archive_output: true

- name: Upload artifact
  uses: actions/upload-artifact@v4
  # No condition to check if export succeeded!
```

## Proposed Solutions

### Solution 1: Fix GDScript Warnings (Recommended - Short Term)

Add explicit type annotations to fix warnings treated as errors:

**File: `scripts/autoload/cinema_effects_manager.gd`**
```gdscript
# Before (warning: Variant inference)
var node := get_node_or_null(path)

# After (explicit type)
var node: Node = get_node_or_null(path)
```

**File: `experiments/test_issue_393_fix.gd`**
```gdscript
# Remove duplicate variable declaration of 'has_velocity'
```

### Solution 2: Add Export Failure Detection (Recommended - Short Term)

Modify `build-windows.yml` to fail the job when export fails:

```yaml
- name: Export game
  id: export
  uses: firebelley/godot-export@v7.0.0
  with:
    godot_executable_download_url: https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_mono_linux_x86_64.zip
    godot_export_templates_download_url: https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_mono_export_templates.tpz
    relative_project_path: ./
    archive_output: true

- name: Verify export output
  run: |
    # Check if data folder exists (required for .NET builds)
    if [ ! -d "${{ steps.export.outputs.build_directory }}/data_*" ]; then
      echo "ERROR: .NET data folder not found - export likely failed"
      exit 1
    fi

- name: Upload artifact
  if: success()
  uses: actions/upload-artifact@v4
  with:
    name: windows-build
    path: ${{ steps.export.outputs.archive_directory }}/*
```

### Solution 3: Disable GDScript Warnings as Errors (Alternative)

Add to `project.godot`:
```ini
[debug]
gdscript/warnings/inferred_declaration=0
gdscript/warnings/unsafe_property_access=0
```

**Note:** This masks the underlying issues and is not recommended for long-term maintenance.

### Solution 4: Fix C# Build Pipeline (Long Term)

1. Ensure C# project builds successfully before export
2. Add a dedicated C# build step in the workflow
3. Consider separating GDScript-only and C#/GDScript mixed builds

## Impact Assessment

| Component | Impact Level | Description |
|-----------|-------------|-------------|
| Windows Builds | **Critical** | All Windows builds fail to run |
| Main Branch | **Critical** | Main branch is also affected |
| CI/CD Pipeline | **High** | False positive success reports |
| Developer Experience | **Medium** | Requires manual testing to verify builds |

## Recommendations

1. **Immediate:** Create a separate issue to track the Windows build pipeline fix
2. **Short Term:** Implement Solution 1 (fix GDScript warnings) and Solution 2 (add verification)
3. **Long Term:** Review C# integration and consider comprehensive build validation

## Related Resources

- [Godot GDScript Warning System Documentation](https://docs.godotengine.org/en/4.3/tutorials/scripting/gdscript/warning_system.html)
- [firebelley/godot-export GitHub Action](https://github.com/firebelley/godot-export)
- [Godot .NET Export Documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)
- [GitHub Issue: Godot 4.3 GDScript export mode breaks exported builds](https://github.com/godotengine/godot/issues/94150)

## Log Files

- [`logs/windows-build-pr-branch-21674701937.log`](logs/windows-build-pr-branch-21674701937.log) - PR branch build log
- [`logs/windows-build-main-branch-21674649456.log`](logs/windows-build-main-branch-21674649456.log) - Main branch build log (same issues)

## Conclusion

The Windows build failure is a **systemic issue** in the repository's CI/CD pipeline, not specific to PR #482. The root cause is a combination of:

1. GDScript scripts with warnings that are treated as errors during export
2. C# autoload scripts that fail to compile in the CI environment
3. The workflow not detecting and failing on export errors

Fixing this requires addressing both the code issues and the workflow configuration.
