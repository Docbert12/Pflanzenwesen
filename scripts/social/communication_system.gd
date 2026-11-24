class_name CommunicationSystem
extends RefCounted
## Kurze direkte Gespräche zwischen nahen Wesen (Prompt 5). Weltseite der Kommunikation.
## Eine Äußerung (utterance):
##   id, t, speaker, listener, intent, statement {type, id, …}, referenced [IDs], source {kind, creature, t, chain},
##   certainty (geäußerte Sicherheit, nie höher als die eigene), text (aus VORLAGE erzeugt),
##   model_text (optionaler Modelltext, bereinigt, nur Anzeige – ohne jede Wirkung), via (lokal|ollama|simuliert),
##   status (geplant|gehört|nicht_gehört|abgebrochen)
## Absichten: ask_food → vorhandene Handlung request_food; offer_help → vorhandene Handlung offer_food;
##   point_food, share_experience, share_guess → Handlung „talk“ (1,5 s), danach Zustellung an den Zuhörer.
## Inhalte stammen ausschließlich aus dem eigenen Wissen des Sprechers (topics()). Was nicht dort steht,
## kann nicht gesagt werden – damit ist strategische Täuschung ausgeschlossen (nicht implementiert).

const INTENTS := ["ask_food", "offer_help", "point_food", "share_experience", "share_guess", "explain_procedure", "offer_demo"]
const INTENT_LABEL := {"ask_food": "bittet um Nahrung", "offer_help": "bietet Hilfe an", "point_food": "weist auf Nahrung hin",
	"share_experience": "erzählt ein Erlebnis", "share_guess": "äußert eine Vermutung", "explain_procedure": "erklärt ein Verfahren",
	"offer_demo": "bietet eine Vorführung an", "none": "nichts"}
const EXPERIENCE_TYPES := ["food_appeared", "healed", "material_appeared", "food_given", "death"]

var log: Array = []                 # zugestellte/abgebrochene Äußerungen (begrenzt)
var pending: Dictionary = {}        # utterance id -> Äußerung (während „talk“ läuft)
var next_id: int = 1
var stats := {"started": 0, "heard": 0, "not_heard": 0, "rejected": 0, "via_ollama": 0, "via_simulated": 0, "via_local": 0}


