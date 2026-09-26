@tool
extends EditorExportPlugin
## Packages the selected resource. Dependency exporters retain ownership of native binaries.

func _get_name() -> String:
	return "GameExtrakit"

func _export_begin(_features: PackedStringArray, is_debug: bool, _path: String,
		_flags: int) -> void:
	var path: String = ProjectSettings.get_setting("game_extrakit/config_path", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("GameExtrakit: select a configuration before exporting.")
		return
	var config := load(path) as GEXConfig
	if config == null:
		push_error("GameExtrakit: configuration is not GEXConfig.")
		return
	for issue in config.validate():
		push_error("GameExtrakit: " + issue)
	if config.mock_enabled and not is_debug and not config.allow_mock_in_release:
		push_error("GameExtrakit: mock is blocked in this release; runtime will reject it.")
	# Export filters can omit an otherwise unreferenced Resource. Convert the whole embedded
	# catalog to text and add it at the configured path, keeping script dependencies explicit.
	add_file(path, FileAccess.get_file_as_bytes(path), false)

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://addons/game_extrakit/editor/"):
		skip()
