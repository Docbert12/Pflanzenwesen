class_name LabUI
extends CanvasLayer
## Bedienoberfläche des Physiklabors (vollständig per Code aufgebaut).
## Bleibt während der Pause bedienbar.

const EVENT_TEXT := {
	"simulation_initialized": "Simulation initialisiert",
	"lab_built": "Labor aufgebaut",
	"world_reset": "Labor zurückgesetzt",
	"paused": "Pausiert",
	"resumed": "Fortgesetzt",
	"contact_created": "Wärmekontakt angelegt",
	"contact_enabled": "Wärmekontakt aktiviert",
	"contact_disabled": "Wärmekontakt deaktiviert",
	"contact_removed": "Wärmekontakt entfernt",
	"heater_on": "Heizung an",
	"heater_off": "Heizung aus",
	"heater_blocked_model_limit": "Heizung gestoppt: Modellgrenze",
	"cooling_on": "Kühlung an",
	"cooling_off": "Kühlung aus",
	"thermal_target_changed": "Heizung/Kühlung umgelenkt",
	"melting_started": "Schmelzen begonnen",
	"melting_complete": "Vollständig geschmolzen",
	"solidification_started": "Erstarren begonnen",
	"solidification_complete": "Vollständig erstarrt",
	"model_limit_exceeded": "WARNUNG Modellgrenze überschritten",
	"mechanical_load": "Laborbelastung",
	"deformed": "Verformt",
	"fractured": "Zerbrochen",
	"load_rejected": "Belastung abgewiesen",
	"sample_split": "Probe geteilt",
	"samples_merged": "Laboroperation Zusammenführen",
	"process_rejected": "Laboroperation abgewiesen",
	"fall_test_started": "Falltest gestartet",
	"fall_landed": "Aufgeschlagen",
	"object_rejected": "FEHLER Objekt abgewiesen",
	"init_error": "FEHLER Initialisierung",
	"environment_exchange_on": "Umgebungsaustausch an",
	"environment_exchange_off": "Umgebungsaustausch aus",
}

var lab: PhysicsLab
var _status: RichTextLabel
var _selection: RichTextLabel
var _events: RichTextLabel
var _station_a: Label
var _station_b: Label
var _station_c: Label
var _station_d: Label
var _message: Label
var _legend: Label
var _btn_pause: Button
var _btn_false: Button
var _btn_env: Button
var _btn_cu_st: Button
var _btn_cu_wa: Button
var _btn_heat: Button
var _btn_cool: Button
var _heat_slider: HSlider
var _heat_label: Label
var _load_slider: HSlider
var _load_label: Label
var _tests_panel: PanelContainer
var _tests_text: RichTextLabel
var _hints: Label
var _accum := 0.0


