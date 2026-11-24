class_name TestMind
extends RefCounted
## Prüfungen zu Geist, sozialen Handlungen, Göttermenü, Lernen und Migration (Prompt 4).
## Szenarien A–G laufen über mehrere feste Startwerte (ein einzelner Durchlauf ist kein Nachweis).

const SEEDS := [101, 202, 303]
const FIXTURE := "res://tests/fixtures/save_v1_prompt03.json"
const MIG_PATH := "user://saves/_test_migration.json"

var results: Array = []
var notes: Array = []
var db: DefinitionDB
var sc: MindScenarios


func run_all() -> Array:
	results.clear()
	notes.clear()
	db = DefinitionDB.new()
	db.load_all()
	sc = MindScenarios.new(db)
	_test_personality()
	_test_scenarios()
	_test_decisions()
	_test_god_commands()
	_test_privacy_and_pause()
	_test_migration()
	sc.cleanup()
	return results


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": name, "ok": ok, "detail": detail})


func _test_personality() -> void:
	var mc: Dictionary = db.config("mind")
	var a := Personality.generate(4711, mc)
	var b := Personality.generate(4711, mc)
	var c := Personality.generate(4712, mc)
	var in_range := true
	var vals: Array = []
	for s in 200:
		var p := Personality.generate(s * 7919, mc)
		for k in p.values:
			var v := float(p.values[k])
			vals.append(v)
			if v < float(mc["personality"]["min"]) or v > float(mc["personality"]["max"]):
				in_range = false
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	_check("Persönlichkeit: reproduzierbar aus Startwert, begrenzt, verschieden je Wesen", a.to_dict() == b.to_dict() and a.to_dict() != c.to_dict() and in_range and absf(mean - 0.5) < 0.03 and a.values.size() == 5,
		"Mittel %.3f über %d Werte" % [mean, vals.size()])
	var life := sc.env(55, 6)
	var cr: Creature = life.ctx.creatures.values()[0]
	var before := cr.personality.to_dict()
	sc.gift_near(life, cr)
	sc.run(life, 15.0)
	_check("Persönlichkeit ändert sich nicht durch Ereignisse; Hunger liegt getrennt im Stoffwechsel", cr.personality.to_dict() == before and not cr.personality.values.has("hunger"))
	_check("Keine Kopplung der Persönlichkeit an Farbe/Art/Körper (nur plan_seed + Salz)", Personality.generate(cr.plan_seed, db.config("mind")).to_dict() == before, "")


func _test_scenarios() -> void:
	for letter in ["A", "B", "C", "D", "E", "F", "G"]:
		var passed := 0
		var total := 0
		var fails: Array = []
		for s in SEEDS:
			var checks := sc.run_scenario(letter, s, "user://saves/_szenario_%s_%d.json" % [letter, s])
			for c in checks:
				total += 1
				if c["ok"]:
					passed += 1
				else:
					fails.append("Startwert %d: %s – %s" % [s, c["name"], c["detail"]])
			if s == SEEDS[0]:
				for c in checks:
					notes.append("  [%s] %s %s%s" % [letter, "ok" if c["ok"] else "FEHLER", c["name"], (" | " + str(c["detail"])) if str(c["detail"]) != "" else ""])
			sc.cleanup()
		_check("Szenario %s (%s) über Startwerte %s: %d/%d Teilprüfungen" % [letter, MindScenarios.SCENARIOS[letter], str(SEEDS), passed, total], passed == total and total > 0, "; ".join(fails.slice(0, 3)))
	for s3 in SEEDS:
		for ext in ["", ".bak"]:
			var p := "user://saves/_szenario_G_%d.json%s" % [s3, ext]
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)


