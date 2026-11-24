class_name AIStatusPanel
extends PanelContainer
## KI-Panel (Taste K): Einstellungen und Zustand der Ollama-Anbindung.
## Zeigt deutlich, ob Antworten ECHT (Ollama) oder SIMULIERT (Testdienst) sind.
## Bedienung: ein/aus, Adresse, Modellwahl aus den INSTALLIERTEN Modellen, Verbindung testen, speichern.
## Das Panel lädt, löscht, startet oder stoppt keine Modelle und keinen Dienst.

var service: AIService
var ai: AISystem
var _mode: Label
var _status: Label
var _enabled: CheckBox
var _url: LineEdit
var _model: OptionButton
var _diag: CheckBox
var _mock: CheckBox
var _stats: RichTextLabel
var _log: RichTextLabel
var _msg: Label
var _models_sig: String = ""


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.12, 0.95)
	sb.border_color = Color(0.4, 0.85, 0.9)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(470, 0)
	var v := VBoxContainer.new()
	add_child(v)
	Nav.label(v, "KI-ANBINDUNG (Ollama) – Vorschläge für einzelne Wesen, keine Befehle", 14).modulate = Color(0.6, 0.95, 1.0)
	_mode = Nav.label(v, "", 15)
	_status = Nav.label(v, "", 12)
	_enabled = CheckBox.new()
	_enabled.text = "KI-Anbindung einschalten (ohne: Welt läuft vollständig lokal)"
	_enabled.focus_mode = Control.FOCUS_NONE
	v.add_child(_enabled)
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	Nav.label(r1, "Adresse:", 12, false)
	_url = LineEdit.new()
	_url.custom_minimum_size = Vector2(260, 0)
	_url.tooltip_text = "Nur lokale Adressen (127.0.0.1/localhost), außer allow_remote ist in user://ai_settings.json ausdrücklich gesetzt."
	r1.add_child(_url)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	Nav.label(r2, "Modell:", 12, false)
	_model = OptionButton.new()
	_model.custom_minimum_size = Vector2(260, 0)
	_model.focus_mode = Control.FOCUS_NONE
	r2.add_child(_model)
	var r3 := HBoxContainer.new()
	v.add_child(r3)
	Nav.button(r3, "Verbindung testen", _on_test)
	Nav.button(r3, "Übernehmen + speichern", _on_save)
	_diag = CheckBox.new()
	_diag.text = "Diagnosemodus (volle Kontexte/Rohantworten im Protokoll)"
	_diag.focus_mode = Control.FOCUS_NONE
	v.add_child(_diag)
	_mock = CheckBox.new()
	_mock.text = "ENTWICKLUNG: simulierter Testdienst statt Ollama"
	_mock.focus_mode = Control.FOCUS_NONE
	_mock.modulate = Color(1, 0.75, 0.5)
	v.add_child(_mock)
	_msg = Nav.label(v, "", 12)
	_msg.modulate = Color(1, 0.95, 0.7)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.custom_minimum_size = Vector2(450, 0)
	_stats.add_theme_font_size_override("normal_font_size", 11)
	v.add_child(_stats)
	Nav.label(v, "Protokoll (begrenzt):", 12)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(450, 170)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 10)
	v.add_child(_log)
	load_fields()


func load_fields() -> void:
	if service == null:
		return
	_enabled.set_pressed_no_signal(service.settings.enabled())
	_url.text = str(service.settings.g("base_url", ""))
	_diag.set_pressed_no_signal(bool(service.settings.g("diagnostic_mode", false)))
	_mock.set_pressed_no_signal(service.settings.use_mock())
	_fill_models()


func _fill_models() -> void:
	var names: Array = service.models.map(func(m): return str(m["name"]))
	var cur := str(service.settings.g("model", ""))
	var sig := ",".join(names) + "|" + cur
	if sig == _models_sig:
		return
	_models_sig = sig
	_model.clear()
	_model.add_item("– kein Modell gewählt –")
	_model.set_item_metadata(0, "")
	var sel := 0
	for m in service.models:
		var label := "%s (%s, %s, %.1f GB)" % [m["name"], m["parameter_size"], m["quantization"], float(m["size"]) / 1e9]
		_model.add_item(label)
		_model.set_item_metadata(_model.item_count - 1, str(m["name"]))
		if service.model_installed(cur) and (str(m["name"]) == cur or str(m["name"]) == cur + ":latest"):
			sel = _model.item_count - 1
	if cur != "" and sel == 0:
		_model.add_item("%s (NICHT installiert)" % cur)
		_model.set_item_metadata(_model.item_count - 1, cur)
		sel = _model.item_count - 1
	_model.select(sel)


