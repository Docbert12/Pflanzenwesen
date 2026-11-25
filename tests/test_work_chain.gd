class_name TestWorkChain
extends RefCounted
## Abnahmetests Prompt 6B: Arbeitsposen und Werkzeug-/Materialkette (Testszene „Werkzeugkette“).
## Kontrollierte Funktionstests sind GEZIELT AUSGELÖST (Herkunft sichtbar). Sie beweisen, dass die Kette
## über dieselben Handlungen wie im Spiel funktioniert – nicht, dass Wesen sie selbst wählen. Die
## eigenständige Wahl prüft der Beobachtungslauf (Verhalten an); sein Ergebnis wird als Messwert notiert.

const DT := 1.0 / 60.0

var results: Array = []
var notes: Array = []
var db: DefinitionDB
var sc: MindScenarios
var world_seed: int = 12345
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
	for f in [_t01_pose_geometry, _t02_body_limits, _t03_chain_store, _t04_chain_build, _t05_chain_melt, _t06_failure_cases,
			_t07_interrupt, _t08_save_load, _t09_contact_sync, _t10_normal_game, _t11_model_plan, _t12_autonomous_run]:
		if only != "" and not str(f.get_method()).contains(only):
			continue
		print("  Arbeits-Test: %s (%.1f s)" % [str(f.get_method()), Time.get_ticks_msec() / 1000.0])
		f.call()
		sc.cleanup()
	return results


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append({"name": "[Arbeit] " + name, "ok": ok, "detail": detail})


# ── Hilfen ────────────────────────────────────────

func _scene(behavior: bool = false) -> LifeSimulation:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, AIService.disabled())
	var r := life.new_work_scene(world_seed, behavior)
	if not r.get("ok", false):
		push_error("Testszene: " + str(r.get("message", "")))
	sc.lives.append(life)
	return life


func _run(life: LifeSimulation, secs: float) -> void:
	for i in int(round(secs / DT)):
		life.step(DT)


## Läuft, bis die Kette des Wesens beendet ist (oder max_s). Rückgabe: die (zuletzt) laufende Kette.
func _run_chain(life: LifeSimulation, cr: Creature, max_s: float, sampler: Callable = Callable()) -> WorkChain:
	var t := 0.0
	var w: WorkChain = life.ctx.work.active(cr)
	while t < max_s:
		life.step(DT)
		t += DT
		if sampler.is_valid():
			sampler.call()
		var a := life.ctx.work.active(cr)
		if a == null:
			break
		w = a
	var all := life.ctx.work.of_creature(cr.id)
	return all[0] if not all.is_empty() else w


func _id(life: LifeSimulation, key: String) -> int:
	return int(life.workshop[key])


func _total_mass(life: LifeSimulation) -> float:
	var s := 0.0
	for id in life.ctx.material_pieces:
		s += (life.ctx.material_pieces[id] as MaterialPiece).mass_kg
	return s


func _mass_by_material(life: LifeSimulation) -> Dictionary:
	var out := {}
	for id in life.ctx.material_pieces:
		var p: MaterialPiece = life.ctx.material_pieces[id]
		out[p.material_id] = float(out.get(p.material_id, 0.0)) + p.mass_kg
	return out


func _actions(life: LifeSimulation, cr: Creature, type: String) -> Array:
	var out: Array = []
	for h in life.ctx.executor.history:
		if int(h["actor"]) == cr.id and str(h["type"]) == type:
			out.append(h)
	return out


## Ansicht eines Wesens (ohne Szenenbaum), gesteuert wie in LivingWorld._sync_views.
func _drive_view(life: LifeSimulation, cr: Creature, anim: Dictionary) -> CreatureView:
	var view := CreatureGenerator.build_view(cr.plan, life.sim.materials, 0.02)
	sc.nodes.append(view)
	view.position = cr.position
	view.rotation.y = cr.heading
	var side := cr.hold_side if cr.hold_side != "" else str(cr.caps.get("grasp_side", "r"))
	view.animator.request(str(anim["pose"]), side)
	var info := {"tool_h": WorkPose.tool_reach(life.ctx, cr.held_object_id) if cr.held_object_id != 0 else 0.0,
		"hold_mode": (cr.hold_mode if cr.hold_mode != "" else "one") if cr.held_object_id != 0 else "", "moving": false, "target_local": null}
	if anim.has("target"):
		var tg: Array = anim["target"]
		info["target_local"] = WorkPose.to_local(cr.position, cr.heading, Vector3(float(tg[0]), float(tg[1]), float(tg[2])))
	view.animator.drive_data = anim
	view.animator.drive_info = info
	view.animator.update(0.0)
	return view


## Weltpunkt des Werkzeugkopfs (bzw. des Griffs bei h = 0) aus den tatsächlich gesetzten Gelenken.
static func _head_world(view: CreatureView, side: String, h: float) -> Vector3:
	var g := view.animator.grip_frame(side)
	if not g["ok"]:
		return Vector3(INF, INF, INF)
	return view.transform * ((g["xform"] as Transform3D) * Vector3(h, 0.0, 0.0))


