# Contrato 0.1

`GameServices` es el autoload; `GEXGameServices` permite instancias controladas por el
juego. Para estas últimas, asigna `auto_initialize = false` **antes** de agregarlas al
árbol y llama a `initialize(config)`. Inicializar prepara la dependencia sin abrir el
inicio de sesión. Se selecciona el proveedor una vez por ciclo de vida. Tras `shutdown`,
crea una instancia nueva. En Android solo puede haber un propietario del singleton nativo.

Las operaciones se pueden esperar con `await`, aunque ciertos errores locales se
resuelven inmediatamente. No hagas llamadas paralelas a los clientes de la dependencia
por fuera de GameExtrakit: romperían la correlación de sus señales compartidas.

## API pública

| Área | Métodos |
|---|---|
| Inicio | `initialize(config)`, `get_provider()`, `get_capabilities()` |
| Sesión | `authenticate()`, `refresh_auth_state()`, `get_auth_state()`, `get_player()` |
| Identidad | `get_identity_proof()`, `verify_player_identity()`, `set_identity_verifier(node)` |
| Amigos | `list_friends(limit=25, ask_permission=false, force_refresh=false)` |
| Logros | `unlock_achievement(key)`, `set_achievement_progress(key, progress)`, `list_achievement_definitions(force_refresh=false)`, `list_player_achievements(force_refresh=false)` |
| Rankings | `list_leaderboards(force_refresh=false)`, `submit_score(key, int64)`, `get_player_score(key, query=null)`, `get_top_scores(key, query=null)`, `get_scores_around_player(key, query=null)` |
| Partidas | `save_game(slot, bytes, description="", played_msec=0, progress_value=0)`, `load_game(slot)`, `list_saved_games(force_refresh=false)`, `delete_saved_game(slot)`, `resolve_save_conflict(token, bytes)` |
| UI nativa | `show_achievements()`, `show_leaderboards()`, `show_leaderboard(key, query=null)`, `show_platform_overlay()`, `show_native_destination(destination, key_or_id="")` |
| Access point | `set_platform_entry_point_visible(enabled)`, `set_platform_entry_point_location(location)` |
| Observación | `get_native_ui_capabilities()`, `get_native_ui_state()`, `get_interruption_state()` |
| Ciclo de vida | `cancel_pending_requests()`, `shutdown()`, `set_pause_token(token, enabled)`, `take_pending_activities()` |
| Desarrollo | `get_simulator()` devuelve `GEXMockAdapter` únicamente en simulación |

No hay logout universal. `refresh_auth_state` conserva el comportamiento nativo: la
comprobación PGS puede mostrar su popup; no se promete una comprobación silenciosa idéntica.

## Resultados y datos

`GEXResult` contiene `request_id`, `operation`, `provider`, `status`, `error_code`,
`message`, `native_code`, `delivery` y campos tipados opcionales. No expone objetos
GameKit ni diccionarios de PGS. Los perfiles, estados, entradas, metadatos, capacidades
y conflictos están definidos en `GEXTypes`.

| Estado | Significado |
|---|---|
| `OK` | Operación completada según el contrato específico; abrir UI significa solicitud enviada |
| `FAILED` | Fallo conocido o validación rechazada |
| `CANCELLED` | Espera local cancelada o sesión invalidada |
| `UNSUPPORTED` | Operación/plataforma sin soporte |
| `UNKNOWN` | La evidencia no distingue éxito y fallo; no equivale a un fallo reintentable |

`is_ok()` solo devuelve true para `OK`. Guardados Apple aceptados usan
`delivery=PROVIDER_ACCEPTED`; ningún adaptador declara `SYNC_CONFIRMED` sin evidencia.
PGS conserva `status=UNKNOWN` y `delivery=UNKNOWN` al recibir `gameSaved(true, ...)`.

Los IDs son opacos. Un `PlayerProfile.id` Apple es `gamePlayerID`; la prueba de
identidad usa `teamPlayerID` por separado. No cruces identidades de ambos proveedores.
No registres pruebas de identidad, firmas, códigos OAuth ni bytes de partidas.

## Consultas y límites adoptados

`GEXQuery` es un Resource con `scope=GLOBAL/FRIENDS`,
`period=DAILY/WEEKLY/ALL_TIME`, `limit=1..25`, `force_refresh`. Los enums se traducen
explícitamente a cada binding. Los calendarios son nativos y no son temporadas comunes.
Apple no ofrece equivalente para `force_refresh`; se conserva como preferencia sin
promesa de frescura. La consulta cercana Apple usa hasta dos lecturas y no es atómica.

Amigos solicita 1..200 entradas como límite de la API del addon. PGS devuelve una página
sin continuación ni prueba de completitud; su lista vacía puede ocultar un error y
se marca `UNKNOWN`. Apple devuelve los amigos autorizados y recorta al límite pedido,
marcando `PARTIAL` si corresponde. Esto no representa todos los contactos del usuario.