func _test_decisions() -> void:
	var life := sc.env(77, 6)
	var ctx := life.ctx
	var ids: Array = ctx.creatures.keys()
	ids.sort()
	var giver: Creature = ctx.creatures[ids[0]]
	var asker: Creature = ctx.creatures[ids[1]]
	sc.fetch_food(life, giver)
	sc.place(life, giver, sc.center(life))
	sc.place(life, asker, giver.position + Vector3(2.0, 0, 0))
	sc.set_hunger(giver, 0.2)
	giver.social["inbox"] = [{"from": asker.id, "t": ctx.now(), "req": 1}]
	giver.personality.values["hilfsbereitschaft"] = 0.9
	var opts_hi := DecisionSystem.evaluate(giver, ctx)
	giver.personality.values["hilfsbereitschaft"] = 0.1
	var opts_lo := DecisionSystem.evaluate(giver, ctx)
	_check("Persönlichkeit wirkt auf konkrete Bewertungen (hilfsbereit → geben, wenig hilfsbereit → ablehnen)", _best(opts_hi) == "give_requested" and _best(opts_lo) == "decline_request",
		"hoch: %s · niedrig: %s" % [_best(opts_hi), _best(opts_lo)])
	sc.set_hunger(giver, 0.85)
	giver.personality.values["hilfsbereitschaft"] = 0.9
	var opts_need := DecisionSystem.evaluate(giver, ctx)
	_check("Eigener Bedarf geht vor: sehr hungrig gibt nicht ab", _best(opts_need) != "give_requested", _best(opts_need))
	# Kritischer Hunger schlägt eine (starke) gelernte Vorliebe
	var x: Creature = ctx.creatures[ids[2]]
	var key := "gift_after_action:raise_arms"
	x.beliefs.get_or_create(key, "gift_after_action", "raise_arms", "self", ctx.now(), ctx.mind_cfg)
	for k in 12:
		x.beliefs.update(key, true, 1.0, ctx.now(), ctx.mind_cfg, {}, 1.0)
	x.beliefs.get_or_create("gift_base", "gift_base", "self", "self", ctx.now(), ctx.mind_cfg)
	for k in 12:
		x.beliefs.update("gift_base", false, 1.0, ctx.now(), ctx.mind_cfg, {})
	sc.set_hunger(x, 0.2)
	Perception.scan(x, ctx)
	var o_sated := DecisionSystem.evaluate(x, ctx)
	sc.set_hunger(x, 0.85)
	var o_crit := DecisionSystem.evaluate(x, ctx)
	_check("Gelernte Wiederholung wird versorgt gewählt, bei kritischem Hunger aber nicht (kein Verhungern aus Vorliebe)",
		_best(o_sated) == "repeat:raise_arms" and _best(o_crit) in ["seek_food", "search_food", "ask_food", "eat_carried"],
		"versorgt: %s · kritisch: %s" % [_best(o_sated), _best(o_crit)])
	# Erklärung: Beiträge werden protokolliert
	x.behavior_enabled = true
	DecisionSystem.decide(x, ctx)
	_check("Entscheidung protokolliert Bewertungsbeiträge (erklärbar)", not x.decision.is_empty() and not x.decision.get("options", []).is_empty() and not x.decision["options"][0]["parts"].is_empty(),
		str(x.decision.get("options", []).slice(0, 2)))
	# Zielbindung: Wechsel braucht deutlich höheren Nutzwert
	GoalManager.commit(x, "explore", 0, 0.3, ctx)
	_check("Zielbindung: aktuelles Ziel erhält Zuschlag, solange die Bindung gilt", GoalManager.binding_bonus(x, "explore", ctx) > 0.0 and GoalManager.binding_bonus(x, "rest", ctx) == 0.0)
	var s := GoalManager.suggest(x, "explore", "test", 1.0, ctx)
	var bad := GoalManager.suggest(x, "fliegen", "test", 1.0, ctx)
	_check("Schnittstelle für Zielvorschläge (für Ollama vorbereitet): begrenzter Zuschlag, unbekannte Ziele abgewiesen",
		s["ok"] and not bad["ok"] and GoalManager.suggestion_bonus(x, "explore", ctx) <= float(ctx.m("decision")["suggestion_max_bonus"]) + 1e-9)
	# Bitte-Ablehnung-Schleifen: Wartezeiten
	var b2: Creature = ctx.creatures[ids[3]]
	sc.place(life, b2, giver.position + Vector3(-1.5, 0, 0))
	sc.set_hunger(b2, 0.7)
	var r1 := ctx.executor.request(b2.id, "request_food", giver.id)
	sc.run_until_idle(life, b2.id)
	var r2 := ctx.executor.request(b2.id, "request_food", giver.id)
	_check("Wartezeit verhindert sofortige erneute Bitte", r1["result"].ok and not r2["result"].ok and r2["result"].code in ["cooldown", "cooldown_target"], r2["result"].message)
	var outcome_hungry := RewardAssociation.outcome_value(x, _obs("food_appeared", x.id))
	sc.set_hunger(x, 0.05)
	x.personality.values["vorsicht"] = 0.95
	var outcome_sated := RewardAssociation.outcome_value(x, _obs("food_appeared", x.id))
	_check("Ein Geschenk ist nicht für jeden gleich wertvoll (hungrig > satt und vorsichtig)", outcome_hungry > outcome_sated + 0.5, "%.2f vs %.2f" % [outcome_hungry, outcome_sated])


