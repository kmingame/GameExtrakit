# Interfaces nativas, pausa y actividades

[Manual](README.md) · [API](api.md#interfaces-nativas) · [Configuración](configuration.md) · [Modelos](results.md)

## Abrir según capacidades

La lista `available_native_destinations` informa soporte por proveedor, versión y módulos. No garantiza sesión activa. Comprueba `available`, `authenticated` y el destino antes de ofrecer una acción.

```gdscript
func abrir_logros() -> void:
    var caps := GameServices.get_native_ui_capabilities()
    if not caps.available or not caps.authenticated or not caps.can_open_achievements:
        return
    var result := await GameServices.show_achievements()
    if result.status == GEXTypes.Status.UNKNOWN:
        print("Solicitud enviada sin confirmación suficiente de presentación.")
    elif not result.is_ok():
        push_warning("UI: " + result.error_code)
```

Un resultado OK significa que se solicitó la interfaz, no que el usuario terminó de verla. No reanudes el gameplay al recibir el retorno de `show_*`. Apple separa el callback de presentación y la observación de estado; Android no dispone de observador de su UI.

## Matriz de destinos

| Destino | Identificador de show_native_destination | Android | Apple mínimo | Mock |
|---|---|---|---|---|
| `overlay` | Ninguno | No | iOS 17 | Sí |
| `achievements` | Ninguno | Sí | iOS 17 | Sí |
| `leaderboards` | Ninguno | Sí | iOS 17 | Sí |
| `leaderboard` | Clave local de ranking | Sí | iOS 17, fallback sin callback; access point desde 18 | Método directo simulado; no figura en la lista de destinos |
| `profile` | Ninguno | No | iOS 17 | No |
| `friends` | Ninguno | No | iOS 17 | No |
| `achievement` | Clave local de logro | No | iOS 18 | No |
| `leaderboard_set` | ID nativo del conjunto | No | iOS 18 | No |
| `challenges` | Ninguno | No | iOS 26 | No |
| `challenge` | ID nativo de definición | No | iOS 26 | No |
| `friending` | Ninguno | No | iOS 26 | No |
| `play_together` | Ninguno | No | iOS 26 | No |
| `activity` | ID nativo de definición | No | iOS 26 | No |

`achievements`/`achievement` se filtran por el módulo de logros; `leaderboards`/`leaderboard`/`leaderboard_set` por rankings. Los destinos generales, incluido `friends` de UI nativa, usan el módulo identity; desactivar la consulta de amigos no elimina ese destino del overlay del sistema.

Los destinos avanzados abren pantallas de objetos configurados fuera del addon. No crean retos, actividades, conjuntos, partidas multijugador ni matchmaking.

```gdscript
func abrir_logro_individual() -> GEXResult:
    var caps := GameServices.get_capabilities()
    if not caps.available or not caps.authenticated:
        return GEXResult.fail("NOT_AUTHENTICATED")
    if "achievement" not in caps.available_native_destinations:
        return GEXResult.fail("UNSUPPORTED_OPERATION")
    return await GameServices.show_native_destination("achievement", "primera_victoria")

func abrir_ranking_semanal() -> GEXResult:
    var query := GEXQuery.new()
    query.scope = GEXTypes.Scope.GLOBAL
    query.period = GEXTypes.Period.WEEKLY
    return await GameServices.show_leaderboard("mejor_puntuacion", query)
```

En Android las pantallas PGS producen UNKNOWN/UI_PRESENTATION_UNOBSERVABLE. En iOS 17 el ranking específico utiliza un controlador sin callback expuesto y devuelve UNKNOWN/UI_DISPATCHED; no interpretes ese despacho como cierre observado. No existe método común para cerrar forzosamente la interfaz.

## Access point Apple

`set_platform_entry_point_visible(true)` activa el acceso; `false` lo desactiva. El nombre del método expresa intención, mientras el proveedor decide la visibilidad efectiva. Ocultarlo no cierra una pantalla abierta.

`set_platform_entry_point_location(location)` acepta 0 arriba leading, 1 arriba trailing, 2 abajo leading, 3 abajo trailing. Android responde UNSUPPORTED. Mock acepta el ajuste sin modelar una posición gráfica.

```gdscript
func activar_acceso_inferior() -> void:
    var caps := GameServices.get_capabilities()
    if not caps.available or not caps.authenticated or not caps.can_control_entry_point:
        return
    var placed := await GameServices.set_platform_entry_point_location(3)
    if not placed.is_ok():
        push_warning(placed.error_code)
        return
    var shown := await GameServices.set_platform_entry_point_visible(true)
    if not shown.is_ok():
        push_warning(shown.error_code)
```

La configuración inicial también contiene `apple_show_highlights`. Un posterior authenticate/refresh/get_player Apple vuelve a aplicar `apple_entry_point_active`; usa ese valor para la política persistente de la sesión.

## Observar presentación

Apple consulta `is_presenting_game_center` cada **250 ms**. El observador sigue activo con el juego pausado y con el botón oculto. Mock usa el mismo observador; PGS permanece UNKNOWN.

No hay una señal nativa de visibilidad del overlay: `has_overlay_visibility_signal=false`. La señal común `native_ui_state_changed` se construye al detectar cambios de presentación, active o visible. Leer el estado directamente no emite la señal ni actualiza inmediatamente el coordinador de pausa; este se actualiza en el siguiente sondeo.

`active`, `visible` y `presentation` son distintos. `destination` no se rellena actualmente: conocer que Game Center está presentado no identifica su pantalla específica.

```gdscript
func observar_interfaz() -> void:
    GameServices.native_ui_state_changed.connect(_on_native_ui)

func _on_native_ui(state: GEXTypes.NativeUiState) -> void:
    match state.presentation:
        GEXTypes.Presentation.PRESENTING:
            print("Presentación observada.")
        GEXTypes.Presentation.NOT_PRESENTING:
            print("Sin presentación según el proveedor.")
        _:
            print("Presentación desconocida.")
```

<a id="pausa-y-motivos"></a>
## Pausa y motivos

Se registran por separado foco de aplicación, suspensión, presentación nativa y tokens del juego. Los motivos automáticos son:

| Motivo | Activación predeterminada |
|---|---|
| `game_extrakit/focus` | Desactivada: pause_on_focus_loss=false |
| `game_extrakit/suspension` | Activada: pause_on_suspend=true |
| `game_extrakit/native_ui` | Activada: pause_on_native_ui=true |

Los estados booleanos se observan aunque el motivo correspondiente esté desactivado. Usa nombres de tokens del juego distintos a los anteriores. Repetir un token es idempotente; no cuenta referencias: dos sistemas que comparten nombre podrían liberarse mutuamente.

### Modo de eventos, predeterminado

Con `manage_scene_tree_pause=false`, el addon emite `interruption_changed` y no cambia SceneTree. Tu gestor combina `state.pause_reasons` con sus otros motivos.

```gdscript
var motivos_servicios: PackedStringArray = []

func conectar_interrupciones() -> void:
    GameServices.interruption_changed.connect(_on_interruption)
    _on_interruption(GameServices.get_interruption_state())

func _on_interruption(state: GEXTypes.InterruptionState) -> void:
    motivos_servicios = state.pause_reasons.duplicate()
    # Entrega esta lista a tu gestor central de pausa.
    # El gestor debe combinarla con menú, cinemáticas u otros motivos propios.
```

No asignes simplemente `get_tree().paused = state.pause_reasons.is_empty() == false` desde varios sistemas: podrías eliminar la pausa de otro.

### Modo con propiedad de SceneTree

Activa `manage_scene_tree_pause=true` y usa tokens para todas las nuevas pausas del juego:

```gdscript
func abrir_menu() -> void:
    GameServices.set_pause_token("juego/menu", true)

func cerrar_menu() -> void:
    GameServices.set_pause_token("juego/menu", false)
```

La UI del menú debe poder procesar estando pausada. El coordinador memoriza la pausa previa del árbol y solo libera su propia intervención cuando no quedan motivos. Recuperar foco no libera suspensión, presentación ni tokens manuales. No hay timeout que fuerce reanudar.

Godot no permite distinguir otra asignación `paused=true` realizada cuando ya está en true. Para preservar pausas nuevas usa tokens o el modo de eventos con un único gestor. Al cerrar el servicio se preserva una pausa previa o tokens manuales todavía activos; el juego debe gestionar su salida.

Pausar SceneTree no es una política automática de audio, red, guardado, vibración o consumo. Integra esos sistemas en tu gestor si procede.

## Sidekick y eventos de aplicación

PGS no expone control/visibilidad de Sidekick mediante el binding fijado. El addon no añade SDK ni identifica cualquier pérdida de foco como Sidekick. Usa las notificaciones APPLICATION_FOCUS_OUT/IN y APPLICATION_PAUSED/RESUMED como interrupciones genéricas.

Si Sidekick no produce esos eventos, no se puede garantizar pausa específica. Su estado sigue UNKNOWN incluso tras recuperar foco. [Protocolo manual de Sidekick](validation.md#investigación-de-sidekick).

## Actividades entrantes Apple

En iOS 26, cuando el binding ofrece la señal, se emite `native_activity_received` con ID, definición y generación y se encola el mismo dato. La cola conserva hasta 32; al excederlos descarta el más antiguo. Cambio de cuenta y cierre la vacían.

Elige una política de consumo para evitar procesar dos veces la señal y la cola. Este ejemplo usa la señal solo para solicitar el drenaje:

```gdscript
func conectar_actividades() -> void:
    GameServices.native_activity_received.connect(_on_activity_available)
    consumir_actividades()

func _on_activity_available(_activity: GEXTypes.NativeActivity) -> void:
    consumir_actividades()

func consumir_actividades() -> void:
    for activity in GameServices.take_pending_activities():
        # Valida definition_id y decide cuándo tu juego puede atenderla.
        print("Actividad recibida; generación: ", activity.generation)
```

No se cambia de escena automáticamente. La aceptación nativa ya ocurrió en el binding; no hay rechazo retroactivo ni cola persistente entre procesos. Se entregan solo datos comunes, no un objeto GameKit para administrar actividades.

