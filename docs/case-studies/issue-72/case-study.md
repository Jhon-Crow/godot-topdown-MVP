# Case Study: Issue #72 - Fix Bullets Visual Artifact

## Issue Summary

**Title:** fix пули (fix bullets)
**Original Description (Russian):** когда выпускается одна пуля она выглядит как очередь (троиться в полёте). должно выглядеть как одна пуля (или реалистичный трассер).
**Translation:** When one bullet is fired, it looks like a burst (tripled in flight). It should look like one bullet (or a realistic tracer).

**Repository:** https://github.com/Jhon-Crow/godot-topdown-MVP
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/72

## Timeline of Events

1. **Issue Reported:** User observed visual artifact where a single bullet appears as multiple copies ("tripled") during flight
2. **Expected Behavior:** Single bullet should appear as one projectile or a realistic tracer effect
3. **Investigation Started:** Code analysis and online research conducted

## Technical Analysis

### Current Bullet Implementation

**File:** `scripts/projectiles/bullet.gd`

```gdscript
@export var speed: float = 2500.0  # Very fast: 2500 pixels/second
@export var lifetime: float = 3.0

func _physics_process(delta: float) -> void:
    position += direction * speed * delta
```

**File:** `scenes/projectiles/Bullet.tscn`

- Type: Area2D
- Sprite: PlaceholderTexture2D (8x8 pixels)
- Color: Yellow (modulate = Color(1, 0.9, 0.2, 1))
- Collision: CircleShape2D with radius 4.0

### Project Settings Analysis

**File:** `project.godot`

```ini
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[rendering]
renderer/rendering_method="gl_compatibility"
textures/canvas_textures/default_texture_filter=0  # Nearest filtering
```

### Root Cause Analysis

Based on investigation, the "tripling" effect is likely caused by one or more of the following factors:

#### 1. Monitor/Hardware Ghosting
- The bullet moves at 2500 pixels/second
- At 60 FPS, this is ~41 pixels per frame
- Fast-moving small objects can cause persistence of vision effects
- Monitor response time can create trailing images

#### 2. Frame Timing Issues
- Bullet uses `_physics_process()` for movement
- Physics tick rate may differ from render rate
- Without physics interpolation, discrete position jumps are visible

#### 3. Sprite Size vs Speed Ratio
- 8x8 pixel sprite moving 41+ pixels per frame
- The object "teleports" rather than smoothly transitions
- Human eye perceives multiple positions as separate objects

## Research Findings

### Godot Community Sources

