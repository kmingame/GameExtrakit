class_name GEXGameServices
extends Node
## Common services facade; normally installed as the GameServices autoload.
## Await each operation and inspect result.status, including UNKNOWN.

signal auth_state_changed(state: GEXTypes.AuthState)
signal player_changed(player: GEXTypes.PlayerProfile)
signal capabilities_changed(capabilities: GEXTypes.Capabilities)
signal save_conflict_detected(conflict: GEXTypes.SaveConflict)
signal saved_game_modified(metadata: GEXTypes.SavedGameMetadata)
signal native_ui_state_changed(state: GEXTypes.NativeUiState)
signal interruption_changed(state: GEXTypes.InterruptionState)
signal native_activity_received(activity: GEXTypes.NativeActivity)
signal operation_completed(request_id: int, operation: String, status: GEXTypes.Status,
	error_code: String)
signal _auth_finished

const CONFIG_SETTING := "game_extrakit/config_path"
var _config: GEXConfig
var _adapter: GEXPlatformAdapter
var _requests: GEXRequestCoordinator
var _interruptions: GEXInterruptionCoordinator
var _observer: Timer
var _verifier: GEXIdentityVerifier
var _auth_state: GEXTypes.AuthState = GEXTypes.AuthState.UNKNOWN
var _player: GEXTypes.PlayerProfile
var _ready_for_requests: bool = false
var _auth_busy: bool = false
var _auth_operation: String = ""
var _last_auth_result: GEXResult
var _last_ui := GEXTypes.NativeUiState.new()
var _pending_activities: Array[GEXTypes.NativeActivity] = []
var _failure_sequence: int = -1
## Set false before adding a manually managed instance to the tree.
var auto_initialize: bool = true

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	if _config != null or not auto_initialize:
		return
	var path: String = ProjectSettings.get_setting(CONFIG_SETTING, "")
	if not path.is_empty() and ResourceLoader.exists(path):
		var config := load(path) as GEXConfig
		if config != null:
			initialize(config)

## Initialization never prompts authentication. Reuse this instance for one lifecycle.
func initialize(config: GEXConfig) -> GEXResult:
	if _ready_for_requests:
		return GEXResult.new()
	if _requests != null:
		return _failure("INVALID_CONFIGURATION", "Create a new instance after shutdown.")
	if not is_inside_tree():
		return _failure("NOT_INITIALIZED", "Add GameServices to the tree before initializing.")
	if config == null:
		return _failure("INVALID_CONFIGURATION", "Configuration is missing.")
	var issues := config.validate()
	if not issues.is_empty():
		return _failure("INVALID_CONFIGURATION", "\n".join(issues))
	_config = config.duplicate(true) as GEXConfig
	if _config.mock_enabled:
		if not OS.is_debug_build() and not _config.allow_mock_in_release:
			return _failure("INVALID_CONFIGURATION", "Mock disabled in release builds.")
		_adapter = GEXMockAdapter.new()
	elif OS.get_name() == "Android":
		if not _config.android_enabled:
			return _failure("FEATURE_DISABLED", "Android provider disabled.")
		_adapter = GEXAndroidAdapter.new()
	elif OS.get_name() == "iOS":
		if not _config.apple_enabled:
			return _failure("FEATURE_DISABLED", "Apple provider disabled.")
		_adapter = GEXAppleAdapter.new()
	else:
		return _failure("UNSUPPORTED_PLATFORM", "Enable explicit simulation for desktop.")
	add_child(_adapter)
	var result := _adapter.setup(_config)
	result.provider = _adapter.provider
	if not result.is_ok():
		_adapter.shutdown()
		_adapter.queue_free()
		_adapter = null
		return result
	_requests = GEXRequestCoordinator.new()
	_requests.adapter = _adapter
	add_child(_requests)
	_interruptions = GEXInterruptionCoordinator.new()
	_interruptions.config = _config
	add_child(_interruptions)
	_interruptions.changed.connect(interruption_changed.emit)
	_adapter.session_observed.connect(_on_session_observed)
	_adapter.conflict_detected.connect(save_conflict_detected.emit)
	_adapter.saved_game_modified.connect(saved_game_modified.emit)
	_adapter.activity_received.connect(_on_activity)
	_observer = Timer.new()
	_observer.wait_time = 0.25
	_observer.ignore_time_scale = true
	_observer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_observer)
	_observer.timeout.connect(_observe_native_ui)
	if _adapter.capabilities.can_observe_platform_overlay:
		_observer.start()
	if not _config.identity_verifier_url.is_empty() and _verifier == null:
		var http := GEXHttpIdentityVerifier.new()
		http.endpoint = _config.identity_verifier_url
		http.timeout_seconds = _config.timeout_seconds
		add_child(http)
		_verifier = http
	_ready_for_requests = true
	capabilities_changed.emit(get_capabilities())
	return result

