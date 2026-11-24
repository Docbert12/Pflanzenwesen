class_name Creature
extends RefCounted
## Ein lebendes Pflanzenwesen (Simulationsdaten, keine Nodes).
## Körper: base_genes/plan_seed = grundlegende (vererbbare) Konfiguration; plan = aktuell
## vorhandene Teile inkl. Prothesen (Status present/removed/replaced); health = Verletzungszustand;
## caps = daraus abgeleitete Fähigkeiten (BodyCapabilities).

var id: int = 0
var display_name: String = ""
var plan: BodyPlan
var base_genes: Dictionary = {}
var plan_seed: int = 0
var health := Health.new()
var metabolism := Metabolism.new()
var position := Vector3.ZERO
var heading: float = 0.0
var alive: bool = true
var death: Dictionary = {}
var carried_item_id: int = 0
var held_object_id: int = 0          # Gegenstand/Werkzeug in der Greifhand (Prompt 6; Stück oder Verbund)
var food_memory: Dictionary = {}     # id -> {pos, available_kg, seen_t, kind}
var unreachable: Dictionary = {}     # id -> bis Zeitpunkt
var visible_food: Array = []
var visible_creatures: Array = []    # letzte Wahrnehmung anderer Wesen [{id, d, alive, carrying}]
var behavior_state: String = "neu"
var behavior_reason: String = ""
var goal: Dictionary = {}
var last_result: Dictionary = {}
var path: Array = []
var path_i: int = 0
var path_target = null
var moving: bool = false
var tick_moved_m: float = 0.0
var speed_now: float = 0.0
var caps: Dictionary = {}
var mass_kg: float = 0.0
var rng := RandomNumberGenerator.new()
var next_decision_t: float = 0.0
var next_perception_t: float = 0.0
var explore_attempts: int = 0
var behavior_enabled: bool = true    # Entwicklermodus/Tests: Verhalten anhalten (Handlungen laufen weiter)
var stats := {"distance_m": 0.0, "eaten_kg": 0.0, "decisions": 0, "light_j": 0.0}
var body_version: int = 0            # erhöht sich bei jeder Körperänderung (Darstellung neu bauen)

# ── Geist (Prompt 4) – strikt getrennt vom Weltzustand ──
var personality := Personality.new()
var memory := MemoryStore.new()
var beliefs := BeliefStore.new()
var relations := RelationshipStore.new()
var learning := {"pending": [], "pending_other": [], "base_window_t": 0.0, "base_hit": false, "running_credited": 0}
var goal_state := {}                 # GoalManager: aktuelles Ziel mit Bindung
var decision := {}                   # letzte Entscheidung mit Bewertungsbeiträgen (Erklärung)
var social := {"inbox": [], "pending_request": {}, "target_cooldown": {}, "next_request_t": 0.0, "next_approach_t": 0.0, "holding_for_sharing": false}
var interventions_seen: Array = []   # eigene Interpretationen wahrgenommener Eingriffe
var suggestions: Array = []          # externe Zielvorschläge (vorbereitet für Ollama), begrenzt
var mind_since_t: float = 0.0        # ab hier ist die eigene Vergangenheit bekannt (Migration: Ladezeit)
var next_learning_t: float = 0.0
# ── Modellanbindung und Gespräche (Prompt 5) – Pläne, Hörensagen, Wartezeiten; KEINE offenen Verbindungen ──
var ai: Dictionary = Creature.default_ai()
# ── Praktisches Wissen (Prompt 6): bekannte Gegenstände, Verfahren, Hypothesen, Unterricht ──
var tech: Dictionary = ProceduralKnowledge.default_tech()


static func default_ai() -> Dictionary:
	return {"next_request_t": 0.0, "fail_streak": 0, "plan": {}, "plan_seq": 0, "plan_history": [], "failed_sigs": {}, "notes": [],
		"hearsay": [], "next_hearsay_id": 1, "empty_seen": {}, "talk": {"next_t": 0.0, "pair": {}}, "last": {},
		"notable_t": -1.0e9, "notable_mem": 0, "notable_asked": -1, "interpreted": {}}


## Fest je Wesen (aus dem Körper-Startwert): darf dieses Wesen überhaupt Modellvorschläge erhalten?
func ai_eligible(share: float) -> bool:
	var h := hash(plan_seed * 7919 + 13) % 1000
	return float(h) / 1000.0 < share


## Fähigkeiten, Masse und Speicherkapazität nach Körperänderung neu ableiten.
func refresh_body(ctx: LifeContext) -> void:
	caps = BodyCapabilities.compute(plan, health, ctx.cfg)
	mass_kg = plan.total_mass(ctx.sim.materials)
	metabolism.update_capacity(mass_kg, ctx.cfg)
	body_version += 1


