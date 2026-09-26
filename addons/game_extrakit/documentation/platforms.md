# Integración y exportación

Este addon no modifica wrappers, no descarga `main`, no administra consolas y no
duplica la inyección de AAR/frameworks. Los cambios remotos y la firma son del juego.

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

## Sidekick

No se integra el SDK adicional de Sidekick. Las pantallas de logros/rankings PGS no se
etiquetan como Sidekick. Sigue la prueba manual en `validation.md` desde una instalación
de Play: si se reciben eventos de foco/pausa podrán servir como interrupción genérica.
Si no se reciben, esta integración no puede garantizar pausa al abrir Sidekick.
