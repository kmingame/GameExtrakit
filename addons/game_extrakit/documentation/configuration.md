# Configuración y editor

[Manual](README.md) · [Primeros pasos](getting-started.md) · [API](api.md) · [Diagnóstico](troubleshooting.md)

## Resource y flujo del dock

La configuración es un [GEXConfig](../configuration/game_services_config.gd). Contiene información pública que se exporta con el juego. No almacenes secretos OAuth, claves privadas ni tokens del backend.

| Control | Comportamiento |
|---|---|
| Nueva | Crea un Resource en memoria; no cambia la configuración activa hasta guardarlo |
| Abrir | Carga un `.tres`/`.res` de tipo GEXConfig y persiste su ruta como selección |
| Guardar | Escribe el Resource, selecciona la ruta, actualiza el filesystem y ejecuta diagnóstico |
| Configuración | Edita campos escalares; el tooltip de cada etiqueta muestra el nombre de propiedad |
| Catálogos | Añade/quita logros y rankings y edita claves, IDs y metadatos locales |
| Abrir en Inspector (opciones completas) | Permite editar subrecursos, por ejemplo `default_query` de un ranking |
| Actualizar diagnóstico | Revalida la configuración en memoria y dependencias/presets locales |

Los campos numéricos del dock admiten valores fuera de los límites orientativos del Inspector. El diagnóstico y la validación al inicializar determinan si el Resource es aceptable. Guardar no impide escribir una configuración inválida: corrige los errores antes de ejecutar/exportar.

El runtime duplica la configuración durante `initialize()`; modificar o volver a guardar el original no cambia la instancia activa. Guarda y reinicia el juego para aplicar cambios.

## General y módulos

Todas las propiedades siguientes pertenecen a `GEXConfig`. Los nombres son exactamente los utilizados en GDScript.

| Propiedad | Tipo | Predeterminado | Significado y validación |
|---|---|---|---|
| `schema_version` | int | `1` | Único esquema aceptado; no hay migración automática |
| `android_enabled` | bool | `false` | Habilita selección PGS en Android y validación de IDs Android |
| `apple_enabled` | bool | `false` | Habilita selección Game Center en iOS y validación Apple |
| `mock_enabled` | bool | `false` | Prioridad sobre cualquier proveedor real; necesario para escritorio |
| `allow_mock_in_release` | bool | `false` | Autoriza explícitamente simulación en release; no la activa por sí solo |
| `timeout_seconds` | float | `20.0` | Segundos por espera nativa y petición HTTP; positivo y finito. Inspector: 0.1–120, paso 0.1 |
| `identity_enabled` | bool | `true` | Sesión, perfil, prueba de identidad y acceso general a UI |
| `friends_enabled` | bool | `true` | Consulta de amigos |
| `achievements_enabled` | bool | `true` | Logros, sus consultas y destinos de UI |
| `leaderboards_enabled` | bool | `true` | Rankings, consultas y destinos de UI |
| `cloud_save_enabled` | bool | `true` | Partidas y conflictos |

No se permite desactivar identidad dejando alguno de los otros cuatro módulos activo. Un módulo desactivado devuelve `FEATURE_DISABLED` cuando la llamada llega a la comprobación de módulos; un argumento inválido puede rechazarse antes. Desactivar un módulo no borra datos remotos ni elimina entradas de catálogo. La validación de catálogos se sigue ejecutando.

El timeout no es un plazo global para toda la operación: la espera en cola y las distintas llamadas de una operación compuesta pueden aumentar su duración. Véase [Concurrencia](lifecycle.md).

## Android y Apple

| Propiedad | Tipo | Predeterminado | Uso |
|---|---|---|---|
| `android_server_client_id` | String | `""` | ID OAuth público de servidor requerido por `get_identity_proof()` en PGS; no es el Game ID ni un secreto |
| `apple_bundle_id` | String | `""` | Obligatorio si Apple está activo; debe coincidir con preset/app y se incluye en la prueba |
| `apple_icloud_container` | String | `""` | Obligatorio si Apple y Cloud Save están activos; declaración de configuración, no crea entitlements ni selecciona contenedor mediante una API del adapter |
| `apple_minimum_ios` | int | `17` | Validación mínima declarada >=17; Inspector 17–99. No modifica el deployment target y el runtime comprueba por sí mismo iOS >=17 |

**Game ID de Android:** se edita exclusivamente en el preset Android, opción `godot_play_game_services/game_id`. No existe un segundo campo equivalente en GEXConfig. El dock lee el preset para diagnóstico.

