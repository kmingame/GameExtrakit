class_name GEXAppleAdapter
extends GEXPlatformAdapter
## Dynamically resolves the pinned GodotApplePlugins Game Center classes.
## No native class references are needed to parse this file on Windows/Android.

const PERIODS := {GEXTypes.Period.DAILY: 0, GEXTypes.Period.WEEKLY: 1,
	GEXTypes.Period.ALL_TIME: 2}
const SCOPES := {GEXTypes.Scope.GLOBAL: 0, GEXTypes.Scope.FRIENDS: 1}

var _manager: Object
var _local: Object
var _access: Object
var _ios_major: int = 0
var _identity: String = ""
var _auth_reply: GEXNativeReply
var _conflicts: Dictionary = {}
var _conflict_sequence: int = 0
var _ui_pending: bool = false

func setup(value: GEXConfig) -> GEXResult:
	provider = GEXTypes.Provider.APPLE_GAME_CENTER
	super.setup(value)
	for name in ["GameCenterManager", "GKLocalPlayer", "GKAchievement",
			"GKAchievementDescription", "GKLeaderboard", "GKSavedGame", "GKAccessPoint"]:
		if not ClassDB.class_exists(name):
			return GEXResult.fail("DEPENDENCY_MISSING", "Missing native class: " + name)
	var version_pattern := RegEx.create_from_string("([0-9]+)\\.")
	var version_match := version_pattern.search(OS.get_version())
	if version_match != null:
		_ios_major = int(version_match.get_string(1))
	if _ios_major < 17:
		return GEXResult.fail("UNSUPPORTED_PLATFORM", "Requires a known iOS version >= 17.")
	_manager = ClassDB.instantiate("GameCenterManager")
	_local = _manager.get("local_player")
	_access = _manager.get("access_point")
	if _local == null or _access == null:
		return GEXResult.fail("DEPENDENCY_MISSING", "Game Center runtime unavailable.")
	_manager.connect("authentication_result", _on_authentication, CONNECT_DEFERRED)
	_local.connect("conflicting_saved_games", _on_conflict, CONNECT_DEFERRED)
	_local.connect("saved_game_modified", _on_saved_game_modified, CONNECT_DEFERRED)
	if _ios_major >= 26 and _local.has_signal("game_activity_wants_to_play"):
		_local.connect("game_activity_wants_to_play", _on_activity, CONNECT_DEFERRED)
	_local.call("register_listener")
	_access.set("location", config.apple_entry_point_location)
	_access.set("show_highlights", config.apple_show_highlights)
	capabilities.available = true
	capabilities.can_resolve_save_conflicts = true
	capabilities.can_confirm_save_completion = true
	capabilities.can_open_platform_overlay = true
	capabilities.can_control_entry_point = true
	capabilities.can_observe_platform_overlay = true
	capabilities.interruption_observation = "PROVIDER_PROPERTY"
	capabilities.available_native_destinations = ["overlay", "achievements", "leaderboards",
		"leaderboard", "profile", "friends"]
	if _ios_major >= 18:
		capabilities.available_native_destinations.append_array(["achievement", "leaderboard_set"])
	if _ios_major >= 26:
		capabilities.available_native_destinations.append_array(
			["challenges", "friending", "play_together", "activity", "challenge"])
	capabilities.limitations = ["force_refresh has no Apple equivalent.",
		"Saved Games require iCloud separately from Game Center authentication."]
	return GEXResult.new()

func invalidate_session(new_generation: int) -> void:
	super.invalidate_session(new_generation)
	_conflicts.clear()
	if _auth_reply != null:
		_auth_reply.cancel("SESSION_CHANGED")

func shutdown() -> void:
	if closed:
		return
	super.shutdown()
	if _local != null:
		_local.call("unregister_listener")
		for pair in [["conflicting_saved_games", _on_conflict],
				["saved_game_modified", _on_saved_game_modified],
				["game_activity_wants_to_play", _on_activity]]:
			if _local.has_signal(pair[0]) and _local.is_connected(pair[0], pair[1]):
				_local.disconnect(pair[0], pair[1])
	if _manager != null and _manager.is_connected("authentication_result", _on_authentication):
		_manager.disconnect("authentication_result", _on_authentication)
	if _access != null:
		_access.set("active", false)

func native_ui_state() -> GEXTypes.NativeUiState:
	var state := super.native_ui_state()
	if _access == null:
		return state
	state.presentation = GEXTypes.Presentation.PRESENTING \
		if bool(_access.get("is_presenting_game_center")) else GEXTypes.Presentation.NOT_PRESENTING
	state.source = "PROVIDER_PROPERTY"
	state.observed_at_msec = Time.get_ticks_msec()
	state.entry_point_active = bool(_access.get("active"))
	state.entry_point_visible = bool(_access.get("visible"))
	return state

