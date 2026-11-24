class_name PopulationPanel
extends PanelContainer
## Übersicht der Population: lebend/tot, Nahrung, Zeit, Tagesphase, Zustände; Liste zum Auswählen.

signal creature_selected(id: int)

var summary: RichTextLabel
var list: ItemList
var _ids: Array = []


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.86)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	summary = RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.fit_content = true
	summary.scroll_active = false
	summary.custom_minimum_size = Vector2(300, 0)
	summary.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(summary)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(300, 230)
	list.add_theme_font_size_override("font_size", 11)
	list.focus_mode = Control.FOCUS_NONE
	list.item_selected.connect(func(i): if i < _ids.size(): creature_selected.emit(_ids[i]))
	v.add_child(list)


func refresh(life: LifeSimulation, selected_id: int) -> void:
	var s := life.population_summary()
	var states: Array = []
	for k in s["states"]:
		states.append("%s %d" % [k, s["states"][k]])
	summary.text = "[b]Population[/b]  lebend [color=#8f8]%d[/color] · gestorben [color=#f88]%d[/color]\nZeit %.0f s · Tag %d, %s (%s) · Licht %.0f %%\nNahrung %.2f kg (frei %.2f kg) in %d/%d Quellen · Portionen am Boden %d\nØ Hunger %.0f %% · Handlungen %d · Reservierungen %d\n%s%s" % [
		s["alive"], s["dead"], s["time_s"], life.ctx.day_night.day_number(s["time_s"]), s["clock"], s["phase"], s["light"] * 100,
		s["food_kg"], s["food_free_kg"], s["food_sources_nonempty"], s["food_sources"], s["ground_items"],
		s["avg_hunger"] * 100, s["running_actions"], s["reservations"], ", ".join(states),
		"\n[color=#fc6]TESTOPTION Nachfüllen AKTIV[/color]" if life.ctx.refill_enabled else ""]
	var ids := life.ctx.creatures.keys()
	ids.sort()
	if ids.size() != _ids.size():
		list.clear()
		for id in ids:
			list.add_item("")
		_ids = ids
	for i in ids.size():
		var cr: Creature = life.ctx.creatures[ids[i]]
		var t := "#%d %s  %s  H %.0f%%  E %.0f%%" % [cr.id, cr.display_name, cr.behavior_state, cr.metabolism.hunger() * 100, cr.metabolism.energy_fraction() * 100] if cr.alive else "#%d %s  † %s" % [cr.id, cr.display_name, str(cr.death.get("cause", ""))]
		list.set_item_text(i, t)
		list.set_item_custom_fg_color(i, Color(1, 0.55, 0.55) if not cr.alive else Color(0.9, 0.95, 0.9))
		if ids[i] == selected_id and not list.is_selected(i):
			list.select(i)
