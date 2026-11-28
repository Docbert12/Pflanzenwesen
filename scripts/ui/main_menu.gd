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
	sub.text = "%s – Lebenssimulation mit Persönlichkeit, Erinnerung, Lernen, Göttermenü, Gesprächen, ersten Werkzeugen und Arbeitsketten" % version_text()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.modulate = Color(0.8, 0.85, 0.8)
	box.add_child(sub)
	var ng := Button.new()
	ng.name = "NeuesSpiel"
	ng.text = "Neues Spiel\nKarte und Startwert wählen – Voxelwelt, Lebensbaum, 50 Pflanzenwesen, endliche Nahrung, Tag und Nacht"
	ng.custom_minimum_size = Vector2(560, 70)
	ng.add_theme_font_size_override("font_size", 17)
	ng.pressed.connect(open_new_game_dialog)
	box.add_child(ng)
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


static func version_text() -> String:
	return MainMenuVersion.text()


var new_game_dialog: ConfirmationDialog
var map_select: OptionButton
var seed_edit: LineEdit
var map_info: Label
var map_list: Array = []


## Neues-Spiel-Dialog (Alpha 1.1): Kartenvorlage aus data/maps und Startwert.
func open_new_game_dialog() -> void:
	if new_game_dialog == null:
		new_game_dialog = ConfirmationDialog.new()
		new_game_dialog.title = "Neues Spiel"
		new_game_dialog.ok_button_text = "Starten"
		new_game_dialog.cancel_button_text = "Abbrechen"
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(520, 0)
		v.add_theme_constant_override("separation", 8)
		var l1 := Label.new()
		l1.text = "Karte"
		v.add_child(l1)
		map_select = OptionButton.new()
		map_list = MapTemplate.list_all()
		for t in map_list:
			map_select.add_item((t as MapTemplate).name)
		map_select.item_selected.connect(func(_i): _refresh_map_info(true))
		v.add_child(map_select)
		map_info = Label.new()
		map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		map_info.modulate = Color(0.8, 0.85, 0.8)
		v.add_child(map_info)
		var l2 := Label.new()
		l2.text = "Startwert (gleicher Startwert + gleiche Karte = gleiche Welt)"
		v.add_child(l2)
		seed_edit = LineEdit.new()
		v.add_child(seed_edit)
		new_game_dialog.add_child(v)
		new_game_dialog.confirmed.connect(start_new_game)
		add_child(new_game_dialog)
		_refresh_map_info(true)
	new_game_dialog.popup_centered()


func _refresh_map_info(set_seed: bool) -> void:
	if map_list.is_empty():
		map_info.text = "Keine Kartenvorlage in data/maps gefunden."
		return
	var t: MapTemplate = map_list[maxi(0, map_select.selected)]
	map_info.text = "%s\n%s" % [t.summary(), t.description]
	if set_seed:
		seed_edit.text = str(t.default_seed)


## Auswahl des Dialogs als Startauftrag der Spielszene. Ungültiger Startwert → Standardwert der Karte.
func new_game_request() -> Dictionary:
	if map_list.is_empty():
		return {"mode": "new"}
	var t: MapTemplate = map_list[maxi(0, map_select.selected)]
	var txt := seed_edit.text.strip_edges()
	return {"mode": "new", "map": t.id, "seed": int(txt) if txt.is_valid_int() else t.default_seed}


func start_new_game() -> void:
	LivingWorld.pending = new_game_request()
	Nav.go(get_tree(), Nav.LIVING)


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
