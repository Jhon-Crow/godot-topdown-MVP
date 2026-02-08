# Issue #676: Force Field Active Item

## Requirements (from issue)
- Active item activated on Space key press
- Glowing force field appears around the player
- 100% chance to reflect ALL projectiles (bullets, shrapnel, grenades)
- Offensive/frag grenades bounce off WITHOUT detonating on contact
- 1 charge per fight (per level)
- Effect lasts 8 seconds

## Architecture Decision

### Approach: Area2D-based deflection zone
The force field is implemented as a circular Area2D around the player that detects
incoming projectiles. When a projectile enters the force field area, it is reflected
back in the opposite direction (mirrored across the field surface normal).

### Key design decisions:
1. **Active Item System**: Follows existing pattern from Flashlight (ActiveItemManager enum + player.gd init/input handling)
2. **Projectile detection**: Uses Area2D with collision mask for projectiles (layer 16) + grenades (layer 32)
3. **Reflection mechanics**: Bullets/shrapnel get their direction reversed (reflected off the sphere surface normal). Grenades get velocity reversed via linear_velocity reflection.
4. **Frag grenade special handling**: When a frag grenade hits the force field, it bounces off WITHOUT triggering impact explosion. This requires temporarily disabling `_is_thrown` and re-enabling after bounce.
5. **Visual effect**: Glowing circular shader effect with pulsing animation, using CanvasItem shader for the shield bubble visual.
6. **Charge system**: 1 charge per level, consumed on activation, cannot be recharged.

### Files modified:
- `scripts/autoload/active_item_manager.gd` - Add FORCE_FIELD enum
- `scripts/characters/player.gd` - Add force field init/input handling
- `scripts/projectiles/bullet.gd` - Add force field area detection in _on_area_entered
- `scripts/projectiles/shrapnel.gd` - Add force field area detection in _on_area_entered
- `scripts/projectiles/grenade_base.gd` - Add force field detection in _on_body_entered
- `scripts/projectiles/frag_grenade.gd` - Override to prevent impact explosion on force field bounce

### Files created:
- `scripts/effects/force_field_effect.gd` - Force field effect script
- `scripts/shaders/force_field.gdshader` - Glowing shield shader
- `scenes/effects/ForceFieldEffect.tscn` - Force field scene

### Physics interaction:
- Bullets (Area2D, layer 16): Detected via area_entered signal on force field Area2D
- Shrapnel (Area2D, layer 16): Same as bullets
- Grenades (RigidBody2D, collision_layer 32): Detected via body_entered on force field Area2D
