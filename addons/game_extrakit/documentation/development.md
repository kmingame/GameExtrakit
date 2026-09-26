# Desarrollo, pruebas y distribución

[Manual](README.md) · [Cobertura](coverage.md) · [Validación](validation.md) · [Dependencias](platforms.md)

Esta guía distingue el **repositorio de desarrollo completo** del **ZIP instalable**. Los comandos de tools y la demo requieren el repositorio; no se incluyen en el ZIP.

## Estructura

```text
README.md                         Presentación breve del proyecto
plugindev.md                      Especificación, hallazgos y registro de implementación
project.godot                     Proyecto de laboratorio
addons/game_extrakit/
  plugin.cfg                      Descriptor 0.1.0
  configuration/                  GEXConfig, logros, rankings y GEXQuery
  editor/                         Dock, registro del plugin, diagnóstico y export hook
  runtime/
    game_services.gd              Fachada/autoload
    request_coordinator.gd        Cola FIFO y generaciones
    native_reply.gd               Buzón de callbacks diferidos
    interruption_coordinator.gd   Motivos y propiedad de pausa
    adapters/                     Android, Apple, mock y parser JSON nativo
    models/                       GEXTypes y GEXResult
    identity/                     Interfaz de verificador y cliente HTTP
  documentation/                  Manual completo incluido en el paquete
  dependencies.lock.json          Fuentes fijadas y estado de verificación
  LICENSE                         Licencia del addon
  THIRD_PARTY_NOTICES.md           Dependencias externas
demo/                             Laboratorio visual
tests/                            Contrato, ciclo de editor y smoke de exportación
tools/                            Scripts PowerShell de validación y empaquetado
dist/                             ZIP y SHA-256 generados
test-results/                     Logs, fixtures y evidencias locales ignoradas
```

Conserva los `.gd.uid` junto a los scripts. No distribuyas `.godot`, fixtures, credenciales, logs ni el estado local de pruebas como parte del addon.

## Arquitectura y responsabilidades

| Capa | Responsabilidad |
|---|---|
| GEXConfig y catálogos | Configuración pública y mapeo de claves; no crean objetos en consolas |
| GEXGameServices | Precondiciones, API común, estado de sesión y señales |
| GEXRequestCoordinator | Serializar operaciones y completar cada solicitud una sola vez |
| GEXNativeReply | Retener callbacks y diferir recepción al hilo principal |
| GEXPlatformAdapter | Frontera interna; argumentos nativos/handles no forman parte de la API del juego |
| Android adapter | Consumir singleton y señales existentes, correlacionar IDs posibles y drenar canales |
| Apple adapter | Resolver clases dinámicamente, callbacks/listeners y observar propiedad de presentación |
| Mock adapter | Datos de prueba por cuenta y escenarios explícitos |
| Interruption coordinator | Componer motivos y administrar opcionalmente SceneTree |
| Verificador | Obtener respuesta de un backend del juego; no confiar localmente en la prueba |
| Editor/export hook | Crear/configurar Resources y asegurar su inclusión; binarios pertenecen a sus exportadores |

GEXPlatformAdapter, GEXRequestCoordinator, GEXNativeReply y GEXNativeJson son detalles de implementación, aunque GDScript los registre como clases globales. El contrato de integración es la [fachada](api.md), los [recursos](configuration.md), los [modelos](results.md) y el [verificador extensible](identity.md).

Apple usa ClassDB de forma dinámica para que los scripts puedan analizarse en Windows sin símbolos GameKit. El buzón usa call_deferred y las señales nativas se conectan diferidas. La creación/conversión previa de objetos por el binding necesita prueba real de hilos; no puede certificarse solo con dobles.

## Ejecutar validación local

Desde la raíz del proyecto, en PowerShell con .NET disponible:

```powershell
.\tools\validate.ps1 -Godot 'D:\apps\Godot\Godot_v4.7-stable_win64_console.exe'
```

Sustituye la ruta por tu ejecutable console de Godot 4.7. El parámetro `-Godot` es obligatorio. El script:

1. Importa el proyecto en headless.
2. Ejecuta las comprobaciones de contrato en `tests/run_tests.gd`.
3. Arranca la demo en headless.
4. Crea un proyecto aislado con GUID bajo `test-results`, importa y prueba activar, editar Resource, desactivar y reactivar el plugin.
5. Exporta un PCK de prueba Windows y lo ejecuta para comprobar autoload, configuración y roundtrip de bytes.
6. Falla por código de salida o por patrones de error/fugas en stdout/stderr capturados.

Los archivos `*.log.console.txt` incluyen también mensajes de cierre que pueden aparecer después de que Godot cierre su log. Consulta la lista de evidencia y alcance en [Validación](validation.md).

El fixture permite simulación release expresamente para probar el PCK; no cambies por ello la política de tu Resource de producción. La exportación PCK no es una exportación móvil firmada ni valida plantillas/SDKs Android/iOS.

Para ejecutarlo, el sistema debe permitir a Godot escribir su configuración de usuario y datos locales. Si se usa un entorno aislado, revisa sus permisos en vez de ocultar los errores del motor.

## Crear el ZIP

```powershell
.\tools\package.ps1
# Para nombrar un paquete de otra versión:
.\tools\package.ps1 -Version '0.1.0'
Get-FileHash .\dist\game-extrakit-0.1.0.zip -Algorithm SHA256
```

El script toma todos los archivos de `addons/game_extrakit`, ordenados por ruta, con timestamp fijo de ZIP (2026-09-26). Genera/sobrescribe `dist/game-extrakit-VERSION.zip` y `.zip.sha256`. El resultado es reproducible para contenido y entorno de compresión iguales.

`-Version` valida el formato y cambia **el nombre del archivo**, no modifica `plugin.cfg`, títulos ni el contrato. Actualiza esos metadatos conscientemente al publicar otra versión.

El ZIP contiene documentación, scripts, UIDs, licencia y lock de fuentes; no contiene el proyecto de demo, tests, herramientas ni binarios de terceros. El script no descarga dependencias ni publica el paquete. Revisa el contenido de la carpeta del addon antes de empaquetar: cualquier archivo que dejes allí se incluirá.

## Actualizar código o dependencias

1. Fija una referencia oficial concreta y conserva licencias/avisos.
2. Compara métodos, señales, argumentos, nombres de propiedades, callback arities, JSON y enums con el adapter.
3. Reevalúa confirmación de guardado, correlación, conflictos, permisos, rangos, UI y hilos. Una versión nueva no elimina automáticamente un UNKNOWN.
4. Actualiza adaptador/capacidades, pruebas relevantes, manual y matriz de cobertura.
5. Ejecuta validación local y los casos nativos afectados.
6. Registra artefactos y SHA-256 en `dependencies.lock.json` únicamente después de verificarlos.

El lock contiene `contract_version`, `godot_tested` y, por dependencia, repositorio, source_commit, referencia de release/componentes, artifact_sha256, binary_source_correspondence_verified y device_tested. Los valores null/false actuales expresan evidencia pendiente, no una comprobación satisfactoria.

No sustituyas el commit fijado por main ni interpretes la versión del descriptor como hash de un AAR/framework. La actualización no autoriza añadir forks, SDKs o puentes para suplir funciones excluidas.

## Mantener documentación

El README raíz y el del addon son entradas breves. Conserva el detalle en esta carpeta y enlaza cada nuevo capítulo desde el [índice](README.md). Las guías deben funcionar dentro del ZIP, por lo que las rutas a demo/tests/tools del repositorio se describen como rutas de texto, no enlaces internos que quedarían rotos en el paquete.

Ante cambios de contrato revisa firmas/señales en [API](api.md), campos/valores en [Configuración](configuration.md) y [Resultados](results.md), códigos en [Diagnóstico](troubleshooting.md), ejemplos y [Cobertura](coverage.md). Comprueba enlaces/anclas y analiza los ejemplos GDScript con el motor objetivo.

No marques una funcionalidad como probada en dispositivo usando solo mock o dobles. Mantén [Validación](validation.md) como registro de evidencia con fecha, entorno y alcance.