func setup(p_lab: PhysicsLab) -> void:
	lab = p_lab
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if not lab.sim.is_ready():
		_status.text = "[color=#ff6060][b]Initialisierung fehlgeschlagen:[/b][/color]\n" + "\n".join(lab.sim.init_errors)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Linke Spalte: Status, Hinweise und Steuerung in einer scrollbaren Spalte
	var left := _panel(root, Vector2.ZERO, Vector2.ZERO)
	left.anchor_left = 0.0
	left.anchor_right = 0.0
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_left = 10
	left.offset_right = 450
	left.offset_top = 10
	left.offset_bottom = -10
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cv)
	_status = _rich(cv, 0)
	_status.fit_content = true
	_hints = Label.new()
	_hints.text = "Maus: rechts ziehen = drehen · Mitte oder Umschalt+rechts = verschieben · Rad = zoomen · Linksklick = auswählen · Umschalt+Klick = Zweitauswahl\nTasten: 0 Übersicht · 1–4 Stationen · WASD/QE bewegen · Leertaste Pause · R Zurücksetzen · F Falschfarbe · C Kamera auf Auswahl · Esc Auswahl aufheben"
	_hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hints.custom_minimum_size = Vector2(410, 0)
	_hints.add_theme_font_size_override("font_size", 12)
	_hints.modulate = Color(0.8, 0.85, 0.9)
	cv.add_child(_hints)
	Nav.back_button(cv, lab)
	_header(cv, "Ansicht")
	var views := HBoxContainer.new()
	cv.add_child(views)
	_button(views, "Übersicht", func(): lab.view_station(""))
	for st in ["A", "B", "C", "D"]:
		_button(views, "Station " + st, lab.view_station.bind(st))

	_header(cv, "Allgemein")
	var row := HBoxContainer.new()
	cv.add_child(row)
	_btn_pause = _button(row, "Pause", lab.toggle_pause)
	_button(row, "Zurücksetzen", lab.reset_lab)
	_btn_false = _button(row, "Falschfarbe", lab.toggle_false_color)
	var row2 := HBoxContainer.new()
	cv.add_child(row2)
	_btn_env = _button(row2, "Umgebung", lab.toggle_environment)
	_button(row2, "Selbsttests", _run_self_tests)
	_button(row2, "Schnappschuss", func(): lab.write_snapshot())
	_legend = Label.new()
	_legend.add_theme_font_size_override("font_size", 12)
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.text = "FALSCHFARBE AKTIV – Darstellungsüberlagerung, kein Materialzustand. Skala: 273 K blau · 337 K türkis · 400 K grün · 900 K gelb · ≥1400 K rot"
	_legend.modulate = Color(1, 0.8, 0.4)
	cv.add_child(_legend)

	_header(cv, "A  Falltest")
	_button(cv, "Falltest starten", lab.start_fall_test)
	_station_a = _label(cv)

	_header(cv, "B  Wärmetest")
	var rb := HBoxContainer.new()
	cv.add_child(rb)
	_btn_cu_st = _button(rb, "Kontakt Kupfer–Stein", func(): lab.toggle_contact("Kupfer–Stein"))
	_btn_cu_wa = _button(rb, "Kontakt Kupfer–Wasser", func(): lab.toggle_contact("Kupfer–Wasser"))
	_station_b = _label(cv)

	_header(cv, "C  Kupfer-Schmelztest")
	_heat_label = _label(cv)
	_heat_slider = HSlider.new()
	_heat_slider.min_value = 0.0
	_heat_slider.max_value = float(lab.sim.settings.get("lab", {}).get("heater_power_max_w", 3000.0)) if lab.sim.is_ready() else 3000.0
	_heat_slider.step = 50.0
	_heat_slider.value = lab.heater_power_w
	_heat_slider.value_changed.connect(func(v): lab.set_heater_power(v))
	cv.add_child(_heat_slider)
	var rc := HBoxContainer.new()
	cv.add_child(rc)
	_btn_heat = _button(rc, "Heizung", lab.toggle_heater)
	_btn_cool = _button(rc, "Kühlung", lab.toggle_cooling)
	_button(rc, "Auf Auswahl richten", lab.retarget_thermal_to_selection)
	_station_c = _label(cv)

	_header(cv, "D  Masse & Bruch")
	_station_d = _label(cv)

	# Auswahl rechts
	var sel_panel := _panel(root, Vector2.ZERO, Vector2.ZERO)
	sel_panel.anchor_left = 1.0
	sel_panel.anchor_right = 1.0
	sel_panel.offset_left = -420
	sel_panel.offset_right = -10
	sel_panel.offset_top = 10
	var selv := VBoxContainer.new()
	sel_panel.add_child(selv)
	_header(selv, "Ausgewähltes Objekt")
	_selection = _rich(selv, 0)
	_selection.fit_content = true
	_selection.custom_minimum_size = Vector2(390, 0)
	_header(selv, "Laboreingriffe (Testbefehle)")
	_load_label = _label(selv)
	_load_slider = HSlider.new()
	_load_slider.min_value = 10.0
	_load_slider.max_value = float(lab.sim.settings.get("lab", {}).get("load_max_j", 2000.0)) if lab.sim.is_ready() else 2000.0
	_load_slider.step = 10.0
	_load_slider.value = lab.load_j
	_load_slider.value_changed.connect(func(v): lab.load_j = v)
	selv.add_child(_load_slider)
	_button(selv, "Belastung anwenden", lab.apply_load_to_selection)
	var rs := HBoxContainer.new()
	selv.add_child(rs)
	_button(rs, "Teilen 50/50", func(): lab.split_selection(0.5))
	_button(rs, "Teilen 30/70", func(): lab.split_selection(0.3))
	_button(selv, "Zusammenführen mit Zweitauswahl", lab.merge_selection)

	# Meldung + Ereignisse unten
	var ev_panel := _panel(root, Vector2.ZERO, Vector2.ZERO)
	ev_panel.anchor_left = 1.0
	ev_panel.anchor_right = 1.0
	ev_panel.anchor_top = 1.0
	ev_panel.anchor_bottom = 1.0
	ev_panel.offset_left = -700
	ev_panel.offset_right = -10
	ev_panel.offset_top = -245
	ev_panel.offset_bottom = -10
	var ev := VBoxContainer.new()
	ev_panel.add_child(ev)
	_message = _label(ev)
	_message.modulate = Color(0.6, 1.0, 0.6)
	_header(ev, "Letzte Ereignisse")
	_events = _rich(ev, 175)

	# Selbsttest-Ausgabe
	_tests_panel = PanelContainer.new()
	_tests_panel.anchor_left = 0.5
	_tests_panel.anchor_right = 0.5
	_tests_panel.anchor_top = 0.5
	_tests_panel.anchor_bottom = 0.5
	_tests_panel.offset_left = -450
	_tests_panel.offset_right = 450
	_tests_panel.offset_top = -300
	_tests_panel.offset_bottom = 300
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.06, 0.07, 0.09, 0.97)
	tsb.set_content_margin_all(10)
	_tests_panel.add_theme_stylebox_override("panel", tsb)
	_tests_panel.visible = false
	root.add_child(_tests_panel)
	var tv := VBoxContainer.new()
	_tests_panel.add_child(tv)
	_tests_text = _rich(tv, 540)
	_tests_text.scroll_active = true
	_button(tv, "Schließen", func(): _tests_panel.visible = false)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.1 or lab == null or not lab.sim.is_ready():
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	var sim := lab.sim
	var led := sim.thermal.ledger(sim.registry)
	_status.text = "[b]Pflanzenwesen – Physiklabor[/b]  (v%s)\nSimulationszeit: [b]%.2f s[/b]   Ticks: %d   Takt: %d Hz\nZustand: %s   Zeitfaktor: 1,0 (Beschleunigung nicht implementiert)\nTestobjekte: %d   Durchgang: %d   Startwert: %d\nUmgebung: %s, %s, h = %.1f W/(m²·K)\nEnergiebilanz: Objekte %s · Umgebung %s · Kühlung %s · Heizung −%s\n→ Bilanz %s (konstant, wenn korrekt)" % [
		ProjectSettings.get_setting("application/config/version", "?"),
		sim.clock.sim_time_s, sim.clock.tick_count, Engine.physics_ticks_per_second,
		"[color=#ffcc40]PAUSIERT[/color]" if sim.is_paused() else "[color=#80ff80]läuft[/color]",
		sim.registry.count(), sim.generation, sim.rng.seed,
		"an" if sim.thermal.environment_enabled else "AUS (geschlossen)", _fmt_t(sim.thermal.ambient_temperature_k), sim.thermal.convection_coefficient,
		_fmt_e(led["objects_j"]), _fmt_e(led["environment_j"]), _fmt_e(led["sinks_j"]), _fmt_e(led["heaters_j"]), _fmt_e(led["balance_j"]),
	]
	_btn_pause.text = "Fortsetzen" if sim.is_paused() else "Pause"
	_btn_false.text = "Falschfarbe: " + ("an" if lab.false_color else "aus")
	_btn_env.text = "Umgebung: " + ("an" if sim.thermal.environment_enabled else "aus")
	_legend.visible = lab.false_color
	_btn_cu_st.text = "Kupfer–Stein: " + ("AN" if lab.contact_enabled("Kupfer–Stein") else "aus")
	_btn_cu_wa.text = "Kupfer–Wasser: " + ("AN" if lab.contact_enabled("Kupfer–Wasser") else "aus")
	_btn_heat.text = "Heizung: " + ("AN" if lab.heater_enabled else "aus")
	_btn_cool.text = "Kühlung: " + ("AN" if lab.cooling_enabled else "aus")
	_heat_label.text = "Heizleistung: %.0f W" % lab.heater_power_w
	_load_label.text = "Belastung: %.0f J (Spielmodell, keine reale Bruchmechanik)" % lab.load_j
	_message.text = lab.last_message

	# Station A
	var a_lines: Array = ["Erwartet ohne Luftwiderstand: t = √(2h/g) = %.3f s (gleich für alle Massen)" % lab.expected_fall_time()]
	for mid in PhysicsLab.FALL_MATERIALS:
		var id: int = lab.roles.get("fall_" + mid, 0)
		var o := sim.registry.get_entity(id) as PhysicalObject
		var b: PhysicalBody = lab.bodies.get(id, null)
		if o == null or b == null:
			continue
		var res := "wartet"
		if b.fall_time_s >= 0.0:
			res = "%.3f s" % b.fall_time_s
		elif b.fall_release_time >= 0.0:
			res = "fällt …"
		a_lines.append("%-16s %6.3f kg  →  %s" % [o.material().display_name.get_slice(" (", 0), o.mass_kg, res])
	a_lines.append("Messauflösung: 1 Physiktick (%.4f s)" % (1.0 / Engine.physics_ticks_per_second))
	_station_a.text = "\n".join(a_lines)

	# Station B
	var b_lines: Array = []
	for role in ["warm", "cold", "water"]:
		var o := lab._obj(role)
		if o != null:
			b_lines.append("#%d %s: %s" % [o.id, o.label, _fmt_t(o.temperature_k())])
	for cname in lab.contact_keys:
		var key: String = lab.contact_keys[cname]
		if sim.thermal.contacts.has(key):
			var c: Dictionary = sim.thermal.contacts[key]
			b_lines.append("%s: G=%.3f W/K, Fluss %.2f W, übertragen %s" % [cname, c["conductance_w_k"], c["last_flow_w"], _fmt_e(c["transferred_j"])])
		else:
			b_lines.append("%s: entfernt" % cname)
	_station_b.text = "\n".join(b_lines)

	# Station C
	var h: Dictionary = sim.thermal.heaters.get(PhysicsLab.HEATER, {})
	var k: Dictionary = sim.thermal.sinks.get(PhysicsLab.COOLER, {})
	var c_lines: Array = []
	var target := sim.registry.get_entity(h.get("target_id", 0)) as PhysicalObject
	if target != null:
		c_lines.append("Ziel #%d %s, %.4f kg" % [target.id, target.material().display_name, target.mass_kg])
		c_lines.append("Temperatur: %s   Flüssiganteil: %.1f %%   Zustand: %s" % [_fmt_t(target.temperature_k()), target.liquid_fraction() * 100.0, _phase_de(target.phase_state())])
	else:
		c_lines.append("Kein Ziel (Probe entfernt). Probe wählen und „Auf Auswahl richten“.")
	if not h.is_empty():
		c_lines.append("Heizung: %s, aktuell %.0f W, zugeführt %s" % [h["status"], h["last_power_w"], _fmt_e(h["supplied_j"])])
	if not k.is_empty():
		c_lines.append("Kühlung (%.0f W bis %s): %s, entzogen %s" % [k["power_w"], _fmt_t(k["sink_temperature_k"]), k["status"], _fmt_e(k["absorbed_j"])])
	c_lines.append("Tiegel und Heizplatte haben im Modell keine Wärmekapazität. Strahlung nicht modelliert.")
	_station_c.text = "\n".join(c_lines)

	# Station D
	var ids := sim.ids_in_station("D")
	_station_d.text = "Gesamtmasse Station D: anfangs %.9f kg · jetzt %.9f kg · Abweichung %s kg\nObjekte: %d (Fragmente/Teile eingeschlossen)\nAuswahl anklicken → rechts Belastung, Teilen oder Zusammenführen." % [
		lab.station_d_initial_mass, sim.total_mass("D"), TestSuite.sci(sim.total_mass("D") - lab.station_d_initial_mass), ids.size()]

	_refresh_selection()
	_refresh_events()


