extends Node
## Autoload singleton for logging to a file next to the executable.
##
## This logger automatically captures print output and errors,
## writing them to a log file for debugging exported builds.
## The log file is created in the same directory as the executable.
##
## Performance: writes are batched and flushed every FLUSH_INTERVAL seconds
## (Issue #885). Error-level messages are flushed immediately.

## The log file handle.
var _log_file: FileAccess = null

## Path to the log file.
var _log_path: String = ""

## Whether logging is enabled (controlled by ExperimentalSettings, Issue #848).
## When false, no log file is written and console output is suppressed for performance.
var _logging_enabled: bool = true

## Buffer for log messages before file is ready.
var _log_buffer = []

## Maximum buffer size before flush.
const MAX_BUFFER_SIZE: int = 100

## Write buffer: accumulates log lines between timed flushes (Issue #885).
var _write_buffer: Array[String] = []

## How often (in seconds) to flush buffered writes to disk (Issue #885).
const FLUSH_INTERVAL: float = 1.0

## Timer node that triggers periodic batch flush (Issue #885).
var _flush_timer: Timer = null

## When true, every _write_log call flushes immediately instead of batching.
## Used during fragile windows (startup, scene reload) so a hard crash leaves
## a complete log file (Issue #1927). Disabled automatically after a short
## window to avoid FPS impact during normal gameplay.
var _immediate_flush: bool = true

## Tree time (msec) at which immediate-flush mode auto-disables.
var _immediate_flush_until_msec: int = 0

## How long (in milliseconds) immediate-flush stays active after startup
## or after force_immediate_flush_window() is called (Issue #1927).
const IMMEDIATE_FLUSH_WINDOW_MSEC: int = 10000


func _ready() -> void:
	_setup_flush_timer()
	_setup_log_file()
	_log_startup_info()
	# Issue #1927: keep flushing on every write for the first few seconds so a
	# hard crash during startup or first scene change still produces a usable log.
	_immediate_flush = true
	_immediate_flush_until_msec = Time.get_ticks_msec() + IMMEDIATE_FLUSH_WINDOW_MSEC


## Create and start the periodic flush timer (Issue #885).
func _setup_flush_timer() -> void:
	_flush_timer = Timer.new()
	_flush_timer.wait_time = FLUSH_INTERVAL
	_flush_timer.autostart = true
	_flush_timer.one_shot = false
	add_child(_flush_timer)
	_flush_timer.timeout.connect(_flush_write_buffer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_close_log_file()


## Setup the log file in the same directory as the executable.
func _setup_log_file() -> void:
	# Get the directory where the executable is located
	var exe_path := OS.get_executable_path()
	var exe_dir := exe_path.get_base_dir()

	# Create timestamp for log file name
	var datetime := Time.get_datetime_dict_from_system()
	var timestamp := "%04d%02d%02d_%02d%02d%02d" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]
	]

	# Try to create log file next to executable first
	_log_path = exe_dir.path_join("game_log_%s.txt" % timestamp)

	# Try to open the log file
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)

	if _log_file == null:
		# Fallback to user:// directory if we can't write next to executable
		_log_path = "user://game_log_%s.txt" % timestamp
		_log_file = FileAccess.open(_log_path, FileAccess.WRITE)

		if _log_file == null:
			# Last resort - just print to console
			_logging_enabled = false
			push_error("FileLogger: Could not create log file at either location")
			return

	# Flush any buffered messages
	for msg in _log_buffer:
		_log_file.store_line(msg)
	_log_buffer.clear()


## Log startup information about the game and system.
func _log_startup_info() -> void:
	log_info("=" .repeat(60))
	log_info("GAME LOG STARTED")
	log_info("=" .repeat(60))
	log_info("Timestamp: %s" % Time.get_datetime_string_from_system())
	log_info("Log file: %s" % _log_path)
	log_info("Executable: %s" % OS.get_executable_path())
	log_info("OS: %s" % OS.get_name())
	log_info("Debug build: %s" % OS.is_debug_build())
	log_info("Engine version: %s" % Engine.get_version_info().get("string", "unknown"))
	log_info("Project: %s" % ProjectSettings.get_setting("application/config/name", "unknown"))
	_log_build_info()
	log_info("-" .repeat(60))


## Log build information (branch, commit, date) from build_info.cfg if it exists.
func _log_build_info() -> void:
	const BUILD_INFO_PATH: String = "res://build_info.cfg"
	# Use FileAccess instead of ResourceLoader.exists() — ResourceLoader does not
	# recognise plain .cfg files as Godot resources and always returns false for them
	# even when they are packed into the PCK via include_filter (Issue #1578).
	if not FileAccess.file_exists(BUILD_INFO_PATH):
		log_info("Build info: not available (build_info.cfg not found)")
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(BUILD_INFO_PATH)
	if err != OK:
		log_info("Build info: not available (failed to load build_info.cfg)")
		return
	var branch: String = cfg.get_value("build", "branch", "unknown")
	var commit: String = cfg.get_value("build", "commit", "unknown")
	var date: String = cfg.get_value("build", "date", "unknown")
	log_info("Build branch: %s" % branch)
	log_info("Build commit: %s" % commit)
	log_info("Build date: %s" % date)