## Gesprächsthemen aus dem EIGENEN Wissen des Sprechers für einen bestimmten Zuhörer.
## Jedes Thema: {thema_id, absicht, about, eigene_sicherheit, statement, source}
func topics(s: Creature, listener_id: int, ctx: LifeContext) -> Array:
	var cc: Dictionary = ctx.m("communication")
	var now := ctx.now()
	var out: Array = []
	var lv := _visible(s, listener_id)
	var lpos = ctx.position_of(listener_id)
	var hunger := s.metabolism.hunger()
	# Bitten / Anbieten (vorhandene Handlungen)
	if not lv.is_empty() and lv["carrying"] and hunger >= float(ctx.c("behavior").get("hunger_seek_threshold", 0.6)) and s.carried_item_id == 0:
		out.append({"absicht": "ask_food", "about": "#%d trägt sichtbar Nahrung; eigener Hunger %.0f %%" % [listener_id, hunger * 100], "eigene_sicherheit": 1.0,
			"statement": {"type": "request", "id": listener_id}, "source": {"kind": "eigene_beobachtung", "creature": s.id, "t": now, "chain": []}})
	if s.carried_item_id != 0 and ctx.items.has(s.carried_item_id) and (ctx.items[s.carried_item_id] as FoodItem).reserved_by == 0 \
			and hunger < float(ctx.m("social").get("share_eat_threshold", 0.35)) and not lv.is_empty() and not lv["carrying"]:
		out.append({"absicht": "offer_help", "about": "trägt eine Portion (#%d), selbst versorgt" % s.carried_item_id, "eigene_sicherheit": 1.0,
			"statement": {"type": "offer", "id": s.carried_item_id}, "source": {"kind": "eigene_beobachtung", "creature": s.id, "t": now, "chain": []}})
	# Hinweise auf Nahrungsquellen: eigene Beobachtung …
	var foods: Array = []
	for fid in s.food_memory:
		if not ctx.foods.has(fid):
			continue
		var m: Dictionary = s.food_memory[fid]
		var age := now - float(m["seen_t"])
		if float(m["available_kg"]) <= 1e-6 or age > float(cc.get("point_food_max_age_s", 90.0)):
			continue
		var p := Vector3(m["pos"][0], m["pos"][1], m["pos"][2])
		foods.append({"fid": fid, "m": m, "age": age, "d": ctx.distance_xz(lpos, p) if lpos != null else 0.0})
	foods.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for f in foods.slice(0, 2):
		var m2: Dictionary = f["m"]
		out.append({"absicht": "point_food", "about": "Nahrungsquelle #%d (%s), selbst gesehen vor %.0f s, etwa %.2f kg, %.0f m vom Zuhörer" % [f["fid"], str(m2.get("kind", "")), f["age"], float(m2["available_kg"]), f["d"]],
			"eigene_sicherheit": snappedf(clampf(1.0 - 0.5 * float(f["age"]) / float(cc.get("point_food_max_age_s", 90.0)), 0.3, 1.0), 0.01),
			"statement": {"type": "food_source", "id": f["fid"], "pos": m2["pos"].duplicate(), "kind": str(m2.get("kind", "")), "kg": snappedf(float(m2["available_kg"]), 0.01)},
			"source": {"kind": "eigene_beobachtung", "creature": s.id, "t": float(m2["seen_t"]), "chain": []}})
	# … oder Weitererzählen von Gehörtem (bleibt Hörensagen, Herkunft bleibt erhalten)
	if not s.ai.is_empty():
		for c in s.ai["hearsay"]:
			if c["status"] != "ungeprüft" or str(c["subject"].get("type", "")) != "food_source" or listener_id in c["chain"] or int(c["origin"]["creature"]) == listener_id:
				continue
			if s.food_memory.has(int(c["subject"]["id"])):
				continue
			out.append({"absicht": "point_food", "about": "Gehört von #%d (Ursprung #%d): Nahrungsquelle #%d – nicht selbst geprüft" % [int(c["speaker"]), int(c["origin"]["creature"]), int(c["subject"]["id"])],
				"eigene_sicherheit": snappedf(clampf(float(c["certainty"]) * float(c["trust_at_hearing"]), 0.05, 0.9), 0.01), "statement": c["subject"].duplicate(true),
				"source": {"kind": "hörensagen", "creature": int(c["origin"]["creature"]), "t": float(c["origin"]["t"]), "chain": c["chain"].duplicate()}})
			break
	# Eigene Erlebnisse
	for e in s.memory.recall({"types": EXPERIENCE_TYPES, "since": now - 300.0}, now, ctx.mind_cfg, 2):
		if float(e["significance"]) < 0.4 or (e["type"] == "food_given" and int(e["target"]) != s.id):
			continue
		out.append({"absicht": "share_experience", "about": "Eigene Erinnerung %d: %s vor %.0f s (Sicherheit %.2f)" % [int(e["id"]), _event_label(str(e["type"])), now - float(e["t_last"]), float(e["certainty"])],
			"eigene_sicherheit": snappedf(float(e["certainty"]), 0.01),
			"statement": {"type": "experience", "id": int(e["id"]), "event": str(e["type"]), "pos": e["pos"].duplicate(), "t": float(e["t_last"])},
			"source": {"kind": "eigenes_erlebnis", "creature": s.id, "t": float(e["t_last"]), "chain": []}})
	# Vermutungen (mit Unsicherheit)
	var nguess := 0
	for h in s.beliefs.of_kind("gift_after_action"):
		if int(h["n_support"]) < 1 or nguess >= 2:
			continue
		nguess += 1
		var conf := s.beliefs.confidence(str(h["key"]), ctx.mind_cfg)
		out.append({"absicht": "share_guess", "about": "Vermutung: %s (Häufigkeit %.2f, Konfidenz %.2f)" % [BeliefStore.statement(h), s.beliefs.p(str(h["key"])), conf],
			"eigene_sicherheit": snappedf(conf, 0.01),
			"statement": {"type": "guess", "key": str(h["key"]), "id": 0, "subject": str(h["subject"]), "p": snappedf(s.beliefs.p(str(h["key"])), 0.01), "confidence": snappedf(conf, 0.01)},
			"source": {"kind": "vermutung", "creature": s.id, "t": float(h["updated_t"]), "chain": []}})
	# Praktisches Wissen erklären (Prompt 6) – strukturiert, wirkt beim Zuhörer höchstens als „gehört“
	out.append_array(TeachingSystem.explain_topics(s, listener_id, ctx).slice(0, 1))
	out = out.slice(0, int(cc.get("topics_max", 5)) + 1)
	for i in out.size():
		out[i]["thema_id"] = i + 1
	return out


