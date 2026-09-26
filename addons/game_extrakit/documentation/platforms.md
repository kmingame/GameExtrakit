# Integración y exportación

[Manual](README.md) · [Configuración](configuration.md) · [Diagnóstico](troubleshooting.md) · [Validación](validation.md)

Este addon no modifica wrappers, no descarga `main`, no administra consolas y no
duplica la inyección de AAR/frameworks. Los cambios remotos y la firma son del juego.

## Dependencias y versiones

| Componente | Referencia de integración | Evidencia |
|---|---|---|
| Godot | 4.7 estable; ejecutado 4.7.stable.official.5b4e0cb0f | Importación, contrato, editor y PCK locales |
| Android | godot-play-game-services v3.4.0, commit e38b618578572b558691c4f476f70f5e142226ce | API fuente examinada; artefacto y dispositivo pendientes |
| Apple | GodotApplePlugins, commit a2ae65df061c80d66420e23572300cc9ffcedb7c | Fuentes Game Center/SwiftGodotRuntime examinadas; artefacto y dispositivo pendientes |

El [lock de dependencias](../dependencies.lock.json) es el registro de referencias y evidencia. No es un instalador ni asegura por sí solo compatibilidad binaria. Los [avisos de terceros](../THIRD_PARTY_NOTICES.md) acompañan al addon.

## Android