Progreso: número finito entre 0 y 1. PGS incremental usa pasos absolutos
`floor(progress * total_steps)`, nunca incrementos relativos; cero no se envía.
Se contrastan tipo/pasos con metadatos PGS antes de mutar. `achievementUnlocked(false)`
es ambiguo para progresivos. Un logro PGS normal no admite progreso parcial.
Apple usa porcentaje absoluto y conserva la monotonicidad de GameKit.

Slots: 1..100 caracteres ASCII `[A-Za-z0-9._~-]`, incluyendo prefijo. Presupuesto
de aplicación predeterminado: 1 MiB, configurable hasta 3 MiB. No se presenta como
garantía de cuota Apple. Descripción: presupuesto conservador de 500 bytes UTF-8.
Se aceptan bytes vacíos. `delete_saved_game` Apple elimina todas las versiones con
ese nombre; Android resuelve primero el `snapshotId` a partir del slot.

El juego conserva su respaldo local y decide cuándo reemplazarlo. GameExtrakit no
impone formato, fusión, reintentos ni sincronización entre proveedores.

## Solicitudes y sesiones

FIFO global: serializa mutaciones, consultas de mismo leaderboard/períodos diferentes
y operaciones compuestas. Cada espera nativa tiene timeout en tiempo real y continúa
procesándose durante pausa. No se reintentan mutaciones automáticamente.

Android mantiene un canal bloqueado después de timeout/cancelación hasta que drena la
respuesta original. Devuelve `REQUEST_CHANNEL_BUSY` mientras tanto. Si se destruye
el adaptador con canales pendientes, se bloquean para el resto del proceso: reiniciar
la app es la única manera segura de iniciar otra época nativa sin IDs de correlación.

Cambiar de jugador incrementa la generación, cancela solicitudes y caduca conflictos.
Se revalida identidad antes y después de las operaciones nativas y al reanudar. Esto
descarta datos cruzados observables; no puede cancelar efectos remotos que el SDK ya
inició durante un cambio de cuenta. La cancelación de una mutación en vuelo es `UNKNOWN`.

Errores adicionales: `NOT_INITIALIZED`, `FEATURE_DISABLED`, `DEPENDENCY_MISSING`,
`INVALID_CONFIGURATION`, `INVALID_ARGUMENT`, `NOT_AUTHENTICATED`, `AUTHENTICATION_FAILED`,
`PERMISSION_REQUIRED`, `PERMISSION_DENIED`, `USER_CANCELLED`, `NETWORK_UNAVAILABLE`,
`TIMEOUT`, `PROVIDER_ERROR`, `SAVE_NOT_FOUND`, `CONFLICT_PENDING`, `CONFLICT_EXPIRED`,
`BACKEND_NOT_CONFIGURED`, `IDENTITY_VERIFICATION_FAILED`, `SESSION_CHANGED`,
`AMBIGUOUS_NATIVE_RESULT`, `SAVE_COMPLETION_UNVERIFIABLE`, `UI_PRESENTATION_UNOBSERVABLE`.

## UI e interrupciones

Apple consulta `is_presenting_game_center` cada 250 ms mientras el adaptador está
activo, incluso con gameplay pausado o acceso oculto. `active`, `visible` y
presentación son estados diferentes. PGS no ofrece estado de Sidekick: permanece
`UNKNOWN` aunque el motor recupere foco.

Destinos comunes: `overlay`, `achievements`, `leaderboards`, `leaderboard`.
Apple añade `profile`, `friends`; desde iOS 18: `achievement`, `leaderboard_set`;
desde iOS 26: `challenges`, `challenge`, `friending`, `play_together`, `activity`.
La lista se filtra por versión y módulos. Consultarla no implica que el usuario esté
autenticado. El método valida la sesión antes de presentar. `activity` y `challenge`
reciben IDs de definiciones ya creadas; no administran retos ni actividades remotas.

Por defecto se emiten motivos y el gestor del juego decide la pausa. Si se activa
`manage_scene_tree_pause`, **todas las nuevas pausas del juego deben usar tokens**:

```gdscript
GameServices.set_pause_token("menu", true)
# ...
GameServices.set_pause_token("menu", false)
```

Se preserva una pausa previa de SceneTree. No existe una API del motor para distinguir
una asignación externa `paused=true` que ocurra cuando ya está pausado: usa tokens o
el modo solo eventos si tu gestor escribe directamente `SceneTree.paused`.
Foco, suspensión y presentación son motivos separados y deduplicados. La recuperación
de foco no libera los demás. No hay timeout que fuerce reanudar gameplay.

Las actividades Apple entrantes se encolan (máximo 32) y se emiten como datos; el juego
las recoge con `take_pending_activities`. No se cambia de escena. La aceptación nativa
ya ocurre en el binding: no se ofrece rechazarla retroactivamente.
