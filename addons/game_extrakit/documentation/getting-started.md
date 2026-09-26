# Primeros pasos

[Manual](README.md) · [Configuración](configuration.md) · [Plataformas](platforms.md)

## Requisitos e instalación

Usa Godot 4.7. La versión comprobada es `4.7.stable.official.5b4e0cb0f`; los resultados de otras versiones no están certificados. El addon usa GDScript y puede importarse en escritorio sin tener las dependencias móviles presentes.

1. Copia la carpeta del addon a `res://addons/game_extrakit`, conservando archivos `.gd.uid`. También puedes importar el ZIP generado por el proyecto desde el editor.
2. Activa **GameExtrakit** en Proyecto → Ajustes del proyecto → Plugins.
3. Comprueba la aparición del dock **GameExtrakit** y el autoload `GameServices`. Si otro autoload tiene ese nombre, renómbralo o resuelve la colisión antes de usar los ejemplos. El plugin no lo reemplaza.
4. Pulsa **Nueva**, activa **Mock Enabled**, deja Android/Apple desactivados y pulsa **Guardar**. Una ruta posible es `res://game_services.tres`.
5. En **Diagnóstico**, pulsa **Actualizar diagnóstico**. Debe mostrar configuración local válida y simulación explícita.

Guardar o abrir selecciona la ruta `game_extrakit/config_path` en los ajustes del proyecto. **Nueva** por sí sola no reemplaza la ruta activa. Los cambios requieren guardar; no hay autoguardado ni recarga en caliente de la instancia en ejecución.

## Primera operación

Añade este script a un Node de tu escena y ejecuta el proyecto:

```gdscript
extends Node

func _ready() -> void:
    var caps := GameServices.get_capabilities()
    if not caps.available:
        push_warning("Revisa la configuración seleccionada y el diagnóstico.")
        return

    var result := await GameServices.authenticate()
    if not result.is_ok():
        push_warning("Autenticación: " + result.error_code)
        return
    if result.player == null:
        push_warning("Todavía no hay un jugador autenticado.")
        return

    print("Proveedor: ", GEXTypes.Provider.keys()[result.provider])
    print("Sesión preparada.")
```

La carga de configuración no abre el diálogo de autenticación: el juego decide cuándo llamar a `authenticate()`. Para comprobar una sesión existente consulta [Autenticación](services.md#autenticacion-y-perfil). En una UI de producción conviene iniciar el flujo interactivo desde una acción del usuario.

## Añadir funciones

En **Catálogos**, añade un logro con `key=primera_victoria` y un leaderboard con `key=mejor_puntuacion`. En simulación no hacen falta IDs nativos mientras ambas plataformas estén desactivadas. Guarda y reinicia la ejecución.

```gdscript
func registrar_victoria(puntos: int) -> void:
    var logro := await GameServices.unlock_achievement("primera_victoria")
    if not logro.is_ok():
        push_warning("Logro: " + logro.error_code)

    var ranking := await GameServices.submit_score("mejor_puntuacion", puntos)
    if not ranking.is_ok():
        push_warning("Puntuación: " + ranking.error_code)
```

Esta función presupone autenticación correcta y módulos habilitados. No encadenes reintentos automáticos ante `UNKNOWN`. Consulta [Servicios](services.md) para leer resultados y [Partidas](cloud-save.md) para guardar bytes.

## Pasar a dispositivos

Instala las [dependencias oficiales](platforms.md), configura las consolas y el preset correspondiente, completa IDs, activa el proveedor y desactiva `mock_enabled`. El simulador tiene prioridad incluso en un teléfono; dejarlo activado impide comprobar los servicios reales.

| Entorno | Selección |
|---|---|
| Cualquier sistema con `mock_enabled=true` | MOCK; una compilación release exige además `allow_mock_in_release=true` |
| Android con mock apagado | PGS si `android_enabled=true`; si no, `FEATURE_DISABLED` |
| iOS con mock apagado | Game Center si `apple_enabled=true`; si no, `FEATURE_DISABLED` |
| Escritorio/web/otro con mock apagado | `UNSUPPORTED_PLATFORM` |

Las dos plataformas pueden estar habilitadas en el mismo Resource, siempre que todos sus campos requeridos sean válidos. No existe cambio de proveedor en caliente.

## Desactivar y retirar

Desactivar el plugin quita el dock y el export hook y elimina únicamente el autoload que el plugin registró y todavía reconoce como propio. Conserva el Resource y la ruta de configuración. Cerrar el editor no equivale a desactivar el plugin.

Para retirar el addon del juego, desactívalo primero, elimina referencias de tus escenas/scripts y después retira su carpeta. Las dependencias móviles y sus exportadores se gestionan por separado. Si administras la instancia manualmente, sigue [Ciclo de vida](lifecycle.md).

