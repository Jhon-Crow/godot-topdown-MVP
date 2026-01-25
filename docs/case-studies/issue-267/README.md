# Case Study: Issue #267 - Death Animation Debugging

## Issue Summary

**Title**: отладить анимации смерти (Debug death animations)
**Issue URL**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/267
**Status**: In Progress

### Original Requirements (Russian)

1. "тела не должны исчезать (сейчас исчезают)" - Bodies should not disappear (currently disappearing)
2. "добавь на учебную площадку не атакующих врагов" - Add non-attacking enemies to training area
3. "один должен 'падать' в реальном времени, другой со скоростью 0.1" - One should fall in real time, other at 0.1 speed
4. "добавь расширяемость (разные анимации в зависимости от разного оружия)" - Add extensibility (different animations based on weapon type)
5. "тела не должны разваливаться на части" - Bodies should not fall apart

### Additional Requirements (from PR comments)

6. "тело не должно исчезать вообще (сейчас исчезает почти сразу)" - Body should not disappear at all (currently disappears almost immediately)
7. "добавь реакцию тела на выстрелы (отбрасывание для дробовика, дёрганья для автомата и uzi)" - Add body reaction to shots (knockback for shotgun, twitching for rifle and uzi)

## Technical Analysis

### Current Implementation

The death animation system consists of two main components:

1. **`scripts/components/death_animation_component.gd`** - Handles the actual death animation including:
   - Pre-made fall animations based on 24 angle directions (15-degree intervals)
   - Ragdoll physics using `RigidBody2D` and `PinJoint2D`
   - Weapon-type based animation intensity variations
   - `persist_body_after_death` property (default: `true`)

2. **`scripts/objects/enemy.gd`** - Enemy logic including:
   - Death handling via `_on_death()` function
   - Reset/respawn logic via `_reset()` function
   - `respawn_delay` property (default: 2.0 seconds)
   - `destroy_on_death` property (default: `false`)

### Root Cause Analysis

#### Problem 1: Bodies Disappearing

The body disappears because of the **respawn mechanism**:

1. Enemy dies → `_on_death()` called
2. Death animation starts (ragdoll created with duplicated sprites)
3. Original sprites are hidden
4. After `respawn_delay` (2 seconds), `_reset()` is called
5. `_reset()` calls `death_animation.reset(false)` which:
   - Keeps ragdoll bodies (since `persist_body_after_death = true`)
   - **Restores original sprites to visible** (issue!)
6. Enemy respawns at original position with visible sprites
7. **Result**: User sees "new" enemy and thinks body disappeared

The ragdoll bodies actually DO persist, but:
- The enemy respawns quickly (2 seconds)
- Original sprites become visible again at spawn position
- Creates visual confusion

#### Problem 2: No Post-Death Bullet Reactions

Currently, the ragdoll bodies:
- Are created with collision layer 32 (ragdoll) and collision mask 4 (obstacles only)
- **Do not react to bullets** because:
  - They don't have a detection/hit system
  - Bullets use `Area2D` detection, not collision with `RigidBody2D`

## Research Findings

### Godot Ragdoll Physics (2D)

