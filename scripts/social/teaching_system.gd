class_name TeachingSystem
extends RefCounted
## Weitergabe praktischen Wissens (Prompt 6): erklären, Vorführung anbieten, zusehen, selbst üben.
##
## Wege und was sie höchstens bewirken:
##   explain_procedure (Gespräch)          → Lernender: „gehört“ (Hörensagen, Quelle gespeichert)
##   offer_demo (Gespräch)                 → Lernender: Angebot im Eingang, kann zusehen
##   Vorführung/fremder Versuch WAHRNEHMEN → Zuschauer: „zugesehen“ (nur wer es tatsächlich sieht)
##   practice_procedure (eigenes Tun)      → „versucht“ / „erfolgreich“ (ExperimentSystem)
## Freier Text schaltet nichts frei; wirksam sind nur die strukturierten Inhalte. Der Lernende
## erhält nie die internen Daten des Lehrers (Versuchsprotokolle, exakte Werte, Geschick).

const OBSERVED_TYPES := ["object_struck", "parts_connected", "metal_poured", "procedure_demonstrated", "demonstration_started", "connection_broken"]


## Thema „Vorführung anbieten“ (strukturiert).
static func offer_topic(cr: Creature, key: String, ctx: LifeContext) -> Dictionary:
	return {"absicht": "offer_demo", "about": "Vorführung: %s" % ProceduralKnowledge.describe_key(key), "eigene_sicherheit": 1.0,
		"statement": {"type": "procedure", "key": key, "id": 0, "steps": ProceduralKnowledge.template_steps(key), "level": ProceduralKnowledge.level(cr, key)},
		"source": {"kind": "eigene_erfahrung", "creature": cr.id, "t": ctx.now(), "chain": []}}


## Thema „Verfahren erklären“ aus eigenem Wissen (mind. „zugesehen“) oder Weitererzählen (gehört).
static func explain_topics(s: Creature, listener_id: int, ctx: LifeContext) -> Array:
	var out: Array = []
	if s.tech.is_empty():
		return out
	var procs: Dictionary = s.tech["procedures"]
	var keys := procs.keys()
	keys.sort()
	for key in keys:
		var e: Dictionary = procs[key]
		var lv := str(e["level"])
		var expl: Dictionary = s.tech["explained"].get(str(listener_id), {})
		if expl.has(key):
			continue
		var origin := s.id
		var chain: Array = []
		var kind := "eigene_erfahrung"
		if lv == "gehört":
			var src: Array = e["heard"]["sources"]
			if src.is_empty():
				continue
			origin = int(src[-1]["origin"])
			if origin == listener_id:
				continue
			kind = "hörensagen"
			chain = [int(src[-1]["speaker"])]
		elif lv == "zugesehen":
			kind = "beobachtung"
		out.append({"absicht": "explain_procedure", "about": "Verfahren: %s (%s)" % [e["label"], ProceduralKnowledge.LEVEL_LABEL.get(lv, lv)],
			"eigene_sicherheit": snappedf(clampf(float(e["confidence"]), 0.1, 1.0), 0.01),
			"statement": {"type": "procedure", "key": key, "id": 0, "steps": (e["steps"] as Array).duplicate(true), "level": lv, "materials": (e["materials"] as Array).duplicate()},
			"source": {"kind": kind, "creature": origin, "t": float(e["last_t"]), "chain": chain}})
		if out.size() >= 2:
			break
	return out


static func mark_explained(cr: Creature, listener: int, key: String, ctx: LifeContext) -> void:
	var ex: Dictionary = cr.tech["explained"]
	if not ex.has(str(listener)):
		ex[str(listener)] = {}
	ex[str(listener)][key] = ctx.now()


## Zustellung einer gehörten Äußerung mit Verfahrensbezug (CommunicationSystem.deliver).
static func hear(l: Creature, u: Dictionary, ctx: LifeContext) -> Dictionary:
	var st: Dictionary = u["statement"]
	var key := str(st.get("key", ""))
	if key == "" or not (ProceduralKnowledge.kind_of(key) in ["schlagen", "verbinden", "giessen"]):
		return {"status": "ungültig"}
	var src: Dictionary = u["source"]
	match str(u["intent"]):
		"explain_procedure":
			var origin := int(src.get("creature", int(u["speaker"])))
			ProceduralKnowledge.record_heard(ctx, l, key, int(u["speaker"]), origin, str(st.get("level", "")))
			return {"status": "als Hörensagen gespeichert"}
		"offer_demo":
			var offers: Array = l.tech["offers"]
			offers.append({"from": int(u["speaker"]), "key": key, "t": ctx.now(), "expires_t": ctx.now() + 40.0})
			while offers.size() > 4:
				offers.pop_front()
			return {"status": "Vorführung angeboten"}
	return {"status": "ungültig"}


