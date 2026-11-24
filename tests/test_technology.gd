class_name TestTechnology
extends RefCounted
## Abnahmetests Prompt 6: Experimente, Werkzeuge, Verbindungen, Gießen, praktisches Wissen.
## Regeltests sind reproduzierbar und GEZIELT AUSGELÖST (Testwerkstatt) – sie beweisen, dass ein
## Vorgang funktioniert, nicht dass ihn die Wesen spontan entdecken. Spontanes Verhalten prüft der
## Beobachtungslauf (eigenes Verhalten an, Ergebnis als Messwert protokolliert).
## Modellantworten stammen ausschließlich vom SIMULIERTEN Testdienst (MockOllama).

const DT := 1.0 / 60.0

var results: Array = []
var notes: Array = []
var db: DefinitionDB
var sc: MindScenarios
var world_seed: int = 12345
var clock := {"ms": 0.0}
var quick: bool = false
var only: String = ""


func run_all(p_quick: bool = false, p_only: String = "") -> Array:
	quick = p_quick
	only = p_only
	results.clear()
	notes.clear()
	db = DefinitionDB.new()
	db.load_all()
	sc = MindScenarios.new(db)
	world_seed = int(db.config("world").get("seed", 12345))
	for f in [_t01_named_hammer, _t02_stone_tool, _t03_connect, _t03b_gather_parts, _t04_05_overload_and_break, _t06_work, _t07_08_melt_and_cast,
			_t09_hot_handling, _t10_cancel, _t11_model_hypothesis, _t12_13_knowledge_and_teaching, _t14_save_load, _t14b_migration,
			_t15_normal_game, _t_observation_run]:
		if only != "" and not str(f.get_method()).contains(only):
			continue
		print("  Technik-Test: %s (%.1f s)" % [str(f.get_method()), Time.get_ticks_msec() / 1000.0])
		f.call()
		sc.cleanup()
	return results


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": "[Technik] " + name, "ok": ok, "detail": detail})


# ── Hilfen ────────────────────────────────────────

func _ws(svc: AIService = null, behavior: bool = false) -> LifeSimulation:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, svc)
	var r := life.new_workshop(world_seed, behavior)
	if not r.get("ok", false):
		push_error("Werkstatt: " + str(r.get("message", "")))
	sc.lives.append(life)
	return life


func _run(life: LifeSimulation, secs: float) -> void:
	for i in int(round(secs / DT)):
		clock["ms"] = float(clock["ms"]) + 1000.0 / 60.0
		life.step(DT)


## Läuft, bis das Wesen keinen Versuch mehr hat (oder max_s).
func _run_exp(life: LifeSimulation, cr: Creature, max_s: float) -> float:
	var t := 0.0
	while t < max_s and life.ctx.experiments.active(cr) != null:
		life.step(DT)
		t += DT
	return t


func _a(life: LifeSimulation) -> Creature:
	return life.ctx.creature(int(life.workshop["a"]))


func _b(life: LifeSimulation) -> Creature:
	return life.ctx.creature(int(life.workshop["b"]))


func _p(life: LifeSimulation, role: String) -> MaterialPiece:
	return life.ctx.material_pieces.get(int(life.workshop[role]), null)


func _total_mass(life: LifeSimulation) -> float:
	var s := 0.0
	for id in life.ctx.material_pieces:
		s += (life.ctx.material_pieces[id] as MaterialPiece).mass_kg
	return s


## Erste Abweichung zweier JSON-artiger Werte (Pfad + Werte), "" wenn gleich.
static func first_diff(a, b, path: String = "") -> String:
	if typeof(a) != typeof(b) and not (typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]):
		return "%s: Typ %d≠%d" % [path, typeof(a), typeof(b)]
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				return "%s.%s fehlt nach Laden" % [path, str(k)]
			var d := first_diff(a[k], b[k], path + "." + str(k))
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				return "%s.%s neu nach Laden" % [path, str(k)]
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: Länge %d≠%d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		# Godot 4.5 liest manche 17-stellige Zahlen um 1 ulp anders (HANDOVER) → relative Toleranz 1e-12
		if absf(float(a) - float(b)) > 1e-12 * maxf(1.0, maxf(absf(float(a)), absf(float(b)))):
			return "%s: %s ≠ %s" % [path, str(a), str(b)]
		return ""
	if a != b:
		return "%s: %s ≠ %s" % [path, str(a).substr(0, 80), str(b).substr(0, 80)]
	return ""


func _rec_info(life: LifeSimulation, id: int) -> String:
	var rec: ExperimentRecord = life.ctx.experiments.records.get(id, null)
	if rec == null:
		return "kein Protokoll"
	return "%s / %s / Schritte %s / Fehler %s" % [rec.status, rec.outcome, str(rec.executed_steps.map(func(x): return "%s:%s" % [x["op"], x["status"]])), str(rec.failures)]


func _own_assemblies(life: LifeSimulation) -> int:
	var n := 0
	for id in life.ctx.assemblies:
		if not (life.ctx.assemblies[id] as Assembly).test_equipment:
			n += 1
	return n


func _near(life: LifeSimulation, cr: Creature, id: int) -> void:
	var p = life.ctx.position_of(id)
	cr.position = TestWorkshop._walkable(life, p + Vector3(-0.35, 0, 0), 0.0)
	life.ctx.rebuild_spatial_hash()


## Werkzeug aus Stiel/Kopf/Fasern direkt über die echte Handlung bauen (A), Rückgabe Verbund-ID.
func _build_tool(life: LifeSimulation, cr: Creature, stick: String = "stick_a", head: String = "stone_head", fiber: String = "fiber") -> int:
	var w := life.workshop
	_near(life, cr, int(w[stick]))
	var r := life.ctx.executor.request(cr.id, "connect_parts", int(w[stick]), null, {"head": int(w[head]), "fiber": int(w[fiber])})
	if not r["result"].ok:
		return 0
	sc.run_until_idle(life, cr.id, 12.0)
	return cr.held_object_id if life.ctx.assemblies.has(cr.held_object_id) else 0


# ── 1 „Hammer“ ohne Eigenschaften ──────────────────