func _refresh_selection() -> void:
	var sim := lab.sim
	var o := sim.registry.get_entity(lab.selected_id) as PhysicalObject
	if o == null:
		_selection.text = "Nichts ausgewählt. Linksklick auf eine Probe."
		return
	var m := o.material()
	var lines: Array = []
	lines.append("[b]#%d %s[/b]" % [o.id, o.label])
	lines.append("Material: %s" % m.display_name)
	lines.append("[i]%s[/i]" % m.model_material)
	lines.append("Masse: %.6f kg   (gespeichert)" % o.mass_kg)
	lines.append("Volumen: %.3f cm³   Dichte: %.1f kg/m³   (abgeleitet)" % [o.volume_m3() * 1e6, m.density])
	lines.append("Temperatur: %s   (abgeleitet)" % _fmt_t(o.temperature_k()))
	lines.append("Thermische Energie: %s   (gespeichert, Bezug: Festkörper bei 0 K)" % _fmt_e(o.thermal_energy_j))
	if m.has_melting():
		lines.append("Schmelzpunkt %s · Flüssiganteil %.2f %% · %s" % [_fmt_t(m.melting_point), o.liquid_fraction() * 100.0, _phase_de(o.phase_state())])
	else:
		lines.append("Phasenmodell: nur fest (Schmelzpunkt nicht anwendbar)")
	lines.append("Modellbereich: %.1f – %.1f K%s" % [m.valid_min_k, m.valid_max_k, "   [color=#ff8080]ÜBERSCHRITTEN[/color]" if sim.phases.is_outside_model(o.id) else ""])
	lines.append("Schaden (Spielmodell): %.0f %%%s" % [o.damage * 100.0, " · verformt" if o.deformed else ""])
	lines.append("Bruchverhalten: %s · Brennbar: %s (Verbrennung nicht simuliert)" % [m.fracture_behavior, "ja" if m.combustible else "nein"])
	lines.append("Herkunft: %s %s" % [o.origin, ("von " + str(o.parent_ids)) if not o.parent_ids.is_empty() else ""])
	var b: PhysicalBody = lab.bodies.get(o.id, null)
	if b != null:
		lines.append("Position: (%.2f, %.2f, %.2f) m · v = %.2f m/s%s" % [b.global_position.x, b.global_position.y, b.global_position.z, b.linear_velocity.length(), " · im Behälter" if b.contained else ""])
	var sec := sim.registry.get_entity(lab.secondary_id) as PhysicalObject
	if sec != null:
		lines.append("[color=#60e0ff]Zweitauswahl: #%d %s (%s)[/color]" % [sec.id, sec.label, sec.material().display_name])
	_selection.text = "\n".join(lines)


