# Partidas guardadas y conflictos

[Manual](README.md) · [API de partidas](api.md#partidas) · [Resultados](results.md) · [Ciclo de vida](lifecycle.md)

GameExtrakit guarda **bytes opacos** por slot y cuenta del proveedor. El juego controla formato, versiones de datos, cifrado si lo necesita, copia local, elección entre versiones y recuperación. No hay sincronización Android↔iOS, fusión automática, cola offline persistente ni backup integrado.

## Slots, tamaño y metadatos

| Elemento | Regla |
|---|---|
| Slot lógico | 1–100 caracteres ASCII `[A-Za-z0-9._~-]`; sin barras ni espacios |
| Nombre remoto | `slot_prefix + slot`; también debe cumplir el límite de 100 |
| Presupuesto | `max_save_bytes`, 1 MiB por defecto, configurable entre 1 byte y 3 MiB |
| Contenido vacío | Permitido; no se confunde con partida ausente |
| description | Hasta 500 bytes UTF-8; no 500 caracteres necesariamente |
| played_msec | Entero no negativo, tiempo jugado en milisegundos |
| progress_value | Entero no negativo, metadato de progreso PGS |
| Prefijo | Solo selecciona nombres remotos; no ofrece aislamiento criptográfico |

El presupuesto es una regla local de la aplicación, no una garantía de cuota Apple ni de red. Descripción, tiempo y progreso se envían a PGS; Apple guarda contenido y nombre, sin equivalentes para esos argumentos. Los datos recibidos desde el proveedor también deben validarse antes de aplicarlos al juego.

## Guardar y conservar copia local

El siguiente ejemplo usa JSON UTF-8 como elección del juego, no como formato del addon. La función devuelve el resultado remoto; si falla el respaldo local se detiene antes de enviarlo.

```gdscript
func guardar_partida(nivel: int, monedas: int) -> GEXResult:
    var payload := {
        "schema": 1,
        "nivel": nivel,
        "monedas": monedas
    }
    var data := JSON.stringify(payload).to_utf8_buffer()
    var local_file := FileAccess.open("user://partida-respaldo.json", FileAccess.WRITE)
    if local_file == null:
        return GEXResult.fail("LOCAL_BACKUP_FAILED", "No se pudo guardar el respaldo.")
    local_file.store_buffer(data)
    local_file.flush()
    var local_error := local_file.get_error()
    local_file.close()
    if local_error != OK:
        return GEXResult.fail("LOCAL_BACKUP_FAILED", "Error al escribir el respaldo.")

    var result := await GameServices.save_game("principal", data, "Partida principal", 0, nivel)
    if result.status == GEXTypes.Status.UNKNOWN:
        print("Conservar respaldo: escritura remota sin confirmar.")
    elif result.is_ok():
        print("Aceptación: ", GEXTypes.Delivery.keys()[result.delivery])
    else:
        push_warning("Guardado: " + result.error_code)
    return result
```

`LOCAL_BACKUP_FAILED` es un código del ejemplo, no del runtime del addon. La escritura local ilustrativa sobrescribe un archivo; para producción diseña rotación, reemplazo seguro y migración propios. JSON puede perder precisión para números grandes al decodificar: representa como cadenas los int64 que necesiten exactitud o usa otro formato.

### Qué confirma cada plataforma

| Proveedor | Respuesta de guardado |
|---|---|
| Android PGS | UNKNOWN / SAVE_COMPLETION_UNVERIFIABLE y delivery UNKNOWN; el binding emite gameSaved antes de observar el commit |
| Apple | Callback satisfactorio: OK / PROVIDER_ACCEPTED, con metadatos disponibles |
| Mock | OK / PROVIDER_ACCEPTED: aceptación en memoria, sin servidor ni disco |

Ninguno declara SYNC_CONFIRMED. No borres el respaldo al recibir OK ni reenvíes automáticamente un guardado UNKNOWN. Una mutación que agotó el timeout o fue cancelada localmente puede seguir ejecutándose en el SDK.

## Cargar y validar

`load_game()` no crea un slot ausente. El juego decide si ofrecer “Nueva partida”, usar copia local o resolver un conflicto; no trata todos los errores como ausencia.

```gdscript
func leer_partida() -> Dictionary:
    var result := await GameServices.load_game("principal")
    if result.error_code == "SAVE_NOT_FOUND":
        print("No existe este slot; decide si iniciar una partida.")
        return {}
    if result.error_code == "CONFLICT_PENDING":
        print("Esperar la elección explícita del conflicto.")
        return {}
    if not result.is_ok():
        push_warning("Carga: " + result.error_code)
        return {}

    var parsed: Variant = JSON.parse_string(result.bytes.get_string_from_utf8())
    if not parsed is Dictionary:
        push_warning("Formato de partida no reconocido.")
        return {}
    if parsed.get("schema") != 1 or not parsed.has_all(["nivel", "monedas"]):
        push_warning("Se necesita validar o migrar este esquema.")
        return {}
    # Antes de aplicar: valida tipos, rangos y reglas propias del juego.
    return parsed
```

El `{}` del ejemplo solo indica “no aplicar datos”; un juego real debería conservar una razón diferenciada. En Android los bytes Java con signo se normalizan al intervalo 0–255. En Apple varias versiones con el mismo nombre generan conflicto en vez de elegir una arbitrariamente.

## Enumerar, refrescar y eliminar

```gdscript
func enumerar_partidas() -> void:
    var result := await GameServices.list_saved_games(true)
    if not result.is_ok():
        push_warning("Listado: " + result.error_code)
        return
    for metadata in result.saves:
        print("Slot: ", metadata.slot)
        if metadata.pending_sync_known:
            print("Sincronización pendiente informada: ", metadata.pending_sync)

# Invocar únicamente después de la decisión de borrado en la UI del juego.
func eliminar_partida_elegida(slot: String) -> GEXResult:
    return await GameServices.delete_saved_game(slot)
```

La lista filtra por prefijo y devuelve slots lógicos. Una lista vacía válida no es error. `force_refresh` se traslada a PGS; Apple no tiene equivalente. El evento `saved_game_modified` de Apple trae metadatos: requiere una carga explícita para obtener nuevos bytes.

Android busca el snapshot por nombre y elimina por ID; si no existe, SAVE_NOT_FOUND. Apple elimina **todas** las versiones del nombre. No hay papelera/deshacer universal y una cancelación local no garantiza que el borrado remoto se haya detenido.

## Conflictos

Conecta `save_conflict_detected` antes de operar. La señal devuelve token, slot, proveedor, generación y metadatos de versiones.

| Aspecto | Android | Apple | Mock |
|---|---|---|---|
| Detección | Evento del binding | Evento nativo o duplicados al cargar | Control explícito |
| Resolución manual | UNSUPPORTED_OPERATION | Callback nativo con handles retenidos internamente | Sustitución en memoria |
| Datos de versiones expuestos | Metadatos | Metadatos | Metadatos sintéticos |
| Validez del token | Sesión actual, sin resolver por esta API | Sesión actual; consumido al resolver con éxito | Sesión actual; un solo uso |

La API actual **no tiene un método para leer por separado los bytes de cada versión conflictiva**. No se puede construir una fusión arbitraria únicamente a partir de `versions`. El juego puede aportar una copia local conocida o bytes producidos por su propia estrategia.

```gdscript
var conflicto_pendiente: GEXTypes.SaveConflict

func conectar_conflictos() -> void:
    GameServices.save_conflict_detected.connect(_on_save_conflict)
    GameServices.player_changed.connect(_on_conflict_player_changed)

func _on_save_conflict(conflict: GEXTypes.SaveConflict) -> void:
    conflicto_pendiente = conflict
    print("Versiones detectadas: ", conflict.versions.size())
    # Presenta una decisión al jugador; no resuelvas automáticamente aquí.

func _on_conflict_player_changed(_player: GEXTypes.PlayerProfile) -> void:
    conflicto_pendiente = null

func resolver_con_bytes_elegidos(data: PackedByteArray) -> GEXResult:
    if conflicto_pendiente == null:
        return GEXResult.fail("CONFLICT_EXPIRED")
    if not GameServices.get_capabilities().can_resolve_save_conflicts:
        return GEXResult.fail("UNSUPPORTED_OPERATION")
    var result := await GameServices.resolve_save_conflict(conflicto_pendiente.token, data)
    if result.is_ok() or result.error_code in ["CONFLICT_EXPIRED", "SESSION_CHANGED"]:
        conflicto_pendiente = null
    return result
```

Cambiar cuenta, llamar a `cancel_pending_requests()` o cerrar invalida tokens. Descarta también tu referencia local al cancelar manualmente. No persistas tokens para reusarlos en otro arranque. Ante UNKNOWN conserva el respaldo y reconcilia el estado antes de decidir otra mutación; no supongas que el token remoto sigue siendo útil.

## Reanudación y comprobación real

Autenticación Game Center e iCloud son condiciones diferentes. Prueba dispositivo sin iCloud, offline, cierre de proceso, dos dispositivos con el mismo slot, payload cercano al presupuesto y cambios de cuenta. El mock no reproduce esas condiciones nativas.

[Configuración de iCloud/PGS](platforms.md) · [Pruebas de aceptación](validation.md) · [Errores y recuperación](troubleshooting.md).

