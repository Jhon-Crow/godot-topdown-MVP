# Case Study: Issue #896 — Add Persistence (добавь persist)

## Issue Description

**Title**: добавь persist (add persist)

**Original text (Russian)**:
> после выхода и входа в игру игрок должен быть на последнем выбранном уровне, с последними выбранными предметами (то есть можно продолжить играть тот же уровень с теми же вещами, что и в последний раз).

**Translation**: After leaving and re-entering the game, the player should be on the last selected level, with the last selected items (i.e., they can continue playing the same level with the same things as the last time).

## Requirements

1. **Persist last selected level** — When the game starts, load the player into the last level they were playing.
2. **Persist last selected weapon** — Remember which weapon was selected.
3. **Persist last selected grenade** — Remember which grenade type was selected.
4. **Persist last selected active item** — Remember which special/active item was equipped.
5. **Persist unlocked weapons** — Remember which weapons have been unlocked via the armory.
6. **Persist unlocked grenades** — Remember which grenades have been unlocked via the armory.
7. **Persist unlocked active items** — Remember which active items have been unlocked via the armory.

## Current State

The project already has a `ProgressManager` that persists best scores/ranks per level using `user://progress.cfg` (ConfigFile). A similar pattern is used by `DifficultyManager` and `ExperimentalSettings`.

However, the following game state is **NOT** persisted between game sessions:
- `GameManager.selected_weapon` — always resets to "makarov_pm"
- `GameManager.unlocked_weapons` — always resets to only makarov_pm unlocked
- `GrenadeManager.current_grenade_type` — always resets to FLASHBANG
- `GrenadeManager.unlocked_grenades` — always resets to only FLASHBANG unlocked
- `ActiveItemManager.current_active_item` — always resets to NONE
- `ActiveItemManager.unlocked_active_items` — always resets to all locked
- Last selected level — not remembered at all

## Solution Design

### Approach: Add save/load to existing managers

The cleanest approach follows the existing patterns in the codebase:
- `ExperimentalSettings` saves/loads individual boolean flags to a ConfigFile
- `DifficultyManager` saves/loads the difficulty enum value
- `ProgressManager` saves/loads score data

We should add persistence to the three existing managers (GameManager, GrenadeManager, ActiveItemManager) by:
1. Adding `_save_state()` and `_load_state()` methods
2. Calling save when state changes (weapon selection, unlock, etc.)
3. Loading state on `_ready()`

Additionally, we need to track and restore the last visited level, which the `LevelsMenu` should save when a level is selected.

### Save File Strategy

We'll create a new save file `user://game_state.cfg` specifically for game state persistence. This keeps it separate from:
- `user://progress.cfg` — best scores per level
- `user://difficulty_settings.cfg` — difficulty selection
- `user://experimental_settings.cfg` — experimental features

### Implementation Details

**user://game_state.cfg structure**:
```
[game]
selected_weapon = "makarov_pm"
last_level = "res://scenes/levels/LabyrinthLevel.tscn"

[unlocked_weapons]
makarov_pm = true
m16 = false
...

[grenade]
current_type = 0    # GrenadeType enum int

[unlocked_grenades]
0 = true    # FLASHBANG
1 = false   # FRAG
...

[active_item]
current_type = 0    # ActiveItemType enum int

[unlocked_active_items]
0 = true    # NONE
1 = false   # FLASHLIGHT
...
```

### Key Decisions

1. **Save file location**: `user://game_state.cfg` — Godot's user:// path is platform-appropriate (e.g., `~/.local/share/GodotTopDownTemplate/` on Linux)
2. **Save trigger**: Save on every state change (when weapon/grenade/item selected or unlocked), same pattern as ExperimentalSettings
3. **Load trigger**: Load in `_ready()` of each manager
4. **Default values**: When no save file exists, use the existing defaults (makarov_pm unlocked, flashbang unlocked, etc.)
5. **Level persistence**: Save in GameManager since it already knows about the level system; load on startup and navigate to saved level instead of main scene

## Existing Similar Solutions

- **ConfigFile pattern**: Already used by DifficultyManager, ProgressManager, ExperimentalSettings in this codebase
- **Godot SaveGame tutorial**: https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html
- **JSON approach**: Alternative to ConfigFile (used in more complex games), not needed here

## References

- `scripts/autoload/game_manager.gd` — Manages selected_weapon and unlocked_weapons
- `scripts/autoload/grenade_manager.gd` — Manages current_grenade_type and unlocked_grenades
- `scripts/autoload/active_item_manager.gd` — Manages current_active_item and unlocked_active_items
- `scripts/autoload/experimental_settings.gd` — Reference implementation for ConfigFile persistence
- `scripts/autoload/difficulty_manager.gd` — Reference implementation for simple value persistence
- `scripts/autoload/progress_manager.gd` — Reference implementation for complex data persistence
- `scripts/ui/levels_menu.gd` — Level selection UI, needs to save last level
