extends Control
## Device lab: only logs status/capabilities, never proofs, player IDs or save payloads.

var services: GEXGameServices
var _log: RichTextLabel
var _status: Label
var _achievement_key: String = "first_win"
var _board_key: String = "high_score"
var _last_conflict: String = ""
var _record_events: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var title := Label.new()
	title.text = "GameExtrakit / Service Lab"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var explanation := Label.new()
	explanation.text = "Inicia en simulación. Para dispositivo, selecciona una configuración real en el dock."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(explanation)
	var toolbar := HFlowContainer.new()
	root.add_child(toolbar)
	_button(toolbar, "Reiniciar simulador", _start_mock)
	_button(toolbar, "Usar configuración del proyecto", _start_project)
	_button(toolbar, "Capacidades", _capabilities)
	var events := CheckButton.new()
	events.text = "Registrar interrupciones (sin datos personales)"
	events.button_pressed = true
	events.toggled.connect(func(value: bool) -> void: _record_events = value)
	toolbar.add_child(events)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 330
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(controls)
	for entry in [
		["Autenticar", "authenticate"], ["Actualizar sesión", "refresh_auth_state"],
		["Perfil", "get_player"], ["Amigos (sin pedir permiso)", "list_friends"],
		["Amigos (solicitar permiso)", "friends_permission"],
		["Definiciones de logros", "list_achievement_definitions"],
		["Progreso de logros", "list_player_achievements"],
		["Desbloquear logro", "unlock"], ["Progreso 50 %", "progress"],
		["Listar rankings", "list_leaderboards"], ["Enviar 12345 puntos", "score"],
		["Puntuación propia", "own"], ["Top 10", "top"], ["Alrededor del jugador", "around"],
		["Guardar slot de demo", "save"], ["Cargar slot de demo", "load"],
		["Listar guardados", "list_saved_games"], ["Eliminar slot de demo", "delete"],
		["UI de logros", "show_achievements"], ["UI de rankings", "show_leaderboards"],
		["UI del ranking", "show_board"], ["Overlay de plataforma", "show_platform_overlay"],
		["Verificar identidad en backend", "verify_player_identity"],
		["Simular conflicto", "conflict"], ["Resolver conflicto con bytes demo", "resolve"],
		["Simular cierre de overlay", "close_overlay"], ["Simular timeout siguiente", "timeout"],
	]:
		_button(controls, entry[0], _operate.bind(entry[1]))
	var pause := CheckButton.new()
	pause.text = "Token de pausa manual"
	pause.toggled.connect(func(value: bool) -> void:
		if services != null:
			services.set_pause_token("demo/menu", value))
	controls.add_child(pause)
	_log = RichTextLabel.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.selection_enabled = true
	_log.scroll_following = true
	split.add_child(_log)
	_start_mock()
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://test-results/service-lab.png")
		get_tree().quit()

func _start_mock() -> void:
	var config := GEXConfig.new()
	config.mock_enabled = true
	config.timeout_seconds = 2.0
	config.manage_scene_tree_pause = true
	var achievement := GEXAchievementDefinition.new()
	achievement.key = "first_win"
	achievement.title = "Primera victoria"
	achievement.incremental = true
	achievement.android_total_steps = 10
	config.achievements.append(achievement)
	var leaderboard := GEXLeaderboardDefinition.new()
	leaderboard.key = "high_score"
	leaderboard.title = "Mejor puntuación"
	config.leaderboards.append(leaderboard)
	_start(config)