1. Instala el paquete oficial de
   [godot-play-game-services 3.4.0](https://github.com/godot-sdk-integrations/godot-play-game-services/releases/tag/v3.4.0)
   preservando `res://addons/GodotPlayGameServices`. Activa su plugin de editor.
2. Usa Godot y plantillas **4.7 estables coincidentes**. Crea el preset Android con
   Gradle Build según el exportador oficial. Su código declara Java 17, compileSdk 35,
   minSdk 21 y Play Games v2 21.0.0; confirma tu cadena final de exportación.
3. El único Game ID editable vive en **Proyecto → Exportar → Android →
   godot_play_game_services/game_id**. El dock lo lee como diagnóstico; no crea otro.
4. Configura el paquete, la firma SHA del certificado, testers, PGS y Saved Games en
   Play Console. Copia IDs de logros/rankings al catálogo y activa Android.
5. Si necesitas verificación server-side, completa `android_server_client_id` con el
   identificador OAuth público del servidor. El secreto permanece en el backend.
6. Desactiva el simulador y ejecuta las pruebas de dispositivo.

La fuente fijada es el commit
[`e38b618578572b558691c4f476f70f5e142226ce`](https://github.com/godot-sdk-integrations/godot-play-game-services/tree/e38b618578572b558691c4f476f70f5e142226ce).
La release binaria no se descargó ni se comparó con este commit. Registra su SHA-256
antes de fijarla en el juego; actualizar la dependencia exige reevaluar capacidades.

No uses a la vez los clientes GDScript PGS y GameServices para emitir solicitudes.
Sus señales nativas carecen de correlación suficiente para compartirlas entre clientes.

### Comprobaciones Android

El diagnóstico busca el descriptor en `res://addons/GodotPlayGameServices/plugin.cfg` y estos artefactos:

```text
res://addons/GodotPlayGameServices/bin/debug/GodotPlayGameServices-debug.aar
res://addons/GodotPlayGameServices/bin/release/GodotPlayGameServices-release.aar
```

Lee la versión declarada, el Game ID, `gradle_build/use_gradle_build` y `package/unique_name` del preset. La presencia de archivos no confirma su contenido ni la firma de la aplicación. El runtime busca el singleton `GodotPlayGameServices` y comprueba la presencia de `setAchievementSteps`; tampoco es una auditoría binaria completa.

El exportador oficial administra los AAR y su inicialización; GameExtrakit reutiliza la inicialización del autoload PGS si está disponible. No añadas otro puente o inyección manual en paralelo para corregir una dependencia ausente.

En el dispositivo comprueba autenticación con la cuenta de prueba, permisos de amigos y catálogos configurados para ese entorno. Una clave local no reemplaza un ID creado en Play Console. Para los casos específicos de firma, distribución y testers usa la guía del paquete oficial de la versión fijada.

Guardados, conflictos, consultas y UI conservan las [limitaciones Android de cobertura](coverage.md). Una lectura vacía ambigua o un guardado UNKNOWN no se corrigen prometiendo éxito en la UI.

## Apple / iOS

1. Compila o instala **Game Center** y **SwiftGodotRuntime** de
   [GodotApplePlugins](https://github.com/migueldeicaza/GodotApplePlugins), fijados al
   commit `a2ae65df061c80d66420e23572300cc9ffcedb7c`. Respeta las rutas de sus descriptores.
2. Usa macOS/Xcode y las plantillas Godot 4.7 correspondientes. El paquete examinado
   requiere iOS 17 como mínimo y Swift tools 6.2 para compilar; valida arquitecturas
   y runtime. No necesitas los módulos de Ads, compras o Sign in with Apple.
3. Configura Bundle ID, Game Center y los IDs de catálogo en App Store Connect/Xcode.
   El Bundle ID del Resource debe coincidir con el preset y la app.
4. Para Saved Games habilita el contenedor/capacidades iCloud necesarios. La sesión
   Game Center no prueba disponibilidad de iCloud.
5. Para amigos proporciona el texto `NSGKFriendListUsageDescription` apropiado en la
   app. Usa una acción explícita del usuario para `ask_permission=true`.
6. Activa Apple en el Resource. La aparición de clases/stubs en Windows no prueba
   disponibilidad iOS; el runtime selecciona Apple únicamente en iOS.

Los callbacks de datos del binding no están todos despachados explícitamente al motor
en sus fuentes. GameExtrakit entra por un buzón que solo llama `call_deferred`, y conecta
señales con `CONNECT_DEFERRED`; la creación/conversión previa de objetos dentro del
binding aún necesita validación en dispositivo. No se afirma certificación de hilos
del SDK a partir de estas pruebas GDScript.

### Comprobaciones Apple

El adaptador requiere las clases `GameCenterManager`, `GKLocalPlayer`, `GKAchievement`, `GKAchievementDescription`, `GKLeaderboard`, `GKSavedGame` y `GKAccessPoint`. Usa los componentes y rutas oficiales completos; un stub importable no reemplaza el framework para el dispositivo.

`apple_minimum_ios`, Bundle ID y contenedor son declaraciones locales. No cambian el deployment target, el perfil de aprovisionamiento, capacidades, Info.plist ni entitlements. Revisa en la exportación/Xcode:

- Bundle ID del preset y de la app igual al del Resource.
- Game Center habilitado para la app y la cuenta de prueba.
- Capacidades/contenedor iCloud apropiados para Saved Games y sesión iCloud disponible.
- Descripción de uso de amigos `NSGKFriendListUsageDescription`.
- Frameworks, SwiftGodotRuntime, arquitecturas, firma y mínimo de iOS compatibles con tu destino.

La versión real del sistema determina los [destinos disponibles](native-ui.md#matriz-de-destinos). No hace falta activar módulos de anuncios, compras ni Sign in with Apple para usar este contrato.

## Empaquetado

El export hook incluye la configuración seleccionada. El código de editor está
separado del runtime; para excluir también sus scripts compilados añade
`addons/game_extrakit/editor/*` al filtro de exclusión de tu preset (el exportador
GDScript puede añadir archivos compilados antes de que otro export hook omita el original).
Usa **Exportar todos los recursos**; valida especialmente cualquier filtro personalizado
que pueda excluir catálogos externos. Se recomienda guardar catálogos como subrecursos
del `.tres`, como hace el dock.

Desactivar `android_enabled`/`apple_enabled` impide utilizar ese proveedor en runtime.
Para excluir sus binarios, desactiva el exportador o retira la dependencia del destino
según sus propias instrucciones. GameExtrakit no puede impedir que otro plugin inyecte
sus binarios. No se modifica automáticamente ningún identificador, permiso ni firma.

Para distribuir el addon ejecuta `tools/package.ps1`. El ZIP solo contiene
`addons/game_extrakit`, documentación y licencia. `dependencies.lock.json` fija las
fuentes; los campos de binarios permanecen sin verificar hasta probar artefactos reales.

### Revisión antes de exportar

1. Abre la configuración de destino en el dock y guárdala: hay una ruta global seleccionada, no una configuración automática por preset.
2. Revisa `mock_enabled`, proveedor, módulos, IDs, prefijo y presupuesto de guardado.
3. Usa plantillas de la misma versión de Godot y comprueba los exportadores nativos externos.
4. Incluye el Resource y todos sus scripts/catálogos externos. El hook añade el archivo de configuración, pero no corrige cualquier filtro de recursos personalizado.
5. Revisa el log: el hook emite `push_error` por configuración inválida o mock bloqueado, **no aborta por sí mismo la exportación**. El runtime vuelve a rechazar la configuración inválida.
6. Instala y ejecuta el artefacto firmado en el dispositivo; un PCK local no valida esta etapa.

El filtro de exclusión de editor afecta al empaquetado del juego, no al ZIP de instalación del addon, que sí debe llevar su editor. Consulta [Desarrollo](development.md#crear-el-zip) para producir el paquete distribuible.

## Sidekick

No se integra el SDK adicional de Sidekick. Las pantallas de logros/rankings PGS no se
etiquetan como Sidekick. Sigue la [prueba manual](validation.md#investigación-de-sidekick) desde una instalación
de Play: si se reciben eventos de foco/pausa podrán servir como interrupción genérica.
Si no se reciben, esta integración no puede garantizar pausa al abrir Sidekick.

## Continuar la integración

[Sesión, amigos, logros y rankings](services.md) · [Partidas/iCloud](cloud-save.md) · [Backend opcional](identity.md) · [Pausa y actividades](native-ui.md).
