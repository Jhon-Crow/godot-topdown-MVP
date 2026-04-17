extends CanvasLayer
## Steam-style top-screen toast for newly available Armory unlocks.
##
## Listens to UnlockManager availability signals and announces locked items whose
## conditions have just become satisfied. The actual permanent unlock still happens
## in the Armory by holding LMB on the gold slot.


const DISPLAY_DURATION: float = 4.0
const SLIDE_DURATION: float = 0.35
const SLIDE_OUT_REPEAT_COUNT: int = 1
const TOAST_WIDTH: float = 460.0
const TOAST_HEIGHT: float = 78.0
const TOAST_TOP_MARGIN: float = 18.0
const TOAST_SIDE_MARGIN: float = 18.0
const ARMORY_ICON_PATH: String = "res://assets/sprites/ui/menu_icons/icon_armory.svg"
const GOLD_SHINE_SHADER_PATH: String = "res://scripts/shaders/gold_shine.gdshader"
const NOTIFICATION_TEMPLATE_KEY: String = "UNLOCK_NOTIFICATION_OPENED"
const NOTIFICATION_KIND_KEYS: Dictionary = {
	"weapon": "UNLOCK_NOTIFICATION_KIND_WEAPON",
	"grenade": "UNLOCK_NOTIFICATION_KIND_GRENADE",
	"active_item": "UNLOCK_NOTIFICATION_KIND_ACTIVE_ITEM"
}
const NOTIFICATION_KIND_FALLBACKS_RU: Dictionary = {
	"weapon": "оружие",
	"grenade": "граната",
	"active_item": "предмет"
}
const NOTIFICATION_KIND_FALLBACKS_EN: Dictionary = {
	"weapon": "weapon",
	"grenade": "grenade",
	"active_item": "item"
}

const WEAPON_NAME_KEYS: Dictionary = {
	"m16": "WEAPON_M16_NAME",
	"shotgun": "WEAPON_SHOTGUN_NAME",
	"mini_uzi": "WEAPON_MINI_UZI_NAME",
	"silenced_pistol": "WEAPON_SILENCED_PISTOL_NAME",
	"sniper": "WEAPON_ASVK_NAME",
	"revolver": "WEAPON_RSH12_NAME",
	"ak_gl": "WEAPON_AK_GL_NAME"
}

const WEAPON_FALLBACK_NAMES: Dictionary = {
	"m16": "M16",
	"shotgun": "Shotgun",
	"mini_uzi": "Mini UZI",
	"silenced_pistol": "Silenced Pistol",
	"sniper": "ASVK",
	"revolver": "RSh-12",
	"ak_gl": "AK + GL"
}

const GRENADE_NAME_KEYS: Dictionary = {
	0: "GRENADE_FLASHBANG_NAME",
	1: "GRENADE_FRAG_NAME",
	2: "GRENADE_DEFENSIVE_NAME",
	3: "GRENADE_AGGRESSION_GAS_NAME",
	4: "GRENADE_DRONE_NAME"
}

const GRENADE_FALLBACK_NAMES: Dictionary = {
	0: "Flashbang",
	1: "Frag Grenade",
	2: "F-1 Grenade",
	3: "Aggression Gas",
	4: "Drone"
}

const ACTIVE_ITEM_NAME_KEYS: Dictionary = {
	1: "ITEM_FLASHLIGHT_NAME",
	2: "ITEM_HOMING_BULLETS_NAME",
	3: "ITEM_TELEPORT_BRACERS_NAME",
	4: "ITEM_BFF_PENDANT_NAME",
	5: "ITEM_INVISIBILITY_NAME",
	6: "ITEM_BREAKER_BULLETS_NAME",
	7: "ITEM_FORCE_FIELD_NAME",
	8: "ITEM_TRAJECTORY_GLASSES_NAME",
	9: "ITEM_LASER_SIGHT_NAME",
	10: "ITEM_EXTENDED_MAGAZINE_NAME",
	11: "ITEM_LOUDSPEAKER_NAME",
	12: "ITEM_BREACHING_CHARGES_NAME",
	13: "ITEM_ARMORED_SKIN_NAME",
	14: "ITEM_AUTO_RELOAD_NAME",
	15: "ITEM_DRILLING_BULLETS_NAME",
	16: "ITEM_RECOIL_COMPENSATOR_NAME",
	17: "ITEM_COMBAT_DISPOSITION_NAME",
	18: "ITEM_EXPERIMENTAL_SAMPLE_NAME",
	19: "ITEM_FINE_MOTOR_SKILLS_NAME",
	20: "ITEM_DASH_NAME",
	21: "ITEM_GRENADE_BAG_NAME"
}

