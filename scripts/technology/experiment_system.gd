class_name ExperimentSystem
extends RefCounted
## Versuche der Wesen (Prompt 6). Ein Versuch ist eine kurze Folge von Schritten, die AUSSCHLIESSLICH
## über das gemeinsame Handlungssystem ausgeführt werden (ActionExecutor). Ergebnisse entstehen aus
## Material, Geometrie, Energie, Körper und tatsächlich ausgeführten Schritten – nie aus einem
## Vorschlag allein. Es gibt keinen Technologiebaum und keine Freischaltung nach N Versuchen.
##
## Herkunft eines Versuchs (source): eigene Idee | Verfahren (Abwandlung/Wiederholung) | Übung |
## Vorführung | Modell (Ollama) | Modell (SIMULIERT) | Testwerkstatt (gezielt ausgelöst).
##
## Begrenzung eigenständiger Versuche: Hunger (max_hunger), Neugier und Vorsicht (Persönlichkeit),
## Zeitbudget (budget_share je budget_window_s), Abklingzeit, Risiko (heiße Gegenstände), Neuheit
## (bereits sicher bekannte Verfahren werden selten wiederholt), Ressourcen in der Nähe.
##
## Schritte (op): inspect, equip, release, strike, deform, connect, disconnect, heat, wait_molten,
##                pour, offer_demo, demonstrate, practice

const OPS := ["inspect", "equip", "release", "strike", "deform", "connect", "disconnect", "heat", "wait_molten", "pour", "offer_demo", "demonstrate", "practice", "bring"]
const OP_ACTION := {"inspect": "inspect_object", "equip": "equip_tool", "release": "drop", "strike": "strike_target", "deform": "deform_material",
	"connect": "connect_parts", "disconnect": "disconnect_parts", "heat": "place_in_heater", "wait_molten": "wait", "pour": "pour_into_mold",
	"demonstrate": "demonstrate_procedure", "practice": "practice_procedure", "bring": "drop"}
const OP_LABEL := {"inspect": "untersuchen", "equip": "in die Hand nehmen", "release": "ablegen", "strike": "einmal schlagen", "deform": "durch Schlagen verformen",
	"connect": "mit Fasern verbinden", "disconnect": "lösen", "heat": "Tiegel in die Heizung setzen", "wait_molten": "warten, bis es schmilzt",
	"pour": "in die Form gießen", "offer_demo": "Vorführung anbieten", "demonstrate": "vorführen", "practice": "üben",
	"bring": "hintragen und ablegen"}

var records: Dictionary = {}     # id -> ExperimentRecord (begrenzt, älteste abgeschlossene fallen heraus)
var next_id: int = 1
var stats := {"started": 0, "completed": 0, "failed": 0, "aborted": 0, "by_source": {}}


func active(cr: Creature) -> ExperimentRecord:
	var eid := int(cr.tech.get("experiment_id", 0))
	if eid == 0 or not records.has(eid):
		return null
	var r: ExperimentRecord = records[eid]
	return r if r.is_running() else null


func of_creature(cid: int) -> Array:
	var out: Array = []
	for id in records:
		if (records[id] as ExperimentRecord).actor_id == cid:
			out.append(records[id])
	out.sort_custom(func(a, b): return a.id > b.id)
	return out


# ── Start ───────────────────────────────────────

## plan: {kind, question, expected, steps:[{op, obj, target, tool, head, fiber, heater, mold, learner, params}],
##        source, hypothesis_id, procedure_key, learner, uncertainty}
func start(cr: Creature, plan: Dictionary, ctx: LifeContext) -> Dictionary:
	if cr == null or not cr.alive:
		return {"ok": false, "message": "Kein lebendes Wesen."}
	if active(cr) != null:
		return {"ok": false, "message": "Wesen #%d führt bereits Versuch #%d durch." % [cr.id, active(cr).id]}
	var steps: Array = plan.get("steps", [])
	if steps.is_empty() or steps.size() > int(ctx.tc("experiments").get("max_steps", 6)):
		return {"ok": false, "message": "Versuch braucht 1–%d Schritte." % int(ctx.tc("experiments").get("max_steps", 6))}
	for s in steps:
		if not (str(s.get("op", "")) in OPS):
			return {"ok": false, "message": "Unbekannter Schritt „%s“." % str(s.get("op", ""))}
	var r := ExperimentRecord.new()
	r.id = next_id
	next_id += 1
	r.actor_id = cr.id
	r.kind = str(plan.get("kind", "versuch"))
	r.question = str(plan.get("question", ""))
	r.expected = str(plan.get("expected", ""))
	r.source = str(plan.get("source", "eigene Idee"))
	r.hypothesis_id = int(plan.get("hypothesis_id", 0))
	r.procedure_key = str(plan.get("procedure_key", ""))
	r.learner_id = int(plan.get("learner", 0))
	r.uncertainty = float(plan.get("uncertainty", 0.8))
	r.proposed_steps = steps.duplicate(true)
	r.started_t = ctx.now()
	r.heater_j_start = _heater_total(ctx)
	_snapshot_initial(r, cr, ctx)
	records[r.id] = r
	cr.tech["experiment_id"] = r.id
	stats["started"] += 1
	stats["by_source"][r.source] = int(stats["by_source"].get(r.source, 0)) + 1
	cr.tech["stats"]["experiments"] = int(cr.tech["stats"]["experiments"]) + 1
	if r.kind == "demonstrate" and r.learner_id != 0:
		var tg: Dictionary = cr.tech["taught"]
		if not tg.has(r.learner_id):
			tg[r.learner_id] = {}
		tg[r.learner_id][r.procedure_key] = ctx.now()
	if r.hypothesis_id != 0:
		var h := ProceduralKnowledge.hypothesis(cr, r.hypothesis_id)
		if not h.is_empty():
			h["status"] = "wird geprüft"
			h["experiment_id"] = r.id
	_trim()
	ctx.log_event("experiment_started", [cr.id], {"experiment": r.id, "kind": r.kind, "source": r.source, "question": r.question})
	return {"ok": true, "record": r, "id": r.id, "message": "Versuch #%d begonnen: %s" % [r.id, r.question]}


func _trim() -> void:
	var cap := 200
	if records.size() <= cap:
		return
	var ids := records.keys()
	ids.sort()
	for id in ids:
		if records.size() <= cap:
			break
		if not (records[id] as ExperimentRecord).is_running():
			records.erase(id)


static func _heater_total(ctx: LifeContext) -> float:
	var s := 0.0
	for hid in ctx.heaters:
		var n := (ctx.heaters[hid] as TestHeater).heater_name()
		if ctx.sim.thermal.heaters.has(n):
			s += float(ctx.sim.thermal.heaters[n]["supplied_j"])
	return s


func _involved_ids(r: ExperimentRecord) -> Array:
	var ids: Array = []
	for s in r.proposed_steps:
		for f in ["obj", "target", "tool", "head", "fiber", "mold"]:
			var v := int(s.get(f, 0))
			if v != 0 and not (v in ids):
				ids.append(v)
	return ids