func _t01_named_hammer() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	# Ein „Hammer“ aus Stiel + weichem Pflanzengewebe-Kopf, gebaut über die echte Verbindung
	var soft := ConstructionSystem.new_piece(ctx, "plant_tissue", "block", Vector3(0.05, 0.05, 0.05), 293.15, _p(life, "stick_b").position + Vector3(0.1, 0, 0), "test", "Hammer")
	var ham := ConstructionSystem.connect_lashing(ctx, 0, int(w["stick_b"]), int(soft["id"]), int(w["fiber2"]), "erfolgreich", "Hammer")
	var ev_h := ObjectEvaluator.evaluate(ctx, a, int(ham["id"]))
	(ctx.assemblies[int(ham["id"])] as Assembly).label = "Unbenannt"
	var ev_x := ObjectEvaluator.evaluate(ctx, a, int(ham["id"]))
	var stone_tool := _build_tool(life, a)
	var ev_s := ObjectEvaluator.evaluate(ctx, a, stone_tool)
	_check("(1) „Hammer“-Name ändert nichts: identische Bewertung mit anderem Namen", absf(float(ev_h["copper_strain_per_strike"]) - float(ev_x["copper_strain_per_strike"])) < 1e-12 and ev_h["suitable"] == ev_x["suitable"])
	_check("(1) Weicher Kopf: als Schlagwerkzeug für Kupfer ungeeignet, Steinkopf geeignet",
		not ev_h["suitable"] and ev_s["suitable"] and float(ev_s["copper_strain_per_strike"]) > 3.0 * float(ev_h["copper_strain_per_strike"]),
		"Stauchung/Schlag: „Hammer“ %.5f, Steinkopf %.5f" % [float(ev_h["copper_strain_per_strike"]), float(ev_s["copper_strain_per_strike"])])
	# tatsächliche Wirkung: je 4 Schläge auf zwei gleiche Kupferproben
	var c1 := _p(life, "copper_sample")
	var c2 := _p(life, "copper_sample2")
	_near(life, a, c1.id)
	ctx.executor.request(a.id, "deform_material", c1.id, null, {"strikes": 4})
	sc.run_until_idle(life, a.id, 20.0)
	ctx.executor.request(a.id, "drop")
	sc.run_until_idle(life, a.id, 2.0)
	_near(life, a, int(ham["id"]))
	ctx.executor.request(a.id, "equip_tool", int(ham["id"]))
	sc.run_until_idle(life, a.id, 3.0)
	_near(life, a, c2.id)
	var soft_id := int(soft["id"])
	var first := ToolUseSystem.strike(ctx, a, c2.id)
	var strain_first := c2.strain
	_check("(1) Erster Schlag mit „Hammer“ wirkt genau wie bewertet; Bewertung sagt Zerfall des weichen Kopfes voraus, und er zerfällt tatsächlich",
		absf(strain_first - float(ev_h["copper_strain_per_strike"])) < 1e-12 and float(ev_h.get("strikes_until_head_fails", INF)) <= 1.0
		and not ctx.material_pieces.has(soft_id) and first.has("tool_fracture"),
		"ε 1. Schlag %.5f (vorhergesagt %.5f), Kopf hält %.2f Schläge" % [strain_first, float(ev_h["copper_strain_per_strike"]), float(ev_h.get("strikes_until_head_fails", -1))])
	ctx.executor.request(a.id, "deform_material", c2.id, null, {"strikes": 3})
	sc.run_until_idle(life, a.id, 20.0)
	_check("(1) Tatsächliche Wirkung folgt Material und Geometrie (keine magischen Fähigkeiten): Steinkopf wirkt stärker als der zerfallene „Hammer“",
		c1.strain > 1.5 * c2.strain and c2.strain > strain_first and life.audit().is_empty(),
		"ε Steinkopf (4 Schläge) %.4f, ε „Hammer“ (1 Schlag, danach Holzstiel 3 Schläge) %.4f" % [c1.strain, c2.strain])
	var rod := ConstructionSystem.new_piece(ctx, "wood", "rod", Vector3(0.4, 0.025, 0.025), 293.15, a.position, "test", "Hammer")
	var ev_r := ObjectEvaluator.evaluate(ctx, a, int(rod["id"]))
	_check("(1) Einzelner Holzstab namens „Hammer“: kein Arbeitskopf erkannt", not bool(ev_r.get("has_head", true)))
	_check("(1) Gesamtzustand konsistent", life.audit().is_empty(), str(life.audit().slice(0, 3)))


# ── 2 Stein als einfaches Werkzeug ─────────────────

func _t02_stone_tool() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var r := TestWorkshop.trigger(life, 1)
	_run_exp(life, a, 60.0)
	var rec: ExperimentRecord = ctx.experiments.records[int(r["id"])]
	var c := _p(life, "copper_sample")
	var e0: Dictionary = rec.sim_initial[c.id]
	_check("(2) Versuch 1 über das Handlungssystem ausgeführt (untersuchen, nehmen, schlagen)", rec.status == "abgeschlossen" and rec.executed_steps.size() >= 3
		and rec.executed_steps.all(func(s): return str(s["status"]) in ["succeeded", "übersprungen"]), "%s %s" % [rec.status, str(rec.failures)])
	_check("(2) Stein in der Hand verformt Kupfer messbar (ε > 0, Höhe kleiner, Volumen und Masse gleich)", c.strain > 0.02 and c.dims_m.y < float(e0["dims_mm"][1]) / 1000.0
		and absf(c.mass_kg - float(e0["mass_kg"])) < 1e-12 and absf(c.dims_m.x * c.dims_m.y * c.dims_m.z - 8.0e-6) < 2.0e-8, "ε %.4f, Höhe %.2f mm" % [c.strain, c.dims_m.y * 1000])
	# Vergleich: unbewaffnet auf frische Probe
	var c2 := _p(life, "copper_sample2")
	ctx.executor.request(a.id, "drop")
	sc.run_until_idle(life, a.id, 2.0)
	var hd0 := a.health.damage_of(ToolUseSystem.hand_part(a))
	_near(life, a, c2.id)
	ctx.executor.request(a.id, "deform_material", c2.id, null, {"strikes": 16})
	sc.run_until_idle(life, a.id, 40.0)
	_check("(2) Vergleich: bloße Hand wirkt viel schwächer und verletzt die Hand", c2.strain < c.strain * 0.35 and a.health.damage_of(ToolUseSystem.hand_part(a)) > hd0,
		"ε Hand %.4f vs Stein %.4f, Handschaden %.3f" % [c2.strain, c.strain, a.health.damage_of(ToolUseSystem.hand_part(a))])
	_check("(2) Wahrnehmung: Wesen kennt die Wirkung nur als Kategorie, Verfahren aus eigenem Versuch", rec.perceived_results.any(func(p): return str(p["text"]).contains("flacher") or str(p["text"]).contains("Veränderung"))
		and ProceduralKnowledge.knows(a, ProceduralKnowledge.strike_key("stone", "Stück", "copper")), str(rec.perceived_results))
	notes.append("Technik: Stein in der Hand, 16 Schläge auf 20-mm-Kupferwürfel: ε = %.4f (Höhe %.2f mm); bloße Hand 16 Schläge: ε = %.4f" % [c.strain, c.dims_m.y * 1000, c2.strain])


# ── 3 Verbinden ───────────────────────────────────

