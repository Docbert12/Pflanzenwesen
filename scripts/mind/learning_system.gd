class_name LearningSystem
extends RefCounted
## Verarbeitet, was ein Wesen SELBST wahrnimmt oder tut, zu Erinnerungen, Beziehungen und Überzeugungen.
## Eingänge (nur diese):
##   on_observation(cr, obs)   – Beobachtung aus Perception.broadcast (eigene Wahrnehmung)
##   on_own_action(cr, a)      – Ende einer eigenen Handlung (das Wesen weiß, was es selbst getan hat)
##   tick(cr)                  – zeitliche Auflösung offener Erwartungen (bei jeder Wahrnehmungsrunde, 1 s)
## Das globale Ereignisprotokoll wird NIE gelesen.

const INTERVENTION_TYPES := ["food_appeared", "material_appeared", "healed"]


static func significance(cr: Creature, obs: Observation, ctx: LifeContext) -> float:
	var s: Dictionary = ctx.m("memory").get("significance", {})
	var base := 0.0
	match obs.event_type:
		"food_given":
			if obs.target_id == cr.id:
				base = float(s.get("received_food", 0.5))
			elif obs.actor_id == cr.id:
				base = float(s.get("gave_food", 0.3))
			else:
				base = float(s.get("other_help_seen", 0.25))
		"request_declined":
			base = float(s.get("declined_me", 0.3)) if obs.target_id == cr.id else 0.1
		"food_requested":
			base = float(s.get("request_to_me", 0.2)) if obs.target_id == cr.id else 0.08
		"food_appeared":
			base = float(s.get("divine_gift", 0.55))
		"material_appeared":
			base = float(s.get("material_appeared", 0.35))
		"healed":
			base = float(s.get("healed", 0.6)) if obs.target_id == cr.id else 0.3
		"death":
			base = float(s.get("death_seen", 0.6))
		"injury_visible":
			base = float(s.get("injury_seen", 0.4))
		"food_eaten":
			base = float(s.get("food_eaten_seen", 0.1))
		"food_taken":
			base = float(s.get("food_taken_seen", 0.08))
		"raise_arms":
			base = float(s.get("raise_arms_seen", 0.12))
		"food_offered":
			base = 0.15 if obs.target_id == cr.id else 0.06
		_:
			base = 0.05
	if obs.involves(cr.id):
		base += float(s.get("self_involved", 0.35)) * 0.5
	return clampf(base * (0.5 + 0.5 * obs.quality), 0.0, 1.0)


