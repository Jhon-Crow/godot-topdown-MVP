# Case Study: Issue #188 - Armory Menu Breakage After Frag Grenade Implementation

## Executive Summary

This case study documents the investigation and resolution of a bug where the armory menu stopped displaying content after implementing the frag grenade feature (Issue #188). The root cause was identified as invalid node naming in Godot due to spaces in grenade names.

## Timeline of Events

### Phase 1: Initial Implementation (PR #189)
- **Date:** 2026-01-22 ~00:13
- **Action:** AI solver implemented frag grenade feature
- **Changes Made:**
  1. Added `GrenadeManager` autoload for grenade type selection
  2. Modified `armory_menu.gd` to include grenade selection UI
  3. Removed flashbang from the `WEAPONS` dictionary (moved to `GrenadeManager`)
  4. Added dynamic grenade slot creation in armory menu

### Phase 2: User Testing
- **Date:** 2026-01-22 03:32
- **Action:** User tested the build
- **Result:** User reported "armory сломалось - там ничего не отображается" (armory broke - nothing is displayed there)
- **Logs Provided:**
  - `game_log_20260122_033222.txt`
  - `game_log_20260122_033248.txt`

### Phase 3: Investigation
- **Date:** 2026-01-22
- **Findings:**
  1. Logs showed normal game operation, no explicit errors
  2. GrenadeManager was loading correctly
  3. Identified potential issue: Node naming with spaces

## Root Cause Analysis

### Primary Issue: Invalid Node Names

In Godot 4.x, node names cannot contain spaces. The code in `_create_grenade_slot()` was setting:

```gdscript
slot.name = grenade_data.get("name", "grenade") + "_slot"
```

With `GRENADE_DATA` containing:
```gdscript
GrenadeType.FRAG: {
    "name": "Frag Grenade",  # Contains a space!
    ...
}
```

This would create a node named "Frag Grenade_slot" which violates Godot's node naming rules.

### Secondary Issues Identified

1. **No defensive checks:** The code didn't validate that UI elements were properly initialized
2. **No logging:** Without diagnostic logging, it was difficult to trace the execution path
3. **WEAPONS dictionary modification:** Removing flashbang from WEAPONS could have unintended consequences if other code depended on it

## Solution Implemented

### Fix 1: Sanitize Node Names
```gdscript
func _create_grenade_slot(grenade_type: int, grenade_data: Dictionary, is_selected: bool) -> PanelContainer:
    var slot := PanelContainer.new()
    # Use sanitized name for node (no spaces allowed in Godot node names)
    var grenade_name: String = grenade_data.get("name", "grenade")
    slot.name = grenade_name.replace(" ", "_") + "_slot"
```

### Fix 2: Add Defensive Checks
```gdscript
func _populate_weapon_grid() -> void:
    # Verify weapon_grid is valid
    if weapon_grid == null:
        FileLogger.info("[ArmoryMenu] ERROR: weapon_grid is null!")
        return
```

### Fix 3: Add Diagnostic Logging
Added comprehensive logging throughout the armory menu to track:
- When `_ready()` is called
- Whether `GrenadeManager` was found
- Number of weapon/grenade slots being created
- Completion of grid population

## Files Modified

1. `scripts/ui/armory_menu.gd`
   - Fixed node naming to replace spaces with underscores
   - Added null checks for weapon_grid
   - Added diagnostic logging

## Lessons Learned

1. **Godot Node Naming:** Always sanitize user-facing strings before using them as node names
2. **Defensive Programming:** Add null checks and validation for @onready variables
3. **Logging:** Implement logging early in development to aid debugging
4. **Testing:** Visual UI changes should be manually tested before merging

## Recommendations

1. Create a utility function for sanitizing node names
2. Add unit tests that verify node naming conventions
3. Consider adding debug overlay for UI debugging
4. Document Godot-specific constraints in coding guidelines

### Phase 4: Second Fix Attempt (Continued Investigation)
- **Date:** 2026-01-22 ~00:48
- **Action:** User reported armory still broken
- **New Log:** `game_log_20260122_034730.txt`
- **Key Observation:** Log shows GrenadeManager loading correctly, but **NO `[ArmoryMenu]` entries**
  - This indicates the armory menu was never opened during the test session
  - OR the script's `_ready()` function never executed

### Phase 5: Enhanced Debugging
- **Date:** 2026-01-22
- **Actions Taken:**
  1. Added comprehensive logging to pause_menu.gd for armory button handling
  2. Enhanced logging in armory_menu.gd with per-slot creation messages
  3. Added validation for all UI elements (back_button, status_label, weapon_grid)
  4. Added refresh call when re-opening existing armory menu (like levels_menu does)

## Key Observations from Logs

### Log Analysis Summary:

| Log File | ArmoryMenu Entries | GrenadeManager Entries | Interpretation |
|----------|-------------------|------------------------|----------------|
| game_log_20260122_033222.txt | **NONE** | Present | Armory not opened |
| game_log_20260122_033248.txt | **NONE** | Present | Armory not opened |
| game_log_20260122_034730.txt | **NONE** | Present | Armory not opened |

### Conclusion:
The logs show the GrenadeManager is loading correctly (proving the new code is running), but there are NO `[ArmoryMenu]` entries in any of the logs. This means either:
1. The user did not open the armory menu during these test sessions
2. The armory menu's script is not executing at all
3. There's an issue before the logging starts

## Enhanced Solution

### Additional Fix: Pause Menu Logging
```gdscript
func _on_armory_pressed() -> void:
    FileLogger.info("[PauseMenu] Armory button pressed")
    # ... existing code ...
    FileLogger.info("[PauseMenu] Armory menu instance created and added as child")
```

### Additional Fix: Armory Menu Refresh on Re-open
```gdscript
# In pause_menu.gd _on_armory_pressed():
else:
    FileLogger.info("[PauseMenu] Showing existing armory menu")
    # Refresh the weapon grid in case grenade selection changed
    if _armory_menu.has_method("_populate_weapon_grid"):
        _armory_menu._populate_weapon_grid()
    _armory_menu.show()
```

### Additional Fix: Per-Slot Logging
Added logging for each weapon and grenade slot creation to trace exactly which items are being added.

## Related Files

- [Game Log 1](logs/game_log_20260122_033222.txt)
- [Game Log 2](logs/game_log_20260122_033248.txt)
- [Game Log 3](game_log_20260122_034730.txt)
- [Game Log 4 (Latest)](game_log_20260122_041025.txt)

---

## Phase 6: Fourth Log Analysis (2026-01-22 04:10)

### New Log: `game_log_20260122_041025.txt`

This log provides **critical new information**:

```
[04:10:26] [INFO] [PauseMenu] Armory button pressed
[04:10:26] [INFO] [PauseMenu] Creating new armory menu instance
[04:10:26] [INFO] [PauseMenu] Armory menu instance created and added as child
```

And later:
```
[04:10:44] [INFO] [PauseMenu] Armory button pressed
[04:10:44] [INFO] [PauseMenu] Creating new armory menu instance
[04:10:44] [INFO] [PauseMenu] Armory menu instance created and added as child
```

### Key Finding

The `[PauseMenu]` logs ARE appearing (proving the latest code is running), but there are **STILL NO `[ArmoryMenu]` entries**. This means:

1. The armory button IS being pressed ✓
2. The scene IS being instantiated ✓
3. The instance IS being added as a child ✓
4. **BUT `_ready()` in armory_menu.gd is NOT being called!**

### Hypothesis: Silent Script Error

When a Godot script has an error that prevents execution, the `_ready()` function may silently fail to run. Possible causes:
1. The `@onready` variables fail to resolve their node paths
2. There's a parse-time error in the script
3. The script is somehow not attached to the instantiated scene

### Investigation Actions

1. **Added `_enter_tree()` function** - This runs before `_ready()` and before `@onready` variables are initialized:
   ```gdscript
   func _enter_tree() -> void:
       FileLogger.info("[ArmoryMenu] _enter_tree() called - node added to tree")
   ```

2. **Enhanced pause menu logging** - Added detailed logging to trace the exact state:
   ```gdscript
   FileLogger.info("[PauseMenu] armory_menu_scene resource path: %s" % armory_menu_scene.resource_path)
   FileLogger.info("[PauseMenu] Instance created, class: %s, name: %s" % [_armory_menu.get_class(), _armory_menu.name])
   FileLogger.info("[PauseMenu] is_inside_tree: %s" % _armory_menu.is_inside_tree())
   ```

### Next Steps

User needs to:
1. Rebuild the game with the latest code
2. Open the armory menu
3. Provide the new log file

Expected log entries if `_enter_tree()` works but `_ready()` doesn't:
```
[PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[PauseMenu] Instance created, class: CanvasLayer, name: ArmoryMenu
[ArmoryMenu] _enter_tree() called - node added to tree
[PauseMenu] is_inside_tree: true
```

If `_enter_tree()` also doesn't appear, the script is not executing at all (possibly not attached).

---

## Phase 7: Fifth Log Analysis (2026-01-22 04:17)

### New Log: `game_log_20260122_041747.txt`

The latest log provides **definitive confirmation** of the issue:

```
[04:17:50] [INFO] [PauseMenu] Armory button pressed
[04:17:50] [INFO] [PauseMenu] Creating new armory menu instance
[04:17:50] [INFO] [PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[04:17:50] [INFO] [PauseMenu] Instance created, class: CanvasLayer, name: ArmoryMenu
[04:17:50] [INFO] [PauseMenu] back_pressed signal connected
[04:17:50] [INFO] [PauseMenu] Armory menu instance added as child, is_inside_tree: true
```

### Critical Finding

The log shows:
- ✅ Scene path is correct: `res://scenes/ui/ArmoryMenu.tscn`
- ✅ Instance created with correct class: `CanvasLayer`
- ✅ Instance has correct name: `ArmoryMenu`
- ✅ `back_pressed` signal successfully connected (signal is defined in script)
- ✅ Node is inside tree: `is_inside_tree: true`
- ❌ **NO `[ArmoryMenu]` log entries at all** - neither `_enter_tree()` nor `_ready()`

### Confirmed Root Cause: Script Not Executing

The fact that:
1. The `back_pressed` signal was successfully connected proves the script IS attached (signals are defined in the script)
2. But `_enter_tree()` never logs anything
3. And `_ready()` never logs anything

This indicates **the script is attached but not executing its lifecycle callbacks**.

### Possible Causes

1. **GDScript parsing/compilation error** - The script fails to compile silently
2. **FileLogger autoload timing** - FileLogger might not be available when ArmoryMenu tries to use it
3. **Export build issue** - Script might be partially loaded in export builds
4. **Resource caching** - Old compiled script might be cached

### Solution Approach

Added additional debugging:
1. **`_init()` function** - Runs when object is created, before `_enter_tree()`
2. **`print()` statements** - Direct print instead of FileLogger, in case autoload is the issue
3. **Script attachment verification** - Check if `get_script()` returns a valid script
4. **Signal/method existence checks** - Verify script methods are callable

### Updated Code Changes

**armory_menu.gd:**
```gdscript
# Top-level variable to verify script is parsed
var _script_load_marker: bool = true

func _init() -> void:
    # _init runs when object is created
    print("[ArmoryMenu] _init() called - object created")
    if FileLogger:
        FileLogger.info("[ArmoryMenu] _init() called - object created")

func _enter_tree() -> void:
    print("[ArmoryMenu] _enter_tree() called - node added to tree")
    FileLogger.info("[ArmoryMenu] _enter_tree() called - node added to tree")

func _ready() -> void:
    print("[ArmoryMenu] _ready() called")
    FileLogger.info("[ArmoryMenu] _ready() called")
```

**pause_menu.gd:**
```gdscript
# Check if script is properly attached
var script = _armory_menu.get_script()
if script:
    FileLogger.info("[PauseMenu] Script attached: %s" % script.resource_path)
else:
    FileLogger.info("[PauseMenu] WARNING: No script attached to armory menu instance!")

# Check if signal exists (proves script is loaded)
if _armory_menu.has_signal("back_pressed"):
    FileLogger.info("[PauseMenu] back_pressed signal exists on instance")
else:
    FileLogger.info("[PauseMenu] WARNING: back_pressed signal NOT found!")
```

### Research: Similar Issues

Reference: [Godot Forum - Instantiated Scenes Don't Have Scripts Connected](https://forum.godotengine.org/t/instantiated-scenes-dont-have-scripts-connected/75079)

Key points from research:
- Scripts work in editor but not in export builds is a known issue in Godot 4.2+
- Scene file must have script attached to root node, not just instance in editor
- `@export var scene: PackedScene` can lose assignments on save (use preload instead)

### Files in logs/ Directory

| File | Timestamp | Contains ArmoryMenu Logs |
|------|-----------|-------------------------|
| game_log_20260122_033222.txt | 03:32 | No |
| game_log_20260122_033248.txt | 03:32 | No |
| game_log_20260122_034730.txt | 03:47 | No |
| game_log_20260122_041747.txt | 04:17 | No |

All four logs show the same pattern: GrenadeManager works, PauseMenu logs appear, but ArmoryMenu script never executes.

---

## Phase 8: Root Cause Identified and Fixed (2026-01-22 05:26)

### New Log: `game_log_20260122_052623.txt`

The log provides **definitive evidence** of the script compilation issue:

```
[05:26:29] [INFO] [PauseMenu] Armory button pressed
[05:26:29] [INFO] [PauseMenu] Creating new armory menu instance
[05:26:29] [INFO] [PauseMenu] armory_menu_scene resource path: res://scenes/ui/ArmoryMenu.tscn
[05:26:29] [INFO] [PauseMenu] Instance created, class: CanvasLayer, name: ArmoryMenu
[05:26:29] [INFO] [PauseMenu] Script attached: res://scripts/ui/armory_menu.gd
[05:26:29] [INFO] [PauseMenu] WARNING: back_pressed signal NOT found on instance!
[05:26:29] [INFO] [PauseMenu] back_pressed signal connected
[05:26:29] [INFO] [PauseMenu] Armory menu instance added as child, is_inside_tree: true
[05:26:29] [INFO] [PauseMenu] WARNING: _populate_weapon_grid method NOT found!
```

### Final Root Cause: GDScript Compilation Failure in Export Build

The log clearly shows:
1. Script IS attached: `res://scripts/ui/armory_menu.gd`
2. **BUT signal NOT found**: `WARNING: back_pressed signal NOT found on instance!`
3. **AND method NOT found**: `WARNING: _populate_weapon_grid method NOT found!`

This is the **smoking gun**: The script file is referenced, but its class members (signals, methods) are not available. This happens when:

1. **GDScript fails to compile** in the export build but succeeds in the editor
2. **The compiled bytecode is invalid** or incompatible with the export build
3. **A silent parse error** prevents the script from fully loading

### User Feedback

The user reported: "новое armory работает" (new armory works) - referring to the UPSTREAM version of armory_menu.gd. This confirmed:
- The UPSTREAM armory_menu.gd works fine
- MY modified armory_menu.gd causes compilation failures in export builds

### Solution: Simplify to Match Upstream Pattern

Instead of using a separate grenade selection system with GrenadeManager integration in the armory menu, I simplified the approach to match the upstream pattern:

**Before (broken):**
- Complex grenade slot creation via `_create_grenade_slot()` method
- Dynamic querying of GrenadeManager for grenade types
- Separate grenade selection logic from weapon selection
- Type annotations like `var grenade_types := _grenade_manager.get_all_grenade_types()`

**After (working):**
- Add grenades directly to the WEAPONS dictionary (like upstream's Flashbang)
- Add `is_grenade: true` flag to distinguish grenades from weapons
- Reuse existing `_create_weapon_slot()` logic for all items
- Simple integration with GrenadeManager for grenade type changes

### Key Changes Made

1. **Added frag_grenade to WEAPONS dictionary:**
```gdscript
const WEAPONS: Dictionary = {
    # ... existing weapons ...
    "frag_grenade": {
        "name": "Frag Grenade",
        "icon_path": "res://assets/sprites/weapons/frag_grenade.png",
        "unlocked": true,
        "description": "Offensive grenade - explodes on impact, releases 4 shrapnel pieces that ricochet.",
        "is_grenade": true,
        "grenade_type": 1
    },
    # ... other weapons ...
}
```

2. **Modified slot click handling:**
```gdscript
func _on_slot_gui_input(event: InputEvent, slot: PanelContainer, weapon_id: String) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var weapon_data: Dictionary = WEAPONS.get(weapon_id, {})
        var is_grenade: bool = weapon_data.get("is_grenade", false)

        if is_grenade:
            _select_grenade(weapon_id, weapon_data)
        else:
            _select_weapon(weapon_id)
```

3. **Added grenade selection with level restart:**
```gdscript
func _select_grenade(weapon_id: String, weapon_data: Dictionary) -> void:
    if _grenade_manager == null:
        return

    var grenade_type: int = weapon_data.get("grenade_type", 0)

    if _grenade_manager.is_selected(grenade_type):
        return

    # Set new grenade type - this will restart the level
    _grenade_manager.set_grenade_type(grenade_type, true)
```

### Lessons Learned

1. **Export builds are less forgiving** than the Godot editor for script errors
2. **Complex type inference** (`:=` with method return types) can cause issues in exports
3. **Keep UI scripts simple** - follow existing patterns that are known to work
4. **The WEAPONS dictionary pattern** is a proven approach in this codebase

### Files Modified

1. `scripts/ui/armory_menu.gd` - Simplified to upstream pattern + frag grenade

### Testing Request

User should rebuild and test the armory menu to verify:
1. All items (M16, Flashbang, Frag Grenade, Shotgun, locked weapons) are displayed
2. Clicking Frag Grenade restarts the level and selects it
3. Both weapon and grenade selections are highlighted correctly

---

## Phase 9: Final Root Cause - C# Player Not Using GrenadeManager (2026-01-22 06:06)

### New Log: `game_log_20260122_060646.txt`

User reported: "похоже граната не берётся" (it seems the grenade is not being picked up/selected)

### Log Analysis

The log shows that:
1. ✅ Armory menu now works correctly
2. ✅ Grenade selection is working (`[GrenadeManager] Grenade type changed from Flashbang to Frag Grenade`)
3. ✅ Level restarts after grenade type change
4. ❌ **But the grenade thrown is still FlashbangGrenade!**

Key evidence from log:
```
[06:06:56] [INFO] [GrenadeManager] Grenade type changed from Flashbang to Frag Grenade
[06:06:56] [INFO] [GrenadeManager] Restarting level due to grenade type change
...
[06:07:21] [INFO] [SoundPropagation] Sound emitted: type=EXPLOSION, source=NEUTRAL (FlashbangGrenade)
```

The grenade explosion still shows "FlashbangGrenade" even though Frag Grenade was selected!

### Critical Finding: C# Player Script Doesn't Use GrenadeManager

Searching for the log message `[Player.Grenade] Grenade scene loaded` revealed it comes from:
- **`Scripts/Characters/Player.cs:274`** (C# script)
- NOT from `scripts/characters/player.gd` (GDScript)

The user is running the **C# version** of the player, which has hardcoded grenade loading:

**Player.cs (BEFORE FIX):**
```csharp
// Lines 268-280
// Preload grenade scene if not set in inspector
if (GrenadeScene == null)
{
    GrenadeScene = GD.Load<PackedScene>("res://scenes/projectiles/FlashbangGrenade.tscn");
    if (GrenadeScene != null)
    {
        LogToFile($"[Player.Grenade] Grenade scene loaded");
    }
}
```

The C# player always loads FlashbangGrenade, ignoring GrenadeManager entirely!

### Solution: Update C# Player to Use GrenadeManager

**Player.cs (AFTER FIX):**
```csharp
// Get grenade scene from GrenadeManager (supports grenade type selection)
// GrenadeManager handles the currently selected grenade type (Flashbang or Frag)
if (GrenadeScene == null)
{
    var grenadeManager = GetNodeOrNull("/root/GrenadeManager");
    if (grenadeManager != null && grenadeManager.HasMethod("get_current_grenade_scene"))
    {
        var sceneVariant = grenadeManager.Call("get_current_grenade_scene");
        GrenadeScene = sceneVariant.As<PackedScene>();
        if (GrenadeScene != null)
        {
            var grenadeNameVariant = grenadeManager.Call("get_grenade_name", grenadeManager.Get("current_grenade_type"));
            var grenadeName = grenadeNameVariant.AsString();
            LogToFile($"[Player.Grenade] Grenade scene loaded from GrenadeManager: {grenadeName}");
        }
        else
        {
            LogToFile($"[Player.Grenade] WARNING: GrenadeManager returned null grenade scene");
        }
    }
    else
    {
        // Fallback to flashbang if GrenadeManager is not available
        var grenadePath = "res://scenes/projectiles/FlashbangGrenade.tscn";
        GrenadeScene = GD.Load<PackedScene>(grenadePath);
        if (GrenadeScene != null)
        {
            LogToFile($"[Player.Grenade] Grenade scene loaded from fallback: {grenadePath}");
        }
        else
        {
            LogToFile($"[Player.Grenade] WARNING: Grenade scene not found at {grenadePath}");
        }
    }
}
else
{
    LogToFile($"[Player.Grenade] Grenade scene already set in inspector");
}
```

### Why This Wasn't Caught Earlier

1. **GDScript player.gd** was already updated to use GrenadeManager
2. The user was running the **C# version** of the game (csharp levels)
3. The C# Player.cs was never updated when GrenadeManager was implemented
4. Logs showed "Grenade scene loaded" without specifying the type, hiding the issue

### Files Modified

1. `Scripts/Characters/Player.cs` - Added GrenadeManager integration for grenade type selection

### Diagnostic Improvements

The new logging now shows which grenade type is loaded:
- `[Player.Grenade] Grenade scene loaded from GrenadeManager: Frag Grenade`
- `[Player.Grenade] Grenade scene loaded from fallback: res://scenes/projectiles/FlashbangGrenade.tscn`
- `[Player.Grenade] Grenade scene already set in inspector`

This makes it immediately clear which grenade type the player is using.

### Lessons Learned

1. **Keep GDScript and C# implementations in sync** when adding new features
2. **Log the actual values/types** not just "scene loaded" - include what was loaded
3. **Check for multiple player implementations** when debugging player-related issues
4. **The log message source (file:line)** is critical for tracing issues

### Expected Behavior After Fix

After rebuilding with this fix:
1. Select "Frag Grenade" in armory menu
2. Level restarts
3. Log should show: `[Player.Grenade] Grenade scene loaded from GrenadeManager: Frag Grenade`
4. Thrown grenade should be FragGrenade with shrapnel mechanics

---

## Phase 10: Two Additional Issues Found (2026-01-22 06:32)

### New Log: `game_log_20260122_063204.txt`

User reported two issues:
1. "при выборе гранаты в armory игра застревает и приходится вручную нажимать quick restart" (when selecting a grenade in armory, the game freezes and requires manual quick restart)
2. "граната не наносит фугасный урон (волной), а должна наносить 99 урона всем в зоне волны" (grenade doesn't deal explosive damage (blast wave), should deal 99 damage to all in the blast zone)

### Log Analysis

**Issue 1: Game Freeze / Restart Loop**

Looking at the timestamps:
```
[06:32:06] [INFO] [PauseMenu] Armory button pressed
[06:32:08] [INFO] [GrenadeManager] Grenade type changed from Flashbang to Frag Grenade
[06:32:08] [INFO] [GrenadeManager] Restarting level due to grenade type change
...
[06:32:08] [INFO] [Player.Grenade] Grenade scene loaded from GrenadeManager: Frag Grenade
...
[06:32:10] [INFO] [PenultimateHit] Resetting all effects (scene change detected)
...
[06:32:11] [INFO] [PenultimateHit] Resetting all effects (scene change detected)
...
[06:32:13] [INFO] [Player.Grenade] Tutorial level detected - infinite grenades enabled
```

The level keeps restarting rapidly (06:32:08 → 06:32:10 → 06:32:11 → 06:32:13) multiple times before finally stabilizing.

**Root Cause**: The game is **still paused** when GrenadeManager tries to restart the level. The pause state was not cleared before calling `reload_current_scene()`.

**Evidence**: The `levels_menu.gd` correctly unpauses before changing scenes:
```gdscript
# In levels_menu.gd:67
get_tree().paused = false
```

But `grenade_manager.gd` does NOT unpause:
```gdscript
# In grenade_manager.gd:_restart_current_level()
# Missing: get_tree().paused = false
get_tree().reload_current_scene()  # Reloads while still paused!
```

**Issue 2: Grenade Explosive Damage**

Looking at `frag_grenade.gd`:
```gdscript
@export var explosion_damage: int = 2  # Should be 99!
```

The grenade was dealing only 2 damage, scaled by distance. User requirement states it should deal 99 damage to ALL enemies in the blast zone (flat damage, no distance scaling).

### Solutions Applied

**Fix 1: Unpause Game Before Restart**

In `scripts/autoload/grenade_manager.gd`:
```gdscript
func _restart_current_level() -> void:
    FileLogger.info("[GrenadeManager] Restarting level due to grenade type change")

    # IMPORTANT: Unpause the game before restarting
    # This prevents the game from getting stuck in paused state when
    # changing grenades from the armory menu while the game is paused
    get_tree().paused = false

    # Restore hidden cursor for gameplay (confined and hidden)
    Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

    # Use GameManager to restart if available
    var game_manager: Node = get_node_or_null("/root/GameManager")
    if game_manager and game_manager.has_method("restart_scene"):
        game_manager.restart_scene()
    else:
        # Fallback: reload current scene directly
        get_tree().reload_current_scene()
```

**Fix 2: 99 Explosive Damage**

In `scripts/projectiles/frag_grenade.gd`:
```gdscript
## Direct explosive (HE/blast wave) damage to enemies in effect radius.
## Per user requirement: should deal 99 damage to all enemies in the blast zone.
@export var explosion_damage: int = 99
```

And updated `_apply_explosion_damage()` to apply flat damage (no distance scaling):
```gdscript
func _apply_explosion_damage(enemy: Node2D) -> void:
    var distance := global_position.distance_to(enemy.global_position)

    # Flat damage to all enemies in blast zone - no distance scaling
    var final_damage := explosion_damage

    # Try to apply damage through various methods
    if enemy.has_method("on_hit_with_info"):
        var hit_direction := (enemy.global_position - global_position).normalized()
        for i in range(final_damage):
            enemy.on_hit_with_info(hit_direction, null)
    elif enemy.has_method("on_hit"):
        for i in range(final_damage):
            enemy.on_hit()

    FileLogger.info("[FragGrenade] Applied %d HE damage to enemy at distance %.1f" % [final_damage, distance])
```

### Files Modified

1. `scripts/autoload/grenade_manager.gd` - Added unpause before level restart
2. `scripts/projectiles/frag_grenade.gd` - Changed explosion_damage to 99 and removed distance scaling

### Expected Behavior After Fix

1. **Grenade Selection**: Select grenade in armory → game unpauses → level restarts cleanly (no freeze)
2. **Explosive Damage**: Frag grenade deals 99 damage to ALL enemies in the blast zone (250px radius)
3. **Shrapnel Damage**: Each of the 4 shrapnel pieces still deals 1 damage (unchanged)

### Lessons Learned

1. **Pause state must be cleared** before scene transitions initiated from paused menus
2. **Follow existing patterns** - `levels_menu.gd` already had the correct unpause logic
3. **User requirements must be interpreted literally** - "99 damage to all" means flat 99, not scaled
4. **Log timestamps reveal restart loops** - rapid repeated "scene change detected" indicates a loop

---

## Phase 11: Remove Timer - Impact-Only Explosion (2026-01-22 07:04)

### New Logs: `game_log_20260122_070403.txt` and `game_log_20260122_070520.txt`

User reported: "у этой гранаты не должно быть таймера, должна взрываться при падении/столкновении с препятствием" (this grenade should not have a timer, it should explode on landing/collision with an obstacle)

### Log Analysis

**First Log (`game_log_20260122_070403.txt`)** shows successful impact explosions:
```
[07:04:28] [INFO] [FragGrenade] Grenade thrown - impact detection enabled
[07:04:29] [INFO] [GrenadeBase] Grenade landed at (447.9349, 822.3268)
[07:04:29] [INFO] [FragGrenade] Impact detected - exploding immediately!
[07:04:29] [INFO] [GrenadeBase] EXPLODED at (447.9349, 822.3268)!
```

This shows the impact detection IS working when the grenade is thrown and lands.

**Second Log (`game_log_20260122_070520.txt`)** shows the timer issue:
```
[07:05:34] [INFO] [GrenadeBase] Grenade created at (0, 0) (frozen)
[07:05:34] [INFO] [FragGrenade] Shrapnel scene loaded from: res://scenes/projectiles/Shrapnel.tscn
[07:05:34] [INFO] [GrenadeBase] Timer activated! 4.0 seconds until explosion
[07:05:34] [INFO] [Player.Grenade] Timer started, grenade created at (450, 1250)
...
[07:05:38] [INFO] [GrenadeBase] EXPLODED at (397.1667, 1250)!
```

The grenade activated at 07:05:34 and exploded at 07:05:38 - exactly 4 seconds later, via the timer, NOT via impact.

### Critical Finding: Timer Still Active

Looking at the flow:
1. Player starts Step 1 (G + RMB pressed) - grenade created
2. Timer activates (4 seconds countdown)
3. Player doesn't complete the throw (stays in "aiming" mode)
4. Timer expires after 4 seconds → grenade explodes

The user is correct: **The frag grenade should NOT have a timer at all.** It should ONLY explode on impact (landing or hitting a wall). If the player holds the grenade without throwing it, it should remain "safe" until thrown.

### Original Issue Requirement

From Issue #188:
> "взрывается при приземлении/ударе об стену (**без таймера**)"
> Translation: "explodes on landing/hitting a wall (**without timer**)"

The key phrase is "без таймера" - "without timer".

### Solution: Disable Timer for Frag Grenades

**Root Cause**: The base class `GrenadeBase` calls `activate_timer()` which starts a countdown. The frag grenade was inheriting this behavior.

**Fix Applied**: Override `activate_timer()` in `FragGrenade` to NOT start the timer countdown:

```gdscript
## Override to prevent timer countdown for frag grenades.
## Frag grenades explode ONLY on impact (landing or wall hit), NOT on a timer.
## Per issue requirement: "без таймера" = "without timer"
func activate_timer() -> void:
    # Set _timer_active to true so landing detection works (line 114 in base class)
    # But do NOT set _time_remaining - no countdown, no timer-based explosion
    if _timer_active:
        FileLogger.info("[FragGrenade] Already activated")
        return
    _timer_active = true
    # Set to very high value so timer never triggers explosion
    # The grenade will only explode on impact (landing or wall hit)
    _time_remaining = 999999.0  # Effectively infinite

    # Play activation sound (pin pull)
    if not _activation_sound_played:
        _activation_sound_played = true
        _play_activation_sound()
    FileLogger.info("[FragGrenade] Pin pulled - waiting for impact (no timer, impact-triggered only)")
```

Also overrode `_physics_process()` to disable the blinking countdown effect (since there's no countdown).

### Why _timer_active is Still Set to True

The `_timer_active` flag is used by the base class's `_physics_process()` to check for grenade landing:

```gdscript
# In grenade_base.gd:114
if not _has_landed and _timer_active:
    # ... landing detection logic ...
```

We need `_timer_active = true` so the landing detection works, but we set `_time_remaining = 999999.0` so the timer-based explosion never triggers.

### Files Modified

1. `scripts/projectiles/frag_grenade.gd`:
   - Updated class documentation to clarify "NO timer"
   - Overrode `activate_timer()` to disable timer countdown
   - Overrode `_physics_process()` to disable blinking effect

### Expected Behavior After Fix

1. **Pin Pull**: Player initiates grenade (G + RMB) - sound plays, no countdown starts
2. **Holding Grenade**: Player can hold the grenade indefinitely without it exploding
3. **Throw**: Player throws grenade - impact detection enabled
4. **Impact**: Grenade explodes ONLY when:
   - It lands on the ground (velocity drops below threshold)
   - It hits a wall/obstacle (StaticBody2D or TileMap collision)
5. **No Timer**: The grenade will NEVER explode from a timer countdown

### Lessons Learned

1. **Re-read requirements carefully** - "без таймера" was explicitly stated in the original issue
2. **Don't assume inherited behavior is desired** - the timer was inherited from GrenadeBase but not wanted for frag grenades
3. **Different grenade types have different mechanics** - flashbangs use timers, frag grenades use impact triggers
4. **Override lifecycle methods when needed** - `activate_timer()` override was the right approach
