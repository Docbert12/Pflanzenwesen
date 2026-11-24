class_name ExperimentInspector
extends PanelContainer
## Versuchs- und Gegenstandsansicht (Prompt 6, Taste E).
##   Versuche: Ausgangslage, vorgeschlagene/ausgeführte Schritte, fehlgeschlagene Voraussetzungen,
##             Hypothese ↔ tatsächliches Resultat.
##   Gegenstand: Bauteile, Verbindungen, funktionale Bewertung (Fähigkeiten aus Geometrie/Material).
## Strikt getrennt: SPIELERDIAGNOSE (exakte Simulationswerte, Debug-Wissen) und WAHRNEHMUNG DES WESENS.
## Es wird nie „Technologie erfunden“ angezeigt, wenn nur ein Modell eine Idee vorgeschlagen hat.

const TAG_DEBUG := "[bgcolor=#5a2e2e] SPIELERDIAGNOSE (Debug-Wissen, das Wesen kennt diese Werte nicht) [/bgcolor]"
const TAG_PERC := "[bgcolor=#2e5a3a] WAHRNEHMUNG DES WESENS [/bgcolor]"
const TAG_HYP := "[bgcolor=#2e5a5a] HYPOTHESE (nur Vorschlag – keine Entdeckung) [/bgcolor]"

var text: RichTextLabel
var object_id: int = 0          # ausgewählter Gegenstand (Klick) – 0 = keiner


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(505, 0)
	text.add_theme_font_size_override("normal_font_size", 11)
	text.add_theme_font_size_override("bold_font_size", 12)
	scroll.add_child(text)


func refresh(life: LifeSimulation, creature_id: int) -> void:
	text.text = describe(life, creature_id, object_id)


static func describe(life: LifeSimulation, creature_id: int, obj_id: int) -> String:
	var ctx := life.ctx
	var L: Array = []
	if obj_id != 0 and ConstructionSystem.is_object(ctx, obj_id):
		L.append_array(object_lines(ctx, ctx.creature(creature_id), obj_id))
		L.append("")
	var recs: Array = ctx.experiments.of_creature(creature_id) if creature_id != 0 else []
	if creature_id == 0:
		var all: Array = ctx.experiments.records.values()
		all.sort_custom(func(a, b): return a.id > b.id)
		recs = all.slice(0, 6)
	L.append("[b]Versuche%s[/b] – gestartet %d, abgeschlossen %d, fehlgeschlagen %d, abgebrochen %d" % [
		(" von #%d" % creature_id) if creature_id != 0 else " (alle)", int(ctx.experiments.stats["started"]), int(ctx.experiments.stats["completed"]),
		int(ctx.experiments.stats["failed"]), int(ctx.experiments.stats["aborted"])])
	var cr := ctx.creature(creature_id)
	if cr != null:
		var br := ctx.experiments.blocked_reason(cr, ctx)
		L.append("Neuer eigener Versuch: %s · Zeitbudget genutzt %.0f %%" % ["möglich" if br == "" else "nicht jetzt (%s)" % br, ExperimentSystem.budget_used(cr, ctx) * 100])
		for h in cr.tech["hypotheses"].slice(-3):
			L.append("%s #%d (%s): %s – Status: [b]%s[/b]" % [TAG_HYP, int(h["id"]), str(h.get("source", "")), str(h.get("question", "")), str(h["status"])])
	if recs.is_empty():
		L.append("[i]Noch keine Versuche.[/i]")
	for r in recs.slice(0, 4):
		L.append_array(record_lines(ctx, r))
	return "\n".join(L)


