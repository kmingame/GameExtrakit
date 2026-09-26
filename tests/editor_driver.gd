@tool
extends EditorPlugin
## Installed only in a disposable fixture by tools/validate.ps1.

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	if EditorInterface.is_plugin_enabled("game_extrakit"):
		EditorInterface.set_plugin_enabled("game_extrakit", false)
	var config := GEXConfig.new()
	config.mock_enabled = true
	config.allow_mock_in_release = true
	var achievement := GEXAchievementDefinition.new()
	achievement.key = "editor_test"
	config.achievements.append(achievement)
	assert(ResourceSaver.save(config, "res://settings.tres") == OK)
	ProjectSettings.set_setting("game_extrakit/config_path", "res://settings.tres")
	EditorInterface.set_plugin_enabled("game_extrakit", true)
	await get_tree().process_frame
	assert(ProjectSettings.has_setting("autoload/GameServices"))
	var dock := _find_dock(EditorInterface.get_base_control())
	assert(dock != null)
	assert(dock.get("config") is GEXConfig)
	assert(dock.get("config").achievements[0].key == "editor_test")
	EditorInterface.set_plugin_enabled("game_extrakit", false)
	await get_tree().process_frame
	assert(not ProjectSettings.has_setting("autoload/GameServices"))
	assert(_find_dock(EditorInterface.get_base_control()) == null)
	EditorInterface.set_plugin_enabled("game_extrakit", true)
	await get_tree().process_frame
	assert(ProjectSettings.has_setting("autoload/GameServices"))
	print("GameExtrakit editor lifecycle: PASS (enable, resource form, disable, reenable)")
	ProjectSettings.set_setting("application/run/main_scene", "res://smoke.tscn")
	ProjectSettings.set_setting("editor_plugins/enabled",
		PackedStringArray(["res://addons/game_extrakit/plugin.cfg"]))
	ProjectSettings.save()
	get_tree().quit()

func _find_dock(node: Node) -> Node:
	if node.name == "GameExtrakit" and node is VBoxContainer:
		return node
	for child in node.get_children():
		var result := _find_dock(child)
		if result != null:
			return result
	return null
