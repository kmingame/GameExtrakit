class_name GEXMockAdapter
extends GEXPlatformAdapter
## Explicit, deterministic, memory-only simulator. No production service is contacted.

var authenticated: bool = false
var player_id: String = ""
var next_error: String = ""
var drop_next_reply: bool = false
var _accounts: Dictionary = {}
var _conflicts: Dictionary = {}
var _presenting: bool = false
var _entry_active: bool = false
var _conflict_sequence: int = 0

func setup(value: GEXConfig) -> GEXResult:
	provider = GEXTypes.Provider.MOCK
	super.setup(value)
	player_id = config.mock_player_id
	capabilities.available = true
	capabilities.can_resolve_save_conflicts = true
	capabilities.can_confirm_save_completion = true
	capabilities.can_open_platform_overlay = true
	capabilities.can_control_entry_point = true
	capabilities.can_observe_platform_overlay = true
	capabilities.available_native_destinations = ["overlay", "achievements", "leaderboards"]
	capabilities.interruption_observation = "SIMULATOR"
	capabilities.limitations = ["SIMULATION: data exists only in memory."]
	return GEXResult.new()

func switch_account(id: String) -> void:
	player_id = id
	authenticated = not id.is_empty()
	session_observed.emit(id, authenticated)

func simulate_conflict(slot: String) -> GEXTypes.SaveConflict:
	_conflict_sequence += 1
	var conflict := GEXTypes.SaveConflict.new()
	conflict.token = "mock:%d:%d" % [generation, _conflict_sequence]
	conflict.slot = slot
	conflict.provider = provider
	conflict.generation = generation
	for index in 2:
		var metadata := GEXTypes.SavedGameMetadata.new()
		metadata.slot = slot
		metadata.native_id = "mock-version-%d" % index
		conflict.versions.append(metadata)
	_conflicts[conflict.token] = conflict
	conflict_detected.emit(conflict)
	return conflict

func simulate_presentation(value: bool) -> void:
	_presenting = value

func invalidate_session(new_generation: int) -> void:
	super.invalidate_session(new_generation)
	_conflicts.clear()
	_presenting = false

func native_ui_state() -> GEXTypes.NativeUiState:
	var state := super.native_ui_state()
	state.presentation = GEXTypes.Presentation.PRESENTING if _presenting \
		else GEXTypes.Presentation.NOT_PRESENTING
	state.source = "SIMULATOR"
	state.entry_point_active = _entry_active
	state.entry_point_visible = _entry_active
	state.observed_at_msec = Time.get_ticks_msec()
	return state