func _obs(t: String, target: int) -> Observation:
	var o := Observation.new()
	o.event_type = t
	o.target_id = target
	return o


static func _best(opts: Array) -> String:
	var b := ""
	var bu := -INF
	for o in opts:
		if float(o["u"]) > bu:
			bu = float(o["u"])
			b = str(o["id"])
	return b


func _test_god_commands() -> void:
	var life := sc.env(88, 5)
	var ctx := life.ctx
	var ids: Array = ctx.creatures.keys()
	ids.sort()
	var cr: Creature = ctx.creatures[ids[0]]
	sc.place(life, cr, sc.center(life))
	ctx.rebuild_spatial_hash()
	var tree_pos := life.tree_node.position
	var in_tree := GodCommands.prepare(ctx, {"kind": "gift_food", "position": tree_pos, "amount_kg": 0.2, "food_id": "N001"})
	var on_body := GodCommands.prepare(ctx, {"kind": "gift_food", "position": cr.position, "amount_kg": 0.2, "food_id": "N001"})
	var too_much := GodCommands.prepare(ctx, {"kind": "gift_food", "target_id": cr.id, "amount_kg": 5.0, "food_id": "N001"})
	var outside := GodCommands.prepare(ctx, {"kind": "place_material", "position": Vector3(-50, 3, -50), "material_id": "stone"})
	var bad_mat := GodCommands.prepare(ctx, {"kind": "place_material", "target_id": cr.id, "material_id": "water"})
	_check("Göttermenü: keine Platzierung im Baum, im Körper, außerhalb; Mengen und Materialien begrenzt",
		not in_tree["ok"] and not on_body["ok"] and not too_much["ok"] and not outside["ok"] and not bad_mat["ok"],
		"%s | %s" % [str(in_tree["errors"]), str(on_body["errors"])])
	var ok_prev := GodCommands.prepare(ctx, {"kind": "gift_food", "target_id": cr.id, "amount_kg": 0.3, "food_id": "N002", "linked_event": {"seq": 7, "type": "raise_arms", "actor": cr.id, "t": 1.0}})
	var txt: String = ok_prev["text"]
	_check("Vorschau zeigt Art, Ziel/Position, Menge und zugeordnetes Ereignis", ok_prev["ok"] and txt.find("Nahrung schenken") >= 0 and txt.find("Wesen #%d" % cr.id) >= 0 and txt.find("0.30 kg") >= 0 and txt.find("raise_arms") >= 0, txt)
	var g0 := ctx.ledger.god_kg
	var r := ctx.interventions.execute({"kind": "gift_food", "target_id": cr.id, "amount_kg": 0.3, "food_id": "N002"})
	var it: FoodItem = ctx.items.get(int(r.get("record", {}).get("result", {}).get("item", 0)), null)
	_check("Nahrungsgabe: echte Portion am Boden, extern bilanziert, Bilanz geschlossen, eindeutige ID, Ereignisprotokoll",
		r["ok"] and it != null and it.carrier_id == 0 and absf(ctx.ledger.god_kg - g0 - 0.3) < 1e-12 and absf(ctx.ledger.balance_error(ctx)) < 1e-9 and int(r["id"]) == 1 and life.sim.event_log.count_type("god_intervention") == 1,
		str(r["message"]))
	var r2 := ctx.interventions.execute({"kind": "place_material", "target_id": cr.id, "material_id": "copper"})
	var mp: MaterialPiece = ctx.material_pieces.get(int(r2.get("record", {}).get("result", {}).get("piece", 0)), null)
	var exp_mass := life.sim.materials.get_material("copper").density * pow(0.12, 3)
	_check("Materialgabe: Gegenstand mit Masse aus Dichte × Volumen, registriert", r2["ok"] and mp != null and absf(mp.mass_kg - exp_mass) < 1e-9 and life.sim.registry.has_id(mp.id) and int(r2["id"]) == 2,
		"%.3f kg Kupfer" % (mp.mass_kg if mp else -1.0))
	life.dev_body_change(cr.id, "injure_leg", "l")
	life.dev_body_change(cr.id, "remove_forearm", "r")
	var dmg0 := cr.health.damage_of("leg_l_lower")
	var r3 := ctx.interventions.execute({"kind": "heal", "target_id": cr.id, "heal_amount": 0.4})
	_check("Heilen: repariert vorhandenes verletztes Gewebe begrenzt, fehlender Unterarm bleibt fehlend",
		r3["ok"] and absf(cr.health.damage_of("leg_l_lower") - (dmg0 - 0.4)) < 1e-9 and not cr.plan.is_present("arm_r_lower") and not cr.plan.is_present("hand_r"),
		"Schaden %.2f → %.2f" % [dmg0, cr.health.damage_of("leg_l_lower")])
	var dead: Creature = ctx.creatures[ids[1]]
	life.dev_body_change(dead.id, "injure_leg", "l")
	dead.die("Test", ctx)
	var r4 := ctx.interventions.execute({"kind": "heal", "target_id": dead.id, "heal_amount": 0.5})
	_check("Heilen eines toten Wesens abgewiesen", not r4["ok"], r4["message"])
	_check("Jeder Eingriff hat eine eindeutige ID und steht im Protokoll", ctx.interventions.history.size() == 3 and ctx.interventions.history.map(func(h): return int(h["id"])) == [1, 2, 3])
	var ev := ctx.interventions.recent_events(600.0, 50, 0)
	_check("Kürzlich beobachtete Ereignisse auswählbar (Spielerwissen aus dem Ereignisprotokoll)", ev.size() >= 3, str(ev.slice(0, 3)))


