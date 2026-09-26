extends SceneTree
## No third-party test runner. Run after a headless editor import.

var _checks: int = 0
var _failures: int = 0
var _async_results: Dictionary = {}

class FakeAndroid extends RefCounted:
	signal conflictEmitted(json: String)
	signal scoreSubmitted(success: bool, id: String)
	signal gameSaved(success: bool, slot: String, description: String)
	signal gameLoaded(json: String)
	signal achievementUnlocked(success: bool, id: String)
	signal achievementsLoaded(json: String)
	signal friendsLoaded(json: String)
	signal topScoresLoaded(id: String, json: String)
	signal snapshotsLoaded(json: String)
	signal snapshotDeleted(success: bool, id: String)
	var delay_score: bool = false
	var last_steps: int = -1
	var create_on_load: bool = true
	var deleted_id: String = ""
	var score_calls: int = 0
	func submitScore(id: String, _score: int) -> void:
		score_calls += 1
		if not delay_score:
			scoreSubmitted.emit(true, id)
	func saveGame(slot: String, description: String, _bytes: PackedByteArray,
			_played: int, _progress: int) -> void:
		gameSaved.emit(true, slot, description)
	func loadGame(_slot: String, create: bool) -> void:
		create_on_load = create
		gameLoaded.emit('{"content":[0,-128,-1],"metadata":{"uniqueName":"slot","snapshotId":"native"}}')
	func setAchievementSteps(id: String, steps: int) -> void:
		last_steps = steps
		achievementUnlocked.emit(false, id)
	func loadAchievements(_refresh: bool) -> void:
		achievementsLoaded.emit('[{"achievementId":"a-progress","type":"TYPE_INCREMENTAL","totalSteps":10,"currentSteps":0,"state":"STATE_REVEALED"}]')
	func loadFriends(_limit: int, _refresh: bool, _permission: bool) -> void:
		friendsLoaded.emit("[]")
	func loadTopScores(id: String, _period: int, _scope: int, _limit: int, _refresh: bool) -> void:
		topScoresLoaded.emit(id, '{"scores":[{"rawScore":9223372036854775807,"rank":42}]}')
	func loadSnapshots(_refresh: bool) -> void:
		snapshotsLoaded.emit('[{"uniqueName":"slot","snapshotId":"native-id"}]')
	func deleteSnapshot(id: String) -> void:
		deleted_id = id
		snapshotDeleted.emit(true, id)

class FakeSavedGame extends RefCounted:
	var name: String = "slot"
	var modification_date: float = 123.0
	var device_name: String = "test"
	func load_data(callback: Callable) -> void:
		callback.call(PackedByteArray([0, 128, 255]), null)

class FakeApplePlayer extends RefCounted:
	var game_player_id: String = "apple-player"
	var team_player_id: String = "team-player"
	var display_name: String = "Test"
	var is_authenticated: bool = true
	var permission: int = 0
	var friends_called: bool = false
	var duplicates: bool = false
	var resolved_count: int = 0
	func fetch_saved_games(callback: Callable) -> void:
		var games: Array = [FakeSavedGame.new()]
		if duplicates:
			games.append(FakeSavedGame.new())
		callback.call(games, null)
	func resolve_conflicting_saved_games(handles: Array, _data: PackedByteArray,
			callback: Callable) -> void:
		resolved_count = handles.size()
		callback.call(handles, null)
	func load_friends_authorization_status(callback: Callable) -> void:
		callback.call(permission, null)
	func load_friends(callback: Callable) -> void:
		friends_called = true
		callback.call([], null)
	func unregister_listener() -> void:
		pass

