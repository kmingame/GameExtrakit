class_name GEXNativeReply
extends RefCounted
## Private callback mailbox. Receipt only enqueues work on Godot's main thread.

signal completed
var values: Array = []
var error_code: String = ""
var done: bool = false

func receive0() -> void:
	finish.call_deferred([])

func receive1(a: Variant) -> void:
	finish.call_deferred([a])

func receive2(a: Variant, b: Variant) -> void:
	finish.call_deferred([a, b])

func receive3(a: Variant, b: Variant, c: Variant) -> void:
	finish.call_deferred([a, b, c])

func receive4(a: Variant, b: Variant, c: Variant, d: Variant) -> void:
	finish.call_deferred([a, b, c, d])

func finish(arguments: Array) -> void:
	if done:
		return
	values = arguments
	done = true
	completed.emit()

func cancel(code: String = "CANCELLED") -> void:
	if done:
		return
	error_code = code
	done = true
	completed.emit()

func wait() -> GEXNativeReply:
	if not done:
		await completed
	return self