func execute(operation: String, args: Dictionary) -> GEXResult:
	if operation == "authenticate" and not bool(_local.get("is_authenticated")):
		if _auth_reply != null:
			return GEXResult.fail("REQUEST_CHANNEL_BUSY")
		_auth_reply = make_reply()
		var reply := _auth_reply
		_manager.call("authenticate")
		await wait_reply(reply)
		var failure := reply_failure(reply)
		if failure != null:
			return failure
		if not bool(_local.get("is_authenticated")):
			return GEXResult.fail("AUTHENTICATION_FAILED")
	if operation in ["authenticate", "refresh_auth_state", "get_player"]:
		var result := GEXResult.new()
		if bool(_local.get("is_authenticated")):
			result.player = _player(_local)
			_identity = result.player.id
			_access.set("active", config.apple_entry_point_active)
		return result
	if not bool(_local.get("is_authenticated")):
		session_observed.emit("", false)
		return GEXResult.fail("NOT_AUTHENTICATED")
	var observed := str(_local.get("game_player_id"))
	if observed != _identity:
		_identity = observed
		session_observed.emit(observed, true)
		return GEXResult.fail("SESSION_CHANGED")
	var result: GEXResult = await _execute_authenticated(operation, args)
	if not bool(_local.get("is_authenticated")) or str(_local.get("game_player_id")) != observed:
		session_observed.emit("", false)
		return GEXResult.uncertain("SESSION_CHANGED", "Result discarded after identity changed.")
	return result

func _execute_authenticated(operation: String, args: Dictionary) -> GEXResult:
	var result := GEXResult.new()
	match operation:
		"get_identity_proof":
			var reply := await _callback(_local, "fetch_items_for_identity_verification_signature", [])
			var failure := _failure(reply)
			if failure != null:
				return failure
			if not reply.values[0] is Dictionary:
				return _malformed()
			var data: Dictionary = reply.values[0]
			if not data.get("data") is PackedByteArray or not data.get("salt") is PackedByteArray \
					or not data.get("timestamp") is int or not data.get("url") is String:
				return _malformed()
			result.proof = GEXTypes.IdentityProof.new()
			result.proof.provider = provider
			result.proof.kind = "APPLE_GAME_CENTER_SIGNATURE"
			result.proof.signature = data.data
			result.proof.salt = data.salt
			result.proof.timestamp = data.timestamp
			result.proof.public_key_url = data.url
			result.proof.signed_player_id = str(_local.get("team_player_id"))
			result.proof.bundle_id = config.apple_bundle_id
		"list_friends":
			var permission := await _callback(_local, "load_friends_authorization_status", [])
			var failure := _failure(permission)
			if failure != null:
				return failure
			var status: int = int(permission.values[0])
			if status == 0 and not args.ask_permission:
				return GEXResult.fail("PERMISSION_REQUIRED")
			if status in [1, 2]:
				return GEXResult.fail("PERMISSION_DENIED")
			if status not in [0, 3]:
				return GEXResult.fail("PROVIDER_ERROR", "Unknown friends authorization status.")
			var reply := await _callback(_local, "load_friends", [])
			failure = _failure(reply)
			if failure != null:
				return failure
			if not reply.values[0] is Array:
				return _malformed()
			var players: Array = reply.values[0]
			for item: Variant in players.slice(0, args.limit):
				var player := _player(item)
				if player == null:
					return _malformed()
				result.friends.append(player)
			result.completeness = GEXTypes.Completeness.COMPLETE if players.size() <= int(args.limit) \
				else GEXTypes.Completeness.PARTIAL
		"set_achievement_progress":
			var achievement: Object = ClassDB.class_call_static(
				"GKAchievement", "make", args.definition.apple_id)
			achievement.set("percent_complete", float(args.progress) * 100.0)
			achievement.set("shows_completion_banner", true)
			var reply := await _callback(null, "report_achievement", [[achievement]],
				1, "GKAchievement")
			var failure := _failure(reply, true)
			if failure != null:
				return failure
		"list_achievement_definitions", "list_player_achievements":
			return await _achievements(operation)
		"list_leaderboards":
			var reply := await _callback(null, "load_leaderboards", [PackedStringArray()],
				2, "GKLeaderboard")
			var failure := _failure(reply)
			if failure != null:
				return failure
			if not reply.values[0] is Array:
				return _malformed()
			for board: Object in reply.values[0]:
				var info := GEXTypes.LeaderboardInfo.new()
				info.native_id = str(board.get("base_leaderboard_id"))
				info.key = leaderboard_key(info.native_id)
				info.title = str(board.get("title"))
				var definition := config.leaderboard(info.key)
				if definition != null:
					info.higher_is_better = definition.higher_is_better
					info.unit = definition.unit
				result.leaderboards.append(info)
		"submit_score", "get_player_score", "get_top_scores", "get_scores_around_player":
			return await _leaderboard_operation(operation, args)
		"save_game":
			var reply := await _callback(_local, "save_game_data",
				[args.data, config.slot_prefix + args.slot])
			var failure := _failure(reply, true)
			if failure != null:
				return failure
			if not reply.values[0] is Object:
				return _malformed()
			result.saves.append(_metadata(reply.values[0]))
			result.delivery = GEXTypes.Delivery.PROVIDER_ACCEPTED
		"list_saved_games", "load_game":
			return await _saved_games(operation, args)
		"delete_saved_game":
			var reply := await _callback(_local, "delete_saved_games",
				[config.slot_prefix + args.slot], 1)
			var failure := _failure(reply, true)
			if failure != null:
				return failure
			result.message = "Deleted all Saved Games with this name, including duplicate versions."
		"resolve_save_conflict":
			if not _conflicts.has(args.token):
				return GEXResult.fail("CONFLICT_EXPIRED")
			var record: Dictionary = _conflicts[args.token]
			if int(record.generation) != generation:
				return GEXResult.fail("CONFLICT_EXPIRED")
			var reply := await _callback(_local, "resolve_conflicting_saved_games",
				[record.handles, args.data])
			var failure := _failure(reply, true)
			if failure != null:
				return failure
			_conflicts.erase(args.token)
			result.delivery = GEXTypes.Delivery.PROVIDER_ACCEPTED
		"set_platform_entry_point_visible":
			_access.set("active", args.enabled)
		"set_platform_entry_point_location":
			_access.set("location", args.location)
		"show_platform_overlay", "show_achievements", "show_leaderboards", \
				"show_leaderboard", "show_native_destination":
			return _show(operation, args)
		_:
			return GEXResult.fail("UNSUPPORTED_OPERATION")
	return result

