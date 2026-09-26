# Diagnóstico y solución de problemas

[Manual](README.md) · [Configuración](configuration.md) · [Resultados](results.md) · [Validación](validation.md)

## Orden de comprobación

1. Confirma versión Godot, plugin activo, autoload correcto y Resource guardado/seleccionado.
2. Ejecuta **Actualizar diagnóstico** y corrige los errores locales.
3. Comprueba `get_provider()`, `get_capabilities().available`, módulos y estado de auth.
4. Registra `status` y `error_code` del resultado; interpreta también delivery/completitud.
5. En móvil, revisa dependencias, preset, firma/cuenta y permisos según [Plataformas](platforms.md).
6. Reproduce con una sola operación y un slot/catálogo de prueba; evita reintentos de mutaciones inciertas.

El diagnóstico local comprueba Resource, motor, descriptores/AAR esperados y presets. No demuestra que las credenciales, testers, permisos remotos, binarios o entitlements funcionen.

## Códigos del runtime

El estado depende del contexto: una mutación con TIMEOUT o SESSION_CHANGED puede ser UNKNOWN. Consulta [GEXResult](results.md), no clasifiques solo por el nombre del código.

| Código | Causa/interpretación | Acción |
|---|---|---|
| `NOT_INITIALIZED` | Fachada sin preparar, fuera del árbol o cerrada | Guardar/seleccionar Resource; revisar resultado de initialize en instancia manual |
| `INVALID_CONFIGURATION` | Resource inválido, clave inexistente, catálogo PGS discordante, ID OAuth ausente o intento de reiniciar instancia cerrada | Leer message y diagnóstico; corregir Resource y crear nuevo ciclo |
| `INVALID_ARGUMENT` | Progreso, consulta, slot, tamaño, metadatos, ubicación o token inválidos | Comparar con límites de API; corregir antes de reenviar |
| `FEATURE_DISABLED` | Proveedor o módulo desactivado | Habilitar intencionadamente en Resource y reiniciar |
| `DEPENDENCY_MISSING` | Singleton/clase/runtime nativo requerido ausente | Instalar versión oficial fijada y revisar exportador, arquitectura y ruta |
| `UNSUPPORTED_PLATFORM` | Escritorio sin mock o iOS no reconocido/menor que 17 | Activar mock para desarrollo o usar plataforma compatible |
| `UNSUPPORTED_OPERATION` | Operación/destino no expuesto o progreso parcial en logro PGS normal | Consultar capacidades y usar una alternativa soportada |
| `NOT_AUTHENTICATED` | La fachada/proveedor no tiene sesión observada | Autenticar o refrescar, antes de leer datos de cuenta |
| `AUTHENTICATION_FAILED` | Autenticación terminó sin sesión nativa válida | Revisar cuenta, firma y configuración; ofrecer acción del usuario, sin bucle |
| `PERMISSION_REQUIRED` | Amigos Apple sin permiso decidido y ask_permission=false | Mostrar explicación y botón que permita solicitarlo |
| `PERMISSION_DENIED` | Acceso denegado/restringido | Mantener función indisponible; no repetir prompts automáticamente |
| `USER_CANCELLED` | Cancelación nativa mapeada, principalmente Apple | Respetar la decisión; status FAILED en el mapeo actual |
| `NETWORK_UNAVAILABLE` | Fallo de transporte HTTP incluido o código inyectado en simulación | Recuperar conectividad; no implica que todo error nativo de red se mapee así |
| `TIMEOUT` | Espera nativa agotada o error nativo equivalente | Diferenciar lectura/mutación; considerar respuesta tardía/canal ocupado |
| `CANCELLED` | Cancelación explícita local | No mostrar como éxito; no supone deshacer una escritura remota |
| `SESSION_CHANGED` | Resultado invalidado al cambiar generación/cuenta | Retirar datos viejos, refrescar y descartar tokens/conflictos previos |
| `REQUEST_CHANNEL_BUSY` | Singleton ya ocupado, canal Android pendiente/retirado, auth Apple pendiente o UI superpuesta | Reutilizar propietario y esperar la respuesta/cierre original; en canales Android retirados reiniciar proceso |
| `PROVIDER_ERROR` | Fallo nativo conocido o respuesta malformada | Revisar native_code y logs sin payload; contrastar dependencia fijada |
| `AMBIGUOUS_NATIVE_RESULT` | PGS devuelve vacío/null o false sin poder distinguir todos los resultados | Mostrar estado desconocido; no tratarlo automáticamente como cero/vacío/fallo reintentable |
| `SAVE_COMPLETION_UNVERIFIABLE` | Señal PGS de guardado anterior a confirmación del commit | Conservar copia local y reconciliar; no prometer sincronización |
| `SAVE_NOT_FOUND` | Slot ausente en una carga o búsqueda de borrado | Ofrecer partida nueva/copia local según política; cargar no crea el slot |
| `CONFLICT_PENDING` | Operación interrumpida por versiones conflictivas | Atender save_conflict_detected; Android no dispone de resolución manual |
| `CONFLICT_EXPIRED` | Token desconocido, consumido o de generación anterior | Descartarlo; obtener un conflicto vigente antes de otra decisión |
| `BACKEND_NOT_CONFIGURED` | Sin verificador válido/endpoint o implementación base | Configurar cliente HTTP o verificador propio |
| `IDENTITY_VERIFICATION_FAILED` | Prueba mock/no admitida, HTTP rechazado o respuesta inválida | Revisar protocolo/servidor; no aceptar el perfil como sustituto |
| `UI_PRESENTATION_UNOBSERVABLE` | Pantalla PGS despachada sin API de observación | Separar intención de estado real; usar solo interrupciones genéricas observables |
| `UI_DISPATCHED` | Fallback del ranking Apple iOS 17 sin callback expuesto | No asumir que terminó la presentación al volver el método |