func speed_m_s(ctx: LifeContext) -> float:
	if not alive or not caps.get("can_walk", false):
		return 0.0
	var lc: Dictionary = ctx.c("locomotion")
	var m: Dictionary = ctx.c("metabolism")
	var s := float(lc.get("base_speed_m_s", 1.0)) * float(caps.get("locomotion", 0.0))
	if metabolism.energy_fraction() < float(m.get("weakness_energy_fraction", 0.15)):
		s *= float(m.get("weakness_speed_factor", 0.6))
	return s


func on_action_finished(a: GameAction, ctx: LifeContext) -> void:
	LearningSystem.on_own_action(self, a, ctx)
	# Fehlschlagserie (Anlass für eine Modellanfrage); Erfolg beim Essen/Aufnehmen setzt zurück
	if a.status == ActionDefinition.STATUS_FAILED:
		ai["fail_streak"] = int(ai.get("fail_streak", 0)) + 1
	elif a.status == ActionDefinition.STATUS_SUCCEEDED and a.type in ["eat", "pick_up"]:
		ai["fail_streak"] = 0
	PlanManager.on_action_finished(self, a, ctx)
	if ctx.experiments != null:
		ctx.experiments.on_action_finished(self, a, ctx)
	last_result = {"type": a.type, "status": a.status, "code": a.result_code, "message": a.result_message, "t": ctx.now(), "target": a.target_id}
	next_decision_t = minf(next_decision_t, ctx.now() + 0.1)
	if a.type == "move_to" and goal.get("type", "") == "food":
		if a.status == ActionDefinition.STATUS_SUCCEEDED:
			next_perception_t = ctx.now()   # erneute Prüfung bei Ankunft
		elif a.status == ActionDefinition.STATUS_FAILED:
			var fid: int = goal.get("id", 0)
			if fid != 0:
				unreachable[fid] = ctx.now() + float(ctx.c("perception").get("unreachable_blacklist_s", 60.0))
	if a.status != ActionDefinition.STATUS_SUCCEEDED and a.type in ["pick_up", "eat"] and a.result_code in ["unavailable", "target_lost", "out_of_reach"]:
		if a.target_id != 0 and a.target_id != carried_item_id:
			food_memory.erase(a.target_id)


## Tod: Verhalten und Handlungen enden, Reservierungen frei, Getragenes wird abgelegt,
## der Körper bleibt als Weltzustand erhalten (kein Recycling).
func die(cause: String, ctx: LifeContext) -> void:
	if not alive:
		return
	ctx.executor.cancel(id, "actor_died", "Wesen ist gestorben (%s)." % cause)
	alive = false
	if ctx.ai != null:
		ctx.ai.on_death(self)
	ctx.executor.release_all_for(id, "Tod")
	Locomotion.stop(self)
	var dropped := 0
	if carried_item_id != 0 and ctx.items.has(carried_item_id):
		var it: FoodItem = ctx.items[carried_item_id]
		it.carrier_id = 0
		it.position = position + Vector3(0, 0.05, 0)
		dropped = it.id
	carried_item_id = 0
	var dropped_obj := 0
	if ctx.experiments != null:
		ctx.experiments.abort(self, "Wesen gestorben", ctx)
	if held_object_id != 0:
		dropped_obj = ToolUseSystem.release(ctx, self, "Tod")
	death = {"t": ctx.now(), "cause": cause, "position": [position.x, position.y, position.z], "dropped_item": dropped, "dropped_object": dropped_obj,
		"energy_j": metabolism.energy_j, "nutrients_g": metabolism.nutrients_g}
	behavior_state = "tot"
	behavior_reason = "Gestorben bei t=%.1f s: %s" % [ctx.now(), cause]
	ctx.publish({"type": "death", "actor": id, "position": position, "consequences": {"liegt_still": true},
		"visibility_m": float(ctx.m("observation").get("gesture_visibility_m", 10.0))}, "warning")
	ctx.log_event("creature_died", [id], death, "warning")


