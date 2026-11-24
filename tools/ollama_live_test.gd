extends SceneTree
## LIVE-TEST mit ECHTEM Ollama – auf dem eigenen Rechner auszuführen (im Arbeitsbereich der Entwicklung
## war kein Ollama erreichbar). Nur Abfragen: lädt, löscht, startet oder stoppt nichts.
##
##   godot --headless --path . -s res://tools/ollama_live_test.gd -- [--model=NAME] [--url=http://127.0.0.1:11434]
##         [--minutes=3] [--unterbrechung]
##
## Ablauf (Prompt 5, Abschnitt 17):
##   0 Verbindung: Version, installierte Modelle, geladene Modelle
##   1 Ein Wesen, eine Plananfrage
##   2 Zwei Wesen, ein kurzes Gespräch
##   3 50 Wesen mit begrenzter Anfragerate (Echtzeit, Standard 3 min)
##   4 Dienst unterbrechen (nur mit --unterbrechung: SIE beenden Ollama, das Werkzeug wartet)
##   5 Dienst wieder verfügbar (SIE starten Ollama wieder)
## Bericht: user://ollama_live_report.txt (und Konsole). Formulierungen des Modells sind nie gleich –
## geprüft werden Struktur, Prüfergebnis und Wirkung.

const DT := 1.0 / 60.0

var lines: Array = []
var svc: AIService
var db: DefinitionDB
var keep: Array = []


func _initialize() -> void:
	create_timer(3600.0, true, false, true).timeout.connect(func(): _say("ABBRUCH: Zeitlimit 60 min"); _finish(3))
	_run.call_deferred()


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
		if a == "--" + name:
			return "ja"
	return fallback


