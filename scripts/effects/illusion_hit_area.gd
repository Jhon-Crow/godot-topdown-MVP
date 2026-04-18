extends Area2D
## Hit area for illusion effects (Issue #1353).
##
## Lightweight replacement for the full Enemy HitArea.
## Responds to bullet hits by destroying the illusion (1 HP).
## Bullets pass through illusions without losing damage.

## Reference to the parent IllusionEffect.
var illusion_parent: Node2D = null


## Called when a bullet hits this illusion.
## Matches the interface expected by bullet.gd's _on_area_entered.
func on_hit() -> void:
	if illusion_parent and illusion_parent.has_method("take_damage"):
		illusion_parent.take_damage(1.0)


## Extended hit handler with bullet info and damage (Issue #1196 compatible).
func on_hit_with_bullet_info_and_damage(_direction: Vector2, _caliber_data: Resource, _is_ricochet: bool, _is_penetration: bool, _damage: float, _from_player: bool, _attacker_node: Node2D = null) -> void:
	on_hit()


## Extended hit handler with bullet info (legacy compatibility).
func on_hit_with_bullet_info(_direction: Vector2, _caliber_data: Resource, _is_ricochet: bool, _is_penetration: bool, _from_player: bool, _attacker_node: Node2D = null) -> void:
	on_hit()


## Extended hit handler with caliber info.
func on_hit_with_info(_direction: Vector2, _caliber_data: Resource) -> void:
	on_hit()


## Report as alive so bullets don't skip this target.
func is_alive() -> bool:
	if illusion_parent and illusion_parent.has_method("is_alive"):
		return illusion_parent.is_alive()
	return false
