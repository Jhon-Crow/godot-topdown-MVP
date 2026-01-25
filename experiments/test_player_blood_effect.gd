## Experiment: Test Player Blood Effect (Issue #350)
##
## This script tests that blood effects spawn correctly when the player takes damage.
## Run this to verify that blood splashes and puddles appear when the player is hit,
## just like they do for enemies.
##
## How to test manually:
## 1. Start the game
## 2. Let an enemy shoot the player
## 3. Observe: Blood splashes (red particles) should appear at player position
## 4. Observe: Blood puddles (floor decals) should appear after particles land
##
## The behavior should be identical to when enemies are shot:
## - Non-lethal hits: Blood splash particles + 10 floor decals
## - Lethal hits: Larger blood splash (1.5x scale) + 20 floor decals

extends Node


func _ready() -> void:
	print("=== Player Blood Effect Test (Issue #350) ===")
	print("")
	print("Testing that blood effects spawn correctly for player hits...")
	print("")

	# Find the ImpactEffectsManager
	var impact_manager = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null:
		push_error("ImpactEffectsManager not found! Blood effects will not work.")
		print("ERROR: ImpactEffectsManager not found at /root/ImpactEffectsManager")
		return

	print("OK: ImpactEffectsManager found")

	# Verify blood effect method exists
	if not impact_manager.has_method("spawn_blood_effect"):
		push_error("spawn_blood_effect method not found on ImpactEffectsManager!")
		print("ERROR: spawn_blood_effect method not found")
		return

	print("OK: spawn_blood_effect method exists")

	# Find the player
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		print("WARNING: Player not found in scene (run in actual game level)")
		print("")
		print("Testing blood effect spawn directly...")
		_test_blood_spawn_directly(impact_manager)
		return

	print("OK: Player found")

	# Verify player has on_hit_with_info method
	if not player.has_method("on_hit_with_info"):
		push_error("Player is missing on_hit_with_info method!")
		print("ERROR: Player missing on_hit_with_info method")
		return

	print("OK: Player has on_hit_with_info method")
	print("")
	print("=== All checks passed! ===")
	print("")
	print("To test in-game:")
	print("1. Let an enemy shoot the player")
	print("2. Watch for blood splash particles at player position")
	print("3. Watch for blood puddles appearing on the floor")
	print("")
	print("The blood effect should be identical to enemy hits.")


## Test spawning blood effect directly (without needing a player in scene)
func _test_blood_spawn_directly(impact_manager: Node) -> void:
	# Get viewport center for spawn position
	var spawn_pos = Vector2(400, 300)
	var viewport = get_viewport()
	if viewport:
		spawn_pos = viewport.get_visible_rect().size / 2.0

	print("Spawning test blood effects at ", spawn_pos)
	print("")

	# Spawn non-lethal hit effect
	print("1. Spawning non-lethal blood effect (is_lethal=false)...")
	impact_manager.spawn_blood_effect(spawn_pos + Vector2(-100, 0), Vector2.RIGHT, null, false)
	print("   -> Blood splash spawned at ", spawn_pos + Vector2(-100, 0))

	# Spawn lethal hit effect
	print("2. Spawning lethal blood effect (is_lethal=true)...")
	impact_manager.spawn_blood_effect(spawn_pos + Vector2(100, 0), Vector2.LEFT, null, true)
	print("   -> Blood splash spawned at ", spawn_pos + Vector2(100, 0))

	print("")
	print("Test complete! Check the game window for blood effects.")
	print("- Left side: non-lethal hit (smaller)")
	print("- Right side: lethal hit (larger, 1.5x scale)")