const ACTIVE_ITEM_FALLBACK_NAMES: Dictionary = {
	1: "Flashlight",
	2: "Homing Bullets",
	3: "Teleport Bracers",
	4: "BFF Pendant",
	5: "Invisibility",
	6: "Breaker Bullets",
	7: "Force Field",
	8: "Trajectory Glasses",
	9: "Laser Sight",
	10: "Extended Magazine",
	11: "Loudspeaker",
	12: "Breaching Charges",
	13: "Armored Skin",
	14: "Auto-Reload",
	15: "Drilling Bullets",
	16: "Recoil Compensator",
	17: "Combat Disposition",
	18: "Experimental Sample",
	19: "Fine Motor Skills",
	20: "Dash",
	21: "Grenade Bag"
}

var _announced_available_keys: Dictionary = {}
var _startup_suppressed_available_keys: Dictionary = {}
var _pending_notifications: Array[Dictionary] = []
var _is_showing: bool = false
var _animation_phase: String = "idle"

var _root_control: Control = null
var _toast: PanelContainer = null
var _toast_background: Panel = null
var _shine_overlay: ColorRect = null
var _icon_rect: TextureRect = null
var _message_label: Label = null
var _active_tween: Tween = null


func _ready() -> void:
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_unlock_manager()
	call_deferred("_seed_announced_available_unlocks")


## Builds the user-facing text. Falls back to Russian to match the issue text when
## compiled translation resources have not been regenerated yet.
func build_notification_text(kind: String, item_name: String) -> String:
	var clean_kind: String = kind.strip_edges()
	var clean_name: String = item_name.strip_edges()
	var template: String = tr(NOTIFICATION_TEMPLATE_KEY)
	if template == NOTIFICATION_TEMPLATE_KEY or template.is_empty():
		template = "Открыт %s !"
	return template % _build_notification_subject(clean_kind, clean_name)


func _build_notification_subject(kind: String, item_name: String) -> String:
	var kind_label: String = get_unlock_kind_display_name(kind)
	if kind_label.is_empty():
		return item_name
	if item_name.is_empty():
		return kind_label
	return "%s %s" % [kind_label, item_name]


func get_unlock_kind_display_name(kind: String) -> String:
	var kind_key: String = NOTIFICATION_KIND_KEYS.get(kind, "")
	var fallback: String = NOTIFICATION_KIND_FALLBACKS_RU.get(kind, kind)
	var locale: String = TranslationServer.get_locale()
	if locale.begins_with("en"):
		fallback = NOTIFICATION_KIND_FALLBACKS_EN.get(kind, fallback)
	return _translate_with_fallback(kind_key, fallback)


## Public entry point for tests and one-off scripted announcements.
func show_unlock_notification(item_name: String, kind: String = "") -> void:
	var clean_name: String = item_name.strip_edges()
	if clean_name.is_empty():
		return
	_pending_notifications.append({
		"kind": kind.strip_edges(),
		"item_name": clean_name
	})
	if _toast != null and not _is_showing:
		_show_next_notification()


## Collects all locked items whose unlock condition is currently met.
func collect_available_unlock_entries() -> Array[Dictionary]:
	return collect_available_unlock_entries_from_managers(
		get_node_or_null("/root/UnlockManager"),
		get_node_or_null("/root/GameManager"),
		get_node_or_null("/root/GrenadeManager"),
		get_node_or_null("/root/ActiveItemManager"))


