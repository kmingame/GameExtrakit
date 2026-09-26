# Verificación opcional de identidad

[Manual](README.md) · [Sesión y perfil](services.md#autenticacion-y-perfil) · [Modelos](results.md) · [Plataformas](platforms.md)

Autenticarse en el proveedor, obtener una prueba y verificarla en el servidor son pasos diferentes. GameExtrakit ofrece el cliente y el punto de extensión; el backend real del juego no está implementado ni probado aquí.

## Elegir un modo

| Modo | Configuración | Resultado |
|---|---|---|
| Solo servicios nativos | Endpoint vacío, sin verificador | Puedes autenticar y usar servicios. Verificar devuelve BACKEND_NOT_CONFIGURED |
| Cliente HTTP incluido | `identity_verifier_url=https://...` | La fachada crea GEXHttpIdentityVerifier al inicializar si no hay uno inyectado |
| Verificador del juego | Node derivado de GEXIdentityVerifier | Inyecta con set_identity_verifier; el juego administra su ciclo de vida |

Para Google añade `android_server_client_id`, el ID público del cliente OAuth de servidor. El Game ID del preset cumple otra función. Para Apple configura `apple_bundle_id`, coherente con la app. No incluyas secretos en Resources, código cliente, export presets públicos ni logs.

## Flujo

1. Prepara el servicio y autentica al jugador.
2. `get_identity_proof()` solicita evidencia nativa, sin validarla.
3. `verify_player_identity()` obtiene esa prueba y espera a `verifier.verify(proof)`.
4. El servidor comprueba la evidencia y devuelve su ID interno.
5. Si cambió la generación de sesión mientras esperaba, la fachada descarta el resultado.

```gdscript
func verificar_sesion_en_backend() -> String:
    var result := await GameServices.verify_player_identity()
    if not result.is_ok():
        push_warning("Verificación: " + result.error_code)
        return ""
    return result.verified_player_id
```

La función presupone autenticación y verificador configurados. No imprimas la prueba para depurar. El ID verificado no reemplaza `PlayerProfile.id` dentro de las consultas nativas.

## Evidencia por proveedor

| Proveedor | kind | Contenido |
|---|---|---|
| Google | GOOGLE_SERVER_AUTH_CODE | `authorization_code`, obtenido mediante requestServerSideAccess con el ID público de servidor |
| Apple | APPLE_GAME_CENTER_SIGNATURE | URL pública de clave, firma, salt, timestamp, teamPlayerID y Bundle ID configurado |
| Mock | SIMULATED_NOT_VALID_FOR_BACKEND | Marcador de simulación; rechazado por el cliente HTTP incluido |

Apple usa `gamePlayerID` en el perfil y `teamPlayerID` en la prueba. No los intercambies. La excepción de Apple Arcade exige un verificador específico y queda fuera del contrato predeterminado.

El addon no conserva ni renueva tokens OAuth de servidor. Obtener evidencia no acredita por sí mismo que quien llama al backend sea el jugador declarado.

## Contrato HTTP 1

Implementado en [GEXHttpIdentityVerifier](../runtime/identity/http_identity_verifier.gd).

| Opción | Valor |
|---|---|
| endpoint | URL HTTPS de configuración |
| Método | POST |
| Content-Type | application/json |
| timeout_seconds | Copia del timeout configurado, 20 segundos por defecto |
| Redirecciones | 0; una redirección no es una verificación satisfactoria |
| Tamaño máximo de respuesta | 65536 bytes (64 KiB) |
| Reintentos | Ninguno |
| Procesamiento | HTTPRequest puede continuar durante pausa de SceneTree |
| Autenticación adicional/cabeceras propias | No incluidas; usa un verificador propio si se requieren |

Petición Google:

```json
{
  "contract_version": 1,
  "kind": "GOOGLE_SERVER_AUTH_CODE",
  "authorization_code": "codigo-obtenido-del-proveedor"
}
```

Petición Apple:

```json
{
  "contract_version": 1,
  "kind": "APPLE_GAME_CENTER_SIGNATURE",
  "public_key_url": "https://dominio-validado-del-proveedor/clave",
  "signature_base64": "firma-en-base64",
  "salt_base64": "salt-en-base64",
  "timestamp": "1840000000000",
  "team_player_id": "identificador-firmado",
  "bundle_id": "com.example.game"
}
```

Son ejemplos de estructura con marcadores, no pruebas válidas. Timestamp viaja como **cadena decimal**, para preservar el entero. Firma y salt viajan en Base64. No se envía el perfil completo ni un campo provider separado: el discriminador es kind.

Respuesta aceptada: HTTP **200**, cuerpo JSON de tipo objeto, `verified` igual a booleano true y `player_id` String no vacío:

```json
{
  "verified": true,
  "player_id": "identificador-interno-del-backend"
}
```

El cliente solo consume esos dos campos; no almacena tokens de sesión añadidos al cuerpo. Un ID por sí solo no establece una sesión autenticada para futuras peticiones del juego.

| Situación | Resultado del cliente |
|---|---|
| No se configuró verificador/endpoint | BACKEND_NOT_CONFIGURED |
| Endpoint sin HTTPS | INVALID_CONFIGURATION |
| Proveedor simulado/no aceptado | IDENTITY_VERIFICATION_FAILED |
| Error de inicio de request, transporte, timeout HTTP o respuesta que excede el presupuesto | NETWORK_UNAVAILABLE |
| HTTP distinto de 200 | IDENTITY_VERIFICATION_FAILED |
| JSON inválido, verified distinto de true, player_id que no es String o está vacío | IDENTITY_VERIFICATION_FAILED |
| Cambió la sesión mientras esperaba la fachada | SESSION_CHANGED |

Un rechazo del cliente no detiene necesariamente un proceso ya iniciado en el servidor. `operation_completed` registra la obtención de la prueba; el resultado final del backend se recoge con el await de `verify_player_identity()`.

## Verificador personalizado

[GEXIdentityVerifier](../runtime/identity/identity_verifier.gd) es un Node cuya implementación base devuelve BACKEND_NOT_CONFIGURED. El override debe implementar:

```gdscript
extends GEXIdentityVerifier

func verify(_proof: GEXTypes.IdentityProof) -> GEXResult:
    # Sustituye este rechazo por la petición y validación de TU protocolo.
    # Nunca devuelvas OK solo por recibir un ID o una prueba no vacía.
    return GEXResult.fail("BACKEND_NOT_CONFIGURED",
        "Falta implementar el protocolo del servidor del juego.")
```

El ejemplo es una base segura, no un verificador funcional. Puedes alojar lógica de autenticación adicional, tokens propios y políticas del servidor en tu implementación.

Para instalar un Node ya construido:

```gdscript
func instalar_verificador(verifier: GEXIdentityVerifier) -> void:
    if not verifier.is_inside_tree():
        add_child(verifier)
    GameServices.set_identity_verifier(verifier)
```

El juego posee ese Node y debe mantenerlo vivo durante las verificaciones. Si sustituyes el verificador o le pasas null, gestiona tú el cierre/liberación del anterior; no se libera automáticamente. Inyectar uno antes de `initialize()` evita crear el HTTP por defecto. [Inicialización manual](lifecycle.md).

## Responsabilidades del servidor

El servidor debe verificar la evidencia mediante el procedimiento oficial Google/Apple, contexto de app, frescura y medidas contra reutilización adecuadas a su protocolo. No debe confiar en el nombre, ID de perfil ni Bundle ID recibidos del cliente como autoridades.

Las URLs/certificados de clave Apple deben validarse antes de usarse; una URL arbitraria del cuerpo no es un destino confiable de descarga. Los secretos OAuth y claves del backend permanecen en el servidor. Si necesitas unir cuentas entre proveedores, eso requiere un diseño independiente fuera de este addon.

Prueba evidencia válida, manipulada, antigua, de otra app, red caída y cambio de cuenta durante la respuesta. La lista completa de aceptación está en [Validación](validation.md); el simulador no certifica identidad.