static func sim_state(ctx: LifeContext, id: int) -> Dictionary:
	if ctx.material_pieces.has(id):
		var p: MaterialPiece = ctx.material_pieces[id]
		return {"material": p.material_id, "shape": p.shape, "mass_kg": p.mass_kg, "temperature_k": snappedf(p.temperature_k(), 0.01),
			"liquid_fraction": snappedf(p.liquid_fraction(), 0.001), "dims_mm": [snappedf(p.dims_m.x * 1000, 0.01), snappedf(p.dims_m.y * 1000, 0.01), snappedf(p.dims_m.z * 1000, 0.01)],
			"strain": snappedf(p.strain, 0.0001), "damage": snappedf(p.damage, 0.0001), "wear": snappedf(p.wear, 0.0001), "assembly": p.assembly_id}
	if ctx.assemblies.has(id):
		var a: Assembly = ctx.assemblies[id]
		var cs: Array = []
		for c in a.connections:
			cs.append({"method": c["method"], "capacity_j": snappedf(float(c["capacity_j"]), 0.001), "wear": snappedf(float(c["wear"]), 0.0001), "strikes": c["strikes"]})
		return {"assembly": true, "parts": a.part_ids.duplicate(), "mass_kg": ConstructionSystem.mass_of(ctx, id), "connections": cs,
			"max_temperature_k": snappedf(ConstructionSystem.max_temperature_k(ctx, id), 0.01)}
	return {"exists": false}


static func perceived_state(ctx: LifeContext, cr: Creature, id: int) -> Dictionary:
	var top := ConstructionSystem.top_id(ctx, id)
	if top == 0:
		return {"sichtbar": "nicht mehr vorhanden"}
	var e := {"aussehen": "", "temperatur": ToolUseSystem.object_temperature_category(ctx, top)}
	var mp: MaterialPiece = ctx.material_pieces.get(id, null)
	if mp != null:
		e["aussehen"] = "%s, %s" % [ProceduralKnowledge._mat(mp.material_id), mp.shape_label()]
		e["groesse"] = "klein" if mp.size_m < 0.04 else ("mittel" if mp.size_m < 0.1 else "groß")
		if mp.damage >= 0.3:
			e["zustand"] = "rissig/abgesplittert"
	else:
		e["aussehen"] = "zusammengesetzter Gegenstand"
	return e


func _snapshot_initial(r: ExperimentRecord, cr: Creature, ctx: LifeContext) -> void:
	for id in _involved_ids(r):
		var top := ConstructionSystem.top_id(ctx, id)
		if top == 0:
			continue
		r.items.append({"id": id, "label": ConstructionSystem.label_of(ctx, id), "mass_kg": ConstructionSystem.mass_of(ctx, id)})
		r.sim_initial[id] = sim_state(ctx, id)
		r.perceived_initial[id] = perceived_state(ctx, cr, id)
		# Inhalte von Tiegeln mitschreiben (Schmelzprobe)
		for p in ConstructionSystem.parts_of(ctx, top):
			if (p as MaterialPiece).shape == "cup":
				for c in ConstructionSystem.contents_of(ctx, p.id):
					r.sim_initial[c.id] = sim_state(ctx, c.id)
					r.perceived_initial[c.id] = perceived_state(ctx, cr, c.id)


# ── Ausführung ──────────────────────────────────

## Nächsten Schritt über das Handlungssystem anfordern. Fügt bei Bedarf eine Annäherung ein.
## Rückgabe {ok, state, reason}.
func advance(cr: Creature, ctx: LifeContext) -> Dictionary:
	var r := active(cr)
	if r == null:
		return {"ok": false, "state": "", "reason": "kein laufender Versuch"}
	if ctx.executor.running.has(cr.id):
		return {"ok": true, "state": "versucht", "reason": "Schritt läuft"}
	if ctx.now() - r.started_t > float(ctx.tc("experiments").get("step_timeout_s", 40.0)) * maxi(1, r.proposed_steps.size()) + 30.0 * r.waits:
		_finish(cr, r, "abgebrochen", "Zeitbudget des Versuchs überschritten", ctx)
		return {"ok": false, "state": "", "reason": "Versuch zu lang"}
	if r.step_i >= r.proposed_steps.size():
		_finish(cr, r, "abgeschlossen", "", ctx)
		return {"ok": true, "state": "versuch_beendet", "reason": "Versuch #%d ausgewertet: %s" % [r.id, r.outcome]}
	var s: Dictionary = r.proposed_steps[r.step_i]
	var op := str(s["op"])
	if op == "offer_demo":
		return _offer_demo(cr, r, s, ctx)
	# Vorbereitung: liegen Kopf/Fasern zu weit vom Stiel, werden sie zuerst hingetragen (echte Handlungen)
	if op in ["connect", "demonstrate", "practice"] and not bool(s.get("gathered", false)):
		s["gathered"] = true
		var prep := _gather_steps(cr, s, ctx)
		if not prep.is_empty():
			for j in prep.size():
				r.proposed_steps.insert(r.step_i + j, prep[j])
			return advance(cr, ctx)
	if op == "bring":
		return _advance_bring(cr, r, s, ctx)
	var req := _request_for(cr, s, ctx)
	if req.is_empty():
		_step_failed(cr, r, s, "unbekannter Schritt", "unknown", ctx)
		return {"ok": false, "state": "", "reason": "unbekannter Schritt"}
	if op == "release" and cr.held_object_id == 0:
		r.executed_steps.append({"i": r.step_i, "op": op, "action": "-", "status": "übersprungen", "code": "ok", "message": "hält nichts", "t": ctx.now()})
		r.step_i += 1
		return advance(cr, ctx)
	if op == "equip" and cr.held_object_id == ConstructionSystem.top_id(ctx, int(s.get("obj", 0))) and cr.held_object_id != 0:
		r.executed_steps.append({"i": r.step_i, "op": op, "action": "-", "status": "übersprungen", "code": "ok", "message": "bereits in der Hand", "t": ctx.now()})
		r.step_i += 1
		return advance(cr, ctx)
	var dry := ctx.executor.dry_run(cr.id, req["type"], int(req["target"]), null, req["params"])
	if not dry.ok and dry.code == "out_of_reach":
		var p = _approach_pos(cr, s, ctx)
		s["approaches"] = int(s.get("approaches", 0)) + 1
		if p != null and int(s["approaches"]) <= MAX_APPROACHES:
			var mv := ctx.executor.request(cr.id, "move_to", 0, p, {"arrive_radius_m": 0.45})
			if mv["result"].ok:
				return {"ok": true, "state": "geht_zum_versuch", "reason": "Geht für Versuch #%d zu den Gegenständen (%s)." % [r.id, OP_LABEL.get(op, op)]}
	if not dry.ok and dry.code == "hands_full" and op in ["equip", "connect", "pour", "heat"] and cr.held_object_id != 0:
		var rel := ctx.executor.request(cr.id, "drop")
		if rel["result"].ok:
			return {"ok": true, "state": "legt_ab", "reason": "Legt #%d ab, um die Hand frei zu haben." % cr.held_object_id}
	if not dry.ok:
		_step_failed(cr, r, s, dry.message, dry.code, ctx)
		return {"ok": false, "state": "", "reason": "Voraussetzung fehlt: " + dry.message}
	var res := ctx.executor.request(cr.id, req["type"], int(req["target"]), null, req["params"])
	if not res["result"].ok:
		_step_failed(cr, r, s, res["result"].message, res["result"].code, ctx)
		return {"ok": false, "state": "", "reason": res["result"].message}
	return {"ok": true, "state": "versucht", "reason": "Versuch #%d, Schritt %d/%d: %s." % [r.id, r.step_i + 1, r.proposed_steps.size(), OP_LABEL.get(op, op)]}


