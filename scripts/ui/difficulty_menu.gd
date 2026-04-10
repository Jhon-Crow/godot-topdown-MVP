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
## Issue #1742: Strelok (Gunslinger) uses glowing red background and cowboy-style font.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var night_mode_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NightModeContainer/NightModeCheckbox
@onready var power_fantasy_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/PowerFantasyButton
@onready var gunslinger_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/GunslingerButton
@onready var easy_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/EasyButton
@onready var normal_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NormalButton
@onready var hard_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/HardButton
@onready var black_metal_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BlackMetalButton
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel

## Gothic bitmap font for Black Metal button (Issue #1014).
var _gothic_font: Font = null

## Path to the Gothic bitmap font file.
const GOTHIC_FONT_PATH: String = "res://assets/fonts/gothic_bitmap.fnt"

## Cowboy TTF font for Gunslinger button (Issue #1742).
## Rye is a Western/cowboy-style slab serif font for Latin characters.
## Cyrillic characters fall back to a system serif font automatically.
var _cowboy_font: Font = null

## Path to the Rye Western-style TTF font file.
const COWBOY_FONT_PATH: String = "res://assets/fonts/rye/Rye-Regular.ttf"

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
	# Setup tooltips and label behaviour for settings rows (Issue #1200)
	_setup_row_hover($MenuContainer/PanelContainer/MarginContainer/VBoxContainer/NightModeContainer,
			tr("NIGHT_MODE"))

	# Load gothic font for Black Metal button (Issue #1014)
	_load_gothic_font()

	# Load cowboy font for Strelok (Gunslinger) button (Issue #1742)
	_load_cowboy_font()

	# Apply special styling to Power Fantasy and Black Metal buttons (Issue #1014)
	_setup_power_fantasy_button()
	_setup_black_metal_button()

	# Apply cowboy styling to Strelok (Gunslinger) button (Issue #1742)
	_setup_strelok_button()
	# Connect button signals
	night_mode_checkbox.toggled.connect(_on_night_mode_toggled)
	power_fantasy_button.pressed.connect(_on_power_fantasy_pressed)
	gunslinger_button.pressed.connect(_on_gunslinger_pressed)
	easy_button.pressed.connect(_on_easy_pressed)
	normal_button.pressed.connect(_on_normal_pressed)
	hard_button.pressed.connect(_on_hard_pressed)
	black_metal_button.pressed.connect(_on_black_metal_pressed)
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

	# Connect to locale changes so button text updates immediately on language switch
	var localization_settings: Node = get_node_or_null("/root/LocalizationSettings")
	if localization_settings and localization_settings.has_signal("locale_changed"):
		localization_settings.locale_changed.connect(_on_locale_changed)

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
	var is_gunslinger: bool = difficulty_manager.is_gunslinger_mode()

	# Highlight current difficulty - disable the selected button
	power_fantasy_button.disabled = is_power_fantasy
	gunslinger_button.disabled = is_gunslinger
	easy_button.disabled = is_easy
	normal_button.disabled = is_normal
	hard_button.disabled = is_hard
	black_metal_button.disabled = is_black_metal

	# Update button text to show selection
	# Power Fantasy uses gradient text via RichTextLabel (Issue #1014)
	_update_power_fantasy_text(is_power_fantasy)
	gunslinger_button.text = tr("GUNSLINGER_SELECTED") if is_gunslinger else tr("GUNSLINGER")
	easy_button.text = tr("EASY_SELECTED") if is_easy else tr("EASY")
	normal_button.text = tr("NORMAL_SELECTED") if is_normal else tr("NORMAL")
	hard_button.text = tr("HARD_SELECTED") if is_hard else tr("HARD")
	# Always use hardcoded uppercase ASCII for Black Metal — gothic font only supports uppercase
	# ASCII glyphs, and the name must not change when switching languages (it is a proper name).
	black_metal_button.text = "BLACK METAL - SELECTED" if is_black_metal else "BLACK METAL"

	# Update night mode checkbox
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings:
		night_mode_checkbox.button_pressed = experimental_settings.is_realistic_visibility_enabled()

	# Update status label based on current difficulty
	var status_text: String = ""
	if is_power_fantasy:
		status_text = tr("DIFFICULTY_STATUS_POWER_FANTASY")
	elif is_gunslinger:
		status_text = tr("DIFFICULTY_STATUS_GUNSLINGER")
	elif is_easy:
		status_text = tr("DIFFICULTY_STATUS_EASY")
	elif is_hard:
		status_text = tr("DIFFICULTY_STATUS_HARD")
	elif is_black_metal:
		status_text = tr("DIFFICULTY_STATUS_BLACK_METAL")
	else:
		status_text = tr("DIFFICULTY_STATUS_NORMAL")

	if experimental_settings and experimental_settings.is_realistic_visibility_enabled():
		status_text += tr("DIFFICULTY_STATUS_NIGHT_MODE_ON")

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
	_restart_if_in_game()


