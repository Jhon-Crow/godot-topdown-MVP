extends CanvasLayer
## Performance settings menu (Issue #1186).
##
## Provides toggles for every subsystem that can affect performance,
## making it easy to isolate bottlenecks during profiling.
## All features are enabled by default - disabling does not change
## default gameplay.

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to UI elements.
@onready var particles_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ParticlesContainer/ParticlesCheckbox
@onready var blood_decals_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BloodDecalsContainer/BloodDecalsCheckbox
@onready var screen_shake_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ScreenShakeContainer/ScreenShakeCheckbox
@onready var explosion_lights_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/ExplosionLightsContainer/ExplosionLightsCheckbox
@onready var wall_hit_particles_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/WallHitParticlesContainer/WallHitParticlesCheckbox
@onready var ai_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIContainer/AICheckbox
@onready var ai_idle_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIIdleContainer/AIIdleCheckbox
@onready var ai_combat_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AICombatContainer/AICombatCheckbox
@onready var ai_seeking_cover_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AISeekingCoverContainer/AISeekingCoverCheckbox
@onready var ai_in_cover_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIInCoverContainer/AIInCoverCheckbox
@onready var ai_flanking_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIFlankingContainer/AIFlankingCheckbox
@onready var ai_suppressed_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AISuppressedContainer/AISuppressedCheckbox
@onready var ai_retreating_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIRetreatingContainer/AIRetreatingCheckbox
@onready var ai_pursuing_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIPursuingContainer/AIPursuingCheckbox
@onready var ai_assault_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AIAssaultContainer/AIAssaultCheckbox
@onready var ai_searching_checkbox: CheckButton = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/AISearchingContainer/AISearchingCheckbox
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StatusLabel
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton
@onready var benchmark_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BenchmarkContainer/BenchmarkButton
@onready var benchmark_label: Label = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BenchmarkLabel
@onready var stress_benchmark_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StressBenchmarkContainer/StressBenchmarkButton
@onready var quick_benchmark_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BenchmarkContainer/QuickBenchmarkButton
@onready var quick_stress_benchmark_button: Button = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/StressBenchmarkContainer/QuickStressBenchmarkButton

## Semi-transparent background colour drawn over a settings row on hover (Issue #1461).
const ROW_HOVER_BG: Color = Color(1.0, 1.0, 1.0, 0.08)

## Seconds to sample FPS for each benchmark step (Issue #1497).
const BENCHMARK_SAMPLE_DURATION: float = 3.0

## Number of cycles each benchmark step is repeated for reliable results (Issue #1516).
const BENCHMARK_CYCLES: int = 20

## Number of particle emitters spawned per stress step (Issue #1504).
const STRESS_PARTICLE_COUNT: int = 30

## Number of PointLight2D nodes spawned per stress step (Issue #1504).
const STRESS_LIGHT_COUNT: int = 20

## Number of enemies spawned for the AI stress step (Issue #1504).
const STRESS_ENEMY_COUNT: int = 20

## Seconds to sample FPS under each extreme load (Issue #1504).
const STRESS_SAMPLE_DURATION: float = 2.0

## Whether a benchmark is currently running (Issue #1497).
var _benchmark_running: bool = false

## Tracks which Control nodes currently have a hover background drawn on them.
var _row_hover_bg: Dictionary = {}


