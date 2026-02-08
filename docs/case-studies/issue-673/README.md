# Case Study: Issue #673 — Invisibility Suit Active Item

## Issue Summary
**Title:** добавь активный предмет - костюм невидимости
**Author:** Jhon-Crow
**Requested Feature:** Add an invisibility suit as a selectable active item in the armory.

### Requirements (translated from Russian)
- On activation (Space key), the player becomes invisible to enemies
- Visual effect: transparent ripple (like the Predator movie cloaking device)
- 2 charges per battle
- Effect lasts 4 seconds per activation

## Architecture Analysis

### Existing Active Item System
The game already has an active item system with the flashlight as the sole implementation:
- **ActiveItemManager** (autoload singleton): Manages item selection via enum + dictionary
- **ArmoryMenu**: UI grid for selecting active items, integrated with Apply button
- **Player script**: Initializes and handles input for active items in `_ready()` and `_process()`
- **Input**: Space key mapped to `flashlight_toggle` action

### Enemy Detection Systems
Enemies detect the player through multiple systems that must respect invisibility:
1. **Vision System** (`_check_player_visibility()`): Multi-point raycast, FOV-based
2. **Sound/Gunshot Detection** (`on_sound_heard_with_intensity()`): Reload/gunshot sounds
3. **Flashlight Detection** (`FlashlightDetectionComponent`): Beam-in-FOV sampling
4. **Threat Sphere**: Area2D that detects bullets within 100px

### Shader System
Existing shaders in the project use:
- `shader_type canvas_item` with `hint_screen_texture`
- `textureLod(..., 0.0)` for `gl_compatibility` mode support
- `SCREEN_UV` for screen-space effects

## Solution Design

### Approach: Per-Sprite Material Shader
Since this is a 2D top-down game with a multi-sprite player model (Body, Head, LeftArm, RightArm, WeaponMount), the invisibility effect is applied as a `ShaderMaterial` on each sprite. The shader:
- Reads the screen texture behind the sprite
- Applies time-varying UV offset per RGB channel (chromatic aberration distortion)
- Creates the classic Predator "transparent ripple" look
- Uses a `mix_amount` uniform to smoothly fade in/out

### Components
1. **`invisibility_cloak.gdshader`** — Predator-style distortion shader
2. **`invisibility_suit_effect.gd`** — Effect controller script (manages shader, charges, timer)
3. **ActiveItemManager** — Extended with `INVISIBILITY_SUIT` enum entry
4. **Player script** — Extended with invisibility initialization and input handling
5. **Enemy script** — `_check_player_visibility()` returns early when player is invisible

### Key Design Decisions
- **Invisibility blocks vision only, not sound**: Enemies can still hear gunshots and reload sounds during invisibility, keeping gameplay balanced
- **Per-sprite shader vs screen shader**: Per-sprite approach is more performant and only affects the player model, not the entire screen
- **Charges system**: 2 charges per battle (not per level), resets on level restart
- **Duration**: 4 seconds per activation, with smooth fade-in/fade-out transitions

## References
- [Almost Invisible Character Shader](https://godotshaders.com/shader/almost-invisible-character/) — Base reference for chromatic distortion approach
- [Transparent Ripples Shader](https://godotshaders.com/shader/transparent-ripples/) — Ripple pattern reference
- Existing `last_chance.gdshader` in this project — Ripple distortion pattern reference
