class_name ContextBuilder
extends RefCounted
## Baut den Kontext EINER Modellanfrage ausschließlich aus den Daten DIESES Wesens:
## Identität, Fähigkeiten, Bedürfnisse, Persönlichkeit, eigene Wahrnehmung, eigene Erinnerungen,
## eigene Vermutungen (mit Unsicherheit), eigene Beziehungen, Gehörtes (als Hörensagen gekennzeichnet),
## aktuelles Ziel, erlaubte Handlungen, begrenzte Kandidaten-IDs.
## NIE enthalten: Weltzustand, verborgene Eigenschaften anderer (Persönlichkeit, Hunger, Gedächtnis …),
## Absichten des Spielers, nicht beobachtete Ereignisse, Erinnerungen anderer Wesen, Technologiebaum,
## freie Modelltexte anderer Wesen (verhindert Weitergabe eingeschleuster Anweisungen).
## Größe ist begrenzt (max_context_chars); Listen werden notfalls gekürzt.

const PLAN_ACTIONS := ["go_to", "pick_up", "eat", "give_food", "request_food", "offer_food", "wait", "explore", "raise_arms", "talk"]
const GOAL_TYPES := ["food", "ask_food", "offer_food", "approach", "explore", "rest", "talk", "repeat_learned", "keep_current"]


