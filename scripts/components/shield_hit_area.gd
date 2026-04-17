class_name ShieldHitArea
extends Area2D
## Hit detection area for the SWAT shield (Issue #1242).
## Attached as a child of the shield visual on EnemyModel.
## When a bullet hits this area, the shield component intercepts
## the damage instead of the enemy's body HitArea.
## Bullets that miss the shield (hit from side/back) bypass this area
## and hit the enemy's body HitArea directly, dealing normal damage.

## Reference to the EnemyShieldComponent that owns this area.
var shield_component: Node = null

## Reference to the parent enemy (CharacterBody2D).
var enemy: Node2D = null


## Called when hit by a projectile with full bullet info and damage.
func on_hit_with_bullet_info_and_damage(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float, is_from_player: bool = false, attacker_node: Node2D = null) -> void:
	if shield_component and shield_component.is_active():
		if shield_component.try_intercept_hit(caliber_data, bullet_damage, hit_direction):
			# Issue #1242: shield enemy slowly rotates toward attacker when shield absorbs a hit.
			if enemy and enemy.has_method("_set_hit_reaction_target"):
				enemy._set_hit_reaction_target(-hit_direction.normalized())
			return  # Shield blocked the hit
	# Shield didn't block (down, or sniper round) — forward to enemy
	_forward_to_enemy(hit_direction, caliber_data, has_ricocheted, has_penetrated, bullet_damage, is_from_player, attacker_node)


## Called when hit with bullet info (no explicit damage).
func on_hit_with_bullet_info(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, is_from_player: bool = false, attacker_node: Node2D = null) -> void:
	on_hit_with_bullet_info_and_damage(hit_direction, caliber_data, has_ricocheted, has_penetrated, 1.0, is_from_player, attacker_node)


## Called when hit with basic info.
func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
	on_hit_with_bullet_info_and_damage(hit_direction, caliber_data, false, false, 1.0, false)


## Called when hit with no info.
func on_hit() -> void:
	on_hit_with_bullet_info_and_damage(Vector2.RIGHT, null, false, false, 1.0, false)


## Forward the hit to the enemy when shield doesn't block.
func _forward_to_enemy(hit_direction: Vector2, caliber_data: Resource, has_ricocheted: bool, has_penetrated: bool, bullet_damage: float, is_from_player: bool, attacker_node: Node2D = null) -> void:
	if enemy and enemy.has_method("on_hit_with_bullet_info"):
		enemy.on_hit_with_bullet_info(hit_direction, caliber_data, has_ricocheted, has_penetrated, bullet_damage, is_from_player, attacker_node)
	elif enemy and enemy.has_method("on_hit"):
		enemy.on_hit()