## Close the log file properly.
func _close_log_file() -> void:
	if _log_file != null:
		log_info("-" .repeat(60))
		log_info("GAME LOG ENDED: %s" % Time.get_datetime_string_from_system())
		log_info("=" .repeat(60))
		_flush_write_buffer()
		_log_file.close()
		_log_file = null


## Write a message to the log file with timestamp.
## Writes are batched and flushed every FLUSH_INTERVAL seconds (Issue #885).
## ERROR-level messages bypass the buffer and flush immediately.
## Issue #1293: print() is gated to debug builds only. In release/export builds,
## stdout writes cause variable FPS drops (1–9 fps) depending on how the OS
## handles the unconnected stdout pipe. With 40–70 log messages/second the
## overhead is significant and non-deterministic across launches.
func _write_log(level: String, message: String) -> void:
	if not _logging_enabled:
		return

	var timestamp := Time.get_time_string_from_system()
	var log_line := "[%s] [%s] %s" % [timestamp, level, message]

	# Only print to console in debug builds to avoid FPS drops (Issue #1293).
	if OS.is_debug_build():
		print(log_line)

	if _log_file != null:
		_write_buffer.append(log_line)
		# Flush errors immediately so they are not lost on crash (Issue #885).
		if level == "ERROR":
			_flush_write_buffer()
		elif _immediate_flush:
			# Issue #1927: flush every write while inside the immediate-flush
			# window so logs are not lost on a hard crash during scene reload.
			if _immediate_flush_until_msec != 0 and Time.get_ticks_msec() > _immediate_flush_until_msec:
				_immediate_flush = false
			else:
				_flush_write_buffer()
	else:
		# Buffer messages if file not ready yet
		_log_buffer.append(log_line)
		if _log_buffer.size() > MAX_BUFFER_SIZE:
			_log_buffer.pop_front()


## Re-arm the immediate-flush window (Issue #1927).
## Call this just before risky operations like scene reload or weapon swap so
## that a subsequent hard crash leaves a complete log file on disk.
func force_immediate_flush_window() -> void:
	_immediate_flush = true
	_immediate_flush_until_msec = Time.get_ticks_msec() + IMMEDIATE_FLUSH_WINDOW_MSEC
	_flush_write_buffer()


## Flush the write buffer right now without changing the flush mode (Issue #1927).
## Useful from C# code paths that want to checkpoint the log without taking the
## FPS hit of permanently enabling immediate flushing.
func flush_now() -> void:
	_flush_write_buffer()


## Flush all buffered log lines to disk (Issue #885).
## Called automatically by _flush_timer every FLUSH_INTERVAL seconds,
## immediately for ERROR messages, and on file close.
func _flush_write_buffer() -> void:
	if _log_file == null or _write_buffer.is_empty():
		return
	for line in _write_buffer:
		_log_file.store_line(line)
	_write_buffer.clear()
	_log_file.flush()


## Log an info message.
func log_info(message: String) -> void:
	_write_log("INFO", message)


## Log a warning message.
func log_warning(message: String) -> void:
	_write_log("WARN", message)


## Log an error message.
func log_error(message: String) -> void:
	_write_log("ERROR", message)


## Log a debug message (only in debug builds).
func log_debug(message: String) -> void:
	if OS.is_debug_build():
		_write_log("DEBUG", message)


## Log an enemy-specific message.
func log_enemy(enemy_name: String, message: String) -> void:
	_write_log("ENEMY", "[%s] %s" % [enemy_name, message])


## Log an AI state change.
func log_ai_state(enemy_name: String, old_state: String, new_state: String) -> void:
	_write_log("AI", "[%s] State: %s -> %s" % [enemy_name, old_state, new_state])


## Get the path to the current log file.
func get_log_path() -> String:
	return _log_path


## Check if logging is enabled and working.
func is_logging_enabled() -> bool:
	return _logging_enabled and _log_file != null


## Enable or disable logging (Issue #848).
## Called by ExperimentalSettings when the logging toggle changes.
func set_logging_enabled(enabled: bool) -> void:
	_logging_enabled = enabled


## Alias methods for compatibility with different calling conventions.
## These allow calling FileLogger.info() instead of FileLogger.log_info().
func info(message: String) -> void:
	log_info(message)


func warning(message: String) -> void:
	log_warning(message)


func warn(message: String) -> void:
	log_warning(message)


func error(message: String) -> void:
	log_error(message)


func debug(message: String) -> void:
	log_debug(message)
