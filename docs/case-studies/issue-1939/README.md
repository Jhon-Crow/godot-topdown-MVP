# Issue 1939: Red Dot Cursor

## Request

Replace the visible mouse cursor with a glowing red dot, visually close to the laser sight dot. Hidden gameplay cursor modes should remain hidden.

## Collected Data

- GitHub issue data: `issue.json`
- Issue comments snapshot: `comments.json`
- Current project cursor management uses Godot mouse modes:
  - Gameplay code commonly switches to `Input.MOUSE_MODE_CONFINED_HIDDEN`.
  - Menus, pause screens, score screens, and completion screens switch to visible or confined visible modes.

## External Reference

Godot's documentation recommends using project settings or `Input.set_custom_mouse_cursor()` for hardware cursors. Cursor images must be at most 256x256, and 128x128 or smaller is recommended. Hardware cursors avoid the extra frame of latency that a sprite-based software cursor would add.

Source: https://docs.godotengine.org/en/4.0/tutorials/inputs/custom_mouse_cursor.html

## Solution Options

1. Set `display/mouse_cursor/custom_image` in `project.godot`.
   - Applies consistently to visible cursor modes.
   - Keeps existing hidden cursor behavior unchanged.
   - Uses Godot's hardware cursor path.

2. Add a cursor autoload that calls `Input.set_custom_mouse_cursor()`.
   - More flexible if multiple cursor shapes are needed later.
   - Adds code and another autoload for a single global cursor.

3. Hide the OS cursor and render a `Sprite2D` at mouse position.
   - Allows animated effects.
   - Adds at least one frame of latency and needs scene/runtime management.

## Implemented Choice

Option 1 was implemented with a 32x32 SVG asset at `res://assets/sprites/ui/red_dot_cursor.svg` and a centered hotspot at `(16, 16)`.
