# Jugadores, amigos, logros y rankings

[Manual](README.md) · [API](api.md) · [Configuración](configuration.md) · [Resultados](results.md)

Los ejemplos usan el autoload configurado y muestran decisiones de integración. Maneja los errores con la [guía de diagnóstico](troubleshooting.md); un resultado UNKNOWN no dispara reintentos automáticos.

<a id="autenticacion-y-perfil"></a>
## Autenticación y perfil

Inicializar no autentica. `get_auth_state()` consulta el estado local; `refresh_auth_state()` pregunta al proveedor. Un refresco OK con `player=null` significa que no se observó sesión. `authenticate()` puede abrir el flujo nativo. No hay un método común de logout.

En Android el refresco utiliza `isAuthenticated` del binding y no promete la misma ausencia de popups que Apple. Las llamadas simultáneas de autenticación se agrupan; si un authenticate coincide con un refresco que termina sin sesión, se intenta después la autenticación interactiva.

```gdscript
func comprobar_sesion() -> bool:
    var result := await GameServices.refresh_auth_state()
    return result.is_ok() and result.player != null

# Conectar a un botón de inicio de sesión.
func iniciar_sesion() -> void:
    var result := await GameServices.authenticate()
    if not result.is_ok() or result.player == null:
        push_warning("No se pudo iniciar sesión: " + result.error_code)
        return
    # Actualiza aquí tu interfaz. No uses el nombre visible como clave de guardado.
    print("Sesión disponible.")

func leer_perfil() -> GEXTypes.PlayerProfile:
    var result := await GameServices.get_player()
    if not result.is_ok():
        return null
    return result.player
```