**Sources:**
- [Godot Ragdoll System Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/ragdoll_system.html)
- [Active Ragdoll in Godot Forum](https://forum.godotengine.org/t/active-ragdoll-in-godot-4-5-how-to-achieve-good-results/128728)
- [V-Sekai Active Ragdoll GitHub](https://github.com/V-Sekai/godot-active-ragdoll-physics-animations)

**Key Points:**
- Godot's built-in ragdoll system (`PhysicalBone3D`, `PhysicalBoneSimulator3D`) is for 3D
- For 2D, use `RigidBody2D` with `PinJoint2D` (current approach is correct)
- Each physics body has performance cost - minimize bone count
- For death animations, can blend between animation and physics using "influence" property

### Applying Impulses for Knockback/Reactions

**Sources:**
- [Godot RigidBody2D Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Character vs Rigid Body Interaction](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)
- [How apply_impulse works](https://forum.godotengine.org/t/how-does-apply-impulse-work-on-rigidbody2d/70364)

**Key Points:**
- `apply_impulse()` - one-time instantaneous push (like bat hitting ball)
- `apply_force()` / `apply_central_force()` - continuous force (use in `_physics_process`)
- `_integrate_forces()` - for direct physics state manipulation
- Impulse is time-independent; applying every frame causes framerate-dependent force
- For knockback: use `apply_central_impulse(-collision_normal * push_force)`

### Post-Death Hit Reactions in Games

**Sources:**
- [HowStuffWorks - Ragdoll Physics](https://electronics.howstuffworks.com/ragdoll-physics.htm)
- [NeoGAF - Ragdoll Deaths Discussion](https://www.neogaf.com/threads/what-happened-to-ragdoll-deaths-in-games.810061/)
- [Unity Hit Reaction Ragdoll System](https://discussions.unity.com/t/hit-reaction-ragdoll-system/603102)

**Key Points:**
- Most games switch from animated skeleton to ragdoll on death (hard switch)
- Advanced games (Halo, Max Payne, RDR2) have bodies react to bullets post-death
- Typically uses impulse application at hit point
- Weapon type should affect impulse magnitude and direction
- Shotguns: larger knockback (spread impact)
- Automatic weapons: smaller impulses, more frequent (twitching effect)

## Proposed Solutions

### Solution 1: Prevent Body Disappearance

**Option A: Disable Respawn Completely** (Simple)
- Set `respawn_delay` to very high value (e.g., 999999)
- Or add `disable_respawn` property

**Option B: Keep Respawn but Don't Hide Ragdoll** (Recommended)
- When respawning, keep the ragdoll bodies visible
- Spawn new enemy at original position (existing behavior)
- Ragdoll bodies persist as separate entities

**Option C: Make Ragdoll Bodies Permanent Scene Objects**
- On death, reparent ragdoll bodies to scene root
- Remove reference from enemy
- Bodies persist even if enemy is destroyed

### Solution 2: Post-Death Bullet Reactions

**Implementation Approach:**

1. **Add Area2D to ragdoll bodies** for bullet detection:
   ```gdscript
   var hit_area := Area2D.new()
   hit_area.collision_layer = 0
   hit_area.collision_mask = 8  # Bullet layer
   rb.add_child(hit_area)
   hit_area.area_entered.connect(_on_ragdoll_hit.bind(rb))
   ```

2. **Apply weapon-specific impulses** on hit:
   ```gdscript
   func _on_ragdoll_hit(area: Area2D, rb: RigidBody2D) -> void:
       if area.has_method("get_caliber_data"):
           var caliber = area.get_caliber_data()
           var impulse = calculate_impulse(caliber, area.global_position)
           rb.apply_impulse(impulse, area.global_position - rb.global_position)
   ```

3. **Weapon-specific impulse values:**
   - **Shotgun**: Large single impulse (200-400 units) - knockback
   - **Rifle/Automatic**: Medium impulses (50-100 units) - twitching
   - **Pistol/UZI**: Small impulses (30-50 units) - subtle movement

### Solution 3: Different Animation Speeds for Test Enemies

Already implemented in current PR:
- Test enemies with `animation_speed = 1.0` (real-time)
- Test enemies with `animation_speed = 0.1` (slow motion)

## Implementation Plan

1. **Fix body disappearing**:
   - Add `body_cleanup_timer` with configurable delay (default: -1 for never)
   - When timer expires, fade out and cleanup ragdoll bodies
   - For testing: set very long timer or disable completely

2. **Add post-death bullet reactions**:
   - Create `Area2D` hit detection on ragdoll bodies
   - Connect to bullet collision signal
   - Apply appropriate impulse based on weapon type
   - Unfreeze body briefly when hit, re-freeze after settling

3. **Weapon-specific reaction tuning**:
   - Define impulse profiles per weapon type
   - Shotgun: high magnitude, away from bullet direction
   - Rifle: medium magnitude with slight jitter
   - UZI: low magnitude, rapid (if multiple hits)

## Files to Modify

1. `scripts/components/death_animation_component.gd`
   - Add hit detection to ragdoll bodies
   - Add impulse application on hit
   - Add body cleanup timer system
   - Add weapon-specific impulse profiles

2. `scripts/objects/enemy.gd`
   - Update `_reset()` to properly handle persistent bodies
   - Possibly add method to apply hit impulse to dead enemy

3. `scripts/projectiles/bullet.gd` (minimal changes)
   - Ensure bullets can detect ragdoll bodies if needed

## Risk Assessment

- **Low Risk**: Body persistence changes (isolated to death animation component)
- **Medium Risk**: Bullet detection on ragdoll (needs proper collision layer setup)
- **Low Risk**: Impulse application (standard physics operation)

## Success Criteria

1. Dead bodies persist indefinitely (or until configurable timer)
2. Shooting dead bodies causes visible reaction:
   - Shotgun: noticeable knockback
   - Rifle/UZI: twitching/jerking motion
3. Test enemies work as expected (1.0 and 0.1 speed)
4. No performance degradation with many dead bodies
5. All CI checks pass

---

## Update: January 25, 2026 - Root Cause Discovery

### User Feedback

After initial implementation, user reported:
> "тела всё ещё исчезают, не вижу изменений" (bodies still disappear, I don't see changes)

**User provided log file**: `logs/game_log_20260125_043039.txt`

### Deep Log Analysis

Analyzed the game log and found the critical pattern:

```
[04:30:47] [ENEMY] [Enemy3] Enemy died (ricochet: false, penetration: false)
[04:30:47] [INFO] [DeathAnim] Started - Angle: 0.0 deg, Index: 12
[04:30:48] [ENEMY] [Enemy3] Ragdoll activated
[04:30:48] [INFO] [DeathAnim] Ragdoll activated at 60% fall progress

-- 1 SECOND LATER --

[04:30:48] [INFO] [Player.Grenade] Normal level - starting with 1 grenade
[04:30:48] [INFO] [ScoreManager] Level started with 10 enemies
[04:30:48] [ENEMY] [Enemy1] Death animation component initialized
[04:30:48] [ENEMY] [Enemy2] Death animation component initialized
... (all enemies re-initialized)
```

**Key Observation**: "Level started with 10 enemies" appears multiple times in quick succession, indicating **level restarts**.

### TRUE Root Cause

The issue was **NOT** with `respawn_delay` (individual enemy respawn), but with **SCENE RELOAD**:

1. **Level Architecture**:
   - `building_level.gd` line 510-516: When player dies, calls `GameManager.on_player_death()`
   - `game_manager.gd` line 124-128: `on_player_death()` calls `restart_scene()`
   - `game_manager.gd` line 131-134: `restart_scene()` calls `get_tree().reload_current_scene()`

2. **Impact of Scene Reload**:
   - `reload_current_scene()` **destroys the entire scene tree**
   - All nodes, including ragdoll bodies, are freed
   - Scene is recreated fresh with all enemies alive
   - **Even with `persist_body_after_death = true`, bodies are destroyed on scene reload**

3. **Why Previous Fix Didn't Work**:
   - Previous fix set `respawn_delay = 999999` only for TestTier level
   - User was playing on BuildingLevel (main game level)
   - Even if respawn was disabled, player death restarts the entire level
   - **Scene reload = all physics bodies (including ragdoll) destroyed**

### Solution: RagdollManager Autoload

**Solution**: Create an autoload (`RagdollManager`) that persists across scene changes.

**How it works**:
1. When ragdoll animation completes, bodies are reparented to `RagdollManager`
2. `RagdollManager` is an autoload (under `/root/`), which persists across scene changes
3. When level restarts, `RagdollManager` keeps the ragdoll bodies alive
4. Bodies continue to exist in the new scene instance

**Files Added/Modified**:
1. **NEW** `scripts/autoload/ragdoll_manager.gd` - Manages persistent ragdoll bodies
2. **MODIFIED** `project.godot` - Added RagdollManager autoload
3. **MODIFIED** `scripts/components/death_animation_component.gd`:
   - Added `_register_with_ragdoll_manager()` function
   - Bodies are registered when ragdoll reaches AT_REST state
   - Bodies are reparented to RagdollManager container

### Technical Details

**RagdollManager Features**:
- `max_persistent_bodies` - Limit to prevent memory leaks (default: 50)
- `persist_bodies` - Toggle persistence on/off
- Automatic cleanup of oldest bodies when limit exceeded
- Automatic cleanup of invalid references after scene change
- Logging for debugging

**Integration with DeathAnimationComponent**:
```gdscript
# When ragdoll reaches AT_REST state:
if persist_body_after_death:
    _register_with_ragdoll_manager()

# This reparents bodies from current_scene to RagdollManager container
```

### Sequence of Events (Fixed)

1. Enemy dies → Death animation starts
2. Ragdoll created (RigidBody2D nodes)
3. Ragdoll settles → AT_REST state
4. `_register_with_ragdoll_manager()` called
5. Bodies reparented to `/root/RagdollManager/PersistentRagdolls`
6. **Player dies → Level restarts**
7. Current scene destroyed, but RagdollManager persists
8. New scene loads, ragdoll bodies still visible
9. Bodies persist indefinitely (until max_persistent_bodies exceeded)

### Lessons Learned

1. **Scene reload vs node lifecycle**: Godot's scene reload destroys ALL nodes in the scene tree. Only autoloads survive.
2. **Testing environment matters**: TestTier had different setup than BuildingLevel - always test on actual user environment.
3. **Log analysis is crucial**: The "Level started with 10 enemies" pattern revealed the true cause.
4. **Reparenting for persistence**: To persist objects across scene changes, reparent them to autoloads.