func to_dict() -> Dictionary:
	return {"id": id, "display_name": display_name, "plan": plan.to_dict(), "base_genes": base_genes.duplicate(true), "plan_seed": plan_seed,
		"health": health.to_dict(), "metabolism": metabolism.to_dict(), "position": [position.x, position.y, position.z], "heading": heading,
		"alive": alive, "death": death.duplicate(true), "carried_item_id": carried_item_id, "held_object_id": held_object_id, "food_memory": food_memory.duplicate(true),
		"unreachable": unreachable.duplicate(), "behavior_state": behavior_state, "behavior_reason": behavior_reason, "goal": goal.duplicate(),
		"last_result": last_result.duplicate(true), "rng_state": str(rng.state), "rng_seed": str(rng.seed),
		"next_decision_t": next_decision_t, "next_perception_t": next_perception_t, "explore_attempts": explore_attempts, "behavior_enabled": behavior_enabled, "stats": stats.duplicate(),
		"mind": {"personality": personality.to_dict(), "memory": memory.to_dict(), "beliefs": beliefs.to_dict(), "relations": relations.to_dict(),
			"learning": learning.duplicate(true), "goal_state": goal_state.duplicate(true), "decision": decision.duplicate(true),
			"social": _social_to_dict(), "interventions_seen": interventions_seen.duplicate(true), "suggestions": suggestions.duplicate(true),
			"mind_since_t": mind_since_t, "next_learning_t": next_learning_t, "ai": _ai_to_dict(),
			"tech": ProceduralKnowledge.to_save(tech)}}


## Speicherbare Modell-/Gesprächsdaten. Offene Anfragen werden NICHT gespeichert (beim Laden ungültig).
func _ai_to_dict() -> Dictionary:
	var d := ai.duplicate(true)
	var es := {}
	for k in ai["empty_seen"]:
		es[str(k)] = ai["empty_seen"][k]
	d["empty_seen"] = es
	var pair := {}
	for k in ai["talk"]["pair"]:
		pair[str(k)] = ai["talk"]["pair"][k]
	d["talk"] = {"next_t": ai["talk"]["next_t"], "pair": pair}
	var last: Dictionary = d.get("last", {})
	if str(last.get("status", "")) in ["wartet", "läuft", "wiederholt"]:
		last["status"] = "offen beim Speichern (wird beim Laden verworfen)"
	return d


static func ai_from_dict(src: Dictionary) -> Dictionary:
	var a := Creature.default_ai()
	if src.is_empty():
		return a
	for k in ["next_request_t", "notable_t"]:
		a[k] = float(src.get(k, a[k]))
	for k in ["fail_streak", "plan_seq", "next_hearsay_id", "notable_mem", "notable_asked"]:
		a[k] = int(src.get(k, a[k]))
	a["plan"] = src.get("plan", {}).duplicate(true)
	a["plan_history"] = src.get("plan_history", []).duplicate(true)
	a["notes"] = src.get("notes", []).duplicate(true)
	a["interpreted"] = src.get("interpreted", {}).duplicate(true)
	for k in src.get("failed_sigs", {}):
		a["failed_sigs"][str(k)] = float(src["failed_sigs"][k])
	for k in src.get("empty_seen", {}):
		a["empty_seen"][int(k)] = float(src["empty_seen"][k])
	var t: Dictionary = src.get("talk", {})
	a["talk"]["next_t"] = float(t.get("next_t", 0.0))
	for k in t.get("pair", {}):
		a["talk"]["pair"][int(k)] = float(t["pair"][k])
	for c in src.get("hearsay", []):
		var x: Dictionary = c.duplicate(true)
		for f in ["id", "speaker", "independent", "retold", "utterance"]:
			x[f] = int(x.get(f, 0))
		var ch: Array = []
		for v in x.get("chain", []):
			ch.append(int(v))
		x["chain"] = ch
		x["origin"]["creature"] = int(x["origin"]["creature"])
		x["subject"]["id"] = int(x["subject"].get("id", 0))
		a["hearsay"].append(x)
	var last: Dictionary = src.get("last", {}).duplicate(true)
	if str(last.get("status", "")).begins_with("offen beim Speichern"):
		last["status"] = "beim Laden verworfen"
		last["why"] = "Offene Anfragen gelten nach dem Laden nicht mehr; bei Bedarf wird neu gefragt."
	a["last"] = last
	var p: Dictionary = a["plan"]
	if not p.is_empty():
		p["request_id"] = int(p.get("request_id", 0))
		p["i"] = int(p.get("i", 0))
		p["id"] = int(p.get("id", 0))
		p["running"] = {}
		p["step_started_t"] = -1.0
		for s in p.get("steps", []):
			s["target"] = int(s["target"])
			if s["status"] == "läuft":
				s["status"] = "offen"
	return a


func _social_to_dict() -> Dictionary:
	var d := social.duplicate(true)
	var tc := {}
	for k in social["target_cooldown"]:
		tc[str(k)] = social["target_cooldown"][k]
	d["target_cooldown"] = tc
	return d