func get_provider() -> GEXTypes.Provider:
	return _adapter.provider if _adapter != null else GEXTypes.Provider.NONE

func get_auth_state() -> GEXTypes.AuthState:
	return _auth_state

func get_capabilities() -> GEXTypes.Capabilities:
	var result := GEXTypes.Capabilities.new()
	if _adapter == null:
		return result
	var source := _adapter.capabilities
	for property: Dictionary in source.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(property.name, source.get(property.name))
	result.available = _ready_for_requests and source.available
	result.authenticated = _auth_state == GEXTypes.AuthState.AUTHENTICATED
	result.enabled_modules = []
	for module in ["identity", "friends", "achievements", "leaderboards", "cloud_save"]:
		if _config.module_enabled(module):
			result.enabled_modules.append(module)
	result.can_open_achievements = result.available and result.authenticated \
		and _config.achievements_enabled
	result.can_open_leaderboards = result.available and result.authenticated \
		and _config.leaderboards_enabled
	result.can_resolve_save_conflicts = source.can_resolve_save_conflicts and _config.cloud_save_enabled
	result.can_confirm_save_completion = source.can_confirm_save_completion and _config.cloud_save_enabled
	result.available_native_destinations = source.available_native_destinations.duplicate()
	if not _config.achievements_enabled:
		for destination in ["achievements", "achievement"]:
			var index := result.available_native_destinations.find(destination)
			if index >= 0:
				result.available_native_destinations.remove_at(index)
	if not _config.leaderboards_enabled:
		for destination in ["leaderboards", "leaderboard", "leaderboard_set"]:
			var index := result.available_native_destinations.find(destination)
			if index >= 0:
				result.available_native_destinations.remove_at(index)
	return result

func get_native_ui_capabilities() -> GEXTypes.Capabilities:
	return get_capabilities()

func get_native_ui_state() -> GEXTypes.NativeUiState:
	return _adapter.native_ui_state() if _adapter != null else GEXTypes.NativeUiState.new()

func get_interruption_state() -> GEXTypes.InterruptionState:
	return _interruptions.snapshot() if _interruptions != null else GEXTypes.InterruptionState.new()

func authenticate() -> GEXResult:
	return await _authentication("authenticate")

func refresh_auth_state() -> GEXResult:
	return await _authentication("refresh_auth_state")

func get_player() -> GEXResult:
	var result := await _run("get_player", {}, "identity")
	if result.is_ok():
		_accept_player(result.player)
	return result

func get_identity_proof() -> GEXResult:
	return await _run("get_identity_proof", {}, "identity")

## Caller owns an injected verifier's lifetime; add it to the tree before injection.
func set_identity_verifier(verifier: GEXIdentityVerifier) -> void:
	_verifier = verifier