func _refresh_events() -> void:
	var lines: Array = []
	var recent := lab.sim.event_log.recent(9)
	recent.reverse()
	for e in recent:
		var txt: String = EVENT_TEXT.get(e["type"], e["type"])
		var col := "#ffffff"
		if e["severity"] == "warning":
			col = "#ffcc60"
		elif e["severity"] == "error":
			col = "#ff6060"
		var detail := ""
		var d: Dictionary = e["data"]
		if d.has("temperature_k"):
			detail += " " + _fmt_t(d["temperature_k"])
		if d.has("fall_time_s"):
			detail += " nach %.3f s (erwartet %.3f s), %.3f kg" % [d["fall_time_s"], d["expected_s"], d["mass_kg"]]
		if d.has("reason"):
			detail += " – " + str(d["reason"])
		if d.has("label") and not d.has("reason"):
			detail += " " + str(d["label"])
		if d.has("load_j"):
			detail += " %.0f J, Schaden %.0f %%" % [d["load_j"], d["damage_after"] * 100.0]
		lines.append("[color=%s][t=%.2f s] %s %s%s[/color]" % [col, e["t"], txt, ("#" + ",#".join(e["ids"].map(func(x): return str(x)))) if not e["ids"].is_empty() else "", detail])
	_events.text = "\n".join(lines)


