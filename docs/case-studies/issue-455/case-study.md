# Case Study: Issue #455 - Muzzle Flash and Light Reflection

## Timeline of Events

### Initial Issue (2026-02-03)
- **Issue opened**: Request for muzzle flash effect on player and enemy weapons with wall reflections
- **Original requirements**:
  1. Muzzle flash (small flame at barrel) when shooting
  2. Light reflection on walls (less visible with distance)

### First Implementation Attempt
- Created `MuzzleFlash.tscn` scene with:
  - GPUParticles2D for flame particles
  - PointLight2D for dynamic wall lighting
- Integrated with `ImpactEffectsManager`
- Added calls in GDScript player (`scripts/characters/player.gd`) and enemy (`scripts/objects/enemy.gd`)

### User Feedback (2026-02-03 23:32)
User reported issues:
1. **Flash added to enemies but NOT player** - works for enemies, but not for player
2. **Barrel flash too large** - should be 4x smaller, more like directed sparks
3. **Weapon flash too small** - should be 2x bigger with 3x larger residual glow
4. **Missing shadows** - need shadows from flashes on enemies and player

### Root Cause Analysis

#### Issue 1: Player Missing Muzzle Flash
**Root Cause**: The codebase has **dual implementation** for player - both C# and GDScript.
- `scripts/characters/player.gd` - GDScript implementation (muzzle flash WAS added here)
- `Scripts/Characters/Player.cs` - C# implementation (**muzzle flash NOT added**)

The actual game uses the **C# Player.cs**, while the first implementation only added muzzle flash to the GDScript version.

Evidence from logs:
- Log shows `[INFO] [Player.Grenade] Grenade scene loaded from GrenadeManager: Flashbang`
- The GDScript player.gd uses `ImpactEffects.spawn_muzzle_flash()` at line 629
- C# Player.cs uses `BaseWeapon.SpawnBullet()` which did NOT call muzzle flash

**Fix**: Added muzzle flash call to `Scripts/AbstractClasses/BaseWeapon.cs` in the `SpawnBullet()` method:
```csharp
// Spawn muzzle flash effect at the bullet spawn position
SpawnMuzzleFlash(spawnPosition, direction);
```

#### Issue 2: Barrel Flash Too Large
**Root Cause**: Particle settings were too generous:
- Original: 10 particles, 0.4-1.0 scale, 25° spread
- Too much like a fireball, not like sparks

**Fix**: Modified `MuzzleFlash.tscn` particle settings:
- Reduced particles: 10 → 6
- Reduced scale: 0.4-1.0 → 0.1-0.25 (4x smaller)
- Reduced spread: 25° → 12° (more directed)
- Increased velocity: 80-150 → 150-280 (faster, more spark-like)
- Reduced texture size: 16x16 → 8x8
- Shortened lifetime: 0.12s → 0.08s

#### Issue 3: Weapon Flash Too Small / Residual Glow
**Root Cause**: Light texture and energy were conservative:
- Original: 128x128 texture, scale 1.5, energy 1.5, duration 0.1s

**Fix**:
- Increased light texture: 128x128 → 256x256
- Increased texture_scale: 1.5 → 3.0 (2x larger)
- Increased light energy: 1.5 → 4.5 (3x larger)
- Increased flash duration: 0.1s → 0.3s (3x longer for residual glow)

#### Issue 4: Missing Shadows
**Root Cause**: PointLight2D shadow was not enabled.

**Fix**: Added shadow properties to PointLight2D in `MuzzleFlash.tscn`:
```
shadow_enabled = true
shadow_color = Color(0, 0, 0, 0.6)
```

## Game Logs Analysis

### Log 1: game_log_20260203_232835.txt (712KB)
- Game startup and initialization
- All 10 enemies initialized with death animation components
- Player initialized with Rifle weapon pose
- Shows sound propagation system working
- **No muzzle flash logs** - confirms the effect wasn't being called for player

### Log 2: game_log_20260203_233151.txt (300KB)
- Similar game startup
- Player shooting at 23:31:52 - `[SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1199.667), source=PLAYER (AssaultRifle)`
- **No muzzle flash logs** - confirms player's C# implementation bypassed GDScript muzzle flash code

## Technical Details

### Codebase Structure (Dual Language Implementation)
```
/scripts/            (GDScript)
├── characters/
│   └── player.gd   (GDScript player - has muzzle flash)
├── objects/
│   └── enemy.gd    (GDScript enemy - has muzzle flash)
└── autoload/
    └── impact_effects_manager.gd

/Scripts/            (C#)
├── Characters/
│   └── Player.cs   (C# player - was MISSING muzzle flash)
├── AbstractClasses/
│   └── BaseWeapon.cs  (C# weapon base - NOW has muzzle flash)
└── Weapons/
    └── AssaultRifle.cs
```

