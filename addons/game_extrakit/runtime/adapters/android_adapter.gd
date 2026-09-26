class_name GEXAndroidAdapter
extends GEXPlatformAdapter
## Pinned public GodotPlayGameServices API only; no new Android bridge.

const SINGLETON := "GodotPlayGameServices"
const PERIODS := {GEXTypes.Period.DAILY: 0, GEXTypes.Period.WEEKLY: 1,
	GEXTypes.Period.ALL_TIME: 2}
const COLLECTIONS := {GEXTypes.Scope.GLOBAL: 0, GEXTypes.Scope.FRIENDS: 3}
const OWNER_META := "game_extrakit_android_owner"
const RETIRED_META := "game_extrakit_android_retired_channels"

var _native: Object
var _channels: Dictionary = {}
var _identity: String = ""
var _conflict_sequence: int = 0

func setup(value: GEXConfig) -> GEXResult:
	provider = GEXTypes.Provider.ANDROID_PGS
	super.setup(value)
	if not Engine.has_singleton(SINGLETON):
		return GEXResult.fail("DEPENDENCY_MISSING", "Install GodotPlayGameServices 3.4.0.")
	var active_owner: WeakRef
	if Engine.has_meta(OWNER_META):
		active_owner = Engine.get_meta(OWNER_META)
	if active_owner != null and active_owner.get_ref() != null:
		return GEXResult.fail("REQUEST_CHANNEL_BUSY", "Use the existing GameServices instance.")
	Engine.set_meta(OWNER_META, weakref(self))
	_native = Engine.get_singleton(SINGLETON)
	if not _native.has_method("setAchievementSteps"):
		return GEXResult.fail("INVALID_CONFIGURATION", "Pinned PGS API not found.")
	var autoload := get_tree().root.get_node_or_null(SINGLETON)
	if autoload != null and autoload.has_method("initialize"):
		if autoload.get("android_plugin") == null:
			autoload.call("initialize")
	else:
		_native.call("initialize")
	_native.connect("conflictEmitted", _on_conflict, CONNECT_DEFERRED)
	capabilities.available = true
	capabilities.available_native_destinations = ["achievements", "leaderboards", "leaderboard"]
	capabilities.limitations = ["Save commit confirmation UNKNOWN; manual conflicts UNSUPPORTED.",
		"Sidekick control/visibility unavailable; lifecycle events do not identify it.",
		"Friends are one page; empty responses may hide provider errors."]
	return GEXResult.new()

func shutdown() -> void:
	if closed:
		return
	super.shutdown()
	var active_owner: WeakRef
	if Engine.has_meta(OWNER_META):
		active_owner = Engine.get_meta(OWNER_META)
	if active_owner != null and active_owner.get_ref() == self:
		Engine.remove_meta(OWNER_META)
	if _native == null:
		return
	if _native.has_signal("conflictEmitted") and _native.is_connected("conflictEmitted", _on_conflict):
		_native.disconnect("conflictEmitted", _on_conflict)
	for channel: String in _channels:
		# A future instance cannot safely attribute these replies. Keep process-wide
		# tombstones after teardown; only an app restart establishes a fresh native epoch.
		var retired: Dictionary = Engine.get_meta(RETIRED_META, {})
		retired[channel] = true
		Engine.set_meta(RETIRED_META, retired)
		var callback: Callable = _channels[channel].callback
		if _native.is_connected(channel, callback):
			_native.disconnect(channel, callback)
	_channels.clear()