func verify_player_identity() -> GEXResult:
	if not is_instance_valid(_verifier):
		return _failure("BACKEND_NOT_CONFIGURED")
	var result := await get_identity_proof()
	if not result.is_ok():
		return result
	var generation := _requests.generation
	var verified: GEXResult = await _verifier.verify(result.proof)
	if not _ready_for_requests or _requests.generation != generation:
		return _failure("SESSION_CHANGED")
	verified.request_id = result.request_id
	verified.operation = "verify_player_identity"
	verified.provider = get_provider()
	return verified

func list_friends(limit: int = 25, ask_permission: bool = false,
		force_refresh: bool = false) -> GEXResult:
	if limit < 1 or limit > 200:
		return _failure("INVALID_ARGUMENT", "Friends page size must be 1..200.")
	return await _run("list_friends", {"limit": limit, "ask_permission": ask_permission,
		"force_refresh": force_refresh}, "friends")

func unlock_achievement(key: String) -> GEXResult:
	return await set_achievement_progress(key, 1.0)

func set_achievement_progress(key: String, progress: float) -> GEXResult:
	if not is_finite(progress) or progress < 0.0 or progress > 1.0:
		return _failure("INVALID_ARGUMENT", "Progress must be finite and in [0, 1].")
	if _config == null:
		return _failure("NOT_INITIALIZED")
	var definition := _config.achievement(key)
	if definition == null:
		return _failure("INVALID_CONFIGURATION", "Unknown achievement key: " + key)
	return await _run("set_achievement_progress", {"definition": definition,
		"progress": progress}, "achievements")

func list_achievement_definitions(force_refresh: bool = false) -> GEXResult:
	return await _run("list_achievement_definitions", {"force_refresh": force_refresh}, "achievements")

func list_player_achievements(force_refresh: bool = false) -> GEXResult:
	return await _run("list_player_achievements", {"force_refresh": force_refresh}, "achievements")

func list_leaderboards(force_refresh: bool = false) -> GEXResult:
	return await _run("list_leaderboards", {"force_refresh": force_refresh}, "leaderboards")

func submit_score(key: String, score: int) -> GEXResult:
	return await _board("submit_score", key, null, score)

func get_player_score(key: String, query: GEXQuery = null) -> GEXResult:
	return await _board("get_player_score", key, query)

func get_top_scores(key: String, query: GEXQuery = null) -> GEXResult:
	return await _board("get_top_scores", key, query)

func get_scores_around_player(key: String, query: GEXQuery = null) -> GEXResult:
	return await _board("get_scores_around_player", key, query)

func save_game(slot: String, data: PackedByteArray, description: String = "",
		played_msec: int = 0, progress_value: int = 0) -> GEXResult:
	var failure := _validate_save(slot, data)
	if failure != null:
		return failure
	if played_msec < 0 or progress_value < 0 or description.to_utf8_buffer().size() > 500:
		return _failure("INVALID_ARGUMENT", "Nonnegative metadata; description budget 500 UTF-8 bytes.")
	return await _run("save_game", {"slot": slot, "data": data.duplicate(),
		"description": description, "played_msec": played_msec,
		"progress_value": progress_value}, "cloud_save")

func load_game(slot: String) -> GEXResult:
	var failure := _validate_save(slot, PackedByteArray())
	if failure != null:
		return failure
	return await _run("load_game", {"slot": slot}, "cloud_save")

func list_saved_games(force_refresh: bool = false) -> GEXResult:
	return await _run("list_saved_games", {"force_refresh": force_refresh}, "cloud_save")

func delete_saved_game(slot: String) -> GEXResult:
	var failure := _validate_save(slot, PackedByteArray())
	if failure != null:
		return failure
	return await _run("delete_saved_game", {"slot": slot}, "cloud_save")

func resolve_save_conflict(token: String, data: PackedByteArray) -> GEXResult:
	if _config == null:
		return _failure("NOT_INITIALIZED")
	if token.is_empty() or data.size() > _config.max_save_bytes:
		return _failure("INVALID_ARGUMENT")
	return await _run("resolve_save_conflict", {"token": token, "data": data.duplicate()}, "cloud_save")