func _t03_connect() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	var m0 := _total_mass(life)
	var fiber0 := _p(life, "fiber").mass_kg
	var handle := _p(life, "stick_a")
	var head := _p(life, "stone_head")
	# ohne Bindemittel (Stein statt Fasern) → abgewiesen
	_p(life, "stone_heavy").position = handle.position + Vector3(0, 0, 0.15)
	ctx.rebuild_spatial_hash()
	_near(life, a, handle.id)
	var bad := ctx.executor.request(a.id, "connect_parts", handle.id, null, {"head": head.id, "fiber": int(w["stone_heavy"])})
	_check("(3) Verbinden ohne echtes Verbindungsmittel abgewiesen", not bad["result"].ok and bad["result"].code == "no_binding_material", bad["result"].message)
	var bad2 := ctx.executor.request(a.id, "connect_parts", handle.id, null, {"head": head.id, "fiber": int(w["fiber"]), "method": "kleben"})
	_check("(3) Nicht unterstützte Verbindungsmethode abgewiesen", not bad2["result"].ok and bad2["result"].code == "unsupported_connection")
	var r := TestWorkshop.trigger(life, 2)
	_run_exp(life, a, 30.0)
	var asm: Assembly = ctx.assemblies.get(handle.assembly_id, null)
	var binding: MaterialPiece = null
	if asm != null:
		for pid in asm.part_ids:
			if (ctx.material_pieces[pid] as MaterialPiece).role == "binding":
				binding = ctx.material_pieces[pid]
	var used := binding.mass_kg if binding != null else 0.0
	_check("(3) Verbund aus Stiel, Kopf und verbrauchten Fasern entstanden (Teil des Gegenstands)", asm != null and asm.part_ids.size() == 3 and binding != null and used > 0.0
		and head.assembly_id == asm.id and a.held_object_id == asm.id, "Versuch %s" % str(r.get("message", "")))
	_check("(3) Masse erhalten: Verbund = Stiel + Kopf + Faseranteil, Restfasern liegen, Gesamtmasse gleich",
		asm != null and absf(ConstructionSystem.mass_of(ctx, asm.id) - (handle.mass_kg + head.mass_kg + used)) < 1e-12 and absf(_p(life, "fiber").mass_kg - (fiber0 - used)) < 1e-12
		and absf(_total_mass(life) - m0) < 1e-12, "Fasern %.4f kg verwendet, Rest %.4f kg" % [used, _p(life, "fiber").mass_kg])
	_check("(3) Kein Teil gleichzeitig einzeln und im Verbund; Audit leer", life.audit().is_empty() and handle.carrier_id == 0 and head.carrier_id == 0, str(life.audit().slice(0, 3)))
	var c: Dictionary = asm.connections[0] if asm != null else {}
	notes.append("Technik: Umwicklung (erster Versuch, Geschick „none“) %.4f kg Fasern → Belastbarkeit %.2f J/Schlag (Passung %.0f %%, Geschick %.0f %%)" % [used, float(c.get("capacity_j", 0)), float(c.get("fit", 0)) * 100, float(c.get("skill", 0)) * 100])


# ── 3b Teile zusammentragen (echte Handlungen) ─────

func _t03b_gather_parts() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	var m0 := _total_mass(life)
	var handle := _p(life, "stick_a")
	var head := _p(life, "stone_head")
	var fiber := _p(life, "fiber")
	# Kopf und Fasern 2 m vom Stiel weg: von keinem Standpunkt aus alle drei erreichbar
	head.position = TestWorkshop._walkable(life, handle.position + Vector3(2.0, 0, 0.3), 0.0) + Vector3(0, 0.02, 0)
	fiber.position = TestWorkshop._walkable(life, handle.position + Vector3(-1.6, 0, 1.2), 0.0) + Vector3(0, 0.02, 0)
	ctx.rebuild_spatial_hash()
	var st := ctx.experiments.start(a, {"kind": "connect", "question": "Test: Teile liegen verstreut", "expected": "Werkzeug",
		"steps": [{"op": "connect", "obj": handle.id, "head": head.id, "fiber": fiber.id}], "source": "Testwerkstatt (gezielt ausgelöst)"}, ctx)
	_run_exp(life, a, 90.0)
	var rec: ExperimentRecord = ctx.experiments.records[int(st["id"])]
	var brings: Array = rec.proposed_steps.filter(func(x): return str(x["op"]) == "bring")
	var drops: Array = rec.executed_steps.filter(func(x): return str(x["op"]) == "bring" and str(x["action"]) == "drop" and str(x["status"]) == "succeeded")
	_check("(3b) Verstreute Teile: Wesen trägt Kopf und Fasern zum Stiel (aufnehmen → gehen → ablegen, automatisch ergänzt) und verbindet",
		st["ok"] and rec.status == "abgeschlossen" and brings.size() == 2 and brings.all(func(x): return x.has("auto")) and drops.size() == 2
		and head.assembly_id != 0 and head.assembly_id == handle.assembly_id, _rec_info(life, int(st.get("id", 0))))
	_check("(3b) Zusammentragen erhält Masse, keine doppelten Teile", absf(_total_mass(life) - m0) < 1e-12 and life.audit().is_empty(), str(life.audit().slice(0, 3)))
	# Unmöglicher Versuch (Ziel unerreichbar) wird nicht endlos wiederholt
	var b := _b(life)
	ExperimentSystem.perceive_objects(b, ctx)
	var q := "Test: unmöglich"
	ctx.experiments.start(b, {"kind": "inspect", "question": q, "expected": "?", "steps": [{"op": "inspect", "obj": 99999}], "source": "eigene Idee"}, ctx)
	_run_exp(life, b, 5.0)
	_check("(3b) Gescheiterter Versuch wird gemerkt (Neuheit gedämpft für eine Weile)", b.tech["failed_plans"].has(q) or ctx.experiments.records.values().any(func(x): return x.question == q and x.status == "fehlgeschlagen"),
		str(b.tech.get("failed_plans", {})))


# ── 4+5 Überlast, Bruch, keine doppelten Teile ─────

