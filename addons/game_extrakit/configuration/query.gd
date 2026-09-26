@tool
class_name GEXQuery
extends Resource
## Periods preserve each provider's calendar. No pagination is synthesized.

@export var scope: GEXTypes.Scope = GEXTypes.Scope.GLOBAL
@export var period: GEXTypes.Period = GEXTypes.Period.ALL_TIME
@export_range(1, 25, 1) var limit: int = 10
@export var force_refresh: bool = false

func is_valid() -> bool:
	return limit >= 1 and limit <= 25 and scope in [0, 1] and period in [0, 1, 2]