func _on_gunslinger_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.GUNSLINGER)
	_update_button_states()
	_restart_if_in_game()


func _on_easy_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.EASY)
	_update_button_states()
	_restart_if_in_game()


func _on_normal_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.NORMAL)
	_update_button_states()
	_restart_if_in_game()


func _on_hard_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.HARD)
	_update_button_states()
	_restart_if_in_game()


func _on_black_metal_pressed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.set_difficulty(difficulty_manager.Difficulty.BLACK_METAL)
	_update_button_states()
	_restart_if_in_game()


## Restarts the current scene when difficulty changes mid-game (Issue #1432).
## Only restarts if a level is actually running (player node is present).
## Unpauses the tree first so the reload can proceed cleanly.
func _restart_if_in_game() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager == null:
		return
	# Only restart when the game is actually in-progress (a player exists in the scene).
	if game_manager.get("player") == null:
		return
	get_tree().paused = false
	game_manager.restart_scene()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_difficulty_changed(_new_difficulty: int) -> void:
	_update_button_states()


func _on_settings_changed() -> void:
	_update_button_states()


func _on_locale_changed(_new_locale: String) -> void:
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


## Loads the Rye Western-style font for Gunslinger button (Issue #1742).
## Rye handles Latin characters with a cowboy/Western aesthetic.
## A SystemFont fallback covers Cyrillic characters (for Russian "Стрелок" text).
func _load_cowboy_font() -> void:
	if not ResourceLoader.exists(COWBOY_FONT_PATH):
		push_warning("[DifficultyMenu] Cowboy font file not found: " + COWBOY_FONT_PATH)
		return
	var rye_font := FontFile.new()
	var err := rye_font.load_dynamic_font(COWBOY_FONT_PATH)
	if err != OK:
		push_warning("[DifficultyMenu] Failed to load Rye font from: " + COWBOY_FONT_PATH)
		return
	# Add a Cyrillic-capable serif system font as fallback so Russian text renders correctly
	var cyrillic_fallback := SystemFont.new()
	cyrillic_fallback.font_names = ["FreeSerif", "DejaVu Serif", "Georgia", "Times New Roman", "serif"]
	rye_font.fallbacks = [cyrillic_fallback]
	_cowboy_font = rye_font


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


## Semi-transparent background colour drawn over a settings row on hover (Issue #1200).
const ROW_HOVER_BG: Color = Color(1.0, 1.0, 1.0, 0.08)

## Tracks which Control nodes currently have a hover background drawn on them.
var _row_hover_bg: Dictionary = {}


## Draw the hover background rect for a registered row node.
func _draw_row_bg(node: Control) -> void:
	if _row_hover_bg.get(node, false):
		node.draw_rect(Rect2(Vector2.ZERO, node.size), ROW_HOVER_BG)


## Setup tooltip, hover highlight, and label behaviour for a settings row (Issue #1200).
## @param container   The HBoxContainer that holds the label + interactive control.
## @param tooltip     Short name shown in the tooltip and applied to all child nodes.
## @param description Optional sibling Label with the long description text.
##                    When provided it receives the same tooltip, hover highlight,
##                    and click-forwarding as the main container.
func _setup_row_hover(container: Control, tooltip: String,
		description: Control = null) -> void:
	container.tooltip_text = tooltip
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in container.get_children():
		if child is Control:
			child.tooltip_text = tooltip
	_row_hover_bg[container] = false
	container.draw.connect(_draw_row_bg.bind(container))
	container.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
	container.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
	container.gui_input.connect(_on_row_gui_input.bind(container))
	if description != null:
		description.tooltip_text = tooltip
		description.mouse_filter = Control.MOUSE_FILTER_STOP
		_row_hover_bg[description] = false
		description.draw.connect(_draw_row_bg.bind(description))
		description.mouse_entered.connect(_on_row_hovered.bind(container, description, true))
		description.mouse_exited.connect(_on_row_hovered.bind(container, description, false))
		description.gui_input.connect(_on_row_gui_input.bind(container))


## Apply or remove hover background on the row container and its description label.
func _on_row_hovered(container: Control, description: Control,
		hovered: bool) -> void:
	_row_hover_bg[container] = hovered
	container.queue_redraw()
	if description != null:
		_row_hover_bg[description] = hovered
		description.queue_redraw()


