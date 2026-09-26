class_name GEXPlatformAdapter
extends Node
## Adapter boundary. Request arguments and native values stay private to runtime.

signal conflict_detected(conflict: GEXTypes.SaveConflict)
signal saved_game_modified(metadata: GEXTypes.SavedGameMetadata)
signal activity_received(activity: GEXTypes.NativeActivity)
signal session_observed(player_id: String, authenticated: bool)

var config: GEXConfig
var provider: GEXTypes.Provider = GEXTypes.Provider.NONE
var generation: int = 0
var capabilities := GEXTypes.Capabilities.new()
var pending: Array[GEXNativeReply] = []
var closed: bool = false

func setup(value: GEXConfig) -> GEXResult:
	config = value
	process_mode = Node.PROCESS_MODE_ALWAYS
	capabilities.provider = provider
	return GEXResult.new()

func execute(_operation: String, _arguments: Dictionary) -> GEXResult:
	return GEXResult.fail("UNSUPPORTED_OPERATION")

func invalidate_session(new_generation: int) -> void:
	generation = new_generation
	for reply in pending.duplicate():
		reply.cancel("SESSION_CHANGED")

func shutdown() -> void:
	closed = true
	invalidate_session(generation + 1)

func _exit_tree() -> void:
	shutdown()

func native_ui_state() -> GEXTypes.NativeUiState:
	var state := GEXTypes.NativeUiState.new()
	state.provider = provider
	return state

func make_reply() -> GEXNativeReply:
	var reply := GEXNativeReply.new()
	pending.append(reply)
	var timer := get_tree().create_timer(config.timeout_seconds, true, false, true)
	timer.timeout.connect(reply.cancel.bind("TIMEOUT"))
	return reply

func wait_reply(reply: GEXNativeReply) -> GEXNativeReply:
	await reply.wait()
	pending.erase(reply)
	return reply

func reply_failure(reply: GEXNativeReply, mutation: bool = false) -> GEXResult:
	if reply.error_code.is_empty():
		return null
	if mutation and reply.error_code in ["TIMEOUT", "CANCELLED", "SESSION_CHANGED"]:
		return GEXResult.uncertain(reply.error_code, "Native operation may still complete.")
	return GEXResult.fail(reply.error_code)

func achievement_key(native_id: String) -> String:
	for item in config.achievements:
		if item.native_id(provider) == native_id:
			return item.key
	return ""

func leaderboard_key(native_id: String) -> String:
	for item in config.leaderboards:
		if item.native_id(provider) == native_id:
			return item.key
	return ""

func logical_slot(native_name: String) -> String:
	return native_name.trim_prefix(config.slot_prefix)