func _finish(code: int) -> void:
	var f := FileAccess.open("user://ollama_live_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("Bericht: ", ProjectSettings.globalize_path("user://ollama_live_report.txt"))
	quit(code)


func _run() -> void:
	_say("Pflanzenwesen – Ollama-Live-Test (ECHTER Dienst, keine Simulation)")
	_say("Zeit: %s · Godot %s · %s · CPU %s (%d Kerne) · RAM %.1f GB" % [Time.get_datetime_string_from_system(), Engine.get_version_info()["string"], OS.get_name(),
		OS.get_processor_name(), OS.get_processor_count(), float(OS.get_memory_info().get("physical", 0)) / 1073741824.0])
	_say("Grafikkarte: im Kopflos-Modus von Godot nicht ermittelbar; Hinweis liefert Ollama (/api/ps: Speicher im Grafikspeicher).")
	var s := AISettings.load_settings()
	s.set_value("enabled", true)
	s.set_value("use_mock", false)
	var m := _arg("model", "")
	if m != "":
		s.set_value("model", m)
	var u := _arg("url", "")
	if u != "":
		s.set_value("base_url", u)
	svc = AIService.new(s)
	if svc.simulated():
		_say("FEHLER: simulierter Dienst aktiv – Live-Test abgebrochen.")
		_finish(2)
		return
	db = DefinitionDB.new()
	db.load_all()
	# 0 Verbindung
	_say("\n== 0 Verbindung ==")
	if not _wait_status(["verbunden", "keine_modellwahl", "modell_fehlt", "nicht_erreichbar", "einstellung_fehlerhaft"], 15.0):
		_say("Keine Antwort auf die Verbindungsprüfung.")
	_say("Adresse %s · Zustand: %s · %s" % [svc.client.describe(), svc.status_text(), svc.status_message])
	_say("Installiert: %s" % ", ".join(svc.models.map(func(x): return "%s (%s, %s)" % [x["name"], x["parameter_size"], x["quantization"]])))
	if svc.status != "verbunden":
		_say("Live-Test endet hier. Modell wählen mit --model=NAME (aus der Liste oben) oder im KI-Panel (Taste K). Herunterladen nur selbst: ollama pull NAME.")
		_finish(1)
		return
	_say("Modell: %s · Ollama %s" % [str(s.g("model")), svc.version])
	# 1 Plan
	_say("\n== 1 Ein Wesen, eine Plananfrage ==")
	var life := _world(3)
	var ids: Array = life.ctx.creatures.keys()
	ids.sort()
	var a: Creature = life.ctx.creatures[ids[0]]
	var sc := MindScenarios.new(db)
	keep.append(sc)
	_place_near_food(life, sc, a)
	sc.set_hunger(a, 0.55)
	var r := life.ctx.ai.request_now(a, "plan", "Live-Test: einfache Plananfrage")
	_say(str(r["message"]))
	_wait_answer(life, a, float(s.g("timeout_s", 90.0)) * 2.0 + 20.0)
	_report_last(a)
	if PlanManager.active(a):
		a.behavior_enabled = true
		_step_real(life, 30.0)
		var h: Array = a.ai["plan_history"]
		if not h.is_empty():
			var lp: Dictionary = h[h.size() - 1]
			_say("Ausführung: Plan %s – %s" % [lp["state"], lp.get("result", "")])
			for st in lp["steps"]:
				_say("  %s %s #%d → %s" % [st["status"], st["action"], int(st["target"]), st["result"]])
		else:
			_say("Plan noch aktiv nach 30 s: Schritt %d" % (int(a.ai["plan"]["i"]) + 1))
	_say("Prüfung der Welt: %s" % ("in Ordnung" if life.audit().is_empty() else str(life.audit())))
	life.dispose()
	# 2 Gespräch
	_say("\n== 2 Zwei Wesen, ein kurzes Gespräch ==")
	var life2 := _world(2)
	var ids2: Array = life2.ctx.creatures.keys()
	ids2.sort()
	var sp: Creature = life2.ctx.creatures[ids2[0]]
	var li: Creature = life2.ctx.creatures[ids2[1]]
	_place_near_food(life2, sc, sp)
	sc.place(life2, li, sp.position + Vector3(1.3, 0, 0), 0.0)
	life2.ctx.rebuild_spatial_hash()
	Perception.scan(sp, life2.ctx)
	Perception.scan(li, life2.ctx)
	var r2 := life2.ctx.ai.request_now(sp, "talk", "Live-Test: Gespräch", li.id)
	_say(str(r2["message"]))
	_wait_answer(life2, sp, float(s.g("timeout_s", 90.0)) * 2.0 + 20.0)
	_report_last(sp)
	if PlanManager.active(sp):
		sp.behavior_enabled = true
		_step_real(life2, 6.0)
	for ut in life2.ctx.comm.recent(3):
		_say("Äußerung #%d → #%d (%s, %s): %s%s" % [ut["speaker"], ut["listener"], ut["via"], ut["status"], ut["text"], (" | Modelltext ohne Wirkung: " + str(ut["model_text"])) if str(ut["model_text"]) != "" else ""])
	for c in li.ai["hearsay"]:
		_say("Beim Zuhörer: Hörensagen von #%d, Status %s, Sicherheit %.2f" % [int(c["speaker"]), c["status"], float(c["certainty"])])
	life2.dispose()
	# 3 50 Wesen
	var minutes := float(_arg("minutes", "3"))
	_say("\n== 3 50 Wesen mit begrenzter Anfragerate (%.0f min Echtzeit) ==" % minutes)
	_say("Einstellungen: %d Anfragen/min, %d gleichzeitig, %.0f s Mindestabstand je Wesen, Anteil fragender Wesen %.0f %%" % [int(s.g("global_rate_per_min")), int(s.g("max_concurrent")),
		float(s.g("per_creature_min_interval_s")), float(s.g("eligible_share")) * 100])
	var life3 := LifeSimulation.new()
	_setup(life3)
	life3.new_game(int(db.config("world").get("seed", 12345)))
	var st0 := svc.stats.duplicate(true)
	var tick := _step_real(life3, minutes * 60.0)
	var d_sent := int(svc.stats["sent"]) - int(st0["sent"])
	_say("Gesendet %d (%.1f/min) · angenommen %d · abgelehnt %d · Fehler %s · Ø Antwortzeit %.1f s · max %.1f s" % [d_sent, d_sent / maxf(minutes, 0.01),
		int(life3.ctx.ai.local["accepted"]), int(life3.ctx.ai.local["rejected"]), str(svc.stats["by_code"]), svc.avg_latency_ms() / 1000.0, int(svc.stats["latency_max_ms"]) / 1000.0])
	_say("Anlässe %s · Ablehnungen nach Stufe %s · Simulationstakt Ø %.2f ms" % [str(life3.ctx.ai.local["by_trigger"]), str(life3.ctx.ai.local["by_stage"]), tick])
	_say("Welt: %d lebend, Prüfung %s" % [int(life3.population_summary()["alive"]), "in Ordnung" if life3.audit().is_empty() else str(life3.audit().slice(0, 3))])
	for e in life3.ctx.ai.recent.slice(maxi(0, life3.ctx.ai.recent.size() - 8)):
		_say("  Anfrage %d #%d %s: %s → %s" % [int(e["id"]), int(e["actor"]), e["kind"], e["reason"], e["outcome"]])
	if svc.loaded_models.size() > 0:
		_say("Geladen laut /api/ps: %s" % str(svc.loaded_models))
	# 4/5 Unterbrechung
	if _arg("unterbrechung", "") == "ja":
		_say("\n== 4 Dienst unterbrechen ==")
		_say(">>> Bitte JETZT Ollama beenden (Windows: Ollama-Symbol in der Taskleiste → Quit Ollama). Warte bis zu 3 min …")
		var t0 := Time.get_ticks_msec()
		var ok4 := _step_until(life3, func(): return svc.status == "nicht_erreichbar", 180.0, true)
		_say("Erkannt: %s nach %.0f s · Meldung: %s · Welt lief weiter: t=%.0f s" % ["ja" if ok4 else "nein", (Time.get_ticks_msec() - t0) / 1000.0, svc.status_message, life3.ctx.now()])
		_say("\n== 5 Dienst wieder verfügbar ==")
		_say(">>> Bitte JETZT Ollama wieder starten. Warte bis zu 5 min …")
		var t1 := Time.get_ticks_msec()
		var rec0 := svc.recoveries
		var ok5 := _step_until(life3, func(): return svc.status == "verbunden" and svc.recoveries > rec0, 300.0, false)
		_say("Wiederhergestellt: %s nach %.0f s" % ["ja" if ok5 else "nein", (Time.get_ticks_msec() - t1) / 1000.0])
		if ok5:
			var acc0 := int(life3.ctx.ai.local["accepted"]) + int(life3.ctx.ai.local["rejected"])
			_step_until(life3, func(): return int(life3.ctx.ai.local["accepted"]) + int(life3.ctx.ai.local["rejected"]) > acc0, 240.0, true)
			_say("Nächste Antwort nach Wiederherstellung verarbeitet: %s" % ("ja" if int(life3.ctx.ai.local["accepted"]) + int(life3.ctx.ai.local["rejected"]) > acc0 else "nein"))
	else:
		_say("\n(4/5 Unterbrechung übersprungen – mit --unterbrechung ausführen.)")
	_say("\nProtokoll (letzte Einträge):")
	for e2 in svc.log.slice(maxi(0, svc.log.size() - 15)):
		_say("  [%s] %s" % [e2["level"], OllamaClient.sanitize(str(e2["text"]), 300)])
	life3.dispose()
	_finish(0)


func _setup(life: LifeSimulation) -> void:
	var sim := Simulation.new()
	var world := VoxelWorld.new()
	var objs := Node3D.new()
	root.add_child(sim)
	root.add_child(world)
	root.add_child(objs)
	sim.initialize()
	sim.set_physics_process(false)
	world.set_physics_process(false)
	life.setup(sim, db, world, objs, svc)


func _world(n: int) -> LifeSimulation:
	var life := LifeSimulation.new()
	_setup(life)
	var seed := int(db.config("world").get("seed", 12345))
	life.build_world(seed)
	life._create_food_sources(seed)
	PopulationSpawner.spawn(life.ctx, n, 4242, life.tree_node.position)
	life.game_ready = true
	for id in life.ctx.creatures:
		life.ctx.creatures[id].behavior_enabled = false
	return life


func _place_near_food(life: LifeSimulation, sc: MindScenarios, cr: Creature) -> void:
	for fid in life.ctx.foods:
		var f: FoodSource = life.ctx.foods[fid]
		if f.available_kg() > 0.3 and sc.place_with_view(life, cr, f.position, 3.0):
			break
	life.ctx.rebuild_spatial_hash()
	Perception.scan(cr, life.ctx)


func _wait_status(ok_states: Array, secs: float) -> bool:
	svc.test_connection()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		svc.poll()
		if svc.status in ok_states and svc.check_pending.is_empty():
			return true
		OS.delay_msec(20)
	return false


func _wait_answer(life: LifeSimulation, cr: Creature, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		life.step(DT)
		if str(cr.ai.get("last", {}).get("status", "")) in ["angenommen", "abgelehnt", "fehlgeschlagen", "verworfen"]:
			return
		OS.delay_msec(15)


func _report_last(cr: Creature) -> void:
	var l: Dictionary = cr.ai.get("last", {})
	_say("Ergebnis: %s · Antwortzeit %.1f s · %s" % [str(l.get("status", "keine Antwort")), int(l.get("latency_ms", 0)) / 1000.0, str(l.get("why", ""))])
	if str(l.get("explanation", "")) != "":
		_say("Modellbegründung (nur Vorschlag): „%s“" % str(l["explanation"]))
	var p: Dictionary = cr.ai.get("plan", {})
	for st in p.get("steps", []):
		_say("  Schritt: %s #%d" % [st["action"], int(st["target"])])


## Echtzeitlauf (60 Hz). Rückgabe: mittlere Simulationszeit je Takt in ms.
func _step_real(life: LifeSimulation, secs: float) -> float:
	var t0 := Time.get_ticks_msec()
	var n := 0
	var us := 0
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		var a := Time.get_ticks_usec()
		life.step(DT)
		us += Time.get_ticks_usec() - a
		n += 1
		var target := t0 + int(n * DT * 1000.0)
		var wait := target - Time.get_ticks_msec()
		if wait > 0:
			OS.delay_msec(wait)
	return us / 1000.0 / maxf(1.0, float(n))


func _step_until(life: LifeSimulation, cond: Callable, secs: float, poke: bool) -> bool:
	var t0 := Time.get_ticks_msec()
	var last_poke := 0
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		_step_real(life, 0.5)
		if poke and Time.get_ticks_msec() - last_poke > 8000:
			last_poke = Time.get_ticks_msec()
			for id in life.ctx.creatures:
				var cr: Creature = life.ctx.creatures[id]
				if cr.alive and not life.ctx.ai.queue.has_actor(id) and life.ctx.ai.request_now(cr, "plan", "Live-Test: Anfrage während Ausfallprüfung")["ok"]:
					break
		if cond.call():
			return true
	return false