The game uses C# for the player and GDScript for enemies, which explains why enemies had muzzle flash but player didn't.

### Effect Parameter Comparison

| Parameter | Original | After Fix | Change |
|-----------|----------|-----------|--------|
| Particle amount | 10 | 6 | -40% |
| Particle scale | 0.4-1.0 | 0.1-0.25 | 4x smaller |
| Particle spread | 25° | 12° | More focused |
| Particle velocity | 80-150 | 150-280 | 2x faster |
| Particle lifetime | 0.12s | 0.08s | Shorter |
| Light texture | 128x128 | 256x256 | 2x larger |
| Light scale | 1.5 | 3.0 | 2x larger |
| Light energy | 1.5 | 4.5 | 3x brighter |
| Flash duration | 0.1s | 0.3s | 3x longer |
| Shadow | disabled | enabled | New feature |

## Files Modified

1. **Scripts/AbstractClasses/BaseWeapon.cs**
   - Added `SpawnMuzzleFlash()` method
   - Added muzzle flash call in `SpawnBullet()`

2. **scenes/effects/MuzzleFlash.tscn**
   - Reduced particle size and count (spark-like effect)
   - Increased light texture size (2x)
   - Enabled shadows

3. **scripts/effects/muzzle_flash.gd**
   - Increased `FLASH_DURATION` to 0.3s (3x)
   - Increased `LIGHT_START_ENERGY` to 4.5 (3x)

## Iteration 3: Light Falloff and Position Refinements (2026-02-03)

### User Feedback (Comment #3843752470)
User reported additional issues:
1. **Brightness zone too large** - Maximum brightness area should be 2x smaller, fade zone should cover entire viewport
2. **Flash passes through walls** - Flash light shouldn't penetrate walls or go behind the shooter
3. **Player muzzle flash position wrong** - Fire appears inside weapon body, not at barrel end
4. **Muzzle fire too long** - Barrel flame particle effect should be shorter

### Root Cause Analysis

#### Issue 1: Light Falloff Zone Too Small
**Root Cause**: Light gradient had limited range:
- Original gradient: 3 stops (0, 0.4, 1) with max brightness extending to 40%
- Texture scale 3.0 with 256x256 = 768px coverage radius
- Viewport is typically ~1920x1080, diagonal ~2200px

**Fix**:
- Modified gradient: 5 stops (0, 0.1, 0.2, 0.5, 1) - max brightness only to 10%, then gradual fade
- Increased texture: 256x256 → 512x512
- Increased texture_scale: 3.0 → 4.5 (effective radius ~1152px, covers half viewport)
- This creates a smaller bright center (2x smaller at 10% vs 40%) with viewport-wide fade

#### Issue 2: Light Penetrating Walls
**Root Cause**: Shadow settings needed refinement:
- Shadow was enabled but filter/smoothing settings were default
- Shadow color at 0.6 alpha wasn't dark enough

**Fix**:
- Enhanced shadow_color: alpha 0.6 → 0.8 (darker shadows)
- Added shadow_filter = 1 (PCF5 filtering for smoother shadows)
- Added shadow_filter_smooth = 4.0 (softened shadow edges)

#### Issue 3: Player Muzzle Flash Position Wrong
**Root Cause**: `BulletSpawnOffset` in weapon scenes didn't match visual barrel length.

Weapon sprite analysis:
- **AssaultRifle** (m16_rifle_topdown.png): 64x16px, offset=20, barrel end = 20+32 = 52px
  - Original BulletSpawnOffset = 25.0 (27px too short!)
- **MiniUzi** (mini_uzi_topdown.png): 40x10px, offset=15, barrel end = 15+20 = 35px
  - Original BulletSpawnOffset = 20.0 (15px too short!)
- **SilencedPistol** (silenced_pistol_topdown.png): 44x12px, offset=11, barrel end = 11+22 = 33px
  - Original BulletSpawnOffset = 22.0 (11px too short!)
- **Shotgun** (shotgun_topdown.png): 64x16px, offset=20, barrel end = 20+32 = 52px
  - Original BulletSpawnOffset = 25.0 (27px too short!)

**Fix**: Updated all weapon scenes with correct barrel-end offset:
- `AssaultRifle.tscn`: 25.0 → 52.0
- `MiniUzi.tscn`: 20.0 → 35.0
- `SilencedPistol.tscn`: 22.0 → 33.0
- `Shotgun.tscn`: 25.0 → 52.0

