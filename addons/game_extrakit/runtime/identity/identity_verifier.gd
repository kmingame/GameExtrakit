class_name GEXIdentityVerifier
extends Node
## Override verify() to integrate a game's backend. Evidence is not verified locally.

func verify(_proof: GEXTypes.IdentityProof) -> GEXResult:
	return GEXResult.fail("BACKEND_NOT_CONFIGURED")
