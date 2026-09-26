class_name GEXResult
extends RefCounted
## Only Status.OK means success. UNKNOWN must never trigger a blind retry.

var request_id: int = 0
var status: GEXTypes.Status = GEXTypes.Status.OK
var provider: GEXTypes.Provider = GEXTypes.Provider.NONE
var operation: String = ""
var error_code: String = ""
var message: String = ""
var native_code: String = ""
var delivery: GEXTypes.Delivery = GEXTypes.Delivery.UNKNOWN
var player: GEXTypes.PlayerProfile
var proof: GEXTypes.IdentityProof
var friends: Array[GEXTypes.PlayerProfile] = []
var achievement_definitions: Array[GEXTypes.AchievementInfo] = []
var achievements: Array[GEXTypes.AchievementState] = []
var leaderboards: Array[GEXTypes.LeaderboardInfo] = []
var entries: Array[GEXTypes.LeaderboardEntry] = []
var own_entry: GEXTypes.LeaderboardEntry
var saves: Array[GEXTypes.SavedGameMetadata] = []
var bytes: PackedByteArray = []
var completeness: GEXTypes.Completeness = GEXTypes.Completeness.UNKNOWN
var centered_on_player: bool = false
var centered_known: bool = false
var total_count: int = -1
var verified_player_id: String = ""
var query: GEXQuery

func is_ok() -> bool:
	return status == GEXTypes.Status.OK

static func fail(code: String, detail: String = "") -> GEXResult:
	var result := GEXResult.new()
	result.status = GEXTypes.Status.FAILED
	result.error_code = code
	result.message = detail
	if code.begins_with("UNSUPPORTED"):
		result.status = GEXTypes.Status.UNSUPPORTED
	elif code == "CANCELLED" or code == "SESSION_CHANGED":
		result.status = GEXTypes.Status.CANCELLED
	return result

static func uncertain(code: String, detail: String) -> GEXResult:
	var result := fail(code, detail)
	result.status = GEXTypes.Status.UNKNOWN
	return result
