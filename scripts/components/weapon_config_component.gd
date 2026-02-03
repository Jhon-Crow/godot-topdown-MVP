class_name WeaponConfigComponent
extends RefCounted
## Static utility for weapon type configurations.
## Used by enemy.gd to configure weapon parameters based on weapon type.
## Updated to use the same bullet/casing scenes as player weapons (Issue #417 PR feedback).

## Weapon type configurations as static data.
## Keys: "shoot_cooldown", "bullet_speed", "magazine_size", "bullet_spawn_offset", "weapon_loudness", "sprite_path"
## Added: "bullet_scene_path", "casing_scene_path", "caliber_path", "is_shotgun", "pellet_count_min", "pellet_count_max", "spread_angle"
const WEAPON_CONFIGS := {
	0: {  # RIFLE (M16) - uses same bullets as player's AssaultRifle
		"shoot_cooldown": 0.1,
		"bullet_speed": 2500.0,
		"magazine_size": 30,
		"bullet_spawn_offset": 30.0,
		"weapon_loudness": 1469.0,
		"sprite_path": "",  # Default sprite already in scene
		"bullet_scene_path": "res://scenes/projectiles/csharp/Bullet.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_545x39.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0
	},
	1: {  # SHOTGUN - uses same pellets as player's Shotgun (multiple projectiles)
		"shoot_cooldown": 0.8,
		"bullet_speed": 1800.0,
		"magazine_size": 8,
		"bullet_spawn_offset": 35.0,
		"weapon_loudness": 2000.0,
		"sprite_path": "res://assets/sprites/weapons/shotgun_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/csharp/ShotgunPellet.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_buckshot.tres",
		"is_shotgun": true,
		"pellet_count_min": 6,
		"pellet_count_max": 10,
		"spread_angle": 15.0  # degrees
	},
	2: {  # UZI - uses same 9mm bullets as player's MiniUzi
		"shoot_cooldown": 0.06,
		"bullet_speed": 2200.0,
		"magazine_size": 32,
		"bullet_spawn_offset": 25.0,
		"weapon_loudness": 1200.0,
		"sprite_path": "res://assets/sprites/weapons/mini_uzi_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/Bullet9mm.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_9x19.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0
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
