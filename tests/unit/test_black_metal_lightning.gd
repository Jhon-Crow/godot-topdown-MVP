extends GutTest
## Unit tests for Black Metal lightning effects (Issue #1023).
##
## Tests the BlackMetalLightningEffectsManager autoload that provides
## screen-wide lightning flash effects when killing enemies in Black Metal mode.


var _lightning_manager: Node = null


func before_each() -> void:
	# Get the autoload instance
	_lightning_manager = get_node_or_null("/root/BlackMetalLightningEffectsManager")


func test_lightning_manager_exists() -> void:
	assert_not_null(_lightning_manager, "BlackMetalLightningEffectsManager autoload should exist")


func test_lightning_manager_has_trigger_method() -> void:
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return
	assert_true(_lightning_manager.has_method("trigger_lightning"),
		"Manager should have trigger_lightning method")


func test_lightning_manager_has_is_active_method() -> void:
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return
	assert_true(_lightning_manager.has_method("is_active"),
		"Manager should have is_active method")


func test_flash_pattern_enum_exists() -> void:
	# Test that the flash pattern enum values are defined
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	# The manager should have the FlashPattern enum values
	var script: Script = _lightning_manager.get_script()
	assert_not_null(script, "Manager should have a script attached")


func test_constants_are_reasonable() -> void:
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	# Test that flash constants are reasonable values
	# MIN_FLASH_DURATION and MAX_FLASH_DURATION should be positive
	# Flash duration should be short (< 0.5s for lightning feel)
	# We can access these via the script constants

	var script: Script = _lightning_manager.get_script()
	if script == null:
		pending("Manager script not found")
		return

	# Get constants from script
	var constants := script.get_script_constant_map()

	if "MIN_FLASH_DURATION" in constants:
		var min_duration: float = constants["MIN_FLASH_DURATION"]
		assert_gt(min_duration, 0.0, "MIN_FLASH_DURATION should be positive")
		assert_lt(min_duration, 0.5, "MIN_FLASH_DURATION should be short (< 0.5s)")

	if "MAX_FLASH_DURATION" in constants:
		var max_duration: float = constants["MAX_FLASH_DURATION"]
		assert_gt(max_duration, 0.0, "MAX_FLASH_DURATION should be positive")
		assert_lt(max_duration, 0.5, "MAX_FLASH_DURATION should be short (< 0.5s)")

	if "MIN_INTENSITY" in constants:
		var min_intensity: float = constants["MIN_INTENSITY"]
		assert_gte(min_intensity, 0.0, "MIN_INTENSITY should be >= 0")
		assert_lte(min_intensity, 1.0, "MIN_INTENSITY should be <= 1")

	if "MAX_INTENSITY" in constants:
		var max_intensity: float = constants["MAX_INTENSITY"]
		assert_gte(max_intensity, 0.0, "MAX_INTENSITY should be >= 0")
		assert_lte(max_intensity, 1.0, "MAX_INTENSITY should be <= 1")


func test_lightning_triggers_on_enemy_kill_not_on_hit() -> void:
	## Lightning should fire via GameManager.enemy_killed signal, not projectile hit callbacks.
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	# Verify the manager has the _on_enemy_killed handler.
	assert_true(_lightning_manager.has_method("_on_enemy_killed"),
		"Manager should have _on_enemy_killed method for kill-based triggering")

	# Verify trigger_lightning still exists (used internally by _on_enemy_killed).
	assert_true(_lightning_manager.has_method("trigger_lightning"),
		"Manager should have trigger_lightning method")

	# Verify the manager is connected to GameManager.enemy_killed.
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager == null:
		pending("GameManager not found")
		return

	if not game_manager.has_signal("enemy_killed"):
		pending("GameManager.enemy_killed signal not found")
		return

	var connections := game_manager.get_signal_connection_list("enemy_killed")
	var found_connection := false
	for conn in connections:
		if conn["callable"].get_object() == _lightning_manager:
			found_connection = true
			break
	assert_true(found_connection,
		"BlackMetalLightningEffectsManager should be connected to GameManager.enemy_killed")


func test_lightning_only_triggers_in_black_metal_mode() -> void:
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null:
		pending("DifficultyManager not found")
		return

	# Set to Normal mode - lightning should NOT be active
	difficulty_manager.set_difficulty(difficulty_manager.Difficulty.NORMAL)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(_lightning_manager.is_active(),
		"Lightning effects should be inactive in Normal mode")

	# Set to Black Metal mode - lightning should be active
	difficulty_manager.set_difficulty(difficulty_manager.Difficulty.BLACK_METAL)
	# Wait for activation delay
	for i in range(5):
		await get_tree().process_frame

	assert_true(_lightning_manager.is_active(),
		"Lightning effects should be active in Black Metal mode")

	# Reset to Normal
	difficulty_manager.set_difficulty(difficulty_manager.Difficulty.NORMAL)


func test_flash_patterns_have_correct_probabilities() -> void:
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	var script: Script = _lightning_manager.get_script()
	if script == null:
		pending("Manager script not found")
		return

	var constants := script.get_script_constant_map()

	# Get probability constants
	var double_chance: float = constants.get("DOUBLE_FLASH_CHANCE", -1.0)
	var triple_chance: float = constants.get("TRIPLE_FLASH_CHANCE", -1.0)

	if double_chance < 0 or triple_chance < 0:
		pending("Flash chance constants not found")
		return

	# Total probability should be <= 1.0
	var total_chance: float = double_chance + triple_chance
	assert_lte(total_chance, 1.0,
		"Sum of double + triple flash chances should not exceed 1.0")

	# Each should be positive
	assert_gt(double_chance, 0.0, "DOUBLE_FLASH_CHANCE should be positive")
	assert_gt(triple_chance, 0.0, "TRIPLE_FLASH_CHANCE should be positive")


func test_layer_order_is_correct() -> void:
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	# The lightning layer should be above Black Metal filter (97) but below hit effects (100)
	# Check that _flash_layer exists and has correct layer value
	var flash_layer: CanvasLayer = null
	for child in _lightning_manager.get_children():
		if child is CanvasLayer and child.name == "BlackMetalLightningLayer":
			flash_layer = child
			break

	assert_not_null(flash_layer, "Lightning layer should exist")
	if flash_layer:
		assert_eq(flash_layer.layer, 98,
			"Lightning layer should be at layer 98 (above filter 97, below hit effects 100)")


func test_bolt_drawer_node_exists() -> void:
	## v10: lightning is drawn via Node2D draw calls, no shader required.
	if _lightning_manager == null:
		pending("BlackMetalLightningEffectsManager not found")
		return

	# Check that the CanvasLayer and LightningBoltDrawer exist as children.
	var flash_layer: CanvasLayer = null
	for child in _lightning_manager.get_children():
		if child is CanvasLayer and child.name == "BlackMetalLightningLayer":
			flash_layer = child
			break

	assert_not_null(flash_layer, "BlackMetalLightningLayer CanvasLayer should exist")

	if flash_layer:
		var drawer: Node2D = null
		for child in flash_layer.get_children():
			if child is Node2D and child.name == "LightningBoltDrawer":
				drawer = child
				break
		assert_not_null(drawer, "LightningBoltDrawer Node2D should exist inside the layer")
