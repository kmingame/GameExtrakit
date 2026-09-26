class_name GEXInterruptionCoordinator
extends Node
## Owns named tokens, never infers Sidekick visibility from focus notifications.

signal changed(state: GEXTypes.InterruptionState)
var config: GEXConfig
var _focus_lost: bool = false
var _suspended: bool = false
var _presenting: bool = false
var _tokens: Dictionary[String, bool] = {}
var _owns_pause: bool = false
var _was_paused: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _notification(what: int) -> void:
	if config == null:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			set_focus_lost(true)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			set_focus_lost(false)
		NOTIFICATION_APPLICATION_PAUSED:
			set_suspended(true)
		NOTIFICATION_APPLICATION_RESUMED:
			set_suspended(false)

func set_focus_lost(value: bool) -> void:
	if _focus_lost == value:
		return
	_focus_lost = value
	_publish()

func set_suspended(value: bool) -> void:
	if _suspended == value:
		return
	_suspended = value
	_publish()

func set_native_presenting(value: bool) -> void:
	if _presenting == value:
		return
	_presenting = value
	_publish()

## Use a unique game-owned token for menus/manual pauses when tree ownership is enabled.
func set_pause_token(token: String, enabled: bool) -> void:
	if token.is_empty():
		return
	if enabled:
		_tokens[token] = true
	else:
		_tokens.erase(token)
	_publish()

func snapshot() -> GEXTypes.InterruptionState:
	var state := GEXTypes.InterruptionState.new()
	state.focus_lost = _focus_lost
	state.suspended = _suspended
	state.native_presenting = _presenting
	state.pause_reasons = PackedStringArray(_tokens.keys())
	if config != null:
		if _focus_lost and config.pause_on_focus_loss:
			state.pause_reasons.append("game_extrakit/focus")
		if _suspended and config.pause_on_suspend:
			state.pause_reasons.append("game_extrakit/suspension")
		if _presenting and config.pause_on_native_ui:
			state.pause_reasons.append("game_extrakit/native_ui")
	return state

func release_owned_pause() -> void:
	if _owns_pause and is_inside_tree():
		# During shutdown external/menu tokens still belong to the game.
		get_tree().paused = _was_paused or not _tokens.is_empty()
	_owns_pause = false

func _publish() -> void:
	var state := snapshot()
	if config != null and config.manage_scene_tree_pause and is_inside_tree():
		if not state.pause_reasons.is_empty() and not _owns_pause:
			_was_paused = get_tree().paused
			_owns_pause = true
			get_tree().paused = true
		elif state.pause_reasons.is_empty():
			release_owned_pause()
	changed.emit(state)

func _exit_tree() -> void:
	release_owned_pause()