func _callback(target: Object, method: String, arguments: Array, arity: int = 2,
		static_class: String = "") -> GEXNativeReply:
	var reply := make_reply()
	var args := arguments.duplicate()
	args.append(Callable(reply, "receive%d" % arity))
	if static_class.is_empty():
		target.callv(method, args)
	else:
		ClassDB.callv("class_call_static", [static_class, method] + args)
	return await wait_reply(reply)

func _failure(reply: GEXNativeReply, mutation: bool = false) -> GEXResult:
	var failure := reply_failure(reply, mutation)
	if failure != null:
		return failure
	if reply.values.is_empty():
		return _malformed()
	var error: Variant = reply.values.back()
	if error == null:
		return null
	var result := GEXResult.fail("PROVIDER_ERROR", "Game Center returned an error.")
	if error is Object:
		result.native_code = str(error.get("code"))
		var mappings := {"CANCELLED": "USER_CANCELLED", "NOT_AUTHENTICATED": "NOT_AUTHENTICATED",
			"USER_DENIED": "PERMISSION_DENIED", "FRIEND_LIST_DENIED": "PERMISSION_DENIED",
			"FRIEND_LIST_RESTRICTED": "PERMISSION_DENIED", "API_NOT_AVAILABLE": "UNSUPPORTED_OPERATION",
			"CONNECTION_TIMEOUT": "TIMEOUT"}
		for native_name: String in mappings:
			if ClassDB.class_has_integer_constant("GKError", native_name) and \
					int(error.get("code")) == ClassDB.class_get_integer_constant("GKError", native_name):
				result = GEXResult.fail(mappings[native_name])
				result.native_code = str(error.get("code"))
				break
	return result

