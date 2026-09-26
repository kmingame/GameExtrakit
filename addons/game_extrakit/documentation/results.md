# Resultados, modelos y capacidades

[Manual](README.md) · [API](api.md) · [Errores](troubleshooting.md)

Fuentes: [GEXResult](../runtime/models/result.gd) y [GEXTypes](../runtime/models/types.gd). Los modelos son `RefCounted`, sin objetos nativos de GameKit/PGS expuestos. Trátalos como snapshots de lectura, no como una API de escritura al proveedor.

## Estados y enums

Usa nombres de enum; los valores numéricos siguientes describen el contrato actual y no sustituyen los enums de los SDKs.

| Enum GEXTypes | Valores |
|---|---|
| `Provider` | NONE=0, ANDROID_PGS=1, APPLE_GAME_CENTER=2, MOCK=3 |
| `Status` | OK=0, FAILED=1, CANCELLED=2, UNSUPPORTED=3, UNKNOWN=4 |
| `AuthState` | UNKNOWN=0, AUTHENTICATING=1, AUTHENTICATED=2, UNAUTHENTICATED=3 |
| `Delivery` | UNKNOWN=0, PROVIDER_ACCEPTED=1, PENDING_SYNC=2, SYNC_CONFIRMED=3 |
| `Scope` | GLOBAL=0, FRIENDS=1 |
| `Period` | DAILY=0, WEEKLY=1, ALL_TIME=2 |
| `Presentation` | UNKNOWN=0, NOT_PRESENTING=1, PRESENTING=2 |
| `Completeness` | UNKNOWN=0, PARTIAL=1, COMPLETE=2 |

| Status | Interpretación |
|---|---|
| OK | Se cumplió el contrato concreto de la operación; un despacho de UI no confirma cierre ni interacción |
| FAILED | Fallo conocido o validación rechazada |
| CANCELLED | Espera local cancelada o sesión invalidada |
| UNSUPPORTED | No está expuesta la operación/plataforma solicitada |
| UNKNOWN | No hay evidencia suficiente para afirmar éxito o fallo; no activar un reintento ciego |

`GEXResult.is_ok()` solo acepta OK. `GEXResult.fail(code, detail="")` crea FAILED, excepto códigos que empiezan con `UNSUPPORTED` (UNSUPPORTED) y `CANCELLED`/`SESSION_CHANGED` (CANCELLED). `GEXResult.uncertain(code, detail)` fuerza UNKNOWN. Por ello `USER_CANCELLED` mapeado mediante `fail()` tiene status FAILED en esta versión; usa también `error_code`.

Delivery describe evidencia de guardado: PROVIDER_ACCEPTED confirma aceptación por el proveedor, no sincronización entre dispositivos. PENDING_SYNC y SYNC_CONFIRMED existen en el modelo pero los adaptadores actuales no los emiten como resultado de guardado. No deduzcas ninguno de ellos a partir de OK.

## GEXResult

| Campo | Tipo y valor inicial | Lectura |
|---|---|---|
| `request_id` | int = 0 | Positivo para solicitudes encoladas, negativo para rechazos locales de fachada; 0 puede aparecer en inicialización/otros resultados sin cola |
| `operation` | String = "" | Nombre de operación encolada; puede estar vacío en errores locales |
| `provider` | Provider = NONE | Proveedor asociado cuando está disponible; no asumir que todo rechazo lo rellena |
| `status` | Status = OK | Estado según tabla anterior |
| `error_code` | String = "" | Código estable de diagnóstico, también posible con UNKNOWN |
| `message` | String = "" | Detalle para diagnóstico; no contrato para decisiones ni traducción de UI |
| `native_code` | String = "" | Código nativo si se pudo recuperar, principalmente errores Apple |
| `delivery` | Delivery = UNKNOWN | Evidencia de entrega de una mutación de partida |
| `player` | PlayerProfile = null | Sesión/perfil; OK con null es posible al refrescar sin sesión |
| `proof` | IdentityProof = null | Evidencia para backend, no identidad ya verificada |
| `friends` | Array[PlayerProfile] = [] | Página/lista de amigos autorizados |
| `achievement_definitions` | Array[AchievementInfo] = [] | Metadatos de logros |
| `achievements` | Array[AchievementState] = [] | Estados de progreso |
| `leaderboards` | Array[LeaderboardInfo] = [] | Metadatos de rankings |
| `entries` | Array[LeaderboardEntry] = [] | Página de ranking |
| `own_entry` | LeaderboardEntry = null | Entrada propia, cuando está disponible |
| `saves` | Array[SavedGameMetadata] = [] | Metadatos de partidas; no necesariamente solo la partida solicitada |
| `bytes` | PackedByteArray = [] | Contenido de carga; vacío puede ser una partida válida |
| `completeness` | Completeness = UNKNOWN | Grado conocido de completitud, según operación; no inferirlo de una lista corta |
| `centered_on_player` | bool = false | El resultado cercano incluye el centrado observado |
| `centered_known` | bool = false | Indica si es significativo interpretar `centered_on_player` |
| `total_count` | int = -1 | Total del ranking si se conoce; -1 no es cero |
| `verified_player_id` | String = "" | ID emitido por el backend tras verificación |
| `query` | GEXQuery = null | Filtros de la consulta de puntuaciones devuelta |

