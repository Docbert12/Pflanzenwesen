extends Control
## Startbildschirm: Neues Spiel, Fortsetzen/Laden (Lebenssimulation) sowie Physiklabor,
## Weltvorschau und Kreaturenvorschau (Vorschau- und Testbereiche).


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.14, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Pflanzenwesen"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(0.7, 0.95, 0.6)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Entwicklungsstand %s – Lebenssimulation mit Persönlichkeit, Erinnerung, Lernen, Göttermenü, Gesprächen, ersten Werkzeugen und Arbeitsketten (Prototyp)" % ProjectSettings.get_setting("application/config/version", "?")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.modulate = Color(0.8, 0.85, 0.8)
	box.add_child(sub)
	var ng := _entry(box, "Neues Spiel", "Kleine Voxelwelt, Lebensbaum, 50 Pflanzenwesen, endliche Nahrung, Tag und Nacht", Nav.LIVING)
	ng.pressed.connect(func(): LivingWorld.pending = {"mode": "new"}, CONNECT_ONE_SHOT)
	_load_entry(box)
	var sep := HSeparator.new()
	box.add_child(sep)
	_entry(box, "Physiklabor", "Fall, Wärme, Schmelzen, Bruch und Massenerhaltung", Nav.LAB)
	var ws := _entry(box, "Testwerkstatt (Testbereich)", "Werkzeuge, Verbinden, Kaltverformung, Gießen mit Testheizung, Vorführen – 2 Testwesen, gezielte Versuche", Nav.LIVING)
	ws.pressed.connect(func(): LivingWorld.pending = {"mode": "workshop"}, CONNECT_ONE_SHOT)
	var wk := _entry(box, "Testszene Werkzeugkette (Testbereich)", "Hammer bauen → Stein zerschlagen → Stücke tragen → lagern, verbauen oder im Testofen schmelzen; Fehlerfälle", Nav.LIVING)
	wk.pressed.connect(func(): LivingWorld.pending = {"mode": "werkzeugkette"}, CONNECT_ONE_SHOT)
	_entry(box, "Geistlabor (Testbereich)", "Kontrollierte Versuche zu Erfahrung, Hilfe, Belohnung, Widerspruch, Speichern", Nav.MIND_LAB)
	_entry(box, "Weltvorschau", "Voxelwelt bearbeiten, Wasser, abbrechende Teile, Lebensbaum, Pflanzen und Pilze", Nav.WORLD)
	_entry(box, "Kreaturenvorschau", "Pflanzenwesen erzeugen, verändern, animieren, speichern; 10er- und 50er-Ansicht", Nav.CREATURES)
	var quit := Button.new()
	quit.text = "Beenden"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)


func _entry(box: VBoxContainer, title: String, desc: String, path: String) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [title, desc]
	b.custom_minimum_size = Vector2(560, 70)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func(): Nav.go(get_tree(), path))
	box.add_child(b)
	return b


## „Fortsetzen / Laden“: zeigt Zustand des Spielstands; bei beschädigter Datei ggf. Sicherung anbieten.
func _load_entry(box: VBoxContainer) -> void:
	var path := SaveManager.path_for()
	var b := Button.new()
	b.custom_minimum_size = Vector2(560, 70)
	b.add_theme_font_size_override("font_size", 17)
	box.add_child(b)
	if not FileAccess.file_exists(path):
		b.text = "Fortsetzen / Laden\nNoch kein Spielstand vorhanden (im Spiel mit F5 speichern)"
		b.disabled = true
		return
	var info := SaveManager.peek(path)
	if info["ok"]:
		b.text = "Fortsetzen / Laden\nSimulationszeit %.0f s · %d lebend, %d tot · gespeichert %s" % [info["time_s"], info["alive"], info["dead"], str(info["saved_at"]).replace("T", " ")]
		b.pressed.connect(func():
			LivingWorld.pending = {"mode": "load", "path": path}
			Nav.go(get_tree(), Nav.LIVING))
		return
	b.text = "Fortsetzen / Laden\nSpielstand nicht ladbar: %s" % str(info["message"]).substr(0, 90)
	b.disabled = true
	var bak := SaveManager.backup_path(path)
	if FileAccess.file_exists(bak) and SaveManager.read_file(bak)["ok"]:
		var bb := Button.new()
		bb.text = "Sicherung laden\nVorherige gültige Speicherung (%s)" % bak
		bb.custom_minimum_size = Vector2(560, 60)
		bb.add_theme_font_size_override("font_size", 15)
		bb.pressed.connect(func():
			LivingWorld.pending = {"mode": "load", "path": bak}
			Nav.go(get_tree(), Nav.LIVING))
		box.add_child(bb)
