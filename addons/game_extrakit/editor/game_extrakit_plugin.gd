@tool
extends EditorPlugin

const Dock = preload("game_extrakit_dock.gd")
const ExportCoordinator = preload("export_coordinator.gd")
const AUTOLOAD_PATH := "res://addons/game_extrakit/runtime/game_services.gd"
var _dock: Control
var _exporter: EditorExportPlugin

func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/GameServices"):
		add_autoload_singleton("GameServices", AUTOLOAD_PATH)
		ProjectSettings.set_setting("game_extrakit/owns_autoload", true)
		ProjectSettings.save()
	elif not _is_our_autoload():
		push_warning("GameExtrakit: GameServices name already belongs to another autoload.")

func _disable_plugin() -> void:
	if ProjectSettings.get_setting("game_extrakit/owns_autoload", false) and _is_our_autoload():
		remove_autoload_singleton("GameServices")
	ProjectSettings.set_setting("game_extrakit/owns_autoload", null)
	ProjectSettings.save()

func _is_our_autoload() -> bool:
	var path := str(ProjectSettings.get_setting("autoload/GameServices", "")).trim_prefix("*")
	if path == AUTOLOAD_PATH:
		return true
	if path.begins_with("uid://"):
		return ResourceUID.text_to_id(path) == ResourceLoader.get_resource_uid(AUTOLOAD_PATH)
	return false

func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.configuration_selected.connect(_select_configuration)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_exporter = ExportCoordinator.new()
	add_export_plugin(_exporter)

func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null

func _select_configuration(path: String) -> void:
	ProjectSettings.set_setting("game_extrakit/config_path", path)
	ProjectSettings.add_property_info({"name": "game_extrakit/config_path", "type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE, "hint_string": "*.tres,*.res"})
	ProjectSettings.save()
