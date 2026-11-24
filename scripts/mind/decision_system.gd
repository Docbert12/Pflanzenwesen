class_name DecisionSystem
extends RefCounted
## EINZIGER Entscheider für die laufende Handlung eines Wesens (ersetzt BasicBehavior.decide).
## Läuft alle decision_interval_s (versetzt) und nur, wenn keine Handlung läuft.
## Gemeinsame Bewertung aller Optionen in einer Nutzwert-Skala; jede Option protokolliert ihre
## Beiträge (Bedarf, Persönlichkeit, Beziehung, Erfahrung, Unsicherheit, Bindung, Vorschlag).
## Grundlage nur: eigener Körperzustand, eigene Wahrnehmung, eigenes Gedächtnis/Überzeugungen/Beziehungen.

static func decide(cr: Creature, ctx: LifeContext) -> void:
	if not cr.alive or ctx.executor.running.has(cr.id):
		return
	cr.stats["decisions"] = int(cr.stats.get("decisions", 0)) + 1
	var options := evaluate(cr, ctx)
	options.sort_custom(func(a, b): return float(a["u"]) > float(b["u"]))
	var tried: Array = []
	for o in options.slice(0, 4):
		var r := _execute(cr, o, ctx)
		tried.append({"id": o["id"], "ok": r["ok"], "why": r["reason"]})
		if r["ok"]:
			if ctx.experiments != null and not str(o["id"]).begins_with("tech:") and ctx.experiments.active(cr) != null:
				ctx.experiments.abort(cr, "zugunsten von „%s“ (Nutzwert %.2f)" % [o["id"], float(o["u"])], ctx)
			GoalManager.commit(cr, o["goal"], int(o.get("target", 0)), float(o["u"]), ctx)
			cr.behavior_state = r["state"]
			cr.behavior_reason = r["reason"]
			cr.decision = {"t": snappedf(ctx.now(), 0.1), "chosen": o["id"], "u": snappedf(float(o["u"]), 0.001),
				"parts": o["parts"], "options": _summary(options), "tried": tried, "reason": r["reason"],
				"source": "modellplan" if o["id"] == "follow_plan" else ("lokal + Modellvorschlag" if o["parts"].has("vorschlag") else "lokal")}
			if ctx.ai != null:
				ctx.ai.consider(cr, options)
			return
	# Nichts ausführbar: kurz warten (mit protokolliertem Grund)
	var w := BasicBehavior.wait(cr, ctx, 2.0, "wartet", "Keine ausführbare Option (%s)." % ", ".join(tried.map(func(x): return "%s: %s" % [x["id"], x["why"]])))
	cr.behavior_state = w["state"]
	cr.behavior_reason = w["reason"]
	cr.decision = {"t": snappedf(ctx.now(), 0.1), "chosen": "rest", "u": 0.0, "parts": {}, "options": _summary(options), "tried": tried, "reason": w["reason"], "source": "lokal"}
	if ctx.ai != null:
		ctx.ai.consider(cr, options)


static func _summary(options: Array) -> Array:
	var out: Array = []
	for o in options.slice(0, 6):
		var parts := {}
		for k in o["parts"]:
			parts[k] = snappedf(float(o["parts"][k]), 0.001)
		out.append({"id": o["id"], "u": snappedf(float(o["u"]), 0.001), "parts": parts})
	return out


