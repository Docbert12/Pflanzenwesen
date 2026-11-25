class_name CreatureInspector
extends PanelContainer
## Beobachtungsfenster für ein einzelnes Wesen. Alle Texte stammen aus Systemdaten
## (Körperplan, Fähigkeiten, Stoffwechsel, Handlung, Wahrnehmung, Geist, letztes Ergebnis) –
## es werden keine inneren Gedanken erfunden. Sichtbar getrennt (Farbbalken):
##   WELTFAKT (tatsächlicher Zustand) · BEOBACHTUNG (aktuelle eigene Wahrnehmung) ·
##   ERINNERUNG (eigener Speicher) · VERMUTUNG (Überzeugungen, Vertrauen) · ENTSCHEIDUNG (Bewertung) ·
##   MODELLVORSCHLAG (Ollama/SIMULIERT, nur nach Prüfung wirksam) · HÖRENSAGEN (Gehörtes, nicht selbst gesehen).

const TAG := {"welt": "[bgcolor=#3a4a5a] WELTFAKT [/bgcolor]", "beob": "[bgcolor=#2e5a3a] BEOBACHTUNG [/bgcolor]",
	"erin": "[bgcolor=#5a4a2e] ERINNERUNG [/bgcolor]", "verm": "[bgcolor=#5a2e5a] VERMUTUNG [/bgcolor]", "ents": "[bgcolor=#2e3a5a] ENTSCHEIDUNG [/bgcolor]",
	"modell": "[bgcolor=#2e5a5a] MODELLVORSCHLAG [/bgcolor]", "hoer": "[bgcolor=#6a4a1e] HÖRENSAGEN [/bgcolor]"}

var text: RichTextLabel


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(375, 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 12)
	text.add_theme_font_size_override("bold_font_size", 13)
	text.add_theme_font_size_override("italics_font_size", 12)
	scroll.add_child(text)


func show_creature(life: LifeSimulation, id: int) -> void:
	text.text = describe(life, id)


