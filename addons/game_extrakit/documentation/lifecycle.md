# Sesiones, concurrencia y ciclo de vida

[Manual](README.md) · [API](api.md) · [Resultados](results.md) · [Interrupciones](native-ui.md)

## Una instancia por ciclo de vida

El autoload carga el Resource seleccionado al entrar en el árbol. Si la ruta falta, no existe o no es GEXConfig, no se prepara el servicio; comprueba `get_capabilities().available` y el diagnóstico del editor.

Para una instancia administrada por tu juego, desactiva autoinicialización antes de añadirla:

```gdscript
extends Node

var services: GEXGameServices

func _ready() -> void:
    var config := GEXConfig.new()
    config.mock_enabled = true

    services = GEXGameServices.new()
    services.auto_initialize = false
    add_child(services)
    var initialized := services.initialize(config)
    if not initialized.is_ok():
        push_warning("Inicialización: " + initialized.error_code)
        return

    var authenticated := await services.authenticate()
    if not authenticated.is_ok():
        push_warning("Sesión: " + authenticated.error_code)

func cerrar_servicio() -> void:
    if is_instance_valid(services):
        services.shutdown()
        services.queue_free()
        services = null
```

Este ejemplo usa `services` en lugar del autoload. No inicialices simultáneamente ambos contra el singleton Android: solo admite un propietario. El [laboratorio](simulator.md) ilustra cómo reutilizar el autoload o preparar una instancia propia.

La selección del proveedor ocurre una vez, con prioridad mock → plataforma real. Inicializar otra vez una instancia ya preparada devuelve OK sin reemplazar configuración. Tras un ciclo inicializado y cerrado, `initialize()` devuelve INVALID_CONFIGURATION; crea una instancia nueva. Los errores previos a crear la cola no equivalen a un ciclo inicializado completo.

## Cola FIFO

Una cola global serializa las operaciones: consultas, mutaciones y operaciones compuestas. Evita que dos peticiones usen a la vez una señal nativa sin ID suficiente para correlacionarlas. La cola también ordena consultas del mismo leaderboard con periodos distintos y escrituras del mismo slot.

Cada solicitud encolada obtiene un ID positivo incremental. Los rechazos locales de fachada usan números negativos decrecientes. La autenticación simultánea puede compartir resultado e ID. No interpretes un hueco en IDs como pérdida de respuestas.

No uses simultáneamente los clientes GDScript del wrapper y la fachada para emitir llamadas; un tercero podría consumir/provocar una señal fuera de la correlación de GameExtrakit.

La cola no es persistente: no sobrevive al cierre del proceso, no reintenta operaciones offline y no ofrece transacciones entre métodos. Un `await save_game()` seguido de `await submit_score()` son dos operaciones independientes.

## Timeouts

`timeout_seconds` se aplica a **cada espera de respuesta nativa**. Una operación puede necesitar más de una espera: por ejemplo cargar jugador antes/después o consultar leaderboard y después sus entradas. El tiempo esperando turno en la cola no usa un límite total separado.

Los timers ignoran la escala de tiempo y procesan durante pausa de SceneTree. Esto no significa que una aplicación suspendida por el sistema siga ejecutando código: al volver se reconcilia el estado.

Al agotar el tiempo, una lectura puede fallar con TIMEOUT. Una mutación en vuelo puede devolver UNKNOWN/TIMEOUT porque el SDK aún podría terminar. El resultado no cancela por sí mismo el trabajo remoto.

### Canales Android

Tras timeout/cancelación, el canal sigue ocupado hasta recibir y drenar la respuesta original. Nuevas llamadas que lo necesitan devuelven REQUEST_CHANNEL_BUSY; no se atribuye una respuesta tardía a la petición siguiente.

Si se destruye el adaptador con canales todavía pendientes, se marcan como retirados para el resto del proceso. Crear otro Node no hace segura la correlación: reiniciar la aplicación es la recuperación que establece una nueva época nativa. No borres las marcas de Engine manualmente.

Apple mantiene una espera de autenticación pendiente hasta su señal y evita presentaciones superpuestas. También puede devolver REQUEST_CHANNEL_BUSY en esos casos. [Diagnóstico](troubleshooting.md).

## Cambio de cuenta

La fachada mantiene una generación de sesión. Cambiar el ID observado invalida solicitudes y conflictos, vacía actividades pendientes y publica estado/perfil. Los adaptadores comprueban identidad alrededor de las operaciones; una observación de nueva sesión puede dejar el estado UNKNOWN hasta que se refresque.

Al reanudar la aplicación se observa UI nativa y se llama a `refresh_auth_state()`. El juego debe retirar de pantalla datos del usuario anterior y volver a consultarlos tras autenticar.

Esto limita la mezcla observable de datos entre cuentas, pero no permite deshacer una mutación que el SDK ya envió justo antes del cambio. El resultado puede ser SESSION_CHANGED/CANCELLED o UNKNOWN cuando hay incertidumbre.

Para el backend, se verifica la generación después de obtener prueba y después de esperar al verificador; una respuesta de una sesión vieja se descarta. No conserves perfiles, conflictos o actividades como autoridades permanentes.

## Cancelación explícita

`cancel_pending_requests()` cancela las solicitudes en cola y la espera activa, incrementa generación e invalida tokens de conflicto aunque el jugador no cambie.

| Solicitud | Resultado de cancelación local |
|---|---|
| Aún en cola | CANCELLED; no llegó al adaptador |
| Lectura activa | CANCELLED, salvo un resultado ya finalizado |
| Guardar, borrar, score, progreso o resolver activo | UNKNOWN: el trabajo nativo puede continuar |

No hay cancelación individual por ID. El método no hace logout ni libera inmediatamente los canales nativos ambiguos. La cancelación del verificador HTTP no aborta la petición de red; el control de generación permite descartar su resultado.

Si una escena deja de interesarse por datos, decide si realmente debes cancelar **toda** la cola compartida. No llames a cancelación global simplemente para ocultar un panel que comparte el servicio con otras escenas.

## Cierre

`shutdown()` marca el servicio como no disponible, detiene el observador, cancela la cola, desconecta listeners y desactiva el access point Apple. Limpia actividades/perfil y lleva auth a UNKNOWN. No realiza logout nativo ni borra datos.

Libera solo la pausa que posee; conserva la pausa previa y tokens manuales activos. Si se cierra con un menú todavía pausando, el juego sigue siendo responsable de gestionar esa pausa. No elimines de golpe tu gestor sin transferir su estado.

El Node no se libera automáticamente con `shutdown()`; una instancia manual pertenece a quien la creó. Su `_exit_tree()` también ejecuta cierre. Un verificador inyectado pertenece al juego; el HTTP creado por la fachada es hijo del servicio.

Los procesos siempre activos de GameExtrakit permiten observar cierre de UI durante pausa. Configura igualmente tus propios botones de reanudación como `PROCESS_MODE_ALWAYS` si deben funcionar con SceneTree pausado. [Pausa por tokens](native-ui.md#pausa-y-motivos).