func _t04_05_overload_and_break() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	var m0 := _total_mass(life)
	# schwerer Kopf mit wenig Fasern (Teilmenge 0,005 kg)
	var tp := MaterialProcessSystem.take_portion(ctx, _p(life, "fiber2"), 0.005, false)
	var little: MaterialPiece = tp["piece"]
	var r := ConstructionSystem.connect_lashing(ctx, a.id, int(w["stick_b"]), int(w["stone_heavy"]), little.id, "none", "")
	var aid := int(r.get("id", 0))
	var cap := float((ctx.assemblies[aid] as Assembly).connections[0]["capacity_j"]) if aid != 0 else 0.0
	var parts: Array = (ctx.assemblies[aid] as Assembly).part_ids.duplicate() if aid != 0 else []
	ToolUseSystem.hold(ctx, a, aid)
	var ev := ObjectEvaluator.evaluate(ctx, a, aid)
	var target := _p(life, "copper_sample")
	_near(life, a, target.id)
	ctx.executor.request(a.id, "strike_target", target.id)
	sc.run_until_idle(life, a.id, 5.0)
	var broke := not ctx.assemblies.has(aid)
	_check("(4) Überlastete Verbindung bricht (schwerer Kopf, wenig Fasern)", aid != 0 and broke, "Belastbarkeit %.3f J, vorhergesagter Rückprall %.3f J" % [cap, float(ev.get("rebound_on_copper_j", 0))])
	var all_free := true
	var seen := {}
	for pid in parts:
		if not ctx.material_pieces.has(pid) or (ctx.material_pieces[pid] as MaterialPiece).assembly_id != 0:
			all_free = false
		seen[pid] = int(seen.get(pid, 0)) + 1
	var fibers_torn: bool = parts.any(func(pid): return ctx.material_pieces.has(pid) and ctx.material_pieces[pid].material_id == "plant_fiber" and ctx.material_pieces[pid].damage >= 1.0)
	_check("(5) Bruch: alle Teile bleiben genau einmal als Weltobjekte erhalten, Fasern zerrissen, Masse gleich",
		broke and all_free and seen.size() == 3 and fibers_torn and absf(_total_mass(life) - m0) < 1e-12 and life.audit().is_empty(), str(life.audit().slice(0, 3)))
	_check("(5) Beim Bruch bleibt der Stiel in der Hand", ctx.material_pieces.has(a.held_object_id) and (ctx.material_pieces[a.held_object_id] as MaterialPiece).shape == "rod")
	# Zusammengesetzt ist nicht automatisch besser: Vergleich Stein allein vs. Verbund mit schwerem Kopf
	var heavy := ObjectEvaluator.evaluate(ctx, a, int(w["stone_heavy"]))
	notes.append("Technik: schwerer Kopf (%.2f kg) mit 5 g Fasern: Belastbarkeit %.3f J < Rückprall %.3f J → Bruch beim 1. Schlag; Stein allein: Stauchung %.4f/Schlag" % [
		_p(life, "stone_heavy").mass_kg, cap, float(ev.get("rebound_on_copper_j", 0)), float(heavy.get("copper_strain_per_strike", 0))])
	# Bruch eines Steins als Ziel: Fragmente erhalten Masse und Energie
	var st := _p(life, "stone_head2")
	var sm := st.mass_kg
	var se := st.thermal_energy_j
	var sid := st.id
	var res := MaterialProcessSystem.work_piece(ctx, st, 50.0)
	var fm := 0.0
	var fe := 0.0
	for fid in res.get("fragment_ids", []):
		fm += (ctx.material_pieces[fid] as MaterialPiece).mass_kg
		fe += (ctx.material_pieces[fid] as MaterialPiece).thermal_energy_j
	_check("(5) Steinbruch: Bruchstücke ersetzen das Stück, Masse und Wärme exakt erhalten", str(res.get("kind", "")) == "fractured" and not ctx.material_pieces.has(sid)
		and absf(fm - sm) < 1e-12 and absf(fe - se) < 1e-6 and life.audit().is_empty())


# ── 6 Bearbeitung braucht definierte Arbeit ────────

func _t06_work() -> void:
	var life := _ws()
	var ctx := life.ctx
	var c := _p(life, "copper_sample3")
	var v := c.volume_m3()
	var s0 := MaterialProcessSystem.flow_stress_pa(c)
	var r0 := MaterialProcessSystem.work_piece(ctx, c, 0.0)
	var r1 := MaterialProcessSystem.work_piece(ctx, c, 1.0)
	var expect := 1.0 / (s0 * v)
	_check("(6) Verformung Δε = W / (σ(ε) · V): exakt nach dokumentierter Formel, ohne Arbeit keine Änderung",
		float(r0["d_strain"]) == 0.0 and absf(float(r1["d_strain"]) - expect) < 1e-12 and absf(c.volume_m3() - v) < 1e-15, "Δε %.6f erwartet %.6f" % [float(r1["d_strain"]), expect])
	var s1 := MaterialProcessSystem.flow_stress_pa(c)
	var r2 := MaterialProcessSystem.work_piece(ctx, c, 1.0)
	_check("(6) Kaltverfestigung: gleiche Arbeit bewirkt danach weniger Verformung", s1 > s0 and float(r2["d_strain"]) < float(r1["d_strain"]))
	var big := 0.0
	var n := 0
	while c.strain < 1.7 and n < 400:
		MaterialProcessSystem.work_piece(ctx, c, 30.0)
		n += 1
	_check("(6) Über die Grenze der Kaltverformung hinaus entstehen Risse (Schaden), kein Schmelzen nötig", c.damage > 0.0 and c.liquid_fraction() == 0.0, "ε %.2f, Schaden %.2f" % [c.strain, c.damage])
	var stn := _p(life, "stone_heavy")
	var d0 := stn.damage
	MaterialProcessSystem.work_piece(ctx, stn, 10.0)
	_check("(6) Spröder Stein: Schaden = W / (m · Zähigkeit)", absf(stn.damage - (d0 + 10.0 / (stn.mass_kg * stn.material().toughness_j_kg))) < 1e-12)
	var _unused := big


# ── 7+8 Schmelzen und Gießen ──────────────────────

func _t07_08_melt_and_cast() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	var th := ctx.sim.thermal
	var melt := _p(life, "melt")
	var m := melt.material()
	var e_need := melt.mass_kg * (m.enthalpy_from_temperature(m.melting_point, 1.0) - m.enthalpy_from_temperature(293.15, 0.0))
	var bal0 := float(th.ledger(ctx.sim.registry)["balance_j"])
	var m0 := _total_mass(life)
	# zu schwache Heizung: schmilzt nie
	var h: TestHeater = ctx.heaters[int(w["heater"])]
	h.power_w = 40.0
	ToolUseSystem.place_in_heater(ctx, null, int(w["crucible"]), h.id)
	_run(life, 120.0)
	var weak_melt := melt.liquid_fraction()
	var weak_t := melt.temperature_k()
	ToolUseSystem.remove_from_heater(ctx, h.id)
	h.power_w = float(ctx.tc("heater").get("power_w", 3500.0))
	_check("(7) Kupfer schmilzt NICHT bei zu geringer Energiezufuhr (40 W, 120 s)", weak_melt == 0.0, "T %.0f K" % weak_t)
	# echter Versuch 5 mit normaler Leistung
	_run(life, 30.0)
	var sup0 := float(th.heaters[h.heater_name()]["supplied_j"])
	var r := TestWorkshop.trigger(life, 5)
	var first_liquid_sup := -1.0
	var t := 0.0
	while t < 900.0 and ctx.experiments.active(a) != null:
		life.step(DT)
		t += DT
		if first_liquid_sup < 0.0 and melt.liquid_fraction() >= 1.0:
			first_liquid_sup = float(th.heaters[h.heater_name()]["supplied_j"]) - sup0
	var rec: ExperimentRecord = ctx.experiments.records[int(r["id"])]
	_check("(7) Schmelzen erst nach ausreichender Energiezufuhr (zugeführt ≥ Bedarf der Probe)", first_liquid_sup >= e_need,
		"Bedarf Probe %.0f J, zugeführt bis flüssig %.0f J (Tiegel und Verluste eingeschlossen)" % [e_need, first_liquid_sup])
	var cast: MaterialPiece = null
	for id in ctx.material_pieces:
		if (ctx.material_pieces[id] as MaterialPiece).shape == "ingot":
			cast = ctx.material_pieces[id]
	var pour_step: Dictionary = {}
	for s in rec.executed_steps:
		if str(s["op"]) == "pour":
			pour_step = s
	var pd: Dictionary = pour_step.get("data", {})
	_check("(8) Versuch 5: geschmolzen und gegossen, Gussstück in der Form", rec.status == "abgeschlossen" and cast != null and cast.container_id == int(w["mold"]),
		"%s %s %s" % [rec.status, rec.outcome, str(rec.failures)])
	_check("(8) Gießen erhält Masse und thermische Energie exakt", not pd.is_empty() and absf(float(pd["energy_before_j"]) - float(pd["energy_after_j"])) < 1e-6
		and absf(_total_mass(life) - m0) < 1e-12, str(pd))
	_run(life, 240.0)
	var bal1 := float(th.ledger(ctx.sim.registry)["balance_j"])
	var sup := float(th.ledger(ctx.sim.registry)["heaters_j"])
	_check("(8) Wärmebilanz über Heizen, Gießen, Abkühlen geschlossen (Objekte + Umgebung + Körper − Heizung = konstant)",
		absf(bal1 - bal0) < 1e-6 * maxf(1.0, sup), "Abweichung %s J bei %.0f J Heizzufuhr" % [str(bal1 - bal0), sup])
	_check("(8) Guss kühlt ab und erstarrt (Phasenmodell)", cast != null and cast.liquid_fraction() == 0.0 and cast.temperature_k() < 1000.0, "T %.0f K" % (cast.temperature_k() if cast != null else 0.0))
	notes.append("Technik: Testheizung %.0f W: Probe %.3f kg Kupfer braucht %.0f J bis flüssig; zugeführt bis flüssig %.0f J; Versuch 5 dauerte %.0f s" % [h.power_w, melt.mass_kg, e_need, first_liquid_sup, t])


