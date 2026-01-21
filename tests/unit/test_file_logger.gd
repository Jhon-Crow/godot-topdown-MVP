extends GutTest
## Unit tests for FileLogger autoload.
##
## Tests the logging functionality including message formatting,
## log levels, and buffer management.


# Mock class that mirrors FileLogger's testable functionality
# without actual file system operations
class MockFileLogger:
	## Whether logging is enabled
	var _logging_enabled: bool = true

	## Path to the log file (simulated)
	var _log_path: String = ""

	## Simulated file open state
	var _file_open: bool = false

	## Buffer for log messages
	var _log_buffer: Array[String] = []

	## Maximum buffer size
	const MAX_BUFFER_SIZE: int = 100

	## Captured log messages for testing
	var logged_messages: Array[String] = []

	## Whether this is a debug build (can be set for testing)
	var _is_debug_build: bool = true


	func setup_log(path: String) -> void:
		_log_path = path
		_file_open = true
		# Flush buffer
		for msg in _log_buffer:
			logged_messages.append(msg)
		_log_buffer.clear()


	func close_log() -> void:
		_file_open = false


	func _write_log(level: String, message: String) -> void:
		var timestamp := "12:00:00"  # Fixed timestamp for testing
		var log_line := "[%s] [%s] %s" % [timestamp, level, message]

		if not _logging_enabled:
			return

		if _file_open:
			logged_messages.append(log_line)
		else:
			_log_buffer.append(log_line)
			if _log_buffer.size() > MAX_BUFFER_SIZE:
				_log_buffer.pop_front()


	func log_info(message: String) -> void:
		_write_log("INFO", message)


	func log_warning(message: String) -> void:
		_write_log("WARN", message)


	func log_error(message: String) -> void:
		_write_log("ERROR", message)


	func log_debug(message: String) -> void:
		if _is_debug_build:
			_write_log("DEBUG", message)


	func log_enemy(enemy_name: String, message: String) -> void:
		_write_log("ENEMY", "[%s] %s" % [enemy_name, message])


	func log_ai_state(enemy_name: String, old_state: String, new_state: String) -> void:
		_write_log("AI", "[%s] State: %s -> %s" % [enemy_name, old_state, new_state])


	func get_log_path() -> String:
		return _log_path


	func is_logging_enabled() -> bool:
		return _logging_enabled and _file_open


	func set_logging_enabled(enabled: bool) -> void:
		_logging_enabled = enabled


var logger: MockFileLogger


func before_each() -> void:
	logger = MockFileLogger.new()
	logger.setup_log("user://test_log.txt")


func after_each() -> void:
	logger = null


# ============================================================================
# Basic Logging Tests
# ============================================================================


func test_log_info_creates_message() -> void:
	logger.log_info("Test info message")

	assert_eq(logger.logged_messages.size(), 1, "Should have 1 logged message")
	assert_true(logger.logged_messages[0].contains("[INFO]"),
		"Message should contain INFO level")
	assert_true(logger.logged_messages[0].contains("Test info message"),
		"Message should contain the original text")


func test_log_warning_creates_message() -> void:
	logger.log_warning("Test warning message")

	assert_eq(logger.logged_messages.size(), 1, "Should have 1 logged message")
	assert_true(logger.logged_messages[0].contains("[WARN]"),
		"Message should contain WARN level")
	assert_true(logger.logged_messages[0].contains("Test warning message"),
		"Message should contain the original text")


func test_log_error_creates_message() -> void:
	logger.log_error("Test error message")

	assert_eq(logger.logged_messages.size(), 1, "Should have 1 logged message")
	assert_true(logger.logged_messages[0].contains("[ERROR]"),
		"Message should contain ERROR level")
	assert_true(logger.logged_messages[0].contains("Test error message"),
		"Message should contain the original text")


func test_log_debug_in_debug_build() -> void:
	logger._is_debug_build = true
	logger.log_debug("Test debug message")

	assert_eq(logger.logged_messages.size(), 1, "Should have 1 logged message in debug build")
	assert_true(logger.logged_messages[0].contains("[DEBUG]"),
		"Message should contain DEBUG level")


func test_log_debug_in_release_build() -> void:
	logger._is_debug_build = false
	logger.log_debug("Test debug message")

	assert_eq(logger.logged_messages.size(), 0, "Should have no logged messages in release build")


# ============================================================================
# Specialized Logging Tests
# ============================================================================


func test_log_enemy_formats_correctly() -> void:
	logger.log_enemy("Enemy1", "Spotted player")

	assert_eq(logger.logged_messages.size(), 1)
	assert_true(logger.logged_messages[0].contains("[ENEMY]"),
		"Message should contain ENEMY level")
	assert_true(logger.logged_messages[0].contains("[Enemy1]"),
		"Message should contain enemy name in brackets")
	assert_true(logger.logged_messages[0].contains("Spotted player"),
		"Message should contain the action text")