static func record_lines(ctx: LifeContext, r: ExperimentRecord) -> Array:
	var L: Array = []
	var col: String = {"laufend": "#ffd27a", "abgeschlossen": "#8f8", "fehlgeschlagen": "#f88", "abgebrochen": "#fa8", "unterbrochen": "#fa8"}.get(r.status, "#ccc")
	L.append("[b]Versuch #%d[/b] von #%d · [color=%s]%s[/color] · Herkunft: %s" % [r.id, r.actor_id, col, r.status, r.source])
	L.append("Frage: %s · erwartet: %s" % [r.question, r.expected])
	if r.procedure_key != "":
		L.append("Verfahren: %s" % ProceduralKnowledge.describe_key(r.procedure_key))
	L.append(TAG_PERC)
	for id in r.perceived_initial:
		var pv: Dictionary = r.perceived_initial[id]
		L.append("  vorher #%d: %s, %s" % [int(id), pv.get("aussehen", "?"), pv.get("temperatur", "?")])
	var steps: Array = []
	for i in r.proposed_steps.size():
		var s: Dictionary = r.proposed_steps[i]
		var mark := "✔" if i < r.step_i else ("▶" if i == r.step_i and r.is_running() else "·")
		var lbl := str(ExperimentSystem.OP_LABEL.get(str(s["op"]), s["op"]))
		if str(s["op"]) == "bring":
			lbl = "#%d zu #%d %s" % [int(s.get("obj", 0)), int(s.get("target", 0)), lbl]
		steps.append("%s %s%s" % [mark, lbl, " (automatisch ergänzt)" if s.has("auto") else ""])
	L.append("  Schritte: " + " → ".join(steps))
	for pr in r.perceived_results.slice(-4):
		L.append("  bemerkt: %s" % str(pr["text"]))
	for f in r.failures.slice(-2):
		L.append("  [color=#f88]Voraussetzung/Fehler[/color] Schritt %d (%s): %s" % [int(f["i"]) + 1, ExperimentSystem.OP_LABEL.get(str(f["op"]), f["op"]), str(f["message"])])
	if r.outcome != "":
		var hyp := "Erwartung „%s“ ↔ Resultat „%s“" % [r.expected, r.outcome]
		L.append("  [b]%s[/b] (Unsicherheit %.0f %%)" % [hyp, r.uncertainty * 100])
	L.append(TAG_DEBUG)
	L.append("  Aufwand: %.1f s, %d Schläge, mechanisch %.1f J, Stoffwechsel ≈ %.0f J, Heizung %.0f J" % [float(r.effort["duration_s"]), int(r.effort["strikes"]),
		float(r.effort["mechanical_j"]), float(r.effort["metabolic_j"]), float(r.effort["heater_j"])])
	for id in r.sim_initial:
		var a: Dictionary = r.sim_initial[id]
		var b: Dictionary = r.sim_results.get(str(id), {})
		if a.has("material"):
			L.append("  #%d %s: %.1f→%s K, Höhe %.2f→%s mm, ε %.4f→%s, Schaden %.2f→%s" % [int(id), a["material"], float(a["temperature_k"]),
				str(snappedf(float(b.get("temperature_k", 0)), 0.1)) if b.has("temperature_k") else "–", float(a["dims_mm"][1]),
				str(snappedf(float(b["dims_mm"][1]), 0.01)) if b.has("dims_mm") else "–", float(a["strain"]), str(b.get("strain", "–")), float(a["damage"]), str(b.get("damage", "–"))])
		elif a.get("assembly", false):
			L.append("  #%d Verbund %.3f kg, Verbindungen %s" % [int(id), float(a["mass_kg"]), str(b.get("connections", a.get("connections", [])))])
	return L


## Gegenstandsansicht: Bauteile, Verbindungen, Fähigkeiten (funktional bewertet).
static func object_lines(ctx: LifeContext, cr: Creature, id: int) -> Array:
	var L: Array = []
	var top := ConstructionSystem.top_id(ctx, id)
	L.append("[b]Gegenstand %s[/b] · %.3f kg · %s" % [ConstructionSystem.label_of(ctx, top), ConstructionSystem.mass_of(ctx, top),
		"gehalten von #%d" % ConstructionSystem.carrier_of(ctx, top) if ConstructionSystem.carrier_of(ctx, top) != 0 else "liegt"])
	L.append(TAG_DEBUG)
	for p in ConstructionSystem.parts_of(ctx, top):
		var mp: MaterialPiece = p
		L.append("  Teil #%d %s (%s) %s: %.4f kg, %.0f×%.0f×%.0f mm, %.1f K, flüssig %.0f %%, ε %.3f, Schaden %.0f %%, Verschleiß %.0f %%%s" % [mp.id, mp.material_id, mp.shape_label(),
			mp.role, mp.mass_kg, mp.dims_m.x * 1000, mp.dims_m.y * 1000, mp.dims_m.z * 1000, mp.temperature_k(), mp.liquid_fraction() * 100, mp.strain, mp.damage * 100, mp.wear * 100,
			" · TESTAUSRÜSTUNG" if mp.test_equipment else ""])
		for c in ConstructionSystem.contents_of(ctx, mp.id):
			L.append("    Inhalt #%d %s: %.4f kg, %.1f K, flüssig %.0f %%" % [c.id, c.material_id, c.mass_kg, c.temperature_k(), c.liquid_fraction() * 100])
	if ctx.assemblies.has(top):
		for c2 in (ctx.assemblies[top] as Assembly).connections:
			L.append("  Verbindung %s: Teile #%d↔#%d, Bindemittel #%d, Belastbarkeit %.2f J/Schlag, Verschleiß %.0f %%, %d Schläge, Passung %.0f %%, Geschick %.0f %%" % [
				ConnectionDefinition.label(str(c2["method"])), int(c2["a"]), int(c2["b"]), int(c2["binding_id"]), float(c2["capacity_j"]), float(c2["wear"]) * 100,
				int(c2["strikes"]), float(c2.get("fit", 1)) * 100, float(c2.get("skill", 1)) * 100])
	if cr != null and cr.alive:
		L.append("[b]Funktionale Bewertung als Schlagwerkzeug für #%d[/b] (Name spielt keine Rolle):" % cr.id)
		for line in ObjectEvaluator.lines(ObjectEvaluator.evaluate(ctx, cr, top)):
			L.append("  " + str(line))
		var kn := ProceduralKnowledge.known_object(cr, top)
		L.append(TAG_PERC)
		if kn.is_empty():
			L.append("  #%d kennt diesen Gegenstand nicht." % cr.id)
		else:
			L.append("  Aussehen %s, Form %s, Härte %s, Gewicht %s, Temperatur %s%s" % [ProceduralKnowledge._mat(str(kn.get("aussehen", "?"))), kn.get("form", "?"),
				kn.get("haerte", "unbekannt"), kn.get("gewicht", "unbekannt"), kn.get("temperatur", "unbekannt"),
				(" · Verbindungen: " + ", ".join(kn["verbindungen"])) if kn.has("verbindungen") else ""])
	return L