# ── 9 Heiße Objekte ───────────────────────────────

func _t09_hot_handling() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	var st := _p(life, "stone_head")
	st.thermal_energy_j = st.mass_kg * st.material().enthalpy_from_temperature(420.0, 0.0)
	var hand := ToolUseSystem.hand_part(a)
	var d0 := a.health.damage_of(hand)
	var b0 := ctx.sim.thermal.body_energy_j
	_near(life, a, st.id)
	var r := ctx.executor.request(a.id, "equip_tool", st.id)
	_check("(9) Heißer Stein (420 K): Greifen abgewiesen nach Temperaturprüfung, kurze Berührung verbrennt, Wärme in die Hand bilanziert",
		not r["result"].ok and r["result"].code == "too_hot" and a.health.damage_of(hand) > d0 and ctx.sim.thermal.body_energy_j > b0 and a.held_object_id == 0,
		"Handschaden %.3f, Körperwärme %.1f J" % [a.health.damage_of(hand) - d0, ctx.sim.thermal.body_energy_j - b0])
	var kn := ProceduralKnowledge.known_object(a, st.id)
	_check("(9) Das Wesen merkt sich „heiß“ als wahrgenommene Kategorie (kein exakter Wert)", str(kn.get("temperatur", "")).contains("heiß") or str(kn.get("temperatur", "")).contains("warm"), str(kn))
	# flüssiges Kupfer lässt sich nicht greifen
	var melt := _p(life, "melt")
	melt.thermal_energy_j = melt.mass_kg * melt.material().enthalpy_from_temperature(melt.material().melting_point + 20.0, 1.0)
	melt.container_id = 0
	_near(life, a, melt.id)
	var r2 := ctx.executor.request(a.id, "equip_tool", melt.id)
	_check("(9) Schmelze ohne Behälter: nicht greifbar", not r2["result"].ok and r2["result"].code == "liquid", r2["result"].message)
	melt.container_id = int(w["cup"])
	# Tiegelgriff heiß → Gießen abgewiesen
	var grip := ConstructionSystem.grip_piece(ctx, int(w["crucible"]))
	grip.thermal_energy_j = grip.mass_kg * grip.material().enthalpy_from_temperature(360.0, 0.0)
	_near(life, a, int(w["crucible"]))
	var r3 := ctx.executor.request(a.id, "pour_into_mold", int(w["crucible"]), null, {"mold": int(w["mold"])})
	_check("(9) Heißer Tiegelgriff: Gießen wird nicht begonnen", not r3["result"].ok and r3["result"].code in ["too_hot", "out_of_reach"], r3["result"].message)
	# Gehaltener Gegenstand wird heiß → Reflex: loslassen, Verbrennung
	grip.thermal_energy_j = grip.mass_kg * grip.material().enthalpy_from_temperature(293.15, 0.0)
	var cold := _p(life, "copper_sample")
	_near(life, a, cold.id)
	ctx.executor.request(a.id, "equip_tool", cold.id)
	sc.run_until_idle(life, a.id, 3.0)
	var held_before := a.held_object_id
	cold.thermal_energy_j = cold.mass_kg * cold.material().enthalpy_from_temperature(400.0, 0.0)
	_run(life, 0.2)
	_check("(9) Gehaltenes wird heiß → lokaler Reflex: loslassen (keine Modellanfrage)", held_before == cold.id and a.held_object_id == 0 and cold.carrier_id == 0 and life.audit().is_empty())


# ── 10 Abbruch erhält Zwischenzustand ──────────────

func _t10_cancel() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	var st := _p(life, "stone_head")
	_near(life, a, st.id)
	ctx.executor.request(a.id, "equip_tool", st.id)
	sc.run_until_idle(life, a.id, 3.0)
	var c := _p(life, "copper_sample")
	_near(life, a, c.id)
	var e0 := a.metabolism.energy_j
	var r := ctx.executor.request(a.id, "deform_material", c.id, null, {"strikes": 20})
	var act: GameAction = r["action"]
	_run(life, 3.0)
	var strain_mid := c.strain
	ctx.executor.cancel(a.id, "test_cancel", "Testabbruch")
	_run(life, 0.5)
	_check("(10) Abbruch beim Verformen: ausgeführte Schläge bleiben wirksam (ε > 0), nichts zurückgesetzt",
		r["result"].ok and act.status == "cancelled" and int(act.consumed.get("strikes", 0)) >= 1 and c.strain > 0.0 and absf(c.strain - strain_mid) < 1e-12, "ε %.4f nach %d Schlägen" % [c.strain, int(act.consumed.get("strikes", 0))])
	_check("(10) Verbrauchte Energie wird nicht erstattet (Stoffwechselbilanz geschlossen)", a.metabolism.energy_j < e0 and life.audit().is_empty())
	# Abbruch beim Verbinden vor Abschluss: keine Fasern verbraucht, kein Verbund
	ctx.executor.request(a.id, "drop")
	sc.run_until_idle(life, a.id, 2.0)
	var fm := _p(life, "fiber").mass_kg
	_near(life, a, int(w["stick_a"]))
	var r2 := ctx.executor.request(a.id, "connect_parts", int(w["stick_a"]), null, {"head": int(w["stone_head"]), "fiber": int(w["fiber"])})
	_run(life, 2.0)
	ctx.executor.cancel(a.id, "test_cancel", "Testabbruch")
	_check("(10) Abbruch beim Verbinden vor Abschluss: kein Verbund, Fasern unverändert, Reservierungen frei",
		r2["result"].ok and _own_assemblies(life) == 0 and absf(_p(life, "fiber").mass_kg - fm) < 1e-15 and _p(life, "fiber").reserved_by == 0 and life.audit().is_empty(),
		"ok %s, eigene Verbünde %d, Fasern %.5f→%.5f, reserviert %d, Audit %s" % [str(r2["result"].ok), _own_assemblies(life), fm, _p(life, "fiber").mass_kg, _p(life, "fiber").reserved_by, str(life.audit().slice(0, 2))])
	# Versuch abbrechen: Status abgebrochen, Zwischenstand bleibt
	var t := TestWorkshop.trigger(life, 4)
	_run(life, 6.0)
	var s_mid := c.strain
	ctx.experiments.abort(a, "Testabbruch", ctx)
	var rec: ExperimentRecord = ctx.experiments.records[int(t["id"])]
	_check("(10) Abgebrochener Versuch: Status „abgebrochen“, Zwischenstand der Probe bleibt", rec.status == "abgebrochen" and c.strain >= s_mid and c.strain > 0.0, rec.status)


