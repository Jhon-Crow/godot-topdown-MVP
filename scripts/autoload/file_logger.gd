extends Node
## Autoload singleton for logging to a file next to the executable.
##
## This logger automatically captures print output and errors,
## writing them to a log file for debugging exported builds.
## The log file is created in the same directory as the executable.

## The log file handle.
var _log_file: FileAccess = null

## Path to the log file.
var _log_path: String = ""

## Whether logging is enabled.
var _logging_enabled: bool = true

## Buffer for log messages before file is ready.
var _log_buffer: Array[String] = []

## Maximum buffer size before flush.
const MAX_BUFFER_SIZE: int = 100


func _ready() -> void:
	_setup_log_file()
	_log_startup_info()


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
	log_info("-" .repeat(60))


## Close the log file properly.
func _close_log_file() -> void:
	if _log_file != null:
		log_info("-" .repeat(60))
		log_info("GAME LOG ENDED: %s" % Time.get_datetime_string_from_system())
		log_info("=" .repeat(60))
		_log_file.close()
		_log_file = null


## Write a message to the log file with timestamp.
func _write_log(level: String, message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	var log_line := "[%s] [%s] %s" % [timestamp, level, message]

	# Also print to console
	print(log_line)

	if not _logging_enabled:
		return

	if _log_file != null:
		_log_file.store_line(log_line)
		_log_file.flush()
	else:
		# Buffer messages if file not ready yet
		_log_buffer.append(log_line)
		if _log_buffer.size() > MAX_BUFFER_SIZE:
			_log_buffer.pop_front()


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
