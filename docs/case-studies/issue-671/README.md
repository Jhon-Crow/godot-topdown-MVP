# Case Study: Issue #671 — AI Helmet Active Item

## Problem Statement

Add a new active item — an AI-powered helmet that predicts enemy movements.

### Requirements (from issue):
1. **Activation**: Press Space to activate the helmet
2. **Prediction**: Shows red outlines of enemies at their predicted position 1 second in the future
3. **Duration**: Effect lasts 10 seconds per activation
4. **Charges**: 2 charges per battle (level)

## Codebase Analysis

### Existing Active Item System

The game already has an active item system with one item (Flashlight):

- **ActiveItemManager** (`scripts/autoload/active_item_manager.gd`): Autoload singleton managing item selection via enum `ActiveItemType`. Currently has `NONE` (0) and `FLASHLIGHT` (1).
- **ArmoryMenu** (`scripts/ui/armory_menu.gd`): UI for selecting items. Dynamically reads from `ActiveItemManager.get_all_active_item_types()`, so new items are automatically displayed.
- **Player** (`scripts/characters/player.gd`): Handles flashlight input (Space key) and initialization in `_init_flashlight()` / `_handle_flashlight_input()`.

### Enemy Movement System

Enemies (`scripts/objects/enemy.gd`) use:
- `NavigationAgent2D` for pathfinding
- `velocity` property (inherited from `CharacterBody2D`) for movement
- Multiple AI states: IDLE, COMBAT, SEEKING_COVER, FLANKING, PURSUING, etc.
- Movement speeds: `move_speed` (patrol) and `combat_move_speed` (combat)

### Prediction Approach

To predict where enemies will be in 1 second:
- Use the enemy's current `velocity` vector
- Extrapolate: `predicted_position = current_position + velocity * 1.0`
- This is simple but effective for a gameplay feature — it shows the general direction enemies are moving

### Visual Approach: Ghost Outlines

For the red outline effect, we create ghost sprites:
- Duplicate each enemy's visual model at the predicted position
- Apply red modulation with transparency
- The ghosts update every frame during the 10-second effect window

### Existing Patterns Used

| Pattern | Source | Applied To |
|---------|--------|------------|
| Active item enum + data dict | `active_item_manager.gd` | Add `AI_HELMET` type |
| Scene loading + instantiation | `player.gd` `_init_flashlight()` | `_init_ai_helmet()` |
| Input handling in `_physics_process` | `_handle_flashlight_input()` | `_handle_ai_helmet_input()` |
| Charge-based system | Grenade system (`grenade_manager.gd`) | Helmet charges |
| Group-based enemy iteration | `get_tree().get_nodes_in_group("enemies")` | Ghost rendering |

## Solution Design

### Architecture

```
ActiveItemManager (autoload)
  └── AI_HELMET enum type + data

Player (character)
  └── HelmetEffect (Node2D, child of PlayerModel)
       ├── Manages charges and activation timer
       ├── Creates ghost sprites per enemy
       └── Updates ghost positions each frame

Enemy ghosts: Sprite2D nodes added to level root
  └── Red-tinted, semi-transparent copies of enemy sprites
  └── Positioned at predicted_position = enemy.position + enemy.velocity * 1.0
```

### Key Design Decisions

1. **Ghost sprites vs shader outline**: Ghost sprites are simpler and more visually clear. A shader-based outline would require per-enemy material changes and is harder to position at predicted locations.

2. **Velocity extrapolation vs AI prediction**: Simple velocity extrapolation (`pos + vel * dt`) provides good-enough predictions for gameplay. The existing `PlayerPredictionComponent` is designed for enemy-to-player prediction, not the reverse.

3. **Press to activate vs hold**: The issue says "на пробел" (on Space), implying a single press activation rather than hold (which is how flashlight works). The helmet activates on press and runs for 10 seconds.

4. **Charges reset per level**: Charges reset when the level restarts, similar to how grenade counts work.

## Files Modified

| File | Change |
|------|--------|
| `scripts/autoload/active_item_manager.gd` | Add `AI_HELMET` enum, data, and `has_ai_helmet()` |
| `scripts/characters/player.gd` | Add helmet init, input handling, and getter methods |
| `scripts/effects/helmet_effect.gd` | **NEW** — Helmet effect logic |
| `scenes/effects/HelmetEffect.tscn` | **NEW** — Helmet effect scene |
| `tests/unit/test_active_item_manager.gd` | Add tests for AI_HELMET type |
| `tests/unit/test_helmet_effect.gd` | **NEW** — Unit tests for helmet effect |

## Bug Report: "не работает" (Doesn't Work)

### Timeline Reconstruction

1. User selected AI Helmet from the Armory Menu (log line: `[ActiveItemManager] Active item changed from None to AI Helmet`)
2. Level restarted automatically (standard behavior when changing active items)
3. Player.cs `_Ready()` was called — initialized flashlight check (logged: `[Player.Flashlight] No flashlight selected`)
4. **No AI Helmet initialization occurred** — zero helmet-related log entries after level restart
5. User pressed Space during gameplay — nothing happened (no helmet activation logged)

### Root Cause Analysis

The game log from the user's session (`game_log_20260209_015706.txt`) revealed that:

- **All level scenes use the C# Player** (`scenes/characters/csharp/Player.tscn` → `Scripts/Characters/Player.cs`)
- **The initial implementation only added helmet integration to the GDScript Player** (`scripts/characters/player.gd`)
- The C# `Player.cs` had zero helmet-related code: no field declarations, no `InitAIHelmet()`, no `HandleAIHelmetInput()`
- The `ActiveItemManager.gd` (GDScript autoload) correctly tracked the AI Helmet selection
- The `HelmetEffect.gd` (GDScript) was never instantiated because no code called it

**Evidence:** In the 3900+ line game log, the only helmet-related entry was:
```
[ActiveItemManager] Active item changed from None to AI Helmet
```
There were zero entries containing "AIHelmet", "HelmetEffect", or any initialization/activation messages.

### Fix Applied

Added AI Helmet integration to `Scripts/Characters/Player.cs` following the exact same pattern as the Flashlight integration (Issue #546):

| Component | Flashlight (existing) | AI Helmet (added) |
|-----------|----------------------|-------------------|
| Fields | `_flashlightEquipped`, `_flashlightNode` | `_aiHelmetEquipped`, `_aiHelmetNode` |
| Init | `InitFlashlight()` | `InitAIHelmet()` |
| Input | `HandleFlashlightInput()` (hold) | `HandleAIHelmetInput()` (just_pressed) |
| Helpers | `is_flashlight_on()` | `is_ai_helmet_active()`, `get_ai_helmet_charges()` |
| Scene attachment | PlayerModel (child) | Level root (child) |

Key difference: The helmet attaches to the **level root** (not PlayerModel) so ghost drawings use global coordinates, matching the GDScript implementation.

### Compatibility Notes

- Enemies are GDScript `CharacterBody2D` nodes in the "enemies" group — compatible with `helmet_effect.gd`
- The C# Player calls GDScript methods via `Call("activate")` / `Call("is_active")` etc., matching the cross-language pattern used by flashlight
- Both GDScript `player.gd` and C# `Player.cs` now have helmet integration for full variant coverage

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/671
- Flashlight PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/551
- Godot CharacterBody2D velocity: https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html
- User bug report: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/684#issuecomment-3868506415