## Wahrgenommenes Ereignis → „zugesehen“ (nur Zuschauer; der Handelnde selbst verbucht über Versuche).
static func on_observation(cr: Creature, obs: Observation, ctx: LifeContext) -> void:
	if cr.tech.is_empty() or not (obs.event_type in OBSERVED_TYPES) or obs.actor_id == cr.id or obs.actor_id == 0:
		return
	var c := obs.consequences
	var key := ""
	var success := false
	var demo := false
	match obs.event_type:
		"procedure_demonstrated":
			key = str(c.get("verfahren", ""))
			success = bool(c.get("erfolg", false))
			demo = true
		"parts_connected":
			key = str(c.get("verfahren", ""))
			success = true
		"metal_poured":
			key = str(c.get("verfahren", ""))
			success = true
		"object_struck":
			key = str(c.get("verfahren", ""))
			success = str(c.get("effect", "")) == "fractured" or float(c.get("sichtbare_stauchung", 0.0)) >= 0.02
			# Einzelschläge nur selten verbuchen (sonst zählte jeder Schlag als eigener Versuch)
			var last: Dictionary = cr.tech.get("seen_strikes", {})
			var lk := "%d|%s" % [obs.actor_id, key]
			if ctx.now() - float(last.get(lk, -1.0e9)) < 10.0 and not success:
				return
			last[lk] = ctx.now()
			cr.tech["seen_strikes"] = last
		"demonstration_started":
			if obs.target_id == cr.id:
				cr.tech["watching"] = {"teacher": obs.actor_id, "key": str(c.get("verfahren", "")), "until": ctx.now() + 30.0}
			return
		_:
			return
	if key == "":
		return
	ProceduralKnowledge.record_observed(ctx, cr, key, obs.actor_id, success, demo)


# ── Optionen (DecisionSystem über ExperimentSystem.options) ──

static func options(cr: Creature, ctx: LifeContext, free: float) -> Array:
	var out: Array = []
	var tc: Dictionary = ctx.tc("teaching")
	var pers := cr.personality
	var now := ctx.now()
	var range_m := float(ctx.m("communication").get("range_m", 4.0))
	# Zusehen bei angebotener Vorführung
	var offers: Array = cr.tech["offers"]
	for o in offers.duplicate():
		if now > float(o["expires_t"]):
			offers.erase(o)
	for o in offers:
		var t := ctx.creature(int(o["from"]))
		if t == null or not t.alive:
			continue
		out.append({"id": "tech:watch", "goal": "watch", "u": float(tc.get("watch_weight", 0.3)) * (0.5 + pers.v("neugier")) * free,
			"parts": {"lernen": float(tc.get("watch_weight", 0.3)) * (0.5 + pers.v("neugier")) * free}, "target": t.id, "key": str(o["key"])})
		break
	# Vorführen (nur selbst erfolgreich) – braucht echte Gegenstände in der Nähe
	for v in cr.visible_creatures:
		if not v["alive"] or float(v["d"]) > range_m:
			continue
		var lid := int(v["id"])
		var taught: Dictionary = cr.tech["taught"].get(lid, {})
		for key in cr.tech["procedures"]:
			var e: Dictionary = cr.tech["procedures"][key]
			if str(e["level"]) != "erfolgreich" or now - float(taught.get(key, -1.0e9)) < float(tc.get("offer_cooldown_s", 120.0)):
				continue
			var plan := _demo_plan(cr, key, lid, ctx)
			if plan.is_empty():
				continue
			var u := float(tc.get("teach_weight", 0.25)) * (0.4 + pers.v("hilfsbereitschaft")) * (0.5 + 0.5 * pers.v("geselligkeit")) * free
			out.append({"id": "tech:teach", "goal": "teach", "u": u, "parts": {"weitergeben": u}, "plan": plan, "target": lid})
			break
		if not out.is_empty() and out[-1]["id"] == "tech:teach":
			break
	# Erklären (Gespräch) – auch ohne Gegenstände
	if ctx.comm != null and now >= float(cr.ai.get("talk", {}).get("next_t", 0.0)):
		for v in cr.visible_creatures:
			if not v["alive"] or float(v["d"]) > range_m:
				continue
			var tps := explain_topics(cr, int(v["id"]), ctx)
			if tps.is_empty():
				continue
			var u2 := float(tc.get("teach_weight", 0.25)) * 0.5 * pers.v("geselligkeit") * free * float(tps[0]["eigene_sicherheit"])
			out.append({"id": "tech:explain", "goal": "talk", "u": u2, "parts": {"mitteilung": u2}, "target": int(v["id"]), "topic": tps[0]})
			break
	# Üben (gehört/zugesehen/versucht, aber noch nicht erfolgreich)
	if ctx.experiments != null and ctx.experiments.blocked_reason(cr, ctx) == "":
		for key in cr.tech["procedures"]:
			var e2: Dictionary = cr.tech["procedures"][key]
			if not (str(e2["level"]) in ["gehört", "zugesehen", "versucht"]):
				continue
			var plan2 := _practice_plan(cr, key, ctx)
			if plan2.is_empty():
				continue
			var u3 := float(tc.get("practice_weight", 0.3)) * (0.3 + pers.v("neugier") + 0.3 * pers.v("beharrlichkeit")) * free
			out.append({"id": "tech:practice", "goal": "experiment", "u": u3, "parts": {"üben": u3}, "plan": plan2})
			break
	return out