class FakeAccessPoint extends RefCounted:
	var active: bool = true
	var visible: bool = true
	var is_presenting_game_center: bool = false
	var location: int = 0
	func trigger(done: Callable) -> void:
		is_presenting_game_center = true
		done.call()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_contract()
	await _test_android_boundary()
	await _test_apple_boundary()
	await _test_interruptions()
	_test_json()
	print("GameExtrakit: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _config() -> GEXConfig:
	var config := GEXConfig.new()
	config.mock_enabled = true
	config.mock_latency_seconds = 0.002
	config.timeout_seconds = 1.0
	var achievement := GEXAchievementDefinition.new()
	achievement.key = "progress"
	achievement.android_id = "a-progress"
	achievement.apple_id = "i-progress"
	achievement.incremental = true
	achievement.android_total_steps = 10
	config.achievements.append(achievement)
	var leaderboard := GEXLeaderboardDefinition.new()
	leaderboard.key = "score"
	leaderboard.android_id = "a-score"
	leaderboard.apple_id = "i-score"
	config.leaderboards.append(leaderboard)
	return config

func _service(config: GEXConfig) -> GEXGameServices:
	var api := GEXGameServices.new()
	api.auto_initialize = false
	root.add_child(api)
	_check(api.initialize(config).is_ok(), "initialize mock")
	return api

func _test_contract() -> void:
	var config := _config()
	var api := _service(config)
	_check(api.get_provider() == GEXTypes.Provider.MOCK, "explicit mock provider")
	_check((await api.list_friends()).error_code == "NOT_AUTHENTICATED", "auth prerequisite")
	_check((await api.authenticate()).is_ok(), "authenticate")
	_check(api.get_auth_state() == GEXTypes.AuthState.AUTHENTICATED, "auth state")
	_check((await api.get_player()).player.id == config.mock_player_id, "profile")
	_check((await api.get_identity_proof()).proof.kind.begins_with("SIMULATED"), "mock proof tagged")
	_check((await api.verify_player_identity()).error_code == "BACKEND_NOT_CONFIGURED", "missing backend")
	_check((await api.list_friends()).friends.size() == 3, "friends")
	_check((await api.list_friends(1)).completeness == GEXTypes.Completeness.PARTIAL, "partial friends")
	_check((await api.set_achievement_progress("progress", NAN)).error_code == "INVALID_ARGUMENT", "NaN")
	_check((await api.set_achievement_progress("missing", 0.5)).error_code == "INVALID_CONFIGURATION", "key")
	_check((await api.set_achievement_progress("progress", 0.5)).is_ok(), "progress accepted")
	await api.set_achievement_progress("progress", 0.5)
	await api.set_achievement_progress("progress", 0.2)
	_check((await api.list_player_achievements()).achievements[0].progress == 0.5, "monotonic/idempotent")
	await api.unlock_achievement("progress")
	_check((await api.list_player_achievements()).achievements[0].unlocked, "unlock")
	_check((await api.list_achievement_definitions()).achievement_definitions.size() == 1, "definitions")
	_check((await api.list_leaderboards()).leaderboards[0].key == "score", "boards")
	_check((await api.get_player_score("score")).own_entry == null, "missing own score is optional")
	const BIG: int = 9223372036854775807
	await api.submit_score("score", BIG)
	await api.submit_score("score", 10)
	_check((await api.get_player_score("score")).own_entry.score == BIG, "int64 and best score")
	for scope in [GEXTypes.Scope.GLOBAL, GEXTypes.Scope.FRIENDS]:
		for period in [GEXTypes.Period.DAILY, GEXTypes.Period.WEEKLY, GEXTypes.Period.ALL_TIME]:
			var query := GEXQuery.new()
			query.scope = scope
			query.period = period
			query.limit = 25
			var result := await api.get_top_scores("score", query)
			_check(result.is_ok() and result.query.period == period, "scope/period mapping")
	var query := GEXQuery.new()
	query.limit = 26
	_check((await api.get_top_scores("score", query)).error_code == "INVALID_ARGUMENT", "reject >25")
	_check((await api.get_scores_around_player("score")).centered_on_player, "around player")
	var bytes := PackedByteArray([0, 1, 127, 128, 255])
	_check((await api.save_game("slot", bytes)).delivery == GEXTypes.Delivery.PROVIDER_ACCEPTED, "save")
	_check((await api.load_game("slot")).bytes == bytes, "exact byte roundtrip")
	_check((await api.load_game("absent")).error_code == "SAVE_NOT_FOUND", "load never creates")
	_check((await api.list_saved_games()).saves.size() == 1, "list saves")
	_check((await api.save_game("../bad", bytes)).error_code == "INVALID_ARGUMENT", "invalid slot")
	_check((await api.delete_saved_game("slot")).is_ok(), "delete")
	_check((await api.load_game("slot")).error_code == "SAVE_NOT_FOUND", "deleted slot")
	var mock := api.get_simulator()
	var conflict := mock.simulate_conflict("slot")
	_check((await api.resolve_save_conflict(conflict.token, bytes)).is_ok(), "resolve conflict")
	_check((await api.resolve_save_conflict(conflict.token, bytes)).error_code == "CONFLICT_EXPIRED", "single use token")
	_check((await api.show_achievements()).is_ok(), "UI achievements")
	mock.simulate_presentation(false)
	_check((await api.show_leaderboard("score")).is_ok(), "UI board")
	_check((await api.show_platform_overlay()).is_ok(), "mock overlay")
	await api.set_platform_entry_point_visible(false)
	_check(api.get_native_ui_state().presentation == GEXTypes.Presentation.PRESENTING,
		"hiding access point does not close overlay")
	mock.next_error = "NETWORK_UNAVAILABLE"
	_check((await api.list_friends()).error_code == "NETWORK_UNAVAILABLE", "injected failure")
	mock.drop_next_reply = true
	_check((await api.save_game("timeout", bytes)).status == GEXTypes.Status.UNKNOWN, "mutation timeout unknown")
	_capture(api, "save_game", ["ordered", PackedByteArray([1])], "first")
	_capture(api, "save_game", ["ordered", PackedByteArray([2])], "second")
	var loaded := await api.load_game("ordered")
	_check(loaded.bytes == PackedByteArray([2]), "FIFO slot serialization")
	_check(_async_results.first.request_id != _async_results.second.request_id, "request IDs unique")
	conflict = mock.simulate_conflict("slot")
	mock.drop_next_reply = true
	_capture(api, "load_game", ["slot"], "old_player")
	await process_frame
	mock.switch_account("second-player")
	await process_frame
	_check(_async_results.old_player.status == GEXTypes.Status.CANCELLED, "account invalidates request")
	await api.refresh_auth_state()
	_check((await api.load_game("slot")).error_code == "SAVE_NOT_FOUND", "account data isolated")
	_check((await api.resolve_save_conflict(conflict.token, bytes)).error_code == "CONFLICT_EXPIRED", "old conflict invalid")
	api.shutdown()
	_check((await api.list_friends()).error_code == "NOT_INITIALIZED", "shutdown")
	api.queue_free()
	await process_frame
	var disabled := _config()
	disabled.friends_enabled = false
	api = _service(disabled)
	await api.authenticate()
	_check((await api.list_friends()).error_code == "FEATURE_DISABLED", "disabled module")
	api.queue_free()
	await process_frame
	var invalid := _config()
	invalid.achievements.append(invalid.achievements[0])
	_check(not invalid.validate().is_empty(), "duplicate catalog rejected")
	var no_provider := GEXGameServices.new()
	no_provider.auto_initialize = false
	root.add_child(no_provider)
	_check(no_provider.initialize(GEXConfig.new()).error_code == "UNSUPPORTED_PLATFORM", "no implicit mock")
	no_provider.queue_free()
	await process_frame

func _test_android_boundary() -> void:
	var adapter := GEXAndroidAdapter.new()
	root.add_child(adapter)
	adapter.config = _config()
	adapter.provider = GEXTypes.Provider.ANDROID_PGS
	var native := FakeAndroid.new()
	adapter.set("_native", native)
	var args := {"slot": "slot", "description": "", "data": PackedByteArray([1]),
		"played_msec": 0, "progress_value": 0}
	var result: GEXResult = await adapter._execute_authenticated("save_game", args)
	_check(result.status == GEXTypes.Status.UNKNOWN and result.delivery == GEXTypes.Delivery.UNKNOWN,
		"Android early save never confirmed")
	result = await adapter._execute_authenticated("load_game", {"slot": "slot"})
	_check(result.bytes == PackedByteArray([0, 128, 255]) and not native.create_on_load,
		"Android signed byte decoding / create=false")
	result = await adapter._execute_authenticated("set_achievement_progress",
		{"definition": adapter.config.achievements[0], "progress": 0.59})
	_check(native.last_steps == 5 and result.status == GEXTypes.Status.UNKNOWN,
		"absolute floor steps / ambiguous false")
	await adapter._execute_authenticated("set_achievement_progress",
		{"definition": adapter.config.achievements[0], "progress": 0.0})
	_check(native.last_steps == 5, "zero steps not sent")
	result = await adapter._execute_authenticated("list_friends",
		{"limit": 25, "force_refresh": false, "ask_permission": false})
	_check(result.status == GEXTypes.Status.UNKNOWN, "empty friends not invented as success")
	result = await adapter._execute_authenticated("get_top_scores",
		{"definition": adapter.config.leaderboards[0], "query": GEXQuery.new()})
	_check(result.entries[0].score == 9223372036854775807 and result.entries[0].rank == 42,
		"Android JSON int64 and native rank preserved")
	await adapter._execute_authenticated("delete_saved_game", {"slot": "slot"})
	_check(native.deleted_id == "native-id", "delete resolves native snapshot ID")
	native.delay_score = true
	args = {"definition": adapter.config.leaderboards[0], "score": 1}
	result = await adapter._execute_authenticated("submit_score", args)
	_check(result.status == GEXTypes.Status.UNKNOWN and result.error_code == "TIMEOUT", "Android timeout")
	result = await adapter._execute_authenticated("submit_score", args)
	_check(result.error_code == "REQUEST_CHANNEL_BUSY" and native.score_calls == 1, "quarantine late signal")
	native.scoreSubmitted.emit(true, "wrong-id")
	await process_frame
	result = await adapter._execute_authenticated("submit_score", args)
	_check(result.error_code == "REQUEST_CHANNEL_BUSY", "wrong ID cannot drain channel")
	native.scoreSubmitted.emit(true, "a-score")
	await process_frame
	native.delay_score = false
	result = await adapter._execute_authenticated("submit_score", args)
	_check(result.is_ok(), "late signal drains tombstone before channel reuse")
	_check(adapter.native_ui_state().presentation == GEXTypes.Presentation.UNKNOWN, "Sidekick stays UNKNOWN")
	adapter.queue_free()
	await process_frame

func _test_apple_boundary() -> void:
	var adapter := GEXAppleAdapter.new()
	root.add_child(adapter)
	adapter.config = _config()
	adapter.provider = GEXTypes.Provider.APPLE_GAME_CENTER
	var player := FakeApplePlayer.new()
	var access := FakeAccessPoint.new()
	adapter.set("_local", player)
	adapter.set("_access", access)
	adapter.set("_ios_major", 17)
	var result: GEXResult = await adapter._execute_authenticated("load_game", {"slot": "slot"})
	_check(result.bytes == PackedByteArray([0, 128, 255]), "Apple callback and saved bytes")
	result = await adapter._execute_authenticated("list_friends", {"limit": 25, "ask_permission": false})
	_check(result.error_code == "PERMISSION_REQUIRED" and not player.friends_called, "silent friends stays silent")
	player.permission = 3
	result = await adapter._execute_authenticated("list_friends", {"limit": 25, "ask_permission": false})
	_check(result.is_ok() and result.friends.is_empty(), "authorized empty Apple friends valid")
	player.duplicates = true
	var received: Array[GEXTypes.SaveConflict] = []
	adapter.conflict_detected.connect(func(conflict: GEXTypes.SaveConflict) -> void: received.append(conflict))
	result = await adapter._execute_authenticated("load_game", {"slot": "slot"})
	_check(result.error_code == "CONFLICT_PENDING" and received.size() == 1, "Apple duplicate save conflict")
	result = await adapter._execute_authenticated("resolve_save_conflict",
		{"token": received[0].token, "data": PackedByteArray([7])})
	_check(result.is_ok() and player.resolved_count == 2, "Apple retains native handles for resolve")
	result = await adapter._execute_authenticated("resolve_save_conflict",
		{"token": received[0].token, "data": PackedByteArray([7])})
	_check(result.error_code == "CONFLICT_EXPIRED", "Apple conflict token single use")
	result = adapter._show("show_native_destination", {"destination": "challenges"})
	_check(result.status == GEXTypes.Status.UNSUPPORTED, "iOS version gate avoids callbackless route")
	access.is_presenting_game_center = true
	await adapter._execute_authenticated("set_platform_entry_point_visible", {"enabled": false})
	_check(adapter.native_ui_state().presentation == GEXTypes.Presentation.PRESENTING,
		"Apple property separate from active button")
	adapter.queue_free()
	await process_frame

func _test_interruptions() -> void:
	var coordinator := GEXInterruptionCoordinator.new()
	coordinator.config = _config()
	coordinator.config.manage_scene_tree_pause = true
	coordinator.config.pause_on_focus_loss = true
	root.add_child(coordinator)
	coordinator.set_focus_lost(true)
	coordinator.set_focus_lost(true)
	_check(paused and coordinator.snapshot().pause_reasons.size() == 1, "deduplicate focus")
	coordinator.set_suspended(true)
	coordinator.set_native_presenting(true)
	coordinator.set_pause_token("menu", true)
	coordinator.set_focus_lost(false)
	coordinator.set_suspended(false)
	_check(paused, "overlapping interruption")
	coordinator.set_native_presenting(false)
	_check(paused, "manual pause preserved")
	coordinator.set_pause_token("menu", false)
	_check(not paused, "last owned reason releases pause")
	paused = true
	coordinator.set_native_presenting(true)
	coordinator.set_native_presenting(false)
	_check(paused, "preexisting tree pause preserved")
	paused = false
	coordinator.set_pause_token("menu", true)
	coordinator.release_owned_pause()
	_check(paused, "shutdown preserves game-owned pause token")
	paused = false
	coordinator.queue_free()
	await process_frame

func _test_json() -> void:
	var value: Variant = GEXNativeJson.parse('{"rawScore":9223372036854775807,"min":-9223372036854775808,"text":"123\\\"45","float":1.5,"bool":true}')
	_check(value is Dictionary and int(value.rawScore) == 9223372036854775807, "max int64 decoder")
	_check(int(value.min) == -9223372036854775807 - 1, "min int64 decoder")
	_check(value.text == '123"45' and value.float == 1.5 and value.bool, "JSON strings/decimal/bool preserved")
	_check(not GEXNativeJson.int64_valid("9223372036854775808"), "int64 overflow rejected")
	_check(GEXNativeJson.parse('{bad}') == null, "malformed JSON rejected")

func _capture(api: GEXGameServices, operation: String, arguments: Array, key: String) -> void:
	_async_results[key] = await api.callv(operation, arguments)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
