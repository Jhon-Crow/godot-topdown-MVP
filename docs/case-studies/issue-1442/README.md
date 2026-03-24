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

### Level Data Format (v1)

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

## Testing

- 35+ unit tests covering LevelData serialization, grid snapping, roundtrip integrity
- Tests for edge cases: empty levels, invalid JSON, missing format version
- Tests for all element types: walls, enemies, cover objects, player spawn

## Integration Points

- Accessible from pause menu via "Level Editor" button
- Uses existing SceneLoader for scene transitions
- Uses existing PauseMenu in custom levels
- Enemies use existing Enemy.tscn scene
- Player uses existing Player.tscn scene
- Navigation mesh auto-generated for pathfinding