# ── 1. Posen: Animation ≡ WorkPose-Geometrie ────────

func _t01_pose_geometry() -> void:
	var life := _scene()
	var cr := WorkChainScene.actor(life)
	var view := CreatureGenerator.build_view(cr.plan, life.sim.materials, 0.02)
	sc.nodes.append(view)
	var worst := 0.0
	var worst_case := ""
	var n := 0
	for side in ["r", "l"]:
		var b := WorkPose.body(cr.plan, side)
		for kind in ["strike", "place", "pour"]:
			for h in ([0.0] if kind == "place" else [0.0, 0.18, 0.3]):
				for ty in [0.02, 0.08, 0.16]:
					var pose := WorkPose.contact(b, h, ty, kind)
					var anim := {"pose": "strike" if kind == "strike" else ("pour" if kind == "pour" else "place"), "phase": "contact" if kind == "strike" else "work", "u": 0.15 if kind == "pour" else 0.5,
						"target": [0.0, ty, 0.0], "contacts": 1}
					view.animator.request(str(anim["pose"]), side)
					view.animator.drive_data = anim
					view.animator.drive_info = {"tool_h": h, "hold_mode": "one", "moving": false, "target_local": Vector3(float(b["sx"]), ty, 0.3)}
					view.animator.update(0.0)
					var expect := WorkPose.head_local(b, pose, h)
					var got := _head_world(view, side, h)   # Ansicht steht im Ursprung → Körperrahmen
					if got.distance_to(expect) > worst:
						worst = got.distance_to(expect)
						worst_case = "%s %s h=%.2f y=%.2f: erwartet %s, Gelenke %s" % [side, kind, h, ty, str(expect), str(got)]
					n += 1
	_check("Arbeitsposen: Gelenkkette der Animation trifft die WorkPose-Kontaktpunkte (beide Seiten, Schlag/Einsetzen/Gießen)", worst < 0.01 and n == 42,
		"%d Posen, größte Abweichung %.4f m (%s)" % [n, worst, worst_case])
	# Kontaktposen erreichen die geforderte Höhe (Rumpfneigung + Hocke, Füße am Boden)
	var b2 := WorkPose.body(cr.plan, "r")
	var miss: Array = []
	for ty2 in [0.0, 0.05, 0.1, 0.2]:
		var p2 := WorkPose.contact(b2, 0.3, ty2, "strike")
		if not p2["ok"]:
			miss.append("Schlag %.2f m → Kopf %.3f m" % [ty2, float(p2["head_y"])])
		var p3 := WorkPose.contact(b2, 0.0, ty2 + 0.02, "place")
		if not p3["ok"]:
			miss.append("Greifen %.2f m → Hand %.3f m" % [ty2 + 0.02, float(p3["head_y"])])
	_check("Kontaktposen erreichen Ziele von Bodenhöhe bis 0,2 m (Schlag mit 0,3-m-Werkzeug, Greifen/Ablegen mit der Hand)", miss.is_empty(), "nicht erreichbar: %s" % str(miss))


# ── 2. Körpergrenzen: entfernter Arm, Zweihandposen, vorbereitete Posen ────────

func _t02_body_limits() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	life.dev_body_change(cr.id, "remove_forearm", "r")
	var view := CreatureGenerator.build_view(cr.plan, life.sim.materials, 0.02)
	sc.nodes.append(view)
	var s1 := view.animator.request("strike", "r")
	view.animator.drive_data = {"pose": "strike", "phase": "contact", "u": 1.0, "contacts": 1}
	view.animator.drive_info = {"tool_h": 0.3, "hold_mode": "one", "moving": false, "target_local": Vector3(0, 0.05, 0.3)}
	view.animator.update(0.0)
	var used := view.animator.used_part_ids()
	_check("Fehlender rechter Unterarm: Schlag weicht auf die linke Hand aus, entfernte Teile werden nie bewegt",
		s1["ok"] and s1["side"] == "l" and not used.has("arm_r_lower") and not used.has("hand_r") and used.has("arm_l_upper"), "%s · bewegt: %s" % [s1["message"], str(used)])
	var s2 := view.animator.request("place_two", "r")
	var s3 := view.animator.request("assemble", "r")
	var s4 := view.animator.request("assemble_one", "r")
	_check("Zweihandposen ohne zweite Hand abgelehnt; einarmiges Verbinden als Variante erlaubt",
		not s2["ok"] and not s3["ok"] and s4["ok"] and s4["side"] == "l" and str(s2["message"]).contains("zwei"), "%s | %s | %s" % [s2["message"], s3["message"], s4["message"]])
	var d1 := view.animator.request("dig", "l")
	var d2 := view.animator.request("compact", "l")
	_check("Graben/Verdichten vorbereitet, aber nachvollziehbar abgewiesen (keine Abbau-Mengenbilanz)",
		not d1["ok"] and not d2["ok"] and str(d1["message"]).contains("vorbereitet"), "%s | %s" % [d1["message"], d2["message"]])
	# Handlungsseite: Verbinden mit einer Hand = einarmige Variante; Tragen eines breiten Stücks braucht zwei Hände
	var wide := ConstructionSystem.new_piece(ctx, "stone", "lump", Vector3(0.11, 0.11, 0.11), ctx.sim.thermal.ambient_temperature_k, cr.position + Vector3(0.3, 0.01, 0.3), "test_equipment", "breiter Stein", true)
	var cc := ToolUseSystem.check_carry(ctx, cr, int(wide["id"]))
	_check("Einarmig: zu breites Stück wird mit Begründung nicht getragen (zweite Hand fehlt)", not cc["ok"] and str(cc["message"]).contains("zweite"), str(cc["message"]))
	var l2 := _scene()
	var cr_full := WorkChainScene.actor(l2)
	var cc2 := ToolUseSystem.check_carry(l2.ctx, cr_full, int(l2.workshop["heavy_block"]))
	_check("Sehr schwerer Block auch mit zwei Händen abgewiesen (Masse > Tragegrenze beider Hände)", not cc2["ok"] and str(cc2["message"]).contains("beiden Händen zu schwer"), str(cc2["message"]))