Usa señales de [API](api.md#señales-públicas) para actualizar botones y estado. Cuando `player_changed` recibe null, deja de mostrar datos del jugador anterior. Un ID Apple de perfil (`gamePlayerID`) no equivale al de firma (`teamPlayerID`) ni al ID interno del backend. [Identidad](identity.md) explica las diferencias.

<a id="amigos"></a>
## Amigos

`list_friends()` ofrece amigos autorizados para ese servicio y juego, no una libreta de contactos. PGS devuelve una página sin cursor ni garantía de totalidad. El límite común aceptado es 1–200, sin prometer que el binding entregue ese número.

En Apple se consulta el permiso antes de cargar: NOT_DETERMINED sin autorización para preguntar produce PERMISSION_REQUIRED; estados denegado/restringido producen PERMISSION_DENIED. Configura el texto de uso antes de probar en [iOS](platforms.md#apple--ios).

```gdscript
func consultar_amigos(desde_boton_de_permiso: bool = false) -> void:
    var result := await GameServices.list_friends(25, desde_boton_de_permiso, false)
    if result.error_code == "PERMISSION_REQUIRED":
        print("Ofrece al usuario un botón para autorizar la lista.")
        return
    if not result.is_ok():
        push_warning("Amigos: " + result.error_code)
        return

    print("Entradas recibidas: ", result.friends.size())
    match result.completeness:
        GEXTypes.Completeness.COMPLETE:
            print("Lista autorizada completa.")
        GEXTypes.Completeness.PARTIAL:
            print("Se muestra solo parte de la lista.")
        _:
            print("No se conoce si hay más entradas.")
```

No vuelvas a solicitar permiso en un bucle. En PGS vacío/null puede significar error y se devuelve UNKNOWN/AMBIGUOUS_NATIVE_RESULT. Apple puede devolver OK con una lista vacía completa. `force_refresh` solo tiene efecto cuando el proveedor lo ofrece.

<a id="logros"></a>
## Logros

El catálogo une una clave local a IDs remotos. La mutación usa esa clave, mientras las listas devuelven metadatos nativos y su mapeo cuando existe. Configura [los catálogos](configuration.md#catálogo-de-logros) antes de ejecutar estos ejemplos.

```gdscript
func progreso_coleccion(encontrados: int, objetivo: int) -> void:
    if objetivo <= 0:
        return
    var progress := clampf(float(encontrados) / float(objetivo), 0.0, 1.0)
    var result := await GameServices.set_achievement_progress("coleccionista", progress)
    if not result.is_ok():
        push_warning("Progreso: " + result.error_code)

func consultar_logros() -> void:
    var definitions := await GameServices.list_achievement_definitions()
    if not definitions.is_ok():
        push_warning("Definiciones: " + definitions.error_code)
        return

    var states := await GameServices.list_player_achievements()
    if not states.is_ok():
        push_warning("Estados: " + states.error_code)
        return
    for state in states.achievements:
        print("Logro configurado: ", not state.key.is_empty(),
            "; progreso: ", state.progress, "; desbloqueado: ", state.unlocked)
```

| Operación | Android PGS | Apple Game Center |
|---|---|---|
| Progreso normal 0 | No envía mutación; no reinicia un logro | Reporta porcentaje 0; no es una API de reset |
| Progreso normal entre 0 y 1 | UNSUPPORTED_OPERATION | Porcentaje absoluto |
| Incremental | `floor(progress * android_total_steps)`, pasos absolutos; cero no se envía | Porcentaje absoluto; pasos Android no se aplican |
| Desbloquear | Equivale a progreso 1, según tipo | Reporta 100% y solicita banner |
| Respuesta incremental false | UNKNOWN: no distingue resultado ambiguo | Usa callback de reporte |
| Leer estados | Metadatos y estado de PGS, validando tipo/pasos configurados | Une definiciones con progresos para incluir logros a cero |

La implementación no convierte progreso absoluto en incrementos relativos. No uses `progress=0` para intentar restablecer datos. Las mutaciones reales no prometen devolver el nuevo estado; puedes consultarlo después, respetando las condiciones de caché. Los títulos/descripciones locales del Resource no se publican en la consola.

Para abrir la pantalla del proveedor usa `show_achievements()`; el resultado se interpreta según [UI nativa](native-ui.md).

<a id="rankings"></a>
## Rankings

Las puntuaciones son enteros de 64 bits. El orden y formato del ranking se configuran en el proveedor. `higher_is_better` y `unit` no reconfiguran el servicio; orientan metadatos locales y simulación. Enviar una puntuación aceptada no significa haber superado un récord.

```gdscript
func enviar_y_consultar_puntuacion(puntos: int) -> void:
    var submitted := await GameServices.submit_score("mejor_puntuacion", puntos)
    if not submitted.is_ok():
        push_warning("Envío: " + submitted.error_code)
        return

    var query := GEXQuery.new()
    query.scope = GEXTypes.Scope.GLOBAL
    query.period = GEXTypes.Period.ALL_TIME
    query.limit = 10

    var own := await GameServices.get_player_score("mejor_puntuacion", query)
    if own.is_ok() and own.own_entry != null:
        print("Puesto propio: ", own.own_entry.rank)
    elif not own.is_ok():
        push_warning("Puntuación propia: " + own.error_code)

    var top := await GameServices.get_top_scores("mejor_puntuacion", query)
    if not top.is_ok():
        push_warning("Top: " + top.error_code)
        return
    for entry in top.entries:
        var score_text := entry.formatted_score
        if score_text.is_empty():
            score_text = str(entry.score)
        print("Puesto %d: %s" % [entry.rank, score_text])
```

No uses `index + 1` como puesto: las páginas pueden empezar en otro rango y existen empates. El parser PGS conserva enteros grandes sin pasar sus tokens por float; mantén esa precisión en tu código.

### Consultas y periodos

| Opción | Contrato |
|---|---|
| GLOBAL | Ranking global del proveedor |
| FRIENDS | Colección/ámbito de amigos autorizado por el proveedor |
| DAILY | Ventana diaria nativa |
| WEEKLY | Ventana semanal nativa |
| ALL_TIME | Histórico nativo |
| limit | 1–25; se pueden recibir menos entradas |
| force_refresh | Solicitud de refresco PGS; sin equivalente Apple |

Las ventanas temporales no son una temporada compartida entre plataformas. El addon no decide zona horaria, calendario ni reinicios; los periodos del servicio pueden diferir. La consulta de amigos no incorpora jugadores del otro proveedor.

```gdscript
func cercanos_amigos_semana() -> void:
    var query := GEXQuery.new()
    query.scope = GEXTypes.Scope.FRIENDS
    query.period = GEXTypes.Period.WEEKLY
    query.limit = 15
    query.force_refresh = true

    var result := await GameServices.get_scores_around_player("mejor_puntuacion", query)
    if not result.is_ok():
        push_warning("Cercanos: " + result.error_code)
        return
    if not result.centered_known:
        print("Centrado desconocido.")
    elif not result.centered_on_player:
        print("La página no está centrada en el jugador.")
    if result.total_count >= 0:
        print("Total informado: ", result.total_count)
    print("Entradas recibidas: ", result.entries.size())
```

Android usa el resultado cercano del proveedor y determina si encontró la entrada propia. Apple primero consulta rank y después el rango cercano: no es una instantánea atómica y el ranking puede cambiar entre lecturas. Sin score propio Apple usa la página superior; comprueba los indicadores.

`get_player_score()` con OK y `own_entry=null` puede representar ausencia válida en Apple/mock. En PGS una respuesta null es UNKNOWN. No conviertas ambos casos en cero puntos.

`list_leaderboards()` enumera metadatos remotos, no solo tus definiciones locales; una entrada no mapeada tiene `key=""`. Para operar por clave añade el mapeo al Resource. Para abrir un ranking usa `show_leaderboard(key, query)`; solo scope y periodo se trasladan a la pantalla nativa.

## Datos personalizados y presentación

Puedes construir tu propia UI con modelos tipados o abrir vistas nativas. El addon no crea HUD, avatares descargados, tablas gráficas ni navegación del juego. Todos los modelos y campos opcionales están en [Resultados](results.md); las pantallas y capacidades, en [UI nativa](native-ui.md).