## Benötigte Gegenstände aus dem EIGENEN Wissen des Wesens (wahrgenommen, in der Nähe, frei).
static func _find(cr: Creature, ctx: LifeContext, pred: Callable) -> int:
	var rad := float(ctx.tc("experiments").get("candidate_radius_m", 8.0))
	var best := 0
	var bd := 1.0e9
	for id in cr.tech["objects"]:
		var e: Dictionary = cr.tech["objects"][id]
		var top := ConstructionSystem.top_id(ctx, int(id))
		if top != int(id) or top == 0:
			continue
		var c := ConstructionSystem.carrier_of(ctx, top)
		if c != 0 and c != cr.id:
			continue
		if ConstructionSystem.container_of(ctx, top) != 0:
			continue
		var p = ctx.position_of(top)
		if p == null:
			continue
		var d := ctx.distance_xz(cr.position, p)
		if d <= rad and d < bd and pred.call(e):
			bd = d
			best = top
	return best


static func _roles_for(cr: Creature, key: String, ctx: LifeContext) -> Dictionary:
	var p := key.split(":")
	match p[0]:
		"schlagen":
			var tt := p[2].split(">")
			var contact := p[1]
			var form := tt[0]
			var target_mat := tt[1] if tt.size() > 1 else ""
			var tool := 0
			if form != "Hand":
				tool = cr.held_object_id if cr.held_object_id != 0 and _matches_tool(cr, cr.tech["objects"].get(cr.held_object_id, {}), contact, form) else \
					_find(cr, ctx, func(e): return _matches_tool(cr, e, contact, form))
				if tool == 0:
					return {}
			var target := _find(cr, ctx, func(e): return str(e.get("aussehen", "")) == target_mat and str(e.get("form", "")) in ["block", "lump", "ingot"] and int(e["id"]) != tool)
			if target == 0:
				return {}
			return {"tool": tool, "target": target, "form": form}
		"verbinden":
			var hh := p[2].split("+")
			var handle := _find(cr, ctx, func(e): return str(e.get("form", "")) == "rod" and str(e.get("aussehen", "")) == hh[0])
			var head := _find(cr, ctx, func(e): return str(e.get("form", "")) in ConnectionDefinition.HEAD_SHAPES and str(e.get("aussehen", "")) == (hh[1] if hh.size() > 1 else ""))
			var fiber := _find(cr, ctx, func(e): return str(e.get("form", "")) == "bundle" and str(e.get("aussehen", "")) == "plant_fiber")
			if handle == 0 or head == 0 or fiber == 0 or handle == head:
				return {}
			return {"handle": handle, "head": head, "fiber": fiber}
	return {}


