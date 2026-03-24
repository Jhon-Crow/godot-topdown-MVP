# Issue #809: Weapon Training Hints System

## Summary

This case study documents the implementation of a weapon-specific tutorial/hints system that shows contextual tips when a player uses a new weapon for the first time.

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/809

## Requirements

From the issue (translated from Russian):

1. **Weapon Hints on Level Start:** When a player starts any level with a new weapon (switched to it), tutorial hints about its features should appear (similar to the tutorial system).

2. **Settings Option:** Add a select/dropdown in settings with three modes:
   - **Always** - Show hints every time
   - **First time only** - Show hints only when this specific weapon is used for the first time
   - **Never** - Never show weapon hints

## Existing Codebase Analysis

### Current Tutorial System

The game already has a sophisticated tutorial system in `scripts/levels/tutorial_level.gd`:

- Uses floating `RichTextLabel` hints near the player
- Supports multiple simultaneous hints with unique colors
- Hints are positioned above the player and update positions in `_process()`
- Each hint has a unique key and can be shown/dismissed independently
- Supports multi-step hints with red highlight on the next step

**Hint Colors Used:**
```gdscript
const HINT_COLOR_FIRE_MODE := Color(0.3, 0.9, 1.0, 1.0)      # Cyan
const HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)         # Green
const HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)       # Orange
const HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)    # Purple
const HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)          # Cyan
const HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)    # Yellow
const HINT_COLOR_GRENADE_LAUNCHER := Color(1.0, 0.4, 0.2, 1.0) # Red-orange
```

### Available Weapons

From `scripts/autoload/game_manager.gd` and `scripts/ui/armory_menu.gd`:

| Weapon ID | Name | Description |
|-----------|------|-------------|
| `makarov_pm` | PM | Makarov PM — 9x18mm starting pistol |
| `m16` | M16 | Assault rifle with fire mode switch (B key) |
| `shotgun` | Shotgun | Pump-action shotgun |
| `mini_uzi` | Mini UZI | Compact SMG |
| `silenced_pistol` | Silenced Pistol | Quiet pistol |
| `sniper` | ASVK | Sniper rifle with scope |
| `revolver` | RSh-12 | Revolver with cylinder reload |
| `ak_gl` | AK+GL | AK with underbarrel grenade launcher |

### Settings System

The game uses `ExperimentalSettings` autoload (`scripts/autoload/experimental_settings.gd`) for toggle settings with persistence via `ConfigFile`.

Settings are saved to `user://experimental_settings.cfg`.

Pattern for adding new settings:
1. Add variable declaration
2. Add setter/getter methods
3. Add to `_save_settings()` and `_load_settings()`
4. Emit `settings_changed` signal on change

### Level Script Pattern

Levels use `_ready()` to:
1. Find player node
2. Setup weapon based on `GameManager.get_selected_weapon()`
3. Connect signals
4. Initialize UI

## Research: Game Tutorial Best Practices

### Industry Standards

From [Inworld AI's tutorial design guide](https://inworld.ai/blog/game-ux-best-practices-for-video-game-tutorial-design):
- **Invisible tutorials** integrate instructions subtly into mechanics
- **Playable tutorials** immerse players in interactive learning
- **Mixed approach** explains a concept then has the player experience it immediately

From [Hotline Miami Wiki](https://hotlinemiami.fandom.com/wiki/Tutorial):
- Tutorial introduces basic weapon mechanics early
- Uses contextual prompts during gameplay
- Shows controls only when relevant (e.g., weapon pickup)

### Best Practices Applied

1. **Progressive Disclosure:** Show weapon hints only when relevant (weapon equipped)
2. **Non-intrusive:** Floating hints that don't block gameplay
3. **Dismissable:** Hints disappear after action is completed
4. **Customizable:** Three modes let players control their experience

## Proposed Solution

### Architecture

1. **New Autoload: `WeaponHintsSettings`**
   - Stores hint display mode preference
   - Tracks which weapons have been used (for "first time only" mode)
   - Persisted to `user://weapon_hints_settings.cfg`

2. **New Component: `WeaponHintsComponent`**
   - Reusable component that can be added to any level
   - Shows weapon-specific hints based on current weapon
   - Respects user's display mode preference

3. **Integration:**
   - Add component to all level scripts
   - Add settings UI to an existing menu (Experimental or new submenu)

### Weapon-Specific Hints

| Weapon | Hints |
|--------|-------|
| PM | Basic pistol controls, reload (R→F→R) |
| M16 | Fire mode switch (B), reload (R→F→R) |
| Shotgun | Pump action, shell loading (RMB sequence) |
| Mini UZI | High fire rate, reload |
| Silenced Pistol | Stealth benefit, same reload as PM |
| Sniper | Scope (RMB), bolt-action reload (arrows) |
| Revolver | Cylinder reload, hammer cock |
| AK+GL | Underbarrel grenade launcher (RMB) |

### Settings UI

Add to Experimental Menu or create dedicated "Gameplay" menu:
```
Weapon Hints: [Always ▼]
             [ ] Always
             [ ] First time only (default)
             [ ] Never
```

## Implementation Plan

1. Create `WeaponHintsSettings` autoload
2. Create `WeaponHintsComponent` script
3. Define hint texts for each weapon
4. Add settings UI
5. Integrate component into all levels
6. Test with each weapon type

## Files to Modify/Create

### New Files
- `scripts/autoload/weapon_hints_settings.gd`
- `scripts/components/weapon_hints_component.gd`

### Modified Files
- `project.godot` - Add new autoload
- `scripts/ui/experimental_menu.gd` - Add settings dropdown (or create new menu)
- `scenes/ui/ExperimentalMenu.tscn` - Add UI elements
- All level scripts - Add component initialization

## References

- [Game UX: Best practices for video game tutorial design](https://inworld.ai/blog/game-ux-best-practices-for-video-game-tutorial-design)
- [Best Practices for Game UI/UX Design](https://genieee.com/best-practices-for-game-ui-ux-design/)
- [Hotline Miami Tutorial](https://hotlinemiami.fandom.com/wiki/Tutorial)
- [Hotline Miami Weapons](https://hotlinemiami.fandom.com/wiki/Weapons)