func _request_for(cr: Creature, s: Dictionary, _ctx: LifeContext) -> Dictionary:
	var op := str(s["op"])
	if not OP_ACTION.has(op):
		return {}
	var p: Dictionary = (s.get("params", {}) as Dictionary).duplicate()
	var target := int(s.get("obj", s.get("target", 0)))
	match op:
		"strike", "deform":
			target = int(s.get("target", 0))
		"connect":
			target = int(s.get("obj", 0))
			p["head"] = int(s.get("head", 0))
			p["fiber"] = int(s.get("fiber", 0))
		"heat":
			p["heater"] = int(s.get("heater", 0))
		"pour":
			p["mold"] = int(s.get("mold", 0))
		"wait_molten":
			target = 0
			p["duration_s"] = 3.0
		"release":
			target = 0
		"demonstrate", "practice":
			target = int(s.get("learner", 0))
			p["key"] = str(s.get("key", ""))
			for f in ["target_piece", "handle", "head", "fiber"]:
				if s.has(f):
					p[f] = int(s[f])
	if op == "demonstrate" and int(s.get("learner", 0)) != 0:
		target = int(s["learner"])
	return {"type": OP_ACTION[op], "target": target, "params": p}


## Zusätzliche Schritte „hintragen und ablegen“ für Kopf und Fasern, die weiter als 70 % der Reichweite
## vom Stiel entfernt liegen (sonst wäre das Verbinden von keinem Standpunkt aus möglich).
func _gather_steps(cr: Creature, s: Dictionary, ctx: LifeContext) -> Array:
	var handle := int(s.get("obj", 0)) if str(s["op"]) == "connect" else int(s.get("handle", 0))
	var hp = ctx.position_of(handle) if handle != 0 else null
	if hp == null:
		return []
	var lim := TechActionUtil.reach_m(ctx) * 0.7
	var out: Array = []
	for f in ["head", "fiber"]:
		var id := int(s.get(f, 0))
		if id == 0 or not ctx.material_pieces.has(id):
			continue
		var mp: MaterialPiece = ctx.material_pieces[id]
		if mp.assembly_id != 0 or (mp.carrier_id == cr.id and cr.held_object_id == id):
			continue
		var p = ctx.position_of(id)
		if p != null and ctx.distance_xz(p, hp) > lim:
			out.append({"op": "bring", "obj": id, "target": handle, "auto": "Vorbereitung: Teile zusammenlegen"})
	return out


## Vorgang „hintragen und ablegen“: aufnehmen (equip_tool) → zum Ziel gehen (move_to) → ablegen (drop).
## Jede Teilhandlung läuft über den ActionExecutor mit allen Prüfungen (Temperatur, Masse, Hand frei).
func _advance_bring(cr: Creature, r: ExperimentRecord, s: Dictionary, ctx: LifeContext) -> Dictionary:
	var oid := int(s.get("obj", 0))
	var tid := int(s.get("target", 0))
	var po = ctx.position_of(oid)
	var pt = ctx.position_of(tid)
	if po == null or pt == null:
		_step_failed(cr, r, s, "Gegenstand nicht mehr vorhanden", "target_lost", ctx)
		return {"ok": false, "state": "", "reason": "Gegenstand nicht mehr vorhanden"}
	var top := ConstructionSystem.top_id(ctx, oid)
	var held := cr.held_object_id != 0 and cr.held_object_id == top
	var close := TechActionUtil.reach_m(ctx) * 0.45
	if not held:
		if ctx.distance_xz(po, pt) <= close:
			r.executed_steps.append({"i": r.step_i, "op": "bring", "action": "-", "status": "übersprungen", "code": "ok", "message": "liegt schon dort", "t": ctx.now()})
			r.step_i += 1
			return advance(cr, ctx)
		var dry := ctx.executor.dry_run(cr.id, "equip_tool", oid, null, {})
		if not dry.ok and dry.code == "out_of_reach":
			s["approaches"] = int(s.get("approaches", 0)) + 1
			if int(s["approaches"]) <= MAX_APPROACHES:
				var away: Vector3 = cr.position - po
				away.y = 0.0
				var dest: Vector3 = po + (away.normalized() if away.length() > 0.01 else Vector3.RIGHT) * 0.4
				var mv := ctx.executor.request(cr.id, "move_to", 0, dest, {"arrive_radius_m": 0.45})
				if mv["result"].ok:
					return {"ok": true, "state": "geht_zum_versuch", "reason": "Geht zu #%d, um es zu #%d zu bringen." % [oid, tid]}
		if not dry.ok and dry.code == "hands_full" and cr.held_object_id != 0:
			var rel := ctx.executor.request(cr.id, "drop")
			if rel["result"].ok:
				return {"ok": true, "state": "legt_ab", "reason": "Legt #%d ab, um die Hand frei zu haben." % cr.held_object_id}
		if not dry.ok:
			_step_failed(cr, r, s, dry.message, dry.code, ctx)
			return {"ok": false, "state": "", "reason": "Voraussetzung fehlt: " + dry.message}
		var eq := ctx.executor.request(cr.id, "equip_tool", oid)
		if not eq["result"].ok:
			_step_failed(cr, r, s, eq["result"].message, eq["result"].code, ctx)
			return {"ok": false, "state": "", "reason": eq["result"].message}
		return {"ok": true, "state": "versucht", "reason": "Versuch #%d: nimmt #%d, um es zu #%d zu bringen." % [r.id, oid, tid]}
	if ctx.distance_xz(cr.position, pt) > close:
		s["approaches_place"] = int(s.get("approaches_place", 0)) + 1
		if int(s["approaches_place"]) > MAX_APPROACHES:
			_step_failed(cr, r, s, "Ziel #%d nicht erreicht" % tid, "out_of_reach", ctx)
			return {"ok": false, "state": "", "reason": "Ziel nicht erreicht"}
		var away2: Vector3 = cr.position - pt
		away2.y = 0.0
		var dest2: Vector3 = pt + (away2.normalized() if away2.length() > 0.01 else Vector3.RIGHT) * 0.25
		var mv2 := ctx.executor.request(cr.id, "move_to", 0, dest2, {"arrive_radius_m": 0.15})
		if mv2["result"].ok:
			return {"ok": true, "state": "geht_zum_versuch", "reason": "Trägt #%d zu #%d." % [oid, tid]}
		_step_failed(cr, r, s, mv2["result"].message, mv2["result"].code, ctx)
		return {"ok": false, "state": "", "reason": mv2["result"].message}
	var dr := ctx.executor.request(cr.id, "drop", 0, null, {"object": true})
	if not dr["result"].ok:
		_step_failed(cr, r, s, dr["result"].message, dr["result"].code, ctx)
		return {"ok": false, "state": "", "reason": dr["result"].message}
	return {"ok": true, "state": "versucht", "reason": "Versuch #%d: legt #%d bei #%d ab." % [r.id, oid, tid]}


## Höchstens so viele Annäherungen je Schritt; liegen die Teile weiter auseinander als die Reichweite,
## schlägt der Schritt fehl („außer Reichweite“) statt endlos hin und her zu laufen.
const MAX_APPROACHES := 3


