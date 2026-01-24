# Codebase Analysis for Issue #332

## Analyzed Files

### 1. scripts/objects/enemy.gd

**Total size**: ~5000 lines (large file)

#### Key FOV-Related Sections

**FOV Configuration (lines 45-55)**:
```gdscript
## Field of view angle in degrees.
## Enemy can only see targets within this cone centered on their facing direction.
## Set to 0 or negative to disable FOV check (360 degree vision).
## Default is 100 degrees as requested in issue #66.
@export var fov_angle: float = 100.0

## Whether FOV checking is enabled for this specific enemy.
## This is combined with the global ExperimentalSettings.fov_enabled setting.
## Both must be true for FOV to be active.
## Note: The global setting in ExperimentalSettings is disabled by default.
@export var fov_enabled: bool = true
```

**Debug Label (lines 122-126)**:
```gdscript
## Enable/disable debug logging.
@export var debug_logging: bool = false

## Enable/disable debug label above enemy showing current AI state.
@export var debug_label_enabled: bool = false
```

**Model Rotation Logic (lines 1021-1054)**:
- Uses `_enemy_model.global_rotation` for actual facing
- Idle scanning uses smooth rotation (`MODEL_ROTATION_SPEED: float = 3.0`)
- Combat/movement uses instant rotation

**Idle Scanning (lines 204-207, 4070-4123)**:
```gdscript
var _idle_scan_timer: float = 0.0  ## IDLE scanning state for GUARD enemies
var _idle_scan_target_index: int = 0
var _idle_scan_targets: Array[float] = []
const IDLE_SCAN_INTERVAL: float = 10.0
```

**Damage Response (lines 4140-4208)**:
- `on_hit()` -> `on_hit_with_info()` -> `on_hit_with_bullet_info()`
- Stores `_last_hit_direction` but only uses it for death animation
- No rotation toward attacker on hit

**FOV Cone Drawing (lines 4825-4841)**:
```gdscript
func _draw_fov_cone(fill_color: Color, edge_color: Color) -> void:
    var half_fov := deg_to_rad(fov_angle / 2.0)
    var cone_length := 400.0
    var left_end := Vector2.from_angle(-half_fov) * cone_length
    var right_end := Vector2.from_angle(half_fov) * cone_length
    var cone_points: PackedVector2Array = [Vector2.ZERO]
    var arc_segments := 16
    for i in range(arc_segments + 1):
        cone_points.append(Vector2.from_angle(-half_fov + (float(i) / arc_segments) * 2 * half_fov) * cone_length)
    draw_colored_polygon(cone_points, fill_color)
    draw_line(Vector2.ZERO, left_end, edge_color, 2.0)
    draw_line(Vector2.ZERO, right_end, edge_color, 2.0)
    for i in range(arc_segments):
        var a1 := -half_fov + (float(i) / arc_segments) * 2 * half_fov
        var a2 := -half_fov + (float(i + 1) / arc_segments) * 2 * half_fov
        draw_line(Vector2.from_angle(a1) * cone_length, Vector2.from_angle(a2) * cone_length, edge_color, 1.5)
```

**BUG**: Uses `Vector2.from_angle()` without accounting for `_enemy_model.global_rotation`

### 2. scripts/components/vision_component.gd

**Lines**: 225

Simple vision component with:
- Detection range
- Detection delay
- Line-of-sight checking via RayCast2D
- Visibility ratio calculation (5-point check)

Not currently used for sector coordination.

### 3. scripts/ai/states/idle_state.gd

**Lines**: 77

Handles PATROL and GUARD modes:
- PATROL: Moves between patrol points
- GUARD: Stays in place, velocity = Vector2.ZERO

Calls into enemy's `_process_patrol()` and `_process_guard()` methods.

### 4. scripts/ai/enemy_memory.gd

**Purpose**: Tracks suspected player position with confidence decay.

Could potentially be extended to track friendly enemy positions for sector coordination.

## Architecture Notes

### Enemy Model Hierarchy
```
CharacterBody2D (enemy.gd)
├── EnemyModel (Node2D) - rotates to face direction
│   ├── Body (Sprite2D)
│   ├── Head (Sprite2D)
│   ├── LeftArm (Sprite2D)
│   ├── RightArm (Sprite2D)
│   └── WeaponMount (Node2D)
│       └── WeaponSprite (Sprite2D)
├── RayCast2D - for line of sight
├── NavigationAgent2D - for pathfinding
├── HitArea (Area2D) - for bullet collision
└── DebugLabel (Label) - AI state display
```

### Key Variables for FOV

| Variable | Type | Location | Purpose |
|----------|------|----------|---------|
| `fov_angle` | float | enemy.gd:49 | FOV cone width in degrees |
| `fov_enabled` | bool | enemy.gd:55 | Per-enemy FOV toggle |
| `_enemy_model` | Node2D | enemy.gd:175 | Model that rotates |
| `_idle_scan_targets` | Array[float] | enemy.gd:206 | Angles to scan in GUARD mode |
| `_last_hit_direction` | Vector2 | enemy.gd:560 | Direction of last hit received |

### AI State Machine

```
IDLE (patrol/guard)
  ↓ (sees player)
COMBAT
  ↓ (under fire)
SEEKING_COVER → IN_COVER
  ↓ (suppressed)
SUPPRESSED
  ↓ (retreating)
RETREATING
  ↓ (pursuing)
PURSUING → ASSAULT
  ↓ (searching)
SEARCHING
```

## Relevant Signals

```gdscript
signal hit  ## Enemy hit
signal died  ## Enemy died
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool)
signal state_changed(new_state: AIState)
```

The `hit` signal could be used to notify other nearby enemies about the attack direction.
