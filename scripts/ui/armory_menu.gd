extends CanvasLayer
## Armory menu for viewing unlocked and locked weapons and selecting grenade type.
##
## Displays a grid of weapons showing which are unlocked (available) and
## which are locked (coming in future updates). Also allows selection of
## grenade type (Flashbang or Frag Grenade).
##
## Note: Changing grenade type will restart the current level.

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

## Reference to grenade manager.
var _grenade_manager: Node = null

## Dictionary to track grenade selection buttons.
var _grenade_buttons: Dictionary = {}


func _ready() -> void:
	# Connect button signals
	back_button.pressed.connect(_on_back_pressed)

	# Get grenade manager reference
	_grenade_manager = get_node_or_null("/root/GrenadeManager")

	# Populate weapon grid (includes grenades now)
	_populate_weapon_grid()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _populate_weapon_grid() -> void:
	# Clear existing children
	for child in weapon_grid.get_children():
		child.queue_free()
	_grenade_buttons.clear()

	# Count unlocked weapons for status
	var unlocked_count: int = 0
	var total_count: int = WEAPONS.size()

	# Create a slot for each weapon
	for weapon_id in WEAPONS:
		var weapon_data: Dictionary = WEAPONS[weapon_id]
		var slot := _create_weapon_slot(weapon_id, weapon_data, false)
		weapon_grid.add_child(slot)

		if weapon_data["unlocked"]:
			unlocked_count += 1

	# Add grenade selection slots
	if _grenade_manager:
		var grenade_types := _grenade_manager.get_all_grenade_types()
		for grenade_type in grenade_types:
			var grenade_data := _grenade_manager.get_grenade_data(grenade_type)
			var is_selected := _grenade_manager.is_selected(grenade_type)
			var slot := _create_grenade_slot(grenade_type, grenade_data, is_selected)
			weapon_grid.add_child(slot)
			unlocked_count += 1  # All grenades are unlocked
			total_count += 1

	# Update status label
	status_label.text = "Unlocked: %d / %d" % [unlocked_count, total_count]


func _create_weapon_slot(weapon_id: String, weapon_data: Dictionary, _is_selectable: bool) -> PanelContainer:
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


func _create_grenade_slot(grenade_type: int, grenade_data: Dictionary, is_selected: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = grenade_data.get("name", "grenade") + "_slot"
	slot.custom_minimum_size = Vector2(100, 120)

	# Add style override for selected state
	if is_selected:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.5, 0.3, 0.5)  # Green tint for selected
		style.set_border_width_all(2)
		style.border_color = Color(0.3, 0.8, 0.4, 1.0)
		style.set_corner_radius_all(5)
		slot.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(vbox)

	# Grenade icon
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(64, 64)
	vbox.add_child(icon_container)

	var icon_path: String = grenade_data.get("icon_path", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(64, 64)
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var texture: Texture2D = load(icon_path)
		if texture:
			texture_rect.texture = texture

		icon_container.add_child(texture_rect)
	else:
		# Fallback icon
		var fallback_label := Label.new()
		fallback_label.text = "💣"
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.add_theme_font_size_override("font_size", 32)
		icon_container.add_child(fallback_label)

	# Grenade name
	var name_label := Label.new()
	name_label.text = grenade_data.get("name", "Grenade")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# Selection button
	var select_button := Button.new()
	select_button.custom_minimum_size = Vector2(80, 25)

	if is_selected:
		select_button.text = "Selected"
		select_button.disabled = true
	else:
		select_button.text = "Select"
		select_button.pressed.connect(_on_grenade_selected.bind(grenade_type))

	vbox.add_child(select_button)
	_grenade_buttons[grenade_type] = select_button

	# Add tooltip
	slot.tooltip_text = grenade_data.get("description", "")

	return slot


func _on_grenade_selected(grenade_type: int) -> void:
	if _grenade_manager == null:
		return

	# Get grenade name for confirmation
	var grenade_name := _grenade_manager.get_grenade_name(grenade_type)

	# Show confirmation that level will restart
	FileLogger.info("[ArmoryMenu] Player selected grenade: %s - level will restart" % grenade_name)

	# Set the new grenade type (this will restart the level)
	_grenade_manager.set_grenade_type(grenade_type, true)


func _on_back_pressed() -> void:
	back_pressed.emit()