#### Issue 4: Barrel Particle Effect Too Long
**Root Cause**: Particle lifetime and count were still too prominent:
- Lifetime was 0.08s (after iteration 2 fix)
- Still slightly visible as a "blob" instead of instant flash

**Fix**:
- Reduced lifetime: 0.08s → 0.04s (instantaneous)
- Reduced amount: 6 → 5
- Increased explosiveness: 0.98 → 1.0 (all particles emit at once)
- Reduced randomness: 0.15 → 0.1

### Effect Parameter Comparison (Final)

| Parameter | Original | Iteration 2 | Iteration 3 | Change |
|-----------|----------|-------------|-------------|--------|
| Particle amount | 10 | 6 | 5 | 50% reduction |
| Particle lifetime | 0.12s | 0.08s | 0.04s | 3x shorter |
| Particle explosiveness | - | 0.98 | 1.0 | All at once |
| Light texture | 128x128 | 256x256 | 512x512 | 4x larger |
| Light scale | 1.5 | 3.0 | 4.5 | 3x larger |
| Light gradient stops | 3 | 3 | 5 | More gradual fade |
| Shadow alpha | 0 | 0.6 | 0.8 | Darker |
| Shadow filter | none | none | PCF5 | Smoother |
| BulletSpawnOffset (rifle) | - | 25.0 | 52.0 | Correct barrel |

### Files Modified (Iteration 3)

1. **scenes/effects/MuzzleFlash.tscn**
   - Light gradient: smaller bright center (10% vs 40%), 5 stops for gradual fade
   - Light texture: 512x512 (larger coverage)
   - Light scale: 4.5 (viewport-wide fade)
   - Shadow: darker (0.8 alpha), PCF5 filter, 4.0 smoothing
   - Particles: shorter lifetime (0.04s), less randomness

2. **scenes/weapons/csharp/AssaultRifle.tscn**
   - BulletSpawnOffset: 25.0 → 52.0

3. **scenes/weapons/csharp/MiniUzi.tscn**
   - BulletSpawnOffset: 20.0 → 35.0

4. **scenes/weapons/csharp/SilencedPistol.tscn**
   - BulletSpawnOffset: 22.0 → 33.0

5. **scenes/weapons/csharp/Shotgun.tscn**
   - BulletSpawnOffset: 25.0 → 52.0

## Lessons Learned

1. **Always verify which language implementation is used** - The codebase has both C# and GDScript versions of the same functionality. Need to check which one is actually being used at runtime.

2. **Log analysis helps identify root cause** - The absence of muzzle flash logs in game logs pointed to the player implementation issue.

3. **Visual effects have multiple components** - Muzzle flash consists of:
   - Barrel particles (small, directed sparks)
   - Light effect (larger, illuminates surroundings)
   - Shadows (adds realism)
   - Residual glow (persistence)

4. **User feedback is essential** - Initial implementation was technically correct but visually wrong. User testing revealed specific adjustments needed.

5. **Sprite offset calculations are critical** - BulletSpawnOffset must account for sprite offset + half sprite width to position effects at the visual barrel end, not just an arbitrary offset from the weapon node center.

6. **Light gradients control visual perception** - A 5-stop gradient with concentrated brightness (0-10%) and long fade (10-100%) creates the perception of a smaller bright center with viewport-wide illumination.

## Iteration 4: Light Occlusion - Flash Passing Through Walls (2026-02-03)

### User Feedback (Comment #3843825427)
User reported:
> "сейчас вспышка проходит сквозь стены" (currently the flash passes through walls)

### Root Cause Analysis

**Root Cause**: The walls in the level scenes were **missing LightOccluder2D nodes**.

In Godot 4, for PointLight2D shadows to work correctly, walls need TWO things:
1. `shadow_enabled = true` on the PointLight2D ✓ (already done in Iteration 3)
2. `LightOccluder2D` nodes on objects that should block light ✗ (was missing!)

The current walls had:
- `StaticBody2D` - for physics
- `ColorRect` - for visual rendering
- `CollisionShape2D` - for collision detection

But they were **missing**:
- `LightOccluder2D` with `OccluderPolygon2D` - for shadow casting

This is why shadows weren't appearing despite `shadow_enabled = true` - there were no occluders for the light to cast shadows against.

### Technical Details

In Godot 4's 2D lighting system:
- `PointLight2D` emits light and can cast shadows when `shadow_enabled = true`
- Shadows require `LightOccluder2D` nodes that define the shadow-casting geometry
- Each occluder needs an `OccluderPolygon2D` resource that defines the shape
- The polygon vertices should match the collision shape for consistency

