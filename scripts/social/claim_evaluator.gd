class_name ClaimEvaluator
extends RefCounted
## Gehörte Aussagen (Hörensagen) eines Wesens: speichern, Herkunft verfolgen, mit EIGENER Wahrnehmung prüfen.
## Gespeichert in cr.ai["hearsay"] (begrenzt). Ein Eintrag:
##   id, t_heard, speaker (direkter Sprecher), chain (Sprecherkette), origin {creature, t, key} (ursprüngliche
##   Quelle), intent, subject {type, id, pos, kind, kg}, statement (Vorlagentext), certainty (geäußert),
##   trust_at_hearing, independent (unabhängige Quellen), retold (Weitererzählungen derselben Quelle),
##   status, status_t, contradicting [Beobachtungen], note
## Status: ungeprüft | bestätigt (selbst gefunden) | veraltet (Quelle jetzt leer – war vermutlich richtig) |
##   fehler (Angabe kann nicht stimmen, z. B. falsche Art/Ort) | widersprochen (eigene Beobachtung zur selben
##   Zeit sagt das Gegenteil) | selbst_beobachtet (war schon bekannt) | nicht_prüfbar
## Regeln:
##   - Hörensagen geht NICHT ins Nahrungsgedächtnis und NICHT als Beleg in Überzeugungen.
##   - Weitererzählen derselben Ursprungsbeobachtung zählt nicht als unabhängige Bestätigung.
##   - Vertrauen ändert sich vorsichtig: bestätigt ↑ (klein), veraltet ±0, fehler/widersprochen ↓ (klein).
##   - Strategische Täuschung ist NICHT implementiert: Sprecher können nur sagen, was sie selbst glauben.

const STATUS_LABEL := {"ungeprüft": "ungeprüft", "wird_geprüft": "wird geprüft", "bestätigt": "bestätigt (selbst gefunden)",
	"veraltet": "veraltet (Quelle jetzt leer)", "fehler": "Fehler (Angabe passt nicht)", "widersprochen": "widerspricht eigener Beobachtung",
	"selbst_beobachtet": "war schon selbst beobachtet", "nicht_prüfbar": "nicht prüfbar", "nicht_erreichbar": "Ort nicht erreichbar"}


static func origin_key(u: Dictionary) -> String:
	var o: Dictionary = u["source"]
	var s: Dictionary = u["statement"]
	return "%d|%s|%d|%d" % [int(o.get("creature", 0)), str(s.get("type", "")), int(s.get("id", 0)), int(round(float(o.get("t", 0.0))))]