func _approach_pos(cr: Creature, s: Dictionary, ctx: LifeContext):
	var ids: Array = []
	for f in ["obj", "target", "head", "fiber", "mold", "heater", "target_piece", "handle"]:
		if int(s.get(f, 0)) != 0:
			ids.append(int(s[f]))
	var acc := Vector3.ZERO
	var n := 0
	for id in ids:
		if ConstructionSystem.top_id(ctx, id) == cr.held_object_id and cr.held_object_id != 0:
			continue
		var p = ctx.position_of(id)
		if p != null:
			acc += p
			n += 1
	if n == 0:
		return null
	var c: Vector3 = acc / n
	var away := cr.position - c
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.RIGHT
	return c + away.normalized() * 0.4


func _step_failed(cr: Creature, r: ExperimentRecord, s: Dictionary, msg: String, code: String, ctx: LifeContext) -> void:
	r.failures.append({"i": r.step_i, "op": str(s["op"]), "code": code, "message": msg, "t": ctx.now()})
	r.executed_steps.append({"i": r.step_i, "op": str(s["op"]), "action": OP_ACTION.get(str(s["op"]), ""), "status": "Voraussetzung fehlt", "code": code, "message": msg, "t": ctx.now()})
	_finish(cr, r, "fehlgeschlagen", "Schritt %d (%s): %s" % [r.step_i + 1, OP_LABEL.get(str(s["op"]), s["op"]), msg], ctx)


## Rückmeldung des Handlungssystems (Creature.on_action_finished).
func on_action_finished(cr: Creature, a: GameAction, ctx: LifeContext) -> void:
	var r := active(cr)
	if r == null or r.step_i >= r.proposed_steps.size():
		return
	var s: Dictionary = r.proposed_steps[r.step_i]
	var op := str(s["op"])
	if op == "bring" and a.type == "drop" and int(a.consumed.get("dropped_object", 0)) != ConstructionSystem.top_id(ctx, int(s.get("obj", 0))):
		return   # Hand frei machen, nicht der eigentliche Schritt
	if a.type == "move_to" or (a.type == "drop" and not op in ["release", "bring"]):
		if a.status != ActionDefinition.STATUS_SUCCEEDED and a.type == "move_to":
			_step_failed(cr, r, s, "nicht erreichbar: " + a.result_message, a.result_code, ctx)
		return
	if a.type != OP_ACTION.get(op, ""):
		return
	var entry := {"i": r.step_i, "op": op, "action": a.type, "status": a.status, "code": a.result_code, "message": a.result_message,
		"t": ctx.now(), "duration_s": snappedf(a.elapsed_s, 0.01), "data": _compact(a.consumed)}
	r.executed_steps.append(entry)
	r.effort["duration_s"] = float(r.effort["duration_s"]) + a.elapsed_s
	r.effort["mechanical_j"] = float(r.effort["mechanical_j"]) + float(a.consumed.get("mechanical_j", 0.0))
	r.effort["strikes"] = int(r.effort["strikes"]) + int(a.consumed.get("strikes", 0))
	r.effort["metabolic_j"] = float(r.effort["metabolic_j"]) + float(a.consumed.get("mechanical_j", 0.0)) / float(ctx.tc("strike").get("muscle_efficiency", 0.25))
	if op == "wait_molten":
		if a.status == ActionDefinition.STATUS_SUCCEEDED and _melt_visible(cr, s, ctx):
			r.perceived_results.append({"t": ctx.now(), "text": "Inhalt des Tiegels glüht und ist flüssig geworden"})
			r.step_i += 1
		else:
			r.waits += 1
			if r.waits * 3 > 600:
				_step_failed(cr, r, s, "schmilzt nicht (lange gewartet)", "not_liquid", ctx)
		return
	if a.status == ActionDefinition.STATUS_SUCCEEDED:
		r.step_i += 1
	elif a.status == ActionDefinition.STATUS_CANCELLED:
		_finish(cr, r, "abgebrochen", "Schritt %d abgebrochen: %s" % [r.step_i + 1, a.result_message], ctx)
	else:
		r.failures.append({"i": r.step_i, "op": op, "code": a.result_code, "message": a.result_message, "t": ctx.now()})
		# ein Fehlschlag nach tatsächlichem Tun ist Evidenz – Versuch wird ausgewertet
		_finish(cr, r, "fehlgeschlagen", "Schritt %d: %s" % [r.step_i + 1, a.result_message], ctx)


static func _compact(d: Dictionary) -> Dictionary:
	var c := d.duplicate(true)
	if c.has("log") and (c["log"] as Array).size() > 12:
		c["log"] = (c["log"] as Array).slice(-12)
	return c


func _melt_visible(cr: Creature, s: Dictionary, ctx: LifeContext) -> bool:
	var top := ConstructionSystem.top_id(ctx, int(s.get("obj", 0)))
	for p in ConstructionSystem.parts_of(ctx, top):
		if (p as MaterialPiece).shape == "cup":
			for c in ConstructionSystem.contents_of(ctx, p.id):
				var pos = ctx.position_of(c.id)
				if pos != null and ctx.distance_xz(cr.position, pos) <= float(ctx.c("perception").get("radius_m", 10.0)):
					if c.liquid_fraction() >= float(ctx.tc("casting").get("min_liquid_fraction", 0.95)):
						return true
	return false


func _offer_demo(cr: Creature, r: ExperimentRecord, s: Dictionary, ctx: LifeContext) -> Dictionary:
	var lid := int(s.get("learner", 0))
	var key := str(s.get("key", r.procedure_key))
	var l := ctx.creature(lid)
	if l == null or not l.alive:
		_step_failed(cr, r, s, "Zuschauer nicht mehr da", "target_lost", ctx)
		return {"ok": false, "state": "", "reason": "Zuschauer fehlt"}
	var topic := TeachingSystem.offer_topic(cr, key, ctx)
	var st := ctx.comm.start(cr, lid, topic, "lokal", ctx) if ctx.comm != null else {"ok": false, "message": "keine Kommunikation"}
	r.executed_steps.append({"i": r.step_i, "op": "offer_demo", "action": "talk", "status": "succeeded" if st["ok"] else "failed",
		"code": "ok" if st["ok"] else "talk_failed", "message": str(st["message"]), "t": ctx.now()})
	if not st["ok"]:
		# Angebot scheitert (z. B. zu weit, Abklingzeit) – Vorführung trotzdem für Sichtbare möglich
		r.failures.append({"i": r.step_i, "op": "offer_demo", "code": "talk_failed", "message": str(st["message"]), "t": ctx.now()})
	r.step_i += 1
	return {"ok": true, "state": "bietet_vorführung_an", "reason": "Bietet #%d eine Vorführung an: %s" % [lid, ProceduralKnowledge.describe_key(key)]}


## Laufenden Versuch abbrechen (Bedarf, Tod, Laden, Entwicklereingriff). Zwischenstand bleibt.
func abort(cr: Creature, reason: String, ctx: LifeContext) -> void:
	var r := active(cr)
	if r == null:
		return
	if ctx.executor.running.has(cr.id) and ctx.executor.running[cr.id].type in ActionDefinition.TECH_TYPES:
		ctx.executor.cancel(cr.id, "experiment_aborted", reason)
	if active(cr) != null:
		_finish(cr, r, "abgebrochen", reason, ctx)


