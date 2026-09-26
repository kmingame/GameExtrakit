class_name GEXRequestCoordinator
extends Node
## FIFO also serializes slot mutations and queries lacking native request IDs.

class Request extends RefCounted:
	signal completed
	var id: int
	var generation: int
	var operation: String
	var arguments: Dictionary
	var result: GEXResult
	func finish(value: GEXResult) -> void:
		if result != null:
			return
		result = value
		result.request_id = id
		result.operation = operation
		completed.emit()

var adapter: GEXPlatformAdapter
var generation: int = 0
var _next_id: int = 1
var _queue: Array[Request] = []
var _active: Request
var _pumping: bool = false

func submit(operation: String, arguments: Dictionary) -> GEXResult:
	var request := Request.new()
	request.id = _next_id
	_next_id += 1
	request.operation = operation
	request.arguments = arguments
	request.generation = generation
	_queue.append(request)
	_pump.call_deferred()
	if request.result == null:
		await request.completed
	return request.result

func cancel_all(code: String = "CANCELLED") -> void:
	generation += 1
	for request in _queue:
		request.finish(GEXResult.fail(code))
	_queue.clear()
	if _active != null:
		var result := GEXResult.fail(code)
		if _active.operation in ["save_game", "delete_saved_game", "submit_score",
				"set_achievement_progress", "resolve_save_conflict"]:
			result = GEXResult.uncertain(code, "Cancellation is local; native work may finish.")
		result.provider = adapter.provider
		_active.finish(result)
	if adapter != null:
		adapter.invalidate_session(generation)

func _pump() -> void:
	if _pumping or _queue.is_empty() or adapter == null:
		return
	_pumping = true
	_active = _queue.pop_front()
	var request := _active
	var result: GEXResult = await adapter.execute(request.operation, request.arguments)
	if request.generation != generation:
		result = GEXResult.fail("SESSION_CHANGED")
	result.provider = adapter.provider
	request.finish(result)
	_active = null
	_pumping = false
	_pump.call_deferred()