No todos los métodos pueblan todos los campos. Por ejemplo, la mutación nativa de un logro no tiene que devolver `achievements`; consulta después si necesitas representar el progreso. El detalle por operación está en [API](api.md).

## PlayerProfile e IdentityProof

| Modelo/campo | Tipo inicial | Semántica |
|---|---|---|
| PlayerProfile.`provider` | Provider = NONE | Espacio de identidad |
| PlayerProfile.`id` | String = "" | ID opaco del jugador; Apple usa gamePlayerID |
| PlayerProfile.`id_scope` | String = "" | Alcance declarado por el adaptador; consultar junto a provider |
| PlayerProfile.`display_name` | String = "" | Nombre visible, puede faltar |
| PlayerProfile.`avatar_uri` | String = "" | URI si está disponible; no descarga ni textura automática |
| IdentityProof.`provider` | Provider = NONE | Proveedor de evidencia |
| IdentityProof.`kind` | String = "" | GOOGLE_SERVER_AUTH_CODE, APPLE_GAME_CENTER_SIGNATURE o marcador de simulación |
| IdentityProof.`authorization_code` | String = "" | Código OAuth Google para intercambio en backend |
| IdentityProof.`public_key_url` | String = "" | Referencia Apple que el servidor debe validar |
| IdentityProof.`signature` | PackedByteArray = [] | Firma Apple |
| IdentityProof.`salt` | PackedByteArray = [] | Salt Apple |
| IdentityProof.`timestamp` | int = 0 | Timestamp nativo de firma; se transporta como cadena decimal en HTTP |
| IdentityProof.`signed_player_id` | String = "" | Apple usa teamPlayerID; distinto de PlayerProfile.id |
| IdentityProof.`bundle_id` | String = "" | Contexto Apple tomado de configuración, no prueba de autenticidad por sí mismo |

No mezcles los ID de perfil, firma y backend. Los campos específicos del otro proveedor quedan vacíos. No persistas ni registres las pruebas. [Verificación de identidad](identity.md).

## Logros

| Modelo/campo | Tipo inicial | Semántica |
|---|---|---|
| AchievementInfo.`key` | String = "" | Clave del catálogo si hay mapeo |
| AchievementInfo.`native_id` | String = "" | Identificador remoto |
| AchievementInfo.`title` | String = "" | Título devuelto por proveedor o catálogo simulado |
| AchievementInfo.`description` | String = "" | Descripción disponible |
| AchievementInfo.`incremental` | bool = false | Indicador de progresión por pasos cuando lo proporciona el adaptador |
| AchievementInfo.`total_steps` | int = 0 | Total de pasos si aplica; no usar 0 como divisor |
| AchievementState.`key` | String = "" | Clave local si existe |
| AchievementState.`native_id` | String = "" | Identificador remoto |
| AchievementState.`progress` | float = 0.0 | Fracción normalizada 0–1 |
| AchievementState.`unlocked` | bool = false | Estado de desbloqueo normalizado |

