extends Node
## Experiment script to test collision detection between player and enemies (Issue #512)
##
## This script validates that:
## 1. Player can collide with enemies
## 2. Enemies can collide with player
## 3. Enemies can collide with each other
##
## How to test manually:
## 1. Open any level scene (e.g., BuildingLevel.tscn)
## 2. Run the game
## 3. Try to walk through enemies - player should be blocked
## 4. Watch enemies move - they should not pass through each other
##
## Expected behavior after fix:
## - Player collision_mask = 6 (layers 2+3: enemies + obstacles)
## - Enemy collision_mask = 7 (layers 1+2+3: player + enemies + obstacles)
## - No pass-through between any characters

func _ready():
	print("=== Collision Detection Test (Issue #512) ===")

	# Test 1: Check player collision configuration
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var player_mask = player.collision_mask
		var player_layer = player.collision_layer
		print("Player collision_layer: ", player_layer, " (should be 1)")
		print("Player collision_mask: ", player_mask, " (should be 6)")

		# Verify player can detect enemies (layer 2) and obstacles (layer 3)
		var detects_enemies = (player_mask & 2) != 0
		var detects_obstacles = (player_mask & 4) != 0
		print("  - Detects enemies (layer 2): ", detects_enemies)
		print("  - Detects obstacles (layer 3): ", detects_obstacles)

		if player_mask != 6:
			push_error("FAIL: Player collision_mask is not 6!")
		else:
			print("PASS: Player collision_mask is correct")
	else:
		print("WARNING: No player found in scene")

	print()

	# Test 2: Check enemy collision configuration
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.size() > 0:
		var enemy = enemies[0]
		var enemy_mask = enemy.collision_mask
		var enemy_layer = enemy.collision_layer
		print("Enemy collision_layer: ", enemy_layer, " (should be 2)")
		print("Enemy collision_mask: ", enemy_mask, " (should be 7)")

		# Verify enemy can detect player (layer 1), enemies (layer 2), and obstacles (layer 3)
		var detects_player = (enemy_mask & 1) != 0
		var detects_enemies = (enemy_mask & 2) != 0
		var detects_obstacles = (enemy_mask & 4) != 0
		print("  - Detects player (layer 1): ", detects_player)
		print("  - Detects other enemies (layer 2): ", detects_enemies)
		print("  - Detects obstacles (layer 3): ", detects_obstacles)

		if enemy_mask != 7:
			push_error("FAIL: Enemy collision_mask is not 7!")
		else:
			print("PASS: Enemy collision_mask is correct")

		# Check all enemies have consistent configuration
		var all_consistent = true
		for e in enemies:
			if e.collision_mask != 7 or e.collision_layer != 2:
				all_consistent = false
				push_error("FAIL: Enemy at ", e.global_position, " has incorrect collision config")

		if all_consistent:
			print("PASS: All ", enemies.size(), " enemies have consistent collision config")
	else:
		print("WARNING: No enemies found in scene")

	print()
	print("=== Manual Testing Required ===")
	print("1. Try walking through enemies - you should be blocked")
	print("2. Watch enemies move - they should not pass through each other")
	print("3. Verify player cannot push through enemy crowds")
	print("=====================================")
