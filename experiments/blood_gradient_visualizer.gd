extends Node2D

## Blood Gradient Visualizer
## Displays the current blood decal gradient for visual verification
## Useful for debugging circular vs rectangular appearance issues

@onready var blood_decal_scene = preload("res://scenes/effects/BloodDecal.tscn")

var test_scales = [0.5, 1.0, 2.0, 3.0]
var decals: Array[Sprite2D] = []

func _ready():
	print("[GradientViz] Blood Gradient Visualizer started")
	print("[GradientViz] This scene displays blood decals at various scales")
	print("[GradientViz] to verify circular shape vs rectangular artifacts")

	# Create test decals at different scales
	var x_pos = 100
	for scale_val in test_scales:
		var decal = blood_decal_scene.instantiate() as Sprite2D
		add_child(decal)
		decal.position = Vector2(x_pos, 300)
		decal.scale = Vector2(scale_val, scale_val)
		decals.append(decal)

		# Add label
		var label = Label.new()
		add_child(label)
		label.position = Vector2(x_pos - 30, 100)
		label.text = "Scale: %.1fx" % scale_val

		print("[GradientViz] Created decal at scale %.1fx, pos (%d, 300)" % [scale_val, x_pos])
		x_pos += 200

	print("[GradientViz] Press Q to quit")
	print("[GradientViz] Gradient info:")
	_print_gradient_info()

func _print_gradient_info():
	if decals.size() == 0:
		return

	var decal = decals[0]
	var texture = decal.texture as GradientTexture2D
	if not texture:
		print("[GradientViz] ERROR: No GradientTexture2D found")
		return

	var gradient = texture.gradient
	print("[GradientViz] Fill mode: %d (1 = RADIAL)" % texture.fill)
	print("[GradientViz] Fill from: %s" % texture.fill_from)
	print("[GradientViz] Fill to: %s" % texture.fill_to)
	print("[GradientViz] Texture size: %dx%d" % [texture.width, texture.height])
	print("[GradientViz] Gradient stops: %d" % gradient.offsets.size())

	for i in range(gradient.offsets.size()):
		var offset = gradient.offsets[i]
		var color = gradient.colors[i]
		print("[GradientViz]   Stop %d: offset=%.3f, rgba=(%.2f, %.2f, %.2f, %.2f)" % [
			i, offset, color.r, color.g, color.b, color.a
		])

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_pressed(KEY_Q):
		print("[GradientViz] Exiting...")
		get_tree().quit()
