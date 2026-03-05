# Case Study: Issue #938 - Delete Saves Button

## Overview

**Issue:** [#938 - добавь кнопку Удалить сохранения](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/938)
**Pull Request:** [#943 - feat: add Delete Saves button in Experimental menu](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/943)
**Related PR:** [#924 - fix: condition-based item unlock system](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/924)

## Timeline of Events

### 2026-02-28 (Before Issue Creation)
- PR #924 was created addressing the condition-based item unlock system (Issue #894)
- This PR implemented the unlock mechanism for weapons, grenades, and active items based on level completion

### 2026-03-01 00:34 UTC - Issue Created
**Request (translated from Russian):**
> Extend branch from PR #924, add "Delete Saves" button to experimental menu.
> All progress should be erased (completed levels, unlocked weapons), game should return to first-launch state.
> Experimental settings should NOT be reset.

### 2026-03-02 15:05 UTC - Initial Implementation
- Branch `issue-938-cd67e048b530` created
- Initial commit with task details (CLAUDE.md file)

### 2026-03-02 15:09 UTC - Feature Implementation
- **Commit:** `589e539b` - "feat: add Delete Saves button in Experimental menu (Issue #938)"
- Added `clear_all_saves()` method to `PersistManager`
- Added UI elements to `ExperimentalMenu.tscn`
- Added button handler in `experimental_menu.gd`
- Created unit tests in `tests/unit/test_delete_saves.gd`

### 2026-03-02 15:10 UTC - Cleanup
- **Commit:** `9e6a29fb` - Reverted CLAUDE.md task file

### 2026-03-02 15:10 UTC - PR Ready
- Solution log posted (cost: ~$1.51)
- All CI checks passed
- No merge conflicts at this point

### 2026-03-02 17:10 UTC - Owner Feedback
**Jhon-Crow commented with 3 requests:**
1. Resolve merge conflicts
2. Make experimental menu width 2x larger (horizontal scrolling issue)
3. Create case study documentation

### 2026-03-02 - 2026-03-05 - Conflicts Developed
- Other PRs merged to main branch:
  - PR #749 (issue-748)
  - PR #936 (issue-935 - WeaponData caliber ricochet)
  - PR #927 (issue-926)
  - PR #951 (issue-950)
- These PRs added new features to ExperimentalMenu:
  - FPS Counter option
  - FPS Drop Logging option
  - ScrollContainer for better scrolling

### 2026-03-05 19:45 UTC - Current Session
- AI work session started
- Merge conflicts resolved
- Menu width doubled
- Case study created

## Root Cause Analysis

### Problem 1: Merge Conflicts

**Root Cause:** The ExperimentalMenu.tscn scene file was modified concurrently:
- This PR added DeleteSaves button at a specific location
- Other PRs (during 3-day gap) added FpsCounter, FpsDropLogging features, and introduced ScrollContainer

**Technical Details:**
- Scene files use node paths that include parent container names
- Original implementation used `VBoxContainer` directly
- Upstream changes added `ScrollContainer` wrapper, changing all node paths
- Godot scene files (.tscn) are text-based but position-sensitive

### Problem 2: Horizontal Scrolling

**Root Cause:** PanelContainer width was insufficient for content
- Original width: 440px (-220 to +220 offset)
- Content (especially long description labels) exceeded container width
- ScrollContainer only handled vertical scrolling, not horizontal content fit

**Fix Applied:** Doubled width to 880px (-440 to +440 offset)

## Technical Implementation

### Core Feature: `clear_all_saves()` Method

Location: `scripts/autoload/persist_manager.gd:298-329`

```gdscript
func clear_all_saves() -> void:
    # 1. Delete the save file
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(SAVE_PATH)

    # 2. Reset GameManager weapons to defaults (only Makarov PM)
    # 3. Reset GrenadeManager to defaults (only Flashbang)
    # 4. Reset ActiveItemManager to defaults (none)
    # 5. Clear level progress via ProgressManager

    _log_to_file("All saves cleared — game reset to first-launch state")
```

### Design Decisions

1. **File Deletion vs Section Clearing:** Chose `DirAccess.remove_absolute()` instead of `erase_section()` because:
   - Cleaner approach for full reset
   - Avoids potential issues with ConfigFile methods in some Godot versions ([reference](https://github.com/godotengine/godot/issues/52645))
   - Simpler to verify success

2. **In-Memory State Reset:** Must reset both file AND runtime state because:
   - Managers cache unlock states in memory
   - File deletion alone wouldn't affect current session
   - User expects immediate effect when pressing "Delete"

3. **Experimental Settings Preserved:** Intentional per requirements
   - ExperimentalSettings uses separate persistence mechanism
   - Different concerns: game progress vs user preferences

## Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `scripts/autoload/persist_manager.gd` | Modified | Added `clear_all_saves()` method |
| `scenes/ui/ExperimentalMenu.tscn` | Modified | Added DeleteSaves UI row, doubled width |
| `scripts/ui/experimental_menu.gd` | Modified | Added button reference and handler |
| `tests/unit/test_delete_saves.gd` | New | 17 unit tests for the feature |

## Best Practices Applied

Based on [Godot documentation](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html) and community best practices:

1. **Centralized Save Management:** All save operations go through `PersistManager` autoload
2. **Signal-Based Auto-Save:** State changes automatically trigger saves
3. **Graceful Degradation:** Uses `get_node_or_null()` to handle missing nodes
4. **Logging:** All operations logged via `FileLogger` for debugging

## Lessons Learned

1. **Concurrent Development:** Long-lived branches require regular rebasing/merging
2. **UI Layout:** Container widths should accommodate longest expected content
3. **Scene File Conflicts:** Godot .tscn files are particularly prone to merge conflicts when structure changes
4. **State Management:** For "reset" features, consider both persistent storage AND runtime state

## Test Coverage

The implementation includes 17 unit tests covering:
- Weapon reset to defaults
- Grenade reset to defaults
- Active item reset to defaults
- Level progress clearing
- Save file removal
- Full reset scenario
- Idempotency (multiple resets)

## References

- [Godot Saving Games Documentation](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
- [ConfigFile API Reference](https://docs.godotengine.org/en/stable/classes/class_configfile.html)
- [Forum: How to erase saved data](https://forum.godotengine.org/t/how-to-erase-saved-data-in-a-config-file/74384)
- [GDQuest: Saving and Loading Games](https://www.gdquest.com/library/save_game_godot4/)
- [GitHub Issue: ConfigFile erase_section issues](https://github.com/godotengine/godot/issues/52645)

## Data Files

This case study folder contains:
- `issue-data.json` - Original issue details
- `pr-data.json` - Pull request metadata
- `pr-comments.json` - PR conversation history
- `pr-commits.json` - Commit history
- `related-pr-924.json` - Related PR that this issue references
- `solution-draft-log.txt` - Full AI solution log (~1.4MB)
