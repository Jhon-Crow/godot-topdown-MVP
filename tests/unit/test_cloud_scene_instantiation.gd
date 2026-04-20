extends GutTest
## Integration tests verifying cloud scenes can be instantiated via PackedScene.
##
## Regression tests for Godot bug #94150 mitigation: cloud nodes must be created
## with instantiate() on a PackedScene rather than .new() on a GDScript, so that
## _ready() is always called regardless of the GDScript class registry state.


const ChemicalCloudScene := preload("res://scenes/effects/ChemicalCloud.tscn")
const AggressionCloudScene := preload("res://scenes/effects/AggressionCloud.tscn")


func test_chemical_cloud_scene_instantiates_with_script() -> void:
	# Given: ChemicalCloud.tscn is loaded as a PackedScene
	# When: instantiate() is called
	var cloud := ChemicalCloudScene.instantiate()
	add_child_autofree(cloud)
	await wait_frames(2)

	# Then: _ready() ran and the node has the ChemicalCloud script (cloud_radius exported)
	assert_true(cloud.has_method("_is_player_in_range"),
		"ChemicalCloud should have _is_player_in_range() method — script must be attached")
	assert_eq(cloud.cloud_radius, 300.0,
		"ChemicalCloud default cloud_radius should be 300.0")


func test_chemical_cloud_ready_is_called() -> void:
	# Given: a cloud node created via scene instantiation
	var cloud := ChemicalCloudScene.instantiate()
	add_child_autofree(cloud)
	await wait_frames(2)

	# Then: _time_remaining was initialized in _ready() (non-zero)
	assert_eq(cloud._time_remaining, cloud.cloud_duration,
		"_time_remaining must equal cloud_duration after _ready() — proves _ready() ran")


func test_aggression_cloud_scene_instantiates_with_script() -> void:
	# Given: AggressionCloud.tscn is loaded as a PackedScene
	var cloud := AggressionCloudScene.instantiate()
	add_child_autofree(cloud)
	await wait_frames(2)

	# Then: the node has the AggressionCloud script attached
	assert_true(cloud.has_method("_apply_effect_to_enemies_in_cloud"),
		"AggressionCloud should have _apply_effect_to_enemies_in_cloud() — script must be attached")
	assert_eq(cloud.cloud_radius, 300.0,
		"AggressionCloud default cloud_radius should be 300.0")


func test_aggression_cloud_ready_is_called() -> void:
	var cloud := AggressionCloudScene.instantiate()
	add_child_autofree(cloud)
	await wait_frames(2)

	assert_eq(cloud._time_remaining, cloud.cloud_duration,
		"_time_remaining must equal cloud_duration after _ready() — proves _ready() ran")


func test_chemical_cloud_grow_in_scales_only_visual() -> void:
	# Regression test: grow_in must NOT scale the whole node (which collapses detection area).
	var cloud := ChemicalCloudScene.instantiate()
	cloud.grow_in_duration = 5.0
	add_child_autofree(cloud)
	await wait_frames(2)

	# Parent node scale must stay at 1 — only _cloud_visual is scaled down
	assert_eq(cloud.scale, Vector2.ONE,
		"ChemicalCloud parent node scale must remain 1.0 — detection area must not be collapsed")


func test_aggression_cloud_grow_in_scales_only_visual() -> void:
	# Regression test: same check for aggression cloud.
	var cloud := AggressionCloudScene.instantiate()
	cloud.grow_in_duration = 5.0
	add_child_autofree(cloud)
	await wait_frames(2)

	assert_eq(cloud.scale, Vector2.ONE,
		"AggressionCloud parent node scale must remain 1.0 — detection area must not be collapsed")


func test_chemical_cloud_scene_has_preloaded_script_matching_grenade_reference() -> void:
	# Regression test: the grenade uses set_script() as a belt-and-suspenders fallback
	# comparing the instantiated cloud's script identity to a preloaded script reference.
	# That comparison only works if both references resolve to the same Script resource.
	var ChemicalCloudScript := preload("res://scripts/effects/chemical_cloud.gd")
	var cloud := ChemicalCloudScene.instantiate()
	add_child_autofree(cloud)
	await wait_frames(1)

	assert_eq(cloud.get_script(), ChemicalCloudScript,
		"ChemicalCloud.tscn must use the same Script resource as chemical_cloud.gd preload")


func test_aggression_cloud_scene_has_preloaded_script_matching_grenade_reference() -> void:
	var AggressionCloudScript := preload("res://scripts/effects/aggression_cloud.gd")
	var cloud := AggressionCloudScene.instantiate()
	add_child_autofree(cloud)
	await wait_frames(1)

	assert_eq(cloud.get_script(), AggressionCloudScript,
		"AggressionCloud.tscn must use the same Script resource as aggression_cloud.gd preload")


func test_chemical_cloud_set_script_fallback_attaches_behavior() -> void:
	# Simulates the exported-build case where instantiate() returns a bare Node2D
	# with no script. The grenade's set_script() fallback must restore behavior.
	var ChemicalCloudScript := preload("res://scripts/effects/chemical_cloud.gd")
	var bare := Node2D.new()
	bare.set_script(ChemicalCloudScript)
	add_child_autofree(bare)
	await wait_frames(2)

	assert_eq(bare.get_script(), ChemicalCloudScript,
		"set_script() must attach the ChemicalCloud script to a bare Node2D")
	assert_true(bare.has_method("_is_player_in_range"),
		"After set_script(), the node must expose ChemicalCloud methods")
	assert_eq(bare._time_remaining, bare.cloud_duration,
		"_ready() must still run after set_script() — _time_remaining should be initialized")