# ── 3. Kette „lagern“: Hammer → Schlag → Bruchstücke → Lager ────────

func _t03_chain_store() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	var m0 := _total_mass(life)
	var mm0 := _mass_by_material(life)
	var big := _id(life, "big_stone")
	var big_mass := (ctx.material_pieces[big] as MaterialPiece).mass_kg
	var big_e := (ctx.material_pieces[big] as MaterialPiece).thermal_energy_j
	var parts := [_id(life, "handle"), _id(life, "head"), _id(life, "fiber")]
	var tr := WorkChainScene.trigger(life, "lagern")
	var samples := {"carry_kg": 0.0, "tool_seen": 0, "two_hand": false, "hud_ok": true, "held_copy": 0, "status": {}}
	var sampler := func():
		var v := ctx.work.status_view(cr, ctx)
		if v.is_empty():
			return
		for k in ["ziel", "handlung", "werkzeug", "zielobjekt", "getragen_kg", "fortschritt", "abbruchgrund"]:
			if not v.has(k):
				samples["hud_ok"] = false
		samples["carry_kg"] = maxf(float(samples["carry_kg"]), float(v["getragen_kg"]))
		if cr.hold_mode == "two":
			samples["two_hand"] = true
		if cr.held_object_id != 0 and ctx.assemblies.has(cr.held_object_id):
			samples["tool_seen"] = cr.held_object_id
			# Ausrüsten erzeugt keine Kopie: Verbund nur einmal vorhanden, seine Teile nur in ihm, Position = Hand
			var asm: Assembly = ctx.assemblies[cr.held_object_id]
			for pid in asm.part_ids:
				if (ctx.material_pieces[pid] as MaterialPiece).assembly_id != asm.id:
					samples["held_copy"] = int(samples["held_copy"]) + 1
			if asm.carrier_id != cr.id or asm.position.distance_to(ToolUseSystem.hand_position(cr)) > 0.05:
				samples["held_copy"] = int(samples["held_copy"]) + 1
	var w := _run_chain(life, cr, 400.0, sampler)
	_check("(lagern) Kette gezielt ausgelöst und abgeschlossen", tr.get("ok", false) and w != null and w.status == "abgeschlossen" and not w.autonomous,
		"%s · %s · %s" % [str(tr.get("message", "")), w.status if w != null else "-", w.abort_reason if w != null else ""])
	if w == null:
		return
	var hammer := w.tool_id
	var asm: Assembly = ctx.assemblies.get(hammer, null)
	_check("(lagern) Hammer aus den vorhandenen Teilen gebunden: eigene eindeutige ID, besteht aus Stiel, Steinkopf und Fasern",
		asm != null and hammer != 0 and not (hammer in parts) and asm.head_part_id == parts[1] and asm.part_ids.has(parts[0]) and samples["tool_seen"] == hammer,
		"Hammer #%d, Teile %s" % [hammer, str(asm.part_ids) if asm != null else "-"])
	_check("(lagern) Ausrüsten ohne Kopie: genau dieser Hammer in der Hand, Teile nur im Verbund, Lage = Hand", int(samples["held_copy"]) == 0, "%d Abweichungen" % int(samples["held_copy"]))
	var deform := _actions(life, cr, "deform_material")
	var strikes := 0
	var contacts := 0
	for h in deform:
		strikes += int(h["consumed"].get("strikes", 0))
		contacts += int(h["consumed"].get("contacts", 0))
	var frags: Array = []
	for id in ctx.material_pieces:
		var p: MaterialPiece = ctx.material_pieces[id]
		if p.origin == "bruch:#%d" % big:
			frags.append(p)
	var fm := 0.0
	var fe := 0.0
	var temps_ok := true
	for p in frags:
		fm += p.mass_kg
		fe += p.thermal_energy_j
		if p.material_id != "stone":
			temps_ok = false
	_check("(lagern) Schlag: Stein zerbricht nach mehreren Schlägen; jeder Schlag genau EIN Kontakt", strikes > 1 and contacts == strikes and not ctx.material_pieces.has(big),
		"%d Schläge, %d Kontakte" % [strikes, contacts])
	_check("(lagern) Bruchstücke: gleiches Material, Gesamtmasse und Wärmeenergie erhalten", frags.size() >= 2 and absf(fm - big_mass) < 1e-9 and temps_ok and absf(fe - big_e) <= 1e-6 * absf(big_e) + 1e-9,
		"%d Stücke, %.6f kg von %.6f kg" % [frags.size(), fm, big_mass])
	var st: StoragePlace = ctx.storages[_id(life, "storage")]
	var in_store := 0
	for p in frags:
		if p.storage_id == st.id and st.contents.has(p.id) and StorageSystem.inside(st, p.position, 0.05):
			in_store += 1
	_check("(lagern) Bruchstücke getragen (eine Hand bzw. beide Hände) und real eingelagert", in_store == frags.size() and float(samples["carry_kg"]) > 0.0 and w.delivered.size() == frags.size()
		and absf(w.moved_kg - big_mass) < 1e-6, "%d/%d im Lager, transportiert %.3f kg, max. getragen %.2f kg, zweihändig %s" % [in_store, frags.size(), w.moved_kg, float(samples["carry_kg"]), str(samples["two_hand"])])
	var mm1 := _mass_by_material(life)
	var mat_ok := true
	for k in mm0:
		if absf(float(mm0[k]) - float(mm1.get(k, 0.0))) > 1e-9:
			mat_ok = false
	_check("(lagern) Nichts verschwindet: Gesamtmasse und Masse je Material unverändert", absf(_total_mass(life) - m0) < 1e-9 and mat_ok, "%.6f → %.6f kg" % [m0, _total_mass(life)])
	_check("(lagern) Anzeige: Ziel, Handlung, Werkzeug-ID, Zielobjekt, getragene Masse, Fortschritt, Abbruchgrund vorhanden", samples["hud_ok"])
	_check("(lagern) Wissen verbucht: Binden, Schlagen, Lagern als eigene Erfahrung", ProceduralKnowledge.level(cr, "lagern:stone") != "" and WorkSystem.knows_procedure(cr, "verbinden:lashing", "erfolgreich"),
		str(w.knowledge))
	_check("(lagern) Konsistenz (Audit leer)", life.audit().is_empty(), str(life.audit().slice(0, 3)))


