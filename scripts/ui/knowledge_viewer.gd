class_name KnowledgeViewer
extends PanelContainer
## Wissensansicht (Prompt 6, Taste W): praktisches Wissen EINES Wesens mit Herkunft und
## Erfahrungsstand (davon gehört / dabei zugesehen / selbst versucht / selbst erfolgreich),
## Quellen, Sicherheit und Versionsgeschichte. Wissen ist individuell – es gibt keine globale Liste.

var text: RichTextLabel


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.08, 0.92)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(455, 0)
	text.add_theme_font_size_override("normal_font_size", 11)
	scroll.add_child(text)


func refresh(life: LifeSimulation, creature_id: int) -> void:
	text.text = describe(life.ctx, creature_id)


static func describe(ctx: LifeContext, creature_id: int) -> String:
	var cr := ctx.creature(creature_id)
	if cr == null:
		return "[b]Wissen[/b]: kein Wesen ausgewählt."
	var L: Array = []
	L.append("[b]Praktisches Wissen von #%d %s[/b]%s" % [cr.id, cr.display_name, "" if cr.alive else "  [color=#f88](tot – ungeteiltes Wissen ist mit ihm verloren)[/color]"])
	var st: Dictionary = cr.tech["stats"]
	L.append("Eigene Versuche %d · Erfolge %d · Fehlschläge %d · bekannte Gegenstände %d" % [int(st["experiments"]), int(st["successes"]), int(st["failures"]), cr.tech["objects"].size()])
	var procs: Dictionary = cr.tech["procedures"]
	if procs.is_empty():
		L.append("[i]Kennt noch kein Verfahren.[/i]")
	var keys := procs.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = procs[k]
		var col: String = {"gehört": "#c9a86a", "zugesehen": "#9ac9e0", "versucht": "#e0c070", "erfolgreich": "#8f8"}.get(str(e["level"]), "#ccc")
		L.append("[b]%s[/b]  [color=%s]%s[/color] · Sicherheit %.0f %% · Herkunft: %s" % [str(e["label"]), col, ProceduralKnowledge.LEVEL_LABEL.get(str(e["level"]), "?"),
			float(e["confidence"]) * 100, ProceduralKnowledge.ORIGIN_LABEL.get(str(e["origin"]), str(e["origin"]))])
		var own: Dictionary = e["own"]
		var obs: Dictionary = e["observed"]
		var heard: Dictionary = e["heard"]
		L.append("  selbst: %d Versuche, %d Erfolge%s · gesehen: %d (bei %s) · gehört: %d (unabhängige Ursprünge %d)" % [int(own["attempts"]), int(own["successes"]),
			(" – zuletzt " + str(own["last"])) if str(own["last"]) != "" else "", int(obs["count"]), ", ".join(obs["by"].map(func(x): return "#%d" % int(x))) if not obs["by"].is_empty() else "–",
			int(heard["count"]), (heard["origins"] as Array).size()])
		var pre: Array = []
		for pk in e["prerequisites"]:
			pre.append("%s: %s" % [pk, e["prerequisites"][pk]])
		L.append("  Voraussetzungen: %s" % "; ".join(pre))
		L.append("  Schritte: %s · Materialbereich: %s" % [" → ".join((e["steps"] as Array).map(func(s): return ExperimentSystem.OP_LABEL.get(str(s["op"]), str(s["op"])))),
			", ".join((e["materials"] as Array).map(func(m): return ProceduralKnowledge._mat(str(m)))) if not e["materials"].is_empty() else "–"])
		var vs: Array = []
		for v in (e["versions"] as Array).slice(-3):
			vs.append("v%d t=%.0f s: %s" % [int(v["v"]), float(v["t"]), str(v["change"])])
		L.append("  Versionen: %s" % " | ".join(vs))
	var hs: Array = cr.tech["hypotheses"]
	if not hs.is_empty():
		L.append("[b]Hypothesen[/b] (ungeprüfte Ideen – erst ein ausgeführter Versuch liefert Evidenz):")
		for h in hs.slice(-4):
			L.append("  #%d %s: %s → %s" % [int(h["id"]), str(h.get("source", "")), str(h.get("question", "")), str(h["status"])])
	var w: Dictionary = cr.tech.get("watching", {})
	if not w.is_empty() and ctx.now() < float(w.get("until", 0.0)):
		L.append("Sieht gerade #%d zu: %s" % [int(w["teacher"]), ProceduralKnowledge.describe_key(str(w["key"]))])
	return "\n".join(L)