func execute(operation: String, args: Dictionary) -> GEXResult:
	if operation in ["authenticate", "refresh_auth_state"]:
		var method := "signIn" if operation == "authenticate" else "isAuthenticated"
		var reply := await _signal_call(method, [], "userAuthenticated", 1)
		var failure := reply_failure(reply)
		if failure != null:
			return failure
		if not bool(reply.values[0]):
			_identity = ""
			return GEXResult.fail("AUTHENTICATION_FAILED") if operation == "authenticate" \
				else GEXResult.new()
		var result := await _load_player()
		if result.player != null:
			_identity = result.player.id
		return result
	if operation == "get_player":
		var result := await _load_player()
		if result.player != null:
			_identity = result.player.id
		return result
	if operation in ["show_platform_overlay", "set_platform_entry_point_visible",
			"set_platform_entry_point_location", "resolve_save_conflict"]:
		return GEXResult.fail("UNSUPPORTED_OPERATION", "Not exposed by the pinned PGS wrapper.")
	var before := await _load_player()
	if not before.is_ok() or before.player == null:
		return before
	if before.player.id != _identity:
		_identity = before.player.id
		session_observed.emit(_identity, true)
		return GEXResult.fail("SESSION_CHANGED")
	var result: GEXResult = await _execute_authenticated(operation, args)
	# Read identity again before returning account-bound data. Never retry a mutation here.
	var after := await _load_player()
	if not after.is_ok() or after.player == null or after.player.id != _identity:
		session_observed.emit("", false)
		return GEXResult.uncertain("SESSION_CHANGED", "Result discarded; refresh authentication.")
	return result

func _execute_authenticated(operation: String, args: Dictionary) -> GEXResult:
	var result := GEXResult.new()
	match operation:
		"get_identity_proof":
			if config.android_server_client_id.is_empty():
				return GEXResult.fail("INVALID_CONFIGURATION", "Missing server OAuth client ID.")
			var reply := await _signal_call("requestServerSideAccess",
				[config.android_server_client_id, false], "serverSideAccessRequested", 1)
			var failure := reply_failure(reply)
			if failure != null:
				return failure
			if str(reply.values[0]).is_empty():
				return GEXResult.fail("PROVIDER_ERROR")
			result.proof = GEXTypes.IdentityProof.new()
			result.proof.provider = provider
			result.proof.kind = "GOOGLE_SERVER_AUTH_CODE"
			result.proof.authorization_code = str(reply.values[0])
		"list_friends":
			var reply := await _signal_call("loadFriends",
				[args.limit, args.force_refresh, args.ask_permission], "friendsLoaded", 1)
			var failure := reply_failure(reply)
			if failure != null:
				return failure
			var data: Variant = GEXNativeJson.parse(str(reply.values[0]))
			if not data is Array or data.is_empty():
				return _ambiguous_empty()
			for item: Variant in data:
				var player := _player(item)
				if player == null:
					return _malformed()
				result.friends.append(player)
			result.completeness = GEXTypes.Completeness.UNKNOWN
		"set_achievement_progress":
			return await _progress(args)
		"list_player_achievements", "list_achievement_definitions":
			return await _achievements(args.force_refresh)
		"submit_score":
			var id: String = args.definition.android_id
			var reply := await _signal_call("submitScore", [id, args.score],
				"scoreSubmitted", 2, id, 1)
			return _boolean_result(reply, true)
		"list_leaderboards":
			var reply := await _signal_call("loadAllLeaderboards", [args.force_refresh],
				"allLeaderboardsLoaded", 1)
			var failure := reply_failure(reply)
			if failure != null:
				return failure
			var data: Variant = GEXNativeJson.parse(str(reply.values[0]))
			if not data is Array or data.is_empty():
				return _ambiguous_empty()
			for item: Variant in data:
				if not item is Dictionary or not item.get("leaderboardId") is String:
					return _malformed()
				var info := GEXTypes.LeaderboardInfo.new()
				info.native_id = item.leaderboardId
				info.key = leaderboard_key(info.native_id)
				info.title = str(item.get("displayName", ""))
				info.higher_is_better = item.get("scoreOrder") != "SCORE_ORDER_SMALLER_IS_BETTER"
				result.leaderboards.append(info)
		"get_player_score", "get_top_scores", "get_scores_around_player":
			return await _scores(operation, args)
		"save_game":
			var name: String = config.slot_prefix + args.slot
			var reply := await _signal_call("saveGame", [name, args.description, args.data,
				args.played_msec, args.progress_value], "gameSaved", 3, name, 1)
			var failure := reply_failure(reply, true)
			if failure != null:
				return failure
			return GEXResult.uncertain("SAVE_COMPLETION_UNVERIFIABLE",
				"Wrapper reported gameSaved; commitAndClose completion was not observed.")
		"load_game":
			var reply := await _signal_call("loadGame", [config.slot_prefix + args.slot, false],
				"gameLoaded", 1)
			var failure := reply_failure(reply)
			if failure != null:
				return failure
			var raw: String = str(reply.values[0])
			if raw.strip_edges() == "null":
				return GEXResult.fail("SAVE_NOT_FOUND")
			var data: Variant = GEXNativeJson.parse(raw)
			if not data is Dictionary or not data.get("content") is Array:
				return _malformed()
			var metadata := _metadata(data.get("metadata"))
			if metadata == null or metadata.slot != args.slot:
				return _malformed()
			for byte: Variant in data.content:
				if not (byte is float or byte is int) or not is_finite(float(byte)) \
						or float(byte) != floorf(float(byte)) or int(byte) < -128 or int(byte) > 255:
					return _malformed()
				result.bytes.append(int(byte) & 255)
			result.saves.append(metadata)
		"list_saved_games":
			return await _saved_games(args.force_refresh)
		"delete_saved_game":
			var listing := await _saved_games(true)
			if not listing.is_ok():
				return listing
			for metadata in listing.saves:
				if metadata.slot == args.slot:
					var reply := await _signal_call("deleteSnapshot", [metadata.native_id],
						"snapshotDeleted", 2, metadata.native_id, 1)
					return _boolean_result(reply, true)
			return GEXResult.fail("SAVE_NOT_FOUND")
		"show_achievements":
			_native.call("showAchievements")
			return _ui_dispatched()
		"show_leaderboards":
			_native.call("showAllLeaderboards")
			return _ui_dispatched()
		"show_leaderboard":
			var query: GEXQuery = args.query
			_native.call("showLeaderboardForTimeSpanAndCollection", args.definition.android_id,
				PERIODS[query.period], COLLECTIONS[query.scope])
			return _ui_dispatched()
		"show_native_destination":
			if args.destination in ["achievements", "leaderboards"]:
				return await _execute_authenticated("show_" + args.destination, args)
			return GEXResult.fail("UNSUPPORTED_OPERATION")
		_:
			return GEXResult.fail("UNSUPPORTED_OPERATION")
	return result

