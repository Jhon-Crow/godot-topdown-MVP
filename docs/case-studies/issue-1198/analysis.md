# Case Study: Issue #1198 — Add Icons to Pause Menu Items

## Issue Summary

**Title:** добавь значки особым пунктам в меню (Add icons to special menu items)

**Request:**
- Add same-color icons to pause menu buttons
- Gear icon for Settings
- Crossed swords for Armory
- Fitting distinct icons for each button
- Icons should be different enough and reflect the purpose of each item
- Add screenshot of final pause menu as a PR comment

## Analysis

### Current State (Before Fix)

The pause menu (`scenes/ui/PauseMenu.tscn`) has 8 buttons with plain text only:
- Resume
- Armory
- Levels
- Training
- Рогалик (Roguelike)
- Arena
- Settings
- Quit

The neon button theme (`resources/themes/neon_button_theme.tres`) already has `icon_normal_color` defined as `Color(1.0, 0.85, 0.92, 1.0)` — matching the font color. This means icons will be automatically tinted to match the button text color by the theme, requiring only white SVG icons.

### Godot Icon Support in Buttons

Godot 4's `Button` node has a built-in `icon` property of type `Texture2D`. Buttons render the icon to the left of the text by default. The theme controls icon coloring through:
- `icon_normal_color`
- `icon_hover_color`
- `icon_focus_color`
- `icon_pressed_color`
- `icon_disabled_color`

All these were already set in the neon theme to match font colors — so adding icons is purely additive.

### Chosen Icons (SVG, 32×32)

| Button | Icon | Rationale |
|--------|------|-----------|
| Resume | Play triangle (▶) | Universal play/resume symbol |
| Armory | Crossed swords (⚔) | Directly requested — weapons/combat |
| Levels | Map with pin | Navigation / level selection |
| Training | Bullseye/crosshair | Target practice, precision |
| Рогалик | Dice | Randomness, roguelike genre |
| Arena | Shield with star | Combat arena, glory |
| Settings | Cogwheel/gear | Directly requested — configuration |
| Quit | Power button | Universal exit symbol |

### Implementation Approach

- Created 8 SVG icons in `assets/sprites/ui/menu_icons/`
- SVGs use white fill/stroke (Godot's icon tinting will apply the neon theme color)
- Updated `PauseMenu.tscn` to reference icons via `ext_resource` entries and assign them to each button's `icon` property
- No script changes needed — all visual

### Alternative Approaches Considered

1. **Use Unicode emoji in button text** — Works but emoji rendering is platform-dependent and may not match the neon aesthetic
2. **Use existing sprite icons** — The existing weapon icons in `assets/sprites/weapons/` are game-world items, not UI metaphors; not suitable for menu navigation
3. **Use Godot's built-in theme icons** — No built-in icons match the game's needs specifically
4. **Custom PNG icons** — Would require pixel art creation or external tools; SVG is simpler and scales perfectly

### Files Changed

- `scenes/ui/PauseMenu.tscn` — Added icon ext_resource references and icon property to each button
- `assets/sprites/ui/menu_icons/icon_resume.svg` — Play triangle
- `assets/sprites/ui/menu_icons/icon_armory.svg` — Crossed swords
- `assets/sprites/ui/menu_icons/icon_levels.svg` — Map with pin
- `assets/sprites/ui/menu_icons/icon_training.svg` — Bullseye/crosshair
- `assets/sprites/ui/menu_icons/icon_roguelike.svg` — Dice
- `assets/sprites/ui/menu_icons/icon_arena.svg` — Shield with star
- `assets/sprites/ui/menu_icons/icon_settings.svg` — Cogwheel
- `assets/sprites/ui/menu_icons/icon_quit.svg` — Power button
