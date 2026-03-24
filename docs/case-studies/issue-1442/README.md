# Case Study: Level Editor (Issue #1442)

## Problem Statement

The user requested a level editor similar to Hotline Miami 2's built-in editor. Key requirements:
1. Create custom levels within the game
2. Export levels so they can be shared with other players
3. Import and play shared levels

## Research: Hotline Miami 2 Level Editor

### Architecture
- **Tile-based grid system**: 16x16 pixel tiles, walls span 2 tiles (32px)
- **Tab-organized tools**: Build, Items, Enemy, Misc, Level tabs
- **Capsule tool**: Click-and-drag to create rooms with walls and floor simultaneously
- **Multi-floor support**: Levels can have multiple floors connected via transitions

### Placeable Elements
- Walls (standard, glass, invisible, barriers)
- Enemies (multiple factions, configurable weapons, patrol behavior)
- Furniture/objects (searchable decorative items)
- Player spawn point
- Doors (locked, cutscene-triggered)
- Environmental effects (rain, darkness, backgrounds)

### Sharing System
- Steam Workshop as primary sharing mechanism (12,990+ levels, 3,555+ campaigns)
- Manual file sharing: `.hlm`, `.obj`, `.tls`, `.wll` files in a folder
- Recipients place folders in game's Levels directory

## Solution Design

### Architecture Decision: JSON-based Level Format

Chose JSON over Godot's native `.tscn` format because:
1. **Human-readable**: Easy to inspect, debug, and manually edit
2. **Portable**: Works outside Godot engine, can be shared via text (clipboard, chat, email)
3. **Version-safe**: Format versioning allows forward compatibility
4. **Lightweight**: No binary dependencies, simple parsing

### Components

| Component | File | Purpose |
|-----------|------|---------|
| `LevelData` | `scripts/editor/level_data.gd` | Data model with JSON serialization |
| `LevelEditor` | `scripts/editor/level_editor.gd` | Grid-based editor UI |
| `LevelEditorManager` | `scripts/editor/level_editor_manager.gd` | Save/load/export/import autoload |
| `CustomLevel` | `scripts/editor/custom_level.gd` | Builds playable level from data |
| `LevelEditor.tscn` | `scenes/editor/LevelEditor.tscn` | Editor scene |
| `CustomLevel.tscn` | `scenes/editor/CustomLevel.tscn` | Custom level scene |

### Level Data Format (v1, deprecated — auto-migrated to v2)

```json
{
  "format_version": 1,
  "level_name": "My Level",
  "author": "Player",
  "description": "A custom level",
  "map_width": 2400,
  "map_height": 2000,
  "player_spawn": {"x": 200, "y": 200},
  "floor_color": {"r": 0.25, "g": 0.25, "b": 0.28, "a": 1.0},
  "wall_color": {"r": 0.35, "g": 0.35, "b": 0.4, "a": 1.0},
  "walls": [
    {"x": 100, "y": 200, "w": 300, "h": 32}
  ],
  "enemies": [
    {"x": 400, "y": 500, "weapon": "m16", "patrol": true}
  ],
  "cover_objects": [
    {"x": 300, "y": 400, "w": 64, "h": 64, "type": "crate"}
  ]
}
```

### Editor Tools