# ── Auswertung ──────────────────────────────────

func _finish(cr: Creature, r: ExperimentRecord, status: String, note: String, ctx: LifeContext) -> void:
	if not r.is_running():
		return
	r.status = status
	r.ended_t = ctx.now()
	r.effort["heater_j"] = _heater_total(ctx) - r.heater_j_start
	cr.tech["experiment_id"] = 0
	var ec: Dictionary = ctx.tc("experiments")
	cr.tech["next_experiment_t"] = ctx.now() + float(ec.get("cooldown_s", 45.0))
	var b: Array = cr.tech["budget"]
	b.append([r.started_t, r.ended_t])
	while b.size() > 20:
		b.pop_front()
	for id in _involved_ids(r):
		r.sim_results[str(id)] = sim_state(ctx, id)
		var top := ConstructionSystem.top_id(ctx, id)
		if top != 0:
			for p in ConstructionSystem.parts_of(ctx, top):
				if (p as MaterialPiece).shape == "cup":
					for c in ConstructionSystem.contents_of(ctx, p.id):
						r.sim_results[str(c.id)] = sim_state(ctx, c.id)
	if note != "":
		r.perceived_results.append({"t": ctx.now(), "text": note})
	if status == "fehlgeschlagen":
		var fp: Dictionary = cr.tech.get("failed_plans", {})
		fp[r.question] = ctx.now()
		while fp.size() > 12:
			var oldest := ""
			var ot := INF
			for k in fp:
				if float(fp[k]) < ot:
					ot = float(fp[k])
					oldest = k
			fp.erase(oldest)
		cr.tech["failed_plans"] = fp
	var ev := _evaluate(cr, r, ctx)
	r.outcome = str(ev["outcome"])
	r.uncertainty = float(ev["uncertainty"])
	if status == "abgeschlossen" and not bool(ev["success"]) and r.outcome == "":
		r.outcome = "kein sichtbarer Effekt"
	match status:
		"abgeschlossen":
			stats["completed"] += 1
		"fehlgeschlagen":
			stats["failed"] += 1
		_:
			stats["aborted"] += 1
	if bool(ev["success"]):
		cr.tech["stats"]["successes"] = int(cr.tech["stats"]["successes"]) + 1
	elif bool(ev["evidence"]):
		cr.tech["stats"]["failures"] = int(cr.tech["stats"]["failures"]) + 1
	# Hypothese: nur ein ausgeführter Versuch liefert Evidenz
	if r.hypothesis_id != 0:
		var h := ProceduralKnowledge.hypothesis(cr, r.hypothesis_id)
		if not h.is_empty():
			if not bool(ev["evidence"]):
				h["status"] = "ungeprüft (Versuch #%d %s)" % [r.id, status]
			else:
				h["status"] = ("bestätigt durch Versuch #%d" if bool(ev["success"]) else "nicht bestätigt (Versuch #%d)") % r.id
			h["result"] = r.outcome
	ctx.log_event("experiment_finished", [cr.id], {"experiment": r.id, "status": status, "outcome": r.outcome, "source": r.source})


## Wertet aus, was das Wesen WAHRNEHMEN kann, und verbucht eigenes Verfahrenswissen.
## Rückgabe {success, evidence, outcome, uncertainty}
func _evaluate(cr: Creature, r: ExperimentRecord, ctx: LifeContext) -> Dictionary:
	var pc: Dictionary = ctx.tc("perception")
	var res := {"success": false, "evidence": false, "outcome": "", "uncertainty": r.uncertainty}
	var done_any := false
	for e in r.executed_steps:
		if str(e["status"]) in [ActionDefinition.STATUS_SUCCEEDED, ActionDefinition.STATUS_FAILED] and str(e.get("action", "-")) != "-" and str(e["action"]) != "talk":
			done_any = true
	if not done_any:
		res["outcome"] = "nicht ausgeführt – keine Evidenz"
		return res
	res["evidence"] = true
	for e in r.executed_steps:
		var d: Dictionary = e.get("data", {})
		match str(e["op"]):
			"inspect":
				if str(e["status"]) == ActionDefinition.STATUS_SUCCEEDED:
					var pv: Dictionary = d.get("perceived", {})
					r.perceived_results.append({"t": float(e["t"]), "text": "Untersucht: %s, %s, %s" % [pv.get("haerte", "?"), pv.get("gewicht", "nicht anhebbar"), pv.get("temperatur", "?")]})
					if not (d.get("burn", {}) as Dictionary).is_empty():
						r.perceived_results.append({"t": float(e["t"]), "text": "Beim Anfassen verbrannt – heiß!"})
					res["success"] = true
					res["outcome"] = "Eigenschaften wahrgenommen"
			"strike", "deform", "practice", "demonstrate":
				if not d.has("strikes"):
					if d.has("assembly"):
						_record_connect(cr, r, e, d, res, ctx)
					continue
				var key := str(d.get("key", ""))
				var t0 := float(d.get("thickness0_m", 0.0))
				var t1 := float(d.get("thickness_m", t0))
				var rel := (t0 - t1) / t0 if t0 > 0.0 else 0.0
				var vis := ""
				var ok := false
				if d.get("fractured", false):
					vis = "Werkstück zerbrochen"
					ok = true
				elif rel >= float(pc.get("visible_thickness_change", 0.05)):
					vis = "Werkstück sichtbar flacher geworden (deutlich)" if rel >= 0.15 else "Werkstück sichtbar flacher geworden"
					ok = true
				elif float(d.get("damage", 0.0)) - float(d.get("damage0", 0.0)) >= 0.3:
					vis = "Werkstück hat Risse/Absplitterungen"
					ok = true
				elif rel > 0.0:
					vis = "kaum eine Veränderung zu sehen"
				else:
					vis = "keine sichtbare Veränderung"
				r.perceived_results.append({"t": float(e["t"]), "text": "%d Schläge: %s" % [int(d["strikes"]), vis]})
				if d.get("tool_broke", false):
					r.perceived_results.append({"t": float(e["t"]), "text": "Werkzeug ist auseinandergebrochen (Kopf ab)"})
				var hd := 0.0
				for lg in d.get("log", []):
					hd += float(lg.get("hand", 0.0))
				if hd > 0.0:
					r.perceived_results.append({"t": float(e["t"]), "text": "Hand schmerzt nach den Schlägen"})
				if key != "":
					var mats: Array = []
					var tid := int(r.proposed_steps[int(e["i"])].get("target", r.proposed_steps[int(e["i"])].get("target_piece", 0)))
					var sim0: Dictionary = r.sim_initial.get(tid, {})
					if sim0.has("material"):
						mats.append(str(sim0["material"]))
					ProceduralKnowledge.record_own(ctx, cr, key, ok, mats, r.id, vis)
					r.procedure_key = key
				res["success"] = ok
				res["outcome"] = vis
				res["uncertainty"] = 0.35 if ok else 0.6
			"connect":
				_record_connect(cr, r, e, d, res, ctx)
			"pour":
				if str(e["status"]) == ActionDefinition.STATUS_SUCCEEDED:
					r.perceived_results.append({"t": float(e["t"]), "text": "Glühende Schmelze floss in die Form"})
					ProceduralKnowledge.record_own(ctx, cr, str(d.get("key", "")), true, [str(d.get("key", "")).split(":")[1]], r.id, "gegossen")
					r.procedure_key = str(d.get("key", ""))
					res["success"] = true
					res["outcome"] = "Gussstück in der Form"
					res["uncertainty"] = 0.3
				else:
					var cast_key := ProceduralKnowledge.cast_key("copper")
					ProceduralKnowledge.record_own(ctx, cr, cast_key, false, [], r.id, str(e["message"]))
					res["outcome"] = "Gießen fehlgeschlagen: %s" % str(e["message"])
			"heat":
				if str(e["status"]) == ActionDefinition.STATUS_SUCCEEDED:
					r.perceived_results.append({"t": float(e["t"]), "text": "Tiegel steht in der heißen Kiste"})
	if r.status == "fehlgeschlagen" and not res["success"] and res["outcome"] == "":
		res["outcome"] = "fehlgeschlagen: " + (str(r.failures[-1]["message"]) if not r.failures.is_empty() else "?")
	return res