## Forward a left-click on the row container to the first interactive control inside.
func _on_row_gui_input(event: InputEvent, container: Control) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		for child in container.get_children():
			if child is CheckButton:
				# Setting button_pressed automatically emits toggled signal.
				child.button_pressed = not child.button_pressed
				container.accept_event()
				return
			if child is Button:
				child.pressed.emit()
				container.accept_event()
				return
			if child is OptionButton:
				child.show_popup()
				container.accept_event()
				return


## Sets up the Black Metal button with gothic font styling (Issue #1014).
## Issue #1020: Increased font size, added black background.
func _setup_black_metal_button() -> void:
	if _gothic_font != null:
		black_metal_button.add_theme_font_override("font", _gothic_font)
		# Use a silver/gray color that fits the Black Metal aesthetic
		black_metal_button.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		black_metal_button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.9))
		black_metal_button.add_theme_color_override("font_pressed_color", Color(0.7, 0.6, 0.6))
		black_metal_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
		# Increase font size for better visibility (Issue #1020)
		black_metal_button.add_theme_font_size_override("font_size", 24)

	# Add black background to the Black Metal button (Issue #1020)
	var black_style := StyleBoxFlat.new()
	black_style.bg_color = Color(0.05, 0.05, 0.05)  # Near-black background
	black_style.set_corner_radius_all(4)
	black_style.set_content_margin_all(8)
	black_metal_button.add_theme_stylebox_override("normal", black_style)

	# Create hover style with slightly lighter background
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.12, 0.12, 0.12)
	hover_style.set_corner_radius_all(4)
	hover_style.set_content_margin_all(8)
	black_metal_button.add_theme_stylebox_override("hover", hover_style)

	# Create pressed style with darker background
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.02, 0.02, 0.02)
	pressed_style.set_corner_radius_all(4)
	pressed_style.set_content_margin_all(8)
	black_metal_button.add_theme_stylebox_override("pressed", pressed_style)

	# Create disabled style for when Black Metal is selected
	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.08, 0.08, 0.08)
	disabled_style.set_corner_radius_all(4)
	disabled_style.set_content_margin_all(8)
	black_metal_button.add_theme_stylebox_override("disabled", disabled_style)


## Sets up the Gunslinger button with cowboy-style font and glowing red background (Issue #1742).
## The glowing semi-transparent red background evokes the danger of the Gunslinger difficulty.
## The Rye Western font handles Latin; Cyrillic falls back to a system serif font.
func _setup_strelok_button() -> void:
	# Apply cowboy font if loaded
	if _cowboy_font != null:
		gunslinger_button.add_theme_font_override("font", _cowboy_font)
		gunslinger_button.add_theme_font_size_override("font_size", 18)

	# Warm amber/gold text color for a Western/cowboy feel
	gunslinger_button.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	gunslinger_button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
	gunslinger_button.add_theme_color_override("font_pressed_color", Color(0.9, 0.7, 0.3))
	gunslinger_button.add_theme_color_override("font_disabled_color", Color(0.8, 0.6, 0.4))

	# Normal state: semi-transparent glowing red background
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.7, 0.05, 0.05, 0.55)  # Semi-transparent crimson
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)
	normal_style.shadow_color = Color(1.0, 0.1, 0.1, 0.75)  # Bright red glow
	normal_style.shadow_size = 8
	gunslinger_button.add_theme_stylebox_override("normal", normal_style)

	# Hover state: slightly more opaque on hover
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.8, 0.07, 0.07, 0.7)  # More visible on hover
	hover_style.set_corner_radius_all(4)
	hover_style.set_content_margin_all(8)
	hover_style.shadow_color = Color(1.0, 0.15, 0.15, 0.9)  # Intense glow on hover
	hover_style.shadow_size = 12
	gunslinger_button.add_theme_stylebox_override("hover", hover_style)

	# Pressed state: darker, compressed look
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.5, 0.02, 0.02, 0.6)  # Semi-transparent dark red
	pressed_style.set_corner_radius_all(4)
	pressed_style.set_content_margin_all(8)
	pressed_style.shadow_color = Color(0.8, 0.1, 0.1, 0.6)
	pressed_style.shadow_size = 4
	gunslinger_button.add_theme_stylebox_override("pressed", pressed_style)

	# Disabled state: when Gunslinger is already selected
	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.6, 0.03, 0.03, 0.5)  # Muted semi-transparent red
	disabled_style.set_corner_radius_all(4)
	disabled_style.set_content_margin_all(8)
	disabled_style.shadow_color = Color(0.9, 0.1, 0.1, 0.5)
	disabled_style.shadow_size = 6
	gunslinger_button.add_theme_stylebox_override("disabled", disabled_style)