## Rückgabe {"context": Dictionary, "json": String, "cand": {"food": [ids], "creatures": [ids], "memories": [ids], "topics": {id: topic}},
##           "allowed": [Handlungen], "state_t": float, "chars": int}
static func build(cr: Creature, ctx: LifeContext, kind: String, request_id: int, reason: String, max_chars: int, listener_id: int = 0) -> Dictionary:
	var now := ctx.now()
	var cand := {"food": [], "creatures": [], "memories": [], "topics": {}}
	var c := {}
	c["anfrage"] = {"request_id": request_id, "art": kind, "anlass": reason, "zeit_s": snappedf(now, 0.1)}
	c["ich"] = {"id": cr.id, "name": cr.display_name}
	c["faehigkeiten"] = {"gehen": bool(cr.caps.get("can_walk", false)), "greifen": float(cr.caps.get("grasp", 0.0)) > 0.0,
		"essen": float(cr.caps.get("mouth", 0.0)) > 0.0, "gesten": float(cr.caps.get("gesture", 0.0)) > 0.0,
		"sehweite_m": snappedf(float(ctx.c("perception").get("radius_m", 10.0)) * float(cr.caps.get("perception", 1.0)), 0.1)}
	var inj: Array = []
	for pid in cr.health.part_damage:
		if float(cr.health.part_damage[pid]) > 0.05:
			inj.append(pid)
	c["beduerfnisse"] = {"hunger": snappedf(cr.metabolism.hunger(), 0.01), "energie": snappedf(cr.metabolism.energy_fraction(), 0.01),
		"verletzte_teile": inj.slice(0, 4), "traegt_nahrung": cr.carried_item_id != 0}
	var pers := {}
	for k in cr.personality.values:
		pers[k] = snappedf(float(cr.personality.values[k]), 0.01)
	c["persoenlichkeit"] = pers
	# Wahrnehmung (eigene, letzte Abtastung)
	var vf: Array = []
	for fid in cr.visible_food:
		if cr.food_memory.has(fid):
			var m: Dictionary = cr.food_memory[fid]
			vf.append({"id": fid, "entfernung_m": snappedf(ctx.distance_xz(cr.position, _v(m["pos"])), 0.1), "art": str(m.get("kind", ""))})
	var vc: Array = []
	for v in cr.visible_creatures:
		vc.append({"id": int(v["id"]), "entfernung_m": snappedf(float(v["d"]), 0.1), "lebt": bool(v["alive"]), "traegt_etwas": bool(v["carrying"])})
	c["wahrnehmung"] = {"nahrung_sichtbar": vf.slice(0, 5), "wesen_sichtbar": vc.slice(0, 5)}
	# Erinnerungen (eigene, wichtigste zuerst)
	var mems: Array = []
	for e in cr.memory.recall({}, now, ctx.mind_cfg, 6):
		mems.append({"id": int(e["id"]), "art": str(e["type"]), "vor_s": snappedf(now - float(e["t_last"]), 1.0), "anzahl": int(e["count"]),
			"sicherheit": snappedf(float(e["certainty"]), 0.01), "handelnder": int(e["actor"]), "ziel": int(e["target"])})
		cand["memories"].append(int(e["id"]))
	c["erinnerungen"] = mems
	# Vermutungen mit Unsicherheit
	var bel: Array = []
	for k in cr.beliefs.items:
		var h: Dictionary = cr.beliefs.items[k]
		if h["kind"] == "gift_base":
			continue
		bel.append({"aussage": BeliefStore.statement(h), "haeufigkeit": snappedf(cr.beliefs.p(k), 0.01), "konfidenz": snappedf(cr.beliefs.confidence(k, ctx.mind_cfg), 0.01)})
	bel.sort_custom(func(a, b): return float(a["konfidenz"]) > float(b["konfidenz"]))
	c["vermutungen"] = bel.slice(0, 4)
	# Beziehungen (eigene Einschätzungen)
	var rels: Array = []
	for oid in cr.relations.rel:
		var r: Dictionary = cr.relations.rel[oid]
		rels.append({"id": int(oid), "vertrauen": snappedf(cr.relations.trust(oid), 0.01), "vertrautheit": snappedf(float(r["familiarity"]), 0.01),
			"hilfe_erhalten": int(r["help_received"]), "ablehnungen": int(r["declines"])})
	rels.sort_custom(func(a, b): return float(a["vertrautheit"]) > float(b["vertrautheit"]))
	c["beziehungen"] = rels.slice(0, 4)
	# Gehörtes – nur strukturiert, nie fremder Freitext
	var hs: Array = []
	if not cr.ai.is_empty():
		for h2 in cr.ai["hearsay"]:
			hs.append({"von": int(h2["speaker"]), "ursprung": int(h2["origin"]["creature"]), "absicht": str(h2["intent"]),
				"gegenstand": int(h2["subject"].get("id", 0)), "sicherheit": snappedf(float(h2["certainty"]), 0.01), "status": str(h2["status"])})
	c["gehoertes_hoerensagen"] = hs.slice(maxi(0, hs.size() - 3))
	c["aktuelles_ziel"] = {"typ": str(cr.goal_state.get("type", "")), "seit_s": snappedf(now - float(cr.goal_state.get("started_t", now)), 1.0)}
	c["letztes_ergebnis"] = {"handlung": str(cr.last_result.get("type", "")), "status": str(cr.last_result.get("status", "")), "code": str(cr.last_result.get("code", ""))}
	c["fehlschlaege_in_folge"] = int(cr.ai.get("fail_streak", 0)) if not cr.ai.is_empty() else 0
	# Kandidaten
	var kfood: Array = []
	for fid in cr.food_memory:
		if cr.unreachable.has(fid):
			continue
		var m2: Dictionary = cr.food_memory[fid]
		if float(m2["available_kg"]) <= 1e-6:
			continue
		kfood.append({"id": int(fid), "entfernung_m": snappedf(ctx.distance_xz(cr.position, _v(m2["pos"])), 0.1),
			"menge_kg_geschaetzt": snappedf(float(m2["available_kg"]), 0.01), "gesehen_vor_s": snappedf(now - float(m2["seen_t"]), 1.0),
			"art": "gegenstand" if str(m2.get("kind", "")) == "item" else str(m2.get("kind", ""))})
	kfood.sort_custom(func(a, b): return float(a["entfernung_m"]) < float(b["entfernung_m"]))
	kfood = kfood.slice(0, 6)
	for f in kfood:
		cand["food"].append(int(f["id"]))
	var kcr: Array = []
	for v2 in cr.visible_creatures:
		if v2["alive"]:
			kcr.append({"id": int(v2["id"]), "entfernung_m": snappedf(float(v2["d"]), 0.1)})
			cand["creatures"].append(int(v2["id"]))
	kcr = kcr.slice(0, 5)
	cand["creatures"] = cand["creatures"].slice(0, 5)
	c["kandidaten"] = {"nahrung": kfood, "wesen": kcr, "erinnerungen": cand["memories"].duplicate()}
	var allowed: Array = allowed_actions(cr)
	if kind == "talk":
		allowed = []
		var tps: Array = ctx.comm.topics(cr, listener_id, ctx) if ctx.comm != null else []
		var shown: Array = []
		for tp in tps:
			cand["topics"][int(tp["thema_id"])] = tp
			shown.append({"thema_id": int(tp["thema_id"]), "absicht": str(tp["absicht"]), "inhalt": str(tp["about"]), "eigene_sicherheit": float(tp["eigene_sicherheit"])})
		c["kandidaten"]["themen"] = shown
		var lw := ctx.creature(listener_id)
		c["zuhoerer"] = {"id": listener_id, "entfernung_m": snappedf(ctx.distance_xz(cr.position, lw.position), 0.1) if lw != null else -1.0,
			"vertrauen": snappedf(cr.relations.trust(listener_id), 0.01)}
	elif kind == "interpret":
		allowed = []
	elif kind == "work":
		# Prompt 6B: Arbeitsvorschlag nach gescheiterter Kette – nur eigenes Wissen des Wesens
		allowed = []
		var tkw := tech_context(cr, ctx)
		c["technik"] = tkw["context"]
		cand["objects"] = tkw["objects"]
		cand["heaters"] = tkw["heaters"]
		var wk := work_context(cr, ctx)
		c["arbeit"] = wk["context"]
		cand["storages"] = wk["storages"]
		cand["sites"] = wk["sites"]
		c["kandidaten"] = {"erinnerungen": []}
		cand["memories"] = []
		c["erinnerungen"] = []
	elif kind == "experiment":
		allowed = []
		var tk := tech_context(cr, ctx)
		c["technik"] = tk["context"]
		cand["objects"] = tk["objects"]
		cand["heaters"] = tk["heaters"]
		# Nahrung/Erinnerungen sind für einen Versuchsvorschlag nicht nötig (Kontext klein halten)
		c["kandidaten"] = {"erinnerungen": []}
		cand["memories"] = []
		c["erinnerungen"] = []
	c["erlaubte_handlungen"] = allowed
	if kind != "experiment" and kind != "work":
		c["erlaubte_zieltypen"] = GOAL_TYPES if kind == "plan" else ["keep_current"]
	# Größe begrenzen
	var js := JSON.stringify(c)
	var guard := 0
	while js.length() > max_chars and guard < 12:
		guard += 1
		for key in ["gehoertes_hoerensagen", "beziehungen", "vermutungen", "erinnerungen"]:
			if c[key].size() > 1:
				c[key] = c[key].slice(0, c[key].size() - 1)
		c["wahrnehmung"]["nahrung_sichtbar"] = c["wahrnehmung"]["nahrung_sichtbar"].slice(0, maxi(1, c["wahrnehmung"]["nahrung_sichtbar"].size() - 1))
		c["wahrnehmung"]["wesen_sichtbar"] = c["wahrnehmung"]["wesen_sichtbar"].slice(0, maxi(1, c["wahrnehmung"]["wesen_sichtbar"].size() - 1))
		js = JSON.stringify(c)
	var keep: Array = []
	for e2 in c["erinnerungen"]:
		keep.append(int(e2["id"]))
	cand["memories"] = keep
	if c["kandidaten"].has("erinnerungen"):
		c["kandidaten"]["erinnerungen"] = keep.duplicate()
	js = JSON.stringify(c)
	return {"context": c, "json": js, "cand": cand, "allowed": allowed, "state_t": now, "chars": js.length(), "fits": js.length() <= max_chars}