Los mensajes no se traducen automáticamente; el juego debe presentar textos adecuados a sus usuarios según códigos. El simulador puede inyectar códigos arbitrarios y un verificador propio puede definir otros; los códigos propios de ejemplos no amplían la lista del runtime.

## Síntomas frecuentes

| Síntoma | Revisar |
|---|---|
| No aparece el dock | Plugin activo, errores de importación, script del descriptor; no mover solo una parte de la carpeta |
| GameServices apunta a otro script | Colisión de autoload; el plugin preserva el existente |
| Resource “válido” pero no funciona móvil | Diagnóstico local no comprueba consolas, firma, testers, entitlements ni contenido de binarios |
| Sigue usando MOCK en el teléfono | mock_enabled tiene prioridad sobre Android/Apple |
| Release no inicializa | Simulación bloqueada salvo allow_mock_in_release; corregir configuración antes de distribuir |
| Cambié un campo y runtime sigue igual | Configuración duplicada al inicializar; guardar y reiniciar ejecución |
| Mock exige IDs Android/Apple | Hay proveedores reales habilitados; la validación de sus catálogos sigue activa |
| API devuelve clave desconocida | Usaste ID remoto en vez de key, o no guardaste el catálogo |
| Logro incremental falla por metadatos | Tipo/total_steps locales deben coincidir con PGS |
| Lista de amigos vacía es UNKNOWN | Limitación de señales PGS; no significa necesariamente “cero amigos” |
| Puntuación propia null | Comprobar status; en Apple puede ser ausencia válida, en PGS es ambigua |
| Top no empieza por rank 1 o hay empates | Usa ranks del proveedor, no índice local |
| Guardar Android nunca muestra OK | Limitación declarada del commit, no confirmación fiable de fallo |
| Cargar una partida devuelve conflicto | Apple encontró varias versiones o el binding emitió conflicto; no seleccionar por orden de lista |
| Game Center autentica pero Cloud Save falla | iCloud requiere condiciones/capacidades separadas |
| Access point se vuelve a ocultar | Refresh/get_player Apple puede reponer apple_entry_point_active del Resource |
| Botón oculto pero juego pausado | El overlay puede seguir presentado; revisar presentation y demás motivos |
| Menú no puede cerrar al pausar | Su Node debe procesar durante pausa |
| Cerré overlay y no reanuda | Queda suspensión/foco/token/pausa previa; no forzar resume |
| Se queda pausado al cerrar servicio | Se preservó pausa previa o tokens del juego; coordinar el traspaso a tu gestor |
| Sidekick no pausa | Sin señal nativa; comprobar si el dispositivo entrega eventos de aplicación |
| Varias llamadas devuelven canal ocupado | Revisar [colas, drenaje y cierre](lifecycle.md#canales-android) |
| Exportó pero no inicializa | El hook publica errores sin abortar por sí solo; revisar logs y configuración incluida |

## Registro útil

Registra versión de addon/Godot/dependencia, proveedor, operación, ID de solicitud, estado, código, native_code cuando exista, timestamps monotónicos y motivos de pausa. La demo ofrece ese registro reducido.

No registres códigos OAuth, pruebas, firmas, salt, contenido de partidas ni perfiles completos. Para un reporte de incidencia usa un catálogo/slot de prueba y pasos reproducibles, con el resultado esperado y observado. No adjuntes archivos de firma o credenciales.

Las comprobaciones headless no acreditan integración móvil. Compara el problema con la [evidencia existente](validation.md) y ejecuta únicamente las pruebas de plataforma pertinentes.

