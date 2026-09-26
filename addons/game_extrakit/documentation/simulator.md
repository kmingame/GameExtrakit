# Simulador y laboratorio

[Manual](README.md) · [Primeros pasos](getting-started.md) · [API](api.md) · [Validación](validation.md)

El simulador es explícito, determinista y en memoria. Sirve para desarrollar la integración en escritorio y provocar estados controlados. No valida servicios nativos, firma, permisos reales, cuotas, sincronización o backend.

## Activación y datos

Activa `mock_enabled`. Tiene prioridad incluso en Android/iOS. En release también exige `allow_mock_in_release=true`; la configuración de producción debe desactivar mock.

| Área | Comportamiento simulado |
|---|---|
| Autenticación | authenticate habilita sesión; refresh conserva el estado observado |
| Perfil | ID configurado; display_name “Simulator / ID”; id_scope “simulation” |
| Amigos | friend-1, friend-2 y friend-3, recortados al límite |
| Logros | Del catálogo; progreso absoluto monótono por cuenta |
| Rankings | 30 entradas globales o 3 de amigos, más puntuación propia si existe |
| Scores sintéticos | `index * 100 + int(period) * 10`; los periodos varían datos, no simulan un calendario |
| Score propio | Conserva mejor valor según higher_is_better; sin historial por periodo |
| Empates | Comparten rank |
| Partidas | Bytes copiados por cuenta/slot en memoria, sin persistencia |
| Conflictos | Dos metadatos sintéticos, resolución con bytes aportados y token de un uso |
| UI | Marca presentación hasta simular cierre; sin ventana del proveedor |
| Verificación | Evidencia marcada como simulada y rechazada por el HTTP incluido |

Los datos desaparecen al reiniciar el adaptador/proceso. Cambiar de cuenta conserva los diccionarios de cada ID mientras esa instancia exista. No equipares “aceptado en memoria” con “sincronizado”.

## Controles de prueba

Obtén el adaptador con `get_simulator()`; en proveedor real devuelve null. No llames a sus métodos base internos `setup/execute/shutdown` para el uso normal; utiliza la fachada.

| Control GEXMockAdapter | Efecto |
|---|---|
| `next_error: String = ""` | Próxima operación que llegue a ejecutarse devuelve ese código mediante GEXResult.fail y lo consume |
| `drop_next_reply: bool = false` | Pierde la siguiente respuesta, fuerza espera hasta timeout y vuelve a false |
| `switch_account(id: String)` | Cambia cuenta y emite observación; vacío representa sin autenticar |
| `simulate_conflict(slot: String) -> GEXTypes.SaveConflict` | Crea/retiene conflicto y emite señal |
| `simulate_presentation(value: bool)` | Cambia presentación; el observador común la detecta en el siguiente sondeo |
| `authenticated`, `player_id` | Estado interno observable para diagnóstico; usa switch_account para cambiar cuenta con las señales correctas |

`mock_latency_seconds` añade demora por operación y `timeout_seconds` controla la espera. No programes un timeout largo si buscas una prueba rápida. Un error de validación previo a la cola no consume `next_error` ni `drop_next_reply`.

```gdscript
func probar_error_de_lectura() -> void:
    var simulator := GameServices.get_simulator()
    if simulator == null:
        return
    simulator.next_error = "NETWORK_UNAVAILABLE"
    var result := await GameServices.list_saved_games()
    print("Resultado simulado: ", result.error_code)

func probar_timeout_de_lectura() -> void:
    var simulator := GameServices.get_simulator()
    if simulator == null:
        return
    simulator.drop_next_reply = true
    var result := await GameServices.get_player()
    print("Timeout simulado: ", result.error_code)

func cambiar_cuenta_de_prueba() -> void:
    var simulator := GameServices.get_simulator()
    if simulator == null:
        return
    simulator.switch_account("segundo-jugador")
    var refreshed := await GameServices.refresh_auth_state()
    print("Nueva sesión observada: ", refreshed.is_ok())

func provocar_conflicto_y_cerrar_overlay() -> void:
    var simulator := GameServices.get_simulator()
    if simulator == null:
        return
    simulator.simulate_conflict("principal")
    simulator.simulate_presentation(false)
```

