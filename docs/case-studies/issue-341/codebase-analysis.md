# Codebase Analysis: Shell Casing System

## Overview

This document provides a comprehensive analysis of the existing shell casing implementation in the godot-topdown-MVP project. The analysis was conducted on 2026-01-25 to understand the current state and identify what needs to be added to make shell casings interactive.

## Current Implementation

### 1. Shell Casing Core Files

#### `scripts/effects/casing.gd`
**Type:** RigidBody2D-based physics object
**Purpose:** Represents ejected bullet casings from weapons
**Key Features:**
- Physics-based movement with gravity disabled (top-down view)
- Auto-landing after 2 seconds via `AUTO_LAND_TIME` constant
- Collision detection with static bodies/walls triggers landing
- Time freeze support for slow-motion effects
- Caliber-aware appearance system
- Lifetime management with optional auto-destruction

**Key Properties:**
```gdscript
collision_layer = 0
collision_mask = 4  # Collides with walls/obstacles
gravity_scale = 0.0  # Top-down view
linear_damp = 3.0
angular_damp = 5.0
```

**Key Methods:**
- `freeze_time()` - Stores velocities and sets them to zero
- `unfreeze_time()` - Restores stored velocities
- `land()` - Stops all movement and disables physics
- `set_caliber_data()` - Sets appearance based on caliber type

#### `scenes/effects/Casing.tscn`
**Node Structure:**
```
Casing (RigidBody2D)
├── CollisionShape2D (RectangleShape2D 4x14)
└── Sprite2D (default: casing_rifle.png)
```

### 2. Shell Casing Spawning

#### Enemy Spawning (`scripts/objects/enemy.gd:4013-4051`)
```gdscript
func _spawn_casing(shoot_direction: Vector2, weapon_forward: Vector2):
    var casing = CASING_SCENE.instantiate()
    var spawn_pos = global_position + weapon_forward * (bullet_spawn_offset * 0.5)

    # Ejection perpendicular to weapon (90° counter-clockwise)
    var eject_dir = Vector2(-weapon_forward.y, weapon_forward.x)
    var random_angle = randf_range(-0.3, 0.3)
    eject_dir = eject_dir.rotated(random_angle)

    # Speed and rotation
    var eject_speed = randf_range(300, 450)
    casing.linear_velocity = eject_dir * eject_speed
    casing.angular_velocity = randf_range(-15, 15)

    get_tree().current_scene.add_child(casing)
```

**Key Parameters:**
- Spawn position: Near weapon barrel
- Ejection direction: Perpendicular to weapon with ±17° variation
- Ejection speed: 300-450 pixels/sec
- Initial spin: ±15 rad/s
- Caliber: 5.45x39mm for rifles

#### Player Shooting (`scripts/characters/player.gd:600-630`)
Players do not spawn visual casings, only play shell casing sounds with 0.15s delay for realism.

### 3. Sound Effects System

#### Audio Manager (`scripts/autoload/audio_manager.gd:63-66`)
**Casing Sound Constants:**
```gdscript
SHELL_RIFLE = "res://assets/audio/падает гильза автомата.wav"
SHELL_PISTOL = "res://assets/audio/падает гильза пистолета.wav"
SHELL_SHOTGUN = "res://assets/audio/падение гильзы дробовик.mp3"
VOLUME_SHELL = -10.0  # dB
```

**Sound Playback Methods:**
- `play_shell_rifle(position: Vector2)`
- `play_shell_pistol(position: Vector2)`
- `play_shell_shotgun(position: Vector2)`

All use AudioStreamPlayer2D for positional audio.

**Delayed Sound Timing:**
- 0.15 second delay after shot for realism
- Simulates time for casing to eject and land

### 4. Physics Behavior

