@tool
extends RefCounted
## Local evidence only. Never claims remote credentials, entitlements or testers are valid.

static func diagnose(config: GEXConfig) -> PackedStringArray:
	var lines: PackedStringArray = []
	if config == null:
		return ["Crea o carga una configuración."]
	var issues := config.validate()
	if issues.is_empty():
		lines.append("Configuración local: válida (esquema 1 / contrato 0.1).")
	else:
		for issue in issues:
			lines.append("ERROR: " + issue)
	lines.append("Motor: " + str(Engine.get_version_info().get("string", "desconocido")))
	if config.mock_enabled:
		lines.append("SIMULACIÓN explícita. Datos en memoria; no usa servicios de producción.")
	if config.android_enabled:
		var installed := FileAccess.file_exists("res://addons/GodotPlayGameServices/plugin.cfg")
		lines.append("PGS addon: " + ("descriptor presente" if installed else "AUSENTE"))
		lines.append("Referencia esperada: PGS 3.4.0 / e38b61857857. Binario no verificado aquí.")
		if installed:
			var descriptor := ConfigFile.new()
			if descriptor.load("res://addons/GodotPlayGameServices/plugin.cfg") == OK:
				lines.append("Versión declarada por descriptor: " + str(
					descriptor.get_value("plugin", "version", "sin versión")))
		for build in ["debug", "release"]:
			var path := "res://addons/GodotPlayGameServices/bin/%s/GodotPlayGameServices-%s.aar" % [build, build]
			lines.append("AAR %s: %s" % [build, "presente" if FileAccess.file_exists(path) else "AUSENTE"])
		lines.append("Android: guardado UNKNOWN; resolver conflictos y controlar Sidekick UNSUPPORTED.")
		lines.append("Sidekick: probar foco/suspensión en instalación de Play; no hay señal de visibilidad.")
	if config.apple_enabled:
		lines.append("GameCenterManager registrado: " + str(ClassDB.class_exists("GameCenterManager")))
		lines.append("Un stub en Windows no prueba disponibilidad en iOS.")
		lines.append("Apple esperado: a2ae65df061c. Verificar GameCenter + SwiftGodotRuntime en iOS.")
		lines.append("iOS >= 17; destinos de acceso específicos >=18 y Activities/Challenges >=26.")
		lines.append("Game Center e iCloud requieren comprobación en Xcode y dispositivo.")
	_validate_presets(config, lines)
	lines.append("Firma, testers, permisos remotos y cuentas: comprobación manual pendiente.")
	lines.append("Sin descarga automática; no se agregan AAR/frameworks ni SDK de Sidekick.")
	return lines

static func _validate_presets(config: GEXConfig, lines: PackedStringArray) -> void:
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		if config.android_enabled or config.apple_enabled:
			lines.append("PENDIENTE: crear presets de exportación Android/iOS.")
		return
	var found_android := false
	var found_ios := false
	for section in presets.get_sections():
		if section.ends_with(".options"):
			continue
		var platform: String = presets.get_value(section, "platform", "")
		var options := section + ".options"
		if platform == "Android" and config.android_enabled:
			found_android = true
			var id: String = presets.get_value(options, "godot_play_game_services/game_id", "")
			lines.append("PGS Game ID (única fuente: preset): " + (id if not id.is_empty() else "FALTA"))
			if not bool(presets.get_value(options, "gradle_build/use_gradle_build", false)):
				lines.append("ERROR: Android requiere Gradle Build para el exportador PGS.")
			lines.append("Paquete Android: " + str(presets.get_value(options, "package/unique_name", "FALTA")))
		if platform == "iOS" and config.apple_enabled:
			found_ios = true
			var bundle: String = presets.get_value(options, "application/bundle_identifier", "")
			if bundle != config.apple_bundle_id:
				lines.append("ERROR: Bundle ID del preset iOS no coincide con la configuración.")
	if config.android_enabled and not found_android:
		lines.append("PENDIENTE: preset Android.")
	if config.apple_enabled and not found_ios:
		lines.append("PENDIENTE: preset iOS.")
