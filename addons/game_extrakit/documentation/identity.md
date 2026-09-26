# Verificación opcional de identidad

Sin endpoint ni verificador inyectado se devuelve `BACKEND_NOT_CONFIGURED`. Obtener
una prueba no equivale a verificarla. El backend del juego no fue proporcionado y no
se declara implementado ni probado en este proyecto.

Puedes derivar un Node de `GEXIdentityVerifier`, implementar
`verify(proof: GEXTypes.IdentityProof) -> GEXResult` y pasarlo a
`GameServices.set_identity_verifier(node)`. El juego posee su ciclo de vida.

El cliente HTTP incluido permite configurar un endpoint HTTPS y envía un POST JSON.
No sigue redirecciones, no reintenta y limita la respuesta a 64 KiB. Contrato 1:

```json
{"contract_version":1,"kind":"GOOGLE_SERVER_AUTH_CODE","authorization_code":"..."}
```

O, para Apple:

```json
{
  "contract_version": 1,
  "kind": "APPLE_GAME_CENTER_SIGNATURE",
  "public_key_url": "https://...",
  "signature_base64": "...",
  "salt_base64": "...",
  "timestamp": "1840000000000",
  "team_player_id": "...",
  "bundle_id": "com.example.game"
}
```

El timestamp viaja como cadena decimal para preservar enteros. Respuesta HTTP 200:

```json
{"verified":true,"player_id":"identificador-interno-del-backend"}
```

El servidor debe comprobar la evidencia con Google/Apple, frescura y contexto de app;
no debe confiar en el perfil ni en `bundle_id` suministrado por el cliente. Debe fijar
las URLs y certificados Apple válidos y evitar utilizar una URL arbitraria como
destino confiable. La excepción de identificador de Apple Arcade requiere un verificador
específico y no forma parte del contrato predeterminado de este addon.

No se incluyen secretos ni se persisten códigos o firmas. El verificador HTTP rechaza
evidencia del simulador. Las sesiones/tokens propios del backend deben integrarse en
un verificador del juego, no en los recursos exportados.
