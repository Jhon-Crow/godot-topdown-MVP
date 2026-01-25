extends Node
## LastChanceEffectsManager - Special "last chance" effect for hard difficulty.
##
## This autoload singleton manages the special time-freeze effect that triggers
## on hard difficulty when the player is about to die (1 HP or less) and an
## enemy bullet on a collision course enters their threat sphere.
##
## Effect details (as per issue #167):
## 1. Time completely stops for 6 real seconds
## 2. Player can move at normal speed and shoot during the freeze
## 3. Player-fired bullets stay frozen in place until time unfreezes
## 4. All colors except the player are dimmed
## 5. Blue sepia effect overlay with a ripple effect
## 6. This effect triggers ONLY ONCE per life

## Duration of the time freeze in real seconds.
const FREEZE_DURATION_REAL_SECONDS: float = 6.0

## Blue sepia intensity for the shader (0.0-1.0).
const SEPIA_INTENSITY: float = 0.7

## Brightness reduction for non-player elements (0.0-1.0, where 1.0 is normal).
const BRIGHTNESS: float = 0.6

## Ripple effect strength.
const RIPPLE_STRENGTH: float = 0.008

## Ripple effect frequency.
const RIPPLE_FREQUENCY: float = 25.0

## Ripple effect speed.
const RIPPLE_SPEED: float = 2.0

## Player saturation multiplier during last chance (same as enemy saturation).
## Makes the player more vivid and visible during the effect.
const PLAYER_SATURATION_MULTIPLIER: float = 4.0

## The CanvasLayer for screen effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the last chance shader.
var _effect_rect: ColorRect = null

## Whether the last chance effect is currently active.
var _is_effect_active: bool = false

## Whether the last chance effect has already been used this life.
## Only triggers ONCE.
var _effect_used: bool = false

## Reference to the player for monitoring.
var _player: Node = null

## Reference to the player's ThreatSphere for signal connection.
var _threat_sphere: Area2D = null

## Whether we've successfully connected to player signals.
var _connected_to_player: bool = false

## Timer for tracking effect duration (uses real time, not game time).
var _effect_start_time: float = 0.0

## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null

## List of bullets frozen by the player during time freeze.
var _frozen_player_bullets: Array = []

## List of grenades frozen during time freeze.
var _frozen_grenades: Array = []

## List of bullet casings frozen during time freeze.
var _frozen_casings: Array = []

## Original process mode of the player (to restore after effect).
var _player_original_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT

## Dictionary storing original process modes of all nodes we modified.
## Key: node instance, Value: original ProcessMode
var _original_process_modes: Dictionary = {}

## Distance to push threatening bullets away from player (in pixels).
const BULLET_PUSH_DISTANCE: float = 200.0

## Whether to grant invulnerability during the time freeze.
var _player_was_invulnerable: bool = false

## Cached player health from Damaged/health_changed signals.
## This is used because accessing C# HealthComponent.CurrentHealth from GDScript
## doesn't work reliably due to cross-language interoperability issues.
var _player_current_health: float = 0.0

## Original player sprite modulate colors (to restore after effect ends).
## Key: sprite node, Value: original modulate Color
var _player_original_colors: Dictionary = {}