func test_log_ai_state_formats_correctly() -> void:
	logger.log_ai_state("Guard1", "IDLE", "PURSUING")

	assert_eq(logger.logged_messages.size(), 1)
	assert_true(logger.logged_messages[0].contains("[AI]"),
		"Message should contain AI level")
	assert_true(logger.logged_messages[0].contains("[Guard1]"),
		"Message should contain enemy name")
	assert_true(logger.logged_messages[0].contains("State: IDLE -> PURSUING"),
		"Message should show state transition")


# ============================================================================
# Log Path Tests
# ============================================================================


func test_get_log_path_returns_set_path() -> void:
	assert_eq(logger.get_log_path(), "user://test_log.txt",
		"Should return the set log path")


func test_empty_log_path_initially() -> void:
	var new_logger := MockFileLogger.new()
	assert_eq(new_logger.get_log_path(), "", "Log path should be empty before setup")


# ============================================================================
# Logging Enabled State Tests
# ============================================================================


func test_is_logging_enabled_when_file_open() -> void:
	assert_true(logger.is_logging_enabled(),
		"Logging should be enabled when file is open and logging is enabled")


func test_is_logging_disabled_when_logging_turned_off() -> void:
	logger.set_logging_enabled(false)

	assert_false(logger.is_logging_enabled(),
		"Logging should be disabled when logging is turned off")


func test_is_logging_disabled_when_file_closed() -> void:
	logger.close_log()

	assert_false(logger.is_logging_enabled(),
		"Logging should be disabled when file is closed")


func test_messages_not_logged_when_disabled() -> void:
	logger.set_logging_enabled(false)
	logger.log_info("This should not be logged")

	assert_eq(logger.logged_messages.size(), 0,
		"No messages should be logged when logging is disabled")


# ============================================================================
# Buffer Tests
# ============================================================================


func test_buffer_used_when_file_not_open() -> void:
	var new_logger := MockFileLogger.new()
	# File not opened yet
	new_logger.log_info("Buffered message")

	assert_eq(new_logger._log_buffer.size(), 1,
		"Message should be buffered when file not open")
	assert_eq(new_logger.logged_messages.size(), 0,
		"Message should not be in logged_messages yet")


func test_buffer_flushed_on_file_open() -> void:
	var new_logger := MockFileLogger.new()
	new_logger.log_info("Buffered message 1")
	new_logger.log_info("Buffered message 2")

	# Now open file
	new_logger.setup_log("user://new_log.txt")

	assert_eq(new_logger._log_buffer.size(), 0,
		"Buffer should be empty after flush")
	assert_eq(new_logger.logged_messages.size(), 2,
		"Buffered messages should be in logged_messages")


func test_buffer_max_size_limit() -> void:
	var new_logger := MockFileLogger.new()

	# Fill buffer beyond max
	for i in range(MockFileLogger.MAX_BUFFER_SIZE + 10):
		new_logger.log_info("Message %d" % i)

	assert_eq(new_logger._log_buffer.size(), MockFileLogger.MAX_BUFFER_SIZE,
		"Buffer should not exceed max size")


# ============================================================================
# Message Format Tests
# ============================================================================


func test_message_contains_timestamp() -> void:
	logger.log_info("Test message")

	assert_true(logger.logged_messages[0].contains("[12:00:00]"),
		"Message should contain timestamp in brackets")


func test_message_format_structure() -> void:
	logger.log_info("Test message")

	# Expected format: [timestamp] [LEVEL] message
	var msg := logger.logged_messages[0]
	assert_true(msg.begins_with("["), "Message should start with timestamp bracket")
	assert_true(msg.contains("] ["), "Message should have separator between timestamp and level")


# ============================================================================
# Multiple Messages Tests
# ============================================================================


func test_multiple_messages_logged_in_order() -> void:
	logger.log_info("First")
	logger.log_warning("Second")
	logger.log_error("Third")

	assert_eq(logger.logged_messages.size(), 3)
	assert_true(logger.logged_messages[0].contains("First"))
	assert_true(logger.logged_messages[1].contains("Second"))
	assert_true(logger.logged_messages[2].contains("Third"))


func test_mixed_log_levels() -> void:
	logger.log_info("Info message")
	logger.log_warning("Warning message")
	logger.log_error("Error message")
	logger.log_debug("Debug message")
	logger.log_enemy("Enemy", "Action")
	logger.log_ai_state("Enemy", "A", "B")

	assert_eq(logger.logged_messages.size(), 6, "All 6 messages should be logged")
