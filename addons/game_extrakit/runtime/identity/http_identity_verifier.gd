class_name GEXHttpIdentityVerifier
extends GEXIdentityVerifier
## HTTPS JSON contract documented in documentation/identity.md. No redirects or retries.

var endpoint: String = ""
var timeout_seconds: float = 20.0

func verify(proof: GEXTypes.IdentityProof) -> GEXResult:
	if endpoint.is_empty():
		return GEXResult.fail("BACKEND_NOT_CONFIGURED")
	if not endpoint.begins_with("https://"):
		return GEXResult.fail("INVALID_CONFIGURATION", "Verifier must use HTTPS.")
	var payload: Dictionary = {"contract_version": 1, "kind": proof.kind}
	match proof.provider:
		GEXTypes.Provider.ANDROID_PGS:
			payload["authorization_code"] = proof.authorization_code
		GEXTypes.Provider.APPLE_GAME_CENTER:
			payload.merge({"public_key_url": proof.public_key_url,
				"signature_base64": Marshalls.raw_to_base64(proof.signature),
				"salt_base64": Marshalls.raw_to_base64(proof.salt),
				"timestamp": str(proof.timestamp), "team_player_id": proof.signed_player_id,
				"bundle_id": proof.bundle_id})
		_:
			return GEXResult.fail("IDENTITY_VERIFICATION_FAILED", "Mock evidence is not accepted.")
	var request := HTTPRequest.new()
	request.process_mode = Node.PROCESS_MODE_ALWAYS
	request.timeout = timeout_seconds
	request.max_redirects = 0
	request.body_size_limit = 65536
	add_child(request)
	var error := request.request(endpoint, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request.queue_free()
		return GEXResult.fail("NETWORK_UNAVAILABLE")
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return GEXResult.fail("NETWORK_UNAVAILABLE")
	if int(response[1]) != 200:
		return GEXResult.fail("IDENTITY_VERIFICATION_FAILED")
	var data: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary or data.get("verified") != true \
			or not data.get("player_id") is String or data.player_id.is_empty():
		return GEXResult.fail("IDENTITY_VERIFICATION_FAILED")
	var result := GEXResult.new()
	result.provider = proof.provider
	result.verified_player_id = data.player_id
	return result