func _record_connect(cr: Creature, r: ExperimentRecord, e: Dictionary, d: Dictionary, res: Dictionary, ctx: LifeContext) -> void:
	var key := str(d.get("practiced_key", d.get("key", "")))
	if str(e["status"]) == ActionDefinition.STATUS_SUCCEEDED and d.has("assembly"):
		r.perceived_results.append({"t": float(e["t"]), "text": "Kopf hält am Stiel (Verbund #%d)" % int(d["assembly"])})
		if key != "":
			ProceduralKnowledge.record_own(ctx, cr, key, true, key.split(":")[2].split("+"), r.id, "Kopf hält am Stiel")
			r.procedure_key = key
		res["success"] = true
		res["outcome"] = "Werkzeug zusammengesetzt"
		res["uncertainty"] = 0.4
	elif key != "":
		ProceduralKnowledge.record_own(ctx, cr, key, false, [], r.id, str(e["message"]))
		res["outcome"] = "Verbinden misslungen: %s" % str(e["message"])


# ── Takt ───────────────────────────────────────

## Treibt Versuche von Wesen ohne eigenes Verhalten (Testwerkstatt, gezielt ausgelöst) voran;
## mit Verhalten entscheidet DecisionSystem über „tech:continue“. Gegenstände sehen.
func tick(ctx: LifeContext) -> void:
	var ids := ctx.creatures.keys()
	ids.sort()
	for id in ids:
		var cr: Creature = ctx.creatures[id]
		if not cr.alive:
			if active(cr) != null:
				_finish(cr, active(cr), "abgebrochen", "Wesen gestorben", ctx)
			continue
		if not cr.behavior_enabled and active(cr) != null and not ctx.executor.running.has(id):
			advance(cr, ctx)


## Gegenstände in Sichtweite wahrnehmen (aufgerufen im Wahrnehmungstakt).
static func perceive_objects(cr: Creature, ctx: LifeContext) -> void:
	if ctx.material_pieces.is_empty() and ctx.heaters.is_empty():
		return
	var radius := float(ctx.c("perception").get("radius_m", 10.0)) * float(cr.caps.get("perception", 1.0))
	radius = minf(radius, float(ctx.tc("experiments").get("candidate_radius_m", 8.0)) * 1.5)
	var eye := cr.position + Vector3(0, float(ctx.c("perception").get("eye_height_m", 0.75)), 0)
	var seen := {}
	for mid in ctx.material_pieces:
		var mp: MaterialPiece = ctx.material_pieces[mid]
		var top: int = mp.assembly_id if mp.assembly_id != 0 else int(mid)
		if seen.has(top):
			continue
		var d := ctx.distance_xz(cr.position, mp.position)
		if d > radius:
			continue
		if d > 1.5 and not Perception._line_of_sight(ctx, eye, mp.position + Vector3(0, 0.05, 0), eye.distance_to(mp.position)):
			continue
		seen[top] = true
		ProceduralKnowledge.see_object(ctx, cr, top, d)
	for hid in ctx.heaters:
		var h: TestHeater = ctx.heaters[hid]
		var dh := ctx.distance_xz(cr.position, h.position)
		if dh <= radius:
			var objs: Dictionary = cr.tech["objects"]
			var e: Dictionary = objs.get(hid, {})
			e.merge({"id": hid, "seen_t": ctx.now(), "d": snappedf(dh, 0.1), "aussehen": "Heizkiste (Testausrüstung)", "form": "Heizung", "heater": true,
				"warm_spürbar": h.slot_id != 0 and dh <= float(ctx.tc("temperature").get("radiant_feel_m", 1.5))}, true)
			objs[hid] = e


# ── Eigenständige Kandidaten ────────────────────

## Zeitbudget: Anteil der letzten budget_window_s, der mit Versuchen verbracht wurde.
static func budget_used(cr: Creature, ctx: LifeContext) -> float:
	var ec: Dictionary = ctx.tc("experiments")
	var win := float(ec.get("budget_window_s", 600.0))
	var t0 := ctx.now() - win
	var s := 0.0
	for b in cr.tech["budget"]:
		s += maxf(0.0, float(b[1]) - maxf(float(b[0]), t0))
	return s / win


## Grund, warum gerade KEIN neuer Versuch möglich ist ("" = möglich).
func blocked_reason(cr: Creature, ctx: LifeContext) -> String:
	var ec: Dictionary = ctx.tc("experiments")
	if not bool(ec.get("enabled", true)):
		return "Versuche ausgeschaltet"
	if float(cr.caps.get("grasp", 0.0)) <= 0.0:
		return "keine Greifhand"
	if cr.metabolism.hunger() >= float(ec.get("max_hunger", 0.45)):
		return "zu hungrig"
	if ctx.now() < float(cr.tech.get("next_experiment_t", 0.0)):
		return "Abklingzeit"
	if budget_used(cr, ctx) >= float(ec.get("budget_share", 0.25)):
		return "Zeitbudget erschöpft"
	return ""


