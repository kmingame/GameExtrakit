@tool
class_name GEXConfig
extends Resource
## Public configuration only. Never store OAuth secrets or private keys here.

@export var schema_version: int = 1
@export_group("General")
@export var android_enabled: bool = false
@export var apple_enabled: bool = false
@export var mock_enabled: bool = false
@export var allow_mock_in_release: bool = false
@export_range(0.1, 120.0, 0.1, "suffix:s") var timeout_seconds: float = 20.0
@export_group("Modules")
@export var identity_enabled: bool = true
@export var friends_enabled: bool = true
@export var achievements_enabled: bool = true
@export var leaderboards_enabled: bool = true
@export var cloud_save_enabled: bool = true
@export_group("Android")
## Game ID lives ONLY in godot_play_game_services/game_id in the export preset.
@export var android_server_client_id: String = ""
@export_group("Apple")
@export var apple_bundle_id: String = ""
@export var apple_icloud_container: String = ""
@export_range(17, 99, 1) var apple_minimum_ios: int = 17
@export_group("Catalogs")
@export var achievements: Array[GEXAchievementDefinition] = []
@export var leaderboards: Array[GEXLeaderboardDefinition] = []
@export_group("Cloud Save")
@export var slot_prefix: String = ""
## Application budget, not a claim about the provider maximum. PGS supports 3 MiB.
@export_range(1, 3145728, 1, "suffix:bytes") var max_save_bytes: int = 1048576
@export_group("Native UI and interruptions")
@export var apple_entry_point_active: bool = false
@export_enum("Top leading", "Top trailing", "Bottom leading", "Bottom trailing")
var apple_entry_point_location: int = 0
@export var apple_show_highlights: bool = true
@export var pause_on_focus_loss: bool = false
@export var pause_on_suspend: bool = true
@export var pause_on_native_ui: bool = true
## Emit reasons by default. With ownership enabled, all game pauses use pause tokens.
@export var manage_scene_tree_pause: bool = false
@export_group("Identity verification")
@export var identity_verifier_url: String = ""
@export_group("Simulator")
@export_range(0.0, 10.0, 0.01, "suffix:s") var mock_latency_seconds: float = 0.05
@export var mock_player_id: String = "simulated-player"

func module_enabled(module: String) -> bool:
	return bool(get(module + "_enabled"))

func achievement(key: String) -> GEXAchievementDefinition:
	for item in achievements:
		if item != null and item.key == key:
			return item
	return null

func leaderboard(key: String) -> GEXLeaderboardDefinition:
	for item in leaderboards:
		if item != null and item.key == key:
			return item
	return null

func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	if schema_version != 1:
		issues.append("Unsupported configuration schema; expected 1.")
	if timeout_seconds <= 0.0 or not is_finite(timeout_seconds):
		issues.append("Timeout must be positive and finite.")
	if max_save_bytes < 1 or max_save_bytes > 3145728:
		issues.append("Save budget must be between 1 and 3145728 bytes.")
	if not identity_enabled and (friends_enabled or achievements_enabled
			or leaderboards_enabled or cloud_save_enabled):
		issues.append("Identity must be enabled for the other modules.")
	if apple_enabled and (apple_bundle_id.is_empty() or apple_minimum_ios < 17):
		issues.append("Apple requires a Bundle ID and minimum iOS 17.")
	if apple_enabled and cloud_save_enabled and apple_icloud_container.is_empty():
		issues.append("Apple Cloud Save requires an iCloud container.")
	if not identity_verifier_url.is_empty() and not identity_verifier_url.begins_with("https://"):
		issues.append("Identity verifier must use HTTPS.")
	if not slot_prefix.is_empty() and not valid_slot(slot_prefix):
		issues.append("Invalid slot prefix.")
	if apple_entry_point_location not in [0, 1, 2, 3]:
		issues.append("Invalid Apple access point location.")
	_validate_catalog(achievements, "achievement", issues)
	_validate_catalog(leaderboards, "leaderboard", issues)
	for item in achievements:
		if item != null and item.incremental and item.android_total_steps < 1:
			issues.append("Incremental achievement needs positive steps: " + item.key)
	for item in leaderboards:
		if item != null and item.default_query != null and not item.default_query.is_valid():
			issues.append("Invalid default query: " + item.key)
	return issues

func _validate_catalog(items: Array, kind: String, issues: PackedStringArray) -> void:
	var keys: Dictionary = {}
	var android_ids: Dictionary = {}
	var apple_ids: Dictionary = {}
	for item: Resource in items:
		if item == null:
			issues.append("Null entry in " + kind + " catalog.")
			continue
		if item.key.is_empty() or keys.has(item.key):
			issues.append("Missing/duplicate " + kind + " key: " + item.key)
		keys[item.key] = true
		if android_enabled and (item.android_id.is_empty() or android_ids.has(item.android_id)):
			issues.append("Missing/duplicate Android ID: " + item.key)
		if apple_enabled and (item.apple_id.is_empty() or apple_ids.has(item.apple_id)):
			issues.append("Missing/duplicate Apple ID: " + item.key)
		android_ids[item.android_id] = true
		apple_ids[item.apple_id] = true

static func valid_slot(slot: String) -> bool:
	if slot.length() < 1 or slot.length() > 100:
		return false
	for code in slot.to_utf8_buffer():
		if not (code >= 65 and code <= 90 or code >= 97 and code <= 122
				or code >= 48 and code <= 57 or code in [45, 46, 95, 126]):
			return false
	return true
