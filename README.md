# GameExtrakit 0.1.0

Addon para **Godot 4.7** que unifica servicios de Google Play Games y Apple Game Center mediante el autoload `GameServices`.

| Función | Incluye |
|---|---|
| Jugadores | Autenticación, perfil, prueba de identidad y amigos |
| Logros | Definiciones, progreso, desbloqueo y pantalla nativa |
| Rankings | Envío de puntuaciones, score propio, top, cercanos y filtros |
| Partidas | Guardar, cargar, enumerar, eliminar y detectar conflictos |
| Integración | Dock de configuración, capacidades, UI nativa y pausa |
| Desarrollo | Simulador en memoria, laboratorio y pruebas de contrato |

**Estado:** comprobado localmente con Godot `4.7.stable.official.5b4e0cb0f`. La validación en dispositivos y del backend real sigue pendiente. Android no confirma el commit de guardado, no resuelve conflictos manualmente y no observa Sidekick. Consulta la [cobertura por plataforma](addons/game_extrakit/documentation/coverage.md).

## Inicio rápido

1. Copia `addons/game_extrakit` al proyecto o importa el ZIP de `dist`.
2. Activa **GameExtrakit** en Proyecto → Ajustes del proyecto → Plugins.
3. En el dock crea una configuración, activa **Mock Enabled** para probar en escritorio y guarda el Resource.
4. Llama a `await GameServices.authenticate()` desde el juego y comprueba su resultado.

Los binarios de terceros se instalan por separado. Sigue [Primeros pasos](addons/game_extrakit/documentation/getting-started.md) para el ejemplo completo y [Plataformas](addons/game_extrakit/documentation/platforms.md) para Android/iOS.

## Documentación

El [índice del manual](addons/game_extrakit/documentation/README.md) enlaza todas las guías y propone recorridos según la tarea.

- [Configuración y editor](addons/game_extrakit/documentation/configuration.md): todas las opciones, valores por defecto y catálogos.
- [API](addons/game_extrakit/documentation/api.md) y [modelos/resultados](addons/game_extrakit/documentation/results.md): métodos, señales y contratos.
- [Servicios y ejemplos](addons/game_extrakit/documentation/services.md), [partidas y conflictos](addons/game_extrakit/documentation/cloud-save.md), [identidad/backend](addons/game_extrakit/documentation/identity.md).
- [UI nativa y pausa](addons/game_extrakit/documentation/native-ui.md), [sesiones y concurrencia](addons/game_extrakit/documentation/lifecycle.md).
- [Simulador y demo](addons/game_extrakit/documentation/simulator.md), [diagnóstico](addons/game_extrakit/documentation/troubleshooting.md), [validación](addons/game_extrakit/documentation/validation.md).
- [Desarrollo, pruebas y empaquetado](addons/game_extrakit/documentation/development.md).

La especificación original está en [plugindev.md](plugindev.md); el manual describe el comportamiento implementado. Licencia [MIT](addons/game_extrakit/LICENSE) y [avisos de terceros](addons/game_extrakit/THIRD_PARTY_NOTICES.md).