Una entrada remota desconocida conserva `native_id` aunque `key` esté vacío. El catálogo local no crea ni renombra logros remotos. [Ejemplos](services.md#logros).

## Rankings

| Modelo/campo | Tipo inicial | Semántica |
|---|---|---|
| LeaderboardInfo.`key` | String = "" | Clave local si hay mapeo |
| LeaderboardInfo.`native_id` | String = "" | ID remoto |
| LeaderboardInfo.`title` | String = "" | Título disponible |
| LeaderboardInfo.`unit` | String = "" | Apple/mock pueden copiar catálogo; Android no lo rellena |
| LeaderboardInfo.`higher_is_better` | bool = true | Orden informado por PGS o tomado del catálogo Apple/mock |
| LeaderboardEntry.`player` | PlayerProfile = null | Perfil de la entrada si está disponible |
| LeaderboardEntry.`score` | int = 0 | Puntuación de 64 bits, no float |
| LeaderboardEntry.`formatted_score` | String = "" | Representación del proveedor; puede faltar |
| LeaderboardEntry.`rank` | int = 0 | Puesto real del proveedor; no renumerar por posición de página |

Para mostrar puntuaciones usa `formatted_score` cuando exista y `str(score)` como fallback. No conviertas enteros grandes a float en tu UI/serialización. [Filtros y consultas](services.md#rankings).

## Partidas y conflictos

| Modelo/campo | Tipo inicial | Semántica |
|---|---|---|
| SavedGameMetadata.`slot` | String = "" | Nombre lógico sin prefijo |
| SavedGameMetadata.`native_id` | String = "" | snapshotId en Android; puede quedar vacío en Apple |
| SavedGameMetadata.`modified_unix` | float = 0.0 | Marca de modificación en segundos Unix si existe |
| SavedGameMetadata.`description` | String = "" | Descripción disponible en PGS |
| SavedGameMetadata.`device_name` | String = "" | Nombre de dispositivo si el proveedor lo expone |
| SavedGameMetadata.`pending_sync` | bool = false | Indicador remoto cuando es conocido |
| SavedGameMetadata.`pending_sync_known` | bool = false | false significa que no se puede interpretar el flag anterior |
| SaveConflict.`token` | String = "" | Token opaco para resolver dentro del ciclo de vida actual |
| SaveConflict.`slot` | String = "" | Slot en conflicto |
| SaveConflict.`provider` | Provider = NONE | Proveedor del conflicto |
| SaveConflict.`generation` | int = 0 | Generación de sesión que lo originó; no modificar |
| SaveConflict.`versions` | Array[SavedGameMetadata] = [] | Versiones descritas por metadatos, sin contenido ni handles nativos públicos |

`pending_sync_known=true` y `pending_sync=false` no certifican sincronización en todos los dispositivos. La API no permite descargar separadamente los bytes de cada versión conflictiva; la resolución recibe bytes que el juego ya ha seleccionado o construido. [Partidas y conflictos](cloud-save.md).

## Estado de UI, interrupciones y actividades

| Modelo/campo | Tipo inicial | Semántica |
|---|---|---|
| NativeUiState.`presentation` | Presentation = UNKNOWN | Presentación observada; desconocida en PGS |
| NativeUiState.`provider` | Provider = NONE | Origen |
| NativeUiState.`source` | String = "UNAVAILABLE" | PROVIDER_PROPERTY en Apple, SIMULATOR en mock, UNAVAILABLE sin observador |
| NativeUiState.`destination` | String = "" | Campo reservado; los adaptadores actuales no identifican la pantalla observada |
| NativeUiState.`observed_at_msec` | int = 0 | Tiempo monotónico local de observación; no timestamp Unix |
| NativeUiState.`entry_point_active` | bool = false | Activación solicitada/observada del acceso |
| NativeUiState.`entry_point_visible` | bool = false | Visibilidad informada por proveedor; distinta de presentación |
| InterruptionState.`focus_lost` | bool = false | Foco de aplicación perdido |
| InterruptionState.`suspended` | bool = false | Aplicación suspendida |
| InterruptionState.`native_presenting` | bool = false | Coordinador observó presentación conocida |
| InterruptionState.`pause_reasons` | PackedStringArray = [] | Tokens del juego más motivos habilitados de GameExtrakit |
| NativeActivity.`id` | String = "" | ID de actividad entrante |
| NativeActivity.`definition_id` | String = "" | ID de definición |
| NativeActivity.`generation` | int = 0 | Generación de la sesión que recibió la actividad |

`native_presenting=false` no convierte un proveedor no observable en “overlay cerrado”. Consulta también NativeUiState.presentation y capacidades. [UI, pausa y actividades](native-ui.md).

## Capabilities

| Campo | Tipo inicial | Uso |
|---|---|---|
| `provider` | Provider = NONE | Proveedor seleccionado |
| `available` | bool = false | Fachada inicializada y adaptador preparado |
| `authenticated` | bool = false | Sesión observada autenticada |
| `enabled_modules` | PackedStringArray = [] | Nombres de los cinco módulos habilitados |
| `max_score_results` | int = 25 | Límite de consultas |
| `friends_completeness` | Completeness = UNKNOWN | Capacidad general; permanece UNKNOWN actualmente. Leer el resultado concreto |
| `can_resolve_save_conflicts` | bool = false | Apple/mock con módulo activo; false Android |
| `can_confirm_save_completion` | bool = false | Confirmar callback de aceptación, no sincronización; Apple/mock con módulo activo |
| `can_open_platform_overlay` | bool = false | Apple/mock; false Android |
| `can_control_entry_point` | bool = false | Apple/mock |
| `can_observe_platform_overlay` | bool = false | Apple/mock |
| `has_overlay_visibility_signal` | bool = false | Permanece false: Apple se observa mediante propiedad, no señal nativa de visibilidad |
| `can_open_achievements` | bool = false | Disponible, autenticado y módulo de logros habilitado |
| `can_open_leaderboards` | bool = false | Disponible, autenticado y módulo de rankings habilitado |
| `available_native_destinations` | PackedStringArray = [] | Destinos por proveedor/versión, filtrados por módulos |
| `interruption_observation` | String = "GODOT_LIFECYCLE" | Android: ciclo de vida; Apple: PROVIDER_PROPERTY; mock: SIMULATOR |
| `limitations` | PackedStringArray = [] | Diagnósticos explicativos del adaptador |

Algunos flags de soporte pueden permanecer true sin autenticación, o después de cerrar una instancia. Para ofrecer una acción comprueba primero `available`, `authenticated`, el módulo y el flag/destino; el método aplica sus propias precondiciones. No modifiques arrays ni propiedades devueltos para intentar activar funciones. [Ejemplo de UI por capacidades](native-ui.md).

