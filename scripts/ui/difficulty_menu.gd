extends CanvasLayer
## Difficulty selection menu.
##
## Allows the player to select between Power Fantasy, Easy, Normal, Hard, and Black Metal modes.
## Power Fantasy mode: 10 HP, 3x ammo, reduced recoil, blue laser sights, special effects
## Easy mode: Longer enemy reaction delay - enemies take more time to shoot after spotting player
## Normal mode: Classic game behavior
## Hard mode: Enemies react when player looks away, reduced ammo
## Black Metal mode: 25% less HP, 25% faster movement, black-and-white-red visual filter (Issue #958)
## Also includes a Night Mode toggle right under the Difficulty title.
##
## Issue #1014: Power Fantasy uses bright gradient text, Black Metal uses gothic font.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var night_mode_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NightModeContainer/NightModeCheckbox
@onready var power_fantasy_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/PowerFantasyButton
@onready var easy_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EasyButton
@onready var normal_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NormalButton
@onready var hard_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/HardButton
@onready var black_metal_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BlackMetalButton
@onready var weapon_hints_option: OptionButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/WeaponHintsContainer/WeaponHintsOption
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel

## Gothic bitmap font for Black Metal button (Issue #1014).
var _gothic_font: Font = null

## Path to the Gothic bitmap font file.
const GOTHIC_FONT_PATH: String = "res://assets/fonts/gothic_bitmap.fnt"

## Gradient colors for Power Fantasy text (Issue #1014).
## Bright vibrant gradient from cyan through magenta to yellow.
const POWER_FANTASY_GRADIENT_COLORS: Array[Color] = [
	Color(0.0, 1.0, 1.0),    # Cyan
	Color(0.5, 0.0, 1.0),    # Purple
	Color(1.0, 0.0, 1.0),    # Magenta
	Color(1.0, 0.5, 0.0),    # Orange
	Color(1.0, 1.0, 0.0),    # Yellow
]

## RichTextLabel for Power Fantasy gradient text (Issue #1014).
var _power_fantasy_label: RichTextLabel = null


func _ready() -> void:
	# Load gothic font for Black Metal button (Issue #1014)
	_load_gothic_font()

	# Apply special styling to Power Fantasy and Black Metal buttons (Issue #1014)
	_setup_power_fantasy_button()
	_setup_black_metal_button()
	# Connect button signals
	night_mode_checkbox.toggled.connect(_on_night_mode_toggled)
	power_fantasy_button.pressed.connect(_on_power_fantasy_pressed)
	easy_button.pressed.connect(_on_easy_pressed)
	normal_button.pressed.connect(_on_normal_pressed)
	hard_button.pressed.connect(_on_hard_pressed)
	black_metal_button.pressed.connect(_on_black_metal_pressed)
	_setup_weapon_hints_option()
	weapon_hints_option.item_selected.connect(_on_weapon_hints_selected)
	back_button.pressed.connect(_on_back_pressed)

	# Update button states based on current difficulty
	_update_button_states()

	# Connect to difficulty changes
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)

	# Connect to experimental settings changes (for night mode)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.settings_changed.connect(_on_settings_changed)

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_button_states() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null:
		return

	var is_easy: bool = difficulty_manager.is_easy_mode()
	var is_normal: bool = difficulty_manager.is_normal_mode()
	var is_hard: bool = difficulty_manager.is_hard_mode()
	var is_power_fantasy: bool = difficulty_manager.is_power_fantasy_mode()
	var is_black_metal: bool = difficulty_manager.is_black_metal_mode()

	# Highlight current difficulty - disable the selected button
	power_fantasy_button.disabled = is_power_fantasy
	easy_button.disabled = is_easy
	normal_button.disabled = is_normal
	hard_button.disabled = is_hard
	black_metal_button.disabled = is_black_metal

	# Update button text to show selection
	# Power Fantasy uses gradient text via RichTextLabel (Issue #1014)
	_update_power_fantasy_text(is_power_fantasy)
	easy_button.text = "Easy (Selected)" if is_easy else "Easy"
	normal_button.text = "Normal (Selected)" if is_normal else "Normal"
	hard_button.text = "Hard (Selected)" if is_hard else "Hard"
	# Use uppercase for Black Metal because the gothic font only has uppercase glyphs (Issue #1014)
	black_metal_button.text = "BLACK METAL (SELECTED)" if is_black_metal else "BLACK METAL"

	# Update night mode checkbox
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		night_mode_checkbox.button_pressed = experimental_settings.is_realistic_visibility_enabled()

	# Update status label based on current difficulty
	var status_text: String = ""
	if is_power_fantasy:
		status_text = "Power Fantasy: 10 HP, 3x ammo, blue lasers"
	elif is_easy:
		status_text = "Easy mode: Enemies react slower"
	elif is_hard:
		status_text = "Hard mode: Enemies react when you look away"
	elif is_black_metal:
		status_text = "Black Metal: 25% less HP, 25% faster, B&W filter"
	else:
		status_text = "Normal mode: Classic gameplay"

	if experimental_settings and experimental_settings.is_realistic_visibility_enabled():
		status_text += " | Night Mode ON"

	status_label.text = status_text


func _on_night_mode_toggled(enabled: bool) -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		experimental_settings.set_realistic_visibility_enabled(enabled)
	_update_button_states()


func _on_power_fantasy_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.POWER_FANTASY)
	_update_button_states()