static func _opt(id: String, goal: String, parts: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var u := 0.0
	for k in parts:
		u += float(parts[k])
	var o := {"id": id, "goal": goal, "u": u, "parts": parts}
	o.merge(extra)
	return o


## Alle gültigen Optionen mit Nutzwert und Beiträgen.
static func evaluate(cr: Creature, ctx: LifeContext) -> Array:
	var dc: Dictionary = ctx.m("decision")
	var sc: Dictionary = ctx.m("social")
	var bc: Dictionary = ctx.c("behavior")
	var pers := cr.personality
	var now := ctx.now()
	var hunger := cr.metabolism.hunger()
	var seek := float(bc.get("hunger_seek_threshold", 0.6))
	var sated := float(bc.get("sated_threshold", 0.15))
	var critical := hunger >= float(dc.get("critical_hunger", 0.8))
	var need := smoothstep(float(dc.get("food_need_low", 0.3)), float(dc.get("food_need_high", 0.9)), hunger)
	var continuing_food: bool = cr.goal_state.get("type", "") == "food" and hunger > sated
	var hungry := hunger >= seek or continuing_food
	var food_u := float(dc.get("food_weight", 1.2)) * need
	var surv := float(dc.get("survival_weight", 2.5)) if critical else 0.0
	var free := 1.0 - need                       # Spielraum für Nicht-Überlebensziele
	var caution := pers.v("vorsicht")
	var options: Array = []
	var carried := cr.carried_item_id != 0 and ctx.items.has(cr.carried_item_id) and (ctx.items[cr.carried_item_id] as FoodItem).reserved_by == 0
	# ── Überleben / Nahrung ──
	var holding: bool = cr.social.get("holding_for_sharing", false)
	if carried and float(cr.caps.get("feeding", 0.0)) > 0.0 and (hunger >= float(sc.get("share_eat_threshold", 0.35)) or (continuing_food and not holding)):
		options.append(_opt("eat_carried", "food", {"bedarf": food_u + 0.1, "überleben": surv, "trägt_nahrung": 0.1}))
	if hungry and cr.carried_item_id == 0:
		var known := BasicBehavior.choose_food(cr, ctx) != 0
		var dist_food := BasicBehavior.nearest_known_food_dist(cr, ctx)
		if known:
			options.append(_opt("seek_food", "food", {"bedarf": food_u, "überleben": surv, "bekannte_nahrung": 0.1,
				"weg": -minf(float(dc.get("walk_cost_max", 0.3)), float(dc.get("walk_cost_per_m", 0.015)) * dist_food)}))
		elif cr.explore_attempts < int(bc.get("explore_attempts", 3)):
			options.append(_opt("search_food", "food", {"bedarf": food_u * 0.6, "überleben": surv * 0.8}))
		# Um Nahrung bitten: sichtbares Wesen, das etwas trägt
		if now >= float(cr.social.get("next_request_t", 0.0)) and cr.social.get("pending_request", {}).is_empty():
			var best := {}
			for v in cr.visible_creatures:
				if not v["alive"] or not v["carrying"] or now < float(cr.social["target_cooldown"].get(v["id"], 0.0)):
					continue
				var tr := cr.relations.trust(v["id"])
				var sc2 := tr - 0.03 * float(v["d"])
				if best.is_empty() or sc2 > float(best["s"]):
					best = {"id": v["id"], "s": sc2, "trust": tr, "d": v["d"]}
			if not best.is_empty():
				# Wegvergleich: Bitten lohnt eher, wenn der Träger näher ist als die nächste bekannte Quelle
				var dfood := dist_food if dist_food < INF else 20.0
				var rel_way := clampf(float(dc.get("walk_cost_per_m", 0.015)) * (dfood - float(best["d"])), -0.15, 0.15)
				options.append(_opt("ask_food", "ask_food", {"bedarf": food_u * 0.85, "vertrauen": 0.3 * (float(best["trust"]) - 0.5),
					"wegvergleich": rel_way, "geselligkeit": float(dc.get("ask_sociability_weight", 0.3)) * pers.v("geselligkeit"),
					"unsicherheit": -0.1 * caution * (1.0 - minf(1.0, cr.relations.trust_evidence(best["id"]) / 4.0)),
					"überleben": surv * 0.7}, {"target": best["id"], "dist": best["d"]}))
	# ── Bitten anderer beantworten ──
	var inbox: Array = cr.social["inbox"]
	if not inbox.is_empty():
		var req: Dictionary = inbox[inbox.size() - 1]
		var rq := ctx.creature(int(req["from"]))
		if rq != null and rq.alive:
			var tr2 := cr.relations.trust(rq.id)
			var fam := cr.relations.familiarity(rq.id)
			var will := 0.6 * pers.v("hilfsbereitschaft") + 0.3 * tr2 + 0.2 * fam - 0.9 * hunger - 0.15
			if carried and will > 0.05 and not critical:
				options.append(_opt("give_requested", "respond_request", {"hilfe": float(dc.get("help_weight", 0.9)) * (0.5 + will),
					"hilfsbereitschaft": 0.2 * pers.v("hilfsbereitschaft"), "vertrauen": 0.2 * (tr2 - 0.5), "eigener_bedarf": -0.5 * hunger},
					{"target": rq.id, "request": int(req["req"]), "will": will}))
			options.append(_opt("decline_request", "respond_request", {"antwort": 0.55, "eigener_bedarf": 0.2 * hunger,
				"hat_nichts": 0.1 if not carried else -0.2}, {"target": rq.id, "request": int(req["req"]), "will": will}))
	# ── Unaufgefordert anbieten ──
	if carried and not hungry and cr.social.get("holding_for_sharing", false):
		for v in cr.visible_creatures:
			if not v["alive"] or v["carrying"] or float(v["d"]) > 6.0:
				continue
			var signs := cr.memory.recall({"participant": v["id"], "types": ["request_declined", "food_requested", "offer_not_accepted"], "since": now - 60.0}, now, ctx.mind_cfg, 1)
			if signs.is_empty() or int(signs[0]["actor"]) != v["id"]:
				continue
			var tr3 := cr.relations.trust(v["id"])
			options.append(_opt("offer_food", "offer_food", {"hilfe": float(dc.get("help_weight", 0.9)) * pers.v("hilfsbereitschaft") * (0.4 + 0.6 * tr3),
				"beobachtete_bitte": 0.1}, {"target": v["id"]}))
			break
	# ── Gehörten Nahrungshinweis selbst prüfen (Hörensagen ist kein eigenes Wissen) ──
	if hungry and cr.carried_item_id == 0:
		var hint := ClaimEvaluator.best_food_hint(cr, ctx)
		if not hint.is_empty():
			var hp: Array = hint["subject"]["pos"]
			var hd := ctx.distance_xz(cr.position, Vector3(hp[0], hp[1], hp[2]))
			var hc: Dictionary = ctx.m("hearsay")
			options.append(_opt("check_hint", "check_hint", {"bedarf": food_u * float(hc.get("check_weight", 0.7)) * float(hint["certainty"]),
				"vertrauen": 0.3 * (float(hint["trust_at_hearing"]) - 0.5), "unabhängig": float(hc.get("independent_bonus", 0.05)) * (int(hint["independent"]) - 1),
				"weg": -minf(float(dc.get("walk_cost_max", 0.3)), float(dc.get("walk_cost_per_m", 0.015)) * hd), "überleben": surv * 0.8},
				{"claim": int(hint["id"]), "dist": hd}))
	# ── Modellplan (nur Vorschlag; konkurriert mit allen lokalen Optionen) ──
	var pp := PlanManager.utility(cr, ctx, food_u, critical)
	if not pp.is_empty():
		options.append(_opt("follow_plan", "plan", pp))
	# ── Für andere sammeln ──
	if not carried and cr.carried_item_id == 0 and hunger < 0.3 and pers.v("hilfsbereitschaft") > 0.55 and float(cr.caps.get("grasp", 0.0)) > 0.0:
		if BasicBehavior.nearest_known_food_dist(cr, ctx) < 6.0:
			options.append(_opt("collect_share", "collect_share", {"hilfsbereitschaft": float(dc.get("collect_for_sharing_weight", 0.35)) * pers.v("hilfsbereitschaft") * free}))
	if not critical:
		# ── Annäherung ──
		if now >= float(cr.social.get("next_approach_t", 0.0)):
			var tgt := {}
			for v in cr.visible_creatures:
				if not v["alive"] or float(v["d"]) < 2.5:
					continue
				var rr: Dictionary = cr.relations.rel.get(v["id"], {})
				var attract := float(rr.get("familiarity", 0.0)) + 0.5 * float(rr.get("similarity", 0.0)) * 0.2 + 0.3 * (cr.relations.trust(v["id"]) - 0.5)
				if tgt.is_empty() or attract > float(tgt["a"]):
					tgt = {"id": v["id"], "a": attract}
			if not tgt.is_empty():
				options.append(_opt("approach", "approach", {"geselligkeit": float(dc.get("social_weight", 0.35)) * pers.v("geselligkeit") * free,
					"beziehung": 0.1 * clampf(float(tgt["a"]), -0.5, 1.0)}, {"target": tgt["id"]}))
		# ── Kurzes Gespräch (lokal, ohne Modell): Hinweis, Erlebnis, Vermutung ──
		if ctx.comm != null:
			var opp := ctx.comm.local_opportunity(cr, ctx)
			if not opp.is_empty():
				options.append(_opt("talk", "talk", {"mitteilung": float(opp["relevance"]),
					"geselligkeit": float(ctx.m("communication").get("talk_weight", 0.3)) * pers.v("geselligkeit") * free * 0.5},
					{"target": int(opp["listener"]), "topic": opp["topic"]}))
		# ── Technik (Prompt 6): Versuch fortsetzen/beginnen, vorführen, zusehen, erklären, üben ──
		if ctx.experiments != null:
			options.append_array(ctx.experiments.options(cr, ctx, free, critical))
		# ── Erkunden ──
		options.append(_opt("explore", "explore", {"neugier": float(dc.get("explore_weight", 0.45)) * pers.v("neugier") * free}))
		# ── Gelernte Handlung wiederholen ──
		for h in cr.beliefs.of_kind("gift_after_action"):
			var est := LearningSystem.repeat_estimate(cr, str(h["subject"]), ctx)
			if float(est["delta"]) <= 0.0 or float(est["value"]) <= 0.0 or not ActionDefinition.has_type(str(h["subject"])):
				continue
			if not str(h["subject"]) in ["raise_arms", "wait"]:
				continue   # nur eigenständig wiederholbare Handlungen ohne Ziel
			var conf := float(est["confidence"])
			options.append(_opt("repeat:" + str(h["subject"]), "repeat_learned", {
				"erwartung": float(dc.get("repeat_weight", 0.8)) * float(est["delta"]) * float(est["value"]) * conf * free,
				"unsicherheit": -float(dc.get("caution_uncertainty_penalty", 0.5)) * caution * (1.0 - conf) * 0.2},
				{"action": str(h["subject"]), "est": est}))
	options.append(_opt("rest", "rest", {"ruhe": float(dc.get("rest_base", 0.15)) + 0.05 * (1.0 - pers.v("neugier"))}))
	# Bindung und externe Vorschläge
	for o in options:
		var bb := GoalManager.binding_bonus(cr, o["goal"], ctx)
		if bb > 0.0 and not critical:
			o["parts"]["bindung"] = bb
			o["u"] = float(o["u"]) + bb
		var sb := GoalManager.suggestion_bonus(cr, o["goal"], ctx)
		if sb > 0.0:
			o["parts"]["vorschlag"] = sb
			o["u"] = float(o["u"]) + sb
	return options


static func _execute(cr: Creature, o: Dictionary, ctx: LifeContext) -> Dictionary:
	var dc: Dictionary = ctx.m("decision")
	var sc: Dictionary = ctx.m("social")
	var bc: Dictionary = ctx.c("behavior")
	var hunger := cr.metabolism.hunger()
	var why := "Nutzwert %.2f (%s)" % [float(o["u"]), _parts_text(o["parts"])]
	match str(o["id"]):
		"eat_carried":
			var r := ctx.executor.request(cr.id, "eat", cr.carried_item_id)
			cr.social["holding_for_sharing"] = false
			return {"ok": r["result"].ok, "state": "isst", "reason": ("Isst getragene Portion: Hunger %.0f %%. " % (hunger * 100) + why) if r["result"].ok else r["result"].message}
		"seek_food":
			cr.explore_attempts = 0
			var f := BasicBehavior.pursue_food(cr, ctx, "eat")
			f["reason"] = "Hunger %.0f %% → %s %s" % [hunger * 100, f["reason"], why]
			return f
		"search_food":
			var e := BasicBehavior.explore(cr, ctx, float(bc.get("explore_radius_m", 8.0)))
			if e["ok"]:
				cr.explore_attempts += 1
				e["state"] = "sucht_nahrung"
				e["reason"] = "Hunger %.0f %%, keine bekannte erreichbare Nahrung → Erkundung %d/%d. %s" % [hunger * 100, cr.explore_attempts, int(bc.get("explore_attempts", 3)), why]
			return e
		"ask_food":
			var t := ctx.creature(int(o["target"]))
			var rng := float(sc.get("request_range_m", 3.0))
			if ctx.distance_xz(cr.position, t.position) > rng * 0.9:
				var r2 := ctx.executor.request(cr.id, "move_to", 0, t.position, {"arrive_radius_m": rng * 0.7})
				return {"ok": r2["result"].ok, "state": "geht_zu_wesen", "reason": "Geht zu #%d (trägt sichtbar Nahrung), um zu bitten. %s" % [t.id, why] if r2["result"].ok else r2["result"].message}
			var r3 := ctx.executor.request(cr.id, "request_food", t.id)
			return {"ok": r3["result"].ok, "state": "bittet", "reason": "Bittet #%d um Nahrung (Vertrauen %.2f). %s" % [t.id, cr.relations.trust(t.id), why] if r3["result"].ok else r3["result"].message}
		"give_requested":
			var t2 := ctx.creature(int(o["target"]))
			var gr := float(sc.get("give_range_m", 1.4))
			if ctx.distance_xz(cr.position, t2.position) > gr * 0.9:
				var r4 := ctx.executor.request(cr.id, "move_to", 0, t2.position, {"arrive_radius_m": gr * 0.7})
				return {"ok": r4["result"].ok, "state": "geht_zu_wesen", "reason": "Geht zu #%d, um auf die Bitte hin zu geben. %s" % [t2.id, why] if r4["result"].ok else r4["result"].message}
			var r5 := ctx.executor.request(cr.id, "give_food", t2.id, null, {"request_id": int(o["request"])})
			_clear_inbox(cr, t2.id)
			if not r5["result"].ok:
				return {"ok": false, "state": "", "reason": r5["result"].message}
			return {"ok": true, "state": "gibt", "reason": "Gibt #%d Nahrung (Bereitschaft %.2f). %s" % [t2.id, float(o["will"]), why]}
		"decline_request":
			var t3 := int(o["target"])
			_clear_inbox(cr, t3)
			var r6 := ctx.executor.request(cr.id, "decline_request", t3, null, {"request_id": int(o["request"])})
			var because := "trägt nichts" if cr.carried_item_id == 0 else "Bereitschaft %.2f zu gering" % float(o["will"])
			return {"ok": r6["result"].ok, "state": "lehnt_ab", "reason": "Lehnt Bitte von #%d ab (%s). %s" % [t3, because, why]}
		"offer_food":
			var r7 := ctx.executor.request(cr.id, "offer_food", int(o["target"]))
			return {"ok": r7["result"].ok, "state": "bietet_an", "reason": "Bietet #%d Nahrung an (zuvor Bitte/Ablehnung beobachtet). %s" % [int(o["target"]), why] if r7["result"].ok else r7["result"].message}
		"collect_share":
			var c := BasicBehavior.pursue_food(cr, ctx, "share", 6.0)
			c["reason"] = "Versorgt, hilfsbereit → %s %s" % [c["reason"], why]
			if c["state"] == "geht_zu_nahrung":
				c["state"] = "sammelt_für_andere"
			return c
		"approach":
			var t4 := ctx.creature(int(o["target"]))
			cr.social["next_approach_t"] = ctx.now() + 45.0
			var dirv := (cr.position - t4.position)
			dirv.y = 0
			var p := t4.position + (dirv.normalized() if dirv.length() > 0.01 else Vector3.RIGHT) * 1.8
			var r8 := ctx.executor.request(cr.id, "move_to", 0, Vector3(p.x, t4.position.y, p.z), {"arrive_radius_m": 0.6})
			return {"ok": r8["result"].ok, "state": "nähert_sich", "reason": "Nähert sich #%d (Vertrautheit %.2f). %s" % [t4.id, cr.relations.familiarity(t4.id), why] if r8["result"].ok else r8["result"].message}
		"explore":
			# Gelegentliches Ausprobieren einer neutralen Ausdruckshandlung (nicht vorgeschrieben)
			if float(cr.caps.get("gesture", 0.0)) > 0.0 and cr.rng.randf() < float(dc.get("raise_arms_try_chance", 0.06)) * (0.5 + cr.personality.v("neugier")):
				var ra := ctx.executor.request(cr.id, "raise_arms")
				if ra["result"].ok:
					return {"ok": true, "state": "arme_heben", "reason": "Probiert aus Neugier „Arme heben“ (zufälliger Versuch). %s" % why}
			var ex := BasicBehavior.explore(cr, ctx, 3.0 + 5.0 * cr.personality.v("neugier"))
			if ex["ok"]:
				ex["state"] = "schlendert"
				ex["reason"] = "Erkundet die Umgebung. %s" % why
			return ex
		"rest":
			var seek_t := float(bc.get("hunger_seek_threshold", 0.6))
			if hunger >= seek_t and cr.explore_attempts >= int(bc.get("explore_attempts", 3)):
				# wie in Prompt 3: nach erfolgloser Suche 8 s warten, danach erneut begrenzt suchen
				cr.explore_attempts = 0
				cr.ai["fail_streak"] = int(cr.ai.get("fail_streak", 0)) + 1     # erfolglose Suche zählt als Scheitern
				return BasicBehavior.wait(cr, ctx, 8.0, "wartet_hungrig", "Hunger %.0f %%, nach %d Erkundungen keine Nahrung gefunden → wartet 8 s, sucht danach erneut. %s" % [hunger * 100, int(bc.get("explore_attempts", 3)), why])
			var dur := cr.rng.randf_range(3.0, 6.0)
			return BasicBehavior.wait(cr, ctx, dur, "wartet", "Versorgt (Hunger %.0f %%); ruht %.1f s. %s" % [hunger * 100, dur, why])
		"follow_plan":
			return PlanManager.execute_next(cr, ctx)
		"talk":
			var st := ctx.comm.start(cr, int(o["target"]), o["topic"], "lokal", ctx)
			return {"ok": st["ok"], "state": "spricht", "reason": ("Spricht mit #%d: %s. %s" % [int(o["target"]), st["message"], why]) if st["ok"] else st["message"]}
		"check_hint":
			var claim: Dictionary = {}
			for c in cr.ai["hearsay"]:
				if int(c["id"]) == int(o["claim"]):
					claim = c
			if claim.is_empty():
				return {"ok": false, "state": "", "reason": "Hinweis nicht mehr vorhanden"}
			var cp: Array = claim["subject"]["pos"]
			var rr := ctx.executor.request(cr.id, "move_to", 0, Vector3(cp[0], cp[1], cp[2]), {"arrive_radius_m": float(ctx.m("hearsay").get("verify_radius_m", 3.0)) * 0.6})
			if not rr["result"].ok:
				claim["status"] = "nicht_erreichbar"
				claim["status_t"] = ctx.now()
				claim["note"] = rr["result"].message
				return {"ok": false, "state": "", "reason": rr["result"].message}
			claim["status"] = "wird_geprüft"
			claim["status_t"] = ctx.now()
			return {"ok": true, "state": "prüft_hinweis", "reason": "Prüft gehörten Hinweis von #%d auf Nahrung #%d (%.0f m, geäußerte Sicherheit %.0f %%, Vertrauen %.2f) – Hörensagen, noch nicht selbst gesehen. %s" % [int(claim["speaker"]), int(claim["subject"]["id"]), float(o["dist"]), float(claim["certainty"]) * 100, float(claim["trust_at_hearing"]), why]}
	if str(o["id"]).begins_with("tech:"):
		var tr := ctx.experiments.execute_option(cr, o, ctx)
		if tr["ok"]:
			tr["reason"] = "%s %s" % [tr["reason"], why]
		return tr
	if str(o["id"]).begins_with("repeat:"):
		var at := str(o["action"])
		var est: Dictionary = o["est"]
		var r9: Dictionary
		if at == "wait":
			r9 = ctx.executor.request(cr.id, "wait", 0, null, {"duration_s": 4.0})
		else:
			r9 = ctx.executor.request(cr.id, at)
		return {"ok": r9["result"].ok, "state": "wiederholt", "reason": ("Wiederholt „%s“: erlebte Häufigkeit danach %.0f %% gegenüber allgemein %.0f %%, Konfidenz %.2f, erlebter Wert %.2f. %s" % [ActionDefinition.label(at), float(est["p"]) * 100, float(est["p_base"]) * 100, float(est["confidence"]), float(est["value"]), why]) if r9["result"].ok else r9["result"].message}
	return {"ok": false, "state": "", "reason": "unbekannte Option"}


static func _clear_inbox(cr: Creature, from_id: int) -> void:
	cr.social["inbox"] = cr.social["inbox"].filter(func(r): return int(r["from"]) != from_id)


static func _parts_text(parts: Dictionary) -> String:
	var out: Array = []
	for k in parts:
		if absf(float(parts[k])) >= 0.005:
			out.append("%s %+.2f" % [k, float(parts[k])])
	return ", ".join(out)
