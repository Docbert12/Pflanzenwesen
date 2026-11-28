class_name ModuleRegistry
extends RefCounted
## Register der Simulationsmodule (Alpha 1.1): Anmeldung, Reihenfolge aus Abhängigkeiten, Takt mit
## Zeitmessung je Modul, Speicherabschnitte, Nacharbeit nach dem Laden, Prüfungen.
## Die Reihenfolge ist eine stabile topologische Sortierung: wer von nichts (mehr) abhängt, läuft in
## Anmeldereihenfolge; nach einem Akteur-Modul kommen zuerst weitere bereite Akteur-Module, damit die
## Akteur-Gruppe (Körper → Wahrnehmung → Entscheidung je Wesen) zusammenbleibt. Zyklen, doppelte IDs und unbekannte Abhängigkeiten sind Fehler (resolve() = false).

const WINDOW := 120

var modules: Array = []            # Anmeldereihenfolge
var by_id: Dictionary = {}
var order: Array = []              # Taktreihenfolge (nach resolve)
var groups: Array = []             # [{"per_actor": bool, "modules": Array}] aus `order`
var errors: Array = []
var resolved: bool = false
var timing: Dictionary = {}        # id -> {"calls", "sum_us", "max_us", "last_us", "window": Array, "acc_us"}
var measure: bool = true


func register(m: SimModule) -> bool:
	if m == null or m.id == "":
		errors.append("Modul ohne ID abgewiesen.")
		return false
	if by_id.has(m.id):
		errors.append("Modul '%s' ist doppelt angemeldet." % m.id)
		return false
	modules.append(m)
	by_id[m.id] = m
	timing[m.id] = {"calls": 0, "sum_us": 0, "max_us": 0, "last_us": 0, "window": [], "acc_us": 0}
	resolved = false
	return true


func has(id: String) -> bool:
	return by_id.has(id)


func get_module(id: String) -> SimModule:
	return by_id.get(id, null)


func ids() -> Array:
	var r: Array = []
	for m in order:
		r.append(m.id)
	return r


## Reihenfolge bestimmen. false + errors bei unbekannter Abhängigkeit oder Zyklus.
func resolve() -> bool:
	order.clear()
	groups.clear()
	var ok := true
	for m in modules:
		for d in m.depends_on:
			if not by_id.has(d):
				errors.append("Modul '%s' hängt von unbekanntem Modul '%s' ab." % [m.id, d])
				ok = false
	if not ok:
		return false
	var done := {}
	var remaining: Array = modules.duplicate()
	while not remaining.is_empty():
		var picked: SimModule = null
		var in_actor_group := not order.is_empty() and (order[-1] as SimModule).per_actor
		for m in remaining:
			var ready := true
			for d in m.depends_on:
				if not done.has(d):
					ready = false
					break
			if not ready:
				continue
			# Akteur-Gruppe zusammenhalten: nach einem Akteur-Modul zuerst weitere bereite Akteur-Module
			if in_actor_group and m.per_actor:
				picked = m
				break
			if picked == null:
				picked = m
				if not in_actor_group:
					break
		if picked == null:
			var names: Array = []
			for m in remaining:
				names.append(m.id)
			errors.append("Zyklische Abhängigkeit zwischen Modulen: " + ", ".join(names))
			order.clear()
			return false
		order.append(picked)
		done[picked.id] = true
		remaining.erase(picked)
	for m in order:
		if groups.is_empty() or bool(groups[-1]["per_actor"]) != m.per_actor:
			groups.append({"per_actor": m.per_actor, "modules": []})
		groups[-1]["modules"].append(m)
	resolved = true
	return true


func setup_all(life, ctx: LifeContext) -> void:
	for m in order:
		m.setup(life, ctx)


## Ein Simulationsbild: Module in Reihenfolge; Akteur-Gruppen je lebendem Akteur (IDs aufsteigend).
func tick_all(dt: float, actor_ids: Array, actors: Dictionary, zone: int = SimModule.ZONE_A) -> void:
	for g in groups:
		var mods: Array = g["modules"]
		if not g["per_actor"]:
			for m in mods:
				var t0 := Time.get_ticks_usec() if measure else 0
				m.tick(dt, zone)
				if measure:
					_add(m.id, Time.get_ticks_usec() - t0)
			continue
		for m in mods:
			var t1 := Time.get_ticks_usec() if measure else 0
			m.tick(dt, zone)
			if measure:
				timing[m.id]["acc_us"] = Time.get_ticks_usec() - t1
		for aid in actor_ids:
			var cr: Creature = actors[aid]
			for m in mods:
				if not cr.alive:
					break
				if measure:
					var t2 := Time.get_ticks_usec()
					m.actor_tick(cr, dt)
					timing[m.id]["acc_us"] += Time.get_ticks_usec() - t2
				else:
					m.actor_tick(cr, dt)
		if measure:
			for m in mods:
				_add(m.id, int(timing[m.id]["acc_us"]))


func tick_paused_all() -> void:
	for m in order:
		m.tick_paused()