func _achievements(operation: String) -> GEXResult:
	var descriptions := await _callback(null, "load_achievement_descriptions", [],
		2, "GKAchievementDescription")
	var failure := _failure(descriptions)
	if failure != null:
		return failure
	if not descriptions.values[0] is Array:
		return _malformed()
	var result := GEXResult.new()
	var states: Dictionary = {}
	for item: Object in descriptions.values[0]:
		var info := GEXTypes.AchievementInfo.new()
		info.native_id = str(item.get("identifier"))
		info.key = achievement_key(info.native_id)
		info.title = str(item.get("title"))
		info.description = str(item.get("unachieved_description"))
		var definition := config.achievement(info.key)
		info.incremental = definition != null and definition.incremental
		result.achievement_definitions.append(info)
		var state := GEXTypes.AchievementState.new()
		state.native_id = info.native_id
		state.key = info.key
		states[info.native_id] = state
	if operation == "list_player_achievements":
		var reply := await _callback(null, "load_achievements", [], 2, "GKAchievement")
		failure = _failure(reply)
		if failure != null:
			return failure
		if not reply.values[0] is Array:
			return _malformed()
		for item: Object in reply.values[0]:
			var id := str(item.get("identifier"))
			var state: GEXTypes.AchievementState = states.get(id, GEXTypes.AchievementState.new())
			state.native_id = id
			state.key = achievement_key(id)
			state.progress = clampf(float(item.get("percent_complete")) / 100.0, 0.0, 1.0)
			state.unlocked = bool(item.get("is_completed"))
			states[id] = state
		result.achievements.assign(states.values())
	return result

func _leaderboard_operation(operation: String, args: Dictionary) -> GEXResult:
	var reply := await _callback(null, "load_leaderboards",
		[PackedStringArray([args.definition.apple_id])], 2, "GKLeaderboard")
	var failure := _failure(reply)
	if failure != null:
		return failure
	if not reply.values[0] is Array or reply.values[0].is_empty():
		return GEXResult.fail("INVALID_CONFIGURATION", "Leaderboard ID not returned by Game Center.")
	var board: Object = reply.values[0][0]
	if operation == "submit_score":
		reply = await _callback(board, "submit_score", [args.score, 0, _local], 1)
		failure = _failure(reply, true)
		return failure if failure != null else GEXResult.new()
	var query: GEXQuery = args.query
	var native_args: Array = [SCOPES[query.scope], PERIODS[query.period], 1, query.limit]
	reply = await _callback(board, "load_local_player_entries", native_args, 4)
	failure = _failure(reply)
	if failure != null:
		return failure
	var own := _entry(reply.values[0])
	if operation == "get_scores_around_player" and own != null:
		native_args[2] = maxi(1, own.rank - query.limit / 2)
		reply = await _callback(board, "load_local_player_entries", native_args, 4)
		failure = _failure(reply)
		if failure != null:
			return failure
		own = _entry(reply.values[0])
	var result := GEXResult.new()
	result.own_entry = own
	result.query = query
	result.total_count = int(reply.values[2])
	result.centered_known = true
	if operation != "get_player_score":
		if not reply.values[1] is Array:
			return _malformed()
		for item: Variant in reply.values[1]:
			var entry := _entry(item)
			if entry == null:
				return _malformed()
			result.entries.append(entry)
			if entry.player != null and entry.player.id == _identity:
				result.centered_on_player = operation == "get_scores_around_player"
	result.message = "Native time window; around-player query is not an atomic snapshot."
	return result

func _saved_games(operation: String, args: Dictionary) -> GEXResult:
	var reply := await _callback(_local, "fetch_saved_games", [])
	var failure := _failure(reply)
	if failure != null:
		return failure
	if not reply.values[0] is Array:
		return _malformed()
	var result := GEXResult.new()
	var matches: Array = []
	for item: Object in reply.values[0]:
		if not str(item.get("name")).begins_with(config.slot_prefix):
			continue
		var metadata := _metadata(item)
		result.saves.append(metadata)
		if operation == "load_game" and metadata.slot == args.slot:
			matches.append(item)
	if operation == "load_game":
		if matches.is_empty():
			return GEXResult.fail("SAVE_NOT_FOUND")
		if matches.size() > 1:
			_on_conflict(_local, matches)
			return GEXResult.fail("CONFLICT_PENDING")
		reply = await _callback(matches[0], "load_data", [])
		failure = _failure(reply)
		if failure != null:
			return failure
		if not reply.values[0] is PackedByteArray:
			return _malformed()
		result.bytes = reply.values[0]
	result.completeness = GEXTypes.Completeness.COMPLETE
	return result