## Dependency-injected variant used by tests.
func collect_available_unlock_entries_from_managers(
		unlock_manager: Node,
		game_manager: Node,
		grenade_manager: Node,
		active_item_manager: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append_array(_collect_weapon_entries(unlock_manager, game_manager))
	entries.append_array(_collect_grenade_entries(unlock_manager, grenade_manager))
	entries.append_array(_collect_active_item_entries(unlock_manager, active_item_manager))
	return entries


func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "UnlockNotificationRoot"
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)

	_toast = PanelContainer.new()
	_toast.name = "UnlockToast"
	_toast.custom_minimum_size = Vector2(TOAST_WIDTH, TOAST_HEIGHT)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate = Color.WHITE

	var empty_panel_style := StyleBoxEmpty.new()
	_toast.add_theme_stylebox_override("panel", empty_panel_style)
	_root_control.add_child(_toast)

	_toast_background = Panel.new()
	_toast_background.name = "ToastBackground"
	_toast_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_background.modulate.a = 0.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.055, 0.94)
	style.border_color = Color(1.0, 0.78, 0.16, 1.0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_toast_background.add_theme_stylebox_override("panel", style)
	_toast.add_child(_toast_background)

	_shine_overlay = ColorRect.new()
	_shine_overlay.name = "GoldShineOverlay"
	_shine_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shine_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	var shine_shader := load(GOLD_SHINE_SHADER_PATH) as Shader
	if shine_shader:
		var mat := ShaderMaterial.new()
		mat.shader = shine_shader
		mat.set_shader_parameter("horizontal_sweep", true)
		mat.set_shader_parameter("cycle_duration", 2.4)
		_shine_overlay.material = mat
	_toast.add_child(_shine_overlay)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 10)
	_toast.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "ContentRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	_icon_rect = TextureRect.new()
	_icon_rect.name = "ArmoryIcon"
	_icon_rect.custom_minimum_size = Vector2(42, 42)
	_icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.modulate = Color(1.0, 0.84, 0.22, 1.0)
	var icon_texture: Texture2D = load(ARMORY_ICON_PATH)
	if icon_texture:
		_icon_rect.texture = icon_texture
	row.add_child(_icon_rect)

	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.clip_text = true
	_message_label.add_theme_font_size_override("font_size", 20)
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.68, 1.0))
	_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_message_label.add_theme_constant_override("shadow_offset_x", 1)
	_message_label.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(_message_label)

	_position_toast(false)


func _connect_unlock_manager() -> void:
	var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
	if unlock_manager == null:
		_log("UnlockManager not found; unlock notifications are disabled")
		return
	if unlock_manager.has_signal("items_unlocked_by_condition"):
		var condition_callable := Callable(self, "_on_condition_unlocks_changed")
		if not unlock_manager.is_connected("items_unlocked_by_condition", condition_callable):
			unlock_manager.connect("items_unlocked_by_condition", condition_callable)
			_log("Connected to items_unlocked_by_condition")
	if unlock_manager.has_signal("items_unlocked_by_kill_condition"):
		var kill_callable := Callable(self, "_on_kill_condition_unlocks_changed")
		if not unlock_manager.is_connected("items_unlocked_by_kill_condition", kill_callable):
			unlock_manager.connect("items_unlocked_by_kill_condition", kill_callable)
			_log("Connected to items_unlocked_by_kill_condition")


func _seed_announced_available_unlocks() -> void:
	for entry in collect_available_unlock_entries():
		_startup_suppressed_available_keys[entry["key"]] = true
	if not _startup_suppressed_available_keys.is_empty():
		_log("Suppressed %d already-available startup unlock notification(s)" % _startup_suppressed_available_keys.size())


func _on_condition_unlocks_changed(_level_path: String) -> void:
	_queue_new_available_unlocks()