1. **[Godot 4 2D movement causing ghost jitter blur [FIX]](https://forum.godotengine.org/t/godot-4-2d-movement-causing-ghost-jitter-blur-fix/62706)**
   - Solution: Change Camera2D process_callback from "Idle" to "Physics"
   - Ensures camera movement syncs with physics updates

2. **[Sprite blurry/is ghosting while running in Godot 4](https://forum.godotengine.org/t/sprite-blurry-is-ghosting-while-running-in-godot-4/44702)**
   - Check Default Texture Filter is set to Nearest
   - Review import settings for sprites

3. **[Ghosting effect with pixel-art in bigger resolutions (Issue #44098)](https://github.com/godotengine/godot/issues/44098)**
   - Pixel sprites ghost at non-native resolutions
   - Affects games with resolution scaling

4. **[2D Sprites get quite blurry and leave trails (Issue #75842)](https://github.com/godotengine/godot/issues/75842)**
   - Often caused by "unhealthy mix of stretch mode + low res texture + physics tick rate"
   - Monitor ghosting is hardware-related, not fixable by engine

### Known Godot Issues

- Physics interpolation can cause visual artifacts on fast-moving objects
- GL Compatibility renderer may have different behavior than Forward+
- Stretch mode "canvas_items" can affect visual quality

## Proposed Solutions

### Solution A: Visual Trail Effect (Tracer Style)

Instead of fighting the ghosting, embrace it by adding an intentional tracer/trail effect:

**Pros:**
- Aligns with issue description's alternative ("or realistic tracer")
- Makes fast bullets more visible and satisfying
- Common in many shooters

**Cons:**
- Changes visual style
- Requires new implementation

### Solution B: Physics Interpolation

Enable physics interpolation for smoother rendering:

**Pros:**
- Engine-level solution
- Reduces position "jumping"

**Cons:**
- May have side effects on other objects
- Requires Godot 4.3+ for full support

### Solution C: Increase Sprite Size with Trail Texture

Replace the small placeholder with a larger elongated sprite:

**Pros:**
- Simple change
- Makes bullet more visible
- Reduces perceived ghosting

**Cons:**
- Changes visual appearance

### Solution D: Reduce Bullet Speed

Lower the speed from 2500 to a more reasonable value:

**Pros:**
- Reduces the distance traveled per frame
- Makes ghosting less noticeable

**Cons:**
- Changes gameplay feel
- May make combat less snappy

## Recommended Approach

**Primary Recommendation: Solution A + C Combined**

1. Create a proper bullet sprite with a tracer-style elongated shape
2. Add a Line2D or Trail2D component for visual trail effect
3. Keep the fast speed for snappy gameplay
4. Embrace the visual style common in tactical shooters

This approach:
- Addresses the user's request for "realistic tracer" appearance
- Works with the existing high-speed mechanics
- Is commonly used in similar games
- Doesn't require engine-level changes

## Files to Modify

1. `scenes/projectiles/Bullet.tscn` - Update sprite and add trail
2. `scripts/projectiles/bullet.gd` - Potentially add trail management code
3. Assets folder - Add tracer sprite if needed

## Implemented Solution

### Changes Made

#### 1. `scenes/projectiles/Bullet.tscn`

- Changed bullet sprite from 8x8 to 16x4 pixels (elongated tracer shape)
- Added Line2D "Trail" node with:
  - Width: 3.0 pixels
  - Width curve: tapers from full width at front to 0 at back
  - Gradient: fades from solid yellow (1, 0.9, 0.2, 1) to transparent
  - Round end caps for smoother appearance

#### 2. `scripts/projectiles/bullet.gd`

- Added `trail_length` export variable (default: 8 points)
- Added `_trail` reference variable for Line2D node
- Added `_position_history` array to track bullet positions
- Added `_update_rotation()` function to orient bullet in travel direction
- Added `_update_trail()` function to manage trail points
- Trail uses `top_level = true` for global coordinates

#### 3. `tests/integration/test_bullet.gd`

- Added tests for trail length defaults and configuration
- Added tests for position history initialization
- Added tests for bullet rotation in all cardinal and diagonal directions

### Technical Details

The solution implements a realistic tracer effect by:

1. **Elongated Sprite**: The 16x4 pixel shape resembles a bullet/tracer more than the original 8x8 square

2. **Position History Trail**: Instead of fighting ghosting artifacts, we embrace the trail concept with a Line2D that:
   - Records the last 8 positions
   - Renders as a fading gradient from opaque to transparent
   - Uses a width curve that tapers the trail

3. **Proper Rotation**: The bullet rotates to match its travel direction, making the elongated sprite point the right way

4. **Global Coordinates**: The trail uses `top_level = true` so it renders in world space, not relative to the moving bullet

## User Feedback (2026-01-20)

User reported that after testing the built exe, "ничего не изменилось" (nothing changed). The tripling effect persisted despite the tracer visual changes.

### Second Investigation

After reviewing the user's feedback and conducting additional research, a critical root cause was identified:

**Camera2D process_callback was set to default (Idle) instead of Physics**

This issue is well-documented in the Godot community:
- [Godot 4 2D movement causing ghost jitter blur [FIX]](https://forum.godotengine.org/t/godot-4-2d-movement-causing-ghost-jitter-blur-fix/62706)

When the camera updates in Idle mode while the game objects move in physics mode, there's a desynchronization that causes:
- Visual artifacts on fast-moving objects
- Ghosting/tripling appearance
- Objects appearing at multiple positions simultaneously

### Additional Fix Applied

#### `scenes/characters/Player.tscn` and `scenes/characters/csharp/Player.tscn`

Added `process_callback = 0` to Camera2D node:

```ini
[node name="Camera2D" type="Camera2D" parent="."]
process_callback = 0  # 0 = Physics mode (was default Idle)
limit_left = 0
...
```

This ensures the camera updates synchronize with physics updates, eliminating the visual desync that caused the tripling effect.

### Combined Solution

The complete fix consists of:

1. **Camera2D process_callback = Physics** (Root cause fix)
   - Syncs camera with physics updates
   - Eliminates ghosting from timing desynchronization

2. **Tracer visual effect** (Enhanced appearance)
   - 16x4 elongated bullet sprite
   - Line2D trail with gradient fade
   - Rotation to match travel direction

## Third Investigation (2026-01-20 17:05)

User feedback: "у врагов правильные трассеры, у игрока всё те же старые пули" (enemies have correct tracers, player still has the old bullets).

### Root Cause

The project has **two separate bullet implementations**:

1. **GDScript** (`scenes/projectiles/Bullet.tscn` + `scripts/projectiles/bullet.gd`)
   - Used by: `enemy.gd`, `player.gd`
   - Status: Updated with tracer effect ✓

2. **C#** (`scenes/projectiles/csharp/Bullet.tscn` + `Scripts/Projectiles/Bullet.cs`)
   - Used by: `AssaultRifle.cs` → loaded by C# player
   - Status: **NOT updated** (was still using 8x8 sprite, no trail, speed 600 instead of 2500)

The user was testing with the **C# version** of the game (which uses `csharp/Player.tscn` and `csharp/Bullet.tscn`), while the tracer fixes were only applied to the GDScript version.

### Fix Applied

#### `scenes/projectiles/csharp/Bullet.tscn`

Updated to match GDScript version:
- Changed sprite from 8x8 to 16x4 pixels
- Added Line2D "Trail" node with gradient and width curve
- Kept same collision (CircleShape2D radius 4.0)

#### `Scripts/Projectiles/Bullet.cs`

Added trail functionality:
- `TrailLength` export property (default: 8)
- `_trail` reference to Line2D node
- `_positionHistory` list for tracking positions
- `UpdateRotation()` method to orient bullet in travel direction
- `UpdateTrail()` method to manage Line2D points
- Trail uses `TopLevel = true` for global coordinates
- Updated default speed from 600 to 2500 (matching GDScript)

### Key Lesson

**When a project has both GDScript and C# implementations, ALL parallel implementations must be updated.**

The project structure mirrors GDScript scenes in `/csharp/` subdirectories:
- `scenes/characters/Player.tscn` ↔ `scenes/characters/csharp/Player.tscn`
- `scenes/projectiles/Bullet.tscn` ↔ `scenes/projectiles/csharp/Bullet.tscn`
- `scripts/projectiles/bullet.gd` ↔ `Scripts/Projectiles/Bullet.cs`

Future changes must update both implementations to maintain parity.

## References

- https://forum.godotengine.org/t/godot-4-2d-movement-causing-ghost-jitter-blur-fix/62706
- https://forum.godotengine.org/t/sprite-blurry-is-ghosting-while-running-in-godot-4/44702
- https://github.com/godotengine/godot/issues/44098
- https://github.com/godotengine/godot/issues/75842
- https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html