## Technikkontext (Prompt 6) – NUR das eigene Wissen des Wesens: wahrgenommene Gegenstände mit
## wahrnehmbaren Kategorien (keine exakten Werte, keine fremden Gegenstände), eigene Verfahren mit
## Erfahrungsstand, eigene letzte Versuche, zulässige Vorgänge. Kein weltweiter Technologiebaum.
static func tech_context(cr: Creature, ctx: LifeContext) -> Dictionary:
	var objs: Array = []
	var heaters: Array = []
	var hl: Array = []
	var rad := float(ctx.tc("experiments").get("candidate_radius_m", 8.0))
	for id in cr.tech["objects"]:
		var e: Dictionary = cr.tech["objects"][id]
		if e.get("heater", false):
			heaters.append(int(id))
			hl.append({"id": int(id), "art": "Heizkiste (Testausrüstung, extern versorgt)", "entfernung_m": float(e.get("d", 0.0))})
			continue
		if ConstructionSystem.top_id(ctx, int(id)) != int(id):
			continue
		var p = ctx.position_of(int(id))
		if p == null or ctx.distance_xz(cr.position, p) > rad:
			continue
		var o := {"id": int(id), "aussehen": ProceduralKnowledge._mat(str(e.get("aussehen", "?"))), "form": str(e.get("form", "?")),
			"entfernung_m": snappedf(ctx.distance_xz(cr.position, p), 0.1)}
		for k in ["haerte", "gewicht", "temperatur", "klang"]:
			if e.has(k):
				o[k] = e[k]
		if e.get("assembly", false):
			var parts: Array = []
			for pp in e.get("parts", []):
				parts.append({"rolle": str(pp.get("rolle", "")), "aussehen": ProceduralKnowledge._mat(str(pp.get("aussehen", "")))})
			o["teile"] = parts
		objs.append(o)
	objs.sort_custom(func(a, b): return float(a["entfernung_m"]) < float(b["entfernung_m"]))
	objs = objs.slice(0, 8)
	var ids: Array = []
	for o in objs:
		ids.append(int(o["id"]))
	var procs: Array = []
	for key in cr.tech["procedures"]:
		var pe: Dictionary = cr.tech["procedures"][key]
		procs.append({"verfahren": str(pe["label"]), "stand": ProceduralKnowledge.LEVEL_LABEL.get(str(pe["level"]), ""), "sicherheit": snappedf(float(pe["confidence"]), 0.01)})
	var exps: Array = []
	if ctx.experiments != null:
		for r in ctx.experiments.of_creature(cr.id).slice(0, 3):
			exps.append({"frage": (r as ExperimentRecord).question, "status": r.status, "ergebnis": r.outcome})
	var problem := "Etwas Nützliches mit den bekannten Gegenständen herausfinden."
	if not exps.is_empty() and str(exps[0]["status"]) == "fehlgeschlagen":
		problem = "Letzter Versuch misslang: %s" % str(exps[0]["ergebnis"])
	return {"context": {"problem": problem, "bekannte_gegenstaende": objs, "heizungen": hl.slice(0, 2), "eigene_verfahren": procs.slice(0, 6),
		"eigene_versuche": exps, "erlaubte_vorgaenge": ["inspect", "equip", "release", "strike", "deform", "connect", "disconnect", "heat", "wait_molten", "pour"],
		"hinweis": "Schritte: equip(object_id) nimmt in die Hand; deform(target_id, strikes) schlägt mehrmals mit dem Gehaltenen; connect(object_id=Stiel, head_id, fiber_id); heat(object_id=Tiegel, heater_id); wait_molten(object_id=Tiegel); pour(object_id=Tiegel, mold_id)."},
		"objects": ids, "heaters": heaters.slice(0, 2)}


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Arbeitskontext (Prompt 6B): letzte eigene Kette (Ziel, Status, Grund), bekannte Lager/Baustellen,
## erlaubte Arbeitsschritte. Nur Wahrgenommenes; keine fremden Gegenstände, keine exakten Messwerte.
static func work_context(cr: Creature, ctx: LifeContext) -> Dictionary:
	var storages: Array = []
	var sites: Array = []
	var ls: Array = []
	var bs: Array = []
	for id in cr.tech.get("objects", {}):
		var e: Dictionary = cr.tech["objects"][id]
		if e.get("lager", false) and ctx.storages.has(int(id)):
			storages.append(int(id))
			ls.append({"id": int(id), "platz_frei": bool(e.get("platz_frei", true)), "entfernung_m": snappedf(float(e.get("d", 0.0)), 0.1)})
		if e.get("bauwerk", false) and ctx.structures.has(int(id)):
			var st: Structure = ctx.structures[int(id)]
			sites.append(int(id))
			bs.append({"id": int(id), "bauplan": st.blueprint, "plaetze_frei": st.slots.size() - st.filled(), "eigene": st.initiator == cr.id})
	var last := {}
	if ctx.work != null:
		var past := ctx.work.of_creature(cr.id)
		if not past.is_empty():
			var w: WorkChain = past[0]
			last = {"kette": w.id, "ziel": w.goal, "status": w.status, "grund": w.abort_reason.substr(0, 160), "werkzeug": w.tool_id}
	var ops: Array = WorkSystem.OPS.duplicate()
	ops.erase("mark_site")
	return {"context": {"letzte_kette": last, "lager": ls.slice(0, 3), "baustellen": bs.slice(0, 3), "erlaubte_schritte": ops},
		"storages": storages.slice(0, 3), "sites": sites.slice(0, 3)}


