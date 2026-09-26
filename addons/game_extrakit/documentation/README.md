# Manual de GameExtrakit

[Presentación del addon](../README.md)

Documentación de **GameExtrakit 0.1.0**, contrato 0.1 y configuración de esquema 1, para Godot 4.7. Describe el código entregado y separa las comprobaciones locales de las pruebas nativas pendientes.

## Recorridos recomendados

| Quiero… | Leer en este orden |
|---|---|
| Probar por primera vez | [Primeros pasos](getting-started.md) → [Simulador](simulator.md) → [Resultados](results.md) |
| Integrar mi juego | [Configuración](configuration.md) → [Servicios](services.md) → [API](api.md) |
| Guardar partidas | [Resultados](results.md) → [Partidas y conflictos](cloud-save.md) → [Sesiones](lifecycle.md) |
| Preparar Android/iOS | [Plataformas](platforms.md) → [Cobertura](coverage.md) → [Validación](validation.md) |
| Conectar mi backend | [Identidad](identity.md) → [Sesiones](lifecycle.md) → [Diagnóstico](troubleshooting.md) |
| Pausar durante interfaces nativas | [UI e interrupciones](native-ui.md) → [Configuración](configuration.md) |
| Investigar un error | [Diagnóstico](troubleshooting.md) → [Resultados](results.md) → [Validación](validation.md) |
| Mantener o distribuir el addon | [Desarrollo](development.md) → [Cobertura](coverage.md) → [Validación](validation.md) |

## Referencia completa

| Documento | Contenido |
|---|---|
| [Primeros pasos](getting-started.md) | Instalación, primer inicio, ejemplo, selección de proveedor y desinstalación |
| [Configuración](configuration.md) | Dock, todos los campos y valores por defecto, catálogos, consultas, validación |
| [API](api.md) | Firmas, argumentos, resultados de cada operación y todas las señales públicas |
| [Resultados y modelos](results.md) | Estados, enums, propiedades tipadas, capacidades y campos opcionales |
| [Servicios](services.md) | Autenticación, perfil, amigos, logros, rankings y ejemplos de uso |
| [Partidas](cloud-save.md) | Bytes, slots, metadatos, aceptación, sincronización, conflictos y recuperación |
| [Identidad](identity.md) | Pruebas Google/Apple, protocolo HTTP, verificador inyectable y responsabilidades del servidor |
| [UI nativa](native-ui.md) | Destinos por iOS, access point, observación, pausa, Sidekick y actividades |
| [Ciclo de vida](lifecycle.md) | Inicialización manual, cola FIFO, timeouts, cuenta, cancelación y cierre |
| [Plataformas](platforms.md) | Dependencias fijadas, Android/iOS, exportación y límites del export hook |
| [Simulador](simulator.md) | Datos de prueba, fallos, cuentas, conflictos, presentaciones y laboratorio |
| [Diagnóstico](troubleshooting.md) | Todos los códigos de error, síntomas, comprobaciones y registro |
| [Cobertura](coverage.md) | Los 25 objetivos funcionales y exclusiones del contrato |
| [Validación](validation.md) | Evidencia local, aceptación pendiente y protocolo de Sidekick |
| [Desarrollo](development.md) | Estructura, arquitectura, pruebas, empaquetado y actualización de dependencias |

## Convenciones

Los ejemplos usan GDScript con `GameServices` como autoload. Las claves `primera_victoria`, `coleccionista` y `mejor_puntuacion` deben existir en el catálogo cuando un ejemplo las utilice; se explica cómo crearlas en [Configuración](configuration.md). Los fragmentos con funciones se pegan en un script `extends Node`, salvo que indiquen otra base.

Los objetos `GEXTypes.*` son datos comunes. Los identificadores son opacos; no representan cuentas compartidas entre Apple y Google. Un campo ausente no se convierte en una certeza: `UNKNOWN`, `null`, `-1` y los indicadores `*_known` se explican en [Resultados](results.md).

La API no administra las consolas, no instala SDKs ni implementa un backend. La [matriz de cobertura](coverage.md) y la [validación](validation.md) delimitan lo implementado y lo probado.