func show_achievements() -> GEXResult:
	return await _run("show_achievements", {}, "achievements")

func show_leaderboards() -> GEXResult:
	return await _run("show_leaderboards", {}, "leaderboards")

func show_leaderboard(key: String, query: GEXQuery = null) -> GEXResult:
	return await _board("show_leaderboard", key, query)

func show_platform_overlay() -> GEXResult:
	return await _run("show_platform_overlay", {}, "identity")

func set_platform_entry_point_visible(enabled: bool) -> GEXResult:
	return await _run("set_platform_entry_point_visible", {"enabled": enabled}, "identity")

func set_platform_entry_point_location(location: int) -> GEXResult:
	if location not in [0, 1, 2, 3]:
		return _failure("INVALID_ARGUMENT")
	return await _run("set_platform_entry_point_location", {"location": location}, "identity")

## Named destinations; achievement/leaderboard IDs use the catalog's logical key.
## Other identifiers (activity/challenge/set) are native public definition IDs.
func show_native_destination(destination: String, key_or_id: String = "") -> GEXResult:
	if destination == "leaderboard":
		return await show_leaderboard(key_or_id)
	if destination == "achievements":
		return await show_achievements()
	if destination == "leaderboards":
		return await show_leaderboards()
	var native_id := key_or_id
	var module := "identity"
	if destination == "achievement":
		if _config == null or _config.achievement(key_or_id) == null:
			return _failure("INVALID_CONFIGURATION")
		native_id = _config.achievement(key_or_id).native_id(get_provider())
		module = "achievements"
	if destination == "leaderboard_set":
		module = "leaderboards"
	if destination in ["achievement", "leaderboard_set", "challenge", "activity"] \
			and native_id.is_empty():
		return _failure("INVALID_ARGUMENT", "Destination requires an identifier.")
	return await _run("show_native_destination", {"destination": destination,
		"native_id": native_id}, module)

func set_pause_token(token: String, enabled: bool) -> void:
	if _interruptions != null:
		_interruptions.set_pause_token(token, enabled)

func take_pending_activities() -> Array[GEXTypes.NativeActivity]:
	var activities := _pending_activities.duplicate()
	_pending_activities.clear()
	return activities

## Simulator-only hooks: caller must check for null on real platforms.
func get_simulator() -> GEXMockAdapter:
	return _adapter as GEXMockAdapter

func cancel_pending_requests() -> void:
	if _requests != null:
		_requests.cancel_all()

func shutdown() -> void:
	_ready_for_requests = false
	if _observer != null:
		_observer.stop()
	if _requests != null:
		_requests.cancel_all()
	if _adapter != null:
		_adapter.shutdown()
	if _interruptions != null:
		_interruptions.release_owned_pause()
	_pending_activities.clear()
	_player = null
	_set_auth_state(GEXTypes.AuthState.UNKNOWN)

func _exit_tree() -> void:
	shutdown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _ready_for_requests:
		_resume.call_deferred()

func _resume() -> void:
	_observe_native_ui()
	await refresh_auth_state()

func _authentication(operation: String) -> GEXResult:
	if _auth_busy:
		var previous_operation := _auth_operation
		await _auth_finished
		if operation == "authenticate" and previous_operation == "refresh_auth_state" \
				and _auth_state != GEXTypes.AuthState.AUTHENTICATED:
			return await _authentication(operation)
		return _last_auth_result
	_auth_busy = true
	_auth_operation = operation
	_set_auth_state(GEXTypes.AuthState.AUTHENTICATING)
	var result := await _run(operation, {}, "identity", false)
	if result.is_ok():
		_accept_player(result.player)
	elif result.error_code == "AUTHENTICATION_FAILED":
		_accept_player(null)
	else:
		_set_auth_state(GEXTypes.AuthState.UNKNOWN)
	_last_auth_result = result
	_auth_busy = false
	_auth_finished.emit()
	return result