static func on_observation(cr: Creature, obs: Observation, ctx: LifeContext) -> void:
	if not cr.alive:
		return
	var now := ctx.now()
	var mcfg := ctx.mind_cfg
	var mem := cr.memory.remember(obs, significance(cr, obs, ctx), now, mcfg)
	TeachingSystem.on_observation(cr, obs, ctx)
	var ev := {"mem": int(mem.get("id", 0)), "q": snappedf(obs.quality, 0.01)}
	# Anlass für eine mögliche Modellanfrage (Prompt 5): neue bedeutsame Erinnerung
	if not mem.is_empty() and float(mem["significance"]) >= float(ctx.m("ai_triggers").get("notable_significance", 0.5)) and obs.event_type != "talk":
		cr.ai["notable_t"] = now
		cr.ai["notable_mem"] = int(mem["id"])
	var rc: Dictionary = ctx.m("relationships")
	# Vertrautheit mit wahrgenommenen Beteiligten
	for pid in [obs.actor_id, obs.target_id]:
		if pid != 0 and pid != cr.id and ctx.creatures.has(pid):
			cr.relations.ensure(cr, ctx.creatures[pid], now, mcfg)
			var gain := float(rc.get("familiarity_gain_per_observation", 0.02)) * obs.quality
			if obs.involves(cr.id):
				gain = float(rc.get("familiarity_gain_interaction", 0.08))
			cr.relations.touch(pid, gain, now, mcfg)
	match obs.event_type:
		"food_given":
			if obs.target_id == cr.id and obs.actor_id != 0:
				var r: Dictionary = cr.relations.rel.get(obs.actor_id, {})
				if not r.is_empty():
					r["help_received"] = int(r["help_received"]) + 1
				cr.relations.trust_update(obs.actor_id, true, float(rc.get("trust_help_weight", 1.0)), mcfg)
				var hk := "helper:%d" % obs.actor_id
				cr.beliefs.get_or_create(hk, "helper", str(obs.actor_id), "self", now, mcfg)
				cr.beliefs.update(hk, true, 1.0, now, mcfg, ev, cr.metabolism.hunger())
				cr.social["pending_request"] = {}
			elif obs.actor_id == cr.id and obs.target_id != 0:
				var r2: Dictionary = cr.relations.rel.get(obs.target_id, {})
				if not r2.is_empty():
					r2["help_given"] = int(r2["help_given"]) + 1
			elif obs.actor_id != 0:
				var r3: Dictionary = cr.relations.rel.get(obs.actor_id, {})
				if not r3.is_empty():
					r3["observed_help_others"] = int(r3["observed_help_others"]) + 1
				cr.relations.trust_update(obs.actor_id, true, float(rc.get("trust_observed_help_weight", 0.25)) * obs.quality, mcfg)
		"request_declined":
			if obs.target_id == cr.id and obs.actor_id != 0:
				var r4: Dictionary = cr.relations.rel.get(obs.actor_id, {})
				if not r4.is_empty():
					r4["declines"] = int(r4["declines"]) + 1
				# Ablehnung ist kein schwerer Vertrauensbruch: kleines Gewicht, nur wenn sichtbar Nahrung vorhanden war
				var w := float(rc.get("trust_decline_weight", 0.3)) if obs.consequences.get("had_food", false) else float(rc.get("trust_decline_without_visible_food", 0.0))
				cr.relations.trust_update(obs.actor_id, false, w, mcfg)
				var hk2 := "helper:%d" % obs.actor_id
				cr.beliefs.get_or_create(hk2, "helper", str(obs.actor_id), "self", now, mcfg)
				cr.beliefs.update(hk2, false, 1.0, now, mcfg, ev)
				cr.social["target_cooldown"][obs.actor_id] = now + float(ctx.m("social").get("after_decline_cooldown_s", 90.0))
				cr.social["pending_request"] = {}
		"food_requested":
			if obs.target_id == cr.id and obs.actor_id != 0:
				var r5: Dictionary = cr.relations.rel.get(obs.actor_id, {})
				if not r5.is_empty():
					r5["requests_to_me"] = int(r5["requests_to_me"]) + 1
				var inbox: Array = cr.social["inbox"]
				inbox.append({"from": obs.actor_id, "t": now, "req": int(obs.consequences.get("request_id", 0))})
				while inbox.size() > 4:
					inbox.pop_front()
		"raise_arms":
			if obs.actor_id != cr.id and obs.actor_id != 0:
				var po: Array = cr.learning["pending_other"]
				po.append({"type": "raise_arms", "actor": obs.actor_id, "t": now, "credited": false})
				while po.size() > int(ctx.m("learning").get("pending_max", 12)):
					po.pop_front()
		"death":
			if obs.actor_id != 0 and cr.relations.rel.has(obs.actor_id):
				cr.relations.rel[obs.actor_id]["seen_dead"] = true
	if obs.event_type in INTERVENTION_TYPES:
		RewardAssociation.process(cr, obs, mem, ctx)


## Eigene, abgeschlossene Handlung (Selbstwissen, kein Weltwissen).
static func on_own_action(cr: Creature, a: GameAction, ctx: LifeContext) -> void:
	var now := ctx.now()
	var mcfg := ctx.mind_cfg
	var lc: Dictionary = ctx.m("learning")
	if a.status == ActionDefinition.STATUS_SUCCEEDED and a.type in lc.get("trackable_actions", []):
		var pend: Array = cr.learning["pending"]
		var already := int(cr.learning.get("running_credited", 0)) == a.id   # schon während der Ausführung zugeordnet
		pend.append({"type": a.type, "t_end": now, "credited": already, "action_id": a.id})
		while pend.size() > int(lc.get("pending_max", 12)):
			pend.pop_front()
	# Nahrungsorte: Erfolg bei Aufnahme/Essen an einer Quelle, Gegenbeispiel bei leerer/vergebener Quelle
	if a.type in ["pick_up", "eat"] and ctx.foods.has(a.target_id):
		var pos: Vector3 = ctx.foods[a.target_id].position
		var cell := float(ctx.m("beliefs").get("place_cell_m", 4.0))
		var pk := MemoryStore.place_key(pos, cell)
		var key := "food_place:" + pk
		if a.status == ActionDefinition.STATUS_SUCCEEDED:
			cr.beliefs.get_or_create(key, "food_place", pk, "self", now, mcfg)
			cr.beliefs.update(key, true, 1.0, now, mcfg, {"action": a.id}, 1.0)
		elif a.result_code in ["unavailable", "target_lost"]:
			cr.beliefs.get_or_create(key, "food_place", pk, "self", now, mcfg)
			cr.beliefs.update(key, false, 1.0, now, mcfg, {"action": a.id})
	if a.type == "request_food" and a.status == ActionDefinition.STATUS_SUCCEEDED:
		cr.social["pending_request"] = {"to": a.target_id, "t": now}