func _on_easy_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.EASY)
	_update_button_states()


func _on_normal_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.NORMAL)
	_update_button_states()


func _on_hard_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.HARD)
	_update_button_states()


func _on_black_metal_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.BLACK_METAL)
	_update_button_states()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_difficulty_changed(_new_difficulty: int) -> void:
	_update_button_states()


func _on_settings_changed() -> void:
	_update_button_states()


## Loads the Gothic bitmap font for Black Metal button (Issue #1014).
func _load_gothic_font() -> void:
	if ResourceLoader.exists(GOTHIC_FONT_PATH):
		var font = load(GOTHIC_FONT_PATH)
		if font != null:
			_gothic_font = font
		else:
			push_warning("[DifficultyMenu] Failed to load Gothic font from: " + GOTHIC_FONT_PATH)
	else:
		push_warning("[DifficultyMenu] Gothic font file not found: " + GOTHIC_FONT_PATH)


## Sets up the Power Fantasy button with gradient text (Issue #1014).
## Creates a RichTextLabel overlay on the button for the gradient effect.
func _setup_power_fantasy_button() -> void:
	# Hide the button's default text - we'll use a RichTextLabel overlay
	power_fantasy_button.text = ""

	# Create a CenterContainer to vertically center the RichTextLabel
	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create RichTextLabel for gradient text
	_power_fantasy_label = RichTextLabel.new()
	_power_fantasy_label.bbcode_enabled = true
	_power_fantasy_label.scroll_active = false
	_power_fantasy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_fantasy_label.fit_content = true
	_power_fantasy_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	center_container.add_child(_power_fantasy_label)
	power_fantasy_button.add_child(center_container)

	# Apply initial gradient text
	_update_power_fantasy_text(false)


## Updates the Power Fantasy button text with gradient effect (Issue #1014).
## @param is_selected: Whether Power Fantasy mode is currently selected.
func _update_power_fantasy_text(is_selected: bool) -> void:
	if _power_fantasy_label == null:
		return

	var base_text: String = "Power Fantasy (Selected)" if is_selected else "Power Fantasy"
	var gradient_text: String = _create_gradient_bbcode(base_text)
	_power_fantasy_label.text = "[center]" + gradient_text + "[/center]"


## Creates BBCode text with per-character gradient coloring (Issue #1014).
## @param text: The text to apply gradient to.
## @returns: BBCode formatted text with color tags for each character.
func _create_gradient_bbcode(text: String) -> String:
	if text.is_empty():
		return ""

	var result: String = ""
	var text_length: int = text.length()

	for i in range(text_length):
		var char: String = text[i]

		# Skip whitespace characters (no color needed)
		if char == " ":
			result += " "
			continue

		# Calculate gradient position (0.0 to 1.0)
		var t: float = float(i) / float(text_length - 1) if text_length > 1 else 0.0

		# Interpolate color along the gradient
		var color: Color = _sample_gradient(t)

		# Convert to hex and wrap character in color tag
		var hex_color: String = color.to_html(false)
		result += "[color=#" + hex_color + "]" + char + "[/color]"

	return result


## Samples a color from the Power Fantasy gradient at position t (Issue #1014).
## @param t: Position along gradient (0.0 to 1.0).
## @returns: Interpolated color at the given position.
func _sample_gradient(t: float) -> Color:
	var colors: Array[Color] = POWER_FANTASY_GRADIENT_COLORS
	var num_colors: int = colors.size()

	if num_colors == 0:
		return Color.WHITE
	if num_colors == 1:
		return colors[0]

	# Clamp t to valid range
	t = clampf(t, 0.0, 1.0)

	# Calculate which segment we're in
	var segment_size: float = 1.0 / float(num_colors - 1)
	var segment_index: int = int(t / segment_size)

	# Clamp to valid segment index
	if segment_index >= num_colors - 1:
		segment_index = num_colors - 2

	# Calculate position within segment
	var segment_t: float = (t - (float(segment_index) * segment_size)) / segment_size

	# Interpolate between the two colors
	return colors[segment_index].lerp(colors[segment_index + 1], segment_t)


## Sets up the Black Metal button with gothic font styling (Issue #1014).
func _setup_black_metal_button() -> void:
	if _gothic_font != null:
		black_metal_button.add_theme_font_override("font", _gothic_font)
		# Use a silver/gray color that fits the Black Metal aesthetic
		black_metal_button.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		black_metal_button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.9))
		black_metal_button.add_theme_color_override("font_pressed_color", Color(0.7, 0.6, 0.6))
		black_metal_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))


## Setup the weapon hints option button with items.
## Issue #809: Weapon hints setting moved to Difficulty/Gameplay menu.
func _setup_weapon_hints_option() -> void:
	weapon_hints_option.clear()
	weapon_hints_option.add_item("Always", 0)
	weapon_hints_option.add_item("First time only", 1)
	weapon_hints_option.add_item("Never", 2)

	# Select current mode from settings
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		var current_mode: int = weapon_hints_settings.get_hint_mode()
		weapon_hints_option.select(current_mode)
	else:
		# Default to "First time only" if settings not available
		weapon_hints_option.select(1)


## Called when weapon hints option is changed.
func _on_weapon_hints_selected(index: int) -> void:
	var weapon_hints_settings: Node = get_node_or_null("/root/WeaponHintsSettings")
	if weapon_hints_settings:
		weapon_hints_settings.set_hint_mode(index)
	_update_button_states()