## Mögliche Versuche aus dem EIGENEN Wissen (wahrgenommene Gegenstände, bekannte Verfahren,
## ungeprüfte Hypothesen). Jeder Kandidat: plan + novelty + risk + dist.
func candidates(cr: Creature, ctx: LifeContext) -> Array:
	var out: Array = []
	var objs: Dictionary = cr.tech["objects"]
	var rad := float(ctx.tc("experiments").get("candidate_radius_m", 8.0))
	var near: Array = []
	for id in objs:
		var e: Dictionary = objs[id]
		if e.get("heater", false):
			continue
		var top := ConstructionSystem.top_id(ctx, int(id))
		if top != int(id) or top == 0:
			continue
		var p = ctx.position_of(top)
		if p == null or ctx.distance_xz(cr.position, p) > rad:
			continue
		near.append(e)
	# 1 Untersuchen
	for e in near:
		if not e.has("untersucht_t") and ConstructionSystem.carrier_of(ctx, int(e["id"])) == 0:
			var hot := str(e.get("temperatur", "")).contains("heiß") or str(e.get("temperatur", "")).contains("glüh")
			out.append({"plan": {"kind": "inspect", "question": "Was ist #%d (%s)?" % [int(e["id"]), ProceduralKnowledge._mat(str(e.get("aussehen", "?")))],
				"expected": "Eigenschaften erkennen", "steps": [{"op": "inspect", "obj": int(e["id"])}], "source": "eigene Idee"},
				"novelty": 1.0, "risk": 0.6 if hot else 0.05, "need": 0.0})
	var inspected := near.filter(func(e): return e.has("untersucht_t"))
	var tools: Array = []
	var targets: Array = []
	var rods: Array = []
	var heads: Array = []
	var fibers: Array = []
	for e in inspected:
		var id := int(e["id"])
		var cold := not (str(e.get("temperatur", "")).contains("heiß") or str(e.get("temperatur", "")).contains("glüh") or str(e.get("temperatur", "")).contains("warm") or str(e.get("temperatur", "")).contains("schmilzt") or str(e.get("temperatur", "")).contains("flüssig"))
		var free := ConstructionSystem.carrier_of(ctx, id) == 0 or ConstructionSystem.carrier_of(ctx, id) == cr.id
		if not free or ConstructionSystem.container_of(ctx, id) != 0:
			continue
		var liftable := str(e.get("gewicht", "")) in ["leicht", "mittel"]
		if e.get("assembly", false):
			if liftable and cold:
				tools.append(e)
			continue
		var form := str(e.get("form", ""))
		if liftable and cold and str(e.get("haerte", "")) in ["hart", "mittel"] and form in ConnectionDefinition.HEAD_SHAPES:
			tools.append(e)
			heads.append(e)
		if form in ["block", "lump", "ingot"] and cold:
			targets.append(e)
		if form == "rod" and liftable and cold:
			rods.append(e)
			tools.append(e)
		if form == "bundle" and str(e.get("aussehen", "")) == "plant_fiber":
			fibers.append(e)
	# 2 Schlagen (auch Werkzeug testen und Abwandeln: anderes Werkzeug auf bekanntes Ziel)
	for t in targets:
		for tool in tools:
			if int(tool["id"]) == int(t["id"]):
				continue
			var key := _guess_strike_key(ctx, cr, int(tool["id"]), int(t["id"]))
			var lv := ProceduralKnowledge.level(cr, key)
			var conf := float(cr.tech["procedures"].get(key, {}).get("confidence", 0.0))
			var nov := 1.0 if lv == "" else (0.5 if lv in ["gehört", "zugesehen"] else (0.35 if lv == "versucht" else 0.15 * (1.0 - conf)))
			var is_tool_test: bool = tool.get("assembly", false) and lv == ""
			out.append({"plan": {"kind": "test_tool" if is_tool_test else "deform",
				"question": "Was passiert mit #%d, wenn ich mit #%d darauf schlage?" % [int(t["id"]), int(tool["id"])],
				"expected": "Werkstück verändert seine Form", "procedure_key": key,
				"steps": [{"op": "equip", "obj": int(tool["id"])}, {"op": "deform", "target": int(t["id"]), "params": {"strikes": 8}}],
				"source": "eigene Idee" if lv == "" else "Verfahren (Wiederholung/Abwandlung)"},
				"novelty": nov, "risk": 0.1, "need": 0.0})
		# unbewaffnet
		var hk := ProceduralKnowledge.strike_key("Hand", "Hand", str(t.get("aussehen", "")))
		if ProceduralKnowledge.level(cr, hk) == "" and cr.held_object_id == 0:
			out.append({"plan": {"kind": "deform", "question": "Kann ich #%d mit der Hand verändern?" % int(t["id"]), "expected": "Werkstück verändert seine Form",
				"procedure_key": hk, "steps": [{"op": "release"}, {"op": "deform", "target": int(t["id"]), "params": {"strikes": 3}}], "source": "eigene Idee"},
				"novelty": 0.6, "risk": 0.2, "need": 0.0})
	# 3 Verbinden
	for rod in rods:
		for head in heads:
			if int(head["id"]) == int(rod["id"]):
				continue
			for fb in fibers:
				var lk := ProceduralKnowledge.lashing_key(str(rod.get("aussehen", "")), str(head.get("aussehen", "")))
				var lv2 := ProceduralKnowledge.level(cr, lk)
				var nov2 := 1.0 if lv2 == "" else (0.6 if lv2 in ["gehört", "zugesehen", "versucht"] else 0.1)
				out.append({"plan": {"kind": "connect", "question": "Hält #%d am Stab #%d, wenn ich Fasern #%d darum wickle?" % [int(head["id"]), int(rod["id"]), int(fb["id"])],
					"expected": "Ein zusammengesetzter Gegenstand entsteht", "procedure_key": lk,
					"steps": [{"op": "release"}, {"op": "connect", "obj": int(rod["id"]), "head": int(head["id"]), "fiber": int(fb["id"])}],
					"source": "eigene Idee" if lv2 == "" else "Verfahren (Wiederholung/Abwandlung)"},
					"novelty": nov2, "risk": 0.05, "need": 0.0})
	# 4 Gießen (nur mit bekannter Heizung, Tiegel mit Inhalt und Form)
	var heater_id := 0
	for id in objs:
		if objs[id].get("heater", false) and ctx.heaters.has(int(id)) and (ctx.heaters[int(id)] as TestHeater).slot_id == 0:
			heater_id = int(id)
	if heater_id != 0:
		var crucible := 0
		var mold := 0
		for e in inspected:
			var top2 := int(e["id"])
			for p in ConstructionSystem.parts_of(ctx, top2):
				if (p as MaterialPiece).shape == "cup" and not ConstructionSystem.contents_of(ctx, p.id).is_empty():
					crucible = top2
				if (p as MaterialPiece).shape == "mold" and ConstructionSystem.contents_of(ctx, p.id).is_empty():
					mold = top2
		if crucible != 0 and mold != 0:
			var ck := ProceduralKnowledge.cast_key("copper")
			var lv3 := ProceduralKnowledge.level(cr, ck)
			out.append({"plan": {"kind": "cast", "question": "Was geschieht mit dem Inhalt von Tiegel #%d in der heißen Kiste #%d?" % [crucible, heater_id],
				"expected": "Inhalt verändert sich durch Wärme", "procedure_key": ck,
				"steps": [{"op": "release"}, {"op": "heat", "obj": crucible, "heater": heater_id}, {"op": "wait_molten", "obj": crucible}, {"op": "pour", "obj": crucible, "mold": mold}],
				"source": "eigene Idee" if lv3 == "" else "Verfahren (Wiederholung/Abwandlung)"},
				"novelty": 1.0 if lv3 == "" else 0.2, "risk": 0.5, "need": 0.0})
	# 5 Ungeprüfte Hypothesen (eigene oder vom Modell vorgeschlagene) – nur Vorschlag, Versuch liefert Evidenz
	for h in cr.tech["hypotheses"]:
		if str(h["status"]) != "ungeprüft":
			continue
		out.append({"plan": {"kind": str(h.get("kind", "versuch")), "question": str(h.get("question", "")), "expected": str(h.get("expected", "")),
			"steps": h["steps"].duplicate(true), "source": str(h.get("source", "Modell")), "hypothesis_id": int(h["id"]), "uncertainty": float(h.get("uncertainty", 0.8))},
			"novelty": 0.9, "risk": float(h.get("risk", 0.2)), "need": 0.1})
	return out


