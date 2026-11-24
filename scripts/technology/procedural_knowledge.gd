class_name ProceduralKnowledge
extends RefCounted
## Individuelles praktisches Wissen eines Wesens (Prompt 6). Liegt in Creature.tech:
##   objects:    bekannte Gegenstände [id → Wahrnehmung des Wesens, NICHT Simulationsdaten]
##   procedures: bekannte Verfahren   [key → Eintrag]
##   hypotheses: ungeprüfte Ideen (eigene oder Modellvorschläge) – nie automatisch Entdeckung
##
## Verfahrensschlüssel entstehen aus dem, was tatsächlich getan bzw. beobachtet wurde
## (Vorgang + Materialien + Werkzeugform), nicht aus einem Technologiebaum:
##   schlagen:<Kontaktmaterial>:<Werkzeugform>><Zielmaterial>    z. B. schlagen:stone:Stiel+Kopf>copper
##   verbinden:lashing:<Stielmaterial>+<Kopfmaterial>             z. B. verbinden:lashing:wood+stone
##   giessen:<Material>:Tiegel>Form                               z. B. giessen:copper:Tiegel>Form
##
## Erfahrungsstand (aufsteigend): gehört < zugesehen < versucht < erfolgreich.
## Ein Gespräch setzt höchstens „gehört“, Zusehen höchstens „zugesehen“; „versucht“/„erfolgreich“
## entstehen NUR aus eigenen ausgeführten Handlungen.

const LEVELS := ["gehört", "zugesehen", "versucht", "erfolgreich"]
const LEVEL_LABEL := {"": "unbekannt", "gehört": "davon gehört", "zugesehen": "dabei zugesehen", "versucht": "selbst versucht", "erfolgreich": "selbst erfolgreich ausgeführt"}
const ORIGIN_LABEL := {"eigener_versuch": "eigener Versuch", "beobachtung": "Beobachtung", "mitteilung": "Mitteilung (Hörensagen)", "unterricht": "Vorführung (Unterricht)"}


static func default_tech() -> Dictionary:
	return {"objects": {}, "procedures": {}, "hypotheses": [], "next_hyp_id": 1, "experiment_id": 0, "next_experiment_t": 0.0,
		"budget": [], "taught": {}, "offers": [], "watching": {}, "explained": {}, "stats": {"experiments": 0, "successes": 0, "failures": 0},
		"failed_plans": {}}


static func level_index(lv: String) -> int:
	return LEVELS.find(lv)


static func level(cr: Creature, key: String) -> String:
	var e: Dictionary = cr.tech["procedures"].get(key, {})
	return str(e.get("level", ""))


static func knows(cr: Creature, key: String) -> bool:
	return cr.tech["procedures"].has(key)


## Schlüsselbau
static func strike_key(contact_material: String, tool_form: String, target_material: String) -> String:
	return "schlagen:%s:%s>%s" % [contact_material, tool_form, target_material]


static func lashing_key(handle_material: String, head_material: String) -> String:
	return "verbinden:lashing:%s+%s" % [handle_material, head_material]


static func cast_key(material_id: String) -> String:
	return "giessen:%s:Tiegel>Form" % material_id


static func kind_of(key: String) -> String:
	return key.split(":")[0]


static func describe_key(key: String) -> String:
	var p := key.split(":")
	match p[0]:
		"schlagen":
			var tt := p[2].split(">")
			return "Mit %s (%s) auf %s schlagen" % [_mat(p[1]), tt[0], _mat(tt[1]) if tt.size() > 1 else "?"]
		"verbinden":
			var hh := p[2].split("+")
			return "Stiel (%s) und Kopf (%s) mit Fasern umwickeln" % [_mat(hh[0]), _mat(hh[1]) if hh.size() > 1 else "?"]
		"giessen":
			return "%s im Tiegel erhitzen und in eine Form gießen" % _mat(p[1])
	return key


static func _mat(m: String) -> String:
	return {"stone": "Stein", "wood": "Holz", "copper": "Kupfer", "plant_fiber": "Fasern", "plant_tissue": "Pflanzengewebe", "ceramic": "Keramik", "Hand": "bloßer Hand", "soil": "Erde"}.get(m, m)


## Schrittvorlage (Rollen statt IDs) je Verfahrensart.
static func template_steps(key: String) -> Array:
	match kind_of(key):
		"schlagen":
			return [{"op": "equip", "role": "tool"}, {"op": "deform", "role": "target"}]
		"verbinden":
			return [{"op": "connect", "roles": ["handle", "head", "fiber"]}]
		"giessen":
			return [{"op": "heat", "roles": ["crucible", "heater"]}, {"op": "wait_molten", "role": "crucible"}, {"op": "pour", "roles": ["crucible", "mold"]}]
	return []