static func describe(life: LifeSimulation, id: int) -> String:
	var ctx := life.ctx
	var cr := ctx.creature(id)
	if cr == null:
		return "[b]Kein Wesen ausgewählt.[/b]\nLinksklick auf ein Wesen oder Eintrag in der Liste."
	var L: Array = []
	L.append(TAG["welt"])
	var head := "[b]#%d %s[/b]" % [cr.id, cr.display_name]
	if cr.alive:
		L.append(head + "  [color=#8f8]lebt[/color]")
	else:
		L.append(head + "  [color=#f88]tot[/color] – %s (t = %.0f s)" % [str(cr.death.get("cause", "?")), float(cr.death.get("t", 0.0))])
	var g: Dictionary = cr.base_genes
	L.append("[b]Körpervariante[/b] %s · Größe %.2f m · Blattform %s · Haut %s · Startwert %d" % [cr.plan.species_id, float(g.get("height_m", 0)), str(g.get("leaf_shape", "?")), str(g.get("skin_palette_id", "?")), cr.plan_seed])
	L.append("Masse %.2f kg (inkl. Prothesen) · Blätter %d (angelegt %d)" % [cr.mass_kg, int(cr.caps.get("leaf_count", 0)), int(g.get("leaf_count", 0))])
	var present: Array = []
	var missing: Array = []
	for pid in cr.plan.order:
		var p: Dictionary = cr.plan.parts[pid]
		var dmg := cr.health.damage_of(pid)
		match str(p["status"]):
			"present":
				if p["type"] == "prosthesis":
					present.append("[color=#fc6]%s (%s)[/color]" % [pid, p["material_id"]])
				elif dmg > 0.0:
					present.append("[color=#f96]%s %.0f %% verletzt[/color]" % [pid, dmg * 100])
				else:
					present.append(pid)
			"removed":
				missing.append(pid)
			"replaced":
				missing.append("%s → %s" % [pid, str(p.get("replaced_by", "Prothese"))])
	L.append("[b]Vorhanden[/b] (%d): %s" % [present.size(), ", ".join(present)])
	L.append("[b]Fehlend/ersetzt[/b]: %s" % (", ".join(missing) if not missing.is_empty() else "keine"))
	var c := cr.caps
	var walk := "Gehen %.2f → %.2f m/s" % [float(c.get("locomotion", 0)), cr.speed_m_s(ctx)] if c.get("can_walk", false) else "[color=#f88]Gehen nicht möglich[/color]: %s" % str(c.get("walk_reason", ""))
	var gb: Dictionary = c.get("grasp_by_side", {})
	L.append("[b]Fähigkeiten[/b] %s · Greifen L %.2f / R %.2f · Zum Mund führen %.2f · Mund %.2f · Blattfläche %.4f m²" % [walk, float(gb.get("l", 0)), float(gb.get("r", 0)), float(c.get("feeding", 0)), float(c.get("mouth", 0)), float(c.get("leaf_area_m2", 0))])
	var m := cr.metabolism
	L.append("[b]Energie[/b] %.0f / %.0f J (%.0f %%) · [b]Nährstoffe[/b] %.2f / %.2f g (%.0f %%) · Hunger %.0f %%" % [m.energy_j, m.energy_capacity_j, m.energy_fraction() * 100, m.nutrients_g, m.nutrient_capacity_g, m.nutrient_fraction() * 100, m.hunger() * 100])
	var lp: Dictionary = m.last_power
	if not lp.is_empty() and cr.alive:
		L.append("Leistung: Licht +%.2f W · Grundumsatz −%.2f W · Blätter −%.2f W · Bewegung −%.2f W · Handlung −%.2f W" % [float(lp.get("light_w", 0)), float(lp.get("basal_w", 0)), float(lp.get("leaf_upkeep_w", 0)), float(lp.get("move_w", 0)), float(lp.get("action_w", 0))])
	L.append("Gegessen %.3f kg · Licht gesamt %.0f J · Weg %.1f m" % [float(cr.stats.get("eaten_kg", 0)), float(cr.stats.get("light_j", 0)), float(cr.stats.get("distance_m", 0))])
	var dm: Array = []
	for pid in cr.health.part_damage:
		dm.append("%s %.0f %%" % [pid, float(cr.health.part_damage[pid]) * 100])
	L.append("[b]Gesundheit[/b] Vitalität %.0f %% · Mangelschaden %.0f %% · Teilschäden: %s" % [cr.health.vitality() * 100, cr.health.starvation * 100, ", ".join(dm) if not dm.is_empty() else "keine"])
	L.append("[b]Persönlichkeit[/b] " + cr.personality.describe(ctx.mind_cfg) + "  [i](Spielwerte 0…1, fest)[/i]")
	L.append("")
	L.append(TAG["ents"])
	L.append("[b]Zustand[/b] %s – %s" % [cr.behavior_state, cr.behavior_reason])
	L.append_array(decision_lines(cr))
	if not cr.goal.is_empty():
		L.append("[b]Ziel[/b] %s" % _goal_text(ctx, cr.goal))
	if ctx.executor.running.has(cr.id):
		var a: GameAction = ctx.executor.running[cr.id]
		L.append("[b]Handlung[/b] %s · %.1f / %.0f s" % [a.summary(), a.elapsed_s, a.timeout_s])
		if a.target_id != 0:
			L.append("Zielobjekt: %s" % _obj_text(ctx, a.target_id))
	else:
		L.append("[b]Handlung[/b] keine")
	if cr.carried_item_id != 0:
		L.append("Trägt: %s" % _obj_text(ctx, cr.carried_item_id))
	var mem: Array = []
	var ids := cr.food_memory.keys()
	ids.sort_custom(func(x, y): return float(cr.food_memory[x]["seen_t"]) > float(cr.food_memory[y]["seen_t"]))
	for fid in ids.slice(0, 5):
		var e: Dictionary = cr.food_memory[fid]
		var pos := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
		mem.append("#%d %.2f kg, %.1f m, vor %.0f s" % [fid, float(e["available_kg"]), ctx.distance_xz(cr.position, pos), ctx.now() - float(e["seen_t"])])
	L.append("[b]Wahrnehmung[/b] sichtbar %d Nahrung · gemerkt %d: %s" % [cr.visible_food.size(), cr.food_memory.size(), "; ".join(mem) if not mem.is_empty() else "–"])
	if not cr.unreachable.is_empty():
		var u: Array = []
		for k in cr.unreachable:
			u.append("#%d bis %.0f s" % [k, float(cr.unreachable[k])])
		L.append("Verworfen (unerreichbar): " + ", ".join(u))
	if not cr.last_result.is_empty():
		var lr := cr.last_result
		var col := "#8f8" if lr.get("status") == "succeeded" else "#fc6"
		L.append("[b]Letztes Ergebnis[/b] [color=%s]%s %s[/color] (%s) %s" % [col, str(lr.get("type")), str(lr.get("status")), str(lr.get("code")), str(lr.get("message"))])
	L.append("Position (%.1f, %.1f, %.1f)" % [cr.position.x, cr.position.y, cr.position.z])
	L.append_array(mind_lines(ctx, cr, 5))
	L.append_array(ai_lines(ctx, cr))
	L.append_array(work_lines(ctx, cr))
	L.append_array(tech_lines(ctx, cr))
	return "\n".join(L)


