@tool
class_name GEXLeaderboardDefinition
extends Resource

@export var key: String = ""
@export var android_id: String = ""
@export var apple_id: String = ""
@export var title: String = ""
@export var unit: String = "points"
@export var higher_is_better: bool = true
@export var default_query: GEXQuery

func native_id(provider: GEXTypes.Provider) -> String:
	return android_id if provider == GEXTypes.Provider.ANDROID_PGS else apple_id
