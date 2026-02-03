class_name WeaponConfigComponent
extends RefCounted
## Static utility for weapon type configurations.
## Used by enemy.gd to configure weapon parameters based on weapon type.

## Weapon type configurations as static data.
## Keys: "shoot_cooldown", "bullet_speed", "magazine_size", "bullet_spawn_offset", "weapon_loudness", "sprite_path"
const WEAPON_CONFIGS := {
	0: {  # RIFLE (M16)
		"shoot_cooldown": 0.1,
		"bullet_speed": 2500.0,
		"magazine_size": 30,
		"bullet_spawn_offset": 30.0,
		"weapon_loudness": 1469.0,
		"sprite_path": ""  # Default sprite already in scene
	},
	1: {  # SHOTGUN
		"shoot_cooldown": 0.8,
		"bullet_speed": 1800.0,
		"magazine_size": 8,
		"bullet_spawn_offset": 35.0,
		"weapon_loudness": 2000.0,
		"sprite_path": "res://assets/sprites/weapons/shotgun_topdown.png"
	},
	2: {  # UZI
		"shoot_cooldown": 0.06,
		"bullet_speed": 2200.0,
		"magazine_size": 32,
		"bullet_spawn_offset": 25.0,
		"weapon_loudness": 1200.0,
		"sprite_path": "res://assets/sprites/weapons/mini_uzi_topdown.png"
	}
}


## Get weapon configuration for a given weapon type.
static func get_config(weapon_type: int) -> Dictionary:
	if WEAPON_CONFIGS.has(weapon_type):
		return WEAPON_CONFIGS[weapon_type]
	return WEAPON_CONFIGS[0]  # Default to RIFLE


## Get weapon type name for logging.
static func get_type_name(weapon_type: int) -> String:
	match weapon_type:
		0: return "RIFLE"
		1: return "SHOTGUN"
		2: return "UZI"
		_: return "UNKNOWN"
