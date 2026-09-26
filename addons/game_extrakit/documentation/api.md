# Referencia de API

[Manual](README.md) · [Modelos y resultados](results.md) · [Ejemplos de servicios](services.md) · [Ciclo de vida](lifecycle.md)

La fachada es [GEXGameServices](../runtime/game_services.gd), instalada normalmente como autoload `GameServices`. Todos los métodos operativos que devuelven `GEXResult` se invocan con `await`, salvo `initialize()`, que es síncrono. Un rechazo local puede completarse inmediatamente.

Los nombres de los tipos de datos pertenecen a `GEXTypes`. Las tablas indican el dato principal de una respuesta válida; no prometen que todos los campos opcionales estén poblados por todos los proveedores.

## Reglas comunes

- Inicialización, módulo y sesión son requisitos previos; autenticación/refresco no exigen sesión previa.
- Los IDs que recibe el juego son claves de catálogo salvo donde se indique ID nativo.
- Consulta `status`/`is_ok()` antes de usar datos y revisa `delivery`, `completeness` o `*_known` cuando correspondan.
- Los argumentos pueden rechazarse antes de comprobar disponibilidad: el primer error observado no es un inventario de todos los problemas.
- Las operaciones nativas pasan por una cola global. No emitas solicitudes directamente a la dependencia móvil mientras uses esta fachada.
- No hay logout común, paginación común ni reintentos automáticos.

## Inicialización y observación

| Firma | Retorno y comportamiento |
|---|---|
| `initialize(config: GEXConfig) -> GEXResult` | Valida, duplica configuración y prepara un proveedor; no autentica. La instancia debe estar en el árbol |
| `get_provider() -> GEXTypes.Provider` | Proveedor seleccionado o NONE |
| `get_auth_state() -> GEXTypes.AuthState` | Último estado observado; no consulta la red |
| `get_capabilities() -> GEXTypes.Capabilities` | Capacidades, módulos, sesión y limitaciones actuales |
| `get_native_ui_capabilities() -> GEXTypes.Capabilities` | Alias de `get_capabilities()`, no un modelo distinto |
| `get_native_ui_state() -> GEXTypes.NativeUiState` | Lectura de presentación y access point cuando existen |
| `get_interruption_state() -> GEXTypes.InterruptionState` | Snapshot de motivos y estados de interrupción |

`auto_initialize: bool = true` carga el Resource de `game_extrakit/config_path` en `_ready()`. Para administración manual asígnalo a `false` **antes** de añadir el nodo al árbol. Una inicialización repetida sobre una instancia ya preparada devuelve OK sin aplicar la nueva configuración. Tras el cierre crea otra instancia; consulta [Ciclo de vida](lifecycle.md).

## Autenticación, perfil e identidad

Módulo `identity`.

| Firma | Datos y condiciones |
|---|---|
| `authenticate() -> GEXResult` | Solicita autenticación; `player` si existe sesión. Las llamadas simultáneas se agrupan |
| `refresh_auth_state() -> GEXResult` | Reconsulta la sesión. Puede devolver OK y `player=null`, pasando a UNAUTHENTICATED |
| `get_player() -> GEXResult` | Exige sesión observada autenticada; devuelve `player` y actualiza el estado local |
| `get_identity_proof() -> GEXResult` | Devuelve `proof`; en Android exige `android_server_client_id` |
| `set_identity_verifier(verifier: GEXIdentityVerifier) -> void` | Inyecta un Node propiedad del juego, ya dentro del árbol; no lo autentica ni lo libera |
| `verify_player_identity() -> GEXResult` | Obtiene prueba y llama al verificador; `verified_player_id` es el ID del backend |

El verificador HTTP opcional se crea desde `identity_verifier_url` cuando no se inyectó uno antes de inicializar. Sin verificador válido: `BACKEND_NOT_CONFIGURED`. La verificación conserva el ID de solicitud de la prueba; no emite un segundo `operation_completed` para la respuesta HTTP. Espera su retorno directamente.