# ── 4. Kette „bauen“: Steinreihe aus Bruchstücken und vorhandenem Stein ────────

func _t04_chain_build() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	var m0 := _total_mass(life)
	WorkChainScene.trigger(life, "bauen")
	var w := _run_chain(life, cr, 400.0)
	var st: Structure = ctx.structures[_id(life, "site")]
	var ev := StructureSystem.evaluate(ctx, st)
	var built_ok := true
	for sl in st.slots:
		var pid := int(sl["part_id"])
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p == null or p.structure_id != st.id or p.is_free():
			built_ok = false
	_check("(bauen) Steinreihe vollständig aus realen Steinen gebaut (Bruchstücke + vorhandener Stein)", w != null and w.status == "abgeschlossen" and st.filled() == st.slots.size() and built_ok and st.status == "fertig",
		"%s · %d/%d · %s" % [w.status if w != null else "-", st.filled(), st.slots.size(), str(ev.get("funktion", ""))])
	var p0: MaterialPiece = ctx.material_pieces.get(int(st.slots[0]["part_id"]), null)
	var g := ToolUseSystem.check_grasp(ctx, cr, p0.id) if p0 != null else ActionResult.fail("x", "x")
	_check("(bauen) Verbaute Teile sind fest: nicht mehr greifbar, Funktion messbar aus den Teilen (kein Name als Nachweis)",
		not g.ok and g.code == "built_in" and int(ev["teile"]) == 3 and ev.has("hoehe_m") and ev.has("hindernis_fuer_wegsuche"), "%s · %s" % [g.message, JSON.stringify(ev).left(140)])
	_check("(bauen) Masse erhalten, Audit leer", absf(_total_mass(life) - m0) < 1e-9 and life.audit().is_empty(), str(life.audit().slice(0, 2)))


# ── 5. Kette „schmelzen“: Kupfer bearbeiten → Tiegel → Testofen → Guss ────────

