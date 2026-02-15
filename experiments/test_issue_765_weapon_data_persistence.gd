extends Node
## Experiment script to test and diagnose Issue #765
## Bug: Sometimes after restart, weapon gets 30 rounds and 5.45 casings (even for revolver)
##
## This script tests weapon data integrity during scene restart.
## Usage: Run this script and press Q to restart, check logs for any data corruption.

var _frame_count: int = 0
var _restart_count: int = 0

func _ready() -> void:
	print("\n" + "="*80)
	print("[Issue765Test] Experiment started - Testing weapon data persistence")
	print("[Issue765Test] Restart count: %d" % _restart_count)
	print("="*80 + "\n")

	# Wait a frame for scene to fully load
	await get_tree().process_frame
	_check_all_weapons()


func _process(_delta: float) -> void:
	_frame_count += 1

	# Check weapon data every 60 frames (about once per second at 60 FPS)
	if _frame_count % 60 == 0:
		_check_all_weapons()


func _check_all_weapons() -> void:
	var weapons := _find_all_weapons(get_tree().root)

	if weapons.is_empty():
		print("[Issue765Test] No weapons found in scene")
		return

	print("\n[Issue765Test] ========== Weapon Check (frame %d) ==========" % _frame_count)

	for weapon in weapons:
		_check_weapon_data(weapon)

	print("[Issue765Test] ===============================================\n")


func _find_all_weapons(node: Node) -> Array:
	var weapons: Array = []

	# Check if this node is a weapon (has WeaponData property)
	if node.get("WeaponData") != null:
		weapons.append(node)

	# Recursively check children
	for child in node.get_children():
		weapons.append_array(_find_all_weapons(child))

	return weapons


func _check_weapon_data(weapon: Node) -> void:
	var weapon_name := weapon.name
	var weapon_data = weapon.get("WeaponData")
	var bullet_scene = weapon.get("BulletScene")
	var casing_scene = weapon.get("CasingScene")

	print("[Issue765Test] Weapon: %s" % weapon_name)
	print("[Issue765Test]   Path: %s" % weapon.get_path())

	if weapon_data == null:
		print("[Issue765Test]   ERROR: WeaponData is NULL!")
		return

	# Get WeaponData properties
	var weapon_data_name := weapon_data.get("Name") if weapon_data.get("Name") != null else "UNKNOWN"
	var magazine_size: int = weapon_data.get("MagazineSize") if weapon_data.get("MagazineSize") != null else -1
	var caliber = weapon_data.get("Caliber")

	print("[Issue765Test]   WeaponData.Name: %s" % weapon_data_name)
	print("[Issue765Test]   WeaponData.MagazineSize: %d" % magazine_size)

	# Check for mismatch between weapon name and data
	var expected_mag_sizes := {
		"Revolver": 5,
		"AssaultRifle": 30,
		"MakarovPM": 8,
		"Shotgun": 8,
		"MiniUzi": 32,
		"SilencedPistol": 8,
		"SniperRifle": 10,
		"AKGL": 30
	}

	if weapon_name in expected_mag_sizes:
		var expected := expected_mag_sizes[weapon_name]
		if magazine_size != expected:
			print("[Issue765Test]   ⚠️ WARNING: Magazine size mismatch!")
			print("[Issue765Test]   Expected: %d, Got: %d" % [expected, magazine_size])
			print("[Issue765Test]   This is likely the Issue #765 bug!")

	# Check caliber data
	if caliber == null:
		print("[Issue765Test]   Caliber: NULL")
	else:
		var caliber_name := caliber.get("caliber_name") if caliber.get("caliber_name") != null else "UNKNOWN"
		print("[Issue765Test]   Caliber: %s" % caliber_name)

		# Check for expected calibers
		var expected_calibers := {
			"Revolver": "12.7x55mm",
			"AssaultRifle": "5.45x39mm",
			"MakarovPM": "9x18mm",
			"Shotgun": "Buckshot",
			"MiniUzi": "9x19mm",
			"SilencedPistol": "9x19mm",
			"SniperRifle": "12.7x108mm",
			"AKGL": "7.62x39mm"
		}

		if weapon_name in expected_calibers:
			var expected_caliber := expected_calibers[weapon_name]
			if caliber_name != expected_caliber:
				print("[Issue765Test]   ⚠️ WARNING: Caliber mismatch!")
				print("[Issue765Test]   Expected: %s, Got: %s" % [expected_caliber, caliber_name])
				print("[Issue765Test]   This is likely the Issue #765 bug!")

	# Check current ammo
	var current_ammo := weapon.get("CurrentAmmo")
	if current_ammo != null:
		print("[Issue765Test]   CurrentAmmo: %d" % current_ammo)

	# Get resource paths for debugging
	var weapon_data_path := weapon_data.resource_path if weapon_data.resource_path != "" else "NOT_A_FILE_RESOURCE"
	print("[Issue765Test]   WeaponData resource path: %s" % weapon_data_path)

	if caliber != null:
		var caliber_path := caliber.resource_path if caliber.resource_path != "" else "NOT_A_FILE_RESOURCE"
		print("[Issue765Test]   Caliber resource path: %s" % caliber_path)

	print("")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		print("\n[Issue765Test] Manual trigger - checking weapons now")
		_check_all_weapons()