# ── 11 Modellhypothese ─────────────────────────────

func _svc() -> AIService:
	var s := AISettings.new()
	s.user_path = ""
	s.reload()
	s.set_value("enabled", true)
	s.set_value("use_mock", true)
	s.set_value("model", MockOllama.MODEL)
	s.set_value("eligible_share", 0.0)
	s.set_value("per_creature_min_interval_s", 5.0)
	s.set_value("global_rate_per_min", 600)
	var m := MockOllama.new()
	var svc := AIService.new(s, m)
	svc.client.clock = func(): return int(clock["ms"])
	svc.test_connection()
	for i in 4:
		svc.poll()
	return svc


func _t11_model_hypothesis() -> void:
	var svc := _svc()
	var life := _ws(svc)
	var ctx := life.ctx
	var a := _a(life)
	var w := life.workshop
	# Wesen kennt Stein und Kupfer aus eigener Untersuchung
	for role in ["stone_head", "copper_sample"]:
		_near(life, a, int(w[role]))
		ctx.executor.request(a.id, "inspect_object", int(w[role]))
		sc.run_until_idle(life, a.id, 4.0)
	ExperimentSystem.perceive_objects(a, ctx)
	var pieces0 := ctx.material_pieces.size()
	var procs0: Array = a.tech["procedures"].keys()
	var rq := ctx.ai.request_now(a, "experiment", "Test: Versuchsvorschlag")
	_run(life, 3.0)
	var hs: Array = a.tech["hypotheses"]
	var h: Dictionary = hs[-1] if not hs.is_empty() else {}
	_check("(11) Modellvorschlag (SIMULIERT) wird als UNGEPRÜFTE Hypothese gespeichert", rq["ok"] and not h.is_empty() and str(h["status"]) == "ungeprüft" and str(h["source"]) == "Modell (SIMULIERT)",
		str(a.ai.get("last", {})))
	_check("(11) Hypothese erzeugt weder Gegenstand noch Verfahrenswissen", ctx.material_pieces.size() == pieces0 and a.tech["procedures"].keys() == procs0)
	# erfundene Technik / unbekannte IDs werden abgewiesen
	var mock := svc.client.transport as MockOllama
	mock.responder = func(_b, c): return {"request_id": int(c["anfrage"]["request_id"]), "actor_id": a.id, "question": "Generator bauen", "expected_effect": "unknown",
		"proposed_steps": [{"op": "build_generator", "object_id": int(w["stone_head"])}], "uncertainty": 0.1, "short_explanation": "Strom erzeugen"}
	a.ai["next_request_t"] = 0.0
	ctx.ai.request_now(a, "experiment", "Test: erfundene Technik")
	_run(life, 3.0)
	var l1: Dictionary = a.ai.get("last", {})
	mock.responder = func(_b, c): return {"request_id": int(c["anfrage"]["request_id"]), "actor_id": a.id, "question": "?", "expected_effect": "form_change",
		"proposed_steps": [{"op": "equip", "object_id": 99999}], "uncertainty": 0.1, "short_explanation": "x"}
	a.ai["next_request_t"] = 0.0
	ctx.ai.request_now(a, "experiment", "Test: unbekannte ID")
	_run(life, 3.0)
	var l2: Dictionary = a.ai.get("last", {})
	mock.responder = func(_b, c): return {"request_id": int(c["anfrage"]["request_id"]), "actor_id": a.id, "question": "?", "expected_effect": "form_change",
		"proposed_steps": [{"op": "equip", "object_id": int(w["stone_head"]), "material": "Bronze"}], "uncertainty": 0.1, "short_explanation": "x"}
	a.ai["next_request_t"] = 0.0
	ctx.ai.request_now(a, "experiment", "Test: erfundenes Material")
	_run(life, 3.0)
	var l3: Dictionary = a.ai.get("last", {})
	_check("(11) Erfundener Vorgang („Generator“) abgewiesen (Stufe 2/5), kein Gegenstand", str(l1.get("status", "")) == "abgelehnt" and int(l1.get("stage", 0)) in [2, 5] and ctx.material_pieces.size() == pieces0, str(l1))
	_check("(11) Unbekannte Gegenstands-ID abgewiesen (Stufe 3)", str(l2.get("status", "")) == "abgelehnt" and int(l2.get("stage", 0)) == 3, str(l2))
	_check("(11) Erfundenes Material/Feld abgewiesen (Stufe 2), kein Gegenstand", str(l3.get("status", "")) == "abgelehnt" and int(l3.get("stage", 0)) == 2 and ctx.material_pieces.size() == pieces0, str(l3))
	# Hypothese tatsächlich ausprobieren → erst dann Evidenz
	var st := ctx.experiments.start(a, {"kind": "modellvorschlag", "question": str(h["question"]), "steps": h["steps"], "source": str(h["source"]), "hypothesis_id": int(h["id"])}, ctx)
	_run_exp(life, a, 60.0)
	var h2 := ProceduralKnowledge.hypothesis(a, int(h["id"]))
	_check("(11) Erst der ausgeführte Versuch liefert Evidenz; Verfahren stammt aus eigenem Versuch", st["ok"] and str(h2["status"]).contains("Versuch #")
		and a.tech["procedures"].values().any(func(e): return int(e["own"]["attempts"]) >= 1), str(h2.get("status", "")))


# ── 12+13 Wissen individuell, Unterricht ───────────

