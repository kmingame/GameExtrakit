class_name GEXTypes
extends RefCounted
## Contract 0.1. Native objects never leave the adapters.

enum Provider { NONE, ANDROID_PGS, APPLE_GAME_CENTER, MOCK }
enum Status { OK, FAILED, CANCELLED, UNSUPPORTED, UNKNOWN }
enum AuthState { UNKNOWN, AUTHENTICATING, AUTHENTICATED, UNAUTHENTICATED }
enum Delivery { UNKNOWN, PROVIDER_ACCEPTED, PENDING_SYNC, SYNC_CONFIRMED }
enum Scope { GLOBAL, FRIENDS }
enum Period { DAILY, WEEKLY, ALL_TIME }
enum Presentation { UNKNOWN, NOT_PRESENTING, PRESENTING }
enum Completeness { UNKNOWN, PARTIAL, COMPLETE }

class PlayerProfile extends RefCounted:
	var provider: Provider = Provider.NONE
	var id: String = ""
	var id_scope: String = ""
	var display_name: String = ""
	var avatar_uri: String = ""

class IdentityProof extends RefCounted:
	var provider: Provider = Provider.NONE
	var kind: String = ""
	var authorization_code: String = ""
	var public_key_url: String = ""
	var signature: PackedByteArray = []
	var salt: PackedByteArray = []
	var timestamp: int = 0
	var signed_player_id: String = ""
	var bundle_id: String = ""

class AchievementInfo extends RefCounted:
	var key: String = ""
	var native_id: String = ""
	var title: String = ""
	var description: String = ""
	var incremental: bool = false
	var total_steps: int = 0

class AchievementState extends RefCounted:
	var key: String = ""
	var native_id: String = ""
	var progress: float = 0.0
	var unlocked: bool = false

class LeaderboardInfo extends RefCounted:
	var key: String = ""
	var native_id: String = ""
	var title: String = ""
	var unit: String = ""
	var higher_is_better: bool = true

class LeaderboardEntry extends RefCounted:
	var player: PlayerProfile
	var score: int = 0
	var formatted_score: String = ""
	var rank: int = 0

class SavedGameMetadata extends RefCounted:
	var slot: String = ""
	var native_id: String = ""
	var modified_unix: float = 0.0
	var description: String = ""
	var device_name: String = ""
	var pending_sync: bool = false
	var pending_sync_known: bool = false

class SaveConflict extends RefCounted:
	var token: String = ""
	var slot: String = ""
	var provider: Provider = Provider.NONE
	var generation: int = 0
	var versions: Array[SavedGameMetadata] = []

class NativeUiState extends RefCounted:
	var presentation: Presentation = Presentation.UNKNOWN
	var provider: Provider = Provider.NONE
	var source: String = "UNAVAILABLE"
	var destination: String = ""
	var observed_at_msec: int = 0
	var entry_point_active: bool = false
	var entry_point_visible: bool = false

class InterruptionState extends RefCounted:
	var focus_lost: bool = false
	var suspended: bool = false
	var native_presenting: bool = false
	var pause_reasons: PackedStringArray = []

class NativeActivity extends RefCounted:
	var id: String = ""
	var definition_id: String = ""
	var generation: int = 0

class Capabilities extends RefCounted:
	var provider: Provider = Provider.NONE
	var available: bool = false
	var authenticated: bool = false
	var enabled_modules: PackedStringArray = []
	var max_score_results: int = 25
	var friends_completeness: Completeness = Completeness.UNKNOWN
	var can_resolve_save_conflicts: bool = false
	var can_confirm_save_completion: bool = false
	var can_open_platform_overlay: bool = false
	var can_control_entry_point: bool = false
	var can_observe_platform_overlay: bool = false
	var has_overlay_visibility_signal: bool = false
	var can_open_achievements: bool = false
	var can_open_leaderboards: bool = false
	var available_native_destinations: PackedStringArray = []
	var interruption_observation: String = "GODOT_LIFECYCLE"
	var limitations: PackedStringArray = []