1. **Wall Tool [1]**: Click-and-drag to create rectangular walls (like HM2's capsule tool)
2. **Enemy Tool [2]**: Click to place enemies with configurable weapon and patrol behavior
3. **Cover Tool [3]**: Click to place cover objects (desk, crate, barrel, table)
4. **Player Spawn Tool [4]**: Click to set player start position
5. **Eraser Tool [5]**: Click to remove elements
6. **Select Tool [6]**: Reserved for future selection/move functionality

### Sharing Workflow

1. **Create**: Build level in editor using grid-based tools
2. **Save**: Level saved as JSON to `user://custom_levels/`
3. **Export**: Click "Export (Copy)" to copy JSON to clipboard
4. **Share**: Paste JSON in chat/email/forum
5. **Import**: Recipient copies JSON, clicks "Import (Paste)" in editor
6. **Play**: Click "Play Level" to test the imported level

## Alternatives Considered

### PackedScene Export
- Pro: Native Godot format, full scene tree support
- Con: Binary format not human-readable, harder to share via text, potential security issues loading arbitrary scenes

### TileMap-based Editor
- Pro: Better visual fidelity, built-in tile painting
- Con: More complex implementation, harder to serialize/share, requires tileset assets

### Custom Binary Format
- Pro: Smaller file size, faster parsing
- Con: Not human-readable, harder to debug, version migration is complex

## Bug Report: Canvas Placement Not Working (2026-03-24)

### Problem
User reported objects could not be added to the editor canvas (PR #1443 comment).
Game log: `docs/case-studies/issue-1442/logs/game_log_20260324_181447.txt`

### Root Cause Analysis
The level editor used `_unhandled_input()` for mouse event handling. In Godot 4's
input processing pipeline, `_unhandled_input()` only receives events not consumed by
earlier stages (`_input()`, GUI input). Multiple autoload singletons (GameManager,
ReplaySystem) use `_input()` which runs before `_unhandled_input()`. While these
autoloads only handle keyboard events, the input processing order combined with
CanvasLayer UI controls created conditions where mouse click events were not reliably
delivered to `_unhandled_input()`.

This is a known pattern in this codebase — Issue #568 had the same root cause and
was fixed by switching from `_unhandled_input()` to `_input()` with
`set_input_as_handled()`.

### Additional Issues Found
1. **Weapon type mismatch**: Editor stored weapons as strings ("m16", "shotgun") but
   the enemy.gd uses `WeaponType` enum integers (0=RIFLE, 1=SHOTGUN, etc.)
2. **Limited enemy types**: Only 5 of 17 spawnable enemy types were available
3. **No visual feedback**: No cursor preview showing what would be placed
4. **No context menu**: No way to edit placed objects without deleting and re-placing

### Fix (v2)
1. Switched from `_unhandled_input()` to `_input()` with `set_input_as_handled()`
2. Added cursor preview showing selected object under mouse
3. Added right-click context menu for editing/deleting placed objects
4. Added all 17 enemy types from experimental spawner (9 weapons + special flags)
5. Migrated to integer weapon_type format (v2) with v1 backward compatibility
6. Added undo support (Ctrl+Z) and "Clear All" button
7. Fixed custom_level.gd to use integer weapon_type and apply all special enemy flags

### Level Data Format (v2)

```json
{
  "format_version": 2,
  "level_name": "My Level",
  "author": "Player",
  "map_width": 2400,
  "map_height": 2000,
  "player_spawn": {"x": 200, "y": 200},
  "enemies": [
    {"x": 400, "y": 500, "weapon_type": 0, "behavior": 1,
     "is_teleporter": false, "has_force_field": false}
  ]
}
```

Weapon types: 0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE, 4=RPG, 5=PM,
6=MACHINE_GUN, 7=SNIPER_RIFLE, 8=REVOLVER

## Testing

- 40+ unit tests covering LevelData serialization, grid snapping, roundtrip integrity
- Tests for v1→v2 migration of weapon string names to integer weapon_type
- Tests for undo functionality
- Tests for enemy special flags (teleporter, force field, etc.)
- Tests for edge cases: empty levels, invalid JSON, missing format version
- Tests for all element types: walls, enemies, cover objects, player spawn

## Integration Points

- Accessible from pause menu via "Level Editor" button
- Uses existing SceneLoader for scene transitions
- Uses existing PauseMenu in custom levels
- Enemies use existing Enemy.tscn scene (+ EnemySwatShield.tscn, EnemyDroneOperator.tscn)
- Player uses existing Player.tscn scene
- Navigation mesh auto-generated for pathfinding
- Enemy weapon_type mapping matches enemy.gd WeaponType enum
- Enemy special flags match experimental_menu.gd spawner configuration