static func prerequisites(key: String) -> Dictionary:
	var p := key.split(":")
	match p[0]:
		"schlagen":
			var tt := p[2].split(">")
			return {"Fähigkeit": "greifen", "Werkzeug": "%s (%s)" % [_mat(p[1]), tt[0]], "Ziel": _mat(tt[1]) if tt.size() > 1 else "?"}
		"verbinden":
			var hh := p[2].split("+")
			return {"Fähigkeit": "greifen", "Stiel": "Stab aus %s" % _mat(hh[0]), "Kopf": "kompaktes Stück %s" % (_mat(hh[1]) if hh.size() > 1 else "?"), "Bindemittel": "Pflanzenfasern"}
		"giessen":
			return {"Fähigkeit": "greifen", "Material": _mat(p[1]), "Behälter": "Tiegel mit Griff", "Wärme": "Heizung", "Form": "Gussform"}
	return {}


## Eintrag holen oder anlegen (ohne Erfahrungsstand – den setzen nur die record_*-Funktionen).
static func _entry(ctx: LifeContext, cr: Creature, key: String, origin: String) -> Dictionary:
	var procs: Dictionary = cr.tech["procedures"]
	if not procs.has(key):
		var cap := int(ctx.tc("knowledge").get("procedures_max", 16))
		if procs.size() >= cap:
			# schwächsten Eintrag (niedrigster Stand, älteste Nutzung) verdrängen – nie den einzigen Erfolg
			var worst := ""
			var worst_score := 1.0e18
			for k in procs:
				var sc := float(level_index(str(procs[k]["level"]))) * 1.0e6 + float(procs[k]["last_t"])
				if sc < worst_score:
					worst_score = sc
					worst = k
			procs.erase(worst)
		procs[key] = {"key": key, "label": describe_key(key), "origin": origin, "first_t": ctx.now(), "last_t": ctx.now(), "level": "",
			"prerequisites": prerequisites(key), "steps": template_steps(key), "materials": [], "own": {"attempts": 0, "successes": 0, "last": ""},
			"observed": {"count": 0, "successes": 0, "by": []}, "heard": {"count": 0, "sources": [], "origins": []},
			"confidence": 0.0, "versions": [], "experiments": []}
		_version(ctx, procs[key], "angelegt (%s)" % ORIGIN_LABEL.get(origin, origin), cr.id)
	return procs[key]


static func _version(ctx: LifeContext, e: Dictionary, change: String, by: int) -> void:
	var v: Array = e["versions"]
	v.append({"v": v.size() + 1 if v.is_empty() else int(v[-1]["v"]) + 1, "t": ctx.now(), "change": change, "by": by})
	while v.size() > int(ctx.tc("knowledge").get("versions_max", 8)):
		v.pop_front()


static func _raise(ctx: LifeContext, cr: Creature, e: Dictionary, lv: String, why: String) -> void:
	if level_index(lv) > level_index(str(e["level"])):
		var old := str(e["level"])
		e["level"] = lv
		_version(ctx, e, "Erfahrungsstand %s → %s (%s)" % [LEVEL_LABEL.get(old, old), LEVEL_LABEL[lv], why], cr.id)
	e["last_t"] = ctx.now()
	_update_confidence(e)


## Sicherheit (0..1): eigene Versuche zählen voll, beobachtete fremde halb, Hörensagen gering und
## NUR je unabhängiger Ursprungsquelle (Weitererzählen derselben Quelle zählt einmal).
static func _update_confidence(e: Dictionary) -> void:
	var own: Dictionary = e["own"]
	var obs: Dictionary = e["observed"]
	var heard_ind := float((e["heard"]["origins"] as Array).size())
	var s := float(own["successes"]) + 0.5 * float(obs["successes"]) + 0.15 * heard_ind
	var n := float(own["attempts"]) + 0.5 * float(obs["count"]) + 0.15 * heard_ind
	e["confidence"] = clampf((s + 0.5) / (n + 1.0) * minf(1.0, n / 2.0), 0.0, 1.0)


## Eigener ausgeführter Versuch (einzige Quelle für „versucht“/„erfolgreich“).
static func record_own(ctx: LifeContext, cr: Creature, key: String, success: bool, materials: Array, experiment_id: int, note: String) -> Dictionary:
	var e := _entry(ctx, cr, key, "eigener_versuch")
	var own: Dictionary = e["own"]
	own["attempts"] = int(own["attempts"]) + 1
	if success:
		own["successes"] = int(own["successes"]) + 1
	own["last"] = ("Erfolg: " if success else "Fehlschlag: ") + note
	for m in materials:
		if not (m in e["materials"]):
			e["materials"].append(m)
			_version(ctx, e, "Materialbereich erweitert: %s" % _mat(str(m)), cr.id)
	if experiment_id != 0:
		e["experiments"].append(experiment_id)
		while e["experiments"].size() > 6:
			e["experiments"].pop_front()
	_raise(ctx, cr, e, "erfolgreich" if success else "versucht", "eigener Versuch #%d" % experiment_id)
	return e