func _test_privacy_and_pause() -> void:
	var life := sc.env(99, 4)
	var ctx := life.ctx
	var ids: Array = ctx.creatures.keys()
	ids.sort()
	var a: Creature = ctx.creatures[ids[0]]
	sc.place(life, a, sc.center(life))
	sc.raise_arms(life, a)
	var ev_list := ctx.interventions.recent_events(60.0, 10, a.id)
	var linked: Dictionary = ev_list[0] if not ev_list.is_empty() else {}
	ctx.interventions.execute({"kind": "gift_food", "target_id": a.id, "amount_kg": 0.1, "food_id": "N001", "linked_event": linked, "note_secret": "Spielerabsicht XYZ"})
	sc.run(life, 2.0)
	var mind_txt := JSON.stringify(a.to_dict()["mind"])
	_check("Spielerabsicht (zugeordnetes Ereignis) gelangt nicht in den Geist; nur ins Eingriffsprotokoll",
		not linked.is_empty() and mind_txt.find("linked_event") < 0 and mind_txt.find("XYZ") < 0 and not ctx.interventions.history.back()["player"]["linked_event"].is_empty(),
		"zugeordnet: %s" % str(linked))
	# Wesen lesen das globale Ereignisprotokoll nicht: Protokoll leeren ändert nichts am Geist
	var snap := JSON.stringify(a.to_dict()["mind"])
	life.sim.event_log.clear()
	sc.run(life, 0.0)
	_check("Erinnerungen tragen eigene Daten (Protokoll geleert → Geist unverändert, keine ungültigen Verweise)", JSON.stringify(a.to_dict()["mind"]) == snap and a.memory.audit().is_empty())
	# Pause stoppt Lernen
	sc.run(life, 1.0)
	var before := JSON.stringify(a.to_dict()["mind"])
	life.sim.set_paused(true)
	sc.run(life, 15.0)
	var after := JSON.stringify(a.to_dict()["mind"])
	life.sim.set_paused(false)
	_check("Pause stoppt Lernen (Erwartungen, Erinnerungsverfall, Entscheidungen)", before == after)
	# Begrenzte Speicher
	var m := a.memory
	var o := Observation.new()
	for k in 300:
		o.event_type = "food_eaten"
		o.actor_id = 1000 + k
		o.position = Vector3(k * 5.0, 0, 0)
		o.t = ctx.now() + k
		o.quality = 1.0
		m.remember(o, 0.5, ctx.now() + k, ctx.mind_cfg)
	_check("Erinnerungsspeicher begrenzt (Kapazität, Vergessen gezählt)", m.entries.size() <= int(ctx.m("memory")["capacity"]) and m.forgotten > 0, "%d Einträge, %d vergessen" % [m.entries.size(), m.forgotten])
	var o2 := Observation.new()
	o2.event_type = "food_eaten"
	o2.actor_id = 7
	o2.quality = 0.4
	o2.t = 0.0
	var m2 := MemoryStore.new()
	m2.remember(o2, 0.5, 0.0, ctx.mind_cfg)
	o2.quality = 1.0
	o2.t = 5.0
	var merged := m2.remember(o2, 0.5, 5.0, ctx.mind_cfg)
	_check("Verdichtung: Zähler statt neuer Ereignisse, Sicherheit nie höher als die unsicherste Beobachtung", m2.entries.size() == 1 and int(merged["count"]) == 2 and absf(float(merged["certainty"]) - 0.4) < 1e-9)