[Ejemplos de sesión](services.md#autenticacion-y-perfil) · [Contrato de identidad y backend](identity.md).

## Amigos

Módulo `friends`.

`list_friends(limit: int = 25, ask_permission: bool = false, force_refresh: bool = false) -> GEXResult`

Devuelve `friends: Array[PlayerProfile]` y `completeness`. El límite de la API es 1–200; no hay cursor para la página siguiente. `ask_permission=true` permite el flujo nativo de autorización desde una acción del usuario. Apple consulta primero autorización y puede devolver `PERMISSION_REQUIRED` o `PERMISSION_DENIED`.

Android no garantiza completitud y considera vacío/null ambiguo. Apple puede devolver vacío válido y COMPLETE, o PARTIAL si recorta la lista. [Ejemplo y significado](services.md#amigos).

## Logros

Módulo `achievements`.

| Firma | Datos y condiciones |
|---|---|
| `unlock_achievement(key: String) -> GEXResult` | Equivale a progreso 1; la operación registrada es `set_achievement_progress` |
| `set_achievement_progress(key: String, progress: float) -> GEXResult` | Clave configurada; valor absoluto finito 0–1. No promete devolver el estado actualizado |
| `list_achievement_definitions(force_refresh: bool = false) -> GEXResult` | `achievement_definitions`; Android/mock también pueden incluir `achievements` |
| `list_player_achievements(force_refresh: bool = false) -> GEXResult` | `achievements`; puede incluir las definiciones utilizadas para construir el resultado |

En PGS normal solo se admite 0/1; incremental convierte a pasos absolutos. En Apple se reporta porcentaje. `force_refresh` no tiene equivalente en Apple. La lista puede contener elementos remotos sin clave local; no pases una clave vacía a las mutaciones. [Progreso y ejemplos](services.md#logros).

## Rankings

Módulo `leaderboards`. `key` debe existir en `GEXConfig.leaderboards`; `query=null` usa el valor del catálogo o [GEXQuery por defecto](configuration.md#consultas-gexquery).

| Firma | Datos y condiciones |
|---|---|
| `list_leaderboards(force_refresh: bool = false) -> GEXResult` | `leaderboards: Array[LeaderboardInfo]` |
| `submit_score(key: String, score: int) -> GEXResult` | Entero GDScript de 64 bits. OK no implica nuevo récord ni un rank concreto |
| `get_player_score(key: String, query: GEXQuery = null) -> GEXResult` | `own_entry` opcional; no debe leerse como puntuación cero cuando es null |
| `get_top_scores(key: String, query: GEXQuery = null) -> GEXResult` | `entries`, `query` y metadatos disponibles |
| `get_scores_around_player(key: String, query: GEXQuery = null) -> GEXResult` | `entries`, `own_entry` opcional, `centered_known`, `centered_on_player`, `query` |

Las consultas limitan resultados a 1–25. `rank` viene del proveedor, no del índice local. `total_count=-1` significa desconocido; no lo sustituyas por el tamaño de página. Apple puede devolver OK sin puntuación propia; PGS null es ambiguo. [Consultas, periodos y ejemplos](services.md#rankings).

## Partidas

Módulo `cloud_save`. Slots y bytes se validan antes del envío.

| Firma | Datos y condiciones |
|---|---|
| `save_game(slot: String, data: PackedByteArray, description: String = "", played_msec: int = 0, progress_value: int = 0) -> GEXResult` | Guarda bytes opacos; `delivery` y, si existen, `saves`. Descripción <=500 bytes UTF-8; metadatos numéricos no negativos |
| `load_game(slot: String) -> GEXResult` | `bytes`, metadatos opcionales; slot ausente devuelve SAVE_NOT_FOUND, no crea uno |
| `list_saved_games(force_refresh: bool = false) -> GEXResult` | `saves` del prefijo y `completeness`. No descarga contenido de cada partida |
| `delete_saved_game(slot: String) -> GEXResult` | Android resuelve snapshotId; Apple elimina todas las versiones del nombre |
| `resolve_save_conflict(token: String, data: PackedByteArray) -> GEXResult` | Resolución explícita con bytes elegidos por el juego; token no vacío y vigente. Android: UNSUPPORTED_OPERATION |

El presupuesto de `max_save_bytes` también se aplica a la resolución. No hay serialización, cifrado, backup o fusión incorporados. Una lista Apple obtenida durante `load_game` puede incluir metadatos de otros slots del mismo prefijo; usa `metadata.slot`, no la posición de la lista. [Guía completa](cloud-save.md).

## Interfaces nativas

Exigen sesión. Los métodos de logros/rankings exigen sus módulos; los de overlay, access point y destinos generales exigen `identity`.

| Firma | Comportamiento |
|---|---|
| `show_achievements() -> GEXResult` | Solicita pantalla nativa de logros |
| `show_leaderboards() -> GEXResult` | Solicita lista nativa de rankings |
| `show_leaderboard(key: String, query: GEXQuery = null) -> GEXResult` | Abre ranking concreto con scope/period; `limit` no fija el tamaño de UI nativa |
| `show_platform_overlay() -> GEXResult` | Solicita overlay general Apple/mock; Android no soportado |
| `set_platform_entry_point_visible(enabled: bool) -> GEXResult` | Cambia estado activo solicitado; no garantiza visibilidad ni cierra una presentación |
| `set_platform_entry_point_location(location: int) -> GEXResult` | Ubicación 0–3; Android no soportado |
| `show_native_destination(destination: String, key_or_id: String = "") -> GEXResult` | Destino opcional por plataforma/versión |

Para `achievement` y `leaderboard`, el segundo argumento es clave local; para `leaderboard_set`, `challenge` y `activity` es ID nativo de definición. Los demás destinos no requieren identificador. Consulta la [matriz de destinos y ejemplos](native-ui.md).

El resultado de abrir UI no representa su cierre. Android devuelve UNKNOWN; Apple iOS 17 puede devolver UNKNOWN/UI_DISPATCHED para un ranking específico. Observa estado donde esté disponible.

## Ciclo de vida y desarrollo

| Firma | Comportamiento |
|---|---|
| `set_pause_token(token: String, enabled: bool) -> void` | Activa/libera motivo con nombre; vacío se ignora, repetir el mismo token es idempotente |
| `take_pending_activities() -> Array[GEXTypes.NativeActivity]` | Devuelve y vacía la cola de actividades, máximo 32 |
| `cancel_pending_requests() -> void` | Cancela esperas locales, cambia generación e invalida conflictos; no cancela efectos remotos |
| `shutdown() -> void` | Detiene observación, cancela, desconecta proveedor y libera la pausa propia; no elimina el Node ni cierra sesión nativa |
| `get_simulator() -> GEXMockAdapter` | Adaptador de simulación o null; comprobar antes de usar sus controles |

[Sesiones y cierre](lifecycle.md) · [Pausa y actividades](native-ui.md) · [Controles del simulador](simulator.md).

## Señales públicas

Conecta las señales antes de iniciar las operaciones que quieras observar. No hay reproducción automática del último valor al conectar: consulta los getters para el estado inicial.

| Señal | Cuándo y cómo utilizarla |
|---|---|
| `auth_state_changed(state: GEXTypes.AuthState)` | Cambio efectivo de estado de sesión; actualizar disponibilidad de UI |
| `player_changed(player: GEXTypes.PlayerProfile)` | Cambio de ID observado o invalidación; player puede ser null. No indica cualquier cambio cosmético del perfil |
| `capabilities_changed(capabilities: GEXTypes.Capabilities)` | Al inicializar y cambiar auth; recalcular acciones disponibles |
| `save_conflict_detected(conflict: GEXTypes.SaveConflict)` | Conflicto detectado; conservar token solo durante la sesión actual |
| `saved_game_modified(metadata: GEXTypes.SavedGameMetadata)` | Evento Apple de partida modificada; es metadato, no contenido descargado |
| `native_ui_state_changed(state: GEXTypes.NativeUiState)` | Cambio observado de presentación/active/visible; no se emite cada 250 ms si nada cambia |
| `interruption_changed(state: GEXTypes.InterruptionState)` | Estado/motivos de interrupción y tokens; procesar idempotentemente |
| `native_activity_received(activity: GEXTypes.NativeActivity)` | Actividad Apple recibida; también queda en la cola hasta vaciarla |
| `operation_completed(request_id: int, operation: String, status: GEXTypes.Status, error_code: String)` | Final de una operación que pasó por la cola; no incluye el payload |

`operation_completed` no sustituye el retorno: los fallos de validación local y la inicialización no emiten este evento, y varias llamadas de autenticación agrupadas comparten una operación. `_auth_finished` es interna, no parte del contrato público.

Ejemplo de registro sin datos personales ni pruebas:

```gdscript
func conectar_diagnostico() -> void:
    GameServices.operation_completed.connect(_on_operation_completed)

func _on_operation_completed(request_id: int, operation: String,
        status: GEXTypes.Status, error_code: String) -> void:
    print("#%d %s %s %s" % [
        request_id, operation, GEXTypes.Status.keys()[status], error_code])
```

Para conectar una sola vez, hazlo desde un nodo con ciclo de vida controlado. No registres `proof`, códigos OAuth, firmas, bytes ni perfiles completos. [Códigos y recuperación](troubleshooting.md).