func _show(operation: String, args: Dictionary) -> GEXResult:
	if _ui_pending or bool(_access.get("is_presenting_game_center")):
		return GEXResult.fail("REQUEST_CHANNEL_BUSY", "A native presentation is already pending.")
	var destination := operation.trim_prefix("show_")
	if operation == "show_platform_overlay":
		destination = "overlay"
	elif operation == "show_native_destination":
		destination = args.destination
	if destination not in capabilities.available_native_destinations:
		return GEXResult.fail("UNSUPPORTED_OPERATION", "Destination unavailable on this iOS version.")
	# The native callback owns a mailbox, not a Node that may be freed during presentation.
	var relay := GEXNativeReply.new()
	relay.completed.connect(_presentation_finished)
	var done := Callable(relay, "receive0")
	match destination:
		"overlay":
			_access.call("trigger", done)
		"achievements", "leaderboards", "profile", "friends":
			var states := {"leaderboards": 1, "achievements": 2, "profile": 3, "friends": 5}
			_access.call("trigger_with_state", states[destination], done)
		"leaderboard":
			var query: GEXQuery = args.query
			if _ios_major < 18:
				ClassDB.class_call_static("GKGameCenterViewController", "show_leaderboard_time_period",
					args.definition.apple_id, SCOPES[query.scope], PERIODS[query.period])
				return GEXResult.uncertain("UI_DISPATCHED", "iOS 17 controller has no exposed callback.")
			_access.call("trigger_with_leaderboard", args.definition.apple_id,
				SCOPES[query.scope], PERIODS[query.period], done)
		"achievement":
			_access.call("trigger_with_achievement", args.native_id, done)
		"leaderboard_set":
			_access.call("trigger_with_leaderboard_set", args.native_id, done)
		"challenges", "friending", "play_together":
			_access.call("trigger_for_" + destination, done)
		"challenge":
			_access.call("trigger_with_challenge_definition_id", args.native_id, done)
		"activity":
			_access.call("trigger_with_game_activity_definition_id", args.native_id, done)
	_ui_pending = true
	var result := GEXResult.new()
	result.message = "Native UI requested; presentation is observed separately."
	return result

func _presentation_finished() -> void:
	_ui_pending = false

func _on_authentication(status: bool) -> void:
	if _auth_reply != null:
		var reply := _auth_reply
		_auth_reply = null
		reply.finish([status])
	else:
		session_observed.emit(str(_local.get("game_player_id")) if status else "", status)

func _on_conflict(player: Object, handles: Array) -> void:
	if closed or not _event_player_matches(player):
		return
	var by_slot: Dictionary = {}
	for handle: Object in handles:
		var name := str(handle.get("name"))
		if name.begins_with(config.slot_prefix):
			if not by_slot.has(name):
				by_slot[name] = []
			by_slot[name].append(handle)
	for name: String in by_slot:
		_conflict_sequence += 1
		var conflict := GEXTypes.SaveConflict.new()
		conflict.token = "apple:%d:%d" % [generation, _conflict_sequence]
		conflict.slot = logical_slot(name)
		conflict.provider = provider
		conflict.generation = generation
		for handle: Object in by_slot[name]:
			conflict.versions.append(_metadata(handle))
		_conflicts[conflict.token] = {"generation": generation, "handles": by_slot[name]}
		conflict_detected.emit(conflict)

func _on_saved_game_modified(player: Object, saved: Object) -> void:
	if _event_player_matches(player) and str(saved.get("name")).begins_with(config.slot_prefix):
		saved_game_modified.emit(_metadata(saved))

func _on_activity(player: Object, activity: Object) -> void:
	if not _event_player_matches(player):
		return
	var incoming := GEXTypes.NativeActivity.new()
	incoming.id = str(activity.get("identifier"))
	var definition: Object = activity.get("activity_definition")
	if definition != null:
		incoming.definition_id = str(definition.get("identifier"))
	incoming.generation = generation
	activity_received.emit(incoming)

func _event_player_matches(player: Object) -> bool:
	return not closed and player != null and bool(_local.get("is_authenticated")) \
		and str(player.get("game_player_id")) == str(_local.get("game_player_id"))

func _player(value: Variant) -> GEXTypes.PlayerProfile:
	if not value is Object:
		return null
	var profile := GEXTypes.PlayerProfile.new()
	profile.id = str(value.get("game_player_id"))
	profile.id_scope = "Game Center gamePlayerID"
	profile.provider = provider
	profile.display_name = str(value.get("display_name"))
	return profile

func _entry(value: Variant) -> GEXTypes.LeaderboardEntry:
	if not value is Object:
		return null
	var entry := GEXTypes.LeaderboardEntry.new()
	entry.player = _player(value.get("player"))
	entry.score = int(value.get("score"))
	entry.rank = int(value.get("rank"))
	entry.formatted_score = str(value.get("formatted_score"))
	return entry

func _metadata(value: Object) -> GEXTypes.SavedGameMetadata:
	var metadata := GEXTypes.SavedGameMetadata.new()
	metadata.slot = logical_slot(str(value.get("name")))
	metadata.modified_unix = float(value.get("modification_date"))
	metadata.device_name = str(value.get("device_name"))
	return metadata

func _malformed() -> GEXResult:
	return GEXResult.fail("PROVIDER_ERROR", "Malformed Game Center response; payload omitted.")