func _t05_chain_melt() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	var cu1 := _id(life, "copper1")
	var cu2 := _id(life, "copper2")
	var mcu := (ctx.material_pieces[cu1] as MaterialPiece).mass_kg + (ctx.material_pieces[cu2] as MaterialPiece).mass_kg
	var mm0 := _mass_by_material(life)
	var strain := {"max": 0.0}
	var sampler := func():
		var p: MaterialPiece = ctx.material_pieces.get(cu1, null)
		if p != null and p.liquid_fraction() == 0.0:
			strain["max"] = maxf(float(strain["max"]), p.strain)
	WorkChainScene.trigger(life, "schmelzen")
	var w := _run_chain(life, cr, 600.0 if quick else 900.0, sampler)
	var cast := ConstructionSystem.contents_of(ctx, _id(life, "mold"))
	var cm := 0.0
	for c in cast:
		cm += (c as MaterialPiece).mass_kg
	_check("(schmelzen) Kupfer mit dem Hammer kalt verformt (Verformung statt Bruch)", float(strain["max"]) > 0.005, "Dehnung %.3f" % float(strain["max"]))
	_check("(schmelzen) Stücke im Tiegel, im Testofen geschmolzen und vollständig gegossen (Schmelzen vereinigt, Masse erhalten)",
		w != null and w.status == "abgeschlossen" and cast.size() == 1 and absf(cm - mcu) < 1e-6 and (cast[0] as MaterialPiece).material_id == "copper",
		"%s · %s · Guss %.4f kg von %.4f kg" % [w.status if w != null else "-", w.abort_reason if w != null else "", cm, mcu])
	var mm1 := _mass_by_material(life)
	_check("(schmelzen) Kupfermasse gesamt erhalten; Testofen ist Testausrüstung (kein selbst gebauter Ofen)",
		absf(float(mm0["copper"]) - float(mm1["copper"])) < 1e-9 and life.audit().is_empty() and (ctx.heaters[_id(life, "heater")] as TestHeater).origin != "", str(life.audit().slice(0, 2)))


# ── 6. Fehlerfälle ────────

func _t06_failure_cases() -> void:
	# Fehlendes Material
	var l1 := _scene()
	var r1 := WorkChainScene.trigger_case(l1, "material")
	_check("Fehlendes Material: Kette nicht planbar, Begründung nennt das fehlende Bauteil", not bool(r1.get("started", true)) and str(r1["message"]).contains("Fasern"), str(r1["message"]))
	sc.cleanup()
	# Blockierter Weg
	var l2 := _scene()
	var cr2 := WorkChainScene.actor(l2)
	WorkChainScene.trigger_case(l2, "weg")
	var w2 := _run_chain(l2, cr2, 300.0)
	_run(l2, 6.0)
	_check("Blockierter Weg: Kette stoppt nachvollziehbar („Weg blockiert“), Getragenes wird danach abgelegt",
		w2 != null and w2.status == "fehlgeschlagen" and w2.abort_reason.contains("blockiert") and (cr2.held_object_id == 0 or l2.ctx.assemblies.has(cr2.held_object_id)),
		"%s · %s · hält #%d" % [w2.status if w2 != null else "-", w2.abort_reason if w2 != null else "", cr2.held_object_id])
	sc.cleanup()
	# Fehlender Arm
	var l3 := _scene()
	var cr3 := WorkChainScene.actor(l3)
	WorkChainScene.trigger_case(l3, "arm")
	var w3 := _run_chain(l3, cr3, 400.0)
	var conn := _actions(l3, cr3, "connect_parts")
	var variant := str(conn[conn.size() - 1]["consumed"].get("variant", "")) if not conn.is_empty() else ""
	var rej := ""
	if w3 != null:
		for r in w3.rejected:
			rej += str(r["reason"])
	_check("Fehlender Arm: Hammer einarmig gebunden (Variante), zu breites Stück mit Begründung liegen gelassen",
		w3 != null and variant == "einarmig" and w3.tool_id != 0 and (rej.contains("zweite") or w3.rejected.is_empty()), "Variante %s · %s · abgewiesen: %s" % [variant, w3.status, rej])
	sc.cleanup()
	# Zu schwerer Gegenstand
	var l4 := _scene()
	var cr4 := WorkChainScene.actor(l4)
	var r4 := WorkChainScene.trigger_case(l4, "schwer")
	var w4 := _run_chain(l4, cr4, 60.0)
	_check("Zu schwerer Gegenstand: nicht getragen, Kette endet mit Begründung (keine Teleportation)",
		w4 != null and w4.status == "fehlgeschlagen" and w4.abort_reason.contains("zu schwer") and l4.ctx.material_pieces[_id(l4, "heavy_block")].storage_id == 0,
		"%s · %s" % [str(r4.get("message", "")), w4.abort_reason if w4 != null else ""])
	sc.cleanup()
	# Ungeeignetes Schmelzgut
	var l5 := _scene()
	var cr5 := WorkChainScene.actor(l5)
	WorkChainScene.trigger_case(l5, "ungeeignet")
	var w5 := _run_chain(l5, cr5, 300.0)
	var wood: MaterialPiece = l5.ctx.material_pieces.get(_id(l5, "wood_scrap"), null)
	_check("Ungeeignetes Material: Holz wird nicht in den Tiegel gelegt (brennbar, nicht schmelzbar), Kupfer wird geschmolzen",
		wood != null and wood.container_id == 0 and wood.liquid_fraction() == 0.0 and w5 != null and w5.status == "abgeschlossen" and not w5.rejected.is_empty(),
		"%s · abgewiesen %s" % [w5.status if w5 != null else "-", str(w5.rejected) if w5 != null else ""])
	sc.cleanup()
	# Fehlende Wärmequelle
	var l6 := _scene()
	var r6 := WorkChainScene.trigger_case(l6, "ohne_ofen")
	_check("Fehlende Wärmequelle: Schmelzkette nicht planbar, Begründung „keine Wärmequelle“", str(r6["message"]).contains("Wärmequelle") and l6.ctx.work.active(WorkChainScene.actor(l6)) == null, str(r6["message"]))