static func _visible(s: Creature, id: int) -> Dictionary:
	for v in s.visible_creatures:
		if int(v["id"]) == id and v["alive"]:
			return v
	return {}


static func _event_label(t: String) -> String:
	return {"food_appeared": "Nahrung erschien plötzlich", "healed": "wurde geheilt", "material_appeared": "ein Gegenstand erschien",
		"food_given": "bekam Nahrung geschenkt", "death": "sah ein Wesen sterben"}.get(t, t)


## Grundvoraussetzungen eines Gesprächs. Rückgabe {"ok", "message"}.
func can_talk(s: Creature, listener_id: int, ctx: LifeContext, check_range: bool = true) -> Dictionary:
	var cc: Dictionary = ctx.m("communication")
	var now := ctx.now()
	var l := ctx.creature(listener_id)
	if s == null or not s.alive:
		return {"ok": false, "message": "Sprecher lebt nicht."}
	if l == null or not l.alive or l.id == s.id:
		return {"ok": false, "message": "Kein lebender anderer Zuhörer."}
	if s.metabolism.hunger() >= float(ctx.m("decision").get("critical_hunger", 0.8)):
		return {"ok": false, "message": "Kritischer Hunger – keine Gespräche."}
	if s.ai.is_empty():
		return {"ok": false, "message": "Keine Gesprächsdaten."}
	var t: Dictionary = s.ai["talk"]
	if now < float(t.get("next_t", 0.0)):
		return {"ok": false, "message": "Gesprächspause bis t=%.0f s." % float(t["next_t"])}
	if now < float(t["pair"].get(listener_id, 0.0)):
		return {"ok": false, "message": "Mit #%d erst wieder ab t=%.0f s." % [listener_id, float(t["pair"][listener_id])]}
	if check_range:
		var d := ctx.distance_xz(s.position, l.position)
		if d > float(cc.get("range_m", 4.0)):
			return {"ok": false, "message": "#%d ist %.1f m entfernt (Gespräch bis %.1f m)." % [listener_id, d, float(cc.get("range_m", 4.0))]}
		if not listener_perceives(s, l, ctx):
			return {"ok": false, "message": "#%d kann den Sprecher nicht wahrnehmen (keine Sichtlinie)." % listener_id}
	return {"ok": true, "message": ""}


static func listener_perceives(s: Creature, l: Creature, ctx: LifeContext) -> bool:
	var eh := float(ctx.c("perception").get("eye_height_m", 0.75))
	var eye := l.position + Vector3(0, eh, 0)
	var tp := s.position + Vector3(0, 0.5, 0)
	var reach := float(ctx.c("perception").get("radius_m", 10.0)) * float(l.caps.get("perception", 1.0))
	var d := eye.distance_to(tp)
	return d <= reach and Perception._line_of_sight(ctx, eye, tp, d)


## Lokale Gesprächsgelegenheit für die Entscheidung (ohne Modell). Rückgabe {} oder
## {"listener", "topic", "relevance"} – nur Hinweise/Erlebnisse/Vermutungen (Bitten und Anbieten
## laufen bereits über die Optionen ask_food/offer_food).
func local_opportunity(s: Creature, ctx: LifeContext) -> Dictionary:
	var cc: Dictionary = ctx.m("communication")
	if not bool(cc.get("local_enabled", true)) or s.ai.is_empty():
		return {}
	var now := ctx.now()
	if now < float(s.ai["talk"].get("next_t", 0.0)):
		return {}
	var best := {}
	for v in s.visible_creatures:
		if not v["alive"] or float(v["d"]) > float(cc.get("range_m", 4.0)):
			continue
		if now < float(s.ai["talk"]["pair"].get(int(v["id"]), 0.0)):
			continue
		var lid := int(v["id"])
		var signs := s.memory.recall({"participant": lid, "types": ["food_requested", "request_declined"], "since": now - 60.0}, now, ctx.mind_cfg, 1)
		var needs := not signs.is_empty() and int(signs[0]["actor"] if signs[0]["type"] == "food_requested" else signs[0]["target"]) == lid
		var share := not needs and s.rng.randf() < float(cc.get("share_chance", 0.15)) * 0.1
		if not needs and not share:
			continue           # Themen nur berechnen, wenn es einen Anlass gibt (spart Rechenzeit)
		var tps := topics(s, lid, ctx)
		for tp in tps:
			var rel := 0.0
			if tp["absicht"] == "point_food" and needs:
				rel = float(cc.get("hint_relevance", 0.15)) + 0.15 * float(tp["eigene_sicherheit"])
			elif tp["absicht"] in ["share_experience", "share_guess"] and share:
				rel = 0.1 + 0.1 * float(tp["eigene_sicherheit"])
			if rel > 0.0 and (best.is_empty() or rel > float(best["relevance"])):
				best = {"listener": lid, "topic": tp, "relevance": rel}
	if not best.is_empty() and not can_talk(s, int(best["listener"]), ctx)["ok"]:
		return {}
	return best