Los ejemplos presuponen servicio inicializado/autenticado donde corresponda. Para un escenario determinista, no ejecutes otras operaciones mientras preparas el “siguiente” error.

El mock no reproduce todas las ambigüedades PGS. En particular su timeout de execute marca como mutaciones inciertas guardar/enviar score; otros tipos de operación pueden tener diferencias con los adaptadores reales. La cancelación global de la fachada aplica su propia política de mutaciones. Para probar la interpretación genérica de UNKNOWN usa los casos del contrato y las [pruebas nativas](validation.md), no una equivalencia absoluta del simulador.

## Laboratorio incluido en el repositorio

La escena `demo/service_lab.tscn` pertenece al proyecto de desarrollo completo; **no va dentro del ZIP del addon**. Abre el proyecto de desarrollo y ejecuta F5, o abre esa escena y usa F6.

Siempre inicia su propia simulación con timeout de 2 segundos y pausa de SceneTree administrada. Usa claves `first_win` (incremental, 10 pasos) y `high_score`. La barra permite **Reiniciar simulador**, **Usar configuración del proyecto**, **Capacidades** y activar/desactivar registro de interrupciones.

| Grupo de botones | Acciones |
|---|---|
| Sesión | Autenticar, actualizar sesión, leer perfil |
| Amigos | Consultar sin pedir permiso o permitir solicitud |
| Logros | Definiciones, progreso actual, desbloqueo, enviar 50% |
| Rankings | Listar, enviar 12345, score propio, top 10, cercanos |
| Partidas | Guardar/cargar/listar/eliminar slot de demo |
| UI | Logros, rankings, ranking individual, overlay |
| Identidad | Invocar verificación en backend configurado |
| Fallos y conflictos | Simular conflicto, resolver con bytes demo, perder próxima respuesta |
| Interrupciones | Cerrar overlay simulado, activar token de pausa manual |

El slot utilizado es `game_extrakit_demo`. Guardar usa bytes `[0,128,255]`; resolver usa `[1,2,3]`, por lo que la comprobación de igualdad con el guardado original no coincidirá tras esa resolución. No uses esa resolución de ejemplo para una partida real.

“Usar configuración del proyecto” carga el Resource seleccionado y reutiliza el autoload si existe; toma las primeras claves de catálogo para sus botones. Un autoload ya inicializado conserva su configuración de arranque: si cambiaste el Resource, reinicia la ejecución para aplicarlo.

Los botones de simulación no actúan sobre proveedores reales. En modo real las acciones de guardar, borrar, logros y puntuaciones sí llaman al servicio; utiliza cuentas, IDs y datos de prueba. El log muestra IDs de solicitud, operación, estados, errores, capacidades y motivos; no imprime pruebas, perfiles completos ni bytes.

## Escenarios sugeridos

1. Autenticar → guardar → cargar → comprobar igualdad.
2. Enviar score → top/cercanos → cambiar cuenta → refrescar y comprobar aislamiento.
3. Abrir overlay mock → adquirir token manual → cerrar overlay → comprobar que la pausa manual continúa.
4. Simular conflicto → resolver una vez → repetir token y observar CONFLICT_EXPIRED.
5. Perder respuesta de lectura → esperar TIMEOUT → comprobar tu UI de recuperación.
6. Desactivar un módulo → reiniciar con el Resource → comprobar FEATURE_DISABLED.
7. Pasar a configuración real y ejecutar la [matriz de aceptación](validation.md).

No se han añadido escenarios de SDKs externos ni una imitación de Sidekick. [Limitaciones por plataforma](coverage.md).

