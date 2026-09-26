@tool
extends VBoxContainer

const Validator = preload("configuration_validator.gd")
signal configuration_selected(path: String)
var config: GEXConfig
var _path: String = ""
var _path_label: Label
var _form: VBoxContainer
var _catalogs: VBoxContainer
var _diagnostics: RichTextLabel
var _file_dialog: EditorFileDialog
var _save_dialog: EditorFileDialog

func _ready() -> void:
	name = "GameExtrakit"
	custom_minimum_size = Vector2(300, 300)
	var title := Label.new()
	title.text = "GameExtrakit  ·  0.1.0"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_button(toolbar, "Nueva", _new_config)
	_button(toolbar, "Abrir", func() -> void: _file_dialog.popup_centered_ratio(0.6))
	_button(toolbar, "Guardar", _save)
	_path_label = Label.new()
	_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_path_label)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	_form = _scroll_tab(tabs, "Configuración")
	_catalogs = _scroll_tab(tabs, "Catálogos")
	var diagnostics := VBoxContainer.new()
	diagnostics.name = "Diagnóstico"
	tabs.add_child(diagnostics)
	_button(diagnostics, "Actualizar diagnóstico", _diagnose)
	_diagnostics = RichTextLabel.new()
	_diagnostics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diagnostics.selection_enabled = true
	diagnostics.add_child(_diagnostics)
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = ["*.tres,*.res ; Game services configuration"]
	_file_dialog.file_selected.connect(load_config)
	add_child(_file_dialog)
	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = ["*.tres ; Text resource"]
	_save_dialog.current_file = "game_services.tres"
	_save_dialog.file_selected.connect(_save_to)
	add_child(_save_dialog)
	var path: String = ProjectSettings.get_setting("game_extrakit/config_path", "")
	if not path.is_empty() and ResourceLoader.exists(path):
		load_config(path)
	else:
		_path_label.text = "Crea una configuración o abre una existente."

func load_config(path: String) -> void:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as GEXConfig
	if loaded == null:
		_path_label.text = "El recurso no es una configuración de GameExtrakit."
		return
	config = loaded
	_path = path
	configuration_selected.emit(path)
	_rebuild()

func _new_config() -> void:
	config = GEXConfig.new()
	_path = ""
	_rebuild()

func _rebuild() -> void:
	for container in [_form, _catalogs]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_path_label.text = _path if not _path.is_empty() else "Nueva configuración · sin guardar"
	for property: Dictionary in config.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_GROUP:
			_heading(_form, str(property.name))
		elif int(property.usage) & PROPERTY_USAGE_EDITOR and \
				int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and \
				int(property.type) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			_field(_form, config, property)
	_heading(_form, "Game ID Android")
	var note := Label.new()
	note.text = "Configúralo en Proyecto → Exportar → Android → Godot Play Game Services."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(note)
	_heading(_catalogs, "Logros")
	_button(_catalogs, "+ Logro", func() -> void:
		config.achievements.append(GEXAchievementDefinition.new())
		_rebuild())
	for index in config.achievements.size():
		_catalog_item(config.achievements[index], index, true)
	_heading(_catalogs, "Leaderboards")
	_button(_catalogs, "+ Leaderboard", func() -> void:
		config.leaderboards.append(GEXLeaderboardDefinition.new())
		_rebuild())
	for index in config.leaderboards.size():
		_catalog_item(config.leaderboards[index], index, false)
	_diagnose()

func _catalog_item(item: Resource, index: int, achievement: bool) -> void:
	var panel := VBoxContainer.new()
	_catalogs.add_child(panel)
	_heading(panel, "%s %d" % ["Logro" if achievement else "Leaderboard", index + 1])
	if item != null:
		for property: Dictionary in item.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_EDITOR and \
					int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and \
					int(property.type) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
				_field(panel, item, property)
		_button(panel, "Abrir en Inspector (opciones completas)",
			func() -> void: EditorInterface.edit_resource(item))
	_button(panel, "Quitar entrada", func() -> void:
		if achievement:
			config.achievements.remove_at(index)
		else:
			config.leaderboards.remove_at(index)
		_rebuild())

func _field(parent: VBoxContainer, resource: Resource, property: Dictionary) -> void:
	var label := Label.new()
	label.text = str(property.name).capitalize()
	label.tooltip_text = str(property.name)
	parent.add_child(label)
	var key: String = property.name
	match int(property.type):
		TYPE_BOOL:
			var input := CheckButton.new()
			input.text = "Activado"
			input.button_pressed = bool(resource.get(key))
			input.toggled.connect(func(value: bool) -> void: resource.set(key, value))
			parent.add_child(input)
		TYPE_INT, TYPE_FLOAT:
			var input := SpinBox.new()
			input.allow_greater = true
			input.allow_lesser = true
			input.step = 1.0 if int(property.type) == TYPE_INT else 0.05
			input.value = float(resource.get(key))
			input.value_changed.connect(func(value: float) -> void:
				resource.set(key, int(value) if int(property.type) == TYPE_INT else value))
			parent.add_child(input)
		TYPE_STRING:
			var input := LineEdit.new()
			input.text = str(resource.get(key))
			input.text_changed.connect(func(value: String) -> void: resource.set(key, value))
			parent.add_child(input)

func _save() -> void:
	if config == null:
		return
	if _path.is_empty():
		_save_dialog.popup_centered_ratio(0.6)
	else:
		_save_to(_path)

func _save_to(path: String) -> void:
	if config == null:
		return
	var error := ResourceSaver.save(config, path)
	if error != OK:
		_path_label.text = "No se pudo guardar: " + error_string(error)
		return
	_path = path
	_path_label.text = path
	configuration_selected.emit(path)
	EditorInterface.get_resource_filesystem().scan()
	_diagnose()

func _diagnose() -> void:
	_diagnostics.text = "\n\n".join(Validator.diagnose(config))

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func _heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	parent.add_child(label)

func _scroll_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content
