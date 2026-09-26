# Validación del 26 de septiembre de 2026

[Manual](README.md) · [Cobertura](coverage.md) · [Desarrollo y comandos](development.md#ejecutar-validación-local) · [Diagnóstico](troubleshooting.md)

Motor ejecutado: `4.7.stable.official.5b4e0cb0f` (Windows x86_64).
Renderer de la demo: Compatibility/OpenGL 3.3, GTX 1660.

## Evidencia local

- Importación headless del proyecto, sin dependencias nativas instaladas.
- 83 comprobaciones de contrato y límites: autenticación, módulos, claves, progreso,
  amigos, combinaciones de filtros, scores int64, bytes, slots, conflictos y errores.
- Dobles de Android: guardado prematuro UNKNOWN, bytes Java negativos, pasos absolutos,
  amigos ambiguos, preservación exacta de 9223372036854775807, rank 42, borrado por ID,
  timeout, rechazo de respuesta con otro ID y drenaje de respuesta tardía.
- Dobles de Apple: callbacks diferidos, carga de bytes, consulta de amigos sin abrir
  permisos, vacío autorizado, conflictos con múltiples handles, tokens de un solo uso,
  disponibilidad de destinos y presentación independiente del botón.
- Cambio de cuenta, aislamiento de datos del simulador y descarte de solicitudes antiguas.
- Pausas superpuestas, eventos duplicados, pausa manual y pausa previa de SceneTree.
- Plugin en proyecto aislado: activar, crear/cargar Resource en el dock, desactivar
  limpiando el autoload por UID, y reactivar.
- Exportación PCK local y ejecución de su autoload, configuración y guardado/carga simulados.
- Demo ejecutada headless y revisión visual de su captura con renderizado real.

`tools/validate.ps1` reproduce las pruebas, comprueba el código de salida y busca
errores tanto en log como en stdout/stderr. Esto incluye errores de cierre que Godot
puede imprimir después de cerrar su propio archivo de log. La salida queda bajo
`test-results/`; no se incluye en el ZIP del addon.

## Pendiente antes de aceptación nativa

La ampliación del manual no modifica este estado de aceptación: las comprobaciones
documentales se registran al final y no sustituyen pruebas de SDKs en dispositivos.

No se instalaron/compilaron binarios PGS o Apple ni se firmaron paquetes móviles.
No se realizó una prueba Android/iOS, se cambió una consola remota o se llamó a un
backend real. Los checksums de dependencias y su correspondencia con las fuentes
siguen pendientes en el [lock de dependencias](../dependencies.lock.json).

1. Fijar los artefactos exactos y SHA-256; probar editor y plantillas 4.7 coincidentes.
2. Android: plugin único y ambos paquetes instalados; autenticar, cancelar, reconectar,
   cambiar cuenta, usar permisos de amigos y probar logros normales/incrementales.
3. Android: scores grandes, filtros, jugador sin puntuación, dos consultas concurrentes,
   cache/red fallida, slots ausentes, conflicto y confirmación de guardado UNKNOWN.
4. Apple: compilar/exportar con GameCenter/SwiftGodotRuntime, arquitectura y firma;
   probar autenticación e iCloud independientes, bytes, duplicados de un nombre,
   resolver conflictos entre dispositivos, cambios remotos y cambio de cuenta.
5. Apple: confirmar enum nativo de autorización de amigos en el dispositivo y comprobar
   el comportamiento del buzón diferido con los hilos reales de los callbacks.
6. Apple: iOS 17/18/26 según dispositivos disponibles; destinos no soportados deben
   regresar inmediatamente. Abrir desde el botón nativo y desde la API; ocultar el
   botón durante presentación, pausar y verificar que se detecte el cierre.
7. Backend: prueba válida, inválida, caducada, de otra app, indisponible y respuesta
   tardía tras cambio de cuenta. La simulación no certifica identidad.
8. Exportación firmada instalada, pruebas de suspensión/proceso terminado, tamaños
   próximos al presupuesto y dispositivos objetivo.

## Investigación de Sidekick

Usar una instalación de prueba de Google Play que realmente ofrezca Sidekick. Abrir
el laboratorio con una configuración Android real y registrar únicamente timestamps,
tipos de evento y motivos de pausa. Nunca códigos OAuth, perfiles o partidas.

| Caso | Evidencia a registrar | Resultado esperado de GameExtrakit |
|---|---|---|
| Abrir/cerrar Sidekick varias veces | FOCUS_OUT/IN, PAUSED/RESUMED si se reciben | Estado de Sidekick continúa UNKNOWN |
| Abrir logros/rankings PGS | Eventos de ciclo de vida recibidos | No se identifica la pantalla como Sidekick |
| Notificación, diálogo y cambio de app | Las mismas notificaciones genéricas | Nunca se atribuyen a un overlay específico |
| Foco recuperado con suspensión/pausa manual | Motivos activos | No reanuda hasta liberar cada motivo propio |
| Sidekick no produce eventos | Ausencia registrada | No se garantiza pausa específica |

Completar un registro por combinación de dispositivo, Android, Godot, distribución y
versión de dependencia. Aunque un fallback funcione en esos equipos, seguirá siendo
detección de interrupción genérica. No ampliar el wrapper ni agregar SDKs para esta prueba.

## Revisión documental

La revisión del 26 de septiembre de 2026 mantuvo los README como entradas breves y
organizó el manual en 16 páginas relacionadas. Se contrastaron con el código:

- Los 40 métodos públicos y 9 señales de la fachada.
- Los 47 campos de los cuatro Resources de configuración, incluidos valores iniciales.
- Los 100 campos de GEXResult y modelos de GEXTypes, con sus valores opcionales.
- Los códigos de error del runtime, límites de plataforma y cobertura de los 25 objetivos.
- Los enlaces locales y anclas del manual y ambos README, sin destinos rotos.

Se extrajeron 25 bloques GDScript a un proyecto aislado con el addon y su autoload.
Godot 4.7 importó el proyecto y analizó/cargó todos los scripts sin errores de sintaxis.
**No se ejecutaron las operaciones de esos ejemplos contra proveedores ni backend**;
esta comprobación acredita sintaxis y resolución de tipos, no aceptación nativa.

El inventario y la evidencia local quedaron en
`test-results/documentation-audit.json` y `test-results/documentation-examples.log`
del proyecto de desarrollo. Estos archivos temporales no forman parte del ZIP.
Los comandos de validación funcional existentes siguen documentados en
[Desarrollo](development.md#ejecutar-validación-local).
