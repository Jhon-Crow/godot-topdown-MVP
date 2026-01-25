class_name RagdollManagerAutoload
extends Node
## Manager for persistent ragdoll bodies that survive scene reloads.
##
## This autoload keeps ragdoll bodies (dead enemy corpses) alive across scene changes.
## When a scene reloads (e.g., player death and restart), ragdoll bodies would normally
## be destroyed. By reparenting them to this persistent autoload, they survive.
##
## Features:
## - Ragdoll bodies persist across scene reloads
## - Automatic cleanup of old bodies to prevent memory leaks
## - Position tracking for ragdoll re-placement after scene reload
## - Configurable maximum body count and cleanup settings

## Maximum number of persistent ragdoll bodies to keep.
## When exceeded, oldest bodies are removed.
@export var max_persistent_bodies: int = 50

## Whether to persist bodies across scene changes.
## Set to false to disable persistence (bodies will be destroyed on scene reload).
@export var persist_bodies: bool = true

## Container node for persistent ragdoll bodies.
var _ragdoll_container: Node2D = null

## List of all managed ragdoll body groups (each group = one dead enemy).
## Format: Array of { "bodies": Array[RigidBody2D], "joints": Array[PinJoint2D], "timestamp": float }
var _ragdoll_groups: Array[Dictionary] = []

## Current level scene path (used to detect scene changes).
var _current_scene_path: String = ""

## Signal emitted when a ragdoll group is added.
signal ragdoll_group_added(group_index: int)

## Signal emitted when a ragdoll group is removed.
signal ragdoll_group_removed(group_index: int)

## Signal emitted on scene change (for debugging/logging).
signal scene_changed(old_scene: String, new_scene: String)


func _ready() -> void:
	_create_ragdoll_container()

	# Connect to scene tree signals to detect scene changes
	get_tree().tree_changed.connect(_on_tree_changed)

	_log("RagdollManager initialized - persist_bodies: %s, max_bodies: %d" % [persist_bodies, max_persistent_bodies])


func _process(_delta: float) -> void:
	# Check if scene has changed
	var current_scene: Node = get_tree().current_scene
	if current_scene:
		var scene_path: String = current_scene.scene_file_path
		if scene_path != _current_scene_path:
			var old_path := _current_scene_path
			_current_scene_path = scene_path
			_on_scene_changed(old_path, scene_path)


## Create the container node for ragdoll bodies.
func _create_ragdoll_container() -> void:
	if _ragdoll_container != null:
		return

	_ragdoll_container = Node2D.new()
	_ragdoll_container.name = "PersistentRagdolls"
	# Important: Add to self (which is under /root/) so it survives scene changes
	add_child(_ragdoll_container)

	# Make sure it renders on top of scene content
	_ragdoll_container.z_index = 100
	_ragdoll_container.z_as_relative = false