func _load_player() -> GEXResult:
	var reply := await _signal_call("loadCurrentPlayer", [true], "currentPlayerLoaded", 1)
	var failure := reply_failure(reply)
	if failure != null:
		return failure
	var result := GEXResult.new()
	result.player = _player(GEXNativeJson.parse(str(reply.values[0])))
	return result if result.player != null else _malformed()

func _signal_call(method: String, args: Array, channel: String, arity: int,
		expected_id: String = "", id_index: int = -1) -> GEXNativeReply:
	var retired: Dictionary = Engine.get_meta(RETIRED_META, {})
	if _channels.has(channel) or retired.has(channel):
		var blocked := GEXNativeReply.new()
		blocked.cancel("REQUEST_CHANNEL_BUSY")
		return blocked
	var reply := make_reply()
	var callback: Callable
	match arity:
		1:
			callback = func(a: Variant) -> void: _receive(channel, [a])
		2:
			callback = func(a: Variant, b: Variant) -> void: _receive(channel, [a, b])
		3:
			callback = func(a: Variant, b: Variant, c: Variant) -> void:
				_receive(channel, [a, b, c])
	_channels[channel] = {"reply": reply, "callback": callback,
		"expected_id": expected_id, "id_index": id_index}
	_native.connect(channel, callback, CONNECT_DEFERRED)
	_native.callv(method, args)
	return await wait_reply(reply)

func _receive(channel: String, values: Array) -> void:
	if not _channels.has(channel):
		return
	var entry: Dictionary = _channels[channel]
	if entry.id_index >= 0 and str(values[entry.id_index]) != entry.expected_id:
		return
	_native.disconnect(channel, entry.callback)
	_channels.erase(channel)
	# A timed-out/cancelled ticket stays attached until this exact native reply drains it.
	(entry.reply as GEXNativeReply).finish(values)

func _boolean_result(reply: GEXNativeReply, mutation: bool) -> GEXResult:
	var failure := reply_failure(reply, mutation)
	if failure != null:
		return failure
	return GEXResult.new() if bool(reply.values[0]) else GEXResult.fail("PROVIDER_ERROR")

