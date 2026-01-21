extends CanvasLayer
## Armory menu for viewing unlocked and locked weapons.
##
## Displays a grid of weapons showing which are unlocked (available) and
## which are locked (coming in future updates). Currently shows M16 as
## the only unlocked weapon.

## Signal emitted when the back button is pressed.
signal back_pressed

## Dictionary of all weapons with their data.
## Keys: weapon_id, Values: dictionary with name, icon_path, unlocked status
const WEAPONS: Dictionary = {
	"m16": {
		"name": "M16",
		"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
		"unlocked": true,
		"description": "Standard assault rifle"
	},
	"ak47": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	},
	"shotgun": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	},
	"smg": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	},
	"sniper": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	},
	"pistol": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	}
}

## Reference to UI elements.
@onready var weapon_grid: GridContainer = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/WeaponGrid
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	# Connect button signals
	back_button.pressed.connect(_on_back_pressed)

	# Populate weapon grid
	_populate_weapon_grid()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _populate_weapon_grid() -> void:
	# Clear existing children
	for child in weapon_grid.get_children():
		child.queue_free()

	# Count unlocked weapons for status
	var unlocked_count: int = 0
	var total_count: int = WEAPONS.size()

	# Create a slot for each weapon
	for weapon_id in WEAPONS:
		var weapon_data: Dictionary = WEAPONS[weapon_id]
		var slot := _create_weapon_slot(weapon_id, weapon_data)
		weapon_grid.add_child(slot)

		if weapon_data["unlocked"]:
			unlocked_count += 1

	# Update status label
	status_label.text = "Unlocked: %d / %d" % [unlocked_count, total_count]


func _create_weapon_slot(weapon_id: String, weapon_data: Dictionary) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = weapon_id + "_slot"
	slot.custom_minimum_size = Vector2(100, 100)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(vbox)

	# Weapon icon or placeholder
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(64, 64)
	vbox.add_child(icon_container)

	if weapon_data["unlocked"] and weapon_data["icon_path"] != "":
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(64, 64)
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var texture: Texture2D = load(weapon_data["icon_path"])
		if texture:
			texture_rect.texture = texture

		icon_container.add_child(texture_rect)
	else:
		# Locked weapon - show lock icon (using text for now)
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", 32)
		icon_container.add_child(lock_label)

	# Weapon name
	var name_label := Label.new()
	name_label.text = weapon_data["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not weapon_data["unlocked"]:
		name_label.modulate = Color(0.5, 0.5, 0.5)

	vbox.add_child(name_label)

	# Add tooltip
	slot.tooltip_text = weapon_data["description"]

	return slot


func _on_back_pressed() -> void:
	back_pressed.emit()
