extends Node
## Autoload singleton for managing custom levels.
##
## Handles saving, loading, listing, deleting, exporting, and importing
## custom levels. Levels are stored as JSON files in user://custom_levels/.

## Directory where custom levels are stored.
const CUSTOM_LEVELS_DIR: String = "user://custom_levels/"

## File extension for level files.
const LEVEL_EXTENSION: String = ".json"


func _ready() -> void:
	_ensure_directory_exists()


## Ensure the custom levels directory exists.
func _ensure_directory_exists() -> void:
	if not DirAccess.dir_exists_absolute(CUSTOM_LEVELS_DIR):
		DirAccess.make_dir_recursive_absolute(CUSTOM_LEVELS_DIR)


## Save a LevelData to disk. Returns true on success.
## The filename is derived from the level name (sanitized).
func save_level(data: LevelData) -> bool:
	_ensure_directory_exists()
	var filename: String = _sanitize_filename(data.level_name) + LEVEL_EXTENSION
	var path: String = CUSTOM_LEVELS_DIR + filename
	var json_string: String = data.to_json()

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LevelEditorManager: Failed to open file for writing: %s" % path)
		return false

	file.store_string(json_string)
	file.close()
	return true


## Load a LevelData from disk by filename. Returns null on failure.
func load_level(filename: String) -> LevelData:
	var path: String = CUSTOM_LEVELS_DIR + filename
	if not FileAccess.file_exists(path):
		push_error("LevelEditorManager: File not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LevelEditorManager: Failed to open file: %s" % path)
		return null

	var json_string: String = file.get_as_text()
	file.close()

	var data := LevelData.new()
	if not data.from_json(json_string):
		push_error("LevelEditorManager: Failed to parse level file: %s" % path)
		return null

	return data


## List all custom level filenames.
func list_levels() -> Array[String]:
	_ensure_directory_exists()
	var result: Array[String] = []
	var dir := DirAccess.open(CUSTOM_LEVELS_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(LEVEL_EXTENSION):
			result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	result.sort()
	return result


## Delete a custom level by filename. Returns true on success.
func delete_level(filename: String) -> bool:
	var path: String = CUSTOM_LEVELS_DIR + filename
	if not FileAccess.file_exists(path):
		return false
	var error := DirAccess.remove_absolute(path)
	return error == OK


## Export a level to a shareable JSON string.
func export_level(data: LevelData) -> String:
	return data.to_json()


## Import a level from a JSON string. Returns the LevelData or null on failure.
func import_level(json_string: String) -> LevelData:
	var data := LevelData.new()
	if data.from_json(json_string):
		return data
	return null


## Get the full path to a custom level file.
func get_level_path(filename: String) -> String:
	return CUSTOM_LEVELS_DIR + filename


## Sanitize a string for use as a filename.
func _sanitize_filename(name: String) -> String:
	var sanitized: String = name.strip_edges()
	if sanitized.is_empty():
		sanitized = "untitled"
	# Replace characters not safe in filenames
	sanitized = sanitized.replace("/", "_")
	sanitized = sanitized.replace("\\", "_")
	sanitized = sanitized.replace(":", "_")
	sanitized = sanitized.replace("*", "_")
	sanitized = sanitized.replace("?", "_")
	sanitized = sanitized.replace("\"", "_")
	sanitized = sanitized.replace("<", "_")
	sanitized = sanitized.replace(">", "_")
	sanitized = sanitized.replace("|", "_")
	sanitized = sanitized.to_lower()
	return sanitized
