extends GutTest
## Tests cold white store-style lamp placement on the Double Corridor map.


const REVOLVER_LEVEL_SCENE := preload("res://scenes/levels/RevolverLevel.tscn")
const EXPECTED_LIGHTS := {
	"ColdStoreLamp_TopCorridor_W": Vector2(620, 550),
	"ColdStoreLamp_TopCorridor_E": Vector2(900, 550),
	"ColdStoreLamp_MiddleCorridor_W": Vector2(1180, 700),
	"ColdStoreLamp_MiddleCorridor_E": Vector2(1180, 1000),
	"ColdStoreLamp_BottomCorridor_W": Vector2(620, 1150),
	"ColdStoreLamp_BottomCorridor_E": Vector2(900, 1150),
	"ColdStoreLamp_Exit": Vector2(1900, 800),
}


var level: Node2D = null
var lighting: Node2D = null


func before_each() -> void:
	level = REVOLVER_LEVEL_SCENE.instantiate()
	add_child_autofree(level)
	lighting = level.get_node_or_null("Environment/Lighting")


func test_has_lighting_container() -> void:
	assert_not_null(lighting, "Double Corridor should have an Environment/Lighting container")


func test_has_expected_cold_store_lamp_count() -> void:
	assert_not_null(lighting, "Lighting container is required")
	assert_eq(lighting.get_child_count(), 7,
		"Double Corridor should have 7 cold store lamps: 2 top, 2 middle, 2 bottom, 1 exit")


func test_lamps_are_at_requested_corridor_and_exit_positions() -> void:
	assert_not_null(lighting, "Lighting container is required")

	for light_name in EXPECTED_LIGHTS:
		var light := lighting.get_node_or_null(light_name) as PointLight2D
		assert_not_null(light, "Missing cold store lamp '%s'" % light_name)
		if light == null:
			continue
		assert_eq(light.position, EXPECTED_LIGHTS[light_name],
			"Cold store lamp '%s' should be at the requested map position" % light_name)


func test_lamps_use_cold_white_light_color() -> void:
	assert_not_null(lighting, "Lighting container is required")

	for child in lighting.get_children():
		var light := child as PointLight2D
		assert_not_null(light, "Lighting children should be PointLight2D nodes")
		if light == null:
			continue
		assert_true(light.color.b >= light.color.g and light.color.g > light.color.r,
			"Cold white lamp '%s' should be blue-green dominant, got %s" % [light.name, str(light.color)])
		assert_true(light.color.r >= 0.7 and light.color.g >= 0.85 and light.color.b >= 0.95,
			"Cold white lamp '%s' should stay near white, got %s" % [light.name, str(light.color)])


func test_lamps_have_shadows_and_soft_radial_texture() -> void:
	assert_not_null(lighting, "Lighting container is required")

	for child in lighting.get_children():
		var light := child as PointLight2D
		if light == null:
			continue
		assert_true(light.shadow_enabled,
			"Cold store lamp '%s' should cast shadows like other map lamps" % light.name)
		assert_not_null(light.texture,
			"Cold store lamp '%s' should use a soft radial texture" % light.name)
		assert_true(light.texture_scale >= 3.0 and light.texture_scale <= 4.0,
			"Cold store lamp '%s' should cover a corridor without excessive bleed" % light.name)