func _test_migration() -> void:
	var fp := SaveSchema.definitions_fingerprint()
	_check("Migration: ausgelieferte Definitionen v0.6.0 entsprechen dem eingetragenen Fingerabdruck", fp["hash"] == SaveMigrations.V4_SHIPPED_DEFINITIONS,
		"aktuell %s" % fp["hash"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	for ext in ["", ".bak", ".v1.vor_migration"]:
		if FileAccess.file_exists(MIG_PATH + ext):
			DirAccess.remove_absolute(MIG_PATH + ext)
	DirAccess.copy_absolute(FIXTURE, MIG_PATH)
	var raw: Dictionary = SaveManager.read_file(MIG_PATH)
	var orig_text := FileAccess.get_file_as_string(MIG_PATH)
	var v1 = JSON.parse_string(orig_text.substr(orig_text.find("\n") + 1))
	var calls := PopulationSpawner.spawn_calls
	var life := LifeSimulation.new()
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	life.setup(sim, db, world, objs)
	sc.lives.append(life)
	var r := SaveManager.load_into(life, MIG_PATH)
	_check("Migration Format 1 → 2 → 3: Spielstand aus v0.3.0 lädt, Original vorher gesichert", r["ok"] and int(r.get("migrated_from", 0)) == 1 and FileAccess.file_exists(MIG_PATH + ".v1.vor_migration")
		and FileAccess.get_file_as_string(MIG_PATH + ".v1.vor_migration") == orig_text and raw["ok"], str(r["message"]).substr(0, 200))
	if not r["ok"]:
		return
	var ctx := life.ctx
	var bodies_eq := true
	var pers_ok := true
	var empty_ok := true
	for c in v1["creatures"]:
		var cr: Creature = ctx.creatures[int(c["id"])]
		if JSON.stringify(TestMind._n(c["plan"])) != JSON.stringify(TestMind._n(cr.plan.to_dict())) or JSON.stringify(TestMind._n(c["health"])) != JSON.stringify(TestMind._n(cr.health.to_dict())):
			bodies_eq = false
		if cr.personality.to_dict() != Personality.generate(cr.plan_seed, ctx.mind_cfg).to_dict():
			pers_ok = false
		if not cr.memory.entries.is_empty() or not cr.beliefs.items.is_empty() or not cr.relations.rel.is_empty() or absf(cr.mind_since_t - float(v1["simulation"]["time_s"])) > 1e-9 \
				or not cr.ai["hearsay"].is_empty() or not cr.ai["plan"].is_empty() or not cr.ai["notes"].is_empty():
			empty_ok = false
	_check("Migration: Körper, Verletzungen und Prothesen unverändert; Anzahl gleich; Spawner nicht aufgerufen", bodies_eq and ctx.creatures.size() == v1["creatures"].size() and PopulationSpawner.spawn_calls == calls)
	_check("Migration: reproduzierbare Persönlichkeit aus Körper-Startwert", pers_ok)
	_check("Migration: keine erfundenen Erinnerungen/Überzeugungen/Beziehungen; Vergangenheit vor dem Laden unbekannt", empty_ok)
	_check("Migration: Ressourcen und Weltzustand erhalten (Nahrung, Zeit, Bilanz, Gelände)",
		absf(ctx.now() - float(v1["simulation"]["time_s"])) < 1e-9 and ctx.foods.size() == v1["foods"].size() and absf(ctx.ledger.balance_error(ctx)) < 1e-9 and ctx.ledger.god_kg == 0.0
		and life.world.data.hash_sha256() == str(v1["world"]["current_hash"]) and life.audit().is_empty(), str(life.audit()))
	sc.run(life, 20.0)
	_check("Migration: Simulation läuft danach weiter, Wesen lernen ab jetzt", life.audit().is_empty() and ctx.now() > float(v1["simulation"]["time_s"]))
	# Veränderte Definitionen in Format 1 → keine Migration
	var p_bad: Dictionary = JSON.parse_string(orig_text.substr(orig_text.find("\n") + 1))
	p_bad["definitions"]["hash"] = "verändert"
	var mr := SaveMigrations.migrate(p_bad, 1)
	_check("Migration verweigert Format-1-Stände mit veränderten Definitionen", not mr["ok"] and mr["code"] == "definitions_changed", mr["message"])
	for ext in ["", ".bak", ".v1.vor_migration"]:
		if FileAccess.file_exists(MIG_PATH + ext):
			DirAccess.remove_absolute(MIG_PATH + ext)


static func _n(v):
	return JSON.parse_string(JSON.stringify(v, "", true, true))