## Arbeitskette (Prompt 6B): Ziel, laufende Handlung, Werkzeug-ID, Zielobjekt, getragene Masse,
## Fortschritt, Abbruch-/Pausegrund – Spieleranzeige aus dem tatsächlichen Zustand der Kette.
static func work_lines(ctx: LifeContext, cr: Creature) -> Array:
	var L: Array = []
	if ctx.work == null:
		return L
	var v := ctx.work.status_view(cr, ctx)
	if v.is_empty():
		return L
	L.append("")
	var col := "#8f8" if str(v["status"]) == "abgeschlossen" else ("#fc6" if str(v["status"]) in ["läuft", "pausiert"] else "#f88")
	L.append("[b]ARBEIT[/b] Kette #%d – [b]Ziel:[/b] %s · [color=%s]%s[/color] · %s%s" % [int(v["chain"]), str(v["ziel"]), col, str(v["status"]),
		"[color=#9cf]autonom (eigener Bedarf)[/color]" if v["autonom"] else "gezielt ausgelöst", (" – " + str(v["herkunft"])) if not v["autonom"] else ""])
	L.append("[b]Handlung:[/b] %s · [b]Schritt:[/b] %s · Pose %s · Kontakte %d" % [str(v["handlung"]), str(v["schritt"]), str(v["pose"]) if str(v["pose"]) != "" else "–", int(v["kontakte"])])
	L.append("[b]Werkzeug:[/b] %s · [b]Zielobjekt:[/b] %s · Bestimmung %s" % ["#%d" % int(v["werkzeug"]) if int(v["werkzeug"]) != 0 else "–",
		_obj_text(ctx, int(v["zielobjekt"])) if int(v["zielobjekt"]) != 0 else "–", ("#%d" % int(v["bestimmung"])) if int(v["bestimmung"]) != 0 else "–"])
	L.append("[b]Getragen:[/b] %s · [b]transportiert gesamt:[/b] %.2f kg (%d Stücke abgeliefert) · [b]Fortschritt:[/b] %.0f %%" % [
		("#%d, %.2f kg" % [int(v["getragen_id"]), float(v["getragen_kg"])]) if float(v["getragen_kg"]) > 0.0 else "nichts", float(v["transportiert_kg"]), int(v["abgeliefert"]), float(v["fortschritt"]) * 100.0])
	if str(v["abbruchgrund"]) != "":
		L.append("[color=#f88][b]Abbruchgrund:[/b] %s[/color]" % str(v["abbruchgrund"]))
	if str(v["pausegrund"]) != "":
		L.append("[color=#fc6][b]Pause:[/b] %s[/color]" % str(v["pausegrund"]))
	var lg: Array = v.get("log", [])
	for e in lg.slice(maxi(0, lg.size() - 3)):
		L.append("  · t=%.0f s %s" % [float(e.get("t", 0.0)), str(e.get("text", e.get("what", "")))])
	return L