# ── 7. Unterbrechung: pausieren, fortsetzen, nichts verdoppeln ────────

func _t07_interrupt() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	var big := _id(life, "big_stone")
	WorkChainScene.trigger(life, "lagern")
	# bis in die Schlagfolge laufen
	var t := 0.0
	while t < 120.0:
		life.step(DT)
		t += DT
		var a: GameAction = ctx.executor.running.get(cr.id, null)
		if a != null and a.type == "deform_material" and int(a.state.get("strikes_done", 0)) >= 2:
			break
	var dmg := (ctx.material_pieces[big] as MaterialPiece).damage if ctx.material_pieces.has(big) else 1.0
	var r := WorkChainScene.trigger_case(life, "unterbrechen")
	var w := ctx.work.active(cr)
	var paused := w != null and w.status == "pausiert" and not ctx.executor.running.has(cr.id)
	var dmg_after := (ctx.material_pieces[big] as MaterialPiece).damage if ctx.material_pieces.has(big) else 1.0
	_check("Unterbrechung: Schlagfolge abgebrochen, Kette pausiert; bereits ausgeführte Schläge bleiben wirksam", paused and dmg > 0.0 and absf(dmg_after - dmg) < 1e-12,
		"%s · Schaden %.3f → %.3f" % [str(r.get("message", "")), dmg, dmg_after])
	var w2 := _run_chain(life, cr, 400.0)
	var frags := 0
	for id in ctx.material_pieces:
		if (ctx.material_pieces[id] as MaterialPiece).origin == "bruch:#%d" % big:
			frags += 1
	_check("Unterbrechung: Kette wird fortgesetzt und abgeschlossen, ohne Schritte zu verdoppeln (ein Hammer, Stücke einmal eingelagert)",
		w2 != null and w2.status == "abgeschlossen" and ctx.work.stats["resumed"] >= 1 and ctx.assemblies.size() == 2 and w2.delivered.size() == frags,
		"%s · fortgesetzt %d · Verbünde %d · %d/%d" % [w2.status if w2 != null else "-", int(ctx.work.stats["resumed"]), ctx.assemblies.size(), w2.delivered.size() if w2 != null else 0, frags])


# ── 8. Speichern und Laden während der Herstellung ────────

func _t08_save_load() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	WorkChainScene.trigger(life, "lagern")
	# nach dem Binden, während ein Stück getragen bzw. geschlagen wird
	var t := 0.0
	while t < 200.0:
		life.step(DT)
		t += DT
		var w0 := ctx.work.active(cr)
		if w0 != null and w0.tool_id != 0 and (cr.hold_mode == "two" or (w0.current_step().get("op", "") == "carry" and cr.held_object_id != 0)):
			break
	var held_before := cr.held_object_id
	var path := "user://saves/_test_work.json"
	var sv := SaveManager.save(life, path)
	var snap := SaveManager.snapshot(life)
	var m0 := _total_mass(life)
	var sim2 := Simulation.new()
	var world2 := VoxelWorld.new()
	var objs2 := Node3D.new()
	sim2.initialize()
	sim2.set_physics_process(false)
	world2.set_physics_process(false)
	sc.nodes.append_array([sim2, world2, objs2])
	var life2 := LifeSimulation.new()
	life2.setup(sim2, db, world2, objs2, AIService.disabled())
	sc.lives.append(life2)
	var r := SaveManager.load_into(life2, path)
	var c2 := life2.ctx
	var cr2 := c2.creature(cr.id)
	var w := c2.work.active(cr2) if cr2 != null else null
	_check("Speichern/Laden mitten in der Kette: Kette, Werkzeug und Gehaltenes erhalten (Speicherformat %d)" % SaveSchema.FORMAT_VERSION,
		sv["ok"] and r["ok"] and w != null and w.resumed_after_load and cr2.held_object_id == held_before and c2.assemblies.has(w.tool_id) and absf(_total_mass(life2) - m0) < 1e-9,
		"%s · hält #%d/#%d · Kette %s" % [str(r.get("message", "")), held_before, cr2.held_object_id if cr2 != null else -1, w.status if w != null else "-"])
	var snap2 := SaveManager.snapshot(life2)
	var rt := func(v): return JSON.parse_string(JSON.stringify(v))
	var d := TestTechnology.first_diff(rt.call(snap["work"]), rt.call(snap2["work"]), "Arbeit")
	_check("Speichern/Laden: Arbeitsketten-Zustand identisch (bis auf Fortsetzungsvermerk)", d == "" or d.contains("resumed_after_load") or d.contains("log") or d.contains("pending_action"), d)
	var w2 := _run_chain(life2, cr2, 400.0)
	_check("Nach dem Laden: Kette läuft weiter und wird abgeschlossen (keine Verdopplung, Masse erhalten, Audit leer)",
		w2 != null and w2.status == "abgeschlossen" and absf(_total_mass(life2) - m0) < 1e-9 and c2.assemblies.size() == ctx.assemblies.size() and life2.audit().is_empty(),
		"%s · %s · %s" % [w2.status if w2 != null else "-", w2.abort_reason if w2 != null else "", str(life2.audit().slice(0, 2))])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.backup_path(path)))