func _ready() -> void:
	# Setup tooltips, hover highlight, and label behaviour for settings rows (Issue #1461)
	var _vbox: Node = $MenuContainer/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer
	_setup_row_hover(_vbox.get_node("ParticlesContainer"),
			"Particle Effects",
			_vbox.get_node("ParticlesDescription"))
	_setup_row_hover(_vbox.get_node("BloodDecalsContainer"),
			"Blood Decals on Floor/Walls",
			_vbox.get_node("BloodDecalsDescription"))
	_setup_row_hover(_vbox.get_node("ScreenShakeContainer"),
			"Screen Shake",
			_vbox.get_node("ScreenShakeDescription"))
	_setup_row_hover(_vbox.get_node("ExplosionLightsContainer"),
			"Explosion/Flashbang Lights",
			_vbox.get_node("ExplosionLightsDescription"))
	_setup_row_hover(_vbox.get_node("WallHitParticlesContainer"),
			"Wall Hit Particles",
			_vbox.get_node("WallHitParticlesDescription"))
	_setup_row_hover(_vbox.get_node("AIContainer"),
			"Enemy AI",
			_vbox.get_node("AIDescription"))
	_setup_row_hover(_vbox.get_node("AIIdleContainer"),
			"AI: IDLE state (patrol/guard scan)")
	_setup_row_hover(_vbox.get_node("AICombatContainer"),
			"AI: COMBAT state (peek, shoot, return)")
	_setup_row_hover(_vbox.get_node("AISeekingCoverContainer"),
			"AI: SEEKING_COVER state (pathfind to cover)")
	_setup_row_hover(_vbox.get_node("AIInCoverContainer"),
			"AI: IN_COVER state (wait and peek)")
	_setup_row_hover(_vbox.get_node("AIFlankingContainer"),
			"AI: FLANKING state (flank movement)")
	_setup_row_hover(_vbox.get_node("AISuppressedContainer"),
			"AI: SUPPRESSED state (pinned under fire)")
	_setup_row_hover(_vbox.get_node("AIRetreatingContainer"),
			"AI: RETREATING state (fall back to cover)")
	_setup_row_hover(_vbox.get_node("AIPursuingContainer"),
			"AI: PURSUING state (cover-to-cover advance)")
	_setup_row_hover(_vbox.get_node("AIAssaultContainer"),
			"AI: ASSAULT state (coordinated rush)")
	_setup_row_hover(_vbox.get_node("AISearchingContainer"),
			"AI: SEARCHING state (hunt last known position)")

	# Connect checkbox signals
	particles_checkbox.toggled.connect(_on_particles_toggled)
	blood_decals_checkbox.toggled.connect(_on_blood_decals_toggled)
	screen_shake_checkbox.toggled.connect(_on_screen_shake_toggled)
	explosion_lights_checkbox.toggled.connect(_on_explosion_lights_toggled)
	wall_hit_particles_checkbox.toggled.connect(_on_wall_hit_particles_toggled)
	ai_checkbox.toggled.connect(_on_ai_toggled)
	ai_idle_checkbox.toggled.connect(func(e): _on_ai_state_toggled("idle", e))
	ai_combat_checkbox.toggled.connect(func(e): _on_ai_state_toggled("combat", e))
	ai_seeking_cover_checkbox.toggled.connect(func(e): _on_ai_state_toggled("seeking_cover", e))
	ai_in_cover_checkbox.toggled.connect(func(e): _on_ai_state_toggled("in_cover", e))
	ai_flanking_checkbox.toggled.connect(func(e): _on_ai_state_toggled("flanking", e))
	ai_suppressed_checkbox.toggled.connect(func(e): _on_ai_state_toggled("suppressed", e))
	ai_retreating_checkbox.toggled.connect(func(e): _on_ai_state_toggled("retreating", e))
	ai_pursuing_checkbox.toggled.connect(func(e): _on_ai_state_toggled("pursuing", e))
	ai_assault_checkbox.toggled.connect(func(e): _on_ai_state_toggled("assault", e))
	ai_searching_checkbox.toggled.connect(func(e): _on_ai_state_toggled("searching", e))
	benchmark_button.pressed.connect(_on_benchmark_pressed)
	stress_benchmark_button.pressed.connect(_on_stress_benchmark_pressed)
	quick_benchmark_button.pressed.connect(_on_quick_benchmark_pressed)
	quick_stress_benchmark_button.pressed.connect(_on_quick_stress_benchmark_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Update UI from current settings
	_update_ui()

	# Connect to settings changes so UI stays in sync
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.settings_changed.connect(_update_ui)
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings and gameplay_settings.has_signal("settings_changed"):
		gameplay_settings.settings_changed.connect(_update_ui)

	# Allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _update_ui() -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings == null:
		status_label.text = "Error: PerformanceSettings not found"
		return

	particles_checkbox.button_pressed = perf_settings.is_particles_enabled()
	blood_decals_checkbox.button_pressed = perf_settings.is_blood_decals_enabled()
	screen_shake_checkbox.button_pressed = perf_settings.is_screen_shake_enabled()
	explosion_lights_checkbox.button_pressed = perf_settings.is_explosion_lights_enabled()
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	wall_hit_particles_checkbox.button_pressed = gameplay_settings.is_wall_hit_particles_enabled() if gameplay_settings else true
	ai_checkbox.button_pressed = perf_settings.is_ai_enabled()
	ai_idle_checkbox.button_pressed = perf_settings.is_ai_state_idle_enabled()
	ai_combat_checkbox.button_pressed = perf_settings.is_ai_state_combat_enabled()
	ai_seeking_cover_checkbox.button_pressed = perf_settings.is_ai_state_seeking_cover_enabled()
	ai_in_cover_checkbox.button_pressed = perf_settings.is_ai_state_in_cover_enabled()
	ai_flanking_checkbox.button_pressed = perf_settings.is_ai_state_flanking_enabled()
	ai_suppressed_checkbox.button_pressed = perf_settings.is_ai_state_suppressed_enabled()
	ai_retreating_checkbox.button_pressed = perf_settings.is_ai_state_retreating_enabled()
	ai_pursuing_checkbox.button_pressed = perf_settings.is_ai_state_pursuing_enabled()
	ai_assault_checkbox.button_pressed = perf_settings.is_ai_state_assault_enabled()
	ai_searching_checkbox.button_pressed = perf_settings.is_ai_state_searching_enabled()

	# Show which features are currently disabled
	var disabled_parts: Array[String] = []
	if not perf_settings.is_particles_enabled(): disabled_parts.append("Particles")
	if not perf_settings.is_blood_decals_enabled(): disabled_parts.append("Blood decals")
	if not perf_settings.is_screen_shake_enabled(): disabled_parts.append("Screen shake")
	if not perf_settings.is_explosion_lights_enabled(): disabled_parts.append("Explosion lights")
	var gs: Node = get_node_or_null("/root/GameplaySettings")
	if gs and not gs.is_wall_hit_particles_enabled(): disabled_parts.append("Wall hit particles")
	if not perf_settings.is_ai_enabled(): disabled_parts.append("AI")
	if not perf_settings.is_ai_state_idle_enabled(): disabled_parts.append("AI:IDLE")
	if not perf_settings.is_ai_state_combat_enabled(): disabled_parts.append("AI:COMBAT")
	if not perf_settings.is_ai_state_seeking_cover_enabled(): disabled_parts.append("AI:SEEKING_COVER")
	if not perf_settings.is_ai_state_in_cover_enabled(): disabled_parts.append("AI:IN_COVER")
	if not perf_settings.is_ai_state_flanking_enabled(): disabled_parts.append("AI:FLANKING")
	if not perf_settings.is_ai_state_suppressed_enabled(): disabled_parts.append("AI:SUPPRESSED")
	if not perf_settings.is_ai_state_retreating_enabled(): disabled_parts.append("AI:RETREATING")
	if not perf_settings.is_ai_state_pursuing_enabled(): disabled_parts.append("AI:PURSUING")
	if not perf_settings.is_ai_state_assault_enabled(): disabled_parts.append("AI:ASSAULT")
	if not perf_settings.is_ai_state_searching_enabled(): disabled_parts.append("AI:SEARCHING")

	if disabled_parts.is_empty():
		status_label.text = "All performance features enabled"
	else:
		status_label.text = "Disabled: " + ", ".join(disabled_parts)


func _on_particles_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_particles_enabled(enabled)
	_update_ui()


func _on_blood_decals_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_blood_decals_enabled(enabled)
	_update_ui()


func _on_screen_shake_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_screen_shake_enabled(enabled)
	_update_ui()


func _on_explosion_lights_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_explosion_lights_enabled(enabled)
	_update_ui()


func _on_wall_hit_particles_toggled(enabled: bool) -> void:
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings:
		gameplay_settings.set_wall_hit_particles_enabled(enabled)
	_update_ui()


func _on_ai_toggled(enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings:
		perf_settings.set_ai_enabled(enabled)
	_update_ui()


func _on_ai_state_toggled(state_name: String, enabled: bool) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings == null:
		return
	match state_name:
		"idle": perf_settings.set_ai_state_idle_enabled(enabled)
		"combat": perf_settings.set_ai_state_combat_enabled(enabled)
		"seeking_cover": perf_settings.set_ai_state_seeking_cover_enabled(enabled)
		"in_cover": perf_settings.set_ai_state_in_cover_enabled(enabled)
		"flanking": perf_settings.set_ai_state_flanking_enabled(enabled)
		"suppressed": perf_settings.set_ai_state_suppressed_enabled(enabled)
		"retreating": perf_settings.set_ai_state_retreating_enabled(enabled)
		"pursuing": perf_settings.set_ai_state_pursuing_enabled(enabled)
		"assault": perf_settings.set_ai_state_assault_enabled(enabled)
		"searching": perf_settings.set_ai_state_searching_enabled(enabled)
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()


## Draw the hover background rect for a registered row node.
func _draw_row_bg(node: Control) -> void:
	if _row_hover_bg.get(node, false):
		node.draw_rect(Rect2(Vector2.ZERO, node.size), ROW_HOVER_BG)


## Setup tooltip, hover highlight, and label behaviour for a settings row (Issue #1461).
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
				child.button_pressed = not child.button_pressed
				container.accept_event()
				return


## Start the benchmark sequence (Issue #1497).
func _on_benchmark_pressed() -> void:
	if _benchmark_running:
		return
	_benchmark_running = true
	benchmark_button.disabled = true
	quick_benchmark_button.disabled = true
	stress_benchmark_button.disabled = true
	quick_stress_benchmark_button.disabled = true
	benchmark_label.text = "Benchmark running..."
	_run_benchmark(BENCHMARK_CYCLES)


## Start the quick benchmark sequence with a single cycle (Issue #1516).
func _on_quick_benchmark_pressed() -> void:
	if _benchmark_running:
		return
	_benchmark_running = true
	benchmark_button.disabled = true
	quick_benchmark_button.disabled = true
	stress_benchmark_button.disabled = true
	quick_stress_benchmark_button.disabled = true
	benchmark_label.text = "Quick benchmark running (1 cycle)..."
	_run_benchmark(1)


## Run the full benchmark sequence as a coroutine (Issue #1497).
## Measures FPS with each subsystem disabled one at a time, plus a baseline.
## Results are written to a dedicated benchmark log file.
## @param cycles  Number of cycles to run per step (use 1 for a quick test).
func _run_benchmark(cycles: int) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if perf_settings == null:
		benchmark_label.text = "Benchmark failed: PerformanceSettings not found"
		_benchmark_running = false
		benchmark_button.disabled = false
		quick_benchmark_button.disabled = false
		stress_benchmark_button.disabled = false
		quick_stress_benchmark_button.disabled = false
		return

	# Open a dedicated benchmark log file
	var datetime := Time.get_datetime_dict_from_system()
	var timestamp := "%04d%02d%02d_%02d%02d%02d" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]
	]
	var exe_dir := OS.get_executable_path().get_base_dir()
	var log_path := exe_dir.path_join("benchmark_log_%s.txt" % timestamp)
	var log_file := FileAccess.open(log_path, FileAccess.WRITE)
	if log_file == null:
		log_path = "user://benchmark_log_%s.txt" % timestamp
		log_file = FileAccess.open(log_path, FileAccess.WRITE)
	if log_file == null:
		benchmark_label.text = "Benchmark failed: cannot create log file"
		_benchmark_running = false
		benchmark_button.disabled = false
		quick_benchmark_button.disabled = false
		stress_benchmark_button.disabled = false
		quick_stress_benchmark_button.disabled = false
		return

	# Disable vsync so frame-rate is not artificially capped during benchmarking (Issue #1516).
	var vsync_mode_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_bm_write(log_file, "=".repeat(60))
	_bm_write(log_file, "BENCHMARK LOG")
	_bm_write(log_file, "=".repeat(60))
	_bm_write(log_file, "Started: %s" % Time.get_datetime_string_from_system())
	_bm_write(log_file, "Sample duration per step: %.1f s" % BENCHMARK_SAMPLE_DURATION)
	_bm_write(log_file, "Cycles per step: %d" % cycles)
	_bm_write(log_file, "VSync: disabled for benchmark")
	_bm_write(log_file, "-".repeat(60))

	var results: Array[String] = []

	# Define benchmark steps: [label, disable_fn, enable_fn]
	# Each step disables one subsystem, samples FPS, then re-enables it.
	var steps: Array = [
		["Baseline (all enabled)", null, null],
		["Particles disabled", func(): perf_settings.set_particles_enabled(false),
			func(): perf_settings.set_particles_enabled(true)],
		["Blood Decals disabled", func(): perf_settings.set_blood_decals_enabled(false),
			func(): perf_settings.set_blood_decals_enabled(true)],
		["Screen Shake disabled", func(): perf_settings.set_screen_shake_enabled(false),
			func(): perf_settings.set_screen_shake_enabled(true)],
		["Explosion Lights disabled", func(): perf_settings.set_explosion_lights_enabled(false),
			func(): perf_settings.set_explosion_lights_enabled(true)],
		["Wall Hit Particles disabled",
			func(): if gameplay_settings: gameplay_settings.set_wall_hit_particles_enabled(false),
			func(): if gameplay_settings: gameplay_settings.set_wall_hit_particles_enabled(true)],
		["AI disabled", func(): perf_settings.set_ai_enabled(false),
			func(): perf_settings.set_ai_enabled(true)],
		["AI:IDLE disabled", func(): perf_settings.set_ai_state_idle_enabled(false),
			func(): perf_settings.set_ai_state_idle_enabled(true)],
		["AI:COMBAT disabled", func(): perf_settings.set_ai_state_combat_enabled(false),
			func(): perf_settings.set_ai_state_combat_enabled(true)],
		["AI:SEEKING_COVER disabled", func(): perf_settings.set_ai_state_seeking_cover_enabled(false),
			func(): perf_settings.set_ai_state_seeking_cover_enabled(true)],
		["AI:IN_COVER disabled", func(): perf_settings.set_ai_state_in_cover_enabled(false),
			func(): perf_settings.set_ai_state_in_cover_enabled(true)],
		["AI:FLANKING disabled", func(): perf_settings.set_ai_state_flanking_enabled(false),
			func(): perf_settings.set_ai_state_flanking_enabled(true)],
		["AI:SUPPRESSED disabled", func(): perf_settings.set_ai_state_suppressed_enabled(false),
			func(): perf_settings.set_ai_state_suppressed_enabled(true)],
		["AI:RETREATING disabled", func(): perf_settings.set_ai_state_retreating_enabled(false),
			func(): perf_settings.set_ai_state_retreating_enabled(true)],
		["AI:PURSUING disabled", func(): perf_settings.set_ai_state_pursuing_enabled(false),
			func(): perf_settings.set_ai_state_pursuing_enabled(true)],
		["AI:ASSAULT disabled", func(): perf_settings.set_ai_state_assault_enabled(false),
			func(): perf_settings.set_ai_state_assault_enabled(true)],
		["AI:SEARCHING disabled", func(): perf_settings.set_ai_state_searching_enabled(false),
			func(): perf_settings.set_ai_state_searching_enabled(true)],
	]

	for i in steps.size():
		var step: Array = steps[i]
		var step_label: String = step[0]
		var disable_fn = step[1]
		var enable_fn = step[2]

		benchmark_label.text = "Benchmarking %d/%d: %s..." % [i + 1, steps.size(), step_label]
		_bm_write(log_file, "\n[Step %d/%d] %s" % [i + 1, steps.size(), step_label])

		# Apply the disable function for this step
		if disable_fn != null:
			disable_fn.call()

		# Run cycles and accumulate samples (Issue #1516).
		var fps_samples: Array[float] = []
		for _cycle in cycles:
			var elapsed: float = 0.0
			while elapsed < BENCHMARK_SAMPLE_DURATION:
				await get_tree().process_frame
				var delta: float = get_process_delta_time()
				elapsed += delta
				fps_samples.append(Engine.get_frames_per_second())

		# Calculate stats
		var fps_avg: float = 0.0
		var fps_min: float = fps_samples[0]
		var fps_max: float = fps_samples[0]
		for fps in fps_samples:
			fps_avg += fps
			if fps < fps_min:
				fps_min = fps
			if fps > fps_max:
				fps_max = fps
		fps_avg /= fps_samples.size()

		var result_line: String = "  avg=%.1f  min=%.1f  max=%.1f  samples=%d  cycles=%d" % [
			fps_avg, fps_min, fps_max, fps_samples.size(), cycles]
		_bm_write(log_file, result_line)
		results.append("%s: avg=%.1f min=%.1f max=%.1f" % [step_label, fps_avg, fps_min, fps_max])

		# Re-enable the subsystem
		if enable_fn != null:
			enable_fn.call()

		# Brief pause between steps so settings changes can propagate
		await get_tree().create_timer(0.2).timeout

	_bm_write(log_file, "\n" + "=".repeat(60))
	_bm_write(log_file, "BENCHMARK COMPLETE: %s" % Time.get_datetime_string_from_system())
	_bm_write(log_file, "=".repeat(60))
	log_file.flush()
	log_file.close()

	# Restore vsync mode (Issue #1516).
	DisplayServer.window_set_vsync_mode(vsync_mode_before)

	# Log completion to main game log as well
	var fl: Node = get_node_or_null("/root/FileLogger")
	if fl and fl.has_method("log_info"):
		fl.log_info("[Benchmark] Completed. Results saved to: %s" % log_path)

	benchmark_label.text = "Benchmark done! Log: %s" % log_path.get_file()
	_benchmark_running = false
	benchmark_button.disabled = false
	quick_benchmark_button.disabled = false
	stress_benchmark_button.disabled = false
	quick_stress_benchmark_button.disabled = false
	_update_ui()


