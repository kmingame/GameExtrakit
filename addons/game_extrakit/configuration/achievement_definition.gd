@tool
class_name GEXAchievementDefinition
extends Resource
## Local catalog mapping; this does not create a console achievement.

@export var key: String = ""
@export var android_id: String = ""
@export var apple_id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var incremental: bool = false
@export_range(1, 2147483647, 1) var android_total_steps: int = 1

func native_id(provider: GEXTypes.Provider) -> String:
	return android_id if provider == GEXTypes.Provider.ANDROID_PGS else apple_id