### Fix Implementation

Added `LightOccluder2D` nodes to all wall and obstacle objects in both level scenes:

**BuildingLevel.tscn** (62 occluders):
- 4 outer walls (WallTop, WallBottom, WallLeft, WallRight)
- 18 interior walls (Room1-5, Corridor, LobbyDivider, StorageRoom, MainHall walls)
- 7 corner fills
- 13 cover objects (desks, tables, cabinets, crates)

**TestTier.tscn** (56 occluders):
- 4 outer walls
- 8 large building obstacles
- 4 medium obstacles
- 12 wide cover objects
- 8 tall cover objects
- 6 barricades
- 7 pillars
- 6 square crates
- 1 spawn cover

### OccluderPolygon2D Resources Added

Created reusable `OccluderPolygon2D` sub-resources matching each collision shape:

| Shape | Dimensions | Polygon |
|-------|------------|---------|
| wall_horizontal | 2464x32 | -1232,-16 to 1232,16 |
| wall_vertical | 32x2064 | -16,-1032 to 16,1032 |
| interior_wall_h | 400x24 | -200,-12 to 200,12 |
| interior_wall_v | 24x400 | -12,-200 to 12,200 |
| cover_desk | 120x48 | -60,-24 to 60,24 |
| cover_table | 80x80 | -40,-40 to 40,40 |
| cover_cabinet | 48x96 | -24,-48 to 24,48 |
| obstacle_large | 160x160 | -80,-80 to 80,80 |
| pillar | 48x48 | -24,-24 to 24,24 |
| barricade | 128x24 | -64,-12 to 64,12 |

### Files Modified (Iteration 4)

1. **scenes/levels/BuildingLevel.tscn**
   - Added 12 OccluderPolygon2D sub-resources
   - Added LightOccluder2D child nodes to all 62 wall/cover objects

2. **scenes/levels/TestTier.tscn**
   - Added 10 OccluderPolygon2D sub-resources
   - Added LightOccluder2D child nodes to all 56 wall/obstacle/cover objects

### Effect Parameter Comparison (Complete History)

| Feature | Iteration 1 | Iteration 2 | Iteration 3 | Iteration 4 |
|---------|-------------|-------------|-------------|-------------|
| Player muzzle flash | GDScript only | C# added | ✓ | ✓ |
| Particle sparks | Large | 4x smaller | Shorter duration | ✓ |
| Light radius | Small | 2x bigger | Viewport-wide | ✓ |
| Residual glow | Short | 3x longer | ✓ | ✓ |
| Shadow enabled | No | Yes | Enhanced (PCF5) | ✓ |
| **LightOccluder2D** | No | No | No | **Yes** |
| Flash blocked by walls | No | No | No | **Yes** |

## Lessons Learned

1. **Always verify which language implementation is used** - The codebase has both C# and GDScript versions of the same functionality. Need to check which one is actually being used at runtime.

2. **Log analysis helps identify root cause** - The absence of muzzle flash logs in game logs pointed to the player implementation issue.

3. **Visual effects have multiple components** - Muzzle flash consists of:
   - Barrel particles (small, directed sparks)
   - Light effect (larger, illuminates surroundings)
   - Shadows (adds realism)
   - Residual glow (persistence)

4. **User feedback is essential** - Initial implementation was technically correct but visually wrong. User testing revealed specific adjustments needed.

5. **Sprite offset calculations are critical** - BulletSpawnOffset must account for sprite offset + half sprite width to position effects at the visual barrel end, not just an arbitrary offset from the weapon node center.

6. **Light gradients control visual perception** - A 5-stop gradient with concentrated brightness (0-10%) and long fade (10-100%) creates the perception of a smaller bright center with viewport-wide illumination.

7. **2D shadows require BOTH light settings AND occluders** - Enabling `shadow_enabled` on PointLight2D is only half the solution. The level geometry needs `LightOccluder2D` nodes with `OccluderPolygon2D` resources that define the shadow-casting shapes. Without occluders, light passes through everything regardless of shadow settings.

## References

- Game logs: `game_log_20260203_232835.txt`, `game_log_20260203_233151.txt`
- Initial research: `research.md`
- Godot PointLight2D shadow documentation
- Godot GPUParticles2D material properties
- Godot LightOccluder2D and OccluderPolygon2D documentation
- Weapon sprite dimensions: m16=64x16, uzi=40x10, pistol=44x12, shotgun=64x16