## Write a line to the benchmark log file (Issue #1497).
func _bm_write(log_file: FileAccess, line: String) -> void:
	log_file.store_line(line)


## Start the stress benchmark sequence (Issue #1504).
func _on_stress_benchmark_pressed() -> void:
	if _benchmark_running:
		return
	_benchmark_running = true
	benchmark_button.disabled = true
	quick_benchmark_button.disabled = true
	stress_benchmark_button.disabled = true
	quick_stress_benchmark_button.disabled = true
	benchmark_label.text = "Stress benchmark running..."
	_run_stress_benchmark(BENCHMARK_CYCLES)


## Start the quick stress benchmark with a single cycle (Issue #1516).
func _on_quick_stress_benchmark_pressed() -> void:
	if _benchmark_running:
		return
	_benchmark_running = true
	benchmark_button.disabled = true
	quick_benchmark_button.disabled = true
	stress_benchmark_button.disabled = true
	quick_stress_benchmark_button.disabled = true
	benchmark_label.text = "Quick stress benchmark running (1 cycle)..."
	_run_stress_benchmark(1)


## Run the extreme-load benchmark (Issue #1504).
##
## For each subsystem:
##   1. Spawn stress objects (particles, lights, or enemies) to create extreme load.
##   2. Sample FPS with the subsystem ENABLED.
##   3. Disable the subsystem.
##   4. Sample FPS with the subsystem DISABLED under the same load.
##   5. Clean up stress objects and re-enable the subsystem.
##
## The delta between enabled and disabled FPS is the true runtime cost of each subsystem.
## All results are saved to a dedicated log file alongside the passive benchmark log.
## @param cycles  Number of cycles to run per half-step (use 1 for a quick test).
func _run_stress_benchmark(cycles: int) -> void:
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if perf_settings == null:
		benchmark_label.text = "Stress benchmark failed: PerformanceSettings not found"
		_benchmark_running = false
		benchmark_button.disabled = false
		quick_benchmark_button.disabled = false
		stress_benchmark_button.disabled = false
		quick_stress_benchmark_button.disabled = false
		return

	# Open dedicated stress benchmark log file.
	var datetime := Time.get_datetime_dict_from_system()
	var timestamp := "%04d%02d%02d_%02d%02d%02d" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]
	]
	var exe_dir := OS.get_executable_path().get_base_dir()
	var log_path := exe_dir.path_join("stress_benchmark_%s.txt" % timestamp)
	var log_file := FileAccess.open(log_path, FileAccess.WRITE)
	if log_file == null:
		log_path = "user://stress_benchmark_%s.txt" % timestamp
		log_file = FileAccess.open(log_path, FileAccess.WRITE)
	if log_file == null:
		benchmark_label.text = "Stress benchmark failed: cannot create log file"
		_benchmark_running = false
		benchmark_button.disabled = false
		quick_benchmark_button.disabled = false
		stress_benchmark_button.disabled = false
		quick_stress_benchmark_button.disabled = false
		return

	# Disable vsync so frame-rate is not artificially capped during benchmarking (Issue #1516).
	var vsync_mode_before_stress := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_bm_write(log_file, "=".repeat(60))
	_bm_write(log_file, "STRESS BENCHMARK LOG (Issue #1504)")
	_bm_write(log_file, "=".repeat(60))
	_bm_write(log_file, "Started: %s" % Time.get_datetime_string_from_system())
	_bm_write(log_file, "Sample duration per half-step: %.1f s" % STRESS_SAMPLE_DURATION)
	_bm_write(log_file, "Cycles per half-step: %d" % cycles)
	_bm_write(log_file, "VSync: disabled for benchmark")
	_bm_write(log_file, "Stress: %d particles, %d lights, %d enemies" % [
		STRESS_PARTICLE_COUNT, STRESS_LIGHT_COUNT, STRESS_ENEMY_COUNT])
	_bm_write(log_file, "-".repeat(60))
	_bm_write(log_file, "Format: subsystem | enabled_fps | disabled_fps | delta_fps")
	_bm_write(log_file, "-".repeat(60))

	var results: Array[String] = []

	# -------------------------------------------------------------------------
	# Step 1: Particles stress
	# -------------------------------------------------------------------------
	var step_index := 1
	var total_steps := 4  # particles, lights, AI, AI-states

	benchmark_label.text = "Stress %d/%d: Particles..." % [step_index, total_steps]
	_bm_write(log_file, "\n[Step %d/%d] Particles (spawning %d GPUParticles2D)" % [
		step_index, total_steps, STRESS_PARTICLE_COUNT])

	var particle_nodes: Array = _spawn_stress_particles()
	var fps_particles_on := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)
	perf_settings.set_particles_enabled(false)
	# Stop already-spawned emitters so the disabled sample reflects zero particle work.
	# The PerformanceSettings toggle only guards future creation; existing nodes keep
	# emitting unless explicitly stopped (Issue #1517).
	for p in particle_nodes:
		if is_instance_valid(p):
			p.emitting = false
	var fps_particles_off := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)
	perf_settings.set_particles_enabled(true)
	_cleanup_stress_nodes(particle_nodes)

	var delta_particles: float = fps_particles_off - fps_particles_on
	var line := "  enabled=%.1f  disabled=%.1f  delta=%.1f (positive = cost)" % [
		fps_particles_on, fps_particles_off, delta_particles]
	_bm_write(log_file, line)
	results.append("Particles: enabled=%.1f disabled=%.1f delta=%.1f" % [
		fps_particles_on, fps_particles_off, delta_particles])

	await get_tree().create_timer(0.3).timeout

	# -------------------------------------------------------------------------
	# Step 2: Explosion lights stress
	# -------------------------------------------------------------------------
	step_index += 1
	benchmark_label.text = "Stress %d/%d: Explosion Lights..." % [step_index, total_steps]
	_bm_write(log_file, "\n[Step %d/%d] Explosion Lights (spawning %d PointLight2D)" % [
		step_index, total_steps, STRESS_LIGHT_COUNT])

	var light_nodes: Array = _spawn_stress_lights()
	var fps_lights_on := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)
	perf_settings.set_explosion_lights_enabled(false)
	# Disable light nodes to simulate "lights disabled" path
	for ln in light_nodes:
		if is_instance_valid(ln):
			ln.visible = false
	var fps_lights_off := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)
	perf_settings.set_explosion_lights_enabled(true)
	_cleanup_stress_nodes(light_nodes)

	var delta_lights: float = fps_lights_off - fps_lights_on
	line = "  enabled=%.1f  disabled=%.1f  delta=%.1f" % [
		fps_lights_on, fps_lights_off, delta_lights]
	_bm_write(log_file, line)
	results.append("Explosion lights: enabled=%.1f disabled=%.1f delta=%.1f" % [
		fps_lights_on, fps_lights_off, delta_lights])

	await get_tree().create_timer(0.3).timeout

	# -------------------------------------------------------------------------
	# Step 3: AI stress (all states enabled vs AI fully disabled)
	# -------------------------------------------------------------------------
	step_index += 1
	benchmark_label.text = "Stress %d/%d: AI (%d enemies)..." % [
		step_index, total_steps, STRESS_ENEMY_COUNT]
	_bm_write(log_file, "\n[Step %d/%d] AI (spawning %d enemies)" % [
		step_index, total_steps, STRESS_ENEMY_COUNT])

	var enemy_nodes: Array = _spawn_stress_enemies()
	await get_tree().create_timer(0.5).timeout  # Let enemies initialise
	var fps_ai_on := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)
	perf_settings.set_ai_enabled(false)
	var fps_ai_off := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)
	perf_settings.set_ai_enabled(true)
	_cleanup_stress_nodes(enemy_nodes)

	var delta_ai: float = fps_ai_off - fps_ai_on
	line = "  enabled=%.1f  disabled=%.1f  delta=%.1f" % [fps_ai_on, fps_ai_off, delta_ai]
	_bm_write(log_file, line)
	results.append("AI (%d enemies): enabled=%.1f disabled=%.1f delta=%.1f" % [
		STRESS_ENEMY_COUNT, fps_ai_on, fps_ai_off, delta_ai])

	await get_tree().create_timer(0.3).timeout

	# -------------------------------------------------------------------------
	# Step 4: Combined extreme load (all systems at once)
	# -------------------------------------------------------------------------
	step_index += 1
	benchmark_label.text = "Stress %d/%d: Combined extreme load..." % [step_index, total_steps]
	_bm_write(log_file, "\n[Step %d/%d] Combined extreme load (particles + lights + enemies)" % [
		step_index, total_steps])

	var combo_particles: Array = _spawn_stress_particles()
	var combo_lights: Array = _spawn_stress_lights()
	var combo_enemies: Array = _spawn_stress_enemies()
	await get_tree().create_timer(0.5).timeout
	var fps_combo_on := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)

	# Disable all subsystems
	perf_settings.set_particles_enabled(false)
	perf_settings.set_explosion_lights_enabled(false)
	perf_settings.set_ai_enabled(false)
	# Stop already-spawned particle emitters (same fix as Step 1, Issue #1517).
	for p in combo_particles:
		if is_instance_valid(p):
			p.emitting = false
	for ln in combo_lights:
		if is_instance_valid(ln):
			ln.visible = false
	var fps_combo_off := await _sample_fps(STRESS_SAMPLE_DURATION, cycles)

	# Restore all
	perf_settings.set_particles_enabled(true)
	perf_settings.set_explosion_lights_enabled(true)
	perf_settings.set_ai_enabled(true)
	_cleanup_stress_nodes(combo_particles)
	_cleanup_stress_nodes(combo_lights)
	_cleanup_stress_nodes(combo_enemies)

	var delta_combo: float = fps_combo_off - fps_combo_on
	line = "  enabled=%.1f  disabled=%.1f  delta=%.1f" % [fps_combo_on, fps_combo_off, delta_combo]
	_bm_write(log_file, line)
	results.append("Combined: enabled=%.1f disabled=%.1f delta=%.1f" % [
		fps_combo_on, fps_combo_off, delta_combo])

	# -------------------------------------------------------------------------
	# Finalise
	# -------------------------------------------------------------------------
	_bm_write(log_file, "\n" + "=".repeat(60))
	_bm_write(log_file, "STRESS BENCHMARK COMPLETE: %s" % Time.get_datetime_string_from_system())
	_bm_write(log_file, "=".repeat(60))
	_bm_write(log_file, "Summary:")
	for r in results:
		_bm_write(log_file, "  " + r)
	log_file.flush()
	log_file.close()

	# Restore vsync mode (Issue #1516).
	DisplayServer.window_set_vsync_mode(vsync_mode_before_stress)

	var fl: Node = get_node_or_null("/root/FileLogger")
	if fl and fl.has_method("log_info"):
		fl.log_info("[StressBenchmark] Completed. Results saved to: %s" % log_path)

	benchmark_label.text = "Stress done! Log: %s" % log_path.get_file()
	_benchmark_running = false
	benchmark_button.disabled = false
	quick_benchmark_button.disabled = false
	stress_benchmark_button.disabled = false
	quick_stress_benchmark_button.disabled = false
	_update_ui()