## Erlaubte Planhandlungen nach eigenen Fähigkeiten.
static func allowed_actions(cr: Creature) -> Array:
	var out: Array = ["wait"]
	var walk := bool(cr.caps.get("can_walk", false))
	if walk:
		out.append_array(["go_to", "explore"])
	if float(cr.caps.get("grasp", 0.0)) > 0.0:
		out.append_array(["pick_up", "give_food", "offer_food"])
	if float(cr.caps.get("mouth", 0.0)) > 0.0:
		out.append("eat")
	out.append_array(["request_food", "talk"])
	if float(cr.caps.get("gesture", 0.0)) > 0.0:
		out.append("raise_arms")
	return out


## Nachrichten für /api/chat: Systemanweisung (Datei) + Kontext als JSON + Schema als Text (Empfehlung der Ollama-Doku).
static func messages(kind: String, context_json: String, schema: Dictionary) -> Array:
	var f := "res://data/ai/prompts/%s_system.txt" % ("talk" if kind == "talk" else ("experiment" if kind == "experiment" else ("work" if kind == "work" else "plan")))
	var sys := FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else "Antworte nur mit JSON nach Schema."
	sys += "\n\nSchema:\n" + JSON.stringify(schema)
	return [{"role": "system", "content": sys}, {"role": "user", "content": context_json}]