Configurar un mínimo Apple mayor que 17 no eleva por sí solo el umbral del adaptador; aplícalo también a tu exportación/Xcode. La disponibilidad de destinos usa la versión real de iOS. Las consolas, permisos, firma y contenedores se preparan en [Plataformas](platforms.md).

## Partidas e identidad

| Propiedad | Tipo | Predeterminado | Uso |
|---|---|---|---|
| `slot_prefix` | String | `""` | Prefijo antepuesto al nombre remoto. Vacío o 1–100 caracteres ASCII permitidos |
| `max_save_bytes` | int | `1048576` | Presupuesto de aplicación: 1–3145728 bytes. Predeterminado 1 MiB; no garantiza cuota ni sincronización |
| `identity_verifier_url` | String | `""` | Endpoint opcional. Debe comenzar por `https://`; crea el verificador HTTP si no se inyectó otro |

Tanto el slot lógico como `slot_prefix + slot` deben medir 1–100 caracteres y contener solo `A-Z a-z 0-9 - . _ ~`. No son rutas de archivos. Cambiar el prefijo cambia el espacio de nombres visible; no migra las partidas existentes. Los detalles están en [Partidas](cloud-save.md) e [Identidad](identity.md).

## Interfaces nativas e interrupciones

| Propiedad | Tipo | Predeterminado | Uso |
|---|---|---|---|
| `apple_entry_point_active` | bool | `false` | Estado solicitado del access point al autenticar/refrescar/consultar perfil Apple |
| `apple_entry_point_location` | int | `0` | 0 arriba leading, 1 arriba trailing, 2 abajo leading, 3 abajo trailing; solo 0–3 |
| `apple_show_highlights` | bool | `true` | Solicita highlights al configurar el access point |
| `pause_on_focus_loss` | bool | `false` | Añade motivo de pausa si se pierde el foco de aplicación |
| `pause_on_suspend` | bool | `true` | Añade motivo ante suspensión de la aplicación |
| `pause_on_native_ui` | bool | `true` | Añade motivo si se observa presentación nativa |
| `manage_scene_tree_pause` | bool | `false` | Si está activo, el coordinador administra `SceneTree.paused`; de lo contrario solo publica estado/motivos |

Leading/trailing son los extremos lógicos del sistema, no una garantía de izquierda/derecha en cualquier idioma. Las opciones `pause_on_*` no pausan el árbol por sí solas cuando `manage_scene_tree_pause=false`.

Las llamadas de visibilidad cambian `active` en runtime; una posterior lectura/refresco de perfil Apple puede restablecer `apple_entry_point_active`. La posición/highlights se aplican al preparar el adaptador. Consulta [UI y pausa](native-ui.md) para integrar un gestor propio o usar tokens.

## Simulador

| Propiedad | Tipo | Predeterminado | Uso |
|---|---|---|---|
| `mock_latency_seconds` | float | `0.05` | Retraso artificial por operación; Inspector 0–10, paso 0.01. Usa un valor finito no negativo |
| `mock_player_id` | String | `"simulated-player"` | ID inicial del jugador de prueba; usa uno no vacío |

Estos dos campos no tienen todas las restricciones del Inspector replicadas en `validate()`. No uses valores inválidos para provocar fallos; usa los controles de [Simulación](simulator.md).

## Catálogo de logros

`achievements: Array[GEXAchievementDefinition] = []`. Añade cada entrada desde **+ Logro**.

| Campo de GEXAchievementDefinition | Tipo | Predeterminado | Significado |
|---|---|---|---|
| `key` | String | `""` | Clave local obligatoria y única dentro del catálogo, usada por el juego |
| `android_id` | String | `""` | ID PGS; obligatorio y único cuando Android está activo |
| `apple_id` | String | `""` | ID Game Center; obligatorio y único cuando Apple está activo |
| `title` | String | `""` | Título local, usado por el simulador; no publica/localiza el título remoto |
| `description` | String | `""` | Descripción local; admite múltiples líneas en Inspector |
| `incremental` | bool | `false` | Debe coincidir con el tipo PGS del logro |
| `android_total_steps` | int | `1` | Pasos del logro incremental, >=1; Inspector hasta 2147483647 |

PGS contrasta tipo/pasos contra los metadatos nativos antes de enviar progreso. Un logro normal acepta 0 o 1; el progreso parcial es `UNSUPPORTED`. Apple usa el porcentaje normalizado; `android_total_steps` no convierte un logro Apple en un contador de pasos.

Ejemplos de claves: `primera_victoria` normal y `coleccionista` incremental con 100 pasos. Los IDs de los ejemplos son los tuyos, creados en las consolas. `native_id(provider)` devuelve el ID Android para ANDROID_PGS y el ID Apple en los demás casos; es un helper de adaptadores, no un generador de IDs para MOCK.