## Tatsächlich wahrgenommener fremder Versuch / Vorführung (höchstens „zugesehen“).
static func record_observed(ctx: LifeContext, cr: Creature, key: String, by: int, success: bool, demo: bool) -> Dictionary:
	var e := _entry(ctx, cr, key, "unterricht" if demo else "beobachtung")
	var obs: Dictionary = e["observed"]
	obs["count"] = int(obs["count"]) + 1
	if success:
		obs["successes"] = int(obs["successes"]) + 1
	if not (by in obs["by"]):
		obs["by"].append(by)
		while obs["by"].size() > 6:
			obs["by"].pop_front()
	_raise(ctx, cr, e, "zugesehen", ("Vorführung von #%d" if demo else "beobachtet bei #%d") % by)
	return e


## Mitteilung (strukturierter Gesprächsinhalt): höchstens „gehört“. origin_creature = ursprüngliche
## Quelle (bei Weitererzählen der erste Erzähler), zählt je Ursprung nur einmal.
static func record_heard(ctx: LifeContext, cr: Creature, key: String, speaker: int, origin_creature: int, speaker_level: String) -> Dictionary:
	var e := _entry(ctx, cr, key, "mitteilung")
	var h: Dictionary = e["heard"]
	h["count"] = int(h["count"]) + 1
	h["sources"].append({"speaker": speaker, "origin": origin_creature, "speaker_level": speaker_level, "t": ctx.now()})
	while h["sources"].size() > 6:
		h["sources"].pop_front()
	if not (origin_creature in h["origins"]):
		h["origins"].append(origin_creature)
	_raise(ctx, cr, e, "gehört", "Mitteilung von #%d" % speaker)
	return e


## Hypothese ablegen (ungeprüft). source: "eigene Idee", "Modell (Ollama)", "Modell (SIMULIERT)".
static func add_hypothesis(ctx: LifeContext, cr: Creature, h: Dictionary) -> Dictionary:
	var hs: Array = cr.tech["hypotheses"]
	h["id"] = int(cr.tech["next_hyp_id"])
	cr.tech["next_hyp_id"] = int(h["id"]) + 1
	h["t"] = ctx.now()
	h["status"] = "ungeprüft"
	hs.append(h)
	while hs.size() > int(ctx.tc("experiments").get("model_hypotheses_max", 4)) + 4:
		hs.pop_front()
	return h


static func hypothesis(cr: Creature, hid: int) -> Dictionary:
	for h in cr.tech["hypotheses"]:
		if int(h["id"]) == hid:
			return h
	return {}


## Wahrnehmung eines Gegenstands (Aussehen, Form, Größe) – das, was ein Wesen SIEHT.
static func see_object(ctx: LifeContext, cr: Creature, id: int, d: float) -> void:
	var objs: Dictionary = cr.tech["objects"]
	var top := ConstructionSystem.top_id(ctx, id)
	if top == 0:
		return
	var e: Dictionary = objs.get(top, {})
	var parts: Array = []
	for p in ConstructionSystem.parts_of(ctx, top):
		parts.append({"id": p.id, "aussehen": p.material_id, "form": p.shape, "rolle": p.role})
	e.merge({"id": top, "seen_t": ctx.now(), "d": snappedf(d, 0.1), "parts": parts, "assembly": ctx.assemblies.has(top)}, true)
	var mp: MaterialPiece = ctx.material_pieces.get(top, null)
	if mp != null:
		e["aussehen"] = mp.material_id
		e["form"] = mp.shape
		e["groesse_m"] = snappedf(mp.size_m, 0.01)
	else:
		e["aussehen"] = "Verbund"
		e["form"] = "Verbund"
	# Glühen und Schmelze sind sichtbar; Wärmestrahlung in der Nähe spürbar
	var t := ConstructionSystem.max_temperature_k(ctx, top)
	var tcfg: Dictionary = ctx.tc("temperature")
	if t >= 798.0 or (d <= float(tcfg.get("radiant_feel_m", 1.5)) and t >= float(tcfg.get("radiant_feel_k", 500.0))):
		e["temperatur"] = ToolUseSystem.object_temperature_category(ctx, top)
		e["temperatur_t"] = ctx.now()
	elif e.has("temperatur") and ctx.now() - float(e.get("temperatur_t", 0.0)) > 120.0:
		e["temperatur"] = str(e["temperatur"]) + " (früher)"
	objs[top] = e
	var cap := int(ctx.tc("experiments").get("known_objects_max", 24))
	if objs.size() > cap:
		var oldest := 0
		var ot := 1.0e18
		for k in objs:
			if float(objs[k]["seen_t"]) < ot and int(k) != top:
				ot = float(objs[k]["seen_t"])
				oldest = int(k)
		objs.erase(oldest)