#### Current Physics Process (`casing.gd:45-70`)
```gdscript
func _physics_process(delta: float) -> void:
    if is_time_frozen:
        linear_velocity = Vector2.ZERO
        angular_velocity = 0.0
        return

    if lifetime_limit > 0:
        lifetime_timer += delta
        if lifetime_timer >= lifetime_limit:
            queue_free()

    if not is_landed:
        auto_land_timer += delta
        if auto_land_timer >= AUTO_LAND_TIME:
            land()
```

#### Collision Detection (`casing.gd:90-105`)
```gdscript
func _on_body_entered(body: Node) -> void:
    if body is StaticBody2D or body is TileMap:
        land()
```

**Current Behavior:**
- Casings land when hitting walls/static objects
- Auto-land after 2 seconds regardless of collisions
- No interaction with CharacterBody2D (players/enemies)

### 5. Time Freeze Integration

#### LastChanceEffectsManager (`scripts/autoload/last_chance_effects_manager.gd`)

**Casing Freezing (Lines 883-901):**
```gdscript
func _freeze_casing(casing: RigidBody2D):
    var original_mode = casing.process_mode
    _original_modes.push_back({
        "object": casing,
        "mode": original_mode
    })
    casing.process_mode = Node.PROCESS_MODE_DISABLED
    if casing.has_method("freeze_time"):
        casing.freeze_time()
    _frozen_casings.push_back(casing)
```

**Auto-Freeze During Time Freeze (Lines 978-981):**
Detects casings created during freeze and automatically freezes them immediately.

### 6. Caliber Data System

#### CaliberData Resource (`scripts/data/caliber_data.gd:106-108`)
```gdscript
@export var casing_sprite: Texture2D = null
```

Allows caliber-specific casing appearances with fallback color system:
- Rifles (5.45x39mm): Brass color
- Pistols (9x19mm): Silver color
- Shotguns (buckshot): Red color

**Available Caliber Resources:**
- `resources/calibers/caliber_545x39.tres`
- `resources/calibers/caliber_9x19.tres`
- `resources/calibers/caliber_buckshot.tres`

### 7. Character Movement System

#### Player Movement (`scripts/characters/player.gd`)
**Type:** CharacterBody2D
**Physics Method:** `move_and_slide()` at line 319
**Max Speed:** ~300 px/s (configurable)

**Key Properties:**
- Acceleration-based movement with friction
- No direct interaction with RigidBody2D objects by default
- Uses collision layers for wall/obstacle detection

#### Enemy Movement (`scripts/objects/enemy.gd`)
**Type:** CharacterBody2D
**Physics Method:** `move_and_slide()` at line 1000
**Speeds:**
- Normal: 220 px/s
- Combat: 320 px/s

**Key Properties:**
- State machine-based AI
- Pathfinding with NavigationAgent2D
- No direct interaction with RigidBody2D objects

### 8. Existing Interactive Object Patterns

#### Area2D-Based Objects
These objects use Area2D for trigger-based interactions:

1. **ThreatSphere** (`scripts/components/threat_sphere.gd`)
   - Detects enemies entering range
   - Uses `body_entered` and `body_exited` signals

2. **HitArea** (`scripts/objects/hit_area.gd`)
   - Detects bullet impacts
   - Uses collision layers for filtering

3. **Target** (`scripts/objects/target.gd`)
   - Destructible target practice object
   - Responds to bullet hits

4. **PenetrationHole** (`scripts/effects/penetration_hole.gd`)
   - Visual effect for wall penetration
   - Area2D for collision detection

#### RigidBody2D-Based Objects
These objects use RigidBody2D for physics simulation:

1. **Casing** (current implementation)
   - Simple physics with auto-landing
   - No character interaction

2. **Grenades** (`scripts/effects/frag_grenade.gd`, `scripts/effects/grenade_base.gd`)
   - Physics-based projectiles
   - Collision detection for detonation

3. **Shrapnel** (`scripts/effects/shrapnel.gd`)
   - Particle-like physics
   - Damage on contact

## Current Limitations