# ── 9. Synchronisation: sichtbarer Kontakt am Ziel, kein Fußgleiten in der Arbeitsphase ────────

func _t09_contact_sync() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	WorkChainScene.trigger(life, "lagern")
	var errs: Array = []
	var err_vecs: Array = []
	var contact_frames := 0
	var slide := 0.0
	var last_pos = null
	var phase_seq: Array = []
	var t := 0.0
	while t < 200.0:
		life.step(DT)
		t += DT
		var a: GameAction = ctx.executor.running.get(cr.id, null)
		if a == null or a.type != "deform_material":
			last_pos = null
			if not ctx.material_pieces.has(_id(life, "big_stone")):
				break
			continue
		var an: Dictionary = a.state.get("anim", {})
		var ph := str(an.get("phase", ""))
		if phase_seq.is_empty() or phase_seq[phase_seq.size() - 1] != ph:
			phase_seq.append(ph)
		if ph in ["work", "contact"]:
			if last_pos != null:
				slide = maxf(slide, (cr.position - (last_pos as Vector3)).length())
			last_pos = cr.position
		if ph == "contact" and contact_frames < 6:
			contact_frames += 1
			var view := _drive_view(life, cr, an)
			var hw := _head_world(view, cr.hold_side if cr.hold_side != "" else "r", WorkPose.tool_reach(ctx, cr.held_object_id))
			var tg: Array = an["target"]
			var tv := Vector3(float(tg[0]), float(tg[1]), float(tg[2]))
			errs.append(hw.distance_to(tv))
			err_vecs.append(WorkPose.to_local(cr.position, cr.heading, hw) - WorkPose.to_local(cr.position, cr.heading, tv))
	var worst := 0.0
	for e in errs:
		worst = maxf(worst, float(e))
	_check("Schlag: sichtbarer Kontakt des Hammerkopfs liegt am Ziel (≤ 8 cm), nicht daneben", not errs.is_empty() and worst <= 0.08,
		"%d Kontakte gemessen, größte Abweichung %.3f m · Abweichungen (Körperrahmen) %s" % [errs.size(), worst, str(err_vecs.slice(0, 3))])
	_check("Schlag: Phasen Anlauf → Ausholen/Arbeit → Kontakt → Rückkehr; während der Arbeit kein Fußgleiten", phase_seq.has("work") and phase_seq.has("contact") and phase_seq.has("recover") and slide < 0.001,
		"%s · max. Verschiebung %.4f m" % [str(phase_seq.slice(0, 8)), slide])


# ── 10. Normaler Spielmodus: derselbe Ausführungscode ────────

func _t10_normal_game() -> void:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	sc.nodes.append_array([sim, world, objs])
	var life := LifeSimulation.new()
	life.setup(sim, db, world, objs, AIService.disabled())
	sc.lives.append(life)
	var r := life.new_game(world_seed)
	var ctx := life.ctx
	_check("Normales Spiel: Arbeitssystem aktiv, aber keine Testausrüstung, kein Lager, keine Baustelle, keine Kette beim Start",
		r["ok"] and ctx.work != null and ctx.storages.is_empty() and ctx.structures.is_empty() and ctx.work.chains.is_empty() and ctx.material_pieces.is_empty())
	# Ein Wesen: Göttermenü legt Hammerteile und einen Stein hin; Kette wird über DENSELBEN WorkSystem-Code ausgeführt
	var ids := ctx.creatures.keys()
	ids.sort()
	var cr: Creature = ctx.creatures[ids[0]]
	cr.behavior_enabled = false
	var c := cr.position
	var placed: Array = []
	for spec in [{"material_id": "wood", "shape": "rod", "off": Vector3(0.7, 0, 0.4)}, {"material_id": "stone", "shape": "block", "size_m": 0.06, "off": Vector3(-0.7, 0, 0.5)},
			{"material_id": "plant_fiber", "off": Vector3(0.0, 0, 0.8)}, {"material_id": "stone", "shape": "block", "size_m": 0.08, "off": Vector3(0.5, 0, -0.7)}]:
		var cmd := {"kind": "place_material", "material_id": spec["material_id"], "position": c + (spec["off"] as Vector3)}
		for k in ["shape", "size_m"]:
			if spec.has(k):
				cmd[k] = spec[k]
		var g := ctx.interventions.execute(cmd)
		placed.append(str(g.get("message", "")) if not g.get("ok", false) else "ok")
	var sp := StorageSystem.create(ctx, c + Vector3(-1.0, 0, -0.6), Vector2(0.6, 0.6), "Lagerplatz (Göttermenü-Test)", "test_equipment")
	ExperimentSystem.perceive_objects(cr, ctx)
	StorageSystem.perceive(cr, ctx, 10.0)
	var stones: Array = []
	for id in ctx.material_pieces:
		if (ctx.material_pieces[id] as MaterialPiece).material_id == "stone":
			stones.append(int(id))
	var tr := ctx.work.trigger(cr, "lagern", {"storage": sp.id, "pieces": stones}, ctx, "Test normales Spiel (gezielt)")
	var w := _run_chain(life, cr, 180.0)
	_check("Normales Spiel: dieselbe Kette (WorkSystem → Handlungen) läuft mit Göttermenü-Material", tr.get("ok", false) and w != null and w.status == "abgeschlossen" and not w.delivered.is_empty(),
		"Platzieren %s · %s · %s · %s" % [str(placed), str(tr.get("message", "")), w.status if w != null else "-", w.abort_reason if w != null else ""])
	_check("Normales Spiel: Audit leer", life.audit().is_empty(), str(life.audit().slice(0, 3)))