## Werkzeug, laufender Versuch, praktisches Wissen (Prompt 6) – Details in E (Versuche) und W (Wissen).
static func tech_lines(ctx: LifeContext, cr: Creature) -> Array:
	var L: Array = []
	if cr.tech.is_empty():
		return L
	if cr.held_object_id != 0:
		L.append("%s Hält %s (%s)" % [TAG["welt"], ConstructionSystem.label_of(ctx, cr.held_object_id), ToolUseSystem.object_temperature_category(ctx, cr.held_object_id)])
	var r := ctx.experiments.active(cr) if ctx.experiments != null else null
	if r != null:
		L.append("%s Versuch #%d (%s): %s – Schritt %d/%d" % [TAG["ents"], r.id, r.source, r.question, mini(r.step_i + 1, r.proposed_steps.size()), r.proposed_steps.size()])
	var procs: Dictionary = cr.tech["procedures"]
	if not procs.is_empty():
		var parts: Array = []
		for k in procs:
			parts.append("%s (%s)" % [procs[k]["label"], ProceduralKnowledge.LEVEL_LABEL.get(str(procs[k]["level"]), "")])
		L.append("[b]Verfahren[/b] " + "; ".join(parts.slice(0, 3)) + (" …" if parts.size() > 3 else "") + "  [i](Taste W)[/i]")
	return L


## Bewertungsbeiträge der letzten Entscheidung (aus DecisionSystem protokolliert).
static func decision_lines(cr: Creature) -> Array:
	var L: Array = []
	var d := cr.decision
	if d.is_empty():
		return L
	L.append("Gewählt bei t=%.0f s: [b]%s[/b] (Nutzwert %.2f) · Quelle: [b]%s[/b]" % [float(d.get("t", 0)), str(d.get("chosen", "")), float(d.get("u", 0)), str(d.get("source", "lokal"))])
	for o in d.get("options", []).slice(0, 4):
		var parts: Array = []
		for k in o["parts"]:
			if absf(float(o["parts"][k])) >= 0.005:
				parts.append("%s %+.2f" % [k, float(o["parts"][k])])
		L.append("  %s %.2f: %s" % [str(o["id"]), float(o["u"]), ", ".join(parts)])
	return L