func _apply_fields() -> bool:
	var s := service.settings
	s.set_value("enabled", _enabled.button_pressed)
	s.set_value("base_url", _url.text.strip_edges())
	s.set_value("diagnostic_mode", _diag.button_pressed)
	s.set_value("use_mock", _mock.button_pressed)
	if _model.selected >= 0:
		s.set_value("model", str(_model.get_item_metadata(_model.selected)))
	var ep := s.endpoint()
	if not ep["ok"] and not s.use_mock():
		_msg.text = "Adresse ungültig: " + str(ep["message"])
		return false
	service.reconfigure()
	_models_sig = ""
	return true


func _on_test() -> void:
	if _apply_fields():
		service.test_connection()
		_msg.text = "Prüfe Verbindung (Version, installierte Modelle) …"


func _on_save() -> void:
	if not _apply_fields():
		return
	var r := service.settings.save_user()
	service.test_connection()
	_msg.text = str(r["message"])


func refresh() -> void:
	if service == null:
		return
	if service.simulated():
		_mode.text = "SIMULIERT – Testdienst, KEINE Verbindung zu Ollama"
		_mode.modulate = Color(1, 0.6, 0.3)
	elif service.settings.enabled():
		_mode.text = "ECHT – Ollama unter %s" % service.client.describe()
		_mode.modulate = Color(0.6, 1, 0.6)
	else:
		_mode.text = "AUS – Welt läuft lokal"
		_mode.modulate = Color(0.8, 0.8, 0.8)
	_status.text = "Zustand: %s%s" % [service.status_text(), ("\n" + service.status_message) if service.status_message != "" else ""]
	_fill_models()
	var st := service.stats
	var q := ai.queue if ai != null else null
	var L: Array = []
	L.append("[b]Warteschlange[/b] %d / %d · laufend %d (höchstens %d) · Rate %d / min" % [q.size() if q else 0, int(service.settings.g("max_queue", 16)),
		service.routes.size(), int(service.settings.g("max_concurrent", 1)), int(service.settings.g("global_rate_per_min", 8))])
	L.append("[b]Gesendet[/b] %d · Antworten %d · angenommen %d · abgelehnt %d · Wiederholungen %d" % [int(st["sent"]), int(st["answers"]), int(st["accepted"]), int(st["rejected"]), int(st["retries"])])
	L.append("[b]Antwortzeit[/b] Ø %.1f s · letzte %.1f s · max %.1f s" % [service.avg_latency_ms() / 1000.0, int(st["latency_last_ms"]) / 1000.0, int(st["latency_max_ms"]) / 1000.0])
	L.append("[b]Fehlerquote[/b] %.0f %% · Transportfehler %d · Inhaltsfehler %d · veraltete Antworten verworfen %d · Wiederherstellungen %d" % [service.error_rate() * 100, int(st["transport_errors"]),
		int(st["content_errors"]), int(st["discarded_stale"]), service.recoveries])
	if not st["by_stage"].is_empty():
		var sp: Array = []
		for k in st["by_stage"]:
			sp.append("Stufe %s (%s): %d" % [k, ResponseValidator.STAGES.get(int(k), "Abgleich"), int(st["by_stage"][k])])
		L.append("Ablehnungen nach Prüfstufe: " + ", ".join(sp))
	if not service.loaded_models.is_empty():
		L.append("Geladen (api/ps): " + ", ".join(service.loaded_models.map(func(m): return "%s (%.1f GB VRAM)" % [m["name"], float(m["size_vram"]) / 1e9])))
	if ai != null:
		L.append("Diese Welt: Anlässe %s · gesendet %d · angenommen %d · abgelehnt %d · verworfen %d · fehlgeschlagen %d" % [str(ai.local["by_trigger"]), int(ai.local["dispatched"]),
			int(ai.local["accepted"]), int(ai.local["rejected"]), int(ai.local["discarded"]), int(ai.local["failed"])])
	_stats.text = "\n".join(L)
	var lines: Array = []
	for e in service.log.slice(maxi(0, service.log.size() - 14)):
		var col: String = {"error": "#f88", "warn": "#fc6", "diag": "#9cf"}.get(str(e["level"]), "#ccc")
		lines.append("[color=%s]%s%s[/color]" % [col, "(SIMULIERT) " if e.get("simulated", false) else "", OllamaClient.sanitize(str(e["text"]), 600)])
	_log.text = "\n".join(lines)