## Äußerung aus einem (geprüften) Thema bauen. Text stammt aus der Vorlage, nie vom Modell.
func make_utterance(s: Creature, listener_id: int, topic: Dictionary, via: String, ctx: LifeContext, certainty: float = -1.0, model_text: String = "") -> Dictionary:
	var own := float(topic["eigene_sicherheit"])
	var cert := own if certainty < 0.0 else minf(certainty, own)     # nie sicherer als selbst
	var u := {"id": next_id, "t": ctx.now(), "speaker": s.id, "listener": listener_id, "intent": str(topic["absicht"]),
		"statement": topic["statement"].duplicate(true), "referenced": [], "source": topic["source"].duplicate(true),
		"certainty": snappedf(cert, 0.01), "text": "", "model_text": OllamaClient.sanitize(model_text, 120) if model_text != "" else "",
		"via": via, "status": "geplant"}
	next_id += 1
	var st: Dictionary = u["statement"]
	if int(st.get("id", 0)) != 0:
		u["referenced"].append(int(st["id"]))
	u["text"] = template_text(u)
	return u


static func template_text(u: Dictionary) -> String:
	var st: Dictionary = u["statement"]
	var src: Dictionary = u["source"]
	var how := ""
	match str(src.get("kind", "")):
		"eigene_beobachtung":
			how = "selbst gesehen"
		"hörensagen":
			how = "gehört (Ursprung #%d)" % int(src.get("creature", 0))
		"eigenes_erlebnis":
			how = "selbst erlebt"
		"vermutung":
			how = "eigene Vermutung"
		"eigene_erfahrung":
			how = "selbst gemacht"
		"beobachtung":
			how = "selbst zugesehen"
	var cert := "%.0f %%" % (float(u["certainty"]) * 100.0)
	match str(u["intent"]):
		"ask_food":
			return "„Hast du Nahrung für mich?“"
		"offer_help":
			return "„Ich habe eine Portion – möchtest du sie?“"
		"point_food":
			return "„Bei Quelle #%d (%s) gab es Nahrung, etwa %.2f kg.“ (%s, Sicherheit %s)" % [int(st.get("id", 0)), str(st.get("kind", "?")), float(st.get("kg", 0.0)), how, cert]
		"share_experience":
			var first := {"food_appeared": "Bei mir erschien plötzlich Nahrung", "healed": "Ich wurde geheilt", "material_appeared": "Ein Gegenstand erschien plötzlich",
				"food_given": "Ich bekam Nahrung geschenkt", "death": "Ich sah ein Wesen sterben"}
			return "„%s.“ (%s, Sicherheit %s)" % [first.get(str(st.get("event", "")), _event_label(str(st.get("event", "")))), how, cert]
		"explain_procedure":
			return "„So geht es: %s.“ (%s, Erfahrungsstand: %s, Sicherheit %s)" % [ProceduralKnowledge.describe_key(str(st.get("key", ""))), how, ProceduralKnowledge.LEVEL_LABEL.get(str(st.get("level", "")), "?"), cert]
		"offer_demo":
			return "„Schau zu – ich zeige dir: %s.“" % ProceduralKnowledge.describe_key(str(st.get("key", "")))
		"share_guess":
			return "„Nach „%s“ kam manchmal etwas Auffälliges – ich bin nicht sicher.“ (%s, Häufigkeit %.0f %%, Sicherheit %s)" % [ActionDefinition.label(str(st.get("subject", ""))), how, float(st.get("p", 0.0)) * 100.0, cert]
	return "–"