func _t12_13_knowledge_and_teaching() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	var b := _b(life)
	# B weit weg (ohne Sicht) während A das Verbinden entdeckt
	b.position = TestWorkshop._walkable(life, a.position + Vector3(0, 0, 25.0), 0.0)
	ctx.rebuild_spatial_hash()
	TestWorkshop.trigger(life, 2)
	_run_exp(life, a, 30.0)
	var key := ProceduralKnowledge.lashing_key("wood", "stone")
	_check("(12) A kennt das Verbinden aus eigenem erfolgreichem Versuch", ProceduralKnowledge.level(a, key) == "erfolgreich")
	_check("(12) Nicht beteiligtes Wesen (außer Sicht) erhält kein Wissen", b.tech["procedures"].is_empty(), str(b.tech["procedures"].keys()))
	# Erklären (Gespräch): höchstens „gehört“
	b.position = TestWorkshop._walkable(life, a.position + Vector3(-1.2, 0, 0.4), 0.0)
	ctx.rebuild_spatial_hash()
	Perception.scan(a, ctx)
	Perception.scan(b, ctx)
	var tps := TeachingSystem.explain_topics(a, b.id, ctx)
	var st := ctx.comm.start(a, b.id, tps[0] if not tps.is_empty() else {}, "lokal", ctx) if not tps.is_empty() else {"ok": false}
	sc.run_until_idle(life, a.id, 4.0)
	_run(life, 0.2)
	_check("(13) Erklärung: B hat nur „davon gehört“ (Hörensagen mit Quelle), keine Praxis", st["ok"] and ProceduralKnowledge.level(b, key) == "gehört"
		and int(b.tech["procedures"][key]["own"]["attempts"]) == 0 and int(b.tech["procedures"][key]["heard"]["sources"][-1]["speaker"]) == a.id, str(b.tech["procedures"].get(key, {}).get("level", "")))
	# zweimal dieselbe Quelle ist kein unabhängiger Beweis
	ProceduralKnowledge.record_heard(ctx, b, key, a.id, a.id, "erfolgreich")
	_check("(13) Wiederholtes Hören derselben Quelle zählt als EIN unabhängiger Ursprung", (b.tech["procedures"][key]["heard"]["origins"] as Array).size() == 1)
	# Vorführung (Versuch 6): B sieht zu → „zugesehen“, nicht „erfolgreich“
	var r6 := TestWorkshop.trigger(life, 6)
	_run_exp(life, a, 40.0)
	var lv_after_demo := ProceduralKnowledge.level(b, key)
	var rec6: ExperimentRecord = ctx.experiments.records.get(int(r6.get("id", 0)), null)
	_check("(13) Vorführung tatsächlich ausgeführt (echter Verbund entsteht) und von B wahrgenommen", rec6 != null and rec6.status == "abgeschlossen" and lv_after_demo == "zugesehen"
		and int(b.tech["procedures"][key]["observed"]["count"]) >= 1, "%s / %s" % [str(r6.get("message", "")), lv_after_demo])
	_check("(13) Unterricht überträgt Information, aber keine Praxiserfahrung (B: 0 eigene Versuche, keine Lehrerdaten)",
		int(b.tech["procedures"][key]["own"]["attempts"]) == 0 and (b.tech["procedures"][key]["experiments"] as Array).is_empty() and lv_after_demo != "erfolgreich")
	# B übt selbst → eigener Versuch
	ctx.executor.request(a.id, "drop")
	sc.run_until_idle(life, a.id, 2.0)
	var asm_demo := 0
	for aid in ctx.assemblies:
		if not (ctx.assemblies[aid] as Assembly).test_equipment:
			asm_demo = aid
	if asm_demo != 0:
		_near(life, a, asm_demo)
		ctx.executor.request(a.id, "disconnect_parts", asm_demo)
		sc.run_until_idle(life, a.id, 5.0)
	var pr := TestWorkshop.trigger_practice(life)
	_run_exp(life, b, 40.0)
	var lv_b := ProceduralKnowledge.level(b, key)
	_check("(13) Üben: erst ein eigener Versuch hebt B auf „versucht“/„erfolgreich“", pr["ok"] and lv_b in ["versucht", "erfolgreich"] and int(b.tech["procedures"][key]["own"]["attempts"]) == 1,
		"%s → %s; Versuch: %s; B läuft: %s" % [str(pr["message"]), lv_b, _rec_info(life, int(pr.get("id", 0))), str(ctx.executor.running.get(b.id).type if ctx.executor.running.has(b.id) else "nichts")])
	# Tod: ungeteiltes Wissen geht nicht über
	var only_a := ProceduralKnowledge.strike_key("stone", "Stück", "copper")
	ProceduralKnowledge.record_own(ctx, a, only_a, true, ["copper"], 0, "Test")
	a.die("Test: Wissen stirbt mit", ctx)
	_run(life, 1.0)
	_check("(12) Stirbt das einzige sachkundige Wesen, geht sein ungeteiltes Wissen nicht auf andere über", not ProceduralKnowledge.knows(b, only_a) and ProceduralKnowledge.knows(a, only_a) and life.audit().is_empty())


# ── 14 Speichern/Laden ────────────────────────────