## Auflösung offener Erwartungen (1-s-Takt je Wesen, versetzt).
static func tick(cr: Creature, ctx: LifeContext) -> void:
	var now := ctx.now()
	var mcfg := ctx.mind_cfg
	var lc: Dictionary = ctx.m("learning")
	var window := float(lc.get("credit_window_s", 12.0))
	# Eigene Handlungen ohne nachfolgendes Ereignis → Gegenbeispiel (nur für bestehende Hypothesen)
	var pend: Array = cr.learning["pending"]
	var keep: Array = []
	for p in pend:
		if now - float(p["t_end"]) <= window:
			keep.append(p)
			continue
		if not p["credited"]:
			var key := "gift_after_action:" + str(p["type"])
			if cr.beliefs.has_belief(key):
				cr.beliefs.update(key, false, 1.0, now, mcfg, {"ausgeblieben_nach": p["type"]})
	cr.learning["pending"] = keep
	var po: Array = cr.learning["pending_other"]
	var keep2: Array = []
	for q in po:
		if now - float(q["t"]) <= window:
			keep2.append(q)
			continue
		if not q["credited"]:
			var k2 := "gift_after_other:" + str(q["type"])
			if cr.beliefs.has_belief(k2):
				cr.beliefs.update(k2, false, 0.5, now, mcfg, {"ausgeblieben_nach": q["type"], "bei": q["actor"]})
	cr.learning["pending_other"] = keep2
	# Grundhäufigkeit: gleich lange Zeitfenster, Treffer = auffälliges Ereignis bei mir
	if now - float(cr.learning["base_window_t"]) >= window:
		var bk := "gift_base"
		cr.beliefs.get_or_create(bk, "gift_base", "self", "self", now, mcfg)
		cr.beliefs.update(bk, bool(cr.learning["base_hit"]), 1.0, now, mcfg, {"fenster_s": window})
		cr.learning["base_window_t"] = now
		cr.learning["base_hit"] = false
	# Anfragen im Eingang verfallen
	var inbox: Array = cr.social["inbox"]
	var exp_s := float(ctx.m("social").get("request_expire_s", 10.0))
	cr.social["inbox"] = inbox.filter(func(r): return now - float(r["t"]) <= exp_s)
	var pr: Dictionary = cr.social.get("pending_request", {})
	if not pr.is_empty() and now - float(pr["t"]) > exp_s:
		cr.social["target_cooldown"][int(pr["to"])] = now + float(ctx.m("social").get("same_target_cooldown_s", 60.0))
		cr.social["pending_request"] = {}


## Erwarteter Nutzen einer Wiederholung: (p(Ereignis | Handlung) − p(Ereignis allgemein)) × erlebter Wert.
## Konfidenz wird separat zurückgegeben.
static func repeat_estimate(cr: Creature, action_type: String, ctx: LifeContext) -> Dictionary:
	var key := "gift_after_action:" + action_type
	if not cr.beliefs.has_belief(key):
		return {"delta": 0.0, "value": 0.0, "confidence": 0.0, "p": 0.0, "p_base": 0.0}
	var pa := cr.beliefs.p(key)
	var pb := cr.beliefs.p("gift_base") if cr.beliefs.has_belief("gift_base") else 0.5
	return {"delta": pa - pb, "value": cr.beliefs.value_avg(key), "confidence": cr.beliefs.confidence(key, ctx.mind_cfg), "p": pa, "p_base": pb}