## Zuhörer verarbeitet eine zugestellte Äußerung.
static func hear(listener: Creature, u: Dictionary, ctx: LifeContext) -> Dictionary:
	var hc: Dictionary = ctx.m("hearsay")
	var now := ctx.now()
	var ai: Dictionary = listener.ai
	var speaker := int(u["speaker"])
	var sp := ctx.creature(speaker)
	if sp != null:
		listener.relations.ensure(listener, sp, now, ctx.mind_cfg)
		listener.relations.touch(speaker, float(ctx.m("relationships").get("familiarity_gain_interaction", 0.08)) * 0.5, now, ctx.mind_cfg)
	var st: Dictionary = u["statement"]
	var okey := origin_key(u)
	var list: Array = ai["hearsay"]
	# Bekannter Gegenstand derselben Aussage?
	for c in list:
		if c["subject"].get("type", "") == st.get("type", "") and int(c["subject"].get("id", 0)) == int(st.get("id", 0)) and c["intent"] == u["intent"]:
			if str(c["origin"]["key"]) == okey:
				c["retold"] = int(c["retold"]) + 1
				if not speaker in c["chain"]:
					c["chain"].append(speaker)
				c["note"] = "erneut gehört (gleiche Ursprungsquelle – keine unabhängige Bestätigung)"
			else:
				c["independent"] = int(c["independent"]) + 1
				c["note"] = "von unabhängiger Quelle erneut gehört"
				if float(u["source"].get("t", 0.0)) > float(c["origin"]["t"]):
					c["origin"] = {"creature": int(u["source"].get("creature", 0)), "t": float(u["source"].get("t", 0.0)), "key": okey}
					c["subject"] = st.duplicate(true)
					if c["status"] in ["veraltet", "nicht_erreichbar"]:
						c["status"] = "ungeprüft"
			c["t_heard"] = now
			return c
	var claim := {"id": int(ai.get("next_hearsay_id", 1)), "t_heard": now, "speaker": speaker, "chain": [speaker] + u["source"].get("chain", []).filter(func(x): return int(x) != speaker),
		"origin": {"creature": int(u["source"].get("creature", speaker)), "t": float(u["source"].get("t", now)), "key": okey},
		"source_kind": str(u["source"].get("kind", "")), "intent": str(u["intent"]), "subject": st.duplicate(true), "statement": str(u["text"]),
		"certainty": float(u["certainty"]), "trust_at_hearing": listener.relations.trust(speaker), "independent": 1, "retold": 0,
		"status": "ungeprüft", "status_t": now, "contradicting": [], "note": "", "utterance": int(u["id"])}
	ai["next_hearsay_id"] = int(claim["id"]) + 1
	if str(st.get("type", "")) == "food_source":
		var fid := int(st.get("id", 0))
		var own: Dictionary = listener.food_memory.get(fid, {})
		var es: Dictionary = ai.get("empty_seen", {})
		if not own.is_empty() and float(own["seen_t"]) >= float(claim["origin"]["t"]):
			claim["status"] = "selbst_beobachtet"
			claim["note"] = "selbst gesehen vor %.0f s" % (now - float(own["seen_t"]))
		elif es.has(fid) and absf(float(es[fid]) - float(claim["origin"]["t"])) <= float(hc.get("contradiction_window_s", 10.0)):
			claim["status"] = "widersprochen"
			claim["contradicting"].append({"t": float(es[fid]), "obs": "selbst leer gesehen"})
			claim["note"] = "eigene Beobachtung zur gleichen Zeit: Quelle leer"
			listener.relations.trust_update(speaker, false, float(hc.get("trust_contradict_weight", 0.4)), ctx.mind_cfg)
	else:
		claim["status"] = "nicht_prüfbar"
		if str(st.get("type", "")) == "guess":
			var own_b: Dictionary = listener.beliefs.items.get(str(st.get("key", "")), {})
			claim["note"] = "eigene Vermutung dazu: p=%.2f" % listener.beliefs.p(str(st.get("key", ""))) if not own_b.is_empty() else "keine eigene Erfahrung dazu"
	list.append(claim)
	_evict(list, int(hc.get("capacity", 24)))
	return claim


static func _evict(list: Array, cap: int) -> void:
	while list.size() > cap:
		var worst := 0
		for i in list.size():
			var a: Dictionary = list[i]
			var b: Dictionary = list[worst]
			var ra := 0 if a["status"] in ["ungeprüft", "wird_geprüft"] else 1
			var rb := 0 if b["status"] in ["ungeprüft", "wird_geprüft"] else 1
			if ra > rb or (ra == rb and float(a["t_heard"]) < float(b["t_heard"])):
				worst = i
		list.remove_at(worst)


## Während der Wahrnehmung: leere Quellen merken, offene Aussagen mit eigener Sicht prüfen.
static func on_perception(cr: Creature, ctx: LifeContext) -> void:
	if cr.ai.is_empty():
		return
	var hc: Dictionary = ctx.m("hearsay")
	var now := ctx.now()
	var es: Dictionary = cr.ai["empty_seen"]
	for fid in cr.visible_food:
		if ctx.foods.has(fid) and (ctx.foods[fid] as FoodSource).amount_kg <= 1e-6:
			es[fid] = now
	if es.size() > int(hc.get("empty_seen_max", 32)):
		var ks := es.keys()
		ks.sort_custom(func(a, b): return float(es[a]) < float(es[b]))
		for k in ks.slice(0, es.size() - int(hc.get("empty_seen_max", 32))):
			es.erase(k)
	var list: Array = cr.ai["hearsay"]
	for i in range(list.size() - 1, -1, -1):
		var c: Dictionary = list[i]
		if now - float(c["t_heard"]) > float(hc.get("expire_s", 600.0)):
			list.remove_at(i)
			continue
		if not c["status"] in ["ungeprüft", "wird_geprüft"] or str(c["subject"].get("type", "")) != "food_source":
			continue
		var fid2 := int(c["subject"]["id"])
		if not fid2 in cr.visible_food:
			if c["status"] == "wird_geprüft":
				var cp: Array = c["subject"].get("pos", [])
				var near := cp.size() == 3 and ctx.distance_xz(cr.position, Vector3(cp[0], cp[1], cp[2])) <= float(hc.get("verify_radius_m", 3.0))
				if near or now - float(c["status_t"]) > 60.0:
					_mark(c, "nicht_prüfbar", now, "Ort erreicht, Quelle nicht zu sehen" if near else "Prüfung nicht abgeschlossen")
			continue
		_verify_food(cr, c, fid2, ctx)


