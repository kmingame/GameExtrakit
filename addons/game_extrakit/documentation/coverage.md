# Cobertura frente a plugindev.md

[Manual](README.md) · [API](api.md) · [Validación](validation.md)

Los métodos siguientes están implementados. **Nativo pendiente** significa que la
ejecución real de la dependencia no se validó; los dobles de prueba no la sustituyen.

| Nº | Objetivo | Android | Apple | API |
|---|---|---|---|---|
| 1 | Autenticación | Adaptador; nativo pendiente | Adaptador; nativo pendiente | authenticate / refresh_auth_state |
| 2 | Perfil | Modelo tipado | gamePlayerID tipado | get_player |
| 3 | Verificación | Código OAuth + verificador opcional | Firma + teamPlayerID + verificador opcional | get_identity_proof / verify_player_identity; backend real pendiente |
| 4 | Amigos | Una página, vacío ambiguo UNKNOWN | Permiso explícito, completo/parcial | list_friends |
| 5 | Desbloquear | Normal/pasos según catálogo | Porcentaje 100 | unlock_achievement |
| 6 | Progreso | Pasos absolutos; false ambiguo | Porcentaje absoluto | set_achievement_progress |
| 7 | Estado logros | Conversión de respuesta | Unión con definiciones para progreso cero | list_player_achievements |
| 8 | Definiciones | Valida tipo y pasos | Metadatos nativos | list_achievement_definitions |
| 9 | UI logros | Despacho UNKNOWN, sin observador | Access point | show_achievements |
| 10 | Enviar score | int64 nativo | int64 nativo | submit_score |
| 11 | Leaderboards | Lista; vacío ambiguo UNKNOWN | Lista del servicio | list_leaderboards |
| 12 | Score propio | null ambiguo UNKNOWN | Entrada opcional | get_player_score |
| 13 | Top N | 1..25 | 1..25 | get_top_scores |
| 14 | Cercanos | Resultado nativo, centrado observado | Dos lecturas / fallback top | get_scores_around_player |
| 15 | Global | COLLECTION_PUBLIC | PlayerScope.global | GEXQuery.scope |
| 16 | Amigos | COLLECTION_FRIENDS | PlayerScope.friendsOnly | GEXQuery.scope |
| 17 | Diario | Calendario Google | TimeScope.today | GEXQuery.period |
| 18 | Semanal | Calendario Google | TimeScope.week | GEXQuery.period |
| 19 | Histórico | ALL_TIME | allTime | GEXQuery.period |
| 20 | UI rankings | Pantallas PGS | Access point / controlador iOS 17 | show_leaderboards / show_leaderboard |
| 21 | Guardar | **UNKNOWN**, commit no verificable | PROVIDER_ACCEPTED según callback | save_game |
| 22 | Cargar | createIfNotFound=false | Buscar nombre y cargar bytes | load_game |
| 23 | Enumerar | Snapshots y metadatos | Saved Games | list_saved_games |
| 24 | Eliminar | Resuelve snapshotId | Todas las versiones del nombre | delete_saved_game |
| 25 | Conflictos | Detecta; resolver **UNSUPPORTED** | Tokens, handles, resolución explícita | save_conflict_detected / resolve_save_conflict |

Transversal: configuración sin dependencias presentes, selección por plataforma,
simulación explícita, FIFO, timeouts, generaciones, pausa por tokens, logging sin datos
sensibles, capacidades, acceso Apple y destinos por versión. Android no tiene control
ni observación de Sidekick. No se añadieron SDKs, puentes, forks ni administración remota.

No se considera cerrada la aceptación completa hasta ejecutar las pruebas nativas,
el backend real y la investigación de Sidekick enumerados en [Validación](validation.md).

## Guías relacionadas con los 25 objetivos

| Objetivos | Guía de integración | Referencia |
|---|---|---|
| 1–2, sesión/perfil | [Servicios](services.md#autenticacion-y-perfil) | [API de identidad](api.md#autenticación-perfil-e-identidad) |
| 3, verificación | [Identidad y backend](identity.md) | [Pruebas y modelos](results.md#playerprofile-e-identityproof) |
| 4, amigos | [Permisos y listas](services.md#amigos) | [API de amigos](api.md#amigos) |
| 5–8, logros | [Progreso y lecturas](services.md#logros) | [Catálogo de logros](configuration.md#catálogo-de-logros) |
| 9, 20, vistas nativas | [Destinos y observación](native-ui.md) | [API de UI](api.md#interfaces-nativas) |
| 10–19, rankings | [Scores, consultas y periodos](services.md#rankings) | [GEXQuery](configuration.md#consultas-gexquery) |
| 21–25, partidas | [Guardados y conflictos](cloud-save.md) | [API de partidas](api.md#partidas) |

## Funciones transversales

| Función | Documentación |
|---|---|
| Dock, Resources, módulos y catálogos | [Configuración completa](configuration.md) |
| Dependencias, presets y exportación | [Plataformas](platforms.md) |
| Estados, datos tipados y capacidades | [Resultados y modelos](results.md) |
| FIFO, timeouts, cancelación, generaciones y cierre | [Ciclo de vida](lifecycle.md) |
| Access point, overlays, pausa y actividades Apple | [UI e interrupciones](native-ui.md) |
| Simulación, cuentas y fallos controlados | [Simulador y laboratorio](simulator.md) |
| Errores y recuperación | [Diagnóstico](troubleshooting.md) |
| Scripts de prueba, ZIP, versiones y licencias | [Desarrollo](development.md) |

## Exclusiones y límites de alcance

- Events Google, Game Stats, Recall, Quests y servicios ajenos al contrato.
- SDK separado de Sidekick, control/visibilidad no expuestos, nuevos puentes, señales nativas o forks para suplirlos.
- Multiplayer, matchmaking, sistemas propios de retos o administración remota de Challenges/Activities. Abrir destinos Apple y recibir eventos ya expuestos sí está contemplado.
- Compras, anuncios, analítica, notificaciones y Sign in with Apple independiente de Game Center.
- Unión de cuentas, partidas o rankings entre Android e iOS.
- Crear/configurar automáticamente productos, logros, rankings, credenciales, permisos o testers en consolas.
- Editor de HUD/UI de gameplay, descarga de avatares o navegación automática de escenas.
- Backend de verificación operativo, formato de partida, cifrado, backup, fusión genérica y reintentos persistentes.

La existencia de un método común no significa soporte completo en ambas plataformas. El objetivo 25 permanece parcial en Android y el 21 no tiene confirmación fiable del commit en el binding fijado. Las guías describen estas diferencias; no se presentan los 25 puntos como certificados en dispositivos.