func _progress(args: Dictionary) -> GEXResult:
	var definition: GEXAchievementDefinition = args.definition
	var amount: float = args.progress
	var id := definition.android_id
	# Validate catalog type/steps against native metadata before writing progress.
	# This also detects accidentally mapping an incremental key to a normal PGS ID.
	var catalog := await _achievements(false)
	if not catalog.is_ok():
		return catalog
	var found := false
	for info in catalog.achievement_definitions:
		if info.native_id == id:
			found = true
	if not found:
		return GEXResult.fail("INVALID_CONFIGURATION", "Achievement missing in PGS catalog.")
	if not definition.incremental:
		if amount == 0.0:
			return GEXResult.new()
		if amount != 1.0:
			return GEXResult.fail("UNSUPPORTED_OPERATION", "Normal PGS achievements have no steps.")
		return _boolean_result(await _signal_call("unlockAchievement", [id],
			"achievementUnlocked", 2, id, 1), true)
	var steps := floori(amount * definition.android_total_steps)
	if steps == 0:
		var unchanged := GEXResult.new()
		unchanged.message = "No positive steps to report; no native mutation sent."
		return unchanged
	var reply := await _signal_call("setAchievementSteps", [id, steps],
		"achievementUnlocked", 2, id, 1)
	var failure := reply_failure(reply, true)
	if failure != null:
		return failure
	if not bool(reply.values[0]):
		return GEXResult.uncertain("AMBIGUOUS_NATIVE_RESULT",
			"false can mean accepted progress without unlock, or failure.")
	return GEXResult.new()

func _achievements(force_refresh: bool) -> GEXResult:
	var reply := await _signal_call("loadAchievements", [force_refresh], "achievementsLoaded", 1)
	var failure := reply_failure(reply)
	if failure != null:
		return failure
	var data: Variant = GEXNativeJson.parse(str(reply.values[0]))
	if not data is Array or data.is_empty():
		return _ambiguous_empty()
	var result := GEXResult.new()
	for item: Variant in data:
		if not item is Dictionary or not item.get("achievementId") is String:
			return _malformed()
		var info := GEXTypes.AchievementInfo.new()
		info.native_id = item.achievementId
		info.key = achievement_key(info.native_id)
		info.title = str(item.get("name", ""))
		info.description = str(item.get("description", ""))
		info.incremental = item.get("type") == "TYPE_INCREMENTAL"
		info.total_steps = int(item.get("totalSteps", "0"))
		var definition := config.achievement(info.key)
		if definition != null and (definition.incremental != info.incremental or
				info.incremental and definition.android_total_steps != info.total_steps):
			return GEXResult.fail("INVALID_CONFIGURATION", "Achievement metadata mismatch: " + info.key)
		var state := GEXTypes.AchievementState.new()
		state.key = info.key
		state.native_id = info.native_id
		state.unlocked = item.get("state") == "STATE_UNLOCKED"
		if info.incremental:
			if info.total_steps <= 0:
				return _malformed()
			state.progress = float(item.get("currentSteps", "0")) / info.total_steps
		elif state.unlocked:
			state.progress = 1.0
		result.achievement_definitions.append(info)
		result.achievements.append(state)
	return result

func _scores(operation: String, args: Dictionary) -> GEXResult:
	var query: GEXQuery = args.query
	var id: String = args.definition.android_id
	var native_args: Array = [id, PERIODS[query.period], COLLECTIONS[query.scope]]
	var method := "loadPlayerScore"
	var channel := "scoreLoaded"
	if operation != "get_player_score":
		method = "loadTopScores" if operation == "get_top_scores" else "loadPlayerCenteredScores"
		channel = "topScoresLoaded" if operation == "get_top_scores" else "playerCenteredScoresLoaded"
		native_args.append_array([query.limit, query.force_refresh])
	var reply := await _signal_call(method, native_args, channel, 2, id, 0)
	var failure := reply_failure(reply)
	if failure != null:
		return failure
	var data: Variant = GEXNativeJson.parse(str(reply.values[1]))
	if not data is Dictionary or data.is_empty():
		return _ambiguous_empty()
	var result := GEXResult.new()
	result.query = query
	if operation == "get_player_score":
		result.own_entry = _entry(data)
		return result if result.own_entry != null else _malformed()
	if not data.get("scores") is Array:
		return _malformed()
	for item: Variant in data.scores:
		var entry := _entry(item)
		if entry == null:
			return _malformed()
		result.entries.append(entry)
		if entry.player != null and entry.player.id == _identity:
			result.own_entry = entry
	result.centered_known = true
	result.centered_on_player = result.own_entry != null and operation == "get_scores_around_player"
	return result

