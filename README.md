# GameExtrakit 0.1.0

Addon de servicios de juegos para **Godot 4.7**, implementado a partir de
[`plugindev.md`](plugindev.md). Ofrece la fachada `GameServices`, recursos de
configuración, dock del editor, adaptadores Android/iOS, simulador y un laboratorio
de integración.

**Estado:** implementación inicial comprobada en Godot `4.7.stable.official.5b4e0cb0f`
en Windows. Las pruebas locales usan simulación y dobles de los bindings. La ejecución
de PGS/Game Center, exportación firmada, iCloud, Sidekick y el backend real todavía
requieren sus entornos de plataforma. No se afirma aceptación completa en dispositivos.

## Instalación

1. Copia `addons/game_extrakit` a `res://addons/game_extrakit` en tu juego, o instala
   el ZIP de `dist` desde la opción de importar paquetes de Godot.
2. Activa **GameExtrakit** en Proyecto → Ajustes del proyecto → Plugins. Esto registra
   el dock y el autoload `GameServices`. Si ese nombre ya existe, resuelve la colisión
   antes de continuar; el addon no lo sustituye.
3. En el dock, crea una configuración, edita módulos, plataformas y catálogos, y
   guárdala como `.tres`. El campo `game_extrakit/config_path` guarda la ruta seleccionada.
4. Para escritorio activa explícitamente **Mock Enabled**. Para dispositivos instala
   la dependencia oficial correspondiente y sigue la [guía de plataformas](addons/game_extrakit/documentation/platforms.md).

El ZIP contiene el addon; no incluye los binarios de terceros ni sus SDKs. Desactivar
un proveedor impide usarlo en runtime, pero sus binarios los administra su exportador.

## Uso

```gdscript
func _ready() -> void:
    # La configuración seleccionada en el dock se carga sin abrir UI de autenticación.
    var auth := await GameServices.authenticate()
    if not auth.is_ok():
        return

    var achievement := await GameServices.unlock_achievement("primera_victoria")
    var score := await GameServices.submit_score("mejor_puntuacion", 12345)
    var saved := await GameServices.save_game("principal", PackedByteArray([1, 2, 3]))
    if saved.status == GEXTypes.Status.UNKNOWN:
        # Conserva el respaldo del juego; no reintentes automáticamente.
        print("No se puede confirmar la escritura: ", saved.error_code)
```

Las claves deben existir en el catálogo. El juego decide la serialización de su partida.
`save_game` recibe bytes opacos y `load_game` no crea un slot ausente.

## Contenido

- [API, resultados y concurrencia](addons/game_extrakit/documentation/api.md).
- [Instalación Android/iOS y exportación](addons/game_extrakit/documentation/platforms.md).
- [Verificador de identidad opcional](addons/game_extrakit/documentation/identity.md).
- [Cobertura de los 25 puntos](addons/game_extrakit/documentation/coverage.md).
- [Validación ejecutada y pruebas de dispositivo](addons/game_extrakit/documentation/validation.md).
- `demo/service_lab.tscn`: ejecutar con F6, o F5 desde este proyecto.

## Validación y empaquetado

```powershell
.\tools\validate.ps1 -Godot 'D:\apps\Godot\Godot_v4.7-stable_win64_console.exe'
.\tools\package.ps1
```

La validación falla si hay errores en los logs, además de comprobar códigos de salida.
El ZIP tiene orden y timestamps fijos y un SHA-256 al lado. El paquete es reproducible
para el mismo contenido y entorno de compresión. Conserva los `.gd.uid` en el proyecto.