## Gespräch beginnen (Voraussetzungen geprüft). Rückgabe {"ok", "message", "utterance"}.
func start(s: Creature, listener_id: int, topic: Dictionary, via: String, ctx: LifeContext, certainty: float = -1.0, model_text: String = "") -> Dictionary:
	var ck := can_talk(s, listener_id, ctx)
	if not ck["ok"]:
		stats["rejected"] += 1
		return {"ok": false, "message": ck["message"], "utterance": {}}
	var cc: Dictionary = ctx.m("communication")
	var u := make_utterance(s, listener_id, topic, via, ctx, certainty, model_text)
	var r: Dictionary
	match str(u["intent"]):
		"ask_food":
			r = ctx.executor.request(s.id, "request_food", listener_id)
		"offer_help":
			r = ctx.executor.request(s.id, "offer_food", listener_id)
		_:
			pending[int(u["id"])] = u
			r = ctx.executor.request(s.id, "talk", listener_id, null, {"utterance": int(u["id"])})
			if not r["result"].ok:
				pending.erase(int(u["id"]))
	if not r["result"].ok:
		stats["rejected"] += 1
		return {"ok": false, "message": r["result"].message, "utterance": u}
	var now := ctx.now()
	s.ai["talk"]["next_t"] = now + float(cc.get("speaker_cooldown_s", 25.0))
	s.ai["talk"]["pair"][listener_id] = now + float(cc.get("pair_cooldown_s", 90.0))
	stats["started"] += 1
	stats["via_" + ("ollama" if via == "ollama" else ("simulated" if via == "simuliert" else "local"))] += 1
	if u["intent"] in ["ask_food", "offer_help"]:
		u["status"] = "über Handlung „%s“" % ActionDefinition.label("request_food" if u["intent"] == "ask_food" else "offer_food")
		_append(u, ctx)
	return {"ok": true, "message": "%s → #%d: %s" % [INTENT_LABEL.get(u["intent"], u["intent"]), listener_id, u["text"]], "utterance": u}


## Abschluss der Handlung „talk“: zustellen, wenn der Zuhörer noch da ist und wahrnimmt.
func deliver(uid: int, ctx: LifeContext) -> Dictionary:
	var u: Dictionary = pending.get(uid, {})
	pending.erase(uid)
	if u.is_empty():
		return {"ok": false, "message": "Äußerung unbekannt."}
	var s := ctx.creature(int(u["speaker"]))
	var l := ctx.creature(int(u["listener"]))
	var cc: Dictionary = ctx.m("communication")
	if s == null or l == null or not l.alive or not s.alive or ctx.distance_xz(s.position, l.position) > float(cc.get("range_m", 4.0)) * 1.25 or not listener_perceives(s, l, ctx):
		u["status"] = "nicht_gehört"
		stats["not_heard"] += 1
		_append(u, ctx)
		return {"ok": false, "message": "Zuhörer hat nichts mitbekommen."}
	var claim: Dictionary
	if str(u["intent"]) in ["explain_procedure", "offer_demo"]:
		claim = TeachingSystem.hear(l, u, ctx)
	else:
		claim = ClaimEvaluator.hear(l, u, ctx)
	u["status"] = "gehört"
	u["claim_status"] = str(claim.get("status", ""))
	stats["heard"] += 1
	_append(u, ctx)
	ctx.publish({"type": "talk", "actor": s.id, "target": l.id, "position": s.position, "consequences": {"absicht": str(u["intent"])},
		"visibility_m": float(cc.get("visibility_m", 8.0))})
	return {"ok": true, "message": u["text"]}


func cancel_pending(uid: int, reason: String, ctx: LifeContext) -> void:
	if pending.has(uid):
		var u: Dictionary = pending[uid]
		pending.erase(uid)
		u["status"] = "abgebrochen: " + reason
		_append(u, ctx)


func _append(u: Dictionary, ctx: LifeContext) -> void:
	log.append(u)
	while log.size() > int(ctx.m("communication").get("log_max", 200)):
		log.pop_front()
	ctx.log_event("utterance", [int(u["speaker"]), int(u["listener"])], {"intent": u["intent"], "status": u["status"], "via": u["via"], "text": u["text"]})


func recent(n: int, creature_id: int = 0) -> Array:
	var out: Array = []
	for i in range(log.size() - 1, -1, -1):
		var u: Dictionary = log[i]
		if creature_id != 0 and int(u["speaker"]) != creature_id and int(u["listener"]) != creature_id:
			continue
		out.append(u)
		if out.size() >= n:
			break
	return out


func to_dict() -> Dictionary:
	return {"log": log.duplicate(true), "next_id": next_id, "stats": stats.duplicate()}


static func from_dict(d: Dictionary) -> CommunicationSystem:
	var c := CommunicationSystem.new()
	c.next_id = int(d.get("next_id", 1))
	for u in d.get("log", []):
		var x: Dictionary = u.duplicate(true)
		for k in ["id", "speaker", "listener"]:
			x[k] = int(x[k])
		c.log.append(x)
	for k in d.get("stats", {}):
		c.stats[k] = int(d["stats"][k])
	return c
