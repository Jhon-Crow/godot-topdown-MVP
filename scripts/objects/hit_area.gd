extends Area2D
## Hit detection area that forwards on_hit calls to its parent.
##
## This is used as a child of CharacterBody2D-based enemies to allow
## Area2D-based projectiles (bullets) to detect hits on the enemy.


## Called when hit by a projectile.
## Forwards the call to the parent if it has an on_hit method.
func on_hit() -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_hit"):
		parent.on_hit()


## Called when hit by a projectile with extended hit information.
## Forwards the call to the parent with hit direction and caliber data.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Caliber resource for effect scaling.
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_hit_with_info"):
		parent.on_hit_with_info(hit_direction, caliber_data)
	elif parent and parent.has_method("on_hit"):
		# Fallback to basic on_hit if extended method not available
		parent.on_hit()


## Called when hit by a projectile with full bullet information.
## Forwards the call to the parent with hit direction, caliber data, and bullet properties.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Caliber resource for effect scaling.
## @param has_ricocheted: Whether the bullet had ricocheted before this hit.
## @param has_penetrated: Whether the bullet had penetrated a wall before this hit.
func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool) -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_hit_with_bullet_info"):
		parent.on_hit_with_bullet_info(hit_direction, caliber_data, has_ricocheted, has_penetrated)
	elif parent and parent.has_method("on_hit_with_info"):
		# Fallback to on_hit_with_info if extended method not available
		parent.on_hit_with_info(hit_direction, caliber_data)
	elif parent and parent.has_method("on_hit"):
		# Fallback to basic on_hit
		parent.on_hit()


## Called when hit by a projectile with full bullet information AND explicit damage.
## This is the primary entry point for bullets that set their own damage (e.g., silenced pistol).
## Forwards the call to the parent with all parameters including damage.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Caliber resource for effect scaling.
## @param has_ricocheted: Whether the bullet had ricocheted before this hit.
## @param has_penetrated: Whether the bullet had penetrated a wall before this hit.
## @param bullet_damage: The damage amount to apply (from bullet.damage × damage_multiplier).
func on_hit_with_bullet_info_and_damage(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float) -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_hit_with_bullet_info"):
		# Pass damage as the 5th parameter - enemy.on_hit_with_bullet_info supports this
		parent.on_hit_with_bullet_info(hit_direction, caliber_data, has_ricocheted, has_penetrated, bullet_damage)
	elif parent and parent.has_method("take_damage"):
		# Fallback: call take_damage directly if extended method not available
		parent.take_damage(bullet_damage)
	elif parent and parent.has_method("on_hit"):
		# Last resort fallback to basic on_hit (won't apply correct damage)
		parent.on_hit()
