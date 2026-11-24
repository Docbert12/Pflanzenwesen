class_name RewardAssociation
extends RefCounted
## Interpretation eines wahrgenommenen Eingriffs durch EIN Wesen (nicht die Absicht des Spielers).
## Grundlage nur: eigene wahrgenommene Handlungen, zeitlicher Abstand, sichtbarer Empfänger/Ort,
## Wiederholungen (über die Überzeugungen) und der Vergleich mit Zeitfenstern ohne Ereignis (gift_base).
##
## Zuordnung („credit assignment“), begrenzt und nachvollziehbar:
##   Kandidaten = eigene Handlungen, die höchstens credit_window_s vor dem Ereignis endeten
##                (+ die gerade laufende Handlung mit Δt = 0)
##   Gewicht_i  = exp(−Δt_i / τ), normiert auf Summe 1; nur Gewichte ≥ credit_min_weight zählen
##   → eine kurz vorher beendete Handlung erhält den Großteil; ältere fast nichts.
##   Jede Handlung wird höchstens einmal zugeordnet.
## Wert für das Wesen (tatsächliche Folgen, nicht „Belohnung an sich“):
##   Nahrung:  Hunger + 0,1 − 0,2·Vorsicht (satt + vorsichtig → kaum oder negativ: Schreck)
##   Heilung:  0,6 + geheilter Schaden, wenn ICH geheilt wurde; sonst 0
##   Material: 0,1 + 0,2·Neugier − 0,2·Vorsicht (noch ohne Nutzen)
## Liegt das Ereignis bei einem ANDEREN Wesen, ordnet der Beobachter es dessen von ihm
## wahrgenommenen Gesten zu (gift_after_other) – er kann also eine andere Erklärung bilden.
## Wer nichts wahrgenommen hat, wird nicht aufgerufen und weiß nichts.

const NEAR_SELF_M := 2.0


static func outcome_value(cr: Creature, obs: Observation) -> float:
	var caution := cr.personality.v("vorsicht")
	match obs.event_type:
		"food_appeared":
			return clampf(cr.metabolism.hunger() + 0.1 - 0.2 * caution, -0.3, 1.1)
		"healed":
			if obs.target_id == cr.id:
				return 0.6 + float(obs.consequences.get("healed", 0.0))
			return 0.0
		"material_appeared":
			return clampf(0.1 + 0.2 * cr.personality.v("neugier") - 0.2 * caution, -0.3, 0.5)
	return 0.0


static func process(cr: Creature, obs: Observation, mem: Dictionary, ctx: LifeContext) -> void:
	var now := ctx.now()
	var mcfg := ctx.mind_cfg
	var lc: Dictionary = ctx.m("learning")
	var window := float(lc.get("credit_window_s", 12.0))
	var tau := float(lc.get("credit_tau_s", 4.0))
	var wmin := float(lc.get("credit_min_weight", 0.15))
	var near_self := obs.target_id == cr.id or ctx.distance_xz(obs.position, cr.position) <= NEAR_SELF_M
	var value := outcome_value(cr, obs)
	var record := {"t": snappedf(now, 0.1), "type": obs.event_type, "near_self": near_self, "value": snappedf(value, 0.01),
		"quality": snappedf(obs.quality, 0.01), "credited": [], "explanation": "", "mem": int(mem.get("id", 0))}
	if near_self:
		cr.learning["base_hit"] = true
		var cands: Array = []
		for p in cr.learning["pending"]:
			var dt := obs.t - float(p["t_end"])
			if not p["credited"] and dt >= 0.0 and dt <= window:
				cands.append({"p": p, "type": p["type"], "dt": dt, "w": exp(-dt / tau)})
		if ctx.executor.running.has(cr.id):
			var ra: GameAction = ctx.executor.running[cr.id]
			if ra.type in lc.get("trackable_actions", []) and ra.elapsed_s >= 0.5:
				cands.append({"p": null, "type": ra.type, "dt": 0.0, "w": 1.0, "running": true})
		var total := 0.0
		for c in cands:
			total += float(c["w"])
		for c in cands:
			var wn := float(c["w"]) / maxf(total, 1e-9)
			if wn < wmin:
				continue
			var key := "gift_after_action:" + str(c["type"])
			cr.beliefs.get_or_create(key, "gift_after_action", str(c["type"]), "self", now, mcfg)
			cr.beliefs.update(key, true, wn * obs.quality, now, mcfg, {"mem": record["mem"], "dt": snappedf(float(c["dt"]), 0.1), "w": snappedf(wn, 0.01)}, value)
			if c["p"] != null:
				c["p"]["credited"] = true
			elif c.get("running", false):
				cr.learning["running_credited"] = ctx.executor.running[cr.id].id
			record["credited"].append({"type": c["type"], "dt": snappedf(float(c["dt"]), 0.1), "w": snappedf(wn, 0.01)})
		if record["credited"].is_empty():
			record["explanation"] = "Keine eigene Handlung im Zeitfenster von %.0f s – kein Zusammenhang vermutet." % window
		else:
			var parts: Array = []
			for c2 in record["credited"]:
				parts.append("„%s“ (Δt %.1f s, Gewicht %.2f)" % [ActionDefinition.label(str(c2["type"])), c2["dt"], c2["w"]])
			record["explanation"] = "Zeitlich nach eigener Handlung: " + ", ".join(parts) + ". Zeitliche Folge, keine bewiesene Ursache."
	else:
		# Ereignis bei einem anderen: wahrgenommene Gesten dieses anderen als mögliche Erklärung
		var who := obs.target_id
		if who == 0:
			var best := 0
			var bd := NEAR_SELF_M
			for oid in ctx.nearby_creatures(obs.position, NEAR_SELF_M):
				if oid != cr.id and ctx.creatures[oid].alive:
					var d := ctx.distance_xz(ctx.creatures[oid].position, obs.position)
					if d < bd and cr.relations.rel.has(oid):   # nur Wesen, die es kennt/gesehen hat
						bd = d
						best = oid
			who = best
		var credited := false
		if who != 0:
			for q in cr.learning["pending_other"]:
				var dt2 := obs.t - float(q["t"])
				if int(q["actor"]) == who and not q["credited"] and dt2 >= 0.0 and dt2 <= window:
					var w2 := exp(-dt2 / tau) * obs.quality
					var k2 := "gift_after_other:" + str(q["type"])
					cr.beliefs.get_or_create(k2, "gift_after_other", str(q["type"]), "others", now, mcfg)
					cr.beliefs.update(k2, true, w2, now, mcfg, {"mem": record["mem"], "bei": who, "dt": snappedf(dt2, 0.1)}, value)
					q["credited"] = true
					credited = true
					record["credited"].append({"type": q["type"], "actor": who, "dt": snappedf(dt2, 0.1), "w": snappedf(w2, 0.01)})
		if credited:
			record["explanation"] = "Bei #%d, kurz nach dessen wahrgenommener Geste – vermuteter Zusammenhang dort, nicht bei mir." % who
		elif who != 0:
			record["explanation"] = "Bei #%d gesehen, ohne vorher wahrgenommene Geste – keine Erklärung." % who
		else:
			record["explanation"] = "Ohne erkennbaren Bezug gesehen."
	var seen: Array = cr.interventions_seen
	seen.append(record)
	while seen.size() > 10:
		seen.pop_front()