static func _verify_food(cr: Creature, c: Dictionary, fid: int, ctx: LifeContext) -> void:
	var hc: Dictionary = ctx.m("hearsay")
	var now := ctx.now()
	var f: FoodSource = ctx.foods.get(fid, null)
	var claimed_kind := str(c["subject"].get("kind", ""))
	var cp: Array = c["subject"].get("pos", [])
	var speaker := int(c["speaker"])
	if f == null:
		return
	# Fehler: sichtbare Art oder Ort passt nicht zur Angabe
	if (claimed_kind != "" and claimed_kind != f.kind) or (cp.size() == 3 and ctx.distance_xz(f.position, Vector3(cp[0], cp[1], cp[2])) > 1.5):
		_mark(c, "fehler", now, "gesehene Quelle passt nicht zur Angabe (Art/Ort)")
		cr.relations.trust_update(speaker, false, float(hc.get("trust_error_weight", 0.4)), ctx.mind_cfg)
		return
	if f.amount_kg > 1e-6:
		_mark(c, "bestätigt", now, "selbst gefunden: %.2f kg" % f.available_kg())
		cr.relations.trust_update(speaker, true, float(hc.get("trust_confirm_weight", 0.3)), ctx.mind_cfg)
		return
	if now - float(c["origin"]["t"]) <= float(hc.get("contradiction_window_s", 10.0)):
		_mark(c, "widersprochen", now, "kurz nach der Ursprungsbeobachtung selbst leer gesehen")
		c["contradicting"].append({"t": now, "obs": "leer gesehen"})
		cr.relations.trust_update(speaker, false, float(hc.get("trust_contradict_weight", 0.4)), ctx.mind_cfg)
		return
	_mark(c, "veraltet", now, "Quelle jetzt leer; Hinweis war %.0f s alt – vermutlich inzwischen gegessen, kein Hinweis auf Unwahrheit" % (now - float(c["origin"]["t"])))
	var w := float(hc.get("trust_outdated_weight", 0.0))
	if w > 0.0:
		cr.relations.trust_update(speaker, false, w, ctx.mind_cfg)


static func _mark(c: Dictionary, status: String, now: float, note: String) -> void:
	c["status"] = status
	c["status_t"] = now
	c["note"] = note


## Bester offener Nahrungshinweis für die Entscheidung (oder {}).
static func best_food_hint(cr: Creature, ctx: LifeContext) -> Dictionary:
	if cr.ai.is_empty():
		return {}
	var best := {}
	var bs := -INF
	for c in cr.ai["hearsay"]:
		if c["status"] != "ungeprüft" or str(c["subject"].get("type", "")) != "food_source":
			continue
		var p: Array = c["subject"].get("pos", [])
		if p.size() != 3:
			continue
		var d := ctx.distance_xz(cr.position, Vector3(p[0], p[1], p[2]))
		var s := float(c["trust_at_hearing"]) * float(c["certainty"]) - 0.01 * d + float(ctx.m("hearsay").get("independent_bonus", 0.05)) * (int(c["independent"]) - 1)
		if s > bs:
			bs = s
			best = c
	return best


static func label(status: String) -> String:
	return STATUS_LABEL.get(status, status)