func _run_self_tests() -> void:
	_tests_panel.visible = true
	_tests_text.text = "Selbsttests laufen … (einige Sekunden)"
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var suite := TestSuite.new()
	var res := suite.run_all()
	var lines: Array = ["[b]Selbsttests (Logikebene): %d von %d bestanden[/b] in %.1f s" % [suite.passed_count(), res.size(), (Time.get_ticks_msec() - t0) / 1000.0]]
	lines.append("Pause- und Zurücksetz-Tests auf Szenenebene laufen nur im Kommandozeilen-Runner (tests/run_tests.gd).\n")
	for r in res:
		lines.append("%s %s %s" % ["[color=#80ff80]✔[/color]" if r["ok"] else "[color=#ff6060]✘[/color]", r["name"], ("[color=#a0a0a0](%s)[/color]" % r["detail"]) if r["detail"] != "" else ""])
	lines.append("\n[b]Messwerte[/b]")
	for n in suite.notes:
		lines.append("• " + n)
	_tests_text.text = "\n".join(lines)


# ── Hilfen ───────────────────────────────────────

func _panel(parent: Control, pos: Vector2, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.85)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _rich(parent: Control, min_h: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.custom_minimum_size = Vector2(0, min_h)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 13)
	r.add_theme_font_size_override("bold_font_size", 13)
	r.add_theme_font_size_override("italics_font_size", 12)
	parent.add_child(r)
	return r


func _label(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.custom_minimum_size = Vector2(400, 0)
	parent.add_child(l)
	return l


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.modulate = Color(0.75, 0.9, 1.0)
	parent.add_child(l)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func _fmt_t(k: float) -> String:
	return "%.2f K (%.2f °C)" % [k, k - 273.15]


static func _fmt_e(j: float) -> String:
	if absf(j) >= 1.0e6:
		return "%.4f MJ" % (j / 1.0e6)
	if absf(j) >= 1.0e3:
		return "%.3f kJ" % (j / 1.0e3)
	return "%.3f J" % j


static func _phase_de(p: String) -> String:
	return {"solid": "fest", "melting": "schmilzt/erstarrt", "liquid": "flüssig"}.get(p, p)