func execute(operation: String, args: Dictionary) -> GEXResult:
	var reply := make_reply()
	if drop_next_reply:
		drop_next_reply = false
	else:
		get_tree().create_timer(config.mock_latency_seconds, true, false, true).timeout.connect(
			reply.finish.bind([]))
	await wait_reply(reply)
	var failure := reply_failure(reply, operation in ["save_game", "submit_score"])
	if failure != null:
		return failure
	if not next_error.is_empty():
		var code := next_error
		next_error = ""
		return GEXResult.fail(code)
	var result := GEXResult.new()
	if operation == "authenticate":
		authenticated = true
	if operation in ["authenticate", "refresh_auth_state", "get_player"]:
		if authenticated:
			result.player = _profile(player_id)
		return result
	if not authenticated:
		return GEXResult.fail("NOT_AUTHENTICATED")
	var account := _account()
	match operation:
		"get_identity_proof":
			result.proof = GEXTypes.IdentityProof.new()
			result.proof.provider = provider
			result.proof.kind = "SIMULATED_NOT_VALID_FOR_BACKEND"
			result.proof.signed_player_id = player_id
		"list_friends":
			for id in ["friend-1", "friend-2", "friend-3"]:
				if result.friends.size() < int(args.limit):
					result.friends.append(_profile(id))
			result.completeness = GEXTypes.Completeness.COMPLETE if int(args.limit) >= 3 \
				else GEXTypes.Completeness.PARTIAL
		"set_achievement_progress":
			var definition: GEXAchievementDefinition = args.definition
			var progress: float = maxf(account.achievements.get(definition.key, 0.0), args.progress)
			account.achievements[definition.key] = progress
			result.achievements.append(_achievement(definition.key, progress))
		"list_player_achievements", "list_achievement_definitions":
			for definition in config.achievements:
				result.achievements.append(_achievement(
					definition.key, account.achievements.get(definition.key, 0.0)))
				var info := GEXTypes.AchievementInfo.new()
				info.key = definition.key
				info.native_id = definition.key
				info.title = definition.title
				info.description = definition.description
				info.incremental = definition.incremental
				info.total_steps = definition.android_total_steps
				result.achievement_definitions.append(info)
		"list_leaderboards":
			for definition in config.leaderboards:
				var info := GEXTypes.LeaderboardInfo.new()
				info.key = definition.key
				info.native_id = definition.key
				info.title = definition.title
				info.unit = definition.unit
				info.higher_is_better = definition.higher_is_better
				result.leaderboards.append(info)
		"submit_score":
			var definition: GEXLeaderboardDefinition = args.definition
			var score: int = args.score
			if account.scores.has(definition.key):
				var previous: int = account.scores[definition.key]
				score = maxi(previous, score) if definition.higher_is_better else mini(previous, score)
			account.scores[definition.key] = score
		"get_player_score", "get_top_scores", "get_scores_around_player":
			result = _scores(operation, args)
		"save_game":
			account.saves[args.slot] = (args.data as PackedByteArray).duplicate()
			result.delivery = GEXTypes.Delivery.PROVIDER_ACCEPTED
			result.message = "Accepted by memory simulator; no remote synchronization."
		"load_game":
			if not account.saves.has(args.slot):
				return GEXResult.fail("SAVE_NOT_FOUND")
			result.bytes = account.saves[args.slot].duplicate()
		"list_saved_games":
			for slot: String in account.saves:
				var metadata := GEXTypes.SavedGameMetadata.new()
				metadata.slot = slot
				metadata.native_id = slot
				result.saves.append(metadata)
			result.completeness = GEXTypes.Completeness.COMPLETE
		"delete_saved_game":
			if not account.saves.erase(args.slot):
				return GEXResult.fail("SAVE_NOT_FOUND")
		"resolve_save_conflict":
			if not _conflicts.has(args.token):
				return GEXResult.fail("CONFLICT_EXPIRED")
			var conflict: GEXTypes.SaveConflict = _conflicts[args.token]
			account.saves[conflict.slot] = (args.data as PackedByteArray).duplicate()
			_conflicts.erase(args.token)
			result.delivery = GEXTypes.Delivery.PROVIDER_ACCEPTED
		"set_platform_entry_point_visible":
			_entry_active = args.enabled
		"set_platform_entry_point_location":
			pass
		"show_platform_overlay", "show_achievements", "show_leaderboards", "show_leaderboard":
			_presenting = true
		"show_native_destination":
			if args.destination not in capabilities.available_native_destinations:
				return GEXResult.fail("UNSUPPORTED_OPERATION")
			_presenting = true
		_:
			return GEXResult.fail("UNSUPPORTED_OPERATION")
	return result

func _account() -> Dictionary:
	if not _accounts.has(player_id):
		_accounts[player_id] = {"achievements": {}, "scores": {}, "saves": {}}
	return _accounts[player_id]

func _profile(id: String) -> GEXTypes.PlayerProfile:
	var player := GEXTypes.PlayerProfile.new()
	player.id = id
	player.display_name = "Simulator / " + id
	player.provider = provider
	player.id_scope = "simulation"
	return player

func _achievement(key: String, progress: float) -> GEXTypes.AchievementState:
	var state := GEXTypes.AchievementState.new()
	state.key = key
	state.native_id = key
	state.progress = progress
	state.unlocked = progress >= 1.0
	return state

func _scores(operation: String, args: Dictionary) -> GEXResult:
	var result := GEXResult.new()
	var definition: GEXLeaderboardDefinition = args.definition
	var query: GEXQuery = args.query
	var entries: Array[GEXTypes.LeaderboardEntry] = []
	var scores: Dictionary = _account().scores
	for index in range(1, 31):
		if query.scope == GEXTypes.Scope.FRIENDS and index > 3:
			break
		var entry := GEXTypes.LeaderboardEntry.new()
		entry.player = _profile("friend-%d" % index)
		entry.score = index * 100 + int(query.period) * 10
		entries.append(entry)
	if scores.has(definition.key):
		var own := GEXTypes.LeaderboardEntry.new()
		own.player = _profile(player_id)
		own.score = scores[definition.key]
		entries.append(own)
		result.own_entry = own
	entries.sort_custom(func(a: GEXTypes.LeaderboardEntry, b: GEXTypes.LeaderboardEntry) -> bool:
		return a.score > b.score if definition.higher_is_better else a.score < b.score)
	for index in entries.size():
		entries[index].rank = index + 1
		if index > 0 and entries[index].score == entries[index - 1].score:
			entries[index].rank = entries[index - 1].rank
		entries[index].formatted_score = str(entries[index].score)
	result.total_count = entries.size()
	var start: int = 0
	if operation == "get_scores_around_player" and result.own_entry != null:
		start = maxi(0, entries.find(result.own_entry) - query.limit / 2)
		start = mini(start, maxi(0, entries.size() - query.limit))
		result.centered_on_player = true
	result.centered_known = true
	if operation != "get_player_score":
		result.entries.assign(entries.slice(start, start + query.limit))
	result.query = query
	return result