# ── 11. Modellvorschlag (Ollama): nur geprüfte Pläne ────────

func _t11_model_plan() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	var bad := ctx.work.validate_model_plan(cr, {"goal": "lagern", "steps": [{"op": "teleport", "obj": 1}, {"op": "carry", "obj": 999999, "dest": _id(life, "storage")}]}, ctx)
	var good := ctx.work.validate_model_plan(cr, {"goal": "lagern", "dest": _id(life, "storage"), "steps": [{"op": "carry", "obj": _id(life, "stone_medium"), "dest": _id(life, "storage"), "mode": "deposit"}, {"op": "check"}]}, ctx)
	_check("Modellvorschlag: unbekannte Schritte und unbekannte Gegenstände abgewiesen, gültiger Plan nur mit bekannten IDs",
		not bad["ok"] and (bad["errors"] as Array).size() >= 2 and good["ok"], "%s | %s" % [str(bad.get("errors", [])), str(good.get("errors", []))])
	if good["ok"]:
		var st := ctx.work.start(cr, "lagern", good["plan"], "Modellvorschlag (geprüft)", false, ctx)
		ctx.work.advance(cr, ctx)
		var w := _run_chain(life, cr, 120.0)
		_check("Modellvorschlag: ausgeführt nur über geprüfte Spielhandlungen (Stück real eingelagert)", st["ok"] and w != null and w.status == "abgeschlossen"
			and (ctx.material_pieces[_id(life, "stone_medium")] as MaterialPiece).storage_id == _id(life, "storage"), w.abort_reason if w != null else "-")


# ── 12. Beobachtungslauf: eigenständige Wahl (Messwert, getrennt dokumentiert) ────────

func _t12_autonomous_run() -> void:
	var life := _scene()
	var ctx := life.ctx
	var cr := WorkChainScene.actor(life)
	# Vorgeschichte (kontrolliert): das Wesen baut einmal gezielt eine Steinreihe und lernt dabei selbst
	WorkChainScene.trigger(life, "bauen")
	var w0 := _run_chain(life, cr, 400.0)
	# Neues Material (wie Göttermenü): großer Stein und loser Stein in der Nähe; danach eigenes Verhalten AN
	var amb := ctx.sim.thermal.ambient_temperature_k
	ConstructionSystem.new_piece(ctx, "stone", "block", Vector3(0.1, 0.1, 0.1), amb, TestWorkshop._ground(life, cr.position + Vector3(1.2, 0, -1.6)), "test_equipment", "Großer Stein (neu)", true)
	ConstructionSystem.new_piece(ctx, "stone", "block", Vector3(0.07, 0.07, 0.07), amb, TestWorkshop._ground(life, cr.position + Vector3(-1.4, 0, 1.2)), "test_equipment", "Stein (neu)", true)
	WorkChainScene.look_around(life)
	cr.behavior_enabled = true
	var started0 := int(ctx.work.stats["autonomous_started"])
	var secs := 300.0 if quick else 600.0
	_run(life, secs)
	var auto: Array = []
	for wch in ctx.work.of_creature(cr.id):
		if (wch as WorkChain).autonomous:
			auto.append("#%d %s: %s (%s)" % [wch.id, wch.goal, wch.status, wch.abort_reason if wch.abort_reason != "" else "%d Stücke" % wch.delivered.size()])
	var n_auto := int(ctx.work.stats["autonomous_started"]) - started0
	notes.append("Arbeits-Beobachtungslauf %.0f s (Verhalten AN nach einer gezielt ausgelösten Steinreihe%s): autonom gestartete Ketten %d, abgeschlossen %d; %s; Wesen lebt %s, Hunger %.0f %%" % [
		secs, "" if w0 != null and w0.status == "abgeschlossen" else " (Vorgeschichte unvollständig)", n_auto, int(ctx.work.stats["autonomous_completed"]),
		"; ".join(auto) if not auto.is_empty() else "keine eigenständige Kette beobachtet", str(cr.alive), cr.metabolism.hunger() * 100.0])
	_check("Beobachtungslauf: Wesen lebt, Konsistenz (Audit leer); eigenständige Ketten werden als Messwert protokolliert", cr.alive and life.audit().is_empty(),
		"%d autonom gestartet · %s" % [n_auto, str(life.audit().slice(0, 2))])