func _on_kill_condition_unlocks_changed() -> void:
	_queue_new_available_unlocks()


func _queue_new_available_unlocks() -> void:
	for entry in collect_available_unlock_entries():
		var key: String = entry["key"]
		if _announced_available_keys.get(key, false):
			continue
		_announced_available_keys[key] = true
		if _startup_suppressed_available_keys.erase(key):
			_log("Announcing previously startup-available unlock after live condition signal: %s" % key)
		show_unlock_notification(entry["name"], entry["kind"])


func _collect_weapon_entries(unlock_manager: Node, game_manager: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if unlock_manager == null or game_manager == null:
		return entries
	if not unlock_manager.has_method("is_weapon_condition_met") or not game_manager.has_method("is_weapon_unlocked"):
		return entries

	var weapon_ids: Array = WEAPON_NAME_KEYS.keys()
	if unlock_manager.has_method("get_weapons_with_conditions"):
		weapon_ids = unlock_manager.get_weapons_with_conditions()
	for raw_weapon_id in weapon_ids:
		var weapon_id: String = str(raw_weapon_id)
		if unlock_manager.is_weapon_condition_met(weapon_id) and not game_manager.is_weapon_unlocked(weapon_id):
			entries.append(_make_entry("weapon", weapon_id, get_weapon_display_name(weapon_id)))
	return entries


func _collect_grenade_entries(unlock_manager: Node, grenade_manager: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if unlock_manager == null or grenade_manager == null:
		return entries
	if not unlock_manager.has_method("is_grenade_condition_met") or not grenade_manager.has_method("is_grenade_unlocked"):
		return entries

	var grenade_types: Array = GRENADE_NAME_KEYS.keys()
	if grenade_manager.has_method("get_all_grenade_types"):
		grenade_types = grenade_manager.get_all_grenade_types()
	for raw_grenade_type in grenade_types:
		var grenade_type: int = int(raw_grenade_type)
		if unlock_manager.is_grenade_condition_met(grenade_type) and not grenade_manager.is_grenade_unlocked(grenade_type):
			entries.append(_make_entry("grenade", grenade_type, get_grenade_display_name(grenade_type, grenade_manager)))
	return entries


func _collect_active_item_entries(unlock_manager: Node, active_item_manager: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if unlock_manager == null or active_item_manager == null:
		return entries
	if not unlock_manager.has_method("is_active_item_condition_met") or not active_item_manager.has_method("is_active_item_unlocked"):
		return entries

	var item_types: Array = ACTIVE_ITEM_NAME_KEYS.keys()
	if active_item_manager.has_method("get_all_active_item_types"):
		item_types = active_item_manager.get_all_active_item_types()
	for raw_item_type in item_types:
		var item_type: int = int(raw_item_type)
		if unlock_manager.is_active_item_condition_met(item_type) and not active_item_manager.is_active_item_unlocked(item_type):
			entries.append(_make_entry("active_item", item_type, get_active_item_display_name(item_type, active_item_manager)))
	return entries


func _make_entry(kind: String, item_id: Variant, item_name: String) -> Dictionary:
	return {
		"kind": kind,
		"id": item_id,
		"key": "%s:%s" % [kind, str(item_id)],
		"name": item_name
	}


func get_weapon_display_name(weapon_id: String) -> String:
	return _translate_with_fallback(
		WEAPON_NAME_KEYS.get(weapon_id, ""),
		WEAPON_FALLBACK_NAMES.get(weapon_id, weapon_id))


func get_grenade_display_name(grenade_type: int, grenade_manager: Node = null) -> String:
	if grenade_manager and grenade_manager.has_method("get_grenade_data"):
		var data: Dictionary = grenade_manager.get_grenade_data(grenade_type)
		var name_key: String = data.get("name_key", "")
		if not name_key.is_empty():
			return _translate_with_fallback(name_key, data.get("name", str(grenade_type)))
		var name: String = data.get("name", "")
		if not name.is_empty():
			return name
	return _translate_with_fallback(
		GRENADE_NAME_KEYS.get(grenade_type, ""),
		GRENADE_FALLBACK_NAMES.get(grenade_type, str(grenade_type)))


func get_active_item_display_name(item_type: int, active_item_manager: Node = null) -> String:
	if active_item_manager and active_item_manager.has_method("get_active_item_data"):
		var data: Dictionary = active_item_manager.get_active_item_data(item_type)
		var name_key: String = data.get("name_key", "")
		if not name_key.is_empty():
			return _translate_with_fallback(name_key, data.get("name", str(item_type)))
		var name: String = data.get("name", "")
		if not name.is_empty():
			return name
	return _translate_with_fallback(
		ACTIVE_ITEM_NAME_KEYS.get(item_type, ""),
		ACTIVE_ITEM_FALLBACK_NAMES.get(item_type, str(item_type)))


func _translate_with_fallback(key: String, fallback: String) -> String:
	if key.is_empty():
		return fallback
	var translated: String = tr(key)
	if translated == key or translated.is_empty():
		return fallback
	return translated


func _show_next_notification() -> void:
	if _toast == null or _message_label == null:
		return
	if _pending_notifications.is_empty():
		_is_showing = false
		_animation_phase = "idle"
		return

	_is_showing = true
	var notification: Dictionary = _pending_notifications.pop_front()
	_message_label.text = build_notification_text(
		notification.get("kind", ""),
		notification.get("item_name", ""))
	_position_toast(false)
	_toast.modulate = Color.WHITE
	if _toast_background:
		_toast_background.modulate.a = 0.0
	if _shine_overlay:
		_shine_overlay.modulate.a = 0.0
	if _message_label:
		_message_label.modulate = Color.WHITE
	if _icon_rect:
		_icon_rect.modulate = Color(1.0, 0.84, 0.22, 1.0)
	_toast.show()

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation_phase = "entering"
	_active_tween.tween_property(_toast, "position:y", TOAST_TOP_MARGIN, SLIDE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _toast_background:
		_active_tween.parallel().tween_property(_toast_background, "modulate:a", 1.0, SLIDE_DURATION * 0.75)
	if _shine_overlay:
		_active_tween.parallel().tween_property(_shine_overlay, "modulate:a", 1.0, SLIDE_DURATION * 0.75)
	_active_tween.tween_callback(func(): _animation_phase = "visible")
	_active_tween.tween_interval(DISPLAY_DURATION)
	_active_tween.tween_callback(func(): _animation_phase = "exiting")
	_active_tween.tween_property(_toast, "position:y", _get_hidden_y(), SLIDE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if _toast_background:
		_active_tween.parallel().tween_property(_toast_background, "modulate:a", 0.0, SLIDE_DURATION)
	if _shine_overlay:
		_active_tween.parallel().tween_property(_shine_overlay, "modulate:a", 0.0, SLIDE_DURATION)
	_active_tween.tween_callback(Callable(self, "_on_current_notification_finished"))


func _on_current_notification_finished() -> void:
	_is_showing = false
	_animation_phase = "idle"
	if _toast:
		_toast.hide()
	if _pending_notifications.is_empty():
		return
	_show_next_notification()


func _position_toast(visible_position: bool) -> void:
	if _toast == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var toast_width: float = minf(TOAST_WIDTH, maxf(260.0, viewport_size.x - TOAST_SIDE_MARGIN * 2.0))
	_toast.size = Vector2(toast_width, TOAST_HEIGHT)
	_toast.custom_minimum_size = Vector2(toast_width, TOAST_HEIGHT)
	_toast.position = Vector2(
		(viewport_size.x - toast_width) * 0.5,
		TOAST_TOP_MARGIN if visible_position else _get_hidden_y())


func _get_hidden_y() -> float:
	return -TOAST_HEIGHT - TOAST_TOP_MARGIN


func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[UnlockNotificationManager] " + message)
	else:
		print("[UnlockNotificationManager] " + message)