## Catálogo de rankings

`leaderboards: Array[GEXLeaderboardDefinition] = []`. Añade cada entrada desde **+ Leaderboard**.

| Campo de GEXLeaderboardDefinition | Tipo | Predeterminado | Significado |
|---|---|---|---|
| `key` | String | `""` | Clave local obligatoria y única |
| `android_id` | String | `""` | ID PGS obligatorio/único si Android está activo |
| `apple_id` | String | `""` | ID Game Center obligatorio/único si Apple está activo |
| `title` | String | `""` | Título local para simulación |
| `unit` | String | `"points"` | Metadato local; no configura el formato del proveedor |
| `higher_is_better` | bool | `true` | Sentido del ranking local/simulador; debe reflejar la consola |
| `default_query` | GEXQuery | `null` | Consulta por defecto; crea el subrecurso desde el Inspector |

`native_id(provider)` sigue la misma regla que en logros. Las configuraciones locales no cambian el orden, la unidad o los periodos del leaderboard remoto.

## Consultas GEXQuery

[GEXQuery](../configuration/query.gd) es un Resource reutilizable.

| Campo | Tipo | Predeterminado | Valores |
|---|---|---|---|
| `scope` | GEXTypes.Scope | `GLOBAL` | GLOBAL=0, FRIENDS=1 |
| `period` | GEXTypes.Period | `ALL_TIME` | DAILY=0, WEEKLY=1, ALL_TIME=2 |
| `limit` | int | `10` | 1–25 |
| `force_refresh` | bool | `false` | Preferencia nativa Android; sin equivalente Apple |

`is_valid()` comprueba enums y límite. Si omites la consulta, se usa `default_query` del catálogo o una nueva consulta con estos valores. Se duplica antes de encolarla. `submit_score()` también valida la consulta por defecto del ranking aunque el envío no acepte filtros. [Ejemplos de rankings](services.md#rankings).

## Crear recursos desde código

La misma configuración del dock puede construirse con GDScript. Este ejemplo devuelve un Resource para simulación con las claves usadas en el manual:

```gdscript
func crear_configuracion_de_prueba() -> GEXConfig:
    var config := GEXConfig.new()
    config.mock_enabled = true

    var normal := GEXAchievementDefinition.new()
    normal.key = "primera_victoria"
    normal.title = "Primera victoria"
    config.achievements.append(normal)

    var incremental := GEXAchievementDefinition.new()
    incremental.key = "coleccionista"
    incremental.incremental = true
    incremental.android_total_steps = 100
    config.achievements.append(incremental)

    var board := GEXLeaderboardDefinition.new()
    board.key = "mejor_puntuacion"
    board.title = "Mejor puntuación"
    board.default_query = GEXQuery.new()
    board.default_query.limit = 10
    config.leaderboards.append(board)
    return config
```

Pásalo a una [instancia manual](lifecycle.md) o guárdalo mediante ResourceSaver y ábrelo en el dock. La función no selecciona una configuración del proyecto ni cambia consolas. Antes de activar Android/Apple, completa sus IDs y demás requisitos.

## Validación y ajustes persistidos

`GEXConfig.validate() -> PackedStringArray` devuelve todos los problemas detectados; vacío significa válido localmente. Comprueba esquema, timeout, presupuesto, dependencias de módulos, requisitos Apple, HTTPS, prefijo, ubicación, entradas nulas, claves/IDs duplicados, pasos y consultas.

Los IDs se comprueban por catálogo y plataforma habilitada. Tener mock activo no omite esas comprobaciones si Android/Apple también están habilitados. No se comprueban credenciales, existencia remota de IDs ni entitlements.

Helpers públicos: `module_enabled(module)` para `identity`, `friends`, `achievements`, `leaderboards`, `cloud_save`; `achievement(key)` y `leaderboard(key)` devuelven la definición o `null`; `GEXConfig.valid_slot(slot)` comprueba la sintaxis de un nombre.

| Ajuste del proyecto | Gestión |
|---|---|
| `game_extrakit/config_path` | Ruta seleccionada; puede ser `.tres` o `.res`, debe existir al ejecutar/exportar |
| `autoload/GameServices` | Entrada del autoload; respetar su nombre para los ejemplos |
| `game_extrakit/owns_autoload` | Marca interna del editor para retirar solo su propio autoload; no editar manualmente |

Para varias configuraciones, guarda Resources separados y abre el que corresponda antes de exportar. La selección es global del proyecto, no una asociación automática por preset. Revisa [Exportación](platforms.md#empaquetado) y [Diagnóstico](troubleshooting.md) antes de distribuir.