## Geist: Beobachtung, Erinnerung, Vermutung, Beziehungen, Eingriffe.
static func mind_lines(ctx: LifeContext, cr: Creature, n: int) -> Array:
	var L: Array = []
	var now := ctx.now()
	var mc := ctx.mind_cfg
	L.append("")
	L.append(TAG["beob"])
	var vc: Array = []
	for v in cr.visible_creatures.slice(0, 6):
		vc.append("#%d %.1f m%s%s" % [int(v["id"]), float(v["d"]), "" if v["alive"] else " (regungslos)", " trägt etwas" if v["carrying"] else ""])
	L.append("Sieht Wesen: %s" % (", ".join(vc) if not vc.is_empty() else "keine"))
	if not cr.social["inbox"].is_empty():
		var ib: Array = []
		for r in cr.social["inbox"]:
			ib.append("#%d (t=%.0f s)" % [int(r["from"]), float(r["t"])])
		L.append("Wahrgenommene Bitten an mich: " + ", ".join(ib))
	L.append("")
	L.append(TAG["erin"] + "  %d gespeichert, %d vergessen; bekannt seit t=%.0f s" % [cr.memory.entries.size(), cr.memory.forgotten, cr.mind_since_t])
	for e in cr.memory.recall({}, now, mc, n):
		L.append("  #%d %s%s%s ×%d, zuletzt t=%.0f s · Bedeutung %.2f · Sicherheit %.2f · Zugänglichkeit %.2f" % [int(e["id"]), str(e["type"]),
			(" von #%d" % int(e["actor"])) if int(e["actor"]) != 0 else "", (" an #%d" % int(e["target"])) if int(e["target"]) != 0 else "",
			int(e["count"]), float(e["t_last"]), float(e["significance"]), float(e["certainty"]), cr.memory.accessibility(e, now, mc)])
	L.append("")
	L.append(TAG["verm"] + "  (zeitliche Häufigkeiten, keine bewiesenen Ursachen)")
	var hs: Array = cr.beliefs.items.values()
	hs.sort_custom(func(a, b): return cr.beliefs.evidence_n(a["key"], mc) > cr.beliefs.evidence_n(b["key"], mc))
	for h in hs.slice(0, n + 1):
		L.append("  „%s“ – Häufigkeit %.0f %% · Konfidenz %.2f · dafür %d / dagegen %d%s" % [BeliefStore.statement(h), cr.beliefs.p(h["key"]) * 100,
			cr.beliefs.confidence(h["key"], mc), int(h["n_support"]), int(h["n_contra"]),
			(" · erlebter Wert %.2f" % float(h["value_avg"])) if int(h["value_n"]) > 0 else ""])
	if hs.is_empty():
		L.append("  keine")
	L.append("[b]Beziehungen[/b] (gerichtet: was DIESES Wesen erlebt hat)")
	var rs: Array = cr.relations.rel.keys()
	rs.sort_custom(func(a, b): return float(cr.relations.rel[a]["familiarity"]) > float(cr.relations.rel[b]["familiarity"]))
	for oid in rs.slice(0, n):
		var r: Dictionary = cr.relations.rel[oid]
		L.append("  → #%d Vertrautheit %.2f · Vertrauen %.2f (Erfahrung %.1f) · Hilfe erhalten %d / gegeben %d · Ablehnungen %d · Ähnlichkeit %.2f · Herkunft %s%s" % [oid,
			float(r["familiarity"]), cr.relations.trust(oid), cr.relations.trust_evidence(oid), int(r["help_received"]), int(r["help_given"]), int(r["declines"]),
			float(r["similarity"]), str(r["origin"]), " · gesehen: regungslos" if r.get("seen_dead", false) else ""])
	if rs.is_empty():
		L.append("  keine")
	if not cr.interventions_seen.is_empty():
		L.append("[b]Wahrgenommene Eingriffe[/b] (eigene Deutung)")
		for rec in cr.interventions_seen.slice(maxi(0, cr.interventions_seen.size() - 3)):
			L.append("  t=%.0f s %s · Wert für mich %.2f · %s" % [float(rec["t"]), str(rec["type"]), float(rec["value"]), str(rec["explanation"])])
	return L


## Kurzfassung für die Vergleichsansicht.
static func compact(ctx: LifeContext, id: int, other_id: int) -> String:
	var cr := ctx.creature(id)
	if cr == null:
		return "—"
	var L: Array = []
	L.append("[b]#%d %s[/b] %s" % [cr.id, cr.display_name, "" if cr.alive else "[color=#f88](tot)[/color]"])
	L.append(cr.personality.describe(ctx.mind_cfg))
	L.append("Hunger %.0f %% · Zustand %s" % [cr.metabolism.hunger() * 100, cr.behavior_state])
	L.append("Erinnerungen %d · Überzeugungen %d · Beziehungen %d · Eingriffe gesehen %d" % [cr.memory.entries.size(), cr.beliefs.items.size(), cr.relations.rel.size(), cr.interventions_seen.size()])
	if other_id != 0:
		if cr.relations.rel.has(other_id):
			var r: Dictionary = cr.relations.rel[other_id]
			L.append("[b]→ #%d[/b]: Vertrautheit %.2f, Vertrauen %.2f, Hilfe erhalten %d, Ablehnungen %d, Ähnlichkeit %.2f" % [other_id, float(r["familiarity"]), cr.relations.trust(other_id), int(r["help_received"]), int(r["declines"]), float(r["similarity"])])
		else:
			L.append("[b]→ #%d[/b]: kennt es nicht" % other_id)
	var hs: Array = cr.beliefs.items.values()
	hs.sort_custom(func(a, b): return cr.beliefs.confidence(a["key"], ctx.mind_cfg) > cr.beliefs.confidence(b["key"], ctx.mind_cfg))
	for h in hs.slice(0, 4):
		L.append("„%s“ %.0f %% (Konf. %.2f)" % [BeliefStore.statement(h), cr.beliefs.p(h["key"]) * 100, cr.beliefs.confidence(h["key"], ctx.mind_cfg)])
	return "\n".join(L)