func _saved_games(force_refresh: bool) -> GEXResult:
	var reply := await _signal_call("loadSnapshots", [force_refresh], "snapshotsLoaded", 1)
	var failure := reply_failure(reply)
	if failure != null:
		return failure
	var data: Variant = GEXNativeJson.parse(str(reply.values[0]))
	if not data is Array:
		return GEXResult.fail("PROVIDER_ERROR")
	var result := GEXResult.new()
	for item: Variant in data:
		var metadata := _metadata(item)
		if metadata == null:
			return _malformed()
		if str(item.uniqueName).begins_with(config.slot_prefix):
			result.saves.append(metadata)
	result.completeness = GEXTypes.Completeness.COMPLETE
	return result

func _player(data: Variant) -> GEXTypes.PlayerProfile:
	if not data is Dictionary or not data.get("playerId") is String:
		return null
	var profile := GEXTypes.PlayerProfile.new()
	profile.id = data.playerId
	profile.provider = provider
	profile.id_scope = "PGS game"
	profile.display_name = str(data.get("displayName", ""))
	profile.avatar_uri = str(data.get("iconImageUri", ""))
	return profile

func _entry(data: Variant) -> GEXTypes.LeaderboardEntry:
	if not data is Dictionary or not GEXNativeJson.int64_valid(data.get("rawScore")) \
			or not GEXNativeJson.int64_valid(data.get("rank")):
		return null
	var entry := GEXTypes.LeaderboardEntry.new()
	entry.score = int(data.rawScore)
	entry.rank = int(data.rank)
	entry.formatted_score = str(data.get("displayScore", ""))
	entry.player = _player(data.get("scoreHolder"))
	return entry

func _metadata(data: Variant) -> GEXTypes.SavedGameMetadata:
	if not data is Dictionary or not data.get("uniqueName") is String \
			or not data.get("snapshotId") is String:
		return null
	var metadata := GEXTypes.SavedGameMetadata.new()
	metadata.slot = logical_slot(data.uniqueName)
	metadata.native_id = data.snapshotId
	metadata.description = str(data.get("description", ""))
	metadata.modified_unix = float(data.get("lastModifiedTimestamp", "0")) / 1000.0
	metadata.pending_sync_known = data.has("hasChangePending")
	metadata.pending_sync = bool(data.get("hasChangePending", false))
	return metadata

func _on_conflict(raw: String) -> void:
	var data: Variant = GEXNativeJson.parse(raw)
	if not data is Dictionary:
		return
	var conflict := GEXTypes.SaveConflict.new()
	for key in ["serverSnapshot", "conflictingSnapshot"]:
		if data.get(key) is Dictionary:
			var metadata := _metadata(data[key].get("metadata"))
			if metadata != null:
				conflict.versions.append(metadata)
	if conflict.versions.is_empty():
		return
	_conflict_sequence += 1
	conflict.token = "pgs:%d:%d" % [generation, _conflict_sequence]
	conflict.slot = conflict.versions[0].slot
	conflict.provider = provider
	conflict.generation = generation
	conflict_detected.emit(conflict)
	var channel := "gameSaved" if data.get("origin") == "SAVE" else "gameLoaded"
	if _channels.has(channel):
		(_channels[channel].reply as GEXNativeReply).cancel("CONFLICT_PENDING")
		_native.disconnect(channel, _channels[channel].callback)
		_channels.erase(channel)

func _malformed() -> GEXResult:
	return GEXResult.fail("PROVIDER_ERROR", "Malformed native response; payload omitted.")

func _ambiguous_empty() -> GEXResult:
	return GEXResult.uncertain("AMBIGUOUS_NATIVE_RESULT", "Empty/null may also represent an SDK error.")

func _ui_dispatched() -> GEXResult:
	return GEXResult.uncertain("UI_PRESENTATION_UNOBSERVABLE",
		"PGS screen requested. Wrapper exposes no presentation callback; this is not Sidekick.")
