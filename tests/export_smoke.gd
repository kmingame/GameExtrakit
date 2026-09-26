extends Node

func _ready() -> void:
	var api := get_node("/root/GameServices") as GEXGameServices
	assert(api != null and api.get_provider() == GEXTypes.Provider.MOCK)
	var result := await api.authenticate()
	assert(result.is_ok())
	var bytes := PackedByteArray([0, 128, 255])
	result = await api.save_game("pack_smoke", bytes)
	assert(result.is_ok())
	result = await api.load_game("pack_smoke")
	assert(result.is_ok() and result.bytes == bytes)
	print("GameExtrakit exported PCK: PASS")
	api.shutdown()
	get_tree().quit()
