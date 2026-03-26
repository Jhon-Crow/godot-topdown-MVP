class_name WeaponConfigComponent
extends RefCounted
## Static utility for weapon type configurations.
## Used by enemy.gd to configure weapon parameters based on weapon type.
## Updated to use the same bullet/casing scenes as player weapons (Issue #417 PR feedback).

## Weapon type configurations as static data.
## Keys: "shoot_cooldown", "bullet_speed", "magazine_size", "bullet_spawn_offset", "weapon_loudness", "sprite_path"
## Added: "bullet_scene_path", "casing_scene_path", "caliber_path", "is_shotgun", "pellet_count_min", "pellet_count_max", "spread_angle"
## Added (Issue #516): "spread_threshold", "initial_spread", "spread_increment", "max_spread", "spread_reset_time"
## for progressive spread on single-bullet weapons (same as player weapons).
## Added (Issue #583): RPG (type 4) with "is_rpg", "rpg_explosion_radius", "rpg_explosion_damage", "switch_weapon_type"
## and PM pistol (type 5) for RPG enemy weapon switching.
## Added (Issue #1033): MACHINE_GUN (PKM belt-fed, type 6).
## Added (Issue #1125): SNIPER_RIFLE (ASVK, type 7).
## Added (Issue #1532): SILENCED_PISTOL (type 9) for Drone Operator active phase.
const WEAPON_CONFIGS := {
	0: {  # RIFLE (M16) - uses same bullets as player's AssaultRifle
		"shoot_cooldown": 0.1,
		"bullet_speed": 2500.0,
		"magazine_size": 30,
		"bullet_spawn_offset": 30.0,
		"weapon_loudness": 800.0,
		"sprite_path": "",  # Default sprite already in scene
		"bullet_scene_path": "res://scenes/projectiles/csharp/Bullet.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_545x39.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		# Progressive spread matching player AssaultRifle (player.gd constants)
		"spread_threshold": 3,
		"initial_spread": 0.5,
		"spread_increment": 0.6,
		"max_spread": 4.0,
		"spread_reset_time": 0.25
	},
	1: {  # SHOTGUN - uses same pellets as player's Shotgun (multiple projectiles)
		"shoot_cooldown": 0.8,
		"bullet_speed": 1800.0,
		"magazine_size": 8,
		"bullet_spawn_offset": 35.0,
		"weapon_loudness": 1089.2,
		"sprite_path": "res://assets/sprites/weapons/shotgun_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/csharp/ShotgunPellet.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_buckshot.tres",
		"is_shotgun": true,
		"pellet_count_min": 6,
		"pellet_count_max": 10,
		"spread_angle": 15.0,  # degrees
		# Shotgun uses pellet spread, not progressive spread
		"spread_threshold": 0,
		"initial_spread": 0.0,
		"spread_increment": 0.0,
		"max_spread": 0.0,
		"spread_reset_time": 0.0
	},
	2: {  # UZI - uses same 9mm bullets as player's MiniUzi
		"shoot_cooldown": 0.06,
		"bullet_speed": 2200.0,
		"magazine_size": 32,
		"total_magazines": 20,  # Issue #1137: 4x increase from default 5
		"bullet_spawn_offset": 25.0,
		"weapon_loudness": 653.5,
		"sprite_path": "res://assets/sprites/weapons/mini_uzi_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/Bullet9mm.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_9x19.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		# Progressive spread matching player MiniUzi (MiniUzi.cs constants)
		# UZI spread starts immediately (threshold=0) and reaches 60° after 10 shots
		"spread_threshold": 0,
		"initial_spread": 6.0,
		"spread_increment": 5.4,
		"max_spread": 60.0,
		"spread_reset_time": 0.3
	},
	3: {  # MACHETE - melee weapon (Issue #579)
		"shoot_cooldown": 1.5,  # Melee attack cooldown
		"bullet_speed": 0.0,  # No projectiles
		"magazine_size": 0,  # No ammo needed
		"bullet_spawn_offset": 0.0,
		"weapon_loudness": 108.9,  # Quiet melee swing sound
		"sprite_path": "res://assets/sprites/weapons/machete_topdown.png",
		"bullet_scene_path": "",  # No bullets
		"casing_scene_path": "",  # No casings
		"caliber_path": "",
		"is_shotgun": false,
		"pellet_count_min": 0,
		"pellet_count_max": 0,
		"spread_angle": 0.0,
		"spread_threshold": 0,
		"initial_spread": 0.0,
		"spread_increment": 0.0,
		"max_spread": 0.0,
		"spread_reset_time": 0.0,
		# Machete-specific config
		"is_melee": true,
		"melee_range": 80.0,
		"melee_damage": 2,
		"dodge_speed": 400.0,
		"dodge_distance": 120.0,
		"sneak_speed_multiplier": 0.6
	},
	4: {  # RPG - rocket launcher, single shot then switches to PM (Issue #583)
		"shoot_cooldown": 2.0,  # Slow RPG fire (only 1 shot anyway)
		"bullet_speed": 800.0,  # Rocket speed (slower than bullets)
		"magazine_size": 1,  # Only 1 RPG round
		"bullet_spawn_offset": 35.0,
		"weapon_loudness": 1361.5,  # Very loud rocket launch
		"sprite_path": "res://assets/sprites/weapons/rpg_topdown.png",  # RPG sprite
		"bullet_scene_path": "res://scenes/projectiles/RpgRocket.tscn",
		"casing_scene_path": "",  # No casings for RPG
		"caliber_path": "",  # Rocket has no caliber
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		"spread_threshold": 0,
		"initial_spread": 0.0,
		"spread_increment": 0.0,
		"max_spread": 0.0,
		"spread_reset_time": 0.0,
		# RPG-specific config
		"is_rpg": true,
		"rpg_explosion_radius": 150.0,
		"rpg_explosion_damage": 3,
		# PM config to switch to after RPG shot
		"switch_weapon_type": 5
	},
	5: {  # PM (Makarov pistol) - used by RPG enemy after switching (Issue #583)
		"shoot_cooldown": 0.3,  # Semi-auto pistol
		"bullet_speed": 1000.0,  # Makarov PM speed
		"magazine_size": 9,  # PM magazine
		"bullet_spawn_offset": 25.0,
		"weapon_loudness": 800.0,
		"sprite_path": "res://assets/sprites/weapons/makarov_pm_topdown.png",  # PM sprite (Issue #583)
		"bullet_scene_path": "res://scenes/projectiles/Bullet9mm.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_9x18.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		"spread_threshold": 2,
		"initial_spread": 1.0,
		"spread_increment": 0.8,
		"max_spread": 5.0,
		"spread_reset_time": 0.3
	},
	6: {  # MACHINE_GUN (PKM) - belt-fed heavy machine gun (Issue #1033)
		"shoot_cooldown": 0.12,     # Slightly slower than rifle (~8.3 rps)
		"bullet_speed": 2800.0,     # High muzzle velocity
		"magazine_size": 500,       # Full belt
		"total_magazines": 2,       # 500 + 500 (one spare belt)
		"reload_time": 9.0,         # Long belt reload
		"bullet_spawn_offset": 40.0,
		"weapon_loudness": 1198.1,
		"sprite_path": "res://assets/sprites/weapons/pkm_topdown.png",  # PKM machine gun top-down sprite (#1033)
		"bullet_scene_path": "res://scenes/projectiles/csharp/Bullet.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_762x39.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		# Progressive spread: sustained fire degrades accuracy
		"spread_threshold": 5,
		"initial_spread": 0.3,
		"spread_increment": 0.4,
		"max_spread": 6.0,
		"spread_reset_time": 0.4
	},
	7: {  # SNIPER_RIFLE (ASVK) - anti-materiel bolt-action sniper rifle (Issue #1125)
		"shoot_cooldown": 3.0,      # Slow bolt-action rate (~0.33 rps)
		"bullet_speed": 10000.0,    # Near-instant (same as player ASVK)
		"magazine_size": 5,         # 5-round magazine (same as player ASVK)
		"total_magazines": 14,      # 5 + 65 extra rounds = 70 total (Issue #1161)
		"reload_time": 4.0,         # Long reload for heavy rifle
		"bullet_spawn_offset": 60.0,
		"weapon_loudness": 1633.8,  # Very loud anti-materiel rifle
		"sprite_path": "res://assets/sprites/weapons/asvk_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/csharp/SniperBulletEnemy.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_127x108.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		# No spread — sniper rifle is perfectly accurate
		"spread_threshold": 999,
		"initial_spread": 0.0,
		"spread_increment": 0.0,
		"max_spread": 0.0,
		"spread_reset_time": 0.0
	},
	8: {  # REVOLVER (RSh-12) - heavy semi-auto revolver used by SWAT shieldbearer (Issue #1242)
		"shoot_cooldown": 0.35,     # Semi-auto revolver pace
		"bullet_speed": 2000.0,     # 12.7mm pistol muzzle velocity
		"magazine_size": 5,         # 5-chamber cylinder (same as player revolver)
		"total_magazines": 4,       # 4 reloads (20 extra rounds in pouches)
		"reload_time": 5.0,         # Cylinder reload (longer than semi-auto pistol)
		"bullet_spawn_offset": 30.0,
		"weapon_loudness": 2000.0,  # Loud heavy caliber revolver
		"sprite_path": "res://assets/sprites/weapons/revolver_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/csharp/Bullet12p7mm.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_12p7x55.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		# Minimal spread — heavy caliber, semi-auto
		"spread_threshold": 2,
		"initial_spread": 0.5,
		"spread_increment": 0.5,
		"max_spread": 3.0,
		"spread_reset_time": 0.4
	},
	9: {  # SILENCED_PISTOL — suppressed 9x19mm pistol with laser sight (Issue #1532, Drone Operator)
		"shoot_cooldown": 0.2,      # Semi-auto, slightly faster than PM
		"bullet_speed": 1350.0,     # Matches SilencedPistolData.tres BulletSpeed
		"magazine_size": 13,        # Matches SilencedPistolData.tres MagazineSize
		"total_magazines": 3,       # 3 reloads (39 extra rounds)
		"reload_time": 2.0,         # Matches SilencedPistolData.tres ReloadTime
		"bullet_spawn_offset": 33.0,  # Matches SilencedPistol.tscn BulletSpawnOffset
		"weapon_loudness": 0.0,     # Silent — matches SilencedPistolData.tres Loudness=0
		"sprite_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
		"bullet_scene_path": "res://scenes/projectiles/Bullet9mm.tscn",
		"casing_scene_path": "res://scenes/effects/Casing.tscn",
		"caliber_path": "res://resources/calibers/caliber_9x19.tres",
		"is_shotgun": false,
		"pellet_count_min": 1,
		"pellet_count_max": 1,
		"spread_angle": 0.0,
		# Tight spread matching SilencedPistolData.tres SpreadAngle=1.5 (accurate weapon)
		"spread_threshold": 2,
		"initial_spread": 0.5,
		"spread_increment": 0.4,
		"max_spread": 2.5,
		"spread_reset_time": 0.3,
		# Laser sight visual flag (handled by DroneOperatorComponent)
		"has_laser_sight": true
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
		3: return "MACHETE"
		4: return "RPG"
		5: return "PM"
		6: return "MACHINE_GUN"
		7: return "SNIPER_RIFLE"
		8: return "REVOLVER"
		9: return "SILENCED_PISTOL"
		_: return "UNKNOWN"
