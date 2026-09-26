# GameExtrakit 0.1.0

Servicios de juegos para **Godot 4.7** mediante el autoload `GameServices`: autenticación, perfil, identidad, amigos, logros, rankings, partidas, interfaces nativas e interrupciones. Incluye configuración en el editor y simulador en memoria.

## Instalación rápida

1. Conserva esta carpeta en `res://addons/game_extrakit`.
2. Activa **GameExtrakit** en Proyecto → Ajustes del proyecto → Plugins.
3. Crea y guarda una configuración en el dock. Para escritorio activa **Mock Enabled**.
4. Sigue el [ejemplo de inicio](documentation/getting-started.md) y comprueba los resultados de cada operación.

Android/iOS requieren [dependencias oficiales externas](documentation/platforms.md). La ejecución local está comprobada en Godot 4.7 estable; la aceptación nativa y el backend real están [pendientes](documentation/validation.md). Android mantiene guardados `UNKNOWN`, resolución manual de conflictos `UNSUPPORTED` y visibilidad de Sidekick desconocida.

## Manual

- [Índice y recorridos](documentation/README.md).
- [Configuración completa](documentation/configuration.md), [API y señales](documentation/api.md), [modelos y resultados](documentation/results.md).
- [Servicios y ejemplos](documentation/services.md), [partidas/conflictos](documentation/cloud-save.md), [identidad/backend](documentation/identity.md).
- [UI nativa/pausa](documentation/native-ui.md), [ciclo de vida](documentation/lifecycle.md).
- [Simulador](documentation/simulator.md), [diagnóstico](documentation/troubleshooting.md), [cobertura](documentation/coverage.md).
- [Validación](documentation/validation.md) y [desarrollo/empaquetado](documentation/development.md).

Licencia [MIT](LICENSE). Consulta los [avisos de terceros](THIRD_PARTY_NOTICES.md) y las [versiones fijadas](dependencies.lock.json).

