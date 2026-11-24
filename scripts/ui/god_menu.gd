class_name GodMenu
extends PanelContainer
## Göttermenü: Nahrung schenken, Material platzieren, Verletzung heilen – optional als Reaktion auf
## ein kürzlich beobachtetes Ereignis. Zeigt VOR der Ausführung Art, Ziel/Position, Menge/Umfang und
## das zugeordnete Ereignis. Die Ereigniszuordnung ist privates Spielerwissen (nur im Eingriffsprotokoll).
## Der Spieler spricht nicht mit Wesen und gibt ihnen keine Befehle.

signal want_position_pick(active: bool)

var life: LifeSimulation
var selected_id: int = 0
var picked_position = null           # Vector3 oder null
var picking: bool = false

var _kind: OptionButton
var _food: OptionButton
var _amount: SpinBox
var _material: OptionButton
var _heal: SpinBox
var _target_mode: OptionButton
var _pick_btn: Button
var _link: CheckBox
var _only_sel: CheckBox
var _events: ItemList
var _preview: Label
var _status: Label
var _ev_cache: Array = []
var _linked: Dictionary = {}
var _amount_row: HBoxContainer
var _mat_row: HBoxContainer
var _shape: OptionButton
var _heal_row: HBoxContainer
var _food_row: HBoxContainer


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.04, 0.93)
	sb.border_color = Color(1.0, 0.85, 0.3)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(400, 0)
	var v := VBoxContainer.new()
	add_child(v)
	Nav.label(v, "GÖTTERMENÜ – sichtbare Eingriffe in die Welt", 14).modulate = Color(1, 0.9, 0.5)
	Nav.label(v, "Kein Sprechen, keine Befehle. Wie Wesen einen Eingriff deuten, entscheidet ihr eigener Geist – nur wer ihn sieht, weiß davon.", 11)
	var r1 := _row(v, "Eingriff:")
	_kind = OptionButton.new()
	for k in GodCommands.KINDS:
		_kind.add_item(GodCommands.KINDS[k])
		_kind.set_item_metadata(_kind.item_count - 1, k)
	_kind.item_selected.connect(func(_i): _update_rows(); refresh_preview())
	r1.add_child(_kind)
	_food_row = _row(v, "Nahrung:")
	_food = OptionButton.new()
	_food.add_item("Beeren (N001)")
	_food.set_item_metadata(0, "N001")
	_food.add_item("Pilz (N002)")
	_food.set_item_metadata(1, "N002")
	_food.item_selected.connect(func(_i): refresh_preview())
	_food_row.add_child(_food)
	_amount_row = _row(v, "Menge kg:")
	_amount = SpinBox.new()
	_amount.min_value = 0.05
	_amount.max_value = 1.0
	_amount.step = 0.05
	_amount.value = 0.2
	_amount.value_changed.connect(func(_x): refresh_preview())
	_amount_row.add_child(_amount)
	_mat_row = _row(v, "Material:")
	_material = OptionButton.new()
	for m in ["stone", "wood", "copper", "plant_fiber"]:
		_material.add_item({"stone": "Stein", "wood": "Holz", "copper": "Kupfer", "plant_fiber": "Pflanzenfasern"}[m])
		_material.set_item_metadata(_material.item_count - 1, m)
	_material.item_selected.connect(func(_i): refresh_preview())
	_mat_row.add_child(_material)
	_shape = OptionButton.new()
	for sh in GodCommands.PIECE_SHAPES:
		_shape.add_item(GodCommands.PIECE_SHAPES[sh]["label"])
		_shape.set_item_metadata(_shape.item_count - 1, sh)
	_shape.item_selected.connect(func(_i): refresh_preview())
	_mat_row.add_child(_shape)
	_heal_row = _row(v, "Heilen bis:")
	_heal = SpinBox.new()
	_heal.min_value = 0.1
	_heal.max_value = 1.0
	_heal.step = 0.1
	_heal.value = 0.5
	_heal.suffix = "Schaden"
	_heal.value_changed.connect(func(_x): refresh_preview())
	_heal_row.add_child(_heal)
	var r2 := _row(v, "Ziel:")
	_target_mode = OptionButton.new()
	_target_mode.add_item("beim ausgewählten Wesen")
	_target_mode.add_item("angeklickte Position")
	_target_mode.item_selected.connect(func(_i): refresh_preview())
	r2.add_child(_target_mode)
	_pick_btn = Button.new()
	_pick_btn.text = "Position wählen"
	_pick_btn.toggle_mode = true
	_pick_btn.focus_mode = Control.FOCUS_NONE
	_pick_btn.toggled.connect(func(on):
		picking = on
		_target_mode.select(1)
		want_position_pick.emit(on)
		refresh_preview())
	r2.add_child(_pick_btn)
	_link = CheckBox.new()
	_link.text = "als Reaktion auf ausgewähltes Ereignis"
	_link.focus_mode = Control.FOCUS_NONE
	_link.toggled.connect(func(_on): refresh_preview())
	v.add_child(_link)
	_only_sel = CheckBox.new()
	_only_sel.text = "nur Ereignisse des ausgewählten Wesens"
	_only_sel.focus_mode = Control.FOCUS_NONE
	_only_sel.button_pressed = true
	_only_sel.toggled.connect(func(_on): refresh_events())
	v.add_child(_only_sel)
	_events = ItemList.new()
	_events.custom_minimum_size = Vector2(380, 120)
	_events.add_theme_font_size_override("font_size", 11)
	_events.focus_mode = Control.FOCUS_NONE
	_events.item_selected.connect(func(i):
		if i < _ev_cache.size():
			_linked = _ev_cache[i]
			_link.button_pressed = true
		refresh_preview())
	v.add_child(_events)
	_preview = Label.new()
	_preview.add_theme_font_size_override("font_size", 12)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(380, 0)
	v.add_child(_preview)
	Nav.button(v, "Eingriff ausführen", execute)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	_status.modulate = Color(1, 0.95, 0.7)
	v.add_child(_status)
	_update_rows()


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(90, 0)
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	return h