static func from_dict(d: Dictionary, materials: MaterialRegistry) -> Dictionary:
	var pr := BodyPlan.from_dict(d["plan"], materials)
	if not pr["ok"]:
		return {"ok": false, "errors": pr["errors"]}
	var c := Creature.new()
	c.id = int(d["id"])
	c.display_name = str(d["display_name"])
	c.plan = pr["plan"]
	c.base_genes = d.get("base_genes", {}).duplicate(true)
	c.plan_seed = int(d.get("plan_seed", 0))
	c.health = Health.from_dict(d.get("health", {}))
	c.metabolism = Metabolism.from_dict(d["metabolism"])
	c.position = Vector3(d["position"][0], d["position"][1], d["position"][2])
	c.heading = float(d.get("heading", 0.0))
	c.alive = bool(d.get("alive", true))
	c.death = d.get("death", {}).duplicate(true)
	c.carried_item_id = int(d.get("carried_item_id", 0))
	c.held_object_id = int(d.get("held_object_id", 0))
	for k in d.get("food_memory", {}):
		c.food_memory[int(k)] = d["food_memory"][k].duplicate(true)
	for k in d.get("unreachable", {}):
		c.unreachable[int(k)] = float(d["unreachable"][k])
	c.behavior_state = str(d.get("behavior_state", ""))
	c.behavior_reason = str(d.get("behavior_reason", ""))
	c.goal = d.get("goal", {}).duplicate()
	if c.goal.has("id"):
		c.goal["id"] = int(c.goal["id"])
	c.last_result = d.get("last_result", {}).duplicate(true)
	c.rng.seed = int(str(d.get("rng_seed", "0")))
	c.rng.state = int(str(d.get("rng_state", "0")))
	c.next_decision_t = float(d.get("next_decision_t", 0.0))
	c.next_perception_t = float(d.get("next_perception_t", 0.0))
	c.explore_attempts = int(d.get("explore_attempts", 0))
	c.behavior_enabled = bool(d.get("behavior_enabled", true))
	for k in d.get("stats", {}):
		c.stats[k] = d["stats"][k]
	var md: Dictionary = d.get("mind", {})
	if md.is_empty():
		return {"ok": false, "errors": ["Geistesdaten fehlen (Format 1 muss vorher migriert werden)."]}
	c.personality = Personality.from_dict(md["personality"])
	c.memory = MemoryStore.from_dict(md.get("memory", {}))
	c.beliefs = BeliefStore.from_dict(md.get("beliefs", {}))
	c.relations = RelationshipStore.from_dict(md.get("relations", {}))
	var ld: Dictionary = md.get("learning", {})
	c.learning = {"pending": ld.get("pending", []).duplicate(true), "pending_other": ld.get("pending_other", []).duplicate(true),
		"base_window_t": float(ld.get("base_window_t", 0.0)), "base_hit": bool(ld.get("base_hit", false)), "running_credited": int(ld.get("running_credited", 0))}
	for pq in c.learning["pending_other"]:
		pq["actor"] = int(pq["actor"])
	c.goal_state = md.get("goal_state", {}).duplicate(true)
	if c.goal_state.has("target"):
		c.goal_state["target"] = int(c.goal_state["target"])
	c.decision = md.get("decision", {}).duplicate(true)
	var sd: Dictionary = md.get("social", {})
	c.social = {"inbox": [], "pending_request": {}, "target_cooldown": {}, "next_request_t": float(sd.get("next_request_t", 0.0)),
		"next_approach_t": float(sd.get("next_approach_t", 0.0)), "holding_for_sharing": bool(sd.get("holding_for_sharing", false))}
	for r in sd.get("inbox", []):
		c.social["inbox"].append({"from": int(r["from"]), "t": float(r["t"]), "req": int(r.get("req", 0))})
	var preq: Dictionary = sd.get("pending_request", {})
	if not preq.is_empty():
		c.social["pending_request"] = {"to": int(preq["to"]), "t": float(preq["t"])}
	for k in sd.get("target_cooldown", {}):
		c.social["target_cooldown"][int(k)] = float(sd["target_cooldown"][k])
	c.interventions_seen = md.get("interventions_seen", []).duplicate(true)
	c.suggestions = md.get("suggestions", []).duplicate(true)
	c.mind_since_t = float(md.get("mind_since_t", 0.0))
	c.next_learning_t = float(md.get("next_learning_t", 0.0))
	c.ai = Creature.ai_from_dict(md.get("ai", {}))
	c.tech = ProceduralKnowledge.from_save(md.get("tech", {}))
	return {"ok": true, "creature": c}