## Register a group of ragdoll bodies and joints to be managed/persisted.
## @param bodies: Array of RigidBody2D nodes (ragdoll body parts).
## @param joints: Array of PinJoint2D nodes (connections between parts).
## @return: Index of the registered group.
func register_ragdoll_group(bodies: Array[RigidBody2D], joints: Array[PinJoint2D]) -> int:
	if not persist_bodies:
		return -1

	# Reparent bodies and joints to the persistent container
	for rb in bodies:
		if is_instance_valid(rb):
			# Store global position before reparenting
			var global_pos := rb.global_position
			var global_rot := rb.global_rotation

			# Reparent to container
			if rb.get_parent():
				rb.get_parent().remove_child(rb)
			_ragdoll_container.add_child(rb)

			# Restore global position
			rb.global_position = global_pos
			rb.global_rotation = global_rot

	for joint in joints:
		if is_instance_valid(joint):
			var global_pos := joint.global_position

			if joint.get_parent():
				joint.get_parent().remove_child(joint)
			_ragdoll_container.add_child(joint)

			joint.global_position = global_pos

	# Create group record
	var group := {
		"bodies": bodies,
		"joints": joints,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	_ragdoll_groups.append(group)

	var group_index := _ragdoll_groups.size() - 1
	ragdoll_group_added.emit(group_index)

	_log("Registered ragdoll group #%d with %d bodies and %d joints" % [
		group_index, bodies.size(), joints.size()
	])

	# Enforce maximum body count
	_enforce_max_bodies()

	return group_index


## Remove a ragdoll group and free its bodies.
## @param group_index: Index of the group to remove.
func remove_ragdoll_group(group_index: int) -> void:
	if group_index < 0 or group_index >= _ragdoll_groups.size():
		return

	var group: Dictionary = _ragdoll_groups[group_index]

	# Free all bodies
	for rb in group["bodies"]:
		if is_instance_valid(rb):
			rb.queue_free()

	# Free all joints
	for joint in group["joints"]:
		if is_instance_valid(joint):
			joint.queue_free()

	_ragdoll_groups.remove_at(group_index)
	ragdoll_group_removed.emit(group_index)

	_log("Removed ragdoll group #%d" % group_index)


## Clear all persistent ragdoll bodies.
func clear_all_ragdolls() -> void:
	for i in range(_ragdoll_groups.size() - 1, -1, -1):
		remove_ragdoll_group(i)

	_log("Cleared all ragdoll groups")


## Enforce maximum body count by removing oldest groups.
func _enforce_max_bodies() -> void:
	var total_bodies := 0
	for group in _ragdoll_groups:
		total_bodies += group["bodies"].size()

	while total_bodies > max_persistent_bodies and _ragdoll_groups.size() > 0:
		var oldest_bodies: int = _ragdoll_groups[0]["bodies"].size()
		remove_ragdoll_group(0)
		total_bodies -= oldest_bodies


## Called when the scene tree changes.
func _on_tree_changed() -> void:
	# Ensure container still exists
	if _ragdoll_container == null:
		_create_ragdoll_container()


## Called when the scene changes.
func _on_scene_changed(old_scene: String, new_scene: String) -> void:
	_log("Scene changed: '%s' -> '%s'" % [old_scene, new_scene])
	scene_changed.emit(old_scene, new_scene)

	# Clean up invalid references after scene change
	_cleanup_invalid_references()


## Remove any invalid references from ragdoll groups.
func _cleanup_invalid_references() -> void:
	for group in _ragdoll_groups:
		# Filter out invalid bodies
		var valid_bodies: Array[RigidBody2D] = []
		for rb in group["bodies"]:
			if is_instance_valid(rb):
				valid_bodies.append(rb)
		group["bodies"] = valid_bodies

		# Filter out invalid joints
		var valid_joints: Array[PinJoint2D] = []
		for joint in group["joints"]:
			if is_instance_valid(joint):
				valid_joints.append(joint)
		group["joints"] = valid_joints

	# Remove empty groups
	for i in range(_ragdoll_groups.size() - 1, -1, -1):
		if _ragdoll_groups[i]["bodies"].is_empty():
			_ragdoll_groups.remove_at(i)


## Apply an impulse to all bodies in a specific ragdoll group.
## @param group_index: Index of the ragdoll group.
## @param direction: Direction of the impulse.
## @param strength: Strength of the impulse.
func apply_impulse_to_group(group_index: int, direction: Vector2, strength: float) -> void:
	if group_index < 0 or group_index >= _ragdoll_groups.size():
		return

	var group: Dictionary = _ragdoll_groups[group_index]
	for rb in group["bodies"]:
		if is_instance_valid(rb):
			if rb.freeze:
				rb.freeze = false
			rb.apply_central_impulse(direction.normalized() * strength)


## Get total number of ragdoll groups.
func get_group_count() -> int:
	return _ragdoll_groups.size()


## Get total number of persistent bodies.
func get_total_body_count() -> int:
	var total := 0
	for group in _ragdoll_groups:
		total += group["bodies"].size()
	return total


## Log a message to the file logger.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("info"):
		file_logger.info("[RagdollManager] " + message)