func _update_rows() -> void:
	var k := kind()
	_food_row.visible = k == "gift_food"
	_amount_row.visible = k == "gift_food"
	_mat_row.visible = k == "place_material"
	_heal_row.visible = k == "heal"


func kind() -> String:
	return str(_kind.get_item_metadata(_kind.selected))


func set_kind(k: String) -> void:
	for i in _kind.item_count:
		if _kind.get_item_metadata(i) == k:
			_kind.select(i)
	_update_rows()


## Baut den Befehl aus der aktuellen Auswahl.
func build_command() -> Dictionary:
	var cmd := {"kind": kind()}
	var by_pos := _target_mode.selected == 1
	if kind() == "heal" or not by_pos:
		cmd["target_id"] = selected_id
	if by_pos and kind() != "heal" and picked_position != null:
		cmd["position"] = picked_position
		cmd["target_id"] = 0
	match kind():
		"gift_food":
			cmd["food_id"] = str(_food.get_item_metadata(_food.selected))
			cmd["amount_kg"] = _amount.value
		"place_material":
			cmd["material_id"] = str(_material.get_item_metadata(_material.selected))
			cmd["shape"] = str(_shape.get_item_metadata(_shape.selected))
		"heal":
			cmd["heal_amount"] = _heal.value
	if _link.button_pressed and not _linked.is_empty():
		cmd["linked_event"] = _linked.duplicate()
	return cmd


func set_picked_position(p: Vector3) -> void:
	picked_position = p
	picking = false
	_pick_btn.set_pressed_no_signal(false)
	want_position_pick.emit(false)
	refresh_preview()


func refresh_events() -> void:
	if life == null:
		return
	var keep := int(_linked.get("seq", -1))
	_ev_cache = life.ctx.interventions.recent_events(180.0, 30, selected_id if _only_sel.button_pressed else 0)
	_events.clear()
	for e in _ev_cache:
		_events.add_item("%6.0f s  %s  #%d" % [float(e["t"]), _ev_label(str(e["type"])), int(e["actor"])])
		if int(e["seq"]) == keep:
			_events.select(_events.item_count - 1)


static func _ev_label(t: String) -> String:
	return {"raise_arms": "Arme heben", "food_given": "Nahrung gegeben", "food_requested": "um Nahrung gebeten", "request_declined": "Bitte abgelehnt",
		"food_offered": "Nahrung angeboten", "offer_not_accepted": "Angebot nicht angenommen", "food_eaten": "gegessen", "food_taken": "Nahrung genommen",
		"death": "gestorben", "injury_visible": "Verletzung sichtbar", "food_appeared": "Gabe: Nahrung", "material_appeared": "Gabe: Material", "healed": "geheilt"}.get(t, t)


func refresh_preview() -> void:
	if life == null:
		return
	var cmd := build_command()
	var prep := GodCommands.prepare(life.ctx, cmd)
	var t: String = prep["text"]
	if _target_mode.selected == 1 and picked_position == null and kind() != "heal":
		t += "\n→ Erst „Position wählen“ und in die Welt klicken."
	if picking:
		t += "\n→ Klick in die Welt setzt die Position."
	if not prep["ok"]:
		t += "\nNicht ausführbar: " + "; ".join(prep["errors"])
	_preview.text = t


func execute() -> void:
	if life == null:
		return
	var r := life.ctx.interventions.execute(build_command())
	_status.text = str(r["message"])
	if r["ok"]:
		_linked = {}
		_link.button_pressed = false
	refresh_events()
	refresh_preview()