## Sample average FPS over [duration] seconds repeated for [cycles] cycles (Issue #1504, #1516).
## Running multiple cycles improves result reliability.
func _sample_fps(duration: float, cycles: int = BENCHMARK_CYCLES) -> float:
	var fps_sum: float = 0.0
	var count: int = 0
	for _cycle in cycles:
		var elapsed: float = 0.0
		while elapsed < duration:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			fps_sum += Engine.get_frames_per_second()
			count += 1
	if count == 0:
		return 0.0
	return fps_sum / count


## Spawn [STRESS_PARTICLE_COUNT] GPUParticles2D as children of this node (Issue #1504).
## Returns the spawned nodes so they can be cleaned up after sampling.
func _spawn_stress_particles() -> Array:
	var nodes: Array = []
	var viewport_size := get_viewport().get_visible_rect().size
	for i in STRESS_PARTICLE_COUNT:
		var p := GPUParticles2D.new()
		p.emitting = true
		p.amount = 16
		p.lifetime = 0.5
		p.explosiveness = 0.0
		p.position = Vector2(
			randf_range(0.0, viewport_size.x),
			randf_range(0.0, viewport_size.y)
		)
		add_child(p)
		nodes.append(p)
	return nodes


## Spawn [STRESS_LIGHT_COUNT] PointLight2D nodes (Issue #1504).
func _spawn_stress_lights() -> Array:
	var nodes: Array = []
	var viewport_size := get_viewport().get_visible_rect().size
	for i in STRESS_LIGHT_COUNT:
		var l := PointLight2D.new()
		l.energy = 1.5
		l.texture_scale = 2.0
		l.position = Vector2(
			randf_range(0.0, viewport_size.x),
			randf_range(0.0, viewport_size.y)
		)
		add_child(l)
		nodes.append(l)
	return nodes


## Spawn [STRESS_ENEMY_COUNT] Enemy.tscn instances (Issue #1504).
## Enemies are added as children of this node and configured to destroy on death.
## Returns the spawned nodes for cleanup.
func _spawn_stress_enemies() -> Array:
	var nodes: Array = []
	var enemy_scene: PackedScene = load("res://scenes/objects/Enemy.tscn")
	if enemy_scene == null:
		return nodes
	var viewport_size := get_viewport().get_visible_rect().size
	for i in STRESS_ENEMY_COUNT:
		var enemy: Node2D = enemy_scene.instantiate()
		enemy.global_position = Vector2(
			randf_range(viewport_size.x * 0.1, viewport_size.x * 0.9),
			randf_range(viewport_size.y * 0.1, viewport_size.y * 0.9)
		)
		enemy.set("destroy_on_death", true)
		add_child(enemy)
		nodes.append(enemy)
	return nodes


## Free all nodes in [nodes] that are still valid (Issue #1504).
func _cleanup_stress_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