func _add(id: String, us: int) -> void:
	var t: Dictionary = timing[id]
	t["calls"] += 1
	t["sum_us"] += us
	t["last_us"] = us
	if us > int(t["max_us"]):
		t["max_us"] = us
	var w: Array = t["window"]
	w.append(us)
	if w.size() > WINDOW:
		w.pop_front()


## Zeit je Modul: {id: {"avg_ms", "max_ms", "window_avg_ms", "calls", "share"}} und Summe.
func timing_report() -> Dictionary:
	var total := 0
	for id in timing:
		total += int(timing[id]["sum_us"])
	var rep := {}
	for m in order:
		var t: Dictionary = timing[m.id]
		var ws := 0
		for v in t["window"]:
			ws += int(v)
		rep[m.id] = {"title": m.title, "calls": int(t["calls"]), "avg_ms": float(t["sum_us"]) / maxf(float(t["calls"]), 1.0) / 1000.0,
			"max_ms": float(t["max_us"]) / 1000.0, "window_avg_ms": float(ws) / maxf(float(t["window"].size()), 1.0) / 1000.0,
			"share": float(t["sum_us"]) / maxf(float(total), 1.0)}
	return {"modules": rep, "total_ms": float(total) / 1000.0}


func reset_timing() -> void:
	for id in timing:
		timing[id] = {"calls": 0, "sum_us": 0, "max_us": 0, "last_us": 0, "window": [], "acc_us": 0}


func metrics_all() -> Dictionary:
	var r := {}
	for m in order:
		r[m.id] = m.metrics()
	return r


func audit_all() -> Array:
	var p: Array = []
	for m in order:
		p.append_array(m.audit())
	return p


## Abschnitte aller Module mit Zustand: {id: {"v": n, …}}
func save_sections() -> Dictionary:
	var out := {}
	for mm in order:
		var m: SimModule = mm
		if not m.has_section:
			continue
		var s := m.save_section()
		s["v"] = m.section_version
		out[m.id] = s
	return out


func _by(field: String) -> Array:
	var l: Array = order.duplicate()
	l.sort_custom(func(a, b): return int(a.get(field)) < int(b.get(field)) if int(a.get(field)) != int(b.get(field)) else order.find(a) < order.find(b))
	return l


## Abschnitte prüfen und auf die aktuelle Abschnittsversion heben, OHNE etwas zu laden.
## {"ok", "code", "message", "sections", "notes"}
func prepare_sections(sections: Dictionary) -> Dictionary:
	var out := {}
	var notes: Array = []
	for id in sections:
		if not by_id.has(str(id)):
			return {"ok": false, "code": "unknown_module", "message": "Der Spielstand enthält den Abschnitt '%s' eines Moduls, das dieses Programm nicht kennt. Er wird nicht teilweise geladen." % str(id)}
	for mm in order:
		var m: SimModule = mm
		if not sections.has(m.id):
			if not m.has_section or m.section_optional:
				if m.section_optional:
					notes.append("%s: kein Abschnitt im Spielstand – Startzustand" % m.id)
				continue
			return {"ok": false, "code": "invalid", "message": "Spielstand unvollständig: Abschnitt '%s' fehlt." % m.id}
		var s = sections[m.id]
		if typeof(s) != TYPE_DICTIONARY:
			return {"ok": false, "code": "invalid", "message": "Abschnitt '%s' ist kein JSON-Objekt." % m.id}
		var v := int(s.get("v", 0))
		if v > m.section_version:
			return {"ok": false, "code": "newer_format", "message": "Abschnitt '%s' hat Version %d, dieses Programm kennt nur bis %d." % [m.id, v, m.section_version]}
		if v < 1:
			return {"ok": false, "code": "invalid", "message": "Abschnitt '%s' ohne gültige Version." % m.id}
		if v < m.section_version:
			var r := m.migrate_section(s, v)
			if not r.get("ok", false):
				return {"ok": false, "code": "no_migration", "message": str(r.get("message", ""))}
			s = r["section"]
			notes.append("%s: Abschnitt %d→%d" % [m.id, v, m.section_version])
		out[m.id] = s
	return {"ok": true, "code": "ok", "message": "", "sections": out, "notes": notes}


## Lädt vorbereitete Abschnitte in Ladereihenfolge. {"ok", "code", "message"}
func load_sections(sections: Dictionary) -> Dictionary:
	for mm in _by("load_order"):
		var m: SimModule = mm
		if not sections.has(m.id):
			continue
		var r: Dictionary = m.load_section(sections[m.id])
		if not r.get("ok", false):
			return {"ok": false, "code": str(r.get("code", "invalid")), "message": str(r.get("message", "Abschnitt '%s' nicht ladbar." % m.id))}
	return {"ok": true, "code": "ok", "message": ""}


func after_load_all() -> Array:
	var notes: Array = []
	for mm in _by("after_load_order"):
		var m: SimModule = mm
		notes.append_array(m.after_load())
	return notes


func dispose_all() -> void:
	for m in modules:
		m.dispose()
