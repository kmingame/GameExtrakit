class_name GEXNativeJson
extends RefCounted
## Preserve JSON integer tokens as strings before Godot's float-based JSON decoder.
## Quoted strings and escapes are left intact. Conversion happens at typed boundaries.

static func parse(text: String) -> Variant:
	var pieces: PackedStringArray = []
	var span_start := 0
	var after_colon := false
	var in_string := false
	var escaped := false
	var index := 0
	while index < text.length():
		var character := text[index]
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				in_string = false
			index += 1
			continue
		if character == '"':
			in_string = true
			after_colon = false
		elif character == "-" or character in "0123456789":
			var end := index + 1
			while end < text.length() and text[end] in "0123456789.eE+-":
				end += 1
			var token := text.substr(index, end - index)
			# Dictionary integer scalars can carry int64 values. Byte arrays stay numeric:
			# their small integers are exactly representable, avoiding millions of strings.
			if after_colon and token.is_valid_int():
				pieces.append(text.substr(span_start, index - span_start))
				pieces.append('"' + token + '"')
				span_start = end
			after_colon = false
			index = end
			continue
		elif character == ":":
			after_colon = true
		elif character not in " \t\r\n":
			after_colon = false
		index += 1
	pieces.append(text.substr(span_start))
	var parser := JSON.new()
	if parser.parse("".join(pieces)) != OK:
		return null
	return parser.data

static func int64_valid(value: Variant) -> bool:
	if value is int:
		return true
	if not value is String or not value.is_valid_int():
		return false
	return str(value.to_int()) == value or value == "-0"