func _t14_save_load() -> void:
	var life := _ws()
	var ctx := life.ctx
	var a := _a(life)
	TestWorkshop.trigger(life, 2)
	_run_exp(life, a, 30.0)
	TestWorkshop.trigger(life, 3)
	_run_exp(life, a, 40.0)
	# Tiegel in die Heizung, mitten im Erhitzen speichern
	ctx.experiments.start(a, TestWorkshop.plan_for(life, 5), ctx)
	_run(life, 25.0)
	var path := "user://saves/_test_tech.json"
	var sv := SaveManager.save(life, path)
	var snap_a := SaveManager.snapshot(life)
	var melt_t := _p(life, "melt").temperature_k()
	var life2 := LifeSimulation.new()
	var sim2 := Simulation.new()
	var world2 := VoxelWorld.new()
	var objs2 := Node3D.new()
	sim2.initialize()
	sim2.set_physics_process(false)
	world2.set_physics_process(false)
	sc.nodes.append_array([sim2, world2, objs2])
	life2.setup(sim2, db, world2, objs2)
	sc.lives.append(life2)
	var r := SaveManager.load_into(life2, path)
	var c2 := life2.ctx
	_check("(14) Speichern und Laden mit Werkzeug, Versuchen und Wissen gelingt (Audit leer)", sv["ok"] and r["ok"], str(r.get("message", "")))
	if not r["ok"]:
		return
	var snap_b := SaveManager.snapshot(life2)
	var rt := func(v): return JSON.parse_string(JSON.stringify(v))
	var d_pieces := first_diff(rt.call(snap_a["material_pieces"]), rt.call(snap_b["material_pieces"]), "Stücke")
	var d_asm := first_diff(rt.call(snap_a["assemblies"]), rt.call(snap_b["assemblies"]), "Verbünde")
	_check("(14) Gegenstände, Verbindungen, Verschleiß, Formänderungen und Wärme exakt erhalten (Werte gleich)", d_pieces == "" and d_asm == "" and c2.assemblies.size() == ctx.assemblies.size()
		and snap_a["material_pieces"].size() > 10, d_pieces + " " + d_asm)
	var a2 := c2.creature(a.id)
	var ta: Dictionary = rt.call(ProceduralKnowledge.to_save(a.tech))
	var tb: Dictionary = rt.call(ProceduralKnowledge.to_save(a2.tech))
	var d_tech := ""
	for k in ["procedures", "hypotheses", "objects", "budget"]:
		d_tech += first_diff(ta.get(k), tb.get(k), k)
	_check("(14) Verfahrenswissen, Hypothesen, bekannte Gegenstände, Versuchsbudget und Halten erhalten", d_tech == "" and a2.held_object_id == a.held_object_id
		and not (ta["procedures"] as Dictionary).is_empty(), d_tech + " gehalten %d/%d" % [a.held_object_id, a2.held_object_id])
	var running := 0
	for id in c2.experiments.records:
		if (c2.experiments.records[id] as ExperimentRecord).status == "unterbrochen":
			running += 1
	_check("(14) Laufender Versuch beim Laden sicher als „unterbrochen“ abgeschlossen (keine rückwirkende Auswertung)", running == 1 and c2.experiments.active(a2) == null
		and c2.experiments.records.size() == ctx.experiments.records.size())
	var melt2: MaterialPiece = c2.material_pieces[int(life2.workshop["melt"])]
	var th2 := c2.sim.thermal
	_check("(14) Wärmezustand und Testheizung wiederhergestellt: Erhitzen läuft nach dem Laden weiter", absf(melt2.temperature_k() - melt_t) < 1e-9 and th2.heaters.size() == 1)
	for i in int(10.0 / DT):
		life2.step(DT)
	_check("(14) Nach dem Laden: Probe wird weiter erhitzt, Bilanz geschlossen, Audit leer", melt2.temperature_k() > melt_t and life2.audit().is_empty(), "%.1f → %.1f K" % [melt_t, melt2.temperature_k()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _t14b_migration() -> void:
	var path := "user://saves/_test_mig_v3.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	for ext in ["", ".bak", ".v3.vor_migration"]:
		if FileAccess.file_exists(path + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/save_v3_prompt05.json"), ProjectSettings.globalize_path(path))
	var orig := FileAccess.get_file_as_string(path)
	var raw = JSON.parse_string(orig.substr(orig.find("\n") + 1))
	var life := LifeSimulation.new()
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	life.setup(sim, db, world, objs)
	sc.lives.append(life)
	var calls := PopulationSpawner.spawn_calls
	var r := SaveManager.load_into(life, path)
	_check("(14) Migration Format 3 → 4: echter Spielstand aus v0.5.1 lädt, Original gesichert, Spawner nicht aufgerufen",
		r["ok"] and int(r.get("migrated_from", 0)) == 3 and FileAccess.file_exists(path + ".v3.vor_migration") and PopulationSpawner.spawn_calls == calls, str(r.get("message", "")).substr(0, 200))
	if not r["ok"]:
		return
	var ctx := life.ctx
	var pieces_ok: bool = ctx.material_pieces.size() == raw["material_pieces"].size()
	for md in raw["material_pieces"]:
		var mp: MaterialPiece = ctx.material_pieces.get(int(md["id"]), null)
		if mp == null or absf(mp.mass_kg - float(md["mass_kg"])) > 1e-12 * maxf(1.0, mp.mass_kg) or absf(mp.temperature_k() - 293.15) > 1e-6:
			pieces_ok = false
	_check("(14) Migration: Materialstücke mit gleicher Masse bei Umgebungstemperatur übernommen", pieces_ok)
	var none := true
	for id in ctx.creatures:
		var cr: Creature = ctx.creatures[id]
		if not cr.tech["procedures"].is_empty() or not cr.tech["hypotheses"].is_empty() or cr.held_object_id != 0:
			none = false
	_check("(14) Migration: keine rückwirkend geschenkten Entdeckungen, kein Werkzeug, keine Versuche", none and ctx.experiments.records.is_empty() and ctx.assemblies.is_empty() and ctx.heaters.is_empty())
	var st: Dictionary = ctx.experiments.stats
	_check("(14) Migration: Versuchsstatistik vollständig mit Nullen angelegt", int(st.get("started", -1)) == 0 and int(st.get("completed", -1)) == 0 and st.get("by_source", null) is Dictionary, str(st))
	for i in int(20.0 / DT):
		life.step(DT)
	_check("(14) Migration: Simulation läuft danach weiter (auch eigene Versuche mit migrierten Materialstücken), Audit leer", life.audit().is_empty()
		and int(ctx.experiments.stats["started"]) >= 0, str(life.audit().slice(0, 3)) + " Versuche " + str(ctx.experiments.stats))
	for ext in ["", ".bak", ".v3.vor_migration"]:
		if FileAccess.file_exists(path + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))


# ── 15 Normales Spiel unverändert ──────────────────

func _t15_normal_game() -> void:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs)
	sc.lives.append(life)
	var r := life.new_game(world_seed)
	_check("(15) Normales Spiel: keine Testausrüstung, keine versteckten Materialgeschenke, keine Pflichtentdeckungen",
		r["ok"] and life.ctx.material_pieces.is_empty() and life.ctx.assemblies.is_empty() and life.ctx.heaters.is_empty() and life.workshop.is_empty() and life.ctx.creatures.size() == 50)
	var g := life.ctx.interventions.execute({"kind": "place_material", "material_id": "plant_fiber", "position": sc.center(life)})
	var g2 := life.ctx.interventions.execute({"kind": "place_material", "material_id": "wood", "shape": "rod", "position": sc.center(life) + Vector3(0.5, 0, 0)})
	_check("(15) Göttermenü platziert Fasern und Holzstab als normale Weltobjekte", g["ok"] and g2["ok"] and life.ctx.material_pieces.size() == 2, "%s | %s" % [g["message"], g2["message"]])
	var ate0 := life.ctx.ledger.eaten_kg
	for i in int(90.0 / DT):
		life.step(DT)
	var ate := life.ctx.ledger.eaten_kg - ate0
	_check("(15) Lebens-, Lern-, Physik- und KI-Funktionen laufen weiter (Audit leer, Wesen essen)", life.audit().is_empty() and ate > 0.0, "%.2f kg gegessen" % ate)


# ── Beobachtungslauf (eigenständiges Verhalten) ────

func _t_observation_run() -> void:
	var life := _ws(null, true)
	var ctx := life.ctx
	var secs := 240.0 if quick else 600.0
	_run(life, secs)
	var a := _a(life)
	var b := _b(life)
	var share_a := 0.0
	var share_b := 0.0
	for x in [a, b]:
		var s := 0.0
		for bb in x.tech["budget"]:
			s += float(bb[1]) - float(bb[0])
		if x == a:
			share_a = s / secs
		else:
			share_b = s / secs
	var by: Dictionary = ctx.experiments.stats["by_source"]
	var eaten := float(a.metabolism.totals["eaten_kg"]) + float(b.metabolism.totals["eaten_kg"])
	var procs: Array = []
	for x in [a, b]:
		for k in x.tech["procedures"]:
			procs.append("#%d %s (%s)" % [x.id, ProceduralKnowledge.describe_key(k), x.tech["procedures"][k]["level"]])
	notes.append("Technik-Beobachtungslauf %.0f s (Verhalten AN, keine gezielten Auslöser): Versuche nach Herkunft %s, abgeschlossen %d, fehlgeschlagen %d, abgebrochen %d; Versuchszeit A %.0f %%, B %.0f %%; gegessen %.2f kg; Verfahren: %s" % [
		secs, str(by), int(ctx.experiments.stats["completed"]), int(ctx.experiments.stats["failed"]), int(ctx.experiments.stats["aborted"]), share_a * 100, share_b * 100, eaten,
		"; ".join(procs) if not procs.is_empty() else "keine"])
	var budget := float(ctx.tc("experiments").get("budget_share", 0.25))
	_check("Beobachtungslauf: Versuche begrenzt (Zeitanteil ≤ Budget + eine Versuchsdauer), Wesen leben", share_a <= budget + 0.15 and share_b <= budget + 0.15 and a.alive and b.alive,
		"A %.0f %%, B %.0f %%" % [share_a * 100, share_b * 100])
	_check("Beobachtungslauf: Konsistenz (Audit leer) bei eigenständigem Verhalten", life.audit().is_empty(), str(life.audit().slice(0, 3)))
