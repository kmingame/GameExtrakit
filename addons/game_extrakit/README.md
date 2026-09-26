# GameExtrakit 0.1.0

Servicios de juegos para Godot 4.7: `GameServices`, configuración en el editor,
PGS Android, Game Center iOS, simulador e interrupciones.

Activa el plugin, crea y guarda un Resource desde el dock **GameExtrakit**, configura
las claves e IDs de catálogo y habilita la plataforma o simulación explícita.

- [API](documentation/api.md)
- [Instalación y exportación por plataforma](documentation/platforms.md)
- [Cobertura de los 25 objetivos](documentation/coverage.md)
- [Verificación de identidad](documentation/identity.md)
- [Validación y trabajo pendiente en dispositivos](documentation/validation.md)

Los binarios de terceros no están incluidos. La compatibilidad nativa en dispositivos
requiere validación. En Android la confirmación de guardado es `UNKNOWN`, la resolución
manual de conflictos es `UNSUPPORTED` y el estado de Sidekick es desconocido.