static func _goal_text(ctx: LifeContext, goal: Dictionary) -> String:
	match str(goal.get("type", "")):
		"food":
			return "Nahrung " + _obj_text(ctx, int(goal.get("id", 0)))
		"explore":
			return "Erkunden"
	return str(goal)


static func _obj_text(ctx: LifeContext, id: int) -> String:
	if ctx.foods.has(id):
		var f: FoodSource = ctx.foods[id]
		return "#%d %s – Rest %.3f kg (frei %.3f kg)" % [id, f.display_name, f.amount_kg, f.available_kg()]
	if ctx.items.has(id):
		var it: FoodItem = ctx.items[id]
		return "#%d Portion %s %.3f kg%s" % [id, it.food_id, it.mass_kg, " (getragen)" if it.carrier_id != 0 else " (am Boden)"]
	if ctx.creatures.has(id):
		return "#%d %s" % [id, ctx.creatures[id].display_name]
	return "#%d (nicht mehr vorhanden)" % id


## Modellanbindung, Plan, Hörensagen und Gespräche dieses Wesens.
static func ai_lines(ctx: LifeContext, cr: Creature) -> Array:
	var L: Array = []
	var now := ctx.now()
	L.append("")
	var svc: AIService = ctx.ai.service if ctx.ai != null else null
	var elig := cr.ai_eligible(float(svc.settings.g("eligible_share", 0.5))) if svc != null else false
	L.append(TAG["modell"] + "  nur Vorschläge – wirksam erst nach Prüfung, jeder Schritt wird neu geprüft")
	L.append("Anbindung: %s · dieses Wesen fragt: %s · nächste Anfrage frühestens t=%.0f s" % [svc.status_text() if svc != null else "–", "ja" if elig else "nein (nicht ausgewählt)", float(cr.ai.get("next_request_t", 0.0))])
	var w: Dictionary = ctx.ai.waiting_for(cr.id) if ctx.ai != null else {}
	if not w.is_empty():
		L.append("[b]Anfrage %d[/b] %s seit t=%.0f s · Anlass: %s%s" % [int(w["id"]), "läuft" if w.get("state", "") == "läuft" else "wartet in der Warteschlange", float(w["created_t"]), str(w["reason"]),
			(" · abgefragter Zustand von t=%.0f s (Alter %.0f s)" % [float(w["state_t"]), now - float(w["state_t"])]) if w.has("state_t") else ""])
		L.append("  Das Wesen handelt währenddessen lokal weiter.")
	var last: Dictionary = cr.ai.get("last", {})
	if not last.is_empty():
		var col := "#8f8" if str(last.get("status", "")) == "angenommen" else ("#fc6" if str(last.get("status", "")) in ["wartet", "läuft", "wiederholt"] else "#f96")
		L.append("[b]Letzte Anfrage[/b] %s [color=%s]%s[/color]%s · Anlass: %s" % [("Nr. %d" % int(last.get("request_id", 0))) if int(last.get("request_id", 0)) > 0 else "",
			col, str(last.get("status", "")), " [color=#f93](SIMULIERT)[/color]" if last.get("simulated", false) else "", str(last.get("reason", ""))])
		if str(last.get("why", "")) != "":
			L.append("  Begründung: %s" % str(last["why"]))
		if last.has("latency_ms"):
			L.append("  Antwortzeit %.1f s · Zustand beim Anfragen t=%.0f s (bei Prüfung %.0f s alt)%s" % [int(last["latency_ms"]) / 1000.0, float(last.get("state_t", 0.0)),
				float(last.get("t", 0.0)) - float(last.get("state_t", 0.0)), " · traf während der Pause ein, danach geprüft" if last.get("after_pause", false) else ""])
		if str(last.get("explanation", "")) != "":
			L.append("  Modellbegründung (nur Vorschlag): [i]„%s“[/i]" % str(last["explanation"]))
	var plan: Dictionary = cr.ai.get("plan", {})
	if not plan.is_empty():
		L.append("[b]Aktiver Plan %d[/b] (%s) Ziel %s · Unsicherheit %.2f · seit t=%.0f s" % [int(plan["id"]), "SIMULIERT" if plan["source"] == "simuliert" else "Ollama", str(plan["goal_type"]), float(plan["uncertainty"]), float(plan["created_t"])])
		var i := 0
		for st in plan["steps"]:
			var mark: String = {"offen": "○", "läuft": "▶", "erledigt": "✓", "fehlgeschlagen": "✗"}.get(str(st["status"]), "?")
			L.append("  %s %d. %s%s%s" % [mark, i + 1, PlanManager.label(str(st["action"])), (" #%d" % int(st["target"])) if int(st["target"]) != 0 else "",
				(" – " + str(st["result"])) if str(st["result"]) != "" else ""])
			i += 1
	for h in cr.ai.get("plan_history", []).slice(maxi(0, cr.ai.get("plan_history", []).size() - 2)):
		L.append("  früherer Plan %d: [b]%s[/b] – %s" % [int(h["id"]), str(h["state"]), str(h.get("result", ""))])
	for nt in cr.ai.get("notes", []).slice(maxi(0, cr.ai.get("notes", []).size() - 2)):
		L.append("  Modelldeutung t=%.0f s: %s (Unsicherheit %.2f) „%s“ – [i]kein Beleg, ändert keine Vermutung[/i]" % [float(nt["t"]), str(nt["interpretation"]), float(nt["uncertainty"]), str(nt["text"])])
	L.append("")
	L.append(TAG["hoer"] + "  Gehörtes – erst eigene Wahrnehmung bestätigt oder widerlegt es")
	var hs: Array = cr.ai.get("hearsay", [])
	for c in hs.slice(maxi(0, hs.size() - 4)):
		var chain: Array = c["chain"]
		L.append("  von #%d (Ursprung #%d%s), t=%.0f s: %s · geäußert %.0f %% · Vertrauen damals %.2f · [b]%s[/b]%s%s" % [int(c["speaker"]), int(c["origin"]["creature"]),
			(", Kette " + "→".join(chain.map(func(x): return "#%d" % int(x)))) if chain.size() > 1 else "", float(c["t_heard"]), str(c["statement"]), float(c["certainty"]) * 100,
			float(c["trust_at_hearing"]), ClaimEvaluator.label(str(c["status"])), (" – " + str(c["note"])) if str(c["note"]) != "" else "",
			(" · unabhängig %d, weitererzählt %d" % [int(c["independent"]), int(c["retold"])]) if int(c["independent"]) > 1 or int(c["retold"]) > 0 else ""])
	if hs.is_empty():
		L.append("  nichts gehört")
	if ctx.comm != null:
		var us := ctx.comm.recent(3, cr.id)
		if not us.is_empty():
			L.append("[b]Gespräche[/b]")
			for u in us:
				L.append("  t=%.0f s #%d → #%d (%s) %s%s" % [float(u["t"]), int(u["speaker"]), int(u["listener"]), str(u["via"]), str(u["text"]),
					(" [i](Modelltext ohne Wirkung: %s)[/i]" % str(u["model_text"])) if str(u.get("model_text", "")) != "" else ""])
	return L