## Verfahrensschlüssel, den ein Schlag mit tool auf target ergäbe (aus Wahrnehmung: Aussehen/Form).
static func _guess_strike_key(ctx: LifeContext, cr: Creature, tool_id: int, target_id: int) -> String:
	var e: Dictionary = cr.tech["objects"].get(tool_id, {})
	var t: Dictionary = cr.tech["objects"].get(target_id, {})
	var contact := str(e.get("aussehen", "?"))
	var form := "Stück"
	if e.get("assembly", false):
		form = "Stab"
		for p in e.get("parts", []):
			if str(p.get("rolle", "")) == "head":
				contact = str(p.get("aussehen", "?"))
				form = "Stiel+Kopf"
		if form == "Stab":
			for p in e.get("parts", []):
				if str(p.get("rolle", "")) == "handle":
					contact = str(p.get("aussehen", "?"))
	elif str(e.get("form", "")) == "rod":
		form = "Stab"
	return ProceduralKnowledge.strike_key(contact, form, str(t.get("aussehen", "?")))


# ── Optionen für DecisionSystem ─────────────────

## Optionen für die gemeinsame Nutzwertbewertung (DecisionSystem). Nur lokale Daten des Wesens.
func options(cr: Creature, ctx: LifeContext, free: float, critical: bool) -> Array:
	var out: Array = []
	if critical:
		return out
	var ec: Dictionary = ctx.tc("experiments")
	var pers := cr.personality
	var r := active(cr)
	if r != null:
		out.append({"id": "tech:continue", "goal": "experiment", "u": 0.0, "parts": {"versuch_fortsetzen": float(ec.get("weight", 0.6)) * (0.6 + 0.6 * pers.v("beharrlichkeit")) * free + 0.15}})
		_sum(out[-1])
		return out
	if blocked_reason(cr, ctx) == "":
		var best := {}
		var best_u := -1.0e9
		var failed: Dictionary = cr.tech.get("failed_plans", {})
		var fail_s := float(ec.get("failed_plan_memory_s", 300.0))
		for c in candidates(cr, ctx):
			# eben erst an einer Voraussetzung gescheitert → vorerst wenig reizvoll (keine Endlosschleife)
			if ctx.now() - float(failed.get(str(c["plan"].get("question", "")), -1.0e9)) < fail_s:
				c["novelty"] = float(c["novelty"]) * float(ec.get("failed_plan_novelty_factor", 0.2))
			var dist := _plan_distance(cr, c["plan"], ctx)
			c["dist"] = dist
			var u := float(ec.get("weight", 0.6)) * pers.v("neugier") * float(c["novelty"]) * free + float(c["need"]) \
				- float(ec.get("risk_weight", 0.5)) * pers.v("vorsicht") * float(c["risk"]) - float(ec.get("distance_weight_per_m", 0.004)) * dist
			if u > best_u:
				best_u = u
				best = c
		if not best.is_empty() and best_u > 0.02:
			out.append({"id": "tech:start", "goal": "experiment", "u": best_u, "parts": {"neugier": float(ec.get("weight", 0.6)) * pers.v("neugier") * float(best["novelty"]) * free,
				"risiko": -float(ec.get("risk_weight", 0.5)) * pers.v("vorsicht") * float(best["risk"]), "bedarf": float(best["need"]),
				"weg": -float(ec.get("distance_weight_per_m", 0.004)) * float(best["dist"])}, "plan": best["plan"]})
	out.append_array(TeachingSystem.options(cr, ctx, free))
	return out


## Weg zum nächsten Gegenstand des Plans (m, XZ); gehaltene Gegenstände zählen 0.
static func _plan_distance(cr: Creature, plan: Dictionary, ctx: LifeContext) -> float:
	var best := INF
	for s in plan.get("steps", []):
		for f in ["obj", "target", "handle", "head", "fiber", "mold", "heater"]:
			var id := int(s.get(f, 0))
			if id == 0:
				continue
			if ConstructionSystem.top_id(ctx, id) == cr.held_object_id and cr.held_object_id != 0:
				return 0.0
			var p = ctx.position_of(id)
			if p != null:
				best = minf(best, ctx.distance_xz(cr.position, p))
	return 0.0 if best == INF else best


static func _sum(o: Dictionary) -> void:
	var u := 0.0
	for k in o["parts"]:
		u += float(o["parts"][k])
	o["u"] = u


func execute_option(cr: Creature, o: Dictionary, ctx: LifeContext) -> Dictionary:
	match str(o["id"]):
		"tech:continue":
			return advance(cr, ctx)
		"tech:start", "tech:teach", "tech:practice":
			var st := start(cr, o["plan"], ctx)
			if not st["ok"]:
				return {"ok": false, "state": "", "reason": st["message"]}
			var a := advance(cr, ctx)
			if not a["ok"] and active(cr) == null:
				return {"ok": false, "state": "", "reason": a["reason"]}
			return {"ok": true, "state": "versucht", "reason": "%s (Herkunft: %s). %s" % [st["message"], (st["record"] as ExperimentRecord).source, a["reason"]]}
		"tech:watch":
			return TeachingSystem.execute_watch(cr, o, ctx)
		"tech:explain":
			var s2 := ctx.comm.start(cr, int(o["target"]), o["topic"], "lokal", ctx)
			if s2["ok"]:
				TeachingSystem.mark_explained(cr, int(o["target"]), str(o["topic"]["statement"]["key"]), ctx)
			return {"ok": s2["ok"], "state": "erklärt", "reason": s2["message"]}
	return {"ok": false, "state": "", "reason": "unbekannte Technikoption"}


# ── Speichern ───────────────────────────────────

func to_dict() -> Dictionary:
	var recs: Array = []
	var ids := records.keys()
	ids.sort()
	for id in ids:
		recs.append((records[id] as ExperimentRecord).to_dict())
	return {"next_id": next_id, "records": recs, "stats": stats.duplicate(true)}


static func from_dict(d: Dictionary) -> ExperimentSystem:
	var s := ExperimentSystem.new()
	s.next_id = int(d.get("next_id", 1))
	for rd in d.get("records", []):
		var r := ExperimentRecord.from_dict(rd)
		s.records[r.id] = r
	var st: Dictionary = d.get("stats", {})
	for k in st:
		s.stats[k] = st[k].duplicate(true) if st[k] is Dictionary else st[k]
	for k in ["started", "completed", "failed", "aborted"]:
		s.stats[k] = int(s.stats.get(k, 0))
	if not s.stats.get("by_source", null) is Dictionary:
		s.stats["by_source"] = {}
	return s


## Nach dem Laden: laufende Versuche gelten als unterbrochen (keine rückwirkende Entdeckung,
## keine Fortsetzung mit möglicherweise veralteten Annahmen). Rückgabe: Hinweise.
func after_load(ctx: LifeContext) -> Array:
	var notes: Array = []
	for id in records:
		var r: ExperimentRecord = records[id]
		if r.is_running():
			r.status = "unterbrochen"
			r.ended_t = ctx.now()
			r.outcome = "beim Laden unterbrochen – ausgeführte Schritte bleiben wirksam, keine Auswertung"
			var cr := ctx.creature(r.actor_id)
			if cr != null:
				cr.tech["experiment_id"] = 0
				cr.tech["next_experiment_t"] = ctx.now() + 5.0
				for h in cr.tech["hypotheses"]:
					if int(h.get("experiment_id", 0)) == r.id:
						h["status"] = "ungeprüft"
			notes.append("Versuch #%d von #%d beim Laden unterbrochen" % [r.id, r.actor_id])
	return notes
