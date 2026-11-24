class_name ConversationViewer
extends PanelContainer
## Gesprächsansicht (Taste C): letzte Äußerungen mit Sprecher, Zuhörer, Absicht, Quelle, Sicherheit,
## Herkunft (lokal / Ollama / SIMULIERT) und – beim Zuhörer – dem aktuellen Prüfstatus des Gehörten
## (bestätigt, veraltet, widersprochen, …). Der angezeigte Satz stammt aus einer Vorlage; optionaler
## Modelltext wird nur grau und ausdrücklich ohne Wirkung gezeigt.

var _text: RichTextLabel
var _only_sel: CheckBox


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.04, 0.94)
	sb.border_color = Color(0.95, 0.75, 0.4)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	add_child(v)
	Nav.label(v, "GESPRÄCHE – strukturierte Mitteilungen; Gehörtes bleibt Hörensagen, bis der Zuhörer es selbst prüft", 13).modulate = Color(1, 0.85, 0.55)
	_only_sel = CheckBox.new()
	_only_sel.text = "nur ausgewähltes Wesen"
	_only_sel.focus_mode = Control.FOCUS_NONE
	v.add_child(_only_sel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.custom_minimum_size = Vector2(540, 300)
	_text.add_theme_font_size_override("normal_font_size", 11)
	v.add_child(_text)


func refresh(life: LifeSimulation, selected_id: int) -> void:
	var ctx := life.ctx
	if ctx.comm == null:
		_text.text = "–"
		return
	var us: Array = ctx.comm.recent(14, selected_id if _only_sel.button_pressed else 0)
	var L: Array = []
	var st: Dictionary = ctx.comm.stats
	L.append("Begonnen %d · gehört %d · nicht gehört %d · nicht möglich %d · lokal %d · Ollama %d · SIMULIERT %d" % [int(st["started"]), int(st["heard"]), int(st["not_heard"]),
		int(st["rejected"]), int(st["via_local"]), int(st["via_ollama"]), int(st["via_simulated"])])
	if us.is_empty():
		L.append("[i]Noch keine Gespräche.[/i]")
	for u in us:
		var via: String = {"lokal": "[color=#aaa]lokal[/color]", "ollama": "[color=#8f8]Ollama[/color]", "simuliert": "[color=#f93]SIMULIERT[/color]"}.get(str(u["via"]), str(u["via"]))
		var src: Dictionary = u["source"]
		L.append("[b]t=%.0f s  #%d → #%d[/b]  %s · %s · %s" % [float(u["t"]), int(u["speaker"]), int(u["listener"]),
			CommunicationSystem.INTENT_LABEL.get(str(u["intent"]), str(u["intent"])), via, str(u["status"])])
		L.append("   %s" % str(u["text"]))
		var chain: Array = src.get("chain", [])
		L.append("   Quelle: %s, Ursprung #%d bei t=%.0f s%s · geäußerte Sicherheit %.0f %%" % [str(src.get("kind", "")), int(src.get("creature", 0)), float(src.get("t", 0.0)),
			(", erzählt über " + "→".join(chain.map(func(x): return "#%d" % int(x)))) if not chain.is_empty() else "", float(u["certainty"]) * 100])
		var l := ctx.creature(int(u["listener"]))
		if l != null and str(u["status"]) == "gehört":
			for c in l.ai["hearsay"]:
				if int(c.get("utterance", 0)) == int(u["id"]) or (c["subject"].get("type", "") == u["statement"].get("type", "") and int(c["subject"].get("id", 0)) == int(u["statement"].get("id", 0)) and c["intent"] == u["intent"]):
					L.append("   beim Zuhörer jetzt: [b]%s[/b]%s" % [ClaimEvaluator.label(str(c["status"])), (" – " + str(c["note"])) if str(c["note"]) != "" else ""])
					break
		if str(u.get("model_text", "")) != "":
			L.append("   [color=#888](Modelltext, ohne Wirkung: %s)[/color]" % str(u["model_text"]))
	_text.text = "\n".join(L)
