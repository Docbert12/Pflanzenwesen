extends Control
## Testbereich „Geistlabor“: führt die kontrollierten Versuche A–G (MindScenarios) sichtbar aus.
## Ereignisse werden hier GEZIELT ausgelöst – das ist Testbetrieb, kein normales Spiel.

var db := DefinitionDB.new()
var _out: RichTextLabel
var _seed: SpinBox
var _box: Node


func _ready() -> void:
	db.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 16)
	add_child(m)
	var v := VBoxContainer.new()
	m.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	Nav.back_button(top, self)
	Nav.label(top, "  Geistlabor – kontrollierte Versuche (Ereignisse werden gezielt ausgelöst; kein normales Spiel)", 16, false)
	var row := HFlowContainer.new()
	v.add_child(row)
	Nav.label(row, "Startwert:", 13, false)
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 99999
	_seed.value = 101
	row.add_child(_seed)
	for letter in MindScenarios.SCENARIOS:
		Nav.button(row, "%s %s" % [letter, MindScenarios.SCENARIOS[letter]], _run.bind(letter, false))
	Nav.button(row, "Alle (3 Startwerte)", _run.bind("*", true))
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.add_theme_font_size_override("normal_font_size", 13)
	_out.add_theme_font_size_override("italics_font_size", 12)
	_out.add_theme_font_size_override("bold_font_size", 14)
	v.add_child(_out)
	_out.text = "Versuch wählen. Jeder Versuch läuft in einer eigenen, frischen Simulation ohne Grafik (dauert einige Sekunden).\n\n" + _descr()
	_box = Node.new()
	_box.name = "Versuchssimulationen"
	add_child(_box)


static func _descr() -> String:
	return "A: Zwei Wesen erleben Hilfe bzw. Ablehnung durch dasselbe Wesen.\nB: Tatsächliche Nahrungsübergabe, gerichtete Beziehung.\nC: Eingriff außerhalb der Wahrnehmung eines Wesens.\nD: Arme heben, kurz danach Gabe – wiederholt; Kontrolle mit zeitlich unverbundener Gabe.\nE: Danach bleibt die Gabe wiederholt aus.\nF: Äußerlich unähnliches Wesen hilft mehrfach.\nG: Speichern und Laden des Geistes."


func _run(letter: String, all_seeds: bool) -> void:
	_out.text = "Läuft …"
	await get_tree().process_frame
	var seeds: Array = [101, 202, 303] if all_seeds else [int(_seed.value)]
	var letters: Array = MindScenarios.SCENARIOS.keys() if letter == "*" else [letter]
	var L: Array = []
	var total := 0
	var ok := 0
	for l in letters:
		for s in seeds:
			var sc := MindScenarios.new(db, _box)
			var checks := sc.run_scenario(l, s, "user://saves/_labor_%s.json" % l)
			sc.cleanup()
			L.append("[b]%s %s – Startwert %d[/b]" % [l, MindScenarios.SCENARIOS[l], s])
			for c in checks:
				total += 1
				if c["ok"]:
					ok += 1
				L.append("  [color=%s]%s[/color] %s%s" % ["#8f8" if c["ok"] else "#f88", "✓" if c["ok"] else "✗", c["name"], ("  [i]" + str(c["detail"]) + "[/i]") if str(c["detail"]) != "" else ""])
			for ext in ["", ".bak"]:
				if FileAccess.file_exists("user://saves/_labor_%s.json%s" % [l, ext]):
					DirAccess.remove_absolute("user://saves/_labor_%s.json%s" % [l, ext])
	_out.text = "[b]%d von %d Teilprüfungen bestanden[/b]\n\n" % [ok, total] + "\n".join(L)