func _start_project() -> void:
	var path: String = ProjectSettings.get_setting("game_extrakit/config_path", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		_append("Selecciona y guarda la configuración desde el dock GameExtrakit.")
		return
	var config := load(path) as GEXConfig
	if config == null:
		_append("El recurso seleccionado no es GEXConfig.")
		return
	_start(config, true)

func _start(config: GEXConfig, use_shared: bool = false) -> void:
	if services != null:
		for pair in [["auth_state_changed", _on_auth_state],
				["interruption_changed", _on_interruption],
				["native_ui_state_changed", _on_native_ui],
				["save_conflict_detected", _on_conflict]]:
			if services.is_connected(pair[0], pair[1]):
				services.disconnect(pair[0], pair[1])
		if services.get_parent() == self:
			services.shutdown()
			services.queue_free()
	services = get_node_or_null("/root/GameServices") as GEXGameServices if use_shared else null
	if services == null:
		services = GEXGameServices.new()
		services.auto_initialize = false
		services.name = "LabServices"
		add_child(services)
	var result := services.initialize(config)
	if not config.achievements.is_empty():
		_achievement_key = config.achievements[0].key
	if not config.leaderboards.is_empty():
		_board_key = config.leaderboards[0].key
	services.auth_state_changed.connect(_on_auth_state)
	services.interruption_changed.connect(_on_interruption)
	services.native_ui_state_changed.connect(_on_native_ui)
	services.save_conflict_detected.connect(_on_conflict)
	_status.text = GEXTypes.Provider.keys()[services.get_provider()]
	_report("initialize", result)

func _on_auth_state(state: GEXTypes.AuthState) -> void:
	_status.text = "%s · %s" % [GEXTypes.Provider.keys()[services.get_provider()],
		GEXTypes.AuthState.keys()[state]]

func _on_interruption(state: GEXTypes.InterruptionState) -> void:
	if _record_events:
		_append("GODOT_LIFECYCLE / motivos: " + str(state.pause_reasons))

func _on_native_ui(state: GEXTypes.NativeUiState) -> void:
	if _record_events:
		_append("UI %s / %s" % [state.source, GEXTypes.Presentation.keys()[state.presentation]])

func _on_conflict(conflict: GEXTypes.SaveConflict) -> void:
	_last_conflict = conflict.token
	_append("Conflicto recibido: %d versiones; token retenido sin registrar." % conflict.versions.size())

func _operate(operation: String) -> void:
	var result: GEXResult
	match operation:
		"unlock": result = await services.unlock_achievement(_achievement_key)
		"progress": result = await services.set_achievement_progress(_achievement_key, 0.5)
		"score": result = await services.submit_score(_board_key, 12345)
		"own": result = await services.get_player_score(_board_key)
		"top": result = await services.get_top_scores(_board_key)
		"around": result = await services.get_scores_around_player(_board_key)
		"save": result = await services.save_game("game_extrakit_demo", PackedByteArray([0, 128, 255]))
		"load": result = await services.load_game("game_extrakit_demo")
		"delete": result = await services.delete_saved_game("game_extrakit_demo")
		"show_board": result = await services.show_leaderboard(_board_key)
		"friends_permission": result = await services.list_friends(25, true)
		"resolve": result = await services.resolve_save_conflict(_last_conflict, PackedByteArray([1, 2, 3]))
		"conflict", "close_overlay", "timeout":
			var simulator := services.get_simulator()
			if simulator == null:
				_append("Acción disponible solo en simulación.")
				return
			if operation == "conflict":
				simulator.simulate_conflict("game_extrakit_demo")
			elif operation == "close_overlay":
				simulator.simulate_presentation(false)
			else:
				simulator.drop_next_reply = true
			return
		_: result = await services.call(operation)
	_report(operation, result)

func _capabilities() -> void:
	var capabilities := services.get_capabilities()
	_append("Proveedor: %s; resolución de conflictos: %s; confirmación de guardado: %s" % [
		GEXTypes.Provider.keys()[capabilities.provider], capabilities.can_resolve_save_conflicts,
		capabilities.can_confirm_save_completion])
	_append("Destinos: " + str(capabilities.available_native_destinations))
	_append("\n".join(capabilities.limitations))

func _report(operation: String, result: GEXResult) -> void:
	_append("#%d %s → %s %s" % [result.request_id, operation,
		GEXTypes.Status.keys()[result.status], result.error_code])
	if not result.message.is_empty():
		_append(result.message)
	if operation == "load" and result.is_ok():
		_append("Bytes de demo coinciden: " + str(result.bytes == PackedByteArray([0, 128, 255])))
	if not result.entries.is_empty():
		_append("Entradas: %d; rank inicial del proveedor: %d" % [result.entries.size(), result.entries[0].rank])

func _append(text: String) -> void:
	_log.add_text("%d ms  %s\n" % [Time.get_ticks_msec(), text])

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