### 1. No Character-Casing Interaction
**Issue:** Casings use `collision_mask = 4` (walls only)
**Impact:** Players and enemies (CharacterBody2D) pass through casings without any physics interaction

**Current Collision Layers:**
- Layer 0: None (casings don't exist in any layer)
- Layer 4: Walls/obstacles (casings detect these)

**Missing:** Detection of CharacterBody2D on appropriate layers

### 2. No Push/Bounce Physics
**Issue:** Even if collisions were detected, CharacterBody2D doesn't push RigidBody2D by default
**Impact:** No realistic bouncing or pushing of casings when walked over

**Required:** Manual impulse application from CharacterBody2D to RigidBody2D on collision

### 3. No Bounce Sound Triggers
**Issue:** Casings only play sound via delayed timer after ejection
**Impact:** No sound when casings bounce off surfaces or are kicked by characters

**Required:** Collision-based sound playback system

### 4. Limited Collision Detection
**Issue:** `_on_body_entered()` only checks for StaticBody2D and TileMap
**Impact:** Cannot detect CharacterBody2D collisions

**Required:** Expand collision detection to include CharacterBody2D nodes

## Gap Analysis

### Missing Components for Interactive Casings

1. **Collision Layer Configuration**
   - Need to add casings to a collision layer (e.g., layer 5 for "items")
   - Need to set collision mask to detect both walls and characters

2. **CharacterBody2D Push Detection**
   - Players and enemies need to detect when they collide with casings
   - Need to apply impulses to push casings realistically

3. **Bounce Sound System**
   - Area2D or collision callback to detect impacts
   - Velocity-based sound triggering (only play if moving fast enough)
   - Cooldown system to prevent sound spam

4. **Physics Parameters**
   - Bounce coefficient (restitution) for realistic bouncing
   - Friction values for sliding behavior
   - Mass values for push resistance

### Required Changes Summary

| Component | Current State | Required State |
|-----------|---------------|----------------|
| Casing collision_layer | 0 (none) | 5 (items layer) |
| Casing collision_mask | 4 (walls only) | 4 + 1 (walls + characters) |
| CharacterBody2D push | Not implemented | Detect casings, apply impulse |
| Bounce sound | Only on spawn | On collision with velocity check |
| Physics material | Default | Custom with bounce/friction |

## Architecture Recommendations

### 1. Minimal Changes Approach
- Add Area2D child to Casing for body_entered detection
- Keep RigidBody2D for physics simulation
- Use signals to trigger sounds on collision

### 2. Character Push Implementation
- Iterate through `move_and_slide()` collisions in player/enemy
- Check if collider is a Casing
- Apply central impulse based on movement velocity

### 3. Sound System Enhancement
- Add collision velocity threshold (e.g., 50 px/s minimum)
- Implement sound cooldown timer (e.g., 0.1s between sounds)
- Choose sound based on impact velocity (soft vs hard bounce)

## References to Similar Implementations

### Grenade Physics Pattern
The grenade system (`scripts/effects/grenade_base.gd`) shows a similar pattern:
- RigidBody2D for physics
- Collision detection for triggering effects
- Can be adapted for casing bounce detection

### Shrapnel Physics Pattern
The shrapnel system (`scripts/effects/shrapnel.gd`) demonstrates:
- High-speed RigidBody2D particles
- Collision-based lifetime management
- Could inform velocity-based sound triggering

## Conclusion

The current casing implementation provides a solid physics foundation but lacks character interaction and collision-based sound effects. The required changes are well-scoped and can be implemented by:

1. Adjusting collision layers and masks
2. Adding Area2D for collision detection
3. Implementing push physics in CharacterBody2D movement
4. Adding collision-based sound playback with velocity checks

All required components exist in the codebase as examples (grenades, shrapnel, area triggers), making implementation straightforward.

---

*Analysis completed: 2026-01-25*
*Analyzed by: AI Issue Solver*