func _ready() -> void:
	# Connect to scene tree changes to find player and reset effects on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (very high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "LastChanceEffectsLayer"
	_effects_layer.layer = 102  # Higher than other effects layers
	add_child(_effects_layer)

	# Create effect overlay
	_effect_rect = ColorRect.new()
	_effect_rect.name = "LastChanceOverlay"
	_effect_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the last chance shader
	var shader := load("res://scripts/shaders/last_chance.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("sepia_intensity", 0.0)
		material.set_shader_parameter("brightness", 1.0)
		material.set_shader_parameter("ripple_strength", 0.0)
		material.set_shader_parameter("ripple_frequency", RIPPLE_FREQUENCY)
		material.set_shader_parameter("ripple_speed", RIPPLE_SPEED)
		material.set_shader_parameter("time_offset", 0.0)
		_effect_rect.material = material
		_log("Last chance shader loaded successfully")
	else:
		push_warning("LastChanceEffectsManager: Could not load last chance shader")
		_log("WARNING: Could not load last chance shader!")

	_effect_rect.visible = false
	_effects_layer.add_child(_effect_rect)

	# Perform shader warmup to prevent first-use lag (Issue #343)
	_warmup_shader()

	_log("LastChanceEffectsManager ready - Configuration:")
	_log("  Freeze duration: %.1f real seconds" % FREEZE_DURATION_REAL_SECONDS)
	_log("  Sepia intensity: %.2f" % SEPIA_INTENSITY)
	_log("  Brightness: %.2f" % BRIGHTNESS)


func _process(delta: float) -> void:
	# Check if we need to find the player
	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Update shader time for ripple animation (using real time)
	if _is_effect_active:
		var current_time := Time.get_ticks_msec() / 1000.0
		var elapsed := current_time - _effect_start_time

		# Update ripple time offset in shader
		var material := _effect_rect.material as ShaderMaterial
		if material:
			material.set_shader_parameter("time_offset", elapsed)

		# Check if effect should end based on real time duration
		if elapsed >= FREEZE_DURATION_REAL_SECONDS:
			_log("Effect duration expired after %.2f real seconds" % elapsed)
			_end_last_chance_effect()


## Log a message with the LastChance prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[LastChance] " + message)
	else:
		print("[LastChance] " + message)


## Find and connect to the player and their threat sphere.
func _find_player() -> void:
	# Skip if already connected
	if _connected_to_player and is_instance_valid(_player):
		return

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	_log("Found player: %s" % _player.name)

	# Find threat sphere on player
	_threat_sphere = _player.get_node_or_null("ThreatSphere") as Area2D
	if _threat_sphere == null:
		_log("WARNING: No ThreatSphere found on player - last chance effect won't work")
		return

	# Connect to threat sphere signal
	if _threat_sphere.has_signal("threat_detected"):
		if not _threat_sphere.threat_detected.is_connected(_on_threat_detected):
			_threat_sphere.threat_detected.connect(_on_threat_detected)
			_log("Connected to ThreatSphere threat_detected signal")

	# Connect to player health signals to track when HP is low
	if _player.has_signal("Damaged"):
		if not _player.Damaged.is_connected(_on_player_damaged):
			_player.Damaged.connect(_on_player_damaged)
			_log("Connected to player Damaged signal (C#)")

	if _player.has_signal("health_changed"):
		if not _player.health_changed.is_connected(_on_player_health_changed):
			_player.health_changed.connect(_on_player_health_changed)
			_log("Connected to player health_changed signal (GDScript)")

	# Connect to died signal to reset effect availability on death
	if _player.has_signal("Died"):
		if not _player.Died.is_connected(_on_player_died):
			_player.Died.connect(_on_player_died)
			_log("Connected to player Died signal (C#)")

	if _player.has_signal("died"):
		if not _player.died.is_connected(_on_player_died):
			_player.died.connect(_on_player_died)
			_log("Connected to player died signal (GDScript)")

	# Try to get initial health from C# HealthComponent
	# This may not work reliably due to cross-language interop issues,
	# but we try anyway to have a starting value
	var health_component: Node = _player.get_node_or_null("HealthComponent")
	if health_component != null and health_component.has_signal("HealthChanged"):
		# Connect to HealthChanged signal to get health updates including initial value
		if not health_component.HealthChanged.is_connected(_on_health_changed):
			health_component.HealthChanged.connect(_on_health_changed)
			_log("Connected to HealthComponent HealthChanged signal (C#)")

	_connected_to_player = true


## Called when player health changes (GDScript).
func _on_player_health_changed(current: int, _maximum: int) -> void:
	# Cache the current health from the signal for reliable cross-language access
	_player_current_health = float(current)
	_log("Player health updated (GDScript): %.1f" % _player_current_health)


## Called when player takes damage (C#).
func _on_player_damaged(_amount: float, current_health: float) -> void:
	# Cache the current health from the signal for reliable cross-language access
	_player_current_health = current_health
	_log("Player health updated (C# Damaged): %.1f" % _player_current_health)


## Called when health changes on C# HealthComponent (includes initial value).
func _on_health_changed(current_health: float, _max_health: float) -> void:
	# Cache the current health from the signal for reliable cross-language access
	_player_current_health = current_health
	_log("Player health updated (C# HealthChanged): %.1f" % _player_current_health)


## Called when player dies.
func _on_player_died() -> void:
	_log("Player died")
	if _is_effect_active:
		_end_last_chance_effect()
	# Reset effect usage on death so it can trigger again next life
	_effect_used = false


## Called when a threat is detected by the player's threat sphere.
func _on_threat_detected(bullet: Area2D) -> void:
	_log("Threat detected: %s" % bullet.name)

	# Check if we can trigger the effect
	if not _can_trigger_effect():
		_log("Cannot trigger effect - conditions not met")
		return

	_log("Triggering last chance effect!")
	_start_last_chance_effect()


## Checks if the last chance effect can be triggered.
func _can_trigger_effect() -> bool:
	# Effect already used this life?
	if _effect_used:
		_log("Effect already used this life")
		return false

	# Effect already active?
	if _is_effect_active:
		_log("Effect already active")
		return false

	# Only trigger in hard mode
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null:
		_log("DifficultyManager not found")
		return false

	if not difficulty_manager.is_hard_mode():
		_log("Not in hard mode - effect disabled")
		return false

	# Check player health (1 HP or less)
	if _player == null:
		_log("Player not found")
		return false

	# Use cached health value from Damaged/health_changed signals
	# This is more reliable than trying to access C# HealthComponent properties from GDScript
	if _player_current_health > 1.0 or _player_current_health <= 0.0:
		_log("Player health is %.1f - effect requires exactly 1 HP or less but alive" % _player_current_health)
		return false

	return true


## Gets the player's current health.
func _get_player_health() -> float:
	if _player == null:
		return 0.0

	# Try C# player (has HealthComponent)
	var health_component: Node = _player.get_node_or_null("HealthComponent")
	if health_component != null:
		if health_component.has_method("get") and health_component.get("CurrentHealth") != null:
			return health_component.get("CurrentHealth")
		if "CurrentHealth" in health_component:
			return health_component.CurrentHealth

	# Try GDScript player
	if _player.has_method("get_health"):
		return _player.get_health()

	# Try health property
	if "health" in _player:
		return _player.health

	# Try current_health property
	if "current_health" in _player:
		return _player.current_health

	return 0.0


## Starts the last chance effect.
func _start_last_chance_effect() -> void:
	if _is_effect_active:
		return

	_is_effect_active = true
	_effect_used = true  # Mark as used (only triggers once)
	_effect_start_time = Time.get_ticks_msec() / 1000.0

	_log("Starting last chance effect:")
	_log("  - Time will be frozen (except player)")
	_log("  - Duration: %.1f real seconds" % FREEZE_DURATION_REAL_SECONDS)
	_log("  - Sepia intensity: %.2f" % SEPIA_INTENSITY)
	_log("  - Brightness: %.2f" % BRIGHTNESS)

	# CRITICAL: Push all threatening bullets away from player BEFORE freezing time
	# This gives the player a fighting chance to survive
	_push_threatening_bullets_away()

	# Grant temporary invulnerability to player during time freeze
	_grant_player_invulnerability()

	# Freeze time for everything except the player
	_freeze_time()

	# Apply visual effects
	_apply_visual_effects()


## Freezes time for everything except the player.
## IMPORTANT: We don't use Engine.time_scale = 0 because it also freezes physics delta,
## which prevents CharacterBody2D.MoveAndSlide() from working even with PROCESS_MODE_ALWAYS.
## Instead, we disable processing on all nodes except the player and this manager.
func _freeze_time() -> void:
	# Clear previous stored modes
	_original_process_modes.clear()

	# CRITICAL: Do NOT set Engine.time_scale to 0!
	# Physics delta becomes 0 which makes MoveAndSlide() not work.
	# Instead, we disable all nodes except player.

	# CRITICAL FIX: First, set player and all children to PROCESS_MODE_ALWAYS
	# This MUST happen BEFORE freezing the scene, because:
	# 1. The player's parent (scene root) will be set to DISABLED
	# 2. By default, player has INHERIT, which would inherit DISABLED
	# 3. Setting to ALWAYS overrides the parent's disabled state
	if _player != null:
		_enable_player_processing_always(_player)

	# Freeze all top-level nodes in the scene tree except player and autoloads
	var root := get_tree().root
	for child in root.get_children():
		# Skip autoloads (they should keep running for UI, audio, etc.)
		# Include GameManager to preserve quick restart (Q key) functionality
		if child.name in ["FileLogger", "AudioManager", "DifficultyManager", "LastChanceEffectsManager", "PenultimateHitEffectsManager", "GameManager"]:
			continue

		# This is likely the current scene - freeze everything inside except player
		_freeze_node_except_player(child)

	_log("Froze all nodes except player and autoloads (including GameManager for quick restart)")

	# This manager uses PROCESS_MODE_ALWAYS to keep running the timer
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect to node_added signal to freeze any new bullets fired during the freeze
	# This ensures player-fired bullets also get frozen immediately
	if not get_tree().node_added.is_connected(_on_node_added_during_freeze):
		get_tree().node_added.connect(_on_node_added_during_freeze)


## Recursively sets the player and all children to PROCESS_MODE_ALWAYS.
## This is needed because the player's parent scene will be DISABLED,
## and we need ALWAYS mode to override the inherited disabled state.
func _enable_player_processing_always(node: Node, depth: int = 0) -> void:
	if node == null or not is_instance_valid(node):
		return

	# Store original process mode for restoration later
	_original_process_modes[node] = node.process_mode

	# Set to ALWAYS so player can move even when parent scene is DISABLED
	node.process_mode = Node.PROCESS_MODE_ALWAYS

	# Only log the player node itself and important children to avoid spam
	if depth == 0:
		_log("Set player %s and all %d children to PROCESS_MODE_ALWAYS" % [node.name, _count_descendants(node)])

	# Recursively enable all children too (weapon, input, animations, etc.)
	for child in node.get_children():
		_enable_player_processing_always(child, depth + 1)


## Counts total number of descendant nodes.
func _count_descendants(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		count += 1 + _count_descendants(child)
	return count


## Recursively freezes a node and its children, except for the player node.
## Uses a selective approach that only disables nodes that need to be frozen,
## preserving physics collision by NOT setting container nodes or physics bodies to DISABLED.
func _freeze_node_except_player(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return

	# Skip the player and all its children - they should keep processing normally
	if node == _player:
		_log("Skipping player node: %s" % node.name)
		return

	# Also skip if this node is a child of player (already handled)
	if _player != null and _is_descendant_of(_player, node):
		return

	# CRITICAL FIX: Only freeze nodes that actually need freezing.
	# DO NOT freeze container nodes (Node2D, Node, Control) that have physics bodies as children.
	# The issue is that setting parent containers to DISABLED affects physics collision detection
	# even if we set the physics bodies themselves to ALWAYS.
	#
	# Strategy:
	# 1. StaticBody2D (walls) - set to ALWAYS to ensure collision detection works
	# 2. CollisionShape2D - set to ALWAYS to ensure collision shapes are active
	# 3. CharacterBody2D (enemies) - DISABLE to freeze them
	# 4. RigidBody2D (physics objects) - DISABLE if they have enemy-like behavior
	# 5. Container nodes (Node2D, Node, etc.) - DON'T disable, just process children
	#    This is key: leaving containers at INHERIT preserves the physics tree structure

	# Handle physics collision bodies - set to ALWAYS to preserve collision detection
	if node is StaticBody2D:
		_original_process_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
		_log("Set StaticBody2D '%s' to PROCESS_MODE_ALWAYS for collision" % node.name)
		# Process children - collision shapes need ALWAYS too
		for child in node.get_children():
			_freeze_node_except_player(child)
		return

	# CollisionShape2D nodes need ALWAYS to stay active for collision detection
	if node is CollisionShape2D:
		_original_process_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
		return

	# Freeze CharacterBody2D nodes that are NOT the player (enemies)
	if node is CharacterBody2D:
		_original_process_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED
		# Freeze all children of enemy character bodies
		for child in node.get_children():
			_freeze_node_except_player(child)
		return

	# Freeze RigidBody2D nodes (physics objects like grenades and casings)
	if node is RigidBody2D:
		_original_process_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED

		# Check if this is a grenade and track it separately for proper unfreezing
		var script: Script = node.get_script()
		if script != null:
			var script_path: String = script.resource_path
			if "grenade" in script_path.to_lower():
				if node not in _frozen_grenades:
					_frozen_grenades.append(node)
					_log("Froze existing grenade: %s" % node.name)
			# Check if this is a bullet casing and track it separately
			elif "casing" in script_path.to_lower():
				if node not in _frozen_casings:
					_frozen_casings.append(node)
					# Call freeze_time method on casing if available
					if node.has_method("freeze_time"):
						node.freeze_time()
					_log("Froze existing bullet casing: %s" % node.name)

		for child in node.get_children():
			_freeze_node_except_player(child)
		return

	# Freeze Area2D nodes (triggers, hit areas, bullets, etc.)
	if node is Area2D:
		_original_process_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED
		for child in node.get_children():
			_freeze_node_except_player(child)
		return

	# For container nodes (Node2D, Node, Control, etc.), DON'T set to DISABLED
	# Just recurse into children to find actual freezable nodes
	# This preserves the physics tree structure and allows collision detection to work
	for child in node.get_children():
		_freeze_node_except_player(child)


## Checks if 'node' is a descendant of 'ancestor'.
func _is_descendant_of(ancestor: Node, node: Node) -> bool:
	if ancestor == null or node == null:
		return false

	var parent := node.get_parent()
	while parent != null:
		if parent == ancestor:
			return true
		parent = parent.get_parent()

	return false




## Applies the visual effects (blue sepia + ripple + arm saturation).
func _apply_visual_effects() -> void:
	_effect_rect.visible = true
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("sepia_intensity", SEPIA_INTENSITY)
		material.set_shader_parameter("brightness", BRIGHTNESS)
		material.set_shader_parameter("ripple_strength", RIPPLE_STRENGTH)
		material.set_shader_parameter("time_offset", 0.0)
		_log("Applied visual effects: sepia=%.2f, brightness=%.2f, ripple=%.4f" % [SEPIA_INTENSITY, BRIGHTNESS, RIPPLE_STRENGTH])

	# Apply saturation boost to player's sprites (makes player more visible)
	_apply_player_saturation()


## Ends the last chance effect.
func _end_last_chance_effect() -> void:
	if not _is_effect_active:
		return

	_is_effect_active = false
	_log("Ending last chance effect")

	# CRITICAL: Reset enemy memory BEFORE unfreezing time (Issue #318)
	# This ensures enemies forget the player's position during the freeze,
	# treating the player's movement as a "teleport" they couldn't see
	_reset_all_enemy_memory()

	# Restore normal time
	_unfreeze_time()

	# Remove visual effects
	_remove_visual_effects()


## Unfreezes time and restores normal processing.
func _unfreeze_time() -> void:
	# Disconnect the node_added signal we connected during freeze
	if get_tree().node_added.is_connected(_on_node_added_during_freeze):
		get_tree().node_added.disconnect(_on_node_added_during_freeze)

	# Restore all nodes' original process modes
	_restore_all_process_modes()

	# Restore this manager's process mode
	process_mode = Node.PROCESS_MODE_INHERIT

	# Remove player invulnerability
	_remove_player_invulnerability()

	# Unfreeze any player bullets that were fired during the time freeze
	_unfreeze_player_bullets()

	# Unfreeze any grenades that were created during the time freeze
	_unfreeze_grenades()

	# Unfreeze any bullet casings that were frozen during the time freeze
	_unfreeze_casings()


## Restores all stored original process modes.
func _restore_all_process_modes() -> void:
	for node in _original_process_modes.keys():
		if is_instance_valid(node):
			node.process_mode = _original_process_modes[node]

	_original_process_modes.clear()
	_log("All process modes restored")


## Removes the visual effects.
func _remove_visual_effects() -> void:
	_effect_rect.visible = false
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("sepia_intensity", 0.0)
		material.set_shader_parameter("brightness", 1.0)
		material.set_shader_parameter("ripple_strength", 0.0)

	# Restore original player sprite colors
	_restore_player_colors()


## Applies saturation boost to all player sprites (visibility during effect).
## This makes the entire player more vivid during the last chance effect.
func _apply_player_saturation() -> void:
	if _player == null:
		return

	_player_original_colors.clear()

	# Find all player sprites in PlayerModel
	var player_model := _player.get_node_or_null("PlayerModel") as Node2D
	if player_model == null:
		_log("WARNING: PlayerModel not found on player")
		return

	# Apply saturation to all direct sprite children (Body, Head, LeftArm, RightArm)
	var sprites_saturated: int = 0
	for child in player_model.get_children():
		if child is Sprite2D:
			_player_original_colors[child] = child.modulate
			child.modulate = _saturate_color(child.modulate, PLAYER_SATURATION_MULTIPLIER)
			sprites_saturated += 1

	# Also apply saturation to armband (sibling of RightArm, not child - to avoid inheriting health modulate)
	var armband := player_model.get_node_or_null("Armband") as Sprite2D
	if armband:
		_player_original_colors[armband] = armband.modulate
		armband.modulate = _saturate_color(armband.modulate, PLAYER_SATURATION_MULTIPLIER)
		sprites_saturated += 1

	_log("Applied %.1fx saturation to %d player sprites" % [PLAYER_SATURATION_MULTIPLIER, sprites_saturated])


## Restores original colors to player's sprites.
## After restoring, tells the player to refresh their health visual to ensure
## the correct health-based coloring is applied (not the stale stored colors).
func _restore_player_colors() -> void:
	for sprite in _player_original_colors.keys():
		if is_instance_valid(sprite):
			sprite.modulate = _player_original_colors[sprite]

	if _player_original_colors.size() > 0:
		_log("Restored original colors to %d player sprites" % _player_original_colors.size())

	_player_original_colors.clear()

	# Tell the player to refresh their health visual to apply correct colors
	# This is needed because the stored colors might be stale (captured at a different
	# health level or during a previous effect state)
	if _player != null and is_instance_valid(_player):
		# Try C# player method (RefreshHealthVisual)
		if _player.has_method("RefreshHealthVisual"):
			_player.RefreshHealthVisual()
			_log("Called player RefreshHealthVisual (C#)")
		# Try GDScript player method (refresh_health_visual)
		elif _player.has_method("refresh_health_visual"):
			_player.refresh_health_visual()
			_log("Called player refresh_health_visual (GDScript)")


## Increase saturation of a color by a multiplier.
## Uses standard luminance-based saturation algorithm.
func _saturate_color(color: Color, multiplier: float) -> Color:
	# Calculate luminance using standard weights
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114

	# Increase saturation by moving away from grayscale
	var saturated_r: float = lerp(luminance, color.r, multiplier)
	var saturated_g: float = lerp(luminance, color.g, multiplier)
	var saturated_b: float = lerp(luminance, color.b, multiplier)

	# Clamp to valid color range
	return Color(
		clampf(saturated_r, 0.0, 1.0),
		clampf(saturated_g, 0.0, 1.0),
		clampf(saturated_b, 0.0, 1.0),
		color.a
	)


## Pushes all bullets that are close to the player away.
## This gives the player a fighting chance when time freezes.
func _push_threatening_bullets_away() -> void:
	if _player == null:
		return

	var player_pos: Vector2 = _player.global_position
	var bullets_pushed: int = 0

	# Get all bullets in the scene (they are Area2D nodes in the "bullets" group or have bullet script)
	var bullets: Array = get_tree().get_nodes_in_group("bullets")

	# Also search for Area2D nodes that might be bullets but not in the group
	for node in get_tree().get_nodes_in_group("enemies"):
		# Enemy projectiles might not be in bullets group
		pass

	# Search through all Area2D nodes
	for area in _get_all_bullets():
		if not is_instance_valid(area):
			continue

		var bullet_pos: Vector2 = area.global_position
		var distance: float = player_pos.distance_to(bullet_pos)

		# Only push bullets that are within the threat radius
		if distance < _threat_sphere.threat_radius if _threat_sphere else 200.0:
			# Calculate direction away from player
			var push_direction: Vector2 = (bullet_pos - player_pos).normalized()
			if push_direction == Vector2.ZERO:
				push_direction = Vector2.RIGHT  # Fallback direction

			# Push bullet away
			var new_pos: Vector2 = player_pos + push_direction * BULLET_PUSH_DISTANCE
			area.global_position = new_pos

			bullets_pushed += 1
			_log("Pushed bullet %s from distance %.1f to %.1f" % [area.name, distance, BULLET_PUSH_DISTANCE])

	if bullets_pushed > 0:
		_log("Pushed %d threatening bullets away from player" % bullets_pushed)


## Gets all bullet nodes in the scene.
func _get_all_bullets() -> Array:
	var bullets: Array = []

	# Check bullets group
	bullets.append_array(get_tree().get_nodes_in_group("bullets"))

	# Also find Area2D nodes that look like bullets
	for node in get_tree().get_root().get_children():
		_find_bullets_recursive(node, bullets)

	return bullets


## Recursively finds bullet and pellet nodes.
func _find_bullets_recursive(node: Node, bullets: Array) -> void:
	if node is Area2D:
		# Check if it's a bullet or pellet by script or name
		var script: Script = node.get_script()
		if script != null:
			var script_path: String = script.resource_path
			if "bullet" in script_path.to_lower() or "pellet" in script_path.to_lower():
				if node not in bullets:
					bullets.append(node)
		elif "Bullet" in node.name or "bullet" in node.name or "Pellet" in node.name or "pellet" in node.name:
			if node not in bullets:
				bullets.append(node)

	for child in node.get_children():
		_find_bullets_recursive(child, bullets)


## Grants temporary invulnerability to the player during time freeze.
func _grant_player_invulnerability() -> void:
	if _player == null:
		return

	# Try to access the health component and set invulnerability
	var health_component: Node = _player.get_node_or_null("HealthComponent")
	if health_component != null:
		# Try to set Invulnerable property (C# - exported property with Pascal case)
		if "Invulnerable" in health_component:
			_player_was_invulnerable = health_component.Invulnerable
			health_component.Invulnerable = true
			_log("Player granted temporary invulnerability (C# Invulnerable property)")
			return

		# Try to set is_invulnerable property (GDScript snake_case)
		if "is_invulnerable" in health_component:
			_player_was_invulnerable = health_component.is_invulnerable
			health_component.is_invulnerable = true
			_log("Player granted temporary invulnerability (GDScript property)")
			return

	# Fallback: try to access invulnerable property on player directly
	if "is_invulnerable" in _player:
		_player_was_invulnerable = _player.is_invulnerable
		_player.is_invulnerable = true
		_log("Player granted temporary invulnerability (on player)")


## Removes temporary invulnerability from the player.
func _remove_player_invulnerability() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var health_component: Node = _player.get_node_or_null("HealthComponent")
	if health_component != null:
		# Try to restore Invulnerable property (C#)
		if "Invulnerable" in health_component:
			health_component.Invulnerable = _player_was_invulnerable
			_log("Player invulnerability restored to %s (C# property)" % _player_was_invulnerable)
			return

		# Try to restore is_invulnerable property (GDScript)
		if "is_invulnerable" in health_component:
			health_component.is_invulnerable = _player_was_invulnerable
			_log("Player invulnerability restored to %s (GDScript property)" % _player_was_invulnerable)
			return

	# Fallback: try to restore on player directly
	if "is_invulnerable" in _player:
		_player.is_invulnerable = _player_was_invulnerable
		_log("Player invulnerability restored to %s (on player)" % _player_was_invulnerable)


## Registers a player bullet that was fired during time freeze.
## These bullets should stay frozen until time unfreezes.
func register_frozen_bullet(bullet: Node2D) -> void:
	if not _is_effect_active:
		return

	if bullet not in _frozen_player_bullets:
		_frozen_player_bullets.append(bullet)
		# Freeze the bullet's processing
		bullet.process_mode = Node.PROCESS_MODE_DISABLED
		_log("Registered frozen player bullet: %s" % bullet.name)


## Unfreezes all player bullets that were fired during time freeze.
func _unfreeze_player_bullets() -> void:
	for bullet in _frozen_player_bullets:
		if is_instance_valid(bullet):
			bullet.process_mode = Node.PROCESS_MODE_INHERIT
			_log("Unfroze player bullet: %s" % bullet.name)

	_frozen_player_bullets.clear()


## Freezes a grenade that was created during the time freeze.
## This stops both the grenade's timer and its physics movement.
func _freeze_grenade(grenade: RigidBody2D) -> void:
	if grenade in _frozen_grenades:
		return

	_frozen_grenades.append(grenade)

	# Store original process mode for restoration
	_original_process_modes[grenade] = grenade.process_mode

	# Disable processing to stop the timer countdown in _physics_process
	grenade.process_mode = Node.PROCESS_MODE_DISABLED

	# Also freeze the RigidBody2D physics to stop any movement
	if not grenade.freeze:
		grenade.freeze = true

	_log("Registered frozen grenade: %s" % grenade.name)


## Freezes a bullet casing that was created during the time freeze.
## This stops both the casing's auto-land timer and its physics movement.
func _freeze_casing(casing: RigidBody2D) -> void:
	if casing in _frozen_casings:
		return

	_frozen_casings.append(casing)

	# Store original process mode for restoration
	_original_process_modes[casing] = casing.process_mode

	# Disable processing to stop the auto-land timer in _physics_process
	casing.process_mode = Node.PROCESS_MODE_DISABLED

	# Call freeze_time method on casing to stop movement
	if casing.has_method("freeze_time"):
		casing.freeze_time()

	_log("Registered frozen bullet casing: %s" % casing.name)


## Unfreezes all grenades that were created during time freeze.
func _unfreeze_grenades() -> void:
	for grenade in _frozen_grenades:
		if is_instance_valid(grenade):
			# Restore process mode to allow timer to continue
			if grenade in _original_process_modes:
				grenade.process_mode = _original_process_modes[grenade]
			else:
				grenade.process_mode = Node.PROCESS_MODE_INHERIT

			# Note: Don't unfreeze physics here - the grenade's throw_grenade() method
			# will handle unfreezing when the player actually throws it
			# If it was already thrown before the freeze, it will continue moving
			_log("Unfroze grenade: %s" % grenade.name)

	_frozen_grenades.clear()


## Unfreezes all bullet casings that were frozen during time freeze.
func _unfreeze_casings() -> void:
	for casing in _frozen_casings:
		if is_instance_valid(casing):
			# Restore process mode to allow casing to continue falling/landing
			if casing in _original_process_modes:
				casing.process_mode = _original_process_modes[casing]
			else:
				casing.process_mode = Node.PROCESS_MODE_INHERIT

			# Call unfreeze_time method on casing to restore velocities
			if casing.has_method("unfreeze_time"):
				casing.unfreeze_time()

			_log("Unfroze bullet casing: %s" % casing.name)

	_frozen_casings.clear()


## Resets memory for all enemies when the last chance effect ends (Issue #318).
## This ensures enemies don't know where the player moved during the time freeze,
## treating the player's movement as a "teleport" they couldn't observe.
## Enemies must re-acquire the player through visual contact or sound detection.
func _reset_all_enemy_memory() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var reset_count := 0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Call the reset_memory method on each enemy that has it
		if enemy.has_method("reset_memory"):
			enemy.reset_memory()
			reset_count += 1

	if reset_count > 0:
		_log("Reset memory for %d enemies (player teleport effect)" % reset_count)


## Called when a node is added to the scene tree during time freeze.
## Automatically freezes player-fired bullets and grenades to maintain the time freeze effect.
func _on_node_added_during_freeze(node: Node) -> void:
	if not _is_effect_active:
		return

	# Check if this is a grenade or casing (RigidBody2D with grenade/casing script)
	if node is RigidBody2D:
		var script: Script = node.get_script()
		if script != null:
			var script_path: String = script.resource_path
			if "grenade" in script_path.to_lower():
				# This is a grenade - freeze it immediately
				_log("Freezing newly created grenade: %s" % node.name)
				_freeze_grenade(node as RigidBody2D)
				return
			elif "casing" in script_path.to_lower():
				# This is a bullet casing - freeze it immediately
				_log("Freezing newly created bullet casing: %s" % node.name)
				_freeze_casing(node as RigidBody2D)
				return

	# Check if this is a bullet (Area2D with bullet script or name)
	if not node is Area2D:
		return

	# Check if it's a bullet or pellet by script path or name
	var is_bullet: bool = false
	var script: Script = node.get_script()
	if script != null:
		var script_path: String = script.resource_path
		if "bullet" in script_path.to_lower() or "pellet" in script_path.to_lower():
			is_bullet = true
	elif "Bullet" in node.name or "bullet" in node.name or "Pellet" in node.name or "pellet" in node.name:
		is_bullet = true

	if not is_bullet:
		return

	# Check if this is a player bullet (shot by the player)
	# Player bullets have shooter_id matching the player's instance ID
	var shooter_id: int = -1
	if "shooter_id" in node:
		shooter_id = node.shooter_id
	elif "ShooterId" in node:
		shooter_id = node.ShooterId

	if shooter_id == -1:
		return

	# Check if the shooter is the player
	if _player != null and shooter_id == _player.get_instance_id():
		# This is a player bullet - freeze it immediately
		_log("Freezing newly fired player bullet: %s" % node.name)
		register_frozen_bullet(node as Node2D)


## Resets all effects (useful when restarting the scene).
func reset_effects() -> void:
	_log("Resetting all effects (scene change detected)")

	# Disconnect node_added signal if connected
	if get_tree().node_added.is_connected(_on_node_added_during_freeze):
		get_tree().node_added.disconnect(_on_node_added_during_freeze)

	if _is_effect_active:
		_end_last_chance_effect()
	_player = null
	_threat_sphere = null
	_connected_to_player = false
	_effect_used = false  # Reset on scene change
	_player_current_health = 0.0  # Reset cached health on scene change
	_frozen_player_bullets.clear()
	_frozen_grenades.clear()
	_frozen_casings.clear()
	_original_process_modes.clear()
	_player_original_colors.clear()
	_player_was_invulnerable = false


## Called when the scene tree structure changes.
## Used to reset effects when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		reset_effects()


## Performs warmup to pre-compile the last chance shader.
## This prevents a shader compilation stutter on first use (Issue #343).
func _warmup_shader() -> void:
	if _effect_rect == null or _effect_rect.material == null:
		return

	_log("Starting shader warmup (Issue #343 fix)...")
	var start_time := Time.get_ticks_msec()

	# Briefly enable the effect rect with zero visual effect
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("sepia_intensity", 0.0)
		material.set_shader_parameter("brightness", 1.0)
		material.set_shader_parameter("ripple_strength", 0.0)

	_effect_rect.visible = true

	# Wait one frame to ensure GPU processes and compiles the shader
	await get_tree().process_frame

	# Hide the overlay again
	_effect_rect.visible = false

	var elapsed := Time.get_ticks_msec() - start_time
	_log("Shader warmup complete in %d ms" % elapsed)


## Returns whether the last chance effect is currently active.
func is_effect_active() -> bool:
	return _is_effect_active


## Returns whether the last chance effect has been used this life.
func is_effect_used() -> bool:
	return _effect_used
