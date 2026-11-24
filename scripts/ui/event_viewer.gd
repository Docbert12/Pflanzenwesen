class_name EventViewer
extends PanelContainer
## Letzte Ereignisse aus dem gemeinsamen Ereignisprotokoll (begrenzt, siehe EventLog.max_entries).
## Optional nur Ereignisse, an denen das ausgewählte Wesen beteiligt ist.

var text: RichTextLabel
var only_selected: CheckBox
var hide_routine: CheckBox
const ROUTINE := ["entity_added", "action_rejected"]


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.86)
	sb.set_content_margin_all(6)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var l := Label.new()
	l.text = "Ereignisse"
	l.add_theme_font_size_override("font_size", 13)
	h.add_child(l)
	only_selected = CheckBox.new()
	only_selected.text = "nur ausgewähltes Wesen"
	only_selected.focus_mode = Control.FOCUS_NONE
	h.add_child(only_selected)
	hide_routine = CheckBox.new()
	hide_routine.text = "Routine ausblenden"
	hide_routine.button_pressed = true
	hide_routine.focus_mode = Control.FOCUS_NONE
	h.add_child(hide_routine)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(620, 150)
	text.add_theme_font_size_override("normal_font_size", 11)
	v.add_child(text)


func refresh(sim: Simulation, selected_id: int) -> void:
	var out: Array = []
	var entries := sim.event_log.recent(300)
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if hide_routine.button_pressed and e["type"] in ROUTINE:
			continue
		if only_selected.button_pressed and not (selected_id in e.get("ids", [])):
			continue
		var col := "#ddd"
		match str(e.get("severity", "info")):
			"warning":
				col = "#fc6"
			"error":
				col = "#f66"
		var ids_txt := ",".join(e.get("ids", []).map(func(x): return "#%d" % int(x)))
		out.append("[color=%s]%7.1f s  %s %s  %s[/color]" % [col, float(e.get("t", 0.0)), e["type"], ids_txt, _short(e.get("data", {})).replace("[", "(").replace("]", ")")])
		if out.size() >= 40:
			break
	text.text = "\n".join(out)


static func _short(d: Dictionary) -> String:
	var parts: Array = []
	for k in ["type", "code", "message", "cause", "reason", "op", "result", "kg", "count"]:
		if d.has(k) and str(d[k]) != "":
			parts.append("%s=%s" % [k, str(d[k]).substr(0, 80)])
	return " ".join(parts)