## Untersuchen (inspect_object): Härte durch Klopfen, Gewicht durch Anheben (falls greifbar),
## Temperatur durch vorsichtiges Annähern/Berühren. Nur Kategorien – keine exakten Werte.
static func inspect(ctx: LifeContext, cr: Creature, id: int) -> Dictionary:
	var top := ConstructionSystem.top_id(ctx, id)
	see_object(ctx, cr, top, ctx.distance_xz(cr.position, ctx.position_of(top)))
	var e: Dictionary = cr.tech["objects"][top]
	var hmax := 0.0
	for p in ConstructionSystem.parts_of(ctx, top):
		hmax = maxf(hmax, (p as MaterialPiece).material().w("hardness", 1.0))
	e["haerte"] = "hart" if hmax >= 5.0 else ("mittel" if hmax >= 1.5 else "weich")
	var plastic := false
	for p in ConstructionSystem.parts_of(ctx, top):
		if (p as MaterialPiece).material().is_plastic():
			plastic = true
	e["klang"] = "dumpf, gibt etwas nach" if plastic else ("hell, hart" if hmax >= 5.0 else "dumpf")
	var m := ConstructionSystem.mass_of(ctx, top)
	var g := ToolUseSystem.check_grasp(ctx, cr, top)
	if g.ok or g.code == "hands_full":
		e["gewicht"] = "leicht" if m < 0.15 else ("mittel" if m < 0.6 else "schwer")
	elif g.code == "too_heavy":
		e["gewicht"] = "zu schwer"
	e["temperatur"] = ToolUseSystem.object_temperature_category(ctx, top)
	e["temperatur_t"] = ctx.now()
	e["untersucht_t"] = ctx.now()
	if ctx.assemblies.has(top):
		var a: Assembly = ctx.assemblies[top]
		var cs: Array = []
		for c in a.connections:
			cs.append("%s, %s" % [ConnectionDefinition.label(str(c["method"])), "fest" if float(c["wear"]) < float(ctx.tc("perception").get("visible_joint_wear", 0.5)) else "locker"])
		e["verbindungen"] = cs
	return e


static func known_object(cr: Creature, id: int) -> Dictionary:
	return cr.tech["objects"].get(id, {})


static func to_save(tech: Dictionary) -> Dictionary:
	var d := tech.duplicate(true)
	var objs := {}
	for k in tech["objects"]:
		objs[str(k)] = tech["objects"][k]
	d["objects"] = objs
	var taught := {}
	for k in tech["taught"]:
		taught[str(k)] = tech["taught"][k]
	d["taught"] = taught
	return d


static func from_save(src: Dictionary) -> Dictionary:
	var t := default_tech()
	if src.is_empty():
		return t
	for k in src.get("objects", {}):
		var o: Dictionary = src["objects"][k].duplicate(true)
		o["id"] = int(o.get("id", int(k)))
		t["objects"][int(k)] = o
	t["procedures"] = src.get("procedures", {}).duplicate(true)
	for key in t["procedures"]:
		var e: Dictionary = t["procedures"][key]
		var ob: Array = []
		for v in e["observed"].get("by", []):
			ob.append(int(v))
		e["observed"]["by"] = ob
		var og: Array = []
		for v in e["heard"].get("origins", []):
			og.append(int(v))
		e["heard"]["origins"] = og
		var ex: Array = []
		for v in e.get("experiments", []):
			ex.append(int(v))
		e["experiments"] = ex
	t["hypotheses"] = src.get("hypotheses", []).duplicate(true)
	for h in t["hypotheses"]:
		h["id"] = int(h["id"])
		h["experiment_id"] = int(h.get("experiment_id", 0))
	t["next_hyp_id"] = int(src.get("next_hyp_id", 1))
	t["experiment_id"] = int(src.get("experiment_id", 0))
	t["next_experiment_t"] = float(src.get("next_experiment_t", 0.0))
	t["budget"] = src.get("budget", []).duplicate(true)
	for k in src.get("failed_plans", {}):
		t["failed_plans"][str(k)] = float(src["failed_plans"][k])
	for k in src.get("taught", {}):
		t["taught"][int(k)] = src["taught"][k].duplicate(true)
	t["offers"] = src.get("offers", []).duplicate(true)
	for o in t["offers"]:
		o["from"] = int(o["from"])
	t["watching"] = src.get("watching", {}).duplicate(true)
	if t["watching"].has("teacher"):
		t["watching"]["teacher"] = int(t["watching"]["teacher"])
	t["explained"] = src.get("explained", {}).duplicate(true)
	t["stats"] = src.get("stats", t["stats"]).duplicate(true)
	return t