static func _matches_tool(_cr: Creature, e: Dictionary, contact: String, form: String) -> bool:
	if e.is_empty():
		return false
	match form:
		"Stiel+Kopf":
			if not e.get("assembly", false):
				return false
			for p in e.get("parts", []):
				if str(p.get("rolle", "")) == "head" and str(p.get("aussehen", "")) == contact:
					return true
			return false
		"Stück":
			return not e.get("assembly", false) and str(e.get("aussehen", "")) == contact and str(e.get("form", "")) in ConnectionDefinition.HEAD_SHAPES
		"Stab":
			return str(e.get("form", "")) == "rod" and str(e.get("aussehen", "")) == contact
	return false


static func _demo_plan(cr: Creature, key: String, learner: int, ctx: LifeContext) -> Dictionary:
	var roles := _roles_for(cr, key, ctx)
	if roles.is_empty():
		return {}
	var steps: Array = [{"op": "offer_demo", "learner": learner, "key": key}]
	match ProceduralKnowledge.kind_of(key):
		"schlagen":
			if int(roles["tool"]) != 0:
				steps.append({"op": "equip", "obj": int(roles["tool"])})
			steps.append({"op": "demonstrate", "learner": learner, "key": key, "target_piece": int(roles["target"])})
		"verbinden":
			steps.append({"op": "release"})
			steps.append({"op": "demonstrate", "learner": learner, "key": key, "handle": int(roles["handle"]), "head": int(roles["head"]), "fiber": int(roles["fiber"])})
		_:
			return {}
	return {"kind": "demonstrate", "question": "Kann #%d sehen, wie „%s“ geht?" % [learner, ProceduralKnowledge.describe_key(key)], "expected": "Zuschauer sieht das Verfahren",
		"steps": steps, "source": "Vorführung", "procedure_key": key, "learner": learner}


static func _practice_plan(cr: Creature, key: String, ctx: LifeContext) -> Dictionary:
	var roles := _roles_for(cr, key, ctx)
	if roles.is_empty():
		return {}
	var steps: Array = []
	match ProceduralKnowledge.kind_of(key):
		"schlagen":
			steps.append({"op": "release"} if int(roles["tool"]) == 0 else {"op": "equip", "obj": int(roles["tool"])})
			steps.append({"op": "practice", "key": key, "target_piece": int(roles["target"]), "params": {"strikes": 6}})
		"verbinden":
			steps.append({"op": "release"})
			steps.append({"op": "practice", "key": key, "handle": int(roles["handle"]), "head": int(roles["head"]), "fiber": int(roles["fiber"])})
		_:
			return {}
	return {"kind": "practice", "question": "Gelingt mir „%s“ selbst?" % ProceduralKnowledge.describe_key(key), "expected": "Verfahren gelingt",
		"steps": steps, "source": "Übung", "procedure_key": key}


## Zusehen: in Sichtweite des Lehrers gehen bzw. warten (die Vorführung selbst wirkt über Wahrnehmung).
static func execute_watch(cr: Creature, o: Dictionary, ctx: LifeContext) -> Dictionary:
	var t := ctx.creature(int(o["target"]))
	if t == null or not t.alive:
		return {"ok": false, "state": "", "reason": "Lehrer nicht mehr da"}
	var offers: Array = cr.tech["offers"]
	cr.tech["offers"] = offers.filter(func(x): return int(x["from"]) != t.id)
	cr.tech["watching"] = {"teacher": t.id, "key": str(o["key"]), "until": ctx.now() + float(ctx.tc("teaching").get("watch_wait_s", 12.0))}
	if ctx.distance_xz(cr.position, t.position) > 2.5:
		var dirv := cr.position - t.position
		dirv.y = 0.0
		var p := t.position + (dirv.normalized() if dirv.length() > 0.01 else Vector3.RIGHT) * 1.6
		var r := ctx.executor.request(cr.id, "move_to", 0, Vector3(p.x, t.position.y, p.z), {"arrive_radius_m": 0.5})
		return {"ok": r["result"].ok, "state": "geht_zuschauen", "reason": "Geht zu #%d, um bei „%s“ zuzusehen." % [t.id, ProceduralKnowledge.describe_key(str(o["key"]))] if r["result"].ok else r["result"].message}
	return BasicBehavior.wait(cr, ctx, float(ctx.tc("teaching").get("watch_wait_s", 12.0)), "sieht_zu", "Sieht #%d bei „%s“ zu." % [t.id, ProceduralKnowledge.describe_key(str(o["key"]))])