func _run(operation: String, args: Dictionary, module: String,
		requires_auth: bool = true) -> GEXResult:
	if not _ready_for_requests:
		return _failure("NOT_INITIALIZED")
	if not _config.module_enabled(module):
		return _failure("FEATURE_DISABLED")
	if requires_auth and _auth_state != GEXTypes.AuthState.AUTHENTICATED:
		return _failure("NOT_AUTHENTICATED")
	var result := await _requests.submit(operation, args)
	operation_completed.emit(result.request_id, operation, result.status, result.error_code)
	return result

func _board(operation: String, key: String, query: GEXQuery, score: int = 0) -> GEXResult:
	if _config == null:
		return _failure("NOT_INITIALIZED")
	var definition := _config.leaderboard(key)
	if definition == null:
		return _failure("INVALID_CONFIGURATION", "Unknown leaderboard key: " + key)
	if query == null:
		query = definition.default_query if definition.default_query != null else GEXQuery.new()
	if not query.is_valid():
		return _failure("INVALID_ARGUMENT", "Query: limit 1..25, valid scope and period required.")
	return await _run(operation, {"definition": definition, "query": query.duplicate(),
		"score": score}, "leaderboards")

func _validate_save(slot: String, data: PackedByteArray) -> GEXResult:
	if _config == null:
		return _failure("NOT_INITIALIZED")
	if not GEXConfig.valid_slot(slot) or not GEXConfig.valid_slot(_config.slot_prefix + slot):
		return _failure("INVALID_ARGUMENT", "Slot: 1..100 ASCII letters, digits, - . _ ~.")
	if data.size() > _config.max_save_bytes:
		return _failure("INVALID_ARGUMENT", "Payload exceeds the configured application budget.")
	return null

func _accept_player(player: GEXTypes.PlayerProfile) -> void:
	var old_id := _player.id if _player != null else ""
	var new_id := player.id if player != null else ""
	if old_id != new_id:
		_requests.cancel_all("SESSION_CHANGED")
		_pending_activities.clear()
		_player = player
		player_changed.emit(player)
	_set_auth_state(GEXTypes.AuthState.AUTHENTICATED if player != null \
		else GEXTypes.AuthState.UNAUTHENTICATED)

func _on_session_observed(id: String, authenticated: bool) -> void:
	if _player != null and authenticated and _player.id == id:
		return
	_requests.cancel_all("SESSION_CHANGED")
	_pending_activities.clear()
	_player = null
	player_changed.emit(null)
	_set_auth_state(GEXTypes.AuthState.UNKNOWN if authenticated else GEXTypes.AuthState.UNAUTHENTICATED)

func _set_auth_state(state: GEXTypes.AuthState) -> void:
	if _auth_state == state:
		return
	_auth_state = state
	auth_state_changed.emit(state)
	capabilities_changed.emit(get_capabilities())

func _observe_native_ui() -> void:
	if _adapter == null or not _ready_for_requests:
		return
	var state := _adapter.native_ui_state()
	if state.presentation == _last_ui.presentation and state.entry_point_active == _last_ui.entry_point_active \
			and state.entry_point_visible == _last_ui.entry_point_visible:
		return
	_last_ui = state
	_interruptions.set_native_presenting(state.presentation == GEXTypes.Presentation.PRESENTING)
	native_ui_state_changed.emit(state)

func _on_activity(activity: GEXTypes.NativeActivity) -> void:
	_pending_activities.append(activity)
	if _pending_activities.size() > 32:
		_pending_activities.pop_front()
	native_activity_received.emit(activity)

func _failure(code: String, message: String = "") -> GEXResult:
	var result := GEXResult.fail(code, message)
	result.provider = get_provider()
	result.request_id = _failure_sequence
	_failure_sequence -= 1
	return result
