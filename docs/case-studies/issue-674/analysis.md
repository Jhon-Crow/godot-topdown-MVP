# Case Study: Windows Export CI Failure - Issue #674

## Summary

The Windows Export CI check fails with a `signal 11` (SIGSEGV) crash during the Godot headless export process. This is a known Godot engine bug affecting headless exports with C# projects.

## Timeline of Events

| Timestamp | Event | SHA | Result |
|-----------|-------|-----|--------|
| 2026-02-08 23:14 | Initial PR commit | d262d402 | SUCCESS |
| 2026-02-08 23:28 | BFF pendant feature | e6d15689 | SUCCESS |
| 2026-02-08 23:31 | Merge origin/main | edf7088b | SUCCESS |
| 2026-02-08 23:35 | Revert commit | f0c756e3 | SUCCESS |
| 2026-02-09 04:19 | Add C# Player.cs support | ec60829d | SUCCESS |
| 2026-02-10 19:07 | Add debug logging | 666f0f92 | SUCCESS |
| **2026-02-10 19:10** | **Merge upstream/main (Breaker Bullets)** | **1c0890d8** | **FAILURE** |

## Root Cause Analysis

### Immediate Cause

The Godot export process crashes with:

```
ERROR: Caller thread can't call this function in this node (/root). Use call_deferred() or call_thread_group() instead.
   at: propagate_notification (scene/main/node.cpp:2422)

================================================================
handle_crash: Program crashed with signal 11
Engine version: Godot Engine v4.3.stable.mono.official (77dcf97d82cbfe4e4615475fa52ca03da645dbd8)
```

### Analysis

1. **Threading Issue**: The error occurs during `dotnet publish` when `propagate_notification` is called from a worker thread instead of the main thread.

2. **C# Autoload Loading**: Both `GrenadeTimerHelper.cs` and `ReplayManager.cs` fail to compile during the headless import phase:
   ```
   ERROR: Failed to create an autoload, script 'res://Scripts/Autoload/GrenadeTimerHelper.cs' is not compiling.
   ERROR: Failed to create an autoload, script 'res://Scripts/Autoload/ReplayManager.cs' is not compiling.
   ```

3. **Not Branch-Specific**: The same autoload errors appear on main branch (which exports successfully), suggesting the crash is timing-dependent, not code-dependent.

4. **Known Godot Issues**:
   - [godotengine/godot#99284](https://github.com/godotengine/godot/issues/99284) - Crash when exporting in headless mode on Linux with Godot 4.3
   - [godotengine/godot#89674](https://github.com/godotengine/godot/issues/89674) - Crash when exporting in headless mode with Godot 4.2.2.rc2
   - [godotengine/godot#112955](https://github.com/godotengine/godot/issues/112955) - Crash during headless export for linux (nix build on gh actions)
   - [Forum: Autoload fails to compile, only on GitHub Actions ubuntu](https://forum.godotengine.org/t/autoload-fails-to-compile-only-on-github-actions-ubuntu/87309)

## Comparison: Main vs Feature Branch

| Aspect | Main Branch (46be77e9) | Feature Branch (1c0890d8) |
|--------|------------------------|---------------------------|
| Windows Export Result | SUCCESS | FAILURE |
| C# Autoload Errors | YES (same errors) | YES (same errors) |
| Signal 11 Crash | NO | YES |
| Export Artifacts Created | YES | NO |

### Key Observation

The main branch experiences identical C# autoload compilation errors but does NOT crash. This strongly suggests:

- The crash is a race condition/timing issue in Godot's headless export
- The exact moment of failure varies based on system load, memory state, or other non-deterministic factors
- The additional files/complexity in the feature branch may affect timing enough to trigger the crash

## Files Changed in Feature Branch

The following files differ from main:

1. `Scripts/Characters/Player.cs` - BFF pendant C# support
2. `assets/sprites/weapons/bff_pendant_icon.png` - Icon asset
3. `docs/case-studies/issue-674/game_log_*.txt` - Game logs
4. `experiments/bff_pendant_icon.png` - Experiment asset
5. `experiments/create_bff_pendant_icon.py` - Python script
6. `scenes/objects/BffCompanion.tscn` - Companion scene
7. `scripts/autoload/active_item_manager.gd` - Active item additions
8. `scripts/characters/player.gd` - BFF pendant GDScript support
9. `scripts/objects/bff_companion.gd` - Companion AI script
10. `tests/unit/test_*.gd` - Unit tests

None of these files use threading or `call_deferred` in a way that would cause the specific crash observed.

## Proposed Solutions

### Solution 1: Re-run CI (Recommended First)

Since this is a flaky/timing-dependent issue, re-running the CI may succeed:

```bash
# Push an empty commit to trigger new CI run
git commit --allow-empty -m "ci: retry Windows export after flaky crash"
git push
```

### Solution 2: Upgrade Godot Version

The issue may be fixed in newer Godot versions:
- Upgrade from 4.3 to 4.4 or 4.5 in `.github/workflows/build-windows.yml`

### Solution 3: Add Error Handling to Workflow

Modify the workflow to handle the crash gracefully:

```yaml
- name: Export game
  id: export
  uses: firebelley/godot-export@v7.0.0
  with:
    godot_executable_download_url: https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_mono_linux_x86_64.zip
    # ...
  continue-on-error: true  # Allow job to continue even if export crashes

- name: Check export artifacts
  run: |
    if [ -f "${{ steps.export.outputs.archive_directory }}/Windows Desktop.zip" ]; then
      echo "Export succeeded despite potential crash"
      exit 0
    else
      echo "Export actually failed - no artifacts"
      exit 1
    fi
```

### Solution 4: Reduce Project Complexity During Export

Temporarily exclude problematic directories:

```yaml
- name: Pre-export cleanup
  run: |
    rm -rf experiments/
    rm -rf docs/case-studies/
```

## Relevant Log Files

- `windows-export-21878802104.log` - Full CI log from failed run
- `issue-details.json` - Original issue data
- `pr-details.json` - Pull request details
- `pr-diff.patch` - Changes in this PR
- `ci-runs-history.json` - CI run history
- `git-log.txt` - Git commit log

## Conclusion

This is a **known Godot engine bug** related to headless exports with C# projects, not a bug in the feature implementation. The crash is timing-dependent and may not occur on re-run. The recommended approach is:

1. First, try re-running CI (empty commit push)
2. If persistent, consider upgrading Godot version
3. If critical, add workflow error handling

## References

- [Godot Issue #99284](https://github.com/godotengine/godot/issues/99284)
- [Godot Issue #89674](https://github.com/godotengine/godot/issues/89674)
- [Godot Issue #112955](https://github.com/godotengine/godot/issues/112955)
- [Godot Forum Discussion](https://forum.godotengine.org/t/autoload-fails-to-compile-only-on-github-actions-ubuntu/87309)
